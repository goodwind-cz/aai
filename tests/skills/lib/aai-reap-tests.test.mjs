// aai-reap-tests.test.mjs - node:test cases for .aai/scripts/aai-reap-tests.mjs
// (docs/specs/SPEC-0267-spec-node-first-reap-tests.md, TEST-3230 to TEST-3235 and TEST-3238).
// Pure functions and run() with injected dependencies, plus one real-process case
// (TEST-3238) that uses only self-terminating Node sleepers in a fresh temp workspace
// and kills them strictly by recorded pid. No pkill, no kill by name.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
// The module may not exist yet (RED on the baseline): TEST-3238 drives the launcher only and must stay runnable.
const M = await import('../../../.aai/scripts/aai-reap-tests.mjs').catch(() => ({}));

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../..');
const LAUNCHER = path.join(ROOT, '.aai/scripts/aai-reap-tests.sh');
const RUN_PS1 = path.join(ROOT, '.aai/scripts/aai-run-tests.ps1');

// ---------------------------------------------------------------- TEST-3230
test('TEST-3230 etimeToSecs maps every valid form exactly', () => {
  const cases = { '00:00': 0, '00:03': 3, '01:00': 60, '1-00:00:00': 86400, '01:02:03': 3723 };
  for (const [et, want] of Object.entries(cases)) assert.equal(M.etimeToSecs(et), want, et);
});

test('TEST-3230 etimeToSecs gives -1 for unparseable or out-of-range fields', () => {
  for (const bad of ['', 'vitest_fresh18', 'worker', 'abc:def', '1.2.3', '/tmp/ws/x', '99:99', '77', '38109073018720', '-', '1--2']) {
    assert.equal(M.etimeToSecs(bad), -1, JSON.stringify(bad));
  }
});

test('TEST-3230 etimeToSecs clamps an impossible age only when the snapshot second is given', () => {
  assert.equal(M.etimeToSecs('441077234-00:18:40'), 38109073018720);
  assert.equal(M.etimeToSecs('441077234-00:18:40', 1753000000), -1);
  assert.equal(M.etimeToSecs('10-00:00:00', 1753000000), 864000);
});

// ---------------------------------------------------------------- TEST-3231
test('TEST-3231 parseConfig epoch validity (R-8)', () => {
  const NOW = 1753000000;
  for (const raw of [undefined, '', 'abc', '-5', '0', String(NOW + 1), '9'.repeat(21), '1.5', '12\n']) {
    const env = raw === undefined ? {} : { AAI_REAP_STEP_START_EPOCH: raw };
    assert.equal(M.parseConfig(env, NOW).stepStart, null, JSON.stringify(raw));
  }
  assert.equal(M.parseConfig({ AAI_REAP_STEP_START_EPOCH: '00012' }, NOW).stepStart, 12);
  assert.equal(M.parseConfig({ AAI_REAP_STEP_START_EPOCH: String(NOW) }, NOW).stepStart, NOW);
});

test('TEST-3231 parseConfig minimum age and grace (R-7)', () => {
  const NOW = 1753000000;
  assert.equal(M.parseConfig({}, NOW).minAge, 0);
  assert.equal(M.parseConfig({ AAI_REAP_MIN_AGE_SECS: '010' }, NOW).minAge, 10);
  assert.equal(M.parseConfig({ AAI_REAP_MIN_AGE_SECS: '5\n' }, NOW).minAge, 0);
  assert.equal(M.parseConfig({ AAI_REAP_MIN_AGE_SECS: 'abc' }, NOW).minAge, 0);
  assert.equal(M.parseConfig({ AAI_REAP_MIN_AGE_SECS: '1'.repeat(20) }, NOW).minAge, Number('1'.repeat(20)));
  assert.equal(M.parseConfig({}, NOW).grace, 2);
  assert.equal(M.parseConfig({ AAI_REAP_GRACE_SECS: 'abc' }, NOW).grace, 2);
  assert.equal(M.parseConfig({ AAI_REAP_GRACE_SECS: '' }, NOW).grace, 2);
  assert.equal(M.parseConfig({ AAI_REAP_GRACE_SECS: '0' }, NOW).grace, 0);
  assert.equal(M.parseConfig({ AAI_REAP_GRACE_SECS: '3\n' }, NOW).grace, 2);
});

