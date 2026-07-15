#!/usr/bin/env node
// orchestration-dispatch.mjs — the deterministic single-agent orchestration
// tick (CHANGE-0009 / spec-mechanize-deterministic-ticks D1-D3).
//
// Same architecture as orchestration-mode.mjs (RFC-0005 / SPEC-0005): a PURE,
// exported decide(snapshot) implements the ORCHESTRATION 14-rule first-match
// decision table (including the SPEC-0012 G3 post-remediation reset routing
// and the rule-14 metrics-flush arm) — no clock, no filesystem, no writes.
// A CLI layer builds the snapshot by READING (never writing) the repo:
// STATE.yaml via the shared line engine (lib/state-engine.mjs) plus mechanical
// probes (TECHNOLOGY.md / WORKFLOW.md presence, focus spec file + SPEC-FROZEN
// marker + frontmatter status, METRICS.jsonl ref presence, LOCKS.md presence).
//
// The script NEVER mutates STATE. Auto-init/auto-repair stays with the LLM
// wrapper (.aai/ORCHESTRATION.prompt.md via check-state.mjs --repair); those
// states are flagged as needs_llm edges with named, machine-greppable reasons.
//
// Mechanical proxies vs judgment residues (D2): anything not mechanically
// decidable is FLAGGED, never guessed —
//   - validation_staleness_unknown: last_validation.status is `pass` but its
//     ref_id does not name the focus ref (a leaked/stale pass must not drive
//     rules 13/14 mechanically);
//   - review_staleness_unknown: both verdicts pass/waived but the LAST
//     agent_run for the focus ref is an implementer role (Implementation /
//     TDD Implementation / Remediation) — code changed after the verdicts;
//   - possible_missing_remediation_reset (SPEC-0012 G3 forensic): a `fail`
//     verdict while the LAST agent_run is already a Remediation — the
//     post-remediation reset-block is what is missing.
//
// Output (D3): stdout carries EXACTLY ONE JSON object; `--human` adds the
// DISPATCH FORMAT text block on stderr (stdout stays parseable either way);
// `--rules` prints the rule table derived from the SAME rule objects.
//
// Exit codes (closed contract):
//   0 — dispatch emitted (verdict `dispatch`)
//   3 — no action required (verdict `no_action`: paused, human gate, flushed)
//   4 — LLM must take over (verdict `needs_llm`): missing/invalid/unrepaired
//       STATE or a flagged judgment edge; the JSON still prints with reasons
//   2 — usage error (unknown flag, missing flag value)
//   1 — internal error (unexpected exception; nothing was written)

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { splitLines, duplicateKeys, inlineChildConflicts } from './lib/state-core.mjs';
import { findBlock, readScalar, indentOf, unquoteScalar, agentRunsFor, lastImplementerModel } from './lib/state-engine.mjs';

// --- closed sets (mirror state.mjs / check-state semantics) --------------------

const PROJECT_STATUSES = ['active', 'paused'];
const VALIDATION_STATUSES = ['pass', 'fail', 'not_run'];
const REVIEW_STATUSES = ['not_run', 'pass', 'fail', 'waived'];
const PHASES = ['planning', 'preparation', 'implementation', 'validation', 'code_review', 'remediation'];
const ITEM_STATUSES = ['planned', 'in_progress', 'blocked', 'done'];
const STRATEGIES = ['loop', 'tdd', 'hybrid', 'undecided'];
const RECOMMENDATIONS = ['not_needed', 'optional', 'recommended', 'required'];
const USER_DECISIONS = ['undecided', 'worktree', 'inline', 'waived'];
const BOOLS = ['true', 'false'];
const IMPLEMENTER_ROLES = ['Implementation', 'TDD Implementation', 'Remediation'];

// Tier suggestion mapping (ORCHESTRATION MODEL SELECTION, D3).
const TIERS = {
  'Planning': 'premium',
  'Code Review': 'premium',
  'Implementation': 'standard',
  'TDD Implementation': 'standard',
  'Remediation': 'standard',
  'Validation': 'standard',
  'Technology extraction': 'mechanical',
  'Bootstrap': 'mechanical',
  'Implementation Preparation / Worktree decision': 'mechanical',
  'Metrics Flush': 'mechanical',
};

