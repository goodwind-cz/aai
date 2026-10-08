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
// Node stdlib only (Node 20 global fetch).

import { spawnSync } from 'node:child_process';
import { appendFileSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const GATE_JOB = 'skill test suite (tests/skills/, via test-framework.sh)';
export const FULL_LEG_JOB = 'skill test suite (full framework, via test-framework.sh)';
export const SELECTED_JOB = 'skill suite (selected, via test-framework.sh --skill)';

const SELF_DIR = dirname(fileURLToPath(import.meta.url));
const CANDIDATE_CAP = 20;
const MAX_BUFFER = 64 * 1024 * 1024;

function parseArgs(argv) {
  const o = {
    baseRef: null, event: null, repo: null, workflowFile: 'skill-suite.yml', apiUrl: null,
    repoRoot: null, map: null, docsAudit: null, apiFixture: null, requestLog: null,
  };
  const keys = {
    '--base-ref': 'baseRef', '--event': 'event', '--repo': 'repo', '--workflow-file': 'workflowFile',
    '--api-url': 'apiUrl', '--repo-root': 'repoRoot', '--map': 'map', '--docs-audit': 'docsAudit',
    '--api-fixture': 'apiFixture', '--request-log': 'requestLog',
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
  if (!body || typeof body !== 'object' || !Array.isArray(body[field])) throw new Stop('api-json');
  if (typeof body.total_count === 'number' && body.total_count > body[field].length) throw new Stop('pagination');
  return body[field];
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
  if (!lines(whole.out).some((l) => l.startsWith('FULL_RUN'))) { none('whole-pr-selected'); return 0; }

  let ev;
  try {
    ev = JSON.parse(readFileSync(String(o.event), 'utf8'));
  } catch (e) { none('event-malformed'); return 0; }
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
