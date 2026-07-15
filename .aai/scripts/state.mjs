#!/usr/bin/env node
// state.mjs — transactional STATE.yaml CLI (CHANGE-0006 / SPEC-0012 G1).
//
// Every runtime-state mutation the role prompts need, as closed-set validated
// subcommands over a STRUCTURAL LINE-EDIT engine (D2): no YAML library — the
// target top-level block is located by its column-0 key (shared TOP_KEY_RE from
// lib/state-core.mjs) and ONLY the lines inside that block are edited; comments,
// key order, and every other line survive byte-identical by construction. The
// commented schema header can never be mistaken for a real field (column-0 match
// — mechanically closes the CHANGE-0005 timestamp-regex mishap class).
//
// Subcommands (D1):
//   set-focus --type <t> [--ref <ID> --path <p>] [--clear spec_path]
//                                       (--type none nulls ref/path/spec_path)
//   set-phase --ref <ID> --phase <p> [--status <s>] [--path <p>] [--spec-path <p>]
//   set-validation --status <s> [--ref <id>] [--model <id>] [--evidence <p>]...
//                  [--notes <text>]
//                  [--clear <f,f>]        (--clear alone allowed; no run_at_utc stamp)
//                  --model = the VALIDATOR's model id (CHANGE-0010 D2): when a
//                  verdict (pass|fail) is set it is compared against the last
//                  Implementation/TDD Implementation run's model_id for the ref
//                  (normalized: trim, lowercase, one trailing [..] suffix
//                  stripped). Same base id = independence violation: WARNING +
//                  write + exit 0 by default; with `independence: enforce` in
//                  <dirname(state)>/docs-audit.yaml: NO write + exit 1. Missing
//                  data (no --model, unresolvable ref, no implementer run)
//                  skips safely with a stderr info line and exit 0.
//   set-code-review [--status <s>] [--required <b>] [--scope <t>] [--base-ref <r>]
//                   [--head-ref <r>] [--report <p>]... [--notes <t>] [--clear <f,f>] (>=1 flag)
//   set-strategy --selected <s> [--source <p>] [--rationale <t>]
//   set-worktree [--recommendation <r>] [--user-decision <d>] [--base-ref <r>]
//                [--branch <b>] [--path <p>] [--inline-scope <t>] [--rationale <t>]
//                [--clear <f,f>] (>=1 flag)
//
// `--clear <field,field,...>` (SPEC-0014 F1): explicitly null stale fields via
// closed per-subcommand whitelists (see CLEAR_FIELDS) — scalars/free-text to
// `field: null`, lists to `field: []`. Verdict/status/policy fields are not
// clearable by construction (reset-block keeps guard ownership); an unknown
// field or a clear+set of the same field in one invocation exits 2 pre-write.
//   set-tdd-cycle --status <IDLE|RED|GREEN|REFACTOR_COMPLETE> [--test-id ...]
//                 [--spec-path ...] [--test-path ...] [--red ...] [--green ...] [--refactor ...]
//   set-human-input --required <true|false> [--question <t>] [--reason <t>]
//   append-run --ref <ID> --role <R> --model <id> --started <ISO-UTC>
//              [--note <t>] [--tokens-in N] [--tokens-out N] [--tdd-tests N]
//              (CHANGE-0010 D5: omitting --tokens-in/--tokens-out still exits 0
//              but prints ONE stderr WARNING after the successful write —
//              cost_usd can never be computed from null tokens at flush)
//   log-tick --tick N --role <t> --scope <ref> --started <ISO-UTC> [...]   (JSONL append; never touches STATE)
//   reset-block <last_validation|code_review> [--force]                    (D6 guards)
//
// Global flags: --state <path> (default docs/ai/STATE.yaml)
//               --ticks <path> (default docs/ai/LOOP_TICKS.jsonl)
//
// Exit codes (closed contract, mirrors append-event.mjs / check-state.mjs):
//   0 — success, incl. idempotent no-ops (resetting an already-not_run block)
//   1 — integrity refusal: STATE already corrupt (duplicate top-level key), the
//       mutation would create one, the target block header carries an inline
//       value the line engine cannot safely splice under, or the file changed
//       on disk between load and commit (concurrent modification — retry).
//       ALSO: policy refusal (CHANGE-0010 D2) — set-validation independence
//       violation under `independence: enforce` — no write performed.
//       Original file preserved byte-identical in every case.
//   2 — usage/validation error before any write (unknown subcommand, UNKNOWN
//       FLAG for the subcommand, invalid enum, unknown block, bad --ref shape,
//       missing flag, malformed or >300s-future timestamp, missing STATE file,
//       newline in a plain-scalar value).
//
// Atomic write (D3): duplicate-key scan on CURRENT file -> mutate in memory ->
// duplicate-key + inline-header-conflict scan on MUTATED content -> write
// <state>.tmp-<pid> in the SAME directory -> re-read the target and refuse if
// it no longer matches the content captured at load (optimistic concurrency
// recheck) -> fs.renameSync (the sole commit point). AAI_STATE_INJECT_CRASH=
// during-write|before-rename and AAI_STATE_INJECT_CONCURRENT=before-rename are
// test-only fault hooks (inert unless set).
//
// CONCURRENCY POSTURE (review-20260704T093742Z W4): the CLI assumes a
// SINGLE-WRITER discipline — coordination is prompt-level (the orchestrator is
// the sole STATE writer under parallel dispatch; .aai/SUBAGENT_PROTOCOL.md
// sole-writer rule; RFC-0004 docs-lock is the heavyweight coordination layer).
// It takes NO lock; instead of silently letting the last rename win, the
// pre-rename content recheck above turns a detected lost-update race into a
// loud exit-1 refusal ("concurrent modification detected — retry").
//
// Normalization rules (documented per D2): multi-line/free-text values are
// written as `>-` block scalars at the existing 2-space-step indentation; CRLF
// input is normalized to LF on read; a field named by the command is created at
// the end of its block when missing; fields the command does not name are left
// untouched; a user-supplied plain-scalar value that YAML could misparse
// (`: `, leading `#`/`[`/`{`/quote, trailing colon, ` #`, leading/trailing
// space) is written single-quoted with `''` escaping — already-safe values stay
// unquoted so diffs remain minimal. Every STATE-mutating subcommand bumps the
// REAL top-level `updated_at_utc:`; `log-tick` never touches STATE.

import fs from 'node:fs';
import path from 'node:path';
import { TOP_KEY_RE, BLOCK_SCALAR_REST_RE, duplicateKeys, inlineChildConflicts, splitLines, joinLines } from './lib/state-core.mjs';

// --- closed sets -------------------------------------------------------------

const FOCUS_TYPES = ['intake_change', 'intake_issue', 'intake_prd', 'intake_hotfix',
  'intake_research', 'intake_rfc', 'intake_release', 'technology_extraction', 'maintenance', 'none'];
const PHASES = ['planning', 'preparation', 'implementation', 'validation', 'code_review', 'remediation'];
const ITEM_STATUSES = ['planned', 'in_progress', 'blocked', 'done'];
const VALIDATION_STATUSES = ['pass', 'fail', 'not_run'];
const REVIEW_STATUSES = ['not_run', 'pass', 'fail', 'waived'];
const STRATEGIES = ['loop', 'tdd', 'hybrid', 'undecided'];
const RECOMMENDATIONS = ['not_needed', 'optional', 'recommended', 'required'];
const USER_DECISIONS = ['undecided', 'worktree', 'inline', 'waived'];
const TDD_STATUSES = ['IDLE', 'RED', 'GREEN', 'REFACTOR_COMPLETE'];
const ROLES = ['Planning', 'Implementation', 'TDD Implementation', 'Validation',
  'Code Review', 'Remediation', 'Orchestration', 'Metrics Flush'];
const BOOLS = ['true', 'false'];
const TICK_TYPES = ['tick', 'recovery'];
const MODES = ['single', 'parallel'];
const RESETTABLE_BLOCKS = ['last_validation', 'code_review'];

const REF_RE = /^[A-Z]+-\d+$/;
// CHANGE-0012 / spec-slug-refs-across-tooling D1: SLUG shape — aligned with the
// SPEC-0015 deriveSlug output (lowercase kebab, max 48 chars) plus an optional
// 4-char base36 collision suffix (53 total); min 3 as a typo guard. DISJOINT
// from REF_RE by construction (case), so no ref can match both.
const SLUG_RE = /^(?=[a-z0-9-]{3,53}$)[a-z0-9]+(?:-[a-z0-9]+)*$/;
// Review W1 (CHANGE-0012): bare YAML-1.1 boolean/null keywords that SLUG_RE
// would otherwise accept but YAML parsers silently re-type when unquoted.
const YAML_KEYWORD_SLUGS = new Set(['null', 'true', 'false', 'yes', 'off']);
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const FUTURE_SLACK_MS = 300 * 1000;

