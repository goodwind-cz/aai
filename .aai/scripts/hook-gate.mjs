#!/usr/bin/env node
//
// hook-gate.mjs — the decisions of the Claude Code hook gate (RFC-0010 /
// spec-hook-enforced-gates), behind the bash launcher
// .aai/scripts/claude-hook-gate.sh. Four gates read one PreToolUse/Stop
// payload (JSON on stdin) and either allow (exit 0) or deny (exit 2, the
// reason on stderr):
//   commit      run .aai/scripts/pre-commit-checks.sh before `git commit`
//   merge       constitution article 7 (operator-only merge); the merge-policy
//               lane path (merge-policy.mjs decides); gate 2b (lane-gate.mjs
//               --sweep-check decides); the Azure merge forms are gated too
//   state-dump  constitution article 6 (single-writer STATE)
//   stop-nudge  wrap-up reminder, NEVER blocks
// This module holds no gate predicate of its own: what blocks is decided by
// the scripts it spawns or by rules ratified elsewhere. FAIL-OPEN BY DESIGN:
// any internal error, an unknown gate or an unreadable payload exits 0 with
// nothing written; only a genuine gate verdict exits 2.
//
// Usage: node hook-gate.mjs <gate>   (payload on stdin; project root from
// CLAUDE_PROJECT_DIR, fallback `.`). Nothing is written to stdout except the
// stop-nudge line. Node stdlib only; no relative import.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const GATES = ['commit', 'merge', 'state-dump', 'stop-nudge'];
const ASCII_SPACE_ONLY = false;
const AZURE_COMPLETED = 'completed';
const PLATFORM_SCRIPT = 'platform.mjs';
const SWEEP_DENY_RC = 5;
const TAIL_COMMIT = 25;
const TAIL_SWEEP = 5;

// Whitespace classes. WS goes inside a bracket expression, HS is one
// whitespace character that never crosses a line (grep matches line by line).
const WS = ASCII_SPACE_ONLY ? ' \\t\\n\\v\\f\\r' : '\\s';
const HS = ASCII_SPACE_ONLY ? '[ \\t\\v\\f\\r]' : '[^\\S\\n]';
const rx = (src, flags = '') => new RegExp(src, flags);

// grep -E per line (the m flag): the commit and merge command shapes.
const GIT_PREFIX = `(^|[;&|${WS}])git(${HS}+-[^${WS}]+(${HS}+[^-;&|${WS}][^${WS}]*)?)*${HS}+`;
const COMMIT_RE = rx(`${GIT_PREFIX}commit(${HS}|$)`, 'm');
const GIT_GH_MERGE_RE = rx(`${GIT_PREFIX}merge(${HS}|$)|(^|[;&|${WS}])gh${HS}+pr${HS}+merge(${HS}|$)`, 'm');
const MERGE_SEG_RE = rx(`gh${HS}+pr${HS}+merge(${HS}[^;&|\\n]*)?`, 'm');
const PLATFORM_MERGE_RE = rx(`(^|[;&|'"/${WS}])${PLATFORM_SCRIPT.replace(/\./g, '\\.')}${HS}+merge(${HS}|$)`, 'm');
const AZURE_UPDATE_RE = rx(`(^|[;&|${WS}])az${HS}+repos${HS}+pr${HS}+update(${HS}|$)[^;&|\\n]*--status(${HS}+|=)["']?${AZURE_COMPLETED}["']?(${HS}|$)`, 'im');
const STATE_DUMP_RE = /yaml\.dump|safe_dump|dump_all/;
const IN_PROGRESS_RE = rx(`^${HS}+status:${HS}*in_progress`, 'm');

