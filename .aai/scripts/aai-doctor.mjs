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
// CAT-14/CAT-15/CAT-16 (CHANGE-0135 / spec-doctor-win-selftest) add three
// read-only diagnostic sections: the REAL Windows wrapper self-test
// (.aai/scripts/aai-win-selftest.ps1, which dot-sources
// .aai/scripts/aai-run-tests.ps1 for its probe functions — never a second
// implementation of them), the environment the wrapper actually sees
// (case-colliding env var groups, PowerShell engines, Git Bash candidates,
// WSL tri-state), and an agent-CLI presence/version probe. All three cap at
// WARN — see catWinSelfTest/catWinEnvironment/catAgentCliProbe below — so the
// pre-existing exit map (0 clean/WARN-only, 1 on any FAIL) stays unchanged;
// `--strict` is the opt-in that also exits 1 on any WARN.
//
// Usage:
//   node .aai/scripts/aai-doctor.mjs [--root <path>] [--json] [--strict]
//
// --root defaults to the repo root resolved from THIS script's own location
// (two levels up from .aai/scripts/), NOT process.cwd() — so the tool
// produces the same verdict regardless of the caller's working directory.
// Pass --root explicitly to point at a fixture / foreign project tree.
//
// Output (default, one line per category — text mode never prints detail):
//   CAT-NN <PASS|WARN|FAIL|SKIP> <short reason>
//   DOCTOR <CLEAN|ISSUES(n)>
// --json prints one object:
//   { root, generatedAt, categories: [{id,name,status,reason,detail?}],
//     verdict: "CLEAN"|"ISSUES", issues: <int>, exit: <int> }
//
// Exit codes: 0 on CLEAN or WARN-only, 1 when any category is FAIL, 2 on a
// CLI usage error. `--strict`: 1 when any category is WARN or FAIL, 0 only
// when every category is PASS or SKIP (a SKIP is not a finding).

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

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

// Returns {msg, ok}: the aggregate verdict keys on the BOOLEAN, never on the
// message wording — a rewording can no longer silently flip PASS/WARN
// (PR #178 review techdebt, closed by CHANGE follow-ups-scripts).
function migrationVerdict(root, rel) {
  const ignored = gitignoreHas(root, rel);
  const tracked = gitTracked(root, rel);
  const onDisk = exists(root, rel);
  if (ignored && !tracked) return { msg: `${rel}: migrated correctly`, ok: true };
  if (ignored && tracked) return { msg: `${rel}: INCONSISTENT — gitignored but still tracked (run migrate-state-to-local.sh)`, ok: false };
  if (!ignored && tracked) return { msg: `${rel}: LEGACY — not yet migrated (run /aai-update then migrate-state-to-local.sh)`, ok: false };
  if (!ignored && !tracked && onDisk) return { msg: `${rel}: LIKELY MISSING — neither gitignored nor tracked`, ok: false };
  return { msg: `${rel}: ok (per-dev local, not initialized yet)`, ok: true };
}

