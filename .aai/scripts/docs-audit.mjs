#!/usr/bin/env node
// Docs hygiene & drift audit CLI (RFC-0002 / SPEC-0001).
//
// Usage:
//   node .aai/scripts/docs-audit.mjs                # full audit, markdown digest
//   node .aai/scripts/docs-audit.mjs --check        # CI gate: exit 1 on hard failures
//   node .aai/scripts/docs-audit.mjs --quick        # counts only, no git/EVENTS probes
//   node .aai/scripts/docs-audit.mjs --list         # per-doc classification table
//   node .aai/scripts/docs-audit.mjs --path <p>     # scope to a file or subtree
//   node .aai/scripts/docs-audit.mjs --no-event     # skip docs_audit EVENTS append
//   node .aai/scripts/docs-audit.mjs --strict       # enforce even without config
//                                                   # (intake post-save check)
//   node .aai/scripts/docs-audit.mjs --strict-types # unknown frontmatter type
//                                                   # becomes a hard failure
//   node .aai/scripts/docs-audit.mjs --lint-body    # body-lint digest only
//                                                   # (SPEC-0013 H1; exit 0 unless
//                                                   # combined with --strict)
//   node .aai/scripts/docs-audit.mjs --lint-body-file <f>  # pure predicate on an
//                                                   # explicit file (a materialized
//                                                   # STAGED blob): 1 findings /
//                                                   # 0 clean / 2 unreadable
//   node .aai/scripts/docs-audit.mjs --intake-file <f>     # pure predicate on the
//                                                   # artifact intake just saved:
//                                                   # it must be an UNNUMBERED
//                                                   # <PREFIX>-DRAFT-<slug>.md with
//                                                   # number: null / status: draft
//                                                   # a kebab-case slug of at
//                                                   # most 48 chars, and the
//                                                   # prefix + directory the
//                                                   # .aai/INTAKE_COMMON.md table
//                                                   # gives its type: 1 findings /
//                                                   # 0 clean / 2 unreadable
//
// Every flag above that takes a value REFUSES an absent or empty one (exit 2,
// "USAGE ERROR" on stderr) rather than falling through to a full audit.
//
// Modes: enforced (docs/ai/docs-audit.yaml present), report-only (absent), quick.
// In report-only mode --check always exits 0 — first runs never drown the operator.
// The audit REPORTS; the operator DECIDES. This script never edits any doc.

import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  runAudit, suggestedStep, gateDoc, gateFile, lintBody, lintFile,
  scanAuditDocs, loadConfig, CONFIG_PATH,
} from './lib/docs-audit-core.mjs';
import { parseFrontmatter, normalizeNewlines } from './lib/docs-model.mjs';
import fs from 'node:fs';

const ROOT = process.cwd();

// Every value-taking flag fails CLOSED on an absent or empty value. main()
// dispatches on TRUTHINESS, so `--intake-file ""` — a wrapper expanding a
// variable that turned out to be unset — left `args.intakeFile` falsy, skipped
// the predicate and ran a FULL REPOSITORY AUDIT instead: exit 0 on a clean repo
// (plus a `docs_audit` EVENTS append unless `--no-event` was also passed),
// indistinguishable from a pass on an artifact that was never opened. Copilot
// and Codex both raised it on `--intake-file`; the identical three lines
// produced it for `--gate`, `--gate-file`, `--lint-body-file` and `--path`, so
// the check lives in ONE place rather than on the flag that got reviewed.
// Exit 2 is the existing "could not evaluate" code of every file predicate.
function requireValue(flag, value) {
  if (value == null || String(value).trim() === '') {
    console.error(`USAGE ERROR: ${flag} requires a non-empty value`);
    process.exit(2);
  }
  return value;
}

function parseArgs(argv) {
  const args = { check: false, quick: false, path: null, event: true, strict: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--check') args.check = true;
    else if (tok === '--quick') args.quick = true;
    else if (tok === '--no-event') args.event = false;
    else if (tok === '--strict') args.strict = true;
    else if (tok === '--strict-types') args.strictTypes = true;
    else if (tok === '--list') args.list = true;
    else if (tok === '--path') args.path = requireValue(tok, argv[++i]);
    else if (tok === '--gate') args.gate = requireValue(tok, argv[++i]);
    else if (tok === '--gate-file') args.gateFile = requireValue(tok, argv[++i]);
    else if (tok === '--lint-body') args.lintBody = true;
    else if (tok === '--lint-body-file') args.lintBodyFile = requireValue(tok, argv[++i]);
    else if (tok === '--intake-file') args.intakeFile = requireValue(tok, argv[++i]);
  }
  return args;
}

