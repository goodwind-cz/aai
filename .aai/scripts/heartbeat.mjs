#!/usr/bin/env node
// heartbeat.mjs — role progress heartbeat (role-progress-heartbeat /
// docs/specs/SPEC-0164-spec-role-progress-heartbeat.md). Node stdlib only,
// zero deps.
//
// WHAT THIS IS FOR, stated honestly. During a long autonomous ride the only
// truthful answer to "stav?" was "still running, no more detail". The sharper
// motivation is narrower: on three occasions in one session the orchestrator
// announced a dispatch it had not actually made, and the only reason it
// surfaced was the operator asking. The value of this signal is that it does
// NOT come from the orchestrator's narration.
//   PROVES, machine-written: SOME process existed, ran in worktree <w> at pid
//     <p>, and wrote at time <t>. That POSITIVE half is the whole of what this
//     mechanism surfaces.
//   DOES NOT PROVE which process. `writer_pid` and `worktree` identify a
//     writer, not the DISPATCHED writer: nothing stops the orchestrator
//     writing a slot itself, so a PRESENT slot is corroboration, never proof
//     of a dispatch. Calling this signal un-narratable over-reads it.
//   `writer_pid` (dispatch-state-sweep D13/Spec-AC-15; the field was named
//     `pid` before this) is the pid of the SHORT-LIVED WRITER PROCESS, which
//     exits immediately once the write returns — it is NOT a liveness handle
//     for the ride. Probing it (is that pid still running?) answers a
//     question about a process that was never meant to still be running; the
//     one honest liveness question this file answers is `read
//     --max-age-seconds N` (D8), never a pid check.
//   PROVES NOTHING BY ITS ABSENCE, and that is BY CONSTRUCTION. A missing slot
//     is produced identically by an announced-but-never-made dispatch, by a
//     role that has not reached a round boundary yet, by a role running in a
//     separate CLONE, and by any role whose write hit a degrade — every degrade
//     exits 0 and writes nothing. Absence is the one observable this design
//     REFUSES to interpret: .aai/VALIDATION.prompt.md c3 states that an absent
//     heartbeat is silence and never a finding, and the no-threshold rule below
//     is the same refusal in another place. Reading absence as detection would
//     turn today's silence into a new failure mode, which is exactly what the
//     spec's residual R2 rules out.
//   DOES NOT PROVE: that `message` is accurate. The message is still the
//     role's self-report. The timestamp is the trustworthy field, not the prose.
//
// STORAGE — <git-common-dir>/aai/heartbeat/hb-<slot>.json, one file per slot.
// The `hb-` prefix is not decoration: it is what makes THIS feature's files
// identifiable in a directory it does not own. `--dir`/AAI_HEARTBEAT_DIR is a
// first-class override, so the directory is caller-named and may hold anything;
// the GC below sweeps by that prefix; `read` lists by it AND by a `.json`
// suffix, so the two sets are NOT the same (see the asymmetry note below).
//   THE BOUND IS THE PREFIX, NOT OWNERSHIP. A file named `hb-*` that this
//   script never wrote is, once its mtime falls outside the window, still
//   REAPED — and if it does not end in `.json` it is reaped WITHOUT ever
//   having been listable, because `read` filters on `hb-*.json` while the
//   sweep filters on `hb-*` alone. The visible set is therefore strictly
//   NARROWER than the deletable set. Found independently by code review and
//   by an external reviewer; filed as fu-heartbeat-read-narrower-than-gc
//   (P3). Deliberately NOT closed here by narrowing the sweep to `.json`:
//   that would strand the abandoned `.tmp.<pid>.<seq>` temps forever. The
//   fix widens `read`, which is a behaviour change and wants its own RED. Aiming --dir/AAI_HEARTBEAT_DIR at a
//   directory shared with something else therefore requires that `hb-` be left
//   free there. Shape-gating the reap on isSlotShape was considered and
//   rejected: it cannot cover the abandoned `.tmp.<pid>.<seq>` temps the sweep
//   exists to collect, and is more machinery than the risk warrants.
//   tests/skills/test-aai-heartbeat.sh TEST-011 pins BOTH halves — an
//   unprefixed foreign file survives, a prefixed one does not.
// The location is worktree-independent BY CONSTRUCTION: `git rev-parse
// --git-common-dir` prints `.git` from a main checkout's root, `../.git` from
// a subdirectory of it, and an ABSOLUTE path from a linked worktree (measured,
// git 2.50.1), and all three resolve to one place. A role writing inside its
// worktree and an observer reading from the main checkout therefore hit the
// same file — the exact defect that ruled docs/ai/STATE.yaml out.
//   THE TRAP: `path.join(root, out)` is right for the two RELATIVE spellings
//   and WRONG for the absolute one (it would glue the absolute path onto the
//   worktree root). `path.resolve(root, out)` is right for all three. That is
//   why every resolution below goes through path.resolve, and why
//   tests/skills/test-aai-heartbeat.sh TEST-002 crosses the seam with a real
//   `git worktree add` rather than a fixture stand-in.
//   It is also STRUCTURALLY UNCOMMITTABLE: nothing under .git/ can enter the
//   index, so this feature owes no entry in ANY of the three ignore/canon
//   lists under .aai/system/ or in .gitignore, and can never appear in a diff
//   or a ledger. (Those list names are spelled out in
//   tests/skills/test-aai-heartbeat.sh TEST-013 rather than here: naming the
//   runtime-ignore list inside an .aai script makes test-aai-sync-seed.sh
//   TEST-016 read this file as one of that list's CONSUMERS, which it is not.)
// AAI_HEARTBEAT_DIR (or --dir) overrides the directory absolutely — tests, and
// any host where the git probe cannot run. Precedent: AAI_LIVE_SPOOL_DIR.
//
// ONE FILE PER SLOT, DELIBERATELY. No cross-process read-modify-write exists
// anywhere here, so class-A TOCTOU (runtime-file.mjs's header) cannot occur
// even under parallel dispatch, where a shared-file design would silently lose
// one role's entry at every collision.
//
// TWO FAILURE GRADES, DELIBERATELY SEPARATED
//   USAGE (exit 2, loud). A caller that cannot identify itself is a WIRING bug
//     and must surface at implementation time, not degrade into silence:
//     a missing --ref/--role/--message, or any of them empty after sanitization.
//   RUNTIME DEGRADE (exit 0, named note on stderr). No git, no repo, unwritable
//     directory, failed sweep. The role's own outcome must NEVER move because
//     of a heartbeat, so every runtime condition exits 0 and writes nothing.
//     Absence degrades to today's silence, never to a new failure mode.
//   `read` is exit 0 in every case including a corrupt slot, WITH ONE NAMED
//   EXCEPTION below (`--max-age-seconds`): per Constitution article 4 a
//   damaged slot is NAMED in the output, never dropped silently and never
//   read as "nothing there" (runtime-file.mjs class B).
//
// WHAT IS DELIBERATELY ABSENT — there is no `clear`, no lease, and this file
// still computes NO STALE/STUCK VERDICT of its own. Plain `read` prints
// `age_seconds`, a fact; it defines no threshold, and the intake still defers
// stuck-detection.
//   dispatch-state-sweep D8 (Spec-AC-08) is a NARROW, NAMED exception, not a
//   reopening of that decision: `read --max-age-seconds <N>` lets the CALLER
//   supply its own threshold for exactly one honest question — "is at least
//   one slot fresher than N seconds" — exiting 0/4/3 (fresh / none-fresher /
//   probe-degraded). It exists because the alternative was worse: the
//   orchestrator inventing its OWN liveness probe (a GNU-only find mtime flag, rejected
//   by BSD find, stderr silenced, zero writes reported as a real answer —
//   the incident this closes). The file still never decides "stuck" on its
//   own; N is the caller's number, not this file's.
//   NO GATE MAY EVER READ THIS FILE FOR A DISPATCH/VALIDATION DECISION: an
//   advisory signal a gate learned to read became a blocker nobody intended
//   (SPEC-0163 / PR #334). `--max-age-seconds` answers a LIVENESS question
//   (is something running), never a CORRECTNESS one (should this pass) — the
//   line SPEC-0163 exists to hold. test-aai-heartbeat.sh TEST-012 makes the
//   correctness half a mechanical, failable check — deny-by-default over the
//   WHOLE .aai/scripts corpus with THIS FILE as the only allowlisted one, not
//   an enumerated list of gates whose forgotten member is the hole.
//
// POSITIONING: this lives BESIDE .aai/scripts/generate-live-status.mjs, not
// inside it. That generator observes the HARNESS from the outside and answers
// "what is running now and what did it cost"; this is written by the ROLE about
// its own ride semantics. `read --json` emits {slots, degraded} using that
// generator's own `degraded`-array convention, as a cheap future seam only.
//
// CLI
//   node heartbeat.mjs write --ref <R> --role <Role> --message <text>
//        [--slot <token>] [--dir <path>]
//   node heartbeat.mjs read [--json] [--ref <R>] [--dir <path>] [--max-age-seconds <N>]
//
// Exit codes: 0 for every write/read OUTCOME including degrades; 2 usage error.
//   `read --max-age-seconds <N>` (D8) is the one exception: 0 fresh, 4 no
//   slot fresher than N (including none at all), 3 the probe itself degraded
//   (directory unreadable, git dir not resolvable) — see the header note.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { atomicWrite, loadOrDegrade, reapAsides } from './lib/runtime-file.mjs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const MESSAGE_MAX = 200;
const COMPONENT_MAX = 64;
const GC_WINDOW_MS = 24 * 60 * 60 * 1000;
// How many prefixed non-slot entries a single read will NAME before summarising.
const STRAY_REPORT_MAX = 20;
// How long an atomicWrite temp may exist before it stops counting as in flight.
// A real create-to-rename window is milliseconds; a minute is generous enough
// that a loaded machine never trips it and short enough that an abandoned temp
// surfaces on the next read rather than in 24 hours.
const TEMP_INFLIGHT_MS = 60 * 1000;
// Every file this script writes starts with this. It is what bounds the GC
// sweep and the read listing to files this feature owns; see STORAGE above.
const SLOT_PREFIX = 'hb-';