// --- rule table (single source: decide() AND --rules print from these) ---------

const RULES = [
  { id: '1', when: 'project_status == paused', then: 'no action required (STOP)' },
  { id: '2', when: 'human_input.required == true', then: 'no action required (waiting for human decision)' },
  { id: '3', when: 'docs/TECHNOLOGY.md missing', then: 'dispatch Technology extraction (.aai/TECH_EXTRACT.prompt.md)' },
  { id: '4', when: '.aai/workflow/WORKFLOW.md missing', then: 'dispatch Bootstrap (.aai/BOOTSTRAP.prompt.md)' },
  { id: '5', when: 'focus spec_path null or spec file missing', then: 'dispatch Planning' },
  { id: '6', when: 'spec not frozen (no SPEC-FROZEN: true) or frontmatter status not draft/implementing', then: 'dispatch Planning' },
  { id: '7', when: 'implementation_strategy.selected missing or undecided', then: 'dispatch Planning' },
  { id: '8', when: 'worktree.recommendation in {recommended, required} AND user_decision == undecided', then: 'dispatch Implementation Preparation / Worktree decision (.aai/SKILL_WORKTREE.prompt.md)' },
  { id: '9a', when: 'phase in {planning done, preparation} AND strategy == tdd', then: 'dispatch TDD Implementation (.aai/SKILL_TDD.prompt.md)' },
  { id: '9b', when: 'phase in {planning done, preparation} AND strategy == hybrid', then: 'dispatch TDD Implementation (the role reads the spec TEST-xxx ordering)' },
  { id: '9c', when: 'phase in {planning done, preparation} AND strategy == loop', then: 'dispatch Implementation (.aai/IMPLEMENTATION.prompt.md)' },
  { id: '10', when: 'last_validation.status == fail', then: 'dispatch Remediation (.aai/REMEDIATION.prompt.md); fail + last run already Remediation -> needs_llm possible_missing_remediation_reset' },
  { id: '11', when: 'last_validation.status == not_run AND phase in {implementation, validation, remediation, code_review}', then: 'dispatch Validation (.aai/VALIDATION.prompt.md) with validator_independence' },
  { id: '12', when: 'code_review.status == fail', then: 'dispatch Remediation (.aai/REMEDIATION.prompt.md)' },
  { id: '13', when: 'validation pass AND code_review.required AND status not in {pass, waived}', then: 'dispatch Code Review (.aai/SKILL_CODE_REVIEW.prompt.md)' },
  { id: '14', when: 'validation pass AND focus ref absent from METRICS.jsonl', then: 'dispatch Metrics Flush (.aai/METRICS_FLUSH.prompt.md); ref present -> no action required' },
];

// SPEC-0012 G3 reset routing is EMERGENT from the proxies: a completed
// remediation already reset the failed block to not_run, so rule 10/12 no
// longer match and the state falls through to rule 11 (fresh, independent
// Validation) / rule 13 (fresh Code Review). A recorded `pass` with only
// code_review reset routes to rule 13 — rule 11 requires status not_run, so a
// pass can never re-fire it.

// --- pure decision core (D1) ----------------------------------------------------

function refMatches(vref, ref) {
  if (vref == null || ref == null) return false;
  return vref === ref || String(vref).split('/').includes(ref);
}

