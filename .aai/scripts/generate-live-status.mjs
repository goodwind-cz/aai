#!/usr/bin/env node
// generate-live-status.mjs — optional, zero-token live-status dashboard
// (SPEC-DRAFT-spec-live-status-dashboard / CHANGE-0127).
//
// Answers what the existing three generators (dashboard, factory-report,
// overview) cannot: what is running NOW, what it has cost TODAY, and how
// much official plan-quota headroom is left. Mirrors
// generate-factory-report.mjs's shape (parseArgs / buildModel / renderHtml /
// main) but reads harness session transcripts through a per-harness PARSER
// REGISTRY (.aai/scripts/live-parsers/registry.mjs) instead of the AAI
// ledgers — none of the other three generators knows a harness session file
// exists, and this one never reads docs/ai/STATE.yaml.
//
// Node stdlib only, zero network, zero outbound socket (docs/TECHNOLOGY.md).
// Read-only over every harness/session/spool input; writes only the two
// output files plus the incremental cache. Exits 0 even when every harness
// directory is absent (each absence named in the `degraded` array, never
// fatal).
//
// Usage: node .aai/scripts/generate-live-status.mjs
//          [--output <html path>] [--data-only] [--watch] [--interval <s>]
//          [--now <iso>] [--home <dir>] [--no-cache] [--cache <path>]
//          [--spool-dir <dir>]

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import PARSERS from './live-parsers/registry.mjs';

const ROOT = process.cwd();
const DAY_MS = 24 * 60 * 60 * 1000;
const HEURISTIC_RUNNING_WINDOW_MS = 15 * 60 * 1000;
// The env vars each parser's roots(env) prefers over HOME/USERPROFILE (see
// live-parsers/claude-code.mjs, codex.mjs, gemini-cli.mjs). --home must strip
// all of these or a machine that exports one of them silently defeats the
// fixture override and reads the real corpus (BLOCKING-3, code review
// CHANGE-0127). Extend this list whenever a new parser adds its own override.
const HARNESS_ENV_OVERRIDES = ['CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'GEMINI_HOME'];

function parseArgs(argv) {
  const args = {
    outputPath: 'docs/ai/live-status.html',
    dataOnly: false,
    watch: false,
    interval: 30,
    now: null,
    home: null,
    noCache: false,
    cachePath: '.aai/cache/live-status-index.json',
    spoolDir: null,
  };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--output' && argv[i + 1]) { args.outputPath = argv[i + 1]; i += 1; continue; }
    if (tok === '--data-only') { args.dataOnly = true; continue; }
    if (tok === '--watch') { args.watch = true; continue; }
    if (tok === '--interval' && argv[i + 1]) { args.interval = Number(argv[i + 1]); i += 1; continue; }
    if (tok === '--now' && argv[i + 1]) { args.now = argv[i + 1]; i += 1; continue; }
    if (tok === '--home' && argv[i + 1]) { args.home = argv[i + 1]; i += 1; continue; }
    if (tok === '--no-cache') { args.noCache = true; continue; }
    if (tok === '--cache' && argv[i + 1]) { args.cachePath = argv[i + 1]; i += 1; continue; }
    if (tok === '--spool-dir' && argv[i + 1]) { args.spoolDir = argv[i + 1]; i += 1; continue; }
    if (tok === '-h' || tok === '--help') {
      console.log('Usage: generate-live-status.mjs [--output <html>] [--data-only] [--watch] [--interval <s>] [--now <iso>] [--home <dir>] [--no-cache] [--cache <path>] [--spool-dir <dir>]');
      process.exit(0);
    }
  }
  if (!Number.isFinite(args.interval) || args.interval <= 0) args.interval = 30;
  return args;
}

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
const na = (v) => (v === null || v === undefined ? 'N/A' : String(v));
// naEsc: the na() semantics (missing -> literal "N/A") PLUS esc() on any
// present value. Every foreign-data interpolation in renderHtml() must go
// through esc() or naEsc() — na() alone is not an escaping function (see
// BLOCKING-1, code review CHANGE-0127: the session-quotas branch used na()
// on payload.rate_limits.primary fields read verbatim from a harness JSONL
// file, so a hostile resets_at/used_percent rendered a live <script> into a
// page the spec guarantees is network-free).
const naEsc = (v) => (v === null || v === undefined ? 'N/A' : esc(String(v)));

