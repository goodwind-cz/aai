// install-parity.test.mjs - node:test cases for tests/skills/lib/install-parity.mjs
// (docs/specs/SPEC-0284-spec-install-path-parity-harness.md, TEST-3560 to TEST-3570).
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
const UPDATE_ALLOWLIST_BASE = 'tests/skills/lib/install-parity-allowlist.tsv';

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
  const specPath = (id) => {
    const dir = path.join(ROOT, 'docs/specs');
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith('.md')) continue;
      const t = fs.readFileSync(path.join(dir, f), 'utf8');
      if (new RegExp(`^id: ${id}$`, 'm').test(t)) return path.join(dir, f);
    }
    throw new Error(`spec ${id} not found`);
  };
  // The matrix tables of both specs: SPEC-0284's rows first, then the bootstrap-on-node rows.
  const specRows = () => {
    const rows = [];
    for (const [id, prefix] of [['spec-install-path-parity-harness', 'SY|UP|HK'], ['spec-bootstrap-on-node', 'BS']]) {
      for (const l of fs.readFileSync(specPath(id), 'utf8').split('\n')) {
        const m = new RegExp(`^\\| ((?:${prefix})-\\d\\d) \\| (smoke|default|full) \\|`).exec(l);
        if (m) rows.push({ id: m[1], tier: m[2] });
      }
    }
    return rows;
  };
  const rank = { smoke: 0, default: 1, full: 2 };
  for (const [tier, n] of [['smoke', 9], ['default', 21], ['full', 29]]) {
    test(`list --matrix ${tier} prints the ${n} ids of the matrix tables in order`, () => {
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
  test('the closed list holds exactly N1 N2 N3 N4 N5 E1 E2 with reasons', () => {
    assert.deepEqual(M.NORMALIZATIONS.map((n) => n.id), ['N1', 'N2', 'N3', 'N4', 'N5', 'E1', 'E2']);
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
  test('N3 renames every report by ordinal, flagging a name that disagrees with its Generated-at second', () => {
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
  test('N3 treats a name 0 to 2 s before its Generated-at second as agreeing (two clock reads), not 3 s, not later, not an hour off', () => {
    const flag = (name, gen) => snapOf({ [`docs/ai/reports/sync-conflicts-${name}.md`]: `- Generated at (UTC): ${gen}\n` }).get('docs/ai/reports/sync-conflicts-<stamp-1>.md').nameSkew === true;
    assert.equal(flag('20261110-185419', '2026-11-10T18:54:19Z'), false);
    assert.equal(flag('20261110-185418', '2026-11-10T18:54:19Z'), false);
    assert.equal(flag('20261110-185417', '2026-11-10T18:54:19Z'), false);
    assert.equal(flag('20261110-185416', '2026-11-10T18:54:19Z'), true);
    assert.equal(flag('20261110-185420', '2026-11-10T18:54:19Z'), true);
    assert.equal(flag('20261110-215419', '2026-11-10T18:54:19Z'), true);
    assert.equal(flag('20261110-235959', '2026-11-11T00:00:00Z'), false);
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
    refused(row({ pairs: 'b:a' }), 'r1', 'pairs');
    refused(row({ pairs: 'a:b,c:a' }), 'r1', 'pairs');
    assert.equal(parse(row({ pairs: 'a:b,a:a,c:c,a:c' }))[0].id, 'r1');
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
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] });
    const pin = rows.filter((r) => r.id === 'pin-template-version-spacing');
    const d = (a, b) => ({ pair: 'sh:ps1', path: '.aai/system/AAI_PIN.md', kind: 'lines', detail: 'd', onlyA: [a], onlyB: [b] });
    const run = (x) => M.applyAllowlist([x], pin, { scenario: 'SY-01', host: { ...HOST_POSIX, bsdSed: true } }).uncovered.length;
    assert.equal(run(d('- Template version:  v2026.11.1', '- Template version: v2026.11.1')), 0);
    assert.equal(run(d('- Template version:  v2026.11.1', '- Template version: v2026.01.01')), 1);
  });
  test('the committed Windows rows excuse the path spelling, the CR and the byte order mark, plus (disclosed in their reasons) a Source path naming another aai-parity directory or present on one side only', () => {
    has('probePs5');
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] }).filter((r) => r.id.startsWith('win-') && r.id !== 'win-sh-odd-root-dirs' && r.id !== 'win-bootstrap-target-root');
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
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] });
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
  test('the win-source-path rows excuse only the two spellings of a scratch fx/src path', () => {
    has('applyAllowlist');
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] }).filter((r) => r.id === 'win-source-path-pin');
    const win = { platform: 'win32', utc: true, ps5: false };
    const d = (a, b) => ({ pair: 'sh:ps1', path: '.aai/system/AAI_PIN.md', kind: 'lines', detail: 'd', onlyA: [`- Source path: ${a}`], onlyB: [`- Source path: ${b}\r`] });
    const go = (a, b) => M.applyAllowlist([d(a, b)], rows, { scenario: 'SY-01', host: win }).uncovered.length;
    assert.equal(go('/c/Users/x/AppData/Local/Temp/aai-parity-run-ab12/fx/src', 'C:\\Users\\x\\AppData\\Local\\Temp\\aai-parity-run-ab12\\fx\\src'), 0);
    assert.equal(go('/c/elsewhere/project/fx/src', 'C:\\elsewhere\\project\\fx\\src'), 1, 'a directory outside the scratch root stays visible');
    assert.equal(go('/c/Users/x/Temp/aai-parity-run-ab12/fx/other', 'C:\\Users\\x\\Temp\\aai-parity-run-ab12\\fx\\src'), 1, 'a different leaf stays visible');
  });
  // The frozen twins run from the syref copy of the scratch source and the module from fx/src (SY-01), so on a Windows host the pin and
  // the report name syref in the POSIX spelling for sh and the Windows spelling for ps1, and fx\src for the module; ps1 writes the pin with LF inside and
  // CRLF at its end and the report with CRLF throughout, a byte order mark under Windows PowerShell 5.1 and seven fraction digits. Lines are the ones the CI run 45069641354 printed.
  test('the committed rows cover the syref source path of the frozen twins on a Windows host, for sh:ps1 and for ps1:node', () => {
    has('applyAllowlist');
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] });
    const win = { platform: 'win32', utc: true, ps5: true };
    const run = 'C:\\Users\\runneradmin\\AppData\\Local\\Temp\\aai-parity-pester-7efbfa2ab524\\aai-parity-run-thDytQ';
    const posix = '/c/Users/runneradmin/AppData/Local/Temp/aai-parity-pester-7efbfa2ab524/aai-parity-run-thDytQ';
    const left = (pair, file, onlyA, onlyB) => M.applyAllowlist([{ pair, path: file, kind: 'lines', detail: 'd', onlyA, onlyB }], rows, { scenario: 'SY-01', host: win }).uncovered.length;
    const pin = '.aai/system/AAI_PIN.md';
    const report = 'docs/ai/reports/sync-conflicts-<stamp-1>.md';
    const shPin = ['# AAI Pin', `- Source path: ${posix}/syref`, '- Synced at (UTC): <stamp>'];
    const psPin = ['\uFEFF# AAI Pin', `- Source path: ${run}\\syref`, '- Synced at (UTC): 2026-11-22T21:02:05.1485042Z'];
    const nodePin = ['# AAI Pin', `- Source path: ${run}\\fx\\src`, '- Synced at (UTC): <stamp>'];
    assert.equal(left('sh:ps1', pin, shPin, psPin), 0, 'sh and ps1 both run from syref, in two spellings');
    assert.equal(left('ps1:node', pin, psPin, nodePin), 0, 'ps1 from syref, the module from fx\\src');
    const shRep = ['# Sync Conflict Advisory', '- Generated at (UTC): <stamp>', `- Source: ${posix}/syref`];
    const psRep = ['\uFEFF# Sync Conflict Advisory\r', '- Generated at (UTC): 2026-11-22T21:02:05.0698568Z\r', `- Source: ${run}\\syref\r`];
    const nodeRep = ['# Sync Conflict Advisory', '- Generated at (UTC): <stamp>', `- Source: ${run}\\fx\\src`];
    assert.equal(left('sh:ps1', report, shRep, psRep), 0);
    assert.equal(left('ps1:node', report, psRep, nodeRep), 0);
    // what stays visible: a syref outside an aai-parity scratch directory, another leaf, and a Source path on one side only
    assert.equal(left('sh:ps1', pin, ['- Source path: /c/elsewhere/syref'], ['- Source path: C:\\elsewhere\\syref']), 1);
    assert.equal(left('sh:ps1', pin, [`- Source path: ${posix}/other`], [`- Source path: ${run}\\other`]), 1);
    assert.equal(left('ps1:node', pin, [`- Source path: ${run}\\syref`], ['# AAI Pin']), 1);
  });
  test('a bsd-sed row is judged only on a host whose sed is BSD, so a GNU-sed host neither covers nor stales it', () => {
    has('staleRows'); has('probeBsdSed');
    assert.deepEqual(stale([row({ host: 'bsd-sed' })], ['S-1']), []);
    assert.deepEqual(stale([row({ host: 'bsd-sed' })], ['S-1'], { host: { ...HOST_POSIX, bsdSed: false } }), []);
    assert.deepEqual(stale([row({ host: 'bsd-sed' })], ['S-1'], { host: { ...HOST_POSIX, bsdSed: true } }), ['r1'], 'a dead row stays caught where the divergence exists');
    assert.deepEqual(stale([row({ host: 'bsd-sed' })], ['S-1'], { host: { ...HOST_POSIX, bsdSed: true }, used: ['r1'] }), []);
    assert.equal(typeof M.probeBsdSed(), 'boolean');
    const pin = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] }).filter((r) => r.id === 'pin-template-version-spacing');
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
  test('an intermittent row (match ?) covers when present and is never stale, and the parser refuses it elsewhere', () => {
    has('staleRows'); has('parseAllowlist');
    const im = (o = {}) => row({ kind: 'missing', tracker: 'fu-x-y', match: '?', host: 'posix', ...o });
    assert.deepEqual(stale([im()], ['S-1']), [], 'covering nothing is not stale');
    assert.deepEqual(stale([im()], ['S-1'], { used: ['r1'] }), []);
    assert.deepEqual(stale([row({ kind: 'missing', tracker: 'fu-x-y', match: '-' })], ['S-1']), ['r1'], 'a plain missing row still goes stale');
    const ds = [{ pair: 'a:b', path: 'f.txt', kind: 'missing', detail: 'd' }];
    assert.equal(M.applyAllowlist(ds, parse(im()), { scenario: 'S-1', host: HOST_POSIX }).uncovered.length, 0, 'it still covers');
    refused(im({ kind: 'lines' }), 'r1', 'match');
    refused(im({ kind: 'bytes' }), 'r1', 'match');
    refused(im({ tracker: 'accepted' }), 'r1', 'match');
    refused(im({ path: 'docs/*', host: 'win32' }), 'r1', 'match');
    refused(im({ host: 'any' }), 'r1', 'match');
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
    assert.deepEqual(Object.keys(M.TWINS), ['sh', 'ps1', 'node', 'launcher']);
    const ctx = { src: '/s', target: '/t', bash: 'bash', ps: 'pwsh' };
    const sy = { op: 'sync', profile: 'core', flags: [] };
    const sctx = { ...ctx, syref: '/sy' };
    const a = M.TWINS.sh.argv(sy, sctx);
    assert.deepEqual([a.file, ...a.args], ['bash', '/sy/.aai/scripts/aai-sync.sh', '/t', '--profile', 'core']);
    assert.equal(a.cwd, '/t');
    const p = M.TWINS.ps1.argv(sy, sctx);
    assert.equal(p.file, 'pwsh');
    assert.ok(p.args.includes('-File'));
    assert.deepEqual(p.args.slice(p.args.indexOf('-File')), ['-File', '/sy/.aai/scripts/aai-sync.ps1', '-TargetRoot', '/t', '-Profile', 'core']);
    const up = { op: 'update', profile: null, flags: [] };
    assert.deepEqual(M.TWINS.sh.argv(up, { ...ctx, upref: '/u' }).args, ['/u/.aai/scripts/aai-update.sh', '--repo', '/s', '--ref', 'main']);
    const upp = M.TWINS.ps1.argv(up, ctx).args;
    assert.deepEqual(upp.slice(upp.indexOf('-File')), ['-File', '/s/.aai/scripts/aai-update.ps1', '-Repo', '/s', '-Ref', 'main']);
    const hk = { op: 'hooks', profile: null, flags: ['force', 'uninstall', 'decline-ref-guard'] };
    const hctx = { ...ctx, hkref: '/hk' };
    assert.deepEqual(M.TWINS.sh.argv(hk, hctx).args, ['/hk/.aai/scripts/install-pre-commit-hook.sh', '--force', '--uninstall', '--decline-ref-guard']);
    const hp = M.TWINS.ps1.argv(hk, hctx).args;
    assert.deepEqual(hp.slice(hp.indexOf('-File')), ['-File', '/hk/.aai/scripts/install-pre-commit-hook.ps1', '-Force', '-Uninstall', '-DeclineRefGuard']);
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
      { twins: ['sh', 'ps1', 'mirror', 'skew', 'node', 'launcher'] });
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
  test('TEST-3585: no twin step carries GIT_REDIRECT_STDERR, with ps5 true or false', () => {
    has('runMatrix');
    const base = { src: '/src', target: '/t', bash: 'bash', ps: 'pwsh' };
    const steps = [{ op: 'sync' }, { op: 'update' }, { op: 'hooks', flags: [] }];
    for (const twin of ['sh', 'ps1']) {
      for (const st of steps) {
        for (const ps5 of [true, false]) {
          const a = M.TWINS[twin].argv({ ...st, index: 0 }, { ...base, ps5 });
          assert.equal('GIT_REDIRECT_STDERR' in (a.env || {}), false, `${twin} ${st.op} ps5=${ps5}`);
          assert.equal(JSON.stringify(a).includes('GIT_REDIRECT_STDERR'), false, `${twin} ${st.op} ps5=${ps5} argv`);
        }
      }
    }
    const src = fs.readFileSync(new URL('./install-parity.mjs', import.meta.url), 'utf8');
    assert.equal(src.includes('GIT_REDIRECT_STDERR'), false);
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
        rows: M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] }), matrix: 'smoke', filtered: true,
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
  const rows = () => M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node', 'launcher'] });
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