function dispatchFor(role, snapshot, rule, extra = {}) {
  const ref = snapshot.focus ? snapshot.focus.ref_id : null;
  const specPath = snapshot.spec && snapshot.spec.path ? snapshot.spec.path : null;
  const base = {
    'Technology extraction': {
      system_prompt: '.aai/TECH_EXTRACT.prompt.md',
      inputs: ['<repository sources>'],
      expected_outputs: ['docs/TECHNOLOGY.md'],
      stop_condition: 'docs/TECHNOLOGY.md written with the authoritative technology contract',
    },
    'Bootstrap': {
      system_prompt: '.aai/BOOTSTRAP.prompt.md',
      inputs: ['docs/TECHNOLOGY.md'],
      expected_outputs: ['.aai/workflow/WORKFLOW.md'],
      stop_condition: '.aai/workflow/WORKFLOW.md present with normalized roles',
    },
    'Planning': {
      system_prompt: '.aai/PLANNING.prompt.md',
      inputs: [snapshot.focus && snapshot.focus.primary_path, 'docs/TECHNOLOGY.md', specPath].filter(Boolean),
      expected_outputs: ['frozen spec (SPEC-FROZEN: true) with measurable AC + Test Plan + implementation strategy'],
      stop_condition: 'spec frozen with a Test Plan and implementation_strategy recorded in STATE',
    },
    'Implementation Preparation / Worktree decision': {
      system_prompt: '.aai/SKILL_WORKTREE.prompt.md',
      inputs: ['docs/ai/STATE.yaml', specPath].filter(Boolean),
      expected_outputs: ['worktree.user_decision recorded (worktree | inline | waived)'],
      stop_condition: 'the user answered the worktree recommendation gate',
    },
    'TDD Implementation': {
      system_prompt: '.aai/SKILL_TDD.prompt.md',
      inputs: [specPath, 'docs/TECHNOLOGY.md'].filter(Boolean),
      expected_outputs: ['RED-GREEN-REFACTOR evidence in docs/ai/tdd/', 'spec Test Plan statuses updated'],
      stop_condition: 'all selected TEST-xxx green with evidence recorded',
    },
    'Implementation': {
      system_prompt: '.aai/IMPLEMENTATION.prompt.md',
      inputs: [specPath, 'docs/TECHNOLOGY.md'].filter(Boolean),
      expected_outputs: ['implementation covering the spec Test Plan'],
      stop_condition: 'all spec TEST-xxx entries covered and passing',
    },
    'Remediation': {
      system_prompt: '.aai/REMEDIATION.prompt.md',
      inputs: [specPath, 'docs/ai/STATE.yaml'].filter(Boolean),
      expected_outputs: ['defects fixed', 'failed block reset via state.mjs reset-block'],
      stop_condition: 'failures remediated and the failed verdict block reset to not_run',
    },
    'Validation': {
      system_prompt: '.aai/VALIDATION.prompt.md',
      inputs: [specPath, 'docs/ai/STATE.yaml'].filter(Boolean),
      expected_outputs: ['independent verdict via state.mjs set-validation with evidence paths'],
      stop_condition: 'validation verdict recorded with executable evidence',
    },
    'Code Review': {
      system_prompt: '.aai/SKILL_CODE_REVIEW.prompt.md',
      inputs: [specPath, 'docs/ai/STATE.yaml'].filter(Boolean),
      expected_outputs: ['review report under docs/ai/reviews/', 'verdict via state.mjs set-code-review'],
      stop_condition: 'review verdict recorded (ERROR findings block readiness)',
    },
    'Metrics Flush': {
      system_prompt: '.aai/METRICS_FLUSH.prompt.md',
      inputs: ['docs/ai/STATE.yaml', 'docs/ai/METRICS.jsonl', '.aai/system/PRICING.yaml'],
      expected_outputs: ['ledger entry appended', 'STATE cleaned via line-surgical flush'],
      stop_condition: 'focus ref present in METRICS.jsonl and STATE cleanup committed',
    },
  }[role];
  const inputs = [...base.inputs];
  if (snapshot.locks_present) inputs.push('.aai/system/LOCKS.md');
  return {
    verdict: 'dispatch',
    rule,
    role,
    ref_id: ref,
    system_prompt: base.system_prompt,
    inputs,
    expected_outputs: base.expected_outputs,
    stop_condition: base.stop_condition,
    suggested_tier: TIERS[role],
    validator_independence: role === 'Validation'
      ? { implementer_model: snapshot.implementer_model ?? null, must_differ: true }
      : null,
    reasons: extra.reasons ?? [],
  };
}

