#!/usr/bin/env node
// merge-cleanup.mjs — deterministic engine behind `/aai-merge <PR>`
// (docs/specs/SPEC-DRAFT-spec-directed-merge-and-post-merge-cleanup.md, D1-D12).
//
//   merge-cleanup.mjs preflight --pr <n> --expect-head <sha> --directed-by human
//                               --direction "<verbatim owner words>" [--origin <abs>] [--json]
//   merge-cleanup.mjs plan  --pr <n> [--origin <abs>] [--json]
//   merge-cleanup.mjs apply --pr <n> --pid <harness pid> [--origin <abs>]
//                               [--archive-divergent <path>]... [--json]
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
// IMPLEMENTED HERE: the CLI/step skeleton, the D5 read-back gate, the D6/D7
// superseded-draft archive (batch B1), the D8 base sync and the D10 runtime
// archive, worktree removal and branch compare-and-swap delete (batch B2), the
// D9 focus clear, index regeneration, audit verdict and saved report, and the
// D11 resume contract (batch B3), and the D3/D4 open-PR preflight (batch B4a).
// Every precondition that can refuse is derived BEFORE the first write, so a
// refusal is exit 3 with nothing changed.

import fs from 'node:fs';
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
options: --origin <abs> --json --archive-divergent <path> (apply, repeatable)
exit: 0 complete, 2 usage, 3 refused, 4 stopped mid-way, 10 preflight ready
`;

const STEP_IDS = [
  'resolve', 'plan', 'archive-runtime', 'archive-drafts', 'sync-base',
  'state', 'index-audit', 'remove-worktree', 'delete-branch', 'report',
];
const PR_FIELDS = 'number,state,isDraft,headRefOid,headRefName,baseRefName,mergeStateStatus,statusCheckRollup,mergeCommit,url';
const DRAFT_BASENAME_RE = /^[A-Z]+(?:-[A-Z]+)*-DRAFT-.+\.md$/;
const BASE_NAME_RE = /^[A-Za-z0-9._/-]+$/;
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
// D8 append-only ledgers and the generated index, origin-relative.
const LEDGERS = ['docs/ai/EVENTS.jsonl', 'docs/ai/decisions.jsonl', 'docs/ai/METRICS.jsonl', 'docs/ai/tests/test-runs.jsonl'];
const INDEX_PATH = 'docs/INDEX.md';
// D10 ignored evidence directories of the ride worktree.
const RUNTIME_DIRS = ['reports', 'tdd', 'validation', 'reviews', 'evidence'].map((d) => `docs/ai/${d}`);
const STATE_REL = 'docs/ai/STATE.yaml';

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
  const out = { archiveDivergent: [], json: false };
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
    if (a === '--archive-divergent') {
      if (mode !== 'apply') usage('--archive-divergent is an apply option');
      if (i + 1 >= argv.length || argv[i + 1] === '') usage('--archive-divergent requires a path');
      out.archiveDivergent.push(argv[++i]);
      continue;
    }
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

// The ONE gh read (D4). Test seam: AAI_MERGE_CLEANUP_GH_NODE=<abs .js path> runs
// that script under this node instead of `gh`, because a native Windows runner
// cannot spawn a .cmd/.sh stub without a shell. Production leaves it unset.
function ghPrView(cwd, pr, maxBuffer) {
  const stub = process.env.AAI_MERGE_CLEANUP_GH_NODE;
  const viewArgs = ['pr', 'view', String(pr), '--json', PR_FIELDS];
  if (stub && path.isAbsolute(stub)) {
    return spawnSync(process.execPath, [stub, ...viewArgs], { cwd, encoding: 'utf8', maxBuffer });
  }
  return spawnSync('gh', viewArgs, { cwd, encoding: 'utf8', maxBuffer });
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
const posix = (p) => p.split(path.sep).join('/');

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

function deliveredIds(origin, mc) {
  const names = git(origin, ['diff', '--name-only', '--no-renames', '--diff-filter=AM', '-z', `${mc}^1`, mc]);
  const ids = new Set();
  if (names.status !== 0) return ids;
  for (const rel of names.stdout.split('\0').filter(Boolean)) {
    if (!rel.endsWith('.md')) continue;
    const blob = git(origin, ['cat-file', 'blob', `${mc}:${rel}`]);
    if (blob.status !== 0) continue;
    const id = parseFrontmatter(blob.stdout)?.id;
    if (id) ids.add(String(id));
  }
  return ids;
}

// Blob ids the PR's own commits introduced. null when the history cannot be read.
function historyBlobs(origin, ctx, prNumber) {
  const has = (oid) => git(origin, ['cat-file', '-e', `${oid}^{commit}`]).status === 0;
  if (!/^[0-9a-f]{40}$/i.test(ctx.head)) return null;
  if (!has(ctx.head)) git(origin, ['fetch', '-q', 'origin', `refs/pull/${prNumber}/head`]);
  if (!has(ctx.head)) return null;
  const range = has(`${ctx.mc}^1`) ? [ctx.head, `^${ctx.mc}^1`] : [ctx.head];
  const log = git(origin, ['log', '--format=', '--raw', '--no-abbrev', '--no-renames', '-r', ...range]);
  if (log.status !== 0) return null;
  const blobs = new Set();
  for (const line of log.stdout.split('\n')) {
    const m = line.match(/^:\d+ \d+ [0-9a-f]+ ([0-9a-f]+) [A-Z]\d*\t/);
    if (m && !/^0+$/.test(m[1])) blobs.add(m[1]);
  }
  return blobs;
}

function normalizeNamed(origin, p) {
  const abs = path.isAbsolute(p) ? p : path.join(origin, p);
  const rel = path.relative(origin, abs);
  if (rel === '' || rel.startsWith('..') || path.isAbsolute(rel)) return null;
  return posix(rel);
}

function classifyDrafts(origin, ctx, opts) {
  const ls = git(origin, ['ls-files', '--others', '--exclude-standard', '-z']);
  const candidates = (ls.status === 0 ? ls.stdout.split('\0').filter(Boolean) : [])
    .filter((rel) => rel.startsWith('docs/') && DRAFT_BASENAME_RE.test(path.posix.basename(rel)));
  const named = new Set();
  for (const p of opts.archiveDivergent ?? []) {
    const rel = normalizeNamed(origin, p);
    if (!rel) refuse('archive_divergent_not_candidate', p);
    named.add(rel);
  }
  const delivered = candidates.length ? deliveredIds(origin, ctx.mc) : new Set();
  const blobs = candidates.length ? historyBlobs(origin, ctx, opts.pr) : new Set();
  const archive = [];
  const retained = [];
  for (const rel of candidates.sort()) {
    const abs = path.join(origin, rel);
    const bytes = fs.readFileSync(abs);
    const id = parseFrontmatter(bytes.toString('utf8'))?.id ?? null;
    if (!id || !delivered.has(String(id))) { retained.push({ path: rel, reason: 'unrelated_id' }); continue; }
    if (blobs === null) { retained.push({ path: rel, reason: 'unverifiable_history' }); continue; }
    const h = git(origin, ['hash-object', '--no-filters', abs]);
    if (h.status === 0 && blobs.has(h.stdout.trim())) { archive.push({ path: rel, reason: 'superseded' }); continue; }
    if (named.has(rel)) { archive.push({ path: rel, reason: 'divergent_archived_by_decision' }); continue; }
    retained.push({ path: rel, reason: 'divergent_content' });
  }
  const candidateReasons = new Map(retained.map((r) => [r.path, r.reason]));
  for (const rel of named) {
    if (archive.some((a) => a.path === rel)) continue;
    if (candidateReasons.get(rel) !== 'divergent_content') refuse('archive_divergent_not_candidate', rel);
  }
  return { archive, retained };
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

function archiveDrafts(ctx) {
  const { origin, opts, drafts } = ctx;
  if (drafts.archive.length === 0) return { status: 'noop', detail: 'no_superseded_drafts' };
  const root = archiveRoot(origin, opts.pr);
  for (const item of drafts.archive) {
    const src = path.join(origin, item.path);
    const { rel, digest } = archiveFile(ctx, {
      src, destBase: path.join(root, 'files', item.path), original: item.path, reason: item.reason, step: 'archive-drafts',
    });
    fs.unlinkSync(src);
    ctx.archived.push({ path: item.path, archive: rel, sha256: digest, reason: item.reason });
  }
  return { status: 'done', detail: `${drafts.archive.length} archived` };
}

// ---- D8: base sync --------------------------------------------------------

const readBlob = (cwd, spec) => {
  const r = git(cwd, ['cat-file', 'blob', spec], { buffer: true });
  return r.status === 0 ? r.stdout : null;
};

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
  const plan = { head, target, ledgers: [], index: false, removeEqual: [] };
  for (const rel of dirty.sort()) {
    const isLedger = LEDGERS.includes(rel) && incoming.has(rel);
    const isIndex = rel === INDEX_PATH;
    if (!isLedger && !isIndex && !incoming.has(rel)) continue;
    if (!isLedger && !isIndex) return { refusal: ['overlap', rel] };
    if (staged.has(rel)) return { refusal: ['overlap', rel] };
    if (isIndex) { plan.index = true; continue; }
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

function syncBase(ctx) {
  const plan = planSync(ctx);
  if (plan.refusal) stop(...plan.refusal);
  if (plan.noop) return { status: 'noop', detail: 'already_at_target' };
  const { origin, opts } = ctx;
  const root = archiveRoot(origin, opts.pr);
  const saved = [];
  const restore = () => {
    for (const s of saved) fs.writeFileSync(path.join(origin, s.rel), s.bytes);
  };
  for (const rel of [...plan.ledgers, ...(plan.index ? [INDEX_PATH] : [])]) {
    const abs = path.join(origin, rel);
    const bytes = fs.readFileSync(abs);
    archiveFile(ctx, { src: abs, destBase: path.join(root, 'sync', rel), original: rel, reason: 'pre_sync_local_state', step: 'sync-base' });
    saved.push({ rel, bytes, headBlob: readBlob(origin, `${plan.head}:${rel}`), ledger: rel !== INDEX_PATH });
    fs.writeFileSync(abs, saved[saved.length - 1].headBlob);
  }
  // Untracked copies byte-equal to the incoming blob would block the fast-forward
  // and are recreated by it; keep the bytes to put back should it fail.
  const removed = plan.removeEqual.map((rel) => ({ rel, bytes: fs.readFileSync(path.join(origin, rel)) }));
  for (const r of removed) fs.unlinkSync(path.join(origin, r.rel));
  const ff = git(origin, ['merge', '--ff-only', plan.target]);
  if (ff.status !== 0) {
    restore();
    for (const r of removed) { fs.mkdirSync(path.dirname(path.join(origin, r.rel)), { recursive: true }); fs.writeFileSync(path.join(origin, r.rel), r.bytes); }
    stop('sync_failed', (ff.stderr || ff.stdout).trim().split('\n')[0] ?? '');
  }
  const headNow = git(origin, ['rev-parse', 'HEAD']).stdout.trim();
  const refNow = git(origin, ['rev-parse', `refs/heads/${ctx.base}`]).stdout.trim();
  if (headNow !== plan.target || refNow !== plan.target) stop('sync_failed', `head_ref_mismatch HEAD=${headNow} ${ctx.base}=${refNow} want=${plan.target}`);
  const tmp = path.join(root, 'sync', '.tmp');
  for (const s of saved.filter((x) => x.ledger)) {
    fs.mkdirSync(tmp, { recursive: true });
    const baseF = path.join(tmp, 'base'); const theirs = path.join(tmp, 'theirs'); const out = path.join(tmp, 'out');
    fs.writeFileSync(baseF, s.headBlob);
    fs.writeFileSync(theirs, s.bytes);
    const m = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'ledger-merge.mjs'), '--base', baseF, '--ours', path.join(origin, s.rel), '--theirs', theirs, '--out', out], { encoding: 'utf8' });
    if (m.status !== 0) stop('ledger_merge_failed', `${s.rel}: local bytes kept in ${posix(path.relative(origin, path.join(root, 'sync', s.rel)))}`);
    fs.copyFileSync(out, path.join(origin, s.rel));
  }
  fs.rmSync(tmp, { recursive: true, force: true });
  if (plan.index) {
    const g = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'generate-docs-index.mjs')], { cwd: origin, encoding: 'utf8' });
    if (g.status !== 0) stop('index_regen_failed', (g.stderr || g.stdout).trim().split('\n')[0] ?? '');
  }
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

// First eligibility failure as [reason, detail], else null.
function worktreeVerdict(ctx, wt) {
  const cwd = realOr(process.cwd());
  if (cwd === wt.path || cwd.startsWith(wt.path + path.sep)) return ['cwd_inside_target', wt.path];
  const st = git(wt.path, ['status', '--porcelain']);
  if (st.status !== 0 || st.stdout.trim() !== '') return ['worktree_dirty', wt.path];
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
  const root = archiveRoot(ctx.origin, ctx.opts.pr);
  const ls = git(wt.path, ['ls-files', '--others', '--ignored', '--exclude-standard', '-z', '--', STATE_REL, ...RUNTIME_DIRS]);
  const rels = new Set(ls.status === 0 ? ls.stdout.split('\0').filter(Boolean) : []);
  if (fs.existsSync(path.join(wt.path, STATE_REL))) rels.add(STATE_REL);
  let archived = 0; let copied = 0; let fresh = 0;
  for (const rel of [...rels].sort()) {
    const src = path.join(wt.path, rel);
    let st = null;
    try { st = fs.lstatSync(src); } catch { continue; }
    if (!st.isFile()) continue;
    const a = archiveFile(ctx, { src, destBase: path.join(root, 'worktree', rel), original: `worktree:${rel}`, reason: 'runtime_archive', step: 'archive-runtime' });
    archived++;
    if (a.fresh) fresh++;
    const dest = path.join(ctx.origin, rel);
    if (rel !== STATE_REL && !fs.existsSync(dest)) {
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.copyFileSync(src, dest);
      copied++;
    }
  }
  if (archived === 0) return { status: 'noop', detail: 'no_runtime_files' };
  if (fresh === 0 && copied === 0) return { status: 'noop', detail: 'already_archived' };
  return { status: 'done', detail: `${archived} archived, ${copied} copied to origin` };
}

function removeWorktree(ctx) {
  const wt = findRideWorktree(ctx);
  if (!wt) return { status: 'noop', detail: 'no_worktree' };
  const why = worktreeVerdict(ctx, wt);
  if (why) stop(...why);
  const lk = lockStatus(wt.path);
  if (lk.held && lk.pid === Number(ctx.opts.pid)) lockRelease({ cwd: wt.path, pid: lk.pid });
  const r = git(ctx.origin, ['worktree', 'remove', wt.path]);
  if (r.status !== 0) stop('worktree_remove_failed', (r.stderr || r.stdout).trim().split('\n')[0] ?? '');
  return { status: 'done', detail: wt.path };
}

function deleteBranch(ctx) {
  const tip = branchTip(ctx);
  if (!tip) return { status: 'noop', detail: 'no_branch' };
  const cur = git(ctx.origin, ['symbolic-ref', '-q', '--short', 'HEAD']).stdout.trim();
  if (ctx.headRef === ctx.base || ctx.headRef === cur) return { status: 'noop', detail: 'branch_is_current_or_base' };
  if (!/^[0-9a-f]{40}$/i.test(ctx.head)) stop('branch_moved', 'PR head sha unknown');
  const r = git(ctx.origin, ['update-ref', '-d', `refs/heads/${ctx.headRef}`, ctx.head]);
  if (r.status !== 0) stop('branch_moved', `${ctx.headRef} no longer at ${ctx.head}`);
  return { status: 'done', detail: ctx.headRef };
}

// Everything that can refuse, derived before the first write (exit 3).
function planChecks(ctx) {
  if (!ctx.headRef || !BASE_NAME_RE.test(ctx.headRef) || ctx.headRef.startsWith('-')) refuse('bad_head_name', JSON.stringify(ctx.headRef));
  const sync = planSync(ctx);
  if (sync.refusal) refuse(...sync.refusal);
  const wt = findRideWorktree(ctx);
  if (wt) {
    const why = worktreeVerdict(ctx, wt);
    if (why) refuse(...why);
  } else {
    const tip = branchTip(ctx);
    if (tip && tip !== ctx.head && ctx.headRef !== ctx.base) refuse('tip_mismatch', `${ctx.headRef} at ${tip}, PR head ${ctx.head}`);
  }
}

// ---- D9: focus, index, audit, report --------------------------------------

// Work-item ids this PR delivered: the frontmatter ids of the docs it added or
// changed plus the last segment of its branch name (refs are named after it).
function mergedRefs(ctx) {
  if (!ctx.refs) {
    ctx.refs = new Set(deliveredIds(ctx.origin, ctx.mc));
    const tail = ctx.headRef.split('/').pop();
    if (tail) ctx.refs.add(tail);
  }
  return ctx.refs;
}

function focusRefOf(file) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  let inFocus = false;
  for (const line of lines) {
    if (/^current_focus:\s*$/.test(line)) { inFocus = true; continue; }
    if (inFocus && /^\S/.test(line)) break;
    const m = inFocus ? line.match(/^ {2}ref_id:\s*(.*?)\s*$/) : null;
    if (m) {
      const v = m[1].replace(/\s+#.*$/, '').replace(/^(['"])(.*)\1$/, '$2');
      return v === '' || v === 'null' || v === '~' ? null : v;
    }
  }
  return null;
}

function stateStep(ctx) {
  const file = path.join(ctx.origin, STATE_REL);
  if (!fs.existsSync(file)) return { status: 'noop', detail: 'no_state' };
  const ref = focusRefOf(file);
  if (!ref || !mergedRefs(ctx).has(ref)) return { status: 'noop', detail: 'focus_not_this_ref' };
  const r = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'state.mjs'), 'clear-focus', '--ref', ref], { cwd: ctx.origin, encoding: 'utf8' });
  if (r.status !== 0) stop('state_clear_failed', (r.stderr || r.stdout).trim().split('\n')[0] ?? '');
  return { status: 'done', detail: `cleared focus ${ref}` };
}

// The generator stamps a `Generated:` line; a regeneration that differs only
// there keeps the old bytes, so a repeat run leaves the tree untouched.
const stripStamp = (buf) => buf.toString('utf8').split('\n').filter((l) => !l.startsWith('Generated: ')).join('\n');
const INDEX_FILES = [INDEX_PATH, 'docs/INDEX.audit.md', 'docs/INDEX.violations.md'];

function indexAudit(ctx) {
  const before = new Map(INDEX_FILES.map((rel) => {
    try { return [rel, fs.readFileSync(path.join(ctx.origin, rel))]; } catch { return [rel, null]; }
  }));
  const g = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'generate-docs-index.mjs')], { cwd: ctx.origin, encoding: 'utf8' });
  if (g.status !== 0) stop('index_regen_failed', (g.stderr || g.stdout).trim().split('\n')[0] ?? '');
  let changed = false;
  for (const [rel, old] of before) {
    const abs = path.join(ctx.origin, rel);
    let now = null;
    try { now = fs.readFileSync(abs); } catch { /* not produced */ }
    if (old && now && stripStamp(old) === stripStamp(now)) { fs.writeFileSync(abs, old); continue; }
    if (rel === INDEX_PATH && (old || now)) changed = true;
  }
  const a = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'docs-audit.mjs'), '--check', '--strict', '--no-event'], { cwd: ctx.origin, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const verdict = `${a.stdout ?? ''}`.match(/^.*Verdict: .*$/m);
  ctx.audit = verdict ? verdict[0].replace(/^#+\s*/, '').trim() : `Verdict: UNKNOWN (docs-audit exit ${a.status})`;
  return { status: changed ? 'done' : 'noop', detail: changed ? 'index regenerated' : 'index_current' };
}

const REPORT_DIR = 'docs/ai/reports';
const utcStamp = () => new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');

function savedReports(ctx) {
  const dir = path.join(ctx.origin, REPORT_DIR);
  const re = new RegExp(`^merge-cleanup-pr${ctx.opts.pr}-.+\\.md$`);
  try { return fs.readdirSync(dir).filter((f) => re.test(f)).sort(); } catch { return []; }
}

function renderReport(report) {
  const list = (items, fmt) => (items.length ? items.map((i) => `- ${fmt(i)}`) : ['- none']);
  return `${[
    `# merge-cleanup PR #${report.pr}`,
    '',
    `- pr: ${report.pr}`,
    `- merge commit: ${report.mergeCommit}`,
    `- base: ${report.base}`,
    `- final HEAD: ${report.head}`,
    ...(report.direction ? [`- direction: ${report.direction}`] : []),
    `- audit: ${report.audit ?? 'not run'}`,
    '',
    '## Steps',
    ...report.steps.map((s) => `- ${s.id}: ${s.status}${s.detail ? ` (${s.detail})` : ''}`),
    '',
    '## Archived',
    ...list(report.archived, (a) => `${a.path} -> ${a.archive} [${a.reason}] sha256 ${a.sha256}`),
    '',
    '## Retained',
    ...list(report.retained, (r) => `${r.path} [${r.reason}]`),
    '',
    '## No-ops',
    ...list(report.noops, (n) => n),
    '',
    '## Remaining',
    ...list(report.remaining, (r) => r),
  ].join('\n')}\n`;
}

// A repeat run that did no work keeps the report already saved; any run that
// did work (first run, resume, a new decision) saves its own.
function reportStep(ctx, steps) {
  const existing = savedReports(ctx);
  if (existing.length > 0 && !steps.some((s) => s.status === 'done')) return { status: 'noop', detail: 'report_exists' };
  const dir = path.join(ctx.origin, REPORT_DIR);
  fs.mkdirSync(dir, { recursive: true });
  let name = `merge-cleanup-pr${ctx.opts.pr}-${utcStamp()}.md`;
  for (let n = 1; fs.existsSync(path.join(dir, name)); n++) name = `merge-cleanup-pr${ctx.opts.pr}-${utcStamp()}-${n}.md`;
  const rel = `${REPORT_DIR}/${name}`;
  fs.writeFileSync(path.join(dir, name), renderReport(buildReport(ctx, [...steps, { id: 'report', status: 'done', detail: rel }])));
  ctx.reportPath = rel;
  return { status: 'done', detail: rel };
}

// ---- steps ----------------------------------------------------------------

const HANDLERS = {
  resolve: () => ({ status: 'read' }),
  plan: () => ({ status: 'read' }),
  'archive-runtime': archiveRuntime,
  'archive-drafts': archiveDrafts,
  'sync-base': syncBase,
  state: stateStep,
  'index-audit': indexAudit,
  'remove-worktree': removeWorktree,
  'delete-branch': deleteBranch,
};

// D10: remote branches are never deleted here; a surviving one is an owner action.
function remoteBranchNote(ctx) {
  if (ctx.opts.mode !== 'apply' || ctx.headRef === ctx.base) return [];
  const r = git(ctx.origin, ['ls-remote', '--heads', 'origin', `refs/heads/${ctx.headRef}`]);
  if (r.status !== 0 || r.stdout.trim() === '') return [];
  return [`origin/${ctx.headRef} still exists on the remote: delete it yourself (git push origin --delete ${ctx.headRef})`];
}

function buildReport(ctx, steps) {
  const headRev = git(ctx.origin, ['rev-parse', 'HEAD']);
  return {
    pr: ctx.opts.pr,
    mergeCommit: ctx.mc,
    base: ctx.base,
    head: headRev.status === 0 ? headRev.stdout.trim() : null,
    steps,
    archived: ctx.archived,
    retained: ctx.drafts.retained,
    noops: steps.filter((s) => s.status === 'noop').map((s) => `noop:${s.id}:${s.detail}`),
    audit: ctx.audit ?? null,
    ...(ctx.opts.direction ? { direction: ctx.opts.direction } : {}),
    ...(ctx.reportPath ? { report: ctx.reportPath } : {}),
    remaining: [
      ...(ctx.audit && !/Verdict: CLEAN/.test(ctx.audit) ? [`docs-audit ${ctx.audit}: owner action, not auto-remediated`] : []),
      ...ctx.drafts.retained
        .filter((r) => r.reason === 'divergent_content' || r.reason === 'unverifiable_history')
        .map((r) => `${r.path} (${r.reason}): owner decision; archive with --archive-divergent`),
      ...remoteBranchNote(ctx),
    ],
  };
}

function emit(report, json) {
  if (json) { process.stdout.write(`${JSON.stringify(report)}\n`); return; }
  const lines = [`merge-cleanup PR #${report.pr}: merge ${report.mergeCommit} base ${report.base} head ${report.head}`];
  for (const s of report.steps) lines.push(`  ${s.id}: ${s.status}${s.detail ? ` (${s.detail})` : ''}`);
  for (const a of report.archived) lines.push(`  archived ${a.path} -> ${a.archive} [${a.reason}]`);
  for (const r of report.retained) lines.push(`  retained ${r.path} [${r.reason}]`);
  for (const r of report.remaining) lines.push(`  remaining: ${r}`);
  process.stdout.write(`${lines.join('\n')}\n`);
}

