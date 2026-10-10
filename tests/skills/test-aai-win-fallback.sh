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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
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
  assert_payload_not_contains "$out" "AAI-DEGRADED-MODE" "degraded marker printed with AAI_UNAME unset (must be inert on macOS/Linux)"
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
  assert_payload_contains_i "$out" "MSYS" "degraded marker must name the detected MSYS/MINGW uname"

  AAI_UNAME="MSYS_NT-10.0" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 5' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "AAI_UNAME=MSYS_NT-10.0: exit-code fidelity broke (expected 5, got $rc)"

  # MINGW variant also selects the degraded branch.
  out="$(AAI_UNAME="MINGW64_NT-10.0" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  assert_payload_contains "$out" "AAI-DEGRADED-MODE" "AAI_UNAME=MINGW64_NT-10.0 must also select the degraded branch"

  # A non-Windows-shaped AAI_UNAME override (e.g. explicitly set to Linux) must
  # NOT force the degraded branch — selection is uname-value-driven, not
  # merely override-presence-driven.
  out="$(AAI_UNAME="Linux" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  assert_payload_not_contains "$out" "AAI-DEGRADED-MODE" "AAI_UNAME=Linux must NOT select the degraded branch"

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
    before_line="$(grep -n '^BeforeAll' "$f" | qhead -n1 | cut -d: -f1)"
    dotsource_line="$(grep -nE "^[[:space:]]*\.[[:space:]].*lib/pester-host-skip\.ps1" "$f" | qhead -n1 | cut -d: -f1)"
    if [[ -n "$before_line" && -n "$dotsource_line" ]]; then
      [[ "$dotsource_line" -lt "$before_line" ]] \
        || log_fail "$f: the pester-host-skip.ps1 dot-source (line $dotsource_line) must precede the first BeforeAll block (line $before_line) -- file/discovery scope, never inside BeforeAll"
    fi

    grep -qE '\$script:SkipOnWindows[[:space:]]*=[[:space:]]*Test-IsWindowsHostFor' "$f" \
      || log_fail "$f must set \$script:SkipOnWindows = Test-IsWindowsHostFor ... at file scope"

    # Every -Skip:$script:SkipOnWindows It must carry the PosixOnly token with
    # a non-empty reason in its own description line.
    local skip_lines skip_count
    skip_lines="$(grep -nE "^[[:space:]]*It[[:space:]]+'.*'[[:space:]]+-Skip:\\\$script:SkipOnWindows" "$f" || true)"
    if [[ -n "$skip_lines" ]]; then
      while IFS= read -r line; do
        assert_payload_contains "$line" "PosixOnly" "$f: a -Skip:\$script:SkipOnWindows It is missing the PosixOnly token in its name: $line"
        assert_payload_line_matches "$line" 'PosixOnly:[[:space:]]*[^)'"'"']+' \
          "$f: a -Skip:\$script:SkipOnWindows It carries PosixOnly with no non-empty reason: $line"
      done <<< "$skip_lines"
      skip_count="$(grep -cE "^[[:space:]]*It[[:space:]]+'.*'[[:space:]]+-Skip:\\\$script:SkipOnWindows" "$f")"
      total_skip_lines=$((total_skip_lines + skip_count))
    fi
  done

  # The expected-skip-count constant is declared exactly once (WORKFLOW-level
  # env since CHANGE-0136 — it moved up from windows-5_1's job level so BOTH
  # windows jobs consume the one declaration), asserted identically by every
  # engine run step.
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

# --- CHANGE-0136 helpers: job/step block extraction --------------------------

# Prints the body of one top-level job (2-space-indented key) from the
# ps1-quality workflow, from its key line up to (exclusive) the next job key.
get_job_block() {
  local job_key="$1"
  awk -v job="$job_key" '
    $0 ~ ("^  " job ":") { f = 1; print; next }
    f && /^  [A-Za-z0-9_-]+:/ { f = 0 }
    f { print }
  ' "$CI_WORKFLOW"
}

# Prints the body of one step (6-space-indented "- name:" entry) from the
# workflow, from its verbatim name line up to (exclusive) the next step.
get_step_block() {
  local step_name="$1"
  awk -v name="$step_name" '
    index($0, name) > 0 && $0 ~ /^      - name:/ { f = 1; print; next }
    f && /^      - name:/ { f = 0 }
    f { print }
  ' "$CI_WORKFLOW"
}

# --- TEST-019 (CHANGE-0136 Spec-AC-01): windows-wsl1 job shape ---------------

test_019() {
  log_info "TEST-019: windows-wsl1 job installs WSL1 Debian via major-pinned Vampire/setup-wsl, control-asserts sentinel 42 + VERSION 1 + wslpath /mnt/c, proves AAI-BRANCH: WSL on a real wrapper invocation, and asserts the three doctor CAT-14 arms (3/124/125) plus CAT-15 wsl functional..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"

  local job
  job="$(get_job_block "windows-wsl1")"
  [[ -n "$job" ]] || log_fail "$CI_WORKFLOW must carry a windows-wsl1 job (functional-WSL leg)"

  # D1: install mechanism — Vampire/setup-wsl pinned by MAJOR tag, WSL1, Debian.
  grep -qE 'uses:[[:space:]]*Vampire/setup-wsl@v[0-9]+' <<<"$job" \
    || log_fail "windows-wsl1 must use Vampire/setup-wsl pinned by major tag (@vN)"
  grep -qE 'wsl-version:[[:space:]]*1([^0-9]|$)' <<<"$job" \
    || log_fail "windows-wsl1 setup-wsl step must request wsl-version: 1 (WSL1 — hosted runners cannot run WSL2)"
  grep -qE 'distribution:[[:space:]]*Debian' <<<"$job" \
    || log_fail "windows-wsl1 setup-wsl step must install the Debian distribution (D1: GNU userland, not busybox)"

  # D1 controls: functional sentinel (Test-WslUsable's own semantics), genuine
  # VERSION 1, and the wslpath /mnt/c translation.
  grep -qF 'exit 42' <<<"$job" \
    || log_fail "windows-wsl1 control step must run the exit-42 functional sentinel (wsl.exe -e sh -c \"exit 42\")"
  grep -qE '\-ne 42|\-eq 42' <<<"$job" \
    || log_fail "windows-wsl1 control step must assert the sentinel exit code is exactly 42"
  grep -qE 'wsl\.exe -l -v|wsl -l -v' <<<"$job" \
    || log_fail "windows-wsl1 control step must run wsl -l -v to assert the distro is genuinely VERSION 1"
  grep -qF 'wslpath -a' <<<"$job" \
    || log_fail "windows-wsl1 control step must run wslpath -a (the marker-translation seam control)"
  grep -qF '/mnt/c' <<<"$job" \
    || log_fail "windows-wsl1 wslpath control must assert a path beginning /mnt/c"

  # Routing proof: one REAL wrapper invocation, OS-handle stream capture,
  # asserting the AAI-BRANCH: WSL stderr line.
  grep -qF 'aai-run-tests.ps1' <<<"$job" \
    || log_fail "windows-wsl1 must invoke the real aai-run-tests.ps1 wrapper"
  grep -qF 'RedirectStandardError' <<<"$job" \
    || log_fail "windows-wsl1 wrapper invocation must capture stderr at the OS-handle level (Start-Process -RedirectStandardError) — [Console]::Error is invisible to in-process 2>"
  grep -qF 'AAI-BRANCH:\s*WSL' <<<"$job" \
    || log_fail "windows-wsl1 must assert the AAI-BRANCH: WSL routing line on the wrapper's captured stderr"

  # Selftest reuse (SPEC-0122 D1): the vendored selftest via the doctor,
  # per-arm assertions with WSL semantics.
  grep -qF 'aai-doctor.mjs' <<<"$job" \
    || log_fail "windows-wsl1 must run node .aai/scripts/aai-doctor.mjs (vendored selftest reuse, never a third smoke implementation)"
  grep -qF -- <<<"$job" '--json' \
    || log_fail "windows-wsl1 doctor step must use --json (structured per-arm assertions)"
  local arm
  for arm in success timeout spawnfail; do
    grep -qF "'$arm'" <<<"$job" \
      || log_fail "windows-wsl1 doctor step must assert the CAT-14 '$arm' arm by name"
  done
  grep -qE '\-ne 3([^0-9]|$)' <<<"$job" \
    || log_fail "windows-wsl1 doctor step must assert the success arm exit code 3"
  grep -qE '\-ne 124([^0-9]|$)' <<<"$job" \
    || log_fail "windows-wsl1 doctor step must assert the timeout arm exit code 124"
  grep -qE '\-ne 125([^0-9]|$)' <<<"$job" \
    || log_fail "windows-wsl1 doctor step must assert the spawnfail arm exit code 125"
  grep -qF 'CAT-15' <<<"$job" \
    || log_fail "windows-wsl1 doctor step must assert CAT-15 (Windows Environment)"
  grep -qF 'functional' <<<"$job" \
    || log_fail "windows-wsl1 doctor step must assert the CAT-15 wsl tri-state is 'functional'"

  log_pass "windows-wsl1 job shape: pinned setup-wsl, three non-vacuous controls, live WSL routing + selftest arm assertions (TEST-019)"
}

# --- TEST-020 (CHANGE-0136 Spec-AC-02): WSL-leg Pester discipline + workflow-level skip count ---

