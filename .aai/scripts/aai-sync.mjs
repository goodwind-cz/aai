#!/usr/bin/env node
// aai-sync.mjs - the AAI layer sync as one Node module behind thin launchers
// (docs/specs/SPEC-0310-spec-sync-on-node.md; RFC-0017 phase 5).
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
// STATE OF THE PORT (run 4 of the ride): the module completes a whole sync: arguments, help, usage, the roots and their
// refusals (DR-5 to DR-8), the profile and the core list, the core copy and prune, the extended copy, the skill trees, the
// indexes, the knowledge files, the seeds and the root shims, the Copilot shim and the session hooks (the registration merge
// runs in process), the .gitignore reconcile, the advisory report and the pin, in the step order of the bash twin. The module
// is not reachable from a launcher before the launcher swap.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveFromBase } from './lib/resolve-base.mjs';
import { sameFile } from './lib/resolve-base.mjs';
import { reconcileGitignore } from './lib/gitignore-block.mjs';
import { mergeHooksJson, formatSummary, formatConflicts, formatSnapshotError } from './lib/merge-hooks-json.mjs';

const EXIT_FAIL = 1;
const EXIT_USAGE = 2;
const PROFILE_NAMES = ['core', 'extended'];
const PS_NAMES = { '-targetroot': 'target', '-profile': '--profile' };
const ROOT_SHIMS = ['AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md', 'SKILLS.md'];
const SKILL_TREES = ['.claude/skills', '.agents/skills'];
const isCoreListed = (coreSet, rel) => coreSet.has(rel);
// Identity, not spelling (DR-32): a file system may be case-insensitive, so one directory has many spellings. The
// roots are compared by their canonical (native) real paths and, in addition, by device and inode up the ancestors.
// The identities are bigint stats (DR-35); an identity that is unknown (a zero inode) is compared by real path spelling.
const ancestorIsFile = (start, other) => {
  const stat = statOrNull(other);
  if (stat === null) return false;
  let dir = start;
  for (;;) {
    if (sameFile(statOrNull(dir), stat, dir, other)) return true;
    const up = path.dirname(dir);
    if (up === dir) return false;
    dir = up;
  }
};
const overlapsSource = (roots) => isUnderOrSame(roots.targetReal, roots.srcReal);
const targetInSource = (roots) => [overlapsSource(roots), ancestorIsFile(roots.targetReal, roots.srcReal)].some(Boolean);
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
    return fs.statSync(p, { bigint: true });
  } catch {
    return null;
  }
};

// realNative(p): the real path in the file system's own spelling; realpathSync.native may be unavailable or refuse a path
// (a Windows volume without it), so a throw falls back to realpathSync, which throws only when the path cannot be resolved (DR-35).
const realNative = (p) => {
  try {
    return fs.realpathSync.native(p);
  } catch {
    return fs.realpathSync(p);
  }
};

const realOrResolve = (p) => {
  try {
    return realNative(p);
  } catch {
    return path.resolve(p);
  }
};

// isUnderOrSame(child, parent): child is parent or lies below it (both real, absolute paths).
function isUnderOrSame(child, parent) {
  if (child === parent) return true;
  return child.startsWith(parent.endsWith(path.sep) ? parent : parent + path.sep);
}

// sourceRoot(scriptPath): the parent of the parent of the directory of the script as the launcher passed it (a
// logical path), used only when its .aai/scripts/aai-sync.mjs names the same device and inode as the running
// module; else the root of the module's real path.
function sourceRoot(scriptPath) {
  const modulePath = fileURLToPath(import.meta.url);
  const logical = path.resolve(path.dirname(path.dirname(path.dirname(path.resolve(scriptPath)))));
  const running = statOrNull(modulePath);
  const logicalModule = path.join(logical, '.aai', 'scripts', 'aai-sync.mjs');
  if (sameFile(statOrNull(logicalModule), running, logicalModule, modulePath)) return logical;
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
    src, target, srcReal: realNative(src), targetReal: realNative(target), targetDev: st.dev, targetIno: st.ino,
  };
  if (targetInSource(roots)) {
    return refusal(`ERROR: target ${roots.targetReal} is the source ${roots.srcReal} or lies inside it; nothing was written.`);
  }
  if (path.parse(roots.targetReal).root === roots.targetReal) {
    return refusal(`ERROR: target ${roots.targetReal} is the root of its file system (source ${roots.srcReal}); nothing was written.`);
  }
  const linked = managedLinkRefusal(roots);
  if (linked !== null) return linked;
  const nested = sourceInManagedRefusal(roots);
  if (nested !== null) return nested;
  return roots;
}

// The managed top-level paths of a target (DR-7, and the .gitignore the runs append to, DR-29): none of them may be a link that leaves
// the target or enters the source.
const MANAGED_TOP = ['.aai', '.agents', '.agents/skills', '.claude', '.claude/skills', '.claude-plugin', '.codex', '.codex/skills', '.cursor',
  '.gemini', '.gemini/skills', '.github', 'docs', 'docs/ai', 'docs/knowledge', 'hooks', '.gitignore'];

// sourceInManagedRefusal(roots) (DR-33): the refusal when the source (and with it the running engine) lies inside a
// managed entry of the target, which a run deletes or replaces wholesale; else null. Identity walk over the source's
// ancestors, so the spelling and the case of the paths do not matter. Reads only.
function sourceInManagedRefusal(roots) {
  for (const rel of MANAGED_TOP) {
    if (rel === 'docs' || rel === 'docs/ai' || rel === '.gitignore') continue;
    const managed = path.join(roots.target, rel);
    const st = statOrNull(managed);
    if (st !== null && st.isDirectory() && ancestorIsFile(roots.srcReal, managed)) {
      return refusal(`ERROR: the source ${roots.srcReal} lies inside ${rel} of the target ${roots.target}, which the sync replaces; nothing was written.`);
    }
  }
  return null;
}