describe('TEST-3566b step bound from the environment and timeouts as infrastructure breaks', () => {
  test('AAI_PARITY_STEP_TIMEOUT overrides the 300 s default in seconds and refuses a non-number', () => {
    has('stepTimeoutMs');
    assert.equal(M.stepTimeoutMs({}), 300000);
    assert.equal(M.stepTimeoutMs({ AAI_PARITY_STEP_TIMEOUT: '' }), 300000);
    assert.equal(M.stepTimeoutMs({ AAI_PARITY_STEP_TIMEOUT: '900' }), 900000);
    assert.equal(M.stepTimeoutMs({ AAI_PARITY_STEP_TIMEOUT: '1.5' }), 1500);
    for (const bad of ['0', '-3', 'abc', '10s']) assert.throws(() => M.stepTimeoutMs({ AAI_PARITY_STEP_TIMEOUT: bad }), /AAI_PARITY_STEP_TIMEOUT/);
    const r = cli(['run', '--matrix', 'smoke', '--scenario', 'SY-01'], { env: { ...process.env, AAI_PARITY_STEP_TIMEOUT: 'abc' } });
    assert.equal(r.status, 2);
    assert.match(r.stderr, /AAI_PARITY_STEP_TIMEOUT/);
  });
  test('a step that outlives the bound is an INFRA timeout naming scenario, twin and step, exit 4, with no divergence or stale judgement', { skip: !posix && 'POSIX process groups' }, () => {
    const d = scratch('infra');
    const hang = (name) => {
      put(d, `${name}.mjs`, `export default { argv(step, ctx) { return { file: process.execPath, args: ['-e', 'setTimeout(function () {}, 60000)'], cwd: ctx.target }; } };\n`);
    };
    hang('hang');
    hang('hang2'); // two twins: a scenario run by fewer than two is refused before it runs
    put(d, 'none.tsv', '# none\n');
    const r = cli(['run', '--matrix', 'smoke', '--scenario', 'SY-01', '--twins', '', '--twin-module', `hang=${path.join(d, 'hang.mjs')}`, '--twin-module', `hang2=${path.join(d, 'hang2.mjs')}`, '--allowlist', path.join(d, 'none.tsv')], { env: { ...process.env, AAI_PARITY_STEP_TIMEOUT: '1' } });
    assert.equal(r.status, 4, r.stdout + r.stderr);
    assert.match(r.stdout, /^INFRA timeout SY-01 hang 1$/m);
    assert.doesNotMatch(r.stdout, /UNCOVERED|STALE|verdict/);
  });
  test('a step that exits 124 on its own is a plain exit code, not a timeout', () => {
    has('runStep');
    const r = M.runStep(process.execPath, ['-e', 'process.exit(124)'], { cwd: ROOT, env: process.env });
    assert.equal(r.code, 124);
    assert.equal(r.timedOut, false);
  });
});