function noAction(rule, snapshot, reasons) {
  return {
    verdict: 'no_action',
    rule,
    role: null,
    ref_id: snapshot.focus ? snapshot.focus.ref_id : null,
    system_prompt: null,
    inputs: [],
    expected_outputs: [],
    stop_condition: 'no action required',
    suggested_tier: null,
    validator_independence: null,
    reasons,
  };
}

function needsLlm(snapshot, reasons, rule = null) {
  return {
    verdict: 'needs_llm',
    rule,
    role: null,
    ref_id: snapshot && snapshot.focus ? snapshot.focus.ref_id : null,
    system_prompt: null,
    inputs: [],
    expected_outputs: [],
    stop_condition: 'LLM wrapper must take over the flagged edge (fail-closed)',
    suggested_tier: null,
    validator_independence: null,
    reasons,
  };
}

// decide(snapshot) — PURE first-match evaluation of the rule table. The
// snapshot shape is documented by buildSnapshot() below; decide never touches
// a clock, the filesystem, or its input.
export function decide(snapshot) {
  const s = snapshot;
  // Rule 1 — paused.
  if (s.project_status === 'paused') return noAction('1', s, ['project_status_paused']);
  // Rule 2 — human gate.
  if (s.human_input_required === true) return noAction('2', s, ['human_input_required']);
  // Rule 3 — technology contract missing ("outdated" stays a role judgment).
  if (!s.technology_present) return dispatchFor('Technology extraction', s, '3');
  // Rule 4 — workflow missing (deeper "roles not normalized" is not mechanical).
  if (!s.workflow_present) return dispatchFor('Bootstrap', s, '4');
  // Ref-consuming rules need a focus ref; inferring one is LLM work (auto-init).
  if (!s.focus || s.focus.ref_id == null) return needsLlm(s, ['no_focus_ref']);
  // Rules 5+6 — spec mapping / freeze proxies.
  if (!s.spec || s.spec.path == null || !s.spec.present) return dispatchFor('Planning', s, '5');
  if (!s.spec.frozen || !['draft', 'implementing'].includes(s.spec.frontmatter_status)) {
    return dispatchFor('Planning', s, '6');
  }
  // Rule 7 — strategy undecided.
  if (s.strategy_selected == null || s.strategy_selected === 'undecided') {
    return dispatchFor('Planning', s, '7');
  }
  // Rule 8 — worktree recommendation gate.
  if (s.worktree && ['recommended', 'required'].includes(s.worktree.recommendation)
    && s.worktree.user_decision === 'undecided') {
    return dispatchFor('Implementation Preparation / Worktree decision', s, '8');
  }
  // The remaining rules read the focus work item.
  if (!s.work_item) return needsLlm(s, ['focus_ref_not_in_active_work_items']);
  const phase = s.work_item.phase;
  // Rule 9 — implementation/tests missing: planning done or preparation phase.
  if ((phase === 'planning' && s.work_item.status === 'done') || phase === 'preparation') {
    if (s.strategy_selected === 'tdd') return dispatchFor('TDD Implementation', s, '9a');
    if (s.strategy_selected === 'hybrid') return dispatchFor('TDD Implementation', s, '9b');
    return dispatchFor('Implementation', s, '9c');
  }
  const vstatus = s.validation ? s.validation.status : null;
  const vmatch = refMatches(s.validation ? s.validation.ref_id : null, s.focus.ref_id);
  // Rule 10 — validation FAIL -> Remediation; the G3 "missing reset" forensic
  // case (fail + a Remediation already ran last) is not mechanically provable.
  if (vstatus === 'fail') {
    if (s.last_run_role === 'Remediation') return needsLlm(s, ['possible_missing_remediation_reset'], '10');
    return dispatchFor('Remediation', s, '10');
  }
  // Rule 11 — implementation exists but validation not run. A recorded `pass`
  // counts as run (G3: never re-fire 11 on a pass + review-only reset).
  if (vstatus === 'not_run'
    && ['implementation', 'validation', 'remediation', 'code_review'].includes(phase)) {
    return dispatchFor('Validation', s, '11');
  }
  // Rule 12 — review FAIL -> Remediation (same forensic residue as rule 10).
  if (s.review && s.review.status === 'fail') {
    if (s.last_run_role === 'Remediation') return needsLlm(s, ['possible_missing_remediation_reset'], '12');
    return dispatchFor('Remediation', s, '12');
  }
  // Judgment residue — a `pass` that does not name the focus ref may be a
  // stale/leaked verdict; "not run recently" is not mechanically decidable.
  if (vstatus === 'pass' && !vmatch) return needsLlm(s, ['validation_staleness_unknown']);
  // Rule 13 — validation pass, review required and missing.
  if (vstatus === 'pass' && s.review && s.review.required === true
    && !['pass', 'waived'].includes(s.review.status)) {
    return dispatchFor('Code Review', s, '13');
  }
  // Judgment residue — verdicts satisfied but code changed after them
  // ("review outdated relative to diff" is not mechanically provable).
  if (vstatus === 'pass' && IMPLEMENTER_ROLES.includes(s.last_run_role)) {
    return needsLlm(s, ['review_staleness_unknown']);
  }
  // Rule 14 — metrics-flush arm.
  if (vstatus === 'pass') {
    if (s.flushed) return noAction('14', s, ['already_flushed']);
    return dispatchFor('Metrics Flush', s, '14');
  }
  // Exhausted table: fail closed to the LLM, never guess.
  return needsLlm(s, ['no_rule_matched']);
}

