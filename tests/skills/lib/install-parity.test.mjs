// install-parity.test.mjs - node:test cases for tests/skills/lib/install-parity.mjs
// (docs/specs/SPEC-DRAFT-install-path-parity-harness.md, TEST-3560 to TEST-3570).
// Pure rules (compare, normalize, allowlist, positive controls, the twin seam) run on synthetic trees and
// injected fake twins; two cases (TEST-3566, TEST-3567) run the real twins into scratch targets.
// Every case works in fresh temp directories and leaves none behind.
import { describe, test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
// The driver may not exist yet (RED on the baseline): every case must fail on its own assertion.
const M = await import('./install-parity.mjs').catch(() => ({}));

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../..');
const DRIVER = path.join(HERE, 'install-parity.mjs');
const ALLOWLIST = path.join(HERE, 'install-parity-allowlist.tsv');
const TMP = [];
after(() => { for (const d of TMP) fs.rmSync(d, { recursive: true, force: true }); });

const scratch = (label) => {
  const d = fs.realpathSync(fs.mkdtempSync(path.join(process.env.AAI_PARITY_SCRATCH || os.tmpdir(), `aai-parity-${label}-`)));
  TMP.push(d);
  return d;
};
const put = (dir, rel, content, mode) => {
  const p = path.join(dir, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
  if (mode) fs.chmodSync(p, mode);
};
const cli = (args, opts = {}) => spawnSync(process.execPath, [DRIVER, ...args], { encoding: 'utf8', cwd: ROOT, ...opts });
const has = (name) => assert.equal(typeof M[name], 'function', `install-parity.mjs must export function ${name}`);
const posix = process.platform !== 'win32';
const HOST_POSIX = { platform: 'posix', utc: false };

// A fake twin: argv() returns a node child that writes files into the target and exits with a code.
const fakeTwin = (name, { files = {}, code = 0, codes = null, after: extra = '' } = {}) => ({
  name,
  argv(step, ctx) {
    const c = codes ? codes[Math.min(step.index ?? 0, codes.length - 1)] : code;
    const script = `const fs=require('fs'),p=require('path');const F=${JSON.stringify(files)};`
      + `for(const k of Object.keys(F)){fs.mkdirSync(p.dirname(k),{recursive:true});fs.writeFileSync(k,F[k]);}${extra}process.exit(${c});`;
    return { file: process.execPath, args: ['-e', script], cwd: ctx.target };
  },
});
const scen = (over = {}) => ({
  id: 'T-01', tier: 'smoke', op: 'sync', setup: 'empty',
  steps: [{ op: 'sync', profile: 'core', flags: [], expect: '0' }],
  probes: ['p.txt'], ...over,
});
const fakeSetup = (_s, target) => { fs.mkdirSync(target, { recursive: true }); };
const runFake = (twins, scenarios, rows = [], extra = {}) => {
  const root = scratch('run');
  return M.runMatrix({
    scenarios, twins, rows, matrix: 'smoke', filtered: false,
    ctx: { root, src: root, bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX },
    ...extra,
  });
};

describe('TEST-3560 matrix tiers', () => {
  const specPath = () => {
    const dir = path.join(ROOT, 'docs/specs');
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith('.md')) continue;
      const t = fs.readFileSync(path.join(dir, f), 'utf8');
      if (/^id: spec-install-path-parity-harness$/m.test(t)) return path.join(dir, f);
    }
    throw new Error('spec spec-install-path-parity-harness not found');
  };
  const specRows = () => {
    const rows = [];
    for (const l of fs.readFileSync(specPath(), 'utf8').split('\n')) {
      const m = /^\| ((?:SY|UP|HK)-\d\d) \| (smoke|default|full) \|/.exec(l);
      if (m) rows.push({ id: m[1], tier: m[2] });
    }
    return rows;
  };
  const rank = { smoke: 0, default: 1, full: 2 };
  for (const [tier, n] of [['smoke', 7], ['default', 15], ['full', 20]]) {
    test(`list --matrix ${tier} prints the ${n} ids of the D-MATRIX table in order`, () => {
      const want = specRows().filter((r) => rank[r.tier] <= rank[tier]).map((r) => r.id);
      assert.equal(want.length, n);
      const r = cli(['list', '--matrix', tier, '--json']);
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(JSON.parse(r.stdout), want);
      const plain = cli(['list', '--matrix', tier]);
      assert.equal(plain.stdout, `${want.join('\n')}\n`);
    });
  }
  test('an unknown tier exits 2', () => {
    assert.equal(cli(['list', '--matrix', 'bogus']).status, 2);
    assert.equal(cli(['list']).status, 2);
  });
});

describe('TEST-3561 compare kinds', () => {
  const kinds = (ds) => ds.map((d) => d.kind).sort();
  test('exactly one divergence of each kind, with pair, path and detail', () => {
    has('compareTrees');
    const a = scratch('ca'); const b = scratch('cb');
    put(a, 'only-a.txt', 'x\n');
    put(a, 'ord.txt', 'one\ntwo\nthree\n'); put(b, 'ord.txt', 'three\none\ntwo\n');
    put(a, 'ln.txt', 'same\nleft\n'); put(b, 'ln.txt', 'same\nright\n');
    put(a, 'bin.dat', Buffer.from([1, 0, 2])); put(b, 'bin.dat', Buffer.from([1, 0, 3]));
    put(a, 'same.txt', 'eq\n'); put(b, 'same.txt', 'eq\n');
    if (posix) { put(a, 'run.sh', '#!/bin/sh\n', 0o755); put(b, 'run.sh', '#!/bin/sh\n', 0o644); }
    const ds = M.compareTrees(a, b, { pair: 'a:b', exits: { a: [0], b: [3] } });
    const want = ['bytes', 'exit', 'lines', 'missing', 'order'].concat(posix ? ['mode'] : []).sort();
    assert.deepEqual(kinds(ds), want);
    for (const d of ds) {
      assert.equal(d.pair, 'a:b');
      assert.ok(d.path && typeof d.detail === 'string' && d.detail.length > 0, JSON.stringify(d));
    }
    const ln = ds.find((d) => d.kind === 'lines');
    assert.equal(ln.path, 'ln.txt');
    assert.deepEqual(ln.onlyA, ['left']);
    assert.deepEqual(ln.onlyB, ['right']);
    assert.equal(ds.find((d) => d.kind === 'exit').path, 'step1');
    assert.equal(ds.find((d) => d.kind === 'missing').path, 'only-a.txt');
    assert.equal(ds.find((d) => d.kind === 'order').path, 'ord.txt');
  });
  test('an empty directory counts as tree content', () => {
    has('compareTrees');
    const a = scratch('da'); const b = scratch('db');
    fs.mkdirSync(path.join(a, 'empty-dir'));
    const ds = M.compareTrees(a, b, { pair: 'a:b' });
    assert.deepEqual(ds.map((d) => [d.kind, d.path]), [['missing', 'empty-dir']]);
  });
  test('a symlink target counts as tree content', { skip: !posix && 'no symlinks' }, () => {
    has('compareTrees');
    const a = scratch('sa'); const b = scratch('sb');
    fs.symlinkSync('target-one', path.join(a, 'link'));
    fs.symlinkSync('target-two', path.join(b, 'link'));
    const ds = M.compareTrees(a, b, { pair: 'a:b' });
    assert.equal(ds.length, 1);
    assert.equal(ds[0].path, 'link');
    assert.match(ds[0].detail, /target-one/);
    assert.match(ds[0].detail, /target-two/);
    const c = scratch('sc');
    fs.symlinkSync('target-one', path.join(c, 'link'));
    assert.deepEqual(M.compareTrees(a, c, { pair: 'a:b' }), []);
  });
  test('a CRLF-only difference is a lines divergence', () => {
    has('compareTrees');
    const a = scratch('ra'); const b = scratch('rb');
    put(a, 'f.txt', 'one\ntwo\n'); put(b, 'f.txt', 'one\r\ntwo\r\n');
    const ds = M.compareTrees(a, b, { pair: 'a:b' });
    assert.deepEqual(ds.map((d) => [d.kind, d.path]), [['lines', 'f.txt']]);
  });
  test('identical trees give no divergence and a kind difference is missing', () => {
    has('compareTrees');
    const a = scratch('ia'); const b = scratch('ib');
    put(a, 'x/y.txt', 'q\n'); put(b, 'x/y.txt', 'q\n');
    assert.deepEqual(M.compareTrees(a, b, { pair: 'a:b' }), []);
    const c = scratch('ic'); const d = scratch('id');
    put(c, 'n', 'file\n'); fs.mkdirSync(path.join(d, 'n'));
    assert.deepEqual(M.compareTrees(c, d, { pair: 'a:b' }).map((x) => x.kind), ['missing']);
  });
  test('the mode kind is declared and MODE_MEANINGFUL follows the platform', () => {
    assert.deepEqual(M.KINDS, ['exit', 'missing', 'bytes', 'lines', 'order', 'mode']);
    assert.equal(M.MODE_MEANINGFUL, process.platform !== 'win32');
  });
});

