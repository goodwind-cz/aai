#!/usr/bin/env node
// orphan-sweep — kill orphaned runaway shell wrappers left behind by agent
// sessions (spec: CHANGE orphan-sweep-session-hook).
//
// THE INCIDENT THIS EXISTS FOR (2026-07-29 → 08-02): stress-test tool calls
// spawned detached CPU busy-loops with cleanup via a TRAILING `kill $LP`; the
// harness's 120s tool timeout killed the parent shell first, the cleanup never
// ran, launchd adopted the loops, and 37 processes burned ~15 cores for almost
// 4 days until the operator noticed. Prose ("remember to clean up") does not
// fire; this sweep is the deterministic backstop, wired into the session-start
// hook alongside update-check.
//
// SELECTION (every predicate must hold — deliberately conservative):
//   1. PPID == 1            — orphaned (adopted by launchd/init). Any process
//                             still parented to a live session/terminal/editor
//                             is NEVER a candidate.
//   2. args contain PATTERN — the agent-shell wrapper marker
//                             (default: shell-snapshots/snapshot-zsh-).
//   3. age >= --min-age-s   — default 7200s. Protects short-lived detached
//                             jobs a live session legitimately runs (nohup'd
//                             suites, detached update sync).
//   4. %CPU >= --min-cpu    — default 20. A leaked BUSY loop burns ~40%; a
//                             legit long-lived detached waiter idles near 0.
//                             No legitimate factory job burns >20% CPU for 2h+
//                             unattended.
// Victims are killed by PROCESS GROUP (SIGKILL to -PGID) so the busy-loop
// subshell children die with their wrappers. PGIDs <= 1, the sweep's own
// PGID, and any PGID containing a non-matching process are excluded.
//
// NEVER kill by bare `pkill -f <snapshot-id>`: a long-lived session's OWN
// tool calls carry the same snapshot string — that pkill is a self-kill
// (verified live before this script existed).
//
// Hook contract (mirrors update-check): best-effort, bounded by the hook's
// watchdog, exit 0 on every runtime outcome; the ONLY output on the happy
// path is a single summary line when something was actually killed (silent
// no-op otherwise). Exit 2 = usage error.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import process from 'node:process';

const DEFAULT_PATTERN = 'shell-snapshots/snapshot-zsh-';
const DEFAULT_MIN_AGE_S = 7200;
const DEFAULT_MIN_CPU = 20;
const MAX_GROUPS_PER_SWEEP = 32; // sanity cap — a leak is a handful of groups

function usage(msg) {
  process.stderr.write(`orphan-sweep: ${msg}\n`
    + 'Usage: orphan-sweep [--dry-run] [--json] [--pattern <s>] '
    + '[--min-age-s <n>] [--min-cpu <n>] [--ps-file <path>] [--self-pgid <n>]\n');
  process.exit(2);
}

// etime formats: ss is never emitted alone by ps; forms are mm:ss, hh:mm:ss,
// dd-hh:mm:ss. Unparseable -> null (treated as NOT old enough — fail-safe).
export function parseEtimeSeconds(s) {
  const m = String(s ?? '').trim().match(/^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$/);
  if (!m) return null;
  const [, dd, hh, mm, ss] = m;
  return (Number(dd || 0) * 86400) + (Number(hh || 0) * 3600)
    + (Number(mm) * 60) + Number(ss);
}

// Parse fixed-width-ish `ps axo pid,pgid,ppid,pcpu,etime,args` output.
// Returns [{pid,pgid,ppid,pcpu,etimeS,args}]. Malformed lines are skipped.
export function parsePsTable(text) {
  const rows = [];
  for (const line of String(text).split('\n')) {
    const m = line.match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)\s+(\S+)\s+(.*)$/);
    if (!m) continue;
    rows.push({
      pid: Number(m[1]), pgid: Number(m[2]), ppid: Number(m[3]),
      pcpu: Number(m[4]), etimeS: parseEtimeSeconds(m[5]), args: m[6],
    });
  }
  return rows;
}

