#!/usr/bin/env node
// generate-factory-report.mjs — Factory Performance Report generator
// (SPEC spec-factory-performance-report / CHANGE factory-performance-report).
//
// Answers the owner ask "how efficiently is the factory running — what does it
// deliver, how fast, at what token cost, at what quality — over time" as a
// self-contained docs/ai/factory-report.html (+ factory-report-data.json),
// assembled deterministically from the existing committed ledgers:
//   - docs/ai/METRICS.jsonl   (per-ride agent_runs, reliability, verdict)
//   - docs/ai/EVENTS.jsonl    (work_item_closed timestamps)
//   - docs/releases/*.md      (links.members release grouping)
//
// It is NOT generate-dashboard.mjs (per-operation activity telemetry, keyed on
// tokens_in/out which are null across this repo) nor generate-overview.mjs
// (stakeholder "what shipped" cards). It is the time-series efficiency layer
// none of the three provide, built by REUSING the proven pieces of
// generate-overview.mjs (inline self-contained render, the shared
// lib/usage-note.mjs token grammar, readReleaseMembers grouping, the
// work_item_closed close-date map) and mirroring metrics-report.mjs honesty:
// TOKENS ONLY, null preserved, never a fabricated USD figure, no LLM parsing
// of prose notes.
//
// Usage: node .aai/scripts/generate-factory-report.mjs
//          [--output <html path>] [--data-only]
//          [--metrics <path>] [--events <path>] [--releases <dir>]
// Read-only over inputs; writes only the two output files. Node stdlib only,
// zero network (docs/TECHNOLOGY.md). Always exits 0 on a readable/absent
// ledger; a malformed JSONL line is skipped and named, never fatal.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { extractUsageTotal, CANONICAL_ROLES, normalizeRole } from './lib/usage-note.mjs';

const ROOT = process.cwd();

// readOriginUrl() -> the `origin` remote URL, or null on any failure (not a git
// repo, no origin, git missing). Mirrors pr-platform.mjs (uses the same
// execFileSync/stdio contract), read as `git config --get remote.origin.url`.
function readOriginUrl() {
  try {
    const out = execFileSync('git', ['config', '--get', 'remote.origin.url'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out === '' ? null : out;
  } catch {
    return null;
  }
}

// remoteSlug(url) -> 'owner/repo' from a git remote URL, or null when it cannot
// be parsed. Parsing style follows pr-platform.mjs: strip HTTPS basic-auth
// userinfo, then take the last two path segments of either an scheme:// URL or an
// scp-like `git@host:owner/repo(.git)` form, dropping a trailing `.git`.
function remoteSlug(remoteUrl) {
  if (!remoteUrl) return null;
  const clean = remoteUrl.replace(/^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/)[^/]*@/, '$1');
  const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(clean);
  let pathPart;
  if (hasScheme) {
    try { pathPart = new URL(clean).pathname; } catch { return null; }
  } else {
    const m = clean.match(/^(?:[^@/:]+@)?[^:/]+:(.+)$/);
    if (!m) return null;
    pathPart = m[1];
  }
  const parts = pathPart.replace(/\.git$/, '').split('/').filter(Boolean);
  if (parts.length < 2) return null;
  return parts.slice(-2).join('/');
}

// projectLabel() -> a STABLE report identity. Derived from the origin remote
// slug (owner/repo) so the committed artifact does not embed the throwaway
// working-directory basename (a git worktree is named e.g. agent-a1b…). Falls
// back to the cwd basename only when no remote slug is resolvable.
function projectLabel() {
  return remoteSlug(readOriginUrl()) ?? path.basename(ROOT);
}

// CANONICAL_ROLES + normalizeRole now live in lib/usage-note.mjs (the single
// source shared with the close-time usage-capture gate, so a new role variant
// is never silently un-gated OR mis-bucketed — spec-telemetry-completeness).

function parseArgs(argv) {
  const args = {
    outputPath: 'docs/ai/factory-report.html',
    dataOnly: false,
    metricsPath: 'docs/ai/METRICS.jsonl',
    eventsPath: 'docs/ai/EVENTS.jsonl',
    releasesDir: 'docs/releases',
  };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--output' && argv[i + 1]) { args.outputPath = argv[i + 1]; i += 1; continue; }
    if (tok === '--metrics' && argv[i + 1]) { args.metricsPath = argv[i + 1]; i += 1; continue; }
    if (tok === '--events' && argv[i + 1]) { args.eventsPath = argv[i + 1]; i += 1; continue; }
    if (tok === '--releases' && argv[i + 1]) { args.releasesDir = argv[i + 1]; i += 1; continue; }
    if (tok === '--data-only') { args.dataOnly = true; continue; }
    if (tok === '-h' || tok === '--help') {
      console.log('Usage: generate-factory-report.mjs [--output <html>] [--data-only] [--metrics <path>] [--events <path>] [--releases <dir>]');
      process.exit(0);
    }
  }
  return args;
}

