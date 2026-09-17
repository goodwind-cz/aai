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
//     --sed's pat is a JavaScript RegExp (not sed BRE/ERE): `(` groups, `\(` is literal.
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
//     scope by D18 (fu-mutation-gate-skips-pester, filed);
//   - D7 (NB2-r2): the shipping-tree tripwire compares a tree hash before and
//     after the run — it CANNOT distinguish the run's own write from a
//     CONCURRENT editor's (another process touching the source tree while
//     this run is in flight, e.g. a full sweep appending to
//     docs/ai/tests/test-runs.jsonl). Either way it fails CLOSED: the verdict
//     is downgraded to INCONCLUSIVE, never recorded as RED or STAYED GREEN,
//     and the message names the changed path(s) so an operator can tell a
//     concurrent writer from a real self-inflicted bug. --replay counts this
//     as `inconclusive` (exit 4), never a genuine regression (exit 1) — "I
//     could not tell" must never render as "regression" (D6/D8);
//   - D7 (NB-5): the tree hash it compares covers tracked files plus
//     untracked-not-ignored files, so it is BLIND to every OTHER gitignored
//     path outside docs/ai/tdd — a mutated run writing into the source
//     tree's docs/ai/STATE.yaml would leave the hash unchanged were it not
//     for lib/tree-hash.mjs's own named RUNTIME_ALLOWLIST (docs/ai/STATE.yaml,
//     docs/ai/LOOP_TICKS.jsonl — hashed when present, closed list, never a
//     blanket "every gitignored path"); an unlisted runtime sidecar is still
//     invisible to this tripwire.
//   - D7 (remediation round 4, NB-1): the allowlist above is reproduced into
//     the clone (D4, buildIsolatedClone) so the D4 clone-fidelity comparison
//     still covers it, but it is EXCLUDED from THIS before/after comparison —
//     a canon-permitted concurrent ceremony write (log-tick, state.mjs) to
//     docs/ai/STATE.yaml or docs/ai/LOOP_TICKS.jsonl during a run must never
//     downgrade a genuine RED to INCONCLUSIVE (TEST-497). The mirror-image
//     limit this buys: a MUTATED run that itself writes the source copy of
//     an allowlist path from inside the suite is now invisible to D7 too —
//     the allowlist is reproduced into the clone, never tripwired in the
//     source, and this tool makes no wider claim than that.
//
// Node stdlib only (docs/TECHNOLOGY.md). Never invokes a shell: every
// external command runs via execFileSync/spawnSync with an argv array, so a
// mutation expression containing shell metacharacters is passed through
// literally rather than re-interpreted (Implementation plan "Edge cases").

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { exit, runMain, ExitSignal } from './lib/cli-pipe-guard.mjs';
import { parseFrontmatter } from './lib/docs-model.mjs';
import {
  computeTreeFileHashes,
  hashFromFileHashes,
  diffTreeFileHashes,
  describeTreeDiff,
  RUNTIME_ALLOWLIST,
} from './lib/tree-hash.mjs';
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

