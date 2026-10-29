import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const gate = path.join(root, '.aai/scripts/release-notes-gate.mjs');
const finish = path.join(root, '.aai/scripts/release-finish.mjs');
const {isShipped} = await import(pathToFileURL(gate).href);

const SHIPPED_DOCS = ['README.md', 'AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md', 'SKILLS.md',
  'docs/USER_GUIDE.md', 'docs/product/x.md'];
const INTERNAL_DOCS = ['docs/specs/x.md', 'docs/issues/x.md', 'docs/rfc/x.md', 'docs/analysis/x.md',
  'docs/ai/x.md', 'docs/knowledge/x.md', 'docs/decisions/x.md', 'docs/INDEX.md', 'docs/README.md'];

function run(exe, args, cwd) {
  const env = {...process.env, AAI_GIT_WRITE: '1'};
  delete env.NODE_TEST_CONTEXT;
  for (const k of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE']) delete env[k];
  return spawnSync(exe, args, {cwd, encoding: 'utf8', env, timeout: 120000});
}
function git(dir, ...args) {
  const r = run('git', args, dir);
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}
function repo(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-notes-docs-'));
  git(dir, 'init', '-q', '-b', 'main');
  git(dir, 'config', 'user.name', 'notes-docs-fixture');
  git(dir, 'config', 'user.email', 'notes-docs@example.invalid');
  git(dir, 'config', 'core.hooksPath', '/dev/null');
  put(dir, 'CHANGELOG.md', '# Changelog\n\n## [unreleased]\n');
  for (const f of files) put(dir, f, 'old\n');
  git(dir, 'add', '-A');
  git(dir, 'commit', '-qm', 'initial');
  return dir;
}
function put(dir, rel, text) {
  fs.mkdirSync(path.dirname(path.join(dir, rel)), {recursive: true});
  fs.writeFileSync(path.join(dir, rel), text);
}
// Run the gate staged and over the committed range; return both results.
function gateBoth(dir, body) {
  const bodyFile = path.join(dir, '..', `${path.basename(dir)}.body`);
  fs.writeFileSync(bodyFile, body);
  const out = [];
  const base = git(dir, 'rev-parse', 'HEAD');
  const staged = run(process.execPath, [gate, '--staged', '--body-file', bodyFile], dir);
  out.push(staged);
  git(dir, 'commit', '-qm', 'change');
  out.push(run(process.execPath, [gate, '--base', base, '--head', 'HEAD', '--body-file', bodyFile], dir));
  fs.rmSync(bodyFile, {force: true});
  return out;
}

test('TEST-2706 each shipped documentation path alone needs a note or a no-notes reason', () => {
  for (const rel of SHIPPED_DOCS) {
    const dirs = [];
    try {
      // refused: only the doc changes, empty body
      let dir = repo([rel]); dirs.push(dir);
      put(dir, rel, 'new\n'); git(dir, 'add', '-A');
      for (const r of gateBoth(dir, 'Summary\n')) {
        assert.equal(r.status, 1, `${rel}: ${r.stdout}${r.stderr}`);
        assert.match(r.stderr, /^REFUSED: release-notes /, rel);
        assert.ok(r.stderr.includes(rel), `${rel} not named: ${r.stderr}`);
      }
      // passes with a new unreleased entry
      dir = repo([rel]); dirs.push(dir);
      put(dir, rel, 'new\n');
      fs.appendFileSync(path.join(dir, 'CHANGELOG.md'), '\n## [unreleased] — docs: change ' + rel + '\n\n- A user-facing change.\n');
      git(dir, 'add', '-A');
      for (const r of gateBoth(dir, 'Summary\n')) {
        assert.equal(r.status, 0, `${rel}: ${r.stdout}${r.stderr}`);
        assert.match(r.stdout, /newly added unreleased entry/, rel);
      }
      // passes with a no-notes reason
      dir = repo([rel]); dirs.push(dir);
      put(dir, rel, 'new\n'); git(dir, 'add', '-A');
      for (const r of gateBoth(dir, 'no-notes: typo fix needs no operator action\n')) {
        assert.equal(r.status, 0, `${rel}: ${r.stdout}${r.stderr}`);
        assert.match(r.stdout, /explicit no-notes reason/, rel);
      }
    } finally {
      for (const d of dirs) fs.rmSync(d, {recursive: true, force: true});
    }
  }
});

test('TEST-2707 internal docs stay exempt and near-miss paths are not shipped', () => {
  const dir = repo(INTERNAL_DOCS);
  try {
    for (const rel of INTERNAL_DOCS) put(dir, rel, 'new\n');
    git(dir, 'add', '-A');
    for (const r of gateBoth(dir, 'Summary\n')) {
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.match(r.stdout, /^PASS: release-notes exempt/);
    }
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
  for (const rel of ['docs/product-notes.md', 'sub/README.md', 'tests/README.md', 'docs/README.md',
    'CHANGELOG.md', 'docs/USER_GUIDE.md.bak', 'docs/ai/x.md', 'readme.md']) {
    assert.equal(isShipped(rel, '100644'), false, rel);
  }
  for (const rel of SHIPPED_DOCS) assert.equal(isShipped(rel, '100644'), true, rel);
});

test('TEST-2708 every file aai-sync installs from the source root is classified shipped', () => {
  const sh = fs.readFileSync(path.join(root, '.aai/scripts/aai-sync.sh'), 'utf8');
  const ps = fs.readFileSync(path.join(root, '.aai/scripts/aai-sync.ps1'), 'utf8');
  const shList = /^for f in ([^;\n]*\bAGENTS\.md[^;\n]*); do$/m.exec(sh);
  const psList = /foreach \(\$f in @\(([^)\n]*"AGENTS\.md"[^)\n]*)\)\)/.exec(ps);
  assert.ok(shList, 'root shim loop not found in aai-sync.sh');
  assert.ok(psList, 'root shim loop not found in aai-sync.ps1');
  const names = new Set([...shList[1].trim().split(/\s+/), ...[...psList[1].matchAll(/"([^"]+)"/g)].map(m => m[1]), 'README.md']);
  assert.ok(names.size >= 6, [...names].join(','));
  for (const name of names) assert.equal(isShipped(name, '100644'), true, `${name} is installed by aai-sync but not shipped`);
});

test('TEST-2709 release history audit names an unnoted product page and accepts a noted guide change', () => {
  const dir = repo(['docs/USER_GUIDE.md', 'docs/product/x.md']);
  try {
    git(dir, 'tag', 'v1');
    put(dir, 'docs/USER_GUIDE.md', 'new\n');
    fs.appendFileSync(path.join(dir, 'CHANGELOG.md'), '\n## [unreleased] — docs: new section about guides\n\n- Guide gained a section.\n');
    git(dir, 'add', '-A'); git(dir, 'commit', '-qm', 'docs: change the guide (#101)');
    put(dir, 'docs/product/x.md', 'new\n');
    git(dir, 'add', '-A'); git(dir, 'commit', '-qm', 'docs: change a product page (#102)');
    const rolled = path.join(dir, '..', `${path.basename(dir)}.notes`);
    fs.writeFileSync(rolled, '## [unreleased] — docs: new section about guides\n\n- Guide gained a section.\n');
    const withNotes = run(process.execPath, [finish, '--root', dir, '--audit', rolled], dir);
    assert.equal(withNotes.status, 0, withNotes.stderr);
    assert.ok(withNotes.stdout.includes('#102'), withNotes.stdout);
    assert.ok(!withNotes.stdout.includes('#101'), withNotes.stdout);
    // without the rolled entry the guide change is named as well: the classifier, not the notes, decides
    fs.writeFileSync(rolled, 'nothing relevant\n');
    const bare = run(process.execPath, [finish, '--root', dir, '--audit', rolled], dir);
    assert.equal(bare.status, 0, bare.stderr);
    assert.ok(bare.stdout.includes('#101') && bare.stdout.includes('#102'), bare.stdout);
    fs.rmSync(rolled, {force: true});
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});

test('TEST-2710 the CHANGELOG preamble and the product page name all eight paths', () => {
  const changelog = fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf8');
  const preamble = changelog.slice(0, changelog.search(/^## /m));
  const page = fs.readFileSync(path.join(root, 'docs/product/release-notes-gate.md'), 'utf8');
  const names = ['README.md', 'AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md', 'SKILLS.md',
    'docs/USER_GUIDE.md', 'docs/product/'];
  for (const name of names) {
    assert.ok(preamble.includes(name), `CHANGELOG preamble lacks ${name}`);
    assert.ok(page.includes(name), `release-notes-gate.md lacks ${name}`);
  }
  assert.match(preamble, /other docs paths stay exempt/i);
  assert.match(page, /other docs paths stay exempt/i);
  assert.ok(!/Documentation, tests, and evidence-only changes are exempt/.test(page), 'old wholesale exemption remains');
  const finishPage = fs.readFileSync(path.join(root, 'docs/product/release-command-finish.md'), 'utf8');
  assert.match(finishPage, /superseded cancelled (workflow )?run/i);
  // The release dry-run rehearses this test on a rolled CHANGELOG, where
  // `[unreleased]` has become the version label; accept either heading.
  const heading = /^## \[(?:unreleased|v[^\]]+)\] — fix: .*watch-ci-cancelled-runs-and-release-gate-docs/m;
  assert.match(changelog, heading);
  const entry = changelog.split(/^## /m).find(s => /^\[(?:unreleased|v[^\]]+)\] — fix: /.test(s) && s.includes('watch-ci-cancelled-runs-and-release-gate-docs')) || '';
  assert.match(entry, /watch-ci/);
  assert.match(entry, /release[- ]notes gate/i);
});
