#!/usr/bin/env node
//
// select-suites.mjs — deterministic CI test-impact selection
// (CHANGE ci-test-impact-selection / SPEC spec-ci-test-impact-selection).
//
// Reads a changed-path list (from `git diff --name-only <base-ref>...HEAD`,
// or an injected file list for deterministic testing) and maps it onto
// tests/skills/ suites via tests/skills/suite-map.yaml. FAIL-OPEN by design:
// the selector never tries to be clever about a path it cannot confidently
// classify — it escalates to FULL_RUN instead of silently narrowing
// coverage. Three fail-open triggers, checked in this priority order:
//   1. protected-l3  — a changed path is listed in docs/ai/docs-audit.yaml
//                       `protected_paths_l3` (read live, never duplicated).
//   2. shared-lib     — a changed path matches suite-map.yaml
//                       `full_run_triggers.shared_lib_globs`
//                       (.aai/scripts/lib/** — fan-out no single suite glob
//                       list can safely bound).
//   3. unmapped       — a changed path matches NO suite's glob list at all.
//
// Usage:
//   node .aai/scripts/select-suites.mjs --base-ref <ref> [--repo-root <dir>]
//     [--map <path>] [--docs-audit <path>]
//   node .aai/scripts/select-suites.mjs --files-from <path|->
//     [--repo-root <dir>] [--map <path>] [--docs-audit <path>]
//
//   node .aai/scripts/select-suites.mjs --delta-base <sha> [--head <sha>]
//     [--repo-root <dir>] [--map <path>] [--docs-audit <path>]
//
// INERT CLASS (D4, post-validation-pushes-reuse-test-results): suite-map.yaml
// `inert_globs` names gitignored runtime directories. An inert path selects
// nothing and is never unmapped; precedence is protected-l3, shared-lib,
// inert, suite match, unmapped.
//
// DELTA MODE: selects over `git diff --name-only --no-renames <sha> <head>`
// (head defaults to HEAD) or refuses by name. Only paths matching
// `carry_forward_globs` or `inert_globs` are eligible. Output is either
//   DELTA base=<sha>   then CORE / SELECTED / DROPPED lines, or exactly one
//   DELTA_REFUSED reason=<not-ancestor|ineligible|full-run:<reason>|internal-error> [path=<p>]
// Exit is always 0.
//
// `--files-from` reads a newline-separated list of repo-relative changed
// paths from a file (or stdin when the value is `-`) and skips `git diff`
// entirely — the deterministic hook tests/skills/test-aai-suite-select.sh
// uses to fixture every case without needing a throwaway git repo per case.
//
// Zero dependencies (Node stdlib only, per docs/TECHNOLOGY.md). Exit code is
// ALWAYS 0 — selection must never fail the build itself; any script-internal
// error (unreadable map, bad base-ref, git failure) degrades to FULL_RUN
// with reason=internal-error rather than a non-zero exit.
//
// Output (stdout), exactly one of two shapes:
//
//   FULL_RUN reason=<protected-l3|shared-lib|unmapped|internal-error> path=<path>
//
// or, one line per always-on core suite, one per diff-matched suite, one per
// companion (suite-map.yaml `companions:`, followed transitively, each suite
// printed once), then exactly one DROPPED count line (AC-005: auditable, no
// silent truncation):
//
//   CORE <suite> reason=core
//   SELECTED <suite> reason=<path that matched it>
//   SELECTED <suite> reason=companion:<parent suite>
//   DROPPED <n>
//
// A malformed companion (no row, its own row, bad name) is a malformed map:
// FULL_RUN reason=internal-error (DELTA_REFUSED in delta mode).
//
// SHARD MODE (D1, SPEC-0206-spec-ci-test-selection-narrowing-and-sharding):
//   node .aai/scripts/select-suites.mjs --shards <N> [--repo-root <dir>]
//     [--weights <path>]
//
// Enumerates every `test-aai-*.sh` file under <repo-root>/tests/skills/ (the
// SAME rule test-framework.sh's discover_tests() uses) and assigns each to
// one of N shards by LPT (longest processing time first), reading weights
// from tests/skills/suite-weights.tsv by default. Prints:
//
//   SHARD <i> <suite> weight=<w>     one per suite; i is 1-based
//   SHARDS count=<k> suites=<total>  exactly one, last
//
// plus optional report lines that never carry suites:
//   WEIGHT_ORPHAN <name>             a weight row naming no on-disk suite
//   WEIGHTS_IGNORED reason=<...>     the whole weights file was malformed
//
// On a degrade it prints `SHARD_FALLBACK reason=<...>` and NO `SHARD` line.
// Exit is always 0, like every other mode. With no `--shards` flag, every
// existing mode is byte-for-byte unchanged.