test_020() {
  log_info "TEST-020: windows-wsl1 runs the full 5.1 Pester discovery with the identical floor/ceiling/skip discipline; AAI_EXPECTED_WIN_SKIP_COUNT sits at WORKFLOW level (before jobs:); test_017's pins still hold..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"

  local job
  job="$(get_job_block "windows-wsl1")"
  [[ -n "$job" ]] || log_fail "$CI_WORKFLOW must carry a windows-wsl1 job"

  grep -qF "cfg.Run.Path = 'tests/skills'" <<<"$job" \
    || log_fail "windows-wsl1 Pester step must discover the tests/skills DIRECTORY (same discovery as the other legs)"
  grep -qE 'shell:[[:space:]]*powershell([[:space:]]|$)' <<<"$job" \
    || log_fail "windows-wsl1 Pester step must run under Windows PowerShell 5.1 (shell: powershell) — D2: one engine, the field one"
  grep -qE 'timeout-minutes:[[:space:]]*15' <<<"$job" \
    || log_fail "windows-wsl1 Pester step must carry timeout-minutes: 15 like the existing legs"
  grep -qE 'TotalCount[[:space:]]*-lt[[:space:]]*111' <<<"$job" \
    || log_fail "windows-wsl1 Pester step must assert the TotalCount floor of 111"
  grep -qE 'elapsed[[:space:]]*-gt[[:space:]]*600([^0-9]|$)' <<<"$job" \
    || log_fail "windows-wsl1 Pester step must assert the 600s hard ceiling"
  grep -qF 'AAI-WIN-SKIP' <<<"$job" \
    || log_fail "windows-wsl1 Pester step must print one AAI-WIN-SKIP line per skipped test (two-direction reconciliation)"
  grep -qF 'Invoke-Pester -Configuration $cfg' <<<"$job" \
    || log_fail "windows-wsl1 Pester step must call Invoke-Pester -Configuration \$cfg"
  grep -qF 'FailedContainersCount' <<<"$job" \
    || log_fail "windows-wsl1 Pester step must assert FailedContainersCount (discovery-failure detection)"

  # SEAM-3: the single declaration now feeds TWO consumer jobs, so it must sit
  # at WORKFLOW level — i.e. BEFORE the jobs: key.
  local decl_line jobs_line
  decl_line="$(grep -nF 'AAI_EXPECTED_WIN_SKIP_COUNT:' "$CI_WORKFLOW" | qhead -n1 | cut -d: -f1)"
  jobs_line="$(grep -nE '^jobs:' "$CI_WORKFLOW" | qhead -n1 | cut -d: -f1)"
  [[ -n "$decl_line" ]] || log_fail "$CI_WORKFLOW must declare AAI_EXPECTED_WIN_SKIP_COUNT"
  [[ -n "$jobs_line" ]] || log_fail "$CI_WORKFLOW must carry a top-level jobs: key"
  [[ "$decl_line" -lt "$jobs_line" ]] \
    || log_fail "AAI_EXPECTED_WIN_SKIP_COUNT (line $decl_line) must be declared at WORKFLOW level, before jobs: (line $jobs_line) — both windows jobs consume the single declaration"

  # test_017's declared-exactly-once and count-equals-actual pins must keep
  # holding across the move (SEAM-3).
  test_017

  log_pass "windows-wsl1 Pester discipline identical to the existing leg; skip-count declaration at workflow level, still declared once (TEST-020)"
}

# --- TEST-021 (CHANGE-0136 Spec-AC-03): 5.1-only doctored-child step in windows-5_1 ---

test_021() {
  log_info "TEST-021: windows-5_1 carries the 5.1-only doctored-child step — undoctored-parent pwsh control, child-side must-not-resolve control with distinct exit code, Resolve-SelfTestEngine -> powershell, CAT-14 arms PASS, and no host mutation..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"

  local step_name='5.1-only fallback proof in a doctored child (CHANGE-0136 Spec-AC-03)'
  local job step
  job="$(get_job_block "windows-5_1")"
  [[ -n "$job" ]] || log_fail "$CI_WORKFLOW must carry the windows-5_1 job"
  grep -qF "$step_name" <<<"$job" \
    || log_fail "the windows-5_1 job must carry the step named '$step_name'"

  step="$(get_step_block "$step_name")"
  [[ -n "$step" ]] || log_fail "could not extract the '$step_name' step body"

  # Control, direction 1: pwsh IS resolvable in the undoctored parent (the
  # hiding check below can never pass vacuously).
  grep -qiE 'undoctored' <<<"$step" \
    || log_fail "the 5.1-only step must control-assert pwsh IS resolvable in the undoctored parent first"
  grep -qF 'pwsh.exe' <<<"$step" \
    || log_fail "the 5.1-only step must filter PATH by directories containing pwsh.exe (surgical filter, D3)"

  # Control, direction 2: inside the doctored child, Get-Command pwsh must
  # resolve NOTHING, with a distinct loud exit code.
  grep -qF 'Get-Command pwsh' <<<"$step" \
    || log_fail "the doctored child must control-assert Get-Command pwsh resolves nothing"
  grep -qF 'exit 97' <<<"$step" \
    || log_fail "the child-side hiding control must fail with a DISTINCT exit code (97) if pwsh still resolves — the hiding silently breaking is a named failure"

  # The real fallback proofs.
  grep -qF 'aai-win-selftest.ps1' <<<"$step" \
    || log_fail "the doctored child must dot-source aai-win-selftest.ps1 for Resolve-SelfTestEngine"
  grep -qF 'Resolve-SelfTestEngine' <<<"$step" \
    || log_fail "the doctored child must assert Resolve-SelfTestEngine returns powershell"
  grep -qF "'powershell'" <<<"$step" \
    || log_fail "the Resolve-SelfTestEngine assertion must compare against 'powershell'"
  grep -qF 'aai-doctor.mjs' <<<"$step" \
    || log_fail "the doctored child must run node .aai/scripts/aai-doctor.mjs (doctor's own engine pick under the doctored PATH)"
  grep -qF -- <<<"$step" '--json' \
    || log_fail "the doctored-child doctor run must use --json"
  grep -qF 'CAT-14' <<<"$step" \
    || log_fail "the step must assert the CAT-14 arms from the doctored-context doctor run"
  grep -qF 'PASS' <<<"$step" \
    || log_fail "the step must assert all three CAT-14 arms are PASS under powershell.exe"

  # Negative pin (D3): a doctored CHILD environment only — never a host
  # mutation. The step body must contain neither Move-Item nor Rename-Item.
  grep -qF 'Move-Item' <<<"$step" \
    && log_fail "the 5.1-only step must NOT contain Move-Item (host mutation forbidden — doctored CHILD environment only)"
  grep -qF 'Rename-Item' <<<"$step" \
    && log_fail "the 5.1-only step must NOT contain Rename-Item (host mutation forbidden — doctored CHILD environment only)"

  # OS-handle capture on the child spawn.
  grep -qF 'RedirectStandardError' <<<"$step" \
    || log_fail "the doctored child must be spawned with OS-handle stream capture (Start-Process -RedirectStandardError)"

  log_pass "5.1-only doctored-child step: both control directions, powershell fallback proven, no host mutation (TEST-021)"
}

# --- TEST-022 (CHANGE-0136 Spec-AC-04): weekly scheduled canary --------------

test_022() {
  log_info "TEST-022: ps1-quality declares the weekly UTC cron, a schedule-only canary run-name, and the product doc carries the canary sentence..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  local product_doc="$PROJECT_ROOT/docs/product/windows-test-wrapper.md"
  [[ -f "$product_doc" ]] || log_fail "missing $product_doc"

  grep -qF "cron: '0 5 * * 1'" "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must declare the weekly UTC cron '0 5 * * 1' (Mondays 05:00 UTC) under schedule:"
  grep -qE '^[[:space:]]*schedule:' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must declare a schedule: trigger"
  grep -qE '^run-name:' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW must declare a top-level run-name expression"
  grep -qF "github.event_name == 'schedule'" "$CI_WORKFLOW" \
    || log_fail "the run-name expression must condition on github.event_name == 'schedule' (canary named on schedule events ONLY)"
  grep -qiF 'canary' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW run-name must name the canary so a scheduled failure is distinguishable from PR noise"

  grep -qiF 'canary' "$product_doc" \
    || log_fail "$product_doc must carry the weekly-canary sentence (Spec-AC-04)"
  grep -qiE 'runner[- ]image|image drift' "$product_doc" \
    || log_fail "$product_doc canary sentence must state what a scheduled failure means (runner-image drift, not PR changes)"

  log_pass "weekly cron + schedule-only canary run-name declared; product doc carries the canary sentence (TEST-022)"
}

# --- TEST-023 (CHANGE-0136 Spec-AC-05): WSL1-vs-WSL2 honesty docs ------------

test_023() {
  log_info "TEST-023: WSL1-only coverage stated truthfully — workflow header (no nested virtualization), product doc (E_ACCESSDENIED field-only), TECHNOLOGY.md (WSL1 CI-verified, stale not-verified claim gone), CHANGELOG entry present..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  local product_doc="$PROJECT_ROOT/docs/product/windows-test-wrapper.md"
  local changelog="$PROJECT_ROOT/CHANGELOG.md"
  [[ -f "$product_doc" ]] || log_fail "missing $product_doc"
  [[ -f "$changelog" ]] || log_fail "missing $changelog"

  # Workflow header: hosted runners cannot run WSL2 — the leg proves WSL1 only.
  grep -qiF 'nested virtualization' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW header must state that GitHub-hosted runners cannot run WSL2 (no nested virtualization)"
  grep -qF 'WSL1' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW header must state the leg proves WSL1 only"
  grep -qF 'WSL2' "$CI_WORKFLOW" \
    || log_fail "$CI_WORKFLOW header must name the WSL2 limitation explicitly"

  # Product doc: WSL1-coverage caveat naming the E_ACCESSDENIED class.
  grep -qF 'WSL1' "$product_doc" \
    || log_fail "$product_doc must state the WSL1-coverage caveat"
  grep -qF 'E_ACCESSDENIED' "$product_doc" \
    || log_fail "$product_doc must name WSL2-specific failures such as the E_ACCESSDENIED class as remaining field-only"
  grep -qiE 'field[- ]only' "$product_doc" \
    || log_fail "$product_doc must state that WSL2-specific failures remain field-only"

  # TECHNOLOGY.md: the stale blanket not-verified-by-CI sentence is replaced
  # by the truthful WSL1-CI-verified statement; the matrix itself is pinned
  # byte-identical-in-concepts by test_009/test_015 (rerun by the full suite).
  grep -qF 'windows-wsl1' "$TECHNOLOGY_DOC" \
    || log_fail "$TECHNOLOGY_DOC must name the windows-wsl1 job as the CI proof of the WSL1 delegation path"
  grep -qiF 'CI-verified' "$TECHNOLOGY_DOC" \
    || log_fail "$TECHNOLOGY_DOC must state the WSL1 delegation path is CI-verified"
  grep -qF 'E_ACCESSDENIED' "$TECHNOLOGY_DOC" \
    || log_fail "$TECHNOLOGY_DOC must state WSL2-specific semantics (e.g. the E_ACCESSDENIED class) remain field/manual-only"
  grep -qF 'documented but NOT verified' "$TECHNOLOGY_DOC" \
    && log_fail "$TECHNOLOGY_DOC still carries the stale blanket 'documented but NOT verified by this repo's own CI' claim — false for the WSL1 delegation path after CHANGE-0136"

  # CHANGELOG: one own-heading entry for this scope. Accepts the rolled form
  # too — /aai-release legitimately moves '## [unreleased] — <title>' headings
  # into a '## [vYYYY.MM.DD...]' section at cut time (the v2026.08.13 release
  # rolled this entry; an unreleased-only pin rots at every release).
  grep -qE '^## \[(unreleased|v[0-9][^]]*)\].*CHANGE-0136' "$changelog" \
    || log_fail "$changelog must carry the CHANGE-0136 scope entry as its own '## [unreleased/vX] — <title>' heading"

  log_pass "WSL1-vs-WSL2 honesty stated in workflow header, product doc and TECHNOLOGY.md; CHANGELOG entry present (TEST-023)"
}

