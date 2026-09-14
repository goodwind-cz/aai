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
//        line for the selected test, OR the run's own D7 tripwire fired
//        (the mutated suite run wrote into the SOURCE tree outside
//        docs/ai/tdd/ — the verdict it produced cannot be trusted, so it is
//        downgraded to INCONCLUSIVE rather than recorded as-is); recorded,
//        non-zero exit
//   --replay:
//     0  every live record for the spec still reddens
//     1  one or more records replayed cleanly but no longer redden (STAYED
//        GREEN, INCONCLUSIVE-suite-died-for-another-reason, a malformed
//        record, the record's target no longer exists, or the D7 tripwire
//        fired on the replay run itself) — a genuine regression signal
//     4  no regression above, but one or more records could not even be
//        REPLAYED (the stored mutation could not be applied — e.g. a v0
//        record naming a patch file outside the evidence directory that no
//        longer exists) — distinct from exit 1 on purpose (D14, SPEC-0180
//        D8): "the replay ran and found a stale record" and "the replay
//        itself could not reproduce the mutation" must never render as the
//        same answer
//     2  usage error
//
// LIMITS (named, not fixed — out of scope for this ride):
//   - submodules are not reproduced by the isolated clone (D4's untracked-
//     file copy and `git diff HEAD` do not carry submodule contents);
//   - two concurrent runners recording the SAME Test Plan row race on the
//     live record path — last writer wins (fu-tripwire-attributes-concurrent-
//     writes, open, P3, is the tracked follow-up);
//   - Windows / sh-less environments: `runSuite` spawns `bash` unconditionally
//     and degrades by name (INCONCLUSIVE: bash not found) rather than
//     crashing (see runSuite below), but Pester suites themselves are out of
//     scope by D18 (fu-mutation-gate-skips-pester, filed).
//
// Node stdlib only (docs/TECHNOLOGY.md). Never invokes a shell: every
// external command runs via execFileSync/spawnSync with an argv array, so a
// mutation expression containing shell metacharacters is passed through
// literally rather than re-interpreted (Implementation plan "Edge cases").

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { exit, runMain, ExitSignal } from './lib/cli-pipe-guard.mjs';
import { parseFrontmatter } from './lib/docs-model.mjs';
import { computeTreeHash } from './lib/tree-hash.mjs';
import {
  formatRecord,
  parseRecord,
  lastLines,
  recordFileName,
  rotatedFileName,
  isRotatedFileName,
  patchFileName,
  rotatedPatchFileName,
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

// Strip heredoc bodies (<<'EOS' ... EOS, <<EOS, <<-EOS) before scanning for
// selectors (NB5): a fixture suite that WRITES another suite's source as
// heredoc text (this repo's own tests do this) must never have that quoted
// text's function definitions leak into ITS OWN selector grammar — a suite
// does not define a test merely by printing one.
function stripHeredocs(content) {
  const lines = content.split('\n');
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const m = /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/.exec(line);
    if (m) {
      out.push(line);
      const dash = line.includes('<<-');
      const marker = m[2];
      i++;
      while (i < lines.length) {
        const candidate = dash ? lines[i].replace(/^\t+/, '') : lines[i];
        if (candidate === marker) break;
        i++;
      }
      if (i < lines.length) i++; // skip the terminator line itself
      continue;
    }
    out.push(line);
    i++;
  }
  return out.join('\n');
}

