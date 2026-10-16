// platform-adapter.mjs — the one seam between AAI's git-host consumers and the
// host CLIs (spec-git-platform-detected-at-bootstrap, ride 1). Node stdlib only.
//
// It carries the platform RECORD side (D1, D3, D5): the column-0 `platform:`
// key of docs/ai/pr-config.yaml, the resolution rule every consumer shares and
// the CLI authentication probe; and the host OPERATIONS (D6 to D8, D10, D13):
// createAdapter with github, azure and generic implementations, and azSpawnSpec.
// The Azure merge executor (D9) lives in platform.mjs.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { classify, extractHost, readOriginUrl } from '../pr-platform.mjs';

export const PLATFORM_VALUES = ['github', 'azure', 'unknown', 'none'];
const KNOWN_DETECTED = ['github', 'azure', 'none'];
export const PR_CONFIG_REL = 'docs/ai/pr-config.yaml';
const AUTH_TIMEOUT_MS = 30000;

// D1: column-0 line scan, same discipline as reviewer_bots. The value is the
// ENTIRE rest of the line, trimmed, and must equal a closed-set token.
// Returns null (file or key absent), one of PLATFORM_VALUES, or 'invalid'.
export function readRecordedPlatform(repoRoot) {
  let raw;
  try {
    raw = fs.readFileSync(path.join(repoRoot, PR_CONFIG_REL), 'utf8');
  } catch {
    return null;
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^platform:(.*)$/);
    if (!m) continue;
    const v = m[1].trim();
    return PLATFORM_VALUES.includes(v) ? v : 'invalid';
  }
  return null;
}

// Closed-set classification of the origin remote; none when there is none.
export function detectPlatform({ repoRoot, remoteUrl } = {}) {
  const url = remoteUrl !== undefined ? (remoteUrl || null) : readOriginUrl(repoRoot);
  if (!url) return 'none';
  const c = classify(extractHost(url));
  return KNOWN_DETECTED.includes(c) ? c : 'unknown';
}

// D5: a mismatch is an invalid record, or a record that differs from a
// detected github, azure or none. A detected unknown never contradicts.
export function isMismatch(recorded, detected) {
  if (recorded === null) return false;
  return recorded === 'invalid' || (KNOWN_DETECTED.includes(detected) && recorded !== detected);
}

// D5 resolution, shared by every consumer.
export function resolvePlatform({ repoRoot, remoteUrl } = {}) {
  const recorded = readRecordedPlatform(repoRoot);
  const detected = detectPlatform({ repoRoot, remoteUrl });
  const mismatch = isMismatch(recorded, detected);
  if (recorded !== null && recorded !== 'invalid') {
    return { platform: recorded, recorded, detected, mismatch, legacy: false };
  }
  if (recorded === null && KNOWN_DETECTED.includes(detected)) {
    return { platform: detected, recorded, detected, mismatch, legacy: false };
  }
  if (recorded === null) {
    return { platform: 'github', recorded, detected, mismatch, legacy: true };
  }
  return { platform: null, recorded, detected, mismatch, legacy: false };
}

// D13: on Windows the Azure CLI is az.cmd, which Node refuses to spawn without
// a shell; the one safe route is cmd.exe /d /s /c az <args> after every arg is
// checked against a closed character set, so no shell metacharacter can pass.
// cmd.exe also looks in the current directory before PATH, so the spec's env sets
// NoDefaultCurrentDirectoryInExePath=1 and a planted az.cmd in the repo never runs.
const AZ_SAFE_ARG = /^[A-Za-z0-9._\/:=@-]+$/;
export function azSpawnSpec(args, platform = process.platform) {
  if (platform !== 'win32') return { cmd: 'az', args };
  const bad = args.find((a) => !AZ_SAFE_ARG.test(String(a)));
  if (bad !== undefined) return { refused: 'az_arg_unsafe', detail: `az argument refused on Windows: ${JSON.stringify(String(bad))}` };
  return {
    cmd: process.env.ComSpec || 'cmd.exe',
    args: ['/d', '/s', '/c', 'az', ...args],
    env: { ...process.env, NoDefaultCurrentDirectoryInExePath: '1' },
  };
}

function runTool(cmd, args, runner, hostPlatform) {
  let spec = { cmd, args };
  if (cmd === 'az') {
    spec = azSpawnSpec(args, hostPlatform);
    if (spec.refused) return 'unauthenticated';
  }
  const res = (runner || spawnSync)(spec.cmd, spec.args, { stdio: 'ignore', timeout: AUTH_TIMEOUT_MS, env: spec.env });
  if (res.error) return res.error.code === 'ENOENT' ? 'cli_missing' : 'unauthenticated';
  return res.status === 0 ? 'ok' : 'unauthenticated';
}

