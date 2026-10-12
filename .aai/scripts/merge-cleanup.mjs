#!/usr/bin/env node
// merge-cleanup.mjs — deterministic engine behind `/aai-merge <PR>`
// (docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md, D1-D12).
//
//   merge-cleanup.mjs preflight --pr <n> --expect-head <sha> --directed-by human
//                               --direction "<verbatim owner words>" [--origin <abs>] [--json]
//   merge-cleanup.mjs plan  --pr <n> [--origin <abs>] [--json]
//   merge-cleanup.mjs apply --pr <n> --pid <harness pid> [--origin <abs>] [--json]
//
// EXIT CONTRACT
//   0  complete (every eligible step done or a named no-op)
//   2  usage error
//   3  refused before any mutation: `REFUSE <reason> <detail>` on stdout
//   4  stopped mid-way (a re-run resumes)
//   10 preflight ready (open PR, every gate passed)
//
// The engine NEVER runs `gh pr merge` (D3). It performs ONE fixed gh read (D4)
// and `git fetch`; every other effect is a local, archive-first file or git
// operation. Node stdlib only (docs/TECHNOLOGY.md).
//
// Test seams (AAI_MERGE_CLEANUP_GH_NODE, _STOP_AFTER, _CRASH_AT) are honoured
// ONLY when AAI_MERGE_CLEANUP_TEST_SEAMS=1 is also set; in production they are
// inert, so a stray variable can neither replace gh nor stop a run.
//
// IMPLEMENTED HERE: the CLI/step skeleton, the D5 read-back gate, the D6/D7
// superseded-draft archive (batch B1), the D8 base sync and the D10 runtime
// archive, worktree removal and branch compare-and-swap delete (batch B2), the
// D9 focus clear, index regeneration, audit verdict and saved report, and the
// D11 resume contract (batch B3), and the D3/D4 open-PR preflight (batch B4a),
// and the delete-remote-branch step (spec-merge-cleanup-delete-remote-branch):
// the merged origin branch is deleted only by a lease against the merged head
// (git push --force-with-lease=<ref>:<oid>), else retained with a named reason.
// Every precondition that can refuse is derived BEFORE the first write, so a
// refusal is exit 3 with nothing changed.
//
// spec-merge-cleanup-ride-leftovers: the ride's own traces no longer stop the run. A roadmap
// change confined to the merged ride's entry is archived and the incoming roadmap taken (D1-D5);
// whole lines appended after the last commit to the ride worktree's ledgers are moved byte-exact
// to the main checkout and archived before the worktree is removed (D6-D10); and when sync-base
// replaced the engine file this process was loaded from, the new file is run once (D11-D14).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { status as lockStatus, release as lockRelease } from './lib/session-lock.mjs';
import { parseFrontmatter } from './lib/docs-model.mjs';

const HELP = `merge-cleanup.mjs <preflight|plan|apply> --pr <n> [options]
  preflight  read-only gates for an OPEN pull request; exit 10 when ready
  plan       read-only plan for a MERGED pull request
  apply      cleanup after a MERGED pull request (needs --pid)
options: --origin <abs> --json
         --direction "<owner's words>"
         --origin defaults to the main checkout (the first git worktree), in every mode;
         pass it to read and write a ride worktree's ledger instead
the ride's own leftovers (apply): a roadmap change confined to the merged ride's entry is archived and the
         incoming roadmap taken; whole lines appended to the ride worktree's ledgers are moved to the main checkout
         (archived first, journalled, reported as moved lines); an engine file replaced by the base sync is run
         again once (reload-engine), and a re-run child that exits other than 0 or 4 prints STOPPED reexec_child_exit_<n|signal> (exit 4)
exit: 0 complete, 2 usage, 3 refused, 4 stopped mid-way, 10 preflight ready
`;

const STEP_IDS = [
  'resolve', 'plan', 'archive-runtime', 'sync-base',
  'remove-worktree', 'delete-branch', 'report',
];
const PR_FIELDS = 'number,state,isDraft,headRefOid,headRefName,baseRefName,mergeStateStatus,statusCheckRollup,mergeCommit,url,isCrossRepository';
const DRAFT_BASENAME_RE = /^[A-Z]+(?:-[A-Z]+)*-DRAFT-.+\.md$/;
const BASE_NAME_RE = /^[A-Za-z0-9._/-]+$/;
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
// D8 append-only ledgers and the generated index, origin-relative.
const LEDGERS = ['docs/ai/EVENTS.jsonl', 'docs/ai/decisions.jsonl', 'docs/ai/METRICS.jsonl', 'docs/ai/tests/test-runs.jsonl'];
const INDEX_PATH = 'docs/INDEX.md';
const STATE_REL = 'docs/ai/STATE.yaml';
const ROADMAP_PATH = 'docs/ai/roadmap.yaml';

function usage(msg) {
  process.stderr.write(`merge-cleanup: ${msg}\n${HELP}`);
  exit(2);
}

function refuse(reason, detail = '') {
  process.stdout.write(`REFUSE ${reason}${detail ? ` ${detail}` : ''}\n`);
  exit(3);
}

// A step that cannot finish after earlier steps already wrote: exit 4, a re-run resumes.
function stop(reason, detail = '') {
  process.stdout.write(`STOPPED ${reason}${detail ? ` ${detail}` : ''}\n`);
  exit(4);
}

function parseArgs(argv) {
  const out = { json: false };
  const mode = argv[0];
  if (!['preflight', 'plan', 'apply'].includes(mode)) usage(`unknown or missing mode: ${mode ?? '(none)'}`);
  out.mode = mode;
  const valueFlags = {
    '--pr': 'pr', '--origin': 'origin', '--pid': 'pid', '--expect-head': 'expectHead',
    '--directed-by': 'directedBy', '--direction': 'direction',
  };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') { out.json = true; continue; }
    if (Object.hasOwn(valueFlags, a)) {
      if (i + 1 >= argv.length) usage(`${a} requires a value`);
      out[valueFlags[a]] = argv[++i];
      continue;
    }
    usage(`unknown argument: ${a}`);
  }
  if (!/^[1-9][0-9]*$/.test(out.pr ?? '')) usage('--pr must be a positive integer');
  out.pr = Number(out.pr);
  if (mode === 'apply' && !/^[1-9][0-9]*$/.test(out.pid ?? '')) usage('apply requires --pid <positive integer>');
  if (out.origin !== undefined && !path.isAbsolute(out.origin)) usage('--origin must be an absolute path');
  return out;
}