// Resolved from THIS SCRIPT's own location, so the caller's cwd is irrelevant
// (the live-spool.sh discipline). In a linked worktree this is that worktree's
// root, which is exactly what the `worktree` payload field should record.
const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

function usage(msg) {
  process.stderr.write(`heartbeat: ${msg}\n`);
  exit(2);
}

function degrade(reason) {
  process.stderr.write(`heartbeat: degraded — ${reason}\n`);
  exit(0);
}

// Shallow --key value parser plus boolean --json. The first positional is the
// subcommand. An empty-string value is ACCEPTED here on purpose: it is a real
// caller mistake that must reach the empty-after-sanitization refusal with its
// own message, not be masked as "requires a value".
function parseArgs(argv) {
  const opts = { _: [], json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--json') { opts.json = true; continue; }
    if (tok === '-h' || tok === '--help') { opts._.push('--help'); continue; }
    if (tok.startsWith('--')) {
      const key = tok.slice(2);
      const val = argv[i + 1];
      if (val === undefined || val.startsWith('--')) usage(`--${key} requires a value`);
      opts[key] = val;
      i += 1;
      continue;
    }
    opts._.push(tok);
  }
  return opts;
}

// A slot-name component: filesystem- and shell-safe by construction, so no
// component can ever escape the heartbeat directory.
function sanitizeComponent(value) {
  return String(value).replace(/[^A-Za-z0-9._-]/g, '-').slice(0, COMPONENT_MAX);
}

