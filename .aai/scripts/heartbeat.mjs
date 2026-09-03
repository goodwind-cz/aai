#!/usr/bin/env node
// heartbeat.mjs — role progress heartbeat (role-progress-heartbeat /
// docs/specs/SPEC-DRAFT-spec-role-progress-heartbeat.md). Node stdlib only,
// zero deps.
//
// WHAT THIS IS FOR, stated honestly. During a long autonomous ride the only
// truthful answer to "stav?" was "still running, no more detail". The sharper
// motivation is narrower: on three occasions in one session the orchestrator
// announced a dispatch it had not actually made, and the only reason it
// surfaced was the operator asking. The value of this signal is that it does
// NOT come from the orchestrator's narration.
//   PROVES, machine-written and un-narratable: a process existed, ran in
//     worktree <w> at pid <p>, and wrote at time <t>. An announced dispatch
//     that never happened leaves NO slot file at all — that absence is the
//     real detection.
//   DOES NOT PROVE: that `message` is accurate. The message is still the
//     role's self-report. The timestamp is the trustworthy field, not the prose.
//
// STORAGE — <git-common-dir>/aai/heartbeat/<slot>.json, one file per slot.
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
//   `read` is exit 0 in every case including a corrupt slot: per Constitution
//   article 4 a damaged slot is NAMED in the output, never dropped silently and
//   never read as "nothing there" (runtime-file.mjs class B).
//
// WHAT IS DELIBERATELY ABSENT — there is no `clear`, no lease, and NO
// STALE/STUCK VERDICT. `read` prints `age_seconds`, a fact; it defines no
// threshold. The intake explicitly defers stuck-detection, and inventing a
// threshold here would be the first step toward something a gate could learn to
// read. Which is also why NO GATE MAY EVER READ THIS FILE: an advisory signal a
// gate learned to read became a blocker nobody intended (SPEC-0163 / PR #334).
// test-aai-heartbeat.sh TEST-012 makes that a mechanical, failable check over
// the named gate scripts rather than a promise in this comment.
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
//   node heartbeat.mjs read [--json] [--ref <R>] [--dir <path>]
//
// Exit codes: 0 for every write/read OUTCOME including degrades; 2 usage error.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { atomicWrite, loadOrDegrade, reapAsides } from './lib/runtime-file.mjs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const MESSAGE_MAX = 200;
const COMPONENT_MAX = 64;
const GC_WINDOW_MS = 24 * 60 * 60 * 1000;

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
    && typeof o.pid === 'number'
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
  let slotName = `${ref}__${role}`;
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
  // leaving a half-tended directory behind. An empty prefix sweeps every entry
  // (slot files and any abandoned atomicWrite temp alike); reapAsides keeps
  // every FRESH one, so a live producer's slot is never taken.
  const swept = reapAsides(dir, '', Date.now(), GC_WINDOW_MS);
  if (swept.error) degrade(`orphan sweep failed (${swept.error})`);

  // The SANITIZED components, not the raw ones. Two reasons: the payload is
  // printed straight to an operator's terminal, so leaving control or bidi
  // bytes in ref_id/role would defeat the message sanitization beside it; and
  // it keeps `ref_id` consistent with the `slot` filename built from the same
  // value, so a reader can map one to the other.
  const payload = {
    ref_id: ref,
    role,
    message,
    updated_at: new Date().toISOString(),
    pid: process.pid,
    worktree: REPO_ROOT,
  };
  const file = path.join(dir, `${slotName}.json`);
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
  const slots = [];
  // `degraded` is the JSON contract and carries EVERY degrade, the failed probe
  // included. `slotDegraded` is the subset that says something about the data
  // itself; only those are printed on stdout, because a probe that could not
  // run is not a damaged slot.
  const degraded = [];
  const slotDegraded = [];
  let names = [];

  if (resolved.reason) {
    // Report the degrade on stderr (article 4: degrade AND report) while stdout
    // stays on the cold-start literal — an observer asking "is anything
    // running" gets a clean answer, never an error, and never a slot count that
    // implies the directory was actually read.
    degraded.push({ source: 'git', reason: resolved.reason });
    process.stderr.write(`heartbeat: degraded — ${resolved.reason}\n`);
  } else {
    try {
      names = fs.readdirSync(resolved.dir).filter((n) => n.endsWith('.json')).sort();
    } catch (e) {
      if (!e || e.code !== 'ENOENT') {
        const entry = { source: resolved.dir, reason: `directory unreadable (${(e && e.code) || 'unknown'})` };
        degraded.push(entry);
        slotDegraded.push(entry);
      }
    }
  }

  const now = Date.now();
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
      pid: d.pid,
      worktree: d.worktree,
    });
  }

  if (opts.json) {
    process.stdout.write(`${JSON.stringify({ slots, degraded })}\n`);
    exit(0);
  }

  if (slots.length === 0 && slotDegraded.length === 0) {
    process.stdout.write('heartbeat: none recorded\n');
    exit(0);
  }

  const lines = [`heartbeat: ${slots.length} slot(s)`];
  for (const s of slots) {
    lines.push(`  ${s.ref_id} / ${s.role}`);
    lines.push(`    message:    ${s.message}`);
    lines.push(`    updated_at: ${s.updated_at} (age_seconds ${s.age_seconds})`);
    lines.push(`    pid:        ${s.pid}`);
    lines.push(`    worktree:   ${s.worktree}`);
  }
  for (const d of slotDegraded) {
    lines.push(`heartbeat: degraded — ${d.source}: ${d.reason}`);
  }
  process.stdout.write(`${lines.join('\n')}\n`);
  exit(0);
}

function main(argv) {
  const opts = parseArgs(argv);
  const sub = opts._[0];
  if (sub === '--help' || !sub) {
    process.stdout.write(
      'Usage: node heartbeat.mjs write --ref <R> --role <Role> --message <text> [--slot <t>] [--dir <path>]\n'
      + '       node heartbeat.mjs read [--json] [--ref <R>] [--dir <path>]\n',
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
