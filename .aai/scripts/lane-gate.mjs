#!/usr/bin/env node
//
// lane-gate.mjs — deterministic PR fast-lane gate
// (CHANGE lightweight-e2e-lane / SPEC spec-lightweight-e2e-lane).
//
// Decides whether a finished, gated ride may take the PR FAST LANE (narrowed
// CI + on-demand bot sweep, SKILL_PR steps 5c/5d) or must run the unchanged
// HEAVY lane. The verdict is a CONJUNCTION of four machine-read predicates —
// NO agent judgment anywhere in the write path (anti-gaming): a bad or
// inflated declaration can only ever select the HEAVY lane (fail-closed,
// inheriting the SPEC-0041 / SPEC-0097 philosophy).
//
//   1. ceremony_level in {0,1}            — frozen spec frontmatter.
//   2. strategy in {direct,untested,loop} — STATE implementation_strategy.selected.
//   3. select-suites.mjs != FULL_RUN      — no protected-l3 / .aai/scripts/lib/**
//                                           / unmapped path (the exact SPEC-0097
//                                           triad, reused verbatim — never
//                                           re-implemented here).
//   4. changed-file count < N (default 5) AND every changed path classifies
//      into {docs, prose, <=1 test file, <=1 non-core script}.
//
// ANY predicate false, unknown, missing, or degenerate resolves to HEAVY.
// Exit code is ALWAYS 0 — the gate must never fail the ceremony itself; a
// heavy verdict is the safe default, not an error.
//
// Usage:
//   node .aai/scripts/lane-gate.mjs --spec <spec.md> --state <STATE.yaml>
//     (--base-ref <ref> | --files-from <path|->) [--repo-root <dir>]
//     [--max-files <N>] [--select-suites <path>] [--map <path>]
//     [--docs-audit <path>] [--json]
//
// Output (stdout): a verdict line then one line per predicate value, e.g.
//
//   LANE fast
//   ceremony_level=1 ok
//   strategy=direct ok
//   suite_selection=selected ok
//   changed_files=2 max=5 ok
//   diff_classes=docs,test ok
//
// or, on a heavy verdict, the FIRST failing predicate names the reason:
//
//   LANE heavy reason=ceremony_level
//   ceremony_level=2 need=0|1
//   ...
//
// Zero dependencies (Node stdlib only, per docs/TECHNOLOGY.md).

import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SELF_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO_ROOT = resolve(SELF_DIR, '..', '..');

const FAST_STRATEGIES = new Set(['direct', 'untested', 'loop']);
const DEFAULT_MAX_FILES = 5;

function parseArgs(argv) {
  const out = {
    spec: null, intake: null, state: null, baseRef: null, filesFrom: null, repoRoot: null,
    maxFiles: DEFAULT_MAX_FILES, selectSuites: null, mapPath: null,
    auditPath: null, json: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--spec') out.spec = argv[++i];
    else if (a === '--intake') out.intake = argv[++i];
    else if (a === '--state') out.state = argv[++i];
    else if (a === '--base-ref') out.baseRef = argv[++i];
    else if (a === '--files-from') out.filesFrom = argv[++i];
    else if (a === '--repo-root') out.repoRoot = argv[++i];
    else if (a === '--max-files') out.maxFiles = Number(argv[++i]);
    else if (a === '--select-suites') out.selectSuites = argv[++i];
    else if (a === '--map') out.mapPath = argv[++i];
    else if (a === '--docs-audit') out.auditPath = argv[++i];
    else if (a === '--json') out.json = true;
    // Unknown flags ignored on purpose — a CLI slip must never fail the
    // ceremony; it degrades to HEAVY via the normal fail-closed path.
  }
  if (!Number.isInteger(out.maxFiles) || out.maxFiles < 1) out.maxFiles = DEFAULT_MAX_FILES;
  return out;
}

