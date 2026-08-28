#!/usr/bin/env node
// validation-waiver.mjs — the aai-pr VALIDATION precondition, made executable
// (CHANGE-0167-operator-waiver-unblocks-pr, ceremony_level 1).
//
// THE BLOCKER: .aai/SKILL_PR.prompt.md refused unless
// `last_validation.status` is `pass`, and state.mjs accepts only
// `pass | fail | not_run` there. An operator who validated the change
// themselves had two routes to a PR — buy a validation round, or record a
// `pass` for a run that never happened. The second is a lie the ledger can
// never un-tell.
//
// THE EXIT: the status keeps saying what happened (`not_run` — nothing ran)
// and a STRUCTURED WAIVER RECORD in `last_validation.notes` says what was
// decided about it. `state.mjs` already accepts `--notes` on `set-validation`,
// so nothing in the state engine (a protected L3 surface) changes.
//
//   node .aai/scripts/state.mjs set-validation --status not_run --ref <ref> \
//     --notes '[AAI-VALIDATION-WAIVER v1 by=operator at=2026-08-28T17:00:00Z reason="operator ran the suite by hand; buying a second round is not worth it"]'
//
// GRAMMAR (v1) — exactly one record, on one line:
//
//   [AAI-VALIDATION-WAIVER v1 by=<operator|agent> at=<YYYY-MM-DDTHH:MM:SSZ> reason="<text>"]
//
// Every element is load-bearing, and the shape is chosen so PROSE CANNOT
// PRODUCE IT BY ACCIDENT: a bracketed all-caps sentinel nobody types in a
// sentence, a version token, three REQUIRED keys in a FIXED order, a closed
// two-value `by` set, a calendar-valid UTC instant, and a double-quoted
// reason. A sentence that merely says "validation waived by the operator"
// matches nothing and blocks exactly as a bare `not_run` does.
//
// WHO waived is read ONLY from `by=` in the record. It is NEVER inferred from
// the environment: `AAI_ROLE` was measured UNSET in this repo on a dispatch
// that mandated it, so it cannot carry an accountability claim.
//
// FAIL-CLOSED everywhere: a record whose sentinel is PRESENT but whose
// grammar is not satisfied (missing reason, empty reason, bad instant, two
// records) is REFUSED — never downgraded to "no waiver was intended" and
// never accepted. `fail` is never waivable; only `not_run` is.
//
// The notes field is written by state-engine's textFieldLines as a FOLDED
// block scalar (`>-`), which YAML re-joins with single spaces — so the reader
// below folds the same way, and the grammar stays single-line.
//
// Usage:
//   node .aai/scripts/validation-waiver.mjs --state docs/ai/STATE.yaml [--json]
//   node .aai/scripts/validation-waiver.mjs --notes '<text>' [--status <s>] [--json]
//
// Exit codes: 0 gate OPEN | 1 gate BLOCKED (incl. unreadable state) | 2 usage.
// Zero dependencies (Node stdlib only, per docs/TECHNOLOGY.md).

import { readFileSync, existsSync } from 'node:fs';

export const WAIVER_SENTINEL = 'AAI-VALIDATION-WAIVER';
const SENTINEL_RE = /\[AAI-VALIDATION-WAIVER\b/g;
const RECORD_RE = /\[AAI-VALIDATION-WAIVER v1 by=(operator|agent) at=(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) reason="([^"]*)"\]/g;
const BY_VALUES = ['operator', 'agent'];

// A syntactically well-formed instant is not necessarily a real one
// (2026-13-45T99:00:00Z parses the regex fine). Round-tripping through Date
// rejects every impossible calendar value without a date library.
function isRealInstant(at) {
  const ms = Date.parse(at);
  if (Number.isNaN(ms)) return false;
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z') === at;
}

// parseWaiver(text) -> a closed verdict about ONE piece of note text.
//   { present:false }                              — no sentinel anywhere
//   { present:true, ok:false, error:<code> }       — refused, code names why
//   { present:true, ok:true, by, at, reason }      — a usable waiver
export function parseWaiver(text) {
  const s = String(text ?? '');
  SENTINEL_RE.lastIndex = 0;
  const sentinels = s.match(SENTINEL_RE);
  if (!sentinels) return { present: false, ok: false, error: null };
  RECORD_RE.lastIndex = 0;
  const found = [...s.matchAll(RECORD_RE)];
  // A sentinel the grammar cannot fully parse is a BROKEN waiver, not a
  // missing one — refusing it is what keeps a half-typed record from reading
  // as "no waiver intended" and silently taking the bare-not_run path.
  if (found.length === 0) return { present: true, ok: false, error: 'waiver_malformed' };
  if (found.length !== sentinels.length || found.length > 1) {
    return { present: true, ok: false, error: 'waiver_ambiguous' };
  }
  const [, by, at, reason] = found[0];
  if (!BY_VALUES.includes(by)) return { present: true, ok: false, error: 'waiver_unknown_actor' };
  if (!isRealInstant(at)) return { present: true, ok: false, error: 'waiver_bad_instant' };
  if (reason.trim() === '') return { present: true, ok: false, error: 'waiver_empty_reason' };
  return { present: true, ok: true, error: null, by, at, reason: reason.trim() };
}

