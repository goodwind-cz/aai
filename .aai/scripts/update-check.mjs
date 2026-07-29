#!/usr/bin/env node
// update-check.mjs — config-driven new-release notify + opt-in auto-sync
// (CHANGE auto-update-config / SPEC spec-auto-update-config).
//
// A target AAI project learns a newer AAI release exists as a SIDE EFFECT OF
// NORMAL USE: the SessionStart hook runs this best-effort at every session
// start. It REUSES the existing detection and sync engines verbatim — no
// parallel engine:
//   - .aai/scripts/layer-drift.mjs  — pin-vs-canonical verdict (--json).
//   - .aai/scripts/aai-update.{sh,ps1} — the sync, incl. its canonical-repo
//     origin-slug guard (NOT duplicated here).
//
// Behavior is governed by a LOCAL config (docs/ai/update-config.yaml, absent ==
// notify default):
//   mode: notify (default, safe) — print a "newer AAI release available" line;
//         change no repository files.
//   mode: auto   (opt-in)        — on a `behind` verdict, apply aai-update as a
//         side effect of normal use WITHOUT blocking session start and WITHOUT
//         losing the outcome (DETACHED + REPORT-NEXT-SESSION model, below).
//   An unknown mode is REJECTED on stderr and falls back to notify (a typo
//   never auto-syncs).
//
// DETACHED + REPORT-NEXT-SESSION (auto mode). The SessionStart hook path runs
// only the FAST detection (bounded by the hook's short watchdog) and ALWAYS
// surfaces the availability line for a `behind` verdict — in BOTH modes. In
// AUTO mode + `behind`, instead of running the ~40s sync synchronously (which
// the hook's ~15s watchdog would SIGKILL, orphaning the child and LOSING the
// outcome), it spawns the aai-update sync FULLY DETACHED (own session/process
// group, own stdio) and returns at once. The detached child records a
// persistent OUTCOME LOG (.aai/cache/update-sync-outcome.json — gitignored,
// excluded from the PROFILES union): {started_utc, finished_utc,
// target_version, result: applied|failed|refused, detail}. The NEXT run (hook
// or manual) SURFACES that outcome once ("auto-update applied … — review the
// diff" / "failed: …" / "refused (canonical repo)") and marks it reported. A
// synchronously-written `running` marker guards against a second concurrent
// detached sync. Guarantees: session start is NEVER blocked; the outcome is
// NEVER lost; the detach is deliberate + reaped (no zombie/orphan surprise).
//
// Runtime outcomes ALWAYS exit 0 (best-effort, non-blocking). Exit 2 is
// reserved for CLI usage errors (unknown flag / missing value) when run by
// hand. Notify/degrade/outcome lines go to STDOUT (the hook concatenates them
// onto the injected meta-skill content); config/usage errors go to STDERR.
//
// Usage:
//   node update-check.mjs [--config <path>] [--pin <path>] [--remote <url>]
//     [--source <slug|path>] [--cache <path>] [--outcome <path>] [--now <iso>]
//     [--force] [--timeout-ms <n>] [--json]
//   --remote  overrides the canonical remote passed to layer-drift (tests/CI).
//   --source  overrides the aai-update sync source (--repo) in auto mode; when
//             omitted the source is DERIVED from the drift verdict's resolved
//             `remote` so detection and sync agree on one source of truth.
//   --now     injects a deterministic clock (ISO 8601) for throttle tests.
//   --cache   overrides the throttle cache path (default .aai/cache/update-check.json).
//   --outcome overrides the detached-sync outcome log path
//             (default .aai/cache/update-sync-outcome.json).
//   (--run-sync / --target-version are the detached child's private contract.)

import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SELF_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_TIMEOUT_MS = 10_000;
// A `running` outcome older than this is treated as a crashed/abandoned sync so
// a fresh sync may start (the concurrent guard never wedges forever).
const SYNC_STALE_MS = 30 * 60_000;

function usage() {
  console.error(
    'Usage: update-check [--config <path>] [--pin <path>] [--remote <url>]\n' +
    '                   [--source <slug|path>] [--cache <path>] [--outcome <path>]\n' +
    '                   [--now <iso>] [--force] [--timeout-ms <n>] [--json]\n' +
    '  Best-effort new-release check. Runtime outcomes exit 0; exit 2 = usage error.',
  );
}

function fail(msg) {
  console.error(`update-check: ${msg}`);
  usage();
  process.exit(2);
}

