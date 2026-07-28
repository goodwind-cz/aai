#!/usr/bin/env node
// AAI environment health check — deterministic engine (CHANGE-0079 /
// spec-doctor-determinize). Replaces the 11 prose-computed categories that
// used to live entirely inside .aai/SKILL_DOCTOR.prompt.md (file existence,
// line counts, git-status parsing, hook wiring, dynamic-skills presence,
// template presence, RFC-0001 migration matrix) with one deterministic,
// zero-dependency script. CAT-11 (docs hygiene) and CAT-13 (vendored layer
// drift) already called real scripts before this change and keep doing so
// here, unchanged, as subprocess calls honoring their documented exit codes.
//
// Design notes (mirror-exactly, not redesign):
// - CAT-01 checks EXISTENCE only. It does NOT parse STATE.yaml for YAML
//   validity — that would require either a YAML parser (this script is
//   zero-dep) or importing the protected state-engine/core internals
//   (off-limits for this change). Structural STATE.yaml validation is
//   CAT-06's job, and CAT-06 covers exactly the one piece of it that is
//   ALREADY a real deterministic script: check-state.mjs's duplicate
//   top-level-key detector (INV-14). The other 13 STATE.yaml invariants
//   (INV-01..13) require semantic interpretation of business rules across
//   nested fields — genuinely judgmental — and stay owned by
//   .aai/SKILL_CHECK_STATE.prompt.md (the doctor wrapper says so; it does
//   not force-fit them into this script).
// - Only CAT-01, CAT-02, and CAT-06 (on a real detected structural failure)
//   can produce FAIL. Every other category caps at WARN — this mirrors the
//   original prompt's explicit "informational, never blocks" language for
//   CAT-10/11/12/13, and extends the same posture to CAT-03/04/05/07/08/09
//   which the original prose never named a required/BROKEN trigger for.
//
// Usage:
//   node .aai/scripts/aai-doctor.mjs [--root <path>] [--json]
//
// --root defaults to the repo root resolved from THIS script's own location
// (two levels up from .aai/scripts/), NOT process.cwd() — so the tool
// produces the same verdict regardless of the caller's working directory.
// Pass --root explicitly to point at a fixture / foreign project tree.
//
// Output (default, one line per category):
//   CAT-NN <PASS|WARN|FAIL|SKIP> <short reason>
//   DOCTOR <CLEAN|ISSUES(n)>
// --json prints one object:
//   { root, generatedAt, categories: [{id,name,status,reason}],
//     verdict: "CLEAN"|"ISSUES", issues: <int>, exit: <int> }
//
// Exit codes: 0 on CLEAN or WARN-only, 1 when any category is FAIL.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// --- generic helpers -----------------------------------------------------

function exists(root, rel) {
  return fs.existsSync(path.join(root, rel));
}

function readText(root, rel) {
  try {
    return fs.readFileSync(path.join(root, rel), 'utf8');
  } catch {
    return null;
  }
}

// wc -l semantics: count newline-terminated lines; a final unterminated
// line still counts once; an empty file counts 0.
function countLines(text) {
  if (text === null || text === undefined) return 0;
  if (text === '') return 0;
  const parts = text.split('\n');
  if (parts[parts.length - 1] === '') parts.pop();
  return parts.length;
}

function run(cmd, args, cwd, timeoutMs = 10_000) {
  const res = spawnSync(cmd, args, { cwd, encoding: 'utf8', timeout: timeoutMs });
  return {
    ok: res.status === 0 && !res.error,
    status: res.error ? null : res.status,
    stdout: res.stdout || '',
    stderr: res.stderr || '',
    error: res.error || null,
  };
}

function cat(id, name, status, reason) {
  return { id, name, status, reason };
}

// --- CAT-01 Core Files -----------------------------------------------------

