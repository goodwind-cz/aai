#!/usr/bin/env node
// canon.mjs — the rules that bind a dispatched agent are ASSEMBLED and
// ASSERTED, never pasted (SPEC-DRAFT-spec-canon-is-a-build-artifact).
//
// THIS FILE (D1): ONE script, subcommands `build` / `check` / `claims`, all
// reading the same declaration (`.aai/system/CANON.yaml`) — three files
// would cost three PROFILES rows, three main guards and three refusal
// vocabularies for one mechanism. Only `build` is implemented so far
// (Spec-AC-01..05); `check` and `claims` land in later Test Plan rows of the
// same spec (Spec-AC-08..15) and this file grows subcommands, not siblings.
//
// `build --role <R> --ref <r> [--manifest <path>]` assembles the dispatch
// payload for role R from the manifest's declared, ORDERED sections (D3:
// every order/count/uniqueness assertion downstream reads THIS assembled
// payload, never the manifest — the manifest is an input, not a proof) and
// prints it, and ONLY it, to stdout: the orchestrator pastes stdout verbatim
// into a dispatch, so stdout carries nothing but the payload — every
// diagnostic (the measured byte size, an admitted duplicate's reason) goes
// to stderr, on success as much as on refusal (D4).
//
// FAIL CLOSED (D4): every refusal prints a named reason token plus the
// offending file:line (and, for a count, both numbers) to stderr, and
// stdout is left completely EMPTY — never a truncated payload. Checks run
// in this order: section resolution (absent/empty), hazard count, duplicate
// rule, byte budget; the first violation found refuses and stops there.
//
// Node stdlib only (docs/TECHNOLOGY.md) — no YAML dependency. CANON.yaml is
// parsed by a small hand-rolled, file-shape-specific parser below, the same
// discipline `.aai/system/PROFILES.yaml` already uses for its own line-based
// dialect (D2 comment in CANON.yaml itself).

import fs from 'node:fs';
import path from 'node:path';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const ROOT = process.cwd();
const DEFAULT_MANIFEST = '.aai/system/CANON.yaml';

// Section marker frame (Spec-AC-01 Verification: `grep -n '^<<<AAI-CANON-SECTION '`
// extracts the id sequence — this exact literal, anchored at line start, is
// the payload's only order-bearing shape a caller may rely on).
const SECTION_OPEN = '<<<AAI-CANON-SECTION';
const SECTION_CLOSE = '>>>AAI-CANON-SECTION';

// A "declared canon rule line" for the duplicate-rule scan (Spec-AC-04): any
// markdown bullet line. R2 (measured 2026-09-25, see CANON.yaml's own
// comment for the corpus measurement and the false-positive result) — safe
// for every role's own assembled payload, the only shape `build` produces.
const RULE_LINE_RE = /^- (.+)$/;

function usageError(msg) {
  process.stderr.write(`canon: ${msg}\n`);
  process.stderr.write(
    'usage: node .aai/scripts/canon.mjs build --role <R> --ref <r> [--manifest <path>]\n'
  );
  exit(2);
}

// --- CANON.yaml parsing ------------------------------------------------------
//
// Hand-rolled for THIS file's exact shape (top-level `roles:` / `sections:`
// / `standing_hazards:` / `byte_ceiling:` / `uniqueness_exceptions:`, two-
// space then four-space indentation, `[]` for an empty list) — not a
// general YAML parser. Comment lines (first non-space char `#`) and blank
// lines are dropped before parsing; every remaining line keeps its original
// indentation, which is the only structure this parser reads.

function stripQuotes(s) {
  const t = s.trim();
  if (t.length >= 2 && ((t[0] === '"' && t[t.length - 1] === '"') || (t[0] === "'" && t[t.length - 1] === "'"))) {
    return t.slice(1, -1);
  }
  return t;
}

