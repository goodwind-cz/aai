// runtime-file.mjs — shared runtime-SIDECAR lifecycle primitives
// (CHANGE runtime-state-consolidation, docs/issues/CHANGE-DRAFT-runtime-state-consolidation.md).
//
// Node stdlib only, zero deps (node:fs + node:path). Stateless helpers over MANY
// files — NOT one shared ledger (the unified-ledger design was rejected: it would
// couple unrelated lifecycles and let one corruption kill every feature at once).
//
// WHY THIS EXISTS. Every recent feature that needed local runtime state invented
// its own gitignored sidecar with a hand-rolled lifecycle, and the re-derivation
// is where the defects entered: ~23 substantive lifecycle bugs across four
// sidecar families in ~2 weeks, ~74% first found by EXTERNAL review bots. The
// bugs cluster into six recurring CLASSES (intake "Bug-class analysis"):
//   A. cross-process read-modify-write / TOCTOU race
//   B. silent-empty on a corrupt read (a damaged ledger read as "nothing there")
//   C. future-dated / clock-skew timestamp wedge
//   D. no GC of aside / orphan files
//   E. non-atomic / torn write window
//   F. staleness helper re-implemented (no shared symmetric window / injectable clock)
// Each primitive below is distilled from the two MATURE reference implementations
// (lib/state-engine.mjs atomic tmp+rename, docs-lock.mjs O_EXCL lease) and the
// hard-won update-check.mjs fixes, and is annotated with the class(es) it kills.
//
// CONVENTION PIN (intake Stage 3): any NEW gitignored runtime sidecar MUST use
// these primitives instead of re-deriving load/write/stale/claim/GC by hand. A
// bespoke re-implementation is a code-review BLOCKING finding (surfaced in
// .aai/SKILL_CODE_REVIEW.prompt.md Verdict 2). Existing sidecars migrate
// opportunistically; do NOT big-bang rewrite code that is currently green.
//
// APPEND vs REWRITE. These primitives are for WHOLE-FILE state (read all / write
// all). Append-only ledgers (EVENTS.jsonl, LOOP_TICKS, friction observations) use
// a DIFFERENT atomicity model (O_APPEND under PIPE_BUF) and are DELIBERATELY not
// covered here — an appendLine primitive is deferred to Stage 4 so nobody
// force-fits append semantics onto rewrite semantics (intake Design (a)).

import fs from 'node:fs';
import path from 'node:path';

// A monotonic per-process counter keeps each temp/aside path unique even for
// rapid successive writes/claims from the same pid (mirrors update-check.mjs).
let seq = 0;

// Filesystems that disallow hard links make linkSync throw one of these; on such
// a host claimExclusive falls back to an O_EXCL open (mirrors update-check.mjs
// Finding A, VERBATIM set).
const HARDLINK_UNSUPPORTED = new Set(['EPERM', 'ENOSYS', 'EOPNOTSUPP', 'EMLINK']);