// The SAME grammar check-test-registration.mjs uses (D3): a suite's own
// defined test_* functions, extracted without executing the suite, and
// without descending into any heredoc body it happens to write (NB5).
function extractSelectors(suiteContent) {
  return [...stripHeredocs(suiteContent).matchAll(/^(test_[A-Za-z0-9_]+)\(\)\s*\{/gm)].map((m) => m[1]);
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
  // Everything from here on is inside ONE try: any throw, of ANY shape
  // (a copy of a dangling symlink included — NB1), removes tmpBase before
  // propagating. The two explicit exit-3/generic-error paths below used to
  // be the only cleaned-up failures; this makes cleanup unconditional.
  try {
    const cloneDir = path.join(tmpBase, 'clone');
    execFileSync('git', ['clone', '--local', '--no-hardlinks', ROOT, cloneDir], { stdio: ['ignore', 'pipe', 'pipe'] });
    execFileSync('git', ['-C', cloneDir, 'checkout', '--quiet', baseCommit], { stdio: ['ignore', 'pipe', 'pipe'] });

    // Reproduce tracked modifications.
    const diff = execFileSync('git', ['-C', ROOT, 'diff', 'HEAD'], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
    if (diff.trim()) {
      const res = spawnSync('git', ['-C', cloneDir, 'apply'], { input: diff, encoding: 'utf8' });
      if (res.status !== 0) {
        throw new Error(`mutation-run: failed to reproduce tracked modifications in the clone: ${res.stderr || res.stdout}`);
      }
    }

    // Reproduce untracked-not-ignored files. A symlink (including a DANGLING
    // one, NB1) is reproduced AS a symlink — never followed/read — so a link
    // to nowhere can never throw here; anything else that cannot be copied
    // (a permission error, a race) is skipped BY NAME rather than aborting
    // the whole clone build.
    const untracked = execFileSync('git', ['-C', ROOT, 'ls-files', '--others', '--exclude-standard'], { encoding: 'utf8' });
    for (const rel of untracked.split('\n')) {
      const p = rel.trim();
      if (!p) continue;
      if (p === 'docs/ai/tdd' || p.startsWith('docs/ai/tdd/')) continue;
      const src = path.join(ROOT, p);
      const dst = path.join(cloneDir, p);
      try {
        const st = fs.lstatSync(src);
        fs.mkdirSync(path.dirname(dst), { recursive: true });
        if (st.isSymbolicLink()) {
          fs.symlinkSync(fs.readlinkSync(src), dst);
        } else {
          fs.copyFileSync(src, dst);
        }
      } catch (err) {
        process.stderr.write(`mutation-run: skipping untracked path that could not be reproduced in the clone: ${p} (${err.message})\n`);
      }
    }

    const cloneTreeHash = computeTreeHash(cloneDir);
    if (cloneTreeHash !== sourceTreeHash) {
      throw new TreeMismatchError(
        `mutation-run: clone tree hash (${cloneTreeHash}) does not match the source working tree's (${sourceTreeHash}) — the clone does not reproduce your tree`
      );
    }

    return { tmpBase, cloneDir, baseCommit, sourceTreeHash };
  } catch (err) {
    fs.rmSync(tmpBase, { recursive: true, force: true });
    throw err;
  }
}

// Runs the suite exactly as a human would: through aai-run-tests.sh, inside
// the clone (D1). Returns { rc, output } normally, or { rc: null, output,
// spawnError } when the interpreter itself could not be spawned (HAZ10:
// Windows / an sh-less host) — a distinct shape a caller degrades BY NAME
// (INCONCLUSIVE: bash not found) rather than mis-reading as a run that
// happened to exit 124 (the timeout convention, which this is NOT).
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
  if (res.error) {
    return { rc: null, output: '', spawnError: res.error };
  }
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
// under its OWN run_at_utc before writing the new one. Its accompanying
// --patch copy (D14: "a record is self-contained"), if any, rotates in
// lockstep under the SAME stamp, so a rotated record's mutation stays
// reproducible too.
function rotateExisting(dir, testId) {
  const live = path.join(dir, recordFileName(testId));
  if (!fs.existsSync(live)) return;
  const prevText = fs.readFileSync(live, 'utf8');
  const parsed = parseRecord(prevText);
  const stamp = parsed.ok ? parsed.fields.run_at_utc : `unknown-${Date.now()}`;
  const rotated = path.join(dir, rotatedFileName(testId, stamp));
  fs.renameSync(live, rotated);

  const livePatch = path.join(dir, patchFileName(testId));
  if (fs.existsSync(livePatch)) {
    fs.renameSync(livePatch, path.join(dir, rotatedPatchFileName(testId, stamp)));
  }
}

// D14: a --patch mutation's content is copied beside the record, under the
// SAME evidence directory, so the record is reproducible without relying on
// a path outside the repo (e.g. /tmp, which may be cleared, may not exist on
// another machine, or may simply belong to a different run by the time
// --replay reads it back). Returns the repo-relative stored path, or null
// when the mutation was a --sed expression (nothing to store).
function storePatchCopy(dir, testId, patchSourceAbs) {
  const dest = path.join(dir, patchFileName(testId));
  fs.copyFileSync(patchSourceAbs, dest);
  return path.relative(ROOT, dest);
}

// `patchSourceAbs`, when given (a --patch run), is copied beside the record
// and `fields.mutation` is rewritten to point at the STORED copy (repo-
// relative, under the evidence dir) rather than the caller's original
// --patch path, which may not outlive this run (D14).
function writeRecord(specId, testId, fields, tailText, patchSourceAbs) {
  const dir = evidenceDir(specId);
  fs.mkdirSync(dir, { recursive: true });
  rotateExisting(dir, testId);
  if (patchSourceAbs) {
    const storedRel = storePatchCopy(dir, testId, patchSourceAbs);
    fields = { ...fields, mutation: `patch:${storedRel}` };
  }
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

    const ran = runSuite(clone.cloneDir, args.suite, args.selector);
    let rc, output, verdict, firstFail;
    if (ran.spawnError) {
      // HAZ10: the interpreter itself could not be spawned (Windows / an
      // sh-less host) — a distinct, NAMED degrade, never a crash and never
      // confused with a real exit code.
      rc = 0;
      output = '';
      verdict = 'INCONCLUSIVE';
      firstFail = `INCONCLUSIVE: bash not found (${ran.spawnError.message})`;
    } else {
      ({ rc, output } = ran);
      ({ verdict, firstFail } = classifyVerdict(rc, output, args.testId));
    }

    // D7 self-check: the run above must have touched ONLY the clone and
    // docs/ai/tdd/ — never the shipping tree it was cloned from. A mismatch
    // means the mutated run itself wrote outside its lane (B1: e.g. a
    // mutated mutation-run.mjs appending to its own SOURCE copy of the
    // target), so the verdict it produced cannot be trusted and is
    // downgraded to INCONCLUSIVE rather than recorded as RED/STAYED GREEN.
    const postRunSourceTreeHash = computeTreeHash(ROOT);
    if (postRunSourceTreeHash !== clone.sourceTreeHash) {
      verdict = 'INCONCLUSIVE';
      firstFail = `INCONCLUSIVE: the run wrote into the source tree outside docs/ai/tdd/ (D7 tripwire: tree hash ${clone.sourceTreeHash} -> ${postRunSourceTreeHash}) — refusing to trust this result`;
    }

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
    const patchSourceAbs = args.patch ? (path.isAbsolute(args.patch) ? args.patch : path.join(ROOT, args.patch)) : undefined;
    const recordPath = writeRecord(specId, args.testId, fields, lastLines(output, TAIL_LINES), patchSourceAbs);
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

  // Two independent counters (B3 / D14): `failures` is a genuine regression
  // signal (the record replayed cleanly but no longer reddens — the code
  // under test changed); `inconclusive` is "this replay could not even be
  // ATTEMPTED" (the stored mutation could not be applied — e.g. an older v0
  // record naming a patch file outside the evidence directory that no
  // longer exists). SPEC-0180 D8's rule applies here too: these must never
  // render as the same exit code.
  let failures = 0;
  let inconclusive = 0;
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
    // Everything from here on can throw for a REPRODUCIBILITY reason (a
    // missing/stale --patch file, a `git apply` failure) rather than a
    // regression one — caught here so it becomes a named INCONCLUSIVE row,
    // never an uncaught stack trace with an exit code indistinguishable
    // from "the mutation no longer reddens" (B3).
    try {
      let before, after;
      try {
        const mutationKind = fields.mutation.startsWith('sed:') ? 'sed' : 'patch';
        const mutationValue = fields.mutation.slice(fields.mutation.indexOf(':') + 1);
        const mutArgs = mutationKind === 'sed' ? { sed: mutationValue } : { patch: mutationValue };
        ({ before, after } = applyMutation(mutArgs, clone.cloneDir, fields.target));
      } catch (err) {
        inconclusive++;
        process.stdout.write(`INCONCLUSIVE ${testId}: could not apply the recorded mutation (${err.message})\n`);
        continue;
      }
      if (before === after) {
        failures++;
        process.stdout.write(`FAIL ${testId}: replayed mutation no longer changes ${fields.target}\n`);
        continue;
      }
      const ran = runSuite(clone.cloneDir, fields.suite, fields.selector);
      if (ran.spawnError) {
        inconclusive++;
        process.stdout.write(`INCONCLUSIVE ${testId}: bash not found (${ran.spawnError.message})\n`);
        continue;
      }
      const { rc, output } = ran;
      const postRunSourceTreeHash = computeTreeHash(ROOT);
      if (postRunSourceTreeHash !== clone.sourceTreeHash) {
        failures++;
        process.stdout.write(`INCONCLUSIVE ${testId}: own replay run wrote into the source tree outside docs/ai/tdd/ (D7 tripwire) — refusing to trust the result\n`);
        continue;
      }
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

  const attempted = liveRecords.length - inconclusive;
  process.stdout.write(`mutation-run --replay: ${attempted - failures}/${attempted} attempted records still redden (${inconclusive} inconclusive of ${liveRecords.length} total)\n`);
  if (failures > 0) exit(1);
  if (inconclusive > 0) exit(4);
  exit(0);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) printHelp();
  if (args.replay) replay(args);
  else runOne(args);
}

runMain(() => main());
