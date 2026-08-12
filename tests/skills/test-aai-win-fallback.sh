#!/usr/bin/env bash
#
# Test: Windows fallback wiring that lives OUTSIDE the Pester suite (SPEC-0046
# / ISSUE-0009, TEST-007, TEST-009, TEST-013).
#
#   - TEST-007 (Spec-AC-05): the MSYS-deterministic degraded branch in
#     .aai/scripts/aai-run-tests.sh. Branch SELECTION is injectable via an
#     AAI_UNAME override (used only when set), so it is unit-testable on this
#     macOS host without a real Git-Bash/MSYS environment. With AAI_UNAME
#     UNSET the chain must be byte-for-byte the current (pre-change) behavior
#     — this suite's own AAI_UNAME-unset assertions ARE that regression check.
#   - TEST-009 (Spec-AC-07): the 5-row supported-platform matrix is present,
#     with the same 5 concepts, in both wrapper headers AND docs/TECHNOLOGY.md.
#   - TEST-013 (Spec-AC-10): the Manual verification protocol section
#     (MV-1..MV-3) is documented in the frozen spec. Automated part checks
#     ONLY that the protocol is documented — MV-1..3 EXECUTION is manual,
#     off-host (real Windows), and is never claimed here.
#
# Usage:
#   bash tests/skills/test-aai-win-fallback.sh            # run all
#   bash tests/skills/test-aai-win-fallback.sh 007 009     # run only selected
#
# Exit codes:
#   0  - All selected tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-win-fallback"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_TESTS_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"
REAP_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-reap-tests.sh"
RUN_TESTS_PS1="$PROJECT_ROOT/.aai/scripts/aai-run-tests.ps1"
REAP_PS1="$PROJECT_ROOT/.aai/scripts/aai-reap-tests.ps1"
TECHNOLOGY_DOC="$PROJECT_ROOT/docs/TECHNOLOGY.md"
SPEC_DOC="$PROJECT_ROOT/docs/specs/SPEC-0046-spec-test-wrapper-windows-fallback.md"
USER_GUIDE_DOC="$PROJECT_ROOT/docs/USER_GUIDE.md"
CI_WORKFLOW="$PROJECT_ROOT/.github/workflows/ps1-quality.yml"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  [[ -f "$RUN_TESTS_SCRIPT" ]] || log_fail "missing $RUN_TESTS_SCRIPT"
  [[ -f "$REAP_SCRIPT" ]] || log_fail "missing $REAP_SCRIPT"
  [[ -f "$TECHNOLOGY_DOC" ]] || log_fail "missing $TECHNOLOGY_DOC"
  [[ -f "$SPEC_DOC" ]] || log_fail "missing $SPEC_DOC"
  log_pass "Dependencies checked"
}

# --- TEST-007 (Spec-AC-05): MSYS-deterministic degraded branch, injectable ---

test_007() {
  log_info "TEST-007: AAI_UNAME=MSYS_NT-10.0 -> degraded branch marker on stderr; unset -> current chain untouched..."

  local out rc

  # Baseline: AAI_UNAME unset -> no degraded marker, exit-code fidelity holds
  # exactly as before this change (regression tripwire for the untouched path).
  out="$(sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  echo "$out" | grep -q "AAI-DEGRADED-MODE" \
    && log_fail "degraded marker printed with AAI_UNAME unset (must be inert on macOS/Linux)"
  sh "$RUN_TESTS_SCRIPT" sh -c 'exit 7' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 7 ]] || log_fail "AAI_UNAME unset: exit-code fidelity broke (expected 7, got $rc)"

  # Forced MSYS: AAI_UNAME=MSYS_NT-10.0 -> exactly one degraded-mode marker on
  # stderr, naming the reason; exit-code fidelity still holds under the
  # degraded (bare-background) launch path.
  out="$(AAI_UNAME="MSYS_NT-10.0" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  local marker_count
  marker_count="$(echo "$out" | grep -c "AAI-DEGRADED-MODE")"
  [[ "$marker_count" -eq 1 ]] \
    || log_fail "expected exactly one AAI-DEGRADED-MODE marker under AAI_UNAME=MSYS_NT-10.0, got $marker_count"
  echo "$out" | grep -qi "MSYS" || log_fail "degraded marker must name the detected MSYS/MINGW uname"

  AAI_UNAME="MSYS_NT-10.0" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 5' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "AAI_UNAME=MSYS_NT-10.0: exit-code fidelity broke (expected 5, got $rc)"

  # MINGW variant also selects the degraded branch.
  out="$(AAI_UNAME="MINGW64_NT-10.0" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  echo "$out" | grep -q "AAI-DEGRADED-MODE" \
    || log_fail "AAI_UNAME=MINGW64_NT-10.0 must also select the degraded branch"

  # A non-Windows-shaped AAI_UNAME override (e.g. explicitly set to Linux) must
  # NOT force the degraded branch — selection is uname-value-driven, not
  # merely override-presence-driven.
  out="$(AAI_UNAME="Linux" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  echo "$out" | grep -q "AAI-DEGRADED-MODE" \
    && log_fail "AAI_UNAME=Linux must NOT select the degraded branch"

  log_pass "MSYS-deterministic degraded branch selects on AAI_UNAME override; inert when unset (TEST-007)"
}

