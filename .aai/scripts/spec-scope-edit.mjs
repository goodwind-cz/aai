#!/usr/bin/env node
// spec-scope-edit.mjs — orchestrator-level review-scope edits (CHANGE-0120
// cheap-ticks, AC-002).
//
// WHY THIS EXISTS
// In the motivating ride, excluding the user's unrelated requirements.txt /
// .gitattributes edits from the review scope ran a FULL re-Planning agent. That
// is a mechanical list edit, not a planning decision — but only for paths the
// ride never touched. This tool draws exactly that line and enforces it:
//
//   path NOT in the ride's diff  -> a bookkeeping edit this tool may make
//   path IS in the ride's diff   -> a CONTENT decision; REFUSED, go to Planning
//
// The refusal is the safety property. A path the ride actually changed is
// review-relevant by definition, and quietly dropping it from the review scope
// would be the tool laundering work past the reviewer. So the refusal applies
// to `--include` as well as `--exclude`: this tool only ever moves paths the
// ride did not touch, and the diff probe failing at all is also a refusal
// (fail-closed — never fall open to "no diff, therefore safe").
//
// The "ride's diff" is the UNION of: <base>...HEAD, staged, unstaged, and
// untracked files. Broader is safer here — every extra path can only cause a
// refusal, never permit an edit.
//
// SCOPE OF THE EDIT: the `- Inline review scope:` bullet under
// `## Isolation and review` (SPEC_TEMPLATE), including its wrapped
// continuation lines. Nothing else in the spec is touched — not the AC table,
// not the freeze marker, not the frontmatter.
//
// Usage:
//   node .aai/scripts/spec-scope-edit.mjs --spec <path>
//        (--include <path> | --exclude <path>)
//        [--base-ref <ref>] [--json] [--dry-run]
//
// Exit codes (closed contract):
//   0 applied, OR already in the requested state (idempotent no-op success)
//   2 usage error (missing/unknown flag, neither or both of include/exclude)
//   3 REFUSED — the path appears in the ride's diff; this is a content
//     decision, re-plan instead. Nothing written, no event.
//   4 REFUSED — structural: the spec is unreadable, or carries no
//     `- Inline review scope:` bullet, or the git diff probe failed
//   1 internal error (unexpected exception; nothing was written)
//
// An APPLIED edit appends a `spec_scope_edited` audit line to
// docs/ai/EVENTS.jsonl. A no-op does NOT — idempotence covers the ledger too.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { normalizeNewlines, parseFrontmatter, toPosix } from './lib/docs-model.mjs';

const ROOT = process.cwd();
const WRAP_COLS = 76;

function usage() {
  console.error(
    'Usage: spec-scope-edit --spec <path> (--include <p> | --exclude <p>)\n'
    + '                      [--base-ref <ref>] [--json] [--dry-run]\n'
    + '  Includes/excludes ONE path in a frozen spec\'s review-scope list.\n'
    + '  REFUSES any path the ride\'s own diff touched (that is a content\n'
    + '  decision — re-plan instead). Edits only the review-scope bullet.\n'
    + '  Exit codes:\n'
    + '  0 applied, or already in the requested state (idempotent no-op)\n'
    + '  2 usage error\n'
    + '  3 REFUSED - the path is in the ride diff; nothing written\n'
    + '  4 REFUSED - structural (no review-scope bullet, unreadable spec, or\n'
    + '    the git diff probe failed); nothing written\n'
    + '  1 internal error',
  );
}

function fail(msg) {
  console.error(`spec-scope-edit: ${msg}`);
  usage();
  process.exit(2);
}

function refuse(code, msg, json) {
  if (json) console.log(JSON.stringify({ ok: false, refused: true, exit: code, reason: msg }, null, 2));
  else console.error(`spec-scope-edit: REFUSED — ${msg}`);
  process.exit(code);
}

