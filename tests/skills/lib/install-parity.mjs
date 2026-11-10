#!/usr/bin/env node
// install-parity.mjs - run the bash and PowerShell twins of aai-sync, aai-update and the hook installer into
// scratch targets, diff what each leaves behind, apply the documented normalizations and the reviewed allowlist
// (docs/specs/SPEC-DRAFT-install-path-parity-harness.md, D-DRIVER .. D-FU). Test-only: nothing under .aai/ or
// hooks/ is changed. Node stdlib only. Importing this module runs nothing; `main` is the CLI.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(HERE, '../../..');
export const defaultTwinNames = () => Object.keys(TWINS);
export function defaultScratchBase({ platform = process.platform, env = process.env, tmpdir = os.tmpdir(), usable = (d) => { try { fs.accessSync(d, fs.constants.W_OK); return fs.statSync(d).isDirectory(); } catch { return false; } } } = {}) {
  if (env.AAI_PARITY_SCRATCH) return env.AAI_PARITY_SCRATCH;
  // The PowerShell twin is about ten times slower with its source tree under a macOS $TMPDIR (/var/folders/...).
  if (platform === 'darwin' && usable('/tmp')) return '/tmp';
  return tmpdir;
}
export const DEFAULT_ALLOWLIST = path.join(HERE, 'install-parity-allowlist.tsv');

export const PINNED_TZ = 'Etc/GMT-3';
export const KINDS = ['exit', 'missing', 'bytes', 'lines', 'order', 'mode'];
export const MODE_MEANINGFUL = process.platform !== 'win32';
export const REFERENCE_TWIN = 'sh';
export const NAME_MUST_MATCH_STAMP = true;
const HOSTS = ['any', 'posix', 'win32', 'utc', 'non-utc'];
const STEP_TIMEOUT_MS = 300000;

// ---------------------------------------------------------------------------------------------------------------
// D-NORM: the complete list of normalizations and exclusions. Nothing else rewrites a byte or a name.
export const NORMALIZATIONS = [
  { id: 'N1', what: 'AAI_PIN.md sync time (second precision only)', reason: 'wall clock' },
  { id: 'N2', what: 'sync-conflicts report Generated-at line (second precision only)', reason: 'wall clock' },
  { id: 'N3', what: 'sync-conflicts report name stamp, only when it equals the report Generated-at second in UTC',
    reason: 'wall clock; the agreement condition keeps a time-zone divergence visible' },
  { id: 'N4', what: 'doctor report name stamp and host', reason: 'wall clock and host name' },
  { id: 'E1', what: 'everything under .git/ except, for hooks scenarios, the regular non-sample files of .git/hooks/',
    reason: 'the object store and index are git output, sample hooks are git own' },
  { id: 'E2', what: 'content of a doctor report renamed by N4 (presence stays compared)',
    reason: 'written by the shared update-doctor-report.mjs, holds host and clock' },
];

// ---------------------------------------------------------------------------------------------------------------
// D-MATRIX: scenarios. smoke is a subset of default, which is a subset of full; each tier lists its own rows.
const T0 = (op, profile, flags, expect) => ({ op, profile, flags, expect });
const AAI_PIN = '.aai/system/AAI_PIN.md';
const HK3 = ['.git/hooks/pre-commit', '.git/hooks/reference-transaction', '.git/hooks/pre-push'];
export const SCENARIOS = [
  { id: 'SY-01', tier: 'smoke', op: 'sync', setup: 'empty', target: 'target with space',
    steps: [T0('sync', 'core', [], '0')], probes: [AAI_PIN, '.gitignore'] },
  { id: 'SY-02', tier: 'default', op: 'sync', setup: 'empty',
    steps: [T0('sync', 'extended', [], '0'), T0('sync', null, [], '0')], probes: [AAI_PIN, '.codex/skills/README.md'] },
  { id: 'SY-03', tier: 'default', op: 'sync', setup: 'crlf-gitignore',
    steps: [T0('sync', 'core', [], '0')], probes: ['.gitignore'] },
  { id: 'SY-04', tier: 'default', op: 'sync', setup: 'hooks-json',
    steps: [T0('sync', 'core', [], '0')], probes: ['hooks/hooks.json'] },
  { id: 'SY-05', tier: 'full', op: 'sync', setup: 'empty',
    steps: [T0('sync', 'extended', [], '0')], probes: [AAI_PIN] },
  { id: 'SY-06', tier: 'full', op: 'sync', setup: 'empty',
    steps: [T0('sync', 'extended', [], '0'), T0('sync', 'core', [], '0')], probes: [AAI_PIN] },
  { id: 'SY-07', tier: 'full', op: 'sync', setup: 'older-core',
    steps: [T0('sync', 'core', [], '0')], probes: [AAI_PIN] },
  { id: 'UP-01', tier: 'smoke', op: 'update', setup: 'older-core',
    steps: [T0('update', null, [], '0')], probes: [AAI_PIN] },
  { id: 'UP-02', tier: 'full', op: 'update', setup: 'empty',
    steps: [T0('update', null, [], '0')], probes: [AAI_PIN] },
  { id: 'UP-03', tier: 'full', op: 'update', setup: 'older-extended',
    steps: [T0('update', null, [], '0')], probes: [AAI_PIN] },
  { id: 'HK-01', tier: 'smoke', op: 'hooks', setup: 'base',
    steps: [T0('hooks', null, [], '0')], probes: HK3 },
  { id: 'HK-02', tier: 'default', op: 'hooks', setup: 'base',
    steps: [T0('hooks', null, [], '0'), T0('hooks', null, [], '0')], probes: ['.git/hooks/pre-commit'] },
  { id: 'HK-03', tier: 'smoke', op: 'hooks', setup: 'base-foreign-hook',
    steps: [T0('hooks', null, [], 'nonzero')], probes: ['.git/hooks/pre-commit'] },
  { id: 'HK-04', tier: 'default', op: 'hooks', setup: 'base-foreign-hook',
    steps: [T0('hooks', null, ['force'], '0')], probes: ['.git/hooks/pre-commit'] },
  { id: 'HK-05', tier: 'smoke', op: 'hooks', setup: 'base-preguard',
    steps: [T0('hooks', null, [], '0')], probes: ['.git/hooks/pre-commit'] },
  { id: 'HK-06', tier: 'default', op: 'hooks', setup: 'base-hookspath',
    steps: [T0('hooks', null, [], '0')], probes: ['.githooks/pre-commit'] },
  { id: 'HK-07', tier: 'smoke', op: 'hooks', setup: 'base-declined',
    steps: [T0('hooks', null, [], '0')], probes: ['.git/hooks/pre-commit'] },
  { id: 'HK-08', tier: 'default', op: 'hooks', setup: 'base',
    steps: [T0('hooks', null, ['decline-ref-guard'], '0')], probes: ['docs/ai/docs-audit.yaml'] },
  { id: 'HK-09', tier: 'default', op: 'hooks', setup: 'base',
    steps: [T0('hooks', null, [], '0'), T0('hooks', null, ['uninstall'], '0')], probes: ['docs/ai/docs-audit.yaml'] },
  { id: 'HK-10', tier: 'smoke', op: 'hooks', setup: 'base', target: 'target with space',
    steps: [T0('hooks', null, [], '0')], probes: ['.git/hooks/pre-commit'] },
];
export const TIERS = ['smoke', 'default', 'full'];

