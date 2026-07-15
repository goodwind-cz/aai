#!/usr/bin/env node
// metrics-report.mjs — byte-deterministic METRICS_REPORT (CHANGE-0009 D7).
//
// Reads docs/ai/METRICS.jsonl (+ PRICING.yaml to fill null cost_usd where both
// token counts are known — the SAME lookup_rules resolver flush uses, from
// lib/pricing.mjs) and writes the exact METRICS_REPORT.prompt.md markdown
// (Per Work Item / Totals / Per Model Breakdown) to stdout.
//
// Determinism contract (AC-004, golden-tested): no file writes, no clock, no
// locale — fixed toFixed(2) USD, leverage one decimal + 'x', rows in ledger
// order, per-model table sorted lexicographically by model_id, `~` prefix on
// partial costs (some runs had null token data), 'n/a' when no run in the
// group has a computable value, "No metrics recorded yet." on an empty or
// comment-only ledger. Identical input bytes -> identical output bytes.
//
// Flags: --metrics <path> (default docs/ai/METRICS.jsonl),
//        --pricing <path> (default .aai/system/PRICING.yaml).
// Exit codes: 0 success (incl. the empty ledger), 2 usage,
//             1 unreadable/corrupt ledger line (named line number).

import fs from 'node:fs';
import path from 'node:path';
import { loadPricing, runCostUsd } from './lib/pricing.mjs';

function fail(msg, code = 2) {
  console.error(`metrics-report: ${msg}`);
  process.exit(code);
}

function parseArgs(argv) {
  const opts = { metrics: 'docs/ai/METRICS.jsonl', pricing: '.aai/system/PRICING.yaml' };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--metrics' || tok === '--pricing') {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) fail(`${tok} requires a value`);
      opts[tok.slice(2)] = v;
      i += 1;
    } else {
      fail(`unknown flag "${tok}" (valid: --metrics --pricing)`);
    }
  }
  return opts;
}

const usd = n => `$${n.toFixed(2)}`;

// Cost cell for a run group: sum of known costs; `~` when any run's cost is
// null (partial); 'n/a' when NO run has a known cost.
function costCell(runs) {
  const known = runs.filter(r => typeof r._cost === 'number');
  if (known.length === 0) return 'n/a';
  const sum = known.reduce((a, r) => a + r._cost, 0);
  const partial = known.length < runs.length;
  return `${partial ? '~' : ''}${usd(sum)}`;
}

function tokenCell(runs, key) {
  const known = runs.filter(r => typeof r[key] === 'number');
  if (known.length === 0) return 'n/a';
  return String(known.reduce((a, r) => a + r[key], 0));
}

function main() {
  const opts = parseArgs(process.argv);
  const metricsPath = path.resolve(process.cwd(), opts.metrics);
  const pricingPath = path.resolve(process.cwd(), opts.pricing);
  if (!fs.existsSync(metricsPath)) {
    console.log('No metrics recorded yet.');
    process.exit(0);
  }
  const pricing = loadPricing(pricingPath);
  const entries = [];
  const rawLines = fs.readFileSync(metricsPath, 'utf8').split(/\r?\n/);
  for (let i = 0; i < rawLines.length; i += 1) {
    const t = rawLines[i].trim();
    if (t === '' || t.startsWith('#')) continue;
    try {
      entries.push(JSON.parse(t));
    } catch {
      fail(`unreadable ledger line ${i + 1} in ${opts.metrics} — fix or remove it (append-only ledger, one JSON object per line)`, 1);
    }
  }
  if (entries.length === 0) {
    console.log('No metrics recorded yet.');
    process.exit(0);
  }

  // Resolve each run's effective cost ONCE (ledger value, else pricing fill
  // when both tokens are known) — shared by every section below.
  const allRuns = [];
  for (const e of entries) {
    e._runs = Array.isArray(e.agent_runs) ? e.agent_runs : [];
    for (const r of e._runs) {
      r._cost = typeof r.cost_usd === 'number'
        ? r.cost_usd
        : runCostUsd(pricing, r.model_id, typeof r.tokens_in === 'number' ? r.tokens_in : null,
          typeof r.tokens_out === 'number' ? r.tokens_out : null);
      allRuns.push(r);
    }
  }

  const out = [];
  out.push('## AAI Metrics Summary');
  out.push('');
  out.push('### Per Work Item');
  out.push('| ref_id | title | human (min) | agent (sec) | cost USD | leverage | verdict |');
  out.push('|--------|-------|-------------|-------------|----------|----------|---------|');
  let totalHuman = 0;
  let totalAgent = 0;
  let passCount = 0;
  for (const e of entries) {
    const h = e.human_time_minutes ?? {};
    const human = (typeof h.intake === 'number' ? h.intake : 0) + (typeof h.reviews === 'number' ? h.reviews : 0);
    const agent = e._runs.reduce((a, r) => a + (typeof r.duration_seconds === 'number' ? r.duration_seconds : 0), 0);
    const leverage = human > 0 ? `${(agent / (human * 60)).toFixed(1)}x` : 'n/a';
    const verdict = typeof e.verdict === 'string' ? e.verdict : 'n/a';
    if (verdict === 'PASS') passCount += 1;
    totalHuman += human;
    totalAgent += agent;
    out.push(`| ${e.ref_id ?? 'n/a'} | ${e.title ?? 'n/a'} | ${human} | ${agent} | ${costCell(e._runs)} | ${leverage} | ${verdict} |`);
  }
  out.push('');
  out.push('Note: "~" prefix on cost means partial (some runs had null token data).');
  out.push('');
  out.push('### Totals');
  out.push(`- Human time: ${totalHuman} min`);
  out.push(`- Agent time: ${totalAgent} sec (${(totalAgent / 60).toFixed(1)} min)`);
  out.push(`- Total cost: ${costCell(allRuns)}`);
  out.push(`- Average leverage: ${totalHuman > 0 ? `${(totalAgent / (totalHuman * 60)).toFixed(1)}x` : 'n/a'} (agent-seconds per human-second)`);
  out.push(`- Features delivered (PASS): ${passCount}`);
  out.push('');
  out.push('### Per Model Breakdown');
  out.push('| model_id | runs | tokens_in | tokens_out | cost USD |');
  out.push('|----------|------|-----------|------------|----------|');
  const byModel = new Map();
  for (const r of allRuns) {
    const id = typeof r.model_id === 'string' && r.model_id !== '' ? r.model_id : 'unknown';
    if (!byModel.has(id)) byModel.set(id, []);
    byModel.get(id).push(r);
  }
  for (const id of [...byModel.keys()].sort()) {
    const runs = byModel.get(id);
    out.push(`| ${id} | ${runs.length} | ${tokenCell(runs, 'tokens_in')} | ${tokenCell(runs, 'tokens_out')} | ${costCell(runs)} |`);
  }
  console.log(out.join('\n'));
  process.exit(0);
}

main();
