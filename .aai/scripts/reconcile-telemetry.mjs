#!/usr/bin/env node
//
// reconcile-telemetry.mjs — worktree-stranded committed telemetry reconciler
// (CHANGE-0039 / SPEC-0055-spec-worktree-telemetry-reconciliation.md).
//
// PURPOSE
//   STATE.yaml/LOOP_TICKS.jsonl are gitignored per-developer, so orchestration
//   and metrics-flush.mjs MUST run in the MAIN checkout. But docs/ai/METRICS.jsonl
//   and docs/ai/EVENTS.jsonl are COMMITTED-class shared ledgers. When a scope is
//   built in a git worktree, flush/an agent write the scope's ledger record(s)
//   into the MAIN checkout's working tree — never staged into the worktree's PR
//   branch — and they are LOST on branch/worktree cleanup (observed on PR #99).
//   This script, run FROM the scope tree at PR time, carries those stranded
//   lines onto the scope tree, append-only union deduped, and stages them —
//   then scrubs the exact carried lines from the source (carry-before-clean).
//
// CLI GRAMMAR (frozen)
//   node .aai/scripts/reconcile-telemetry.mjs --ref <slug>
//     [--metrics <path>] [--events <path>]   # repo-relative, default docs/ai/*
//     [--no-source-cleanup]                   # carry+stage only; skip source scrub
//     [--dry-run]                             # print the plan JSON, write nothing, exit 0
//
// DETECTION (no STATE read — STATE is gitignored and absent in a worktree):
//   `git worktree list --porcelain` enumerates every linked worktree. The
//   CURRENT tree (`git rev-parse --show-toplevel`) is compared against that
//   list; every OTHER worktree is a candidate SOURCE. Zero siblings (a normal,
//   non-worktree checkout) is a verified no-op.
//
// HARVEST: for each sibling, per file, the lines present in that sibling's
//   CURRENT working tree but absent from its own HEAD blob (a multiset line
//   diff — the "working-tree lines minus HEAD-blob lines" equivalent the spec
//   sanctions) are the UNCOMMITTED-ADDED candidates — never committed history.
//
// FILTER: a METRICS candidate matches --ref when its parsed `ref_id` equals
//   the ref or `String(ref_id).split('/')` includes it (flush's `refMatches`
//   semantics). An EVENTS candidate matches when its `ref` equals the ref or
//   starts with `<ref>/` (the append-event PARENT/suffix rollup). Comment/
//   blank lines and unparseable JSON are always skipped — fail-safe, never a
//   speculative carry.
//
// CARRY: matched candidates are appended (source order, dedup by full-line
//   trimmed identity against the destination) onto the CURRENT tree's same
//   file; the destination is created fresh if absent. Changed destinations
//   are `git add`-ed. A post-write VERIFY confirms every carried line is
//   present; on mismatch the partial write is reverted and the run exits 1
//   (fail-closed) without touching the source.
//
// CLEAN (default on; `--no-source-cleanup` skips): once a candidate is
//   confirmed present in the destination, that EXACT uncommitted-added line
//   is removed from the SOURCE sibling's working tree — a pure relocation of
//   a stray edit, never a rewrite of committed telemetry.
//
// EXIT CONTRACT (frozen)
//   0 = reconciled (carried, reports counts) OR nothing to carry (reports why).
//   1 = a write happened and post-write VERIFY failed, or a write/stage
//       operation raised an error — fail-closed, nonzero, ceremony STOPS.
//   2 = usage error (missing/invalid --ref, unknown flag); nothing written.
//
// Node stdlib only (docs/TECHNOLOGY.md); no network; deterministic.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const PREFIX = 'reconcile-telemetry';

function fail(msg, code = 2) {
  console.error(`${PREFIX}: ${msg}`);
  process.exit(code);
}

