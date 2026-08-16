#!/usr/bin/env node
// deslop-unrequested.mjs — class-4 "unrequested surface" detector
// (spec-deslop-scope-and-unrequested-engine). Companion engine for
// .aai/SKILL_DESLOP.prompt.md's class-4 row: a mechanical check for CLI
// flags and yaml config keys under .aai/ that no requirement document names.
//
// Usage:
//   node .aai/scripts/deslop-unrequested.mjs --diff [--base <ref>] [--json]
//   node .aai/scripts/deslop-unrequested.mjs --all [--json]
//
// Fails closed: invoked with neither --diff nor --all, or with both (an
// ambiguous scope), it performs NO scan — no git call, no file read, no
// candidate line — and exits 2 with a usage line. Node stdlib only
// (docs/TECHNOLOGY.md). Read-only: never writes any file. The only nonzero
// exit this script produces anywhere is 2, for a usage error.
//
// Two closed extractor kinds (pattern-based, not a parser — see the LIMITS
// block emitted with every report). Both are CONTRACT SURFACES: things a
// requirement is expected to name because a human types or sets them
// directly (a flag, a config key) — NOT internal helpers, which are absent
// from every spec BY DESIGN and whose absence therefore carries no signal
// (owner decision, docs/ai/decisions.jsonl hitl_decision
// deslop-scope-and-unrequested-engine, 2026-08-15T08:14:24Z — this record is
// the amendment authority for narrowing this list from the original five
// kinds; see the spec's Amendment note):
//   cli-flag    .aai/scripts/**/*.{mjs,sh,ps1}  every long-dash flag token
//   yaml-key    .aai/system/*.yaml              column-0 top-level keys
//
// cli-flag PRECISION (fu-deslop-cliflag-kind-precision): a raw
// `/--[a-z][a-z0-9-]*/` match is not automatically a flag this code OWNS.
// Three closed, syntactic (not per-flag) exclusions apply before a match
// becomes a candidate:
//   - Comment-only occurrence: a match whose position falls at or after the
//     start of a `//` (.mjs) or `#` (.sh/.ps1) comment on its own line is
//     never extracted — a flag mentioned only in prose (often another
//     tool's, or a misspelled non-flag) is not evidence this code
//     implements anything (round-5 validation V5-2). Quote-aware (a `#`/`//`
//     inside a string literal does not start a comment); single physical
//     line only, matching this tool's pattern-based-not-a-parser limit.
//   - CSS custom property: immediately followed by `:` (a `--name: value`
//     declaration) or immediately preceded by `var(` and followed by `)` (a
//     `var(--name)` usage). These are stylesheet tokens, not CLI surface.
//   - External-tool argument: a flag this code merely PASSES to a
//     subprocess it invokes (git, gh, or any other external binary) is not
//     a contract surface this code owns — see findExternalSpansMjs /
//     findExternalSpansShell below for the exact detection rules. The .mjs
//     arm also resolves ONE level of local array indirection (`const NAME =
//     [...]` passed by reference to the external call, e.g. `runGh(ghArgs,
//     ...)`) so a flag built into a variable before the call site is not
//     missed (round-5 validation V5-2).
// None of the three is a per-flag stoplist (D3 forbids a curated exemption
// list): all key off syntactic CONTEXT (comment/string position, punctuation,
// or which process a token is an argument to), so none needs updating as new
// flags are added.
//
// A symbol is SUPPRESSED (not reported) when its exact token appears as a
// whole word anywhere in the body text (frontmatter stripped) of the
// requirement corpus. Whole-word here means "not embedded in a longer
// [A-Za-z0-9_-] run" — dashes count as word characters so flag/function
// names with dashes match as a single unit.
//
// --diff corpus: docs/ai/STATE.yaml's current_focus.spec_path and
// primary_path (read-only, best-effort; STATE is gitignored and absent on a
// fresh CI checkout).
// --all corpus: docs/specs/**/*.md whose frontmatter type is spec and status
// is accepted, implementing or done.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const USAGE = 'Usage: deslop-unrequested.mjs --diff [--base <ref>] [--json] | --all [--json]';
const NOT_SCANNED_NOTE = 'NOTE: scanned surface is exactly .aai/scripts/**/*.{mjs,sh,ps1} and .aai/system/*.yaml — everything else (.aai/*.prompt.md, .aai/workflow/**, .aai/templates/**, .aai/system/*.md, tests/**, docs/**, agent wrapper trees, anything outside .aai/) is NOT scanned.';
const EXCLUDED_STATUSES = ['draft', 'proposed', 'rejected', 'superseded', 'deferred'];
const INCLUDED_STATUSES = new Set(['accepted', 'implementing', 'done']);

function usageExit() {
  console.error(USAGE);
  process.exit(2);
}

function parseArgs(argv) {
  const args = { diff: false, all: false, base: null, json: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--diff') { args.diff = true; continue; }
    if (tok === '--all') { args.all = true; continue; }
    if (tok === '--json') { args.json = true; continue; }
    if (tok === '--base') {
      const v = argv[i + 1];
      // A missing value and an option-shaped value (e.g. `--base --json`,
      // the next flag silently consumed as a ref) are the same usage error:
      // both leave --base without a real ref, so both fail closed here
      // rather than falling back to the working-tree diff with the
      // requested flag dropped.
      if (v === undefined || v.startsWith('--')) return null;
      args.base = v;
      i += 1;
      continue;
    }
    return null; // unknown flag
  }
  if (args.diff === args.all) return null; // neither, or both — ambiguous scope
  if (args.base !== null && !args.diff) return null; // --base only meaningful with --diff
  return args;
}

// ---------------------------------------------------------------------------
// File system helpers
// ---------------------------------------------------------------------------

function walk(dir) {
  let out = [];
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out = out.concat(walk(full));
    else out.push(full);
  }
  return out;
}

