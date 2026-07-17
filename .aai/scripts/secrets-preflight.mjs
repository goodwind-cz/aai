#!/usr/bin/env node
//
// secrets-preflight.mjs — intake-time secrets existence preflight
// (SPEC-0045 / CHANGE-0034).
//
// PURPOSE
//   Classify locally referenced secrets (env vars, JSON/.env config keys) as
//   exactly one of `exists` / `empty` / `missing` WITHOUT any code path that
//   can log, print, return, or persist the underlying value. Never a secrets
//   manager: read-only existence/non-empty classification, nothing else.
//
// GRAMMAR (D1, closed)
//   node .aai/scripts/secrets-preflight.mjs \
//     --env NAME [--env NAME2 ...] \
//     [--file <path> --key <dotted.key> [--key <dotted.key2> ...]] \
//     [--file <path2> --key ... ]
//   Each `--env NAME` is one independent check (duplicates yield duplicate,
//   independent output lines). Each `--key` binds to the most recently seen
//   `--file`; a `--key` with no preceding `--file` is a usage error.
//   Supported file formats, chosen by extension/basename:
//     .json                              -> JSON.parse + dotted-path walk
//     .env or a basename starting with .env (e.g. .env.local) -> line-scan
//   Any other extension (including .yaml/.yml) is a usage error naming the
//   supported formats — YAML is explicitly out of scope v1 (zero-dependency
//   rule: no YAML parser exists in this repo's stdlib-only contract).
//
// OUTPUT CONTRACT (D2)
//   Exactly one line per requested check on stdout, in request order:
//     env:<NAME> <status>
//     file:<path>#<key> <status>
//   <status> is exactly one of the closed set: exists | empty | missing.
//   Nothing else is ever written to stdout. References (names, paths, keys)
//   are not secret and may be echoed; VALUES are never echoed, anywhere.
//
// CLASSIFICATION RULES
//   env:  unset -> missing; set (any length, including whitespace-only,
//         no trimming — length semantics only) -> empty if length 0, else
//         exists.
//   json: dotted-path walk; any hop that is not a plain object (including
//         arrays), or a missing key at any hop -> missing. A present key
//         whose value is `null` -> empty (explicit rule, checked BEFORE
//         generic coercion). A present string value -> empty/exists by
//         length. A present non-string, non-null terminal (number, boolean,
//         object, array) -> String-coerced for the length test ONLY.
//   .env: quoting-aware line-scan for `KEY=` or `export KEY=` (first genuine
//         top-level assignment wins, top to bottom). When a candidate
//         assignment's value opens with a quote (`"` or `'`) that is not
//         closed on the SAME physical line, subsequent lines are consumed as
//         value continuation up to (and including) the line bearing the
//         matching closing quote, or EOF if never closed; those consumed
//         interior lines are never re-scanned as top-level assignments, even
//         when they look like `KEY=...` themselves (SPEC-0049). One pair of
//         matching surrounding quotes is stripped before the length test
//         (now applied to the full, possibly multiline, value); no other
//         trimming.
//   Any check against a file that could not be read (ENOENT/EACCES/any read
//   error) or a JSON file that failed to parse classifies as `missing` for
//   every key requested against that file (see NEVER-ECHO RULES).
//
// EXIT CONTRACT (D3, informational/non-blocking)
//   0  every requested check was classified, regardless of the individual
//      statuses — `missing` is a recorded fact, not an error condition.
//   2  usage error: no checks requested, `--key` with no preceding `--file`,
//      an unrecognized flag, or an unsupported file format. A fixed-string
//      message is printed to stderr; nothing else.
//   1  unexpected internal error. Prints ONLY the fixed string
//      `secrets-preflight: internal error (details suppressed)` to stderr —
//      never the caught error's message or a stack trace.
//
// NEVER-ECHO RULES (D4 — the heart of this script)
//   - Values are ONLY ever tested for `undefined`/absence and `.length === 0`
//     (after the JSON-null/quote-strip special cases above). No value is
//     ever interpolated into any output string, log line, or exception.
//   - Unreadable file -> every key against it classifies `missing`, plus ONE
//     fixed stderr note per file: `note: <path>: unreadable (content not
//     shown)`.
//   - Unparseable JSON -> every key against it classifies `missing`, plus
//     ONE fixed stderr note per file: `note: <path>: parse failed (content
//     not shown)`. The caught SyntaxError is NEVER printed — Node's own
//     JSON.parse error messages can quote the surrounding file content, so
//     printing `err.message` here would defeat the entire guarantee.
//   - A top-level try/catch around the whole run enforces the D3 exit-1
//     fixed string for any unanticipated failure — never leaks err.message.
//   - No tempfile copies, no environment dumps, no debug/verbose mode that
//     could print a value.
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import { readFileSync } from 'node:fs';
import { basename, extname } from 'node:path';

