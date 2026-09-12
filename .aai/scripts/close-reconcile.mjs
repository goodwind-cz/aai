#!/usr/bin/env node
// close-reconcile.mjs — route-independent close-ceremony gate
// (ride ref close-ceremony-fires-only-via-aai-pr, docs/specs/
// SPEC-0175-spec-close-ceremony-fires-only-via-aai-pr.md).
//
// WHY THIS EXISTS: the close ceremony (frontmatter status flip, links.pr /
// links.commits stamping, the close event set — all mechanized by
// close-work-item.mjs) was reachable only through `/aai-pr` /
// .aai/SKILL_PR.prompt.md step 5. A PR opened with `gh pr create`, the
// GitHub UI, or a merge queue merges, deploys, and leaves the intake doc
// reading `status: draft` with nothing failing. This CLI reads a pushed
// range on the default branch with git ALONE — no `--ref`, no PR API — so
// every route that lands code on `main` produces exactly one pushed range,
// and exactly one thing triggers the check.
//
// GRAMMAR (D1)
//   node .aai/scripts/close-reconcile.mjs --range <A>..<B> [--root <dir>] [--check|--apply]
//   --range <A>..<B>  required. Two git-resolvable refs/shas joined by "..".
//                      Read with git alone: `git diff --name-only A..B` and
//                      `git log --format=%H%x09%s A..B`.
//   --root <dir>       default process.cwd().
//   --check             default mode. Report-only, never writes. Exit 0
//                       CLEAN, 1 when items are found.
//   --apply             spawns the REAL close-work-item.mjs (D3) once per
//                       item (never re-implemented, never edited by this
//                       scope — it is hash-pinned by four other suites).
// Exit codes: 0 clean/applied | 1 items found (--check) or an apply
// refusal/failure | 2 usage error or an unresolvable --range.
//
// D2 — ONE named delivery arm, so an intake-only PR is never a false
// positive. A touched doc is an ITEM only when its post-merge frontmatter
// status is non-terminal (docs-model.mjs TERMINAL_DOC_STATUS — the SHARED
// list, never a private copy) AND the arm fires:
//   frozen_work_merged  — the doc's own status is `implementing`, or the
//                          doc body carries the `SPEC-FROZEN: true` marker
//                          line spec-freeze.mjs writes.
// A range that only ADDS a draft doc fires NEITHER this arm nor any other
// and is CLEAN — the one false-positive class this design exists to rule
// out (D2).
//
// AMENDED 2026-09-11 (owner decision, post-freeze remediation; see the
// spec's `## Amendment` section, item 1): a second arm, `code_with_open_doc`
// (fired when the range ALSO touched a non-doc path), shipped at first
// implementation and was REMOVED here. A CI-faithful 40-push replay of this
// repository's own `main` history measured it at 1 true / 7 false, with 3 of
// the 4 firing pushes carrying ZERO true items — "the doc was added by the
// same range" does not discriminate a delivery from a backlog intake filed
// alongside unrelated code. `frozen_work_merged` measured 1 true / 0 false
// over the same corpus. The recall gap this narrowing leaves open (one of
// three documented close-ceremony escapes in this repo's history was
// detected only by the arm now removed) is knowingly NOT closed here; it is
// filed as follow-up `fu-close-gate-status-trigger-blind`.
//
// REMEDIATION ROUND 3 (owner decision recorded 2026-09-12, code review
// docs/ai/reviews/review-20260911T222047Z.md) — two fixes at cause, both in
// computeItems below, neither touching pairItems or close-work-item.mjs:
//
// BLOCKING-1 — the pair, not just the spec, is the item. spec-freeze.mjs is
// the SOLE writer of `status: implementing`, and it writes it ONLY to
// docs/specs/** (the census: 0 of 268 docs/issues docs have ever carried
// it). So a primary (intake) doc never independently satisfies the arm
// above, and pairItems() — which can only pair a spec FROM a primary that
// is already an item — never sees it: `--apply` closed the spec alone,
// leaving the primary `draft` with `links.pr: []` (issue #352's
// corruption), and a REPEAT `--check` over the same range then read both
// docs fresh off disk — the spec now `done` (terminal, skipped), the
// primary still `draft` and non-firing — and reported CLEAN over that
// half-closed state. The fix adds a second pass after the arm loop: for
// every SPEC touched by this same range whose id is `spec-<primary id>`
// and whose status shows the pair's delivery is underway or already
// recorded (`implementing`, the frozen marker, or already `done` — the
// half-closed-replay case), its primary is added as an item too, by the
// SAME naming convention pairItems() already assumes, WHENEVER that
// primary is still non-terminal — so `--apply` closes both in the ONE
// transaction pairItems() builds, and a repeat `--check` keeps reporting
// the primary until it is. Deliberately bounded to primary and spec BOTH
// touched in the same range (matching the reproduced corruption and this
// factory's single-squash-merge convention); a spec-only range whose
// primary was never touched by any commit in this push is out of scope —
// not reproduced, not required by the round-3 dispatch, left unfixed.
//
// BLOCKING-2 — `umbrella: true` is exempt, matching docs-audit-core.mjs's
// OWN predicate (`String(fm.umbrella ?? '').toLowerCase() === 'true'`,
// read verbatim, not re-derived) rather than a second, weaker notion of
// what an umbrella parent is. Before this fix this CLI had zero awareness
// of the marker, so a deliberately-open multi-phase parent (e.g.
// docs/rfc/RFC-0012, `status: implementing` + `umbrella: true`) fired
// `frozen_work_merged` on every child-phase delivery that merely touched
// it, with no dial (D5) and no legitimate remedy — the parent is SUPPOSED
// to stay open. A marked doc is now skipped before either arm pass runs,
// so it can never become an item on its own account NOR be resolved as a
// pairing primary.
//
// D4 — the PR number comes from the merge subject or it does not come at
// all: the trailing `(#N)` of a commit subject in the range, newest first
// (git log's own default order). No subject carries one -> every
// resolvable item is refused by name with reason `pr-number-unknown`,
// --apply exits non-zero, and nothing is written. A guessed number is
// never stamped.
//
// D3 — the remediation is close-work-item.mjs, invoked as a child process,
// never re-implemented. This file owns NO frontmatter write and NO
// EVENTS.jsonl write of its own (Spec-AC-04 / TEST-005) — every mutation
// happens inside that script's own D6 snapshot/rollback transaction.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { scanAuditDocs, loadConfig } from './lib/docs-audit-core.mjs';
import { parseFrontmatter, TERMINAL_DOC_STATUS } from './lib/docs-model.mjs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const CLOSE_WORK_ITEM = path.join(SCRIPT_DIR, 'close-work-item.mjs');