function runApplyOrPlan(opts) {
  const stopAfter = process.env.AAI_MERGE_CLEANUP_STOP_AFTER;
  if (stopAfter && !STEP_IDS.includes(stopAfter)) usage(`AAI_MERGE_CLEANUP_STOP_AFTER names an unknown step: ${stopAfter}`);
  const origin = resolveOrigin(opts);
  const gate = readAndGate(opts, origin);
  const drafts = classifyDrafts(origin, gate, opts);
  const ctx = { opts, origin, ...gate, drafts, archived: [] };
  planChecks(ctx);
  const steps = [];
  const journal = path.join(archiveRoot(origin, opts.pr), 'journal.jsonl');
  for (const id of STEP_IDS) {
    if (opts.mode === 'plan' && !['resolve', 'plan', 'report'].includes(id)) {
      steps.push({ id, status: 'planned' });
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
// cancelled, still running or pending - is not.
function rollupGreen(e) {
  if (e && typeof e.status === 'string' && e.status !== '') {
    return e.status === 'COMPLETED' && ['SUCCESS', 'NEUTRAL', 'SKIPPED'].includes(e.conclusion);
  }
  if (e && typeof e.state === 'string') return e.state === 'SUCCESS';
  return false;
}

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
  if (pr.state !== 'OPEN') refuse('not_open', `state=${pr.state ?? 'unknown'}`);
  if (pr.isDraft) refuse('draft', `PR #${opts.pr} is a draft`);
  const head = pr.headRefOid ?? '';
  if (head.toLowerCase() !== opts.expectHead.toLowerCase()) refuse('head_changed', `PR head ${head || 'unknown'}, expected ${opts.expectHead}`);
  const rollup = Array.isArray(pr.statusCheckRollup) ? pr.statusCheckRollup : [];
  const bad = rollup.filter((e) => !rollupGreen(e));
  if (bad.length > 0) refuse('checks_failing', bad.map((e) => `${e.name ?? e.context ?? 'check'}=${e.conclusion || e.state || e.status || 'unknown'}`).join(','));
  if (pr.mergeStateStatus !== 'CLEAN') refuse('not_mergeable', `mergeStateStatus=${pr.mergeStateStatus ?? 'unknown'}`);
  // The sweep is judged by the real lane-gate, in the checkout named by --origin
  // (the ride checkout the merge is being judged from), else the engine's own.
  const gateArgs = [path.join(SCRIPT_DIR, 'lane-gate.mjs'), '--sweep-check', '--pr', String(opts.pr)];
  if (opts.origin) gateArgs.push('--repo-root', opts.origin);
  const g = spawnSync(process.execPath, gateArgs, { cwd, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const gateOut = (g.stdout ?? '').trim();
  if (g.error || g.status !== 0) {
    refuse('sweep_missing', gateOut.split('\n').filter(Boolean).join(' | ') || 'lane-gate --sweep-check did not allow the merge');
  }
  const command = `AAI_OPERATOR_MERGE=1 gh pr merge ${opts.pr} --squash --match-head-commit ${head}`;
  if (opts.json) {
    process.stdout.write(`${JSON.stringify({ ready: true, pr: opts.pr, head, command, sweep: gateOut, direction: opts.direction })}\n`);
  } else {
    process.stdout.write(`READY PR #${opts.pr} head ${head}\n${gateOut}\n${command}\n`);
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