function parseManifestText(content) {
  const raw = content.split(/\r?\n/);
  const lines = raw.filter((l) => l.trim() !== '' && !/^\s*#/.test(l));
  const manifest = { roles: {}, sections: [], standing_hazards: null, byte_ceiling: null, uniqueness_exceptions: [] };
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const top = /^(\S.*?):\s*(.*)$/.exec(line);
    if (!top || /^\s/.test(line)) { i += 1; continue; }
    const key = top[1].trim();
    const inline = top[2];
    if (key === 'roles') {
      i += 1;
      while (i < lines.length && /^ {2}\S/.test(lines[i])) {
        const m = /^ {2}(.+?):\s*(.+)$/.exec(lines[i]);
        if (m) manifest.roles[m[1].trim()] = stripQuotes(m[2]);
        i += 1;
      }
      continue;
    }
    if (key === 'sections') {
      i += 1;
      while (i < lines.length && /^ {2}- /.test(lines[i])) {
        const sec = {};
        const idm = /^ {2}- id:\s*(.+)$/.exec(lines[i]);
        if (idm) sec.id = stripQuotes(idm[1]);
        i += 1;
        while (i < lines.length && /^ {4}\S/.test(lines[i])) {
          const fm = /^ {4}(\w+):\s*(.*)$/.exec(lines[i]);
          if (fm) sec[fm[1]] = stripQuotes(fm[2]);
          i += 1;
        }
        manifest.sections.push(sec);
      }
      continue;
    }
    if (key === 'uniqueness_exceptions') {
      if (inline.trim() === '[]') { i += 1; continue; }
      i += 1;
      while (i < lines.length && /^ {2}- /.test(lines[i])) {
        const ex = {};
        const tm = /^ {2}- text:\s*(.+)$/.exec(lines[i]);
        if (tm) ex.text = stripQuotes(tm[1]);
        i += 1;
        while (i < lines.length && /^ {4}\S/.test(lines[i])) {
          const fm = /^ {4}(\w+):\s*(.*)$/.exec(lines[i]);
          if (fm) ex[fm[1]] = stripQuotes(fm[2]);
          i += 1;
        }
        manifest.uniqueness_exceptions.push(ex);
      }
      continue;
    }
    if (key === 'standing_hazards') { manifest.standing_hazards = parseInt(inline.trim(), 10); i += 1; continue; }
    if (key === 'byte_ceiling') { manifest.byte_ceiling = parseInt(inline.trim(), 10); i += 1; continue; }
    i += 1;
  }
  return manifest;
}

function loadManifest(manifestPath) {
  const abs = path.isAbsolute(manifestPath) ? manifestPath : path.resolve(ROOT, manifestPath);
  let content;
  try {
    content = fs.readFileSync(abs, 'utf8');
  } catch (err) {
    usageError(`cannot read --manifest ${manifestPath} (${(err && err.code) || 'unknown'})`);
  }
  return parseManifestText(content);
}

// --- section resolution -------------------------------------------------------

// normalizeLine: trim + collapse internal whitespace to one space — the
// "normalized text" D4 names for a duplicate-rule refusal.
function normalizeLine(s) {
  return s.trim().replace(/\s+/g, ' ');
}

// readSourceFile(relPath) -> { content, lines } with CRLF normalized to LF
// (Implementation plan edge case: CRLF sources) so byte counting and line
// numbering are stable regardless of the source file's own line endings.
// Absent/unreadable resolves to null rather than throwing.
function readSourceFile(relPath) {
  const abs = path.isAbsolute(relPath) ? relPath : path.resolve(ROOT, relPath);
  let raw;
  try {
    raw = fs.readFileSync(abs, 'utf8');
  } catch {
    return null;
  }
  if (raw.length === 0) return { content: '', lines: [] };
  const content = raw.replace(/\r\n/g, '\n');
  return { content, lines: content.split('\n') };
}

// resolveSections(manifest, role, ref) -> { ok: true, sections: [{id, path, lines}] }
// or { ok: false, id, path } naming the first absent/empty declared section,
// in declared order (Spec-AC-02: fail fast, never a truncated payload).
function resolveSections(manifest, role, ref) {
  const resolved = [];
  for (const sec of manifest.sections) {
    if (sec.type === 'file') {
      const f = readSourceFile(sec.path);
      if (!f || f.content.length === 0) return { ok: false, id: sec.id, path: sec.path };
      resolved.push({ id: sec.id, path: sec.path, lines: f.lines });
    } else if (sec.type === 'role') {
      const rolePath = manifest.roles[role];
      if (rolePath === undefined) usageError(`--role "${role}" is not declared in manifest roles: (known: ${Object.keys(manifest.roles).join(', ')})`);
      const f = readSourceFile(rolePath);
      if (!f || f.content.length === 0) return { ok: false, id: sec.id, path: rolePath };
      resolved.push({ id: sec.id, path: rolePath, lines: f.lines });
    } else if (sec.type === 'scope') {
      const text = `Scope ref: ${ref}\n`
        + '(dispatch-specific scope and inputs occupy this position in the assembled payload)\n';
      resolved.push({ id: sec.id, path: '<scope>', lines: text.replace(/\n$/, '').split('\n') });
    } else {
      usageError(`manifest section "${sec.id}" has unknown type "${sec.type}"`);
    }
  }
  return { ok: true, sections: resolved };
}

// --- payload assembly ---------------------------------------------------------

// framePayload(sections) -> the full payload string, sections framed by the
// open/close markers, in the EXACT order the `sections` array is given —
// D3: this function never reorders; whoever calls it decides the order, and
// that caller (buildPayload below) reads it straight off manifest.sections.
function framePayload(sections) {
  let out = '';
  for (const s of sections) {
    out += `${SECTION_OPEN} ${s.id}\n`;
    out += s.lines.length ? `${s.lines.join('\n')}\n` : '';
    out += `${SECTION_CLOSE} ${s.id}\n`;
  }
  return out;
}

