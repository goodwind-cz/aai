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
//   0  every step done, a named no-op or kept (a protected object is left as it is)
//   2  usage error
//   3  refused before any write to the working tree, refs or index: `REFUSE <reason> <detail>`
//   4  a step stopped mid-way (a re-run resumes): `STOPPED <reason> <detail>`
//   6  the run reached the end and at least one `decide` item waits (apply --decide <id>=<option>)
//   10 preflight ready (open PR, every gate passed)
// Every classified item also prints `OUTCOME <json>` (lib/merge-outcomes.mjs holds the table).
//
// The engine NEVER runs `gh pr merge` (D3). It performs ONE fixed gh read (D4)
// and `git fetch`; every other effect is a local, archive-first file or git
// operation. Node stdlib only (docs/TECHNOLOGY.md).
//
// Test seams (AAI_MERGE_CLEANUP_GH_NODE, _STOP_AFTER, _CRASH_AT) are honoured
// ONLY when AAI_MERGE_CLEANUP_TEST_SEAMS=1 is also set; in production they are
// inert, so a stray variable can neither replace gh nor stop a run.
//
// Steps: superseded-draft archive, runtime archive, base sync, reconcile-origin, ride worktree removal, branch
// delete (the origin branch only by a lease against the merged head), report. Each archives before it removes and
// journals its completion, so a re-run resumes. A protected object (dirty worktree, diverged main, moved branch,
// live lock) is kept as it is, its step is recorded retained and the other steps run; only a gate reason or a
// failed read refuses (exit 3). The ride's own roadmap entry and appended ledger lines are carried to the main checkout.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { status as lockStatus, release as lockRelease } from './lib/session-lock.mjs';
import { parseFrontmatter } from './lib/docs-model.mjs';
import { createAdapter, resolvePlatform, githubRepoSlug } from './lib/platform-adapter.mjs';
import {
  classify, outcomeLine, nextAttempt, choiceFor, parseDecide, compareDraft, representedChanges, summaryLines, keptLine,
  GENERATED_PROJECTIONS,
} from './lib/merge-outcomes.mjs';

const HELP = `merge-cleanup.mjs <preflight|plan|apply> --pr <n> [options]
  preflight  read-only gates for an OPEN pull request; exit 10 when ready
  plan       read-only plan for a MERGED pull request
  apply      cleanup after a MERGED pull request (needs --pid)
options: --origin <abs> --json
         --direction "<owner's words>"
         --decide <id>=<option>[,<id>=<option>...]   (apply only: answers the OUTCOME lines of a decide item)
         --origin defaults to the main checkout (the first git worktree), in every mode;
         pass it to read and write a ride worktree's ledger instead
the ride's own leftovers (apply): a roadmap change the incoming roadmap represents is archived and the incoming one
         taken; whole lines appended to the ride worktree's ledgers are moved to the main checkout (archived first)
exit: 0 complete or kept, 2 usage, 3 refused, 4 stopped mid-way, 6 decision pending, 10 preflight ready
`;

const STEP_IDS = [
  'resolve', 'plan', 'archive-drafts', 'archive-runtime', 'sync-base', 'reconcile-origin',
  'remove-worktree', 'delete-branch', 'report',
];
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

const EXIT_DECISION_PENDING = 6;
const RUN = { opts: null, origin: null, pr: 0, mc: null, step: null, outcomes: [], kept: [], decisions: [], pairs: [], retries: new Set(), fp: null, reset: false };
// Run state: classified items, kept lines, decisions given or recorded. Keep: a kept reason inside a step.
class Keep extends Error {
  constructor(reason, detail) { super(reason); this.reason = reason; this.detail = detail; }
}
const notDone = (ctx, id) => ctx.status[id] === 'retained';

// <git common dir>/aai-merge-cleanup/pr-<n>/attempts.jsonl (apply only): an exit-3 run changes no working-tree file.
const attemptsFile = () => {
  const r = RUN.origin && RUN.opts?.mode === 'apply' ? git(RUN.origin, ['rev-parse', '--git-common-dir']) : null;
  return r?.status === 0 ? path.join(path.resolve(RUN.origin, r.stdout.trim()), 'aai-merge-cleanup', `pr-${RUN.opts.pr}`, 'attempts.jsonl') : null;
};
const choicesFile = () => path.join(archiveRoot(RUN.origin, RUN.opts.pr), 'choices.jsonl');

// The sha256 of what progress changes: origin HEAD, the journal done lines, the manifest size and the item.
function fingerprint(key) {
  if (!RUN.origin || RUN.opts?.mode !== 'apply') return '';
  const root = archiveRoot(RUN.origin, RUN.opts.pr);
  const done = readJsonl(path.join(root, 'journal.jsonl')).filter((r) => r.status === 'done').map(({ timestamp, ...r }) => JSON.stringify(r));
  const head = git(RUN.origin, ['rev-parse', 'HEAD']).stdout.trim();
  return sha256([head, ...done, String(readJsonl(path.join(root, 'manifest.jsonl')).length), key].join('\n'));
}