function parseArgs(argv) {
  const args = {
    ref: null,
    metrics: 'docs/ai/METRICS.jsonl',
    events: 'docs/ai/EVENTS.jsonl',
    noSourceCleanup: false,
    dryRun: false,
  };
  const rest = argv.slice(2);
  for (let i = 0; i < rest.length; i += 1) {
    const tok = rest[i];
    if (tok === '--ref') { args.ref = rest[++i]; }
    else if (tok === '--metrics') { args.metrics = rest[++i]; }
    else if (tok === '--events') { args.events = rest[++i]; }
    else if (tok === '--no-source-cleanup') { args.noSourceCleanup = true; }
    else if (tok === '--dry-run') { args.dryRun = true; }
    else fail(`unknown flag "${tok}"`);
  }
  if (!args.ref || args.ref.startsWith('--')) fail('missing or invalid --ref <slug>');
  if (!args.metrics || args.metrics.startsWith('--')) fail('missing value for --metrics');
  if (!args.events || args.events.startsWith('--')) fail('missing value for --events');
  return args;
}

// --- git helpers --------------------------------------------------------------

function git(cwd, gitArgs, { silent = false } = {}) {
  return execFileSync('git', gitArgs, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', silent ? 'ignore' : 'pipe'],
  });
}

function realpathOrSelf(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}

function currentRoot() {
  let out;
  try { out = git(process.cwd(), ['rev-parse', '--show-toplevel']); }
  catch { fail('not inside a git working tree'); }
  return realpathOrSelf(out.trim());
}

// Every linked worktree path, per `git worktree list --porcelain`. Fail-safe:
// a git error here (should not happen once we have a root) yields a single-
// entry list (the root itself) — i.e. treated as inline/no siblings.
function listWorktrees(root) {
  let out;
  try { out = git(root, ['worktree', 'list', '--porcelain']); }
  catch { return [root]; }
  const paths = [];
  for (const line of out.split('\n')) {
    if (line.startsWith('worktree ')) paths.push(realpathOrSelf(line.slice('worktree '.length).trim()));
  }
  return paths.length ? paths : [root];
}

// Returns the file's blob content at HEAD, or null if the path does not
// exist at HEAD (untracked, or the sibling has no matching commit) — any
// git failure is treated the same way (fail-safe: the whole working file is
// then treated as "added", still subject to the ref filter downstream).
function headBlobOrNull(repoRoot, relPath) {
  try { return git(repoRoot, ['show', `HEAD:${relPath}`], { silent: true }); }
  catch { return null; }
}