function catCoreFiles(root) {
  const required = [
    '.aai/AGENTS.md',
    '.aai/PLAYBOOK.md',
    '.aai/ORCHESTRATION.prompt.md',
    'CLAUDE.md',
  ];
  // docs/ai/STATE.yaml is deliberately NOT here: it is a per-developer,
  // gitignored runtime file (RFC-0001) that legitimately does not exist on a
  // fresh checkout or CI runner — CAT-06 owns its absence (WARN + init hint).
  // Listing it as required made the doctor report FAIL on every CI checkout
  // (PR #178 first CI run).
  const optional = ['docs/TECHNOLOGY.md', '.aai/workflow/WORKFLOW.md'];
  const missingRequired = required.filter((f) => !exists(root, f));
  const missingOptional = optional.filter((f) => !exists(root, f));
  if (missingRequired.length > 0) {
    return cat('CAT-01', 'Core Files', 'FAIL', `missing required: ${missingRequired.join(', ')}`);
  }
  if (missingOptional.length > 0) {
    return cat(
      'CAT-01', 'Core Files', 'WARN',
      `${required.length}/${required.length} required present; missing optional: ${missingOptional.join(', ')}`,
    );
  }
  return cat('CAT-01', 'Core Files', 'PASS', `${required.length}/${required.length} required, ${optional.length}/${optional.length} optional present`);
}

// --- CAT-02 Role Prompts -----------------------------------------------------

function catRolePrompts(root) {
  const files = [
    '.aai/PLANNING.prompt.md',
    '.aai/IMPLEMENTATION.prompt.md',
    '.aai/VALIDATION.prompt.md',
    '.aai/REMEDIATION.prompt.md',
  ];
  const missing = files.filter((f) => !exists(root, f));
  if (missing.length > 0) {
    return cat('CAT-02', 'Role Prompts', 'FAIL', `missing: ${missing.join(', ')}`);
  }
  return cat('CAT-02', 'Role Prompts', 'PASS', `${files.length}/${files.length} present`);
}

// --- CAT-03 Universal Skills -------------------------------------------------
// A skill is "healthy" when its SKILL.md does not dangle-reference a
// .aai/*.prompt.md path that doesn't exist. A SKILL.md that names no prompt
// file at all (e.g. aai-overview, which points at a script) is healthy by
// definition — there is nothing to dangle.

function catUniversalSkills(root) {
  const skillsDir = path.join(root, '.claude/skills');
  if (!fs.existsSync(skillsDir)) {
    return cat('CAT-03', 'Universal Skills', 'WARN', '.claude/skills not found');
  }
  const dirs = fs.readdirSync(skillsDir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && d.name.startsWith('aai-'))
    .map((d) => d.name)
    .sort();
  if (dirs.length === 0) {
    return cat('CAT-03', 'Universal Skills', 'WARN', 'no aai-* skills found under .claude/skills');
  }
  const orphaned = [];
  for (const d of dirs) {
    const skillMd = readText(root, `.claude/skills/${d}/SKILL.md`);
    if (skillMd === null) {
      orphaned.push(`${d} (SKILL.md missing)`);
      continue;
    }
    const refs = skillMd.match(/\.aai\/[A-Za-z0-9_]+\.prompt\.md/g) || [];
    const dangling = refs.filter((r) => !exists(root, r));
    if (dangling.length > 0) orphaned.push(`${d} -> ${dangling.join(', ')}`);
  }
  const healthy = dirs.length - orphaned.length;
  if (orphaned.length > 0) {
    return cat('CAT-03', 'Universal Skills', 'WARN', `${healthy}/${dirs.length} healthy; orphaned: ${orphaned.join('; ')}`);
  }
  return cat('CAT-03', 'Universal Skills', 'PASS', `${healthy}/${dirs.length} healthy`);
}

// --- CAT-04 Dynamic Skills (Bootstrap) --------------------------------------