// The message is DATA, never executed and never interpreted. C0/C1 whitespace
// becomes a space so a multi-line status collapses to one readable line;
// remaining control and bidi characters are dropped outright (a bidi override
// in a status line can reorder everything printed after it).
function sanitizeMessage(value) {
  return String(value)
    .replace(/[\t\n\r\v\f\u0085\u2028\u2029]/g, ' ')
    .replace(/[\u0000-\u001F\u007F-\u009F\u200E\u200F\u202A-\u202E\u2066-\u2069]/g, '')
    .replace(/ {2,}/g, ' ')
    .trim()
    .slice(0, MESSAGE_MAX);
}

// Returns { dir } or { reason } — never throws, because a role's outcome must
// not move because of a heartbeat.
function resolveDir(explicit) {
  if (explicit !== undefined) return { dir: path.resolve(explicit) };
  if (process.env.AAI_HEARTBEAT_DIR) return { dir: path.resolve(process.env.AAI_HEARTBEAT_DIR) };
  let common;
  try {
    common = execFileSync('git', ['-C', REPO_ROOT, 'rev-parse', '--git-common-dir'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch (e) {
    return { reason: `git unavailable or not a repository (${(e && e.code) || 'unknown'})` };
  }
  if (!common) return { reason: 'git returned no --git-common-dir' };
  // path.RESOLVE for the git output (it may be relative OR absolute — THE TRAP
  // in the header); path.join for the two literal subdirectories, which are
  // never absolute and so have no such split.
  return { dir: path.join(path.resolve(REPO_ROOT, common), 'aai', 'heartbeat') };
}

// The shape gate for loadOrDegrade: a parseable but structurally wrong payload
// is CORRUPT, not usable. Without this a truncated or hand-edited slot would be
// reported as a real heartbeat with undefined fields.
function isSlotShape(o) {
  return !!o
    && typeof o === 'object'
    && !Array.isArray(o)
    && typeof o.ref_id === 'string'
    && typeof o.role === 'string'
    && typeof o.message === 'string'
    && typeof o.updated_at === 'string'
    && !Number.isNaN(Date.parse(o.updated_at))
    && typeof o.writer_pid === 'number'
    && typeof o.worktree === 'string';
}

function cmdWrite(opts) {
  if (opts.ref === undefined) usage('--ref is required');
  if (opts.role === undefined) usage('--role is required');
  if (opts.message === undefined) usage('--message is required');

  const ref = sanitizeComponent(opts.ref);
  if (!ref) usage('--ref is empty after sanitization');
  const role = sanitizeComponent(opts.role);
  if (!role) usage('--role is empty after sanitization');
  let slotName = `${SLOT_PREFIX}${ref}__${role}`;
  if (opts.slot !== undefined) {
    const slot = sanitizeComponent(opts.slot);
    if (!slot) usage('--slot is empty after sanitization');
    slotName = `${slotName}__${slot}`;
  }
  const message = sanitizeMessage(opts.message);
  if (!message) usage('--message is empty after sanitization');

  const resolved = resolveDir(opts.dir);
  if (resolved.reason) degrade(resolved.reason);
  const dir = resolved.dir;

  // Class-D orphan GC before the write, so a failed sweep degrades without
  // leaving a half-tended directory behind. BOUNDED BY SLOT_PREFIX, which is
  // reapAsides' whole contract ("every entry whose name starts with prefix"):
  // an empty prefix here would make this an unbounded 24-hour GC over whatever
  // directory the caller named — deleting an operator's files with exit 0 and a
  // success line. The prefix still covers abandoned atomicWrite temps, which
  // are named `<slot-file>.tmp.<pid>.<seq>` and so inherit it. reapAsides keeps
  // every FRESH entry, so a live producer's slot is never taken.
  //   The bound is the prefix and NOTHING ELSE: a prefixed file this script
  //   never wrote is reaped too (see STORAGE above). And the window is
  //   SYMMETRIC, not "older than" — reapAsides delegates to isStale, which is
  //   stale iff |now - mtime| > window, so a FUTURE-dated prefixed file is
  //   stale as well. That is deliberate library semantics (runtime-file.mjs
  //   classes C+F: a far-future mtime must never wedge a GC), not an accident.
  const swept = reapAsides(dir, SLOT_PREFIX, Date.now(), GC_WINDOW_MS);
  if (swept.error) degrade(`orphan sweep failed (${swept.error})`);

  const file = path.join(dir, `${slotName}.json`);
  // dispatch-state-sweep D13 (Spec-AC-13): sanitizeComponent is NOT injective
  // — two different raw refs can collapse onto the same slot (different
  // separator characters both becoming '-', or a shared 64-char prefix past
  // COMPONENT_MAX). That collision used to be silent: the second write simply
  // won, and nothing said a first writer's progress was ever sharing a slot.
  // Read (best-effort — a read failure here must never block the write) the
  // EXISTING slot's raw ref before overwriting it; when it names a DIFFERENT
  // raw ref than this call's, name both raw refs and the shared slot on
  // stderr. The write still wins either way — the alternative is a live role
  // with nowhere to report — this only stops the collision being invisible.
  const rawRef = String(opts.ref);
  try {
    const existing = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (existing && typeof existing.ref_id_raw === 'string' && existing.ref_id_raw !== rawRef) {
      process.stderr.write(
        `heartbeat: slot collision — "${existing.ref_id_raw}" and "${rawRef}" both sanitize to `
        + `${slotName}; the newer write wins\n`,
      );
    }
  } catch {
    // absent, corrupt, or unreadable — no prior writer to name a collision
    // against; proceed exactly as a fresh slot would.
  }

  // The SANITIZED components, not the raw ones, for ref_id/role/message. Two
  // reasons: the payload is printed straight to an operator's terminal, so
  // leaving control or bidi bytes in ref_id/role would defeat the message
  // sanitization beside it; and it keeps `ref_id` consistent with the `slot`
  // filename built from the same value, so a reader can map one to the other.
  // `ref_id_raw` (D13) is the one field that deliberately keeps the caller's
  // UNSANITIZED --ref, so a later write can detect the collision above.
  const payload = {
    ref_id: ref,
    ref_id_raw: rawRef,
    role,
    message,
    updated_at: new Date().toISOString(),
    // D13/Spec-AC-15: the SHORT-LIVED WRITER's pid, not a liveness handle —
    // see the header note. `pid` (unqualified) is a prior name this field
    // must never carry again (a hand-written or legacy slot with only `pid`
    // is CORRUPT, not accepted — isSlotShape above requires writer_pid).
    writer_pid: process.pid,
    worktree: REPO_ROOT,
  };
  try {
    atomicWrite(file, `${JSON.stringify(payload, null, 2)}\n`);
  } catch (e) {
    degrade(`cannot write ${file} (${(e && e.code) || 'unknown'})`);
  }
  process.stdout.write(`heartbeat: ${slotName} updated\n`);
  exit(0);
}

function cmdRead(opts) {
  const resolved = resolveDir(opts.dir);
  // Hoisted above the readdir: the stray scan dates atomicWrite temps with it.
  const now = Date.now();
  const slots = [];
  // `degraded` is the JSON contract and carries EVERY degrade, the failed probe
  // included. `slotDegraded` is the subset that says something about the data
  // itself; only those are printed on stdout, because a probe that could not
  // run is not a damaged slot.
  const degraded = [];
  const slotDegraded = [];
  let names = [];
  // D8/Spec-AC-08: distinguishes "the probe itself could not run" (exit 3,
  // below) from "it ran and found nothing/nothing fresh" (exit 4). Only a
  // git-probe failure or an unreadable directory sets this — a cold-start
  // ENOENT and a corrupt/stray slot are both legitimate "ran fine, nothing
  // here" answers, never a probe failure.
  let probeDegradeReason = null;

  if (resolved.reason) {
    // Report the degrade on stderr (article 4: degrade AND report) while stdout
    // stays on the cold-start literal — an observer asking "is anything
    // running" gets a clean answer, never an error, and never a slot count that
    // implies the directory was actually read.
    degraded.push({ source: 'git', reason: resolved.reason });
    process.stderr.write(`heartbeat: degraded — ${resolved.reason}\n`);
    probeDegradeReason = resolved.reason;
  } else {
    // dispatch-state-sweep D13 (Spec-AC-14): the same GC the write path runs,
    // now ALSO on read, so a quiet repository (no write ever running the
    // sweep) still reaps. Best-effort — a read must never fail because a
    // sweep could not run; the subsequent readdir below still degrades
    // normally if the directory itself is unreadable.
    reapAsides(resolved.dir, SLOT_PREFIX, now, GC_WINDOW_MS);
    try {
      // The GC beside this is free to delete anything matching the prefix, so a
      // prefixed entry this read silently ignored was a file one seam could
      // remove and the other could not see (fu-heartbeat-read-narrower-than-gc).
      //
      // TWO EXCLUSIONS, both found by review:
      //   - `<slot>.tmp.<pid>.<seq>` is atomicWrite's own in-flight temp. The
      //     live page reads every five seconds while roles write heartbeats, so
      //     a read landing inside a write window would light the Degraded panel
      //     for a perfectly healthy write.
      //   - the list is CAPPED. 3000 stray files produced 3000 entries and a
      //     452 KB /data.json on every five-second poll; past the cap the count
      //     is stated instead.
      const all = fs.readdirSync(resolved.dir).sort();
      names = all.filter((n) => n.startsWith(SLOT_PREFIX) && n.endsWith('.json'));
      // An atomicWrite temp is excluded only while it is plausibly IN FLIGHT.
      // A blanket exclusion hid the abandoned ones — a writer killed between
      // create and rename leaves a temp that no read would ever mention, until
      // some later write's GC removed it, which is exactly the GC-owned input
      // this change exists to expose (bot review, PR #351). Fresh: skip.
      // Stale: name it, and say what it is.
      const isTemp = (n) => /\.tmp\.\d+\.\d+$/.test(n);
      const ageOf = (n) => { try { return now - fs.statSync(path.join(resolved.dir, n)).mtimeMs; } catch { return Infinity; } };
      const strays = all.filter((n) => n.startsWith(SLOT_PREFIX) && !n.endsWith('.json')
        && !(isTemp(n) && ageOf(n) < TEMP_INFLIGHT_MS));
      for (const n of strays.slice(0, STRAY_REPORT_MAX)) {
        const entry = { source: n, reason: isTemp(n)
          ? 'an abandoned atomicWrite temp — a writer died between create and rename; the GC will remove it, this read cannot interpret it'
          : 'carries the heartbeat prefix but is not a .json slot — the GC may delete it, this read cannot interpret it' };
        degraded.push(entry);
        slotDegraded.push(entry);
      }
      if (strays.length > STRAY_REPORT_MAX) {
        const entry = { source: resolved.dir, reason: `and ${strays.length - STRAY_REPORT_MAX} more prefixed non-slot entr${strays.length - STRAY_REPORT_MAX === 1 ? 'y' : 'ies'} not listed` };
        degraded.push(entry);
        slotDegraded.push(entry);
      }
    } catch (e) {
      if (!e || e.code !== 'ENOENT') {
        const reason = `directory unreadable (${(e && e.code) || 'unknown'})`;
        const entry = { source: resolved.dir, reason };
        degraded.push(entry);
        slotDegraded.push(entry);
        probeDegradeReason = reason;
      }
    }
  }

  for (const name of names) {
    const res = loadOrDegrade(path.join(resolved.dir, name), { isShape: isSlotShape });
    if (res.status !== 'ok') {
      // Class B: a damaged slot is NAMED, never silently dropped and never
      // counted as "nothing there".
      const entry = { source: name, reason: 'unreadable or not a valid heartbeat payload' };
      degraded.push(entry);
      slotDegraded.push(entry);
      continue;
    }
    const d = res.data;
    // Sanitize the filter the same way the writer sanitized what it stored, so
    // `read --ref X` finds the slot `write --ref X` created for every X.
    if (opts.ref !== undefined && d.ref_id !== sanitizeComponent(opts.ref)) continue;
    slots.push({
      slot: name,
      ref_id: d.ref_id,
      role: d.role,
      message: d.message,
      updated_at: d.updated_at,
      // A FACT, not a verdict. No threshold is defined anywhere here.
      age_seconds: Math.round((now - Date.parse(d.updated_at)) / 1000),
      writer_pid: d.writer_pid,
      worktree: d.worktree,
    });
  }

  // dispatch-state-sweep D8 (Spec-AC-08): --max-age-seconds turns this read
  // into a liveness PROBE with three, and only three, exit codes — the
  // incident this closes was a probe that failed closed to a NUMBER
  // indistinguishable from a measurement (a GNU-only find mtime flag rejected by BSD
  // find, stderr silenced, zero writes reported as a real answer). Computed
  // once, applied to every output branch below (json / cold-start / lines),
  // so the exit code is the same regardless of --json.
  let readExitCode = 0;
  if (opts['max-age-seconds'] !== undefined) {
    const maxAge = Number(opts['max-age-seconds']);
    if (!Number.isFinite(maxAge) || maxAge < 0) usage('--max-age-seconds must be a non-negative number');
    if (probeDegradeReason !== null) {
      readExitCode = 3;
      process.stderr.write(`heartbeat: liveness probe degraded — ${probeDegradeReason}\n`);
    } else if (slots.some((s) => s.age_seconds < maxAge)) {
      readExitCode = 0;
      process.stderr.write(`heartbeat: liveness — at least one slot is fresher than ${maxAge}s\n`);
    } else {
      readExitCode = 4;
      process.stderr.write(`heartbeat: liveness — no slot is fresher than ${maxAge}s\n`);
    }
  }

  if (opts.json) {
    process.stdout.write(`${JSON.stringify({ slots, degraded })}\n`);
    exit(readExitCode);
  }

  if (slots.length === 0 && slotDegraded.length === 0) {
    process.stdout.write('heartbeat: none recorded\n');
    exit(readExitCode);
  }

  const lines = [`heartbeat: ${slots.length} slot(s)`];
  for (const s of slots) {
    lines.push(`  ${s.ref_id} / ${s.role}`);
    lines.push(`    message:    ${s.message}`);
    lines.push(`    updated_at: ${s.updated_at} (age_seconds ${s.age_seconds})`);
    lines.push(`    writer_pid: ${s.writer_pid}`);
    lines.push(`    worktree:   ${s.worktree}`);
  }
  for (const d of slotDegraded) {
    lines.push(`heartbeat: degraded — ${d.source}: ${d.reason}`);
  }
  process.stdout.write(`${lines.join('\n')}\n`);
  exit(readExitCode);
}

function main(argv) {
  const opts = parseArgs(argv);
  // The same empty-after-a-value refusal --ref/--role/--message carry, extended
  // to --dir, and checked here so every subcommand inherits it. path.resolve('')
  // is the CURRENT DIRECTORY, so an accepted empty --dir silently aims the write
  // — and the GC beside it — at wherever the caller happens to stand, which from
  // the repo root is the shipping tree. USAGE grade, not a degrade: a caller
  // that passed an unset shell variable has a wiring bug and must be told.
  if (opts.dir !== undefined && opts.dir === '') usage('--dir is empty');
  const sub = opts._[0];
  if (sub === '--help' || !sub) {
    process.stdout.write(
      'Usage: node heartbeat.mjs write --ref <R> --role <Role> --message <text> [--slot <t>] [--dir <path>]\n'
      + '       node heartbeat.mjs read [--json] [--ref <R>] [--dir <path>] [--max-age-seconds <N>]\n',
    );
    exit(sub ? 0 : 2);
  }
  if (sub === 'write') return cmdWrite(opts);
  if (sub === 'read') return cmdRead(opts);
  return usage(`unknown subcommand "${sub}" (expected write | read)`);
}

// No `import.meta.url === process.argv[1]` main-guard on purpose: that shape is
// the open follow-up fu-ismain-symlink-realpath (it compares two unresolved
// spellings and silently does nothing under a symlinked checkout). This file is
// a CLI with no importers, so runMain runs unconditionally and the defect has
// nowhere to live.
runMain(() => main(process.argv.slice(2)));