const PR_SUBJECT_RE = /\(#(\d+)\)\s*$/;
const FROZEN_MARKER_RE = /^SPEC-FROZEN:\s*true\s*$/m;

function usage() {
  return (
    'usage: node .aai/scripts/close-reconcile.mjs --range <A>..<B> [--root <dir>] [--check|--apply]\n'
  );
}

function usageError(msg) {
  process.stderr.write(`close-reconcile: ${msg}\n${usage()}`);
  exit(2);
}

function parseArgs(argv) {
  const args = { mode: 'check' };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--range') args.range = argv[++i];
    else if (tok === '--root') args.root = argv[++i];
    else if (tok === '--check') args.mode = 'check';
    else if (tok === '--apply') args.mode = 'apply';
    else usageError(`unrecognized argument "${tok}"`);
  }
  return args;
}

function isAllZero(s) {
  return /^0+$/.test(s);
}

// resolveRange(root, rawRange) -> { ok: true, a, b } with a/b resolved to
// full commit shas, or { ok: false, reason }. Fail-closed (Spec-AC-06):
// missing, empty, all-zero, and unresolvable each report a distinct named
// reason — never a silent 0.
function resolveRange(root, rawRange) {
  if (rawRange === undefined) return { ok: false, reason: 'no --range given' };
  if (rawRange === '') return { ok: false, reason: 'empty --range value' };
  const parts = rawRange.split('..');
  if (parts.length !== 2 || parts[0] === '' || parts[1] === '') {
    return { ok: false, reason: 'not a resolvable A..B range' };
  }
  const [a, b] = parts;
  if (isAllZero(a) || isAllZero(b)) {
    return { ok: false, reason: 'names the all-zero placeholder ref' };
  }
  try {
    const shaA = execFileSync('git', ['rev-parse', '--verify', `${a}^{commit}`], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
    const shaB = execFileSync('git', ['rev-parse', '--verify', `${b}^{commit}`], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
    return { ok: true, a: shaA, b: shaB };
  } catch (err) {
    const detail = String(err?.stderr || err?.message || err).trim().split('\n')[0];
    return { ok: false, reason: `git could not resolve it (${detail})` };
  }
}

function rangeErrorMessage(rawRange, reason) {
  const shown = rawRange === undefined ? '(not given)' : JSON.stringify(rawRange);
  return `close-reconcile: invalid --range ${shown} — ${reason}`;
}

function changedPaths(root, a, b) {
  const out = execFileSync('git', ['diff', '--name-only', `${a}..${b}`], {
    cwd: root, encoding: 'utf8',
  });
  return out.split('\n').map((s) => s.trim()).filter(Boolean);
}

// commitLog(root, a, b) -> [{ sha, subject }] newest-first (git log's own
// default order for a..b). commits[0] is the delivery sha (D1: "the newest
// commit in the range").
function commitLog(root, a, b) {
  const out = execFileSync('git', ['log', '--format=%H%x09%s', `${a}..${b}`], {
    cwd: root, encoding: 'utf8',
  });
  return out.split('\n').filter(Boolean).map((line) => {
    const idx = line.indexOf('\t');
    return { sha: line.slice(0, idx), subject: line.slice(idx + 1) };
  });
}

function parsePrNumber(commits) {
  for (const c of commits) {
    const m = PR_SUBJECT_RE.exec(c.subject);
    if (m) return m[1];
  }
  return null;
}

function bodyOf(content) {
  if (!content.startsWith('---\n')) return content;
  const end = content.indexOf('\n---', 4);
  if (end < 0) return content;
  return content.slice(end + 4);
}

// isUmbrellaDoc(fm) -> bool. BLOCKING-2 — the SAME predicate
// docs-audit-core.mjs applies for its own umbrella suppression (read
// verbatim, never re-derived): a deliberately-open multi-phase parent
// declares itself with frontmatter `umbrella: true`, string-compared
// case-insensitively.
function isUmbrellaDoc(fm) {
  return String(fm?.umbrella ?? '').toLowerCase() === 'true';
}

// computeItems(root, a, b) -> { items, deliverySha, prNumber }
// items: [{ rel, fmId, status, arm, reason, isSpec }]. `reason` is only set
// to 'slug-unresolvable' when the doc's frontmatter has no usable `id:` —
// still reported (fail-closed, never silently skipped) but always refused
// by --apply.
function computeItems(root, a, b) {
  const changed = changedPaths(root, a, b);
  const config = loadConfig(root);
  const docSet = new Set(scanAuditDocs(root, { scanExclude: config?.scan_exclude ?? [] }).map((d) => d.rel));
  const docPaths = changed.filter((rel) => docSet.has(rel));
  const commits = commitLog(root, a, b);
  const deliverySha = commits.length ? commits[0].sha : b;
  const prNumber = parsePrNumber(commits);

  // Read every touched doc's frontmatter + body ONCE, regardless of its own
  // terminal status. BLOCKING-1's pairing pass below needs to see an
  // ALREADY-done spec too (the half-closed-replay case), not only a
  // currently-firing one, so terminal docs stay in `touched` and are only
  // excluded per-purpose (own-arm firing skips them; pairing does not).
  const touched = [];
  for (const rel of docPaths) {
    const abs = path.join(root, rel);
    if (!fs.existsSync(abs)) continue; // deleted by the range: nothing to close
    let content;
    try {
      content = fs.readFileSync(abs, 'utf8');
    } catch {
      continue;
    }
    const fm = parseFrontmatter(content);
    if (isUmbrellaDoc(fm)) continue; // BLOCKING-2 — exempt, full stop, either role
    const status = String(fm?.status ?? '').toLowerCase();
    touched.push({
      rel,
      // TERMINAL_DOC_STATUS is the shared partition (docs-model.mjs);
      // anything NOT in it (including an empty/unclassified status) is
      // non-terminal by the library's own fail-safe direction — never a
      // private re-derivation.
      terminal: TERMINAL_DOC_STATUS.has(status),
      fmId: fm?.id ?? null,
      status,
      isFrozen: FROZEN_MARKER_RE.test(bodyOf(content)),
      isSpec: rel.startsWith('docs/specs/'),
    });
  }

  const byId = new Map(touched.filter((d) => d.fmId).map((d) => [d.fmId, d]));
  const items = [];
  const pushed = new Set();
  const pushItem = (d) => {
    if (pushed.has(d.rel)) return; // already an item via the other pass
    pushed.add(d.rel);
    items.push({
      rel: d.rel,
      fmId: d.fmId,
      status: d.status,
      arm: 'frozen_work_merged',
      reason: d.fmId ? null : 'slug-unresolvable',
      isSpec: d.isSpec,
    });
  };

  // D2 (amended) — a doc's OWN state fires the one named arm.
  for (const d of touched) {
    if (d.terminal) continue;
    if (d.status === 'implementing' || d.isFrozen) pushItem(d);
  }

  // BLOCKING-1 remediation — pair resolution. In this factory's own
  // convention (spec-freeze.mjs is the SOLE writer of `implementing`, and
  // only ever to a docs/specs/** doc) a primary/intake doc never fires on
  // its own account, so without this pass it never becomes an item and
  // pairItems() below — which can only match a spec TO a primary already
  // in `items` — never sees it. A spec doc whose id is `spec-<primary id>`
  // (pairItems()'s own naming convention) and whose status shows its
  // delivery is underway (`implementing`/frozen) OR was already recorded
  // (`done` — a prior half-close) means its paired primary belongs in this
  // closure too, whenever that primary is present in this SAME range and
  // still non-terminal — so `--apply` closes both in one transaction and a
  // repeat `--check` keeps reporting the primary instead of going CLEAN.
  for (const d of touched) {
    if (!d.isSpec || !d.fmId || !d.fmId.startsWith('spec-')) continue;
    if (d.status !== 'implementing' && !d.isFrozen && d.status !== 'done') continue;
    const primary = byId.get(d.fmId.slice('spec-'.length));
    if (!primary || primary.terminal) continue;
    pushItem(primary);
  }

  return { items, deliverySha, prNumber };
}

function runCheck(root, a, b) {
  const { items, deliverySha, prNumber } = computeItems(root, a, b);
  if (items.length === 0) {
    console.log('close-reconcile: CLEAN');
    exit(0);
  }
  for (const it of items) {
    if (it.reason === 'slug-unresolvable') {
      console.log(`close-reconcile: OPEN ${it.rel} reason=slug-unresolvable sha=${deliverySha}`);
      continue;
    }
    console.log(`close-reconcile: OPEN ${it.rel} id=${it.fmId} arm=${it.arm} sha=${deliverySha}`);
    if (prNumber === null) {
      console.log(
        `close-reconcile:   remediation: BLOCKED — no commit subject in the range carries a trailing "(#N)", so no PR number can be resolved; this cannot be closed by command until one is known`
      );
      continue;
    }
    console.log(
      `close-reconcile:   remediation: node .aai/scripts/close-work-item.mjs --ref ${it.fmId} --pr ${prNumber} --commit ${deliverySha}`
    );
  }
  console.log(`close-reconcile: ${items.length} item(s) found — the close ceremony did not run before merge`);
  exit(1);
}

// pairItems(items) -> [{ primary, spec|null }]. D3's "never two" rule for an
// intake doc and its paired spec: a spec doc (docs/specs/**) whose
// frontmatter id equals "spec-<primary id>" is closed in the SAME
// close-work-item.mjs invocation as its primary doc (--spec), never as a
// second standalone invocation. An unpaired spec item still closes on its
// own.
function pairItems(items) {
  const specs = items.filter((i) => i.isSpec);
  const primaries = items.filter((i) => !i.isSpec);
  const specById = new Map(specs.map((s) => [s.fmId, s]));
  const paired = new Set();
  const plan = [];
  for (const p of primaries) {
    const spec = p.fmId ? specById.get(`spec-${p.fmId}`) ?? null : null;
    if (spec) paired.add(spec);
    plan.push({ primary: p, spec });
  }
  for (const s of specs) {
    if (!paired.has(s)) plan.push({ primary: s, spec: null });
  }
  return plan;
}

function runApply(root, a, b) {
  const { items, deliverySha, prNumber } = computeItems(root, a, b);
  if (items.length === 0) {
    console.log('close-reconcile: CLEAN — nothing to apply');
    exit(0);
  }

  const unresolvable = items.filter((i) => i.reason === 'slug-unresolvable');
  for (const it of unresolvable) {
    process.stderr.write(
      `close-reconcile: REFUSED ${it.rel} reason=slug-unresolvable — no frontmatter "id:", cannot close, nothing written\n`
    );
  }

  // D4 — one PR number sourced from the whole range. None present: every
  // resolvable item is refused by name, exit non-zero, nothing written.
  if (prNumber === null) {
    for (const it of items) {
      if (it.reason === 'slug-unresolvable') continue;
      process.stderr.write(
        `close-reconcile: REFUSED ${it.rel} id=${it.fmId} reason=pr-number-unknown — no commit subject in the range carries a trailing "(#N)", nothing written\n`
      );
    }
    exit(1);
  }

  const resolvable = items.filter((i) => i.reason !== 'slug-unresolvable');
  let failed = unresolvable.length > 0;

  const plan = pairItems(resolvable);
  for (const { primary, spec } of plan) {
    const cliArgs = ['--ref', primary.fmId, '--pr', prNumber, '--commit', deliverySha];
    if (spec) cliArgs.push('--spec', spec.fmId);
    try {
      execFileSync('node', [CLOSE_WORK_ITEM, ...cliArgs], {
        cwd: root, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8',
      });
    } catch (err) {
      failed = true;
      const detail = String(err?.stderr || err?.message || err).trim();
      process.stderr.write(`close-reconcile: close-work-item.mjs failed for ${primary.fmId}: ${detail}\n`);
      continue;
    }
    // Re-read to confirm the flip actually landed (defense-in-depth; the
    // write itself is owned entirely by close-work-item.mjs's own D6
    // transaction — this is a read, never a second write). Guarded like the
    // spawn above it: one item's unreadable doc (EACCES, a concurrent
    // checkout) must not abort the remaining items in the batch.
    const abs = path.join(root, primary.rel);
    let statusAfter;
    try {
      const after = fs.readFileSync(abs, 'utf8');
      const fmAfter = parseFrontmatter(after);
      statusAfter = String(fmAfter?.status ?? '').toLowerCase();
    } catch (err) {
      failed = true;
      const detail = String(err?.message || err).trim();
      process.stderr.write(
        `close-reconcile: ${primary.rel} could not be re-read to confirm the close-work-item.mjs flip: ${detail}\n`
      );
      continue;
    }
    if (!TERMINAL_DOC_STATUS.has(statusAfter)) {
      failed = true;
      process.stderr.write(
        `close-reconcile: ${primary.rel} still reads status "${statusAfter}" after close-work-item.mjs returned — apply did not flip it\n`
      );
      continue;
    }
    console.log(`close-reconcile: CLOSED ${primary.rel} (pr #${prNumber}, commit ${deliverySha})`);
  }
  exit(failed ? 1 : 0);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = args.root ? path.resolve(args.root) : process.cwd();
  const range = resolveRange(root, args.range);
  if (!range.ok) {
    process.stderr.write(`${rangeErrorMessage(args.range, range.reason)}\n`);
    exit(2);
  }
  if (args.mode === 'apply') runApply(root, range.a, range.b);
  else runCheck(root, range.a, range.b);
}

runMain(() => main(), {
  onError(err) {
    process.stderr.write(`close-reconcile: internal error (${err.message})\n`);
    process.exitCode = 1;
  },
});
