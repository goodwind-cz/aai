// aai-release.test.mjs - node:test cases for .aai/scripts/aai-release.mjs and the release group of the GitHub adapter
// (docs/specs/SPEC-0282-spec-release-publish-on-node.md, TEST-3520 to TEST-3526 and TEST-3536; one case per drift DB-01..DB-18,
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

// ci-flake-root-causes: the git child's own death by the signal decides the interrupt. node's handler for the
// same signal runs from its event loop, and on a loaded Linux runner it had not run yet when the failed git step
// was read (the CI red of PR #597), so a cut whose handler is late must still report the interrupt.
for (const [sig, exit] of [['SIGINT', 130], ['SIGTERM', 143]]) {
  test(`TEST-4164 a git step killed by ${sig} before node's own handler has run still prints the interrupted line and exits ${exit}`, async () => {
    const { deps, log } = mk({
      gitFn: (a, cwd, defaults) => (a[0] === 'rev-parse' && a[1] === '-q' ? { status: 1, stdout: '', stderr: '' }
        : a[0] === 'check-ref-format' || a.join(' ') === 'rev-parse --show-toplevel' || a[0] === 'symbolic-ref' ? defaults(a)
          : a[0] === 'commit' ? { status: 1, signal: sig, stdout: '', stderr: '' }
            : { status: 0, stdout: 'abc1234\n', stderr: '' }),
    });
    const code = await run(['--launcher', 'sh', '--confirm', '--no-remote', '--version', 'v9'], deps);
    assert.equal(code, exit, log.err.join('|'));
    assert.deepEqual(log.err, [`REFUSED: interrupted (${sig}) — the temporary worktree was removed.`]);
    assert.ok(log.git.some((a) => a[0] === 'worktree' && a[1] === 'remove'), 'the temporary worktree is removed');
  });
}

test('TEST-4164 a git step killed by a signal other than SIGINT or SIGTERM stays a git-command refusal', async () => {
  const { deps, log } = mk({
    gitFn: (a, cwd, defaults) => (a[0] === 'rev-parse' && a[1] === '-q' ? { status: 1, stdout: '', stderr: '' }
      : a[0] === 'check-ref-format' || a.join(' ') === 'rev-parse --show-toplevel' || a[0] === 'symbolic-ref' ? defaults(a)
        : a[0] === 'commit' ? { status: 1, signal: 'SIGKILL', stdout: '', stderr: '' }
          : { status: 0, stdout: 'abc1234\n', stderr: '' }),
  });
  const code = await run(['--launcher', 'sh', '--confirm', '--no-remote', '--version', 'v9'], deps);
  assert.equal(code, 20, log.err.join('|'));
  assert.match(log.err[0], /^REFUSED: git-command — git commit /);
});

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

// ---- TEST-4026: the PowerShell grammar of the module under --launcher ps1 (SPEC node-first-phase5-closeout D-RELEASE) ----
const PS1_FORMS = [
  // [name, double-dash form, option patch]
  ['-DryRun', ['--dry-run'], { dryRun: true }],
  ['-Confirm', ['--confirm'], { confirm: true }],
  ['-Yes', ['--yes'], { confirm: true }],
  ['-NoRemote', ['--no-remote'], { noRemote: true }],
];
const cases3 = (name) => [name, name.toLowerCase(), name.toUpperCase()];
const parse = (argv) => M.parseArgs(argv, {});
const LP = ['--launcher', 'ps1', '--launcher-path', '/p/aai-release.ps1'];

test('TEST-4026 each PowerShell switch in three letter cases parses as its double-dash form under ps1', () => {
  assert.equal(typeof M.parseArgs, 'function');
  for (const [name, dd, patch] of PS1_FORMS) {
    const want = parse([...LP, ...dd]);
    assert.equal(want.dryRun === (patch.dryRun === true), true);
    for (const form of cases3(name)) {
      assert.deepEqual(parse([...LP, form]), want, form);
      for (const on of ['$true', 'true', '$TRUE', 'True']) assert.deepEqual(parse([...LP, `${form}:${on}`]), want, `${form}:${on}`);
      const off = parse([...LP]);
      for (const v of ['$false', 'false', '$FALSE', 'False']) assert.deepEqual(parse([...LP, `${form}:${v}`]), off, `${form}:${v}`);
    }
  }
});