function readTextSafe(filePath) {
  try {
    return { ok: true, content: fs.readFileSync(filePath, 'utf8') };
  } catch {
    return { ok: false, content: null };
  }
}

function toPosix(p) {
  return p.split(path.sep).join('/');
}

// ---------------------------------------------------------------------------
// Frontmatter / YAML micro-parsing (no YAML library, Node stdlib only —
// mirrors the line-based technique state.mjs / docs-audit-core.mjs use).
// ---------------------------------------------------------------------------

function cleanYamlScalar(raw) {
  let s = raw.trim();
  if (s === '' || s === 'null' || s === '~') return null;
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
    s = s.slice(1, -1);
  }
  return s;
}

function parseFrontmatter(content) {
  if (!content.startsWith('---')) return null;
  const firstNl = content.indexOf('\n');
  if (firstNl === -1) return null;
  const closeIdx = content.indexOf('\n---', firstNl);
  if (closeIdx === -1) return null;
  const block = content.slice(firstNl + 1, closeIdx);
  const fm = {};
  for (const line of block.split('\n')) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/);
    if (m) fm[m[1]] = cleanYamlScalar(m[2]);
  }
  return fm;
}

function stripFrontmatter(content) {
  if (!content.startsWith('---')) return content;
  const firstNl = content.indexOf('\n');
  if (firstNl === -1) return content;
  const closeIdx = content.indexOf('\n---', firstNl);
  if (closeIdx === -1) return content;
  const afterClose = content.indexOf('\n', closeIdx + 1);
  return afterClose === -1 ? '' : content.slice(afterClose + 1);
}

// current_focus.spec_path / primary_path out of docs/ai/STATE.yaml, without a
// YAML library: find the `current_focus:` block (column-0 key, 2-space-
// indented children) and read the two scalar children we need.
function readCurrentFocusPaths(stateContent) {
  const blockMatch = stateContent.match(/^current_focus:\r?\n((?:[ \t].*\r?\n?)*)/m);
  if (!blockMatch) return null; // no recognizable current_focus block: unparseable
  const body = blockMatch[1];
  const specMatch = body.match(/^ {2}spec_path:\s*(.*)$/m);
  const primaryMatch = body.match(/^ {2}primary_path:\s*(.*)$/m);
  return {
    specPath: specMatch ? cleanYamlScalar(specMatch[1]) : null,
    primaryPath: primaryMatch ? cleanYamlScalar(primaryMatch[1]) : null,
  };
}

// ---------------------------------------------------------------------------
// Requirement corpus resolution (D2)
// ---------------------------------------------------------------------------

function resolveDiffCorpus() {
  const state = readTextSafe('docs/ai/STATE.yaml');
  if (!state.ok) {
    return { empty: true, reason: 'STATE.yaml absent', documents: [] };
  }
  const focus = readCurrentFocusPaths(state.content);
  if (!focus) {
    return { empty: true, reason: 'STATE.yaml present but unparseable (no current_focus block found)', documents: [] };
  }
  const candidatePaths = [...new Set([focus.specPath, focus.primaryPath].filter(Boolean))];
  if (candidatePaths.length === 0) {
    return { empty: true, reason: 'current_focus.spec_path and primary_path are both null', documents: [] };
  }
  // Mirror resolveAllCorpus's own named-degrade pattern (below): a path
  // STATE names but this process cannot read (stale, deleted, permission-
  // denied) must not be silently dropped at buildCorpusText time — that
  // made a corpus that failed to load look identical to a corpus that had
  // nothing to say, with no NOTE and `empty: false` still claimed.
  const documents = [];
  const unreadable = [];
  for (const p of candidatePaths) {
    if (readTextSafe(p).ok) documents.push(p); else unreadable.push(p);
  }
  if (documents.length === 0) {
    return {
      empty: true,
      reason: `requirement document(s) named by STATE.yaml unreadable: ${unreadable.join(', ')}`,
      documents: [],
    };
  }
  return { empty: false, documents, unreadable };
}

function resolveAllCorpus() {
  const files = walk('docs/specs').filter((f) => f.endsWith('.md'));
  const excluded = { draft: 0, proposed: 0, rejected: 0, superseded: 0, deferred: 0 };
  const documents = [];
  for (const f of files) {
    const read = readTextSafe(f);
    if (!read.ok) continue;
    const fm = parseFrontmatter(read.content);
    if (!fm || fm.type !== 'spec') continue;
    const status = fm.status;
    if (INCLUDED_STATUSES.has(status)) {
      documents.push(f);
    } else if (Object.prototype.hasOwnProperty.call(excluded, status)) {
      excluded[status] += 1;
    }
  }
  if (documents.length === 0) {
    return {
      empty: true,
      reason: 'no docs/specs/**/*.md with type: spec and status in accepted|implementing|done',
      documents: [],
      excluded,
    };
  }
  return { empty: false, documents, excluded };
}

function buildCorpusText(documents) {
  let combined = '';
  for (const doc of documents) {
    const read = readTextSafe(doc);
    if (!read.ok) continue;
    combined += `\n${stripFrontmatter(read.content)}`;
  }
  return combined;
}

