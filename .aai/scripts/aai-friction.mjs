#!/usr/bin/env node
//
// aai-friction.mjs — RFC-0012 Phase 0 offline friction capture CLI.
//
// PURPOSE
//   Validate a schema-v1 friction observation and append exactly one JSONL
//   line to an untracked project-local spool. Local-first and offline: this
//   tool holds no token and performs no network I/O. Capture is a standalone
//   process — a bad input exits non-zero with a specific code and never masks
//   or replaces the calling skill's original result (exit codes are the
//   contract). See .aai/system/FRICTION_PROTOCOL.md for the full contract.
//
// GRAMMAR
//   node .aai/scripts/aai-friction.mjs record --input <path|->
//   node .aai/scripts/aai-friction.mjs --help
//   `--input -` reads the observation JSON from stdin; otherwise it is a path.
//
// D6 DENY-BY-DEFAULT (the privacy crux)
//   The persisted record is built by COPYING ONLY the eight allowlisted keys
//   into a fresh object literal — never by copying the input and deleting a
//   denylist. Named identity fields (hostname, absolute path, repo remote,
//   username, project id) AND any novel/unknown key a caller supplies are
//   therefore absent from the spool line by construction. The locally derived
//   fields (os_family, aai_pin, node_major) are derived on this machine and
//   are never trusted from the caller.
//
// EXIT CONTRACT
//   0  success (a line was appended), or --help.
//   2  usage error (bad subcommand, missing/duplicate --input, unknown flag).
//   3  input validation error (schema v1 violation, oversized, unparsable
//      JSON). No spool line is written. stdout stays empty.
//   1  unexpected internal error — fixed message, details suppressed.
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import { readFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { redactSummary, MAX_SUMMARY_LEN } from './lib/aai-redact.mjs';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, '..', '..');
const AAI_PIN_PATH = join(SCRIPT_DIR, '..', 'system', 'AAI_PIN.md');
const SPOOL_FILE_NAME = 'observations.jsonl';
const MAX_INPUT_BYTES = 65536;
const SCHEMA_VERSION = 1;
// RFC-0013: schema v2 persists structured signal fields (still leak-free) and,
// opt-in, a hard-redacted summary. v1 records are accepted and persisted exactly
// as before (backward compatible, byte-identical).
const SUPPORTED_SCHEMA_VERSIONS = [1, 2];
const WORKAROUND_VALUES = ['none', 'manual', 'automatic'];
// Schema v2 impact domain per RFC-0013 D1 (low|medium|high). Deliberately does
// NOT include the legacy IMPACT_VALUES 'critical' — v2 honors the frozen RFC
// decision, so a v2 record with impact:critical is rejected (PR review P2).
const V2_IMPACT_VALUES = ['low', 'medium', 'high'];
const REDACTION_STATUS_VALUES = ['none', 'capture_clean', 'capture_dropped_fields'];
// evidence_ref (RFC-0013 D5): a SAFE pointer only — a repo-relative docs/ path or
// an AAI doc id. No URLs, no absolute paths, no free text. The doc-id arm ends
// EXACTLY after the 4 digits: a trailing `[A-Za-z0-9-]*` suffix (e.g.
// `SPEC-0079-private-customer-acme`) would be a free-text identity channel that
// bypasses the redactor, so it is rejected (PR review P1). Use the `docs/…` arm
// for a full document reference.
const EVIDENCE_REF_RE = /^(?:docs\/[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*|(?:SPEC|CHANGE|ISSUE|RFC|PRD|RES|DEBT)-\d{4})$/;
const FINGERPRINT_VERSION = 1;
// Atomic-append size bound. A single write() of a line strictly under PIPE_BUF
// is not interleaved with another concurrent O_APPEND writer's; a line that
// would reach PIPE_BUF is REJECTED (never appended), so lossless concurrency is
// a construction, not an assumption. PIPE_BUF is 4096 on Linux/macOS.
const PIPE_BUF = 4096;
// Persisted identifier/enum string fields are capped so a normal record's line
// stays far below PIPE_BUF; over-length values are invalid input, not data.
const MAX_ID_LEN = 128;

const FAILURE_CLASSES = [
  'contradictory_instructions',
  'missing_or_invalid_artifact',
  'deterministic_script_failure',
  'abstraction_leak_recovery',
  'human_corrected_defect',
  'contract_violation',
];
const IMPACT_VALUES = ['low', 'medium', 'high', 'critical'];
const CONFIDENCE_VALUES = ['low', 'medium', 'high'];
const REDACTION_VALUES = ['none', 'standard', 'hard'];

const HELP = `aai-friction — RFC-0012 Phase 0 offline friction capture.

Usage:
  node .aai/scripts/aai-friction.mjs record --input <path|->
  node .aai/scripts/aai-friction.mjs --help

record
  Validate a schema-v1 or -v2 observation (JSON) and append ONE JSONL line to
  the untracked spool at docs/ai/friction/${SPOOL_FILE_NAME}. Pass a file path,
  or '-' to read the observation from stdin.

Guarantees:
  - Offline: no token and no network access is ever used.
  - D6 allowlist (deny-by-default): the persisted line contains ONLY the eight
    safe v1 keys (schema_version, os_family, aai_pin, node_major, skill_id,
    skill_phase, failure_class, fingerprint) plus, for schema_version 2, the
    leak-free structured signal fields (reproducible, impact, confidence,
    workaround, evidence_ref, redaction_status). Every other input key — named
    identity fields or any novel key — is dropped by construction.
  - Redaction (RFC-0013): the opt-in free-text 'summary' (schema v2) is persisted
    only when .aai/feedback.yaml enables it AND the hard redactor certifies it
    clean; otherwise it is dropped fail-closed (the record still persists).
  - Concurrency-safe: the line is appended with O_APPEND, so concurrent
    record processes never lose or interleave lines; a rejected input never
    leaves a partial line.

Exit codes:
  0 success / --help   2 usage error   3 validation error   1 internal error

See .aai/system/FRICTION_PROTOCOL.md for the schema, the allowlist, the v1
fingerprint algorithm, and the redaction policy.
`;

class UsageError extends Error {}
class ValidationError extends Error {}

function usageExit(msg) {
  process.stderr.write(`aai-friction: ${msg}\n`);
  process.stderr.write('usage: node .aai/scripts/aai-friction.mjs record --input <path|->\n');
  process.exit(2);
}

// --- input acquisition ------------------------------------------------------

function readInput(inputArg) {
  let raw;
  if (inputArg === '-') {
    try {
      raw = readFileSync(0, 'utf8');
    } catch {
      throw new ValidationError('could not read observation from stdin');
    }
  } else {
    try {
      raw = readFileSync(inputArg, 'utf8');
    } catch {
      throw new ValidationError(`could not read input file: ${inputArg}`);
    }
  }
  if (Buffer.byteLength(raw, 'utf8') > MAX_INPUT_BYTES) {
    throw new ValidationError(`input exceeds maximum size of ${MAX_INPUT_BYTES} bytes`);
  }
  let obj;
  try {
    obj = JSON.parse(raw);
  } catch {
    throw new ValidationError('input is not valid JSON');
  }
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
    throw new ValidationError('input must be a JSON object');
  }
  return obj;
}

