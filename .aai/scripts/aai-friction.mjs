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

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, '..', '..');
const AAI_PIN_PATH = join(SCRIPT_DIR, '..', 'system', 'AAI_PIN.md');
const SPOOL_FILE_NAME = 'observations.jsonl';
const MAX_INPUT_BYTES = 65536;
const SCHEMA_VERSION = 1;
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
  Validate a schema-v1 observation (JSON) and append ONE JSONL line to the
  untracked spool at docs/ai/friction/${SPOOL_FILE_NAME}. Pass a file path, or
  '-' to read the observation from stdin.

Guarantees:
  - Offline: no token and no network access is ever used.
  - D6 allowlist (deny-by-default): the persisted line contains ONLY the eight
    safe keys (schema_version, os_family, aai_pin, node_major, skill_id,
    skill_phase, failure_class, fingerprint). Every other key in the input —
    named identity fields or any novel key — is dropped by construction.
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
  if (obj.schema_version !== SCHEMA_VERSION) {
    throw new ValidationError(
      `field 'schema_version' must equal ${SCHEMA_VERSION} (unsupported schema version)`
    );
  }
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
  return { skillId, skillPhase, failureClass, expected, observed };
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
    schema_version: SCHEMA_VERSION,
    os_family: deriveOsFamily(),
    aai_pin: deriveAaiPin(),
    node_major: deriveNodeMajor(),
    skill_id: fields.skillId,
    skill_phase: fields.skillPhase,
    failure_class: fields.failureClass,
    fingerprint: computeFingerprint(fields),
  };

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
