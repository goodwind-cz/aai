#!/usr/bin/env node
//
// hook-gate.mjs — the decisions of the Claude Code hook gate (RFC-0010 /
// spec-hook-enforced-gates), behind the bash launcher
// .aai/scripts/claude-hook-gate.sh (four gates). Each reads one PreToolUse/Stop
// payload (JSON on stdin) and either allows (exit 0) or deny (exit 2, the
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
// A command longer than COMMAND_CEILING that could concern a gate is denied before any scan (DG-15): the hook has a
// time limit, a hook that runs out of it is an allow, and a long command is the one way to make a scan run out of it.
// The decide() input may carry a `ceiling` of its own; only the tests set it, main() never does.
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
const MAX_TARGETS = 16;
// DG-15: the longest command, in UTF-16 code units, that a gate scans. A hook that runs out of time is a non-blocking
// error, that is an allow, so a command above this size that could concern a gate is denied before any scan.
const COMMAND_CEILING = 262144;

// Whitespace classes. WS goes inside a bracket expression, HS is one
// whitespace character that never crosses a line (grep matches line by line).
// The class is explicit, never JavaScript \s: \s also counts U+FEFF, which
// bash and grep never split on (DG-10), so a token would differ from the old
// gate's. The non-ASCII members are what [[:space:]] matched in a UTF-8 locale.
const WS_ASCII = ' \\t\\n\\v\\f\\r';
const WS = ASCII_SPACE_ONLY ? WS_ASCII : `${WS_ASCII}\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000`;
const HS = `[${WS.replace('\\n', '')}]`;
const SP = `[${WS}]`;
const NSP = `[^${WS}]`;
// ASCII-only twins (B4). Linux bash 5 split a merge target with tr, on ASCII
// white space in every locale. Every pattern that can ALLOW (the PR target of
// gate 2b, the lane path) uses these on every platform, so a non-ASCII
// separator never turns an old deny into an allow; the wide class above only
// widens what is DETECTED as a merge command.
const SPA = `[${WS_ASCII}]`;
const NSPA = `[^${WS_ASCII}]`;
const rx = (src, flags = '') => new RegExp(src, flags);

// grep -E per line (the m flag): the commit and merge command shapes. The git shape
// `(^|[;&|WS])git(HS+-NSP+(HS+X NSP*)?)*HS+<word>(HS|$)` is scanned by gitSubcommand below, not by one
// regular expression: nested quantifiers over a repeated `git -a ` run took quadratic time (51 s for a
// megabyte), and a hook that times out is a non-blocking error, that is an allow (DG-14). Every other
// pattern here has no nested quantifier and anchors on a literal word, so it runs in linear time.
const GH_MERGE_RE = rx(`(^|[;&|${WS}])gh${HS}+pr${HS}+merge(${HS}|$)`, 'm');
const MERGE_SEG_RE = rx(`gh${HS}+pr${HS}+merge(${HS}[^;&|\\n]*)?`, 'm');
const MERGE_SEG_ALL_RE = rx(MERGE_SEG_RE.source, 'gm');
const PLATFORM_MERGE_RE = rx(`(^|[;&|'"/${WS}])${PLATFORM_SCRIPT.replace(/\./g, '\\.')}${HS}+merge(${HS}|$)`, 'm');
// `az repos pr update ... --status completed`, scanned per segment by azureUpdateStarts (DG-14): the head and the
// status are two simple expressions, never one with a `[^;&|\n]*` between them.
const AZ_HEAD_RE = rx(`(^|${SP})az${HS}+repos${HS}+pr${HS}+update${HS}`, 'i');
const AZ_STATUS_RE = rx(`--status(${HS}+|=)["']?${AZURE_COMPLETED}["']?(${HS}|$)`, 'im');
const SEG_DELIM_RE = /[;&|\n]/g;
const NUMBER_RE = Object.fromEntries(['pr', 'id'].map((flag) => [flag, rx(`--${flag}(?:${SPA}+|=)["']?([0-9]+)["']?(?:${SPA}|$)`, 'g')]));
const STATE_DUMP_RE = /yaml\.dump|safe_dump|dump_all/;
const IN_PROGRESS_RE = rx(`^${HS}+status:${HS}*in_progress`, 'm');