// managedLinkRefusal(roots): the refusal for the first managed top-level path that is a symbolic link whose real path
// (the link text resolved when it dangles) lies outside the target or inside the source, else null. Reads only.
function managedLinkRefusal(roots) {
  for (const rel of MANAGED_TOP) {
    const abs = path.join(roots.target, rel);
    let st = null;
    try {
      st = fs.lstatSync(abs);
    } catch {
      continue;
    }
    if (!st.isSymbolicLink()) continue;
    let real = '';
    try {
      real = realNative(abs);
    } catch {
      real = path.resolve(path.dirname(abs), fs.readlinkSync(abs));
    }
    if (!isUnderOrSame(real, roots.targetReal) || isUnderOrSame(real, roots.srcReal)) {
      return refusal(`ERROR: ${rel} in the target ${roots.target} is a symbolic link to ${real}, which lies outside the target or inside the source ${roots.srcReal}; nothing was written.`);
    }
  }
  return null;
}

// targetUnchanged(roots): the target still names the device and inode captured at the start; an identity that was unknown (a zero
// inode) is judged by the real path spelling captured at the start (DR-35).
const targetUnchanged = (roots) => sameFile(statOrNull(roots.target), { dev: roots.targetDev, ino: roots.targetIno }, roots.target, roots.targetReal);

