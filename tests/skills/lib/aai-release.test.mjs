// aai-release.test.mjs - node:test cases for .aai/scripts/aai-release.mjs and the release group of the GitHub adapter
// (docs/specs/SPEC-DRAFT-spec-release-publish-on-node.md, TEST-3520 to TEST-3526 and TEST-3536; one case per drift DB-01..DB-18,
// DB-10 and DB-19 live in tests/skills/release-cut.Tests.ps1).
// Every case works in a fresh temp directory: recording fakes for the unit cases, scratch git repositories and the real
// release-cut.mjs / release-finish.mjs for the integration cases, a stub gh (and az) first on PATH that logs its argv.
// No case runs a real gh, pushes to a network remote, opens a PR, tags or publishes, and none reads or writes the
// repository's own CHANGELOG.md.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
// The modules may not exist yet (RED on the baseline): every case must fail on its own assertion.
const M = await import('../../../.aai/scripts/aai-release.mjs').catch(() => ({}));
const A = await import('../../../.aai/scripts/lib/platform-adapter.mjs').catch(() => ({}));

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../..');
const MODULE = path.join(ROOT, '.aai/scripts/aai-release.mjs');
const FINISH = path.join(ROOT, '.aai/scripts/release-finish.mjs');
const SH = path.join(ROOT, '.aai/scripts/aai-release.sh');
const TMP = [];
after(() => { for (const d of TMP) fs.rmSync(d, { recursive: true, force: true }); });

const MISSING_NODE = 'REFUSED: missing-node — Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.';
const GOOD = ['# Changelog', '', '## [unreleased]', '', '## [unreleased] — feat: thing', '', 'Body.', ''].join('\n');
const HOST_FREE = (extra = {}) => ({ ...process.env, AAI_ROLE: '', AAI_GIT_WRITE: '', AAI_RELEASE_DATE: '', AAI_RELEASE_NO_REMOTE: '', ...extra });

const scratch = (label) => {
  const d = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), `aai-rel-${label}-`)));
  TMP.push(d);
  return d;
};
const git = (cwd, ...args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
};
const initRepo = (dir, { identity = true } = {}) => {
  fs.mkdirSync(dir, { recursive: true });
  git(dir, 'init', '-q', '-b', 'main');
  if (identity) { git(dir, 'config', 'user.email', 'fixture@example.invalid'); git(dir, 'config', 'user.name', 'fixture'); }
  git(dir, 'config', 'commit.gpgsign', 'false');
  git(dir, 'config', 'core.autocrlf', 'false');
};
const commitAll = (dir, msg) => { git(dir, 'add', '-A'); git(dir, 'commit', '-q', '-m', msg); };
// fixture: a committed repository on main holding a rollable CHANGELOG.md; origin optional.
function fixture({ origin = '', record = '' } = {}) {
  const dir = path.join(scratch('fx'), 'repo dir');
  initRepo(dir);
  fs.writeFileSync(path.join(dir, 'CHANGELOG.md'), GOOD);
  if (record) { fs.mkdirSync(path.join(dir, 'docs/ai'), { recursive: true }); fs.writeFileSync(path.join(dir, 'docs/ai/pr-config.yaml'), `platform: ${record}\n`); }
  commitAll(dir, 'chore: base');
  if (origin) git(dir, 'remote', 'add', 'origin', origin);
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
  return [files.sort().join('\n'), git(dir, 'status', '--porcelain'), git(dir, 'ls-files', '-s'), git(dir, 'show-ref'), git(dir, 'worktree', 'list')].join('\n--\n');
}
// stubBin: gh and az stubs that log their argv, answer `auth status` with GH_STUB_AUTH_RC (default 0) and fail anything else.
function stubBin() {
  const bin = path.join(scratch('bin'), 'bin');
  fs.mkdirSync(bin, { recursive: true });
  for (const tool of ['gh', 'az']) {
    fs.writeFileSync(path.join(bin, tool), `#!/bin/sh\nprintf '%s\\n' "$*" >> "\${0%/*}/${tool}.log"\n[ "$1 $2" = "auth status" ] && exit "\${GH_STUB_AUTH_RC:-0}"\nexit 1\n`, { mode: 0o755 });
  }
  const log = (tool) => (fs.existsSync(path.join(bin, `${tool}.log`)) ? fs.readFileSync(path.join(bin, `${tool}.log`), 'utf8') : '');
  return { bin, log };
}
const cli = (args, { cwd, env = {}, bin = '' } = {}) => spawnSync(process.execPath, [MODULE, ...args], {
  cwd, encoding: 'utf8', env: HOST_FREE({ ...(bin ? { PATH: `${bin}${path.delimiter}${process.env.PATH}` } : {}), ...env }),
});
const lines = (s) => s.split('\n').filter((l) => l !== '');