describe('TEST-3562 normalizations', () => {
  const snapOf = (files, opts = {}) => {
    const d = scratch('n');
    for (const [k, v] of Object.entries(files)) put(d, k, v);
    return M.snapshotNormalized(d, opts);
  };
  const text = (snap, p) => snap.get(p).data.toString('utf8');
  test('the closed list holds exactly N1 N2 N3 N4 E1 E2 with reasons', () => {
    assert.deepEqual(M.NORMALIZATIONS.map((n) => n.id), ['N1', 'N2', 'N3', 'N4', 'E1', 'E2']);
    for (const n of M.NORMALIZATIONS) assert.ok(typeof n.reason === 'string' && n.reason.length > 0, n.id);
    assert.equal(M.NAME_MUST_MATCH_STAMP, true);
  });
  test('N1 rewrites the second-precision line only', () => {
    const s = snapOf({ '.aai/system/AAI_PIN.md': '- Template version: v1\n- Synced at (UTC): 2026-11-10T18:54:19Z\n- Other: 2026-11-10T18:54:19Z\n' });
    assert.equal(text(s, '.aai/system/AAI_PIN.md'), '- Template version: v1\n- Synced at (UTC): <stamp>\n- Other: 2026-11-10T18:54:19Z\n');
    const f = snapOf({ '.aai/system/AAI_PIN.md': '- Synced at (UTC): 2026-11-10T18:54:19.1023490Z\n' });
    assert.equal(text(f, '.aai/system/AAI_PIN.md'), '- Synced at (UTC): 2026-11-10T18:54:19.1023490Z\n');
  });
  test('a timestamp-like string elsewhere is unchanged', () => {
    const body = '- Synced at (UTC): 2026-11-10T18:54:19Z\n';
    const s = snapOf({ 'docs/other.md': body });
    assert.equal(text(s, 'docs/other.md'), body);
  });
  test('N2 rewrites the Generated-at line of a conflicts report', () => {
    const r = 'docs/ai/reports/sync-conflicts-20261110-185419.md';
    const s = snapOf({ [r]: '# x\n- Generated at (UTC): 2026-11-10T18:54:19Z\n' });
    const only = [...s.keys()].find((k) => k.startsWith('docs/ai/reports/'));
    assert.match(text(s, only), /- Generated at \(UTC\): <stamp>\n/);
    const f = snapOf({ [r]: '- Generated at (UTC): 2026-11-10T18:54:19.1023490Z\n' });
    assert.match(text(f, [...f.keys()].find((k) => k.startsWith('docs/ai/reports/'))), /19\.1023490Z/);
  });
  test('N3 renames when the name stamp equals the Generated-at second, and not otherwise', () => {
    const agree = snapOf({
      'docs/ai/reports/sync-conflicts-20261110-185419.md': '- Generated at (UTC): 2026-11-10T18:54:19.1023490Z\n',
      'docs/ai/reports/sync-conflicts-20261110-190000.md': '- Generated at (UTC): 2026-11-10T19:00:00Z\n',
    });
    assert.deepEqual([...agree.keys()].filter((k) => k.includes('sync-conflicts')).sort(),
      ['docs/ai/reports/sync-conflicts-<stamp-1>.md', 'docs/ai/reports/sync-conflicts-<stamp-2>.md']);
    const skew = snapOf({ 'docs/ai/reports/sync-conflicts-20261110-215419.md': '- Generated at (UTC): 2026-11-10T18:54:19Z\n' });
    assert.ok(!skew.has('docs/ai/reports/sync-conflicts-20261110-215419.md'), 'a disagreeing name is paired by ordinal too, so its content is compared');
    assert.equal(skew.get('docs/ai/reports/sync-conflicts-<stamp-1>.md').nameSkew, true);
    assert.ok(!agree.get('docs/ai/reports/sync-conflicts-<stamp-1>.md').nameSkew);
  });
  test('a report name that disagrees with its Generated-at line on one side only stays a visible divergence, apart from the content', () => {
    const g = '- Generated at (UTC): 2026-11-10T18:54:19Z\n';
    const a = snapOf({ 'docs/ai/reports/sync-conflicts-20261110-185419.md': g });
    const b = snapOf({ 'docs/ai/reports/sync-conflicts-20261110-215419.md': g });
    const ds = M.compareSnapshots(a, b, 'a:b');
    assert.deepEqual(ds.map((d) => d.kind), ['missing']);
    assert.equal(ds[0].path, 'docs/ai/reports/sync-conflicts-<stamp-1>.md#name');
    const c = snapOf({ 'docs/ai/reports/sync-conflicts-20261110-215419.md': '- Generated at (UTC): 2026-11-10T18:54:19Z\nextra\n' });
    const ds2 = M.compareSnapshots(a, c, 'a:b');
    assert.deepEqual(ds2.map((d) => `${d.kind} ${d.path}`).sort(), ['lines docs/ai/reports/sync-conflicts-<stamp-1>.md', 'missing docs/ai/reports/sync-conflicts-<stamp-1>.md#name']);
    assert.deepEqual(M.compareSnapshots(b, b, 'a:b'), []);
  });
  test('N4 renames doctor reports by ordinal and E2 keeps presence but drops content', () => {
    const s = snapOf({
      'docs/ai/reports/doctor-20261110T185419Z-hosta.md': 'host a\n',
      'docs/ai/reports/doctor-20261110T185420Z-hostb.md': 'host b\n',
    });
    const names = [...s.keys()].filter((k) => k.includes('doctor')).sort();
    assert.deepEqual(names, ['docs/ai/reports/doctor-<stamp-1>.md', 'docs/ai/reports/doctor-<stamp-2>.md']);
    assert.equal(text(s, names[0]), '');
    assert.equal(text(s, names[1]), '');
  });
  test('E1 keeps non-sample .git/hooks files for hooks scenarios only', () => {
    const files = { '.git/HEAD': 'ref\n', '.git/hooks/pre-commit': '#!/bin/sh\n', '.git/hooks/pre-commit.sample': 's\n', 'f.txt': 'x\n' };
    const h = snapOf(files, { hooks: true });
    assert.deepEqual([...h.keys()].filter((k) => !h.get(k) || h.get(k).kind === 'file').sort(), ['.git/hooks/pre-commit', 'f.txt']);
    const s = snapOf(files, { hooks: false });
    assert.deepEqual([...s.keys()].filter((k) => s.get(k).kind === 'file').sort(), ['f.txt']);
  });
});

