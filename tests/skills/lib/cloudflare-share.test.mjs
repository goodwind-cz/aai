// cloudflare-share.test.mjs - node:test cases for .aai/scripts/cloudflare-share.mjs
// (docs/specs/SPEC-DRAFT-cloudflare-share-on-node.md, TEST-3416 to TEST-3421 and DR-20 of TEST-3423).
// Every case works in a fresh temp directory with a recording fake or a stub wrangler on PATH; no case
// runs a real wrangler or reaches the network, and no case prints an environment value.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
// The module may not exist yet (RED on the baseline): every case must fail on its own assertion.
const M = await import('../../../.aai/scripts/cloudflare-share.mjs').catch(() => ({}));

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../..');
const MODULE = path.join(ROOT, '.aai/scripts/cloudflare-share.mjs');
const SH_LAUNCHER = path.join(ROOT, '.aai/scripts/cloudflare-share.sh');
const URL1 = 'https://abc123.my-repo.aai-reports.pages.dev';
const USAGE = 'Usage: cloudflare-share <document.md>';
const REFUSED = 'cloudflare-share: refused - node not found in PATH or cloudflare-share.mjs missing; nothing was published. Install Node.js 22 or later (https://nodejs.org/) and re-run.';
const TMP = [];
after(() => { for (const d of TMP) fs.rmSync(d, { recursive: true, force: true }); });

const scratch = (label) => {
  const d = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), `aai-cfs-${label}-`)));
  TMP.push(d);
  return d;
};
// run: asserts the export first so a missing module fails on an assertion, not on a TypeError.
const run = (opts, deps) => {
  assert.equal(typeof M.run, 'function', 'cloudflare-share.mjs must export run');
  return M.run(opts, deps);
};
const git = (cwd, ...args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
};

// stubScript <body lines>: an executable POSIX wrangler stub that records its argv next to itself.
function stub(bin, lines) {
  fs.mkdirSync(bin, { recursive: true });
  const body = ['#!/bin/sh', 'printf \'%s\\n\' "$@" > "$(dirname "$0")/argv.txt"', ...lines].join('\n') + '\n';
  const p = path.join(bin, 'wrangler');
  fs.writeFileSync(p, body, { mode: 0o755 });
  fs.chmodSync(p, 0o755);
  return p;
}
const OK_STUB = [`echo " Deployment complete! Take a peek over at"`, `echo " ${URL1}"`];

