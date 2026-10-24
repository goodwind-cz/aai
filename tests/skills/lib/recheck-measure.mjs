#!/usr/bin/env node
// recheck-measure.mjs - the before/after payload size of the delta re-check mode
// (docs/specs/SPEC-0250-spec-cheap-transitions-slice.md, D11, TEST-2715).
//
// Builds a throwaway git repository under the OS temp directory from the LIVE canon
// inputs (never the shipping tree), commits a base, adds a four-path non-production
// delta shaped like node-first-third-slice round 4 (a suite, a node:test file, the
// spec and one ledger line), seeds STATE, two prior reports that carry
// `security_relevant: false`, an L2 spec and a check_verdict per role at the base,
// then prints one JSON line per role:
//   {"role":"Code Review","full_bytes":N,"delta_bytes":M,"ratio":0.xx}
// Exit 0 when both builds succeed. The repository this script runs from is only read.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(HERE, '..', '..', '..');
const CANON = path.join(PROJECT_ROOT, '.aai', 'scripts', 'canon.mjs');
const REF = 'x';
const INPUTS = [
  '.aai/SUBAGENT_CONTRACT.md', '.aai/RECHECK_DELTA.prompt.md', '.aai/system/CANON.yaml', 'docs/knowledge/LEARNED.md',
  '.aai/PLANNING.prompt.md', '.aai/IMPLEMENTATION.prompt.md', '.aai/VALIDATION.prompt.md',
  '.aai/REMEDIATION.prompt.md', '.aai/SKILL_TDD.prompt.md', '.aai/SKILL_CODE_REVIEW.prompt.md',
];

function git(cwd, args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}
function put(root, rel, text) {
  const abs = path.join(root, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, text);
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-recheck-measure.'));
let code = 0;
try {
  git(root, ['init', '-q', '-b', 'main']);
  git(root, ['config', 'user.email', 'measure@example.invalid']);
  git(root, ['config', 'user.name', 'AAI Measure']);
  for (const rel of INPUTS) {
    const dst = path.join(root, rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(path.join(PROJECT_ROOT, rel), dst);
  }
  put(root, '.gitignore', 'docs/ai/STATE.yaml\ndocs/ai/EVENTS.jsonl\n');
  put(root, 'docs/ai/docs-audit.yaml', 'protected_paths_l3:\n  - .aai/workflow/WORKFLOW.md\n');
  put(root, 'docs/specs/SPEC-0001-fx.md', '---\nid: SPEC-0001\ntype: spec\nstatus: draft\nceremony_level: 2\nlinks:\n  pr: []\n---\n\n# Fixture spec\n');
  put(root, 'docs/ai/reviews/rev-1.md', '# Review\n\nsecurity_relevant: false\n');
  put(root, 'docs/ai/reports/VALIDATION-1.md', '# Validation\n\nsecurity_relevant: false\n');
  put(root, 'docs/ai/decisions.jsonl', '{"type":"x"}\n');
  put(root, 'tests/skills/test-aai-fixture.sh', '#!/usr/bin/env bash\necho base\n');
  put(root, 'tests/skills/lib/fixture.test.mjs', '// base\n');
  put(root, 'docs/ai/STATE.yaml', `project_status: active
current_focus:
  type: intake_change
  ref_id: ${REF}
  primary_path: null
  spec_path: docs/specs/SPEC-0001-fx.md
active_work_items:
  - ref_id: ${REF}
    status: in_progress
    phase: implementation
    spec_path: docs/specs/SPEC-0001-fx.md
code_review:
  required: true
  status: fail
  report_paths:
    - docs/ai/reviews/rev-1.md
last_validation:
  status: fail
  run_at_utc: 2026-07-01T00:00:00Z
  ref_id: ${REF}
  evidence_paths:
    - docs/ai/reports/VALIDATION-1.md
updated_at_utc: 2026-07-01T00:00:00Z
`);
  git(root, ['add', '-A']);
  git(root, ['commit', '-q', '-m', 'base']);
  const base = git(root, ['rev-parse', 'HEAD']);
  put(root, 'docs/ai/EVENTS.jsonl', ['validation', 'code_review'].map((role) => JSON.stringify({
    v: 1, ts: '2026-07-01T00:00:00.000Z', actor: 'measure', event: 'check_verdict', ref: REF, payload: { role, head: base, status: 'fail', security_relevant: false },
  }) + '\n').join(''));
  // the four-path non-production delta
  fs.appendFileSync(path.join(root, 'tests/skills/test-aai-fixture.sh'), 'echo fixed\n');
  fs.appendFileSync(path.join(root, 'tests/skills/lib/fixture.test.mjs'), '// fixed\n');
  fs.appendFileSync(path.join(root, 'docs/specs/SPEC-0001-fx.md'), '\nAmended.\n');
  fs.appendFileSync(path.join(root, 'docs/ai/decisions.jsonl'), '{"type":"y"}\n');

  const env = { ...process.env };
  env.AAI_RECHECK_MODE = 'delta';
  delete env.AAI_ROLE;
  const build = (role, extra) => spawnSync(process.execPath, [CANON, 'build', '--role', role, '--ref', REF, ...extra], { cwd: root, encoding: 'utf8', env });
  for (const role of ['Code Review', 'Validation']) {
    const full = build(role, []);
    const delta = build(role, ['--recheck', 'delta']);
    if (full.status !== 0 || delta.status !== 0) {
      process.stderr.write(`recheck-measure: ${role}: full exit ${full.status}, delta exit ${delta.status}\n${full.stderr}${delta.stderr}`);
      code = 1;
      continue;
    }
    const fullBytes = Buffer.byteLength(full.stdout, 'utf8');
    const deltaBytes = Buffer.byteLength(delta.stdout, 'utf8');
    process.stdout.write(`${JSON.stringify({ role, full_bytes: fullBytes, delta_bytes: deltaBytes, ratio: Number((deltaBytes / fullBytes).toFixed(3)) })}\n`);
  }
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
process.exit(code);
