#!/usr/bin/env node
//
// golden-flow.mjs — the deterministic downstream golden flow
// (ref simple-and-friendly-to-use / SPEC-0172-spec-simple-and-friendly-to-use,
// D1 / D3, Spec-AC-01, 02, 04, 05).
//
// Builds a FRESH downstream target the way tests/self-hosting/
// test-self-hosting-smoke.sh does (tests/fixtures/target-project + aai-sync.sh),
// gives it a bare origin whose HEAD is refs/heads/main, then drives one feature
// ride and one bug-fix ride through the ride's OWN CLIs in the order the
// skills call them — intake doc from the vendored template, spec draft,
// spec-freeze.mjs, a delivery commit on a ride branch, a merge into main,
// close-work-item.mjs --pr NONE, docs-audit.mjs --check --strict — every step
// with stdin closed and a per-step timeout, so a step that waits for a human
// is OBSERVED (recorded under `questions` with its command, exit code and the
// first 200 characters of output), never hung. Then it reads the three gate
// fields from nothing-left-behind.mjs --json (never recomputed here) and
// appends ONE record line to the append-only ledger. `--diff` compares the
// last two lines: "behaves worse than before" is its exit 1.
//
// Usage:
//   node .aai/scripts/golden-flow.mjs --out <dir> [--metrics <METRICS.jsonl>]
//        [--record <path>] [--steps-from <jsonl>] [--timeout-ms <n>]
//   node .aai/scripts/golden-flow.mjs --diff [--record <path>]
//   node .aai/scripts/golden-flow.mjs --print-steps
//
//   --out <dir>        REQUIRED for a run: an absolute, non-empty path; the
//                      fixture target is <dir>/target, the bare origin
//                      <dir>/origin.git, HOME for every step <dir>/home, and
//                      <dir>/steps.log lists every step's command + exit code.
//                      Never this checkout — the flow refuses an --out inside
//                      it — and never a directory it did not create: the
//                      fixture build deletes <dir>/target, so a NON-EMPTY
//                      --out without the `.golden-flow-scratch` marker is
//                      refused (exit 2) before anything is removed.
//   --metrics <path>   the METRICS.jsonl ledger tokens_median_last10 is read
//                      from (median of the last ten rides carrying a
//                      usage_total_tokens= marker); absent flag -> null.
//   --record <path>    the record ledger; default docs/ai/tests/golden-flow.jsonl
//                      under this checkout. Append-only (HAZ-LEDGER).
//   --steps-from <f>   override the embedded step list: one JSON object per
//                      line, {"name","run":[argv...]} with the placeholders
//                      {fixture}, {origin}, {home}, {delivery_sha:<branch>};
//                      or {"name","write":"<rel path>","content":"..."}; an
//                      optional "timeout_ms" per step. --print-steps emits the
//                      embedded list in this format so a suite can inject a step.
//   --timeout-ms <n>   per-step timeout, default 120000 (Spec-AC-02).
//
// Exit codes:
//   0  every step exited 0, nothing asked a question (record appended)
//   1  a step failed / timed out / a hitl-channel entry appeared, or --diff
//      found a count that rose (record appended in the run case)
//   2  usage error
//
// Node stdlib only. The vendored layer's CLIs are invoked from the FIXTURE's
// .aai/scripts (seam S1) — this file's own siblings are used only to build the
// fixture (aai-sync.sh) and to replay select-suites.mjs against THIS repo's
// suite map for ci_docs_only_full_run.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { extractUsageTotal } from './lib/usage-note.mjs';

const SELF_DIR = path.dirname(fileURLToPath(import.meta.url));
const SELF_ROOT = path.resolve(SELF_DIR, '..', '..');
const DEFAULT_RECORD = 'docs/ai/tests/golden-flow.jsonl';
const DEFAULT_TIMEOUT_MS = 120000;
export const TOKENS_CEILING = 1640003;   // measured 2026-09-06, spec "The measurements"
const OUTPUT_CHARS = 200;
// The marker a --out scratch dir carries so the flow knows it created it (see
// the guard in main(): the fixture build rm -rf's <out>/target).
export const OUT_MARKER = '.golden-flow-scratch';
const COUNT_FIELDS = ['steps_failed', 'questions_asked', 'files_left', 'docs_open', 'audit_findings', 'registry_self_items'];