function git(cwd, args, opts = {}) {
  const r = spawnSync('git', args, {
    cwd, encoding: opts.buffer ? 'buffer' : 'utf8', maxBuffer: 256 * 1024 * 1024,
  });
  return { status: r.status ?? 1, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}

// A test seam is live only under the explicit test guard (F5).
const seam = (name) => (process.env.AAI_MERGE_CLEANUP_TEST_SEAMS === '1' ? process.env[name] : undefined);

// A hard stop at a named point (no handler, no cleanup), to prove a resume (test seam _CRASH_AT).
function crashAt(point) {
  if (seam('AAI_MERGE_CLEANUP_CRASH_AT') === point) process.exit(137);
}

// The PR read (D4); ghDependents below is the only other gh call. Test seam: AAI_MERGE_CLEANUP_GH_NODE=<abs .js path> runs
// that script under this node instead of `gh`, because a native Windows runner
// cannot spawn a .cmd/.sh stub without a shell. Inert without the test guard.
function ghPrView(cwd, pr, maxBuffer) {
  const stub = seam('AAI_MERGE_CLEANUP_GH_NODE');
  const viewArgs = ['pr', 'view', String(pr), '--json', PR_FIELDS];
  if (stub && path.isAbsolute(stub)) {
    return spawnSync(process.execPath, [stub, ...viewArgs], { cwd, encoding: 'utf8', maxBuffer });
  }
  return spawnSync('gh', viewArgs, { cwd, encoding: 'utf8', maxBuffer });
}

// Open PRs that deleting a branch would close, same gh seam: those stacked on it (their BASE is the
// branch) and those opened from it (their HEAD is the branch). `side` is 'base' or 'head'.
function ghDependents(cwd, branch, side = 'base') {
  const listArgs = ['pr', 'list', '--state', 'open', `--${side}`, branch, '--json', 'number', '--limit', '100'];
  const stub = seam('AAI_MERGE_CLEANUP_GH_NODE');
  if (stub && path.isAbsolute(stub)) return spawnSync(process.execPath, [stub, ...listArgs], { cwd, encoding: 'utf8', timeout: 120000 });
  return spawnSync('gh', listArgs, { cwd, encoding: 'utf8', timeout: 120000 });
}

// PR numbers from one dependents query, or null when it failed or its output is not a list of numbers.
function dependentNumbers(dep) {
  if (dep.error || dep.status !== 0) return null;
  try {
    const rows = JSON.parse(dep.stdout);
    if (Array.isArray(rows) && rows.every((x) => Number.isInteger(x?.number))) return rows.map((x) => x.number);
  } catch { /* unparsable: fail closed */ }
  return null;
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
const posix = (p) => p.split(path.sep).join('/');

// owner/repo of a git remote URL or a GitHub pull-request URL, lower-cased; null
// when it is not recognisably a hosted repository (a local path, a bare name).
function repoSlug(url) {
  const u = String(url ?? '').trim().replace(/\/pull\/\d+.*$/, '').replace(/\/+$/, '');
  const m = u.match(/^(?:https?|ssh|git):\/\/(?:[^@/]+@)?[^/:]+(?::\d+)?\/([^/]+)\/([^/]+?)(?:\.git)?$/)
    ?? u.match(/^(?:[^@/\s]+@)?[^/:\s]*\.[^/:\s]+:([^/]+)\/([^/]+?)(?:\.git)?$/);
  return m ? `${m[1]}/${m[2]}`.toLowerCase() : null;
}

// NB-4: the PR must belong to the repository the origin remote points at. Only a
// recognisable remote is compared (a local path or an unparsable URL is skipped).
function checkRepo(origin, prUrl) {
  const r = git(origin, ['config', '--get', 'remote.origin.url']);
  const remote = r.status === 0 ? repoSlug(r.stdout) : null;
  const pr = repoSlug(prUrl);
  if (remote && pr && remote !== pr) refuse('repo_mismatch', `PR ${pr}, origin ${remote}`);
}

function resolveOrigin(opts) {
  let origin = opts.origin;
  if (!origin) {
    const r = git(process.cwd(), ['worktree', 'list', '--porcelain']);
    const m = r.status === 0 ? r.stdout.match(/^worktree (.+)$/m) : null;
    if (!m) refuse('no_origin', 'cannot locate the origin checkout from the current directory');
    origin = m[1];
  }
  const top = git(origin, ['rev-parse', '--show-toplevel']);
  if (top.status !== 0) refuse('no_origin', `not a git checkout: ${origin}`);
  return fs.realpathSync(top.stdout.trim());
}

// D4/D5: the one fixed gh read, then the read-back gate.
function readAndGate(opts, origin) {
  const r = ghPrView(origin, opts.pr, 64 * 1024 * 1024);
  if (r.error || r.status !== 0) refuse('gh_read_failed', `gh pr view ${opts.pr}`);
  let pr;
  try { pr = JSON.parse(r.stdout); } catch { refuse('gh_read_invalid', 'gh pr view printed no JSON'); }
  checkRepo(origin, pr?.url);
  const mc = pr?.mergeCommit?.oid ?? '';
  if (pr.state !== 'MERGED' || !/^[0-9a-f]{40}$/i.test(mc)) {
    refuse('not_merged', `state=${pr.state ?? 'unknown'} mergeCommit=${mc || 'none'}`);
  }
  const base = pr.baseRefName ?? '';
  if (!BASE_NAME_RE.test(base) || base.startsWith('-')) refuse('bad_base_name', JSON.stringify(base));
  const f = git(origin, ['fetch', '-q', 'origin', `+refs/heads/${base}:refs/remotes/origin/${base}`]);
  if (f.status !== 0) refuse('fetch_failed', `origin ${base}`);
  const anc = git(origin, ['merge-base', '--is-ancestor', mc, `refs/remotes/origin/${base}`]);
  if (anc.status !== 0) refuse('merge_commit_not_on_base', `${mc} is not reachable from origin/${base}`);
  return { pr, mc, base, head: pr.headRefOid ?? '', headRef: pr.headRefName ?? '' };
}

// ---- D6: draft classification --------------------------------------------



// PR numbers a frontmatter links.pr value names, read strictly: a bare number, '#N',
// or a URL of THIS repository whose path ends /pull/N. Digits elsewhere in an entry
// (an owner or repo name, a query) name nothing.
function linkedPrs(fm, repo) {
  const v = fm?.links?.pr;
  const out = [];
  for (const x of Array.isArray(v) ? v : [v]) {
    const t = String(x ?? '').trim();
    const plain = t.match(/^#?(\d+)$/);
    if (plain) { out.push(Number(plain[1])); continue; }
    const url = t.match(/^https?:\/\/[^\s?#]+\/pull\/(\d+)\/?$/);
    if (url && repo && repoSlug(t) === repo) out.push(Number(url[1]));
  }
  return out;
}

// The work item(s) THIS PR delivered: intake docs (any type but spec) in the merged
// tree that the PR added or changed, left status done with links.pr naming this PR -
// the stamp close-work-item writes. Touching a doc, filing a draft, or sharing the
// branch-name tail does not make a ref merged (F1). Returns [{ id, rel }].
function deliveredDoneDocs(origin, mc, pr, repo) {
  return doneDocsBetween(origin, `${mc}^1`, mc, pr, repo);
}

// Intake docs (any type but spec) the range from..to added or changed, status done at `to`
// with links.pr naming `pr`. Returns [{ id, rel }].
function doneDocsBetween(cwd, from, to, pr, repo) {
  const names = git(cwd, ['diff', '--name-only', '--no-renames', '--diff-filter=AM', '-z', from, to]);
  const docs = [];
  if (names.status !== 0) return docs;
  for (const rel of names.stdout.split('\0').filter(Boolean)) {
    if (!rel.endsWith('.md')) continue;
    const blob = git(cwd, ['cat-file', 'blob', `${to}:${rel}`]);
    if (blob.status !== 0) continue;
    const fm = parseFrontmatter(blob.stdout);
    if (fm?.id && fm.type !== 'spec' && fm.status === 'done' && linkedPrs(fm, repo).includes(pr)) docs.push({ id: String(fm.id), rel });
  }
  return docs;
}

function classifyDrafts(origin) {
  const ls = git(origin, ['ls-files', '--others', '--exclude-standard', '-z']);
  const candidates = (ls.status === 0 ? ls.stdout.split('\0').filter(Boolean) : [])
    .filter((rel) => rel.startsWith('docs/') && DRAFT_BASENAME_RE.test(path.posix.basename(rel)));
  return { retained: candidates.map((rel) => ({ path: rel, reason: 'leftover_draft' })) };
}

// ---- D7: archive ----------------------------------------------------------

function archiveRoot(origin, pr) {
  return path.join(origin, 'docs', 'ai', 'archive', 'merge-cleanup', `pr-${pr}`);
}

function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).flatMap((l) => {
    try { return [JSON.parse(l)]; } catch { return []; }
  });
}

function appendJsonl(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.appendFileSync(file, `${JSON.stringify(obj)}\n`);
}

// Copy `src` to `destBase` (a numeric suffix when a DIFFERENT file already
// occupies it), byte-compare, and record one manifest line unless the same
// original+sha256 is already recorded. Never overwrites, never removes `src`.
// `fresh` tells a repeat (nothing new written) from a first archive.
function archiveFile(ctx, { src, destBase, original, reason, step }) {
  const bytes = fs.readFileSync(src);
  const digest = sha256(bytes);
  let dest = destBase;
  for (let n = 1; fs.existsSync(dest) && !fs.readFileSync(dest).equals(bytes); n++) dest = `${destBase}.${n}`;
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const created = !fs.existsSync(dest);
  if (created) fs.copyFileSync(src, dest);
  if (!fs.readFileSync(dest).equals(bytes)) throw new Error(`archive copy differs from source: ${original}`);
  const rel = posix(path.relative(ctx.origin, dest));
  const manifest = path.join(archiveRoot(ctx.origin, ctx.opts.pr), 'manifest.jsonl');
  const known = readJsonl(manifest).some((m) => m.original === original && m.sha256 === digest);
  if (!known) {
    appendJsonl(manifest, { original, archive: rel, sha256: digest, reason, step, timestamp: new Date().toISOString() });
  }
  return { rel, digest, fresh: created || !known };
}


// ---- D8: base sync --------------------------------------------------------

const readBlob = (cwd, spec) => {
  const r = git(cwd, ['cat-file', 'blob', spec], { buffer: true });
  return r.status === 0 ? r.stdout : null;
};

// D2: the roadmap text without the merged ride's own entries - every pair block whose first line is
// `  - capability: <ref>` (it runs until the next line not indented by four spaces or more) and every
// `  - <ref>` line (the wave_2 entry ship-append deletes). Everything else, line endings included, stays.
function stripRideEntries(text, refs) {
  const lines = text.split(/(?<=\n)/);
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const body = lines[i].replace(/\r?\n$/, '');
    const cap = body.match(/^ {2}- capability: (.+)$/);
    if (cap && refs.has(cap[1])) {
      while (i + 1 < lines.length && /^ {4}/.test(lines[i + 1])) i++;
      continue;
    }
    const wave = body.match(/^ {2}- (.+)$/);
    if (wave && refs.has(wave[1])) continue;
    out.push(lines[i]);
  }
  return out.join('');
}

// The roadmap as three latin1 strings: the main checkout's file, the HEAD blob, the incoming blob.
function roadmapTexts(ctx, head, target) {
  let local;
  try { local = fs.readFileSync(path.join(ctx.origin, ROADMAP_PATH), 'latin1'); } catch { return null; }
  const headBlob = readBlob(ctx.origin, `${head}:${ROADMAP_PATH}`);
  const inBlob = readBlob(ctx.origin, `${target}:${ROADMAP_PATH}`);
  if (!headBlob || !inBlob) return null;
  return { local, head: headBlob.toString('latin1'), incoming: inBlob.toString('latin1') };
}

// The ride refs whose own entry differs between the HEAD blob and the local file.
function rideChangedRefs(refs, t) {
  return [...refs].sort().filter((ref) => {
    const others = new Set([...refs].filter((r) => r !== ref));
    return stripRideEntries(t.local, others) !== stripRideEntries(t.head, others);
  });
}

// D3: true only when every local change is confined to the merged ride's entries and the incoming
// roadmap carries a pair block for each of them (taking it loses no record of the ride).
function roadmapRideOnly(ctx, head, target) {
  const refs = mergedRefs(ctx);
  if (refs.size === 0) return false;
  const t = roadmapTexts(ctx, head, target);
  if (!t) return false;
  if (stripRideEntries(t.local, refs) !== stripRideEntries(t.head, refs)) return false;
  const incoming = t.incoming.split(/\r?\n/);
  return rideChangedRefs(refs, t).every((ref) => incoming.includes(`  - capability: ${ref}`));
}

// Pure derivation, no writes. Returns { refusal } or a plan.
function planSync(ctx) {
  const { origin, base } = ctx;
  const target = git(origin, ['rev-parse', '--verify', '-q', `refs/remotes/origin/${base}`]).stdout.trim();
  const cur = git(origin, ['symbolic-ref', '-q', '--short', 'HEAD']);
  const branch = cur.status === 0 ? cur.stdout.trim() : '';
  if (branch !== base) return { refusal: ['origin_not_on_base', branch || 'detached_head'] };
  const head = git(origin, ['rev-parse', '--verify', 'HEAD']).stdout.trim();
  if (head === target) return { noop: true, head, target };
  if (git(origin, ['merge-base', '--is-ancestor', head, target]).status !== 0) return { refusal: ['base_diverged', base] };

  const diff = git(origin, ['diff', '--name-status', '--no-renames', '-z', head, target]);
  const toks = diff.status === 0 ? diff.stdout.split('\0').filter(Boolean) : [];
  const incoming = new Map();
  for (let i = 0; i + 1 < toks.length; i += 2) incoming.set(toks[i + 1], toks[i][0]);
  const names = (args) => {
    const r = git(origin, args);
    return r.status === 0 ? r.stdout.split('\0').filter(Boolean) : [];
  };
  const dirty = names(['diff', '--name-only', '-z', 'HEAD']);
  const staged = new Set(names(['diff', '--cached', '--name-only', '-z']));
  const plan = { head, target, ledgers: [], index: false, roadmap: false, removeEqual: [] };
  for (const rel of dirty.sort()) {
    const isLedger = LEDGERS.includes(rel) && incoming.has(rel);
    const isIndex = rel === INDEX_PATH;
    const isRoadmap = rel === ROADMAP_PATH;
    if (!isLedger && !isIndex && !incoming.has(rel)) continue;
    if (!isLedger && !isIndex && !isRoadmap) return { refusal: ['overlap', rel] };
    if (staged.has(rel)) return { refusal: ['overlap', rel] };
    if (isIndex) { plan.index = true; continue; }
    if (isRoadmap) {
      if (!roadmapRideOnly(ctx, head, target)) return { refusal: ['overlap', rel] };
      plan.roadmap = true;
      continue;
    }
    const headBlob = readBlob(origin, `${head}:${rel}`);
    const inBlob = readBlob(origin, `${target}:${rel}`);
    let local = null;
    try { local = fs.readFileSync(path.join(origin, rel)); } catch { /* deleted locally */ }
    const prefix = (whole, part) => whole && part && whole.length >= part.length && whole.subarray(0, part.length).equals(part);
    if (!headBlob || !prefix(local, headBlob) || !prefix(inBlob, headBlob)) return { refusal: ['ledger_rewritten', rel] };
    plan.ledgers.push(rel);
  }
  for (const [rel, kind] of [...incoming].sort()) {
    if (kind !== 'A') continue;
    const abs = path.join(origin, rel);
    let st = null;
    try { st = fs.lstatSync(abs); } catch { continue; }
    const inBlob = readBlob(origin, `${target}:${rel}`);
    if (!st.isFile() || !inBlob || !fs.readFileSync(abs).equals(inBlob)) return { refusal: ['untracked_collision', rel] };
    plan.removeEqual.push(rel);
  }
  return plan;
}

// NB-2: a hard kill between rewriting a dirty ledger to the HEAD blob and
// re-appending the local tail would leave the tail only in the archive. The
// pending journal below names it; the next run puts it back before anything else.
// Any later apply finds the journal, whichever PR wrote it (NB-r2-4).
const pendingPath = (ctx) => path.join(archiveRoot(ctx.origin, ctx.opts.pr), 'sync', 'pending.json');

function pendingJournals(ctx) {
  const root = path.join(ctx.origin, 'docs', 'ai', 'archive', 'merge-cleanup');
  let names = [];
  try { names = fs.readdirSync(root); } catch { /* no archive yet */ }
  return names.sort().map((n) => path.join(root, n, 'sync', 'pending.json')).filter((f) => fs.existsSync(f));
}

const startsWith = (whole, part) => !!whole && !!part && whole.length >= part.length && whole.subarray(0, part.length).equals(part);

// What a ledger that was rewritten to the HEAD blob becomes when the archived local
// bytes (HEAD blob + local tail) go back: anything appended since stays AFTER them.
// null when the live bytes cannot be proven to be the HEAD blob plus appends.
function putBack(saved, headBlob, live) {
  if (!headBlob || !startsWith(live, headBlob)) return null;
  if (startsWith(live, saved)) return live;
  return Buffer.concat([saved, live.subarray(headBlob.length)]);
}

// Re-append (or restore) from one pending journal. Returns a detail string when it
// did work.
function resumeSync(ctx, file) {
  const { origin } = ctx;
  const rel = posix(path.relative(origin, file));
  let pending;
  try { pending = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { stop('pending_unreadable', rel); }
  const headNow = git(origin, ['rev-parse', 'HEAD']).stdout.trim();
  let entries;
  try { entries = pending.entries.map((e) => ({ ...e, saved: fs.readFileSync(path.join(origin, e.archive)), headBlob: readBlob(origin, `${pending.head}:${e.rel}`) })); } catch { stop('pending_unreadable', rel); }
  if (entries.some((e) => !e.headBlob)) stop('pending_unreadable', `${rel}: HEAD blob of a journalled file is gone`);
  let detail;
  if (headNow === pending.head) {
    // the fast-forward never happened: put the local bytes back after anything appended
    // since, the normal sync redoes the rest. Prove every file before writing any.
    const writes = [];
    for (const e of entries) {
      const abs = path.join(origin, e.rel);
      let cur = null;
      try { cur = fs.readFileSync(abs); } catch { /* removed */ }
      if (!e.ledger) { if (cur && cur.equals(e.headBlob)) writes.push([abs, e.saved]); continue; }
      const next = putBack(e.saved, e.headBlob, cur);
      if (!next) stop('pending_diverged', `${e.rel}: the live ledger no longer starts with the HEAD blob; the local tail stays in ${e.archive} and the journal ${rel}`);
      writes.push([abs, next]);
    }
    for (const [abs, bytes] of writes) fs.writeFileSync(abs, bytes);
    detail = 'restored local state of an interrupted sync';
  } else {
    mergeLedgerTails(ctx, entries.filter((e) => e.ledger).map((e) => ({ rel: e.rel, headBlob: e.headBlob, bytes: e.saved })));
    if (entries.some((e) => e.rel === INDEX_PATH)) regenIndex(ctx);
    detail = 're-appended the local ledger tail of an interrupted sync';
  }
  fs.rmSync(file, { force: true });
  return detail;
}

function mergeLedgerTails(ctx, items) {
  const { origin, opts } = ctx;
  const root = archiveRoot(origin, opts.pr);
  const tmp = path.join(root, 'sync', '.tmp');
  for (const s of items) {
    fs.mkdirSync(tmp, { recursive: true });
    const baseF = path.join(tmp, 'base'); const theirs = path.join(tmp, 'theirs'); const out = path.join(tmp, 'out');
    fs.writeFileSync(baseF, s.headBlob);
    fs.writeFileSync(theirs, s.bytes);
    const m = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'ledger-merge.mjs'), '--base', baseF, '--ours', path.join(origin, s.rel), '--theirs', theirs, '--out', out], { encoding: 'utf8' });
    if (m.status !== 0) stop('ledger_merge_failed', `${s.rel}: local bytes kept in ${posix(path.relative(origin, path.join(root, 'sync', s.rel)))}`);
    fs.copyFileSync(out, path.join(origin, s.rel));
  }
  fs.rmSync(tmp, { recursive: true, force: true });
}

