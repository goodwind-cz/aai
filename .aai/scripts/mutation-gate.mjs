#!/usr/bin/env node
// mutation-gate.mjs — read every `## Test Plan` row of an applicable spec and
// confirm each carries a genuine RED mutation record (SPEC-DRAFT
// spec-mutation-gate-for-tests D8, D9).
//
// A row is SATISFIED when ALL of:
//   - its Mutation cell is non-empty and not a placeholder (-, —, TBD, pending);
//   - docs/ai/tdd/<spec-id>/mutation-<TEST-id>.txt exists and parses as
//     mutation_record: v1;
//   - the record's test_id equals the row's Test ID and its suite equals the
//     row's File path cell (catches a record copied from another row);
//   - the record's verdict is RED;
//   - the record's base_commit is an ancestor of HEAD (a record from an
//     abandoned/rebased history is not evidence for the tree being closed).
//
// APPLICABILITY (D9): a spec is gated when its frontmatter carries
// `mutation_gate: v1` AND its recorded strategy (spec-lint's own precedence,
// see lib/docs-model.mjs resolveStrategy — never a private parser) is `tdd`
// or `hybrid`. A spec without the marker DEGRADES (pre-change spec) rather
// than failing; an applicable spec whose evidence directory does not exist
// also DEGRADES (the CI / fresh-clone case) — for every row at once, in ONE
// line carrying the count, never a silent per-row 0.
//
// USAGE
//   node .aai/scripts/mutation-gate.mjs --spec <path> [--json] [--list-degraded]
//   node .aai/scripts/mutation-gate.mjs --help
//
// EXIT CONTRACT (D8, the same three-way split as mutation-run.mjs D6)
//   0  every applicable row satisfied (degraded rows/specs named per D9)
//   5  at least one row unsatisfied — EVERY offending row is printed
//   3  the gate itself could not run (spec unreadable, no frontmatter id,
//      Test Plan unparseable, git unavailable)
//   2  usage error
//
// NB8-r2 (disclosed design, D8): the gate reads ROWS, not the suite's own
// text — renaming a selector out from under an otherwise-satisfied record
// clears this gate at PASS (it never re-derives whether the record's
// selector still exists in the suite), because only `mutation-run.mjs
// --replay` re-runs the recorded mutation and can catch that staleness.
// `close-work-item.mjs` runs THIS gate, not `--replay` — a "GATE PASS" here
// is never proof the evidence is fresh, only that a record satisfying the
// row's shape was once produced.
//
// Node stdlib only (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { parseFrontmatter, parseTestPlanTable, resolveStrategy, isMutationCellPlaceholder } from './lib/docs-model.mjs';
import { parseRecord, recordFileName } from './lib/mutation-record.mjs';

const ROOT = process.cwd();

function usageError(msg) {
  process.stderr.write(`mutation-gate: ${msg}\n`);
  process.stderr.write('usage: node .aai/scripts/mutation-gate.mjs --spec <path> [--json] [--list-degraded]\n');
  exit(2);
}

function printHelp() {
  process.stdout.write(
    'mutation-gate.mjs — confirm every Test Plan row of an applicable spec carries a RED mutation record\n\n' +
      'usage:\n' +
      '  node .aai/scripts/mutation-gate.mjs --spec <path> [--json] [--list-degraded]\n\n' +
      'exit: 0 satisfied (degraded named) | 5 offending row(s) | 3 gate could not run | 2 usage\n'
  );
  exit(0);
}

function parseArgs(argv) {
  const out = { spec: null, json: false, listDegraded: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '--help':
      case '-h':
        out.help = true;
        break;
      case '--spec':
        out.spec = argv[++i];
        break;
      case '--json':
        out.json = true;
        break;
      case '--list-degraded':
        out.listDegraded = true;
        break;
      default:
        usageError(`unrecognized argument: ${a}`);
    }
  }
  return out;
}

function gateError(msg) {
  process.stderr.write(`mutation-gate: ${msg}\n`);
  exit(3);
}

// isApplicable(fm, content) -> boolean. D9: the marker AND a tdd/hybrid
// strategy, read with spec-lint's own precedence (resolveStrategy) — never a
// private parser.
function isApplicable(fm, content) {
  if (fm.mutation_gate !== 'v1') return false;
  const strategy = resolveStrategy(content);
  return strategy === 'tdd' || strategy === 'hybrid';
}

