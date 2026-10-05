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
//   --canonical [--path <file>] [--repo-root <dir>]
//     prints the P1 canonical text of a policy the parser can read (exit
//     0), so an owner can copy it over a noncanonical file; exit 1 on a
//     parse-time error, 4 when the file is absent.
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
// P1 textual canonical form (remediation round 5, owner decision
// 2026-10-04 after validation round 4 R4-B1).
//
// Four validation rounds each found one more way this hand parser could
// MISREAD a line and then allow (quoted booleans, malformed lists, inline
// values on block headers, a scalar key accepting a list). Round 4's
// round-trip check compared the parser's re-rendering of what it read with
// the parser's re-emission of the object it built — both sides came from
// the same parse, so a misreading re-rendered identically on both. This
// replaces it with a comparison against the RAW FILE TEXT:
//
//   valid  <=>  textualNormalize(raw) === canonicalText(parsePolicy(raw))
//
// line by line, in order. textualNormalize touches only the raw text and
// never a parsed value; canonicalText is one deterministic emitter from the
// parsed object. If the parser reads `marker: [X]` as X, it emits
// `marker: X`, which differs from the file's `marker: [X]`, and the policy
// is `noncanonical line=<n>` naming the first raw line that differs. Any
// misreading of any kind is a visible textual difference, by construction;
// no per-shape rule is needed to catch it.
//
// THE CANONICAL FORM (also printed by `merge-policy.mjs --canonical`):
//   * Key order is fixed: top level version, deploy, architecture, kinds,
//     lanes; deploy preview, production_on_merge; an architecture or kind
//     entry `- id:` then `globs:`; a lane `- id:` then decision_ref,
//     decision_match, signed_by, kinds, merge_reaches,
//     allow_public_side_effect, max_ceremony, marker, requester_logins,
//     requires; requires intake_types, exclude_roadmap_capability,
//     validation_pass, review_pass, pr_body_contains.
//   * Two-space indentation per level; `key: value` with exactly one space
//     after the colon; a block header is the bare `key:`.
//   * An optional key appears only when it was written. An empty block
//     (deploy, architecture, kinds, lanes, a lane's requires) is spelled by
//     OMITTING it: `lanes:` with no entries, `lanes: []`, `deploy: {}` and
//     `requires:` with no keys are all noncanonical.
//   * Booleans are bare `true` / `false`. Integers are bare decimal, no
//     sign padding or leading zeros.
//   * Strings — the ONE quoting rule: a string is written BARE when it
//     matches SAFE_BARE_RE (a letter or `_` first, then only letters,
//     digits and `_ . / @ : + -`, not ending in `:`) and is not a YAML
//     reserved word (true/false/yes/no/on/off/y/n/null, any case);
//     otherwise it is wrapped in double quotes, verbatim. Single quotes are
//     never canonical. A string containing `"`, `\` or a control character
//     has no canonical spelling and is parse_error.
//   * Every list (globs, kinds, requester_logins, intake_types) is ONE
//     flow list on the key's own line: `[a, b]` — items by the string rule
//     above, separated by `, `; the empty list is `[]`.
//   * No comments. Comments in the file are fine: textualNormalize strips
//     them before the comparison.
// ---------------------------------------------------------------------------

const SAFE_BARE_RE = /^[A-Za-z_][A-Za-z0-9_./@:+-]*$/;
const YAML_RESERVED_RE = /^(?:true|false|yes|no|on|off|y|n|null)$/i;
// eslint-disable-next-line no-control-regex
const NO_CANONICAL_SPELLING_RE = /["\\\u0000-\u001f\u007f]/;

// DECISION_REF_RE — validation-round6 NB-1: decision_ref is parse-rejected
// unless it matches the P2 `<ref_id>@<ISO8601Z>` shape exactly, with a
// SAFE_BARE ref_id that cannot itself contain `@` (so the string carries
// exactly one `@`, the P2 separator) and no whitespace or `=` anywhere.
// This is the root-cause fix: runCheck's printed line puts decision_ref's
// value verbatim right after `marker=` and before `merge_reaches=`
// (:1429-1430), so whatever shape this regex allows is also exactly what
// claude-hook-gate.sh's field-exact LANE_ALLOWED_ERE must be able to read
// unambiguously as that one field, never as data that could be misread as
// a later `marker=`/`decision_ref=` occurrence.
const DECISION_REF_RE = /^[A-Za-z_][A-Za-z0-9_./:+-]*@\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

// stripTrailingComment(line) — the ONE comment rule, shared by
// textualNormalize and the parser so the two can never disagree about
// where a value ends: a `#` starts a comment only when it is outside
// quotes AND preceded by an ASCII space or tab (validation-round4 NB-1:
// `/[ \t]/`, never JS `\s`, which also matches NBSP and U+FEFF — YAML
// itself only ever starts a comment after a space or a tab).
function stripTrailingComment(line) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === "'" && !inDouble) inSingle = !inSingle;
    else if (c === '"' && !inSingle) inDouble = !inDouble;
    else if (c === '#' && !inSingle && !inDouble && i > 0 && /[ \t]/.test(line[i - 1])) {
      return line.slice(0, i);
    }
  }
  return line;
}

