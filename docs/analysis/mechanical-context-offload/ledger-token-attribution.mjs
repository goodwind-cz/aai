#!/usr/bin/env node
// ledger-token-attribution.mjs — one-off measurement script for the
// mechanical-context-offload-to-cheap-tier research spike.
//
// Reads docs/ai/METRICS.jsonl (or a --path snapshot), extracts the only
// token signal that exists in this ledger today — usage_total_tokens=N
// embedded in the free-text `note` field of agent_runs entries — and
// groups it by NORMALIZED role and by NORMALIZED model_id.
//
// Hard constraints this script exists to respect, not paper over:
//   - tokens_in / tokens_out / cost_usd are null on every record. There is
//     NO per-tool-call attribution. This script attributes at run
//     granularity only.
//   - Coverage is partial: not every agent_runs entry carries a usage
//     marker. The no-marker remainder is counted and printed, never
//     silently dropped from either grouping's denominator.
//   - Both grouping axes need normalization (role free-text singletons,
//     model_id "unknown" and harness-suffixed ids like claude-opus-4-8[1m]).
//     The normalization inputs and their remainders are printed so a
//     reviewer can audit what got folded into what.
//
// Node stdlib only, zero dependencies, writes nothing (docs/TECHNOLOGY.md).
//
// Usage:
//   node docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs [--path <file>]

import fs from 'node:fs';
import path from 'node:path';

const DEFAULT_LEDGER_PATH = 'docs/ai/METRICS.jsonl';
const USAGE_MARKER_RE = /usage_total_tokens=(\d+)/g;
const CANONICAL_ROLES = [
  'Planning',
  'Implementation',
  'Validation',
  'Code Review',
  'Remediation',
  'TDD Implementation',
];

function parseArgs(argv) {
  const out = { path: DEFAULT_LEDGER_PATH };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--path') {
      if (i + 1 >= argv.length) {
        console.error('ledger-token-attribution: --path requires a value');
        process.exit(1);
      }
      out.path = argv[i + 1];
      i += 1;
    } else {
      console.error(`ledger-token-attribution: unrecognized argument: ${argv[i]}`);
      process.exit(1);
    }
  }
  return out;
}

// Strip a trailing bracket suffix (e.g. "claude-opus-4-8[1m]" -> "claude-opus-4-8").
// A missing or empty model_id, or the literal string "unknown", folds to "unknown".
function normalizeModelId(modelId) {
  if (!modelId || modelId === 'unknown') return 'unknown';
  return modelId.replace(/\[[^\]]*\]$/, '');
}

// Fold a hand-written free-text role variant ("Remediation (E1 over-kill)")
// onto its canonical prefix ("Remediation") when the text before " (" is one
// of the six canonical role strings. A role that does not fold this way is
// kept verbatim and counted separately as an UNFOLDED remainder — this
// script never silently merges an unrecognized role into a canonical one.
function normalizeRole(role) {
  if (!role) return { normalized: 'unknown', folded: false, unfoldedVariant: false };
  if (CANONICAL_ROLES.includes(role)) {
    return { normalized: role, folded: false, unfoldedVariant: false };
  }
  const prefix = role.split(' (')[0].trim();
  if (CANONICAL_ROLES.includes(prefix)) {
    return { normalized: prefix, folded: true, unfoldedVariant: false };
  }
  return { normalized: role, folded: false, unfoldedVariant: true };
}

function extractUsageTokens(note) {
  if (!note) return { tokens: null, occurrences: 0 };
  const matches = [...note.matchAll(USAGE_MARKER_RE)];
  if (matches.length === 0) return { tokens: null, occurrences: 0 };
  return { tokens: parseInt(matches[0][1], 10), occurrences: matches.length };
}