describe('driver import and CLI', () => {
  test('importing the module runs nothing and a usage error exits 2', () => {
    assert.equal(typeof M.main, 'function');
    assert.equal(cli(['frobnicate']).status, 2);
    assert.equal(cli(['run', '--matrix', 'bogus']).status, 2);
  });
  test('TEST-3975 a twin selection with no permitted pair for a scenario exits 2 naming it (ps1,node on UP-01)', () => {
    const r = cli(['run', '--matrix', 'full', '--twins', 'ps1,node', '--scenario', 'UP-01']);
    assert.equal(r.status, 2, r.stderr);
    assert.match(r.stderr, /UP-01/);
    assert.match(r.stderr, /no permitted pair/);
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

// TEST-3934 (spec-test-residue-files-and-processes, Spec-AC-12): a root entry whose name has no UTF-8 form (the
// random wide-character directories of fu-parity-win-odd-root-dirs on Windows) comes back from readdir with
// replacement characters, and lstat of that name fails ENOENT. The snapshot must record such an odd entry as a
// directory (the allowlist row win-sh-odd-root-dirs covers it) instead of crashing the whole matrix.
describe('TEST-3934 an unreadable odd root name does not crash the snapshot', () => {
  test('lstat ENOENT on a non-ASCII name is recorded, any other is thrown', () => {
    const d = scratch('oddname');
    put(d, 'a.txt', 'a\n');
    const odd = 'odd-éé';
    fs.mkdirSync(path.join(d, odd));
    const real = fs.lstatSync;
    fs.lstatSync = (p, ...rest) => {
      if (path.basename(String(p)) === odd) { const e = new Error(`ENOENT: no such file or directory, lstat '${p}'`); e.code = 'ENOENT'; throw e; }
      return real.call(fs, p, ...rest);
    };
    const errWrite = process.stderr.write;
    let errText = '';
    process.stderr.write = (chunk, ...rest) => { errText += String(chunk); return true; };
    try {
      const snap = M.snapshot(d);
      assert.deepEqual(snap.get(odd), { kind: 'dir' });
      assert.equal(snap.get('a.txt').kind, 'file');
    } finally { fs.lstatSync = real; process.stderr.write = errWrite; }
    // the skipped subtree is named, never silently truncated (degrade-with-NOTE)
    assert.match(errText, /NOTE - .*could not be read by name.*not compared/);
    const plain = 'plain-ascii';
    fs.mkdirSync(path.join(d, plain));
    fs.lstatSync = (p, ...rest) => {
      if (path.basename(String(p)) === plain) { const e = new Error('ENOENT'); e.code = 'ENOENT'; throw e; }
      return real.call(fs, p, ...rest);
    };
    try {
      assert.throws(() => M.snapshot(d), /ENOENT/);
    } finally { fs.lstatSync = real; }
  });
});

describe('driver refuses a scenario with fewer than two twins', () => {
  test('--twins node on SY-01 exits 2 naming the scenario, never a crash or a pass', () => {
    const r = cli(['run', '--matrix', 'smoke', '--scenario', 'SY-01', '--twins', 'node']);
    assert.equal(r.status, 2, r.stderr);
    assert.match(r.stderr, /scenario SY-01 .*1 of the selected twins \(node\)/);
    assert.doesNotMatch(r.stderr + r.stdout, /TypeError/);
    assert.doesNotMatch(r.stdout, /verdict PASS/);
  });
  test('a single selected twin on a scenario it runs is refused too', () => {
    const r = cli(['run', '--matrix', 'smoke', '--scenario', 'SY-01', '--twins', 'sh']);
    assert.equal(r.status, 2, r.stderr);
    assert.match(r.stderr, /scenario SY-01 .*1 of the selected twins \(sh\)/);
  });
});

// TEST-3975 (spec-update-on-node, Spec-AC-16, D-PARITY): the module is the third twin on update scenarios and is paired only with
// the bash reference; bootstrap scenarios keep all three pairs.
describe('TEST-3975 update peers', () => {
  const upScen = () => scen({ id: 'U-01', op: 'update', steps: [{ op: 'update', profile: null, flags: [], expect: '0' }] });
  const ok = { 'p.txt': 'same\n' };
  const withPeers = (t, peers) => ({ ...t, peers });
  const run3 = (nodeTwin, scenarios = [upScen()]) => runFake([fakeTwin('sh', { files: ok }), fakeTwin('ps1', { files: ok }), nodeTwin], scenarios, [], {
    ctx: { root: scratch('peers'), src: null, upref: '/unused', bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX },
  });
  test('a twin with peers for update is paired only with the twins it lists, on update scenarios only', () => {
    has('runMatrix');
    const rep = run3(withPeers(fakeTwin('node', { files: ok }), { update: ['sh'] }));
    assert.deepEqual(rep.pairs, ['sh:ps1', 'sh:node']);
    assert.equal(rep.verdict, 'PASS', JSON.stringify(rep.uncovered));
  });
  test('a peers entry for update does not narrow a scenario of another operation', () => {
    has('runMatrix');
    const rep = run3(withPeers(fakeTwin('node', { files: ok }), { update: ['sh'] }), [scen()]);
    assert.deepEqual(rep.pairs, ['sh:ps1', 'sh:node', 'ps1:node']);
  });
  test('a fake node twin with peers that writes one more byte fails naming sh:node, and no ps1:node pair exists', () => {
    has('runMatrix');
    const rep = run3(withPeers(fakeTwin('node', { files: { 'p.txt': 'samex\n' } }), { update: ['sh'] }));
    assert.equal(rep.verdict, 'FAIL');
    assert.deepEqual(rep.uncovered.map((d) => d.pair), ['sh:node']);
    assert.deepEqual(rep.pairs, ['sh:ps1', 'sh:node']);
  });
  test('the real registry: the node twin runs bootstrap, update and hooks, peers only sh for update, and the update argv of sh and node', () => {
    assert.deepEqual(M.TWINS.node.ops, ['bootstrap', 'update', 'hooks', 'sync']);
    assert.deepEqual(M.TWINS.node.peers, { update: ['sh', 'launcher'] });
    assert.equal(M.TWINS.sh.peers, undefined);
    assert.equal(M.TWINS.ps1.peers, undefined);
    const ctx = { src: '/s', target: '/t', bash: '/bin/bash', ps: 'pwsh', upref: '/u', bsref: '/b' };
    const up = { op: 'update', profile: null, flags: [] };
    const sh = M.TWINS.sh.argv(up, ctx);
    assert.deepEqual([sh.file, ...sh.args], ['/bin/bash', '/u/.aai/scripts/aai-update.sh', '--repo', '/s', '--ref', 'main']);
    const nd = M.TWINS.node.argv(up, ctx);
    assert.equal(nd.file, process.execPath);
    assert.deepEqual(nd.args, [path.join('/s', '.aai', 'scripts', 'aai-update.mjs'), '--repo', '/s', '--ref', 'main']);
    assert.equal(nd.cwd, '/t');
    assert.deepEqual(nd.env, { AAI_UPDATE_SYNC_RUNNER: '/bin/bash' });
    const bs = M.TWINS.node.argv({ op: 'bootstrap', flags: [] }, ctx);
    assert.equal(bs.args[0], path.join('/b', '.aai', 'scripts', 'aai-bootstrap.mjs'));
  });
  test('the driver source holds the exact node update line and the peers text once each', () => {
    const src = fs.readFileSync(DRIVER, 'utf8');
    const line = "      return { file: process.execPath, args: [path.join(ctx.src, '.aai', 'scripts', 'aai-update.mjs'), '--repo', ctx.src, '--ref', 'main'], cwd: ctx.target, env: { AAI_UPDATE_SYNC_RUNNER: ctx.bash } };";
    assert.equal(src.split(line).length - 1, 1);
    assert.equal(src.split("peers: { update: ['sh', 'launcher'] }").length - 1, 1);
  });
  test('the committed allowlist keeps every row of the update ride, and win-sh-odd-root-dirs is paired sh:ps1,sh:node', () => {
    has('parseAllowlist');
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] });
    const odd = rows.filter((r) => r.id === 'win-sh-odd-root-dirs');
    assert.equal(odd.length, 1);
    assert.deepEqual(odd[0].pairList, ['sh:ps1', 'sh:node']);
    // sync-on-node run 6c: the sync scenarios gave the module twin its own ps1:node rows, so only the update rows are checked
    assert.ok(rows.filter((r) => !r.id.startsWith('sync-') && r.scenario !== '*' && /^UP-/.test(r.scenario)).every((r) => !r.pairList.includes('ps1:node')));
    const base = spawnSync('git', ['show', `30c983ef:${UPDATE_ALLOWLIST_BASE}`], { cwd: ROOT, encoding: 'utf8' });
    if (base.status === 0) {
      const baseRows = M.parseAllowlist(base.stdout, { twins: ['sh', 'ps1', 'node'] });
      const ids = rows.map((r) => r.id);
      for (const r of baseRows) assert.ok(ids.includes(r.id), r.id);
    }
  });
});

// TEST-3995 (pre-commit-installer-on-node, Spec-AC-16, D-PARITY): the module is the third twin on hook scenarios, all three
// pairs are compared, the sh and ps1 twins run the frozen references from ctx.hkref, and the uninstall row is widened.
describe('TEST-3995 hook twins', () => {
  const hkScen = (over = {}) => scen({ id: 'HK-T1', op: 'hooks', setup: 'empty', steps: [{ op: 'hooks', profile: null, flags: [], expect: '0' }], probes: ['.git/hooks/pre-commit'], ...over });
  const hook = (body) => ({ '.git/hooks/pre-commit': body });
  const same = '#!/bin/sh\necho hook\n';
  const run3 = (nodeFiles, extra = {}) => runFake([fakeTwin('sh', { files: hook(same) }), fakeTwin('ps1', { files: hook(same) }), fakeTwin('node', { files: nodeFiles })], [hkScen()], [], {
    ctx: { root: scratch('hk'), src: null, hkref: '/unused', bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX },
    ...extra,
  });
  test('a hook scenario compares all three pairs and passes when the three hooks are equal', () => {
    has('runMatrix');
    const rep = run3(hook(same));
    assert.deepEqual(rep.pairs, ['sh:ps1', 'sh:node', 'ps1:node']);
    assert.equal(rep.verdict, 'PASS', JSON.stringify(rep.uncovered));
  });
  test('a fake node twin that writes one more byte into a hook fails naming sh:node', () => {
    has('runMatrix');
    const rep = run3(hook(`${same}x`));
    assert.equal(rep.verdict, 'FAIL');
    assert.ok(rep.uncovered.some((d) => d.pair === 'sh:node'), JSON.stringify(rep.uncovered));
  });
  test('runMatrix builds hkref once for a hook scenario, hands it to every twin, and builds none for another operation', () => {
    has('runMatrix');
    const seen = [];
    const spy = (name, files) => ({ name, argv(step, ctx) { seen.push([name, ctx.hkref]); return fakeTwin(name, { files }).argv(step, ctx); } });
    const root = scratch('hkref');
    M.runMatrix({
      scenarios: [hkScen()], twins: [spy('sh', hook(same)), spy('ps1', hook(same)), spy('node', hook(same))], rows: [], matrix: 'smoke', filtered: false,
      ctx: { root, src: root, bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX },
    });
    assert.equal(seen.length, 3);
    const refs = new Set(seen.map((x) => x[1]));
    assert.equal(refs.size, 1);
    const [ref] = refs;
    assert.ok(fs.existsSync(path.join(ref, '.aai', 'scripts', 'install-pre-commit-hook.sh')), 'the frozen bash reference is there');
    assert.ok(fs.existsSync(path.join(ref, '.aai', 'scripts', 'install-pre-commit-hook.ps1')), 'the frozen PowerShell reference is there');
    const other = [];
    M.runMatrix({
      scenarios: [scen()], twins: [{ name: 'sh', argv(step, ctx) { other.push(ctx.hkref); return fakeTwin('sh', { files: { 'p.txt': 'a\n' } }).argv(step, ctx); } }, fakeTwin('ps1', { files: { 'p.txt': 'a\n' } })], rows: [], matrix: 'smoke', filtered: false,
      ctx: { root: scratch('nohkref'), src: root, bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX },
    });
    assert.deepEqual(other, [undefined]);
  });
  test('the real registry: the node twin runs bootstrap, update and hooks with peers for update only, and the hooks argv of the three twins', () => {
    assert.deepEqual(M.TWINS.node.ops, ['bootstrap', 'update', 'hooks', 'sync']);
    assert.deepEqual(M.TWINS.node.peers, { update: ['sh', 'launcher'] });
    const ctx = { src: '/s', target: '/t', bash: '/bin/bash', ps: 'pwsh', hkref: '/hk' };
    const hk = { op: 'hooks', profile: null, flags: ['force', 'uninstall', 'decline-ref-guard'] };
    const sh = M.TWINS.sh.argv(hk, ctx);
    assert.deepEqual([sh.file, ...sh.args], ['/bin/bash', '/hk/.aai/scripts/install-pre-commit-hook.sh', '--force', '--uninstall', '--decline-ref-guard']);
    assert.equal(sh.cwd, '/t');
    const ps = M.TWINS.ps1.argv(hk, ctx);
    assert.deepEqual(ps.args.slice(ps.args.indexOf('-File')), ['-File', '/hk/.aai/scripts/install-pre-commit-hook.ps1', '-Force', '-Uninstall', '-DeclineRefGuard']);
    const nd = M.TWINS.node.argv(hk, ctx);
    assert.equal(nd.file, process.execPath);
    assert.deepEqual(nd.args, [path.join('/t', '.aai', 'scripts', 'install-pre-commit-hook.mjs'), '--force', '--uninstall', '--decline-ref-guard']);
    assert.equal(nd.cwd, '/t');
    const src = fs.readFileSync(DRIVER, 'utf8');
    const line = "      if (step.op === 'hooks') return { file: process.execPath, args: [path.join(ctx.target, '.aai', 'scripts', 'install-pre-commit-hook.mjs'), ...(step.flags || []).map((f) => SH_FLAG[f])], cwd: ctx.target };";
    assert.equal(src.split(line).length - 1, 1);
  });
  test('the widened hk-uninstall-removes-hooks row pairs sh:sh,ps1:ps1,node:node, and every row of the hook ride is kept', () => {
    has('parseAllowlist');
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] });
    const row = rows.filter((r) => r.id === 'hk-uninstall-removes-hooks');
    assert.equal(row.length, 1);
    assert.equal(row[0].pairs, 'sh:sh,ps1:ps1,node:node');
    assert.match(row[0].reason, /the module twin's uninstall step removes what its install step wrote, as the twins do$/);
    const base = spawnSync('git', ['show', `52152cdb:${UPDATE_ALLOWLIST_BASE}`], { cwd: ROOT, encoding: 'utf8' });
    if (base.status === 0) {
      const baseRows = M.parseAllowlist(base.stdout, { twins: ['sh', 'ps1', 'node'] });
      // sync-on-node run 6c added the sync rows after the hook ride: every row of the hook ride is still there
      const ids = rows.map((r) => r.id);
      for (const r of baseRows) assert.ok(ids.includes(r.id), r.id);
    }
  });
});