// SPEC-0013 H1 (D2) — one finding, one digest line.
function bodyLintLine(f) {
  return `- ${f.rel}:${f.line} [${f.rule}] ${f.detail}`;
}

// SPEC-0013 H1 — `--lint-body`: lint-only digest over the governed scan set
// (scanAuditDocs minus docs/plans/ under plan_scan_mode: lenient), honoring
// `--path`. Exit 0 always unless combined with `--strict` (then 1 on findings).
// Never emits a docs_audit event.
function runLintBody(args) {
  const config = loadConfig(ROOT);
  const planMode = config?.plan_scan_mode ?? 'lenient';
  const files = scanAuditDocs(ROOT, { scopePath: args.path, scanExclude: config?.scan_exclude ?? [] });
  const findings = [];
  let scanned = 0;
  for (const f of files) {
    if (planMode === 'lenient' && f.rel.startsWith('docs/plans/')) continue;
    scanned += 1;
    const content = fs.readFileSync(path.join(ROOT, f.rel), 'utf8');
    for (const bl of lintBody(content)) findings.push({ rel: f.rel, ...bl });
  }
  console.log(`## Body Lint — ${new Date().toISOString().slice(0, 10)}`);
  console.log('');
  console.log(`- Scanned: ${scanned} docs${args.path ? ` | Scope: ${args.path}` : ''}`);
  console.log('');
  console.log(`### Body lint: ${findings.length}`);
  console.log('');
  if (findings.length === 0) console.log('_None._');
  else for (const f of findings) console.log(bodyLintLine(f));
  if (!args.strict) {
    console.log('');
    console.log('Report-only: body lint never fails this mode without --strict.');
  }
  process.exit(args.strict && findings.length > 0 ? 1 : 0);
}

// SPEC-0013 H1 — `--lint-body-file <file>`: pure predicate on an explicit file
// path (e.g. a materialized STAGED blob), mirroring `--gate-file` (SPEC-0011 G5):
// exit 1 findings / 0 clean / 2 unreadable. Never emits a docs_audit event.
function runLintBodyFile(filePath) {
  console.log(`## Body Lint — ${filePath}`);
  console.log('');
  const res = lintFile(ROOT, filePath);
  if (!res.found) {
    console.log(`LINT ERROR: file not found or unreadable: "${filePath}"`);
    process.exit(2);
  }
  if (res.findings.length === 0) {
    console.log('LINT PASS: no body-lint findings.');
    process.exit(0);
  }
  console.log('LINT FAIL — body-lint findings:');
  for (const f of res.findings) console.log(`- line ${f.line} [${f.rule}] ${f.detail}`);
  process.exit(1);
}

// spec-intake-numbers-some-doc-types-immediately — `--intake-file <file>`: the
// INTAKE-time twin of the allocator's merge-time no-DRAFT guard. That guard
// catches an unnumbered doc reaching the merge point; nothing caught a NUMBERED
// doc being created at intake, which is how DEBT-0001, DEBT-0002, RES-0001 and
// RESEARCH-0001 entered the corpus already numbered. Scoped to the ONE file
// intake just saved (the only place the act of creation is observable), so it
// never judges a doc the allocator legitimately numbered later. Same exit
// contract as --gate-file: 1 findings / 0 clean / 2 unreadable.
//
// Everything this mode needs lives HERE rather than in lib/docs-audit-core.mjs
// on purpose: that library is imported by two dozen suites, `select-suites.mjs`
// classifies it as a shared lib and escalates any edit to a FULL_RUN, and
// `test-aai-ceremony-levels.sh` TEST-016 pins it byte-untouched. None of that
// is worth paying for three functions used by one flag.

// Path to the ONE place that states the intake type -> directory + prefix
// mapping. It is a PROMPT the intake router already reads, so keeping the
// machine-readable table there (rather than duplicating it here) is what makes
// prompt and gate un-driftable: the gate fails the moment the table the router
// obeys stops matching the artifact the router produced.
const INTAKE_COMMON_PATH = '.aai/INTAKE_COMMON.md';

