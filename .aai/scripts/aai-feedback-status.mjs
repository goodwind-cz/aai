// aai-feedback-status.mjs — RFC-0012 friction feedback DISCOVERY surface.
//
// Tells a human operator, in plain terms, the state of the local friction
// feedback loop so the built machinery is actually reachable:
//   - how many friction observations are captured in the local spool,
//   - how many of those clear the triage signal floor as REVIEW CANDIDATES,
//     read from the last triage report (spec-friction-channel-sweep Spec-AC-11),
//   - whether that report is STALE — its own total_observations no longer
//     matches the live spool's line count, named with BOTH numbers, because a
//     surface that reports "N captured" without saying whether the report
//     behind "candidates" is current is a surface that can lie by omission
//     (measured: a 65-observation report sat behind an 824-observation spool
//     for 20 days while this surface kept advertising drafts built from it),
//   - how many prepared issue drafts await their `--confirm`,
//   - whether GitHub `gh` is present and authenticated (read-only check),
//   - the exact next command to run — which NAMES TRIAGE, never a publish
//     over stale drafts, whenever the report is absent or stale, even while
//     drafts exist (D9: the surface must state the backlog, not the inbox).
//
// Offline for the counts (pure filesystem reads of the untracked spool and the
// triage report — never a re-run of the triage engine itself, so "candidates"
// is read from the SAME scoring Spec-AC-01 defines, not a second one). The
// ONLY external call is a READ-ONLY `gh auth status` — it never mutates and
// degrades cleanly if gh is absent/unauthenticated. Wired into /aai-wrap-up as
// an end-of-session nudge (silent when there is nothing to surface).
//
// Usage:
//   node .aai/scripts/aai-feedback-status.mjs [--json]
//   node .aai/scripts/aai-feedback-status.mjs --help
//
// Node stdlib only.

import { readFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { countSpoolRows } from './lib/friction-spool.mjs';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, '..', '..');
const FRICTION_DIR = process.env.AAI_FRICTION_DIR || join(REPO_ROOT, 'docs', 'ai', 'friction');
const SPOOL = join(FRICTION_DIR, 'observations.jsonl');
const PENDING_DIR = join(FRICTION_DIR, 'pending-issues');
const TRIAGE_REPORT = join(FRICTION_DIR, 'triage-report.json');
const TRIAGE_CMD = 'node .aai/scripts/aai-feedback-triage.mjs   # review clusters, then prepare with aai-feedback-upsert.mjs';
const PUBLISH_CMD = 'review docs/ai/friction/pending-issues/, then: node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm';

const HELP = `aai-feedback-status — RFC-0012 friction feedback discovery.

Usage:
  node .aai/scripts/aai-feedback-status.mjs [--json]
  node .aai/scripts/aai-feedback-status.mjs --help

Reports the local feedback-loop state: observations captured, review candidates
and staleness read from the last triage report, drafts pending your --confirm,
and whether GitHub \`gh\` is authenticated — plus the next command (triage,
never a publish over stale drafts, whenever the report is absent or stale). The
counts are offline filesystem reads; the only external call is a read-only
\`gh auth status\`. No mutation, no issue writes.
`;

