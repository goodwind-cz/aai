// release-cut.test.mjs - node:test cases for .aai/scripts/release-cut.mjs
// (docs/specs/SPEC-DRAFT-spec-release-on-node.md, TEST-3462 to TEST-3466 and TEST-3478; one case per drift DR-01..DR-22).
// Every case works in a fresh temp directory: recording fakes for the unit cases, scratch git repositories and
// the real release-finish.mjs --audit for the integration cases. No case runs a real gh, pushes, tags or publishes,
// and none reads or writes the repository's own CHANGELOG.md.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
// The module may not exist yet (RED on the baseline): every case must fail on its own assertion.
const M = await import('../../../.aai/scripts/release-cut.mjs').catch(() => ({}));

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../..');
const MODULE = path.join(ROOT, '.aai/scripts/release-cut.mjs');
const SH = path.join(ROOT, '.aai/scripts/aai-release.sh');
const PS1 = path.join(ROOT, '.aai/scripts/aai-release.ps1');
const TMP = [];
after(() => { for (const d of TMP) fs.rmSync(d, { recursive: true, force: true }); });

const MALFORMED = "REFUSED: malformed [unreleased] heading in CHANGELOG.md (a '## [unreleased]' line has unexpected trailing text or a stray heading-only body) — never silently dropping entries.";
const ENCODING = 'REFUSED: CHANGELOG.md is not valid UTF-8 — never guessing its encoding.';
const EMPTY = 'REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) — nothing to release.';
const MISSING_NODE = 'REFUSED: missing-node — Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.';
const HEADER = '## aai-release (plan) — no files changed';

const scratch = (label) => {
  const d = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), `aai-rcut-${label}-`)));
  TMP.push(d);
  return d;
};
const run = (argv, deps) => {
  assert.equal(typeof M.run, 'function', 'release-cut.mjs must export run');
  return M.run(argv, deps);
};
const git = (cwd, ...args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
};
const initRepo = (dir) => {
  fs.mkdirSync(dir, { recursive: true });
  git(dir, 'init', '-q', '-b', 'main');
  git(dir, 'config', 'user.email', 'fixture@example.invalid');
  git(dir, 'config', 'user.name', 'fixture');
  git(dir, 'config', 'commit.gpgsign', 'false');
  git(dir, 'config', 'core.autocrlf', 'false');
};
const commitAll = (dir, msg) => { git(dir, 'add', '-A'); git(dir, 'commit', '-q', '-m', msg); };

// Fixture A: tag v0, then three merged PRs of shipped files; only #12 is named in the notes.
const CHANGELOG_A = [
  '# Changelog', '', '## [unreleased]', '',
  '## [unreleased] — feat: noted thing (#12)', '', 'Body one.', '',
  '## [unreleased] — second', '', 'Body two.', '',
  '## [v0] — old', '', 'old body', '',
].join('\n');
function fixtureA({ allNoted = false } = {}) {
  const dir = path.join(scratch('fxa'), 'repo dir');
  initRepo(dir);
  fs.writeFileSync(path.join(dir, 'CHANGELOG.md'), CHANGELOG_A);
  commitAll(dir, 'chore: base');
  git(dir, 'tag', 'v0');
  const prs = allNoted ? [12] : [12, 13, 14];
  for (const n of prs) {
    fs.mkdirSync(path.join(dir, '.aai'), { recursive: true });
    fs.writeFileSync(path.join(dir, `.aai/f${n}.txt`), `${n}\n`);
    commitAll(dir, n === 12 ? `feat: noted thing (#${n})` : `fix: ${n === 13 ? 'other' : 'another'} (#${n})`);
  }
  return dir;
}
// snapshot: working tree bytes, index, every ref and the file list (outside .git), as one comparable string.
function snapshot(dir) {
  const files = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.name === '.git') continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p); else files.push(`${path.relative(dir, p)}:${fs.readFileSync(p).toString('base64')}`);
    }
  };
  walk(dir);
  return [files.sort().join('\n'), git(dir, 'status', '--porcelain'), git(dir, 'ls-files', '-s'), git(dir, 'show-ref')].join('\n--\n');
}
const cli = (args, { cwd, env = {} } = {}) => spawnSync(process.execPath, [MODULE, ...args], { cwd, encoding: 'utf8', env: { ...process.env, ...env } });