test('TEST-4026 -Version takes a value by space or colon in any letter case, and refuses a missing value', () => {
  const want = parse([...LP, '--version', 'v9']);
  assert.equal(want.version, 'v9');
  for (const form of cases3('-Version')) {
    assert.deepEqual(parse([...LP, form, 'v9']), want, form);
    assert.deepEqual(parse([...LP, `${form}:v9`]), want, `${form}:v9`);
  }
  for (const argv of [['-Version'], ['-Version:'], ['-Version', '-DryRun']]) {
    assert.deepEqual(parse([...LP, ...argv]), { error: ['REFUSED: --version needs a value.'], code: 1 }, argv.join(' '));
  }
});

test('TEST-4026 every form accepted today is still accepted under ps1, and common parameters and a second bare word are not', () => {
  for (const argv of [['--version', 'v9'], ['--version=v9'], ['--dry-run'], ['--confirm'], ['--yes'], ['--no-remote'], ['-h'], ['--help']]) {
    assert.equal(parse([...LP, ...argv]).error, undefined, argv.join(' '));
  }
  assert.equal(parse([...LP, '--dry-run', '-Confirm']).confirm, false, 'dry run wins over confirm as before');
  for (const bad of ['-Verbose', '-Debug', '-ErrorAction', '-Deb', '-Verb', '-Bogus', '-DryRun:maybe', '-Yes:0', '-X']) {
    assert.deepEqual(parse([...LP, bad]), { error: [`Unknown argument: ${bad}`, 'Run with --help for usage.'], code: 1 }, bad);
  }
});

test('TEST-4026 Windows PowerShell 5.1 -File hands -Switch:value over as two tokens (-Switch: then the value); the colon value binds to its flag', () => {
  for (const [name, dd] of PS1_FORMS) {
    const on = parse([...LP, ...dd]);
    const off = parse([...LP]);
    for (const form of cases3(name)) {
      for (const v of ['true', '$true', 'True', '$TRUE']) assert.deepEqual(parse([...LP, `${form}:`, v]), on, `${form}: ${v}`);
      for (const v of ['false', '$false', 'False', '$FALSE']) assert.deepEqual(parse([...LP, `${form}:`, v]), off, `${form}: ${v}`);
    }
  }
  const want = parse([...LP, '--version', 'v9', '--dry-run', '--no-remote']);
  assert.deepEqual(parse([...LP, '-Version:', 'v9', '-DryRun:', 'true', '-NoRemote:', 'true']), want);
  assert.deepEqual(parse([...LP, '-VERSION:', 'v9', '-dryrun:', '$true', '-noremote:', '$true']), want);
  assert.deepEqual(parse([...LP, '-Version:', 'v9', '-DryRun:', '$false']), parse([...LP, '--version', 'v9']));
  assert.deepEqual(parse([...LP, '-Version:']), { error: ['REFUSED: --version needs a value.'], code: 1 });
  assert.deepEqual(parse([...LP, '-Version:', '-DryRun']), { error: ['REFUSED: --version needs a value.'], code: 1 });
  assert.deepEqual(parse([...LP, '-DryRun:', 'maybe']), { error: ['Unknown argument: -DryRun:maybe', 'Run with --help for usage.'], code: 1 });
  assert.deepEqual(parse([...LP, '-DryRun:']), { error: ['Unknown argument: -DryRun:', 'Run with --help for usage.'], code: 1 });
});

// Hosted run 45115879244 (Windows PowerShell 5.1 -File, both 5.1 legs): -DryRun:$false gave 'Unknown argument: $false' and
// -Version:v9 -DryRun:$true -NoRemote:true gave 'Unknown argument: true', so 5.1 -File hands the switch over WITHOUT its colon
// (-DryRun, then the value as its own token). A switch followed by a boolean word takes it as its value.
test('TEST-4026 Windows PowerShell 5.1 -File drops the colon of -Switch:value (-Switch, then the boolean word); the word binds to its switch', () => {
  const want = parse([...LP, '--version', 'v9', '--dry-run', '--no-remote']);
  assert.deepEqual(parse([...LP, '-Version', 'v9', '-DryRun', '$true', '-NoRemote', 'true']), want);
  assert.deepEqual(parse([...LP, '-Version', 'v9', '-DryRun', '$false']), parse([...LP, '--version', 'v9']));
  for (const [name, dd] of PS1_FORMS) {
    if (dd[0] === '--version') continue;
    const on = parse([...LP, ...dd]);
    for (const form of cases3(name)) {
      for (const v of ['true', '$true', 'TRUE']) assert.deepEqual(parse([...LP, form, v]), on, `${form} ${v}`);
      for (const v of ['false', '$false', 'False']) assert.deepEqual(parse([...LP, form, v]), parse([...LP]), `${form} ${v}`);
    }
  }
  // a non-boolean bare word after a switch is still the positional version, as before
  assert.deepEqual(parse([...LP, '-DryRun', 'v9']), parse([...LP, '--dry-run', '--version', 'v9']));
});

