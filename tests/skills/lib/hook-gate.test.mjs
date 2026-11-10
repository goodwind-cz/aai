// hook-gate.test.mjs - node:test cases for .aai/scripts/hook-gate.mjs and its launcher .aai/scripts/claude-hook-gate.sh
// (docs/specs/SPEC-0283-spec-hook-gate-on-node.md, TEST-3500 to TEST-3506; one case per drift DG-01..DG-09).
// Every case works in fresh temp directories: scratch git repositories, a stub gh first on PATH that logs its argv,
// and payloads written to files and redirected in (no live pipe). No case calls a real gh, az or network.
// The baseline script is read with `git show c88cf708:.aai/scripts/claude-hook-gate.sh`.
import { describe, test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
// The module may not exist yet (RED on the baseline): every case must fail on its own assertion.
const M = await import('../../../.aai/scripts/hook-gate.mjs').catch(() => ({}));

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../..');
const MODULE = path.join(ROOT, '.aai/scripts/hook-gate.mjs');
// AAI_HOOK_GATE_LAUNCHER points the launcher cases at another script (used to capture RED on the baseline).
const LAUNCHER = process.env.AAI_HOOK_GATE_LAUNCHER || path.join(ROOT, '.aai/scripts/claude-hook-gate.sh');
const BASE_SHA = 'c88cf708';
const TMP = [];
after(() => { for (const d of TMP) fs.rmSync(d, { recursive: true, force: true }); });

const ARTICLE7 = [
  'Merge denied: constitution article 7 (operator-only merge) — the agent never merges;',
  "the PR ceremony ends at 'gh pr create' (.aai/SKILL_PR.prompt.md step 6).",
  'If the OPERATOR explicitly directed this merge, run it with AAI_OPERATOR_MERGE=1.',
  '(Guardrail, not a security boundary — setting the marker without operator direction',
  'is a constitution violation.)',
].map((l) => `${l}\n`).join('');
const NUDGE = 'AAI wrap-up nudge: docs/ai/STATE.yaml still has an in_progress work item and no loop tick was logged after the last state change. Consider /aai-wrap-up (capture learnings, close the item) or log the tick via node .aai/scripts/state.mjs log-tick. (Reminder only — never blocks.)\n';
const NONODE = `${ARTICLE7}merge-policy: evaluator unavailable: node not found (the command could not be read)\n`;

const scratch = (label) => {
  const d = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), `aai-hgate-${label}-`)));
  TMP.push(d);
  return d;
};
// A PATH directory holding node and every executable of /usr/bin and /bin except gh, so a runner that
// ships gh in /usr/bin (GitHub-hosted images do) still gets a PATH on which gh is absent.
const ghFreeDir = (label) => {
  const d = scratch(label);
  fs.symlinkSync(process.execPath, path.join(d, 'node'));
  for (const dir of ['/usr/bin', '/bin']) {
    let names = [];
    try { names = fs.readdirSync(dir); } catch { continue; }
    for (const n of names) {
      if (n === 'gh' || n === 'node') continue;
      try { fs.symlinkSync(path.join(dir, n), path.join(d, n)); } catch { /* already linked from the other dir */ }
    }
  }
  return d;
};
const git = (cwd, ...args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
};
const initRepo = (dir) => {
  fs.mkdirSync(dir, { recursive: true });
  git(dir, 'init', '-q', '-b', 'main');
  git(dir, 'config', 'user.email', 'fixture@example.invalid');
  git(dir, 'config', 'user.name', 'fixture');
  git(dir, 'config', 'commit.gpgsign', 'false');
  git(dir, 'config', 'core.autocrlf', 'false');
};
const commitAll = (dir, msg) => { git(dir, 'add', '-A'); git(dir, 'commit', '-q', '-m', msg); };
const put = (file, text, mode) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text, mode ? { mode } : undefined);
};

let baseScript = null;
const baseline = () => {
  if (baseScript) return baseScript;
  const r = spawnSync('git', ['show', `${BASE_SHA}:.aai/scripts/claude-hook-gate.sh`], { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 24 });
  assert.equal(r.status, 0, `git show ${BASE_SHA}:.aai/scripts/claude-hook-gate.sh failed (a full-history checkout is required): ${r.stderr}`);
  baseScript = path.join(scratch('base'), 'claude-hook-gate.base.sh');
  put(baseScript, r.stdout, 0o755);
  return baseScript;
};

// A stub gh: logs argv, answers the `pr view` shapes the gates use and any merge-queue graphql read.
const GH_STUB = `#!/bin/sh
printf '%s\\n' "$*" >> "$STUB_DIR/gh.log"
if [ "$1" = api ] && [ "$2" = graphql ]; then echo '{"data":{"repository":{"pullRequest":{"isMergeQueueEnabled":false}}}}'; exit 0; fi
[ "$1" = pr ] && [ "$2" = view ] || exit 1
shift 2
if [ "\${1:-}" = "--json" ]; then
  [ -n "\${STUB_CURRENT_PR:-}" ] && { echo "$STUB_CURRENT_PR"; exit 0; }
  exit 1
fi
t="$1"
case "$*" in
  *"-q .headRefOid"*) [ -f "$STUB_DIR/pr-$t.json" ] && sed -n 's/.*"headRefOid":"\\([^"]*\\)".*/\\1/p' "$STUB_DIR/pr-$t.json" && exit 0; exit 1 ;;
  *"-q .number"*)
    case "$t" in feature-branch) echo 44; exit 0 ;; https://*) echo "\${t##*/}"; exit 0 ;; esac
    exit 1 ;;
esac
[ -f "$STUB_DIR/pr-$t.json" ] && { cat "$STUB_DIR/pr-$t.json"; exit 0; }
exit 1
`;
const PRECHECKS = `#!/usr/bin/env bash
if [ -f "$(dirname "$0")/../../.checks-fail" ]; then
  i=0
  while [ "$i" -lt 30 ]; do
    i=$((i + 1))
    if [ $((i % 2)) -eq 0 ]; then echo "check line $i" >&2; else echo "check line $i"; fi
  done
  exit 1
fi
exit 0
`;

// A project fixture: a git repository with the merge layer, a stub gh and a stub pre-commit-checks script.
const mergeLayer = ['merge-policy.mjs', 'lane-gate.mjs', 'lib/cli-pipe-guard.mjs', 'lib/pr-sweep.mjs', 'lib/roadmap-model.mjs'];
function makeProject(label, { module = false } = {}) {
  const dir = scratch(label);
  initRepo(dir);
  const stub = path.join(dir, '.stub');
  put(path.join(stub, 'gh'), GH_STUB, 0o755);
  for (const f of mergeLayer) put(path.join(dir, '.aai/scripts', f), fs.readFileSync(path.join(ROOT, '.aai/scripts', f)));
  if (module) put(path.join(dir, '.aai/scripts/hook-gate.mjs'), fs.readFileSync(MODULE));
  put(path.join(dir, '.aai/scripts/pre-commit-checks.sh'), PRECHECKS, 0o755);
  put(path.join(dir, 'docs/ai/EVENTS.jsonl'), '');
  const sweep = (pr, lane, outcome) => `${JSON.stringify({ v: 1, ts: '2026-01-01T00:00:00.000Z', actor: 't', event: 'pr_sweep', ref: 'hg-ride', payload: { pr, lane, reviewer_bots: 'none', threads_seen: 0, threads_unresolved: 0, outcome } })}\n`;
  fs.appendFileSync(path.join(dir, 'docs/ai/EVENTS.jsonl'), sweep(42, 'heavy', 'internal_substituted') + sweep(43, 'fast', 'skipped_fast_lane'));
  fs.writeFileSync(path.join(dir, '.gitignore'), '.stub/\n');
  commitAll(dir, 'base');
  return { dir, stub, bin: stub };
}

// The lane fixture of hooks-overlay TEST-1520: a policy with lane-x (docs), a base and a head commit, PR 71 and 72.
const LANE_X = 'AAI_LANEX1520_MERGE';
function makeLaneProject() {
  const p = makeProject('lane');
  const { dir, stub } = p;
  put(path.join(dir, 'docs/ai/merge-policy.yaml'), [
    'version: 1', 'kinds:', '  - id: docs', '    globs: ["docs/**"]', 'lanes:', '  - id: lane-x',
    '    decision_ref: t1520-x@2026-10-03T22:01:00Z', '    decision_match: "MERGE LANE t1520 x"', '    signed_by: owner-login',
    '    kinds: [docs]', '    merge_reaches: nothing', '    max_ceremony: 3', `    marker: ${LANE_X}`, '',
  ].join('\n'));
  put(path.join(dir, 'docs/ai/decisions.jsonl'), `${JSON.stringify({ type: 'hitl_decision', ref_id: 't1520-x', ts: '2026-10-03T22:01:00Z', owner_signoff: true, actor: 'owner-login', decision: 'MERGE LANE t1520 x approved' })}\n`);
  put(path.join(dir, 'docs/base.md'), 'base\n');
  commitAll(dir, 'lane base');
  const base = git(dir, 'rev-parse', 'HEAD').trim();
  put(path.join(dir, 'docs/changed.md'), 'a docs change\n');
  commitAll(dir, 'lane head');
  const head = git(dir, 'rev-parse', 'HEAD').trim();
  const prJson = (n, checks) => `${JSON.stringify({ number: n, state: 'OPEN', isDraft: false, baseRefName: 'main', baseRefOid: base, headRefOid: head, reviews: [], mergeStateStatus: 'CLEAN', autoMergeRequest: null, statusCheckRollup: checks, body: '' })}\n`;
  put(path.join(stub, 'pr-71.json'), prJson(71, [{ state: 'SUCCESS' }]));
  put(path.join(stub, 'pr-72.json'), prJson(72, [{ __typename: 'CheckRun', status: 'COMPLETED', conclusion: 'FAILURE' }]));
  const ev = path.join(dir, 'docs/ai/EVENTS.jsonl');
  for (const pr of [71, 72]) fs.appendFileSync(ev, `${JSON.stringify({ v: 1, ts: '2026-01-01T00:00:00.000Z', actor: 't', event: 'pr_sweep', ref: 'hg-lane', payload: { pr, lane: 'heavy', reviewer_bots: 'none', threads_seen: 0, threads_unresolved: 0, outcome: 'internal_substituted' } })}\n`);
  return { ...p, head };
}