// mk: run() deps with recording fakes. files maps absolute paths to Buffer/string content.
const ROOT_DIR = path.join(path.sep, 'fake', 'root');
const FAKE_TMP = path.join(path.sep, 'fake', 'tmp');
function mk({ text = null, bytes = null, git: gitFn, audit: auditFn } = {}) {
  const files = new Map();
  if (bytes !== null) files.set(path.join(ROOT_DIR, 'CHANGELOG.md'), Buffer.from(bytes));
  else if (text !== null) files.set(path.join(ROOT_DIR, 'CHANGELOG.md'), Buffer.from(text, 'utf8'));
  const log = { out: [], err: [], git: [], audits: [], writes: [], rms: [], seen: [] };
  const deps = {
    readFile: (p) => { if (!files.has(p)) throw Object.assign(new Error(`ENOENT ${p}`), { code: 'ENOENT' }); return files.get(p); },
    writeFile: (p, d) => { log.writes.push([p, String(d)]); files.set(p, Buffer.from(String(d))); },
    rename: (a, b) => { files.set(b, files.get(a)); files.delete(a); },
    rm: (p) => { log.rms.push(p); files.delete(p); },
    tmpdir: () => FAKE_TMP,
    git: (args, cwd) => { log.git.push([args, cwd]); return gitFn ? gitFn(args, cwd) : { status: 1, stdout: '', stderr: '' }; },
    audit: (args) => {
      log.audits.push(args);
      log.seen.push(files.has(args[4]) ? files.get(args[4]).toString('utf8') : null);
      return auditFn ? auditFn(args) : { status: 0, stdout: '', stderr: '' };
    },
    out: (l) => log.out.push(l),
    err: (l) => log.err.push(l),
  };
  return { deps, log, files };
}
const PLAN_ARGS = ['plan', '--root', ROOT_DIR, '--version', 'v9', '--target-branch', 'main', '--launcher', 'sh'];
const CHECK_ARGS = (launcher = 'sh') => ['check', '--root', ROOT_DIR, '--version', 'v9', '--launcher', launcher, '--launcher-path', '/p/aai-release'];
const ENTRY = '# C\n\n## [unreleased] — a\n\nA\n';

// expectedPlan: the D-OUT plan built from literals (not from the module).
function expectedPlan({ launcher = 'sh', noRemote = false, headings, preview, named = [], blocks = [], branch = 'main', version = 'v9' }) {
  const C = launcher === 'ps1' ? '-Confirm' : '--confirm';
  const NR = launcher === 'ps1' ? '-NoRemote' : '--no-remote';
  const L = [HEADER, `- Resolved version: ${version}`, `- Tag to create:    ${version} (annotated)`, `- Commit message:   chore(release): ${version}`, '',
    '## CHANGELOG rollup (would write)', ...headings.map(([n, t]) => `  ${n}:## [${version}] — ${t}`), '  ## [unreleased]   <- fresh scaffold inserted above the rolled section', '',
    `## Release notes preview (title=${version})`, ...preview.map((l) => `  ${l}`), '', '## Preconditions', ...blocks];
  if (named.length) {
    L.push(`- NAMED (not blocking): ${named.length} PR(s) merged since the previous tag have no matching section in these notes:`, ...named.map((n) => `    - ${n}`),
      "    Add a '## [unreleased] — <title>' section for each, or confirm they are covered under another title.", '- confirm will refuse until the NAMED missing release notes are resolved');
  } else if (!blocks.length) L.push(`- none — ready to cut with ${C}`);
  L.push('', '## Remote');
  L.push(noRemote ? `- ${NR} / AAI_RELEASE_NO_REMOTE=1: push + gh pr create would be SKIPPED`
    : `- push (branch chore/release-${version}) and 'gh pr create' (base ${branch}) WOULD run against this repo's remote; CI will tag and publish upon merge`);
  return L;
}
const PREVIEW_A = ['## [v9] — feat: noted thing (#12)', '', 'Body one.', '', '## [v9] — second', '', 'Body two.'];
const HEADINGS_A = [[5, 'feat: noted thing (#12)'], [9, 'second']];