function catDynamicSkills(root) {
  const candidates = [
    '.claude/skills/aai-test-unit/SKILL.md',
    '.claude/skills/aai-test-e2e/SKILL.md',
    '.claude/skills/aai-build/SKILL.md',
    '.claude/skills/aai-lint/SKILL.md',
  ];
  const found = candidates.filter((f) => exists(root, f));
  if (found.length === 0) {
    return cat('CAT-04', 'Dynamic Skills', 'WARN', 'no dynamic skills — run /aai-bootstrap to generate');
  }
  return cat('CAT-04', 'Dynamic Skills', 'PASS', `${found.length} found`);
}

// --- CAT-05 Knowledge Files --------------------------------------------------

function catKnowledgeFiles(root) {
  const issues = [];
  const parts = [];
  for (const f of ['docs/knowledge/FACTS.md', 'docs/knowledge/PATTERNS.md']) {
    const text = readText(root, f);
    if (text === null) { issues.push(`${f} missing`); continue; }
    const n = countLines(text);
    if (n === 0) issues.push(`${f} empty`);
    parts.push(`${f}: ${n} lines`);
  }
  for (const f of ['docs/knowledge/UI_MAP.md', 'docs/knowledge/LEARNED.md']) {
    if (!exists(root, f)) issues.push(`${f} missing (optional)`);
  }
  if (issues.length > 0) {
    return cat('CAT-05', 'Knowledge Files', 'WARN', issues.join('; '));
  }
  return cat('CAT-05', 'Knowledge Files', 'PASS', parts.join('; '));
}

// --- CAT-06 STATE.yaml Health ------------------------------------------------
// Shallow, honest check: existence + the one piece of STATE.yaml validation
// that already exists as a real script (check-state.mjs's duplicate
// top-level-key detector, INV-14). The other 13 invariants are semantic and
// stay owned by /aai-check-state (LLM step) — this category says so.

function catStateHealth(root, scriptDir) {
  const statePath = path.join(root, 'docs/ai/STATE.yaml');
  if (!fs.existsSync(statePath)) {
    return cat(
      'CAT-06', 'STATE.yaml Health', 'WARN',
      'docs/ai/STATE.yaml not yet initialized (per-dev runtime file, RFC-0001) — run any /aai-loop tick',
    );
  }
  const checker = path.join(scriptDir, 'check-state.mjs');
  if (!fs.existsSync(checker)) {
    return cat('CAT-06', 'STATE.yaml Health', 'WARN', 'check-state.mjs not found — structural check unavailable');
  }
  const res = run(process.execPath, [checker, statePath], root);
  if (res.ok) {
    return cat('CAT-06', 'STATE.yaml Health', 'PASS', 'no duplicate top-level keys (run /aai-check-state for the full 14-invariant report)');
  }
  const combined = `${res.stderr || ''}\n${res.stdout || ''}`;
  const firstLine = (res.stderr || res.stdout || 'check-state.mjs reported a structural failure').trim().split('\n')[0];
  // A genuine structural verdict carries an ERROR:/FAIL marker from
  // check-state itself; anything else (unresolved import in a partially
  // vendored tree, node crash) is a TOOLING problem — degrade to WARN like
  // every other category's broken-helper branch, never a false BROKEN.
  if (/(^|\n)\s*(ERROR:|FAIL)/.test(combined)) {
    return cat('CAT-06', 'STATE.yaml Health', 'FAIL', firstLine);
  }
  return cat('CAT-06', 'STATE.yaml Health', 'WARN', `check-state.mjs did not run cleanly — partial vendoring? run /aai-update (${firstLine})`);
}

// --- CAT-07 Telemetry & Metrics ----------------------------------------------

function catTelemetry(root) {
  const parts = [];
  const issues = [];
  for (const f of ['docs/ai/METRICS.jsonl', 'docs/ai/decisions.jsonl']) {
    const text = readText(root, f);
    if (text === null) { issues.push(`${f} missing`); continue; }
    const n = countLines(text);
    if (n === 0) issues.push(`${f} empty`);
    parts.push(`${f}: ${n} entries`);
  }
  if (!exists(root, 'docs/ai/LOOP_TICKS.jsonl')) issues.push('docs/ai/LOOP_TICKS.jsonl missing (optional)');
  if (issues.length > 0) {
    return cat('CAT-07', 'Telemetry & Metrics', 'WARN', issues.join('; '));
  }
  return cat('CAT-07', 'Telemetry & Metrics', 'PASS', parts.join('; '));
}

