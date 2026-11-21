#!/usr/bin/env node
// install-pre-commit-hook.mjs - the AAI git hook installer as one Node module behind thin launchers
// (docs/specs/SPEC-DRAFT-pre-commit-installer-on-node.md; RFC-0017 phase 5).
//
// Usage: node .aai/scripts/install-pre-commit-hook.mjs [--force] [--uninstall] [--print [kind]] [--hooks <csv>] [--decline-ref-guard] [--arm-ref-guard] [-h]
//
// The module holds the installer policy: arguments and the one resolved mode, template loading, path
// resolution, slot attestation, composition, writes and the exit code. Importing it has no side effect;
// the main guard runs it only as the entry point. It never reads standard input, and all of its output
// goes through descriptors 1 and 2 so that its lines and the lines of the git children appear in
// program order.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readRefGuardPolicy, writeRefGuardPolicy } from './lib/guard-config.mjs';

const EXIT_FAIL = 1;
const EXIT_USAGE = 2;
const GUARD_BEGIN = '# AAI:GUARD-CHECKS BEGIN';
const GUARD_END = '# AAI:GUARD-CHECKS END';
const HOOK_TOKENS = ['index', 'ref-guard', 'close-gate'];
const PRINT_KINDS = ['index', 'ref-guard', 'guard-checks', 'pre-push'];
const MODE_FLAGS = ['--uninstall', '--print', '--decline-ref-guard', '--arm-ref-guard'];
const PS_NAMES = { '-force': '--force', '-uninstall': '--uninstall', '-hooks': '--hooks', '-declinerefguard': '--decline-ref-guard', '-armrefguard': '--arm-ref-guard' };
const GIT_PATH_ARGS = (name) => ['rev-parse', '--git-path', `hooks/${name}`];
const SKIP_DECLINED = (mode, policy) => !mode.force && policy === 'declined';
const ensureFinalLf = (b) => (b.length && b[b.length - 1] !== 10 ? Buffer.concat([b, Buffer.from('\n')]) : b);
const runChild = (file, args, opts) => spawnSync(file, args, opts);
const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };

