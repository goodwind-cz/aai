// TEST-006 offline documentation contracts; runs without a Hermes installation.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

let failures = 0;
function check(label, test) {
  try { test(); console.log(`TEST-006 ${label} GREEN (offline)`); }
  catch (error) { failures++; console.error(`TEST-006 ${label} FAIL: ${error.message}`); }
}
check('guide-only selection', () => {
  const result = spawnSync(process.execPath, ['.aai/scripts/select-suites.mjs', '--files-from', '-'], {
    input: 'docs/USER_GUIDE.md\n', encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^SELECTED aai-hermes-skills reason=docs\/USER_GUIDE\.md$/m,
    'guide-only changes must select the suite that checks the Hermes instructions');
});
check('durable product evidence', () => {
  const product = 'docs/product/hermes-agent-skill-discovery.md';
  const match = fs.readFileSync(product, 'utf8').match(/^- Verification: \[[^\]]+\]\(([^)]+)\)/m);
  assert.ok(match, 'product must link verification evidence');
  const target = path.resolve(path.dirname(product), match[1]);
  assert.ok(fs.existsSync(target), `verification target missing: ${target}`);
  const relative = path.relative(process.cwd(), target);
  assert.ok(!relative.startsWith('..'), 'verification target must stay in repository');
  const tracked = spawnSync('git', ['ls-files', '--error-unmatch', '--', relative], { encoding: 'utf8' });
  assert.equal(tracked.status, 0, 'verification evidence must be tracked so the link works in a fresh clone');
});
process.exitCode = failures ? 1 : 0;