// --- snapshot builder (CLI layer; READ-ONLY) --------------------------------------

function topScalar(lines, key) {
  const re = new RegExp(`^${key}:(.*)$`);
  for (const l of lines) {
    const m = l.match(re);
    if (m) {
      const v = m[1].trim();
      return v === '' || v === 'null' ? null : unquoteScalar(v);
    }
  }
  return null;
}

// Parse active_work_items into [{ ref_id, status, phase, spec_path, primary_path }].
function parseWorkItems(lines) {
  const b = findBlock(lines, 'active_work_items');
  if (!b) return null;
  const items = [];
  let cur = null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (l.trim() === '' || l.trim().startsWith('#')) continue;
    if (/^ {2}- /.test(l)) { cur = {}; items.push(cur); }
    if (!cur) continue;
    const m = l.match(/^(?: {2}- | {4})([\w-]+):\s*(.*)$/);
    if (m && indentOf(l) <= 4) {
      const v = m[2].trim();
      cur[m[1]] = v === '' || v === 'null' ? null : unquoteScalar(v);
    }
  }
  return items;
}

function parseBool(v) {
  return v === 'true' ? true : v === 'false' ? false : v;
}

// buildSnapshot(statePath, root) -> { snapshot, problems[] }
// problems non-empty => the CLI degrades fail-closed (exit 4, needs_llm).
export function buildSnapshot(statePath, root) {
  const problems = [];
  if (!fs.existsSync(statePath)) {
    return { snapshot: null, problems: [`state_file_missing:${statePath}`] };
  }
  const raw = fs.readFileSync(statePath, 'utf8');
  const { lines } = splitLines(raw);
  for (const d of duplicateKeys(lines)) problems.push(`duplicate_top_level_key:${d.key}`);
  for (const c of inlineChildConflicts(lines)) problems.push(`inline_child_conflict:${c.key}`);
  if (problems.length > 0) return { snapshot: null, problems };

  const checkEnum = (value, allowed, field, { required = false } = {}) => {
    if (value == null) {
      if (required) problems.push(`missing_required_field:${field}`);
      return value;
    }
    if (!allowed.includes(value)) problems.push(`unknown_enum_value:${field}=${value}`);
    return value;
  };
  for (const block of ['current_focus', 'last_validation', 'code_review']) {
    if (!findBlock(lines, block)) problems.push(`missing_required_block:${block}`);
  }
  if (problems.length > 0) return { snapshot: null, problems };

  const projectStatus = checkEnum(topScalar(lines, 'project_status'), PROJECT_STATUSES, 'project_status', { required: true });
  const humanRequired = checkEnum(readScalar(lines, 'human_input', 'required'), BOOLS, 'human_input.required');
  const focusRef = readScalar(lines, 'current_focus', 'ref_id');
  const focus = {
    type: readScalar(lines, 'current_focus', 'type'),
    ref_id: focusRef,
    primary_path: readScalar(lines, 'current_focus', 'primary_path'),
  };
  const items = parseWorkItems(lines) ?? [];
  const item = items.find(it => it.ref_id === focusRef) ?? null;
  if (item) {
    checkEnum(item.phase, PHASES, 'active_work_items[].phase');
    checkEnum(item.status, ITEM_STATUSES, 'active_work_items[].status');
  }
  const specPath = (item && item.spec_path) || readScalar(lines, 'current_focus', 'spec_path');
  const spec = { path: specPath ?? null, present: false, frozen: false, frontmatter_status: null };
  if (specPath) {
    const abs = path.resolve(root, specPath);
    if (fs.existsSync(abs)) {
      spec.present = true;
      const body = fs.readFileSync(abs, 'utf8').replace(/\r\n?/g, '\n');
      spec.frozen = /^SPEC-FROZEN: true$/m.test(body);
      const fm = body.match(/^---\n([\s\S]*?)\n---/);
      if (fm) {
        const st = fm[1].match(/^status:\s*(\S+)/m);
        if (st) spec.frontmatter_status = st[1];
      }
    }
  }
  const strategy = checkEnum(readScalar(lines, 'implementation_strategy', 'selected'), STRATEGIES, 'implementation_strategy.selected');
  const worktree = {
    recommendation: checkEnum(readScalar(lines, 'worktree', 'recommendation'), RECOMMENDATIONS, 'worktree.recommendation'),
    user_decision: checkEnum(readScalar(lines, 'worktree', 'user_decision'), USER_DECISIONS, 'worktree.user_decision'),
  };
  const validation = {
    status: checkEnum(readScalar(lines, 'last_validation', 'status'), VALIDATION_STATUSES, 'last_validation.status', { required: true }),
    ref_id: readScalar(lines, 'last_validation', 'ref_id'),
  };
  const review = {
    required: parseBool(checkEnum(readScalar(lines, 'code_review', 'required'), BOOLS, 'code_review.required')),
    status: checkEnum(readScalar(lines, 'code_review', 'status'), REVIEW_STATUSES, 'code_review.status'),
  };
  if (problems.length > 0) return { snapshot: null, problems };

  // Rule-14 "already flushed" probe: focus ref present in the ledger.
  let flushed = false;
  const metricsPath = path.resolve(root, 'docs/ai/METRICS.jsonl');
  if (focusRef && fs.existsSync(metricsPath)) {
    for (const line of fs.readFileSync(metricsPath, 'utf8').split(/\r?\n/)) {
      const t = line.trim();
      if (t === '' || t.startsWith('#')) continue;
      try {
        if (JSON.parse(t).ref_id === focusRef) { flushed = true; break; }
      } catch { /* unparseable ledger line: best-effort probe, skip */ }
    }
  }
  const runs = focusRef ? agentRunsFor(lines, focusRef) : [];
  const snapshot = {
    project_status: projectStatus,
    human_input_required: parseBool(humanRequired) === true,
    technology_present: fs.existsSync(path.resolve(root, 'docs/TECHNOLOGY.md')),
    workflow_present: fs.existsSync(path.resolve(root, '.aai/workflow/WORKFLOW.md')),
    locks_present: fs.existsSync(path.resolve(root, '.aai/system/LOCKS.md')),
    focus,
    work_item: item ? { phase: item.phase, status: item.status } : null,
    spec,
    strategy_selected: strategy,
    worktree,
    validation,
    review,
    flushed,
    implementer_model: focusRef ? lastImplementerModel(lines, focusRef) : null,
    last_run_role: runs.length ? runs[runs.length - 1].role : null,
  };
  return { snapshot, problems: [] };
}