// Whole-string (bash [[ =~ ]]) forms of the lane path: ^ and $ are the string
// ends and a newline is ordinary white space.
const NL = '\n';
const LANE_MARKER_RE = /^AAI_[A-Z0-9_]+_MERGE$/;
const LANE_ASSIGNS_RE = rx(`^\\s*([A-Za-z_][A-Za-z0-9_]*=[^\\s]*\\s+)*$`);
const LANE_SOLE_MERGE_RE = rx(`^\\s*([A-Za-z_][A-Za-z0-9_]*=[^\\s]*\\s+)*gh\\s+pr\\s+merge(\\s|$)`);
const LANE_PREFIX_RE = rx(`(^|[;&|(${NL}])([^;&|(${NL}]*)gh\\s+pr\\s+merge(\\s|$)`);
const LANE_ALLOWED_RE = /^MERGE-POLICY allowed pr=([0-9]+) lane=([^\s=]+) marker=(AAI_[A-Z0-9_]+_MERGE) decision_ref=([^\s=]+) merge_reaches=(nothing|preview|production)$/;
const LANE_MATCH_HEAD_RE = /--match-head-commit\s+([0-9a-fA-F]+)/;

const ARTICLE7_LINES = [
  'Merge denied: constitution article 7 (operator-only merge) — the agent never merges;',
  "the PR ceremony ends at 'gh pr create' (.aai/SKILL_PR.prompt.md step 6).",
  'If the OPERATOR explicitly directed this merge, run it with AAI_OPERATOR_MERGE=1.',
  '(Guardrail, not a security boundary — setting the marker without operator direction',
  'is a constitution violation.)',
];
const STATE_DUMP_LINES = [
  'STATE write denied: docs/ai/STATE.yaml has exactly ONE writer — the transactional CLI',
  'node .aai/scripts/state.mjs (constitution article 6). Whole-file YAML serialization',
  '(yaml.dump/safe_dump) destroys the commented schema header and reorders keys',
  '(SPEC-0019 manual-flush lesson). Use the state.mjs subcommands instead.',
];
const NUDGE = 'AAI wrap-up nudge: docs/ai/STATE.yaml still has an in_progress work item and no loop tick was logged after the last state change. Consider /aai-wrap-up (capture learnings, close the item) or log the tick via node .aai/scripts/state.mjs log-tick. (Reminder only — never blocks.)';

const lines = (arr) => arr.map((l) => `${l}\n`).join('');
const stripNl = (s) => String(s ?? '').replace(/\n+$/, '');
const tailLines = (out, n) => `${`${out}\n`.split('\n').slice(0, -1).slice(-n).join('\n')}\n`;
const ALLOW = () => ({ code: 0, stderr: '' });

export function parsePayload(text) {
  try {
    const j = JSON.parse(text);
    const command = String((j.tool_input && j.tool_input.command) || '');
    return { command: stripNl(command), cwd: String(j.cwd || '') };
  } catch {
    return { command: '', cwd: '' };
  }
}

function azureNumber(command) {
  for (const [re, flag] of [[PLATFORM_MERGE_RE, 'pr'], [AZURE_UPDATE_RE, 'id']]) {
    const m = re.exec(command);
    if (!m) continue;
    const segment = command.slice(m.index + m[1].length).split(/[;&|\n]/)[0];
    const n = segment.match(rx(`--${flag}(?:${HS}+|=)["']?([0-9]+)["']?(?:${HS}|$)`));
    if (n) return n[1];
  }
  return '';
}

export function isMergeCommand(command) {
  return GIT_GH_MERGE_RE.test(command) || PLATFORM_MERGE_RE.test(command) || AZURE_UPDATE_RE.test(command);
}

export function mergeSegment(command) {
  const m = MERGE_SEG_RE.exec(command);
  return m ? m[0] : '';
}

