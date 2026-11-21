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

const TEMPLATE_FILES = { index: 'pre-commit-index.sh', 'guard-checks': 'pre-commit-guard-checks.sh', 'ref-guard': 'reference-transaction.sh', 'pre-push': 'pre-push.sh' };
const SLOT_NAMES = { index: 'pre-commit', 'ref-guard': 'reference-transaction', 'close-gate': 'pre-push' };
const SLOT_MARKERS = { index: '# AAI:INDEX-AUTOGEN', 'ref-guard': '# AAI:REF-GUARD', 'close-gate': '# AAI:CLOSE-GATE' };
const CONFIG_NAME = 'docs-audit.yaml';
const WARN_PREFIX = 'install-pre-commit-hook';
const ownDir = () => path.dirname(fileURLToPath(import.meta.url));
const installerCmd = (root) => `bash ${root}/.aai/scripts/install-pre-commit-hook.sh`;

// loadTemplates(scriptDir, kinds): the templates the run needs, read from <scriptDir>/../templates/git-hooks
// (the module's own location, never the target) with every CR removed. Returns { templates, errors }: the bytes by
// kind and one bash error line (no newline) per missing or malformed template, in the order of kinds (D-TEMPLATE).
export function loadTemplates(scriptDir = ownDir(), kinds = []) {
  const dir = path.join(scriptDir, '..', 'templates', 'git-hooks');
  const templates = {};
  const errors = [];
  for (const kind of kinds) {
    const file = path.join(dir, TEMPLATE_FILES[kind]);
    const st = statOrNull(file);
    if (!st || !st.isFile()) {
      errors.push(`ERROR: AAI hook template missing: ${file}`);
      continue;
    }
    const bytes = Buffer.from(fs.readFileSync(file).filter((b) => b !== 13));
    const lines = bytes.toString('latin1').split('\n');
    if (kind === 'index' && lines.length - (lines[lines.length - 1] === '' ? 1 : 0) < 2) {
      errors.push(`ERROR: AAI hook template malformed (needs a first line and a second line): ${file}`);
      continue;
    }
    if (kind === 'guard-checks') {
      const begins = lines.flatMap((l, i) => (l === GUARD_BEGIN ? [i] : []));
      const ends = lines.flatMap((l, i) => (l === GUARD_END ? [i] : []));
      if (begins.length !== 1 || ends.length !== 1 || begins[0] > ends[0] || bytes[bytes.length - 1] !== 10) {
        errors.push(`ERROR: AAI hook template malformed (needs one GUARD-CHECKS BEGIN line, then one END line, and a final newline): ${file}`);
        continue;
      }
    }
    templates[kind] = bytes;
  }
  return { templates, errors };
}

// composePreCommit(index, guard): a fresh pre-commit hook: the index template's first line with its LF, the guard
// block, the rest of the index template, and a final LF (DR-19).
export function composePreCommit(index, guard) {
  const first = index.indexOf(10) + 1;
  return ensureFinalLf(Buffer.concat([index.subarray(0, first), guard, index.subarray(first)]));
}