// --- schema v1 validation ---------------------------------------------------

function requireString(obj, field) {
  if (!Object.prototype.hasOwnProperty.call(obj, field)) {
    throw new ValidationError(`missing required field: ${field}`);
  }
  const v = obj[field];
  if (typeof v !== 'string') {
    throw new ValidationError(`field '${field}' has wrong type (expected a string)`);
  }
  if (v.length === 0) {
    throw new ValidationError(`field '${field}' must not be empty`);
  }
  return v;
}

// Caps a persisted identifier/enum string field. An over-length value is
// invalid input (identifiers and enums are short by nature) and keeps the
// serialized line far below the PIPE_BUF atomic-append bound.
function capField(field, value) {
  if (value.length > MAX_ID_LEN) {
    throw new ValidationError(
      `field '${field}' exceeds the maximum length of ${MAX_ID_LEN} characters`
    );
  }
}

function optionalEnum(obj, field, allowed) {
  if (!Object.prototype.hasOwnProperty.call(obj, field)) return;
  const v = obj[field];
  if (typeof v !== 'string') {
    throw new ValidationError(`field '${field}' has wrong type (expected a string)`);
  }
  if (!allowed.includes(v)) {
    throw new ValidationError(`field '${field}' must be one of: ${allowed.join(', ')}`);
  }
}

function optionalString(obj, field) {
  if (!Object.prototype.hasOwnProperty.call(obj, field)) return;
  if (typeof obj[field] !== 'string') {
    throw new ValidationError(`field '${field}' has wrong type (expected a string)`);
  }
}

