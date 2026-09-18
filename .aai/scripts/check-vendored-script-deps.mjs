#!/usr/bin/env node
/**
 * check-vendored-script-deps.mjs — the vendored-engine-missing-its-own-
 * import guard (validation round 4 follow-up, spec-close-ceremony-sweep
 * Amendment 21).
 *
 * THE DEFECT CLASS
 * A test fixture that wants to exercise the REAL, CURRENT version of an
 * `.aai/scripts/*.mjs` engine (not a frozen stand-in) copies that one file
 * into an isolated fixture root:
 *
 *     cp "$PROJECT_ROOT/.aai/scripts/ride-select.mjs" "$d/.aai/scripts/"
 *
 * This is correct on the day it is written. It silently breaks the moment
 * that engine's OWN source gains a new `import ... from './something.mjs'`
 * (a sibling script or a `lib/*.mjs` helper) that the fixture does not also
 * carry: node's ESM loader cannot resolve the import inside the fixture and
 * exits with ERR_MODULE_NOT_FOUND. Depending on how the caller treats a
 * non-zero exit, this can look like an ordinary refusal rather than a crash
 * — exactly what happened to `ride-select.mjs` vendored alone in
 * tests/skills/test-aai-orchestration-dispatch.sh: Spec-AC-29's own R6/D2
 * fix added `import { parseFrontmatter, DOC_TYPE_ENUM } from
 * './lib/docs-model.mjs'`, the fixture never copied `lib/`, and
 * `test_567_rule_4a_single_retarget` failed reading `no_action` — a passing
 * arm gone silently wrong, not a crash, because the caller (`roadmapGate()`)
 * treats "the gate could not run" the same as "the gate said no".
 *
 * WHAT THIS GUARD DOES
 * For every `tests/skills/*.sh` bash FUNCTION that copies a single
 * top-level `.aai/scripts/<name>.mjs` file (never a `lib/*.mjs` helper —
 * those are dependencies, not vendored engines) into a fixture root, this
 * computes that engine's TRANSITIVE closure of relative (`./...`) imports by
 * reading the REAL, CURRENT file on disk — never a hand-maintained list that
 * could itself go stale the same way the fixture did — and checks that the
 * function's EFFECTIVE coverage (its own `cp` lines, PLUS every function it
 * calls, resolved recursively over the file's own call graph — see below)
 * carries every file in that closure, by one of:
 *   - a specific `cp .../<path>` naming that exact file, or
 *   - a `.aai/scripts/<dir>/*` glob or `.aai/scripts/<dir>/$VAR`-shaped
 *     dynamic copy (covers everything under that subdirectory — `lib/` is
 *     the common case, but not the only one; see DIR_GLOB_RE below), or
 *   - a recursive `.aai/scripts` (or `.aai/scripts/lib`) directory copy.
 * The vendored engine's own SOURCE is identified by the `cp` line's SOURCE
 * argument's own SHAPE — `.../.aai/scripts/<name>.mjs`, whichever
 * variable(s) spell the prefix — or, when the source is a bare variable
 * reference, by a same-file assignment of that shape (see
 * `vendoredSourceScriptName`/`ASSIGN_*` below); it is never restricted to a
 * specific variable name.
 * A required file not covered by any of these is a VIOLATION, naming the
 * vendored engine, the missing dependency, and the function.
 *
 * WHY CALL-GRAPH INHERITANCE, NOT A SIMPLER SCOPE. Two simpler designs were
 * tried and rejected in order:
 *   v1, per-function, NO inheritance: 19 false positives across 5 files, all
 *   the same shape — a shared fixture-building helper (`setup_iso_repo()`,
 *   `mk_root()`, `new_bare_fixture()`+`add_core_and_role_files()`) copies
 *   `.aai/scripts/lib/*.mjs` wholesale in ONE function, and the function
 *   that vendors and RUNS the engine is built on top of that already-
 *   populated fixture root (`d="$(setup_iso_repo ...)"`, or a bare call
 *   that mutates an existing dir in place) — a DIFFERENT function. v1 could
 *   not see the helper's copy at all.
 *   v2, WHOLE-FILE (every `cp` anywhere in the file covers every vendored
 *   script in the file): fixed all 19 false positives, but FALSE-NEGATIVED
 *   on the checker's own reason for existing — reverting this file's own
 *   Amendment 21 fix and re-running v2 still reported CLEAN, because
 *   tests/skills/test-aai-orchestration-dispatch.sh ALSO contains two wholly
 *   unrelated fixture-builders (`pre_change_dispatch_tree()`,
 *   `pre_harness_dispatch_tree()`) that `cp -r $PROJECT_ROOT/.aai/scripts`
 *   for a different test's purposes — neither is ever called by
 *   `test_567_rule_4a_single_retarget`, but v2's file-wide union could not
 *   tell the difference. A checker that cannot see its own target defect is
 *   worse than none: it would have shipped as a green gate hiding a red
 *   fixture, measured directly before this design replaced it.
 * This (v3) design's inheritance edge is a real CALL — bare `B ...` or
 * `x="$(B ...)"` inside A's own body — so it reaches `setup_iso_repo()` from
 * its caller (a real call edge) without also reaching
 * `pre_change_dispatch_tree()` from an unrelated test (no call edge at
 * all). Function ranges are the same convention used throughout
 * tests/skills/*.sh: a top-level `name() {` opens, a line that is exactly
 * `}` (no leading whitespace) closes; a `cp` line outside any function is
 * attributed to a synthetic `<top-level>` pseudo-function.
 *
 * SCOPE / WHAT THIS DELIBERATELY DOES NOT CATCH
 *   - Only relative (`./` or `../`) imports ending in `.mjs` are followed;
 *     `node:` built-ins and bare package specifiers are not dependencies a
 *     fixture must vendor. Dynamic `await import(...)`, `export ... from`
 *     and side-effect `import './x.mjs'` are not followed either — measured
 *     directly (grep over every `.aai/scripts` engine and lib file): none
 *     of the three shapes occurs anywhere in the engine corpus today, so
 *     this is a scope limit with no live false negative behind it, not a
 *     gap disclosed only in theory.
 *   - SOURCE-line coverage (validation-round5 B2-R5, re-measured at the
 *     ride's own base commit 2762264e, before this round's fixes): a blind
 *     text grep for `cp .*\.aai/scripts/[A-Za-z0-9_.-]+\.mjs` across
 *     `tests/skills/*.sh` finds 77 lines. Of those, 6 are NOT real vendoring
 *     sites and this checker correctly does not count them: 4 are
 *     `test_131`'s own BITE fixtures (`tests/skills/test-aai-hygiene-pack.sh`)
 *     vendoring a `target-engine.mjs` that does not exist under the real
 *     `.aai/scripts/` — `fs.existsSync` already excludes those, independent
 *     of heredoc handling — and 2 (`test-aai-update.sh`'s
 *     `build_fixture_doctor_source_repo`) are `<<'STUB'`/`<<'FIXTURE'`
 *     HEREDOC BODY TEXT — a nested, self-contained STUB `aai-doctor.mjs` and
 *     a synthetic `aai-sync.sh` written out for a DIFFERENT fixture process
 *     to run, never code this file itself executes — excluded by
 *     `computeHeredocMask` (below). The remaining 71 grep-matched lines are
 *     all real, and all now correctly recognized: 13 of them (of 15 raw
 *     grep lines spelling some OTHER variable; the other 2 of those 15 are
 *     the excluded heredoc lines above) were fixed this round, and 58 (of
 *     62 raw grep lines spelling `$PROJECT_ROOT`/`$SRC_ROOT`; the other 4
 *     of those 62 are the excluded BITE-fixture lines above) already were —
 *     NOT 62, which double-counted the 4 BITE lines as "already recognized
 *     real sites" when they were never real sites at all (validation-round6,
 *     confirmed by instrumenting the pre-round checker at its own
 *     `existsSync` push point: `SITES 58`; Amendment 22's matching sentence
 *     is corrected by name in Amendment 23, not edited here). SIX further genuine
 *     vendoring sites — `test-aai-delta-stage3.sh:77`/`:335`,
 *     `test-aai-live-status.sh:611`, `test-aai-spec-amend.sh:1422`/`:1476`,
 *     `test-aai-test-canon.sh:122` — are OUTSIDE that same blind grep
 *     entirely (their destination is a bare directory or a
 *     `.aai/scripts/`-free flat path, so the text `.aai/scripts/<name>.mjs`
 *     never appears anywhere on the line) and are still found, because
 *     detection is keyed on the SOURCE argument's shape or variable, never
 *     on the destination's path or on that substring's presence anywhere on
 *     the line. Net: 71 + 6 = 77 vendored-engine sites recognized today
 *     (`--json`'s `vendoredSites`, and the human summary's own count), and 0
 *     violations remain against them.
 *   - A script copied into a fixture but never actually EXECUTED from that
 *     copy (read only for its bytes, or resolved by the invoking tool from
 *     its own real, un-vendored location — e.g. aai-doctor.mjs resolves its
 *     CAT-06/CAT-13 sub-checkers via `import.meta.url`, never `--root`) is
 *     still flagged if its dependency is missing: this checker cannot tell
 *     "copied for decoration" from "copied to run". A false positive of
 *     that specific shape WAS observed in this corpus (golden-flow.mjs,
 *     tests/skills/test-aai-release.sh TEST-036 — aai-release.sh only
 *     `[ -f ... ]`-stats the vendored copy, never `node`s it) and fixed by
 *     copying the real dependency anyway (harmless even if never read, and
 *     it means a FUTURE test that does invoke that copy inherits a fixture
 *     that already carries what the engine needs) rather than adding an
 *     exemption here. If another one appears, prefer that same fix over
 *     narrowing this checker's confidence further.
 *   - This is a HARD GATE, not a ratchet: the defect class has no
 *     legitimate "acceptable known violation", so there is no baseline file
 *     and no --record mode, unlike check-cd-subshell-leak.mjs / check-base-
 *     ref-pins.mjs.
 *
 * USAGE
 *   node .aai/scripts/check-vendored-script-deps.mjs [--root <dir>] [--json]
 *
 * EXIT CONTRACT
 *   0  clean — every vendored engine's transitive dependencies are covered
 *   1  one or more violations (see stdout)
 *   2  usage error
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HELP = 'usage: check-vendored-script-deps.mjs [--root <dir>] [--json]\n';

function fail(msg) {
  process.stderr.write(`check-vendored-script-deps: ${msg}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const args = { root: process.cwd(), json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--root') { args.root = argv[++i]; if (!args.root) fail('--root needs a directory'); }
    else if (a === '--json') args.json = true;
    else if (a === '--help' || a === '-h') { process.stdout.write(HELP); process.exit(0); }
    else fail(`unknown argument: ${a}`);
  }
  return args;
}

// relativeImportsOf(absFile) -> array of the file's own `./...`/`../...`
// import targets ending in `.mjs`, resolved to POSIX paths relative to
// `.aai/scripts/` (e.g. 'lib/docs-model.mjs', 'branch-guard.mjs'). Reads
// the file fresh every call — never cached across a run in a way that could
// go stale within one invocation, and never memoizes across process runs.
function relativeImportsOf(absFile, scriptsRootAbs) {
  let content;
  try {
    content = fs.readFileSync(absFile, 'utf8');
  } catch {
    return [];
  }
  const out = [];
  const re = /^\s*import\s+(?:[^'"]*?)\s+from\s+['"](\.\.?\/[^'"]+\.mjs)['"]/gm;
  let m;
  while ((m = re.exec(content))) {
    const spec = m[1];
    const absTarget = path.resolve(path.dirname(absFile), spec);
    const rel = path.relative(scriptsRootAbs, absTarget).split(path.sep).join('/');
    out.push(rel);
  }
  return out;
}

// transitiveDeps(scriptRel, scriptsRootAbs) -> Set of every '.mjs' file
// (POSIX path relative to .aai/scripts/) reachable from scriptRel via
// relative imports, EXCLUDING scriptRel itself. BFS, cycle-safe.
function transitiveDeps(scriptRel, scriptsRootAbs) {
  const seen = new Set([scriptRel]);
  const deps = new Set();
  const queue = [scriptRel];
  while (queue.length) {
    const cur = queue.shift();
    const absCur = path.join(scriptsRootAbs, cur);
    for (const rel of relativeImportsOf(absCur, scriptsRootAbs)) {
      deps.add(rel);
      if (!seen.has(rel)) {
        seen.add(rel);
        queue.push(rel);
      }
    }
  }
  return deps;
}

// --- fixture-function scan over one tests/skills/*.sh file -----------------
//
// vendoredSourceScriptName() / ASSIGN_RE (validation-round5 B2-R5): a `cp`
// line's SOURCE naming a single TOP-LEVEL `.aai/scripts/<name>.mjs` file
// (never `.../lib/<name>.mjs` — the character class excludes `/`, so a
// `lib/...` path can never satisfy the final `\.mjs` requirement at this
// position), resolved by the SHAPE of the path, never by which variable
// spells its prefix. The prior version required the literal prefix
// `$PROJECT_ROOT` or `$SRC_ROOT` immediately before the path, which is only
// one of two shapes the live corpus actually uses (measured: 15 of 77
// vendoring `cp` lines used a different spelling and were invisible to it —
// see the checker's own docstring above). Two forms are now resolved:
//   (a) the source argument's own text already has the shape
//       `.../.aai/scripts/<name>.mjs`, whatever identifier(s) precede it
//       ($PROJECT_ROOT, $SRC_ROOT, a fixture-local $src, or even a
//       fixture-rooted $d re-copying an already-vendored file); or
//   (b) the source argument is a bare variable reference (`$VAR` or
//       `${VAR}`) that this SAME FILE assigns, on some other line, from a
//       `$PROJECT_ROOT`- or `$SRC_ROOT`-rooted path of shape (a) — the
//       `$HB` / `$DOCTOR` / `$CHECK_SCRIPT` idiom.
// Any specific file this function ALSO copies, lib or sibling alike.
const COPY_RE = /\.aai\/scripts\/((?:lib\/)?[A-Za-z0-9_.-]+\.mjs)/g;
// A glob or recursive directory copy that covers a whole subtree — ANY
// `.aai/scripts/<dir>/...` subdirectory, not only `lib/` (validation-round5
// B2-R5's own follow-on: fixing SOURCE detection made three previously-
// invisible vendoring sites visible for the first time, and one real shape
// among them — `cp "$PROJECT_ROOT/.aai/scripts/live-parsers/"*.mjs
// "$dest/live-parsers/"` — copies a whole SIBLING subdirectory the same way
// the old lib-only glob did). Matches either a literal `*` glob (optionally
// right after a closing quote, the corpus's own
// `"$ROOT/.../live-parsers/"*.mjs` idiom) or a bare `$VAR`/`${VAR}`
// reference in the file-name position (the `for f in a.mjs b.mjs; do cp
// ".../lib/$f" ...; done` idiom, e.g. test-aai-sweep-parallel.sh's own
// per-engine lib-copy helper) — either shape means "whatever this
// subdirectory needs, by name, is copied", which is what a fixed
// member-list glob means too.
const DIR_GLOB_RE = /\.aai\/scripts\/([A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*)\/(?:"?\*|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)/g;
const SCRIPTS_DIR_COPY_RE = /cp\s+(?:-\w+\s+)*"?\$(?:PROJECT_ROOT|SRC_ROOT)"?\/?\.aai\/scripts"?\s/;
const LIB_DIR_COPY_RE = /cp\s+(?:-\w+\s+)*"?\$(?:PROJECT_ROOT|SRC_ROOT)"?\/?\.aai\/scripts\/lib"?\s/;
// A narrow special case DIR_GLOB_RE cannot reach: the source path's
// `.aai/scripts` prefix is itself hidden behind a command substitution
// (`$(dirname "$SA")/lib/$_lib`, test-aai-spec-amend.sh's
// `test_445_ac12_negative_controls_test003_008_009` — a loop that `grep`s
// the REAL engine's own `from './lib/...'` import lines and copies every
// match by name, so it can never go stale the way a fixed list could).
// Measured: exactly 2 lines in the whole corpus match this shape (both in
// the same function, both this same loop) — narrow enough that a false
// negative from over-matching is not a live risk today.
const LIB_VAR_COPY_RE = /(?:^|\/)lib\/\$\{?[A-Za-z_][A-Za-z0-9_]*\}?(?:["\s]|$)/;
// A same-file `VAR="...$PROJECT_ROOT|$SRC_ROOT.../.aai/scripts/<name>.mjs..."`
// (or `VAR="${OTHER:-$PROJECT_ROOT/.../<name>.mjs}"`) assignment — resolves
// form (b) above. Deliberately whole-file, not per-function: the assignment
// and the `cp` that dereferences it are routinely in different functions
// (`HB=...` at file scope, `cp "$HB" ...` inside a test function). Scoped
// PER `NAME=VALUE` TOKEN (never the rest of the line): a single `local a=...
// b=...` line assigns several variables at once, and an earlier version of
// this regex let a later variable's shaped value get attributed to an
// earlier variable's name on the same line (test-aai-intake.sh's
// `local src="${1:-...INTAKE_COMMON.md}" script="${2:-.../docs-audit.mjs}"`
// falsely mapped `src` to `docs-audit`).
const ASSIGN_TOKEN_RE = /([A-Za-z_][A-Za-z0-9_]*)=("(?:[^"\\]|\\.)*"|'[^']*'|\S*)/g;
const ASSIGN_SHAPE_RE = /\$(?:PROJECT_ROOT|SRC_ROOT)"?\/?\.aai\/scripts\/([A-Za-z0-9_.-]+)\.mjs/;

// Extracts, from a `cp` line, the top-level `.aai/scripts/<name>.mjs` script
// name its SOURCE (first non-flag argument) names — by the path's own SHAPE
// when the argument spells it directly, or via `varToScript` when the
// argument is a bare reference to a same-file assignment of that shape.
// Never matches a `.../lib/<name>.mjs` dependency (the shape regex's
// character class excludes `/`, so a `lib/...` segment can never reach the
// trailing `\.mjs` it requires).
function vendoredSourceScriptName(line, varToScript) {
  const tokens = line.match(/"[^"]*"|'[^']*'|\S+/g) || [];
  const args = tokens.slice(1).filter((t) => !/^-/.test(t));
  if (args.length === 0) return null;
  const src = args[0].replace(/^["']|["']$/g, '');
  const direct = /\.aai\/scripts\/([A-Za-z0-9_.-]+)\.mjs$/.exec(src);
  if (direct) return direct[1];
  const varMatch = /^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$/.exec(src);
  if (varMatch && varToScript.has(varMatch[1])) return varToScript.get(varMatch[1]);
  return null;
}

// scanAssignments(lines) -> Map<VAR, scriptName> for every same-file
// assignment matching ASSIGN_SHAPE_RE — built once per file (see
// vendoredSourceScriptName). Tokenized per `NAME=VALUE` so a multi-variable
// `local a=... b=...` line cannot cross-attribute (see ASSIGN_TOKEN_RE above).
function scanAssignments(lines) {
  const map = new Map();
  for (const line of lines) {
    ASSIGN_TOKEN_RE.lastIndex = 0;
    let m;
    while ((m = ASSIGN_TOKEN_RE.exec(line))) {
      const shape = ASSIGN_SHAPE_RE.exec(m[2]);
      if (shape) map.set(m[1], shape[1]);
    }
  }
  return map;
}

// computeHeredocMask(lines) -> boolean[] marking every line that is BODY
// TEXT of a `<<WORD` / `<<'WORD'` / `<<-WORD` heredoc, never executed shell
// code — e.g. test-aai-update.sh's `build_fixture_doctor_source_repo` writes
// a whole nested `aai-sync.sh` fixture as heredoc TEXT, and that text
// happens to contain a `cp .../.aai/scripts/aai-doctor.mjs ...` line that
// reads exactly like a real vendoring `cp` to a line-based scanner. Does not
// attempt to also fix function-range attribution across a heredoc containing
// a column-0 `}` (a DIFFERENT, measured non-blocking gap: 91 such ranges
// corpus-wide, none of which change the live verdict) — only excludes
// heredoc BODY lines from `cp`/call-graph scanning, since B2-R5's own fix is
// what first turned this heredoc's text into a false vendoring match.
function computeHeredocMask(lines) {
  const mask = new Array(lines.length).fill(false);
  const startRe = /<<(-?)\s*(?:(['"])([A-Za-z_][A-Za-z0-9_]*)\2|([A-Za-z_][A-Za-z0-9_]*))/g;
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    startRe.lastIndex = 0;
    let m;
    let terminator = null;
    let stripTabs = false;
    while ((m = startRe.exec(line))) {
      if (line[m.index - 1] === '<') continue; // part of a `<<<` here-string, not a heredoc
      terminator = m[3] || m[4];
      stripTabs = m[1] === '-';
      break;
    }
    i += 1;
    if (!terminator) continue;
    while (i < lines.length) {
      mask[i] = true;
      const body = stripTabs ? lines[i].replace(/^\t+/, '') : lines[i];
      const isEnd = body === terminator;
      i += 1;
      if (isEnd) break;
    }
  }
  return mask;
}

// maskQuotedRegions(line) -> the line with every character that sits inside
// a single- or double-quoted STRING LITERAL, or an unquoted `#` COMMENT,
// replaced by a space, so a name that merely appears in prose (a
// log_info/log_fail message, or a `# built on top of setup_iso_repo`-shaped
// comment) can never satisfy CALL_RE below (validation-round5 B1-R5:
// `log_info "... (main-guard ...)"` let `(main-guard` be read as a call to
// `main`, inheriting that function's whole-file coverage — v2's rejected
// whole-file masking, revived through a string; code review 20260918T172546Z
// NON-BLOCKING measured the SAME shape revived through a `#` comment instead,
// 21 call edges live in the corpus that exist only because a function name
// appears after one, three of them the same `test_fn -> main` pattern).
// A `#` starts a comment only when it opens a WORD — the first character of
// the line or preceded by whitespace — so `${#arr[@]}` / `${var#pattern}`
// parameter expansion is never mis-masked as a comment; bash applies the
// same word-boundary rule. A `$(...)` command-substitution span is CODE
// regardless of whether it sits inside a double-quoted string
// (`x="$(helper ...)"` is the corpus's own idiom for a call-and-capture) and
// is left unmasked, including a `#` inside it (still a real comment there,
// masked the same way); single-quoted text is never re-entered as code
// (bash gives it none).
function maskQuotedRegions(line) {
  const chars = line.split('');
  const out = new Array(chars.length);
  const stack = ['code']; // 'code' | 'squote' | 'dquote'
  let i = 0;
  while (i < chars.length) {
    const c = chars[i];
    const top = stack[stack.length - 1];
    if (top === 'squote') {
      out[i] = ' ';
      if (c === "'") stack.pop();
      i += 1;
      continue;
    }
    if (c === '\\' && top === 'dquote') {
      out[i] = ' ';
      if (i + 1 < chars.length) { out[i + 1] = ' '; i += 2; } else { i += 1; }
      continue;
    }
    if (c === '#' && top === 'code' && (i === 0 || /\s/.test(chars[i - 1]))) {
      for (let j = i; j < chars.length; j += 1) out[j] = ' ';
      i = chars.length;
      continue;
    }
    if (c === "'" && top !== 'dquote') {
      out[i] = ' ';
      stack.push('squote');
      i += 1;
      continue;
    }
    if (c === '"') {
      out[i] = ' ';
      if (top === 'dquote') stack.pop(); else stack.push('dquote');
      i += 1;
      continue;
    }
    if (c === '$' && chars[i + 1] === '(') {
      out[i] = c; out[i + 1] = chars[i + 1];
      stack.push('code');
      i += 2;
      continue;
    }
    if (c === ')' && top === 'code' && stack.length > 1) {
      out[i] = c;
      stack.pop();
      i += 1;
      continue;
    }
    out[i] = top === 'dquote' ? ' ' : c;
    i += 1;
  }
  return out.join('');
}

// Scope is PER-FUNCTION, with EXPLICIT CALL-GRAPH INHERITANCE — neither of
// the two simpler designs tried first survives this corpus:
//
//   v1, per-function, no inheritance: 19 false positives, all the SAME
//   shape — a shared fixture-building helper (setup_iso_repo(), mk_root(),
//   new_bare_fixture()+add_core_and_role_files()) copies
//   `.aai/scripts/lib/*.mjs` wholesale in ONE function, and the function
//   that vendors and RUNS the engine is built ON TOP of that already-copied
//   fixture root (`d="$(setup_iso_repo ...)"` or a bare call that mutates
//   an existing dir in place) — a DIFFERENT function. v1 cannot see the
//   helper's copy at all.
//
//   v2, whole-file (every cp anywhere in the file covers every vendored
//   script in the file): measured CLEAN on the v1 false positives, but
//   FALSE NEGATIVE on the exact defect this checker exists for — reverting
//   this file's own ride-select.mjs fix (Amendment 21) and re-running v2
//   still reported CLEAN, because tests/skills/test-aai-orchestration-
//   dispatch.sh ALSO contains two wholly unrelated fixture-builders
//   (pre_change_dispatch_tree(), pre_harness_dispatch_tree()) that
//   `cp -r $PROJECT_ROOT/.aai/scripts` for a different test's purposes —
//   neither is ever called by test_567_rule_4a_single_retarget, but v2's
//   file-wide union could not tell the difference. A checker that cannot
//   see its own target defect is worse than none: it would have shipped as
//   a green gate hiding a red fixture.
//
// This version keeps v1's per-function precision but adds the one relation
// that actually matters: function A's coverage includes function B's
// coverage whenever A's body CALLS B (bare `B ...` or `x="$(B ...)"`) —
// covering the real "shared fixture-builder helper" shape — resolved via a
// memoized DFS over the file's own call graph, so it extends coverage only
// along an actual call edge, never to an unrelated function that merely
// lives in the same file.
//
// v3 (this version, as first shipped) matched a bare name after `(`, `=`,
// `&&`, `;` or line start ANYWHERE on the line, including inside a
// double-quoted string — so a name that merely appears in PROSE (a
// `log_info`/`log_fail` message parenthetical naming a function, e.g.
// `log_info "... (main-guard URL-decode bug)..."`) was read as a call to
// that name, re-creating v2's whole-file masking through a single string
// (validation-round5 B1-R5, measured live: `test-aai-layer-drift.sh`'s
// `test_space_in_path` inherited `main()`'s whole-file coverage this way).
// v3.1 runs CALL_RE only against `maskQuotedRegions(line)` (above), so a
// name is a call edge only when it sits in COMMAND POSITION — never inside
// a quoted string literal, `$(...)` command substitution excepted (that is
// still a real call, wherever it is quoted). v3.1, as first shipped, did not
// mask `#` comments — the SAME prose-name gap v3 had just closed for quoted
// strings, revived through a comment instead (code review 20260918T172546Z
// NON-BLOCKING: 21 call edges in the live corpus existed only because a
// function name appeared after an unquoted `#`, three of them the exact
// `test_fn -> main` shape B1-R5 named). v3.2 masks a `#` that opens a word
// the same way it already masks a quote — see `maskQuotedRegions` above.
const CALL_RE = /(?:^|[=(]\s*|&&\s*|;\s*)"?\$?\(?\s*([A-Za-z_][A-Za-z0-9_]*)\b/g;

function scanFile(relFile, absFile, scriptsRootAbs, violations, vendoredSites) {
  const lines = fs.readFileSync(absFile, 'utf8').split('\n');
  // A function's opening brace often carries a trailing `# comment` on the
  // SAME line (e.g. `test_567_rule_4a_single_retarget() {  # TEST-567 /
  // Spec-AC-29`) — 466 occurrences measured across tests/skills/*.sh. A
  // stricter end-of-line anchor silently failed to recognize any of them as
  // function starts at all (attributing their whole body to whatever OTHER
  // scope was open, or to '<top-level>'), which is exactly how this checker
  // first missed test_567_rule_4a_single_retarget's own defect — the
  // function that could have caught its own regression was itself invisible
  // to the scanner. No closing `}` line in the corpus carries a trailing
  // comment (measured: 0), so FN_END_RE stays anchored.
  const FN_START_RE = /^([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{\s*(#.*)?$/;
  const FN_END_RE = /^\}\s*$/;

  // Pass 1: split the file into function bodies (name -> line range),
  // attributing every line outside any function to a synthetic
  // '<top-level>' pseudo-function so nothing is silently skipped.
  const fnRanges = []; // { name, start, end } end exclusive
  let curName = '<top-level>';
  let curStart = 0;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const startMatch = FN_START_RE.exec(line);
    if (startMatch) {
      fnRanges.push({ name: curName, start: curStart, end: i });
      curName = startMatch[1];
      curStart = i + 1;
      continue;
    }
    if (FN_END_RE.test(line) && curName !== '<top-level>') {
      fnRanges.push({ name: curName, start: curStart, end: i });
      curName = '<top-level>';
      curStart = i + 1;
      continue;
    }
  }
  fnRanges.push({ name: curName, start: curStart, end: lines.length });

  const definedNames = new Set(fnRanges.map((r) => r.name).filter((n) => n !== '<top-level>'));
  const varToScript = scanAssignments(lines);
  const heredocMask = computeHeredocMask(lines);

  // Pass 2: per range, local facts (own cp evidence + own vendored-script
  // list) and the set of in-file functions it calls.
  const facts = new Map(); // name -> { copiedFiles, globDirs, hasScriptsDirCopy, calls: Set, vendored: [{name,line}] }
  for (const { name, start, end } of fnRanges) {
    const f = facts.get(name) ?? {
      copiedFiles: new Set(), globDirs: new Set(), hasScriptsDirCopy: false, calls: new Set(), vendored: [],
    };
    for (let i = start; i < end; i += 1) {
      if (heredocMask[i]) continue; // heredoc BODY text, not executed shell code
      const line = lines[i];
      const lineNo = i + 1;
      const codeLine = maskQuotedRegions(line);

      CALL_RE.lastIndex = 0;
      let callMatch;
      while ((callMatch = CALL_RE.exec(codeLine))) {
        const callee = callMatch[1];
        if (callee !== name && definedNames.has(callee)) f.calls.add(callee);
      }

      if (!/^\s*cp\s/.test(line)) continue;

      if (LIB_DIR_COPY_RE.test(line)) f.globDirs.add('lib');
      if (SCRIPTS_DIR_COPY_RE.test(line)) f.hasScriptsDirCopy = true;
      if (LIB_VAR_COPY_RE.test(line)) f.globDirs.add('lib');

      DIR_GLOB_RE.lastIndex = 0;
      let gm;
      while ((gm = DIR_GLOB_RE.exec(line))) f.globDirs.add(gm[1]);

      let cm;
      COPY_RE.lastIndex = 0;
      while ((cm = COPY_RE.exec(line))) f.copiedFiles.add(cm[1]);

      const vendoredName = vendoredSourceScriptName(line, varToScript);
      if (vendoredName) f.vendored.push({ name: vendoredName, line: lineNo });
    }
    facts.set(name, f);
  }

  // Pass 3: memoized DFS to compute EFFECTIVE coverage (own facts unioned
  // with every transitively-called function's own facts). Cycle-safe via a
  // visiting set — a call cycle just stops contributing further, never
  // loops.
  const effective = new Map();
  const visiting = new Set();
  function effectiveOf(name) {
    if (effective.has(name)) return effective.get(name);
    const f = facts.get(name);
    const result = { copiedFiles: new Set(), globDirs: new Set(), hasScriptsDirCopy: false };
    if (!f) { effective.set(name, result); return result; }
    if (visiting.has(name)) return result; // cycle guard: contribute nothing further
    visiting.add(name);
    for (const c of f.copiedFiles) result.copiedFiles.add(c);
    for (const d of f.globDirs) result.globDirs.add(d);
    result.hasScriptsDirCopy = f.hasScriptsDirCopy;
    for (const callee of f.calls) {
      const e = effectiveOf(callee);
      for (const c of e.copiedFiles) result.copiedFiles.add(c);
      for (const d of e.globDirs) result.globDirs.add(d);
      if (e.hasScriptsDirCopy) result.hasScriptsDirCopy = true;
    }
    visiting.delete(name);
    effective.set(name, result);
    return result;
  }

  for (const name of facts.keys()) {
    const f = facts.get(name);
    if (f.vendored.length === 0) continue;
    const cov = effectiveOf(name);
    for (const { name: scriptName, line } of f.vendored) {
      const scriptRel = `${scriptName}.mjs`;
      const scriptAbs = path.join(scriptsRootAbs, scriptRel);
      if (!fs.existsSync(scriptAbs)) continue; // not a real .aai/scripts file — nothing to check
      if (vendoredSites) vendoredSites.push({ file: relFile, line, fn: name, script: scriptRel });
      const deps = transitiveDeps(scriptRel, scriptsRootAbs);
      for (const dep of deps) {
        const depDir = dep.includes('/') ? dep.slice(0, dep.lastIndexOf('/')) : '';
        const globCovered = depDir !== '' && cov.globDirs.has(depDir);
        const covered = cov.hasScriptsDirCopy || cov.copiedFiles.has(dep) || globCovered;
        if (!covered) {
          violations.push({ file: relFile, line, fn: name, script: scriptRel, missing: dep });
        }
      }
    }
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.root);
  const scriptsRootAbs = path.join(root, '.aai', 'scripts');
  const testsDir = path.join(root, 'tests', 'skills');
  if (!fs.existsSync(scriptsRootAbs)) fail(`no .aai/scripts under ${root}`);
  if (!fs.existsSync(testsDir)) fail(`no tests/skills under ${root}`);

  const files = fs.readdirSync(testsDir).filter((f) => f.endsWith('.sh')).sort();
  const violations = [];
  const vendoredSites = [];
  for (const f of files) {
    const abs = path.join(testsDir, f);
    scanFile(path.join('tests', 'skills', f), abs, scriptsRootAbs, violations, vendoredSites);
  }

  if (args.json) {
    process.stdout.write(`${JSON.stringify({ violations, vendoredSites }, null, 2)}\n`);
  } else if (violations.length === 0) {
    // The site count is the checker's own coverage disclosure (validation-
    // round5 B2-R5): a CLEAN verdict is only as meaningful as the number of
    // vendoring `cp` lines it actually recognized as vendoring sites.
    process.stdout.write(`check-vendored-script-deps: CLEAN — 0 violation(s) (${vendoredSites.length} vendored engine site(s) checked)\n`);
  } else {
    process.stdout.write(`check-vendored-script-deps: ${violations.length} violation(s) (${vendoredSites.length} vendored engine site(s) checked)\n`);
    for (const v of violations) {
      process.stdout.write(
        `VIOLATION ${v.file}:${v.line} (${v.fn}) vendors ${v.script} but never copies its dependency ${v.missing}\n`
      );
    }
  }
  process.exitCode = violations.length === 0 ? 0 : 1;
}

// realOrResolve, not a bare path.resolve: a repo checked out under a
// symlinked path (this repo's own /tmp -> /private/tmp on macOS included)
// leaves process.argv[1] unresolved while import.meta.url resolves THROUGH
// it, so a plain path.resolve() comparison never matches and main() is
// silently never called — the exact shape TEST-439 pins across every
// check-*.mjs sibling (same idiom as check-cd-subshell-leak.mjs /
// check-base-ref-pins.mjs).
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main();
}
