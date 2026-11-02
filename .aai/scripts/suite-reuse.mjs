#!/usr/bin/env node
//
// suite-reuse.mjs - precise local reuse of a passing suite result
// (CHANGE precise-suite-evidence-reuse / SPEC spec-precise-suite-evidence-reuse).
//
// A suite listed in tests/skills/suite-reuse.json whose identity is unchanged
// since an earlier passing, isolated, attested run is reported REUSED by
// tests/skills/test-framework.sh instead of executed. The identity is keyed on
// the files the suite actually read, found by an access-time trace of its
// disposable checkout (lib/checkout-trace.mjs), not on its source text.
// Every rule errs toward a miss: over-inclusion costs a re-run, never a false
// pass. Node stdlib only; no second glob matcher, map parser or tree lister.
//
// Usage:
//   node .aai/scripts/suite-reuse.mjs check  --root R --run-dir D --mode selected|full
//        --isolation on|off --suite S [--suite S ...] [--seed-paths "a b"]
//   node .aai/scripts/suite-reuse.mjs arm|collect --dir CHECKOUT --run-dir D --suite S [--seed-paths "a b"]
//   node .aai/scripts/suite-reuse.mjs record --root R --run-dir D --suite S
//        --isolation isolated --seeding seeded [--seed-paths "a b"]
//   node .aai/scripts/suite-reuse.mjs forget --root R --suite S
//   node .aai/scripts/suite-reuse.mjs lint    [--root R] [--admit [--suite S ...] [--changed-since REF]]
//   node .aai/scripts/suite-reuse.mjs explain --suite S [--root R]

import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSuiteMap, matchesGlob } from './select-suites.mjs';
import { listTreeFiles } from './lib/tree-hash.mjs';
import { atomicWrite, loadOrDegrade, reapAsides } from './lib/runtime-file.mjs';
import { armTrace, collectTrace } from './lib/checkout-trace.mjs';
import { referencedNames, contentHash } from './lib/checkout-trace.mjs';

const IDENTITY_COMPONENTS = ['inputs', 'paths', 'env', 'args', 'runtime', 'policy', 'history'];
const REUSE_POLICY_VERSION = 2;
const DEFAULT_SEEDS = 'docs/ai/STATE.yaml docs/ai/LOOP_TICKS.jsonl docs/ai/hitl-channel.json';
const MANIFEST_REL = 'tests/skills/suite-reuse.json';
const MAP_REL = 'tests/skills/suite-map.yaml';
const STORE_REL = 'tests/skills/results/reuse';
const HARNESS = [
  'tests/skills/test-framework.sh', '.aai/scripts/aai-run-tests.sh', '.aai/scripts/suite-reuse.mjs',
  '.aai/scripts/lib/checkout-trace.mjs', '.aai/scripts/select-suites.mjs', MAP_REL, MANIFEST_REL,
  '.gitignore',
];
const TEMP_WINDOW_MS = 3600 * 1000;
const ENV_PREFIXES = ['AAI_', 'GIT_', 'NODE_', 'npm_config_'];
const ENV_FIXED = ['PATH', 'HOME', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TZ', 'TMPDIR', 'SHELL'];
const STARTUP_HOOK_VARS = ['BASH_ENV', 'ENV', 'SHELLOPTS', 'BASHOPTS'];
// Any non-empty bash startup hook (a file, exported functions, or inherited shell options)
// changes what a suite executes outside the identity: the reason, or null.
export function shellStartupHazard(env) {
  const e = env || {};
  const hit = STARTUP_HOOK_VARS.find((v) => e[v]) || Object.keys(e).find((k) => k.startsWith('BASH_FUNC_') && e[k]);
  return hit ? 'bash-startup-hook' : null;
}
const ENV_EXCLUDED = ['AAI_SUITE_REUSE', 'AAI_TEST_REF_ID', 'AAI_REAP_STEP_START_EPOCH'];
// Maintained by the shell itself and different for every caller: never an input a suite can be keyed on.
const ENV_NOISE = ['PWD', 'OLDPWD', 'SHLVL', '_'];

const sha256 = (data) => createHash('sha256').update(data).digest('hex');
const posix = (p) => p.split(path.sep).join('/');
function canon(v) {
  if (Array.isArray(v)) return `[${v.map(canon).join(',')}]`;
  if (v && typeof v === 'object') return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canon(v[k])}`).join(',')}}`;
  return JSON.stringify(v === undefined ? null : v);
}
const hashOf = (v) => sha256(canon(v));
function readText(abs) { try { return fs.readFileSync(abs, 'utf8'); } catch { return null; } }
function firstLine(cmd, args) {
  try { return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).split('\n')[0]; } catch { return 'unavailable'; }
}