function validate(obj) {
  if (!Object.prototype.hasOwnProperty.call(obj, 'schema_version')) {
    throw new ValidationError('missing required field: schema_version');
  }
  if (!SUPPORTED_SCHEMA_VERSIONS.includes(obj.schema_version)) {
    throw new ValidationError(
      `field 'schema_version' must be one of: ${SUPPORTED_SCHEMA_VERSIONS.join(', ')} (unsupported schema version)`
    );
  }
  const schemaVersion = obj.schema_version;
  const skillId = requireString(obj, 'skill_id');
  capField('skill_id', skillId);
  const skillPhase = requireString(obj, 'skill_phase');
  capField('skill_phase', skillPhase);
  const failureClass = requireString(obj, 'failure_class');
  capField('failure_class', failureClass);
  if (!FAILURE_CLASSES.includes(failureClass)) {
    throw new ValidationError(
      `field 'failure_class' must be one of: ${FAILURE_CLASSES.join(', ')}`
    );
  }
  const expected = requireString(obj, 'expected_behavior');
  const observed = requireString(obj, 'observed_behavior');

  optionalEnum(obj, 'impact', IMPACT_VALUES);
  optionalEnum(obj, 'confidence', CONFIDENCE_VALUES);
  optionalEnum(obj, 'redaction', REDACTION_VALUES);
  optionalString(obj, 'reproduction');
  optionalString(obj, 'workaround');
  optionalString(obj, 'recurrence');
  optionalString(obj, 'timestamp');
  if (Object.prototype.hasOwnProperty.call(obj, 'evidence_refs')) {
    const refs = obj.evidence_refs;
    if (!Array.isArray(refs) || refs.some((r) => typeof r !== 'string')) {
      throw new ValidationError("field 'evidence_refs' has wrong type (expected an array of strings)");
    }
  }

  // --- schema v2 structured fields (RFC-0013) — collected ONLY for v2 records,
  // so a v1 record's persisted line is byte-identical to the pre-v2 tool. All
  // are optional; each is type/enum/shape-validated. These are leak-free by
  // construction (bool/enum/shape-restricted pointer) and NEVER reach the
  // redactor — only the opt-in free-text `summary` (handled at record time) does.
  let v2;
  if (schemaVersion === 2) {
    v2 = {};
    if (Object.prototype.hasOwnProperty.call(obj, 'reproducible')) {
      if (typeof obj.reproducible !== 'boolean') {
        throw new ValidationError("field 'reproducible' has wrong type (expected a boolean)");
      }
      v2.reproducible = obj.reproducible;
    }
    // confidence was already enum-validated above (optionalEnum). impact is
    // re-validated against the TIGHTER v2 domain (RFC-0013 D1) — the legacy
    // optionalEnum accepts 'critical', which v2 must reject.
    if (Object.prototype.hasOwnProperty.call(obj, 'impact')) {
      if (!V2_IMPACT_VALUES.includes(obj.impact)) {
        throw new ValidationError(`field 'impact' must be one of: ${V2_IMPACT_VALUES.join(', ')} (schema v2)`);
      }
      v2.impact = obj.impact;
    }
    if (Object.prototype.hasOwnProperty.call(obj, 'confidence')) v2.confidence = obj.confidence;
    if (Object.prototype.hasOwnProperty.call(obj, 'workaround')) {
      if (!WORKAROUND_VALUES.includes(obj.workaround)) {
        throw new ValidationError(`field 'workaround' must be one of: ${WORKAROUND_VALUES.join(', ')}`);
      }
      v2.workaround = obj.workaround;
    }
    if (Object.prototype.hasOwnProperty.call(obj, 'evidence_ref')) {
      const ref = obj.evidence_ref;
      // Shape gate PLUS an explicit traversal guard: EVIDENCE_REF_RE permits `.`
      // in a path segment (so `..` is syntactically a "valid" segment), which
      // would let `docs/../../etc/passwd` masquerade as a repo-relative doc
      // path. Reject any `..` component so the pointer cannot escape the repo.
      if (typeof ref !== 'string' || !EVIDENCE_REF_RE.test(ref) || ref.split('/').includes('..')) {
        throw new ValidationError(
          "field 'evidence_ref' must be a repo-relative docs/ path (no '..') or an AAI doc id (e.g. SPEC-0079); URLs, absolute paths, traversal, and free text are rejected"
        );
      }
      capField('evidence_ref', ref);
      v2.evidenceRef = ref;
    }
    if (Object.prototype.hasOwnProperty.call(obj, 'summary')) {
      if (typeof obj.summary !== 'string') {
        throw new ValidationError("field 'summary' has wrong type (expected a string)");
      }
      v2.summary = obj.summary; // redaction is applied at record time, fail-closed
    }
  }

  return { skillId, skillPhase, failureClass, expected, observed, schemaVersion, v2 };
}