// ---- predicate 1: ceremony_level from spec frontmatter, with an intake ----
// fallback. Mirrors orchestration-dispatch.mjs's reader exactly (fail-closed
// to a non-fast value on absent file/field/garbage token).
//
// INTAKE FALLBACK (CHANGE lane-intake-ceremony): the lane's exact target
// class — small L0/L1 rides that ship on an intake CHANGE doc with NO spec —
// could never qualify, because this predicate only read spec frontmatter
// (measured on 2026-08-02: two 4-5-file test+docs rides, both forced heavy
// solely by ceremony_level=absent). When NO spec path is given (or the file
// does not exist), the same parser now reads `ceremony_level:` from the
// intake doc's frontmatter. Trust model is unchanged: an L0/L1 level is
// self-declared-and-reviewed in a spec too (freezing is an L3 concern), the
// intake sits in the same reviewed diff, and every degenerate input still
// fails closed to heavy. A spec, when present, always WINS — declaring a
// lower level in the intake of a spec'd ride cannot downgrade the lane.
function readCeremonyLevel(specPath, intakePath) {
  const primary = specPath && existsSync(specPath) ? specPath : null;
  const fallback = !primary && intakePath && existsSync(intakePath) ? intakePath : null;
  const source = primary ?? fallback;
  return { ...readCeremonyFrom(source), source: source === null ? null : (primary ? 'spec' : 'intake') };
}

function readCeremonyFrom(specPath) {
  if (!specPath || !existsSync(specPath)) return { value: null, ok: false };
  let body;
  try {
    body = readFileSync(specPath, 'utf8').replace(/\r\n?/g, '\n');
  } catch {
    return { value: null, ok: false };
  }
  const fm = body.match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return { value: null, ok: false };
  const cl = fm[1].match(/^ceremony_level:\s*(\S+)\s*$/m);
  if (!cl || !['0', '1', '2', '3'].includes(cl[1])) return { value: cl ? cl[1] : null, ok: false };
  const n = Number(cl[1]);
  return { value: n, ok: n === 0 || n === 1 };
}

// ---- predicate 2: strategy from STATE.yaml ----
// Indentation-scoped line reader (Node stdlib only, no YAML dep — the same
// discipline close-work-item.mjs's countRemediationRuns uses): top-level
// `implementation_strategy:` (col 0) -> 2-space `selected: <v>`.
function readStrategy(statePath) {
  if (!statePath || !existsSync(statePath)) return { value: null, ok: false };
  let text;
  try {
    text = readFileSync(statePath, 'utf8');
  } catch {
    return { value: null, ok: false };
  }
  let inBlock = false;
  for (const raw of text.split('\n')) {
    if (!raw.trim()) continue;
    const indent = raw.length - raw.trimStart().length;
    const line = raw.trim();
    if (!inBlock) {
      if (indent === 0 && /^implementation_strategy\s*:/.test(line)) inBlock = true;
      continue;
    }
    if (indent === 0) break; // block ended without a selected key
    const m = line.match(/^selected\s*:\s*(\S+)/);
    if (indent === 2 && m) {
      const v = m[1];
      return { value: v, ok: FAST_STRATEGIES.has(v) };
    }
  }
  return { value: null, ok: false };
}

// ---- changed-file list (same source select-suites will see) ----
function getChangedFiles(opts) {
  if (opts.filesFrom) {
    let text;
    try {
      text = opts.filesFrom === '-' ? readFileSync(0, 'utf8') : readFileSync(opts.filesFrom, 'utf8');
    } catch {
      return null; // unreadable -> caller treats as fail-closed
    }
    return text.split('\n').map((s) => s.trim()).filter(Boolean);
  }
  if (!opts.baseRef) return null;
  try {
    // --no-renames (validation RR-rename-blindness): rename detection reports
    // only the DESTINATION path, hiding a protected source renamed to a benign
    // docs/prose path; disabling it surfaces delete+add so the old path always
    // reaches the predicates (fail-closed).
    const out = execFileSync('git', ['diff', '--name-only', '--no-renames', `${opts.baseRef}...HEAD`], {
      cwd: opts.repoRoot,
      encoding: 'utf8',
    });
    return out.split('\n').map((s) => s.trim()).filter(Boolean);
  } catch {
    return null;
  }
}

