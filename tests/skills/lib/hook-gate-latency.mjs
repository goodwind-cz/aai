// hook-gate-latency.mjs - latency of the hook gate launcher against the c88cf708 script
// (docs/specs/SPEC-0283-spec-hook-gate-on-node.md D-MEASURE, Spec-AC-08 / TEST-3507).
//
// usage: node tests/skills/lib/hook-gate-latency.mjs [--n 40] [--launcher <script>] [--baseline <script>]
//
// Both scripts run through spawnSync('bash', [script, gate]) with the payload redirected from a file, in one scratch
// fixture holding this repository's merge layer, ALTERNATING the two per iteration (the first of each pair swaps every
// round) so host load lands on both alike. Prints p50 and p95 per case. Fails (exit 1) when
//   - a pre-filtered case has launcher p50 > 0.35 x baseline p50, or
//   - a delegated case has launcher p50 > 1.15 x baseline p50 + 3 ms, or
//   - AAI_HOOK_GATE_REFERENCE_HOST=1 and a launcher p95 exceeds 10 ms (pre-filtered) or 50 ms (delegated).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const BASE_SHA = 'c88cf708';
const arg = (name, dflt) => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : dflt; };
const N = Number(arg('--n', '40'));
const launcher = path.resolve(arg('--launcher', path.join(ROOT, '.aai/scripts/claude-hook-gate.sh')));
const WARMUP = 3;

const tmp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'aai-hgate-lat-')));
process.on('exit', () => fs.rmSync(tmp, { recursive: true, force: true }));

let baseline = arg('--baseline', '');
if (!baseline) {
  const r = spawnSync('git', ['show', `${BASE_SHA}:.aai/scripts/claude-hook-gate.sh`], { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 24 });
  if (r.status !== 0) { console.error(`FAIL: git show ${BASE_SHA}:.aai/scripts/claude-hook-gate.sh failed (a full-history checkout is required): ${r.stderr}`); process.exit(1); }
  baseline = path.join(tmp, 'claude-hook-gate.base.sh');
  fs.writeFileSync(baseline, r.stdout, { mode: 0o755 });
}

// The fixture: a scratch project with the merge layer, a STATE.yaml and no tick log.
const project = path.join(tmp, 'project');
for (const f of ['merge-policy.mjs', 'lane-gate.mjs', 'hook-gate.mjs', 'lib/cli-pipe-guard.mjs', 'lib/pr-sweep.mjs', 'lib/roadmap-model.mjs']) {
  const src = path.join(ROOT, '.aai/scripts', f);
  if (!fs.existsSync(src)) continue;
  fs.mkdirSync(path.dirname(path.join(project, '.aai/scripts', f)), { recursive: true });
  fs.copyFileSync(src, path.join(project, '.aai/scripts', f));
}
fs.mkdirSync(path.join(project, 'docs/ai'), { recursive: true });
fs.writeFileSync(path.join(project, 'docs/ai/STATE.yaml'), 'active_work_items:\n  - ref_id: X-1\n    status: in_progress\n');

const cases = [
  { name: 'commit ls -la docs/specs', gate: 'commit', cmd: 'ls -la docs/specs', kind: 'pre-filtered', exit: 0 },
  { name: 'merge ls -la docs/specs', gate: 'merge', cmd: 'ls -la docs/specs', kind: 'pre-filtered', exit: 0 },
  { name: 'state-dump ls -la docs/specs', gate: 'state-dump', cmd: 'ls -la docs/specs', kind: 'pre-filtered', exit: 0 },
  { name: 'commit git status --short', gate: 'commit', cmd: 'git status --short', kind: 'pre-filtered', exit: 0 },
  { name: 'merge git log --oneline -5', gate: 'merge', cmd: 'git log --oneline -5', kind: 'pre-filtered', exit: 0 },
  { name: 'merge git merge feature-x', gate: 'merge', cmd: 'git merge feature-x', kind: 'delegated', exit: 2 },
  { name: 'state-dump yaml.dump STATE.yaml', gate: 'state-dump', cmd: 'python3 -c "import yaml; yaml.dump(d, open(\'docs/ai/STATE.yaml\',\'w\'))"', kind: 'delegated', exit: 2 },
  { name: 'stop-nudge in-progress STATE', gate: 'stop-nudge', cmd: '', kind: 'delegated', exit: 0 },
];
for (const c of cases) {
  c.file = path.join(tmp, `${c.gate}-${cases.indexOf(c)}.json`);
  fs.writeFileSync(c.file, JSON.stringify(c.gate === 'stop-nudge' ? { hook_event_name: 'Stop' } : { hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: c.cmd } }));
}

