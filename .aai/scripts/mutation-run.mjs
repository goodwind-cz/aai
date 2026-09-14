#!/usr/bin/env node
// mutation-run.mjs — produce a v1 mutation record for one Test Plan row by
// actually mutating the code and watching the test go RED (SPEC-DRAFT
// spec-mutation-gate-for-tests D1, D3, D4, D5, D6, D7, D14).
//
// A test is admitted only with the mutation that reddens it: this tool is
// the thing that reddens it, on a real isolated clone of the tree the
// implementer is actually working in (D4), never on HEAD alone (a TDD ride's
// tree is DIRTY — the new test and the fix both exist uncommitted).
//
// USAGE
//   node .aai/scripts/mutation-run.mjs \
//     --spec <path> --test-id <TEST-nnn> --suite <repo-relative path> \
//     --selector <test_* function name> --target <repo-relative path> \
//     (--sed '<s/pat/repl/[flags]>' | --patch <unified-diff file>)
//
//   node .aai/scripts/mutation-run.mjs --replay --spec <path>
//
//   node .aai/scripts/mutation-run.mjs --help
//
// EXIT CONTRACT
//   Normal run:
//     0  RED verdict recorded — the test failed for the mutation, evidence
//     2  usage error, OR a named refusal (D3: --selector not defined by the
//        suite; D5: the mutation left --target byte-identical) — no record
//        written, no clone left behind
//     3  the clone's tree hash did not match the source working tree's (D4
//        step 4) — no record written, no clone left behind
//     5  STAYED GREEN — the mutated run exited 0; recorded, non-zero exit
//     6  INCONCLUSIVE — the mutated run exited non-zero but named no FAIL
//        line for the selected test; recorded, non-zero exit
//   --replay:
//     0  every live record for the spec still reddens
//     1  one or more records failed to replay (STAYED GREEN, INCONCLUSIVE,
//        malformed record, or the record's target no longer exists)
//     2  usage error
//
// Node stdlib only (docs/TECHNOLOGY.md). Never invokes a shell: every
// external command runs via execFileSync/spawnSync with an argv array, so a
// mutation expression containing shell metacharacters is passed through
// literally rather than re-interpreted (Implementation plan "Edge cases").

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { exit, runMain, ExitSignal } from './lib/cli-pipe-guard.mjs';
import { parseFrontmatter } from './lib/docs-model.mjs';
import {
  formatRecord,
  parseRecord,
  lastLines,
  recordFileName,
  rotatedFileName,
  isRotatedFileName,
} from './lib/mutation-record.mjs';

const ROOT = process.cwd();
const TAIL_LINES = 200;

function usageError(msg) {
  process.stderr.write(`mutation-run: ${msg}\n`);
  process.stderr.write(
    'usage: node .aai/scripts/mutation-run.mjs --spec <path> --test-id <TEST-nnn> ' +
      '--suite <path> --selector <name> --target <path> (--sed <expr> | --patch <file>)\n' +
      '   or: node .aai/scripts/mutation-run.mjs --replay --spec <path>\n'
  );
  exit(2);
}

function parseArgs(argv) {
  const out = { replay: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '--help':
      case '-h':
        out.help = true;
        break;
      case '--replay':
        out.replay = true;
        break;
      case '--spec':
        out.spec = argv[++i];
        break;
      case '--test-id':
        out.testId = argv[++i];
        break;
      case '--suite':
        out.suite = argv[++i];
        break;
      case '--selector':
        out.selector = argv[++i];
        break;
      case '--target':
        out.target = argv[++i];
        break;
      case '--sed':
        out.sed = argv[++i];
        break;
      case '--patch':
        out.patch = argv[++i];
        break;
      default:
        usageError(`unrecognized argument: ${a}`);
    }
  }
  return out;
}

function printHelp() {
  process.stdout.write(
    'mutation-run.mjs — produce a v1 mutation record for one Test Plan row\n\n' +
      'usage:\n' +
      '  node .aai/scripts/mutation-run.mjs --spec <path> --test-id <TEST-nnn> \\\n' +
      '    --suite <repo-relative path> --selector <test_* fn> --target <repo-relative path> \\\n' +
      '    (--sed \'<s/pat/repl/[flags]>\' | --patch <unified-diff file>)\n\n' +
      '  node .aai/scripts/mutation-run.mjs --replay --spec <path>\n'
  );
  exit(0);
}

