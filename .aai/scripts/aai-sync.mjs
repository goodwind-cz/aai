#!/usr/bin/env node
// aai-sync.mjs - the AAI layer sync as one Node module behind thin launchers
// (docs/specs/SPEC-DRAFT-spec-sync-on-node.md; RFC-0017 phase 5).
//
// Usage: node .aai/scripts/aai-sync.mjs <path-to-target-project> [--profile core|extended] [-h]
//
// The module holds the sync policy: arguments, the source and target roots, the refusals before any write, the
// profile and the core list. Importing it has no side effect; the main guard runs it only as the entry point. It
// never reads standard input, and all of its output goes through descriptors 1 and 2 so that its lines and the
// lines of the children it starts appear in program order.
//
// DROPPED, ON PURPOSE (D-LEGACY, DR-13): both old twins carried moves for the layout that predates .aai/ (2026-03).
// This module performs none of them and prints nothing about them. The moves removed a top-level ai/ directory, the
// scripts/ files that share a name with a shipped script (and the ones under the old product name), a root playbook file, the
// docs/ workflow, roles and templates trees, six loose files under docs/ai/ and one knowledge file. Each deleted a
// name a project may own, and every target synced since 2026-03 has already moved its files. A target that still
// holds the old layout keeps those files (the CHANGELOG names the manual cleanup). The rule this enforces: the sync
// deletes only inside the managed set (the .aai/ prune and the stale clean, the copy-replaced managed entries and the
// retired skill wrappers), under a target root it has verified again. Kept: the pointer to migrate-state-to-local,
// printed by lib/gitignore-block.mjs when it appends the runtime-state patterns.
//
// STATE OF THE PORT (run 2 of the ride): arguments, help, usage, the roots and their refusals, the profile and
// the core list are here, with the shared base resolution (lib/resolve-base.mjs) and the .gitignore reconcile
// (lib/gitignore-block.mjs, called by the step order that run 3 assembles). The copy, prune, surfaces, hooks,
// report and pin steps (D-PROFILE onward) are exported names that refuse with "not implemented yet" until their
// runs; the module is not reachable from a launcher before the launcher swap, and a run that passes every pre-write
// check ends with exit 1 and no write.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveFromBase } from './lib/resolve-base.mjs';
import { reconcileGitignore } from './lib/gitignore-block.mjs';
import { mergeHooksJson, formatSummary, formatConflicts, formatSnapshotError } from './lib/merge-hooks-json.mjs';

const EXIT_FAIL = 1;
const EXIT_USAGE = 2;
const PROFILE_NAMES = ['core', 'extended'];
const PS_NAMES = { '-targetroot': 'target', '-profile': '--profile' };
const ROOT_SHIMS = ['AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md', 'SKILLS.md'];
const SKILL_TREES = ['.claude/skills', '.agents/skills'];
const isCoreListed = (coreSet, rel) => coreSet.has(rel);
const overlapsSource = (roots) => isUnderOrSame(roots.targetReal, roots.srcReal);
const PIN_VERSION_PREFIX = '- Template version: ';
const runChild = (file, args, opts) => spawnSync(file, args, opts);
const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };

const USAGE_LINE = 'Usage: .aai/scripts/aai-sync.sh <path-to-target-project> [--profile core|extended]';
const PROFILE_NEEDS_VALUE = 'ERROR: --profile needs a value (core|extended)';

// The help text (DR-1): lines 4 to 20 of the bash reference after the comment marker is removed, then the
// PowerShell usage line and the Node requirement line. Non-ASCII characters are escapes.
const HELP_LINES = [
  'Push AAI layer FROM this repository INTO a target project.',
  '',
  'Usage (run from anywhere, script finds its own repo root):',
  '  ./.aai/scripts/aai-sync.sh <path-to-target-project> [--profile core|extended]',
  '',
  'Example:',
  '  ./.aai/scripts/aai-sync.sh ../maty-ai',
  '  ./.aai/scripts/aai-sync.sh ../maty-ai --profile core',
  '',
  'Profiles (CHANGE layer-profiles / .aai/system/PROFILES.yaml):',
  '  extended (default) \u2014 the whole vendored layer; copy behavior identical to',
  '                       the pre-profile sync (the manifest is never consulted).',
  '  core               \u2014 exactly the PROFILES.yaml `core:` list (the workflow',
  '                       engine); non-core .aai files are pruned from the',
  '                       target, target-only scripts are preserved.',
  'Resolution when --profile is absent: the target pin\'s `- Profile:` line',
  '(sticky \u2014 /aai-update re-syncs keep the installed profile), else extended.',
  '  powershell -NoProfile -File .aai/scripts/aai-sync.ps1 -TargetRoot <path> [-Profile core|extended]   # the bash form works too',
  'Requires Node.js 22 or later; both launchers run .aai/scripts/aai-sync.mjs.',
];
export const HELP_TEXT = `${HELP_LINES.join('\n')}\n`;