// hasMarkerLine(bytes, marker): the marker opens a line (column 0) and is followed by a space, an LF, the end of the
// file, or a CR that is followed by an LF or the end of the file (DR-21).
export function hasMarkerLine(bytes, marker) {
  const escaped = marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(?:^|\\n)${escaped}(?: |\\n|\\r\\n|\\r?$)`).test(Buffer.from(bytes).toString('latin1'));
}

// The interior between the one BEGIN line and the one END line of a hook, or null for any other shape.
const guardInterior = (bytes) => {
  const lines = bytes.toString('latin1').split('\n');
  const begins = lines.flatMap((l, i) => (l === GUARD_BEGIN ? [i] : []));
  const ends = lines.flatMap((l, i) => (l === GUARD_END ? [i] : []));
  if (begins.length !== 1 || ends.length !== 1 || begins[0] > ends[0]) return null;
  return lines.slice(begins[0] + 1, ends[0]).join('\n');
};

// resolveHookPath(ctx, base, name): where git looks for hooks/<name> (resolved against the base directory when
// relative), or '' when git cannot say.
function resolveHookPath(ctx, base, name) {
  const r = ctx.child('git', GIT_PATH_ARGS(name), { cwd: base, env: ctx.env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const p = r.status === 0 ? String(r.stdout).replace(/\n+$/, '') : '';
  return p === '' ? '' : path.resolve(base, p);
}

// resolveSlots(ctx, base): { root, paths } for the repository around base, the hook path of each slot token, or
// { lines } holding the stderr lines of the first refusal.
export function resolveSlots(ctx, base) {
  const top = ctx.child('git', ['rev-parse', '--show-toplevel'], { cwd: base, env: ctx.env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (top.error) return { lines: ['ERROR: git was not found on PATH.'] };
  if (top.status !== 0) return { lines: ['ERROR: not inside a git repository.'] };
  const paths = {};
  for (const token of ['index', 'ref-guard', 'close-gate']) {
    const name = SLOT_NAMES[token];
    paths[token] = resolveHookPath(ctx, base, name);
    if (paths[token] === '') {
      return { lines: [
        `ERROR: could not resolve the effective git hooks path for ${name}`,
        `       (git rev-parse --git-path failed). Refusing to install: a ${token === 'index' ? 'hook' : 'guard'}`,
        '       written to a guessed path would report success while git never runs it.',
      ] };
    }
  }
  return { root: String(top.stdout).replace(/\n+$/, ''), paths };
}

// classifySlot(slotPath, marker): the state of a slot: absent, marked or foreign (a regular file with or without
// the marker line, bytes included) or other (anything else: refused by a later run of this port).
export function classifySlot(slotPath, marker) {
  let l;
  try {
    l = fs.lstatSync(slotPath);
  } catch {
    return { state: 'absent' };
  }
  if (l.isSymbolicLink() || !l.isFile()) return { state: 'other' };
  const bytes = fs.readFileSync(slotPath);
  return { state: hasMarkerLine(bytes, marker) ? 'marked' : 'foreign', bytes };
}

export function planUpgrade() { throw notYet('planUpgrade'); }

// writeSlot(slot, bytes): a temp sibling, created exclusively with mode 0777 minus umask, renamed over the slot.
export function writeSlot(slot, bytes) {
  const tmp = `${slot.path}.aai-tmp.${process.pid}`;
  slot.tmp = tmp;
  try {
    const fd = fs.openSync(tmp, 'wx', 0o777);
    try {
      fs.writeSync(fd, bytes);
    } finally {
      fs.closeSync(fd);
    }
    slot.rename(tmp, slot.path);
  } catch (e) {
    fs.rmSync(tmp, { force: true });
    throw e;
  }
}

const landed = (slot, bytes) => {
  const st = statOrNull(slot.path);
  const l = fs.lstatSync(slot.path, { throwIfNoEntry: false });
  return Boolean(st && l && st.isFile() && !l.isSymbolicLink() && fs.readFileSync(slot.path).equals(bytes[slot.label]));
};

const landingFailure = (slot) => {
  fs.rmSync(slot.tmp, { force: true });
  slot.err(`ERROR: the ${slot.label} hook was composed but did not land at ${slot.path} \u2014 the bytes there are not the ones written (the slot may be a link or a directory). No hook was installed; any stray temporary file has been removed.\n`);
  return EXIT_FAIL;
};

// refuseWholeRun(refusals): every refusal prints its lines in slot order; nothing was written.
const refuseWholeRun = (refusals) => {
  for (const r of refusals) for (const line of r.lines) r.err(`${line}\n`);
  return EXIT_FAIL;
};

// installSlots(slots, refusals, bytes): the attest-then-write order of an install. A slot with keep set needs no
// write; bytes holds the composed bytes by slot label.
function installSlots(slots, refusals, bytes) {
  if (refusals.length) return refuseWholeRun(refusals);
  for (const slot of slots) {
    if (!slot.keep) {
      writeSlot(slot, bytes[slot.label]);
      if (!landed(slot, bytes)) return landingFailure(slot);
    }
    slot.done();
  }
  return 0;
}

// attestSlots(ctx, repo, tokens): re-ask git where each hook lives and prove the file there is ours and runnable;
// every failure prints its line. True when all hold.
function attestSlots(ctx, repo, tokens) {
  let ok = true;
  for (const token of tokens) {
    const name = SLOT_NAMES[token];
    const p = resolveHookPath(ctx, ctx.base, name);
    const bad = (line) => { ctx.err(`ERROR: ${line}\n`); ok = false; };
    if (p === '') bad(`installed ${name} but can no longer resolve the effective hooks path.`);
    else if (!statOrNull(p)?.isFile()) bad(`git resolves the ${name} hook to ${p}, but no file is there.`);
    else if (!hasMarkerLine(fs.readFileSync(p), SLOT_MARKERS[token])) bad(`the ${name} hook git would run (${p}) does not carry ${SLOT_MARKERS[token]}.`);
    else if (ctx.platform !== 'win32' && (fs.statSync(p).mode & 0o100) === 0) bad(`the ${name} hook git would run (${p}) is not executable \u2014 git skips it silently.`);
  }
  return ok;
}

const foreignRefusal = (repo, token) => {
  const p = repo.paths[token];
  if (token === 'index') {
    return [
      `ERROR: ${p} already exists and is not AAI-managed.`,
      '       Pass --force to overwrite, or merge the snippets manually:',
      `       ${repo.root}/.aai/scripts/install-pre-commit-hook.sh --print               # the AAI:INDEX-AUTOGEN body`,
      `       ${repo.root}/.aai/scripts/install-pre-commit-hook.sh --print guard-checks  # the AAI:GUARD-CHECKS block (put it first)`,
    ];
  }
  const kind = token === 'ref-guard' ? 'ref-guard' : 'pre-push';
  return [
    `ERROR: ${p} already exists and is not AAI-managed.`,
    `       Pass --force to overwrite, or merge the ${SLOT_MARKERS[token].slice(2)} body with: ${repo.root}/.aai/scripts/install-pre-commit-hook.sh --print ${kind}`,
  ];
};

