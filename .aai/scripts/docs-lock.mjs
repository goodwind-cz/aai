#!/usr/bin/env node
// Atomic scope-lock CLI (RFC-0004 / SPEC-0004) — enforced multi-agent STATE locking.
//
// Coordinates K parallel subagents under one orchestrator by serializing access
// to a named scope through an atomic, TTL-leased lock file. The acquire CAS is a
// SINGLE syscall — fs.openSync(lockPath, 'wx') (O_WRONLY|O_CREAT|O_EXCL) — which
// creates the lock iff it does not exist and throws EEXIST otherwise, so two
// concurrent acquires of one scope can NEVER both succeed (SPEC-0004 D1/D4).
//
// Lock files live at docs/ai/locks/<safe-scope>.lock (per-agent-local, gitignored)
// and hold one JSON payload: {scope, owner, acquired_utc, ttl_seconds, pid}.
// The directory is overridable via AAI_LOCK_DIR (used by the test harness so it
// never touches the real lock dir).
//
// Usage:
//   docs-lock acquire <scope> <owner> [--ttl <seconds>]   atomically claim a scope
//   docs-lock release <scope> <owner>                      release a scope you own
//   docs-lock list [--json]                                show current locks
//   docs-lock reap                                         delete expired locks
//
// Exit codes (so the orchestrator can branch deterministically, SPEC-0004 D5):
//   0  success (acquired / released / listed / reaped)
//   2  usage error (missing args / unknown subcommand)
//   3  acquire contention (scope held by a live, non-expired lock)
//   4  release ownership violation (lock held by a different owner)
// release of an unheld scope is idempotent success (0).

import fs from 'node:fs';
import path from 'node:path';

const DEFAULT_TTL = 1800; // seconds (30 min) — SPEC-0004 D3
const LOCKS_DIR = process.env.AAI_LOCK_DIR
  ? path.resolve(process.env.AAI_LOCK_DIR)
  : path.join(process.cwd(), 'docs/ai/locks');

// Reclaiming an EXPIRED lock is serialized through a short-lived O_EXCL sentinel
// (`<lock>.reclaim`) so exactly one acquirer removes-and-recreates the dead
// lock and a FRESH lock is never clobbered (review E1). A real reclaim is a few
// syscalls; a sentinel older than this bound must be a leak from a dead acquirer
// and is safe to steal/reap (never removes a live, microsecond-held sentinel).
const SENTINEL_STALE_MS = 30_000;
const MAX_RECLAIM_ATTEMPTS = 64; // bounded spin while a peer reclaim is in flight

// Synchronous sleep with no busy-wait (Atomics.wait on a throwaway buffer).
function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function fail(msg, code = 2) {
  console.error(`docs-lock: ${msg}`);
  process.exit(code);
}

function usage() {
  console.error(
    'Usage: docs-lock <acquire|release|list|reap> [args]\n' +
    '  acquire <scope> <owner> [--ttl <seconds>]   atomically claim a scope (0; 3 if held)\n' +
    '  release <scope> <owner>                      release a scope you own (0; 4 if not yours)\n' +
    '  list [--json]                                show current locks\n' +
    '  reap                                         delete expired locks',
  );
}

function safeScope(scope) {
  return String(scope).replace(/[^A-Za-z0-9._-]/g, '_');
}

function lockPath(scope) {
  return path.join(LOCKS_DIR, `${safeScope(scope)}.lock`);
}

// A leaked reclaim sentinel (its acquirer died mid-reclaim) is stale once older
// than SENTINEL_STALE_MS; a live one is microseconds old and never matches.
function sentinelIsStale(sp, now = Date.now()) {
  try {
    return now - fs.statSync(sp).mtimeMs > SENTINEL_STALE_MS;
  } catch {
    return false; // already gone
  }
}

function readLock(p) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null; // missing, empty, or corrupt/non-JSON
  }
}

// A lock is expired iff now > acquired_utc + ttl_seconds. An unparseable
// timestamp is treated as NOT expired (fail closed — never clobber an unknown
// holder); reap will leave it and acquire will contend (exit 3).
function isExpired(lock, now = Date.now()) {
  if (!lock) return false;
  const acquired = Date.parse(lock.acquired_utc);
  if (Number.isNaN(acquired)) return false;
  const ttl = Number(lock.ttl_seconds);
  if (!Number.isFinite(ttl)) return false;
  return now > acquired + ttl * 1000;
}