// --- arguments (D-CLI) ---------------------------------------------------------------------------------------

// flagKey(arg): the lookup key of a flag word: a long flag exactly, a single-dash name lower-cased (PowerShell names
// match in any case, bash flags exactly; no abbreviation).
const flagKey = (arg) => (arg.startsWith('--') ? arg : arg.toLowerCase());

const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

// isOption(word): a word this parser accepts as a flag (help, the end marker, a profile flag in either spelling,
// the PowerShell target name); after a value flag it is a missing value, never the value.
const isOption = (word) => {
  const eq = word.startsWith('--') ? word.indexOf('=') : -1;
  const k = flagKey(eq > 0 ? word.slice(0, eq) : word);
  return word === '-h' || word === '--help' || word === '--' || k === '--profile' || hasOwn(PS_NAMES, k);
};

// parseArgs(argv): arguments left to right; a later --profile wins, the target is set once. outcome is 'run',
// 'help' (-h or --help seen at that position), 'unexpected' (arg names the first argument that is not accepted or
// a second target) or 'profile-value' (a --profile or -Profile that came without a value). Parsing stops at the
// first terminal outcome. target and profile keep what was read; run decides what an empty target or an invalid
// profile means (the bash order: target presence first, then the profile value).
export function parseArgs(argv) {
  const out = { target: '', profile: '', outcome: 'run', arg: '' };
  let targetSet = false;
  let endMarker = false;
  const setTarget = (value, word) => {
    if (targetSet) {
      out.outcome = 'unexpected';
      out.arg = word;
      return false;
    }
    out.target = value;
    targetSet = value !== '';
    return true;
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (endMarker) {
      if (!setTarget(arg, arg)) return out;
      continue;
    }
    if (arg === '--') {
      endMarker = true;
      continue;
    }
    if (arg === '-h' || arg === '--help') {
      out.outcome = 'help';
      return out;
    }
    const eq = arg.startsWith('--') ? arg.indexOf('=') : -1;
    const key = flagKey(eq > 0 ? arg.slice(0, eq) : arg);
    const named = hasOwn(PS_NAMES, key) ? PS_NAMES[key] : '';
    if (key === '--profile' || named === '--profile') {
      const value = eq > 0 ? arg.slice(eq + 1) : argv[i + 1];
      if (value === undefined || value === '' || (eq < 0 && isOption(value))) {
        out.outcome = 'profile-value';
        out.arg = arg;
        return out;
      }
      out.profile = value;
      if (eq < 0) i += 1;
    } else if (named === 'target' && eq < 0) {
      const value = argv[i + 1];
      if (value === undefined || value === '' || isOption(value)) continue;
      if (!setTarget(value, arg)) return out;
      i += 1;
    } else if (arg.startsWith('-') && arg !== '-') {
      out.outcome = 'unexpected';
      out.arg = arg;
      return out;
    } else if (!setTarget(arg, arg)) {
      return out;
    }
  }
  return out;
}

// --- roots (D-ROOTS) -----------------------------------------------------------------------------------------

const statOrNull = (p) => {
  try {
    return fs.statSync(p);
  } catch {
    return null;
  }
};

const realOrResolve = (p) => {
  try {
    return fs.realpathSync(p);
  } catch {
    return path.resolve(p);
  }
};

// isUnderOrSame(child, parent): child is parent or lies below it (both real, absolute paths).
function isUnderOrSame(child, parent) {
  if (child === parent) return true;
  return child.startsWith(parent.endsWith(path.sep) ? parent : parent + path.sep);
}

const sameFile = (a, b) => a !== null && b !== null && a.dev === b.dev && a.ino === b.ino;