// --- locally derived fields (never trusted from the caller) -----------------

function deriveOsFamily() {
  switch (process.platform) {
    case 'linux':
      return 'linux';
    case 'darwin':
      return 'macos';
    case 'win32':
      return 'windows';
    default:
      return 'unknown';
  }
}

function deriveNodeMajor() {
  const major = parseInt(String(process.versions.node).split('.')[0], 10);
  return Number.isFinite(major) ? major : 0;
}

function deriveAaiPin() {
  let text;
  try {
    text = readFileSync(AAI_PIN_PATH, 'utf8');
  } catch {
    return 'unknown';
  }
  const m = text.match(/^-\s*Template version\s*:\s*(.*)$/m);
  if (!m) return 'unknown';
  const value = m[1].trim();
  if (value === '' || value.startsWith('<')) return 'unknown';
  return value;
}

// --- v1 fingerprint ---------------------------------------------------------

function normalizeField(s) {
  return s.toLowerCase().replace(/\s+/g, ' ').trim();
}

function computeFingerprint(v) {
  const parts = [
    `v${FINGERPRINT_VERSION}`,
    normalizeField(v.skillId),
    normalizeField(v.skillPhase),
    normalizeField(v.failureClass),
    normalizeField(v.expected),
    normalizeField(v.observed),
  ];
  const canonical = parts.join('');
  const digest = createHash('sha256').update(canonical, 'utf8').digest('hex');
  return `v${FINGERPRINT_VERSION}:${digest.slice(0, 32)}`;
}

// --- atomic spool append ----------------------------------------------------

function spoolDir() {
  const override = process.env.AAI_FRICTION_SPOOL_DIR;
  if (override && override.length > 0) return override;
  return join(REPO_ROOT, 'docs', 'ai', 'friction');
}

// Concurrency-safe single-line append. appendFileSync opens the spool with the
// O_APPEND flag, so the kernel atomically positions each write() at end-of-file
// — concurrent record processes (the COMMON case under AAI parallel agents)
// never read a shared snapshot and never clobber each other's line. Atomicity
// across concurrent writers requires each line be strictly under PIPE_BUF (4096
// bytes on Linux/macOS): a shorter write() is not interleaved with another's.
// That bound is ENFORCED, not assumed — persisted identifier/enum fields are
// length-capped (MAX_ID_LEN) at validation and record() rejects any serialized
// line that would reach PIPE_BUF before calling this function, so every line
// that reaches appendFileSync lands whole and none are lost. A read-modify-write
// (read snapshot, rewrite whole file, rename) would silently drop lines and is
// deliberately NOT used. A rejected input never reaches this function, so no
// partial line is ever written.
function appendLine(line) {
  const dir = spoolDir();
  mkdirSync(dir, { recursive: true });
  const target = join(dir, SPOOL_FILE_NAME);
  appendFileSync(target, line + '\n');
}

// --- feedback.yaml config (opt-in summary gate) -----------------------------
// RFC-0013 D2: the free-text `summary` is persisted ONLY when the operator
// opts in via `.aai/feedback.yaml` `capture.summary_enabled: true`. Absent or
// unparseable config FAILS CLOSED to `false` (no free-text persisted). Minimal
// line-based read — no YAML dependency (Technology contract: zero deps).
function loadSummaryEnabled() {
  const path = process.env.AAI_FEEDBACK_CONFIG || join(REPO_ROOT, '.aai', 'feedback.yaml');
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch {
    return false; // no config -> fail closed
  }
  // SCOPED read: only `summary_enabled` DIRECTLY under the top-level `capture:`
  // mapping counts. A stray `summary_enabled: true` in an unrelated section must
  // never override the privacy opt-out (PR review P1). Any dedent to another
  // top-level key ends the capture block. Fail closed to false throughout.
  let inCapture = false;
  for (const line of text.split('\n')) {
    if (/^[ \t]/.test(line)) {
      if (inCapture) {
        const m = line.match(/^[ \t]+summary_enabled[ \t]*:[ \t]*(true|false)[ \t]*$/);
        if (m) return m[1] === 'true';
      }
      continue; // indented line outside capture -> ignore
    }
    // a non-indented, non-blank line is a new top-level key
    inCapture = /^capture[ \t]*:/.test(line);
  }
  return false;
}