// ---- manifest (D3) ----
export function loadManifest(root, rel = MANIFEST_REL) {
  const raw = readText(path.join(root, rel));
  if (raw === null) return { state: 'absent', suites: {} };
  let m;
  try { m = JSON.parse(raw); } catch { return { state: 'invalid', suites: {} }; }
  const isObj = (x) => x && typeof x === 'object' && !Array.isArray(x);
  if (!isObj(m) || m.version !== 1 || !isObj(m.suites)) return { state: 'invalid', suites: {} };
  if (Object.keys(m).some((k) => k !== 'version' && k !== 'suites')) return { state: 'invalid', suites: {} };
  for (const e of Object.values(m.suites)) {
    if (!isObj(e) || Object.keys(e).some((k) => !['inputs', 'live', 'note'].includes(k))) return { state: 'invalid', suites: {} };
    if (typeof e.live !== 'boolean' || typeof e.note !== 'string' || e.note.trim() === '') return { state: 'invalid', suites: {} };
    if (!Array.isArray(e.inputs) || e.inputs.some((g) => typeof g !== 'string')) return { state: 'invalid', suites: {} };
  }
  return { state: 'ok', suites: m.suites };
}

// ---- shared context: one listing, one map, one manifest, one hash cache ----
export function loadContext(root, opts = {}) {
  const mapText = readText(path.join(root, MAP_REL));
  const map = mapText === null ? { suites: {}, sharedLibGlobs: [] } : parseSuiteMap(mapText);
  const env = opts.env || process.env;
  const seeds = (opts.seedPaths || env.AAI_TEST_ISOLATION_SEED || DEFAULT_SEEDS).split(/\s+/).filter(Boolean);
  const files = listTreeFiles(root);
  const pathList = [...new Set([...files, ...seeds.filter((s) => fs.existsSync(path.join(root, s)))])].sort();
  return {
    root, map, env, seeds, files, pathList, fileSet: new Set(files), manifest: loadManifest(root, opts.manifestRel),
    runtime: opts.runtime || {
      node: process.version, platform: process.platform, arch: process.arch,
      git: firstLine('git', ['--version']), bash: firstLine('bash', ['--version']),
    },
    policyVersion: opts.policyVersion === undefined ? REUSE_POLICY_VERSION : opts.policyVersion,
    timeoutSeconds: opts.timeoutSeconds !== undefined ? opts.timeoutSeconds : resolveTimeout(env.AAI_TEST_TIMEOUT),
    hashes: new Map(),
  };
}
// Run-ledger files an index-reading suite is compared on the bytes its checkout held, lines appended
// after them tolerated (D1): git's index refresh reads every tracked file, so the framework's own
// append would otherwise make every such suite miss.
const APPEND_ONLY_LEDGERS = ['docs/ai/tests/test-runs.jsonl'];
function resolveTimeout(raw) { return /^[0-9]+$/.test(raw || '') && Number(raw) > 0 ? Number(raw) : 3000; }
function fileHash(ctx, rel) {
  if (!ctx.hashes.has(rel)) {
    let h = 'absent';
    try { const abs = path.join(ctx.root, rel); h = contentHash(fs.readFileSync(abs), fs.statSync(abs).mode); } catch { /* absent or unreadable: a later creation is a change */ }
    ctx.hashes.set(rel, h);
  }
  return ctx.hashes.get(rel);
}
function globMatches(ctx, globs) {
  const out = new Set();
  for (const g of globs) {
    if (!g.includes('*')) { if (ctx.fileSet.has(g)) out.add(g); continue; }
    for (const f of ctx.files) if (matchesGlob(f, g)) out.add(f);
  }
  return out;
}

function appendPrefix(ctx, inputsMap) {
  const out = {};
  for (const p of APPEND_ONLY_LEDGERS) {
    const h = inputsMap[p];
    if (typeof h !== 'string' || h === 'absent') continue;
    try { out[p] = { bytes: fs.statSync(path.join(ctx.root, p)).size, sha256: h }; } catch { /* gone again: no tolerance for it */ }
  }
  return out;
}
function appendedOnly(ctx, p, prefix) {
  try {
    const abs = path.join(ctx.root, p);
    const buf = fs.readFileSync(abs);
    return buf.length >= prefix.bytes && contentHash(buf.subarray(0, prefix.bytes), fs.statSync(abs).mode) === prefix.sha256;
  } catch { return false; }
}

