#!/usr/bin/env node
// check-committed-scope.mjs — for every in-scope path, the COMMITTED BLOB must
// equal the worktree. SPEC spec-lessons-that-must-hold-downstream-are-guards D3.
//
// WHY THIS EXISTS. docs/knowledge/LEARNED.md has said since 2026-07-03 that a
// content check must read the STAGED blob and never the worktree. On 2026-09-06
// the same author broke exactly that twice in one session (PR #346, PR #347):
// `git add` was handed a path the doc-number allocator had already renamed, so
// the whole add aborted, and the commit still LOOKED whole because the allocator
// stages the rename itself and the pre-commit hook stages docs/INDEX.md. A
// frontmatter stamp and several regenerated pages never reached the commit.
// `git status` said "modified" — which is also what a legitimate later edit says.
// Only comparing the committed blob to the worktree separates the two. A note
// did not prevent it twice; this does.
//
// Usage:
//   node .aai/scripts/check-committed-scope.mjs <path>...
//   node .aai/scripts/check-committed-scope.mjs --from-state [--state <p>]
//   node .aai/scripts/check-committed-scope.mjs --from-stdin      (NUL- or NL-separated)
//   [--rev <ref>]   compare against that commit instead of the index (default: the index)
//   [--strict]      a degrade is a FAILURE too (see below)
//   [--json]
//   [--expect-branch <branch>]  CHANGE-0180 D4 HEAD-pin re-check; see below.
//
// Exit: 0 clean (or a NAMED degrade) · 1 at least one path differs · 2 usage
// · 3 HEAD PIN REFUSED (CHANGE-0180 D4, --expect-branch given): EITHER cwd is
//   not inside a git work tree at all (checkBranchPin's 'no-work-tree' cause,
//   review NB-2), OR the pinned branch/sha no longer matches the given
//   --expect-branch (F-3: both causes map to this one exit here — the
//   distinct no-work-tree/detached/renamed/concurrent taxonomy is
//   checkBranchPin's own `cause` field, not surfaced as a separate exit code
//   by this script). ADDITIVE: no --expect-branch given, or no pin file at
//   all, and this check is a complete no-op (Spec-AC-04) — every other exit
//   above is unaffected.
// A degrade is exit 0 and SAYS SO: an untracked path or an unreadable repo is
// not a mismatch, but it is also not a verified match, and silence would be the
// same failure this script exists to catch.
//
// --strict MAKES A DEGRADE FAIL, and the PR ceremony uses it. Exit 0 on "there
// was nothing to compare" is the wrong answer for a gate: the aborted `git add`
// this script exists to catch drops EVERY path in that command, and an
// untracked one degrades rather than mismatching — so the plain mode would wave
// through the exact incident. Reported by code review, 2026-09-06.
//
// COMPARISON. `git diff` does the comparing, not this script. A hand-rolled
// byte compare of `git show :<path>` against the file on disk is wrong three
// ways, all found by review: with `core.autocrlf=true` (the Git-for-Windows
// default) every text file legitimately differs, so the gate would STOP every
// PR on every Windows install; a symlink always differs, because the blob is
// the target string while the read follows the link; and a blob over
// execFileSync's 1 MiB default maxBuffer throws, which the old code caught as
// "untracked" and passed — a real mismatch reported as clean. git knows its own
// clean/smudge filters, modes and link semantics; asking it is both correct and
// less code.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { checkBranchPin } from './branch-guard.mjs';

function usage(msg) { process.stderr.write(`check-committed-scope: ${msg}\n`); process.exit(2); }

function parseArgs(argv) {
  const a = { paths: [], fromState: false, fromStdin: false, state: 'docs/ai/STATE.yaml', rev: null, json: false, strict: false, expectBranch: null };
  for (let i = 0; i < argv.length; i += 1) {
    const k = argv[i]; const v = argv[i + 1];
    const need = () => { if (v === undefined || v.startsWith('--')) usage(`${k} requires a value`); i += 1; return v; };
    if (k === '--from-state') a.fromState = true;
    else if (k === '--from-stdin') a.fromStdin = true;
    else if (k === '--state') a.state = need();
    else if (k === '--rev') a.rev = need();
    else if (k === '--json') a.json = true;
    else if (k === '--strict') a.strict = true;
    else if (k === '--expect-branch') a.expectBranch = need();
    else if (k === '--help' || k === '-h') { process.stdout.write('usage: check-committed-scope.mjs <path>... | --from-state | --from-stdin [--state <p>] [--rev <ref>] [--strict] [--json] [--expect-branch <branch>]\n'); process.exit(0); }
    else if (k.startsWith('--')) usage(`unknown argument ${k}`);
    else a.paths.push(k);
  }
  return a;
}