export function listMatrix(tier) {
  const rank = TIERS.indexOf(tier);
  if (rank < 0) throw new Error(`unknown matrix tier: ${tier} (smoke, default or full)`);
  return SCENARIOS.filter((s) => TIERS.indexOf(s.tier) <= rank).map((s) => s.id);
}

// ---------------------------------------------------------------------------------------------------------------
// D-SEAM: the twin registry. A twin is { name, argv(step, ctx) } returning { file, args, cwd }.
const fwd = (p) => String(p).replace(/\\/g, '/');
const SH_FLAG = { force: '--force', uninstall: '--uninstall', 'decline-ref-guard': '--decline-ref-guard' };
const PS_FLAG = { force: '-Force', uninstall: '-Uninstall', 'decline-ref-guard': '-DeclineRefGuard' };
const psHead = (ctx) => ['-NoProfile', '-NonInteractive', ...(process.platform === 'win32' ? ['-ExecutionPolicy', 'Bypass'] : []), '-File'];

export const TWINS = {
  sh: {
    name: 'sh',
    argv(step, ctx) {
      const src = fwd(ctx.src); const target = fwd(ctx.target);
      if (step.op === 'sync') {
        return { file: ctx.bash, args: [`${src}/.aai/scripts/aai-sync.sh`, target, ...(step.profile ? ['--profile', step.profile] : [])], cwd: ctx.target };
      }
      if (step.op === 'update') {
        return { file: ctx.bash, args: [`${src}/.aai/scripts/aai-update.sh`, '--repo', src, '--ref', 'main'], cwd: ctx.target };
      }
      return { file: ctx.bash, args: ['.aai/scripts/install-pre-commit-hook.sh', ...(step.flags || []).map((f) => SH_FLAG[f])], cwd: ctx.target };
    },
  },
  ps1: {
    name: 'ps1',
    argv(step, ctx) {
      const src = fwd(ctx.src);
      if (step.op === 'sync') {
        return { file: ctx.ps, args: [...psHead(ctx), `${src}/.aai/scripts/aai-sync.ps1`, '-TargetRoot', ctx.target, ...(step.profile ? ['-Profile', step.profile] : [])], cwd: ctx.target };
      }
      if (step.op === 'update') {
        return { file: ctx.ps, args: [...psHead(ctx), `${src}/.aai/scripts/aai-update.ps1`, '-Repo', ctx.src, '-Ref', 'main'], cwd: ctx.target };
      }
      return { file: ctx.ps, args: [...psHead(ctx), '.aai/scripts/install-pre-commit-hook.ps1', ...(step.flags || []).map((f) => PS_FLAG[f])], cwd: ctx.target };
    },
  },
};

export async function loadTwinModule(name, file, registered) {
  if (!/^[a-z0-9-]+$/.test(name)) throw new Error(`--twin-module name ${name} must match [a-z0-9-]+`);
  if (registered.includes(name)) throw new Error(`--twin-module name ${name} clashes with a registered twin`);
  const mod = await import(pathToFileURL(path.resolve(file)).href);
  const def = mod.default;
  if (!def || typeof def.argv !== 'function') throw new Error(`twin module ${file}: the default export needs an argv(step, ctx) function`);
  return { name, argv: (step, ctx) => def.argv(step, ctx) };
}

// ---------------------------------------------------------------------------------------------------------------
// D-ENV: the twins' environment.
export function twinEnv(root, base = process.env) {
  const env = {};
  for (const [k, v] of Object.entries(base)) if (!k.startsWith('AAI_') && v !== undefined) env[k] = v;
  const tmp = path.join(root, 'tmp');
  env.TZ = PINNED_TZ;
  env.GIT_CONFIG_NOSYSTEM = '1';
  env.GIT_CONFIG_GLOBAL = path.join(root, 'gitconfig');
  env.TMPDIR = tmp; env.TMP = tmp; env.TEMP = tmp;
  return env;
}

export function hostInfo() {
  const win = process.platform === 'win32';
  return { platform: win ? 'win32' : 'posix', utc: win ? new Date().getTimezoneOffset() === 0 : false };
}
const hostMatches = (want, host) => want === 'any' || want === host.platform || (want === 'utc' && host.utc) || (want === 'non-utc' && !host.utc);

// ---------------------------------------------------------------------------------------------------------------
// D-SNAP: snapshot, normalization, comparison.
const isText = (buf) => {
  if (buf.includes(0)) return false;
  try { new TextDecoder('utf-8', { fatal: true }).decode(buf); return true; } catch { return false; }
};

// E1 is applied while walking so the object store is never read.
export function snapshot(dir, { hooks = false } = {}) {
  const out = new Map();
  const walk = (rel) => {
    const abs = rel ? path.join(dir, ...rel.split('/')) : dir;
    for (const name of fs.readdirSync(abs).sort()) {
      const r = rel ? `${rel}/${name}` : name;
      const st = fs.lstatSync(path.join(abs, name));
      const inGit = r === '.git' || r.startsWith('.git/');
      if (inGit) {
        if (!hooks) continue;
        if (r === '.git' || r === '.git/hooks') { walk(r); continue; }
        if (!r.startsWith('.git/hooks/') || !st.isFile() || r.endsWith('.sample')) continue;
      }
      if (st.isSymbolicLink()) out.set(r, { kind: 'symlink', target: fs.readlinkSync(path.join(abs, name)) });
      else if (st.isDirectory()) { if (!inGit) { out.set(r, { kind: 'dir' }); } walk(r); }
      else if (st.isFile()) out.set(r, { kind: 'file', data: fs.readFileSync(path.join(abs, name)), exec: (st.mode & 0o111) !== 0 });
    }
  };
  walk('');
  return out;
}