function fail(msg, code = 2) {
  console.error(`state: ${msg}`);
  process.exit(code);
}

function nowIso() {
  return new Date().toISOString().replace(/\.\d+Z$/, 'Z');
}

// --- argv --------------------------------------------------------------------

// `clear` accumulates like evidence/report (review-20260707T081303Z W1):
// last-wins would silently DROP a whole clear instruction, the exact silent-drop
// class the W5 strict-flag hardening exists to prevent.
const MULTI_FLAGS = new Set(['evidence', 'report', 'clear']);

function parseArgs(argv) {
  const pos = [];
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok.startsWith('--')) {
      const key = tok.slice(2).replace(/-/g, '_');
      let val = true;
      if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) val = argv[++i];
      if (MULTI_FLAGS.has(key)) {
        if (!Array.isArray(flags[key])) flags[key] = [];
        flags[key].push(val);
      } else {
        flags[key] = val;
      }
    } else {
      pos.push(tok);
    }
  }
  return { pos, flags };
}

// Strict per-subcommand flag sets (review-20260704T093742Z W5): a typoed flag
// (`--evidnce`) is the most likely LLM mistake — it must fail LOUD (exit 2)
// instead of silently dropping the data. Keys are underscore-normalized.
const GLOBAL_FLAGS = ['state', 'ticks'];
const CMD_FLAGS = {
  'set-focus': ['type', 'ref', 'path', 'spec_path', 'clear'],
  'set-phase': ['ref', 'phase', 'status', 'path', 'spec_path'],
  'set-validation': ['status', 'ref', 'model', 'evidence', 'notes', 'clear'],
  'set-code-review': ['status', 'required', 'scope', 'base_ref', 'head_ref', 'report', 'notes', 'clear'],
  'set-strategy': ['selected', 'source', 'rationale'],
  'set-worktree': ['recommendation', 'user_decision', 'base_ref', 'branch', 'path', 'inline_scope', 'rationale', 'clear'],
  'set-tdd-cycle': ['status', 'test_id', 'spec_path', 'test_path', 'red', 'green', 'refactor'],
  'set-human-input': ['required', 'question', 'reason'],
  'append-run': ['ref', 'role', 'model', 'started', 'note', 'tokens_in', 'tokens_out', 'tdd_tests'],
  'log-tick': ['tick', 'role', 'scope', 'started', 'type', 'exit_code', 'mode', 'k', 'harness',
    'tokens_in', 'tokens_out', 'cache_read', 'cost', 'lingering_procs', 'free_memory',
    'focus_before', 'validation_before'],
  'reset-block': ['force'],
};

function rejectUnknownFlags(cmd, flags) {
  const allowed = CMD_FLAGS[cmd];
  if (!allowed) return;   // unknown subcommand fails on its own, later
  const ok = new Set([...GLOBAL_FLAGS, ...allowed]);
  for (const k of Object.keys(flags)) {
    if (!ok.has(k)) {
      fail(`${cmd}: unknown flag --${k.replace(/_/g, '-')} `
        + `(valid: ${allowed.map(a => `--${a.replace(/_/g, '-')}`).join(' ')} | global: --state --ticks)`);
    }
  }
}

function strFlag(flags, name, cmd, { required = false } = {}) {
  const key = name.replace(/-/g, '_');
  const v = flags[key];
  if (v === undefined) {
    if (required) fail(`${cmd}: missing required --${name}`);
    return undefined;
  }
  if (v === true) fail(`${cmd}: --${name} requires a value`);
  return String(v);
}

function enumFlag(flags, name, allowed, cmd, { required = false } = {}) {
  const v = strFlag(flags, name, cmd, { required });
  if (v === undefined) return undefined;
  if (!allowed.includes(v)) fail(`${cmd}: invalid --${name} "${v}" (allowed: ${allowed.join(' | ')})`);
  return v;
}

function intFlag(flags, name, cmd, { required = false } = {}) {
  const v = strFlag(flags, name, cmd, { required });
  if (v === undefined) return undefined;
  if (!/^-?\d+$/.test(v)) fail(`${cmd}: --${name} must be an integer (got "${v}")`);
  return Number(v);
}

function numFlag(flags, name, cmd) {
  const v = strFlag(flags, name, cmd);
  if (v === undefined) return undefined;
  if (!/^-?\d+(\.\d+)?$/.test(v)) fail(`${cmd}: --${name} must be a number (got "${v}")`);
  return Number(v);
}

function refFlag(flags, name, cmd, { required = false } = {}) {
  const v = strFlag(flags, name, cmd, { required });
  if (v === undefined) return undefined;
  // CHANGE-0012 D1/D5: closed set of two disjoint shapes; anything else fails
  // closed (exit 2, pre-write) with a usage message naming BOTH shapes.
  if (!REF_RE.test(v) && !SLUG_RE.test(v)) {
    fail(`${cmd}: --${name} "${v}" matches neither the display shape ^[A-Z]+-\\d+$ `
      + 'nor the slug shape ^(?=[a-z0-9-]{3,53}$)[a-z0-9]+(?:-[a-z0-9]+)*$');
  }
  // Review W1 (CHANGE-0012): a bare YAML-keyword slug (null/true/false/yes/no/
  // on/off) would be written unquoted and silently re-typed by YAML parsers
  // (ref_id: null -> None). Fail closed instead; deriveSlug never NEEDS these
  // as full slugs and longer slugs containing them (e.g. null-handling) pass.
  if (YAML_KEYWORD_SLUGS.has(v)) {
    fail(`${cmd}: --${name} "${v}" is a bare YAML keyword and would be re-typed `
      + 'when the state file is parsed; use a longer slug');
  }
  return v;
}

function isoFlag(flags, name, cmd, { required = false } = {}) {
  const v = strFlag(flags, name, cmd, { required });
  if (v === undefined) return undefined;
  if (!ISO_RE.test(v) || Number.isNaN(Date.parse(v))) {
    fail(`${cmd}: --${name} "${v}" is not an ISO-8601 UTC timestamp (YYYY-MM-DDTHH:MM:SSZ)`);
  }
  if (Date.parse(v) - Date.now() > FUTURE_SLACK_MS) {
    fail(`${cmd}: --${name} "${v}" is more than 300s in the future vs the system clock`);
  }
  return v;
}

// --- load / atomic write (D3) ------------------------------------------------

function loadState(statePath) {
  if (!fs.existsSync(statePath)) fail(`STATE file not found: ${statePath}`);
  const raw = fs.readFileSync(statePath, 'utf8');   // exact bytes for the pre-rename concurrency recheck
  const { lines, trailingNewline } = splitLines(raw);
  const dups = duplicateKeys(lines);
  if (dups.length > 0) {
    fail(`refusing to edit ${statePath}: it ALREADY has duplicate top-level key(s) `
      + `[${dups.map(d => `${d.key} x${d.count}`).join(', ')}] — repair first with: `
      + `node .aai/scripts/check-state.mjs --repair ${statePath}`, 1);
  }
  return { lines, trailingNewline, raw, statePath };
}

function injectCrash(point) {
  if (process.env.AAI_STATE_INJECT_CRASH === point) {
    // Die UNCLEANLY at exactly this point (deterministic kill-mid-write tests).
    process.kill(process.pid, 'SIGKILL');
  }
}

