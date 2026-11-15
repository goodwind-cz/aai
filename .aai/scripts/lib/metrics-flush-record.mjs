import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

// A worktree lifecycle event may share METRICS.jsonl with archived ride
// summaries. Older final summaries used a full UTC timestamp; current ones
// use a date. Both forms prove delivery when accompanied by summary fields.
const FLUSH_DATE_RE = /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|\+00:00))?$/;

export function metricsFlushDateToTs(date) {
  if (typeof date !== 'string' || !FLUSH_DATE_RE.test(date)) return '';
  const instant = date.length === 10 ? `${date}T23:59:59.999Z` : date;
  const millis = Date.parse(instant);
  return Number.isFinite(millis) ? new Date(millis).toISOString() : '';
}

export function isMetricsFlushRecord(record) {
  return record !== null && typeof record === 'object' && !Array.isArray(record)
    && typeof record.ref_id === 'string' && record.ref_id.length > 0
    && metricsFlushDateToTs(record.date_utc) !== ''
    && !Object.hasOwn(record, 'event')
    && (Object.hasOwn(record, 'title') || Array.isArray(record.agent_runs)
      || (record.totals !== null && typeof record.totals === 'object')
      || Object.hasOwn(record, 'verdict'));
}

// spec-flush-drops-reopened-runs Spec-AC-07: a reopened ride leaves SEVERAL
// summary lines for one ref in METRICS.jsonl (the first flush, then one
// continuation line per later flush marked `flush_segment: n`, or a
// reconstructed segment-2 line whose segment 1 lives elsewhere). Every reader
// that presents per-ride or per-ref data folds those lines into ONE ride
// through this single helper, so "one ledger line = one ride" is never
// assumed again.
//
// A "recovery line" (recover-archived-state-runs: metrics-flush
// --recover-archives) is a summary line whose `reconstructed` is a non-null
// object and whose verdict is not "PASS". It holds role runs that reached the
// ledger long after the ride ended and carries no verdict of its own, so no
// gate reads it as a PASS, a delivery or a flush (isRecoveryRecord). A
// reconstructed line with verdict PASS (SPEC-0291's incident segment) is a real
// ride segment and is NOT a recovery line.
//
// foldRideSegments(records) -> array in ledger order. Non-summary records
// (worktree lifecycle events, anything isMetricsFlushRecord refuses) pass
// through untouched. A ref with exactly one summary line is returned as the
// SAME object (byte-identical downstream output for every single-line ref).
// A ref with several lines is replaced, at the position of its BASE segment
// (the latest segment that is not a recovery line, else the last segment), by
// one merged record:
//   - agent_runs: concatenated in ledger order
//   - totals.agent_duration_seconds / total_cost_usd: summed (cost is null if
//     any segment's cost is null, like buildEntry's anyNullCost);
//     totals.cost_basis: the one shared basis, else 'mixed'
//   - human time (human_time_minutes.intake/reviews and totals.human_time_minutes):
//     the MAX across segments, never the sum — a continuation line can repeat
//     the ride's human time (follow-up fu-continuation-rerecords-human-time)
//   - reliability: validation_fails / review_fails / remediation_runs summed,
//     first_pass_clean false if any segment false, else true only when every
//     segment says true, else null; basis the shared value else 'mixed';
//     verdict_after_last_implementer from the base segment
//   - date_utc: the latest; title: the first non-empty one
//   - verdict, verdict_basis, strategy and every other field: the base
//     segment's (validation_waiver: the latest non-recovery segment that
//     carries one). With no recovery line the base is the last segment, so
//     every pre-recovery output is unchanged
//   - flush_segment: the highest; flush_lines: how many lines were folded
export function isRecoveryRecord(record) {
  return isMetricsFlushRecord(record)
    && record.reconstructed !== null && typeof record.reconstructed === 'object' && !Array.isArray(record.reconstructed)
    && record.verdict !== 'PASS';
}

// The segment a folded ride takes its verdict, position and non-summed fields
// from: the latest that is not a recovery line, else the last (an all-recovery
// ride keeps its own, null, verdict).
function baseSegment(segs) {
  for (let i = segs.length - 1; i >= 0; i--) if (!isRecoveryRecord(segs[i])) return segs[i];
  return segs[segs.length - 1];
}