# =============================================================================
# CHANGE-0139 / spec-canonical-test-invocation — the canonical test-invocation
# contract: one allowlist-stable command shape per platform, wrapper never
# bypassed. Fixed literals and pinned sentences are defined in the frozen
# spec's "The contract" section and pinned verbatim here (grep -F, single
# lines, ASCII hyphens, no pipes).
# =============================================================================

# The two canonical repo-root literals (full shape as stated in guidance) and
# the two allowlist prefixes (what an operator approves once).
CANON_WIN_LITERAL='powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 <command...>'
CANON_POSIX_LITERAL='bash .aai/scripts/aai-run-tests.sh <command...>'
CANON_WIN_PREFIX='powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1'
CANON_POSIX_PREFIX='bash .aai/scripts/aai-run-tests.sh'
CANON_ROOT_RULE='Run it from the repository root; when elsewhere, cd to the repo root first - never rewrite the script path relative to the current directory.'
CANON_PROHIBITION='Never invoke bash.exe, sh, or wsl directly for test runs, and never via CWD-relative paths from a subdirectory - the dispatcher owns interpreter routing.'
CANON_RATIONALE='The fixed repo-root literal prefix is what approval allowlists match - a stable command shape is approved once, a varying one re-prompts forever.'

# --- TEST-024 (Spec-AC-01/02/03): guidance trio unchanged; prompt corpus is
#     Windows-safe — Windows .ps1 literal OR AGENTS.md Canonical test
#     invocation pointer; POSIX bash prefix never stands alone; SKILL_TDD
#     is in the pin list; bare-path residue still forbidden after BOTH
#     prefixes are stripped.
test_024() {
  log_info "TEST-024: TECHNOLOGY.md + TECHNOLOGY_TEMPLATE.md + AGENTS.md carry both canonical literals + repo-root rule + prohibition; listed skill prompts are Windows-safe (pair or AGENTS.md pointer, no bash-only, no bare .sh)..."

  local template_doc="$PROJECT_ROOT/.aai/templates/TECHNOLOGY_TEMPLATE.md"
  local agents_doc="$PROJECT_ROOT/.aai/AGENTS.md"
  [[ -f "$template_doc" ]] || log_fail "missing $template_doc"
  [[ -f "$agents_doc" ]] || log_fail "missing $agents_doc"

  local doc
  for doc in "$TECHNOLOGY_DOC" "$template_doc" "$agents_doc"; do
    grep -qF "$CANON_WIN_LITERAL" "$doc" \
      || log_fail "$doc missing the canonical Windows literal: $CANON_WIN_LITERAL"
    grep -qF "$CANON_POSIX_LITERAL" "$doc" \
      || log_fail "$doc missing the canonical POSIX literal: $CANON_POSIX_LITERAL"
    grep -qF "$CANON_ROOT_RULE" "$doc" \
      || log_fail "$doc missing the pinned repo-root sentence"
    grep -qF "$CANON_PROHIBITION" "$doc" \
      || log_fail "$doc missing the pinned prohibition sentence"
  done

  local pf
  local prompt_files=(
    "$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_VERIFY.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_TEST_SKILLS.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_BOOTSTRAP.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_DESLOP.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md"
    "$PROJECT_ROOT/.aai/system/DYNAMIC_SKILLS.md"
  )
  for pf in "${prompt_files[@]}"; do
    [[ -f "$pf" ]] || log_fail "missing $pf"
    local has_win=0 has_posix=0 has_pointer=0
    grep -qF -- "$CANON_WIN_PREFIX" "$pf" && has_win=1
    grep -qF -- "$CANON_POSIX_PREFIX" "$pf" && has_posix=1
    grep -qF -- 'Canonical test invocation' "$pf" && grep -qF -- '.aai/AGENTS.md' "$pf" && has_pointer=1
    [[ "$has_win" -eq 1 || "$has_pointer" -eq 1 ]] \
      || log_fail "TEST-024: $pf names neither the Windows canonical prefix nor an AGENTS.md Canonical test invocation pointer — a Windows agent following it would start with bash"
    if [[ "$has_posix" -eq 1 && "$has_win" -ne 1 ]]; then
      log_fail "TEST-024: $pf carries the POSIX bash prefix without the Windows .ps1 literal — bash-only is the WSL E_ACCESSDENIED footgun"
    fi
    local residue
    residue="$(sed -e "s|${CANON_POSIX_PREFIX}||g" -e "s|${CANON_WIN_PREFIX}||g" "$pf" | grep -nF -- '.aai/scripts/aai-run-tests.sh' || true)"
    [[ -z "$residue" ]] \
      || log_fail "TEST-024: $pf still carries a bare-path aai-run-tests.sh invocation mention after canonical-occurrence strip: $residue"
    # Pipe-free (pipe-grep-q-ratchet / assert-payload.sh): assert_payload_contains
    # is fail-closed on miss, so a skip-on-miss filter cannot call it. Use the
    # same primitives the helper wraps — `[[ =~ ]]` for the host `bash tests/`
    # ERE (one line, so REG_NEWLINE is not a trap) and `case` for the two
    # canonical-prefix substring skips (grep -qF).
    local bash_tests="" line
    local bash_tests_ere='(^|[[:space:]`])bash[[:space:]]+tests/'
    while IFS= read -r line; do
      [[ "$line" =~ $bash_tests_ere ]] || continue
      case "$line" in
        *"$CANON_POSIX_PREFIX"*) continue ;;
        *"$CANON_WIN_PREFIX"*) continue ;;
      esac
      bash_tests="${bash_tests}${line}"$'\n'
    done < "$pf"
    [[ -z "$bash_tests" ]] \
      || log_fail "TEST-024: $pf still tells a Windows agent to invoke bash on a tests/ path (WSL E_ACCESSDENIED footgun): $bash_tests"
  done

  log_pass "guidance trio unchanged; listed prompts are Windows-safe (pair or AGENTS.md pointer) (TEST-024)"
}

# --- TEST-025 (Spec-AC-01): wrapper Usage headers state the canonical shapes,
#     comment-only, ASCII-clean on the edited literal lines ------------------
test_025() {
  log_info "TEST-025: aai-run-tests.ps1 Usage header carries the canonical powershell literal (ASCII-clean lines); aai-run-tests.sh Usage header carries the bash-prefixed literal..."

  [[ -f "$RUN_TESTS_PS1" ]] || log_fail "missing $RUN_TESTS_PS1"
  grep -qF "$CANON_WIN_PREFIX" "$RUN_TESTS_PS1" \
    || log_fail "$RUN_TESTS_PS1 Usage header missing the canonical Windows literal prefix: $CANON_WIN_PREFIX"

  # ASCII-clean pin on the edited lines: every line carrying the canonical
  # Windows prefix must be pure printable ASCII (LC_ALL=C; no bytes >= 0x80).
  local lit_lines
  lit_lines="$(grep -F "$CANON_WIN_PREFIX" "$RUN_TESTS_PS1")"
  if LC_ALL=C grep -q '[^ -~]' <<<"$lit_lines"; then
    log_fail "$RUN_TESTS_PS1: a line carrying the canonical Windows literal contains non-ASCII bytes"
  fi

  grep -qF "$CANON_POSIX_PREFIX" "$RUN_TESTS_SCRIPT" \
    || log_fail "$RUN_TESTS_SCRIPT Usage header missing the canonical bash-prefixed literal: $CANON_POSIX_PREFIX"

  log_pass "both wrapper Usage headers state the canonical shapes; ps1 literal lines are ASCII-clean (TEST-025)"
}

# --- TEST-026 (Spec-AC-02/Spec-AC-05): allowlist rationale + USER_GUIDE
#     operator note + truthful product doc + CHANGELOG heading ---------------
test_026() {
  log_info "TEST-026: TECHNOLOGY.md rationale sentence; USER_GUIDE Leak-safe section names both prefixes + 'once'; product doc states the canonical Windows literal (no stale pwsh -File claim as THE way); CHANGELOG unreleased heading..."

  grep -qF "$CANON_RATIONALE" "$TECHNOLOGY_DOC" \
    || log_fail "$TECHNOLOGY_DOC missing the pinned allowlist-rationale sentence"

  # Operator note scoped to the Leak-safe test execution section.
  [[ -f "$USER_GUIDE_DOC" ]] || log_fail "missing $USER_GUIDE_DOC"
  local section
  section="$(awk '/^## Leak-safe test execution$/{f=1;next} f && /^## /{f=0} f' "$USER_GUIDE_DOC")"
  [[ -n "$section" ]] || log_fail "$USER_GUIDE_DOC missing the '## Leak-safe test execution' section"
  grep -qF "$CANON_WIN_PREFIX" <<<"$section" \
    || log_fail "$USER_GUIDE_DOC Leak-safe section missing the Windows allowlist prefix: $CANON_WIN_PREFIX"
  grep -qF "$CANON_POSIX_PREFIX" <<<"$section" \
    || log_fail "$USER_GUIDE_DOC Leak-safe section missing the POSIX allowlist prefix: $CANON_POSIX_PREFIX"
  grep -qiE 'allowlist' <<<"$section" \
    || log_fail "$USER_GUIDE_DOC Leak-safe section missing the allowlist operator note"
  grep -qiE 'once' <<<"$section" \
    || log_fail "$USER_GUIDE_DOC Leak-safe section must say the two prefixes are approved once"

  # Product doc: the canonical Windows literal is THE stated invocation; the
  # stale 'pwsh -File .aai/scripts/aai-run-tests.ps1' claim (pwsh does not
  # exist on 5.1-only corporate hosts) is gone; the allowlist stability
  # rationale is named.
  local product_doc="$PROJECT_ROOT/docs/product/windows-test-wrapper.md"
  [[ -f "$product_doc" ]] || log_fail "missing $product_doc"
  grep -qF "$CANON_WIN_PREFIX" "$product_doc" \
    || log_fail "$product_doc missing the canonical Windows invocation literal"
  grep -qF 'pwsh -File .aai/scripts/aai-run-tests.ps1' "$product_doc" \
    && log_fail "$product_doc still states the stale 'pwsh -File .aai/scripts/aai-run-tests.ps1' shape as THE invocation (pwsh is absent on 5.1-only hosts)"
  grep -qiE 'allowlist' "$product_doc" \
    || log_fail "$product_doc must name the allowlist-stability rationale"

  # CHANGELOG: this scope as its own '## [unreleased] — <title>' heading
  # entry. The rolled '## [vYYYY.MM.DD...]' form is accepted too, so this pin
  # does not rot when /aai-release later cuts the entry into a versioned
  # section (the exact rot test_023's CHANGE-0136 pin exhibited).
  local changelog="$PROJECT_ROOT/CHANGELOG.md"
  [[ -f "$changelog" ]] || log_fail "missing $changelog"
  grep -qE '^## \[(unreleased|v[0-9][^]]*)\].*CHANGE-0139' "$changelog" \
    || log_fail "$changelog must carry the CHANGE-0139 scope entry as its own '## [unreleased/vX] — <title>' heading"

  log_pass "allowlist rationale + operator note + truthful product doc + CHANGELOG heading (TEST-026)"
}