// --- record subcommand ------------------------------------------------------

function parseRecordArgs(rest) {
  let input = null;
  let i = 0;
  while (i < rest.length) {
    const tok = rest[i];
    if (tok === '--input') {
      if (input !== null) usageExit('--input given more than once');
      const val = rest[i + 1];
      if (val === undefined) usageExit('--input requires a <path|-> argument');
      input = val;
      i += 2;
    } else {
      usageExit(`unrecognized argument: ${tok}`);
    }
  }
  if (input === null) usageExit('record requires --input <path|->');
  return input;
}

function record(rest) {
  const inputArg = parseRecordArgs(rest);
  const obj = readInput(inputArg);
  const fields = validate(obj);

  // D6 deny-by-default: build the persisted record by copying ONLY the eight
  // allowlisted keys into a fresh object. No input key other than the three
  // explicitly named below can reach this object.
  const persisted = {
    schema_version: fields.schemaVersion,
    os_family: deriveOsFamily(),
    aai_pin: deriveAaiPin(),
    node_major: deriveNodeMajor(),
    skill_id: fields.skillId,
    skill_phase: fields.skillPhase,
    failure_class: fields.failureClass,
    fingerprint: computeFingerprint(fields),
  };

  // Schema v2 (RFC-0013): append the leak-free structured fields that are
  // present, then handle the opt-in, hard-redacted, fail-closed `summary`. The
  // v1 branch above is left byte-identical — v2 keys are ADDED only for v2.
  if (fields.schemaVersion === 2) {
    const v2 = fields.v2 || {};
    if (v2.reproducible !== undefined) persisted.reproducible = v2.reproducible;
    if (v2.impact !== undefined) persisted.impact = v2.impact;
    if (v2.confidence !== undefined) persisted.confidence = v2.confidence;
    if (v2.workaround !== undefined) persisted.workaround = v2.workaround;
    if (v2.evidenceRef !== undefined) persisted.evidence_ref = v2.evidenceRef;
    // Free-text summary: only if opted in AND the redactor certifies it clean.
    // Deny-by-default + fail-closed DROP (RFC-0013 D2/D4): an uncertain summary
    // is dropped (never persisted class-redacted in the capture pass), the
    // structured record still persists, and redaction_status records the outcome.
    let redactionStatus = 'none';
    if (v2.summary !== undefined && loadSummaryEnabled()) {
      const r = redactSummary(v2.summary, { maxLen: MAX_SUMMARY_LEN });
      if (r.ok) {
        persisted.summary = r.value;
        redactionStatus = 'capture_clean';
      } else {
        redactionStatus = 'capture_dropped_fields';
      }
    }
    persisted.redaction_status = redactionStatus;
  }

  // Hard atomic-append guard (belt-and-suspenders over the per-field caps): a
  // line is appended with O_APPEND only if it is strictly under PIPE_BUF, so a
  // single write() cannot interleave with a concurrent writer's. With the
  // MAX_ID_LEN caps and the short derived/computed fields this never fires in
  // normal use; it makes the atomicity invariant true by construction rather
  // than by assumption. The '\n' the append adds is counted in the bound.
  const line = JSON.stringify(persisted);
  if (Buffer.byteLength(line + '\n', 'utf8') >= PIPE_BUF) {
    throw new ValidationError(
      `serialized record line reaches the atomic-append size bound (${PIPE_BUF} bytes); refusing to append a line that could interleave under concurrent writers`
    );
  }

  appendLine(line);
  process.stdout.write(`recorded ${persisted.fingerprint}\n`);
}

// --- entrypoint -------------------------------------------------------------

function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0) {
    usageExit('no subcommand (expected: record)');
  }
  const [cmd, ...rest] = argv;
  if (cmd === '--help' || cmd === '-h' || cmd === 'help') {
    process.stdout.write(HELP);
    process.exit(0);
  }
  if (cmd === 'record') {
    record(rest);
    process.exit(0);
  }
  usageExit(`unknown subcommand: ${cmd} (expected: record)`);
}

try {
  main();
} catch (err) {
  if (err instanceof ValidationError) {
    process.stderr.write(`aai-friction: ${err.message}\n`);
    process.exit(3);
  }
  if (err instanceof UsageError) {
    process.stderr.write(`aai-friction: ${err.message}\n`);
    process.exit(2);
  }
  process.stderr.write('aai-friction: internal error (details suppressed)\n');
  process.exit(1);
}
