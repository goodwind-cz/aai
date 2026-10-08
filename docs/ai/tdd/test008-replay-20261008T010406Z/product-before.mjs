#!/usr/bin/env node
// pr-capability-preflight A1: invocation-time repository read access only.
// No provider stdout/stderr or credential fields cross the result boundary.
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { classify, extractHost, sanitize } from './pr-platform.mjs';

const LIMIT = 1024 * 1024;
const result = { schema_version: 1, platform: null, repository: null,
  remote_name: null, source_branch: null, target_branch: null, head_sha: null,
  outcome: 'refused', code: null, operation: null, remedy: null,
  create_permission: 'unknown' };
const remedies = {
  IDENTITY_INVALID: 'Supply schema v1 with the actual checkout, selected remote, current source branch and a distinct explicit target; bind provider identity to a single matching fetch and push destination. Divergent or multiple destinations require explicit configuration repair.',
  CLIENT_MISSING: 'Make the named provider client available on PATH, then rerun readiness.',
  EXTENSION_MISSING: 'Ask the operator to provide a working installed azure-devops extension, then rerun readiness.',
  AUTH_FAILED: 'Ask the operator to repair authentication for the named repository and rerun readiness.',
  NETWORK_FAILED: 'Check connectivity to the provider and rerun readiness.',
  ACCESS_UNKNOWN: 'Ask the operator to verify repository read access; an ambiguous denial cannot prove readiness.',
  PROVIDER_RESULT_INVALID: 'Check the named client output and repository identity locally, then rerun readiness.',
  PROBE_TIMEOUT: 'Check the named probe locally and rerun readiness with an appropriate bounded timeout.',
};
class Refusal extends Error {
  constructor(code, operation, status = 3) { super(code); Object.assign(this, { code, operation, status }); }
}
function invalid(operation = 'identity') { throw new Refusal('IDENTITY_INVALID', operation, 2); }
function text(v) { return typeof v === 'string' && v.trim() === v && v.length > 0 && !/[\x00-\x1f\x7f]/.test(v); }
function parseArgs() {
  const opts = { timeout: 10000 }; const seen = new Set();
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    const key = args[i];
    if (seen.has(key)) invalid('input'); seen.add(key);
    if (key === '--json') continue;
    if (key !== '--input' && key !== '--timeout-ms') invalid('input');
    const value = args[++i]; if (!text(value)) invalid('input');
    if (key === '--input') opts.input = value;
    else { if (!/^\d+$/.test(value) || Number(value) < 100 || Number(value) > 60000) invalid('input'); opts.timeout = Number(value); }
  }
  if (!opts.input || !seen.has('--json')) invalid('input');
  return opts;
}

// Official MSI/ZIP launcher templates (2026-10-07):
// https://github.com/Azure/azure-cli/blob/dev/build_scripts/windows/scripts/az_msi.cmd
// https://github.com/Azure/azure-cli/blob/dev/build_scripts/windows/scripts/az_zip.cmd
// Read the recognized wrapper, never execute batch text or construct shell args.
export function azureWindowsLauncher(wrapper) {
  const lines = fs.readFileSync(wrapper, 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/)
    .map(line => line.trim()).filter(line => line && !line.startsWith('::'));
  const patterns = [/^@IF EXIST "%~dp0\\\.\.\\python\.exe" \($/i,
    /^SET AZ_INSTALLER=(MSI|ZIP)$/i, /^"%~dp0\\\.\.\\python\.exe" -IBm azure\.cli %\*$/i,
    /^\) ELSE \($/i, /^echo Failed to load python executable\.$/i, /^exit \/b 1$/i, /^\)$/];
  if (lines.length !== patterns.length || lines.some((line, i) => !patterns[i].test(line)))
    throw new Refusal('ACCESS_UNKNOWN', 'az.launcher');
  const python = path.resolve(path.dirname(wrapper), '..', 'python.exe');
  if (!fs.statSync(python).isFile()) throw new Refusal('CLIENT_MISSING', 'az.launcher');
  return { bin: python, prefix: ['-IBm', 'azure.cli'], installer: lines[1].split('=')[1].toUpperCase() };
}
function windowsAzure(env) {
  // Select the same PATH order as a normal client lookup, without shell lookup.
  for (const dir of (env.PATH || env.Path || '').split(path.delimiter).filter(Boolean)) {
    for (const extension of ['.exe', '.cmd']) {
      const candidate = path.join(dir.replace(/^"|"$/g, ''), 'az' + extension);
      if (fs.existsSync(candidate)) return extension === '.cmd' ? azureWindowsLauncher(candidate) : { bin: candidate, prefix: [] };
    }
  }
  return { bin: 'az', prefix: [] };
}

