#!/usr/bin/env node
// aai-bootstrap.mjs - project bootstrap as one Node module behind thin launchers
// (docs/specs/SPEC-DRAFT-bootstrap-on-node.md; RFC-0017 phase 5).
//
// Usage: node .aai/scripts/aai-bootstrap.mjs [target-root] [--dry-run] [--force] [--with-claude-hooks]
//
// The module holds the bootstrap policy: arguments, root resolution, detection, command choice, the
// skill plan, rendering, writes and the exit code. Importing it has no side effect; the main guard
// runs it only as the entry point. It never reads standard input.

import { spawnSync } from 'node:child_process';
import { realpathSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const GENERATOR = '.aai/scripts/aai-bootstrap.sh';
const SKILL_MARKER = 'AAI-DYNAMIC-SKILL:START';
const FILE_MARKER = 'AAI-DYNAMIC-FILE:START';
const RUNTIME_MARKER_PREFIX = '# AAI runtime sidecars';
const RUNTIME_MARKER = '# AAI runtime sidecars (seeded by aai-bootstrap; per-dev, never commit)';
const CACHE_PATTERNS = ['.claude/skills/.cache', '.codex/skills.local/.cache', '.gemini/skills.local/.cache'];
const LOCKFILES = [['pnpm-lock.yaml', 'pnpm'], ['yarn.lock', 'yarn'], ['bun.lock', 'bun'], ['bun.lockb', 'bun']];
const AUTH_SKIP_DIRS = ['node_modules', '.git', 'dist', 'build'];
const HOOKS_UNCHANGED = '0 hook(s) added, 0 updated';
const PLATFORM_MISMATCH = 6;
const EXIT_HOOKS_REFUSED = 3;
const EXIT_CONFLICT = 1;
const EXIT_USAGE = 2;

const samePlace = (a, b) => a.dev === b.dev && a.ino === b.ino;
const stripTrailingNewlines = (s) => s.replace(/\n+$/, '');
const sameContent = (a, b) => stripTrailingNewlines(a) === stripTrailingNewlines(b);
const runChild = (script, args, cwd) => spawnSync(process.execPath, [script, ...args], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

// The help text: the reference's comment block (DR-1: without its two leading source lines) with the
// PowerShell usage line right after the POSIX usage line.
const HELP_LINES = [
  'Generate project-local AAI dynamic skills from evidence in the target repo.',
  '',
  'Usage:',
  '  ./.aai/scripts/aai-bootstrap.sh [target-root] [--dry-run] [--force] [--with-claude-hooks]',
  '  powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 [target-root] [--dry-run] [--force] [--with-claude-hooks]',
  '',
  'Safety model:',
  '- Creates or updates only known dynamic skill files and local discovery indexes.',
  '- Refuses to overwrite a skill file that does not contain the AAI dynamic marker.',
  '- --dry-run prints planned writes without changing files.',
  '- --force is the explicit confirmation for replacing unmarked dynamic skill paths.',
  '- --with-claude-hooks (OPT-IN, RFC-0010): merge the AAI hook-enforced gates',
  '  overlay from .aai/templates/hooks/settings-hooks.json into .claude/settings.json',
  '  (additive merge; existing settings preserved; never overwrites silently).',
];
export const HELP_TEXT = `${HELP_LINES.join('\n')}\n`;

// The npm family's command for a package script; npm runs its test script without `run`.
function scriptCommand(pm, script) {
  if (pm === 'npm' && script === 'test') return 'npm test';
  return `${pm} run ${script}`;
}

const notYet = (name) => () => {
  throw new Error(`aai-bootstrap: ${name} is not implemented yet`);
};

// parseArgs(argv): arguments left to right as the reference reads them. outcome is 'run', 'help'
// (-h or --help seen first) or 'usage' (a second positional, named in extra).
export function parseArgs(argv) {
  const out = { dryRun: false, force: false, withClaudeHooks: false, target: '', outcome: 'run', extra: '' };
  for (const arg of argv) {
    if (arg === '--dry-run') out.dryRun = true;
    else if (arg === '--force') out.force = true;
    else if (arg === '--with-claude-hooks') out.withClaudeHooks = true;
    else if (arg === '-h' || arg === '--help') {
      out.outcome = 'help';
      return out;
    } else if (out.target === '') out.target = arg;
    else {
      out.outcome = 'usage';
      out.extra = arg;
      return out;
    }
  }
  return out;
}

const statOrNull = (p) => {
  try {
    return statSync(p);
  } catch {
    return null;
  }
};

// resolveRoot(target, env, cwd): the base is PWD when it is absolute and names the working directory
// (the rule bash trusts PWD by), else the working directory; a target resolves lexically against it.
// CDPATH is not read.
export function resolveRoot(target = '', env = process.env, cwd = process.cwd()) {
  let base = cwd;
  const pwd = env.PWD;
  if (typeof pwd === 'string' && path.isAbsolute(pwd)) {
    const a = statOrNull(pwd);
    const b = statOrNull(cwd);
    if (a && b && samePlace(a, b)) base = pwd;
  }
  return target === '' ? base : path.resolve(base, target);
}

export const detect = notYet('detect');
export const chooseCommands = notYet('chooseCommands');
export const dockerTag = notYet('dockerTag');
export const detectAuth = notYet('detectAuth');
export const planSkills = notYet('planSkills');
export const wrapTestCommand = notYet('wrapTestCommand');
export const renderSkill = notYet('renderSkill');
export const renderMarker = notYet('renderMarker');
export const renderIndex = notYet('renderIndex');
export const renderSummary = notYet('renderSummary');
export const isManagedFile = notYet('isManagedFile');
export const preflight = notYet('preflight');
export const writeOutputs = notYet('writeOutputs');
export const ensureGitignore = notYet('ensureGitignore');
export const seedRuntimeGitignore = notYet('seedRuntimeGitignore');
export const installClaudeHooks = notYet('installClaudeHooks');
export const recordGitPlatform = notYet('recordGitPlatform');

// run(argv, io): returns the exit code. io holds out, err (string sinks), now, env, cwd and spawn.
export function run(argv, io = {}) {
  const out = io.out ?? ((s) => process.stdout.write(s));
  const err = io.err ?? ((s) => process.stderr.write(s));
  const env = io.env ?? process.env;
  const cwd = io.cwd ?? process.cwd();
  const args = parseArgs(argv);
  if (args.outcome === 'help') {
    out(HELP_TEXT);
    return 0;
  }
  if (args.outcome === 'usage') {
    err(`ERROR: unexpected argument: ${args.extra}\n`);
    err(HELP_TEXT);
    return EXIT_USAGE;
  }
  const root = resolveRoot(args.target, env, cwd);
  const st = statOrNull(root);
  if (!st || !st.isDirectory()) {
    err(`aai-bootstrap: target not found: ${args.target}\n`);
    return EXIT_CONFLICT;
  }
  notYet('the bootstrap pipeline')(args, root);
  return 0;
}

export function main(argv = process.argv.slice(2)) {
  process.exitCode = run(argv);
}

const isEntryPoint = () => {
  try {
    return Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
};

if (isEntryPoint()) main();
