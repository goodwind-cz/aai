# Shared prompt-diet byte-floor ledger (prompt-diet-floor-credit-drift /
# SPEC-DRAFT-spec-prompt-diet-floor-credit-drift.md).
#
# Single sourceable definition of the diet-floor constants, the
# JUSTIFIED_ADDITIONS ledger, and the two pure helpers, so
# tests/skills/test-aai-prompt-diet.sh and tests/skills/test-aai-verify-gate.sh
# can never drift from each other again (DEBT-0002 "two copies of one gate"
# pattern; docs/knowledge/LEARNED.md 2026-07-17).
#
# This file is a PURE library: no `set -u`, no `cd`, no test execution. It is
# only ever sourced, never run directly. bash-3.2 / Windows-Git-Bash safe: no
# `bc`, no `mapfile`, no `declare -A`.

# Byte baseline measured before any CHANGE-0011 edit (evidence:
# docs/ai/tdd/prompt-diet-kb-before.txt). AC floor: >= 28KB net reduction.
# BASELINE_PROMPT_BYTES and REQUIRED_REDUCTION_BYTES are the historical
# SPEC-0017 diet contract and stay UNCHANGED (DEBT-0002/SPEC-0048): rewriting
# them to match live measurements would erase history and IS the
# blank-raise anti-pattern the floor exists to prevent.
BASELINE_PROMPT_BYTES=357457
REQUIRED_REDUCTION_BYTES=28672   # 28 KB