// ---- TEST-3462 ----------------------------------------------------------------------------------
test('TEST-3462 importing the module has no side effect and exposes the D-MOD functions', () => {
  const cwd = scratch('imp');
  const r = spawnSync(process.execPath, ['--input-type=module', '-e', `
    const m = await import(${JSON.stringify(MODULE)});
    process.stdout.write(Object.keys(m).sort().join(','));
  `], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const names = r.stdout.split(',');
  for (const n of ['parseArgs', 'decode', 'rollOrRefuse', 'rolledHeadings', 'onlineAllowed', 'planLines', 'resumeLine', 'run']) {
    assert.ok(names.includes(n), `missing export ${n}`);
  }
  assert.deepEqual(fs.readdirSync(cwd), [], 'import wrote into the cwd');
  assert.equal(r.stderr, '');
});

test('TEST-3462 plan with recording fakes runs the audit once with the module-adjacent script, the root and a temp notes file, then removes it', () => {
  const { deps, log, files } = mk({ text: ENTRY });
  const rc = run(PLAN_ARGS, deps);
  assert.equal(rc, 0, log.err.join('\n'));
  assert.equal(log.audits.length, 1, 'audit must run exactly once');
  const a = log.audits[0];
  assert.equal(path.basename(a[0]), 'release-finish.mjs');
  assert.equal(path.dirname(a[0]), path.dirname(MODULE), 'the audit script lives next to the module');
  assert.deepEqual(a.slice(1, 4), ['--root', ROOT_DIR, '--audit']);
  assert.equal(path.dirname(a[4]), FAKE_TMP, 'the notes file lives in the OS temp directory, outside the root');
  assert.equal(a.length, 5, 'no --online without an origin');
  assert.equal(log.seen[0], '## [v9] — a\n\nA', 'the audit reads the rolled notes');
  assert.ok(log.rms.includes(a[4]), 'the temp notes file is removed');
  assert.equal(files.has(a[4]), false);
  assert.deepEqual(log.writes.map((w) => w[0]), [a[4]], 'the only write is the temp notes file');
});

test('TEST-3462 --online is added only with an origin, gh not blocked and the remote not skipped', () => {
  assert.equal(typeof M.onlineAllowed, 'function', 'must export onlineAllowed');
  assert.equal(M.onlineAllowed({ ghBlock: '', noRemote: false, origin: 'git@x:y/z.git' }), true);
  assert.equal(M.onlineAllowed({ ghBlock: 'gh CLI not found on PATH', noRemote: false, origin: 'git@x:y/z.git' }), false);
  assert.equal(M.onlineAllowed({ ghBlock: '', noRemote: true, origin: 'git@x:y/z.git' }), false);
  assert.equal(M.onlineAllowed({ ghBlock: '', noRemote: false, origin: '' }), false);
  const origin = (args) => (args.join(' ') === 'config --get remote.origin.url' ? { status: 0, stdout: 'git@x:y/z.git\n', stderr: '' } : { status: 1, stdout: '', stderr: '' });
  const cases = [[[], true], [['--no-remote'], false], [['--gh-block', 'gh CLI not found on PATH'], false]];
  for (const [extra, online] of cases) {
    const { deps, log } = mk({ text: ENTRY, git: origin });
    assert.equal(run([...PLAN_ARGS, ...extra], deps), 0, log.err.join('\n'));
    assert.equal(log.audits[0].includes('--online'), online, `extra ${extra.join(' ')}`);
  }
});

// ---- TEST-3463 ----------------------------------------------------------------------------------
test('TEST-3463 the CLI plan in a committed repo prints exactly the D-OUT lines for launcher sh and writes nothing', () => {
  const dir = fixtureA();
  const before = snapshot(dir);
  const r = cli(['plan', '--root', dir, '--version', 'v9', '--target-branch', 'main', '--launcher', 'sh'], { cwd: dir });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stderr, '');
  assert.deepEqual(r.stdout.split('\n'), [...expectedPlan({ launcher: 'sh', headings: HEADINGS_A, preview: PREVIEW_A, named: ['#14 fix: another', '#13 fix: other'] }), '']);
  assert.equal(snapshot(dir), before, 'the plan must not change the repository');
});

test('TEST-3463 the CLI plan for launcher ps1 differs only in the flag spellings, with and without the remote skip', () => {
  const dir = fixtureA({ allNoted: true });
  const before = snapshot(dir);
  const base = ['plan', '--root', dir, '--version', 'v9', '--target-branch', 'main', '--launcher', 'ps1'];
  let r = cli(base, { cwd: dir });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stderr, '');
  assert.deepEqual(r.stdout.split('\n'), [...expectedPlan({ launcher: 'ps1', headings: HEADINGS_A, preview: PREVIEW_A }), '']);
  r = cli([...base, '--no-remote'], { cwd: dir });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.stdout.split('\n'), [...expectedPlan({ launcher: 'ps1', noRemote: true, headings: HEADINGS_A, preview: PREVIEW_A }), '']);
  assert.equal(snapshot(dir), before);
});

// ---- TEST-3464: DR-01 to DR-09 ------------------------------------------------------------------
const planOf = (text, over = {}) => { const m = mk({ text, ...over }); const rc = run(PLAN_ARGS, m.deps); return { rc, ...m }; };
const refused = (text, line, code, argv = PLAN_ARGS) => {
  const m = mk({ text });
  const rc = run(argv, m.deps);
  assert.equal(rc, code);
  assert.deepEqual(m.log.err, [line]);
  assert.deepEqual(m.log.out, []);
  assert.equal(m.log.audits.length, 0, 'a rollup refusal precedes the audit');
};
// rollFile: the roll command over a real file; returns { rc, err, bytes }.
function rollFile(bytes, version = 'v9') {
  const dir = scratch('roll');
  const file = path.join(dir, 'CHANGELOG.md');
  fs.writeFileSync(file, bytes);
  const r = cli(['roll', '--file', file, '--version', version], { cwd: dir });
  return { r, file, dir, bytes: fs.readFileSync(file), listing: fs.readdirSync(dir) };
}

