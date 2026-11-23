#!/usr/bin/env node
// install-parity.mjs - run the bash and PowerShell twins of aai-sync, aai-update and the hook installer into
// scratch targets, diff what each leaves behind, apply the documented normalizations and the reviewed allowlist
// (docs/specs/SPEC-0284-spec-install-path-parity-harness.md, D-DRIVER .. D-FU). Test-only: nothing under .aai/ or
// hooks/ is changed. Node stdlib only. Importing this module runs nothing; `main` is the CLI.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { HOOKS_TEMPLATE_REL, K01_FILES } from './aai-bootstrap-fixtures.mjs';
import { materializeBootstrapReference } from './bootstrap-reference.mjs';
import { materializeUpdateReference } from './update-reference.mjs';
import { materializeHookInstallerReference } from './hook-installer-reference.mjs';
import { materializeSyncReference } from './sync-reference.mjs';

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
const HOSTS = ['any', 'posix', 'win32', 'utc', 'non-utc', 'bsd-sed', 'ps5'];
const STEP_TIMEOUT_MS = 300000;
// AAI_PARITY_STEP_TIMEOUT (seconds) overrides the 300 s per-step bound; a value that is not a positive number is refused.
export function stepTimeoutMs(env = process.env) {
  const v = env.AAI_PARITY_STEP_TIMEOUT;
  if (v === undefined || v === '') return STEP_TIMEOUT_MS;
  const n = Number(v);
  if (!/^[0-9]+(\.[0-9]+)?$/.test(String(v).trim()) || !(n > 0)) throw new RangeError(`AAI_PARITY_STEP_TIMEOUT must be a positive number of seconds, got '${v}'`);
  return Math.round(n * 1000);
}
// A step that outlived its bound is an infrastructure break (a loaded host), not a divergence between the twins.
export class InfraFixtureTimeout extends Error {
  constructor(what) { super(`INFRA timeout fixture ${what}`); this.what = what; }
}
export class InfraTimeout extends Error {
  constructor(scenario, twin, step) { super(`INFRA timeout ${scenario} ${twin} ${step}`); this.scenario = scenario; this.twin = twin; this.step = step; }
}
export const EXIT_INFRA = 4;