function parseArgs(argv) {
  const args = {
    config: path.resolve(process.cwd(), 'docs/ai/update-config.yaml'),
    pin: null,
    remote: null,
    source: null,
    cache: path.resolve(process.cwd(), '.aai/cache/update-check.json'),
    outcome: path.resolve(process.cwd(), '.aai/cache/update-sync-outcome.json'),
    now: null,
    force: false,
    runSync: false,
    targetVersion: null,
    timeoutMs: DEFAULT_TIMEOUT_MS,
    json: false,
  };
  const toks = argv.slice(2);
  for (let i = 0; i < toks.length; i++) {
    const tok = toks[i];
    const need = (name) => {
      const v = toks[++i];
      if (v === undefined || v.startsWith('--')) fail(`${name} needs a value`);
      return v;
    };
    if (tok === '--config') args.config = path.resolve(need('--config'));
    else if (tok === '--pin') args.pin = path.resolve(need('--pin'));
    else if (tok === '--remote') args.remote = need('--remote');
    else if (tok === '--source') args.source = need('--source');
    else if (tok === '--cache') args.cache = path.resolve(need('--cache'));
    else if (tok === '--outcome') args.outcome = path.resolve(need('--outcome'));
    else if (tok === '--now') args.now = need('--now');
    else if (tok === '--force') args.force = true;
    // --run-sync / --target-version are the DETACHED background-sync child's
    // private contract (spawned by this same script; not for hand use).
    else if (tok === '--run-sync') args.runSync = true;
    else if (tok === '--target-version') args.targetVersion = need('--target-version');
    else if (tok === '--timeout-ms') {
      const n = Number.parseInt(need('--timeout-ms'), 10);
      if (!Number.isInteger(n) || n <= 0) fail('--timeout-ms must be a positive integer');
      args.timeoutMs = n;
    } else if (tok === '--json') args.json = true;
    else fail(`unknown flag: ${tok}`);
  }
  return args;
}

// --- Config resolution (COLUMN-0 line scan; no YAML lib) ----------------------
// Same discipline as .aai/scripts/lib/guard-config.mjs: an indented or
// commented key is never a dial. Absent file -> notify default. Unknown mode ->
// stderr error + notify fallback (fail-safe: a typo never auto-syncs).
export function resolveConfig(cfgPath, warn = (m) => console.error(m)) {
  const out = { mode: 'notify', throttle_hours: 24, present: false };
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return out; // absent file: notify default, silently
  }
  out.present = true;
  const seen = new Set();
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^(mode|throttle_hours):\s*(\S+)/);
    if (!m || seen.has(m[1])) continue; // column-0 only; first occurrence wins
    seen.add(m[1]);
    if (m[1] === 'mode') {
      if (m[2] === 'notify' || m[2] === 'auto') {
        out.mode = m[2];
      } else {
        warn(`update-check: WARNING mode value "${m[2]}" in ${cfgPath} is not `
          + '"notify" or "auto" — falling back to notify (a typo never auto-syncs)');
        out.mode = 'notify';
      }
    } else if (m[1] === 'throttle_hours') {
      // Strict digits-only (mirror guard-config.mjs full-token discipline):
      // Number.parseInt would coerce "24h" -> 24 and "0x10" -> 0, silently
      // accepting a malformed dial despite the "non-negative integer" contract.
      // A non-digit token is REJECTED (warn on stderr + default 24), never
      // coerced — a typo can never quietly change the throttle window.
      if (/^\d+$/.test(m[2])) {
        out.throttle_hours = Number.parseInt(m[2], 10);
      } else {
        warn(`update-check: WARNING throttle_hours value "${m[2]}" in ${cfgPath} `
          + 'is not a non-negative integer — using default 24');
      }
    }
  }
  return out;
}

// --- Throttle cache (gitignored .aai/cache/update-check.json) -----------------
// Corrupt / absent cache -> treat as never-checked (probe). Never crashes.
function readLastCheck(cachePath) {
  try {
    const j = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    const t = Date.parse(j.last_check_utc);
    return Number.isNaN(t) ? null : t;
  } catch {
    return null;
  }
}

function refreshCache(cachePath, nowIso) {
  try {
    fs.mkdirSync(path.dirname(cachePath), { recursive: true });
    fs.writeFileSync(cachePath, JSON.stringify({ last_check_utc: nowIso }) + '\n');
  } catch {
    // best-effort: an unwritable cache must never break the check
  }
}