// The allow-list over a `gh pr merge` segment's own tokens (lane path only).
export function checkMergeShape(segment) {
  const refuse = (verdict) => ({ ok: false, verdict });
  if (segment.includes("'") || segment.includes('"')) return refuse('lane path refused: a quote character is not permitted on the merge-policy lane');
  if (segment.includes('\\')) return refuse('lane path refused: a backslash is not permitted on the merge-policy lane');
  const rest = segment.replace(/^\s*gh\s+pr\s+merge/, '');
  const tokens = rest.split(/[ \t\n]+/).filter(Boolean);
  let havePr = false; let haveMode = false; let haveDelete = false; let haveMatch = false;
  for (let i = 0; i < tokens.length; i += 1) {
    let tok = tokens[i];
    if (tok.includes('=')) return refuse(`lane path refused: ${tok} is not permitted on the merge-policy lane`);
    if (tok === '--match-head-commit') {
      if (haveMatch) return refuse('lane path refused: --match-head-commit is not permitted more than once on the merge-policy lane');
      i += 1;
      tok = tokens[i] ?? '';
      if (!tok || /[^0-9a-fA-F]/.test(tok)) return refuse('lane path refused: --match-head-commit requires a hex commit value');
      haveMatch = true;
    } else if (tok === '--squash' || tok === '--merge' || tok === '--rebase') {
      if (haveMode) return refuse(`lane path refused: ${tok} is not permitted on the merge-policy lane`);
      haveMode = true;
    } else if (tok === '--delete-branch') {
      if (haveDelete) return refuse('lane path refused: --delete-branch is not permitted more than once on the merge-policy lane');
      haveDelete = true;
    } else if (/[^0-9]/.test(tok)) {
      return refuse(`lane path refused: ${tok} is not permitted on the merge-policy lane`);
    } else {
      if (havePr) return refuse(`lane path refused: ${tok} is not permitted on the merge-policy lane`);
      havePr = true;
    }
  }
  if (!havePr) return refuse('lane path refused: a PR number is required on the merge-policy lane');
  return { ok: true };
}

function article7(laneVerdict) {
  return lines(ARTICLE7_LINES) + (laneVerdict ? `merge-policy: ${laneVerdict}\n` : '');
}

const realOrNull = (p) => { try { return fs.realpathSync(p); } catch { return null; } };

// `cd DIR && cd "$(git rev-parse --git-common-dir)" && pwd -P`; a failing git
// prints nothing and `cd ""` stays in DIR.
function gitCommonDir(dir, deps) {
  if (!dir || !realOrNull(dir)) return '';
  const r = deps.run('git', ['rev-parse', '--git-common-dir'], { cwd: dir });
  const out = r.status === 0 ? stripNl(r.stdout) : '';
  return realOrNull(out ? path.resolve(dir, out) : dir) || '';
}

function sweepExtra(env, withBase) {
  const extra = [];
  if (env.AAI_SWEEP_SPEC) extra.push('--spec', env.AAI_SWEEP_SPEC);
  if (env.AAI_SWEEP_INTAKE) extra.push('--intake', env.AAI_SWEEP_INTAKE);
  if (env.AAI_SWEEP_STATE) extra.push('--state', env.AAI_SWEEP_STATE);
  if (withBase && env.AAI_SWEEP_BASE_REF) extra.push('--base-ref', env.AAI_SWEEP_BASE_REF);
  return extra;
}

// The ONE PR-resolution routine of the merge gate, shared by gate 2b and the
// lane path. Returns { pr } (empty when capability-absent) or { deny }.
function mergeTargetPr(seg, cmd, root, deps) {
  const flagValue = '(-R|--repo|-b|--body|-F|--body-file|-t|--subject|--match-head-commit)';
  let search = seg
    .replace(rx(`(^|\\s)${flagValue}\\s+"[^"]*"`, 'g'), '')
    .replace(rx(`(^|\\s)${flagValue}\\s+'[^']*'`, 'g'), '')
    .replace(rx(`(^|\\s)${flagValue}\\s+[^\\s]+`, 'g'), '');
  search = search.replace(/"([0-9]+)"/g, ' $1 ').replace(/'([0-9]+)'/g, ' $1 ');
  const target = search.replace(/^\s*gh\s+pr\s+merge/, '').replace(/(^|\s)-[A-Za-z0-9-]+/g, '')
    .split(/\s+/).find(Boolean) || '';
  const view = (args) => {
    const r = deps.run('gh', args, { cwd: root });
    const out = r.status === 0 ? stripNl(r.stdout) : '';
    return /^[0-9]+$/m.test(out) ? out : '';
  };
  let pr = '';
  if (/^[0-9]+$/.test(target)) {
    pr = target;
  } else if (target && deps.which('gh')) {
    pr = view(['pr', 'view', target, '--json', 'number', '-q', '.number']);
    if (!pr) {
      return { deny: lines([
        `Merge denied: could not resolve a PR for target "${target}".`,
        `Command: ${cmd}`,
        `'gh pr view ${target} --json number' did not resolve one (Spec-AC-34, issue`,
        '338) -- this gate refuses to guess rather than allow a merge it cannot check',
        'a sweep record for.',
      ]) };
    }
  }
  if (!pr && !target && deps.which('gh')) {
    pr = view(['pr', 'view', '--json', 'number', '-q', '.number']);
    if (!pr) return { deny: unidentifiedPr(cmd) };
  }
  return { pr };
}