// Parse the DURABLE DOC IDENTITY type table out of INTAKE_COMMON.md. One row
// per intake type: "| <intake type> | <frontmatter type> | docs/<dir> | PREFIX |".
// The header row and the |---| separator cannot match by construction (their
// cells carry spaces and capitals), so no row-skipping heuristic is needed.
// Returns [] when the table is absent — callers treat that as an error, never
// as "no rule" (degrade LOUDLY, never silently permit).
// EXPORTED for one reason: tests/skills/test-aai-intake.sh TEST-013 reads the
// table with a deliberately independent single-space awk, and an independent
// reader that is never cross-checked cannot notice a row the GATE has and the
// test does not (this regex allows \s*, the awk does not). The arm imports
// this function to compare the two readings row-for-row. Nothing in production
// imports it; main() below is the only caller.
export function parseIntakeTypeTable(content) {
  const rows = [];
  for (const line of normalizeNewlines(String(content ?? '')).split('\n')) {
    const m = line.match(/^\|\s*([a-z]+)\s*\|\s*([a-z]+)\s*\|\s*(docs\/[a-z]+)\s*\|\s*([A-Z]+)\s*\|\s*$/);
    if (m) rows.push({ intakeType: m[1], type: m[2], dir: m[3], prefix: m[4] });
  }
  return rows;
}

