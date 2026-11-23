#!/usr/bin/env bash
#
# Test: aai-phase5-closeout
# (docs/specs/SPEC-DRAFT-spec-node-first-phase5-closeout.md; TEST-4024, TEST-4035 here, TEST-4033, TEST-4034 and
# TEST-4036 as the later steps of the ride land)
#
# The classification and record half of the RFC-0017 phase 5 closeout. TEST-4024 reads the Kept native scripts table of
# RFC-0017 through parseKeptNative of tests/skills/lib/script-classes.mjs; TEST-4035 installs the extended profile with
# aai-sync.mjs into a scratch target and runs every launcher of the shared classifier from that install. Scratch
# directories carry this suite's own prefix and ownership marker and are removed by a trap also on failure; nothing here
# syncs, updates, installs hooks or releases into this repository or any real one, starts a container tool, kills by
# pattern or reaches the network.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-phase5-closeout.sh                 # run all
#   bash tests/skills/test-aai-phase5-closeout.sh test_4024_kept_native_rows
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-phase5-closeout"
OWN_PREFIX="aai-phase5-closeout."
OWN_MARKER=".aai-p5c-owned"

# The script directory without a cd inside a command substitution (the cd-subshell ratchet).
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR="."
case "$SCRIPT_DIR" in /*) ;; *) SCRIPT_DIR="$PWD/$SCRIPT_DIR" ;; esac

# phys_path <path>: the physical absolute path (symlinks resolved); empty and failing when it does not exist.
phys_path() {
  node -e 'try { process.stdout.write(require("fs").realpathSync(process.argv[1])); } catch (e) { process.exit(1); }' "$1"
}

PROJECT_ROOT="$(phys_path "$SCRIPT_DIR/../..")"
SPEC_ID="node-first-phase5-closeout"
CLASSES_LIB="$PROJECT_ROOT/tests/skills/lib/script-classes.mjs"
RFC_REL="docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

# safe_rm_own <path>...: removes only scratch directories this suite created. It fails the test (never
# skips) for no path at all, an empty path, a relative path, a basename without the own prefix, a path
# outside the temp directory, a symbolic link and a directory without the numeric ownership marker; the
# marker is read again right before the removal.
safe_rm_own() {
  [[ "$#" -gt 0 ]] || log_fail "safe_rm_own: an empty list of paths to remove is a failure"
  local p base real tmp_real
  for p in "$@"; do
    [[ -n "$p" ]] || log_fail "safe_rm_own: empty path"
    [[ "$p" == /* ]] || log_fail "safe_rm_own: relative path: $p"
    base="${p%/}"
    base="${base##*/}"
    [[ "$base" == "$OWN_PREFIX"* ]] || log_fail "safe_rm_own: basename lacks the own prefix $OWN_PREFIX: $p"
    [[ -d "$p" && ! -L "$p" ]] || log_fail "safe_rm_own: not a real directory: $p"
    real="$(phys_path "$p")" || log_fail "safe_rm_own: cannot resolve $p"
    tmp_real="$(phys_path "${TMPDIR:-/tmp}")" || log_fail "safe_rm_own: cannot resolve the temp directory"
    case "$real" in "$tmp_real"/*) ;; *) log_fail "safe_rm_own: outside the temp directory: $p" ;; esac
    [[ "$(cat "$real/$OWN_MARKER" 2>/dev/null)" =~ ^[0-9]+$ ]] || log_fail "safe_rm_own: no ownership marker in $p"
    rm -rf -- "$real"
  done
}

# new_own_scratch <label>: prints a fresh own scratch directory (own prefix, marker holding this process id).
new_own_scratch() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/${OWN_PREFIX}$1.XXXXXX")" || log_fail "mktemp failed"
  d="$(phys_path "$d")"
  printf '%s\n' "$$" > "$d/$OWN_MARKER"
  printf '%s\n' "$d"
}

cleanup() {
  # A failed test leaves its own scratch behind: sweep, through safe_rm_own, exactly the directories of the own
  # prefix whose marker holds this process id. Leftovers of other runs carry another id and are not touched.
  local d mine=()
  for d in "${TMPDIR:-/tmp}/${OWN_PREFIX}"*; do
    [[ -d "$d" && ! -L "$d" && "$(cat "$d/$OWN_MARKER" 2>/dev/null)" == "$$" ]] && mine+=("$d")
  done
  if [[ "${#mine[@]}" -gt 0 ]]; then safe_rm_own "${mine[@]}"; fi
  return 0
}
trap cleanup EXIT

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$CLASSES_LIB" ]] || log_fail "missing tests/skills/lib/script-classes.mjs"
  log_pass "Dependencies checked"
}

# TEST-4024 (D-KEPT): the Kept native scripts table of RFC-0017 holds exactly nine rows, read through the shared
# parser: the four old rows byte for byte, then the five new files in the D-KEPT order, every reason non-empty.
test_4024_kept_native_rows() {
  local out
  out="$(T4024_LIB="$CLASSES_LIB" T4024_RFC="$PROJECT_ROOT/$RFC_REL" node --input-type=module -e '
    import fs from "node:fs";
    const { parseKeptNative } = await import(process.env.T4024_LIB);
    const text = fs.readFileSync(process.env.T4024_RFC, "utf8");
    const rows = parseKeptNative(text);
    const bad = [];
    const want = [
      ".aai/scripts/aai-run-tests.sh", ".aai/scripts/aai-run-tests.ps1", ".aai/scripts/aai-win-selftest.ps1", ".aai/scripts/pre-commit-checks.sh",
      ".aai/scripts/claude-hook-gate.sh", ".aai/scripts/lib/test-residue.sh", ".aai/scripts/lib/repo-tripwire.sh",
      ".aai/scripts/lib/append-lock.sh", ".aai/scripts/lib/git-bash-path.sh",
    ];
    const got = rows.map((r) => r.file);
    if (JSON.stringify(got) !== JSON.stringify(want)) bad.push("the rows are [" + got.join(" ; ") + "], want [" + want.join(" ; ") + "]");
    for (const r of rows) if (r.reason === "") bad.push("empty reason: " + r.file);
    // the four old rows, byte for byte
    const old = [
      "| `.aai/scripts/aai-run-tests.sh` | supervises suite processes, timeouts and orphan cleanup in bash; the per-suite cost is the isolation clone, not the shell |",
      "| `.aai/scripts/aai-run-tests.ps1` | a WSL and Git-Bash dispatcher of the bash runner, not a twin of it |",
      "| `.aai/scripts/aai-win-selftest.ps1` | inherently a PowerShell engine probe |",
      "| `.aai/scripts/pre-commit-checks.sh` | git hooks always run under Git\x27s shell; an L3 protected surface |",
    ];
    const lines = text.split("\n");
    for (const o of old) if (lines.filter((l) => l === o).length !== 1) bad.push("an old row changed or is missing: " + o.slice(0, 60));
    process.stdout.write(bad.join("; "));
  ')" || log_fail "TEST-4024: the table check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4024: $out"
  log_pass "TEST-4024: the Kept native scripts table holds the four old rows unchanged and the five D-KEPT rows in order, each with a non-empty reason"
}

# launcher_case <stem> <kind sh|ps1>: prints "<rc> <marker> <args>" for the launcher, args being one token or the
# word NONE; @S@ stands for the scratch directory. The marker is a text the output of the recorded run holds ("-" for
# none). A launcher without a row here fails TEST-4035.
launcher_case() {
  case "$1" in
    aai-bootstrap)           echo "0 Generate_project-local -h" ;;
    aai-live)                echo "0 Usage -h" ;;
    aai-sync)                echo "0 Push_AAI_layer -h" ;;
    cloudflare-share)        echo "1 Document_not_found @S@/none.md" ;;
    expert-fetch)            echo "2 not_found_in_registry no-such-expert-xyz" ;;
    install-pre-commit-hook) echo "0 Install_the_AAI_git_hook -h" ;;
    migrate-state-to-local)  echo "1 target_directory_not_found @S@/nonexistent" ;;
    triage)                  echo "0 AAI_L1_Triage NONE" ;;
    validate-skills)         echo "1 Target_not_found @S@/nonexistent" ;;
    aai-reap-tests)          echo "0 reaped: NONE" ;;
    aai-release)             echo "0 usage:_aai-release -h" ;;
    aai-update)              echo "0 AAI_layer_updater -h" ;;
    live-spool)              echo "0 - hooks" ;;
    aai-canonicalize)        echo "1 retired NONE" ;;
    autonomous-loop)         echo "1 retired NONE" ;;
    migrate-yaml-to-jsonl)   echo "1 retired NONE" ;;
    pre-commit-checks)       echo "1 retired NONE" ;;
    *) return 1 ;;
  esac
}

# run_launcher <scratch> <target> <kind> <stem> <rc> <marker> <arg>: one launcher from the install, in a scrubbed
# environment, cwd the target. Fails on a wrong exit code, a missing marker, the node-missing refusal or a shell error.
run_launcher() {
  local s="$1" t="$2" kind="$3" stem="$4" want_rc="$5" marker="$6" arg="$7" rc=0 file out text
  file="$t/.aai/scripts/$stem.$kind"
  [[ -f "$file" ]] || log_fail "TEST-4035: $stem.$kind is not in the install"
  [[ "$arg" != "NONE" ]] || arg=""
  arg="${arg//@S@/$s}"
  mkdir -p "$s/spool" "$s/home"
  text="$s/run.out"
  set +e
  if [[ "$kind" == "sh" ]]; then
    if [[ -n "$arg" ]]; then
      (cd "$t" && env -i PATH="$PATH" HOME="$s/home" AAI_REAP_WORKSPACE="$t" AAI_LIVE_SPOOL_DIR="$s/spool" bash "$file" "$arg" </dev/null >"$text" 2>&1)
    else
      (cd "$t" && env -i PATH="$PATH" HOME="$s/home" AAI_REAP_WORKSPACE="$t" AAI_LIVE_SPOOL_DIR="$s/spool" bash "$file" </dev/null >"$text" 2>&1)
    fi
  else
    if [[ -n "$arg" ]]; then
      (cd "$t" && env -i PATH="$PATH" HOME="$s/home" AAI_REAP_WORKSPACE="$t" AAI_LIVE_SPOOL_DIR="$s/spool" pwsh -NoProfile -File "$file" "$arg" </dev/null >"$text" 2>&1)
    else
      (cd "$t" && env -i PATH="$PATH" HOME="$s/home" AAI_REAP_WORKSPACE="$t" AAI_LIVE_SPOOL_DIR="$s/spool" pwsh -NoProfile -File "$file" </dev/null >"$text" 2>&1)
    fi
  fi
  rc=$?
  set -e
  out="$(cat "$text")"
  [[ "$rc" == "$want_rc" ]] || log_fail "TEST-4035: $stem.$kind exited $rc, recorded $want_rc: ${out:0:300}"
  if [[ "$marker" != "-" ]]; then
    [[ "$out" == *"${marker//_/ }"* ]] || log_fail "TEST-4035: $stem.$kind output lacks its recorded text '${marker//_/ }': ${out:0:300}"
  fi
  case "$out" in
    *"node not found"*|*"missing-node"*|*"Node.js 22 or later is required"*) log_fail "TEST-4035: $stem.$kind printed the node-missing refusal: ${out:0:300}" ;;
    *"command not found"*|*"syntax error"*|*"No such file or directory"*|*"unbound variable"*|*"cannot be found"*) log_fail "TEST-4035: $stem.$kind printed a shell error: ${out:0:300}" ;;
  esac
}

# TEST-4035 (Spec-AC-12): the extended profile is installed by aai-sync.mjs into a scratch target and every launcher
# and deprecation launcher of the shared classifier that the install holds runs from it with its recorded argument
# (sh under bash, ps1 under pwsh 7). A shipped launcher without a recorded row fails the test.
test_4035_every_launcher_runs() {
  local s t have_pwsh=1 list line cls rel stem kind spec rc marker arg ran=0 ran_ps1=0 cmd
  command -v pwsh >/dev/null 2>&1 || have_pwsh=0
  if [[ "$have_pwsh" -eq 0 ]]; then
    [[ -z "${CI:-}" ]] || log_fail "TEST-4035: pwsh 7 is required on CI and was not found"
    log_info "TEST-4035: pwsh not found; the ps1 arm is skipped on this host"
  fi
  s="$(new_own_scratch install)"
  t="$s/target"
  mkdir -p "$t" "$s/home"
  [[ -n "$t" && "$t" == /* && "$t" != "$PROJECT_ROOT" ]] || log_fail "TEST-4035: bad target path"
  # a scratch git repository with its own identity; GIT_* scrubbed so nothing reaches another repository
  rc=0
  (cd "$t" && env -i PATH="$PATH" HOME="$s/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git -c user.email=p5c@example.invalid -c user.name=p5c init -q -b main) || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-4035: the scratch git init failed ($rc)"
  rc=0
  (cd "$t" && env -i PATH="$PATH" HOME="$s/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    node "$PROJECT_ROOT/.aai/scripts/aai-sync.mjs" "$t" --profile extended </dev/null >"$s/sync.out" 2>&1) || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-4035: aai-sync.mjs into the scratch target exited $rc: $(tail -c 300 "$s/sync.out")"
  [[ -d "$t/.aai/scripts" ]] || log_fail "TEST-4035: the install holds no .aai/scripts"

  # the classifier names the launchers of the install (top level of .aai/scripts, rows of the live RFC)
  list="$s/launchers.tsv"
  T4035_LIB="$CLASSES_LIB" T4035_RFC="$PROJECT_ROOT/$RFC_REL" T4035_TARGET="$t" node --input-type=module -e '
    import fs from "node:fs";
    import path from "node:path";
    const { classify, parseKeptNative } = await import(process.env.T4035_LIB);
    const kept = parseKeptNative(fs.readFileSync(process.env.T4035_RFC, "utf8"));
    const dir = path.join(process.env.T4035_TARGET, ".aai", "scripts");
    const out = [];
    for (const name of fs.readdirSync(dir).sort()) {
      if (!name.endsWith(".sh") && !name.endsWith(".ps1")) continue;
      const rel = ".aai/scripts/" + name;
      const cls = classify({ file: rel, text: fs.readFileSync(path.join(dir, name), "utf8"), kept });
      if (cls === "launcher" || cls === "deprecation launcher") out.push(cls.replace(" ", "-") + "\t" + rel);
    }
    fs.writeFileSync(process.argv[1], out.join("\n") + "\n");
  ' "$list" || log_fail "TEST-4035: the classifier failed over the install"
  [[ -s "$list" ]] || log_fail "TEST-4035: the classifier found no launcher in the install"

  while IFS=$'\t' read -r cls rel; do
    [[ -n "$rel" ]] || continue
    stem="${rel##*/}"; kind="${stem##*.}"; stem="${stem%.*}"
    spec="$(launcher_case "$stem")" || log_fail "TEST-4035: the shipped $cls $rel has no recorded row in launcher_case"
    rc="${spec%% *}"; spec="${spec#* }"; marker="${spec%% *}"; arg="${spec#* }"
    if [[ "$kind" == "ps1" && "$have_pwsh" -eq 0 ]]; then continue; fi
    run_launcher "$s" "$t" "$kind" "$stem" "$rc" "$marker" "$arg"
    ran=$((ran + 1))
    [[ "$kind" != "ps1" ]] || ran_ps1=$((ran_ps1 + 1))
  done < "$list"
  [[ "$ran" -ge 20 ]] || log_fail "TEST-4035: only $ran launchers ran; a vacuous pass"
  [[ "$have_pwsh" -eq 0 || "$ran_ps1" -ge 10 ]] || log_fail "TEST-4035: only $ran_ps1 ps1 launchers ran; a vacuous pass"
  safe_rm_own "$s"
  log_pass "TEST-4035: $ran launchers ($ran_ps1 ps1) ran from a scratch extended install with their recorded arguments and exit codes"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-4024, TEST-4035)"
  check_deps
  test_4024_kept_native_rows
  test_4035_every_launcher_runs
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
