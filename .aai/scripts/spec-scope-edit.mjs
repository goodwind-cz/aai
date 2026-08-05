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
//     `- Inline review scope:` bullet, or that bullet yields NO parsable path
//     entries (a list shape this tool cannot read — refusing beats reporting a
//     no-op success), or the git diff probe failed
//   1 internal error (unexpected exception; nothing was written)
//
// PATH SPELLING: the target and every diff/scope entry are compared through
// ONE normalized repo-relative posix key, so `./x`, `a/../x`, `.//x` and an
// absolute in-repo path are the same path — no spelling launders a
// ride-touched file past the exit-3 refusal. Backticks and trailing `(note)`
// annotations are ignored for comparison and PRESERVED on rewrite.
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
  // -c core.quotePath=false on EVERY probe: with git's default quoting a
  // non-ASCII path comes back C-quoted ("p\305\231..."), never matches the
  // normalized target, and a ride-touched file slips past the exit-3 gate
  // (re-validation finding R1 — the exact laundering class this tool exists
  // to refuse).
  const run = (argv) => execFileSync('git', ['-c', 'core.quotePath=false', ...argv], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
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

// normalizeRelPath(p) — the ONE spelling every comparison in this file uses.
// `./x`, `a/../x`, `.//x` and an absolute in-repo path all collapse to the same
// repo-relative posix key. Without this the refusal below compares raw strings,
// and a laundered spelling (`./committed.js` for `committed.js`) walks straight
// past the gate that exists to stop exactly that.
// realish(p) — p with its existing prefix resolved through symlinks. A repo
// reached via a symlinked prefix (every macOS mktemp root is one: /var ->
// /private/var) otherwise makes an ABSOLUTE spelling of an in-repo file look
// like a path outside the repo, which is exactly the refusal-bypass again.
const realCache = new Map();
function realish(p) {
  if (realCache.has(p)) return realCache.get(p);
  let out = p;
  try {
    out = fs.realpathSync(p);
  } catch {
    try { out = path.join(fs.realpathSync(path.dirname(p)), path.basename(p)); } catch { out = p; }
  }
  realCache.set(p, out);
  return out;
}

export function normalizeRelPath(p, root = ROOT) {
  const s = String(p).trim();
  if (s === '') return '';
  const bases = [...new Set([root, realish(root)])];
  const targets = [...new Set([path.resolve(root, s), realish(path.resolve(root, s))])];
  const rels = [];
  for (const b of bases) {
    for (const t of targets) rels.push(toPosix(path.relative(b, t)).replace(/\/+$/, ''));
  }
  // The target IS the repo root.
  if (rels.includes('')) return '';
  // Prefer any spelling that lands INSIDE the repo; a path genuinely outside it
  // keeps its escaping form (deterministic, and it can never match a diff entry).
  return rels.find((r) => !r.startsWith('..')) ?? rels[0];
}

// touchedByRide(target, diff) — exact match, or the target is a DIRECTORY
// prefix of a changed file, or a changed file is a directory prefix of the
// target. All three directions are treated as "touched" (fail-closed).
// BOTH sides are normalized first, so no spelling of a ride-touched path can
// present itself as a different, untouched path.
export function touchedByRide(target, diff, root = ROOT) {
  const t = normalizeRelPath(target, root);
  // The target resolved to the repo root itself: every diff entry is inside it.
  // eslint-disable-next-line no-unused-vars
  if (t === '') { for (const _ of diff) return true; return false; }
  for (const raw of diff) {
    const d = normalizeRelPath(raw, root);
    if (d === '') continue;
    if (d === t || d.startsWith(`${t}/`) || t.startsWith(`${d}/`)) return true;
  }
  return false;
}

// --- the review-scope bullet -------------------------------------------------

// The corpus writes this bullet in TWO shapes, and both must be first class:
//
//   INLINE (82/114)   - Inline review scope: a.mjs, b.sh
//                       (optionally wrapped onto indented continuation lines,
//                        optionally with `backticked` entries — 24 specs)
//   NESTED (30/114)   - Inline review scope (explicit paths):
//                         - a.mjs (new)
//                         - b.sh
//
// Reading only the inline shape made the nested one parse as EMPTY: `--exclude`
// reported "already out of scope" and exited 0 without editing or auditing, and
// `--include` wrote onto the LABEL line and left the child list dangling.

// findScopeBlock(norm) -> { start, end, label, style, indent, value, items } | null
// `start`/`end` bound the whole block: the bullet, its wrapped continuation
// lines, AND (nested shape) its indented child bullets. `items` carries each
// entry in its ORIGINAL spelling — the rewrite preserves it.
export function findScopeBlock(norm) {
  const lines = norm.split('\n');
  const idx = lines.findIndex((l) => /^-\s*Inline review scope\b[^\n:]*:/.test(l));
  if (idx < 0) return null;
  const m = lines[idx].match(/^(-\s*Inline review scope\b[^\n:]*:)(.*)$/);

  // Wrapped continuation lines of the INLINE shape. This loop stops at the
  // first indented bullet, which is precisely where the nested shape starts.
  const parts = [m[2]];
  let end = idx + 1;
  while (end < lines.length) {
    const l = lines[end];
    if (l.trim() === '' || /^\s*[-*]\s/.test(l) || /^#{1,6}\s/.test(l) || !/^\s+\S/.test(l)) break;
    parts.push(l);
    end += 1;
  }
  const value = parts.join(' ');

  // Child bullets of the NESTED shape: a contiguous run of indented `- ` lines
  // at ONE indent level, each of which may itself WRAP onto deeper-indented
  // continuation lines (SPEC-0011/0012/0031/0042 all do). Those continuations
  // must fall inside `end` too — a splice that stopped short of them would
  // leave them dangling under a rewritten list, which is the very corruption
  // this parser exists to prevent. A deeper BULLET sub-list is document
  // structure, not a path, so the run stops there rather than flattening it.
  const children = [];
  let nend = end;
  let indent = null;
  while (nend < lines.length) {
    const l = lines[nend];
    const cm = l.match(/^([ \t]+)[-*][ \t]+(\S.*?)[ \t]*$/);
    if (cm && (indent === null || cm[1] === indent)) {
      if (indent === null) indent = cm[1];
      children.push(cm[2]);
      nend += 1;
      continue;
    }
    const wrap = children.length > 0 ? l.match(/^([ \t]+)(\S.*?)[ \t]*$/) : null;
    if (wrap && wrap[1].length > indent.length && !/^[-*][ \t]/.test(wrap[2]) && !/^#{1,6}\s/.test(wrap[2])) {
      children[children.length - 1] += ` ${wrap[2]}`;
      nend += 1;
      continue;
    }
    break;
  }

  const inlineItems = parseScopeItems(value);
  if (children.length > 0) {
    return {
      start: idx,
      end: nend,
      label: m[1],
      style: 'nested',
      indent: indent ?? '  ',
      value: [value, ...children].join(', '),
      items: dedupeScopeItems([...inlineItems, ...children.flatMap((c) => parseScopeItems(c))]),
    };
  }
  return {
    start: idx, end, label: m[1], style: 'inline', indent: null, value, items: inlineItems,
  };
}

// scopeItemKey(text) -> the normalized identity of a scope entry. Everything
// the corpus decorates an entry with is stripped for COMPARISON only:
//   `path`        -> path   (backticked entries, 24 specs)
//   path (new)    -> path   (the nested shape's trailing annotations)
//   ./path        -> path   (via normalizeRelPath — same laundering as F2)
export function scopeItemKey(text, root = ROOT) {
  let t = String(text).replace(/\s+/g, ' ').trim();
  // Strip surrounding backticks, a trailing `(annotation)` and trailing
  // punctuation ITERATIVELY until stable: `` `p` (new) `` must key as `p`,
  // not `p\`` (review finding — stripping in one fixed order left a stray
  // backtick and reopened the silent-no-op class on 13 corpus specs).
  for (;;) {
    const before = t;
    t = t.replace(/^`+|`+$/g, '').trim();
    t = t.replace(/\s*\([^()]*\)$/, '').trim();
    t = t.replace(/[.,;]+$/, '').trim();
    if (t === before) break;
  }
  return normalizeRelPath(t, root);
}

function dedupeScopeItems(items) {
  const out = [];
  const seen = new Set();
  for (const it of items) {
    const k = scopeItemKey(it);
    if (k === '' || seen.has(k)) continue;
    seen.add(k);
    out.push(it);
  }
  return out;
}

// splitEntries(s) -> [chunk]. Splits on commas that are at the TOP level only:
// a comma inside `backticks` or (parentheses) belongs to the entry, not between
// entries. A blind `.split(',')` turns the real corpus entry
// `` `.aai/scripts/lib/state-core.mjs` (new, extracted) `` into the two junk
// entries "(new" and "extracted)".
function splitEntries(s) {
  const out = [];
  let cur = '';
  let depth = 0;
  let tick = false;
  for (const ch of String(s)) {
    if (ch === '`') tick = !tick;
    else if (!tick && (ch === '(' || ch === '[')) depth += 1;
    else if (!tick && (ch === ')' || ch === ']')) depth = Math.max(0, depth - 1);
    else if (!tick && depth === 0 && ch === ',') { out.push(cur); cur = ''; continue; }
    cur += ch;
  }
  out.push(cur);
  return out;
}

// parseScopeItems(value) -> [entry]. Comma-separated, order-preserving,
// de-duplicated by scopeItemKey; template placeholders (`<...>`, bare or
// backticked) and bare annotations that carry no path are dropped. Entries keep
// their ORIGINAL spelling so a rewrite can put them back exactly as the spec
// author wrote them.
export function parseScopeItems(value) {
  const out = [];
  for (const raw of splitEntries(value)) {
    const t = raw.replace(/\s+/g, ' ').trim();
    if (t === '') continue;
    const bare = t.replace(/^`+|`+$/g, '').trim();
    if (bare === '' || (bare.startsWith('<') && bare.endsWith('>'))) continue;
    out.push(t);
  }
  return dedupeScopeItems(out);
}

// renderScopeBlock(block, items) -> [line] — the block re-emitted in ITS OWN
// shape. A nested block stays a label plus a child list at the original indent
// (rewriting it as an inline list is what corrupted the doc); an inline block
// is re-wrapped at WRAP_COLS with a two-space continuation indent.
export function renderScopeBlock(block, items) {
  const { label } = block;
  if (items.length === 0) return [`${label} (none)`];
  if (block.style === 'nested') {
    return [label, ...items.map((it) => `${block.indent}- ${it}`)];
  }
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
  const spelled = toPosix(args.include ?? args.exclude);
  // Everything downstream — the diff refusal, the membership test, the entry
  // written into the spec, the audit line — uses the ONE normalized spelling.
  const target = normalizeRelPath(spelled) || spelled;
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
    const as = spelled === target ? '' : ` (spelled "${spelled}")`;
    refuse(3, `"${target}"${as} appears in this ride's diff (base ${args.baseRef}) — moving a path the ride actually changed is a CONTENT decision, not bookkeeping: re-plan instead`, args.json);
    return;
  }

  const items = block.items;
  // A bullet that EXISTS but yields no parsable entry means this tool did not
  // understand the shape it is looking at. Reporting "already out of scope" (a
  // success!) is the one outcome that must never happen: refuse, so an
  // unreadable list is visible instead of silently unedited. The `(none)`
  // marker this tool itself writes for an emptied scope is the sole carve-out.
  if (items.length === 0 && !/^\(none\)$/i.test(block.value.trim())) {
    refuse(4, `the "- Inline review scope:" bullet in "${args.spec}" yields no parsable path entries (raw: ${JSON.stringify(block.value.trim())}) — refusing rather than reporting a no-op success on a list this tool cannot read`, args.json);
    return;
  }

  const keys = items.map((p) => scopeItemKey(p));
  const targetKey = scopeItemKey(target);
  const present = keys.includes(targetKey);
  const next = op === 'include'
    ? (present ? items : [...items, target])
    : items.filter((_, i) => keys[i] !== targetKey);
  const changed = op === 'include' ? !present : present;

  const report = {
    ok: true, spec: args.spec, op, target, base_ref: args.baseRef, changed, dry_run: args.dryRun, scope: next,
  };

  if (changed && !args.dryRun) {
    const lines = norm.split('\n');
    lines.splice(block.start, block.end - block.start, ...renderScopeBlock(block, next));
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