test('TEST-3231 decide: strict epoch rule, inclusive legacy rule, sentinel and missing creation time spared', () => {
  const epoch = { stepStart: 1000, grace: 2, minAge: 0 };
  assert.equal(M.decide({ ageSec: 10, startSec: 998 }, epoch), false);
  assert.equal(M.decide({ ageSec: 10, startSec: 997 }, epoch), true);
  const legacy = { stepStart: null, grace: 2, minAge: 5 };
  assert.equal(M.decide({ ageSec: 5, startSec: 0 }, legacy), true);
  assert.equal(M.decide({ ageSec: 4, startSec: 0 }, legacy), false);
  assert.equal(M.decide({ ageSec: -1, startSec: 0 }, { stepStart: null, grace: 2, minAge: 0 }), false);
  assert.equal(M.decide({ ageSec: -1, startSec: 1 }, epoch), false);
  for (const cfg of [epoch, legacy, { stepStart: null, grace: 2, minAge: 0 }]) {
    assert.equal(M.decide({ ageSec: -1, startSec: null }, cfg), false);
  }
});

// ---------------------------------------------------------------- TEST-3232
test('TEST-3232 matches on linux and darwin is exact (R-1 to R-4)', () => {
  for (const p of ['linux', 'darwin']) {
    assert.equal(M.matches('node vitest /ws/a/x', '/ws/a', p), true);
    assert.equal(M.matches('node VITEST /ws/a/x', '/ws/a', p), false);
    assert.equal(M.matches('node Vitest /ws/a/x', '/ws/a', p), false);
    assert.equal(M.matches('node esbuild /WS/A/x', '/ws/a', p), false);
    assert.equal(M.matches('node vitest \\ws\\a\\x', '/ws/a', p), false);
    assert.equal(M.matches('node vitest /ws/a/x', '/ws/a//', p), true);
    assert.equal(M.matches('node vitest /ws/a-fork/x', '/ws/a', p), false);
    assert.equal(M.matches('node vitest /ws/a', '/ws/a', p), false);
    assert.equal(M.matches('node vitest /ws/a/*/x', '/ws/a/*', p), true);
    assert.equal(M.matches('node vitest /ws/a/b/x', '/ws/a/*', p), false);
    assert.equal(M.matches('node vitest /ws/a/b/x', '/ws/a/?', p), false);
    assert.equal(M.matches('node vitest /ws/a/[b]/x', '/ws/a/[b]', p), true);
    assert.equal(M.matches('node vitest /ws/a/b/x', '/ws/a/[b]', p), false);
    assert.equal(M.matches('node other /ws/a/x', '/ws/a', p), false);
  }
});

test('TEST-3232 matches on win32 folds case and accepts both separators (R-1 to R-3)', () => {
  assert.equal(M.matches('node.exe VITEST C:\\ws\\a\\x', 'C:\\ws\\a', 'win32'), true);
  assert.equal(M.matches('node.exe vitest C:\\WS\\A\\x', 'c:\\ws\\a', 'win32'), true);
  assert.equal(M.matches('node.exe vitest C:\\ws\\a/x', 'c:\\ws\\a', 'win32'), true);
  assert.equal(M.matches('node.exe vitest C:\\ws\\a-fork\\x', 'C:\\ws\\a', 'win32'), false);
  assert.equal(M.matches('node.exe vitest C:\\ws\\a\\x', 'C:\\ws\\a\\\\', 'win32'), true);
  assert.equal(M.matches('node.exe vitest C:\\ws\\a\\x', '', 'win32'), false);
});