import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { exit, runMain, ExitSignal } from './lib/cli-pipe-guard.mjs';

const SELF_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO_ROOT = resolve(SELF_DIR, '..', '..');

// ---- shard mode constants (D1, D2) ----
const SUITE_FILE_RE = /^test-aai-.*\.sh$/;
const MAX_SHARDS = 8;

function parseArgs(argv) {
  const out = {
    baseRef: null, filesFrom: null, repoRoot: null, mapPath: null, auditPath: null,
    shards: null, weightsPath: null, deltaBase: null, head: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--base-ref') out.baseRef = argv[++i];
    else if (a === '--files-from') out.filesFrom = argv[++i];
    else if (a === '--repo-root') out.repoRoot = argv[++i];
    else if (a === '--map') out.mapPath = argv[++i];
    else if (a === '--docs-audit') out.auditPath = argv[++i];
    else if (a === '--shards') out.shards = argv[++i];
    else if (a === '--weights') out.weightsPath = argv[++i];
    else if (a === '--delta-base') out.deltaBase = argv[++i];
    else if (a === '--head') out.head = argv[++i];
    // Unknown flags are ignored on purpose — a CLI usage slip must never
    // fail the build; it degrades to FULL_RUN via the normal fail-open path
    // below when it leaves required inputs missing.
  }
  return out;
}

function fullRun(reason, path) {
  console.log(`FULL_RUN reason=${reason} path=${path}`);
  exit(0);
}

function shardFallback(reason) {
  console.log(`SHARD_FALLBACK reason=${reason}`);
  exit(0);
}

// ---- shard mode (D1, D2, D3) ----

// discoverSuiteNames <repoRoot> — recursively walks <repoRoot>/tests/skills/
// for files matching SUITE_FILE_RE, mirroring discover_tests()'s
// `find "$SCRIPT_DIR" -name "test-aai-*.sh" -type f` exactly. A suite's name
// is its basename with the `test-` prefix and `.sh` suffix stripped.
function discoverSuiteNames(repoRoot) {
  const skillsDir = resolve(repoRoot, 'tests', 'skills');
  const names = [];
  function walk(dir) {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = join(dir, e.name);
      if (e.isDirectory()) {
        walk(full);
      } else if (e.isFile() && SUITE_FILE_RE.test(e.name)) {
        names.push(e.name.slice('test-'.length, -'.sh'.length));
      }
    }
  }
  walk(skillsDir);
  return names;
}

// parseShardCount <raw> — null unless raw is a decimal integer in 1..MAX_SHARDS.
function parseShardCount(raw) {
  if (typeof raw !== 'string' || !/^[1-9][0-9]*$/.test(raw)) return null;
  const n = parseInt(raw, 10);
  if (n > MAX_SHARDS) return null;
  return n;
}

// parseWeights <text> — '#' comments, blank lines, and
// '<suite><whitespace><positive integer seconds>' rows (D3). A single
// malformed line makes the WHOLE file ignored: the caller gets an empty
// map plus the offending line number, never a partial parse.
function parseWeights(text) {
  const weights = new Map();
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].replace(/\r$/, '');
    if (line.trim() === '' || /^\s*#/.test(line)) continue;
    const m = line.trim().match(/^(\S+)\s+(\S+)$/);
    if (!m || !/^[1-9][0-9]*$/.test(m[2])) {
      return { weights: new Map(), ignored: { reason: 'malformed-line', line: i + 1 } };
    }
    weights.set(m[1], parseInt(m[2], 10));
  }
  return { weights, ignored: null };
}

// byWeightDescThenName — weight descending, then name ascending (byte
// order): determinism, and longest-first inside each shard (D2).
function byWeightDescThenName(a, b) {
  return b.w - a.w || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
}

