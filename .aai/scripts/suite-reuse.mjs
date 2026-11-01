#!/usr/bin/env node
//
// suite-reuse.mjs - precise local reuse of a passing suite result
// (CHANGE precise-suite-evidence-reuse / SPEC spec-precise-suite-evidence-reuse).
//
// A suite listed in tests/skills/suite-reuse.json whose declared input
// identity is unchanged since an earlier passing, isolated, attested run is
// reported REUSED by tests/skills/test-framework.sh instead of executed.
// Every rule errs toward a miss: over-inclusion costs a re-run, never a false
// pass. Node stdlib only; no second glob matcher, map parser or tree lister.
//
// Usage:
//   node .aai/scripts/suite-reuse.mjs check  --root R --run-dir D --mode selected|full
//        --isolation on|off --suite S [--suite S ...] [--seed-paths "a b"]
//   node .aai/scripts/suite-reuse.mjs record --root R --run-dir D --suite S
//        --isolation isolated --seeding seeded [--seed-paths "a b"]
//   node .aai/scripts/suite-reuse.mjs forget --root R --suite S
//   node .aai/scripts/suite-reuse.mjs lint    [--root R] [--minimal-tree [--manifest FILE] [--suite S ...]]
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

const IDENTITY_COMPONENTS = ['inputs', 'env', 'args', 'runtime', 'policy', 'history'];
const REUSE_POLICY_VERSION = 1;
const DEFAULT_SEEDS = 'docs/ai/STATE.yaml docs/ai/LOOP_TICKS.jsonl docs/ai/hitl-channel.json';
const MANIFEST_REL = 'tests/skills/suite-reuse.json';
const MAP_REL = 'tests/skills/suite-map.yaml';
const STORE_REL = 'tests/skills/results/reuse';
const HARNESS = [
  'tests/skills/test-framework.sh', '.aai/scripts/aai-run-tests.sh', '.aai/scripts/suite-reuse.mjs',
  '.aai/scripts/select-suites.mjs', MAP_REL, MANIFEST_REL, '.gitignore',
];
const TEMP_WINDOW_MS = 3600 * 1000;
const ENV_PREFIXES = ['AAI_', 'GIT_', 'NODE_', 'npm_config_'];
const ENV_FIXED = ['PATH', 'HOME', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TZ', 'TMPDIR', 'SHELL'];
const ENV_EXCLUDED = ['AAI_SUITE_REUSE', 'AAI_TEST_REF_ID', 'AAI_REAP_STEP_START_EPOCH'];
const HISTORY_RE = /git log|rev-parse|merge-base|git diff|git show|git describe/;
const MARKER_RE = /gh api|gh pr|curl |ls-remote|git push|git fetch|https?:\/\//;

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
  return {
    root, map, env, seeds, files, fileSet: new Set(files), manifest: loadManifest(root, opts.manifestRel),
    runtime: opts.runtime || {
      node: process.version, platform: process.platform, arch: process.arch,
      git: firstLine('git', ['--version']), bash: firstLine('bash', ['--version']),
    },
    policyVersion: opts.policyVersion === undefined ? REUSE_POLICY_VERSION : opts.policyVersion,
    timeoutSeconds: opts.timeoutSeconds !== undefined ? opts.timeoutSeconds : resolveTimeout(env.AAI_TEST_TIMEOUT),
    hashes: new Map(),
  };
}
function resolveTimeout(raw) { return /^[0-9]+$/.test(raw || '') && Number(raw) > 0 ? Number(raw) : 3000; }
function fileHash(ctx, rel) {
  if (!ctx.hashes.has(rel)) {
    let h = 'absent';
    try { h = sha256(fs.readFileSync(path.join(ctx.root, rel))); } catch { /* absent or unreadable: a later creation is a change */ }
    ctx.hashes.set(rel, h);
  }
  return ctx.hashes.get(rel);
}
function underDir(ctx, dir) {
  const prefix = dir.endsWith('/') ? dir : `${dir}/`;
  return ctx.files.filter((f) => f.startsWith(prefix));
}
function globMatches(ctx, globs) {
  const out = new Set();
  for (const g of globs) {
    if (!g.includes('*')) { if (ctx.fileSet.has(g)) out.add(g); continue; }
    for (const f of ctx.files) if (matchesGlob(f, g)) out.add(f);
  }
  return out;
}