const num = (v) => typeof v === 'number' && Number.isFinite(v);
const maxOrNull = (vals) => { const n = vals.filter(num); return n.length ? Math.max(...n) : null; };

function mergeSegments(segs) {
  const base = baseSegment(segs);
  const merged = { ...base };
  let latestDate = base.date_utc;
  for (const s of segs) {
    if (metricsFlushDateToTs(s.date_utc) >= metricsFlushDateToTs(latestDate)) latestDate = s.date_utc;
  }
  merged.date_utc = latestDate;
  const title = segs.map((s) => s.title).find((t) => typeof t === 'string' && t !== '');
  if (title !== undefined) merged.title = title;
  if (segs.some((s) => s.human_time_minutes && typeof s.human_time_minutes === 'object')) {
    const h = segs.map((s) => (s.human_time_minutes && typeof s.human_time_minutes === 'object' ? s.human_time_minutes : {}));
    merged.human_time_minutes = { intake: maxOrNull(h.map((x) => x.intake)), reviews: maxOrNull(h.map((x) => x.reviews)) };
  }
  const runsOf = (s) => (Array.isArray(s.agent_runs) ? s.agent_runs : []);
  if (segs.some((s) => Array.isArray(s.agent_runs))) merged.agent_runs = segs.flatMap(runsOf);
  if (segs.some((s) => s.totals && typeof s.totals === 'object')) {
    const t = segs.map((s) => (s.totals && typeof s.totals === 'object' ? s.totals : {}));
    const secs = segs.map((s, i) => (num(t[i].agent_duration_seconds) ? t[i].agent_duration_seconds
      : runsOf(s).reduce((a, r) => a + (num(r.duration_seconds) ? r.duration_seconds : 0), 0)));
    const bases = new Set(t.map((x) => x.cost_basis).filter((b) => typeof b === 'string'));
    merged.totals = {
      ...(base.totals && typeof base.totals === 'object' ? base.totals : {}),
      human_time_minutes: maxOrNull(t.map((x) => x.human_time_minutes)) ?? 0,
      agent_duration_seconds: secs.reduce((a, v) => a + v, 0),
      total_cost_usd: t.every((x) => num(x.total_cost_usd)) ? t.reduce((a, x) => a + x.total_cost_usd, 0) : null,
    };
    if (bases.size > 0) merged.totals.cost_basis = bases.size === 1 ? [...bases][0] : 'mixed';
  }
  const rels = segs.map((s) => (s.reliability && typeof s.reliability === 'object' && !Array.isArray(s.reliability) ? s.reliability : null));
  if (rels.some((r) => r !== null)) {
    const present = rels.filter((r) => r !== null);
    const sum = (k) => (present.some((r) => num(r[k])) ? present.reduce((a, r) => a + (num(r[k]) ? r[k] : 0), 0) : undefined);
    const flags = present.map((r) => r.first_pass_clean);
    const bases = new Set(present.map((r) => r.basis).filter((b) => typeof b === 'string'));
    const rel = { ...(rels[segs.indexOf(base)] ?? present[present.length - 1]) };
    for (const k of ['validation_fails', 'review_fails', 'remediation_runs']) { const v = sum(k); if (v !== undefined) rel[k] = v; }
    if (flags.some((f) => typeof f === 'boolean')) {
      rel.first_pass_clean = flags.some((f) => f === false) ? false : (flags.every((f) => f === true) ? true : null);
    }
    if (bases.size > 0) rel.basis = bases.size === 1 ? [...bases][0] : 'mixed';
    merged.reliability = rel;
  }
  const waiver = [...segs].reverse().find((s) => !isRecoveryRecord(s) && s.validation_waiver !== undefined && s.validation_waiver !== null);
  if (waiver !== undefined) merged.validation_waiver = waiver.validation_waiver;
  const segNums = segs.map((s) => (Number.isInteger(s.flush_segment) && s.flush_segment >= 1 ? s.flush_segment : 1));
  merged.flush_segment = Math.max(...segNums);
  merged.flush_lines = segs.length;
  return merged;
}

