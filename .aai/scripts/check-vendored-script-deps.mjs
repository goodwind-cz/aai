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
 *   - a `.aai/scripts/lib/*` glob (covers everything under lib/), or
 *   - a recursive `.aai/scripts` (or `.aai/scripts/lib`) directory copy.
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
 *     fixture must vendor.
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
// SOURCE_RE: a `cp` line's SOURCE naming a single TOP-LEVEL
// `.aai/scripts/<name>.mjs` file (never `.../lib/<name>.mjs` — the
// character class excludes `/`, so a `lib/...` path can never satisfy the
// final `\.mjs` requirement at this position).
const SOURCE_RE = /\$(?:PROJECT_ROOT|SRC_ROOT)"?\/?\.aai\/scripts\/([A-Za-z0-9_.-]+)\.mjs/g;
// Any specific file this function ALSO copies, lib or sibling alike.
const COPY_RE = /\.aai\/scripts\/((?:lib\/)?[A-Za-z0-9_.-]+\.mjs)/g;
// A glob or recursive directory copy that covers a whole subtree.
const LIB_GLOB_RE = /\.aai\/scripts\/lib\/\*/;
const SCRIPTS_DIR_COPY_RE = /cp\s+(?:-\w+\s+)*"?\$(?:PROJECT_ROOT|SRC_ROOT)"?\/?\.aai\/scripts"?\s/;
const LIB_DIR_COPY_RE = /cp\s+(?:-\w+\s+)*"?\$(?:PROJECT_ROOT|SRC_ROOT)"?\/?\.aai\/scripts\/lib"?\s/;

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
const CALL_RE = /(?:^|[=(]\s*|&&\s*|;\s*)"?\$?\(?\s*([A-Za-z_][A-Za-z0-9_]*)\b/g;

function scanFile(relFile, absFile, scriptsRootAbs, violations) {
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

  // Pass 2: per range, local facts (own cp evidence + own vendored-script
  // list) and the set of in-file functions it calls.
  const facts = new Map(); // name -> { copiedFiles, hasLibGlob, hasScriptsDirCopy, calls: Set, vendored: [{name,line}] }
  for (const { name, start, end } of fnRanges) {
    const f = facts.get(name) ?? {
      copiedFiles: new Set(), hasLibGlob: false, hasScriptsDirCopy: false, calls: new Set(), vendored: [],
    };
    for (let i = start; i < end; i += 1) {
      const line = lines[i];
      const lineNo = i + 1;

      CALL_RE.lastIndex = 0;
      let callMatch;
      while ((callMatch = CALL_RE.exec(line))) {
        const callee = callMatch[1];
        if (callee !== name && definedNames.has(callee)) f.calls.add(callee);
      }

      if (!/^\s*cp\s/.test(line)) continue;

      if (LIB_DIR_COPY_RE.test(line)) f.hasLibGlob = true;
      if (SCRIPTS_DIR_COPY_RE.test(line)) f.hasScriptsDirCopy = true;
      if (LIB_GLOB_RE.test(line)) f.hasLibGlob = true;

      let cm;
      COPY_RE.lastIndex = 0;
      while ((cm = COPY_RE.exec(line))) f.copiedFiles.add(cm[1]);

      SOURCE_RE.lastIndex = 0;
      let sm;
      while ((sm = SOURCE_RE.exec(line))) f.vendored.push({ name: sm[1], line: lineNo });
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
    const result = { copiedFiles: new Set(), hasLibGlob: false, hasScriptsDirCopy: false };
    if (!f) { effective.set(name, result); return result; }
    if (visiting.has(name)) return result; // cycle guard: contribute nothing further
    visiting.add(name);
    for (const c of f.copiedFiles) result.copiedFiles.add(c);
    result.hasLibGlob = f.hasLibGlob;
    result.hasScriptsDirCopy = f.hasScriptsDirCopy;
    for (const callee of f.calls) {
      const e = effectiveOf(callee);
      for (const c of e.copiedFiles) result.copiedFiles.add(c);
      if (e.hasLibGlob) result.hasLibGlob = true;
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
      const deps = transitiveDeps(scriptRel, scriptsRootAbs);
      for (const dep of deps) {
        const isLibDep = dep.startsWith('lib/');
        const covered = cov.hasScriptsDirCopy || cov.copiedFiles.has(dep) || (isLibDep && cov.hasLibGlob);
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
  for (const f of files) {
    const abs = path.join(testsDir, f);
    scanFile(path.join('tests', 'skills', f), abs, scriptsRootAbs, violations);
  }

  if (args.json) {
    process.stdout.write(`${JSON.stringify({ violations }, null, 2)}\n`);
  } else if (violations.length === 0) {
    process.stdout.write('check-vendored-script-deps: CLEAN — 0 violation(s)\n');
  } else {
    process.stdout.write(`check-vendored-script-deps: ${violations.length} violation(s)\n`);
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
