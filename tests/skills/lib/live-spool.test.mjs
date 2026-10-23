// live-spool.test.mjs — node:test cases for .aai/scripts/live-spool.mjs
// (docs/specs/SPEC-0247-spec-node-first-sync-hook-slice.md, TEST-2401..2407).
// Direct imports, temp directories only, no repository clone.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { projectPayload, appendCapped, runLiveSpool, MAX_LINES, PASSTHROUGH } from '../../../.aai/scripts/live-spool.mjs';

const MODULE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../.aai/scripts/live-spool.mjs');

const made = [];
function tmp() {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-live-spool-'));
  made.push(d);
  return d;
}
after(() => {
  for (const d of made) fs.rmSync(d, { recursive: true, force: true });
});

const FIXED = new Date('2026-10-23T13:36:09.977Z');
const EXTRA = { transcript_path: '/t', message: 'hello' };
const FULL = {
  session_id: 's1', cwd: '/x', model: { id: 'm' },
  rate_limits: { five_hour: { used_percent: 33 } }, cost: { total: 1 },
  hook_event_name: 'Stop', ...EXTRA,
};

test('TEST-2401 statusline payload keeps exactly ts plus the statusline keys in allow-list order', () => {
  const o = JSON.parse(projectPayload(JSON.stringify(FULL), 'statusline', FIXED));
  assert.deepEqual(Object.keys(o), ['ts', 'session_id', 'cwd', 'model', 'rate_limits', 'cost']);
});

test('TEST-2401 hooks payload keeps exactly ts plus the hook keys in allow-list order', () => {
  const o = JSON.parse(projectPayload(JSON.stringify(FULL), 'hooks', FIXED));
  assert.deepEqual(Object.keys(o), ['ts', 'session_id', 'cwd', 'model', 'hook_event_name']);
});

test('TEST-2401 a non-whitelisted kind uses the statusline fields', () => {
  const o = JSON.parse(projectPayload(JSON.stringify(FULL), 'foo', FIXED));
  assert.deepEqual(Object.keys(o), ['ts', 'session_id', 'cwd', 'model', 'rate_limits', 'cost']);
});

test('TEST-2401 null, zero and empty-string values are kept', () => {
  const o = JSON.parse(projectPayload('{"session_id":null,"cwd":"","model":0}', 'statusline', FIXED));
  assert.deepEqual(o, { ts: FIXED.toISOString(), session_id: null, cwd: '', model: 0 });
});

test('TEST-2402 ts equals toISOString of the injected date and has 3 fractional digits', () => {
  const o = JSON.parse(projectPayload('{"cwd":"/x"}', 'statusline', FIXED));
  assert.equal(o.ts, FIXED.toISOString());
  assert.match(o.ts, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
});

test('TEST-2403 array, number, string and null payloads return null and create no spool file', () => {
  const dir = tmp();
  for (const raw of ['[1,2]', '42', '"s"', 'null', '', '   ', '{bad']) {
    assert.equal(projectPayload(raw, 'statusline', FIXED), null, raw);
    runLiveSpool({ argv: ['statusline'], env: { AAI_LIVE_SPOOL_DIR: dir }, stdinText: raw, stdout: { write() {} } });
  }
  assert.deepEqual(fs.readdirSync(dir), []);
});

test('TEST-2404 a cost value nested 12 levels deep is written equal to JSON.stringify of the input value', () => {
  let deep = 'leaf';
  for (let i = 0; i < 12; i++) deep = { n: deep };
  const line = projectPayload(JSON.stringify({ cost: deep }), 'statusline', FIXED);
  assert.equal(JSON.stringify(JSON.parse(line).cost), JSON.stringify(deep));
  assert.ok(line.includes(JSON.stringify(deep)));
});

test('TEST-2405 a non-ASCII payload is written as UTF-8 without BOM and without CR', () => {
  const dir = tmp();
  const raw = JSON.stringify({ model: { display_name: 'Opus ✓ čř' } });
  runLiveSpool({ argv: ['statusline'], env: { AAI_LIVE_SPOOL_DIR: dir }, stdinText: raw, stdout: { write() {} } });
  const buf = fs.readFileSync(path.join(dir, 'statusline.jsonl'));
  assert.notDeepEqual([...buf.subarray(0, 3)], [0xef, 0xbb, 0xbf]);
  assert.ok(!buf.includes(0x0d));
  assert.equal(JSON.parse(buf.toString('utf8')).model.display_name, 'Opus ✓ čř');
});

test('TEST-2406 a spool of 505 lines plus one append holds exactly 500 lines ending with the new one', () => {
  const dir = tmp();
  const file = path.join(dir, 'statusline.jsonl');
  const old = [];
  for (let i = 0; i < 505; i++) old.push(JSON.stringify({ n: i }));
  fs.writeFileSync(file, old.join('\n') + '\n');
  appendCapped(file, '{"n":"new"}');
  const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
  assert.equal(MAX_LINES, 500);
  assert.equal(lines.length, 500);
  assert.equal(lines[499], '{"n":"new"}');
  assert.equal(lines[0], '{"n":6}');
  assert.deepEqual(fs.readdirSync(dir), ['statusline.jsonl']);
});

function cli(args, input, env) {
  return spawnSync(process.execPath, [MODULE, ...args], {
    input, encoding: 'utf8', env: { ...process.env, ...env },
  });
}

test('TEST-2407 CLI statusline and no-kind print exactly the passthrough and exit 0', () => {
  const dir = tmp();
  for (const args of [['statusline'], []]) {
    const r = cli(args, '{"cwd":"/x"}', { AAI_LIVE_SPOOL_DIR: dir });
    assert.equal(r.status, 0);
    assert.equal(r.stdout, PASSTHROUGH + '\n');
    assert.equal(r.stderr, '');
  }
});

test('TEST-2407 CLI hooks prints nothing and exits 0', () => {
  const dir = tmp();
  const r = cli(['hooks'], '{"hook_event_name":"Stop"}', { AAI_LIVE_SPOOL_DIR: dir });
  assert.equal(r.status, 0);
  assert.equal(r.stdout, '');
  assert.equal(r.stderr, '');
  assert.equal(fs.readFileSync(path.join(dir, 'hooks.jsonl'), 'utf8').split('\n').filter(Boolean).length, 1);
});

test('TEST-2407 CLI exits 0 with empty stderr when the spool dir is a regular file', () => {
  const dir = tmp();
  const file = path.join(dir, 'regular');
  fs.writeFileSync(file, 'x');
  const r = cli(['statusline'], '{"cwd":"/x"}', { AAI_LIVE_SPOOL_DIR: file });
  assert.equal(r.status, 0);
  assert.equal(r.stderr, '');
  assert.equal(r.stdout, PASSTHROUGH + '\n');
});