# TEST-028 gate (win-fallback-test028-red-on-bash-3): the execution arm needs
# command_not_found_handle (bash 4+). The major is read from the interpreter the
# wrapper will invoke (the bare word `bash` on PATH), never from this process.
win_fallback_invoked_bash_major() {
  bash -c 'printf %s "${BASH_VERSINFO[0]}"' 2>/dev/null || true
}

# Prints `skip` only for an all-digit major below 4; everything else (4+, empty,
# non-numeric) fails closed to `run`.
win_fallback_exec_arm_decision() {
  case "${1:-}" in
    ''|*[!0-9]*) printf 'run' ;;
    *) if [ "$1" -lt 4 ]; then printf 'skip'; else printf 'run'; fi ;;
  esac
}

test_028() {
  log_info "TEST-028: a Windows project Python path round-trips to Git Bash and a bash suite executes it (no helper command, so not exit 127)..."
  local lib="$PROJECT_ROOT/.aai/scripts/lib/git-bash-path.sh"
  [[ -f "$lib" ]] || log_fail "missing $lib"
  # shellcheck source=/dev/null
  . "$lib"
  local win='C:\proj\.venv\Scripts\python.exe'
  local gb
  gb="$(aai_to_git_bash_path "$win")"
  [[ "$gb" == "/c/proj/.venv/Scripts/python.exe" ]] || log_fail "git-bash path wrong: got '$gb'"
  local back
  back="$(aai_to_windows_path "$gb")"
  [[ "$back" == 'C:\proj\.venv\Scripts\python.exe' ]] || log_fail "windows path wrong: got '$back'"
  local slash
  slash="$(aai_to_git_bash_path 'C:/proj/.venv/Scripts/python.exe')"
  [[ "$slash" == "/c/proj/.venv/Scripts/python.exe" ]] || log_fail "C:/ spelling wrong: got '$slash'"
  # Non-paths stay put (the wrapper must not rewrite "sh" or "-c").
  [[ "$(aai_to_git_bash_path 'sh')" == "sh" ]] || log_fail "plain token was rewritten"

  local invoked_major
  invoked_major="$(win_fallback_invoked_bash_major)"
  if [[ "$(win_fallback_exec_arm_decision "$invoked_major")" == skip ]]; then
    echo "SKIP: TEST-028 execution arm: invoked bash is $invoked_major.x; bash older than 4 has no command_not_found_handle (Git Bash and CI run bash 5); translation asserts passed"
    return 0
  fi

  local root exe suite out rc
  root="$(mktemp -d "${TMPDIR:-/tmp}/aai-gb-root.XXXXXX")"
  mkdir -p "$root/c/proj/.venv/Scripts"
  exe="$root/c/proj/.venv/Scripts/python.exe"
  printf '#!/bin/sh\necho PYOK\n' > "$exe"
  chmod +x "$exe"
  suite="$(mktemp "${TMPDIR:-/tmp}/aai-gb-suite.XXXXXX")"
  cat > "$suite" <<'EOS'
#!/usr/bin/env bash
py='C:\proj\.venv\Scripts\python.exe'
out="$("$py")"
[ "$out" = "PYOK" ] || { echo "FAIL python path: got [$out]" >&2; exit 1; }
echo PASS
EOS
  chmod +x "$suite"
  out="$(AAI_UNAME="MSYS_NT-10.0" AAI_GIT_BASH_FS_ROOT="$root" bash "$RUN_TESTS_SCRIPT" bash "$suite" 2>&1)" && rc=0 || rc=$?
  rm -rf "$root" "$suite"
  [[ "$rc" -eq 0 ]] || log_fail "TEST-028: wrapper exit $rc (want 0, not 127): $out"
  assert_payload_contains "$out" "PASS" "TEST-028: sentinel python did not run: $out"
  log_pass "TEST-028 Windows Python path translated in-process and executed under Git Bash"
}

# --- TEST-004 / TEST-005 (ci-windows-leg-waits-and-ps1-path-filter Spec-AC-02): smoke harness measures the wrapper, not the orphan ---

# Prints the two Real-wrapper smoke step bodies, comment lines stripped, one
# engine per call: "5.1" or "pwsh7".
smoke_step_body() {
  local engine="$1" name
  case "$engine" in
    5.1)   name="Real-wrapper smoke: aai-run-tests.ps1 under Windows PowerShell 5.1" ;;
    pwsh7) name="Real-wrapper smoke: aai-run-tests.ps1 under pwsh 7" ;;
    *) return 2 ;;
  esac
  get_step_block "$name" | awk '$0 !~ /^[[:space:]]*#/'
}

test_032() {
  log_info "TEST-004 (test_032): both Real-wrapper smoke steps wait on the wrapper process only: no Start-Process wait-for-descendants flag, a bounded WaitForExit follows the spawn, and the timeout-arm bound is above the 2 s timeout and at most 30 s..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  local engine body spawn_ln wait_ln bound ceiling
  for engine in 5.1 pwsh7; do
    body="$(smoke_step_body "$engine")"
    [[ -n "$body" ]] || log_fail "TEST-004 (test_032): smoke step body for $engine not found"
    spawn_ln="$(awk '/\$p = Start-Process/ { print NR; exit }' <<<"$body")"
    [[ -n "$spawn_ln" ]] || log_fail "TEST-004 (test_032): $engine smoke arm has no '\$p = Start-Process' spawn line"
    if grep -qE '(^|[[:space:]])-Wait([[:space:]]|$)' <<<"$body"; then
      log_fail "TEST-004 (test_032): $engine smoke step still uses Start-Process -Wait (waits on the hang fixture's orphaned descendants, ~300 s)"
    fi
    grep -qF '$null = $p.Handle' <<<"$body" \
      || log_fail "TEST-004 (test_032): $engine smoke arm must cache \$p.Handle (5.1 ExitCode-null workaround once -Wait is gone)"
    wait_ln="$(awk -v s="$spawn_ln" 'index($0, "$p.WaitForExit($armCeilingSeconds * 1000)") && NR > s { print NR; exit }' <<<"$body")"
    [[ -n "$wait_ln" ]] || log_fail "TEST-004 (test_032): $engine smoke arm needs a bounded \$p.WaitForExit(\$armCeilingSeconds * 1000) AFTER the spawn line"
    ceiling="$(sed -n 's/^[[:space:]]*\$armCeilingSeconds = \([0-9][0-9]*\)[[:space:]]*$/\1/p' <<<"$body")"
    [[ -n "$ceiling" && "$ceiling" -ge 20 && "$ceiling" -le 120 ]] \
      || log_fail "TEST-004 (test_032): $engine smoke step must define \$armCeilingSeconds as a bare integer 20..120 (got '${ceiling:-none}')"
    bound="$(sed -n 's/^[[:space:]]*\$timeoutArmBoundSeconds = \([0-9][0-9]*\)[[:space:]]*$/\1/p' <<<"$body")"
    [[ -n "$bound" && "$bound" -gt 2 && "$bound" -le 30 ]] \
      || log_fail "TEST-004 (test_032): $engine smoke step must define \$timeoutArmBoundSeconds as a bare integer >2 and <=30 (got '${bound:-none}')"
    grep -qF 'taskkill /PID' <<<"$body" \
      || log_fail "TEST-004 (test_032): $engine smoke arm must force-stop the wrapper tree when the ceiling is hit"
  done
  log_pass "TEST-004 (test_032) both smoke steps wait on the wrapper only, bounded (ceiling and timeout-arm bound pinned)"
}

test_033() {
  log_info "TEST-005 (test_033): both smoke steps' timeout arm probes for surviving hang-fixture processes, fails on any, and asserts the started marker; the fixture-prep step writes the marker before sleep 300..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  local engine body
  for engine in 5.1 pwsh7; do
    body="$(smoke_step_body "$engine")"
    [[ -n "$body" ]] || log_fail "TEST-005 (test_033): smoke step body for $engine not found"
    grep -qF 'function Get-SmokeHangSurvivors' <<<"$body" \
      || log_fail "TEST-005 (test_033): $engine smoke step must define function Get-SmokeHangSurvivors"
    grep -qF 'Get-SmokeHangSurvivors -Token' <<<"$body" \
      || log_fail "TEST-005 (test_033): $engine timeout arm must call Get-SmokeHangSurvivors -Token"
    grep -qE 'FAIL timeout: .*surviv' <<<"$body" \
      || log_fail "TEST-005 (test_033): $engine timeout arm must turn a non-empty survivor result into a 'FAIL timeout:' line"
    grep -qF 'ParentProcessId' <<<"$body" \
      || log_fail "TEST-005 (test_033): $engine survivor FAIL line must name the survivor's ParentProcessId (H1 vs H2 diagnosis)"
    grep -qF 'AAI_SMOKE_HANG_MARKER' <<<"$body" \
      || log_fail "TEST-005 (test_033): $engine timeout arm must hand the fixture AAI_SMOKE_HANG_MARKER"
    grep -qE 'FAIL timeout: .*marker' <<<"$body" \
      || log_fail "TEST-005 (test_033): $engine timeout arm must FAIL when the started marker is missing (positive control)"
  done
  local prep fix
  prep="$(get_step_block "Prepare real-wrapper smoke fixtures")"
  fix="$(grep -F 'aai-smoke-hang.sh' <<<"$prep" | grep -F 'printf' || true)"
  [[ -n "$fix" ]] || log_fail "TEST-005 (test_033): fixture-prep step must printf the aai-smoke-hang.sh fixture"
  [[ "$fix" == *'AAI_SMOKE_HANG_MARKER'*'sleep 300'* ]] \
    || log_fail "TEST-005 (test_033): hang fixture must write the AAI_SMOKE_HANG_MARKER started marker BEFORE 'sleep 300': $fix"
  log_pass "TEST-005 (test_033) survivor probe + started-marker positive control wired in both smoke steps and the fixture"
}

# --- TEST-001 / TEST-002 / TEST-003 (ci-windows-leg-waits-and-ps1-path-filter Spec-AC-01): MSYS timeout reaps the child tree ---

