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
// NB-7 (remediation round 3): a Test Plan row whose Status cell is a
// TERMINAL-NOT-GREEN value (deferred/dropped/rejected — the vocabulary the
// live corpus's own Test Plan Status columns already use, distinct from the
// AC Status table's done/deferred/blocked/rejected) is EXEMPT: a ride that
// truthfully defers or drops a row, disclosed in an amendment, must still be
// able to close — fabricating a RED record or deleting the row were the only
// two ways to satisfy the gate before this fix. Exempt rows are named in the
// output (`EXEMPT <TEST-id>: status <value>`), never silently skipped.
//
// NB-2 (remediation round 4): a Test Plan whose EVERY row is exempt (NB-7
// above) passes vacuously — the satisfied count is 0, indistinguishable at a
// glance from "GATE PASS: 0 row(s) satisfied" for an empty spec. This is now
// its own DEGRADE class (`DEGRADED: every row exempt (n) degraded=n
// exempt=n`, exit 0 unchanged — the trailing `exempt=n` keeps this class
// parseable by the SAME regex close-work-item.mjs already uses on an
// ordinary PASS line's `exempt=n`), never silently folded into an ordinary
// PASS line — see
// close-work-item.mjs `evaluateMutationGate`, which surfaces this (and any
// partial exempt/degraded count) as a WARNING at close, even on the gate's
// exit-0 path.
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
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { parseFrontmatter, parseTestPlanTable, resolveStrategy, isMutationCellPlaceholder } from './lib/docs-model.mjs';
import { parseRecord, recordFileName, extractDeclaredMutations, canonicalizeMutation } from './lib/mutation-record.mjs';

const ROOT = process.cwd();

// NB-7: the closed set of Test Plan Status values that exempt a row from the
// RED-record requirement — a terminal disposition the ride disclosed, not a
// green pass. `pending` and `green` (and `red`, mid-flight) are NOT terminal
// here: only these three take a row out of the gate's judgement entirely.
const EXEMPT_STATUSES = new Set(['deferred', 'dropped', 'rejected']);

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