// Pure predicate: does this artifact have the shape intake is required to
// produce? An intake artifact is an UNNUMBERED draft — the sequential display
// number is assigned at MERGE by allocate-doc-number.mjs. Returns finding
// strings; empty == clean.
function intakeShapeFindings(rel, content, table) {
  const findings = [];
  const base = path.basename(rel);
  const dir = path.dirname(rel).split(path.sep).join('/');
  // The DRAFT match is deliberately permissive about the SLUG (`.+`, not
  // `[a-z0-9-]+`) and the slug shape is judged separately below. A DRAFT file
  // with a malformed slug IS a DRAFT file, and reporting `not-a-draft-basename`
  // for it would be the same wrong-diagnosis defect this pass fixes one finding
  // down: the verdict would be right and the reason would send the reader to
  // the wrong fix.
  const draft = base.match(/^([A-Z]+(?:-[A-Z]+)*)-DRAFT-(.+)\.md$/);
  const numbered = base.match(/^([A-Z]+(?:-[A-Z]+)*)-(\d{1,5})(?=[-.])/);
  // Prefix token of the basename whatever its shape — the DRAFT prefix, else
  // the numbered one, else none. The directory/prefix rule is judged against
  // THIS rather than against `Boolean(draft)` (see the finding below).
  const basePrefix = draft ? draft[1] : numbered ? numbered[1] : null;
  if (!draft) {
    findings.push(numbered
      ? `numbered-at-intake: "${base}" already carries the display number ${numbered[2]}. Intake creates ${numbered[1]}-DRAFT-<slug>.md; the number is assigned at MERGE by allocate-doc-number.mjs`
      : `not-a-draft-basename: "${base}" is not <PREFIX>-DRAFT-<slug>.md`);
  } else {
    // The gate enforces the slug constraint .aai/INTAKE_COMMON.md STATES
    // ("kebab-case of the topic (lowercase, ASCII, at most 48 chars)"). It did
    // not: `[a-z0-9-]+` accepted `ISSUE-DRAFT--.md`, `ISSUE-DRAFT-foo-.md` and
    // any length, so the document claimed a constraint no tool held (Codex
    // review, PR #269). Kebab-case is spelled out rather than assumed: at
    // least one alphanumeric run, single hyphens BETWEEN runs only, so no
    // leading, trailing or doubled hyphen. Same shape `deriveSlug` in
    // allocate-doc-number.mjs produces, and the same 48 it truncates to.
    // NOTE the one known gap, named rather than left to be discovered:
    // `draftFilename(type, slug, suffix)` can append a 4-char collision
    // suffix, which would put a maximal slug at 53. Nothing on the intake path
    // calls it (intake names its own file from the table; the only callers are
    // in tests/skills/test-aai-doc-numbering.sh), so the bound is enforced on
    // the whole slug token as written. If that path is ever wired to intake,
    // this is the line that has to learn about the suffix.
    const slug = draft[2];
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
      findings.push(`slug-not-kebab: "${slug}" is not kebab-case (lowercase ASCII alphanumerics separated by single hyphens; no leading, trailing or doubled hyphen) — ${INTAKE_COMMON_PATH} DURABLE DOC IDENTITY`);
    }
    if (slug.length > 48) {
      findings.push(`slug-too-long: "${slug}" is ${slug.length} characters; ${INTAKE_COMMON_PATH} DURABLE DOC IDENTITY caps the slug at 48`);
    }
  }
  const fm = parseFrontmatter(content);
  if (fm == null) {
    findings.push('no-frontmatter: the artifact has no parsable YAML frontmatter block');
    return findings;
  }
  // An ABSENT `number:` key is a finding, not a pass. `fm.number != null` is
  // false for `undefined`, so a frontmatter block that simply omits the key
  // used to clear the gate while an omitted `status` was caught — an asymmetry
  // with no reason behind it. The rule is `number: null`, present and explicit
  // (the allocator stamps the number INTO that key at merge), so the gate says
  // so. It only ever failed open in the unnumbered direction, which is why
  // this is a hardening, not a numbered-at-intake escape.
  if (!Object.prototype.hasOwnProperty.call(fm, 'number')) {
    findings.push('number-absent: frontmatter has no number key at all (intake writes an explicit number: null)');
  } else if (fm.number != null) findings.push(`number-not-null: frontmatter number is "${fm.number}" (intake writes number: null)`);
  if (fm.status !== 'draft') findings.push(`status-not-draft: frontmatter status is "${fm.status ?? '(absent)'}" (intake writes status: draft)`);
  const type = fm.type == null ? '' : String(fm.type);
  const matches = table.filter(r => r.type === type);
  if (matches.length === 0) {
    findings.push(`unknown-type: frontmatter type "${type || '(absent)'}" is not in the ${INTAKE_COMMON_PATH} table (known: ${[...new Set(table.map(r => r.type))].join(', ')})`);
  } else if (!matches.some(r => r.dir === dir && r.prefix === basePrefix)) {
    // Judged on the DIRECTORY and the PREFIX alone. `Boolean(draft)` used to
    // sit inside this predicate, so a correctly located numbered file —
    // DEBT-0001-<slug>.md in docs/issues/ with type techdebt — collected
    // `wrong-prefix-or-dir` on top of `numbered-at-intake` even though neither
    // its directory nor its prefix was wrong (Copilot review, PR #269). The
    // verdict was right and the reason was false, which sends the next reader
    // to the wrong fix; the DRAFT shape is already reported by its own finding
    // above.
    const want = [...new Set(matches.map(r => `${r.dir}/${r.prefix}-DRAFT-<slug>.md`))].join(' or ');
    findings.push(`wrong-prefix-or-dir: type "${type}" must be saved as ${want}, got "${rel}"`);
  }
  return findings;
}

// File-facing wrapper mirroring gateFile / lintFile: resolves both the artifact
// and the single-source table, and reports WHICH of the two is unreadable
// rather than passing an unchecked artifact.
function intakeShapeFile(root, filePath) {
  const abs = path.isAbsolute(filePath) ? filePath : path.join(root, filePath);
  let content;
  try { content = fs.readFileSync(abs, 'utf8'); }
  catch { return { found: false, findings: [], error: `file not found or unreadable: "${filePath}"` }; }
  let table;
  try { table = parseIntakeTypeTable(fs.readFileSync(path.join(root, INTAKE_COMMON_PATH), 'utf8')); }
  catch { return { found: false, findings: [], error: `${INTAKE_COMMON_PATH} not found or unreadable — the type/prefix table is the single source of truth and cannot be inferred` }; }
  if (table.length === 0) {
    return { found: false, findings: [], error: `${INTAKE_COMMON_PATH} carries no DURABLE DOC IDENTITY type table` };
  }
  const rel = path.isAbsolute(filePath) ? path.relative(root, abs) : filePath;
  return { found: true, findings: intakeShapeFindings(rel, content, table), error: null };
}