// scanWaivers(text) -> every well-formed record in `text`, plus a count of
// sentinels the grammar rejected. Used by the factory report, which reads
// many rides' notes and must never silently drop a broken record.
export function scanWaivers(text) {
  const s = String(text ?? '');
  SENTINEL_RE.lastIndex = 0;
  const sentinels = (s.match(SENTINEL_RE) || []).length;
  RECORD_RE.lastIndex = 0;
  const records = [];
  for (const m of s.matchAll(RECORD_RE)) {
    const [, by, at, reason] = m;
    if (!isRealInstant(at) || reason.trim() === '') continue;
    records.push({ by, at, reason: reason.trim() });
  }
  return { records, rejected: Math.max(0, sentinels - records.length) };
}

function unquoteScalar(v) {
  const t = String(v).trim();
  if (t === '' || t === 'null' || t === '~') return '';
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.slice(1, -1);
  }
  return t;
}

// readValidationBlock(yamlText) -> { status, notes } for the top-level
// `last_validation:` block, or null when the block is absent. Indentation-
// scoped line reader in the same zero-dependency discipline lane-gate.mjs
// uses for `implementation_strategy`. Block scalars are FOLDED with single
// spaces, matching how YAML itself reads the `>-` form state.mjs writes.
export function readValidationBlock(yamlText) {
  const lines = String(yamlText).replace(/\r\n?/g, '\n').split('\n');
  let i = 0;
  while (i < lines.length && !/^last_validation\s*:/.test(lines[i])) i += 1;
  if (i >= lines.length) return null;
  const out = { status: null, notes: '' };
  for (i += 1; i < lines.length; i += 1) {
    const raw = lines[i];
    if (raw.trim() === '') continue;
    const indent = raw.length - raw.trimStart().length;
    if (indent === 0) break;
    if (indent !== 2) continue;
    const line = raw.trim();
    const st = line.match(/^status\s*:\s*(.+)$/);
    if (st) { out.status = unquoteScalar(st[1]); continue; }
    const nt = line.match(/^notes\s*:\s*(.*)$/);
    if (!nt) continue;
    const head = nt[1].trim();
    if (/^[|>][-+]?\d*$/.test(head) && head !== '') {
      const segs = [];
      let j = i + 1;
      for (; j < lines.length; j += 1) {
        if (lines[j].trim() === '') continue;
        if (lines[j].length - lines[j].trimStart().length <= 2) break;
        segs.push(lines[j].trim());
      }
      out.notes = segs.join(' ');
      i = j - 1;
      continue;
    }
    out.notes = unquoteScalar(head);
  }
  return out;
}

// evaluateGate({status, notes}) -> the PR precondition verdict.
// `pass` opens it as it always did. `not_run` opens it ONLY with a well-formed
// waiver. Everything else — `fail`, an unknown status, a broken waiver —
// blocks. A waiver never overrides a recorded FAIL: nothing here lowers a bar.
export function evaluateGate(block) {
  if (!block || block.status === null) {
    return { open: false, reason: 'validation_block_unreadable', waiver: null, status: null };
  }
  const status = block.status;
  if (status === 'pass') return { open: true, reason: 'validation_pass', waiver: null, status };
  if (status !== 'not_run') {
    return { open: false, reason: `validation_${status}`, waiver: null, status };
  }
  const w = parseWaiver(block.notes);
  if (!w.present) return { open: false, reason: 'validation_not_run_no_waiver', waiver: null, status };
  if (!w.ok) return { open: false, reason: w.error, waiver: null, status };
  return {
    open: true,
    reason: w.by === 'operator' ? 'waived_by_operator' : 'self_waived_by_agent',
    waiver: { by: w.by, at: w.at, reason: w.reason },
    status,
  };
}

function usage(msg) {
  console.error(`validation-waiver: ${msg}`);
  console.error('usage: validation-waiver.mjs (--state <STATE.yaml> | --notes <text> [--status <s>]) [--json]');
  process.exit(2);
}

function main(argv) {
  const opts = { state: null, notes: null, status: 'not_run', json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--state') { opts.state = argv[++i]; if (opts.state === undefined) usage('--state needs a path'); }
    else if (a === '--notes') { opts.notes = argv[++i]; if (opts.notes === undefined) usage('--notes needs a value'); }
    else if (a === '--status') { opts.status = argv[++i]; if (opts.status === undefined) usage('--status needs a value'); }
    else if (a === '--json') opts.json = true;
    else if (a === '-h' || a === '--help') usage('help');
    else usage(`unknown flag ${a}`);
  }
  if (opts.state === null && opts.notes === null) usage('one of --state / --notes is required');

  let block;
  if (opts.state !== null) {
    if (!existsSync(opts.state)) {
      // Fail CLOSED: an absent state file is not an open gate.
      console.log(`VALIDATION-GATE blocked reason=state_unreadable state=${opts.state}`);
      process.exit(1);
    }
    block = readValidationBlock(readFileSync(opts.state, 'utf8'));
  } else {
    block = { status: opts.status, notes: opts.notes };
  }

  const v = evaluateGate(block);
  if (opts.json) {
    console.log(JSON.stringify({ ...v }, null, 2));
    process.exit(v.open ? 0 : 1);
  }
  console.log(`VALIDATION-GATE ${v.open ? 'open' : 'blocked'} reason=${v.reason}`);
  console.log(`status=${v.status ?? 'absent'}`);
  if (v.waiver) {
    console.log(`waiver_by=${v.waiver.by} waiver_at=${v.waiver.at}`);
    console.log(`waiver_reason=${v.waiver.reason}`);
  }
  process.exit(v.open ? 0 : 1);
}

// Only run the CLI when invoked directly — the factory report imports the
// parser from here (one grammar, two consumers).
if (process.argv[1] && process.argv[1].endsWith('validation-waiver.mjs')) {
  main(process.argv.slice(2));
}