test('TEST-3232 normalizeWorkspace refuses a filesystem root (R-4, R-5)', () => {
  assert.equal(M.normalizeWorkspace('/ws/a///', 'linux'), '/ws/a');
  assert.equal(M.normalizeWorkspace('/', 'linux'), null);
  assert.equal(M.normalizeWorkspace('//', 'darwin'), null);
  assert.equal(M.normalizeWorkspace('', 'linux'), null);
  assert.equal(M.normalizeWorkspace('C:\\', 'win32'), null);
  assert.equal(M.normalizeWorkspace('C:', 'win32'), null);
  assert.equal(M.normalizeWorkspace('', 'win32'), null);
  assert.equal(M.normalizeWorkspace('C:\\ws\\a\\/', 'win32'), 'C:\\ws\\a');
  assert.equal(M.normalizeWorkspace('C:\\', 'linux'), 'C:\\');
});

// ---------------------------------------------------------------- TEST-3233
test('TEST-3233 parsePosixSnapshot keeps the verbatim line and fails safe on a shifted column', () => {
  const rows = M.parsePosixSnapshot('  123 01:05 node vitest /ws/a/x\n 124 vitest_fresh18 worker /ws/a/y\n\n', 1753000000);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].pid, 123);
  assert.equal(rows[0].raw, '  123 01:05 node vitest /ws/a/x');
  assert.equal(rows[0].cmd, 'node vitest /ws/a/x');
  assert.equal(rows[0].ageSec, 65);
  assert.equal(rows[0].startSec, 1753000000 - 65);
  assert.equal(rows[1].pid, 124);
  assert.equal(rows[1].ageSec, -1);
});

test('TEST-3233 parseWinSnapshot reads id, parent, creation milliseconds and a spaced command line', () => {
  const NOW = 1753000000000;
  const text = ['10\t4\t1752999000000\tnode.exe vitest C:\\my ws\\a\\x', '11\t4\t\tsvc.exe vitest C:\\ws\\a\\y', ''].join('\r\n');
  const rows = M.parseWinSnapshot(text, NOW);
  assert.equal(rows.length, 2);
  assert.deepEqual([rows[0].pid, rows[0].ppid, rows[0].creationMs], [10, 4, 1752999000000]);
  assert.equal(rows[0].cmd, 'node.exe vitest C:\\my ws\\a\\x');
  assert.equal(rows[0].ageSec, 1000);
  assert.equal(rows[0].startSec, 1752999000);
  assert.equal(rows[0].raw, '10 1752999000000 node.exe vitest C:\\my ws\\a\\x');
  assert.equal(rows[1].creationMs, null);
  assert.equal(rows[1].ageSec, -1);
  assert.equal(rows[1].startSec, null);
});

test('TEST-3233 selectCandidates skips its own pid and parent pid even when they match', () => {
  const procs = [10, 11, 12].map((pid) => ({ pid, cmd: 'node vitest /ws/a/x', ageSec: 50, startSec: 10, raw: '' }));
  const cfg = { stepStart: null, grace: 2, minAge: 0 };
  const got = M.selectCandidates(procs, cfg, { workspace: '/ws/a', platform: 'linux', selfPid: 10, parentPid: 11 });
  assert.deepEqual(got.map((p) => p.pid), [12]);
});

test('TEST-3233 subtreePids returns the root and its descendants only', () => {
  const pairs = [[2, 1], [3, 2], [4, 3], [5, 2], [9, 8], [10, 9]];
  assert.deepEqual([...M.subtreePids(2, pairs)].sort((a, b) => a - b), [2, 3, 4, 5]);
  assert.deepEqual([...M.subtreePids(77, pairs)], [77]);
});