// --- CAT-08 Git Status --------------------------------------------------------

function catGitStatus(root) {
  if (!fs.existsSync(path.join(root, '.git'))) {
    return cat('CAT-08', 'Git Status', 'SKIP', 'not a git repository');
  }
  const branchRes = run('git', ['rev-parse', '--abbrev-ref', 'HEAD'], root);
  const branch = branchRes.ok ? branchRes.stdout.trim() : 'UNKNOWN';
  const statusRes = run('git', ['status', '--porcelain'], root);
  if (!statusRes.ok) {
    // Never report a clean tree we could not actually observe (PR #178
    // Copilot finding — git missing/corrupt must not masquerade as PASS).
    return cat('CAT-08', 'Git Status', 'WARN', `git status unavailable: ${(statusRes.stderr || 'unknown error').trim().split('\n')[0]}`);
  }
  const changed = statusRes.stdout.split('\n').filter((l) => l.trim() !== '');
  const parts = [`branch: ${branch}`];
  if (changed.length === 0) parts.push('clean working tree');
  else parts.push(`${changed.length} changed file(s)`);
  const aheadBehindRes = run('git', ['rev-list', '--left-right', '--count', '@{upstream}...HEAD'], root);
  if (aheadBehindRes.ok) {
    const [behind, ahead] = aheadBehindRes.stdout.trim().split(/\s+/).map((n) => Number.parseInt(n, 10) || 0);
    if (ahead === 0 && behind === 0) parts.push('up to date with remote');
    else parts.push(`${ahead} ahead / ${behind} behind remote`);
  } else {
    parts.push('no upstream configured');
  }
  const status = changed.length === 0 ? 'PASS' : 'WARN';
  return cat('CAT-08', 'Git Status', status, parts.join(', '));
}

// --- CAT-09 Pre-Compact Hook --------------------------------------------------

function catPreCompactHook(root) {
  const sh = exists(root, '.aai/scripts/pre-compact-save.sh');
  const ps1 = exists(root, '.aai/scripts/pre-compact-save.ps1');
  if (sh && ps1) return cat('CAT-09', 'Pre-Compact Hook', 'PASS', 'both platform scripts present');
  const missing = [!sh && 'pre-compact-save.sh', !ps1 && 'pre-compact-save.ps1'].filter(Boolean);
  return cat('CAT-09', 'Pre-Compact Hook', 'WARN', `missing: ${missing.join(', ')} (hook registration in settings is user-managed)`);
}

// --- CAT-10 RFC-0001 STATE Migration Consistency ------------------------------

function gitignoreHas(root, rel) {
  const text = readText(root, '.gitignore');
  if (text === null) return false;
  return text.split('\n').some((l) => l.trim() === rel);
}

function gitTracked(root, rel) {
  return run('git', ['ls-files', '--error-unmatch', rel], root).ok;
}

function migrationVerdict(root, rel) {
  const ignored = gitignoreHas(root, rel);
  const tracked = gitTracked(root, rel);
  const onDisk = exists(root, rel);
  if (ignored && !tracked) return `${rel}: migrated correctly`;
  if (ignored && tracked) return `${rel}: INCONSISTENT — gitignored but still tracked (run migrate-state-to-local.sh)`;
  if (!ignored && tracked) return `${rel}: LEGACY — not yet migrated (run /aai-update then migrate-state-to-local.sh)`;
  if (!ignored && !tracked && onDisk) return `${rel}: LIKELY MISSING — neither gitignored nor tracked`;
  return `${rel}: ok (per-dev local, not initialized yet)`;
}