function isoDay(ts) {
  return typeof ts === 'string' && ts.length >= 10 ? ts.slice(0, 10) : null;
}
function isToday(ts, nowMs, nowDay) {
  if (!ts) return false;
  const d = isoDay(ts);
  if (!d) return false;
  return d === nowDay;
}
function within7d(ts, nowMs) {
  if (!ts) return false;
  const t = Date.parse(ts);
  if (Number.isNaN(t)) return false;
  return t <= nowMs && (nowMs - t) <= 7 * DAY_MS;
}

// ---- cache -------------------------------------------------------------

function loadCache(cacheAbs) {
  try {
    const raw = fs.readFileSync(cacheAbs, 'utf8');
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function saveCache(cacheAbs, cache) {
  try {
    fs.mkdirSync(path.dirname(cacheAbs), { recursive: true });
    fs.writeFileSync(cacheAbs, JSON.stringify(cache));
  } catch {
    // Cache is a pure optimization — a write failure never fails the run.
  }
}

// ---- scan ----------------------------------------------------------------

// scanHarness(entry, env, cache, args, notes) -> per-harness raw records plus
// scan counters. A file whose cached {mtimeMs, size} still matches is NOT
// re-read (Spec-AC-03): its previously-parsed records are reused verbatim.
function scanHarness(entry, env, cache, args, notes) {
  const roots = entry.roots(env);
  const rootExists = roots.some((r) => { try { return fs.existsSync(r); } catch { return false; } });
  if (!rootExists) {
    return {
      id: entry.id,
      available: false,
      root: roots[0],
      records: [],
      filesTotal: 0,
      filesRead: 0,
      filesSkipped: 0,
      fileMtimeBySession: new Map(),
    };
  }
  const files = entry.discover(roots);
  let filesRead = 0;
  let filesSkipped = 0;
  const records = [];
  const fileMtimeBySession = new Map();
  for (const file of files) {
    const key = file.path;
    const cached = !args.noCache ? cache[key] : undefined;
    let fileRecords;
    if (cached && cached.mtimeMs === file.mtimeMs && cached.size === file.size) {
      fileRecords = cached.records;
      filesSkipped += 1;
    } else {
      const parseCtx = { notes };
      fileRecords = [...entry.parse(file, parseCtx)];
      cache[key] = { mtimeMs: file.mtimeMs, size: file.size, records: fileRecords };
      filesRead += 1;
    }
    for (const r of fileRecords) {
      records.push(r);
      if (r.sessionId) {
        const prev = fileMtimeBySession.get(r.sessionId);
        if (prev === undefined || file.mtimeMs > prev) fileMtimeBySession.set(r.sessionId, file.mtimeMs);
      }
    }
  }
  return {
    id: entry.id,
    available: true,
    root: roots[0],
    records,
    filesTotal: files.length,
    filesRead,
    filesSkipped,
    fileMtimeBySession,
  };
}

// accumulate(entry, records) -> the records that actually count toward
// usage, per the entry's accumulation mode (Spec-AC-02):
//   event_sum_dedup:        every record once, skipping repeat dedupKeys.
//   session_cumulative_last: per sessionId, only the LAST record (by ts).
//   none:                   pass-through (usage is null on every record).
function accumulate(entry, records) {
  if (entry.accumulation === 'event_sum_dedup') {
    const seen = new Set();
    const out = [];
    for (const r of records) {
      if (r.dedupKey) {
        if (seen.has(r.dedupKey)) continue;
        seen.add(r.dedupKey);
      }
      out.push(r);
    }
    return out;
  }
  if (entry.accumulation === 'session_cumulative_last') {
    const bySession = new Map();
    for (const r of records) {
      if (!r.sessionId) continue;
      const prev = bySession.get(r.sessionId);
      if (!prev) { bySession.set(r.sessionId, r); continue; }
      if (r.ts && prev.ts) {
        // Both sides carry a real timestamp: the later one wins.
        if (r.ts >= prev.ts) bySession.set(r.sessionId, r);
      } else {
        // Either side lacks a reliable ts (upstream format drift, RR-3): a
        // `r.ts &&` guard here used to silently keep whichever record
        // arrived FIRST, inverting "last cumulative wins" to "first wins".
        // Fall back to encounter order — records arrive in file order, so
        // the later record in iteration deterministically wins instead.
        bySession.set(r.sessionId, r);
      }
    }
    return [...bySession.values()];
  }
  return records;
}

// ---- quotas ----------------------------------------------------------------

function readSpoolLastLine(spoolAbs) {
  let raw;
  try { raw = fs.readFileSync(spoolAbs, 'utf8'); } catch { return null; }
  const lines = raw.split('\n').map((l) => l.trim()).filter(Boolean);
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    try { return JSON.parse(lines[i]); } catch { continue; }
  }
  return null;
}

function readSpoolAllLines(spoolAbs) {
  let raw;
  try { raw = fs.readFileSync(spoolAbs, 'utf8'); } catch { return []; }
  const out = [];
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    try { out.push(JSON.parse(t)); } catch { continue; }
  }
  return out;
}

