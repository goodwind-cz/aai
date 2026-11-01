// validate-skills.test.mjs - node:test cases for .aai/scripts/validate-skills.mjs
// (docs/specs/SPEC-DRAFT-spec-node-first-small-pairs.md, TEST-3201 and TEST-3202).
// Direct imports of validate(), temporary directories only.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { REQUIRED, validate } from '../../../.aai/scripts/validate-skills.mjs';

const WANT = [
  '.aai/SKILL_CHECK_STATE.prompt.md', '.aai/SKILL_INTAKE.prompt.md', '.aai/SKILL_LOOP.prompt.md',
  '.aai/SKILL_HITL.prompt.md', '.aai/SKILL_BOOTSTRAP.prompt.md', '.aai/SKILL_VALIDATE_REPORT.prompt.md',
  '.aai/SKILL_CANONICALIZE.prompt.md', '.aai/SKILL_TDD.prompt.md', '.aai/SKILL_WORKTREE.prompt.md',
  '.aai/SKILL_CODE_REVIEW.prompt.md', '.aai/SKILL_SHARE.prompt.md', '.aai/scripts/aai-bootstrap.sh',
];
const MARKER = '.claude/skills/AAI_DYNAMIC_SKILLS.md';
const TICKS = 'docs/ai/LOOP_TICKS.jsonl';
const made = [];
after(() => { for (const d of made) fs.rmSync(d, { recursive: true, force: true }); });

// fixture({ skip, dirs, marker, ticks }): a root holding the required files, minus skip, with dirs as directories.
function fixture({ skip = [], dirs = [], marker = false, ticks = null } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-vs-'));
  made.push(root);
  const put = (rel, text) => { fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true }); fs.writeFileSync(path.join(root, rel), text); };
  for (const rel of WANT) {
    if (dirs.includes(rel)) fs.mkdirSync(path.join(root, rel), { recursive: true });
    else if (!skip.includes(rel)) put(rel, '');
  }
  if (marker) put(MARKER, '');
  if (ticks !== null) put(TICKS, ticks);
  return root;
}
const headLine = (root) => 'Validating skills in: ' + path.resolve(root);

test('TEST-3201 REQUIRED holds the twelve baseline paths in order', () => {
  assert.deepEqual(REQUIRED, WANT);
});

test('TEST-3201 a full fixture gives exit 0 and the four bash lines', () => {
  const root = fixture({ marker: true, ticks: '{"mode":"skill"}\n' });
  assert.deepEqual(validate(root), {
    code: 0,
    out: [headLine(root), 'OK: dynamic skills bootstrap marker exists (.claude/skills/AAI_DYNAMIC_SKILLS.md)',
      'OK: LOOP_TICKS.jsonl contains skill-mode evidence.', 'Skill validation completed.'],
    err: [],
  });
});

test('TEST-3201 the first missing path in REQUIRED order is the only one named', () => {
  const root = fixture({ skip: ['.aai/SKILL_SHARE.prompt.md', '.aai/SKILL_TDD.prompt.md'], marker: true });
  const r = validate(root);
  assert.equal(r.code, 1);
  assert.deepEqual(r.out, [headLine(root)]);
  assert.deepEqual(r.err, ['ERROR: Missing required file: ' + path.join(root, '.aai/SKILL_TDD.prompt.md')]);
});

test('TEST-3201 a directory at a required path counts as missing (V-3)', () => {
  const root = fixture({ dirs: ['.aai/SKILL_TDD.prompt.md'], marker: true });
  const r = validate(root);
  assert.equal(r.code, 1);
  assert.deepEqual(r.err, ['ERROR: Missing required file: ' + path.join(root, '.aai/SKILL_TDD.prompt.md')]);
});

test('TEST-3201 the last required file missing is still caught (negative control)', () => {
  const root = fixture({ skip: ['.aai/scripts/aai-bootstrap.sh'] });
  const r = validate(root);
  assert.equal(r.code, 1);
  assert.equal(r.err.length, 1);
  assert.match(r.err[0], /aai-bootstrap\.sh$/);
});

test('TEST-3202 a required-only fixture gives the two WARN lines on stdout and nothing on stderr', () => {
  const root = fixture();
  assert.deepEqual(validate(root), {
    code: 0,
    out: [headLine(root), 'WARN: Missing .claude/skills/AAI_DYNAMIC_SKILLS.md (bootstrap may not have run yet).',
      'WARN: Missing docs/ai/LOOP_TICKS.jsonl (no runtime evidence yet).', 'Skill validation completed.'],
    err: [],
  });
});

test('TEST-3202 a tick log without a skill entry gives the no-skill-mode WARN', () => {
  const root = fixture({ marker: true, ticks: '{"mode":"other"}\n' });
  const r = validate(root);
  assert.equal(r.code, 0);
  assert.deepEqual(r.out.slice(2), ['WARN: LOOP_TICKS.jsonl has no skill-mode entries yet.', 'Skill validation completed.']);
});

test('TEST-3202 the CRLF tick log with a space after the colon also gives it (V-5)', () => {
  const root = fixture({ marker: true, ticks: '{"mode": "skill"}\r\n{"mode": "skill"}\r\n' });
  assert.ok(validate(root).out.includes('WARN: LOOP_TICKS.jsonl has no skill-mode entries yet.'));
});

test('TEST-3202 a CRLF log with the literal substring is detected', () => {
  const root = fixture({ marker: true, ticks: '{"a":1}\r\n{"mode":"skill"}\r\n' });
  assert.ok(validate(root).out.includes('OK: LOOP_TICKS.jsonl contains skill-mode evidence.'));
});

test('TEST-3202 a missing target gives exit 1 and exactly the Target-not-found line (V-4)', () => {
  const arg = path.join(os.tmpdir(), 'aai-vs-no-such-dir-' + process.pid);
  assert.deepEqual(validate(arg), { code: 1, out: [], err: ['ERROR: Target not found: ' + arg] });
});

test('TEST-3202 a file given as the target is not found either', () => {
  const root = fixture();
  const file = path.join(root, '.aai/SKILL_TDD.prompt.md');
  assert.deepEqual(validate(file), { code: 1, out: [], err: ['ERROR: Target not found: ' + file] });
});