// shell:false throughout. POSIX starts a process group so a timed-out probe's
// descendants are terminated too. Windows taskkill /T /F targets the process
// tree by numeric pid; no provider argument enters a command string.
function probe(bin, args, { cwd, env, timeout, operation, provider = true }) {
  env = { ...env, GIT_TERMINAL_PROMPT: '0', GH_PROMPT_DISABLED: '1' };
  return new Promise((resolve, reject) => {
    const stdout = [], stderr = [];
    let bytes = 0, refusal = null;
    let child;
    try { child = spawn(bin, args, { cwd, env, shell: false, windowsHide: true,
      detached: process.platform !== 'win32', stdio: ['ignore', 'pipe', 'pipe'] }); }
    catch { reject(new Refusal(provider ? 'CLIENT_MISSING' : 'IDENTITY_INVALID', operation, provider ? 3 : 2)); return; }
    let timer, killTimer, treeKill;
    const terminate = () => {
      if (!child.pid) return;
      if (process.platform === 'win32') {
        const taskkill = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'taskkill.exe');
        treeKill = spawn(taskkill, ['/PID', String(child.pid), '/T', '/F'], { shell: false, windowsHide: true, stdio: 'ignore' });
        treeKill.on('error', () => child.kill());
        // Bounded fallback if taskkill itself is unavailable or stalls.
        killTimer = setTimeout(() => { treeKill.kill(); child.kill(); }, 500);
      } else {
        try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
      }
    };
    timer = setTimeout(() => { refusal = new Refusal('PROBE_TIMEOUT', operation, 124); terminate(); }, timeout);
    const read = (key, chunk) => {
      bytes += chunk.length;
      if (bytes > LIMIT) { if (!refusal) refusal = new Refusal('PROVIDER_RESULT_INVALID', operation); terminate(); return; }
      // Decode after close so a multibyte character split between pipe events survives.
      (key === 'out' ? stdout : stderr).push(chunk);
    };
    child.stdout.on('data', chunk => read('out', chunk)); child.stderr.on('data', chunk => read('err', chunk));
    child.on('error', err => { clearTimeout(timer); clearTimeout(killTimer);
      reject(new Refusal(provider ? (err.code === 'ENOENT' ? 'CLIENT_MISSING' : 'ACCESS_UNKNOWN') : 'IDENTITY_INVALID', operation, provider ? 3 : 2)); });
    child.on('close', code => { clearTimeout(timer); clearTimeout(killTimer);
      if (refusal) reject(refusal); else resolve({ code, stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8') }); });
  });
}
function remoteParts(remote) {
  let parts;
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(remote)) {
    const url = new URL(sanitize(remote));
    if (!['https:', 'ssh:'].includes(url.protocol) || url.search || url.hash || url.port) invalid();
    parts = url.pathname.split('/').slice(1);
  } else {
    const match = remote.match(/^(?:[^@/:]+@)?[^:/]+:(.+)$/); if (!match) invalid();
    parts = match[1].split('/');
  }
  return parts.map(part => {
    let decoded; try { decoded = decodeURIComponent(part); } catch { invalid(); }
    if (!text(decoded) || /[\/\\]/.test(decoded) || decoded === '.' || decoded === '..') invalid();
    return decoded;
  });
}
function azureIdentity(remote) {
  const host = extractHost(remote), p = remoteParts(remote);
  let org, project, repository;
  if (host === 'dev.azure.com' && p.length === 4 && p[2] === '_git') [org, project, , repository] = p;
  else if ((host === 'ssh.dev.azure.com' || host === 'vs-ssh.visualstudio.com') && p.length === 4 && p[0] === 'v3') [, org, project, repository] = p;
  else if (host?.endsWith('.visualstudio.com') && p.length === 3 && p[1] === '_git') { org = host.slice(0, -'.visualstudio.com'.length); [project, , repository] = p; }
  else if (host?.endsWith('.visualstudio.com') && p.length === 4 && p[0] === 'DefaultCollection' && p[2] === '_git') { org = host.slice(0, -'.visualstudio.com'.length); [, project, , repository] = p; }
  else invalid();
  return { organization_url: 'https://dev.azure.com/' + encodeURIComponent(org), project, repository };
}
function organization(value) {
  let url; try { url = new URL(value); } catch { invalid(); }
  if (url.protocol !== 'https:' || url.username || url.password || url.port || url.search || url.hash) invalid();
  const parts = url.pathname.replace(/\/$/, '').split('/').filter(Boolean);
  if (url.hostname === 'dev.azure.com' && parts.length === 1) return 'https://dev.azure.com/' + encodeURIComponent(decodeURIComponent(parts[0]));
  if (url.hostname.endsWith('.visualstudio.com') && (parts.length === 0 || parts.length === 1 && parts[0] === 'DefaultCollection')) return 'https://dev.azure.com/' + encodeURIComponent(url.hostname.slice(0,-'.visualstudio.com'.length));
  invalid();
}
async function identity(input, opts) {
  if (!input || Array.isArray(input) || typeof input !== 'object') invalid('input');
  const allowed = new Set(['schema_version','repo_root','remote_name','source_branch','target_branch','organization_url','project','repository']);
  if (Object.keys(input).some(key => !allowed.has(key)) || input.schema_version !== 1) invalid('input');
  for (const key of ['repo_root','source_branch','target_branch']) if (!text(input[key])) invalid('input');
  if (!path.isAbsolute(input.repo_root) || !fs.statSync(input.repo_root).isDirectory()) invalid();
  let gitLineTerminator;
  const local = async args => {
    const r = await probe('git', ['-C', input.repo_root, ...args], { cwd: input.repo_root, env: process.env, timeout: opts.timeout, operation: 'git.identity', provider: false });
    if (r.code !== 0) invalid();
    // Calibrate from rev-parse before URL data: a URL's trailing CR is not a CRLF delimiter.
    if (gitLineTerminator === undefined) gitLineTerminator = r.stdout.endsWith('\r\n') ? '\r\n' : '\n';
    return r.stdout.endsWith(gitLineTerminator) ? r.stdout.slice(0, -gitLineTerminator.length) : r.stdout;
  };
  const actualRoot = await local(['rev-parse','--show-toplevel']);
  if (fs.realpathSync(actualRoot) !== fs.realpathSync(input.repo_root)) invalid();
  const branch = await local(['symbolic-ref','--quiet','--short','HEAD']);
  await local(['check-ref-format','--branch',input.source_branch]); await local(['check-ref-format','--branch',input.target_branch]);
  if (branch !== input.source_branch || input.source_branch === input.target_branch) invalid();
  // A null remote is explicit local-only intent, never a missing-remote guess.
  let remote = null;
  if (input.remote_name !== null) {
    if (!text(input.remote_name) || input.remote_name.startsWith('-')) invalid();
    const fetch = (await local(['remote','get-url','--all','--',input.remote_name])).split(/\r?\n/);
    const push = (await local(['remote','get-url','--push','--all','--',input.remote_name])).split(/\r?\n/);
    // get-url expands insteadOf/pushInsteadOf. Conservative endpoint equality
    // keeps the provider read bound to the repository a later named-remote push uses.
    if (fetch.length !== 1 || push.length !== 1 || !text(fetch[0]) ||
        /^\s|\s$|[\r\n]/.test(fetch[0]) || /^\s|\s$|[\r\n]/.test(push[0]) || fetch[0] !== push[0])
      invalid('git.push-destination');
    remote = fetch[0];
  }
  result.platform = remote === null ? 'none' : classify(extractHost(remote));
  const host = extractHost(remote);
  if (result.platform === 'azure') {
    for (const key of ['organization_url','project','repository']) if (!text(input[key])) invalid();
    const resolved = azureIdentity(remote);
    if (resolved.organization_url.toLowerCase() !== organization(input.organization_url).toLowerCase() || resolved.project !== input.project || resolved.repository !== input.repository) invalid();
    result.repository = { ...resolved, organization_url: organization(input.organization_url) };
  } else if (result.platform === 'github') {
    const parts = remoteParts(remote); if (parts.length !== 2) invalid();
    const repository = parts[0] + '/' + parts[1].replace(/\.git$/, '');
    if (!text(input.repository) || input.repository !== repository || input.organization_url !== undefined || input.project !== undefined) invalid();
    result.repository = { host, repository };
  } else {
    if (['organization_url','project','repository'].some(key => input[key] !== undefined)) invalid();
    // Generic identity is display-only: credentials and URL query/fragment never leave this boundary.
    let safeRemote = remote === null ? null : sanitize(remote).split(/[?#]/, 1)[0];
    result.repository = remote === null ? null : { remote: safeRemote };
  }
  Object.assign(result, { remote_name: input.remote_name, source_branch: branch, target_branch: input.target_branch, head_sha: await local(['rev-parse','--verify','HEAD']) });
}
function parseRecord(raw, operation) {
  try { const value = JSON.parse(raw); if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(); return value; }
  catch { throw new Refusal('PROVIDER_RESULT_INVALID', operation); }
}
function failure(r, operation) {
  // Only known signals are named; denied/not-found/other failures stay unknown.
  const msg = (r.stderr + '\n' + r.stdout).toLowerCase();
  if (/authentication failed|not logged in|login required|please run .*(?:az login|gh auth login)|unauthorized|expired.*(?:token|credential)/.test(msg)) throw new Refusal('AUTH_FAILED', operation);
  if (/connection timed out|dns resolution failed|could not resolve host|name resolution|connection refused|network is unreachable/.test(msg)) throw new Refusal('NETWORK_FAILED', operation);
  throw new Refusal('ACCESS_UNKNOWN', operation);
}
async function readiness(input, opts) {
  const invoke = (bin,args,operation) => {
    const env = {...process.env,AZURE_EXTENSION_USE_DYNAMIC_INSTALL:'no',AZURE_CORE_NO_COLOR:'true',GH_HOST:result.repository?.host};
    if (bin === 'az' && process.platform === 'win32') {
      let launcher; try { launcher = windowsAzure(env); } catch (err) { if (err instanceof Refusal) throw err; throw new Refusal('CLIENT_MISSING','az.launcher'); }
      if (launcher.installer) env.AZ_INSTALLER = launcher.installer;
      return probe(launcher.bin,[...launcher.prefix,...args],{cwd:input.repo_root,env,timeout:opts.timeout,operation});
    }
    return probe(bin,args,{cwd:input.repo_root,env,timeout:opts.timeout,operation});
  };
  if (result.platform === 'azure') {
    let r = await invoke('az',['--version'],'az.version'); if (r.code !== 0) failure(r,'az.version');
    r = await invoke('az',['extension','show','--name','azure-devops','--output','json','--only-show-errors'],'az.extension');
    if (r.code !== 0) throw new Refusal('EXTENSION_MISSING','az.extension');
    let extension; try { extension = parseRecord(r.stdout,'az.extension'); } catch { throw new Refusal('EXTENSION_MISSING','az.extension'); }
    if (extension.name !== 'azure-devops' || !text(extension.version)) throw new Refusal('EXTENSION_MISSING','az.extension');
    const wanted = result.repository;
    r = await invoke('az',['repos','show','--organization',wanted.organization_url,'--project',wanted.project,'--repository',wanted.repository,'--detect','false','--output','json','--only-show-errors'],'az.repository');
    if (r.code !== 0) failure(r,'az.repository');
    const repo = parseRecord(r.stdout,'az.repository');
    let matches = false;
    try { const observed = azureIdentity(repo.remoteUrl); matches = observed.organization_url.toLowerCase() === wanted.organization_url.toLowerCase() && observed.project === wanted.project && observed.repository === wanted.repository; } catch { /* fail closed */ }
    if (repo.name !== wanted.repository || repo.project?.name !== wanted.project || !matches) throw new Refusal('PROVIDER_RESULT_INVALID','az.repository');
  } else if (result.platform === 'github') {
    let r = await invoke('gh',['--version'],'gh.version'); if (r.code !== 0) failure(r,'gh.version');
    r = await invoke('gh',['auth','status','--hostname',result.repository.host],'gh.authentication'); if (r.code !== 0) failure(r,'gh.authentication');
    r = await invoke('gh',['repo','view',result.repository.repository,'--json','nameWithOwner,url'],'gh.repository'); if (r.code !== 0) failure(r,'gh.repository');
    const repo = parseRecord(r.stdout,'gh.repository');
    let url; try { url = new URL(repo.url); } catch { throw new Refusal('PROVIDER_RESULT_INVALID','gh.repository'); }
    if (repo.nameWithOwner !== result.repository.repository || url.protocol !== 'https:' || url.host !== result.repository.host || url.pathname !== '/' + result.repository.repository || url.username || url.password || url.search || url.hash) throw new Refusal('PROVIDER_RESULT_INVALID','gh.repository');
  } else {
    Object.assign(result,{outcome:'capability_not_applicable',code:'CAPABILITY_NOT_APPLICABLE',operation:'generic',remedy:'GENERIC MODE: automated provider PR and reviewer checks are unavailable; use the existing local/manual ceremony route.'});return;
  }
  Object.assign(result,{outcome:'read_verified',code:'READ_VERIFIED',operation:result.platform + '.readiness',remedy:'Repository read access verified at invocation time; future PR create permission remains unknown.'});
}
async function main() {
try {
  const opts = parseArgs(); let input;
  try { input = JSON.parse(fs.readFileSync(opts.input,'utf8')); } catch { invalid('input'); }
  await identity(input,opts); await readiness(input,opts);
  console.log(JSON.stringify(result));
} catch (err) {
  const refusal = err instanceof Refusal ? err : new Refusal('IDENTITY_INVALID','input',2);
  Object.assign(result,{outcome:'refused',code:refusal.code,operation:refusal.operation,remedy:remedies[refusal.code]});
  console.log(JSON.stringify(result)); console.error('pr-preflight: ' + refusal.code + ' (' + refusal.operation + '): ' + result.remedy);
  process.exitCode = refusal.status;
}

}
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) await main();
