// Shared classifier for the shipped shell and PowerShell scripts under .aai/scripts
// (docs/specs/SPEC-DRAFT-spec-node-first-phase5-closeout.md D-CLASS). One reading of the
// plan's section 1 method (docs/analysis/node-first-remaining-plan.md) and of the
// "Kept native scripts" table of RFC-0017. Test-only; Node stdlib.
//
// CLI: node tests/skills/lib/script-classes.mjs strict --root <dir> [--files-from <list>]
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const LAUNCHER_MAX_CODE_LINES = 20;
export const POLICY_TOKENS = [/\bgit\b/, /\.gitignore/, /PROFILES/, /--profile\b|-Profile\b/];
export const KEPT_NATIVE_HEADING = '### Kept native scripts';

// Lines that are not blank and whose first non-space character is not '#'.
export function countCodeLines(text) {
  return codeLines(text).length;
}

function codeLines(text) {
  return text.split('\n').filter((l) => !/^\s*(#|$)/.test(l));
}

function namesPolicy(text) {
  return codeLines(text).some((l) => POLICY_TOKENS.some((re) => re.test(l)));
}

function isRetired(text) {
  return text.split('\n').slice(0, 3).some((l) => /^#\s*RETIRED\b/.test(l));
}

// Every table row under the heading, as { file, reason, line }; an empty reason is kept.
export function parseKeptNative(rfcText) {
  const lines = rfcText.split('\n');
  const at = lines.findIndex((l) => l === KEPT_NATIVE_HEADING);
  const rows = [];
  if (at < 0) return rows;
  for (let i = at + 1; i < lines.length && !lines[i].startsWith('#'); i += 1) {
    const m = /^\|\s*`([^`]+)`\s*\|(.*)\|\s*$/.exec(lines[i]);
    if (m) rows.push({ file: m[1], reason: m[2].trim(), line: i + 1 });
  }
  return rows;
}

function keptMap(kept) {
  const map = new Map();
  for (const r of kept || []) if (!map.has(r.file)) map.set(r.file, r);
  return map;
}

export function classify({ file, text, kept }) {
  if (isRetired(text)) return 'deprecation launcher';
  const row = keptMap(kept).get(file);
  if (row && row.reason !== '') return 'kept native';
  if (countCodeLines(text) <= LAUNCHER_MAX_CODE_LINES && !namesPolicy(text)) return 'launcher';
  return 'logic';
}

export function strictProblems({ files, read, kept }) {
  const problems = [];
  for (const file of files) {
    const text = read(file);
    const cls = classify({ file, text, kept });
    if (cls === 'logic') problems.push(`logic: ${file} (${countCodeLines(text)} code lines, not a launcher and not a kept-native row)`);
    if (cls === 'deprecation launcher') {
      const n = countCodeLines(text);
      if (n > LAUNCHER_MAX_CODE_LINES) problems.push(`deprecation launcher over ${LAUNCHER_MAX_CODE_LINES} code lines: ${file} (${n})`);
      if (namesPolicy(text)) problems.push(`deprecation launcher names a policy token: ${file}`);
    }
  }
  const seen = new Map();
  const set = new Set(files);
  for (const r of kept || []) {
    if (r.reason === '') problems.push(`kept-native row with an empty reason: ${r.file} (RFC line ${r.line})`);
    if (!set.has(r.file)) problems.push(`kept-native row names a file outside the list: ${r.file} (RFC line ${r.line})`);
    if (seen.has(r.file)) problems.push(`kept-native file named by two rows: ${r.file} (RFC lines ${seen.get(r.file)} and ${r.line})`);
    else seen.set(r.file, r.line);
  }
  return problems;
}

// ---- readers of the dated closeout record (node-first-phase5-closeout, code review r1: B2, N1) ----
// A re-measure section of the plan is a dated record. These readers check it against the measurement and the ledger AS OF THE
// RECORD, so a later change of state (a follow-up closed by another ride, a retirement launcher deleted at its scheduled release, an
// edit to a kept-native script) does not turn an unrelated pull request red; the live guard of the tree is the strict check above.

// The file table rows [file, code lines, class, reason] of a record against the measured non-launcher rows of the tree
// ({ file, code, cls }). Counts are the record's own measurement and are not compared with the live tree; the file and its class are.
// A listed deprecation launcher missing from the tree is the scheduled deletion and is fine. tree = null checks only the shape.
export function fileTableProblems({ rows, tree }) {
  const problems = [];
  const byFile = new Map((tree || []).map((r) => [r.file, r]));
  const seen = new Set();
  let prev = '';
  for (const c of rows) {
    const file = c[0].replace(/`/g, '');
    if (seen.has(file)) problems.push(`the file table lists ${file} twice`);
    if (file < prev) problems.push(`the file table is not sorted by file at ${file}`);
    prev = file;
    seen.add(file);
    if (!/^[0-9]+$/.test(c[1])) problems.push(`the file table row ${file} has no integer code line count: ${c[1]}`);
    if (!['deprecation launcher', 'kept native', 'logic'].includes(c[2])) problems.push(`the file table row ${file} has an unknown class: ${c[2]}`);
    if (!c[3]) problems.push(`the file table row ${file} has no reason`);
    if (!tree) continue;
    const live = byFile.get(file);
    if (!live) { if (c[2] !== 'deprecation launcher') problems.push(`the file table lists ${file} (${c[2]}), which is not a non-launcher script of the tree`); }
    else if (live.cls !== c[2]) problems.push(`the file table lists ${file} as ${c[2]}, the tree classifies it ${live.cls}`);
  }
  if (tree) for (const r of tree) if (!seen.has(r.file)) problems.push(`the tree holds the non-launcher script ${r.file} (${r.cls}), absent from the file table`);
  return problems;
}

