#!/usr/bin/env node
// unattended-gate.mjs — the deterministic auto-versus-park boundary for an
// opted-in unattended ride (RFC-0014 D1 / SPEC-0174-spec-unattended-rides-
// human-gate-at-merge). The trigger set is CLOSED and mechanically stamped
// (`[HITL-<n>]` by .aai/ORCHESTRATION_HITL.prompt.md; `stagnation` /
// `run-budget` / `review-round-cap` by .aai/SKILL_LOOP.prompt.md's own stop
// conditions) — this engine never asks a role to grade its own question.
//
//   node .aai/scripts/unattended-gate.mjs classify --trigger <t> --ref <ref>
//        [--question <q>] [--answer <a>] [--source <s>]
//        [--worktree-recommendation <not_needed|optional|recommended|required>]
//        [--ceremony <0-3>] [--ledger <path>] [--json]
//   node .aai/scripts/unattended-gate.mjs preflight [--intake <path>]
//        [--max-ticks <n>] [--stagnation-limit <n>] [--max-run-tokens <n>]
//        [--max-run-cost-usd <n>] [--max-prs <n>] [--json]
//   node .aai/scripts/unattended-gate.mjs summary --since <ISO8601>
//        [--ledger <path>]
//
// Exit codes: 0 admit/auto · 3 refuse/park · 2 usage · 1 ledger append failed
// (classify only — no verdict is ever printed when the audit line could not
// be written, D3).
//
// D2 — this file contains NO code path that can emit the string "waived",
// for any trigger, flag or environment variable. HITL-9 always resolves
// "fail". Do not add one; a waiver is never an autonomous outcome.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const DEFAULT_LEDGER = path.join(ROOT, 'docs/ai/decisions.jsonl');

function usage(msg) {
  process.stderr.write(`unattended-gate: ${msg}\n`);
  process.exit(2);
}

// --- D1: the frozen 13-row table (RFC-0014 D1 / spec ## Design decisions) ---
// Every row: class is one of quality|scope|cost|irreversibility|guard|unknown.
// `auto` rows resolve without a human; `park` rows always stop for one.
const D1_TABLE = Object.freeze({
  'HITL-1': { class: 'scope', decision: 'park' },
  'HITL-2': { class: 'scope', decision: 'park' },
  'HITL-3': { class: 'irreversibility', decision: 'park' },
  'HITL-4': { class: 'irreversibility', decision: 'park' },
  'HITL-5': { class: 'quality', decision: 'auto' },
  'HITL-6': { class: 'cost', decision: 'park' },
  'HITL-7': { class: 'quality', decision: 'auto' }, // conditional park below
  'HITL-8': { class: 'quality', decision: 'auto' },
  'HITL-9': { class: 'quality', decision: 'auto' },
  stagnation: { class: 'guard', decision: 'park' },
  'run-budget': { class: 'cost', decision: 'park' },
  'review-round-cap': { class: 'scope', decision: 'park' },
});

const WORKTREE_RESOLUTION = Object.freeze({
  not_needed: 'inline',
  optional: 'inline',
  recommended: 'worktree',
  // 'required' is never resolved here — it always parks (see classifyTrigger).
});