// ---------------------------------------------------------------- run() harness
const NOW_MS = 1753000000000;
function harness(over = {}) {
  const calls = { list: 0, tree: 0, kill: [], sleep: [], taskkill: [], wsl: [] };
  const o = { stdout: '', stderr: '' };
  const deps = {
    platform: 'linux',
    env: { AAI_REAP_WORKSPACE: '/ws/a' },
    cwd: () => '/elsewhere',
    now: () => NOW_MS,
    selfPid: 900,
    parentPid: 901,
    shLauncher: '/repo/.aai/scripts/aai-reap-tests.sh',
    list: () => { calls.list += 1; return ''; },
    tree: () => { calls.tree += 1; return ''; },
    kill: (t, s) => { calls.kill.push([t, s]); },
    sleep: (ms) => { calls.sleep.push(ms); },
    taskkill: (a) => { calls.taskkill.push(a); },
    wsl: (a, t) => { calls.wsl.push([a, t]); return { status: 1, stdout: '' }; },
    out: (s) => { o.stdout += s; },
    err: (s) => { o.stderr += s; },
    ...over,
  };
  return { deps, calls, o };
}
const ZERO = 'reaped: 0\nreaped pids:\nreaped ages:\nreaped raw:\n';

// ---------------------------------------------------------------- TEST-3234
test('TEST-3234 run on POSIX: group leader gets the group TERM, a non-leader gets itself and its subtree', () => {
  const list = [' 100 10:00 node vitest /ws/a/x', ' 200 10:00 node vitest /ws/a/y', ' 300 10:00 node vitest /ws/b/y'].join('\n');
  const tree = ['100 1 100', '101 100 100', '200 1 50', '201 200 50', '202 201 50', '300 1 300'].join('\n');
  const { deps, calls, o } = harness({ list: () => list, tree: () => tree });
  assert.equal(M.run(deps), 0);
  assert.deepEqual(calls.kill.slice(0, 4), [[-100, 'SIGTERM'], [200, 'SIGTERM'], [201, 'SIGTERM'], [202, 'SIGTERM']]);
  assert.deepEqual(calls.sleep, [1000]);
  assert.deepEqual(calls.kill.slice(4), [[-100, 'SIGKILL'], [200, 'SIGKILL'], [201, 'SIGKILL'], [202, 'SIGKILL']]);
  assert.equal(calls.kill.length, 8);
  assert.equal(o.stdout, 'reaped: 2\nreaped pids: 100 200\nreaped ages: 100=600 200=600\nreaped raw: | ' + list.split('\n').slice(0, 2).join(' | ') + '\n');
  assert.equal(o.stderr, '');
});

test('TEST-3234 run on POSIX with no match neither sleeps nor kills', () => {
  const { deps, calls, o } = harness({ list: () => ' 100 10:00 node vitest /ws/b/x\n 101 10:00 node other /ws/a/x' });
  assert.equal(M.run(deps), 0);
  assert.equal(calls.kill.length, 0);
  assert.equal(calls.sleep.length, 0);
  assert.equal(o.stdout, ZERO);
});

test('TEST-3234 run reports a listing failure on stderr with four zero lines and exit 0 (R-13)', () => {
  const { deps, calls, o } = harness({ list: () => { throw new Error('ps exploded'); } });
  assert.equal(M.run(deps), 0);
  assert.equal(o.stdout, ZERO);
  assert.equal(o.stderr, 'aai-reap-tests: process listing failed: ps exploded\n');
  assert.equal(calls.kill.length, 0);
});

test('TEST-3234 run refuses a root workspace without listing anything (R-5)', () => {
  for (const ws of ['/', '//']) {
    const { deps, calls, o } = harness({ env: { AAI_REAP_WORKSPACE: ws } });
    assert.equal(M.run(deps), 0);
    assert.equal(calls.list, 0);
    assert.equal(calls.kill.length, 0);
    assert.equal(o.stdout, ZERO);
    assert.equal(o.stderr, `aai-reap-tests: refused - workspace is a filesystem root (${ws}); nothing reaped\n`);
  }
});