// --- loadOrDegrade — KILLS CLASS B (silent-empty on corrupt read) -------------
// Read + parse a whole-file sidecar, distinguishing three outcomes so a DAMAGED
// ledger is NEVER returned as an empty one (the exact class-B failure, e.g.
// hitl-channel's shipped corrupt-as-empty read):
//   { status: 'absent', data: <empty> } — file does not exist (ENOENT). A normal
//        empty ledger; `data` is the caller-supplied `empty` default (null).
//   { status: 'corrupt', data: null }   — present but unreadable / unparseable /
//        wrong-shape. The caller must degrade LOUDLY, never proceed as if empty.
//   { status: 'ok', data: <parsed> }    — present, parsed, and shape-valid.
// A present-but-unreadable file (EACCES/EISDIR/…) is treated as CORRUPT, not
// absent: an inaccessible ledger is not "nothing parked" and must degrade loud.
// Options: { parse = JSON.parse, isShape = null, empty = null }. `isShape(parsed)`
// (optional) rejects a structurally-wrong-but-parseable payload as corrupt.
export function loadOrDegrade(filePath, opts = {}) {
  const parse = opts.parse || JSON.parse;
  const isShape = opts.isShape || null;
  const empty = 'empty' in opts ? opts.empty : null;
  let raw;
  try {
    raw = fs.readFileSync(filePath, 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') return { status: 'absent', data: empty };
    // present-but-unreadable -> damaged, NOT empty (class B).
    return { status: 'corrupt', data: null, code: e && e.code };
  }
  let parsed;
  try {
    parsed = parse(raw);
  } catch {
    return { status: 'corrupt', data: null }; // unparseable -> damaged
  }
  if (isShape && !isShape(parsed)) return { status: 'corrupt', data: null }; // wrong shape
  return { status: 'ok', data: parsed };
}

// --- atomicWrite — KILLS CLASS E (non-atomic / torn write) --------------------
// Write `contents` so a reader (or a crash) never observes a torn/partial file:
// mkdir -p the parent, write a per-pid.seq temp, then renameSync into place. The
// rename is the SOLE commit point (POSIX atomic on the same filesystem), so a
// crash between write and rename leaves the target either its PRIOR content or
// absent — never half-written; and two concurrent writers each land a WHOLE file
// (last rename wins; no interleaved bytes). This is the lib/state-engine.mjs
// discipline (SPEC-0012 D3), generalized so no sidecar ships a plain writeFileSync
// again (it is exactly the latent gap in hitl-channel's saveSidecar this closes).
export function atomicWrite(filePath, contents) {
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
  const tmp = `${filePath}.tmp.${process.pid}.${seq++}`;
  fs.writeFileSync(tmp, contents);
  try {
    fs.renameSync(tmp, filePath); // atomic on same-filesystem POSIX
  } catch (e) {
    try { fs.rmSync(tmp, { force: true }); } catch { /* best-effort temp cleanup */ }
    throw e;
  }
}

// --- claimExclusive — KILLS CLASS A (cross-process TOCTOU on a cold claim) -----
// A true single-winner exclusive claim on `filePath`, mirroring update-check.mjs
// claimLockFile VERBATIM where proven: write a per-pid.seq temp carrying the FULL
// body first, then hard-link it into place. linkSync is O_EXCL-equivalent (EEXIST
// if the target exists) AND the target has full content the instant it appears —
// no created-but-empty torn window. Returns a status object instead of throwing:
//   { status: 'claimed' } — THIS caller created the file (spawn / proceed).
//   { status: 'held' }    — another caller already holds it (back off).
//   { status: 'error', code } — a GENUINE failure (e.g. EACCES). LOUD, never
//        masqueraded as 'held' (Finding A: a silent no-op makes the feature
//        quietly never run on such a host).
// PORTABILITY: on a hard-link-hostile filesystem (linkSync throws
// EPERM/ENOSYS/EOPNOTSUPP/EMLINK) it FALLS BACK to fs.openSync(filePath, 'wx')
// (O_CREAT|O_EXCL) — still exclusive. Set env AAI_RUNTIME_FILE_NO_HARDLINK=1 to
// force that fallback path deterministically in tests (mirrors state-engine's
// AAI_STATE_INJECT_* test-only convention). Cold-start races only: reclaiming a
// STALE claim (see isStale) is the owning script's policy, not this primitive's.
export function claimExclusive(filePath, body) {
  try {
    fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
  } catch { /* best-effort: an unwritable parent surfaces below as a genuine error */ }
  const noHardlink = process.env.AAI_RUNTIME_FILE_NO_HARDLINK === '1';
  const tmp = `${filePath}.tmp.${process.pid}.${seq++}`;
  try {
    fs.writeFileSync(tmp, body);
  } catch (e) {
    return { status: 'error', code: e && e.code }; // cannot even stage -> loud error
  }
  try {
    if (noHardlink) throw Object.assign(new Error('hardlink disabled (test)'), { code: 'ENOSYS' });
    fs.linkSync(tmp, filePath);           // exclusive create; EEXIST if held
    return { status: 'claimed' };
  } catch (e) {
    if (e.code === 'EEXIST') return { status: 'held' };               // target already held
    if (!HARDLINK_UNSUPPORTED.has(e.code)) return { status: 'error', code: e.code }; // genuine
    // Hard links unsupported here: fall back to an O_EXCL open+write.
    try {
      const fd = fs.openSync(filePath, 'wx');   // EEXIST if held; else genuine
      try { fs.writeSync(fd, body); } finally { fs.closeSync(fd); }
      return { status: 'claimed' };
    } catch (e2) {
      if (e2.code === 'EEXIST') return { status: 'held' };
      return { status: 'error', code: e2.code };
    }
  } finally {
    try { fs.rmSync(tmp, { force: true }); } catch { /* best-effort temp cleanup */ }
  }
}

// --- isStale — KILLS CLASSES C + F (clock-skew wedge; re-implemented staleness)-
// The ONE shared staleness verdict, with an INJECTABLE clock (nowMs) so it is
// deterministic and never wall-clock dependent. The window is SYMMETRIC —
// stale iff |now - ts| > window — for the update-check.mjs reason: a FAR-future /
// NaN / corrupt timestamp (e.g. started_utc in 2099) is stale and IS reclaimable,
// so a future-dated value NEVER wedges (class C); but a value a live racer wrote
// microseconds ago can read as slightly "future" against this process's own clock
// snapshot and, being WITHIN the window, is correctly NOT stale (that is the
// live-racer protection — reclaiming it would be a duplicate-spawn race). `ts` is
// milliseconds since epoch (a parsed timestamp OR a file mtimeMs). NaN -> stale.
export function isStale(ts, nowMs, windowMs) {
  if (typeof ts !== 'number' || Number.isNaN(ts)) return true; // unparseable -> stale
  return Math.abs(nowMs - ts) > windowMs;
}

// --- reapAsides — KILLS CLASS D (no GC of aside / orphan files) ----------------
// Bounded GC of orphan/aside files: remove every entry in `dir` whose name starts
// with `prefix` and whose mtime is stale (isStale over the same symmetric window),
// keeping any FRESH one (a live producer mid-flight is never swept — that would be
// the double-surface / stolen-lock bug this guards). A missing directory is a
// no-op, NEVER a throw. This generalizes update-check's .surfacing/.reclaim/
// sentinel sweeps. Returns { reaped, kept } for a loud, auditable outcome.
export function reapAsides(dir, prefix, nowMs, windowMs) {
  let names;
  try {
    names = fs.readdirSync(dir);
  } catch {
    return { reaped: 0, kept: 0 }; // missing dir -> no-op, never throws
  }
  let reaped = 0;
  let kept = 0;
  for (const name of names) {
    if (!name.startsWith(prefix)) continue;
    const p = path.join(dir, name);
    let m;
    try {
      m = fs.statSync(p).mtimeMs;
    } catch {
      continue; // vanished between readdir and stat -> skip
    }
    if (isStale(m, nowMs, windowMs)) {
      try { fs.rmSync(p, { force: true }); reaped += 1; } catch { /* best-effort */ }
    } else {
      kept += 1; // fresh -> a live producer may own it; never sweep
    }
  }
  return { reaped, kept };
}
