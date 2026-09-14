#!/usr/bin/env node
// branch-guard.mjs — deterministic branch-per-work-item hygiene guard
// (SPEC-0070-spec-branch-per-work-item-hygiene).
//
// Fails CLOSED before a PR push when the current git branch does not correspond
// to the current work item (current_focus.ref_id). The inline (L0-L2) path never
// created or checked a dedicated branch, so SKILL_PR could push whatever branch
// happened to be checked out onto a stale/shared line. This guard is the
// deterministic chokepoint SKILL_PR runs as its "0. BRANCH HYGIENE" precondition.
//
// READ-ONLY: it reads the current branch via `git rev-parse` and
// current_focus.ref_id/.type from STATE.yaml using the SAME read-only line-engine
// helpers orchestration-dispatch.mjs already imports (splitLines / readScalar /
// unquoteScalar). It NEVER writes STATE.yaml or any file — Constitution Art. 6
// (single writer is state.mjs) is preserved.
//
// CLI: node branch-guard.mjs [--base <branch>] [--suggest] [--state <path>]
//                             [--pin] [--verify-pin]
//   --base <branch>  base branch to compare against; default `main`.
//   --state <path>   override the STATE.yaml path; default
//                    <git-toplevel>/docs/ai/STATE.yaml (works from any subdir).
//   --suggest        print the canonical `<type-token>/<ref-id>` to stdout and
//                    exit; performs NO git-branch check (meant to run before the
//                    branch exists). Still reads STATE — a broken/empty ref_id
//                    exits 4, never a silent pass.
//   --pin            record the current branch + HEAD sha + pid + worktree at
//                    `$(git rev-parse --git-dir)/aai/branch-pin.json`
//                    (CHANGE-0180 D4). Per-worktree by construction — never
//                    shared across a linked worktree — and structurally
//                    uncommittable, so it owes no `.gitignore` entry. Exit 0
//                    on success.
//   --verify-pin     re-read the pin and compare it to the CURRENT branch +
//                    HEAD sha. No pin file at all -> exit 0 (a ceremony that
//                    never pinned is unaffected — CHANGE-0180 AC-004 — and
//                    this costs exactly one `stat`). A pin that still matches
//                    -> exit 0. A mismatch names the expected and the actual
//                    value and distinguishes THREE causes rather than
//                    collapsing them (CHANGE-0180 AC-003):
//                      exit 5 — HEAD is now detached.
//                      exit 6 — the pinned branch no longer exists as a ref
//                               (renamed or removed under this session).
//                      exit 7 — the pinned branch still exists, but HEAD now
//                               points elsewhere (a concurrent session moved
//                               HEAD in this same worktree, or reset/rebased
//                               this same branch name to a different sha).
//   `checkBranchPin(cwd, expectBranch)` (exported, not a CLI flag) is the
//   same check as `--verify-pin` (which calls it with no `expectBranch`),
//   returned as a plain result object rather than an exit, so the three
//   ceremony scripts that still stand between the agent and a git write
//   (check-committed-scope.mjs, close-before-push-guard.mjs,
//   close-work-item.mjs) can reuse ONE implementation behind their own
//   `--expect-branch` re-check rather than each re-deriving the pin logic
//   (Article 2 — one new lib module in this scope is the session lock, not a
//   second copy of this). Passing `expectBranch` does TWO things a bare
//   `--verify-pin` call does not (remediation round 4, validation-round4.txt
//   BLOCKING-1 + review NB-3): the branch itself is compared against the
//   ARGUMENT, not silently `pin.branch` (closing NB-3 — a wrong/typo'd
//   `--expect-branch` used to be indistinguishable from the correct one);
//   and a same-branch HEAD sha that is a git-ancestor DESCENDANT of the
//   pinned sha is read as the ceremony's own commit, not a concurrent move,
//   and passes — bare `--verify-pin` keeps the original exact-sha-match
//   reading (see `checkBranchPin`'s own header comment below for why this is
//   scoped to `expectBranch` callers only).
//
// A branch may also legitimately have NO work item — a chore, a release cut, or
// a docs-only edit. Such branches carry a recognized non-work-item PREFIX
// (ALLOWLIST_PREFIXES: `chore/`, `release/`, `docs/`) and pass (exit 0) with a
// distinct message, once the guard has confirmed the branch is not the base and
// STATE is readable. This splits the STATE read into two tiers:
//   Tier A — STATE cannot be opened/read at all (missing/corrupt): fails closed
//            EVERYWHERE, even on an allowlisted branch (order item 3).
//   Tier B — STATE opens fine but records no focus (ref_id empty/null): fails
//            closed for non-allowlisted branches (item 6), but an allowlisted
//            branch still passes (item 5).
//
// Deterministic check order (guard mode) — EARLIER checks win:
//   1. cwd not inside a git work tree              -> exit 4
//   2. HEAD detached (`git rev-parse --abbrev-ref HEAD` == "HEAD") -> exit 2
//   3. Tier A — STATE cannot be opened/read at all -> exit 4 (unconditional)
//   4. current branch == base branch:
//        4a. ref_id empty/null (Tier B)            -> exit 4
//        4b. ref_id set                            -> exit 1
//   5. current branch matches an ALLOWLIST_PREFIX  -> exit 0 (non-work-item pass)
//   6. Tier B on a non-allowlisted branch          -> exit 4
//   7. current branch does NOT contain ref_id      -> exit 3
//   8. otherwise                                   -> exit 0
//
// Exit codes (closed set):
//   0 — branch matches current_focus.ref_id, OR is a recognized non-work-item
//       branch (allowlisted prefix); neither base nor detached.
//   1 — current branch equals the base branch.
//   2 — HEAD is detached.
//   3 — current branch name does not contain the ref_id slug.
//   4 — config/usage error (not a git repo, STATE unreadable, ref_id empty/null
//       on a non-allowlisted branch, bad flag).
//
// --verify-pin's own exit codes (guard-mode 0-4 above do not apply to it):
//   0 — no pin file (nothing to verify), or the pin still matches.
//   5 — HEAD is detached under a pin.
//   6 — the pinned branch was renamed/removed under the session.
//   7 — a concurrent session moved HEAD (the pinned branch still exists).
//   8 — the pin file exists but is unreadable/malformed (a partial or
//       corrupted write) — NEVER treated as "no pin" (round 8 / Codex P1).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { splitLines } from './lib/state-core.mjs';
import { readScalar, unquoteScalar } from './lib/state-engine.mjs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