export function foldRideSegments(records) {
  const byRef = new Map();
  for (const r of records) {
    if (!isMetricsFlushRecord(r)) continue;
    if (!byRef.has(r.ref_id)) byRef.set(r.ref_id, []);
    byRef.get(r.ref_id).push(r);
  }
  const out = [];
  for (const r of records) {
    if (!isMetricsFlushRecord(r)) { out.push(r); continue; }
    const segs = byRef.get(r.ref_id);
    if (segs.length === 1) { out.push(r); continue; }
    if (baseSegment(segs) === r) out.push(mergeSegments(segs));
  }
  return out;
}

// archive-ledger-check D2/D3: the role runs of `copy`, a STATE copy of the ride checkout
// `root` whose ride has ended, checked against root's docs/ai/METRICS.jsonl by the ONE
// recovery path (metrics-flush --recover-archives --include-focus in `scriptDir`, run as a
// child, cwd root): a dry run counts the runs the ledger lacks; when `writable` (and the
// ledger file exists) and not `dryRun`, the real run appends them. Returns
// { would, refs, recovered, keep }: keep is null when nothing is left behind, else what is
// missing or failed plus the command a person runs from the main checkout (`rel` is the
// archived copy's path there). With `origin` (the main checkout) its working ledger and,
// with `base`, the ledger at refs/remotes/origin/<base> (where the base sync lands, written
// to a temporary file) are passed as --held-in, so a run any of them holds is never written.
export function recoverStateCopy({ scriptDir, root, copy, rel, writable, dryRun = false, origin = null, base = null }) {
  const metrics = path.join(root, 'docs', 'ai', 'METRICS.jsonl');
  const held = [];
  let tmp = null;
  if (origin) {
    held.push(path.join(origin, 'docs', 'ai', 'METRICS.jsonl'));
    const blob = base ? spawnSync('git', ['-C', origin, 'show', `refs/remotes/origin/${base}:docs/ai/METRICS.jsonl`], { encoding: 'utf8', maxBuffer: 1 << 30 }) : null;
    tmp = path.join(os.tmpdir(), `aai-held-ledger-${process.pid}-${Date.now()}.jsonl`);
    if (blob && blob.status === 0 && blob.stdout) { fs.writeFileSync(tmp, blob.stdout); held.push(tmp); }
  }
  try {
    return recoverWith({ scriptDir, root, copy, rel, writable, dryRun, metrics, held });
  } finally {
    if (tmp) fs.rmSync(tmp, { force: true });
  }
}

function recoverWith({ scriptDir, root, copy, rel, writable, dryRun, metrics, held }) {
  const fallback = `node .aai/scripts/metrics-flush.mjs --recover-archives --include-focus --state ${rel} --archive ${rel}`;
  const args = [path.join(scriptDir, 'metrics-flush.mjs'), '--recover-archives', '--include-focus', '--archive', copy,
    '--state', path.join(root, 'docs', 'ai', 'STATE.yaml'), '--metrics', metrics, '--pricing', path.join(scriptDir, '..', 'system', 'PRICING.yaml'), ...held.flatMap((f) => ['--held-in', f])];
  const cwd = root;
  writable = writable && fs.existsSync(metrics);
  const run = (extra) => spawnSync(process.execPath, [...args, ...extra], { cwd, encoding: 'utf8' });
  const why = (r) => (r.error?.message ?? `${r.stderr ?? ''}${r.stdout ?? ''}`.trim().split('\n')[0]) || `exit ${r.status}`;
  const keep = (text) => `${text}; run from the main checkout: ${fallback}`;
  const probe = run(['--dry-run']);
  let plan = null;
  try { plan = probe.status === 0 ? JSON.parse(probe.stdout) : null; } catch { /* reported below */ }
  if (!plan) return { would: 0, refs: [], recovered: 0, keep: keep(`ledger check failed (${why(probe)})`) };
  const refs = [...new Set(plan.entries.map((e) => e.ref_id))].sort();
  const would = plan.runs_recovered;
  const write = writable && would > 0;
  if (!write || dryRun) return { would, refs, recovered: 0, keep: would > 0 && !writable ? keep(`${would} run(s) of ${refs.join(', ')} not in the ride ledger`) : null };
  const r = run([]);
  const m = /^RECOVER SUMMARY .* recovered=(\d+) /m.exec(r.stdout ?? '');
  if (r.status !== 0 || !m) return { would, refs, recovered: 0, keep: keep(`ledger write failed (${why(r)})`) };
  return { would, refs, recovered: Number(m[1]), keep: null };
}