// --- CLI ---------------------------------------------------------------------------

function usage() {
  console.error(
    'Usage: orchestration-dispatch [--state <path>] [--root <dir>] [--human] [--rules]\n'
    + '  Deterministic orchestration tick: reads STATE + repo probes, prints ONE\n'
    + '  dispatch JSON on stdout. Exit: 0 dispatch, 3 no action, 4 LLM must take\n'
    + '  over (named reasons in JSON), 2 usage, 1 internal error. Never writes.',
  );
}

function parseArgs(argv) {
  const opts = { state: 'docs/ai/STATE.yaml', root: process.cwd(), human: false, rules: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--state' || tok === '--root') {
      const v = argv[i + 1];
      if (!v || v.startsWith('--')) { usage(); console.error(`orchestration-dispatch: ${tok} requires a value`); process.exit(2); }
      opts[tok.slice(2)] = v;
      i += 1;
    } else if (tok === '--human') {
      opts.human = true;
    } else if (tok === '--rules') {
      opts.rules = true;
    } else if (tok === '-h' || tok === '--help') {
      usage();
      process.exit(2);
    } else {
      usage();
      console.error(`orchestration-dispatch: unknown flag "${tok}"`);
      process.exit(2);
    }
  }
  return opts;
}

function printRules() {
  console.log('ORCHESTRATION decision table (first match wins) — single source: this script');
  for (const r of RULES) {
    console.log(`${r.id}) IF ${r.when} -> ${r.then}`);
  }
  console.log('Post-remediation reset routing (SPEC-0012 G3) is emergent: reset-to-not_run');
  console.log('blocks make rules 10/12 not match and fall through to 11/13; a recorded pass');
  console.log('with only code_review reset routes to 13 and never re-fires 11.');
}

