#!/usr/bin/env node
// metrics-report.mjs — byte-deterministic METRICS_REPORT (CHANGE-0009 D7).
//
// Reads docs/ai/METRICS.jsonl (+ PRICING.yaml to fill null cost_usd where both
// token counts are known — the SAME lookup_rules resolver flush uses, from
// lib/pricing.mjs) and writes the exact METRICS_REPORT.prompt.md markdown
// (Per Work Item / Totals / Per Model Breakdown / Per-Strategy Reliability)
// to stdout. The reliability section (SPEC-0032-spec-truth-scoring) groups entries
// by their flush-recorded `strategy` (lexicographic; no string -> 'n/a') and
// aggregates the `reliability` object; ledger lines predating the field
// contribute 'n/a' stats — old lines are never reinterpreted.
//
// Determinism contract (AC-004, golden-tested): no file writes, no clock, no
// locale — fixed toFixed(2) USD, leverage one decimal + 'x', rows in ledger
// order, per-model table sorted lexicographically by model_id, `~` prefix on
// partial costs (some runs had null token data), 'n/a' when no run in the
// group has a computable value, "No metrics recorded yet." on an empty or
// comment-only ledger. Identical input bytes -> identical output bytes.
//
// Flags: --metrics <path> (default docs/ai/METRICS.jsonl),
//        --pricing <path> (default .aai/system/PRICING.yaml),
//        --by-effort [--split <YYYY-MM-DD>] (spec-model-effort-routing D-REPORT:
//        prints ONLY the per-role / requested-effort table, plus Before/From/
//        Delta tables with --split; without --by-effort the output is unchanged).
// Exit codes: 0 success (incl. the empty ledger), 2 usage,
//             1 unreadable/corrupt ledger line (named line number).

import fs from 'node:fs';
import path from 'node:path';
import { runCostUsd } from './lib/pricing.mjs';
import { loadCostPricing } from './lib/project-config.mjs';
import { extractUsageTotal } from './lib/usage-note.mjs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

function fail(msg, code = 2) {
  console.error(`metrics-report: ${msg}`);
  exit(code);
}

function parseArgs(argv) {
  const opts = { metrics: 'docs/ai/METRICS.jsonl', pricing: '.aai/system/PRICING.yaml' };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--by-effort') {
      opts.byEffort = true;
    } else if (tok === '--metrics' || tok === '--pricing' || tok === '--split') {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) fail(`${tok} requires a value`);
      opts[tok.slice(2)] = v;
      i += 1;
    } else {
      fail(`unknown flag "${tok}" (valid: --metrics --pricing --by-effort --split)`);
    }
  }
  if (opts.split !== undefined) {
    if (!opts.byEffort) fail('--split requires --by-effort');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(opts.split)) fail(`--split must be YYYY-MM-DD (got "${opts.split}")`);
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

// Spec-AC-02/03 (token-economics-end-to-end): sum of the canonical
// usage_total_tokens=<N> marker across `runs`, via the SAME shared
// lib/usage-note.mjs extractUsageTotal metrics-flush classifies with — a
// malformed value or a prefixed key never counts (extractUsageTotal returns
// null for both). 'n/a' when NO run in the group carries a valid marker.
// TOKENS ONLY — this is never converted to a USD figure (the marker carries
// no in/out split to price).
function undecomposedTokenCell(runs) {
  let sum = 0;
  let any = false;
  for (const r of runs) {
    const t = extractUsageTotal(r.note);
    if (t !== null) {
      sum += t;
      any = true;
    }
  }
  return any ? String(sum) : 'n/a';
}

// spec-model-effort-routing D-REPORT: --by-effort. Rows group by role (any
// " (...)" suffix removed) and requested_effort ('unset' when absent), sorted
// by role then low < medium < high < unset. Medians are rounded to a whole token.
const EFFORT_ORDER = ['low', 'medium', 'high', 'unset'];
const roleBase = r => (typeof r.role === 'string' && r.role !== '' ? r.role.replace(/ \(.*\)$/, '') : 'unknown');
const effortOf = r => (typeof r.requested_effort === 'string' && r.requested_effort !== '' ? r.requested_effort : 'unset');

function medianOf(nums) {
  if (nums.length === 0) return null;
  const a = [...nums].sort((x, y) => x - y);
  const m = a.length >> 1;
  return a.length % 2 === 1 ? a[m] : Math.round((a[m - 1] + a[m]) / 2);
}
const totalsOf = runs => runs.map(r => r.tokens_total).filter(t => typeof t === 'number');
const sumNum = (runs, key) => runs.reduce((a, r) => a + (typeof r[key] === 'number' ? r[key] : 0), 0);