# --- TEST-009 (Spec-AC-07): 5-row platform matrix, both headers + TECHNOLOGY.md

test_009() {
  log_info "TEST-009: grep asserts — 5-row platform matrix present in both wrapper headers + TECHNOLOGY.md..."

  [[ -f "$RUN_TESTS_PS1" ]] || log_fail "missing $RUN_TESTS_PS1 (new Windows dispatcher)"
  [[ -f "$REAP_PS1" ]] || log_fail "missing $REAP_PS1 (new Windows reap dispatcher)"

  local doc
  for doc in "$RUN_TESTS_SCRIPT" "$REAP_SCRIPT" "$TECHNOLOGY_DOC"; do
    grep -qiE 'macOS' "$doc" || log_fail "$doc missing the macOS platform-matrix row"
    grep -qiE 'Linux' "$doc" || log_fail "$doc missing the Linux platform-matrix row"
    grep -qiE 'WSL' "$doc" || log_fail "$doc missing the Windows+WSL platform-matrix row"
    grep -qiE 'Git.?Bash' "$doc" || log_fail "$doc missing the Windows+Git-Bash-only platform-matrix row"
    grep -qiE 'neither|AAI-ENV-ERROR' "$doc" || log_fail "$doc missing the Windows-neither-available platform-matrix row"
  done

  log_pass "5-row platform matrix present in both wrapper headers and docs/TECHNOLOGY.md (TEST-009)"
}

# --- TEST-013 (Spec-AC-10): Manual verification protocol documented ----------

test_013() {
  log_info "TEST-013: MV-1..3 manual verification protocol section documented in the frozen spec (doc-presence only; execution is manual, off-host)..."

  grep -qF "## Manual verification protocol" "$SPEC_DOC" \
    || log_fail "SPEC-0046 must carry a '## Manual verification protocol' section"
  grep -qF "MV-1" "$SPEC_DOC" || log_fail "SPEC-0046 must document MV-1"
  grep -qF "MV-2" "$SPEC_DOC" || log_fail "SPEC-0046 must document MV-2"
  grep -qF "MV-3" "$SPEC_DOC" || log_fail "SPEC-0046 must document MV-3"
  grep -qiE "residual risk" "$SPEC_DOC" \
    || log_fail "SPEC-0046 must record the residual risk (Windows-host semantics unverified in this repo)"

  log_pass "Manual verification protocol section documented; execution remains off-host (TEST-013)"
}

# --- TEST-014 (CHANGE-0133 Spec-AC-05): ps1-quality windows-5_1 job carries a real-wrapper smoke step ---

test_014() {
  log_info "TEST-014: ps1-quality windows-5_1 job carries a real-wrapper smoke step (aai-run-tests.ps1, both engines, exit 3 + marker + no AAI-SPAWN-ERROR)..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  grep -qF "aai-run-tests.ps1" "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must name aai-run-tests.ps1 in a real-wrapper smoke step"
  grep -qiE "windows-5_1" "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must carry the windows-5_1 job"
  grep -qE 'shell:[[:space:]]*powershell' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must run a step under Windows PowerShell 5.1 (shell: powershell)"
  grep -qE 'shell:[[:space:]]*pwsh' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must run a step under pwsh 7 (shell: pwsh)"
  grep -qE '(-eq 3|exit 3)' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW smoke step must assert exit code 3"
  grep -qiE "AAI-SPAWN-ERROR" "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW smoke step must assert the absence of an AAI-SPAWN-ERROR line"
  log_pass "ps1-quality windows-5_1 job carries the real-wrapper smoke step (TEST-014)"
}

# --- TEST-015 (CHANGE-0133 Spec-AC-07): 124/125/78 exit-code contract documented consistently ---

