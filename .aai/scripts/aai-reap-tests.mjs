#!/usr/bin/env node
// aai-reap-tests.mjs - workspace + age scoped reaper for leaked test processes (SPEC-0009, SPEC-0064,
// RFC-0017 phase 5). Defence-in-depth sweep the loop runs AFTER a test-running tick to kill hung
// `vitest`/`esbuild` trees that escaped the wrapper. aai-reap-tests.sh and aai-reap-tests.ps1 are thin launchers.
//
// SAFETY INVARIANT (load-bearing): this reaper is NEVER global. It kills ONLY processes whose command line
// holds `vitest` or `esbuild` AND the workspace path followed by a path separator (a sibling checkout or a
// prefix-sibling like ws-fork is left alone), AND that predate the step. A workspace that is a filesystem root
// is refused. A process whose age cannot be established (unparseable or impossible etime, no creation time)
// is spared in both modes, and so are this process and its parent. Two age modes:
//   - EPOCH MODE (AAI_REAP_STEP_START_EPOCH valid): reap iff start < step start - grace (strict).
//   - LEGACY MODE (unset, empty, non-digits, zero, or later than the snapshot second): reap iff age >= minimum.
//
// Environment:
//   AAI_REAP_WORKSPACE        workspace to scope by (default: the current directory)
//   AAI_REAP_MIN_AGE_SECS     legacy mode minimum age in seconds (digits only, default 0)
//   AAI_REAP_STEP_START_EPOCH step-start Unix seconds taken by the step owner before the test step (epoch mode)
//   AAI_REAP_GRACE_SECS       epoch mode grace in seconds (digits only, default 2)
//
// Output (every path that reaches a listing): `reaped: N`, `reaped pids:`, `reaped ages:`, `reaped raw:` lines.
// Exit 0; exit 1 only for an internal error (the launchers also use 1 when node or this module is missing).
//
// Platform matrix (kept identical across this header, aai-run-tests.sh, aai-run-tests.ps1 and docs/TECHNOLOGY.md):
//   macOS                              - full contract above (BSD ps etime + pid/ppid walk)
//   Linux                              - full contract above (GNU ps etime + pid/ppid walk)
//   Windows + WSL                      - full contract, native pass plus a WSL half run through the sh launcher
//   Windows + Git-Bash-only (no WSL)   - native Windows process-table pass (creation times, taskkill /T)
//   Windows, neither WSL nor Git Bash  - AAI-ENV-ERROR path lives in aai-run-tests.ps1; the native pass still runs
//
// Usage: node .aai/scripts/aai-reap-tests.mjs (normally through aai-reap-tests.sh or aai-reap-tests.ps1)
import { spawnSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TOKENS = ['vitest', 'esbuild'];
const DEFAULT_GRACE = 2;
const KILL_GRACE_MS = 1000;
const WSL_SENTINEL = 42;
const MAX_BUFFER = 64 * 1024 * 1024;
const PS_MATCH_ARGS = ['axo', 'pid=,etime=,args='];
const PS_TREE_ARGS = ['axo', 'pid=,ppid=,pgid='];
const WIN_LIST_SHELLS = ['powershell.exe', 'pwsh'];
const WIN_LIST_SCRIPT = String.raw`[Console]::OutputEncoding=New-Object Text.UTF8Encoding $false;Get-CimInstance Win32_Process|ForEach-Object{$c='';if($_.CreationDate){$c=[DateTimeOffset]::new($_.CreationDate).ToUnixTimeMilliseconds()};$l=[string]$_.CommandLine -replace '[\r\n\t]+',' ';($_.ProcessId,$_.ParentProcessId,$c,$l) -join [char]9}`;
const DIGITS = /^[0-9]+$/;
const ETIME = /^(?:(\d+)-)?(?:(?:(\d+):)?(\d+):)?(\d+)$/;
const THIS_DIR = path.dirname(fileURLToPath(import.meta.url));
const realOrResolve = (p) => { try { return realpathSync(p); } catch { return path.resolve(p); } };

export { WSL_SENTINEL };

// ps etime (SS, MM:SS, HH:MM:SS, D-HH:MM:SS) to seconds; -1 (spare) for anything else, any out-of-range
// component, or (when the snapshot second is given) an age at or above it, which no real process can have.
export function etimeToSecs(et, now) {
  const m = ETIME.exec(et);
  if (!m) return -1;
  const [d, h, mi, s] = [m[1], m[2], m[3], m[4]].map((x) => Number(x ?? 0));
  if (s > 59 || mi > 59 || h > 23) return -1;
  const total = d * 86400 + h * 3600 + mi * 60 + s;
  if (now !== undefined && total >= now) return -1;
  return total;
}

export function parseConfig(env, nowSec) {
  const epoch = env.AAI_REAP_STEP_START_EPOCH ?? '';
  const valid = DIGITS.test(epoch) && Number(epoch) > 0 && Number(epoch) <= nowSec;
  const num = (raw, dflt) => (DIGITS.test(raw ?? '') ? Number(raw) : dflt);
  return { stepStart: valid ? Number(epoch) : null, minAge: num(env.AAI_REAP_MIN_AGE_SECS, 0), grace: num(env.AAI_REAP_GRACE_SECS, DEFAULT_GRACE) };
}

// The workspace without trailing separators, or null when nothing is left (a filesystem root or empty).
export function normalizeWorkspace(raw, platform) {
  const ws = platform === 'win32' ? raw.replace(/[\\/]+$/, '') : raw.replace(/\/+$/, '');
  return ws === '' || (platform === 'win32' && /^[A-Za-z]:$/.test(ws)) ? null : ws;
}

export function matches(cmd, ws, platform) {
  const fold = platform === 'win32' ? (s) => s.toLowerCase() : (s) => s;
  const base = normalizeWorkspace(ws, platform);
  if (base === null) return false;
  const c = fold(cmd);
  const seps = platform === 'win32' ? ['\\', '/'] : ['/'];
  return TOKENS.some((t) => c.includes(t)) && seps.some((sep) => c.includes(fold(base) + sep));
}

const epochReap = (startSec, stepStart, grace) => {
  return startSec < stepStart - grace;
};
const legacyReap = (ageSec, minAge) => {
  return ageSec >= minAge;
};

export function decide(proc, cfg) {
  const { ageSec, startSec } = proc;
  if (!(ageSec >= 0) || startSec === null) return false;
  return cfg.stepStart === null ? legacyReap(ageSec, cfg.minAge) : epochReap(startSec, cfg.stepStart, cfg.grace);
}

// One process per `pid etime args` line; the line is kept verbatim for the report.
export function parsePosixSnapshot(text, now) {
  const rows = [];
  for (const raw of text.split('\n')) {
    const m = /^\s*(\d+)(?:\s+(\S+))?(?:\s+(.*))?$/.exec(raw);
    if (!m) continue;
    const ageSec = etimeToSecs(m[2] ?? '', now);
    rows.push({ pid: Number(m[1]), cmd: (m[3] ?? '').trimEnd(), ageSec, startSec: ageSec >= 0 && now !== undefined ? now - ageSec : null, raw });
  }
  return rows;
}

// One process per `id TAB parent TAB creation-ms TAB command line` line (the command line may hold tabs).
export function parseWinSnapshot(text, nowMs) {
  const rows = [];
  for (const raw of text.replace(/^﻿/, '').split(/\r?\n/)) {
    const f = raw.split('\t');
    if (f.length < 4 || !DIGITS.test(f[0])) continue;
    const creationMs = DIGITS.test(f[2]) ? Number(f[2]) : null;
    const age = creationMs === null ? -1 : Math.floor((nowMs - creationMs) / 1000);
    const cmd = f.slice(3).join('\t');
    rows.push({ pid: Number(f[0]), ppid: Number(f[1]), creationMs, cmd, ageSec: age < 0 ? -1 : age, startSec: creationMs === null ? null : creationMs / 1000, raw: `${f[0]} ${f[2]} ${cmd}` });
  }
  return rows;
}

export function parseTree(text) {
  const rows = text.split('\n').map((l) => l.trim().split(/\s+/).map(Number));
  return rows.filter((a) => a.length === 3 && a.every(Number.isInteger)).map(([pid, ppid, pgid]) => ({ pid, ppid, pgid }));
}

// The root and every transitive descendant, from [pid, ppid] pairs.
export function subtreePids(root, pairs) {
  const out = [root];
  for (let i = 0; i < out.length; i++) {
    for (const [pid, ppid] of pairs) if (ppid === out[i] && !out.includes(pid)) out.push(pid);
  }
  return out;
}

export function selectCandidates(procs, cfg, opts) {
  const skip = new Set([opts.selfPid, opts.parentPid]);
  return procs.filter((p) => p.pid > 1 && !skip.has(p.pid) && matches(p.cmd, opts.workspace, opts.platform) && decide(p, cfg));
}

export function formatReport(found) {
  const join = (f) => found.map(f).join('');
  return `reaped: ${found.length}\nreaped pids:${join((p) => ' ' + p.pid)}\nreaped ages:${join((p) => ` ${p.pid}=${p.ageSec}`)}\nreaped raw:${join((p) => ' | ' + p.raw)}\n`;
}

export function wslDelegationArgs({ workspace, minAge, epoch, grace, wslScript }) {
  const env = [`AAI_REAP_WORKSPACE=${workspace}`, `AAI_REAP_MIN_AGE_SECS=${minAge}`];
  if (epoch) {
    env.push(`AAI_REAP_STEP_START_EPOCH=${epoch}`);
    if (grace) env.push(`AAI_REAP_GRACE_SECS=${grace}`);
  }
  return ['-e', 'env', ...env, wslScript];
}

// POSIX: a group leader gets the group TERM, anything else itself and its subtree; one wait; KILL the same targets.
function killPosix(found, deps) {
  if (found.length === 0) return;
  const pairs = []; const pgids = new Map();
  try { for (const r of parseTree(deps.tree())) { pairs.push([r.pid, r.ppid]); pgids.set(r.pid, r.pgid); } } catch { /* no snapshot: pids only */ }
  const targets = found.flatMap((p) => (pgids.get(p.pid) === p.pid ? [-p.pid] : subtreePids(p.pid, pairs)));
  const send = (sig) => { for (const t of targets) { try { deps.kill(t, sig); } catch { /* ESRCH: already gone */ } } };
  send('SIGTERM');
  deps.sleep(KILL_GRACE_MS);
  send('SIGKILL');
}

// The WSL half: usable only when the probe returns exactly the sentinel; null when not usable.
function wslHalf(deps, ws) {
  const env = deps.env;
  try {
    if (deps.wsl(['-e', 'sh', '-c', `exit ${WSL_SENTINEL}`], 5000).status !== WSL_SENTINEL) return null;
    const res = deps.wsl(['wslpath', '-a', deps.shLauncher], 5000);
    const first = (res.stdout || '').split(/\r?\n/)[0].trim();
    const raw = (k) => env[k] ?? '';
    const minAge = DIGITS.test(raw('AAI_REAP_MIN_AGE_SECS')) ? raw('AAI_REAP_MIN_AGE_SECS') : '0';
    const args = wslDelegationArgs({ workspace: ws, minAge, epoch: raw('AAI_REAP_STEP_START_EPOCH'), grace: raw('AAI_REAP_GRACE_SECS'), wslScript: res.status === 0 && first ? first : deps.shLauncher });
    return deps.wsl(args, 120000);
  } catch (e) {
    return { status: null, stdout: '', error: e };
  }
}

export function run(deps) {
  const { platform, env, out, err } = deps;
  const rawWs = env.AAI_REAP_WORKSPACE || deps.cwd();
  const ws = normalizeWorkspace(rawWs, platform);
  if (ws === null) {
    err(`aai-reap-tests: refused - workspace is a filesystem root (${rawWs}); nothing reaped\n`);
    out(formatReport([]));
    return 0;
  }
  let native;
  try {
    const text = deps.list();
    const nowMs = deps.now();
    const nowSec = Math.floor(nowMs / 1000);
    const procs = platform === 'win32' ? parseWinSnapshot(text, nowMs) : parsePosixSnapshot(text, nowSec);
    const found = selectCandidates(procs, parseConfig(env, nowSec), { workspace: ws, platform, selfPid: deps.selfPid, parentPid: deps.parentPid });
    if (platform === 'win32') for (const p of found) deps.taskkill(['/PID', String(p.pid), '/T', '/F']);
    else killPosix(found, deps);
    native = formatReport(found);
  } catch (e) {
    err(`aai-reap-tests: process listing failed: ${e.message}\n`);
    native = formatReport([]);
  }
  const half = platform === 'win32' ? wslHalf(deps, rawWs) : null;
  if (half && /^reaped: /m.test(half.stdout || '')) {
    out(half.stdout.endsWith('\n') ? half.stdout : half.stdout + '\n');
    return 0;
  }
  if (half) err(`aai-reap-tests: WSL half did not report (exit ${half.status}); native summary follows\n`);
  out(native);
  return 0;
}

function psText(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: 'utf8', maxBuffer: MAX_BUFFER });
  if (r.error || r.status !== 0) throw new Error(r.error ? r.error.message : `${cmd} exited ${r.status}`);
  return r.stdout;
}