// Whole-string (bash [[ =~ ]]) forms of the lane path: ^ and $ are the string
// ends and a newline is ordinary white space.
const NL = '\n';
const LANE_MARKER_RE = /^AAI_[A-Z0-9_]+_MERGE$/;
const LANE_ASSIGNS_RE = rx(`^${SPA}*([A-Za-z_][A-Za-z0-9_]*=${NSPA}*${SPA}+)*$`);
const LANE_SOLE_MERGE_RE = rx(`^${SPA}*([A-Za-z_][A-Za-z0-9_]*=${NSPA}*${SPA}+)*gh${SPA}+pr${SPA}+merge(${SPA}|$)`);
const LANE_PREFIX_RE = rx(`(^|[;&|(${NL}])([^;&|(${NL}]*)gh${SPA}+pr${SPA}+merge(${SPA}|$)`);
const LANE_ALLOWED_RE = /^MERGE-POLICY allowed pr=([0-9]+) lane=([^\s=]+) marker=(AAI_[A-Z0-9_]+_MERGE) decision_ref=([^\s=]+) merge_reaches=(nothing|preview|production)$/;
const LANE_MATCH_HEAD_RE = rx(`--match-head-commit${SPA}+([0-9a-fA-F]+)`);

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
// Linear: the pattern /\n+$/ retried at every newline of a run that is not at the end, so a long run cost k squared.
const stripNl = (s) => {
  const t = String(s ?? '');
  let e = t.length;
  while (e > 0 && t.charCodeAt(e - 1) === 10) e -= 1;
  return e === t.length ? t : t.slice(0, e);
};
const tailLines = (out, n) => `${`${out}\n`.split('\n').slice(0, -1).slice(-n).join('\n')}\n`;
const ALLOW = () => ({ code: 0, stderr: '' });

function parseRaw(text) {
  try {
    const j = JSON.parse(text);
    // bash drops a NUL in the command substitution that read the command, so the module does too.
    return { command: String((j.tool_input && j.tool_input.command) || '').replaceAll('\0', ''), cwd: String(j.cwd || '') };
  } catch {
    return { command: '', cwd: '' };
  }
}

export function parsePayload(text) {
  const p = parseRaw(text);
  return { command: stripNl(p.command), cwd: p.cwd };
}

// Could the command concern the gate? Only linear substring checks, each a necessary condition of the gate's own
// detection (the words its patterns hold), so a command that fails one is a command the gate allows anyway.
const MAYBE = {
  merge: (c) => (c.includes('merge') && (c.includes('git') || c.includes('gh') || c.includes(PLATFORM_SCRIPT))) || (/completed/i.test(c) && /az/i.test(c)),
  commit: (c) => c.includes('git') && c.includes('commit'),
  'state-dump': (c) => STATE_DUMP_RE.test(c) && c.includes('STATE.yaml'),
};
const DENY_HEAD = { merge: 'Merge denied', commit: 'Commit denied', 'state-dump': 'STATE write denied' };

function ceilingDeny(gate) {
  return lines([
    `${DENY_HEAD[gate]}: the command is longer than ${COMMAND_CEILING} characters (${COMMAND_CEILING / 1024} KiB) and may hold a ${gate} the gate cannot check in the time a hook has.`,
    'Put the long text in a file and run a short command that reads it.',
  ]);
}

// The command of a gate payload, the ceiling checked FIRST (DG-15): { deny } above it, else { command, cwd }.
function readCommand(gate, input) {
  const p = parseRaw(input.payload);
  if (p.command.length > (input.ceiling ?? COMMAND_CEILING) && MAYBE[gate](p.command)) return { deny: { code: 2, stderr: ceilingDeny(gate) } };
  return { command: stripNl(p.command), cwd: p.cwd };
}

const WS_CHAR_RE = rx(`^${SP}$`);
const HS_CHAR_RE = rx(`^${HS}$`);
const isWs = (c) => WS_CHAR_RE.test(c);
const isHs = (c) => HS_CHAR_RE.test(c);
const isDelim = (c) => ';&|'.includes(c) || isWs(c);

// True when the command holds `git [-opt [arg]]... <word>` as grep -E matched it: `git` at a line start or after
// `;`, `&`, `|` or white space; each option a token starting with `-`, followed by at most one token that does not
// start with `-`, `;`, `&` or `|`; then the word as a whole token. Same language as the regular expression it
// replaces, scanned once: a (position, state) pair already walked from an earlier `git` is never walked again.
function gitSubcommand(s, word) {
  let seen = null;
  const n = s.length;
  for (let p = s.indexOf('git'); p !== -1; p = s.indexOf('git', p + 1)) {
    if ((p > 0 && !isDelim(s[p - 1])) || p + 3 >= n || !isHs(s[p + 3])) continue;
    seen ??= [new Uint8Array(n + 1), new Uint8Array(n + 1)];
    let i = p + 3;
    let state = 0;
    for (;;) {
      let j = i;
      while (j < n && isHs(s[j])) j += 1;
      let k = j;
      while (k < n && !isWs(s[k])) k += 1;
      if (k === j || seen[state][j]) break;
      seen[state][j] = 1;
      const tok = s.slice(j, k);
      if (tok === word) return true;
      if (tok[0] === '-') {
        if (tok.length < 2) break;
        state = 1;
      } else if (state === 1 && !';&|'.includes(tok[0])) {
        state = 0;
      } else {
        break;
      }
      if (k >= n || !isHs(s[k])) break;
      i = k;
    }
  }
  return false;
}