// fx: a fresh project directory (default name "My Repo") with doc.md, plus a bin dir for stubs.
function fx({ label = 'My Repo', stubLines = OK_STUB, repo = false } = {}) {
  const root = scratch('fx');
  const cwd = path.join(root, label);
  const bin = path.join(root, 'bin');
  fs.mkdirSync(cwd, { recursive: true });
  fs.mkdirSync(bin, { recursive: true });
  fs.writeFileSync(path.join(cwd, 'doc.md'), '# Title\n\nbody\n');
  if (stubLines) stub(bin, stubLines);
  if (repo) {
    git(cwd, 'init', '-q');
    git(cwd, 'config', 'user.email', 'fixture@example.invalid');
    git(cwd, 'config', 'user.name', 'fixture');
    git(cwd, 'config', 'commit.gpgsign', 'false');
    git(cwd, 'add', '-A');
    git(cwd, 'commit', '-q', '-m', 'fixture');
  }
  return { root, cwd, bin };
}
const cli = (f, args, env = {}) => spawnSync(process.execPath, [MODULE, ...args], {
  cwd: f.cwd,
  encoding: 'utf8',
  env: { ...process.env, PATH: f.bin + path.delimiter + process.env.PATH, ...env },
});
// mk: run() deps with recording fakes over the real fs in the fixture directory.
function mk(f, over = {}) {
  const log = { out: [], err: [], convert: [], deploy: [] };
  const deps = {
    cwd: f.cwd,
    env: { PATH: f.bin },
    platform: process.platform,
    fs,
    convert: (doc, dir) => {
      log.convert.push([doc, dir]);
      fs.writeFileSync(path.join(f.cwd, dir, 'index.html'), '<p>x</p>');
      return { status: 0, stdout: `Converted: ${doc}\n`, stderr: '' };
    },
    deploy: (cmd, env) => { log.deploy.push({ cmd, env }); return { status: 0, stdout: `${URL1}\n`, stderr: '' }; },
    gitToplevel: () => ({ status: 0, stdout: `${f.root}/fixture\n`, stderr: '' }),
    now: () => new Date('2026-01-02T03:04:05.678Z'),
    out: (l) => log.out.push(l),
    err: (l) => log.err.push(l),
    ...over,
  };
  return { deps, log };
}
const historyPath = (f) => path.join(f.cwd, 'docs/ai/published/history.jsonl');
const records = (f) => (fs.existsSync(historyPath(f)) ? fs.readFileSync(historyPath(f), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);
const assertClean = (f) => {
  assert.equal(fs.existsSync(path.join(f.cwd, '.cloudflare-publish')), false, 'publish dir left behind');
  assert.equal(fs.existsSync(historyPath(f)), false, 'history file written');
};

// ---- TEST-3416 ----------------------------------------------------------------------------------
test('TEST-3416 importing the module has no side effect and exposes the D-MOD functions', () => {
  const cwd = scratch('imp');
  const r = spawnSync(process.execPath, ['--input-type=module', '-e', `
    const m = await import(${JSON.stringify(MODULE)});
    process.stdout.write(Object.keys(m).sort().join(','));
  `], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const names = r.stdout.split(',');
  for (const n of ['parseArgs', 'branchName', 'extractUrl', 'redact', 'historyLine', 'findWrangler', 'deployCommand', 'run']) {
    assert.ok(names.includes(n), `missing export ${n}`);
  }
  assert.deepEqual(fs.readdirSync(cwd), [], 'import wrote into the cwd');
  assert.equal(r.stderr, '');
});

test('TEST-3416 run with recording fakes converts once and deploys once with the D-MOD command', () => {
  const f = fx({ label: 'fixture' });
  const { deps, log } = mk(f);
  const rc = run({ doc: 'doc.md' }, deps);
  assert.equal(rc, 0, log.err.join('\n'));
  assert.deepEqual(log.convert, [['doc.md', '.cloudflare-publish']]);
  assert.equal(log.deploy.length, 1);
  assert.equal(typeof M.deployCommand, 'function', 'must export deployCommand');
  const want = M.deployCommand(path.join(f.bin, 'wrangler'), 'fixture', process.platform);
  assert.deepEqual(log.deploy[0].cmd, want);
  assert.equal(want.command, path.join(f.bin, 'wrangler'));
  assert.deepEqual(want.args, ['pages', 'deploy', '.cloudflare-publish', '--project-name=aai-reports', '--branch=fixture']);
  assert.equal(want.shell, false);
  assert.equal(fs.existsSync(path.join(f.cwd, '.cloudflare-publish')), false);
});

// ---- TEST-3417 ----------------------------------------------------------------------------------
test('TEST-3417 the CLI in a committed repo named My Repo meets the D-OUT contract', () => {
  const f = fx({ repo: true });
  const r = cli(f, ['doc.md']);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stderr, '');
  const want = [
    'Converting Markdown to HTML...',
    'Converted: doc.md',
    'Output: .cloudflare-publish/index.html',
    'Images: 0',
    'Deploying to Cloudflare Pages (branch: my-repo)...',
    '',
    'Document published successfully!',
    '',
    'Document: doc',
    `URL: ${URL1}`,
    '',
    `Click to open: ${URL1}`,
    '',
    '',
  ].join('\n');
  assert.equal(r.stdout, want);
  const recs = records(f);
  assert.equal(recs.length, 1);
  assert.equal(recs[0].url, URL1);
  assert.equal(fs.existsSync(path.join(f.cwd, '.cloudflare-publish')), false);
  assert.equal(fs.readFileSync(path.join(f.bin, 'argv.txt'), 'utf8'),
    'pages\ndeploy\n.cloudflare-publish\n--project-name=aai-reports\n--branch=my-repo\n');
});

// ---- TEST-3418 ----------------------------------------------------------------------------------
test('TEST-3418 DR-01 no argument prints the usage line on stderr and exits 1; -h and --help exit 0 on stdout', () => {
  assert.deepEqual(M.parseArgs?.([]), { error: USAGE });
  assert.deepEqual(M.parseArgs?.(['-h']), { help: true });
  assert.deepEqual(M.parseArgs?.(['--help']), { help: true });
  const f = fx();
  const r = cli(f, []);
  assert.equal(r.status, 1);
  assert.equal(r.stdout, '');
  assert.equal(r.stderr, `${USAGE}\n`);
  assert.deepEqual(fs.readdirSync(f.cwd), ['doc.md']);
  for (const h of ['-h', '--help']) {
    const k = cli(f, [h]);
    assert.equal(k.status, 0);
    assert.equal(k.stdout, `${USAGE}\n`);
    assert.equal(k.stderr, '');
  }
});

test('TEST-3418 DR-02 a missing document is reported on stderr with exit 1', () => {
  const f = fx();
  const { deps, log } = mk(f);
  const rc = run({ doc: 'nope.md' }, deps);
  assert.equal(rc, 1);
  assert.deepEqual(log.err, ['ERROR: Document not found: nope.md']);
  assert.deepEqual(log.out, []);
  assert.equal(log.convert.length, 0);
  assertClean(f);
});

test('TEST-3418 DR-03 a directory or wildcard is not a document; a literal name with brackets is', () => {
  const f = fx();
  fs.mkdirSync(path.join(f.cwd, 'dir.md'));
  let m = mk(f);
  assert.equal(run({ doc: 'dir.md' }, m.deps), 1);
  assert.deepEqual(m.log.err, ['ERROR: Document not found: dir.md']);
  m = mk(f);
  assert.equal(run({ doc: '*.md' }, m.deps), 1);
  assert.deepEqual(m.log.err, ['ERROR: Document not found: *.md']);
  assertClean(f);
  fs.writeFileSync(path.join(f.cwd, '[a].md'), '# x\n');
  m = mk(f);
  assert.equal(run({ doc: '[a].md' }, m.deps), 0, m.log.err.join('\n'));
  assert.ok(m.log.out.includes('Document: [a]'));
});

test('TEST-3418 DR-04 the report strips the last extension', () => {
  const f = fx();
  fs.writeFileSync(path.join(f.cwd, 'notes.markdown'), '# n\n');
  for (const [doc, name] of [['doc.md', 'doc'], ['notes.markdown', 'notes']]) {
    const m = mk(f);
    assert.equal(run({ doc }, m.deps), 0, m.log.err.join('\n'));
    assert.ok(m.log.out.includes(`Document: ${name}`), `${doc} -> ${m.log.out.join('|')}`);
  }
});

test('TEST-3418 DR-05 a failing conversion exits 1, names the code on stderr and removes the publish dir', () => {
  const f = fx();
  const m = mk(f, { convert: () => ({ status: 3, stdout: '', stderr: '' }) });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 1);
  assert.equal(m.log.err.at(-1), 'ERROR: conversion failed (share-convert.mjs exited 3)');
  assert.equal(m.log.deploy.length, 0);
  assertClean(f);
});