// throttle_hours 0 => always probe. --force => always probe.
// A FUTURE-DATED cache (lastMs > nowMs — clock skew, a bad hand-edit, or a stale
// timestamp read against an injected past clock) would make (now-last) negative
// and throttle FOREVER, silently suppressing notify AND auto-sync until wall
// time passes it — and a throttled run never refreshes, so it never self-heals.
// Treat it (and any NaN/unparseable last, handled upstream in readLastCheck as
// null) as never-checked: force a probe so the cache is re-stamped honestly.
function withinThrottle(lastMs, throttleHours, nowMs, force) {
  if (force) return false;
  if (throttleHours <= 0) return false;
  if (lastMs === null) return false;
  if (lastMs > nowMs) return false; // future-dated -> never-checked (self-heal)
  return (nowMs - lastMs) < throttleHours * 3_600_000;
}

// --- Detection (REUSE layer-drift.mjs via --json) -----------------------------
function runLayerDrift({ pin, remote, timeoutMs }) {
  const driftScript = path.join(SELF_DIR, 'layer-drift.mjs');
  const argv = ['--json', '--timeout-ms', String(timeoutMs)];
  if (pin) argv.push('--pin', pin);
  if (remote) argv.push('--remote', remote);
  const res = spawnSync('node', [driftScript, ...argv], {
    encoding: 'utf8',
    timeout: timeoutMs + 5_000, // wall-clock backstop over layer-drift's own bound
  });
  if (res.error || res.stdout == null) {
    return { status: 'unverifiable', message: 'layer-drift did not run', relation: 'unknown' };
  }
  try {
    return JSON.parse(res.stdout);
  } catch {
    return { status: 'unverifiable', message: 'layer-drift output unparseable', relation: 'unknown' };
  }
}

// --- Auto sync (REUSE aai-update.{sh,ps1}; its canonical guard is authoritative)

// Pick the PowerShell host on Windows (Finding 7): pwsh (PowerShell 7+) if it is
// available, else fall back to powershell.exe (Windows PowerShell 5.1). Before
// this, `pwsh` was looked up unconditionally, so a 5.1-only host ENOENTs and
// EVERY auto-update records failure instead of running the 5.1-compatible
// aai-update.ps1. Mirrors resolveRunner(['pwsh','powershell']) in
// lib/test-canon-core.mjs. `isAvailable` is injectable for a focused unit test.
export function resolvePwsh(isAvailable = pwshAvailable) {
  return isAvailable('pwsh') ? 'pwsh' : 'powershell.exe';
}

function pwshAvailable(exe) {
  try {
    const r = spawnSync(exe, ['-NoProfile', '-Command', 'exit 0'], {
      stdio: 'ignore',
      timeout: 5_000,
    });
    return !r.error && r.status === 0;
  } catch {
    return false;
  }
}

// Build the spawnSync options for an aai-update sync. A bounded timeout here is a
// WATCHDOG: the DETACHED --run-sync child passes timeoutMs=null so the sync runs
// to COMPLETION (Finding 6) — a clone+copy can outlast any fixed bound, and a
// SIGKILL mid-copy leaves a partial layer plus a bogus generic failure outcome,
// contradicting the detached-to-completion guarantee. The short bounded watchdog
// stays ONLY on the hook's fast DETECTION path (runLayerDrift), never on the
// sync itself. Exported for a focused unit test of the selection.
export function buildSyncSpawnOptions(timeoutMs, cwd) {
  const opts = { encoding: 'utf8', cwd };
  if (timeoutMs != null) opts.timeout = timeoutMs + 30_000; // a sync clones/copies
  return opts;
}

function runAaiUpdate({ source, timeoutMs, cwd }) {
  const isWin = process.platform === 'win32';
  const script = path.join(SELF_DIR, isWin ? 'aai-update.ps1' : 'aai-update.sh');
  let cmd, cmdArgs;
  if (isWin) {
    cmd = resolvePwsh();
    cmdArgs = ['-NoProfile', '-File', script];
    if (source) cmdArgs.push('-Repo', source);
  } else {
    cmd = 'bash';
    cmdArgs = [script];
    if (source) cmdArgs.push('--repo', source);
  }
  const res = spawnSync(cmd, cmdArgs, buildSyncSpawnOptions(timeoutMs, cwd));
  const stdout = res.stdout || '';
  const stderr = res.stderr || '';
  // aai-update refuses on the canonical repo with exit 2 + a REFUSED note.
  const refused = res.status === 2 || /REFUSED/i.test(stderr);
  return { status: res.status, refused, stdout, stderr, timedOut: res.error?.code === 'ETIMEDOUT' };
}