# Runs the wrapper under a forced MSYS uname with a Windows-modelling
# `taskkill` PATH stub and an AAI_PROC_ROOT fixture, around a fixture command
# that hangs (leader sh + a `sleep 300` child). Sets globals: MK_RC,
# MK_ELAPSED, MK_LOG (stub call log), MK_LEADER (the leader's MSYS pid),
# MK_GC (the sleep child's pid), MK_DIR (scratch). Arg 1: "winpid" (the
# fixture writes its own proc winpid entry, MSYS pid + 100000) or "nowinpid"
# (AAI_PROC_ROOT stays empty). The stub models Windows: it refuses a
# non-forced call, only knows Windows pids the fixture registered, and for
# //T walks children by parent pid, so a leader killed first orphans its child.
msys_reap_run() {
  local mode="$1" t0
  MK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-msys-reap.XXXXXX")"
  [[ -n "$MK_DIR" && "$MK_DIR" = /* ]] || log_fail "msys_reap_run: scratch dir not absolute: '$MK_DIR'"
  mkdir -p "$MK_DIR/bin" "$MK_DIR/proc"
  MK_LOG="$MK_DIR/taskkill.log"
  : > "$MK_LOG"
  cat > "$MK_DIR/bin/taskkill" <<'EOS'
#!/bin/sh
echo "$*" >> "$MK_DIR/taskkill.log"
pid="" force=""
while [ $# -gt 0 ]; do
  case "$1" in
    //PID) pid="$2"; shift ;;
    //F) force=1 ;;
  esac
  shift
done
[ -f "$MK_DIR/win-$pid" ] || exit 128
real="$(cat "$MK_DIR/win-$pid")"
[ -n "$force" ] || { echo "ERROR: can only be terminated forcefully" >&2; exit 1; }
kill_tree() {
  for c in $(ps -A -o pid= -o ppid= | awk -v p="$1" '$2 == p { print $1 }'); do kill_tree "$c"; done
  kill -KILL "$1" 2>/dev/null
}
kill_tree "$real"
exit 0
EOS
  chmod +x "$MK_DIR/bin/taskkill"
  cat > "$MK_DIR/fixture.sh" <<'EOS'
#!/bin/sh
echo "$$" > "$MK_DIR/leader.pid"
if [ "$MK_MODE" = winpid ]; then
  mkdir -p "$AAI_PROC_ROOT/$$"
  echo "$(( $$ + 100000 ))" > "$AAI_PROC_ROOT/$$/winpid"
  echo "$$" > "$MK_DIR/win-$(( $$ + 100000 ))"
fi
sleep 300 &
echo "$!" > "$MK_DIR/gc.pid"
wait
EOS
  chmod +x "$MK_DIR/fixture.sh"
  t0="$(date +%s)"
  MK_DIR="$MK_DIR" MK_MODE="$mode" AAI_PROC_ROOT="$MK_DIR/proc" \
    AAI_UNAME="MINGW64_NT-10.0" AAI_TEST_TIMEOUT=2 PATH="$MK_DIR/bin:$PATH" \
    sh "$RUN_TESTS_SCRIPT" sh "$MK_DIR/fixture.sh" >"$MK_DIR/out.txt" 2>&1 < /dev/null
  MK_RC=$?
  MK_ELAPSED=$(( $(date +%s) - t0 ))
  MK_LEADER="$(cat "$MK_DIR/leader.pid" 2>/dev/null || true)"
  MK_GC="$(cat "$MK_DIR/gc.pid" 2>/dev/null || true)"
}

msys_reap_cleanup() {
  [[ -n "${MK_GC:-}" ]] && kill -KILL "$MK_GC" 2>/dev/null
  [[ -n "${MK_LEADER:-}" ]] && kill -KILL "$MK_LEADER" 2>/dev/null
  [[ -n "${MK_DIR:-}" && "$MK_DIR" = /* ]] && rm -rf "$MK_DIR"
  return 0
}

test_029() {
  log_info "TEST-001 (test_029): MSYS timeout aims the tree kill at the Windows pid from the proc winpid entry, never the raw MSYS pid..."
  msys_reap_run winpid
  local first calls
  first="$(sed -n '1p' "$MK_LOG")"
  calls="$(cat "$MK_LOG")"
  [[ -n "$MK_LEADER" ]] || { msys_reap_cleanup; log_fail "TEST-001 (test_029): fixture never started (positive control: no leader pid recorded)"; }
  if [[ "$first" != *"//PID $(( MK_LEADER + 100000 )) "* ]]; then
    msys_reap_cleanup
    log_fail "TEST-001 (test_029): first taskkill call must target the mapped Windows pid $(( MK_LEADER + 100000 )), got: '${first:-no call}'"
  fi
  if [[ "$calls" == *"//PID $MK_LEADER "* ]]; then
    msys_reap_cleanup
    log_fail "TEST-001 (test_029): a taskkill call carried the raw MSYS pid $MK_LEADER (wrong PID namespace)"
  fi
  msys_reap_cleanup
  log_pass "TEST-001 (test_029) taskkill targets the winpid-mapped Windows pid"
}

test_030() {
  log_info "TEST-002 (test_030): MSYS timeout does one forced tree kill first, so the fixture's grandchild sleep does not survive..."
  msys_reap_run winpid
  local first alive=1 i
  first="$(sed -n '1p' "$MK_LOG")"
  if [[ -z "$MK_GC" ]]; then
    msys_reap_cleanup
    log_fail "TEST-002 (test_030): fixture never started its grandchild (positive control: no gc pid recorded)"
  fi
  if [[ "$first" != *"//T"* || "$first" != *"//F"* ]]; then
    msys_reap_cleanup
    log_fail "TEST-002 (test_030): first taskkill call must carry //T and //F, got: '${first:-no call}'"
  fi
  [[ "$MK_RC" -eq 124 ]] || { msys_reap_cleanup; log_fail "TEST-002 (test_030): wrapper exit $MK_RC (want 124)"; }
  [[ "$MK_ELAPSED" -le 10 ]] || { msys_reap_cleanup; log_fail "TEST-002 (test_030): wrapper took ${MK_ELAPSED}s (want <= TIMEOUT+8 = 10)"; }
  # A killed grandchild that no one reaps stays a zombie (Z) in containers
  # whose PID 1 does not reap orphans; kill -0 still succeeds on it, so a
  # defunct process counts as killed (PR #442 review, Codex P2).
  local st
  for i in 1 2 3 4 5 6; do
    kill -0 "$MK_GC" 2>/dev/null || { alive=0; break; }
    st="$(ps -o stat= -p "$MK_GC" 2>/dev/null)" || st=""
    case "$st" in *Z*) alive=0; break ;; esac
    sleep 0.5
  done
  if [[ "$alive" -eq 1 ]]; then
    msys_reap_cleanup
    log_fail "TEST-002 (test_030): the grandchild sleep (pid $MK_GC) survived the timeout reap (orphaned by a leader-first kill)"
  fi
  msys_reap_cleanup
  log_pass "TEST-002 (test_030) forced tree kill first; grandchild reaped; exit 124 in ${MK_ELAPSED}s"
}

test_031() {
  log_info "TEST-003 (test_031): with no proc winpid entry the tree kill falls back to the MSYS pid itself (never empty) and the wrapper still exits 124..."
  msys_reap_run nowinpid
  local first
  first="$(sed -n '1p' "$MK_LOG")"
  if [[ -z "$MK_LEADER" ]]; then
    msys_reap_cleanup
    log_fail "TEST-003 (test_031): fixture never started (positive control: no leader pid recorded)"
  fi
  if [[ "$first" != *"//PID $MK_LEADER //T //F"* ]]; then
    msys_reap_cleanup
    log_fail "TEST-003 (test_031): first taskkill call must be a forced tree kill on the MSYS pid $MK_LEADER, got: '${first:-no call}'"
  fi
  if [[ "$MK_RC" -ne 124 ]]; then
    msys_reap_cleanup
    log_fail "TEST-003 (test_031): wrapper exit $MK_RC (want 124)"
  fi
  msys_reap_cleanup
  log_pass "TEST-003 (test_031) missing winpid degrades to the MSYS pid; exit 124"
}

# --- TEST-006..009 (Spec-AC-03/04): ps1-quality `paths:` filter derived from
# what PowerShell actually reads, and the windows-5_1 job-level bound ---------

# ps1f_derive <root> <tests-glob> -- prints, sorted, the name of every file in
# <root>/tests/skills/lib that the PowerShell side reads (D3): named as
# `lib/<name>` by a .aai/scripts/*.ps1, a <tests-glob> Pester file in
# tests/skills, a tests/skills/lib/*.ps1, test-ps1-quality.sh, or one hop out,
# a test-*.sh a Pester file names. No pipe into a quiet grep (pipefail).
ps1f_derive() {
  local root="$1" tglob="$2" libdir tok_file src_file hop f b h
  libdir="$root/tests/skills/lib"
  [[ -d "$libdir" ]] || return 0
  tok_file="$(mktemp "${TMPDIR:-/tmp}/ps1f-tok.XXXXXX")"
  src_file="$(mktemp "${TMPDIR:-/tmp}/ps1f-src.XXXXXX")"
  : >"$src_file"
  find "$root/.aai/scripts" -maxdepth 1 -name '*.ps1' -type f 2>/dev/null >>"$src_file"
  find "$root/tests/skills" -maxdepth 1 -name "$tglob" -type f 2>/dev/null >>"$src_file"
  find "$libdir" -maxdepth 1 -name '*.ps1' -type f 2>/dev/null >>"$src_file"
  [[ -f "$root/tests/skills/test-ps1-quality.sh" ]] && echo "$root/tests/skills/test-ps1-quality.sh" >>"$src_file"
  # one hop: bash suites a Pester file names
  find "$root/tests/skills" -maxdepth 1 -name "$tglob" -type f 2>/dev/null >"$tok_file"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    for h in $(grep -ohE 'test-[A-Za-z0-9_-]+\.sh' "$f" 2>/dev/null); do
      [[ -f "$root/tests/skills/$h" ]] && echo "$root/tests/skills/$h" >>"$src_file"
    done
  done <"$tok_file"
  : >"$tok_file"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    grep -ohE 'lib/[A-Za-z0-9_.-]+' "$f" 2>/dev/null >>"$tok_file"
  done <"$src_file"
  for f in "$libdir"/*; do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    if grep -qxF "lib/$b" "$tok_file" || grep -qxF "lib/$b." "$tok_file"; then
      echo "$b"
    fi
  done | sort
  rm -f "$tok_file" "$src_file"
}

# ps1f_list <event> -- the `paths:` entries of one `on:` event, unquoted.
ps1f_list() {
  awk -v ev="$1" '
    /^on:/ { on = 1; next }
    on && /^[^[:space:]#]/ { on = 0 }
    on && $0 ~ ("^  " ev ":") { cur = 1; inp = 0; next }
    on && /^  [A-Za-z_]+:/ { cur = 0; inp = 0 }
    cur && /^    paths:/ { inp = 1; next }
    cur && /^    [A-Za-z_-]+:/ { inp = 0 }
    inp && /^      - / { sub(/^      - /, ""); sub(/[[:space:]]*#.*$/, ""); print }
  ' "$CI_WORKFLOW" | sed "s/^'//; s/'\$//"
}

# ps1f_exempt -- "<name>|<reason>" for each well-formed exemption comment line.
ps1f_exempt() {
  local line re='^[[:space:]]*#[[:space:]]*ps1-paths-exempt:[[:space:]]+tests/skills/lib/([^[:space:]]+)[[:space:]]+--[[:space:]]*(.*)$'
  while IFS= read -r line; do
    if [[ "$line" =~ $re ]]; then echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}"; fi
  done <"$CI_WORKFLOW"
}

# ps1f_match <glob-entry> <path> -- GitHub path-glob semantics: `*` stays
# inside a segment, `**` crosses `/`.
ps1f_match() {
  local re
  re="$(printf '%s' "$1" | sed -e 's/[.+^$(){}|\\]/\\&/g' -e 's/\*\*/@@DS@@/g' -e 's/\*/[^\/]*/g' -e 's/@@DS@@/.*/g')"
  [[ "$2" =~ ^${re}$ ]]
}

# ps1f_is_dirwide <entry> -- a bare directory glob is not a derived entry.
ps1f_is_dirwide() {
  case "$1" in */\*\*|*/\*|\*\*) return 0 ;; esac
  return 1
}

# ps1f_uncovered <root> <tests-glob> -- prints each derived-set member that no
# non-directory-wide push entry matches and no well-formed exemption names;
# returns 1 when there is any.
ps1f_uncovered() {
  local root="$1" tglob="$2" name entry hit ex rc=0 exempt_names
  exempt_names="$(ps1f_exempt | cut -d'|' -f1)"
  for name in $(ps1f_derive "$root" "$tglob"); do
    hit=0
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      ps1f_is_dirwide "$entry" && continue
      if ps1f_match "$entry" "tests/skills/lib/$name"; then hit=1; break; fi
    done <<<"$(ps1f_list push)"
    if [[ "$hit" -eq 0 ]]; then
      ex=0
      case $'\n'"$exempt_names"$'\n' in *$'\n'"$name"$'\n'*) ex=1 ;; esac
      if [[ "$ex" -eq 0 ]]; then echo "$name"; rc=1; fi
    fi
  done
  return "$rc"
}

