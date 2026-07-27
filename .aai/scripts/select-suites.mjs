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
// or, one line per always-on core suite, one per diff-matched suite, then
// exactly one DROPPED count line (AC-005: auditable, no silent truncation):
//
//   CORE <suite> reason=core
//   SELECTED <suite> reason=<path that matched it>
//   DROPPED <n>

import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SELF_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO_ROOT = resolve(SELF_DIR, '..', '..');

function parseArgs(argv) {
  const out = { baseRef: null, filesFrom: null, repoRoot: null, mapPath: null, auditPath: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--base-ref') out.baseRef = argv[++i];
    else if (a === '--files-from') out.filesFrom = argv[++i];
    else if (a === '--repo-root') out.repoRoot = argv[++i];
    else if (a === '--map') out.mapPath = argv[++i];
    else if (a === '--docs-audit') out.auditPath = argv[++i];
    // Unknown flags are ignored on purpose — a CLI usage slip must never
    // fail the build; it degrades to FULL_RUN via the normal fail-open path
    // below when it leaves required inputs missing.
  }
  return out;
}

function fullRun(reason, path) {
  console.log(`FULL_RUN reason=${reason} path=${path}`);
  process.exit(0);
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
  const suites = {}; // name -> { globs: [] }, insertion-ordered

  let section = null; // 'core' | 'shared' | 'suites'
  let currentSuite = null;
  let inGlobs = false;

  for (const raw of text.split('\n')) {
    const line = raw.replace(/\r$/, '');
    if (line.trim() === '' || /^\s*#/.test(line)) continue;
    const indent = line.match(/^ */)[0].length;
    const trimmed = line.trim();

    if (indent === 0) {
      if (trimmed === 'core:') { section = 'core'; currentSuite = null; inGlobs = false; continue; }
      if (trimmed === 'full_run_triggers:') { section = 'shared'; currentSuite = null; inGlobs = false; continue; }
      if (trimmed === 'suites:') { section = 'suites'; currentSuite = null; inGlobs = false; continue; }
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

    if (section === 'shared') {
      if (trimmed === 'shared_lib_globs:') { inGlobs = true; continue; }
      if (inGlobs && trimmed.startsWith('- ')) sharedLibGlobs.push(trimmed.slice(2).trim());
      continue;
    }

    if (section === 'suites') {
      if (indent === 2 && /^[A-Za-z0-9_-]+:$/.test(trimmed)) {
        currentSuite = trimmed.slice(0, -1);
        suites[currentSuite] = { globs: [] };
        inGlobs = false;
        continue;
      }
      if (indent === 4 && trimmed === 'globs:' && currentSuite) {
        inGlobs = true;
        continue;
      }
      if (indent >= 6 && inGlobs && currentSuite && trimmed.startsWith('- ')) {
        suites[currentSuite].globs.push(trimmed.slice(2).trim());
      }
    }
  }

  return { core, sharedLibGlobs, suites };
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
    const out = execFileSync('git', ['diff', '--name-only', `${opts.baseRef}...HEAD`], {
      cwd: opts.repoRoot,
      encoding: 'utf8',
    });
    return out.split('\n').map((s) => s.trim()).filter(Boolean);
  } catch (err) {
    fullRun('internal-error', `git diff --name-only ${opts.baseRef}...HEAD failed: ${String(err.message || err).slice(0, 160)}`);
    return [];
  }
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  opts.repoRoot = resolve(opts.repoRoot || DEFAULT_REPO_ROOT);
  const mapPath = resolve(opts.repoRoot, opts.mapPath || 'tests/skills/suite-map.yaml');
  const auditPath = resolve(opts.repoRoot, opts.auditPath || 'docs/ai/docs-audit.yaml');

  let mapText;
  try {
    mapText = readFileSync(mapPath, 'utf8');
  } catch {
    return fullRun('internal-error', `suite-map unreadable: ${mapPath}`);
  }
  let parsedMap;
  try {
    parsedMap = parseSuiteMap(mapText);
  } catch (err) {
    return fullRun('internal-error', `suite-map malformed: ${String(err.message || err).slice(0, 160)}`);
  }
  const { core, sharedLibGlobs, suites } = parsedMap;
  if (core.length === 0 || Object.keys(suites).length === 0) {
    return fullRun('internal-error', `suite-map empty or malformed: ${mapPath}`);
  }

  let protectedL3 = [];
  if (existsSync(auditPath)) {
    try {
      protectedL3 = parseProtectedPathsL3(readFileSync(auditPath, 'utf8'));
    } catch {
      // Unreadable protected-paths config: never run with silently-zero L3
      // coverage — fall open unconditionally rather than guess.
      return fullRun('internal-error', `docs-audit.yaml unreadable: ${auditPath}`);
    }
  }

  const changed = getChangedFiles(opts);
  const coreSet = new Set(core);

  if (changed.length === 0) {
    for (const c of core) console.log(`CORE ${c} reason=core`);
    console.log(`DROPPED ${Object.keys(suites).length - core.length}`);
    return;
  }

  // Priority 1: protected L3 surfaces (exact path match — docs-audit.yaml
  // lists literal files, not globs).
  for (const path of changed) {
    if (protectedL3.includes(path)) return fullRun('protected-l3', path);
  }

  // Priority 2: shared-lib fan-out.
  for (const path of changed) {
    for (const g of sharedLibGlobs) {
      if (matchesGlob(path, g)) return fullRun('shared-lib', path);
    }
  }

  // Priority 3: per-path suite matching + unmapped detection. Every suite
  // (core included) is checked so a path that only touches a core suite's
  // own source is correctly treated as mapped (core already always runs) —
  // only non-core matches produce a SELECTED line.
  const selected = new Map(); // suite -> first matching path
  let firstUnmapped = null;

  for (const path of changed) {
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

  if (firstUnmapped !== null) return fullRun('unmapped', firstUnmapped);

  for (const c of core) console.log(`CORE ${c} reason=core`);
  for (const [name, path] of selected) console.log(`SELECTED ${name} reason=${path}`);
  const dropped = Object.keys(suites).length - core.length - selected.size;
  console.log(`DROPPED ${dropped}`);
}

try {
  main();
} catch (err) {
  fullRun('internal-error', String((err && err.message) || err).slice(0, 200));
}