describe('TEST-3563 allowlist', () => {
  const row = (o = {}) => {
    const f = { id: 'r1', pairs: 'a:b', scenario: '*', path: 'f.txt', kind: 'lines', host: 'any', tracker: 'accepted', match: '.*', reason: 'by design', ...o };
    return [f.id, f.pairs, f.scenario, f.path, f.kind, f.host, f.tracker, f.match, f.reason].join('\t');
  };
  const parse = (text) => M.parseAllowlist(text, { twins: ['a', 'b', 'c'] });
  const refused = (text, rowId, field) => {
    let err;
    try { parse(text); } catch (e) { err = e; }
    assert.ok(err, `expected a refusal naming ${rowId} ${field}`);
    assert.equal(err.row, rowId);
    assert.equal(err.field, field);
    assert.match(err.message, new RegExp(rowId));
  };
  test('each parser refusal names the row and field', () => {
    has('parseAllowlist');
    refused('r1\ta:b\t*\tf\tlines\tany\taccepted\t-', 'r1', 'fields');
    refused(row({ reason: '' }), 'r1', 'reason');
    refused(row({ kind: 'weird' }), 'r1', 'kind');
    refused(row({ host: 'mars' }), 'r1', 'host');
    refused(row({ pairs: 'a:zzz' }), 'r1', 'pairs');
    refused(`${row()}\n${row()}`, 'r1', 'id');
    refused(row({ tracker: 'nope' }), 'r1', 'tracker');
    refused(row({ match: '(' }), 'r1', 'match');
    refused(row({ match: '-' }), 'r1', 'match');
    refused(row({ match: '=^v\\S+$' }), 'r1', 'match');
    refused(row({ id: 'Bad Id' }), 'Bad Id', 'id');
  });
  test('comments, blank lines and CRLF are tolerated', () => {
    has('parseAllowlist');
    const rows = parse(`# c\r\n\r\n${row()}\r\n${row({ id: 'r2', tracker: 'fu-x-y' })}\r\n`);
    assert.deepEqual(rows.map((r) => r.id), ['r1', 'r2']);
    assert.equal(rows[0].reason, 'by design');
  });
  const div = (o = {}) => ({ pair: 'a:b', path: 'f.txt', kind: 'lines', detail: 'd', onlyA: ['x 1'], onlyB: ['x 2'], ...o });
  const apply = (ds, rows, scenario = 'S-1') => M.applyAllowlist(ds, parse(rows.join('\n')), { scenario, host: HOST_POSIX });
  test('a matching row covers, an unmatched divergence is uncovered', () => {
    has('applyAllowlist');
    const r = apply([div()], [row()]);
    assert.equal(r.covered.length, 1);
    assert.equal(r.covered[0].covered_by, 'r1');
    assert.equal(r.uncovered.length, 0);
    for (const bad of [row({ pairs: 'a:c' }), row({ scenario: 'S-2' }), row({ path: 'g.txt' }), row({ kind: 'order' }), row({ host: 'win32' })]) {
      assert.equal(apply([div()], [bad]).uncovered.length, 1, bad);
    }
  });
  test('globs: * stays in a segment and ** crosses segments', () => {
    has('applyAllowlist');
    assert.equal(apply([div({ path: 'd/x.txt' })], [row({ path: 'd/*.txt' })]).uncovered.length, 0);
    assert.equal(apply([div({ path: 'd/e/x.txt' })], [row({ path: 'd/*.txt' })]).uncovered.length, 1);
    assert.equal(apply([div({ path: 'd/e/x.txt' })], [row({ path: 'd/**' })]).uncovered.length, 0);
  });
  test('a lines row whose regex misses one differing line does not cover', () => {
    has('applyAllowlist');
    assert.equal(apply([div()], [row({ match: '^x \\d$' })]).uncovered.length, 0);
    assert.equal(apply([div({ onlyB: ['x 2', 'y 3'] })], [row({ match: '^x \\d$' })]).uncovered.length, 1);
  });
  test('a file that differs in two ways takes one lines row per way; both rows count as used', () => {
    has('applyAllowlist');
    const two = [row({ id: 'r1', match: '^x \\d$' }), row({ id: 'r2', match: '^y$' })];
    const d = div({ onlyA: ['x 1'], onlyB: ['x 2', 'y'] });
    const r = apply([d], two);
    assert.equal(r.uncovered.length, 0);
    assert.deepEqual([...r.used].sort(), ['r1', 'r2']);
    assert.equal(apply([div({ onlyA: ['x 1'], onlyB: ['z'] })], two).uncovered.length, 1);
    assert.equal(apply([d], [row({ id: 'r1', match: '^x \\d$' }), row({ id: 'r3', match: '^y$', pairs: 'a:c' })]).uncovered.length, 1);
  });
  test('a bytes row never covers a text file', () => {
    has('applyAllowlist');
    assert.equal(apply([div()], [row({ kind: 'bytes' })]).uncovered.length, 1);
    assert.equal(apply([div({ kind: 'bytes' })], [row({ kind: 'bytes' })]).uncovered.length, 0);
  });
  test('a paired row (match starting with =) covers only when the captured value is equal on both sides', () => {
    has('applyAllowlist');
    const paired = [row({ match: '=^- V:  ?(v\\S+)$' })];
    assert.equal(apply([div({ onlyA: ['- V:  v1.2'], onlyB: ['- V: v1.2'] })], paired).uncovered.length, 0);
    assert.equal(apply([div({ onlyA: ['- V:  v1.2'], onlyB: ['- V: v1.3'] })], paired).uncovered.length, 1, 'a wrong version on one twin is not excused');
    assert.equal(apply([div({ onlyA: ['- V:  v1.2'], onlyB: [] })], paired).uncovered.length, 1, 'a line on one side only is not excused');
    assert.equal(apply([div({ onlyA: ['- V:  v1.2'], onlyB: ['- V: v1.2', '- other'] })], paired).uncovered.length, 1);
  });
  test('the committed pin row excuses the spacing and nothing else about the version', () => {
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1'] });
    const pin = rows.filter((r) => r.id === 'pin-template-version-spacing');
    const d = (a, b) => ({ pair: 'sh:ps1', path: '.aai/system/AAI_PIN.md', kind: 'lines', detail: 'd', onlyA: [a], onlyB: [b] });
    const run = (x) => M.applyAllowlist([x], pin, { scenario: 'SY-01', host: { ...HOST_POSIX, bsdSed: true } }).uncovered.length;
    assert.equal(run(d('- Template version:  v2026.11.1', '- Template version: v2026.11.1')), 0);
    assert.equal(run(d('- Template version:  v2026.11.1', '- Template version: v2026.01.01')), 1);
  });
  test('the committed Windows rows excuse the path spelling, the CR and the byte order mark and nothing else', () => {
    has('probePs5');
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1'] }).filter((r) => r.id.startsWith('win-') && r.id !== 'win-sh-odd-root-dirs');
    assert.equal(rows.length, 5);
    const win = { platform: 'win32', utc: true, ps5: true };
    const d = (path_, a, b) => ({ pair: 'sh:ps1', path: path_, kind: 'lines', detail: 'd', onlyA: a, onlyB: b });
    const left = (x, host = win) => M.applyAllowlist([x], rows, { scenario: 'SY-01', host }).uncovered.length;
    const pin = '.aai/system/AAI_PIN.md';
    const sh = '- Source path: /c/Users/r/AppData/Local/Temp/p/aai-parity-run-x/fx/src';
    const ps = '- Source path: C:\\Users\\r\\AppData\\Local\\Temp\\p\\aai-parity-run-x\\fx\\src';
    assert.equal(left(d(pin, [sh], [ps])), 0);
    assert.equal(left(d(pin, [sh], ['- Source path: C:\\Users\\r\\elsewhere'])), 1, 'a different directory stays visible');
    assert.equal(left(d(pin, ['# AAI Pin'], ['\uFEFF# AAI Pin'])), 0);
    assert.equal(left(d(pin, ['- Profile: core'], ['- Profile: core\r'])), 0);
    assert.equal(left(d(pin, ['- Profile: core'], ['- Profile: extended\r'])), 1, 'a different value stays visible behind the CR');
    assert.equal(left(d('.gitignore', ['.aai/', 'x'], ['.aai/\r', 'x\r'])), 0);
    assert.equal(left(d('.gitignore', ['.aai/'], ['.env\r'])), 1);
    assert.equal(left(d('.gitignore', ['.aai/'], ['.aai/\r']), HOST_POSIX), 1, 'the rows are judged on a Windows host only');
    assert.equal(typeof M.probePs5('definitely-not-a-shell'), 'boolean');
    assert.equal(M.probePs5('definitely-not-a-shell'), false);
  });
  test('a root directory with a mangled name is reported at <odd-root-name> and covered by its own Windows row only', () => {
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1'] });
    const a = new Map([['翿ৠ', { kind: 'dir' }], ['keep', { kind: 'dir' }]]);
    const b = new Map([['keep', { kind: 'dir' }]]);
    const ds = M.compareSnapshots(a, b, 'sh:ps1');
    assert.equal(ds.length, 1);
    assert.equal(ds[0].path, '<odd-root-name>');
    assert.match(ds[0].detail, /\\u\{7fff\}\\u\{9e0\}/);
    const win = { platform: 'win32', utc: true, ps5: true };
    assert.equal(M.applyAllowlist(ds, rows, { scenario: 'UP-01', host: win }).uncovered.length, 0);
    assert.equal(M.applyAllowlist(ds, rows, { scenario: 'SY-01', host: win }).uncovered.length, 1, 'only the update scenario');
    assert.equal(M.applyAllowlist(ds, rows, { scenario: 'UP-01', host: HOST_POSIX }).uncovered.length, 1, 'only a Windows host');
    const plain = M.compareSnapshots(new Map([['ai', { kind: 'dir' }]]), new Map(), 'sh:ps1');
    assert.equal(plain[0].path, 'ai');
    assert.equal(M.applyAllowlist(plain, rows, { scenario: 'UP-01', host: win }).uncovered.length, 1, 'a readable root name stays visible');
  });
  const stale = (rows, ran, o = {}) => {
    const parsed = parse(rows.join('\n'));
    const used = new Set(o.used || []);
    return M.staleRows(parsed, { ran, pairsRun: o.pairsRun || ['a:b'], host: o.host || HOST_POSIX, used, wholeTier: o.wholeTier !== false }).map((r) => r.id);
  };
  test('a bsd-sed row is judged only on a host whose sed is BSD, so a GNU-sed host neither covers nor stales it', () => {
    has('staleRows'); has('probeBsdSed');
    assert.deepEqual(stale([row({ host: 'bsd-sed' })], ['S-1']), []);
    assert.deepEqual(stale([row({ host: 'bsd-sed' })], ['S-1'], { host: { ...HOST_POSIX, bsdSed: false } }), []);
    assert.deepEqual(stale([row({ host: 'bsd-sed' })], ['S-1'], { host: { ...HOST_POSIX, bsdSed: true } }), ['r1'], 'a dead row stays caught where the divergence exists');
    assert.deepEqual(stale([row({ host: 'bsd-sed' })], ['S-1'], { host: { ...HOST_POSIX, bsdSed: true }, used: ['r1'] }), []);
    assert.equal(typeof M.probeBsdSed(), 'boolean');
    const pin = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1'] }).filter((r) => r.id === 'pin-template-version-spacing');
    const d = { pair: 'sh:ps1', path: '.aai/system/AAI_PIN.md', kind: 'lines', detail: 'd', onlyA: ['- Template version:  v1'], onlyB: ['- Template version: v1'] };
    assert.equal(M.applyAllowlist([d], pin, { scenario: 'SY-01', host: { ...HOST_POSIX, bsdSed: true } }).uncovered.length, 0);
    assert.equal(M.applyAllowlist([d], pin, { scenario: 'SY-01', host: { ...HOST_POSIX, bsdSed: false } }).uncovered.length, 1, 'on a GNU-sed host the spacing divergence is a real failure');
  });
  test('a row that covered nothing is stale on a whole-tier run only', () => {
    has('staleRows');
    assert.deepEqual(stale([row()], ['S-1']), ['r1']);
    assert.deepEqual(stale([row()], ['S-1'], { used: ['r1'] }), []);
    assert.deepEqual(stale([row()], ['S-1'], { wholeTier: false }), []);
  });
  test('rows for a scenario, pair or host that did not run are not stale', () => {
    has('staleRows');
    assert.deepEqual(stale([row({ scenario: 'S-9' })], ['S-1']), []);
    assert.deepEqual(stale([row({ scenario: 'S-9,S-1' })], ['S-1']), ['r1']);
    assert.deepEqual(stale([row({ pairs: 'a:c' })], ['S-1']), []);
    assert.deepEqual(stale([row({ host: 'win32' })], ['S-1']), []);
    assert.deepEqual(stale([row({ host: 'utc' })], ['S-1']), []);
    assert.deepEqual(stale([row({ host: 'non-utc' })], ['S-1']), ['r1']);
  });
  test('a dead pair inside a multi-pair row is reported as stale, per row and pair', () => {
    has('staleRows');
    const parsed = parse(row({ pairs: 'a:b,c:c' }));
    const go = (usedPairs, pairsRun) => M.staleRows(parsed, { ran: ['S-1'], pairsRun, host: HOST_POSIX, used: new Set(['r1']), usedPairs: new Set(usedPairs), wholeTier: true }).map((r) => `${r.id} ${r.pair}`);
    assert.deepEqual(go(['r1|a:b'], ['a:b', 'c:c']), ['r1 c:c']);
    assert.deepEqual(go(['r1|a:b', 'r1|c:c'], ['a:b', 'c:c']), []);
    assert.deepEqual(go(['r1|a:b'], ['a:b']), [], 'a pair that did not run is not judged');
    assert.deepEqual(go([], ['a:b', 'c:c']), ['r1 a:b', 'r1 c:c']);
  });
  test('end to end: the dead pair of a two-pair row fails the run naming the pair', () => {
    has('runMatrix');
    const rows = parse(row({ path: 'p.txt', pairs: 'a:b,b:c,a:c' }));
    const mk = (n, c) => fakeTwin(n, { files: { 'p.txt': c } });
    const rep = runFake([mk('a', 'one\n'), mk('b', 'two\n'), mk('c', 'one\n')], [scen()], rows);
    assert.equal(rep.uncovered.length, 0);
    assert.deepEqual(rep.stale.map((s) => `${s.id} ${s.pairs}`), ['r1 a:c']);
    assert.equal(rep.verdict, 'FAIL');
  });
  test('the driver exits 1 naming an uncovered divergence and a stale row (end to end on fakes)', () => {
    has('runMatrix');
    const rep = runFake([fakeTwin('a', { files: { 'p.txt': 'one\n' } }), fakeTwin('b', { files: { 'p.txt': 'two\n' } })], [scen()]);
    assert.equal(rep.verdict, 'FAIL');
    assert.equal(rep.uncovered.length, 1);
    assert.match(rep.uncovered[0].path, /p\.txt/);
    const rows = parse([row({ path: 'p.txt' }), row({ id: 'gone', path: 'nothing.txt' })].join('\n'));
    const rep2 = runFake([fakeTwin('a', { files: { 'p.txt': 'one\n' } }), fakeTwin('b', { files: { 'p.txt': 'two\n' } })], [scen()], rows);
    assert.equal(rep2.uncovered.length, 0);
    assert.deepEqual(rep2.stale.map((r) => r.id), ['gone']);
    assert.equal(rep2.verdict, 'FAIL');
    const rep3 = runFake([fakeTwin('a', { files: { 'p.txt': 'one\n' } }), fakeTwin('b', { files: { 'p.txt': 'two\n' } })], [scen()], rows, { filtered: true });
    assert.deepEqual(rep3.stale, []);
    assert.equal(rep3.verdict, 'PASS');
  });
});

