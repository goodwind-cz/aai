#!/usr/bin/env bash
#
# Test: aai-cloudflare-share
# (docs/specs/SPEC-0276-spec-cloudflare-share-on-node.md, TEST-3416..3431)
#
# cloudflare-share is one Node module (.aai/scripts/cloudflare-share.mjs) behind thin sh/ps1 launchers.
# Every case works in fresh mktemp fixtures with a stub wrangler first on PATH; no case runs a real
# wrangler or reaches the network, and nothing touches the repository checkout.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-cloudflare-share.sh                      # run all
#   bash tests/skills/test-aai-cloudflare-share.sh test_3416_seam
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-cloudflare-share"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MJS="$PROJECT_ROOT/.aai/scripts/cloudflare-share.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/cloudflare-share.test.mjs"
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/cloudflare-share.sh"
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/cloudflare-share.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/cloudflare-share.Tests.ps1"
SPEC_ID="spec-cloudflare-share-on-node"
URL1="https://abc123.my-repo.aai-reports.pages.dev"
REFUSED="cloudflare-share: refused - node not found in PATH or cloudflare-share.mjs missing; nothing was published. Install Node.js 22 or later (https://nodejs.org/) and re-run."
USAGE="Usage: cloudflare-share <document.md>"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
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
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-cloudflare-share-suite.XXXXXX")" && pwd -P)"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/cloudflare-share.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/cloudflare-share.test.mjs does not exist"
  out="$(env -u AAI_ROLE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
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

# make_stub <bin dir>: a POSIX wrangler stub that records its argv and prints the deployment URL.
make_stub() {
  mkdir -p "$1"
  {
    echo '#!/bin/sh'
    echo 'printf "%s\n" "$@" > "$(dirname "$0")/argv.txt"'
    echo "echo ' Deployment complete! Take a peek over at'"
    echo "echo ' $URL1'"
  } > "$1/wrangler"
  chmod +x "$1/wrangler"
}

# make_repo <dir>: a committed git repository with doc.md (the directory name is the caller's choice).
make_repo() {
  mkdir -p "$1"
  printf '# Title\n\nbody\n' > "$1/doc.md"
  git -C "$1" init -q
  git -C "$1" config user.email fixture@example.invalid
  git -C "$1" config user.name fixture
  git -C "$1" config commit.gpgsign false
  git -C "$1" add -A
  git -C "$1" commit -q -m fixture
}

# expected_out <branch>: the D-OUT stdout for doc.md.
expected_out() {
  printf '%s\n' 'Converting Markdown to HTML...' 'Converted: doc.md' 'Output: .cloudflare-publish/index.html' 'Images: 0' \
    "Deploying to Cloudflare Pages (branch: $1)..." '' 'Document published successfully!' '' 'Document: doc' "URL: $URL1" '' "Click to open: $URL1" ''
}

# assert_published <TEST id> <label> <fixture> <stdout file> <stderr file> <rc> [records]: D-OUT, no stderr, one record, no publish dir.
assert_published() {
  local id="$1" label="$2" fx="$3" so="$4" se="$5" rc="$6" want="${7:-1}" n
  [[ "$rc" == 0 ]] || { cat "$so" "$se" >&2; log_fail "$id: $label exited $rc"; }
  [[ "$(cat "$so")" == "$(expected_out my-repo)" ]] || { cat "$so" >&2; log_fail "$id: $label stdout differs from the D-OUT contract"; }
  [[ ! -s "$se" ]] || log_fail "$id: $label wrote to stderr: $(cat "$se")"
  [[ ! -e "$fx/.cloudflare-publish" ]] || log_fail "$id: $label left .cloudflare-publish"
  n="$(wc -l < "$fx/docs/ai/published/history.jsonl" | tr -d ' ')"
  [[ "$n" == "$want" ]] || log_fail "$id: $label history holds $n lines, expected $want"
}