test('TEST-3464 DR-01 an entry heading with an empty title exits 12 with the malformed line', () => {
  refused('# C\n\n## [unreleased] — \n\nbody\n', MALFORMED, 12);
  refused('# C\n\n## [unreleased] — \n\nbody\n', MALFORMED, 12, CHECK_ARGS());
  const t = rollFile('# C\n\n## [unreleased] — \n\nbody\n');
  assert.equal(t.r.status, 12);
  assert.equal(t.r.stderr, `${MALFORMED}\n`);
  assert.equal(t.bytes.toString(), '# C\n\n## [unreleased] — \n\nbody\n');
});

test('TEST-3464 DR-02 an entry whose body is blank exits 12 with the malformed line', () => {
  const text = '# C\n\n## [unreleased] — t\n\n\n## [v0] — old\n\no\n';
  refused(text, MALFORMED, 12);
  const t = rollFile(text);
  assert.equal(t.r.status, 12);
  assert.equal(t.r.stderr, `${MALFORMED}\n`);
  assert.equal(t.bytes.toString(), text);
});

test('TEST-3464 DR-03 entries interleaved with an older section move, in order, under the fresh scaffold', () => {
  const src = '# C\n\n## [unreleased] — a\n\nA\n\n## [v0] — old\n\nO\n\n## [unreleased] — c\n\nC\n';
  const t = rollFile(src);
  assert.equal(t.r.status, 0, t.r.stderr);
  assert.equal(t.bytes.toString(), '# C\n\n## [unreleased]\n\n## [v9] — a\n\nA\n\n## [v9] — c\n\nC\n## [v0] — old\n\nO\n\n');
  const p = planOf(src);
  assert.equal(p.rc, 0, p.log.err.join('\n'));
  const at = p.log.out.indexOf('## CHANGELOG rollup (would write)');
  assert.deepEqual(p.log.out.slice(at + 1, at + 4), ['  5:## [v9] — a', '  9:## [v9] — c', '  ## [unreleased]   <- fresh scaffold inserted above the rolled section']);
});

test('TEST-3464 DR-04 a CRLF file rolls with every byte outside the rolled headings kept', () => {
  const withScaffold = '# C\r\n\r\n## [unreleased]\r\n\r\n## [unreleased] — a\r\n\r\nA\r\n';
  let t = rollFile(withScaffold);
  assert.equal(t.r.status, 0, t.r.stderr);
  assert.equal(t.bytes.toString(), '# C\r\n\r\n## [unreleased]\r\n\r\n## [v9] — a\r\n\r\nA\r\n');
  t = rollFile('# C\r\n\r\n## [unreleased] — a\r\n\r\nA\r\n');
  assert.equal(t.r.status, 0, t.r.stderr);
  assert.equal(t.bytes.toString(), '# C\r\n\r\n## [unreleased]\r\n\r\n## [v9] — a\r\n\r\nA\r\n', 'the fresh scaffold lines take the CR of the first heading');
});

test('TEST-3464 DR-05 a UTF-8 byte order mark is kept', () => {
  const t = rollFile(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('# C\n\n## [unreleased] — a\n\nA\n')]));
  assert.equal(t.r.status, 0, t.r.stderr);
  assert.deepEqual([...t.bytes.subarray(0, 3)], [0xef, 0xbb, 0xbf]);
  assert.equal(t.bytes.subarray(3).toString(), '# C\n\n## [unreleased]\n\n## [v9] — a\n\nA\n');
});

test('TEST-3464 DR-06 bytes that are not valid UTF-8 exit 12 with the encoding line on every command', () => {
  const bad = Buffer.concat([Buffer.from('# C '), Buffer.from([0xe9]), Buffer.from('\n\n## [unreleased] — a\n\nA\n')]);
  const t = rollFile(bad);
  assert.equal(t.r.status, 12);
  assert.equal(t.r.stderr, `${ENCODING}\n`);
  assert.deepEqual(t.bytes, bad, 'the file is unchanged');
  for (const argv of [PLAN_ARGS, CHECK_ARGS()]) {
    const m = mk({ bytes: bad });
    assert.equal(run(argv, m.deps), 12);
    assert.deepEqual(m.log.err, [ENCODING]);
    assert.equal(m.log.audits.length, 0);
  }
  assert.equal(typeof M.decode, 'function', 'must export decode');
  assert.throws(() => M.decode(bad), (e) => e.causeName === 'encoding');
  assert.equal(M.decode(Buffer.from('é')), 'é');
});

test('TEST-3464 DR-07 a one-line file holding only an entry heading exits 12 (an entry without a body)', () => {
  const t = rollFile('## [unreleased] — x');
  assert.equal(t.r.status, 12);
  assert.equal(t.r.stderr, `${MALFORMED}\n`);
  assert.equal(t.bytes.toString(), '## [unreleased] — x');
});