// The help text (DR-1): the leading comment block of the bash reference, then the PowerShell usage
// line and the Node requirement line.
const HELP_LINES = [
  'Install the AAI git hook SET into the EFFECTIVE hooks directory \u2014 the one',
  '`git rev-parse --git-path hooks/<name>` resolves, which honours core.hooksPath',
  'and a linked worktree\'s shared git dir. It is usually .git/hooks, but never',
  'assume that: see the resolve_hook_path comment below. Three hooks, each',
  'recognised by its own marker:',
  '  - pre-commit (token index, marker AAI:INDEX-AUTOGEN) \u2014 auto-regenerates',
  '    docs/INDEX.md whenever the commit touches docs/ (RFC-0001 layer 4',
  '    convenience). Its first lines are a marker-scoped AAI:GUARD-CHECKS',
  '    block (`# AAI:GUARD-CHECKS BEGIN` \u2026 `END`) that runs',
  '    .aai/scripts/pre-commit-checks.sh on EVERY commit and refuses the',
  '    commit when that script does (secrets detection blocks; the doc-',
  '    numbering guard reports or blocks per docs/ai/docs-audit.yaml).',
  '  - reference-transaction (token ref-guard, marker AAI:REF-GUARD) \u2014 refuses',
  '    a refs/heads/main ref update unless AAI_GIT_WRITE=1 is set on that',
  '    exact command (D1/D3,',
  '    docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md).',
  '    This turns an honest/accidental write to main into a refusal instead',
  '    of an ambient default; it is not a security boundary (the spec\'s D3).',
  '  - pre-push (token close-gate, marker AAI:CLOSE-GATE) \u2014 runs',
  '    .aai/scripts/close-reconcile.mjs --check over every pushed range: a',
  '    default-branch ref is checked as <remote sha>..<local sha>, any other',
  '    ref as merge-base(origin/<default>, local)..local. Report-only unless',
  '    the PUSHED commit\'s docs/ai/docs-audit.yaml says `close_gate: enforce`,',
  '    and even then only a push to the default branch is refused',
  '    (docs/specs/SPEC-0201-spec-shipped-guards-have-no-downstream-trigger.md D1).',
  '',
  'Usage:',
  '  ./.aai/scripts/install-pre-commit-hook.sh           # install if absent',
  '  ./.aai/scripts/install-pre-commit-hook.sh --force   # overwrite existing',
  '  ./.aai/scripts/install-pre-commit-hook.sh --uninstall',
  '  ./.aai/scripts/install-pre-commit-hook.sh --print [index|ref-guard|guard-checks|pre-push]',
  '                                                       # emit a hook body (or',
  '                                                       # the guard block) to',
  '                                                       # stdout for a manual',
  '                                                       # merge (bare --print',
  '                                                       # keeps the index body)',
  '  ./.aai/scripts/install-pre-commit-hook.sh --print guard-checks',
  '                                                       # the AAI:GUARD-CHECKS',
  '                                                       # block alone',
  '  ./.aai/scripts/install-pre-commit-hook.sh --print pre-push',
  '                                                       # the AAI:CLOSE-GATE',
  '                                                       # pre-push body',
  '  ./.aai/scripts/install-pre-commit-hook.sh --hooks <csv>',
  '                                                       # select which hook(s)',
  '                                                       # to install/uninstall',
  '                                                       # -- closed set:',
  '                                                       # index, ref-guard, close-gate, all',
  '                                                       # (default all)',
  '  ./.aai/scripts/install-pre-commit-hook.sh --decline-ref-guard',
  '                                                       # remove the ref-guard',
  '                                                       # hook and record the',
  '                                                       # decline in',
  '                                                       # docs/ai/docs-audit.yaml',
  '  ./.aai/scripts/install-pre-commit-hook.sh --arm-ref-guard',
  '                                                       # (re-)install the',
  '                                                       # ref-guard hook and',
  '                                                       # record the arm in',
  '                                                       # docs/ai/docs-audit.yaml',
  '',
  'Idempotent per hook. A plain run (no flags, the shape /aai-update runs after',
  'every successful sync) installs the SELECTED hooks that are absent, leaves',
  'an AAI-managed hook whose bytes already match alone, and honours a declared',
  '`ref_guard: declined` (docs/ai/docs-audit.yaml) by SKIPPING the ref-guard',
  'hook rather than silently re-arming it \u2014 so a plain run does not install',
  '"both hooks" on a repository that declined one; --arm-ref-guard or --force',
  'override the decline. It refuses to overwrite a non-AAI (foreign) hook in a',
  'selected slot unless --force is given, and checks EVERY selected slot before',
  'writing any, so a foreign hook in one slot never causes a partial install.',
  'An AAI pre-commit hook installed before the guard block existed is UPGRADED',
  'in place: the block is inserted after the shebang line and every other byte',
  'is left as it was (a hand-merged foreign hook that adopted the marker keeps',
  'its own body); a hook the installer cannot prove it owns \u2014 no AAI marker, a',
  'symlinked slot, a CR-terminated first line, more than one guard block \u2014 is',
  'refused by name and left byte-identical. Nothing outside an AAI marker is',
  'ever deleted or rewritten by a plain run.',
  '  powershell -NoProfile -File .aai/scripts/install-pre-commit-hook.ps1 [-Force] [-Uninstall] [-Hooks <csv>] [-DeclineRefGuard] [-ArmRefGuard]   # the long flags work too',
  'Requires Node.js 22 or later; both launchers run .aai/scripts/install-pre-commit-hook.mjs.',
];
export const HELP_TEXT = `${HELP_LINES.join('\n')}\n`;