// readJsonl(absPath) -> { rows, dropped }: parses one JSON object per line,
// skipping blank and '#'-comment lines; a JSON-invalid line is DROPPED and
// counted (degrade-with-NOTE, never fatal — Spec-AC-08). Absent file -> empty.
function readJsonl(absPath) {
  const rows = [];
  let dropped = 0;
  if (!fs.existsSync(absPath)) return { rows, dropped };
  for (const line of fs.readFileSync(absPath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (t === '' || t.startsWith('#')) continue;
    try { rows.push(JSON.parse(t)); } catch { dropped += 1; }
  }
  return { rows, dropped };
}

// isoWeek(dateStr 'YYYY-MM-DD' | ISO ts) -> 'YYYY-Www' (ISO-8601), computed
// from UTC components only — no locale, no Date week helpers, deterministic.
function isoWeek(dateStr) {
  if (typeof dateStr !== 'string' || dateStr.length < 10) return null;
  const y = Number(dateStr.slice(0, 4));
  const m = Number(dateStr.slice(5, 7));
  const d = Number(dateStr.slice(8, 10));
  if (!Number.isInteger(y) || !Number.isInteger(m) || !Number.isInteger(d)) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (Number.isNaN(dt.getTime())) return null;
  // ISO: Thursday of the current week decides the year; week 1 holds Jan 4th.
  const day = dt.getUTCDay() === 0 ? 7 : dt.getUTCDay();
  dt.setUTCDate(dt.getUTCDate() + 4 - day);
  const isoYear = dt.getUTCFullYear();
  const yearStart = new Date(Date.UTC(isoYear, 0, 1));
  const week = Math.ceil((((dt - yearStart) / 86400000) + 1) / 7);
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}

function median(nums) {
  const xs = nums.filter((n) => typeof n === 'number' && Number.isFinite(n)).sort((a, b) => a - b);
  if (xs.length === 0) return null;
  const mid = Math.floor(xs.length / 2);
  return xs.length % 2 ? xs[mid] : Math.round((xs[mid - 1] + xs[mid]) / 2);
}

function mean1(nums) {
  const xs = nums.filter((n) => typeof n === 'number' && Number.isFinite(n));
  if (xs.length === 0) return null;
  return Math.round((xs.reduce((a, v) => a + v, 0) / xs.length) * 10) / 10;
}

// readReleaseMembers(body) — release doc `links.members` list (inline or
// block form). Byte-for-byte the same contract as generate-overview.mjs so
// the two group deliveries identically (Spec-AC-06 SEAM 2).
function readReleaseMembers(body) {
  const norm = body.replace(/\r\n?/g, '\n');
  const fm = norm.match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return [];
  const lines = fm[1].split('\n');
  const linksIdx = lines.findIndex((l) => /^links:\s*$/.test(l));
  if (linksIdx === -1) return [];
  let membersIdx = -1;
  for (let i = linksIdx + 1; i < lines.length; i += 1) {
    if (/^\S/.test(lines[i])) break;
    if (/^ {2}members:/.test(lines[i])) { membersIdx = i; break; }
  }
  if (membersIdx === -1) return [];
  const inline = lines[membersIdx].match(/^ {2}members:\s*\[(.*)\]\s*$/);
  if (inline) {
    return inline[1].split(',').map((s) => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
  }
  const members = [];
  for (let i = membersIdx + 1; i < lines.length; i += 1) {
    const mm = lines[i].match(/^ {4}-\s*(.+?)\s*$/);
    if (!mm) break;
    members.push(mm[1].replace(/^["']|["']$/g, ''));
  }
  return members;
}

function readFrontmatterField(body, key) {
  const fm = body.replace(/\r\n?/g, '\n').match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return null;
  const m = fm[1].match(new RegExp(`^${key}:\\s*(.+?)\\s*$`, 'm'));
  return m ? m[1].replace(/^["']|["']$/g, '') : null;
}

// releaseMembership(releasesDir) -> Map<ref, {id, title}> (first release that
// names a ref wins) — same precedence as generate-overview.mjs.
function releaseMembership(releasesDir) {
  const abs = path.join(ROOT, releasesDir);
  const map = new Map();
  let files = [];
  try { files = fs.readdirSync(abs).filter((f) => f.endsWith('.md') && f !== 'INDEX.md').sort(); } catch { return map; }
  for (const f of files) {
    let body;
    try { body = fs.readFileSync(path.join(abs, f), 'utf8'); } catch { continue; }
    const id = readFrontmatterField(body, 'id') || f.replace(/\.md$/, '');
    const title = readFrontmatterField(body, 'title') || id;
    for (const member of readReleaseMembers(body)) {
      if (!map.has(member)) map.set(member, { id, title });
    }
  }
  return map;
}

function buildModel(args) {
  const metricsAbs = path.resolve(ROOT, args.metricsPath);
  const eventsAbs = path.resolve(ROOT, args.eventsPath);
  const { rows: metrics, dropped: droppedMetrics } = readJsonl(metricsAbs);
  const { rows: events, dropped: droppedEvents } = readJsonl(eventsAbs);
  const membership = releaseMembership(args.releasesDir);

  const notes = [];
  const rides = metrics.filter((m) => m && m.ref_id);
  const empty = rides.length === 0;

  // --- deliveries + close dates (EVENTS). "Delivered" is the honest
  // work_item_closed signal only — a work item the factory actually closed.
  // doc_lifecycle->done status flips are NOT counted as separate deliveries
  // (many fire per work item; counting them would inflate throughput).
  // A ref may be closed MORE THAN ONCE (reopened, then re-delivered). Decision:
  // delivered_total stays DISTINCT refs (a re-close is not a second delivery),
  // and the delivery moment is the LATEST close — a re-delivery after reopen
  // supersedes the earlier close. So keep the max timestamp (NOT last-write-wins
  // by ledger order, which would silently honor whichever line came last), and
  // count re-closed refs for an honesty note below (Codex P2 :208).
  const closedAt = new Map();
  const closeCounts = new Map();
  let reviewEvents = 0;
  for (const e of events) {
    if (!e) continue;
    if (e.event === 'code_review_completed') { reviewEvents += 1; continue; }
    if (e.event === 'work_item_closed' && e.ref && e.ts) {
      closeCounts.set(e.ref, (closeCounts.get(e.ref) ?? 0) + 1);
      const prev = closedAt.get(e.ref);
      // ISO-8601 timestamps compare lexicographically -> latest close wins.
      if (prev === undefined || e.ts > prev) closedAt.set(e.ref, e.ts);
    }
  }
  const reClosedRefs = [...closeCounts.values()].filter((n) => n > 1).length;

  // --- earliest agent-run start per ref (for lead time).
  const earliestStart = new Map();
  for (const m of rides) {
    for (const r of m.agent_runs ?? []) {
      const s = typeof r.started_utc === 'string' ? Date.parse(r.started_utc) : NaN;
      if (Number.isNaN(s)) continue;
      if (!earliestStart.has(m.ref_id) || s < earliestStart.get(m.ref_id)) earliestStart.set(m.ref_id, s);
    }
  }

  // ============================ THROUGHPUT ============================
  // Delivered = refs with a close event. Per ISO week and per release.
  const deliveredRefs = [...closedAt.keys()];
  const deliveredByWeek = new Map();
  for (const ref of deliveredRefs) {
    const wk = isoWeek(closedAt.get(ref));
    if (!wk) continue;
    deliveredByWeek.set(wk, (deliveredByWeek.get(wk) ?? 0) + 1);
  }
  // Per-release / close-month grouping (mirrors generate-overview.mjs).
  const groups = new Map();
  for (const ref of deliveredRefs) {
    const rel = membership.get(ref);
    if (rel) {
      const key = `release:${rel.id}`;
      if (!groups.has(key)) groups.set(key, { key, kind: 'release', label: rel.title, ref: rel.id, count: 0, refs: [] });
      const g = groups.get(key); g.count += 1; g.refs.push(ref);
    } else {
      const ts = closedAt.get(ref);
      const month = ts && ts.length >= 7 ? ts.slice(0, 7) : 'undated';
      const key = `month:${month}`;
      if (!groups.has(key)) groups.set(key, { key, kind: 'month', label: month === 'undated' ? 'Undated' : month, count: 0, refs: [] });
      const g = groups.get(key); g.count += 1; g.refs.push(ref);
    }
  }
  const deliveredGroups = [...groups.values()].sort((a, b) => {
    if (a.kind !== b.kind) return a.kind === 'release' ? -1 : 1;
    return a.label.localeCompare(b.label);
  });
  // Lead time per delivered ref (null when either endpoint is absent).
  const leadTimes = [];
  for (const ref of deliveredRefs) {
    const closeMs = Date.parse(closedAt.get(ref));
    const startMs = earliestStart.has(ref) ? earliestStart.get(ref) : null;
    const lead = (startMs !== null && !Number.isNaN(closeMs) && closeMs >= startMs)
      ? Math.round((closeMs - startMs) / 1000) : null;
    leadTimes.push({ ref, lead_time_seconds: lead });
  }
  const leadVals = leadTimes.map((x) => x.lead_time_seconds).filter((v) => v !== null);

  // ============================ SPEED ============================
  const perRide = [];
  const roleDurations = new Map();     // canonical role -> total seconds
  const roleTokens = new Map();        // canonical role -> total tokens (null-safe)
  let unnormalizedRoleRuns = 0;
  // Run-level usage-capture coverage (spec-telemetry-completeness B): the
  // first-class KPI the close-time gate exists to drive upward — runs carrying
  // a valid usage_total_tokens marker / ALL agent runs, overall + per ISO week
  // (keyed on the ride's date_utc, the same week bucket the trend series uses).
  let totalRuns = 0;
  let runsWithMarker = 0;
  const coverageByWeek = new Map();    // week -> { total, with }
  for (const m of rides) {
    let busy = 0; let hasBusy = false;
    let tok = 0; let hasTok = false;
    const rideWeek = isoWeek(m.date_utc);
    for (const r of m.agent_runs ?? []) {
      if (typeof r.duration_seconds === 'number') { busy += r.duration_seconds; hasBusy = true; }
      const role = normalizeRole(r.role);
      if (role === null) unnormalizedRoleRuns += 1;
      const roleKey = role ?? 'Other';
      if (typeof r.duration_seconds === 'number') roleDurations.set(roleKey, (roleDurations.get(roleKey) ?? 0) + r.duration_seconds);
      const t = extractUsageTotal(r.note);
      totalRuns += 1;
      if (t !== null) {
        tok += t; hasTok = true;
        roleTokens.set(roleKey, (roleTokens.get(roleKey) ?? 0) + t);
        runsWithMarker += 1;
      }
      if (rideWeek) {
        const c = coverageByWeek.get(rideWeek) ?? { total: 0, with: 0 };
        c.total += 1;
        if (t !== null) c.with += 1;
        coverageByWeek.set(rideWeek, c);
      }
    }
    const rel = m.reliability && typeof m.reliability === 'object' && !Array.isArray(m.reliability) ? m.reliability : null;
    // Remediation count is reliability-only (Spec-AC-05): a ride predating the
    // reliability block is null, NOT a role-prefix guess — so pre-field rides
    // land in the explicit n/a bucket below and never inflate a numeric one.
    const remediation = rel && typeof rel.remediation_runs === 'number' ? rel.remediation_runs : null;
    perRide.push({
      ref: m.ref_id,
      date_utc: m.date_utc ?? null,
      week: isoWeek(m.date_utc),
      busy_seconds: hasBusy ? busy : null,
      tokens: hasTok ? tok : null,
      remediation_runs: remediation,
      first_pass_clean: rel && typeof rel.first_pass_clean === 'boolean' ? rel.first_pass_clean : null,
      validation_fails: rel && typeof rel.validation_fails === 'number' ? rel.validation_fails : null,
      review_fails: rel && typeof rel.review_fails === 'number' ? rel.review_fails : null,
      verdict: typeof m.verdict === 'string' ? m.verdict : null,
    });
  }
  const roleSplit = CANONICAL_ROLES
    .concat(['Other'])
    .map((role) => ({
      role,
      duration_seconds: roleDurations.has(role) ? roleDurations.get(role) : null,
      tokens: roleTokens.has(role) ? roleTokens.get(role) : null,
    }))
    .filter((x) => x.duration_seconds !== null || x.tokens !== null);

  // ============================ QUALITY ============================
  const flagged = perRide.filter((r) => r.first_pass_clean !== null);
  const clean = flagged.filter((r) => r.first_pass_clean === true).length;
  const naReliability = perRide.length - flagged.length;
  // Distribution over reliability-flagged rides only; pre-field rides go to an
  // explicit 'n/a' bucket (mirrors first_pass_clean's treatment, Spec-AC-05).
  const remediationDist = {};
  for (const r of perRide) {
    const k = r.remediation_runs === null ? 'n/a' : String(r.remediation_runs);
    remediationDist[k] = (remediationDist[k] ?? 0) + 1;
  }
  const verdictMix = {};
  for (const r of perRide) {
    const k = r.verdict ?? 'null';
    verdictMix[k] = (verdictMix[k] ?? 0) + 1;
  }

  // ============================ WEEKLY TREND SERIES ============================
  // Union of delivery weeks and ride weeks, chronologically; zero-delivery
  // weeks are PRESENT with 0 (Spec-AC-07), never omitted.
  const weekSet = new Set([...deliveredByWeek.keys()]);
  for (const r of perRide) if (r.week) weekSet.add(r.week);
  const weeks = [...weekSet].sort();
  // active_weeks = the UNION of delivery weeks and ride weeks, so the headline
  // count matches the rendered trend series exactly (Copilot :262). A ride-only
  // week (activity but no close that week) still counts as an active week.
  const activeWeeks = weeks.length;
  const trend = weeks.map((wk) => {
    const wkRides = perRide.filter((r) => r.week === wk);
    const wkLead = leadTimes
      .filter((x) => x.lead_time_seconds !== null && isoWeek(closedAt.get(x.ref)) === wk)
      .map((x) => x.lead_time_seconds);
    const wkFlagged = wkRides.filter((r) => r.first_pass_clean !== null);
    const wkClean = wkFlagged.filter((r) => r.first_pass_clean === true).length;
    const busyVals = wkRides.map((r) => r.busy_seconds).filter((v) => v !== null);
    const tokVals = wkRides.map((r) => r.tokens).filter((v) => v !== null);
    return {
      week: wk,
      delivered: deliveredByWeek.get(wk) ?? 0,
      median_lead_time_seconds: median(wkLead),
      busy_seconds: busyVals.length ? busyVals.reduce((a, v) => a + v, 0) : null,
      tokens: tokVals.length ? tokVals.reduce((a, v) => a + v, 0) : null,
      first_pass_rate: wkFlagged.length ? Math.round((100 * wkClean) / wkFlagged.length) : null,
    };
  });

  // ============================ NOTES (degrade-with-NOTE) ============================
  if (reClosedRefs) notes.push(`NOTE ${reClosedRefs} ref(s) closed more than once; latest close counted (re-delivery after reopen supersedes the earlier close; delivered_total stays distinct refs)`);
  if (droppedMetrics) notes.push(`EXCLUDED ${droppedMetrics} malformed METRICS.jsonl line(s) (unparseable JSON, skipped)`);
  if (droppedEvents) notes.push(`EXCLUDED ${droppedEvents} malformed EVENTS.jsonl line(s) (unparseable JSON, skipped)`);
  if (unnormalizedRoleRuns) notes.push(`NOTE ${unnormalizedRoleRuns} agent_run(s) had a role that matched no canonical role — bucketed as Other`);
  if (naReliability) notes.push(`NOTE ${naReliability} ride(s) predate the reliability block — excluded from quality rates (shown as n/a, never zero)`);
  const noMarkerRides = perRide.filter((r) => r.tokens === null).length;
  if (noMarkerRides) notes.push(`NOTE ${noMarkerRides} ride(s) carry no usage_total_tokens marker — token cost shown as n/a (never imputed, never USD)`);

  const rideTokenVals = perRide.map((r) => r.tokens).filter((v) => v !== null);
  const rideBusyVals = perRide.map((r) => r.busy_seconds).filter((v) => v !== null);

  // Run-level capture-coverage KPI (spec-telemetry-completeness B): overall +
  // per-week series, an explicit percentage — pct is null (never a fabricated
  // zero) only when there are NO runs at all; a real 0% (runs present, none
  // marked) is reported honestly.
  const captureByWeek = [...coverageByWeek.keys()].sort().map((wk) => {
    const c = coverageByWeek.get(wk);
    return { week: wk, runs_with_marker: c.with, total_runs: c.total, pct: c.total ? Math.round((100 * c.with) / c.total) : null };
  });
  const captureCoverage = {
    runs_with_marker: runsWithMarker,
    total_runs: totalRuns,
    pct: totalRuns ? Math.round((100 * runsWithMarker) / totalRuns) : null,
    by_week: captureByWeek,
  };

  return {
    generatedAt: new Date().toISOString(),
    project: projectLabel(),
    empty,
    empty_reason: empty ? 'no metrics recorded yet' : null,
    counts: {
      rides: rides.length,
      delivered: deliveredRefs.length,
      active_weeks: activeWeeks,
      releases: deliveredGroups.filter((g) => g.kind === 'release').length,
      review_events: reviewEvents,
    },
    throughput: {
      note: `"delivered" counts every work_item_closed event (${deliveredRefs.length} closes vs ${rides.length} recorded metric rides) — this includes administrative and non-feature doc closes, not only full agent rides`,
      delivered_total: deliveredRefs.length,
      delivered_per_week_avg: activeWeeks ? Math.round((deliveredRefs.length / activeWeeks) * 10) / 10 : null,
      delivered_by_week: Object.fromEntries(deliveredByWeek),
      delivered_groups: deliveredGroups,
      lead_time: {
        per_item: leadTimes,
        median_seconds: median(leadVals),
        mean_seconds: mean1(leadVals),
        measured: leadVals.length,
        unmeasurable: leadTimes.length - leadVals.length,
      },
    },
    speed: {
      ride_busy_seconds: { median: median(rideBusyVals), mean: mean1(rideBusyVals), measured: rideBusyVals.length },
      role_split: roleSplit,
      per_ride: perRide.map((r) => ({ ref: r.ref, busy_seconds: r.busy_seconds, remediation_runs: r.remediation_runs })),
      note: 'busy_seconds is summed agent duration (agent busy time), NOT calendar wall-clock',
    },
    cost: {
      tokens_only: true,
      usd: null,
      usd_note: 'no USD figure is derivable — tokens_in/out are null across the ledger and the usage marker is an undecomposed total with no in/out split to price',
      tokens_per_ride: { median: median(rideTokenVals), mean: mean1(rideTokenVals), measured: rideTokenVals.length },
      tokens_total: rideTokenVals.length ? rideTokenVals.reduce((a, v) => a + v, 0) : null,
      by_role: roleSplit.map((x) => ({ role: x.role, tokens: x.tokens })),
      capture_coverage: captureCoverage,
    },
    quality: {
      first_pass_clean: flagged.length ? { clean, flagged: flagged.length, rate_pct: Math.round((100 * clean) / flagged.length) } : { clean: 0, flagged: 0, rate_pct: null },
      na_reliability: naReliability,
      remediation_distribution: remediationDist,
      avg_validation_fails: mean1(perRide.map((r) => r.validation_fails)),
      avg_review_fails: mean1(perRide.map((r) => r.review_fails)),
      verdict_mix: verdictMix,
      review_events: reviewEvents,
      review_verdict_note: 'per-review pass/fail lives only in prose run notes and is not mechanically derived; only ride verdict + code_review_completed count are shown',
    },
    trend,
    notes,
  };
}

// ============================ RENDER ============================

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
const na = (v) => (v === null || v === undefined ? 'n/a' : String(v));
function fmtDur(sec) {
  if (sec === null || sec === undefined) return 'n/a';
  if (sec < 90) return `${sec}s`;
  if (sec < 5400) return `${Math.round(sec / 60)}m`;
  return `${Math.round((sec / 3600) * 10) / 10}h`;
}

// barSeries(values) -> inline SVG bar chart (self-contained, no external refs).
function barSeries(series, key, labelFn) {
  const vals = series.map((p) => (typeof p[key] === 'number' ? p[key] : 0));
  const max = Math.max(1, ...vals);
  const bw = 30; const gap = 8; const h = 90; const pad = 18;
  const w = series.length * (bw + gap) + pad;
  const bars = series.map((p, i) => {
    const v = typeof p[key] === 'number' ? p[key] : 0;
    const bh = Math.round((v / max) * (h - pad));
    const x = pad + i * (bw + gap);
    const y = h - bh - pad + 4;
    const isNull = p[key] === null || p[key] === undefined;
    return `<rect x="${x}" y="${y}" width="${bw}" height="${Math.max(1, bh)}" class="${isNull ? 'bar bar-null' : 'bar'}"><title>${esc(p.week)}: ${isNull ? 'n/a' : labelFn(p[key])}</title></rect>`
      + `<text x="${x + bw / 2}" y="${h - 4}" class="xlab">${esc(p.week.slice(-3))}</text>`;
  }).join('');
  return `<svg viewBox="0 0 ${w} ${h}" class="spark" role="img" preserveAspectRatio="xMinYMid meet">${bars}</svg>`;
}

function renderHtml(m) {
  if (m.empty) {
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${esc(m.project)} — Factory Performance Report</title></head><body><h1>${esc(m.project)} — Factory Performance Report</h1><p>No metrics recorded yet.</p></body></html>\n`;
  }
  const lead = m.throughput.lead_time;
  const notesHtml = m.notes.length
    ? `<section><h2>Data honesty notes</h2><ul class="notes">${m.notes.map((n) => `<li>${esc(n)}</li>`).join('')}</ul></section>`
    : '';
  const groupRows = m.throughput.delivered_groups
    .map((g) => `<tr><td>${esc(g.label)}</td><td>${esc(g.kind)}</td><td>${g.count}</td></tr>`).join('');
  const roleRows = m.speed.role_split
    .map((r) => `<tr><td>${esc(r.role)}</td><td>${fmtDur(r.duration_seconds)}</td><td>${na(r.tokens)}</td></tr>`).join('');
  // Deterministic order: numeric remediation-count buckets ascending, then the
  // non-numeric 'n/a' bucket LAST explicitly (Number('n/a') is NaN, whose
  // comparisons are undefined — never let it decide the order — Copilot :462).
  const remRows = Object.keys(m.quality.remediation_distribution)
    .sort((a, b) => {
      const na = Number(a); const nb = Number(b);
      const aNum = Number.isFinite(na); const bNum = Number.isFinite(nb);
      if (aNum && bNum) return na - nb;
      if (aNum) return -1;
      if (bNum) return 1;
      return a.localeCompare(b);
    })
    .map((k) => `<tr><td>${esc(k)}</td><td>${m.quality.remediation_distribution[k]}</td></tr>`).join('');
  const verdictRows = Object.keys(m.quality.verdict_mix).sort()
    .map((k) => `<tr><td>${esc(k)}</td><td>${m.quality.verdict_mix[k]}</td></tr>`).join('');
  const fpc = m.quality.first_pass_clean;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(m.project)} — Factory Performance Report</title>
<style>
  :root { color-scheme: light dark; --fg:#1c1c1c; --bg:#fff; --muted:#6b6b6b; --line:#e3e3e3; --accent:#0b62d6; --bar:#0b62d6; --barnull:#c9c9c9; --card:#f7f7f8; }
  @media (prefers-color-scheme: dark) { :root { --fg:#e8e8e8; --bg:#161616; --muted:#9a9a9a; --line:#333; --accent:#6fb0ff; --bar:#6fb0ff; --barnull:#444; --card:#1f1f1f; } }
  :root[data-theme="dark"] { --fg:#e8e8e8; --bg:#161616; --muted:#9a9a9a; --line:#333; --accent:#6fb0ff; --bar:#6fb0ff; --barnull:#444; --card:#1f1f1f; }
  :root[data-theme="light"] { --fg:#1c1c1c; --bg:#fff; --muted:#6b6b6b; --line:#e3e3e3; --accent:#0b62d6; --bar:#0b62d6; --barnull:#c9c9c9; --card:#f7f7f8; }
  body { margin:0 auto; max-width:64rem; padding:2rem 1.25rem 4rem; font:16px/1.55 system-ui, sans-serif; color:var(--fg); background:var(--bg); }
  h1 { font-size:1.6rem; margin-bottom:.25rem; }
  h2 { font-size:1.15rem; border-bottom:1px solid var(--line); padding-bottom:.3rem; margin-top:2.2rem; }
  .meta { color:var(--muted); font-size:.85rem; }
  .kpis { display:flex; gap:1rem; flex-wrap:wrap; margin:1rem 0; }
  .kpi { background:var(--card); border:1px solid var(--line); border-radius:.6rem; padding:.7rem 1.1rem; min-width:8rem; }
  .kpi b { font-size:1.5rem; display:block; }
  .kpi span { color:var(--muted); font-size:.8rem; }
  table { border-collapse:collapse; width:100%; font-size:.9rem; margin:.4rem 0; }
  th, td { border-bottom:1px solid var(--line); padding:.35rem .5rem; text-align:left; }
  .scroll { overflow-x:auto; }
  .spark { max-width:100%; height:auto; display:block; margin:.5rem 0; }
  .bar { fill:var(--bar); }
  .bar-null { fill:var(--barnull); }
  .xlab { fill:var(--muted); font-size:9px; text-anchor:middle; }
  .notes li { color:var(--muted); font-size:.85rem; }
</style>
</head>
<body>
<h1>${esc(m.project)} — Factory Performance Report</h1>
<p class="meta">Generated ${esc(m.generatedAt)} · ${m.counts.rides} rides · ${m.counts.delivered} delivered · ${m.counts.active_weeks} active weeks · regenerate with <code>node .aai/scripts/generate-factory-report.mjs</code></p>

<section>
<h2>Throughput — what the factory delivers</h2>
<div class="kpis">
  <div class="kpi"><b>${m.throughput.delivered_total}</b><span>delivered (total)</span></div>
  <div class="kpi"><b>${na(m.throughput.delivered_per_week_avg)}</b><span>delivered / week (avg)</span></div>
  <div class="kpi"><b>${fmtDur(lead.median_seconds)}</b><span>median lead time</span></div>
  <div class="kpi"><b>${lead.measured}/${lead.measured + lead.unmeasurable}</b><span>lead time measurable</span></div>
</div>
<div class="scroll">${barSeries(m.trend, 'delivered', (v) => `${v} delivered`)}</div>
<p class="meta">Delivered per ISO week (zero-delivery weeks shown as empty bars).</p>
<p class="meta">${esc(m.throughput.note)}.</p>
<div class="scroll"><table><thead><tr><th>Release / month</th><th>Kind</th><th>Delivered</th></tr></thead><tbody>${groupRows}</tbody></table></div>
</section>

<section>
<h2>Speed — how fast</h2>
<div class="kpis">
  <div class="kpi"><b>${fmtDur(m.speed.ride_busy_seconds.median)}</b><span>median ride busy time</span></div>
  <div class="kpi"><b>${fmtDur(m.speed.ride_busy_seconds.mean)}</b><span>mean ride busy time</span></div>
</div>
<div class="scroll">${barSeries(m.trend, 'busy_seconds', (v) => fmtDur(v))}</div>
<p class="meta">${esc(m.speed.note)}.</p>
<div class="scroll"><table><thead><tr><th>Role</th><th>Total busy time</th><th>Tokens (undecomposed)</th></tr></thead><tbody>${roleRows}</tbody></table></div>
</section>

<section>
<h2>Cost — at what token price</h2>
<div class="kpis">
  <div class="kpi"><b>${na(m.cost.tokens_total)}</b><span>tokens total (undecomposed)</span></div>
  <div class="kpi"><b>${na(m.cost.tokens_per_ride.median)}</b><span>median tokens / ride</span></div>
  <div class="kpi"><b>${m.cost.tokens_per_ride.measured}/${m.counts.rides}</b><span>rides with token data</span></div>
  <div class="kpi"><b>${m.cost.capture_coverage.pct === null ? 'n/a' : `${m.cost.capture_coverage.pct}%`}</b><span>usage capture coverage (${m.cost.capture_coverage.runs_with_marker}/${m.cost.capture_coverage.total_runs} runs)</span></div>
</div>
<div class="scroll">${barSeries(m.trend, 'tokens', (v) => `${v} tokens`)}</div>
<p class="meta">Tokens only — ${esc(m.cost.usd_note)}.</p>
<div class="scroll">${barSeries(m.cost.capture_coverage.by_week, 'pct', (v) => `${v}%`)}</div>
<p class="meta">Run-level usage-capture coverage per ISO week — runs carrying a usage_total_tokens marker / total runs (${m.cost.capture_coverage.runs_with_marker}/${m.cost.capture_coverage.total_runs} overall). A close-time gate (usage_capture_gate) drives this upward.</p>
</section>

<section>
<h2>Quality — at what quality</h2>
<div class="kpis">
  <div class="kpi"><b>${fpc.rate_pct === null ? 'n/a' : `${fpc.rate_pct}%`}</b><span>first-pass clean (${fpc.clean}/${fpc.flagged})</span></div>
  <div class="kpi"><b>${na(m.quality.avg_validation_fails)}</b><span>avg validation fails</span></div>
  <div class="kpi"><b>${na(m.quality.avg_review_fails)}</b><span>avg review fails</span></div>
  <div class="kpi"><b>${m.quality.review_events}</b><span>code reviews recorded</span></div>
</div>
<div class="scroll">${barSeries(m.trend, 'first_pass_rate', (v) => `${v}%`)}</div>
<p class="meta">First-pass-clean rate per ISO week (weeks with no reliability data show empty bars). ${esc(m.quality.review_verdict_note)}.</p>
<div class="scroll"><table><thead><tr><th>Remediation runs</th><th>Rides</th></tr></thead><tbody>${remRows}</tbody></table></div>
<div class="scroll"><table><thead><tr><th>Ride verdict</th><th>Rides</th></tr></thead><tbody>${verdictRows}</tbody></table></div>
</section>

${notesHtml}
</body>
</html>
`;
}

function main() {
  const args = parseArgs(process.argv);
  const model = buildModel(args);
  const dataPath = path.resolve(ROOT, path.join(path.dirname(args.outputPath), 'factory-report-data.json'));
  fs.mkdirSync(path.dirname(dataPath), { recursive: true });
  fs.writeFileSync(dataPath, `${JSON.stringify(model, null, 2)}\n`);
  if (!args.dataOnly) {
    const htmlPath = path.resolve(ROOT, args.outputPath);
    fs.mkdirSync(path.dirname(htmlPath), { recursive: true });
    fs.writeFileSync(htmlPath, renderHtml(model));
    console.log(`factory-report: ${model.counts.rides} rides, ${model.counts.delivered} delivered, ${model.counts.active_weeks} active weeks`);
    console.log(`- ${path.relative(ROOT, htmlPath)}`);
  }
  console.log(`- ${path.relative(ROOT, dataPath)}`);
}

main();

export { buildModel, normalizeRole, isoWeek, readReleaseMembers, median };