test('TEST-4026 an unambiguous prefix of a PowerShell flag binds like the full name, in any letter case, with the colon forms', () => {
  const want = {
    '-Ver': parse([...LP, '--version', 'v9']), '-V': parse([...LP, '--version', 'v9']), '-Versio': parse([...LP, '--version', 'v9']),
    '-Dry': parse([...LP, '--dry-run']), '-D': parse([...LP, '--dry-run']), '-Conf': parse([...LP, '--confirm']), '-C': parse([...LP, '--confirm']),
    '-Y': parse([...LP, '--yes']), '-NoR': parse([...LP, '--no-remote']), '-N': parse([...LP, '--no-remote']),
  };
  for (const [prefix, expected] of Object.entries(want)) {
    const isVersion = expected.version !== '';
    for (const form of [prefix, prefix.toLowerCase(), prefix.toUpperCase()]) {
      if (isVersion) {
        assert.deepEqual(parse([...LP, form, 'v9']), expected, `${form} v9`);
        assert.deepEqual(parse([...LP, `${form}:v9`]), expected, `${form}:v9`);
      } else {
        assert.deepEqual(parse([...LP, form]), expected, form);
        assert.deepEqual(parse([...LP, `${form}:$true`]), expected, `${form}:$true`);
        assert.deepEqual(parse([...LP, `${form}:$false`]), parse([...LP]), `${form}:$false`);
      }
    }
  }
  assert.deepEqual(parse(['-Ver', 'v9']), { error: ['Unknown argument: -Ver', 'Run with --help for usage.'], code: 1 }, 'a prefix is a PowerShell form: still refused without the ps1 launcher');
});

test('TEST-4026 a name that is a prefix of more than one flag is refused on one line naming the candidates (parseArgs over a synthetic flag table)', () => {
  const table = { '-verbose': '--verbose', '-version': '--version', '-dryrun': '--dry-run' };
  const run3 = (argv) => M.parseArgs([...LP, ...argv], {}, table);
  assert.deepEqual(run3(['-ver']), { error: ['REFUSED: ambiguous argument -ver: matches -verbose, -version.'], code: 1 });
  assert.deepEqual(run3(['-VER:v9']), { error: ['REFUSED: ambiguous argument -VER:v9: matches -verbose, -version.'], code: 1 });
  assert.equal(run3(['-vers', 'v9']).version, 'v9');
  assert.equal(run3(['-Dry']).dryRun, true);
  assert.deepEqual(run3(['-x']), { error: ['Unknown argument: -x', 'Run with --help for usage.'], code: 1 });
  // every prefix of the five real flags is unambiguous (measured: the old binder agrees), so no real argument reaches the refusal
  for (const f of ['-Version', '-DryRun', '-Confirm', '-Yes', '-NoRemote']) for (let n = 2; n <= f.length; n++) {
    const r = parse([...LP, f.slice(0, n)]);
    assert.ok(r.error === undefined || r.error[0].startsWith('REFUSED: --version needs a value'), `${f.slice(0, n)}: ${JSON.stringify(r.error)}`);
  }
});

test('TEST-4026 the first bare word is the version when no -Version is given (the old positional binding); a second bare word or a bare word beside -Version is refused', () => {
  assert.equal(parse([...LP, 'extra']).version, 'extra');
  assert.deepEqual(parse([...LP, '-DryRun', 'extra']), parse([...LP, '--dry-run', '--version', 'extra']));
  assert.deepEqual(parse([...LP, 'extra', '-DryRun']), parse([...LP, '--dry-run', '--version', 'extra']));
  const second = { error: ['Unknown argument: two', 'Run with --help for usage.'], code: 1 };
  assert.deepEqual(parse([...LP, 'one', 'two']), second);
  assert.deepEqual(parse([...LP, '-Version', 'v9', 'two']), second);
  assert.deepEqual(parse([...LP, 'two', '-Version', 'v9']), second);
  assert.deepEqual(parse(['extra']), { error: ['Unknown argument: extra', 'Run with --help for usage.'], code: 1 }, 'under sh a bare word is still refused');
});