function writeState(statePath, lines, trailingNewline, expectedRaw) {
  const dups = duplicateKeys(lines);
  if (dups.length > 0) {
    fail(`refusing to write ${statePath}: the mutation would create duplicate top-level key(s) `
      + `[${dups.map(d => d.key).join(', ')}] — original file preserved`, 1);
  }
  const conflicts = inlineChildConflicts(lines);
  if (conflicts.length > 0) {
    fail(`refusing to write ${statePath}: the mutation would splice child lines under an `
      + `inline-valued top-level header [${conflicts.map(c => c.key).join(', ')}] (invalid YAML) `
      + '— original file preserved', 1);
  }
  const content = joinLines(lines, trailingNewline);
  const tmp = `${statePath}.tmp-${process.pid}`;
  if (process.env.AAI_STATE_INJECT_CRASH === 'during-write') {
    // Simulate a crash mid-write: partial tmp content, then die. The TARGET is
    // untouched — rename below is the sole commit point.
    fs.writeFileSync(tmp, content.slice(0, Math.floor(content.length / 2)));
    process.kill(process.pid, 'SIGKILL');
  }
  fs.writeFileSync(tmp, content);
  injectCrash('before-rename');
  if (process.env.AAI_STATE_INJECT_CONCURRENT === 'before-rename') {
    // Test-only fault hook: simulate a SECOND writer committing between our
    // load and our rename (deterministic lost-update race).
    fs.appendFileSync(statePath, '# concurrent-writer marker (test injection)\n');
  }
  // Optimistic concurrency recheck (single-writer posture, W4): if the target
  // no longer matches the bytes captured at load, another writer committed in
  // between — renaming our stale copy over it would silently LOSE that write.
  if (expectedRaw !== undefined && fs.readFileSync(statePath, 'utf8') !== expectedRaw) {
    fs.rmSync(tmp, { force: true });
    fail(`concurrent modification detected: ${statePath} changed after it was read `
      + '— no write performed; re-run the command to retry on the fresh file', 1);
  }
  fs.renameSync(tmp, statePath);   // atomic on same-filesystem POSIX
}

function bumpUpdatedAt(lines) {
  const stamp = `updated_at_utc: ${nowIso()}`;
  for (let i = 0; i < lines.length; i += 1) {
    if (/^updated_at_utc:/.test(lines[i])) { lines[i] = stamp; return; }
  }
  lines.push(stamp);
}

// --- block engine (D2) ---------------------------------------------------------

function findBlock(lines, key) {
  for (let i = 0; i < lines.length; i += 1) {
    const m = lines[i].match(TOP_KEY_RE);
    if (!m || m[1] !== key) continue;
    let end = lines.length;
    for (let j = i + 1; j < lines.length; j += 1) {
      const l = lines[j];
      if (l.startsWith('#') || l.startsWith('---')) continue;
      if (TOP_KEY_RE.test(l)) { end = j; break; }
    }
    return { start: i, end };
  }
  return null;
}

// Ensure a top-level block exists; create it (header + defaultLines) before the
// real `updated_at_utc:` line (or at EOF) when missing.
function ensureBlock(lines, key, defaultLines = []) {
  let b = findBlock(lines, key);
  if (b) return b;
  let insertAt = lines.length;
  for (let i = 0; i < lines.length; i += 1) {
    if (/^updated_at_utc:/.test(lines[i])) { insertAt = i; break; }
  }
  lines.splice(insertAt, 0, `${key}:`, ...defaultLines, '');
  return findBlock(lines, key);
}

// Edit one top-level block in place: fn(blockLines) returns the new block lines.
// Refuses (exit 1) when the block header carries an inline value (`metrics: {}`,
// `metrics: null`, ...): splicing nested lines under it would write invalid YAML
// (mapping value given twice) — refuse rather than corrupt (D2 posture; review
// W2). `opts.allowInline` whitelists a header rest the caller converts itself
// (e.g. set-phase handles `active_work_items: []`).
function editBlock(lines, key, fn, defaultLines = [], opts = {}) {
  const b = ensureBlock(lines, key, defaultLines);
  const header = lines[b.start];
  const rest = header.slice(header.indexOf(':') + 1).trim();
  if (rest !== '' && !rest.startsWith('#') && !(opts.allowInline && opts.allowInline.test(rest))) {
    fail(`refusing to edit top-level block "${key}": its header carries an inline value `
      + `(\`${header.trim()}\`) that the line engine cannot safely splice nested lines under `
      + `— convert it to block form (bare \`${key}:\` header) by hand first; file preserved`, 1);
  }
  const blockLines = lines.slice(b.start, b.end);
  const next = fn(blockLines) ?? blockLines;
  lines.splice(b.start, b.end - b.start, ...next);
}

function indentOf(line) {
  const m = line.match(/^ */);
  return m ? m[0].length : 0;
}

// Number of lines the field starting at blockLines[idx] occupies (the field
// line plus any more-indented continuation lines: `>-` scalars, list items).
// Blank lines are legal INSIDE block scalars (YAML spec): a blank run belongs
// to the span only when a MORE-indented continuation follows it — stopping at
// the first blank orphaned post-blank paragraphs of hand-edited `>-` fields on
// clear/overwrite (review-20260707T081303Z W2). Otherwise the field ends there.
function fieldSpan(blockLines, idx, indent) {
  let n = 1;
  for (let j = idx + 1; j < blockLines.length; j += 1) {
    const l = blockLines[j];
    if (l.trim() === '') {
      let k = j;
      while (k < blockLines.length && blockLines[k].trim() === '') k += 1;
      if (k < blockLines.length && indentOf(blockLines[k]) > indent) {
        n = k - idx + 1;   // the blank run + its continuation join the span
        j = k;
        continue;
      }
      break;
    }
    if (indentOf(l) > indent) n += 1;
    else break;
  }
  return n;
}

function fieldRe(indent, name) {
  return new RegExp(`^ {${indent}}${name}:(\\s|$)`);
}

function scalarLine(indent, name, value) {
  return `${' '.repeat(indent)}${name}: ${value}`;
}