// Classify one item through the table, apply a decision that names it, register the outcome.
// Returns { o, option } - option is the decision applied now, else null.
function raise(reason, subject, detail, { phase = 'step', evidence = [] } = {}) {
  const fp = fingerprint(`${reason}:${subject}`);
  const af = attemptsFile();
  const att = af ? nextAttempt(readJsonl(af), fp) : { retry: false };  // no attempts record (preflight, plan): a retry reason goes straight to its fallback class
  const ev = evidence.length ? evidence : [fp];
  let o = classify(reason, { phase, subject, detail, evidence: ev, retry: att.retry });
  // an answer that names this id was given for the fallback menu the previous run showed
  if (o.state === 'retry' && RUN.decisions.some((d) => d.id === o.id)) o = classify(reason, { phase, subject, detail, evidence: ev, retry: false });
  const ch = o.class === 'decide' ? choiceFor(o, RUN.decisions) : null;
  if (ch) {
    const file = choicesFile();
    const known = readJsonl(file);
    const rec = { id: ch.id, option: ch.option, reason, subject, timestamp: new Date().toISOString() };
    if (!known.some((c) => c.id === rec.id && c.option === rec.option)) appendJsonl(file, rec);
    crashAt('choice-after-record');
    if (ch.pair) RUN.pairs.find((x) => x.pair === ch.pair).used = true;
    o = { ...o, state: 'resolved' };
    if (ch.option === 'retry') { RUN.reset = true; o = { ...o, state: 'retry' }; }
  }
  if (!RUN.outcomes.some((x) => x.id === o.id)) RUN.outcomes.push(o);
  if (o.state === 'retry') RUN.retries.add(o.id);
  RUN.fp = fp;
  return { o, option: ch?.option ?? null };
}

const keptItem = (o, step) => { const line = keptLine(o, step); if (!RUN.kept.includes(line)) RUN.kept.push(line); };

// The ends of a run print the plain lines; apply also appends one attempts record (D7).
function endRun(code, kind, step = RUN.step) {
  const pending = RUN.outcomes.filter((o) => o.class === 'decide' && o.state === 'pending');
  const needs = RUN.outcomes.filter((o) => o.class === 'external');
  const { lines, summary } = summaryLines({ pr: RUN.pr, mc: RUN.mc, kind, kept: RUN.kept, pending, needs, step, noCleanup: RUN.opts?.mode === 'preflight' });
  const ignored = RUN.pairs.filter((x) => !x.used).map((x) => `IGNORED ${x.pair} ${RUN.outcomes.some((o) => o.id === x.id) ? 'option_not_offered' : 'no_longer_applies'}`);
  const af = attemptsFile();
  if (af) {
    fs.mkdirSync(path.dirname(af), { recursive: true });
    appendJsonl(af, { exit: code, retries: [...RUN.retries], fingerprint: RUN.fp ?? fingerprint(''), ...(RUN.reset ? { reset: true } : {}), timestamp: new Date().toISOString() });
  }
  return { lines, summary, ignored, pending };
}

// Printed by a run that ends without a report (REFUSE or STOPPED, or a plan).
function finish(code, kind, step) {
  const e = endRun(code, kind, step);
  process.stdout.write(`${[...e.ignored, ...RUN.outcomes.map(outcomeLine), ...e.lines].join('\n')}\n`);
  exit(code);
}

// A reason the engine cannot go on with. kept (or a skip_step decision): the step is retained and the run goes on.
// Otherwise REFUSE (exit 3, nothing written yet) or STOPPED (exit 4, a re-run resumes).
function halt(reason, detail, { refused = false, subject = detail, phase = refused ? 'plan' : RUN.step ? 'step' : 'plan', evidence = [] } = {}) {
  const { o, option } = raise(reason, subject, detail, { phase, evidence });
  if ((o.class === 'auto' && o.state === 'resolved') || option === 'skip_step') {
    keptItem(o, RUN.step);
    throw new Keep(reason, detail);
  }
  process.stdout.write(`${refused ? 'REFUSE' : 'STOPPED'} ${reason}${detail ? ` ${detail}` : ''}\n`);
  finish(refused ? 3 : 4, refused ? 'refused' : o.state === 'retry' ? 'interrupted_retry' : 'interrupted_decision');
}

const refuse = (reason, detail = '', opt = {}) => halt(reason, detail, { ...opt, refused: true });
// A step that cannot finish after earlier steps already wrote: exit 4, a re-run resumes.
const stop = (reason, detail = '', opt = {}) => halt(reason, detail, opt);
// A protected object: the named step is retained (the Keep reaches the step loop).
const keepStep = (ctx, step, reason, detail = '') => { RUN.step = step; return halt(reason, detail, { phase: 'plan' }); };