// Whole-word match: the needle must not be embedded in a longer run of
// [A-Za-z0-9_-] characters on either side (dashes count as "word" here so
// flag/function names with dashes match as a single unit).
function wholeWordMatch(haystack, needle) {
  const esc = needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(?<![A-Za-z0-9_-])${esc}(?![A-Za-z0-9_-])`);
  return re.test(haystack);
}

// ---------------------------------------------------------------------------
// Extractors (D3) — each returns [{ line, symbol }], deduped to the first
// (smallest) line per symbol.
// ---------------------------------------------------------------------------

function dedupeFirstLine(items) {
  const bySymbol = new Map();
  for (const item of items) {
    const existing = bySymbol.get(item.symbol);
    if (!existing || item.line < existing.line) bySymbol.set(item.symbol, item);
  }
  return [...bySymbol.values()].sort((a, b) => a.line - b.line || a.symbol.localeCompare(b.symbol));
}

// --- cli-flag precision helpers (fu-deslop-cliflag-kind-precision) --------

// Comment-only occurrence (round-5 validation V5-2): the column at which a
// `//` (.mjs) or `#` (.sh/.ps1) comment starts on THIS physical line, quote-
// aware so a marker inside a string literal is not mistaken for one (e.g. a
// URL's `//` or a shell arg containing `#`). A match at or after this column
// is prose, never a candidate. Single physical line only — a `/* ... */`
// block comment spanning lines is out of scope, the same pattern-based-not-
// a-parser limit already disclosed for the rest of this file.
function commentStartIndex(line, marker) {
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quote) {
      if (c === '\\') { i += 1; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (marker === '#' && c === '#') return i;
    if (marker === '//' && c === '/' && line[i + 1] === '/') return i;
  }
  return line.length;
}

// CSS custom property: `--name: value` (declaration, immediately followed by
// a colon) or `var(--name)` (usage, immediately preceded by `var(` and
// followed by `)`). Neither is CLI surface.
function isCssCustomProperty(line, matchIndex, matchLen) {
  const after = line.slice(matchIndex + matchLen, matchIndex + matchLen + 1);
  if (after === ':') return true;
  const before = line.slice(Math.max(0, matchIndex - 4), matchIndex);
  return before === 'var(' && after === ')';
}

// A bracketed span (`(...)` or `[...]`), character-offset based so it
// survives multi-line content. Quote-aware (a bracket inside a string
// literal never perturbs the depth count).
function matchBracketSpan(content, openIdx, openCh, closeCh) {
  let depth = 1;
  let i = openIdx + 1;
  let quote = null;
  while (i < content.length && depth > 0) {
    const c = content[i];
    if (quote) {
      if (c === '\\') { i += 2; continue; }
      if (c === quote) quote = null;
    } else if (c === '"' || c === "'" || c === '`') {
      quote = c;
    } else if (c === openCh) {
      depth += 1;
    } else if (c === closeCh) {
      depth -= 1;
    }
    i += 1;
  }
  return i;
}

// A subprocess-invocation call's argument-list span. See matchBracketSpan.
function matchParenSpan(content, openIdx) {
  return matchBracketSpan(content, openIdx, '(', ')');
}

// One level of local array indirection (round-5 validation V5-2): an
// external call's real argument list is sometimes built a few lines earlier
// as `const NAME = [...]` and passed BY REFERENCE — either as the NAME-
// convention call's first argument (`runGh(ghArgs, ...)`) or as the SHAPE
// convention's SECOND argument (`execFileSync('gh', ghArgs)`, the command
// name is the first) — so the call's own paren span never contains the
// flags at all. Every top-level (not nested inside another call/array/
// object) argument that is a bare identifier is resolved exactly one level:
// the identifier's own array-literal span, plus any `NAME.push(...)` call
// sites, are external too. Left unresolved beyond that (e.g. the array is
// itself built from another variable) — the same conservative, keep-it-as-
// a-candidate default already used when a call's command word can't be
// resolved (firstArgCommandWord).
function splitTopLevelArgs(argsText) {
  const parts = [];
  let depth = 0;
  let quote = null;
  let cur = '';
  for (let i = 0; i < argsText.length; i++) {
    const c = argsText[i];
    if (quote) {
      cur += c;
      if (c === '\\') { i += 1; cur += argsText[i] || ''; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { quote = c; cur += c; continue; }
    if (c === '(' || c === '[' || c === '{') { depth += 1; cur += c; continue; }
    if (c === ')' || c === ']' || c === '}') { depth -= 1; cur += c; continue; }
    if (c === ',' && depth === 0) { parts.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim() !== '') parts.push(cur);
  return parts;
}

function bareIdentifierArgs(argsText) {
  return splitTopLevelArgs(argsText)
    .map((s) => s.trim())
    .filter((s) => /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(s));
}

function findLocalArraySpans(content, identName) {
  const spans = [];
  const declRe = new RegExp(`\\b(?:const|let|var)\\s+${identName}\\s*=\\s*\\[`, 'g');
  let m;
  while ((m = declRe.exec(content)) !== null) {
    const openIdx = m.index + m[0].length - 1;
    spans.push([openIdx, matchBracketSpan(content, openIdx, '[', ']')]);
  }
  const pushRe = new RegExp(`\\b${identName}\\.push\\s*\\(`, 'g');
  while ((m = pushRe.exec(content)) !== null) {
    const openIdx = m.index + m[0].length - 1;
    spans.push([openIdx, matchParenSpan(content, openIdx)]);
  }
  return spans;
}

// The first argument's resolved "command word", for calls of the shape
// `fn('cmd', [...])` or `fn(\`cmd ${x}\`, ...)` — the leading literal text up
// to the closing quote or the first `${` interpolation, first whitespace-
// separated word. Null when the first argument isn't a resolvable literal
// (e.g. an identifier or expression) — callers treat null as "cannot prove
// external", the conservative (keep-it) default.
function firstArgCommandWord(argsText) {
  const m = argsText.match(/^\s*(['"`])((?:\\.|(?!\1)[^\n])*?)(?:\1|\$\{)/);
  if (!m) return null;
  const word = m[2].trim().split(/\s+/)[0];
  return word || null;
}

// Locally-defined "cmd passthrough" wrappers: `function NAME(cmd, ...)`
// whose body invokes a child_process primitive as `spawnSync(cmd,` or
// `execFileSync(cmd,` — the command lives at the CALL SITE (`NAME('git',
// [...])`), not in the wrapper body, mirroring aai-doctor.mjs's `run`. This
// is a shape rule (parameter literally named `cmd`, fed straight into a
// primitive), not a per-file name list, so it generalizes to any file
// following the same idiom.
function findCmdPassthroughWrapperNames(content) {
  const names = new Set();
  const defRe = /function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(\s*cmd\s*,/g;
  let m;
  while ((m = defRe.exec(content)) !== null) {
    const bodyWindow = content.slice(m.index, m.index + 600);
    if (/\b(?:spawnSync|execFileSync)\(\s*cmd\s*,/.test(bodyWindow)) names.add(m[1]);
  }
  return names;
}

// External-tool-argument spans for .mjs files (fu-deslop-cliflag-kind-
// precision): a flag this code merely PASSES to a subprocess it invokes is
// not a contract surface this code owns (owner decision, decisions.jsonl
// 2026-08-15T08:14:24Z). Three closed, syntactic signals — none a per-flag
// list:
//   (A) NAME convention: a call literally named `git`, `tryGit` or `runGh`
//       — this repo's established local-wrapper naming convention for "shell
//       out to git/gh" (verified across 8 scripts) — is always external.
//   (B) SHAPE: a direct call to a child_process primitive (execFileSync,
//       spawnSync, spawn, execSync) whose first argument resolves to a
//       command word other than 'node' is external; 'node' (this runtime
//       re-invoking one of this repo's OWN other scripts) is internal.
//   (C) PASSTHROUGH: a call to a locally-defined cmd-passthrough wrapper
//       (see findCmdPassthroughWrapperNames) is resolved the same way as (B).
// An unresolved first argument (a variable, not a literal) is left
// unmarked — conservatively kept, never suppressed on a guess.
function findExternalSpansMjs(content) {
  const spans = [];
  const passthroughNames = findCmdPassthroughWrapperNames(content);
  const callRe = /\b([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/g;
  let m;
  while ((m = callRe.exec(content)) !== null) {
    const name = m[1];
    const openIdx = m.index + m[0].length - 1;
    const closeIdx = matchParenSpan(content, openIdx);
    if (closeIdx <= openIdx + 1) continue;
    const argsText = content.slice(openIdx + 1, closeIdx - 1);
    let external = false;
    if (name === 'git' || name === 'tryGit' || name === 'runGh') {
      external = true; // (A)
    } else if (name === 'execFileSync' || name === 'spawnSync' || name === 'spawn' || name === 'execSync' || passthroughNames.has(name)) {
      const cmdWord = firstArgCommandWord(argsText);
      external = cmdWord !== null && cmdWord !== 'node'; // (B) / (C)
    }
    if (external) {
      spans.push([openIdx, closeIdx]);
      for (const ident of bareIdentifierArgs(argsText)) { // one level of indirection (V5-2)
        spans.push(...findLocalArraySpans(content, ident));
      }
    }
  }
  return spans;
}

function offsetInSpans(offset, spans) {
  for (const [s, e] of spans) {
    if (offset >= s && offset < e) return true;
  }
  return false;
}

// External-tool-argument spans for .sh/.ps1 files (round-5 validation V5-1;
// replaces the pre-amendment "does a WORD appear anywhere in this LOGICAL
// LINE" heuristic, which fired inside comments/quoted strings and, being
// line-granular rather than position-granular, could sweep a script's OWN
// flag sitting BEFORE the external command on the same line — see
// docs/ai/validation/validation-20260815T085528Z-...-round5.md V5-1's
// fixture). A binary word is recognized only OUTSIDE a comment and OUTSIDE a
// quoted string — both masked to spaces first, so `git` inside `# ... git
// ...` or `"... git ..."` never counts — using the same dash-inclusive word
// boundary as wholeWordMatch (so "the-git-package" is never mistaken for the
// word "git"). Each recognized occurrence opens a span running FORWARD from
// itself to the next unmasked `;`/`|`/`&`/real-newline — never backward — so
// a flag occurring BEFORE the external word on the same line (this script's
// own flag, e.g. a case-label immediately followed by `git ...`) is never
// inside the span, while a local "run the external tool" wrapper (`if !
// command -v git`, `pkg_exec_command tsc --noEmit`) is still recognized
// because nothing requires the word to be the line's very first token.
// Backslash-newline line continuations are collapsed to spaces first, so a
// multi-line invocation (`sed -i \` / `-e '...' \` / ...) is one span,
// matching shell's own continuation rule. Process-name-based, not
// flag-based — this is the same "not a per-flag stoplist" shape as the
// .mjs NAME/SHAPE signals above.
const EXTERNAL_BIN_WORDS = ['git', 'gh', 'cargo', 'rg', 'wrangler', 'tsc', 'wsl', 'sed', 'npm', 'npx'];
const EXTERNAL_BIN_RE = new RegExp(`(?<![A-Za-z0-9_-])(?:${EXTERNAL_BIN_WORDS.join('|')})(?![A-Za-z0-9_-])`, 'g');

// Stack-based, offset-preserving (same length as `content`, so absolute
// offsets stay valid for offsetInSpans). A double-quoted string masks its
// content EXCEPT a nested `$(...)` command substitution — bash parses that
// as real, separately-quoted code even inside "..." (`HOOK_PATH="$(git
// rev-parse --git-path ...)"` must still see `git` as a command word, or
// this repo's OWN --git-path flag stays wrongly excluded nowhere near a real
// suppression risk, but the converse — treating the whole double-quoted
// span as inert — would silently stop recognizing this repo's most common
// invocation idiom as external). Single-quoted strings mask everything
// (bash performs no expansion inside '...', so nothing nested is real code).
// Backtick is NOT treated as command substitution — this repo's .sh files
// use only `$(...)`, and .ps1 uses backtick as its line-continuation/escape
// character (treating it as a quote-like toggle would misparse every
// PowerShell continuation), so a bare backtick is left as an ordinary
// character; only backtick-immediately-before-newline is recognized, as a
// second line-continuation form alongside bash's backslash-newline.
function maskShellNoise(content) {
  const n = content.length;
  const out = new Array(n);
  const stack = [{ type: 'top' }];
  let i = 0;
  while (i < n) {
    const frame = stack[stack.length - 1];
    const type = frame.type;
    const c = content[i];
    if (type !== 'squote' && (c === '\\' || c === '`') && (content[i + 1] === '\n' || (content[i + 1] === '\r' && content[i + 2] === '\n'))) {
      const len = content[i + 1] === '\n' ? 2 : 3; // line continuation -> spaces (offset-preserving)
      for (let k = 0; k < len; k++) out[i + k] = ' ';
      i += len;
      continue;
    }
    if (type !== 'squote' && c === '\\' && i + 1 < n) {
      const masked = type === 'dquote';
      out[i] = masked ? ' ' : c;
      out[i + 1] = masked ? ' ' : content[i + 1];
      i += 2;
      continue;
    }
    if (type === 'squote') {
      out[i] = c === '\n' ? '\n' : ' ';
      if (c === "'") stack.pop();
      i += 1;
      continue;
    }
    if (c === '#' && type !== 'dquote') {
      while (i < n && content[i] !== '\n') { out[i] = ' '; i += 1; }
      continue;
    }
    if (c === "'" && type !== 'dquote') { out[i] = ' '; stack.push({ type: 'squote' }); i += 1; continue; }
    if (c === '"') {
      out[i] = ' ';
      if (type === 'dquote') stack.pop(); else stack.push({ type: 'dquote' });
      i += 1;
      continue;
    }
    if (c === '$' && content[i + 1] === '(') {
      out[i] = ' '; out[i + 1] = ' ';
      stack.push({ type: 'subst', depth: 1 });
      i += 2;
      continue;
    }
    if (type === 'subst' && c === '(') { frame.depth += 1; out[i] = c; i += 1; continue; }
    if (type === 'subst' && c === ')') {
      frame.depth -= 1;
      out[i] = ')';
      if (frame.depth <= 0) stack.pop();
      i += 1;
      continue;
    }
    out[i] = type === 'dquote' ? (c === '\n' ? '\n' : ' ') : c;
    i += 1;
  }
  return out.join('');
}

function findExternalSpansShell(content) {
  const masked = maskShellNoise(content);
  const spans = [];
  let m;
  EXTERNAL_BIN_RE.lastIndex = 0;
  while ((m = EXTERNAL_BIN_RE.exec(masked)) !== null) {
    let end = masked.length;
    for (let k = m.index; k < masked.length; k++) {
      const ch = masked[k];
      if (ch === ';' || ch === '|' || ch === '&' || ch === '\n') { end = k; break; }
    }
    spans.push([m.index, end]);
  }
  return spans;
}

function extractCliFlags(content, filePath) {
  const out = [];
  const lines = content.split('\n');
  const isMjs = filePath.endsWith('.mjs');
  const externalSpans = isMjs ? findExternalSpansMjs(content) : findExternalSpansShell(content);
  const commentMarker = isMjs ? '//' : '#';
  const re = /(?<![A-Za-z0-9_])--[a-z][a-z0-9-]*/g;
  let offset = 0;
  for (let idx = 0; idx < lines.length; idx++) {
    const line = lines[idx];
    const commentAt = commentStartIndex(line, commentMarker);
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(line)) !== null) {
      if (m.index >= commentAt) continue; // comment-only occurrence (V5-2): never a candidate
      if (isCssCustomProperty(line, m.index, m[0].length)) continue;
      if (offsetInSpans(offset + m.index, externalSpans)) continue;
      out.push({ line: idx + 1, symbol: m[0] });
    }
    offset += line.length + 1;
  }
  return dedupeFirstLine(out);
}

function extractYamlKeys(content) {
  const out = [];
  content.split('\n').forEach((line, idx) => {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_-]*):/);
    if (m) out.push({ line: idx + 1, symbol: m[1] });
  });
  return dedupeFirstLine(out);
}

function extractFileCandidates(filePath) {
  const read = readTextSafe(filePath);
  if (!read.ok) return { unreadable: true, candidates: [] };
  const candidates = [];
  if (filePath.endsWith('.mjs') || filePath.endsWith('.sh') || filePath.endsWith('.ps1')) {
    for (const c of extractCliFlags(read.content, filePath)) candidates.push({ ...c, kind: 'cli-flag' });
  } else if (filePath.endsWith('.yaml')) {
    for (const c of extractYamlKeys(read.content)) candidates.push({ ...c, kind: 'yaml-key' });
  }
  return { unreadable: false, candidates };
}

// ---------------------------------------------------------------------------
// Surface (D3) — the closed file-glob set
// ---------------------------------------------------------------------------

function collectSurfaceFiles() {
  const scripts = walk('.aai/scripts');
  const mjsFiles = scripts.filter((f) => f.endsWith('.mjs'));
  const shFiles = scripts.filter((f) => f.endsWith('.sh'));
  const ps1Files = scripts.filter((f) => f.endsWith('.ps1'));
  let yamlFiles = [];
  try {
    yamlFiles = fs.readdirSync('.aai/system', { withFileTypes: true })
      .filter((e) => e.isFile() && e.name.endsWith('.yaml'))
      .map((e) => path.join('.aai/system', e.name));
  } catch {
    yamlFiles = [];
  }
  return [...mjsFiles, ...shFiles, ...ps1Files, ...yamlFiles];
}

function matchesScanGlobs(relPath) {
  if (/^\.aai\/scripts\/.+\.(mjs|sh|ps1)$/.test(relPath)) return true;
  if (/^\.aai\/system\/[^/]+\.yaml$/.test(relPath)) return true;
  return false;
}

// ---------------------------------------------------------------------------
// Diff resolution (--diff scope)
// ---------------------------------------------------------------------------

function tryGit(args) {
  try {
    const out = execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    return { ok: true, stdout: out };
  } catch {
    return { ok: false, stdout: '' };
  }
}

function resolveDiffInput(baseArg) {
  // Constitution art. 4 (degrade and report): a git failure (no git binary,
  // or cwd is not a git repository) must never silently masquerade as a
  // clean "working tree, no changes" scan — this cheap probe is the same
  // shape as the --all surfaceEmpty degrade (buildNotes below).
  const gitProbe = tryGit(['rev-parse', '--git-dir']);
  if (!gitProbe.ok) {
    return {
      mode: 'unavailable',
      label: 'unavailable (git failed: not a git repository, or git is not installed)',
      unavailable: true,
    };
  }
  const base = baseArg || 'main';
  const baseExists = tryGit(['rev-parse', '--verify', '--quiet', base]);
  if (!baseExists.ok) {
    return { mode: 'working-tree', label: 'working tree' };
  }
  const headExists = tryGit(['rev-parse', '--verify', '--quiet', 'HEAD']);
  if (!headExists.ok) {
    return { mode: 'working-tree', label: 'working tree' };
  }
  const baseSha = tryGit(['rev-parse', base]).stdout.trim();
  const headSha = tryGit(['rev-parse', 'HEAD']).stdout.trim();
  if (baseSha && headSha && baseSha === headSha) {
    return { mode: 'working-tree', label: 'working tree' };
  }
  return { mode: 'range', label: `${base}...HEAD`, range: `${base}...HEAD` };
}

// Map<posix relative path, Set<added line numbers in the NEW file>>. For
// 'range' mode this is exactly `git diff --unified=0 <range>`. For
// 'working-tree' mode a plain `git diff HEAD` never shows brand-new
// UNTRACKED files (they are not in the index at all) — exactly the common
// mid-implementation shape this skill runs against — so untracked files are
// added separately as fully-added (every line counts as added).
function resolveAddedLines(diffInput) {
  if (diffInput.unavailable) return { map: new Map(), rangeDiffFailed: false };
  if (diffInput.mode === 'range') {
    const res = tryGit(['diff', '--unified=0', diffInput.range]);
    // Both refs can resolve individually (resolveDiffInput already checked
    // that) yet share no merge base — e.g. two unrelated histories reached
    // via --base — and `git diff <base>...HEAD` then exits non-zero instead
    // of printing a diff. Treating that failure as empty diff TEXT would
    // misreport a git failure as a clean, nothing-found scan: same honesty
    // class as the NB-1 git-unavailable degrade in resolveDiffInput.
    if (!res.ok) return { map: new Map(), rangeDiffFailed: true };
    return { map: parseAddedLines(res.stdout), rangeDiffFailed: false };
  }
  const trackedRes = tryGit(['diff', '--unified=0', 'HEAD']);
  const map = parseAddedLines(trackedRes.ok ? trackedRes.stdout : '');
  const statusRes = tryGit(['status', '--porcelain', '--untracked-files=all']);
  if (statusRes.ok) {
    for (const line of statusRes.stdout.split('\n')) {
      if (!line.startsWith('?? ')) continue;
      let rel = line.slice(3).trim();
      if (rel.startsWith('"') && rel.endsWith('"')) rel = rel.slice(1, -1);
      if (map.has(rel)) continue;
      const read = readTextSafe(rel);
      if (!read.ok) continue;
      const lineCount = read.content.split('\n').length;
      const set = new Set();
      for (let i = 1; i <= lineCount; i += 1) set.add(i);
      map.set(rel, set);
    }
  }
  return { map, rangeDiffFailed: false };
}

function parseAddedLines(diffText) {
  const result = new Map();
  let currentFile = null;
  let pendingOldFile = null;
  let newLine = 0;
  for (const line of diffText.split('\n')) {
    if (line.startsWith('diff --git ')) {
      currentFile = null;
      pendingOldFile = null;
      continue;
    }
    // A COMPLETE file deletion never emits `+++ b/<path>` — git prints
    // `+++ /dev/null` for the new side instead, so the fileMatch branch
    // below never fires and the file gets no Map entry at all. That made a
    // deletion-only diff (the only change in the range) misread as an
    // EMPTY diff — the same "touched but nothing to extract" honesty gap
    // V4-6 fixed for a partial in-file deletion, one level up: the whole
    // file, not just its content, is what got removed. `--- a/<path>`
    // always precedes `+++ /dev/null` in the same file header, so its path
    // is captured here and registered (empty added-line set: a deletion
    // adds nothing) the moment the dev/null marker confirms a deletion.
    const oldFileMatch = line.match(/^--- a\/(.+)$/);
    if (oldFileMatch) {
      pendingOldFile = oldFileMatch[1];
      continue;
    }
    if (line === '+++ /dev/null') {
      if (pendingOldFile && !result.has(pendingOldFile)) result.set(pendingOldFile, new Set());
      currentFile = null;
      continue;
    }
    const fileMatch = line.match(/^\+\+\+ b\/(.+)$/);
    if (fileMatch) {
      currentFile = fileMatch[1];
      if (!result.has(currentFile)) result.set(currentFile, new Set());
      continue;
    }
    const hunkMatch = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
    if (hunkMatch) {
      newLine = parseInt(hunkMatch[1], 10);
      continue;
    }
    if (currentFile && line.startsWith('+') && !line.startsWith('+++')) {
      result.get(currentFile).add(newLine);
      newLine += 1;
      continue;
    }
    if (currentFile && line.startsWith(' ')) {
      newLine += 1;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Scan drivers — shared extraction + matching path (AC-03: one engine)
// ---------------------------------------------------------------------------

function matchAndSplit(rawCandidates, corpusText, corpusEmpty) {
  if (corpusEmpty) {
    return { candidates: rawCandidates, suppressed: 0 };
  }
  const candidates = [];
  let suppressed = 0;
  for (const c of rawCandidates) {
    if (wholeWordMatch(corpusText, c.symbol)) suppressed += 1;
    else candidates.push(c);
  }
  return { candidates, suppressed };
}

function scanAll() {
  const corpus = resolveAllCorpus();
  const corpusText = corpus.empty ? '' : buildCorpusText(corpus.documents);
  const files = collectSurfaceFiles();
  let unreadable = 0;
  const raw = [];
  for (const f of files) {
    const rel = toPosix(f);
    const { unreadable: fileUnreadable, candidates } = extractFileCandidates(f);
    if (fileUnreadable) {
      unreadable += 1;
      continue;
    }
    for (const c of candidates) raw.push({ path: rel, line: c.line, kind: c.kind, symbol: c.symbol });
  }
  const { candidates, suppressed } = matchAndSplit(raw, corpusText, corpus.empty);
  return {
    scope: 'all',
    corpus,
    surface: { filesScanned: files.length, extractorKinds: 2, unreadable },
    candidates,
    suppressed,
    notes: buildNotes({ corpus, surfaceEmpty: files.length === 0 }),
  };
}

function scanDiff({ base }) {
  const corpus = resolveDiffCorpus();
  const corpusText = corpus.empty ? '' : buildCorpusText(corpus.documents);
  const diffInput = resolveDiffInput(base);
  const { map: addedLines, rangeDiffFailed } = resolveAddedLines(diffInput);

  // B2: "the diff has no added lines at all" and "the diff has added lines,
  // but none of them are under the scanned surface" are DIFFERENT facts —
  // reporting both as the literal "empty diff" told a downstream project
  // (whose changed files are never under .aai/scripts or .aai/system, the
  // default shape for every AAI-vendored project) that its non-empty diff
  // was empty. touchedFiles answers "did the diff change anything";
  // scannedFiles narrows that to "anything this engine can extract from".
  // V4-6 (round-4 validation, residual of the same B2 conflation):
  // touchedFiles previously filtered on `lines.size > 0`, so a
  // DELETION-ONLY change to an existing file (its `+++ b/<path>` header
  // appears, so resolveAddedLines/parseAddedLines gives it a Map entry, but
  // the entry's Set stays empty because no `+` line was added) read as
  // untouched — the diff is NOT empty, it just added nothing. touchedFiles
  // is keyed off Map MEMBERSHIP (a file the diff mentions at all), not off
  // whether that file's added-line set is non-empty; whether a scanned
  // file's OWN candidates get reported still correctly depends on the
  // per-symbol `added.has(c.line)` check further down, unaffected by
  // this fix.
  const touchedFiles = [...addedLines.keys()];
  const diffEmpty = touchedFiles.length === 0;
  const scannedFiles = touchedFiles.filter((f) => matchesScanGlobs(f));
  const noScannedPath = !diffEmpty && scannedFiles.length === 0;

  let unreadable = 0;
  const raw = [];
  if (!diffEmpty && !noScannedPath) {
    for (const rel of scannedFiles) {
      const { unreadable: fileUnreadable, candidates } = extractFileCandidates(rel);
      if (fileUnreadable) {
        unreadable += 1;
        continue;
      }
      const added = addedLines.get(rel);
      for (const c of candidates) {
        // Both surviving kinds (cli-flag, yaml-key) report a symbol at the
        // exact physical line its own token sits on, so the diff's
        // added-line set is checked directly against that line.
        if (added.has(c.line)) raw.push({ path: rel, line: c.line, kind: c.kind, symbol: c.symbol });
      }
    }
  }

  const { candidates, suppressed } = matchAndSplit(raw, corpusText, corpus.empty);
  return {
    scope: 'diff',
    corpus,
    diffInput,
    emptyDiff: diffEmpty,
    surface: { filesScanned: scannedFiles.length, extractorKinds: 2, unreadable },
    candidates,
    suppressed,
    notes: buildNotes({
      corpus,
      diffInput,
      rangeDiffFailed,
      emptyDiff: diffEmpty,
      noScannedPath,
      touchedCount: touchedFiles.length,
    }),
  };
}

function buildNotes({ corpus, diffInput, rangeDiffFailed, emptyDiff, noScannedPath, touchedCount, surfaceEmpty }) {
  const notes = [NOT_SCANNED_NOTE];
  if (diffInput) notes.push(`Diff input: ${diffInput.label}`);
  if (diffInput && diffInput.unavailable) {
    // NB-1: a git failure is a DIFFERENT fact than "clean scan, nothing
    // found" and must say so — Constitution art. 4.
    notes.push('NOTE: git failed (not a git repository, or git is not installed) — the diff could not be resolved. This is NOT a clean scan: zero candidates here means nothing was checked, not that nothing was found.');
  } else if (rangeDiffFailed) {
    // Same honesty class as NB-1 above, one layer deeper: both refs
    // resolved, but `git diff <base>...HEAD` itself failed — most commonly
    // no merge base between two unrelated histories. Zero candidates here
    // must not read as "nothing to report".
    notes.push('NOTE: git diff failed for the resolved range — most likely no merge base between the two refs (unrelated histories). This is NOT a clean scan: zero candidates here means nothing was checked, not that nothing was found.');
  } else if (emptyDiff) {
    notes.push('NOTE: empty diff — rerun with --all to scan accumulated surface.');
  } else if (noScannedPath) {
    notes.push(`NOTE: diff touches ${touchedCount} file(s), but none are under the scanned surface (.aai/scripts/**/*.{mjs,sh,ps1}, .aai/system/*.yaml) — the diff is NOT empty, it is just out of class-4's scope. Rerun with --all to scan the accumulated surface instead.`);
  }
  if (corpus.empty) {
    notes.push(`NOTE: requirement corpus EMPTY (${corpus.reason}) — every extracted symbol is reported; treat this run as an inventory, not a finding list.`);
  } else if (corpus.unreadable && corpus.unreadable.length > 0) {
    // A PARTIAL corpus read — at least one document was readable, so the
    // corpus is not empty, but a symbol named only by the skipped
    // document would otherwise be falsely reported as unrequested with no
    // trace of why. Name every skipped path rather than dropping it.
    notes.push(`NOTE: requirement document(s) unreadable, skipped (not searched): ${corpus.unreadable.join(', ')}.`);
  }
  if (surfaceEmpty) {
    notes.push('NOTE: surface EMPTY (0 files under .aai/scripts or .aai/system) — this almost always means the scan was invoked from the wrong working directory; re-run from the repository root.');
  }
  return notes;
}

// ---------------------------------------------------------------------------
// Reporting (D5) — human text and --json, both carrying the LIMITS block
// ---------------------------------------------------------------------------

function buildLimits(suppressed, diffInput) {
  const limits = [
    'Pattern-based extraction, not a parser: dynamically created exports, computed names and generated flags are invisible to this scan.',
    `FALSE NEGATIVES: a symbol named ANYWHERE in a requirement document, including prose, is suppressed. Suppressed this run: ${suppressed}.`,
    'Report only. No file was written. Nothing here is a verdict.',
    // Round-5 candidate adjudication (docs/ai/reports/deslop-candidate-
    // adjudication-20260815.md, summarized in the CHANGE intake's
    // Adjudication Summary — docs/issues/
    // CHANGE-0145-deslop-scope-and-unrequested-engine.md, moved there from
    // the spec by the 2026-08-15 remediation) walked all 70 real-tree
    // candidates and found 10 that are flag-shaped TEXT, not a flag this
    // code owns: a string comparison, a printf/suggestion message, a
    // regex pattern, or a flag naming a separately configured external
    // agent CLI. Telling those apart from a genuine own flag needs
    // semantics (does this string describe a flag, or invoke one?), not
    // syntax — this pattern-based scan cannot attempt it, and no correct
    // per-run count can be computed without that same semantic judgment,
    // so this line is disclosed qualitatively rather than with a guessed
    // number (a fabricated figure would be worse than none).
    'TEXT, NOT A FLAG: some candidates are flag-shaped TEXT rather than a flag this code owns — a string comparison, a printf/suggestion message, a regex pattern, or a flag naming a separately configured external agent CLI. Distinguishing those needs semantics, not syntax, so this pattern-based scan does not attempt it — read each candidate before acting.',
  ];
  // V4-1 / F17 (tracked fu-deslop-range-mode-dirty-worktree, deliberately
  // OPEN — not fixed by this pass): range mode takes its added-line numbers
  // from `git diff <base>...HEAD` but reads file CONTENT from the worktree,
  // so uncommitted edits on top of that range can report an untouched
  // symbol or miss a changed one. Disclosed here (it previously was not)
  // because a range-mode run with a dirty worktree is a real, reachable
  // shape, not a hypothetical.
  if (diffInput && diffInput.mode === 'range') {
    limits.push('RANGE MODE + DIRTY WORKTREE (tracked, open: fu-deslop-range-mode-dirty-worktree): added-line numbers come from the committed range, but file content is read from the worktree — uncommitted edits on top of this range can produce a false positive or a false negative.');
  }
  return limits;
}

function renderHuman(result) {
  const lines = [];
  lines.push(`DESLOP class-4 scan — scope: ${result.scope}`);
  if (result.scope === 'all') {
    const c = result.corpus;
    if (c.empty) {
      lines.push(`  Requirement corpus: 0 documents (${c.reason})`);
    } else {
      lines.push(`  Requirement corpus: ${c.documents.length} documents (type spec, status accepted/implementing/done)`);
      lines.push(`    excluded: ${c.excluded.draft} draft, ${c.excluded.proposed} proposed, ${c.excluded.rejected} rejected, ${c.excluded.superseded} superseded, ${c.excluded.deferred} deferred`);
    }
  } else {
    const c = result.corpus;
    lines.push(`  Requirement corpus: ${c.documents.length} documents (STATE current_focus: spec_path, primary_path)`);
  }
  for (const n of result.notes) lines.push(`  ${n}`);
  const surfaceSuffix = result.scope === 'diff' ? ' (of diff)' : '';
  lines.push(`  Surface scanned: ${result.surface.filesScanned} files${surfaceSuffix}, ${result.surface.extractorKinds} extractor kinds, ${result.surface.unreadable} unreadable`);
  lines.push(`  Candidates: ${result.candidates.length}`);
  for (const cand of result.candidates) {
    lines.push(`    ${cand.path}:${cand.line}  ${cand.kind}  ${cand.symbol}`);
  }
  lines.push('LIMITS (read before acting)');
  for (const limit of buildLimits(result.suppressed, result.diffInput)) {
    lines.push(`  - ${limit}`);
  }
  return lines.join('\n');
}

function renderJson(result) {
  const excludedBlock = result.scope === 'all' && !result.corpus.empty ? result.corpus.excluded : {
    draft: 0, proposed: 0, rejected: 0, superseded: 0, deferred: 0,
  };
  const payload = {
    scope: result.scope,
    requirement_corpus: {
      count: result.corpus.documents.length,
      documents: result.corpus.documents,
      excluded: excludedBlock,
      empty: result.corpus.empty,
      empty_reason: result.corpus.empty ? result.corpus.reason : null,
    },
    diff_input: result.diffInput ? result.diffInput.label : null,
    surface: {
      files_scanned: result.surface.filesScanned,
      extractor_kinds: result.surface.extractorKinds,
      unreadable: result.surface.unreadable,
    },
    candidates: result.candidates,
    suppressed: result.suppressed,
    notes: result.notes,
    limits: buildLimits(result.suppressed, result.diffInput),
  };
  return JSON.stringify(payload, null, 2);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

const args = parseArgs(process.argv);
if (!args) usageExit();

const result = args.diff ? scanDiff({ base: args.base }) : scanAll();
console.log(args.json ? renderJson(result) : renderHuman(result));
process.exit(0);