// A plain scalar YAML could misparse: `: ` / trailing `:` (second mapping
// value), ` #` (comment opener), leading indicator characters, or leading/
// trailing whitespace. Already-safe values (paths, refs, timestamps, enums)
// never match, so they stay unquoted and diffs stay minimal (review W3).
function needsQuoting(v) {
  if (v === '') return true;
  if (/^[\s#\[\]{}&*!|>%@`"',]/.test(v)) return true;   // leading indicator char
  if (/^[?:-](\s|$)/.test(v)) return true;              // `- x` / `? x` / `: x` / bare
  if (/:(\s|$)/.test(v)) return true;                   // `k: v` inside, or trailing colon
  if (/\s#/.test(v)) return true;                       // opens a comment mid-value
  if (/\s$/.test(v)) return true;                       // trailing whitespace
  return false;
}

// Quote a USER-SUPPLIED plain-scalar value when needed (single-quoted, `'`
// doubled). Newlines/control chars cannot live on a single plain-scalar line at
// all — reject exit 2 before any write (free-text belongs in `>-` fields).
function yq(value) {
  const s = String(value);
  if (/[\r\n\t\0]/.test(s)) {
    fail(`value ${JSON.stringify(s)} contains a newline/control character — not representable `
      + 'as a plain scalar field (use a free-text --notes/--rationale style field)');
  }
  return needsQuoting(s) ? `'${s.replace(/'/g, "''")}'` : s;
}

// Free-text values are always written as `>-` block scalars (D2 normalization).
function textFieldLines(indent, name, text) {
  const sp = ' '.repeat(indent);
  const out = [`${sp}${name}: >-`];
  const segs = String(text).split(/\r?\n/).map(s => s.trim()).filter(s => s !== '');
  if (segs.length === 0) return [scalarLine(indent, name, 'null')];
  for (const seg of segs) out.push(`${sp}  ${seg}`);
  return out;
}

function listFieldLines(indent, name, items) {
  if (!items || items.length === 0) return [scalarLine(indent, name, '[]')];
  const sp = ' '.repeat(indent);
  const out = [`${sp}${name}:`];
  for (const it of items) out.push(`${sp}  - ${yq(it)}`);
  return out;
}

// Replace (or create at end of block) the field `name` at `indent` inside a
// top-level block's lines. `newLines` is the full replacement line array.
function setField(blockLines, indent, name, newLines) {
  const re = fieldRe(indent, name);
  for (let i = 1; i < blockLines.length; i += 1) {
    if (re.test(blockLines[i])) {
      const n = fieldSpan(blockLines, i, indent);
      blockLines.splice(i, n, ...newLines);
      return blockLines;
    }
  }
  let at = blockLines.length;
  while (at > 1 && (blockLines[at - 1].trim() === '' || blockLines[at - 1].startsWith('#'))) at -= 1;
  blockLines.splice(at, 0, ...newLines);
  return blockLines;
}

// Null a field only when it already exists (used by set-human-input false).
function nullFieldIfPresent(blockLines, indent, name) {
  const re = fieldRe(indent, name);
  for (let i = 1; i < blockLines.length; i += 1) {
    if (re.test(blockLines[i])) {
      const n = fieldSpan(blockLines, i, indent);
      blockLines.splice(i, n, scalarLine(indent, name, 'null'));
      return blockLines;
    }
  }
  return blockLines;
}

// Append items to a list field; converts an inline `name: []` to block form;
// creates the field when missing.
function appendListItems(blockLines, indent, name, items) {
  const sp = ' '.repeat(indent);
  const itemLines = items.map(it => `${sp}  - ${yq(it)}`);
  const re = fieldRe(indent, name);
  for (let i = 1; i < blockLines.length; i += 1) {
    if (!re.test(blockLines[i])) continue;
    const rest = blockLines[i].slice(blockLines[i].indexOf(':') + 1).trim();
    if (rest === '[]' || rest === '') {
      const n = fieldSpan(blockLines, i, indent);
      const existing = rest === '' ? blockLines.slice(i + 1, i + n) : [];
      blockLines.splice(i, n, `${sp}${name}:`, ...existing, ...itemLines);
      return blockLines;
    }
    fail(`cannot append to non-empty inline list "${name}: ${rest}" — convert it to block form first`);
  }
  let at = blockLines.length;
  while (at > 1 && (blockLines[at - 1].trim() === '' || blockLines[at - 1].startsWith('#'))) at -= 1;
  blockLines.splice(at, 0, `${sp}${name}:`, ...itemLines);
  return blockLines;
}

// --- field clearing (SPEC-0014 F1 / D1-D2) ------------------------------------
//
// `--clear <field,field,...>` on set-worktree / set-code-review /
// set-validation / set-focus. Closed per-subcommand whitelists (field names as
// they appear in the YAML block, NOT flag names). Scalars/free-text clear to
// `field: null`, lists to `field: []`; a missing whitelisted field is created
// (setField's create-at-end normalization). Verdict/status/policy fields are
// excluded BY CONSTRUCTION — `status` refusals name reset-block (D6 guard
// ownership untouched). `flag` is the set-flag whose value would contradict
// clearing the same field in one invocation (exit 2 before any write).
const CLEAR_FIELDS = {
  'set-worktree': {
    branch: { kind: 'scalar', flag: 'branch' },
    path: { kind: 'scalar', flag: 'path' },
    base_ref: { kind: 'scalar', flag: 'base_ref' },
    inline_review_scope: { kind: 'scalar', flag: 'inline_scope' },
    rationale: { kind: 'scalar', flag: 'rationale' },
  },
  'set-code-review': {
    scope: { kind: 'scalar', flag: 'scope' },
    base_ref: { kind: 'scalar', flag: 'base_ref' },
    head_ref: { kind: 'scalar', flag: 'head_ref' },
    report_paths: { kind: 'list', flag: 'report' },
    notes: { kind: 'scalar', flag: 'notes' },
  },
  'set-validation': {
    ref_id: { kind: 'scalar', flag: 'ref' },
    evidence_paths: { kind: 'list', flag: 'evidence' },
    notes: { kind: 'scalar', flag: 'notes' },
  },
  'set-focus': {
    spec_path: { kind: 'scalar', flag: 'spec_path' },
  },
};

// Validate `--clear` for a subcommand: returns the (deduplicated) field list,
// or [] when the flag is absent. Every refusal exits 2 BEFORE any write.
function resolveClearList(cmd, flags) {
  if (flags.clear === undefined) return [];
  const spec = CLEAR_FIELDS[cmd];
  const valid = Object.keys(spec).join(' ');
  // `clear` is a MULTI_FLAG (W1): every occurrence accumulates; merge them into
  // one comma-list. Any valueless/blank occurrence is refused outright.
  const rawParts = Array.isArray(flags.clear) ? flags.clear : [flags.clear];
  if (rawParts.some(v => v === true || String(v).trim() === '')) {
    fail(`${cmd}: --clear requires a comma-separated field list (clearable: ${valid})`);
  }
  const fields = rawParts.join(',').split(',').map(s => s.trim()).filter(s => s !== '');
  if (fields.length === 0) {
    fail(`${cmd}: --clear requires a comma-separated field list (clearable: ${valid})`);
  }
  const seen = new Set();
  for (const f of fields) {
    // Own-property membership only (review-20260707T081303Z E1): plain spec[f]
    // let Object.prototype names (toString, __proto__, ...) pass the "closed"
    // whitelist and write junk keys into STATE with exit 0.
    const info = Object.hasOwn(spec, f) ? spec[f] : undefined;
    if (!info) {
      const hint = f === 'status' && (cmd === 'set-validation' || cmd === 'set-code-review')
        ? ' — a verdict status is guard-owned: use the sanctioned reset-block path instead'
        : '';
      fail(`${cmd}: --clear field "${f}" is not clearable (valid clearable set: ${valid})${hint}`);
    }
    if (flags[info.flag] !== undefined) {
      fail(`${cmd}: --clear ${f} contradicts --${info.flag.replace(/_/g, '-')} in the same invocation `
        + '— a field cannot be cleared and set at once');
    }
    seen.add(f);
  }
  return [...seen];
}

// Apply validated clears inside a block: scalar/free-text -> `field: null`,
// list -> `field: []`. Re-clearing an already-null/[] field is an idempotent
// field-level no-op (setField rewrites the identical line).
function applyClears(blockLines, cmd, fields) {
  const spec = CLEAR_FIELDS[cmd];
  for (const f of fields) {
    setField(blockLines, 2, f, [scalarLine(2, f, spec[f].kind === 'list' ? '[]' : 'null')]);
  }
  return blockLines;
}

// Read a direct scalar field value from a top-level block ('null' -> null).
function readScalar(lines, blockKey, field, indent = 2) {
  const b = findBlock(lines, blockKey);
  if (!b) return null;
  const re = fieldRe(indent, field);
  for (let i = b.start + 1; i < b.end; i += 1) {
    if (re.test(lines[i])) {
      const v = lines[i].slice(lines[i].indexOf(':') + 1).trim();
      return v === '' || v === 'null' ? null : v;
    }
  }
  return null;
}

// --- validator independence (CHANGE-0010 / spec-model-tiering-with-teeth D2/D3)

// Normalize a model id for the independence comparison: trim, lowercase, strip
// ONE trailing bracket suffix (`claude-opus-4-8[1m]` -> `claude-opus-4-8` — a
// context-window variant runs the same weights, hence the same blind spots).
// No family taxonomy: different weights are treated as independent by design.
function normalizeModelId(s) {
  return String(s).trim().toLowerCase().replace(/\[[^\]]*\]$/, '');
}

// Strip one layer of single/double quoting from a scalar read off a YAML line.
function unquoteScalar(v) {
  if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
    return v.slice(1, -1).replace(/''/g, "'");
  }
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) return v.slice(1, -1);
  return v;
}

// model_id of the LAST run whose role is Implementation or TDD Implementation
// under metrics.work_items[<ref>].agent_runs (same line engine, no YAML lib).
// Returns null when metrics/ref/agent_runs/implementer-run is missing — the
// caller treats null as "skip safely" (never block honest work).
function lastImplementerModel(lines, ref) {
  const b = findBlock(lines, 'metrics');
  if (!b) return null;
  // Locate the `    <ref>:` entry (exact string compare — ref may be an
  // arbitrary scalar read back from last_validation.ref_id, never regex it).
  let e0 = -1;
  for (let i = b.start + 1; i < b.end; i += 1) {
    if (lines[i].replace(/\s+$/, '') === `    ${ref}:`) { e0 = i; break; }
  }
  if (e0 === -1) return null;
  let e1 = b.end;
  for (let j = e0 + 1; j < b.end; j += 1) {
    const l = lines[j];
    if (l.trim() === '' || l.trim().startsWith('#')) continue;
    if (indentOf(l) < 6) { e1 = j; break; }   // next work_items key or dedent
  }
  // Locate agent_runs within the entry; inline `agent_runs: []` = no runs.
  let arIdx = -1;
  for (let i = e0 + 1; i < e1; i += 1) {
    if (/^ {6}agent_runs:\s*$/.test(lines[i])) { arIdx = i; break; }
    if (/^ {6}agent_runs:\s*\S/.test(lines[i])) return null;   // inline [] / scalar
  }
  if (arIdx === -1) return null;
  // Scan run items: `        - role: X` starts a run, `          model_id: Y`
  // belongs to the current run. Keep the last Implementation-role model.
  let currentRole = null;
  let lastImplModel = null;
  for (let i = arIdx + 1; i < e1; i += 1) {
    const l = lines[i];
    if (l.trim() === '') continue;
    if (indentOf(l) < 8) break;
    let m = l.match(/^ {8}- role:\s*(.*)$/);
    if (m) { currentRole = unquoteScalar(m[1].trim()); continue; }
    m = l.match(/^ {10}model_id:\s*(.*)$/);
    if (m && (currentRole === 'Implementation' || currentRole === 'TDD Implementation')) {
      const v = unquoteScalar(m[1].trim());
      if (v !== '' && v !== 'null') lastImplModel = v;
    }
  }
  return lastImplModel;
}

