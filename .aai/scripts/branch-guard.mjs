#!/usr/bin/env node
// branch-guard.mjs — deterministic branch-per-work-item hygiene guard
// (SPEC-DRAFT-spec-branch-per-work-item-hygiene).
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
//   --base <branch>  base branch to compare against; default `main`.
//   --state <path>   override the STATE.yaml path; default
//                    <git-toplevel>/docs/ai/STATE.yaml (works from any subdir).
//   --suggest        print the canonical `<type-token>/<ref-id>` to stdout and
//                    exit; performs NO git-branch check (meant to run before the
//                    branch exists). Still reads STATE — a broken/empty ref_id
//                    exits 4, never a silent pass.
//
// Deterministic check order (guard mode) — EARLIER checks win:
//   1. cwd not inside a git work tree            -> exit 4
//   2. HEAD detached (`git rev-parse --abbrev-ref HEAD` == "HEAD") -> exit 2
//   3. STATE unreadable OR ref_id empty/null     -> exit 4
//   4. current branch == base branch             -> exit 1
//   5. current branch does NOT contain ref_id    -> exit 3
//   6. otherwise                                 -> exit 0
//
// Exit codes (closed set):
//   0 — branch matches current_focus.ref_id, neither base nor detached.
//   1 — current branch equals the base branch.
//   2 — HEAD is detached.
//   3 — current branch name does not contain the ref_id slug.
//   4 — config/usage error (not a git repo, STATE unreadable, ref_id empty/null,
//       bad flag).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { splitLines } from './lib/state-core.mjs';
import { readScalar, unquoteScalar } from './lib/state-engine.mjs';

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

function git(args, cwd) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
}

function isInsideWorkTree(cwd) {
  try {
    return git(['rev-parse', '--is-inside-work-tree'], cwd) === 'true';
  } catch {
    return false;
  }
}

function topLevel(cwd) {
  return git(['rev-parse', '--show-toplevel'], cwd);
}

function currentBranch(cwd) {
  return git(['rev-parse', '--abbrev-ref', 'HEAD'], cwd);
}

// Read current_focus.ref_id/.type from STATE (read-only). Returns
// { ok, refId, type } — ok:false means the file is unreadable or ref_id is
// empty/null (fail-closed). Never throws.
function readFocus(statePath) {
  let raw;
  try {
    raw = fs.readFileSync(statePath, 'utf8');
  } catch {
    return { ok: false, refId: null, type: null };
  }
  const { lines } = splitLines(raw);
  const refRaw = readScalar(lines, 'current_focus', 'ref_id');
  const typeRaw = readScalar(lines, 'current_focus', 'type');
  const refId = refRaw == null ? null : unquoteScalar(refRaw);
  const type = typeRaw == null ? null : unquoteScalar(typeRaw);
  if (refId == null || refId === '') return { ok: false, refId: null, type };
  return { ok: true, refId, type };
}

function parseArgs(argv) {
  const opts = { base: 'main', suggest: false, state: null };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--base' || tok === '--state') {
      const v = argv[i + 1];
      if (!v || v.startsWith('--')) {
        console.error(`branch-guard: ${tok} requires a value`);
        process.exit(4);
      }
      opts[tok.slice(2)] = v;
      i += 1;
    } else if (tok === '--suggest') {
      opts.suggest = true;
    } else if (tok === '-h' || tok === '--help') {
      console.error('Usage: node branch-guard.mjs [--base <branch>] [--suggest] [--state <path>]');
      process.exit(4);
    } else {
      console.error(`branch-guard: unknown flag "${tok}"`);
      process.exit(4);
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

function main() {
  const opts = parseArgs(process.argv);
  const cwd = process.cwd();

  // --suggest — no git-branch check; still reads STATE (fail-closed on ref_id).
  if (opts.suggest) {
    const statePath = resolveStatePath(opts, cwd);
    if (!statePath) {
      console.error('branch-guard: cannot resolve STATE.yaml (not a git repo and no --state given)');
      process.exit(4);
    }
    const focus = readFocus(statePath);
    if (!focus.ok) {
      console.error('branch-guard: current_focus.ref_id is not set in STATE.yaml');
      process.exit(4);
    }
    console.log(`${typeToken(focus.type)}/${focus.refId}`);
    process.exit(0);
  }

  // Order item 1 — must be inside a git work tree.
  if (!isInsideWorkTree(cwd)) {
    console.error('branch-guard: not inside a git work tree (cannot determine the current branch)');
    process.exit(4);
  }

  // Order item 2 — detached HEAD wins over the STATE read (best-effort remediation).
  const branch = currentBranch(cwd);
  if (branch === 'HEAD') {
    const statePath = resolveStatePath(opts, cwd);
    const focus = statePath ? readFocus(statePath) : { type: null, refId: null };
    console.error('branch-guard: HEAD is detached — no work-item branch is checked out.');
    console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    process.exit(2);
  }

  // Order item 3 — STATE unreadable / ref_id empty -> fail closed.
  const statePath = resolveStatePath(opts, cwd);
  const focus = statePath ? readFocus(statePath) : { ok: false, type: null, refId: null };
  if (!focus.ok) {
    console.error('branch-guard: current_focus.ref_id is not set in STATE.yaml (cannot verify the branch).');
    console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    process.exit(4);
  }

  // Order item 4 — current branch equals the base branch.
  if (branch === opts.base) {
    console.error(`branch-guard: on the base branch "${opts.base}" — start a dedicated work-item branch first.`);
    console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    process.exit(1);
  }

  // Order item 5 — branch name must CONTAIN the ref_id slug (per intake convention).
  if (!branch.includes(focus.refId)) {
    console.error(`branch-guard: branch "${branch}" does not correspond to current_focus.ref_id "${focus.refId}".`);
    console.error(`  Remediation: ${remediation(focus.type, focus.refId, opts.base)}`);
    process.exit(3);
  }

  // Order item 6 — pass.
  console.log(`branch-guard: OK — branch "${branch}" matches current_focus.ref_id "${focus.refId}".`);
  process.exit(0);
}

// Run as CLI only when invoked directly; importable for unit tests.
const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) main();

export { TYPE_TOKENS, typeToken, remediation };