test('TEST-3418 DR-19 extra arguments print the usage line on stderr, exit 1 and create nothing', () => {
  assert.deepEqual(M.parseArgs?.(['a.md', 'b.md']), { error: USAGE });
  const f = fx();
  const r = cli(f, ['doc.md', 'doc.md']);
  assert.equal(r.status, 1);
  assert.equal(r.stdout, '');
  assert.equal(r.stderr, `${USAGE}\n`);
  assert.deepEqual(fs.readdirSync(f.cwd), ['doc.md']);
  assert.deepEqual(M.parseArgs?.(['-h', 'x']), { error: USAGE });
  assert.deepEqual(M.parseArgs?.(['x', '-h']), { error: USAGE });
  assert.deepEqual(M.parseArgs?.(['--help', 'x']), { error: USAGE });
  assert.deepEqual(M.parseArgs?.(['-h']), { help: true });
});

// ---- TEST-3419 ----------------------------------------------------------------------------------
test('TEST-3419 DR-06 wrangler absent from PATH: three stderr lines before conversion, nothing created', () => {
  const f = fx({ stubLines: null });
  const m = mk(f);
  assert.equal(run({ doc: 'doc.md' }, m.deps), 1);
  assert.deepEqual(m.log.err, ['ERROR: wrangler not found', 'Install: npm install -g wrangler', 'Then run: wrangler login']);
  assert.deepEqual(m.log.out, []);
  assert.equal(m.log.convert.length, 0);
  assertClean(f);
});