// Recognized NON-work-item branch prefixes. A CLOSED allowlist: a branch whose
// name starts with one of these legitimately has no work item to verify against
// (chores, release cuts, doc-only edits), so the guard passes it (exit 0) once
// it has established the branch is NOT the base branch and STATE is readable.
// The trailing slash is baked in on purpose so `choreography/x` does NOT match
// `chore/` (segment-safe prefix match). Work-item type tokens (`feat/`, `fix/`)
// are DELIBERATELY excluded — those must still contain the current ref_id.
const ALLOWLIST_PREFIXES = ['chore/', 'release/', 'docs/'];

// Return the allowlisted prefix a branch name starts with, or null.
function matchAllowlistPrefix(branch) {
  return ALLOWLIST_PREFIXES.find((p) => branch.startsWith(p)) ?? null;
}

// current_focus.type -> branch type-token. Closed + deterministic; used ONLY to
// build the --suggest output and the remediation string. Any unmapped/blank
// value falls back to `chore` (never throws).
const TYPE_TOKENS = {
  intake_issue: 'fix',
  intake_hotfix: 'fix',
  intake_change: 'feat',
  intake_prd: 'feat',
  intake_rfc: 'feat',
  intake_release: 'chore',
  intake_research: 'chore',
  technology_extraction: 'chore',
  maintenance: 'chore',
  none: 'chore',
};

function typeToken(type) {
  return TYPE_TOKENS[type] ?? 'chore';
}

// Copy-pasteable remediation, identical shape on every non-zero exit. refId may
// be null on a detached-HEAD exit that precedes the STATE read — fall back to the
// literal `<ref-id>` placeholder so the line is still shape-correct and useful.
function remediation(type, refId, base) {
  return `git checkout -b ${typeToken(type)}/${refId ?? '<ref-id>'} origin/${base}`;
}

