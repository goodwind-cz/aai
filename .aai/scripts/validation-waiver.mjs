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
//   node .aai/scripts/state.mjs set-validation --status not_run --ref CHANGE-0167 \
//     --notes '[AAI-VALIDATION-WAIVER v2 by=operator ref=CHANGE-0167 at=2026-08-28T17:00:00Z reason="operator ran the suite by hand; buying a second round is not worth it"]'
//
// GRAMMAR (v2) — exactly one record, on one line:
//
//   [AAI-VALIDATION-WAIVER v2 by=<operator|agent> ref=<REF-ID> at=<YYYY-MM-DDTHH:MM:SSZ> reason="<text>"]
//
// Every element is load-bearing, and the shape is chosen so PROSE CANNOT
// PRODUCE IT BY ACCIDENT: a bracketed all-caps sentinel nobody types in a
// sentence, a version token, four REQUIRED keys in a FIXED order, a closed
// two-value `by` set, a scope ref, a calendar-valid UTC instant, and a
// double-quoted reason. A sentence that merely says "validation waived by the
// operator" matches nothing and blocks exactly as a bare `not_run` does.
//
// WHY `ref=` EXISTS (v1 -> v2, bot review PR #303 F-1). `state.mjs
// set-validation --status not_run --ref <other-ref>` REWRITES `status` and
// `ref_id` but PRESERVES the previous `notes`. Under v1 the evaluator read the
// note without ever consulting a ref, so once ride A was waived, ride B's bare
// `not_run` inherited A's waiver and opened the gate on a decision nobody made
// for B. v2 makes the record NAME the scope it was issued for, and the gate
// refuses a record that does not match the scope in hand — by the NAMED reason
// `waiver_ref_mismatch`, never as a silent "no waiver".
//
// A v1 RECORD FOUND IN THE WILD IS REFUSED, LOUDLY, BY NAME
// (`waiver_obsolete_version`) — never honoured, and never degraded to
// `waiver_malformed`, because "this waiver predates the scope binding" is a
// different fact from "somebody mistyped a record" and the operator needs to
// be told which one they are looking at. A v1 record can be re-issued as v2 by
// adding the ref it was always implicitly about; nothing about it is honoured
// by accident in the meantime.
//
// WHO waived is read ONLY from `by=` in the record. It is NEVER inferred from
// the environment: `AAI_ROLE` was measured UNSET in this repo on a dispatch
// that mandated it, so it cannot carry an accountability claim.
//
// FAIL-CLOSED everywhere: a record whose sentinel is PRESENT but whose
// grammar is not satisfied (missing reason, empty reason, bad instant, an
// obsolete version, two records) is REFUSED — never downgraded to "no waiver
// was intended" and never accepted. `fail` is never waivable; only `not_run`
// is. Both consumers of the grammar (this gate and the factory report) route
// through `parseWaiver`, so the report can never accept a shape the gate
// refuses.
//
// The notes field is written by state-engine's textFieldLines as a FOLDED
// block scalar (`>-`), which YAML re-joins with single spaces — so the reader
// below folds the same way, and the grammar stays single-line.
//
// ---------------------------------------------------------------------------
// THE ARCHIVE LANE (spec-metrics-flush-invalidates-pr-precondition)
//
// `metrics-flush.mjs` ARCHIVES a ride's PASS into `docs/ai/METRICS.jsonl` and
// resets `last_validation` to `not_run` — designed behaviour, since the
// durable record moved. But this gate reads the live fields, so a flush that
// runs before SKILL_PR blocked the ship path with
// `validation_not_run_no_waiver`: "this ride never validated", which is false,
// with the PASS sitting in the ledger a directory away.
//
// So `not_run` has a SECOND opening: a durable ARCHIVE RECORD the flush leaves
// in the reset note, cross-checked against the ledger it wrote in the same
// transaction. This is a second EVIDENCE SOURCE inside the one predicate, not
// a second decider — `evaluateGate` remains the single executable authority,
// with one call site and one exit-code contract.
//
// GRAMMAR (v1) — one record per reset ref, on one line, same folded-scalar
// discipline as the waiver, and rendered only through `formatArchive`:
//
//   [AAI-VALIDATION-ARCHIVED v1 ref=<REF-ID> at=<YYYY-MM-DDTHH:MM:SSZ>]
//
// The lane opens ONLY when all three bindings hold, and each has a job:
//   1. REF — exactly one record matching the scope in hand (the same
//      `refMatchesScope` binding waiver v2 established, for the same reason:
//      a record must never be honoured for a ride nobody issued it for).
//   2. RECENCY — `at` BYTE-EQUAL to `last_validation.run_at_utc`. This is what
//      makes the record UN-INHERITABLE. `state.mjs set-validation` re-stamps
//      `run_at_utc` on every call carrying a `--status` while PRESERVING
//      `notes`, so the moment any later ride writes a status the inherited
//      record goes stale and this lane refuses. (`reset-block` cannot defeat
//      it either: it is a documented no-op when the status is already
//      `not_run`, which is exactly the post-flush state.)
//   3. LEDGER PROOF — exactly one `verdict: PASS` entry in METRICS.jsonl for
//      that scope on `at`'s own day. The record is a CLAIM; the ledger entry
//      is the PROOF, and it is a proof worth trusting because metrics-flush
//      refuses to build one unless the PASS named the ref and code_review was
//      pass-or-waived when required.
//
// PRECEDENCE — the lane may only ever OPEN. If it does not, the waiver lane
// runs BYTE-FOR-BYTE as it did before, every existing refusal token included;
// the archive's own named refusal is surfaced ONLY where the waiver lane would
// otherwise have printed the generic `validation_not_run_no_waiver`. This is
// not cosmetic: the flush PRESERVES an unflushed waiver into the very note it
// writes archive records to, and such a waiver names a ref that was NOT
// flushed — a different ref from every record beside it. An
// archive-decides-terminally rule would have blocked a scope whose own
// preserved waiver opens the gate today.
//
// FAIL-CLOSED, exactly as the waiver lane is: a sentinel that is PRESENT but
// whose grammar is not satisfied is REFUSED by name (`archive_malformed`),
// never degraded to "no record was intended"; a NON-CURRENT version is
// `archive_obsolete_version`, because "this predates the binding" and
// "somebody mistyped" are different facts. Unparseable LEDGER lines are
// skipped rather than fatal — skipping can only ever make the gate more
// closed. `fail` is still never openable; nothing here lowers a bar.
//
// A waiver would have been the zero-code shortcut and is WRONG: a waiver
// asserts "nothing ran and we proceeded anyway", while here validation ran and
// PASSED. Recording a pass as a self-waiver would corrupt every waiver count
// the factory report shows and make every flushed ride read as self-waived.
// ---------------------------------------------------------------------------
//
// Usage:
//   node .aai/scripts/validation-waiver.mjs --state docs/ai/STATE.yaml [--metrics <path>] [--json]
//   node .aai/scripts/validation-waiver.mjs --notes '<text>' [--status <s>] [--ref <scope>] [--json]
//
// `--metrics` defaults to `METRICS.jsonl` beside the `--state` path (never the
// CWD, or every fixture would silently read the real ledger).
//
// Exit codes: 0 gate OPEN | 1 gate BLOCKED (incl. unreadable state) | 2 usage.
// Zero dependencies (Node stdlib only, per docs/TECHNOLOGY.md).