function readFileOrNull(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

// --- line-set helpers ----------------------------------------------------------

function splitLines(content) {
  if (content === null || content === undefined) return [];
  const parts = content.split(/\r?\n/);
  if (parts.length && parts[parts.length - 1] === '') parts.pop();
  return parts;
}

function isCommentOrBlank(line) {
  const t = line.trim();
  return t === '' || t.startsWith('#');
}

// Multiset diff: for each line in `workingLines` (in order), decide whether
// it is protected (present in HEAD, one occurrence consumed) or "added"
// (working-tree-only). Blank lines are never counted either way.
function computeAddedFlags(headContent, workingContent) {
  const headLines = splitLines(headContent);
  const headCount = new Map();
  for (const l of headLines) headCount.set(l, (headCount.get(l) || 0) + 1);

  const workingLines = splitLines(workingContent);
  const addedFlags = workingLines.map((line) => {
    if (line.trim() === '') return false;
    const c = headCount.get(line) || 0;
    if (c > 0) { headCount.set(line, c - 1); return false; }
    return true;
  });
  return { workingLines, addedFlags };
}

function metricsMatches(obj, ref) {
  if (!obj || typeof obj !== 'object') return false;
  const rid = obj.ref_id;
  if (rid == null) return false;
  return rid === ref || String(rid).split('/').includes(ref);
}

function eventsMatches(obj, ref) {
  if (!obj || typeof obj !== 'object') return false;
  const r = obj.ref;
  if (r == null) return false;
  return r === ref || String(r).startsWith(`${ref}/`);
}

// Harvest one (sibling, relPath) pair: returns workingLines + a parallel
// carriedFlags array (position-accurate, for later surgical cleanup) + the
// ordered list of carried line strings.
function harvestFile(sib, relPath, ref, matcher) {
  const abs = path.join(sib, relPath);
  const workingContent = readFileOrNull(abs);
  if (workingContent === null) {
    return { sib, workingLines: [], carriedFlags: [], carriedLines: [] };
  }
  const headContent = headBlobOrNull(sib, relPath);
  const { workingLines, addedFlags } = computeAddedFlags(headContent, workingContent);

  const carriedFlags = new Array(workingLines.length).fill(false);
  const carriedLines = [];
  for (let i = 0; i < workingLines.length; i += 1) {
    if (!addedFlags[i]) continue;
    const line = workingLines[i];
    if (isCommentOrBlank(line)) continue;
    let obj;
    try { obj = JSON.parse(line.trim()); } catch { continue; } // fail-safe: never carry garbage
    if (!matcher(obj, ref)) continue;
    carriedFlags[i] = true;
    carriedLines.push(line);
  }
  return { sib, workingLines, carriedFlags, carriedLines };
}

// --- destination union / write / verify -----------------------------------------

function computeUnion(rootAbs, relPath, allCarried) {
  const destPath = path.join(rootAbs, relPath);
  const existingContent = readFileOrNull(destPath);
  const existingLines = splitLines(existingContent);
  const existingSet = new Set(existingLines.map((l) => l.trim()));

  const toAppend = [];
  const seenThisRun = new Set();
  for (const line of allCarried) {
    const t = line.trim();
    if (existingSet.has(t) || seenThisRun.has(t)) continue;
    seenThisRun.add(t);
    toAppend.push(line);
  }
  return { destPath, existingContent, existingLines, toAppend };
}

// Writes existingLines+toAppend, then re-reads and verifies every appended
// line is present. On any failure (write error, or a post-write mismatch)
// the destination is reverted to its pre-write state and ok:false is
// returned — the caller fails closed (exit 1), never touching the source.
function writeAndVerify(destPath, existingContent, existingLines, toAppend) {
  const newLines = [...existingLines, ...toAppend];
  const newContent = `${newLines.join('\n')}\n`;
  try {
    fs.mkdirSync(path.dirname(destPath), { recursive: true });
    fs.writeFileSync(destPath, newContent);
  } catch (e) {
    return { changed: false, ok: false, reason: `write failed: ${e.message}` };
  }

  let verifyContent;
  try { verifyContent = fs.readFileSync(destPath, 'utf8'); }
  catch (e) { return { changed: false, ok: false, reason: `post-write read failed: ${e.message}` }; }

  const verifySet = new Set(splitLines(verifyContent).map((l) => l.trim()));
  const missing = toAppend.filter((l) => !verifySet.has(l.trim()));
  if (missing.length > 0) {
    try {
      if (existingContent === null) fs.rmSync(destPath, { force: true });
      else fs.writeFileSync(destPath, existingContent);
    } catch { /* best-effort revert; the failure below is already fatal */ }
    return { changed: false, ok: false, reason: `verify mismatch: ${missing.length} carried line(s) missing after write` };
  }
  return { changed: true, ok: true };
}

// Removes exactly the carried-and-confirmed occurrences from a sibling's
// working-tree file (position-accurate against the harvestFile snapshot),
// leaving every protected (committed) and wrong-ref occurrence untouched.
function cleanupSource(sib, relPath, workingLines, carriedFlags, destPresenceSet) {
  const kept = [];
  const removed = [];
  for (let i = 0; i < workingLines.length; i += 1) {
    if (carriedFlags[i] && destPresenceSet.has(workingLines[i].trim())) {
      removed.push(workingLines[i]);
      continue;
    }
    kept.push(workingLines[i]);
  }
  if (removed.length === 0) return { changed: false, removed: [] };
  const abs = path.join(sib, relPath);
  const newContent = kept.length ? `${kept.join('\n')}\n` : '';
  fs.writeFileSync(abs, newContent);
  return { changed: true, removed };
}

// Processes one destination file end-to-end: union -> write+verify (unless
// dry-run) -> git add -> cleanup (unless disabled). Returns a report object;
// throws-free — errors are surfaced via `ok: false`.
function processFile(rootAbs, relPath, sources, args) {
  const allCarried = sources.flatMap((s) => s.carriedLines);
  const union = computeUnion(rootAbs, relPath, allCarried);

  if (args.dryRun) {
    return { relPath, ok: true, allCarried, toAppend: union.toAppend, changed: false, cleanup: [] };
  }

  let writeResult = { changed: false, ok: true };
  if (union.toAppend.length > 0) {
    writeResult = writeAndVerify(union.destPath, union.existingContent, union.existingLines, union.toAppend);
    if (!writeResult.ok) return { relPath, ok: false, reason: writeResult.reason };
    try {
      git(rootAbs, ['add', relPath]);
    } catch (e) {
      return { relPath, ok: false, reason: `git add failed: ${e.message}` };
    }
  }

  const cleanupReports = [];
  if (!args.noSourceCleanup && allCarried.length > 0) {
    const destContent = readFileOrNull(union.destPath);
    const destSet = new Set(splitLines(destContent).map((l) => l.trim()));
    for (const s of sources) {
      if (s.carriedLines.length === 0) continue;
      const res = cleanupSource(s.sib, relPath, s.workingLines, s.carriedFlags, destSet);
      if (res.changed) cleanupReports.push({ sibling: s.sib, removed: res.removed.length });
    }
  }

  return {
    relPath, ok: true, allCarried, toAppend: union.toAppend,
    changed: writeResult.changed, cleanup: cleanupReports,
  };
}

// --- main -----------------------------------------------------------------------

function main() {
  const args = parseArgs(process.argv);
  const rootAbs = currentRoot();
  const worktrees = listWorktrees(rootAbs);
  const siblings = worktrees.filter((w) => w !== rootAbs);

  const metricsSources = siblings.map((sib) => harvestFile(sib, args.metrics, args.ref, metricsMatches));
  const eventsSources = siblings.map((sib) => harvestFile(sib, args.events, args.ref, eventsMatches));

  const metricsAllCarried = metricsSources.flatMap((s) => s.carriedLines);
  const eventsAllCarried = eventsSources.flatMap((s) => s.carriedLines);
  const totalCarried = metricsAllCarried.length + eventsAllCarried.length;
  const noop = siblings.length === 0 || totalCarried === 0;

  if (args.dryRun) {
    const plan = {
      ref: args.ref,
      siblings,
      carry: { metrics: metricsAllCarried, events: eventsAllCarried },
      cleanup: args.noSourceCleanup ? [] : [
        ...metricsSources.filter((s) => s.carriedLines.length).map((s) => ({ sibling: s.sib, file: args.metrics, count: s.carriedLines.length })),
        ...eventsSources.filter((s) => s.carriedLines.length).map((s) => ({ sibling: s.sib, file: args.events, count: s.carriedLines.length })),
      ],
      noop,
    };
    console.log(JSON.stringify(plan, null, 2));
    process.exit(0);
  }

  if (siblings.length === 0) {
    console.log(`${PREFIX}: inline scope (no sibling worktree) — nothing to carry for ref=${args.ref}`);
    process.exit(0);
  }
  if (totalCarried === 0) {
    console.log(`${PREFIX}: nothing to carry for ref=${args.ref} (checked ${siblings.length} sibling worktree(s))`);
    process.exit(0);
  }

  const metricsResult = processFile(rootAbs, args.metrics, metricsSources, args);
  if (!metricsResult.ok) {
    console.error(`${PREFIX}: ${args.metrics} — ${metricsResult.reason} — reverted, source untouched, ceremony STOPPED`);
    process.exit(1);
  }
  const eventsResult = processFile(rootAbs, args.events, eventsSources, args);
  if (!eventsResult.ok) {
    console.error(`${PREFIX}: ${args.events} — ${eventsResult.reason} — reverted, source untouched, ceremony STOPPED`);
    process.exit(1);
  }

  const alreadyPresentMetrics = metricsResult.allCarried.length - metricsResult.toAppend.length;
  const alreadyPresentEvents = eventsResult.allCarried.length - eventsResult.toAppend.length;
  console.log(
    `${PREFIX}: ref=${args.ref} carried metrics=${metricsResult.toAppend.length} events=${eventsResult.toAppend.length} `
    + `(already-present metrics=${alreadyPresentMetrics} events=${alreadyPresentEvents})`,
  );

  if (args.noSourceCleanup) {
    console.log(`${PREFIX}: source cleanup skipped (--no-source-cleanup)`);
  } else {
    const allCleanup = [...metricsResult.cleanup, ...eventsResult.cleanup];
    if (allCleanup.length === 0) {
      console.log(`${PREFIX}: no source cleanup needed`);
    } else {
      for (const r of allCleanup) {
        console.log(`${PREFIX}: cleaned ${r.removed} line(s) from ${r.sibling}`);
      }
    }
  }

  process.exit(0);
}

main();