function runIntakeFile(filePath) {
  console.log(`## Intake Shape — ${filePath}`);
  console.log('');
  const res = intakeShapeFile(ROOT, filePath);
  if (!res.found) {
    console.log(`INTAKE ERROR: ${res.error}`);
    process.exit(2);
  }
  if (res.findings.length === 0) {
    console.log('INTAKE PASS: unnumbered draft with the prefix and directory its type requires.');
    process.exit(0);
  }
  console.log('INTAKE FAIL — this artifact is not the unnumbered draft intake must produce:');
  for (const f of res.findings) console.log(`- ${f}`);
  process.exit(1);
}

// SPEC-0011 G1 — `--gate <DOC-ID>` offline close-time predicate. Prints the
// reasons and exits 1 on fail, 0 on pass, 2 when the id resolves to no scanned
// doc. Scope-limited to the one doc; never emits a docs_audit event.
function runGate(docId) {
  emitGate(`## Close Gate — ${docId}`, gateDoc(ROOT, docId));
}

// SPEC-0011 G5 — `--gate-file <file>` gates the content of an explicit file path
// (e.g. a materialized STAGED blob) rather than resolving the doc by id from the
// worktree. Same exit contract as `--gate` (1 fail / 0 pass / 2 unreadable).
function runGateFile(filePath) {
  emitGate(`## Close Gate — ${filePath}`, gateFile(ROOT, filePath));
}

function emitGate(header, res) {
  console.log(header);
  console.log('');
  if (!res.found) {
    console.log(`GATE ERROR: ${res.reasons.join('; ')}`);
    process.exit(2);
  }
  if (res.ok) {
    console.log('GATE PASS: AC Status table complete (every row terminal, every done row evidenced, every Review-By valid).');
    process.exit(0);
  }
  console.log('GATE FAIL — the AC Status table is not reconciled:');
  for (const r of res.reasons) console.log(`- ${r}`);
  process.exit(1);
}

function table(header, rows) {
  const out = [`| ${header.join(' | ')} |`, `|${header.map(() => '---').join('|')}|`];
  for (const r of rows) out.push(`| ${r.join(' | ')} |`);
  return out;
}

function emitEvent(result, scope) {
  try {
    const helper = path.join(path.dirname(fileURLToPath(import.meta.url)), 'append-event.mjs');
    execFileSync('node', [
      helper, '--event', 'docs_audit', '--ref', `docs-audit/${scope}`,
      '--total', String(result.counts.total),
      '--orphans', String(result.counts.orphans),
      '--drifted', String(result.counts.drifted),
      '--stale', String(result.counts.stale),
      '--false-open', String(result.counts.falseOpen),
      '--mode', result.mode,
    ], { stdio: 'ignore' });
  } catch {
    console.warn('warn: docs_audit event append failed (best-effort, continuing)');
  }
}