// ---------------------------------------------------------------------------------------------------------------
// D-NORM: the complete list of normalizations and exclusions. Nothing else rewrites a byte or a name.
export const NORMALIZATIONS = [
  { id: 'N1', what: 'AAI_PIN.md sync time (second precision only)', reason: 'wall clock' },
  { id: 'N2', what: 'sync-conflicts report Generated-at line (second precision only)', reason: 'wall clock' },
  { id: 'N3', what: 'sync-conflicts report name stamp (every report renamed by ordinal; a name that is not 0 to 2 s before its Generated-at second is reported at #name)',
    reason: 'wall clock; two clock reads of one moment (name up to 2 s before Generated-at) agree; a name that disagrees with the report Generated-at second is still renamed by ordinal and reported at #name' },
  { id: 'N4', what: 'doctor report name stamp and host', reason: 'wall clock and host name' },
  { id: 'N5', what: 'bootstrap run timestamp (second precision only) in the marker and the two discovery indexes', reason: 'wall clock: the bootstrap run timestamp NOW_UTC' },
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
  // bootstrap-on-node (D-PARITY): the bootstrap operation, run by the frozen reference (sh), the PowerShell launcher (ps1) and the module (node).
  { id: 'BS-01', tier: 'smoke', op: 'bootstrap', setup: 'bs-polyglot', target: 'target with space',
    steps: [T0('bootstrap', null, [], '0')], probes: ['.claude/skills/AAI_DYNAMIC_SKILLS.md', '.claude/skills/aai-test-e2e/SKILL.md', 'docs/ai/pr-config.yaml'] },
  { id: 'BS-02', tier: 'smoke', op: 'bootstrap', setup: 'bs-unmarked',
    steps: [T0('bootstrap', null, [], 'nonzero')], probes: ['.claude/skills/aai-test-unit/SKILL.md'] },
  { id: 'BS-03', tier: 'default', op: 'bootstrap', setup: 'bs-empty',
    steps: [T0('bootstrap', null, [], '0'), T0('bootstrap', null, [], '0')], probes: ['.gitignore', '.claude/skills/AAI_DYNAMIC_SKILLS.md'] },
  { id: 'BS-04', tier: 'default', op: 'bootstrap', setup: 'bs-unmarked',
    steps: [T0('bootstrap', null, ['force'], '0')], probes: ['.claude/skills/aai-test-unit/SKILL.md'] },
  { id: 'BS-05', tier: 'default', op: 'bootstrap', setup: 'bs-polyglot',
    steps: [T0('bootstrap', null, ['dry-run'], '0')], probes: ['package.json'] },
  { id: 'BS-06', tier: 'default', op: 'bootstrap', setup: 'bs-hooks',
    steps: [T0('bootstrap', null, ['with-claude-hooks'], '0')], probes: ['.claude/settings.json'] },
  { id: 'BS-07', tier: 'full', op: 'bootstrap', setup: 'bs-hooks-invalid',
    steps: [T0('bootstrap', null, ['with-claude-hooks'], 'nonzero')], probes: ['.claude/settings.json'] },
  { id: 'BS-08', tier: 'full', op: 'bootstrap', setup: 'bs-multi',
    steps: [T0('bootstrap', null, [], '0')], probes: ['.gitignore'] },
  { id: 'BS-09', tier: 'full', op: 'bootstrap', setup: 'bs-vitest',
    steps: [T0('bootstrap', null, [], '0')], probes: ['.claude/skills/aai-test-unit/SKILL.md'] },
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
const BS_FLAG = { force: '--force', 'dry-run': '--dry-run', 'with-claude-hooks': '--with-claude-hooks' };
const bsFlags = (step) => (step.flags || []).map((f) => BS_FLAG[f]);
const psHead = (ctx) => ['-NoProfile', '-NonInteractive', ...(process.platform === 'win32' ? ['-ExecutionPolicy', 'Bypass'] : []), '-File'];

export const TWINS = {
  sh: {
    name: 'sh',
    argv(step, ctx) {
      if (step.op === 'bootstrap') return { file: ctx.bash, args: [`${fwd(ctx.bsref)}/.aai/scripts/aai-bootstrap.sh`, fwd(ctx.target), ...bsFlags(step)], cwd: ctx.target };
      const src = fwd(ctx.src); const target = fwd(ctx.target);
      if (step.op === 'sync') {
        return { file: ctx.bash, args: [`${fwd(ctx.syref)}/.aai/scripts/aai-sync.sh`, target, ...(step.profile ? ['--profile', step.profile] : [])], cwd: ctx.target };
      }
      if (step.op === 'update') {
        return { file: ctx.bash, args: [`${fwd(ctx.upref)}/.aai/scripts/aai-update.sh`, '--repo', src, '--ref', 'main'], cwd: ctx.target };
      }
      return { file: ctx.bash, args: [`${fwd(ctx.hkref)}/.aai/scripts/install-pre-commit-hook.sh`, ...(step.flags || []).map((f) => SH_FLAG[f])], cwd: ctx.target };
    },
  },
  ps1: {
    name: 'ps1',
    argv(step, ctx) {
      if (step.op === 'bootstrap') return { file: ctx.ps, args: [...psHead(ctx), `${fwd(ctx.bsref)}/.aai/scripts/aai-bootstrap.ps1`, ctx.target, ...bsFlags(step)], cwd: ctx.target };
      const src = fwd(ctx.src);
      if (step.op === 'sync') {
        return { file: ctx.ps, args: [...psHead(ctx), `${fwd(ctx.syref)}/.aai/scripts/aai-sync.ps1`, '-TargetRoot', ctx.target, ...(step.profile ? ['-Profile', step.profile] : [])], cwd: ctx.target };
      }
      if (step.op === 'update') {
        return { file: ctx.ps, args: [...psHead(ctx), `${src}/.aai/scripts/aai-update.ps1`, '-Repo', ctx.src, '-Ref', 'main'], cwd: ctx.target };
      }
      return { file: ctx.ps, args: [...psHead(ctx), `${fwd(ctx.hkref)}/.aai/scripts/install-pre-commit-hook.ps1`, ...(step.flags || []).map((f) => PS_FLAG[f])], cwd: ctx.target };
    },
  },
  // The module twin: it runs only on bootstrap and update scenarios (ops). Bootstrap: straight on the Node module of the
  // reference tree. Update: the module of the scratch source with the bash sync runner, paired only with the bash reference
  // (peers), because next to the ps1 twin it would repeat every sync divergence of sh:ps1 under a second pair name.
  node: {
    name: 'node',
    ops: ['bootstrap', 'update', 'hooks', 'sync'],
    peers: { update: ['sh', 'launcher'] },
    argv(step, ctx) {
      if (step.op === 'sync') return { file: process.execPath, args: [path.join(ctx.src, '.aai', 'scripts', 'aai-sync.mjs'), ctx.target, ...(step.profile ? ['--profile', step.profile] : [])], cwd: ctx.target };
      if (step.op === 'bootstrap') return { file: process.execPath, args: [path.join(ctx.bsref, '.aai', 'scripts', 'aai-bootstrap.mjs'), ctx.target, ...bsFlags(step)], cwd: ctx.target };
      if (step.op === 'hooks') return { file: process.execPath, args: [path.join(ctx.target, '.aai', 'scripts', 'install-pre-commit-hook.mjs'), ...(step.flags || []).map((f) => SH_FLAG[f])], cwd: ctx.target };
      return { file: process.execPath, args: [path.join(ctx.src, '.aai', 'scripts', 'aai-update.mjs'), '--repo', ctx.src, '--ref', 'main'], cwd: ctx.target, env: { AAI_UPDATE_SYNC_RUNNER: ctx.bash } };
    },
  },
  // The launcher twin (node-first-phase5-closeout D-TWIN): the SHIPPED aai-sync.sh and aai-update.sh of the scratch source, run
  // through the same bash as the frozen twins (Git for Windows' bash on Windows, never the WSL shim). It is paired only with the
  // module twin: both run the same module from the same scratch source, so a divergence between them is a launcher or
  // Git Bash environment fault, not a rule difference. The shipped aai-update.sh sets its own sync runner, so none is passed here.
  launcher: {
    name: 'launcher',
    ops: ['sync', 'update'],
    peers: { sync: ['node'], update: ['node'] },
    argv(step, ctx) {
      const src = fwd(ctx.src);
      if (step.op === 'sync') return { file: ctx.bash, args: [`${src}/.aai/scripts/aai-sync.sh`, fwd(ctx.target), ...(step.profile ? ['--profile', step.profile] : [])], cwd: ctx.target };
      return { file: ctx.bash, args: [`${src}/.aai/scripts/aai-update.sh`, '--repo', src, '--ref', 'main'], cwd: ctx.target };
    },
  },
};

// twinsFor(twins, scenario): the twins that run a scenario; a twin with ops runs only the operations it lists.
export const twinsFor = (twins, scenario) => twins.filter((t) => !t.ops || t.ops.includes(scenario.op));

// pairAllowed(a, b, op): a twin that lists peers for an operation is compared only with the twins it lists; a twin without peers pairs with every twin.
export const pairAllowed = (a, b, op) => [[a, b], [b, a]].every(([x, y]) => !x.peers || !x.peers[op] || x.peers[op].includes(y.name));

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

export function hostInfo({ ps = null, bash = null } = {}) {
  const win = process.platform === 'win32';
  return { platform: win ? 'win32' : 'posix', utc: win ? new Date().getTimezoneOffset() === 0 : false, bsdSed: probeBsdSed(bash), ps5: ps ? probePs5(ps) : false };
}
// Windows PowerShell 5.1 (a PowerShell older than 6) writes a UTF-8 byte order mark with -Encoding utf8; pwsh 7 does not.
// The probe asks the engine the driver is given for its own major version.
export function probePs5(ps) {
  try {
    const r = spawnSync(ps, ['-NoProfile', '-NonInteractive', '-Command', '[Console]::Out.Write($PSVersionTable.PSVersion.Major)'], { encoding: 'utf8', timeout: 60000 });
    return r.status === 0 && Number(String(r.stdout).trim()) < 6;
  } catch { return false; }
}
// BSD sed (macOS) reads \s in an ERE as a literal s, so aai-sync.sh's version extraction keeps the space after
// "Version:"; GNU sed (Linux, Git for Windows, WSL) strips it. The probe runs the same expression the script uses.
// The sed asked is the one the bash twin runs: with a bash path the probe goes through it, since a Windows PATH may name
// another sed than the one Git for Windows' bash puts first.
export function probeBsdSed(bash = null) {
  try {
    const r = bash
      ? spawnSync(bash, ['-c', "sed -E 's/.*Version:\\s*//'"], { input: '- Version: v1\n', encoding: 'utf8', timeout: 30000 })
      : spawnSync('sed', ['-E', 's/.*Version:\\s*//'], { input: '- Version: v1\n', encoding: 'utf8', timeout: 10000 });
    return r.status === 0 && r.stdout === ' v1\n';
  } catch { return false; }
}
const hostMatches = (want, host) => want === 'any' || want === host.platform || (want === 'utc' && host.utc) || (want === 'non-utc' && !host.utc) || (want === 'bsd-sed' && host.bsdSed === true) || (want === 'ps5' && host.ps5 === true);

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
      let st;
      try {
        st = fs.lstatSync(path.join(abs, name));
      } catch (err) {
        // A name with no UTF-8 form (fu-parity-win-odd-root-dirs: random wide-character directories on Windows)
        // comes back from readdir with replacement characters and cannot be stat'ed by that name. Record it as the
        // directory it is, so the allowlist row for odd root entries decides, instead of crashing the matrix.
        if (err && err.code === 'ENOENT' && !/^[\x20-\x7e]*$/.test(name)) {
          out.set(r, { kind: 'dir' });
          const shown = name.replace(/[^\x20-\x7e]/gu, (c) => `\\u{${c.codePointAt(0).toString(16)}}`);
          process.stderr.write(`install-parity: NOTE - ${rel ? `${rel}/` : ''}${shown} in ${dir} could not be read by name; recorded as a directory, its contents were not compared\n`);
          continue;
        }
        throw err;
      }
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

// N5: the paths whose run timestamp line is normalized (bootstrap marker and the two discovery indexes).
const BOOTSTRAP_STAMPED = ['.claude/skills/AAI_DYNAMIC_SKILLS.md', '.codex/skills.local/README.md', '.gemini/skills.local/README.md'];
const BOOTSTRAP_STAMP_LINE = /^((?:- )?Generated at \(UTC\): )\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ(\r?)$/;
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
      else if (BOOTSTRAP_STAMPED.includes(p)) entry = { ...e, data: Buffer.from(e.data.toString('utf8').split('\n').map((l) => l.replace(BOOTSTRAP_STAMP_LINE, '$1<stamp>$2')).join('\n'), 'utf8') };
    }
    const mc = /^docs\/ai\/reports\/sync-conflicts-(\d{8}-\d{6})\.md$/.exec(p);
    if (mc && e.kind === 'file') {
      const g = e.data.toString('utf8').split('\n').map((l) => GEN_LINE.exec(l)).find(Boolean);
      const nm = /^(\d{4})(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d)$/.exec(mc[1]);
      const at = (m) => Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]) / 1000;
      // The sh twin stamps the name and the Generated-at line with two separate clock reads, so a name 0..2 s BEFORE its
      // own Generated-at is one moment read twice; a later name, a larger gap or an hours offset is a real disagreement.
      const lag = g && nm ? at(g) - at(nm) : null;
      const stamp = lag !== null && lag >= 0 && lag <= 2 ? mc[1] : null;
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