function unidentifiedPr(cmd) {
  return lines([
    'Merge denied: could not determine which PR this merge command targets.',
    `Command: ${cmd}`,
    "No positional PR number, and 'gh pr view --json number' (current branch) did",
    'not resolve one either (Spec-AC-34, issue 338) -- this gate refuses to guess',
    'rather than allow a merge it cannot check a sweep record for.',
    "Run 'gh pr merge <N> ...' naming the PR explicitly, or merge from a branch",
    'with exactly one open PR.',
  ]);
}

function lanePrefix(cmd) {
  const m = LANE_PREFIX_RE.exec(cmd);
  return m ? m[2] : null;
}

function laneMarkers(cmd, env) {
  const names = Object.keys(env).filter((n) => LANE_MARKER_RE.test(n) && n !== 'AAI_OPERATOR_MERGE' && env[n] === '1');
  const pre = lanePrefix(cmd);
  if (pre !== null && LANE_ASSIGNS_RE.test(pre)) {
    for (const w of pre.split(/[ \t\n]+/).filter(Boolean)) {
      const name = w.slice(0, w.includes('=') ? w.indexOf('=') : w.length);
      const value = w.includes('=') ? w.slice(w.indexOf('=') + 1) : w;
      if (name !== 'AAI_OPERATOR_MERGE' && value === '1' && LANE_MARKER_RE.test(name)) names.push(name);
    }
  }
  return names;
}