test('TEST-4026 under --launcher sh or none each PowerShell form is Unknown argument with exit 1', () => {
  for (const lp of [['--launcher', 'sh'], []]) {
    for (const form of ['-Version', '-DryRun', '-Confirm', '-Yes', '-NoRemote', '-dryrun', '-DryRun:$true']) {
      assert.deepEqual(parse([...lp, form]), { error: [`Unknown argument: ${form}`, 'Run with --help for usage.'], code: 1 }, `${lp.join(' ')} ${form}`);
    }
  }
});

// ---- TEST-4027: D-RELEASE-MATRIX, the frozen launcher against the new one under pwsh (M01 to M20) ----------
// Both launchers sit next to the same module copy (two copies of .aai/scripts: the old one holds the hash-verified frozen
// launcher). Each case runs in a fresh scratch repository, by -File and in session; the remote finish is never run, and a
// stub gh and az on PATH record any host call (none is expected).
const R = await import('./release-reference.mjs');
const PWSH = (() => { const r = spawnSync('sh', ['-c', 'command -v pwsh'], { encoding: 'utf8' }); return r.status === 0 ? r.stdout.trim() : ''; })();
const OWN = [];
after(() => { for (const d of OWN) R.removeOwnScratch(d); });
const ownScratch = (label) => { const d = R.createOwnScratch(label); OWN.push(d); return d; };
const MATRIX_ENV = (extra = {}) => {
  const env = {};
  for (const [k, v] of Object.entries(process.env)) if (!/^GIT_/.test(k)) env[k] = v;
  return { ...env, AAI_ROLE: '', AAI_GIT_WRITE: '', AAI_RELEASE_DATE: '2026-07-20', AAI_RELEASE_NO_REMOTE: '', GIT_CONFIG_NOSYSTEM: '1', ...extra };
};
// Every pwsh spawn gets its own cache directory, so a broken operator PowerShell cache cannot fail these cases.
const PWSH_CACHES = [];
after(() => { for (const d of PWSH_CACHES) fs.rmSync(d, { recursive: true, force: true }); });
function pwshEnv(t, env = process.env) {
  const cache = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-pwsh-cache-'));
  if (t && typeof t.after === 'function') t.after(() => fs.rmSync(cache, { recursive: true, force: true }));
  else PWSH_CACHES.push(cache);
  return { ...env, XDG_CACHE_HOME: cache };
}
const D = (...t) => t;
const MATRIX = [
  ['M01', D('-h')], ['M02', D('--help')], ['M03', D('-Version', 'v9', '-DryRun')], ['M04', D('-Version:v9', '-DryRun')],
  ['M05', D('-version', 'v9', '-dryrun')], ['M06', D('--version', 'v9', '--dry-run')], ['M07', D('-DryRun', '-NoRemote')],
  ['M08', D('-Confirm', '-NoRemote', '-Version', 'v9')], ['M09', D('-Yes', '-NoRemote', '-Version', 'v9')],
  ['M10', D('-DryRun:$false', '-NoRemote', '-Version', 'v9')], ['M11', D('-Bogus')],
  ['M12', D('-DryRun', '-Version', 'v9'), { repo: 'none' }], ['M13', D('-DryRun', '-Version', 'v9'), { repo: 'nochangelog' }],
  ['M14', D('-DryRun'), { env: { AAI_RELEASE_DATE: '2026-07-20', AAI_RELEASE_NO_REMOTE: '1' } }], ['M15', D('-DryRun', 'extra')],
  ['M16', D('-DryRun', '-Version', 'v9'), { nonode: true }],
  // old-equal after the owner's decision 3: prefixes and the bare first word keep the old binding (DR-R1, DR-R3 preserved)
  ['M17', D('-Ver', 'v9', '-Dry')], ['M19', D('v9')], ['M21', D('-Conf', '-NoR', '-V', 'v9')], ['M22', D('-Y', '-N', '-Ver:v9')],
  ['M23', D('-D', '-NoR', '-V:v9')], ['M24', D('v9', 'extra')], ['M25', D('-Version', 'v9', 'extra')], ['M26', D('-Dry:$false', '-N', '-Ver', 'v9')],
];
// Measured, not predicted by D-RELEASE-MATRIX: in session the old launcher binds a bare first word by position to -Version, and
// PowerShell reads --help and --version there as bare words, so M02 and M06 (session only) fail in the old launcher. The
// first bare word, the unambiguous prefixes and the second bare word are old-equal (M15, M17, M19, M21 to M26).
const MEASURED_BARE_WORD = {
  'M02 session': { old: (o) => o.code === 1 && o.out === '' && o.err === 'REFUSED: --version needs a value.\n', new: (f) => f },
  'M06 session': { old: (o) => o.code === 1 && o.out === '' && o.err === 'REFUSED: --version needs a value.\n', new: (f) => f },
};
const DR = [
  ['M18', D('-Verbose'), 1, ['Unknown argument: -Verbose', 'Run with --help for usage.']],
  ['M20', D('-Version'), 1, ['REFUSED: --version needs a value.']],
];
function matrixRepo(kind) {
  if (kind === 'none') return scratch('nogit');
  const dir = path.join(scratch('mx'), 'repo dir');
  initRepo(dir);
  if (kind === 'nochangelog') fs.writeFileSync(path.join(dir, 'README.md'), 'x\n'); else fs.writeFileSync(path.join(dir, 'CHANGELOG.md'), GOOD);
  commitAll(dir, 'chore: base');
  return dir;
}
function launcherDirs() {
  const root = ownScratch('lx-');
  const dirs = {};
  for (const kind of ['old', 'new']) {
    const dir = path.join(root, kind, '.aai', 'scripts');
    fs.cpSync(path.join(ROOT, '.aai/scripts'), dir, { recursive: true });
    if (kind === 'old') R.materializeReleaseReference(ROOT, dir);
    dirs[kind] = dir;
  }
  return dirs;
}
function gitOnlyBin() {
  const bin = path.join(ownScratch('gb-'), 'bin');
  fs.mkdirSync(bin, { recursive: true });
  const g = spawnSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).stdout.trim();
  fs.writeFileSync(path.join(bin, 'git'), `#!/bin/sh\nexec "${g}" "$@"\n`, { mode: 0o755 });
  return bin;
}
function runPwsh(mode, launcher, tokens, { cwd, env }) {
  const base = ['-NoProfile', '-NonInteractive'];
  const args = mode === 'file' ? [...base, '-File', launcher, ...tokens] : [...base, '-Command', `& '${launcher}' ${tokens.join(' ')}; exit $LASTEXITCODE`];
  return spawnSync(PWSH, args, { cwd, encoding: 'utf8', env: pwshEnv(null, env) });
}
const normalize = (s, pairs) => pairs.reduce((t, [from, to]) => t.split(from).join(to), s)
  .replace(/[0-9a-f]{40}/g, '<SHA>').replace(/(Commit: +)[0-9a-f]{7,}/g, '$1<SHORT>');