// mk: run() deps with recording fakes for the unit cases.
const GIT_WRITE = /^(worktree|branch|add|commit|update-ref|tag|push|checkout|reset|config)$/;
function mk({ gitFn, adapter, env = {}, version = 'v9' } = {}) {
  const log = { git: [], finish: [], cut: [], out: [], err: [], adapter: [], rm: [], write: [] };
  const defaults = (args) => {
    const k = args.join(' ');
    if (k === 'rev-parse --show-toplevel') return { status: 0, stdout: '/repo\n', stderr: '' };
    if (args[0] === 'check-ref-format') return { status: 0, stdout: '', stderr: '' };
    if (k === 'symbolic-ref refs/remotes/origin/HEAD') return { status: 0, stdout: 'refs/remotes/origin/main\n', stderr: '' };
    return { status: 1, stdout: '', stderr: '' };
  };
  const deps = {
    git: (args, cwd) => { log.git.push(args); return gitFn ? gitFn(args, cwd, defaults) : defaults(args); },
    finish: (args) => { log.finish.push(args); return 0; },
    cut: (args) => { log.cut.push(args); return 0; },
    adapter: (root) => { log.adapter.push(root); return adapter ?? { resolved: { platform: 'github', recorded: null, detected: 'unknown', mismatch: false, legacy: true }, adapter: { authStatus: () => 'ok' } }; },
    exists: () => true,
    writeFile: (p, d) => log.write.push([p, d]),
    mkdtemp: () => '/fake/tmp/wt',
    rm: (p) => log.rm.push(p),
    env, now: () => new Date('2026-07-20T10:00:00Z'), cwd: () => '/work',
    out: (l) => log.out.push(l), err: (l) => log.err.push(l),
    tick: async () => {}, interrupted: () => '',
  };
  return { deps, log, version };
}
const run = async (argv, deps) => {
  assert.equal(typeof M.run, 'function', 'aai-release.mjs must export run');
  return M.run(argv, deps);
};
const writes = (log) => log.git.filter((a) => GIT_WRITE.test(a[0]));

// ---- TEST-3520: the seam -------------------------------------------------------------------------------
test('TEST-3520 importing the module in a child node with a temp cwd writes nothing and exposes the six exports', () => {
  const cwd = scratch('imp');
  const r = spawnSync(process.execPath, ['--input-type=module', '-e', `
    const m = await import(${JSON.stringify(pathToFileURL(MODULE).href)});
    process.stdout.write(Object.keys(m).sort().join(','));
  `], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.stdout.split(',').sort(), ['cutReport', 'parseArgs', 'platformBlock', 'resolveVersion', 'run', 'usage']);
  assert.deepEqual(fs.readdirSync(cwd), [], 'import wrote into the cwd');
  assert.equal(r.stderr, '');
});

test('TEST-3520 a remote confirm hands off to finish once with the FINISH_SCRIPT path and the three flags after the 10 and 11 checks', async () => {
  const { deps, log } = mk();
  const rc = await run(['--launcher', 'sh', '--launcher-path', '/p/aai-release.sh', '--version', 'v9', '--confirm'], deps);
  assert.equal(rc, 0, log.err.join('\n'));
  assert.equal(log.finish.length, 1, 'finish runs exactly once');
  const f = log.finish[0];
  assert.equal(path.basename(f[0]), 'release-finish.mjs');
  assert.equal(path.dirname(f[0]), path.dirname(MODULE), 'the finish script lives next to the module');
  assert.deepEqual(f.slice(1), ['--root', '/repo', '--version', 'v9', '--confirm']);
  assert.equal(log.git[0].join(' '), 'rev-parse --show-toplevel', 'the repository check comes first');
  assert.deepEqual([log.cut.length, log.adapter.length, writes(log).length], [0, 0, 0], 'no cut, adapter or git write call');
});

test('TEST-3520 a bare run calls cut with plan, root, version, target branch and launcher', async () => {
  const { deps, log } = mk();
  const rc = await run(['--launcher', 'ps1', '--launcher-path', '/p/aai-release.ps1', '--version', 'v9'], deps);
  assert.equal(rc, 0, log.err.join('\n'));
  assert.deepEqual(log.cut, [['plan', '--root', '/repo', '--version', 'v9', '--target-branch', 'main', '--launcher', 'ps1']]);
  assert.equal(log.finish.length, 0);
  assert.equal(writes(log).length, 0);
});

test('TEST-3520 --dry-run wins over --confirm and --yes is --confirm', async () => {
  const dry = mk();
  await run(['--launcher', 'sh', '--dry-run', '--confirm', '--version', 'v9'], dry.deps);
  assert.equal(dry.log.finish.length, 0);
  assert.equal(dry.log.cut[0][0], 'plan');
  const yes = mk();
  await run(['--launcher', 'sh', '--yes', '--version', 'v9'], yes.deps);
  assert.equal(yes.log.finish.length, 1);
});

test('TEST-3520 resolveVersion prefers the explicit version, then AAI_RELEASE_DATE with dots, then the UTC date of now', () => {
  assert.equal(typeof M.resolveVersion, 'function');
  const now = new Date('2026-07-20T23:30:00Z');
  assert.equal(M.resolveVersion({ version: 'v1.2.3', env: { AAI_RELEASE_DATE: '2026-01-02' }, now }), 'v1.2.3');
  assert.equal(M.resolveVersion({ version: '', env: { AAI_RELEASE_DATE: '2026-01-02' }, now }), 'v2026.01.02');
  assert.equal(M.resolveVersion({ version: '', env: {}, now }), 'v2026.07.20');
});