// --- Detached auto-sync + report-next-session ---------------------------------
// The auto path must NOT block session start and must NEVER lose the sync
// outcome. So on a `behind` verdict in auto mode we spawn the aai-update sync
// FULLY DETACHED (its own session/process group; own stdio) and return
// immediately. The detached child writes a persistent OUTCOME LOG under
// .aai/cache/ (gitignored, excluded from the PROFILES union); the NEXT run
// surfaces that outcome once. The detach is deliberate, reaped (unref'd), and
// logged — no orphan surprise. A `running` marker (written synchronously here
// BEFORE the spawn) is the concurrent-sync guard: a second run never launches a
// duplicate while one is in flight.

function readOutcome(outcomePath) {
  try {
    return JSON.parse(fs.readFileSync(outcomePath, 'utf8'));
  } catch {
    return null; // absent/corrupt outcome -> nothing to report, no in-flight sync
  }
}

function writeOutcome(outcomePath, obj) {
  try {
    fs.mkdirSync(path.dirname(outcomePath), { recursive: true });
    fs.writeFileSync(outcomePath, JSON.stringify(obj) + '\n');
  } catch {
    // best-effort: an unwritable outcome log must never break the check
  }
}

// A sync is in flight iff a non-stale `running` marker exists.
function syncInFlight(outcome, nowMs) {
  if (!outcome || outcome.result !== 'running') return false;
  const started = Date.parse(outcome.started_utc);
  if (Number.isNaN(started)) return false;          // malformed -> treat as free
  if (started > nowMs) return false;                // future-dated started_utc:
  // (now - started) is NEGATIVE and <= SYNC_STALE_MS, which would WEDGE the guard
  // (auto mode stuck reporting "in progress") until wall-clock catches up. Treat
  // it as NOT in flight (free to launch), mirroring the future-dated
  // throttle-cache guard in withinThrottle.
  return (nowMs - started) <= SYNC_STALE_MS;         // stale -> allow a fresh sync
}

// --- Atomic concurrent-sync claim (RR-1) --------------------------------------
// The `running` marker is a cross-process TOCTOU: read-marker -> decide ->
// spawn -> write-marker has no OS-level lock, so N truly-simultaneous session
// starts each spawn a detached aai-update sync (probe: 5 parallel -> 5 syncs).
// The fix is an ATOMIC claim on a SEPARATE lock file (the outcome log
// legitimately pre-exists, so an O_EXCL create there would wrongly fail).
// fs.openSync(..., 'wx') is O_CREAT|O_EXCL: exactly one caller creates the file;
// the rest get EEXIST and back off to the existing "in progress" path.

// The lock lives beside the outcome log (gitignored .aai/cache/, PROFILES-
// excluded), a SEPARATE file so the O_EXCL create is a true claim.
function syncLockPath(outcomePath) {
  return path.join(path.dirname(outcomePath), 'update-sync.lock');
}

function lockMtimeMs(lockPath) {
  try {
    return fs.statSync(lockPath).mtimeMs;
  } catch {
    return NaN;
  }
}

// Is an existing lock reclaimable (a crashed/abandoned sync)? Reuses the SAME
// >30min window as the running marker so auto mode NEVER wedges. The staleness
// test is SYMMETRIC — reclaimable iff |now - started| > SYNC_STALE_MS — for a
// deliberate reason: a genuinely future-dated / clock-skewed / corrupt lock
// (e.g. started_utc in 2099) is far in the future and IS reclaimed (mirrors the
// existing future-date guards, never wedges), BUT a lock a live racer wrote
// microseconds ago can read as slightly "future" relative to THIS process's
// own clock snapshot (each process reads its own `now`), and that near-future
// lock must NOT be reclaimed — reclaiming it is exactly the duplicate-spawn race
// (RR-1) this fix closes. A small (< 30min) skew in either direction means the
// sync is live. A PARSEABLE lock is aged by its started_utc; a NaN timestamp is
// reclaimable. A TORN/empty/corrupt lock (the O_EXCL create is visible before
// the winner's content write lands) is aged by its FILE mtime instead, same
// symmetric window, so a racer mid-write is NOT reclaimed while a genuinely
// abandoned corrupt lock (old mtime) still ages out.
function lockIsStale(lockPath, nowMs) {
  let raw;
  try {
    raw = fs.readFileSync(lockPath, 'utf8');
  } catch {
    return true; // vanished between EEXIST and read -> free to (re)claim
  }
  let parsed = null;
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = null;
  }
  if (parsed) {
    const started = Date.parse(parsed.started_utc);
    if (Number.isNaN(started)) return true; // NaN timestamp -> reclaimable
    return Math.abs(nowMs - started) > SYNC_STALE_MS;
  }
  // torn/empty/corrupt content: age by mtime (same symmetric window).
  const m = lockMtimeMs(lockPath);
  if (Number.isNaN(m)) return true;          // vanished -> reclaimable
  return Math.abs(nowMs - m) > SYNC_STALE_MS;
}