# launcher_problems <file> <sh|ps1>: prints problems of one cloudflare-share launcher (empty when clean).
launcher_problems() {
  node -e '
    const fs = require("fs");
    const [file, kind] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    if (!s.includes("cloudflare-share.mjs")) bad.push("does not name cloudflare-share.mjs");
    if (!s.includes("cloudflare-share: refused - node not found in PATH or cloudflare-share.mjs missing; nothing was published. Install Node.js 22 or later (https://nodejs.org/) and re-run.")) bad.push("lacks the refusal line");
    if (/grep/i.test(s)) bad.push("holds the word grep");
    if (kind === "sh") {
      if (s.split("\n")[0] !== "#!/bin/sh") bad.push("first line is not #!/bin/sh");
      if (s.includes("[[")) bad.push("holds [[");
      if (s.includes("BASH_SOURCE")) bad.push("holds BASH_SOURCE");
    } else {
      if (!s.includes("[CmdletBinding()] param([Parameter(Position = 0)][string]$DocumentPath)")) bad.push("lacks the D-LAUNCH param line");
      if (/Mandatory/i.test(s)) bad.push("holds Mandatory");
    }
    for (const w of ["wrangler", "history.jsonl", "docs/ai/", ".cloudflare-publish"]) {
      if (s.includes(w)) bad.push("holds forbidden string " + w);
    }
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

# code_lines <file> <comment prefix: # or //>: non-blank, non-comment lines (the plan's method).
code_lines() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -cvE "^[[:space:]]*($2|\$)" "$1" || true
}

test_3416_seam() {
  run_node_tests TEST-3416
  log_pass "TEST-3416: importing the module has no side effect and run drives the convert and deploy seams"
}

test_3417_cli_success() {
  run_node_tests TEST-3417
  log_pass "TEST-3417: the module CLI meets the D-OUT contract in a repo named My Repo with a stub wrangler"
}

test_3418_args_drift() {
  run_node_tests TEST-3418
  log_pass "TEST-3418: DR-01 to DR-05 and DR-19 behave as decided"
}

test_3419_deploy_drift() {
  run_node_tests TEST-3419
  log_pass "TEST-3419: DR-06 to DR-12 and DR-18 behave as decided"
}

test_3420_record_drift() {
  run_node_tests TEST-3420
  log_pass "TEST-3420: DR-13 to DR-17 record shape and output behave as decided"
}

test_3421_secrets() {
  run_node_tests TEST-3421
  log_pass "TEST-3421: DR-21 credentials reach wrangler and are redacted from the failure echo"
}