test('TEST-3520 parseArgs reads the launcher pair first, then the user flags, and AAI_RELEASE_NO_REMOTE=1', () => {
  assert.equal(typeof M.parseArgs, 'function');
  const o = M.parseArgs(['--launcher', 'ps1', '--launcher-path', '/p/x.ps1', '--version', 'v9', '--dry-run', '--no-remote'], {});
  assert.deepEqual({ ...o }, { launcher: 'ps1', launcherPath: '/p/x.ps1', version: 'v9', dryRun: true, confirm: false, noRemote: true, help: false });
  assert.equal(M.parseArgs(['--launcher', 'sh'], { AAI_RELEASE_NO_REMOTE: '1' }).noRemote, true);
  assert.equal(M.parseArgs(['--launcher', 'sh'], { AAI_RELEASE_NO_REMOTE: '0' }).noRemote, false);
});

// ---- TEST-3521: argument drifts ------------------------------------------------------------------------
test('TEST-3521 DB-01 an unknown argument gives two stderr lines, nothing on stdout and exit 1 with no git write', async () => {
  const { deps, log } = mk();
  const rc = await run(['--launcher', 'sh', '--bogus'], deps);
  assert.equal(rc, 1);
  assert.deepEqual(log.err, ['Unknown argument: --bogus', 'Run with --help for usage.']);
  assert.deepEqual(log.out, []);
  assert.deepEqual([writes(log).length, log.cut.length, log.finish.length], [0, 0, 0]);
});

test('TEST-3521 DB-02 -h and --help print the usage in the launcher spelling to stdout and exit 0 without running anything', async () => {
  for (const [launcher, flag, first, yes, nr] of [
    ['sh', '-h', 'usage: aai-release.sh [--version <v>] [--dry-run] [--confirm] [--no-remote]', '--yes', '--no-remote'],
    ['sh', '--help', 'usage: aai-release.sh [--version <v>] [--dry-run] [--confirm] [--no-remote]', '--yes', '--no-remote'],
    ['ps1', '-h', 'usage: aai-release.ps1 [-Version <v>] [-DryRun] [-Confirm] [-NoRemote]', '-Yes', '-NoRemote'],
  ]) {
    const { deps, log } = mk();
    const rc = await run(['--launcher', launcher, flag], deps);
    assert.equal(rc, 0, `${launcher} ${flag}`);
    assert.deepEqual(log.err, []);
    assert.equal(log.out[0], first);
    const text = log.out.join('\n');
    for (const t of [yes, nr, 'AAI_RELEASE_DATE', 'AAI_RELEASE_NO_REMOTE=1']) assert.ok(text.includes(t), `${launcher} usage names ${t}`);
    assert.equal(log.out.at(-1), 'Exit codes: see .aai/SKILL_RELEASE.prompt.md');
    assert.deepEqual([log.git.length, log.cut.length, log.finish.length], [0, 0, 0], 'nothing else runs');
  }
});

test('TEST-3521 DB-03 --version=<v> is accepted and equals --version <v>', async () => {
  const dir = fixture();
  const a = cli(['--launcher', 'sh', '--dry-run', '--no-remote', '--version=v9'], { cwd: dir });
  const b = cli(['--launcher', 'sh', '--dry-run', '--no-remote', '--version', 'v9'], { cwd: dir });
  assert.equal(a.status, 0, a.stderr);
  assert.equal(a.stderr, '');
  assert.ok(a.stdout.includes('- Resolved version: v9'), a.stdout);
  assert.equal(a.stdout, b.stdout);
});

test('TEST-3521 DB-04 --version without a value, or followed by a flag, refuses with exit 1 and runs nothing', async () => {
  for (const argv of [['--version'], ['--version', '--no-remote'], ['--version=']]) {
    const { deps, log } = mk();
    const rc = await run(['--launcher', 'sh', ...argv], deps);
    assert.equal(rc, 1, argv.join(' '));
    assert.deepEqual(log.err, ['REFUSED: --version needs a value.'], argv.join(' '));
    assert.deepEqual(log.out, []);
    assert.deepEqual([log.git.length, log.cut.length, log.finish.length], [0, 0, 0]);
  }
});

test('TEST-3521 DB-05 a version that is not a valid tag and branch name is refused in every mode before any git write', () => {
  for (const bad of ['v 1', 'v1..2']) {
    for (const mode of [[], ['--dry-run'], ['--confirm', '--no-remote'], ['--confirm']]) {
      const dir = fixture();
      const before = snapshot(dir);
      const r = cli(['--launcher', 'sh', ...mode, '--version', bad], { cwd: dir });
      assert.equal(r.status, 1, `${bad} ${mode.join(' ')}: ${r.stdout}${r.stderr}`);
      assert.equal(r.stderr, `REFUSED: invalid version '${bad}' — not a valid git tag or branch name.\n`);
      assert.equal(r.stdout, '');
      assert.equal(snapshot(dir), before, 'no git write');
    }
  }
});

// ---- TEST-3522: the local cut --------------------------------------------------------------------------
const VERSION_DOC = [
  '# AAI Version', '', '- Version: v9', '', 'Notes:',
  '- Written by the release engines (aai-release.sh / aai-release.ps1) at each cut;',
  '  consumed by `.aai/scripts/aai-sync.*` to stamp `Template version:` into the',
  "  target project's `.aai/system/AAI_PIN.md`. Do not edit by hand.", '',
].join('\n');