// --- small utilities --------------------------------------------------------

function readSpecId(specPath) {
  let content;
  try {
    content = fs.readFileSync(specPath, 'utf8');
  } catch (err) {
    usageError(`cannot read --spec ${specPath} (${err.message})`);
  }
  const fm = parseFrontmatter(content);
  if (!fm || !fm.id) usageError(`--spec ${specPath} has no frontmatter "id:" field`);
  return fm.id;
}

function nowUtcSeconds() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

// git ls-files (tracked) + git ls-files --others --exclude-standard
// (untracked, not ignored), EXCLUDING docs/ai/tdd/** on both sides (D4 step
// 4, D7): the evidence this tool is about to write must never be able to
// change the verdict it is about to record.
function listTreeFiles(dir) {
  const tracked = execFileSync('git', ['-C', dir, 'ls-files'], { encoding: 'utf8' });
  const untracked = execFileSync('git', ['-C', dir, 'ls-files', '--others', '--exclude-standard'], { encoding: 'utf8' });
  const all = new Set();
  for (const raw of [tracked, untracked]) {
    for (const line of raw.split('\n')) {
      const p = line.trim();
      if (!p) continue;
      if (p === 'docs/ai/tdd' || p.startsWith('docs/ai/tdd/')) continue;
      all.add(p);
    }
  }
  return [...all].sort();
}

// A tree hash over PATH + CONTENT for every file listTreeFiles returns, so it
// is comparable between two independent working trees (the source and the
// clone) without either being a git object store of the other.
function computeTreeHash(dir) {
  const files = listTreeFiles(dir);
  const h = createHash('sha256');
  for (const rel of files) {
    let bytes;
    try {
      bytes = fs.readFileSync(path.join(dir, rel));
    } catch {
      continue; // a symlink to nowhere, or a race — never fatal to the hash
    }
    const fileHash = createHash('sha256').update(bytes).digest('hex');
    h.update(`${rel}\0${fileHash}\n`);
  }
  return h.digest('hex');
}

function levenshtein(a, b) {
  const m = a.length, n = b.length;
  const d = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
  for (let j = 0; j <= n; j++) d[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      d[i][j] = a[i - 1] === b[j - 1]
        ? d[i - 1][j - 1]
        : 1 + Math.min(d[i - 1][j - 1], d[i - 1][j], d[i][j - 1]);
    }
  }
  return d[m][n];
}

function nearestSelectors(name, candidates, n) {
  return [...candidates]
    .sort((a, b) => levenshtein(name, a) - levenshtein(name, b))
    .slice(0, n);
}