// Remediation round 7 (Copilot, PR #384): a missing value OR a value that
// itself looks like another flag (starts with "--") is a usage error, never
// silently accepted as the flag's value — see the same fix and rationale in
// mutation-gate.mjs (`requireValue`).
function requireValue(argv, i, flagName) {
  const v = argv[i + 1];
  if (v === undefined || v.startsWith('--')) {
    usageError(`${flagName} requires a value${v === undefined ? '' : ` (got "${v}", which looks like another flag)`}`);
  }
  return v;
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
        out.spec = requireValue(argv, i, '--spec');
        i += 1;
        break;
      case '--test-id':
        out.testId = requireValue(argv, i, '--test-id');
        i += 1;
        break;
      case '--suite':
        out.suite = requireValue(argv, i, '--suite');
        i += 1;
        break;
      case '--selector':
        out.selector = requireValue(argv, i, '--selector');
        i += 1;
        break;
      case '--target':
        out.target = requireValue(argv, i, '--target');
        i += 1;
        break;
      case '--sed':
        out.sed = requireValue(argv, i, '--sed');
        i += 1;
        break;
      case '--patch':
        out.patch = requireValue(argv, i, '--patch');
        i += 1;
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
      '    (--sed \'<s/pat/repl/[flags]>\' | --patch <unified-diff file>)\n' +
      '    --sed: pat is a JavaScript RegExp, NOT sed BRE/ERE — `(` groups, `\\(` is a\n' +
      '          literal paren; repl is literal except JS $-patterns; a no-op is refused.\n\n' +
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
//
// NB4-r2: an UNTERMINATED heredoc (no line before EOF equals the marker) is
// treated as NO heredoc at all, deliberately — the opener line and every
// line after it up to EOF are left for the normal per-line scan below, so a
// REAL selector defined after a malformed/never-closed heredoc opener is
// still found rather than silently swallowed to EOF. The alternative (close
// it at EOF) would make a single stray `<<MARKER` anywhere in the file blind
// this tool to every real test defined after it — a worse failure mode than
// occasionally scanning a few lines of undelimited heredoc body text.
function stripHeredocs(content) {
  const lines = content.split('\n');
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    // NB6-r3: a heredoc opener written inside a full-line COMMENT (this
    // repo's own house style: `# example: cat <<EOS`) must never open a REAL
    // heredoc — when another, legitimate `<<EOS ... EOS` heredoc later in the
    // same file shares that marker, the commented mention would consume
    // everything up to that later heredoc's OWN terminator, silently
    // swallowing every selector defined in between. Only recognise `<<`
    // outside a comment line.
    const isCommentLine = /^\s*#/.test(line);
    const m = isCommentLine ? null : /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/.exec(line);
    if (m) {
      const dash = line.includes('<<-');
      const marker = m[2];
      let j = i + 1;
      let terminatorIdx = -1;
      while (j < lines.length) {
        const candidate = dash ? lines[j].replace(/^\t+/, '') : lines[j];
        if (candidate === marker) {
          terminatorIdx = j;
          break;
        }
        j++;
      }
      if (terminatorIdx === -1) {
        // NB4-r2: unterminated — do not consume anything beyond this line.
        out.push(line);
        i++;
        continue;
      }
      out.push(line);
      i = terminatorIdx + 1; // skip the terminator line itself
      continue;
    }
    out.push(line);
    i++;
  }
  return out.join('\n');
}

// NB6-r2: re-implements, by hand, the SAME six command-position idioms
// tests/skills/test-aai-hygiene-pack.sh `hp_scan_selector_suites` detects —
// that scanner is bash (grep -E over a file), this tool is Node, and this
// check runs at record-write time against the suite text mutation-run.mjs
// already read (extractSelectors' own input), so re-implementing the regexes
// here (rather than shelling out to a bash lib) keeps this check in the same
// process and language as the rest of the tool. Keep both lists in sync by
// hand; hygiene-pack's test_094 is the corpus authority for the real tree.
// Whitespace class NB4-r3 (remediation round 3): the bash twin
// (hp_scan_selector_suites, tests/skills/test-aai-hygiene-pack.sh) matches
// POSIX `[[:space:]]`, which includes vertical tab and form feed; the prior
// `[ \t]` here did not, a divergence measured to be unreachable on the LIVE
// corpus today (a sweep of both scanners over every tests/skills/*.sh agrees
// byte-for-byte) but real on a synthetic file. Widened so the two copies stay
// aligned on the same whitespace grammar, not merely the same corpus.
const WS = ' \\t\\v\\f';
const POSITIONAL_DISPATCH_PATTERNS = [
  /declare -[fF] "\$1"/,
  /declare -[fF] "test_\$\{[A-Za-z_]+\}"/,
  new RegExp(`(^|;|&&|\\|\\||then|do)[${WS}]*"\\$1"([${WS};]|$)`, 'm'),
  new RegExp(`(^|;|&&|\\|\\||then|do)[${WS}]*"test_\\$\\{[A-Za-z_]+\\}"`, 'm'),
  /ALL_TESTS\[@\]/,
  new RegExp(`"\\$fn"[${WS}]*$`, 'm'),
];