test('TEST-3522 DB-06 a release branch with unmerged commits refuses with exit 14 and the unchanged line', () => {
  const dir = fixture();
  git(dir, 'checkout', '-q', '-b', 'chore/release-v9');
  fs.writeFileSync(path.join(dir, 'other.txt'), 'other work\n');
  commitAll(dir, 'feat: other work');
  git(dir, 'checkout', '-q', 'main');
  const before = snapshot(dir);
  const r = cli(['--launcher', 'sh', '--confirm', '--no-remote', '--version', 'v9'], { cwd: dir });
  assert.equal(r.status, 14, `${r.stdout}${r.stderr}`);
  assert.equal(r.stderr, 'REFUSED: branch chore/release-v9 already exists with unmerged commits (feat: other work).\n');
  assert.equal(r.stdout, '');
  assert.equal(snapshot(dir), before, 'the branch and the tree are untouched and no worktree is left');
});

test('TEST-3522 DB-07 a failing git step of the cut refuses with git-command, exit 20, and leaves no worktree', () => {
  const dir = path.join(scratch('noid'), 'repo');
  initRepo(dir, { identity: false });
  git(dir, '-c', 'user.email=f@example.invalid', '-c', 'user.name=f', 'config', 'commit.gpgsign', 'false');
  fs.writeFileSync(path.join(dir, 'CHANGELOG.md'), GOOD);
  git(dir, '-c', 'user.email=f@example.invalid', '-c', 'user.name=f', 'add', '-A');
  git(dir, '-c', 'user.email=f@example.invalid', '-c', 'user.name=f', 'commit', '-q', '-m', 'chore: base');
  git(dir, 'config', 'user.useConfigOnly', 'true');
  const home = scratch('home');
  const r = cli(['--launcher', 'sh', '--confirm', '--no-remote', '--version', 'v9'], {
    cwd: dir, env: { HOME: home, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1', EMAIL: '', GIT_AUTHOR_NAME: '', GIT_AUTHOR_EMAIL: '', GIT_COMMITTER_NAME: '', GIT_COMMITTER_EMAIL: '' },
  });
  assert.equal(r.status, 20, `${r.stdout}${r.stderr}`);
  const err = lines(r.stderr);
  assert.equal(err.length, 1, r.stderr);
  assert.match(err[0], /^REFUSED: git-command — git commit -q -m chore\(release\): v9: .+/);
  assert.equal(r.stdout, '');
  assert.equal(git(dir, 'worktree', 'list').trim().split('\n').length, 1, 'only the main worktree is left');
});

test('TEST-3522 DB-08 the cut report header carries the em dash', () => {
  const dir = fixture();
  const r = cli(['--launcher', 'ps1', '--confirm', '--no-remote', '--version', 'v9'], { cwd: dir });
  assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
  assert.equal(lines(r.stdout)[0], '## aai-release — cut complete');
});

test('TEST-3522 DB-09 the cut report names the release SHA on the Remote line, in the launcher flag spelling', () => {
  for (const [launcher, nr] of [['sh', '--no-remote'], ['ps1', '-NoRemote']]) {
    const dir = fixture();
    const r = cli(['--launcher', launcher, '--confirm', '--no-remote', '--version', 'v9'], { cwd: dir });
    assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
    const sha = git(dir, 'rev-parse', 'chore/release-v9').trim();
    const short = git(dir, 'rev-parse', '--short', sha).trim();
    assert.deepEqual(lines(r.stdout), [
      '## aai-release — cut complete', '- Version: v9', `- Commit:  ${short}`, `- Release branch: chore/release-v9 (${sha})`,
      `- Remote:  SKIPPED (${nr}/AAI_RELEASE_NO_REMOTE=1) — release branch chore/release-v9 created locally at ${sha}`,
    ]);
    assert.equal(r.stderr, '');
  }
});

test('TEST-3522 DB-11 AAI_VERSION.md has LF line ends and a final newline, byte for byte', () => {
  const dir = fixture();
  const r = cli(['--launcher', 'ps1', '--confirm', '--no-remote', '--version', 'v9'], { cwd: dir });
  assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
  const bytes = spawnSync('git', ['show', 'chore/release-v9:docs/ai/AAI_VERSION.md'], { cwd: dir }).stdout;
  assert.equal(Buffer.compare(bytes, Buffer.from(VERSION_DOC, 'utf8')), 0, bytes.toString('utf8'));
  assert.equal(git(dir, 'log', '-1', '--format=%s', 'chore/release-v9').trim(), 'chore(release): v9');
  assert.equal(git(dir, 'worktree', 'list').trim().split('\n').length, 1, 'the temporary worktree is removed');
});

test('TEST-3522 DB-14 SIGTERM during the local cut removes the worktree, prints the interrupted line and exits 143', async () => {
  const dir = fixture();
  const bin = path.join(scratch('slow'), 'bin');
  fs.mkdirSync(bin, { recursive: true });
  const marker = path.join(bin, 'marker');
  const real = spawnSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).stdout.trim();
  fs.writeFileSync(path.join(bin, 'git'), `#!/bin/sh\ncase " $* " in *" commit "*) : > "${marker}"; sleep 2;; esac\nexec "${real}" "$@"\n`, { mode: 0o755 });
  const child = spawn(process.execPath, [MODULE, '--launcher', 'sh', '--confirm', '--no-remote', '--version', 'v9'], {
    cwd: dir, env: HOST_FREE({ PATH: `${bin}${path.delimiter}${process.env.PATH}` }),
  });
  let stdout = ''; let stderr = '';
  child.stdout.on('data', (d) => { stdout += d; });
  child.stderr.on('data', (d) => { stderr += d; });
  const closed = new Promise((resolve) => child.on('close', (code, signal) => resolve({ code, signal })));
  const t0 = Date.now();
  while (!fs.existsSync(marker)) {
    if (Date.now() - t0 > 20000) { child.kill('SIGKILL'); assert.fail('the cut never reached the commit step'); }
    await new Promise((r) => setTimeout(r, 20));
  }
  child.kill('SIGTERM');
  const { code, signal } = await closed;
  assert.equal(signal, null, 'the module handles SIGTERM itself');
  assert.equal(code, 143, `${stdout}${stderr}`);
  assert.equal(stderr, 'REFUSED: interrupted (SIGTERM) — the temporary worktree was removed.\n');
  assert.equal(git(dir, 'worktree', 'list').trim().split('\n').length, 1, 'git worktree list shows only the main tree');
});