function regenIndex(ctx) {
  const g = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'generate-docs-index.mjs')], { cwd: ctx.origin, encoding: 'utf8' });
  if (g.status !== 0) stop('index_regen_failed', (g.stderr || g.stdout).trim().split('\n')[0] ?? '');
}

function syncBase(ctx) {
  const resumed = pendingJournals(ctx).map((f) => resumeSync(ctx, f)).pop() ?? null;
  const plan = planSync(ctx);
  if (plan.refusal) stop(...plan.refusal);
  if (plan.noop) return resumed ? { status: 'done', detail: resumed } : { status: 'noop', detail: 'already_at_target' };
  const { origin, opts } = ctx;
  const root = archiveRoot(origin, opts.pr);
  const saved = [];
  // Puts the pre-sync local bytes back after a failed fast-forward, keeping anything another
  // session appended meanwhile. Returns the files it could not prove safe to touch.
  const restore = () => {
    const stuck = [];
    for (const s of saved) {
      const abs = path.join(origin, s.rel);
      let cur = null;
      try { cur = fs.readFileSync(abs); } catch { /* removed */ }
      const next = s.ledger ? putBack(s.bytes, s.headBlob, cur) : s.bytes;
      if (next) fs.writeFileSync(abs, next); else stuck.push(s.rel);
    }
    return stuck;
  };
  const pendingEntries = [];
  for (const rel of [...plan.ledgers, ...(plan.index ? [INDEX_PATH] : []), ...(plan.roadmap ? [ROADMAP_PATH] : [])]) {
    const abs = path.join(origin, rel);
    const bytes = fs.readFileSync(abs);
    const a = archiveFile(ctx, { src: abs, destBase: path.join(root, 'sync', rel), original: rel, reason: 'pre_sync_local_state', step: 'sync-base' });
    saved.push({ rel, bytes, headBlob: readBlob(origin, `${plan.head}:${rel}`), ledger: LEDGERS.includes(rel) });
    pendingEntries.push({ rel, archive: a.rel, ledger: LEDGERS.includes(rel) });
  }
  if (pendingEntries.length > 0) {
    fs.mkdirSync(path.dirname(pendingPath(ctx)), { recursive: true });
    fs.writeFileSync(pendingPath(ctx), `${JSON.stringify({ head: plan.head, entries: pendingEntries })}\n`);
  }
  for (const s of saved) fs.writeFileSync(path.join(origin, s.rel), s.headBlob);
  crashAt('sync-after-rewrite');
  // Untracked copies byte-equal to the incoming blob would block the fast-forward
  // and are recreated by it; keep the bytes to put back should it fail.
  const removed = plan.removeEqual.map((rel) => ({ rel, bytes: fs.readFileSync(path.join(origin, rel)) }));
  for (const r of removed) fs.unlinkSync(path.join(origin, r.rel));
  const ff = git(origin, ['merge', '--ff-only', plan.target]);
  if (ff.status !== 0) {
    const stuck = restore();
    for (const r of removed) { fs.mkdirSync(path.dirname(path.join(origin, r.rel)), { recursive: true }); fs.writeFileSync(path.join(origin, r.rel), r.bytes); }
    const why = (ff.stderr || ff.stdout).trim().split('\n')[0] ?? '';
    if (stuck.length > 0) stop('sync_failed', `${why}; pending_diverged: ${stuck.join(', ')} changed meanwhile, the local tail stays archived and the journal is kept`);
    fs.rmSync(pendingPath(ctx), { force: true });
    stop('sync_failed', why);
  }
  const headNow = git(origin, ['rev-parse', 'HEAD']).stdout.trim();
  const refNow = git(origin, ['rev-parse', `refs/heads/${ctx.base}`]).stdout.trim();
  if (headNow !== plan.target || refNow !== plan.target) stop('sync_failed', `head_ref_mismatch HEAD=${headNow} ${ctx.base}=${refNow} want=${plan.target}`);
  crashAt('sync-after-ff');
  mergeLedgerTails(ctx, saved.filter((x) => x.ledger));
  fs.rmSync(pendingPath(ctx), { force: true });
  if (plan.index) regenIndex(ctx);
  return { status: 'done', detail: `fast-forward to ${plan.target.slice(0, 12)}` };
}