const payloadObj = (command, cwd) => ({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command }, ...(cwd ? { cwd } : {}) });
// gate(script, project, name, payload, opts): the payload is a command text, an object or a raw string; it is written to a file.
function gate(script, project, name, payload, opts = {}) {
  const dir = scratch('pl');
  const file = path.join(dir, 'payload.json');
  const text = typeof payload === 'string' && opts.raw ? payload : JSON.stringify(typeof payload === 'string' ? payloadObj(payload, opts.payloadCwd) : payload);
  fs.writeFileSync(file, text);
  const fd = fs.openSync(file, 'r');
  const env = {
    PATH: opts.path || `${project.bin}:${process.env.PATH}`, HOME: os.tmpdir(), CLAUDE_PROJECT_DIR: project.dir, STUB_DIR: project.stub, ...opts.env,
  };
  if (opts.bounded) return runBounded(script, name, file, fd, { cwd: opts.cwd || project.dir, env }, opts.bounded);
  const r = spawnSync('bash', [script, name], { cwd: opts.cwd || project.dir, env, stdio: [fd, 'pipe', 'pipe'], encoding: 'utf8', timeout: 120000, maxBuffer: 1 << 26 });
  fs.closeSync(fd);
  return { rc: r.status, stdout: r.stdout, stderr: r.stderr };
}

// A launcher run in its own process group, killed as a group at the bound: the bash and the node under it both go,
// so a regression that makes the module slow fails the case and leaves no orphan process behind.
const BOUNDED_RUNNER = `
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const [script, name, file, ms] = process.argv.slice(1);
const t0 = process.hrtime.bigint();
const c = spawn('bash', [script, name], { stdio: [fs.openSync(file, 'r'), 'pipe', 'pipe'], detached: true });
let o = ''; let e = ''; let timedOut = false;
c.stdout.on('data', (d) => { o += d; }); c.stderr.on('data', (d) => { e += d; });
const t = setTimeout(() => { timedOut = true; try { process.kill(-c.pid, 'SIGKILL'); } catch { /* gone */ } }, Number(ms));
c.on('close', (rc) => { clearTimeout(t); process.stdout.write(JSON.stringify({ rc: timedOut ? null : rc, stdout: o, stderr: e, timedOut, ms: Number(process.hrtime.bigint() - t0) / 1e6 })); });
`;
function runBounded(script, name, file, fd, { cwd, env }, ms) {
  const r = spawnSync(process.execPath, ['-e', BOUNDED_RUNNER, script, name, file, String(ms)], { cwd, env, encoding: 'utf8', timeout: ms + 20000, maxBuffer: 1 << 26 });
  fs.closeSync(fd);
  if (r.error || r.status !== 0) return { rc: null, stdout: '', stderr: String(r.error || r.stderr), timedOut: true, ms: ms + 20000 };
  return JSON.parse(r.stdout);
}