test('TEST-3234 run takes the default workspace from cwd and applies epoch mode with the snapshot second', () => {
  const nowSec = NOW_MS / 1000;
  const list = [` 100 00:09 node vitest /cwd/ws/x`, ` 101 00:20 node vitest /cwd/ws/y`].join('\n');
  const env = { AAI_REAP_STEP_START_EPOCH: String(nowSec - 15), AAI_REAP_GRACE_SECS: '0' };
  const { deps, o } = harness({ env, cwd: () => '/cwd/ws', list: () => list, tree: () => '' });
  M.run(deps);
  assert.match(o.stdout, /^reaped: 1\nreaped pids: 101\n/);
});

test('TEST-3234 PS_MATCH_ARGS and TREE args name the sh format columns', () => {
  const src = fs.readFileSync(fileURLToPath(new URL('../../../.aai/scripts/aai-reap-tests.mjs', import.meta.url)), 'utf8');
  assert.match(src, /PS_MATCH_ARGS = \['axo', 'pid=,etime=,args='\]/);
  assert.match(src, /PS_TREE_ARGS = \['axo', 'pid=,ppid=,pgid='\]/);
  assert.match(src, /MAX_BUFFER = 64 \* 1024 \* 1024/);
});

// ---------------------------------------------------------------- TEST-3235
const WINCMD = (id, ws, name) => `${id}\t4\t${name}\tnode.exe vitest ${ws}\\x`;
test('TEST-3235 run on win32 calls taskkill once for the aged in-workspace match and prints the four lines', () => {
  const old = NOW_MS - 600000;
  const young = NOW_MS - 1000;
  const list = [WINCMD(10, 'C:\\ws\\a', old), WINCMD(11, 'C:\\ws\\b', old), WINCMD(12, 'C:\\ws\\a', young), `13\t4\t\tnode.exe vitest C:\\ws\\a\\x`].join('\r\n');
  const env = { AAI_REAP_WORKSPACE: 'C:\\ws\\a', AAI_REAP_MIN_AGE_SECS: '30' };
  const { deps, calls, o } = harness({ platform: 'win32', env, list: () => list });
  assert.equal(M.run(deps), 0);
  assert.deepEqual(calls.taskkill, [['/PID', '10', '/T', '/F']]);
  assert.equal(calls.kill.length, 0);
  assert.equal(o.stdout, `reaped: 1\nreaped pids: 10\nreaped ages: 10=600\nreaped raw: | 10 ${old} node.exe vitest C:\\ws\\a\\x\n`);
});

test('TEST-3235 WSL probe argv, usable only on the exact sentinel exit code', () => {
  const run = (probe) => {
    const h = harness({ platform: 'win32', env: { AAI_REAP_WORKSPACE: 'C:\\ws\\a' }, list: () => '', wsl: (a, t) => { h.calls.wsl.push([a, t]); return a[3] === 'exit 42' ? probe : { status: 1, stdout: '' }; } });
    M.run(h.deps);
    return h;
  };
  const h0 = run({ status: 0, stdout: '' });
  assert.deepEqual(h0.calls.wsl, [[['-e', 'sh', '-c', 'exit 42'], 5000]]);
  assert.equal(h0.o.stdout, ZERO);
  const hT = run({ status: null, stdout: '', error: new Error('ETIMEDOUT') });
  assert.equal(hT.calls.wsl.length, 1);
  const h42 = run({ status: 42, stdout: '' });
  assert.ok(h42.calls.wsl.length >= 2, 'a usable probe leads to the delegation');
});

