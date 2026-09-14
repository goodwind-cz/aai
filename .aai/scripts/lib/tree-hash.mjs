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

// A tree hash over PATH + CONTENT for every file listTreeFiles returns, so it
// is comparable between two independent working trees (the source and the
// clone) without either being a git object store of the other, AND
// comparable against ITSELF at two points in time (the D7 tripwire).
export function computeTreeHash(dir) {
  const files = listTreeFiles(dir);
  const h = createHash('sha256');
  for (const rel of files) {
    let bytes;
    try {
      bytes = fs.readFileSync(path.join(dir, rel));
    } catch {
      continue; // a symlink to nowhere, or a race — never fatal to the hash
    }
    const fileHash = createHash('sha256').update(bytes).digest('hex');
    h.update(`${rel}\0${fileHash}\n`);
  }
  return h.digest('hex');
}