test('TEST-3419 DR-07 wrangler resolution over PATH and PATHEXT, and the win32 cmd plan', () => {
  const files = new Map([['C:\\tools\\wrangler.cmd', 0o644], ['/opt/a/wrangler', 0o644], ['/opt/b/wrangler', 0o755]]);
  const ffs = {
    statSync: (p) => {
      if (!files.has(p)) throw Object.assign(new Error('ENOENT'), { code: 'ENOENT' });
      return { isFile: () => true, mode: files.get(p) };
    },
  };
  assert.equal(M.findWrangler?.({ Path: 'C:\\nope;C:\\tools', PATHEXT: '.COM;.EXE;.BAT;.CMD' }, 'win32', ffs), 'C:\\tools\\wrangler.cmd');
  assert.equal(M.findWrangler?.({ PATH: '/opt/a:/opt/b' }, 'linux', ffs), '/opt/b/wrangler');
  assert.equal(M.findWrangler?.({ PATH: '/opt/a' }, 'linux', ffs), null);
  assert.equal(M.findWrangler?.({ PATH: '' }, 'linux', ffs), null);
  const cmd = M.deployCommand?.('C:\\tools\\wrangler.cmd', 'my-repo', 'win32');
  assert.deepEqual(cmd, {
    command: '"C:\\tools\\wrangler.cmd" pages deploy .cloudflare-publish --project-name=aai-reports --branch=my-repo',
    args: [],
    shell: true,
  });
  assert.equal(M.deployCommand?.('C:\\x\\wrangler.exe', 'b', 'win32')?.shell, false);
  assert.equal(M.deployCommand?.('/opt/b/wrangler', 'b', 'linux')?.shell, false);
  assert.equal(M.deployCommand?.('C:\\a"b\\wrangler.cmd', 'b', 'win32'), null);
  assert.equal(M.deployCommand?.('C:\\%x%\\wrangler.cmd', 'b', 'win32'), null);
  assert.equal(M.deployCommand?.('C:\\a!b!c\\wrangler.cmd', 'b', 'win32'), null);
  const f = fx();
  const m = mk(f, { platform: 'win32', env: { Path: 'C:\\a"b', PATHEXT: '.CMD' }, fs: { ...fs, statSync: (p, ...a) => (p === 'C:\\a"b\\wrangler.cmd' ? { isFile: () => true, mode: 0 } : fs.statSync(p, ...a)) } });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 1);
  assert.equal(m.log.err.at(-1), 'ERROR: wrangler path cannot be run safely: C:\\a"b\\wrangler.cmd');
  assert.equal(m.log.convert.length, 0);
});

