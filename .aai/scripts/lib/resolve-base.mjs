// resolve-base.mjs - the one base-directory resolution shared by the updater, the bootstrap, the hook installer
// and the layer sync (docs/specs/SPEC-0310-spec-sync-on-node.md, D-BASE).
//
// The base directory is PWD when it is absolute and names the same device and inode as the working directory,
// else the working directory. Dependency-free; importing it has no side effect.
//
// The identity of a file is its device and inode read as bigint (DR-35): a Number cannot hold every id a file system hands
// out (Windows file ids pass 2**53), and a file system without inodes reports 0. Such an identity is unknown, and two
// unknown identities are compared by the real path spellings of the files, never taken for one file.

import fs from 'node:fs';
import path from 'node:path';

const statOrNull = (p) => {
  try {
    return fs.statSync(p, { bigint: true });
  } catch {
    return null;
  }
};

// idOf(v): the value as bigint when it is one or a safe integer Number, else null; zero is null too (no identity).
const idOf = (v) => {
  const n = typeof v === 'bigint' ? v : (Number.isSafeInteger(v) ? BigInt(v) : null);
  return n === null || n === 0n ? null : n;
};

// spelling(p, platform): the real path of p in the file system's own spelling (realpathSync.native, else realpathSync, else the
// resolved path when p does not exist), lower-cased on win32 where the file system is case-insensitive.
const spelling = (p, platform) => {
  let real;
  try {
    real = fs.realpathSync.native(p);
  } catch {
    try {
      real = fs.realpathSync(p);
    } catch {
      real = path.resolve(p);
    }
  }
  return platform === 'win32' ? real.toLowerCase() : real;
};

// sameFile(a, b, pathA, pathB, platform): a and b are stats (or { dev, ino }) of two files, pathA and pathB their paths. True when
// both identities are known and equal; when either is unknown, true only when both paths are given and have one real path
// spelling; never true for an unknown identity and no path.
export function sameFile(a, b, pathA = '', pathB = '', platform = process.platform) {
  if (!a || !b) return false;
  const [da, ia, db, ib] = [idOf(a.dev), idOf(a.ino), idOf(b.dev), idOf(b.ino)];
  if (da !== null && ia !== null && db !== null && ib !== null) return da === db && ia === ib;
  if (pathA === '' || pathB === '') return false;
  return spelling(pathA, platform) === spelling(pathB, platform);
}

// resolveBase(env, cwd): PWD resolved, but only when that resolved path is the working directory. The identity
// check applies to the very path that is returned: path.resolve folds '..' lexically while the OS follows a
// symbolic link first, so a PWD whose two readings differ is not trusted and the working directory wins.
export function resolveBase(env = process.env, cwd = process.cwd()) {
  const pwd = env.PWD;
  if (typeof pwd === 'string' && path.isAbsolute(pwd)) {
    const resolved = path.resolve(pwd);
    const a = statOrNull(resolved);
    const b = statOrNull(cwd);
    if (sameFile(a, b, resolved, cwd)) return resolved;
  }
  return cwd;
}

// resolveFromBase(rel, env, cwd): the base itself for an empty path, else the path resolved lexically against it
// (dot-dot goes up the logical path). CDPATH is not read.
export function resolveFromBase(rel = '', env = process.env, cwd = process.cwd()) {
  const base = resolveBase(env, cwd);
  return rel === '' ? base : path.resolve(base, rel);
}