test('TEST-3235 wslDelegationArgs equals the retired Pester argv lists', () => {
  const sh = '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh';
  assert.deepEqual(
    M.wslDelegationArgs({ workspace: 'C:\\ws\\myproject', minAge: '30', epoch: '', grace: '', wslScript: sh }),
    ['-e', 'env', 'AAI_REAP_WORKSPACE=C:\\ws\\myproject', 'AAI_REAP_MIN_AGE_SECS=30', sh],
  );
  assert.deepEqual(
    M.wslDelegationArgs({ workspace: 'C:\\ws\\myproject', minAge: '0', epoch: '1750000000', grace: '2', wslScript: sh }),
    ['-e', 'env', 'AAI_REAP_WORKSPACE=C:\\ws\\myproject', 'AAI_REAP_MIN_AGE_SECS=0', 'AAI_REAP_STEP_START_EPOCH=1750000000', 'AAI_REAP_GRACE_SECS=2', sh],
  );
  assert.deepEqual(
    M.wslDelegationArgs({ workspace: 'C:\\w', minAge: '0', epoch: '1750000000', grace: '', wslScript: sh }),
    ['-e', 'env', 'AAI_REAP_WORKSPACE=C:\\w', 'AAI_REAP_MIN_AGE_SECS=0', 'AAI_REAP_STEP_START_EPOCH=1750000000', sh],
  );
});

function wslHarness(delegate) {
  const h = harness({
    platform: 'win32',
    env: { AAI_REAP_WORKSPACE: 'C:\\ws\\a', AAI_REAP_STEP_START_EPOCH: '1750000000' },
    list: () => '',
    wsl: (a, t) => {
      h.calls.wsl.push([a, t]);
      if (a[3] === 'exit 42') return { status: 42, stdout: '' };
      if (a[0] === 'wslpath') return { status: 0, stdout: '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh\n' };
      return delegate;
    },
  });
  return h;
}

test('TEST-3235 a delegate that reports is printed verbatim and the native summary is suppressed', () => {
  const text = 'reaped: 2\nreaped pids: 5 6\nreaped ages: 5=9 6=9\nreaped raw: | a | b\n';
  const h = wslHarness({ status: 0, stdout: text });
  assert.equal(M.run(h.deps), 0);
  assert.equal(h.o.stdout, text);
  assert.equal(h.o.stderr, '');
  const call = h.calls.wsl.find(([a]) => a[0] === '-e' && a[1] === 'env');
  assert.ok(call, 'delegation call present');
  assert.deepEqual(call[0], ['-e', 'env', 'AAI_REAP_WORKSPACE=C:\\ws\\a', 'AAI_REAP_MIN_AGE_SECS=0', 'AAI_REAP_STEP_START_EPOCH=1750000000', '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh']);
});

test('TEST-3235 a delegate without a reaped line gives the native lines and the stderr note', () => {
  const h = wslHarness({ status: 1, stdout: 'env: node: not found\n' });
  assert.equal(M.run(h.deps), 0);
  assert.equal(h.o.stdout, ZERO);
  assert.equal(h.o.stderr, 'aai-reap-tests: WSL half did not report (exit 1); native summary follows\n');
});

test('TEST-3235 WSL_SENTINEL equals the sentinel in aai-run-tests.ps1', () => {
  const ps = fs.readFileSync(RUN_PS1, 'utf8');
  const m = /\$sentinel\s*=\s*(\d+)/.exec(ps);
  assert.ok(m, 'sentinel assignment found in aai-run-tests.ps1');
  assert.equal(M.WSL_SENTINEL, Number(m[1]));
});