test_034() {
  log_info "TEST-006 (test_034): push and pull_request path lists are identical and cover every file the PowerShell side reads from tests/skills/lib, or carry a reasoned ps1-paths-exempt line..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  local push pr derived n missing ex_line ex_name ex_reason
  push="$(ps1f_list push)"
  pr="$(ps1f_list pull_request)"
  [[ -n "$push" ]] || log_fail "TEST-006 (test_034): no push paths list parsed (positive control)"
  [[ "$push" == "$pr" ]] || log_fail "TEST-006 (test_034): push and pull_request paths lists differ"
  derived="$(ps1f_derive "$PROJECT_ROOT" '*.Tests.ps1')"
  n="$(printf '%s\n' "$derived" | awk 'NF' | wc -l | tr -d ' ')"
  [[ "$n" -ge 4 ]] || log_fail "TEST-006 (test_034): derived set has $n members (want >= 4), the derivation is broken: $derived"
  [[ $'\n'"$derived"$'\n' == *$'\npester-host-skip.ps1\n'* ]] || log_fail "TEST-006 (test_034): derived set lacks pester-host-skip.ps1 (positive control)"
  [[ $'\n'"$derived"$'\n' == *$'\nassert-payload.sh\n'* ]] || log_fail "TEST-006 (test_034): derived set lacks assert-payload.sh (positive control)"
  missing="$(ps1f_uncovered "$PROJECT_ROOT" '*.Tests.ps1' || true)"
  [[ -z "$missing" ]] || log_fail "TEST-006 (test_034): PowerShell-read lib files neither matched by the push paths list nor exempted with a reason: $(printf '%s' "$missing" | tr '\n' ' ')"
  while IFS= read -r ex_line; do
    [[ -n "$ex_line" ]] || continue
    ex_name="${ex_line%%|*}"
    ex_reason="${ex_line#*|}"
    [[ $'\n'"$derived"$'\n' == *$'\n'"$ex_name"$'\n'* ]] || log_fail "TEST-006 (test_034): ps1-paths-exempt names $ex_name, which is not in the derived set"
    [[ -n "${ex_reason//[[:space:]]/}" ]] || log_fail "TEST-006 (test_034): ps1-paths-exempt for $ex_name has an empty reason"
  done <<<"$(ps1f_exempt)"
  log_pass "TEST-006 (test_034) lists identical; derived set ($n files) covered or reasoned-exempt"
}

