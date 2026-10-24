// triage.test.mjs - node:test cases for .aai/scripts/triage.mjs
// (docs/specs/SPEC-0248-spec-node-first-second-slice.md, TEST-2501..2506).
// Direct imports, temp directories only, no repository clone.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { buildReport, stateLine, tickLine, runTriage, stampUtc } from '../../../.aai/scripts/triage.mjs';

const made = [];
function tmpRoot() {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-triage-'));
  fs.mkdirSync(path.join(d, 'docs', 'ai'), { recursive: true });
  made.push(d);
  return d;
}
after(() => {
  for (const d of made) fs.rmSync(d, { recursive: true, force: true });
});

const FIXED = new Date('2026-10-23T21:58:07.456Z');
const BOM = String.fromCharCode(0xfeff);
const AUDIT = '- Mode: quick\n- Scanned: 3\n- Tracked: 2\n### Verdict: OK\nnoise line\n';
const BASE = { now: FIXED, check: false, stateText: 'project_status: active\n', porcelain: ' M a\n?? b\n', ticksText: '{"t":1}\n{"t":2}\n', auditOutput: AUDIT };

function runIn(root, argv = []) {
  let text = '';
  const code = runTriage({ argv, root, now: FIXED, stdout: { write: (t) => { text += t; } } });
  return { text, code };
}

test('TEST-2501 buildReport returns the lines in order, LF joined, one final LF, exit 0', () => {
  const r = buildReport(BASE);
  assert.equal(r.text, [
    '## AAI L1 Triage - 2026-10-23T21:58:07Z', '',
    '- State: present (project_status=active)',
    '- Working tree: 2 uncommitted change(s)',
    '- Last tick: {"t":2}', '',
    '- Mode: quick', '- Scanned: 3', '- Tracked: 2', '### Verdict: OK', '',
    '### Triage verdict: CLEAN',
  ].join('\n') + '\n');
  assert.equal(r.exitCode, 0);
});

test('TEST-2501 absent inputs give the not-present, clean, none and skipped lines', () => {
  const r = buildReport({ now: FIXED, check: true, stateText: null, porcelain: null, ticksText: null, auditOutput: null });
  assert.match(r.text, /\n- State: not present yet \(docs\/ai\/STATE\.yaml\) - orchestrator will init, or run \/aai-check-state\n/);
  assert.match(r.text, /\n- Working tree: clean\n- Last tick: none recorded\n\n- Docs audit: skipped \(node or docs-audit\.mjs unavailable\)\n\n### Triage verdict: CLEAN\n$/);
  assert.equal(r.exitCode, 0);
});

test('TEST-2502 header uses an ASCII hyphen and the whole report is ASCII for ASCII inputs', () => {
  assert.equal(stampUtc(FIXED), '2026-10-23T21:58:07Z');
  const r = buildReport(BASE);
  assert.equal(r.text.split('\n')[0], '## AAI L1 Triage - 2026-10-23T21:58:07Z');
  for (const b of Buffer.from(r.text, 'utf8')) assert.ok(b <= 0x7e, 'byte above 0x7E: ' + b);
});

test('TEST-2503 an empty or glued project_status prints unknown', () => {
  for (const t of ['project_status:\n', 'project_status:active\n', 'project_status:   \n']) {
    assert.equal(stateLine(t), '- State: present (project_status=unknown)', JSON.stringify(t));
  }
  assert.equal(stateLine('project_status: active # note\n'), '- State: present (project_status=active)');
  assert.equal(stateLine('other: 1\n'), '- State: not present yet (docs/ai/STATE.yaml) - orchestrator will init, or run /aai-check-state');
});

test('TEST-2504 a leading BOM in STATE.yaml and LOOP_TICKS.jsonl is ignored', () => {
  const root = tmpRoot();
  fs.writeFileSync(path.join(root, 'docs', 'ai', 'STATE.yaml'), BOM + 'project_status: active\n');
  fs.writeFileSync(path.join(root, 'docs', 'ai', 'LOOP_TICKS.jsonl'), BOM + '{"t":9}\n');
  const r = runIn(root);
  assert.match(r.text, /\n- State: present \(project_status=active\)\n/);
  assert.match(r.text, /\n- Last tick: \{"t":9\}\n/);
  assert.equal(r.text.includes(BOM), false);
});

test('TEST-2504 a ticks file holding only a BOM prints none recorded', () => {
  const root = tmpRoot();
  fs.writeFileSync(path.join(root, 'docs', 'ai', 'LOOP_TICKS.jsonl'), BOM);
  assert.match(runIn(root).text, /\n- Last tick: none recorded\n/);
});

test('TEST-2505 the audit marker is case-sensitive', () => {
  const lower = buildReport({ ...BASE, check: true, auditOutput: '- mode: quick\n### verdict: needs-triage\n' });
  assert.match(lower.text, /\n- Docs audit: \(no output\)\n/);
  assert.match(lower.text, /### Triage verdict: CLEAN\n$/);
  assert.equal(lower.exitCode, 0);
  const upper = buildReport({ ...BASE, check: true, auditOutput: '- Mode: quick\n### Verdict: NEEDS-TRIAGE\n' });
  assert.match(upper.text, /### Triage verdict: NEEDS-ATTENTION \(1 area\(s\)\)\n$/);
  assert.equal(upper.exitCode, 1);
  assert.equal(buildReport({ ...BASE, check: false, auditOutput: '### Verdict: NEEDS-TRIAGE\n' }).exitCode, 0);
});

test('TEST-2506 a CRLF tick line is printed without CR; a trailing empty line prints an empty tick', () => {
  assert.equal(tickLine('{"t":1}\r\n{"t":2}\r\n'), '- Last tick: {"t":2}');
  assert.equal(tickLine('{"t":1}\r\n{"t":2}').includes('\r'), false);
  assert.equal(tickLine('{"t":1}\n\n'), '- Last tick: ');
  assert.equal(tickLine(''), '- Last tick: none recorded');
});
