#!/usr/bin/env node
// session-lock.mjs — per-worktree session lock (CHANGE-0180 D5,
// fu-learned-worktree-seeded-copies / docs/specs/SPEC-0179-spec-test-framework-sweep.md).
//
// WHY THIS EXISTS. A shared checkout can host two live agent sessions at
// once, and the second `git checkout` moves HEAD out from under the first
// mid-ceremony (the P1 scar of 2026-09-06). Detecting that after the fact is
// branch-guard.mjs's `--pin`/`--verify-pin` (CHANGE-0180 D4); this module is
// the OTHER half — refusing the second session up front rather than only
// catching the collision downstream.
//
// LOCATION. `$(git rev-parse --git-dir)/aai/session.lock` — beside the pin
// file branch-guard.mjs writes (D4/D5), for the same reason: `--git-dir`
// resolves to a DISTINCT path per linked worktree (and the main checkout's
// own `.git`), never one path shared across worktrees, so the lock is
// per-worktree by construction and owes no `.gitignore` entry.
//
// LIVENESS, NOT A TTL. A TTL long enough to cover a ceremony is too long to
// reclaim after a crash; a `pid` that is gone is the one signal that is both
// cheap and certain (D5). `acquire` is a `fs.openSync(p, 'wx')` CAS exactly
// like `docs-lock.mjs`'s O_EXCL arbiter; on EEXIST it probes the holder pid
// with `process.kill(pid, 0)` — alive refuses (exit 3, naming the pid and
// worktree), dead reclaims. The reclaim is serialized through the SAME
// short-lived O_EXCL sentinel shape `docs-lock.mjs` uses (`<lock>.reclaim`),
// so a dead holder's lock can never be double-claimed by two reclaimers at
// once, and a FRESH lock created in the gap is never clobbered.
//
// Heartbeat files are never read here — a gate reading a heartbeat is
// forbidden by a tested rule of this repository (D5); this lock is its own,
// independent, deliberately narrow signal.
//
// Payload: {pid, worktree, ref_id, acquired_utc}. No `owner`/`ttl_seconds`
// fields — this lock's whole claim is "this pid, in this worktree, is alive
// right now", not an identity or a lease.
//
// CLI (used by tests and, eventually, the ceremony scripts):
//   node session-lock.mjs acquire [--pid <n>] [--ref <ref_id>]
//   node session-lock.mjs release [--pid <n>]
//   node session-lock.mjs status
// `--pid` defaults to this process's own pid; tests pass an explicit
// long-lived (or already-dead) pid to exercise the liveness branches without
// needing this CLI invocation itself to stay alive.
//
// Exit codes: 0 acquired/released/status printed; 3 held by a live pid
// (acquire) or a stuck reclaim; 4 release by a non-holder pid; 2 usage error.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './cli-pipe-guard.mjs';

const SENTINEL_STALE_MS = 30_000;
const MAX_RECLAIM_ATTEMPTS = 64;

function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function git(args, cwd) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
}

function gitDir(cwd) {
  return git(['rev-parse', '--git-dir'], cwd);
}

function topLevel(cwd) {
  return git(['rev-parse', '--show-toplevel'], cwd);
}

// Per-worktree by construction (see header). Exported so tests can assert the
// resolved path directly rather than re-deriving it.
export function lockDir(cwd) {
  return path.join(path.resolve(cwd, gitDir(cwd)), 'aai');
}

export function lockPath(cwd) {
  return path.join(lockDir(cwd), 'session.lock');
}

// process.kill(pid, 0) throws ESRCH when the pid is gone, and EPERM when it
// exists but is owned by someone else — EPERM therefore still means "alive".
function isPidAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return Boolean(err && err.code === 'EPERM');
  }
}

function readLock(p) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null; // missing, empty, or corrupt — never throws the caller closed
  }
}

function sentinelIsStale(sp, now = Date.now()) {
  try {
    return now - fs.statSync(sp).mtimeMs > SENTINEL_STALE_MS;
  } catch {
    return false; // already gone
  }
}