// underRoot(roots, abs) (DR-8): true only when the real path of the parent directory of abs (the nearest existing
// ancestor for a path about to be created) lies under the target and not under the source, and the target still
// names the device and inode captured at the start.
export function underRoot(roots, abs) {
  if (!targetUnchanged(roots)) return false;
  let dir = path.dirname(path.resolve(abs));
  let real = '';
  for (;;) {
    try {
      real = realNative(dir);
      break;
    } catch {
      const up = path.dirname(dir);
      if (up === dir) return false;
      dir = up;
    }
  }
  return isUnderOrSame(real, roots.targetReal) && !isUnderOrSame(real, roots.srcReal) && !ancestorIsFile(real, roots.srcReal);
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
// A CR before the line feed ends the line and is no part of it (DR-34): a Windows checkout (core.autocrlf) holds the
// manifest with CRLF, and the PowerShell twin read it line by line without the CR.
export function parseCoreList(text) {
  const entries = [];
  let inBlock = false;
  for (const raw of text.split('\n')) {
    const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
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

// --- the file system helpers of the steps ---------------------------------------------------------------------------

// SyncRefusal: a mutation that fails its guard or a target whose identity changed; run() prints its line on stderr and
// resolves to its code.
export class SyncRefusal extends Error {
  constructor(line, code = EXIT_FAIL) {
    super(line);
    this.code = code;
    this.refusal = { code, line };
  }
}

const lstatOrNull = (p) => {
  try {
    return fs.lstatSync(p);
  } catch {
    return null;
  }
};
const isDir = (p) => statOrNull(p)?.isDirectory() === true;
const isFile = (p) => statOrNull(p)?.isFile() === true;
const exists = (p) => lstatOrNull(p) !== null;

// globNames(dir): the entries a shell glob of dir/* names (dotfiles are not matched), in the byte order of the C locale. An entry
// that does not exist once its link is followed (a dangling link) is skipped, the bash `[[ -e ]]` test of every glob loop (DR-27).
function globNames(dir) {
  try {
    return fs.readdirSync(dir).filter((n) => !n.startsWith('.') && fs.existsSync(path.join(dir, n))).sort();
  } catch {
    return [];
  }
}

// mustGuard(roots, abs): every mutation asks the guard first; a refusal ends the run.
function mustGuard(roots, abs) {
  const refused = guardMutation(roots, abs);
  if (refused !== null) throw new SyncRefusal(refused.refusal.line, refused.refusal.code);
}

// reverifyTarget(roots): null while the target still names the device and inode captured at the start, else the refusal.
// Read again before each delete phase (the core prune, the stale clean, the retired-wrapper removal).
export function reverifyTarget(roots) {
  if (!targetUnchanged(roots)) return refuseOutside(roots, path.join(roots.target, '.aai'));
  return null;
}

function mustReverify(roots) {
  const refused = reverifyTarget(roots);
  if (refused !== null) throw new SyncRefusal(refused.refusal.line, refused.refusal.code);
}

// makeDir(roots, dir): mkdir -p under the guard.
function makeDir(roots, dir) {
  mustGuard(roots, dir);
  fs.mkdirSync(dir, { recursive: true });
}

// copyTree(src, dst): the copy of cp -a for the entry kinds a layer holds: a file keeps its mode and timestamps, a directory is
// created, filled and then given its source mode and timestamps, a link (dangling or not) is copied as a link with its text and
// never followed. fs.cpSync is not used: Node 22 reads a dangling top-level link through stat and fails on it (DR-15).
function copyTree(src, dst) {
  const st = fs.lstatSync(src);
  if (st.isSymbolicLink()) {
    fs.symlinkSync(fs.readlinkSync(src), dst);
  } else if (st.isDirectory()) {
    fs.mkdirSync(dst);
    for (const name of fs.readdirSync(src)) copyTree(path.join(src, name), path.join(dst, name));
    fs.chmodSync(dst, st.mode & 0o7777);
    fs.utimesSync(dst, st.atime, st.mtime);
  } else if (st.isFile()) {
    fs.copyFileSync(src, dst, fs.constants.COPYFILE_EXCL);
    fs.chmodSync(dst, st.mode & 0o7777);
    fs.utimesSync(dst, st.atime, st.mtime);
  } else {
    throw new Error(`cannot copy ${src}: it is not a file, a directory or a link`);
  }
}

// copyReplace(src, dst, roots): the destination (a file, a tree or a link, never followed) is removed, then the source is
// copied with its modes, timestamps and links (a dangling link as a link). The guard runs first.
export function copyReplace(src, dst, roots) {
  mustGuard(roots, dst);
  fs.rmSync(dst, { recursive: true, force: true });
  copyTree(src, dst);
}

// fileDiffers(src, dst): the bash twin's byte compare: different when either is not a regular file or the bytes differ;
// a read that fails counts as not different (fail closed: a hiccup cannot make the sync rewrite a target).
function fileDiffers(src, dst) {
  if (!isFile(src) || !isFile(dst)) return true;
  try {
    return !fs.readFileSync(src).equals(fs.readFileSync(dst));
  } catch {
    return false;
  }
}

// regularFiles(root): the root-relative forward-slash paths of every regular file under root (links not followed).
function regularFiles(root) {
  const found = [];
  const walk = (dir, rel) => {
    let names = [];
    try {
      names = fs.readdirSync(dir);
    } catch {
      return;
    }
    for (const name of names) {
      const full = path.join(dir, name);
      const r = rel === '' ? name : `${rel}/${name}`;
      const st = lstatOrNull(full);
      if (st === null) continue;
      if (st.isDirectory()) walk(full, r);
      else if (st.isFile()) found.push(r);
    }
  };
  walk(root, '');
  return found.sort();
}

// dirDiffers(src, dst): different when either is not a directory, the relative file lists differ or one file differs.
function dirDiffers(src, dst) {
  if (!isDir(src) || !isDir(dst)) return true;
  const a = regularFiles(src);
  const b = regularFiles(dst);
  if (a.length !== b.length || a.some((f, i) => f !== b[i])) return true;
  return a.some((f) => {
    try {
      return !fs.readFileSync(path.join(src, f)).equals(fs.readFileSync(path.join(dst, f)));
    } catch {
      return false;
    }
  });
}

// --- profile and core list: the plans (D-PROFILE) -----------------------------------------------------------------------

// planCore(entries, srcRoot): each core entry in order, present when the source holds a regular file at that path.
export function planCore(entries, srcRoot) {
  return entries.map((rel) => ({ rel, present: isFile(path.join(srcRoot, rel)) }));
}

// planPrune(files, coreSet, srcHas) (pure): the target's .aai files (relative, forward-slash, files and links only) that the
// core profile removes or preserves, in the order given. A file under .aai/cache/ or in the core set is no candidate; a script
// the source does not have is preserved. An empty or non-Set core set is a hard failure: it would nominate every file.
export function planPrune(files, coreSet, srcHas) {
  if (!(coreSet instanceof Set) || coreSet.size === 0) throw new Error('planPrune refused an empty core set: the prune would delete every file under .aai');
  const plan = [];
  for (const rel of files) {
    if (rel.startsWith('.aai/cache/')) continue;
    if (isCoreListed(coreSet, rel)) continue;
    if (rel.startsWith('.aai/scripts/') && !srcHas(rel)) plan.push({ rel, action: 'preserve' });
    else plan.push({ rel, action: 'prune' });
  }
  return plan;
}

// aaiFiles(target): every regular file and link under <target>/.aai in one byte order of the whole relative path (DR-26: the bash
// find order is undefined; a directory is never listed, a link is listed and never followed; the cache is not walked).
function aaiFiles(target) {
  const found = [];
  const walk = (dir, rel) => {
    let names = [];
    try {
      names = fs.readdirSync(dir).sort();
    } catch {
      return;
    }
    for (const name of names) {
      const r = `${rel}/${name}`;
      if (r === '.aai/cache') continue;
      const st = lstatOrNull(path.join(dir, name));
      if (st === null) continue;
      if (st.isDirectory()) walk(path.join(dir, name), r);
      else found.push(r);
    }
  };
  walk(path.join(target, '.aai'), '.aai');
  return found.sort();
}

// removeEmptyDirs(ctx): directories under .aai left empty, deepest first; .aai itself and .aai/cache are never removed.
function removeEmptyDirs(ctx) {
  const { roots } = ctx;
  const cache = path.join(roots.target, '.aai', 'cache');
  const root = path.join(roots.target, '.aai');
  const walk = (dir) => {
    let names = [];
    try {
      names = fs.readdirSync(dir).sort();
    } catch {
      return;
    }
    for (const name of names) {
      const full = path.join(dir, name);
      if (lstatOrNull(full)?.isDirectory()) walk(full);
    }
    if (dir === root || dir === cache) return;
    if (fs.readdirSync(dir).length === 0) {
      mustGuard(roots, dir);
      fs.rmdirSync(dir);
    }
  };
  walk(root);
}

// --- the steps (the twin's order) ------------------------------------------------------------------------------------

const DIRS_UP_FRONT = ['.aai/workflow', '.aai/roles', '.aai/templates', '.aai/scripts', '.aai/system', '.aai/knowledge', '.agents/skills', '.claude/skills',
  '.claude-plugin', '.codex/skills', '.codex/skills.local', '.cursor/rules', '.gemini/skills', '.gemini/skills.local', '.github', 'docs/knowledge', 'docs/ai', 'hooks'];

const conflictOf = (ctx, rel, text) => ctx.conflicts.push({ path: rel, text });

function stepCore(ctx) {
  const { roots, out, src } = ctx;
  out('  PROFILE core: filtered .aai copy per .aai/system/PROFILES.yaml\n');
  for (const entry of planCore(ctx.coreEntries, src)) {
    if (!entry.present) {
      out(`  WARN core-listed file missing in source (skipped): ${entry.rel}\n`);
      continue;
    }
    const dst = path.join(roots.target, entry.rel);
    mustGuard(roots, dst);
    makeDir(roots, path.dirname(dst));
    copyReplace(path.join(src, entry.rel), dst, roots);
  }
  mustReverify(roots);
  const plan = planPrune(aaiFiles(roots.target), ctx.coreSet, (rel) => fs.existsSync(path.join(src, rel)));
  for (const item of plan) {
    if (item.action === 'preserve') {
      out(`  PRESERVE target-only script: ${item.rel}\n`);
      continue;
    }
    const abs = path.join(roots.target, item.rel);
    mustGuard(roots, abs);
    fs.rmSync(abs, { force: true });
    ctx.deletions.push(item.rel);
    out(`  PROFILE prune (not in core): ${item.rel}\n`);
  }
  removeEmptyDirs(ctx);
}

function stepExtended(ctx) {
  const { roots, out, src } = ctx;
  const aaiSrc = path.join(src, '.aai');
  const aaiDst = path.join(roots.target, '.aai');
  for (const name of globNames(aaiSrc)) {
    if (name === 'scripts' || name === 'cache') continue;
    copyReplace(path.join(aaiSrc, name), path.join(aaiDst, name), roots);
  }
  mustReverify(roots);
  for (const name of globNames(aaiDst)) {
    if (name === 'scripts' || name === 'cache') continue;
    if (!fs.existsSync(path.join(aaiSrc, name))) {
      mustGuard(roots, path.join(aaiDst, name));
      fs.rmSync(path.join(aaiDst, name), { recursive: true, force: true });
      ctx.deletions.push(`.aai/${name}`);
      out(`  CLEAN removed stale: .aai/${name}\n`);
    }
  }
  makeDir(roots, path.join(aaiDst, 'scripts'));
  for (const name of globNames(path.join(aaiSrc, 'scripts'))) copyReplace(path.join(aaiSrc, 'scripts', name), path.join(aaiDst, 'scripts', name), roots);
  for (const name of globNames(path.join(aaiDst, 'scripts'))) {
    if (!fs.existsSync(path.join(aaiSrc, 'scripts', name))) out(`  PRESERVE target-only script: .aai/scripts/${name}\n`);
  }
}

// isRetiredSkillWrapper(entry, name, srcRoot): true only for a template skill wrapper the source no longer ships: a
// name that is aai-[a-z0-9-]+ and not aai-project-* (checked before any file system call), a real directory whose only entry is a
// regular file named SKILL.md byte for byte of 1 to 65536 bytes without NUL, and whose text (every CR removed, read one
// character per byte) is exactly the frontmatter, the optional SUBAGENT-STOP block and the two delegation lines naming a
// prompt that srcRoot/.aai does not ship.
export function isRetiredSkillWrapper(entry, name, srcRoot) {
  if (!/^aai-[a-z0-9-]+$/.test(name) || name.startsWith('aai-project-')) return false;
  const st = lstatOrNull(entry);
  if (st === null || !st.isDirectory()) return false;
  let names = [];
  try {
    names = fs.readdirSync(entry);
  } catch {
    return false;
  }
  if (names.length !== 1 || names[0] !== 'SKILL.md') return false;
  const file = path.join(entry, 'SKILL.md');
  const fst = lstatOrNull(file);
  if (fst === null || !fst.isFile() || fst.size < 1 || fst.size > 65536) return false;
  let bytes = null;
  try {
    bytes = fs.readFileSync(file);
  } catch {
    return false;
  }
  if (bytes.includes(0)) return false;
  const prompt = wrapperPrompt(bytes.toString('latin1').replace(/\r/g, ''), name);
  return prompt !== '' && !fs.existsSync(path.join(srcRoot, '.aai', `SKILL_${prompt}.prompt.md`));
}

// The em dash of the expected line is read as its three UTF-8 bytes, one latin1 character each.
const WRAPPER_DASH = Buffer.from('\u2014', 'utf8').toString('latin1');

// wrapperPrompt(text, name): the prompt name a wrapper text delegates to, or '' when the text is not exactly a wrapper.
function wrapperPrompt(text, name) {
  const lines = text.replace(/\n+$/, '').split('\n');
  let n = lines.length;
  while (n > 0 && /^[ \t]*$/.test(lines[n - 1])) n -= 1;
  if (lines[0] !== '---') return '';
  let close = -1;
  for (let i = 1; i < n; i += 1) {
    if (lines[i] === '---') {
      close = i;
      break;
    }
  }
  if (close < 0) return '';
  let named = false;
  for (let i = 1; i < close; i += 1) if (lines[i] === `name: ${name}`) named = true;
  if (!named) return '';
  const body = [];
  for (let i = close + 1; i < n; i += 1) if (!/^[ \t]*$/.test(lines[i])) body.push(lines[i]);
  let k = 0;
  if (body[0] === '<SUBAGENT-STOP>') {
    k = 1;
    let j = k;
    let found = false;
    while (j < body.length) {
      if (body[j] === '</SUBAGENT-STOP>') {
        found = true;
        break;
      }
      j += 1;
    }
    if (!found || j === k) return '';
    k = j + 1;
  }
  if (body.length - k !== 2) return '';
  const pre = 'Read the file `.aai/SKILL_';
  if (!body[k].startsWith(pre)) return '';
  let rest = body[k].slice(pre.length);
  const e = rest.indexOf('.prompt.md`');
  if (e < 0) return '';
  const x = rest.slice(0, e);
  if (!/^[A-Z0-9_]+$/.test(x)) return '';
  rest = rest.slice(e + '.prompt.md`'.length);
  const mid = ' from the current project root and follow its instructions exactly';
  if (!rest.startsWith(mid)) return '';
  rest = rest.slice(mid.length);
  if (!rest.includes(' Invoke this as `') || rest.includes('.aai/') || !body[k].endsWith('.')) return '';
  const want = `If \`.aai/SKILL_${x}.prompt.md\` does not exist, say: "SKILL_${x} not found ${WRAPPER_DASH} are you in an AAI project? Expected: .aai/SKILL_${x}.prompt.md"`;
  return body[k + 1] === want ? x : '';
}

// removeRetiredWrappers(ctx, tree): the target's entries of the tree that are provably retired wrappers go; each removal is
// recorded; a failed removal prints the WARN line and is not recorded.
function removeRetiredWrappers(ctx, tree) {
  const { roots, out, src } = ctx;
  const dstTree = path.join(roots.target, tree);
  if (!isDir(dstTree)) return;
  mustReverify(roots);
  let names = [];
  try {
    names = fs.readdirSync(dstTree).sort();
  } catch {
    return;
  }
  for (const name of names) {
    if (!/^aai-[a-z0-9-]+$/.test(name)) continue;
    const dstEntry = path.join(dstTree, name);
    if (!exists(dstEntry) || exists(path.join(src, tree, name))) continue;
    if (!isRetiredSkillWrapper(dstEntry, name, src)) continue;
    mustGuard(roots, dstEntry);
    try {
      fs.rmSync(dstEntry, { recursive: true, force: true });
    } catch {
      // reported below: the entry still exists
    }
    if (!exists(dstEntry)) {
      ctx.deletions.push(`${tree}/${name}`);
      out(`  CLEAN removed retired skill wrapper: ${tree}/${name}\n`);
    } else {
      out(`  WARN could not remove retired skill wrapper (left in place): ${tree}/${name}\n`);
    }
  }
}

function stepSkillTree(ctx, tree) {
  const { roots, out, src } = ctx;
  const srcTree = path.join(src, tree);
  if (!isDir(srcTree)) return;
  const dstTree = path.join(roots.target, tree);
  makeDir(roots, dstTree);
  for (const name of globNames(srcTree)) {
    const srcEntry = path.join(srcTree, name);
    const dstEntry = path.join(dstTree, name);
    if (fs.existsSync(dstEntry)) {
      const srcMd = path.join(srcEntry, 'SKILL.md');
      const dstMd = path.join(dstEntry, 'SKILL.md');
      if (isFile(srcMd) && isFile(dstMd) && fileDiffers(srcMd, dstMd)) {
        conflictOf(ctx, `${tree}/${name}/SKILL.md`, `Template skill differs in target. Use AI agent to merge intentional project guidance into a project-owned skill (for example ${tree}/aai-project-<topic>/SKILL.md) and keep synced template skills unchanged.`);
      } else if (dirDiffers(srcEntry, dstEntry)) {
        conflictOf(ctx, `${tree}/${name}`, 'Directory differs in target. Use AI agent to extract project-specific content into project-owned skills and keep sync-managed entries as template-only.');
      }
    }
    copyReplace(srcEntry, dstEntry, roots);
  }
  removeRetiredWrappers(ctx, tree);
  out(`  PRESERVE target-only skills under: ${dstTree}\n`);
}

function stepKnowledge(ctx) {
  const { roots, out, src } = ctx;
  const srcDir = path.join(src, 'docs', 'knowledge');
  if (!isDir(srcDir)) return;
  makeDir(roots, path.join(roots.target, 'docs', 'knowledge'));
  for (const name of globNames(srcDir)) {
    const srcFile = path.join(srcDir, name);
    if (!isFile(srcFile)) continue;
    const dstFile = path.join(roots.target, 'docs', 'knowledge', name);
    let holdsSentinel = false;
    try {
      holdsSentinel = isFile(dstFile) && fs.readFileSync(dstFile).includes('AAI-TEMPLATE');
    } catch {
      holdsSentinel = false;
    }
    if (!isFile(dstFile) || holdsSentinel) copyReplace(srcFile, dstFile, roots);
    else out(`  SKIP (project-owned, sentinel removed): ${dstFile}\n`);
  }
}

// seed(ctx, templateRel, targetRel, line, needsDocsAi): copy a template into the target only when the target file is missing.
function seed(ctx, templateRel, targetRel, line) {
  const { roots, out, src } = ctx;
  const template = path.join(src, templateRel);
  const dst = path.join(roots.target, targetRel);
  if (!isFile(template) || isFile(dst)) return;
  makeDir(roots, path.dirname(dst));
  copyReplace(template, dst, roots);
  out(`  ${line}\n`);
}

function stepSeeds(ctx) {
  seed(ctx, '.aai/templates/TECHNOLOGY_TEMPLATE.md', 'docs/TECHNOLOGY.md', 'SEED docs/TECHNOLOGY.md from .aai/templates/TECHNOLOGY_TEMPLATE.md');
  seed(ctx, '.aai/templates/update-config.template.yaml', 'docs/ai/update-config.yaml', 'SEED docs/ai/update-config.yaml from .aai/templates/update-config.template.yaml');
  seed(ctx, '.aai/templates/docs-audit.template.yaml', 'docs/ai/docs-audit.yaml',
    'SEED docs/ai/docs-audit.yaml from .aai/templates/docs-audit.template.yaml (dials report-only; docs-audit --check now runs enforced)');
  if (isDir(path.join(ctx.roots.target, 'docs', 'ai'))) {
    ctx.out('  PRESERVE docs/ai/ runtime data (STATE.yaml, LOOP_TICKS.jsonl, METRICS.jsonl, EVENTS.jsonl, decisions.jsonl, reports/)\n');
  }
}

function stepRootShims(ctx) {
  const { roots, src } = ctx;
  for (const name of ROOT_SHIMS) {
    const srcFile = path.join(src, name);
    const dstFile = path.join(roots.target, name);
    if (isFile(srcFile) && isFile(dstFile) && fileDiffers(srcFile, dstFile)) {
      conflictOf(ctx, name, `Target file contains local changes. Use AI agent to merge project-specific instructions into docs/ai/project-overrides/${name} and keep synced shim concise.`);
    }
    if (isFile(srcFile)) copyReplace(srcFile, dstFile, roots);
  }
  const readme = path.join(src, 'README.md');
  const readmeAai = path.join(roots.target, 'README_AAI.md');
  if (isFile(readme) && isFile(readmeAai) && fileDiffers(readme, readmeAai)) {
    conflictOf(ctx, 'README_AAI.md', 'Target README_AAI.md differs from source README.md. Use AI agent to move project notes into README.md or docs/, and keep README_AAI.md sync-managed.');
  }
  if (isFile(readme)) copyReplace(readme, readmeAai, roots);
}

// stepIndex(ctx, rel, label, text): a skill index (.codex/skills, .gemini/skills) is copy-replaced wholesale.
function stepIndex(ctx, rel, label, text) {
  const { roots, out, src } = ctx;
  const srcDir = path.join(src, rel);
  const dstDir = path.join(roots.target, rel);
  if (isDir(srcDir) && isDir(dstDir) && dirDiffers(srcDir, dstDir)) conflictOf(ctx, `${rel}/`, text);
  if (isDir(srcDir)) copyReplace(srcDir, dstDir, roots);
  if (isDir(`${dstDir}.local`)) out(`  PRESERVE local ${label} dynamic index: ${dstDir}.local\n`);
}

// stepFile(ctx, rel, line): a single managed file copy-replaced when the source has it.
function stepFile(ctx, rel, line) {
  const srcFile = path.join(ctx.src, rel);
  if (!isFile(srcFile)) return;
  copyReplace(srcFile, path.join(ctx.roots.target, rel), ctx.roots);
  ctx.out(`  ${line}\n`);
}

function stepGitignore(ctx) {
  const { roots, out, src } = ctx;
  mustGuard(roots, path.join(roots.target, '.gitignore'));
  reconcileGitignore(roots.target, {
    srcList: path.join(src, '.aai', 'system', 'RUNTIME_IGNORE.list'),
    targetList: path.join(roots.target, '.aai', 'system', 'RUNTIME_IGNORE.list'),
    out,
  });
}

// --- the Copilot shim and the session hooks (D-SURFACES, D-HOOKS) -------------------------------------------------------

const OVERRIDES_START = '<!-- AAI-PROJECT-OVERRIDES:START -->';
const OVERRIDES_END = '<!-- AAI-PROJECT-OVERRIDES:END -->';
const stripTrailingLf = (text) => text.replace(/\n+$/, '');

// extractCopilotOverrides(text): the project overrides of a target's Copilot shim as the bash twin's extraction read them
// (the trailing line feeds of a command substitution removed): when the text holds both markers anywhere, the lines between
// the start line and the end line (each line's CR removed; the first end line stops the scan, even one that comes before the
// start line); else the whole text.
export function extractCopilotOverrides(text) {
  if (!text.includes(OVERRIDES_START) || !text.includes(OVERRIDES_END)) return stripTrailingLf(text);
  const lines = text.split('\n');
  if (lines[lines.length - 1] === '') lines.pop();
  const kept = [];
  let inBlock = false;
  for (const raw of lines) {
    const line = raw.replace(/\r$/, '');
    if (line === OVERRIDES_START) {
      inBlock = true;
      continue;
    }
    if (line === OVERRIDES_END) break;
    if (inBlock) kept.push(line);
  }
  return stripTrailingLf(kept.map((l) => `${l}\n`).join(''));
}

// shippedBytes(bytes, listFile): the work of copilotShimIsShipped on a text held one character per byte (latin1): every CR
// removed; empty or whitespace only is shipped; else the sha256 (node:crypto, always computed, DR-19) of the bytes against the
// list's rows (CR removed), a missing list meaning not shipped.
function shippedBytes(bytes, listFile) {
  const norm = stripTrailingLf(bytes.replace(/\r/g, ''));
  if (/^[ \t\n\v\f]*$/.test(norm)) return true;
  let list = '';
  try {
    if (!statOrNull(listFile)?.isFile()) return false;
    list = fs.readFileSync(listFile, 'latin1');
  } catch {
    return false;
  }
  const hash = createHash('sha256').update(Buffer.from(norm, 'latin1')).digest('hex');
  const rows = list.split('\n');
  if (rows[rows.length - 1] === '') rows.pop();
  return rows.some((row) => row.replace(/\r$/, '') === hash);
}

// copilotShimIsShipped(text, listFile): true when the project-override text of a target's Copilot shim is empty or whitespace
// only, or its normalized hash (every CR removed, trailing LFs dropped, sha256 of the UTF-8 bytes) is a row of the list.
export function copilotShimIsShipped(text, listFile) {
  return shippedBytes(Buffer.from(text, 'utf8').toString('latin1'), listFile);
}

// writeManaged(roots, abs, bytes): a file written under the guard; a destination that is a link is removed first (the link,
// never what it points to), a regular destination is truncated in place (its mode is kept).
function writeManaged(roots, abs, bytes) {
  mustGuard(roots, abs);
  if (lstatOrNull(abs)?.isSymbolicLink()) fs.unlinkSync(abs);
  fs.writeFileSync(abs, bytes);
}

function stepCopilot(ctx) {
  const { roots, out, src } = ctx;
  const srcShim = path.join(src, '.github', 'copilot-instructions.md');
  if (!isFile(srcShim)) return;
  const dstShim = path.join(roots.target, '.github', 'copilot-instructions.md');
  if (!(isFile(dstShim) && fileDiffers(srcShim, dstShim))) {
    copyReplace(srcShim, dstShim, roots);
    return;
  }
  const overrideDir = path.join(roots.target, 'docs', 'ai', 'project-overrides');
  const overrideFile = path.join(overrideDir, 'copilot-instructions.project.md');
  let overrides = extractCopilotOverrides(fs.readFileSync(dstShim, 'latin1'));
  if (overrides === '' && isFile(overrideFile)) overrides = stripTrailingLf(fs.readFileSync(overrideFile, 'latin1'));
  if (shippedBytes(overrides, path.join(src, '.aai', 'system', 'COPILOT_SHIM_SHIPPED.list'))) {
    copyReplace(srcShim, dstShim, roots);
    out('  SYNC .github/copilot-instructions.md (unmodified shipped shim replaced, no project overrides)\n');
    return;
  }
  makeDir(roots, overrideDir);
  writeManaged(roots, overrideFile, Buffer.from(`${overrides}\n`, 'latin1'));
  const merged = Buffer.concat([
    fs.readFileSync(srcShim),
    Buffer.from(`\n---\n## Project Overrides (auto-merged)\n\n${OVERRIDES_START}\n${overrides}\n${OVERRIDES_END}\n`, 'latin1'),
  ]);
  writeManaged(roots, dstShim, merged);
  out(`  MERGE preserved project overrides in: ${overrideFile}\n`);
}

// mergeRegistration(ctx, name): hooks/<name> merged in process (the library throws before it writes); the MERGE line and the
// advisory entries as the bash twin made them from the library CLI's output, the target prefix removed and the source prefix
// replaced by <source>/.
function mergeRegistration(ctx, name) {
  const { roots, out, src } = ctx;
  const srcHook = path.join(src, 'hooks', name);
  const dstHook = path.join(roots.target, 'hooks', name);
  const shipped = path.join(roots.target, '.aai', 'cache', 'hooks-shipped', name);
  mustGuard(roots, dstHook);
  mustGuard(roots, shipped);
  const scrub = (text) => text.split(`${roots.target}${path.sep}`).join('').split(`${src}${path.sep}`).join('<source>/');
  let res = null;
  let refused = '';
  try {
    res = mergeHooksJson(srcHook, dstHook, { shipped });
  } catch (e) {
    refused = scrub(e.message || String(e));
  }
  if (res === null) {
    conflictOf(ctx, `hooks/${name}`, `Hook-registration merge was refused and the target was left untouched: ${refused} Merge the registration manually.`);
    out(`  WARN hooks/${name} registration merge refused (target left untouched): ${refused}\n`);
    return;
  }
  const lines = [formatSummary(res, dstHook), ...formatConflicts(res), ...formatSnapshotError(res, shipped)];
  const text = scrub(lines.join('\n'));
  out(`  MERGE hooks/${name}: ${text}\n`);
  for (const line of text.split('\n')) {
    if (line.startsWith('LEFT-AS-IS ')) {
      conflictOf(ctx, `hooks/${name}`, `A source-owned hook registration changed in the source, but the target's entry for the same script differs from what this engine last shipped, so it was left as-is and the new version was NOT added beside it (a user-modified hook is never rewritten). ${line.slice('LEFT-AS-IS '.length)}`);
    } else if (line.startsWith('SNAPSHOT-NOT-RECORDED ')) {
      const detail = line.slice('SNAPSHOT-NOT-RECORDED '.length);
      conflictOf(ctx, `hooks/${name}`, `The registration merge was applied to the target, but the engine could not record what it shipped (${detail}), so the next sync can only report a changed source-owned entry as left as-is, never update it, until that path is writable. Fix the snapshot path under .aai/cache/hooks-shipped/ and re-sync.`);
      out(`  WARN hooks/${name} merged, but the shipped snapshot could not be recorded: ${detail}\n`);
    }
  }
}

// hookNames(dir): every entry of dir, dotfiles included, in the byte order of the C locale.
function hookNames(dir) {
  try {
    return fs.readdirSync(dir).sort();
  } catch {
    return [];
  }
}

function stepHooks(ctx) {
  const { roots, out, src } = ctx;
  const srcDir = path.join(src, 'hooks');
  if (!isDir(srcDir)) return;
  const dstDir = path.join(roots.target, 'hooks');
  makeDir(roots, dstDir);
  for (const name of hookNames(srcDir)) {
    const srcHook = path.join(srcDir, name);
    if (!fs.existsSync(srcHook)) continue;
    if (name === 'hooks.json' || name === 'hooks.windows.json') mergeRegistration(ctx, name);
    else copyReplace(srcHook, path.join(dstDir, name), roots);
  }
  for (const name of hookNames(dstDir)) {
    if (fs.existsSync(path.join(dstDir, name)) && !fs.existsSync(path.join(srcDir, name))) out(`  PRESERVE target-only hook: hooks/${name}\n`);
  }
  const session = path.join(dstDir, 'session-start.sh');
  const st = lstatOrNull(session);
  if (st !== null && st.isFile()) {
    mustGuard(roots, session);
    fs.chmodSync(session, st.mode & 0o7777 | 0o111);
  }
  out('  SYNC hooks/\n');
}

// --- the advisory report and the pin (D-REPORT) -------------------------------------------------------------------------

// The variables that select a repository; removed from the environment of every git child (DR-22).
const GIT_SELECTORS = ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE'];

const two = (n) => String(n).padStart(2, '0');
// utcStamp(now): the UTC fields of one clock read, to the second.
function utcStamp(now) {
  const date = `${now.getUTCFullYear()}${two(now.getUTCMonth() + 1)}${two(now.getUTCDate())}`;
  const time = `${two(now.getUTCHours())}${two(now.getUTCMinutes())}${two(now.getUTCSeconds())}`;
  const iso = `${now.getUTCFullYear()}-${two(now.getUTCMonth() + 1)}-${two(now.getUTCDate())}T${two(now.getUTCHours())}:${two(now.getUTCMinutes())}:${two(now.getUTCSeconds())}Z`;
  return { name: `${date}-${time}`, iso };
}

// renderAdvisory({ conflicts, deletions, src, now }): { name, text } for the advisory report of a run that recorded a conflict or
// a deletion (the bash text, LF, no BOM; the name and the Generated-at stamp from the one clock read now), else null.
export function renderAdvisory({ conflicts, deletions, src, now }) {
  if (conflicts.length === 0 && deletions.length === 0) return null;
  const stamp = utcStamp(now);
  const lines = [
    '# Sync Conflict Advisory',
    '',
    `- Generated at (UTC): ${stamp.iso}`,
    `- Source: ${src}`,
    '',
    'The following target files/directories had local content that differed from sync source and were overwritten.',
    'Use an AI agent to decide merge strategy per item.',
    '',
    '## Recommended AI workflow',
    '1. Inspect each item with `git diff -- <path>` in the target project.',
    '2. Ask AI to extract project-specific guidance and place it into project-owned docs (for example `docs/ai/project-overrides/`).',
    '3. Keep sync-managed files as baseline templates to reduce future conflicts.',
    '',
    '## Overwritten items',
  ];
  for (const c of conflicts) lines.push('', `- Path: ${c.path}`, `- Recommendation: ${c.text}`);
  if (deletions.length > 0) {
    lines.push('', '## Deleted items');
    for (const d of deletions) lines.push('', `- Path: ${d}`);
  }
  return { name: `sync-conflicts-${stamp.name}.md`, text: `${lines.join('\n')}\n` };
}

// gitOut(startChild, env, src, args): the standard output of one git child (git -C src args; the repository-selecting variables
// removed, stdin ignored, stdout piped) with its trailing line feeds removed, or '' when it failed.
function gitOut(startChild, env, src, args) {
  const childEnv = { ...env };
  for (const name of GIT_SELECTORS) delete childEnv[name];
  let r = null;
  try {
    r = startChild('git', ['-C', src, ...args], { env: childEnv, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8' });
  } catch {
    return '';
  }
  if (!r || r.error || r.status !== 0 || typeof r.stdout !== 'string') return '';
  return stripTrailingLf(r.stdout);
}

// versionOf(src): the value after the last "Version:" on the first line of docs/ai/AAI_VERSION.md that matches ^-? *Version:, with
// spaces, tabs and a CR trimmed; '' when there is no such line or the file cannot be read.
function versionOf(src) {
  let text = '';
  try {
    text = fs.readFileSync(path.join(src, 'docs', 'ai', 'AAI_VERSION.md'), 'utf8');
  } catch {
    return '';
  }
  for (const line of text.split('\n')) {
    if (/^-? *Version:/.test(line)) return line.slice(line.lastIndexOf('Version:') + 'Version:'.length).replace(/^[ \t]+|[ \t\r]+$/g, '');
  }
  return '';
}

// renderPin({ src, profile, now, spawn, env }): the text of .aai/system/AAI_PIN.md: the version (the source's version file, else
// the newest reachable tag with " (tag)", else UNKNOWN), the commit, the canonical url (UNKNOWN on failure), the profile and the
// run's clock to the second. LF, no BOM.
export function renderPin({ src, profile, now, spawn, env }) {
  const git = (args) => gitOut(spawn, env, src, args);
  const commit = git(['rev-parse', 'HEAD']) || 'UNKNOWN';
  const canonical = git(['config', '--get', 'remote.origin.url']) || 'UNKNOWN';
  let version = versionOf(src) || 'UNKNOWN';
  if (version === 'UNKNOWN') {
    const tag = git(['describe', '--tags', '--abbrev=0']);
    if (tag !== '') version = `${tag} (tag)`;
  }
  return [
    '# AAI Pin',
    '',
    `- Source path: ${src}`,
    `${PIN_VERSION_PREFIX}${version}`,
    `- Template commit: ${commit}`,
    `- Canonical repo: ${canonical}`,
    `- Profile: ${profile}`,
    `- Synced at (UTC): ${utcStamp(now).iso}`,
    '',
    'Notes:',
    '- This project intentionally vendors the AAI files (self-contained).',
    '- Project-specific docs (requirements/specs/decisions/releases/issues/project-sessions) are not synced by this script.',
    '- docs/TECHNOLOGY.md is seeded from template only when missing and becomes project-owned after generation.',
    '',
  ].join('\n');
}

// stepReport(ctx, io, profile): the advisory (only when a conflict or a deletion was recorded), then the pin, then the closing
// lines. The clock is read once.
function stepReport(ctx, io, profile) {
  const { roots, out, src } = ctx;
  const now = (io.now ?? (() => new Date()))();
  const advisory = renderAdvisory({ conflicts: ctx.conflicts, deletions: ctx.deletions, src, now });
  if (advisory !== null) {
    const dir = path.join(roots.target, 'docs', 'ai', 'reports');
    makeDir(roots, dir);
    const report = path.join(dir, advisory.name);
    writeManaged(roots, report, advisory.text);
    out(`  Advisory report: ${report}\n`);
  }
  makeDir(roots, path.join(roots.target, '.aai', 'system'));
  writeManaged(roots, path.join(roots.target, '.aai', 'system', 'AAI_PIN.md'), renderPin({ src, profile, now, spawn: io.spawn, env: io.env ?? process.env }));
  out(`Sync complete. Review changes in ${roots.target}:\n  cd ${roots.target} && git status && git diff\n`);
}

// --- run -----------------------------------------------------------------------------------------------------------

// runSteps(argv, io): the checks in the bash order, each before any write, then the steps in the twin's order. Returns the
// exit code.
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
  let coreEntries = [];
  if (profile === 'core') {
    const manifest = path.join(roots.src, '.aai', 'system', 'PROFILES.yaml');
    if (!isFile(manifest)) {
      err(`ERROR: --profile core requires the manifest: ${manifest}\n`);
      return EXIT_FAIL;
    }
    coreEntries = parseCoreList(fs.readFileSync(manifest, 'utf8'));
    if (coreEntries.length === 0) {
      err(`ERROR: no core entries found in ${manifest}\n`);
      return EXIT_FAIL;
    }
  }
  const ctx = {
    roots, out, src: roots.src, coreEntries, coreSet: new Set(coreEntries),
    conflicts: io.ledger?.conflicts ?? [], deletions: io.ledger?.deletions ?? [],
  };
  for (const dir of DIRS_UP_FRONT) makeDir(roots, path.join(roots.target, dir));
  makeDir(roots, path.join(roots.target, '.aai'));
  if (profile === 'core') stepCore(ctx);
  else stepExtended(ctx);
  stepSkillTree(ctx, '.claude/skills');
  stepKnowledge(ctx);
  stepSeeds(ctx);
  stepRootShims(ctx);
  stepCopilot(ctx);
  stepIndex(ctx, '.codex/skills', 'Codex', 'Target Codex skills differ from sync source. Use AI agent to migrate project-specific content into project-owned docs and keep sync-managed indexes untouched.');
  stepIndex(ctx, '.gemini/skills', 'Gemini', 'Target Gemini skills differ from sync source. Use AI agent to migrate project-specific content into project-owned docs and keep sync-managed indexes untouched.');
  stepSkillTree(ctx, '.agents/skills');
  stepFile(ctx, '.claude-plugin/plugin.json', 'SYNC .claude-plugin/plugin.json');
  stepHooks(ctx);
  stepFile(ctx, '.cursor/rules/aai.mdc', 'SYNC .cursor/rules/aai.mdc');
  stepGitignore(ctx);
  stepReport(ctx, io, profile);
  return 0;
}

// run(argv, io): resolves to the exit code. io holds out and err (string sinks), env, cwd, spawn, now and
// scriptPath; each defaults to the real thing. Every child process (git only) goes through io.spawn with io.env.
export async function run(argv, io = {}) {
  const err = io.err ?? writeFd(2);
  try {
    return await runSteps(argv, { ...io, spawn: io.spawn ?? runChild });
  } catch (e) {
    if (e instanceof SyncRefusal) {
      err(`${e.message}\n`);
      return e.code;
    }
    err(`aai-sync: internal error: ${e.message}\n`);
    return EXIT_FAIL;
  }
}

export async function main(argv = process.argv.slice(2)) {
  process.exitCode = await run(argv);
}

// The main guard resolves both sides through realpath (a symlinked checkout still runs main), falling back to a plain resolve.
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) main();
