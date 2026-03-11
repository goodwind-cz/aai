#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

function parseArgs(argv) {
  const args = {
    metricsPath: 'docs/ai/METRICS.jsonl',
    outputPath: 'docs/ai/dashboard.html',
    from: null,
    to: null,
    skill: null,
    dataOnly: false
  };

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
    if (token === '--metrics' && argv[i + 1]) {
      args.metricsPath = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === '--output' && argv[i + 1]) {
      args.outputPath = argv[i + 1];
      i += 1;
      continue;
    }

    if (!token.startsWith('-') && args.metricsPath === 'docs/ai/METRICS.jsonl') {
      args.metricsPath = token;
      continue;
    }
    if (!token.startsWith('-') && args.outputPath === 'docs/ai/dashboard.html') {
      args.outputPath = token;
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
  return {
    timestamp,
    skill: entry.skill || entry.operation || 'unknown',
    operation: entry.operation || entry.skill || 'unknown',
    status: entry.status || 'success',
    durationMs: Number(entry.duration_ms) || 0,
    tokensIn: Number(entry.tokens?.input) || 0,
    tokensOut: Number(entry.tokens?.output) || 0,
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
    const tokensIn = Number(run.tokens_in);
    const tokensOut = Number(run.tokens_out);
    const durationSeconds = Number(run.duration_seconds);

    return {
      timestamp,
      skill: role,
      operation: role,
      status,
      durationMs: Number.isFinite(durationSeconds) ? Math.round(durationSeconds * 1000) : 0,
      tokensIn: Number.isFinite(tokensIn) ? tokensIn : 0,
      tokensOut: Number.isFinite(tokensOut) ? tokensOut : 0,
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
  const totalTokens = operations.reduce((sum, op) => sum + op.tokensIn + op.tokensOut, 0);
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
    if (!grouped[day]) grouped[day] = { input: 0, output: 0 };
    grouped[day].input += op.tokensIn;
    grouped[day].output += op.tokensOut;
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
    item.tokens += op.tokensIn + op.tokensOut;
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
    const payload = JSON.stringify(data)
      .replace(/</g, '\\u003c')
      .replace(/`/g, '\\`')
      .replace(/\\/g, '\\\\');
    const html = template.replace('{{METRICS_DATA}}', payload);

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