import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

export const WAIVER_SENTINEL = 'AAI-VALIDATION-WAIVER';
export const WAIVER_VERSION = 2;
const SENTINEL_RE = /\[AAI-VALIDATION-WAIVER\b/g;
// The version token, read on its own so a NON-CURRENT version is refused by
// its own name rather than falling through to "malformed".
const VERSION_RE = /\[AAI-VALIDATION-WAIVER v(\d+)\b/g;
// `ref` deliberately excludes `/`: one waiver names ONE scope, and a slash is
// how STATE joins several refs into one `ref_id` — allowing it here would make
// the scope comparison below ambiguous.
const REF_TOKEN = '[A-Za-z0-9][A-Za-z0-9._-]*';
const RECORD_RE = new RegExp(
  `\\[AAI-VALIDATION-WAIVER v${WAIVER_VERSION} by=(operator|agent) ref=(${REF_TOKEN}) `
  + 'at=(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z) reason="([^"]*)"\\]',
  'g',
);
const BY_VALUES = ['operator', 'agent'];

export const ARCHIVE_SENTINEL = 'AAI-VALIDATION-ARCHIVED';
export const ARCHIVE_VERSION = 1;
const ARCHIVE_SENTINEL_RE = /\[AAI-VALIDATION-ARCHIVED\b/g;
const ARCHIVE_VERSION_RE = /\[AAI-VALIDATION-ARCHIVED v(\d+)\b/g;
// Same `REF_TOKEN` as the waiver, and for the same reason: one record names
// ONE scope, and `/` is how STATE joins several refs into one `ref_id`.
const ARCHIVE_RECORD_RE = new RegExp(
  `\\[AAI-VALIDATION-ARCHIVED v${ARCHIVE_VERSION} ref=(${REF_TOKEN}) `
  + 'at=(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z)\\]',
  'g',
);

// A syntactically well-formed instant is not necessarily a real one
// (2026-13-45T99:00:00Z parses the regex fine). Round-tripping through Date
// rejects every impossible calendar value without a date library.
function isRealInstant(at) {
  const ms = Date.parse(at);
  if (Number.isNaN(ms)) return false;
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z') === at;
}

// formatWaiver({by, ref, at, reason}) -> the record TEXT, or null when the
// fields cannot be rendered into a record this file's own grammar would parse
// back. The single writer for the grammar: every place that needs to put a
// waiver back on the wire (the flush's durable ledger field, the preserved
// reset note) goes through here, so a producer can never emit a shape the
// reader refuses.
export function formatWaiver(w) {
  if (!w || typeof w !== 'object') return null;
  const by = String(w.by ?? '');
  const ref = String(w.ref ?? w.ref_id ?? '');
  const at = String(w.at ?? '');
  const reason = String(w.reason ?? '');
  const text = `[${WAIVER_SENTINEL} v${WAIVER_VERSION} by=${by} ref=${ref} at=${at} reason="${reason}"]`;
  const back = parseWaiver(text);
  return back.ok ? text : null;
}

// parseWaiver(text) -> a closed verdict about ONE piece of note text.
//   { present:false, ok:false, error:null }              — no sentinel anywhere
//   { present:true,  ok:false, error:<code> }            — refused, code names why
//   { present:true,  ok:true,  error:null, by, ref, at, reason }
//                                                        — a usable waiver
// The `present:false` shape carries ok/error too so EVERY return of this
// function has the same keys — a caller that reads `.ok` on the no-sentinel
// result gets `false`, not `undefined` (bot review PR #303 F-5: the comment
// used to promise a bare `{present:false}` the code never returned).
export function parseWaiver(text) {
  const s = String(text ?? '');
  SENTINEL_RE.lastIndex = 0;
  const sentinels = s.match(SENTINEL_RE);
  if (!sentinels) return { present: false, ok: false, error: null };
  // Version FIRST: a v1 record is a waiver written under the pre-scope-binding
  // grammar. Refusing it by its own name is what keeps it from being honoured
  // by accident and from being mistaken for a typo.
  VERSION_RE.lastIndex = 0;
  const versions = [...s.matchAll(VERSION_RE)];
  if (versions.some((m) => Number(m[1]) !== WAIVER_VERSION)) {
    return { present: true, ok: false, error: 'waiver_obsolete_version' };
  }
  RECORD_RE.lastIndex = 0;
  const found = [...s.matchAll(RECORD_RE)];
  // A sentinel the grammar cannot fully parse is a BROKEN waiver, not a
  // missing one — refusing it is what keeps a half-typed record from reading
  // as "no waiver intended" and silently taking the bare-not_run path.
  if (found.length === 0) return { present: true, ok: false, error: 'waiver_malformed' };
  if (found.length !== sentinels.length || found.length > 1) {
    return { present: true, ok: false, error: 'waiver_ambiguous' };
  }
  const [, by, ref, at, reason] = found[0];
  if (!BY_VALUES.includes(by)) return { present: true, ok: false, error: 'waiver_unknown_actor' };
  if (!isRealInstant(at)) return { present: true, ok: false, error: 'waiver_bad_instant' };
  if (reason.trim() === '') return { present: true, ok: false, error: 'waiver_empty_reason' };
  return { present: true, ok: true, error: null, by, ref, at, reason: reason.trim() };
}

// formatArchive({ref, at}) -> the record TEXT, or null when the fields cannot
// be rendered into a record this file's own grammar would parse back. The
// SINGLE writer for the archive grammar, the same discipline formatWaiver
// establishes: metrics-flush.mjs renders through here, so the producer can
// never emit a shape this reader refuses.
export function formatArchive(a) {
  if (!a || typeof a !== 'object') return null;
  const ref = String(a.ref ?? a.ref_id ?? '');
  const at = String(a.at ?? '');
  const text = `[${ARCHIVE_SENTINEL} v${ARCHIVE_VERSION} ref=${ref} at=${at}]`;
  const back = parseArchive(text);
  return back.ok ? text : null;
}

// parseArchive(text) -> a closed verdict about the archive records ONE piece of
// note text carries. Same three-shape contract as parseWaiver, plus `records`:
//   { present:false, ok:false, error:null, records:[] }   — no sentinel anywhere
//   { present:true,  ok:false, error:<code>, records:[] } — refused, code names why
//   { present:true,  ok:true,  error:null, records:[{ref,at},...] }
// A partial reset can name SEVERAL refs, so a well-formed note carries one
// record per ref; the scope in hand selects which one is read. Two records for
// the SAME ref is `archive_ambiguous` — picking one would decide silently.
export function parseArchive(text) {
  const s = String(text ?? '');
  ARCHIVE_SENTINEL_RE.lastIndex = 0;
  const sentinels = s.match(ARCHIVE_SENTINEL_RE);
  if (!sentinels) return { present: false, ok: false, error: null, records: [] };
  // Version FIRST, by its own name: a future-version record is not a typo.
  ARCHIVE_VERSION_RE.lastIndex = 0;
  const versions = [...s.matchAll(ARCHIVE_VERSION_RE)];
  if (versions.some((m) => Number(m[1]) !== ARCHIVE_VERSION)) {
    return { present: true, ok: false, error: 'archive_obsolete_version', records: [] };
  }
  ARCHIVE_RECORD_RE.lastIndex = 0;
  const found = [...s.matchAll(ARCHIVE_RECORD_RE)];
  // A sentinel the grammar cannot fully parse is a BROKEN record, not a
  // missing one — refusing it is what keeps a half-written record from reading
  // as "no archive intended" and silently taking the bare-not_run path.
  if (found.length === 0 || found.length !== sentinels.length) {
    return { present: true, ok: false, error: 'archive_malformed', records: [] };
  }
  const records = found.map(([, ref, at]) => ({ ref, at }));
  if (records.some((r) => !isRealInstant(r.at))) {
    return { present: true, ok: false, error: 'archive_malformed', records: [] };
  }
  const refs = records.map((r) => r.ref);
  if (new Set(refs).size !== refs.length) {
    return { present: true, ok: false, error: 'archive_ambiguous', records: [] };
  }
  return { present: true, ok: true, error: null, records };
}

// readArchiveLedger(metricsPath) -> the {ref_id, verdict, date_utc} triples
// docs/ai/METRICS.jsonl carries, or null when there is no readable ledger.
// Comment and blank lines are skipped as the flush itself skips them, and a
// line that is not parseable JSON is SKIPPED rather than fatal: a dropped
// line can only ever remove a proof, i.e. close the gate further.
export function readArchiveLedger(metricsPath) {
  if (typeof metricsPath !== 'string' || metricsPath === '') return null;
  if (!existsSync(metricsPath)) return null;
  const out = [];
  for (const line of readFileSync(metricsPath, 'utf8').split('\n')) {
    const t = line.trim();
    if (t === '' || t.startsWith('#')) continue;
    let e;
    try { e = JSON.parse(t); } catch { continue; }
    if (!e || typeof e !== 'object') continue;
    out.push({
      ref_id: typeof e.ref_id === 'string' ? e.ref_id : null,
      verdict: typeof e.verdict === 'string' ? e.verdict : null,
      date_utc: typeof e.date_utc === 'string' ? e.date_utc : null,
    });
  }
  return out;
}

// refMatchesScope(waiverRef, scopeRef) -> does the record name the scope in
// hand? `scopeRef` may be the `/`-joined multi-ref STATE writes when one
// validation verdict covers several work items (the same tolerance
// metrics-flush.mjs's refMatches applies).
export function refMatchesScope(waiverRef, scopeRef) {
  if (typeof waiverRef !== 'string' || waiverRef === '') return false;
  if (typeof scopeRef !== 'string' || scopeRef === '') return false;
  if (waiverRef === scopeRef) return true;
  return scopeRef.split('/').includes(waiverRef);
}

// scanWaivers(text) -> the waiver records `text` carries, plus a count of
// sentinels the grammar rejected. Used by the factory report, which reads many
// rides' notes and must never silently drop a broken record.
//
// It DELEGATES to parseWaiver rather than re-deciding (bot review PR #303 F-4:
// it used to accept `records.length > 1` with `rejected` still 0, so the
// report would have counted as valid exactly the ambiguous shape the gate
// refuses). One grammar, one verdict, fail-closed in both consumers: a refused
// note contributes ZERO records and every one of its sentinels to `rejected`.
export function scanWaivers(text) {
  const s = String(text ?? '');
  SENTINEL_RE.lastIndex = 0;
  const sentinels = (s.match(SENTINEL_RE) || []).length;
  const w = parseWaiver(s);
  if (!w.present) return { records: [], rejected: 0 };
  if (!w.ok) return { records: [], rejected: Math.max(1, sentinels) };
  return { records: [{ by: w.by, ref: w.ref, at: w.at, reason: w.reason }], rejected: 0 };
}

// normalizeWaiverRecord(obj) -> the record an already-structured field claims
// to be, re-checked THROUGH THE GRAMMAR (render, then parse back), or null.
// The durable ledger field written by metrics-flush.mjs is data on disk like
// any other; routing it back through the one grammar is what stops a
// hand-edited ledger from carrying a waiver the gate would have refused.
export function normalizeWaiverRecord(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const text = formatWaiver(obj);
  if (text === null) return null;
  const w = parseWaiver(text);
  return w.ok ? { by: w.by, ref: w.ref, at: w.at, reason: w.reason } : null;
}

function unquoteScalar(v) {
  const t = String(v).trim();
  if (t === '' || t === 'null' || t === '~') return '';
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.slice(1, -1);
  }
  return t;
}

// readIndentedBlock(yamlText, blockName) -> { <2-space key>: <scalar or folded
// text> } for one top-level block, or null when the block is absent.
// Indentation-scoped line reader in the same zero-dependency discipline
// lane-gate.mjs uses for `implementation_strategy`. Block scalars are FOLDED
// with single spaces, matching how YAML itself reads the `>-` form state.mjs
// writes.
function readIndentedBlock(yamlText, blockName) {
  const lines = String(yamlText).replace(/\r\n?/g, '\n').split('\n');
  const head = new RegExp(`^${blockName}\\s*:`);
  let i = 0;
  while (i < lines.length && !head.test(lines[i])) i += 1;
  if (i >= lines.length) return null;
  const out = {};
  for (i += 1; i < lines.length; i += 1) {
    const raw = lines[i];
    if (raw.trim() === '') continue;
    const indent = raw.length - raw.trimStart().length;
    if (indent === 0) break;
    if (indent !== 2) continue;
    const kv = raw.trim().match(/^([A-Za-z0-9_]+)\s*:\s*(.*)$/);
    if (!kv) continue;
    const [, key, rest] = kv;
    const value = rest.trim();
    if (/^[|>][-+]?\d*$/.test(value) && value !== '') {
      const segs = [];
      let j = i + 1;
      for (; j < lines.length; j += 1) {
        if (lines[j].trim() === '') continue;
        if (lines[j].length - lines[j].trimStart().length <= 2) break;
        segs.push(lines[j].trim());
      }
      out[key] = segs.join(' ');
      i = j - 1;
      continue;
    }
    out[key] = unquoteScalar(value);
  }
  return out;
}

// readValidationBlock(yamlText) -> { status, notes, ref_id, run_at_utc } for
// the top-level `last_validation:` block, or null when the block is absent.
// `ref_id` is the scope the recorded verdict names — the field the waiver must
// agree with; `run_at_utc` is the instant an archive record must match to be
// this ride's proof rather than an inherited one.
export function readValidationBlock(yamlText) {
  const b = readIndentedBlock(yamlText, 'last_validation');
  if (b === null) return null;
  return {
    status: b.status === undefined || b.status === '' ? null : b.status,
    notes: b.notes ?? '',
    ref_id: b.ref_id === undefined || b.ref_id === '' ? null : b.ref_id,
    run_at_utc: b.run_at_utc === undefined || b.run_at_utc === '' ? null : b.run_at_utc,
  };
}

// readFocusRef(yamlText) -> `current_focus.ref_id`, the FALLBACK scope used
// only when the validation block names none.
export function readFocusRef(yamlText) {
  const b = readIndentedBlock(yamlText, 'current_focus');
  if (b === null) return null;
  return b.ref_id === undefined || b.ref_id === '' ? null : b.ref_id;
}

// evaluateArchive(notes, scopeRef, runAtUtc, ledger) -> the archive lane's own
// verdict about ONE note, or null when the note carries no archive sentinel at
// all (i.e. the lane has nothing to say and does not exist for this input).
// Never called anywhere but from evaluateGate: the gate stays one predicate.
function evaluateArchive(notes, scopeRef, runAtUtc, ledger) {
  const a = parseArchive(notes);
  if (!a.present) return null;
  if (!a.ok) return { open: false, reason: a.error };
  // A record with no scope to check against is not a record we may honour —
  // the leak this binding closes is a record surviving into a context nobody
  // issued it for, and "there is no context" is that case at its worst.
  if (scopeRef === null) return { open: false, reason: 'archive_scope_unknown' };
  const matches = a.records.filter((r) => refMatchesScope(r.ref, scopeRef));
  if (matches.length === 0) {
    return { open: false, reason: 'archive_ref_mismatch', archive_ref: a.records.map((r) => r.ref).join(' ') };
  }
  if (matches.length > 1) return { open: false, reason: 'archive_ambiguous' };
  const rec = matches[0];
  // RECENCY. Byte equality, not tolerance: one instant, written into both
  // fields by one flush transaction. Anything else is an inherited record.
  if (rec.at !== runAtUtc) return { open: false, reason: 'archive_stale', archive_ref: rec.ref };
  const day = rec.at.slice(0, 10);
  const hits = (ledger ?? []).filter(
    (e) => e.verdict === 'PASS' && e.date_utc === day && refMatchesScope(e.ref_id, scopeRef),
  );
  if (hits.length === 0) return { open: false, reason: 'archive_no_ledger_pass', archive_ref: rec.ref };
  if (hits.length > 1) return { open: false, reason: 'archive_ledger_ambiguous', archive_ref: rec.ref };
  return { open: true, reason: 'validation_archived_pass', archive: { ref: rec.ref, at: rec.at } };
}

// evaluateGate({status, notes, ref_id, run_at_utc}, fallbackRef, ledger) -> the
// PR precondition verdict. `pass` opens it as it always did. `not_run` opens it
// on EITHER of two durable evidence sources: a well-formed waiver THAT NAMES
// THE SCOPE IN HAND, or an archive record whose ref, instant and ledger PASS
// all agree (see THE ARCHIVE LANE in the header). Everything else — `fail`, an
// unknown status, a broken record of either kind, a record issued for another
// ride — blocks. Neither source ever overrides a recorded FAIL: nothing here
// lowers a bar.
export function evaluateGate(block, fallbackRef = null, ledger = null) {
  if (!block || block.status === null) {
    return { open: false, reason: 'validation_block_unreadable', waiver: null, status: null, scope_ref: null };
  }
  const status = block.status;
  const scopeRef = block.ref_id ?? fallbackRef ?? null;
  if (status === 'pass') return { open: true, reason: 'validation_pass', waiver: null, status, scope_ref: scopeRef };
  if (status !== 'not_run') {
    return { open: false, reason: `validation_${status}`, waiver: null, status, scope_ref: scopeRef };
  }
  // The archive lane may only ever OPEN. When it does not, its NAMED refusal
  // is carried to the one position where the waiver lane would otherwise have
  // printed the generic `validation_not_run_no_waiver`, and every other waiver
  // outcome below runs byte-for-byte as it did before the lane existed.
  const archive = evaluateArchive(block.notes, scopeRef, block.run_at_utc ?? null, ledger);
  if (archive !== null && archive.open) {
    return { open: true, reason: archive.reason, waiver: null, status, scope_ref: scopeRef, archive: archive.archive };
  }
  const w = parseWaiver(block.notes);
  if (!w.present) {
    const blocked = {
      open: false,
      reason: archive === null ? 'validation_not_run_no_waiver' : archive.reason,
      waiver: null,
      status,
      scope_ref: scopeRef,
    };
    if (archive !== null && archive.archive_ref !== undefined) blocked.archive_ref = archive.archive_ref;
    return blocked;
  }
  if (!w.ok) return { open: false, reason: w.error, waiver: null, status, scope_ref: scopeRef };
  // Scope binding. A waiver with no scope to check against is NOT a waiver we
  // may honour — the leak this closes is precisely a record surviving into a
  // context nobody issued it for, and "there is no context" is that case at
  // its worst.
  if (scopeRef === null) {
    return { open: false, reason: 'waiver_scope_unknown', waiver: null, status, scope_ref: null, waiver_ref: w.ref };
  }
  if (!refMatchesScope(w.ref, scopeRef)) {
    return { open: false, reason: 'waiver_ref_mismatch', waiver: null, status, scope_ref: scopeRef, waiver_ref: w.ref };
  }
  return {
    open: true,
    reason: w.by === 'operator' ? 'waived_by_operator' : 'self_waived_by_agent',
    waiver: { by: w.by, ref: w.ref, at: w.at, reason: w.reason },
    status,
    scope_ref: scopeRef,
  };
}

// The absent-STATE bootstrap route (CHANGE-0099 / state-bootstrap-template,
// verified end to end by state-route-exists-but-is-undiscoverable): a
// genuinely absent STATE.yaml is not a corrupt one — `state_unreadable` below
// fires ONLY when `existsSync(opts.state)` is false, never for a present-but-
// broken file (that is `validation_block_unreadable`, from `evaluateGate`,
// left exactly as it prints today). These two commands are the actual,
// already-shipped fix; `--repair` never touches a file that already exists,
// so it is named here and nowhere a file merely failed to parse.
function bootstrapHint() {
  return [
    'node .aai/scripts/check-state.mjs --repair',
    'node .aai/scripts/state.mjs set-focus --type <type> --ref <ref-id> --path <primary-path>',
  ];
}

function usage(msg) {
  console.error(`validation-waiver: ${msg}`);
  console.error('usage: validation-waiver.mjs (--state <STATE.yaml> | --notes <text> [--status <s>] [--ref <scope>]) [--metrics <METRICS.jsonl>] [--json]');
  exit(2);
}

function main(argv) {
  const opts = { state: null, notes: null, status: 'not_run', ref: null, metrics: null, json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--state') { opts.state = argv[++i]; if (opts.state === undefined) usage('--state needs a path'); }
    else if (a === '--metrics') { opts.metrics = argv[++i]; if (opts.metrics === undefined) usage('--metrics needs a path'); }
    else if (a === '--notes') { opts.notes = argv[++i]; if (opts.notes === undefined) usage('--notes needs a value'); }
    else if (a === '--status') { opts.status = argv[++i]; if (opts.status === undefined) usage('--status needs a value'); }
    else if (a === '--ref') { opts.ref = argv[++i]; if (opts.ref === undefined) usage('--ref needs a value'); }
    else if (a === '--json') opts.json = true;
    else if (a === '-h' || a === '--help') usage('help');
    else usage(`unknown flag ${a}`);
  }
  if (opts.state === null && opts.notes === null) usage('one of --state / --notes is required');

  let block;
  let ledger = null;
  let fallbackRef = opts.ref;
  if (opts.state !== null) {
    if (!existsSync(opts.state)) {
      // Fail CLOSED: an absent state file is not an open gate. The file was
      // never created — name the bootstrap route rather than leave the
      // operator with an opaque reason token and no next step.
      const remediation = bootstrapHint();
      if (opts.json) {
        console.log(JSON.stringify({
          open: false, reason: 'state_unreadable', waiver: null, status: null, scope_ref: null,
          state: opts.state, remediation,
        }, null, 2));
      } else {
        console.log(`VALIDATION-GATE blocked reason=state_unreadable state=${opts.state}`);
        console.log('  Remediation:');
        for (const step of remediation) console.log(`    ${step}`);
      }
      exit(1);
    }
    const yaml = readFileSync(opts.state, 'utf8');
    block = readValidationBlock(yaml);
    // The scope the ride is actually on, used only when the validation block
    // records none of its own.
    fallbackRef = opts.ref ?? readFocusRef(yaml);
    // Resolved as a SIBLING of the state file, never off the CWD — otherwise
    // every fixture in every suite would silently read the real ledger.
    ledger = readArchiveLedger(opts.metrics ?? join(dirname(resolve(opts.state)), 'METRICS.jsonl'));
  } else {
    // No STATE means no `run_at_utc` to bind an archive record to, so the
    // archive lane cannot open here by construction — fail-closed, and the
    // waiver lane this mode exists for is unaffected.
    block = { status: opts.status, notes: opts.notes, ref_id: null, run_at_utc: null };
    ledger = opts.metrics === null ? null : readArchiveLedger(opts.metrics);
  }

  const v = evaluateGate(block, fallbackRef, ledger);
  if (opts.json) {
    console.log(JSON.stringify({ ...v }, null, 2));
    exit(v.open ? 0 : 1);
  }
  console.log(`VALIDATION-GATE ${v.open ? 'open' : 'blocked'} reason=${v.reason}`);
  console.log(`status=${v.status ?? 'absent'}`);
  console.log(`scope_ref=${v.scope_ref ?? 'absent'}`);
  if (v.waiver_ref !== undefined) console.log(`waiver_ref=${v.waiver_ref}`);
  if (v.archive_ref !== undefined) console.log(`archive_ref=${v.archive_ref}`);
  if (v.archive) console.log(`archive_ref=${v.archive.ref} archive_at=${v.archive.at}`);
  if (v.waiver) {
    console.log(`waiver_by=${v.waiver.by} waiver_ref=${v.waiver.ref} waiver_at=${v.waiver.at}`);
    console.log(`waiver_reason=${v.waiver.reason}`);
  }
  exit(v.open ? 0 : 1);
}

// Only run the CLI when invoked directly — the factory report and the metrics
// flush import the parser from here (one grammar, every consumer).
if (process.argv[1] && process.argv[1].endsWith('validation-waiver.mjs')) {
  runMain(() => main(process.argv.slice(2)));
}