const INSTALLED = {
  index: ['Installed AAI pre-commit hook at', () => 'Effect: pre-commit-checks.sh now runs on every commit (secrets detection blocks; roughly four seconds per commit); on every commit that touches docs/, regenerate docs/INDEX.md and stage it.'],
  'ref-guard': ['Installed AAI reference-transaction hook (AAI:REF-GUARD) at', (repo) => `Effect: a refs/heads/main update is refused unless AAI_GIT_WRITE=1 is set on that command. Decline: ${installerCmd(repo.root)} --decline-ref-guard`],
  'close-gate': ['Installed AAI pre-push hook (AAI:CLOSE-GATE) at', () => 'Effect: every push runs close-reconcile.mjs --check over the pushed range (report-only; close_gate: enforce refuses a default-branch push only).'],
};

// slotFor(ctx, repo, token, cls, want, force): the slot record of one planned hook: keep (already installed, with
// its lines) or write (its Installed lines after the write).
function slotFor(ctx, repo, token, cls, want, force) {
  const slot = { token, label: SLOT_NAMES[token], path: repo.paths[token], err: ctx.err, rename: ctx.rename, keep: false };
  if (cls.state === 'marked' && !force) {
    slot.keep = true;
    if (token === 'index' && guardInterior(cls.bytes) === null) throw notYet('planUpgrade');
    const current = token === 'index' ? guardInterior(cls.bytes) === guardInterior(want) : cls.bytes.equals(want);
    slot.done = () => {
      ctx.out(`AAI ${slot.label} hook already installed at ${slot.path}. No action taken.\n`);
      if (!current && token !== 'index') ctx.out(`NOTE: ${slot.path} carries ${SLOT_MARKERS[token]} but its bytes differ from the shipped body; pass --force to replace it.\n`);
    };
    return slot;
  }
  if (cls.state === 'other') throw notYet('a slot that is not a regular file');
  slot.done = () => {
    ctx.out(`${INSTALLED[token][0]} ${slot.path}\n`);
    ctx.out(`${INSTALLED[token][1](repo)}\n`);
  };
  return slot;
}

function ensureHooksDir(ctx, repo) {
  const dir = path.dirname(repo.paths['ref-guard']);
  const st = statOrNull(dir);
  if (st && !st.isDirectory()) {
    ctx.err(`ERROR: the effective git hooks path ${dir} exists and is not a directory.\n`);
    ctx.err('       Refusing to install rather than reporting success on a guard git cannot run.\n');
    return false;
  }
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    ctx.err(`ERROR: could not create the effective git hooks directory ${dir}.\n`);
    return false;
  }
  return true;
}

// recordPolicy(ctx, repo, value): the one writer of the declaration, with the creation disclosure and the repair line.
function recordPolicy(ctx, repo, value) {
  try {
    const r = writeRefGuardPolicy(repo.cfgDir, value, { seedFrom: path.join(repo.root, '.aai', 'templates', 'docs-audit.template.yaml') });
    if (r.seeded === 'template') ctx.out('SEED docs/ai/docs-audit.yaml from .aai/templates/docs-audit.template.yaml (dials report-only; docs-audit --check now runs enforced)\n');
    if (r.seeded === 'empty') ctx.out('NOTE: creating docs/ai/docs-audit.yaml -- this switches docs-audit from report-only to enforced mode (docs-audit --check may now hard-fail on pre-existing orphans/violations it previously only reported).\n');
    if (r.removed.length) ctx.out(`Removed ${r.removed.length} duplicate ref_guard: line(s) from ${repo.cfgPath} (lines ${r.removed.join(', ')}).\n`);
    return true;
  } catch (e) {
    ctx.err(`ERROR: ${e.message}\n`);
    return false;
  }
}