// D3: one result token per platform; the exact argv is part of the contract.
export function authStatus(platform, { runner, hostPlatform } = {}) {
  if (platform === 'github') return runTool('gh', ['auth', 'status'], runner, hostPlatform);
  if (platform === 'azure') {
    const account = runTool('az', ['account', 'show', '--output', 'json'], runner, hostPlatform);
    if (account !== 'ok') return account;
    const ext = runTool('az', ['extension', 'show', '--name', 'azure-devops', '--output', 'json'], runner, hostPlatform);
    return ext === 'ok' ? 'ok' : (ext === 'cli_missing' ? 'cli_missing' : 'extension_missing');
  }
  return 'skipped';
}

// ---- host operations (D6 to D8, D10) ---------------------------------------
export const PR_FIELDS = 'number,state,isDraft,headRefOid,headRefName,baseRefName,mergeStateStatus,statusCheckRollup,mergeCommit,url,isCrossRepository';
const AZ_STATE = { active: 'OPEN', completed: 'MERGED', abandoned: 'CLOSED' };
const UNRESOLVED_THREAD_STATUSES = ['active', 'pending'];
const READ_TIMEOUT_MS = 120000;
const BIG_BUFFER = 64 * 1024 * 1024;
const GENERIC_MANUAL = (op) => `open the pull request on your git host and ${op === 'mergeCommand' ? 'merge it there' : 'check it there'}; then delete the worktree and branch by hand`;

// The refusal name a consumer prints for a failed read: the CLI's own prefix for a failed or unreadable call, any other reason (repo_mismatch, az_arg_unsafe) as is.
const refusalFor = (prefix) => (r) => (r.reason === 'read_failed' || r.reason === 'read_invalid' ? `${prefix}_${r.reason}` : r.reason);

const okv = (value) => ({ ok: true, value });
const bad = (reason, detail) => ({ ok: false, reason, detail });

// stdout of a finished call parsed as JSON; the failure classes of D7/D8.
function readJson(res, what, failedDetail) {
  if (res.error || res.status !== 0) return bad('read_failed', failedDetail);
  try { return okv(JSON.parse(res.stdout)); } catch { return bad('read_invalid', `${what} printed no JSON`); }
}

// owner/repo of a git remote URL or a GitHub pull-request URL, lower-cased; null
// when it is not recognisably a hosted repository (a local path, a bare name).
export function githubRepoSlug(url) {
  const u = String(url ?? '').trim().replace(/\/pull\/\d+.*$/, '').replace(/\/+$/, '');
  const m = u.match(/^(?:https?|ssh|git):\/\/(?:[^@/]+@)?[^/:]+(?::\d+)?\/([^/]+)\/([^/]+?)(?:\.git)?$/)
    ?? u.match(/^(?:[^@/\s]+@)?[^/:\s]*\.[^/:\s]+:([^/]+)\/([^/]+?)(?:\.git)?$/);
  return m ? `${m[1]}/${m[2]}`.toLowerCase() : null;
}

// org/project/repo of an Azure DevOps remote or web URL, lower-cased and
// URL-decoded; null for anything that is not one of the three Azure forms.
export function azureRepoId(url) {
  const u = String(url ?? '').trim().replace(/\/pullrequest\/\d+.*$/, '').replace(/\/+$/, '');
  const dec = (x) => { try { return decodeURIComponent(x); } catch { return x; } };
  let m = u.match(/^https?:\/\/(?:[^@/]+@)?dev\.azure\.com\/([^/]+)\/([^/]+)\/_git\/([^/]+?)(?:\.git)?$/i);
  if (!m) m = u.match(/^(?:ssh:\/\/)?(?:[^@/]+@)?ssh\.dev\.azure\.com[:/]v3\/([^/]+)\/([^/]+)\/([^/]+?)(?:\.git)?$/i);
  if (!m) m = u.match(/^https?:\/\/(?:[^@/]+@)?([^./]+)\.visualstudio\.com\/(?:DefaultCollection\/)?([^/]+)\/_git\/([^/]+?)(?:\.git)?$/i);
  return m ? `${dec(m[1])}/${dec(m[2])}/${dec(m[3])}`.toLowerCase() : null;
}

function repoMatchesWith(idOf, originUrl, pr) {
  const remote = idOf(originUrl);
  const prId = idOf(pr?.url);
  if (remote && prId && remote !== prId) return bad('repo_mismatch', `PR ${prId}, origin ${remote}`);
  return okv(true);
}