// The SAME grammar check-test-registration.mjs uses (D3): a suite's own
// defined test_* functions, extracted without executing the suite.
function extractSelectors(suiteContent) {
  return [...suiteContent.matchAll(/^(test_[A-Za-z0-9_]+)\(\)\s*\{/gm)].map((m) => m[1]);
}

// A minimal, dependency-free s/pattern/replacement/flags applier (single
// delimiter '/', backslash-escaped delimiters honored). Sufficient for the
// mutation expressions this ride's own Test Plan rows use; unsupported syntax
// throws rather than silently no-op-ing.
function applySedExpr(expr, content) {
  const m = /^s\/((?:\\.|[^\\/])*)\/((?:\\.|[^\\/])*)\/([a-z]*)$/.exec(expr);
  if (!m) throw new Error(`unsupported --sed expression (want s/pattern/replacement/[flags]): ${expr}`);
  const [, patSrc, replSrc, flags] = m;
  const pattern = patSrc.replace(/\\\//g, '/');
  const replacement = replSrc.replace(/\\\//g, '/');
  const re = new RegExp(pattern, flags.includes('g') ? 'g' : '');
  return content.replace(re, replacement);
}

function applyMutation({ sed, patch }, cloneDir, targetRel) {
  const targetAbs = path.join(cloneDir, targetRel);
  const before = fs.readFileSync(targetAbs, 'utf8');
  let after;
  if (sed) {
    after = applySedExpr(sed, before);
  } else {
    // --patch <file>: applied via `git apply` inside the clone (the clone is
    // its own git checkout), argv-only, no shell.
    const patchAbs = path.isAbsolute(patch) ? patch : path.join(ROOT, patch);
    execFileSync('git', ['-C', cloneDir, 'apply', patchAbs], { stdio: ['ignore', 'pipe', 'pipe'] });
    after = fs.readFileSync(targetAbs, 'utf8');
  }
  fs.writeFileSync(targetAbs, after);
  return { before, after };
}

function mutationDescription({ sed, patch }) {
  return sed ? `sed:${sed}` : `patch:${patch}`;
}

// Builds an isolated clone of the CURRENT working tree (committed history +
// tracked modifications + untracked-not-ignored files), proved by a tree
// hash (D4). Returns { cloneDir, baseCommit, sourceTreeHash } or throws a
// TreeMismatch marker error the caller turns into the exit-3 refusal.
class TreeMismatchError extends Error {}

function buildIsolatedClone() {
  const baseCommit = execFileSync('git', ['-C', ROOT, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  const sourceTreeHash = computeTreeHash(ROOT);

  const tmpBase = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-mutation-'));
  const cloneDir = path.join(tmpBase, 'clone');
  execFileSync('git', ['clone', '--local', '--no-hardlinks', ROOT, cloneDir], { stdio: ['ignore', 'pipe', 'pipe'] });
  execFileSync('git', ['-C', cloneDir, 'checkout', '--quiet', baseCommit], { stdio: ['ignore', 'pipe', 'pipe'] });

  // Reproduce tracked modifications.
  const diff = execFileSync('git', ['-C', ROOT, 'diff', 'HEAD'], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (diff.trim()) {
    const res = spawnSync('git', ['-C', cloneDir, 'apply'], { input: diff, encoding: 'utf8' });
    if (res.status !== 0) {
      fs.rmSync(tmpBase, { recursive: true, force: true });
      throw new Error(`mutation-run: failed to reproduce tracked modifications in the clone: ${res.stderr || res.stdout}`);
    }
  }

  // Reproduce untracked-not-ignored files.
  const untracked = execFileSync('git', ['-C', ROOT, 'ls-files', '--others', '--exclude-standard'], { encoding: 'utf8' });
  for (const rel of untracked.split('\n')) {
    const p = rel.trim();
    if (!p) continue;
    if (p === 'docs/ai/tdd' || p.startsWith('docs/ai/tdd/')) continue;
    const src = path.join(ROOT, p);
    const dst = path.join(cloneDir, p);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst);
  }

  const cloneTreeHash = computeTreeHash(cloneDir);
  if (cloneTreeHash !== sourceTreeHash) {
    fs.rmSync(tmpBase, { recursive: true, force: true });
    throw new TreeMismatchError(
      `mutation-run: clone tree hash (${cloneTreeHash}) does not match the source working tree's (${sourceTreeHash}) — the clone does not reproduce your tree`
    );
  }

  return { tmpBase, cloneDir, baseCommit, sourceTreeHash };
}

// Runs the suite exactly as a human would: through aai-run-tests.sh, inside
// the clone (D1). Returns { rc, output }.
function runSuite(cloneDir, suiteRel, selector) {
  const wrapper = path.join(cloneDir, '.aai/scripts/aai-run-tests.sh');
  const env = { ...process.env };
  delete env.AAI_ROLE; // a marker exported into this CLI's own env must not leak into the suite run
  const res = spawnSync('bash', [wrapper, 'bash', suiteRel, selector], {
    cwd: cloneDir,
    encoding: 'utf8',
    env,
    maxBuffer: 256 * 1024 * 1024,
  });
  const output = `${res.stdout || ''}${res.stderr || ''}`;
  return { rc: res.status == null ? 124 : res.status, output };
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// D6: classify the mutated run three ways, never two.
function classifyVerdict(rc, output, testId) {
  if (rc === 0) return { verdict: 'STAYED GREEN', firstFail: '(none — the mutated run exited 0)' };
  const failRe = new RegExp(`^.*FAIL.*\\b${escapeRegExp(testId)}\\b.*$`, 'm');
  const m = failRe.exec(output);
  if (m) return { verdict: 'RED', firstFail: m[0].trim().slice(0, 400) };
  return {
    verdict: 'INCONCLUSIVE',
    firstFail: `(no FAIL line naming ${testId} — the suite exited ${rc} for another reason)`,
  };
}

function evidenceDir(specId) {
  return path.join(ROOT, 'docs', 'ai', 'tdd', specId);
}

// D2: never delete, never overwrite — rotate any existing live record aside
// under its OWN run_at_utc before writing the new one.
function rotateExisting(dir, testId) {
  const live = path.join(dir, recordFileName(testId));
  if (!fs.existsSync(live)) return;
  const prevText = fs.readFileSync(live, 'utf8');
  const parsed = parseRecord(prevText);
  const stamp = parsed.ok ? parsed.fields.run_at_utc : `unknown-${Date.now()}`;
  const rotated = path.join(dir, rotatedFileName(testId, stamp));
  fs.renameSync(live, rotated);
}

function writeRecord(specId, testId, fields, tailText) {
  const dir = evidenceDir(specId);
  fs.mkdirSync(dir, { recursive: true });
  rotateExisting(dir, testId);
  const text = formatRecord(fields, tailText);
  fs.writeFileSync(path.join(dir, recordFileName(testId)), text);
  return path.join(dir, recordFileName(testId));
}

// --- normal run --------------------------------------------------------

function runOne(args) {
  for (const req of ['spec', 'testId', 'suite', 'selector', 'target']) {
    if (!args[req]) usageError(`missing required --${req.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`);
  }
  if (!args.sed && !args.patch) usageError('exactly one of --sed or --patch is required');
  if (args.sed && args.patch) usageError('--sed and --patch are mutually exclusive');
  if (!/^TEST-\d+$/.test(args.testId)) usageError(`--test-id must look like TEST-<n> (got ${args.testId})`);

  const specPath = path.isAbsolute(args.spec) ? args.spec : path.join(ROOT, args.spec);
  if (!fs.existsSync(specPath)) usageError(`--spec not found: ${args.spec}`);
  const specId = readSpecId(specPath);

  const suiteAbs = path.join(ROOT, args.suite);
  if (!fs.existsSync(suiteAbs)) usageError(`--suite not found: ${args.suite}`);
  const suiteContent = fs.readFileSync(suiteAbs, 'utf8');
  const selectors = extractSelectors(suiteContent);
  if (!selectors.includes(args.selector)) {
    const nearest = nearestSelectors(args.selector, selectors, 3);
    process.stderr.write(
      `mutation-run: unknown selector "${args.selector}" in ${args.suite} — nearest existing selectors: ${nearest.join(', ')}\n`
    );
    exit(2);
  }

  const targetAbs = path.join(ROOT, args.target);
  if (!fs.existsSync(targetAbs)) usageError(`--target not found: ${args.target}`);

  let clone;
  try {
    clone = buildIsolatedClone();
  } catch (err) {
    if (err instanceof TreeMismatchError) {
      process.stderr.write(`${err.message}\n`);
      exit(3);
    }
    throw err;
  }

  try {
    let before, after;
    try {
      ({ before, after } = applyMutation(args, clone.cloneDir, args.target));
    } catch (err) {
      if (err instanceof ExitSignal) throw err;
      process.stderr.write(`mutation-run: could not apply mutation "${mutationDescription(args)}" to ${args.target}: ${err.message}\n`);
      exit(2);
    }
    if (before === after) {
      process.stderr.write(
        `mutation-run: mutation "${mutationDescription(args)}" left ${args.target} byte-identical — refusing to record a false result\n`
      );
      exit(2);
    }

    const { rc, output } = runSuite(clone.cloneDir, args.suite, args.selector);
    const { verdict, firstFail } = classifyVerdict(rc, output, args.testId);

    const fields = {
      spec_id: specId,
      test_id: args.testId,
      suite: args.suite,
      selector: args.selector,
      target: args.target,
      mutation: mutationDescription(args),
      base_commit: clone.baseCommit,
      tree_hash: clone.sourceTreeHash,
      run_at_utc: nowUtcSeconds(),
      rc: String(rc),
      verdict,
      first_fail: firstFail,
    };
    const recordPath = writeRecord(specId, args.testId, fields, lastLines(output, TAIL_LINES));
    process.stdout.write(`${verdict}: ${recordPath}\n`);
    process.stdout.write(`first_fail: ${firstFail}\n`);

    if (verdict === 'RED') exit(0);
    if (verdict === 'STAYED GREEN') exit(5);
    exit(6);
  } finally {
    fs.rmSync(clone.tmpBase, { recursive: true, force: true });
  }
}

// --- replay --------------------------------------------------------------

function replay(args) {
  if (!args.spec) usageError('--replay requires --spec <path>');
  const specPath = path.isAbsolute(args.spec) ? args.spec : path.join(ROOT, args.spec);
  if (!fs.existsSync(specPath)) usageError(`--spec not found: ${args.spec}`);
  const specId = readSpecId(specPath);
  const dir = evidenceDir(specId);

  let entries = [];
  try {
    entries = fs.readdirSync(dir);
  } catch {
    process.stdout.write(`mutation-run --replay: no evidence directory for ${specId} (docs/ai/tdd/${specId}/) — nothing to replay\n`);
    exit(0);
  }

  const liveRecords = entries.filter((name) => {
    const m = /^mutation-(TEST-\d+)\.txt$/.exec(name);
    if (!m) return false;
    return true;
  }).sort();

  if (liveRecords.length === 0) {
    process.stdout.write(`mutation-run --replay: no live mutation records under docs/ai/tdd/${specId}/\n`);
    exit(0);
  }

  let failures = 0;
  for (const name of liveRecords) {
    const testId = /^mutation-(TEST-\d+)\.txt$/.exec(name)[1];
    const text = fs.readFileSync(path.join(dir, name), 'utf8');
    const parsed = parseRecord(text);
    if (!parsed.ok) {
      failures++;
      process.stdout.write(`FAIL ${testId}: malformed record (${parsed.error})\n`);
      continue;
    }
    const { fields } = parsed;
    const targetAbs = path.join(ROOT, fields.target);
    if (!fs.existsSync(targetAbs)) {
      failures++;
      process.stdout.write(`INCONCLUSIVE ${testId}: target no longer exists: ${fields.target}\n`);
      continue;
    }

    let clone;
    try {
      clone = buildIsolatedClone();
    } catch (err) {
      failures++;
      process.stdout.write(`FAIL ${testId}: could not build an isolated clone (${err.message})\n`);
      continue;
    }
    try {
      const mutationKind = fields.mutation.startsWith('sed:') ? 'sed' : 'patch';
      const mutationValue = fields.mutation.slice(fields.mutation.indexOf(':') + 1);
      const mutArgs = mutationKind === 'sed' ? { sed: mutationValue } : { patch: mutationValue };
      const { before, after } = applyMutation(mutArgs, clone.cloneDir, fields.target);
      if (before === after) {
        failures++;
        process.stdout.write(`FAIL ${testId}: replayed mutation no longer changes ${fields.target}\n`);
        continue;
      }
      const { rc, output } = runSuite(clone.cloneDir, fields.suite, fields.selector);
      const { verdict } = classifyVerdict(rc, output, testId);
      if (verdict === 'RED') {
        process.stdout.write(`RED ${testId}: still reddens (${fields.suite} ${fields.selector})\n`);
      } else {
        failures++;
        process.stdout.write(`${verdict} ${testId}: no longer reddens (${fields.suite} ${fields.selector})\n`);
      }
    } finally {
      fs.rmSync(clone.tmpBase, { recursive: true, force: true });
    }
  }

  process.stdout.write(`mutation-run --replay: ${liveRecords.length - failures}/${liveRecords.length} records still redden\n`);
  exit(failures === 0 ? 0 : 1);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) printHelp();
  if (args.replay) replay(args);
  else runOne(args);
}

runMain(() => main());