function parseClassifyArgs(argv) {
  const a = {
    trigger: undefined,
    ref: null,
    question: '',
    answer: null,
    source: 'unattended-gate default',
    worktreeRecommendation: 'optional',
    ceremony: 0,
    ledger: DEFAULT_LEDGER,
    json: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const k = argv[i];
    const v = argv[i + 1];
    const needVal = () => { if (v === undefined) usage(`${k} requires a value`); return v; };
    if (k === '--trigger') { a.trigger = needVal(); i += 1; }
    else if (k === '--ref') { a.ref = needVal(); i += 1; }
    else if (k === '--question') { a.question = needVal(); i += 1; }
    else if (k === '--answer') { a.answer = needVal(); i += 1; }
    else if (k === '--source') { a.source = needVal(); i += 1; }
    else if (k === '--worktree-recommendation') { a.worktreeRecommendation = needVal(); i += 1; }
    else if (k === '--ceremony') { a.ceremony = Number(needVal()); i += 1; }
    else if (k === '--ledger') { a.ledger = needVal(); i += 1; }
    else if (k === '--json') { a.json = true; }
    else usage(`unknown argument ${k}`);
  }
  if (!a.ref) usage('classify requires --ref <id>');
  if (!['not_needed', 'optional', 'recommended', 'required'].includes(a.worktreeRecommendation)) {
    usage(`--worktree-recommendation must be one of not_needed|optional|recommended|required, got "${a.worktreeRecommendation}"`);
  }
  if (!Number.isInteger(a.ceremony) || a.ceremony < 0 || a.ceremony > 3) {
    usage('--ceremony must be an integer 0..3');
  }
  return a;
}

function parsePreflightArgs(argv) {
  const a = {
    intake: null,
    maxTicks: 20,
    stagnationLimit: 3,
    maxRunTokens: 0,
    maxRunCostUsd: 0,
    maxPrs: 3,
    json: false,
  };
  const numFlag = (k, v, dest) => {
    if (v === undefined) usage(`${k} requires a value`);
    const n = Number(v);
    if (!Number.isFinite(n)) usage(`${k} must be numeric, got "${v}"`);
    a[dest] = n;
  };
  for (let i = 0; i < argv.length; i += 1) {
    const k = argv[i];
    const v = argv[i + 1];
    if (k === '--intake') { if (v === undefined) usage('--intake requires a value'); a.intake = v; i += 1; }
    else if (k === '--max-ticks') { numFlag(k, v, 'maxTicks'); i += 1; }
    else if (k === '--stagnation-limit') { numFlag(k, v, 'stagnationLimit'); i += 1; }
    else if (k === '--max-run-tokens') { numFlag(k, v, 'maxRunTokens'); i += 1; }
    else if (k === '--max-run-cost-usd') { numFlag(k, v, 'maxRunCostUsd'); i += 1; }
    else if (k === '--max-prs') { numFlag(k, v, 'maxPrs'); i += 1; }
    else if (k === '--json') { a.json = true; }
    else usage(`unknown argument ${k}`);
  }
  return a;
}

function parseSummaryArgs(argv) {
  const a = { since: null, ledger: DEFAULT_LEDGER };
  for (let i = 0; i < argv.length; i += 1) {
    const k = argv[i];
    const v = argv[i + 1];
    if (k === '--since') { if (v === undefined) usage('--since requires a value'); a.since = v; i += 1; }
    else if (k === '--ledger') { if (v === undefined) usage('--ledger requires a value'); a.ledger = v; i += 1; }
    else usage(`unknown argument ${k}`);
  }
  if (!a.since) usage('summary requires --since <ISO8601>');
  return a;
}

// --- classify ----------------------------------------------------------------