// The absent-STATE bootstrap route (CHANGE-0099 / state-bootstrap-template,
// verified end to end by state-route-exists-but-is-undiscoverable): STATE.yaml
// does not exist yet, so there is no ref_id to compare a branch against at
// all — printing "is not set in STATE.yaml" here would be false (there is no
// STATE.yaml), and today's `remediation()` checkout suggestion fixes nothing
// (it never creates the file), so the SAME Tier-A failure repeats forever.
// These two commands are the actual, already-shipped fix.
function bootstrapHint() {
  return [
    'node .aai/scripts/check-state.mjs --repair',
    'node .aai/scripts/state.mjs set-focus --type <type> --ref <ref-id> --path <primary-path>',
  ];
}

function git(args, cwd) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
}

// Why this captures stderr instead of discarding it: git refuses a repository
// for several distinct reasons and says which one every time — "not a git
// repository", "detected dubious ownership" (the safe.directory case, which
// prints the exact `git config --global --add safe.directory ...` fix), a
// permission error, a broken gitdir link. Swallowing all of them and printing
// one sentence turned a solvable ownership refusal into "not inside a git work
// tree", which is not even true: the caller IS inside a work tree, git just
// declined to read it. Reported from a downstream Codex run on Windows where
// the operator lost time to the false diagnosis before finding safe.directory
// themselves (fu-branchguard-hides-git-stderr).
// git prints a fatal for BOTH "there is no repository here" and "there is one
// and I refuse to read it", so the presence of stderr cannot tell them apart —
// and calling the ordinary no-repository case a refusal is its own false
// diagnosis. Discriminate structurally instead of by matching git's wording,
// which differs across versions and platforms: walk up for a .git entry. One
// exists => something IS here and git declined it (ownership, a dangling
// gitdir link, permissions) => relay git's message. None => the caller is
// simply not in a repository, and the plain sentence is the honest answer.
function repoMarkerAbove(cwd) {
  let dir = path.resolve(cwd);
  for (;;) {
    if (fs.existsSync(path.join(dir, '.git'))) return true;
    const parent = path.dirname(dir);
    if (parent === dir) return false;
    dir = parent;
  }
}