// ---------------------------------------------------------------- TEST-3238
const made = [];
const pids = [];
const alive = (pid) => {
  const r = spawnSync('ps', ['-o', 'stat=', '-p', String(pid)], { encoding: 'utf8' });
  const stat = (r.stdout || '').trim();
  return stat !== '' && !stat.startsWith('Z');
};
function scanFor(root) {
  const r = spawnSync('ps', ['axo', 'pid=,args='], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return (r.stdout || '').split('\n').filter((l) => l.includes(root));
}
const argsOf = (pid) => (spawnSync('ps', ['-o', 'args=', '-p', String(pid)], { encoding: 'utf8' }).stdout || '');
// Kill strictly by recorded pid, and only while that pid still shows the fixture's own command line (guards pid reuse).
function cleanup() {
  for (const { pid, expect } of pids) {
    if (!argsOf(pid).includes(expect)) continue;
    try { process.kill(pid, 'SIGKILL'); } catch { /* already gone */ }
  }
}
after(() => { cleanup(); for (const d of made) fs.rmSync(d, { recursive: true, force: true }); });

const PARENT_SRC = "const {spawn}=require('node:child_process');const c=spawn(process.execPath,['-e','setTimeout(()=>{},90000)'],{stdio:'ignore'});process.stdout.write(c.pid+'\\n');setTimeout(()=>{},90000)";
function startSleeper(dir, detached, withChild) {
  const arg = path.join(dir, 'worker');
  const script = withChild ? PARENT_SRC : 'process.stdout.write("0\\n");setTimeout(()=>{},90000)';
  const p = spawn(process.execPath, ['-e', script, 'vitest', arg], { detached, stdio: ['ignore', 'pipe', 'ignore'] });
  pids.push({ pid: p.pid, expect: dir });
  return new Promise((resolve, reject) => {
    let buf = '';
    p.on('error', reject);
    p.stdout.on('data', (d) => {
      buf += d;
      if (!buf.includes('\n')) return;
      const child = Number(buf.split('\n')[0]);
      if (child > 0) pids.push({ pid: child, expect: 'setTimeout(()=>{},90000)' });
      p.stdout.destroy();
      p.unref();
      resolve({ pid: p.pid, child: child > 0 ? child : null });
    });
  });
}
const delay = (ms) => new Promise((r) => setTimeout(r, ms));
async function goneWithin(list, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (list.every((p) => !alive(p))) return true;
    await delay(100);
  }
  return list.every((p) => !alive(p));
}

test('TEST-3238 the sh launcher reaps only the pre-step in-workspace matches on real processes', async () => {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'aai-reap-3238-')));
  made.push(root);
  const ws = path.join(root, 'ws');
  const dirs = { ws, other: path.join(root, 'other'), fork: path.join(root, 'ws-fork') };
  for (const d of Object.values(dirs)) fs.mkdirSync(d, { recursive: true });
  try {
    const leader = await startSleeper(ws, true, true);
    const member = await startSleeper(ws, false, true);
    const sibling = await startSleeper(dirs.other, false, false);
    const prefix = await startSleeper(dirs.fork, false, false);
    await delay(4000);
    const stepStart = Math.floor(Date.now() / 1000);
    await delay(1100);
    const post = await startSleeper(ws, false, false);
    for (const p of [leader, member, sibling, prefix, post]) assert.ok(alive(p.pid), 'fixture alive ' + p.pid);
    const r = spawnSync('sh', [LAUNCHER], {
      encoding: 'utf8',
      env: { ...process.env, AAI_ROLE: '', AAI_REAP_WORKSPACE: ws, AAI_REAP_STEP_START_EPOCH: String(stepStart), AAI_REAP_GRACE_SECS: '0' },
    });
    assert.equal(r.status, 0, r.stderr);
    const gone = [leader.pid, leader.child, member.pid, member.child];
    assert.ok(await goneWithin(gone, 5000), 'both matched parents and both children are gone');
    for (const p of [sibling, prefix, post]) assert.ok(alive(p.pid), 'spared sleeper alive ' + p.pid);
    const line = r.stdout.split('\n').find((l) => l.startsWith('reaped pids:')) ?? '';
    assert.deepEqual(line.slice('reaped pids:'.length).trim().split(/\s+/).map(Number).sort((a, b) => a - b), [leader.pid, member.pid].sort((a, b) => a - b));
    assert.match(r.stdout, /^reaped: 2\n/);
  } finally {
    cleanup();
    await goneWithin(pids.map((e) => e.pid), 3000);
    assert.deepEqual(scanFor(root), [], 'no process command line may still hold the test workspace root');
  }
});
