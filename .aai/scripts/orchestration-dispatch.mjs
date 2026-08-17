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
// ONE opt-in write exists (CHANGE-0120 confirm-by-script, rule 9x): with
// --confirm, a tick that proves the frozen spec's AC/test contract is green
// and UNCHANGED since the last recorded confirmation appends a phase_confirmed
// line to docs/ai/EVENTS.jsonl instead of dispatching an implementer agent.
// That line is also the comparison snapshot the NEXT tick reads back — which
// is why the storage is the append-only committed ledger and not a new STATE
// field (STATE is gitignored runtime state, and state.mjs is a protected L3
// surface this arm deliberately does not touch). Without --confirm the arm
// still fires but writes nothing. Any delta, a non-green AC table, or no proof
// of prior green falls through to the normal 9a/9b/9c dispatch: fail-closed to
// dispatching, always.
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
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { specContentHash, acTableGreen } from './lib/docs-model.mjs';
import { splitLines, duplicateKeys, inlineChildConflicts } from './lib/state-core.mjs';
import { findBlock, readScalar, indentOf, unquoteScalar, agentRunsFor, lastImplementerModel } from './lib/state-engine.mjs';
import { computeEffectivePromptHash, componentHashes, shortHash } from './lib/prompt-hash.mjs';

// --- closed sets (mirror state.mjs / check-state semantics) --------------------

const PROJECT_STATUSES = ['active', 'paused'];
const VALIDATION_STATUSES = ['pass', 'fail', 'not_run'];
const REVIEW_STATUSES = ['not_run', 'pass', 'fail', 'waived'];
const PHASES = ['planning', 'preparation', 'implementation', 'validation', 'code_review', 'remediation'];
const ITEM_STATUSES = ['planned', 'in_progress', 'blocked', 'done'];
// implementation-mode-choice: `direct` and `untested` are cheap non-TDD lanes.
// They are NOT undecided (so rule 7 never re-plans them) and NOT tdd/hybrid (so
// rule 9c dispatches the regular Implementation agent, which honors the lane).
const STRATEGIES = ['loop', 'tdd', 'hybrid', 'direct', 'untested', 'undecided'];
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
  { id: '4a', when: 'focus work item done/absent AND focus ref flushed to METRICS.jsonl (spec-dispatch-new-intake-after-completed-scope D1) AND no recorded fail verdict (validation.status !== fail AND review.status !== fail; CHANGE-0036 fail-verdict precedence guard — abstains so decide() falls through to rule 10/12 Remediation instead of burying the failure); exactly one open mappable docs/issues intake (draft/implementing, no done work item) -> retarget; zero -> no_action scope_complete_no_open_intake; 2+/unmappable/scan-failure -> needs_llm named reasons', then: 'dispatch Planning retarget (.aai/PLANNING.prompt.md) to the open intake, or no_action/needs_llm per candidate count' },
  { id: '4b', when: 'focus work item done/absent AND focus ref NOT flushed to METRICS.jsonl AND a committed work_item_closed event for the focus ref exists in docs/ai/EVENTS.jsonl (close ceremony ran — possibly in another session/clone whose local STATE verdicts never traveled) AND no recorded fail verdict AND no unsatisfied required review; closes the close->flush->retarget autonomy gap: without this arm a closed-but-unflushed focus falls to rule 5 and re-offers Planning for a finished scope', then: 'dispatch Metrics Flush (.aai/METRICS_FLUSH.prompt.md); after the flush lands, rule 4a retargets or reports scope_complete_no_open_intake' },
  { id: '5', when: 'focus spec_path null or spec file missing', then: 'dispatch Planning' },
  { id: '6', when: 'spec not frozen (no SPEC-FROZEN: true) or frontmatter status not draft/implementing; ceremony L0 (RFC-0009) prunes the status arm (tech-note doc), never the marker arm', then: 'dispatch Planning' },
  { id: '7', when: 'implementation_strategy.selected missing or undecided', then: 'dispatch Planning' },
  { id: '8', when: 'worktree.recommendation in {recommended, required} AND user_decision == undecided; ceremony L3 (RFC-0009): undecided gates for ANY recommendation (worktree mandatory)', then: 'dispatch Implementation Preparation / Worktree decision (.aai/SKILL_WORKTREE.prompt.md)' },
  { id: '9x', when: 'phase in {planning done, preparation} AND the frozen spec\'s AC table is fully green AND its AC/test content hash matches the last recorded phase_confirmed event for the ref (or, with no prior confirmation, an implementer agent_run for the ref exists); CHANGE-0120 confirm-by-script', then: 'no action required (phase confirmed by script — NO agent dispatched); with --confirm the tick records a phase_confirmed EVENTS line carrying the hash the next tick compares against. ANY delta, a non-green AC table, or missing prior green falls through to 9a/9b/9c' },
  { id: '9a', when: 'phase in {planning done, preparation} AND strategy == tdd', then: 'dispatch TDD Implementation (.aai/SKILL_TDD.prompt.md)' },
  { id: '9b', when: 'phase in {planning done, preparation} AND strategy == hybrid', then: 'dispatch TDD Implementation (the role reads the spec TEST-xxx ordering)' },
  { id: '9c', when: 'phase in {planning done, preparation} AND strategy in {loop, direct, untested} (direct/untested: spec-implementation-mode-choice non-TDD lanes)', then: 'dispatch Implementation (.aai/IMPLEMENTATION.prompt.md)' },
  { id: '10', when: 'last_validation.status == fail', then: 'dispatch Remediation (.aai/REMEDIATION.prompt.md); fail + last run already Remediation -> needs_llm possible_missing_remediation_reset' },
  { id: '11', when: 'last_validation.status == not_run AND phase in {implementation, validation, remediation, code_review}; ceremony L0/L1 (spec-loop-ceremony-aware-dispatch): lightweight lane adds reason lightweight_lane_declared_scope (lane.validation_depth == declared_scope)', then: 'dispatch Validation (.aai/VALIDATION.prompt.md) with validator_independence' },
  { id: '12', when: 'code_review.status == fail', then: 'dispatch Remediation (.aai/REMEDIATION.prompt.md)' },
  { id: '13', when: 'validation pass AND code_review.required AND status not in {pass, waived}; ceremony L3 (RFC-0009): required coerced true, waived -> needs_llm l3_review_waived_requires_operator_checkpoint', then: 'dispatch Code Review (.aai/SKILL_CODE_REVIEW.prompt.md)' },
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

