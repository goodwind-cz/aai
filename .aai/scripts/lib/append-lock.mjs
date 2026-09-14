// append-lock.mjs — serialised appends to an append-only ledger, for a Node
// (.mjs) caller (spec-test-framework-sweep, Spec-AC-10).
//
// A Node PORT of tests/skills/lib/append-lock.sh, not a reinvention: the two
// must agree on the same on-disk protocol (an `mkdir`-created lock directory
// beside the target file, a `stamp` file inside it holding the epoch second
// the lock was taken, a staleness timeout that reclaims an abandoned lock)
// because both are asked to serialise appends to files under docs/ai/, and a
// shell writer and a Node writer contending on two DIFFERENT protocols would
// not exclude each other at all. AAI_APPEND_LOCK_TIMEOUT is the same env
// override the shell library reads, on purpose.
//
// WHY THIS EXISTS (golden-flow.mjs, Spec-AC-10): its own record file
// (docs/ai/tests/golden-flow.jsonl by default) is exactly the kind of ledger
// HAZ-LEDGER protects — append-only, and the discipline is about BYTES: the
// base must stay an exact prefix and every line whole. A single small
// `fs.appendFileSync` is atomic in practice on the filesystems this runs on
// today (confirmed empirically during planning: 12 concurrent bare
// appendFileSync calls produced 12 whole lines, no corruption) — which is
// exactly the "current payload, not the file" property the shell library's
// own header warns is not a promise, only an accident of today's size. This
// library moves the guarantee onto the FILE, the same way the shell one does.
//
// CONTRACT
//   withAppendLock(filePath, fn, { timeoutS }) -> { ok, value } | { ok:false, reason }
//     Acquires the mkdir-mutex `<filePath>.aai-lock`, creates the target's
//     parent directory, runs `fn()` while holding it, and always releases —
//     even when `fn` throws (the lock is freed, the throw still propagates).
//     Returns { ok:false, reason } on a timeout WITHOUT ever calling `fn`:
//     this library never appends around a lock it could not take, mirroring
//     the shell contract's own "it NEVER falls back to an unlocked append"
//     sentence.
//
// Node stdlib only. Uses Atomics.wait on a throwaway SharedArrayBuffer for a
// real, non-CPU-spinning synchronous sleep between polls — the Node
// equivalent of the shell library's blocking `sleep 0.05`.

import fs from 'node:fs';
import path from 'node:path';

const DEFAULT_TIMEOUT_S = 30;
const POLL_MS = 50;

function envTimeoutS() {
  const raw = process.env.AAI_APPEND_LOCK_TIMEOUT;
  if (raw === undefined || raw === '') return DEFAULT_TIMEOUT_S;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_TIMEOUT_S;
}

function sleepMs(ms) {
  // A real, blocking sleep with no CPU spin: Atomics.wait blocks the calling
  // thread in the kernel until the timeout, on an Int32Array nothing else
  // ever touches. This is the main thread of a plain Node CLI process, which
  // is exactly where Atomics.wait is allowed to block.
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// lockAge <lockDir> — seconds since the lock was taken, or null when that
// cannot be established (matches the shell library: an unreadable or
// non-numeric stamp is treated as "cannot say", not as "definitely fresh").
function lockAge(lockDir) {
  let stamp;
  try {
    stamp = fs.readFileSync(path.join(lockDir, 'stamp'), 'utf8').trim();
  } catch {
    return null;
  }
  if (!/^[0-9]+$/.test(stamp)) return null;
  return Math.floor(Date.now() / 1000) - Number(stamp);
}

// acquire <lockDir> <timeoutS> -> boolean. `mkdir` is the portable atomic
// test-and-set, exactly as in the shell library — two processes racing on
// the same mkdir(2) call, exactly one succeeds.
function acquire(lockDir, timeoutS) {
  const maxSpins = Math.max(1, Math.round((timeoutS * 1000) / POLL_MS));
  let spins = 0;
  for (;;) {
    try {
      fs.mkdirSync(lockDir);
      break;
    } catch (e) {
      if (!e || e.code !== 'EEXIST') throw e;
      const age = lockAge(lockDir);
      if (age !== null && age > timeoutS) {
        try {
          fs.rmSync(lockDir, { recursive: true, force: true });
        } catch {
          // Another process may have reclaimed or released it first; loop
          // and try mkdir again rather than treat a race here as fatal.
        }
        continue;
      }
      spins += 1;
      if (spins > maxSpins) return false;
      sleepMs(POLL_MS);
    }
  }
  try {
    fs.writeFileSync(path.join(lockDir, 'stamp'), String(Math.floor(Date.now() / 1000)));
  } catch {
    // The lock is still HELD even if the stamp write failed; a later
    // acquirer that cannot read a stamp treats the age as unknown (never
    // stale), which is the safe direction to fail in.
  }
  return true;
}

function release(lockDir) {
  try {
    fs.rmSync(lockDir, { recursive: true, force: true });
  } catch {
    // Best-effort: a release that cannot remove its own directory leaves a
    // lock that the next acquirer's staleness timeout will eventually reclaim.
  }
}

export function withAppendLock(filePath, fn, opts = {}) {
  const timeoutS = opts.timeoutS ?? envTimeoutS();
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const lockDir = `${filePath}.aai-lock`;
  if (!acquire(lockDir, timeoutS)) {
    return { ok: false, reason: `could not acquire the append lock ${lockDir} within ${timeoutS}s` };
  }
  try {
    const value = fn();
    return { ok: true, value };
  } finally {
    release(lockDir);
  }
}
