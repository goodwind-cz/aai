#!/usr/bin/env node
//
// merge-policy.mjs — the ONE deterministic evaluator for a project-owned,
// owner-signed merge policy (docs/ai/merge-policy.yaml), SPEC-DRAFT
// spec-configurable-merge-policy-lanes.
//
// Implements the full P1-P10 contract: closed-shape policy parsing
// (parsePolicy), policy-wide validation (validatePolicy — decision binding,
// deploy consistency/opt-ins, duplicate/missing keys, marker shape),
// base-only reads (readAtBase), P5 classification (classifyFiles,
// globToRegExp), P6 requester approval (requesterApproved), P8 ride inputs
// (readRideCeremony, readIntakeMeta, defaulting to STATE current_focus when
// no --spec/--intake/--state is given — Spec-AC-18/validation-round1 B1),
// P7/P9 CI and sweep-check gates (ciGreen, runSweepCheck) and the P10
// output/exit contract. The hook lane path (claude-hook-gate.sh) and the
// repo policy/prompts/doctor/constitution migration (Spec-AC-02/14/18..23)
// are implemented alongside this file; see docs/specs/
// SPEC-DRAFT-spec-configurable-merge-policy-lanes.md for the full mapping.
//
// Modes:
//   --check --pr <n> [--repo-root <dir>] [--debug-inputs]
//     [--spec <path>] [--intake <path>] [--state <path>]
//   --validate [--path <file>] [--repo-root <dir>]
//   --classify --path <policy> --files-from <path|-> [--repo-root <dir>]
//
// Node stdlib only (docs/TECHNOLOGY.md) — no YAML library; the policy file
// is a closed-shape, line-level parse (same discipline as
// .aai/scripts/lib/roadmap-model.mjs).

import { execFileSync } from 'node:child_process';
import {
  readFileSync, existsSync, realpathSync, mkdtempSync, writeFileSync, rmSync,
} from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { loadRoadmap } from './lib/roadmap-model.mjs';

const SELF_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO_ROOT = resolve(SELF_DIR, '..', '..');

export const POLICY_PATH = 'docs/ai/merge-policy.yaml';
export const DECISIONS_PATH = 'docs/ai/decisions.jsonl';

// P4 — GUARD_PATHS: the policy file, this evaluator, the hook adapter,
// lane-gate.mjs, and every lib module either this file or lane-gate.mjs
// imports (TEST-1507 proves this set is a superset of that real import
// closure, read via a live `import`, not restated by hand elsewhere).
export const GUARD_PATHS = [
  'docs/ai/merge-policy.yaml',
  '.aai/scripts/merge-policy.mjs',
  '.aai/scripts/claude-hook-gate.sh',
  '.aai/scripts/lane-gate.mjs',
  '.aai/scripts/lib/cli-pipe-guard.mjs',
  '.aai/scripts/lib/pr-sweep.mjs',
  '.aai/scripts/lib/roadmap-model.mjs',
  // validation-round1 NB-3: not an `import`, so the closure probe (TEST-1507)
  // never finds these on its own — lane-gate.mjs SPAWNS select-suites.mjs
  // (runSelectSuites) and both of them READ these two config files directly
  // (profilesCore, the docs-audit.yaml protected_paths_l3 reader). A PR
  // editing any of the four changes the --sweep-check verdict exactly as
  // editing lane-gate.mjs itself would, so they guard the same way.
  '.aai/scripts/select-suites.mjs',
  'tests/skills/suite-map.yaml',
  'docs/ai/docs-audit.yaml',
  '.aai/system/PROFILES.yaml',
];

export const MARKER_RE = /^AAI_[A-Z0-9_]+_MERGE$/;
export const DEFAULT_MAX_CEREMONY = 2;

export const EXIT_ALLOWED = 0;
const EXIT_USAGE = 2;
export const EXIT_DENIED = 3;
export const EXIT_NO_POLICY = 4;

// ---------------------------------------------------------------------------
// Closed-shape, line-level policy parsing (P1). No YAML library — a
// deliberately narrow parser for the exact schema the spec documents.
// ---------------------------------------------------------------------------

function stripComment(line) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === "'" && !inDouble) inSingle = !inSingle;
    else if (c === '"' && !inSingle) inDouble = !inDouble;
    else if (c === '#' && !inSingle && !inDouble) {
      if (i === 0 || /\s/.test(line[i - 1])) return line.slice(0, i);
    }
  }
  return line;
}

// lineNo is the physical (1-based) line number in the source text, BEFORE
// blank/comment-only lines are dropped -- the round-trip check (checkRoundTrip
// below, called from parsePolicy) names it on a `noncanonical` finding so a
// diff points at a real place in the file, not an index into this filtered
// array.
function tokenizeLines(text) {
  const rawLines = String(text).replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  for (let idx = 0; idx < rawLines.length; idx += 1) {
    const stripped = stripComment(rawLines[idx]);
    if (!stripped.trim()) continue;
    const indent = stripped.length - stripped.replace(/^ */, '').length;
    out.push({ indent, content: stripped.trim(), lineNo: idx + 1 });
  }
  return out;
}

function splitKV(content) {
  const idx = content.indexOf(':');
  if (idx === -1) return null;
  return { key: content.slice(0, idx).trim(), rest: content.slice(idx + 1).trim() };
}

function parseScalar(raw) {
  const s = String(raw).trim();
  if (s === 'true') return true;
  if (s === 'false') return false;
  if (/^-?\d+$/.test(s)) return Number(s);
  if ((s.startsWith('"') && s.endsWith('"') && s.length >= 2)
      || (s.startsWith("'") && s.endsWith("'") && s.length >= 2)) {
    return s.slice(1, -1);
  }
  return s;
}

