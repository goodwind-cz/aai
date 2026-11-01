// aai-live.test.mjs - node:test cases for .aai/scripts/aai-live.mjs
// (docs/specs/SPEC-DRAFT-spec-node-first-small-pairs.md, TEST-3206).
// Direct imports of the pure resolvers, temporary directories only.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { resolveOutputPath, warmupArgs, resolveOpener } from '../../../.aai/scripts/aai-live.mjs';

const made = [];
after(() => { for (const d of made) fs.rmSync(d, { recursive: true, force: true }); });
function binDir(...names) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-live-bin-'));
  made.push(d);
  for (const n of names) fs.writeFileSync(path.join(d, n), '#!/bin/sh\n', { mode: 0o755 });
  return d;
}
const ROOT = path.resolve(os.tmpdir(), 'aai-live-root');

test('TEST-3206 resolveOutputPath gives the default under root', () => {
  assert.equal(resolveOutputPath([], ROOT), path.join(ROOT, 'docs/ai/live-status.html'));
  assert.equal(resolveOutputPath(['--watch', '--interval', '1'], ROOT), path.join(ROOT, 'docs/ai/live-status.html'));
});

test('TEST-3206 resolveOutputPath takes the last --output value, relative under root, absolute unchanged', () => {
  assert.equal(resolveOutputPath(['--output', 'a.html', '--output', 'custom/b.html'], ROOT), path.join(ROOT, 'custom/b.html'));
  const abs = path.resolve(os.tmpdir(), 'abs-page.html');
  assert.equal(resolveOutputPath(['--output', 'x.html', '--output', abs], ROOT), abs);
  assert.equal(resolveOutputPath(['--output'], ROOT), path.join(ROOT, 'docs/ai/live-status.html'));
});

test('TEST-3206 warmupArgs drops every --watch and keeps order', () => {
  assert.deepEqual(warmupArgs(['--watch', '--interval', '1', '--watch', '--data-only']), ['--interval', '1', '--data-only']);
  assert.deepEqual(warmupArgs(['--watch']), []);
  assert.deepEqual(warmupArgs([]), []);
});

test('TEST-3206 resolveOpener honours AAI_LIVE_OPENER on linux and win32', () => {
  assert.deepEqual(resolveOpener({ env: { AAI_LIVE_OPENER: '/x/op' }, platform: 'linux', pathEnv: '' }), { cmd: '/x/op', shell: false });
  assert.deepEqual(resolveOpener({ env: { AAI_LIVE_OPENER: 'C:\\t\\op.exe' }, platform: 'win32', pathEnv: '' }), { cmd: 'C:\\t\\op.exe', shell: false });
});

test('TEST-3206 resolveOpener finds open before xdg-open on a fixture PATH', () => {
  assert.deepEqual(resolveOpener({ env: {}, platform: 'linux', pathEnv: binDir('xdg-open', 'open') }), { cmd: 'open', shell: false });
  assert.deepEqual(resolveOpener({ env: {}, platform: 'linux', pathEnv: binDir('xdg-open') }), { cmd: 'xdg-open', shell: false });
});

test('TEST-3206 resolveOpener returns null on an empty PATH or one without a candidate', () => {
  assert.equal(resolveOpener({ env: {}, platform: 'linux', pathEnv: '' }), null);
  assert.equal(resolveOpener({ env: {}, platform: 'linux', pathEnv: binDir('other') }), null);
  assert.equal(resolveOpener({ env: { AAI_LIVE_OPENER: '' }, platform: 'linux', pathEnv: '' }), null);
});

test('TEST-3206 resolveOpener gives explorer.exe on win32 without an override', () => {
  assert.deepEqual(resolveOpener({ env: {}, platform: 'win32', pathEnv: '' }), { cmd: 'explorer.exe', shell: false });
});

test('TEST-3206 a .CMD or .bat override on win32 is shell with the opener double-quoted', () => {
  assert.deepEqual(resolveOpener({ env: { AAI_LIVE_OPENER: 'C:\\a b\\op.CMD' }, platform: 'win32', pathEnv: '' }), { cmd: '"C:\\a b\\op.CMD"', shell: true });
  assert.deepEqual(resolveOpener({ env: { AAI_LIVE_OPENER: 'C:\\a b\\op.bat' }, platform: 'win32', pathEnv: '' }), { cmd: '"C:\\a b\\op.bat"', shell: true });
  assert.deepEqual(resolveOpener({ env: { AAI_LIVE_OPENER: '/x/op.cmd' }, platform: 'linux', pathEnv: '' }), { cmd: '/x/op.cmd', shell: false });
});
