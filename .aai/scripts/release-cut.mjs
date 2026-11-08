#!/usr/bin/env node
// release-cut.mjs: the CHANGELOG rollup, the tag check, the unlogged-PR audit call and the plan rendering
// of /aai-release's local paths (plan, --dry-run, --confirm --no-remote). aai-release.sh and aai-release.ps1
// call it; it rolls through the shared lib/release-rollup.mjs (the transform the remote finish uses) and
// spawns release-finish.mjs --audit. Node stdlib only; importing it has no side effect.
//
//   release-cut.mjs plan  --root R --version V --target-branch B --launcher sh|ps1 [--no-remote] [--gh-block <reason>]
//   release-cut.mjs check --root R --version V --launcher sh|ps1 --launcher-path P
//   release-cut.mjs roll  --file F --version V
//
// Exit codes: 0 ok | 1 bad argument | 12 malformed [unreleased] region or file not UTF-8 |
//   13 no rollable entries | 15 tag exists | 20 missing release notes (relays the audit's own code on audit failure)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { rollup } from './lib/release-rollup.mjs';

const AUDIT_SCRIPT = 'release-finish.mjs';
const PLAN_HEADER = '## aai-release (plan) — no files changed';
const EXIT = { MALFORMED: 12, EMPTY: 13, TAG: 15, REFUSED: 20 };
const ORIGIN_PROBE = ['config', '--get', 'remote.origin.url'];
const USAGE = 'usage: release-cut.mjs plan|check|roll (see the header of release-cut.mjs)';

const LINES = {
  malformed: "REFUSED: malformed [unreleased] heading in CHANGELOG.md (a '## [unreleased]' line has unexpected trailing text or a stray heading-only body) — never silently dropping entries.",
  encoding: 'REFUSED: CHANGELOG.md is not valid UTF-8 — never guessing its encoding.',
  empty: 'REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) — nothing to release.',
};

const FLAGS = {
  '--root': 'root', '--version': 'version', '--target-branch': 'targetBranch', '--launcher': 'launcher',
  '--launcher-path': 'launcherPath', '--gh-block': 'ghBlock', '--file': 'file',
};
const NEEDS = {
  plan: ['root', 'version', 'targetBranch', 'launcher'],
  check: ['root', 'version', 'launcher', 'launcherPath'],
  roll: ['file', 'version'],
};

export function parseArgs(argv) {
  const o = { cmd: argv[0], root: '', version: '', targetBranch: '', launcher: '', launcherPath: '', noRemote: false, ghBlock: '', file: '' };
  if (!NEEDS[o.cmd]) return { error: USAGE };
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--no-remote') o.noRemote = true;
    else if (FLAGS[argv[i]] && i + 1 < argv.length) o[FLAGS[argv[i]]] = argv[++i];
    else return { error: USAGE };
  }
  if (NEEDS[o.cmd].some((k) => !o[k])) return { error: USAGE };
  if (o.launcher && o.launcher !== 'sh' && o.launcher !== 'ps1') return { error: USAGE };
  return o;
}

// Strict UTF-8 on every engine (DR-06); the BOM is kept so the rollup can keep it (DR-05).
export function decode(bytes) {
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch {
    throw Object.assign(new Error(LINES.encoding), { causeName: 'encoding' });
  }
}

export function rollOrRefuse(text, version) {
  try {
    return rollup(text, version);
  } catch (e) {
    if (e.causeName === 'malformed-notes') return { code: EXIT.MALFORMED, line: LINES.malformed };
    if (e.causeName === 'empty-notes') return { code: EXIT.EMPTY, line: LINES.empty };
    throw e;
  }
}

export function rolledHeadings(content, version) {
  const prefix = `## [${version}] — `;
  const found = [];
  content.split('\n').forEach((l, i) => {
    const line = l.replace(/\r$/, '');
    if (line.startsWith(prefix)) found.push({ n: i + 1, line });
  });
  return found;
}

export function onlineAllowed({ ghBlock, noRemote, origin }) {
  return !ghBlock && !noRemote && Boolean(origin);
}

export function resumeLine(launcher, launcherPath, version) {
  return launcher === 'ps1'
    ? `Resume: pwsh -NoProfile -File "${launcherPath}" -Version ${version} -Confirm -NoRemote`
    : `Resume: bash "${launcherPath}" --version ${version} --confirm --no-remote`;
}

export function planLines({ version, launcher, targetBranch, noRemote, ghBlock, tagExists, headings, notes, unlogged }) {
  const ps = launcher === 'ps1';
  const L = [PLAN_HEADER, `- Resolved version: ${version}`, `- Tag to create:    ${version} (annotated)`, `- Commit message:   chore(release): ${version}`, ''];
  L.push('## CHANGELOG rollup (would write)', ...headings.map((h) => `  ${h.n}:${h.line}`), '  ## [unreleased]   <- fresh scaffold inserted above the rolled section', '');
  L.push(`## Release notes preview (title=${version})`, ...notes.split('\n').map((l) => `  ${l}`), '', '## Preconditions');
  let blocked = false;
  if (tagExists) { L.push(`- would block: tag ${version} already exists`); blocked = true; }
  if (ghBlock) { L.push(`- would block (publish path): ${ghBlock}`); blocked = true; }
  if (unlogged.length) {
    L.push(`- NAMED (not blocking): ${unlogged.length} PR(s) merged since the previous tag have no matching section in these notes:`, ...unlogged.map((l) => `    - ${l}`),
      "    Add a '## [unreleased] — <title>' section for each, or confirm they are covered under another title.");
    L.push('- confirm will refuse until the NAMED missing release notes are resolved');
  } else if (!blocked) L.push(`- none — ready to cut with ${ps ? '-Confirm' : '--confirm'}`);
  L.push('', '## Remote');
  if (noRemote) L.push(`- ${ps ? '-NoRemote' : '--no-remote'} / AAI_RELEASE_NO_REMOTE=1: push + gh pr create would be SKIPPED`);
  else L.push(`- push (branch chore/release-${version}) and 'gh pr create' (base ${targetBranch}) WOULD run against this repo's remote; CI will tag and publish upon merge`);
  return L;
}