// countObservations() -> the SAME count the triage engine writes as
// `total_observations` (lib/friction-spool.mjs's shared readSpoolRows()
// predicate: a line parses as JSON and is a plain object) — NOT every
// non-blank line (PR #394 review F1). Before this shared predicate existed,
// this function counted raw non-blank lines while aai-feedback-triage.mjs
// counted only the parseable ones; one malformed line left behind by a
// crashed or concurrent writer then pinned `report_stale` (below) to true
// FOREVER, because the raw count could never again equal the report's
// parseable-row count, even immediately after a fresh triage run.
function countObservations() {
  return countSpoolRows(SPOOL);
}
function countDrafts() {
  try {
    return readdirSync(PENDING_DIR).filter((f) => f.endsWith('.md')).length;
  } catch { return 0; }
}
// isValidReportShape(report) -> true only when the parsed JSON is actually
// shaped like a triage-report.json (aai-feedback-triage.mjs's REPORT_SCHEMA):
// a plain object whose `total_observations` is a finite number and whose
// `clusters` is an array. A report that PARSES but is structurally wrong
// (e.g. `{"total_observations":0,"clusters":"corrupt"}`) must fail the same
// way an absent report does (PR #394 review F2) — otherwise it silently
// normalizes to zero observations/candidates and, next to an empty spool,
// reads as a healthy CURRENT report instead of an unusable, broken one.
function isValidReportShape(report) {
  return !!report && typeof report === 'object' && !Array.isArray(report)
    && Number.isFinite(report.total_observations)
    && Array.isArray(report.clusters);
}
// readTriageReport() -> { hasReport, reportObservations, candidates,
// reportStale } read from the last triage-report.json (never re-triaged
// here — see file header). A missing, unreadable, structurally-invalid (F2),
// or malformed report is treated as absent, which is itself a stale state
// (there is nothing current to trust) — distinct from a report that
// genuinely reports 0 observations, which is why `hasReport` is its own
// field.
function readTriageReport(spoolLines) {
  let report;
  try {
    report = JSON.parse(readFileSync(TRIAGE_REPORT, 'utf8'));
  } catch {
    return { hasReport: false, reportObservations: 0, candidates: 0, reportStale: true };
  }
  if (!isValidReportShape(report)) {
    return { hasReport: false, reportObservations: 0, candidates: 0, reportStale: true };
  }
  const reportObservations = report.total_observations;
  const candidates = report.clusters.filter((c) => c?.decision === 'review_candidate').length;
  const reportStale = reportObservations !== spoolLines;
  return { hasReport: true, reportObservations, candidates, reportStale };
}
// Read-only auth probe. Returns 'ready' | 'unauthenticated' | 'absent'. Never
// throws, never mutates — `gh auth status` performs no write. `timeout`
// bounds the wall clock (B4, spec-friction-channel-sweep validation round 1):
// this is the ONE network call in a chain the close ceremony's best-effort
// backlog step now spawns (surfaceFrictionBacklog -> this script -> gh), and
// before that chain existed close-work-item.mjs made zero network calls. A
// hung `gh` must degrade this probe, never hang the caller — killSignal
// SIGKILL because a stuck `gh` past its own timeout has already shown SIGTERM
// does not reliably reap it (same posture as golden-flow.mjs / update-doctor-
// report.mjs's own execFileSync timeouts).
function ghState() {
  const bin = process.env.AAI_GH_BIN || 'gh';
  try {
    execFileSync(bin, ['auth', 'status'], { stdio: ['ignore', 'ignore', 'ignore'], timeout: 5000, killSignal: 'SIGKILL' });
    return 'ready';
  } catch (e) {
    // execFileSync throws ENOENT (gh absent), a non-zero exit (unauthenticated),
    // or ETIMEDOUT (ours, when the timeout above fired) — all three degrade the
    // same way: this is a best-effort read-only probe, not a hard requirement.
    return e && e.code === 'ENOENT' ? 'absent' : 'unauthenticated';
  }
}

function parseArgs(argv) {
  const a = {};
  for (const t of argv) {
    if (t === '--help' || t === '-h') a.help = true;
    else if (t === '--json') a.json = true;
    else { process.stderr.write(`aai-feedback-status: unrecognized argument: ${t}\n`); process.exit(2); }
  }
  return a;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { process.stdout.write(HELP); process.exit(0); }

  const observations = countObservations();
  const drafts = countDrafts();
  const gh = ghState();
  const ghReady = gh === 'ready';
  const ghHint = gh === 'absent' ? 'install & run: gh auth login'
    : gh === 'unauthenticated' ? 'run: gh auth login'
    : 'ready';
  const { hasReport, reportObservations, candidates, reportStale } = readTriageReport(observations);

  // Next actionable command for the operator (Spec-AC-11 / D9): a stale or
  // absent report NAMES TRIAGE, never a publish over drafts built from it —
  // even while drafts exist. The override only fires when there is something
  // actionable at all (drafts or observations); an empty loop stays null.
  let next = null;
  if (drafts > 0) next = PUBLISH_CMD;
  else if (observations > 0) next = TRIAGE_CMD;
  if (reportStale && next !== null) next = TRIAGE_CMD;

  if (args.json) {
    process.stdout.write(JSON.stringify({
      observations,
      drafts,
      gh,
      gh_ready: ghReady,
      candidates,
      report_observations: reportObservations,
      report_stale: reportStale,
      next: next || '',
    }, null, 2) + '\n');
    process.exit(0);
  }

  // Silent when there is nothing to surface (shadow mode is quiet by design):
  // the human nudge writes NOTHING on an empty loop so /aai-wrap-up can include
  // its output verbatim only when non-silent. --json above always emits the
  // object (a programmatic caller wants the zeros); this silence is human-only.
  if (observations === 0 && drafts === 0) {
    process.exit(0);
  }
  const reportSegment = !hasReport
    ? 'report: none yet'
    : reportStale
      ? `report STALE (${reportObservations} of ${observations} triaged)`
      : null;
  const parts = [
    `${observations} observation(s) captured`,
    `${candidates} review candidate(s)`,
    `${drafts} draft(s) pending your --confirm`,
  ];
  if (reportSegment) parts.push(reportSegment);
  parts.push(`gh: ${ghHint}`);
  process.stdout.write(`friction feedback: ${parts.join(' · ')}\n`);
  if (next) process.stdout.write(`  next: ${next}\n`);
}

main();