// D1 (spec-loop-ceremony-aware-dispatch) — derived ceremony-aware dispatch
// lane. FAIL-CLOSED identically to the effective-level guard in decide():
// absent, garbage, out-of-range, or null resolves to level 2 (full). A pure
// function of the snapshot's spec object, so every dispatchFor() call
// (including the pre-spec rules 3/4/5, where no ceremony_level is knowable
// yet) carries a consistent lane without threading an extra parameter
// through every call site. Never a new rule: rule predicates/order/verdicts
// are untouched by this pair of helpers.
function deriveLevel(spec) {
  const raw = spec && spec.ceremony_level;
  return [0, 1, 2, 3].includes(raw) ? raw : 2;
}
function deriveLane(spec) {
  const lvl = deriveLevel(spec);
  return {
    selected: lvl <= 1 ? 'lightweight' : 'full',
    ceremony_level: lvl,
    validation_depth: lvl <= 1 ? 'declared_scope' : 'full',
  };
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
      stop_condition: 'review verdict recorded (BLOCKING findings block readiness)',
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
    lane: deriveLane(snapshot.spec),
    reasons: extra.reasons ?? [],
    retarget: null,
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
    lane: null,
    reasons,
    retarget: null,
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
    lane: null,
    reasons,
    retarget: null,
  };
}

// Doc-type -> current_focus.type enum mapping (spec-dispatch-new-intake-after-
// completed-scope D2): only the three docs/issues intake classes are mappable;
// techdebt/rfc/prd/release have no matching enum member (or their own
// pipeline) and stay unmappable (fail-closed, never guessed).
const OPEN_INTAKE_DOC_TYPES = { change: 'intake_change', issue: 'intake_issue', hotfix: 'intake_hotfix' };

// Rule 4a dispatch constructor (D3/D4) — separate from dispatchFor() because
// its ref_id/inputs/lane target the NEW open intake, not the (closed) snapshot
// focus: inputs carry the candidate's own primary_path (never the closed
// scope's spec path) and lane is deriveLane(null) (full/2/full) since the new
// scope has no spec yet — composing cleanly instead of leaking the old
// scope's ceremony onto the new one.
function dispatchRetarget(candidate, snapshot, fromRef) {
  const inputs = [candidate.primary_path, 'docs/TECHNOLOGY.md'];
  if (snapshot.locks_present) inputs.push('.aai/system/LOCKS.md');
  return {
    verdict: 'dispatch',
    rule: '4a',
    role: 'Planning',
    ref_id: candidate.ref_id,
    system_prompt: '.aai/PLANNING.prompt.md',
    inputs,
    expected_outputs: ['frozen spec (SPEC-FROZEN: true) with measurable AC + Test Plan + implementation strategy'],
    stop_condition: 'spec frozen with a Test Plan and implementation_strategy recorded in STATE',
    suggested_tier: TIERS.Planning,
    validator_independence: null,
    lane: deriveLane(null),
    reasons: ['focus_completed_retarget_to_open_intake'],
    retarget: {
      from_ref: fromRef,
      to_ref: candidate.ref_id,
      to_type: OPEN_INTAKE_DOC_TYPES[candidate.doc_type],
      to_primary_path: candidate.primary_path,
    },
  };
}

// decide(snapshot, opts) — PURE first-match evaluation of the rule table. The
// snapshot shape is documented by buildSnapshot() below; decide never touches
// a clock, the filesystem, or its input.
// `opts.skipConfirm` disables the rule-9x confirm arm so the caller can ask
// "what would this tick do if confirming were not an option?" — used ONLY by
// the --confirm fail-closed fallback, when the confirmation could not be
// recorded and therefore does not exist as far as the next tick is concerned.
//
// role-verification-guards G2 (D2) — decide() is a thin wrapper: the rule
// table itself lives in decideRuleTable() below, UNCHANGED; this function
// only adds the pure, additive staleness comparison on the way out, so every
// existing return point keeps its exact verdict/rule/role/reasons/exit-code
// behavior and only gains an `advisories` key in the one case that trips it.
export function decide(snapshot, opts = {}) {
  return withStaleAdvisory(decideRuleTable(snapshot, opts), snapshot);
}

// withStaleAdvisory(out, snapshot) — pure comparison of the two G2 snapshot
// fields (tree_hash, last_validation_verdict), computed once in
// buildSnapshot() and never recomputed here. Sets an ADDITIVE `advisories`
// key ONLY when: a validation_verdict event exists for the focus ref, its
// recorded status is still 'pass', STATE's OWN `validation.status` is ALSO
// still 'pass' for the same ref (corrected at remediation, N-4,
// validation-20260816T203700Z — see below), and its hash differs from the
// current tree_hash — with BOTH hashes non-null. A snapshot missing either
// new field (undefined — every pre-existing snapshot fixture) or carrying a
// null hash on either side yields the input unchanged: decide()'s own return
// value is byte-identical in that case. The CLI's stdout is NOT byte-identical
// to the pre-G2 tree even then — buildSnapshot unconditionally adds
// `tree_hash` and `last_validation_verdict` to `state_summary` regardless of
// staleness — it is additive-only modulo those two named keys (Spec-AC-05;
// test_042's `cmp` against the pinned pre-change blob, corrected at
// validation-20260816T131500Z B3/N2b — this comment previously repeated the
// retracted byte-identity claim and a `test_033` citation the spec removed
// as a non-sequitur; test_033 pins `prompt_hash`/`inherits` stability across
// two ticks, a different, narrower thing).
//
// N-4 fix: the STALE-EVENT status check alone is not enough. The event
// payload's `status` is a snapshot of what `last_validation.status` WAS at
// stamp time — it never changes after the fact. If STATE's own
// `last_validation.status` later moves off 'pass' (a genuine new fail/not_run
// verdict, or an operator's `reset-block`), the OLD stamped event still says
// `status: "pass"` forever, and without this corroborating check a live tick
// would keep asserting "the recorded pass verdict's tree hash no longer
// matches" about a pass verdict STATE no longer holds — a true statement
// about the stale EVENT, but a false one about STATE, which is what the
// advisory text actually claims. Requiring `snapshot.validation.status ===
// 'pass'` too means the advisory only fires while STATE and the last stamp
// AGREE that a pass verdict is standing.
function withStaleAdvisory(out, snapshot) {
  const s = snapshot;
  const verdict = s && s.last_validation_verdict;
  const treeHash = s ? s.tree_hash : undefined;
  const currentlyPass = !!(s && s.validation && s.validation.status === 'pass');
  if (verdict && verdict.status === 'pass' && currentlyPass
    && verdict.hash != null && treeHash != null
    && verdict.hash !== treeHash) {
    return { ...out, advisories: ['validation_verdict_stale'] };
  }
  return out;
}