describe('TEST-3564 broken scenarios', () => {
  const ok = { 'p.txt': 'same\n' };
  test('the reference twin missing a step expectation is broken', () => {
    has('runMatrix');
    const rep = runFake([fakeTwin('sh', { files: ok, code: 3 }), fakeTwin('ps1', { files: ok, code: 0 })], [scen()]);
    assert.equal(rep.verdict, 'FAIL');
    assert.equal(rep.scenarios[0].broken.length >= 1, true);
    assert.match(rep.scenarios[0].broken.join('\n'), /step 1/);
  });
  test('two twins failing alike never pass as parity', () => {
    has('runMatrix');
    const rep = runFake([fakeTwin('sh', { files: ok, code: 3 }), fakeTwin('ps1', { files: ok, code: 3 })], [scen()]);
    assert.equal(rep.scenarios[0].divergences.length, 0);
    assert.equal(rep.scenarios[0].broken.length >= 1, true);
    assert.equal(rep.verdict, 'FAIL');
  });
  test('a nonzero expectation is met by a nonzero reference exit', () => {
    has('expectMet');
    assert.equal(M.expectMet('nonzero', 1), true);
    assert.equal(M.expectMet('nonzero', 0), false);
    assert.equal(M.expectMet('0', 0), true);
    assert.equal(M.expectMet('0', 124), false);
    const s = scen({ steps: [{ op: 'sync', profile: 'core', flags: [], expect: 'nonzero' }] });
    const rep = runFake([fakeTwin('sh', { files: ok, code: 1 }), fakeTwin('ps1', { files: ok, code: 1 })], [s]);
    assert.equal(rep.verdict, 'PASS');
  });
  test('a probe path absent from a twin tree is broken, also when both lack it', () => {
    has('runMatrix');
    const rep = runFake([fakeTwin('sh', { files: { 'q.txt': 'x\n' } }), fakeTwin('ps1', { files: { 'q.txt': 'x\n' } })], [scen()]);
    assert.equal(rep.verdict, 'FAIL');
    assert.match(rep.scenarios[0].broken.join('\n'), /p\.txt/);
    const rep2 = runFake([fakeTwin('sh', { files: ok }), fakeTwin('ps1', { files: { 'q.txt': 'x\n' } })], [scen()]);
    assert.match(rep2.scenarios[0].broken.join('\n'), /p\.txt.*ps1|ps1.*p\.txt/);
  });
  test('a healthy pair passes', () => {
    has('runMatrix');
    const rep = runFake([fakeTwin('sh', { files: ok }), fakeTwin('ps1', { files: ok })], [scen()]);
    assert.equal(rep.verdict, 'PASS');
    assert.deepEqual(rep.pairs, ['sh:ps1']);
  });
});

