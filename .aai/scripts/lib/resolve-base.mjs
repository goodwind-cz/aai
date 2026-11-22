// resolve-base.mjs - the one base-directory resolution shared by the updater, the bootstrap, the hook installer
// and the layer sync (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, D-BASE).
//
// The base directory is PWD when it is absolute and names the same device and inode as the working directory,
// else the working directory. Dependency-free; importing it has no side effect.

import fs from 'node:fs';
import path from 'node:path';

const statOrNull = (p) => {
  try {
    return fs.statSync(p);
  } catch {
    return null;
  }
};

// resolveBase(env, cwd): PWD resolved, but only when that resolved path is the working directory. The identity
// check applies to the very path that is returned: path.resolve folds '..' lexically while the OS follows a
// symbolic link first, so a PWD whose two readings differ is not trusted and the working directory wins.
export function resolveBase(env = process.env, cwd = process.cwd()) {
  const pwd = env.PWD;
  if (typeof pwd === 'string' && path.isAbsolute(pwd)) {
    const resolved = path.resolve(pwd);
    const a = statOrNull(resolved);
    const b = statOrNull(cwd);
    if (a && b && a.dev === b.dev && a.ino === b.ino) return resolved;
  }
  return cwd;
}

// resolveFromBase(rel, env, cwd): the base itself for an empty path, else the path resolved lexically against it
// (dot-dot goes up the logical path). CDPATH is not read.
export function resolveFromBase(rel = '', env = process.env, cwd = process.cwd()) {
  const base = resolveBase(env, cwd);
  return rel === '' ? base : path.resolve(base, rel);
}
