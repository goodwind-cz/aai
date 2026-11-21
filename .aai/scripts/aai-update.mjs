#!/usr/bin/env node
// aai-update.mjs - the AAI layer updater as one Node module behind thin launchers
// (docs/specs/SPEC-DRAFT-update-on-node.md; RFC-0017 phase 5).
//
// Usage: node .aai/scripts/aai-update.mjs [--repo <slug|url|path>] [--ref <ref>] [--dry-run] [--keep-temp] [--force] [-h]
//
// The module holds the update policy: arguments, the base directory, the canonical-repo guard,
// source resolution, the temp lifecycle, the sync step, the evidence report and the exit code.
// Importing it has no side effect; the main guard runs it only as the entry point. It never reads
// standard input, and all of its output goes through descriptors 1 and 2 so that its lines and the
// lines of the children it starts appear in program order.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_REPO = 'goodwind-cz/aai';
const DEFAULT_REF = 'main';
const EXIT_USAGE = 1;
const EXIT_REFUSED = 2;
const EXIT_FETCH = 3;
const EXIT_MALFORMED = 4;
const TMP_PREFIX = 'aai-src.';
const SRC_SUBDIR = 'src';
const RUNNER_ENV = 'AAI_UPDATE_SYNC_RUNNER';
const SLUG_CASE_FLAGS = 'i';
const PIN_KEYWORDS = ['source', 'version', 'commit', 'canonical', 'ref'];
const ANON_CLONE = ['-c', 'credential.helper=', '-c', 'http.https://github.com/.extraheader='];
const HELPER_REL = '.aai/scripts/update-doctor-report.mjs';
const runChild = (file, args, opts) => spawnSync(file, args, opts);
const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };

// The help text (DR-1): the bash reference's comment block, then the PowerShell usage line and the
// Node requirement line.
const HELP_LINES = [
  'AAI layer updater \u2014 one deterministic command for /aai-update.',
  '',
  'Materializes the canonical AAI repo\'s `main`, runs aai-sync into THIS project,',
  'and prints concise post-sync evidence. Replaces the old 7-step agent-narrated',
  'procedure: the agent now runs this once and relays the final report.',
  '',
  'Usage (run from the TARGET project root):',
  '  ./.aai/scripts/aai-update.sh                       # sync from goodwind-cz/aai@main',
  '  ./.aai/scripts/aai-update.sh --dry-run             # print the plan, change nothing',
  '  ./.aai/scripts/aai-update.sh --repo OWNER/NAME     # alternate upstream slug',
  '  ./.aai/scripts/aai-update.sh --repo ../aai         # alternate upstream: local checkout',
  '  ./.aai/scripts/aai-update.sh --repo git@github.com:OWNER/NAME.git',
  '  ./.aai/scripts/aai-update.sh --ref some-branch     # non-default ref',
  '  ./.aai/scripts/aai-update.sh --keep-temp           # keep the temp clone for inspection',
  '  ./.aai/scripts/aai-update.sh --force               # allow running inside the canonical repo',
  '  powershell -NoProfile -File .aai/scripts/aai-update.ps1 [-Repo X] [-Ref Y] [-DryRun] [-KeepTemp] [-Force]   # the long flags work too',
  'Requires Node.js 22 or later; both launchers run .aai/scripts/aai-update.mjs.',
];
export const HELP_TEXT = `${HELP_LINES.join('\n')}\n`;

const notYet = (name) => new Error(`${name} is not implemented yet`);

// The flags that take a value and the switches, by their exact long spelling and by their PowerShell
// name (matched case-insensitively, no abbreviation).
const VALUE_FLAGS = { '--repo': 'repo', '--ref': 'ref', '-repo': 'repo', '-ref': 'ref' };
const SWITCH_FLAGS = { '--dry-run': 'dryRun', '--keep-temp': 'keepTemp', '--force': 'force', '-dryrun': 'dryRun', '-keeptemp': 'keepTemp', '-force': 'force' };

// flagKey(arg): the lookup key of a flag word: a long flag exactly, a single-dash name lower-cased.
const flagKey = (arg) => (arg.startsWith('--') ? arg : arg.toLowerCase());