function usage(msg) {
  process.stderr.write(`golden-flow: ${msg}\n`);
  process.stderr.write('usage: node .aai/scripts/golden-flow.mjs --out <dir> [--metrics <ledger>] [--record <path>] [--steps-from <jsonl>] [--timeout-ms <n>]\n');
  process.stderr.write('       node .aai/scripts/golden-flow.mjs --diff [--record <path>]\n');
  process.stderr.write('       node .aai/scripts/golden-flow.mjs --print-steps\n');
  exit(2);
}

function parseArgs(argv) {
  const out = { out: null, metrics: null, record: null, stepsFrom: null, timeoutMs: DEFAULT_TIMEOUT_MS, diff: false, printSteps: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const val = () => { const v = argv[++i]; if (v === undefined || v === '') usage(`${a} needs a value`); return v; };
    if (a === '--out') out.out = val();
    else if (a === '--metrics') out.metrics = val();
    else if (a === '--record') out.record = val();
    else if (a === '--steps-from') out.stepsFrom = val();
    else if (a === '--timeout-ms') { out.timeoutMs = Number(val()); if (!Number.isFinite(out.timeoutMs) || out.timeoutMs <= 0) usage('--timeout-ms must be a positive number'); }
    else if (a === '--diff') out.diff = true;
    else if (a === '--print-steps') out.printSteps = true;
    else usage(`unknown argument ${a}`);
  }
  return out;
}

// ---- the two rides ----------------------------------------------------------

const RIDES = [
  { slug: 'golden-feature', kind: 'change', template: 'CHANGE_TEMPLATE.md', branch: 'feat/golden-feature', file: 'src/feature.txt', title: 'Golden feature', ac: 'src/feature.txt exists on main' },
  { slug: 'golden-bugfix', kind: 'issue', template: 'ISSUE_TEMPLATE.md', branch: 'fix/golden-bugfix', file: 'src/bugfix.txt', title: 'Golden bug fix', ac: 'src/bugfix.txt exists on main' },
];

