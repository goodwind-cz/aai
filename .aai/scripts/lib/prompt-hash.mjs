// prompt-hash.mjs — content-addressed identity of the EFFECTIVE instruction
// stack a role ran under (prompt-hash-telemetry /
// SPEC-0096-spec-prompt-hash-telemetry, Spec-AC-01).
//
// computeEffectivePromptHash(rolePromptPath, root) hashes, in fixed order:
//   1. the role prompt file (e.g. .aai/VALIDATION.prompt.md)
//   2. .aai/SUBAGENT_CONTRACT.md
//   3. docs/knowledge/LEARNED.md
// Each section is framed by a stable filename separator (the file's basename)
// so a byte moving between sections still changes the digest. A missing
// input contributes the literal ABSENT marker in place of its bytes instead
// of throwing — the hash is always computable, never a hard failure.
//
// `root` is optional (default process.cwd()) so a caller invoked from the
// repo root can pass just the role prompt path; tests point `root` at a
// throwaway fixture tree without touching the real .aai/SUBAGENT_CONTRACT.md
// or docs/knowledge/LEARNED.md.
//
// Node stdlib only (node:crypto, node:fs, node:path) — zero new dependencies
// (TECHNOLOGY.md hard constraint).

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const CONTRACT_REL = '.aai/SUBAGENT_CONTRACT.md';
const LEARNED_REL = 'docs/knowledge/LEARNED.md';
const ABSENT = 'ABSENT';

// Best-effort read; a missing/unreadable file (any reason) resolves to null
// rather than throwing — the hash function itself never throws.
function readOrNull(absPath) {
  try {
    return fs.readFileSync(absPath, 'utf8');
  } catch {
    return null;
  }
}

// computeEffectivePromptHash(rolePromptPath, root = process.cwd())
//   rolePromptPath: absolute, or relative to `root`.
// Returns a lowercase 64-char sha256 hex digest. Never throws.
function computeEffectivePromptHash(rolePromptPath, root = process.cwd()) {
  const roleAbs = path.isAbsolute(rolePromptPath) ? rolePromptPath : path.resolve(root, rolePromptPath);
  const sections = [
    { name: path.basename(String(rolePromptPath)), abs: roleAbs },
    { name: path.basename(CONTRACT_REL), abs: path.resolve(root, CONTRACT_REL) },
    { name: path.basename(LEARNED_REL), abs: path.resolve(root, LEARNED_REL) },
  ];

  const hash = crypto.createHash('sha256');
  for (const s of sections) {
    const body = readOrNull(s.abs);
    hash.update(`\n--- ${s.name} ---\n`);
    hash.update(body === null ? ABSENT : body);
  }
  return hash.digest('hex');
}

// First 12 hex chars of a full 64-char digest — the display/grouping form.
function shortHash(hash) {
  return typeof hash === 'string' ? hash.slice(0, 12) : hash;
}

export { computeEffectivePromptHash, shortHash, ABSENT };