function shellSingleQuote(s) {
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

// The HITL token in blocking_reason is stamped as `[HITL-<n>]`. The D1 table
// keys are the bare `HITL-<n>` form SKILL_HITL STEP 4c uses. Strip only that
// exact display wrapper — never trim, never case-fold, never a partial match.
function bareTrigger(rawTrigger) {
  const t = typeof rawTrigger === 'string' ? rawTrigger : '';
  const m = /^\[(HITL-\d+)\]$/.exec(t);
  return m ? m[1] : t;
}

// Resolve the D1 row for a raw trigger token. Absent/empty/malformed/case-
// mismatched/whitespace-padded/invented tokens ALL fall to the closed
// "unknown" row (fail-closed) — never a guess, never a partial match.
function resolveRow(rawTrigger) {
  const t = bareTrigger(rawTrigger);
  if (Object.prototype.hasOwnProperty.call(D1_TABLE, t)) return { trigger: t, row: D1_TABLE[t] };
  return { trigger: t || '(absent)', row: { class: 'unknown', decision: 'park' } };
}

// HITL-7's park-vs-auto is conditional (D1): `required` always parks, and
// ceremony 3 always parks even when the recommendation itself is auto-eligible.
function hitl7Decision(worktreeRecommendation, ceremony) {
  if (worktreeRecommendation === 'required' || ceremony === 3) return 'park';
  return 'auto';
}

// Every literal produced anywhere in this function is a fixed string chosen
// by THIS engine — never an echo of caller input for HITL-9 (D2: waived is
// unreachable, whatever --answer or the environment claims).
function classifyTrigger(a) {
  const { trigger, row } = resolveRow(a.trigger);
  let decision = row.decision;
  let answer = '';
  let targetCommand = '';

  if (trigger === 'HITL-7') {
    decision = hitl7Decision(a.worktreeRecommendation, a.ceremony);
    if (decision === 'auto') {
      answer = WORKTREE_RESOLUTION[a.worktreeRecommendation] || 'inline';
      targetCommand = `node .aai/scripts/state.mjs set-worktree --user-decision ${answer}`;
    }
  } else if (trigger === 'HITL-9') {
    decision = 'auto';
    answer = 'fail'; // fixed literal — D2, never derived from input
    targetCommand = 'node .aai/scripts/state.mjs set-code-review --status fail';
  } else if (trigger === 'HITL-8') {
    decision = 'auto';
    const provided = a.answer != null && a.answer !== '';
    answer = provided ? a.answer : 'inferred: <path not provided>';
    // POSIX-single-quote --scope so a path with `"`, `$()`, backticks or
    // newlines cannot break the shell line SKILL_LOOP executes. No --answer
    // means no command: LOOP treats empty HITL-8 target_command as park.
    targetCommand = provided
      ? `node .aai/scripts/state.mjs set-code-review --scope ${shellSingleQuote(answer)}`
      : '';
  } else if (trigger === 'HITL-5') {
    decision = 'auto';
    answer = a.answer != null && a.answer !== '' ? a.answer : 'recommended-default';
    targetCommand = ''; // STEP 4c's declared target for HITL-5 is "none"
  }
  // every other row (park) carries answer '' and targetCommand ''

  return {
    decision,
    class: row.class,
    trigger,
    ref_id: a.ref,
    question: a.question || '',
    answer,
    source: a.source || 'unattended-gate default',
    target_command: targetCommand,
  };
}

function appendLedgerLine(ledgerPath, rec) {
  const line = `${JSON.stringify(rec)}\n`;
  try {
    fs.mkdirSync(path.dirname(ledgerPath), { recursive: true });
    fs.appendFileSync(ledgerPath, line);
    return true;
  } catch {
    return false;
  }
}

function runClassify(argv) {
  const a = parseClassifyArgs(argv);
  const result = classifyTrigger(a);

  const ledgerRec = {
    v: 1,
    ts: new Date().toISOString(),
    actor: 'unattended',
    type: 'unattended_decision',
    ref_id: result.ref_id,
    trigger: result.trigger,
    class: result.class,
    decision: result.decision,
    question: result.question,
    answer: result.answer,
    source: result.source,
  };

  // D3: append BEFORE printing any verdict; a failed append means NO verdict.
  if (!appendLedgerLine(a.ledger, ledgerRec)) {
    process.stderr.write(`unattended-gate: could not append to ledger ${a.ledger} — no verdict recorded\n`);
    process.exit(1);
  }

  if (a.json) {
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } else {
    process.stdout.write(
      `decision=${result.decision} class=${result.class} trigger=${result.trigger} answer=${result.answer}\n`,
    );
  }
  process.exit(result.decision === 'auto' ? 0 : 3);
}

// --- preflight -----------------------------------------------------------------

function runPreflight(argv) {
  const a = parsePreflightArgs(argv);
  const refusals = [];

  if (!(a.maxRunTokens > 0) && !(a.maxRunCostUsd > 0)) {
    refusals.push('no declared run budget: --max-run-tokens or --max-run-cost-usd must be > 0 (the default of unlimited is the guard that is not actually armed)');
  }
  if (a.maxTicks > 20) refusals.push(`max_ticks ${a.maxTicks} exceeds the ceiling of 20 (unattended may only LOWER this guard)`);
  if (a.stagnationLimit > 3) refusals.push(`stagnation_limit ${a.stagnationLimit} exceeds the ceiling of 3 (unattended may only LOWER this guard)`);
  if (a.maxPrs < 1 || a.maxPrs > 5) refusals.push(`max_prs ${a.maxPrs} is outside the allowed range 1 to 5`);
  if (!a.intake) {
    refusals.push('--intake is required: unattended never authors an intake document, it only consumes one already on disk');
  } else {
    let st = null;
    try { st = fs.statSync(a.intake); } catch { st = null; }
    if (!st) refusals.push(`--intake ${a.intake} does not exist on disk`);
    else if (!st.isFile()) refusals.push(`--intake ${a.intake} is not a regular file`);
  }

  if (refusals.length > 0) {
    for (const r of refusals) process.stderr.write(`unattended-gate: REFUSED — ${r}\n`);
    process.exit(3);
  }

  const bounds = {
    max_ticks: a.maxTicks,
    stagnation_limit: a.stagnationLimit,
    max_run_tokens: a.maxRunTokens,
    max_run_cost_usd: a.maxRunCostUsd,
    max_prs: a.maxPrs,
  };
  if (a.json) {
    process.stdout.write(`${JSON.stringify(bounds)}\n`);
  } else {
    process.stdout.write(
      `ADMIT — max_ticks=${bounds.max_ticks} stagnation_limit=${bounds.stagnation_limit} `
      + `max_run_tokens=${bounds.max_run_tokens} max_run_cost_usd=${bounds.max_run_cost_usd} max_prs=${bounds.max_prs}\n`,
    );
  }
  process.exit(0);
}

// --- summary -------------------------------------------------------------------

function runSummary(argv) {
  const a = parseSummaryArgs(argv);
  let text;
  try {
    text = fs.readFileSync(a.ledger, 'utf8');
  } catch {
    usage(`cannot read ledger ${a.ledger}`);
    return;
  }
  const sinceMs = Date.parse(a.since);
  if (Number.isNaN(sinceMs)) usage(`--since "${a.since}" is not a parseable ISO-8601 timestamp`);

  const autoRows = [];
  const parkRows = [];
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let rec;
    try { rec = JSON.parse(line); } catch { continue; }
    if (rec.type !== 'unattended_decision') continue;
    const ts = Date.parse(rec.ts);
    if (Number.isNaN(ts) || ts < sinceMs) continue;
    const row = {
      ref_id: rec.ref_id, trigger: rec.trigger, class: rec.class,
      question: rec.question, answer: rec.answer, source: rec.source,
    };
    if (rec.decision === 'auto') autoRows.push(row);
    else parkRows.push(row);
  }

  const fmt = (rows) => rows.map((r) => `  ${r.ref_id} [${r.trigger}/${r.class}] Q: ${r.question} A: ${r.answer} (${r.source})`).join('\n');
  process.stdout.write(`UNATTENDED SUMMARY since ${a.since}\n`);
  process.stdout.write(`auto-resolved (${autoRows.length}):\n${fmt(autoRows)}\n`);
  process.stdout.write(`parked (${parkRows.length}):\n${fmt(parkRows)}\n`);
  process.stdout.write('Pull requests: run `gh pr list` to see what opened this run.\n');
  process.exit(0);
}

function main() {
  const argv = process.argv.slice(2);
  const cmd = argv[0];
  const rest = argv.slice(1);
  if (cmd === 'classify') return runClassify(rest);
  if (cmd === 'preflight') return runPreflight(rest);
  if (cmd === 'summary') return runSummary(rest);
  usage('usage: unattended-gate.mjs <classify|preflight|summary> [flags]');
  return undefined;
}

main();