// Render an intake doc FROM the vendored template: its frontmatter with the
// id/status substituted, and every `## ` section it declares, filled with one
// line each so the body carries no template placeholder (docs-audit --strict
// body lint) — the heading set is the template's, not this script's.
function renderIntakeFromTemplate(templateText, ride) {
  const text = templateText.replace(/\r\n/g, '\n');
  const fmEnd = text.indexOf('\n---', 4);
  let fm = text.slice(0, fmEnd + 4);
  fm = fm.replace(/^id: .*$/m, `id: ${ride.slug}`).replace(/^status: .*$/m, 'status: draft');
  const headings = [...text.slice(fmEnd + 4).matchAll(/^## (.+)$/gm)].map(m => m[1].trim());
  const fill = {
    'Summary': `- ${ride.title}: a deterministic ${ride.kind === 'issue' ? 'bug-fix' : 'feature'} ride driven by golden-flow.mjs.`,
    'Type': '- bug',
    'Acceptance Criteria': `- AC-001: ${ride.ac}.`,
    'Verification': `- test -f ${ride.file} on main -> exit 0`,
    'Scope': `- In scope: ${ride.file}.\n- Out of scope: everything else.`,
  };
  const body = [`# ${ride.kind === 'issue' ? 'Issue' : 'Change'} — ${ride.title}`, ''];
  for (const h of headings) {
    body.push(`## ${h}`);
    body.push(fill[h] ?? `- ${ride.title}: nothing beyond the file ${ride.file}.`);
    body.push('');
  }
  return `${fm}\n\n${body.join('\n')}`;
}

function specDraft(ride) {
  return `---
id: spec-${ride.slug}
type: spec
number: null
status: draft
ceremony_level: 1
links:
  requirement: docs/issues/${ride.kind === 'issue' ? 'ISSUE' : 'CHANGE'}-DRAFT-${ride.slug}.md
  rfc: null
  pr: []
  commits: []
---

# Spec — ${ride.title}

SPEC-FROZEN: false

## Implementation strategy
- Strategy: loop
- Rationale: one file, one assertion.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | ${ride.ac} | planned | — | — | — |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/${ride.slug}.sh | file exists on main | pending |
`;
}

function specDelivered(ride) {
  return specDraft(ride)
    .replace('status: draft', 'status: implementing')
    .replace('SPEC-FROZEN: false', 'SPEC-FROZEN: true')
    .replace('| planned | — | — | — |', `| done | test -f ${ride.file} exit 0 (delivery commit) | — | — |`)
    .replace('| pending |', '| green |');
}

function rideSteps(ride) {
  const intakePath = `docs/issues/${ride.kind === 'issue' ? 'ISSUE' : 'CHANGE'}-DRAFT-${ride.slug}.md`;
  const specPath = `docs/specs/SPEC-DRAFT-spec-${ride.slug}.md`;
  const git = (...a) => ['git', '-C', '{fixture}', ...a];
  const node = (script, ...a) => ['node', `{fixture}/.aai/scripts/${script}`, ...a];
  return [
    { name: `${ride.slug}: intake doc from the template`, write: intakePath, template: ride.template, ride: ride.slug },
    { name: `${ride.slug}: spec draft`, write: specPath, content: specDraft(ride) },
    { name: `${ride.slug}: commit intake`, run: git('add', '-A') },
    { name: `${ride.slug}: commit intake`, run: git('commit', '-q', '-m', `intake: ${ride.slug}`) },
    { name: `${ride.slug}: spec-freeze`, run: node('spec-freeze.mjs', '--path', specPath) },
    { name: `${ride.slug}: commit freeze`, run: git('add', '-A') },
    { name: `${ride.slug}: commit freeze`, run: git('commit', '-q', '-m', `spec-freeze: spec-${ride.slug}`) },
    { name: `${ride.slug}: ride branch`, run: git('checkout', '-q', '-b', ride.branch) },
    { name: `${ride.slug}: deliver file`, write: ride.file, content: `${ride.title}\n` },
    { name: `${ride.slug}: flip AC table`, write: specPath, content: specDelivered(ride) },
    { name: `${ride.slug}: delivery commit`, run: git('add', '-A') },
    { name: `${ride.slug}: delivery commit`, run: git('commit', '-q', '-m', `deliver ${ride.file} (${ride.slug})`) },
    { name: `${ride.slug}: back to main`, run: git('checkout', '-q', 'main') },
    { name: `${ride.slug}: merge`, run: git('merge', '-q', '--no-ff', '-m', `merge: ${ride.branch} (${ride.slug})`, ride.branch) },
    { name: `${ride.slug}: push main`, run: git('push', '-q', 'origin', 'main') },
    { name: `${ride.slug}: close-work-item`, run: node('close-work-item.mjs', '--ref', ride.slug, '--pr', 'NONE', '--commit', `{delivery_sha:${ride.branch}}`, '--spec', `spec-${ride.slug}`, '--review', 'none') },
    { name: `${ride.slug}: close commit`, run: git('add', '-A') },
    { name: `${ride.slug}: close commit`, run: git('commit', '-q', '-m', `chore(close): ${ride.slug} close ceremony`) },
    { name: `${ride.slug}: push close`, run: git('push', '-q', 'origin', 'main') },
    { name: `${ride.slug}: docs-audit strict`, run: node('docs-audit.mjs', '--check', '--strict', '--no-event') },
  ];
}

export function embeddedSteps() {
  return RIDES.flatMap(rideSteps);
}

function readStepsFrom(file) {
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (err) { usage(`cannot read --steps-from ${file}: ${err.message}`); }
  const steps = [];
  text.split('\n').forEach((line, i) => {
    if (!line.trim() || line.trim().startsWith('#')) return;
    let s;
    try { s = JSON.parse(line); } catch (err) { usage(`--steps-from line ${i + 1} is not JSON: ${err.message}`); }
    if (!s || typeof s.name !== 'string' || (!Array.isArray(s.run) && typeof s.write !== 'string')) usage(`--steps-from line ${i + 1}: need {"name","run":[...]} or {"name","write","content"}`);
    steps.push(s);
  });
  return steps;
}

// ---- fixture ------------------------------------------------------------------

function assertAbs(p, label) {
  if (!p || !path.isAbsolute(p)) usage(`${label} must be a non-empty absolute path, got "${p ?? ''}"`);
}

function git(cwd, args, env) {
  const r = spawnSync('git', ['-C', cwd, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} in ${cwd} failed (exit ${r.status}): ${(r.stderr || r.stdout).trim()}`);
  return r.stdout.trim();
}

function buildFixture(outDir, env) {
  const fixture = path.join(outDir, 'target');
  const origin = path.join(outDir, 'origin.git');
  const home = path.join(outDir, 'home');
  for (const p of [fixture, origin]) {
    if (fs.existsSync(p)) fs.rmSync(p, { recursive: true, force: true });
  }
  fs.mkdirSync(home, { recursive: true });
  fs.cpSync(path.join(SELF_ROOT, 'tests', 'fixtures', 'target-project'), fixture, { recursive: true });
  const sync = spawnSync('bash', [path.join(SELF_DIR, 'aai-sync.sh'), fixture], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env });
  if (sync.status !== 0) throw new Error(`aai-sync.sh failed (exit ${sync.status}): ${(sync.stderr || sync.stdout).trim().slice(-800)}`);
  git(fixture, ['init', '-q']);
  git(fixture, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  git(fixture, ['config', 'user.email', 'golden-flow@example.com']);
  git(fixture, ['config', 'user.name', 'golden-flow']);
  git(fixture, ['add', '-A']);
  git(fixture, ['commit', '-q', '-m', 'init: fresh downstream target']);
  spawnSync('git', ['init', '-q', '--bare', origin], { stdio: 'ignore' });
  git(origin, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  git(fixture, ['remote', 'add', 'origin', origin]);
  git(fixture, ['push', '-q', 'origin', 'HEAD:refs/heads/main']);
  git(fixture, ['symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main']);
  return { fixture, origin, home };
}

// ---- steps ---------------------------------------------------------------------

function substitute(value, ctx) {
  return String(value)
    .replace(/\{fixture\}/g, ctx.fixture)
    .replace(/\{origin\}/g, ctx.origin)
    .replace(/\{home\}/g, ctx.home)
    .replace(/\{delivery_sha:([^}]+)\}/g, (_m, branch) => {
      try { return git(ctx.fixture, ['rev-parse', branch]); } catch { return `unresolved:${branch}`; }
    });
}

function hitlEntries(fixture) {
  const p = path.join(fixture, 'docs', 'ai', 'hitl-channel.json');
  if (!fs.existsSync(p)) return 0;
  try {
    const d = JSON.parse(fs.readFileSync(p, 'utf8'));
    return Array.isArray(d.entries) ? d.entries.length : 0;
  } catch { return 0; }
}

function runStep(step, ctx, stepEnv, timeoutMs) {
  if (typeof step.write === 'string') {
    const target = path.join(ctx.fixture, substitute(step.write, ctx));
    let content = step.content ?? '';
    if (step.template) {
      const ride = RIDES.find(r => r.slug === step.ride);
      const tpl = fs.readFileSync(path.join(ctx.fixture, '.aai', 'templates', step.template), 'utf8');
      content = renderIntakeFromTemplate(tpl, ride);
    }
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, substitute(content, ctx));
    return { command: `write ${target}`, exit_code: 0, output: '', timed_out: false, duration_ms: 0 };
  }
  const argv = step.run.map(a => substitute(a, ctx));
  const started = Date.now();
  const r = spawnSync(argv[0], argv.slice(1), {
    cwd: ctx.fixture, env: stepEnv, encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: step.timeout_ms ?? timeoutMs, killSignal: 'SIGKILL',
  });
  const timedOut = !!(r.error && r.error.code === 'ETIMEDOUT');
  const output = `${r.stdout ?? ''}${r.stderr ?? ''}`.trim();
  const code = r.status === null ? (timedOut ? 124 : (r.error ? 127 : -1)) : r.status;
  return {
    command: argv.join(' '),
    exit_code: code,
    output: (r.error && !timedOut ? `${r.error.message}\n` : '') + output,
    timed_out: timedOut,
    duration_ms: Date.now() - started,
  };
}

// ---- record inputs ----------------------------------------------------------------

function aaiVersion() {
  try {
    const m = fs.readFileSync(path.join(SELF_ROOT, 'docs', 'ai', 'AAI_VERSION.md'), 'utf8').match(/^- Version:\s*(\S+)/m);
    return m ? m[1] : null;
  } catch { return null; }
}

export function tokensMedianLast10(ledgerPath) {
  if (!ledgerPath) return null;
  let text;
  try { text = fs.readFileSync(ledgerPath, 'utf8'); } catch { return null; }
  const totals = [];
  for (const line of text.split('\n')) {
    if (!line.trim() || line.startsWith('#')) continue;
    let r;
    try { r = JSON.parse(line); } catch { continue; }
    if (!Array.isArray(r.agent_runs)) continue;
    let sum = 0, marked = false;
    for (const run of r.agent_runs) {
      // The canonical both-sides-delimited grammar, on the NOTE field only —
      // never a re-declared literal and never the serialized run object
      // (SPEC-0089 Spec-AC-01 single source; a prefixed key or a malformed
      // value is not an honest total, so extractUsageTotal returns null).
      const total = extractUsageTotal(run?.note);
      if (total !== null) { sum += total; marked = true; }
    }
    if (marked) totals.push(sum);
  }
  const last = totals.slice(-10).sort((a, b) => a - b);
  if (last.length === 0) return null;
  const mid = Math.floor(last.length / 2);
  return last.length % 2 ? last[mid] : Math.round((last[mid - 1] + last[mid]) / 2);
}

function gateJson(ctx, ref, stepEnv) {
  const r = spawnSync('node', [path.join(ctx.fixture, '.aai', 'scripts', 'nothing-left-behind.mjs'), '--ref', ref, '--json'], {
    cwd: ctx.fixture, env: stepEnv, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  });
  // NON-ZERO HERE IS NOT A FLOW FAILURE, and that is deliberate — see TEST-006.
  // The gate exits 1 whenever it has something to report, and its counts are
  // carried into the record's files_left / docs_open / audit_findings /
  // registry_self_items, byte-equal to this JSON (TEST-006 asserts that
  // equality against an independent gate run). A leftover file is a FINDING,
  // not a failed step: the flow still exits 0, and `--diff` is what exits 1 when
  // any counter RISES between two runs (Spec-AC-05). Reported as P1 in the PR
  // #355 bot review and re-derived as a false positive against this design —
  // documented here so the next reader does not "fix" it back.
  // `ok` therefore means PARSEABLE, never PASSED; only an unreadable gate is a
  // problem entry, because then the counters would be silently absent.
  try { return { ok: true, json: JSON.parse(r.stdout), exit_code: r.status }; }
  catch (err) { return { ok: false, json: null, exit_code: r.status, error: `${err.message}: ${(r.stderr || r.stdout).trim().slice(0, OUTPUT_CHARS)}` }; }
}

function ciDocsOnlyFullRun(ctx, outDir) {
  // The manifest of the run's own last close-ceremony commit, replayed through
  // THIS repo's suite map: true means such a diff would escalate CI to the
  // full sweep (the PR #350 shape).
  let manifest = '';
  try {
    const sha = git(ctx.fixture, ['log', '--format=%H', '--grep=chore(close):', '-n', '1', 'main']);
    if (!sha) return null;
    manifest = git(ctx.fixture, ['show', '--name-only', '--format=', sha]);
  } catch { return null; }
  const list = path.join(outDir, 'close-manifest.txt');
  fs.writeFileSync(list, manifest.split('\n').filter(Boolean).join('\n') + '\n');
  const r = spawnSync('node', [path.join(SELF_DIR, 'select-suites.mjs'), '--repo-root', SELF_ROOT, '--files-from', list], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return /^FULL_RUN /m.test(r.stdout ?? '');
}

function appendRecord(recordPath, record) {
  fs.mkdirSync(path.dirname(recordPath), { recursive: true });
  // One O_APPEND write of one serialized line — the house JSONL pattern; the
  // base is left a byte-exact prefix (HAZ-LEDGER).
  let prefixNewline = '';
  if (fs.existsSync(recordPath)) {
    const st = fs.statSync(recordPath);
    if (st.size > 0) {
      const fd = fs.openSync(recordPath, 'r');
      const buf = Buffer.alloc(1);
      fs.readSync(fd, buf, 0, 1, st.size - 1);
      fs.closeSync(fd);
      if (buf[0] !== 0x0a) prefixNewline = '\n';
    }
  }
  fs.appendFileSync(recordPath, prefixNewline + JSON.stringify(record) + '\n');
}

// ---- --diff ------------------------------------------------------------------------

function readRecords(recordPath) {
  if (!fs.existsSync(recordPath)) return [];
  const out = [];
  for (const line of fs.readFileSync(recordPath, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    // A malformed line is NAMED and never crashes the diff — but it must not be
    // compared either: every counter reads `undefined`, nothing can be
    // classified as rising, and `--diff` would print `0 worse` and exit 0 over a
    // corrupt record. runDiff refuses instead (Codex review P2, PR #355).
    try { out.push(JSON.parse(line)); } catch { out.push({ malformed: line.slice(0, 80) }); }
  }
  return out;
}

function runDiff(recordPath) {
  const records = readRecords(recordPath);
  if (records.length < 2) {
    process.stdout.write(`golden-flow --diff: ${records.length} record(s) in ${recordPath}; nothing to compare yet\n`);
    exit(0);
  }
  const [prev, last] = records.slice(-2);
  const bad = [prev, last].filter((r) => r && r.malformed !== undefined);
  if (bad.length) {
    process.stderr.write(`golden-flow --diff: refusing to compare a malformed record in ${recordPath}: ${bad.map((r) => r.malformed).join(' | ')}\n`);
    exit(2);
  }
  const keys = [...new Set([...Object.keys(prev), ...Object.keys(last)])].filter(k => k !== 'questions');
  let worse = 0, differ = 0;
  for (const k of keys) {
    const a = JSON.stringify(prev[k] ?? null), b = JSON.stringify(last[k] ?? null);
    if (a === b) continue;
    differ++;
    let mark = '';
    if (COUNT_FIELDS.includes(k) && Number(last[k]) > Number(prev[k])) { worse++; mark = '  <- ROSE'; }
    if (k === 'ci_docs_only_full_run' && last[k] === true && prev[k] !== true) { worse++; mark = '  <- TURNED TRUE'; }
    process.stdout.write(`${k}: ${a} -> ${b}${mark}\n`);
  }
  process.stdout.write(`golden-flow --diff: ${differ} field(s) differ, ${worse} worse (${prev.run_utc ?? '?'} -> ${last.run_utc ?? '?'})\n`);
  exit(worse > 0 ? 1 : 0);
}

// ---- main -------------------------------------------------------------------------

function main() {
  const args = parseArgs(process.argv.slice(2));
  const recordPath = path.resolve(args.record ?? path.join(SELF_ROOT, DEFAULT_RECORD));
  if (args.printSteps) {
    for (const s of embeddedSteps()) process.stdout.write(JSON.stringify(s) + '\n');
    exit(0);
  }
  if (args.diff) runDiff(recordPath);
  if (!args.out) usage('--out <dir> is required for a run');
  const outDir = path.resolve(args.out);
  assertAbs(outDir, '--out');
  if (outDir === SELF_ROOT || outDir.startsWith(SELF_ROOT + path.sep)) usage(`--out must not be inside this checkout (${SELF_ROOT})`);
  fs.mkdirSync(outDir, { recursive: true });
  // buildFixture rm -rf's <out>/target and <out>/origin.git. `target/` is the
  // build-output directory of Rust, Maven and Gradle, and the SELF_ROOT check
  // above covers only THIS checkout — not a sibling clone or a real project
  // root an operator (or the release precondition line, which prints only
  // `--out <scratch dir>`) might name. So: a scratch dir is one this flow
  // created, and it says so in a marker file. A non-empty --out without the
  // marker is refused before anything is deleted; an empty one, or one from a
  // previous run, is accepted and re-marked.
  const marker = path.join(outDir, OUT_MARKER);
  if (!fs.existsSync(marker) && fs.readdirSync(outDir).length > 0) {
    usage(`--out ${outDir} is not empty and carries no ${OUT_MARKER} marker; the flow deletes <out>/target and <out>/origin.git, so point --out at an empty scratch directory`);
  }
  fs.writeFileSync(marker, `golden-flow scratch dir; <out>/target and <out>/origin.git are rebuilt on every run\n`);

  // A minimal environment for every step: no harness variable, no global git
  // config or hook can leak into the fixture (HOME lives under --out).
  const home = path.join(outDir, 'home');
  const stepEnv = {
    PATH: process.env.PATH ?? '/usr/bin:/bin',
    HOME: home,
    TMPDIR: process.env.TMPDIR ?? os.tmpdir(),
    LANG: 'C', LC_ALL: 'C',
    GIT_CONFIG_NOSYSTEM: '1', GIT_TERMINAL_PROMPT: '0',
    ...(process.env.SYSTEMROOT ? { SYSTEMROOT: process.env.SYSTEMROOT } : {}),
  };
  const runUtc = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  let ctx;
  try { ctx = buildFixture(outDir, stepEnv); }
  catch (err) { process.stderr.write(`golden-flow: fixture build failed: ${err.message}\n`); exit(1); }

  const steps = args.stepsFrom ? readStepsFrom(args.stepsFrom) : embeddedSteps();
  const questions = [];
  const stepsLog = [];
  let hitlBefore = hitlEntries(ctx.fixture);
  let failed = 0;
  for (const step of steps) {
    const res = runStep(step, ctx, stepEnv, args.timeoutMs);
    stepsLog.push(`${res.exit_code}\t${res.timed_out ? 'TIMEOUT' : 'ok'}\t${res.duration_ms}ms\t${step.name}\t${res.command}`);
    const hitlAfter = hitlEntries(ctx.fixture);
    const asked = hitlAfter > hitlBefore;
    hitlBefore = hitlAfter;
    if (res.exit_code !== 0 || res.timed_out || asked) {
      failed++;
      questions.push({
        step: step.name,
        command: res.command,
        exit_code: res.exit_code,
        timed_out: res.timed_out,
        hitl_entries: asked ? hitlAfter : 0,
        output: res.output.slice(0, OUTPUT_CHARS),
      });
    }
  }
  fs.writeFileSync(path.join(outDir, 'steps.log'), stepsLog.join('\n') + '\n');

  // The gate is read for the LAST ride's ref — the one whose close ceremony
  // ran last; its three counts are the record's, never recomputed here.
  const gateRef = RIDES[RIDES.length - 1].slug;
  const gate = gateJson(ctx, gateRef, stepEnv);
  const g = gate.ok ? gate.json : {};
  if (!gate.ok) questions.push({ step: 'nothing-left-behind --json', command: `nothing-left-behind.mjs --ref ${gateRef} --json`, exit_code: gate.exit_code, timed_out: false, hitl_entries: 0, output: String(gate.error).slice(0, OUTPUT_CHARS) });

  const record = {
    v: 1,
    run_utc: runUtc,
    aai_version: aaiVersion(),
    node_major: Number(process.versions.node.split('.')[0]),
    os_family: process.platform === 'win32' ? 'windows' : process.platform,
    steps_total: steps.length,
    steps_failed: failed,
    questions_asked: questions.length,
    questions,
    files_left: gate.ok ? g.files_left : null,
    docs_open: gate.ok ? g.docs_open : null,
    audit_findings: gate.ok ? g.audit_findings : null,
    registry_self_items: gate.ok ? g.registry_self_items : null,
    gate_ref: gateRef,
    tokens_median_last10: tokensMedianLast10(args.metrics ? path.resolve(args.metrics) : null),
    tokens_ceiling: TOKENS_CEILING,
    ci_docs_only_full_run: ciDocsOnlyFullRun(ctx, outDir),
  };
  appendRecord(recordPath, record);
  const ok = failed === 0 && questions.length === 0;
  process.stdout.write(`golden-flow: ${steps.length} step(s), ${failed} failed, ${questions.length} question(s); files_left=${record.files_left} docs_open=${record.docs_open} audit_findings=${record.audit_findings} registry_self_items=${record.registry_self_items}; record -> ${recordPath}\n`);
  for (const q of questions) process.stdout.write(`  question: [${q.step}] exit ${q.exit_code}${q.timed_out ? ' (timed out)' : ''}: ${q.command}\n    ${q.output.split('\n')[0] ?? ''}\n`);
  exit(ok ? 0 : 1);
}

runMain(() => main());