test('TEST-3419 DR-08 branch outside git is the directory name; an empty name refuses', () => {
  const f = fx({ label: 'Share Dir' });
  let m = mk(f, { gitToplevel: () => ({ status: 128, stdout: '', stderr: 'fatal' }) });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 0, m.log.err.join('\n'));
  assert.deepEqual(m.log.deploy[0]?.cmd.args.at(-1), '--branch=share-dir');
  assert.ok(m.log.out.includes('Deploying to Cloudflare Pages (branch: share-dir)...'));
  const rootDir = path.parse(os.tmpdir()).root;
  const root = path.join(rootDir, 'doc.md');
  m = mk(f, {
    cwd: rootDir,
    gitToplevel: () => ({ status: 128, stdout: '', stderr: '' }),
    fs: { ...fs, statSync: (p, ...a) => (p === root ? { isFile: () => true, mode: 0o644 } : fs.statSync(p, ...a)) },
  });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 1);
  assert.match(m.log.err.at(-1), /^ERROR: /);
  assert.equal(m.log.convert.length, 0);
  assert.equal(M.branchName?.(''), '');
});

test('TEST-3419 DR-09 branch sanitising is Unicode lower case with one dash per code point', () => {
  assert.equal(M.branchName?.('Caf\u00e9'), 'caf-');
  assert.equal(M.branchName?.('My Repo_2'), 'my-repo-2');
  assert.equal(M.branchName?.('\u{1F600}'), '-');
  assert.equal(M.branchName?.('\u00c4B'), '\u002db');
  assert.equal(M.branchName?.('ok-name9'), 'ok-name9');
});

test('TEST-3419 DR-10 a non-zero wrangler status fails even with a URL; stderr output alone does not', () => {
  const f = fx();
  let m = mk(f, { deploy: () => ({ status: 3, stdout: `${URL1}\n`, stderr: '' }) });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 1);
  assert.equal(m.log.err[0], 'ERROR: Deployment failed or URL not found');
  assertClean(f);
  m = mk(f, { deploy: () => ({ status: 0, stdout: `${URL1}\n`, stderr: 'warning: something\n' }) });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 0, m.log.err.join('\n'));
  assert.deepEqual(m.log.err, []);
});

test('TEST-3419 DR-11 URL extraction is the first pages.dev match, stdout before stderr, no grep', () => {
  assert.equal(M.extractUrl?.('\u001b[36mhttps://a.b.pages.dev\u001b[0m'), 'https://a.b.pages.dev');
  assert.equal(M.extractUrl?.('x https://first.pages.dev y https://second.pages.dev'), 'https://first.pages.dev');
  assert.equal(M.extractUrl?.('nothing here https://example.com'), null);
  assert.equal(M.extractUrl?.(''), null);
  const f = fx();
  const m = mk(f, { deploy: () => ({ status: 0, stdout: 'no url\n', stderr: 'see https://only-err.pages.dev\n' }) });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 0, m.log.err.join('\n'));
  assert.ok(m.log.out.includes('URL: https://only-err.pages.dev'));
});

test('TEST-3419 DR-12 a failed deploy reports on stderr, redacted, exit 1, publish dir removed', () => {
  const f = fx();
  const m = mk(f, { deploy: () => ({ status: 0, stdout: 'no url in this output\n', stderr: 'boom detail\n' }) });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 1);
  assert.equal(m.log.err[0], 'ERROR: Deployment failed or URL not found');
  assert.ok(m.log.err.join('\n').includes('no url in this output'));
  assert.ok(m.log.err.join('\n').includes('boom detail'));
  assert.ok(!m.log.out.join('\n').includes('boom detail'));
  assertClean(f);
});

test('TEST-3419 DR-18 a deploy that cannot be spawned reports wrangler could not be run', () => {
  const f = fx();
  const m = mk(f, { deploy: () => { throw new Error('spawn exploded'); } });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 1);
  assert.equal(m.log.err.at(-1), 'ERROR: wrangler could not be run: spawn exploded');
  assertClean(f);
});