// ---- TEST-3523: launcher-neutral drifts ----------------------------------------------------------------
test('TEST-3523 DB-12 a missing node gives the one D-LAUNCH line for every mode, exit 20, no Resume line', () => {
  const bin = path.join(scratch('nonode'), 'bin');
  fs.mkdirSync(bin, { recursive: true });
  const dir = fixture();
  for (const mode of [[], ['--dry-run'], ['--confirm', '--no-remote'], ['--confirm'], ['--version', 'v9', '--confirm']]) {
    const r = spawnSync('/bin/sh', [SH, ...mode], { cwd: dir, encoding: 'utf8', env: { PATH: bin } });
    assert.equal(r.status, 20, mode.join(' '));
    assert.equal(r.stderr, `${MISSING_NODE}\n`, mode.join(' '));
    assert.equal(r.stdout, '');
  }
});

test('TEST-3523 DB-13 the cwd of the not-a-repository refusal is the process cwd, not the logical pwd', () => {
  const dir = scratch('norepo');
  const r = spawnSync('/bin/sh', ['-c', `cd "${dir}" && PWD="/logical/elsewhere" exec "${process.execPath}" "${MODULE}" --launcher sh`], { encoding: 'utf8', env: HOST_FREE() });
  assert.equal(r.status, 10, `${r.stdout}${r.stderr}`);
  assert.equal(r.stderr, `REFUSED: not a git repository (cwd=${dir}).\n`);
  assert.equal(r.stdout, '');
});

test('TEST-3523 a repository without CHANGELOG.md refuses with exit 11 and the root path', () => {
  const dir = path.join(scratch('nocl'), 'repo');
  initRepo(dir);
  const r = cli(['--launcher', 'sh', '--dry-run'], { cwd: dir });
  assert.equal(r.status, 11);
  assert.equal(r.stderr, `REFUSED: no CHANGELOG.md at repo root: ${path.join(dir, 'CHANGELOG.md')}\n`);
});

// ---- TEST-3524: the platform block of the plan ---------------------------------------------------------
const BLOCK = '- would block (publish path): ';
test('TEST-3524 DB-15 a plan on a non-GitHub platform blocks by name and calls neither gh nor az', () => {
  const { bin, log } = stubBin();
  const bare = path.join(scratch('bare'), 'origin.git');
  git(scratch('x'), 'init', '-q', '--bare', '-b', 'main', bare);
  const cases = [
    [fixture({ origin: 'https://dev.azure.com/org/proj/_git/repo' }), 'sh', 'azure', '--no-remote'],
    [fixture({ origin: bare, record: 'none' }), 'ps1', 'none', '-NoRemote'],
    [fixture({ origin: bare, record: 'unknown' }), 'sh', 'unknown', '--no-remote'],
  ];
  for (const [dir, launcher, platform, nr] of cases) {
    const r = cli(['--launcher', launcher, '--dry-run', '--version', 'v9'], { cwd: dir, bin });
    assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
    assert.ok(lines(r.stdout).includes(`${BLOCK}the remote release finish runs on GitHub only (platform ${platform}); cut locally with ${nr}`), r.stdout);
    const skipped = cli(['--launcher', launcher, '--dry-run', '--no-remote', '--version', 'v9'], { cwd: dir, bin });
    assert.equal(skipped.stdout.includes('would block (publish path)'), false, 'the skip flag leaves no block');
  }
  assert.equal(log('gh'), '', 'no gh call');
  assert.equal(log('az'), '', 'no az call');
});

test('TEST-3524 DB-16 a platform record that disagrees with the remote is named in the plan and the origin is never fetched', () => {
  const { bin, log } = stubBin();
  const dir = fixture({ origin: 'https://github.com/example-owner/example-repo.git', record: 'azure' });
  const r = cli(['--launcher', 'sh', '--dry-run', '--version', 'v9'], { cwd: dir, bin });
  assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
  assert.ok(lines(r.stdout).includes(`${BLOCK}platform record does not match the remote (recorded=azure, detected=github); re-record: node .aai/scripts/platform.mjs record --force`), r.stdout);
  assert.equal(log('gh') + log('az'), '', 'no host call');
});