function githubAdapter({ cwd, runner }) {
  const run = (args, extra) => (runner || spawnSync)('gh', args, { cwd, encoding: 'utf8', ...extra });
  return {
    platform: 'github',
    refusalReason: refusalFor('gh'),
    prView(n) {
      const r = readJson(run(['pr', 'view', String(n), '--json', PR_FIELDS], { maxBuffer: BIG_BUFFER }), 'gh pr view', `gh pr view ${n}`);
      return r;
    },
    listDependents(branch, side = 'base') {
      const res = run(['pr', 'list', '--state', 'open', `--${side}`, branch, '--json', 'number', '--limit', '100'], { timeout: READ_TIMEOUT_MS });
      const r = readJson(res, 'gh pr list', `gh pr list --${side} ${branch}`);
      if (!r.ok) return r;
      if (Array.isArray(r.value) && r.value.every((x) => Number.isInteger(x?.number))) return okv(r.value.map((x) => x.number));
      return bad('read_invalid', 'gh pr list printed no list of numbers');
    },
    reviewThreads(n, pr) {
      const slug = githubRepoSlug(pr?.url);
      if (!slug) return okv({ unresolvedCount: 0, details: '' });
      const [owner, repo] = slug.split('/');
      let hostname = null;
      try { const u = new URL(pr.url); if (u.hostname) hostname = u.hostname; } catch { /* no host */ }
      const query = 'query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) { repository(owner: $owner, name: $repo) { pullRequest(number: $pr) { reviewThreads(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes { isResolved isOutdated comments(first: 10) { nodes { body author { login } path line } } } } } } }';
      const apiArgs = ['api', 'graphql', '--paginate', '--slurp'];
      if (hostname) apiArgs.push('--hostname', hostname);
      apiArgs.push('-F', `owner=${owner}`, '-F', `repo=${repo}`, '-F', `pr=${n}`, '-f', `query=${query}`);
      const r = readJson(run(apiArgs, { maxBuffer: 16 * 1024 * 1024 }), 'gh api review-threads', `gh api review-threads ${n}`);
      if (!r.ok) return r;
      const pages = Array.isArray(r.value) ? r.value : [r.value];
      const threads = [];
      for (const page of pages) threads.push(...(page?.data?.repository?.pullRequest?.reviewThreads?.nodes ?? []));
      const unresolved = threads.filter((t) => !t.isResolved);
      const details = unresolved.map((t) => {
        const c = t.comments?.nodes?.[0];
        const loc = c?.path ? `${c.path}${c.line ? `:${c.line}` : ''}` : '';
        return `${c?.author?.login ?? 'unknown'}${loc ? ` (${loc})` : ''}: ${(c?.body || '').slice(0, 100)}`;
      }).join('; ');
      return okv({ unresolvedCount: unresolved.length, details });
    },
    repoMatches: (originUrl, pr) => repoMatchesWith(githubRepoSlug, originUrl, pr),
    mergeCommand: (n, head) => `AAI_OPERATOR_MERGE=1 gh pr merge ${n} --squash --match-head-commit ${head}`,
    authStatus: () => authStatus('github', { runner }),
  };
}

// scheme, host and, for dev.azure.com, the first path segment of a repository URL.
function azureOrgUrl(repoUrl) {
  try {
    const u = new URL(repoUrl);
    const first = u.pathname.split('/').filter(Boolean)[0];
    return u.hostname.toLowerCase() === 'dev.azure.com' && first ? `${u.protocol}//${u.host}/${first}` : `${u.protocol}//${u.host}`;
  } catch { return null; }
}