test_015() {
  log_info "TEST-015: 124/125/78 exit-code contract documented consistently in both wrapper headers + TECHNOLOGY.md + USER_GUIDE.md; pre-existing 5-row matrix pins still pass..."
  local doc
  for doc in "$RUN_TESTS_PS1" "$RUN_TESTS_SCRIPT" "$TECHNOLOGY_DOC" "$USER_GUIDE_DOC"; do
    [[ -f "$doc" ]] || log_fail "missing $doc"
    grep -qE "124" "$doc" || log_fail "$doc missing the 124 (timeout of a RAN process) code"
    grep -qE "125" "$doc" || log_fail "$doc missing the 125 (spawn/infrastructure failure) code"
    grep -qE "78" "$doc" || log_fail "$doc missing the 78 (no usable interpreter) code"
  done
  # Re-run the pre-existing 5-row platform-matrix pins to prove editing the
  # header did not break them (SEAM-4).
  test_009
  log_pass "125 exit-code contract documented consistently across all four docs; 5-row matrix pins still pass (TEST-015)"
}

# --- TEST-016 (CHANGE-0134 Spec-AC-01): windows-5_1 runs the full Pester suite under both engines ---

test_016() {
  log_info "TEST-016: windows-5_1 job installs Pester per engine and runs Pester discovery over tests/skills under both shells, printing AAI-PESTER-VERSION/AAI-PESTER-ELAPSED, timeout-minutes 15, 600s ceiling asserted..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"

  grep -qE 'Import-Module[[:space:]]+Pester[[:space:]]+-MinimumVersion[[:space:]]+5\.0' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must Import-Module Pester -MinimumVersion 5.0 (fails below major 5, closing the 5.1 built-in 3.4.0 silent-bind trap)"

  # VF-3: -MinimumVersion 5.0 must appear in ALL SIX occurrences across BOTH
  # engines (per engine: Install-Module + Import-Module in the install-if-
  # missing step, plus the Import-Module in the full-suite discovery step) --
  # a single grep -q above is satisfied by any one of them, so a per-step drop
  # (e.g. VF-3's b1 mutation: remove it from one of the four/six occurrences)
  # must be caught by a floor on the total count, not existence alone.
  local minver_count
  minver_count="$(grep -cF -- '-MinimumVersion 5.0' "$CI_WORKFLOW")"
  [[ "$minver_count" -ge 6 ]] \
    || log_fail "$CI_WORKFLOW must assert -MinimumVersion 5.0 at least 6 times (3 per engine: install-step Install-Module + Import-Module, plus the discovery-step Import-Module), got $minver_count -- a per-step drop is no longer silent"

  grep -qF 'AAI-PESTER-VERSION' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must print an AAI-PESTER-VERSION line"
  grep -qF 'AAI-PESTER-ELAPSED' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must print an AAI-PESTER-ELAPSED line"
  grep -qF "cfg.Run.Path = 'tests/skills'" "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must discover the tests/skills DIRECTORY (not two hardcoded *.Tests.ps1 files), so a future Tests.ps1 file is picked up without a workflow edit"
  grep -qE 'timeout-minutes:[[:space:]]*15' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW Pester step(s) must carry timeout-minutes: 15"
  # VF-1: anchored on the trailing token boundary so a relaxation to 6000/60000
  # (still textually starting with "600") cannot slip through as a false match.
  grep -qE 'elapsed[[:space:]]*-gt[[:space:]]*600([^0-9]|$)' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must assert the 600s hard ceiling on measured Pester duration (exact '600' token, not a relaxed '6000')"

  # Per-engine Pester install-if-missing steps (5.1 needs TLS 1.2 + NuGet
  # provider bootstrap; each engine has its own CurrentUser module scope).
  grep -qF 'Tls12' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must force TLS 1.2 before installing Pester under Windows PowerShell 5.1"
  grep -qF 'NuGet' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must bootstrap the NuGet package provider under Windows PowerShell 5.1"

  # VF-2: the "both engines" claim is the central claim of AC-001 and must be
  # pinned on content that ONLY the two full-suite Pester run steps carry --
  # "shell: powershell" / "shell: pwsh" / a bare "Invoke-Pester" substring are
  # each also satisfied by the parse-check and real-wrapper smoke steps, so
  # deleting an ENTIRE engine's Pester run step left this pin green before.
  # Fix: pin the two step names verbatim (deleting either step removes its
  # name) AND require >= 2 Invoke-Pester invocations tied to those two step
  # bodies specifically (each full-suite step calls Invoke-Pester exactly
  # once with this configuration-object shape; no other step in the file
  # does), so a step deleted OR gutted while its name survives is still caught.
  grep -qF 'name: "Full Pester suite discovery under Windows PowerShell 5.1 (CHANGE-0134 Spec-AC-01/Spec-AC-02)"' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must carry the named 'Full Pester suite discovery under Windows PowerShell 5.1' step (5.1 engine Pester coverage deleted)"
  grep -qF 'name: "Full Pester suite discovery under pwsh 7 (CHANGE-0134 Spec-AC-01/Spec-AC-02)"' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must carry the named 'Full Pester suite discovery under pwsh 7' step (pwsh 7 engine Pester coverage deleted)"

  local invoke_pester_count
  invoke_pester_count="$(grep -cE 'Invoke-Pester[[:space:]]+-Configuration[[:space:]]+\$cfg' "$CI_WORKFLOW")"
  [[ "$invoke_pester_count" -ge 2 ]] \
    || log_fail "$CI_WORKFLOW must call 'Invoke-Pester -Configuration \$cfg' at least twice -- once per engine's full-suite discovery step -- got $invoke_pester_count"

  log_pass "windows-5_1 job installs Pester per engine and runs the full suite under both shells (TEST-016)"
}