function resolveQuotas(spoolDir, harnessResults) {
  const tapPath = path.join(spoolDir, 'statusline.jsonl');
  const tap = readSpoolLastLine(tapPath);
  if (tap && tap.rate_limits && (tap.rate_limits.five_hour || tap.rate_limits.seven_day)) {
    return {
      source: 'tap',
      five_hour: tap.rate_limits.five_hour || null,
      seven_day: tap.rate_limits.seven_day || null,
      skip: null,
    };
  }
  for (const hr of harnessResults) {
    if (hr.rateLimits) {
      return {
        source: `session:${hr.id}`,
        five_hour: null,
        seven_day: null,
        primary: hr.rateLimits,
        skip: null,
      };
    }
  }
  return {
    source: null,
    five_hour: null,
    seven_day: null,
    skip: {
      reason: `no statusline-tap spool found at ${tapPath}`,
      install: 'pipe your harness statusline JSON through: bash .aai/scripts/live-spool.sh statusline (see .aai/templates/hooks/live-status-hooks.json for the opt-in overlay)',
    },
  };
}

// ---- liveness ----------------------------------------------------------------

function deriveLiveSessions(harnessResults, hooksLines, nowMs) {
  const bySession = new Map();
  for (const line of hooksLines) {
    if (!line || !line.session_id) continue;
    const prev = bySession.get(line.session_id);
    if (!prev || (line.ts && (!prev.ts || line.ts >= prev.ts))) bySession.set(line.session_id, line);
  }
  const out = [];
  for (const hr of harnessResults) {
    if (!hr.available) continue;
    const seen = new Set();
    for (const r of hr.records) {
      if (!r.sessionId || seen.has(r.sessionId)) continue;
      seen.add(r.sessionId);
      const hookLine = bySession.get(r.sessionId);
      let state;
      let heuristic = false;
      if (hookLine && hookLine.hook_event_name === 'Stop') {
        state = 'finished';
      } else if (hookLine && hookLine.hook_event_name === 'Notification') {
        state = 'waiting-on-approval';
      } else {
        heuristic = true;
        const mtime = hr.fileMtimeBySession.get(r.sessionId);
        const running = typeof mtime === 'number' && (nowMs - mtime) < HEURISTIC_RUNNING_WINDOW_MS;
        state = `${running ? 'running' : 'finished'} (heuristic)`;
      }
      out.push({
        harness: hr.id,
        sessionId: r.sessionId,
        project: r.project || null,
        state,
        heuristic,
      });
    }
  }
  return out;
}

// ---- model ----------------------------------------------------------------