function catRfc0001Migration(root) {
  // gitTracked() is meaningless without a working git repo — say so instead
  // of synthesizing a migrated-correctly verdict (PR #178 Copilot finding).
  const gitProbe = run('git', ['rev-parse', '--is-inside-work-tree'], root);
  if (!gitProbe.ok) {
    return cat('CAT-10', 'RFC-0001 Migration', 'WARN', 'migration state unverifiable: git unavailable or not a repository');
  }
  const parts = [
    migrationVerdict(root, 'docs/ai/STATE.yaml'),
    migrationVerdict(root, 'docs/ai/LOOP_TICKS.jsonl'),
  ];
  const eventsText = readText(root, 'docs/ai/EVENTS.jsonl');
  parts.push(eventsText === null
    ? 'docs/ai/EVENTS.jsonl: not initialized'
    : `docs/ai/EVENTS.jsonl: present (${countLines(eventsText)} entries)`);
  const inconsistent = parts.some((p) => p.includes('INCONSISTENT') || p.includes('LEGACY') || p.includes('LIKELY MISSING') || p.includes('not initialized'));
  return cat('CAT-10', 'RFC-0001 Migration', inconsistent ? 'WARN' : 'PASS', parts.join('; '));
}

// --- CAT-11 Docs Hygiene (subprocess to docs-audit.mjs) -----------------------

function catDocsHygiene(root, scriptDir) {
  const script = path.join(scriptDir, 'docs-audit.mjs');
  if (!fs.existsSync(script)) {
    return cat('CAT-11', 'Docs Hygiene', 'WARN', 'docs-audit.mjs not installed — run /aai-update');
  }
  const res = run(process.execPath, [script, '--quick', '--no-event'], root, 20_000);
  const out = res.stdout || res.stderr || '';
  const verdictLine = out.split('\n').find((l) => l.includes('### Verdict:')) || '';
  const enforcementNote = exists(root, 'docs/ai/docs-audit.yaml')
    ? 'enforcement enabled'
    : 'report-only mode (create docs/ai/docs-audit.yaml to enable enforcement)';
  if (!res.ok && !verdictLine) {
    return cat('CAT-11', 'Docs Hygiene', 'WARN', `docs-audit.mjs --quick failed to run cleanly: ${(res.error && res.error.message) || res.stderr.split('\n')[0] || 'unknown error'}`);
  }
  const isClean = verdictLine.includes('CLEAN');
  const reason = `${verdictLine.replace('### Verdict:', '').trim() || 'no verdict line'}; ${enforcementNote}`;
  return cat('CAT-11', 'Docs Hygiene', isClean ? 'PASS' : 'WARN', reason);
}

// --- CAT-12 Docs Index Auto-Regen Hook ----------------------------------------

function catIndexRegenHook(root) {
  const installer = exists(root, '.aai/scripts/install-pre-commit-hook.sh');
  // Linked worktrees ship .git as a FILE, so <root>/.git/hooks never exists
  // there — ask git for the real common dir (PR #178 Codex P2).
  let gitDir = path.join(root, '.git');
  const commonRes = run('git', ['rev-parse', '--git-common-dir'], root);
  if (commonRes.ok && commonRes.stdout.trim() !== '') {
    const common = commonRes.stdout.trim();
    gitDir = path.isAbsolute(common) ? common : path.join(root, common);
  }
  const hookPath = path.join(gitDir, 'hooks/pre-commit');
  if (!fs.existsSync(hookPath)) {
    return cat('CAT-12', 'Index Regen Hook', 'WARN', installer
      ? 'not installed (optional) — run bash .aai/scripts/install-pre-commit-hook.sh'
      : 'not installed and installer missing — run /aai-update');
  }
  const body = fs.readFileSync(hookPath, 'utf8');
  if (body.includes('AAI:INDEX-AUTOGEN')) {
    return cat('CAT-12', 'Index Regen Hook', 'PASS', 'installed');
  }
  return cat('CAT-12', 'Index Regen Hook', 'WARN', 'pre-commit hook present but NOT AAI-managed — merge manually or re-run install-pre-commit-hook.sh --force');
}