// ---- TEST-3420 ----------------------------------------------------------------------------------
test('TEST-3420 DR-13 size_kb is the apparent byte sum over 1024 rounded to two decimals', () => {
  const f = fx();
  const m = mk(f, {
    convert: (doc, dir) => {
      fs.writeFileSync(path.join(f.cwd, dir, 'index.html'), Buffer.alloc(1000, 97));
      fs.mkdirSync(path.join(f.cwd, dir, 'img'));
      fs.writeFileSync(path.join(f.cwd, dir, 'img', 'a.png'), Buffer.alloc(1300, 98));
      return { status: 0, stdout: '', stderr: '' };
    },
  });
  assert.equal(run({ doc: 'doc.md' }, m.deps), 0, m.log.err.join('\n'));
  const [rec] = records(f);
  assert.equal(rec.size_kb, 2.25);
  assert.equal(typeof rec.size_kb, 'number');
});

test('TEST-3420 DR-14 the record is JSON.stringify in the order timestamp, document, url, size_kb', () => {
  const f = fx();
  const weird = 'we"ird\\name.md';
  fs.writeFileSync(path.join(f.cwd, weird), '# w\n');
  const m = mk(f);
  assert.equal(run({ doc: weird }, m.deps), 0, m.log.err.join('\n'));
  const [rec] = records(f);
  assert.deepEqual(Object.keys(rec), ['timestamp', 'document', 'url', 'size_kb']);
  assert.equal(rec.document, weird);
  const prompt = fs.readFileSync(path.join(ROOT, '.aai/SKILL_SHARE.prompt.md'), 'utf8');
  const echo = prompt.match(/echo '(\{"timestamp".*?\})' >> docs\/ai\/published\/history\.jsonl/);
  assert.ok(echo, 'SKILL_SHARE step 4 echo line not found');
  assert.deepEqual(Object.keys(rec).slice(0, 3), Object.keys(JSON.parse(echo[1])));
  assert.equal(M.historyLine?.({ timestamp: 't', document: 'd', url: 'u', sizeKb: 1.5 }), '{"timestamp":"t","document":"d","url":"u","size_kb":1.5}');
});

test('TEST-3420 DR-15 the appended line is UTF-8 and ends with LF only', () => {
  const f = fx();
  fs.writeFileSync(path.join(f.cwd, '\u010de\u0161tina.md'), '# c\n');
  for (let i = 0; i < 2; i++) {
    const m = mk(f);
    assert.equal(run({ doc: '\u010de\u0161tina.md' }, m.deps), 0, m.log.err.join('\n'));
  }
  const buf = fs.readFileSync(historyPath(f));
  assert.ok(buf.includes(Buffer.from([0xc4, 0x8d])), 'UTF-8 bytes of the non-ASCII path missing');
  assert.equal(buf.includes(Buffer.from('\r')), false);
  assert.equal(buf.at(-1), 0x0a);
  assert.equal(buf.toString('utf8').split('\n').filter(Boolean).length, 2);
});

test('TEST-3420 DR-16 the timestamp is ISO 8601 UTC to the second with Z', () => {
  const f = fx();
  const m = mk(f);
  assert.equal(run({ doc: 'doc.md' }, m.deps), 0, m.log.err.join('\n'));
  assert.equal(records(f)[0]?.timestamp, '2026-01-02T03:04:05Z');
});

test('TEST-3420 DR-17 the output carries no ANSI escape', () => {
  const f = fx();
  const m = mk(f);
  assert.equal(run({ doc: 'doc.md' }, m.deps), 0, m.log.err.join('\n'));
  assert.ok(m.log.out.length > 5, 'no output captured');
  assert.equal(m.log.out.join('\n').includes('\u001b'), false);
  assert.equal(m.log.err.join('\n').includes('\u001b'), false);
  // the failed-deploy echo path: wrangler output carrying CSI and OSC-8 sequences
  const coloured = '\u001b[31mred boom\u001b[0m \u001b]8;;https://x.invalid\u0007link\u001b]8;;\u0007\n';
  const bad = mk(fx(), { deploy: () => ({ status: 1, stdout: coloured, stderr: '\u001b[1mbold detail\u001b[22m\n' }) });
  assert.equal(run({ doc: 'doc.md' }, bad.deps), 1);
  const all = [...bad.log.out, ...bad.log.err].join('\n');
  assert.equal(all.includes('\u001b'), false, 'an ESC byte reached the output');
  assert.ok(all.includes('red boom') && all.includes('bold detail') && all.includes('link'), 'the echoed text was lost');
});