# --- TEST-017 (CHANGE-0134 Spec-AC-02): host-specific tests skipped via one named, counted mechanism ---

test_017() {
  log_info "TEST-017: shared SkipOnWindows predicate dot-sourced at file scope, PosixOnly reasons, expected-skip-count declared once..."
  local skip_helper="$PROJECT_ROOT/tests/skills/lib/pester-host-skip.ps1"
  local win_dispatch="$PROJECT_ROOT/tests/skills/aai-win-dispatch.Tests.ps1"
  local update_tests="$PROJECT_ROOT/tests/skills/aai-update.Tests.ps1"

  [[ -f "$skip_helper" ]] || log_fail "missing $skip_helper"
  grep -qF 'function Test-IsWindowsHostFor' "$skip_helper" \
    || log_fail "$skip_helper must define Test-IsWindowsHostFor"

  local f
  local total_skip_lines=0
  for f in "$win_dispatch" "$update_tests"; do
    [[ -f "$f" ]] || log_fail "missing $f"

    # Dot-sourced at file/discovery scope: a top-level '. (Join-Path ...
    # pester-host-skip.ps1)' line OUTSIDE any BeforeAll block, and nowhere
    # else in the file as an ACTUAL dot-source (a second copy inside
    # BeforeAll would defeat the discovery-time -Skip: evaluation this scope
    # depends on). Matched on the dot-source SHAPE (a line starting with a
    # bare '.' operator), not a bare substring -- a path-only reference such
    # as '$script:SkipHelperPath = Join-Path ... pester-host-skip.ps1' is a
    # legitimate, unrelated use of the same filename and must not count.
    local dotsource_count
    dotsource_count="$(grep -cE "^[[:space:]]*\.[[:space:]].*lib/pester-host-skip\.ps1" "$f")"
    [[ "$dotsource_count" -eq 1 ]] \
      || log_fail "$f must dot-source lib/pester-host-skip.ps1 exactly once (got $dotsource_count)"

    local before_line dotsource_line
    before_line="$(grep -n '^BeforeAll' "$f" | head -n1 | cut -d: -f1)"
    dotsource_line="$(grep -nE "^[[:space:]]*\.[[:space:]].*lib/pester-host-skip\.ps1" "$f" | head -n1 | cut -d: -f1)"
    if [[ -n "$before_line" && -n "$dotsource_line" ]]; then
      [[ "$dotsource_line" -lt "$before_line" ]] \
        || log_fail "$f: the pester-host-skip.ps1 dot-source (line $dotsource_line) must precede the first BeforeAll block (line $before_line) -- file/discovery scope, never inside BeforeAll"
    fi

    grep -qE '\$script:SkipOnWindows[[:space:]]*=[[:space:]]*Test-IsWindowsHostFor' "$f" \
      || log_fail "$f must set \$script:SkipOnWindows = Test-IsWindowsHostFor ... at file scope"

    # Every -Skip:$script:SkipOnWindows It must carry the PosixOnly token with
    # a non-empty reason in its own description line.
    local skip_lines skip_count
    skip_lines="$(grep -nE "^\s*It[[:space:]]+'.*'[[:space:]]+-Skip:\\\$script:SkipOnWindows" "$f" || true)"
    if [[ -n "$skip_lines" ]]; then
      while IFS= read -r line; do
        echo "$line" | grep -qF 'PosixOnly' \
          || log_fail "$f: a -Skip:\$script:SkipOnWindows It is missing the PosixOnly token in its name: $line"
        echo "$line" | grep -qE 'PosixOnly:[[:space:]]*[^)'"'"']+' \
          || log_fail "$f: a -Skip:\$script:SkipOnWindows It carries PosixOnly with no non-empty reason: $line"
      done <<< "$skip_lines"
      skip_count="$(grep -cE "^\s*It[[:space:]]+'.*'[[:space:]]+-Skip:\\\$script:SkipOnWindows" "$f")"
      total_skip_lines=$((total_skip_lines + skip_count))
    fi
  done

  # The expected-skip-count constant is declared exactly once (job-level env
  # in the workflow), consumed identically by both engine run steps.
  local decl_count
  decl_count="$(grep -cF 'AAI_EXPECTED_WIN_SKIP_COUNT:' "$CI_WORKFLOW")"
  [[ "$decl_count" -eq 1 ]] \
    || log_fail "$CI_WORKFLOW must declare AAI_EXPECTED_WIN_SKIP_COUNT exactly once (got $decl_count), consumed by both engine steps"
  grep -qF 'AAI-WIN-SKIP' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must print one AAI-WIN-SKIP line per skipped test"

  # NB-1: pin the declared count to reality -- the number of
  # -Skip:$script:SkipOnWindows It lines actually present across both files
  # must equal the workflow's declared AAI_EXPECTED_WIN_SKIP_COUNT, so a fifth
  # skip added without bumping the workflow constant fails here (a bash
  # suite, seconds) instead of ~10+ minutes into the real Windows job.
  local workflow_count
  workflow_count="$(grep -oE 'AAI_EXPECTED_WIN_SKIP_COUNT:[[:space:]]*"?[0-9]+' "$CI_WORKFLOW" | grep -oE '[0-9]+$')"
  [[ -n "$workflow_count" ]] \
    || log_fail "$CI_WORKFLOW: could not parse an integer value out of the AAI_EXPECTED_WIN_SKIP_COUNT declaration"
  [[ "$total_skip_lines" -eq "$workflow_count" ]] \
    || log_fail "actual -Skip:\$script:SkipOnWindows It count ($total_skip_lines across $win_dispatch + $update_tests) != $CI_WORKFLOW's declared AAI_EXPECTED_WIN_SKIP_COUNT ($workflow_count) -- bump the workflow constant when adding/removing a PosixOnly skip"

  log_pass "shared SkipOnWindows predicate wired correctly; PosixOnly reasons present; expected-skip-count ($workflow_count) matches actual skip count (TEST-017)"
}