// The ledger records written up to the end of the day (UTC) the record is dated.
export function recordsThroughDate(records, isoDate) {
  const end = `${isoDate}T23:59:59Z`;
  return records.filter((r) => r && typeof r.ts === 'string' && r.ts <= end);
}

// The first follow_up record filing the id, and the last follow_up_status record of the id written by the ride.
export function filingRecord(records, id) {
  return records.find((r) => r && r.type === 'follow_up' && r.id === id) || null;
}
export function rideStatusRecord(records, id, self) {
  let hit = null;
  for (const r of records) if (r && r.type === 'follow_up_status' && r.id === id && r.resolved_by === self) hit = r;
  return hit;
}

// The owner-downgrade state of the odd-root item as this ride recorded it (D-ODD step 6, owner decision 2026-11-23): dropped by the ride
// as superseded by a P3 successor that was filed before the drop, with a hitl_decision of the ride naming the downgrade. It reads the
// records, not the live registry, so a later close of the successor is not a failure.
export function oddDropProblems(records, self) {
  const DIRS = 'fu-parity-win-odd-root-dirs';
  const CAUSE = 'fu-parity-win-odd-root-cause';
  const errs = [];
  const drop = rideStatusRecord(records, DIRS, self);
  if (!drop) errs.push(`no follow_up_status record of ${self} closes ${DIRS}`);
  else {
    if (drop.status !== 'dropped') errs.push(`${DIRS} is closed by the ride as ${drop.status}, not dropped as superseded by the owner downgrade`);
    if (!String(drop.source ?? '').includes(CAUSE)) errs.push(`the odd-root close source does not name its P3 successor ${CAUSE}: ${drop.source}`);
  }
  const fil = filingRecord(records, CAUSE);
  if (!fil) errs.push(`the successor ${CAUSE} was never filed`);
  else {
    if (fil.severity !== 'P3') errs.push(`the successor ${CAUSE} was filed at ${fil.severity}, not P3`);
    if (drop && String(fil.ts) > String(drop.ts)) errs.push(`the successor ${CAUSE} was filed after the drop of ${DIRS}`);
  }
  const hitl = records.filter((r) => r && r.type === 'hitl_decision' && r.ref_id === self && new RegExp(DIRS).test(String(r.decision)) && /P3/.test(String(r.decision)) && new RegExp(CAUSE).test(String(r.decision)));
  if (!hitl.length) errs.push(`no hitl_decision of ${self} names the downgrade of ${DIRS} to P3 with its successor`);
  return errs;
}

function listFiles(root, filesFrom) {
  if (filesFrom) return fs.readFileSync(filesFrom, 'utf8').split('\n').map((l) => l.trim()).filter(Boolean);
  const out = execFileSync('git', ['-C', root, 'ls-files', '-z', '--', '.aai/scripts'], { encoding: 'utf8' });
  return out.split('\0').filter((f) => f.endsWith('.sh') || f.endsWith('.ps1'));
}

function main(argv) {
  const [cmd, ...rest] = argv;
  const opt = {};
  for (let i = 0; i < rest.length; i += 2) opt[rest[i]] = rest[i + 1];
  if (cmd !== 'strict' || !opt['--root']) {
    process.stderr.write('usage: script-classes.mjs strict --root <dir> [--files-from <list>]\n');
    return 2;
  }
  const root = path.resolve(opt['--root']);
  const files = listFiles(root, opt['--files-from']);
  if (files.length === 0) { process.stderr.write('no script files found\n'); return 2; }
  const rfc = fs.readFileSync(path.join(root, 'docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md'), 'utf8');
  const problems = strictProblems({ files, read: (f) => fs.readFileSync(path.join(root, f), 'utf8'), kept: parseKeptNative(rfc) });
  for (const p of problems) process.stdout.write(`${p}\n`);
  return problems.length === 0 ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2));