# --- Justified-growth ledger (DEBT-0002/SPEC-0048 -> CHANGE-0040/SPEC-0059) -
# Canon-mandated prompt additions AFTER the SPEC-0017 diet legitimately grew
# the corpus. JUSTIFIED_GROWTH_BYTES is no longer a manually-bumped magic
# number: it is the portable bash-3.2 sum of the leading `<bytes>` field of
# each JUSTIFIED_ADDITIONS entry below (no bc, no mapfile, no declare -A --
# just `${_entry%% *}` + `$(( ))`, so it also runs under the Windows/Git-Bash
# matrix). Each entry is self-documenting: "<bytes> <ref> <rationale>".
# Adding a new legitimate prompt addition is a one-line array append with its
# own audit trail, not a recomputed constant (source: DEBT-0002 root cause,
# docs/knowledge/LEARNED.md 2026-07-17; true-up history: ISSUE-0016).
JUSTIFIED_ADDITIONS=(
  "6144 DEBT-0002 dual-verdict code-review taxonomy + VALIDATION 8a exception + CEREMONY LANE block (SPEC-0041) + RED_CLASS discipline (SPEC-0044) + SECRETS PREFLIGHT (SPEC-0045) + doc-number origin reservation (SPEC-0047) + ceremony-lane declaration surfaces (SPEC_TEMPLATE/PLANNING/WORKFLOW); measured deficit 5122 B, credit chosen 6144 B for 1022 B headroom"
  "1309 CHANGE-0037 deterministic close-ceremony wiring prose: SKILL_PR.prompt.md step 5c close-work-item.mjs invocation (+1144 B) + VALIDATION 8b hand-flip/hand-emit removal replaced by close-ceremony pointer (+165 B)"
  "1786 CHANGE-0038+0039 workflow-hardening wiring prose: METRICS_FLUSH.prompt.md rewrite (flush no longer emits close events, SPEC-0054) + SKILL_PR step 2b RECONCILE WORKTREE TELEMETRY invocation prose (SPEC-0055)"
  "3100 aai-release-skill new .aai/SKILL_RELEASE.prompt.md thin-wrapper prompt (SPEC-DRAFT-spec-aai-release-skill D9) documenting the /aai-release deterministic release-cut engine (--dry-run/--version/--confirm/--no-remote), mirroring SKILL_UPDATE.prompt.md's shape; measured deficit 3027 B, credit chosen 3100 B for 73 B headroom"
  "825 reaper-deterministic-age-guard SKILL_LOOP.prompt.md POST-TICK REAP + VALIDATION.prompt.md step-boundary reap prose documenting the step owner's AAI_REAP_STEP_START_EPOCH=\$(date +%s) capture/handoff to the reaper's deterministic epoch guard; measured deficit 825 B, credit chosen 825 B for 0 B headroom"
  "5396 hitl-decision-propagation SKILL_HITL.prompt.md STEP 4c trigger->target mapping table + normalization table + fail-closed rule + write-ordering rule (replacing the old absolute STATE-field prohibition) + ORCHESTRATION_HITL.prompt.md [HITL-<n>] blocking_reason stamping prose (SPEC-DRAFT-spec-hitl-decision-propagation); measured deficit 4848 B + 548 B code-review remediation (scope FAIL-CLOSED to enum targets so HITL-1..6/8 cannot deadlock; sanction set-human-input for the STEP 5 clear so the narrowed guardrail cannot forbid the resolver's own job); credit chosen 5396 B for 0 B headroom"
  "738 metrics-flush-strands-completed-refs METRICS_FLUSH.prompt.md RUN step 1 one-line --sweep mention (opt-in durable-provenance multi-ref flush of stranded work items, SPEC-DRAFT-spec-metrics-flush-sweep) + --events NO-OP caveat update; measured deficit 418 B initial + 320 B code-review reword, credit chosen 738 B for 0 B headroom"
  "494 branch-per-work-item-hygiene SKILL_PR.prompt.md '0. BRANCH HYGIENE' precondition (runs branch-guard.mjs, fail-closed, STOPS before push on a mis-branched scope) + AGENTS.md one-branch-per-work-item rule naming the guard (ISSUE-0024/SPEC-0070); measured deficit 494 B, credit chosen 494 B for 0 B headroom"
  "566 planning-companion-obligations PLANNING.prompt.md step 3a COMPANION OBLIGATIONS CHECK (closed two-entry planner checklist: prompt-corpus byte growth -> prompt-diet ledger true-up; new .aai/** file -> PROFILES.yaml classification), self-dogfooding the rule it introduces (SPEC-DRAFT-spec-planning-companion-obligations); measured deficit 566 B, credit chosen 566 B for 0 B headroom"
  "488 friction-shadow-capture-wiring AGENTS.md '### Friction capture (shadow)' thin inheriting pointer to the FRICTION_PROTOCOL.md 'Skill wiring (shadow capture)' seam (RFC-0012 Phase 1, SPEC-DRAFT-spec-friction-shadow-capture-wiring); AGENTS.md is prompt corpus per PLANNING step 3a but sits outside TEST-010's live .aai/*.prompt.md glob, so its 488 B growth carries no MEASURED deficit — credited manually at exactly the +488 B AGENTS.md delta (18425 -> 18913) to keep the corpus-as-defined reduction honest, headroom 0 -> 488 within the 2048 cap. The seam BODY lives in .aai/system/FRICTION_PROTOCOL.md (system/, not corpus, no ledger cost)"
  "1486 feedback-triage-offline new .aai/SKILL_FEEDBACK_TRIAGE.prompt.md thin wrapper (RFC-0012 Phase 2 / RFC-0013 Slice B, SPEC-DRAFT-spec-feedback-triage-offline) documenting the offline /aai-feedback-triage engine (spool -> gates -> v2-signal scoring -> fingerprint clustering -> local report, no network), mirroring SKILL_UPDATE's thin-wrapper shape; the 1486 B prompt is inside TEST-010's live .aai/*.prompt.md glob (measured deficit 998 B after consuming the prior 488 B headroom), credited at the true +1486 B growth so JUSTIFIED_GROWTH tracks the actual corpus addition, headroom back to 488 within the 2048 cap"
  "608 friction-feedback-discovery SKILL_WRAP_UP.prompt.md step 6 FRICTION FEEDBACK NUDGE (runs aai-feedback-status.mjs at session end to surface captured observations / pending --confirm drafts / gh auth state, silent when nothing captured; RFC-0012 discovery, SPEC-DRAFT-spec-friction-feedback-discovery); 608 B inside TEST-010's live .aai/*.prompt.md glob (measured deficit 120 B after the prior 488 B headroom), credited at the true +608 B growth, headroom back to 488 within the 2048 cap"
  "1931 feedback-upsert-review new .aai/SKILL_FEEDBACK_UPSERT.prompt.md thin wrapper (RFC-0012 Phase 2c / Slice C, SPEC-DRAFT-spec-feedback-upsert-review) documenting the review-mode /aai-feedback-upsert engine (prepare-only default; --publish <fp> --confirm the ONLY GitHub write; transmit-pass redaction reuse; v1:<fp> dedup marker; budget ledger; destination pin); the 1931 B prompt is inside TEST-010's live .aai/*.prompt.md glob (measured deficit 1443 B after consuming the prior 488 B headroom), credited at the true +1931 B growth, headroom back to 488 within the 2048 cap"
  "535 prune-stale-briefs SKILL_WRAP_UP.prompt.md step 6b STALE-BRIEF SWEEP (runs prune-stale-briefs.mjs at session end to prune terminal/orphan work-item briefs while KEEPING live handoffs, no-op when clean; AAI docs-lifecycle hygiene, CHANGE-DRAFT-prune-stale-briefs); the 535 B step is inside TEST-010's live .aai/*.prompt.md glob (measured deficit 47 B after consuming the prior 488 B headroom), credited at the true +535 B growth, headroom back to 488 within the 2048 cap"
  "3336 auditor-autonomy-pack new .aai/SKILL_SHIP.prompt.md end-to-end autopilot composition prompt (3201 B: need -> intake -> loop -> product docs -> ONE ship checkpoint -> PR, autopilot defaults recorded, never merges) + ORCHESTRATION.prompt.md / ORCHESTRATION_PARALLEL.prompt.md MODEL SELECTION suggested_model pointers to the .aai/system/MODEL_ROUTING.yaml deterministic tier->id binding (+15 B / +120 B; ORCHESTRATION held at 40 lines per the spec D5 cap); measured deficit 2848 B after consuming the prior 488 B headroom, credited at the true +3336 B growth, headroom back to 488 within the 2048 cap"
  "148 auditor-autonomy-pack AGENTS.md SKILL_SHIP listing line in the Universal Skills block — AGENTS.md sits outside TEST-010's live .aai/*.prompt.md glob, so the growth carries no MEASURED deficit; credited manually at the exact +148 B AGENTS.md delta (18913 -> 19061) to keep the corpus-as-defined reduction honest, headroom 488 -> 636 within the 2048 cap"
  "912 token-capture-canary SKILL_LOOP.prompt.md step 4 mandatory-usage-note reinforcement (usage_total_tokens=<N> non-optional at merge time) + step 6 MANDATORY --started/--harness wiring prose so log-tick's new duration/harness WARNINGs never fire on a correctly-wired tick (SPEC-DRAFT-spec-token-capture-canary Spec-AC-03); the edit is inside TEST-010's live .aai/*.prompt.md glob, measured growth 912 B (25941 -> 26853), credited 1:1 to keep headroom unchanged at 636 within the 2048 cap"
  "-3021 prompt-dedup-canonical-includes RECLAIMED credit (NEGATIVE entry, DEBT-0002/SPEC-0059 reconciliation): trimming PLANNING step 10's ceremony-level paraphrase to a WORKFLOW.md pointer + reducing VALIDATION's AC STATUS GATE Rules 1/2/4-format to a docs-audit.mjs --gate <ref> invocation (Rules 3/4-anti-cheat retained as prose, script does not compute them) + collapsing the D5 subagent-mode metrics/append-run boilerplate in PLANNING/IMPLEMENTATION/VALIDATION/REMEDIATION/SKILL_TDD to a pointer at the new .aai/ROLE_COMMON.md shrank the live .aai/*.prompt.md glob by a measured 4687 B (349697 -> 345010); .aai/ROLE_COMMON.md (1666 B) is added to TEST-010's extra accounting to neutralize the relocation, leaving a genuine 3021 B reduction (4687 minus 1666) that would otherwise push headroom from 636 to 3657, breaching HEADROOM_CAP=2048; this entry retires exactly that 3021 B of credit so headroom lands back at 636 within the cap (per TEST-010's own remediation message: the corpus legitimately shrank below the credit, so LOWER JUSTIFIED_GROWTH_BYTES)"
  "-9573 decapod-prune RECLAIMED credit (NEGATIVE entry, CHANGE-0077): deleting the dead .aai/SKILL_DECAPOD.prompt.md (9571 B file; retired 9573 B = 9571 B file + 2 B residual slack from the SPEC-0099 SKILL_CHECK_STATE reword credited at 286 but measuring 284; external decapod CLI never shipped, zero consumers since 2026-03 — skill-sweep group C evidence) shrank the live .aai/*.prompt.md glob accordingly; without reconciliation headroom jumps 636 -> 10209, breaching HEADROOM_CAP=2048; this entry retires exactly 9573 B of credit so headroom lands back at 636 within the cap (per TEST-010 remediation guidance: the corpus legitimately shrank below the credit, so LOWER JUSTIFIED_GROWTH_BYTES)"
  "992 pr-post-open-review-sweep SKILL_PR.prompt.md new step 5d POST-OPEN REVIEW SWEEP (operator-directed 2026-07-26): after gh pr create, poll bot inline comments post-CI (gh api pulls/<n>/comments + reviews); any findings route through the canonical EXTERNAL-REVIEW RESPONSE flow in SKILL_CODE_REVIEW.prompt.md (triage real/stale/duplicate/disputed, RED-proofed regression per real code finding, inline reply per thread — Codex P2 review on PR #160 replaced the original lighter duplicated triage path with this delegation, +97 B over the initial 895 B); wait for the CI re-run + one repeat sweep before any merge-readiness claim; merge boundary unchanged — promotes the PR #158/#159 review-response discipline (7+3 real bot findings fixed) from session memory to canon; measured deficit 356 B after consuming the prior 636 B headroom, credited at the true +992 B growth, headroom back to 636 within the 2048 cap"
  "32 subagent-protocol-slim SKILL_LOOP.prompt.md line-18 clause fix (code-review non-blocking finding disposition, review-20260726T184739Z): the AUTHORITATIVE SOURCES bullet no longer credits SUBAGENT_PROTOCOL.md with the result-block format (relocated to .aai/SUBAGENT_CONTRACT.md by CHANGE-0061) — reworded to name both files honestly; measured +32 B in the TEST-010 glob, credited at the true +32 B growth, headroom 636 -> 636 net across the CHANGE-0061 scope (all other edits byte-neutral renames)"
  "1881 friction-capture-default-on thin FRICTION HOOK pointers naming .aai/system/FRICTION_PROTOCOL.md's new 'Deterministic hook points' subsection (default-on best-effort capture at the moments AAI-owned friction is most salient, RFC-0012 root-cause finding): VALIDATION.prompt.md step 5h canon-file gate/lint/CI failure + step 8 validation-FAIL-recorded (+629 B), REMEDIATION.prompt.md step 1/2 remediation-dispatched (+288 B), SKILL_PR.prompt.md step 5d CI-check-failure-handled (+307 B), SKILL_WRAP_UP.prompt.md step 6 non-empty-spool triage + proposed-intake surfacing (+657 B) — the seam body itself lives in FRICTION_PROTOCOL.md (system/, not corpus, no ledger cost); measured deficit 1245 B after consuming the prior 636 B headroom, credited at the true +1881 B growth, headroom back to 636 within the 2048 cap"
  "453 friction-capture-default-on-r2 IMPLEMENTATION.prompt.md FRICTION HOOK (canon-surface check failure during implementation, default-on) — validation residual-risk R2 remediation: the ride's own motivating case (prompt-diet headroom-cap trap) fired during IMPLEMENTATION where no hook existed, so the class stayed uncaptured; thin pointer mirrors the VALIDATION 5h wording, swallow-and-never-mask contract unchanged; measured +453 B, credited at the true +453 B growth, headroom unchanged within the 2048 cap"
  "755 learned-append-gate SKILL_WRAP_UP.prompt.md step 3 PROPOSE NEW LEARNED RULES rewrite (confirmed rule now routes through a compact critic pass THEN the structural gate node .aai/scripts/learned-append.mjs --source/--text — never a direct edit) + step 6 FRICTION FEEDBACK NUDGE one-line cross-reference back to step 3 (CHANGE learned-append-gate / spec-learned-append-gate); the edit is inside TEST-010's live .aai/*.prompt.md glob, measured growth 755 B (348368 -> 349123), credited 1:1 to keep headroom unchanged at 636 within the 2048 cap; FRICTION_PROTOCOL.md's new 'Learned-append gate' pointer section carries no ledger cost (system/, not corpus)"
  "131 prompt-hash-runtime-wiring SKILL_LOOP.prompt.md step 4 one-line pointer (Dispatch printed \`Prompt hash: <hex>\`? Pass the full hex as \`--prompt-hash\` on this role's append-run) closing the producer/consumer gap left by PR #170 (prompt-hash-telemetry); the edit is inside TEST-010's live .aai/*.prompt.md glob, measured growth 131 B (349123 -> 349254), credited 1:1 to keep headroom unchanged at 636 within the 2048 cap"
  "286 state-bootstrap-template SKILL_CHECK_STATE.prompt.md AUTHORITATIVE SCHEMA paragraph reworded to name the new tracked .aai/templates/STATE_TEMPLATE.yaml (not the gitignored docs/ai/STATE.yaml) as the canonical schema source, with a pin requiring the live file's header to match it verbatim (CHANGE-0074/spec-state-bootstrap-template); the edit is inside TEST-010's live .aai/*.prompt.md glob, measured growth 286 B (349254 -> 349540), credited 1:1 to keep headroom unchanged at 636 within the 2048 cap"
  "-7475 doctor-determinize RECLAIMED credit (NEGATIVE entry, CHANGE-0079): .aai/SKILL_DOCTOR.prompt.md rewritten from a 10697 B prose file (11 of 13 categories were file-existence/line-count/git-status prose the LLM re-derived by hand every run) to a 3163 B thin wrapper that runs the new deterministic .aai/scripts/aai-doctor.mjs and relays its output (CAT-11/CAT-13 keep calling docs-audit.mjs/layer-drift.mjs exactly as before, now from inside the script) shrank the live .aai/*.prompt.md glob by the measured 7534 B (339967 -> 332433); the new engine itself lives outside the glob (.aai/scripts/, no ledger cost); without reconciliation headroom would jump 636 -> 8170, breaching HEADROOM_CAP=2048; this entry retires exactly 7534 B of credit so headroom lands back at 636 within the cap (per TEST-010's own remediation message: the corpus legitimately shrank below the credit, so LOWER JUSTIFIED_GROWTH_BYTES)"
)
JUSTIFIED_GROWTH_BYTES=0
for _entry in "${JUSTIFIED_ADDITIONS[@]}"; do
  JUSTIFIED_GROWTH_BYTES=$(( JUSTIFIED_GROWTH_BYTES + ${_entry%% *} ))