describe('TEST-3564 CRLF-tolerant fixture parsing', () => {
  const PROFILES = ['version: 1', 'core:', '  # templates', '  - .aai/templates/a.md', '  - .aai/other', '', 'next:', '  - x'];
  const isFile = (rel) => rel === '.aai/templates/a.md';
  test('the removable core entry is found in an LF and in a CRLF PROFILES.yaml', () => {
    has('findRemovableCoreEntry');
    assert.equal(M.findRemovableCoreEntry(PROFILES, isFile), 3);
    assert.equal(M.findRemovableCoreEntry(PROFILES.join('\r\n').split('\n'), isFile), 3);
  });
  test('the entry path handed to the file check carries no carriage return, and a missing entry is -1', () => {
    has('findRemovableCoreEntry');
    const seen = [];
    M.findRemovableCoreEntry(PROFILES.join('\r\n').split('\n'), (rel) => { seen.push(rel); return false; });
    assert.deepEqual(seen, ['.aai/templates/a.md']);
    assert.equal(M.findRemovableCoreEntry(['other:', '  - .aai/templates/a.md'], isFile), -1);
  });
  test('the repository PROFILES.yaml yields a removable entry as LF and as CRLF', () => {
    has('findRemovableCoreEntry');
    const text = fs.readFileSync(path.join(ROOT, '.aai/system/PROFILES.yaml'), 'utf8').replace(/\r\n/g, '\n');
    const ok = (rel) => fs.existsSync(path.join(ROOT, rel)) && fs.lstatSync(path.join(ROOT, rel)).isFile();
    const lf = M.findRemovableCoreEntry(text.split('\n'), ok);
    assert.ok(lf > 0);
    assert.equal(M.findRemovableCoreEntry(text.replace(/\n/g, '\r\n').split('\n'), ok), lf);
  });
  test('a CRLF Synced-at stamp line is still normalized and keeps its carriage return', () => {
    has('normalizeSnapshot');
    const t = M.normalizeSnapshot(new Map([['.aai/system/AAI_PIN.md', { kind: 'file', data: Buffer.from('- Synced at (UTC): 2026-01-02T03:04:05Z\r\n'), exec: false }]]));
    assert.equal(t.get('.aai/system/AAI_PIN.md').data.toString(), '- Synced at (UTC): <stamp>\r\n');
    const rep = M.normalizeSnapshot(new Map([['docs/ai/reports/sync-conflicts-20260102-060405.md', { kind: 'file', data: Buffer.from('- Generated at (UTC): 2026-01-02T03:04:05Z\r\n'), exec: false }]]));
    assert.ok(rep.has('docs/ai/reports/sync-conflicts-<stamp>.md') || rep.size === 1);
  });
});