// ---- identity (D3) ----
// A trace is {inputs: {path: arm sha256 or null}, paths, env_names, git_read, index_read}. The check side
// builds it from the store record (hashes then come from the working tree); the record side from the
// trace file of the run (hashes are the bytes the checkout held when the suite started).
const NO_TRACE = { inputs: {}, paths: [], env_names: [], git_read: false, index_read: false };
function historyOf(root) {
  const git = (...a) => { try { return execFileSync('git', ['-C', root, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return 'unavailable'; } };
  return `${git('rev-parse', 'HEAD')}\n${git('for-each-ref', '--format=%(objectname) %(refname)')}`;
}
function prefixEnv(ctx) {
  const envMap = {};
  for (const name of Object.keys(ctx.env)) {
    if ((ENV_PREFIXES.some((p) => name.startsWith(p)) || ENV_FIXED.includes(name)) && !ENV_EXCLUDED.includes(name)) envMap[name] = ctx.env[name];
  }
  return envMap;
}
function harnessMap(ctx, suite) {
  const entry = ctx.manifest.suites[suite];
  const wanted = new Set([`tests/skills/test-${suite}.sh`, ...HARNESS]);
  if (entry) for (const f of globMatches(ctx, entry.inputs)) wanted.add(f);
  const map = {};
  for (const rel of [...wanted].sort()) map[rel] = fileHash(ctx, rel);
  return map;
}
// Everything a run can move under the suite: env, runtime, policy, history, harness bytes.
function stableOf(ctx, suite) {
  return hashOf({ env: prefixEnv(ctx), runtime: ctx.runtime, policy: policyOf(ctx), hist: historyOf(ctx.root), harness: harnessMap(ctx, suite) });
}
const policyOf = (ctx) => ({ policy_version: ctx.policyVersion, trace: 'atime', timeout_seconds: ctx.timeoutSeconds, isolation: 'isolated', seed_paths: ctx.seeds });

export function computeIdentity(ctx, suite, args, trace = NO_TRACE, recorded = false) {
  const inputsMap = harnessMap(ctx, suite);
  const armed = (p) => (recorded && typeof trace.inputs[p] === 'string' ? trace.inputs[p] : null);
  for (const p of Object.keys(trace.inputs)) if (!p.startsWith('.git/')) inputsMap[p] = armed(p) || fileHash(ctx, p);
  const pathList = recorded ? [...trace.paths].sort() : ctx.pathList;
  if (trace.index_read) {
    for (const p of pathList) if (!(p in inputsMap)) inputsMap[p] = (recorded && trace.tree_hashes && trace.tree_hashes[p]) || fileHash(ctx, p);
  }
  if (!recorded) {
    for (const p of APPEND_ONLY_LEDGERS) {
      const tolerate = trace.index_read && trace.append_prefix && trace.append_prefix[p];
      if (tolerate && p in inputsMap && appendedOnly(ctx, p, tolerate)) inputsMap[p] = tolerate.sha256;
    }
  }
  const envMap = prefixEnv(ctx);
  for (const name of trace.env_names.filter((n) => !ENV_NOISE.includes(n))) envMap[name] = ctx.env[name] === undefined ? null : ctx.env[name];
  const history = trace.git_read ? historyOf(ctx.root) : '';
  const values = { inputs: inputsMap, paths: pathList, env: envMap, args, runtime: ctx.runtime, policy: policyOf(ctx), history };
  const components = {};
  for (const c of IDENTITY_COMPONENTS) components[c] = hashOf(values[c]);
  return { suite, identity: hashOf(components), components, inputs_map: inputsMap, paths: pathList, args };
}

// First differing component (in IDENTITY_COMPONENTS order); null when equal.
export function diffIdentity(recorded, current) {
  for (const c of IDENTITY_COMPONENTS) {
    if (recorded.components[c] === current.components[c]) continue;
    if (c === 'paths') {
      const a = new Set(recorded.paths || []);
      const b = new Set(current.paths);
      const added = current.paths.find((p) => !a.has(p));
      if (added !== undefined) return { reason: 'paths', detail: `added ${added}` };
      const gone = (recorded.paths || []).find((p) => !b.has(p));
      return gone === undefined ? { reason: 'paths' } : { reason: 'paths', detail: `removed ${gone}` };
    }
    if (c !== 'inputs') return { reason: c };
    const a = recorded.inputs_map || {};
    const b = current.inputs_map;
    for (const p of [...new Set([...Object.keys(a), ...Object.keys(b)])].sort()) {
      if (a[p] === b[p]) continue;
      const was = a[p] === undefined || a[p] === 'absent';
      const now = b[p] === undefined || b[p] === 'absent';
      return { reason: 'inputs', detail: `${was ? 'added' : now ? 'removed' : 'changed'} ${p}` };
    }
    return { reason: 'inputs' };
  }
  return null;
}

// ---- store ----
const storeFile = (root, suite) => path.join(root, STORE_REL, `${suite}.json`);
function readStore(root, suite) {
  return loadOrDegrade(storeFile(root, suite), { isShape: (v) => v !== null && typeof v === 'object' && !Array.isArray(v) });
}
export function forgetSuite({ root, suite }) {
  try { fs.unlinkSync(storeFile(root, suite)); return true; } catch { return false; }
}
function offReason(env, mode, isolation) {
  if ((env.CI && env.CI !== 'false') || env['GITHUB_ACTIONS'] === 'true') return 'ci';
  if (env.AAI_SUITE_REUSE === '0') return 'opt-out';
  if (mode === 'full') return 'full-sweep';
  if (isolation === 'off') return 'isolation-off';
  return null;
}

// ---- check (D5) ----
function traceOfRecord(rec) {
  const t = rec && rec.schema === 2 && rec.trace;
  if (!t || !Array.isArray(t.input_paths) || !Array.isArray(t.env_names)) return undefined;
  return { inputs: Object.fromEntries(t.input_paths.map((p) => [p, null])), paths: [], env_names: t.env_names, git_read: t.git_read === true, index_read: t.index_read === true, append_prefix: rec.append_prefix && typeof rec.append_prefix === 'object' ? rec.append_prefix : {} };
}
export function checkSuites({ root, suites, mode = 'selected', isolation = 'on', runDir, args, env, runtime, seedPaths, policyVersion, timeoutSeconds }) {
  const ctx = loadContext(root, { env, runtime, seedPaths, policyVersion, timeoutSeconds });
  const off = offReason(ctx.env, mode, isolation);
  const results = [];
  const trace = [];
  for (const suite of suites) {
    const argv = args && !Array.isArray(args) ? args[suite] : args || ['bash', `tests/skills/test-${suite}.sh`];
    // An identity is only ever compared or recorded for a declared, non-live suite.
    const entry = ctx.manifest.suites[suite];
    const declared = ctx.manifest.state === 'ok' && entry && entry.live === false;
    const loaded = declared ? readStore(root, suite) : { status: 'missing', data: null };
    const rec = loaded.status === 'corrupt' ? null : loaded.data;
    const id = off === 'ci' || off === 'opt-out' || !declared ? null : computeIdentity(ctx, suite, argv, traceOfRecord(rec));
    if (id && runDir) {
      fs.mkdirSync(runDir, { recursive: true });
      fs.writeFileSync(path.join(runDir, `${suite}.reuse-identity.json`), JSON.stringify({ identity: id.identity, args: argv, stable: stableOf(ctx, suite) }));
    }
    if (declared && (!off || off === 'full-sweep')) trace.push(suite);
    if (off) { results.push({ suite, off }); continue; }
    results.push({ suite, ...decide(ctx, suite, id, loaded) });
  }
  return { off, results, trace };
}
function decide(ctx, suite, id, loaded) {
  const entry = ctx.manifest.suites[suite];
  // A bash startup hook (BASH_ENV, ENV) runs code outside the identity: fail closed, never hash it.
  if (shellStartupHazard(ctx.env)) return { status: 'RUN', reason: 'bash-startup-hook' };
  if (ctx.manifest.state === 'invalid') return { status: 'RUN', reason: 'manifest-invalid' };
  if (!entry) return { status: 'RUN', reason: 'not-declared' };
  if (entry.live !== false) return { status: 'RUN', reason: 'live' };
  if (loaded.status === 'corrupt') return { status: 'RUN', reason: 'store-corrupt' };
  const rec = loaded.data;
  if (!rec || !rec.components) return { status: 'RUN', reason: 'no-record' };
  if (!traceOfRecord(rec)) return { status: 'RUN', reason: 'policy', detail: 'record predates the access trace' };
  const d = diffIdentity(rec, id);
  if (d) return { status: 'RUN', ...d };
  const logAbs = path.join(ctx.root, rec.log || '');
  let logHash = null;
  try { logHash = sha256(fs.readFileSync(logAbs)); } catch { /* missing log */ }
  if (!rec.log || logHash !== rec.log_sha256) return { status: 'RUN', reason: 'log-missing' };
  return { status: 'REUSE', run: rec.run_id, at: rec.finished_at, log: rec.log, identity: id.identity };
}
export function formatCheck(r) {
  if (r.off) return `OFF ${r.off}`;
  if (r.status === 'REUSE') return `REUSE ${r.suite} run=${r.run} at=${r.at} log=${r.log}`;
  return `RUN ${r.suite} reason=${r.reason}${r.detail ? ` ${r.detail}` : ''}`;
}

// ---- record (D4) ----
function readJson(abs) { try { return JSON.parse(fs.readFileSync(abs, 'utf8')); } catch { return null; } }
export function recordSuite({ root, suite, runDir, metrics, isolation = 'isolated', seeding = 'seeded', env, runtime, seedPaths, policyVersion, timeoutSeconds, now = new Date() }) {
  const e = env || process.env;
  const off = offReason(e, 'selected', 'on');
  if (off === 'ci' || off === 'opt-out') return { recorded: false, off };
  const no = (reason) => ({ recorded: false, reason });
  // A pass produced under a startup hook is never stored, and a stale record cannot survive it.
  if (shellStartupHazard(e)) { forgetSuite({ root, suite }); return no('bash-startup-hook'); }
  let m = metrics;
  if (!m) {
    const lines = (readText(path.join(runDir, 'metrics.jsonl')) || '').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return {}; } });
    m = lines.filter((x) => x.skill === suite).pop() || {};
  }
  if (m.status !== 'PASS' || m.exit_code !== 0) return no('not-pass');
  if (m.tripwire_attested !== true || m.tripwire_hasher_degraded !== false) return no('not-attested');
  if (isolation !== 'isolated' || seeding !== 'seeded') return no('not-isolated');
  const before = readJson(path.join(runDir, `${suite}.reuse-identity.json`));
  if (!before || typeof before !== 'object' || !Array.isArray(before.args)) return no('no-identity');
  // Decided before any context is loaded: a missing or foreign trace is a clean refusal, never a throw.
  const trace = readJson(path.join(runDir, `${suite}.reuse-trace.json`));
  const isObj = (x) => x && typeof x === 'object' && !Array.isArray(x);
  if (!isObj(trace) || trace.suite !== suite || trace.run_id !== path.basename(runDir) || !isObj(trace.inputs) || !Array.isArray(trace.paths) || !Array.isArray(trace.env_names)) return no('no-trace');
  if (!trace.canary) return no('trace-unavailable');
  const ctx = loadContext(root, { env: e, runtime, seedPaths, policyVersion, timeoutSeconds });
  const entry = ctx.manifest.suites[suite];
  if (ctx.manifest.state !== 'ok' || !entry || entry.live !== false) return no('not-declared');
  if (stableOf(ctx, suite) !== before.stable) return no('inputs-changed-during-run');
  const texts = Object.keys(trace.inputs).filter((p) => !p.startsWith('.git/')).map((p) => readText(path.join(root, p))).filter((t) => t !== null);
  const names = [...new Set([...trace.env_names, ...referencedNames(texts)])].sort();
  const traced = { ...trace, env_names: names, git_read: trace.git_read === true, index_read: trace.index_read === true };
  const after = computeIdentity(ctx, suite, before.args, traced, true);
  const logAbs = path.join(runDir, `${suite}.log`);
  let logHash;
  try { logHash = sha256(fs.readFileSync(logAbs)); } catch { return no('log-missing'); }
  const rec = {
    schema: 2, suite, identity: after.identity, components: after.components, inputs_map: after.inputs_map, paths: after.paths,
    trace: { input_paths: Object.keys(trace.inputs).filter((p) => !p.startsWith('.git/')).sort(), index_read: traced.index_read, git_read: traced.git_read, env_names: names },
    append_prefix: traced.index_read ? appendPrefix(ctx, after.inputs_map) : undefined,
    run_id: path.basename(runDir), finished_at: now.toISOString(), duration_seconds: m.duration_seconds || 0,
    exit_code: 0, log: posix(path.relative(root, logAbs)), log_sha256: logHash,
  };
  const dest = storeFile(root, suite);
  atomicWrite(dest, JSON.stringify(rec, null, 2));
  reapAsides(path.dirname(dest), `${suite}.json.tmp.`, Date.now(), TEMP_WINDOW_MS);
  return { recorded: true, identity: after.identity };
}