function buildModel(args) {
  const now = args.now ? new Date(args.now) : new Date();
  const nowMs = now.getTime();
  const nowDay = isoDay(now.toISOString());
  const homeOverride = args.home ? path.resolve(ROOT, args.home) : null;
  const env = { ...process.env };
  if (homeOverride) {
    env.HOME = homeOverride;
    env.USERPROFILE = homeOverride;
    // --home means total isolation: strip every harness-specific override so
    // a parser cannot silently prefer the real corpus over the fixture.
    for (const key of HARNESS_ENV_OVERRIDES) delete env[key];
  }
  const spoolDir = args.spoolDir
    ? path.resolve(ROOT, args.spoolDir)
    : path.resolve(ROOT, process.env.AAI_LIVE_SPOOL_DIR || 'docs/ai/live');
  const cacheAbs = path.resolve(ROOT, args.cachePath);
  const cache = args.noCache ? {} : loadCache(cacheAbs);
  const notes = [];

  const harnessResults = [];
  const degraded = [];
  let filesTotal = 0;
  let filesRead = 0;
  let filesSkipped = 0;

  for (const entry of PARSERS) {
    const scan = scanHarness(entry, env, cache, args, notes);
    filesTotal += scan.filesTotal;
    filesRead += scan.filesRead;
    filesSkipped += scan.filesSkipped;
    if (!scan.available) {
      degraded.push({ source: entry.id, reason: `ABSENT: expected at ${scan.root}` });
    }
    const usageRecords = accumulate(entry, scan.records);
    const sessions = new Set(scan.records.filter((r) => r.sessionId).map((r) => r.sessionId));
    let usageToday = null;
    let usage7d = null;
    // project -> {today, sevenDay}; values are numbers when a real usage
    // total was accumulated, or `null` when the honesty invariant requires
    // it (see the two branches below) — never a fabricated 0.
    const spendByProject = new Map();
    if (scan.available && entry.accumulation !== 'none') {
      usageToday = 0;
      usage7d = 0;
      for (const r of usageRecords) {
        if (r.usage === null || r.usage === undefined) continue;
        const proj = r.project || 'unknown';
        if (!spendByProject.has(proj)) spendByProject.set(proj, { today: 0, sevenDay: 0 });
        const bucket = spendByProject.get(proj);
        if (isToday(r.ts, nowMs, nowDay)) { usageToday += r.usage; bucket.today += r.usage; }
        if (within7d(r.ts, nowMs)) { usage7d += r.usage; bucket.sevenDay += r.usage; }
        if (!r.ts) {
          // Honesty gap (validator O1 / review NB-7): a ts-less record
          // matches neither isToday nor within7d and used to contribute a
          // silent, plausible-looking 0 to every bucket. Name it instead of
          // burying it — an upstream format that stops writing timestamps
          // must not look indistinguishable from a genuinely idle day.
          notes.push(`${entry.id}: record with usage ${r.usage} has no timestamp; excluded from usage_today and usage_7d`);
        }
      }
    } else if (scan.available && entry.accumulation === 'none') {
      // Spec-AC-04: this format carries no usage fields at all (Gemini CLI).
      // Surface an explicit spend row per project with tokens: null so the
      // renderer's N/A cell actually reaches the page — omitting the row
      // entirely (the old behavior) silently dropped the AC's named
      // observable even though the top-level usage_today/usage_7d were
      // already honest.
      const projects = new Set(scan.records.map((r) => r.project || 'unknown'));
      for (const proj of projects) spendByProject.set(proj, { today: null, sevenDay: null });
    }
    // scan.available === false (harness dir ABSENT): usageToday/usage7d and
    // spendByProject stay null/empty. An absent harness's spend is UNKNOWN,
    // not a verified zero — reporting 0 would let a consumer summing
    // usage_today across harnesses silently absorb a missing source.
    const rateLimits = typeof entry.rateLimits === 'function' ? entry.rateLimits(scan.records) : null;
    harnessResults.push({
      id: entry.id,
      available: scan.available,
      root: scan.root,
      sessionsTotal: sessions.size,
      usageToday,
      usage7d,
      rateLimits,
      spendByProject: [...spendByProject.entries()].map(([proj, v]) => ({ project: proj, today: v.today, seven_day: v.sevenDay })),
      records: scan.records,
      fileMtimeBySession: scan.fileMtimeBySession,
    });
  }

  const quotas = resolveQuotas(spoolDir, harnessResults);
  const hooksLines = readSpoolAllLines(path.join(spoolDir, 'hooks.jsonl'));
  const liveSessions = deriveLiveSessions(harnessResults, hooksLines, nowMs);

  saveCache(cacheAbs, cache);

  const spendToday = [];
  const spend7d = [];
  for (const hr of harnessResults) {
    for (const s of hr.spendByProject) {
      spendToday.push({ harness: hr.id, project: s.project, tokens: s.today });
      spend7d.push({ harness: hr.id, project: s.project, tokens: s.seven_day });
    }
  }

  return {
    generatedAt: now.toISOString(),
    watchIntervalSeconds: args.interval,
    harnesses: harnessResults.map((h) => ({
      id: h.id,
      available: h.available,
      root: h.root,
      sessions_total: h.sessionsTotal,
      usage_today: h.usageToday,
      usage_7d: h.usage7d,
    })),
    quotas,
    live_sessions: liveSessions,
    spend: { today: spendToday, seven_day: spend7d },
    degraded,
    scan: { files_total: filesTotal, files_read: filesRead, files_skipped_unchanged: filesSkipped },
    notes,
  };
}