describe('TEST-3566 third twin seam', () => {
  test('every pair i<j is compared, a third twin against both', () => {
    has('runMatrix');
    const ok = { 'p.txt': 'same\n' };
    const rep = runFake([fakeTwin('sh', { files: ok }), fakeTwin('ps1', { files: ok }), fakeTwin('node', { files: ok })], [scen()]);
    assert.deepEqual(rep.pairs, ['sh:ps1', 'sh:node', 'ps1:node']);
    assert.equal(rep.verdict, 'PASS');
  });
  test('a skewing third twin diverges from both others, naming the pairs and the path', () => {
    has('runMatrix');
    const ok = { 'p.txt': 'same\n' };
    const rep = runFake([fakeTwin('sh', { files: ok }), fakeTwin('ps1', { files: ok }), fakeTwin('skew', { files: { 'p.txt': 'samex\n' } })], [scen()]);
    assert.equal(rep.verdict, 'FAIL');
    assert.deepEqual(rep.uncovered.map((d) => d.pair).sort(), ['ps1:skew', 'sh:skew']);
  });
  test('--twin-module appends a module twin under its name; clashes and bad names are refused', async () => {
    has('loadTwinModule');
    const d = scratch('mod');
    put(d, 'm.mjs', 'export default { argv(step, ctx) { return { file: "x", args: [], cwd: ctx.target }; } };\n');
    const t = await M.loadTwinModule('mine', path.join(d, 'm.mjs'), ['sh', 'ps1']);
    assert.equal(t.name, 'mine');
    assert.equal(typeof t.argv, 'function');
    await assert.rejects(() => M.loadTwinModule('sh', path.join(d, 'm.mjs'), ['sh', 'ps1']), /sh/);
    await assert.rejects(() => M.loadTwinModule('Bad_Name', path.join(d, 'm.mjs'), ['sh']), /Bad_Name/);
    put(d, 'n.mjs', 'export default {};\n');
    await assert.rejects(() => M.loadTwinModule('nope', path.join(d, 'n.mjs'), ['sh']), /argv/);
  });
  test('the real registry holds sh and ps1 with the documented argv shapes', () => {
    assert.equal(M.REFERENCE_TWIN, 'sh');
    assert.deepEqual(Object.keys(M.TWINS), ['sh', 'ps1']);
    const ctx = { src: '/s', target: '/t', bash: 'bash', ps: 'pwsh' };
    const sy = { op: 'sync', profile: 'core', flags: [] };
    const a = M.TWINS.sh.argv(sy, ctx);
    assert.deepEqual([a.file, ...a.args], ['bash', '/s/.aai/scripts/aai-sync.sh', '/t', '--profile', 'core']);
    assert.equal(a.cwd, '/t');
    const p = M.TWINS.ps1.argv(sy, ctx);
    assert.equal(p.file, 'pwsh');
    assert.ok(p.args.includes('-File'));
    assert.deepEqual(p.args.slice(p.args.indexOf('-File')), ['-File', '/s/.aai/scripts/aai-sync.ps1', '-TargetRoot', '/t', '-Profile', 'core']);
    const up = { op: 'update', profile: null, flags: [] };
    assert.deepEqual(M.TWINS.sh.argv(up, ctx).args, ['/s/.aai/scripts/aai-update.sh', '--repo', '/s', '--ref', 'main']);
    const upp = M.TWINS.ps1.argv(up, ctx).args;
    assert.deepEqual(upp.slice(upp.indexOf('-File')), ['-File', '/s/.aai/scripts/aai-update.ps1', '-Repo', '/s', '-Ref', 'main']);
    const hk = { op: 'hooks', profile: null, flags: ['force', 'uninstall', 'decline-ref-guard'] };
    assert.deepEqual(M.TWINS.sh.argv(hk, ctx).args, ['.aai/scripts/install-pre-commit-hook.sh', '--force', '--uninstall', '--decline-ref-guard']);
    const hp = M.TWINS.ps1.argv(hk, ctx).args;
    assert.deepEqual(hp.slice(hp.indexOf('-File')), ['-File', '.aai/scripts/install-pre-commit-hook.ps1', '-Force', '-Uninstall', '-DeclineRefGuard']);
  });
  test('real twins: a mirror module twin passes, a one-byte skew fails naming sh:skew and ps1:skew', async () => {
    has('runMatrix');
    const d = scratch('mirror');
    const mirror = { name: 'mirror', argv: (step, ctx) => M.TWINS.sh.argv(step, ctx) };
    const skew = {
      name: 'skew',
      argv(step, ctx) {
        const a = M.TWINS.sh.argv(step, ctx);
        const script = `const {spawnSync}=require('child_process');const r=spawnSync(${JSON.stringify(a.file)},${JSON.stringify(a.args)},{cwd:${JSON.stringify(a.cwd)},stdio:'inherit',env:process.env});`
          + `require('fs').appendFileSync('.aai/system/AAI_PIN.md','x');process.exit(r.status||0);`;
        return { file: process.execPath, args: ['-e', script], cwd: ctx.target };
      },
    };
    const rows = M.parseAllowlist(
      fs.readFileSync(ALLOWLIST, 'utf8').split('\n').map((l) => (l.startsWith('#') || !l.trim() ? l : l.split('\t').map((f, i) => (i === 1 ? f.split(',').flatMap((p) => (p === 'sh:ps1' ? ['sh:ps1', 'ps1:mirror'] : [p])).join(',') : f)).join('\t'))).join('\n'),
      { twins: ['sh', 'ps1', 'mirror', 'skew'] });
    const base = (third) => M.runMatrix({
      scenarios: M.SCENARIOS.filter((s) => s.id === 'SY-01'), twins: [M.TWINS.sh, M.TWINS.ps1, third], rows, matrix: 'smoke', filtered: true,
      ctx: { root: path.join(d, third.name), src: null, bash: 'bash', ps: 'pwsh', host: M.hostInfo() },
    });
    const ok = await base(mirror);
    assert.equal(ok.verdict, 'PASS', JSON.stringify(ok.uncovered));
    assert.ok(ok.pairs.includes('sh:mirror') && ok.pairs.includes('ps1:mirror'));
    const bad = await base(skew);
    assert.equal(bad.verdict, 'FAIL');
    const pairs = bad.uncovered.filter((u) => u.path === '.aai/system/AAI_PIN.md').map((u) => u.pair).sort();
    assert.deepEqual(pairs, ['ps1:skew', 'sh:skew']);
  });
});