const HOOKS_SET = '(closed set: index, ref-guard, close-gate, all)';
const MODE_OF = { '--uninstall': 'uninstall', '--print': 'print', '--decline-ref-guard': 'decline', '--arm-ref-guard': 'arm' };

// canonicalFlag(arg): the long flag a word names: a long flag exactly (case-sensitive), or one of the five
// PowerShell names matched case-insensitively. Anything else (an abbreviation, a common parameter, an equals
// form) names no flag.
const canonicalFlag = (arg) => {
  if (/^--(force|uninstall|print|hooks|decline-ref-guard|arm-ref-guard)$/.test(arg)) return arg;
  const key = arg.toLowerCase();
  return Object.prototype.hasOwnProperty.call(PS_NAMES, key) ? PS_NAMES[key] : '';
};

// parseArgs(argv): arguments left to right. outcome is 'run', 'help' (-h or --help seen: parsing stops there),
// 'unknown' (arg names the first unrecognized argument) or 'hooks-value' (--hooks or -Hooks came last, with no
// value). A later --hooks or --print kind wins; a repeated flag is one flag.
export function parseArgs(argv) {
  const out = { force: false, flags: [], printKind: '', hooks: null, outcome: 'run', arg: '' };
  const seen = new Set();
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '-h' || arg === '--help') {
      out.outcome = 'help';
      return out;
    }
    const flag = canonicalFlag(arg);
    if (flag === '') {
      out.outcome = 'unknown';
      out.arg = arg;
      return out;
    }
    if (flag === '--force') {
      out.force = true;
    } else if (flag === '--hooks') {
      if (i + 1 >= argv.length) {
        out.outcome = 'hooks-value';
        out.arg = arg;
        return out;
      }
      i += 1;
      out.hooks = argv[i];
    } else {
      seen.add(flag);
      if (flag === '--print' && PRINT_KINDS.includes(argv[i + 1])) {
        i += 1;
        out.printKind = argv[i];
      }
    }
  }
  out.flags = MODE_FLAGS.filter((f) => seen.has(f));
  return out;
}

// splitHooks(value): the selected slot tokens of a --hooks value, or { bad } naming the first token (trimmed of
// spaces and tabs) that is empty or outside the closed set. Matching is case-sensitive.
function splitHooks(value) {
  const tokens = [];
  for (const raw of value.split(',')) {
    const tok = raw.replace(/^[ \t]+|[ \t]+$/g, '');
    if (tok === 'all') tokens.push(...HOOK_TOKENS);
    else if (HOOK_TOKENS.includes(tok)) tokens.push(tok);
    else return { bad: tok };
  }
  return { tokens: HOOK_TOKENS.filter((t) => tokens.includes(t)) };
}

// resolveMode(parsed): the one mode of a parsed command line with its modifiers, or { error } holding the
// single stderr line of the first rule that fails (D-CLI order). It reads no file and starts no child.
export function resolveMode(parsed) {
  const { flags, force } = parsed;
  const hooksGiven = parsed.hooks !== null;
  if (flags.length > 1) return { error: `ERROR: ${flags[0]} and ${flags[1]} are contradictory.` };
  if (hooksGiven && (flags[0] === '--decline-ref-guard' || flags[0] === '--arm-ref-guard')) {
    return { error: 'ERROR: --hooks is contradictory with --decline-ref-guard/--arm-ref-guard (these act on the reference-transaction hook alone).' };
  }
  if (hooksGiven && flags[0] === '--print') {
    return { error: 'ERROR: --hooks has no effect with --print (name the body instead: --print index, ref-guard, guard-checks or pre-push).' };
  }
  if (force && ['--print', '--uninstall', '--decline-ref-guard'].includes(flags[0])) return { error: `ERROR: --force has no effect with ${flags[0]}.` };
  const picked = splitHooks(hooksGiven ? parsed.hooks : 'all');
  if (picked.bad !== undefined) return { error: `ERROR: unknown --hooks value: '${picked.bad}' ${HOOKS_SET}` };
  const mode = flags.length ? MODE_OF[flags[0]] : 'install';
  return { mode, force, selected: picked.tokens, printKind: mode === 'print' ? (parsed.printKind || 'index') : '' };
}

