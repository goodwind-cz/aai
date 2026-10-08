#!/usr/bin/env node
//
// tracked-ignored.mjs — the one predicate for "is a tracked path ignored by
// the repository" (CHANGE post-validation-pushes-reuse-test-results /
// SPEC spec-post-validation-pushes-reuse-test-results, D1).
//
// Rules counted: the repository's own per-directory .gitignore files only
// (`git ls-files -ci` with the per-directory exclude option). Global
// core.excludesFile and .git/info/exclude are deliberately NOT counted: they
// are per-machine, CI has neither, and a developer's private excludes must
// not refuse what CI accepts.
//
// USAGE
//   node .aai/scripts/tracked-ignored.mjs --all [--rev <rev>]
//
// OUTPUT (--all)
//   TRACKED_IGNORED <path> rule=<source>:<line>:<pattern>   (one per path, exit 1)
//   TRACKED_IGNORED none checked=<n>                         (n > 0, exit 0)
//
// EXIT: 0 clean, 1 tracked ignored path(s) found, 2 usage or git failure
// (never a silent 0). `--staged` mode is reserved for a later batch.
//
// Node stdlib only; no imports from sibling scripts (fixtures copy this file
// alone). Exported: trackedIgnored({cwd, rev, paths}).

import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const MAX_BUFFER = 256 * 1024 * 1024;

function git(cwd, args, env) {
  const r = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
    maxBuffer: MAX_BUFFER,
    env: { ...process.env, ...(env || {}) },
  });
  if (r.error) throw new Error(`git ${args.join(' ')}: ${r.error.message}`);
  return r;
}

function gitOk(cwd, args, env, input) {
  const r = input === undefined ? git(cwd, args, env) : spawnSyncInput(cwd, args, env, input);
  if (r.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed (exit ${r.status}): ${(r.stderr || '').trim()}`);
  }
  return r.stdout;
}

function spawnSyncInput(cwd, args, env, input) {
  const r = spawnSync('git', args, {
    cwd,
    input,
    encoding: 'utf8',
    maxBuffer: MAX_BUFFER,
    env: { ...process.env, ...(env || {}) },
  });
  if (r.error) throw new Error(`git ${args.join(' ')}: ${r.error.message}`);
  return r;
}

function splitNul(s) {
  return s.split('\0').filter((x) => x.length > 0);
}

// Names the rule best-effort. core.excludesFile is emptied so a developer's
// global file cannot be named as the source; .git/info/exclude can still be
// named for a path ALSO matched by a repo rule only if it comes first, hence
// "best effort" (exact on CI, which has neither).
function ruleFor(cwd, path) {
  const r = spawnSyncInput(
    cwd,
    ['-c', 'core.excludesFile=', 'check-ignore', '-v', '--no-index', '-z', '--stdin'],
    {},
    path + '\0',
  );
  if (r.status === 0) {
    const f = splitNul(r.stdout);
    if (f.length >= 4) return `${f[0]}:${f[1]}:${f[2]}`;
  }
  return 'unknown';
}

export function trackedIgnored({ cwd, rev, paths } = {}) {
  const top = gitOk(resolve(cwd || process.cwd()), ['rev-parse', '--show-toplevel']).trim();
  if (!top) throw new Error('not inside a git work tree');
  let env = {};
  let tmp = null;
  try {
    if (rev) {
      gitOk(top, ['rev-parse', '--verify', '--quiet', `${rev}^{tree}`]);
      tmp = mkdtempSync(join(tmpdir(), 'tracked-ignored-'));
      env = { GIT_INDEX_FILE: join(tmp, 'index') };
      gitOk(top, ['read-tree', rev], env);
    }
    const tracked = splitNul(gitOk(top, ['ls-files', '-z'], env));
    const ignored = splitNul(
      gitOk(top, ['ls-files', '-z', '-ci', '--exclude-per-directory=.gitignore'], env),
    );
    const want = paths ? new Set(paths) : null;
    const hits = (want ? ignored.filter((p) => want.has(p)) : ignored).map((p) => ({
      path: p,
      rule: ruleFor(top, p),
    }));
    return { checked: want ? tracked.filter((p) => want.has(p)).length : tracked.length, hits };
  } finally {
    if (tmp) rmSync(tmp, { recursive: true, force: true });
  }
}

function usage(msg) {
  process.stderr.write(`${msg ? msg + '\n' : ''}usage: tracked-ignored.mjs --all [--rev <rev>]\n`);
  process.exit(2);
}

function main(argv) {
  let all = false;
  let rev = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--all') all = true;
    else if (a === '--rev') {
      rev = argv[++i];
      if (!rev) usage('--rev needs a value');
    } else usage(`unknown argument: ${a}`);
  }
  if (!all) usage('--all is required');
  let res;
  try {
    res = trackedIgnored({ rev });
  } catch (e) {
    process.stderr.write(`tracked-ignored: ${e.message}\n`);
    process.exit(2);
  }
  if (res.hits.length === 0) {
    if (res.checked === 0) {
      process.stderr.write('tracked-ignored: no tracked paths to check (checked=0)\n');
      process.exit(2);
    }
    process.stdout.write(`TRACKED_IGNORED none checked=${res.checked}\n`);
    process.exit(0);
  }
  for (const h of res.hits) process.stdout.write(`TRACKED_IGNORED ${h.path} rule=${h.rule}\n`);
  process.exit(1);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2));
}