// isPositionalDispatchSuite(content) -> true when the suite's own text
// matches at least one of the idioms above — i.e. it actually dispatches on
// a positional selector rather than ignoring $1 and running every test.
export function isPositionalDispatchSuite(content) {
  return POSITIONAL_DISPATCH_PATTERNS.some((re) => re.test(content));
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

// Remediation round 7 (Codex P1, PR #384) + validation rounds 10 and 11:
// a --patch with hunks for files besides --target was applied WHOLE, so an
// extra hunk could edit the suite (or a dependency) to print a matching FAIL
// line and fake a RED. Round 7 refused by parsing `a/`-`b/` headers by hand;
// round 10 forged a RED through it three ways (another prefix — `git apply`
// strips ANY first component, a C-quoted header, CRLF headers). Round 10's
// fix asked git (`git apply --numstat -z`), and round 11 forged a RED through
// THAT: numstat prints only the POST-image path of each item, so a rename
// whose destination is --target deletes a foreign file unseen. Two guards,
// because each sees what the other cannot:
//   1. `git apply --numstat -z` BEFORE the apply — git's own parse of the
//      post-image paths (prefix stripping, quoting, creations, binary); a
//      hostile patch is refused without being applied.
//   2. the clone's tree, hashed before and after the apply — what actually
//      changed on disk, whatever the patch said: a rename SOURCE, a deletion,
//      anything. lib/tree-hash.mjs lists with `ls-files -z`, so a git-quoted
//      name is seen too.
// Either naming a path other than targetRel is a refusal (throws; the
// normal-run caller turns it into exit 2 naming the path with no record and
// no clone left, the --replay caller into a named INCONCLUSIVE row).
function patchPathsPerGit(cloneDir, patchAbs) {
  const out = execFileSync('git', ['-C', cloneDir, 'apply', '--numstat', '-z', patchAbs],
    { stdio: ['ignore', 'pipe', 'pipe'] }).toString('utf8');
  const paths = new Set();
  // `git apply --numstat -z` emits ONE record per item,
  // "<added>\t<deleted>\t<post-image path>\0" ("-\t-\t" for binary). It
  // never prints a rename's source (that is `git diff --numstat -z`'s format,
  // not this command's — measured on git 2.54, validation round 11); the
  // tree-diff guard below is what sees a source.
  for (const tok of out.split('\0')) {
    if (tok === '') continue;
    const m = /^(?:\d+|-)\t(?:\d+|-)\t(.*)$/s.exec(tok);
    if (m) { if (m[1] !== '') paths.add(m[1]); } else paths.add(tok);
  }
  return paths;
}

function refuseForeignPaths(kind, offending, targetRel) {
  if (offending.length) {
    throw new Error(`--patch touches path(s) other than --target ${targetRel} (${kind}): ${[...new Set(offending)].sort().join(', ')}`);
  }
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
    refuseForeignPaths('per git apply --numstat',
      [...patchPathsPerGit(cloneDir, patchAbs)].filter((rel) => rel !== targetRel), targetRel);
    const treeBeforeApply = computeTreeFileHashes(cloneDir);
    execFileSync('git', ['-C', cloneDir, 'apply', patchAbs], { stdio: ['ignore', 'pipe', 'pipe'] });
    const applied = diffTreeFileHashes(treeBeforeApply, computeTreeFileHashes(cloneDir));
    refuseForeignPaths('changed on disk by the apply',
      [...applied.added, ...applied.removed, ...applied.changed].filter((rel) => rel !== targetRel), targetRel);
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
// hash (D4). Returns { cloneDir, baseCommit, sourceTreeHash, sourceTreeFiles }
// or throws a TreeMismatch marker error the caller turns into the exit-3
// refusal. `sourceTreeFiles` (NB2-r2) is the per-file hash map the summary
// hash was derived from — kept so a caller can later NAME which path moved,
// not only that the summary hash did.
class TreeMismatchError extends Error {}

// Remediation round 4 (NB-1): D4 (buildIsolatedClone, above) and D7 (the two
// before/after tripwire call sites below) share tree-hash.mjs's primitives,
// but they now WANT different comparisons over the same RUNTIME_ALLOWLIST
// paths — D4 must still prove the clone reproduces them (a copy failure is a
// real fidelity gap), D7 must NOT trip on a canon-permitted concurrent
// ceremony write to them (log-tick, state.mjs) that never touches the clone
// at all. withoutRuntimeAllowlist() is the ONE place that difference is
// expressed: it strips the allowlist paths out of a computeTreeFileHashes()
// map before D7 hashes/diffs it, so a caller cannot accidentally compare the
// two tripwires with different filtering logic.
function withoutRuntimeAllowlist(fileHashMap) {
  if (!RUNTIME_ALLOWLIST.length) return fileHashMap;
  const filtered = new Map(fileHashMap);
  for (const rel of RUNTIME_ALLOWLIST) filtered.delete(rel);
  return filtered;
}

function buildIsolatedClone() {
  const baseCommit = execFileSync('git', ['-C', ROOT, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  const sourceTreeFiles = computeTreeFileHashes(ROOT);
  // sourceTreeHash is NOT derived here (remediation round 4, NB-1 second
  // window): RUNTIME_ALLOWLIST entries in sourceTreeFiles above were read at
  // THIS instant, but the allowlist copy loop below reads them again, later,
  // when it writes them into the clone — a concurrent ceremony write landing
  // between the two reads would make sourceTreeFiles' allowlist entries
  // describe bytes the clone never actually received, tripping the D4
  // comparison over a race rather than a real fidelity gap. Deferred to
  // after that loop, once sourceTreeFiles has been corrected to the bytes
  // ACTUALLY copied.

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

    // NB-5: RUNTIME_ALLOWLIST paths are now part of the tree hash (tree-hash.mjs
    // listTreeFiles), so they must ALSO be reproduced in the clone — the same
    // way an ordinary untracked-not-ignored file is above — or every run would
    // spuriously refuse (source hash includes the path, clone hash does not,
    // since `git ls-files --others --exclude-standard` never lists a
    // gitignored path). Copied only when present, same skip-by-name
    // discipline as the untracked-file loop above.
    //
    // Remediation round 4 (NB-1, second window): the bytes are read HERE,
    // ONCE, and that same buffer is both written to the clone AND hashed to
    // correct sourceTreeFiles' entry for this path — never a second
    // `fs.readFileSync(ROOT/...)` and never trusting the earlier
    // computeTreeFileHashes(ROOT) snapshot for these paths. This makes the
    // D4 comparison below compare the clone against what was ACTUALLY
    // copied, not against a possibly-stale earlier read, closing the race
    // where a concurrent ceremony write between the two reads would show up
    // as a spurious TreeMismatchError. A path that vanished between the
    // early scan and this loop is removed from sourceTreeFiles too (it will
    // not be in the clone either — nothing to compare).
    for (const rel of RUNTIME_ALLOWLIST) {
      const src = path.join(ROOT, rel);
      let bytes;
      try {
        bytes = fs.readFileSync(src);
      } catch {
        sourceTreeFiles.delete(rel); // vanished since the early scan — not reproduced, not compared
        continue;
      }
      const dst = path.join(cloneDir, rel);
      try {
        fs.mkdirSync(path.dirname(dst), { recursive: true });
        fs.writeFileSync(dst, bytes);
        sourceTreeFiles.set(rel, createHash('sha256').update(bytes).digest('hex'));
      } catch (err) {
        process.stderr.write(`mutation-run: skipping runtime-allowlist path that could not be reproduced in the clone: ${rel} (${err.message})\n`);
      }
    }
    const sourceTreeHash = hashFromFileHashes(sourceTreeFiles);

    const cloneTreeFiles = computeTreeFileHashes(cloneDir);
    const cloneTreeHash = hashFromFileHashes(cloneTreeFiles);
    if (cloneTreeHash !== sourceTreeHash) {
      // Remediation round 3 NB-3: name the changed path(s), the same way the
      // D7 in-run tripwire does — this mismatch is most often a CONCURRENT
      // WRITER touching the source tree between the hash captured above and
      // the diff/untracked-copy steps just run against ROOT again, not a bug
      // in the clone builder itself.
      const treeDiff = diffTreeFileHashes(sourceTreeFiles, cloneTreeFiles);
      throw new TreeMismatchError(
        `mutation-run: clone tree hash (${cloneTreeHash}) does not match the source working tree's (${sourceTreeHash}) — ${describeTreeDiff(treeDiff)} — the clone does not reproduce your tree`
      );
    }

    return { tmpBase, cloneDir, baseCommit, sourceTreeHash, sourceTreeFiles };
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

  // NB2-r3: `run_at_utc` is ISO to the SECOND, so two rotations landing in
  // the same second would otherwise target the identical archive name and
  // the later write would silently clobber the earlier one — the one case
  // D2's "never delete, never overwrite" did not itself cover. Probe for the
  // first name (bare, then .1, .2, ...) not already on disk, for BOTH the
  // record and its patch sibling together, so the two stay paired under the
  // same suffix.
  let suffix; // undefined = the bare (unsuffixed) name
  let rotated = path.join(dir, rotatedFileName(testId, stamp));
  // NB5-r4: the probe must consider the PATCH sibling's name as well — a
  // rotated .patch left on disk without its paired .txt (or planted by hand)
  // was silently overwritten when only the record name was checked.
  const taken = (sfx) => fs.existsSync(path.join(dir, rotatedFileName(testId, stamp, sfx)))
    || fs.existsSync(path.join(dir, rotatedPatchFileName(testId, stamp, sfx)));
  while (taken(suffix)) {
    suffix = (suffix ?? 0) + 1;
    rotated = path.join(dir, rotatedFileName(testId, stamp, suffix));
  }

  const livePatch = path.join(dir, patchFileName(testId));
  const hasPatch = fs.existsSync(livePatch);
  const rotatedPatchAbs = path.join(dir, rotatedPatchFileName(testId, stamp, suffix));

  // NB7-r2: rotation moves the record AND its --patch copy in lockstep
  // (below), so the rotated RECORD's own `mutation:` field must be rewritten
  // to name the rotated patch it now sits beside — not the LIVE patch name,
  // whose bytes belong to the NEXT run the instant this function returns.
  // Leaving the field unrewritten was a false sentence in this comment's own
  // prior claim ("a rotated record's mutation stays reproducible too") and an
  // archival footgun: a hand-replay of the rotated .txt would apply the
  // WRONG (next run's) patch. Everything else about the rotated text is
  // byte-identical to what was live.
  let rotatedText = prevText;
  if (hasPatch && parsed.ok && parsed.fields.mutation.startsWith('patch:')) {
    const rotatedPatchRel = path.relative(ROOT, rotatedPatchAbs);
    // NB3-r3: the replacement MUST be a function, never a string. this
    // repo's own LEARNED rule (js-replace-dollar-quote-corrupts) names the
    // trap directly: `String.replace`'s STRING form re-interprets `$&`,
    // `` $` `` and `$'` inside the replacement text as special patterns —
    // `rotatedPatchRel` is built from the spec's frontmatter `id` (read with
    // no validation, readSpecId) and a stamp taken verbatim from a prior
    // record's `run_at_utc` header value (parseRecord accepts arbitrary
    // single-line text there), so a hand-edited record or a `$`-bearing spec
    // id reaches this unguarded. A function replacement passes the text
    // through literally, with no pattern re-interpretation.
    rotatedText = prevText.replace(/^mutation: patch:.*$/m, () => `mutation: patch:${rotatedPatchRel}`);
  }
  // NB7-r3: write the rotated copy via tmp + renameSync (atomic on the same
  // filesystem — the same discipline spec-freeze.mjs's own atomic write
  // uses), and remove the LIVE record only after the rotated copy is safely
  // in place. The prior `writeFileSync(rotated, ...)` could leave a
  // TRUNCATED file at the final rotated name if interrupted mid-write; this
  // ordering never does — the worst case after an interruption between the
  // rename and the rm is BOTH the live and the rotated record surviving
  // (a harmless duplicate), never a half-written archive and never the live
  // record vanishing before its replacement exists.
  //
  // Remediation round 4 (NB-3): the patch sibling moves to its rotated
  // location FIRST — before the record is rotated and before the live
  // record is removed. The prior order (record rotated, live record
  // removed, THEN the patch renamed last) left a window where a process
  // death between "live record removed" and "patch renamed" left the
  // rotated record on disk naming a rotated patch path that did not exist
  // yet, and an orphan live patch the NEXT run's storePatchCopy would then
  // silently overwrite — the rotated archive permanently unreproducible.
  // With the patch moved first, by the time any rotated record can exist on
  // disk, its named rotated patch already does too; only then is the live
  // record removed, last.
  if (hasPatch) {
    fs.renameSync(livePatch, rotatedPatchAbs);
  }
  const rotatedTmp = `${rotated}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(rotatedTmp, rotatedText);
  fs.renameSync(rotatedTmp, rotated);
  fs.rmSync(live);
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
  // Remediation round 5 (D8 amendment): the SOURCE target's bytes at record
  // time, hashed BEFORE the mutation is applied (to the CLONE, never to this
  // source path) — this is what mutation-gate.mjs later compares against the
  // live target to detect a STALE record (BLOCKING-1, validation round 6).
  const targetSha256 = createHash('sha256').update(fs.readFileSync(targetAbs)).digest('hex');

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
    // means EITHER the mutated run itself wrote outside its lane (B1: e.g. a
    // mutated mutation-run.mjs appending to its own SOURCE copy of the
    // target) OR a concurrent editor touched the source tree while this run
    // was in flight (NB2-r2) — this tripwire cannot tell the two apart, so
    // either way the verdict it produced cannot be trusted and is downgraded
    // to INCONCLUSIVE rather than recorded as RED/STAYED GREEN, and the
    // message names the changed path(s) rather than asserting which cause it
    // was.
    //
    // Remediation round 4 (NB-1): RUNTIME_ALLOWLIST paths are excluded from
    // THIS comparison (withoutRuntimeAllowlist) — they are reproduced into
    // the clone at D4 build time, never tripwired here, so a canon-permitted
    // concurrent ceremony write to docs/ai/STATE.yaml or
    // docs/ai/LOOP_TICKS.jsonl during the run cannot downgrade a genuine
    // verdict (TEST-497). A change to any OTHER path still trips this exactly
    // as before.
    const postRunSourceTreeFiles = computeTreeFileHashes(ROOT);
    const beforeD7 = withoutRuntimeAllowlist(clone.sourceTreeFiles);
    const afterD7 = withoutRuntimeAllowlist(postRunSourceTreeFiles);
    const beforeD7Hash = hashFromFileHashes(beforeD7);
    const afterD7Hash = hashFromFileHashes(afterD7);
    if (afterD7Hash !== beforeD7Hash) {
      const treeDiff = diffTreeFileHashes(beforeD7, afterD7);
      verdict = 'INCONCLUSIVE';
      firstFail = `INCONCLUSIVE: the source tree changed during this run (this run, or another writer) — ${describeTreeDiff(treeDiff)} (D7 tripwire: tree hash ${beforeD7Hash} -> ${afterD7Hash}) — refusing to trust this result`;
    }

    // NB6-r2: whether the row's own suite actually dispatches on `selector`,
    // or ignores $1 and runs every test (spec-lint, spec-tools, prompt-diet,
    // the liveness suite all do this today) — the record is still honest either way
    // (the suite reddened), but this says whether --selector's isolation
    // claim actually held for THIS run.
    const selectorHonoured = isPositionalDispatchSuite(suiteContent);
    if (!selectorHonoured) {
      process.stdout.write(
        `NOTE: ${args.suite} does not appear to dispatch on a positional selector — this record's verdict is honest (the suite reddened), but --selector did not isolate it; the whole suite ran.\n`
      );
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
      selector_honoured: selectorHonoured ? 'yes' : 'no (suite runs every test)',
      target_sha256: targetSha256,
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
      // NB-3 (remediation round 3): a buildIsolatedClone() failure — a
      // TreeMismatchError (a concurrent writer touching the source tree
      // between the hash and the clone build, this ride's own documented
      // operating mode) included — means "this replay could not even be
      // ATTEMPTED", the exact exit-4 class D14 already carves out for a
      // stale/unapplyable --patch, never a genuine regression (exit 1).
      // Counting it as failures++ (the pre-fix behavior) manufactured a
      // false BLOCKING verdict out of an ordinary concurrent full sweep.
      inconclusive++;
      process.stdout.write(`INCONCLUSIVE ${testId}: could not build an isolated clone (${err.message})\n`);
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
        // NB2-r7 (validation round 7): the OTHER stale-target symptom — a
        // record's own sed pattern can stop matching because the target
        // itself was edited/re-pinned after the record was produced (the
        // LIKELIER of the two ways a record goes stale here, D8's own
        // amendment). Same target_sha256 comparison as the "no longer
        // reddens" branch below, so this diagnostic is no longer missing on
        // the branch that fires more often for a genuinely stale record.
        let beforeAfterStaleNote = '';
        if (fields.target_sha256) {
          try {
            const liveSha256 = createHash('sha256').update(fs.readFileSync(targetAbs)).digest('hex');
            if (liveSha256 !== fields.target_sha256) beforeAfterStaleNote = ' (target changed since the record)';
          } catch {
            // target already reported missing above; nothing to add here.
          }
        }
        process.stdout.write(`FAIL ${testId}: replayed mutation no longer changes ${fields.target}${beforeAfterStaleNote}\n`);
        continue;
      }
      const ran = runSuite(clone.cloneDir, fields.suite, fields.selector);
      if (ran.spawnError) {
        inconclusive++;
        process.stdout.write(`INCONCLUSIVE ${testId}: bash not found (${ran.spawnError.message})\n`);
        continue;
      }
      const { rc, output } = ran;
      // Remediation round 4 (NB-1): same exclusion as the normal-run D7
      // self-check above — RUNTIME_ALLOWLIST paths are reproduced into the
      // clone at D4 build time, never tripwired here, so a concurrent
      // ceremony write to them during a --replay run cannot manufacture a
      // false inconclusive either.
      const postRunSourceTreeFiles = computeTreeFileHashes(ROOT);
      const beforeD7 = withoutRuntimeAllowlist(clone.sourceTreeFiles);
      const afterD7 = withoutRuntimeAllowlist(postRunSourceTreeFiles);
      const beforeD7Hash = hashFromFileHashes(beforeD7);
      const afterD7Hash = hashFromFileHashes(afterD7);
      if (afterD7Hash !== beforeD7Hash) {
        // NB2-r2: a D7 trip during --replay cannot tell "this run wrote
        // outside its lane" from "a concurrent editor touched the source
        // tree while this run was in flight" (e.g. a full sweep appending to
        // docs/ai/tests/test-runs.jsonl) — it is "I could not tell", never a
        // genuine regression signal, so it counts as inconclusive++ (exit 4)
        // rather than failures++ (exit 1: SPEC-0180 D8's rule applied to
        // replay). The message names the changed path(s) instead of naming a
        // cause it cannot actually distinguish.
        inconclusive++; // NB2-r2 D7 trip during replay is inconclusive, not a regression
        const treeDiff = diffTreeFileHashes(beforeD7, afterD7);
        process.stdout.write(`INCONCLUSIVE ${testId}: the source tree changed during this run (this run, or another writer) — ${describeTreeDiff(treeDiff)} (D7 tripwire) — refusing to trust the result\n`);
        continue;
      }
      const { verdict } = classifyVerdict(rc, output, testId);
      if (verdict === 'RED') {
        process.stdout.write(`RED ${testId}: still reddens (${fields.suite} ${fields.selector})\n`);
      } else {
        failures++;
        // Remediation round 5 (D8 amendment): when the record carries a
        // target_sha256 and the target's LIVE bytes no longer match it, name
        // that alongside a STAYED GREEN — the exact BLOCKING-1 shape
        // (validation round 6): the record's own mutation went stale because
        // its target was edited/re-pinned after the record was produced, not
        // because the property it tests stopped holding. An older record
        // with no target_sha256 (nothing to compare) prints nothing extra.
        let staleNote = '';
        if (fields.target_sha256) {
          try {
            const liveSha256 = createHash('sha256').update(fs.readFileSync(targetAbs)).digest('hex');
            if (liveSha256 !== fields.target_sha256) staleNote = ' (target changed since the record)';
          } catch {
            // target already reported missing above; nothing to add here.
          }
        }
        process.stdout.write(`${verdict} ${testId}: no longer reddens (${fields.suite} ${fields.selector})${staleNote}\n`);
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

// NB4-r3 (remediation round 3): standard ESM entry-point guard, so a TEST can
// `import` this module for its exported helpers (isPositionalDispatchSuite)
// without also running the CLI against the test's own process.argv — a pure
// safety addition, zero behavior change for every existing `node
// mutation-run.mjs ...` invocation (argv[1] IS this file in that case).
// Both sides through realpath (sweep-2 Spec-AC-22, doctor TEST-439): a
// symlinked invocation (`node /usr/local/bin/mutation-run`) must still run.
const __argvReal = (() => { try { return fs.realpathSync(path.resolve(process.argv[1] ?? '')); } catch { return ''; } })();
if (__argvReal !== '' && __argvReal === fs.realpathSync(fileURLToPath(import.meta.url))) {
  runMain(() => main());
}