// Remediation round 7 (Copilot, PR #384): a missing value OR a value that
// itself looks like another flag (starts with "--") is a usage error, never
// silently accepted as the flag's value — `--spec --json` used to swallow
// `--json` as the (nonexistent) spec path and report a confusing exit 3
// "cannot read" instead of naming the real defect: the invocation itself.
function requireValue(argv, i, flagName) {
  const v = argv[i + 1];
  if (v === undefined || v.startsWith('--')) {
    usageError(`${flagName} requires a value${v === undefined ? '' : ` (got "${v}", which looks like another flag)`}`);
  }
  return v;
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
        out.spec = requireValue(argv, i, '--spec');
        i += 1;
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

// computeUncomparableRows(rows) -> [{ testId, reason }] — SPEC-DRAFT
// spec-gate-checks-declared-mutation D2/D6/D7: every row whose Mutation cell
// is non-empty and not a placeholder (the gate's OWN two pre-existing
// classes — a missing/placeholder cell is already OFFENDING and never
// reaches this classifier) yet yields ZERO tokens from
// extractDeclaredMutations. Reads ROW TEXT ONLY — no record lookup, no
// evidence directory — so this is the ONE judgement this gate can still make
// on a checkout with no evidence tree at all (D7). An EXEMPT row (Status
// deferred/dropped/rejected) is skipped first, matching the per-row loop
// below byte-for-byte: the frozen spec's Implementation plan Edge cases says
// an EXEMPT row "is still exempted first and is never classified, counted or
// compared" — a deferred row carrying a prose Mutation cell must not drive
// this ratchet with a remedy nobody can perform (you cannot produce a RED
// record for a row that is deliberately not being run).
// EXPORTED (validation round 2 BLOCKING, TEST-709): a test asserting
// Spec-AC-09 ("equal to the count the shipped classifier measures") must call
// THIS function, never re-implement its loop — a second copy is exactly the
// defect class this ride exists to close (round 1's tautological TEST-703
// backtick arm was the first instance; a re-implemented TEST-709 was the
// second). Exporting a function from a CLI script is otherwise inert: this
// file's own entry point is now guarded (see the isMain check at the bottom),
// so `import`ing this module for its exports no longer also runs main()
// against the importer's own process.argv.
export function computeUncomparableRows(rows) {
  const out = [];
  for (const row of rows) {
    const statusNorm = (row.statusCell ?? '').trim().toLowerCase();
    if (EXEMPT_STATUSES.has(statusNorm)) continue;
    const cell = (row.mutationCell ?? '').trim();
    if (!cell) continue;
    if (isMutationCellPlaceholder(cell)) continue;
    if (extractDeclaredMutations(cell).length === 0) {
      out.push({ testId: row.testId, reason: `Mutation cell has no machine-readable declaration: ${JSON.stringify(cell)}` });
    }
  }
  return out;
}

// readUncomparableBaseline(fm, specArg) -> non-negative integer (absent = 0,
// D6). A non-integer or negative value is a gate error (exit 3) naming the
// spec, never a silent 0 (Implementation plan "Edge cases").
function readUncomparableBaseline(fm, specArg) {
  const raw = fm.mutation_uncomparable;
  if (raw === undefined || raw === null || String(raw).trim() === '') return 0;
  const s = String(raw).trim();
  if (!/^-?\d+$/.test(s)) {
    gateError(`--spec ${specArg} has a non-integer mutation_uncomparable frontmatter value (${JSON.stringify(raw)}); must be a non-negative integer`);
  }
  const n = Number(s);
  if (n < 0) {
    gateError(`--spec ${specArg} has a negative mutation_uncomparable frontmatter value (${n}); must be a non-negative integer`);
  }
  return n;
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
      if (payload.unstamped) {
        console.log(`NOTE: unstamped=${payload.unstamped} record(s) lack target_sha256 (predate the D8 stale-record check) — regenerate via mutation-run.mjs to close the gap`);
      }
      if (payload.ratchet_note) {
        console.log(payload.ratchet_note);
      }
      if (args.listDegraded) {
        for (const d of payload.degraded_rows ?? []) console.log(`DEGRADED ${d.testId}: ${d.reason}`);
      }
      for (const e of payload.exempt_rows ?? []) console.log(`EXEMPT ${e.testId}: status ${e.status}`);
      for (const u of payload.uncomparable_rows ?? []) console.log(`UNCOMPARABLE ${u.testId}: ${u.reason}`);
      for (const o of payload.offending_rows ?? []) console.log(`OFFENDING ${o.testId}: ${o.reason}`);
      for (const s of payload.spec_offending ?? []) console.log(`OFFENDING ${s.specId}: ${s.reason}`);
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

  // D6/D7: the uncomparable ratchet is evaluated for EVERY applicable spec,
  // reading committed row text only — before the evidence-directory check
  // below, so it runs identically whether or not that directory exists (the
  // one place a DEGRADED run can now exit 5).
  const uncomparableBaseline = readUncomparableBaseline(fm, args.spec);
  const textUncomparableRows = computeUncomparableRows(tp.rows);
  const uncomparableIdSet = new Set(textUncomparableRows.map((r) => r.testId));
  const ratchetActual = textUncomparableRows.length;
  const ratchetExceeded = ratchetActual > uncomparableBaseline;
  const ratchetBelow = ratchetActual < uncomparableBaseline;
  const ratchetOffendingEntry = () => ({
    specId,
    reason: `mutation_uncomparable actual=${ratchetActual} exceeds frontmatter baseline=${uncomparableBaseline} (row(s): ${textUncomparableRows.map((r) => r.testId).join(', ') || 'none named'}) — reconcile the drifted row(s) via mutation-run.mjs (and spec-amend.mjs to disclose the cell edit) or raise mutation_uncomparable to ${ratchetActual} with disclosure`,
  });
  const ratchetNoteText = () => `NOTE: mutation_uncomparable (${uncomparableBaseline}) can be lowered to ${ratchetActual}`;

  const evidenceDir = path.join(ROOT, 'docs', 'ai', 'tdd', specId);
  let evidenceDirExists = false;
  try {
    evidenceDirExists = fs.statSync(evidenceDir).isDirectory();
  } catch {
    evidenceDirExists = false;
  }
  if (!evidenceDirExists) {
    if (ratchetExceeded) {
      const payload = {
        spec_id: specId,
        applicable: true,
        degraded: tp.rows.length,
        degraded_class: 'evidence tree absent',
        uncomparable: ratchetActual,
        uncomparable_rows: textUncomparableRows,
        uncomparable_baseline: uncomparableBaseline,
        spec_offending: [ratchetOffendingEntry()],
        offending_rows: [],
        degraded_rows: tp.rows.map((r) => ({ testId: r.testId, reason: 'evidence tree absent' })),
        summary_line: `GATE FAIL: mutation_uncomparable ratchet exceeded degraded=${tp.rows.length} uncomparable=${ratchetActual}`,
      };
      summary(payload);
      exit(5);
    }
    const payload = {
      spec_id: specId,
      applicable: true,
      degraded: tp.rows.length,
      degraded_class: 'evidence tree absent',
      uncomparable: ratchetActual,
      uncomparable_rows: textUncomparableRows,
      uncomparable_baseline: uncomparableBaseline,
      // `uncomparable=<n>` is appended, never inserted — the line still
      // STARTS with the byte-identical "DEGRADED: evidence tree absent
      // degraded=<n>" prefix Spec-AC-06/TEST-706 pin (D7: the ratchet is
      // evaluated even here, and the count it read must be visible, not
      // only silently correct).
      summary_line: `DEGRADED: evidence tree absent degraded=${tp.rows.length} uncomparable=${ratchetActual}`,
      offending_rows: [],
      degraded_rows: tp.rows.map((r) => ({ testId: r.testId, reason: 'evidence tree absent' })),
    };
    if (ratchetBelow) payload.ratchet_note = ratchetNoteText();
    summary(payload);
    exit(0);
  }

  const offending = [];
  const exempt = [];
  const uncomparable = [];
  // Remediation round 5 (D8 amendment, BLOCKING-1 validation round 6): a
  // record's own `target_sha256` (optional — see lib/mutation-record.mjs)
  // lets this gate tell that a SATISFIED-shaped record has gone STALE — its
  // target file changed since the record was produced, so a RED verdict it
  // still carries is no longer evidence that the mutation still reddens
  // (only `--replay` re-runs it; this gate only re-READS it, D8's own
  // NB8-r2 limit). `unstamped` counts records that predate this field — a
  // NAMED degrade (NOTE), never blocking, so an old record does not start
  // failing the moment this field ships.
  let unstamped = 0;
  for (const row of tp.rows) {
    const statusNorm = (row.statusCell ?? '').trim().toLowerCase();
    if (EXEMPT_STATUSES.has(statusNorm)) {
      exempt.push({ testId: row.testId, status: statusNorm });
      continue;
    }
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
    // Spec-AC-01/02/03/04 (D2, D3, D4, D5): the row's cell is classified
    // against the SAME text-only judgement the ratchet above already made
    // (uncomparableIdSet) — a row with zero declared tokens is UNCOMPARABLE
    // and excluded from `satisfied`, never silently counted as passing
    // (D5: it still owes every check above AND the target_sha256 checks
    // below, so it falls through rather than `continue`ing here). A row
    // WITH declared token(s) must have its record's `mutation` canonically
    // equal AT LEAST ONE of them (D4: a cell may legitimately carry a
    // rotated token beside the live one) — any other recorded value is a
    // declaration that does not match what actually ran, and is OFFENDING,
    // naming both the declared and the recorded value (never accusing a row
    // this gate could not parse — that fails safe to UNCOMPARABLE instead,
    // D2).
    if (uncomparableIdSet.has(row.testId)) {
      uncomparable.push({ testId: row.testId, reason: `Mutation cell has no machine-readable declaration: ${JSON.stringify(mCell)}` });
    } else {
      const declaredTokens = extractDeclaredMutations(mCell);
      const recordedCanon = canonicalizeMutation(f.mutation);
      if (!declaredTokens.includes(recordedCanon)) {
        offending.push({
          testId: row.testId,
          reason: `declared mutation (${declaredTokens.join(' | ')}) does not match the record's mutation "${f.mutation}" (canonical "${recordedCanon}")`,
        });
        continue;
      }
    }
    if (!f.target_sha256) {
      unstamped++;
      continue;
    }
    const targetAbs = path.join(ROOT, f.target);
    let liveSha256;
    try {
      liveSha256 = createHash('sha256').update(fs.readFileSync(targetAbs)).digest('hex');
    } catch {
      // NB3-r7 (validation round 7): a DELETED (or renamed) target is a
      // different cause from an EDITED one — say so, rather than reusing the
      // "changed since the record" wording the comparison below uses for a
      // genuine hash mismatch. fu-mutation-gate-remedy-does-not-restamp: a
      // MISSING target is the one shape --replay genuinely cannot heal (its
      // own existsSync check refuses before any mutation is even applied),
      // so the remedy here still names a fresh (plain) mutation-run.mjs run,
      // never --replay.
      offending.push({
        testId: row.testId,
        reason: `STALE ${row.testId}: target ${f.target} missing — restore the target or re-run mutation-run.mjs (not --replay, which cannot restamp a target that no longer exists) to produce a fresh record for this row`,
      });
      continue;
    }
    if (liveSha256 !== f.target_sha256) {
      // fu-mutation-gate-remedy-does-not-restamp (measured closing this
      // ride): the OLD wording here told an operator to "re-run
      // mutation-run.mjs (or --replay)", but --replay used to only VERIFY —
      // it never re-stamped target_sha256, so following this exact remedy
      // left the row STALE forever. --replay now re-stamps target_sha256
      // whenever it re-applies a record's mutation and the row still
      // reddens (see mutation-run.mjs's own RE-STAMPING note), so this line
      // now names the remedy that actually clears the gate.
      offending.push({
        testId: row.testId,
        reason: `STALE ${row.testId}: target ${f.target} changed since the record — re-run mutation-run.mjs --replay for this row (a replay that still reddens re-stamps target_sha256 automatically)`,
      });
      continue;
    }
  }

  if (offending.length || ratchetExceeded) {
    // N3 (validation round 2, non-blocking-but-fixed): `uncomparable.length`
    // (the per-row array below) only counts rows that reached the
    // classification step at all — a row whose Mutation cell is ALREADY
    // text-uncomparable but whose RECORD is missing (or otherwise fails an
    // earlier check) is pushed to `offending` and `continue`s BEFORE ever
    // reaching that step, so it is silently absent from `uncomparable.length`
    // while `ratchetActual` (computed from row TEXT ALONE, D7) still counts
    // it. That let this same GATE FAIL summary line print `uncomparable=0`
    // beside an `OFFENDING <spec-id>: ... actual=1 ...` ratchet refusal for
    // the SAME run — two numbers for one fact, and close-work-item.mjs reads
    // the summary line's number, not the ratchet's prose. `ratchetActual` is
    // the authoritative D7 measure (a strict superset of the per-row array:
    // every row counted in `uncomparable` is by construction also counted in
    // `ratchetActual`, never the reverse), so it is what this line reports —
    // the two are provably equal whenever no row failed an earlier check
    // (the ordinary case, and the ONLY case the PASS branch below can reach),
    // and `ratchetActual` is the honest, non-optimistic count otherwise.
    const payload = {
      spec_id: specId,
      applicable: true,
      degraded: 0,
      unstamped,
      offending_rows: offending,
      degraded_rows: [],
      exempt_rows: exempt,
      uncomparable: ratchetActual,
      uncomparable_rows: uncomparable,
      uncomparable_baseline: uncomparableBaseline,
      spec_offending: ratchetExceeded ? [ratchetOffendingEntry()] : [],
      summary_line: `GATE FAIL: ${offending.length} offending row(s) degraded=0 unstamped=${unstamped} uncomparable=${ratchetActual}${exempt.length ? ` exempt=${exempt.length}` : ''}`,
    };
    summary(payload);
    exit(5);
  }

  const satisfied = tp.rows.length - exempt.length - uncomparable.length;

  // Remediation round 4 (NB-2): a Test Plan whose rows are ALL exempt passes
  // vacuously — zero rows were ever judged against the RED-record
  // requirement, which reads identically to a spec with no rows at all. That
  // is an applicability degrade (D9's own class), not a satisfied-rows PASS,
  // so it gets its own named class here rather than a "GATE PASS: 0 row(s)
  // satisfied" line an operator would read as "nothing to report". Guarded
  // on exempt.length === tp.rows.length (not merely satisfied === 0, which
  // the new uncomparable subtraction can now also drive to zero without
  // every row being exempt) — this class is specifically "every row exempt",
  // never "every row exempt or uncomparable".
  if (exempt.length > 0 && exempt.length === tp.rows.length) {
    const payload = {
      spec_id: specId,
      applicable: true,
      degraded: exempt.length,
      degraded_class: 'every row exempt',
      summary_line: `DEGRADED: every row exempt (${exempt.length}) degraded=${exempt.length} exempt=${exempt.length}`,
      offending_rows: [],
      degraded_rows: [],
      exempt_rows: exempt,
      uncomparable: 0,
      uncomparable_rows: [],
      uncomparable_baseline: uncomparableBaseline,
    };
    summary(payload);
    exit(0);
  }

  const payload = {
    spec_id: specId,
    applicable: true,
    degraded: 0,
    unstamped,
    offending_rows: [],
    degraded_rows: [],
    exempt_rows: exempt,
    uncomparable: uncomparable.length,
    uncomparable_rows: uncomparable,
    uncomparable_baseline: uncomparableBaseline,
    summary_line: `GATE PASS: ${satisfied} row(s) satisfied degraded=0 unstamped=${unstamped} uncomparable=${uncomparable.length}${exempt.length ? ` exempt=${exempt.length}` : ''}`,
  };
  if (ratchetBelow) payload.ratchet_note = ratchetNoteText();
  summary(payload);
  exit(0);
}

// Standard ESM entry-point guard (matching mutation-run.mjs's own NB4-r3):
// lets a TEST import this module for its exports (computeUncomparableRows)
// without ALSO running the CLI against the importer's own process.argv — a
// pure safety addition; every existing `node mutation-gate.mjs ...`
// invocation is unaffected (argv[1] IS this file in that case). Both sides
// through realpath so a symlinked invocation still runs.
const __argvReal = (() => { try { return fs.realpathSync(path.resolve(process.argv[1] ?? '')); } catch { return ''; } })();
if (__argvReal !== '' && __argvReal === fs.realpathSync(fileURLToPath(import.meta.url))) {
  runMain(() => main());
}
