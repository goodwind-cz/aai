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
  echo "$out" | grep -qi "MSYS" || log_fail "degraded marker must name the detected MSYS/MINGW uname"

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
    skip_lines="$(grep -nE "^[[:space:]]*It[[:space:]]+'.*'[[:space:]]+-Skip:\\\$script:SkipOnWindows" "$f" || true)"
    if [[ -n "$skip_lines" ]]; then
      while IFS= read -r line; do
        assert_payload_contains "$line" "PosixOnly" "$f: a -Skip:\$script:SkipOnWindows It is missing the PosixOnly token in its name: $line"
        echo "$line" | grep -qE 'PosixOnly:[[:space:]]*[^)'"'"']+' \
          || log_fail "$f: a -Skip:\$script:SkipOnWindows It carries PosixOnly with no non-empty reason: $line"
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
  decl_line="$(grep -nF 'AAI_EXPECTED_WIN_SKIP_COUNT:' "$CI_WORKFLOW" | head -n1 | cut -d: -f1)"
  jobs_line="$(grep -nE '^jobs:' "$CI_WORKFLOW" | head -n1 | cut -d: -f1)"
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

# --- TEST-024 (Spec-AC-01): guidance trio carries the contract verbatim; the
#     seven prompt-corpus invocation mentions carry the bash-prefixed literal --
test_024() {
  log_info "TEST-024: TECHNOLOGY.md + TECHNOLOGY_TEMPLATE.md + AGENTS.md carry both canonical literals + repo-root rule + prohibition; 6 prompts + DYNAMIC_SKILLS.md carry the bash-prefixed POSIX literal with no bare-path mention left..."

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

  # The seven invocation mentions (six prompt-corpus files + the system-side
  # DYNAMIC_SKILLS.md): every aai-run-tests.sh mention carries the bash prefix.
  local pf
  local prompt_files=(
    "$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_VERIFY.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_TEST_SKILLS.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_BOOTSTRAP.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_DESLOP.prompt.md"
    "$PROJECT_ROOT/.aai/system/DYNAMIC_SKILLS.md"
  )
  for pf in "${prompt_files[@]}"; do
    [[ -f "$pf" ]] || log_fail "missing $pf"
    grep -qF -- 'bash .aai/scripts/aai-run-tests.sh' "$pf" \
      || log_fail "$pf missing the bash-prefixed canonical POSIX invocation literal"
    # Shadow-proof bare-mention audit (PR #254 bot catch): a line-count
    # compare (grep -c) lets a bare mention hide on a line that ALSO carries
    # a prefixed one. Strip every canonical occurrence from the content
    # first, then ANY surviving mention is a bare one — per-occurrence, not
    # per-line.
    local residue
    residue="$(sed 's|bash \.aai/scripts/aai-run-tests\.sh||g' "$pf" | grep -nF -- '.aai/scripts/aai-run-tests.sh' || true)"
    [[ -z "$residue" ]] \
      || log_fail "$pf still carries a bare-path aai-run-tests.sh invocation mention after canonical-occurrence strip: $residue"
  done

  log_pass "guidance trio carries the contract verbatim; all seven prompt invocation mentions are bash-prefixed (TEST-024)"
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

ALL_TESTS="007 009 013 014 015 016 017 018 019 020 021 022 023 024 025 026"

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