// ---- static closure (D4 inputs rule d) ----
// A token is a top-level name (.aai, tests, docs) followed by path characters,
// or the bare name itself when a quote, "=", "(" or "/" precedes it ("$ROOT/docs").
const TOKEN_RE = /(?<![\w.-])(?:\.aai|tests|docs)(?:\/[A-Za-z0-9_./@+-]*|(?<=[/"'=(](?:\.aai|tests|docs))(?![\w-]|\.\w))/g;
const LIB_RE = /(?<![\w.-])lib\/([A-Za-z0-9_.-]+)/g;
const IMPORT_RE = /(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s+)['"](\.{1,2}\/[^'"]+)['"]/g;
const SCRIPT_DIR_RE = /\$\{?SCRIPT_DIR\}?\/([A-Za-z0-9_./@+-]*)/g;
const DIRNAME_RE = /\$\(\s*dirname\s+([^)]*)\)\/([A-Za-z0-9_./@+-]*)/g;
const OWN_DIR_RE = /BASH_SOURCE|\$\{?0\}?(?![\w])/;
const DYNAMIC_NEXT_RE = /[$*?[{]/;
// Fail closed (D4): a reference holding an expansion is accepted only as a known
// base plus a fully literal directory prefix; anything else is unresolved.
const ROOT_VAR = '(?:PROJECT_ROOT|REPO_ROOT|ROOT_DIR|ROOT|REPO_DIR|REPO|PROJECT_DIR|AAI_ROOT)';
const ROOT_VAR_NAME_RE = new RegExp(`^${ROOT_VAR}$`);
const ROOT_THEN_EXPANSION_RE = new RegExp(`\\$\\{?${ROOT_VAR}\\}?/(?:\\.{1,2}/)*(?=[$\`])`, 'g');
const ASSIGN_RE = /^[ \t]*(?:(?:export|readonly|local|declare)\s+)*([A-Za-z_]\w*)=(.*)$/gm;
const CD_OWN_RE = /\bcd\s+"?\$\(\s*dirname\s+[^)]*(?:BASH_SOURCE|\$\{?0\}?)[^)]*\)/g;
const CONCAT_RE = /(?<![\w.-])(?:\.aai|tests|docs)["']\//g;
const QUOTE_CLOSED_RE = /^["'](?:[$`\w/"'])/;
export function computeClosure(ctx, suite) {
  const start = `tests/skills/test-${suite}.sh`;
  const closure = new Set([start]);
  const queue = [start];
  const named = new Set();
  const texts = new Map();
  const dirs = [];
  const unresolved = [];
  while (queue.length) {
    const rel = queue.shift();
    const text = readText(path.join(ctx.root, rel));
    if (text === null) continue;
    texts.set(rel, text);
    const add = (p) => {
      named.add(p);
      if (!closure.has(p)) { closure.add(p); queue.push(p); }
    };
    // dynamic: the literal ends where a variable or glob begins, so its last
    // segment is only a prefix and the deepest fully literal directory is named.
    const addPath = (raw, dynamic) => {
      let p = dynamic ? raw.slice(0, raw.lastIndexOf('/') + 1) : raw.replace(/[.,:;)]+$/, '');
      if (!p) { unresolved.push(`${raw}<expansion> <- ${rel}`); return; }
      // Dot segments collapse like the filesystem does; a path that leaves the repository names nothing the helper can hash.
      const trail = p.endsWith('/');
      p = path.posix.normalize(p);
      if (p === '.' || p === './' || p === '..' || p.startsWith('../')) { unresolved.push(`${raw} leaves the repository <- ${rel}`); return; }
      if (trail && !p.endsWith('/')) p += '/';
      if (p.endsWith('/') || (!ctx.fileSet.has(p) && underDir(ctx, p).length)) {
        dirs.push(`${p} <- ${rel} (${underDir(ctx, p).length} files)`);
        for (const f of underDir(ctx, p)) add(f);
      } else add(p);
    };
    if (rel.startsWith('tests/')) {
      for (const m of text.matchAll(TOKEN_RE)) {
        if (/[%#]\*?\/$/.test(text.slice(Math.max(0, m.index - 4), m.index))) continue; // ${X%/tests/skills} strips a suffix, it reads nothing
        const end = m.index + m[0].length;
        if (QUOTE_CLOSED_RE.test(text.slice(end, end + 2))) { unresolved.push(`${m[0]} closed by a quote before more text <- ${rel}`); continue; }
        addPath(m[0], DYNAMIC_NEXT_RE.test(text.charAt(end)));
      }
      for (const m of text.matchAll(CONCAT_RE)) unresolved.push(`${m[0]} concatenated <- ${rel}`);
      for (const m of text.matchAll(ROOT_THEN_EXPANSION_RE)) unresolved.push(`${m[0]}<expansion> <- ${rel}`);
      if (rel.startsWith('tests/skills/')) for (const m of text.matchAll(LIB_RE)) add(`tests/skills/lib/${m[1]}`);
      // A reference relative to the file's own directory outside lib/ (which LIB_RE
      // covers) is resolved against that directory when the file derives it from its
      // own location, then handled like a path literal (file, directory, or deepest
      // literal directory of a partly built path); else the suite is not reusable.
      // A bare ../.. names nothing only when it computes a known repo-root variable.
      const ownDir = path.posix.dirname(rel);
      const lineStart = (at) => text.lastIndexOf('\n', at - 1) + 1;
      const lineOf = (at) => { const e = text.indexOf('\n', at); return text.slice(lineStart(at), e < 0 ? text.length : e); };
      const relative = (restRaw, at, tailAt, known, shown) => {
        const dyn = DYNAMIC_NEXT_RE.test(text.charAt(tailAt));
        if (restRaw.startsWith('lib/') && !dyn) return;
        if (/^[./]*$/.test(restRaw)) {
          const a = /^[ \t]*(?:(?:export|readonly|local|declare)\s+)*([A-Za-z_]\w*)=/.exec(lineOf(at));
          if (!dyn && a && ROOT_VAR_NAME_RE.test(a[1])) return;
          unresolved.push(`${shown} <- ${rel}`); return;
        }
        const joined = path.posix.normalize(path.posix.join(ownDir, restRaw));
        if (!known || joined === '.' || joined.startsWith('..')) { unresolved.push(`${shown} <- ${rel}`); return; }
        addPath(joined, dyn);
      };
      for (const m of text.matchAll(SCRIPT_DIR_RE)) relative(m[1], m.index, m.index + m[0].length, OWN_DIR_RE.test(text), `$SCRIPT_DIR/${m[1]}`);
      for (const m of text.matchAll(DIRNAME_RE)) relative(m[2], m.index, m.index + m[0].length, OWN_DIR_RE.test(m[1]), `$(dirname ${m[1].trim()})/${m[2]}`);
      // Any other variable derived from the file's own location is not a base the helper knows.
      for (const a of text.matchAll(ASSIGN_RE)) {
        if (a[1] === 'SCRIPT_DIR' || ROOT_VAR_NAME_RE.test(a[1]) || !OWN_DIR_RE.test(a[2]) || !/dirname|pwd/.test(a[2])) continue;
        if (new RegExp(`\\$\\{?${a[1]}\\b`).test(text.slice(a.index + a[0].length))) unresolved.push(`$${a[1]} (own-directory variable) <- ${rel}`);
      }
      for (const m of text.matchAll(CD_OWN_RE)) if (!text.slice(lineStart(m.index), m.index).includes('=')) unresolved.push(`cd to own directory <- ${rel}`);
    }
    if (/\.(mjs|js)$/.test(rel)) {
      for (const m of text.matchAll(IMPORT_RE)) add(posix(path.posix.normalize(path.posix.join(path.posix.dirname(rel), m[1]))));
    }
  }
  return { closure, named, texts, dirs, unresolved };
}

const mapGlobs = (map, suite) => (map.suites[suite] ? map.suites[suite].globs : []);
export function declaredGlobs({ root, suite }) {
  const text = readText(path.join(root, MAP_REL));
  return text === null ? [] : mapGlobs(parseSuiteMap(text), suite);
}

// ---- identity (D4) ----
export function computeIdentity(ctx, suite, args) {
  const entry = ctx.manifest.suites[suite];
  const { closure, named, texts, dirs, unresolved } = computeClosure(ctx, suite);
  const declared = new Set([`tests/skills/test-${suite}.sh`, ...HARNESS, ...named]);
  for (const f of globMatches(ctx, [...mapGlobs(ctx.map, suite), ...(entry ? entry.inputs : []), ...ctx.map.sharedLibGlobs])) declared.add(f);
  for (const f of ctx.files) if (/^tests\/skills\/lib\/[^/]*\.sh$/.test(f)) declared.add(f);
  const allText = [...texts.entries()].filter(([rel]) => rel.startsWith('tests/')).map(([, t]) => t);
  for (const seed of ctx.seeds) {
    const base = path.posix.basename(seed);
    if (fs.existsSync(path.join(ctx.root, seed)) && [...texts.values()].some((t) => t.includes(base))) declared.add(seed);
  }
  const inputsMap = {};
  for (const rel of [...declared].sort()) inputsMap[rel] = fileHash(ctx, rel);

  const referenced = new Set();
  for (const t of texts.values()) {
    for (const m of t.matchAll(/\$\{?([A-Za-z_][A-Za-z0-9_]*)|process\.env\.([A-Za-z_]\w*)|\$env:([A-Za-z_]\w*)/g)) referenced.add(m[1] || m[2] || m[3]);
  }
  const envMap = {};
  for (const name of Object.keys(ctx.env)) {
    const wanted = ENV_PREFIXES.some((p) => name.startsWith(p)) || ENV_FIXED.includes(name);
    if (wanted && (!ENV_EXCLUDED.includes(name) || referenced.has(name))) envMap[name] = ctx.env[name];
  }
  for (const name of referenced) if (!(name in envMap)) envMap[name] = ctx.env[name] === undefined ? null : ctx.env[name];

  let history = '';
  if (allText.some((t) => HISTORY_RE.test(t))) {
    const rev = (r) => { try { return execFileSync('git', ['-C', ctx.root, 'rev-parse', '--verify', '-q', r], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return null; } };
    history = { head: rev('HEAD'), main: rev('refs/heads/main'), origin_main: rev('refs/remotes/origin/main') };
  }
  const values = {
    inputs: inputsMap, env: envMap, args, runtime: ctx.runtime,
    policy: { policy_version: ctx.policyVersion, timeout_seconds: ctx.timeoutSeconds, isolation: 'isolated', seed_paths: ctx.seeds },
    history,
  };
  const components = {};
  for (const c of IDENTITY_COMPONENTS) components[c] = hashOf(values[c]);
  return { suite, identity: hashOf(components), components, inputs_map: inputsMap, args, closure: [...closure].sort(), dirs, unresolved, historyMarker: history !== '' };
}

// First differing component (in IDENTITY_COMPONENTS order); null when equal.
export function diffIdentity(recorded, current) {
  for (const c of IDENTITY_COMPONENTS) {
    if (recorded.components[c] === current.components[c]) continue;
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
export function checkSuites({ root, suites, mode = 'selected', isolation = 'on', runDir, args, env, runtime, seedPaths, policyVersion, timeoutSeconds }) {
  const ctx = loadContext(root, { env, runtime, seedPaths, policyVersion, timeoutSeconds });
  const off = offReason(ctx.env, mode, isolation);
  const results = [];
  for (const suite of suites) {
    const argv = args && !Array.isArray(args) ? args[suite] : args || ['bash', `tests/skills/test-${suite}.sh`];
    // An identity is only ever compared or recorded for a declared, non-live suite.
    const entry = ctx.manifest.suites[suite];
    const declared = ctx.manifest.state === 'ok' && entry && entry.live === false;
    const id = off === 'ci' || off === 'opt-out' || !declared ? null : computeIdentity(ctx, suite, argv);
    if (id && runDir) {
      fs.mkdirSync(runDir, { recursive: true });
      fs.writeFileSync(path.join(runDir, `${suite}.reuse-identity.json`), JSON.stringify(id));
    }
    if (off) { results.push({ suite, off }); continue; }
    results.push({ suite, ...decide(ctx, suite, id) });
  }
  return { off, results };
}
function decide(ctx, suite, id) {
  const entry = ctx.manifest.suites[suite];
  if (ctx.manifest.state === 'invalid') return { status: 'RUN', reason: 'manifest-invalid' };
  if (!entry) return { status: 'RUN', reason: 'not-declared' };
  if (entry.live !== false) return { status: 'RUN', reason: 'live' };
  if (id.unresolved.length) return { status: 'RUN', reason: 'inputs-unresolvable', detail: id.unresolved[0] };
  const loaded = readStore(ctx.root, suite);
  if (loaded.status === 'corrupt') return { status: 'RUN', reason: 'store-corrupt' };
  const rec = loaded.data;
  if (!rec || !rec.components) return { status: 'RUN', reason: 'no-record' };
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

// ---- record (D5) ----
export function recordSuite({ root, suite, runDir, metrics, isolation = 'isolated', seeding = 'seeded', env, runtime, seedPaths, policyVersion, timeoutSeconds, now = new Date() }) {
  const e = env || process.env;
  const off = offReason(e, 'selected', 'on');
  if (off === 'ci' || off === 'opt-out') return { recorded: false, off };
  const no = (reason) => ({ recorded: false, reason });
  let m = metrics;
  if (!m) {
    const lines = (readText(path.join(runDir, 'metrics.jsonl')) || '').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return {}; } });
    m = lines.filter((x) => x.skill === suite).pop() || {};
  }
  if (m.status !== 'PASS' || m.exit_code !== 0) return no('not-pass');
  if (m.tripwire_attested !== true || m.tripwire_hasher_degraded !== false) return no('not-attested');
  if (isolation !== 'isolated' || seeding !== 'seeded') return no('not-isolated');
  const pre = readText(path.join(runDir, `${suite}.reuse-identity.json`));
  const ctx = loadContext(root, { env: e, runtime, seedPaths, policyVersion, timeoutSeconds });
  const entry = ctx.manifest.suites[suite];
  if (ctx.manifest.state !== 'ok' || !entry || entry.live !== false) return no('not-declared');
  let before;
  try { before = JSON.parse(pre); } catch { return no('no-identity'); }
  const after = computeIdentity(ctx, suite, before.args);
  if (after.unresolved.length) return no('inputs-unresolvable');
  if (after.identity !== before.identity) return no('inputs-changed-during-run');
  const logAbs = path.join(runDir, `${suite}.log`);
  let logHash;
  try { logHash = sha256(fs.readFileSync(logAbs)); } catch { return no('log-missing'); }
  const rec = {
    schema: 1, suite, identity: after.identity, components: after.components, inputs_map: after.inputs_map,
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
  for (const suite of Object.keys(man.suites)) {
    if (!rows[suite]) problems.push({ suite, reason: 'not-in-suite-map' });
    if (!fs.existsSync(path.join(root, `tests/skills/test-${suite}.sh`))) problems.push({ suite, reason: 'no-suite-file' });
    else if (rows['aai-suite-reuse'] && !rows['aai-suite-reuse'].globs.some((g) => matchesGlob(`tests/skills/test-${suite}.sh`, g))) problems.push({ suite, reason: 'not-gate-selected' });
  }
  return { ok: problems.length === 0, problems };
}

// ---- minimal-tree admission gate (D4 residual R1) ----
// The tokenizer is advisory; admission safety comes from this test. A suite stays in
// the manifest only if it passes fresh, through the framework, in a repository copy
// holding ONLY its identity files (explain's inputs, which already carry the harness
// of D4 (c)) plus MINIMAL_TREE_FRAMEWORK (the fixed extra files the framework needs to start).
// Measured: the framework starts from the D4 (c) harness alone, so nothing is added; a future need is added here.
export const MINIMAL_TREE_FRAMEWORK = [];
export function minimalTreeAdmit({ root, suites, manifestPath, timeoutMs = 600000, keep = false }) {
  const rel = manifestPath ? posix(path.relative(root, path.resolve(manifestPath))) : MANIFEST_REL;
  const ctx = loadContext(root, { manifestRel: rel });
  if (ctx.manifest.state !== 'ok') return [{ suite: '-', ok: false, detail: `manifest-${ctx.manifest.state}` }];
  const results = [];
  for (const suite of suites && suites.length ? suites : Object.keys(ctx.manifest.suites)) {
    const t0 = Date.now();
    const id = computeIdentity(ctx, suite, ['bash', `tests/skills/test-${suite}.sh`]);
    const want = new Set([...Object.keys(id.inputs_map).filter((p) => id.inputs_map[p] !== 'absent'), ...MINIMAL_TREE_FRAMEWORK]);
    const dir = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), `suite-reuse-min-${suite}-`));
    let ok = false; let detail = '';
    try {
      for (const f of want) {
        if (!fs.existsSync(path.join(root, f))) continue;
        fs.mkdirSync(path.dirname(path.join(dir, f)), { recursive: true });
        fs.copyFileSync(path.join(root, f), path.join(dir, f));
      }
      const git = (...a) => spawnSync('git', ['-c', 'user.email=min@example.invalid', '-c', 'user.name=min', '-c', 'commit.gpgsign=false', ...a], { cwd: dir, encoding: 'utf8' });
      git('init', '-q', '-b', 'main'); git('add', '-A'); git('commit', '-q', '-m', 'minimal tree');
      const env = { ...process.env, AAI_SUITE_REUSE: '0', AAI_TEST_PARALLEL: '1' };
      for (const k of ['AAI_ROLE', 'CI', 'GITHUB_ACTIONS', 'AAI_TEST_REF_ID']) delete env[k];
      const r = spawnSync('bash', ['tests/skills/test-framework.sh', '--skill', suite], { cwd: dir, env, encoding: 'utf8', timeout: timeoutMs });
      const out = `${r.stdout || ''}${r.stderr || ''}`;
      const plain = out.replace(/\x1b\[[0-9;]*m/g, '');
      ok = r.status === 0 && /Total:\s+1\b/.test(plain) && /Passed:\s+1 \(100%\)/.test(plain) && !/Failed:|Skipped:/.test(plain);
      detail = ok ? `${want.size} files` : `rc=${r.status} ${out.split('\n').filter((l) => /FAIL|No such file|not found|error/i.test(l)).slice(0, 4).join(' | ').slice(0, 400)}`;
    } finally { if (!keep) fs.rmSync(dir, { recursive: true, force: true }); }
    results.push({ suite, ok, detail, seconds: Math.round((Date.now() - t0) / 100) / 10 });
  }
  return results;
}

// ---- explain: what a suite's identity reads, plus advisory live markers ----
export function explainSuite({ root, suite, env }) {
  const ctx = loadContext(root, { env });
  const id = computeIdentity(ctx, suite, ['bash', `tests/skills/test-${suite}.sh`]);
  const markers = [];
  for (const rel of id.closure.filter((f) => f.startsWith('tests/'))) {
    (readText(path.join(root, rel)) || '').split('\n').forEach((line, i) => { if (MARKER_RE.test(line)) markers.push(`${rel}:${i + 1}: ${line.trim().slice(0, 100)}`); });
  }
  return { id, markers, history: id.historyMarker };
}

// ---- CLI ----
function parseArgs(argv) {
  const o = { suites: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--suite') o.suites.push(argv[++i]);
    else if (a === '--minimal-tree') o.minimalTree = true;
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
  } else if (cmd === 'record') {
    for (const suite of o.suites) {
      const r = recordSuite({ root, suite, runDir: o.runDir, isolation: o.isolation, seeding: o.seeding, seedPaths: o.seedPaths });
      out(r.recorded ? `RECORDED ${suite}` : r.off ? `OFF ${r.off}` : `NOT-RECORDED ${suite} reason=${r.reason}`);
    }
  } else if (cmd === 'forget') {
    o.suites.forEach((suite) => { forgetSuite({ root, suite }); out(`FORGOT ${suite}`); });
  } else if (cmd === 'lint') {
    const r = lintManifest({ root });
    r.problems.forEach((p) => out(`${p.suite} ${p.reason}`));
    process.exitCode = r.ok ? 0 : 1;
    if (o.minimalTree && r.ok) {
      const res = minimalTreeAdmit({ root, suites: o.suites, manifestPath: o.manifest });
      res.forEach((x) => out(`${x.ok ? 'MINIMAL-TREE-PASS' : 'MINIMAL-TREE-FAIL'} ${x.suite} ${x.seconds}s ${x.detail}`));
      if (res.some((x) => !x.ok)) process.exitCode = 1;
    }
  } else if (cmd === 'explain') {
    const r = explainSuite({ root, suite: o.suites[0] });
    const lines = [`suite ${o.suites[0]}: ${Object.keys(r.id.inputs_map).length} input file(s), closure ${r.id.closure.length}, history ${r.history ? 'yes' : 'no'}`];
    Object.keys(r.id.inputs_map).forEach((p) => lines.push(`  input ${p}`));
    [...new Set(r.id.dirs)].forEach((d) => lines.push(`  dir-literal ${d}`));
    r.id.unresolved.forEach((u) => lines.push(`  unresolved ${u}`));
    r.markers.forEach((m) => lines.push(`  marker ${m}`));
    out(lines.join('\n'));
  } else {
    process.stderr.write('usage: suite-reuse.mjs check|record|forget|lint|explain ...\n');
    process.exitCode = 2;
  }
}
function realOrResolve(p) { try { return fs.realpathSync(p); } catch { return path.resolve(p); } }
const isMain = process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url));
if (isMain) cli(process.argv.slice(2));
export { IDENTITY_COMPONENTS, REUSE_POLICY_VERSION };