// parseArgs(argv): arguments left to right, a later occurrence of a setting wins. outcome is 'run',
// 'help' (-h or --help seen), 'unknown' (arg names the first unrecognized argument) or 'value' (arg
// names the value flag, as given, that came without a value). Parsing stops at the first terminal.
export function parseArgs(argv) {
  const out = { repo: DEFAULT_REPO, ref: DEFAULT_REF, dryRun: false, keepTemp: false, force: false, outcome: 'run', arg: '' };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const eq = arg.startsWith('--') ? arg.indexOf('=') : -1;
    const key = flagKey(eq > 0 ? arg.slice(0, eq) : arg);
    if (arg === '-h' || arg === '--help') {
      out.outcome = 'help';
      return out;
    }
    if (Object.prototype.hasOwnProperty.call(SWITCH_FLAGS, key) && eq < 0) {
      out[SWITCH_FLAGS[key]] = true;
    } else if (Object.prototype.hasOwnProperty.call(VALUE_FLAGS, key)) {
      const value = eq > 0 ? arg.slice(eq + 1) : argv[i + 1];
      if (value === undefined || value === '') {
        out.outcome = 'value';
        out.arg = eq > 0 ? arg.slice(0, eq) : arg;
        return out;
      }
      out[VALUE_FLAGS[key]] = value;
      if (eq < 0) i += 1;
    } else {
      out.outcome = 'unknown';
      out.arg = arg;
      return out;
    }
  }
  return out;
}

const statOrNull = (p) => {
  try {
    return fs.statSync(p);
  } catch {
    return null;
  }
};

const samePlace = (a, b) => a.dev === b.dev && a.ino === b.ino;

// resolveBase(rel, env, cwd): the base directory is PWD when it is absolute and names the same
// device and inode as the working directory, else the working directory; a relative path resolves
// lexically against it (dot-dot goes up the logical path). CDPATH is not read. With no path the
// base itself is returned.
export function resolveBase(rel = '', env = process.env, cwd = process.cwd()) {
  let base = cwd;
  const pwd = env.PWD;
  if (typeof pwd === 'string' && path.isAbsolute(pwd)) {
    const a = statOrNull(pwd);
    const b = statOrNull(cwd);
    if (a && b && samePlace(a, b)) base = path.resolve(pwd);
  }
  return rel === '' ? base : path.resolve(base, rel);
}

export function normSlug() {
  throw notYet('normSlug');
}

export function canonicalGuard() {
  throw notYet('canonicalGuard');
}

export function cloneUrl() {
  throw notYet('cloneUrl');
}

export function resolveSource() {
  throw notYet('resolveSource');
}

export function resolveRunner() {
  throw notYet('resolveRunner');
}

export function syncCommand() {
  throw notYet('syncCommand');
}

export function renderDryRun() {
  throw notYet('renderDryRun');
}

export function changedFiles() {
  throw notYet('changedFiles');
}

export function pinLines() {
  throw notYet('pinLines');
}

export function latestConflict() {
  throw notYet('latestConflict');
}

export function renderEvidence() {
  throw notYet('renderEvidence');
}

export function doctorReport() {
  throw notYet('doctorReport');
}

export function renderNext() {
  throw notYet('renderNext');
}

export function createOwnTemp() {
  throw notYet('createOwnTemp');
}

export function removeOwnTemp() {
  throw notYet('removeOwnTemp');
}

// run(argv, io): returns the exit code. io holds out, err (string sinks), env, cwd, spawn, tmpdir and
// platform; each defaults to the real thing.
export function run(argv, io = {}) {
  const out = io.out ?? writeFd(1);
  const err = io.err ?? writeFd(2);
  const env = io.env ?? process.env;
  const cwd = io.cwd ?? process.cwd();
  const args = parseArgs(argv);
  if (args.outcome === 'help') {
    out(HELP_TEXT);
    return 0;
  }
  if (args.outcome === 'unknown') {
    err(`Unknown argument: ${args.arg}\n`);
    out(HELP_TEXT);
    return EXIT_USAGE;
  }
  if (args.outcome === 'value') {
    err(`aai-update: ${args.arg} needs a value\n`);
    return EXIT_USAGE;
  }
  const state = { keepTemp: args.keepTemp, tmp: '', created: null };
  try {
    resolveBase('', env, cwd);
    throw notYet('the update flow');
  } catch (e) {
    err(`aai-update: internal error: ${e.message}\n`);
    return EXIT_USAGE;
  } finally {
    if (!state.keepTemp && state.tmp) removeOwnTemp(state.tmp, state.created);
  }
}

export function main(argv = process.argv.slice(2)) {
  process.exitCode = run(argv);
}

// The main guard resolves both sides through realpath (a symlinked checkout still runs main), falling back to a plain resolve.
const realOrResolve = (p) => {
  try {
    return fs.realpathSync(p);
  } catch {
    return path.resolve(p);
  }
};

if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) main();