function parseArgs(argv) {
  const out = { json: false };
  const mode = argv[0];
  if (!['preflight', 'plan', 'apply'].includes(mode)) usage(`unknown or missing mode: ${mode ?? '(none)'}`);
  out.mode = mode;
  const valueFlags = {
    '--pr': 'pr', '--origin': 'origin', '--pid': 'pid', '--expect-head': 'expectHead',
    '--directed-by': 'directedBy', '--direction': 'direction', '--decide': 'decide',
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
  if (out.decide !== undefined && (mode !== 'apply' || !parseDecide(out.decide))) usage('--decide takes <id>=<option>[,...] and only apply');
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

// D11: every host read goes through the platform adapter (lib/platform-adapter.mjs). The one
// test seam, AAI_MERGE_CLEANUP_GH_NODE=<abs .js path>, runs that script under this node instead of
// the GitHub CLI, because a native Windows runner cannot spawn a .cmd/.sh stub without a shell.
// Inert without the test guard, and never applied to another platform's adapter.
function seamRunner() {
  const stub = seam('AAI_MERGE_CLEANUP_GH_NODE');
  if (!stub || !path.isAbsolute(stub)) return undefined;
  return (_cmd, args, o) => spawnSync(process.execPath, [stub, ...args], o);
}

// D11: platform resolution runs first in every mode, before any platform read or write.
function openPlatform(cwd) {
  const top = git(cwd, ['rev-parse', '--show-toplevel']);
  const res = resolvePlatform({ repoRoot: top.status === 0 && top.stdout.trim() ? top.stdout.trim() : cwd });
  if (res.mismatch) {
    refuse('platform_mismatch', `recorded=${res.recorded} detected=${res.detected} re-record: node .aai/scripts/platform.mjs record --force`);
  }
  if (res.legacy) {
    process.stderr.write('merge-cleanup: platform not recorded; assuming github (record it: node .aai/scripts/platform.mjs record)\n');
  }
  return createAdapter(res.platform, { cwd, runner: res.platform === 'github' ? seamRunner() : undefined });
}

// An adapter read becomes its value, a named generic skip, or the platform's refusal reason.
function unwrap(adapter, r) {
  if (r.skip) refuse('platform_generic', `${r.op} manual: ${r.manual}`);
  if (!r.ok) refuse(adapter.refusalReason(r), r.detail);
  return r.value;
}

function checkReviewThreads(adapter, prNumber, pr) {
  const t = unwrap(adapter, adapter.reviewThreads(prNumber, pr));
  return { ok: t.unresolvedCount === 0, unresolvedCount: t.unresolvedCount, details: t.details };
}

// PR numbers from one dependents query, or null when it failed (the proof then retains the branch).
function dependentNumbers(r) {
  return r.ok ? r.value : null;
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
const posix = (p) => p.split(path.sep).join('/');

const repoSlug = githubRepoSlug;

// NB-4: the PR must belong to the repository the origin remote points at (the adapter compares
// only a recognisable remote; a local path or an unparsable URL is skipped).
function checkRepo(adapter, origin, pr) {
  const r = git(origin, ['config', '--get', 'remote.origin.url']);
  unwrap(adapter, adapter.repoMatches(r.status === 0 ? r.stdout.trim() : '', pr));
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
  RUN.origin = fs.realpathSync(top.stdout.trim());
  return RUN.origin;
}

// D4/D5: the one fixed PR read, then the read-back gate.
function readAndGate(opts, origin) {
  const adapter = openPlatform(origin);
  const pr = unwrap(adapter, adapter.prView(opts.pr));
  checkRepo(adapter, origin, pr);
  const mc = pr?.mergeCommit?.oid ?? '';
  if (pr.state !== 'MERGED' || !/^[0-9a-f]{40}$/i.test(mc)) {
    refuse('not_merged', `state=${pr.state ?? 'unknown'} mergeCommit=${mc || 'none'}`);
  }
  RUN.mc = mc;
  const base = pr.baseRefName ?? '';
  if (!BASE_NAME_RE.test(base) || base.startsWith('-')) refuse('bad_base_name', JSON.stringify(base));
  const f = git(origin, ['fetch', '-q', 'origin', `+refs/heads/${base}:refs/remotes/origin/${base}`]);
  if (f.status !== 0) refuse('fetch_failed', `origin ${base}`);
  const anc = git(origin, ['merge-base', '--is-ancestor', mc, `refs/remotes/origin/${base}`]);
  if (anc.status !== 0) refuse('merge_commit_not_on_base', `${mc} is not reachable from origin/${base}`);
  return { pr, mc, base, head: pr.headRefOid ?? '', headRef: pr.headRefName ?? '', adapter };
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

// Intake docs (any type but spec) the range from..to added or changed, status done at `to`. Returns
// [{ id, rel, proof }]: links_pr (links.pr names `pr`), merge_commit (links.pr absent or empty and the doc was not
// done at `from`), or null (no proof ties it to `pr`).
function doneDocsBetween(cwd, from, to, pr, repo) {
  const names = git(cwd, ['diff', '--name-only', '--no-renames', '--diff-filter=AM', '-z', from, to]);
  const docs = [];
  if (names.status !== 0) return docs;
  for (const rel of names.stdout.split('\0').filter(Boolean)) {
    if (!rel.endsWith('.md')) continue;
    const blob = git(cwd, ['cat-file', 'blob', `${to}:${rel}`]);
    if (blob.status !== 0) continue;
    const fm = parseFrontmatter(blob.stdout);
    if (!fm?.id || fm.type === 'spec' || fm.status !== 'done') continue;
    const v = fm.links?.pr;
    const raw = (Array.isArray(v) ? v : [v]).filter((x) => x !== undefined && x !== null && String(x).trim() !== '' && String(x).trim() !== '~');
    const was = git(cwd, ['cat-file', 'blob', `${from}:${rel}`]);
    const before = was.status === 0 ? parseFrontmatter(was.stdout)?.status : null;
    if (linkedPrs(fm, repo).includes(pr)) docs.push({ id: String(fm.id), rel, proof: 'links_pr' });
    else if (raw.length === 0 && before !== 'done') docs.push({ id: String(fm.id), rel, proof: 'merge_commit' });
    else docs.push({ id: String(fm.id), rel, proof: null });
  }
  return docs;
}

// D3: each untracked draft against the numbered doc of the same type and slug in the incoming tree.
// superseded: equal after the lifecycle keys are removed; divergent: not equal; untouched: no single counterpart or another item.
function classifyDrafts(origin, base) {
  const ls = git(origin, ['ls-files', '--others', '--exclude-standard', '-z']);
  const out = { superseded: [], divergent: [], untouched: [], retained: [] };
  const ref = `refs/remotes/origin/${base}`;
  for (const rel of (ls.status === 0 ? ls.stdout.split('\0').filter(Boolean) : []).filter((r) => r.startsWith('docs/') && DRAFT_BASENAME_RE.test(path.posix.basename(r)))) {
    const m = path.posix.basename(rel).match(/^([A-Z]+(?:-[A-Z]+)*)-DRAFT-(.+)\.md$/);
    const dir = path.posix.dirname(rel);
    const names = git(origin, ['ls-tree', '--name-only', '-z', ref, `${dir}/`]);
    const re = new RegExp(`^${m[1]}-\\d+-${m[2].replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\.md$`);
    const hits = (names.status === 0 ? names.stdout.split('\0').filter(Boolean) : []).filter((n) => re.test(path.posix.basename(n)));
    const blob = hits.length === 1 ? readBlob(origin, `${ref}:${hits[0]}`) : null;
    const verdict = blob ? compareDraft(fs.readFileSync(path.join(origin, rel), 'utf8'), blob.toString('utf8'), `${m[1]}-DRAFT-${m[2]}`, path.posix.basename(hits[0], '.md')) : false;
    if (verdict) out[verdict === 'superseded' ? 'superseded' : 'divergent'].push({ path: rel, counterpart: hits[0], oid: git(origin, ['rev-parse', `${ref}:${hits[0]}`]).stdout.trim() });
    else out.untouched.push(rel);
  }
  return out;
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
  try {
    if (seam('AAI_MERGE_CLEANUP_FAIL_ARCHIVE') === original) throw new Error('archive failed (test seam)');
    const bytes = fs.readFileSync(src);
    const digest = sha256(bytes);
    let dest = destBase;
    for (let n = 1; fs.existsSync(dest) && !fs.readFileSync(dest).equals(bytes); n++) dest = `${destBase}.${n}`;
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const created = !fs.existsSync(dest);
    if (created) fs.copyFileSync(src, dest);
    if (created && seam('AAI_MERGE_CLEANUP_CORRUPT_ARCHIVE') === original) fs.appendFileSync(dest, 'corrupted (test seam)\n');
    if (!fs.readFileSync(dest).equals(bytes)) throw new Error(`archive copy differs from source: ${original}`);
    const rel = posix(path.relative(ctx.origin, dest));
    const manifest = path.join(archiveRoot(ctx.origin, ctx.opts.pr), 'manifest.jsonl');
    const known = readJsonl(manifest).some((m) => m.original === original && m.sha256 === digest);
    if (!known) {
      appendJsonl(manifest, { original, archive: rel, sha256: digest, reason, step, timestamp: new Date().toISOString() });
    }
    return { rel, digest, fresh: created || !known };
  } catch { stop('archive_failed', original); }
}

// ---- D8: base sync --------------------------------------------------------

const readBlob = (cwd, spec) => {
  const r = git(cwd, ['cat-file', 'blob', spec], { buffer: true });
  return r.status === 0 ? r.stdout : null;
};

// The roadmap as three latin1 strings: the main checkout's file, the HEAD blob, the incoming blob.
function roadmapTexts(ctx, head, target) {
  let local;
  try { local = fs.readFileSync(path.join(ctx.origin, ROADMAP_PATH), 'latin1'); } catch { return null; }
  const headBlob = readBlob(ctx.origin, `${head}:${ROADMAP_PATH}`);
  const inBlob = readBlob(ctx.origin, `${target}:${ROADMAP_PATH}`);
  if (!headBlob || !inBlob) return null;
  return { local, head: headBlob.toString('latin1'), incoming: inBlob.toString('latin1') };
}

// D4: the local roadmap change against the HEAD blob, compared entry by entry with the incoming roadmap
// (lib/merge-outcomes.mjs representedChanges). { represented, unrepresented } or null when a text is unreadable.
function roadmapRepresented(ctx, head, target) {
  const t = roadmapTexts(ctx, head, target);
  return t ? representedChanges({ ...t, refs: mergedRefs(ctx), unproven: unprovenRefs(ctx) }) : null;
}

// The protection check: main checked out on the base, HEAD an ancestor of the fetched base (run before anything writes).
function syncGate({ origin, base }) {
  const target = git(origin, ['rev-parse', '--verify', '-q', `refs/remotes/origin/${base}`]).stdout.trim();
  const cur = git(origin, ['symbolic-ref', '-q', '--short', 'HEAD']);
  const branch = cur.status === 0 ? cur.stdout.trim() : '';
  if (branch !== base) return { refusal: ['origin_not_on_base', branch || 'detached_head'] };
  const head = git(origin, ['rev-parse', '--verify', 'HEAD']).stdout.trim();
  if (head !== target && git(origin, ['merge-base', '--is-ancestor', head, target]).status !== 0) return { refusal: ['base_diverged', base] };
  return { head, target };
}

// Reads and decisions only, no writes. Returns { refusal: [reason, detail] } (a kept reason), { held: {...} } (a
// decide item: pending or answered keep_local) or a plan. An answered take_incoming joins the plan.
function planSync(ctx) {
  const { origin } = ctx;
  const gate = syncGate(ctx);
  if (gate.refusal || gate.head === gate.target) return gate.refusal ? gate : { noop: true, ...gate };
  const { head, target } = gate;
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
  const plan = { head, target, ledgers: [], index: false, replace: [], removeEqual: [], taken: false };
  const read = (rel) => { try { return fs.readFileSync(path.join(origin, rel)); } catch { return null; } };
  // a decide item: answered take_incoming joins the plan, anything else holds the step
  const clash = (reason, rel, detail, bytes) => {
    const { o, option } = raise(reason, rel, detail, { phase: 'plan', evidence: bytes });
    return option === 'take_incoming' ? null : { held: { reason, detail: rel, o, option } };
  };
  for (const rel of dirty.sort()) {
    const isLedger = LEDGERS.includes(rel) && incoming.has(rel);
    const isIndex = rel === INDEX_PATH;
    const isRoadmap = rel === ROADMAP_PATH;
    if (!isLedger && !isIndex && !incoming.has(rel)) continue;
    const evidence = [read(rel) ?? '', readBlob(origin, `${head}:${rel}`) ?? '', readBlob(origin, `${target}:${rel}`) ?? ''];
    if (staged.has(rel)) return { refusal: ['overlap_staged', rel] };
    if (isIndex) { plan.index = true; plan.replace.push(rel); continue; }
    if (GENERATED_PROJECTIONS.includes(rel)) { plan.replace.push(rel); continue; }
    if (isRoadmap) {
      const rr = roadmapRepresented(ctx, head, target);
      if (rr?.represented) { plan.replace.push(rel); continue; }
      const held = clash('overlap', rel, (rr?.unrepresented ?? ['unreadable']).join(', '), evidence);
      if (held) return held;
      plan.replace.push(rel); plan.taken = true;
      continue;
    }
    if (!isLedger) {
      const held = clash('overlap', rel, 'changed locally and by the merge', evidence);
      if (held) return held;
      plan.replace.push(rel); plan.taken = true;
      continue;
    }
    const headBlob = readBlob(origin, `${head}:${rel}`);
    const inBlob = readBlob(origin, `${target}:${rel}`);
    const local = read(rel);
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
    if (st.isFile() && inBlob && fs.readFileSync(abs).equals(inBlob)) { plan.removeEqual.push({ rel, archive: false }); continue; }
    if (!st.isFile()) return { refusal: ['untracked_not_file', rel] };
    const held = clash('untracked_collision', rel, 'differs from the incoming file', [fs.readFileSync(abs), inBlob ?? '']);
    if (held) return held;
    plan.removeEqual.push({ rel, archive: true }); plan.taken = true;
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
  const gate = syncGate(ctx); if (gate.refusal) halt(...gate.refusal, { phase: 'plan' });
  const resumed = pendingJournals(ctx).map((f) => resumeSync(ctx, f)).pop() ?? null;
  const plan = planSync(ctx);
  if (plan.refusal) halt(...plan.refusal, { phase: 'plan' });
  if (plan.held) {
    if (plan.held.option === 'keep_local') keptItem(plan.held.o, 'sync-base');
    throw new Keep(plan.held.reason, plan.held.detail);
  }
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
      if (s.bytes === null) { fs.rmSync(abs, { force: true }); continue; }
      let cur = null;
      try { cur = fs.readFileSync(abs); } catch { /* removed */ }
      const next = s.ledger ? putBack(s.bytes, s.headBlob, cur) : s.bytes;
      if (next) fs.writeFileSync(abs, next); else stuck.push(s.rel);
    }
    return stuck;
  };
  const pendingEntries = [];
  for (const rel of [...plan.ledgers, ...plan.replace]) {
    const abs = path.join(origin, rel);
    let bytes = null; try { bytes = fs.readFileSync(abs); } catch { /* deleted locally: nothing to archive, the rewrite below recreates it */ }
    if (bytes) {
      const a = archiveFile(ctx, { src: abs, destBase: path.join(root, 'sync', rel), original: rel, reason: 'pre_sync_local_state', step: 'sync-base' });
      pendingEntries.push({ rel, archive: a.rel, ledger: LEDGERS.includes(rel) });
    }
    saved.push({ rel, bytes, headBlob: readBlob(origin, `${plan.head}:${rel}`), ledger: LEDGERS.includes(rel) });
  }
  if (plan.taken && plan.replace.length > 0) crashAt('take-incoming-after-archive');
  if (pendingEntries.length > 0) {
    fs.mkdirSync(path.dirname(pendingPath(ctx)), { recursive: true });
    fs.writeFileSync(pendingPath(ctx), `${JSON.stringify({ head: plan.head, entries: pendingEntries })}\n`);
  }
  for (const s of saved) { fs.mkdirSync(path.dirname(path.join(origin, s.rel)), { recursive: true }); fs.writeFileSync(path.join(origin, s.rel), s.headBlob); }
  crashAt('sync-after-rewrite');
  // Untracked copies byte-equal to the incoming blob would block the fast-forward
  // and are recreated by it; keep the bytes to put back should it fail.
  const removed = plan.removeEqual.map(({ rel, archive }) => {
    const abs = path.join(origin, rel);
    if (archive) archiveFile(ctx, { src: abs, destBase: path.join(root, 'sync', rel), original: rel, reason: 'pre_sync_local_state', step: 'sync-base' });
    return { rel, bytes: fs.readFileSync(abs) };
  });
  if (plan.taken) crashAt('take-incoming-after-archive');
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

// spec-ride-state-handoff-to-worktree D8: after the merged ledger is here, clear the merged ride's stale traces
// from the origin STATE through ride-handoff.mjs reconcile. A refusal is the owner's decision, never a stop.
function reconcileRefs(ctx, extra) {
  const statePath = path.join(ctx.origin, STATE_REL);
  const script = path.join(SCRIPT_DIR, 'ride-handoff.mjs');
  const metrics = path.join(ctx.origin, 'docs', 'ai', 'METRICS.jsonl');
  return [...mergedRefs(ctx)].sort().map((ref) => {
    const r = spawnSync(process.execPath, [script, 'reconcile', '--ref', ref, '--state', statePath, '--metrics', metrics, '--branch', ctx.headRef, ...extra],
      { cwd: ctx.origin, encoding: 'utf8' });
    const line = (r.stdout ?? '').split('\n').find((l) => /^(RECONCILED|NOOP|REFUSE) /.test(l)) ?? '';
    return { ref, kind: line.split(' ')[0] || 'ERROR', line: line || (r.stderr ?? '').trim().split('\n')[0] || `exit ${r.status}` };
  });
}

function reconcileOrigin(ctx) {
  if (!fs.existsSync(path.join(ctx.origin, STATE_REL))) return { status: 'noop', detail: 'no_state' };
  if (notDone(ctx, 'sync-base')) return keepStep(ctx, 'reconcile-origin', 'sync_not_done', ctx.headRef);
  const results = reconcileRefs(ctx, []);
  // Only a printed REFUSE is the owner's decision; a child that failed without one (malformed STATE, killed,
  // missing template) is a failed step: stop resumable, like every other step that cannot finish.
  const broke = results.find((x) => x.kind === 'ERROR');
  if (broke) stop('reconcile_origin_failed', `${broke.ref}: ${broke.line}`);
  const bad = results.filter((x) => x.kind !== 'RECONCILED' && x.kind !== 'NOOP');
  if (bad.length > 0) {
    for (const x of bad) keptItem(raise('reconcile_refused', x.ref, x.line).o, 'reconcile-origin');
    return { status: 'retained', detail: bad.map((x) => x.line).join('; ') };
  }
  const done = results.filter((x) => x.kind === 'RECONCILED');
  return done.length > 0 ? { status: 'done', detail: `${done.length} reconciled` } : { status: 'noop', detail: 'no_trace' };
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
  const tails = ledgerTails(ctx, wt) ?? [];
  if (notDone(ctx, 'sync-base') && tails.length > 0) return keepStep(ctx, 'remove-worktree', 'ledger_tails_wait_for_sync');
  const why = worktreeVerdict(ctx, wt, { allowTails: true });
  if (why) stop(...why, { phase: 'plan' });
  for (const t of tails) {
    let cur = null;
    try { cur = fs.readFileSync(path.join(ctx.origin, t.rel)); } catch { /* absent */ }
    if (cur && cur.length > 0 && cur[cur.length - 1] !== 10) stop('ledger_unaligned', t.rel, { phase: 'plan' });
  }
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
  const based = dependentNumbers(ctx.adapter.listDependents(b, 'base'));
  const opened = dependentNumbers(ctx.adapter.listDependents(b, 'head'));
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
  const retain = (reason, fact = '') => {
    keptItem(raise(reason, `origin/${b}`, fact).o, 'delete-branch');
    return { status: 'retained', detail: fact ? `${reason} ${fact}` : reason };
  };
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

// The local branch stays (its worktree stays, or its tip is not the PR head); the origin branch is still deleted by lease.
function keepLocalBranch(ctx, reason = 'kept_with_worktree', detail = ctx.headRef) {
  if (!branchTip(ctx)) return finishBranch(ctx, false);
  keptItem(raise(reason, ctx.headRef, detail, { phase: 'plan' }).o, 'delete-branch');
  const r = finishBranch(ctx, false);
  return { status: 'retained', detail: `${reason}${r.status === 'done' ? ' (origin branch deleted)' : ''}` };
}

function finishBranch(ctx, localDone) {
  const remote = deleteRemoteBranch(ctx);
  if (remote.status === 'retained') ctx.remoteRetained = remote;
  if (localDone || remote.status === 'done') {
    return { status: 'done', detail: remote.status === 'retained' ? `${ctx.headRef} ${remote.detail}` : ctx.headRef };
  }
  return remote.status === 'retained' ? remote : { status: 'noop', detail: 'no_branch' };
}

function deleteBranch(ctx) {
  const tip = branchTip(ctx);
  const cur = git(ctx.origin, ['symbolic-ref', '-q', '--short', 'HEAD']).stdout.trim();
  if (notDone(ctx, 'remove-worktree')) return keepLocalBranch(ctx);
  let localDone = false;
  if (tip && ctx.headRef !== ctx.base && ctx.headRef !== cur) {
    if (!/^[0-9a-f]{40}$/i.test(ctx.head)) stop('branch_moved', 'PR head sha unknown');
    if (tip !== ctx.head) return keepLocalBranch(ctx, 'tip_mismatch', `${ctx.headRef} at ${tip}, PR head ${ctx.head}`);
    const r = git(ctx.origin, ['update-ref', '-d', `refs/heads/${ctx.headRef}`, ctx.head]);
    if (r.status !== 0) stop('branch_moved', `${ctx.headRef} no longer at ${ctx.head}`);
    localDone = true;
  }
  return finishBranch(ctx, localDone);
}

// The one refusal that precedes every step: a head branch name the engine cannot pass to git.
function planChecks(ctx) {
  if (!ctx.headRef || !BASE_NAME_RE.test(ctx.headRef) || ctx.headRef.startsWith('-')) refuse('bad_head_name', JSON.stringify(ctx.headRef));
}

// ---- D9: focus, index, audit, report --------------------------------------

// Work items this PR delivered (see deliveredDoneDocs), and their ids.
function mergedDocs(ctx) {
  // intake docs (any type but spec) the merge added or changed to done, each with the proof that ties it to this PR
  if (!ctx.docs) ctx.docs = doneDocsBetween(ctx.origin, `${ctx.mc}^1`, ctx.mc, ctx.opts.pr, repoSlug(ctx.pr?.url));
  return ctx.docs.filter((d) => d.proof);
}

function mergedRefs(ctx) {
  if (!ctx.refs) ctx.refs = new Set(mergedDocs(ctx).map((d) => d.id));
  return ctx.refs;
}
// Ids of docs the merge changed to done whose identity no proof ties to this PR.
const unprovenRefs = (ctx) => { mergedDocs(ctx); return new Set(ctx.docs.filter((d) => !d.proof).map((d) => d.id)); };

function reportStep(ctx, steps) {
  return { status: steps.some((s) => s.status === 'done') ? 'done' : 'noop', detail: 'stdout' };
}

// ---- steps ----------------------------------------------------------------

// D3: archive each draft whose merged counterpart matches (superseded) or whose owner chose archive_remove,
// then unlink it; archiveFile stops the step before the unlink when the copy does not read back equal.
function archiveDrafts(ctx) {
  const root = archiveRoot(ctx.origin, ctx.opts.pr);
  let n = 0;
  const bytes = (d) => fs.readFileSync(path.join(ctx.origin, d.path));
  const archiveRemove = (d, reason) => {
    archiveFile(ctx, { src: path.join(ctx.origin, d.path), destBase: path.join(root, 'drafts', d.path), original: d.path, reason, step: 'archive-drafts' });
    crashAt('draft-after-archive');
    fs.unlinkSync(path.join(ctx.origin, d.path));
    n++;
  };
  for (const d of ctx.drafts.superseded) {
    raise('superseded_draft', d.path, d.counterpart, { evidence: [bytes(d), d.oid] });
    archiveRemove(d, 'superseded_draft');
  }
  for (const d of ctx.drafts.divergent) {
    const { o, option } = raise('divergent_draft', d.path, d.counterpart, { phase: 'plan', evidence: [bytes(d), d.oid] });
    if (option === 'archive_remove') { archiveRemove(d, 'divergent_draft'); continue; }
    ctx.drafts.retained.push({ path: d.path, reason: 'divergent_draft' });
    if (option === 'keep') keptItem(o, 'archive-drafts');
  }
  return n > 0 ? { status: 'done', detail: `${n} archived` } : { status: 'noop', detail: 'no_draft' };
}

const HANDLERS = {
  resolve: () => ({ status: 'read' }),
  plan: () => ({ status: 'read' }),
  'archive-drafts': archiveDrafts,
  'archive-runtime': archiveRuntime,
  'sync-base': syncBase,
  'reconcile-origin': reconcileOrigin,
  'remove-worktree': removeWorktree,
  'delete-branch': deleteBranch,
};

// plan mode: the concrete targets of each action step, derived without executing it.
// Pure reads (git ls-files, rev-parse, worktree list, the focus file); nothing is written.
const PLANNERS = {
  'archive-drafts': (ctx) => [
    ...ctx.drafts.superseded.map((d) => `archive ${d.path} -> ${posix(path.relative(ctx.origin, path.join(archiveRoot(ctx.origin, ctx.opts.pr), 'drafts', d.path)))} (superseded by ${d.counterpart})`),
    ...ctx.drafts.divergent.map((d) => `ask about ${d.path} (differs from ${d.counterpart})`),
  ],
  'archive-runtime': (ctx) => {
    const wt = findRideWorktree(ctx);
    if (!wt) return [];
    const root = archiveRoot(ctx.origin, ctx.opts.pr);
    const statePath = path.join(wt.path, STATE_REL);
    return fs.existsSync(statePath) ? [`worktree:${STATE_REL} -> ${posix(path.relative(ctx.origin, path.join(root, 'worktree', STATE_REL)))}`] : [];
  },
  'sync-base': (ctx) => {
    const plan = planSync(ctx);
    if (plan.refusal || plan.held || plan.noop) return [];
    return [
      `${ctx.base} ${plan.head.slice(0, 12)}..${plan.target.slice(0, 12)}`,
      ...plan.replace.filter((rel) => rel !== INDEX_PATH).map((rel) => `take incoming ${rel} (archive the local bytes first)`),
    ];
  },
  'reconcile-origin': (ctx) => {
    if (!fs.existsSync(path.join(ctx.origin, STATE_REL))) return [];
    return reconcileRefs(ctx, ['--dry-run']).filter((x) => x.kind !== 'NOOP').map((x) => (x.kind === 'RECONCILED' ? `reconcile ${x.ref}` : `retain ${x.ref} (${x.line})`));
  },
  'remove-worktree': (ctx) => {
    const wt = findRideWorktree(ctx);
    if (!wt) return [];
    const why = worktreeVerdict(ctx, wt, { allowTails: true });
    if (why) return [`keep ${wt.path} (${why[0]} ${why[1]})`];
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

// Every file any run of this PR archived, read from the durable manifest so an interrupted
// earlier run's archives and the runtime/ledger/STATE archives appear too.
function archivedFromManifest(ctx) {
  return readJsonl(path.join(archiveRoot(ctx.origin, ctx.opts.pr), 'manifest.jsonl'))
    .map((m) => ({ path: m.original, archive: m.archive, sha256: m.sha256, reason: m.reason }));
}

function buildReport(ctx, steps, e) {
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
    untouched: ctx.drafts.untouched,
    noops: steps.filter((s) => s.status === 'noop').map((s) => `noop:${s.id}:${s.detail}`),
    audit: ctx.audit ?? null,
    ...(ctx.opts.direction ? { direction: ctx.opts.direction } : {}),
    ...(ctx.reportPath ? { report: ctx.reportPath } : {}),
    remaining: [
      ...RUN.kept.map((l) => l.replace(/^Kept: /, '')),
      ...e.pending.map((o) => `${o.reason} ${o.subject}: waiting for your decision`),
    ],
    outcomes: RUN.outcomes,
    summary: e.summary,
    ...(e.ignored.length ? { ignored: e.ignored } : {}),
  };
}

function emit(report, json, e) {
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
  lines.push(...e.ignored, ...RUN.outcomes.map(outcomeLine), ...e.lines);
  process.stdout.write(`${lines.join('\n')}\n`);
}

function runApplyOrPlan(opts) {
  const stopAfter = seam('AAI_MERGE_CLEANUP_STOP_AFTER');
  if (stopAfter && !STEP_IDS.includes(stopAfter)) usage(`AAI_MERGE_CLEANUP_STOP_AFTER names an unknown step: ${stopAfter}`);
  const origin = resolveOrigin(opts);
  RUN.pairs = opts.decide ? parseDecide(opts.decide).map((x) => ({ ...x, used: false })) : [];
  RUN.decisions = [...readJsonl(choicesFile()).filter((c) => c.option === 'keep' || c.option === 'keep_local'), ...RUN.pairs];
  const gate = readAndGate(opts, origin);
  const ctx = { opts, origin, ...gate, drafts: classifyDrafts(origin, gate.base), status: {} };
  planChecks(ctx);
  const steps = [];
  const journal = path.join(archiveRoot(origin, opts.pr), 'journal.jsonl');
  for (const id of STEP_IDS) {
    RUN.step = id;
    if (opts.mode === 'plan' && !['resolve', 'plan', 'report'].includes(id)) {
      const targets = PLANNERS[id] ? PLANNERS[id](ctx) : [];
      steps.push({ id, status: 'planned', ...(targets.length ? { targets } : {}) });
      continue;
    }
    let res;
    try {
      res = id === 'report' ? (opts.mode === 'apply' ? reportStep(ctx, steps) : { status: 'read' }) : HANDLERS[id](ctx);
    } catch (e) {
      if (!(e instanceof Keep)) throw e;
      res = { status: 'retained', detail: [e.reason, e.detail].filter(Boolean).join(' ') };
    }
    ctx.status[id] = res.status;
    steps.push({ id, status: res.status, ...(res.detail ? { detail: res.detail } : {}) });
    if (res.status === 'done') appendJsonl(journal, { step: id, status: 'done', detail: res.detail ?? '', timestamp: new Date().toISOString() });
    if (opts.mode === 'apply' && stopAfter === id) {
      process.stdout.write(`STOPPED after ${id}\n`);
      exit(4);
    }
  }
  const waiting = RUN.outcomes.some((o) => o.class === 'decide' && o.state === 'pending');
  const code = opts.mode === 'apply' && waiting ? EXIT_DECISION_PENDING : 0;
  const e = endRun(code, opts.mode === 'plan' ? 'planned' : 'complete');
  emit(buildReport(ctx, steps, e), opts.json, e);
  exit(code);
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
  const adapter = openPlatform(cwd);
  const pr = unwrap(adapter, adapter.prView(opts.pr));
  if (pr.state === 'MERGED') {
    process.stdout.write(`already_merged PR #${opts.pr} is merged; run: merge-cleanup.mjs apply --pr ${opts.pr} --pid <harness pid>\n`);
    exit(0);
  }
  checkRepo(adapter, cwd, pr);
  if (pr.state !== 'OPEN') refuse('not_open', `state=${pr.state ?? 'unknown'}`);
  if (pr.isDraft) refuse('draft', `PR #${opts.pr} is a draft`);
  const head = pr.headRefOid ?? '';
  if (head.toLowerCase() !== opts.expectHead.toLowerCase()) refuse('head_changed', `PR head ${head || 'unknown'}, expected ${opts.expectHead}`, { subject: head, evidence: [head] });
  // NB-1: lane-gate judges the sweep record against THIS checkout's HEAD while the
  // printed merge command binds the PR head; the two must be one commit, or a push
  // made elsewhere would be merged on the strength of a sweep that never saw it.
  const local = git(cwd, ['rev-parse', 'HEAD']);
  const localHead = local.status === 0 ? local.stdout.trim() : '';
  if (localHead.toLowerCase() !== head.toLowerCase()) {
    refuse('head_changed', `local HEAD ${localHead || 'unknown'} is not the PR head ${head}; sync this checkout to the PR head before merging`, { subject: head, evidence: [head, localHead] });
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
  const reviewCheck = checkReviewThreads(adapter, opts.pr, pr);
  if (!reviewCheck.ok) {
    refuse('review_unresolved', `${reviewCheck.unresolvedCount} unresolved review thread(s): ${reviewCheck.details}`);
  }
  // D5: the cleanup proof, surfaced before the merge; it never refuses the merge
  const wl = git(cwd, ['worktree', 'list', '--porcelain']);
  const mainWt = wl.status === 0 ? wl.stdout.match(/^worktree (.+)$/m)?.[1] : null;
  const rideWt = findRideWorktree({ origin: realOr(mainWt ?? cwd), headRef: String(pr.headRefName ?? '') });
  const cleanupVerdict = rideWt ? blockerVerdict(submoduleBlockers(rideWt.path)) : null;
  const cleanupBlockers = cleanupVerdict ? [{ reason: cleanupVerdict[0], detail: cleanupVerdict[1] }] : [];
  const command = adapter.mergeCommand(opts.pr, head, SCRIPT_DIR);
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
  RUN.opts = opts;
  RUN.pr = opts.pr;
  if (opts.mode === 'preflight') runPreflight(opts);
  runApplyOrPlan(opts);
}

runMain(() => main(process.argv.slice(2)));