test('TEST-3464 DR-08 a file without a final newline is kept without one on the plan and the cut', () => {
  const src = '# C\n\n## [unreleased] — a\n\nA';
  const t = rollFile(src);
  assert.equal(t.r.status, 0, t.r.stderr);
  assert.equal(t.bytes.toString(), '# C\n\n## [unreleased]\n\n## [v9] — a\n\nA');
  const p = planOf(src);
  assert.equal(p.rc, 0, p.log.err.join('\n'));
  assert.deepEqual(p.log.out.slice(p.log.out.indexOf('## CHANGELOG rollup (would write)') + 1).slice(0, 2), ['  5:## [v9] — a', '  ## [unreleased]   <- fresh scaffold inserted above the rolled section']);
  assert.equal(p.log.seen[0], '## [v9] — a\n\nA');
});

test('TEST-3464 DR-09 a rollup refusal prints the REFUSED line only on stderr, with no bare token before it', () => {
  const cases = [['# C\n\n## [unreleased] foo\n\nx\n', MALFORMED, 12], ['# C\n\nplain\n', EMPTY, 13], ['# C\n\n## [unreleased]\n\n## [v0] — o\n\nx\n', EMPTY, 13]];
  for (const [src, line, code] of cases) {
    const t = rollFile(src);
    assert.equal(t.r.status, code);
    assert.equal(t.r.stderr, `${line}\n`);
    assert.equal(t.r.stdout, '');
    assert.doesNotMatch(t.r.stderr, /^(MALFORMED|ABSENT|EMPTY)/m);
  }
});

// ---- TEST-3465: DR-10, DR-12 to DR-18 -----------------------------------------------------------
test('TEST-3465 DR-10 refusal and header lines use the em dash on both launchers', () => {
  assert.equal(HEADER.includes('—'), true);
  for (const launcher of ['sh', 'ps1']) {
    const m = mk({ text: ENTRY });
    assert.equal(run(PLAN_ARGS.map((a) => (a === 'sh' ? launcher : a)), m.deps), 0);
    assert.equal(m.log.out[0], HEADER);
    assert.doesNotMatch(m.log.out.join('\n'), / - /);
  }
  const r = cli(['plan', '--root', fixtureA({ allNoted: true }), '--version', 'v9', '--target-branch', 'main', '--launcher', 'ps1']);
  assert.ok(r.stdout.startsWith(HEADER), 'the CLI prints the em dash as UTF-8');
  assert.ok(Buffer.from(r.stdout).includes(Buffer.from([0xe2, 0x80, 0x94])));
  for (const line of [MALFORMED, ENCODING, EMPTY]) assert.ok(line.includes(' — '));
  const m = mk({ text: ENTRY, audit: () => ({ status: 0, stdout: '#1 a\n', stderr: '' }) });
  run(CHECK_ARGS('ps1'), m.deps);
  assert.ok(m.log.err[0].startsWith('REFUSED: missing-notes — '));
});

test('TEST-3465 DR-12 the plan words the unlogged PRs as the count line, the items and the advice line', () => {
  const m = mk({ text: ENTRY, audit: () => ({ status: 0, stdout: '#4 four\n#3 three\n', stderr: '' }) });
  assert.equal(run(PLAN_ARGS, m.deps), 0, m.log.err.join('\n'));
  const at = m.log.out.indexOf('- NAMED (not blocking): 2 PR(s) merged since the previous tag have no matching section in these notes:');
  assert.ok(at >= 0, m.log.out.join('\n'));
  assert.deepEqual(m.log.out.slice(at + 1, at + 4), ['    - #4 four', '    - #3 three', "    Add a '## [unreleased] — <title>' section for each, or confirm they are covered under another title."]);
  assert.equal(m.log.out.some((l) => l.includes('missing notes')), false);
});

test('TEST-3465 DR-13 the preconditions come in the order tag, gh, NAMED', () => {
  const gitFn = (args) => (args[0] === 'rev-parse' ? { status: 0, stdout: 'sha\n', stderr: '' } : { status: 1, stdout: '', stderr: '' });
  const m = mk({ text: ENTRY, git: gitFn, audit: () => ({ status: 0, stdout: '#4 four\n', stderr: '' }) });
  assert.equal(run([...PLAN_ARGS, '--gh-block', 'gh CLI not found on PATH'], m.deps), 0, m.log.err.join('\n'));
  const at = m.log.out.indexOf('## Preconditions');
  assert.deepEqual(m.log.out.slice(at + 1, at + 4), ['- would block: tag v9 already exists', '- would block (publish path): gh CLI not found on PATH', '- NAMED (not blocking): 1 PR(s) merged since the previous tag have no matching section in these notes:']);
});