// ---- predicate 3: reuse select-suites.mjs FULL_RUN triad verbatim ----
// Feeds select-suites the SAME changed-file list via `--files-from -` so the
// protected-l3 / shared-lib / unmapped decision is byte-identical to CI's.
function runSelectSuites(opts, changed) {
  const script = opts.selectSuites
    ? resolve(opts.selectSuites)
    : resolve(SELF_DIR, 'select-suites.mjs');
  if (!existsSync(script)) return { mode: 'full', detail: 'select-suites.mjs absent' };
  const args = [script, '--files-from', '-', '--repo-root', opts.repoRoot];
  if (opts.mapPath) args.push('--map', opts.mapPath);
  if (opts.auditPath) args.push('--docs-audit', opts.auditPath);
  let out;
  try {
    out = execFileSync('node', args, { input: changed.join('\n') + '\n', encoding: 'utf8' });
  } catch (err) {
    return { mode: 'full', detail: `select-suites failed: ${String(err.message || err).slice(0, 120)}` };
  }
  const full = out.split('\n').find((l) => l.startsWith('FULL_RUN'));
  if (full) return { mode: 'full', detail: full.replace(/^FULL_RUN\s*/, '') };
  return { mode: 'selected', detail: '' };
}

// ---- predicate 4: changed-file count + diff surface classes ----
// Classify each path into exactly one of {docs, prose, test, script}. A path
// that classifies into NONE (e.g. a workflow yaml, a config file), or a diff
// with >1 test file, >1 script file, >1 prose (prompt-corpus) file, or
// count >= N, is NOT fast-eligible.
// PROFILES core list (workflow engine files). A core-classified script is a
// WORKFLOW ENGINE (close-work-item, dispatch, state tooling...) — never
// fast-eligible even when mapped and unprotected (bot-review P1). Unreadable
// PROFILES -> null -> every script classifies unknown -> heavy (fail-closed).
let PROFILES_CORE = undefined;
function profilesCore(repoRoot) {
  if (PROFILES_CORE !== undefined) return PROFILES_CORE;
  try {
    const raw = readFileSync(resolve(repoRoot, '.aai/system/PROFILES.yaml'), 'utf8');
    const set = new Set();
    let inCore = false;
    for (const line of raw.split(/\r?\n/)) {
      if (/^core:\s*$/.test(line)) { inCore = true; continue; }
      if (/^\S/.test(line)) { inCore = false; continue; }
      const m = inCore ? line.match(/^  - (.+)$/) : null;
      if (m) set.add(m[1].trim());
    }
    PROFILES_CORE = set.size > 0 ? set : null;
  } catch {
    PROFILES_CORE = null;
  }
  return PROFILES_CORE;
}

function classifyPath(p, repoRoot) {
  if (p.startsWith('tests/')) return 'test';
  if (p.startsWith('.aai/scripts/')) {
    const core = profilesCore(repoRoot);
    if (core === null) return null;          // PROFILES unreadable -> heavy
    if (core.has(p)) return null;            // core workflow engine -> heavy
    return 'script';
  }
  // prose: prompt corpus / any .aai markdown.
  if (p.startsWith('.aai/') && p.endsWith('.md')) return 'prose';
  // docs: everything under docs/, or a top-level markdown file (README,
  // CHANGELOG, SKILLS, ...). A top-level *.md has no slash before the name.
  if (p.startsWith('docs/')) return 'docs';
  if (p.endsWith('.md') && !p.includes('/')) return 'docs';
  return null;
}