// ---- render ----------------------------------------------------------------

function renderHtml(m) {
  const chips = m.harnesses.map((h) => `<div class="chip ${h.available ? 'chip-up' : 'chip-down'}"><b>${esc(h.id)}</b><span>${h.available ? 'PRESENT' : 'ABSENT'} · ${h.sessions_total} session(s)</span></div>`).join('');

  let quotasHtml;
  if (m.quotas.source === 'tap') {
    const fh = m.quotas.five_hour;
    const sd = m.quotas.seven_day;
    quotasHtml = `<table><thead><tr><th>Window</th><th>Used</th><th>Resets at</th></tr></thead><tbody>`
      + `<tr><td>five_hour</td><td>${fh ? esc(String(fh.used_percent)) + '%' : 'N/A'}</td><td>${fh ? esc(fh.resets_at) : 'N/A'}</td></tr>`
      + `<tr><td>seven_day</td><td>${sd ? esc(String(sd.used_percent)) + '%' : 'N/A'}</td><td>${sd ? esc(sd.resets_at) : 'N/A'}</td></tr>`
      + `</tbody></table>`;
  } else if (m.quotas.source && m.quotas.source.startsWith('session:')) {
    const harness = m.quotas.source.slice('session:'.length);
    const p = m.quotas.primary || {};
    quotasHtml = `<p>Attributed to <b>${esc(harness)}</b> (server-authoritative, in-session): used ${naEsc(p.used_percent)}%, window ${naEsc(p.window_minutes)}m, resets at ${naEsc(p.resets_at)}.</p>`;
  } else {
    quotasHtml = `<p class="skip">SKIP — ${esc(m.quotas.skip.reason)}. Install: ${esc(m.quotas.skip.install)}</p>`;
  }

  const sessionRows = m.live_sessions.map((s) => `<tr><td>${esc(s.harness)}</td><td>${esc(s.project)}</td><td>${esc(s.sessionId)}</td><td>${esc(s.state)}</td></tr>`).join('');

  const spendRows = (rows) => rows.map((r) => `<tr><td>${esc(r.harness)}</td><td>${esc(r.project)}</td><td>${na(r.tokens)}</td></tr>`).join('');

  const degradedRows = m.degraded.map((d) => `<li><b>${esc(d.source)}</b> — ${esc(d.reason)}</li>`).join('');
  const skipHtml = m.quotas.skip ? `<li><b>quotas</b> — ${esc(m.quotas.skip.reason)}. Install: ${esc(m.quotas.skip.install)}</li>` : '';

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="${m.watchIntervalSeconds}">
<title>Live Status Dashboard</title>
<style>
  :root { color-scheme: light dark; --fg:#1c1c1c; --bg:#fff; --muted:#6b6b6b; --line:#e3e3e3; --accent:#0b62d6; --card:#f7f7f8; --up:#137333; --down:#9a3b3b; }
  @media (prefers-color-scheme: dark) { :root { --fg:#e8e8e8; --bg:#161616; --muted:#9a9a9a; --line:#333; --accent:#6fb0ff; --card:#1f1f1f; --up:#7bd88f; --down:#e08a8a; } }
  :root[data-theme="dark"] { --fg:#e8e8e8; --bg:#161616; --muted:#9a9a9a; --line:#333; --accent:#6fb0ff; --card:#1f1f1f; --up:#7bd88f; --down:#e08a8a; }
  :root[data-theme="light"] { --fg:#1c1c1c; --bg:#fff; --muted:#6b6b6b; --line:#e3e3e3; --accent:#0b62d6; --card:#f7f7f8; --up:#137333; --down:#9a3b3b; }
  body { margin:0 auto; max-width:64rem; padding:2rem 1.25rem 4rem; font:16px/1.55 system-ui, sans-serif; color:var(--fg); background:var(--bg); }
  h1 { font-size:1.6rem; margin-bottom:.25rem; }
  h2 { font-size:1.15rem; border-bottom:1px solid var(--line); padding-bottom:.3rem; margin-top:2.2rem; }
  .meta { color:var(--muted); font-size:.85rem; }
  .chips { display:flex; gap:.75rem; flex-wrap:wrap; margin:1rem 0; }
  .chip { background:var(--card); border:1px solid var(--line); border-radius:.5rem; padding:.5rem .9rem; min-width:8rem; }
  .chip b { display:block; }
  .chip span { color:var(--muted); font-size:.8rem; }
  .chip-up b { color:var(--up); }
  .chip-down b { color:var(--down); }
  table { border-collapse:collapse; width:100%; font-size:.9rem; margin:.4rem 0; }
  th, td { border-bottom:1px solid var(--line); padding:.35rem .5rem; text-align:left; }
  .scroll { overflow-x:auto; }
  .skip { color:var(--down); }
  .degraded li { color:var(--muted); font-size:.9rem; }
</style>
</head>
<body>
<h1>Live Status Dashboard</h1>
<p class="meta">Generated ${esc(m.generatedAt)} · zero-token, zero-network, node stdlib only · regenerate with <code>node .aai/scripts/generate-live-status.mjs</code> or <code>bash .aai/scripts/aai-live.sh --watch</code></p>

<section>
<h2>Harness availability</h2>
<div class="chips">${chips}</div>
</section>

<section>
<h2>Official quotas</h2>
${quotasHtml}
</section>

<section>
<h2>Live sessions</h2>
<div class="scroll"><table><thead><tr><th>Harness</th><th>Project</th><th>Session</th><th>State</th></tr></thead><tbody>${sessionRows}</tbody></table></div>
</section>

<section>
<h2>Spend today</h2>
<div class="scroll"><table><thead><tr><th>Harness</th><th>Project</th><th>Tokens</th></tr></thead><tbody>${spendRows(m.spend.today)}</tbody></table></div>
</section>

<section>
<h2>Spend 7d</h2>
<div class="scroll"><table><thead><tr><th>Harness</th><th>Project</th><th>Tokens</th></tr></thead><tbody>${spendRows(m.spend.seven_day)}</tbody></table></div>
</section>

<section>
<h2>SKIP — degraded sources</h2>
<ul class="degraded">${degradedRows}${skipHtml}</ul>
</section>
</body>
</html>
`;
}

// ---- main ----------------------------------------------------------------

function runOnce(args) {
  const model = buildModel(args);
  const dataPath = path.resolve(ROOT, path.join(path.dirname(args.outputPath), 'live-status-data.json'));
  fs.mkdirSync(path.dirname(dataPath), { recursive: true });
  fs.writeFileSync(dataPath, `${JSON.stringify(model, (k, v) => (v instanceof Map ? undefined : v), 2)}\n`);
  if (!args.dataOnly) {
    const htmlPath = path.resolve(ROOT, args.outputPath);
    fs.mkdirSync(path.dirname(htmlPath), { recursive: true });
    fs.writeFileSync(htmlPath, renderHtml(model));
  }
  return { model, dataPath, htmlPath: args.dataOnly ? null : path.resolve(ROOT, args.outputPath) };
}

function main() {
  const args = parseArgs(process.argv);
  const { dataPath, htmlPath } = runOnce(args);
  if (htmlPath) console.log(`- ${path.relative(ROOT, htmlPath)}`);
  console.log(`- ${path.relative(ROOT, dataPath)}`);

  if (!args.watch) return;

  let stopped = false;
  const timer = setInterval(() => {
    if (stopped) return;
    try {
      // A fresh clock each tick unless --now pinned it (deterministic tests).
      runOnce({ ...args, now: args.now });
    } catch {
      // Watch mode must never crash the sidecar process on a transient error.
    }
  }, Math.max(1, args.interval) * 1000);
  // Deliberately NOT unref()'d: this ref'd timer is what keeps the sidecar
  // process alive between ticks — watch mode's entire point is to block
  // until Ctrl+C (Spec-AC-09), not exit the instant main() returns.

  const shutdown = () => {
    if (stopped) return;
    stopped = true;
    clearInterval(timer);
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

// B1 fix (validation blocker): comparing path.resolve(process.argv[1]) (raw)
// against path.resolve(new URL(import.meta.url).pathname) (percent-encoded)
// never matches once the path contains a space or other URL-encoded
// character — a silent exit-0 no-op, and unconditionally broken on Windows
// drive-letter paths. Adopt the proven idiom from generate-dashboard.mjs:370
// — normalize both sides to a file:// URL string instead of comparing a
// decoded path against an encoded one.
const isMain = Boolean(process.argv[1])
  && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) main();

export { buildModel, renderHtml, parseArgs, accumulate };
