#!/usr/bin/env node
// canon.mjs — the rules that bind a dispatched agent are ASSEMBLED and
// ASSERTED, never pasted (SPEC-DRAFT-spec-canon-is-a-build-artifact).
//
// THIS FILE (D1): ONE script, subcommands `build` / `check` / `claims`, all
// reading the same declaration (`.aai/system/CANON.yaml`) — three files
// would cost three PROFILES rows, three main guards and three refusal
// vocabularies for one mechanism. `build` (Spec-AC-01..07, including
// `--print-hash`) and `claims` (Spec-AC-08..10) are implemented; `check`
// lands in a later Test Plan row of the same spec (Spec-AC-12..13) and this
// file grows subcommands, not siblings.
//
// `build --role <R> --ref <r> [--manifest <path>] [--print-hash]` assembles
// the dispatch payload for role R from the manifest's declared, ORDERED
// sections (D3: every order/count/uniqueness assertion downstream reads
// THIS assembled payload, never the manifest — the manifest is an input,
// not a proof) and prints it, and ONLY it, to stdout: the orchestrator
// pastes stdout verbatim into a dispatch, so stdout carries nothing but the
// payload — every diagnostic (the measured byte size, an admitted
// duplicate's reason) goes to stderr, on success as much as on refusal
// (D4). `--print-hash` prints the telemetry digest instead of the payload
// (Spec-AC-06) — see the S2 comment above `computeCanonPrintHash` below.
//
// `claims [--manifest <path>]` scans the manifest's declared corpus for a
// withdrawn claim's patterns and refuses when a hit is not exempted by a
// declared `historical:` glob or a declared `**CORRECTION (<date>).**` /
// `**WITHDRAWN <date>**` annotation within `annotation_window` lines after
// the hit (D5). It also refuses when a declared claim's citing
// `hitl_decision` cannot be resolved in `docs/ai/decisions.jsonl`
// (Spec-AC-08..10).
//
// FAIL CLOSED (D4): every refusal prints a named reason token plus the
// offending file:line (and, for a count, both numbers) to stderr, and
// stdout is left completely EMPTY — never a truncated payload. `build`'s
// checks run in this order: section resolution (absent/empty), hazard
// count, duplicate rule, byte budget; the first violation found refuses and
// stops there. `claims` instead collects every un-exempted hit before
// refusing (Spec-AC-10: each planted variant must be reported with its own
// line, not just the first).
//
// Node stdlib only (docs/TECHNOLOGY.md) — no YAML dependency. CANON.yaml is
// parsed by a small hand-rolled, file-shape-specific parser below, the same
// discipline `.aai/system/PROFILES.yaml` already uses for its own line-based
// dialect (D2 comment in CANON.yaml itself).

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
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

const USAGE =
  'usage: node .aai/scripts/canon.mjs build --role <R> --ref <r> [--manifest <path>] [--print-hash]\n'
  + '       node .aai/scripts/canon.mjs claims [--manifest <path>]\n';