// A path whose first segment leaves printable ASCII (a name a twin or a tool mangled, random from run to run) is reported at
// the path <odd-root-name> plus the rest, so one allowlist row can name it; its real name stays in the detail.
const ODD_FIRST = /^[^/]*[^\x20-\x7e][^/]*(?=\/|$)/;
const reportPath = (p) => p.replace(ODD_FIRST, '<odd-root-name>');
export function compareSnapshots(a, b, pair, labels = null) {
  const [A, B] = labels || pair.split(':');
  const out = [];
  for (const p of [...new Set([...a.keys(), ...b.keys()])].sort()) {
    const x = a.get(p); const y = b.get(p);
    const at = reportPath(p); const named = at === p ? '' : ` ${showName(p)}`;
    if (!x || !y) { out.push({ pair, path: at, kind: 'missing', detail: `present only in ${x ? A : B} (${(x || y).kind})${named}` }); continue; }
    if (x.kind !== y.kind) { out.push({ pair, path: at, kind: 'missing', detail: `${A} has a ${x.kind}, ${B} has a ${y.kind}${named}` }); continue; }
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
      if (twins) {
        // The runner emits a:b only with a registered before b, and a:a for the idempotence pair; any other order can never match.
        const [a, b] = pr.split(':');
        if (a !== b && twins.indexOf(a) > twins.indexOf(b)) throw new AllowlistError(r.id, 'pairs', `${pr} is in an order the runner never emits (registry order is ${twins.join(',')}); write ${b}:${a}`);
      }
    }
    if (r.scenario !== '*' && !r.scenario.split(',').every((s) => /^[A-Za-z0-9-]+$/.test(s))) throw new AllowlistError(r.id, 'scenario', `${r.scenario} is neither * nor a list of ids`);
    if (!r.path) throw new AllowlistError(r.id, 'path', 'empty');
    if (!KINDS.includes(r.kind)) throw new AllowlistError(r.id, 'kind', `${r.kind} is not one of ${KINDS.join(', ')}`);
    if (!HOSTS.includes(r.host)) throw new AllowlistError(r.id, 'host', `${r.host} is not one of ${HOSTS.join(', ')}`);
    if (r.tracker !== 'accepted' && !/^fu-\S+$/.test(r.tracker)) throw new AllowlistError(r.id, 'tracker', `${r.tracker} is neither accepted nor a fu- id`);
    if (r.kind === 'lines' && r.match === '-') throw new AllowlistError(r.id, 'match', 'a lines row needs a regular expression (- would cover every line of its path)');
    if (r.match === '?') {
      if (r.path.includes('*')) throw new AllowlistError(r.id, 'match', '? (intermittent) needs a literal path, not a wildcard');
      if (r.host === 'any') throw new AllowlistError(r.id, 'match', '? (intermittent) needs a named host, not any');
      // An intermittent row: it covers a divergence when one is present and is never judged stale.
      if (r.kind !== 'missing') throw new AllowlistError(r.id, 'match', '? (intermittent) is only for kind missing');
      if (!/^fu-\S+$/.test(r.tracker)) throw new AllowlistError(r.id, 'match', '? (intermittent) needs a fu- tracker that carries the open cause');
      r.intermittent = true;
    } else if (r.match !== '-') {
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
      if (r.intermittent || !named.length || !hostMatches(r.host, host)) continue;
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

export function runStep(file, args, { cwd, env, timeoutMs = stepTimeoutMs() }) {
  const r = spawnSync(process.execPath, ['-e', SUPERVISOR, JSON.stringify([file, ...args]), String(timeoutMs)], { cwd, env, encoding: 'utf8', timeout: timeoutMs + 15000, killSignal: 'SIGKILL', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 });
  let code = r.status;
  if (r.error) code = r.error.code === 'ETIMEDOUT' ? 124 : (r.error.code === 'ENOENT' ? 127 : 1);
  if (code === null || code === undefined) code = r.signal ? 124 : 1;
  const timedOut = (r.error && r.error.code === 'ETIMEDOUT') || (code === 124 && /install-parity: step exceeded/.test(r.stderr || ''));
  return { code, timedOut: Boolean(timedOut), stdout: r.stdout || '', stderr: (r.stderr || '') + (r.error ? `\n${r.error.message}` : '') };
}
const run = runStep;
// Fixture commands (git, the sh sync that builds a scratch target) are not twin steps: AAI_PARITY_STEP_TIMEOUT may only raise their
// 300 s floor, so a tiny step bound cannot make fixture building flake; a fixture that still expires is an INFRA break (exit 4).
const fixtureRun = (file, args, opts) => {
  const r = runStep(file, args, { ...opts, timeoutMs: Math.max(stepTimeoutMs(), STEP_TIMEOUT_MS) });
  if (r.timedOut) throw new InfraFixtureTimeout(`${path.basename(file)} ${args.slice(0, 3).join(' ')}`.trim());
  return r;
};
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
  const r = fixtureRun('git', args, { cwd, env: twinEnv(ctx.root) });
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
  // No background maintenance: a repack that outlives the commit races the copy of this repository (copyTree of the source for syref).
  gitIn(ctx, dir, 'config', 'gc.auto', '0');
  gitIn(ctx, dir, 'config', 'maintenance.auto', 'false');
}
const commitAll = (ctx, dir, msg) => { gitIn(ctx, dir, 'add', '-A', '-f'); gitIn(ctx, dir, 'commit', '-q', '--no-verify', '-m', msg); };
const copyTree = (from, to) => { fs.mkdirSync(path.dirname(to), { recursive: true }); fs.cpSync(from, to, { recursive: true, verbatimSymlinks: true }); };

const SOURCE_NOTE = 'NOTE: the scratch source leaves out tests/** and docs/** (except docs/knowledge/** and docs/ai/AAI_VERSION.md)';

// F1 CURRENT SOURCE: every tracked path of the checkout (working-tree bytes) except tests/** and most of docs/**.
const SYNC_MODULE_FILES = ['.aai/scripts/aai-sync.mjs', '.aai/scripts/lib/resolve-base.mjs', '.aai/scripts/lib/gitignore-block.mjs'];
export function buildSource(ctx) {
  const dir = path.join(ctx.root, 'fx', 'src');
  const ls = fixtureRun('git', ['ls-files', '-z'], { cwd: REPO_ROOT, env: twinEnv(ctx.root) });
  if (ls.code !== 0) throw new Error(`git ls-files failed: ${ls.stderr}`);
  // A Windows checkout (core.autocrlf) holds CRLF working-tree copies of files the index stores with LF. The twins read these
  // files (the pin version, the profile manifest, the ignore list, their own script text), and a CR left in them is a
  // checkout artifact, not twin behavior, so the scratch source takes the index's line ending for every such file.
  const eol = fixtureRun('git', ['ls-files', '--eol', '-z'], { cwd: REPO_ROOT, env: twinEnv(ctx.root) });
  const toLf = new Set();
  for (const e of (eol.code === 0 ? eol.stdout : '').split('\0').filter(Boolean)) {
    const m = /^i\/(\S+)\s+w\/(crlf|mixed)\s+attr\/[^\t]*\t(.+)$/.exec(e);
    if (m && m[1] === 'lf') toLf.add(m[3]);
  }
  // The sync module and its two libs are copied when they are not tracked yet, so a run before the first commit of a new
  // file is not silently stale (the module twin runs them from this scratch source).
  const listed = ls.stdout.split('\0').filter(Boolean);
  for (const rel of SYNC_MODULE_FILES) if (!listed.includes(rel) && fs.existsSync(path.join(REPO_ROOT, rel))) listed.push(rel);
  for (const rel of listed) {
    if (rel.startsWith('tests/')) continue;
    if (rel.startsWith('docs/') && !rel.startsWith('docs/knowledge/') && rel !== 'docs/ai/AAI_VERSION.md') continue;
    const from = path.join(REPO_ROOT, rel); const to = path.join(dir, rel);
    let st;
    try { st = fs.lstatSync(from); } catch { continue; }
    if (st.isDirectory()) continue;
    fs.mkdirSync(path.dirname(to), { recursive: true });
    if (st.isSymbolicLink()) fs.symlinkSync(fs.readlinkSync(from), to);
    else if (toLf.has(rel)) fs.writeFileSync(to, fs.readFileSync(from).toString('latin1').replace(/\r\n/g, '\n'), 'latin1');
    else fs.copyFileSync(from, to);
  }
  if (toLf.size) ctx.notes = (ctx.notes || []).concat(`NOTE: the scratch source holds ${toLf.size} checkout file(s) with the index's LF line ending in place of their CRLF working-tree copy`);
  initRepo(ctx, dir);
  commitAll(ctx, dir, 'src');
  ctx.notes = (ctx.notes || []).concat(SOURCE_NOTE);
  return dir;
}

function syncWithSh(ctx, srcDir, target, profile) {
  const r = fixtureRun(ctx.bash, [`${fwd(srcDir)}/.aai/scripts/aai-sync.sh`, fwd(target), '--profile', profile], { cwd: target, env: twinEnv(ctx.root) });
  if (r.code !== 0) throw new Error(`fixture sync (${profile}) failed with ${r.code}: ${r.stderr.slice(-400)}`);
  // The sync-conflicts report is named by the second: a twin step that began in the same second would overwrite this report of the fixture
  // sync instead of writing its own, and the module syncs the fixture fast enough for that to happen.
  waitNextSecond();
}

// PROFILES.yaml lines come from a split on LF, so a CRLF checkout leaves a trailing CR on every line; each pattern
// below must treat it as part of the line end.
const CORE_ENTRY = /^  - (\.aai\/templates\/\S+)\r?$/;
const entryPath = (line) => CORE_ENTRY.exec(line)[1];
export function findRemovableCoreEntry(lines, isFile) {
  const core = lines.findIndex((l) => /^core:\s*$/.test(l));
  if (core < 0) return -1;
  for (let i = core + 1; i < lines.length && /^\s*(-|#|$)/.test(lines[i]); i += 1) {
    const m = CORE_ENTRY.exec(lines[i]);
    if (m && isFile(m[1])) return i;
  }
  return -1;
}

// F2 OLDER SOURCE.
function buildOlderSource(ctx) {
  const dir = path.join(ctx.root, 'fx', 'src-older');
  if (fs.existsSync(dir)) return dir;
  copyTree(ctx.src, dir);
  const ver = path.join(dir, 'docs/ai/AAI_VERSION.md');
  fs.writeFileSync(ver, fs.readFileSync(ver, 'utf8').replace(/^- Version: [^\r\n]*/m, '- Version: v2026.01.01'));
  const prof = path.join(dir, '.aai/system/PROFILES.yaml');
  const lines = fs.readFileSync(prof, 'utf8').split('\n');
  const drop = findRemovableCoreEntry(lines, (rel) => { const f = path.join(dir, ...rel.split('/')); return fs.existsSync(f) && fs.lstatSync(f).isFile(); });
  if (drop < 0) throw new Error('F2: no removable core template entry found in PROFILES.yaml');
  fs.rmSync(path.join(dir, ...entryPath(lines[drop]).split('/')));
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

// The bootstrap setups (D-PARITY): every target is a git repository without origin.
const putFiles = (dir, files) => { for (const [rel, body] of Object.entries(files)) { if (rel.endsWith('/')) fs.mkdirSync(path.join(dir, rel), { recursive: true }); else put(dir, rel, body); } };
function bootstrapSetup(kind, target, ctx) {
  const tpl = () => fs.readFileSync(path.join(ctx.src || REPO_ROOT, ...HOOKS_TEMPLATE_REL.split('/')));
  if (kind === 'bs-empty') return;
  if (kind === 'bs-polyglot') putFiles(target, K01_FILES);
  else if (kind === 'bs-unmarked') putFiles(target, { ...K01_FILES, '.claude/skills/aai-test-unit/SKILL.md': 'my own unit skill\n' });
  else if (kind === 'bs-hooks') putFiles(target, { [HOOKS_TEMPLATE_REL]: tpl(), '.claude/settings.json': `${JSON.stringify({ permissions: { allow: ['Bash(ls:*)'] } }, null, 2)}\n` });
  else if (kind === 'bs-hooks-invalid') putFiles(target, { [HOOKS_TEMPLATE_REL]: tpl(), '.claude/settings.json': 'NOT JSON {' });
  else if (kind === 'bs-multi') {
    putFiles(target, {
      'go.mod': 'module multi\n', 'Cargo.toml': '[package]\nname = "multi"\n', Makefile: 'test:\n\tgo test ./...\nbuild:\n\tgo build ./...\nlint:\n\tgo vet ./...\n',
      justfile: 'deploy:\n  echo deploy\n', Dockerfile: 'FROM scratch\n', 'wrangler.toml': 'name = "multi"\n', '.github/workflows/ci.yml': 'name: ci\n',
      '.gitignore': '.claude/skills/.cache\r\ndocs/ai/STATE.yaml\r\n',
    });
  } else if (kind === 'bs-vitest') {
    putFiles(target, { 'pnpm-lock.yaml': '', 'package.json': `${JSON.stringify({ name: 'vt', devDependencies: { vitest: '^1', typescript: '^5' } }, null, 2)}\n`, 'tsconfig.json': '{}\n', 'biome.json': '{}\n' });
  } else throw new Error(`unknown bootstrap setup: ${kind}`);
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
  if (kind.startsWith('bs-')) { bootstrapSetup(kind, target, ctx); return; }
  if (kind === 'crlf-gitignore') put(target, '.gitignore', ['node_modules/', '.env', '.aai/', '.aai/cache/', '.aai/', '.aai/cache/', ''].join('\r\n'));
  else if (kind === 'hooks-json') {
    put(target, 'hooks/hooks.json', `${JSON.stringify({ hooks: { PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'echo user-hook' }] }] } }, null, 2)}\n`);
    put(target, 'hooks/session-start.sh', '#!/usr/bin/env bash\necho project edited\n', 0o755);
  } else if (kind !== 'empty') throw new Error(`unknown scenario setup: ${kind}`);
}

// ---------------------------------------------------------------------------------------------------------------
// D-HOSTCHECK (node-first-phase5-closeout): named host checks. Each entry is { id, scenario, twin, status, checked, detail } with
// status pass, fail, not-applicable or bites; each also goes to the notes as one AAI-HOST-CHECK line, and any fail fails the run.
// A root entry whose name leaves printable ASCII (a mangled name is random from run to run) that a step birthed is the defect
// fu-parity-win-odd-root-dirs describes.
const ODD_NAME = /[^\x20-\x7e]/;
// A Windows absolute source path starts with a drive letter, a colon and a backslash (the Git Bash spelling /c/... does not).
const WIN_ABS_RE = /^[A-Za-z]:\\/;
export { ODD_NAME, WIN_ABS_RE };
// The twins whose output the host checks read: the module and the shipped launchers. The frozen sh twin is the control's subject.
export const HOST_CHECK_TWINS = ['node', 'launcher'];
const HOST_CHECK_OPS = ['sync', 'update'];
const hostCheckLine = (e) => `AAI-HOST-CHECK ${e.id} ${e.scenario} ${e.twin} ${e.status} checked=${e.checked}`;
const entryOf = (id, scenario, twin, status, checked, detail) => ({ id, scenario, twin, status, checked, detail });

// The Source path lines of a pin and the Source lines of the sync-conflicts reports the step wrote, read from the target.
const lineValues = (text, label) => String(text).split('\n').map((l) => new RegExp(`^- ${label}: (.*?)\\r?$`).exec(l)).filter(Boolean).map((m) => m[1]);
export function readSourcePaths(dir) {
  const read = (rel) => { try { return fs.readFileSync(path.join(dir, ...rel.split('/')), 'utf8'); } catch { return ''; } };
  let reports = [];
  try { reports = fs.readdirSync(path.join(dir, 'docs', 'ai', 'reports')).filter((n) => /^sync-conflicts-[^/]+\.md$/.test(n)).sort(); } catch { reports = []; }
  return { pin: lineValues(read(AAI_PIN), 'Source path'), report: reports.flatMap((n) => lineValues(read(`docs/ai/reports/${n}`), 'Source')) };
}
export function sourcePathCheck({ platform, scenario, twin, pin = [], report = [] }) {
  const id = 'source-path-windows';
  if (platform !== 'win32') return entryOf(id, scenario, twin, 'not-applicable', 0, 'POSIX host');
  const lines = [...pin, ...report];
  const bad = lines.find((v) => !WIN_ABS_RE.test(v));
  if (bad !== undefined) return entryOf(id, scenario, twin, 'fail', lines.length, `a source path line is not a drive letter, colon and backslash path: ${showName(bad)}`);
  if (scenario === 'SY-01' && lines.length < 2) return entryOf(id, scenario, twin, 'fail', lines.length, `vacuous: ${lines.length} line(s) checked, at least 2 are required in SY-01 (the pin and a report)`);
  return entryOf(id, scenario, twin, 'pass', lines.length, '');
}
// The control: the same predicate on the frozen sh twin's pin must FAIL (it records /c/...), else the check would not catch the old bug.
export function sourcePathControl({ platform, scenario, twin, pin = [] }) {
  const id = 'source-path-windows-control';
  if (platform !== 'win32') return entryOf(id, scenario, twin, 'not-applicable', 0, 'POSIX host');
  if (!pin.length) return entryOf(id, scenario, twin, 'fail', 0, 'vacuous: the frozen sh pin holds no Source path line to judge');
  if (pin.every((v) => WIN_ABS_RE.test(v))) return entryOf(id, scenario, twin, 'fail', pin.length, 'the predicate passes the frozen sh pin, so it would not catch the old Git Bash spelling');
  return entryOf(id, scenario, twin, 'bites', pin.length, `the predicate rejects ${showName(pin.find((v) => !WIN_ABS_RE.test(v)))}`);
}
export const exitCodeFor = (rep) => (rep.verdict === 'PASS' && !(rep.host_checks || []).some((e) => e.status === 'fail') ? 0 : 1);

// D-ODD step 2 (test-only, off unless AAI_PARITY_ODD_DIAG=1): in a fresh copy of the post-step target, one candidate at a time with a
// root snapshot before and after each. The first candidate that births an entry, narrowed to its child process and arguments, is the
// named root cause. Each runs as a child of the driver's bash (the bash-derived environment the sh twin gave the doctor).
const REF_GUARD_HELPER = `
const fs = require('node:fs'), path = require('node:path'), os = require('node:os'), cp = require('node:child_process'), url = require('node:url');
(async () => {
  const [root, arm] = process.argv.slice(1);
  const g = cp.spawnSync('git', ['rev-parse', '--git-path', 'hooks/reference-transaction'], { cwd: root, encoding: 'utf8' });
  const rel = String(g.stdout || '').trim();
  const hookPath = rel ? (path.isAbsolute(rel) ? rel : path.join(root, rel)) : '';
  if (!hookPath || !fs.existsSync(hookPath)) { process.stdout.write('no-hook\\n'); return; }
  const gc = await import(url.pathToFileURL(path.join(root, '.aai', 'scripts', 'lib', 'guard-config.mjs')).href);
  let gitExecPath = '';
  if (process.platform === 'win32') { const e = cp.spawnSync('git', ['--exec-path'], { cwd: root, encoding: 'utf8' }); if (e.status === 0) gitExecPath = String(e.stdout).trim(); }
  const launchers = gc.resolveRefGuardLaunchers({ platform: process.platform, hookPath, gitExecPath, exists: (p) => fs.existsSync(p) });
  const REFUSE = '0'.repeat(40) + ' ' + '1'.repeat(40) + ' refs/heads/main\\n';
  const pad = Array.from({ length: 1000 }, (_, i) => '0'.repeat(40) + ' ' + '2'.repeat(40) + ' refs/heads/aai-doctor-probe-pad-' + i + '\\n').join('');
  const CONTROL = ('0'.repeat(40) + ' ' + '2'.repeat(40) + ' refs/heads/aai-doctor-probe-control\\n').repeat(1001);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-doctor-probe-'));
  try {
    const input = path.join(dir, 'in'); const control = path.join(dir, 'control');
    fs.writeFileSync(input, REFUSE + pad); fs.writeFileSync(control, CONTROL);
    const base = { ...process.env }; delete base.AAI_GIT_WRITE;
    const env = arm === 'permit' ? { ...base, AAI_GIT_WRITE: '1' } : base;
    const file = arm === 'control' ? control : input;
    for (const [cmd, args] of launchers) {
      const fd = fs.openSync(file, 'r');
      let r; try { r = cp.spawnSync(cmd, args, { cwd: root, env, encoding: 'utf8', timeout: 5000, stdio: [fd, 'pipe', 'pipe'] }); } finally { fs.closeSync(fd); }
      process.stdout.write(cmd + ' ' + args.join(' ') + ' exit=' + r.status + (r.error ? ' error=' + r.error.code : '') + '\\n');
      if (!r.error) break;
    }
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
})().catch((e) => { process.stdout.write('helper-error ' + e.message + '\\n'); });
`;
export function oddDiagCandidates({ ps = 'pwsh' } = {}) {
  const script = (copy, n) => path.join(copy, '.aai', 'scripts', n);
  const node = (name, args) => ({ name, run: (copy) => ({ file: process.execPath, args: args(copy), cwd: copy }) });
  const cli = (n) => ({ name: `agent-cli-${n}`, run: (copy) => ({ file: n, args: ['--version'], cwd: copy }) });
  return [
    node('field-report-helper', (copy) => [script(copy, 'update-doctor-report.mjs'), '--root', copy]),
    node('doctor-json', (copy) => [script(copy, 'aai-doctor.mjs'), '--root', copy, '--json']),
    ...['control', 'refuse', 'permit'].map((arm) => node(`ref-guard-${arm}`, (copy) => ['-e', REF_GUARD_HELPER, copy, arm])),
    { name: 'win-selftest', run: (copy) => ({ file: ps, args: ['-NoProfile', '-File', script(copy, 'aai-win-selftest.ps1')], cwd: copy }) },
    ...['claude', 'codex', 'gemini'].map(cli),
  ];
}
export function runOddDiag({ root, target, bash, env, candidates = oddDiagCandidates(), scenario, twin, useBash = true, timeoutMs = 120000 }) {
  const lines = [];
  const base = path.join(root, 'odd-diag', `${scenario}-${twin}`);
  fs.rmSync(base, { recursive: true, force: true });
  candidates.forEach((cand, i) => {
    const copy = path.join(base, `c${i + 1}`);
    copyTree(target, copy);
    const a = cand.run(copy);
    const before = new Set(fs.readdirSync(copy));
    // The child is started through bash so it sees what a child of the sh twin sees: bash <- cd copy && exec file args.
    const launch = useBash ? { file: bash, args: ['-c', 'cd "$1" && shift && exec "$@"', '_', fwd(copy), a.file, ...a.args] } : { file: a.file, args: a.args };
    const r = run(launch.file, launch.args, { cwd: a.cwd || copy, env, timeoutMs });
    const born = fs.readdirSync(copy).filter((n) => !before.has(n));
    const names = born.length ? ` born_names=${born.map(showName).join(',')}` : '';
    const tail = r.timedOut ? ' timed_out=1' : '';
    lines.push(`AAI-ODD-DIAG ${cand.name} born=${born.length} scenario=${scenario} twin=${twin} exit=${r.code}${tail}${names} cmd=${[a.file, ...a.args].map((x) => (String(x).length > 80 ? `${String(x).slice(0, 40)}...` : x)).join(' ').replace(/\s+/g, ' ').slice(0, 300)}`);
    fs.rmSync(copy, { recursive: true, force: true });
  });
  return lines;
}

// ---------------------------------------------------------------------------------------------------------------
// The runner.
const doctorHead = (dir) => {
  try {
    const rd = path.join(dir, 'docs', 'ai', 'reports');
    const f = fs.readdirSync(rd).filter((n) => /^doctor-.*\.md$/.test(n)).sort().pop();
    return f ? fs.readFileSync(path.join(rd, f), 'utf8').slice(0, 2500) : '';
  } catch { return ''; }
};
const oddRootNames = (dir) => { try { return fs.readdirSync(dir).filter((n) => !/^[\x20-\x7e]*$/.test(n)); } catch { return []; } };
const birthMs = (p, since) => { try { return Math.round(fs.lstatSync(p).birthtimeMs - since); } catch { return 'unknown'; } };
function runScenario(scenario, allTwins, ctx) {
  const t0 = Date.now();
  const twins = twinsFor(allTwins, scenario);
  const targetDir = path.join(ctx.root, scenario.id, scenario.target || 'target');
  const hooks = scenario.op === 'hooks';
  const results = []; const broken = []; const steps = []; const hostChecks = []; const diag = [];
  const platform = ctx.platform || process.platform;
  const hostScenario = HOST_CHECK_OPS.includes(scenario.op);
  let frozenShPin = null;
  for (const twin of twins) {
    fs.rmSync(targetDir, { recursive: true, force: true });
    fs.mkdirSync(path.dirname(targetDir), { recursive: true });
    (ctx.setup || defaultSetup)(scenario, targetDir, ctx, twin.name);
    // Every twin step writes only into a target under this run's scratch root; the launcher twin additionally never runs on an
    // empty target (a launcher that had nothing to act on would prove nothing, and an empty path would mean the wrong directory).
    if (!path.isAbsolute(targetDir) || !(path.resolve(targetDir) + path.sep).startsWith(path.resolve(ctx.root) + path.sep)) throw new Error(`the target ${targetDir} of ${scenario.id} ${twin.name} is not under the scratch root ${ctx.root}`);
    if (twin.name === 'launcher' && (!fs.existsSync(targetDir) || fs.readdirSync(targetDir).length === 0)) throw new Error(`empty target ${targetDir} for the launcher twin in ${scenario.id}: refusing to run a shipped launcher on it`);
    const checked = hostScenario && HOST_CHECK_TWINS.includes(twin.name);
    const oddBorn = []; let rootRead = 0;
    const codes = []; const snaps = [];
    scenario.steps.forEach((step, i) => {
      const actx = { src: ctx.src, target: targetDir, bash: ctx.bash, ps: ctx.ps, bsref: ctx.bsref, upref: ctx.upref, hkref: ctx.hkref };
      Object.defineProperty(actx, 'syref', { enumerable: true, get: () => ctx.syref });
      const a = twin.argv({ ...step, index: i }, actx);
      const before = oddRootNames(targetDir); const t1 = Date.now();
      const rootBefore = checked ? new Set(fs.readdirSync(targetDir)) : null;
      const r = run(a.file, a.args, { cwd: a.cwd || targetDir, env: { ...twinEnv(ctx.root), ...(a.env || {}) } });
      if (r.timedOut) throw new InfraTimeout(scenario.id, twin.name, i + 1);
      codes.push(r.code);
      if (checked) {
        const rootAfter = fs.readdirSync(targetDir);
        rootRead += rootAfter.length;
        for (const name of rootAfter) if (!rootBefore.has(name) && ODD_NAME.test(name)) oddBorn.push({ step: i + 1, name });
      }
      if (process.env.AAI_PARITY_ODD_DIAG === '1' && step.op === 'update') {
        diag.push(...runOddDiag({ root: ctx.root, target: targetDir, bash: ctx.bash, env: { ...twinEnv(ctx.root), ...(a.env || {}) }, candidates: oddDiagCandidates({ ps: ctx.ps }), scenario: scenario.id, twin: twin.name }));
      }
      // Root entries whose name leaves printable ASCII are reported with the step that left them (a mangled name is a harness
      // or twin fault worth seeing in a CI log), with their birth time against the step window.
      const odd = oddRootNames(targetDir).filter((n) => !before.includes(n)).map((n) => `${showName(n)} born ${birthMs(path.join(targetDir, n), t1)} ms after the step started (step took ${Date.now() - t1} ms)`);
      steps.push({ twin: twin.name, step: i + 1, code: r.code, ...(odd.length ? { odd_root_entries: odd } : {}), ...(step.op === 'update' ? { doctor_head: doctorHead(targetDir) } : {}), ...(r.code !== 0 ? { stderr_tail: r.stderr.slice(-1500) } : {}), stdout_tail: r.stdout.slice(-1200) });
      if (scenario.steps.length > 1) snaps.push(snapshotNormalized(targetDir, { hooks }));
      if (i < scenario.steps.length - 1 && step.op !== 'hooks') waitNextSecond();
    });
    const missing = scenario.probes.filter((p) => !fs.existsSync(path.join(targetDir, ...p.split('/'))));
    for (const p of missing) broken.push(`probe ${p} is missing from the ${twin.name} tree`);
    if (checked) {
      const odd = oddBorn.map((o) => `step ${o.step}: ${showName(o.name)}`);
      hostChecks.push(entryOf('no-odd-root', scenario.id, twin.name, odd.length ? 'fail' : 'pass', rootRead, odd.length ? `root entries born with a name outside printable ASCII: ${odd.join('; ')}` : ''));
      const src = readSourcePaths(targetDir);
      hostChecks.push(sourcePathCheck({ platform, scenario: scenario.id, twin: twin.name, pin: src.pin, report: src.report }));
    }
    if (hostScenario && twin.name === REFERENCE_TWIN && scenario.id === 'SY-01') frozenShPin = readSourcePaths(targetDir).pin;
    const final = scenario.steps.length > 1 ? snaps[snaps.length - 1] : snapshotNormalized(targetDir, { hooks });
    results.push({ twin, codes, first: snaps[0] || final, final });
    try { fs.renameSync(targetDir, path.join(path.dirname(targetDir), `out-${twin.name}`)); } catch { fs.rmSync(targetDir, { recursive: true, force: true }); }
  }
  // The control runs the Windows predicate on the frozen sh twin's SY-01 pin: it must fail there, or the check would not catch the old bug.
  if (frozenShPin !== null) hostChecks.push(sourcePathControl({ platform, scenario: scenario.id, twin: REFERENCE_TWIN, pin: frozenShPin }));
  const refResult = results.find((r) => r.twin.name === REFERENCE_TWIN) || results[0];
  scenario.steps.forEach((step, i) => {
    const ref = { code: refResult.codes[i] };
    if (!expectMet(step.expect, ref.code)) broken.push(`step ${i + 1} on the reference twin ${refResult.twin.name} exited ${ref.code}, expected ${step.expect}`);
  });
  const divergences = []; const pairs = [];
  for (let i = 0; i < twins.length; i += 1) {
    for (let j = i + 1; j < twins.length; j += 1) {
      if (!pairAllowed(results[i].twin, results[j].twin, scenario.op)) continue;
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
  return { id: scenario.id, seconds: Math.round((Date.now() - t0) / 100) / 10, steps, broken, divergences, pairs, hostChecks, diag };
}

export function runMatrix({ scenarios, twins, rows = [], ctx, matrix = 'default', filtered = false }) {
  const t0 = Date.now();
  const c = { ...ctx };
  fs.mkdirSync(c.root, { recursive: true });
  prepareRoot(c.root);
  if (!c.src && !c.setup) c.src = buildSource(c);
  // The frozen reference tree (and the module and launchers beside it) for the bootstrap scenarios, built once from the checkout.
  if (!c.bsref && scenarios.some((s) => s.op === 'bootstrap')) { c.bsref = path.join(c.root, 'bsref'); materializeBootstrapReference(REPO_ROOT, c.bsref); }
  // The frozen updater references for the update scenarios: the bash twin of the sh column runs from here.
  if (!c.upref && scenarios.some((s) => s.op === 'update')) { c.upref = path.join(c.root, 'upref'); materializeUpdateReference(REPO_ROOT, c.upref); }
  // The frozen hook installer references (and the current templates beside them) for the hook scenarios: the sh and ps1 columns run from here.
  if (!c.hkref && scenarios.some((s) => s.op === 'hooks')) { c.hkref = path.join(c.root, 'hkref'); materializeHookInstallerReference(REPO_ROOT, c.hkref); }
  // The frozen layer sync references for the sync scenarios: a copy of the scratch source with the two old twins and the bash
  // library written over it and the module-side engine files removed; the sh and ps1 columns run from here, the node column
  // runs the module of the scratch source.
  // It is built when a twin first asks for it (a getter), so a run whose twins never run the frozen sync builds none.
  if (!c.syref && scenarios.some((s) => s.op === 'sync')) {
    let built = null;
    Object.defineProperty(c, 'syref', { enumerable: true, configurable: true, get() { if (built === null) { built = path.join(c.root, 'syref'); copyTree(c.src, built); materializeSyncReference(built); } return built; } });
  }
  const host = c.host || hostInfo();
  const report = { verdict: 'PASS', host: host.platform, tz: PINNED_TZ, matrix, twins: twins.map((t) => t.name), pairs: [], total_seconds: 0, scenarios: [], uncovered: [], stale: [] };
  const used = new Set(); const usedPairs = new Set(); const pairsByScenario = {}; const pairSet = []; const ran = [];
  const hostChecks = []; const oddDiag = [];
  for (const s of scenarios) {
    const r = runScenario(s, twins, c);
    ran.push(s.id);
    const { covered, uncovered, used: u, usedPairs: up } = applyAllowlist(r.divergences, rows, { scenario: s.id, host });
    for (const id of u) used.add(id);
    for (const k of up) usedPairs.add(k);
    pairsByScenario[s.id] = r.pairs;
    for (const p of r.pairs) if (!pairSet.includes(p)) pairSet.push(p);
    hostChecks.push(...r.hostChecks); oddDiag.push(...r.diag);
    report.scenarios.push({ id: r.id, seconds: r.seconds, steps: r.steps, broken: r.broken, pairs: r.pairs, divergences: [...covered, ...uncovered].map((d) => ({ pair: d.pair, path: d.path, kind: d.kind, detail: d.detail, covered_by: d.covered_by })) });
    for (const d of uncovered) report.uncovered.push({ scenario: s.id, pair: d.pair, path: d.path, kind: d.kind, detail: d.detail });
  }
  report.pairs = [...pairSet.filter((p) => p.split(':')[0] !== p.split(':')[1]), ...pairSet.filter((p) => p.split(':')[0] === p.split(':')[1])];
  report.stale = staleRows(rows, { ran, pairsRun: report.pairs, host, used, usedPairs, pairsByScenario, wholeTier: !filtered }).map((r) => ({ id: r.id, scenario: r.scenario, pairs: r.pair, path: r.path, kind: r.kind }));
  report.stale_check = filtered ? 'off (scenario filter)' : 'on';
  report.host_checks = hostChecks;
  report.notes = [...(c.notes || []), ...hostChecks.map(hostCheckLine), ...oddDiag];
  report.total_seconds = Math.round((Date.now() - t0) / 100) / 10;
  if (report.uncovered.length || report.stale.length || report.scenarios.some((s) => s.broken.length) || hostChecks.some((e) => e.status === 'fail')) report.verdict = 'FAIL';
  return report;
}

// ---------------------------------------------------------------------------------------------------------------
// CLI.
const USAGE = `usage: install-parity.mjs list --matrix <smoke|default|full> [--json]
       install-parity.mjs run --matrix <tier> [--scenario <id>]... [--twins <names>; default: every registered twin] [--twin-module <name>=<path>]...
                          [--allowlist <tsv>] [--bash <path>] [--ps <path>] [--json <file>] [--keep]`;
class UsageError extends Error {}

// A path with a byte outside printable ASCII prints as its code points, so a mangled name reads the same in every console.
const showName = (p) => (/^[\x20-\x7e]*$/.test(p) ? p : p.replace(/[^\x20-\x7e]/gu, (c) => `\\u{${c.codePointAt(0).toString(16)}}`));

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
  try { stepTimeoutMs(); } catch (e) { throw new UsageError(e.message); }
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
  // A scenario that fewer than two of the selected twins run has nothing to compare; refuse it by name rather than pass or crash.
  for (const sc of scenarios) {
    const running = twinsFor(twins, sc);
    if (running.length < 2) throw new UsageError(`scenario ${sc.id} (${sc.op}) is run by ${running.length} of the selected twins (${running.map((t) => t.name).join(',') || 'none'}); at least two are needed to compare, so nothing would be proven`);
    // Two runnable twins are not enough when peers forbid every pair between them (ps1,node on an update scenario).
    if (!running.some((x, i) => running.slice(i + 1).some((y) => pairAllowed(x, y, sc.op)))) throw new UsageError(`scenario ${sc.id} (${sc.op}) has no permitted pair among the selected twins (${running.map((t) => t.name).join(',')}); a twin's peers exclude every other selected twin, so nothing would be compared`);
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
    rep = runMatrix({ scenarios, twins, rows, matrix: o.matrix, filtered: o.scenario.length > 0, ctx: { root, src: null, bash: o.bash, ps: o.ps, host: hostInfo({ ps: twinNames.includes('ps1') ? o.ps : null, bash: o.bash }) } });
  } catch (e) {
    if (e instanceof InfraTimeout) { process.stdout.write(`${e.message}\n`); err('install-parity: a twin step outlived its bound (AAI_PARITY_STEP_TIMEOUT, default 300 s); this is an infrastructure break, not a parity divergence, and no divergence or stale judgement was made'); return EXIT_INFRA; }
    if (e instanceof InfraFixtureTimeout) { process.stdout.write(`${e.message}\n`); err('install-parity: a fixture command outlived its bound; this is an infrastructure break, not a parity divergence, and no divergence or stale judgement was made'); return EXIT_INFRA; }
    throw e;
  } finally {
    if (o.keep) process.stdout.write(`scratch root kept: ${root}\n`); else fs.rmSync(root, { recursive: true, force: true });
  }
  for (const n of rep.notes) process.stdout.write(`${n}\n`);
  for (const s of rep.scenarios) {
    const verdict = s.broken.length ? 'BROKEN' : (s.divergences.some((d) => !d.covered_by) ? 'FAIL' : 'PASS');
    process.stdout.write(`${s.id} ${s.seconds}s ${verdict}\n`);
    for (const b of s.broken) process.stdout.write(`  BROKEN ${s.id}: ${b}\n`);
    // A scenario that is not a PASS prints the tails of every step that exited nonzero, so a CI log shows why a twin failed.
    if (verdict !== 'PASS') {
      for (const st of s.steps) {
        for (const o of st.odd_root_entries || []) process.stdout.write(`  ${s.id} ${st.twin} step ${st.step} left an odd root entry ${o}\n`);
        if (st.doctor_head) process.stdout.write(`  ${s.id} ${st.twin} step ${st.step} doctor report head: ${st.doctor_head.replace(/\s+/g, ' ')}\n`);
        if (st.stderr_tail) process.stdout.write(`  ${s.id} ${st.twin} step ${st.step} exit ${st.code} stderr tail: ${st.stderr_tail.replace(/\s+/g, ' ')}\n`);
        if (st.stdout_tail) process.stdout.write(`  ${s.id} ${st.twin} step ${st.step} exit ${st.code} stdout tail: ${st.stdout_tail.replace(/\s+/g, ' ')}\n`);
      }
    }
  }
  for (const u of rep.uncovered) process.stdout.write(`UNCOVERED ${u.scenario} ${u.pair} ${u.kind} ${showName(u.path)}: ${u.detail}\n`);
  for (const s of rep.stale) process.stdout.write(`STALE ${s.id} (scenario ${s.scenario}, pairs ${s.pairs}, ${s.kind} ${s.path})\n`);
  for (const e of rep.host_checks.filter((x) => x.status === 'fail')) process.stdout.write(`HOST-CHECK FAIL ${e.id} ${e.scenario} ${e.twin}: ${e.detail}\n`);
  if (rep.stale_check !== 'on') process.stdout.write(`stale check: ${rep.stale_check}\n`);
  process.stdout.write(`verdict ${rep.verdict} (${rep.total_seconds}s, matrix ${rep.matrix}, pairs ${rep.pairs.join(' ')})\n`);
  if (o.json) fs.writeFileSync(o.json, `${JSON.stringify(rep, null, 2)}\n`);
  return exitCodeFor(rep);
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