done
unset _entry   # do not leak the loop scratch var into the sourcing shell
# Anti-bloat guard (TEST-002/Spec-AC-02): headroom must stay in
# [0, HEADROOM_CAP] so the credit cannot be padded arbitrarily and future
# UNJUSTIFIED prompt growth beyond the cap still fails this test (forcing a
# new itemized ledger line, or a shrink, instead of a silent absorption).
HEADROOM_CAP=2048

# Pure helpers factored out of TEST-010 (Spec-AC-02/SPEC-0059) so synthetic
# fixtures can drive them with SYNTHETIC inputs, proving the breach-deficit
# template and the cap-bite guard WITHOUT mutating the real
# JUSTIFIED_ADDITIONS ledger or reading the live corpus.

# compute_reduction_headroom <baseline> <after> <extra> <credit> <required>
# Mirrors TEST-010's exact formula; echoes "<reduction> <headroom>".
compute_reduction_headroom() {
  local baseline=$1 after=$2 extra=$3 credit=$4 required=$5
  local reduction=$(( baseline - after - extra + credit ))
  local headroom=$(( reduction - required ))
  echo "$reduction $headroom"
}

# justified_growth_breach_suggestion <reduction> <required>
# Computes the exact deficit and echoes a ready-to-paste ledger-entry line.
justified_growth_breach_suggestion() {
  local reduction=$1 required=$2
  local deficit=$(( required - reduction ))
  echo "JUSTIFIED_ADDITIONS+=( \"$deficit <REF-ID> <rationale>\" )"
}
