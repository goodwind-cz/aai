#!/usr/bin/env bash
#
# Test: aai-update-docs
# (docs/specs/SPEC-0307-spec-update-on-node.md, TEST-3978)
#
# The documentation half of the update-on-node ride, split out of test-aai-update-node.sh so that the
# long updater suite does not read the changelog (the release dry-run replays every suite that does).
# It checks the changelog entry, the SKILL_UPDATE sentence and bullet and the RFC-0017 row, then runs the
# prompt-diet, pr-preflight, suite-reuse and expert-fetch single-case checks that these edits touch. Its
# scratch directories carry its own prefix and ownership marker; nothing here starts a container tool,
# kills by pattern, or reaches the network.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-update-docs.sh                  # run all
#   bash tests/skills/test-aai-update-docs.sh test_3978_docs
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-update-docs"
OWN_PREFIX="aai-update-docs."
OWN_MARKER=".aai-up-owned"

# The script directory without a cd inside a command substitution (the cd-subshell ratchet).
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR="."
case "$SCRIPT_DIR" in /*) ;; *) SCRIPT_DIR="$PWD/$SCRIPT_DIR" ;; esac

# phys_path <path>: the physical absolute path (symlinks resolved); empty and failing when it does not exist.
phys_path() {
  node -e 'try { process.stdout.write(require("fs").realpathSync(process.argv[1])); } catch (e) { process.exit(1); }' "$1"
}

PROJECT_ROOT="$(phys_path "$SCRIPT_DIR/../..")"
SPEC_ID="spec-update-on-node"

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
    [[ "$(cat "$real/$OWN_MARKER" 2>/dev/null)" =~ ^[0-9]+$ ]] || log_fail "safe_rm_own: ownership marker vanished in $p"
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
  log_pass "Dependencies checked"
}

test_3978_docs() {
  local work out rc sel
  work="$(new_own_scratch docs)"
  out="$(node -e '
    const fs = require("fs");
    const root = process.argv[1];
    const read = (p) => fs.readFileSync(root + "/" + p, "utf8");
    const bad = [];
    // A release cut rolls "## [unreleased] — " into "## [vYYYY.MM.DD] — ", so the pin accepts both.
    const head = /^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — feat: the AAI layer updater runs on Node behind sh and ps1 launchers$/;
    const cl = read("CHANGELOG.md").split("\n");
    const at = cl.map((l, i) => (head.test(l) ? i : -1)).filter((i) => i >= 0);
    if (at.length !== 1) bad.push("the CHANGELOG heading appears " + at.length + " times");
    else {
      let end = cl.length;
      for (let i = at[0] + 1; i < cl.length; i += 1) if (cl[i].startsWith("## ")) { end = i; break; }
      const body = cl.slice(at[0] + 1, end).join("\n");
      for (const w of ["Node.js 22", "DR-2", "DR-3", "DR-5", "DR-7", "DR-12"]) if (!body.includes(w)) bad.push("the CHANGELOG body lacks " + w);
      if (body.trim() === "") bad.push("the CHANGELOG body is empty");
    }
    const su = read(".aai/SKILL_UPDATE.prompt.md").split("\n");
    const once = (l) => su.filter((x) => x.trim() === l).length;
    for (const l of [
      "Both launchers run .aai/scripts/aai-update.mjs and need Node.js 22 or later.",
      "- exit 1 = an unknown argument, a missing flag value, or Node.js missing (the message says which)",
      ".aai/scripts/aai-update.sh            # bash / macOS / Linux",
      ".aai/scripts/aai-update.ps1           # PowerShell / Windows",
    ]) {
      if (once(l) !== 1) bad.push("SKILL_UPDATE holds the line " + JSON.stringify(l) + " " + once(l) + " times");
    }
    const rfc = read("docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md").split("\n");
    const row = rfc.filter((l) => l.startsWith("| 5 |"));
    if (row.length !== 1) bad.push("the RFC phase 5 row appears " + row.length + " times");
    else {
      const r = row[0];
      { const p5 = require("child_process").spawnSync("node", [root + "/tests/skills/lib/phase5-row-status.mjs", root + "/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md"], { encoding: "utf8" }); if (p5.status !== 0) bad.push((p5.stdout || p5.stderr || "phase 5 status check failed").trim()); }
      // the allocator rewrites the link target at merge; only the suffix update-on-node.md is pinned
      const sentence = "The fifteenth slice [moved the layer updater to Node](LINK): one module holds the argument, source, sync and report policy behind thin aai-update.sh and aai-update.ps1 launchers, compared with frozen copies of both twins, and each launcher keeps running the sync twin it ran before.";
      const norm = r.replace(/\(\.\.\/issues\/[A-Za-z0-9-]*update-on-node\.md\)/, "(LINK)");
      if (norm.split(sentence).length !== 2) bad.push("the RFC row does not hold the D-DOCS sentence once");
      const a = r.indexOf("The fourteenth slice"); const b = r.indexOf("The fifteenth slice"); const c = r.indexOf("The [remaining-scripts plan]");
      if (!(a >= 0 && a < b && b < c)) bad.push("the RFC sentence is not between the fourteenth slice and the remaining-scripts plan");
      if (!/\(\.\.\/issues\/[A-Za-z0-9-]*update-on-node\.md\)/.test(r)) bad.push("the RFC link does not end with update-on-node.md");
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT")" || log_fail "TEST-3978: the docs check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-3978: $out"
  for sel in "test-aai-prompt-diet.sh test_012_growth_sum_matches_ledger" "test-aai-pr-preflight.sh test_008" "test-aai-suite-reuse.sh test_3278_canon_wording" "test-aai-expert-fetch.sh test_2624_inventory_matches_tree"; do
    rc=0
    # shellcheck disable=SC2086
    env -u AAI_ROLE bash "$SCRIPT_DIR/${sel%% *}" ${sel#* } > "$work/sel.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/sel.log" >&2; log_fail "TEST-3978: ${sel#* } of ${sel%% *} exited $rc"; }
  done
  safe_rm_own "$work"
  log_pass "TEST-3978: the CHANGELOG entry, the SKILL_UPDATE sentence and bullet, and the RFC-0017 sentence hold, and the prompt-diet, pr-preflight growth, suite-reuse growth and RFC inventory checks pass"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3978)"
  check_deps
  test_3978_docs
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