const statOrNull = (p) => {
  try {
    return fs.statSync(p);
  } catch {
    return null;
  }
};

// resolveBase(env, cwd): the base directory is PWD when it is absolute and names the same device and inode as
// the working directory, else the working directory (DR-20); git children run with it as their cwd.
export function resolveBase(env = process.env, cwd = process.cwd()) {
  const pwd = env.PWD;
  if (typeof pwd === 'string' && path.isAbsolute(pwd)) {
    const a = statOrNull(pwd);
    const b = statOrNull(cwd);
    if (a && b && a.dev === b.dev && a.ino === b.ino) return path.resolve(pwd);
  }
  return cwd;
}

const notYet = (what) => new Error(`${what} is not implemented yet`);

// Placeholders of the later runs of this port; each one is replaced by its run.
export function loadTemplates() { throw notYet('loadTemplates'); }
export function composePreCommit() { throw notYet('composePreCommit'); }
export function hasMarkerLine() { throw notYet('hasMarkerLine'); }
export function resolveSlots() { throw notYet('resolveSlots'); }
export function classifySlot() { throw notYet('classifySlot'); }
export function planUpgrade() { throw notYet('planUpgrade'); }
export function writeSlot() { throw notYet('writeSlot'); }
const refuseWholeRun = () => { throw notYet('refuseWholeRun'); };
const landed = () => { throw notYet('landed'); };
const landingFailure = () => { throw notYet('landingFailure'); };

// installSlots(slots, refusals, bytes): the attest-then-write order of an install, filled in by the slot runs.
function installSlots(slots, refusals, bytes) {
  if (refusals.length) return refuseWholeRun(refusals);
  for (const slot of slots) {
    if (!landed(slot, bytes)) return landingFailure(slot);
  }
  return 0;
}

// The arm needs no write-first reorder: D4 makes CAT-17 (and every other reader) trust an installed hook file
// over the declaration, so a stale declined line surviving a failed record of armed is read as armed anyway.
const dispatchMode = (mode) => {
  void [installSlots, readRefGuardPolicy, writeRefGuardPolicy, SKIP_DECLINED, ensureFinalLf, GUARD_BEGIN, GUARD_END, GIT_PATH_ARGS, runChild];
  throw notYet(`the ${mode.mode} mode`);
};

// run(argv, io): resolves to the exit code. io takes out, err, env, cwd, spawn, rename, platform and scriptDir.
export function run(argv, io = {}) {
  const out = io.out ?? writeFd(1);
  const err = io.err ?? writeFd(2);
  try {
    const parsed = parseArgs(argv);
    if (parsed.outcome === 'help') {
      out(HELP_TEXT);
      return 0;
    }
    if (parsed.outcome === 'unknown') {
      err(`ERROR: unexpected argument: ${parsed.arg}\n`);
      return EXIT_USAGE;
    }
    if (parsed.outcome === 'hooks-value') {
      err(`ERROR: --hooks requires a value ${HOOKS_SET}\n`);
      return EXIT_USAGE;
    }
    const mode = resolveMode(parsed);
    if (mode.error) {
      err(`${mode.error}\n`);
      return EXIT_USAGE;
    }
    return dispatchMode(mode);
  } catch (e) {
    err(`install-pre-commit-hook: internal error: ${e && e.message ? e.message : e}\n`);
    return EXIT_FAIL;
  }
}

export function main(argv = process.argv.slice(2)) {
  const code = run(argv);
  process.exitCode = code;
  return code;
}

// The main guard resolves both sides through realpath (a symlinked checkout still runs main).
const realOrResolve = (p) => {
  try {
    return fs.realpathSync(p);
  } catch {
    return path.resolve(p);
  }
};

if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) main();
