#!/usr/bin/env bash
#
# Test: aai-install-parity
# (docs/specs/SPEC-DRAFT-install-path-parity-harness.md, TEST-3560..3572)
#
# Runs both twins of aai-sync, aai-update and the hook installer into scratch targets (tests/skills/lib/install-parity.mjs)
# and requires that every divergence between them sits on the reviewed allowlist. The real run happens once per suite
# invocation into $TEST_DIR/run.json; later cases read it. Every fixture lives in mktemp directories: the scratch base of the
# driver defaults to a directory under /tmp (the PowerShell twin is about ten times slower when its source tree lives under a
# macOS $TMPDIR with many entries) and nothing is written into the checkout.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-install-parity.sh                    # run all
#   bash tests/skills/test-aai-install-parity.sh test_3560_matrix_tiers
#
# Environment:
#   AAI_PARITY_MATRIX          smoke | default | full (default: default)
#   AAI_PARITY_REFERENCE_HOST  1 enforces the timing bounds of TEST-3569 (else they are printed)
#   AAI_PARITY_SCRATCH         base directory for the driver's scratch root (default: a mktemp directory under /tmp)
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-install-parity"
TEST_DIR=""
PARITY_BASE=""
# The suite lives at <root>/tests/skills; the root is derived without a cd inside a substitution.
SELF="${BASH_SOURCE[0]}"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
SCRIPT_DIR="${SELF%/*}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
DRIVER="$PROJECT_ROOT/tests/skills/lib/install-parity.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/install-parity.test.mjs"
ALLOWLIST="$PROJECT_ROOT/tests/skills/lib/install-parity-allowlist.tsv"
PESTER_FILE="$PROJECT_ROOT/tests/skills/install-parity.Tests.ps1"
SPEC_ID="spec-install-path-parity-harness"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
  if [[ -n "${PARITY_BASE:-}" && -d "$PARITY_BASE" ]]; then rm -rf "$PARITY_BASE"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  log_pass "Dependencies checked"
}

setup_fixture() {
  # A sweep loads the host: the driver's 300 s per-step bound is tripled here unless the caller names one. A step that still
  # outlives it is reported by the driver as an INFRA timeout (exit 4), not as a parity divergence.
  export AAI_PARITY_STEP_TIMEOUT="${AAI_PARITY_STEP_TIMEOUT:-900}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-install-parity-suite.XXXXXX")"
  # A fast scratch base for the driver unless the caller names one; removed on exit.
  if [[ -z "${AAI_PARITY_SCRATCH:-}" ]]; then
    PARITY_BASE="$(mktemp -d /tmp/aai-parity-base.XXXXXX 2>/dev/null || mktemp -d "$TEST_DIR/base.XXXXXX")"
    export AAI_PARITY_SCRATCH="$PARITY_BASE"
  fi
}

# run_node_tests <TEST id>: the driver and node test file must exist; cases named with the id must pass;
# zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$DRIVER" ]] || log_fail "$id: tests/skills/lib/install-parity.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/install-parity.test.mjs does not exist"
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  [[ "$out" =~ pass\ [1-9] ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported zero passing tests for the pattern"; }
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# parity_matrix: prints the tier the real run uses; any value but smoke, default or full is a named failure.
parity_matrix() {
  local m="${AAI_PARITY_MATRIX:-default}"
  case "$m" in
    smoke|default|full) printf '%s\n' "$m" ;;
    *) echo "FAIL: AAI_PARITY_MATRIX must be smoke, default or full, got '$m'" >&2; return 1 ;;
  esac
}

# driver <args...>: runs the driver with the suite's environment (no AAI_ role or write leak).
driver() { env -u AAI_ROLE -u AAI_GIT_WRITE node "$DRIVER" "$@"; }