// The start of `az` of every Azure completion, one per segment (a segment ends at `;`, `&`, `|` or a newline):
// the first `az repos pr update` of a segment decides, as the later ones have a shorter tail.
function azureUpdateStarts(command) {
  const out = [];
  if (!/az/i.test(command)) return out;
  const n = command.length;
  let from = 0;
  for (;;) {
    SEG_DELIM_RE.lastIndex = from;
    const m = SEG_DELIM_RE.exec(command);
    const end = m ? m.index + 1 : n;
    const seg = command.slice(from, m ? m.index : n); // the delimiter ends the status word, it is not part of it
    const h = AZ_HEAD_RE.exec(seg);
    if (h && AZ_STATUS_RE.test(seg.slice(h.index + h[0].length))) out.push(from + h.index + h[1].length);
    if (!m) break;
    from = end;
  }
  return out;
}

// The PR number of EVERY Azure merge segment (fail closed: a segment with no plain
// number gives ''). The number is ASCII digits after an ASCII separator or `=` only;
// a wide separator (`--pr<U+2003>7`) is no number, so the gate refuses to guess.
function azureNumbers(command) {
  const nums = [];
  const n = command.length;
  // One scan per segment, not per match: the numbers of a segment are listed once and each match takes the first at or after it.
  // pos only grows within a segment, so a cursor into the list replaces a search from its start.
  const numberAt = (flag, pos, st) => {
    if (pos > st.end) {
      SEG_DELIM_RE.lastIndex = pos;
      const m = SEG_DELIM_RE.exec(command);
      st.end = m ? m.index : n;
      st.list = [...command.slice(pos, st.end).matchAll(NUMBER_RE[flag])].map((x) => [x.index + pos, x[1]]);
      st.cur = 0;
    }
    while (st.cur < st.list.length && st.list[st.cur][0] < pos) st.cur += 1;
    const hit = st.list[st.cur];
    return hit ? hit[1] : '';
  };
  const stPr = { end: -1, list: [], cur: 0 };
  for (const m of command.matchAll(rx(PLATFORM_MERGE_RE.source, 'gm'))) nums.push(numberAt('pr', m.index + m[1].length, stPr));
  const stId = { end: -1, list: [], cur: 0 };
  for (const pos of azureUpdateStarts(command)) nums.push(numberAt('id', pos, stId));
  return nums;
}

export function isMergeCommand(command) {
  return gitSubcommand(command, 'merge') || GH_MERGE_RE.test(command) || PLATFORM_MERGE_RE.test(command) || azureUpdateStarts(command).length > 0;
}

export function mergeSegment(command) {
  const m = MERGE_SEG_RE.exec(command);
  return m ? m[0] : '';
}

// Every merge-shaped segment, in order, for the operator-marker path (no first-match).
export function mergeSegments(command) {
  return [...command.matchAll(MERGE_SEG_ALL_RE)].map((m) => m[0]);
}

