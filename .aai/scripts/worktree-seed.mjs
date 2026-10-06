#!/usr/bin/env node
// Copy the installed AAI snapshot into a linked worktree without changing Git or STATE.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const roots = ['.aai', '.agents/skills', '.claude/skills', '.codex/skills', '.gemini/skills'];
const required = ['.aai/AGENTS.md', '.aai/ORCHESTRATION.prompt.md', '.aai/SKILL_WORKTREE.prompt.md', '.aai/scripts/check-state.mjs', '.aai/scripts/state.mjs', '.aai/templates/STATE_TEMPLATE.yaml', '.aai/system/AAI_PIN.md'];
const refuse = (reason, detail) => { throw new Error(`${reason}: ${detail}`); };
function git(root, args) {
  const run = spawnSync('git', ['-C', root, ...args], { encoding: 'utf8' });
  if (run.error || run.status !== 0) refuse('GIT', `${args.join(' ')} at ${root}: ${(run.stderr || run.error?.message || '').trim()}`);
  return run.stdout.trimEnd();
}
function statNoLink(file) {
  const stat = fs.lstatSync(file);
  if (stat.isSymbolicLink()) refuse('SYMLINK', file);
  return stat;
}
function existingPath(root, rel) {
  let current = root;
  for (const part of rel.split('/')) {
    current = path.join(current, part);
    const stat = fs.lstatSync(current, { throwIfNoEntry: false });
    if (stat?.isSymbolicLink()) refuse('SYMLINK', current);
    if (stat && current !== path.join(root, rel) && !stat.isDirectory()) refuse('DESTINATION_TYPE', current);
  }
  return current;
}
function digest(file) { return createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function inventory(source) {
  const files = [], skipped = [];
  function walk(rel) {
    const full = path.join(source, rel), stat = statNoLink(full);
    if (stat.isFile()) { files.push(rel); return; }
    if (!stat.isDirectory()) refuse('SOURCE_TYPE', full);
    for (const name of fs.readdirSync(full).sort()) {
      if (name === '.git' || (rel === '.aai' && name === 'cache') || name === 'skills.local') continue;
      walk(`${rel}/${name}`);
    }
  }
  for (const rel of roots) {
    const full = existingPath(source, rel);
    if (!fs.lstatSync(full, { throwIfNoEntry: false })) {
      if (rel === '.aai') refuse('SOURCE_MISSING', full);
      skipped.push(rel);
    } else walk(rel);
  }
  for (const rel of required) if (!files.includes(rel)) refuse('SOURCE_MISSING', path.join(source, rel));
  return { files, skipped };
}
function canonicalRoot(value, label) {
  if (!value || !path.isAbsolute(value)) refuse('ROOT', `${label} must be absolute: ${value}`);
  const root = fs.realpathSync(value);
  if (!statNoLink(root).isDirectory()) refuse('ROOT', `${label} is not a directory: ${root}`);
  if (path.resolve(git(root, ['rev-parse', '--show-toplevel'])) !== root) refuse('ROOT', `${label} is not a Git root: ${root}`);
  return root;
}
function seed(source, target) {
  if (source === target || target.startsWith(source + path.sep) || source.startsWith(target + path.sep)) refuse('ROOT_OVERLAP', `${source} -> ${target}`);
  const common = root => fs.realpathSync(path.resolve(root, git(root, ['rev-parse', '--git-common-dir'])));
  if (common(source) !== common(target)) refuse('FOREIGN_WORKTREE', `${source} -> ${target}`);
  if (fs.realpathSync(path.resolve(target, git(target, ['rev-parse', '--git-dir']))) === common(target)) refuse('NOT_LINKED_WORKTREE', target);
  const registered = git(source, ['worktree', 'list', '--porcelain']).split('\n').filter(line => line.startsWith('worktree ')).map(line => line.slice(9));
  const targetRegistered = registered.some(candidate => {
    if (path.resolve(candidate) === target) return true;
    try { return fs.realpathSync(candidate) === target; }
    // A stale or inaccessible sibling says nothing about the already
    // canonicalized target. Only a successfully resolved candidate can match.
    catch { return false; }
  });
  if (!targetRegistered) refuse('NOT_REGISTERED', target);
  const { files, skipped } = inventory(source);
  const tracked = new Set(git(target, ['ls-files', '-z']).split('\0').filter(Boolean));
  const pending = [];
  let preserved = 0;
  for (const rel of files) {
    const src = path.join(source, rel), dst = existingPath(target, rel);
    if (tracked.has(rel)) { preserved++; continue; }
    const stat = fs.lstatSync(dst, { throwIfNoEntry: false });
    if (stat) {
      if (!stat.isFile()) refuse('DESTINATION_TYPE', dst);
      if (digest(src) !== digest(dst)) refuse('DESTINATION_CONFLICT', dst);
      continue;
    }
    const ignored = spawnSync('git', ['-C', target, 'check-ignore', '--no-index', '-q', '--', rel], { encoding: 'utf8' });
    if (ignored.error || ignored.status !== 0) refuse('IGNORE_UNSAFE', `${rel} at ${target}: ${ignored.stderr?.trim() || 'not ignored'}`);
    pending.push(rel);
  }
  for (const rel of pending) {
    const src = path.join(source, rel), dst = path.join(target, rel);
    try {
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      fs.copyFileSync(src, dst, fs.constants.COPYFILE_EXCL);
      fs.chmodSync(dst, fs.statSync(src).mode & 0o777);
      if (digest(src) !== digest(dst)) refuse('VERIFY_MISMATCH', dst);
    } catch (error) { refuse('COPY_FAILED', `${src} -> ${dst}: ${error.message}`); }
  }
  console.log(`SEEDED: ${pending.length} copied; ${preserved} tracked preserved; optional roots skipped: ${skipped.join(', ') || 'none'}`);
}
try {
  const args = process.argv.slice(2);
  if (args.length !== 4 || args[0] !== '--source' || args[2] !== '--target') refuse('USAGE', 'worktree-seed.mjs --source <absolute-root> --target <absolute-root>');
  seed(canonicalRoot(args[1], 'source'), canonicalRoot(args[3], 'target'));
} catch (error) {
  console.error(`WORKTREE-SEED-REFUSED ${error.message}`);
  process.exitCode = 1;
}