test('TEST-3465 DR-14 the confirm-will-refuse line is printed whenever the NAMED list is not empty, also under a block', () => {
  const tagged = (args) => (args[0] === 'rev-parse' ? { status: 0, stdout: 'sha\n', stderr: '' } : { status: 1, stdout: '', stderr: '' });
  let m = mk({ text: ENTRY, git: tagged, audit: () => ({ status: 0, stdout: '#4 four\n', stderr: '' }) });
  assert.equal(run(PLAN_ARGS, m.deps), 0);
  assert.ok(m.log.out.includes('- confirm will refuse until the NAMED missing release notes are resolved'));
  m = mk({ text: ENTRY, git: tagged });
  assert.equal(run(PLAN_ARGS, m.deps), 0);
  assert.equal(m.log.out.some((l) => l.includes('confirm will refuse') || l.startsWith('- none')), false, 'a block alone prints neither line');
  m = mk({ text: ENTRY });
  assert.equal(run(PLAN_ARGS, m.deps), 0);
  assert.ok(m.log.out.includes('- none — ready to cut with --confirm'));
});

test('TEST-3465 DR-15 an audit failure during the plan prints no stdout, relays its stderr and returns its code', () => {
  const m = mk({ text: ENTRY, audit: () => ({ status: 7, stdout: 'partial\n', stderr: 'REFUSED: notes-history - boom\nsecond\n' }) });
  assert.equal(run(PLAN_ARGS, m.deps), 7);
  assert.deepEqual(m.log.out, []);
  assert.deepEqual(m.log.err, ['REFUSED: notes-history - boom', 'second']);
  assert.ok(m.log.rms.length === 1, 'the temp file is removed on the failure path');
});

test('TEST-3465 DR-16 the local cut checks the rollup (12, 13), then the tag (15), then runs the audit', () => {
  const tagged = (args) => (args[0] === 'rev-parse' ? { status: 0, stdout: 'sha\n', stderr: '' } : { status: 1, stdout: '', stderr: '' });
  let m = mk({ text: '# C\n\n## [unreleased] foo\n\nx\n', git: tagged });
  assert.equal(run(CHECK_ARGS(), m.deps), 12);
  assert.equal(m.log.git.length, 0, 'no tag query before the rollup is accepted');
  assert.equal(m.log.audits.length, 0);
  m = mk({ text: '# C\n', git: tagged });
  assert.equal(run(CHECK_ARGS(), m.deps), 13);
  assert.deepEqual(m.log.err, [EMPTY]);
  m = mk({ text: ENTRY, git: tagged, audit: () => ({ status: 3, stdout: '', stderr: 'audit broke\n' }) });
  assert.equal(run(CHECK_ARGS(), m.deps), 15, 'an audit failure does not hide exit 15');
  assert.deepEqual(m.log.err, ['REFUSED: tag v9 already exists.']);
  assert.equal(m.log.audits.length, 0, 'the audit has not run when the tag refuses');
  m = mk({ text: ENTRY, audit: () => ({ status: 3, stdout: '', stderr: 'audit broke\n' }) });
  assert.equal(run(CHECK_ARGS(), m.deps), 3);
  assert.deepEqual(m.log.err, ['audit broke']);
  m = mk({ text: ENTRY });
  assert.equal(run(CHECK_ARGS(), m.deps), 0);
  assert.deepEqual([m.log.out, m.log.err], [[], []], 'a passing check prints nothing');
  assert.equal(m.log.audits[0].includes('--online'), false, 'the local cut always audits offline');
});

test('TEST-3465 DR-17 the missing-notes refusal is one line joined with semicolons, then the Resume line per launcher', () => {
  const audit = () => ({ status: 0, stdout: '#4 four\n#3 three\n', stderr: '' });
  let m = mk({ text: ENTRY, audit });
  assert.equal(run(CHECK_ARGS('sh'), m.deps), 20);
  assert.deepEqual(m.log.err, ['REFUSED: missing-notes — #4 four; #3 three', 'Resume: bash "/p/aai-release" --version v9 --confirm --no-remote']);
  m = mk({ text: ENTRY, audit });
  assert.equal(run(CHECK_ARGS('ps1'), m.deps), 20);
  assert.deepEqual(m.log.err, ['REFUSED: missing-notes — #4 four; #3 three', 'Resume: pwsh -NoProfile -File "/p/aai-release" -Version v9 -Confirm -NoRemote']);
  assert.equal(M.resumeLine('sh', '/p/x', 'v1'), 'Resume: bash "/p/x" --version v1 --confirm --no-remote');
});

test('TEST-3465 DR-18 rolled headings are listed only at the line start and without a CR', () => {
  assert.equal(typeof M.rolledHeadings, 'function', 'must export rolledHeadings');
  const content = '# C\r\n\r\n## [unreleased]\r\n\r\n## [v9] — a\r\n\r\nA\r\n  ## [v9] — indented quote\r\n> ## [v9] — quoted\r\nsee ## [v9] — inside text\r\n## [v8] — older\r\n';
  assert.deepEqual(M.rolledHeadings(content, 'v9'), [{ n: 5, line: '## [v9] — a' }]);
  const src = '# C\n\n## [unreleased] — a\n\nA\n\n## [v0] — old\n\nquote: ## [v9] — not a heading\n';
  const p = planOf(src);
  const at = p.log.out.indexOf('## CHANGELOG rollup (would write)');
  assert.deepEqual(p.log.out.slice(at + 1, at + 3), ['  5:## [v9] — a', '  ## [unreleased]   <- fresh scaffold inserted above the rolled section']);
});