function effortTable(title, runs) {
  const out = [title,
    '| role | effort | runs | runs with tokens_total | sum tokens_total | median tokens_total | sum cost USD | sum cache_read | sum cache_creation | runs with cache |',
    '|------|--------|------|------------------------|------------------|---------------------|--------------|----------------|--------------------|-----------------|'];
  const groups = new Map();
  for (const r of runs) {
    const key = `${roleBase(r)}\u0000${effortOf(r)}`;
    if (!groups.has(key)) groups.set(key, { role: roleBase(r), effort: effortOf(r), runs: [] });
    groups.get(key).runs.push(r);
  }
  const rows = [...groups.values()].sort((a, b) => (a.role < b.role ? -1 : a.role > b.role ? 1 : 0)
    || EFFORT_ORDER.indexOf(a.effort) - EFFORT_ORDER.indexOf(b.effort));
  for (const g of rows) {
    const t = totalsOf(g.runs);
    const med = medianOf(t);
    const withCache = g.runs.filter(r => typeof r.cache_read_tokens === 'number' || typeof r.cache_creation_tokens === 'number').length;
    out.push(`| ${g.role} | ${g.effort} | ${g.runs.length} | ${t.length} | ${t.reduce((a, v) => a + v, 0)} | ${med === null ? 'n/a' : med} | ${costCell(g.runs)} | ${sumNum(g.runs, 'cache_read_tokens')} | ${sumNum(g.runs, 'cache_creation_tokens')} | ${withCache} |`);
  }
  return out;
}

function renderByEffort(entries, split) {
  const runsOf = es => es.flatMap(e => e._runs);
  if (split === undefined) return effortTable('### By role and requested effort', runsOf(entries)).join('\n');
  const before = entries.filter(e => typeof e.date_utc === 'string' && e.date_utc < split);
  const from = entries.filter(e => !(typeof e.date_utc === 'string' && e.date_utc < split));
  const out = [...effortTable(`### Before ${split}`, runsOf(before)), '',
    ...effortTable(`### From ${split}`, runsOf(from)), '',
    '### Delta by role',
    '| role | median tokens_total before | median tokens_total from | change |',
    '|------|----------------------------|--------------------------|--------|'];
  const roles = new Set([...runsOf(before), ...runsOf(from)].map(roleBase));
  for (const role of [...roles].sort()) {
    const b = medianOf(totalsOf(runsOf(before).filter(r => roleBase(r) === role)));
    const f = medianOf(totalsOf(runsOf(from).filter(r => roleBase(r) === role)));
    let change = 'n/a';
    if (b !== null && f !== null && b !== 0) {
      const pct = 100 * (f - b) / b;
      change = `${pct >= 0 ? '+' : ''}${pct.toFixed(1)}%`;
    }
    out.push(`| ${role} | ${b === null ? 'n/a' : b} | ${f === null ? 'n/a' : f} | ${change} |`);
  }
  return out.join('\n');
}