// A monotonic per-process counter makes each temp/aside path unique even for
// rapid successive claims from the same pid.
let lockSeq = 0;

// Atomically create a lock file that carries its FULL content the instant it
// becomes visible — no torn window. openSync(..., 'wx')+writeSync is O_EXCL but
// leaves a window in which the file EXISTS yet is EMPTY (created, not-yet-
// written); a concurrent reader then sees empty content and falls back to
// mtime-aging, which is WRONG whenever the caller's clock (e.g. an injected
// --now) differs from the file's real wall-clock mtime — a fresh-but-torn lock
// reads as "stale" and gets falsely reclaimed (a real duplicate-spawn path).
// Instead we write a per-pid temp with the content FIRST, then hard-link it into
// place: linkSync throws EEXIST if the target exists (the same exclusive-create
// guarantee as O_EXCL), and the target has full content from its first instant.
// Throws an EEXIST-coded error when the target already exists; the temp is always
// cleaned up.
function claimLockFile(targetPath, body) {
  const tmp = `${targetPath}.tmp.${process.pid}.${lockSeq++}`;
  fs.writeFileSync(tmp, body);
  try {
    fs.linkSync(tmp, targetPath); // exclusive create; EEXIST if targetPath exists
  } finally {
    try { fs.rmSync(tmp, { force: true }); } catch { /* best-effort temp cleanup */ }
  }
}

// The reclaim lock lives beside the main lock; it serializes stale-lock reclaim.
function reclaimLockPathFor(lockPath) {
  return lockPath + '.reclaim';
}

// Acquire the short-lived, EXCLUSIVE right to reclaim a stale main lock. Returns
// true iff THIS process may proceed to swap the stale lock. Serializing the
// reclaim is what makes it atomic: a plain read-stale -> rm -> create (or a
// rename+verify) reclaim CANNOT be made atomic on its own, because a racer that
// decided "stale" from the OLD lock can still act on a FRESH lock a prior
// reclaimer just installed (deleting/stealing it -> a SECOND spawn: the RR-1
// residual). Under this exclusive lock, only the holder does
// check-stale-then-swap, and it RE-CHECKS staleness after gaining exclusivity,
// so a stale decision can never be acted on against a fresh lock. The reclaim
// lock is held only for the microseconds of the swap; a crashed holder's reclaim
// lock ages out (SYNC_STALE_MS) and is recovered via a rename arbiter — a
// genuinely fresh reclaim lock (held ~microseconds) is never 30-min stale, so
// recovery never fires against a live holder.
function acquireReclaimLock(rlPath, nowMs, body) {
  try {
    claimLockFile(rlPath, body);
    return true;
  } catch (e) {
    if (e.code !== 'EEXIST') return false;
    if (!lockIsStale(rlPath, nowMs)) return false; // another reclaimer is active
    // Crashed holder's abandoned reclaim lock (>30min): recover via a rename
    // arbiter — exactly one racer moves it aside; the losers ENOENT and back off.
    const aside = `${rlPath}.rec.${process.pid}.${lockSeq++}`;
    try { fs.renameSync(rlPath, aside); } catch { return false; }
    try { fs.rmSync(aside, { force: true }); } catch { /* best-effort */ }
    try { claimLockFile(rlPath, body); return true; } catch { return false; }
  }
}

function releaseReclaimLock(rlPath) {
  try {
    fs.rmSync(rlPath, { force: true });
  } catch {
    // best-effort: a crash leaves a stale reclaim lock the >30min rule reclaims
  }
}