const lines = (s) => String(s ?? '').split('\n').map((l) => l.replace(/\r$/, '')).filter((l) => l.trim() !== '');

// readRolled: the root CHANGELOG decoded and rolled, or { code, line } for a refusal.
function readRolled(file, version, deps) {
  let text;
  try {
    text = decode(deps.readFile(file));
  } catch (e) {
    if (e.causeName === 'encoding') return { code: EXIT.MALFORMED, line: LINES.encoding };
    throw e;
  }
  return rollOrRefuse(text, version);
}

// audit: writes the notes to a temp file outside the root, runs the audit once, removes the file on every path.
function audit(notes, root, online, deps) {
  const file = path.join(deps.tmpdir(), `aai-release-notes.${process.pid}.${crypto.randomBytes(6).toString('hex')}`);
  try {
    deps.writeFile(file, notes);
    const args = [path.join(path.dirname(fileURLToPath(import.meta.url)), AUDIT_SCRIPT), '--root', root, '--audit', file];
    if (online) args.push('--online');
    return deps.audit(args);
  } finally {
    deps.rm(file);
  }
}

const tagExists = (root, version, deps) => deps.git(['rev-parse', '-q', '--verify', `refs/tags/${version}`], root).status === 0;

function relay(r, deps) {
  for (const l of lines(r.stderr)) deps.err(l);
  return r.status || 1;
}

function plan(o, deps) {
  const rolled = readRolled(path.join(o.root, 'CHANGELOG.md'), o.version, deps);
  if (rolled.code) { deps.err(rolled.line); return rolled.code; }
  const tag = tagExists(o.root, o.version, deps);
  let origin = '';
  if (!o.ghBlock && !o.noRemote) {
    const p = deps.git(ORIGIN_PROBE, o.root);
    origin = p.status === 0 ? String(p.stdout).trim() : '';
  }
  const r = audit(rolled.notes, o.root, onlineAllowed({ ghBlock: o.ghBlock, noRemote: o.noRemote, origin }), deps);
  if (r.status !== 0) return relay(r, deps);
  for (const l of planLines({ ...o, tagExists: tag, headings: rolledHeadings(rolled.content, o.version), notes: rolled.notes, unlogged: lines(r.stdout) })) deps.out(l);
  return 0;
}

function check(o, deps) {
  const rolled = readRolled(path.join(o.root, 'CHANGELOG.md'), o.version, deps);
  if (rolled.code) { deps.err(rolled.line); return rolled.code; }
  if (tagExists(o.root, o.version, deps)) { deps.err(`REFUSED: tag ${o.version} already exists.`); return EXIT.TAG; }
  const r = audit(rolled.notes, o.root, false, deps);
  if (r.status !== 0) return relay(r, deps);
  const unlogged = lines(r.stdout);
  if (!unlogged.length) return 0;
  deps.err(`REFUSED: missing-notes — ${unlogged.join('; ')}`);
  deps.err(resumeLine(o.launcher, o.launcherPath, o.version));
  return EXIT.REFUSED;
}

// roll: decode and roll one file, then rename a temp file over it; a refusal leaves the file unchanged.
function roll(o, deps) {
  const rolled = readRolled(o.file, o.version, deps);
  if (rolled.code) { deps.err(rolled.line); return rolled.code; }
  const tmp = path.join(path.dirname(o.file), `.${path.basename(o.file)}.${crypto.randomBytes(6).toString('hex')}.tmp`);
  try {
    deps.writeFile(tmp, rolled.content);
    deps.rename(tmp, o.file);
  } finally {
    deps.rm(tmp);
  }
  return 0;
}

export function run(argv, deps) {
  const o = parseArgs(argv);
  if (o.error) { deps.err(o.error); return 1; }
  return { plan, check, roll }[o.cmd](o, deps);
}

const capture = (r) => ({ status: r.status ?? 1, stdout: r.stdout ?? '', stderr: r.error ? String(r.error.message) : (r.stderr ?? '') });

export function main(argv = process.argv.slice(2)) {
  // A reader that closes early (`| head -1`) ends the plan quietly with the SIGPIPE status, not a stack trace.
  process.stdout.on('error', (e) => { if (e.code === 'EPIPE') process.exit(141); throw e; });
  const spawn = (cmd, args, cwd) => capture(spawnSync(cmd, args, { cwd, encoding: 'utf8', maxBuffer: 64 << 20 }));
  return run(argv, {
    readFile: (p) => fs.readFileSync(p),
    writeFile: (p, d) => fs.writeFileSync(p, d),
    rename: (a, b) => fs.renameSync(a, b),
    rm: (p) => fs.rmSync(p, { force: true }),
    tmpdir: () => os.tmpdir(),
    git: (args, cwd) => spawn('git', args, cwd),
    audit: (args) => spawn(process.execPath, args),
    out: (l) => process.stdout.write(`${l}\n`),
    err: (l) => process.stderr.write(`${l}\n`),
  });
}

const realOrResolve = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) process.exitCode = main();