// ---- D10: ride worktree and branch ----------------------------------------

const realOr = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };

function findRideWorktree(ctx) {
  const r = git(ctx.origin, ['worktree', 'list', '--porcelain']);
  if (r.status !== 0 || !ctx.headRef) return null;
  for (const block of r.stdout.split(/\n\s*\n/)) {
    const get = (k) => block.match(new RegExp(`^${k} (.+)$`, 'm'))?.[1] ?? null;
    const wtPath = get('worktree');
    if (!wtPath || get('branch') !== `refs/heads/${ctx.headRef}`) continue;
    if (realOr(wtPath) === ctx.origin) continue;
    return { path: realOr(wtPath), head: get('HEAD') ?? '' };
  }
  return null;
}

// ---- D2: submodule proof --------------------------------------------------

const SUB_KINDS = ['dirty', 'unpushed', 'stash', 'no_remote', 'unverifiable'];

// Every initialized submodule below `dir` (a gitlink whose path holds a `.git`), nested
// ones included, as paths relative to `base`, sorted. Uninitialized gitlinks are skipped.
function submoduleMembers(dir, base = dir) {
  const ls = git(dir, ['ls-files', '--stage', '-z']);
  if (ls.status !== 0) return { members: [], failed: [posix(path.relative(base, dir)) || '.'] };
  const members = [];
  const failed = [];
  for (const entry of ls.stdout.split('\0').filter(Boolean)) {
    const m = entry.match(/^160000 [0-9a-f]+ \d\t(.+)$/s);
    if (!m) continue;
    const abs = path.join(dir, m[1]);
    if (!fs.existsSync(path.join(abs, '.git'))) continue;
    members.push(posix(path.relative(base, abs)));
    const inner = submoduleMembers(abs, base);
    members.push(...inner.members);
    failed.push(...inner.failed);
  }
  return { members: members.sort(), failed };
}

// Git dirs below `modules` (names may hold slashes; nested ones live under <gitdir>/modules).
function moduleGitDirs(modules) {
  const found = [];
  const walk = (d) => {
    let kids = [];
    try { kids = fs.readdirSync(d, { withFileTypes: true }).filter((e) => e.isDirectory()); } catch { return; }
    for (const k of kids) {
      const abs = path.join(d, k.name);
      if (fs.existsSync(path.join(abs, 'HEAD')) && fs.existsSync(path.join(abs, 'objects'))) {
        found.push(abs);
        walk(path.join(abs, 'modules'));
      } else walk(abs);
    }
  };
  walk(modules);
  return found;
}

function adminModulesDir(wtPath) {
  const r = git(wtPath, ['rev-parse', '--absolute-git-dir']);
  return r.status === 0 ? path.join(realOr(r.stdout.trim()), 'modules') : null;
}

// True when the worktree holds an initialized submodule or a modules dir in its admin dir
// (git refuses a plain `worktree remove` for either, F1/F4).
function hasSubmodules(wtPath) {
  if (submoduleMembers(wtPath).members.length > 0) return true;
  const mod = adminModulesDir(wtPath);
  return !!mod && fs.existsSync(mod);
}

// The ignored listing of one submodule (D4). Test seam AAI_MERGE_CLEANUP_FAIL_IGNORED_LS=<member>
// makes it fail, so the fail-closed path is reachable deterministically; with
// AAI_MERGE_CLEANUP_FAIL_IGNORED_LS_AT=<phase> it fails only in that phase (a one-off failure).
function ignoredListing(wtPath, member, phase = 'verify') {
  const at = seam('AAI_MERGE_CLEANUP_FAIL_IGNORED_LS_AT');
  if (seam('AAI_MERGE_CLEANUP_FAIL_IGNORED_LS') === member && (!at || at === phase)) return { status: 1, stdout: '', stderr: '' };
  return git(path.join(wtPath, member), ['ls-files', '--others', '--ignored', '--exclude-standard', '--directory', '-z']);
}