// acquire({cwd, pid, refId}) -> {ok:true} | {ok:false, code, holderPid, holderWorktree}
export function acquire({ cwd, pid, refId }) {
  const dir = lockDir(cwd);
  fs.mkdirSync(dir, { recursive: true });
  const p = path.join(dir, 'session.lock');
  const sentinelPath = `${p}.reclaim`;
  const worktree = topLevel(cwd);
  const payload = JSON.stringify({ pid, worktree, ref_id: refId ?? null, acquired_utc: new Date().toISOString() });

  for (let attempt = 0; attempt < MAX_RECLAIM_ATTEMPTS; attempt += 1) {
    let fd;
    try {
      fd = fs.openSync(p, 'wx'); // O_WRONLY|O_CREAT|O_EXCL
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      const existing = readLock(p);
      if (existing && isPidAlive(existing.pid)) {
        return { ok: false, code: 3, holderPid: existing.pid, holderWorktree: existing.worktree };
      }
      // Dead (or corrupt/unreadable) holder — reclaim under the sentinel, the
      // same double-claim guard docs-lock.mjs's expired-reclaim path uses: a
      // blind unlink-then-create here would let two reclaimers both win.
      let sfd;
      try {
        sfd = fs.openSync(sentinelPath, 'wx');
      } catch (se) {
        if (se.code !== 'EEXIST') throw se;
        if (sentinelIsStale(sentinelPath)) {
          try { fs.rmSync(sentinelPath, { force: true }); } catch { /* gone */ }
        }
        sleepMs(2);
        continue;
      }
      let outcome;
      try {
        try {
          fs.writeSync(sfd, JSON.stringify({ pid, at: new Date().toISOString() }));
        } catch { /* best effort — stale detection still works off mtime */ }
        const cur = readLock(p);
        if (cur && isPidAlive(cur.pid)) {
          outcome = { held: cur }; // a peer reclaimed first and is alive
        } else {
          if (cur) { try { fs.rmSync(p, { force: true }); } catch { /* gone */ } }
          try {
            const nfd = fs.openSync(p, 'wx');
            fs.writeSync(nfd, payload);
            fs.closeSync(nfd);
            outcome = { ok: true };
          } catch (ce) {
            if (ce.code !== 'EEXIST') throw ce;
            outcome = { held: readLock(p) };
          }
        }
      } finally {
        fs.closeSync(sfd);
        try { fs.rmSync(sentinelPath, { force: true }); } catch { /* gone */ }
      }
      if (outcome.ok) return { ok: true };
      const h = outcome.held || {};
      return { ok: false, code: 3, holderPid: h.pid ?? null, holderWorktree: h.worktree ?? null };
    }
    try {
      fs.writeSync(fd, payload);
    } finally {
      fs.closeSync(fd);
    }
    return { ok: true };
  }
  return { ok: false, code: 3, holderPid: null, holderWorktree: null, reclaimStuck: true };
}

// release({cwd, pid}) -> {ok:true} | {ok:false, code:4, holderPid}
// Idempotent when nothing is held (no lock file -> ok:true, noop:true).
export function release({ cwd, pid }) {
  const p = lockPath(cwd);
  if (!fs.existsSync(p)) return { ok: true, noop: true };
  const lk = readLock(p);
  if (!lk) {
    // Corrupt lock — cannot verify ownership by pid; safest is to leave it
    // for a human/CI to look at rather than clobber an unreadable claim.
    return { ok: false, code: 4, holderPid: null };
  }
  if (lk.pid !== pid) {
    return { ok: false, code: 4, holderPid: lk.pid };
  }
  fs.rmSync(p, { force: true });
  return { ok: true };
}

export function status(cwd) {
  const p = lockPath(cwd);
  const lk = readLock(p);
  if (!lk) return { held: false };
  return { held: true, pid: lk.pid, worktree: lk.worktree, ref_id: lk.ref_id ?? null, acquired_utc: lk.acquired_utc, alive: isPidAlive(lk.pid) };
}

// ---- CLI ----

function usage() {
  console.error('Usage: node session-lock.mjs <acquire|release|status> [--pid <n>] [--ref <ref_id>]');
}

function parseArgs(argv) {
  const opts = { pid: process.pid, ref: null };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--pid') {
      const v = argv[++i];
      if (!v || Number.isNaN(Number(v))) { console.error('session-lock: --pid requires a numeric value'); exit(2); }
      opts.pid = Number(v);
    } else if (tok === '--ref') {
      opts.ref = argv[++i];
    } else {
      console.error(`session-lock: unknown flag "${tok}"`);
      exit(2);
    }
  }
  return opts;
}

function main() {
  const argv = process.argv.slice(2);
  const sub = argv[0];
  const cwd = process.cwd();
  if (sub === 'acquire') {
    const opts = parseArgs(argv.slice(1));
    const r = acquire({ cwd, pid: opts.pid, refId: opts.ref });
    if (r.ok) {
      console.log(`session-lock: acquired (pid ${opts.pid})`);
      exit(0);
    }
    console.error(`session-lock: held by pid ${r.holderPid} in worktree ${r.holderWorktree} — refusing (pid is alive)`);
    exit(r.code);
  } else if (sub === 'release') {
    const opts = parseArgs(argv.slice(1));
    const r = release({ cwd, pid: opts.pid });
    if (r.ok) {
      console.log(r.noop ? 'session-lock: released (was not held)' : 'session-lock: released');
      exit(0);
    }
    console.error(`session-lock: held by pid ${r.holderPid}, not ${opts.pid} — refusing to release`);
    exit(r.code);
  } else if (sub === 'status') {
    console.log(JSON.stringify(status(cwd)));
    exit(0);
  } else {
    usage();
    exit(2);
  }
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
const isMain = process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url));
if (isMain) runMain(() => main());