const SUPPORTED_FORMATS_MSG = 'supported formats: .json, .env / .env.*';

function usageError(msg) {
  process.stderr.write(`secrets-preflight: ${msg}\n`);
  process.stderr.write(
    'usage: node .aai/scripts/secrets-preflight.mjs --env NAME [--env NAME2 ...] ' +
      '[--file <path> --key <dotted.key> [--key ...]] [--file <path2> --key ...]\n'
  );
  process.exit(2);
}

function detectFormat(path) {
  if (extname(path) === '.json') return 'json';
  const base = basename(path);
  if (extname(path) === '.env' || base.startsWith('.env')) return 'env';
  return null;
}

function parseArgs(argv) {
  const checks = [];
  let currentFile = null;
  let i = 0;
  while (i < argv.length) {
    const tok = argv[i];
    if (tok === '--env') {
      const name = argv[i + 1];
      if (name === undefined) usageError('--env requires a NAME argument');
      checks.push({ kind: 'env', name });
      i += 2;
    } else if (tok === '--file') {
      const path = argv[i + 1];
      if (path === undefined) usageError('--file requires a PATH argument');
      const format = detectFormat(path);
      if (!format) {
        usageError(`unsupported file format: ${path} (${SUPPORTED_FORMATS_MSG})`);
      }
      currentFile = { path, format };
      i += 2;
    } else if (tok === '--key') {
      const key = argv[i + 1];
      if (key === undefined) usageError('--key requires a dotted.key argument');
      if (currentFile === null) usageError('--key requires a preceding --file');
      checks.push({ kind: 'file', path: currentFile.path, format: currentFile.format, key });
      i += 2;
    } else {
      usageError(`unrecognized flag: ${tok}`);
    }
  }
  if (checks.length === 0) {
    usageError('no checks requested (need at least one --env or --file/--key pair)');
  }
  return checks;
}

function classifyEnv(name) {
  const v = process.env[name];
  if (v === undefined) return 'missing';
  return v.length === 0 ? 'empty' : 'exists';
}

// Loads and parses a file exactly once. Never returns or logs raw content.
function loadFile(path, format) {
  let raw;
  try {
    raw = readFileSync(path, 'utf8');
  } catch {
    process.stderr.write(`note: ${path}: unreadable (content not shown)\n`);
    return { ok: false };
  }
  if (format === 'json') {
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      // Node's SyntaxError can quote surrounding file content — never print it.
      process.stderr.write(`note: ${path}: parse failed (content not shown)\n`);
      return { ok: false };
    }
    return { ok: true, format: 'json', data };
  }
  return { ok: true, format: 'env', raw };
}

// Dotted-path walk. Any non-object hop (including arrays) or absent key at
// any hop -> not found. Distinguishes "not found" from "found but null" so
// the null -> empty rule can be applied by the caller.
function walkDotted(data, dottedKey) {
  const parts = dottedKey.split('.');
  let cur = data;
  for (const part of parts) {
    if (cur === null || typeof cur !== 'object' || Array.isArray(cur)) {
      return { found: false };
    }
    if (!Object.prototype.hasOwnProperty.call(cur, part)) {
      return { found: false };
    }
    cur = cur[part];
  }
  return { found: true, value: cur };
}

function classifyJsonValue(found) {
  if (!found.found) return 'missing';
  const v = found.value;
  if (v === null) return 'empty';
  if (typeof v === 'string') return v.length === 0 ? 'empty' : 'exists';
  const s = String(v);
  return s.length === 0 ? 'empty' : 'exists';
}

