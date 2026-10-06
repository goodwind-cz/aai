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
