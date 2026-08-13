#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
// Canonical usage_total_tokens=<N> note-marker grammar — IMPORTED, never
// forked (SPEC-0089 single-source contract; test_120 in test-aai-metrics.sh
// fails if the raw regex literal exists in more than one source file).
import { extractUsageTotal } from './lib/usage-note.mjs';

// finiteNum(v) -> v when it is a real recorded number, else null. JSON null
// (the real ledger's tokens_in/tokens_out on almost every run) must NOT
// count as a recorded 0 — Number(null) === 0 would silently shadow the
// note-carried total (CHANGE-0140 D3).
function finiteNum(v) {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

// D3 per-run token precedence (never double-count, never fabricate):
// explicit finite tokens_in/tokens_out win; otherwise the note marker's
// undecomposed TOTAL (never split into in/out); otherwise no contribution.
// Returns { total, hasSignal } — hasSignal distinguishes "recorded as 0"
// from "nothing recorded at all" (drives the token panel's no-data state).
function runTokenTotal(tokensIn, tokensOut, note) {
  if (tokensIn !== null || tokensOut !== null) {
    return { total: (tokensIn ?? 0) + (tokensOut ?? 0), hasSignal: true };
  }
  const noteTotal = extractUsageTotal(note);
  if (noteTotal !== null) return { total: noteTotal, hasSignal: true };
  return { total: 0, hasSignal: false };
}

function parseArgs(argv) {
  const args = {
    metricsPath: 'docs/ai/METRICS.jsonl',
    outputPath: 'docs/ai/dashboard.html',
    from: null,
    to: null,
    skill: null,
    dataOnly: false
  };
  // Positional slots track consumption explicitly: comparing against the
  // default STRING mis-routes the 2nd positional into metricsPath whenever
  // the 1st equals the default value (silently overwriting the real
  // docs/ai/dashboard.html; skill-sweep 2026-07-27).
  let metricsSet = false;
  let outputSet = false;

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--from' && argv[i + 1]) {
      args.from = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === '--to' && argv[i + 1]) {
      args.to = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === '--skill' && argv[i + 1]) {
      args.skill = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === '--data-only') {
      args.dataOnly = true;
      continue;
    }
    if (token === '--metrics' || token === '--output') {
      if (!argv[i + 1]) {
        console.error(`${token} requires a value`);
        process.exit(2);
      }
      if (token === '--metrics') { args.metricsPath = argv[i + 1]; metricsSet = true; }
      else { args.outputPath = argv[i + 1]; outputSet = true; }
      i += 1;
      continue;
    }
    // Unknown flags must never silently proceed with defaults — that is the
    // exact class of footgun the positional fix addresses (a typo'd --ouput
    // would otherwise overwrite docs/ai/dashboard.html).
    if (token.startsWith('-')) {
      console.error(`unknown flag: ${token}`);
      console.error('Usage: generate-dashboard.mjs [--metrics <path>] [--output <path>] [--from D] [--to D] [--skill S] [--data-only]');
      process.exit(2);
    }

    if (!token.startsWith('-') && !metricsSet) {
      args.metricsPath = token;
      metricsSet = true;
      continue;
    }
    if (!token.startsWith('-') && !outputSet) {
      args.outputPath = token;
      outputSet = true;
      continue;
    }
  }

  return args;
}

function parseJsonl(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'));

  const entries = [];
  for (const line of lines) {
    try {
      entries.push(JSON.parse(line));
    } catch (error) {
      throw new Error(`Invalid JSONL line: ${line.slice(0, 120)}...`);
    }
  }
  return {
    entries,
    looksLikeLedger: /agent_runs|metrics ledger/i.test(content)
  };
}