// ---- TEST-3421 ----------------------------------------------------------------------------------
test('TEST-3421 DR-21 credentials are passed on, never printed, and redacted from a failed deploy echo', () => {
  const TOK = 'fixture-token-AAAA1111';
  const KEY = 'fixture-key-BBBB2222';
  const f = fx({ stubLines: [
    'printf \'%s\\n%s\\n\' "$CLOUDFLARE_API_TOKEN" "$CLOUDFLARE_API_KEY" > "$(dirname "$0")/envdump.txt"',
    'echo "token=$CLOUDFLARE_API_TOKEN"',
    'echo "key=$CLOUDFLARE_API_KEY" >&2',
    'exit 1',
  ] });
  const r = cli(f, ['doc.md'], { CLOUDFLARE_API_TOKEN: TOK, CLOUDFLARE_API_KEY: KEY });
  assert.equal(r.status, 1);
  assert.equal(r.stderr.split('[REDACTED]').length - 1, 2, r.stderr.replaceAll(TOK, '<T>').replaceAll(KEY, '<K>'));
  for (const v of [TOK, KEY]) {
    assert.equal(r.stderr.includes(v), false, 'a credential value reached stderr');
    assert.equal(r.stdout.includes(v), false, 'a credential value reached stdout');
  }
  assert.equal(fs.readFileSync(path.join(f.bin, 'envdump.txt'), 'utf8'), `${TOK}\n${KEY}\n`);
  const ok = fx({ stubLines: [
    'echo "token=$CLOUDFLARE_API_TOKEN"',
    'echo "key=$CLOUDFLARE_API_KEY" >&2',
    `echo " ${URL1}"`,
  ] });
  const s = cli(ok, ['doc.md'], { CLOUDFLARE_API_TOKEN: TOK, CLOUDFLARE_API_KEY: KEY });
  assert.equal(s.status, 0, s.stderr);
  for (const v of [TOK, KEY]) {
    assert.equal(s.stderr.includes(v), false, 'a credential value reached stderr on success');
    assert.equal(s.stdout.includes(v), false, 'a credential value reached stdout on success');
  }
  assert.ok(s.stdout.includes(`URL: ${URL1}`));
  const envOf = (name, value) => Object.fromEntries([[name, value]]);
  assert.equal(M.redact?.('a 1234567 b', envOf('CLOUDFLARE_API_TOKEN', '1234567')), 'a 1234567 b');
  assert.equal(M.redact?.('a 12345678 b', envOf('CLOUDFLARE_API_KEY', '12345678')), 'a [REDACTED] b');
});

// ---- TEST-3423 (DR-20) --------------------------------------------------------------------------
test('TEST-3423 DR-20 the sh launcher without node prints the refusal on stderr and creates nothing', () => {
  const f = fx();
  const lean = path.join(f.root, 'lean-bin');
  fs.mkdirSync(lean);
  const which = (n) => spawnSync('sh', ['-c', `command -v ${n}`], { encoding: 'utf8' }).stdout.trim();
  fs.symlinkSync(which('dirname'), path.join(lean, 'dirname'));
  fs.copyFileSync(path.join(f.bin, 'wrangler'), path.join(lean, 'wrangler'));
  fs.chmodSync(path.join(lean, 'wrangler'), 0o755);
  const r = spawnSync('/bin/sh', [SH_LAUNCHER, 'doc.md'], { cwd: f.cwd, encoding: 'utf8', env: { PATH: lean } });
  assert.equal(r.status, 1);
  assert.equal(r.stdout, '');
  assert.equal(r.stderr, `${REFUSED}\n`);
  assertClean(f);
});