const hasPwsh = () => {
  if (PWSH) return true;
  assert.ok(!process.env.CI, 'TEST-4027: pwsh is required on CI but is not on PATH');
  console.log('SKIP-CASE: TEST-4027 needs pwsh, which is not installed here');
  return false;
};
function measure(kind, mode, id, tokens, opts, dirs, bin) {
  const cwd = matrixRepo(opts.repo ?? 'repo');
  const pathVar = opts.nonode ? gitOnlyBin() : `${bin}${path.delimiter}${process.env.PATH}`;
  const r = runPwsh(mode, path.join(dirs[kind], 'aai-release.ps1'), tokens, { cwd, env: MATRIX_ENV({ ...(opts.env ?? {}), PATH: pathVar }) });
  const pairs = [[dirs[kind], '<L>'], [cwd, '<R>'], [path.dirname(cwd), '<RP>']];
  return { code: r.status, out: normalize(r.stdout ?? '', pairs), err: normalize(r.stderr ?? '', pairs) };
}

test('TEST-4027 the frozen launcher reference is hash-verified and D-RELEASE-MATRIX M01 to M16, M17, M19 and M21 to M26 give identical results old and new, by -File and in session', () => {
  if (!hasPwsh()) return;
  const dirs = launcherDirs();
  const { bin, log } = stubBin();
  const diffs = [];
  const seen = [];
  for (const [id, tokens, opts = {}] of MATRIX) {
    let newFile = null;
    for (const mode of ['file', 'session']) {
      const o = measure('old', mode, id, tokens, opts, dirs, bin);
      const n = measure('new', mode, id, tokens, opts, dirs, bin);
      if (mode === 'file') newFile = n;
      const known = MEASURED_BARE_WORD[`${id} ${mode}`];
      if (known) {
        // A measured case of DR-R3 (the old binder takes a bare word by position): the old value and the new one are both pinned.
        seen.push(`${id} ${mode}`);
        if (!known.old(o) || JSON.stringify(n) !== JSON.stringify(known.new(newFile))) diffs.push(`${id} ${mode} (measured bare word): old=${JSON.stringify(o)} new=${JSON.stringify(n)}`);
      } else if (o.code !== n.code || o.out !== n.out || o.err !== n.err) diffs.push(`${id} ${mode}: old=${JSON.stringify(o)} new=${JSON.stringify(n)}`);
    }
  }
  assert.deepEqual(seen.sort(), Object.keys(MEASURED_BARE_WORD).sort(), 'every measured bare-word case was observed');
  assert.deepEqual(diffs, [], diffs.join('\n'));
  assert.equal(log('gh') + log('az'), '', 'no hosting platform call');
});