function toIsoDate(value) {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function normalizeOperationRecord(entry) {
  const timestamp = toIsoDate(entry.timestamp) || toIsoDate(entry.date_utc) || null;
  const tokensIn = finiteNum(entry.tokens?.input);
  const tokensOut = finiteNum(entry.tokens?.output);
  const tokens = runTokenTotal(tokensIn, tokensOut, entry.note);
  return {
    timestamp,
    skill: entry.skill || entry.operation || 'unknown',
    operation: entry.operation || entry.skill || 'unknown',
    status: entry.status || 'success',
    durationMs: Number(entry.duration_ms) || 0,
    tokensIn: tokensIn ?? 0,
    tokensOut: tokensOut ?? 0,
    tokensTotal: tokens.total,
    hasTokenSignal: tokens.hasSignal,
    metadata: entry.metadata || {}
  };
}

function normalizeLedgerEntry(entry) {
  const runs = Array.isArray(entry.agent_runs) ? entry.agent_runs : [];
  const verdict = String(entry.verdict || '').toUpperCase();
  const status = verdict === 'PASS' ? 'success' : verdict === 'FAIL' ? 'error' : verdict === 'CANCELLED' ? 'cancelled' : 'success';

  return runs.map((run, index) => {
    const timestamp = toIsoDate(run.started_utc) || toIsoDate(run.ended_utc) || toIsoDate(entry.date_utc) || null;
    const role = run.role || 'Unknown';
    const tokensIn = finiteNum(run.tokens_in);
    const tokensOut = finiteNum(run.tokens_out);
    // Real agent_runs almost always carry tokens_in/out: null with usage as
    // an undecomposed usage_total_tokens=<N> note (SUBAGENT_PROTOCOL
    // capture convention) — parsed under the D3 precedence rule.
    const tokens = runTokenTotal(tokensIn, tokensOut, run.note);
    const durationSeconds = Number(run.duration_seconds);

    return {
      timestamp,
      skill: role,
      operation: role,
      status,
      durationMs: Number.isFinite(durationSeconds) ? Math.round(durationSeconds * 1000) : 0,
      tokensIn: tokensIn ?? 0,
      tokensOut: tokensOut ?? 0,
      tokensTotal: tokens.total,
      hasTokenSignal: tokens.hasSignal,
      metadata: {
        ref_id: entry.ref_id,
        title: entry.title,
        model_id: run.model_id || null,
        run_index: index + 1,
        worktree: run.worktree || entry.worktree || null,
        verdict
      }
    };
  });
}

function normalizeEntries(entries) {
  const operations = [];
  let workItemCount = 0;

  for (const entry of entries) {
    if (entry && Array.isArray(entry.agent_runs)) {
      workItemCount += 1;
      operations.push(...normalizeLedgerEntry(entry));
      continue;
    }
    if (entry && (entry.skill || entry.operation || entry.timestamp || entry.tokens || entry.duration_ms)) {
      operations.push(normalizeOperationRecord(entry));
    }
  }

  return {
    operations,
    workItemCount
  };
}

function toDateOnly(isoDate) {
  if (!isoDate) return null;
  return isoDate.split('T')[0];
}

function filterOperations(operations, { from, to, skill }) {
  const fromDate = from ? new Date(`${from}T00:00:00.000Z`) : null;
  const toDate = to ? new Date(`${to}T23:59:59.999Z`) : null;
  const roleFilter = skill ? skill.toLowerCase() : null;

  return operations.filter((op) => {
    if (!op.timestamp) return false;
    const ts = new Date(op.timestamp);
    if (Number.isNaN(ts.getTime())) return false;
    if (fromDate && ts < fromDate) return false;
    if (toDate && ts > toDate) return false;
    if (roleFilter && !String(op.skill).toLowerCase().includes(roleFilter)) return false;
    return true;
  });
}

function calculateSummary(operations, workItemCount) {
  const total = operations.length;
  const totalTokens = operations.reduce((sum, op) => sum + op.tokensTotal, 0);
  const totalDuration = operations.reduce((sum, op) => sum + op.durationMs, 0);
  const successes = operations.filter((op) => op.status === 'success').length;
  const worktrees = new Set(operations.map((op) => op.metadata?.worktree).filter(Boolean));
  const publishes = operations.filter((op) => {
    const name = String(op.skill || '').toLowerCase();
    return name.includes('share') || name.includes('publish');
  }).length;

  const timestamps = operations.map((op) => op.timestamp).filter(Boolean).sort();
  const period = timestamps.length
    ? `${toDateOnly(timestamps[0])} to ${toDateOnly(timestamps[timestamps.length - 1])}`
    : 'No data';

  return {
    total,
    totalTokens,
    avgDuration: total > 0 ? Math.round(totalDuration / total) : 0,
    successRate: total > 0 ? ((successes / total) * 100).toFixed(1) : '0.0',
    activeWorktrees: worktrees.size,
    publishes,
    workItems: workItemCount,
    period
  };
}

function groupTokensByDay(operations) {
  const grouped = {};
  for (const op of operations) {
    const day = toDateOnly(op.timestamp);
    if (!day) continue;
    // `total` is ADDITIVE (CHANGE-0140): input/output carry only explicit
    // decomposed fields; a note marker's undecomposed total lands ONLY in
    // `total` — it is never fabricated into an in/out split.
    if (!grouped[day]) grouped[day] = { input: 0, output: 0, total: 0 };
    grouped[day].input += op.tokensIn;
    grouped[day].output += op.tokensOut;
    grouped[day].total += op.tokensTotal;
  }
  return grouped;
}

function calculateSkillStats(operations) {
  const map = new Map();
  for (const op of operations) {
    const key = String(op.skill || 'Unknown');
    if (!map.has(key)) {
      map.set(key, { count: 0, tokens: 0, durationMs: 0, success: 0 });
    }
    const item = map.get(key);
    item.count += 1;
    item.tokens += op.tokensTotal;
    item.durationMs += op.durationMs;
    if (op.status === 'success') item.success += 1;
  }

  return Array.from(map.entries())
    .map(([name, item]) => ({
      name,
      count: item.count,
      avgTokens: item.count > 0 ? Math.round(item.tokens / item.count) : 0,
      avgDuration: item.count > 0 ? (item.durationMs / item.count / 1000).toFixed(1) : '0.0',
      successRate: item.count > 0 ? ((item.success / item.count) * 100).toFixed(1) : '0.0'
    }))
    .sort((a, b) => b.count - a.count);
}

function calculateRolePhaseStats(operations) {
  const phaseMap = {
    red: ['red'],
    green: ['green'],
    refactor: ['refactor']
  };
  const buckets = { red: [], green: [], refactor: [] };

  for (const op of operations) {
    const text = `${op.skill} ${op.operation}`.toLowerCase();
    for (const [phase, keys] of Object.entries(phaseMap)) {
      if (keys.some((k) => text.includes(k))) {
        buckets[phase].push(op.durationMs / 1000);
      }
    }
  }

  const hasAny = Object.values(buckets).some((arr) => arr.length > 0);
  if (!hasAny) return null;

  const avg = (arr) => (arr.length ? Number((arr.reduce((a, b) => a + b, 0) / arr.length).toFixed(1)) : 0);
  return {
    red: avg(buckets.red),
    green: avg(buckets.green),
    refactor: avg(buckets.refactor)
  };
}

function calculateWorktreeStats(operations) {
  const stats = {};
  for (const op of operations) {
    const wt = op.metadata?.worktree;
    if (!wt) continue;
    stats[wt] = (stats[wt] || 0) + 1;
  }
  return Object.keys(stats).length > 0 ? stats : null;
}

function calculatePublishStats(operations) {
  const stats = {};
  for (const op of operations) {
    const name = String(op.skill || '').toLowerCase();
    if (!name.includes('share') && !name.includes('publish')) continue;
    const day = toDateOnly(op.timestamp);
    if (!day) continue;
    stats[day] = (stats[day] || 0) + 1;
  }
  return Object.keys(stats).length > 0 ? stats : null;
}

function buildData(entries, args, sourceHints = {}) {
  const normalized = normalizeEntries(entries);
  const operations = filterOperations(normalized.operations, args);
  const schema = normalized.workItemCount > 0 || sourceHints.looksLikeLedger ? 'work-item-ledger' : 'operation-log';

  return {
    summary: calculateSummary(operations, normalized.workItemCount),
    tokensByTime: groupTokensByDay(operations),
    skillStats: calculateSkillStats(operations),
    tddStats: calculateRolePhaseStats(operations),
    worktreeStats: calculateWorktreeStats(operations),
    publishStats: calculatePublishStats(operations),
    // ADDITIVE (CHANGE-0140 D4): false only when NO operation in the
    // filtered dataset carries any token signal (explicit fields or a valid
    // note marker) — drives the token panel's named no-data state, so an
    // absent signal never renders as a flat zero line.
    hasTokenSignal: operations.some((op) => op.hasTokenSignal),
    generatedAt: new Date().toISOString(),
    source: {
      entries: entries.length,
      operations: operations.length,
      schema
    },
    filters: {
      from: args.from,
      to: args.to,
      skill: args.skill
    }
  };
}

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function generateDashboard({ metricsPath, outputPath, from, to, skill, dataOnly }) {
  if (!fs.existsSync(metricsPath)) {
    throw new Error(`METRICS file not found: ${metricsPath}`);
  }

  const parsed = parseJsonl(metricsPath);
  const args = { from, to, skill };
  const data = buildData(parsed.entries, args, { looksLikeLedger: parsed.looksLikeLedger });

  const dataPath = path.join(path.dirname(outputPath), 'dashboard-data.json');
  ensureDir(dataPath);
  fs.writeFileSync(dataPath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');

  if (!dataOnly) {
    const templatePath = 'docs/dashboard-template.html';
    if (!fs.existsSync(templatePath)) {
      throw new Error(`Template not found: ${templatePath}`);
    }

    const template = fs.readFileSync(templatePath, 'utf8');
    // Template-literal embed hardening (CHANGE-0141 D2). Order matters:
    // backslash-doubling MUST run FIRST — the old order (`<`, backtick, then
    // backslash) re-exposed the backslash added by the backtick escape
    // (` -> \` -> \\` = escaped backslash + LIVE backtick, SyntaxError, page
    // dead). Then backtick and `${` (never escaped before) are neutralized,
    // and `<` LAST with a SINGLE post-doubling backslash: the template
    // literal decodes the backslash-u003c escape back to `<` (keeping
    // "</script>" out of the HTML byte stream) while JSON.parse sees the
    // raw character.
    const payload = JSON.stringify(data)
      .replace(/\\/g, '\\\\')
      .replace(/`/g, '\\`')
      .replace(/\$\{/g, '\\${')
      .replace(/</g, '\\u003c');
    // Named no-data state (CHANGE-0140 D4): a chart section whose source
    // stat is absent across the WHOLE dataset renders a deterministic,
    // greppable placeholder in place of its canvas — never a bare empty
    // axis. Sections with data keep their canvas (fixture-proven both ways).
    const panelMarkup = (panel, canvasId, hasData) => (hasData
      ? `<canvas id="${canvasId}"></canvas>`
      : `<div class="no-data" data-panel="${panel}">No data recorded in this dataset</div>`);
    // Function-replacement substitution (CHANGE-0141 D2): a FUNCTION return
    // value is inserted verbatim, disarming String.replace's `$&`/`$\``/`$'`/
    // `$n` replacement patterns in the payload. The four PANEL substitutions
    // take the same form for uniformity (generator-owned constant markup;
    // hygiene, not a fix).
    // Substitution ORDER matters (review NB-2): the payload is the only
    // attacker-influenced string here, so it goes LAST — a payload-borne
    // literal `{{PANEL_*}}` can then never be re-substituted, whatever a
    // future template edit does to placeholder positions. (Today it is
    // inert anyway because every panel placeholder sits above the script
    // block, but that is a template layout accident, not an invariant.)
    const html = template
      .replace('{{PANEL_TOKENS}}', () => panelMarkup('tokens', 'tokenChart', data.hasTokenSignal))
      .replace('{{PANEL_TDD}}', () => panelMarkup('tdd', 'tddChart', data.tddStats !== null))
      .replace('{{PANEL_WORKTREE}}', () => panelMarkup('worktree', 'worktreeChart', data.worktreeStats !== null))
      .replace('{{PANEL_PUBLISH}}', () => panelMarkup('publish', 'publishChart', data.publishStats !== null))
      .replace('{{METRICS_DATA}}', () => payload);

    ensureDir(outputPath);
    fs.writeFileSync(outputPath, html, 'utf8');
  }

  return data;
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  try {
    const args = parseArgs(process.argv);
    const data = generateDashboard(args);

    console.log('Dashboard generation complete');
    console.log(`Schema detected: ${data.source.schema}`);
    console.log(`Work items parsed: ${data.summary.workItems}`);
    console.log(`Operations aggregated: ${data.summary.total}`);
    console.log(`Total tokens: ${data.summary.totalTokens}`);
    console.log(`Success rate: ${data.summary.successRate}%`);
    console.log(`Period: ${data.summary.period}`);
    console.log('Output files:');
    console.log(`- ${path.join(path.dirname(args.outputPath), 'dashboard-data.json')}`);
    if (!args.dataOnly) {
      console.log(`- ${args.outputPath}`);
    }
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

export { generateDashboard, parseJsonl, normalizeEntries, buildData };