function parseArgs(argv) {
  const args = { spec: null, include: null, exclude: null, baseRef: 'main', json: false, dryRun: false };
  const need = (i, flag) => {
    const v = argv[i];
    if (v === undefined || v.startsWith('--')) fail(`${flag} needs a value`);
    return v;
  };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--json') args.json = true;
    else if (tok === '--dry-run') args.dryRun = true;
    else if (tok === '--spec') args.spec = need(++i, '--spec');
    else if (tok === '--include') args.include = need(++i, '--include');
    else if (tok === '--exclude') args.exclude = need(++i, '--exclude');
    else if (tok === '--base-ref') args.baseRef = need(++i, '--base-ref');
    else if (tok === '-h' || tok === '--help') { usage(); process.exit(2); }
    else fail(`unknown flag: ${tok}`);
  }
  if (!args.spec) fail('missing --spec');
  if (!args.include && !args.exclude) fail('exactly one of --include / --exclude is required');
  if (args.include && args.exclude) fail('--include and --exclude are mutually exclusive');
  return args;
}

// rideDiffPaths(baseRef) -> Set<string> | null (null == probe failed).
// The union of committed, staged, unstaged and untracked changes. Any single
// git invocation failing makes the WHOLE probe fail: a partial diff would
// under-report and turn a refusal into a permitted edit.
export function rideDiffPaths(baseRef, cwd = ROOT) {
  const run = (argv) => execFileSync('git', argv, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const out = new Set();
  try {
    // Fail fast on an unusable base ref rather than letting `git diff` fall
    // back to some other interpretation of the argument.
    run(['rev-parse', '--verify', '--quiet', `${baseRef}^{commit}`]);
    const batches = [
      run(['diff', '--name-only', `${baseRef}...HEAD`]),
      run(['diff', '--name-only']),
      run(['diff', '--name-only', '--cached']),
      run(['ls-files', '--others', '--exclude-standard']),
    ];
    for (const b of batches) {
      for (const l of b.split('\n')) {
        const t = l.trim();
        if (t) out.add(toPosix(t));
      }
    }
  } catch {
    return null;
  }
  return out;
}

// touchedByRide(target, diff) — exact match, or the target is a DIRECTORY
// prefix of a changed file, or a changed file is a directory prefix of the
// target. All three directions are treated as "touched" (fail-closed).
export function touchedByRide(target, diff) {
  const t = toPosix(target).replace(/\/+$/, '');
  for (const d of diff) {
    if (d === t || d.startsWith(`${t}/`) || t.startsWith(`${d}/`)) return true;
  }
  return false;
}

// --- the review-scope bullet -------------------------------------------------

// findScopeBlock(norm) -> { start, end, label, value } | null
// `start`/`end` bound the bullet AND its wrapped continuation lines (indented
// lines that are neither blank, nor a new `- ` bullet, nor a heading).
export function findScopeBlock(norm) {
  const lines = norm.split('\n');
  const idx = lines.findIndex((l) => /^-\s*Inline review scope\b[^\n:]*:/.test(l));
  if (idx < 0) return null;
  const m = lines[idx].match(/^(-\s*Inline review scope\b[^\n:]*:)(.*)$/);
  const parts = [m[2]];
  let end = idx + 1;
  while (end < lines.length) {
    const l = lines[end];
    if (l.trim() === '' || /^\s*[-*]\s/.test(l) || /^#{1,6}\s/.test(l) || !/^\s+\S/.test(l)) break;
    parts.push(l);
    end += 1;
  }
  return { start: idx, end, label: m[1], value: parts.join(' ') };
}

// parseScopeItems(value) -> [path]. Comma-separated, order-preserving,
// de-duplicated; template placeholders (`<...>`) are dropped.
export function parseScopeItems(value) {
  const out = [];
  for (const raw of String(value).split(',')) {
    const t = raw.replace(/\s+/g, ' ').trim();
    if (t === '' || (t.startsWith('<') && t.endsWith('>'))) continue;
    if (!out.includes(t)) out.push(t);
  }
  return out;
}

// renderScopeBlock(label, items) -> [line] — the bullet re-wrapped at
// WRAP_COLS with a two-space continuation indent (the corpus convention).
export function renderScopeBlock(label, items) {
  if (items.length === 0) return [`${label} (none)`];
  const lines = [];
  let cur = label;
  for (let i = 0; i < items.length; i += 1) {
    const piece = items[i] + (i < items.length - 1 ? ',' : '');
    if (`${cur} ${piece}`.length > WRAP_COLS && cur !== label) {
      lines.push(cur);
      cur = `  ${piece}`;
    } else {
      cur = `${cur} ${piece}`;
    }
  }
  lines.push(cur);
  return lines;
}

function main() {
  const args = parseArgs(process.argv);
  const op = args.include ? 'include' : 'exclude';
  const target = toPosix(args.include ?? args.exclude);
  const abs = path.isAbsolute(args.spec) ? args.spec : path.join(ROOT, args.spec);

  let raw;
  try {
    raw = fs.readFileSync(abs, 'utf8');
  } catch {
    refuse(4, `spec not found or unreadable: "${args.spec}"`, args.json);
    return;
  }
  const crlf = raw.includes('\r\n');
  const norm = normalizeNewlines(raw);
  const block = findScopeBlock(norm);
  if (!block) {
    refuse(4, `"${args.spec}" carries no "- Inline review scope:" bullet (expected under "## Isolation and review") — nothing this tool may edit`, args.json);
    return;
  }

  // The gate. Probed BEFORE any content work so a refusal can never race a
  // partial edit.
  const diff = rideDiffPaths(args.baseRef);
  if (diff === null) {
    refuse(4, `the git diff probe failed for base ref "${args.baseRef}" — refusing rather than assuming the ride touched nothing`, args.json);
    return;
  }
  if (touchedByRide(target, diff)) {
    refuse(3, `"${target}" appears in this ride's diff (base ${args.baseRef}) — moving a path the ride actually changed is a CONTENT decision, not bookkeeping: re-plan instead`, args.json);
    return;
  }

  const items = parseScopeItems(block.value);
  const present = items.includes(target);
  const next = op === 'include'
    ? (present ? items : [...items, target])
    : items.filter((p) => p !== target);
  const changed = op === 'include' ? !present : present;

  const report = {
    ok: true, spec: args.spec, op, target, base_ref: args.baseRef, changed, dry_run: args.dryRun, scope: next,
  };

  if (changed && !args.dryRun) {
    const lines = norm.split('\n');
    lines.splice(block.start, block.end - block.start, ...renderScopeBlock(block.label, next));
    const content = lines.join('\n');
    // Atomic: stage the complete document beside the target, then rename.
    const tmp = `${abs}.spec-scope-edit.tmp`;
    fs.writeFileSync(tmp, crlf ? content.replace(/\n/g, '\r\n') : content);
    fs.renameSync(tmp, abs);

    const id = parseFrontmatter(norm)?.id ?? args.spec;
    const appender = path.join(path.dirname(fileURLToPath(import.meta.url)), 'append-event.mjs');
    try {
      execFileSync(process.execPath, [appender, '--event', 'spec_scope_edited',
        '--ref', String(id), '--op', op, '--target', target,
        '--base-ref', args.baseRef, '--spec', args.spec], { cwd: ROOT, stdio: 'ignore' });
      report.event = 'spec_scope_edited';
    } catch {
      // NOTE (degrade-with-NOTE): the edit is on disk; only the audit line
      // failed. An unaudited scope edit is exactly what a reviewer must know.
      console.error('spec-scope-edit: NOTE — the scope was edited but the spec_scope_edited audit event could not be appended');
      report.event = null;
    }
  }

  if (args.json) console.log(JSON.stringify(report, null, 2));
  else if (!changed) console.log(`spec-scope-edit: "${target}" is already ${op === 'include' ? 'in' : 'out of'} the review scope of ${args.spec} — no write`);
  else if (args.dryRun) console.log(`spec-scope-edit: DRY RUN — would ${op} "${target}" (review scope would become: ${next.join(', ') || '(none)'})`);
  else console.log(`spec-scope-edit: ${op}d "${target}" in ${args.spec} (review scope: ${next.join(', ') || '(none)'})`);
  process.exit(0);
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  try {
    main();
  } catch (err) {
    console.error(`spec-scope-edit: internal error: ${err && err.stack ? err.stack : err}`);
    process.exit(1);
  }
}