test('TEST-4027 M08 and M09 really cut the local release branch and M16 names the missing node with exit 20 (negative controls on the matrix)', () => {
  if (!hasPwsh()) return;
  const dirs = launcherDirs();
  const { bin } = stubBin();
  const cut = measure('new', 'file', 'M08', ['-Confirm', '-NoRemote', '-Version', 'v9'], {}, dirs, bin);
  assert.equal(cut.code, 0, cut.err);
  assert.ok(cut.out.includes('cut complete'), cut.out);
  const nonode = measure('new', 'file', 'M16', ['-DryRun'], { nonode: true }, dirs, bin);
  assert.deepEqual([nonode.code, nonode.out, nonode.err.trim()], [20, '', MISSING_NODE]);
  const outside = measure('new', 'session', 'M12', ['-DryRun'], { repo: 'none' }, dirs, bin);
  assert.equal(outside.code, 10, outside.err);
  const nolog = measure('new', 'session', 'M13', ['-DryRun'], { repo: 'nochangelog' }, dirs, bin);
  assert.equal(nolog.code, 11, nolog.err);
});

test('TEST-4027 M18 and M20 give the New column of DR-R2 and DR-R4 under the new launcher, by -File and in session', () => {
  if (!hasPwsh()) return;
  const dirs = launcherDirs();
  const { bin } = stubBin();
  for (const [id, tokens, code, errLines] of DR) {
    for (const mode of ['file', 'session']) {
      const n = measure('new', mode, id, tokens, {}, dirs, bin);
      assert.deepEqual([n.code, n.out, n.err.split(/\r?\n/).filter((l) => l !== '')], [code, '', errLines], `${id} ${mode}`);
    }
  }
});

// TEST-4168 (ci-flake-root-causes Spec-AC-02, validation round 1): the REAL git spawn reports the signal that killed
// the git child. The child kills only itself, so node's own handler never runs and the child's signal alone decides.
for (const [sig, exit] of [['SIGINT', 130], ['SIGTERM', 143], ['SIGKILL', 20]]) {
  test(`TEST-4168 a real git child killed by ${sig} alone (node not signalled) ends the local cut with exit ${exit}`, () => {
    const dir = fixture();
    const bin = path.join(scratch('self'), 'bin');
    fs.mkdirSync(bin, { recursive: true });
    const real = spawnSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).stdout.trim();
    fs.writeFileSync(path.join(bin, 'git'), `#!/bin/sh\ncase " $* " in *" commit "*) kill -${sig.slice(3)} $$;; esac\nexec "${real}" "$@"\n`, { mode: 0o755 });
    const r = spawnSync(process.execPath, [MODULE, '--launcher', 'sh', '--confirm', '--no-remote', '--version', 'v9'], {
      cwd: dir, encoding: 'utf8', env: HOST_FREE({ PATH: `${bin}${path.delimiter}${process.env.PATH}` }),
    });
    assert.equal(r.status, exit, `${r.stdout}${r.stderr}`);
    if (exit !== 20) assert.equal(r.stderr, `REFUSED: interrupted (${sig}) — the temporary worktree was removed.\n`);
    else assert.match(r.stderr, /^REFUSED: git-command — git commit /);
    assert.equal(git(dir, 'worktree', 'list').trim().split('\n').length, 1, 'git worktree list shows only the main tree');
  });
}
