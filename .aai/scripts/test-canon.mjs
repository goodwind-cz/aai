#!/usr/bin/env node
// Test canonicalization CLI (RFC-0006 / SPEC-0008) — aai-test-canon helper.
//
// Two-phase, idempotent, re-runnable pipeline:
//
//   Phase 1 (analyze + propose, HUMAN gate):
//     node .aai/scripts/test-canon.mjs --phase1
//       Parses existing tests and the canonical domain map, builds a traceability
//       matrix, emits a coverage gap report, and writes a machine-readable proposal
//       under docs/ai/test-canon.proposal.json with "approved": false. NEVER moves
//       or writes test files.
//
//   Phase 2 (synthesize + canonicalize, AUTO):
//     node .aai/scripts/test-canon.mjs --phase2
//       Reads the approved map (docs/ai/test-canon.map.json with "approved": true),
//       consolidates tests into tests/canonical/, moves originals to tests/_archive/
//       with back-links, scaffolds RED stubs for uncovered criteria. Refuses to run
//       on an unapproved map.
//
//   Drift / re-run report:
//     node .aai/scripts/test-canon.mjs --drift
//       Compares current source bodies against the hashes recorded at last synthesis
//       and reports drifted domains without rewriting anything.
//
//   Resync a drifted domain:
//     node .aai/scripts/test-canon.mjs --phase2 --resync
//       Like --phase2, but DRIFTED domains are re-synthesized from their current
//       (archived) sources and the drift baseline is re-recorded.

import {
  PROPOSAL_PATH, MAP_PATH,
  runPhase1, isApprovedMap,
  runPhase2, detectDrift,
  writeJson, readJson,
} from './lib/test-canon-core.mjs';

const ROOT = process.cwd();

function parseArgs(argv) {
  const args = { phase: null, resync: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--phase1') args.phase = 1;
    else if (tok === '--phase2') args.phase = 2;
    else if (tok === '--drift') args.phase = 'drift';
    else if (tok === '--resync') args.resync = true;
  }
  if (args.phase == null) args.phase = 1;
  return args;
}

function phase1(args) {
  const result = runPhase1(ROOT);

  console.log(`## test-canon — Phase 1 (analyze + propose)`);
  console.log('');
  console.log(`- Scanned: ${result.testFiles} test file(s)`);
  if (result.degraded) {
    console.log(`- Degraded mode: docs/canonical/ absent, mapped against raw docs/`);
  }
  console.log(`- Proposed domains: ${Object.keys(result.proposal.domains).length} | unclear: ${result.proposal.unclear.length}`);
  console.log(`- Proposal written: ${PROPOSAL_PATH}`);
  console.log(`- Coverage report: ${result.reportPath}`);
  console.log('');
  console.log('HUMAN APPROVAL REQUIRED: review the proposed test map, then save an');
  console.log(`approved map to ${MAP_PATH} with "approved": true before running --phase2.`);
  console.log('No files under tests/canonical/ or tests/_archive/ were created (gate enforced).');
}

function phase2(args) {
  const map = readJson(ROOT, MAP_PATH);
  if (!isApprovedMap(map)) {
    console.error(`FAIL: ${MAP_PATH} is missing or not approved (need "approved": true with >=1 domain).`);
    console.error('Run --phase1, review the proposal, and persist an approved map first.');
    process.exit(1);
  }
  const resync = Boolean(args?.resync);
  const result = runPhase2(ROOT, map, { resync });
  // Persist the map back (records sourceHashes for re-run drift)
  writeJson(ROOT, MAP_PATH, result.map);

  console.log(`## test-canon — Phase 2 (synthesize + canonicalize)${resync ? ' [resync]' : ''}`);
  console.log('');
  console.log(`- Canonical written: ${result.written.length} (${result.written.join(', ') || '—'})`);
  console.log(`- Skipped (unchanged): ${result.skipped.length} (${result.skipped.join(', ') || '—'})`);
  if (resync) {
    console.log(`- Re-synced (drift resolved): ${result.resynced.length} (${result.resynced.join(', ') || '—'})`);
  }
  console.log(`- DRIFT (changed since synthesis, NOT rewritten): ${result.drifted.length} (${result.drifted.join(', ') || '—'})`);
  if (!resync && result.drifted.length > 0) {
    console.log(`  Re-run with --resync to re-synthesize drifted domain(s) from current sources.`);
  }
  console.log(`- Archived originals: ${result.archived.length}`);
}

function drift() {
  const map = readJson(ROOT, MAP_PATH);
  if (!map) { console.error(`FAIL: ${MAP_PATH} not found.`); process.exit(1); }
  const d = detectDrift(map, ROOT);
  console.log(`## test-canon — Drift report`);
  console.log('');
  console.log(`- Clean domains: ${d.clean.length} (${d.clean.join(', ') || '—'})`);
  console.log(`- DRIFTED domains: ${d.drifted.length} (${d.drifted.join(', ') || '—'})`);
  if (d.drifted.length > 0) process.exit(1);
}

function main() {
  const args = parseArgs(process.argv);
  if (args.phase === 1) phase1(args);
  else if (args.phase === 2) phase2(args);
  else if (args.phase === 'drift') drift();
}

main();