// Per initialized submodule, recursive (D2): clean, has a remote, pushed, no stash.
// Returns [{ path, kind, fact }] sorted by path; one entry per offending member.
function submoduleBlockers(wtPath) {
  const out = [];
  const { members, failed } = submoduleMembers(wtPath);
  for (const f of failed) out.push({ path: f, kind: 'unverifiable', fact: 'git ls-files failed' });
  const gitDirs = new Set();
  for (const rel of members) {
    const abs = path.join(wtPath, rel);
    const gd = git(abs, ['rev-parse', '--absolute-git-dir']);
    if (gd.status !== 0) { out.push({ path: rel, kind: 'unverifiable', fact: 'git rev-parse failed' }); continue; }
    gitDirs.add(realOr(gd.stdout.trim()));
    const st = git(abs, ['status', '--porcelain', '--ignore-submodules=dirty', '--untracked-files=normal']);
    if (st.status !== 0) { out.push({ path: rel, kind: 'unverifiable', fact: 'git status failed' }); continue; }
    const changed = st.stdout.split('\n').filter((l) => l.trim() !== '').length;
    if (changed > 0) { out.push({ path: rel, kind: 'dirty', fact: `${changed} changed` }); continue; }
    const rm = git(abs, ['remote']);
    if (rm.status !== 0) { out.push({ path: rel, kind: 'unverifiable', fact: 'git remote failed' }); continue; }
    if (rm.stdout.trim() === '') { out.push({ path: rel, kind: 'no_remote', fact: 'no remote configured' }); continue; }
    const rl = git(abs, ['rev-list', '--count', 'HEAD', '--branches', '--tags', '--not', '--remotes']);
    const unpushed = Number(rl.stdout.trim());
    if (rl.status !== 0 || !Number.isFinite(unpushed)) { out.push({ path: rel, kind: 'unverifiable', fact: 'git rev-list failed' }); continue; }
    if (unpushed > 0) { out.push({ path: rel, kind: 'unpushed', fact: `${unpushed} commit${unpushed === 1 ? '' : 's'} not on any remote-tracking ref` }); continue; }
    const sh = git(abs, ['rev-parse', '-q', '--verify', 'refs/stash']);
    if (sh.status === 0) out.push({ path: rel, kind: 'stash', fact: 'stash present' });
    // --force deletes ignored files, so a listing that fails can be neither archived nor named: fail closed
    if (ignoredListing(wtPath, rel).status !== 0) out.push({ path: rel, kind: 'unverifiable', fact: 'git ls-files --ignored failed' });
  }
  const mod = adminModulesDir(wtPath);
  if (mod && fs.existsSync(mod)) {
    for (const dir of moduleGitDirs(mod)) {
      if (!gitDirs.has(realOr(dir))) out.push({ path: posix(path.relative(mod, dir)), kind: 'unverifiable', fact: 'git dir of no initialized submodule' });
    }
  }
  return out.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

// D3: [reason, detail] for a blocker list, else null. Reason is the first kind present.
function blockerVerdict(blockers) {
  const kind = SUB_KINDS.find((k) => blockers.some((b) => b.kind === k));
  if (!kind) return null;
  return [`submodule_${kind}`, blockers.map((b) => `${b.path} (${b.kind}: ${b.fact})`).join('; ')];
}

// D6: the ride worktree's appended ledger lines. One entry per modified ledger when EVERY porcelain
// entry is an unstaged ` M` of a LEDGERS file whose bytes are the HEAD blob plus whole appended
// lines; null as soon as anything else is in the worktree.
function ledgerTails(ctx, wt) {
  const st = git(wt.path, ['status', '--porcelain=v1', '-z', '--ignore-submodules=dirty', '--untracked-files=normal']);
  if (st.status !== 0) return null;
  const tails = [];
  for (const e of st.stdout.split('\0').filter(Boolean)) {
    const rel = e.slice(3);
    if (e.slice(0, 3) !== ' M ' || !LEDGERS.includes(rel)) return null;
    const H = readBlob(wt.path, `HEAD:${rel}`);
    let B = null;
    try { B = fs.readFileSync(path.join(wt.path, rel)); } catch { /* removed */ }
    if (!H || !B) return null;
    const tail = B.subarray(H.length);
    const appendOnly = B.length > H.length && B.subarray(0, H.length).equals(H) && (H.length === 0 || H[H.length - 1] === 10) && tail[tail.length - 1] === 10;
    if (!appendOnly) return null;
    tails.push({ rel, head: H, bytes: B, tail });
  }
  return tails.sort((a, b) => LEDGERS.indexOf(a.rel) - LEDGERS.indexOf(b.rel));
}

// First eligibility failure as [reason, detail], else null. D7: with allowTails a worktree whose only
// changes are append-only ledger tails is clean; the strict form is the late check before the removal.
function worktreeVerdict(ctx, wt, { allowTails = false } = {}) {
  if (!fs.existsSync(wt.path)) return ['worktree_missing', wt.path];
  const cwd = realOr(process.cwd());
  if (cwd === wt.path || cwd.startsWith(wt.path + path.sep)) return ['cwd_inside_target', wt.path];
  const st = git(wt.path, ['status', '--porcelain', '--ignore-submodules=dirty', '--untracked-files=normal']);
  if (st.status !== 0) return ['worktree_dirty', wt.path];
  if (st.stdout.trim() !== '' && !(allowTails && ledgerTails(ctx, wt) !== null)) return ['worktree_dirty', wt.path];
  const blockers = submoduleBlockers(wt.path);
  if (blockers.length > 0) return blockerVerdict(blockers);
  if (wt.head !== ctx.head) return ['tip_mismatch', `${ctx.headRef} at ${wt.head || 'unknown'}, PR head ${ctx.head}`];
  const lk = lockStatus(wt.path);
  if (lk.held && lk.alive && lk.pid !== Number(ctx.opts.pid)) return ['session_locked', `${lk.pid} ${lk.worktree ?? ''}`.trim()];
  return null;
}

function branchTip(ctx) {
  const r = git(ctx.origin, ['rev-parse', '--verify', '-q', `refs/heads/${ctx.headRef}`]);
  return r.status === 0 ? r.stdout.trim() : null;
}

function archiveRuntime(ctx) {
  const wt = findRideWorktree(ctx);
  if (!wt) return { status: 'noop', detail: 'no_worktree' };
  const statePath = path.join(wt.path, STATE_REL);
  if (!fs.existsSync(statePath)) return { status: 'noop', detail: 'no_state' };
  const root = archiveRoot(ctx.origin, ctx.opts.pr);
  const a = archiveFile(ctx, { src: statePath, destBase: path.join(root, 'worktree', STATE_REL), original: `worktree:${STATE_REL}`, reason: 'runtime_archive', step: 'archive-runtime' });
  if (!a.fresh) return { status: 'noop', detail: 'already_archived' };
  return { status: 'done', detail: '1 archived' };
}

// ---- D4: ignored content inside submodules ---------------------------------

const REMOVED_REL = 'removed.jsonl';

// Ignored entries of every initialized submodule: regular files to archive, and the
// fully ignored directories / non-regular entries that are only named (git lists a wholly
// ignored directory once, with a trailing slash, F8). Paths are relative to the worktree.
function submoduleIgnored(wtPath, phase = 'verify') {
  const files = [];
  const named = [];
  for (const member of submoduleMembers(wtPath).members) {
    const ls = ignoredListing(wtPath, member, phase);
    // The proof already refuses a failing listing; a one-off failure after it passed must not
    // let --force delete this submodule's ignored files unarchived and unnamed.
    if (ls.status !== 0) stop('submodule_unverifiable', `${member} (unverifiable: git ls-files --ignored failed)`);
    for (const entry of ls.stdout.split('\0').filter(Boolean)) {
      const rel = `${member}/${entry}`;
      if (entry.endsWith('/')) { named.push({ path: rel, kind: 'directory' }); continue; }
      let st = null;
      try { st = fs.lstatSync(path.join(wtPath, rel)); } catch { continue; }
      if (st.isFile()) files.push(rel); else named.push({ path: rel, kind: 'non_regular' });
    }
  }
  return { files: files.sort(), named: named.sort((a, b) => (a.path < b.path ? -1 : 1)) };
}

// Archive each ignored regular file under worktree-submodules/ and record each entry that is
// only named in removed.jsonl (deduplicated), before the worktree goes. A repeat adds nothing.
function archiveSubmoduleIgnored(ctx, wt) {
  const root = archiveRoot(ctx.origin, ctx.opts.pr);
  const { files, named } = submoduleIgnored(wt.path, 'archive');
  for (const rel of files) {
    archiveFile(ctx, { src: path.join(wt.path, rel), destBase: path.join(root, 'worktree-submodules', rel), original: `worktree:${rel}`, reason: 'submodule_ignored', step: 'remove-worktree' });
  }
  const file = path.join(root, REMOVED_REL);
  const known = readJsonl(file);
  for (const n of named) {
    if (!known.some((k) => k.path === n.path && k.kind === n.kind)) appendJsonl(file, { ...n, reason: 'submodule_ignored_not_archived' });
  }
}

// ---- D4b: tag refs inside submodules ---------------------------------------

const TAGS_DIR = '.aai-submodule-tags';

// Every tag ref of one initialized submodule: [{ ref, oid, type }]. The commit proof compares
// reachability only, so a local-only tag on a pushed commit passes it; --force then deletes the
// git dir and with it the tag name and an annotated tag's own object. Archive-first, no network
// (SPEC-0218 D7): the refs are archived instead of blocked on. A failing listing fails closed.
function submoduleTags(wtPath, member) {
  const r = git(path.join(wtPath, member), ['for-each-ref', '--format=%(refname) %(objectname) %(objecttype)', 'refs/tags']);
  if (r.status !== 0) stop('submodule_unverifiable', `${member} (unverifiable: git for-each-ref failed)`);
  return r.stdout.split('\n').filter(Boolean).map((l) => { const [ref, oid, type] = l.split(' '); return { ref, oid, type }; });
}

// Archive each submodule's tag refs under worktree-submodules/<sub path>/.aai-submodule-tags/:
// tags.txt (`<ref> <oid> <type>` per line) plus objects/<oid>.tag, the raw `git cat-file tag` bytes
// of every annotated tag. Restore, inside the submodule:
//   lightweight:  git update-ref <ref> <oid>
//   annotated:    git hash-object -t tag -w --stdin < objects/<oid>.tag   (prints <oid>), then git update-ref <ref> <oid>
// Idempotent through archiveFile (one manifest line per file and content, reason submodule_tags).
function archiveSubmoduleTags(ctx, wt) {
  const root = archiveRoot(ctx.origin, ctx.opts.pr);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'merge-cleanup-tags-'));
  try {
    for (const member of submoduleMembers(wt.path).members) {
      const tags = submoduleTags(wt.path, member);
      if (tags.length === 0) continue;
      const base = path.join(root, 'worktree-submodules', member, TAGS_DIR);
      const put = (name, bytes, destRel) => {
        const src = path.join(tmp, name);
        fs.writeFileSync(src, bytes);
        archiveFile(ctx, { src, destBase: path.join(base, destRel), original: `worktree:${member}/${TAGS_DIR}/${destRel}`, reason: 'submodule_tags', step: 'remove-worktree' });
      };
      for (const t of tags.filter((x) => x.type === 'tag')) {
        const o = git(path.join(wt.path, member), ['cat-file', 'tag', t.oid], { buffer: true });
        if (o.status !== 0) stop('submodule_unverifiable', `${member} (unverifiable: git cat-file tag failed)`);
        put('obj', o.stdout, `objects/${t.oid}.tag`);
      }
      put('tags', tags.map((t) => `${t.ref} ${t.oid} ${t.type}\n`).join(''), 'tags.txt');
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// Test seam: another session writes into a submodule between the archive and the final verify.
function touchAt(point, wtPath) {
  const v = seam('AAI_MERGE_CLEANUP_TOUCH_AT');
  if (v && v.startsWith(`${point}:`)) fs.appendFileSync(path.join(wtPath, v.slice(point.length + 1)), 'written by another session\n');
}

const LEDGER_TAIL_REASON = 'ride_ledger_tail';
const LEDGER_TAILS_DIR = 'worktree-ledger-tails';

// Does `part` occur in `buf` at a line start (offset 0 or right after a newline), at or after `from`?
function atLineStart(buf, part, from = 0) {
  if (!buf || part.length === 0) return false;
  for (let i = buf.indexOf(part, from); i >= 0; i = buf.indexOf(part, i + 1)) if (i === 0 || buf[i - 1] === 10) return true;
  return false;
}

const LEDGER_APPEND_STEP = 'ledger-append';
const countLines = (buf) => { let n = 0; for (const b of buf) if (b === 10) n++; return n; };

// D8: move the ride worktree's appended ledger lines to the main checkout, archive-first and
// idempotent: a re-run after a crash at any point appends no tail byte twice and loses none.
function moveLedgerTails(ctx, wt) {
  const tails = ledgerTails(ctx, wt);
  if (!tails || tails.length === 0) return;
  const root = archiveRoot(ctx.origin, ctx.opts.pr);
  const journal = path.join(root, 'journal.jsonl');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'merge-cleanup-tail-'));
  try {
    for (const t of tails) {
      const main = path.join(ctx.origin, t.rel);
      let cur = null;
      try { cur = fs.readFileSync(main); } catch { /* absent: the move creates it */ }
      if (cur && cur.length > 0 && cur[cur.length - 1] !== 10) stop('ledger_unaligned', t.rel);
      const src = path.join(tmp, 'tail');
      fs.writeFileSync(src, t.tail);
      const arch = archiveFile(ctx, { src, destBase: path.join(root, LEDGER_TAILS_DIR, t.rel), original: `worktree:${t.rel}`, reason: LEDGER_TAIL_REASON, step: 'remove-worktree' });
      // D8: an earlier archive counts as already moved only when an append-intent record for it precedes
      // the append and its bytes occur at a line start in the main ledger at or after the recorded
      // length of the ledger at intent time. This run's own archive has no intent yet, so a first run
      // appends the whole tail, a line already present in the ledger included.
      // A reset record (written after the ride ledger was reset) retires every intent before it: those
      // bytes were moved and the ride file rewritten, so a later identical tail is new content.
      let open = [];
      const doneArchives = new Set();
      for (const r of readJsonl(journal)) {
        if (r.step !== LEDGER_APPEND_STEP || r.ledger !== t.rel) continue;
        if (r.status === 'intent') open.push(r);
        else if (r.status === 'reset') { open = []; doneArchives.clear(); }
        else if (r.status === 'done') doneArchives.add(r.archive);
      }
      // A later intent's segOffset is what that run judged already appended. An earlier intent whose archive
      // is longer than a later valid segOffset was judged not appended: it crashed before its append, and its
      // bytes only look present because the later append starts with the same bytes. It is never counted.
      const judgedMissing = (i, len) => open.slice(i + 1).some((l) => Number.isInteger(l.segOffset) && l.segOffset >= 0 && (!Number.isInteger(l.length) || l.segOffset <= l.length) && l.segOffset < len);
      let already = 0;
      for (const [i, r] of open.entries()) {
        let c = null;
        try { c = fs.readFileSync(path.join(ctx.origin, r.archive)); } catch { continue; }
        if (judgedMissing(i, c.length)) continue;
        const from = Math.min(r.mainLen ?? 0, cur ? cur.length : 0);
        // the intent appended the archive from segOffset on (an earlier prefix was already in main); an
        // intent without one appended the whole archive
        const segAt = Number.isInteger(r.segOffset) && r.segOffset >= 0 && r.segOffset <= c.length ? r.segOffset : 0;
        const segment = c.subarray(segAt);
        if (c.length > t.tail.length || !t.tail.subarray(0, c.length).equals(c) || (r.segSha256 && r.segSha256 !== sha256(segment)) || !atLineStart(cur, segment, from)) continue;
        already = Math.max(already, c.length);
        // the append happened but the crash came before its done record: record it now, once per archive
        if (!doneArchives.has(r.archive)) {
          doneArchives.add(r.archive);
          appendJsonl(journal, { step: LEDGER_APPEND_STEP, status: 'done', ledger: t.rel, archive: r.archive, sha256: r.sha256, lines: r.lines, intent: r.timestamp, timestamp: new Date().toISOString() });
        }
      }
      if (already < t.tail.length) {
        const seg = t.tail.subarray(already);
        const intentAt = new Date().toISOString();
        appendJsonl(journal, { step: LEDGER_APPEND_STEP, status: 'intent', ledger: t.rel, archive: arch.rel, sha256: arch.digest, length: t.tail.length, segOffset: already, segSha256: sha256(seg), mainLen: cur ? cur.length : 0, lines: countLines(seg), timestamp: intentAt });
        crashAt('ledger-move-after-intent');
        fs.mkdirSync(path.dirname(main), { recursive: true });
        fs.appendFileSync(main, seg);
        crashAt('ledger-move-after-append');
        appendJsonl(journal, { step: LEDGER_APPEND_STEP, status: 'done', ledger: t.rel, archive: arch.rel, sha256: arch.digest, lines: countLines(seg), intent: intentAt, timestamp: new Date().toISOString() });
      }
      const abs = path.join(wt.path, t.rel);
      let now = null;
      try { now = fs.readFileSync(abs); } catch { /* removed */ }
      if (!now || !now.equals(t.bytes)) stop('worktree_dirty', `${t.rel} changed during the move`);
      fs.writeFileSync(abs, t.head);
      appendJsonl(journal, { step: LEDGER_APPEND_STEP, status: 'reset', ledger: t.rel, archive: arch.rel, timestamp: new Date().toISOString() });
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// D10: the moved ledger lines, read from the durable journal: one entry per ledger, the lines
// of every completed append (one per archive), never the archived tail that a skip left unappended.
function movedFromManifest(ctx) {
  const done = new Map();
  for (const r of readJsonl(path.join(archiveRoot(ctx.origin, ctx.opts.pr), 'journal.jsonl'))) {
    if (r.step !== LEDGER_APPEND_STEP || r.status !== 'done') continue;
    const e = done.get(r.ledger) ?? { ledger: r.ledger, lines: 0, sha256: r.sha256, archive: r.archive, seen: new Set() };
    const key = r.intent ?? r.archive;
    if (!e.seen.has(key)) { e.seen.add(key); e.lines += r.lines; e.sha256 = r.sha256; e.archive = r.archive; }
    done.set(r.ledger, e);
  }
  return [...done.values()].map(({ ledger, lines, sha256: digest, archive }) => ({ ledger, lines, sha256: digest, archive }))
    .sort((x, y) => LEDGERS.indexOf(x.ledger) - LEDGERS.indexOf(y.ledger));
}

function removeWorktree(ctx) {
  const wt = findRideWorktree(ctx);
  if (!wt) return { status: 'noop', detail: 'no_worktree' };
  const why = worktreeVerdict(ctx, wt, { allowTails: true });
  if (why) stop(...why);
  moveLedgerTails(ctx, wt);
  archiveSubmoduleIgnored(ctx, wt);
  archiveSubmoduleTags(ctx, wt);
  touchAt('before-remove-verify', wt.path);
  // the proof runs again as the last check, right before the destructive call (D3); strict, so a line
  // appended after the move stops the run (exit 4) instead of reaching a forced removal
  const late = worktreeVerdict(ctx, wt, { allowTails: false });
  if (late) stop(...late);
  const withSubmodules = hasSubmodules(wt.path);
  const lk = lockStatus(wt.path);
  if (lk.held && lk.pid === Number(ctx.opts.pid)) lockRelease({ cwd: wt.path, pid: lk.pid });
  // git refuses a plain remove once submodules are initialized (F1); the proof above is what
  // makes the one --force safe, so only this engine forces and only after it
  const r = withSubmodules
    ? git(ctx.origin, ['worktree', 'remove', '--force', wt.path])
    : git(ctx.origin, ['worktree', 'remove', wt.path]);
  if (r.status !== 0) stop('worktree_remove_failed', (r.stderr || r.stdout).trim().split('\n')[0] ?? '');
  return { status: 'done', detail: wt.path };
}

// spec-merge-cleanup-delete-remote-branch D2: the read-only proofs before the merged origin
// branch may be deleted. Returns { retain: [reason, fact] }, { absent: true } or { oid }.
const remoteFirstLine = (s) => String(s ?? '').trim().split('\n')[0].trim();
function remoteGit(origin, args) {
  return spawnSync('git', args, {
    cwd: origin, encoding: 'utf8', timeout: 120000, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
  });
}
function remoteProof(ctx) {
  const b = ctx.headRef;
  if (!BASE_NAME_RE.test(b) || b.startsWith('-') || git(ctx.origin, ['check-ref-format', `refs/heads/${b}`]).status !== 0) {
    return { retain: ['remote_bad_name', JSON.stringify(b)] };
  }
  if (ctx.pr.isCrossRepository === true) return { retain: ['remote_fork', 'the PR head lives in another repository'] };
  if (ctx.pr.isCrossRepository !== false) return { retain: ['remote_unknown', 'the PR head repository is not known'] };
  // the deletion push goes to the push URL; every proof below reads the fetch URL (D2 step 2b)
  const urlsOf = (args) => {
    const u = remoteGit(ctx.origin, ['remote', 'get-url', ...args, 'origin']);
    return u.error || u.status !== 0 ? null : u.stdout.split('\n').map((l) => l.trim()).filter(Boolean);
  };
  const fetchUrls = urlsOf(['--all']);
  const pushUrls = urlsOf(['--push', '--all']);
  if (!fetchUrls || !pushUrls || fetchUrls.length === 0) return { retain: ['remote_unknown', 'the push URL cannot be compared with the fetch URL'] };
  if (fetchUrls.length !== 1 || pushUrls.length !== 1 || fetchUrls[0] !== pushUrls[0]) return { retain: ['remote_unknown', 'the push URL differs from the fetch URL'] };
  const r = remoteGit(ctx.origin, ['ls-remote', '--symref', 'origin', 'HEAD', `refs/heads/${b}`]);
  if (r.error || r.status !== 0) return { retain: ['remote_unknown', remoteFirstLine(r.error?.message || r.stderr || r.stdout) || 'git ls-remote failed'] };
  let defaultBranch = '';
  let remoteOid = '';
  for (const line of r.stdout.split('\n')) {
    const sym = line.match(/^ref: refs\/heads\/(\S+)\tHEAD$/);
    if (sym) defaultBranch = sym[1];
    const ref = line.match(/^([0-9a-f]{40})\trefs\/heads\/(.+)$/);
    if (ref && ref[2] === b) remoteOid = ref[1];
  }
  if (!defaultBranch) {
    const local = git(ctx.origin, ['symbolic-ref', '-q', 'refs/remotes/origin/HEAD']).stdout.trim();
    defaultBranch = local.startsWith('refs/remotes/origin/') ? local.slice('refs/remotes/origin/'.length) : '';
  }
  if (!defaultBranch) return { retain: ['remote_unknown', 'the default branch of origin is not known'] };
  if ([ctx.base, defaultBranch].includes(b)) return { retain: ['remote_is_base', `${b} is the base or default branch`] };
  if (remoteOid === '') return { absent: true };
  if (!/^[0-9a-f]{40}$/i.test(ctx.head) || remoteOid !== ctx.head) return { retain: ['remote_moved', `origin/${b} at ${remoteOid}, PR head ${ctx.head || 'unknown'}`] };
  const based = dependentNumbers(ghDependents(ctx.origin, b, 'base'));
  const opened = dependentNumbers(ghDependents(ctx.origin, b, 'head'));
  if (based === null || opened === null) return { retain: ['remote_unknown', 'open pull requests based on or opened from the branch could not be listed'] };
  const list = (ns) => ns.map((n) => `#${n}`).join(', ');
  const facts = [];
  if (based.length > 0) facts.push(`open pull requests based on it: ${list(based)}`);
  if (opened.length > 0) facts.push(`open pull requests opened from it: ${list(opened)}`);
  if (facts.length > 0) return { retain: ['remote_has_dependents', facts.join('; ')] };
  return { oid: remoteOid };
}

// D3/D4/D5: delete the merged origin branch by compare-and-swap, never stopping the run.
function deleteRemoteBranch(ctx) {
  const b = ctx.headRef;
  const retain = (reason, fact = '') => ({ status: 'retained', detail: fact ? `${reason} ${fact}` : reason });
  const proof = remoteProof(ctx);
  if (proof.retain) return retain(...proof.retain);
  if (proof.absent) return { status: 'noop', detail: 'remote_absent' };
  const lease = `--force-with-lease=refs/heads/${b}:${ctx.head}`;
  const r = remoteGit(ctx.origin, ['push', '--porcelain', lease, 'origin', `:refs/heads/${b}`]);
  if (r.error) return retain('remote_unknown', remoteFirstLine(r.error.message));
  const cols = r.stdout.split('\n').map((l) => l.split('\t')).find((c) => c.length >= 3 && c[1].endsWith(`refs/heads/${b}`));
  const summary = cols ? cols[2].trim() : '';
  if (r.status === 0 && summary.startsWith('[deleted]')) return { status: 'done', detail: b };
  if (summary.startsWith('[rejected] (stale info)')) {
    const again = remoteProof(ctx);
    if (again.absent) return { status: 'noop', detail: 'remote_absent' };
    if (again.retain) return retain(...again.retain);
  }
  const hook = remoteFirstLine((r.stderr.split('\n').find((l) => l.startsWith('remote: ')) ?? '').slice('remote: '.length));
  const why = [summary, hook].filter(Boolean).join(' ') || remoteFirstLine(r.stderr || r.stdout) || `git push exited ${r.status}`;
  return retain('remote_delete_rejected', why);
}

function deleteBranch(ctx) {
  let localDone = false;
  const tip = branchTip(ctx);
  const cur = git(ctx.origin, ['symbolic-ref', '-q', '--short', 'HEAD']).stdout.trim();
  if (tip && ctx.headRef !== ctx.base && ctx.headRef !== cur) {
    if (!/^[0-9a-f]{40}$/i.test(ctx.head)) stop('branch_moved', 'PR head sha unknown');
    const r = git(ctx.origin, ['update-ref', '-d', `refs/heads/${ctx.headRef}`, ctx.head]);
    if (r.status !== 0) stop('branch_moved', `${ctx.headRef} no longer at ${ctx.head}`);
    localDone = true;
  }
  const remote = deleteRemoteBranch(ctx);
  if (remote.status === 'retained') {
    ctx.remoteRetained = remote;
  }
  if (localDone || remote.status === 'done') {
    const detail = remote.status === 'retained' ? `${ctx.headRef} ${remote.detail}` : ctx.headRef;
    return { status: 'done', detail };
  }
  if (remote.status === 'retained') {
    return remote;
  }
  return { status: 'noop', detail: 'no_branch' };
}

// Everything that can refuse, derived before the first write (exit 3).
function planChecks(ctx) {
  if (!ctx.headRef || !BASE_NAME_RE.test(ctx.headRef) || ctx.headRef.startsWith('-')) refuse('bad_head_name', JSON.stringify(ctx.headRef));
  const sync = planSync(ctx);
  if (sync.refusal) refuse(...sync.refusal);
  const wt = findRideWorktree(ctx);
  if (wt) {
    const why = worktreeVerdict(ctx, wt, { allowTails: true });
    if (why) refuse(...why);
    for (const t of ledgerTails(ctx, wt) ?? []) {
      let cur = null;
      try { cur = fs.readFileSync(path.join(ctx.origin, t.rel)); } catch { /* absent */ }
      if (cur && cur.length > 0 && cur[cur.length - 1] !== 10) refuse('ledger_unaligned', t.rel);
    }
  } else {
    const tip = branchTip(ctx);
    if (tip && tip !== ctx.head && ctx.headRef !== ctx.base) refuse('tip_mismatch', `${ctx.headRef} at ${tip}, PR head ${ctx.head}`);
  }
}

// ---- D9: focus, index, audit, report --------------------------------------

// Work items this PR delivered (see deliveredDoneDocs), and their ids.
function mergedDocs(ctx) {
  if (!ctx.docs) ctx.docs = deliveredDoneDocs(ctx.origin, ctx.mc, ctx.opts.pr, repoSlug(ctx.pr?.url));
  return ctx.docs;
}

function mergedRefs(ctx) {
  if (!ctx.refs) ctx.refs = new Set(mergedDocs(ctx).map((d) => d.id));
  return ctx.refs;
}


function reportStep(ctx, steps) {
  if (!steps.some((s) => s.status === 'done')) return { status: 'noop', detail: 'stdout' };
  return { status: 'done', detail: 'stdout' };
}

// ---- steps ----------------------------------------------------------------

const HANDLERS = {
  resolve: () => ({ status: 'read' }),
  plan: () => ({ status: 'read' }),
  'archive-runtime': archiveRuntime,
  'sync-base': syncBase,
  'remove-worktree': removeWorktree,
  'delete-branch': deleteBranch,
};

// plan mode: the concrete targets of each action step, derived without executing it.
// Pure reads (git ls-files, rev-parse, worktree list, the focus file); nothing is written.
const PLANNERS = {
  'archive-runtime': (ctx) => {
    const wt = findRideWorktree(ctx);
    if (!wt) return [];
    const root = archiveRoot(ctx.origin, ctx.opts.pr);
    const statePath = path.join(wt.path, STATE_REL);
    return fs.existsSync(statePath) ? [`worktree:${STATE_REL} -> ${posix(path.relative(ctx.origin, path.join(root, 'worktree', STATE_REL)))}`] : [];
  },
  'sync-base': (ctx) => {
    const plan = planSync(ctx);
    if (plan.refusal || plan.noop) return [];
    const t = plan.roadmap ? roadmapTexts(ctx, plan.head, plan.target) : null;
    return [
      `${ctx.base} ${plan.head.slice(0, 12)}..${plan.target.slice(0, 12)}`,
      ...(plan.roadmap ? [`take incoming ${ROADMAP_PATH} (archive ride entry ${t ? rideChangedRefs(mergedRefs(ctx), t).join(', ') : ''})`] : []),
    ];
  },
  'remove-worktree': (ctx) => {
    const wt = findRideWorktree(ctx);
    if (!wt) return [];
    const root = archiveRoot(ctx.origin, ctx.opts.pr);
    const { files, named } = submoduleIgnored(wt.path);
    return [
      wt.path,
      ...(ledgerTails(ctx, wt) ?? []).map((t) => `move ${t.tail.filter((b) => b === 10).length} line(s) worktree:${t.rel} -> ${t.rel}`),
      ...files.map((rel) => `archive worktree:${rel} -> ${posix(path.relative(ctx.origin, path.join(root, 'worktree-submodules', rel)))}`),
      ...named.map((n) => `remove (ignored, not archived) ${n.path}`),
      ...submoduleMembers(wt.path).members.map((m) => [m, submoduleTags(wt.path, m).length]).filter(([, n]) => n > 0)
        .map(([m, n]) => `archive ${n} tag${n === 1 ? '' : 's'} of ${m} -> ${posix(path.relative(ctx.origin, path.join(root, 'worktree-submodules', m, TAGS_DIR)))}`),
    ];
  },
  'delete-branch': (ctx) => {
    const targets = [];
    if (branchTip(ctx) && ctx.headRef !== ctx.base) targets.push(ctx.headRef);
    const p = remoteProof(ctx);
    if (!p.absent) {
      if (p.retain) targets.push(`retain origin/${ctx.headRef} (${p.retain[0]})`);
      else targets.push(`origin/${ctx.headRef} ${ctx.head.slice(0, 12)}`);
    }
    return targets;
  },
};

// D6: a retained remote branch is the owner's decision; done and noop leave nothing remaining.
function remoteBranchNote(ctx, steps) {
  const s = ctx.remoteRetained || steps.find((x) => x.id === 'delete-branch' && x.status === 'retained');
  if (!s) return [];
  const [reason, ...fact] = (s.detail ?? '').split(' ');
  return [`origin/${ctx.headRef} retained (${reason}${fact.length ? `: ${fact.join(' ')}` : ''}): owner decision, not deleted`];
}

// Every file any run of this PR archived, read from the durable manifest so an interrupted
// earlier run's archives and the runtime/ledger/STATE archives appear too.
function archivedFromManifest(ctx) {
  return readJsonl(path.join(archiveRoot(ctx.origin, ctx.opts.pr), 'manifest.jsonl'))
    .map((m) => ({ path: m.original, archive: m.archive, sha256: m.sha256, reason: m.reason }));
}

function buildReport(ctx, steps) {
  const headRev = git(ctx.origin, ['rev-parse', 'HEAD']);
  return {
    pr: ctx.opts.pr,
    mergeCommit: ctx.mc,
    base: ctx.base,
    head: headRev.status === 0 ? headRev.stdout.trim() : null,
    mergedHead: ctx.head,
    steps,
    archived: archivedFromManifest(ctx),
    moved: movedFromManifest(ctx),
    removed_unarchived: readJsonl(path.join(archiveRoot(ctx.origin, ctx.opts.pr), REMOVED_REL)).map((r) => r.path),
    retained: ctx.drafts.retained,
    noops: steps.filter((s) => s.status === 'noop').map((s) => `noop:${s.id}:${s.detail}`),
    audit: ctx.audit ?? null,
    ...(ctx.opts.direction ? { direction: ctx.opts.direction } : {}),
    ...(ctx.reportPath ? { report: ctx.reportPath } : {}),
    remaining: [
      ...ctx.drafts.retained.map((r) => `${r.path}: unexpected leftover draft; owner decision`),
      ...remoteBranchNote(ctx, steps),
    ],
  };
}

function emit(report, json) {
  if (json) { process.stdout.write(`${JSON.stringify(report)}\n`); return; }
  const lines = [`merge-cleanup PR #${report.pr}: merge ${report.mergeCommit} base ${report.base} head ${report.head}`];
  for (const s of report.steps) {
    lines.push(`  ${s.id}: ${s.status}${s.detail ? ` (${s.detail})` : ''}`);
    for (const t of s.targets ?? []) lines.push(`    -> ${t}`);
  }
  for (const a of report.archived) lines.push(`  archived ${a.path} -> ${a.archive} [${a.reason}]`);
  for (const m of report.moved ?? []) lines.push(`  moved ${m.lines} line(s) worktree:${m.ledger} -> ${m.ledger}`);
  for (const r of report.retained) lines.push(`  retained ${r.path} [${r.reason}]`);
  for (const r of report.remaining) lines.push(`  remaining: ${r}`);
  process.stdout.write(`${lines.join('\n')}\n`);
}

function runApplyOrPlan(opts) {
  const stopAfter = seam('AAI_MERGE_CLEANUP_STOP_AFTER');
  if (stopAfter && !STEP_IDS.includes(stopAfter)) usage(`AAI_MERGE_CLEANUP_STOP_AFTER names an unknown step: ${stopAfter}`);
  const origin = resolveOrigin(opts);
  const gate = readAndGate(opts, origin);
  const drafts = classifyDrafts(origin);
  const ctx = { opts, origin, ...gate, drafts };
  planChecks(ctx);
  const steps = [];
  const journal = path.join(archiveRoot(origin, opts.pr), 'journal.jsonl');
  for (const id of STEP_IDS) {
    if (opts.mode === 'plan' && !['resolve', 'plan', 'report'].includes(id)) {
      const targets = PLANNERS[id] ? PLANNERS[id](ctx) : [];
      steps.push({ id, status: 'planned', ...(targets.length ? { targets } : {}) });
      continue;
    }
    const res = id === 'report' ? (opts.mode === 'apply' ? reportStep(ctx, steps) : { status: 'read' }) : HANDLERS[id](ctx);
    steps.push({ id, status: res.status, ...(res.detail ? { detail: res.detail } : {}) });
    if (res.status === 'done') appendJsonl(journal, { step: id, status: 'done', detail: res.detail ?? '', timestamp: new Date().toISOString() });
    if (opts.mode === 'apply' && stopAfter === id) {
      process.stdout.write(`STOPPED after ${id}\n`);
      exit(4);
    }
  }
  emit(buildReport(ctx, steps), opts.json);
  exit(0);
}

// ---- D3/D4: open-PR preflight ---------------------------------------------

// A rollup entry is green when it is a completed check with SUCCESS, NEUTRAL or
// SKIPPED, or a status context in state SUCCESS. Anything else - failed,
// D7: the records the owner's direction will sign once this PR is merged - the unsigned
// contract records of the rides the ride checkout delivers (HEAD against its merge base with
// origin/<base>, the same done + links.pr predicate apply uses), read from that checkout's
// ledger. Read-only: no overlay is written here.
// Read-only gates for an OPEN pull request, in the documented order. On success
// it PRINTS the one merge command; the engine never runs it (D3).
function runPreflight(opts) {
  if (!/^[0-9a-f]{40}$/i.test(opts.expectHead ?? '')) usage('preflight requires --expect-head <40-hex sha>');
  if (opts.directedBy !== 'human' || (opts.direction ?? '').trim() === '') {
    refuse('no_direction', 'needs --directed-by human and the owner\'s verbatim --direction');
  }
  const cwd = opts.origin ?? process.cwd();
  const r = ghPrView(cwd, opts.pr, 64 * 1024 * 1024);
  if (r.error || r.status !== 0) refuse('gh_read_failed', `gh pr view ${opts.pr}`);
  let pr;
  try { pr = JSON.parse(r.stdout); } catch { refuse('gh_read_invalid', 'gh pr view printed no JSON'); }
  if (pr.state === 'MERGED') {
    process.stdout.write(`already_merged PR #${opts.pr} is merged; run: merge-cleanup.mjs apply --pr ${opts.pr} --pid <harness pid>\n`);
    exit(0);
  }
  checkRepo(cwd, pr.url);
  if (pr.state !== 'OPEN') refuse('not_open', `state=${pr.state ?? 'unknown'}`);
  if (pr.isDraft) refuse('draft', `PR #${opts.pr} is a draft`);
  const head = pr.headRefOid ?? '';
  if (head.toLowerCase() !== opts.expectHead.toLowerCase()) refuse('head_changed', `PR head ${head || 'unknown'}, expected ${opts.expectHead}`);
  // NB-1: lane-gate judges the sweep record against THIS checkout's HEAD while the
  // printed merge command binds the PR head; the two must be one commit, or a push
  // made elsewhere would be merged on the strength of a sweep that never saw it.
  const local = git(cwd, ['rev-parse', 'HEAD']);
  const localHead = local.status === 0 ? local.stdout.trim() : '';
  if (localHead.toLowerCase() !== head.toLowerCase()) {
    refuse('head_changed', `local HEAD ${localHead || 'unknown'} is not the PR head ${head}; sync this checkout to the PR head before merging`);
  }
  // The sweep is judged by the real lane-gate, in the checkout named by --origin
  // (the ride checkout the merge is being judged from), else the engine's own.
  const gateArgs = [path.join(SCRIPT_DIR, 'lane-gate.mjs'), '--sweep-check', '--pr', String(opts.pr)];
  if (opts.origin) gateArgs.push('--repo-root', opts.origin);
  const g = spawnSync(process.execPath, gateArgs, { cwd, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const gateOut = (g.stdout ?? '').trim();
  if (g.error || g.status !== 0) {
    refuse('sweep_missing', gateOut.split('\n').filter(Boolean).join(' | ') || 'lane-gate --sweep-check did not allow the merge');
  }
  // D5: the cleanup proof, surfaced before the merge; it never refuses the merge
  const wl = git(cwd, ['worktree', 'list', '--porcelain']);
  const mainWt = wl.status === 0 ? wl.stdout.match(/^worktree (.+)$/m)?.[1] : null;
  const rideWt = findRideWorktree({ origin: realOr(mainWt ?? cwd), headRef: String(pr.headRefName ?? '') });
  const cleanupVerdict = rideWt ? blockerVerdict(submoduleBlockers(rideWt.path)) : null;
  const cleanupBlockers = cleanupVerdict ? [{ reason: cleanupVerdict[0], detail: cleanupVerdict[1] }] : [];
  const command = `AAI_OPERATOR_MERGE=1 gh pr merge ${opts.pr} --squash --match-head-commit ${head}`;
  if (opts.json) {
    process.stdout.write(`${JSON.stringify({ ready: true, pr: opts.pr, head, command, sweep: gateOut, direction: opts.direction, cleanup_blockers: cleanupBlockers })}\n`);
  } else {
    process.stdout.write(`READY PR #${opts.pr} head ${head}\n${gateOut}\n${cleanupBlockers.map((b) => `cleanup blocked: ${b.reason} ${b.detail}\n`).join('')}${command}\n`);
  }
  exit(10);
}

function main(argv) {
  if (argv.includes('--help') || argv.includes('-h')) { process.stdout.write(HELP); exit(0); }
  const opts = parseArgs(argv);
  if (opts.mode === 'preflight') runPreflight(opts);
  runApplyOrPlan(opts);
}

runMain(() => main(process.argv.slice(2)));