// ---- TEST-3466: DR-11, DR-19 to DR-22 -----------------------------------------------------------
test('TEST-3466 DR-11 the worktree roll refuses with 12 or 13 and leaves the file unchanged', () => {
  for (const [src, code, line] of [['# C\n\n## [unreleased] foo\n\nx\n', 12, MALFORMED], ['# C\n\n## [v0] — o\n\nx\n', 13, EMPTY]]) {
    const t = rollFile(src);
    assert.equal(t.r.status, code);
    assert.equal(t.r.stderr, `${line}\n`);
    assert.equal(t.bytes.toString(), src);
    assert.deepEqual(t.listing, ['CHANGELOG.md'], 'no temp file is left beside the file');
  }
  const ok = rollFile(ENTRY);
  assert.equal(ok.r.status, 0, ok.r.stderr);
  assert.deepEqual(ok.listing, ['CHANGELOG.md']);
});

test('TEST-3466 DR-19 a plan leaves no new file under the root and the temp directory empty on every exit path', () => {
  const dir = fixtureA({ allNoted: true });
  const tmp = scratch('tmp');
  const real = { readFile: (p) => fs.readFileSync(p), writeFile: (p, d) => fs.writeFileSync(p, d), rename: fs.renameSync, rm: (p) => fs.rmSync(p, { force: true }), tmpdir: () => tmp,
    git: (args, cwd) => { const r = spawnSync('git', args, { cwd, encoding: 'utf8' }); return { status: r.status, stdout: r.stdout, stderr: r.stderr }; }, out() {}, err() {} };
  const before = snapshot(dir);
  const args = ['plan', '--root', dir, '--version', 'v9', '--target-branch', 'main', '--launcher', 'sh'];
  assert.equal(run(args, { ...real, audit: () => ({ status: 0, stdout: '', stderr: '' }) }), 0);
  assert.deepEqual(fs.readdirSync(tmp), [], 'success path');
  assert.equal(run(args, { ...real, audit: () => ({ status: 9, stdout: '', stderr: 'x\n' }) }), 9);
  assert.deepEqual(fs.readdirSync(tmp), [], 'audit failure path');
  assert.throws(() => run(args, { ...real, audit: () => { throw new Error('spawn failed'); } }));
  assert.deepEqual(fs.readdirSync(tmp), [], 'thrown path');
  assert.equal(snapshot(dir), before, 'nothing under the root changed');
});

test('TEST-3466 DR-20 the origin probe is config --get remote.origin.url and a failing probe gives no --online', () => {
  const seen = [];
  const probe = (reply) => (args) => { seen.push(args.join(' ')); return args[0] === 'config' ? reply : { status: 1, stdout: '', stderr: '' }; };
  let m = mk({ text: ENTRY, git: probe({ status: 0, stdout: 'git@x:y/z.git\n', stderr: '' }) });
  assert.equal(run(PLAN_ARGS, m.deps), 0);
  assert.ok(seen.includes('config --get remote.origin.url'), seen.join(' | '));
  assert.equal(seen.some((s) => s.includes('get-url')), false, 'remote get-url is not used');
  assert.equal(m.log.audits[0].includes('--online'), true);
  m = mk({ text: ENTRY, git: probe({ status: 1, stdout: '', stderr: 'fatal: no such remote\n' }) });
  assert.equal(run(PLAN_ARGS, m.deps), 0);
  assert.equal(m.log.audits[0].includes('--online'), false);
  assert.deepEqual(m.log.err, [], 'the probe stderr is captured, not relayed');
  m = mk({ text: ENTRY, git: probe({ status: 0, stdout: '\n', stderr: '' }) });
  assert.equal(run(PLAN_ARGS, m.deps), 0);
  assert.equal(m.log.audits[0].includes('--online'), false, 'an empty value is no origin');
});

// scriptEnv: a PATH holding only git (and nothing else), so node is not found.
function noNodePath() {
  const bin = scratch('nonode');
  const gitBin = spawnSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).stdout.trim();
  fs.symlinkSync(gitBin, path.join(bin, 'git'));
  for (const t of ['dirname', 'basename', 'date', 'mktemp', 'rm', 'cat', 'sed', 'tr', 'uname']) {
    const p = spawnSync('sh', ['-c', `command -v ${t}`], { encoding: 'utf8' }).stdout.trim();
    if (p) fs.symlinkSync(p, path.join(bin, t));
  }
  return bin;
}
const haveBin = (name) => spawnSync('sh', ['-c', `command -v ${name}`], { encoding: 'utf8' }).stdout.trim();