// ---- lint (D3) ----
export function lintManifest({ root }) {
  const man = loadManifest(root);
  if (man.state !== 'ok') return { ok: false, problems: [{ suite: '-', reason: man.state === 'absent' ? 'manifest-absent' : 'manifest-invalid' }] };
  const mapText = readText(path.join(root, MAP_REL));
  const rows = mapText === null ? {} : parseSuiteMap(mapText).suites;
  const problems = [];
  if (Object.keys(man.suites).length && !rows['aai-suite-reuse']) problems.push({ suite: '-', reason: 'gate-row-missing' });
  for (const suite of Object.keys(man.suites)) {
    if (!rows[suite]) problems.push({ suite, reason: 'not-in-suite-map' });
    if (!fs.existsSync(path.join(root, `tests/skills/test-${suite}.sh`))) problems.push({ suite, reason: 'no-suite-file' });
    else if (rows['aai-suite-reuse'] && !rows['aai-suite-reuse'].globs.some((g) => matchesGlob(`tests/skills/test-${suite}.sh`, g))) problems.push({ suite, reason: 'not-gate-selected' });
  }
  return { ok: problems.length === 0, problems };
}

// ---- admission gate (D5): lint --admit ----
// A suite may stay in the manifest only if, from a scratch copy of the working tree, it passes through the
// framework with a trace, every Node content read it made is in the trace, one read and one unread edit move
// `check` the right way, and it still passes when every file it did not read is overwritten.
const CONTENT_FNS = new Set(['readFileSync', 'readFile', 'createReadStream', 'promises.readFile']);
const ANSI_RE = /\x1b\[[0-9;]*m/g;
const admitEnv = (extra = {}) => {
  const e = { ...process.env, ...extra };
  for (const k of ['AAI_ROLE', 'CI', 'GITHUB_ACTIONS', 'AAI_TEST_REF_ID', 'AAI_SUITE_REUSE']) delete e[k];
  return e;
};
const run = (cmd, args, opts) => spawnSync(cmd, args, { encoding: 'utf8', maxBuffer: 1 << 28, ...opts });
function scratchRepo(root, tmp, name) {
  const dest = path.join(tmp, name);
  if (run('git', ['clone', '--local', '--no-hardlinks', '--quiet', root, dest]).status !== 0) return null;
  for (const [k, v] of [['user.email', 'admit@example.invalid'], ['user.name', 'admit'], ['commit.gpgsign', 'false']]) run('git', ['-C', dest, 'config', k, v]);
  const seeds = DEFAULT_SEEDS.split(' ').filter((s) => fs.existsSync(path.join(root, s)));
  const working = new Set([...listTreeFiles(root), ...seeds]);
  for (const f of run('git', ['-C', dest, 'ls-files', '-z']).stdout.split('\0').filter(Boolean)) if (!working.has(f)) fs.rmSync(path.join(dest, f), { force: true });
  for (const f of working) { fs.mkdirSync(path.dirname(path.join(dest, f)), { recursive: true }); fs.cpSync(path.join(root, f), path.join(dest, f), { dereference: false }); }
  return dest;
}
// Node content reads, from the preload log, of a file that existed in the checkout at arm and is not a trace input.
export function nodeReadsMissing(lines, arm, trace) {
  const dirs = [arm.dir, arm.dir.replace(/^\/private/, ''), `/private${arm.dir}`];
  const missing = new Set();
  for (const line of lines) {
    const [kind, p, fn] = line.split('\t');
    if (kind !== 'R' || !CONTENT_FNS.has(fn)) continue;
    const d = dirs.find((x) => p.startsWith(`${x}/`));
    const rel = d ? p.slice(d.length + 1) : null;
    if (rel && rel in arm.inodes && !(rel in trace.inputs)) missing.add(rel);
  }
  return [...missing].sort();
}
const poisonFile = (abs, rel) => fs.writeFileSync(abs, `AAI-REUSE-POISON ${rel}\n`);
function probe(dir, suite, env, { rel, label, expect }) {
  const abs = path.join(dir, rel);
  const had = fs.existsSync(abs) ? fs.readFileSync(abs) : null;
  if (had === null) fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.appendFileSync(abs, 'x');
  let out;
  try { out = run(process.execPath, [fileURLToPath(import.meta.url), 'check', '--root', dir, '--run-dir', path.join(dir, 'tests/skills/results/admit-probe'), '--mode', 'selected', '--isolation', 'on', '--suite', suite], { env, cwd: dir }).stdout; }
  finally { if (had === null) fs.rmSync(abs, { force: true }); else fs.writeFileSync(abs, had); }
  const got = out.split('\n')[0] || '(nothing)';
  const ok = new RegExp(`^${expect} ${suite}\\b${expect === 'RUN' ? ' reason=inputs' : ''}`).test(got);
  return { ok, line: `${label} ${rel} ${got.split(' ')[0]}`, why: `${label} probe on ${rel} gave: ${got}` };
}
function admitSuite(root, suite, tmp) {
  const t0 = Date.now();
  const fail = (reason) => ({ suite, ok: false, seconds: (Date.now() - t0) / 1000, reason });
  const dir = scratchRepo(root, tmp, `${suite}-a`);
  if (!dir) return fail('scratch-repo');
  const tracer = path.join(root, 'tests/skills/lib/read-trace.cjs');
  if (!fs.existsSync(tracer)) return fail('no-read-trace');
  const log = path.join(tmp, `${suite}.nodetrace`);
  fs.writeFileSync(log, '');
  const env = admitEnv({ AAI_TEST_PARALLEL: '1', AAI_TRACE_OUT: log, NODE_OPTIONS: `${process.env.NODE_OPTIONS || ''} --require ${tracer}`.trim() });
  // The framework appends a line to the tracked run ledger after the suite; put it back so the probes start from the state the suite read.
  const ledger = path.join(dir, 'docs/ai/tests/test-runs.jsonl');
  const ledgerWas = fs.existsSync(ledger) ? fs.readFileSync(ledger) : null;
  const r1 = run('bash', ['tests/skills/test-framework.sh', '--skill', suite], { cwd: dir, env, timeout: 1800000 });
  if (ledgerWas !== null) fs.writeFileSync(ledger, ledgerWas);
  const plain = `${r1.stdout}${r1.stderr}`.replace(ANSI_RE, '');
  if (r1.status !== 0 || !/Passed:\s+1 \(100%\)/.test(plain) || /Failed:|Skipped:/.test(plain)) return fail(`fresh-run-failed rc=${r1.status} ${plain.split('\n').filter((l) => /FAIL/.test(l)).slice(0, 3).join(' | ').slice(0, 300)}`);
  const runs = path.join(dir, 'tests/skills/results');
  const latest = fs.readdirSync(runs).filter((n) => n.startsWith('test-')).sort().pop();
  const trace = readJson(path.join(runs, latest || '', `${suite}.reuse-trace.json`));
  const arm = readJson(path.join(runs, latest || '', `${suite}.reuse-arm.json`));
  if (!trace || !arm || !readJson(storeFile(dir, suite))) return fail('no-record (trace or store missing)');
  const lines = fs.readFileSync(log, 'utf8').split('\n').filter(Boolean);
  const missed = nodeReadsMissing(lines, arm, trace);
  if (missed.length) return fail(`trace-misses-node-read ${missed[0]}`);
  const inputs = Object.keys(trace.inputs).filter((p) => !p.startsWith('.git/')).sort();
  const ctx = loadContext(dir, { env });
  const harness = harnessMap(ctx, suite);
  const readProbe = inputs.find((p) => !(p in harness));
  const unread = trace.index_read ? null : trace.paths.find((p) => !(p in trace.inputs) && !(p in harness));
  const probes = [
    readProbe && probe(dir, suite, env, { rel: readProbe, label: 'read', expect: 'RUN' }),
    probe(dir, suite, env, { rel: unread || 'tests/skills/results/admit-probe.txt', label: 'unread', expect: 'REUSE' }),
  ].filter(Boolean);
  const bad = probes.find((x) => !x.ok);
  if (bad) return fail(bad.why);
  const toPoison = trace.index_read ? [] : trace.paths.filter((p) => !(p in trace.inputs) && !p.startsWith('.git/'));
  if (toPoison.length) {
    const pdir = scratchRepo(root, tmp, `${suite}-p`);
    if (!pdir) return fail('scratch-repo');
    for (const rel of toPoison) {
      const abs = path.join(pdir, rel);
      if (fs.existsSync(abs)) poisonFile(abs, rel);
    }
    const r = run('bash', [`tests/skills/test-${suite}.sh`], { cwd: pdir, env: admitEnv({ AAI_SUITE_REUSE: '0' }), timeout: 1800000 });
    const passed = r.status === 0;
    if (!passed) return fail(`poisoned run failed rc=${r.status}`);
  }
  return { suite, ok: true, seconds: (Date.now() - t0) / 1000, reads: inputs.length, poisoned: toPoison.length, probes: probes.map((x) => x.line) };
}
// base: {root, ref, manifest} or null when the ref does not resolve (then every suite is admitted).
function entryChanged(base, suite) {
  if (!base) return true;
  const was = base.manifest && base.manifest.suites ? base.manifest.suites[suite] : undefined;
  if (canon(was) !== canon(loadManifest(base.root).suites[suite])) return true;
  const file = `tests/skills/test-${suite}.sh`;
  return run('git', ['-C', base.root, 'cat-file', '-e', `${base.ref}:${file}`]).status !== 0
    || run('git', ['-C', base.root, 'diff', '--quiet', base.ref, '--', file]).status !== 0;
}
function changedBase(root, ref) {
  if (!ref || run('git', ['-C', root, 'rev-parse', '--verify', '-q', `${ref}^{commit}`]).status !== 0) return null;
  const shown = run('git', ['-C', root, 'show', `${ref}:${MANIFEST_REL}`]);
  let manifest = null;
  try { manifest = JSON.parse(shown.stdout); } catch { /* no manifest at the ref: every entry is new */ }
  return { root, ref, manifest };
}
export function admitSuites({ root, suites, changedSince }) {
  const names = suites.length ? suites : Object.keys(loadManifest(root).suites);
  const base = changedSince ? changedBase(root, changedSince) : null;
  const picked = changedSince ? names.filter((s) => entryChanged(base, s)) : names;
  const tmp = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'suite-reuse-admit-'));
  try { return picked.map((s) => admitSuite(root, s, tmp)); } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
}