function main() {
  const args = parseArgs(process.argv);
  if (args.intakeFile) runIntakeFile(args.intakeFile);   // exits 1/0/2; never returns
  if (args.gate) runGate(args.gate);   // exits 1/0/2; never returns
  if (args.gateFile) runGateFile(args.gateFile);   // exits 1/0/2; never returns
  if (args.lintBodyFile) runLintBodyFile(args.lintBodyFile);   // exits 1/0/2; never returns
  if (args.lintBody) runLintBody(args);   // exits 0 (or 1 with --strict); never returns
  const result = runAudit(ROOT, {
    quick: args.quick, scopePath: args.path, strict: args.strict,
    strictTypes: Boolean(args.strictTypes),
  });
  const { counts, mode } = result;
  const scope = args.path ?? 'full';
  const lines = [];

  lines.push(`## Docs Audit — ${new Date().toISOString().slice(0, 10)}`);
  lines.push('');
  lines.push(`- Mode: ${mode}${args.path ? ` | Scope: ${args.path}` : ''}`);
  lines.push(`- Scanned: ${counts.total} docs | Orphans: ${counts.orphans} (${counts.orphans - counts.orphansNew} legacy soft) | Drifted: ${counts.drifted} | Stale: ${counts.stale} | False-open: ${counts.falseOpen} | Obsolete: ${counts.obsolete}`);
  // umbrella visibility (fix/umbrella-false-open): suppressed noise is still
  // reported — line appears only when at least one umbrella doc exists, so
  // repos without umbrellas keep byte-identical output.
  if (counts.umbrellaOpen > 0) lines.push(`- Umbrella (deliberately open, false-open heuristic suppressed): ${counts.umbrellaOpen} (${(counts.umbrellaIds || []).join(', ')})`);
  lines.push(`- Tracked: ${counts.trackedOpen} open, ${counts.trackedDone} done, ${counts.superseded} superseded/rejected`);
  // Rollout progress (always-shown): an in-flight rfc/prd umbrella's `status` enum
  // never shows how far along it is — this rolls up its done/total child docs so
  // partial progress is visible on a plain `docs-audit --check`. Report-only.
  if (result.parentProgress && result.parentProgress.length > 0) {
    const seg = result.parentProgress
      .map((p) => `${p.id} ${p.done}/${p.total}`)
      .join(' · ');
    lines.push(`- Rollout: ${seg}`);
  }
  // docs/ai canon (CHANGE docs-ai-canon): a DIRECT child of docs/ai/ that is in
  // neither .aai/system/DOCS_AI_CANON.list nor the project's
  // docs_ai_canon_extra. Emitted ONLY when N>0, so clean repos keep
  // byte-identical output (the umbrella-count precedent), and outside the
  // !--quick block so the pure-fs class is visible in quick mode too.
  // Report-only: never flips the verdict.
  if (counts.docsAiNonCanon > 0) {
    lines.push(`- docs/ai non-canonical: ${counts.docsAiNonCanon} (${counts.docsAiNonCanonNames.join(', ')})`);
  }
  lines.push('');

  if (mode === 'report-only') {
    lines.push(`Note: ${CONFIG_PATH} not found — running report-only (nothing hard-fails).`);
    lines.push(`Enable enforcement by creating it with a legacy_until_date (see RFC-0002).`);
    lines.push('');
  }

  if (args.list) {
    const CLASS_ORDER = ['orphan', 'drifted', 'obsolete', 'tracked-open', 'tracked-done', 'superseded'];
    const sorted = [...result.docs].sort((a, b) =>
      (CLASS_ORDER.indexOf(a.cls) - CLASS_ORDER.indexOf(b.cls)) || a.rel.localeCompare(b.rel));
    lines.push(`### Classification: ${result.docs.length} docs`);
    lines.push('');
    lines.push(...table(['Doc', 'Class', 'Status', 'Verdict', 'Scope', 'Path'],
      sorted.map(d => [
        d.id, d.cls, d.effectiveStatus ?? d.status ?? '—',
        d.verdict ?? '—', d.scope ?? '—', d.rel,
      ])));
    lines.push('');
  }

  if (!args.quick) {
    lines.push(`### Orphans (need triage): ${counts.orphans}`);
    lines.push('');
    if (counts.orphans === 0) lines.push('_None._');
    else {
      lines.push(...table(['Path', 'Suggested ID', 'First commit', 'Age class', 'Problem'],
        [...result.orphansNew, ...result.orphansLegacy].map(d => {
          const suggested = d.relatedIds?.length
            ? `${d.fileId} (primary) + ${d.relatedIds.join(' + ')}`
            : (d.fileId ?? '—');
          return [d.rel, suggested, d.firstCommit ?? 'untracked', d.legacy ? 'legacy (soft)' : 'new (hard)', d.reasons.join('; ')];
        })));
    }
    if (result.planLenient.length) {
      lines.push('');
      lines.push(`Note: ${result.planLenient.length} operator plan file(s) inventoried leniently (plan_scan_mode: lenient) — no frontmatter required.`);
    }
    lines.push('');
    lines.push(`### Drift report: ${result.drift.length}`);
    lines.push('');
    if (result.drift.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Verdict', 'Evidence', 'Suggested next step'],
        result.drift.map(d => [d.id, d.verdict, d.reasons.join('; '), suggestedStep(d)])));
      lines.push('');
      lines.push('Triage commands:');
      for (const d of result.drift) {
        lines.push(`- ${d.id}: \`git log --grep="${d.id}" --oneline\` | \`head -50 ${d.rel}\``);
      }
    }
    lines.push('');
    if (result.violations.length) {
      lines.push(`### Schema violations: ${result.violations.length}`);
      lines.push('');
      for (const v of result.violations) lines.push(`- ${v.rel}: ${v.msg}`);
      lines.push('');
    }
    if (result.typeWarnings.length) {
      lines.push(`### Type warnings: ${result.typeWarnings.length}`);
      lines.push('');
      for (const w of result.typeWarnings) lines.push(`- ${w.id} (${w.rel}): ${w.msg}`);
      lines.push('');
    }
    if (result.annotations.length) {
      lines.push(`### Annotations`);
      lines.push('');
      for (const a of result.annotations) lines.push(`- ${a.id}: ${a.key} = ${a.value}`);
      lines.push('');
    }
    // Rollout progress (report-only): done/total child docs per in-flight rfc/prd
    // umbrella, so partial progress is visible — the parent `status` enum never is.
    lines.push(`### Rollout progress: ${result.parentProgress.length}`);
    lines.push('');
    if (result.parentProgress.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Parent', 'Type', 'Status', 'Children done', 'Path'],
        result.parentProgress.map(p => [
          p.id, p.type, p.status,
          `${p.done}/${p.total} (${p.total ? Math.round((p.done / p.total) * 100) : 0}%)`,
          p.rel,
        ])));
    }
    lines.push('');
    // Closeout candidates (SPEC-0003 / CHANGE-0004): report-only — never feeds
    // the exit-code path; surfaces non-terminal parents whose specs are all done.
    lines.push(`### Closeout candidates: ${result.closeoutCandidates.length}`);
    lines.push('');
    if (result.closeoutCandidates.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Parent', 'Type', 'Status', 'Satisfying spec(s)', 'Suggested next step'],
        result.closeoutCandidates.map(c => [
          c.id, c.type, c.status, c.specs.join(' + '), c.suggestedStep,
        ])));
    }
    lines.push('');
    // Duplicate doc ids (SPEC-0057 / ISSUE-0014): report-only signal folded into
    // needsTriage (NOT hardFail) — >=2 scanned docs sharing one effective
    // frontmatter id; id-keyed resolution (byId, closeout) silently picks one
    // until each doc is given a unique id.
    lines.push(`### Duplicate doc ids: ${result.duplicateDocIds.length}`);
    lines.push('');
    if (result.duplicateDocIds.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Id', 'Count', 'Paths'],
        result.duplicateDocIds.map(g => [g.id, String(g.paths.length), g.paths.join(' + ')])));
      lines.push('');
      lines.push('Two or more scanned docs share one frontmatter `id` — id-keyed resolution (byId, closeout) silently picks one. Give each doc a unique id (e.g. `spec-`-prefix a spec that shares its intake\'s slug).');
    }
    lines.push('');
    // Open decisions on done docs (SPEC-0006 / Spec-AC-06): report-only — never
    // feeds the exit-code path; surfaces done docs whose body buries an
    // unresolved decision as a free-text WARNING.
    lines.push(`### Open decisions on done docs: ${result.openDecisionDoneDocs.length}`);
    lines.push('');
    if (result.openDecisionDoneDocs.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Marker', 'Line', 'Path'],
        result.openDecisionDoneDocs.map(d => [d.id, d.marker, String(d.line), d.rel])));
      lines.push('');
      lines.push('Report-only: resolve each decision before close, or promote it to a tracked item (a per-AC blocked/deferred row with Review-By, or a follow-up tracked doc).');
    }
    lines.push('');
    // SPEC-0011 G4 — near-miss AC tables (report-only; never feeds the exit-code
    // path). A table that LOOKS like an AC Status table but is not the canonical
    // shape, so the drift verdict may be inaccurate.
    lines.push(`### Near-miss AC tables: ${result.nearMissWarnings.length}`);
    lines.push('');
    if (result.nearMissWarnings.length === 0) lines.push('_None._');
    else {
      const rows = [];
      for (const d of result.nearMissWarnings) {
        for (const w of d.warnings) rows.push([d.id, w.kind, w.detail, d.rel]);
      }
      lines.push(...table(['Doc', 'Kind', 'Detail', 'Path'], rows));
    }
    lines.push('');
    // SPEC-0011 G3 — Review-By claims not backed by an event/artifact (report-only).
    lines.push(`### Review-By claims (unbacked): ${result.reviewClaimUnbacked.length}`);
    lines.push('');
    if (result.reviewClaimUnbacked.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Spec-AC', 'Review-By', 'Verdict', 'Path'],
        result.reviewClaimUnbacked.map(r => [r.id, r.specAc, r.reviewBy, r.verdict, r.rel])));
      lines.push('');
      lines.push('Report-only: a `Review-By: code-review` claim with no corroborating code_review_completed / work_item_closed(code_review: pass*) event and no docs/ai/{reviews,reports}/*<ID>* artifact.');
    }
    lines.push('');
    // SPEC-0011 G2 — telemetry-at-close: done docs missing a work_item_closed
    // event (report-only).
    lines.push(`### Missing close telemetry: ${result.missingCloseTelemetry.length}`);
    lines.push('');
    if (result.missingCloseTelemetry.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Verdict', 'Path'],
        result.missingCloseTelemetry.map(d => [d.id, 'missing-close-telemetry', d.rel])));
      lines.push('');
      lines.push('Report-only: emit `append-event.mjs --event work_item_closed --ref <ID> --validation <v> --code-review <cr>` on close.');
    }
    lines.push('');
    // SPEC-0013 H1 — body lint (report-only in this digest; the explicit
    // --strict flag promotes findings to the hard-fail exit path, D2).
    lines.push(`### Body lint: ${result.bodyLint.length}`);
    lines.push('');
    if (result.bodyLint.length === 0) lines.push('_None._');
    else {
      for (const f of result.bodyLint) lines.push(bodyLintLine(f));
      lines.push('');
      lines.push('Report-only without --strict: stray tool markup, unbalanced fences, and template placeholders in governed doc bodies (fenced blocks and inline code spans are never flagged).');
    }
    lines.push('');
    // RFC-0011 (delta-spec lifecycle) D3 — canonical-provenance drift. A
    // requirement in docs/canonical/*.md whose Provenance is empty (never
    // merged) or names a spec that resolves to no scanned doc. Empty/absent
    // docs/canonical/ contributes nothing here. Hard-fails --check in enforced
    // or --strict mode (see runAudit hardFail).
    lines.push(`### Canonical provenance drift: ${result.provenanceDrift.length}`);
    lines.push('');
    if (result.provenanceDrift.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Canonical doc', 'Requirement', 'Kind', 'Detail', 'Path'],
        result.provenanceDrift.map(p => [p.id, p.reqId, p.kind, p.detail, p.rel])));
    }
    lines.push('');
    // CHANGE docs-ai-canon — non-canonical docs/ai children, one row per entry
    // with a shape-derived remediation hint. Section emitted ONLY when there is
    // something to say (byte-compat for clean repos, mirroring the summary line
    // and the Schema-violations section).
    if (result.docsAiNonCanon.length) {
      lines.push(`### docs/ai non-canonical entries: ${result.docsAiNonCanon.length}`);
      lines.push('');
      lines.push(...table(['Entry', 'Kind', 'Remediation hint'],
        result.docsAiNonCanon.map(e => [`docs/ai/${e.name}`, e.kind, e.hint])));
      lines.push('');
      lines.push('Report-only: the canonical inventory is `.aai/system/DOCS_AI_CANON.list`; project-specific additions belong in `docs/ai/docs-audit.yaml` under `docs_ai_canon_extra:`. Straighten the entry (move it to its canonical home) or register it — do not leave it to be found by hand.');
      lines.push('');
    }
    if (result.pendingCommit.length) {
      lines.push(`### Pending commit (verdicts reflect the working tree)`);
      lines.push('');
      for (const p of result.pendingCommit) lines.push(`- ${p}`);
      lines.push('');
    }
  }

  const needsTriage = counts.orphans + counts.drifted + counts.obsolete + counts.violations + counts.provenanceDrift + counts.duplicateDocId;
  lines.push(`### Verdict: ${needsTriage === 0 ? 'CLEAN' : `NEEDS-TRIAGE (${needsTriage} items)`}`);
  if (result.hardFail) {
    lines.push('');
    const bodyLintPart = args.strict ? `, ${counts.bodyLint} body lint finding(s)` : '';
    const provPart = counts.provenanceDrift ? `, ${counts.provenanceDrift} canonical provenance drift finding(s)` : '';
    lines.push(`CHECK FAILED: ${counts.orphansNew} new orphan(s), ${counts.violations} schema violation(s)${bodyLintPart}${provPart}.`);
  }

  console.log(lines.join('\n'));

  if (!args.quick && args.event) emitEvent(result, scope);

  if (args.check && result.hardFail) process.exit(1);
}

main();