function readLedgerLines(ledgerPath) {
  let raw;
  try {
    raw = fs.readFileSync(ledgerPath, 'utf8');
  } catch (err) {
    console.error(`ledger-token-attribution: cannot read ${ledgerPath}: ${err.code || err.message}`);
    process.exit(1);
  }
  return raw
    .split('\n')
    .filter((line) => line.trim().startsWith('{'));
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const resolvedPath = path.resolve(process.cwd(), opts.path);

  if (!fs.existsSync(resolvedPath)) {
    console.error(`ledger-token-attribution: no such file: ${resolvedPath}`);
    process.exit(1);
  }

  const lines = readLedgerLines(resolvedPath);

  let workItems = 0;
  let missingRunsField = 0;
  let emptyRunsArrays = 0;
  let agentRuns = 0;
  let withUsageMarker = 0;
  let withoutUsageMarker = 0;
  let multiMarkerRecords = 0;
  let tokensTotal = 0;

  const roleTokens = new Map();
  const roleNoMarker = new Map();
  const modelTokens = new Map();
  const modelNoMarker = new Map();
  let foldedRoleCount = 0;
  const unfoldedRoleVariants = new Set();
  let modelSuffixFoldedCount = 0;
  let modelUnknownCount = 0;

  for (const line of lines) {
    let record;
    try {
      record = JSON.parse(line);
    } catch (err) {
      console.error(`ledger-token-attribution: skipping unparseable line: ${err.message}`);
      continue;
    }
    workItems += 1;

    const runs = record.agent_runs;
    if (runs === undefined || runs === null) {
      missingRunsField += 1;
      continue;
    }
    if (!Array.isArray(runs)) {
      console.error(`ledger-token-attribution: agent_runs is ${typeof runs}, not an array, in record ${record.ref_id ?? `#${workItems}`}; refusing to report a total that silently drops it`);
      process.exit(1);
    }
    if (runs.length === 0) {
      emptyRunsArrays += 1;
      continue;
    }

    for (const run of runs) {
      agentRuns += 1;

      const roleInfo = normalizeRole(run.role);
      if (roleInfo.folded) foldedRoleCount += 1;
      if (roleInfo.unfoldedVariant) unfoldedRoleVariants.add(roleInfo.normalized);
      const role = roleInfo.normalized;

      const rawModel = run.model_id;
      if (/\[[^\]]*\]$/.test(rawModel || '')) modelSuffixFoldedCount += 1;
      if (!rawModel || rawModel === 'unknown') modelUnknownCount += 1;
      const model = normalizeModelId(rawModel);

      const { tokens, occurrences } = extractUsageTokens(run.note);
      if (occurrences > 1) multiMarkerRecords += 1;

      if (tokens === null) {
        withoutUsageMarker += 1;
        roleNoMarker.set(role, (roleNoMarker.get(role) || 0) + 1);
        modelNoMarker.set(model, (modelNoMarker.get(model) || 0) + 1);
        continue;
      }

      withUsageMarker += 1;
      tokensTotal += tokens;
      roleTokens.set(role, (roleTokens.get(role) || 0) + tokens);
      modelTokens.set(model, (modelTokens.get(model) || 0) + tokens);
    }
  }

  const roleSum = [...roleTokens.values()].reduce((a, b) => a + b, 0);
  const modelSum = [...modelTokens.values()].reduce((a, b) => a + b, 0);

  console.log(`snapshot=${resolvedPath}`);
  console.log(`work_items=${workItems} (missing_agent_runs_field=${missingRunsField}, empty_agent_runs_array=${emptyRunsArrays})`);
  console.log(`agent_runs=${agentRuns}`);
  console.log(`with_usage_marker=${withUsageMarker}`);
  console.log(`without_usage_marker=${withoutUsageMarker}`);
  console.log(`tokens_total=${tokensTotal}`);
  console.log(`multi_marker_records=${multiMarkerRecords} (first occurrence taken when a note carries more than one usage_total_tokens= marker)`);
  console.log('');

  console.log('--- tokens by normalized role (marker-bearing runs only) ---');
  for (const [role, tokens] of [...roleTokens.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`role=${role} tokens=${tokens} no_marker_runs=${roleNoMarker.get(role) || 0}`);
  }
  console.log(`role_row_sum=${roleSum} (equals tokens_total: ${roleSum === tokensTotal})`);
  console.log(`role_folded_count=${foldedRoleCount} (free-text role variants folded onto a canonical prefix)`);
  if (unfoldedRoleVariants.size > 0) {
    console.log(`role_unfolded_remainder=${[...unfoldedRoleVariants].join(', ')}`);
  } else {
    console.log('role_unfolded_remainder=none');
  }
  console.log('');

  console.log('--- tokens by normalized model_id (marker-bearing runs only) ---');
  for (const [model, tokens] of [...modelTokens.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`model_id=${model} tokens=${tokens} no_marker_runs=${modelNoMarker.get(model) || 0}`);
  }
  console.log(`model_row_sum=${modelSum} (equals tokens_total: ${modelSum === tokensTotal})`);
  console.log(`model_suffix_folded_count=${modelSuffixFoldedCount} (runs whose raw model_id carried a bracket suffix, e.g. [1m])`);
  console.log(`model_unknown_count=${modelUnknownCount} (raw model_id missing or literal "unknown")`);
  console.log('');

  console.log('--- no-usage-marker remainder, by normalized role and by normalized model_id ---');
  console.log(`without_usage_marker total=${withoutUsageMarker}`);
  for (const [role, count] of [...roleNoMarker.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`no_marker role=${role} count=${count}`);
  }
  for (const [model, count] of [...modelNoMarker.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`no_marker model_id=${model} count=${count}`);
  }

  if (roleSum !== tokensTotal || modelSum !== tokensTotal) {
    console.error('ledger-token-attribution: RECONCILIATION FAILED — a grouping sum does not equal tokens_total');
    process.exit(1);
  }

  process.exit(0);
}

main();