const env = { PATH: process.env.PATH, HOME: os.tmpdir(), CLAUDE_PROJECT_DIR: project };
function once(script, c) {
  const fd = fs.openSync(c.file, 'r');
  const t0 = process.hrtime.bigint();
  const r = spawnSync('bash', [script, c.gate], { cwd: project, env, stdio: [fd, 'ignore', 'ignore'] });
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  fs.closeSync(fd);
  return { ms, status: r.status };
}
const pct = (xs, p) => { const s = [...xs].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.ceil(p * s.length) - 1)]; };

const failures = [];
const rows = [];
// measure(c): one interleaved run of N pairs; a wrong exit status is recorded as a failure.
function measure(c) {
  for (let i = 0; i < WARMUP; i += 1) { once(launcher, c); once(baseline, c); }
  const nu = []; const ba = [];
  for (let i = 0; i < N; i += 1) {
    const order = i % 2 === 0 ? [['n', launcher], ['b', baseline]] : [['b', baseline], ['n', launcher]];
    for (const [k, script] of order) {
      const r = once(script, c);
      if (r.status !== c.exit) failures.push(`${c.name}: ${k === 'n' ? 'launcher' : 'baseline'} exited ${r.status} (want ${c.exit})`);
      (k === 'n' ? nu : ba).push(r.ms);
    }
  }
  return { c, bp50: pct(ba, 0.5), bp95: pct(ba, 0.95), np50: pct(nu, 0.5), np95: pct(nu, 0.95) };
}
// ratioProblem(row): the Spec-AC-08 ratio bound the row breaks, or ''.
function ratioProblem(row) {
  const { c } = row;
  const ratio = row.np50 / row.bp50;
  if (c.kind === 'pre-filtered' && !(row.np50 <= 0.35 * row.bp50)) return `${c.name}: launcher p50 ${row.np50.toFixed(1)} ms > 0.35 x baseline p50 ${row.bp50.toFixed(1)} ms (ratio ${ratio.toFixed(2)})`;
  if (c.kind === 'delegated' && !(row.np50 <= 1.15 * row.bp50 + 3)) return `${c.name}: launcher p50 ${row.np50.toFixed(1)} ms > 1.15 x baseline p50 ${row.bp50.toFixed(1)} ms + 3 ms`;
  return '';
}
for (const c of cases) {
  let row = measure(c);
  // A failing ratio is measured once more on a loaded runner; the second measurement decides.
  if (ratioProblem(row)) { console.log(`INFO: ${ratioProblem(row)}; measuring once more`); row = measure(c); }
  rows.push(row);
  if (ratioProblem(row)) failures.push(ratioProblem(row));
  if (process.env.AAI_HOOK_GATE_REFERENCE_HOST === '1') {
    const bound = c.kind === 'pre-filtered' ? 10 : 50;
    if (!(row.np95 <= bound)) failures.push(`${c.name}: reference host: launcher p95 ${row.np95.toFixed(1)} ms > ${bound} ms`);
  }
}

console.log(`hook gate latency, n=${N} per case, interleaved (launcher ${path.relative(ROOT, launcher) || launcher} vs ${BASE_SHA} script), ms`);
console.log('case'.padEnd(34), 'kind'.padEnd(13), 'base p50', 'base p95', 'new p50', 'new p95', 'ratio');
for (const r of rows) console.log(r.c.name.padEnd(34), r.c.kind.padEnd(13), r.bp50.toFixed(1).padStart(8), r.bp95.toFixed(1).padStart(8), r.np50.toFixed(1).padStart(7), r.np95.toFixed(1).padStart(7), (r.np50 / r.bp50).toFixed(2).padStart(5));
if (process.env.AAI_HOOK_GATE_REFERENCE_HOST === '1') console.log('reference-host p95 bounds checked: pre-filtered <= 10 ms, delegated <= 50 ms');
if (failures.length) { for (const f of failures) console.error(`FAIL: ${f}`); process.exit(1); }
console.log('PASS: every ratio bound holds');