test('TEST-3466 DR-21 each script without node prints the missing-node line on stderr, exit 20, nothing on stdout, no file written', () => {
  const bin = noNodePath();
  const dir = fixtureA({ allNoted: true });
  const before = snapshot(dir);
  const bash = haveBin('bash');
  const tmp = scratch('scripttmp');
  const env = { PATH: bin, HOME: os.homedir(), TMPDIR: tmp, XDG_CACHE_HOME: path.join(tmp, 'xdg-cache') };
  for (const extra of [[], ['--dry-run'], ['--confirm', '--no-remote']]) {
    const r = spawnSync(bash, [SH, '--version', 'v9', ...extra], { cwd: dir, encoding: 'utf8', env });
    assert.equal(r.stderr, `${MISSING_NODE}\n`, `sh ${extra.join(' ')}`);
    assert.equal(r.stdout, '');
    assert.equal(r.status, 20);
  }
  const pwsh = haveBin('pwsh');
  if (pwsh) {
    for (const extra of [[], ['-DryRun'], ['-Confirm', '-NoRemote']]) {
      const r = spawnSync(pwsh, ['-NoProfile', '-NonInteractive', '-File', PS1, '-Version', 'v9', ...extra], { cwd: dir, encoding: 'utf8', env });
      assert.equal(r.stderr.trim(), MISSING_NODE, `ps1 ${extra.join(' ')}`);
      assert.equal(r.stdout, '');
      assert.equal(r.status, 20);
    }
  }
  assert.equal(snapshot(dir), before, 'no file written in the repository');
  assert.deepEqual(fs.readdirSync(tmp).filter((n) => !n.startsWith('xdg-cache')), [], 'no temp file left');
});

test('TEST-3466 DR-22 the ps1 plan reaches the success stream and the child stdout', () => {
  const pwsh = haveBin('pwsh');
  if (!pwsh) { console.log('SKIP-CASE: TEST-3466 DR-22 needs pwsh'); return; }
  const dir = fixtureA({ allNoted: true });
  const env = { ...process.env, XDG_CACHE_HOME: path.join(scratch('xdg'), 'cache') };
  const r = spawnSync(pwsh, ['-NoProfile', '-NonInteractive', '-File', PS1, '-DryRun', '-Version', 'v9'], { cwd: dir, encoding: 'utf8', env });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(r.stdout.startsWith(`${HEADER}\n`) || r.stdout.startsWith(`${HEADER}\r\n`), r.stdout);
  const c = spawnSync(pwsh, ['-NoProfile', '-NonInteractive', '-Command', `$o = @(& '${PS1}' -DryRun -Version v9); [Console]::Out.Write('CAPTURED=' + $o.Count + '|' + $o[0])`], { cwd: dir, encoding: 'utf8', env });
  assert.equal(c.status, 0, c.stderr);
  const m = /^CAPTURED=(\d+)\|(.*)$/s.exec(c.stdout);
  assert.ok(m && Number(m[1]) > 10 && m[2] === HEADER, `a caller that assigns the output captures the plan: ${c.stdout}`);
});

// ---- TEST-3478: N3, an early-closed stdout ends quietly --------------------------------------------
test('TEST-3478 N3 a plan piped into head -1 prints no stack trace and exits 0 or 141', () => {
  // Whether stdout sees EPIPE depends on whether head exits before node finishes writing, so both are correct.
  const dir = fixtureA({ allNoted: true });
  const env = { ...process.env, RC_NODE: process.execPath, RC_MJS: MODULE, RC_DIR: dir };
  const r = spawnSync('bash', ['-c', '"$RC_NODE" "$RC_MJS" plan --root "$RC_DIR" --version v9 --target-branch main --launcher sh | head -1 >/dev/null; exit "${PIPESTATUS[0]}"'], { encoding: 'utf8', env });
  assert.equal(r.stderr, '', `no stderr when the reader closes early: ${r.stderr}`);
  assert.ok(r.status === 0 || r.status === 141, `exit 0 or 141, got ${r.status}`);
});

test('TEST-3478 N3 a plan written to a pipe whose reader has already exited ends quietly with exit 141', () => {
  // Deterministic: the writer sleeps until the reader (true) is long gone, so its first write meets a closed pipe.
  const dir = fixtureA({ allNoted: true });
  const env = { ...process.env, RC_NODE: process.execPath, RC_MJS: MODULE, RC_DIR: dir };
  const r = spawnSync('bash', ['-c', '(sleep 1; exec "$RC_NODE" "$RC_MJS" plan --root "$RC_DIR" --version v9 --target-branch main --launcher sh) | true; exit "${PIPESTATUS[0]}"'], { encoding: 'utf8', env });
  assert.equal(r.stderr, '', `no stderr when the reader is gone: ${r.stderr}`);
  assert.equal(r.status, 141, 'the plan exits 141 when its stdout reader is already closed');
});