// Read the `independence:` guard dial from the committed guard-policy file
// sibling to the STATE file (D3: <dirname(statePath)>/docs-audit.yaml, the same
// column-0 line scan used on STATE). Default when the file, the key, or a
// valid value is absent: report-only (fail-open to warn — enforcement must not
// block single-model environments unless explicitly opted in).
function readIndependencePolicy(statePath) {
  const cfgPath = path.join(path.dirname(statePath), 'docs-audit.yaml');
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return { policy: 'report-only', cfgPath };
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^independence:\s*([^\s#]+)/);
    if (m) {
      // Review W1 (CHANGE-0010): a present-but-invalid value (e.g. "enforced",
      // quoted, capitalized) falls open to report-only per the SPEC — but say
      // so, or an operator who typoed the key believes enforcement is on.
      if (m[1] !== 'enforce' && m[1] !== 'report-only') {
        console.error(`state: WARNING independence value "${m[1]}" in ${cfgPath} is not `
          + '"enforce" or "report-only" — treating as report-only (fail-open default)');
      }
      return { policy: m[1] === 'enforce' ? 'enforce' : 'report-only', cfgPath };
    }
  }
  return { policy: 'report-only', cfgPath };
}

// --- subcommands ---------------------------------------------------------------

function cmdSetFocus(state, flags) {
  const clears = resolveClearList('set-focus', flags);
  // A pure `--clear` invocation needs no --type (SPEC-0014 D1); any set flag
  // re-engages the normal required-type contract.
  const clearOnly = clears.length > 0 && flags.type === undefined
    && flags.ref === undefined && flags.path === undefined && flags.spec_path === undefined;
  const type = clearOnly ? undefined : enumFlag(flags, 'type', FOCUS_TYPES, 'set-focus', { required: true });
  let ref = null;
  let p = null;
  if (type === 'none') {
    if (flags.ref !== undefined) ref = refFlag(flags, 'ref', 'set-focus');
    if (flags.path !== undefined) p = strFlag(flags, 'path', 'set-focus');
  } else if (type !== undefined) {
    ref = refFlag(flags, 'ref', 'set-focus', { required: true });
    p = strFlag(flags, 'path', 'set-focus', { required: true });
  }
  editBlock(state.lines, 'current_focus', bl => {
    applyClears(bl, 'set-focus', clears);
    if (type !== undefined) {
      setField(bl, 2, 'type', [scalarLine(2, 'type', type)]);
      setField(bl, 2, 'ref_id', [scalarLine(2, 'ref_id', ref ?? 'null')]);
      setField(bl, 2, 'primary_path', [scalarLine(2, 'primary_path', p === null ? 'null' : yq(p))]);
      if (flags.spec_path !== undefined) {
        setField(bl, 2, 'spec_path', [scalarLine(2, 'spec_path', yq(strFlag(flags, 'spec-path', 'set-focus')))]);
      } else if (type === 'none') {
        // SPEC-0014 D2 bonus normalization: `--type none` nulls spec_path when
        // present, exactly as it already nulls ref_id/primary_path.
        nullFieldIfPresent(bl, 2, 'spec_path');
      }
    }
    return bl;
  });
  return type !== undefined
    ? `set-focus: type=${type} ref=${ref ?? 'null'}`
    : `set-focus: cleared ${clears.join(',')}`;
}

function cmdSetPhase(state, flags) {
  const ref = refFlag(flags, 'ref', 'set-phase', { required: true });
  const phase = enumFlag(flags, 'phase', PHASES, 'set-phase', { required: true });
  const status = enumFlag(flags, 'status', ITEM_STATUSES, 'set-phase');
  const p = strFlag(flags, 'path', 'set-phase');
  const sp = strFlag(flags, 'spec-path', 'set-phase');

  // allowInline: the empty inline list is converted to block form right below.
  editBlock(state.lines, 'active_work_items', bl => {
    // Inline empty list -> block form.
    if (/^active_work_items:\s*\[\]\s*$/.test(bl[0])) bl[0] = 'active_work_items:';
    // Locate the item whose ref_id matches.
    let i0 = -1;
    let i1 = -1;
    for (let i = 1; i < bl.length; i += 1) {
      if (/^ {2}- /.test(bl[i])) {
        // item start; find its extent
        let end = bl.length;
        for (let j = i + 1; j < bl.length; j += 1) {
          if (/^ {2}- /.test(bl[j]) || (bl[j].trim() !== '' && indentOf(bl[j]) < 4)) { end = j; break; }
        }
        const item = bl.slice(i, end);
        if (item.some(l => new RegExp(`^( {2}- | {4})ref_id: ${ref}$`).test(l))) { i0 = i; i1 = end; break; }
        i = end - 1;
      }
    }
    // SPEC-0014 D3: the INSERTION point for a missing item field must stay
    // INSIDE the contiguous item lines — the run from `  - ref_id:` up to the
    // first blank line (the legacy extent i1 scans ACROSS blanks, which spliced
    // spec_path after the item's trailing blank — valid YAML, wrong placement).
    // i1 stays the SEARCH range so an existing field parked after a blank by
    // the pre-fix writer still updates in place instead of gaining a duplicate.
    let cEnd = i1;
    if (i0 !== -1) {
      for (let j = i0 + 1; j < i1; j += 1) {
        if (bl[j].trim() === '') { cEnd = j; break; }
      }
    }
    const setItemField = (name, value) => {
      for (let i = i0; i < i1; i += 1) {
        if (new RegExp(`^ {4}${name}:(\\s|$)`).test(bl[i]) || new RegExp(`^ {2}- ${name}:(\\s|$)`).test(bl[i])) {
          const prefix = bl[i].startsWith('  - ') ? '  - ' : '    ';
          bl[i] = `${prefix}${name}: ${value}`;
          return;
        }
      }
      // Missing: create inside the contiguous item lines — spec_path directly
      // after primary_path when that field exists; otherwise (and for every
      // other created field) at the end of the contiguous lines, never after
      // the blank (D3).
      let at = cEnd;
      if (name === 'spec_path') {
        for (let i = i0; i < cEnd; i += 1) {
          if (/^( {4}| {2}- )primary_path:(\s|$)/.test(bl[i])) { at = i + 1; break; }
        }
      }
      bl.splice(at, 0, `    ${name}: ${value}`);
      cEnd += 1;
      i1 += 1;
    };
    if (i0 === -1) {
      // Upsert: append a new item at the end of the block.
      let at = bl.length;
      while (at > 1 && (bl[at - 1].trim() === '' || bl[at - 1].startsWith('#'))) at -= 1;
      const item = [`  - ref_id: ${ref}`, `    status: ${status ?? 'in_progress'}`, `    phase: ${phase}`];
      if (p !== undefined) item.push(`    primary_path: ${yq(p)}`);
      if (sp !== undefined) item.push(`    spec_path: ${yq(sp)}`);
      bl.splice(at, 0, ...item);
    } else {
      setItemField('phase', phase);
      if (status !== undefined) setItemField('status', status);
      if (p !== undefined) setItemField('primary_path', yq(p));
      if (sp !== undefined) setItemField('spec_path', yq(sp));
    }
    return bl;
  }, [], { allowInline: /^\[\]$/ });
  return `set-phase: ${ref} phase=${phase}${status ? ` status=${status}` : ''}`;
}

function cmdSetValidation(state, flags) {
  const clears = resolveClearList('set-validation', flags);
  // `--clear` alone is a valid invocation (SPEC-0014 D1); --status stays
  // required otherwise. A clear-only call must NOT re-stamp run_at_utc — no
  // validation ran.
  const status = enumFlag(flags, 'status', VALIDATION_STATUSES, 'set-validation', { required: clears.length === 0 });
  const ref = strFlag(flags, 'ref', 'set-validation');
  const model = strFlag(flags, 'model', 'set-validation');
  const notes = strFlag(flags, 'notes', 'set-validation');
  const evidence = Array.isArray(flags.evidence) ? flags.evidence.map(String) : undefined;

  // Validator-independence check (CHANGE-0010 D2) — runs ONLY when a verdict
  // is being set (pass|fail); placed BEFORE editBlock so an enforce refusal
  // never touches the file. `--status not_run` and clear-only invocations
  // never trigger it. Skip paths never block honest work (info line, exit 0).
  if (status === 'pass' || status === 'fail') {
    const skip = reason => console.error(`state: set-validation: independence not checked: ${reason}`);
    if (model === undefined) {
      skip('--model not provided (pass the validator model id to enable the maker≠checker check)');
    } else {
      const checkRef = ref !== undefined ? ref : readScalar(state.lines, 'last_validation', 'ref_id');
      if (checkRef === null) {
        skip('no --ref given and last_validation.ref_id is null');
      } else {
        const impl = lastImplementerModel(state.lines, checkRef);
        if (impl === null) {
          skip(`no Implementation/TDD Implementation run with a model_id found under metrics.work_items[${checkRef}].agent_runs`);
        } else if (normalizeModelId(model) === normalizeModelId(impl)) {
          const { policy, cfgPath } = readIndependencePolicy(state.statePath);
          if (policy === 'enforce') {
            fail(`set-validation: REFUSED — independence violation: validator model "${model}" `
              + `equals implementer model "${impl}" for ${checkRef} (\`independence: enforce\` in ${cfgPath}); `
              + 'no write performed — set the verdict from a different model or dial the key to report-only', 1);
          }
          console.error(`state: set-validation: WARNING independence violation — validator model "${model}" `
            + `equals implementer model "${impl}" for ${checkRef}`);
        }
        // different normalized base ids: independent — silent pass.
      }
    }
  }

  editBlock(state.lines, 'last_validation', bl => {
    applyClears(bl, 'set-validation', clears);
    if (status !== undefined) {
      setField(bl, 2, 'status', [scalarLine(2, 'status', status)]);
      setField(bl, 2, 'run_at_utc', [scalarLine(2, 'run_at_utc', nowIso())]);   // self-stamped
    }
    if (ref !== undefined) setField(bl, 2, 'ref_id', [scalarLine(2, 'ref_id', yq(ref))]);
    if (evidence !== undefined) setField(bl, 2, 'evidence_paths', listFieldLines(2, 'evidence_paths', evidence));
    if (notes !== undefined) setField(bl, 2, 'notes', textFieldLines(2, 'notes', notes));
    return bl;
  });
  return status !== undefined
    ? `set-validation: status=${status} (run_at_utc self-stamped)`
    : `set-validation: cleared ${clears.join(',')}`;
}

function cmdSetCodeReview(state, flags) {
  const clears = resolveClearList('set-code-review', flags);
  const known = ['status', 'required', 'scope', 'base_ref', 'head_ref', 'report', 'notes'];
  if (clears.length === 0 && !known.some(k => flags[k] !== undefined)) {
    fail('set-code-review: at least one of --status/--required/--scope/--base-ref/--head-ref/--report/--notes/--clear is required');
  }
  const status = enumFlag(flags, 'status', REVIEW_STATUSES, 'set-code-review');
  const required = enumFlag(flags, 'required', BOOLS, 'set-code-review');
  const scope = strFlag(flags, 'scope', 'set-code-review');
  const baseRef = strFlag(flags, 'base-ref', 'set-code-review');
  const headRef = strFlag(flags, 'head-ref', 'set-code-review');
  const notes = strFlag(flags, 'notes', 'set-code-review');
  const reports = Array.isArray(flags.report) ? flags.report.map(String) : undefined;
  editBlock(state.lines, 'code_review', bl => {
    applyClears(bl, 'set-code-review', clears);
    if (required !== undefined) setField(bl, 2, 'required', [scalarLine(2, 'required', required)]);
    if (status !== undefined) setField(bl, 2, 'status', [scalarLine(2, 'status', status)]);
    if (scope !== undefined) setField(bl, 2, 'scope', textFieldLines(2, 'scope', scope));
    if (baseRef !== undefined) setField(bl, 2, 'base_ref', [scalarLine(2, 'base_ref', yq(baseRef))]);
    if (headRef !== undefined) setField(bl, 2, 'head_ref', [scalarLine(2, 'head_ref', yq(headRef))]);
    if (reports !== undefined) appendListItems(bl, 2, 'report_paths', reports);
    if (notes !== undefined) setField(bl, 2, 'notes', textFieldLines(2, 'notes', notes));
    return bl;
  });
  return 'set-code-review: applied';
}

function cmdSetStrategy(state, flags) {
  const selected = enumFlag(flags, 'selected', STRATEGIES, 'set-strategy', { required: true });
  const source = strFlag(flags, 'source', 'set-strategy');
  const rationale = strFlag(flags, 'rationale', 'set-strategy');
  editBlock(state.lines, 'implementation_strategy', bl => {
    setField(bl, 2, 'selected', [scalarLine(2, 'selected', selected)]);
    if (source !== undefined) setField(bl, 2, 'source', [scalarLine(2, 'source', yq(source))]);
    if (rationale !== undefined) setField(bl, 2, 'rationale', textFieldLines(2, 'rationale', rationale));
    return bl;
  });
  return `set-strategy: selected=${selected}`;
}

function cmdSetWorktree(state, flags) {
  const clears = resolveClearList('set-worktree', flags);
  const known = ['recommendation', 'user_decision', 'base_ref', 'branch', 'path', 'inline_scope', 'rationale'];
  if (clears.length === 0 && !known.some(k => flags[k] !== undefined)) {
    fail('set-worktree: at least one of --recommendation/--user-decision/--base-ref/--branch/--path/--inline-scope/--rationale/--clear is required');
  }
  const rec = enumFlag(flags, 'recommendation', RECOMMENDATIONS, 'set-worktree');
  const dec = enumFlag(flags, 'user-decision', USER_DECISIONS, 'set-worktree');
  const baseRef = strFlag(flags, 'base-ref', 'set-worktree');
  const branch = strFlag(flags, 'branch', 'set-worktree');
  const p = strFlag(flags, 'path', 'set-worktree');
  const inlineScope = strFlag(flags, 'inline-scope', 'set-worktree');
  const rationale = strFlag(flags, 'rationale', 'set-worktree');
  editBlock(state.lines, 'worktree', bl => {
    applyClears(bl, 'set-worktree', clears);
    if (rec !== undefined) setField(bl, 2, 'recommendation', [scalarLine(2, 'recommendation', rec)]);
    if (dec !== undefined) setField(bl, 2, 'user_decision', [scalarLine(2, 'user_decision', dec)]);
    if (baseRef !== undefined) setField(bl, 2, 'base_ref', [scalarLine(2, 'base_ref', yq(baseRef))]);
    if (branch !== undefined) setField(bl, 2, 'branch', [scalarLine(2, 'branch', yq(branch))]);
    if (p !== undefined) setField(bl, 2, 'path', [scalarLine(2, 'path', yq(p))]);
    if (inlineScope !== undefined) setField(bl, 2, 'inline_review_scope', textFieldLines(2, 'inline_review_scope', inlineScope));
    if (rationale !== undefined) setField(bl, 2, 'rationale', textFieldLines(2, 'rationale', rationale));
    return bl;
  });
  return 'set-worktree: applied';
}

function cmdSetTddCycle(state, flags) {
  const status = enumFlag(flags, 'status', TDD_STATUSES, 'set-tdd-cycle', { required: true });
  const testId = strFlag(flags, 'test-id', 'set-tdd-cycle');
  const specPath = strFlag(flags, 'spec-path', 'set-tdd-cycle');
  const testPath = strFlag(flags, 'test-path', 'set-tdd-cycle');
  const red = strFlag(flags, 'red', 'set-tdd-cycle');
  const green = strFlag(flags, 'green', 'set-tdd-cycle');
  const refactor = strFlag(flags, 'refactor', 'set-tdd-cycle');

  editBlock(state.lines, 'tdd_cycle', bl => {
    if (status === 'IDLE') {
      // IDLE names ALL fields (the SKILL_TDD cycle-clean shape).
      return ['tdd_cycle:',
        '  status: IDLE',
        '  test_id: null',
        '  spec_path: null',
        '  test_path: null',
        '  evidence:',
        '    red: null',
        '    green: null',
        '    refactor: null',
        ...bl.filter(l => l.trim() === '').slice(0, 1)];
    }
    setField(bl, 2, 'status', [scalarLine(2, 'status', status)]);
    if (testId !== undefined) setField(bl, 2, 'test_id', [scalarLine(2, 'test_id', yq(testId))]);
    if (specPath !== undefined) setField(bl, 2, 'spec_path', [scalarLine(2, 'spec_path', yq(specPath))]);
    if (testPath !== undefined) setField(bl, 2, 'test_path', [scalarLine(2, 'test_path', yq(testPath))]);
    if (red !== undefined || green !== undefined || refactor !== undefined) {
      // Ensure the nested `evidence:` map exists, then set its sub-fields.
      let evIdx = -1;
      for (let i = 1; i < bl.length; i += 1) {
        if (fieldRe(2, 'evidence').test(bl[i])) { evIdx = i; break; }
      }
      if (evIdx === -1) {
        let at = bl.length;
        while (at > 1 && (bl[at - 1].trim() === '' || bl[at - 1].startsWith('#'))) at -= 1;
        bl.splice(at, 0, '  evidence:');
        evIdx = at;
      }
      const evEnd = () => {
        let e = evIdx + 1;
        while (e < bl.length && bl[e].trim() !== '' && indentOf(bl[e]) >= 4) e += 1;
        return e;
      };
      const setEv = (name, value) => {
        if (value === undefined) return;
        const re = fieldRe(4, name);
        for (let i = evIdx + 1; i < evEnd(); i += 1) {
          if (re.test(bl[i])) { bl[i] = scalarLine(4, name, yq(value)); return; }
        }
        bl.splice(evEnd(), 0, scalarLine(4, name, yq(value)));
      };
      setEv('red', red);
      setEv('green', green);
      setEv('refactor', refactor);
    }
    return bl;
  });
  return `set-tdd-cycle: status=${status}`;
}

function cmdSetHumanInput(state, flags) {
  const required = enumFlag(flags, 'required', BOOLS, 'set-human-input', { required: true });
  const question = strFlag(flags, 'question', 'set-human-input');
  const reason = strFlag(flags, 'reason', 'set-human-input');
  editBlock(state.lines, 'human_input', bl => {
    setField(bl, 2, 'required', [scalarLine(2, 'required', required)]);
    if (question !== undefined) setField(bl, 2, 'question', textFieldLines(2, 'question', question));
    if (reason !== undefined) setField(bl, 2, 'blocking_reason', textFieldLines(2, 'blocking_reason', reason));
    if (required === 'false' && question === undefined && reason === undefined) {
      // Unblock: clear the stale question/reason (documented normalization).
      nullFieldIfPresent(bl, 2, 'question');
      nullFieldIfPresent(bl, 2, 'blocking_reason');
    }
    return bl;
  });
  return `set-human-input: required=${required}`;
}

function cmdAppendRun(state, flags) {
  const ref = refFlag(flags, 'ref', 'append-run', { required: true });
  const role = enumFlag(flags, 'role', ROLES, 'append-run', { required: true });
  const model = strFlag(flags, 'model', 'append-run', { required: true });
  const started = isoFlag(flags, 'started', 'append-run', { required: true });
  const note = strFlag(flags, 'note', 'append-run');
  const tokensIn = intFlag(flags, 'tokens-in', 'append-run');
  const tokensOut = intFlag(flags, 'tokens-out', 'append-run');
  const tddTests = intFlag(flags, 'tdd-tests', 'append-run');

  const ended = nowIso();   // SELF-STAMPED from the system clock
  const duration = Math.max(0, Math.round((Date.parse(ended) - Date.parse(started)) / 1000));

  const runLines = [`        - role: ${role}`, `          model_id: ${yq(model)}`];
  if (note !== undefined) {
    const segs = String(note).split(/\r?\n/).map(s => s.trim()).filter(s => s !== '');
    runLines.push('          note: >-');
    for (const seg of segs) runLines.push(`            ${seg}`);
  }
  runLines.push(
    `          started_utc: ${started}`,
    `          ended_utc: ${ended}`,
    `          duration_seconds: ${duration}`,
    `          tokens_in: ${tokensIn ?? 'null'}`,
    `          tokens_out: ${tokensOut ?? 'null'}`,
    '          cost_usd: null',
  );
  if (tddTests !== undefined) runLines.push(`          tdd_tests: ${tddTests}`);

  editBlock(state.lines, 'metrics', bl => {
    // Ensure `  work_items:` exists directly under metrics.
    let wiIdx = -1;
    for (let i = 1; i < bl.length; i += 1) {
      if (/^ {2}work_items:\s*$/.test(bl[i])) { wiIdx = i; break; }
      if (/^ {2}work_items:\s*\[\]\s*$/.test(bl[i])) { bl[i] = '  work_items:'; wiIdx = i; break; }
    }
    if (wiIdx === -1) { bl.splice(1, 0, '  work_items:'); wiIdx = 1; }

    // End of the meaningful block content (before trailing blank/comment lines).
    const blockEnd = () => {
      let at = bl.length;
      while (at > 1 && (bl[at - 1].trim() === '' || bl[at - 1].startsWith('#'))) at -= 1;
      return at;
    };

    // Locate the ref entry `    REF:`.
    let e0 = -1;
    let e1 = -1;
    for (let i = wiIdx + 1; i < bl.length; i += 1) {
      if (new RegExp(`^ {4}${ref}:\\s*$`).test(bl[i])) {
        e0 = i;
        e1 = blockEnd();
        for (let j = i + 1; j < bl.length; j += 1) {
          if (/^ {4}[\w-]+:\s*$/.test(bl[j]) || (bl[j].trim() !== '' && indentOf(bl[j]) < 4)) { e1 = Math.min(e1, j); break; }
        }
        break;
      }
    }
    if (e0 === -1) {
      // AUTO-INIT a missing metrics.work_items.<ref> entry (D1).
      const at = blockEnd();
      bl.splice(at, 0,
        `    ${ref}:`,
        '      human_time_minutes:',
        '        intake: null',
        '        reviews: null',
        '      agent_runs:',
        ...runLines);
      return bl;
    }

    // Locate agent_runs within the entry.
    let arIdx = -1;
    for (let i = e0 + 1; i < e1; i += 1) {
      if (/^ {6}agent_runs:\s*$/.test(bl[i])) { arIdx = i; break; }
      if (/^ {6}agent_runs:\s*\[\]\s*$/.test(bl[i])) {
        // Convert the inline auto-init form to block form WITHOUT duplicating
        // the nested key (ISSUE-0004 / Codex P2 shape).
        bl[i] = '      agent_runs:';
        arIdx = i;
        break;
      }
      if (/^ {6}agent_runs:\s*\S/.test(bl[i])) {
        fail(`append-run: unsupported non-empty inline agent_runs for ${ref} — convert to block form first`);
      }
    }
    if (arIdx === -1) {
      bl.splice(e1, 0, '      agent_runs:', ...runLines);
      return bl;
    }
    // Insert after the last line of the agent_runs field content.
    let ins = arIdx + 1;
    while (ins < e1 && bl[ins].trim() !== '' && indentOf(bl[ins]) >= 8) ins += 1;
    bl.splice(ins, 0, ...runLines);
    return bl;
  }, ['  work_items:']);
  // Token-capture teeth (CHANGE-0010 D5): warn — never block — when usage was
  // not recorded. Printed by main() AFTER the successful atomic write.
  if (tokensIn === undefined || tokensOut === undefined) {
    state.postWriteWarnings = [
      `state: append-run: WARNING tokens_in/tokens_out null for ${ref} role=${role} — cost_usd cannot `
      + 'be computed at flush; pass --tokens-in/--tokens-out when the platform exposes usage',
    ];
  }
  return `append-run: ${ref} role=${role} duration_seconds=${duration} (ended_utc self-stamped ${ended})`;
}

function cmdResetBlock(state, pos, flags, statePath) {
  const block = pos[1];
  if (!block) fail('reset-block: missing block name (last_validation | code_review)');
  if (!RESETTABLE_BLOCKS.includes(block)) {
    fail(`reset-block: unknown block "${block}" (allowed: ${RESETTABLE_BLOCKS.join(' | ')})`);
  }
  const b = findBlock(state.lines, block);
  if (!b) fail(`reset-block: STATE has no top-level "${block}" block`);
  const current = readScalar(state.lines, block, 'status');
  if (current === null) fail(`reset-block: "${block}" has no status field to reset`);
  if (current === 'not_run') {
    // Idempotent no-op: NO file write (D6).
    console.log(`state: reset-block ${block}: already not_run — no-op (file not rewritten)`);
    process.exit(0);
  }
  const force = flags.force === true;
  if ((current === 'pass' || current === 'waived') && !force) {
    fail(`reset-block: REFUSED — ${block}.status is "${current}" (not fail); a passing/waived verdict `
      + 'must not be clobbered by remediation. Use --force only with an explicit human decision.');
  }
  if (current !== 'fail' && !force && !['pass', 'waived'].includes(current)) {
    fail(`reset-block: unexpected ${block}.status "${current}" — repair STATE first`);
  }
  editBlock(state.lines, block, bl => {
    setField(bl, 2, 'status', [scalarLine(2, 'status', 'not_run')]);
    if (block === 'last_validation') {
      // Append the reset marker to notes; prior run_at_utc/evidence_paths stay
      // as audit history (D6).
      const marker = `reset by remediation ${nowIso()}; pending independent re-validation`;
      const re = fieldRe(2, 'notes');
      let idx = -1;
      for (let i = 1; i < bl.length; i += 1) {
        if (re.test(bl[i])) { idx = i; break; }
      }
      if (idx === -1) {
        setField(bl, 2, 'notes', textFieldLines(2, 'notes', marker));
      } else {
        const rest = bl[idx].slice(bl[idx].indexOf(':') + 1).trim();
        const n = fieldSpan(bl, idx, 2);
        if (BLOCK_SCALAR_REST_RE.test(rest)) {
          // ANY block-scalar header (`>-`, `|-`, `|+`, `>`, `|2`, ...): append
          // the marker INSIDE the scalar at the existing content indentation —
          // prior note lines are audit history and must survive (D6; review W1).
          const contentIndent = n > 1 ? indentOf(bl[idx + 1]) : 4;
          bl.splice(idx + n, 0, `${' '.repeat(contentIndent)}${marker}`);
        } else if (rest === 'null' || rest === '') {
          bl.splice(idx, n, ...textFieldLines(2, 'notes', marker));
        } else {
          bl.splice(idx, n, '  notes: >-', `    ${rest}`, `    ${marker}`);
        }
      }
    }
    return bl;
  });
  return `reset-block: ${block} ${current} -> not_run (${statePath})`;
}

function cmdLogTick(state, flags, ticksPath) {
  const tick = intFlag(flags, 'tick', 'log-tick', { required: true });
  const role = strFlag(flags, 'role', 'log-tick', { required: true });
  const scope = strFlag(flags, 'scope', 'log-tick', { required: true });
  const started = isoFlag(flags, 'started', 'log-tick', { required: true });
  const type = enumFlag(flags, 'type', TICK_TYPES, 'log-tick') ?? 'tick';
  const exitCode = intFlag(flags, 'exit-code', 'log-tick') ?? 0;
  const mode = enumFlag(flags, 'mode', MODES, 'log-tick');
  const k = intFlag(flags, 'k', 'log-tick');
  const harness = strFlag(flags, 'harness', 'log-tick');
  const tokensIn = intFlag(flags, 'tokens-in', 'log-tick');
  const tokensOut = intFlag(flags, 'tokens-out', 'log-tick');
  const cacheRead = intFlag(flags, 'cache-read', 'log-tick');
  const cost = numFlag(flags, 'cost', 'log-tick');
  const lingering = intFlag(flags, 'lingering-procs', 'log-tick');
  const freeMemory = strFlag(flags, 'free-memory', 'log-tick');

  // "after" values default to the CURRENT STATE.yaml values; "before" values are
  // supplied by the caller (default: same as after / unchanged) — D7.
  const focusNow = readScalar(state.lines, 'current_focus', 'ref_id');
  const validationNow = readScalar(state.lines, 'last_validation', 'status');
  const modeNow = mode ?? readScalar(state.lines, 'orchestration', 'mode') ?? 'single';
  const kNowRaw = k ?? readScalar(state.lines, 'orchestration', 'k');
  const kNow = kNowRaw === null || kNowRaw === undefined ? 1 : Number(kNowRaw) || 1;

  const ended = nowIso();   // SELF-STAMPED
  const duration = Math.max(0, Math.round((Date.parse(ended) - Date.parse(started)) / 1000));

  const entry = {
    type,
    tick,
    role,
    scope,
    started_utc: started,
    ended_utc: ended,
    duration_seconds: duration,
    exit_code: exitCode,
    focus_ref_id_before: strFlag(flags, 'focus-before', 'log-tick') ?? focusNow,
    focus_ref_id_after: focusNow,
    validation_status_before: strFlag(flags, 'validation-before', 'log-tick') ?? validationNow,
    validation_status_after: validationNow,
    orchestration_mode: modeNow,
    orchestration_k: kNow,
    harness_version: harness ?? 'unknown',
  };
  // Optional usage/leak fields ONLY when their flag was passed — the helper
  // never fabricates usage (D7).
  if (tokensIn !== undefined) entry.input_tokens = tokensIn;
  if (tokensOut !== undefined) entry.output_tokens = tokensOut;
  if (cacheRead !== undefined) entry.cache_read_tokens = cacheRead;
  if (cost !== undefined) entry.est_cost_usd = cost;
  if (lingering !== undefined) entry.lingering_procs = lingering;
  if (freeMemory !== undefined) entry.free_memory = freeMemory;

  fs.mkdirSync(path.dirname(ticksPath), { recursive: true });
  fs.appendFileSync(ticksPath, JSON.stringify(entry) + '\n');
  console.log(`state: log-tick appended to ${ticksPath}: ${JSON.stringify(entry)}`);
}

// --- main ----------------------------------------------------------------------

function main() {
  const { pos, flags } = parseArgs(process.argv.slice(2));
  const statePath = path.resolve(process.cwd(), typeof flags.state === 'string' ? flags.state : 'docs/ai/STATE.yaml');
  const ticksPath = path.resolve(process.cwd(), typeof flags.ticks === 'string' ? flags.ticks : 'docs/ai/LOOP_TICKS.jsonl');
  const cmd = pos[0];
  if (!cmd) fail('missing subcommand (set-focus | set-phase | set-validation | set-code-review | set-strategy | set-worktree | set-tdd-cycle | set-human-input | append-run | log-tick | reset-block)');
  rejectUnknownFlags(cmd, flags);   // typo-class flags fail LOUD before any read/write (W5)

  const MUTATORS = {
    'set-focus': cmdSetFocus,
    'set-phase': cmdSetPhase,
    'set-validation': cmdSetValidation,
    'set-code-review': cmdSetCodeReview,
    'set-strategy': cmdSetStrategy,
    'set-worktree': cmdSetWorktree,
    'set-tdd-cycle': cmdSetTddCycle,
    'set-human-input': cmdSetHumanInput,
    'append-run': cmdAppendRun,
  };

  if (cmd === 'log-tick') {
    // Reads STATE for defaults; never mutates it (no updated_at_utc bump).
    const state = loadStateReadOnly(statePath);
    cmdLogTick(state, flags, ticksPath);
    return;
  }

  if (cmd === 'reset-block') {
    const state = loadState(statePath);
    const msg = cmdResetBlock(state, pos, flags, statePath);
    bumpUpdatedAt(state.lines);
    writeState(statePath, state.lines, state.trailingNewline, state.raw);
    console.log(`state: ${msg}`);
    return;
  }

  const fn = MUTATORS[cmd];
  if (!fn) fail(`unknown subcommand "${cmd}"`);
  const state = loadState(statePath);
  const msg = fn(state, flags);
  bumpUpdatedAt(state.lines);
  writeState(statePath, state.lines, state.trailingNewline, state.raw);
  // Post-write warnings (CHANGE-0010 D5): only after the successful commit.
  for (const w of state.postWriteWarnings ?? []) console.error(w);
  console.log(`state: ${msg} -> ${statePath}`);
}

// log-tick tolerates a corrupt-but-readable STATE (it only reads defaults) but
// still requires the file to exist (D1: every command exits 2 on missing STATE).
function loadStateReadOnly(statePath) {
  if (!fs.existsSync(statePath)) fail(`STATE file not found: ${statePath}`);
  const { lines, trailingNewline } = splitLines(fs.readFileSync(statePath, 'utf8'));
  return { lines, trailingNewline };
}

main();
