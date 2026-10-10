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
// IMPLEMENTED HERE (batch B1): the CLI/step skeleton, the D5 read-back gate and
// the D6/D7 superseded-draft archive. The remaining steps are registered with
// a null handler and reported as `not_implemented` until their batch lands.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
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

function usage(msg) {
  process.stderr.write(`merge-cleanup: ${msg}\n${HELP}`);
  exit(2);
}

function refuse(reason, detail = '') {
  process.stdout.write(`REFUSE ${reason}${detail ? ` ${detail}` : ''}\n`);
  exit(3);
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
  const r = spawnSync('gh', ['pr', 'view', String(opts.pr), '--json', PR_FIELDS], {
    cwd: origin, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
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

function archiveDrafts(ctx) {
  const { origin, opts, drafts } = ctx;
  if (drafts.archive.length === 0) return { status: 'noop', detail: 'no_superseded_drafts' };
  const root = archiveRoot(origin, opts.pr);
  const manifest = path.join(root, 'manifest.jsonl');
  for (const item of drafts.archive) {
    const src = path.join(origin, item.path);
    const bytes = fs.readFileSync(src);
    const digest = sha256(bytes);
    let dest = path.join(root, 'files', item.path);
    for (let n = 1; fs.existsSync(dest) && !fs.readFileSync(dest).equals(bytes); n++) {
      dest = `${path.join(root, 'files', item.path)}.${n}`;
    }
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    if (!fs.existsSync(dest)) fs.copyFileSync(src, dest);
    if (!fs.readFileSync(dest).equals(bytes)) throw new Error(`archive copy differs from source: ${item.path}`);
    const rel = posix(path.relative(origin, dest));
    const known = readJsonl(manifest).some((m) => m.original === item.path && m.sha256 === digest);
    if (!known) {
      appendJsonl(manifest, {
        original: item.path, archive: rel, sha256: digest, reason: item.reason,
        step: 'archive-drafts', timestamp: new Date().toISOString(),
      });
    }
    fs.unlinkSync(src);
    ctx.archived.push({ path: item.path, archive: rel, sha256: digest, reason: item.reason });
  }
  return { status: 'done', detail: `${drafts.archive.length} archived` };
}

// ---- steps ----------------------------------------------------------------

const HANDLERS = {
  resolve: () => ({ status: 'read' }),
  plan: () => ({ status: 'read' }),
  'archive-drafts': archiveDrafts,
  report: () => ({ status: 'read' }),
};

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
    remaining: ctx.drafts.retained
      .filter((r) => r.reason === 'divergent_content' || r.reason === 'unverifiable_history')
      .map((r) => `${r.path} (${r.reason}): owner decision; archive with --archive-divergent`),
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
  const steps = [];
  const journal = path.join(archiveRoot(origin, opts.pr), 'journal.jsonl');
  for (const id of STEP_IDS) {
    if (opts.mode === 'plan' && !['resolve', 'plan', 'report'].includes(id)) {
      steps.push({ id, status: 'planned' });
      continue;
    }
    const handler = HANDLERS[id];
    const res = handler ? handler(ctx) : { status: 'not_implemented' };
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

function main(argv) {
  if (argv.includes('--help') || argv.includes('-h')) { process.stdout.write(HELP); exit(0); }
  const opts = parseArgs(argv);
  if (opts.mode === 'preflight') usage('preflight is not implemented in this build');
  runApplyOrPlan(opts);
}

runMain(() => main(process.argv.slice(2)));