// ---- explain: what the suite's last record read ----
export function explainSuite({ root, suite }) {
  const loaded = readStore(root, suite);
  const rec = loaded.status === 'corrupt' ? null : loaded.data;
  const t = traceOfRecord(rec);
  if (!t) return { suite, record: false };
  const top = {};
  for (const p of rec.trace.input_paths) { const k = p.split('/').slice(0, p.startsWith('docs/') || p.startsWith('.aai/') || p.startsWith('tests/') ? 2 : 1).join('/'); top[k] = (top[k] || 0) + 1; }
  return { suite, record: true, run: rec.run_id, count: rec.trace.input_paths.length, top, git_read: t.git_read, index_read: t.index_read, env_names: t.env_names };
}

// ---- CLI ----
function parseArgs(argv) {
  const o = { suites: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--suite') o.suites.push(argv[++i]);
    else if (a === '--admit') o.admit = true;
    else if (a.startsWith('--')) o[a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = argv[++i];
  }
  return o;
}
function cli(argv) {
  const [cmd, ...rest] = argv;
  const o = parseArgs(rest);
  const root = path.resolve(o.root || path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..'));
  const out = (s) => process.stdout.write(`${s}\n`);
  if (cmd === 'check') {
    const r = checkSuites({ root, suites: o.suites, mode: o.mode, isolation: o.isolation, runDir: o.runDir, seedPaths: o.seedPaths });
    if (r.off) out(`OFF ${r.off}`); else r.results.forEach((x) => out(formatCheck(x)));
    r.trace.forEach((s) => out(`TRACE ${s}`));
  } else if (cmd === 'arm' || cmd === 'collect') {
    const dir = path.resolve(o.dir || '');
    const runDir = path.resolve(o.runDir || '');
    if (!o.dir || !o.runDir || !o.suites[0] || overlaps(dir, root)) { process.stderr.write(`${cmd}: needs --dir (a disposable checkout that neither contains nor sits inside --root), --run-dir and --suite\n`); process.exitCode = 2; return; }
    try {
      if (cmd === 'arm') {
        const arm = armTrace({ dir, runDir, suite: o.suites[0], seedPaths: (o.seedPaths || DEFAULT_SEEDS).split(/\s+/).filter(Boolean) });
        out(`ARMED ${o.suites[0]} canary=${arm.canary}`);
      } else {
        const t = collectTrace({ dir, runDir, suite: o.suites[0] });
        out(t ? `COLLECTED ${o.suites[0]} inputs=${Object.keys(t.inputs).length}` : `NO-ARM ${o.suites[0]}`);
      }
    } catch (err) { process.stderr.write(`${cmd} failed: ${err.message}\n`); process.exitCode = 1; }
  } else if (cmd === 'record') {
    for (const suite of o.suites) {
      const r = recordSuite({ root, suite, runDir: o.runDir, isolation: o.isolation, seeding: o.seeding, seedPaths: o.seedPaths });
      out(r.recorded ? `RECORDED ${suite}` : r.off ? `OFF ${r.off}` : `NOT-RECORDED ${suite} reason=${r.reason}`);
    }
  } else if (cmd === 'forget') {
    o.suites.forEach((suite) => { forgetSuite({ root, suite }); out(`FORGOT ${suite}`); });
  } else if (cmd === 'lint') {
    if (rest.includes('--minimal-tree')) { process.stderr.write('lint: --minimal-tree was replaced by --admit\n'); process.exitCode = 2; return; }
    const r = lintManifest({ root });
    r.problems.forEach((p) => out(`${p.suite} ${p.reason}`));
    process.exitCode = r.ok ? 0 : 1;
    if (o.admit && r.ok) {
      if ((process.env.CI && process.env.CI !== 'false') || process.env.GITHUB_ACTIONS === 'true') { out('ADMIT-OFF ci'); return; }
      const res = admitSuites({ root, suites: o.suites, changedSince: o.changedSince });
      if (!res.length) out('ADMIT-NONE');
      for (const x of res) {
        (x.probes || []).forEach((l) => out(`ADMIT-PROBE ${x.suite} ${l}`));
        out(x.ok ? `ADMIT-PASS ${x.suite} ${x.seconds}s reads=${x.reads} poisoned=${x.poisoned}` : `ADMIT-FAIL ${x.suite} ${x.seconds}s ${x.reason}`);
      }
      if (res.some((x) => !x.ok)) process.exitCode = 1;
    }
  } else if (cmd === 'explain') {
    const r = explainSuite({ root, suite: o.suites[0] });
    if (!r.record) out(`suite ${r.suite}: no record`);
    else {
      out(`suite ${r.suite}: ${r.count} input file(s), git directory ${r.git_read ? 'read' : 'not read'}, git index ${r.index_read ? 'read' : 'not read'}, run ${r.run}`);
      Object.keys(r.top).sort().forEach((k) => out(`  ${k} ${r.top[k]}`));
      out(`  env ${r.env_names.join(',') || '-'}`);
    }
  } else {
    process.stderr.write('usage: suite-reuse.mjs check|arm|collect|record|forget|lint|explain ...\n');
    process.exitCode = 2;
  }
}
// true when either real path equals or contains the other; the trailing separator keeps /a/b and /a/bc apart
function overlaps(a, b) {
  const [x, y] = [realOrResolve(a), realOrResolve(b)].map((p) => (p.endsWith(path.sep) ? p : p + path.sep));
  return x.startsWith(y) || y.startsWith(x);
}
// .native returns the on-disk letter case on case-insensitive volumes, so /r/repo and /r/REPO compare equal
function realOrResolve(p) { try { return fs.realpathSync.native(p); } catch { return path.resolve(p); } }
const isMain = process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url));
if (isMain) cli(process.argv.slice(2));
export { IDENTITY_COMPONENTS, REUSE_POLICY_VERSION };
