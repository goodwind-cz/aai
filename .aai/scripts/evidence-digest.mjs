#!/usr/bin/env node
// evidence-digest.mjs — a deterministic evidence digest and its promotion score
// (SPEC-DRAFT spec-model-effort-routing D-DIGEST, D-SCORE).
//
//   node .aai/scripts/evidence-digest.mjs run --ref <ref> [--spec <path>] [--record] [--root <dir>]
//     prints one `AC ...` line per Acceptance Criteria Status row, one `TEST ...` line per Test Plan
//     row, three `GATE <name> rc=<n>` lines, the `SWEEP ...` line of round-budget.mjs sweep-plan and
//     one `DIGEST ...` summary. Exit 0 whatever it finds (a digest is never a verdict), 2 on usage,
//     3 when the spec cannot be read.
//   node .aai/scripts/evidence-digest.mjs score [--events <path>] [--json]
//     pairs each evidence_digest EVENTS line with the first later validation check_verdict of the same
//     ref and head; prints `SCORE ...` and `PROMOTION ...`. Exit 0.
//
// The dial is `evidence_digest: off|shadow|on` in docs/ai/docs-audit.yaml (column 0). Absent file, absent
// key or any other value reads as off. --record appends one evidence_digest line through append-event.mjs
// only under shadow or on. A sibling script that a downstream install lacks is reported as `rc=absent`
// and never counts as red.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parseAcTable, parseLeanAcTable, parseTestPlanTable, parseFrontmatter, normalizeAcStatus, TERMINAL_AC } from './lib/docs-model.mjs';
import { readEvents } from './round-budget.mjs';

export const PROMOTION_MIN_PAIRS = 20;
export const PROMOTION_MIN_RIDES = 5;
const DIAL_VALUES = ['off', 'shadow', 'on'];
const HERE = path.dirname(fileURLToPath(import.meta.url));

function parseFlags(argv) {
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (!argv[i].startsWith('--')) continue;
    const key = argv[i].slice(2);
    const next = argv[i + 1];
    if (next !== undefined && !next.startsWith('--')) { flags[key] = next; i += 1; } else flags[key] = true;
  }
  return flags;
}

// Dial reader: returns { dial, note } where note is a NOTE line for an out-of-set value or null.
export function readDial(root) {
  let raw;
  try { raw = fs.readFileSync(path.join(root, 'docs/ai/docs-audit.yaml'), 'utf8'); } catch { return { dial: 'off', note: null }; }
  for (const line of raw.split(/\r?\n/)) {
    const m = /^evidence_digest:\s*(\S+)/.exec(line);
    if (!m) continue;
    if (DIAL_VALUES.includes(m[1])) return { dial: m[1], note: null };
    return { dial: 'off', note: `NOTE evidence_digest value "${m[1]}" is not off, shadow or on; treated as off` };
  }
  return { dial: 'off', note: null };
}

