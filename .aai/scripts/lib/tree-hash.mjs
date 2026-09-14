// tree-hash.mjs — a content+path hash over a git working tree, excluding
// docs/ai/tdd/** on both listing and hashing (SPEC-DRAFT
// spec-mutation-gate-for-tests D4 step 4, D7). ONE module, imported by BOTH
// the clone-vs-source comparison (D4) and the runner's OWN before/after
// shipping-tree tripwire (D7), so the two checks can never drift apart —
// and by any fixture test that needs to assert the SAME property from
// outside the tool (never a re-implementation of the hash shape).
//
// Node stdlib only (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const EXCLUDED_PREFIX = 'docs/ai/tdd';

function isExcluded(rel) {
  return rel === EXCLUDED_PREFIX || rel.startsWith(`${EXCLUDED_PREFIX}/`);
}

// git ls-files (tracked) + git ls-files --others --exclude-standard
// (untracked, not ignored), EXCLUDING docs/ai/tdd/** on both sides: the
// evidence this tool writes must never be able to change the verdict it is
// about to record, or the shipping-tree tripwire it computes after the fact.
export function listTreeFiles(dir) {
  const tracked = execFileSync('git', ['-C', dir, 'ls-files'], { encoding: 'utf8' });
  const untracked = execFileSync('git', ['-C', dir, 'ls-files', '--others', '--exclude-standard'], { encoding: 'utf8' });
  const all = new Set();
  for (const raw of [tracked, untracked]) {
    for (const line of raw.split('\n')) {
      const p = line.trim();
      if (!p) continue;
      if (isExcluded(p)) continue;
      all.add(p);
    }
  }
  return [...all].sort();
}

// computeTreeFileHashes(dir) -> Map<relPath, sha256Hex> for every file
// listTreeFiles returns. The per-file breakdown a caller needs to name WHICH
// path changed (NB2-r2) — computeTreeHash below collapses this into one
// digest, which is enough to DETECT a change but not to name it.
export function computeTreeFileHashes(dir) {
  const files = listTreeFiles(dir);
  const map = new Map();
  for (const rel of files) {
    let bytes;
    try {
      bytes = fs.readFileSync(path.join(dir, rel));
    } catch {
      continue; // a symlink to nowhere, or a race — never fatal to the hash
    }
    map.set(rel, createHash('sha256').update(bytes).digest('hex'));
  }
  return map;
}

// hashFromFileHashes(map) -> the same digest computeTreeHash produces, built
// from an already-collected computeTreeFileHashes() map — so a caller that
// needs BOTH the summary hash and the ability to name a changed path computes
// the map once and derives both from it, rather than walking the tree twice.
export function hashFromFileHashes(map) {
  const h = createHash('sha256');
  for (const rel of [...map.keys()].sort()) {
    h.update(`${rel}\0${map.get(rel)}\n`);
  }
  return h.digest('hex');
}

// A tree hash over PATH + CONTENT for every file listTreeFiles returns, so it
// is comparable between two independent working trees (the source and the
// clone) without either being a git object store of the other, AND
// comparable against ITSELF at two points in time (the D7 tripwire).
export function computeTreeHash(dir) {
  return hashFromFileHashes(computeTreeFileHashes(dir));
}

// diffTreeFileHashes(before, after) -> { added, removed, changed } (each a
// sorted array of repo-relative paths), comparing two computeTreeFileHashes()
// maps taken at two points in time over the SAME directory. NB2-r2: when the
// D7 tripwire fires, this is what turns "the tree hash moved" into "THIS path
// moved" — the runner's own write and a concurrent editor's write both trip
// the summary hash identically, but only naming the path lets an operator
// tell them apart.
export function diffTreeFileHashes(before, after) {
  const added = [];
  const removed = [];
  const changed = [];
  for (const [rel, hash] of after) {
    if (!before.has(rel)) added.push(rel);
    else if (before.get(rel) !== hash) changed.push(rel);
  }
  for (const rel of before.keys()) {
    if (!after.has(rel)) removed.push(rel);
  }
  added.sort();
  removed.sort();
  changed.sort();
  return { added, removed, changed };
}

// describeTreeDiff(diff) -> one-line human-readable summary of a
// diffTreeFileHashes() result, e.g. "changed: a.txt, b.txt; added: c.txt".
// Empty when nothing is named (should not happen when the caller only calls
// this after confirming the hashes actually differ).
export function describeTreeDiff({ added, removed, changed }) {
  const parts = [];
  if (changed.length) parts.push(`changed: ${changed.join(', ')}`);
  if (added.length) parts.push(`added: ${added.join(', ')}`);
  if (removed.length) parts.push(`removed: ${removed.join(', ')}`);
  return parts.join('; ') || '(no path named — the hash differs but no per-file diff found one; a race in the diff itself)';
}