const readPolicy = (ctx, repo) => readRefGuardPolicy(repo.cfgDir, { warnPrefix: WARN_PREFIX, warn: (m) => ctx.err(`${m}\n`) });

function requireTemplates(ctx, kinds) {
  const loaded = loadTemplates(ctx.scriptDir, kinds);
  for (const line of loaded.errors) ctx.err(`${line}\n`);
  return loaded.errors.length ? null : loaded.templates;
}

function declineMode(ctx, repo) {
  const cls = classifySlot(repo.paths['ref-guard'], SLOT_MARKERS['ref-guard']);
  if (cls.state === 'other') throw notYet('a slot that is not a regular file');
  if (cls.state === 'foreign') {
    ctx.err(`ERROR: ${repo.paths['ref-guard']} already exists and is not AAI-managed.\n`);
    ctx.err('       Refusing to remove a foreign hook -- --decline-ref-guard only removes an AAI-managed guard.\n');
    return EXIT_FAIL;
  }
  if (!recordPolicy(ctx, repo, 'declined')) return EXIT_FAIL;
  if (cls.state === 'marked') {
    fs.unlinkSync(repo.paths['ref-guard']);
    ctx.out(`Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from ${repo.paths['ref-guard']}\n`);
  }
  ctx.out(`Declined the AAI reference-transaction guard. Recorded ref_guard: declined in ${repo.cfgPath}\n`);
  ctx.out(`Re-arm with: ${installerCmd(repo.root)} --arm-ref-guard\n`);
  return 0;
}

// The arm needs no write-first reorder: D4 makes CAT-17 (and every other reader) trust an installed hook file
// over the declaration, so a stale declined line surviving a failed record of armed is read as armed anyway.
function armMode(ctx, repo, mode) {
  const templates = requireTemplates(ctx, ['ref-guard']);
  if (!templates) return EXIT_FAIL;
  const cls = classifySlot(repo.paths['ref-guard'], SLOT_MARKERS['ref-guard']);
  if (cls.state === 'foreign' && !mode.force) return refuseWholeRun([{ lines: foreignRefusal(repo, 'ref-guard'), foreign: true, err: ctx.err }]);
  if (!ensureHooksDir(ctx, repo)) return EXIT_FAIL;
  const slot = slotFor(ctx, repo, 'ref-guard', cls, templates['ref-guard'], mode.force);
  const bytes = { [slot.label]: templates['ref-guard'] };
  const code = installSlots([slot], [], bytes);
  if (code !== 0) return code;
  if (!attestSlots(ctx, repo, ['ref-guard'])) return EXIT_FAIL;
  if (!recordPolicy(ctx, repo, 'armed')) return EXIT_FAIL;
  ctx.out(`Recorded ref_guard: armed in ${repo.cfgPath}\n`);
  return 0;
}

function uninstallMode(ctx, repo, mode) {
  for (const token of mode.selected) {
    const name = SLOT_NAMES[token];
    const p = repo.paths[token];
    const st = statOrNull(p);
    if (st && st.isFile() && hasMarkerLine(fs.readFileSync(p), SLOT_MARKERS[token])) {
      fs.unlinkSync(p);
      const label = token === 'index' ? 'AAI pre-commit hook' : `AAI ${name} hook (${SLOT_MARKERS[token].slice(2)})`;
      ctx.out(`Uninstalled ${label} from ${p}\n`);
      if (token === 'ref-guard' && readPolicy(ctx, repo) === 'armed') {
        ctx.out('NOTE: docs/ai/docs-audit.yaml still reads ref_guard: armed, so the next plain install (for example /aai-update) installs the guard again.\n');
        ctx.out(`To keep it off, run: ${installerCmd(repo.root)} --decline-ref-guard\n`);
      }
    } else {
      ctx.out(`No AAI ${name} hook found (or hook is not AAI-managed). No action taken.\n`);
    }
  }
  return 0;
}