function stateSpecPath(root) {
  try {
    const st = fs.readFileSync(path.join(root, 'docs/ai/STATE.yaml'), 'utf8');
    const m = /^\s+spec_path:\s*(\S+)\s*$/m.exec(st);
    if (m && m[1] !== 'null') return m[1].replace(/^["']|["']$/g, '');
  } catch { /* no STATE */ }
  return null;
}

// Cell tokens under docs/ or tests/.
function evidencePaths(cell) {
  const out = [];
  for (const m of String(cell ?? '').matchAll(/(?:^|[\s`(,;])((?:docs|tests)\/[^\s`,;)|]+)/g)) out.push(m[1].replace(/[.:]+$/, ''));
  return out;
}

// Runs a sibling script from this file's own directory with cwd = root. null when the script is absent.
function runSibling(script, args, root) {
  const file = path.join(HERE, script);
  if (!fs.existsSync(file)) return null;
  return spawnSync(process.execPath, [file, ...args], { cwd: root, encoding: 'utf8', env: { ...process.env } });
}

// True when every printed gate reason (a `- ` bullet) is a Rule-1 non-terminal AC row and there is at least one.
function onlyNonTerminalReasons(out) {
  const bullets = String(out ?? '').split(/\r?\n/).filter((l) => l.startsWith('- '));
  return bullets.length > 0 && bullets.every((l) => /^- \S+ is non-terminal \(status "/.test(l));
}

function git(root, args) {
  const r = spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  return r.status === 0 ? r.stdout.trim() : '';
}

function runDigest(flags) {
  if (typeof flags.ref !== 'string' || flags.ref === '') {
    console.error('usage: evidence-digest.mjs run --ref <ref> [--spec <path>] [--record] [--root <dir>]');
    return 2;
  }
  const root = typeof flags.root === 'string' ? path.resolve(flags.root) : process.cwd();
  const specRel = typeof flags.spec === 'string' ? flags.spec : stateSpecPath(root);
  if (!specRel) { console.error('evidence-digest: no --spec and no STATE current_focus spec_path'); return 3; }
  const specAbs = path.resolve(root, specRel);
  let content;
  try { content = fs.readFileSync(specAbs, 'utf8'); } catch (err) { console.error(`evidence-digest: cannot read spec ${specRel} (${err.code ?? err.message})`); return 3; }

  const open = ['draft', 'implementing'].includes(String(parseFrontmatter(content)?.status ?? '').trim());
  let acRows = parseAcTable(content).rows;
  if (acRows.length === 0) acRows = parseLeanAcTable(content).rows;
  let notDone = 0;
  let evidenceMissing = 0;
  for (const row of acRows) {
    const status = String(row.Status ?? '').trim().toLowerCase();
    const paths = evidencePaths(row.Evidence);
    const missing = paths.filter((p) => !fs.existsSync(path.join(root, p))).length;
    // AC-FLIP DEFERRAL carve (VALIDATION step 8a): while the spec is draft or implementing, a non-terminal
    // row is not yet-reached work, not a defect. Terminal non-done rows (deferred, blocked, rejected) count.
    const deferred = open && !TERMINAL_AC.has(normalizeAcStatus(row.Status ?? '').status);
    if (status !== 'done' && !deferred) notDone += 1;
    evidenceMissing += missing;
    console.log(`AC ${row['Spec-AC']} status=${status} evidence_paths=${paths.length} missing=${missing}`);
  }

  let unlocated = 0;
  for (const t of parseTestPlanTable(content).rows) {
    const file = t.fileCell.replace(/`/g, '').trim();
    const fileAbs = path.join(root, file);
    const exists = file !== '' && fs.existsSync(fileAbs) && fs.statSync(fileAbs).isFile();
    let idIn = false;
    if (exists) { try { idIn = fs.readFileSync(fileAbs, 'utf8').includes(t.testId); } catch { idIn = false; } }
    if (!exists || !idIn) unlocated += 1;
    console.log(`TEST ${t.testId} ac=${t.acCell} file=${file} file_exists=${exists ? 'yes' : 'no'} id_in_file=${idIn ? 'yes' : 'no'}`);
  }

  const fm = parseFrontmatter(content) ?? {};
  const gates = [
    ['spec-lint', 'spec-lint.mjs', ['--path', specAbs]],
    ['mutation-gate', 'mutation-gate.mjs', ['--spec', specAbs]],
    ['docs-audit-gate', 'docs-audit.mjs', ['--gate', String(fm.id ?? '')]],
  ];
  let gatesRed = 0;
  for (const [name, script, args] of gates) {
    const r = runSibling(script, args, root);
    if (r === null) { console.log(`GATE ${name} rc=absent`); continue; }
    const rc = r.status ?? 1;
    // Same carve as VALIDATION: an open spec's docs-audit gate failing only on Rule-1 non-terminal rows is not red.
    const onlyDeferred = name === 'docs-audit-gate' && open && rc === 1 && onlyNonTerminalReasons(r.stdout);
    if (rc !== 0 && !onlyDeferred) gatesRed += 1;
    console.log(`GATE ${name} rc=${rc}`);
  }

  let sweepLine = 'SWEEP unavailable reason=script-absent';
  const sw = runSibling('round-budget.mjs', ['sweep-plan', '--ref', flags.ref, '--root', root], root);
  if (sw !== null) sweepLine = (sw.stdout.split('\n').find((l) => l.startsWith('SWEEP ')) ?? 'SWEEP unavailable reason=no-output');
  console.log(sweepLine);
  const sweepOwed = sweepLine.startsWith('SWEEP full') ? 1 : 0;

  const counts = [notDone, evidenceMissing, unlocated, gatesRed, sweepOwed];
  const clean = counts.every((n) => n === 0);
  const head = git(root, ['rev-parse', 'HEAD']) || 'unknown';
  console.log(`DIGEST ref=${flags.ref} head=${head} acs=${acRows.length} acs_not_done=${notDone} evidence_missing=${evidenceMissing} `
    + `tests_unlocated=${unlocated} gates_red=${gatesRed} sweep_owed=${sweepOwed} clean=${clean}`);

  if (flags.record === true) {
    const { dial, note } = readDial(root);
    if (note) console.log(note);
    if (dial === 'off') {
      console.log('NOTE evidence_digest off; nothing recorded');
    } else if (!/^[0-9a-f]{40}$/.test(head)) {
      console.log('NOTE evidence_digest head unknown (no git commit); nothing recorded');
    } else {
      const flagsCount = counts.reduce((a, b) => a + b, 0);
      const r = runSibling('append-event.mjs', ['--event', 'evidence_digest', '--ref', flags.ref, '--head', head,
        '--clean', String(clean), '--flags', String(flagsCount)], root);
      if (r === null) console.log('NOTE evidence_digest append-event.mjs absent; nothing recorded');
      else if (r.status !== 0) console.log(`NOTE evidence_digest append-event refused (rc=${r.status}): ${String(r.stderr).trim()}`);
      else console.log(`NOTE evidence_digest recorded (dial ${dial})`);
    }
  }
  return 0;
}

// Pairs digests with validation verdicts; each verdict pairs at most once so a repeated digest of one
// head cannot inflate the count.
export function scoreEvents(events) {
  const used = new Set();
  const s = { pairs: 0, refs: new Set(), clean_pass: 0, clean_fail: 0, flagged_pass: 0, flagged_fail: 0, unpaired: 0, cleanRefs: new Set() };
  events.forEach((e, i) => {
    if (e.event !== 'evidence_digest' || !e.payload) return;
    let at = -1;
    for (let j = i + 1; j < events.length; j += 1) {
      const v = events[j];
      if (used.has(j) || v.event !== 'check_verdict' || !v.payload) continue;
      if (v.payload.role === 'validation' && v.ref === e.ref && v.payload.head === e.payload.head) { at = j; break; }
    }
    if (at < 0) { s.unpaired += 1; return; }
    used.add(at);
    s.pairs += 1;
    s.refs.add(e.ref);
    if (e.payload.clean === true) s.cleanRefs.add(e.ref);
    s[`${e.payload.clean === true ? 'clean' : 'flagged'}_${events[at].payload.status === 'pass' ? 'pass' : 'fail'}`] += 1;
  });
  let reason = 'ok';
  // Only a clean digest tests the false-pass hypothesis, so eligibility counts clean pairs (and the
  // rides they cover) alone; flagged pairs are reported but never count toward promotion.
  const cleanPairs = s.clean_pass + s.clean_fail;
  if (cleanPairs < PROMOTION_MIN_PAIRS) reason = 'min-pairs';
  else if (s.cleanRefs.size < PROMOTION_MIN_RIDES) reason = 'min-rides';
  else if (s.clean_fail > 0) reason = 'clean-fail';
  const { cleanRefs, ...out } = s;
  return { ...out, rides: s.refs.size, reason };
}

function runScore(flags) {
  const eventsPath = typeof flags.events === 'string' ? path.resolve(flags.events) : path.join(process.cwd(), 'docs/ai/EVENTS.jsonl');
  let events = [];
  try { ({ events } = readEvents(eventsPath)); } catch (err) { console.error(`evidence-digest: cannot read ${eventsPath} (${err.code ?? err.message})`); return 3; }
  const r = scoreEvents(events);
  const eligible = r.reason === 'ok';
  if (flags.json === true) {
    console.log(JSON.stringify({ pairs: r.pairs, rides: r.rides, clean_pass: r.clean_pass, clean_fail: r.clean_fail,
      flagged_pass: r.flagged_pass, flagged_fail: r.flagged_fail, unpaired: r.unpaired,
      promotion: eligible ? 'eligible' : 'not-eligible', reason: r.reason }));
    return 0;
  }
  console.log(`SCORE pairs=${r.pairs} rides=${r.rides} clean_pass=${r.clean_pass} clean_fail=${r.clean_fail} `
    + `flagged_pass=${r.flagged_pass} flagged_fail=${r.flagged_fail} unpaired=${r.unpaired}`);
  console.log(`PROMOTION ${eligible ? 'eligible' : 'not-eligible'} reason=${r.reason}`);
  return 0;
}

function main(argv) {
  const cmd = argv[0];
  if (cmd !== 'run' && cmd !== 'score') {
    console.error('usage: evidence-digest.mjs run --ref <ref> [--spec <path>] [--record] [--root <dir>] | score [--events <path>] [--json]');
    return 2;
  }
  const flags = parseFlags(argv.slice(1));
  return cmd === 'run' ? runDigest(flags) : runScore(flags);
}

const realOrResolve = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  process.exitCode = main(process.argv.slice(2));
}