// The in-process deps: the real file system and process spawning, with the stub gh on PATH.
function realDeps(project, env) {
  const which = (n) => env.PATH.split(path.delimiter).some((d) => { try { return fs.statSync(path.join(d, n)).isFile(); } catch { return false; } });
  return {
    which,
    exists: (p) => { try { return fs.statSync(p).isFile(); } catch { return false; } },
    readFile: (p) => fs.readFileSync(p, 'utf8'),
    mtimeMs: (p) => fs.statSync(p).mtimeMs,
    run: (cmd, args, o = {}) => {
      const r = o.merge
        ? spawnSync('sh', ['-c', 'exec "$@" 2>&1', 'sh', cmd, ...args], { cwd: o.cwd, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
        : spawnSync(cmd, args, { cwd: o.cwd, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      return { status: r.error ? null : r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
    },
  };
}
const need = (name) => { assert.equal(typeof M[name], 'function', `hook-gate.mjs must export ${name}`); return M[name]; };
function decideIn(project, name, command, { env = {}, cwd } = {}) {
  const decide = need('decide');
  const full = { PATH: `${project.bin}:${process.env.PATH}`, HOME: os.tmpdir(), STUB_DIR: project.stub, ...env };
  const raw = typeof command === 'string' ? JSON.stringify(payloadObj(command, cwd)) : JSON.stringify(command);
  return decide(name, { payload: raw, env: full, root: project.dir }, realDeps(project, full));
}

// ---------------------------------------------------------------------------
describe('TEST-3500 module seam', () => {
  test('TEST-3500 importing the module has no side effect and exposes the five exports', () => {
    const cwd = scratch('seam');
    const url = `file://${MODULE}`;
    const code = `import(${JSON.stringify(url)}).then((m) => { process.stdout.write(''); process.exitCode = ['parsePayload','isMergeCommand','mergeSegment','checkMergeShape','decide'].every((k) => typeof m[k] === 'function') ? 0 : 7; });`;
    const r = spawnSync(process.execPath, ['-e', code], { cwd, encoding: 'utf8' });
    assert.equal(r.status, 0, `the module must exist and export the five functions: ${r.stderr}`);
    assert.equal(r.stdout, '');
    assert.equal(r.stderr, '');
    assert.deepEqual(fs.readdirSync(cwd), []);
  });

  test('TEST-3500 the CLI fails open on an unknown gate, malformed JSON and a throwing run, and never writes stdout', () => {
    assert.ok(fs.existsSync(MODULE), 'hook-gate.mjs must exist');
    const project = makeProject('seam-cli');
    const cli = (args, input, env = {}) => spawnSync(process.execPath, [MODULE, ...args], {
      cwd: project.dir, input, encoding: 'utf8', env: { PATH: process.env.PATH, CLAUDE_PROJECT_DIR: project.dir, ...env },
    });
    for (const [args, input] of [[['bogus'], '{"tool_input":{"command":"git merge x"}}'], [[], ''], [['merge'], '{not json'], [['commit'], ''], [['state-dump'], 'null']]) {
      const r = cli(args, input);
      assert.equal(r.status, 0, `${args} ${input}`);
      assert.equal(r.stdout, '');
      assert.equal(r.stderr, '');
    }
    const decide = need('decide');
    assert.deepEqual(decide('bogus', { payload: '{}', env: {}, root: '.' }, {}), { code: 0, stderr: '' });
    const deny = cli(['merge'], JSON.stringify(payloadObj('git merge x')));
    assert.equal(deny.status, 2);
    assert.equal(deny.stdout, '');
    assert.equal(deny.stderr, ARTICLE7);
    const code = `import(${JSON.stringify(`file://${MODULE}`)}).then((m) => {
      const deps = { which: () => true, exists: () => true, readFile: () => '', mtimeMs: () => 0, run: () => { throw new Error('boom'); } };
      process.exitCode = m.main(['commit'], { CLAUDE_PROJECT_DIR: '.' }, deps, () => JSON.stringify({ tool_input: { command: 'git commit -m x' } }));
    });`;
    const t = spawnSync(process.execPath, ['-e', code], { cwd: project.dir, encoding: 'utf8' });
    assert.equal(t.status, 0, `a throwing deps.run must fail open: ${t.stderr}`);
    assert.equal(t.stdout, '');
    assert.equal(t.stderr, '');
  });
});

// ---------------------------------------------------------------------------
// The differential corpus (TEST-3501): the same payload, env and cwd through the baseline script and the launcher.
function buildCorpus() {
  const rows = [];
  const add = (id, gate, cmd, o = {}) => rows.push({ id, gate, cmd, ...o });
  // commit gate, checks passing and failing
  const commits = ['git commit -m x', 'git commit', 'git -C sub commit -m x', 'git -c user.name=a commit -m x', 'git add -A && git commit -m x',
    'echo hi', 'git status', 'git commit-tree HEAD', 'ls\ngit commit -m second-line', 'echo "git commit"'];
  for (const c of commits) for (const checks of ['pass', 'fail']) add(`commit/${checks}: ${c}`, 'commit', c, { checks });
  add('commit/no checks script', 'commit', 'git commit -m x', { checks: 'missing' });
  add('commit/empty command', 'commit', '');
  // merge gate with and without the operator marker
  const merges = ['git merge feature-x', 'gh pr merge 42 --squash', 'gh pr merge --squash', 'git -C ../wt merge feat-x', 'echo AAI_X_MERGE=1 && gh pr merge 42',
    'AAI_X_MERGE=0 gh pr merge 42', 'ls -la docs/specs', 'git status --short', 'git log --oneline -5', 'gh pr list', 'git merger x', 'gh pr merge feature-branch --squash',
    'gh pr merge https://github.com/o/r/pull/9', 'gh pr merge "42"', 'gh pr merge --subject "fix 123" 42', 'git commit -m "explain git merge handling"',
    'echo gh pr merge 5', 'ls\nls\ngh pr merge 7', 'gh pr merge 43 --squash', 'gh pr merge 42 --squash && echo done', 'gh pr merge -R o/r 42'];
  for (const c of merges) for (const op of [false, true]) add(`merge/${op ? 'operator' : 'plain'}: ${c}`, 'merge', c, { env: op ? { AAI_OPERATOR_MERGE: '1' } : {} });
  add('merge/bare with a current-branch PR', 'merge', 'gh pr merge --squash', { env: { AAI_OPERATOR_MERGE: '1', STUB_CURRENT_PR: '42' } });
  add('merge/bare with a fast-lane current PR', 'merge', 'gh pr merge --squash', { env: { AAI_OPERATOR_MERGE: '1', STUB_CURRENT_PR: '43' } });
  add('merge/escaped payload', 'merge', 'gh pr merge 5', { raw: '{"tool_input":{"command":"gh\\u0020pr merge 5"}}' });
  // lane path (real merge-policy.mjs and lane-gate.mjs, stub gh)
  const mh = (head) => `--match-head-commit ${head}`;
  const lane = [
    ['env marker allows', (h) => `gh pr merge 71 --squash ${mh(h)}`, { [LANE_X]: '1' }], ['prefix marker allows', (h) => `${LANE_X}=1 gh pr merge 71 --squash ${mh(h)}`, {}],
    ['no marker', (h) => `gh pr merge 71 --squash ${mh(h)}`, {}], ['evaluator denial', (h) => `gh pr merge 72 --squash ${mh(h)}`, { [LANE_X]: '1' }],
    ['git merge with marker', () => 'git merge feature-x', { [LANE_X]: '1' }], ['auto flag', (h) => `gh pr merge 71 --auto ${mh(h)}`, { [LANE_X]: '1' }],
    ['missing match head', () => 'gh pr merge 71 --squash', { [LANE_X]: '1' }], ['mismatched match head', () => 'gh pr merge 71 --squash --match-head-commit 0000000000000000000000000000000000000f', { [LANE_X]: '1' }],
    ['chained second merge', () => 'gh pr merge 71 && gh pr merge 72', { [LANE_X]: '1' }], ['command substitution', () => 'gh pr merge $(echo 72)', { [LANE_X]: '1' }],
    ['other repo via -R', () => 'gh pr merge 71 -R other/repo', { [LANE_X]: '1' }], ['non-marker prefix', () => `GH_REPO=other/repo ${LANE_X}=1 gh pr merge 71`, {}],
    ['marker value not 1', () => 'gh pr merge 71', { [LANE_X]: 'yes' }], ['operator marker as prefix', () => 'AAI_OPERATOR_MERGE=1 gh pr merge 71', {}],
    ['marker in an earlier command', () => `${LANE_X}=1 true && gh pr merge 71`, {}], ['quoted flag', (h) => `gh pr merge 71 '--admin' ${mh(h)}`, { [LANE_X]: '1' }],
    ['no pr number', (h) => `gh pr merge --squash ${mh(h)}`, { [LANE_X]: '1' }],
  ];
  for (const [name, mk, env] of lane) add(`lane/${name}`, 'merge', mk, { project: 'lane', env });
  add('lane/cwd in another repository', 'merge', (h) => `gh pr merge 71 ${mh(h)}`, { project: 'lane', env: { [LANE_X]: '1' }, otherCwd: true });
  // state-dump gate
  const dumps = ['python3 -c "import yaml; yaml.dump(d, open(\'docs/ai/STATE.yaml\',\'w\'))"', 'python3 -c "yaml.safe_dump(d, open(\'docs/ai/STATE.yaml\',\'w\'))"',
    'python3 -c "yaml.dump_all(d, open(\'docs/ai/STATE.yaml\',\'w\'))"', 'python3 -c "yaml.dump(d)"', 'cat docs/ai/STATE.yaml', 'ls\npython3 -c "yaml.dump(x)" > docs/ai/STATE.yaml',
    'echo "yaml.dump STATE.yaml"', 'ls -la docs/specs'];
  for (const c of dumps) add(`state-dump: ${c}`, 'state-dump', c);
  // stop-nudge fixtures
  const states = [
    ['no STATE', null, null], ['in_progress, no ticks', 'active_work_items:\n  - ref_id: X-1\n    status: in_progress\n', null],
    ['in_progress, newer ticks', 'active_work_items:\n  - ref_id: X-1\n    status: in_progress\n', 'newer'], ['in_progress, older ticks', 'active_work_items:\n  - ref_id: X-1\n    status: in_progress\n', 'older'],
    ['done only', 'active_work_items:\n  - ref_id: X-1\n    status: done\n', null], ['tab indented', 'items:\n\tstatus: in_progress\n', null],
    ['unindented', 'status: in_progress\n', null], ['no space after colon', 'items:\n  status:in_progress\n', null], ['blank then status', 'a:\n\n  status: in_progress\n', null],
  ];
  for (const [name, state, ticks] of states) add(`stop-nudge: ${name}`, 'stop-nudge', '', { state, ticks, payload: '{}' });
  // NUL inside the command: bash drops it in a command substitution, so the module drops it too (parity, no drift)
  add('nul in git merge', 'merge', 'git\u0000 merge x');
  add('nul in gh pr merge', 'merge', 'gh pr merge\u0000 5');
  add('nul before a chained merge', 'merge', 'ls\u0000; gh pr merge 5');
  add('nul in git commit', 'commit', 'git\u0000 commit -m x', { checks: 'fail' });
  add('nul in a state dump', 'state-dump', 'python3 -c "yaml.dump(d)"\u0000 > docs/ai/STATE.yaml');
  // rows tagged with the drift whose decision changes them: skipped by name, never compared
  add('azure platform merge', 'merge', 'node .aai/scripts/platform.mjs merge --pr 7 --expect-head abc --operator-merge', { tag: 'DG-01' });
  add('azure az completed', 'merge', 'az repos pr update --id 7 --status completed', { tag: 'DG-01' });
  add('inherited pipefail merge', 'merge', `gh pr merge 42 --squash\n${'x\n'.repeat(8000)}`, { tag: 'DG-02', env: { SHELLOPTS: 'braceexpand:hashall:interactive-comments:pipefail' } });
  add('nbsp between words', 'merge', 'gh\u00a0pr merge 5', { tag: 'DG-06' });
  // U+FEFF is not white space to bash (DG-10): parity rows, untagged, on the plain and the operator-marker path
  for (const c of ['gh\ufeffpr merge 5', 'gh pr merge 42\ufeff', 'gh pr merge 42\ufeff --squash', 'gh pr merge \ufeff42', 'gh pr merge 42\ufeffx',
    'gh pr merge 42 --squash --match-head-commit\ufeffabc123']) for (const op of [false, true]) add(`bom: ${op ? 'operator' : 'plain'}: ${c}`, 'merge', c, { env: op ? { AAI_OPERATOR_MERGE: '1' } : {} });
  return rows;
}
const CORPUS = buildCorpus();

function prepRow(project, row) {
  const checksFlag = path.join(project.dir, '.checks-fail');
  fs.rmSync(checksFlag, { force: true });
  const checks = path.join(project.dir, '.aai/scripts/pre-commit-checks.sh');
  if (row.checks === 'fail') fs.writeFileSync(checksFlag, '');
  if (row.checks === 'missing') fs.rmSync(checks, { force: true }); else if (!fs.existsSync(checks)) put(checks, PRECHECKS, 0o755);
  const state = path.join(project.dir, 'docs/ai/STATE.yaml');
  const ticks = path.join(project.dir, 'docs/ai/LOOP_TICKS.jsonl');
  fs.rmSync(state, { force: true });
  fs.rmSync(ticks, { force: true });
  if (row.state != null) {
    fs.writeFileSync(state, row.state);
    const old = new Date(Date.now() - 100000);
    fs.utimesSync(state, old, old);
    if (row.ticks) {
      fs.writeFileSync(ticks, '{}\n');
      const t = row.ticks === 'newer' ? new Date() : new Date(Date.now() - 200000);
      fs.utimesSync(ticks, t, t);
    }
  }
}

describe('TEST-3501 differential parity with the baseline script', () => {
  test('TEST-3501 launcher and baseline script agree on exit code and bytes for every untagged corpus row', () => {
    assert.ok(fs.existsSync(MODULE), 'hook-gate.mjs must exist');
    const base = baseline();
    const plain = makeProject('parity-plain');
    const lane = makeLaneProject();
    const other = scratch('other-repo');
    initRepo(other);
    let compared = 0; let denies = 0; let allows = 0;
    const problems = [];
    for (const row of CORPUS) {
      if (row.tag) continue;
      const project = row.project === 'lane' ? lane : plain;
      prepRow(project, row);
      const cmd = typeof row.cmd === 'function' ? row.cmd(lane.head) : row.cmd;
      const rawText = row.raw || row.payload;
      const opts = { env: row.env || {}, raw: Boolean(rawText), payloadCwd: row.project === 'lane' ? (row.otherCwd ? other : project.dir) : undefined };
      const run = (script) => gate(script, project, row.gate, rawText ?? cmd, opts);
      const a = run(base);
      // N13: bash 5 warns on stderr about a NUL dropped from a command substitution; the module drops it silently
      a.stderr = a.stderr.replace(/^[^\n]*: warning: command substitution: ignored null byte in input\n/gm, '');
      const b = run(LAUNCHER);
      compared += 1;
      if (a.rc === 2) denies += 1; else if (a.rc === 0) allows += 1;
      if (a.rc !== b.rc) problems.push(`${row.id}: exit ${b.rc}, baseline ${a.rc}\n${b.stderr}`);
      else if (a.stderr !== b.stderr) problems.push(`${row.id}: stderr differs\n--- baseline\n${a.stderr}--- launcher\n${b.stderr}`);
      else if (a.stdout !== b.stdout) problems.push(`${row.id}: stdout differs\n--- baseline\n${a.stdout}--- launcher\n${b.stdout}`);
    }
    assert.deepEqual(problems, []);
    assert.ok(compared >= 60, `only ${compared} rows were compared (at least 60 are required)`);
    assert.ok(denies >= 15 && allows >= 15, `the corpus must exercise both verdicts (deny ${denies}, allow ${allows})`);
  });
});

// ---------------------------------------------------------------------------
describe('TEST-3503 Azure merge forms', () => {
  const FORMS = [
    ['platform.mjs', (n) => `node .aai/scripts/platform.mjs merge ${n ? `--pr ${n} ` : ''}--expect-head abc --operator-merge`],
    ['az repos', (n) => `az repos pr update ${n ? `--id ${n} ` : ''}--status completed`],
  ];
  test('DG-01 the Azure merge forms are denied like gh pr merge and judged by gate 2b', () => {
    const project = makeProject('azure');
    for (const [label, mk] of FORMS) {
      // no marker: the article 7 text, through the module and through the launcher
      const d = decideIn(project, 'merge', mk(7));
      assert.equal(d.code, 2, `${label}: no marker must deny`);
      assert.equal(d.stderr, ARTICLE7);
      const l = gate(LAUNCHER, project, 'merge', mk(7));
      assert.equal(l.rc, 2, `${label}: launcher without the marker must deny`);
      assert.equal(l.stderr, ARTICLE7);
      // marker, no sweep record for 7: gate 2b names the number (a fast-lane record for 43 denies)
      const g = gate(LAUNCHER, project, 'merge', mk(43), { env: { AAI_OPERATOR_MERGE: '1' } });
      assert.equal(g.rc, 2, `${label}: a failing sweep record must deny`);
      assert.match(g.stderr, /^Merge denied: no valid post-open review sweep record for PR 43 \(Spec-AC-34, issue 338\)\.\n/);
      assert.match(g.stderr, /Record one with \.aai\/scripts\/append-event\.mjs --event pr_sweep \.\.\., then retry\.\n$/);
      // a valid record (42) and an absent record (7, allowed by SPEC-0227) pass
      assert.equal(gate(LAUNCHER, project, 'merge', mk(42), { env: { AAI_OPERATOR_MERGE: '1' } }).rc, 0, `${label}: valid record`);
      assert.equal(gate(LAUNCHER, project, 'merge', mk(7), { env: { AAI_OPERATOR_MERGE: '1' } }).rc, 0, `${label}: no record is allowed`);
      // no number: the unidentified-PR text with node and lane-gate.mjs, an allow without lane-gate.mjs
      const n = gate(LAUNCHER, project, 'merge', mk(0), { env: { AAI_OPERATOR_MERGE: '1' } });
      assert.equal(n.rc, 2, `${label}: no number must deny`);
      assert.match(n.stderr, /^Merge denied: could not determine which PR this merge command targets\.\nCommand: /);
      const lg = path.join(project.dir, '.aai/scripts/lane-gate.mjs');
      fs.renameSync(lg, `${lg}.away`);
      assert.equal(gate(LAUNCHER, project, 'merge', mk(0), { env: { AAI_OPERATOR_MERGE: '1' } }).rc, 0, `${label}: no lane-gate.mjs allows`);
      fs.renameSync(`${lg}.away`, lg);
      // a lane marker alone never unlocks an Azure form
      const m = gate(LAUNCHER, project, 'merge', mk(7), { env: { [LANE_X]: '1' } });
      assert.equal(m.rc, 2, `${label}: a lane marker alone must deny`);
      assert.match(m.stderr, /\nmerge-policy: lane path refused: lane markers cover gh pr merge only\n$/);
    }
    // the baseline script allowed both forms without the marker (the RED observation)
    for (const [, mk] of FORMS) assert.equal(gate(baseline(), project, 'merge', mk(7)).rc, 0, 'the baseline allows the Azure forms');
    // other az updates and other platform.mjs subcommands are not merge commands
    for (const c of ['az repos pr update --id 7 --status abandoned', 'az repos pr list', 'node .aai/scripts/platform.mjs pr-view --pr 7']) assert.equal(gate(LAUNCHER, project, 'merge', c).rc, 0, c);
  });
});

describe('TEST-3504 inherited pipefail', () => {
  const PIPEFAIL = { SHELLOPTS: 'braceexpand:hashall:interactive-comments:pipefail' };
  const filler = 'filler line\n'.repeat(8001);
  test('DG-02 a command followed by thousands of lines decides on the whole text under an inherited pipefail', () => {
    const project = makeProject('pipefail');
    const merge = gate(LAUNCHER, project, 'merge', `gh pr merge 42 --squash\n${filler}`, { env: PIPEFAIL });
    assert.equal(merge.rc, 2, 'merge followed by 8000 lines must deny');
    assert.equal(merge.stderr, ARTICLE7);
    // an inherited errexit (with or without pipefail) is no different: the old script aborted on the first non-zero status, an allow
    for (const opts of ['braceexpand:errexit:hashall:interactive-comments', 'braceexpand:errexit:hashall:interactive-comments:pipefail']) {
      const m = gate(LAUNCHER, project, 'merge', `gh pr merge 42 --squash\n${filler}`, { env: { SHELLOPTS: opts } });
      assert.equal(m.rc, 2, `merge under SHELLOPTS=${opts} must deny`);
      assert.equal(m.stderr, ARTICLE7);
    }
    const dump = gate(LAUNCHER, project, 'state-dump', `python3 -c 'yaml.dump(open("docs/ai/STATE.yaml"))'\n${filler}`, { env: PIPEFAIL });
    assert.equal(dump.rc, 2, 'state-dump followed by 8000 lines must deny');
    fs.writeFileSync(path.join(project.dir, '.checks-fail'), '');
    const commit = gate(LAUNCHER, project, 'commit', `git commit -m x\n${filler}`, { env: PIPEFAIL });
    assert.equal(commit.rc, 2, 'commit followed by 8000 lines must run the failing checks');
    assert.match(commit.stderr, /^AAI pre-commit gate blocked this commit/);
    fs.rmSync(path.join(project.dir, '.checks-fail'));
    // the baseline observation: the early-closing reader under pipefail let merge and state-dump through
    // Whether the baseline let them through depends on the platform's SIGPIPE/pipefail behaviour (bash 3.2 on macOS
    // did; bash 5.2 on Linux decides either way), so only macOS pins the allow; elsewhere only the new decision is asserted.
    const bm = gate(baseline(), project, 'merge', `gh pr merge 42 --squash\n${filler}`, { env: PIPEFAIL }).rc;
    const bd = gate(baseline(), project, 'state-dump', `python3 -c 'yaml.dump(open("docs/ai/STATE.yaml"))'\n${filler}`, { env: PIPEFAIL }).rc;
    if (process.platform === 'darwin') {
      assert.equal(bm, 0, 'baseline observation: merge allowed');
      assert.equal(bd, 0, 'baseline observation: state-dump allowed');
    } else {
      assert.ok([0, 2].includes(bm) && [0, 2].includes(bd), 'the baseline decides 0 or 2 on this platform');
    }
  });
});

describe('TEST-3521 inherited errexit with a crashing module', () => {
  test('NB-A under an inherited errexit a module exiting 1 still reaches the lane guard and denies', () => {
    const project = makeProject('nba');
    const fake = scratch('nba-fake');
    fs.copyFileSync(LAUNCHER, path.join(fake, 'claude-hook-gate.sh'));
    put(path.join(fake, 'hook-gate.mjs'), 'process.exit(1);\n');
    const be = path.join(fake, 'bashenv');
    put(be, 'set -e\n');
    const script = path.join(fake, 'claude-hook-gate.sh');
    const lane = { AAI_LANEX_MERGE: '1' };
    const trapEnv = (name, body) => { const f = path.join(fake, name); put(f, body); return f; };
    const traps = [
      ['BASH_ENV with an ERR trap exiting 1', { BASH_ENV: trapEnv('trap1', "trap 'exit 1' ERR\n") }],
      ['BASH_ENV with an ERR trap exiting 0', { BASH_ENV: trapEnv('trap0', "trap 'exit 0' ERR\n") }],
      ['BASH_ENV with set -eE and an ERR trap', { BASH_ENV: trapEnv('trapeE', "set -eE; trap 'exit 1' ERR\n") }],
    ];
    const cases = [['no inherited option', {}], ['SHELLOPTS=errexit', { SHELLOPTS: 'errexit' }], ['BASH_ENV with set -e', { BASH_ENV: be }], ...traps];
    // an inherited ERR trap fires on the module's own deny (exit 2); the real launcher must still exit 2
    for (const [label, env] of traps) {
      assert.equal(gate(LAUNCHER, project, 'merge', 'gh pr merge 5', { env }).rc, 2, `${label}: the module's deny stays a deny`);
    }
    for (const [label, env] of cases) {
      const m = gate(script, project, 'merge', 'gh pr merge 5', { env: { ...lane, ...env } });
      assert.equal(m.rc, 2, `${label}: a lane marker and a crashed module must deny`);
      assert.equal(m.stderr, NONODE, label);
      assert.equal(gate(script, project, 'merge', 'gh pr merge 5', { env }).rc, 0, `${label}: no marker fails open`);
    }
  });
});

describe('TEST-3505 kept decisions', () => {
  test('DG-03 text that only names a merge command is denied', () => {
    const project = makeProject('dg03');
    for (const c of ['git commit -m "explain git merge handling"', 'echo gh pr merge 5']) {
      const d = decideIn(project, 'merge', c);
      assert.equal(d.code, 2, c);
      assert.equal(d.stderr, ARTICLE7, c);
    }
  });

  test('DG-04 the operator marker as a command prefix is denied, only the hook environment counts', () => {
    const project = makeProject('dg04');
    const d = decideIn(project, 'merge', 'AAI_OPERATOR_MERGE=1 gh pr merge 42 --squash');
    assert.equal(d.code, 2);
    assert.equal(d.stderr, ARTICLE7);
    assert.equal(decideIn(project, 'merge', 'gh pr merge 42 --squash', { env: { AAI_OPERATOR_MERGE: '1' } }).code, 0);
  });

  test('DG-05 a JSON-escaped command is decoded and denied', () => {
    const project = makeProject('dg05');
    const raw = '{"tool_input":{"command":"gh\\u0020pr merge 5"}}';
    const decide = need('decide');
    const d = decide('merge', { payload: raw, env: { PATH: process.env.PATH }, root: project.dir }, realDeps(project, { PATH: process.env.PATH }));
    assert.equal(d.code, 2);
    assert.equal(d.stderr, ARTICLE7);
    const l = gate(LAUNCHER, project, 'merge', raw, { raw: true });
    assert.equal(l.rc, 2);
    assert.equal(l.stderr, ARTICLE7);
  });

  test('DG-06 non-ASCII white space between command words is denied under every locale', () => {
    const project = makeProject('dg06');
    const d = decideIn(project, 'merge', 'gh\u00a0pr merge 5');
    assert.equal(d.code, 2);
    assert.equal(d.stderr, ARTICLE7);
    for (const loc of ['C', 'C.UTF-8']) {
      const l = gate(LAUNCHER, project, 'merge', 'gh\u00a0pr merge 5', { env: { LC_ALL: loc } });
      assert.equal(l.rc, 2, `LC_ALL=${loc}`);
    }
    assert.equal(decideIn(project, 'merge', 'ls -la').code, 0);
    // the operator-marker path: a PR target is split on ASCII white space only, so a target carrying a
    // non-ASCII separator stays whole, cannot be resolved and is denied (PR 42 has a sweep record)
    const op = { AAI_OPERATOR_MERGE: '1' };
    const seps = [0x85, 0xa0, 0x1680, ...Array.from({ length: 11 }, (_, i) => 0x2000 + i), 0x2028, 0x2029, 0x202f, 0x205f, 0x3000].map((c) => String.fromCharCode(c));
    assert.equal(decideIn(project, 'merge', 'gh pr merge 42', { env: op }).code, 0);
    for (const c of seps) {
      for (const cmd of [`gh pr merge 42${c}`, `gh pr merge 42${c} --squash`, `gh pr merge ${c}42`, `gh pr merge 42${c}x`, `gh pr merge --squash${c}42`,
        `gh pr merge --match-head-commit${c}abc123 42`, `gh pr merge -R${c}o/r 42`, `gh pr merge --subject${c}x 42`]) {
        const d = decideIn(project, 'merge', cmd, { env: op });
        assert.equal(d.code, 2, JSON.stringify(cmd));
        assert.match(d.stderr, /^Merge denied: could not resolve a PR for target "/, JSON.stringify(cmd));
      }
    }
    for (const loc of ['C', 'C.UTF-8']) {
      for (const c of ['\u00a0', '\u2003', '\u2028']) assert.equal(gate(LAUNCHER, project, 'merge', `gh pr merge 42${c}`, { env: { ...op, LC_ALL: loc } }).rc, 2, `LC_ALL=${loc} U+${c.codePointAt(0).toString(16)}`);
    }
  });

  test('DG-13 the operator-marker path fails closed on an ambiguous target', () => {
    const project = makeProject('dg13');
    const op = { AAI_OPERATOR_MERGE: '1' };
    // a PATH holding node, git and sh but no gh
    const nogh = ghFreeDir('nogh');
    const noGhPath = nogh;
    const ids = (which, cmd, loc) => (which === 'mod'
      ? decideIn(project, 'merge', cmd, { env: { ...op, PATH: noGhPath } })
      : { code: gate(LAUNCHER, project, 'merge', cmd, { env: { ...op, LC_ALL: loc }, path: noGhPath }).rc });
    // gh absent: a target that is not plain ASCII digits is denied; plain digits keep the sweep check by number
    for (const c of [' ', ' ', '　', '﻿']) {
      for (const cmd of [`gh pr merge 42${c}`, `gh pr merge ${c}42`, `gh pr merge 42${c}x`, ...(c === '\ufeff' ? [] : [`gh${c}pr${c}merge 42`, `gh pr merge${c}42`])]) {
        const d = ids('mod', cmd);
        assert.equal(d.code, 2, `gh absent ${JSON.stringify(cmd)}`);
        assert.match(d.stderr, /^Merge denied: gh is not available, and the merge target "/, JSON.stringify(cmd));
        for (const loc of ['C', 'C.UTF-8']) assert.equal(ids('launcher', cmd, loc).code, 2, `launcher ${loc} ${JSON.stringify(cmd)}`);
      }
    }
    assert.equal(ids('mod', 'gh pr merge 42').code, 0, 'gh absent, valid sweep record');
    assert.equal(ids('mod', 'gh pr merge 7 --squash').code, 0, 'gh absent, no record is allowed');
    const failing = ids('mod', 'gh pr merge 43');
    assert.equal(failing.code, 2);
    assert.match(failing.stderr, /^Merge denied: no valid post-open review sweep record for PR 43 /);
    // two merge-shaped segments: every candidate is checked, any deny denies (gh present and absent, both separator classes)
    for (const c of [' ', ' ', '　']) {
      for (const cmd of ['gh pr merge 42; gh pr merge 43', `gh pr merge 42; gh${c}pr${c}merge 43`, `gh${c}pr${c}merge 42; gh pr merge 43`,
        `gh pr merge 42 && echo x | gh pr merge 43`, `gh pr merge 42\ngh pr merge 43`, `gh pr merge 43; gh pr merge 42`]) {
        assert.equal(decideIn(project, 'merge', cmd, { env: op }).code, 2, `gh present ${JSON.stringify(cmd)}`);
        assert.equal(ids('mod', cmd).code, 2, `gh absent ${JSON.stringify(cmd)}`);
        for (const loc of ['C', 'C.UTF-8']) {
          assert.equal(gate(LAUNCHER, project, 'merge', cmd, { env: { ...op, LC_ALL: loc } }).rc, 2, `launcher ${loc} ${JSON.stringify(cmd)}`);
          assert.equal(ids('launcher', cmd, loc).code, 2, `launcher gh absent ${loc} ${JSON.stringify(cmd)}`);
        }
      }
    }
    assert.equal(decideIn(project, 'merge', 'gh pr merge 42; gh pr merge 42', { env: op }).code, 0, 'two valid candidates still allow');
    // the Azure number is plain ASCII digits after an ASCII separator, else the unidentified-PR deny
    for (const c of [' ', ' ', '　']) {
      for (const cmd of [`node .aai/scripts/platform.mjs merge --pr${c}7 --expect-head abc`, `node .aai/scripts/platform.mjs merge --pr=${c}7`,
        `az repos pr update --id${c}7 --status completed`, `node .aai/scripts/platform.mjs merge --pr 7${c}`, `az repos pr update --id 42${c} --status completed`]) {
        const d = decideIn(project, 'merge', cmd, { env: op });
        assert.equal(d.code, 2, JSON.stringify(cmd));
        assert.match(d.stderr, /^Merge denied: could not determine which PR this merge command targets\./);
        for (const loc of ['C', 'C.UTF-8']) assert.equal(gate(LAUNCHER, project, 'merge', cmd, { env: { ...op, LC_ALL: loc } }).rc, 2, `${loc} ${JSON.stringify(cmd)}`);
      }
    }
    assert.equal(decideIn(project, 'merge', 'node .aai/scripts/platform.mjs merge --pr 42 --expect-head abc', { env: op }).code, 0);
    assert.equal(decideIn(project, 'merge', 'az repos pr update --id=42 --status completed', { env: op }).code, 0);
  });

  test('DG-10 U+FEFF is not white space: the gate decides as the baseline script did, on every path', () => {
    const project = makeProject('dg10');
    const op = { AAI_OPERATOR_MERGE: '1' };
    // between words it is not a separator: no merge command, allowed, as the baseline allowed it
    for (const cmd of ['gh\ufeffpr merge 5', 'git\ufeffmerge x']) {
      assert.equal(decideIn(project, 'merge', cmd).code, 0);
      for (const loc of ['C', 'C.UTF-8']) assert.equal(gate(LAUNCHER, project, 'merge', cmd, { env: { LC_ALL: loc } }).rc, 0, `LC_ALL=${loc}`);
      assert.equal(gate(baseline(), project, 'merge', cmd, {}).rc, 0, 'the baseline script allowed it');
    }
    // inside the gate 2b target (operator marker): the target keeps the character, gh cannot resolve it, the merge is denied
    for (const cmd of ['gh pr merge 42\ufeff', 'gh pr merge 42\ufeff --squash', 'gh pr merge \ufeff42', 'gh pr merge 42\ufeffx',
      'gh pr merge 42 --squash --match-head-commit\ufeffabc123']) {
      const d = decideIn(project, 'merge', cmd, { env: op });
      assert.equal(d.code, 2, JSON.stringify(cmd));
      assert.match(d.stderr, /^Merge denied: could not resolve a PR for target "/);
      for (const loc of ['C', 'C.UTF-8']) {
        const l = gate(LAUNCHER, project, 'merge', cmd, { env: { ...op, LC_ALL: loc } });
        const o = gate(baseline(), project, 'merge', cmd, { env: { ...op, LC_ALL: loc } });
        assert.equal(l.rc, o.rc, `${JSON.stringify(cmd)} LC_ALL=${loc}`);
        assert.equal(l.stderr, o.stderr, `${JSON.stringify(cmd)} LC_ALL=${loc}: the deny text names the same target`);
      }
    }
  });

  test('DG-11 a no-break-space indent before status in_progress nudges under every locale', () => {
    const project = makeProject('dg11');
    const state = path.join(project.dir, 'docs/ai/STATE.yaml');
    put(state, 'active_work_items:\n\u00a0\u00a0status: in_progress\n');
    const old = new Date(Date.now() - 100000);
    fs.utimesSync(state, old, old);
    for (const loc of ['C', 'C.UTF-8']) {
      const l = gate(LAUNCHER, project, 'stop-nudge', {}, { env: { LC_ALL: loc } });
      assert.equal(l.rc, 0, `LC_ALL=${loc}`);
      assert.equal(l.stdout, NUDGE, `LC_ALL=${loc}`);
    }
  });

  test('DG-12 loop ticks written in the same second as STATE.yaml do not count as newer', () => {
    const project = makeProject('dg12');
    const state = path.join(project.dir, 'docs/ai/STATE.yaml');
    const ticks = path.join(project.dir, 'docs/ai/LOOP_TICKS.jsonl');
    put(state, 'active_work_items:\n  status: in_progress\n');
    put(ticks, '{}\n');
    const t0 = 1700000000;
    fs.utimesSync(state, t0 + 0.1, t0 + 0.1);
    fs.utimesSync(ticks, t0 + 0.9, t0 + 0.9);
    assert.equal(decideIn(project, 'stop-nudge', {}).stdout, NUDGE, 'under one second newer: the nudge stays');
    fs.utimesSync(ticks, t0 + 1.2, t0 + 1.2);
    assert.equal(decideIn(project, 'stop-nudge', {}).stdout, undefined, 'a later second: silent');
  });

  test('DG-07 Node absent or the module absent allows, except a merge payload with a lane marker', () => {
    const project = makeProject('dg07');
    const nonode = scratch('nonode');
    for (const t of ['bash', 'cat']) fs.symlinkSync(spawnSync('sh', ['-c', `command -v ${t}`], { encoding: 'utf8' }).stdout.trim(), path.join(nonode, t));
    const alone = scratch('alone');
    put(path.join(alone, 'claude-hook-gate.sh'), fs.readFileSync(LAUNCHER), 0o755);
    for (const [script, opts] of [[LAUNCHER, { path: nonode }], [path.join(alone, 'claude-hook-gate.sh'), {}]]) {
      assert.equal(gate(script, project, 'commit', 'ls', opts).rc, 0);
      assert.equal(gate(script, project, 'merge', 'git merge feature-x', opts).rc, 0, 'no marker: allowed');
      const m = gate(script, project, 'merge', 'git merge feature-x', { ...opts, env: { [LANE_X]: '1' } });
      assert.equal(m.rc, 2, 'a lane marker in the environment denies a merge-shaped payload');
      assert.equal(m.stderr, NONODE);
      assert.equal(gate(script, project, 'merge', 'ls', { ...opts, env: { [LANE_X]: '1' } }).rc, 0, 'a lane marker with a payload that is not merge-shaped');
    }
  });

  test('DG-08 stop-nudge prints the nudge line and never exits 2', () => {
    const project = makeProject('dg08');
    const state = path.join(project.dir, 'docs/ai/STATE.yaml');
    put(state, 'active_work_items:\n  - ref_id: X-1\n    status: in_progress\n');
    const old = new Date(Date.now() - 100000);
    fs.utimesSync(state, old, old);
    const d = decideIn(project, 'stop-nudge', {});
    assert.equal(d.code, 0);
    assert.equal(d.stdout, NUDGE);
    assert.equal(d.stderr, '');
    const l = gate(LAUNCHER, project, 'stop-nudge', {}, {});
    assert.equal(l.rc, 0);
    assert.equal(l.stdout, NUDGE);
    assert.equal(gate(baseline(), project, 'stop-nudge', {}, {}).stdout, NUDGE, 'byte for byte the baseline line');
    put(path.join(project.dir, 'docs/ai/LOOP_TICKS.jsonl'), '{}\n');
    assert.equal(decideIn(project, 'stop-nudge', {}).stdout, undefined, 'ticks newer than STATE: silent');
    fs.writeFileSync(state, 'status: [\n');
    assert.notEqual(decideIn(project, 'stop-nudge', {}).code, 2);
  });

  test('DG-09 every ported pattern matches line by line and the merge segment is the first one on any line', () => {
    const isMerge = need('isMergeCommand');
    const seg = need('mergeSegment');
    assert.equal(seg('echo a\necho b\ngh pr merge 7 --squash; echo z'), 'gh pr merge 7 --squash');
    assert.equal(seg('ls'), '');
    assert.equal(seg('gh pr merge 1 --squash\ngh pr merge 2'), 'gh pr merge 1 --squash');
    assert.equal(isMerge('ls\nls\ngit merge x'), true);
    assert.equal(isMerge('git\nmerge x'), false, 'words on different lines do not form a command');
    assert.equal(isMerge('gh pr\nmerge 7'), false);
    const project = makeProject('dg09');
    const d = decideIn(project, 'merge', 'echo one\necho two\ngit merge feature-x');
    assert.equal(d.code, 2);
    assert.equal(d.stderr, ARTICLE7);
  });
});

// ---------------------------------------------------------------------------
// DG-14 and DG-15: every scan on the decision path is linear in the command size, and a command above the ceiling is
// denied before any scan. A hook that runs out of time is a non-blocking error, which Claude Code treats as an allow,
// so a super-linear scan is a bypass of the gate. Every wall-clock case runs in its own process group that is killed at
// the bound, so a regression fails the case in seconds and leaves no orphan behind.
const CEILING = 262144;
const CEILING_TEXT = /longer than 262144 characters \(256 KiB\)/;
const BUDGET_MS = 2000;
const KILL_MS = 12000;
const timed = (project, name, command, opts = {}) => {
  const r = gate(LAUNCHER, project, name, command, { ...opts, bounded: KILL_MS });
  return r;
};
const within = (r, label) => {
  assert.equal(r.timedOut, false, `${label}: no decision within ${KILL_MS} ms (a hook that times out is an allow)`);
  assert.ok(r.ms < BUDGET_MS, `${label}: took ${r.ms | 0} ms (budget ${BUDGET_MS} ms)`);
};
// A command of exactly `len` characters: `head`, `fill` repeated, then `tail`.
const sized = (head, fill, tail, len) => head + fill.repeat(Math.max(0, Math.floor((len - head.length - tail.length) / fill.length))) + tail;
// The module alone, ceiling lifted, in a child that is killed at the bound (the ceiling would deny these sizes first).
const MODULE_RUNNER = `
import fs from 'node:fs';
const inp = JSON.parse(fs.readFileSync(0, 'utf8'));
const m = await import(process.argv[1]);
const deps = { which: () => true, exists: () => true, readFile: () => '', mtimeMs: () => 0, run: () => ({ status: inp.runStatus, stdout: 'checks said no', stderr: '' }) };
const t0 = process.hrtime.bigint();
const d = m.decide(inp.gate, { payload: JSON.stringify({ tool_input: { command: inp.command } }), env: inp.env, root: '/nonexistent', ceiling: Infinity }, deps);
process.stdout.write(JSON.stringify({ code: d.code, stderr: d.stderr, ms: Number(process.hrtime.bigint() - t0) / 1e6 }));
`;
const moduleAlone = (gateName, command, { env = {}, runStatus = 0 } = {}) => {
  const r = spawnSync(process.execPath, ['--input-type=module', '-e', MODULE_RUNNER, pathToFileURL(MODULE).href], {
    input: JSON.stringify({ gate: gateName, command, env, runStatus }), encoding: 'utf8', timeout: KILL_MS, killSignal: 'SIGKILL', maxBuffer: 1 << 26,
  });
  if (r.error || r.status !== 0) return { timedOut: true, code: null, ms: KILL_MS, stderr: '' };
  return { timedOut: false, ...JSON.parse(r.stdout) };
};

describe('TEST-3515 linear-time scans through the launcher', () => {
  const NL = '\n';
  test('DG-14 a command just under the ceiling, built from one repeated shape, is decided correctly in under two seconds', () => {
    const project = makeProject('linear');
    const rep = (unit, tail) => sized('', unit, tail, CEILING);
    // a newline run that is not at the end of the command, before anything else: the first scan on every gate
    const nl = (head) => sized(head, NL, 'x', CEILING);
    const op = { env: { AAI_OPERATOR_MERGE: '1' } };
    const lane = { env: { AAI_LANEX1520_MERGE: '1' } };
    const m1 = timed(project, 'merge', nl('gh pr merge 5'));
    within(m1, 'merge, a newline run in the middle');
    assert.equal(m1.rc, 2); assert.equal(m1.stderr, ARTICLE7);
    const m2 = timed(project, 'merge', nl('gh pr merge 5'), op);
    within(m2, 'merge with the operator marker, a newline run in the middle');
    assert.equal(m2.rc, gate(LAUNCHER, project, 'merge', 'gh pr merge 5\nx', op).rc);
    const m3 = timed(project, 'merge', nl('gh pr merge 5'), lane);
    within(m3, 'merge with a lane marker, a newline run in the middle');
    assert.equal(m3.rc, 2);
    fs.writeFileSync(path.join(project.dir, '.checks-fail'), '');
    const c = timed(project, 'commit', nl('git commit -m x'));
    fs.rmSync(path.join(project.dir, '.checks-fail'));
    within(c, 'commit, a newline run in the middle');
    assert.equal(c.rc, 2); assert.match(c.stderr, /^AAI pre-commit gate blocked this commit/);
    const s = timed(project, 'state-dump', nl('python -c "yaml.dump(d, open(\'docs/ai/STATE.yaml\',\'w\'))"'));
    within(s, 'state-dump, a newline run in the middle');
    assert.equal(s.rc, 2); assert.match(s.stderr, /^STATE write denied/);
    const cases = [
      ['git option run before gh pr merge', rep('git -a ', '; gh pr merge 5'), 2, ARTICLE7],
      ['git option run before git merge', rep('git -a ', 'merge x'), 2, ARTICLE7],
      ['git option run, no merge at all', rep('git -a ', '; echo merge'), 0, ''],
      ['gh words run before gh pr merge', rep('gh pr ', 'merge 5'), 2, ARTICLE7],
      ['az run before an az completion', rep('az repos pr update ', '--id 5 --status completed'), 2, ARTICLE7],
      ['az run with no completion', rep('az repos pr update ', 'x merge-free'), 0, ''],
      ['platform merge run', rep('platform.mjs merge  ', '--pr 5'), 2, ARTICLE7],
    ];
    for (const [label, command, rc, err] of cases) {
      const r = timed(project, 'merge', command);
      within(r, label);
      assert.equal(r.rc, rc, `${label}: exit code`);
      if (rc === 2) assert.equal(r.stderr, err, `${label}: article 7 text`);
    }
    fs.writeFileSync(path.join(project.dir, '.checks-fail'), '');
    const g = timed(project, 'commit', rep('git -a ', '; git commit -m x'));
    fs.rmSync(path.join(project.dir, '.checks-fail'));
    within(g, 'commit after a git option run');
    assert.equal(g.rc, 2); assert.match(g.stderr, /^AAI pre-commit gate blocked this commit/);
    // the operator-marker and lane paths over the same size: a decision, never a crash that fails open
    for (const [label, command, one] of [['platform merge segments', rep('platform.mjs merge  ', '--pr 5'), 'platform.mjs merge --pr 5'],
      ['az completions', rep('az repos pr update --status completed\n', '--id 5'), 'az repos pr update --status completed\n--id 5'],
      ['gh merge segments', rep('gh pr merge 5; ', 'echo'), 'gh pr merge 5']]) {
      const r = timed(project, 'merge', command, op);
      within(r, `${label} with the operator marker`);
      assert.equal(r.rc, gate(LAUNCHER, project, 'merge', one, op).rc, `${label} with the operator marker: the decision of its last segment alone`);
    }
    const l = timed(project, 'merge', rep('A=1 ', 'gh pr merge 5'), lane);
    within(l, 'lane prefix run');
    assert.equal(l.rc, 2);
  });
});

describe('TEST-3516 linear-time Azure number scan', () => {
  test('many --pr tokens and many platform merges in one segment are decided in under two seconds', () => {
    const op = { AAI_OPERATOR_MERGE: '1' };
    // 300000 numbers, then 105000 merges after the last of them: those name no PR, so the gate refuses to guess (DG-01)
    const shapes = [
      ['platform N x M', `node .aai/scripts/platform.mjs merge ${'--pr 5 '.repeat(300000)}${'/platform.mjs merge '.repeat(105000)}`, 2],
      ['platform same PR repeated', 'platform.mjs merge --pr 5 '.repeat(160000), 0],
    ];
    for (const [label, command, code] of shapes) {
      const r = moduleAlone('merge', command, { env: op });
      assert.equal(r.timedOut, false, `${label}: no decision within ${KILL_MS} ms`);
      assert.ok(r.ms < BUDGET_MS, `${label}: took ${r.ms | 0} ms (budget ${BUDGET_MS} ms)`);
      assert.equal(r.code, code, `${label}: the decision of the rule of DG-01`);
    }
  });
});

describe('TEST-3517 linear-time git command scan', () => {
  test('a megabyte of git option runs is decided in under two seconds on every gate', () => {
    const MIB = 1 << 20;
    const rep = (tail) => 'git -a '.repeat(Math.ceil(MIB / 7)) + tail;
    for (const [label, gateName, command, opts] of [
      ['merge after git options', 'merge', rep('; gh pr merge 5'), {}],
      ['git merge after git options', 'merge', rep('merge x'), {}],
      ['commit after git options', 'commit', rep('; git commit -m x'), { runStatus: 1 }],
    ]) {
      const r = moduleAlone(gateName, command, opts);
      assert.equal(r.timedOut, false, `${label}: no decision within ${KILL_MS} ms`);
      assert.ok(r.ms < BUDGET_MS, `${label}: took ${r.ms | 0} ms (budget ${BUDGET_MS} ms)`);
      assert.equal(r.code, 2, label);
    }
  });
});

describe('TEST-3518 command size ceiling', () => {
  test('DG-15 a relevant command above 262144 characters is denied by name, one at the ceiling is decided as ever, an irrelevant one is untouched', () => {
    const project = makeProject('ceiling');
    const op = { env: { AAI_OPERATOR_MERGE: '1' } };
    const pad = (head, len) => sized(head, ' ', '', len);
    // merge: at the ceiling the usual decision, one above the ceiling the ceiling text, marker or not
    for (const [label, head, opts, usual] of [['no marker', 'gh pr merge 5', {}, ARTICLE7], ['operator marker, PR with a sweep record', 'gh pr merge 42', op, null], ['operator marker, PR without one', 'gh pr merge 5', op, 'swept'],
      ['az completion', 'az repos pr update --id 5 --status completed', {}, ARTICLE7], ['git merge', 'git merge x', {}, ARTICLE7]]) {
      const at = timed(project, 'merge', pad(head, CEILING), opts);
      within(at, `${label} at the ceiling`);
      assert.doesNotMatch(at.stderr, CEILING_TEXT, `${label} at the ceiling is not a ceiling deny`);
      if (usual === ARTICLE7) assert.equal(at.stderr, ARTICLE7);
      if (label.startsWith('operator marker, PR with')) assert.equal(at.rc, 0);
      const over = timed(project, 'merge', pad(head, CEILING + 1), opts);
      within(over, `${label} above the ceiling`);
      assert.equal(over.rc, 2, `${label} above the ceiling`);
      assert.match(over.stderr, CEILING_TEXT);
    }
    // commit
    fs.writeFileSync(path.join(project.dir, '.checks-fail'), '');
    assert.match(timed(project, 'commit', pad('git commit -m x', CEILING)).stderr, /^AAI pre-commit gate blocked this commit/);
    fs.rmSync(path.join(project.dir, '.checks-fail'));
    assert.equal(timed(project, 'commit', pad('git commit -m x', CEILING)).rc, 0, 'passing checks at the ceiling: allow');
    const co = timed(project, 'commit', pad('git commit -m x', CEILING + 1));
    assert.equal(co.rc, 2); assert.match(co.stderr, /^Commit denied/); assert.match(co.stderr, CEILING_TEXT);
    // state-dump
    const dump = (len) => pad('python -c "yaml.dump(d, open(\'docs/ai/STATE.yaml\',\'w\'))"', len);
    assert.match(timed(project, 'state-dump', dump(CEILING)).stderr, /^STATE write denied: docs\/ai\/STATE\.yaml has exactly ONE writer/);
    const so = timed(project, 'state-dump', dump(CEILING + 1));
    assert.equal(so.rc, 2); assert.match(so.stderr, CEILING_TEXT);
    // a huge command that cannot concern a gate is not newly denied
    const MIB = 1 << 20;
    for (const [gateName, command] of [['merge', `echo merge ${'x'.repeat(MIB)}`], ['merge', `echo completed ${'x'.repeat(MIB)}`], ['commit', `echo commit ${'x'.repeat(MIB)}`],
      ['commit', `git status ${'x'.repeat(MIB)}`], ['state-dump', `echo dump ${'x'.repeat(MIB)}`], ['state-dump', `yaml.dump ${'x'.repeat(MIB)}`]]) {
      const r = timed(project, gateName, command);
      within(r, `${gateName}: ${command.slice(0, 20)} above the ceiling`);
      assert.equal(r.rc, 0, `${gateName}: ${command.slice(0, 20)}: not a command of this gate`);
    }
    // a huge payload the launcher pre-filter skips: no node process, decided linearly
    const skip = timed(project, 'merge', 'x'.repeat(8 * MIB));
    within(skip, 'an 8 MiB payload with no trigger word');
    assert.equal(skip.rc, 0);
  });
  test('the newline payloads of 1 and 2 MiB are denied by name in under two seconds on every gate', () => {
    const project = makeProject('ceiling-nl');
    const MIB = 1 << 20;
    for (const size of [MIB, 2 * MIB]) {
      const nl = (head) => sized(head, '\n', 'x', size);
      const cases = [
        ['merge', 'merge', nl('gh pr merge 5'), {}], ['merge operator marker', 'merge', nl('gh pr merge 5'), { env: { AAI_OPERATOR_MERGE: '1' } }],
        ['merge lane marker', 'merge', nl('gh pr merge 5'), { env: { AAI_LANEX1520_MERGE: '1' } }], ['commit', 'commit', nl('git commit -m x'), {}],
        ['state-dump', 'state-dump', nl('yaml.dump(d, open("docs/ai/STATE.yaml","w"))'), {}],
      ];
      for (const [label, gateName, command, opts] of cases) {
        const r = timed(project, gateName, command, opts);
        within(r, `${label} at ${size >> 20} MiB`);
        assert.equal(r.rc, 2, `${label} at ${size >> 20} MiB`);
        assert.match(r.stderr, CEILING_TEXT, label);
      }
    }
  });
});

describe('TEST-3519 distinct merge targets', () => {
  const sweepFor = (project, from, to) => {
    for (let pr = from; pr <= to; pr += 1) {
      fs.appendFileSync(path.join(project.dir, 'docs/ai/EVENTS.jsonl'), `${JSON.stringify({ v: 1, ts: '2026-01-01T00:00:00.000Z', actor: 't', event: 'pr_sweep', ref: 'hg-ride', payload: { pr, lane: 'heavy', reviewer_bots: 'none', threads_seen: 0, threads_unresolved: 0, outcome: 'internal_substituted' } })}\n`);
    }
  };
  test('the limit of 16 counts distinct merge targets, not segments, spellings or lookups', () => {
    const project = makeProject('targets');
    sweepFor(project, 100, 120);
    const op = { env: { AAI_OPERATOR_MERGE: '1' } };
    const prs = (n) => Array.from({ length: n }, (_, i) => `gh pr merge ${100 + i}`).join('; ');
    const TOO_MANY = /Merge denied: this command names more than 16 distinct merge targets/;
    assert.equal(gate(LAUNCHER, project, 'merge', prs(9), op).rc, 0, 'nine distinct gh PRs, each with a sweep record, are not too many');
    assert.equal(gate(LAUNCHER, project, 'merge', prs(16), op).rc, 0, 'sixteen distinct gh PRs are the limit');
    const seventeen = gate(LAUNCHER, project, 'merge', prs(17), op);
    assert.equal(seventeen.rc, 2); assert.match(seventeen.stderr, TOO_MANY);
    assert.match(seventeen.stderr, /one PR number or name after 'gh pr merge', or one --pr or --id number of an Azure completion/);
    const spaced = Array.from({ length: 24 }, (_, i) => `gh pr merge${' '.repeat(i + 1)}42`).join('; ');
    assert.equal(gate(LAUNCHER, project, 'merge', spaced, op).rc, 0, 'twenty-four spellings of one PR are one target');
    const azSame = `${prs(8)}; ${Array.from({ length: 8 }, (_, i) => `platform.mjs merge --pr ${100 + i}`).join('; ')}`;
    assert.equal(gate(LAUNCHER, project, 'merge', azSame, op).rc, 0, 'a gh and an Azure form of the same eight PRs are eight targets');
    const mixed = `${prs(9)}; ${Array.from({ length: 9 }, (_, i) => `platform.mjs merge --pr ${110 + i}`).join('; ')}`;
    const m = gate(LAUNCHER, project, 'merge', mixed, op);
    assert.equal(m.rc, 2, 'eighteen distinct targets over gh and Azure forms'); assert.match(m.stderr, TOO_MANY);
    // forty distinct targets: denied, never a process per target
    const many = Array.from({ length: 40 }, (_, i) => `platform.mjs merge --pr ${100 + i}`).join('; ');
    const f = gate(LAUNCHER, project, 'merge', many, op);
    assert.equal(f.rc, 2, 'forty distinct merge targets in one command are denied');
    assert.match(f.stderr, TOO_MANY);
    // the limit only ever denies: a PR whose sweep record is a skip is still denied by the sweep check
    const unswept = gate(LAUNCHER, project, 'merge', `${prs(3)}; gh pr merge 43`, op);
    assert.equal(unswept.rc, 2); assert.match(unswept.stderr, /no valid post-open review sweep record for PR 43/);
  });
});

describe('TEST-3520 byte-wise pre-filter', () => {
  // The pre-filter and the lane guard match the payload with shell globs; under a UTF-8 locale the macOS bash 3.2 does
  // that in super-linear time, so a huge merge command outlasted the hook time limit (an allow). The match runs with
  // LC_ALL=C and the caller's locale is put back before node runs. Where the locale is absent the case is the plain
  // linear one and passes as well; on a bash that is slow in UTF-8 it is the regression guard.
  const UTF8_MS = 8000;
  const big = (head, len) => sized(head, 'echo hello world ', '', len);
  test('a 32 MiB merge or irrelevant command under a UTF-8 locale is decided by the launcher inside the bound', () => {
    const project = makeProject('utf8-big');
    const MIB = 1 << 20;
    const cases = [
      ['merge, LANG', 'merge', big('gh pr merge 5 ', 32 * MIB), { LANG: 'en_US.UTF-8' }, 2],
      ['merge, LC_ALL', 'merge', big('gh pr merge 5 ', 32 * MIB), { LC_ALL: 'en_US.UTF-8' }, 2],
      ['no trigger word, LANG', 'merge', big('', 32 * MIB), { LANG: 'en_US.UTF-8' }, 0],
    ];
    for (const [label, gateName, command, env, rc] of cases) {
      const r = gate(LAUNCHER, project, gateName, command, { env, bounded: UTF8_MS });
      assert.equal(r.timedOut, false, `${label}: no decision within ${UTF8_MS} ms (a hook that times out is an allow)`);
      assert.equal(r.rc, rc, label);
      if (rc === 2) assert.match(r.stderr, CEILING_TEXT, label);
    }
  });
  test('the node module sees the caller locale exactly, LC_ALL set, empty or unset, and the deny text does not change', () => {
    const project = makeProject('utf8-env');
    const dir = scratch('stub-node');
    const out = path.join(dir, 'env.txt');
    put(path.join(dir, 'node'), '#!/bin/sh\nenv | sort > "$STUB_OUT"\n', 0o755);
    put(path.join(project.dir, '.aai/scripts/hook-gate.mjs'), '// stub\n');
    const seen = (env) => {
      fs.rmSync(out, { force: true });
      const r = gate(LAUNCHER, project, 'merge', 'gh pr merge 5', { env: { STUB_OUT: out, ...env }, path: `${dir}:${process.env.PATH}`, cwd: project.dir });
      assert.equal(r.rc, 0, 'the stub node exits 0');
      return fs.readFileSync(out, 'utf8').split('\n').filter((l) => /^(LC_|LANG)/.test(l));
    };
    assert.deepEqual(seen({ LANG: 'en_US.UTF-8' }), ['LANG=en_US.UTF-8'], 'LC_ALL unset stays unset');
    assert.deepEqual(seen({ LC_ALL: 'en_US.UTF-8', LANG: 'C' }), ['LANG=C', 'LC_ALL=en_US.UTF-8']);
    assert.deepEqual(seen({ LC_ALL: '', LC_CTYPE: 'C.UTF-8' }), ['LC_ALL=', 'LC_CTYPE=C.UTF-8'], 'LC_ALL set but empty stays empty');
    assert.deepEqual(seen({ LC_ALL: 'C' }), ['LC_ALL=C']);
    const nonodeDir = scratch('nonode-utf8');
    for (const t of ['bash', 'cat']) fs.symlinkSync(spawnSync('sh', ['-c', `command -v ${t}`], { encoding: 'utf8' }).stdout.trim(), path.join(nonodeDir, t));
    for (const env of [{ LANG: 'en_US.UTF-8' }, { LC_ALL: 'en_US.UTF-8' }, {}]) {
      const nonode = gate(LAUNCHER, project, 'merge', 'gh pr merge 5', { env: { AAI_LANEX1520_MERGE: '1', ...env }, path: nonodeDir });
      // bash itself warns at startup when the host lacks the named locale; that line is not the launcher's
      const own = nonode.stderr.split('\n').filter((l) => !/^bash: warning: setlocale: /.test(l)).join('\n');
      assert.equal(own, NONODE, 'the lane guard text is the same under every locale');
    }
  });
});

// ---------------------------------------------------------------------------
// The launcher pre-filter, restated: a payload it skips must be one the module allows (TEST-3506).
const TRIGGER = { commit: 'commit', merge: 'merge', 'state-dump': 'dump' };
function prefilterSkips(gateName, raw, stateExists) {
  if (raw.includes('\\u')) return false;
  if (gateName === 'stop-nudge') return !stateExists;
  if (gateName === 'merge') return !(raw.includes('merge') || /completed/i.test(raw));
  return !raw.includes(TRIGGER[gateName]);
}
describe('TEST-3506 pre-filter superset', () => {
  test('TEST-3506 every corpus row the pre-filter skips is a row the module allows', () => {
    const plain = makeProject('prefilter');
    const lane = makeLaneProject();
    let skipped = 0;
    for (const row of CORPUS) {
      const project = row.project === 'lane' ? lane : plain;
      prepRow(project, row);
      const cmd = typeof row.cmd === 'function' ? row.cmd(lane.head) : row.cmd;
      const raw = row.raw || row.payload || JSON.stringify(payloadObj(cmd));
      const stateExists = fs.existsSync(path.join(project.dir, 'docs/ai/STATE.yaml'));
      if (!prefilterSkips(row.gate, raw, stateExists)) continue;
      skipped += 1;
      const d = need('decide')(row.gate, { payload: raw, env: { PATH: `${project.bin}:${process.env.PATH}`, STUB_DIR: project.stub, ...(row.env || {}) }, root: project.dir },
        realDeps(project, { PATH: `${project.bin}:${process.env.PATH}`, STUB_DIR: project.stub }));
      assert.equal(d.code, 0, `${row.id}: the pre-filter skips it, so the module must allow it`);
    }
    assert.ok(skipped >= 10, `the corpus must hold rows the pre-filter skips (${skipped})`);
  });
});

describe('TEST-3522 empty PATH entry', () => {
  test('NB-B an empty PATH entry is the current directory, as command -v read it', () => {
    const project = makeProject('nbb');
    // a gh that only the empty entry reaches, and a lane-gate.mjs that denies with exit 5
    put(path.join(project.dir, 'gh'), '#!/bin/sh\nexit 1\n', 0o755);
    put(path.join(project.dir, '.aai/scripts/lane-gate.mjs'), 'process.exit(5);\n');
    const p = `:/usr/bin:/bin:${path.dirname(process.execPath)}`;
    const r = gate(LAUNCHER, project, 'merge', 'gh pr merge --squash', { path: p, env: { AAI_OPERATOR_MERGE: '1' } });
    assert.equal(r.rc, gate(baseline(), project, 'merge', 'gh pr merge --squash', { path: p, env: { AAI_OPERATOR_MERGE: '1' } }).rc, 'the launcher decides as the c88cf708 script');
    assert.equal(r.rc, 2, 'gh found through the empty entry: the gate-2b check runs and denies');
    // no empty entry: gh is not found, the decision is the allow of both
    const q = `${ghFreeDir('nogh-q')}:${path.dirname(process.execPath)}`;
    assert.equal(gate(LAUNCHER, project, 'merge', 'gh pr merge --squash', { path: q, env: { AAI_OPERATOR_MERGE: '1' } }).rc, 0);
  });
});
