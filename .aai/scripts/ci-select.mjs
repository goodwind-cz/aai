#!/usr/bin/env node
//
// ci-select.mjs — PR-path suite selection with carry-forward of a previous
// successful full-mode run (CHANGE post-validation-pushes-reuse-test-results /
// SPEC spec-post-validation-pushes-reuse-test-results, D5, Spec-AC-07/08).
//
// A later push to a PR whose whole-PR selection is FULL_RUN normally re-runs the
// full sweep. When an older commit of the same PR has a completed, successful
// FULL-mode skill-suite run, and every path since that commit is a governed
// ledger/doc (select-suites.mjs --delta-base decides), only the delta is
// selected. The anchor run must belong to the SAME pull request (number, base
// ref and base sha equal the event's; a moved base never carries forward).
// Anything else fails safe: the whole-PR selector lines, byte for
// byte, plus one `CARRY_FORWARD none reason=<cell>` line.
//
// USAGE
//   node .aai/scripts/ci-select.mjs --base-ref origin/<base> --event <path>
//     --repo <owner/name> [--workflow-file skill-suite.yml] [--api-url <url>]
//     [--repo-root <dir>] [--map <path>] [--docs-audit <path>]
//   test-only: --api-fixture <json> --request-log <file>  (the workflow never
//     passes them; a map of "<path>?<query>" to {status, body})
//
// OUTPUT: select-suites.mjs lines, then exactly one CARRY_FORWARD line:
//   CARRY_FORWARD sha=<S> run=<id> url=<html_url>   (delta lines, whole-PR
//       FULL_RUN line re-printed as `WHOLE_PR FULL_RUN ...`)
//   CARRY_FORWARD none reason=<cell>                (whole-PR lines)
// Exit is 0 whenever the selector exits 0; the API is only ever reached with
// GITHUB_TOKEN (job permission `actions: read`), two GET endpoints.
//
// Node stdlib only (Node 22+ global fetch).