// Atomically claim the right to spawn the detached sync. Returns true iff THIS
// process holds the claim. Cold start is arbitrated by the exclusive create; a
// STALE lock is reclaimed under the exclusive reclaim lock so exactly one racer
// ever wins — and a crashed sync never wedges auto mode.
function acquireSyncLock(lockPath, nowMs, nowIso) {
  try {
    fs.mkdirSync(path.dirname(lockPath), { recursive: true });
  } catch {
    // best-effort: an unwritable cache dir must never break the check
  }
  const body = JSON.stringify({ pid: process.pid, started_utc: nowIso }) + '\n';
  try {
    claimLockFile(lockPath, body);
    return true;                             // cold-start: exactly one exclusive winner
  } catch (e) {
    if (e.code !== 'EEXIST') return false;   // unexpected error -> do NOT spawn
    if (!lockIsStale(lockPath, nowMs)) return false; // a live sync holds it
    // Stale lock: reclaim under the EXCLUSIVE reclaim lock so exactly one racer
    // performs the swap (concurrent stale-reclaim atomicity — RR-1 full closure).
    const rlPath = reclaimLockPathFor(lockPath);
    if (!acquireReclaimLock(rlPath, nowMs, body)) return false; // another reclaimer -> back off
    try {
      // Exclusive now. RE-CHECK: a prior holder may already have reclaimed and
      // installed a fresh lock — if so it is no longer stale and we back off,
      // never stealing it.
      if (!lockIsStale(lockPath, nowMs)) return false;
      try { fs.rmSync(lockPath, { force: true }); } catch { /* a racer may have */ }
      // The exclusive create is the final single-winner arbiter for the brief
      // window in which we hold exclusivity: normally we win; if a late
      // cold-start racer's own create slipped into the emptied path first, we
      // lose it and back off (still exactly one spawner).
      try { claimLockFile(lockPath, body); return true; }
      catch { return false; }
    } finally {
      releaseReclaimLock(rlPath);
    }
  }
}

function releaseSyncLock(lockPath) {
  try {
    fs.rmSync(lockPath, { force: true });
  } catch {
    // best-effort: a crash leaves a stale lock the >30min rule reclaims
  }
}

// Spawn `node <self> --run-sync ...` fully detached, with its own stdio (never
// inherits the parent's — so it can't hold the SessionStart hook's pipe open).
// Returns true if the child was launched.
function spawnDetachedSync({ source, outcome, targetVersion, timeoutMs, cwd }) {
  const selfPath = fileURLToPath(import.meta.url);
  const argv = [selfPath, '--run-sync', '--outcome', outcome, '--timeout-ms', String(timeoutMs)];
  if (source) argv.push('--source', source);
  if (targetVersion) argv.push('--target-version', targetVersion);
  // Redirect the child's own stdout/stderr to a persistent log (a last-resort
  // record if the child dies before writing structured JSON). Fall back to
  // 'ignore' if the log can't be opened; NEVER inherit the parent's stdio.
  let outFd = 'ignore';
  const logPath = path.join(path.dirname(outcome), 'update-sync.log');
  try {
    fs.mkdirSync(path.dirname(logPath), { recursive: true });
    outFd = fs.openSync(logPath, 'a');
  } catch {
    outFd = 'ignore';
  }
  try {
    const child = spawn('node', argv, {
      cwd,
      detached: true,                              // own session/process group
      stdio: ['ignore', outFd, outFd],
    });
    child.unref();                                 // parent may exit immediately
    return true;
  } catch {
    return false;
  } finally {
    if (typeof outFd === 'number') { try { fs.closeSync(outFd); } catch { /* noop */ } }
  }
}

// The detached child: run the sync to completion (no watchdog — it is detached),
// then record a structured outcome the next run will surface. Always exits 0.
function runSyncMode(args) {
  const existing = readOutcome(args.outcome);
  const started_utc =
    existing && existing.result === 'running' && existing.started_utc
      ? existing.started_utc
      : new Date().toISOString();
  // timeoutMs=null: run to COMPLETION with NO watchdog (Finding 6). This is the
  // detached child; a bounded timeout would SIGKILL a slow clone/sync mid-copy,
  // leaving a partial layer + a bogus failure outcome.
  const sync = runAaiUpdate({ source: args.source, timeoutMs: null, cwd: process.cwd() });
  let result;
  let detail;
  if (sync.refused) {
    result = 'refused';
    detail = 'canonical repo (origin slug == update source); nothing changed';
  } else if (sync.status === 0) {
    result = 'applied';
    detail = (sync.stdout || '').trim().slice(-500) || 'sync applied';
  } else {
    result = 'failed';
    detail = ((sync.stderr || sync.stdout || '').trim().slice(-500))
      || (sync.timedOut ? 'sync timed out' : `sync exited ${sync.status}`);
  }
  writeOutcome(args.outcome, {
    started_utc,
    finished_utc: new Date().toISOString(),
    target_version: args.targetVersion || null,
    result,
    detail,
    reported: false,
  });
  // Release the atomic claim (success OR failure) so the next eligible run may
  // claim. A crash before here leaves a stale lock the >30min rule reclaims.
  releaseSyncLock(syncLockPath(args.outcome));
  process.exit(0);
}