function listProcesses(platform) {
  if (platform !== 'win32') return psText('ps', PS_MATCH_ARGS);
  let last;
  for (const shell of WIN_LIST_SHELLS) {
    try { return psText(shell, ['-NoProfile', '-NonInteractive', '-Command', WIN_LIST_SCRIPT]); } catch (e) { last = e; }
  }
  throw last;
}

export function main() {
  const platform = process.platform;
  const wsl = (args, timeout) => {
    const r = spawnSync('wsl.exe', args, { encoding: 'utf8', timeout, stdio: ['ignore', 'pipe', 'ignore'] });
    return { status: r.status, stdout: r.stdout || '' };
  };
  try {
    return run({
      platform, env: process.env, cwd: () => process.cwd(), now: () => Date.now(), selfPid: process.pid, parentPid: process.ppid,
      shLauncher: path.join(THIS_DIR, 'aai-reap-tests.sh'),
      list: () => listProcesses(platform), tree: () => psText('ps', PS_TREE_ARGS),
      kill: (t, sig) => process.kill(t, sig), sleep: (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms),
      taskkill: (args) => spawnSync('taskkill.exe', args, { stdio: 'ignore' }), wsl,
      out: (s) => process.stdout.write(s), err: (s) => process.stderr.write(s),
    });
  } catch (e) {
    process.stderr.write(`aai-reap-tests: error: ${e.message}\n`);
    return 1;
  }
}

if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) process.exitCode = main();