// Pure selection: rows -> {groups: Map<pgid, rows[]>, victims: rows[]}.
// A PGID qualifies only if EVERY selected member matches the pattern —
// a group sharing its id with an unrelated process is left alone entirely.
export function selectVictimGroups(rows, opts) {
  const { pattern, minAgeS, minCpu, selfPgid } = opts;
  const candidates = rows.filter((r) =>
    r.ppid === 1
    && r.args.includes(pattern)
    && r.etimeS !== null && r.etimeS >= minAgeS
    && r.pcpu >= minCpu);
  const groups = new Map();
  for (const r of candidates) {
    if (r.pgid <= 1 || r.pgid === selfPgid) continue;
    if (!groups.has(r.pgid)) groups.set(r.pgid, []);
    groups.get(r.pgid).push(r);
  }
  // exclusion: any process IN the group (matching or not) that is younger
  // than the age floor or lacks the pattern in a way that suggests the pgid
  // is shared with live work -> drop the whole group.
  for (const [pgid, members] of [...groups]) {
    const all = rows.filter((r) => r.pgid === pgid);
    const foreign = all.some((r) => !r.args.includes(pattern) && r.ppid !== 1);
    if (foreign) groups.delete(pgid);
    else if (members.length === 0) groups.delete(pgid);
  }
  return groups;
}

function main() {
  const argv = process.argv.slice(2);
  const opts = {
    dryRun: false, json: false, pattern: DEFAULT_PATTERN,
    minAgeS: DEFAULT_MIN_AGE_S, minCpu: DEFAULT_MIN_CPU,
    psFile: null, selfPgid: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--dry-run') opts.dryRun = true;
    else if (a === '--json') opts.json = true;
    else if (a === '--pattern') opts.pattern = argv[++i] ?? usage('missing --pattern value');
    else if (a === '--min-age-s') opts.minAgeS = Number(argv[++i]);
    else if (a === '--min-cpu') opts.minCpu = Number(argv[++i]);
    else if (a === '--ps-file') opts.psFile = argv[++i] ?? usage('missing --ps-file value');
    else if (a === '--self-pgid') opts.selfPgid = Number(argv[++i]);
    else usage(`unknown flag: ${a}`);
  }
  if (!opts.pattern) usage('empty --pattern refused (would match everything)');
  if (!Number.isFinite(opts.minAgeS) || opts.minAgeS < 0) usage('bad --min-age-s');
  if (!Number.isFinite(opts.minCpu) || opts.minCpu < 0) usage('bad --min-cpu');

  let psText;
  if (opts.psFile) {
    try { psText = fs.readFileSync(opts.psFile, 'utf8'); }
    catch { usage(`unreadable --ps-file: ${opts.psFile}`); return; }
  } else {
    try {
      psText = execFileSync('ps', ['axo', 'pid,pgid,ppid,pcpu,etime,args'],
        { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
    } catch {
      // no ps / unsupported platform: silent no-op (hook contract)
      process.exit(0);
    }
  }

  let selfPgid = opts.selfPgid;
  if (selfPgid === null) {
    try { selfPgid = process.getpgrp(); } catch { selfPgid = process.pid; }
  }

  const rows = parsePsTable(psText);
  const groups = selectVictimGroups(rows, { ...opts, selfPgid });
  const capped = [...groups.entries()].slice(0, MAX_GROUPS_PER_SWEEP);

  const plan = capped.map(([pgid, members]) => ({
    pgid,
    pids: members.map((r) => r.pid),
    sample: members[0]?.args.slice(0, 120) ?? '',
  }));

  let killedGroups = 0;
  let killedPids = 0;
  const errors = [];
  if (!opts.dryRun) {
    for (const g of plan) {
      try {
        process.kill(-g.pgid, 'SIGKILL');
        killedGroups += 1;
        killedPids += g.pids.length;
      } catch (e) {
        errors.push(`pgid ${g.pgid}: ${e.code || e.message}`);
      }
    }
  }

  if (opts.json) {
    process.stdout.write(`${JSON.stringify({
      dry_run: opts.dryRun, pattern: opts.pattern, min_age_s: opts.minAgeS,
      min_cpu: opts.minCpu, self_pgid: selfPgid, plan, killed_groups: killedGroups,
      killed_pids_visible: killedPids, errors,
    })}\n`);
  } else if (opts.dryRun && plan.length > 0) {
    process.stdout.write(`orphan-sweep (dry-run): would kill ${plan.length} `
      + `group(s): ${plan.map((g) => `pgid ${g.pgid} (${g.pids.length} visible)`).join(', ')}\n`);
  } else if (killedGroups > 0) {
    process.stdout.write(`orphan-sweep: killed ${killedGroups} orphaned process `
      + `group(s) (${killedPids} visible process(es), pattern '${opts.pattern}', `
      + `age>=${opts.minAgeS}s, cpu>=${opts.minCpu}%)\n`);
  }
  // silent when nothing to do; runtime outcomes always exit 0
  process.exit(0);
}

const isMain = process.argv[1] && import.meta.url.endsWith(
  process.argv[1].split('/').pop());
if (isMain) main();