function escapeRegExp(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Any top-level assignment shape (no leading whitespace, `export` prefix
// optional), regardless of key name. Used ONLY to detect where a quoted
// multiline value starts so its interior lines can be skipped — never to
// classify a value itself (that stays scoped to the requested key's own
// regex in classifyEnvFileKey below).
const ANY_ASSIGNMENT_RE = /^(?:export\s+)?[^\s=][^=]*=(.*)$/;

// Given the value text captured immediately after `KEY=` on line `startIdx`,
// determine whether it opens a quote left unclosed on that same physical
// line and, if so, consume subsequent lines as continuation up to (and
// including) the line bearing the matching closing quote char, or EOF if
// never closed (SPEC-0049). Returns the full — possibly multiline — value
// text and the index of the first line AFTER the consumed span. Never
// inspects the requested key; operates purely on value text and line shape,
// so it is safe to reuse both for masking OTHER keys' interiors and for
// gathering the target key's own (possibly multiline) value.
function consumeQuotedValue(lines, startIdx, firstLineVal) {
  const quote = firstLineVal.length > 0 && (firstLineVal[0] === '"' || firstLineVal[0] === "'")
    ? firstLineVal[0]
    : null;
  const closedSameLine =
    quote !== null && firstLineVal.length >= 2 && firstLineVal[firstLineVal.length - 1] === quote;
  if (quote === null || closedSameLine) {
    return { value: firstLineVal, nextIndex: startIdx + 1 };
  }
  let value = firstLineVal;
  let j = startIdx + 1;
  while (j < lines.length) {
    value += '\n' + lines[j];
    const isClosingLine = lines[j].includes(quote);
    j += 1;
    if (isClosingLine) break;
  }
  return { value, nextIndex: j };
}

// One pair of matching surrounding quotes ("..." or '...') is stripped
// before the length test; no other trimming.
function stripSurroundingQuotes(value) {
  if (value.length < 2) return value;
  const first = value[0];
  const last = value[value.length - 1];
  if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
    return value.slice(1, -1);
  }
  return value;
}

// Marks every line index that is INTERIOR to some quoted multiline value
// (any key, not just the one being looked up) so those lines are never
// re-scanned as fresh top-level assignments — the fix for the first-match
// scan misreading a `KEY=`-shaped interior fragment (SPEC-0049).
function computeConsumedLineMask(lines) {
  const consumed = new Array(lines.length).fill(false);
  let i = 0;
  while (i < lines.length) {
    const m = ANY_ASSIGNMENT_RE.exec(lines[i]);
    if (!m) {
      i += 1;
      continue;
    }
    const { nextIndex } = consumeQuotedValue(lines, i, m[1]);
    for (let k = i + 1; k < nextIndex; k += 1) consumed[k] = true;
    i = nextIndex;
  }
  return consumed;
}

// Quoting-aware line-scan for `KEY=` or `export KEY=` (SPEC-0049): first
// genuine top-level assignment wins, top to bottom; interior lines of any
// quoted multiline value (this key's or another's) are never treated as
// assignments. One pair of matching surrounding quotes is stripped from the
// full (possibly multiline) value before the length test.
function classifyEnvFileKey(raw, key) {
  const escaped = escapeRegExp(key);
  const rePlain = new RegExp(`^${escaped}=(.*)$`);
  const reExport = new RegExp(`^export\\s+${escaped}=(.*)$`);
  const lines = raw.split(/\r?\n/);
  const consumed = computeConsumedLineMask(lines);
  for (let idx = 0; idx < lines.length; idx += 1) {
    if (consumed[idx]) continue;
    const m = rePlain.exec(lines[idx]) || reExport.exec(lines[idx]);
    if (!m) continue;
    const { value } = consumeQuotedValue(lines, idx, m[1]);
    const stripped = stripSurroundingQuotes(value);
    return stripped.length === 0 ? 'empty' : 'exists';
  }
  return 'missing';
}

function classifyFileCheck(cache, check) {
  if (!cache.has(check.path)) {
    cache.set(check.path, loadFile(check.path, check.format));
  }
  const loaded = cache.get(check.path);
  if (!loaded.ok) return 'missing';
  if (loaded.format === 'json') {
    return classifyJsonValue(walkDotted(loaded.data, check.key));
  }
  return classifyEnvFileKey(loaded.raw, check.key);
}

function refLabel(check) {
  return check.kind === 'env' ? `env:${check.name}` : `file:${check.path}#${check.key}`;
}

function run() {
  const checks = parseArgs(process.argv.slice(2));
  const cache = new Map();
  const lines = [];
  for (const check of checks) {
    const status = check.kind === 'env' ? classifyEnv(check.name) : classifyFileCheck(cache, check);
    lines.push(`${refLabel(check)} ${status}`);
  }
  if (lines.length > 0) {
    process.stdout.write(lines.join('\n') + '\n');
  }
  process.exit(0);
}

try {
  run();
} catch {
  process.stderr.write('secrets-preflight: internal error (details suppressed)\n');
  process.exit(1);
}