function workTreeProbe(cwd) {
  try {
    const out = execFileSync('git', ['rev-parse', '--is-inside-work-tree'], {
      cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
    return { inside: out === 'true', refused: false, gitSaid: null };
  } catch (err) {
    const said = String((err && err.stderr) || '').trim();
    return { inside: false, refused: repoMarkerAbove(cwd), gitSaid: said || null };
  }
}

function topLevel(cwd) {
  return git(['rev-parse', '--show-toplevel'], cwd);
}

function currentBranch(cwd) {
  return git(['rev-parse', '--abbrev-ref', 'HEAD'], cwd);
}

// Read current_focus.ref_id/.type from STATE (read-only). Returns
// { ok, fileReadable, exists, refId, type }. Two distinct failure tiers:
//   Tier A — fileReadable:false — the file could not be opened/read at all.
//            Fails closed EVERYWHERE, even on an allowlisted branch. `exists`
//            splits this tier further (fu-no-state-no-route-to-pr / the
//            state-route-exists-but-is-undiscoverable follow-up): exists:false
//            means STATE.yaml was never created (the bootstrap route —
//            `check-state.mjs --repair` then `state.mjs set-focus` — has not
//            been run yet); exists:true means the path is there but
//            fs.readFileSync still failed (a directory in its place,
//            permissions, or some other fs-level refusal) — a strictly more
//            suspicious situation the caller must NOT hand the same
//            create-a-fresh-file advice, because `check-state.mjs --repair`
//            only ever creates the file `if (!fs.existsSync(abs))` and would
//            silently do nothing to it.
//   Tier B — fileReadable:true, ok:false — the file opened fine but carries no
//            focus (ref_id empty/null, including a file whose content is
//            present but unparseable-as-YAML — readScalar simply finds no
//            ref_id in it). Fails closed for non-allowlisted branches, but an
//            allowlisted-prefix branch may still pass.
// `ok` stays true only when a non-empty ref_id was found. Never throws.
function readFocus(statePath) {
  const exists = fs.existsSync(statePath);
  let raw;
  try {
    raw = fs.readFileSync(statePath, 'utf8');
  } catch {
    return { ok: false, fileReadable: false, exists, refId: null, type: null };
  }
  const { lines } = splitLines(raw);
  const refRaw = readScalar(lines, 'current_focus', 'ref_id');
  const typeRaw = readScalar(lines, 'current_focus', 'type');
  const refId = refRaw == null ? null : unquoteScalar(refRaw);
  const type = typeRaw == null ? null : unquoteScalar(typeRaw);
  if (refId == null || refId === '') return { ok: false, fileReadable: true, exists: true, refId: null, type };
  return { ok: true, fileReadable: true, exists: true, refId, type };
}

function parseArgs(argv) {
  const opts = { base: 'main', suggest: false, state: null, pin: false, verifyPin: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--base' || tok === '--state') {
      const v = argv[i + 1];
      if (!v || v.startsWith('--')) {
        console.error(`branch-guard: ${tok} requires a value`);
        exit(4);
      }
      opts[tok.slice(2)] = v;
      i += 1;
    } else if (tok === '--suggest') {
      opts.suggest = true;
    } else if (tok === '--pin') {
      opts.pin = true;
    } else if (tok === '--verify-pin') {
      opts.verifyPin = true;
    } else if (tok === '-h' || tok === '--help') {
      console.error('Usage: node branch-guard.mjs [--base <branch>] [--suggest] [--state <path>] [--pin] [--verify-pin]');
      exit(4);
    } else {
      console.error(`branch-guard: unknown flag "${tok}"`);
      exit(4);
    }
  }
  return opts;
}

// Resolve the STATE.yaml path: an explicit --state wins; otherwise
// <git-toplevel>/docs/ai/STATE.yaml. Returns null when neither is resolvable.
function resolveStatePath(opts, cwd) {
  if (opts.state) return path.resolve(cwd, opts.state);
  try {
    return path.join(topLevel(cwd), 'docs/ai/STATE.yaml');
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// HEAD pin (CHANGE-0180 D4). Per-worktree by construction: `git rev-parse
// --git-dir` resolves to a DISTINCT path for the main checkout and for every
// linked worktree (never one shared path), so the pin lives at
// `<that>/aai/branch-pin.json` — the same directory session-lock.mjs uses for
// its own lock (D5), structurally uncommittable, owing no `.gitignore` entry.
// ---------------------------------------------------------------------------

const PIN_FILENAME = 'branch-pin.json';

// pinDirFast — resolves the git-dir via fs stats only (no `git` subprocess),
// so the no-pin path genuinely costs one stat as D4 and the header comment
// above claim (validation round 1 BLOCKING-1: the ORIGINAL pinDir always
// forked `git rev-parse --git-dir` first, even when no pin file existed —
// measured with a git shim, one subprocess on a no-pin fixture). Handles
// the two shapes `git rev-parse --git-dir` resolves for a normal
// repo-root invocation: a main checkout's `.git` DIRECTORY, and a linked
// worktree's `.git` FILE (`gitdir: <path>`, always written absolute by
// git itself). Returns null — never guesses, never walks up parent
// directories — for anything else (bare repo, GIT_DIR override, cwd not at
// the repo root, an unreadable/malformed `.git` file), so the caller can
// fall back to the authoritative `git rev-parse --git-dir` and correctness
// never trades against the stat-only promise.
function pinDirFast(cwd) {
  // NON-BLOCKING (validation round 2): a GIT_DIR override used to be
  // silently ignored here when cwd also happened to hold its own `.git`
  // directory — this function resolved against the LOCAL `.git` and never
  // fell back to the authoritative `git rev-parse`, contradicting the
  // "never guesses ... GIT_DIR override" comment below and changing the
  // pre-change pinDir's behaviour, which always went through git and
  // therefore honoured GIT_DIR. Deferring to the git fallback whenever
  // GIT_DIR is set keeps the fast path's promise scoped to the one case it
  // can resolve correctly without a subprocess.
  if (process.env.GIT_DIR) return null;
  const dotGit = path.join(cwd, '.git');
  let st;
  try {
    st = fs.lstatSync(dotGit);
  } catch {
    return null;
  }
  if (st.isDirectory()) {
    return path.join(dotGit, 'aai');
  }
  if (st.isFile()) {
    let content;
    try {
      content = fs.readFileSync(dotGit, 'utf8');
    } catch {
      return null;
    }
    const m = /^gitdir:\s*(.+?)\s*$/m.exec(content);
    if (!m) return null;
    const gd = path.isAbsolute(m[1]) ? m[1] : path.resolve(cwd, m[1]);
    return path.join(gd, 'aai');
  }
  return null;
}

// pinDirOrNull — like pinDir, but returns null instead of throwing when the
// git fallback itself fails (cwd is not inside a git work tree at all: no
// repo, or a repo git declines to read). NON-BLOCKING (review NB-2): the
// original pinDir's git() fallback had no try/catch, so any caller that
// reached it outside a work tree — checkBranchPin included — crashed with a
// raw uncaught exception instead of a named refusal in the documented exit
// set. checkBranchPin uses this form so it can report the condition rather
// than crash; pinDir (below) keeps the throwing contract for its own callers,
// which are only reached once main() has already confirmed a work tree.
function pinDirOrNull(cwd) {
  const fast = pinDirFast(cwd);
  if (fast !== null) return fast;
  try {
    return path.join(path.resolve(cwd, git(['rev-parse', '--git-dir'], cwd)), 'aai');
  } catch {
    return null;
  }
}

function pinDir(cwd) {
  const dir = pinDirOrNull(cwd);
  if (dir === null) {
    throw new Error('branch-guard: pinDir: not inside a git work tree');
  }
  return dir;
}

function pinFilePath(cwd) {
  return path.join(pinDir(cwd), PIN_FILENAME);
}

function refExists(cwd, branch) {
  try {
    execFileSync('git', ['show-ref', '--verify', '--quiet', `refs/heads/${branch}`], { cwd, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function doPin(cwd) {
  const branch = currentBranch(cwd);
  if (branch === 'HEAD') {
    console.error('branch-guard: cannot --pin a detached HEAD (check out a branch first).');
    exit(4);
  }
  const sha = git(['rev-parse', 'HEAD'], cwd);
  const dir = pinDir(cwd);
  fs.mkdirSync(dir, { recursive: true });
  const payload = {
    branch,
    sha,
    pid: process.pid,
    worktree: topLevel(cwd),
    pinned_utc: new Date().toISOString(),
  };
  // Atomic write (Codex P1 finding, round 8): a plain writeFileSync interrupted
  // mid-write (crash, kill -9) leaves a TRUNCATED/partial file on disk, which
  // checkBranchPin below must refuse rather than silently read as "no pin"
  // (Spec-AC-04 is about a pin that was never taken, not one that was taken
  // and then torn). tmp-write + rename is atomic on the same filesystem (both
  // live under the same git-dir-derived pin directory), so a reader never
  // observes a partial file at the real path.
  const finalPath = pinFilePath(cwd);
  const tmpPath = `${finalPath}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmpPath, JSON.stringify(payload));
  fs.renameSync(tmpPath, finalPath);
  console.log(`branch-guard: pinned branch "${branch}" at ${sha}`);
  exit(0);
}

// isAncestor(cwd, ancestorSha, descendantSha) -> true when ancestorSha is
// reachable from descendantSha (a commit counts as its own ancestor). Used
// ONLY by the advance-only sha arm below. Fails CLOSED: any git error (an
// unresolvable/pruned sha included) reads as "not an ancestor", never a
// silent pass.
function isAncestor(cwd, ancestorSha, descendantSha) {
  try {
    execFileSync('git', ['merge-base', '--is-ancestor', ancestorSha, descendantSha], { cwd, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

// checkBranchPin(cwd, expectBranch) -> {ok:true} | {ok:false, code, cause, message}
// PURE — never calls exit() — so both `--verify-pin` (below) and the three
// ceremony scripts' `--expect-branch` re-check can share this ONE
// implementation and map the result to their own exit codes. `expectBranch`
// is OPTIONAL and OMITTED by `--verify-pin` (which has no argument to
// compare); passed by the three ceremony scripts' own `--expect-branch
// <branch>` flag.
//   code 0 / ok:true  — no pin, or the pin still matches current HEAD.
//   code 4, cause 'no-work-tree' — cwd is not inside a git work tree at all
//                               (review NB-2): a NAMED refusal instead of the
//                               uncaught exception pinDir's git() fallback
//                               used to throw here. Every caller of this
//                               function already has a !ok branch that
//                               prints result.message and exits with its own
//                               code, so this reuses that path rather than
//                               adding a new one.
//   code 5, cause 'detached'  — HEAD is now detached.
//   code 6, cause 'renamed'   — the expected branch no longer exists as a ref.
//   code 7, cause 'concurrent'— the expected branch still exists; HEAD moved
//                               elsewhere (another session, this same branch
//                               name reset/rebased off the pinned sha, or —
//                               with no pin at all — `expectBranch` itself
//                               naming a branch HEAD is not currently on).
//   code 8, cause 'malformed-pin' — the pin file EXISTS but could not be
//                               read/parsed/validated (round 8 / Codex P1):
//                               distinct from "no pin" (ENOENT, which stays
//                               ok:true above) precisely because a torn
//                               write is MOST likely mid-ceremony, exactly
//                               when this gate matters most — guessing "no
//                               pin" here would silently disable it.
//
// review NB-3: the branch this check holds the ceremony to is `expectBranch`
// itself when given, never silently `pin.branch` — closing the gap where the
// flag was accepted but never actually compared (a typo'd or plain wrong
// --expect-branch used to produce byte-identical output to the correct one,
// because only its presence, not its value, mattered).
//
// remediation round 4 BLOCKING-1: with a pin AND `expectBranch` both present
// (i.e. only at the three ceremony call sites, never bare `--verify-pin`),
// a HEAD sha that has moved FORWARD on the expected branch — a DESCENDANT of
// the pinned sha — is the ceremony's OWN commit (steps 4/4c/5c), not a
// concurrent session, and is tolerated. This is deliberately scoped to
// `expectBranch` callers only: bare `--verify-pin` (no expectBranch) keeps
// the exact-sha-match reading Spec-AC-03 originally specified and TEST-405
// still exercises (a same-branch new commit, from ANY source, still refuses
// under `--verify-pin`) — advance-only tolerance is granted only to a caller
// that identifies itself as the pinning ceremony re-checking its own work.
function checkBranchPin(cwd, expectBranch = null) {
  const dir = pinDirOrNull(cwd);
  if (dir === null) {
    return {
      ok: false,
      code: 4,
      cause: 'no-work-tree',
      message: 'not inside a git work tree (cannot verify the HEAD pin).',
    };
  }
  // Codex P1 finding (round 8): ENOENT ("no pin was ever taken") and a
  // present-but-unreadable/malformed file (an interrupted --pin write, or
  // any other corruption) used to collapse to the SAME `pin = null` and the
  // SAME Spec-AC-04 "no pin, complete no-op" exit 0 — silently disabling
  // every `--expect-branch` ceremony gate exactly when a concurrent HEAD
  // move is most likely (mid-write). Distinguish them: ENOENT is the ONLY
  // case that reads as "no pin"; anything else refuses (code 8) instead of
  // guessing. readFileSync (not existsSync + a separate read) closes the
  // TOCTOU gap between the two.
  const pinPath = path.join(dir, PIN_FILENAME);
  let raw;
  try {
    raw = fs.readFileSync(pinPath, 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') {
      // Spec-AC-04: no pin file at all -> exit 0 without reading git, a
      // complete no-op regardless of `expectBranch` — a caller cannot
      // compare its argument against a pin that was never taken.
      return { ok: true, code: 0, cause: null };
    }
    return {
      ok: false,
      code: 8,
      cause: 'malformed-pin',
      message: `the HEAD pin at ${pinPath} could not be read (${e && e.code ? e.code : e.message}) — refusing rather than treating this as "no pin".`,
    };
  }
  let pin;
  try {
    pin = JSON.parse(raw);
  } catch {
    return {
      ok: false,
      code: 8,
      cause: 'malformed-pin',
      message: `the HEAD pin at ${pinPath} exists but is not valid JSON (a partial or corrupted write) — refusing rather than treating this as "no pin"; remove it and re-run --pin once it is safe to discard.`,
    };
  }
  if (!pin || typeof pin !== 'object' || typeof pin.branch !== 'string' || typeof pin.sha !== 'string') {
    return {
      ok: false,
      code: 8,
      cause: 'malformed-pin',
      message: `the HEAD pin at ${pinPath} is missing required fields (branch/sha) — refusing rather than treating this as "no pin".`,
    };
  }

  const wantBranch = expectBranch || pin.branch;
  const branch = currentBranch(cwd);
  if (branch === 'HEAD') {
    return {
      ok: false,
      code: 5,
      cause: 'detached',
      message: `HEAD is detached (expected branch "${wantBranch}" at ${pin.sha}); check out a branch before continuing.`,
    };
  }

  if (branch !== wantBranch) {
    const sha = git(['rev-parse', 'HEAD'], cwd);
    if (!refExists(cwd, wantBranch)) {
      return {
        ok: false,
        code: 6,
        cause: 'renamed',
        message: `branch "${wantBranch}" was renamed or removed under this session (now on "${branch}" at ${sha}; expected "${wantBranch}" at ${pin.sha}).`,
      };
    }
    return {
      ok: false,
      code: 7,
      cause: 'concurrent',
      message: `a concurrent session changed HEAD (expected branch "${wantBranch}" at ${pin.sha}; actual branch "${branch}" at ${sha}).`,
    };
  }

  const sha = git(['rev-parse', 'HEAD'], cwd);
  if (sha === pin.sha) return { ok: true, code: 0, cause: null };
  if (expectBranch && isAncestor(cwd, pin.sha, sha)) return { ok: true, code: 0, cause: null };

  return {
    ok: false,
    code: 7,
    cause: 'concurrent',
    message: `a concurrent session changed HEAD (expected branch "${wantBranch}" at ${pin.sha}; actual branch "${branch}" at ${sha}).`,
  };
}

function doVerifyPin(cwd) {
  const result = checkBranchPin(cwd);
  if (result.ok) exit(0);
  console.error(`branch-guard: HEAD moved — ${result.message}`);
  exit(result.code);
}

// reportNotInWorkTree(probe) — the two-shaped message workTreeProbe's result
// maps to (git declined to read vs. genuinely no repository here). Shared by
// every dispatch point that needs it so the wording stays in one place.
function reportNotInWorkTree(probe) {
  if (probe.refused) {
    console.error('branch-guard: git refused to read this repository, so the current branch cannot be determined.');
    if (probe.gitSaid) {
      console.error('  git said:');
      for (const line of probe.gitSaid.split('\n')) console.error(`    ${line}`);
    }
  } else {
    console.error('branch-guard: not inside a git work tree (cannot determine the current branch)');
  }
}

function main() {
  const opts = parseArgs(process.argv);
  const cwd = process.cwd();

  // --pin / --verify-pin are their own modes, dispatched before every other
  // check below (guard-mode, --suggest): neither reads STATE or the ref_id at
  // all, and Spec-AC-04's own control is that NEITHER flag given leaves every
  // byte of the rest of this function's behaviour unchanged. NON-BLOCKING
  // (review NB-2): both still need a git work tree to do anything at all
  // (doPin/doVerifyPin/checkBranchPin all eventually shell out to git), so
  // this checks that FIRST and exits with the same named exit-4 refusal
  // guard mode uses below, instead of letting an uncaught exception through.
  if (opts.pin || opts.verifyPin) {
    const pinProbe = workTreeProbe(cwd);
    if (!pinProbe.inside) {
      reportNotInWorkTree(pinProbe);
      exit(4);
    }
  }
  if (opts.pin) doPin(cwd);
  if (opts.verifyPin) doVerifyPin(cwd);

  // --suggest — no git-branch check; still reads STATE (fail-closed on ref_id).
  if (opts.suggest) {
    const statePath = resolveStatePath(opts, cwd);
    if (!statePath) {
      console.error('branch-guard: cannot resolve STATE.yaml (not a git repo and no --state given)');
      exit(4);
    }
    const focus = readFocus(statePath);
    if (!focus.ok) {
      console.error('branch-guard: current_focus.ref_id is not set in STATE.yaml');
      exit(4);
    }
    console.log(`${typeToken(focus.type)}/${focus.refId}`);
    exit(0);
  }

  // Order item 1 — must be inside a git work tree. Two different failures live
  // here and they deserve different answers: a repository git DECLINED to read
  // (relay git's own message — for safe.directory it carries the exact fix),
  // and no repository at all (the plain sentence, which is then true).
  const probe = workTreeProbe(cwd);
  if (!probe.inside) {
    reportNotInWorkTree(probe);
    exit(4);
  }

  // Order item 2 — detached HEAD wins over the STATE read (best-effort remediation).
  const branch = currentBranch(cwd);
  if (branch === 'HEAD') {
    const statePath = resolveStatePath(opts, cwd);
    const focus = statePath ? readFocus(statePath) : { type: null, refId: null };
    console.error('branch-guard: HEAD is detached — no work-item branch is checked out.');
    console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    exit(2);
  }

  // Order item 3 — Tier A: STATE cannot be opened/read at all -> fail closed,
  // unconditionally, before the branch name is even inspected. This is the ONLY
  // STATE-read failure that still blocks an allowlisted branch.
  const statePath = resolveStatePath(opts, cwd);
  const focus = statePath
    ? readFocus(statePath)
    : { ok: false, fileReadable: false, exists: false, type: null, refId: null };
  if (!focus.fileReadable) {
    if (!focus.exists) {
      // Absent, not corrupt: there is no STATE.yaml at all, so "ref_id is not
      // set in STATE.yaml" would be false (there is no STATE.yaml to set it
      // in), and the usual checkout remediation fixes nothing. Name the
      // already-shipped bootstrap route instead.
      console.error('branch-guard: STATE.yaml does not exist yet (cannot verify the branch).');
      console.error('  Remediation:');
      for (const step of bootstrapHint()) console.error(`    ${step}`);
    } else {
      // The path exists but could still not be opened/read (a directory in
      // its place, a permissions refusal, ...) — a strictly more suspicious
      // situation than "absent". `check-state.mjs --repair` only creates the
      // file `if (!fs.existsSync(abs))`, so suggesting it here would be
      // actively wrong: it would silently do nothing, and the operator would
      // believe they had fixed it. Keep today's cautious fail-closed text.
      console.error('branch-guard: current_focus.ref_id is not set in STATE.yaml (cannot verify the branch).');
      console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    }
    exit(4);
  }

  // Order item 4 — current branch equals the base branch. Checked BEFORE the
  // allowlist so a branch that is simultaneously the base and allowlist-shaped
  // still never passes. 4a: cleared ref_id (Tier B) -> exit 4 (unchanged from
  // today). 4b: ref_id set -> exit 1 (base-branch violation).
  if (branch === opts.base) {
    if (!focus.ok) {
      console.error('branch-guard: current_focus.ref_id is not set in STATE.yaml (cannot verify the branch).');
      console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
      exit(4);
    }
    console.error(`branch-guard: on the base branch "${opts.base}" — start a dedicated work-item branch first.`);
    console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    exit(1);
  }

  // Order item 5 — NEW: a recognized non-work-item branch prefix passes with a
  // DISTINCT message (no remediation — it is a pass). Reached only once item 4
  // has established the branch is not the base; fires whether ref_id is
  // set-but-unrelated or empty/null (Tier B) — the allowlist needs no focus.
  const prefix = matchAllowlistPrefix(branch);
  if (prefix) {
    console.log(`branch-guard: OK — "${branch}" is a recognized non-work-item branch (prefix "${prefix}"; no work item claimed).`);
    exit(0);
  }

  // Order item 6 — Tier B on a non-allowlisted branch -> fail closed (identical
  // outcome to today's combined item-3 check for every non-allowlisted branch).
  if (!focus.ok) {
    console.error('branch-guard: current_focus.ref_id is not set in STATE.yaml (cannot verify the branch).');
    console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    exit(4);
  }

  // Order item 7 — branch name must CONTAIN the ref_id slug (per intake
  // convention). The #129 anti-drift guarantee — a work-item-type branch whose
  // name does not contain the current ref_id still exits 3.
  if (!branch.includes(focus.refId)) {
    console.error(`branch-guard: branch "${branch}" does not correspond to current_focus.ref_id "${focus.refId}".`);
    console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    exit(3);
  }

  // Order item 8 — pass.
  console.log(`branch-guard: OK — branch "${branch}" matches current_focus.ref_id "${focus.refId}".`);
  exit(0);
}

// Run as CLI only when invoked directly; importable for unit tests.
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
const isMain = process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url));
if (isMain) runMain(() => main());

export { TYPE_TOKENS, typeToken, remediation, checkBranchPin, pinFilePath };