// Surface a completed-but-unreported detached-sync outcome ONCE, then mark it
// reported. Runs BEFORE the throttle fast path so an outcome is never withheld
// just because the network probe is throttled this session.
//
// Once-only under TRUE concurrency (RR-2): read->print->flip-reported is a
// cross-process TOCTOU, so N simultaneous sessions could each print the line.
// The guard is an ATOMIC rename claim: fs.renameSync moves the whole outcome
// file (content is never torn, unlike an O_EXCL create), so at most one
// simultaneous run captures it; the losers' rename fails (source already moved)
// and they surface nothing. The winner re-checks the CAPTURED content (a racer
// may have flipped reported:true and recreated the file between our peek and our
// rename) before printing. Sequential behavior is unchanged (surface once).
// `readClaim` is injectable purely so a focused unit test can force the
// post-claim read to throw (a torn read is not otherwise deterministically
// reproducible after a same-process rename); production always uses the default.
export function surfaceOutcome(outcomePath, emit, result,
  readClaim = (p) => JSON.parse(fs.readFileSync(p, 'utf8'))) {
  const peek = readOutcome(outcomePath);
  if (!peek || peek.reported || peek.result === 'running' || !peek.finished_utc) return;
  // PER-PID claim path (not a shared '.surfacing'): the SOURCE outcomePath can be
  // renamed only once, so exactly one racer still wins the capture — but a unique
  // destination means no racer ever rmSync's ANOTHER racer's claim. With a shared
  // path, a loser (peeked reported:false) could rename the winner's just-recreated
  // reported:true outcome onto the same '.surfacing' and the winner's rmSync would
  // then delete it -> the outcome file is LOST (benign already-surfaced tombstone,
  // but it made TEST-026 flaky under load). Same fix class as claimLockFile.
  const claimPath = `${outcomePath}.surfacing.${process.pid}.${lockSeq++}`;
  try {
    fs.renameSync(outcomePath, claimPath); // atomic claim; exactly one racer wins
  } catch {
    return; // a concurrent run already claimed the outcome (or it vanished)
  }
  // The claim rename succeeded: the ONLY copy of the outcome now lives at
  // claimPath. If the read/parse throws (a torn write observed mid-write, or a
  // transient fs error), returning here would ORPHAN the outcome at .surfacing
  // with the real path gone -> it would never surface. RESTORE it (best-effort)
  // so a later run surfaces it; print nothing (once-only preserved).
  let oc;
  try {
    oc = readClaim(claimPath);
  } catch {
    try { fs.renameSync(claimPath, outcomePath); } catch { /* best-effort restore */ }
    return;
  }
  // Re-check the captured content: a racer may have already surfaced + recreated
  // the file as reported:true between our peek and our rename. If so, restore
  // the authoritative state and surface nothing.
  if (!oc || oc.reported || oc.result === 'running' || !oc.finished_utc) {
    writeOutcome(outcomePath, oc);
    try { fs.rmSync(claimPath, { force: true }); } catch { /* best-effort */ }
    return;
  }
  const ver = oc.target_version ? ` ${oc.target_version}` : '';
  if (oc.result === 'applied') {
    emit.push(`AAI auto-update applied${ver} — review the diff (git diff) before committing.`);
  } else if (oc.result === 'refused') {
    emit.push('AAI auto-update refused (canonical repo) — nothing changed. '
      + 'This project is the update source; use normal git here.');
  } else {
    // aai-update.sh can modify files before failing mid-copy, so a "No changes
    // were forced" claim would be misleading (Finding 3). Point at git status /
    // git diff and a manual rerun instead of asserting cleanliness.
    emit.push(`AAI auto-update failed${oc.detail ? `: ${oc.detail}` : ''} — `
      + 'inspect `git status` / `git diff` (the sync may have changed files '
      + 'before failing) and rerun /aai-update if needed.');
  }
  result.reported_outcome = oc.result;
  writeOutcome(outcomePath, { ...oc, reported: true }); // recreate, reported once
  try { fs.rmSync(claimPath, { force: true }); } catch { /* best-effort */ }
}

