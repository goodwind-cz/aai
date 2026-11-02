// checkout-trace.mjs - run-time access trace of a disposable checkout
// (CHANGE reuse-for-docs-reading-suites / SPEC spec-reuse-for-docs-reading-suites, D2).
//
// armTrace lists and hashes the checkout, then resets the access time of every
// entry to ATIME_FLOOR; collectTrace, after the suite ran, reports which files
// the operating system saw read (access time advanced), replaced (new inode)
// or deleted. Only ever called on a throwaway checkout: it rewrites timestamps.
// Node stdlib and ./tree-hash.mjs only.

import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { listTreeFiles } from './tree-hash.mjs';

export const ATIME_FLOOR = 946684800;
const ENV_NAME_RE = /\$\{?([A-Za-z_][A-Za-z0-9_]*)|process\.env\.([A-Za-z_]\w*)|\$env:([A-Za-z_]\w*)/g;
const MAX_TEXT_BYTES = 4 * 1024 * 1024;

const posix = (p) => p.split(path.sep).join('/');
const sha256 = (data) => createHash('sha256').update(data).digest('hex');
// A file's identity is its bytes plus its executable bit: chmod -x changes what a suite that runs it sees.
export const contentHash = (data, mode) => sha256(data) + ((mode & 0o111) ? ':x' : ':-');
const armFile = (runDir, suite) => path.join(runDir, `${suite}.reuse-arm.json`);
const traceFile = (runDir, suite) => path.join(runDir, `${suite}.reuse-trace.json`);

// Environment variable names a set of texts refers to (shell, node and powershell forms).
export function referencedNames(texts) {
  const names = new Set();
  for (const t of texts) for (const m of t.matchAll(ENV_NAME_RE)) names.add(m[1] || m[2] || m[3]);
  return [...names].sort();
}

// Every entry under dir (files and directories, .git included), children before their directory.
function walk(dir, visit) {
  const rec = (abs, rel) => {
    const st = fs.lstatSync(abs);
    if (st.isDirectory()) {
      for (const e of fs.readdirSync(abs)) rec(path.join(abs, e), rel ? `${rel}/${e}` : e);
    }
    visit(abs, rel, st);
  };
  rec(dir, '');
}

// True when reading a file whose access time was reset advances it (the file system records reads).
function atimeAdvances(dir, probe) {
  if (probe) return Boolean(probe(dir));
  const canary = path.join(path.dirname(dir), `.reuse-canary-${process.pid}`);
  try {
    fs.writeFileSync(canary, 'canary\n');
    const st = fs.lstatSync(canary);
    fs.utimesSync(canary, ATIME_FLOOR, st.mtime);
    fs.readFileSync(canary);
    return fs.lstatSync(canary).atimeMs / 1000 > ATIME_FLOOR;
  } catch { return false; } finally { try { fs.unlinkSync(canary); } catch { /* already gone */ } }
}

// armTrace({dir, runDir, suite, seedPaths, atimeProbe}) -> the arm record, also written to
// $runDir/<suite>.reuse-arm.json. Hashes are read BEFORE the reset, so the reset is the last touch.
export function armTrace({ dir, runDir, suite, seedPaths = [], atimeProbe }) {
  const paths = new Set(listTreeFiles(dir));
  for (const s of seedPaths) if (fs.existsSync(path.join(dir, s))) paths.add(s);
  const hashes = {};
  const inodes = {};
  const entries = [];
  walk(dir, (abs, rel, st) => {
    if (rel === '') return;
    entries.push([abs, st]);
    if (st.isDirectory()) return;
    inodes[rel] = st.ino;
    if (st.isFile() && !rel.startsWith('.git/')) hashes[rel] = contentHash(fs.readFileSync(abs), st.mode);
  });
  for (const [abs, st] of entries) {
    try { fs.lutimesSync(abs, ATIME_FLOOR, st.mtime); } catch { /* an entry that cannot be reset stays an unverified input */ }
  }
  try { const st = fs.lstatSync(dir); fs.lutimesSync(dir, ATIME_FLOOR, st.mtime); } catch { /* root left as is */ }
  const canary = atimeAdvances(dir, atimeProbe);
  const arm = { suite, run_id: path.basename(runDir), dir: fs.realpathSync(dir), canary, paths: [...paths].sort(), hashes, inodes };
  fs.mkdirSync(runDir, { recursive: true });
  fs.writeFileSync(armFile(runDir, suite), JSON.stringify(arm));
  return arm;
}

// collectTrace({dir, runDir, suite}) -> the trace, also written to $runDir/<suite>.reuse-trace.json;
// null when there is no usable arm record (then no trace file exists and nothing is recorded).
export function collectTrace({ dir, runDir, suite }) {
  let arm;
  try { arm = JSON.parse(fs.readFileSync(armFile(runDir, suite), 'utf8')); } catch { return null; }
  if (!arm || arm.suite !== suite || typeof arm.inodes !== 'object') return null;
  const seen = new Set();
  const read = new Set();
  walk(dir, (abs, rel, st) => {
    if (rel === '' || st.isDirectory() || !(rel in arm.inodes)) return;
    seen.add(rel);
    const armed = { ino: arm.inodes[rel] };
    const wasRead = st.atimeMs / 1000 > ATIME_FLOOR;
    if (wasRead || st.ino !== armed.ino) read.add(rel);
  });
  for (const rel of Object.keys(arm.inodes)) if (!seen.has(rel)) read.add(rel);
  const inputs = {};
  const texts = [];
  for (const rel of [...read].sort()) {
    if (rel.startsWith('.git/')) { inputs[rel] = null; continue; }
    inputs[rel] = arm.hashes[rel] === undefined ? null : arm.hashes[rel];
    try {
      const abs = path.join(dir, rel);
      if (fs.statSync(abs).size <= MAX_TEXT_BYTES) texts.push(fs.readFileSync(abs, 'utf8'));
    } catch { /* deleted or unreadable: no names from it */ }
  }
  const indexRead = read.has('.git/index');
  const trace = {
    suite, run_id: path.basename(runDir), canary: arm.canary === true,
    git_read: [...read].some((r) => r.startsWith('.git/')), index_read: indexRead,
    inputs, paths: arm.paths, env_names: referencedNames(texts),
  };
  if (indexRead) trace.tree_hashes = Object.fromEntries(arm.paths.filter((p) => arm.hashes[p] !== undefined).map((p) => [p, arm.hashes[p]]));
  fs.writeFileSync(traceFile(runDir, suite), JSON.stringify(trace));
  return trace;
}