function usageError(msg) {
  process.stderr.write(`canon: ${msg}\n`);
  process.stderr.write(USAGE);
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
  const manifest = {
    roles: {},
    sections: [],
    standing_hazards: null,
    byte_ceiling: null,
    uniqueness_exceptions: [],
    historical: [],
    annotation_window: null,
    claims: [],
  };
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
    if (key === 'annotation_window') { manifest.annotation_window = parseInt(inline.trim(), 10); i += 1; continue; }
    if (key === 'historical') {
      if (inline.trim() === '[]') { i += 1; continue; }
      i += 1;
      while (i < lines.length && /^ {2}- /.test(lines[i])) {
        const m = /^ {2}- (.+)$/.exec(lines[i]);
        if (m) manifest.historical.push(stripQuotes(m[1]));
        i += 1;
      }
      continue;
    }
    if (key === 'claims') {
      if (inline.trim() === '[]') { i += 1; continue; }
      i += 1;
      while (i < lines.length && /^ {2}- /.test(lines[i])) {
        const claim = { corpus: [], patterns: [] };
        const idm = /^ {2}- id:\s*(.+)$/.exec(lines[i]);
        if (idm) claim.id = stripQuotes(idm[1]);
        i += 1;
        while (i < lines.length && /^ {4}\S/.test(lines[i])) {
          const fm = /^ {4}(\w+):\s*(.*)$/.exec(lines[i]);
          if (fm && (fm[1] === 'corpus' || fm[1] === 'patterns')) {
            const listKey = fm[1];
            i += 1;
            while (i < lines.length && /^ {6}- /.test(lines[i])) {
              const im = /^ {6}- (.+)$/.exec(lines[i]);
              if (im) claim[listKey].push(stripQuotes(im[1]));
              i += 1;
            }
            continue;
          }
          if (fm) claim[fm[1]] = stripQuotes(fm[2]);
          i += 1;
        }
        manifest.claims.push(claim);
      }
      continue;
    }
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

// --- telemetry hash (Spec-AC-06) ----------------------------------------------
//
// S2 (the PAYLOAD and the TELEMETRY seam, spec Seams section): this is an
// INDEPENDENT reimplementation of `.aai/scripts/lib/prompt-hash.mjs`'s
// `computeEffectivePromptHash` — same three inputs (the role prompt,
// `.aai/SUBAGENT_CONTRACT.md`, `docs/knowledge/LEARNED.md`), the same
// "--- name ---" framing, the same ABSENT marker for a missing file — NOT a
// delegate call into that module. Two independent orderings of the same
// three files would make the effective-prompt-hash telemetry
// `state.mjs append-run` records describe a stack `canon.mjs` never
// actually assembled; TEST-682 and TEST-683 run BOTH this function and
// `prompt-hash.mjs`'s on one tree and assert the digests agree, so an edit
// to either one's fixed order is caught here rather than discovered later
// as telemetry nobody can trust.
const HASH_ABSENT = 'ABSENT';
const HASH_CONTRACT_REL = '.aai/SUBAGENT_CONTRACT.md';
const HASH_LEARNED_REL = 'docs/knowledge/LEARNED.md';
const HASH_INPUT_ORDER = ['role', 'contract', 'learned'];

function computeCanonPrintHash(rolePromptRelPath, root) {
  const inputs = { role: rolePromptRelPath, contract: HASH_CONTRACT_REL, learned: HASH_LEARNED_REL };
  const hash = crypto.createHash('sha256');
  for (const key of HASH_INPUT_ORDER) {
    const relPath = inputs[key];
    const abs = path.resolve(root, relPath);
    let body;
    try { body = fs.readFileSync(abs); } catch { body = null; }
    hash.update(`\n--- ${path.basename(relPath)} ---\n`);
    hash.update(body === null ? HASH_ABSENT : body);
  }
  return hash.digest('hex');
}

// --- build subcommand ---------------------------------------------------------

function parseBuildArgs(argv) {
  const opts = { manifest: DEFAULT_MANIFEST, printHash: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--role') { opts.role = argv[i + 1]; i += 1; }
    else if (a === '--ref') { opts.ref = argv[i + 1]; i += 1; }
    else if (a === '--manifest') { opts.manifest = argv[i + 1]; i += 1; }
    else if (a === '--print-hash') { opts.printHash = true; }
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

  if (opts.printHash) {
    const rolePath = manifest.roles[opts.role];
    const digest = computeCanonPrintHash(rolePath, ROOT);
    process.stdout.write(`${digest}\n`);
    exit(0);
  }

  process.stdout.write(payload);
  for (const ex of dup.admitted) {
    process.stderr.write(`canon-duplicate-rule-exception: "${normalizeLine(ex.text)}" reason="${ex.reason || ''}"\n`);
  }
  process.stderr.write(`canon-build: role=${opts.role} ref=${opts.ref} bytes=${measured} sections=${sections.length}\n`);
  exit(0);
}

// --- claims corpus glob helpers (Spec-AC-08..10) --------------------------------
//
// A small hand-rolled `**` / `*` glob matcher — node stdlib only
// (docs/TECHNOLOGY.md), matching the discipline the rest of this file
// already uses. `**` matches zero or more path segments (including the
// separating slash); `*` matches within one segment.

function globToRegExp(glob) {
  const DOUBLE_STAR = '\u0000AAI-CANON-DOUBLE-STAR\u0000';
  let pattern = glob.replace(/\*\*/g, DOUBLE_STAR);
  pattern = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  pattern = pattern.replace(/\*/g, '[^/]*');
  pattern = pattern.split(DOUBLE_STAR).join('.*');
  return new RegExp(`^${pattern}$`);
}

// globWalkRoot(glob) -> the directory (or literal file) to walk for a glob,
// derived from the glob's own text (never a hardcoded "docs/tests/.aai"
// list) — the segment prefix before the first wildcard.
function globWalkRoot(glob) {
  const idx = glob.indexOf('*');
  if (idx === -1) return glob;
  const prefix = glob.slice(0, idx);
  const lastSlash = prefix.lastIndexOf('/');
  return lastSlash === -1 ? '.' : prefix.slice(0, lastSlash);
}

function walkFiles(root, relDir) {
  const absDir = path.resolve(root, relDir);
  let out = [];
  let entries;
  try { entries = fs.readdirSync(absDir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const relPath = relDir === '.' ? e.name : `${relDir}/${e.name}`;
    if (e.isDirectory()) out = out.concat(walkFiles(root, relPath));
    else if (e.isFile()) out.push(relPath);
  }
  return out;
}

// collectCorpusFiles(root, globs) -> deduped, root-relative file paths
// matching any declared glob (D2: the corpus is what the manifest
// declares, not a hand-chosen path set — the exact hazard
// `fu-sweep-scope-excludes-repo-root` names).
function collectCorpusFiles(root, globs) {
  const seen = new Set();
  const files = [];
  for (const glob of globs) {
    const walkRoot = globWalkRoot(glob);
    const abs = path.resolve(root, walkRoot);
    let isDir = false;
    try { isDir = fs.statSync(abs).isDirectory(); } catch { /* absent: no candidates */ }
    const candidates = isDir ? walkFiles(root, walkRoot) : [walkRoot];
    const re = globToRegExp(glob);
    for (const relPath of candidates) {
      if (re.test(relPath) && !seen.has(relPath)) {
        seen.add(relPath);
        files.push(relPath);
      }
    }
  }
  return files;
}

function isHistorical(relPath, historicalGlobs) {
  return historicalGlobs.some((g) => globToRegExp(g).test(relPath));
}

// --- claims subcommand ---------------------------------------------------------
//
// D5: a hit is exempt ONLY by declaration — a `historical:` glob match, or a
// declared annotation marker (`**CORRECTION (<date>).**` / `**WITHDRAWN
// <date>**`) within `annotation_window` lines after the hit. Both routes
// are visible in CANON.yaml; there is no third, undeclared exemption.
const ANNOTATION_RE = /\*\*(CORRECTION \(\d{4}-\d{2}-\d{2}\)\.|WITHDRAWN \d{4}-\d{2}-\d{2})\*\*/;

function resolveClaimDecision(root, claim) {
  const decisionsPath = path.resolve(root, 'docs/ai/decisions.jsonl');
  let text;
  try { text = fs.readFileSync(decisionsPath, 'utf8'); } catch { return false; }
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    let rec;
    try { rec = JSON.parse(line); } catch { continue; }
    if (
      rec && rec.type === 'hitl_decision'
      && rec.ref_id === claim.decision_ref
      && rec.ts === claim.decision_ts
    ) {
      return true;
    }
  }
  return false;
}

// findClaimHits(root, claim, historicalGlobs, window) -> every un-exempted
// occurrence of a declared pattern in the declared corpus, in
// file/line order — ALL of them, not just the first (Spec-AC-10: two
// planted variants must each be reported on their own line).
function findClaimHits(root, claim, historicalGlobs, window) {
  const files = collectCorpusFiles(root, claim.corpus);
  const hits = [];
  let scanned = 0;
  for (const relPath of files) {
    if (isHistorical(relPath, historicalGlobs)) continue;
    let content;
    try { content = fs.readFileSync(path.resolve(root, relPath), 'utf8'); } catch { continue; }
    scanned += 1;
    const lines = content.replace(/\r\n/g, '\n').split('\n');
    for (let i = 0; i < lines.length; i += 1) {
      const hit = claim.patterns.some((p) => lines[i].includes(p));
      if (!hit) continue;
      let exempt = false;
      for (let w = i; w <= i + window && w < lines.length; w += 1) {
        if (ANNOTATION_RE.test(lines[w])) { exempt = true; break; }
      }
      if (!exempt) hits.push({ path: relPath, line: i + 1 });
    }
  }
  return { hits, scanned };
}

function parseClaimsArgs(argv) {
  const opts = { manifest: DEFAULT_MANIFEST };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--manifest') { opts.manifest = argv[i + 1]; i += 1; }
    else usageError(`unrecognized argument: ${a}`);
  }
  return opts;
}

function runClaims(argv) {
  const opts = parseClaimsArgs(argv);
  const manifest = loadManifest(opts.manifest);
  const window = typeof manifest.annotation_window === 'number' && !Number.isNaN(manifest.annotation_window)
    ? manifest.annotation_window
    : 0;

  let refused = false;
  let totalScanned = 0;
  for (const claim of manifest.claims) {
    if (!resolveClaimDecision(ROOT, claim)) {
      process.stderr.write(`claim-record-unresolvable: ${claim.id} ${claim.decision_ref} ${claim.decision_ts}\n`);
      exit(7);
    }
    const { hits, scanned } = findClaimHits(ROOT, claim, manifest.historical, window);
    totalScanned += scanned;
    if (hits.length > 0) {
      refused = true;
      for (const h of hits) {
        process.stderr.write(`claim-live-assertion: ${claim.id} ${h.path}:${h.line}\n`);
      }
    } else {
      process.stderr.write(`canon-claims: id=${claim.id} scanned=${scanned} clean\n`);
    }
  }
  if (refused) exit(8);
  process.stderr.write(`canon-claims: claims=${manifest.claims.length} scanned=${totalScanned} clean\n`);
  exit(0);
}

// --- main ----------------------------------------------------------------------

function main(argv) {
  const [cmd, ...rest] = argv;
  if (cmd === 'build') { runBuild(rest); return; }
  if (cmd === 'claims') { runClaims(rest); return; }
  if (cmd === undefined || cmd === '-h' || cmd === '--help') {
    process.stdout.write(USAGE);
    exit(cmd === undefined ? 2 : 0);
  }
  usageError(`unknown subcommand "${cmd}"`);
}

runMain(() => main(process.argv.slice(2)));

export {
  parseManifestText,
  resolveSections,
  framePayload,
  countHazardLines,
  findDuplicateRule,
  normalizeLine,
  computeCanonPrintHash,
  globToRegExp,
  collectCorpusFiles,
  findClaimHits,
};