// --- CAT-13 Vendored Layer Drift (subprocess to layer-drift.mjs) -------------

function catLayerDrift(root, scriptDir) {
  const script = path.join(scriptDir, 'layer-drift.mjs');
  if (!fs.existsSync(script)) {
    return cat('CAT-13', 'Layer Drift', 'WARN', 'layer-drift.mjs not found — run /aai-update');
  }
  const res = run(process.execPath, [script], root, 15_000);
  const message = (res.stdout || res.stderr || '').trim().split('\n')[0] || 'no output';
  const profile = readProfileFromPin(root);
  const reason = `${message} (profile: ${profile})`;
  // Exit map (documented in layer-drift.mjs header): 0 up-to-date/ahead,
  // 3 behind, 4 unverifiable (informational only — also the normal verdict
  // inside the canonical repo itself), 2/other = script error. This category
  // is informational; it must never block other AAI work, so it never FAILs.
  const status = res.status === 0 ? 'PASS' : 'WARN';
  return cat('CAT-13', 'Layer Drift', status, reason);
}

function readProfileFromPin(root) {
  const text = readText(root, '.aai/system/AAI_PIN.md');
  if (!text) return 'extended (implicit)';
  const m = text.match(/^-\s*Profile\s*:\s*(.+)$/m);
  if (!m) return 'extended (implicit)';
  const value = m[1].trim();
  if (!value || value === 'UNKNOWN' || /^<.*>$/.test(value)) return 'extended (implicit)';
  return value;
}

// --- CLI ---------------------------------------------------------------------

function parseArgs(argv) {
  const args = { root: null, json: false };
  const toks = argv.slice(2);
  for (let i = 0; i < toks.length; i++) {
    const tok = toks[i];
    if (tok === '--root') {
      const v = toks[++i];
      if (v === undefined) { console.error('aai-doctor: --root needs a value'); process.exit(2); }
      args.root = path.resolve(v);
    } else if (tok === '--json') {
      args.json = true;
    } else {
      console.error(`aai-doctor: unknown flag: ${tok}`);
      console.error('Usage: aai-doctor [--root <path>] [--json]');
      process.exit(2);
    }
  }
  return args;
}

function defaultRoot() {
  // .aai/scripts/aai-doctor.mjs -> repo root is two levels up.
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
}

export function runDoctor(root, scriptDir) {
  return [
    catCoreFiles(root),
    catRolePrompts(root),
    catUniversalSkills(root),
    catDynamicSkills(root),
    catKnowledgeFiles(root),
    catStateHealth(root, scriptDir),
    catTelemetry(root),
    catGitStatus(root),
    catPreCompactHook(root),
    catRfc0001Migration(root),
    catDocsHygiene(root, scriptDir),
    catIndexRegenHook(root),
    catLayerDrift(root, scriptDir),
  ];
}

function main() {
  const args = parseArgs(process.argv);
  const root = args.root || defaultRoot();
  if (!fs.existsSync(root)) {
    console.error(`aai-doctor: --root does not exist: ${root}`);
    process.exit(2);
  }
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const categories = runDoctor(root, scriptDir);
  const failCount = categories.filter((c) => c.status === 'FAIL').length;
  const issueCount = categories.filter((c) => c.status !== 'PASS').length;
  const verdict = issueCount === 0 ? 'CLEAN' : 'ISSUES';
  const exitCode = failCount > 0 ? 1 : 0;

  if (args.json) {
    console.log(JSON.stringify({
      root,
      generatedAt: new Date().toISOString(),
      categories,
      verdict,
      issues: issueCount,
      exit: exitCode,
    }, null, 2));
  } else {
    for (const c of categories) {
      console.log(`${c.id} ${c.status} ${c.reason}`);
    }
    console.log(`DOCTOR ${verdict === 'CLEAN' ? 'CLEAN' : `ISSUES(${issueCount})`}`);
  }
  process.exit(exitCode);
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main();
}
