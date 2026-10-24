#!/usr/bin/env node
// expert-fetch.mjs - fetch and cache expert subagent prompts from the pinned
// registry commit (RFC-0017 phase 3, spec-node-first-third-slice). One module
// owns the registry parser, detection, phase eligibility, the cache and the two
// security filters; expert-fetch.sh and expert-fetch.ps1 are thin launchers.
// Exit codes: 0 success, 1 rejected or error, 2 key not found. It never reads
// standard input and writes only under <root>/.aai/cache/experts/.
import { existsSync, mkdirSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

export const DEFAULT_MAX_BYTES = 8192;
const BOM = String.fromCharCode(0xfeff);
const CR = String.fromCharCode(13);
const STRIP_FLAGS = 'i';
const NOT_FOUND = 2;
const DETECT_EMPTY_CODE = 0;
const GH_TIMEOUT_MS = 60000;
const USAGE = [
  'Usage: expert-fetch.sh <expert-key> [--force]', '       expert-fetch.sh --detect <ext|tech>...',
  '       expert-fetch.sh --body <expert-key>', '       expert-fetch.sh --list', '       expert-fetch.sh --check <key> <phase>',
].join('\n') + '\n';
const INJECTION = [/ignore.*previous/i, /disregard.*instruction/i, /you are now/i, /forget.*above/i, /override.*system/i];
const DANGEROUS = 'git push|git reset --hard|rm -rf|force.push|--no-verify';
const TABLE = new Map();
for (const [key, tokens] of [
  ['typescript', 'ts tsx typescript'], ['javascript', 'js jsx javascript'], ['python', 'py python'], ['rails', 'rb ruby rails'],
  ['rust', 'rs rust'], ['golang', 'go golang'], ['java', 'java'], ['csharp', 'cs csharp'], ['swift', 'swift'], ['kotlin', 'kt kotlin'],
  ['flutter', 'dart flutter'], ['php', 'php'], ['elixir', 'ex exs elixir'], ['cpp', 'cpp cc cxx hpp c++'], ['sql', 'sql psql'],
  ['powershell', 'ps1 powershell'], ['graphql', 'graphql gql'], ['vue', 'vue'], ['react', 'react'], ['angular', 'angular'],
  ['nextjs', 'next nextjs'], ['django', 'django'], ['laravel', 'laravel'], ['spring', 'spring'], ['dotnet', 'dotnet'],
  ['docker', 'docker dockerfile'], ['kubernetes', 'k8s kubernetes'], ['terraform', 'terraform tf hcl'], ['postgres', 'postgres postgresql'],
  ['security', 'security owasp'], ['performance', 'performance perf'], ['accessibility', 'accessibility a11y'], ['electron', 'electron'],
  ['websocket', 'websocket ws'], ['blockchain', 'blockchain web3'], ['gamedev', 'gamedev game'], ['iot', 'iot'], ['embedded', 'embedded'],
  ['fintech', 'fintech'], ['payment', 'payment stripe'], ['seo', 'seo'], ['slack', 'slack'], ['mcp', 'mcp'], ['azure', 'azure'],
  ['cloud', 'aws gcp cloud'],
]) for (const t of tokens.split(' ')) TABLE.set(t, key);

const indentOf = (line) => (line.trim() === '' ? 0 : line.length - line.trimStart().length);
const blockEnd = (line) => indentOf(line) <= 2;
const unquote = (v) => v.replace(/\s+#.*$/, '').trim().replace(/^"(.*)"$/, '$1');

export function parseRegistry(text) {
  const lines = (text.startsWith(BOM) ? text.slice(BOM.length) : text).split('\n').map((l) => (l.endsWith(CR) ? l.slice(0, -1) : l));
  const scalar = (name) => {
    for (const l of lines) { const m = new RegExp('^\\s*' + name + ':\\s*(.*)$').exec(l); if (m) return unquote(m[1]); }
    return null;
  };
  const keys = [];
  const experts = new Map();
  lines.forEach((l, i) => {
    const m = /^ {2}([a-z][a-z0-9_-]*):\s*$/.exec(l);
    if (!m) return;
    keys.push(m[1]);
    const ex = { path: undefined, useIn: undefined };
    for (let j = i + 1; j < lines.length && !blockEnd(lines[j]); j++) {
      const p = /^\s+path:\s*(.+?)\s*$/.exec(lines[j]);
      const u = /^\s+use_in:(.*)$/.exec(lines[j]);
      if (p && ex.path === undefined) ex.path = p[1];
      if (u && ex.useIn === undefined) ex.useIn = u[1];
    }
    experts.set(m[1], ex);
  });
  const blocked = [];
  const unq = (v) => v.replace(/#.*$/, '').trim().replace(/^(["'])(.*)\1$/, '$2');
  let emptyFlow = false;
  const heads = lines.flatMap((l, i) => (l.startsWith('blocked_categories:') ? [i] : []));
  for (const at of heads) {
    const flow = /^\[(.*)\]\s*(#.*)?$/.exec(lines[at].slice('blocked_categories:'.length).trim());
    if (flow) { emptyFlow ||= flow[1].trim() === ''; blocked.push(...flow[1].split(',').map(unq).filter(Boolean)); continue; }
    for (let i = at + 1; i < lines.length && /^(\s|#|$)/.test(lines[i]); i++) {
      const item = /^\s+-\s+(.*)$/.exec(lines[i]);
      if (item && unq(item[1])) blocked.push(unq(item[1]));
    }
  }
  const max = /^\d+$/.exec(scalar('max_prompt_bytes') ?? '');
  return {
    repo: scalar('repo'), pinnedSha: scalar('pinned_sha'), basePath: scalar('base_path'),
    maxBytes: max ? Number(max[0]) : DEFAULT_MAX_BYTES, blocked, blockedBroken: heads.length > 0 && blocked.length === 0 && !emptyFlow, keys, experts,
  };
}

export function detect(tokens, reg) {
  const found = new Set();
  for (const raw of tokens) {
    const t = raw.toLowerCase().replace(/^\./, '');
    if (TABLE.has(t)) found.add(TABLE.get(t));
    else if (reg.keys.includes(t)) found.add(t);
  }
  const list = [...found].sort().slice(0, 2);
  return { code: list.length ? 0 : DETECT_EMPTY_CODE, out: list.map((k) => k + '\n').join('') };
}

export function checkPhase(reg, key, phase) {
  if (!key || !phase) return { code: 1, out: '', err: 'Usage: expert-fetch.sh --check <expert-key> <phase>\n' };
  const ex = reg.experts.get(key);
  if (!ex || ex.useIn === undefined) return { code: NOT_FOUND, out: 'not-found\n', err: '' };
  return ex.useIn.includes(phase) ? { code: 0, out: 'eligible\n', err: '' } : { code: 1, out: 'not-eligible\n', err: '' };
}

export function stripFrontmatter(raw) {
  const text = raw.startsWith(BOM) ? raw.slice(BOM.length) : raw;
  const lines = text.split('\n');
  const dash = (l) => (l.endsWith(CR) ? l.slice(0, -1) : l) === '---';
  const close = dash(lines[0]) ? lines.findIndex((l, i) => i > 0 && dash(l)) : -1;
  const body = lines.slice(close + 1);
  const joined = body.join('\n');
  return joined.endsWith('\n') ? joined : joined + '\n';
}

export function sanitize(text, maxBytes) {
  const size = Buffer.byteLength(text, 'utf8');
  if (size > maxBytes) return { ok: false, text: '', error: 'REJECTED: Expert prompt too large (' + size + ' > ' + maxBytes + ' bytes)' };
  const lines = text.split('\n');
  if (INJECTION.some((re) => lines.some((l) => re.test(l)))) {
    return { ok: false, text: '', error: 'REJECTED: Expert prompt contains injection patterns' };
  }
  const drop = new RegExp(DANGEROUS, STRIP_FLAGS);
  return { ok: true, text: lines.filter((l) => !drop.test(l)).join('\n'), error: '' };
}

const readText = (file) => {
  const text = readFileSync(file, 'utf8');
  return text.startsWith(BOM) ? text.slice(BOM.length) : text;
};
const cacheFiles = (root, key) => {
  const dir = path.join(root, '.aai', 'cache', 'experts');
  return { dir, file: path.join(dir, key + '.md'), sha: path.join(dir, '.sha_' + key) };
};
export function blockedRefusal(reg, key) {
  if (reg.blockedBroken) return { code: 1, out: '', err: 'ERROR: blocked_categories in the registry has no readable item; refusing to serve experts\n' };
  const category = (reg.experts.get(key)?.path ?? '').split('/')[0];
  const blocked = reg.blocked.includes(category);
  return blocked ? { code: 1, out: '', err: "ERROR: Category '" + category + "' is blocked in registry\n" } : null;
}

export function fetchExpert({ root, reg, key, force, runGh }) {
  const ex = reg.experts.get(key);
  if (!ex || !ex.path) return { code: NOT_FOUND, out: '', err: "ERROR: Expert '" + key + "' not found in registry\n" };
  const refused = blockedRefusal(reg, key);
  if (refused) return refused;
  const { dir: cacheDir, file: cacheFile, sha: shaFile } = cacheFiles(root, key);
  if (!force && existsSync(cacheFile) && existsSync(shaFile) && readText(shaFile).trim() === reg.pinnedSha) {
    return { code: 0, out: cacheFile + '\n', err: '' };
  }
  const full = reg.basePath + '/' + ex.path;
  const failed = { code: 1, out: '', err: 'ERROR: Failed to fetch ' + full + ' at SHA ' + reg.pinnedSha + '\n' };
  const r = runGh(['api', 'repos/' + reg.repo + '/contents/' + full + '?ref=' + reg.pinnedSha, '--jq', '.content']) || {};
  const ghOk = r.status === 0 && !r.error;
  const out = String(r.stdout ?? '').replace(/\s+/g, '');
  if (!ghOk || out === '' || out.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(out)) return failed;
  const decoded = Buffer.from(out, 'base64').toString('utf8');
  if (decoded === '') return failed;
  const clean = sanitize(decoded, reg.maxBytes);
  if (!clean.ok) return { code: 1, out: '', err: clean.error + '\n' };
  const tmp = path.join(cacheDir, '.tmp_' + key + '_' + process.pid);
  try {
    mkdirSync(cacheDir, { recursive: true });
    writeFileSync(tmp, clean.text, 'utf8');
    renameSync(tmp, cacheFile);
    writeFileSync(shaFile, reg.pinnedSha, 'utf8');
  } catch (e) {
    try { rmSync(tmp, { force: true }); } catch { /* best effort */ } return { code: 1, out: '', err: 'ERROR: Cannot write the cache under ' + cacheDir + ': ' + e.code + '\n' };
  }
  return { code: 0, out: cacheFile + '\n', err: '' };
}

const realDir = () => path.dirname(realpathSync(fileURLToPath(import.meta.url)));
const spawnGh = (env) => (args) => {
  const bin = env.AAI_GH_BIN || 'gh';
  return spawnSync(bin, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: GH_TIMEOUT_MS, killSignal: 'SIGKILL', maxBuffer: 1 << 24 });
};

export function main({ argv, root, env = process.env, stdout = process.stdout, stderr = process.stderr, runGh } = {}) {
  const emit = (r) => { if (r.out) stdout.write(r.out); if (r.err) stderr.write(r.err); return r.code; };
  if (argv.length === 0) return emit({ code: 1, out: '', err: USAGE });
  const base = root ?? path.resolve(realDir(), '..', '..');
  const registry = path.join(base, '.aai', 'system', 'EXPERT_REGISTRY.yaml');
  if (!existsSync(registry)) return emit({ code: 1, out: '', err: 'ERROR: Registry not found at ' + registry + '\n' });
  const reg = parseRegistry(readText(registry));
  const [mode, ...rest] = argv;
  if (mode === '--list') return emit({ code: 0, out: reg.keys.map((k) => k + '\n').join(''), err: '' });
  if (mode === '--detect') return emit(detect(rest, reg));
  if (mode === '--check') return emit(checkPhase(reg, rest[0], rest[1]));
  if (mode === '--body') {
    const key = rest[0] ?? '';
    const c = cacheFiles(base, key);
    if (!/^[a-z][a-z0-9_-]*$/.test(key) || !existsSync(c.file)) {
      return emit({ code: 1, out: '', err: "ERROR: Expert '" + key + "' not cached. Run expert-fetch.sh " + key + ' first.\n' });
    }
    return emit(blockedRefusal(reg, key) ?? { code: 0, out: stripFrontmatter(readText(c.file)), err: '' });
  }
  if (!reg.pinnedSha || !reg.repo) return emit({ code: 1, out: '', err: 'ERROR: Invalid registry - missing pinned_sha or repo\n' });
  const force = rest.includes('--force');
  return emit(fetchExpert({ root: base, reg, key: mode === '--force' ? (rest.find((a) => a !== '--force') ?? '') : mode, force: force || mode === '--force', runGh: runGh ?? spawnGh(env) }));
}

const realOrResolve = (p) => { try { return realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  process.exitCode = main({ argv: process.argv.slice(2) });
}