function shardMain(opts) {
  const n = parseShardCount(opts.shards);
  if (n === null) return shardFallback('invalid-shard-count');

  const names = discoverSuiteNames(opts.repoRoot);
  if (names.length === 0) return shardFallback('no-suites');

  const weightsPath = resolve(opts.repoRoot, opts.weightsPath || 'tests/skills/suite-weights.tsv');
  let weights = new Map();
  let weightsIgnoredReason = null;
  if (existsSync(weightsPath)) {
    let text = null;
    try {
      text = readFileSync(weightsPath, 'utf8');
    } catch {
      text = null;
    }
    if (text !== null) {
      const parsed = parseWeights(text);
      if (parsed.ignored) {
        weightsIgnoredReason = `malformed-line line=${parsed.ignored.line}`;
      } else {
        weights = parsed.weights;
      }
    }
  }

  const nameSet = new Set(names);
  const orphanNames = [];
  for (const k of weights.keys()) {
    if (!nameSet.has(k)) orphanNames.push(k);
  }

  const knownForSuites = names.filter((nm) => weights.has(nm)).map((nm) => weights.get(nm));
  const maxKnownWeight = knownForSuites.length ? Math.max(...knownForSuites) : 1;
  const unknownWeight = maxKnownWeight;

  const order = names
    .map((name) => ({ name, w: weights.has(name) ? weights.get(name) : unknownWeight }))
    .sort(byWeightDescThenName);

  const loads = new Array(n).fill(0);
  const buckets = Array.from({ length: n }, () => []);
  for (const o of order) {
    const target = loads.indexOf(Math.min(...loads));
    loads[target] += o.w;
    buckets[target].push(o);
  }

  for (const orphan of orphanNames.sort()) {
    console.log(`WEIGHT_ORPHAN ${orphan}`);
  }
  if (weightsIgnoredReason) {
    console.log(`WEIGHTS_IGNORED reason=${weightsIgnoredReason}`);
  }

  let emittedShards = 0;
  for (let i = 0; i < n; i++) {
    if (buckets[i].length === 0) continue;
    emittedShards++;
    for (const o of buckets[i]) {
      console.log(`SHARD ${i + 1} ${o.name} weight=${o.w}`);
    }
  }
  console.log(`SHARDS count=${emittedShards} suites=${names.length}`);
  exit(0);
}

// ---- minimal glob matcher (zero deps): '**' = any chars incl. '/', '*' =
// any chars excluding '/'. No other glob syntax is supported or needed here.
function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') {
        re += '.*';
        i++;
        if (glob[i + 1] === '/') i++; // 'dir/**/x' -> 'dir/' + .* already eats the slash
      } else {
        re += '[^/]*';
      }
    } else if ('.+^${}()|[]\\'.includes(c)) {
      re += '\\' + c;
    } else {
      re += c;
    }
  }
  return new RegExp('^' + re + '$');
}

function matchesGlob(path, glob) {
  return globToRegExp(glob).test(path);
}