function listLockFiles() {
  try {
    return fs.readdirSync(LOCKS_DIR).filter((f) => f.endsWith('.lock'));
  } catch {
    return []; // missing dir -> no locks
  }
}

function parseArgs(argv, start) {
  const positional = [];
  const opts = { ttl: DEFAULT_TTL, json: false };
  for (let i = start; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--ttl') {
      opts.ttl = Number(argv[++i]);
    } else if (tok === '--json') {
      opts.json = true;
    } else if (tok.startsWith('--')) {
      usage();
      fail(`unknown flag "${tok}"`, 2);
    } else {
      positional.push(tok);
    }
  }
  opts._ = positional;
  return opts;
}

function acquire(opts) {
  const [scope, owner] = opts._;
  if (!scope || !owner) {
    usage();
    fail('acquire requires <scope> <owner>', 2);
  }
  const ttl = Number.isFinite(opts.ttl) && opts.ttl > 0 ? Math.floor(opts.ttl) : DEFAULT_TTL;
  fs.mkdirSync(LOCKS_DIR, { recursive: true });
  const p = lockPath(scope);
  const payload = JSON.stringify({
    scope,
    owner,
    acquired_utc: new Date().toISOString(),
    ttl_seconds: ttl,
    pid: process.pid,
  });

  const sentinelPath = `${p}.reclaim`;

  for (let attempt = 0; attempt < MAX_RECLAIM_ATTEMPTS; attempt += 1) {
    // Fast path: O_EXCL create on a FREE scope — the sole atomic CAS arbiter.
    let fd;
    try {
      fd = fs.openSync(p, 'wx'); // O_WRONLY|O_CREAT|O_EXCL
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      const existing = readLock(p);
      if (!isExpired(existing)) {
        // Fresh (or corrupt/unparseable) lock -> fail closed, never clobber.
        fail(`scope "${scope}" is held by ${existing && existing.owner ? existing.owner : 'unknown'} (not expired)`, 3);
      }
      // EXPIRED: serialize the reclaim through an O_EXCL sentinel. A blind
      // unlink/rename of p here is the review-E1 double-claim race — between
      // readLock (sees expired) and the unlink, a competitor can create a FRESH
      // lock at p that the unlink then destroys. Under the sentinel we re-verify
      // expiry with mutual exclusion, so a fresh lock is never removed; the
      // O_EXCL create still arbitrates the (briefly empty) slot among everyone.
      let sfd;
      try {
        sfd = fs.openSync(sentinelPath, 'wx');
      } catch (se) {
        if (se.code !== 'EEXIST') throw se;
        // A peer reclaim is in flight (microseconds) — or the sentinel leaked
        // from a dead acquirer. Steal it only if provably stale, else spin.
        if (sentinelIsStale(sentinelPath)) {
          try { fs.rmSync(sentinelPath, { force: true }); } catch { /* gone */ }
        }
        sleepMs(2);
        continue;
      }

      // We hold the reclaim sentinel. Stamp it (for stale detection) and
      // re-verify p UNDER the lock. Use process.exit-free control flow so the
      // finally ALWAYS releases the sentinel (process.exit skips finally).
      let outcome = null; // { ok, fd } | { held }
      try {
        try { fs.writeSync(sfd, JSON.stringify({ by: owner, pid: process.pid, at: new Date().toISOString() })); } catch { /* best effort */ }
        const cur = readLock(p);
        if (cur && !isExpired(cur)) {
          // A peer reclaimed before us and now holds a fresh lock.
          outcome = { held: cur.owner };
        } else {
          if (cur) { try { fs.rmSync(p, { force: true }); } catch { /* gone */ } }
          // Slot is now empty; O_EXCL-create it. A FAST-PATH acquirer may win
          // this gap first — that's fine, exactly one create succeeds.
          try {
            const nfd = fs.openSync(p, 'wx');
            fs.writeSync(nfd, payload); // write before releasing the sentinel
            fs.closeSync(nfd);
            outcome = { ok: true };
          } catch (ce) {
            if (ce.code !== 'EEXIST') throw ce;
            outcome = { held: (readLock(p) || {}).owner };
          }
        }
      } finally {
        fs.closeSync(sfd);
        try { fs.rmSync(sentinelPath, { force: true }); } catch { /* gone */ }
      }

      if (outcome.ok) {
        console.log(`acquired ${scope} -> ${owner} (ttl ${ttl}s, pid ${process.pid})`);
        return;
      }
      fail(`scope "${scope}" is held by ${outcome.held || 'unknown'} (not expired)`, 3);
    }
    // Fast path won the free slot.
    try {
      fs.writeSync(fd, payload);
    } finally {
      fs.closeSync(fd);
    }
    console.log(`acquired ${scope} -> ${owner} (ttl ${ttl}s, pid ${process.pid})`);
    return;
  }

  // Sentinel contention never settled within the bounded spin (a leaked
  // sentinel younger than SENTINEL_STALE_MS, or pathological churn).
  fail(`scope "${scope}" reclaim did not settle (a sentinel may be stuck; run reap)`, 3);
}