test('TEST-3524 the two GitHub reasons stay: gh absent and gh unauthenticated', () => {
  const bare = path.join(scratch('bare2'), 'origin.git');
  git(scratch('y'), 'init', '-q', '--bare', '-b', 'main', bare);
  const dir = fixture({ origin: bare });
  const real = spawnSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).stdout.trim();
  const only = path.join(scratch('gitonly'), 'bin');
  fs.mkdirSync(only, { recursive: true });
  fs.symlinkSync(real, path.join(only, 'git'));
  const absent = spawnSync(process.execPath, [MODULE, '--launcher', 'sh', '--dry-run', '--version', 'v9'], { cwd: dir, encoding: 'utf8', env: HOST_FREE({ PATH: only }) });
  assert.equal(absent.status, 0, `${absent.stdout}${absent.stderr}`);
  assert.ok(lines(absent.stdout).includes(`${BLOCK}gh CLI not found on PATH`), absent.stdout);
  const { bin } = stubBin();
  const denied = cli(['--launcher', 'sh', '--dry-run', '--version', 'v9'], { cwd: dir, bin, env: { GH_STUB_AUTH_RC: '1' } });
  assert.equal(denied.status, 0, `${denied.stdout}${denied.stderr}`);
  assert.ok(lines(denied.stdout).includes(`${BLOCK}gh CLI not authenticated (gh auth status failed)`), denied.stdout);
  const fine = cli(['--launcher', 'sh', '--dry-run', '--version', 'v9'], { cwd: dir, bin });
  assert.equal(fine.stdout.includes('would block (publish path)'), false);
});

test('TEST-3524 platformBlock is empty with the remote skipped and names the reason otherwise', () => {
  assert.equal(typeof M.platformBlock, 'function');
  const mkDeps = (resolved, auth) => ({ adapter: () => ({ resolved, adapter: { authStatus: () => auth } }) });
  const gh = { platform: 'github', recorded: null, detected: 'github', mismatch: false, legacy: false };
  assert.equal(M.platformBlock({ root: '/r', noRemote: true, launcher: 'sh', deps: mkDeps(gh, 'cli_missing') }), '');
  assert.equal(M.platformBlock({ root: '/r', noRemote: false, launcher: 'sh', deps: mkDeps(gh, 'ok') }), '');
  assert.equal(M.platformBlock({ root: '/r', noRemote: false, launcher: 'sh', deps: mkDeps(gh, 'cli_missing') }), 'gh CLI not found on PATH');
  assert.equal(M.platformBlock({ root: '/r', noRemote: false, launcher: 'sh', deps: mkDeps(gh, 'unauthenticated') }), 'gh CLI not authenticated (gh auth status failed)');
});

// ---- TEST-3525: the release group of the GitHub adapter ------------------------------------------------
const OPTS = { cwd: '/w', encoding: 'utf8', timeout: 60000, maxBuffer: 8 * 1024 * 1024, env: process.env };
function recorder() {
  const calls = [];
  const runner = (cmd, args, opts) => { calls.push([cmd, args, opts]); return { status: 0, stdout: '{}', stderr: '' }; };
  return { calls, runner };
}
test('TEST-3525 every release method of the github adapter spawns gh with exactly its D-HOST argv and options', () => {
  assert.equal(typeof A.createAdapter, 'function');
  assert.deepEqual({ ...A.RELEASE_GH_OPTIONS }, { encoding: 'utf8', timeout: 60000, maxBuffer: 8 * 1024 * 1024 });
  const { calls, runner } = recorder();
  const rel = A.createAdapter('github', { cwd: '/w', runner }).release;
  assert.ok(rel, 'the github adapter has a release group');
  const table = [
    [() => rel.authStatus(), ['auth', 'status']],
    [() => rel.repoView(), ['repo', 'view', '--json', 'nameWithOwner']],
    [() => rel.prList({ repo: 'o/r', head: 'b', state: 'all', json: 'number,state' }), ['pr', 'list', '--repo', 'o/r', '--head', 'b', '--state', 'all', '--json', 'number,state']],
    [() => rel.prList({ repo: 'o/r', base: 'b', state: 'open', json: 'number' }), ['pr', 'list', '--repo', 'o/r', '--base', 'b', '--state', 'open', '--json', 'number']],
    [() => rel.prView({ n: 7, repo: 'o/r', json: 'state' }), ['pr', 'view', '7', '--repo', 'o/r', '--json', 'state']],
    [() => rel.prView({ n: '7', json: 'body,files' }), ['pr', 'view', '7', '--json', 'body,files']],
    [() => rel.prCreate({ repo: 'o/r', base: 'main', head: 'h', title: 'T', bodyFile: '/f' }), ['pr', 'create', '--repo', 'o/r', '--base', 'main', '--head', 'h', '--title', 'T', '--body-file', '/f']],
    [() => rel.prEdit({ repo: 'o/r', n: 7, bodyFile: '/f' }), ['pr', 'edit', '7', '--repo', 'o/r', '--body-file', '/f']],
    [() => rel.prMerge({ repo: 'o/r', n: 7, head: 'abc' }), ['pr', 'merge', '7', '--repo', 'o/r', '--squash', '--match-head-commit', 'abc']],
    [() => rel.api({ endpoint: 'repos/o/r/x' }), ['api', 'repos/o/r/x']],
    [() => rel.api({ endpoint: 'repos/o/r/x', paged: true }), ['api', '--paginate', '--slurp', 'repos/o/r/x?per_page=100']],
    [() => rel.runList({ repo: 'o/r', workflow: 'release.yml', commit: 'abc', json: 'databaseId' }), ['run', 'list', '--repo', 'o/r', '--workflow', 'release.yml', '--commit', 'abc', '--json', 'databaseId']],
    [() => rel.releaseView({ repo: 'o/r', tag: 'v9', json: 'body,url' }), ['release', 'view', 'v9', '--repo', 'o/r', '--json', 'body,url']],
  ];
  for (const [call, argv] of table) {
    calls.length = 0;
    const res = call();
    assert.equal(calls.length, 1, argv.join(' '));
    assert.equal(calls[0][0], 'gh');
    assert.deepEqual(calls[0][1], argv);
    assert.deepEqual(calls[0][2], OPTS, argv.join(' '));
    assert.equal(res.status, 0, 'the raw spawn result comes back');
    assert.equal(res.stdout, '{}');
  }
});