// warnDoubledKey: a plain run never writes the policy; with more than one key line it names the repair.
function warnDoubledKey(ctx, repo) {
  let keyLines = [];
  try {
    keyLines = writeRefGuardPolicy(repo.cfgDir, 'armed', { dryRun: true }).keyLines;
  } catch {
    return;
  }
  if (keyLines.length > 1) {
    ctx.err(`WARNING: ${repo.cfgPath} carries ${keyLines.length} ref_guard: lines (lines ${keyLines.join(', ')}); the first one wins. Repair: ${installerCmd(repo.root)} --arm-ref-guard (or --decline-ref-guard).\n`);
  }
}

function installMode(ctx, repo, mode) {
  const want = mode.selected;
  const wantRef = want.includes('ref-guard');
  const policy = wantRef ? readPolicy(ctx, repo) : 'armed';
  if (wantRef) warnDoubledKey(ctx, repo);
  const skipRef = wantRef && SKIP_DECLINED(mode, policy);
  const planned = want.filter((t) => !(t === 'ref-guard' && skipRef));
  const classes = {};
  const refusals = [];
  for (const token of planned) {
    classes[token] = classifySlot(repo.paths[token], SLOT_MARKERS[token]);
    if (classes[token].state === 'foreign' && !mode.force) refusals.push({ lines: foreignRefusal(repo, token), foreign: true, err: ctx.err });
  }
  if (refusals.length > 0) return refuseWholeRun(refusals);
  const kinds = [...(want.includes('index') ? ['index', 'guard-checks'] : []), ...(planned.includes('ref-guard') ? ['ref-guard'] : []), ...(want.includes('close-gate') ? ['pre-push'] : [])];
  const templates = kinds.length ? requireTemplates(ctx, kinds) : {};
  if (!templates) return EXIT_FAIL;
  if (!ensureHooksDir(ctx, repo)) return EXIT_FAIL;
  const bytes = {};
  if (templates.index) bytes['pre-commit'] = composePreCommit(templates.index, templates['guard-checks']);
  if (templates['ref-guard']) bytes['reference-transaction'] = templates['ref-guard'];
  if (templates['pre-push']) bytes['pre-push'] = templates['pre-push'];
  const slots = [];
  for (const token of want) {
    if (token === 'ref-guard' && skipRef) {
      slots.push({ keep: true, done: () => {
        ctx.out(`Skipped AAI reference-transaction hook (AAI:REF-GUARD): ${repo.cfgPath} declares ref_guard: declined.\n`);
        ctx.out(`Re-arm with: ${installerCmd(repo.root)} --arm-ref-guard (--force installs the hook for this run only; ref_guard: declined stays recorded).\n`);
      } });
    } else {
      slots.push(slotFor(ctx, repo, token, classes[token], bytes[SLOT_NAMES[token]], mode.force));
    }
  }
  const code = installSlots(slots, [], bytes);
  if (code !== 0) return code;
  if (!attestSlots(ctx, repo, planned)) {
    ctx.err('ERROR: installation did NOT leave an active hook at the path git resolves.\n');
    ctx.err("       Check 'git config core.hooksPath' and 'git rev-parse --git-path hooks/reference-transaction'.\n");
    return EXIT_FAIL;
  }
  ctx.out('Uninstall with: bash .aai/scripts/install-pre-commit-hook.sh --uninstall\n');
  return 0;
}

function dispatchMode(mode, ctx) {
  if (mode.mode === 'print') {
    const templates = requireTemplates(ctx, [mode.printKind]);
    if (!templates) return EXIT_FAIL;
    ctx.out(templates[mode.printKind]);
    return 0;
  }
  ctx.base = resolveBase(ctx.env, ctx.cwd);
  const found = resolveSlots(ctx, ctx.base);
  if (found.lines) {
    for (const line of found.lines) ctx.err(`${line}\n`);
    return EXIT_FAIL;
  }
  const cfgDir = path.join(found.root, 'docs', 'ai');
  const repo = { root: found.root, paths: found.paths, cfgDir, cfgPath: path.join(cfgDir, CONFIG_NAME) };
  if (mode.mode === 'decline') return declineMode(ctx, repo);
  if (mode.mode === 'arm') return armMode(ctx, repo, mode);
  if (mode.mode === 'uninstall') return uninstallMode(ctx, repo, mode);
  return installMode(ctx, repo, mode);
}

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
    const ctx = {
      out,
      err,
      env: io.env ?? process.env,
      cwd: io.cwd ?? process.cwd(),
      child: io.spawn ?? runChild,
      rename: io.rename ?? fs.renameSync,
      platform: io.platform ?? process.platform,
      scriptDir: io.scriptDir ?? ownDir(),
    };
    return dispatchMode(mode, ctx);
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
