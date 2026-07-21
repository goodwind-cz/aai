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
  "4848 hitl-decision-propagation SKILL_HITL.prompt.md STEP 4c trigger->target mapping table + normalization table + fail-closed rule + write-ordering rule (replacing the old absolute STATE-field prohibition) + ORCHESTRATION_HITL.prompt.md [HITL-<n>] blocking_reason stamping prose (SPEC-DRAFT-spec-hitl-decision-propagation); measured deficit 4848 B, credit chosen 4848 B for 0 B headroom"
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