// TEST-4017 (sync-on-node, Spec-AC-17, D-PARITY): the module is the third twin on sync scenarios, all three pairs are compared,
// the sh and ps1 twins run the frozen references from ctx.syref, and the allowlist rows are widened for the module side.
describe('TEST-4017 sync twins', () => {
  const syScen = (over = {}) => scen({ id: 'SY-T1', op: 'sync', setup: 'empty', steps: [{ op: 'sync', profile: 'core', flags: [], expect: '0' }], probes: ['.aai/system/AAI_PIN.md'], ...over });
  const pin = (body) => ({ '.aai/system/AAI_PIN.md': body });
  const same = '# AAI Pin\n\n- Profile: core\n';
  const run3 = (nodeFiles, extra = {}) => runFake([fakeTwin('sh', { files: pin(same) }), fakeTwin('ps1', { files: pin(same) }), fakeTwin('node', { files: nodeFiles })], [syScen()], [], {
    ctx: { root: scratch('sy'), src: null, syref: '/unused', bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX },
    ...extra,
  });
  test('a sync scenario compares all three pairs and passes when the three pins are equal', () => {
    has('runMatrix');
    const rep = run3(pin(same));
    assert.deepEqual(rep.pairs, ['sh:ps1', 'sh:node', 'ps1:node']);
    assert.equal(rep.verdict, 'PASS', JSON.stringify(rep.uncovered));
  });
  test('a fake node twin that writes one more byte into the pin fails naming sh:node', () => {
    has('runMatrix');
    const rep = run3(pin(`${same}x`));
    assert.equal(rep.verdict, 'FAIL');
    assert.ok(rep.uncovered.some((d) => d.pair === 'sh:node' && d.path === '.aai/system/AAI_PIN.md'), JSON.stringify(rep.uncovered));
  });
  test('runMatrix builds syref once for a sync scenario, hands it to every twin, holds the frozen twins and not the module, and builds none for another operation', () => {
    has('runMatrix');
    const seen = [];
    const spy = (name, files) => ({ name, argv(step, ctx) { seen.push([name, ctx.syref]); return fakeTwin(name, { files }).argv(step, ctx); } });
    const root = scratch('syref');
    const src = path.join(root, 'srcfake');
    put(src, '.aai/scripts/aai-sync.mjs', '// module\n');
    put(src, '.aai/scripts/lib/resolve-base.mjs', '// lib\n');
    put(src, '.aai/scripts/lib/gitignore-block.mjs', '// lib\n');
    put(src, '.aai/scripts/aai-sync.sh', '#!/bin/sh\n# launcher\n');
    M.runMatrix({
      scenarios: [syScen()], twins: [spy('sh', pin(same)), spy('ps1', pin(same)), spy('node', pin(same))], rows: [], matrix: 'smoke', filtered: false,
      ctx: { root, src, bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX },
    });
    assert.equal(seen.length, 3);
    const refs = new Set(seen.map((x) => x[1]));
    assert.equal(refs.size, 1);
    const [ref] = refs;
    assert.notEqual(ref, src);
    assert.ok(fs.readFileSync(path.join(ref, '.aai', 'scripts', 'aai-sync.sh'), 'utf8').length > 1000, 'the frozen bash twin is there');
    assert.ok(fs.existsSync(path.join(ref, '.aai', 'scripts', 'aai-sync.ps1')), 'the frozen PowerShell twin is there');
    assert.ok(fs.existsSync(path.join(ref, '.aai', 'scripts', 'lib', 'gitignore-block.sh')), 'the frozen bash library is there');
    for (const gone of ['aai-sync.mjs', 'lib/resolve-base.mjs', 'lib/gitignore-block.mjs']) assert.equal(fs.existsSync(path.join(ref, '.aai', 'scripts', ...gone.split('/'))), false, `${gone} is not in the reference tree`);
    const other = [];
    M.runMatrix({
      scenarios: [scen({ id: 'HK-T2', op: 'hooks', steps: [{ op: 'hooks', profile: null, flags: [], expect: '0' }] })], twins: [{ name: 'sh', argv(step, ctx) { other.push(ctx.syref); return fakeTwin('sh', { files: { 'p.txt': 'a\n' } }).argv(step, ctx); } }, fakeTwin('ps1', { files: { 'p.txt': 'a\n' } })], rows: [], matrix: 'smoke', filtered: false,
      ctx: { root: scratch('nosyref'), src: root, bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX },
    });
    assert.deepEqual(other, [undefined]);
  });
  test('the real registry: the node twin runs sync with peers for update only, and the sync argv of the three twins', () => {
    assert.deepEqual(M.TWINS.node.ops, ['bootstrap', 'update', 'hooks', 'sync']);
    assert.deepEqual(M.TWINS.node.peers, { update: ['sh', 'launcher'] });
    const ctx = { src: '/s', target: '/t', bash: '/bin/bash', ps: 'pwsh', syref: '/sy' };
    const sy = { op: 'sync', profile: 'core', flags: [] };
    const sh = M.TWINS.sh.argv(sy, ctx);
    assert.deepEqual([sh.file, ...sh.args], ['/bin/bash', '/sy/.aai/scripts/aai-sync.sh', '/t', '--profile', 'core']);
    const ps = M.TWINS.ps1.argv(sy, ctx);
    assert.deepEqual(ps.args.slice(ps.args.indexOf('-File')), ['-File', '/sy/.aai/scripts/aai-sync.ps1', '-TargetRoot', '/t', '-Profile', 'core']);
    const nd = M.TWINS.node.argv(sy, ctx);
    assert.equal(nd.file, process.execPath);
    assert.deepEqual(nd.args, [path.join('/s', '.aai', 'scripts', 'aai-sync.mjs'), '/t', '--profile', 'core']);
    assert.equal(nd.cwd, '/t');
    assert.deepEqual(M.TWINS.node.argv({ op: 'sync', profile: null, flags: [] }, ctx).args, [path.join('/s', '.aai', 'scripts', 'aai-sync.mjs'), '/t']);
    const src = fs.readFileSync(DRIVER, 'utf8');
    const line = "      if (step.op === 'sync') return { file: process.execPath, args: [path.join(ctx.src, '.aai', 'scripts', 'aai-sync.mjs'), ctx.target, ...(step.profile ? ['--profile', step.profile] : [])], cwd: ctx.target };";
    assert.equal(src.split(line).length - 1, 1);
  });
  test('buildSource copies the module and its two libs even when they are untracked', () => {
    const src = fs.readFileSync(DRIVER, 'utf8');
    assert.match(src, /SYNC_MODULE_FILES = \['\.aai\/scripts\/aai-sync\.mjs', '\.aai\/scripts\/lib\/resolve-base\.mjs', '\.aai\/scripts\/lib\/gitignore-block\.mjs'\]/);
    assert.match(src, /for \(const rel of SYNC_MODULE_FILES\) if \(!listed\.includes\(rel\)/);
  });
  test('the sync rows are widened for the module side and the one new row names the engine files', () => {
    has('parseAllowlist');
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] });
    const byId = new Map(rows.map((r) => [r.id, r]));
    for (const id of ['pin-synced-at-precision', 'gitignore-block-order', 'gitignore-block-headers', 'session-start-exec-bit', 'conflict-report-name-local-time',
      'conflict-report-generated-precision', 'conflict-report-next-step-backticks', 'win-ps1-pin-newline-bom', 'win-ps1-report-newline-bom', 'win-ps1-gitignore-newline']) {
      assert.ok(byId.get(id), id);
      assert.ok(byId.get(id).pairs.split(',').includes('ps1:node'), `${id} lacks ps1:node`);
      assert.match(byId.get(id).reason, /the module takes the bash side$/, id);
    }
    assert.ok(byId.get('pin-template-version-spacing').pairs.split(',').includes('sh:node'));
    const engine = byId.get('sync-engine-files');
    assert.ok(engine, 'sync-engine-files');
    assert.equal(engine.pairs, 'sh:node,ps1:node');
    assert.equal(engine.reason, 'the frozen twins vendor themselves and the bash library; the module side vendors its launchers, the module and its libs');
  });
});