// sourceRoot(scriptPath): the parent of the parent of the directory of the script as the launcher passed it (a
// logical path), used only when its .aai/scripts/aai-sync.mjs names the same device and inode as the running
// module; else the root of the module's real path.
function sourceRoot(scriptPath) {
  const modulePath = fileURLToPath(import.meta.url);
  const logical = path.resolve(path.dirname(path.dirname(path.dirname(path.resolve(scriptPath)))));
  const running = statOrNull(modulePath);
  if (sameFile(statOrNull(path.join(logical, '.aai', 'scripts', 'aai-sync.mjs')), running)) return logical;
  return path.dirname(path.dirname(path.dirname(realOrResolve(modulePath))));
}

const refusal = (line) => ({ refusal: { code: EXIT_FAIL, line } });

// resolveRoots(args, io): the source and the target, captured once, or { refusal } (code and the stderr line) when
// the run must stop before any write: a missing target directory, a source without .aai (the bash lines), the target
// equal to the source or inside it (DR-5), the target a file system root (DR-6).
export function resolveRoots(args, io = {}) {
  const env = io.env ?? process.env;
  const cwd = io.cwd ?? process.cwd();
  const target = resolveFromBase(args.target, env, cwd);
  const st = statOrNull(target);
  if (st === null || !st.isDirectory()) return refusal(`ERROR: Target directory does not exist: ${args.target}`);
  const src = sourceRoot(io.scriptPath ?? process.argv[1] ?? '');
  const srcStat = statOrNull(path.join(src, '.aai'));
  if (srcStat === null || !srcStat.isDirectory()) return refusal(`ERROR: Source missing .aai/ directory: ${src}`);
  const roots = {
    src, target, srcReal: fs.realpathSync(src), targetReal: fs.realpathSync(target), targetDev: st.dev, targetIno: st.ino,
  };
  if (overlapsSource(roots)) {
    return refusal(`ERROR: target ${roots.targetReal} is the source ${roots.srcReal} or lies inside it; nothing was written.`);
  }
  if (path.parse(roots.targetReal).root === roots.targetReal) {
    return refusal(`ERROR: target ${roots.targetReal} is the root of its file system (source ${roots.srcReal}); nothing was written.`);
  }
  return roots;
}

// underRoot(roots, abs) (DR-8): true only when the real path of the parent directory of abs (the nearest existing
// ancestor for a path about to be created) lies under the target and not under the source, and the target still
// names the device and inode captured at the start.
export function underRoot(roots, abs) {
  if (!sameFile(statOrNull(roots.target), { dev: roots.targetDev, ino: roots.targetIno })) return false;
  let dir = path.dirname(path.resolve(abs));
  let real = '';
  for (;;) {
    try {
      real = fs.realpathSync(dir);
      break;
    } catch {
      const up = path.dirname(dir);
      if (up === dir) return false;
      dir = up;
    }
  }
  return isUnderOrSame(real, roots.targetReal) && !isUnderOrSame(real, roots.srcReal);
}

// refuseOutside(roots, abs): the refusal of a mutation path that fails underRoot.
function refuseOutside(roots, abs) {
  const rel = path.relative(roots.target, path.resolve(abs));
  return refusal(`ERROR: ${rel} resolves outside the target ${roots.target}; refusing to write or delete there.`);
}

// guardMutation(roots, abs): null when the path may be mutated, else the refusal; every write, rename, copy, chmod
// and delete of the later steps asks it first.
export function guardMutation(roots, abs) {
  if (!underRoot(roots, abs)) return refuseOutside(roots, abs);
  return null;
}

// --- profile and core list (D-PROFILE, the readings only) -------------------------------------------------------

// readStickyProfile(target): the profile the target's pin records: the first line starting "- Profile: " (every CR
// removed, trailing spaces and tabs removed) when it reads core or extended, else an empty string.
export function readStickyProfile(target) {
  const pin = path.join(target, '.aai', 'system', 'AAI_PIN.md');
  let text = '';
  try {
    if (!fs.statSync(pin).isFile()) return '';
    text = fs.readFileSync(pin, 'utf8');
  } catch {
    return '';
  }
  for (const line of text.replace(/\r/g, '').split('\n')) {
    if (line.startsWith('- Profile: ')) {
      const value = line.slice('- Profile: '.length).replace(/[ \t]+$/, '');
      return PROFILE_NAMES.includes(value) ? value : '';
    }
  }
  return '';
}