// ---- suite-map.yaml parser ----
// Hand-rolled, fixed 3-level schema (core: / full_run_triggers: / suites:).
// This is NOT a general YAML parser — see the header comment in
// tests/skills/suite-map.yaml for the exact indentation contract it relies on.
function parseSuiteMap(text) {
  const core = [];
  const sharedLibGlobs = [];
  const inertGlobs = [];
  const carryGlobs = [];
  const suites = {}; // name -> { globs: [], companions: [] }, insertion-ordered

  let section = null; // 'core' | 'shared' | 'suites' | 'inert' | 'carry'
  let currentSuite = null;
  let inGlobs = false;
  let inCompanions = false;

  for (const raw of text.split('\n')) {
    const line = raw.replace(/\r$/, '');
    if (line.trim() === '' || /^\s*#/.test(line)) continue;
    const indent = line.match(/^ */)[0].length;
    const trimmed = line.trim();

    if (indent === 0) {
      if (trimmed === 'core:') { section = 'core'; currentSuite = null; inGlobs = false; continue; }
      if (trimmed === 'full_run_triggers:') { section = 'shared'; currentSuite = null; inGlobs = false; continue; }
      if (trimmed === 'suites:') { section = 'suites'; currentSuite = null; inGlobs = false; continue; }
      if (trimmed === 'inert_globs:') { section = 'inert'; currentSuite = null; inGlobs = false; continue; }
      if (trimmed === 'carry_forward_globs:') { section = 'carry'; currentSuite = null; inGlobs = false; continue; }
      section = null; currentSuite = null; inGlobs = false;
      continue;
    }

    if (section === 'core') {
      if (trimmed.startsWith('- ')) {
        const name = trimmed.slice(2).trim();
        // Same charset contract as suite keys: core names reach the workflow
        // shell via the suites output, so a non-conforming entry is treated
        // as a malformed map (fail-open), never emitted.
        if (!/^[A-Za-z0-9_-]+$/.test(name)) {
          throw new Error(`core entry violates [A-Za-z0-9_-]+: ${name.slice(0, 80)}`);
        }
        core.push(name);
      }
      continue;
    }

    if (section === 'inert' || section === 'carry') {
      if (trimmed.startsWith('- ')) (section === 'inert' ? inertGlobs : carryGlobs).push(trimmed.slice(2).trim());
      continue;
    }

    if (section === 'shared') {
      if (trimmed === 'shared_lib_globs:') { inGlobs = true; continue; }
      if (inGlobs && trimmed.startsWith('- ')) sharedLibGlobs.push(trimmed.slice(2).trim());
      continue;
    }

    if (section === 'suites') {
      if (indent === 2 && /^[A-Za-z0-9_-]+:$/.test(trimmed)) {
        currentSuite = trimmed.slice(0, -1);
        suites[currentSuite] = { globs: [], companions: [] };
        inGlobs = false;
        inCompanions = false;
        continue;
      }
      if (indent === 4 && trimmed === 'globs:' && currentSuite) {
        inGlobs = true;
        inCompanions = false;
        continue;
      }
      // D1 (nested-suite-reruns-duplicate-sweep-time): `companions:` switches the
      // row into companion mode and `globs:` switches it back, so a companion
      // item can never be read as a glob.
      // A flow-form `companions: [x]` (inline content on the key line) is not
      // supported; ignoring it would silently drop the edge, so it is a
      // malformed map and fails open like any other bad companions block.
      if (indent === 4 && /^companions:\s*[^\s#]/.test(trimmed) && currentSuite) {
        throw new Error(`inline companions not supported (use a block list): ${currentSuite}`);
      }
      if (indent === 4 && trimmed === 'companions:' && currentSuite) {
        inCompanions = true;
        inGlobs = false;
        continue;
      }
      if (indent >= 6 && currentSuite && trimmed.startsWith('- ')) {
        if (inGlobs) suites[currentSuite].globs.push(trimmed.slice(2).trim());
        else if (inCompanions) suites[currentSuite].companions.push(trimmed.slice(2).trim());
      }
    }
  }

  return { core, sharedLibGlobs, inertGlobs, carryGlobs, suites };
}

// ---- docs-audit.yaml protected_paths_l3 reader (live, never duplicated) ----
function parseProtectedPathsL3(text) {
  const lines = text.split('\n');
  const out = [];
  let inBlock = false;
  for (const raw of lines) {
    const line = raw.replace(/\r$/, '');
    if (/^protected_paths_l3:\s*$/.test(line)) { inBlock = true; continue; }
    if (!inBlock) continue;
    if (line.trim() === '' || /^\s*#/.test(line)) continue;
    if (/^\s*-\s+/.test(line)) { out.push(line.replace(/^\s*-\s+/, '').trim()); continue; }
    break; // dedent to the next top-level key ends the block
  }
  return out;
}

function getChangedFiles(opts) {
  if (opts.filesFrom) {
    let text;
    try {
      text = opts.filesFrom === '-' ? readFileSync(0, 'utf8') : readFileSync(opts.filesFrom, 'utf8');
    } catch (err) {
      fullRun('internal-error', `--files-from unreadable: ${String(err.message || err).slice(0, 200)}`);
      return [];
    }
    return text.split('\n').map((s) => s.trim()).filter(Boolean);
  }
  if (!opts.baseRef) {
    fullRun('internal-error', 'no --base-ref or --files-from supplied');
    return [];
  }
  try {
    // --no-renames (lane-gate validation RR-rename-blindness): rename detection
    // hides the source path (R100 shows only the destination), letting a
    // protected-file rename read as a benign path; delete+add keeps the old
    // path visible so protected/lib/unmapped triads still trip FULL_RUN.
    const out = execFileSync('git', ['diff', '--name-only', '--no-renames', `${opts.baseRef}...HEAD`], {
      cwd: opts.repoRoot,
      encoding: 'utf8',
    });
    return out.split('\n').map((s) => s.trim()).filter(Boolean);
  } catch (err) {
    fullRun('internal-error', `git diff --name-only --no-renames ${opts.baseRef}...HEAD failed: ${String(err.message || err).slice(0, 160)}`);
    return [];
  }
}

// loadContext <opts> — read and validate the map and the protected-L3 list.
// Returns { ctx } or { fail: <detail> }; the caller decides how a failure is
// reported (FULL_RUN internal-error in whole-PR mode, DELTA_REFUSED in delta mode).
function loadContext(opts) {
  const mapPath = resolve(opts.repoRoot, opts.mapPath || 'tests/skills/suite-map.yaml');
  const auditPath = resolve(opts.repoRoot, opts.auditPath || 'docs/ai/docs-audit.yaml');

  let mapText;
  try {
    mapText = readFileSync(mapPath, 'utf8');
  } catch {
    return { fail: `suite-map unreadable: ${mapPath}` };
  }
  let parsedMap;
  try {
    parsedMap = parseSuiteMap(mapText);
  } catch (err) {
    return { fail: `suite-map malformed: ${String(err.message || err).slice(0, 160)}` };
  }
  const { core, sharedLibGlobs, inertGlobs, carryGlobs, suites } = parsedMap;
  if (core.length === 0 || Object.keys(suites).length === 0) {
    return { fail: `suite-map empty or malformed: ${mapPath}` };
  }
  // Every core entry must name a defined suite: a misspelled/removed core
  // row would otherwise emit CORE <ghost> (workflow runs a nonexistent
  // suite) and corrupt the DROPPED arithmetic (negative count).
  for (const c of core) {
    if (!suites[c]) {
      return { fail: `core entry has no suites row: ${c}` };
    }
  }

  // Companion edges (D1): every name must be a valid, defined, non-self row.
  // A malformed edge fails open like a ghost core entry.
  for (const [name, def] of Object.entries(suites)) {
    for (const comp of def.companions) {
      if (!/^[A-Za-z0-9_-]+$/.test(comp)) {
        return { fail: `suite-map malformed: companion violates [A-Za-z0-9_-]+: ${name} -> ${comp.slice(0, 80)}` };
      }
      if (!suites[comp]) {
        return { fail: `companion has no suites row: ${name} -> ${comp}` };
      }
      if (comp === name) {
        return { fail: `companion names its own row: ${name}` };
      }
    }
  }

  let protectedL3 = [];
  if (existsSync(auditPath)) {
    try {
      protectedL3 = parseProtectedPathsL3(readFileSync(auditPath, 'utf8'));
    } catch {
      // Unreadable protected-paths config: never run with silently-zero L3
      // coverage — fall open unconditionally rather than guess.
      return { fail: `docs-audit.yaml unreadable: ${auditPath}` };
    }
  }
  return { ctx: { core, sharedLibGlobs, inertGlobs, carryGlobs, suites, protectedL3 } };
}

// classifyPaths <changed> <ctx> — pure classification of a non-empty path list.
// Returns { full: { reason, path } } or { selected: Map<suite, first path> }.
function classifyPaths(changed, ctx) {
  const { core, sharedLibGlobs, inertGlobs, suites, protectedL3 } = ctx;
  const coreSet = new Set(core);

  // Priority 1: protected L3 surfaces (exact path match — docs-audit.yaml
  // lists literal files, not globs).
  for (const path of changed) {
    if (protectedL3.includes(path)) return { full: { reason: 'protected-l3', path } };
  }

  // Priority 2: shared-lib fan-out.
  for (const path of changed) {
    for (const g of sharedLibGlobs) {
      if (matchesGlob(path, g)) return { full: { reason: 'shared-lib', path } };
    }
  }

  // Priority 3 (inert) and 4 (suite match) and 5 (unmapped). Every suite
  // (core included) is checked so a path that only touches a core suite's
  // own source is correctly treated as mapped (core already always runs) —
  // only non-core matches produce a SELECTED line.
  const selected = new Map(); // suite -> first matching path
  let firstUnmapped = null;

  for (const path of changed) {
    if (inertGlobs.some((g) => matchesGlob(path, g))) continue;
    let matchedAny = false;
    for (const [name, def] of Object.entries(suites)) {
      const globs = def.globs.concat([`tests/skills/test-${name}.sh`]);
      const suiteMatched = globs.some((g) => matchesGlob(path, g));
      if (suiteMatched) {
        matchedAny = true;
        if (!coreSet.has(name) && !selected.has(name)) selected.set(name, path);
      }
    }
    if (!matchedAny && firstUnmapped === null) firstUnmapped = path;
  }

  if (firstUnmapped !== null) return { full: { reason: 'unmapped', path: firstUnmapped } };
  return { selected };
}

// expandCompanions <selected> <ctx> — D2: the selection plus every companion,
// transitively. `queue` is seeded with the core suites, then the selected ones;
// a suite is added at most once (so a cycle terminates) with the reason
// `companion:<parent>`. Core suites always run, so they are never added.
function expandCompanions(selected, ctx) {
  const coreSet = new Set(ctx.core);
  const out = new Map(selected);
  const queue = [...ctx.core, ...selected.keys()];
  for (let i = 0; i < queue.length; i++) {
    const parent = queue[i];
    const comps = (ctx.suites[parent] && ctx.suites[parent].companions) || [];
    for (const comp of comps) {
      if (coreSet.has(comp) || out.has(comp)) continue;
      out.set(comp, 'companion:' + parent);
      queue.push(comp);
    }
  }
  return out;
}

function printSelection(ctx, pathSelected) {
  const selected = expandCompanions(pathSelected, ctx);
  for (const c of ctx.core) console.log(`CORE ${c} reason=core`);
  for (const [name, path] of selected) console.log(`SELECTED ${name} reason=${path}`);
  const dropped = Object.keys(ctx.suites).length - ctx.core.length - selected.size;
  console.log(`DROPPED ${dropped}`);
}

// ---- delta mode (D4) ----

function deltaRefuse(reason, path) {
  console.log(`DELTA_REFUSED reason=${reason}${path === undefined ? '' : ` path=${path}`}`);
  exit(0);
}

function gitResolveCommit(repoRoot, rev) {
  return execFileSync('git', ['rev-parse', '--verify', '--quiet', `${rev}^{commit}`], {
    cwd: repoRoot, encoding: 'utf8',
  }).trim();
}

// gitIsAncestor — true/false from the exit status; any other failure throws.
function gitIsAncestor(repoRoot, baseSha, headSha) {
  try {
    execFileSync('git', ['merge-base', '--is-ancestor', baseSha, headSha], { cwd: repoRoot, stdio: 'ignore' });
    return true;
  } catch (err) {
    if (err && err.status === 1) return false;
    throw err;
  }
}

function deltaMain(opts) {
  const loaded = loadContext(opts);
  if (loaded.fail) return deltaRefuse('internal-error');
  const { ctx } = loaded;

  let baseSha;
  let headSha;
  try {
    baseSha = gitResolveCommit(opts.repoRoot, opts.deltaBase);
    headSha = gitResolveCommit(opts.repoRoot, opts.head || 'HEAD');
  } catch {
    return deltaRefuse('internal-error');
  }
  let ancestor;
  try {
    ancestor = gitIsAncestor(opts.repoRoot, baseSha, headSha);
  } catch {
    return deltaRefuse('internal-error');
  }
  if (!ancestor) return deltaRefuse('not-ancestor');

  let changed;
  try {
    const out = execFileSync('git', ['diff', '--name-only', '--no-renames', baseSha, headSha], {
      cwd: opts.repoRoot, encoding: 'utf8',
    });
    changed = out.split('\n').map((x) => x.trim()).filter(Boolean);
  } catch {
    return deltaRefuse('internal-error');
  }

  const eligible = (p) => ctx.inertGlobs.some((g) => matchesGlob(p, g))
    || ctx.carryGlobs.some((g) => matchesGlob(p, g));
  for (const p of changed) {
    if (!eligible(p)) return deltaRefuse('ineligible', p);
  }

  console.log(`DELTA base=${opts.deltaBase}`);
  if (changed.length === 0) {
    printSelection(ctx, new Map());
    return;
  }
  const result = classifyPaths(changed, ctx);
  if (result.full) return deltaRefuse(`full-run:${result.full.reason}`, result.full.path);
  printSelection(ctx, result.selected);
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  opts.repoRoot = resolve(opts.repoRoot || DEFAULT_REPO_ROOT);
  if (opts.shards !== null) return shardMain(opts);
  if (opts.deltaBase !== null) return deltaMain(opts);

  const loaded = loadContext(opts);
  if (loaded.fail) return fullRun('internal-error', loaded.fail);
  const { ctx } = loaded;

  const changed = getChangedFiles(opts);

  if (changed.length === 0) {
    printSelection(ctx, new Map());
    return;
  }

  const result = classifyPaths(changed, ctx);
  if (result.full) return fullRun(result.full.reason, result.full.path);
  printSelection(ctx, result.selected);
}

runMain(() => main(), {
  onError(err) {
    try {
      if (process.argv.includes('--delta-base')) deltaRefuse('internal-error');
      fullRun('internal-error', String((err && err.message) || err).slice(0, 200));
    } catch (e) {
      if (e instanceof ExitSignal) { process.exitCode = e.code; return; }
      throw e;
    }
  },
});