test_035() {
  log_info "TEST-007 (test_035): the path lists match no tests/skills/lib file outside the derived set, match no exempt file, and carry no bare lib directory glob..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  local ev entry f name derived exempt
  derived="$(ps1f_derive "$PROJECT_ROOT" '*.Tests.ps1')"
  exempt="$(ps1f_exempt | cut -d'|' -f1)"
  for control in prompt-diet-ledger.sh cd-subshell-leak-baseline.tsv; do
    [[ -f "$PROJECT_ROOT/tests/skills/lib/$control" ]] || log_fail "TEST-007 (test_035): negative control $control no longer exists, re-pick it"
  done
  [[ $'\n'"$derived"$'\n' != *$'\ncd-subshell-leak-baseline.tsv\n'* ]] || log_fail "TEST-007 (test_035): cd-subshell-leak-baseline.tsv is in the derived set, the control is stale"
  for ev in push pull_request; do
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      case "$entry" in
        tests/skills/lib/\*\*|tests/skills/lib/\*|tests/skills/\*\*|tests/\*\*)
          log_fail "TEST-007 (test_035): $ev list carries the directory-wide glob '$entry'" ;;
      esac
      for f in "$PROJECT_ROOT"/tests/skills/lib/*; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        if ps1f_match "$entry" "tests/skills/lib/$name"; then
          [[ $'\n'"$derived"$'\n' == *$'\n'"$name"$'\n'* ]] \
            || log_fail "TEST-007 (test_035): $ev entry '$entry' matches $name, which PowerShell never reads"
          [[ $'\n'"$exempt"$'\n' != *$'\n'"$name"$'\n'* ]] \
            || log_fail "TEST-007 (test_035): $ev entry '$entry' matches $name, which a ps1-paths-exempt line exempts"
        fi
      done
    done <<<"$(ps1f_list "$ev")"
  done
  log_pass "TEST-007 (test_035) lists match only derived, non-exempt lib files"
}

test_036() {
  log_info "TEST-008 (test_036): a new lib data file read by a Pester test makes the derived-set check fail and name it..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  local scan_tests_glob='*.Tests.ps1'
  local scratch out rc
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/ps1f-fixture.XXXXXX")"
  [[ -n "$scratch" && "$scratch" = /* ]] || log_fail "TEST-008 (test_036): scratch dir not absolute"
  mkdir -p "$scratch/.aai/scripts" "$scratch/tests/skills/lib"
  : >"$scratch/tests/skills/lib/pester-host-skip.ps1"
  : >"$scratch/tests/skills/lib/unrelated-data.tsv"
  printf '%s\n' '. (Join-Path $PSScriptRoot "lib/pester-host-skip.ps1")' 'Get-Content (Join-Path $PSScriptRoot "lib/brand-new-fixture.tsv")' >"$scratch/tests/skills/fx.Tests.ps1"
  : >"$scratch/tests/skills/lib/brand-new-fixture.tsv"
  # negative control: the covered file and the unread file are never reported
  out="$(ps1f_uncovered "$scratch" "$scan_tests_glob")"; rc=$?
  if [[ "$rc" -eq 0 ]]; then rm -rf "$scratch"; log_fail "TEST-008 (test_036): derived-set check passed although brand-new-fixture.tsv is read by a Pester test and not in the filter"; fi
  if [[ "$out" != *brand-new-fixture.tsv* ]]; then rm -rf "$scratch"; log_fail "TEST-008 (test_036): check failed but did not name brand-new-fixture.tsv: '$out'"; fi
  if [[ "$out" == *unrelated-data.tsv* ]]; then rm -rf "$scratch"; log_fail "TEST-008 (test_036): unread file unrelated-data.tsv was reported (negative control)"; fi
  if [[ "$out" == *pester-host-skip.ps1* ]]; then rm -rf "$scratch"; log_fail "TEST-008 (test_036): covered file pester-host-skip.ps1 was reported"; fi
  rm -rf "$scratch"
  log_pass "TEST-008 (test_036) a new PowerShell-read lib file is detected and named"
}

test_037() {
  log_info "TEST-009 (test_037): windows-5_1 declares a job-level timeout-minutes of 26..45, windows-wsl1 keeps 25, the Pester steps keep 15..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  local block v wsl steps15
  block="$(awk '/^  windows-5_1:/ { f = 1; print; next } f && /^  [A-Za-z0-9_-]+:/ { f = 0 } f { print }' "$CI_WORKFLOW")"
  [[ -n "$block" ]] || log_fail "TEST-009 (test_037): windows-5_1 job block not found"
  v="$(sed -n 's/^    timeout-minutes:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' <<<"$block")"
  [[ -n "$v" && "$v" != *$'\n'* ]] || log_fail "TEST-009 (test_037): windows-5_1 needs exactly one job-level timeout-minutes (got '${v:-none}')"
  [[ "$v" -ge 26 && "$v" -le 45 ]] || log_fail "TEST-009 (test_037): windows-5_1 timeout-minutes $v is outside 26..45"
  wsl="$(awk '/^  windows-wsl1:/ { f = 1; next } f && /^  [A-Za-z0-9_-]+:/ { f = 0 } f { print }' "$CI_WORKFLOW" | sed -n 's/^    timeout-minutes:[[:space:]]*\([0-9][0-9]*\).*$/\1/p')"
  [[ "$wsl" == "25" ]] || log_fail "TEST-009 (test_037): windows-wsl1 job timeout-minutes must stay 25 (got '${wsl:-none}')"
  steps15="$(grep -cE '^        timeout-minutes: 15[[:space:]]*$' <<<"$block" || true)"
  [[ "$steps15" -ge 2 ]] || log_fail "TEST-009 (test_037): the windows-5_1 Pester steps must keep step-level timeout-minutes: 15 (found $steps15)"
  log_pass "TEST-009 (test_037) windows-5_1 timeout-minutes $v, wsl1 25, Pester steps 15"
}

# --- ci-windows-leg-waits-and-ps1-path-filter amendment (D1-fallback): the
# Git-Bash launch runs inside a Windows Job Object. Job Objects are Windows
# only, so TEST-010/TEST-011 drive the dispatcher's own seams under pwsh with
# stubs, and TEST-012 compiles the P/Invoke type and pins its wiring. The real
# Windows proof is the windows-5_1 smoke timeout arm (no survivor).
# ps1_job_probe <script-body> -- runs the body after dot-sourcing the real
# dispatcher; prints stdout, then a line "STDERR:" and the stderr capture.
ps1_job_probe() {
  local body="$1" d rc
  d="$(mktemp -d "${TMPDIR:-/tmp}/ps1-job-probe.XXXXXX")"
  [[ -n "$d" && "$d" = /* ]] || log_fail "ps1_job_probe: scratch dir not absolute"
  printf '%s\n' 'param([string]$Ps1)' '. $Ps1' "$body" >"$d/probe.ps1"
  pwsh -NoProfile -NonInteractive -File "$d/probe.ps1" -Ps1 "$RUN_TESTS_PS1" >"$d/out" 2>"$d/err" </dev/null
  rc=$?
  cat "$d/out"
  echo "STDERR:"
  cat "$d/err"
  echo "PWSH_RC=$rc"
  rm -rf "$d"
}

test_038() {
  log_info "TEST-010 (test_038): the Git-Bash launch goes through the job seam and the job is terminated on the normal and the timeout path, exit codes unchanged..."
  command -v pwsh >/dev/null 2>&1 || { echo "SKIP: TEST-010 (test_038): pwsh not found on this host (named skip; the windows-5_1 CI smoke arm still proves the job)"; return 0; }
  local out
  out="$(ps1_job_probe '
$script:calls = [System.Collections.Generic.List[string]]::new()
function New-KillOnCloseJob { [IntPtr]77 }
function Start-ProcessInJob { param($BashPath, $ArgString, $Job, $WorkingDirectory) $script:calls.Add("start-in-job:$Job"); $script:cwdSeen = $WorkingDirectory; [pscustomobject]@{ Id = 4242; ExitCode = 7 } }
function Start-Process { $script:calls.Add("start-process"); throw "Start-Process must not run when the job path works" }
function Stop-KillOnCloseJob { param($Job) $script:calls.Add("stop-job:$Job") }
function Stop-ProcessTree { param($ProcessId) $script:calls.Add("tree:$ProcessId") }
function Wait-ProcessWithTimeout { param($Process, $TimeoutSeconds) $true }
$cwdDir = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-cwd-probe-" + [guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $cwdDir
Set-Location -LiteralPath $cwdDir
$want = (Get-Location -PSProvider FileSystem).ProviderPath
$rc = Invoke-ViaGitBash -BashPath "C:\Git\bin\bash.exe" -Command @("sh", "-c", "exit 7") -ShScriptPath "C:\r\aai-run-tests.sh" -Timeout 30
"NORMAL rc=$rc calls=$($script:calls -join ",")"
"CWD same=$($script:cwdSeen -ceq $want) seen=$($script:cwdSeen)"
Set-Location -LiteralPath $HOME
Remove-Item -LiteralPath $cwdDir -Force
$script:calls.Clear()
function Wait-ProcessWithTimeout { param($Process, $TimeoutSeconds) $false }
$rc = Invoke-ViaGitBash -BashPath "C:\Git\bin\bash.exe" -Command @("sh", "-c", "sleep 300") -ShScriptPath "C:\r\aai-run-tests.sh" -Timeout 2
"TIMEOUT rc=$rc calls=$($script:calls -join ",")"
')"
  [[ "$out" == *"NORMAL rc="* ]] || log_fail "TEST-010 (test_038): probe never reached the normal arm (positive control): $out"
  [[ "$out" == *"NORMAL rc=7 calls=start-in-job:77,stop-job:77"$'\n'* ]] \
    || log_fail "TEST-010 (test_038): normal path must start inside job 77, keep exit 7 and terminate the job once: $out"
  [[ "$out" == *"TIMEOUT rc=124 calls=start-in-job:77,tree:4242,stop-job:77"$'\n'* ]] \
    || log_fail "TEST-010 (test_038): timeout path must keep exit 124, tree-kill 4242 and then terminate job 77: $out"
  [[ "$out" == *"CWD same=True"* ]] \
    || log_fail "TEST-010 (test_038): the job launch must start bash in the PowerShell location (Start-Process parity), not the process cwd: $out"
  [[ "$(<"$RUN_TESTS_PS1")" == *"IntPtr.Zero, cwd, ref si, out pi"* ]] \
    || log_fail "TEST-010 (test_038): StartSuspendedInJob must hand its cwd argument to CreateProcessW (lpCurrentDirectory), not null"
  log_pass "TEST-010 (test_038) job seam used; job terminated on normal and timeout paths; exit 7 and 124 kept"
}

test_039() {
  log_info "TEST-011 (test_039): no job -> one named AAI-DEGRADED-MODE line and today's Start-Process launch; assign failure degrades the same way; a CreateProcess failure stays a 125 spawn error..."
  command -v pwsh >/dev/null 2>&1 || { echo "SKIP: TEST-011 (test_039): pwsh not found on this host (named skip)"; return 0; }
  local out
  out="$(ps1_job_probe '
$script:calls = [System.Collections.Generic.List[string]]::new()
function Start-Process { $script:calls.Add("start-process"); [pscustomobject]@{ Id = 5150; Handle = [IntPtr]1; ExitCode = 3 } }
function Stop-KillOnCloseJob { param($Job) $script:calls.Add("stop-job:$Job") }
function Stop-ProcessTree { param($ProcessId) $script:calls.Add("tree:$ProcessId") }
function Wait-ProcessWithTimeout { param($Process, $TimeoutSeconds) $true }
function New-KillOnCloseJob { throw "AAI-NO-JOB-PROBE" }
function Start-ProcessInJob { param($BashPath, $ArgString, $Job) $script:calls.Add("start-in-job:$Job"); throw "must not be reached without a job" }
$rc = Invoke-ViaGitBash -BashPath "C:\Git\bin\bash.exe" -Command @("sh", "-c", "exit 3") -ShScriptPath "C:\r\aai-run-tests.sh" -Timeout 30
"NOJOB rc=$rc calls=$($script:calls -join ",")"
$script:calls.Clear()
function New-KillOnCloseJob { [IntPtr]78 }
function Start-ProcessInJob { param($BashPath, $ArgString, $Job) $script:calls.Add("start-in-job:$Job"); throw [System.InvalidOperationException]::new("AssignProcessToJobObject failed: AAI-ASSIGN-PROBE") }
$rc = Invoke-ViaGitBash -BashPath "C:\Git\bin\bash.exe" -Command @("sh", "-c", "exit 3") -ShScriptPath "C:\r\aai-run-tests.sh" -Timeout 30
"ASSIGN rc=$rc calls=$($script:calls -join ",")"
$script:calls.Clear()
function New-KillOnCloseJob { [IntPtr]79 }
function Start-ProcessInJob { param($BashPath, $ArgString, $Job) $script:calls.Add("start-in-job:$Job"); throw [System.ComponentModel.Win32Exception]::new(193) }
$rc = Invoke-ViaGitBash -BashPath "C:\Git\bin\bash.exe" -Command @("sh", "-c", "exit 3") -ShScriptPath "C:\r\aai-run-tests.sh" -Timeout 30
"SPAWNFAIL rc=$rc calls=$($script:calls -join ",")"
')"
  local err="${out#*STDERR:}" n
  [[ "$out" == *"NOJOB rc="* ]] || log_fail "TEST-011 (test_039): probe never reached the no-job arm (positive control): $out"
  [[ "$out" == *"NOJOB rc=3 calls=start-process"$'\n'* ]] \
    || log_fail "TEST-011 (test_039): with no job the dispatcher must launch through Start-Process and keep exit 3: $out"
  [[ "$err" == *"AAI-DEGRADED-MODE: [Git Bash] no Windows Job Object (AAI-NO-JOB-PROBE)"* ]] \
    || log_fail "TEST-011 (test_039): the no-job degrade must print one named AAI-DEGRADED-MODE line carrying the cause: $err"
  [[ "$out" == *"ASSIGN rc=3 calls=start-in-job:78,stop-job:78,start-process"$'\n'* ]] \
    || log_fail "TEST-011 (test_039): an assign failure must close job 78 and fall back to Start-Process with exit 3: $out"
  [[ "$err" == *"AAI-DEGRADED-MODE: [Git Bash] no Windows Job Object (AssignProcessToJobObject failed: AAI-ASSIGN-PROBE)"* ]] \
    || log_fail "TEST-011 (test_039): the assign degrade must print a named AAI-DEGRADED-MODE line: $err"
  n="$(grep -c 'AAI-DEGRADED-MODE: \[Git Bash\] no Windows Job Object' <<<"$err" || true)"
  [[ "$n" == "2" ]] || log_fail "TEST-011 (test_039): want exactly two degrade lines (no-job, assign), got $n: $err"
  [[ "$out" == *"SPAWNFAIL rc=125 calls=start-in-job:79,stop-job:79"$'\n'* ]] \
    || log_fail "TEST-011 (test_039): a CreateProcess failure must stay a 125 spawn error, close job 79 and never re-spawn through Start-Process: $out"
  [[ "$err" == *"AAI-SPAWN-ERROR: [Git Bash]"* ]] || log_fail "TEST-011 (test_039): the CreateProcess failure must print AAI-SPAWN-ERROR: $err"
  log_pass "TEST-011 (test_039) named degrade on no job and on assign failure; CreateProcess failure stays 125"
}

test_040() {
  log_info "TEST-012 (test_040): the Job Object P/Invoke type compiles under pwsh, sets KILL_ON_JOB_CLOSE, starts bash suspended and assigns it before resuming..."
  [[ -f "$RUN_TESTS_PS1" ]] || log_fail "missing $RUN_TESTS_PS1"
  local src a r
  src="$(cat "$RUN_TESTS_PS1")"
  [[ "$src" == *"JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000"* ]] || log_fail "TEST-012 (test_040): JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE must be 0x2000"
  [[ "$src" == *"LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE"* ]] || log_fail "TEST-012 (test_040): the job's LimitFlags must carry KILL_ON_JOB_CLOSE"
  [[ "$src" == *"CREATE_SUSPENDED = 0x00000004"* ]] || log_fail "TEST-012 (test_040): CREATE_SUSPENDED must be 0x00000004"
  [[ "$src" == *"CreateProcessW(app, cmd, IntPtr.Zero, IntPtr.Zero, true, CREATE_SUSPENDED"* ]] || log_fail "TEST-012 (test_040): bash must be created suspended"
  a="$(grep -n -m1 'if (!AssignProcessToJobObject(job, pi.hProcess))' "$RUN_TESTS_PS1" | cut -d: -f1)"
  r="$(grep -n -m1 'ResumeThread(pi.hThread)' "$RUN_TESTS_PS1" | cut -d: -f1)"
  [[ -n "$a" && -n "$r" ]] || log_fail "TEST-012 (test_040): AssignProcessToJobObject / ResumeThread calls not found (assign=${a:-none} resume=${r:-none})"
  [[ "$a" -lt "$r" ]] || log_fail "TEST-012 (test_040): the process must be assigned to the job (line $a) before its thread is resumed (line $r)"
  if command -v pwsh >/dev/null 2>&1; then
    local out
    out="$(ps1_job_probe 'Initialize-AaiJobObjectType; "TYPE=" + [bool]("AaiJobObject" -as [type])')"
    [[ "$out" == *"TYPE=True"* ]] || log_fail "TEST-012 (test_040): the AaiJobObject P/Invoke type does not compile under pwsh: $out"
  else
    echo "SKIP: TEST-012 (test_040) compile arm: pwsh not found on this host (named skip)"
  fi
  log_pass "TEST-012 (test_040) KILL_ON_JOB_CLOSE set; suspended create, assign, then resume; type compiles"
}

test_041() {
  log_info "TEST-013 (test_041): in both smoke steps the survivor probe, run under pwsh with Win32_Process stubbed, reports zero survivors when none exist and exactly one (with its pid) when one does..."
  [[ -f "$CI_WORKFLOW" ]] || log_fail "missing $CI_WORKFLOW"
  command -v pwsh >/dev/null 2>&1 || { echo "SKIP: TEST-013 (test_041): pwsh not found on this host (named skip)"; return 0; }
  local engine body fn call d out
  for engine in 5.1 pwsh7; do
    body="$(smoke_step_body "$engine")"
    fn="$(awk '/^ *function Get-SmokeHangSurvivors \{/ { f = 1 } f { print } f && /^          \}$/ { exit }' <<<"$body")"
    call="$(grep -m1 -E '^ *\$survivors = .*Get-SmokeHangSurvivors -Token' <<<"$body" || true)"
    [[ -n "$fn" && -n "$call" ]] || log_fail "TEST-013 (test_041): $engine smoke step lacks the survivor function or its call (fn=${#fn} bytes, call='$call')"
    d="$(mktemp -d "${TMPDIR:-/tmp}/survivor-probe.XXXXXX")"
    [[ -n "$d" && "$d" = /* ]] || log_fail "TEST-013 (test_041): scratch dir not absolute"
    {
      printf '%s\n' "$fn"
      printf '%s\n' 'function Start-Sleep { }'
      printf '%s\n' '$script:rows = @()' 'function Get-CimInstance { $script:rows }'
      printf '%s\n' "$call" '"NONE count=$($survivors.Count)"'
      printf '%s\n' '$script:rows = @([pscustomobject]@{ ProcessId = 2672; ParentProcessId = 3184; CommandLine = "sleep.exe 300" }, [pscustomobject]@{ ProcessId = 9; ParentProcessId = 1; CommandLine = "sleep.exe 1" })'
      printf '%s\n' "$call" '"ONE count=$($survivors.Count) pid=$($survivors[0].ProcessId)"'
    } >"$d/probe.ps1"
    out="$(pwsh -NoProfile -NonInteractive -File "$d/probe.ps1" 2>&1 </dev/null)"
    rm -rf "$d"
    [[ "$out" == *"ONE count="* ]] || log_fail "TEST-013 (test_041): $engine probe never reached the one-survivor arm (positive control): $out"
    [[ "$out" == *"NONE count=0"* ]] || log_fail "TEST-013 (test_041): $engine survivor probe reports a phantom survivor when none exist: $out"
    [[ "$out" == *"ONE count=1 pid=2672"* ]] || log_fail "TEST-013 (test_041): $engine survivor probe must report exactly the one sleep 300 survivor (pid 2672): $out"
  done
  log_pass "TEST-013 (test_041) survivor probe: zero when none, exactly one when one, in both smoke steps"
}

# Prints, one per line, each path of the newline-separated list $1 under .aai/.
win_fallback_aai_paths() {
  local p
  while IFS= read -r p; do
    [[ "$p" =~ ^\.aai/ ]] && printf '%s\n' "$p"
  done <<EOF_NAMES
$1
EOF_NAMES
  return 0
}

test_042() {
  log_info "TEST-028 gate (test_042): the execution arm is skipped by name only for an invoked bash older than 4; translation asserts precede the gate; the .aai/ path checker can flag a path (positive control)..."
  local out rc m
  # TEST-001 (Spec-AC-01, SEAM-2): the real host. Below bash 4 the named SKIP line
  # and exit 0; bash 4 or newer the unchanged pass line and no SKIP line.
  local real_major real_out real_rc
  real_major="$(win_fallback_invoked_bash_major)"
  real_out="$(test_028 2>&1)" && real_rc=0 || real_rc=$?
  if [[ "$(win_fallback_exec_arm_decision "$real_major")" == skip ]]; then
    [[ "$real_rc" -eq 0 ]] || log_fail "TEST-001: bash $real_major host must exit 0 on test_028, got $real_rc: $real_out"
    assert_payload_contains "$real_out" "SKIP: TEST-028 execution arm" "TEST-001: bash $real_major host printed no named SKIP line: $real_out"
    assert_payload_not_contains "$real_out" "executed under Git Bash" "TEST-001: bash $real_major host printed the arm pass line: $real_out"
    assert_payload_not_contains "$real_out" "FAIL python path" "TEST-001: bash $real_major host ran the sentinel: $real_out"
  else
    [[ "$real_rc" -eq 0 ]] || log_fail "TEST-001: bash $real_major host must pass test_028, got $real_rc: $real_out"
    assert_payload_contains "$real_out" "executed under Git Bash" "TEST-001: bash $real_major host lost the pass line: $real_out"
    assert_payload_not_contains "$real_out" "SKIP: TEST-028" "TEST-001: bash $real_major host skipped the arm: $real_out"
  fi
  # Positive control + forced majors (SEAM-1, in-process override of the probe).
  for m in 3 4 5 ""; do
    out="$(win_fallback_invoked_bash_major() { printf '%s' "$m"; }; test_028 2>&1)" && rc=0 || rc=$?
    if [[ "$m" == 3 ]]; then
      [[ "$rc" -eq 0 ]] || log_fail "TEST-002: forced major 3 must skip with exit 0, got $rc: $out"
      assert_payload_contains "$out" "SKIP: TEST-028 execution arm" "TEST-002: forced major 3 printed no named SKIP line: $out"
      assert_payload_not_contains "$out" "executed under Git Bash" "TEST-002: forced major 3 still ran the arm: $out"
    else
      assert_payload_not_contains "$out" "SKIP: TEST-028" "TEST-002: forced major '${m}' must not skip the arm: $out"
    fi
  done
  # A stub bash first on PATH is what the real helper reads (SEAM-1).
  local stub
  stub="$(mktemp -d "${TMPDIR:-/tmp}/aai-w28-stub.XXXXXX")"
  [[ -n "$stub" && "$stub" = /* ]] || log_fail "TEST-002: stub dir not absolute"
  printf '#!/bin/sh\nprintf 5\n' > "$stub/bash"
  chmod +x "$stub/bash"
  [[ "$(PATH="$stub:$PATH" win_fallback_invoked_bash_major)" == 5 ]] || { rm -rf "$stub"; log_fail "TEST-002: real helper did not read the stub bash major"; }
  printf '#!/bin/sh\nprintf 3\n' > "$stub/bash"
  out="$(PATH="$stub:$PATH" test_028 2>&1)" && rc=0 || rc=$?
  rm -rf "$stub"
  [[ "$rc" -eq 0 ]] || log_fail "TEST-002: stub bash 3 must skip with exit 0, got $rc: $out"
  assert_payload_contains "$out" "SKIP: TEST-028 execution arm" "TEST-002: stub bash 3 printed no SKIP line: $out"
  [[ "$(win_fallback_exec_arm_decision 3)" == skip && "$(win_fallback_exec_arm_decision 4)" == run && "$(win_fallback_exec_arm_decision x)" == run && "$(win_fallback_exec_arm_decision '')" == run ]] \
    || log_fail "TEST-002: decision helper wrong for 3/4/non-numeric/empty"

  # Spec-AC-03: a broken translation lib fails test_028 even on the skip branch.
  local fake
  fake="$(mktemp -d "${TMPDIR:-/tmp}/aai-w28-fake.XXXXXX")"
  [[ -n "$fake" && "$fake" = /* ]] || log_fail "TEST-003: fake root not absolute"
  mkdir -p "$fake/.aai/scripts/lib"
  printf 'aai_to_git_bash_path() { printf %%s "$1"; }\naai_to_windows_path() { printf %%s "$1"; }\n' > "$fake/.aai/scripts/lib/git-bash-path.sh"
  out="$(PROJECT_ROOT="$fake"; win_fallback_invoked_bash_major() { printf 3; }; test_028 2>&1)" && rc=0 || rc=$?
  rm -rf "$fake"
  [[ "$rc" -eq 1 ]] || log_fail "TEST-003: broken translation must fail test_028 with exit 1 on the skip branch, got $rc: $out"
  assert_payload_contains "$out" "git-bash path wrong" "TEST-003: broken translation failed for another reason: $out"

  # Spec-AC-04 (positive control only): the .aai/ path checker flags exactly the
  # .aai/ path. The one-off "this ride changed nothing under .aai/" diff is a
  # property of the ride, read once at validation, not an invariant of the suite.
  local flagged
  flagged="$(win_fallback_aai_paths $'docs/a.md\n.aai/scripts/x.sh\ntests/skills/t.sh')"
  [[ "$flagged" == ".aai/scripts/x.sh" ]] || log_fail "TEST-004: path checker did not flag exactly the .aai/ path (positive control): '$flagged'"
  log_pass "TEST-042 TEST-028 execution arm gated by the invoked bash major; translation asserts precede the gate"
}

ALL_TESTS="007 009 013 014 015 016 017 018 019 020 021 022 023 024 025 026 027 028 029 030 031 032 033 034 035 036 037 038 039 040 041 042"

# TEST-027 (Spec-AC-04): ALL_TESTS still registers the Windows-safe pin.
test_027() {
  log_info "TEST-027: ALL_TESTS still includes 024..."
  [[ "$ALL_TESTS" == *024* ]] || log_fail "TEST-027: ALL_TESTS missing 024"
  log_pass "TEST-027 ALL_TESTS includes 024"
}

main() {
  echo "Testing $TEST_NAME (Windows fallback: MSYS branch, platform matrix, MV protocol doc-presence)"
  check_deps
  local selected="$*"
  [[ -n "$selected" ]] || selected="$ALL_TESTS"
  local t
  for t in $selected; do
    t="${t#TEST-}"
    t="${t#test_}"
    declare -F "test_${t}" >/dev/null || { echo "Unknown test: $t" >&2; exit 2; }
    "test_${t}"
  done
  echo ""
  log_pass "All selected $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