describe('TEST-3567 pinned environment', () => {
  test('twinEnv pins TZ, git config and TMPDIR and scrubs AAI_ names', () => {
    has('twinEnv');
    const root = scratch('env');
    const e = M.twinEnv(root, { PATH: process.env.PATH, AAI_ROLE: 'x', AAI_GIT_WRITE: '1', AAI_ANYTHING: '1', TZ: 'UTC', TMPDIR: '/elsewhere', GIT_CONFIG_GLOBAL: '/etc/outside' });
    assert.equal(M.PINNED_TZ, 'Etc/GMT-3');
    assert.equal(e.TZ, 'Etc/GMT-3');
    assert.equal(e.GIT_CONFIG_NOSYSTEM, '1');
    assert.equal(e.GIT_CONFIG_GLOBAL, path.join(root, 'gitconfig'));
    assert.equal(e.TMPDIR, path.join(root, 'tmp'));
    assert.equal(e.TMP, path.join(root, 'tmp'));
    assert.equal(e.TEMP, path.join(root, 'tmp'));
    assert.deepEqual(Object.keys(e).filter((k) => k.startsWith('AAI_')), []);
    assert.equal(e.PATH, process.env.PATH);
  });
  test('an env-recording twin sees the pinned environment although the caller sets AAI_ variables', () => {
    has('runMatrix');
    const root = scratch('rec');
    const rec = path.join(root, 'env.json');
    const twin = {
      name: 'sh',
      argv: (step, ctx) => ({ file: process.execPath, args: ['-e', `require('fs').writeFileSync(${JSON.stringify(rec)},JSON.stringify(process.env));require('fs').writeFileSync('p.txt','x\\n')`], cwd: ctx.target }),
    };
    const saved = { r: process.env.AAI_ROLE, w: process.env.AAI_GIT_WRITE, g: process.env.GIT_CONFIG_GLOBAL };
    process.env.AAI_ROLE = 'implementation'; process.env.AAI_GIT_WRITE = '1'; process.env.GIT_CONFIG_GLOBAL = '/nonexistent/outside';
    try {
      const rep = M.runMatrix({ scenarios: [scen()], twins: [twin], rows: [], matrix: 'smoke', filtered: true, ctx: { root, src: root, bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX } });
      assert.equal(rep.verdict, 'PASS');
    } finally {
      for (const [k, v] of [['AAI_ROLE', saved.r], ['AAI_GIT_WRITE', saved.w], ['GIT_CONFIG_GLOBAL', saved.g]]) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
    }
    const env = JSON.parse(fs.readFileSync(rec, 'utf8'));
    assert.equal(env.TZ, 'Etc/GMT-3');
    assert.equal(env.GIT_CONFIG_NOSYSTEM, '1');
    assert.ok(env.GIT_CONFIG_GLOBAL.startsWith(root));
    assert.ok(env.TMPDIR.startsWith(root));
    assert.deepEqual(Object.keys(env).filter((k) => k.startsWith('AAI_')), []);
  });
  test('HK-01 with a caller core.hooksPath in GIT_CONFIG_GLOBAL still installs into .git/hooks for both twins', () => {
    has('runMatrix');
    const outside = scratch('hp');
    const gc = path.join(outside, 'gc');
    fs.writeFileSync(gc, `[core]\n\thooksPath = ${path.join(outside, 'hooks')}\n`);
    const saved = process.env.GIT_CONFIG_GLOBAL;
    process.env.GIT_CONFIG_GLOBAL = gc;
    let rep;
    try {
      rep = M.runMatrix({
        scenarios: M.SCENARIOS.filter((s) => s.id === 'HK-01'), twins: [M.TWINS.sh, M.TWINS.ps1],
        rows: M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1'] }), matrix: 'smoke', filtered: true,
        ctx: { root: path.join(outside, 'run'), src: null, bash: 'bash', ps: 'pwsh', host: M.hostInfo() },
      });
    } finally { if (saved === undefined) delete process.env.GIT_CONFIG_GLOBAL; else process.env.GIT_CONFIG_GLOBAL = saved; }
    assert.equal(rep.verdict, 'PASS', JSON.stringify([rep.uncovered, rep.scenarios[0].broken]));
    assert.deepEqual(rep.scenarios[0].steps.map((s) => s.code), [0, 0]);
    assert.equal(fs.existsSync(path.join(outside, 'hooks')), false, 'nothing is written to the caller hooksPath');
  });
});

describe('TEST-3569 report timing', () => {
  test('the report carries per-scenario and total seconds and the host fields', () => {
    has('runMatrix');
    const ok = { 'p.txt': 'same\n' };
    const rep = runFake([fakeTwin('sh', { files: ok }), fakeTwin('ps1', { files: ok })], [scen(), scen({ id: 'T-02' })]);
    assert.equal(typeof rep.total_seconds, 'number');
    assert.ok(rep.total_seconds >= 0);
    for (const s of rep.scenarios) assert.equal(typeof s.seconds, 'number');
    assert.deepEqual(rep.scenarios.map((s) => s.id), ['T-01', 'T-02']);
    for (const k of ['verdict', 'host', 'tz', 'matrix', 'twins', 'pairs', 'total_seconds', 'scenarios', 'uncovered', 'stale']) assert.ok(k in rep, k);
    assert.equal(rep.tz, 'Etc/GMT-3');
    assert.deepEqual(rep.scenarios[0].steps.map((s) => [s.twin, s.step, s.code]), [['sh', 1, 0], ['ps1', 1, 0]]);
  });
  test('two steps on one twin also compare its tree after step 2 with its own after step 1', () => {
    has('runMatrix');
    const two = scen({ steps: [{ op: 'hooks', profile: null, flags: [], expect: '0' }, { op: 'hooks', profile: null, flags: [], expect: '0' }] });
    const grow = (name) => ({
      name,
      argv: (step, ctx) => ({ file: process.execPath, args: ['-e', `const fs=require('fs');fs.writeFileSync('p.txt','x\\n');fs.appendFileSync('n.txt','y\\n')`], cwd: ctx.target }),
    });
    const rep = runFake([grow('sh'), grow('ps1')], [two]);
    assert.deepEqual(rep.pairs, ['sh:ps1', 'sh:sh', 'ps1:ps1']);
    assert.deepEqual(rep.uncovered.map((d) => d.pair).sort(), ['ps1:ps1', 'sh:sh']);
  });
});