test('TEST-3525 checksRunner spawns gh with 32 MiB and the 60 second timeout of github-checks', () => {
  const { calls, runner } = recorder();
  const run2 = A.createAdapter('github', { cwd: '/w', runner }).release.checksRunner();
  assert.equal(typeof run2, 'function');
  const res = run2(['api', 'x']);
  assert.deepEqual(calls, [['gh', ['api', 'x'], { cwd: '/w', encoding: 'utf8', timeout: 60000, maxBuffer: 32 * 1024 * 1024 }]]);
  assert.equal(res.status, 0);
});

test('TEST-3525 the azure, unknown and none adapters have no release group', () => {
  for (const p of ['azure', 'unknown', 'none']) assert.equal(A.createAdapter(p, { cwd: '/w' }).release, undefined, p);
  assert.ok(A.createAdapter('github', { cwd: '/w' }).release);
});

// ---- TEST-3526: release-finish on the adapter ----------------------------------------------------------
function finishRefusal(origin, record) {
  const { bin, log } = stubBin();
  const dir = fixture({ origin, record });
  const commonDir = path.resolve(dir, git(dir, 'rev-parse', '--git-common-dir').trim());
  const before = snapshot(dir);
  const r = spawnSync(process.execPath, [FINISH, '--root', dir, '--version', 'v9', '--confirm'], {
    cwd: dir, encoding: 'utf8', env: HOST_FREE({ PATH: `${bin}${path.delimiter}${process.env.PATH}` }),
  });
  assert.equal(r.status, 20, `${r.stdout}${r.stderr}`);
  assert.equal(r.stdout, '');
  assert.equal(log('gh') + log('az'), '', 'no host call');
  assert.equal(fs.existsSync(path.join(commonDir, 'aai/releases')), false, 'no journal');
  assert.equal(snapshot(dir), before, 'refs and tree unchanged');
  return lines(r.stderr);
}
test('TEST-3526 DB-17 a remote confirm on a non-GitHub platform refuses release-platform before any host call, journal or ref change', () => {
  const err = finishRefusal('https://dev.azure.com/org/proj/_git/repo', '');
  assert.equal(err[0], 'REFUSED: release-platform — the remote release finish runs on GitHub only (platform azure); cut locally with --no-remote and open the release PR on your host');
  assert.ok(err.some((l) => l.startsWith('Resume: node ')), err.join('\n'));
});

test('TEST-3526 DB-18 a remote confirm with a platform mismatch refuses platform-mismatch before any host call', () => {
  const err = finishRefusal('https://github.com/example-owner/example-repo.git', 'azure');
  assert.equal(err[0], 'REFUSED: platform-mismatch — recorded=azure detected=github; re-record: node .aai/scripts/platform.mjs record --force');
  assert.ok(err.some((l) => l.startsWith('Resume: node ')), err.join('\n'));
});

// ---- TEST-3536: an early-closed stdout ends quietly ----------------------------------------------------
test('TEST-3536 the sh launcher plan and the usage piped into head -1 print no stack trace and exit 0 or 141', () => {
  const dir = fixture();
  const env = HOST_FREE({ RC_SH: SH, RC_DIR: dir });
  for (const args of ['--dry-run --no-remote --version v9', '--help']) {
    const r = spawnSync('bash', ['-c', `cd "$RC_DIR" && bash "$RC_SH" ${args} | head -1 >/dev/null; exit "\${PIPESTATUS[0]}"`], { encoding: 'utf8', env });
    assert.equal(r.stderr, '', `no stderr when the reader closes early: ${r.stderr}`);
    assert.ok(r.status === 0 || r.status === 141, `exit 0 or 141, got ${r.status}`);
  }
});