// countHazardLines(sections) -> number of lines matching `^- HAZ-` across
// every resolved section's content (Spec-AC-03: counted in the ASSEMBLED
// payload, not read as a fixed literal).
function countHazardLines(sections) {
  let n = 0;
  for (const s of sections) {
    for (const line of s.lines) if (/^- HAZ-/.test(line)) n += 1;
  }
  return n;
}

// findDuplicateRule(sections, exceptions) -> null, or
// { normalized, first: {path,line}, second: {path,line} } for the first
// undeclared duplicate found (Spec-AC-04); also returns `admitted`, the
// list of exception matches actually encountered (each printed on success,
// TEST-679 — an admitted exception is never silent).
function findDuplicateRule(sections, exceptions) {
  const exceptionTexts = new Set((exceptions || []).map((e) => normalizeLine(e.text || '')));
  const seen = new Map(); // normalized -> {path, line} of first occurrence
  const admitted = new Map(); // normalized -> exception record, once per text
  for (const s of sections) {
    for (let i = 0; i < s.lines.length; i += 1) {
      const m = RULE_LINE_RE.exec(s.lines[i]);
      if (!m) continue;
      const normalized = normalizeLine(s.lines[i]);
      const occurrence = { path: s.path, line: i + 1 };
      const prior = seen.get(normalized);
      if (!prior) { seen.set(normalized, occurrence); continue; }
      if (exceptionTexts.has(normalized)) {
        if (!admitted.has(normalized)) {
          const ex = exceptions.find((e) => normalizeLine(e.text || '') === normalized);
          admitted.set(normalized, ex);
        }
        continue; // declared exception: not a refusal, keep scanning
      }
      return { refused: true, normalized, first: prior, second: occurrence, admitted: [...admitted.values()] };
    }
  }
  return { refused: false, admitted: [...admitted.values()] };
}

// --- build subcommand ---------------------------------------------------------

function parseBuildArgs(argv) {
  const opts = { manifest: DEFAULT_MANIFEST };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--role') { opts.role = argv[i + 1]; i += 1; }
    else if (a === '--ref') { opts.ref = argv[i + 1]; i += 1; }
    else if (a === '--manifest') { opts.manifest = argv[i + 1]; i += 1; }
    else usageError(`unrecognized argument: ${a}`);
  }
  if (!opts.role) usageError('--role is required');
  if (!opts.ref) usageError('--ref is required');
  return opts;
}

function runBuild(argv) {
  const opts = parseBuildArgs(argv);
  const manifest = loadManifest(opts.manifest);

  const resolution = resolveSections(manifest, opts.role, opts.ref);
  if (!resolution.ok) {
    process.stderr.write(`canon-section-absent: ${resolution.id} ${resolution.path}\n`);
    exit(3);
  }
  const { sections } = resolution;

  if (typeof manifest.standing_hazards === 'number' && !Number.isNaN(manifest.standing_hazards)) {
    const found = countHazardLines(sections);
    if (found !== manifest.standing_hazards) {
      process.stderr.write(
        `canon-count-mismatch: standing_hazards declared=${manifest.standing_hazards} found=${found}\n`
      );
      exit(4);
    }
  }

  const dup = findDuplicateRule(sections, manifest.uniqueness_exceptions);
  if (dup.refused) {
    process.stderr.write(
      `canon-duplicate-rule: "${dup.normalized}" ${dup.first.path}:${dup.first.line} ${dup.second.path}:${dup.second.line}\n`
    );
    exit(5);
  }

  const payload = framePayload(sections);
  const measured = Buffer.byteLength(payload, 'utf8');
  if (typeof manifest.byte_ceiling === 'number' && !Number.isNaN(manifest.byte_ceiling) && measured > manifest.byte_ceiling) {
    process.stderr.write(`canon-over-budget: measured=${measured} ceiling=${manifest.byte_ceiling}\n`);
    exit(6);
  }

  process.stdout.write(payload);
  for (const ex of dup.admitted) {
    process.stderr.write(`canon-duplicate-rule-exception: "${normalizeLine(ex.text)}" reason="${ex.reason || ''}"\n`);
  }
  process.stderr.write(`canon-build: role=${opts.role} ref=${opts.ref} bytes=${measured} sections=${sections.length}\n`);
  exit(0);
}

// --- main ----------------------------------------------------------------------

function main(argv) {
  const [cmd, ...rest] = argv;
  if (cmd === 'build') { runBuild(rest); return; }
  if (cmd === undefined || cmd === '-h' || cmd === '--help') {
    process.stdout.write('usage: node .aai/scripts/canon.mjs build --role <R> --ref <r> [--manifest <path>]\n');
    exit(cmd === undefined ? 2 : 0);
  }
  usageError(`unknown subcommand "${cmd}"`);
}

runMain(() => main(process.argv.slice(2)));

export { parseManifestText, resolveSections, framePayload, countHazardLines, findDuplicateRule, normalizeLine };