describe('TEST-3570 trackers', () => {
  const rows = () => M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] });
  test('the committed allowlist parses and holds the seven seed ids', () => {
    has('parseAllowlist');
    const ids = rows().map((r) => r.id);
    for (const s of ['pin-template-version-spacing', 'pin-synced-at-precision', 'gitignore-block-order', 'gitignore-block-headers',
      'session-start-exec-bit', 'conflict-report-name-local-time', 'conflict-report-generated-precision']) assert.ok(ids.includes(s), s);
  });
  test('every tracker is accepted or a known follow-up whose source names the row path', () => {
    has('loadFollowUps');
    const known = M.loadFollowUps(ROOT);
    const byId = new Map(known.map((f) => [f.id, f]));
    for (const r of rows()) {
      if (r.tracker === 'accepted') continue;
      const f = byId.get(r.tracker);
      assert.ok(f, `${r.id}: tracker ${r.tracker} is not in the follow-up registry`);
      const stem = r.path.split('*')[0];
      assert.ok(stem === '' || String(f.source).includes(stem), `${r.id}: source of ${r.tracker} does not name ${stem}`);
    }
  });
  test('trackerProblems reports an unknown tracker', () => {
    has('trackerProblems');
    const parsed = M.parseAllowlist(['r1', 'a:b', '*', 'f.txt', 'lines', 'any', 'fu-parity-nonesuch', '.*', 'x'].join('\t'), { twins: ['a', 'b'] });
    const probs = M.trackerProblems(parsed, [{ id: 'fu-other', source: 'f.txt' }]);
    assert.equal(probs.length, 1);
    assert.match(probs[0], /r1/);
  });
});

describe('TEST-3566b registry defaults and process bounds', () => {
  test('--twins defaults to every registered twin, in registry order, and an explicit list still narrows', () => {
    has('defaultTwinNames');
    assert.deepEqual(M.defaultTwinNames(), Object.keys(M.TWINS));
    const r = cli(['run', '--matrix', 'smoke', '--bash', '/nonexistent/bash-xyz', '--ps', '/nonexistent/pwsh-xyz', '--scenario', 'SY-01']);
    assert.equal(r.status, 3);
    assert.match(r.stderr, /pwsh-xyz/, 'ps1 is a default twin, so its engine is required');
    const one = cli(['run', '--matrix', 'smoke', '--twins', 'sh', '--bash', '/nonexistent/bash-xyz', '--ps', '/nonexistent/pwsh-xyz', '--scenario', 'SY-01']);
    assert.doesNotMatch(one.stderr, /pwsh-xyz/);
  });
  test('a twin step that outlives the bound is killed with every process of its group', { skip: !posix && 'POSIX process groups' }, () => {
    has('runStep');
    const d = scratch('hang');
    const pidFile = path.join(d, 'child.pid');
    put(d, 'hang.sh', `#!/bin/sh\nsleep 300 &\necho $! > '${pidFile}'\nwait\n`, 0o755);
    const r = M.runStep('/bin/sh', [path.join(d, 'hang.sh')], { cwd: d, env: process.env, timeoutMs: 1500 });
    assert.equal(r.code, 124);
    const pid = Number(fs.readFileSync(pidFile, 'utf8').trim());
    assert.ok(pid > 1);
    let alive = true;
    for (let i = 0; i < 20 && alive; i += 1) {
      try { process.kill(pid, 0); Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100); } catch { alive = false; }
    }
    assert.equal(alive, false, 'the background child of the hung twin is gone');
  });
  test('runStep returns the exit code, the output and 127 for a missing tool', () => {
    has('runStep');
    const ok = M.runStep(process.execPath, ['-e', 'console.log("hi");console.error("er");process.exit(3)'], { cwd: ROOT, env: process.env });
    assert.equal(ok.code, 3);
    assert.match(ok.stdout, /hi/);
    assert.match(ok.stderr, /er/);
    assert.equal(M.runStep('/nonexistent/tool-xyz', [], { cwd: ROOT, env: process.env }).code, 127);
  });
  test('the default scratch base prefers /tmp on darwin and otherwise the OS temp dir; AAI_PARITY_SCRATCH wins', () => {
    has('defaultScratchBase');
    const ok = () => true;
    assert.equal(M.defaultScratchBase({ platform: 'darwin', env: {}, tmpdir: '/var/folders/x/T', usable: ok }), '/tmp');
    assert.equal(M.defaultScratchBase({ platform: 'darwin', env: {}, tmpdir: '/var/folders/x/T', usable: () => false }), '/var/folders/x/T');
    assert.equal(M.defaultScratchBase({ platform: 'linux', env: {}, tmpdir: '/tmp', usable: ok }), '/tmp');
    assert.equal(M.defaultScratchBase({ platform: 'win32', env: {}, tmpdir: 'C:\\Temp', usable: ok }), 'C:\\Temp');
    assert.equal(M.defaultScratchBase({ platform: 'darwin', env: { AAI_PARITY_SCRATCH: '/x/y' }, tmpdir: '/var/T', usable: ok }), '/x/y');
  });
  test('a Windows-style path divergence is reported with both lines, naming pair, scenario, kind and path', () => {
    const d = scratch('win');
    const mod = (name, line) => {
      put(d, `${name}-run.cjs`, `const fs = require('fs'); fs.mkdirSync('.aai/system', { recursive: true });\nfs.writeFileSync('.aai/system/AAI_PIN.md', ${JSON.stringify(`${line}\n`)}); fs.writeFileSync('.gitignore', 'x\\n');\n`);
      put(d, `${name}.mjs`, `export default { argv(step, ctx) { return { file: process.execPath, args: [${JSON.stringify(path.join(d, `${name}-run.cjs`))}], cwd: ctx.target }; } };\n`);
    };
    mod('left', '- Source path: /c/Users/x/src');
    mod('right', '- Source path: C:\\Users\\x\\src');
    put(d, 'none.tsv', '# none\n');
    const r = cli(['run', '--matrix', 'smoke', '--scenario', 'SY-01', '--twins', '', '--twin-module', `left=${path.join(d, 'left.mjs')}`, '--twin-module', `right=${path.join(d, 'right.mjs')}`, '--allowlist', path.join(d, 'none.tsv')]);
    assert.equal(r.status, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /UNCOVERED SY-01 left:right lines \.aai\/system\/AAI_PIN\.md/);
    assert.ok(r.stdout.includes('only in left: ["- Source path: /c/Users/x/src"]'), r.stdout);
    assert.ok(r.stdout.includes('only in right: ["- Source path: C:\\\\Users\\\\x\\\\src"]'), r.stdout);
  });
});

describe('driver import and CLI', () => {
  test('importing the module runs nothing and a usage error exits 2', () => {
    assert.equal(typeof M.main, 'function');
    assert.equal(cli(['frobnicate']).status, 2);
    assert.equal(cli(['run', '--matrix', 'bogus']).status, 2);
  });
  test('a missing --bash tool exits 3 naming it', () => {
    const r = cli(['run', '--matrix', 'smoke', '--bash', '/nonexistent/bash-xyz', '--scenario', 'SY-01']);
    assert.equal(r.status, 3);
    assert.match(r.stderr, /bash-xyz/);
  });
  test('an allowlist that does not parse exits 2 naming the row', () => {
    const d = scratch('bad');
    put(d, 'a.tsv', 'bad-row\tsh:ps1\t*\tf\tlines\tany\taccepted\t.*\t\n');
    const r = cli(['run', '--matrix', 'smoke', '--allowlist', path.join(d, 'a.tsv'), '--scenario', 'SY-01']);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /bad-row/);
    assert.match(r.stderr, /reason/);
  });
});