test('TEST-3536 a plan or a usage written to a pipe whose reader has already exited ends quietly with exit 141', () => {
  const dir = fixture();
  const env = HOST_FREE({ RC_SH: SH, RC_DIR: dir });
  for (const args of ['--dry-run --no-remote --version v9', '--help']) {
    // Deterministic: the writer sleeps until the reader (true) is long gone, so its first write meets a closed pipe.
    const r = spawnSync('bash', ['-c', `(cd "$RC_DIR" && sleep 1 && exec bash "$RC_SH" ${args}) | true; exit "\${PIPESTATUS[0]}"`], { encoding: 'utf8', env });
    assert.equal(r.stderr, '', `no stderr when the reader is gone: ${r.stderr}`);
    assert.equal(r.status, 141, args);
  }
});

// ---- TEST-3537: a signal to the whole process group, and the handlers' lifetime ------------------------
// A terminal Ctrl-C reaches the git child as well as node: the git step dies, and the interrupt still wins over the git-command refusal.
for (const [sig, exit] of [['SIGINT', 130], ['SIGTERM', 143]]) {
  test(`TEST-3537 ${sig} sent to the whole process group during a git step of the local cut prints the interrupted line and exits ${exit}`, async () => {
    const dir = fixture();
    const bin = path.join(scratch('grp'), 'bin');
    fs.mkdirSync(bin, { recursive: true });
    const marker = path.join(bin, 'marker');
    const real = spawnSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).stdout.trim();
    fs.writeFileSync(path.join(bin, 'git'), `#!/bin/sh\ncase " $* " in *" commit "*) : > "${marker}"; sleep 5;; esac\nexec "${real}" "$@"\n`, { mode: 0o755 });
    const child = spawn(process.execPath, [MODULE, '--launcher', 'sh', '--confirm', '--no-remote', '--version', 'v9'], {
      cwd: dir, detached: true, env: HOST_FREE({ PATH: `${bin}${path.delimiter}${process.env.PATH}` }),
    });
    let stdout = ''; let stderr = '';
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    const closed = new Promise((resolve) => child.on('close', (code, signal) => resolve({ code, signal })));
    const t0 = Date.now();
    while (!fs.existsSync(marker)) {
      if (Date.now() - t0 > 20000) { process.kill(-child.pid, 'SIGKILL'); assert.fail('the cut never reached the commit step'); }
      await new Promise((r) => setTimeout(r, 20));
    }
    process.kill(-child.pid, sig);
    const { code, signal } = await closed;
    assert.equal(signal, null, 'the module handles the signal itself');
    assert.equal(code, exit, `${stdout}${stderr}`);
    assert.equal(stderr, `REFUSED: interrupted (${sig}) — the temporary worktree was removed.\n`);
    assert.equal(stdout, '');
    assert.equal(git(dir, 'worktree', 'list').trim().split('\n').length, 1, 'git worktree list shows only the main tree');
  });
}

test('TEST-3537 the signal handlers are removed after the cut on success, on a git refusal and on an interrupt', async () => {
  const cases = [
    ['success', () => ({ status: 0, stdout: 'abc1234\n', stderr: '' }), '', 0],
    ['refusal', (a) => (a[0] === 'commit' ? { status: 1, stdout: '', stderr: 'boom\n' } : { status: 0, stdout: 'abc1234\n', stderr: '' }), '', 20],
    ['interrupt', () => ({ status: 0, stdout: 'abc1234\n', stderr: '' }), 'SIGINT', 130],
  ];
  for (const [label, ok, sig, exit] of cases) {
    const { deps, log } = mk({
      gitFn: (a, cwd, defaults) => (a[0] === 'rev-parse' && a[1] === '-q' ? { status: 1, stdout: '', stderr: '' } : a[0] === 'check-ref-format' || a.join(' ') === 'rev-parse --show-toplevel' || a[0] === 'symbolic-ref' ? defaults(a) : ok(a)),
    });
    const events = [];
    deps.arm = () => events.push('arm');
    deps.disarm = () => events.push('disarm');
    deps.interrupted = () => sig;
    const origGit = deps.git;
    deps.git = (a, cwd) => { if (a[0] === 'worktree' && a[1] === 'remove') events.push('remove'); return origGit(a, cwd); };
    const code = await run(['--launcher', 'sh', '--confirm', '--no-remote', '--version', 'v9'], deps);
    assert.equal(code, exit, `${label}: ${log.err.join('|')}`);
    assert.deepEqual(events.filter((e) => e !== 'remove'), ['arm', 'disarm'], `${label}: armed once, disarmed once`);
    assert.ok(events.lastIndexOf('disarm') > events.lastIndexOf('remove'), `${label}: disarmed after the worktree was removed`);
  }
});

// ---- TEST-3538: DB-20, a repository with no origin and no record ---------------------------------------
test('TEST-3538 DB-20 an unrecorded repository with no origin resolves to platform none: the plan blocks and a remote confirm refuses release-platform', () => {
  const { bin, log } = stubBin();
  const dir = fixture();
  const r = cli(['--launcher', 'sh', '--dry-run', '--version', 'v9'], { cwd: dir, bin });
  assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
  assert.ok(lines(r.stdout).includes(`${BLOCK}the remote release finish runs on GitHub only (platform none); cut locally with --no-remote`), r.stdout);
  const err = finishRefusal('', '');
  assert.equal(err[0], 'REFUSED: release-platform — the remote release finish runs on GitHub only (platform none); cut locally with --no-remote and open the release PR on your host');
  assert.equal(log('gh') + log('az'), '', 'no host call');
});