const STAMP_LINE = (label) => new RegExp(`^(- ${label} \\(UTC\\): )\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ(\\r?)$`);
const GEN_LINE = /^- Generated at \(UTC\): (\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?Z\r?$/;
const rewriteLines = (data, label) => {
  const re = STAMP_LINE(label);
  const text = data.toString('utf8');
  return Buffer.from(text.split('\n').map((l) => l.replace(re, '$1<stamp>$2')).join('\n'), 'utf8');
};

export function normalizeSnapshot(snap) {
  const out = new Map();
  const conflicts = []; const doctors = [];
  for (const [p, e] of snap) {
    let entry = e;
    if (e.kind === 'file' && isText(e.data)) {
      if (p === '.aai/system/AAI_PIN.md') entry = { ...e, data: rewriteLines(e.data, 'Synced at') };
      else if (/^docs\/ai\/reports\/sync-conflicts-[^/]+\.md$/.test(p)) entry = { ...e, data: rewriteLines(e.data, 'Generated at') };
    }
    const mc = /^docs\/ai\/reports\/sync-conflicts-(\d{8}-\d{6})\.md$/.exec(p);
    if (mc && e.kind === 'file') {
      const g = e.data.toString('utf8').split('\n').map((l) => GEN_LINE.exec(l)).find(Boolean);
      const stamp = g ? `${g[1]}${g[2]}${g[3]}-${g[4]}${g[5]}${g[6]}` : null;
      // A name that disagrees with the report's own Generated-at second is paired by ordinal as well, so the report
      // content is compared; the disagreement itself survives as a flag that compareSnapshots reports (a time-zone
      // divergence stays visible, apart from the content).
      conflicts.push([p, NAME_MUST_MATCH_STAMP && stamp !== mc[1] ? { ...entry, nameSkew: true } : entry]);
      continue;
    }
    if (/^docs\/ai\/reports\/doctor-\d{8}T\d{6}Z-[^/]+\.md$/.test(p) && e.kind === 'file') { doctors.push([p, { ...e, data: Buffer.alloc(0) }]); continue; }
    out.set(p, entry);
  }
  conflicts.sort((x, y) => (x[0] < y[0] ? -1 : 1)).forEach(([, entry], i) => out.set(`docs/ai/reports/sync-conflicts-<stamp-${i + 1}>.md`, entry));
  doctors.sort((x, y) => (x[0] < y[0] ? -1 : 1)).forEach(([, entry], i) => out.set(`docs/ai/reports/doctor-<stamp-${i + 1}>.md`, entry));
  return out;
}

export const snapshotNormalized = (dir, opts) => normalizeSnapshot(snapshot(dir, opts));

const sha = (b) => crypto.createHash('sha256').update(b).digest('hex').slice(0, 12);
const countLines = (lines) => { const m = new Map(); for (const l of lines) m.set(l, (m.get(l) || 0) + 1); return m; };
const surplus = (a, b) => { const out = []; for (const [l, n] of a) for (let i = 0; i < n - (b.get(l) || 0); i += 1) out.push(l); return out; };

export function compareSnapshots(a, b, pair, labels = null) {
  const [A, B] = labels || pair.split(':');
  const out = [];
  for (const p of [...new Set([...a.keys(), ...b.keys()])].sort()) {
    const x = a.get(p); const y = b.get(p);
    if (!x || !y) { out.push({ pair, path: p, kind: 'missing', detail: `present only in ${x ? A : B} (${(x || y).kind})` }); continue; }
    if (x.kind !== y.kind) { out.push({ pair, path: p, kind: 'missing', detail: `${A} has a ${x.kind}, ${B} has a ${y.kind}` }); continue; }
    if (x.kind === 'symlink') {
      if (x.target !== y.target) out.push({ pair, path: p, kind: 'bytes', detail: `symlink target ${A} ${x.target} / ${B} ${y.target}` });
      continue;
    }
    if (x.kind !== 'file') continue;
    if (Boolean(x.nameSkew) !== Boolean(y.nameSkew)) {
      out.push({ pair, path: `${p}#name`, kind: 'missing', detail: `the report name stamp disagrees with its Generated-at line in ${x.nameSkew ? A : B} only` });
    }
    if (!x.data.equals(y.data)) {
      if (isText(x.data) && isText(y.data)) {
        const la = x.data.toString('utf8').split('\n'); const lb = y.data.toString('utf8').split('\n');
        const onlyA = surplus(countLines(la), countLines(lb)); const onlyB = surplus(countLines(lb), countLines(la));
        if (onlyA.length === 0 && onlyB.length === 0) out.push({ pair, path: p, kind: 'order', detail: 'same lines in a different order' });
        else {
          const show = (ls) => ls.slice(0, 3).map((l) => JSON.stringify(l)).join(', ') + (ls.length > 3 ? `, +${ls.length - 3} more` : '');
          out.push({ pair, path: p, kind: 'lines', detail: `only in ${A}: [${show(onlyA)}] only in ${B}: [${show(onlyB)}]`, onlyA, onlyB });
        }
      } else out.push({ pair, path: p, kind: 'bytes', detail: `binary content differs (sha256 ${A} ${sha(x.data)} / ${B} ${sha(y.data)})` });
    }
    if (MODE_MEANINGFUL && x.exec !== y.exec) out.push({ pair, path: p, kind: 'mode', detail: `executable bit ${A} ${x.exec} / ${B} ${y.exec}` });
  }
  return out;
}

export function compareExits(pair, exitsA, exitsB) {
  const [A, B] = pair.split(':');
  const out = [];
  const n = Math.max(exitsA.length, exitsB.length);
  for (let i = 0; i < n; i += 1) {
    if (exitsA[i] !== exitsB[i]) out.push({ pair, path: `step${i + 1}`, kind: 'exit', detail: `exit ${A} ${exitsA[i]} / ${B} ${exitsB[i]}` });
  }
  return out;
}

export function compareTrees(dirA, dirB, { pair = 'a:b', hooks = false, exits = null } = {}) {
  const out = exits ? compareExits(pair, exits.a || [], exits.b || []) : [];
  return out.concat(compareSnapshots(snapshotNormalized(dirA, { hooks }), snapshotNormalized(dirB, { hooks }), pair));
}

// ---------------------------------------------------------------------------------------------------------------
// D-ALLOW: the allowlist.
export class AllowlistError extends Error {
  constructor(row, field, msg) { super(`allowlist row ${row}: field ${field}: ${msg}`); this.row = row; this.field = field; }
}
const FIELDS = ['id', 'pairs', 'scenario', 'path', 'kind', 'host', 'tracker', 'match', 'reason'];

export function parseAllowlist(text, { twins = null } = {}) {
  const rows = []; const seen = new Set();
  text.split('\n').forEach((raw, i) => {
    const line = raw.replace(/\r$/, '');
    if (!line.trim() || line.startsWith('#')) return;
    const f = line.split('\t');
    const id = f[0] || `line-${i + 1}`;
    if (f.length !== 9) throw new AllowlistError(id, 'fields', `expected 9 TAB-separated fields, found ${f.length}`);
    const r = Object.fromEntries(FIELDS.map((k, n) => [k, f[n]]));
    if (!/^[a-z0-9-]+$/.test(r.id)) throw new AllowlistError(r.id, 'id', 'must match [a-z0-9-]+');
    if (seen.has(r.id)) throw new AllowlistError(r.id, 'id', 'duplicate id');
    seen.add(r.id);
    r.pairList = r.pairs.split(',');
    for (const pr of r.pairList) {
      if (!/^[a-z0-9-]+:[a-z0-9-]+$/.test(pr)) throw new AllowlistError(r.id, 'pairs', `${pr} is not a:b`);
      if (twins) for (const t of pr.split(':')) if (!twins.includes(t)) throw new AllowlistError(r.id, 'pairs', `${pr} names twin ${t} that is not registered`);
    }
    if (r.scenario !== '*' && !r.scenario.split(',').every((s) => /^[A-Za-z0-9-]+$/.test(s))) throw new AllowlistError(r.id, 'scenario', `${r.scenario} is neither * nor a list of ids`);
    if (!r.path) throw new AllowlistError(r.id, 'path', 'empty');
    if (!KINDS.includes(r.kind)) throw new AllowlistError(r.id, 'kind', `${r.kind} is not one of ${KINDS.join(', ')}`);
    if (!HOSTS.includes(r.host)) throw new AllowlistError(r.id, 'host', `${r.host} is not one of ${HOSTS.join(', ')}`);
    if (r.tracker !== 'accepted' && !/^fu-\S+$/.test(r.tracker)) throw new AllowlistError(r.id, 'tracker', `${r.tracker} is neither accepted nor a fu- id`);
    if (r.kind === 'lines' && r.match === '-') throw new AllowlistError(r.id, 'match', 'a lines row needs a regular expression (- would cover every line of its path)');
    if (r.match !== '-') {
      // A leading = marks a paired row: capture group 1 of every line it covers must be the same multiset on both sides.
      r.paired = r.match.startsWith('=');
      try { r.re = new RegExp(r.paired ? r.match.slice(1) : r.match); } catch (e) { throw new AllowlistError(r.id, 'match', `does not compile: ${e.message}`); }
      if (r.paired && new RegExp(`${r.re.source}|`).exec('').length < 2) throw new AllowlistError(r.id, 'match', 'a paired row (leading =) needs a capture group');
    }
    if (!r.reason.trim()) throw new AllowlistError(r.id, 'reason', 'empty');
    r.globRe = new RegExp(`^${r.path.split('**').map((seg) => seg.split('*').map((s) => s.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('[^/]*')).join('.*')}$`);
    rows.push(r);
  });
  return rows;
}

const scenarioMatches = (row, id) => row.scenario === '*' || row.scenario.split(',').includes(id);

export function applyAllowlist(divergences, rows, { scenario, host }) {
  const covered = []; const uncovered = []; const used = new Set(); const usedPairs = new Set();
  for (const d of divergences) {
    const matching = rows.filter((r) => r.pairList.includes(d.pair) && scenarioMatches(r, scenario) && r.globRe.test(d.path)
      && r.kind === d.kind && hostMatches(r.host, host));
    let by = [];
    if (d.kind !== 'lines') by = matching.slice(0, 1);
    else {
      // Every differing line needs a row whose regex matches it; a row that matched any line has covered it. A paired
      // row also needs the captured values of its lines to be the same on both sides.
      const sides = [d.onlyA || [], d.onlyB || []];
      const hit = new Set(); const caps = new Map();
      let ok = true;
      sides.forEach((ls, side) => {
        for (const l of ls) {
          const r = matching.find((m) => m.re.test(l));
          if (!r) { ok = false; continue; }
          hit.add(r.id);
          if (r.paired) { const c = caps.get(r.id) || [[], []]; c[side].push(String(r.re.exec(l)[1])); caps.set(r.id, c); }
        }
      });
      for (const [, [a, b]] of caps) if (a.slice().sort().join('\0') !== b.slice().sort().join('\0')) ok = false;
      if (ok) by = matching.filter((m) => hit.has(m.id));
    }
    if (by.length) { for (const r of by) { used.add(r.id); usedPairs.add(`${r.id}|${d.pair}`); } covered.push({ ...d, covered_by: by.map((r) => r.id).join(',') }); } else uncovered.push({ ...d, covered_by: null });
  }
  return { covered, uncovered, used, usedPairs };
}

// A row-pair is stale when this whole-tier run executed a scenario the row names, on a host it names, for that pair,
// and the row covered nothing of that pair. usedPairs holds `<row id>|<pair>`; without it a used row counts for all
// its pairs. pairsByScenario (scenario id to the pairs it ran) narrows "the pair ran" to the scenarios the row names.
function staleRows(rows, { ran, pairsRun, host, used, usedPairs = null, pairsByScenario = null, wholeTier }) {
  const stale = [];
  if (wholeTier) {
    for (const r of rows) {
      const named = r.scenario === '*' ? ran : r.scenario.split(',').filter((s) => ran.includes(s));
      if (!named.length || !hostMatches(r.host, host)) continue;
      for (const pair of r.pairList) {
        const pairRan = pairsByScenario ? named.some((s) => (pairsByScenario[s] || []).includes(pair)) : pairsRun.includes(pair);
        const isUsed = usedPairs ? usedPairs.has(`${r.id}|${pair}`) : used.has(r.id);
        if (pairRan && !isUsed) stale.push({ ...r, pair });
      }
    }
  }
  return stale;
}
export { staleRows };

// ---------------------------------------------------------------------------------------------------------------
// D-FU: trackers resolve in the follow-up registry.
export function loadFollowUps(root = REPO_ROOT) {
  const r = spawnSync(process.execPath, [path.join(root, '.aai/scripts/follow-ups.mjs'), 'list', '--status', 'all', '--json'], { cwd: root, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`follow-ups.mjs list failed: ${r.stderr}`);
  return JSON.parse(r.stdout).items;
}
export function trackerProblems(rows, known) {
  const byId = new Map(known.map((f) => [f.id, f]));
  const out = [];
  for (const r of rows) {
    if (r.tracker === 'accepted') continue;
    const f = byId.get(r.tracker);
    if (!f) { out.push(`row ${r.id}: tracker ${r.tracker} is not in the follow-up registry`); continue; }
    const stem = r.path.split('*')[0];
    if (stem && !String(f.source || '').includes(stem)) out.push(`row ${r.id}: the source of ${r.tracker} does not name ${stem}`);
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Process helpers.
export function expectMet(expect, code) { return expect === 'nonzero' ? code !== 0 : code === 0; }

// One bounded child. The child runs under a small supervisor (own process group on POSIX); on expiry the supervisor kills
// the whole group (taskkill /T on Windows) and exits 124, so a hung twin leaves no process behind.
const SUPERVISOR = `
const { spawn, spawnSync } = require('node:child_process');
const [file, ...args] = JSON.parse(process.argv[1]);
const ms = Number(process.argv[2]);
const win = process.platform === 'win32';
const c = spawn(file, args, { stdio: ['ignore', 'inherit', 'inherit'], detached: !win });
let done = false;
const timer = setTimeout(() => {
  if (done) return;
  done = true;
  if (win) spawnSync('taskkill', ['/PID', String(c.pid), '/T', '/F'], { stdio: 'ignore' });
  else { try { process.kill(-c.pid, 'SIGKILL'); } catch { try { c.kill('SIGKILL'); } catch {} } }
  process.stderr.write('install-parity: step exceeded ' + ms + ' ms and was killed with its process group\\n');
  process.exit(124);
}, ms);
c.on('error', (e) => { if (done) return; done = true; clearTimeout(timer); process.stderr.write(String(e.message) + '\\n'); process.exit(e.code === 'ENOENT' ? 127 : 1); });
c.on('close', (code, signal) => {
  if (done) return;
  done = true; clearTimeout(timer);
  if (!win && !signal) { try { process.kill(-c.pid, 'SIGKILL'); } catch {} }
  process.exit(code === null ? 124 : code);
});
`;

export function runStep(file, args, { cwd, env, timeoutMs = STEP_TIMEOUT_MS }) {
  const r = spawnSync(process.execPath, ['-e', SUPERVISOR, JSON.stringify([file, ...args]), String(timeoutMs)], { cwd, env, encoding: 'utf8', timeout: timeoutMs + 15000, killSignal: 'SIGKILL', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 });
  let code = r.status;
  if (r.error) code = r.error.code === 'ETIMEDOUT' ? 124 : (r.error.code === 'ENOENT' ? 127 : 1);
  if (code === null || code === undefined) code = r.signal ? 124 : 1;
  return { code, stdout: r.stdout || '', stderr: (r.stderr || '') + (r.error ? `\n${r.error.message}` : '') };
}
const run = runStep;
const sleepMs = (ms) => { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); };
const waitNextSecond = () => sleepMs(1000 - (Date.now() % 1000) + 25);

// ---------------------------------------------------------------------------------------------------------------
// D-FIX: fixtures, built once per run and copied per twin.
function prepareRoot(root) {
  fs.mkdirSync(path.join(root, 'tmp'), { recursive: true });
  const gc = path.join(root, 'gitconfig');
  if (!fs.existsSync(gc)) fs.writeFileSync(gc, '');
}
const gitIn = (ctx, cwd, ...args) => {
  const r = run('git', args, { cwd, env: twinEnv(ctx.root) });
  if (r.code !== 0) throw new Error(`git ${args.join(' ')} failed in ${cwd}: ${r.stderr}`);
  return r.stdout;
};
function initRepo(ctx, dir) {
  fs.mkdirSync(dir, { recursive: true });
  gitIn(ctx, dir, 'init', '-q');
  gitIn(ctx, dir, 'symbolic-ref', 'HEAD', 'refs/heads/main');
  gitIn(ctx, dir, 'config', 'user.email', 'parity@example.invalid');
  gitIn(ctx, dir, 'config', 'user.name', 'parity');
  gitIn(ctx, dir, 'config', 'commit.gpgsign', 'false');
}
const commitAll = (ctx, dir, msg) => { gitIn(ctx, dir, 'add', '-A', '-f'); gitIn(ctx, dir, 'commit', '-q', '--no-verify', '-m', msg); };
const copyTree = (from, to) => { fs.mkdirSync(path.dirname(to), { recursive: true }); fs.cpSync(from, to, { recursive: true, verbatimSymlinks: true }); };

const SOURCE_NOTE = 'NOTE: the scratch source leaves out tests/** and docs/** (except docs/knowledge/** and docs/ai/AAI_VERSION.md)';

// F1 CURRENT SOURCE: every tracked path of the checkout (working-tree bytes) except tests/** and most of docs/**.
export function buildSource(ctx) {
  const dir = path.join(ctx.root, 'fx', 'src');
  const ls = run('git', ['ls-files', '-z'], { cwd: REPO_ROOT, env: twinEnv(ctx.root) });
  if (ls.code !== 0) throw new Error(`git ls-files failed: ${ls.stderr}`);
  for (const rel of ls.stdout.split('\0').filter(Boolean)) {
    if (rel.startsWith('tests/')) continue;
    if (rel.startsWith('docs/') && !rel.startsWith('docs/knowledge/') && rel !== 'docs/ai/AAI_VERSION.md') continue;
    const from = path.join(REPO_ROOT, rel); const to = path.join(dir, rel);
    let st;
    try { st = fs.lstatSync(from); } catch { continue; }
    if (st.isDirectory()) continue;
    fs.mkdirSync(path.dirname(to), { recursive: true });
    if (st.isSymbolicLink()) fs.symlinkSync(fs.readlinkSync(from), to); else fs.copyFileSync(from, to);
  }
  initRepo(ctx, dir);
  commitAll(ctx, dir, 'src');
  ctx.notes = (ctx.notes || []).concat(SOURCE_NOTE);
  return dir;
}

function syncWithSh(ctx, srcDir, target, profile) {
  const r = run(ctx.bash, [`${fwd(srcDir)}/.aai/scripts/aai-sync.sh`, fwd(target), '--profile', profile], { cwd: target, env: twinEnv(ctx.root) });
  if (r.code !== 0) throw new Error(`fixture sync (${profile}) failed with ${r.code}: ${r.stderr.slice(-400)}`);
}

// F2 OLDER SOURCE.
function buildOlderSource(ctx) {
  const dir = path.join(ctx.root, 'fx', 'src-older');
  if (fs.existsSync(dir)) return dir;
  copyTree(ctx.src, dir);
  const ver = path.join(dir, 'docs/ai/AAI_VERSION.md');
  fs.writeFileSync(ver, fs.readFileSync(ver, 'utf8').replace(/^- Version: .*$/m, '- Version: v2026.01.01'));
  const prof = path.join(dir, '.aai/system/PROFILES.yaml');
  const lines = fs.readFileSync(prof, 'utf8').split('\n');
  const core = lines.findIndex((l) => /^core:\s*$/.test(l));
  let drop = -1;
  for (let i = core + 1; i < lines.length && /^\s*(-|#|$)/.test(lines[i]); i += 1) {
    const m = /^  - (\.aai\/templates\/\S+)$/.exec(lines[i]);
    if (m && fs.existsSync(path.join(dir, m[1])) && fs.lstatSync(path.join(dir, m[1])).isFile()) { drop = i; break; }
  }
  if (drop < 0) throw new Error('F2: no removable core template entry found in PROFILES.yaml');
  fs.rmSync(path.join(dir, lines[drop].slice(4)));
  lines.splice(drop, 1);
  fs.writeFileSync(prof, lines.join('\n'));
  fs.appendFileSync(path.join(dir, '.aai/AGENTS.md'), '\n<!-- parity: older source -->\n');
  commitAll(ctx, dir, 'older');
  return dir;
}

const RETIRED_WRAPPER = [
  '---', 'name: aai-retired-parity', 'description: parity fixture', '---',
  'Read the file `.aai/SKILL_RETIREDPARITY.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-retired-parity`.',
  'If `.aai/SKILL_RETIREDPARITY.prompt.md` does not exist, say: "SKILL_RETIREDPARITY not found \u2014 are you in an AAI project? Expected: .aai/SKILL_RETIREDPARITY.prompt.md"', '',
].join('\n');
const put = (dir, rel, content, mode) => {
  const p = path.join(dir, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
  if (mode) fs.chmodSync(p, mode);
};

// F3 OLDER-CORE and OLDER-EXTENDED installs.
function fixtureOlder(ctx, profile) {
  const dir = path.join(ctx.root, 'fx', `older-${profile}`);
  if (fs.existsSync(dir)) return dir;
  const older = buildOlderSource(ctx);
  initRepo(ctx, dir);
  syncWithSh(ctx, older, dir, profile);
  put(dir, 'ai/legacy.md', 'legacy ai\n');
  put(dir, 'scripts/aai-sync.sh', '#!/bin/sh\n');
  put(dir, 'docs/ai/PRICING.yaml', 'legacy: true\n');
  put(dir, '.claude/skills/aai-retired-parity/SKILL.md', RETIRED_WRAPPER);
  put(dir, '.aai/scripts/project-local.sh', '#!/bin/sh\necho project local\n', 0o755);
  return dir;
}

// F4 INSTALLED-BASE.
function fixtureBase(ctx) {
  const dir = path.join(ctx.root, 'fx', 'base');
  if (fs.existsSync(dir)) return dir;
  initRepo(ctx, dir);
  syncWithSh(ctx, ctx.src, dir, 'core');
  return dir;
}

export function defaultSetup(scenario, target, ctx) {
  const kind = scenario.setup;
  fs.rmSync(target, { recursive: true, force: true });
  if (kind === 'older-core' || kind === 'older-extended') { copyTree(fixtureOlder(ctx, kind.slice(6)), target); return; }
  if (kind.startsWith('base')) {
    copyTree(fixtureBase(ctx), target);
    if (kind === 'base-foreign-hook') put(target, '.git/hooks/pre-commit', '#!/bin/sh\necho foreign\n', 0o755);
    else if (kind === 'base-preguard') put(target, '.git/hooks/pre-commit', fs.readFileSync(path.join(ctx.src, '.aai/templates/git-hooks/pre-commit-index.sh')), 0o755);
    else if (kind === 'base-hookspath') gitIn(ctx, target, 'config', 'core.hooksPath', '.githooks');
    else if (kind === 'base-declined') put(target, 'docs/ai/docs-audit.yaml', 'ref_guard: declined\n');
    return;
  }
  initRepo(ctx, target);
  if (kind === 'crlf-gitignore') put(target, '.gitignore', ['node_modules/', '.env', '.aai/', '.aai/cache/', '.aai/', '.aai/cache/', ''].join('\r\n'));
  else if (kind === 'hooks-json') {
    put(target, 'hooks/hooks.json', `${JSON.stringify({ hooks: { PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'echo user-hook' }] }] } }, null, 2)}\n`);
    put(target, 'hooks/session-start.sh', '#!/usr/bin/env bash\necho project edited\n', 0o755);
  } else if (kind !== 'empty') throw new Error(`unknown scenario setup: ${kind}`);
}

// ---------------------------------------------------------------------------------------------------------------
// The runner.
function runScenario(scenario, twins, ctx) {
  const t0 = Date.now();
  const targetDir = path.join(ctx.root, scenario.id, scenario.target || 'target');
  const hooks = scenario.op === 'hooks';
  const results = []; const broken = []; const steps = [];
  for (const twin of twins) {
    fs.rmSync(targetDir, { recursive: true, force: true });
    fs.mkdirSync(path.dirname(targetDir), { recursive: true });
    (ctx.setup || defaultSetup)(scenario, targetDir, ctx, twin.name);
    const codes = []; const snaps = [];
    scenario.steps.forEach((step, i) => {
      const a = twin.argv({ ...step, index: i }, { src: ctx.src, target: targetDir, bash: ctx.bash, ps: ctx.ps });
      const r = run(a.file, a.args, { cwd: a.cwd || targetDir, env: twinEnv(ctx.root) });
      codes.push(r.code);
      steps.push({ twin: twin.name, step: i + 1, code: r.code, ...(r.code !== 0 ? { stderr_tail: r.stderr.slice(-300) } : {}) });
      if (scenario.steps.length > 1) snaps.push(snapshotNormalized(targetDir, { hooks }));
      if (i < scenario.steps.length - 1 && step.op !== 'hooks') waitNextSecond();
    });
    const missing = scenario.probes.filter((p) => !fs.existsSync(path.join(targetDir, ...p.split('/'))));
    for (const p of missing) broken.push(`probe ${p} is missing from the ${twin.name} tree`);
    const final = scenario.steps.length > 1 ? snaps[snaps.length - 1] : snapshotNormalized(targetDir, { hooks });
    results.push({ twin, codes, first: snaps[0] || final, final });
    try { fs.renameSync(targetDir, path.join(path.dirname(targetDir), `out-${twin.name}`)); } catch { fs.rmSync(targetDir, { recursive: true, force: true }); }
  }
  const refResult = results.find((r) => r.twin.name === REFERENCE_TWIN) || results[0];
  scenario.steps.forEach((step, i) => {
    const ref = { code: refResult.codes[i] };
    if (!expectMet(step.expect, ref.code)) broken.push(`step ${i + 1} on the reference twin ${refResult.twin.name} exited ${ref.code}, expected ${step.expect}`);
  });
  const divergences = []; const pairs = [];
  for (let i = 0; i < twins.length; i += 1) {
    for (let j = i + 1; j < twins.length; j += 1) {
      const pair = `${results[i].twin.name}:${results[j].twin.name}`;
      pairs.push(pair);
      divergences.push(...compareExits(pair, results[i].codes, results[j].codes), ...compareSnapshots(results[i].final, results[j].final, pair));
    }
  }
  if (scenario.steps.length > 1) {
    for (const r of results) {
      const pair = `${r.twin.name}:${r.twin.name}`;
      pairs.push(pair);
      divergences.push(...compareSnapshots(r.first, r.final, pair, ['step 1', 'step 2']));
    }
  }
  return { id: scenario.id, seconds: Math.round((Date.now() - t0) / 100) / 10, steps, broken, divergences, pairs };
}

export function runMatrix({ scenarios, twins, rows = [], ctx, matrix = 'default', filtered = false }) {
  const t0 = Date.now();
  const c = { ...ctx };
  fs.mkdirSync(c.root, { recursive: true });
  prepareRoot(c.root);
  if (!c.src && !c.setup) c.src = buildSource(c);
  const host = c.host || hostInfo();
  const report = { verdict: 'PASS', host: host.platform, tz: PINNED_TZ, matrix, twins: twins.map((t) => t.name), pairs: [], total_seconds: 0, scenarios: [], uncovered: [], stale: [] };
  const used = new Set(); const usedPairs = new Set(); const pairsByScenario = {}; const pairSet = []; const ran = [];
  for (const s of scenarios) {
    const r = runScenario(s, twins, c);
    ran.push(s.id);
    const { covered, uncovered, used: u, usedPairs: up } = applyAllowlist(r.divergences, rows, { scenario: s.id, host });
    for (const id of u) used.add(id);
    for (const k of up) usedPairs.add(k);
    pairsByScenario[s.id] = r.pairs;
    for (const p of r.pairs) if (!pairSet.includes(p)) pairSet.push(p);
    report.scenarios.push({ id: r.id, seconds: r.seconds, steps: r.steps, broken: r.broken, divergences: [...covered, ...uncovered].map((d) => ({ pair: d.pair, path: d.path, kind: d.kind, detail: d.detail, covered_by: d.covered_by })) });
    for (const d of uncovered) report.uncovered.push({ scenario: s.id, pair: d.pair, path: d.path, kind: d.kind, detail: d.detail });
  }
  report.pairs = [...pairSet.filter((p) => p.split(':')[0] !== p.split(':')[1]), ...pairSet.filter((p) => p.split(':')[0] === p.split(':')[1])];
  report.stale = staleRows(rows, { ran, pairsRun: report.pairs, host, used, usedPairs, pairsByScenario, wholeTier: !filtered }).map((r) => ({ id: r.id, scenario: r.scenario, pairs: r.pair, path: r.path, kind: r.kind }));
  report.stale_check = filtered ? 'off (scenario filter)' : 'on';
  report.notes = c.notes || [];
  report.total_seconds = Math.round((Date.now() - t0) / 100) / 10;
  if (report.uncovered.length || report.stale.length || report.scenarios.some((s) => s.broken.length)) report.verdict = 'FAIL';
  return report;
}

// ---------------------------------------------------------------------------------------------------------------
// CLI.
const USAGE = `usage: install-parity.mjs list --matrix <smoke|default|full> [--json]
       install-parity.mjs run --matrix <tier> [--scenario <id>]... [--twins <names>; default: every registered twin] [--twin-module <name>=<path>]...
                          [--allowlist <tsv>] [--bash <path>] [--ps <path>] [--json <file>] [--keep]`;
class UsageError extends Error {}

const toolOk = (file, args) => { const r = run(file, args, { cwd: process.cwd(), env: process.env }); return r.code === 0; };

export async function main(argv) {
  const err = (m) => process.stderr.write(`${m}\n`);
  const [cmd, ...rest] = argv;
  try {
    if (cmd !== 'list' && cmd !== 'run') throw new UsageError(cmd ? `unknown command: ${cmd}` : 'missing command');
    return await dispatch(cmd, rest, err);
  } catch (e) {
    if (e instanceof UsageError) { err(`install-parity: ${e.message}\n${USAGE}`); return 2; }
    throw e;
  }
}

async function dispatch(cmd, rest, err) {
  const o = parseArgsFor(cmd, rest);
  if (!o.matrix || !TIERS.includes(o.matrix)) throw new UsageError(`--matrix must be one of ${TIERS.join(', ')}`);
  if (cmd === 'list') {
    const ids = listMatrix(o.matrix);
    process.stdout.write(o.listJson ? `${JSON.stringify(ids)}\n` : `${ids.join('\n')}\n`);
    return 0;
  }
  const twinNames = o.twins === null ? defaultTwinNames() : o.twins.split(',').filter(Boolean);
  for (const n of twinNames) if (!TWINS[n]) throw new UsageError(`unknown twin ${n} (registered: ${Object.keys(TWINS).join(', ')})`);
  let scenarios = SCENARIOS.filter((s) => listMatrix(o.matrix).includes(s.id));
  if (o.scenario.length) {
    for (const id of o.scenario) if (!scenarios.some((s) => s.id === id)) throw new UsageError(`scenario ${id} is not in the ${o.matrix} matrix`);
    scenarios = scenarios.filter((s) => o.scenario.includes(s.id));
  }
  const twins = twinNames.map((n) => TWINS[n]);
  for (const spec of o.twinModule) {
    const eq = spec.indexOf('=');
    if (eq < 1) throw new UsageError(`--twin-module wants <name>=<path>, got ${spec}`);
    try { twins.push(await loadTwinModule(spec.slice(0, eq), spec.slice(eq + 1), [...Object.keys(TWINS), ...twins.map((t) => t.name)])); } catch (e) { throw new UsageError(e.message); }
  }
  const registered = [...new Set([...Object.keys(TWINS), ...twins.map((t) => t.name)])];
  let rows;
  try { rows = parseAllowlist(fs.readFileSync(o.allowlist, 'utf8'), { twins: registered }); } catch (e) {
    if (e instanceof AllowlistError) { err(`install-parity: ${e.message}`); return 2; }
    throw new UsageError(`cannot read the allowlist ${o.allowlist}: ${e.message}`);
  }
  const missing = [];
  if (!toolOk('git', ['--version'])) missing.push('git');
  if (!toolOk(o.bash, ['--version'])) missing.push(`bash (${o.bash})`);
  if (twinNames.includes('ps1') && !toolOk(o.ps, ['-NoProfile', '-NonInteractive', '-Command', 'exit 0'])) missing.push(`pwsh (${o.ps})`);
  if (missing.length) { err(`install-parity: missing tool: ${missing.join(', ')}`); return 3; }
  const root = fs.realpathSync(fs.mkdtempSync(path.join(defaultScratchBase(), 'aai-parity-run-')));
  let rep;
  try {
    rep = runMatrix({ scenarios, twins, rows, matrix: o.matrix, filtered: o.scenario.length > 0, ctx: { root, src: null, bash: o.bash, ps: o.ps, host: hostInfo() } });
  } finally {
    if (o.keep) process.stdout.write(`scratch root kept: ${root}\n`); else fs.rmSync(root, { recursive: true, force: true });
  }
  for (const n of rep.notes) process.stdout.write(`${n}\n`);
  for (const s of rep.scenarios) {
    const verdict = s.broken.length ? 'BROKEN' : (s.divergences.some((d) => !d.covered_by) ? 'FAIL' : 'PASS');
    process.stdout.write(`${s.id} ${s.seconds}s ${verdict}\n`);
    for (const b of s.broken) process.stdout.write(`  BROKEN ${s.id}: ${b}\n`);
    for (const st of s.steps) if (st.stderr_tail && s.broken.length) process.stdout.write(`  ${s.id} ${st.twin} step ${st.step} exit ${st.code}: ${st.stderr_tail.replace(/\s+/g, ' ')}\n`);
  }
  for (const u of rep.uncovered) process.stdout.write(`UNCOVERED ${u.scenario} ${u.pair} ${u.kind} ${u.path}: ${u.detail}\n`);
  for (const s of rep.stale) process.stdout.write(`STALE ${s.id} (scenario ${s.scenario}, pairs ${s.pairs}, ${s.kind} ${s.path})\n`);
  if (rep.stale_check !== 'on') process.stdout.write(`stale check: ${rep.stale_check}\n`);
  process.stdout.write(`verdict ${rep.verdict} (${rep.total_seconds}s, matrix ${rep.matrix}, pairs ${rep.pairs.join(' ')})\n`);
  if (o.json) fs.writeFileSync(o.json, `${JSON.stringify(rep, null, 2)}\n`);
  return rep.verdict === 'PASS' ? 0 : 1;
}

// --json takes a file for `run` and is a flag for `list`.
function parseArgsFor(cmd, rest) {
  const a = rest.slice();
  const o = { scenario: [], twinModule: [], twins: null, bash: 'bash', ps: 'pwsh', allowlist: DEFAULT_ALLOWLIST, json: null, keep: false, listJson: false, matrix: null };
  const val = (i, flag) => { if (i + 1 >= a.length) throw new UsageError(`${flag} needs a value`); return a[i + 1]; };
  for (let i = 0; i < a.length; i += 1) {
    const f = a[i];
    if (f === '--matrix') { o.matrix = val(i, f); i += 1; }
    else if (f === '--scenario') { o.scenario.push(val(i, f)); i += 1; }
    else if (f === '--twins') { o.twins = val(i, f); i += 1; }
    else if (f === '--twin-module') { o.twinModule.push(val(i, f)); i += 1; }
    else if (f === '--allowlist') { o.allowlist = val(i, f); i += 1; }
    else if (f === '--bash') { o.bash = val(i, f); i += 1; }
    else if (f === '--ps') { o.ps = val(i, f); i += 1; }
    else if (f === '--json') { if (cmd === 'run') { o.json = val(i, f); i += 1; } else o.listJson = true; }
    else if (f === '--keep') o.keep = true;
    else throw new UsageError(`unknown argument: ${f}`);
  }
  return o;
}

const isMain = (() => { try { return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } })();
if (isMain) {
  main(process.argv.slice(2)).then((code) => { process.exitCode = code; }, (e) => { process.stderr.write(`install-parity: ${e && e.stack ? e.stack : e}\n`); process.exitCode = 1; });
}