# drift_problems <spec> <node test file>: DR ids of the D-DRIFT table vs test names (empty when they agree).
drift_problems() {
  cat > "$TEST_DIR/drift.cjs" <<'JS'
const fs = require('fs');
const [spec, tests] = process.argv.slice(2);
const table = fs.readFileSync(spec, 'utf8').split('\n').map((l) => l.match(/^\| (DR-\d\d) \|/)).filter(Boolean).map((m) => m[1]);
const names = [...fs.readFileSync(tests, 'utf8').matchAll(/^test\('(?:TEST-\d+ )?(DR-\d\d)\b/gm)].map((m) => m[1]);
const bad = [];
for (const id of table) { const n = names.filter((x) => x === id).length; if (n !== 1) bad.push(`${id} begins ${n} test names`); }
for (const id of new Set(names)) if (!table.includes(id)) bad.push(`${id} is not in the D-DRIFT table`);
if (table.length !== 21) bad.push(`the table holds ${table.length} ids, expected 21`);
process.stdout.write(bad.join('; '));
JS
  node "$TEST_DIR/drift.cjs" "$1" "$2"
}

test_3422_drift_coverage() {
  local spec="" out f
  for f in "$PROJECT_ROOT"/docs/specs/*.md; do
    if grep -qx "id: $SPEC_ID" "$f"; then spec="$f"; break; fi
  done
  [[ -n "$spec" ]] || log_fail "TEST-3422: no spec with id $SPEC_ID under docs/specs"
  out="$(drift_problems "$spec" "$NODE_TEST")"
  [[ -z "$out" ]] || log_fail "TEST-3422: $out"
  sed "s/'TEST-3420 DR-13 /'TEST-3420 DR-31 /" "$NODE_TEST" > "$TEST_DIR/renamed.test.mjs"
  out="$(drift_problems "$spec" "$TEST_DIR/renamed.test.mjs")"
  [[ "$out" == *"DR-13 begins 0"* && "$out" == *"DR-31 is not in"* ]] || log_fail "TEST-3422: positive control: the renamed DR-13 was not reported ($out)"
  log_pass "TEST-3422: every D-DRIFT id begins exactly one node:test case and no case names a missing id"
}

test_3423_sh_launcher() {
  local out mode rep fx="$TEST_DIR/sh fx/My Repo" bin="$TEST_DIR/sh fx/bin" sh sh_path so="$TEST_DIR/s.out" se="$TEST_DIR/s.err" rc
  out="$(launcher_problems "$SH_LAUNCHER" sh)"; [[ -z "$out" ]] || log_fail "TEST-3423: sh launcher: $out"
  mode="$(git -C "$PROJECT_ROOT" ls-files -s -- .aai/scripts/cloudflare-share.sh | cut -d' ' -f1)"
  [[ "$mode" == 100644 ]] || log_fail "TEST-3423: sh launcher git mode is '$mode', not 100644"
  rep="$TEST_DIR/ctl.sh"; { cat "$SH_LAUNCHER"; echo '# grep'; } > "$rep"
  out="$(launcher_problems "$rep" sh)"
  [[ "$out" == *"grep"* ]] || log_fail "TEST-3423: positive control: a launcher holding grep was not reported"
  make_stub "$bin"
  for sh in bash sh dash; do
    sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3423 needs $sh"; continue; }
    rm -rf "$fx"; make_repo "$fx"
    rc=0; ( cd "$fx" && PATH="$bin:$PATH" "$sh_path" "$SH_LAUNCHER" doc.md ) >"$so" 2>"$se" || rc=$?
    assert_published TEST-3423 "sh launcher under $sh" "$fx" "$so" "$se" "$rc"
  done
  run_node_tests TEST-3423
  log_pass "TEST-3423: the sh launcher is thin, meets D-OUT under bash, sh and dash and refuses without node (DR-20)"
}

test_3424_ps1_launcher() {
  need_tool TEST-3424 pwsh || return 0
  local out mode fx="$TEST_DIR/ps fx/My Repo" bin="$TEST_DIR/ps fx/bin" so="$TEST_DIR/p.out" se="$TEST_DIR/p.err" rc
  out="$(launcher_problems "$PS1_LAUNCHER" ps1)"; [[ -z "$out" ]] || log_fail "TEST-3424: ps1 launcher: $out"
  mode="$(git -C "$PROJECT_ROOT" ls-files -s -- .aai/scripts/cloudflare-share.ps1 | cut -d' ' -f1)"
  [[ "$mode" == 100644 ]] || log_fail "TEST-3424: ps1 launcher git mode is '$mode', not 100644"
  make_stub "$bin"; make_repo "$fx"; mv "$fx/doc.md" "$fx/my doc.md"; git -C "$fx" add -A; git -C "$fx" commit -q -m rename
  rc=0; ( cd "$fx" && PATH="$bin:$PATH" pwsh -NoProfile -NonInteractive -File "$PS1_LAUNCHER" "my doc.md" ) >"$so" 2>"$se" || rc=$?
  [[ "$rc" == 0 ]] || { cat "$so" "$se" >&2; log_fail "TEST-3424: ps1 with a spaced path exited $rc"; }
  [[ "$(cat "$so")" == "$(expected_out my-repo | sed 's/doc\.md/my doc.md/; s/^Document: doc$/Document: my doc/')" ]] || { cat "$so" >&2; log_fail "TEST-3424: ps1 stdout differs from the D-OUT contract"; }
  [[ ! -s "$se" && ! -e "$fx/.cloudflare-publish" ]] || log_fail "TEST-3424: ps1 wrote stderr or left the publish dir"
  [[ "$(wc -l < "$fx/docs/ai/published/history.jsonl" | tr -d ' ')" == 1 ]] || log_fail "TEST-3424: ps1 did not record exactly one line"
  rm -rf "$fx/docs"
  rc=0; ( cd "$fx" && PATH="$bin:$PATH" pwsh -NoProfile -NonInteractive -File "$PS1_LAUNCHER" ) >"$so" 2>"$se" || rc=$?
  [[ "$rc" == 1 && ! -s "$so" && "$(cat "$se")" == "$USAGE" ]] || log_fail "TEST-3424: ps1 without an argument gave rc=$rc stderr=$(cat "$se")"
  [[ ! -e "$fx/.cloudflare-publish" && ! -e "$fx/docs" ]] || log_fail "TEST-3424: ps1 without an argument created something"
  log_pass "TEST-3424: the ps1 launcher is thin, meets D-OUT with a spaced path and prints the usage line without a prompt"
}

test_3425_pester() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3425: tests/skills/cloudflare-share.Tests.ps1 does not exist"
  need_tool TEST-3425 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3425 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PESTER_FILE="$PESTER_FILE" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 5) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3425: cloudflare-share.Tests.ps1 failed, skipped a case or ran fewer than 5 cases (rc=$rc)"; }
  log_pass "TEST-3425: cloudflare-share.Tests.ps1 passes with no skip under pwsh ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

test_3426_bsd_grep() {
  local fx="$TEST_DIR/grep fx/My Repo" bin="$TEST_DIR/grep fx/bin" shim="$TEST_DIR/grep fx/shim" so="$TEST_DIR/g.out" se="$TEST_DIR/g.err" rc f
  make_stub "$bin"; make_repo "$fx"; mkdir -p "$shim"
  printf '%s\n' '#!/bin/sh' 'for a in "$@"; do case "$a" in -*P*) echo "grep: invalid option -- P" >&2; exit 2;; esac; done' 'exec /usr/bin/grep "$@"' > "$shim/grep"
  chmod +x "$shim/grep"
  [[ -x /usr/bin/grep ]] || printf '%s\n' '#!/bin/sh' 'exit 2' > "$shim/grep"
  rc=0; ( cd "$fx" && PATH="$shim:$bin:$PATH" bash "$SH_LAUNCHER" doc.md ) >"$so" 2>"$se" || rc=$?
  assert_published TEST-3426 "sh launcher with a grep that rejects -P" "$fx" "$so" "$se" "$rc"
  for f in "$MJS" "$SH_LAUNCHER" "$PS1_LAUNCHER"; do
    [[ -f "$f" ]] || log_fail "TEST-3426: $f does not exist"
    if tr 'A-Z' 'a-z' < "$f" | tr -c 'a-z\n' ' ' | tr ' ' '\n' | awk '$0=="grep"{f=1} END{exit f?0:1}'; then log_fail "TEST-3426: $f holds the word grep"; fi
  done
  log_pass "TEST-3426: a grep that rejects -P does not stop the share, and no file holds the word grep"
}

test_3427_downstream_install() {
  local ext="$TEST_DIR/ext target" core="$TEST_DIR/core target" bin="$TEST_DIR/inst-bin" so="$TEST_DIR/i.out" se="$TEST_DIR/i.err" f rc n
  make_stub "$bin"
  make_repo "$ext"; make_repo "$core"
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$ext" --profile extended >/dev/null 2>&1 || log_fail "TEST-3427: aai-sync.sh --profile extended failed"
  for f in cloudflare-share.mjs cloudflare-share.sh cloudflare-share.ps1 share-convert.mjs; do
    [[ -f "$ext/.aai/scripts/$f" ]] || log_fail "TEST-3427: the extended install lacks .aai/scripts/$f"
  done
  rc=0; ( cd "$ext" && PATH="$bin:$PATH" bash .aai/scripts/cloudflare-share.sh doc.md ) >"$so" 2>"$se" || rc=$?
  [[ "$rc" == 0 && ! -s "$se" ]] || { cat "$so" "$se" >&2; log_fail "TEST-3427: the target's own sh launcher exited $rc"; }
  grep -qxF "URL: $URL1" "$so" || log_fail "TEST-3427: the target's sh launcher did not print the URL"
  if need_tool TEST-3427 pwsh; then
    rc=0; ( cd "$ext" && PATH="$bin:$PATH" pwsh -NoProfile -NonInteractive -File .aai/scripts/cloudflare-share.ps1 doc.md ) >"$so" 2>"$se" || rc=$?
    [[ "$rc" == 0 && ! -s "$se" ]] || { cat "$so" "$se" >&2; log_fail "TEST-3427: the target's own ps1 launcher exited $rc"; }
    grep -qxF "URL: $URL1" "$so" || log_fail "TEST-3427: the target's ps1 launcher did not print the URL"
    n=2
  else
    n=1
  fi
  [[ "$(wc -l < "$ext/docs/ai/published/history.jsonl" | tr -d ' ')" == "$n" ]] || log_fail "TEST-3427: the target history does not hold $n records"
  [[ ! -e "$ext/.cloudflare-publish" ]] || log_fail "TEST-3427: the target kept .cloudflare-publish"
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$core" --profile core >/dev/null 2>&1 || log_fail "TEST-3427: aai-sync.sh --profile core failed"
  for f in cloudflare-share.mjs cloudflare-share.sh cloudflare-share.ps1; do
    [[ ! -e "$core/.aai/scripts/$f" ]] || log_fail "TEST-3427: the core install holds .aai/scripts/$f"
  done
  log_pass "TEST-3427: an extended install publishes through its own launchers; a core install holds no cloudflare-share file"
}

test_3428_wiring() {
  local f out n wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" tsv="$PROJECT_ROOT/tests/skills/suite-weights.tsv" nsl="$PROJECT_ROOT/tests/skills/lib/nested-suite-lint.mjs"
  for f in .aai/scripts/cloudflare-share.mjs .aai/scripts/cloudflare-share.sh .aai/scripts/cloudflare-share.ps1 tests/skills/lib/cloudflare-share.test.mjs tests/skills/cloudflare-share.Tests.ps1; do
    out="$(printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")"
    [[ "$out" == *'SELECTED aai-cloudflare-share '* ]] || log_fail "TEST-3428: $f does not select aai-cloudflare-share: $out"
  done
  n="$(awk -F'\t' '$1=="aai-cloudflare-share"{c++} END{print c+0}' "$tsv")"
  [[ "$n" == 1 ]] || log_fail "TEST-3428: suite-weights holds $n aai-cloudflare-share rows, expected 1"
  for f in test_090_suite_map_pin test_129_mutation_gate_suite_registration; do
    env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-hygiene-pack.sh" "$f" >/dev/null 2>&1 || log_fail "TEST-3428: test-aai-hygiene-pack.sh $f failed"
  done
  n="$(grep -c '^  aai-[a-z0-9-]*:$' "$PROJECT_ROOT/tests/skills/suite-map.yaml" || true)"
  [[ "$n" == 128 ]] || log_fail "TEST-3428: suite-map.yaml holds $n suite rows, expected 128"
  node "$nsl" --allowlist "$PROJECT_ROOT/tests/skills/lib/nested-suite-allowlist.tsv" "$PROJECT_ROOT/tests/skills" >/dev/null 2>&1 || log_fail "TEST-3428: nested-suite-lint failed"
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >/dev/null 2>&1 || log_fail "TEST-3428: check-cd-subshell-leak.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$PROJECT_ROOT/tests/skills" >/dev/null 2>&1 || log_fail "TEST-3428: check-test-registration.mjs failed"
  n="$(awk '/^extended:/{f=1;next} /^[a-z]/{f=0} f && $0=="  - .aai/scripts/cloudflare-share.mjs"{c++} END{print c+0}' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
  [[ "$n" == 1 ]] || log_fail "TEST-3428: PROFILES extended lists the module $n times, expected 1"
  env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-layer-profiles.sh" test_manifest_conformance >/dev/null 2>&1 || log_fail "TEST-3428: test-aai-layer-profiles.sh test_manifest_conformance failed"
  n="$(awk '/^  push:/{s="push"} /^  pull_request:/{s="pr"} /^  workflow_dispatch/{s=""} s!="" && $0=="      - '"'"'.aai/scripts/cloudflare-share.mjs'"'"'"{c[s]++} END{print c["push"]+0, c["pr"]+0}' "$wf")"
  [[ "$n" == "1 1" ]] || log_fail "TEST-3428: the ps1-quality path lists hold the module '$n' times (push pr), expected 1 1"
  env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-win-fallback.sh" test_034 >/dev/null 2>&1 || log_fail "TEST-3428: test-aai-win-fallback.sh test_034 failed"
  log_pass "TEST-3428: suite-map, weights, hygiene pins, lints, PROFILES and both ps1-quality path lists are wired"
}

RFC17="${CFS_RFC:-$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md}"
D_RFC_SENTENCE='The seventh slice [moved cloudflare-share to Node](../issues/CHANGE-0248-cloudflare-share-on-node.md): one module with an injectable deploy seam behind thin launchers, which ends the macOS grep -oP failure and the twins'"'"' drift.'

test_3429_rfc() {
  local row n out rc=0
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3429: test_2624_inventory_matches_tree exited $rc"; }
  n="$(grep -c '^| `cloudflare-share` |' "$RFC17" || true)"
  [[ "$n" == 0 ]] || log_fail "TEST-3429: the inventory still has a cloudflare-share row"
  row="$(grep '^| 5 | ' "$RFC17" || true)"
  [[ "$row" == *'| in progress |'* ]] || log_fail "TEST-3429: the phase 5 row is not in progress"
  [[ "$row" == *"$D_RFC_SENTENCE"* ]] || log_fail "TEST-3429: the phase 5 row lacks the D-RFC sentence"
  n="$(grep -cF -- "$D_RFC_SENTENCE" "$RFC17" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3429: the D-RFC sentence appears $n times, expected once"
  grep -qF 'cloudflare-share.mjs' "${CFS_TECH:-$PROJECT_ROOT/docs/TECHNOLOGY.md}" || log_fail "TEST-3429: docs/TECHNOLOGY.md does not name cloudflare-share.mjs"
  log_pass "TEST-3429: the RFC-0017 inventory equals the tree, the phase 5 row holds the D-RFC sentence once and TECHNOLOGY names the module"
}

test_3430_line_budget() {
  local d="${CFS_BUDGET_DIR:-$PROJECT_ROOT/.aai/scripts}" f n sum=0 total mod
  n="$(code_lines "$d/cloudflare-share.sh" '#')"
  [[ "$n" -le 6 ]] || log_fail "TEST-3430: cloudflare-share.sh has $n code lines, expected at most 6"
  sum=$((sum + n))
  n="$(code_lines "$d/cloudflare-share.ps1" '#')"
  [[ "$n" -le 10 ]] || log_fail "TEST-3430: cloudflare-share.ps1 has $n code lines, expected at most 10"
  sum=$((sum + n))
  for f in cloudflare-share.sh cloudflare-share.ps1; do
    total="$(wc -l < "$d/$f" | tr -d ' ')"
    [[ "$total" -le 20 ]] || log_fail "TEST-3430: $f has $total lines, expected at most 20"
  done
  mod="$(code_lines "$d/cloudflare-share.mjs" '//')"
  log_pass "TEST-3430: code lines before 98, after launchers $sum plus module $mod"
}

# caller_problems <prompt>: problems with the SKILL_SHARE Scripts line and every script path the wrappers name.
caller_problems() {
  cat > "$TEST_DIR/callers.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
const [root, prompt, mjs] = process.argv.slice(2);
const bad = [];
const files = [prompt, ...['.claude', '.agents', '.codex', '.gemini'].map((d) => path.join(root, d, 'skills/aai-share/SKILL.md'))];
const scripts = fs.readFileSync(prompt, 'utf8').split('\n').find((l) => /non-agent use/.test(l)) || '';
for (const n of ['.aai/scripts/cloudflare-share.sh', '.aai/scripts/cloudflare-share.ps1']) if (!scripts.includes(n)) bad.push(`the Scripts line lacks ${n}`);
for (const f of files) {
  if (!fs.existsSync(f)) { bad.push(`${f} is missing`); continue; }
  for (const m of fs.readFileSync(f, 'utf8').matchAll(/\.aai\/scripts\/[A-Za-z0-9_.\/-]+\.(?:mjs|sh|ps1)/g)) {
    if (!fs.existsSync(path.join(root, m[0]))) bad.push(`${m[0]} does not exist`);
  }
}
if (!fs.existsSync(mjs) || !fs.readFileSync(mjs, 'utf8').includes('share-convert.mjs')) bad.push('the module does not name share-convert.mjs');
process.stdout.write(bad.join('; '));
JS
  node "$TEST_DIR/callers.cjs" "$PROJECT_ROOT" "$1" "$MJS"
}

test_3431_callers() {
  local prompt="${CFS_PROMPT:-$PROJECT_ROOT/.aai/SKILL_SHARE.prompt.md}" out
  out="$(caller_problems "$prompt")"
  [[ -z "$out" ]] || log_fail "TEST-3431: $out"
  sed 's#\.aai/scripts/cloudflare-share\.ps1#.aai/scripts/cloudflare-share-gone.ps1#' "$prompt" > "$TEST_DIR/prompt-copy.md"
  out="$(caller_problems "$TEST_DIR/prompt-copy.md")"
  [[ "$out" == *"cloudflare-share.ps1"* ]] || log_fail "TEST-3431: positive control: a prompt naming a missing script was not reported ($out)"
  log_pass "TEST-3431: SKILL_SHARE and the four wrappers name only existing scripts and the module runs share-convert.mjs"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3416..3431)"
  check_deps
  setup_fixture
  test_3416_seam
  test_3417_cli_success
  test_3418_args_drift
  test_3419_deploy_drift
  test_3420_record_drift
  test_3421_secrets
  test_3422_drift_coverage
  test_3423_sh_launcher
  test_3424_ps1_launcher
  test_3425_pester
  test_3426_bsd_grep
  test_3427_downstream_install
  test_3428_wiring
  test_3429_rfc
  test_3430_line_budget
  test_3431_callers
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