function decideRuleTable(snapshot, opts = {}) {
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
  // Rule 4a (spec-dispatch-new-intake-after-completed-scope D1) — retarget off
  // a terminally complete focus, evaluated before any spec/strategy/worktree
  // rule can re-offer the CLOSED scope. Fires only when the focus work item is
  // terminal (status done, or absent because flush already removed it) AND
  // the focus ref is flushed to METRICS.jsonl (the rule-14 probe, reused as
  // the terminal marker) — a done-but-not-yet-flushed item still walks the
  // normal close pipeline (rules 13/14) untouched; requiring `flushed` keeps
  // that pipeline from being hijacked.
  // A recorded FAIL verdict (validation OR code review) on the completed focus
  // is NOT retargetable: 4a must abstain so decide() falls through to rules
  // 10/12 (Remediation) — a buried failure is worse than a delayed retarget
  // (CHANGE-0036 / reconciles SPEC-0042 D5 for the done+flushed corner).
  const focusHasFailVerdict = (s.validation && s.validation.status === 'fail')
    || (s.review && s.review.status === 'fail');
  if ((s.work_item == null || s.work_item.status === 'done')
      && !focusHasFailVerdict) {
    if (s.flushed === true) {
      const fromRef = s.focus.ref_id;
      const candidates = s.open_intakes;
      // Probe failure: fail-closed, never guess.
      if (candidates === null) return needsLlm(s, ['open_intake_scan_failed'], '4a');
      if (candidates.length === 0) return noAction('4a', s, ['scope_complete_no_open_intake']);
      if (candidates.length >= 2) {
        const names = candidates.map(c => c.ref_id ?? c.primary_path);
        return needsLlm(s, [`multiple_open_intakes:${names.join(',')}`], '4a');
      }
      const only = candidates[0];
      if (only.unmappable) return needsLlm(s, [`open_intake_unmappable:${only.primary_path}`], '4a');
      return dispatchRetarget(only, s, fromRef);
    }
    // Rule 4b — closed but not yet flushed. A committed work_item_closed
    // event in docs/ai/EVENTS.jsonl proves the close ceremony ran even when
    // this session's LOCAL STATE carries no pass verdict (fresh clone, new
    // session after a merged PR): without this arm the state falls through
    // to rule 5 and re-offers Planning for a finished scope. Guards: a fail
    // verdict already abstained above; a required-but-unsatisfied review
    // still routes to rule 13 (never prune the review gate mechanically).
    if (s.close_event_present === true
        && !(s.review && s.review.required === true
             && !['pass', 'waived'].includes(s.review.status))) {
      return dispatchFor('Metrics Flush', s, '4b', { reasons: ['closed_but_unflushed_focus'] });
    }
  }
  // Rules 5+6 — spec mapping / freeze proxies.
  if (!s.spec || s.spec.path == null || !s.spec.present) return dispatchFor('Planning', s, '5');
  // Ceremony level (RFC-0009 / spec-scale-adaptive-ceremony): FAIL-CLOSED to 2
  // (full ceremony). Anything outside the declared integer enum — absent field,
  // legacy snapshot, garbage frontmatter token — can only ever ADD ceremony,
  // never prune a gate. The snapshot builder applies the same guard; this one
  // re-guards pure-call inputs (old/hand-built snapshots).
  const lvl = deriveLevel(s.spec);
  // Ceremony-aware dispatch lane (spec-loop-ceremony-aware-dispatch D1): a
  // DERIVED OUTPUT FIELD, never a new rule — computed once, immediately
  // after the lvl guard above, from the SAME already-guarded value. Used
  // below only to annotate the rule-11 Validation dispatch with its
  // lightweight-lane reason; dispatchFor() independently derives the same
  // value for every other dispatch verdict (see deriveLane()).
  const lane = deriveLane(s.spec);
  // Rule 6 — freeze proxy. L0 prunes ONLY the frontmatter-status arm (the
  // tech-note lives in the intake CHANGE doc, whose status lifecycle is not
  // the spec enum); the SPEC-FROZEN marker arm is never pruned.
  if (!s.spec.frozen || (lvl !== 0 && !['draft', 'implementing'].includes(s.spec.frontmatter_status))) {
    return dispatchFor('Planning', s, '6');
  }
  // Rule 7 — strategy undecided.
  if (s.strategy_selected == null || s.strategy_selected === 'undecided') {
    return dispatchFor('Planning', s, '7');
  }
  // Rule 8 — worktree recommendation gate. L3 tightens: the recommendation is
  // coerced to `required` (worktree decision mandatory for protected surfaces).
  if (s.worktree && s.worktree.user_decision === 'undecided') {
    const legacyArm = ['recommended', 'required'].includes(s.worktree.recommendation);
    if (legacyArm) return dispatchFor('Implementation Preparation / Worktree decision', s, '8');
    if (lvl === 3) {
      return dispatchFor('Implementation Preparation / Worktree decision', s, '8',
        { reasons: ['l3_worktree_mandatory'] });
    }
  }
  // The remaining rules read the focus work item.
  if (!s.work_item) return needsLlm(s, ['focus_ref_not_in_active_work_items']);
  const phase = s.work_item.phase;
  // Rule 9 — implementation/tests missing: planning done or preparation phase.
  if ((phase === 'planning' && s.work_item.status === 'done') || phase === 'preparation') {
    // Rule 9x (CHANGE-0120 confirm-by-script) — a re-plan that moved NOTHING in
    // the spec's AC/test contract must not respawn a full implementer just to
    // re-confirm an already-green phase (the live Codex log's tick 1). The
    // comparison is against the FROZEN SPEC's own content, never against the
    // re-plan's self-report: `content_hash` is computed from the parsed AC ids
    // + statuses and Test Plan ids + AC mapping (docs-model specContentHash),
    // so whitespace and prose edits are invisible while any real contract move
    // is not. FAIL-CLOSED to dispatching on every unknown: a null hash, a
    // non-green AC table, a snapshot predating these fields (undefined), or no
    // proof of prior green all fall through to 9a/9b/9c unchanged.
    const hash = s.spec.content_hash ?? null;
    const prior = s.last_phase_confirm ?? null;
    if (!opts.skipConfirm && s.spec.ac_green === true && hash !== null
      && (prior ? prior.hash === hash : s.prior_implementer_run === true)) {
      const out = noAction('9x', s, ['phase_confirmed_no_delta', 'advance_phase_to_implementation']);
      out.confirm_event = { event: 'phase_confirmed', ref: s.focus.ref_id, phase, hash };
      return out;
    }
    if (s.strategy_selected === 'tdd') return dispatchFor('TDD Implementation', s, '9a');
    if (s.strategy_selected === 'hybrid') return dispatchFor('TDD Implementation', s, '9b');
    // loop | direct | untested all run the regular Implementation agent (9c),
    // which reads implementation_strategy.selected and honors the chosen lane.
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
  // counts as run (G3: never re-fire 11 on a pass + review-only reset). The
  // status !== 'done' clause (spec-dispatch-new-intake-after-completed-scope
  // D5) is an explicit skip: a done work item is terminal and must never be
  // re-offered to Validation — the flushed variant is resolved by the 4a arm
  // above; the not-yet-flushed variant degrades to needs_llm no_rule_matched
  // (structurally ambiguous, recorded edge case, not a gap).
  if (vstatus === 'not_run'
    && s.work_item.status !== 'done'
    && ['implementation', 'validation', 'remediation', 'code_review'].includes(phase)) {
    return dispatchFor('Validation', s, '11',
      lane.selected === 'lightweight' ? { reasons: ['lightweight_lane_declared_scope'] } : {});
  }
  // Rule 12 — review FAIL -> Remediation (same forensic residue as rule 10).
  if (s.review && s.review.status === 'fail') {
    if (s.last_run_role === 'Remediation') return needsLlm(s, ['possible_missing_remediation_reset'], '12');
    return dispatchFor('Remediation', s, '12');
  }
  // Judgment residue — a `pass` that does not name the focus ref may be a
  // stale/leaked verdict; "not run recently" is not mechanically decidable.
  if (vstatus === 'pass' && !vmatch) return needsLlm(s, ['validation_staleness_unknown']);
  // L3 (RFC-0009): review is MANDATORY on protected surfaces — a recorded
  // waiver is not mechanically acceptable at L3; flag it for the operator
  // checkpoint instead of proceeding to the flush arm (fail-closed).
  if (vstatus === 'pass' && lvl === 3 && s.review && s.review.status === 'waived') {
    return needsLlm(s, ['l3_review_waived_requires_operator_checkpoint'], '13');
  }
  // Rule 13 — validation pass, review required and missing. L3 coerces
  // `required` to true (L0's review OPTIONALITY is input-side policy — a
  // recorded required:false / waiver — which this rule already honors).
  if (vstatus === 'pass' && s.review && (s.review.required === true || lvl === 3)
    && !['pass', 'waived'].includes(s.review.status)) {
    return dispatchFor('Code Review', s, '13',
      lvl === 3 && s.review.required !== true ? { reasons: ['l3_review_mandatory'] } : {});
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

function parseIntakeFrontmatter(rawBody) {
  const body = rawBody.replace(/\r\n?/g, '\n'); // CRLF tolerance, mirrors the spec parser (review-20260717T125756Z NB-2)
  const fm = body.match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return { id: null, type: null, status: null };
  const idM = fm[1].match(/^id:\s*(\S+)\s*$/m);
  const typeM = fm[1].match(/^type:\s*(\S+)\s*$/m);
  const statusM = fm[1].match(/^status:\s*(\S+)\s*$/m);
  return { id: idM ? idM[1] : null, type: typeM ? typeM[1] : null, status: statusM ? statusM[1] : null };
}

// open_intakes probe (spec-dispatch-new-intake-after-completed-scope D2):
// top-level docs/issues/*.md, sorted by filename for determinism. A doc is a
// CANDIDATE when its frontmatter status is draft/implementing, OR when its
// frontmatter cannot be parsed (missing id or status) — an unparseable doc is
// kept as a fail-closed UNMAPPABLE candidate, never silently skipped (it can
// still block the deterministic path). Two exclusions apply only to
// draft/implementing docs: the doc matching the current focus (frontmatter
// id, matched work-item ref, or `TYPE-NNNN` filename prefix), and a candidate
// whose matched work item is already `done` (false-open, not a plannable
// scope). Work-item matching is primary_path first, then frontmatter id —
// this bridges mixed ref conventions (number-based CHANGE-0027 vs slug ids).
// Returns null on a directory scan failure (fail-closed: the CLI degrades to
// needs_llm open_intake_scan_failed).
function buildOpenIntakes(root, focusRef, workItems) {
  const dir = path.resolve(root, 'docs/issues');
  let files;
  try {
    files = fs.readdirSync(dir).filter(f => f.endsWith('.md')).sort();
  } catch {
    return null;
  }
  const candidates = [];
  for (const fname of files) {
    const relPath = `docs/issues/${fname}`;
    let body;
    try {
      body = fs.readFileSync(path.join(dir, fname), 'utf8');
    } catch {
      candidates.push({ ref_id: null, primary_path: relPath, doc_type: null, item_status: null, unmappable: true });
      continue;
    }
    const { id, type, status } = parseIntakeFrontmatter(body);
    if (id == null || status == null) {
      candidates.push({ ref_id: id, primary_path: relPath, doc_type: type, item_status: status, unmappable: true });
      continue;
    }
    if (!['draft', 'implementing'].includes(status)) continue; // closed doc: not a candidate

    const filenamePrefix = (fname.match(/^([A-Z]+-\d+)-/) || [])[1] || null;
    const matchedItem = workItems.find(it => it.primary_path === relPath)
      ?? workItems.find(it => it.ref_id === id)
      ?? null;
    const isFocusDoc = id === focusRef
      || (matchedItem && matchedItem.ref_id === focusRef)
      || filenamePrefix === focusRef;
    if (isFocusDoc) continue;
    if (matchedItem && matchedItem.status === 'done') continue; // false-open, not plannable

    const refId = matchedItem ? matchedItem.ref_id : id;
    const focusType = OPEN_INTAKE_DOC_TYPES[type] ?? null;
    candidates.push({ ref_id: refId, primary_path: relPath, doc_type: type, item_status: status, unmappable: focusType == null });
  }
  return candidates;
}

// TREE_HASH_EXCLUDE_PATHS (role-verification-guards G2, B1 fix —
// validation-20260816T131500Z). Tracked, append-only telemetry/generated
// ledgers that ordinary factory operation writes as a BYPRODUCT of a ride,
// never as a reviewed change to the tree a validator judged. Excluding them
// from computeTreeHash below breaks two feedback loops the un-excluded hash
// created in THIS repository (proven by probe_g2b in the validation report):
//   1. self-invalidation — the --confirm stamp appends to
//      docs/ai/EVENTS.jsonl AFTER tree_hash is computed for that tick, so the
//      write invalidated its own hash, and because the stamp is
//      first-observation-only (D2 "who writes it") it never recovered: the
//      staleness advisory latched ON permanently with nothing else changed.
//   2. ordinary-ride churn — docs/ai/decisions.jsonl, the regenerated
//      docs/INDEX.md, docs/ai/overview.html and
//      docs/ai/tests/test-runs.jsonl are all TRACKED and all move within
//      minutes of routine ride activity that has nothing to do with the
//      judged verdict.
// Deliberately narrow (an itemized denylist, not a whole directory), so a
// real change under docs/ai/ that IS part of what a reviewer judged
// (docs-audit.yaml, pr-config.yaml, update-config.yaml, ...) still moves the
// hash. Each entry is the repo-relative posix path exactly as
// `git status --porcelain` prints it — the SAME strings also match the
// `diff --git a/<path> b/<path>` header paths filterExcludedDiff compares
// against below (B4 fix), so a content edit inside an excluded ledger is
// exactly as invisible as its status-letter change already was.
const TREE_HASH_EXCLUDE_PATHS = new Set([
  'docs/ai/EVENTS.jsonl',
  'docs/ai/METRICS.jsonl',
  'docs/ai/decisions.jsonl',
  'docs/ai/tests/test-runs.jsonl',
  'docs/INDEX.md',
  'docs/ai/overview.html',
  'docs/ai/overview-data.json',
  'docs/ai/dashboard.html',
  'docs/ai/dashboard-data.json',
  'docs/ai/factory-report.html',
  'docs/ai/factory-report-data.json',
]);

// filterExcludedDiff(rawDiff) -> the `git diff HEAD` text with any per-file
// block whose path is a TREE_HASH_EXCLUDE_PATHS entry removed wholesale
// (role-verification-guards G2, B4 fix — validation-20260816T143000Z). Every
// file's hunks in unified diff output start with a `diff --git a/<path>
// b/<path>` header; dropping everything from a matching header up to (not
// including) the next one applies the exact SAME denylist used on the
// porcelain status lines below, so an uncommitted edit to an excluded ledger
// stays invisible to the hash on BOTH inputs, never just one.
function filterExcludedDiff(rawDiff) {
  if (!rawDiff) return '';
  const lines = rawDiff.split('\n');
  const kept = [];
  let skipping = false;
  for (const line of lines) {
    const m = /^diff --git a\/(.+) b\/(.+)$/.exec(line);
    if (m) {
      skipping = TREE_HASH_EXCLUDE_PATHS.has(m[1]) || TREE_HASH_EXCLUDE_PATHS.has(m[2]);
      if (skipping) continue;
    }
    if (!skipping) kept.push(line);
  }
  return kept.join('\n');
}

// computeTreeHash(root) -> sha256 hex string, or null on any git failure
// (role-verification-guards G2, D2; content-sensitivity added at remediation
// — validation-20260816T143000Z B4). A TREE hash, NOT a spec content hash:
// sha256 over `git rev-parse HEAD`, `git status --porcelain=v1 -uno` (minus
// any line naming a TREE_HASH_EXCLUDE_PATHS entry, B1 fix) AND `git diff
// HEAD` for tracked changes (minus any per-file block naming a
// TREE_HASH_EXCLUDE_PATHS entry via filterExcludedDiff, same list, B4 fix).
// The status line alone carries only a path and an XY status letter, never
// content, so editing a tracked file that was ALREADY dirty left the pre-B4
// hash byte-identical — proven the dominant shape on a live ride (this
// repository sits at 20 modified tracked files as a matter of routine).
// Folding in the diff closes that blind spot while keeping every existing
// property: `-uno`/plain `git diff HEAD` (no `--no-index`) both ignore
// untracked files identically, the exclusion list still applies via the
// SAME Set to both inputs, and any git failure at any of the three calls
// fails the whole hash open to null, same as before. Measured cost on this
// repository (rsync copy, mktemp; never this repo — see D5): `git diff
// HEAD` adds roughly 20ms beside the ~10ms `git status` call already paid
// every tick, immaterial next to the rest of a dispatch tick's file I/O.
// What this still does NOT close (D5/RR-2): a tree that moved and moved
// back to byte-identical content is still invisible, and a COMMIT touching
// only an excluded path still moves `git rev-parse HEAD`.
function computeTreeHash(root) {
  try {
    const head = execFileSync('git', ['rev-parse', 'HEAD'], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    });
    const rawStatus = execFileSync('git', ['status', '--porcelain=v1', '-uno'], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    });
    const status = rawStatus.split('\n').filter((line) => {
      if (line.length <= 3) return true; // blank/malformed: keep, never seen in practice
      return !TREE_HASH_EXCLUDE_PATHS.has(line.slice(3).trim());
    }).join('\n');
    // maxBuffer raised 16 MB -> 64 MB (role-verification-guards remediation,
    // N-C): TREE_HASH_EXCLUDE_PATHS does NOT reduce what crosses this buffer
    // — filterExcludedDiff runs on the string AFTER execFileSync returns, so
    // a large regenerated EXCLUDED ledger counts against the limit in full
    // before it is ever filtered out. Costs nothing when unused; see D5.
    const rawDiff = execFileSync('git', ['diff', 'HEAD', '--'], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024,
    });
    const diff = filterExcludedDiff(rawDiff);
    return crypto.createHash('sha256').update(head + status + diff).digest('hex');
  } catch {
    return null;
  }
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
  // ceremony_level (RFC-0009): read from the spec_path file's frontmatter,
  // FAIL-CLOSED to 2 (full ceremony) on absent field, missing file, missing
  // frontmatter, yaml null, or any token outside the literal enum 0|1|2|3.
  // content_hash / ac_green (CHANGE-0120) are the rule-9x confirm inputs; both
  // stay at their fail-closed defaults (null / false) whenever the spec is
  // absent or carries no AC or Test Plan table.
  const spec = { path: specPath ?? null, present: false, frozen: false, frontmatter_status: null, ceremony_level: 2, content_hash: null, ac_green: false };
  if (specPath) {
    const abs = path.resolve(root, specPath);
    if (fs.existsSync(abs)) {
      spec.present = true;
      const body = fs.readFileSync(abs, 'utf8').replace(/\r\n?/g, '\n');
      spec.frozen = /^SPEC-FROZEN: true$/m.test(body);
      spec.content_hash = specContentHash(body);
      spec.ac_green = acTableGreen(body).green;
      const fm = body.match(/^---\n([\s\S]*?)\n---/);
      if (fm) {
        const st = fm[1].match(/^status:\s*(\S+)/m);
        if (st) spec.frontmatter_status = st[1];
        const cl = fm[1].match(/^ceremony_level:\s*(\S+)\s*$/m);
        if (cl && ['0', '1', '2', '3'].includes(cl[1])) spec.ceremony_level = Number(cl[1]);
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
  // validationRunAtUtc (role-verification-guards remediation, B-1) — the
  // recorded verdict's own timestamp, read from the SAME block as `validation`
  // above but DELIBERATELY kept OFF the `snapshot` object (and therefore off
  // `state_summary`, which is `snapshot` verbatim): Spec-AC-05 pins
  // state_summary as additive-only modulo exactly the two G2 fields
  // (`tree_hash`, `last_validation_verdict`); a third visible key would widen
  // that contract for a value only main()'s re-stamp condition needs, never
  // decide() or any consumer of the JSON. Returned as a sibling of `snapshot`
  // below instead.
  const validationRunAtUtc = readScalar(lines, 'last_validation', 'run_at_utc');
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
  // Rule 4b close-event probe: a committed work_item_closed event for the
  // focus ref proves the close ceremony ran (possibly in another session or
  // clone whose local STATE verdicts never traveled). Best-effort scan of the
  // shared append-only audit log; any read/parse failure leaves the flag
  // false, which preserves pre-4b behavior exactly.
  // The SAME scan also carries the rule-9x comparison snapshot (CHANGE-0120):
  // the LAST phase_confirmed event for the focus ref. EVENTS.jsonl is the
  // storage on purpose — append-only, committed, and readable by any clone,
  // so the confirm arm needs no new STATE field (docs/ai/STATE.yaml is
  // gitignored per-dev runtime state, and state.mjs is a protected L3 surface
  // this change deliberately does not touch).
  let closeEventPresent = false;
  let lastPhaseConfirm = null;
  // role-verification-guards G2 — the LAST validation_verdict event for the
  // focus ref, from the SAME scan (last wins, matching the phase_confirmed
  // precedent immediately below). Null when no such event has ever been
  // recorded for this ref.
  let lastValidationVerdict = null;
  const eventsPath = path.resolve(root, 'docs/ai/EVENTS.jsonl');
  if (focusRef && fs.existsSync(eventsPath)) {
    for (const line of fs.readFileSync(eventsPath, 'utf8').split(/\r?\n/)) {
      const t = line.trim();
      if (t === '' || t.startsWith('#')) continue;
      try {
        const e = JSON.parse(t);
        if (!refMatches(e.ref, focusRef)) continue;
        if (e.event === 'work_item_closed') closeEventPresent = true;
        else if (e.event === 'phase_confirmed' && e.payload) {
          lastPhaseConfirm = { phase: e.payload.phase ?? null, hash: e.payload.hash ?? null };
        } else if (e.event === 'validation_verdict' && e.payload) {
          // `ts` (role-verification-guards remediation, B-1) — the EVENT's
          // own auto-filled append-event.mjs timestamp, carried through so
          // main() can compare it against last_validation.run_at_utc and
          // tell a fresh stamp from a stale one. Every append-event.mjs line
          // carries `ts`; a hand-corrupted or pre-B-1 line without it falls
          // back to null, which the stamp condition below treats as "cannot
          // prove this stamp is fresh" (fail-closed to no-re-stamp, same
          // polarity as every other null-hash guard in this file).
          lastValidationVerdict = { status: e.payload.status ?? null, hash: e.payload.hash ?? null, ts: e.ts ?? null };
        }
      } catch { /* unparseable event line: best-effort probe, skip */ }
    }
  }
  // role-verification-guards G2 — TREE hash of the current working tree
  // (D2). Computed unconditionally (read-only git probe, no --confirm gate)
  // so the staleness comparison in decide() always has a fresh right-hand
  // side; git failure -> null, same fail-open contract as every other probe
  // here.
  const treeHash = computeTreeHash(root);
  const runs = focusRef ? agentRunsFor(lines, focusRef) : [];
  const openIntakes = buildOpenIntakes(root, focusRef, items);
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
    close_event_present: closeEventPresent,
    last_phase_confirm: lastPhaseConfirm,
    // role-verification-guards G2 — the two staleness-comparison inputs
    // (D2); decide() only ever compares them, never recomputes either.
    tree_hash: treeHash,
    last_validation_verdict: lastValidationVerdict,
    // Rule 9x prior-green bootstrap: an implementer actually ran for this ref
    // at some point. Paired with a fully green AC table it is the committed
    // proof that the phase WAS green before the re-plan bounced it back; on
    // its own it confirms nothing.
    prior_implementer_run: runs.some(r => IMPLEMENTER_ROLES.includes(r.role)),
    open_intakes: openIntakes,
    implementer_model: focusRef ? lastImplementerModel(lines, focusRef) : null,
    last_run_role: runs.length ? runs[runs.length - 1].role : null,
  };
  return { snapshot, problems: [], validationRunAtUtc };
}

// --- CLI ---------------------------------------------------------------------------

function usage() {
  console.error(
    'Usage: orchestration-dispatch [--state <path>] [--root <dir>] [--human] [--rules] [--confirm]\n'
    + '  Deterministic orchestration tick: reads STATE + repo probes, prints ONE\n'
    + '  dispatch JSON on stdout. Exit: 0 dispatch, 3 no action, 4 LLM must take\n'
    + '  over (named reasons in JSON), 2 usage, 1 internal error.\n'
    + '  Reads only, with ONE opt-in exception: --confirm permits TWO idempotent\n'
    + '  docs/ai/EVENTS.jsonl appends — the rule-9x arm\'s phase_confirmed line\n'
    + '  (skipped once the last recorded confirmation already matches), and a\n'
    + '  first-observation validation_verdict stamp (role-verification-guards G2,\n'
    + '  skipped once one already exists for the ref). STATE and the spec are\n'
    + '  NEVER written, with or without the flag.',
  );
}

function parseArgs(argv) {
  const opts = { state: 'docs/ai/STATE.yaml', root: process.cwd(), human: false, rules: false, confirm: false };
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
    } else if (tok === '--confirm') {
      opts.confirm = true;
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

// Optional deterministic tier->model binding (.aai/system/MODEL_ROUTING.yaml).
// Absent file => suggested_model stays null and the orchestrator falls back to
// interpreting suggested_tier itself (pre-binding behavior, fully back-compat).
// Line-based parse mirroring the PROFILES.yaml discipline: two-space-indented
// `  <key>: <value>` rows under `tiers:` / `roles:` (and the cache-friendly-
// dispatch `effort_tiers:` / `effort_roles:`) sections only.
function loadModelRouting(root) {
  const p = path.resolve(root, '.aai/system/MODEL_ROUTING.yaml');
  if (!fs.existsSync(p)) return null;
  const routing = { tiers: {}, roles: {}, effort_tiers: {}, effort_roles: {}, validation_alternate: null };
  let section = null;
  let raw;
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch {
    return null;
  }
  for (const line of raw.split(/\r?\n/)) {
    if (line.trim() === '' || line.trim().startsWith('#')) continue;
    if (/^tiers:\s*$/.test(line)) { section = 'tiers'; continue; }
    if (/^roles:\s*$/.test(line)) { section = 'roles'; continue; }
    // cache-friendly-dispatch: advisory reasoning-effort routing sections,
    // parsed exactly like tiers:/roles: (absent sections stay empty maps -> a
    // pre-effort MODEL_ROUTING.yaml resolves suggested_effort to null, back-compat).
    if (/^effort_tiers:\s*$/.test(line)) { section = 'effort_tiers'; continue; }
    if (/^effort_roles:\s*$/.test(line)) { section = 'effort_roles'; continue; }
    const top = line.match(/^validation_alternate:\s*(\S+)\s*$/);
    if (top) { routing.validation_alternate = top[1] === 'null' ? null : top[1]; section = null; continue; }
    if (/^\S/.test(line)) { section = null; continue; }
    const kv = line.match(/^ {2}([^:#]+):\s*(\S+)\s*$/);
    if (kv && section) routing[section][kv[1].trim()] = kv[2];
  }
  return routing;
}

// suggested_model resolution order: lane-scoped role override (role@lane,
// e.g. "Validation@lightweight"), then per-role override, then tier default,
// then null. The lane key is built from out.lane.selected (produced by
// deriveLane() — "lightweight" on ceremony L0/L1, "full" otherwise) so a
// ceremony-lightweight dispatch can resolve a distinct model without
// touching the plain role/tier defaults every other dispatch relies on
// (additive/back-compat: configs and out shapes without a lane resolve
// byte-identically to before this step existed). Validator independence
// backstop applied AFTER, unchanged: when the routed Validation model equals
// the recorded implementer model, swap to validation_alternate (same
// weights = same blind spots; SUBAGENT_PROTOCOL.md validator rule).
export function suggestModel(out, routing) {
  if (!routing || out.verdict !== 'dispatch') return null;
  const laneSelected = out.lane && out.lane.selected;
  const laneKey = out.role && laneSelected ? `${out.role}@${laneSelected}` : null;
  let model = (laneKey && routing.roles[laneKey])
    ?? (out.role && routing.roles[out.role])
    ?? (out.suggested_tier ? routing.tiers[out.suggested_tier] : null)
    ?? null;
  if (out.role === 'Validation' && model
      && out.validator_independence
      && out.validator_independence.implementer_model === model
      && routing.validation_alternate) {
    model = routing.validation_alternate;
  }
  return model;
}

// suggested_effort resolution (cache-friendly-dispatch): advisory reasoning-
// effort hint per role, MIRRORING suggestModel's config-driven contract.
// Resolution order: per-role override (effort_roles[role]) then tier default
// (effort_tiers[tier]) then null. Effort is a SEPARATE axis from the model
// tier (a standard-tier Validation is high-effort; a premium-tier Planning is
// default-effort), so it is per-role, never derived from suggested_tier alone.
// Absent file (routing null), absent sections, or a no-match all resolve to
// null -> today's output (the field simply carries null, advisory/never
// binding, exactly like suggested_model at introduction). No lane scoping:
// effort does not vary by ceremony lane. NEVER flip effort mid-session — the
// harness caches on it (see MODEL_ROUTING.yaml header pin).
export function suggestEffort(out, routing) {
  if (!routing || out.verdict !== 'dispatch') return null;
  return (out.role && routing.effort_roles[out.role])
    ?? (out.suggested_tier ? routing.effort_tiers[out.suggested_tier] : null)
    ?? null;
}

// recordConfirm (CHANGE-0120) — the ONLY write this script can perform, gated
// behind --confirm and reachable ONLY from the rule-9x arm. Idempotent by
// construction: the append is skipped when the LAST recorded confirmation for
// the ref already carries the same phase+hash, so re-ticking an unchanged
// scope never grows the ledger. Delegates to the sibling append-event.mjs so
// the EVENTS schema (v / ts / actor) keeps exactly ONE writer; `root` is the
// child's cwd, which is what decides where docs/ai/EVENTS.jsonl lands.
//
// Returns a TRI-STATE, because the two ways of NOT appending are opposites:
//   'appended' — a line was written
//   'skipped'  — the SAME confirmation is already on the ledger (idempotence:
//                the confirmation EXISTS, so the next tick will see it)
//   'failed'   — the child could not write it, so the confirmation does NOT
//                exist and never will; the caller must fail closed
// Collapsing the last two into one `false` is what let a failed recording read
// as a clean no_action: the tick reported a confirmation, the ledger stayed
// empty, and the NEXT tick re-derived the same confirm from the same state —
// forever, never advancing the phase and never saying why.
function recordConfirm(ev, root, snapshot) {
  const prior = snapshot && snapshot.last_phase_confirm;
  if (prior && prior.hash === ev.hash && prior.phase === ev.phase) return 'skipped';
  const appender = path.join(path.dirname(fileURLToPath(import.meta.url)), 'append-event.mjs');
  try {
    execFileSync(process.execPath, [appender,
      '--event', 'phase_confirmed', '--ref', ev.ref,
      '--phase', String(ev.phase), '--hash', ev.hash], { cwd: root, stdio: 'ignore' });
    return 'appended';
  } catch {
    return 'failed';
  }
}

// recordValidationVerdict (role-verification-guards G2, D2; re-stamp
// condition corrected at remediation B-1) — the SECOND write --confirm
// permits, independent of the rule-9x confirm arm above and of which rule
// fired this tick. PER-VERDICT, not per-ref-forever: fires when
// last_validation.status is 'pass' FOR THE FOCUS REF (refMatches, same guard
// rule 13/14 already apply to a leaked/stale verdict), tree_hash is known,
// and EITHER no validation_verdict event exists yet for that ref OR the
// recorded validation's own `run_at_utc` is strictly newer than the last
// stamped event's `ts` — i.e. a fresh validation round has been recorded
// since the last stamp. Until a newer verdict is observed, the SAME verdict
// is stamped once (repeated --confirm ticks with nothing new to observe do
// not re-append). This is D2's stated window trade ("who writes it"), NOT
// the phase_confirmed precedent: `recordConfirm` above DOES re-append
// whenever the hash moves (it only returns 'skipped' when
// `prior.hash === ev.hash && prior.phase === ev.phase`) — a corrected claim,
// validation-20260816T131500Z N2; the two writers deliberately differ.
//
// Corrected at remediation (B-1): the ORIGINAL condition was
// `!snapshot.last_validation_verdict` — gated on whether ANY stamp event
// existed for the ref, never on whether it was still the CURRENT verdict's
// stamp. After the first remediation lap on any ride, every later pass
// verdict stamped nothing, so `withStaleAdvisory` compared the current tree
// against a reference that was one or more remediations old and the
// `validation_verdict_stale` advisory latched permanently ON — exactly the
// motivating incident G2 exists to catch, reproduced end-to-end in the
// review that found it. The fix compares timestamps, not existence.
//
// A DIFFERENT design — refresh-on-hash-mismatch — was weighed for G2 and
// rejected, and that rejection still stands: because decide() reads the
// snapshot BUILT BEFORE this tick's own write, refreshing on a tree_hash
// mismatch would still print one stale line on the very tick that observes
// each tracked delta before healing itself, whereas TREE_HASH_EXCLUDE_PATHS
// (B1, above) removes that self-invalidation at its source instead.
// Refresh-on-NEW-VERDICT (this fix) is a different trigger with none of that
// behavior: it fires only when a validator records something new, never as a
// reaction to the tree moving.
//
// Delegates to append-event.mjs so the EVENTS schema keeps exactly ONE
// writer. Every failure is swallowed: unlike recordConfirm this write has no
// fail-closed fallback to take — it is purely additive telemetry for a NEXT
// tick's staleness comparison, never something THIS tick's verdict depends
// on.
function recordValidationVerdict(root, ref, status, hash) {
  const appender = path.join(path.dirname(fileURLToPath(import.meta.url)), 'append-event.mjs');
  try {
    execFileSync(process.execPath, [appender,
      '--event', 'validation_verdict', '--ref', ref,
      '--status', status, '--hash', hash], { cwd: root, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
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
    `Suggested model id: ${out.suggested_model ?? '(unbound — no .aai/system/MODEL_ROUTING.yaml)'}`,
    `Suggested effort: ${out.suggested_effort ?? '(unset — no matching effort routing)'}`,
  ];
  if (out.validator_independence) {
    lines.push(`Validator independence: implementer_model=${out.validator_independence.implementer_model ?? 'null'} (validator model must differ)`);
  }
  if (typeof out.prompt_hash === 'string') {
    lines.push(`Prompt hash: ${shortHash(out.prompt_hash)} (informational — content-addressed identity of the effective instruction stack)`);
    if (out.inherits) {
      lines.push(`Inherits: CONTRACT@${shortHash(out.inherits.contract)} LEARNED@${shortHash(out.inherits.learned)} (per-component provenance)`);
    }
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
    const { snapshot, problems, validationRunAtUtc } = buildSnapshot(statePath, root);
    if (problems.length > 0) {
      out = needsLlm(snapshot, problems);
      out.state_summary = snapshot ?? {};
    } else {
      out = decide(snapshot);
      out.state_summary = snapshot;
    }
    // CHANGE-0120: --confirm records the rule-9x confirmation. Only that arm
    // ever sets confirm_event, so no other verdict can reach the writer.
    // Resolved BEFORE routing/prompt-hash so the fail-closed fallback below
    // gets its model tier, effort and prompt hash computed like any dispatch.
    if (opts.confirm && out.confirm_event) {
      const rec = recordConfirm(out.confirm_event, root, out.state_summary);
      out.confirm_recorded = rec === 'appended';
      if (rec === 'failed') {
        // FAIL CLOSED. A confirmation that could not be written does not exist:
        // the next tick reads the same state, re-confirms, and the phase never
        // advances — a silent permanent stall. Take the dispatch that rule 9x
        // suppressed instead, and say so on stderr.
        console.error('orchestration-dispatch: NOTE — --confirm could not record the phase_confirmed event; falling back to a real dispatch (an unrecorded confirmation is invisible to the next tick and would repeat forever)');
        const fallback = decide(snapshot, { skipConfirm: true });
        fallback.state_summary = snapshot;
        fallback.confirm_recorded = false;
        fallback.reasons = [...fallback.reasons, 'confirm_record_failed_fallback_dispatch'];
        out = fallback;
      }
    }
    // role-verification-guards G2 (D2) — validation-verdict stamp, under the
    // SAME --confirm opt-in, independent of the rule-9x confirm_event arm
    // above (it can fire on ANY rule, e.g. the rule-14 metrics-flush arm a
    // fresh pass verdict typically lands on). PER-VERDICT (corrected at
    // remediation, B-1): re-stamps when either no validation_verdict event
    // exists yet for the ref, OR the recorded validation's own run_at_utc
    // (read separately from `snapshot` — see buildSnapshot's
    // `validationRunAtUtc`, kept OFF state_summary so Spec-AC-05's additive
    // key count does not grow) is strictly newer than the last stamped
    // event's ts — i.e. a validation round has completed SINCE the last
    // stamp. Both timestamps are ISO 8601 UTC strings, but at DIFFERENT
    // precision BY DESIGN — corrected at remediation, BLOCKING-1
    // (validation-20260816T203700Z): append-event.mjs's auto-filled `ts`
    // keeps milliseconds while state-engine.mjs's `nowIso()` (state.mjs's
    // self-stamped `run_at_utc`) truncates to the second. A prior version of
    // this comment claimed "lexicographic `>` is a correct newer-than
    // comparison" — that was FALSE: at string index 19 a truncated-second
    // string ends in `Z` (0x5A) while a millisecond string in the same
    // second has `.` (0x2E) there, so the truncated string sorts ABOVE the
    // millisecond one even though it is not later, and a verdict recorded in
    // the SAME wall-clock second as its own stamp compared as strictly
    // *newer* than that stamp — on every later tick, forever, since the
    // comparison is against the last stamp's `ts`, not the live clock. Both
    // sides are now parsed via `Date.parse` and compared as instants
    // (`validationRunAtMs`/`lastStampMs` below), each guarded by
    // `Number.isFinite`: an unparseable value — same as an absent one (an
    // old event predating this field, or a fixture/STATE without
    // `run_at_utc`) — fails the freshness check closed, no re-stamp, the
    // same polarity as every other missing-data guard in this file. A
    // same-second verdict and stamp now compare as NOT newer (truncation
    // makes the two instants equal), which is the correct fail-closed
    // reading: a verdict whose recorded second matches the stamp's cannot be
    // *proven* newer. None of this changes the "stamp once, ever" case: the
    // `!lvv` arm still covers first observation exactly as before.
    const validationRunAtMs = validationRunAtUtc ? Date.parse(validationRunAtUtc) : NaN;
    const lastStampMs = (snapshot && snapshot.last_validation_verdict && snapshot.last_validation_verdict.ts)
      ? Date.parse(snapshot.last_validation_verdict.ts) : NaN;
    if (opts.confirm && snapshot && snapshot.validation && snapshot.validation.status === 'pass'
      && snapshot.focus && snapshot.focus.ref_id
      && refMatches(snapshot.validation.ref_id, snapshot.focus.ref_id)
      && snapshot.tree_hash != null
      && (!snapshot.last_validation_verdict
        || (Number.isFinite(validationRunAtMs) && Number.isFinite(lastStampMs) && validationRunAtMs > lastStampMs))) {
      recordValidationVerdict(root, snapshot.focus.ref_id, snapshot.validation.status, snapshot.tree_hash);
    }
    // role-verification-guards G2 (D2) — stale-verdict advisory, printed
    // regardless of --confirm/--human and regardless of which rule fired;
    // decide() already computed the additive `advisories` key purely from
    // the snapshot.
    if (Array.isArray(out.advisories) && out.advisories.includes('validation_verdict_stale')) {
      console.error(
        `orchestration-dispatch: WARN validation_verdict_stale - ref ${out.ref_id ?? '(unknown)'}: `
        + 'the recorded pass verdict\'s tree hash no longer matches the tracked tree'
      );
    }
    const routing = loadModelRouting(root);
    out.suggested_model = suggestModel(out, routing);
    // Advisory reasoning-effort hint (cache-friendly-dispatch), resolved from
    // the SAME routing load; null when the file/field is absent (back-compat).
    out.suggested_effort = suggestEffort(out, routing);
    // prompt-hash-telemetry Spec-AC-05: additive-only — only a real dispatch
    // (system_prompt present) gets a prompt_hash; no_action/needs_llm verdicts
    // (no role, no system_prompt) are untouched.
    if (out.system_prompt) {
      out.prompt_hash = computeEffectivePromptHash(out.system_prompt, root);
      // Inheritance provenance (promptbook adoption 4): per-component
      // versions the role inherits, additive alongside the aggregate hash.
      out.inherits = componentHashes(out.system_prompt, root);
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