// --- Orchestration (pure over injected effects, testable) ---------------------
function main() {
  const args = parseArgs(process.argv);
  if (args.runSync) return runSyncMode(args); // detached background-sync child
  const nowIso = args.now || new Date().toISOString();
  const nowMs = Date.parse(nowIso);
  if (Number.isNaN(nowMs)) fail(`--now is not a valid ISO 8601 timestamp: ${args.now}`);

  const cfg = resolveConfig(args.config);
  const emit = [];
  const result = {
    effective_mode: cfg.mode, throttled: false, verdict: null, action: 'none',
    reported_outcome: null,
  };

  // Report-next-session: surface a completed detached-sync outcome BEFORE the
  // throttle fast path (a throttled probe must not withhold a finished outcome).
  surfaceOutcome(args.outcome, emit, result);

  // Throttle fast path — skip the probe entirely (TEST-009: no layer-drift call).
  const lastMs = readLastCheck(args.cache);
  if (withinThrottle(lastMs, cfg.throttle_hours, nowMs, args.force)) {
    result.throttled = true;
    if (args.json) console.log(JSON.stringify(result));
    else if (emit.length) console.log(emit.join('\n'));
    process.exit(0);
  }

  const verdict = runLayerDrift({ pin: args.pin, remote: args.remote, timeoutMs: args.timeoutMs });
  result.verdict = verdict.status;

  if (verdict.status === 'up_to_date') {
    // quiet; refresh cache.
    refreshCache(args.cache, nowIso);
  } else if (verdict.status === 'behind') {
    // ALWAYS surface the availability line for a `behind` verdict — in BOTH
    // modes (the safe fact: a newer release exists).
    const detail = verdict.message ? ` (${verdict.message})` : '';
    if (cfg.mode === 'auto') {
      emit.push(`AAI: a newer AAI release is available${detail}.`);
      const targetVersion = (verdict.canonical_head || '').slice(0, 7) || null;
      // Source agreement (Finding 5): sync from the SAME source layer-drift just
      // verified. aai-update defaults to goodwind-cz/aai, but layer-drift may
      // have checked an ALTERNATE canonical named in AAI_PIN.md (its resolved
      // `remote`); syncing from the default would overwrite the layer from an
      // UNRELATED upstream on a `behind` verdict. Detection and sync must agree
      // on ONE source of truth. A hand-passed --source still wins.
      const syncSource = args.source || verdict.remote || null;
      // Concurrent-sync guard. The `running` marker is a fast early-out, but the
      // AUTHORITATIVE guard against N truly-simultaneous starts is the ATOMIC
      // O_EXCL claim (RR-1): exactly one caller creates update-sync.lock and
      // spawns; the losers back off. A stale/future/torn lock is reclaimed so a
      // crashed sync never wedges auto mode.
      const lockPath = syncLockPath(args.outcome);
      const inFlight = syncInFlight(readOutcome(args.outcome), nowMs);
      const claimed = inFlight ? false : acquireSyncLock(lockPath, nowMs, nowIso);
      if (inFlight || !claimed) {
        result.action = 'sync_in_flight';
        emit.push('AAI auto-update: a background sync is already in progress — '
          + 'its outcome will be reported next session.');
      } else {
        // Claim held. Write the `running` marker then spawn the sync DETACHED so
        // it survives past this fast, non-blocking run.
        writeOutcome(args.outcome, {
          started_utc: nowIso, finished_utc: null, target_version: targetVersion,
          result: 'running', detail: null, reported: false,
        });
        const launched = spawnDetachedSync({
          source: syncSource, outcome: args.outcome, targetVersion,
          timeoutMs: args.timeoutMs, cwd: process.cwd(),
        });
        if (launched) {
          result.action = 'sync_spawned';
          emit.push('AAI auto-update: applying the update in the background (detached) — '
            + 'the outcome will be reported next session.');
        } else {
          // Could not launch — release the claim + clear the running marker so a
          // later run retries.
          releaseSyncLock(lockPath);
          result.action = 'sync_launch_failed';
          writeOutcome(args.outcome, {
            started_utc: nowIso, finished_utc: new Date().toISOString(),
            target_version: targetVersion, result: 'failed',
            detail: 'could not launch the background sync', reported: false,
          });
          emit.push('AAI auto-update could not start the background sync — '
            + 'run /aai-update manually.');
        }
      }
    } else {
      result.action = 'notify';
      emit.push(`AAI: a newer AAI release is available${detail} — run /aai-update.`);
    }
    refreshCache(args.cache, nowIso);
  } else {
    // unverifiable — degrade note; do NOT refresh cache (retry next session);
    // NEVER sync (only a `behind` verdict triggers a sync).
    result.action = 'could_not_check';
    emit.push('AAI: could not check for AAI updates (offline or canonical '
      + 'unreachable) — will retry next session.');
  }

  if (args.json) {
    console.log(JSON.stringify(result));
  } else if (emit.length) {
    console.log(emit.join('\n'));
  }
  process.exit(0);
}

// Allow `import { resolveConfig }` from tests without running the CLI.
// Mirror layer-drift.mjs: compare decoded, symlink-resolved paths.
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main();
}