function release(opts) {
  const [scope, owner] = opts._;
  if (!scope || !owner) {
    usage();
    fail('release requires <scope> <owner>', 2);
  }
  const p = lockPath(scope);
  if (!fs.existsSync(p)) {
    console.log(`release ${scope}: no lock held (idempotent no-op)`);
    return; // exit 0
  }
  const lock = readLock(p);
  if (!lock) {
    // Corrupt lock — cannot verify ownership, fail closed rather than clobber.
    fail(`scope "${scope}" lock is unreadable; cannot verify owner ${owner}`, 4);
  }
  if (lock.owner !== owner) {
    fail(`scope "${scope}" is held by ${lock.owner}, not ${owner}`, 4);
  }
  fs.rmSync(p, { force: true });
  console.log(`released ${scope} (was ${owner})`);
}

function list(opts) {
  const now = Date.now();
  const locks = [];
  for (const f of listLockFiles()) {
    const lk = readLock(path.join(LOCKS_DIR, f));
    if (lk) {
      locks.push({
        scope: lk.scope,
        owner: lk.owner,
        acquired_utc: lk.acquired_utc,
        ttl_seconds: lk.ttl_seconds,
        expired: isExpired(lk, now),
      });
    } else {
      locks.push({ scope: f.replace(/\.lock$/, ''), owner: 'unknown', acquired_utc: null, ttl_seconds: null, expired: null, corrupt: true });
    }
  }

  if (opts.json) {
    console.log(JSON.stringify({ count: locks.length, locks }, null, 2));
    return;
  }

  if (locks.length === 0) {
    console.log('no locks held');
    return;
  }
  console.log(`# ${locks.length} lock(s) held`);
  for (const l of locks) {
    console.log(`- ${l.scope}\towner=${l.owner}\tacquired=${l.acquired_utc}\tttl=${l.ttl_seconds}s\texpired=${l.expired}`);
  }
}

function reap() {
  const now = Date.now();
  const reclaimed = [];
  for (const f of listLockFiles()) {
    const p = path.join(LOCKS_DIR, f);
    const lk = readLock(p);
    if (isExpired(lk, now)) {
      try { fs.rmSync(p, { force: true }); } catch { /* already gone */ }
      reclaimed.push(lk.scope || f.replace(/\.lock$/, ''));
    }
  }
  // Also clear reclaim sentinels leaked by a dead acquirer (stale only — never a
  // live, microsecond-held one), so a crashed reclaim never wedges a scope.
  let sentinels = 0;
  try {
    for (const f of fs.readdirSync(LOCKS_DIR)) {
      if (!f.endsWith('.lock.reclaim')) continue;
      const sp = path.join(LOCKS_DIR, f);
      if (sentinelIsStale(sp, now)) {
        try { fs.rmSync(sp, { force: true }); sentinels += 1; } catch { /* gone */ }
      }
    }
  } catch { /* missing dir -> nothing to sweep */ }
  const tail = sentinels > 0 ? ` (+${sentinels} stale sentinel(s))` : '';
  if (reclaimed.length === 0) {
    console.log(`reaped 0 expired lock(s)${tail}`);
  } else {
    console.log(`reaped ${reclaimed.length} expired lock(s): ${reclaimed.join(', ')}${tail}`);
  }
}

function main() {
  const sub = process.argv[2];
  if (!sub || sub === '-h' || sub === '--help') {
    usage();
    process.exit(2);
  }
  const opts = parseArgs(process.argv, 3);
  switch (sub) {
    case 'acquire': return acquire(opts);
    case 'release': return release(opts);
    case 'list': return list(opts);
    case 'reap': return reap(opts);
    default:
      usage();
      fail(`unknown subcommand "${sub}"`, 2);
  }
}

main();