function catRfc0001Migration(root) {
  // gitTracked() is meaningless without a working git repo — say so instead
  // of synthesizing a migrated-correctly verdict (PR #178 Copilot finding).
  const gitProbe = run('git', ['rev-parse', '--is-inside-work-tree'], root);
  if (!gitProbe.ok) {
    return cat('CAT-10', 'RFC-0001 Migration', 'WARN', 'migration state unverifiable: git unavailable or not a repository');
  }
  const verdicts = [
    migrationVerdict(root, 'docs/ai/STATE.yaml'),
    migrationVerdict(root, 'docs/ai/LOOP_TICKS.jsonl'),
  ];
  const eventsText = readText(root, 'docs/ai/EVENTS.jsonl');
  verdicts.push(eventsText === null
    ? { msg: 'docs/ai/EVENTS.jsonl: not initialized', ok: false }
    : { msg: `docs/ai/EVENTS.jsonl: present (${countLines(eventsText)} entries)`, ok: true });
  const inconsistent = verdicts.some((v) => !v.ok);
  return cat('CAT-10', 'RFC-0001 Migration', inconsistent ? 'WARN' : 'PASS', verdicts.map((v) => v.msg).join('; '));
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

// --- CAT-17 Git Ref Guard (SPEC-0156-spec-agent-shell-can-write-the-shipping-repo) ------
// SPEC-0029 shipped a correct hook mechanism that never fired because opting
// in was left to a step nobody takes (D4). This category exists so a dormant
// guard is at least VISIBLE — doctor runs often, a template in a directory
// does not.
//
// PR #302 review (Codex P1 / Copilot P2): a hook FILE carrying the marker is
// not evidence git will ever run it. Two ways that lie: (1) `core.hooksPath`
// points somewhere else entirely — a manual `.git/hooks` join misses that,
// same worktree-common-dir problem CAT-12 already solves, plus the
// hooksPath case CAT-12 does not have to worry about; (2) the file at the
// EFFECTIVE path is decorative (marker present, logic gutted/inverted) or,
// on POSIX, simply not executable, so git silently never invokes it. This
// category now (a) asks git for the EFFECTIVE hooks path instead of
// re-deriving it, and (b) behaviourally probes the resolved file by
// invoking it directly with synthetic reference-transaction input — no real
// ref ever moves, so this is safe to run against the user's live hook.

function catGitRefGuard(root) {
  const installer = exists(root, '.aai/scripts/install-pre-commit-hook.sh');
  // `git rev-parse --git-path hooks/reference-transaction` resolves BOTH the
  // worktree-common-dir case (linked worktree: .git is a FILE) and a
  // `core.hooksPath` override in one call — verified empirically (scratch
  // repo + scratch worktree + scratch hooksPath override) rather than
  // assumed: this is the exact resolution git itself uses to decide which
  // file to execute, so attesting against it is attesting against reality
  // instead of a plausible-looking re-derivation.
  const pathRes = run('git', ['rev-parse', '--git-path', 'hooks/reference-transaction'], root);
  if (!pathRes.ok || pathRes.stdout.trim() === '') {
    return cat('CAT-17', 'Git Ref Guard', 'WARN', installer
      ? 'could not resolve the effective git hooks path (git rev-parse failed) — run bash .aai/scripts/install-pre-commit-hook.sh'
      : 'could not resolve the effective git hooks path and installer missing — run /aai-update');
  }
  const rel = pathRes.stdout.trim();
  const hookPath = path.isAbsolute(rel) ? rel : path.join(root, rel);
  if (!fs.existsSync(hookPath)) {
    return cat('CAT-17', 'Git Ref Guard', 'WARN', installer
      ? `not armed (refs/heads/main writes are ambient; effective hooks path is ${hookPath}) — run bash .aai/scripts/install-pre-commit-hook.sh`
      : 'not armed and installer missing — run /aai-update');
  }
  const body = fs.readFileSync(hookPath, 'utf8');
  if (!body.includes('AAI:REF-GUARD')) {
    return cat('CAT-17', 'Git Ref Guard', 'WARN', `reference-transaction hook present at the effective hooks path (${hookPath}) but NOT AAI-managed — merge manually or re-run install-pre-commit-hook.sh --force`);
  }
  // POSIX: git refuses to run a hook file that lacks the executable bit —
  // it is silently treated as absent, exactly like the decorative-hook case
  // below, so check this BEFORE trusting the marker. (Windows hooks run
  // through an interpreter regardless of the file's mode bits, so this
  // check does not apply there — CAT-14/15/16 already gate Windows-only
  // logic the same way.)
  if (process.platform !== 'win32') {
    try {
      fs.accessSync(hookPath, fs.constants.X_OK);
    } catch {
      return cat('CAT-17', 'Git Ref Guard', 'WARN', `reference-transaction hook at ${hookPath} carries the AAI:REF-GUARD marker but is NOT executable — git will not run it (NOT armed); chmod +x or re-run install-pre-commit-hook.sh --force`);
    }
  }
  const probe = probeRefGuardHook(hookPath, root);
  if (!probe.verified) {
    return cat('CAT-17', 'Git Ref Guard', 'WARN', `reference-transaction hook at ${hookPath} carries the AAI:REF-GUARD marker but could not be behaviourally verified (${probe.errorCode || 'probe failed'}) — treat as NOT confirmed armed`);
  }
  if (probe.refuses && probe.permits) {
    return cat('CAT-17', 'Git Ref Guard', 'PASS', `armed (probe on ${hookPath} refuses a refs/heads/main update without AAI_GIT_WRITE=1 and permits it with AAI_GIT_WRITE=1)`);
  }
  return cat('CAT-17', 'Git Ref Guard', 'WARN', `reference-transaction hook at ${hookPath} carries the AAI:REF-GUARD marker but does NOT behave as a guard on probe (refuses=${probe.refuses}, permits=${probe.permits}) — NOT armed; re-run install-pre-commit-hook.sh --force`);
}

// Invokes a reference-transaction hook file DIRECTLY with synthetic
// old/new/ref input for refs/heads/main — this never runs a `git` ref-update
// command and never touches a real ref, so it is safe against the caller's
// live repository. Mirrors exactly what git itself feeds a
// reference-transaction hook: argv[1] is the transaction state ("prepared"),
// stdin carries "<old-oid> <new-oid> <refname>" lines.
function probeRefGuardHook(hookPath, root) {
  const REFUSE_INPUT = `${'0'.repeat(40)} ${'1'.repeat(40)} refs/heads/main\n`;
  const baseEnv = { ...process.env };
  delete baseEnv.AAI_GIT_WRITE;
  const writeEnv = { ...baseEnv, AAI_GIT_WRITE: '1' };
  const opts = (env) => ({ cwd: root, input: REFUSE_INPUT, env, encoding: 'utf8', timeout: 5000 });

  // POSIX: exec the file directly — the OS loader honors the shebang, and
  // (having already confirmed the executable bit above) this is exactly how
  // git itself would run it. Windows has no OS-level shebang support, so
  // fall back to an explicit interpreter — the same one Git for Windows
  // uses to run this exact hook.
  if (process.platform !== 'win32') {
    const refuses = spawnSync(hookPath, ['prepared'], opts(baseEnv));
    if (refuses.error) {
      return { verified: false, errorCode: refuses.error.code };
    }
    const permits = spawnSync(hookPath, ['prepared'], opts(writeEnv));
    if (permits.error) {
      return { verified: false, errorCode: permits.error.code };
    }
    return { verified: true, refuses: refuses.status !== 0, permits: permits.status === 0 };
  }

  for (const shell of ['sh', 'bash']) {
    const refuses = spawnSync(shell, [hookPath, 'prepared'], opts(baseEnv));
    if (refuses.error) continue;
    const permits = spawnSync(shell, [hookPath, 'prepared'], opts(writeEnv));
    if (permits.error) continue;
    return { verified: true, refuses: refuses.status !== 0, permits: permits.status === 0 };
  }
  return { verified: false, errorCode: 'ENOINTERPRETER' };
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

// --- CAT-14/CAT-15 Windows Self-Test + Environment (shared probe) -----------
// D1: BOTH categories are derived from the SAME single spawn of
// aai-win-selftest.ps1 (SEAM-1 — one JSON document on stdout), never two
// spawns. D6: this section runs only when process.platform === 'win32' AND a
// PowerShell engine resolves; either missing precondition is a named SKIP
// that spawns NOTHING (never touches the ps1 probe at all).

function resolveWinEngine(root) {
  for (const engine of ['pwsh', 'powershell']) {
    const res = run(engine, ['-NoProfile', '-Command', 'exit 0'], root, 5_000);
    if (!res.error) return engine;
  }
  return null;
}

function runWinSelfTestProbe(root, scriptDir) {
  if (process.platform !== 'win32') {
    return { skip: 'not running on a Windows host' };
  }
  const engine = resolveWinEngine(root);
  if (!engine) {
    return { skip: 'no PowerShell engine (pwsh or powershell.exe) resolved on PATH' };
  }
  const probe = path.join(scriptDir, 'aai-win-selftest.ps1');
  if (!fs.existsSync(probe)) {
    return { warn: 'aai-win-selftest.ps1 not found — run /aai-update' };
  }
  // Generous but bounded: three self-test arms (success/timeout/spawnfail)
  // plus engine-resolution overhead; a genuine hang degrades to WARN, never
  // a throw (RR-4).
  const res = run(engine, ['-NoProfile', '-File', probe], root, 170_000);
  if (res.error) {
    const timedOut = res.error.code === 'ETIMEDOUT' || res.error.killed === true;
    return { warn: timedOut ? 'self-test timed out' : `self-test failed to run: ${res.error.message}` };
  }
  let parsed = null;
  try { parsed = JSON.parse(res.stdout); } catch { /* leave null — unparseable */ }
  if (!parsed || typeof parsed !== 'object') {
    return { warn: 'self-test produced unparseable output' };
  }
  return { ok: true, parsed };
}

function catWinSelfTest(probe) {
  if (probe.skip) return { ...cat('CAT-14', 'Windows Self-Test', 'SKIP', probe.skip), detail: { spawned: false } };
  if (probe.warn) return { ...cat('CAT-14', 'Windows Self-Test', 'WARN', probe.warn), detail: { spawned: false } };
  const st = (probe.parsed && probe.parsed.selftest) || {};
  const arms = Array.isArray(st.arms) ? st.arms : [];
  const passCount = arms.filter((a) => a && a.status === 'PASS').length;
  const status = st.failed || arms.length === 0 ? 'WARN' : 'PASS';
  const reason = arms.length === 0
    ? (st.reason || 'self-test reported no arm results')
    : `${passCount}/${arms.length} arms passed${st.reason ? ` (${st.reason})` : ''}`;
  return { ...cat('CAT-14', 'Windows Self-Test', status, reason), detail: st };
}

function catWinEnvironment(probe) {
  if (probe.skip) return { ...cat('CAT-15', 'Windows Environment', 'SKIP', probe.skip), detail: {} };
  if (probe.warn) return { ...cat('CAT-15', 'Windows Environment', 'WARN', probe.warn), detail: {} };
  const env = (probe.parsed && probe.parsed.environment) || {};
  const collisions = Array.isArray(env.collisions) ? env.collisions : [];
  const engines = Array.isArray(env.engines) ? env.engines : [];
  const gitBash = env.gitBash || {};
  const wsl = env.wsl || 'UNKNOWN';
  const parts = [
    collisions.length > 0 ? `${collisions.length} colliding env group(s)` : 'no env collisions',
    `${engines.length} PowerShell engine(s)`,
    `WSL: ${wsl}`,
    gitBash.selected ? 'Git Bash resolved' : 'no Git Bash resolved',
  ];
  const status = collisions.length > 0 ? 'WARN' : 'PASS';
  return { ...cat('CAT-15', 'Windows Environment', status, parts.join(', ')), detail: env };
}

// --- CAT-16 Agent CLI Probe (cross-platform) --------------------------------
// Spec-AC-03/D4: each agent CLI is resolved and version-probed for real
// (never inferred from a harness name); the four SUBAGENT_PROTOCOL
// capability fields are reported as the literal UNKNOWN with a reason — they
// are runtime properties of the ORCHESTRATING SESSION, not observable from a
// child process — and are never converted into true/false. The codex `exec`
// subcommand observation is a separate, individually labelled fact.

const AGENT_CLIS = ['claude', 'codex', 'gemini'];
const CAPABILITY_REASON = 'resolved at runtime inside an agent session; not observable from a child process';

function resolveExecutable(root, name) {
  if (process.platform !== 'win32') {
    // POSIX: spawnSync with shell:false resolves a bare command name via
    // PATH itself (execvp semantics) — no manual search needed.
    return name;
  }
  // Windows: honor PATHEXT explicitly (Spec-AC-03) — spawning without a
  // shell means Node does not perform PATHEXT resolution for us.
  const pathDirs = String(process.env.PATH || process.env.Path || '').split(path.delimiter).filter(Boolean);
  const pathext = String(process.env.PATHEXT || '.COM;.EXE;.BAT;.CMD').split(';').filter(Boolean);
  for (const dir of pathDirs) {
    for (const ext of ['', ...pathext]) {
      const candidate = path.join(dir, name + ext);
      try {
        if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return candidate;
      } catch { /* unreadable dir entry — keep scanning */ }
    }
  }
  return null;
}

// CHANGE-0138 (F5/D2): every record carries the SAME three fields —
// { present: true | false | 'UNKNOWN', version, reason }. Only a non-empty
// FIRST STDOUT LINE may ever become a version (the old stdout||stderr
// fallback presented stderr diagnostics as versions); a resolved executable
// whose --version yields no stdout is present:true / version:null with a
// named reason (existence is not version knowledge); a timed-out or
// non-ENOENT-failing probe is the literal UNKNOWN (the ad-hoc `unknown: true`
// flag is retired in favor of the tri-state `present` value).
function resolveCliVersion(root, name) {
  const exe = resolveExecutable(root, name);
  if (!exe) return { present: false, version: null, reason: 'not found on PATH' };
  const res = run(exe, ['--version'], root, 5_000);
  if (res.error) {
    const timedOut = res.error.code === 'ETIMEDOUT' || res.error.killed === true;
    if (timedOut) return { present: 'UNKNOWN', version: null, reason: `${name} --version timed out` };
    if (res.error.code === 'ENOENT') return { present: false, version: null, reason: 'not found on PATH' };
    return { present: 'UNKNOWN', version: null, reason: `${name} --version failed to spawn (${res.error.code || 'unknown error'})` };
  }
  const firstLine = (res.stdout || '').split(/\r?\n/)[0].trim();
  if (firstLine) return { present: true, version: firstLine, reason: null };
  return { present: true, version: null, reason: `--version produced no stdout (exit ${res.status})` };
}

// CHANGE-0138 (N2/D1): the exec observation is derived only from
// Commands:/Subcommands: BLOCKS — what clap-style --help actually emits —
// never from a bare line-shape heuristic (rescope fixtures A/G fabricated
// true from indented prose; C/D false-negatived on tab / single-space
// separators). Header: a column-0 `Commands:`/`SUBCOMMANDS:` line with
// nothing after the colon but whitespace. Block: the following
// whitespace-indented lines; a blank line does NOT end the block, the first
// non-empty column-0 line (or EOF) does. Row: the token exactly `exec`
// followed by any single whitespace or end of line. No header anywhere ==
// honest UNKNOWN — prose-only output can no longer produce a boolean.
function parseCodexExecObservation(text) {
  const lines = text.split(/\r?\n/); // CRLF child output parses identically
  let sawHeader = false;
  for (let i = 0; i < lines.length; i++) {
    if (!/^(commands|subcommands):\s*$/i.test(lines[i])) continue;
    sawHeader = true;
    for (let j = i + 1; j < lines.length; j++) {
      const line = lines[j];
      if (line !== '' && !/^[ \t]/.test(line)) break; // non-empty column-0 ends the block
      if (/^[ \t]+exec([ \t]|$)/.test(line)) {
        return { available: true, reason: 'codex --help Commands: block lists an exec subcommand' };
      }
    }
  }
  if (!sawHeader) {
    return { available: 'UNKNOWN', reason: 'codex --help output has no Commands: block' };
  }
  return { available: false, reason: 'codex --help Commands: block does not list an exec subcommand' };
}

function probeCodexExecSubcommand(root, codexPresent) {
  // Tri-state guard: only a strict present === true earns a --help spawn —
  // an UNKNOWN (timed-out) codex would just hang the probe a second time.
  // The skip reason preserves WHICH non-true state blocked the probe (PR
  // #253 bot sweep): an UNKNOWN codex is not "not present", it is unproven.
  if (codexPresent !== true) {
    const reason = codexPresent === 'UNKNOWN'
      ? 'codex CLI state UNKNOWN (version probe inconclusive) - exec probe skipped'
      : 'codex CLI not present';
    return { available: 'UNKNOWN', reason };
  }
  const exe = resolveExecutable(root, 'codex');
  if (!exe) return { available: 'UNKNOWN', reason: 'codex CLI not present' };
  const res = run(exe, ['--help'], root, 5_000);
  if (res.error) return { available: 'UNKNOWN', reason: 'codex --help failed to run' };
  return parseCodexExecObservation(`${res.stdout || ''}\n${res.stderr || ''}`);
}

// CHANGE-0139 (spec-canonical-test-invocation D3): the canonical
// test-invocation contract probe. Probes .aai/AGENTS.md — the vendored,
// agent-facing surface every downstream agent reads at session start — for
// BOTH allowlist prefix literals (exactly the strings an approval allowlist
// matches, never prose that can drift). Tri-state `carried`: true when the
// file is readable and both literals present; false when readable and either
// literal missing (an outdated vendored layer — /aai-update is the remedy);
// the literal 'UNKNOWN' when the file is absent or unreadable (honest
// degrade, never a fabricated false). One readFileSync plus two includes():
// no spawn, no network. CAT-16 stays PASS-only — the signal lives in the
// reason segment and the --json detail, never in the exit code.
const CANONICAL_INVOCATION_FILE = '.aai/AGENTS.md';
const CANONICAL_INVOCATION_PREFIXES = [
  'powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1',
  'bash .aai/scripts/aai-run-tests.sh',
];

function probeCanonicalInvocation(root) {
  const text = readText(root, CANONICAL_INVOCATION_FILE);
  if (text === null) {
    return {
      file: CANONICAL_INVOCATION_FILE,
      carried: 'UNKNOWN',
      reason: `${CANONICAL_INVOCATION_FILE} is absent or unreadable - contract carriage cannot be observed`,
    };
  }
  const missing = CANONICAL_INVOCATION_PREFIXES.filter((p) => !text.includes(p));
  if (missing.length > 0) {
    return {
      file: CANONICAL_INVOCATION_FILE,
      carried: false,
      reason: `canonical test-invocation contract missing from ${CANONICAL_INVOCATION_FILE} (${missing.length} of 2 prefix literals absent) - outdated vendored layer; run /aai-update`,
    };
  }
  return { file: CANONICAL_INVOCATION_FILE, carried: true, reason: null };
}

function catAgentCliProbe(root) {
  const clis = {};
  for (const name of AGENT_CLIS) clis[name] = resolveCliVersion(root, name);
  const capabilities = {
    multi_agent_backend: { value: 'UNKNOWN', reason: CAPABILITY_REASON },
    spawn_agent_available: { value: 'UNKNOWN', reason: CAPABILITY_REASON },
    spawn_model_catalog: { value: 'UNKNOWN', reason: CAPABILITY_REASON },
    fork_turns_supported: { value: 'UNKNOWN', reason: CAPABILITY_REASON },
  };
  const codex_exec_subcommand = probeCodexExecSubcommand(root, clis.codex.present);
  const canonical_invocation = probeCanonicalInvocation(root);
  // CHANGE-0138 (F6/D2): strict equality everywhere — UNKNOWN can never
  // inflate the present count, and a timed-out probe is named on the line
  // (`, N unknown`) instead of being folded into absence. A present CLI
  // without a version is inside the present count and named by the
  // parenthesized segment. CAT-16 stays PASS-only: the honesty lives in the
  // line and the detail, never in the exit code.
  const records = Object.values(clis);
  const presentCount = records.filter((c) => c.present === true).length;
  const noVersionCount = records.filter((c) => c.present === true && c.version === null).length;
  const unknownCount = records.filter((c) => c.present === 'UNKNOWN').length;
  let counts = `${presentCount}/${AGENT_CLIS.length} agent CLI(s) present`;
  if (noVersionCount > 0) counts += ` (${noVersionCount} without version)`;
  if (unknownCount > 0) counts += `, ${unknownCount} unknown`;
  // CHANGE-0139: one short appended segment names the contract tri-state on
  // the single CAT-16 text line; the structured record lives in the detail.
  let contractSeg;
  if (canonical_invocation.carried === true) contractSeg = 'carried';
  else if (canonical_invocation.carried === false) contractSeg = 'MISSING (run /aai-update)';
  else contractSeg = 'UNKNOWN (.aai/AGENTS.md absent or unreadable)';
  const reason = `${counts}; four SUBAGENT_PROTOCOL capability fields reported UNKNOWN (${CAPABILITY_REASON}); canonical test-invocation contract: ${contractSeg}`;
  return {
    ...cat('CAT-16', 'Agent CLI Probe', 'PASS', reason),
    detail: { clis, capabilities, codex_exec_subcommand, canonical_invocation },
  };
}

// --- CLI ---------------------------------------------------------------------

function parseArgs(argv) {
  const args = { root: null, json: false, strict: false };
  const toks = argv.slice(2);
  for (let i = 0; i < toks.length; i++) {
    const tok = toks[i];
    if (tok === '--root') {
      const v = toks[++i];
      if (v === undefined) { console.error('aai-doctor: --root needs a value'); exit(2); }
      args.root = path.resolve(v);
    } else if (tok === '--json') {
      args.json = true;
    } else if (tok === '--strict') {
      args.strict = true;
    } else {
      console.error(`aai-doctor: unknown flag: ${tok}`);
      console.error('Usage: aai-doctor [--root <path>] [--json] [--strict]');
      exit(2);
    }
  }
  return args;
}

function defaultRoot() {
  // .aai/scripts/aai-doctor.mjs -> repo root is two levels up.
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
}

export function runDoctor(root, scriptDir) {
  const winProbe = runWinSelfTestProbe(root, scriptDir);
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
    catWinSelfTest(winProbe),
    catWinEnvironment(winProbe),
    catAgentCliProbe(root),
    catGitRefGuard(root),
  ];
}

function main() {
  const args = parseArgs(process.argv);
  const root = args.root || defaultRoot();
  if (!fs.existsSync(root)) {
    console.error(`aai-doctor: --root does not exist: ${root}`);
    exit(2);
  }
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const categories = runDoctor(root, scriptDir);
  const failCount = categories.filter((c) => c.status === 'FAIL').length;
  const warnOrFailCount = categories.filter((c) => c.status === 'WARN' || c.status === 'FAIL').length;
  // A SKIP is not a finding (matches --strict's own contract below, and the
  // SKILL_DOCTOR.prompt.md verdict-translation line): CAT-14/CAT-15 SKIP on
  // every non-Windows host, which is the NORMAL state there, not an issue.
  // Every category is still printed either way -- only the summary count
  // excludes SKIP.
  const issueCount = warnOrFailCount;
  const verdict = issueCount === 0 ? 'CLEAN' : 'ISSUES';
  let exitCode = failCount > 0 ? 1 : 0;
  if (args.strict && exitCode === 0 && warnOrFailCount > 0) exitCode = 1;

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
    // detail is a structured machine object (CAT-14/15/16) meant for --json
    // consumers; text mode is the paste-able report and never prints it
    // (a raw compact-JSON line here can run past a kilobyte — see --json).
    for (const c of categories) {
      console.log(`${c.id} ${c.status} ${c.reason}`);
    }
    console.log(`DOCTOR ${verdict === 'CLEAN' ? 'CLEAN' : `ISSUES(${issueCount})`}`);
  }
  exit(exitCode);
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  runMain(() => main());
}