function main() {
  const opts = parseArgs(process.argv);
  const metricsPath = path.resolve(process.cwd(), opts.metrics);
  const pricingPath = path.resolve(process.cwd(), opts.pricing);
  if (!fs.existsSync(metricsPath)) {
    console.log('No metrics recorded yet.');
    exit(0);
  }
  const pricing = loadCostPricing(process.cwd(), pricingPath);
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
    exit(0);
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

  if (opts.byEffort) {
    console.log(renderByEffort(entries, opts.split));
    exit(0);
  }

  const out = [];
  out.push('## AAI Metrics Summary');
  out.push('');
  out.push('### Per Work Item');
  out.push('| ref_id | title | human (min) | agent (sec) | cost USD | cost basis | agent tokens (undecomposed) | leverage | verdict |');
  out.push('|--------|-------|-------------|-------------|----------|------------|------------------------------|----------|---------|');
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
    // telemetry-fields-not-prose Spec-AC-12: the entry-level cost basis this
    // scope's flush writes (`totals.cost_basis`) — 'n/a' on a pre-scope
    // ledger line that never carried the field (never fabricated).
    const costBasis = e.totals && typeof e.totals.cost_basis === 'string' ? e.totals.cost_basis : 'n/a';
    out.push(`| ${e.ref_id ?? 'n/a'} | ${e.title ?? 'n/a'} | ${human} | ${agent} | ${costCell(e._runs)} | ${costBasis} | ${undecomposedTokenCell(e._runs)} | ${leverage} | ${verdict} |`);
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
  out.push('');
  out.push('### Per-Role Token Rollup');
  out.push('| role | agent tokens (undecomposed) |');
  out.push('|------|------------------------------|');
  const byRole = new Map();
  for (const r of allRuns) {
    const role = typeof r.role === 'string' && r.role !== '' ? r.role : 'unknown';
    if (!byRole.has(role)) byRole.set(role, []);
    byRole.get(role).push(r);
  }
  for (const role of [...byRole.keys()].sort()) {
    out.push(`| ${role} | ${undecomposedTokenCell(byRole.get(role))} |`);
  }
  out.push('');
  out.push('Note: undecomposed tokens are display-only — never converted to a USD figure (the marker carries no in/out split to price).');
  out.push('');
  out.push('### Per-Strategy Reliability');
  out.push('| strategy | items | first-pass clean | avg validation fails | avg review fails | avg remediations | basis |');
  out.push('|----------|-------|------------------|----------------------|------------------|------------------|-------|');
  const byStrategy = new Map();
  for (const e of entries) {
    const key = typeof e.strategy === 'string' && e.strategy !== '' ? e.strategy : 'n/a';
    if (!byStrategy.has(key)) byStrategy.set(key, []);
    byStrategy.get(key).push(e);
  }
  // The flush-recorded reliability object, or null on pre-truth-scoring lines.
  const relOf = e => (e.reliability && typeof e.reliability === 'object' && !Array.isArray(e.reliability) ? e.reliability : null);
  const avgCell = (group, field) => {
    const vals = group.map(relOf).filter(r => r && typeof r[field] === 'number').map(r => r[field]);
    if (vals.length === 0) return 'n/a';
    return (vals.reduce((a, v) => a + v, 0) / vals.length).toFixed(1);
  };
  // telemetry-fields-not-prose Spec-AC-12: the distinct `reliability.basis`
  // values across the group's entries — 'n/a' when no entry in the group
  // carries the field (a pre-scope ledger line), the single value when every
  // entry agrees, else 'mixed'.
  const basisCell = group => {
    const bases = new Set(group.map(relOf).filter(r => r && typeof r.basis === 'string').map(r => r.basis));
    if (bases.size === 0) return 'n/a';
    if (bases.size > 1) return 'mixed';
    return [...bases][0];
  };
  for (const key of [...byStrategy.keys()].sort()) {
    const group = byStrategy.get(key);
    const flagged = group.map(relOf).filter(r => r && typeof r.first_pass_clean === 'boolean');
    const clean = flagged.filter(r => r.first_pass_clean === true).length;
    const fpc = flagged.length === 0 ? 'n/a' : `${clean}/${flagged.length} (${(100 * clean / flagged.length).toFixed(0)}%)`;
    out.push(`| ${key} | ${group.length} | ${fpc} | ${avgCell(group, 'validation_fails')} | ${avgCell(group, 'review_fails')} | ${avgCell(group, 'remediation_runs')} | ${basisCell(group)} |`);
  }
  out.push('');
  out.push('Note: reliability derives from runs recorded at flush; older ledger lines without it render n/a.');

  // Prompt versions (prompt-hash-telemetry Spec-AC-04): per-role grouping of
  // run counts by short 12-hex prompt_hash — ONLY for roles carrying more
  // than one DISTINCT hash (a role with at most one hash never changed its
  // effective instructions across its recorded runs, so it is not
  // interesting here). Emitted ADDITIVELY: when no role qualifies, no
  // section header is printed at all — the rest of the report is unchanged.
  const byRolePromptHash = new Map();
  for (const r of allRuns) {
    if (typeof r.prompt_hash !== 'string') continue;
    const role = typeof r.role === 'string' && r.role !== '' ? r.role : 'unknown';
    const short = r.prompt_hash.slice(0, 12);
    if (!byRolePromptHash.has(role)) byRolePromptHash.set(role, new Map());
    const hashes = byRolePromptHash.get(role);
    hashes.set(short, (hashes.get(short) ?? 0) + 1);
  }
  const promptRows = [];
  for (const role of [...byRolePromptHash.keys()].sort()) {
    const hashes = byRolePromptHash.get(role);
    if (hashes.size <= 1) continue;   // single version per role: nothing to compare
    for (const hash of [...hashes.keys()].sort()) {
      promptRows.push(`| ${role} | ${hash} | ${hashes.get(hash)} |`);
    }
  }
  if (promptRows.length > 0) {
    out.push('');
    out.push('### Prompt versions');
    out.push('| role | prompt_hash | runs |');
    out.push('|------|-------------|------|');
    out.push(...promptRows);
    out.push('');
    out.push('Note: a role appears here only when its recorded runs carry more than one distinct prompt_hash (its effective instructions changed between runs).');
    out.push('');
  }
  console.log(out.join('\n'));
  exit(0);
}

runMain(() => main());