import { spawnSync } from 'node:child_process';
import { appendFileSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const GATE_JOB = 'skill test suite (tests/skills/, via test-framework.sh)';
export const FULL_LEG_JOB = 'skill test suite (full framework, via test-framework.sh)';
export const SELECTED_JOB = 'skill suite (selected, via test-framework.sh --skill)';
export const SELECTED_SHARDED_JOB = 'skill suite (selected sharded, via test-framework.sh --skill)';
export const SELECT_JOB = 'select suites (PR impact analysis; full elsewhere)';
export const SEED_JOB = 'worktree seed (native Windows PowerShell 5.1 and pwsh 7)';
export const SMOKE_JOB = 'self-hosting smoke (separate job — bootstraps + re-validates a full copy, ~2-3 min)';
export const TRACKED_JOB = 'tracked-ignored guard (no gitignored path may be tracked)';
export const NOTES_JOB = 'release notes';

const SELF_DIR = dirname(fileURLToPath(import.meta.url));
const CANDIDATE_CAP = 20;
const MAX_BUFFER = 64 * 1024 * 1024;

function parseArgs(argv) {
  const o = {
    baseRef: null, event: null, repo: null, workflowFile: 'skill-suite.yml', apiUrl: null,
    repoRoot: null, map: null, docsAudit: null, apiFixture: null, requestLog: null,
    checkoutSha: null, workflowSha: null, currentRunId: null,
  };
  const keys = {
    '--base-ref': 'baseRef', '--event': 'event', '--repo': 'repo', '--workflow-file': 'workflowFile',
    '--api-url': 'apiUrl', '--repo-root': 'repoRoot', '--map': 'map', '--docs-audit': 'docsAudit',
    '--api-fixture': 'apiFixture', '--request-log': 'requestLog',
    '--checkout-sha': 'checkoutSha', '--workflow-sha': 'workflowSha', '--current-run-id': 'currentRunId',
  };
  for (let i = 0; i < argv.length; i++) {
    const k = keys[argv[i]];
    if (k) o[k] = argv[++i];
  }
  return o;
}

function selectorArgs(o) {
  const a = [];
  if (o.repoRoot) a.push('--repo-root', o.repoRoot);
  if (o.map) a.push('--map', o.map);
  if (o.docsAudit) a.push('--docs-audit', o.docsAudit);
  return a;
}

function runSelector(o, extra) {
  const script = process.env.CI_SELECT_SELECTOR || join(SELF_DIR, 'select-suites.mjs');
  const r = spawnSync(process.execPath, [script, ...extra, ...selectorArgs(o)], {
    encoding: 'utf8', maxBuffer: MAX_BUFFER,
  });
  return { out: r.stdout || '', err: r.stderr || '', status: r.status === null ? 1 : r.status };
}

function lines(text) {
  return text.split('\n').filter((l) => l.length > 0);
}

function emit(whole, tail) {
  process.stdout.write(whole.out);
  if (whole.out.length > 0 && !whole.out.endsWith('\n')) process.stdout.write('\n');
  process.stdout.write(`${tail}\n`);
}

async function apiGet(o, token, path) {
  if (o.requestLog) appendFileSync(o.requestLog, `GET ${path}\n`);
  if (o.apiFixture) {
    const map = JSON.parse(readFileSync(o.apiFixture, 'utf8'));
    const hit = map[path];
    if (!hit) return { status: 404, body: null };
    return { status: hit.status, body: hit.body === undefined ? null : hit.body, raw: hit.raw };
  }
  const base = (o.apiUrl || process.env.GITHUB_API_URL || 'https://api.github.com').replace(/\/+$/, '');
  const res = await fetch(`${base}${path}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
    signal: AbortSignal.timeout(15000),
  });
  const text = await res.text();
  return { status: res.status, raw: text };
}

class Stop extends Error {
  constructor(reason) { super(reason); this.reason = reason; }
}

// Fetch + validate one listing. Any non-200, parse error, or total_count above
// the entries returned ends the whole search; it never skips to the next one.
async function getList(o, token, path, field) {
  let r;
  try {
    r = await apiGet(o, token, path);
  } catch (e) {
    throw new Stop('api-error');
  }
  if (r.status !== 200) throw new Stop(`api-${r.status}`);
  let body = r.body;
  if (typeof r.raw === 'string') {
    try { body = JSON.parse(r.raw); } catch (e) { throw new Stop('api-json'); }
  }
  if (!body || typeof body !== 'object' || !Array.isArray(body[field])
    || !Number.isInteger(body.total_count) || body.total_count < body[field].length) throw new Stop('api-json');
  if (body.total_count > body[field].length) throw new Stop('pagination');
  return body[field];
}

async function getObject(o, token, path) {
  let r;
  try { r = await apiGet(o, token, path); } catch { throw new Stop('api-error'); }
  if (r.status !== 200) throw new Stop(`api-${r.status}`);
  let body = r.body;
  if (typeof r.raw === 'string') {
    try { body = JSON.parse(r.raw); } catch { throw new Stop('api-json'); }
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Stop('api-json');
  return body;
}

const sha = (v) => typeof v === 'string' && /^[0-9a-f]{40}$/.test(v);
const repoName = (v) => v && typeof v.full_name === 'string' ? v.full_name : null;

export function bodyEditEligibility(ev, o) {
  if (!ev || ev.action !== 'edited') return 'action-not-edited';
  if (!ev.changes || Object.keys(ev.changes).length !== 1 || !Object.hasOwn(ev.changes, 'body')) return 'changes-not-body-only';
  const old = ev.changes.body?.from;
  const now = ev.pull_request?.body;
  if (!((old === null || typeof old === 'string') && (now === null || typeof now === 'string'))
    || old === now) return 'body-malformed-or-unchanged';
  const pr = ev.pull_request;
  if (pr.labels != null && !Array.isArray(pr.labels)) return 'identity-malformed';
  if (pr.labels?.some((l) => l?.name === 'ci-full')) return 'ci-full';
  if (!Number.isInteger(pr.number) || pr.number <= 0 || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(o.repo || '')
    || repoName(ev.repository) !== o.repo
    || repoName(pr.head?.repo) !== o.repo || repoName(pr.base?.repo) !== o.repo
    || typeof pr.head.ref !== 'string' || !pr.head.ref || typeof pr.base.ref !== 'string' || !pr.base.ref
    || !sha(pr.head.sha) || !sha(pr.base.sha) || !sha(o.checkoutSha) || !sha(o.workflowSha)
    || o.checkoutSha !== o.workflowSha || !/^[A-Za-z0-9_.-]+\.ya?ml$/.test(o.workflowFile || '')
    || !/^[1-9][0-9]*$/.test(String(o.currentRunId))) {
    return 'identity-malformed';
  }
  return null;
}

function checkoutParents(o) {
  const args = ['rev-list', '--parents', '-n', '1', o.checkoutSha];
  const r = spawnSync('git', o.repoRoot ? ['-C', o.repoRoot, ...args] : args,
    { encoding: 'utf8', maxBuffer: MAX_BUFFER });
  if (r.status !== 0) throw new Stop('git-error');
  return r.stdout.trim().split(/\s+/);
}

function identity(ev, o) {
  return `ci-source-identity-v1 head=${ev.pull_request.head.sha} base=${ev.pull_request.base.sha} checkout=${o.checkoutSha} workflow=${o.workflowSha}`;
}

function exactlyOne(jobs, name, conclusion) {
  const matches = jobs.filter((j) => j.name === name);
  return matches.length === 1 && matches[0].status === 'completed' && matches[0].conclusion === conclusion;
}

function identityProofStep(job, name) {
  if (!Array.isArray(job?.steps)) return false;
  const steps = job.steps.filter((s) => typeof s.name === 'string'
    && /^ci-source-identity-v1(?: |$)/.test(s.name));
  return steps.length === 1 && steps[0].name === name
    && steps[0].status === 'completed' && steps[0].conclusion === 'success';
}

function planFromSelect(job) {
  const steps = job.steps?.filter((s) => typeof s.name === 'string' && s.name.startsWith('ci-source-plan-v1 ')) || [];
  if (steps.length !== 1 || steps[0].status !== 'completed' || steps[0].conclusion !== 'success') return null;
  const m = /^ci-source-plan-v1 full=(\[[^ ]*\]) selected=(\[[^ ]*\]|none) runners=(1|2|none)$/.exec(steps[0].name);
  if (!m) return null;
  try {
    const full = JSON.parse(m[1]);
    const selected = m[2] === 'none' ? [] : JSON.parse(m[2]);
    if (!Array.isArray(full) || !Array.isArray(selected)
      || !([['all'], [1, 2, 3, 4]].some((p) => JSON.stringify(full) === JSON.stringify(p)))
      || !([[], [1], [1, 2]].some((p) => JSON.stringify(selected) === JSON.stringify(p)))) return null;
    return { full, selected, runners: m[3] };
  } catch { return null; }
}

// Run-list metadata is a search hint. Only attempt-bound jobs, a successful
// workflow-produced identity step, and the complete plan authorize reuse.
export function proveBodyRun(run, jobs, ev, o) {
  const pr = ev.pull_request;
  if (!run || run.id === Number(o.currentRunId)) return 'current-run';
  if (!Number.isInteger(run.id) || !Number.isInteger(run.run_attempt) || run.run_attempt < 1
    || run.status !== 'completed' || run.conclusion !== 'success' || run.event !== 'pull_request'
    || run.head_sha !== pr.head.sha || run.head_branch !== pr.head.ref
    || repoName(run.repository) !== o.repo || repoName(run.head_repository) !== o.repo
    || ![`.github/workflows/${o.workflowFile}`, `.github/workflows/${o.workflowFile}@refs/pull/${pr.number}/merge`].includes(run.path)
    || !Array.isArray(run.pull_requests)
    || run.pull_requests.length !== 1 || run.pull_requests[0]?.number !== pr.number
    || run.pull_requests[0]?.base?.ref !== pr.base.ref
    || run.pull_requests[0]?.base?.sha !== pr.base.sha
    || run.html_url !== `https://github.com/${o.repo}/actions/runs/${run.id}`) return 'run-identity';
  if (!Array.isArray(jobs) || jobs.length === 0 || jobs.length > 100
    || jobs.some((j) => j.run_attempt !== run.run_attempt)) return 'job-attempt';
  const seen = new Set();
  for (const j of jobs) {
    if (typeof j.name !== 'string' || seen.has(j.name)) return 'job-duplicate';
    seen.add(j.name);
  }
  for (const name of [SELECT_JOB, GATE_JOB, SEED_JOB, SMOKE_JOB, TRACKED_JOB, NOTES_JOB]) {
    if (!exactlyOne(jobs, name, 'success')) return `job-${name === NOTES_JOB ? 'release-notes' : 'required'}`;
  }
  const sel = jobs.find((j) => j.name === SELECT_JOB);
  if (!identityProofStep(sel, identity(ev, o))) return 'identity-proof';
  for (const name of [SEED_JOB, SMOKE_JOB]) {
    if (!identityProofStep(jobs.find((j) => j.name === name), identity(ev, o))) return 'identity-proof';
  }
  const plan = planFromSelect(sel);
  if (!plan) return 'plan-proof';
  const full = jobs.filter((j) => j.name === FULL_LEG_JOB || j.name.startsWith(`${FULL_LEG_JOB} (`));
  const selected = jobs.filter((j) => j.name === SELECTED_JOB);
  const sharded = jobs.filter((j) => j.name === SELECTED_SHARDED_JOB || j.name.startsWith(`${SELECTED_SHARDED_JOB} (`));
  const checkSource = (name) => {
    const j = jobs.find((x) => x.name === name);
    return !!j && identityProofStep(j, identity(ev, o));
  };
  const fullNames = plan.full.map((n) => n === 'all' ? FULL_LEG_JOB : `${FULL_LEG_JOB} (${n})`);
  if (full.length === fullNames.length && fullNames.every((n) => exactlyOne(jobs, n, 'success') && checkSource(n))
    && exactlyOne(jobs, SELECTED_JOB, 'skipped')
    && (sharded.length === 0 || exactlyOne(jobs, SELECTED_SHARDED_JOB, 'skipped'))) return null;
  if (full.length === 1 && exactlyOne(jobs, FULL_LEG_JOB, 'skipped')) {
    if (plan.runners === '1' && selected.length === 1 && exactlyOne(jobs, SELECTED_JOB, 'success')
      && checkSource(SELECTED_JOB) && sharded.length <= 1
      && (sharded.length === 0 || exactlyOne(jobs, SELECTED_SHARDED_JOB, 'skipped'))) return null;
    const names = plan.selected.map((n) => `${SELECTED_SHARDED_JOB} (${n})`);
    if (plan.runners === '2' && selected.length === 1 && exactlyOne(jobs, SELECTED_JOB, 'skipped')
      && sharded.length === names.length && names.length === 2
      && names.every((n) => exactlyOne(jobs, n, 'success') && checkSource(n))) return null;
  }
  return 'source-job-set';
}

async function findBodyAnchor(o, ev, token) {
  const pr = ev.pull_request;
  const path = `/repos/${o.repo}/actions/workflows/${o.workflowFile}/runs?event=pull_request&status=completed&head_sha=${pr.head.sha}&per_page=20`;
  const runs = await getList(o, token, path, 'workflow_runs');
  if (runs.length > CANDIDATE_CAP) throw new Stop('candidate-cap');
  let reason = 'no-proven-run';
  for (const candidate of runs) {
    if (!Number.isInteger(candidate.id) || candidate.id === Number(o.currentRunId)) continue;
    const detailPath = `/repos/${o.repo}/actions/runs/${candidate.id}`;
    const before = await getObject(o, token, detailPath);
    if (!Number.isInteger(before.run_attempt) || before.status !== 'completed') { reason = 'run-attempt'; continue; }
    const jobs = await getList(o, token,
      `/repos/${o.repo}/actions/runs/${candidate.id}/attempts/${before.run_attempt}/jobs?per_page=100`, 'jobs');
    const after = await getObject(o, token, detailPath);
    if (after.run_attempt !== before.run_attempt || after.status !== before.status
      || after.conclusion !== before.conclusion) { reason = 'run-changed'; continue; }
    const refused = proveBodyRun(after, jobs, ev, o);
    if (!refused) return { run: after.id, attempt: after.run_attempt, url: after.html_url };
    reason = refused;
  }
  throw new Stop(reason);
}

// Full-mode proof (D7): gate green, at least one full-leg and all legs green,
// the selected job skipped. A selected-mode success is not an anchor.
function provesFullMode(jobs) {
  const gate = jobs.find((j) => j.name === GATE_JOB);
  if (!gate || gate.conclusion !== 'success') return false;
  const legs = jobs.filter((j) => typeof j.name === 'string' && j.name.startsWith(`${FULL_LEG_JOB} (`));
  if (legs.length === 0 || !legs.every((j) => j.conclusion === 'success')) return false;
  const sel = jobs.find((j) => j.name === SELECTED_JOB);
  return !!sel && sel.conclusion === 'skipped';
}

function revList(o, head) {
  // one beyond the cap, so "exactly CAP commits" is told apart from "more than CAP"
  const args = ['rev-list', `--max-count=${CANDIDATE_CAP + 1}`, head, `^${o.baseRef}`];
  const r = spawnSync('git', o.repoRoot ? ['-C', o.repoRoot, ...args] : args, { encoding: 'utf8', maxBuffer: MAX_BUFFER });
  if (r.status !== 0) return null;
  return lines(r.stdout).map((s) => s.trim());
}

// Returns { sha, run, url } or throws Stop(<reason>).
async function findAnchor(o, ev, token) {
  const head = ev.pull_request.head;
  const H = head.sha;
  const cands = revList(o, H);
  if (cands === null) throw new Stop('git-error');
  const capped = cands.length > CANDIDATE_CAP;
  const older = cands.slice(0, CANDIDATE_CAP).filter((c) => c !== H);
  const pr = ev.pull_request;
  let sawMismatch = false;
  let sawPrMismatch = false;
  let sawBaseMoved = false;
  let sawNotFull = false;
  for (const C of older) {
    const runs = await getList(
      o, token,
      `/repos/${o.repo}/actions/workflows/${o.workflowFile}/runs?event=pull_request&status=completed&head_sha=${C}&per_page=20`,
      'workflow_runs',
    );
    const ok = runs.filter((r) => r.head_sha === C && r.event === 'pull_request' && r.conclusion === 'success');
    const kept = [];
    for (const r of ok) {
      const sameBranch = r.head_branch === head.ref;
      const sameRepo = !!r.head_repository && r.head_repository.full_name === head.repo.full_name;
      if (!(sameBranch && sameRepo)) { sawMismatch = true; continue; }
      // The run must belong to THIS pull request and its base must not have
      // moved: a closed-and-reopened PR from the same branch, a retarget or a
      // newer base all fail safe to the whole-PR selection.
      const prs = Array.isArray(r.pull_requests) ? r.pull_requests : [];
      const samePr = prs.filter((p) => p && p.number === pr.number);
      if (samePr.length === 0) { sawPrMismatch = true; continue; }
      const sameBase = samePr.some((p) => p.base && p.base.ref === pr.base.ref && p.base.sha === pr.base.sha);
      if (!sameBase) { sawBaseMoved = true; continue; }
      kept.push(r);
    }
    kept.sort((a, b) => String(b.created_at || '').localeCompare(String(a.created_at || '')));
    for (const r of kept) {
      const jobs = await getList(o, token, `/repos/${o.repo}/actions/runs/${r.id}/jobs?filter=latest&per_page=100`, 'jobs');
      if (provesFullMode(jobs)) return { sha: C, run: r.id, url: r.html_url };
      sawNotFull = true;
    }
  }
  if (sawNotFull) throw new Stop('no-full-mode-run');
  if (sawMismatch) throw new Stop('head-mismatch');
  if (sawPrMismatch) throw new Stop('anchor-pr-mismatch');
  if (sawBaseMoved) throw new Stop('anchor-base-moved');
  throw new Stop(capped ? 'candidate-cap' : 'no-covering-run');
}

export async function main(argv, env = process.env) {
  const o = parseArgs(argv);
  const whole = runSelector(o, ['--base-ref', String(o.baseRef)]);
  if (whole.err) process.stderr.write(whole.err);
  if (whole.status !== 0) {
    process.stdout.write(whole.out);
    return whole.status;
  }
  const none = (reason) => emit(whole, `CARRY_FORWARD none reason=${reason}`);
  let ev;
  try {
    ev = JSON.parse(readFileSync(String(o.event), 'utf8'));
  } catch (e) { none('event-malformed'); return 0; }
  if (ev?.action === 'edited') {
    const reason = bodyEditEligibility(ev, o);
    if (reason) { none(`body-reuse:${reason}`); return 0; }
    let parents;
    try { parents = checkoutParents(o); } catch (e) {
      none(e instanceof Stop ? e.reason : 'git-error'); return 0;
    }
    if (parents.length !== 3 || parents[0] !== o.checkoutSha
      || parents[1] !== ev.pull_request.base.sha || parents[2] !== ev.pull_request.head.sha) {
      none('body-reuse:checkout-parents'); return 0;
    }
    if (!env.GITHUB_TOKEN) { none('body-reuse:no-token'); return 0; }
    try {
      const anchor = await findBodyAnchor(o, ev, env.GITHUB_TOKEN);
      process.stdout.write(`BODY_REUSE run=${anchor.run} attempt=${anchor.attempt} url=${anchor.url} head=${ev.pull_request.head.sha} base=${ev.pull_request.base.sha} checkout=${o.checkoutSha} workflow=${o.workflowSha}\n`);
    } catch (e) {
      none(`body-reuse:${e instanceof Stop ? e.reason : 'internal-error'}`);
    }
    return 0;
  }
  if (!lines(whole.out).some((l) => l.startsWith('FULL_RUN'))) { none('whole-pr-selected'); return 0; }
  if (!ev || ev.action !== 'synchronize') { none(`action-${ev && ev.action ? ev.action : 'missing'}`); return 0; }
  const head = ev.pull_request && ev.pull_request.head;
  if (!head || !head.sha || !head.ref || !head.repo || !head.repo.full_name || !o.repo || !o.baseRef) {
    none('event-malformed'); return 0;
  }
  const pr = ev.pull_request;
  if (!Number.isInteger(pr.number) || !pr.base || typeof pr.base.ref !== 'string' || !pr.base.ref
    || typeof pr.base.sha !== 'string' || !pr.base.sha) {
    none('event-malformed'); return 0;
  }
  const token = env.GITHUB_TOKEN;
  if (!token) { none('no-token'); return 0; }

  let anchor;
  try {
    anchor = await findAnchor(o, ev, token);
  } catch (e) {
    none(e instanceof Stop ? e.reason : 'internal-error');
    return 0;
  }

  const delta = runSelector(o, ['--delta-base', anchor.sha, '--head', head.sha]);
  const dl = lines(delta.out);
  const refused = dl.find((l) => l.startsWith('DELTA_REFUSED'));
  if (delta.status !== 0 || refused || !dl.some((l) => l.startsWith('DELTA base='))) {
    const m = refused && /reason=(\S+)/.exec(refused);
    none(`delta-refused:${m ? m[1] : 'internal-error'}`);
    return 0;
  }
  const first = lines(whole.out).find((l) => l.startsWith('FULL_RUN'));
  process.stdout.write(`WHOLE_PR ${first}\n${dl.join('\n')}\n`);
  process.stdout.write(`CARRY_FORWARD sha=${anchor.sha} run=${anchor.run} url=${anchor.url}\n`);
  return 0;
}

function realOrResolve(p) {
  try { return realpathSync(p); } catch { return resolve(p); }
}

if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main(process.argv.slice(2)).then((c) => { process.exitCode = c; }, () => { process.exitCode = 1; });
}