# --- TEST-018 (CHANGE-0134 Spec-AC-04): fast-iteration path documented ------

test_018() {
  log_info "TEST-018: gh workflow run ps1-quality.yml + workflow_dispatch documented in the product doc and workflow header; two-engine Pester coverage stated; stale Pester-on-Linux claim removed from TECHNOLOGY.md..."
  local product_doc="$PROJECT_ROOT/docs/product/windows-test-wrapper.md"
  [[ -f "$product_doc" ]] || log_fail "missing $product_doc"

  local f
  for f in "$product_doc" "$CI_WORKFLOW"; do
    grep -qF 'gh workflow run ps1-quality.yml' "$f" \
      || log_fail "$f missing the literal command 'gh workflow run ps1-quality.yml'"
    grep -qF 'workflow_dispatch' "$f" \
      || log_fail "$f missing the workflow_dispatch token"
  done

  for f in "$product_doc" "$CI_WORKFLOW" "$TECHNOLOGY_DOC"; do
    grep -qiE 'both engines|Windows PowerShell 5\.1.*pwsh|pwsh.*Windows PowerShell 5\.1' "$f" \
      || log_fail "$f must state the two-engine (Windows PowerShell 5.1 + pwsh 7) Pester coverage"
  done

  grep -qiE 'Pester on Linux' "$TECHNOLOGY_DOC" \
    && log_fail "$TECHNOLOGY_DOC still carries the stale 'Pester on Linux' (only) claim"

  log_pass "fast-iteration path (workflow_dispatch / gh workflow run) and two-engine Pester coverage documented; stale claim removed (TEST-018)"
}

ALL_TESTS="007 009 013 014 015 016 017 018"

main() {
  echo "Testing $TEST_NAME (Windows fallback: MSYS branch, platform matrix, MV protocol doc-presence)"
  check_deps
  local selected="$*"
  [[ -n "$selected" ]] || selected="$ALL_TESTS"
  local t
  for t in $selected; do
    t="${t#TEST-}"
    "test_${t}"
  done
  echo ""
  log_pass "All selected $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