# spec_file: the spec with the frozen id, wherever the allocator has put it.
spec_file() {
  local f
  for f in "$PROJECT_ROOT"/docs/specs/*.md; do
    if [[ "$(sed -n '2p' "$f")" == "id: $SPEC_ID" ]]; then printf '%s\n' "$f"; return 0; fi
  done
  return 1
}

# tier_ids <tier>: the D-MATRIX table ids of that tier and the tiers below it, in table order.
tier_ids() {
  local spec="$1" tier="$2" line ids="" re='^\|[[:space:]]([A-Z]{2}-[0-9]{2})[[:space:]]\|[[:space:]](smoke|default|full)[[:space:]]\|'
  while IFS= read -r line; do
    if [[ "$line" =~ $re ]]; then
      case "$tier:${BASH_REMATCH[2]}" in
        smoke:smoke|default:smoke|default:default|full:*) ids="$ids${BASH_REMATCH[1]}"$'\n' ;;
      esac
    fi
  done < "$spec"
  printf '%s' "$ids"
}

# ensure_run: the one real run of this suite invocation (matrix from parity_matrix) into $TEST_DIR/run.json.
ensure_run() {
  local m rc=0
  [[ -f "$TEST_DIR/run.rc" ]] && return 0
  m="$(parity_matrix)" || log_fail "parity_matrix refused the matrix"
  driver run --matrix "$m" --json "$TEST_DIR/run.json" > "$TEST_DIR/run.out" 2>&1 || rc=$?
  printf '%s\n' "$rc" > "$TEST_DIR/run.rc"
  printf '%s\n' "$m" > "$TEST_DIR/run.matrix"
}

# json_check <file> <js body>: runs the body with `r` bound to the parsed JSON; a thrown error or a false result fails with its text.
json_check() {
  node -e '
    const fs = require("fs");
    const r = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const out = (function () { '"$2"' })();
    if (out !== true) { process.stderr.write(String(out) + "\n"); process.exit(1); }
  ' "$1"
}

# ------------------------------------------------------------------------------------------------------------------

test_3560_matrix_tiers() {
  need_tool TEST-3560 node || return 0
  local spec tier got want
  spec="$(spec_file)" || log_fail "TEST-3560: no spec with id $SPEC_ID under docs/specs"
  for tier in smoke default full; do
    want="$(tier_ids "$spec" "$tier")"
    got="$(driver list --matrix "$tier" --json)" || log_fail "TEST-3560: list --matrix $tier failed"
    got="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).join("\n") + "\n")' "$got")"
    [[ -n "$want" ]] || log_fail "TEST-3560: the spec's D-MATRIX table holds no $tier rows"
    [[ "$got" == "${want%$'\n'}" ]] || log_fail "TEST-3560: list --matrix $tier gives [$got], the spec table gives [${want%$'\n'}]"
  done
  local rc=0
  driver list --matrix bogus >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 2 ]] || log_fail "TEST-3560: list --matrix bogus exited $rc, expected 2"
  log_pass "TEST-3560: list --matrix gives the D-MATRIX ids of each tier in table order; an unknown tier exits 2"
}

test_3561_compare_kinds() {
  run_node_tests TEST-3561
  log_pass "TEST-3561: compareTrees reports one divergence of each kind and counts empty directories and symlinks"
}

test_3562_normalizations() {
  run_node_tests TEST-3562
  log_pass "TEST-3562: the normalization table is exactly N1 to N4 and E1, E2 with their rules"
}

test_3563_allowlist() {
  run_node_tests TEST-3563
  log_pass "TEST-3563: the allowlist parser refuses, covers, leaves uncovered and judges stale rows as specified"
}

test_3564_broken() {
  run_node_tests TEST-3564
  log_pass "TEST-3564: a missed reference expectation, two twins failing alike and an absent probe are broken"
}

test_3565_default_matrix() {
  need_tool TEST-3565 node || return 0
  need_tool TEST-3565 git || return 0
  need_tool TEST-3565 pwsh || return 0
  local m rc
  ensure_run
  rc="$(cat "$TEST_DIR/run.rc")"; m="$(cat "$TEST_DIR/run.matrix")"
  if [[ "$rc" != 0 ]]; then cat "$TEST_DIR/run.out" >&2; log_fail "TEST-3565: the driver run (matrix $m) exited $rc"; fi
  [[ -f "$TEST_DIR/run.json" ]] || log_fail "TEST-3565: the driver wrote no report"
  json_check "$TEST_DIR/run.json" '
    if (r.verdict !== "PASS") return "verdict " + r.verdict;
    if (r.uncovered.length || r.stale.length) return "uncovered or stale rows in a PASS report";
    for (const s of r.scenarios) if (s.broken.length) return s.id + " is broken: " + s.broken.join("; ");
    if (r.twins[0] !== "sh" || !r.twins.includes("ps1")) return "twins " + r.twins.join(",");
    return true;' || log_fail "TEST-3565: the report is not a clean PASS"
  local want got
  want="$(driver list --matrix "$m")" || log_fail "TEST-3565: list --matrix $m failed"
  got="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).scenarios.map((s) => s.id).join("\n"))' "$TEST_DIR/run.json")"
  [[ "$got" == "$want" ]] || log_fail "TEST-3565: the report holds scenarios [$got], the $m tier lists [$want]"
  if [[ "$m" == smoke ]]; then
    log_info "TEST-3565: smoke tier, the idempotence self pairs (SY-02, HK-02, HK-09) are in the default tier and are not checked"
  else
    json_check "$TEST_DIR/run.json" '
      if (!r.pairs.includes("sh:sh") || !r.pairs.includes("ps1:ps1")) return "self pairs missing from " + r.pairs.join(" ");
      for (const id of ["SY-02", "HK-02", "HK-09"]) {
        const s = r.scenarios.find((x) => x.id === id);
        if (!s) return id + " is not in the report";
        for (const t of ["sh", "ps1"]) if (!s.steps.some((x) => x.twin === t && x.step === 2)) return id + " has no step 2 for " + t;
      }
      return true;' || log_fail "TEST-3565: the idempotence self pairs are not all compared"
  fi
  log_pass "TEST-3565: the $m matrix passes against the committed allowlist, every scenario compared with its probes present"
}

test_3566_third_twin() {
  need_tool TEST-3566 node || return 0
  need_tool TEST-3566 git || return 0
  need_tool TEST-3566 pwsh || return 0
  local dir="$TEST_DIR/t3566" out rc=0 t
  mkdir -p "$dir"
  cat > "$dir/mirror.mjs" <<'JS'
import { TWINS } from '@DRIVER@';
export default { argv: (step, ctx) => TWINS.sh.argv(step, ctx) };
JS
  cat > "$dir/skew.mjs" <<'JS'
import { TWINS } from '@DRIVER@';
export default {
  argv(step, ctx) {
    const a = TWINS.sh.argv(step, ctx);
    const script = `const {spawnSync}=require('child_process');const r=spawnSync(${JSON.stringify(a.file)},${JSON.stringify(a.args)},{cwd:${JSON.stringify(a.cwd)},stdio:'inherit',env:process.env});`
      + `require('fs').appendFileSync('.aai/system/AAI_PIN.md','x');process.exit(r.status||0);`;
    return { file: process.execPath, args: ['-e', script], cwd: ctx.target };
  },
};
JS
  # the twin modules import the driver by absolute file URL
  node -e '
    const fs = require("fs"); const u = require("url").pathToFileURL(process.argv[1]).href;
    for (const n of ["mirror", "skew"]) { const f = process.argv[2] + "/" + n + ".mjs"; fs.writeFileSync(f, fs.readFileSync(f, "utf8").split("@DRIVER@").join(u)); }
  ' "$DRIVER" "$dir"
  # the committed rows, with the module twin added to every sh:ps1 row (one allowlist per twin: a pair must name registered twins)
  for t in mirror skew; do
    awk -F'\t' -v t="$t" 'BEGIN { OFS = "\t" } /^#/ || NF < 9 { print; next } { n = split($2, p, ","); o = ""; for (i = 1; i <= n; i++) { o = o (i > 1 ? "," : "") p[i]; if (p[i] == "sh:ps1") o = o ",ps1:" t } $2 = o; print }' "$ALLOWLIST" > "$dir/allow-$t.tsv"
  done
  out="$(driver run --matrix smoke --scenario SY-01 --twins sh,ps1 --twin-module "mirror=$dir/mirror.mjs" --allowlist "$dir/allow-mirror.tsv" --json "$dir/mirror.json" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3566: the mirror twin run exited $rc, expected 0"; }
  json_check "$dir/mirror.json" '
    for (const p of ["sh:mirror", "ps1:mirror"]) if (!r.pairs.includes(p)) return "pair " + p + " missing from " + r.pairs.join(" ");
    return r.verdict === "PASS" ? true : "verdict " + r.verdict;' || log_fail "TEST-3566: the mirror run is not compared with both twins"
  rc=0
  out="$(driver run --matrix smoke --scenario SY-01 --twins sh,ps1 --twin-module "skew=$dir/skew.mjs" --allowlist "$dir/allow-skew.tsv" --json "$dir/skew.json" 2>&1)" || rc=$?
  [[ "$rc" == 1 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3566: the skew twin run exited $rc, expected 1"; }
  local pair
  for pair in sh:skew ps1:skew; do
    [[ "$out" == *"UNCOVERED SY-01 $pair "*".aai/system/AAI_PIN.md"* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3566: the failure does not name $pair on .aai/system/AAI_PIN.md"; }
  done
  log_pass "TEST-3566: a mirror module twin passes against sh and ps1; a one-byte skew fails naming sh:skew and ps1:skew"
}

test_3567_environment() {
  need_tool TEST-3567 node || return 0
  need_tool TEST-3567 git || return 0
  need_tool TEST-3567 pwsh || return 0
  local dir="$TEST_DIR/t3567" out rc=0 outside="$TEST_DIR/t3567-outside"
  mkdir -p "$dir" "$outside"
  cat > "$dir/rec.mjs" <<'JS'
export default {
  argv: (step, ctx) => ({
    file: process.execPath,
    args: ['-e', `const fs=require('fs');fs.writeFileSync(process.env.PARITY_ENV_OUT,JSON.stringify(process.env));fs.writeFileSync('p.txt','x\\n')`],
    cwd: ctx.target,
  }),
};
JS
  : > "$dir/none.tsv"
  # the recording twin is the only twin of this run; its env goes to a file named in the caller's environment
  PARITY_ENV_OUT="$dir/env.json" AAI_ROLE=implementation AAI_GIT_WRITE=1 GIT_CONFIG_GLOBAL=/nonexistent/outside \
    node "$DRIVER" run --matrix smoke --scenario SY-01 --twins sh --twin-module "rec=$dir/rec.mjs" --allowlist "$dir/none.tsv" --json "$dir/rec.json" > "$dir/rec.out" 2>&1 || rc=$?
  # the sh twin of this run really syncs; only the recorded environment matters here
  [[ -s "$dir/env.json" ]] || { cat "$dir/rec.out" >&2; log_fail "TEST-3567: the recording twin recorded no environment (driver exit $rc)"; }
  node -e '
    const env = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = [];
    const g = String(env.GIT_CONFIG_GLOBAL);
    const root = g.slice(0, g.lastIndexOf("/"));
    if (env.TZ !== "Etc/GMT-3") bad.push("TZ=" + env.TZ);
    if (env.GIT_CONFIG_NOSYSTEM !== "1") bad.push("GIT_CONFIG_NOSYSTEM=" + env.GIT_CONFIG_NOSYSTEM);
    if (!g.endsWith("/gitconfig") || g.startsWith("/nonexistent")) bad.push("GIT_CONFIG_GLOBAL=" + g);
    for (const k of ["TMPDIR", "TMP", "TEMP"]) if (env[k] !== root + "/tmp") bad.push(k + "=" + env[k] + " (scratch root " + root + ")");
    for (const k of Object.keys(env)) if (k.startsWith("AAI_")) bad.push(k);
    if (bad.length) { process.stderr.write(bad.join("; ") + "\n"); process.exit(1); }
  ' "$dir/env.json" || log_fail "TEST-3567: the twin environment is not the pinned one"
  # HK-01 under a caller GIT_CONFIG_GLOBAL that sets core.hooksPath to an outside directory
  printf '[core]\n\thooksPath = %s/hooks\n' "$outside" > "$outside/gc"
  rc=0
  out="$(GIT_CONFIG_GLOBAL="$outside/gc" driver run --matrix smoke --scenario HK-01 --json "$dir/hk.json" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3567: HK-01 under a caller core.hooksPath exited $rc, expected 0"; }
  json_check "$dir/hk.json" '
    const s = r.scenarios[0];
    if (s.id !== "HK-01") return "scenario " + s.id;
    if (s.steps.some((x) => x.code !== 0)) return "a step exited nonzero";
    return r.verdict === "PASS" ? true : "verdict " + r.verdict;' || log_fail "TEST-3567: HK-01 did not pass for both twins"
  [[ ! -e "$outside/hooks" ]] || log_fail "TEST-3567: a twin wrote into the caller's core.hooksPath directory"
  log_pass "TEST-3567: every twin sees the pinned environment, and a caller core.hooksPath does not reach the twins"
}

test_3568_pester() {
  need_tool TEST-3568 pwsh || return 0
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3568: tests/skills/install-parity.Tests.ps1 does not exist"
  local out rc=0 line passed skipped failed containers
  # The default matrix (TEST-3565) already ran both twins over every smoke scenario here, so this case proves the Pester front
  # end on one cheap scenario (HK-01); the Windows parity job and the Linux ps1 gate run the whole smoke matrix through it.
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE AAI_PARITY_PESTER_SCENARIOS="${AAI_PARITY_PESTER_SCENARIOS-HK-01}" PARITY_PESTER_FILE="$PESTER_FILE" pwsh -NoProfile -NonInteractive -Command '
    $ErrorActionPreference = "Stop"
    $m = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $m) { Write-Output "NO-PESTER5"; exit 3 }
    Import-Module $m
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PARITY_PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Output ("PESTER-RESULT passed={0} skipped={1} failed={2} containers={3}" -f $r.PassedCount, $r.SkippedCount, $r.FailedCount, $r.FailedContainersCount)
  ' 2>&1)" || rc=$?
  if [[ "$out" == *NO-PESTER5* ]]; then
    [[ -z "${CI:-}" ]] || log_fail "TEST-3568: Pester 5 is required on CI but is not installed"
    echo "SKIP-CASE: TEST-3568 needs Pester 5, which is not installed here"
    return 0
  fi
  line=""
  while IFS= read -r l; do case "$l" in PESTER-RESULT*) line="$l" ;; esac; done <<< "$out"
  [[ -n "$line" ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3568: Pester printed no result line (exit $rc)"; }
  [[ "$line" =~ passed=([0-9]+)\ skipped=([0-9]+)\ failed=([0-9]+)\ containers=([0-9]+) ]] || log_fail "TEST-3568: unreadable result line: $line"
  passed="${BASH_REMATCH[1]}"; skipped="${BASH_REMATCH[2]}"; failed="${BASH_REMATCH[3]}"; containers="${BASH_REMATCH[4]}"
  if [[ "$rc" != 0 || "$passed" -lt 2 || "$skipped" != 0 || "$failed" != 0 || "$containers" != 0 ]]; then
    printf '%s\n' "$out" >&2
    log_fail "TEST-3568: Pester exit $rc, $line (want at least 2 passed, 0 skipped, 0 failed, 0 failed containers)"
  fi
  # inspection: the file's contract (D-PESTER)
  local f="$PESTER_FILE" c
  for c in 'ProgramFiles' 'ProgramFiles(x86)' '--exec-path' 'System32' 'pester-native-capture.ps1' 'Get-Process -Id $PID'; do
    grep -qF -- "$c" "$f" || log_fail "TEST-3568: install-parity.Tests.ps1 does not mention $c"
  done
  grep -qF -- "'--matrix', 'smoke'" "$f" || log_fail "TEST-3568: the driver call does not run the smoke matrix"
  if grep -qE -- '-Skip|Set-ItResult|-Pending' "$f"; then log_fail "TEST-3568: install-parity.Tests.ps1 skips or pends a case"; fi
  local n
  n="$(grep -cF 'Invoke-NativeCaptured' "$f" || true)"
  [[ "$n" -ge 4 ]] || log_fail "TEST-3568: only $n Invoke-NativeCaptured uses (the driver, git --exec-path, node and bash probes)"
  # no native call outside the helper: no call operator on a bare command, no Start-Process, no ProcessStartInfo
  if grep -qE -- '^[[:space:]]*&[[:space:]]|Start-Process|ProcessStartInfo' "$f"; then log_fail "TEST-3568: a native call bypasses Invoke-NativeCaptured"; fi
  # B1: Windows PowerShell 5.1 hands a top-level JSON array down the pipeline as one object. The $want line of the file is run
  # under pwsh 7 against a ConvertFrom-Json that behaves that way (-NoEnumerate); a double-wrapped list joins as System.Object[].
  local want_line="" l2
  while IFS= read -r l2; do case "$l2" in *'$want = '*) want_line="$l2"; break ;; esac; done < "$f"
  [[ -n "$want_line" ]] || log_fail "TEST-3568: no \$want = line in install-parity.Tests.ps1"
  local joined
  joined="$(env -u AAI_ROLE PARITY_WANT_LINE="$want_line" pwsh -NoProfile -NonInteractive -Command '
    $ErrorActionPreference = "Stop"
    function ConvertFrom-Json { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { Microsoft.PowerShell.Utility\ConvertFrom-Json -NoEnumerate -InputObject $InputObject } }
    $l = @{ Out = "[`"SY-01`",`"UP-01`"]" }
    Invoke-Expression $env:PARITY_WANT_LINE
    Write-Output ("JOINED=" + ($want -join ","))
  ' 2>&1)" || log_fail "TEST-3568: the \$want line did not run under pwsh: $joined"
  [[ "$joined" == *"JOINED=SY-01,UP-01"* ]] || log_fail "TEST-3568: under 5.1 list semantics the \$want line yields [$joined], not SY-01,UP-01"
  if grep -qE -- '@\(\$[A-Za-z.]+[[:space:]]*\|[[:space:]]*ConvertFrom-Json\)' "$f"; then log_fail "TEST-3568: a bare @(... | ConvertFrom-Json) double-wraps a JSON array under Windows PowerShell 5.1"; fi
  # NB-B: no twin list is pinned, so a twin added to the driver registry runs here; the scratch base is cleaned in a finally
  if grep -qF -- "'--twins'" "$f"; then log_fail "TEST-3568: the front end pins --twins"; fi
  grep -qF -- 'finally' "$f" || log_fail "TEST-3568: the front end has no finally that cleans its scratch"
  grep -qF -- 'AAI_PARITY_SCRATCH' "$f" || log_fail "TEST-3568: the front end names no scratch base"
  log_pass "TEST-3568: Pester ($line) and the file contract hold"
}

test_3569_tiers_and_timing() {
  need_tool TEST-3569 node || return 0
  local got rc=0 s t
  got="$(env -u AAI_PARITY_MATRIX bash -c 'source "$1"; parity_matrix' _ "$SELF" 2>&1)" || rc=$?
  [[ "$rc" == 0 && "$got" == default ]] || log_fail "TEST-3569: with AAI_PARITY_MATRIX unset parity_matrix gave [$got] (exit $rc), expected default"
  for t in smoke full; do
    got="$(AAI_PARITY_MATRIX="$t" bash -c 'source "$1"; parity_matrix' _ "$SELF" 2>&1)" || true
    [[ "$got" == "$t" ]] || log_fail "TEST-3569: AAI_PARITY_MATRIX=$t gave [$got]"
  done
  rc=0
  got="$(AAI_PARITY_MATRIX=bogus bash -c 'source "$1"; parity_matrix' _ "$SELF" 2>&1)" || rc=$?
  [[ "$rc" != 0 && "$got" == *AAI_PARITY_MATRIX*bogus* ]] || log_fail "TEST-3569: a bogus matrix gave [$got] (exit $rc), expected a named failure"
  # the report carries per-scenario and total seconds (the smoke matrix is run when no report exists yet)
  need_tool TEST-3569 git || return 0
  need_tool TEST-3569 pwsh || return 0
  if [[ ! -f "$TEST_DIR/run.json" ]]; then
    AAI_PARITY_MATRIX=smoke ensure_run
    [[ "$(cat "$TEST_DIR/run.rc")" == 0 ]] || { cat "$TEST_DIR/run.out" >&2; log_fail "TEST-3569: the smoke run failed"; }
  fi
  json_check "$TEST_DIR/run.json" '
    if (typeof r.total_seconds !== "number") return "no total_seconds";
    for (const s of r.scenarios) if (typeof s.seconds !== "number") return s.id + " has no seconds";
    return true;' || log_fail "TEST-3569: the report lacks per-scenario or total seconds"
  s="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).total_seconds))' "$TEST_DIR/run.json")"
  t="$(cat "$TEST_DIR/run.matrix")"
  log_info "TEST-3569: matrix $t took ${s}s in total (bounds on the reference host: default 150 s, smoke 75 s)"
  if [[ "${AAI_PARITY_REFERENCE_HOST:-}" == 1 ]]; then
    case "$t" in
      default) node -e 'process.exit(Number(process.argv[1]) <= 150 ? 0 : 1)' "$s" || log_fail "TEST-3569: the default matrix took ${s}s, bound 150 s" ;;
      smoke) node -e 'process.exit(Number(process.argv[1]) <= 75 ? 0 : 1)' "$s" || log_fail "TEST-3569: the smoke matrix took ${s}s, bound 75 s" ;;
      *) log_info "TEST-3569: no bound is defined for the $t matrix" ;;
    esac
  fi
  log_pass "TEST-3569: the tier switch and the per-scenario and total seconds hold"
}

test_3570_trackers() {
  run_node_tests TEST-3570
  log_pass "TEST-3570: every allowlist tracker is accepted or a known follow-up naming the row's path; the seven seed ids exist"
}

selected_in() {
  node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$2" --repo-root "$1"
}

test_3571_wiring() {
  need_tool TEST-3571 node || return 0
  local f out n tsv="$SCRIPT_DIR/suite-weights.tsv" wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" e push pr
  mkdir -p "$TEST_DIR/t3571"
  for f in .aai/scripts/aai-sync.sh .aai/scripts/aai-sync.ps1 .aai/scripts/aai-update.sh .aai/scripts/aai-update.ps1 \
    .aai/scripts/install-pre-commit-hook.sh .aai/scripts/install-pre-commit-hook.ps1 \
    tests/skills/lib/install-parity.mjs tests/skills/lib/install-parity-allowlist.tsv tests/skills/install-parity.Tests.ps1; do
    printf '%s\n' "$f" > "$TEST_DIR/t3571/files.txt"
    out="$(selected_in "$PROJECT_ROOT" "$TEST_DIR/t3571/files.txt")"
    [[ "$out" == *'SELECTED aai-install-parity '* ]] || log_fail "TEST-3571: $f does not select aai-install-parity: $out"
  done
  n="$(awk -F'\t' '$1=="aai-install-parity" && $2==196{c++} END{print c+0}' "$tsv")"
  [[ "$n" == 1 ]] || log_fail "TEST-3571: suite-weights holds $n aai-install-parity rows at 196, expected 1"
  grep -qxF '# sample aai-install-parity fallback unsampled (new suite of install-path-parity-harness; no successful observation)' "$tsv" || log_fail "TEST-3571: suite-weights lacks the aai-install-parity fallback line"
  for f in test_090_suite_map_pin test_129_mutation_gate_suite_registration; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-hygiene-pack.sh" "$f" >"$TEST_DIR/t3571.out" 2>&1 || { tail -n 8 "$TEST_DIR/t3571.out" >&2; log_fail "TEST-3571: test-aai-hygiene-pack.sh $f failed"; }
  done
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-win-fallback.sh" test_034 >"$TEST_DIR/t3571.out" 2>&1 || { tail -n 8 "$TEST_DIR/t3571.out" >&2; log_fail "TEST-3571: test-aai-win-fallback.sh test_034 failed"; }
  node "$SCRIPT_DIR/lib/nested-suite-lint.mjs" --allowlist "$SCRIPT_DIR/lib/nested-suite-allowlist.tsv" "$SCRIPT_DIR" >/dev/null 2>&1 || log_fail "TEST-3571: nested-suite-lint failed"
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >/dev/null 2>&1 || log_fail "TEST-3571: check-cd-subshell-leak.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$SCRIPT_DIR" >/dev/null 2>&1 || log_fail "TEST-3571: check-test-registration.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" >/dev/null 2>&1 || log_fail "TEST-3571: check-vendored-script-deps.mjs failed"
  push="$(awk '/^  push:/{s=1;next} /^  pull_request:/{s=0} s && /^      - /' "$wf")"
  pr="$(awk '/^  pull_request:/{s=1;next} /^  workflow_dispatch/{s=0} s && /^      - /' "$wf")"
  [[ -n "$push" && "$push" == "$pr" ]] || log_fail "TEST-3571: the push and pull_request path lists of ps1-quality.yml differ or are empty"
  for e in .aai/scripts/aai-sync.sh .aai/scripts/aai-update.sh .aai/scripts/install-pre-commit-hook.sh .aai/scripts/lib/gitignore-block.sh \
    .aai/scripts/lib/merge-hooks-json.mjs 'hooks/**' tests/skills/lib/install-parity.mjs tests/skills/lib/install-parity-allowlist.tsv; do
    [[ $'\n'"$push"$'\n' == *$'\n'"      - '$e'"$'\n'* ]] || log_fail "TEST-3571: the ps1-quality.yml path lists lack $e"
  done
  # The Windows parity Pester runs in its own job (own timeout, own elapsed line) under both engines and is excluded from the
  # full-suite steps that carry the 600 s ceiling, in both Windows jobs.
  local jobs blk n
  blk="$(awk '/^  windows-parity:/{s=1;print;next} s && /^  [a-z0-9_-]+:/{s=0} s' "$wf")"
  [[ -n "$blk" ]] || log_fail "TEST-3571: ps1-quality.yml has no windows-parity job"
  [[ "$blk" == *'runs-on: windows-latest'* ]] || log_fail "TEST-3571: windows-parity does not run on windows-latest"
  [[ "$blk" == *'timeout-minutes: 20'* ]] || log_fail "TEST-3571: windows-parity has no job-level timeout"
  n="$(grep -cF "Run.Path = 'tests/skills/install-parity.Tests.ps1'" <<< "$blk" || true)"
  [[ "$n" == 2 ]] || log_fail "TEST-3571: windows-parity runs the parity file $n times, expected 2 (Windows PowerShell 5.1 and pwsh 7)"
  [[ "$blk" == *'shell: powershell'* && "$blk" == *'shell: pwsh'* ]] || log_fail "TEST-3571: windows-parity does not use both shells"
  n="$(grep -cF 'AAI-PARITY-ELAPSED' <<< "$blk" || true)"
  [[ "$n" -ge 2 ]] || log_fail "TEST-3571: windows-parity prints AAI-PARITY-ELAPSED $n times, expected one per engine"
  [[ "$blk" != *"Run.Path = 'tests/skills'"* ]] || log_fail "TEST-3571: windows-parity discovers the whole suite"
  for jobs in windows-5_1 windows-wsl1; do
    blk="$(awk -v j="  $jobs:" '$0==j{s=1;next} s && /^  [a-z0-9_-]+:/{s=0} s' "$wf")"
    n="$(grep -cF "Run.Path = 'tests/skills'" <<< "$blk" || true)"
    [[ "$n" -ge 1 ]] || log_fail "TEST-3571: $jobs has no full-suite discovery step"
    [[ "$(grep -cF "Run.ExcludePath = @('*install-parity.Tests.ps1')" <<< "$blk" || true)" == "$n" ]] || log_fail "TEST-3571: a full-suite discovery step of $jobs does not exclude install-parity.Tests.ps1"
  done
  log_pass "TEST-3571: select-suites, the weights row, the hygiene pins, the lints and the ps1-quality path lists know the new suite"
}

test_3572_rfc() {
  need_tool TEST-3572 node || return 0
  local rfc="$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md" row n sentence
  sentence='The thirteenth slice [ran both twins of the install path into scratch targets](../issues/CHANGE-DRAFT-install-path-parity-harness.md): a test-only harness compares the trees and exit codes of the bash and PowerShell twins of aai-sync, aai-update and the hook installer, with each known divergence on a reviewed list, and takes the Node twins of the later rides as a third twin.'
  row=""
  while IFS= read -r l; do
    case "$l" in '| 5 |'*) row="$l" ;; esac
  done < "$rfc"
  [[ -n "$row" ]] || log_fail "TEST-3572: RFC-0017 has no phase 5 table row"
  [[ "$row" == *'in progress'* ]] || log_fail "TEST-3572: the phase 5 row no longer has status in progress"
  n="$(node -e '
    const row = process.argv[1], s = process.argv[2];
    let c = 0, i = -1; while ((i = row.indexOf(s, i + 1)) >= 0) c += 1; process.stdout.write(String(c));
    const m = s.match(/\(([^)]*)\)/); if (!m || !/install-path-parity-harness\.md$/.test(m[1])) process.exit(2);
  ' "$row" "$sentence")" || log_fail "TEST-3572: the sentence link does not end install-path-parity-harness.md"
  [[ "$n" == 1 ]] || log_fail "TEST-3572: the RFC-0017 phase 5 row holds the thirteenth-slice sentence $n times, expected once"
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree >"$TEST_DIR/t3572.out" 2>&1 || { tail -n 8 "$TEST_DIR/t3572.out" >&2; log_fail "TEST-3572: test-aai-expert-fetch.sh test_2624_inventory_matches_tree failed"; }
  log_pass "TEST-3572: RFC-0017 phase 5 keeps in progress and holds the D-RFC sentence once; the inventory check passes"
}

main() {
  check_deps
  setup_fixture
  test_3560_matrix_tiers
  test_3561_compare_kinds
  test_3562_normalizations
  test_3563_allowlist
  test_3564_broken
  test_3565_default_matrix
  test_3566_third_twin
  test_3567_environment
  test_3568_pester
  test_3569_tiers_and_timing
  test_3570_trackers
  test_3571_wiring
  test_3572_rfc
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Sourced (by parity_matrix probes) the file only defines functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
