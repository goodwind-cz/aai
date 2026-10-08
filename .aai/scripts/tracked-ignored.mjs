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
//   node .aai/scripts/tracked-ignored.mjs --staged
//
// OUTPUT (--all)
//   TRACKED_IGNORED <path> rule=<source>:<line>:<pattern>   (one per path, exit 1)
//   TRACKED_IGNORED none checked=<n>                         (n > 0, exit 0)
//
// OUTPUT (--staged: index versus HEAD, `--no-renames` so a rename INTO an
// ignored path is a delete plus an ADD)
//   IGNORED_ADDED <path> rule=<...>      added/copied path the rules match (exit 1)
//   IGNORED_MODIFIED <path> rule=<...>   modified/type-changed tracked ignored path
//   IGNORED_PREEXISTING count=<n>        tracked ignored paths this commit does not touch
//   (deletions are never reported: untracking is the remedy)
//
// EXIT: 0 clean, 1 tracked ignored path(s) found (--staged: an ADDED one),
// 2 usage or git failure (never a silent 0).
//
// Node stdlib only; no imports from sibling scripts (fixtures copy this file
// alone). Exported: trackedIgnored({cwd, rev, paths, pathspecs, nameRulesFor}), stagedIgnored({cwd}),
// ignoreRules(cwd, paths), ignoredByGitignore(cwd, paths).

import { spawnSync } from 'node:child_process';
import { mkdtempSync, realpathSync, rmSync } from 'node:fs';
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

// ignoreRules(cwd, paths) -> Map(path -> {source, line, pattern}) for every
// path git's ignore machinery decides on, one `check-ignore` process for the
// whole batch. core.excludesFile is emptied so a developer's global file cannot
// be named as the source; .git/info/exclude CAN still be named (git always
// reads it) -- callers that must count repository rules only filter on the
// source (see ignoredByGitignore). Works for paths that do not exist.
export function ignoreRules(cwd, paths) {
  const out = new Map();
  if (!paths || paths.length === 0) return out;
  const r = spawnSyncInput(
    cwd,
    ['-c', 'core.excludesFile=', 'check-ignore', '-v', '--no-index', '-z', '--stdin'],
    {},
    paths.join('\0') + '\0',
  );
  if (r.status !== 0 && r.status !== 1) return out;
  const f = splitNul(r.stdout || '');
  for (let i = 0; i + 3 < f.length; i += 4) {
    out.set(f[i + 3], { source: f[i], line: f[i + 1], pattern: f[i + 2] });
  }
  return out;
}

// ignoredByGitignore(cwd, paths) -> Set of the paths the repository's own
// .gitignore files ignore. The single D1 predicate for untracked/not-yet-present
// paths (the evidence rescue): a decision taken by .git/info/exclude (or any
// non-.gitignore source) or a `!` re-include does NOT count.
export function ignoredByGitignore(cwd, paths) {
  const ok = new Set();
  for (const [p, rule] of ignoreRules(cwd, paths)) {
    const base = String(rule.source).split(/[\\/]/).pop();
    if (base === '.gitignore' && !String(rule.pattern).startsWith('!')) ok.add(p);
  }
  return ok;
}

function ruleText(m, p) {
  const r = m.get(p);
  return r ? `${r.source}:${r.line}:${r.pattern}` : 'unknown';
}

// `pathspecs` limits the scan to those paths (a directory covers everything
// under it); each is passed literally so glob characters are not patterns.
// `nameRulesFor` (a Set) limits the rule lookup to those paths; the rest read
// 'unknown' (--staged never prints the rule of a pre-existing hit).
export function trackedIgnored({ cwd, rev, paths, pathspecs, nameRulesFor } = {}) {
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
    const spec = pathspecs && pathspecs.length ? ['--', ...pathspecs.map((p) => `:(literal)${p}`)] : [];
    const tracked = splitNul(gitOk(top, ['ls-files', '-z', ...spec], env));
    const ignored = splitNul(
      gitOk(top, ['ls-files', '-z', '-ci', '--exclude-per-directory=.gitignore', ...spec], env),
    );
    const want = paths ? new Set(paths) : null;
    const wanted = want ? ignored.filter((p) => want.has(p)) : ignored;
    const named = ignoreRules(top, nameRulesFor ? wanted.filter((p) => nameRulesFor.has(p)) : wanted);
    const hits = wanted.map((p) => ({ path: p, rule: ruleText(named, p) }));
    return { checked: want ? tracked.filter((p) => want.has(p)).length : tracked.length, hits };
  } finally {
    if (tmp) rmSync(tmp, { recursive: true, force: true });
  }
}

// Index versus HEAD. `--no-renames` turns a rename into delete + add, so a
// rename INTO an ignored path is caught as an add.
export function stagedIgnored({ cwd } = {}) {
  const top = gitOk(resolve(cwd || process.cwd()), ['rev-parse', '--show-toplevel']).trim();
  if (!top) throw new Error('not inside a git work tree');
  const diff = (filter) =>
    splitNul(gitOk(top, ['diff', '--cached', '--name-only', '--no-renames', '-z', `--diff-filter=${filter}`]));
  const added = new Set(diff('AC'));
  const modified = new Set(diff('MT'));
  const { hits } = trackedIgnored({ cwd: top, nameRulesFor: new Set([...added, ...modified]) });
  const out = { added: [], modified: [], preexisting: 0 };
  for (const h of hits) {
    if (added.has(h.path)) out.added.push(h);
    else if (modified.has(h.path)) out.modified.push(h);
    else out.preexisting += 1;
  }
  return out;
}

function usage(msg) {
  process.stderr.write(`${msg ? msg + '\n' : ''}usage: tracked-ignored.mjs --all [--rev <rev>] | --staged\n`);
  process.exit(2);
}

function main(argv) {
  let all = false;
  let staged = false;
  let rev = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--all') all = true;
    else if (a === '--staged') staged = true;
    else if (a === '--rev') {
      rev = argv[++i];
      if (!rev) usage('--rev needs a value');
    } else usage(`unknown argument: ${a}`);
  }
  if (all === staged) usage('exactly one of --all or --staged is required');
  if (staged && rev) usage('--rev applies to --all only');
  if (staged) {
    let st;
    try {
      st = stagedIgnored({});
    } catch (e) {
      process.stderr.write(`tracked-ignored: ${e.message}\n`);
      process.exit(2);
    }
    for (const h of st.added) process.stdout.write(`IGNORED_ADDED ${h.path} rule=${h.rule}\n`);
    for (const h of st.modified) process.stdout.write(`IGNORED_MODIFIED ${h.path} rule=${h.rule}\n`);
    if (st.preexisting > 0) process.stdout.write(`IGNORED_PREEXISTING count=${st.preexisting}\n`);
    process.exit(st.added.length > 0 ? 1 : 0);
  }
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

function realOrResolve(p) {
  try { return realpathSync(p); } catch { return resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main(process.argv.slice(2));
}
