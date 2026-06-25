#!/usr/bin/env node
// Docs canonicalization CLI (RFC-0003 / SPEC-0002) — aai-docs-canon helper.
//
// Two-phase, idempotent, re-runnable pipeline:
//
//   Phase 1 (analyze + propose, HUMAN gate):
//     node .aai/scripts/docs-canon.mjs --phase1 [--targets a,b,c]
//       Parses the target doc set, builds a supersession/dependency graph,
//       emits a machine-readable domain-map PROPOSAL under docs/ai/, and HALTS
//       for human approval. Writes nothing under docs/canonical or docs/_archive.
//
//   Phase 2 (synthesize + canonicalize, AUTO):
//     node .aai/scripts/docs-canon.mjs --phase2
//       Reads the persisted APPROVED map (docs/ai/docs-canon.map.json with
//       approved: true), synthesizes one canonical doc per domain with the five
//       fixed layer sections, moves contributing originals to docs/_archive/
//       with status: archived + a canonical: back-pointer, and records source
//       hashes for re-run drift. Refuses to run on an unapproved map.
//
//   Drift / re-run report:
//     node .aai/scripts/docs-canon.mjs --drift
//       Compares current source bodies against the hashes recorded at last
//       synthesis and reports drifted domains without rewriting anything.
//
//   Resync a drifted domain:
//     node .aai/scripts/docs-canon.mjs --phase2 --resync
//       Like --phase2, but DRIFTED domains are re-synthesized from their
//       current (archived) sources and the drift baseline is re-recorded, so a
//       drift is resolvable from the CLI without hand-editing the map JSON.
//
// The LLM-driven prose synthesis of each canonical body is the agent's job
// (see .aai/SKILL_DOCS_CANON.prompt.md); this CLI owns every deterministic step
// and enforces the section/provenance contract.

import {
  DEFAULT_TARGET_DIRS, PROPOSAL_PATH, MAP_PATH,
  CANONICAL_DIR, ARCHIVE_DIR,
  collectDocs, buildGraph, proposeDomainMap, isApprovedMap,
  runPhase2, detectDrift, checkLinkIntegrity, writeJson, readJson,
} from './lib/docs-canon-core.mjs';

const ROOT = process.cwd();

function parseArgs(argv) {
  const args = { phase: null, targets: DEFAULT_TARGET_DIRS };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--phase1') args.phase = 1;
    else if (tok === '--phase2') args.phase = 2;
    else if (tok === '--drift') args.phase = 'drift';
    else if (tok === '--resync') args.resync = true;
    else if (tok === '--targets') args.targets = String(argv[++i]).split(',').map(s => s.trim()).filter(Boolean);
  }
  if (args.phase == null) args.phase = 1;
  return args;
}

function phase1(args) {
  const docs = collectDocs(ROOT, args.targets);
  const graph = buildGraph(docs);
  const proposal = proposeDomainMap(docs, graph);
  proposal.targets = args.targets;
  writeJson(ROOT, PROPOSAL_PATH, proposal);

  console.log(`## docs-canon — Phase 1 (analyze + propose)`);
  console.log('');
  console.log(`- Scanned: ${docs.length} doc(s) under ${args.targets.join(', ')}`);
  console.log(`- Umbrella groups: ${graph.umbrellaGroups.length}`);
  console.log(`- Proposed domains: ${Object.keys(proposal.domains).length} | unclear: ${proposal.unclear.length}`);
  console.log(`- Proposal written: ${PROPOSAL_PATH}`);
  console.log('');
  console.log('HUMAN APPROVAL REQUIRED: review the proposed domain map, then save an');
  console.log(`approved map to ${MAP_PATH} with "approved": true before running --phase2.`);
  console.log('No files under docs/canonical/ or docs/_archive/ were created (gate enforced).');
  // exit 0: Phase 1 completed successfully but signals a non-terminal pipeline
  // state (awaiting approval) via the message above.
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
  // persist the map back (records sourceHashes + archivedAt for re-run drift)
  writeJson(ROOT, MAP_PATH, result.map);

  console.log(`## docs-canon — Phase 2 (synthesize + canonicalize)${resync ? ' [resync]' : ''}`);
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

  const link = checkLinkIntegrity(ROOT, { canonicalDir: CANONICAL_DIR, archiveDir: ARCHIVE_DIR });
  if (!link.ok) {
    console.error(`FAIL: link-integrity violations:`);
    for (const v of link.violations) console.error(`  - ${v}`);
    process.exit(1);
  }
  console.log(`- Link integrity: OK (sources: <-> canonical: resolve bidirectionally)`);
}

function drift() {
  const map = readJson(ROOT, MAP_PATH);
  if (!map) { console.error(`FAIL: ${MAP_PATH} not found.`); process.exit(1); }
  const d = detectDrift(map, ROOT);
  console.log(`## docs-canon — Drift report`);
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