const stripHeads = (ref) => String(ref ?? '').replace(/^refs\/heads\//, '');

// D8 normalization of the A1 read.
function normalizeAzurePr(pr, n) {
  if (!pr || typeof pr !== 'object' || typeof pr.status !== 'string') return null;
  const state = AZ_STATE[pr.status] ?? 'CLOSED';
  const repo = pr.repository ?? {};
  return {
    number: Number.isInteger(pr.pullRequestId) ? pr.pullRequestId : n,
    state,
    isDraft: Boolean(pr.isDraft),
    headRefOid: pr.lastMergeSourceCommit?.commitId,
    headRefName: stripHeads(pr.sourceRefName),
    baseRefName: stripHeads(pr.targetRefName),
    mergeCommit: state === 'MERGED' && pr.lastMergeCommit?.commitId ? { oid: pr.lastMergeCommit.commitId } : null,
    url: repo.webUrl ? `${String(repo.webUrl).replace(/\/+$/, '')}/pullrequest/${n}` : '',
    isCrossRepository: Boolean(pr.forkSource),
    azure: { orgUrl: azureOrgUrl(repo.url ?? repo.webUrl), projectId: repo.project?.id, repositoryId: repo.id },
  };
}

function azureAdapter({ cwd, runner, hostPlatform }) {
  const run = (args, extra) => {
    const spec = azSpawnSpec(args, hostPlatform);
    if (spec.refused) return { error: Object.assign(new Error(spec.detail), { code: spec.refused }), status: null, stdout: '' };
    return (runner || spawnSync)(spec.cmd, spec.args, { cwd, encoding: 'utf8', env: spec.env, ...extra });
  };
  const az = (what, failed, args, extra) => {
    const res = run(args, extra);
    if (res.error?.code === 'az_arg_unsafe') return bad('az_arg_unsafe', res.error.message);
    const r = readJson(res, what, failed);
    return r;
  };
  return {
    platform: 'azure',
    refusalReason: refusalFor('az'),
    prView(n) {
      const r = az('az repos pr show', `az repos pr show ${n}`, ['repos', 'pr', 'show', '--id', String(n), '--detect', 'true', '--output', 'json'], { maxBuffer: BIG_BUFFER });
      if (!r.ok) return r;
      const pr = normalizeAzurePr(r.value, n);
      return pr ? okv(pr) : bad('read_invalid', 'az repos pr show printed no pull request');
    },
    listDependents(branch, side = 'base') {
      const flag = side === 'head' ? '--source-branch' : '--target-branch';
      const r = az('az repos pr list', `az repos pr list ${flag} ${branch}`, ['repos', 'pr', 'list', '--status', 'active', flag, branch, '--top', '100', '--detect', 'true', '--output', 'json'], { timeout: READ_TIMEOUT_MS });
      if (!r.ok) return r;
      if (Array.isArray(r.value) && r.value.every((x) => Number.isInteger(x?.pullRequestId))) return okv(r.value.map((x) => x.pullRequestId));
      return bad('read_invalid', 'az repos pr list printed no list of pull requests');
    },
    reviewThreads(n, pr) {
      const a = pr?.azure ?? {};
      if (!a.orgUrl || !a.projectId || !a.repositoryId) return bad('read_invalid', 'pull request carries no Azure repository identity');
      const r = az('az devops invoke', `az devops invoke pullRequestThreads ${n}`, [
        'devops', 'invoke', '--area', 'git', '--resource', 'pullRequestThreads',
        '--route-parameters', `project=${a.projectId}`, `repositoryId=${a.repositoryId}`, `pullRequestId=${n}`,
        '--org', a.orgUrl, '--api-version', '7.1', '--http-method', 'GET', '--output', 'json',
      ], { maxBuffer: 16 * 1024 * 1024 });
      if (!r.ok) return r;
      if (!Array.isArray(r.value?.value)) return bad('read_invalid', 'az devops invoke printed no thread list');
      const unresolved = r.value.value.filter((t) => !t.isDeleted && UNRESOLVED_THREAD_STATUSES.includes(t.status));
      const details = unresolved.map((t) => {
        const c = t.comments?.[0];
        const loc = t.threadContext?.filePath ? `${t.threadContext.filePath}${t.threadContext.rightFileStart?.line ? `:${t.threadContext.rightFileStart.line}` : ''}` : '';
        return `${c?.author?.displayName ?? 'unknown'}${loc ? ` (${loc})` : ''}: ${(c?.content || '').slice(0, 100)}`;
      }).join('; ');
      return okv({ unresolvedCount: unresolved.length, details });
    },
    repoMatches: (originUrl, pr) => repoMatchesWith(azureRepoId, originUrl, pr),
    mergeCommand: (n, head, engineDir) => `AAI_OPERATOR_MERGE=1 node "${engineDir}/platform.mjs" merge --pr ${n} --expect-head ${head}`,
    authStatus: () => authStatus('azure', { runner, hostPlatform }),
  };
}

// D10: recorded unknown or none. Every operation is a named skip, nothing is spawned.
function genericAdapter(platform) {
  const skip = (op) => () => ({ skip: true, reason: 'platform_generic', op, manual: GENERIC_MANUAL(op) });
  return {
    platform,
    prView: skip('prView'),
    listDependents: skip('listDependents'),
    reviewThreads: skip('reviewThreads'),
    repoMatches: skip('repoMatches'),
    mergeCommand: skip('mergeCommand'),
    authStatus: () => 'skipped',
  };
}

// D6: one adapter per run. `runner(cmd, args, opts)` is spawnSync-shaped and injectable.
export function createAdapter(platform, { cwd, runner, hostPlatform } = {}) {
  if (platform === 'github') return githubAdapter({ cwd, runner });
  if (platform === 'azure') return azureAdapter({ cwd, runner, hostPlatform });
  if (platform === 'unknown' || platform === 'none') return genericAdapter(platform);
  throw new Error(`createAdapter: no adapter for platform ${JSON.stringify(platform)}`);
}