// The merge-policy lane path (P9): { allowed: true } or { verdict }.
function lanePath(ctx) {
  const { cmd, seg, root, env, deps, markers, cwd } = ctx;
  const refuse = (verdict) => ({ verdict });
  if (/[\n;&|`$()<>\\]/.test(cmd)) return refuse('lane path refused: the command must be a single gh pr merge, with no chaining, substitution or redirection');
  if (!LANE_SOLE_MERGE_RE.test(cmd)) return refuse('lane path refused: lane markers cover gh pr merge only');
  const shape = checkMergeShape(seg);
  if (!shape.ok) return refuse(shape.verdict);
  const pre = lanePrefix(cmd) ?? '';
  for (const w of pre.split(/[ \t\n]+/).filter(Boolean)) {
    const name = w.slice(0, w.includes('=') ? w.indexOf('=') : w.length);
    const value = w.includes('=') ? w.slice(w.indexOf('=') + 1) : w;
    if (!LANE_MARKER_RE.test(name) || name === 'AAI_OPERATOR_MERGE' || value !== '1') return refuse(`lane path refused: leading assignment ${name} is not a lane marker`);
  }
  if (!deps.which('node')) return refuse('evaluator unavailable: node not found');
  if (!deps.exists(`${root}/.aai/scripts/merge-policy.mjs`)) return refuse('evaluator unavailable: .aai/scripts/merge-policy.mjs not found');
  if (!deps.which('gh')) return refuse('evaluator unavailable: gh not found');
  const rootGit = gitCommonDir(root, deps);
  const cwdGit = cwd ? gitCommonDir(cwd, deps) : '';
  if (!rootGit || rootGit !== cwdGit) return refuse(`lane path refused: the command's cwd (${cwd || 'unknown'}) is not this project's repository`);
  const resolved = mergeTargetPr(seg, cmd, root, deps);
  const pr = resolved.deny ? '' : resolved.pr;
  if (!/^[0-9]+$/.test(pr)) return refuse('lane path refused: could not resolve the PR this command merges');
  const headRun = deps.run('gh', ['pr', 'view', pr, '--json', 'headRefOid', '-q', '.headRefOid'], { cwd: root });
  const head = headRun.status === 0 ? stripNl(headRun.stdout) : '';
  if (!/^[0-9a-fA-F]+$/.test(head)) return refuse(`lane path refused: could not resolve the head commit of PR ${pr}`);
  const mh = LANE_MATCH_HEAD_RE.exec(seg);
  if (!mh) return refuse(`lane path refused: the merge-policy lane requires --match-head-commit ${head}`);
  if (mh[1] !== head) return refuse(`lane path refused: --match-head-commit ${mh[1]} does not match PR ${pr}'s head (${head})`);
  const mp = deps.run('node', [`${root}/.aai/scripts/merge-policy.mjs`, '--check', '--pr', pr, '--repo-root', root, ...sweepExtra(env, false)], { cwd: root });
  const mpRc = mp.status ?? 1;
  const mpLine = stripNl(mp.stdout).split(NL)[0];
  const ok = mpRc === 0 ? LANE_ALLOWED_RE.exec(mpLine) : null;
  if (ok && ok[1] === pr) {
    if (markers.includes(ok[3])) return { allowed: true };
    return refuse(`${mpLine} (lane marker ${ok[3]} is not set)`);
  }
  return refuse(`${mpLine || 'evaluator gave no verdict'} (exit ${mpRc})`);
}

// Gate 2b: lane-gate.mjs --sweep-check for PR `pr`; a deny text or ''.
function sweepDeny(pr, root, env, deps) {
  if (!deps.which('node') || !deps.exists(`${root}/.aai/scripts/lane-gate.mjs`)) return '';
  const args = [`${root}/.aai/scripts/lane-gate.mjs`, '--sweep-check', '--pr', pr, '--repo-root', root, ...sweepExtra(env, true)];
  const r = deps.run('node', args, { cwd: root, merge: true });
  if (r.status !== SWEEP_DENY_RC) return '';
  return lines([`Merge denied: no valid post-open review sweep record for PR ${pr} (Spec-AC-34, issue 338).`])
    + tailLines(stripNl(r.stdout), TAIL_SWEEP)
    + lines(['Record one with .aai/scripts/append-event.mjs --event pr_sweep ..., then retry.']);
}

function mergeGate(input, deps) {
  const { command: cmd, cwd } = parsePayload(input.payload);
  const { env, root } = input;
  if (!cmd || !isMergeCommand(cmd)) return ALLOW();
  const seg = mergeSegment(cmd);
  let verdict = '';
  let allowed = false;
  if (env.AAI_OPERATOR_MERGE !== '1') {
    const markers = laneMarkers(cmd, env);
    if (markers.length) {
      const r = lanePath({ cmd, seg, root, env, deps, markers, cwd });
      allowed = Boolean(r.allowed);
      verdict = r.verdict || '';
    }
    if (!allowed) return { code: 2, stderr: article7(verdict) };
  }
  if (seg) {
    const t = mergeTargetPr(seg, cmd, root, deps);
    if (t.deny) return { code: 2, stderr: t.deny };
    const text = t.pr ? sweepDeny(t.pr, root, env, deps) : '';
    if (text) return { code: 2, stderr: text };
  }
  if (PLATFORM_MERGE_RE.test(cmd) || AZURE_UPDATE_RE.test(cmd)) {
    const pr = azureNumber(cmd);
    if (!pr && deps.which('node') && deps.exists(`${root}/.aai/scripts/lane-gate.mjs`)) return { code: 2, stderr: unidentifiedPr(cmd) };
    const text = pr ? sweepDeny(pr, root, env, deps) : '';
    if (text) return { code: 2, stderr: text };
  }
  return ALLOW();
}

function commitGate(input, deps) {
  const { command: cmd } = parsePayload(input.payload);
  if (!cmd || !COMMIT_RE.test(cmd)) return ALLOW();
  const checks = `${input.root}/.aai/scripts/pre-commit-checks.sh`;
  if (!deps.exists(checks)) return ALLOW();
  const r = deps.run('bash', [checks], { cwd: input.root, merge: true });
  if (r.status === 0) return ALLOW();
  return {
    code: 2,
    stderr: lines(['AAI pre-commit gate blocked this commit (.aai/scripts/pre-commit-checks.sh exited non-zero):'])
      + tailLines(stripNl(r.stdout), TAIL_COMMIT)
      + lines(['Fix the reported errors, then retry the commit. (Hook mirrors the existing gate; RFC-0010.)']),
  };
}

function stateDumpGate(input) {
  const { command: cmd } = parsePayload(input.payload);
  if (!cmd || !STATE_DUMP_RE.test(cmd) || !/STATE\.yaml/.test(cmd)) return ALLOW();
  return { code: 2, stderr: lines(STATE_DUMP_LINES) };
}

function stopNudge(input, deps) {
  const state = `${input.root}/docs/ai/STATE.yaml`;
  if (!deps.exists(state)) return ALLOW();
  let text;
  try { text = deps.readFile(state); } catch { return ALLOW(); }
  if (!IN_PROGRESS_RE.test(text)) return ALLOW();
  const ticks = `${input.root}/docs/ai/LOOP_TICKS.jsonl`;
  if (deps.exists(ticks) && deps.mtimeMs(ticks) > deps.mtimeMs(state)) return ALLOW();
  return { code: 0, stderr: '', stdout: `${NUDGE}\n` };
}

const HANDLERS = { commit: commitGate, merge: mergeGate, 'state-dump': stateDumpGate, 'stop-nudge': stopNudge };

// decide(gate, { payload, env, root }, deps) -> { code, stderr[, stdout] }.
export function decide(gate, input, deps) {
  if (!GATES.includes(gate)) return ALLOW();
  return HANDLERS[gate](input, deps);
}

function which(name, env) {
  const exts = process.platform === 'win32' ? ['', '.exe', '.cmd', '.bat'] : [''];
  for (const dir of String(env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    for (const e of exts) {
      try {
        const p = path.join(dir, name + e);
        if (fs.statSync(p).isFile()) { fs.accessSync(p, fs.constants.X_OK); return true; }
      } catch { /* next */ }
    }
  }
  return false;
}

function realDeps(env) {
  return {
    which: (name) => which(name, env),
    exists: (p) => { try { return fs.statSync(p).isFile(); } catch { return false; } },
    readFile: (p) => fs.readFileSync(p, 'utf8'),
    mtimeMs: (p) => fs.statSync(p).mtimeMs,
    run: (cmd, args, opts = {}) => {
      const o = { cwd: opts.cwd, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] };
      const r = opts.merge
        ? spawnSync('sh', ['-c', 'exec "$@" 2>&1', 'sh', cmd, ...args], o)
        : spawnSync(cmd, args, o);
      return { status: r.error ? null : r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
    },
  };
}

function readStdin() {
  const chunks = [];
  const buf = Buffer.alloc(65536);
  for (;;) {
    try {
      const n = fs.readSync(0, buf, 0, buf.length, null);
      if (n === 0) break;
      chunks.push(Buffer.from(buf.subarray(0, n)));
    } catch (e) {
      if (e.code === 'EAGAIN') continue;
      if (e.code === 'EOF') break;
      break;
    }
  }
  return Buffer.concat(chunks).toString('utf8');
}

function writeAll(fd, text) {
  const b = Buffer.from(text, 'utf8');
  let off = 0;
  while (off < b.length) {
    try { off += fs.writeSync(fd, b, off); } catch (e) { if (e.code !== 'EAGAIN') return; }
  }
}

export function main(argv = process.argv.slice(2), env = process.env, deps = realDeps(env), payload = readStdin) {
  try {
    const gate = argv[0] || '';
    if (!GATES.includes(gate)) return 0;
    const r = decide(gate, { payload: payload(), env, root: env.CLAUDE_PROJECT_DIR || '.' }, deps);
    if (r.stdout) writeAll(1, r.stdout);
    if (r.stderr) writeAll(2, r.stderr);
    return r.code === 2 ? 2 : 0;
  } catch {
    return 0;
  }
}

const realOrResolve = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) process.exitCode = main();
