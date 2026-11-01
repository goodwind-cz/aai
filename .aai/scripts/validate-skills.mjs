#!/usr/bin/env node
// validate-skills.mjs - check that the AAI prompts and the bootstrap script exist in a target root
// (RFC-0017 small-pairs slice). Output is the bash copy's: first missing path stops with exit 1.
// validate-skills.sh and validate-skills.ps1 are thin launchers. Writes nothing, reads no stdin.
import { readFileSync, realpathSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REQUIRED = [
  '.aai/SKILL_CHECK_STATE.prompt.md', '.aai/SKILL_INTAKE.prompt.md', '.aai/SKILL_LOOP.prompt.md',
  '.aai/SKILL_HITL.prompt.md', '.aai/SKILL_BOOTSTRAP.prompt.md', '.aai/SKILL_VALIDATE_REPORT.prompt.md',
  '.aai/SKILL_CANONICALIZE.prompt.md', '.aai/SKILL_TDD.prompt.md', '.aai/SKILL_WORKTREE.prompt.md',
  '.aai/SKILL_CODE_REVIEW.prompt.md', '.aai/SKILL_SHARE.prompt.md', '.aai/scripts/aai-bootstrap.sh',
];
const isFile = (p) => { try { return statSync(p).isFile(); } catch { return false; } };
const isDir = (p) => { try { return statSync(p).isDirectory(); } catch { return false; } };
const TICK = '"mode":"skill"';
const WARN = 'WARN: ';
const MISSING = 'ERROR: Missing required file: ';
const NOT_FOUND = 'ERROR: Target not found: ';

export function validate(target) {
  if (!isDir(target)) return { code: 1, out: [], err: [NOT_FOUND + target] };
  const root = path.resolve(target);
  const out = ['Validating skills in: ' + root];
  const first = REQUIRED.map((r) => path.join(root, r)).find((p) => !isFile(p));
  if (first) return { code: 1, out, err: [MISSING + first] };
  const marker = '.claude/skills/AAI_DYNAMIC_SKILLS.md';
  out.push(isFile(path.join(root, marker))
    ? 'OK: dynamic skills bootstrap marker exists (' + marker + ')'
    : WARN + 'Missing ' + marker + ' (bootstrap may not have run yet).');
  const ticks = path.join(root, 'docs/ai/LOOP_TICKS.jsonl');
  if (!isFile(ticks)) out.push(WARN + 'Missing docs/ai/LOOP_TICKS.jsonl (no runtime evidence yet).');
  else if (readFileSync(ticks, 'utf8').includes(TICK)) out.push('OK: LOOP_TICKS.jsonl contains skill-mode evidence.');
  else out.push(WARN + 'LOOP_TICKS.jsonl has no skill-mode entries yet.');
  out.push('Skill validation completed.');
  return { code: 0, out, err: [] };
}

export function main(argv) {
  const r = validate(argv[0] || '.');
  if (r.out.length) process.stdout.write(r.out.join('\n') + '\n');
  if (r.err.length) process.stderr.write(r.err.join('\n') + '\n');
  return r.code;
}

const realOrResolve = (p) => { try { return realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) process.exitCode = main(process.argv.slice(2));