// round-3 NB-3 — a comma-split that does not respect quoting silently
// NARROWS a malformed list to junk items instead of failing closed: a
// literal comma meant as DATA inside quotes (`["a,b"]`) splits into two
// halves, each missing the quote character that would have closed it
// (`"a` / `b"`); a second bracket pair trailing the list (`[a] [b]`) passes
// the bare start-with-`[`/end-with-`]` check and inner-slices to `a] [b`,
// one "item" carrying stray `[`/`]` text. Neither shape is on offer in P1 —
// quoting is for a scalar that needs it, not for escaping a separator — so
// any split item that is not ITSELF a single well-quoted token, and still
// carries a quote or bracket/brace character, is the tell that the comma
// split cut through something it should not have: reject the whole list.
function parseFlowList(raw) {
  const s = String(raw).trim();
  if (!s.startsWith('[') || !s.endsWith(']')) return null;
  const inner = s.slice(1, -1).trim();
  if (inner === '') return [];
  const tokens = inner.split(',').map((x) => x.trim());
  const items = [];
  for (const tok of tokens) {
    if (tok !== '') {
      // A token is cleanly quoted only when its FIRST and LAST characters
      // are a matching quote pair AND nothing in between repeats that same
      // quote character — `"a"] ["b"` (a trailing bracket pair after the
      // list) starts and ends with `"` too, but its middle still carries
      // the stray `]`/`[`/`"` this check exists to catch.
      const q = (tok[0] === '"' || tok[0] === "'") ? tok[0] : '';
      const quoted = q !== '' && tok.length >= 2 && tok[tok.length - 1] === q
        && !tok.slice(1, -1).includes(q);
      if (!quoted && /['"[\]{}]/.test(tok)) return null;
    }
    items.push(parseScalar(tok));
  }
  return items;
}

// parseRequiredList(raw) -> array | null (invalid) — validation-round2 R2-B2.
// A list-typed policy key (`kinds`, `requester_logins`, `intake_types`) is
// closed-shape (P1): ONLY a well-formed `[...]` flow list, never a bare
// scalar read as a one-element list, a quoted string that merely LOOKS like
// a list (`"[change]"` is the STRING `[change]`, not a list), or an
// unclosed/malformed one — every one of those silently dropped the written
// condition in round-1/round-2 (evaluateLane never even saw it, because the
// generic scalar-or-list dispatch below only called parseFlowList when the
// raw text itself started with `[`). parseFlowList already rejects anything
// not literally bracketed; this adds the one further rule P1 names for a
// list's own items — an empty item (`[alice,]`, `[,bob]`) is invalid too. An
// explicitly empty list (`[]`) is NOT rejected here: it parses to `[]` and
// evaluateLane/validatePolicy fail closed on that already (an empty
// intake_types matches no ride; an empty requester_logins skips the
// approval check only because merge_reaches is nothing, exactly as a lane
// that never wrote the key at all) — a real, if unusual, policy shape, not
// a parse failure.
function parseRequiredList(raw) {
  const list = parseFlowList(raw);
  if (list === null) return null;
  if (list.some((x) => x === '')) return null;
  return list;
}

const TOP_KEYS = new Set(['version', 'deploy', 'architecture', 'kinds', 'lanes']);
const DEPLOY_KEYS = new Set(['preview', 'production_on_merge']);
const LANE_SCALAR_KEYS = [
  'decision_ref', 'decision_match', 'signed_by', 'kinds', 'merge_reaches',
  'allow_public_side_effect', 'max_ceremony', 'marker', 'requester_logins',
];

// validation-round1 B2 — every lane must carry these (missing_key); max_ceremony
// and requires are the only genuinely optional lane keys (P1: "optional; absent
// means 2" / "optional ride conditions"), and requester_logins is required only
// WHEN merge_reaches is not `nothing` (P6 — requester_missing, not missing_key).
const REQUIRED_LANE_KEYS = [
  'decision_ref', 'decision_match', 'signed_by', 'kinds', 'merge_reaches', 'marker',
];

// validation-round1 B2 — the only two genuinely closed-set scalar enums P1
// defines. Any OTHER value (`PUBLIC`, `publik`, a typo) is a `parse_error`,
// same discipline as every other closed-shape violation in this parser —
// never a value that silently reads as neither member of the set.
const DEPLOY_PREVIEW_ENUM = new Set(['none', 'private', 'public']);
const MERGE_REACHES_ENUM = new Set(['nothing', 'preview', 'production']);

// validation-round1 B2 — boolean-typed keys get the STRICT parse
// (parseBooleanScalar below) instead of the generic parseScalar: a quoted or
// non-canonical value (`"true"` is fine; `True`, `yes`, `publik`) must never
// silently become a string that a later `=== true` predicate reads as false.
const BOOLEAN_REQUIRES_KEYS = new Set([
  'exclude_roadmap_capability', 'validation_pass', 'review_pass',
]);

// Spec-AC-15 — the full `requires` allowlist (P1): any key outside these
// five is `unknown_key`, the same closed-shape discipline as every other
// policy key. Spec-AC-09's `ci`/`sweep_check` prohibition falls out of this
// allowlist for free — CI and the sweep check are mandatory and never
// configurable, so no key naming either one is ever legal here.
const ALLOWED_REQUIRES_KEYS = new Set([
  'intake_types', 'exclude_roadmap_capability', 'validation_pass',
  'review_pass', 'pr_body_contains',
]);

// ---------------------------------------------------------------------------
// P1 round-trip (remediation round 4, validation-round3 R3-B1). Closes the
// whole "the parser silently drops what it does not understand" class in
// ONE mechanism instead of a per-shape patch: parsePolicy re-emits the
// policy it just built in ONE canonical text form (fixed key order,
// two-space indentation, block style for `- id:` mappings, flow style
// `[a, b]` for every scalar list, canonical scalars) and requires that
// text to equal the source file line for line, after only meaning-
// preserving normalization (comments/CRLF/BOM/blank lines stripped,
// equivalent scalar spellings canonicalized — never a regex over meaning).
// Anything the parser skipped, ignored or misread then shows up as a diff:
// inline content on a line that is really just a block header (`deploy:
// {...}`, `architecture: [...]`, a lane's `requires: {...}`) has no
// canonical counterpart, because the canonical form for that header is
// ALWAYS the bare key with nothing after the colon — the exact R3-B1 shape.
// A `noncanonical` finding names the first source line the two disagree on.
//
// The emission order below is each schema-fixed field order already
// defined above as a constant (DEPLOY_KEYS, LANE_SCALAR_KEYS,
// ALLOWED_REQUIRES_KEYS), reused rather than restated so the two can never
// drift apart from each other.
const DEPLOY_ORDER = [...DEPLOY_KEYS];
const LANE_ORDER = [...LANE_SCALAR_KEYS, 'requires'];
const REQUIRES_ORDER = [...ALLOWED_REQUIRES_KEYS];

// needsQuoteScalar(s) -> bool. A bare (unquoted) spelling of `s` must read
// back, through parseScalar, as the SAME string — never as a boolean, a
// number, nor (via leading/trailing whitespace) a shorter string, nor (via
// a list/comment/quote metacharacter) something splitKV/parseFlowList
// would itself cut on. Quoting is otherwise never required: this is the
// one shared rule canonicalScalarText below applies to BOTH the emitted
// value (from the parsed object) and the source's own value (re-derived
// from its raw text by the same parse functions) — so an accepted
// alternate spelling (quoted vs bare, `"true"` vs `true`) always
// canonicalizes to identical bytes on both sides, by construction, not by
// matching the source's own quoting choice.
function needsQuoteScalar(s) {
  if (s === '' || s === 'true' || s === 'false') return true;
  if (/^-?\d+$/.test(s)) return true;
  if (/[,[\]{}"'#]/.test(s)) return true;
  if (/^\s|\s$/.test(s)) return true;
  return false;
}

function canonicalScalarText(v) {
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return String(v);
  const s = String(v);
  return needsQuoteScalar(s) ? `"${s.replace(/"/g, '\\"')}"` : s;
}

function canonicalValueText(v) {
  return Array.isArray(v) ? `[${v.map(canonicalScalarText).join(', ')}]` : canonicalScalarText(v);
}

// isEmptyHeaderRest(rest) -> bool. A block-introducing key's canonical form
// is always the bare key; `rest` naming the R3-B1 shape is any TEXT there
// at all -- EXCEPT an explicit empty collection (`[]` or `{}`), which loses
// nothing (omitting the key entirely means exactly the same "zero
// entries") and is accepted as the one equivalent spelling of "nothing was
// written here".
function isEmptyHeaderRest(rest) {
  return rest === '' || rest === '[]' || rest === '{}';
}

// emitCanonical(policy, meta) -> string[]. `meta` names exactly which
// optional piece was WRITTEN at all — a parsed value alone cannot tell,
// since several fields are defaulted in (e.g. `deploy` itself, or a lane's
// `requester_logins`, always present on the object even when the source
// never wrote them).
function emitCanonical(policy, meta) {
  const out = [`version: ${canonicalValueText(policy.version)}`];
  if (meta.seenTop.has('deploy')) {
    out.push('deploy:');
    for (const k of DEPLOY_ORDER) {
      if (meta.seenDeploy.has(k)) out.push(`  ${k}: ${canonicalValueText(policy.deploy[k])}`);
    }
  }
  for (const topKey of ['architecture', 'kinds']) {
    if (!meta.seenTop.has(topKey)) continue;
    out.push(`${topKey}:`);
    for (const item of policy[topKey]) {
      out.push(`  - id: ${canonicalValueText(item.id)}`);
      out.push(`    globs: ${canonicalValueText(item.globs)}`);
    }
  }
  if (meta.seenTop.has('lanes')) {
    out.push('lanes:');
    policy.lanes.forEach((lane, idx) => {
      const seen = meta.laneSeen[idx];
      out.push(`  - id: ${canonicalValueText(lane.id)}`);
      for (const k of LANE_ORDER) {
        if (k === 'requires') {
          if (seen.has('requires')) {
            out.push('    requires:');
            for (const rk of REQUIRES_ORDER) {
              if (Object.prototype.hasOwnProperty.call(lane.requires, rk)) {
                out.push(`      ${rk}: ${canonicalValueText(lane.requires[rk])}`);
              }
            }
          }
          continue;
        }
        if (seen.has(k)) out.push(`    ${k}: ${canonicalValueText(lane[k])}`);
      }
    });
  }
  return out;
}

// parseBooleanScalar(raw) -> true | false | undefined (invalid) —
// validation-round1 B2. P1 allows quoting, but a boolean-typed field accepts
// ONLY the canonical `true`/`false` token, bare or quoted — never a case
// variant, a yes/no word, or any other value that would otherwise silently
// read as the OPPOSITE of its real intent under a later `=== true` check.
function parseBooleanScalar(raw) {
  const s = String(raw).trim();
  const unquoted = ((s.startsWith('"') && s.endsWith('"') && s.length >= 2)
    || (s.startsWith("'") && s.endsWith("'") && s.length >= 2))
    ? s.slice(1, -1)
    : s;
  if (unquoted === 'true') return true;
  if (unquoted === 'false') return false;
  return undefined;
}

// parsePolicy(text) -> { policy } | { errors }. Closed shape, P1. The parse-
// time errors (parse_error, unknown_key, empty_globs, duplicate_key,
// missing_key) are detected here; duplicate_lane, undefined_kind, bad_marker,
// duplicate_marker, reaches_inconsistent, public_effect_not_opted_in,
// requester_missing and bad_ceremony are structural but policy-wide, so they
// are detected in validatePolicy once a full `policy` object exists
// (Spec-AC-10/12/13, validation-round1 B2).
export function parsePolicy(text) {
  let lines;
  try {
    lines = tokenizeLines(String(text));
  } catch {
    return { errors: [{ lane: '-', code: 'parse_error' }] };
  }
  const policy = {
    version: null,
    deploy: { preview: 'none', production_on_merge: false },
    architecture: [],
    kinds: [],
    lanes: [],
  };
  let i = 0;
  const seenTop = new Set();
  // origNorm — the source's own lines, in SOURCE order, each normalized to
  // the same canonical text emitCanonical would produce for that exact
  // value (round-trip check below; see the comment above emitCanonical). A
  // block-introducing line (deploy/architecture/kinds/lanes/requires) has
  // no "value" of its own — its canonical form is always the bare key — so
  // it is pushed literally (key + its raw rest, if any) instead: that is
  // precisely the R3-B1 shape (an inline value the parser never reads) and
  // it only ever disagrees with emitCanonical's bare-key line when rest is
  // non-empty.
  const origNorm = [];
  const meta = { seenTop, seenDeploy: new Set(), laneSeen: [] };
  try {
    while (i < lines.length) {
      const { indent, content } = lines[i];
      if (indent !== 0) return { errors: [{ lane: '-', code: 'parse_error' }] };
      const kv = splitKV(content);
      if (!kv) return { errors: [{ lane: '-', code: 'parse_error' }] };
      const { key, rest } = kv;
      if (!TOP_KEYS.has(key)) return { errors: [{ lane: '-', code: 'unknown_key' }] };
      if (seenTop.has(key)) return { errors: [{ lane: '-', code: 'duplicate_key' }] };
      seenTop.add(key);

      if (key === 'version') {
        policy.version = parseScalar(rest);
        origNorm.push({ lineNo: lines[i].lineNo, text: `version: ${canonicalValueText(policy.version)}` });
        i += 1;
        continue;
      }

      if (key === 'deploy') {
        origNorm.push({ lineNo: lines[i].lineNo, text: isEmptyHeaderRest(rest) ? 'deploy:' : `deploy: ${rest}` });
        i += 1;
        const block = {};
        const seenDeploy = new Set();
        while (i < lines.length && lines[i].indent === 2) {
          const kv2 = splitKV(lines[i].content);
          if (!kv2 || !DEPLOY_KEYS.has(kv2.key)) return { errors: [{ lane: '-', code: 'unknown_key' }] };
          if (seenDeploy.has(kv2.key)) return { errors: [{ lane: '-', code: 'duplicate_key' }] };
          seenDeploy.add(kv2.key);
          if (kv2.key === 'production_on_merge') {
            const b = parseBooleanScalar(kv2.rest);
            if (b === undefined) return { errors: [{ lane: '-', code: 'parse_error' }] };
            block[kv2.key] = b;
          } else {
            const v = parseScalar(kv2.rest);
            if (!DEPLOY_PREVIEW_ENUM.has(v)) return { errors: [{ lane: '-', code: 'parse_error' }] };
            block[kv2.key] = v;
          }
          origNorm.push({ lineNo: lines[i].lineNo, text: `  ${kv2.key}: ${canonicalValueText(block[kv2.key])}` });
          i += 1;
        }
        policy.deploy = {
          preview: block.preview ?? 'none',
          production_on_merge: block.production_on_merge ?? false,
        };
        meta.seenDeploy = seenDeploy;
        continue;
      }

      if (key === 'architecture' || key === 'kinds') {
        origNorm.push({ lineNo: lines[i].lineNo, text: isEmptyHeaderRest(rest) ? `${key}:` : `${key}: ${rest}` });
        i += 1;
        const list = [];
        while (i < lines.length && lines[i].indent === 2 && lines[i].content.startsWith('- ')) {
          const first = lines[i].content.slice(2).trim();
          const kvId = splitKV(first);
          if (!kvId || kvId.key !== 'id') return { errors: [{ lane: '-', code: 'parse_error' }] };
          const item = { id: parseScalar(kvId.rest), globs: [] };
          origNorm.push({ lineNo: lines[i].lineNo, text: `  - id: ${canonicalValueText(item.id)}` });
          i += 1;
          let sawGlobs = false;
          while (i < lines.length && lines[i].indent === 4) {
            const kv3 = splitKV(lines[i].content);
            if (!kv3 || kv3.key !== 'globs') return { errors: [{ lane: item.id, code: 'unknown_key' }] };
            const g = parseFlowList(kv3.rest);
            if (g === null) return { errors: [{ lane: item.id, code: 'parse_error' }] };
            if (g.length === 0 || g.some((x) => x === '')) {
              return { errors: [{ lane: item.id, code: 'empty_globs' }] };
            }
            item.globs = g;
            sawGlobs = true;
            origNorm.push({ lineNo: lines[i].lineNo, text: `    globs: ${canonicalValueText(g)}` });
            i += 1;
          }
          // P1 names `globs` on every architecture/kind entry; an entry
          // that never writes it used to stay VALID with globs silently
          // `[]` (matches nothing) instead of failing closed
          // (validation-round3 R3-B1, the smaller related gap).
          if (!sawGlobs) return { errors: [{ lane: item.id, code: 'missing_key' }] };
          list.push(item);
        }
        policy[key] = list;
        continue;
      }

      if (key === 'lanes') {
        origNorm.push({ lineNo: lines[i].lineNo, text: isEmptyHeaderRest(rest) ? 'lanes:' : `lanes: ${rest}` });
        i += 1;
        const lanes = [];
        while (i < lines.length && lines[i].indent === 2 && lines[i].content.startsWith('- ')) {
          const first = lines[i].content.slice(2).trim();
          const kvId = splitKV(first);
          if (!kvId || kvId.key !== 'id') return { errors: [{ lane: '-', code: 'parse_error' }] };
          const lane = { id: parseScalar(kvId.rest) };
          origNorm.push({ lineNo: lines[i].lineNo, text: `  - id: ${canonicalValueText(lane.id)}` });
          i += 1;
          const seenLaneKeys = new Set();
          while (i < lines.length && lines[i].indent === 4) {
            const kv3 = splitKV(lines[i].content);
            if (!kv3) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
            if (kv3.key === 'requires') {
              if (seenLaneKeys.has('requires')) return { errors: [{ lane: lane.id, code: 'duplicate_key' }] };
              seenLaneKeys.add('requires');
              origNorm.push({
                lineNo: lines[i].lineNo,
                text: isEmptyHeaderRest(kv3.rest) ? '    requires:' : `    requires: ${kv3.rest}`,
              });
              i += 1;
              const requires = {};
              const seenRequires = new Set();
              while (i < lines.length && lines[i].indent === 6) {
                const kv4 = splitKV(lines[i].content);
                if (!kv4) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
                if (!ALLOWED_REQUIRES_KEYS.has(kv4.key)) {
                  return { errors: [{ lane: lane.id, code: 'unknown_key' }] };
                }
                if (seenRequires.has(kv4.key)) return { errors: [{ lane: lane.id, code: 'duplicate_key' }] };
                seenRequires.add(kv4.key);
                if (BOOLEAN_REQUIRES_KEYS.has(kv4.key)) {
                  const b = parseBooleanScalar(kv4.rest);
                  if (b === undefined) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
                  requires[kv4.key] = b;
                } else if (kv4.key === 'intake_types') {
                  // R2-B2: list-typed, closed shape — a scalar, an
                  // unclosed list or a quoted pseudo-list ("[change]") is
                  // parse_error, never silently kept as a value evaluateLane
                  // then has to guess the type of (round-1/round-2 both
                  // shipped exactly that silent drop).
                  const list = parseRequiredList(kv4.rest);
                  if (list === null) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
                  requires[kv4.key] = list;
                } else {
                  // pr_body_contains: the only remaining requires key, and a
                  // plain string — R2-B2 requires it non-empty (an empty
                  // needle is `"".includes("")` === true for every body,
                  // i.e. a written condition that silently never denies).
                  const v = parseScalar(kv4.rest);
                  if (typeof v !== 'string' || v === '') {
                    return { errors: [{ lane: lane.id, code: 'parse_error' }] };
                  }
                  requires[kv4.key] = v;
                }
                origNorm.push({
                  lineNo: lines[i].lineNo,
                  text: `      ${kv4.key}: ${canonicalValueText(requires[kv4.key])}`,
                });
                i += 1;
              }
              lane.requires = requires;
              continue;
            }
            if (!LANE_SCALAR_KEYS.includes(kv3.key)) return { errors: [{ lane: lane.id, code: 'unknown_key' }] };
            if (seenLaneKeys.has(kv3.key)) return { errors: [{ lane: lane.id, code: 'duplicate_key' }] };
            seenLaneKeys.add(kv3.key);
            if (kv3.key === 'merge_reaches') {
              const v = parseScalar(kv3.rest);
              if (!MERGE_REACHES_ENUM.has(v)) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
              lane[kv3.key] = v;
            } else if (kv3.key === 'allow_public_side_effect') {
              const b = parseBooleanScalar(kv3.rest);
              if (b === undefined) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
              lane[kv3.key] = b;
            } else if (kv3.key === 'kinds' || kv3.key === 'requester_logins') {
              // R2-B2: list-typed, closed shape — same discipline as
              // `requires.intake_types` above. A scalar `kinds: code` (no
              // brackets) used to be silently wrapped into a one-element
              // list by the normalization below instead of being rejected;
              // a malformed `requester_logins: [alice` (unclosed) used to
              // fold to an empty list and drop the owner's approval
              // requirement entirely.
              const list = parseRequiredList(kv3.rest);
              if (list === null) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
              lane[kv3.key] = list;
            } else {
              lane[kv3.key] = kv3.rest.trim().startsWith('[') ? parseFlowList(kv3.rest) : parseScalar(kv3.rest);
            }
            origNorm.push({ lineNo: lines[i].lineNo, text: `    ${kv3.key}: ${canonicalValueText(lane[kv3.key])}` });
            i += 1;
          }
          for (const rk of REQUIRED_LANE_KEYS) {
            if (lane[rk] === undefined) return { errors: [{ lane: lane.id, code: 'missing_key' }] };
          }
          // `kinds` is REQUIRED (above) and, when present, is always
          // already a valid array (rejected otherwise, just above) --
          // this normalizes only the one remaining shape: a lane that
          // never wrote `requester_logins` at all (an optional key).
          if (!Array.isArray(lane.requester_logins)) {
            lane.requester_logins = lane.requester_logins != null ? [lane.requester_logins] : [];
          }
          meta.laneSeen.push(seenLaneKeys);
          lanes.push(lane);
        }
        policy.lanes = lanes;
        continue;
      }
    }
  } catch {
    return { errors: [{ lane: '-', code: 'parse_error' }] };
  }
  if (policy.version == null) return { errors: [{ lane: '-', code: 'missing_key' }] };
  if (policy.version !== 1) return { errors: [{ lane: '-', code: 'parse_error' }] };

  // The round-trip check (see the comment above emitCanonical): re-emit the
  // policy just built in canonical form and require every line of it to
  // have a counterpart in origNorm -- the source's OWN lines, each already
  // normalized to the same canonical text a correctly-read line would
  // produce (see each origNorm.push above). The comparison is by MULTISET,
  // not position: P1 fixes the shape of each key's OWN line, never an
  // order lane/deploy/requires keys must appear in relative to each other,
  // so two lines trading places is not itself a defect. What the P1 closed
  // shape does rule out is a line with no canonical counterpart at all --
  // a dropped inline value on a block header (`deploy: {...}`, `lanes:
  // [...]`, a lane's `requires: {...}`) re-emits as the bare header line
  // and so never matches the source's own (longer) text for that line. That
  // surfaces here, generically, as `noncanonical`, named at the first
  // source line with no remaining match.
  const canon = emitCanonical(policy, meta);
  const remaining = new Map();
  for (const line of canon) remaining.set(line, (remaining.get(line) ?? 0) + 1);
  let badLineNo = null;
  for (const o of origNorm) {
    const have = remaining.get(o.text) ?? 0;
    if (have > 0) {
      remaining.set(o.text, have - 1);
    } else if (badLineNo === null) {
      badLineNo = o.lineNo;
    }
  }
  if (badLineNo === null) {
    let leftover = 0;
    for (const v of remaining.values()) leftover += v;
    if (leftover > 0) badLineNo = origNorm.length ? origNorm[origNorm.length - 1].lineNo : 0;
  }
  if (badLineNo !== null) {
    return { errors: [{ lane: '-', code: 'noncanonical', line: badLineNo }] };
  }
  return { policy };
}

function parseJsonl(text) {
  const out = [];
  for (const line of String(text || '').split('\n')) {
    const t = line.trim();
    if (!t) continue;
    try {
      out.push(JSON.parse(t));
    } catch {
      // malformed line — ignored, same as every other JSONL ledger reader
      // in this repo (append-event.mjs's own readers).
    }
  }
  return out;
}

// P2 decision binder. The mandated ambiguity check below (more than one hit)
// disambiguates the wave-2-roadmap shape (three hitl_decision records
// sharing one ts) — decision_match is part of the filter, not an
// afterthought. (The mandated line itself is not quoted literally in this
// comment: mutation-run.mjs's --sed applier is a non-global single
// replacement, and an earlier draft of this comment duplicated the exact
// source text, so the mutation landed on the COMMENT above instead of the
// real code below it and TEST-1517's record came back STAYED GREEN.)
function resolveDecision(lane, decisionsText) {
  const ref = String(lane.decision_ref || '');
  const atIdx = ref.indexOf('@');
  const refId = atIdx === -1 ? ref : ref.slice(0, atIdx);
  const ts = atIdx === -1 ? '' : ref.slice(atIdx + 1);
  const records = parseJsonl(decisionsText);
  const hits = records.filter((r) => r
    && r.type === 'hitl_decision'
    && r.ref_id === refId
    && r.ts === ts
    && typeof r.decision === 'string'
    && r.decision.includes(String(lane.decision_match || '')));
  if (hits.length === 0) return { code: 'decision_missing' };
  if (hits.length > 1) return { code: 'decision_ambiguous' };
  const rec = hits[0];
  if (rec.owner_signoff !== true) return { code: 'decision_unsigned' };
  if (rec.actor !== lane.signed_by) return { code: 'signer_mismatch' };
  return { ok: true, record: rec };
}

// computeImpliedReach(deploy) — P7. `merge_reaches` must equal what `deploy`
// implies: production when production_on_merge is true, otherwise preview
// when deploy.preview is not 'none', otherwise nothing.
function computeImpliedReach(deploy) {
  if (deploy && deploy.production_on_merge === true) return 'production';
  if (deploy && deploy.preview && deploy.preview !== 'none') return 'preview';
  return 'nothing';
}

// validatePolicy(policy, decisionsText) — P2 (decision binding), P7 (deploy
// consistency + public-effect opt-ins, Spec-AC-10/12) and the structural
// codes duplicate_lane/undefined_kind/requester_missing (Spec-AC-12) plus
// bad_marker/duplicate_marker (Spec-AC-13, MARKER_RE) and bad_ceremony
// (validation-round1 B2 — an explicitly-written max_ceremony outside 0-3).
// Every failing predicate pushes its own error — a lane can carry more than
// one error line, matching P10 ("one INVALID line per error").
// parse_error/unknown_key/empty_globs/duplicate_key/missing_key are caught
// earlier, in parsePolicy, before a `policy` object this function could run
// against even exists.
export function validatePolicy(policy, decisionsText) {
  const errors = [];
  const kindIds = new Set((policy.kinds || []).map((k) => k.id));
  const impliedReach = computeImpliedReach(policy.deploy);
  const seenLaneIds = new Set();
  const seenMarkers = new Set();

  for (const lane of policy.lanes || []) {
    const id = lane.id;

    if (seenLaneIds.has(id)) {
      errors.push({ lane: id, code: 'duplicate_lane' });
    } else {
      seenLaneIds.add(id);
    }

    for (const k of lane.kinds || []) {
      if (!kindIds.has(k)) errors.push({ lane: id, code: 'undefined_kind' });
    }

    if (!MARKER_RE.test(String(lane.marker || '')) || lane.marker === 'AAI_OPERATOR_MERGE') {
      errors.push({ lane: id, code: 'bad_marker' });
    } else if (seenMarkers.has(lane.marker)) {
      errors.push({ lane: id, code: 'duplicate_marker' });
    } else {
      seenMarkers.add(lane.marker);
    }

    if (lane.merge_reaches !== impliedReach) {
      errors.push({ lane: id, code: 'reaches_inconsistent' });
    }
    const needsOptIn = lane.merge_reaches === 'production'
      || (lane.merge_reaches === 'preview' && policy.deploy && policy.deploy.preview === 'public');
    if (needsOptIn && lane.allow_public_side_effect !== true) {
      errors.push({ lane: id, code: 'public_effect_not_opted_in' });
    }

    if (lane.merge_reaches !== 'nothing'
        && (!Array.isArray(lane.requester_logins) || lane.requester_logins.length === 0)) {
      errors.push({ lane: id, code: 'requester_missing' });
    }

    // validation-round1 B2 — `max_ceremony` is optional, but WHEN written it
    // must be one of the four real ceremony levels (canon 0-3); a stray
    // string or an out-of-range integer must never silently widen or narrow
    // what the lane covers.
    if (lane.max_ceremony !== undefined
        && !(Number.isInteger(lane.max_ceremony) && lane.max_ceremony >= 0 && lane.max_ceremony <= 3)) {
      errors.push({ lane: id, code: 'bad_ceremony' });
    }

    const res = resolveDecision(lane, decisionsText);
    if (!res.ok) errors.push({ lane: id, code: res.code });
  }
  return errors.length ? { errors } : { ok: true };
}

// readAtBase(root, oid, relPath) -> text | null. `git show <oid>:<relPath>`;
// null when the path is genuinely absent at that commit; throws a
// base_unavailable-coded error when the commit object itself cannot be
// resolved (P3, P6).
export function readAtBase(root, oid, relPath) {
  try {
    return execFileSync('git', ['show', oid + ':' + relPath], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (err) {
    const stderr = String((err && err.stderr) || '');
    if (/invalid object name|bad object|unknown revision|bad revision/i.test(stderr)) {
      const e = new Error('base_unavailable');
      e.code = 'base_unavailable';
      throw e;
    }
    return null; // path absent at this commit
  }
}

// ---------------------------------------------------------------------------
// P5 — glob classification.
// ---------------------------------------------------------------------------

const ESCAPE_RE = /[.+^${}()|[\]\\]/;

// globToRegExp(glob) — `*` within one segment (never `/`), `**` spans zero
// or more whole segments, `?` one non-`/` character, full anchored match
// (no implicit basename matching).
export function globToRegExp(glob) {
  let re = '';
  let i = 0;
  const s = String(glob);
  while (i < s.length) {
    if (s[i] === '*' && s[i + 1] === '*') {
      i += 2;
      if (s[i] === '/') {
        re += '(?:.*/)?';
        i += 1;
      } else {
        re += '.*';
      }
      continue;
    }
    if (s[i] === '*') {
      re += '[^/]*';
      i += 1;
      continue;
    }
    if (s[i] === '?') {
      re += '[^/]';
      i += 1;
      continue;
    }
    const c = s[i];
    re += ESCAPE_RE.test(c) ? '\\' + c : c;
    i += 1;
  }
  return new RegExp(`^${re}$`);
}

// classifyFiles(files, policy) — guard paths first, then architecture, then
// kinds (P5, Spec-AC-05). Returns { denyReason, path } on the first
// PR-level deny, or { kinds: Set<kindId> } naming every kind at least one
// changed file matched. Architecture always overrides a kind match on the
// same path (the `if (archHit) return` below runs before the kind lookup).
// The glob engine itself (globToRegExp, Spec-AC-06) is proven through the
// --classify authoring aid's 10-row glob table.
export function classifyFiles(files, policy) {
  for (const f of files) {
    if (GUARD_PATHS.includes(f)) return { denyReason: 'policy_touched', path: f };
  }
  const kinds = new Set();
  for (const f of files) {
    let archHit = false;
    for (const a of policy.architecture) {
      if ((a.globs || []).some((g) => globToRegExp(g).test(f))) { archHit = true; break; }
    }
    if (archHit) return { denyReason: 'architecture', path: f };
    let kindId = null;
    for (const k of policy.kinds || []) {
      if ((k.globs || []).some((g) => globToRegExp(g).test(f))) { kindId = k.id; break; }
    }
    if (kindId === null) return { denyReason: 'unclassified', path: f };
    kinds.add(kindId);
  }
  return { kinds };
}

// ---------------------------------------------------------------------------
// Requester approval and CI-green predicates (P6, P7/Spec-AC-08).
// ---------------------------------------------------------------------------

// requesterApproved(reviews, logins, headOid) — P6, Spec-AC-07. Only
// APPROVED, CHANGES_REQUESTED and DISMISSED reviews decide anything;
// COMMENTED never overrides. For each listed login, take that login's
// latest deciding review by submittedAt. Satisfied when at least one
// listed login's latest deciding review is APPROVED at headOid.
const DECIDING_REVIEW_STATES = new Set(['APPROVED', 'CHANGES_REQUESTED', 'DISMISSED']);

export function requesterApproved(reviews, logins, headOid) {
  const list = Array.isArray(reviews) ? reviews : [];
  const loginList = Array.isArray(logins) ? logins : [];
  for (const login of loginList) {
    let latest = null;
    for (const rev of list) {
      if (!rev || !rev.author || rev.author.login !== login) continue;
      if (!DECIDING_REVIEW_STATES.has(rev.state)) continue;
      if (!latest || String(rev.submittedAt || '') > String(latest.submittedAt || '')) latest = rev;
    }
    const r = latest;
    if (r && r.state === 'APPROVED' && r.commit && r.commit.oid === headOid) {
      return true;
    }
  }
  return false;
}

// ciGreen(rollup) — Spec-AC-08. `rollup` is the GitHub `statusCheckRollup`
// list: a mix of CheckRun (`status`/`conclusion`) and StatusContext
// (`state`) entries, told apart by which fields they carry (real API
// payloads also carry `__typename`; this evaluator never requires it, so a
// `{"state":"SUCCESS"}` fixture classifies the same as a full payload). A
// CheckRun counts only when COMPLETED with conclusion SUCCESS, NEUTRAL or
// SKIPPED; a StatusContext counts only when its state is SUCCESS. Every
// entry must count, and an empty rollup is never green (nothing to merge
// on is not the same claim as "all green").
function isCheckRunEntry(entry) {
  return Object.prototype.hasOwnProperty.call(entry, 'status')
    || Object.prototype.hasOwnProperty.call(entry, 'conclusion');
}

const CHECK_RUN_OK_CONCLUSIONS = new Set(['SUCCESS', 'NEUTRAL', 'SKIPPED']);

function checkRunGreen(entry) {
  return entry.status === 'COMPLETED' && CHECK_RUN_OK_CONCLUSIONS.has(entry.conclusion);
}

function statusContextGreen(entry) {
  return entry.state === 'SUCCESS';
}

export function ciGreen(rollup) {
  if (!Array.isArray(rollup)) return false;
  if (rollup.length === 0) return false;
  for (const entry of rollup) {
    if (!entry || typeof entry !== 'object') return false;
    const ok = isCheckRunEntry(entry) ? checkRunGreen(entry) : statusContextGreen(entry);
    if (!ok) return false;
  }
  return true;
}

// resolveCurrentFocusPaths(statePath) -> { specPath, primaryPath } —
// validation-round1 B1 (P8 "defaulting to STATE current_focus"). The SAME
// indentation-scoped current_focus block read as lane-gate.mjs's own
// resolveDefaultSpecFromState (agree with it: this repeats its exact
// mechanics rather than diverging) — but lane-gate.mjs never needs an
// intake default for its own purposes, so this also returns
// current_focus.primary_path, which SKILL_PR step 6's documented
// no-flags invocation needs for intake_type/ref (readIntakeMeta, below).
// Values are the raw frontmatter strings, resolved against `root` by the
// caller; `null` for a missing/unreadable STATE, a missing current_focus
// block, or a field whose value is the literal `null`.
function resolveCurrentFocusPaths(statePath) {
  const out = { specPath: null, primaryPath: null };
  if (!statePath || !existsSync(statePath)) return out;
  let text;
  try {
    text = readFileSync(statePath, 'utf8');
  } catch {
    return out;
  }
  let inFocus = false;
  for (const raw of text.split('\n')) {
    if (!raw.trim()) continue;
    const indent = raw.length - raw.trimStart().length;
    const line = raw.trim();
    if (indent === 0) {
      inFocus = /^current_focus\s*:/.test(line);
      continue;
    }
    if (!inFocus || indent !== 2) continue;
    const sm = line.match(/^spec_path\s*:\s*(\S+)/);
    if (sm && sm[1] !== 'null') out.specPath = sm[1];
    const pm = line.match(/^primary_path\s*:\s*(\S+)/);
    if (pm && pm[1] !== 'null') out.primaryPath = pm[1];
  }
  return out;
}

// readRideCeremony(root, specPath, intakePath) -> integer — P8, Spec-AC-11.
// An INDEPENDENT reader (never a call into lane-gate.mjs's own, unexported
// readCeremonyLevel) that must still AGREE with the ceremony_level value
// lane-gate.mjs itself prints for the same spec (TEST-1515, seam S2). A
// spec, when resolvable, always wins over the intake (same precedence as
// lane-gate.mjs). Canon: an absent `ceremony_level` field is implicit 2; a
// ride whose spec and intake cannot be resolved AT ALL counts as ceremony 3.
//
// validation-round1 NB-2 (S2 seam divergence): an EXPLICITLY given --spec
// that does not exist is a broken reference, never a spec-less ride —
// falling back to the intake there could silently downgrade a spec'd ride,
// the exact bot-review concern lane-gate.mjs's own readCeremonyLevel already
// disclaims. Fail closed (ceremony 3) instead of falling through to intake.
// A ceremony_level value that is PRESENT but not one of the four canonical
// digits ('0'..'3' — a quoted `"3"`, the word `three`, a trailing comment)
// also fails closed to 3, never the absent-field default of 2 — agreeing
// with lane-gate.mjs's own ok=false-on-anything-else contract rather than
// reading "present but garbage" as "absent".
export function readRideCeremony(root, specPath, intakePath) {
  const specAbs = specPath ? resolve(root, specPath) : null;
  if (specAbs && !existsSync(specAbs)) return 3;
  const candidates = [specAbs, intakePath ? resolve(root, intakePath) : null].filter(Boolean);
  const source = candidates.find((p) => existsSync(p));
  if (!source) return 3; // canon: a ride with no resolvable spec/intake is ceremony 3
  let body;
  try {
    body = readFileSync(source, 'utf8').replace(/\r\n?/g, '\n');
  } catch {
    return 3;
  }
  const fm = body.match(/^---\n([\s\S]*?)\n---/);
  const cl = fm ? fm[1].match(/^ceremony_level:\s*(\S+)\s*$/m) : null;
  if (!cl) return 2; // canon: absent ceremony_level is implicit 2
  if (!['0', '1', '2', '3'].includes(cl[1])) return 3; // NB-2: non-canonical value fails closed, agreeing with lane-gate
  return Number(cl[1]);
}

// runSweepCheck(root, pr, rideOpts) -> denyReason | null — Spec-AC-09. The
// sweep check is never re-derived here; it spawns the SAME lane-gate.mjs
// --sweep-check this repo's merge hook already calls (S1), forwarding the
// identical ride inputs (--spec/--intake/--state) this evaluator itself
// resolved, so the two never judge a different ride. Exit 5 is the ONLY
// deny signal that mode defines; any other nonzero exit is an adapter
// failure, not a verdict, and must fail the same way (deny), never silently
// allow a merge nothing actually swept.
const LANE_GATE_PATH = resolve(SELF_DIR, 'lane-gate.mjs');

export function runSweepCheck(root, pr, rideOpts) {
  const args = ['--sweep-check', '--pr', String(pr), '--repo-root', root];
  if (rideOpts && rideOpts.spec) args.push('--spec', rideOpts.spec);
  if (rideOpts && rideOpts.intake) args.push('--intake', rideOpts.intake);
  if (rideOpts && rideOpts.state) args.push('--state', rideOpts.state);
  let rc = 0;
  try {
    execFileSync(process.execPath, [LANE_GATE_PATH, ...args], {
      cwd: root, stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (err) {
    rc = (err && typeof err.status === 'number') ? err.status : 1;
  }
  if (rc === 5) return 'sweep_check_failed';
  return null;
}

// readIntakeMeta(root, intakePath) -> { type, ref } — P8, Spec-AC-15
// (intake_types / exclude_roadmap_capability). Reads the intake document's
// OWN frontmatter: `type:` (a bare word — change, issue, rfc, ... — the
// same vocabulary `requires.intake_types` lists) and `id:` (the ride's
// ref_id: the same value STATE `current_focus.ref_id` and decisions.jsonl
// `ref_id` already carry for this ride, per this repo's own intake/decision
// pair). Both null when no --intake was given, the path is absent or
// unreadable, or the file carries no frontmatter block — a requires check
// against a null value fails closed (never silently skipped).
function readIntakeMeta(root, intakePath) {
  if (!intakePath) return { type: null, ref: null };
  const p = resolve(root, intakePath);
  if (!existsSync(p)) return { type: null, ref: null };
  let body;
  try {
    body = readFileSync(p, 'utf8').replace(/\r\n?/g, '\n');
  } catch {
    return { type: null, ref: null };
  }
  const fm = body.match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return { type: null, ref: null };
  const typeM = fm[1].match(/^type\s*:\s*(\S+)\s*$/m);
  const idM = fm[1].match(/^id\s*:\s*(\S+)\s*$/m);
  return { type: typeM ? typeM[1] : null, ref: idM ? idM[1] : null };
}

// readRoadmapCapabilitiesAtBase(root, oid) -> Set<string> | null — P8, S4
// (exclude_roadmap_capability). docs/ai/roadmap.yaml is read from the BASE
// commit via readAtBase, same discipline as the policy and decisions.jsonl
// (never the working tree). The ONE roadmap parser (loadRoadmap,
// lib/roadmap-model.mjs — reused, not re-implemented) takes a file path, not
// text, so the base-commit text is handed to it through a scratch file,
// removed again straight after. `null` means "no usable roadmap at base"
// (absent, or carries a structural error) — exclude_roadmap_capability never
// denies on that absence, only on an actual capability match.
function readRoadmapCapabilitiesAtBase(root, oid) {
  let text;
  try {
    text = readAtBase(root, oid, 'docs/ai/roadmap.yaml');
  } catch {
    return null;
  }
  if (text == null) return null;
  let dir;
  try {
    dir = mkdtempSync(join(tmpdir(), 'aai-merge-policy-roadmap-'));
  } catch {
    return null;
  }
  try {
    const tmpPath = join(dir, 'roadmap.yaml');
    writeFileSync(tmpPath, text, 'utf8');
    const loaded = loadRoadmap(tmpPath);
    if (!loaded || loaded.error || !loaded.roadmap) return null;
    return new Set(loaded.roadmap.pairs.map((p) => p.capability));
  } catch {
    return null;
  } finally {
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best-effort scratch cleanup */ }
  }
}

// readStateStatus(statePath, blockName) -> string | null — P8, Spec-AC-15
// (validation_pass / review_pass). docs/ai/STATE.yaml is per-developer and
// gitignored — never tracked, so never read from the base commit (P3 names
// the policy and the ledgers, not this file); read straight from
// --state/the repo-root default instead. A top-level (column 0) block named
// `blockName` carries a 2-space `status:` scalar — the same indentation-
// scoped shape lane-gate.mjs's own readStrategy reads. Null for a missing
// file, a missing block, or a block with no `status:` line.
function readStateStatus(statePath, blockName) {
  if (!statePath || !existsSync(statePath)) return null;
  let text;
  try {
    text = readFileSync(statePath, 'utf8');
  } catch {
    return null;
  }
  let inBlock = false;
  const blockRe = new RegExp(`^${blockName}\\s*:`);
  for (const raw of text.split('\n')) {
    if (!raw.trim()) continue;
    const indent = raw.length - raw.trimStart().length;
    const line = raw.trim();
    if (indent === 0) {
      inBlock = blockRe.test(line);
      continue;
    }
    if (!inBlock) continue;
    const m = line.match(/^status\s*:\s*(\S+)/);
    if (indent === 2 && m) return m[1];
  }
  return null;
}

// evaluateLane(lane, ctx) — lane-level codes in P10 order. `kind_not_in_lane`
// (Spec-AC-05), `ceremony_exceeds` (Spec-AC-11) and `requester_approval_
// missing` (Spec-AC-07) were real from earlier batches. This batch (Spec-
// AC-15) adds the remaining `requires` keys: `intake_type`/
// `roadmap_capability` slot in between kind and ceremony, the rest
// (`validation_not_pass`/`review_not_pass`/`pr_body_missing`) after
// requester — the exact P10 lane-level-code order. A lane with no
// requester_logins skips the requester check (it is only "WHEN a lane lists
// requester_logins", Spec-AC-07); a lane with no `requires` block (or no
// individual key within it) skips that key's own check entirely — every
// `requires` key is optional, and an unmet NON-declared key never denies. A
// lane with no max_ceremony is capped at DEFAULT_MAX_CEREMONY (P7: ceremony
// 3 is covered only when `max_ceremony: 3` is written explicitly).
export function evaluateLane(lane, ctx) {
  const kinds = Array.isArray(lane.kinds) ? lane.kinds : [];
  if (!kinds.some((k) => ctx.kinds.has(k))) {
    return { ok: false, reason: 'kind_not_in_lane' };
  }
  const req = lane.requires || {};
  // R2-B2: a DECLARED intake_types condition denies when its value is not
  // the array parsePolicy guarantees for a valid policy — never skipped as
  // though the key were absent. parsePolicy now rejects a malformed/scalar
  // intake_types outright (parse_error), so this is defense in depth: it
  // keeps evaluateLane itself fail-closed even if some future caller ever
  // hands it a lane object that bypassed parsePolicy.
  if ('intake_types' in req) {
    if (!Array.isArray(req.intake_types) || !req.intake_types.includes(ctx.intakeType)) {
      return { ok: false, reason: 'intake_type' };
    }
  }
  if (req.exclude_roadmap_capability === true
      && ctx.roadmapCapabilities && ctx.roadmapCapabilities.has(ctx.rideRef)) {
    return { ok: false, reason: 'roadmap_capability' };
  }
  const maxCeremony = typeof lane.max_ceremony === 'number' ? lane.max_ceremony : DEFAULT_MAX_CEREMONY;
  if (ctx.ceremony > maxCeremony) {
    return { ok: false, reason: 'ceremony_exceeds' };
  }
  const logins = Array.isArray(lane.requester_logins) ? lane.requester_logins : [];
  if (logins.length > 0 && !requesterApproved(ctx.reviews, logins, ctx.headOid)) {
    return { ok: false, reason: 'requester_approval_missing' };
  }
  if (req.validation_pass === true && ctx.validationStatus !== 'pass') {
    return { ok: false, reason: 'validation_not_pass' };
  }
  if (req.review_pass === true && ctx.reviewStatus !== 'pass') {
    return { ok: false, reason: 'review_not_pass' };
  }
  const body = ctx.body || '';
  if (req.pr_body_contains && !body.includes(req.pr_body_contains)) {
    return { ok: false, reason: 'pr_body_missing' };
  }
  return { ok: true };
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const out = {
    mode: null, pr: null, path: null, repoRoot: null, filesFrom: null, debugInputs: false,
    spec: null, intake: null, state: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--check') out.mode = 'check';
    else if (a === '--validate') out.mode = 'validate';
    else if (a === '--classify') out.mode = 'classify';
    else if (a === '--pr') out.pr = argv[++i];
    else if (a === '--path') out.path = argv[++i];
    else if (a === '--repo-root') out.repoRoot = argv[++i];
    else if (a === '--files-from') out.filesFrom = argv[++i];
    else if (a === '--debug-inputs') out.debugInputs = true;
    else if (a === '--spec') out.spec = argv[++i];
    else if (a === '--intake') out.intake = argv[++i];
    else if (a === '--state') out.state = argv[++i];
  }
  return out;
}

function getPrJson(root, pr) {
  const fields = 'number,state,isDraft,baseRefName,baseRefOid,headRefOid,reviews,statusCheckRollup,body';
  const raw = execFileSync('gh', ['pr', 'view', String(pr), '--json', fields], {
    cwd: root, encoding: 'utf8',
  });
  return JSON.parse(raw);
}

function getChangedFiles(root, base, head) {
  const out = execFileSync('git', ['diff', '--name-only', '--no-renames', `${base}...${head}`], {
    cwd: root, encoding: 'utf8',
  });
  const files = out.split('\n').map((s) => s.trim()).filter(Boolean);
  return files.length ? files : ['-'];
}

// lineSuffix(e) — a `noncanonical` finding (parsePolicy's round-trip check)
// carries the first source line the two sides disagree on; every other
// code carries no `line`, so this is a no-op for them.
function lineSuffix(e) {
  return e.line !== undefined ? ` line=${e.line}` : '';
}

function printLaneErrors(errors) {
  for (const e of errors) console.log(`lane=${e.lane ?? '-'} reason=${e.code}${lineSuffix(e)}`);
}

function runCheck(opts) {
  const pr = Number(opts.pr);
  if (!Number.isInteger(pr) || pr <= 0) {
    process.stderr.write(`merge-policy: --check requires a positive integer --pr, got ${JSON.stringify(opts.pr)}\n`);
    exit(EXIT_USAGE);
  }
  const root = opts.repoRoot;

  let prJson;
  try {
    prJson = getPrJson(root, pr);
  } catch {
    console.log(`MERGE-POLICY denied pr=${pr} reason=api_unavailable`);
    exit(EXIT_DENIED);
  }

  const base = prJson.baseRefOid;
  const head = prJson.headRefOid;

  // GUARD_PATHS wins over EVERYTHING, including whether a policy exists at
  // all at the base (P4: "even when every other condition holds") — so the
  // changed-file diff and its guard check run before the no_policy decision.
  let files;
  try {
    files = getChangedFiles(root, base, head);
  } catch {
    console.log(`MERGE-POLICY denied pr=${pr} reason=base_unavailable`);
    exit(EXIT_DENIED);
  }
  const guardCheck = classifyFiles(files, { architecture: [], kinds: [] });
  if (guardCheck.denyReason === 'policy_touched') {
    console.log(`MERGE-POLICY denied pr=${pr} reason=policy_touched path=${guardCheck.path}`);
    exit(EXIT_DENIED);
  }

  let policyText;
  try {
    policyText = readAtBase(root, base, POLICY_PATH);
  } catch {
    console.log(`MERGE-POLICY denied pr=${pr} reason=base_unavailable`);
    exit(EXIT_DENIED);
  }
  if (policyText == null) {
    console.log(`MERGE-POLICY no_policy pr=${pr}`);
    exit(EXIT_NO_POLICY);
  }

  const parsed = parsePolicy(policyText);
  if (parsed.errors) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=policy_invalid`);
    printLaneErrors(parsed.errors);
    exit(EXIT_DENIED);
  }
  const policy = parsed.policy;

  let decisionsText;
  try {
    decisionsText = readAtBase(root, base, 'docs/ai/decisions.jsonl');
  } catch {
    console.log(`MERGE-POLICY denied pr=${pr} reason=base_unavailable`);
    exit(EXIT_DENIED);
  }

  const validation = validatePolicy(policy, decisionsText || '');
  if (validation.errors) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=policy_invalid`);
    printLaneErrors(validation.errors);
    exit(EXIT_DENIED);
  }

  if (prJson.state !== 'OPEN' || prJson.isDraft === true) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=pr_not_open`);
    exit(EXIT_DENIED);
  }

  const classification = classifyFiles(files, policy);
  if (classification.denyReason) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=${classification.denyReason} path=${classification.path}`);
    exit(EXIT_DENIED);
  }

  if (!ciGreen(prJson.statusCheckRollup)) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=ci_not_green`);
    exit(EXIT_DENIED);
  }

  // validation-round1 B1 (P8 "defaulting to STATE current_focus"): the
  // documented no-flags invocation (SKILL_PR step 6; the hook lane path with
  // no AAI_SWEEP_* in its environment) passes neither --spec nor --intake.
  // Resolve both from STATE current_focus THEN, same guard lane-gate.mjs's
  // own --sweep-check default uses (resolveDefaultSpecFromState) — an
  // explicitly-given flag always wins; the default only ever fires when
  // BOTH are absent, so it never second-guesses a caller who named one.
  const statePath = opts.state ? resolve(root, opts.state) : resolve(root, 'docs/ai/STATE.yaml');
  let rideSpec = opts.spec;
  let rideIntake = opts.intake;
  if (!rideSpec && !rideIntake) {
    const defaults = resolveCurrentFocusPaths(statePath);
    if (defaults.specPath) rideSpec = defaults.specPath;
    if (defaults.primaryPath) rideIntake = defaults.primaryPath;
  }

  const sweepDeny = runSweepCheck(root, pr, { spec: rideSpec, intake: rideIntake, state: opts.state });
  if (sweepDeny) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=${sweepDeny}`);
    exit(EXIT_DENIED);
  }

  const ceremony = readRideCeremony(root, rideSpec, rideIntake);
  const intakeMeta = readIntakeMeta(root, rideIntake);
  const roadmapCapabilities = readRoadmapCapabilitiesAtBase(root, base);
  const validationStatus = readStateStatus(statePath, 'last_validation');
  const reviewStatus = readStateStatus(statePath, 'code_review');

  if (opts.debugInputs) {
    console.log(`ceremony=${ceremony} intake_type=${intakeMeta.type ?? '-'} ref=${intakeMeta.ref ?? '-'}`);
  }

  const ctx = {
    kinds: classification.kinds, reviews: prJson.reviews, headOid: head,
    body: prJson.body || '', ceremony,
    intakeType: intakeMeta.type, rideRef: intakeMeta.ref,
    roadmapCapabilities, validationStatus, reviewStatus,
  };
  const laneLines = [];
  let allowedLane = null;
  for (const lane of policy.lanes) {
    const verdict = evaluateLane(lane, ctx);
    if (verdict.ok) { allowedLane = lane; break; }
    laneLines.push(`lane=${lane.id} reason=${verdict.reason}`);
  }

  if (!allowedLane) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=no_lane_matched`);
    for (const l of laneLines) console.log(l);
    exit(EXIT_DENIED);
  }

  console.log(`MERGE-POLICY allowed pr=${pr} lane=${allowedLane.id} marker=${allowedLane.marker} `
    + `decision_ref=${allowedLane.decision_ref} merge_reaches=${allowedLane.merge_reaches}`);
  exit(EXIT_ALLOWED);
}

function runValidate(opts) {
  const root = opts.repoRoot;
  const policyPath = opts.path ? resolve(opts.path) : resolve(root, POLICY_PATH);
  if (!existsSync(policyPath)) {
    exit(EXIT_NO_POLICY);
  }
  const text = readFileSync(policyPath, 'utf8');
  const parsed = parsePolicy(text);
  if (parsed.errors) {
    for (const e of parsed.errors) console.log(`INVALID lane=${e.lane ?? '-'} code=${e.code}${lineSuffix(e)}`);
    exit(1);
  }
  const decisionsPath = resolve(root, DECISIONS_PATH);
  const decisionsText = existsSync(decisionsPath) ? readFileSync(decisionsPath, 'utf8') : '';
  const validation = validatePolicy(parsed.policy, decisionsText);
  if (validation.errors) {
    for (const e of validation.errors) console.log(`INVALID lane=${e.lane ?? '-'} code=${e.code}${lineSuffix(e)}`);
    exit(1);
  }
  console.log(`VALID lanes=${parsed.policy.lanes.length}`);
  exit(EXIT_ALLOWED);
}

function runClassify(opts) {
  const root = opts.repoRoot;
  const policyPath = opts.path ? resolve(opts.path) : resolve(root, POLICY_PATH);
  if (!existsSync(policyPath)) {
    process.stderr.write(`merge-policy: --classify policy not found: ${policyPath}\n`);
    exit(EXIT_USAGE);
  }
  const parsed = parsePolicy(readFileSync(policyPath, 'utf8'));
  if (parsed.errors) {
    for (const e of parsed.errors) console.log(`INVALID lane=${e.lane ?? '-'} code=${e.code}${lineSuffix(e)}`);
    exit(1);
  }
  let listText;
  if (!opts.filesFrom) {
    process.stderr.write('merge-policy: --classify requires --files-from\n');
    exit(EXIT_USAGE);
  }
  listText = opts.filesFrom === '-' ? readFileSync(0, 'utf8') : readFileSync(opts.filesFrom, 'utf8');
  const files = listText.split('\n').map((s) => s.trim()).filter(Boolean);
  for (const f of files) {
    const single = classifyFiles([f], parsed.policy);
    const cls = single.denyReason ? single.denyReason : [...single.kinds][0];
    console.log(`${f} ${cls}`);
  }
  exit(EXIT_ALLOWED);
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  opts.repoRoot = resolve(opts.repoRoot || DEFAULT_REPO_ROOT);
  if (opts.mode === 'check') return runCheck(opts);
  if (opts.mode === 'validate') return runValidate(opts);
  if (opts.mode === 'classify') return runClassify(opts);
  process.stderr.write('merge-policy: one of --check --pr <n> | --validate | --classify is required\n');
  exit(EXIT_USAGE);
}

// Guard the CLI entry so this module can be `import()`ed for its exported
// functions/constants (TEST-1507's import-closure probe does exactly that)
// without the side effect of actually running main() and calling exit().
// realOrResolve (same shape as .aai/scripts/aai-doctor.mjs) resolves both
// sides through realpath, so invoking this script through a SYMLINKED
// checkout still runs main() instead of silently no-op'ing
// (tests/skills/test-aai-doctor.sh TEST-439).
function realOrResolve(p) {
  try { return realpathSync(p); } catch { return resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  runMain(() => main());
}