function gitHeadAvailable() {
  try {
    execFileSync('git', ['-C', ROOT, 'rev-parse', '--verify', 'HEAD'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function isAncestorOfHead(commit) {
  if (!/^[0-9a-f]{7,40}$/i.test(String(commit ?? ''))) return false;
  try {
    execFileSync('git', ['-C', ROOT, 'merge-base', '--is-ancestor', commit, 'HEAD'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) printHelp();
  if (!args.spec) usageError('--spec <path> is required');

  const specPath = path.isAbsolute(args.spec) ? args.spec : path.join(ROOT, args.spec);
  let content;
  try {
    content = fs.readFileSync(specPath, 'utf8');
  } catch (err) {
    gateError(`cannot read --spec ${args.spec} (${err.message})`);
  }
  const fm = parseFrontmatter(content);
  if (!fm || !fm.id) gateError(`--spec ${args.spec} has no frontmatter "id:" field`);
  const specId = fm.id;

  const tp = parseTestPlanTable(content);
  if (!tp.present) gateError(`--spec ${args.spec} has no "## Test Plan" section`);

  if (!gitHeadAvailable()) gateError('git is unavailable or this is not a git checkout (no HEAD)');

  // Ambiguity refusal (Implementation plan "Edge cases"): the SAME Test id
  // twice in one Test Plan makes "the record for this row" undefined — refuse
  // rather than silently reading one record for two rows.
  const seen = new Map();
  for (const row of tp.rows) seen.set(row.testId, (seen.get(row.testId) ?? 0) + 1);
  const dupes = [...seen].filter(([, n]) => n > 1).map(([id]) => id);
  if (dupes.length) {
    gateError(`Test Plan lists the same Test ID more than once: ${dupes.join(', ')} — the gate cannot tell which record belongs to which row`);
  }

  const summary = (payload) => {
    if (args.json) {
      console.log(JSON.stringify(payload, null, 2));
    } else {
      console.log(`## Mutation Gate — ${specId}`);
      console.log('');
      console.log(payload.summary_line);
      if (args.listDegraded) {
        for (const d of payload.degraded_rows ?? []) console.log(`DEGRADED ${d.testId}: ${d.reason}`);
      }
      for (const o of payload.offending_rows ?? []) console.log(`OFFENDING ${o.testId}: ${o.reason}`);
    }
  };

  if (!isApplicable(fm, content)) {
    const payload = {
      spec_id: specId,
      applicable: false,
      degraded: tp.rows.length,
      degraded_class: 'pre-change spec (no mutation_gate marker)',
      summary_line: `DEGRADED: pre-change spec (no mutation_gate marker) degraded=${tp.rows.length}`,
      offending_rows: [],
      degraded_rows: tp.rows.map((r) => ({ testId: r.testId, reason: 'pre-change spec (no mutation_gate marker)' })),
    };
    summary(payload);
    exit(0);
  }

  const evidenceDir = path.join(ROOT, 'docs', 'ai', 'tdd', specId);
  let evidenceDirExists = false;
  try {
    evidenceDirExists = fs.statSync(evidenceDir).isDirectory();
  } catch {
    evidenceDirExists = false;
  }
  if (!evidenceDirExists) {
    const payload = {
      spec_id: specId,
      applicable: true,
      degraded: tp.rows.length,
      degraded_class: 'evidence tree absent',
      summary_line: `DEGRADED: evidence tree absent degraded=${tp.rows.length}`,
      offending_rows: [],
      degraded_rows: tp.rows.map((r) => ({ testId: r.testId, reason: 'evidence tree absent' })),
    };
    summary(payload);
    exit(0);
  }

  const offending = [];
  for (const row of tp.rows) {
    const mCell = (row.mutationCell ?? '').trim();
    if (!mCell) {
      offending.push({ testId: row.testId, reason: 'Mutation cell is empty' });
      continue;
    }
    if (isMutationCellPlaceholder(mCell)) {
      offending.push({ testId: row.testId, reason: `Mutation cell "${mCell}" is a placeholder` });
      continue;
    }
    const recPath = path.join(evidenceDir, recordFileName(row.testId));
    let text;
    try {
      text = fs.readFileSync(recPath, 'utf8');
    } catch {
      offending.push({ testId: row.testId, reason: `missing record at docs/ai/tdd/${specId}/${recordFileName(row.testId)}` });
      continue;
    }
    const parsed = parseRecord(text);
    if (!parsed.ok) {
      offending.push({ testId: row.testId, reason: `record does not parse as mutation_record v1 (${parsed.error})` });
      continue;
    }
    const f = parsed.fields;
    if (f.test_id !== row.testId) {
      offending.push({ testId: row.testId, reason: `record's test_id "${f.test_id}" does not match this row` });
      continue;
    }
    if (f.suite !== row.fileCell) {
      offending.push({ testId: row.testId, reason: `record's suite "${f.suite}" does not match the row's File path cell "${row.fileCell}"` });
      continue;
    }
    if (f.verdict !== 'RED') {
      offending.push({ testId: row.testId, reason: `record verdict is "${f.verdict}", not RED` });
      continue;
    }
    if (!isAncestorOfHead(f.base_commit)) {
      offending.push({ testId: row.testId, reason: `record's base_commit "${f.base_commit}" is not an ancestor of HEAD` });
      continue;
    }
  }

  if (offending.length) {
    const payload = {
      spec_id: specId,
      applicable: true,
      degraded: 0,
      offending_rows: offending,
      degraded_rows: [],
      summary_line: `GATE FAIL: ${offending.length} offending row(s) degraded=0`,
    };
    summary(payload);
    exit(5);
  }

  const payload = {
    spec_id: specId,
    applicable: true,
    degraded: 0,
    offending_rows: [],
    degraded_rows: [],
    summary_line: `GATE PASS: ${tp.rows.length} row(s) satisfied degraded=0`,
  };
  summary(payload);
  exit(0);
}

runMain(() => main());