function evaluateDiffSurface(changed, maxFiles, repoRoot) {
  const classes = [];
  let tests = 0;
  let scripts = 0;
  let prose = 0;
  let unclassified = null;
  for (const p of changed) {
    const c = classifyPath(p, repoRoot);
    if (c === null) { if (unclassified === null) unclassified = p; continue; }
    if (c === 'test') tests += 1;
    if (c === 'script') scripts += 1;
    if (c === 'prose') prose += 1;
    if (!classes.includes(c)) classes.push(c);
  }
  const count = changed.length;
  let ok = true;
  let detail = '';
  if (count >= maxFiles) { ok = false; detail = `count ${count} >= max ${maxFiles}`; }
  else if (unclassified !== null) { ok = false; detail = `unclassified path ${unclassified}`; }
  else if (tests > 1) { ok = false; detail = `${tests} test files (max 1)`; }
  else if (scripts > 1) { ok = false; detail = `${scripts} script files (max 1)`; }
  // prose (prompt corpus) capped at 1 (validation RR-prose-uncapped): a
  // multi-prompt ride is exactly the surface where the external sweep has
  // historically earned its keep — it stays on the heavy lane.
  else if (prose > 1) { ok = false; detail = `${prose} prompt-corpus files (max 1)`; }
  return { ok, count, classes, detail };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  opts.repoRoot = resolve(opts.repoRoot || DEFAULT_REPO_ROOT);

  const ceremony = readCeremonyLevel(opts.spec ? resolve(opts.spec) : null,
    opts.intake ? resolve(opts.intake) : null);
  const strategy = readStrategy(opts.state ? resolve(opts.state) : null);
  const changed = getChangedFiles(opts);

  // Fail closed when the protected-path configuration itself is missing:
  // select-suites cannot apply the protected-l3 triad without it, and its
  // silence would otherwise read as "no FULL_RUN" (bot-review P2).
  let protectedCfgOk = true;
  try {
    readFileSync(resolve(opts.repoRoot, 'docs/ai/docs-audit.yaml'), 'utf8');
  } catch {
    protectedCfgOk = false;
  }

  // Predicate lines (AC-007 auditability) — always emitted, fast or heavy.
  const lines = [];
  lines.push(`ceremony_level=${ceremony.value ?? 'absent'}${ceremony.source ? ` source=${ceremony.source}` : ''} ${ceremony.ok ? 'ok' : 'need=0|1'}`);
  lines.push(`strategy=${strategy.value ?? 'absent'} ${strategy.ok ? 'ok' : 'need=direct|untested|loop'}`);
  lines.push(`protected_config=${protectedCfgOk ? 'present ok' : 'MISSING (docs/ai/docs-audit.yaml) fail-closed'}`);

  // Fail-closed if the diff itself is unreadable.
  let suite = { mode: 'full', detail: 'no diff source' };
  let surface = { ok: false, count: 0, classes: [], detail: 'no diff source' };
  if (changed !== null) {
    suite = runSelectSuites(opts, changed);
    surface = evaluateDiffSurface(changed, opts.maxFiles, opts.repoRoot);
  }
  lines.push(`suite_selection=${suite.mode} ${suite.mode === 'full' ? `full_run=${suite.detail}` : 'ok'}`);
  lines.push(`changed_files=${surface.count} max=${opts.maxFiles} ${surface.count >= opts.maxFiles ? 'over' : 'ok'}`);
  lines.push(`diff_classes=${surface.classes.join(',') || 'none'} ${surface.ok ? 'ok' : `blocked=${surface.detail}`}`);

  // Deterministic reason priority: ceremony -> strategy -> protected_config
  // -> full_run -> diff_surface.
  let reason = null;
  if (!ceremony.ok) reason = 'ceremony_level';
  else if (!strategy.ok) reason = 'strategy';
  else if (!protectedCfgOk) reason = 'protected_config_missing';
  else if (suite.mode === 'full') reason = 'full_run';
  else if (!surface.ok) reason = 'diff_surface';

  const fast = reason === null;

  if (opts.json) {
    console.log(JSON.stringify({
      lane: fast ? 'fast' : 'heavy',
      reason,
      predicates: {
        ceremony_level: { value: ceremony.value, ok: ceremony.ok, source: ceremony.source ?? null },
        strategy: { value: strategy.value, ok: strategy.ok },
        protected_config: { ok: protectedCfgOk },
        suite_selection: { mode: suite.mode, detail: suite.detail },
        diff_surface: { count: surface.count, classes: surface.classes, ok: surface.ok, detail: surface.detail },
      },
    }, null, 2));
    process.exit(0);
  }

  console.log(fast ? 'LANE fast' : `LANE heavy reason=${reason}`);
  for (const l of lines) console.log(l);
  process.exit(0);
}

try {
  main();
} catch (err) {
  // Any unexpected internal error -> HEAVY, exit 0 (never fail the ceremony).
  console.log('LANE heavy reason=internal-error');
  console.log(`internal_error=${String((err && err.message) || err).slice(0, 160)}`);
  process.exit(0);
}