// parseCoreList(text): the entries of the manifest's core block (DR-10): the block opens at the line "core:"
// exactly, closes at the next line that starts with a character other than a space, and its entries are the lines
// starting with two spaces, a dash and a space, trailing spaces, tabs and CR removed; empty entries are dropped.
export function parseCoreList(text) {
  const entries = [];
  let inBlock = false;
  for (const line of text.split('\n')) {
    if (line === 'core:') {
      inBlock = true;
      continue;
    }
    if (line !== '' && line[0] !== ' ') inBlock = false;
    if (inBlock && line.startsWith('  - ')) {
      const entry = line.slice(4).replace(/[ \t\r]+$/, '');
      if (entry !== '') entries.push(entry);
    }
  }
  return entries;
}

// --- steps of later runs (exported names, refusing until their run) -----------------------------------------------

const notYet = (name, run) => () => {
  throw new Error(`${name} is not implemented yet (run ${run} of the ride)`);
};
export const planCore = notYet('planCore', 3);
export const planPrune = notYet('planPrune', 3);
export const copyReplace = notYet('copyReplace', 3);
export const isRetiredSkillWrapper = notYet('isRetiredSkillWrapper', 3);
export const copilotShimIsShipped = notYet('copilotShimIsShipped', 4);
export const extractCopilotOverrides = notYet('extractCopilotOverrides', 4);
export const renderAdvisory = notYet('renderAdvisory', 4);
export const renderPin = notYet('renderPin', 4);

// --- run -----------------------------------------------------------------------------------------------------------

// runSteps(argv, io): the checks in the bash order, each before any write. Returns the exit code.
async function runSteps(argv, io) {
  const out = io.out ?? writeFd(1);
  const err = io.err ?? writeFd(2);
  const args = parseArgs(argv);
  if (args.outcome === 'help') {
    out(HELP_TEXT);
    return 0;
  }
  if (args.outcome === 'unexpected') {
    err(`ERROR: unexpected argument: ${args.arg}\n${USAGE_LINE}\n`);
    return EXIT_USAGE;
  }
  if (args.outcome === 'profile-value') {
    err(`${PROFILE_NEEDS_VALUE}\n${USAGE_LINE}\n`);
    return EXIT_USAGE;
  }
  if (args.target === '') {
    err(`${USAGE_LINE}\n`);
    return EXIT_USAGE;
  }
  if (args.profile !== '' && !PROFILE_NAMES.includes(args.profile)) {
    err(`ERROR: invalid --profile value: ${args.profile} (allowed: core|extended)\n${USAGE_LINE}\n`);
    return EXIT_USAGE;
  }
  const roots = resolveRoots(args, io);
  if (roots.refusal) {
    err(`${roots.refusal.line}\n`);
    return roots.refusal.code;
  }
  const profile = args.profile || readStickyProfile(roots.targetReal) || 'extended';
  out(`Syncing AAI from: ${roots.src}\nTarget project:     ${roots.target}\nProfile:            ${profile}\n`);
  if (profile === 'core') {
    const manifest = path.join(roots.src, '.aai', 'system', 'PROFILES.yaml');
    const st = statOrNull(manifest);
    if (st === null || !st.isFile()) {
      err(`ERROR: --profile core requires the manifest: ${manifest}\n`);
      return EXIT_FAIL;
    }
    if (parseCoreList(fs.readFileSync(manifest, 'utf8')).length === 0) {
      err(`ERROR: no core entries found in ${manifest}\n`);
      return EXIT_FAIL;
    }
  }
  err('aai-sync: internal error: the copy, prune and report steps are not implemented yet (run 3 of the ride); no file was changed.\n');
  return EXIT_FAIL;
}

// run(argv, io): resolves to the exit code. io holds out and err (string sinks), env, cwd, spawn, now, platform and
// scriptPath; each defaults to the real thing. Every child process (git only) goes through io.spawn with io.env.
export async function run(argv, io = {}) {
  const err = io.err ?? writeFd(2);
  try {
    return await runSteps(argv, { ...io, spawn: io.spawn ?? runChild });
  } catch (e) {
    err(`aai-sync: internal error: ${e.message}\n`);
    return EXIT_FAIL;
  }
}

export async function main(argv = process.argv.slice(2)) {
  process.exitCode = await run(argv);
}

// The main guard resolves both sides through realpath (a symlinked checkout still runs main), falling back to a plain resolve.
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) main();