// CHANGE-0180 D4 — re-check the HEAD pin, when the caller opted in with
// --expect-branch. ADDITIVE: a caller that never passes the flag sees
// byte-identical behaviour (Spec-AC-04), and the check itself is a single
// early exit when no pin file exists at all (one `stat`, via branch-guard's
// own pinDirOrNull — F-4: NOT the `readPin` this comment used to cite, which
// no longer exists). Fails CLOSED before this script's real work (the git
// diff comparisons) so a HEAD moved out from under the ceremony refuses
// before comparing against the wrong commit. `expectBranch` is passed
// THROUGH to checkBranchPin (review NB-3) so a wrong/typo'd branch name is
// itself the thing compared, not merely a boolean opt-in for the pin file.
function verifyExpectedBranch(expectBranch) {
  if (!expectBranch) return;
  const result = checkBranchPin(process.cwd(), expectBranch);
  if (result.ok) return;
  process.stderr.write(`check-committed-scope: REFUSED (HEAD moved) — ${result.message}\n`);
  process.exit(3);
}

// STATE's code_review.scope is the list SKILL_PR already derives; reading it
// here keeps one definition of "in scope" rather than inventing a second.
//
// BLOCK SCALARS. state.mjs writes long values as `scope: >-` with the text on
// the following indented lines. Reading the header line alone yields the string
// ">-" — the first draft of this very script did exactly that and "checked" a
// path called `>-`. That is the third time in one session a line-level read of
// STATE was fooled by a folded scalar, which is the argument this whole scope
// makes: the fix belongs in the code, not in a note telling the next author to
// remember.
// telemetry-fields-not-prose D8: a scalar `key:` nested directly under a
// top-level `parentName:` block (2-space indent) — same line-scan discipline
// as the `code_review.scope` parent-tracking below (a same-named key under a
// DIFFERENT top-level block must never shadow this one).
function readNestedScalar(lines, parentName, key) {
  let parent = null;
  const re = new RegExp(`^ {2}${key}:\\s*(.*)$`);
  for (let n = 0; n < lines.length; n += 1) {
    const top = /^([A-Za-z_][\w-]*):/.exec(lines[n]);
    if (top) { parent = top[1]; continue; }
    if (parent !== parentName) continue;
    const m = re.exec(lines[n]);
    if (m) {
      const v = m[1].trim().replace(/^["']|["']$/g, '');
      return v === '' || v === 'null' ? null : v;
    }
  }
  return null;
}

function scopeFromState(statePath) {
  let text;
  try { text = fs.readFileSync(statePath, 'utf8'); } catch { return { paths: [], degraded: [`STATE not readable: ${statePath}`] }; }
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  // D8/Spec-AC-09: the preserved `code_review.scope` is an input to a LATER
  // step, not a verdict — but a scope preserved from an EARLIER ride's flush
  // must never be silently reused against the WRONG ref's diff. `scope_ref_id`
  // (D8 metrics-flush.mjs stamp) is used ONLY when it is absent (legacy STATE,
  // back-compat — pre-scope STATE never wrote the field) or equals the
  // CURRENT ride's `current_focus.ref_id`; otherwise this degrades naming
  // both refs rather than comparing a stale scope (M20 removes this check).
  const scopeRefId = readNestedScalar(lines, 'code_review', 'scope_ref_id');
  if (scopeRefId !== null) {
    const focusRefId = readNestedScalar(lines, 'current_focus', 'ref_id');
    if (scopeRefId !== focusRefId) {
      return {
        paths: [],
        degraded: [`code_review.scope_ref_id (${scopeRefId}) does not match current_focus.ref_id `
          + `(${focusRefId ?? 'null'}) — a preserved scope from a different ride is never reused; nothing checked`],
      };
    }
  }
  // The key must belong to `code_review:`, not merely be the first two-space
  // `scope:` in the file. STATE gains blocks over time and is hand-edited
  // downstream; review reproduced a `worktree.scope` shadowing the real one, so
  // the parent is tracked rather than assumed.
  let parent = null; let i = -1;
  for (let n = 0; n < lines.length; n += 1) {
    const top = /^([A-Za-z_][\w-]*):/.exec(lines[n]);
    if (top) { parent = top[1]; continue; }
    if (parent === 'code_review' && /^ {2}scope:/.test(lines[n])) { i = n; break; }
  }
  if (i < 0) return { paths: [], degraded: ['no code_review.scope in STATE — nothing to check'] };
  let raw = lines[i].replace(/^ {2}scope:\s*/, '').trim();
  if (/^[>|][+-]?$/.test(raw)) {
    const parts = [];
    for (let j = i + 1; j < lines.length; j += 1) {
      if (lines[j].trim() === '') { parts.push(''); continue; }
      if (!/^ {4}/.test(lines[j])) break;
      parts.push(lines[j].replace(/^ {4}/, ''));
    }
    raw = raw.startsWith('>') ? parts.join(' ').replace(/ {2,}/g, ' ').trim() : parts.join('\n').trim();
  }
  raw = raw.replace(/^["']|["']$/g, '');
  const tokens = raw.split(',').map((s) => s.trim()).filter(Boolean);
  if (tokens.length === 0) return { paths: [], degraded: ['code_review.scope is empty — nothing to check'] };

  // A DIFF RANGE is a documented scope form, not a path. PLANNING.prompt.md
  // says `--scope "<explicit paths or diff range>"`, so a scope of `main...HEAD`
  // is legal — and treating it as a filename made the guard report "nothing
  // checked" and, under --strict, block every such PR AFTER the commit was
  // already made (bot review, PR #349). A range is expanded to the paths it
  // names; a bare ref is left alone, because it cannot be told from a path.
  const paths = []; const degraded = [];
  for (const t of tokens) {
    if (!/^[^\s]+\.{2,3}[^\s]+$/.test(t)) { paths.push(t); continue; }
    const r = spawnSync('git', ['diff', '--name-only', '-z', t], { encoding: 'buffer', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
    if (r.error || r.status !== 0) {
      degraded.push(`code_review.scope carries the range ${t}, which git could not expand — nothing from it was checked`);
      continue;
    }
    const named = r.stdout.toString().split('\0').map((x) => x.trim()).filter(Boolean);
    if (!named.length) degraded.push(`code_review.scope range ${t} names no changed path`);
    paths.push(...named);
  }
  if (paths.length === 0 && degraded.length === 0) return { paths: [], degraded: ['code_review.scope is empty — nothing to check'] };
  return { paths, degraded };
}

// Is the path known to the comparison target at all? `git rev-parse --verify`
// on `<rev>:<rel>` (or `:<rel>` for the index) answers without reading content,
// so size is irrelevant here.
function isTracked(rev, rel, cwd) {
  const spec = rev ? `${rev}:${rel}` : `:${rel}`;
  try {
    execFileSync('git', ['rev-parse', '--verify', '--quiet', spec], { cwd, stdio: ['ignore', 'ignore', 'ignore'] });
    return true;
  } catch { return false; }
}

// git's own comparison: filter-aware (CRLF), mode-aware, symlink-aware, and it
// streams rather than buffering the blob. `:(literal)` stops a path containing
// glob characters from being read as a pathspec pattern.
// Returns 'same' | 'differs' | 'error:<code>'.
// Untracked files under an in-scope directory. `git diff` cannot see them.
function listUntracked(rel, cwd) {
  const r = spawnSync('git', ['ls-files', '--others', '--exclude-standard', '-z', '--', `:(literal)${rel}`],
    { cwd, stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 });
  if (r.error || r.status !== 0 || !r.stdout) return [];
  return r.stdout.toString().split('\0').map((x) => x.trim()).filter(Boolean);
}

function gitDiffers(rev, rel, cwd) {
  const args = ['diff', '--quiet'];
  if (rev) args.push(rev);
  args.push('--', `:(literal)${rel}`);
  const r = spawnSync('git', args, { cwd, stdio: ['ignore', 'ignore', 'pipe'] });
  if (r.error) return `error:${r.error.code || 'spawn'}`;
  if (r.status === 0) return 'same';
  if (r.status === 1) return 'differs';
  const msg = (r.stderr ? r.stderr.toString() : '').trim().split('\n')[0] || `git diff exited ${r.status}`;
  return `error:${msg}`;
}

// dispatch-state-sweep D15 (Spec-AC-17): the closed list of append-only
// ledgers, taken from HAZ-LEDGER in .aai/SUBAGENT_CONTRACT.md — not invented
// here. A path on this list growing at its own end is the benign shape most
// rides produce; a path NOT on this list, or one on this list whose
// committed blob is NOT a byte-exact prefix of the worktree, is a divergence
// exactly as today.
const LEDGER_PATHS = new Set([
  'docs/ai/EVENTS.jsonl',
  'docs/ai/decisions.jsonl',
  'docs/ai/tests/test-runs.jsonl',
]);

// The raw committed blob bytes for `rel` at `rev` (or the index when `rev` is
// null) — `git show`, never a hand-rolled read, for the same reason gitDiffers
// above delegates to git: filters, modes and link semantics are git's to get
// right. Returns null on any failure (missing blob, git error) — the caller
// treats null as "cannot establish a prefix", never as an empty file.
function committedBytes(rev, rel, cwd) {
  const spec = rev ? `${rev}:${rel}` : `:${rel}`;
  const r = spawnSync('git', ['show', spec], { cwd, encoding: 'buffer', maxBuffer: 256 * 1024 * 1024 });
  if (r.error || r.status !== 0) return null;
  return r.stdout;
}

// Byte-exact prefix test plus the added line count (newlines in the added
// tail — a JSONL ledger's own unit). Returns null when `committed` is not a
// byte-exact prefix of `worktree` (including a worktree SHORTER than the
// committed blob, which is a shrink, never an append) or either buffer is
// unavailable, else the number of appended lines (>= 0; an empty committed
// blob makes every worktree byte an append, per the spec's own edge case).
function appendedLineCount(committed, worktree) {
  if (committed === null || worktree === null) return null;
  if (worktree.length < committed.length) return null;
  if (!worktree.subarray(0, committed.length).equals(committed)) return null;
  const added = worktree.subarray(committed.length);
  let lines = 0;
  for (let i = 0; i < added.length; i += 1) if (added[i] === 0x0a) lines += 1;
  return lines;
}

function main() {
  const a = parseArgs(process.argv.slice(2));
  verifyExpectedBranch(a.expectBranch);
  if (a.fromStdin) {
    let raw = '';
    try { raw = fs.readFileSync(0, 'utf8'); } catch { raw = ''; }
    a.paths.push(...raw.split(/\0|\n/).map((s) => s.trim()).filter(Boolean));
  }
  const degraded = [];
  if (a.fromState) {
    const r = scopeFromState(a.state);
    a.paths.push(...r.paths); degraded.push(...r.degraded);
  }
  if (a.paths.length === 0 && degraded.length === 0) usage('no paths given (pass paths, --from-state or --from-stdin)');

  let root;
  try { root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim(); }
  catch { root = null; }
  if (!root) {
    const reason = 'not a git repository — cannot compare committed blobs';
    const out = { status: 'degraded', strict: a.strict, failed: a.strict, reason, mismatches: [], checked: 0, degraded: [reason] };
    process.stdout.write(a.json ? `${JSON.stringify(out)}\n` : `check-committed-scope: DEGRADED — ${reason}\n`);
    process.exit(a.strict ? 1 : 0);
  }

  // A --rev that does not resolve is a typo, not a degrade: every path would
  // then read "not in <rev>" and the plain mode would exit 0 on all of them.
  if (a.rev) {
    const rr = spawnSync('git', ['rev-parse', '--verify', '--quiet', `${a.rev}^{commit}`], { cwd: root, stdio: ['ignore', 'ignore', 'ignore'] });
    if (rr.status !== 0) usage(`--rev ${a.rev} does not resolve to a commit`);
  }

  const mismatches = []; const appends = []; const pendingAppends = []; let checked = 0;
  for (const rel of [...new Set(a.paths)]) {
    const abs = path.resolve(root, rel);
    let st = null;
    // lstat, not stat: a symlink — broken or not — is present, and its own
    // blob is the target string, which is what git compares.
    try { st = fs.lstatSync(abs); }
    catch (e) {
      if (e && e.code === 'ENOENT') { degraded.push(`${rel}: not on disk (deleted in the worktree?)`); continue; }
      degraded.push(`${rel}: unreadable (${(e && e.code) || 'error'})`); continue;
    }
    // A directory in scope has no blob of its own; git diff still compares
    // everything under it, which is the useful answer.
    if (!st.isDirectory() && !isTracked(a.rev, rel, root)) {
      degraded.push(`${rel}: not in ${a.rev ? a.rev : 'the index'} — untracked or unstaged, so nothing to compare`);
      continue;
    }
    // `git diff` is blind to untracked files, so a directory in scope holding a
    // file that was never added compares clean — and a never-added file is the
    // drop shape this guard exists to catch (a regenerated page, a review report
    // the aborted `git add` left behind). Round-two review reproduced exactly
    // that: scope `docs/ai/reviews` with an unstaged REPORT.md reported clean.
    if (st.isDirectory()) {
      const stray = listUntracked(rel, root);
      for (const u of stray) mismatches.push(u);
      if (stray.length) { checked += 1; continue; }
    }
    const verdict = gitDiffers(a.rev, rel, root);
    if (verdict.startsWith('error:')) { degraded.push(`${rel}: git could not compare it (${verdict.slice(6)})`); continue; }
    checked += 1;
    if (verdict !== 'differs') continue;
    // D15/Spec-AC-17: a ledger path that differs is not automatically a
    // divergence — the committed blob growing at its own end (an append) is
    // the benign shape most rides produce, and a gate that cannot tell it
    // from a rewrite is one people learn to wave through. Only a path ON
    // the closed list gets this treatment; everything else fails exactly
    // as today.
    if (LEDGER_PATHS.has(rel) && !st.isDirectory()) {
      const committed = committedBytes(a.rev, rel, root);
      let worktree = null;
      try { worktree = fs.readFileSync(abs); } catch { worktree = null; }
      const addedLines = appendedLineCount(committed, worktree);
      if (addedLines !== null) {
        appends.push({ path: rel, added_lines: addedLines });
        // Round 6 (Codex P1): --strict means "the working tree equals the
        // commit for every in-scope path" — an append the commit does not
        // yet carry is real content still missing from HEAD, not a benign
        // shape. Non-strict keeps this purely advisory (append recorded,
        // never a mismatch); --strict promotes it to a named MISMATCH so
        // `--strict --rev HEAD` cannot exit 0 while a required ledger
        // record (e.g. the run evidence a spec amendment depends on) sits
        // uncommitted in the worktree.
        if (a.strict) { mismatches.push(rel); pendingAppends.push(rel); }
        continue;
      }
    }
    mismatches.push(rel);
  }

  // A degrade is a failure under --strict, and "clean" is never printed for a
  // run that verified nothing: the last line of the output is what a human or a
  // grep reads, and `clean — 0 path(s)` after a list of degrades is a lie.
  const failed = mismatches.length > 0 || (a.strict && (degraded.length > 0 || checked === 0));
  const out = {
    status: mismatches.length ? 'mismatch' : (degraded.length ? 'degraded' : (checked === 0 ? 'nothing-checked' : 'clean')),
    strict: a.strict, failed, checked, mismatches, degraded, appends, pending_appends: pendingAppends,
  };
  if (a.json) process.stdout.write(`${JSON.stringify(out, null, 2)}\n`);
  else {
    for (const d of degraded) process.stdout.write(`check-committed-scope: degraded — ${d}\n`);
    for (const ap of appends) {
      const suffix = pendingAppends.includes(ap.path)
        ? '— --strict requires it committed, not just on disk'
        : '— not a failure';
      process.stdout.write(`check-committed-scope: append — ${ap.path} (+${ap.added_lines} line(s), append-only per HAZ-LEDGER ${suffix})\n`);
    }
    if (mismatches.length) {
      process.stderr.write(`check-committed-scope: ${mismatches.length} in-scope path(s) differ between ${a.rev ? a.rev : 'the index'} and the worktree:\n`);
      for (const m of mismatches) {
        // D15/Round 6: a ledger path that failed the byte-exact-prefix test
        // is a DIVERGENCE (a rewrite); a ledger path that PASSED it but is
        // still uncommitted under --strict is a PENDING APPEND (real content
        // the commit does not carry yet) — two different causes, named
        // differently, so a reader (or a grep) knows which one it is.
        const label = pendingAppends.includes(m) ? ' (pending append not committed)'
          : LEDGER_PATHS.has(m) ? ' (divergence — not an append)' : '';
        process.stderr.write(`  - ${m}${label}\n`);
      }
      process.stderr.write('The commit does NOT carry what the worktree holds. The usual cause is a\n`git add` given a path something already renamed: the whole add aborts, and the\ncommit still looks plausible because other steps stage files of their own.\nRe-stage these paths and amend, or commit them, before pushing.\n');
    } else if (checked === 0) {
      process.stdout.write(`check-committed-scope: NOTHING CHECKED — no in-scope path could be compared against ${a.rev ? a.rev : 'the index'}\n`);
    } else if (degraded.length) {
      process.stdout.write(`check-committed-scope: ${checked} path(s) match ${a.rev ? a.rev : 'the index'}, ${degraded.length} could NOT be compared (named above)\n`);
    } else {
      process.stdout.write(`check-committed-scope: clean — ${checked} path(s) match ${a.rev ? a.rev : 'the index'}\n`);
    }
    if (failed && !mismatches.length) {
      process.stderr.write('--strict: a path that could not be compared is not a path that matches.\nThe aborted `git add` this guard exists to catch drops EVERY path in that\ncommand, and an untracked one lands here rather than in the mismatch list.\n');
    }
  }
  process.exit(failed ? 1 : 0);
}

main();