// TEST-4030 (node-first-phase5-closeout, Spec-AC-07, D-TWIN): the launcher twin runs the SHIPPED aai-sync.sh and aai-update.sh of
// the scratch source through the driver's bash, is paired only with node, and passes against node on a real run.
describe('TEST-4030 launcher twin', () => {
  const ok = { 'p.txt': 'same\n' };
  const withPeers = (t) => ({ ...t, peers: M.TWINS[t.name] && M.TWINS[t.name].peers });
  const upScen = () => scen({ id: 'U-01', op: 'update', steps: [{ op: 'update', profile: null, flags: [], expect: '0' }] });
  const fourFakes = () => ['sh', 'ps1', 'node', 'launcher'].map((n) => withPeers(fakeTwin(n, { files: ok })));
  const runFour = (scenarios, setup = (_s, target) => { fs.mkdirSync(target, { recursive: true }); fs.writeFileSync(path.join(target, 'seed.txt'), 'seed\n'); }) => runFake(fourFakes(), scenarios, [], {
    ctx: { root: scratch('lt'), src: null, upref: '/unused', bash: 'bash', ps: 'pwsh', setup, host: HOST_POSIX },
  });
  test('the registry holds launcher fourth with ops sync and update and peers node only; node pairs with launcher for update', () => {
    assert.deepEqual(Object.keys(M.TWINS), ['sh', 'ps1', 'node', 'launcher']);
    assert.equal(M.TWINS.launcher.name, 'launcher');
    assert.deepEqual(M.TWINS.launcher.ops, ['sync', 'update']);
    assert.deepEqual(M.TWINS.launcher.peers, { sync: ['node'], update: ['node'] });
    assert.deepEqual(M.TWINS.node.peers, { update: ['sh', 'launcher'] });
    assert.equal(M.TWINS.sh.peers, undefined);
    assert.equal(M.TWINS.ps1.peers, undefined);
  });
  test('argv runs the shipped launchers of the scratch source through the driver bash with the target as cwd', () => {
    const ctx = { src: 'C:\\s', target: '/t', bash: '/bin/bash', ps: 'pwsh', syref: '/sy', upref: '/u' };
    const sy = M.TWINS.launcher.argv({ op: 'sync', profile: 'core', flags: [] }, ctx);
    assert.deepEqual([sy.file, ...sy.args], ['/bin/bash', 'C:/s/.aai/scripts/aai-sync.sh', '/t', '--profile', 'core']);
    assert.equal(sy.cwd, '/t');
    assert.deepEqual(M.TWINS.launcher.argv({ op: 'sync', profile: null, flags: [] }, ctx).args, ['C:/s/.aai/scripts/aai-sync.sh', '/t']);
    const up = M.TWINS.launcher.argv({ op: 'update', profile: null, flags: [] }, ctx);
    assert.deepEqual([up.file, ...up.args], ['/bin/bash', 'C:/s/.aai/scripts/aai-update.sh', '--repo', 'C:/s', '--ref', 'main']);
    assert.equal(up.cwd, '/t');
    assert.equal(up.env, undefined, 'the shipped aai-update.sh sets its own sync runner; the twin sets none');
  });
  test('pairs are emitted in registry order: sync gives node:launcher after ps1:node, update gives node:launcher after sh:node and no ps1:node', () => {
    has('runMatrix');
    const sync = runFour([scen()]);
    assert.deepEqual(sync.pairs, ['sh:ps1', 'sh:node', 'ps1:node', 'node:launcher']);
    assert.equal(sync.verdict, 'PASS', JSON.stringify(sync.uncovered));
    const upd = runFour([upScen()]);
    assert.deepEqual(upd.pairs, ['sh:ps1', 'sh:node', 'node:launcher']);
    assert.equal(upd.verdict, 'PASS', JSON.stringify(upd.uncovered));
  });
  test('a launcher twin that writes one more byte fails naming node:launcher and no other pair', () => {
    has('runMatrix');
    const twins = ['sh', 'ps1', 'node'].map((n) => withPeers(fakeTwin(n, { files: ok }))).concat([withPeers(fakeTwin('launcher', { files: { 'p.txt': 'samex\n' } }))]);
    const rep = runFake(twins, [scen()], [], { ctx: { root: scratch('ltx'), src: null, bash: 'bash', ps: 'pwsh', setup: (_s, target) => { fs.mkdirSync(target, { recursive: true }); fs.writeFileSync(path.join(target, 'seed.txt'), 'x'); }, host: HOST_POSIX } });
    assert.equal(rep.verdict, 'FAIL');
    assert.deepEqual([...new Set(rep.uncovered.map((d) => d.pair))], ['node:launcher']);
  });
  test('an empty target is a hard failure for the launcher twin (a launcher on an empty directory proves nothing)', () => {
    has('runMatrix');
    assert.throws(() => runFour([scen()], fakeSetup), /empty target/);
  });
  test('the committed allowlist parses with the four twins, and a row written launcher:node is refused as an order the runner never emits', () => {
    has('parseAllowlist');
    const rows = M.parseAllowlist(fs.readFileSync(ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node', 'launcher'] });
    assert.ok(rows.length > 0);
    const row = ['r1', 'launcher:node', '*', 'f.txt', 'missing', 'any', 'accepted', '-', 'x'].join('\t');
    assert.throws(() => M.parseAllowlist(row, { twins: ['sh', 'ps1', 'node', 'launcher'] }), /node:launcher/);
  });
  test('the driver source names the launcher twin once', () => {
    const src = fs.readFileSync(DRIVER, 'utf8');
    assert.equal(src.split("name: 'launcher'").length - 1, 1);
  });
  test('a real run of SY-01 and UP-01 with twins node and launcher into scratch targets exits 0 with verdict PASS and the pair node:launcher in both', () => {
    const d = scratch('lreal');
    const json = path.join(d, 'rep.json');
    const env = { ...process.env, AAI_PARITY_SCRATCH: d };
    delete env.AAI_ROLE; delete env.AAI_GIT_WRITE;
    const r = cli(['run', '--matrix', 'smoke', '--scenario', 'SY-01', '--scenario', 'UP-01', '--twins', 'node,launcher', '--json', json], { env });
    assert.equal(r.status, 0, `${r.stdout}\n${r.stderr}`);
    const rep = JSON.parse(fs.readFileSync(json, 'utf8'));
    assert.equal(rep.verdict, 'PASS');
    assert.deepEqual(rep.twins, ['node', 'launcher']);
    for (const id of ['SY-01', 'UP-01']) {
      const s = rep.scenarios.find((x) => x.id === id);
      assert.ok(s, id);
      assert.ok(s.pairs.includes('node:launcher'), `${id} pairs ${JSON.stringify(s.pairs)}`);
      assert.equal(s.broken.length, 0);
      assert.ok(s.steps.some((x) => x.twin === 'launcher' && x.code === 0), `${id} launcher step`);
    }
  });
});

// TEST-4031 (Spec-AC-08, D-HOSTCHECK no-odd-root): a root entry with a name outside printable ASCII that a node or launcher twin step
// birthed fails the run; an entry that existed before the step, an ASCII name and a twin outside the two are not reported.
describe('TEST-4031 no-odd-root host check', () => {
  const clean = { 'p.txt': 'same\n' };
  const seed = (_s, target) => { fs.mkdirSync(target, { recursive: true }); fs.writeFileSync(path.join(target, 'seed.txt'), 'seed\n'); };
  const runHC = (twins, { setup = seed, scenario = scen() } = {}) => M.runMatrix({
    scenarios: [scenario], twins, rows: [], matrix: 'smoke', filtered: true,
    ctx: { root: scratch('hc'), src: null, upref: '/unused', bash: 'bash', ps: 'pwsh', setup, host: HOST_POSIX, platform: 'linux' },
  });
  const entry = (rep, id, scenario, twin) => rep.host_checks.filter((e) => e.id === id && e.scenario === scenario && e.twin === twin);
  test('a fake launcher twin that births a directory with a non-ASCII name fails the check naming its code points; the verdict is FAIL', () => {
    has('runMatrix');
    const rep = runHC([fakeTwin('sh', { files: clean }), fakeTwin('node', { files: clean }), fakeTwin('launcher', { files: clean, after: "fs.mkdirSync('caf\\u00e9-\\u4e2d');" })]);
    const [e] = entry(rep, 'no-odd-root', 'T-01', 'launcher');
    assert.ok(e, JSON.stringify(rep.host_checks));
    assert.equal(e.status, 'fail');
    assert.match(e.detail, /\\u\{e9\}/);
    assert.match(e.detail, /\\u\{4e2d\}/);
    assert.equal(rep.verdict, 'FAIL');
    assert.ok(rep.notes.includes('AAI-HOST-CHECK no-odd-root T-01 launcher fail checked=3'), JSON.stringify(rep.notes));
    assert.equal(entry(rep, 'no-odd-root', 'T-01', 'node')[0].status, 'pass');
  });
  test('the exit code of a report with a failed host check is not 0', () => {
    has('exitCodeFor');
    assert.equal(M.exitCodeFor({ verdict: 'FAIL' }), 1);
    assert.equal(M.exitCodeFor({ verdict: 'PASS', host_checks: [{ status: 'fail' }] }), 1);
    assert.equal(M.exitCodeFor({ verdict: 'PASS', host_checks: [{ status: 'pass' }, { status: 'bites' }, { status: 'not-applicable' }] }), 0);
  });
  test('a clean fake passes with checked equal to the root entries read, on the node twin and the launcher twin', () => {
    has('runMatrix');
    const rep = runHC([fakeTwin('sh', { files: clean }), fakeTwin('node', { files: clean }), fakeTwin('launcher', { files: clean })]);
    assert.equal(rep.verdict, 'PASS', JSON.stringify(rep.uncovered));
    for (const twin of ['node', 'launcher']) {
      const [e] = entry(rep, 'no-odd-root', 'T-01', twin);
      assert.equal(e.status, 'pass');
      assert.equal(e.checked, 2, 'seed.txt and p.txt');
    }
    assert.ok(rep.notes.includes('AAI-HOST-CHECK no-odd-root T-01 node pass checked=2'));
  });
  test('an odd entry present before the step is not reported as born', () => {
    has('runMatrix');
    const pre = (_s, target) => { seed(_s, target); fs.mkdirSync(path.join(target, 'pre\u00e9')); };
    const rep = runHC([fakeTwin('sh', { files: clean }), fakeTwin('node', { files: clean }), fakeTwin('launcher', { files: clean })], { setup: pre });
    for (const twin of ['node', 'launcher']) assert.equal(entry(rep, 'no-odd-root', 'T-01', twin)[0].status, 'pass');
    assert.equal(rep.verdict, 'PASS', JSON.stringify(rep.uncovered));
  });
  test('negative controls: a printable ASCII name with spaces and a twin outside node and launcher are not reported', () => {
    has('runMatrix');
    const rep = runHC([fakeTwin('sh', { files: clean, after: "fs.mkdirSync('caf\\u00e9');" }), fakeTwin('node', { files: clean, after: "fs.mkdirSync('a b~c');" }), fakeTwin('launcher', { files: clean })]);
    assert.equal(entry(rep, 'no-odd-root', 'T-01', 'sh').length, 0, 'the frozen sh twin is not a host-check twin');
    assert.equal(entry(rep, 'no-odd-root', 'T-01', 'node')[0].status, 'pass');
  });
  test('the check follows every sync step of a scenario: an entry born by the second step fails', () => {
    has('runMatrix');
    const two = scen({ id: 'T-02', steps: [{ op: 'sync', profile: 'core', flags: [], expect: '0' }, { op: 'sync', profile: null, flags: [], expect: '0' }] });
    const late = { name: 'launcher', argv(step, ctx) { const t = fakeTwin('launcher', { files: clean, after: step.index === 1 ? "fs.mkdirSync('late\\u00e9');" : '' }); return t.argv(step, ctx); } };
    const rep = runHC([fakeTwin('sh', { files: clean }), fakeTwin('node', { files: clean }), late], { scenario: two });
    const [e] = entry(rep, 'no-odd-root', 'T-02', 'launcher');
    assert.equal(e.status, 'fail');
    assert.match(e.detail, /step 2/);
  });
  test('the driver names the odd-name pattern ODD_NAME once as a constant and tests it by ODD_NAME.test(name)', () => {
    const src = fs.readFileSync(DRIVER, 'utf8');
    assert.equal(src.split('const ODD_NAME = /[^\\x20-\\x7e]/;').length - 1, 1);
    assert.ok(src.includes('ODD_NAME.test(name)'));
  });
});

// TEST-4031 (D-ODD step 2): the diagnostic is off by default and, when asked for, runs one candidate at a time in a fresh copy of the
// target with a root snapshot before and after, printing AAI-ODD-DIAG <candidate> born=<n>.
describe('TEST-4031 odd-root diagnostic', () => {
  test('the default candidate list names the doctor helper, the doctor, the three ref-guard arms, the selftest and the agent CLI probes', () => {
    has('oddDiagCandidates');
    const names = M.oddDiagCandidates({ ps: 'pwsh' }).map((c) => c.name);
    assert.deepEqual(names, ['field-report-helper', 'doctor-json', 'ref-guard-control', 'ref-guard-refuse', 'ref-guard-permit', 'win-selftest', 'agent-cli-claude', 'agent-cli-codex', 'agent-cli-gemini']);
  });
  test('each candidate runs in its own fresh copy of the target and reports the root entries it births', () => {
    has('runOddDiag');
    const root = scratch('diag');
    const target = path.join(root, 'target');
    put(target, 'keep.txt', 'k\n');
    put(target, 'pre\u00e9/x', 'x\n');
    const born = { name: 'births', run: (copy) => ({ file: process.execPath, args: ['-e', `require('fs').mkdirSync(${JSON.stringify(path.join(copy, 'wide\u4e2d'))})`], cwd: copy }) };
    const quiet = { name: 'quiet', run: (copy) => ({ file: process.execPath, args: ['-e', '0'], cwd: copy }) };
    const lines = M.runOddDiag({ root, target, bash: 'bash', env: { ...process.env }, candidates: [born, quiet], scenario: 'UP-01', twin: 'launcher', useBash: false });
    assert.match(lines[0], /^AAI-ODD-DIAG births born=1 scenario=UP-01 twin=launcher /);
    assert.match(lines[0], /\\u\{4e2d\}/);
    assert.match(lines[1], /^AAI-ODD-DIAG quiet born=0 scenario=UP-01 twin=launcher/);
    assert.equal(fs.existsSync(path.join(target, 'wide\u4e2d')), false, 'the post-step target itself is never written');
    assert.deepEqual(fs.readdirSync(target).sort(), ['keep.txt', 'pre\u00e9']);
  });
  test('the diagnostic is off unless AAI_PARITY_ODD_DIAG is 1: a run over fake twins prints no AAI-ODD-DIAG line', () => {
    has('runMatrix');
    const up = scen({ id: 'U-02', op: 'update', steps: [{ op: 'update', profile: null, flags: [], expect: '0' }] });
    const prev = process.env.AAI_PARITY_ODD_DIAG;
    delete process.env.AAI_PARITY_ODD_DIAG;
    try {
      const rep = runFake([fakeTwin('sh', { files: { 'p.txt': 'a\n' } }), fakeTwin('ps1', { files: { 'p.txt': 'a\n' } })], [up], [], { ctx: { root: scratch('diagoff'), src: null, upref: '/unused', bash: 'bash', ps: 'pwsh', setup: fakeSetup, host: HOST_POSIX } });
      assert.ok(!rep.notes.some((n) => n.startsWith('AAI-ODD-DIAG')));
    } finally { if (prev !== undefined) process.env.AAI_PARITY_ODD_DIAG = prev; }
  });
});

// TEST-4032 (Spec-AC-09, D-HOSTCHECK source-path-windows and its control): on win32 every Source path line of the pin and every Source
// line of a sync-conflicts report that the node and launcher twins wrote must be a drive letter, a colon and a backslash path.
describe('TEST-4032 source-path-windows host check', () => {
  const winPin = (n) => Array.from({ length: n }, (_, i) => `- Source path: C:\\Users\\r\\aai-parity-x\\fx\\src${i ? i : ''}\n`).join('');
  const shPin = '# AAI Pin\n\n- Source path: /c/Users/r/aai-parity-x/syref\n';
  const report = '# Sync conflicts\n\n- Source: C:\\Users\\r\\aai-parity-x\\fx\\src\n';
  const files = (pin, rep) => ({ '.aai/system/AAI_PIN.md': pin, ...(rep ? { 'docs/ai/reports/sync-conflicts-20260101-000000.md': rep } : {}) });
  const seed = (_s, target) => { fs.mkdirSync(target, { recursive: true }); fs.writeFileSync(path.join(target, 'seed.txt'), 'seed\n'); };
  const sy = (over = {}) => scen({ id: 'SY-01', steps: [{ op: 'sync', profile: 'core', flags: [], expect: '0' }], probes: ['.aai/system/AAI_PIN.md'], ...over });
  const runWin = (twins, platform = 'win32', scenario = sy()) => M.runMatrix({
    scenarios: [scenario], twins, rows: [], matrix: 'smoke', filtered: true,
    ctx: { root: scratch('sp'), src: null, bash: 'bash', ps: 'pwsh', setup: seed, host: HOST_POSIX, platform },
  });
  const pick = (rep, id, twin, scenario = 'SY-01') => rep.host_checks.filter((e) => e.id === id && e.scenario === scenario && e.twin === twin);
  const good = () => [fakeTwin('sh', { files: files(shPin, '# r\n\n- Source: /c/Users/r/aai-parity-x/syref\n') }), fakeTwin('node', { files: files(winPin(1), report) }), fakeTwin('launcher', { files: files(winPin(1), report) })];
  test('WIN_ABS_RE accepts a drive letter colon backslash path and rejects the Git Bash spelling, a forward slash drive path, a UNC path and a bare drive', () => {
    assert.ok(M.WIN_ABS_RE.test('C:\\Users\\r\\fx\\src'));
    assert.ok(M.WIN_ABS_RE.test('d:\\x'));
    for (const bad of ['/c/Users/r/fx/src', 'C:/Users/r/fx/src', '\\\\server\\share', 'C:', '', 'Users\\r', '1:\\x']) assert.equal(M.WIN_ABS_RE.test(bad), false, JSON.stringify(bad));
  });
  test('on win32 the node and launcher twins pass with the pin and the report line checked, and the control on the frozen sh pin reads bites', () => {
    has('runMatrix');
    const rep = runWin(good());
    for (const twin of ['node', 'launcher']) {
      const es = pick(rep, 'source-path-windows', twin);
      assert.equal(es.length, 1, twin);
      assert.equal(es[0].status, 'pass', es[0].detail);
      assert.equal(es[0].checked, 2);
    }
    const c = pick(rep, 'source-path-windows-control', 'sh');
    assert.equal(c.length, 1);
    assert.equal(c[0].status, 'bites', c[0].detail);
    assert.equal(c[0].checked, 1);
    for (const line of ['AAI-HOST-CHECK source-path-windows SY-01 node pass checked=2', 'AAI-HOST-CHECK source-path-windows SY-01 launcher pass checked=2', 'AAI-HOST-CHECK source-path-windows-control SY-01 sh bites checked=1']) assert.ok(rep.notes.includes(line), line);
    assert.ok(!rep.host_checks.some((e) => e.status === 'fail'), JSON.stringify(rep.host_checks));
  });
  test('SY-01 with fewer than two checked lines is a fail (vacuous), and the verdict is FAIL', () => {
    has('runMatrix');
    const rep = runWin([good()[0], fakeTwin('node', { files: files(winPin(1)) }), good()[2]]);
    const [e] = pick(rep, 'source-path-windows', 'node');
    assert.equal(e.status, 'fail');
    assert.equal(e.checked, 1);
    assert.match(e.detail, /at least 2/);
    assert.equal(rep.verdict, 'FAIL');
  });
  test('a node twin that records the Git Bash spelling fails the predicate on the line it names', () => {
    has('runMatrix');
    const rep = runWin([good()[0], fakeTwin('node', { files: files(`${winPin(1)}- Source path: /c/Users/r/fx/src\n`, report) }), good()[2]]);
    const [e] = pick(rep, 'source-path-windows', 'node');
    assert.equal(e.status, 'fail');
    assert.match(e.detail, /\/c\/Users\/r\/fx\/src/);
    assert.equal(rep.verdict, 'FAIL');
  });
  test('the control fails when the frozen sh pin already holds the Windows spelling (the check would not catch the old bug) and when it holds no line', () => {
    has('runMatrix');
    const winSh = runWin([fakeTwin('sh', { files: files(winPin(2), report) }), good()[1], good()[2]]);
    const c1 = pick(winSh, 'source-path-windows-control', 'sh')[0];
    assert.equal(c1.status, 'fail');
    assert.equal(winSh.verdict, 'FAIL');
    const none = runWin([fakeTwin('sh', { files: files('# AAI Pin\n') }), good()[1], good()[2]]);
    const c2 = pick(none, 'source-path-windows-control', 'sh')[0];
    assert.equal(c2.status, 'fail');
    assert.equal(c2.checked, 0);
  });
  test('on a POSIX host both entries read not-applicable with detail POSIX host and checked 0, whatever the paths are', () => {
    has('runMatrix');
    const rep = runWin([good()[0], fakeTwin('node', { files: files(shPin) }), good()[2]], 'linux');
    for (const [id, twin] of [['source-path-windows', 'node'], ['source-path-windows', 'launcher'], ['source-path-windows-control', 'sh']]) {
      const [e] = pick(rep, id, twin);
      assert.equal(e.status, 'not-applicable', `${id} ${twin}`);
      assert.equal(e.detail, 'POSIX host');
      assert.equal(e.checked, 0);
    }
    assert.ok(rep.notes.includes('AAI-HOST-CHECK source-path-windows SY-01 node not-applicable checked=0'));
    assert.ok(!rep.host_checks.some((e) => e.status === 'fail'), JSON.stringify(rep.host_checks));
  });
  test('the driver names WIN_ABS_RE as one constant line and reads process.platform itself', () => {
    const src = fs.readFileSync(DRIVER, 'utf8');
    assert.equal(src.split('const WIN_ABS_RE = /^[A-Za-z]:\\\\/;').length - 1, 1);
    assert.ok(src.includes('ctx.platform || process.platform'));
  });
  test('install-parity.Tests.ps1 asserts the win32 host checks and the POSIX not-applicable entries and writes every AAI-HOST-CHECK line to the log', () => {
    const f = fs.readFileSync(path.join(HERE, '..', 'install-parity.Tests.ps1'), 'utf8');
    for (const c of ['Get-ParityHostCheckProblems', "'source-path-windows'", "'source-path-windows-control'", "'no-odd-root'", "'bites'", "'not-applicable'", 'AAI-HOST-CHECK', 'host_checks']) assert.ok(f.includes(c), c);
    assert.ok(/Get-ParityHostCheckProblems -Report \$rep -IsWin \$script:IsWin/.test(f), 'the It block calls the function with the host flag');
  });
  const pwsh = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', 'exit 0'], { encoding: 'utf8' });
  const havePwsh = pwsh.status === 0;
  const problems = (rep, win) => {
    const f = fs.readFileSync(path.join(HERE, '..', 'install-parity.Tests.ps1'), 'utf8');
    const m = /# BEGIN Get-ParityHostCheckProblems\n([\s\S]*?)# END Get-ParityHostCheckProblems/.exec(f);
    assert.ok(m, 'the BEGIN and END markers of Get-ParityHostCheckProblems');
    const r = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `${m[1]}\n$rep = $env:PARITY_RPT | ConvertFrom-Json\n$p = @(Get-ParityHostCheckProblems -Report $rep -IsWin ($env:PARITY_WIN -eq '1'))\n$p | ForEach-Object { Write-Output ('PROBLEM: ' + $_) }\nWrite-Output ('COUNT=' + $p.Count)`],
      { encoding: 'utf8', env: { ...process.env, PARITY_RPT: JSON.stringify(rep), PARITY_WIN: win ? '1' : '0' } });
    assert.equal(r.status, 0, r.stderr + r.stdout);
    return r.stdout.split(/\r?\n/).filter((l) => l.startsWith('PROBLEM: ')).map((l) => l.slice(9));
  };
  const hc = (id, scenario, twin, status, checked) => ({ id, scenario, twin, status, checked, detail: '' });
  const winOk = () => [hc('source-path-windows', 'SY-01', 'launcher', 'pass', 2), hc('source-path-windows', 'SY-01', 'node', 'pass', 3), hc('source-path-windows-control', 'SY-01', 'sh', 'bites', 1), hc('no-odd-root', 'UP-01', 'launcher', 'pass', 12)];
  const rpt = (host_checks, ids = ['SY-01', 'UP-01']) => ({ verdict: 'PASS', scenarios: ids.map((id) => ({ id })), host_checks });
  test('the Pester assertion function (run under pwsh): a complete win32 report has no problem; a missing, failing, vacuous, duplicated or absent check on win32 is a problem', (t) => {
    if (!havePwsh) { assert.ok(!process.env.CI, 'pwsh is required on CI'); t.skip('pwsh is not installed here'); return; }
    assert.deepEqual(problems(rpt(winOk()), true), []);
    const without = (pred) => winOk().filter((e) => !pred(e));
    assert.match(problems(rpt(without((e) => e.id === 'source-path-windows-control')), true).join('\n'), /source-path-windows-control/);
    assert.match(problems(rpt(without((e) => e.id === 'source-path-windows' && e.twin === 'node')), true).join('\n'), /source-path-windows.*node/);
    assert.match(problems(rpt(without((e) => e.id === 'no-odd-root')), true).join('\n'), /no-odd-root/);
    assert.match(problems(rpt(winOk().map((e) => (e.twin === 'launcher' && e.id === 'source-path-windows' ? { ...e, status: 'fail' } : e))), true).join('\n'), /launcher.*fail|fail.*launcher/);
    assert.match(problems(rpt(winOk().map((e) => (e.twin === 'node' && e.id === 'source-path-windows' ? { ...e, checked: 1 } : e))), true).join('\n'), /checked 1/);
    assert.match(problems(rpt(winOk().map((e) => (e.id === 'no-odd-root' ? { ...e, checked: 0 } : e))), true).join('\n'), /checked 0/);
    assert.match(problems(rpt(winOk().map((e) => (e.id === 'source-path-windows-control' ? { ...e, status: 'pass' } : e))), true).join('\n'), /bites/);
    assert.match(problems(rpt(winOk().concat([hc('source-path-windows', 'SY-01', 'node', 'pass', 5)])), true).join('\n'), /exactly one/);
    assert.ok(problems({ verdict: 'PASS', scenarios: [{ id: 'SY-01' }] }, true).length > 0, 'a report with no host_checks on win32 is a problem');
    assert.ok(problems(rpt(winOk(), ['HK-01']), true).length > 0, 'a win32 run that did not run SY-01 and UP-01 is a problem');
    assert.match(problems(rpt(winOk().concat([hc('no-odd-root', 'UP-01', 'node', 'fail', 4)])), true).join('\n'), /fail/);
  });
  test('the Pester assertion function (run under pwsh): on POSIX the two Windows entries must read not-applicable when SY-01 ran, and nothing is asserted for a scenario that did not run', (t) => {
    if (!havePwsh) { assert.ok(!process.env.CI, 'pwsh is required on CI'); t.skip('pwsh is not installed here'); return; }
    const posix = () => [hc('source-path-windows', 'SY-01', 'launcher', 'not-applicable', 0), hc('source-path-windows', 'SY-01', 'node', 'not-applicable', 0), hc('source-path-windows-control', 'SY-01', 'sh', 'not-applicable', 0), hc('no-odd-root', 'UP-01', 'launcher', 'pass', 9)];
    assert.deepEqual(problems(rpt(posix()), false), []);
    assert.deepEqual(problems(rpt([], ['HK-01']), false), []);
    assert.match(problems(rpt(posix().map((e) => (e.id === 'source-path-windows-control' ? { ...e, status: 'pass' } : e))), false).join('\n'), /not-applicable/);
    assert.match(problems(rpt(posix().filter((e) => e.id !== 'no-odd-root')), false).join('\n'), /no-odd-root/);
  });
});