// textualNormalizeLines(raw) -> [{ lineNo, text }]. RAW text only, never a
// parsed value: strip one leading BOM; CRLF -> LF; drop a full-line comment
// (first non-space/tab character `#`); drop a trailing comment (the rule
// above); strip trailing ASCII spaces/tabs; drop blank lines. Nothing else
// — no re-quoting, no reflowing, no indentation change. lineNo is the
// physical 1-based line in the raw file.
function textualNormalizeLines(raw) {
  let s = String(raw);
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
  const rawLines = s.replace(/\r\n/g, '\n').split('\n');
  const out = [];
  for (let idx = 0; idx < rawLines.length; idx += 1) {
    const line = rawLines[idx];
    if (/^[ \t]*#/.test(line)) continue;
    const text = stripTrailingComment(line).replace(/[ \t]+$/, '');
    if (text === '') continue;
    out.push({ lineNo: idx + 1, text });
  }
  return out;
}

export function textualNormalize(raw) {
  return textualNormalizeLines(raw).map((l) => l.text).join('\n');
}

function canonicalScalarText(v) {
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return String(v);
  const s = String(v);
  return SAFE_BARE_RE.test(s) && !s.endsWith(':') && !YAML_RESERVED_RE.test(s) ? s : `"${s}"`;
}

// The emitter is driven by each key's SCHEMA type, never by the runtime type
// of the value the parser happened to store: a list-typed key always emits a
// flow list and a scalar-typed key always emits a scalar. So a parser that
// stored the wrong TYPE for a key (round 4: `marker: [X]` kept as the list
// ["X"]) emits a spelling that differs from the file (`marker: "X"`), and
// the textual comparison catches it -- the emitter cannot echo a misreading
// back in the file's own shape.
const LIST_KEYS = new Set(['globs', 'kinds', 'requester_logins', 'intake_types']);

function emitLeaf(key, v) {
  if (LIST_KEYS.has(key)) return `[${(Array.isArray(v) ? v : [v]).map(canonicalScalarText).join(', ')}]`;
  if (typeof v === 'boolean' || typeof v === 'number' || typeof v === 'string') return canonicalScalarText(v);
  return `"${String(v)}"`;
}

// WRITTEN — which optional keys the source actually wrote. A parsed value
// alone cannot say (`deploy` and a lane's `requester_logins` are defaulted
// in), so the parser records it on the policy object itself,
// non-enumerably, and canonicalText reads it from there: canonicalText is a
// function of the parsed policy alone. A hand-built policy with no WRITTEN
// record emits every key it carries.
const WRITTEN = Symbol('merge-policy.written');

function lineOf(key, value, depth) {
  return `${'  '.repeat(depth)}${key}: ${emitLeaf(key, value)}`;
}

function canonicalLines(policy) {
  const w = policy[WRITTEN] || null;
  const has = (obj, k, set) => (set ? set.has(k) : Object.prototype.hasOwnProperty.call(obj, k)
    && obj[k] !== undefined);
  const out = [`version: ${emitLeaf('version', policy.version)}`];
  const deployKeys = DEPLOY_ORDER.filter((k) => has(policy.deploy || {}, k, w && w.deploy));
  if (deployKeys.length) {
    out.push('deploy:');
    for (const k of deployKeys) out.push(lineOf(k, policy.deploy[k], 1));
  }
  for (const topKey of ['architecture', 'kinds']) {
    const items = policy[topKey] || [];
    if (!items.length) continue;
    out.push(`${topKey}:`);
    for (const item of items) {
      out.push(`  - id: ${emitLeaf('id', item.id)}`);
      out.push(lineOf('globs', item.globs, 2));
    }
  }
  const lanes = policy.lanes || [];
  if (lanes.length) {
    out.push('lanes:');
    lanes.forEach((lane, idx) => {
      const seen = w ? w.lanes[idx] : null;
      out.push(`  - id: ${emitLeaf('id', lane.id)}`);
      for (const k of LANE_SCALAR_KEYS) {
        if (has(lane, k, seen)) out.push(lineOf(k, lane[k], 2));
      }
      const req = lane.requires || {};
      const reqKeys = REQUIRES_ORDER.filter((k) => Object.prototype.hasOwnProperty.call(req, k));
      if (reqKeys.length) {
        out.push('    requires:');
        for (const k of reqKeys) out.push(lineOf(k, req[k], 3));
      }
    });
  }
  return out;
}

// canonicalText(policy) -> string. The one deterministic emitter (see the
// CANONICAL FORM above); `--canonical` prints it followed by a newline.
export function canonicalText(policy) {
  return canonicalLines(policy).join('\n');
}

function tokenizeLines(text) {
  return textualNormalizeLines(text).map(({ lineNo, text: t }) => {
    const indent = t.length - t.replace(/^ */, '').length;
    return { indent, content: t.slice(indent), lineNo };
  });
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

// PARSE_FAIL — the sentinel every strict reader below returns for a value
// with no legal reading. Never a value a caller could store.
const PARSE_FAIL = Symbol('parse_fail');

// parseStrictScalar(raw) — a SCALAR-typed key (version, an id,
// deploy.preview, decision_ref, decision_match, signed_by, marker,
// max_ceremony, merge_reaches, requires.pr_body_contains). Defense in depth
// on top of the textual check (R4-B1a): a value starting with `[` or `{` is
// a collection where a scalar belongs — parse_error, never read as
// something else; and a string with no canonical spelling (a `"`, `\` or
// control character inside) is parse_error too.
function parseStrictScalar(raw) {
  const s = String(raw).trim();
  if (/^[[{]/.test(s)) return PARSE_FAIL;
  const v = parseScalar(s);
  if (typeof v === 'string' && NO_CANONICAL_SPELLING_RE.test(v)) return PARSE_FAIL;
  return v;
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
    let badQuote = false;
    if (tok !== '') {
      // A token is cleanly quoted only when its FIRST and LAST characters
      // are a matching quote pair AND nothing in between repeats that same
      // quote character — `"a"] ["b"` (a trailing bracket pair after the
      // list) starts and ends with `"` too, but its middle still carries
      // the stray `]`/`[`/`"` this check exists to catch.
      const q = (tok[0] === '"' || tok[0] === "'") ? tok[0] : '';
      const quoted = q !== '' && tok.length >= 2 && tok[tok.length - 1] === q
        && !tok.slice(1, -1).includes(q);
      if (!quoted && /['"[\]{}]/.test(tok)) badQuote = true;
    }
    const v = parseScalar(tok);
    // A string with no canonical spelling (a `"`, `\` or control character
    // inside) would let the canonical emitter echo a misread list back in
    // the file's own shape (`["a"] ["b"]` read as the one item `a"] ["b`
    // re-emits as `["a"] ["b"]`), so it is refused here too.
    const noSpelling = typeof v === 'string' && NO_CANONICAL_SPELLING_RE.test(v);
    if ([badQuote, noSpelling].some(Boolean)) return null;
    items.push(v);
  }
  return items;
}

// parseRequiredList(raw) -> array | null (invalid) — validation-round2 R2-B2.
// A list-typed policy key (`kinds`, `requester_logins`, `intake_types`) is
// closed-shape (P1): ONLY a well-formed `[...]` flow list, never a bare
// scalar read as a one-element list, a quoted string that merely LOOKS like
// a list (`"[change]"` is the STRING `[change]`, not a list), or an
// unclosed/malformed one. An empty item (`[alice,]`, `[,bob]`) is invalid
// too. An explicitly empty list (`[]`) parses to `[]` and fails closed at
// evaluation (an empty intake_types matches no ride).
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
// defines. Any OTHER value (`PUBLIC`, `publik`, a typo) is a `parse_error`.
const DEPLOY_PREVIEW_ENUM = new Set(['none', 'private', 'public']);
const MERGE_REACHES_ENUM = new Set(['nothing', 'preview', 'production']);

// validation-round1 B2 — boolean-typed keys get the STRICT parse
// (parseBooleanScalar below) instead of the generic parseScalar.
const BOOLEAN_REQUIRES_KEYS = new Set([
  'exclude_roadmap_capability', 'validation_pass', 'review_pass',
]);

// Spec-AC-15 — the full `requires` allowlist (P1): any key outside these
// five is `unknown_key`. Spec-AC-09's `ci`/`sweep_check` prohibition falls
// out of this allowlist for free — CI and the sweep check are mandatory and
// never configurable, so no key naming either one is ever legal here.
const ALLOWED_REQUIRES_KEYS = new Set([
  'intake_types', 'exclude_roadmap_capability', 'validation_pass',
  'review_pass', 'pr_body_contains',
]);

// Canonical emission order: each schema-fixed field order above, reused
// rather than restated so the two can never drift apart.
const DEPLOY_ORDER = [...DEPLOY_KEYS];
const REQUIRES_ORDER = [...ALLOWED_REQUIRES_KEYS];

// parseBooleanScalar(raw) -> true | false | undefined (invalid) —
// validation-round1 B2. Only the `true`/`false` token, bare or quoted
// (a quoted one then fails the textual canonical check: one spelling per
// type), never a case variant or a yes/no word.
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

// headerRest(rest, lines, i, childIndent) -> 'ok' | 'parse_error'. A
// block-introducing key (deploy, architecture, kinds, lanes, a lane's
// requires) carries its content ONLY on the indented lines that follow.
// Text after its own colon is never read, so any is parse_error — except
// an explicit empty collection (`[]` or `{}`), which parses as zero entries
// (and is then noncanonical: the canonical empty block is the omitted key)
// and therefore must have NO indented children under it (R4-B1b: `lanes:
// []` followed by a lane used to read the lane anyway).
function headerRest(rest, lines, i, childIndent) {
  if (rest === '') return 'ok';
  if (rest !== '[]' && rest !== '{}') return 'parse_error';
  if (i < lines.length && lines[i].indent >= childIndent) return 'parse_error';
  return 'ok';
}

// parsePolicyLoose(text) -> { policy } | { errors }. The closed-shape read
// alone, WITHOUT the textual canonical comparison — what `--canonical`
// prints from. Parse-time errors (parse_error, unknown_key, empty_globs,
// duplicate_key, missing_key) are detected here; the policy-wide codes are
// detected in validatePolicy.
function parsePolicyLoose(text) {
  const lines = tokenizeLines(String(text));
  const policy = {
    version: null,
    deploy: { preview: 'none', production_on_merge: false },
    architecture: [],
    kinds: [],
    lanes: [],
  };
  const written = { deploy: new Set(), lanes: [] };
  const fail = (lane, code) => ({ errors: [{ lane, code }] });
  let i = 0;
  const seenTop = new Set();
  while (i < lines.length) {
    const { indent, content } = lines[i];
    if (indent !== 0) return fail('-', 'parse_error');
    const kv = splitKV(content);
    if (!kv) return fail('-', 'parse_error');
    const { key, rest } = kv;
    if (!TOP_KEYS.has(key)) return fail('-', 'unknown_key');
    if (seenTop.has(key)) return fail('-', 'duplicate_key');
    seenTop.add(key);
    i += 1;

    if (key === 'version') {
      const v = parseStrictScalar(rest);
      if (v === PARSE_FAIL) return fail('-', 'parse_error');
      policy.version = v;
      continue;
    }

    if (headerRest(rest, lines, i, 1) !== 'ok') return fail('-', 'parse_error');

    if (key === 'deploy') {
      const block = {};
      while (i < lines.length && lines[i].indent === 2) {
        const kv2 = splitKV(lines[i].content);
        if (!kv2 || !DEPLOY_KEYS.has(kv2.key)) return fail('-', 'unknown_key');
        if (written.deploy.has(kv2.key)) return fail('-', 'duplicate_key');
        written.deploy.add(kv2.key);
        if (kv2.key === 'production_on_merge') {
          const b = parseBooleanScalar(kv2.rest);
          if (b === undefined) return fail('-', 'parse_error');
          block[kv2.key] = b;
        } else {
          const v = parseStrictScalar(kv2.rest);
          if (!DEPLOY_PREVIEW_ENUM.has(v)) return fail('-', 'parse_error');
          block[kv2.key] = v;
        }
        i += 1;
      }
      policy.deploy = {
        preview: block.preview ?? 'none',
        production_on_merge: block.production_on_merge ?? false,
      };
      continue;
    }

    if (key === 'architecture' || key === 'kinds') {
      const list = [];
      while (i < lines.length && lines[i].indent === 2 && lines[i].content.startsWith('- ')) {
        const kvId = splitKV(lines[i].content.slice(2).trim());
        if (!kvId || kvId.key !== 'id') return fail('-', 'parse_error');
        const id = parseStrictScalar(kvId.rest);
        if (id === PARSE_FAIL) return fail('-', 'parse_error');
        const item = { id, globs: [] };
        i += 1;
        let sawGlobs = false;
        while (i < lines.length && lines[i].indent === 4) {
          const kv3 = splitKV(lines[i].content);
          if (!kv3 || kv3.key !== 'globs') return fail(item.id, 'unknown_key');
          if (sawGlobs) return fail(item.id, 'duplicate_key');
          const g = parseFlowList(kv3.rest);
          if (g === null) return fail(item.id, 'parse_error');
          if (g.length === 0 || g.some((x) => x === '')) return fail(item.id, 'empty_globs');
          item.globs = g;
          sawGlobs = true;
          i += 1;
        }
        // P1 names `globs` on every architecture/kind entry; an entry that
        // never writes it is missing_key, never a silent `[]`.
        if (!sawGlobs) return fail(item.id, 'missing_key');
        list.push(item);
      }
      policy[key] = list;
      continue;
    }

    // key === 'lanes'
    const lanes = [];
    while (i < lines.length && lines[i].indent === 2 && lines[i].content.startsWith('- ')) {
      const kvId = splitKV(lines[i].content.slice(2).trim());
      if (!kvId || kvId.key !== 'id') return fail('-', 'parse_error');
      const laneId = parseStrictScalar(kvId.rest);
      if (laneId === PARSE_FAIL) return fail('-', 'parse_error');
      // NB1 (validation round 5): claude-hook-gate.sh's LANE_ALLOWED_ERE
      // extracts the marker from the evaluator's own printed
      // "lane=<id> marker=<marker> " text by scanning for the first
      // non-space run after `lane=` then a literal " marker=" — a quoted
      // lane id that embeds its OWN " marker=<other>" text would be read as
      // that fake field instead of the real one (a space is what lets
      // `[^[:space:]]+` stop early; `=` is the field separator it then
      // matches on). No lane id has legitimate business carrying either
      // character in a line a shell-side regex parses byte for byte.
      if (typeof laneId === 'string' && /[\s=]/.test(laneId)) return fail('-', 'parse_error');
      const lane = { id: laneId };
      i += 1;
      const seenLaneKeys = new Set();
      while (i < lines.length && lines[i].indent === 4) {
        const kv3 = splitKV(lines[i].content);
        if (!kv3) return fail(lane.id, 'parse_error');
        if (kv3.key === 'requires') {
          if (seenLaneKeys.has('requires')) return fail(lane.id, 'duplicate_key');
          seenLaneKeys.add('requires');
          i += 1;
          if (headerRest(kv3.rest, lines, i, 5) !== 'ok') return fail(lane.id, 'parse_error');
          const requires = {};
          while (i < lines.length && lines[i].indent === 6) {
            const kv4 = splitKV(lines[i].content);
            if (!kv4) return fail(lane.id, 'parse_error');
            if (!ALLOWED_REQUIRES_KEYS.has(kv4.key)) return fail(lane.id, 'unknown_key');
            if (Object.prototype.hasOwnProperty.call(requires, kv4.key)) return fail(lane.id, 'duplicate_key');
            if (BOOLEAN_REQUIRES_KEYS.has(kv4.key)) {
              const b = parseBooleanScalar(kv4.rest);
              if (b === undefined) return fail(lane.id, 'parse_error');
              requires[kv4.key] = b;
            } else if (kv4.key === 'intake_types') {
              // R2-B2: list-typed, closed shape.
              const list = parseRequiredList(kv4.rest);
              if (list === null) return fail(lane.id, 'parse_error');
              requires[kv4.key] = list;
            } else {
              // pr_body_contains: a non-empty, non-whitespace-only string
              // (an empty or all-whitespace needle matches — or near-always
              // matches — every real PR body, proving nothing — NB-4,
              // validation round 6, mirrors the N4 decision_match rule).
              const v = parseStrictScalar(kv4.rest);
              if (typeof v !== 'string' || v.trim() === '') return fail(lane.id, 'parse_error');
              requires[kv4.key] = v;
            }
            i += 1;
          }
          lane.requires = requires;
          continue;
        }
        if (!LANE_SCALAR_KEYS.includes(kv3.key)) return fail(lane.id, 'unknown_key');
        if (seenLaneKeys.has(kv3.key)) return fail(lane.id, 'duplicate_key');
        seenLaneKeys.add(kv3.key);
        if (kv3.key === 'merge_reaches') {
          const v = parseStrictScalar(kv3.rest);
          if (!MERGE_REACHES_ENUM.has(v)) return fail(lane.id, 'parse_error');
          lane[kv3.key] = v;
        } else if (kv3.key === 'allow_public_side_effect') {
          const b = parseBooleanScalar(kv3.rest);
          if (b === undefined) return fail(lane.id, 'parse_error');
          lane[kv3.key] = b;
        } else if (kv3.key === 'kinds' || kv3.key === 'requester_logins') {
          // R2-B2: list-typed, closed shape.
          const list = parseRequiredList(kv3.rest);
          if (list === null) return fail(lane.id, 'parse_error');
          lane[kv3.key] = list;
        } else if (kv3.key === 'decision_match') {
          // N4 (code review, HEAD f47f8861): mirrors the pr_body_contains
          // rule above — an empty needle ('' .includes('') === true)
          // matches every decision record's text at the bound ref@ts,
          // proving nothing about which decision authorizes this lane.
          // NB-4 (validation round 6): a whitespace-only needle is the
          // same shape — ' '.includes repeats against almost any real
          // decision text — so it is parse_error too, not merely a bare
          // empty string.
          const scalar = parseStrictScalar(kv3.rest);
          if (scalar === PARSE_FAIL) return fail(lane.id, 'parse_error');
          if (typeof scalar !== 'string' || scalar.trim() === '') return fail(lane.id, 'parse_error');
          lane[kv3.key] = scalar;
        } else if (kv3.key === 'decision_ref') {
          // NB-1 (validation round 6): decision_ref is parse-rejected
          // unless it matches the P2 `<ref_id>@<ISO8601Z>` shape with a
          // SAFE_BARE ref_id (DECISION_REF_RE above) — root-cause closure
          // for the hook-side marker-spoof vector, independent of how
          // strict the shell-side ERE is.
          const scalar = parseStrictScalar(kv3.rest);
          if (scalar === PARSE_FAIL) return fail(lane.id, 'parse_error');
          if (typeof scalar !== 'string' || !DECISION_REF_RE.test(scalar)) return fail(lane.id, 'parse_error');
          lane[kv3.key] = scalar;
        } else {
          // signed_by, max_ceremony, marker — scalar-typed: a `[`/`{`
          // value is parse_error (R4-B1a: `marker: [X]` used to be read as
          // the list ["X"], dodging duplicate_marker).
          const scalar = parseStrictScalar(kv3.rest);
          if (scalar === PARSE_FAIL) return fail(lane.id, 'parse_error');
          lane[kv3.key] = scalar;
        }
        i += 1;
      }
      for (const rk of REQUIRED_LANE_KEYS) {
        if (lane[rk] === undefined) return fail(lane.id, 'missing_key');
      }
      if (!Array.isArray(lane.requester_logins)) lane.requester_logins = [];
      written.lanes.push(seenLaneKeys);
      lanes.push(lane);
    }
    policy.lanes = lanes;
  }
  if (policy.version == null) return fail('-', 'missing_key');
  if (policy.version !== 1) return fail('-', 'parse_error');
  Object.defineProperty(policy, WRITTEN, { value: written, enumerable: false });
  return { policy, lines };
}

// canonicalFromText(text) -> { text } | { errors } — `--canonical`.
export function canonicalFromText(text) {
  const parsed = parsePolicyLoose(text);
  if (parsed.errors) return { errors: parsed.errors };
  return { text: canonicalText(parsed.policy) };
}

// parsePolicy(text) -> { policy } | { errors }. Closed shape (P1), then the
// textual canonical comparison (see the block comment at the top of this
// section): the raw file, normalized textually, must equal the canonical
// text emitted from what was parsed, line by line in order. The first line
// that differs is named: `noncanonical line=<n>` (n is the physical line in
// the raw file; one past the last line when the canonical text is longer).
export function parsePolicy(text) {
  let parsed;
  try {
    parsed = parsePolicyLoose(text);
  } catch {
    return { errors: [{ lane: '-', code: 'parse_error' }] };
  }
  if (parsed.errors) return parsed;
  const raw = textualNormalizeLines(text);
  const canon = canonicalLines(parsed.policy);
  const n = Math.max(raw.length, canon.length);
  for (let k = 0; k < n; k += 1) {
    if (k >= raw.length || k >= canon.length || raw[k].text !== canon[k]) {
      const lineNo = k < raw.length
        ? raw[k].lineNo
        : String(text).replace(/\r\n/g, '\n').split('\n').length + 1;
      return { errors: [{ lane: '-', code: 'noncanonical', line: lineNo }] };
    }
  }
  return { policy: parsed.policy };
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
// PR-level deny, or { kinds: Set<kindId>, fileKinds: Map<path, Set<kindId>> }
// on success: `kinds` names every kind at least one changed file matched
// (PR-level union, kept for callers that only need "did anything match
// kind X"); `fileKinds` names, per path, EVERY kind that path matches —
// code review B1 (round 7): a path can match more than one kind glob, and
// "a lane covers a path when at least one kind the path matches is listed
// in the lane's kinds" (P5) means evaluateLane needs the full per-path set,
// not just the first kind the old `break`-on-first-match loop happened to
// record. Architecture always overrides a kind match on the same path (the
// `if (archHit) return` below runs before the kind lookup). The glob engine
// itself (globToRegExp, Spec-AC-06) is proven through the --classify
// authoring aid's 10-row glob table.
export function classifyFiles(files, policy) {
  // N3 (code review, HEAD f47f8861): getChangedFiles's own zero-file
  // sentinel (an empty diff) is represented as the single path '-' — the
  // spec's Implementation plan names this "unclassified, path -" directly,
  // but '-' reads like any other path through the glob loop below and
  // matches this repo's own `**` kind. Caught before any glob match, same
  // as GUARD_PATHS above.
  if (files.length === 1 && files[0] === '-') return { denyReason: 'unclassified', path: '-' };
  for (const f of files) {
    if (GUARD_PATHS.includes(f)) return { denyReason: 'policy_touched', path: f };
  }
  const kinds = new Set();
  const fileKinds = new Map();
  for (const f of files) {
    let archHit = false;
    for (const a of policy.architecture) {
      if ((a.globs || []).some((g) => globToRegExp(g).test(f))) { archHit = true; break; }
    }
    if (archHit) return { denyReason: 'architecture', path: f };
    const matched = new Set();
    for (const k of policy.kinds || []) {
      if ((k.globs || []).some((g) => globToRegExp(g).test(f))) matched.add(k.id);
    }
    if (matched.size === 0) return { denyReason: 'unclassified', path: f };
    for (const k of matched) kinds.add(k);
    fileKinds.set(f, matched);
  }
  return { kinds, fileKinds };
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
// resolved, so the two never judge a different ride. Exit 5 is the
// documented deny signal; any other nonzero exit is an adapter failure, not
// a verdict, and must fail the same way (deny), never silently allow a
// merge nothing actually swept.
const LANE_GATE_PATH = resolve(SELF_DIR, 'lane-gate.mjs');

// sweepCheckAllowed(rc, stdout, pr) -> boolean — B1 (code review, HEAD
// f47f8861). lane-gate.mjs --sweep-check means "passed" ONLY when it exits
// 0 AND its first stdout line is the allowed verdict for THIS pr
// ("SWEEP-CHECK allowed pr=<n> ..."). lane-gate.mjs's own runMain onError
// handler also exits 0 on ANY internal crash (an unreadable EVENTS.jsonl,
// EISDIR, or anything else readPrSweepRecords/computeLaneVerdict throws),
// printing `LANE heavy reason=internal-error` instead — rc alone cannot
// tell that apart from a real pass, so the line itself is read too. Scanning
// only the FIRST line mirrors claude-hook-gate.sh's own `mp_line` handling
// of this evaluator's allowed line.
export function sweepCheckAllowed(rc, stdout, pr) {
  if (rc !== 0) return false;
  const firstLine = String(stdout || '').split('\n')[0] || '';
  // NB-4 (validation round 6): `pr=` must bind a WHOLE numeric token, not
  // merely a numeric prefix — the old `(?:[^0-9]|$)` tail let `pr=7x`
  // count for PR 7 (`x` is "not a digit", so the alternation was
  // satisfied without the match ever reaching a token boundary). Capture
  // the full digit run and compare it to `pr` as a string so `pr=70`
  // never counts for PR 7 either.
  const m = /^SWEEP-CHECK allowed pr=(\d+)(?:\s|$)/.exec(firstLine);
  return !!m && m[1] === String(pr);
}

export function runSweepCheck(root, pr, rideOpts) {
  const args = ['--sweep-check', '--pr', String(pr), '--repo-root', root];
  if (rideOpts && rideOpts.spec) args.push('--spec', rideOpts.spec);
  if (rideOpts && rideOpts.intake) args.push('--intake', rideOpts.intake);
  if (rideOpts && rideOpts.state) args.push('--state', rideOpts.state);
  let rc = 0;
  let stdout = '';
  try {
    stdout = execFileSync(process.execPath, [LANE_GATE_PATH, ...args], {
      cwd: root, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8',
    });
  } catch (err) {
    rc = (err && typeof err.status === 'number') ? err.status : 1;
    stdout = (err && typeof err.stdout === 'string') ? err.stdout : '';
  }
  return sweepCheckAllowed(rc, stdout, pr) ? null : 'sweep_check_failed';
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
// (absent, or carries a structural error) — N2 (code review, HEAD
// f47f8861): exclude_roadmap_capability now DENIES fail-closed
// (roadmap_unreadable) on that absence rather than silently skipping the
// condition, since an unreadable roadmap proves nothing about which
// capabilities it would have excluded.
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
//
// kind_not_in_lane (code review B1, round 7): P5 — "a lane covers a path
// when at least one kind the path matches is listed in the lane's kinds" —
// is a per-PATH rule, and the spec amendment folded into P5 makes the
// PR-level consequence explicit: a lane is eligible only when it covers
// EVERY changed path. Judging coverage over the PR's union of matched
// kinds (the old `kinds.some(...)` check below) let a single qualifying
// file drag an entire mixed PR through a narrow lane. ctx.fileKinds is
// classifyFiles's per-path kind-set map (insertion order == the diff's own
// file order), so this walks paths in that same deterministic order and
// denies on the FIRST uncovered one, naming it (P10's kind_not_in_lane line
// now carries `path=<p>`) so the denial is actionable without a re-run.
export function evaluateLane(lane, ctx) {
  const kinds = Array.isArray(lane.kinds) ? lane.kinds : [];
  const kindSet = new Set(kinds);
  for (const [path, matched] of ctx.fileKinds) {
    let covered = false;
    for (const k of matched) {
      if (kindSet.has(k)) { covered = true; break; }
    }
    if (!covered) return { ok: false, reason: 'kind_not_in_lane', path };
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
  if (req.exclude_roadmap_capability === true) {
    // N2 (code review, HEAD f47f8861): this key fails CLOSED like every
    // other `requires` predicate — an unresolvable input (the base roadmap
    // absent/structurally broken, giving `null`; or the ride's own intake
    // carrying no `id:`, giving a null rideRef) must deny, never be read as
    // "nothing to exclude". Only an actually-resolved, non-matching ride
    // reaches the capability-set check below.
    if (!ctx.roadmapCapabilities || !ctx.rideRef) {
      return { ok: false, reason: 'roadmap_unreadable' };
    }
    if (ctx.roadmapCapabilities.has(ctx.rideRef)) {
      return { ok: false, reason: 'roadmap_capability' };
    }
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
    else if (a === '--canonical') out.mode = 'canonical';
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

// getChangedFiles (code review B2, round 7): `-z` disables git's default
// `core.quotePath` C-style quoting/escaping of a path carrying a byte
// >= 0x80, a quote, a backslash, a tab or a newline, and NUL-terminates
// each entry instead of newline-separating them, so a literal newline
// INSIDE a path can never be misread as an entry separator. Without `-z`
// a non-ASCII or quote-bearing path comes back as the quoted/escaped
// STRING `".github/workflows/d\303\251ploy.yml"`, not the real repo-
// relative path — an anchored architecture glob then never matches it
// (misread-then-allow), while a catch-all `**` kind still does. No
// `.trim()` here on purpose: a real path may legitimately carry leading or
// trailing whitespace, and trimming it would be exactly the same
// real-bytes-corruption bug in a different shape.
function getChangedFiles(root, base, head) {
  const out = execFileSync('git', ['diff', '-z', '--name-only', '--no-renames', `${base}...${head}`], {
    cwd: root, encoding: 'utf8',
  });
  const files = out.split('\u0000').filter(Boolean);
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
  canonicalHint(errors);
}

// canonicalHint(errors) — a `noncanonical` finding points the owner at the
// one command that prints the form the file must take. stderr only, so the
// P10 stdout contract (one INVALID / lane line per error) is unchanged.
function canonicalHint(errors) {
  if (errors.some((e) => e.code === 'noncanonical')) {
    process.stderr.write('merge-policy: the policy file is not in canonical form (P1); '
      + 'print it with: node .aai/scripts/merge-policy.mjs --canonical\n');
  }
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
    fileKinds: classification.fileKinds, reviews: prJson.reviews, headOid: head,
    body: prJson.body || '', ceremony,
    intakeType: intakeMeta.type, rideRef: intakeMeta.ref,
    roadmapCapabilities, validationStatus, reviewStatus,
  };
  const laneLines = [];
  let allowedLane = null;
  for (const lane of policy.lanes) {
    const verdict = evaluateLane(lane, ctx);
    if (verdict.ok) { allowedLane = lane; break; }
    // P10 amendment (code review B1, round 7): the kind_not_in_lane line
    // carries the first changed path that lane does not cover, so the
    // denial names the specific gap without a re-run under --debug-inputs.
    const pathSuffix = verdict.path !== undefined ? ` path=${verdict.path}` : '';
    laneLines.push(`lane=${lane.id} reason=${verdict.reason}${pathSuffix}`);
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
    canonicalHint(parsed.errors);
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

function runCanonical(opts) {
  const policyPath = opts.path ? resolve(opts.path) : resolve(opts.repoRoot, POLICY_PATH);
  if (!existsSync(policyPath)) exit(EXIT_NO_POLICY);
  const res = canonicalFromText(readFileSync(policyPath, 'utf8'));
  if (res.errors) {
    for (const e of res.errors) console.log(`INVALID lane=${e.lane ?? '-'} code=${e.code}${lineSuffix(e)}`);
    exit(1);
  }
  process.stdout.write(`${res.text}\n`);
  exit(EXIT_ALLOWED);
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  opts.repoRoot = resolve(opts.repoRoot || DEFAULT_REPO_ROOT);
  if (opts.mode === 'check') return runCheck(opts);
  if (opts.mode === 'validate') return runValidate(opts);
  if (opts.mode === 'classify') return runClassify(opts);
  if (opts.mode === 'canonical') return runCanonical(opts);
  process.stderr.write('merge-policy: one of --check --pr <n> | --validate | --classify | --canonical is required\n');
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