// The allow-list over a `gh pr merge` segment's own tokens (lane path only).
export function checkMergeShape(segment) {
  const refuse = (verdict) => ({ ok: false, verdict });
  if (segment.includes("'") || segment.includes('"')) return refuse('lane path refused: a quote character is not permitted on the merge-policy lane');
  if (segment.includes('\\')) return refuse('lane path refused: a backslash is not permitted on the merge-policy lane');
  const rest = segment.replace(rx(`^${SPA}*gh${SPA}+pr${SPA}+merge`), '');
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
const FLAG_VALUE = '(-R|--repo|-b|--body|-F|--body-file|-t|--subject|--match-head-commit)';
const FLAG_DQ_RE = rx(`(^|${SPA})${FLAG_VALUE}${SPA}+"[^"]*"`, 'g');
const FLAG_SQ_RE = rx(`(^|${SPA})${FLAG_VALUE}${SPA}+'[^']*'`, 'g');
const FLAG_BARE_RE = rx(`(^|${SPA})${FLAG_VALUE}${SPA}+${NSPA}+`, 'g');
const MERGE_HEAD_RE = rx(`^${SPA}*gh${SPA}+pr${SPA}+merge`);
const OPTION_RE = rx(`(^|${SPA})-[A-Za-z0-9-]+`, 'g');
const SPA_RUN_RE = rx(`${SPA}+`);

// The merge target of a gh pr merge segment (the first token that is no option or option value), '' when it names none.
function mergeTarget(seg) {
  let search = seg.replace(FLAG_DQ_RE, '').replace(FLAG_SQ_RE, '').replace(FLAG_BARE_RE, '');
  search = search.replace(/"([0-9]+)"/g, ' $1 ').replace(/'([0-9]+)'/g, ' $1 ');
  return search.replace(MERGE_HEAD_RE, '').replace(OPTION_RE, '').split(SPA_RUN_RE).find(Boolean) || '';
}

function mergeTargetPr(seg, cmd, root, deps) {
  return resolveTarget(mergeTarget(seg), cmd, root, deps);
}

// The PR a merge target names: { pr } (empty when capability-absent) or { deny }.
function resolveTarget(target, cmd, root, deps) {
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
  if (!pr && target && !deps.which('gh')) {
    // Fail closed: with no gh a target that is not plain ASCII digits cannot be resolved to a PR.
    return { deny: lines([
      `Merge denied: gh is not available, and the merge target "${target}" is not a plain PR number,`,
      `so no sweep record can be checked for it. Command: ${cmd}`,
      "Run 'gh pr merge <N> ...' naming the PR by its number.",
    ]) };
  }
  if (!pr && !target && deps.which('gh')) {
    pr = view(['pr', 'view', '--json', 'number', '-q', '.number']);
    if (!pr) return { deny: unidentifiedPr(cmd) };
  }
  return { pr };
}

function tooManyTargets() {
  return lines([
    `Merge denied: this command names more than ${MAX_TARGETS} distinct merge targets, more than the gate checks in one command.`,
    "A target is one PR number or name after 'gh pr merge', or one --pr or --id number of an Azure completion; the same target twice counts once.",
    'Run the merges one command at a time.',
  ]);
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
  const read = readCommand('merge', input);
  if (read.deny) return read.deny;
  const { command: cmd, cwd } = read;
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
  // Every candidate is checked and any deny denies: a decoy segment never shields the real one. A command is denied
  // when it names more than MAX_TARGETS DISTINCT merge targets (DG-14): each distinct target costs at most two
  // process spawns (a gh pr view and a sweep check, each once), and a megabyte of segments must not spawn a process
  // each until the hook times out, which Claude Code reads as an allow. The same target spelled again is no new one.
  const counted = new Set();
  const admit = (key) => {
    if (!counted.has(key) && counted.size >= MAX_TARGETS) return false;
    counted.add(key);
    return true;
  };
  const resolved = new Map();
  const swept = new Map();
  const sweep = (pr) => {
    if (!swept.has(pr)) swept.set(pr, sweepDeny(pr, root, env, deps));
    return swept.get(pr);
  };
  for (const candidate of mergeSegments(cmd)) {
    const target = mergeTarget(candidate);
    if (!admit(/^[0-9]+$/.test(target) ? target : `name:${target}`)) return { code: 2, stderr: tooManyTargets() };
    if (!resolved.has(target)) resolved.set(target, resolveTarget(target, cmd, root, deps));
    const t = resolved.get(target);
    if (t.deny) return { code: 2, stderr: t.deny };
    const text = t.pr ? sweep(t.pr) : '';
    if (text) return { code: 2, stderr: text };
  }
  for (const pr of new Set(azureNumbers(cmd))) {
    if (!pr && deps.which('node') && deps.exists(`${root}/.aai/scripts/lane-gate.mjs`)) return { code: 2, stderr: unidentifiedPr(cmd) };
    if (pr && !admit(pr)) return { code: 2, stderr: tooManyTargets() };
    const text = pr ? sweep(pr) : '';
    if (text) return { code: 2, stderr: text };
  }
  return ALLOW();
}

function commitGate(input, deps) {
  const read = readCommand('commit', input);
  if (read.deny) return read.deny;
  const { command: cmd } = read;
  if (!cmd || !gitSubcommand(cmd, 'commit')) return ALLOW();
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
  const read = readCommand('state-dump', input);
  if (read.deny) return read.deny;
  const { command: cmd } = read;
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
  if (deps.exists(ticks) && Math.floor(deps.mtimeMs(ticks) / 1000) > Math.floor(deps.mtimeMs(state) / 1000)) return ALLOW();
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
    for (const e of exts) {
      try {
        const p = path.join(dir || '.', name + e);  // an empty entry is the current directory, as command -v read it
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