function humanBlock(out) {
  const lines = [
    '=== ORCHESTRATION DISPATCH (deterministic tick) ===',
    `Current state summary: ${JSON.stringify(out.state_summary)}`,
    `Decision rationale: rule ${out.rule ?? '-'} (${out.verdict})${out.reasons.length ? ` — reasons: ${out.reasons.join(', ')}` : ''}`,
    `Role: ${out.role ?? '(none)'}`,
    `Scope: ${out.ref_id ?? '(none)'}`,
    `Inputs: ${out.inputs.join(', ') || '(none)'}`,
    `Expected outputs: ${out.expected_outputs.join(', ') || '(none)'}`,
    `Stop condition: ${out.stop_condition}`,
    `Suggested model tier: ${out.suggested_tier ?? '(n/a)'}`,
  ];
  if (out.validator_independence) {
    lines.push(`Validator independence: implementer_model=${out.validator_independence.implementer_model ?? 'null'} (validator model must differ)`);
  }
  console.error(lines.join('\n'));
}

function main() {
  const opts = parseArgs(process.argv);
  if (opts.rules) {
    printRules();
    process.exit(0);
  }
  const statePath = path.resolve(process.cwd(), opts.state);
  const root = path.resolve(process.cwd(), opts.root);
  let out;
  try {
    const { snapshot, problems } = buildSnapshot(statePath, root);
    if (problems.length > 0) {
      out = needsLlm(snapshot, problems);
      out.state_summary = snapshot ?? {};
    } else {
      out = decide(snapshot);
      out.state_summary = snapshot;
    }
  } catch (err) {
    console.error(`orchestration-dispatch: internal error: ${err && err.stack ? err.stack : err}`);
    process.exit(1);
  }
  console.log(JSON.stringify(out));
  if (opts.human) humanBlock(out);
  process.exit(out.verdict === 'dispatch' ? 0 : out.verdict === 'no_action' ? 3 : 4);
}

// Run as CLI only when invoked directly; importable for unit tests.
const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) main();

export { RULES };
