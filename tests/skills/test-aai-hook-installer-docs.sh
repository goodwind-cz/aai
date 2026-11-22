#!/usr/bin/env bash
#
# Test: aai-hook-installer-docs
# (docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md, TEST-3998 and TEST-3999)
#
# The documentation and follow-up half of the pre-commit-installer-on-node ride, split out of
# test-aai-hook-installer-node.sh so that the long installer suite does not read the changelog (the release
# dry-run replays every suite that does). It checks the changelog entry, the SKILL_UPDATE step 4 lines, the
# USER_GUIDE installer section, the RFC-0017 row and the prompt-diet ledger entry, runs the prompt-diet,
# pr-preflight, suite-reuse, git-ref-guard and expert-fetch single-case checks that these edits touch, and
# reads the follow-up registry for the eighteen closed and four filed follow-ups (TEST-3999). Its
# scratch directories carry its own prefix and ownership marker; nothing here starts a container tool,
# kills by pattern, or reaches the network.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-hook-installer-docs.sh           # run all
#   bash tests/skills/test-aai-hook-installer-docs.sh test_3998_docs
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-hook-installer-docs"
OWN_PREFIX="aai-hook-installer-docs."
OWN_MARKER=".aai-hkd-owned"

# The script directory without a cd inside a command substitution (the cd-subshell ratchet).
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR="."
case "$SCRIPT_DIR" in /*) ;; *) SCRIPT_DIR="$PWD/$SCRIPT_DIR" ;; esac

# phys_path <path>: the physical absolute path (symlinks resolved); empty and failing when it does not exist.
phys_path() {
  node -e 'try { process.stdout.write(require("fs").realpathSync(process.argv[1])); } catch (e) { process.exit(1); }' "$1"
}

PROJECT_ROOT="$(phys_path "$SCRIPT_DIR/../..")"
SPEC_ID="pre-commit-installer-on-node"

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

test_3998_docs() {
  local work out rc sel
  work="$(new_own_scratch docs)"
  out="$(node -e '
    const fs = require("fs");
    const root = process.argv[1];
    const read = (p) => fs.readFileSync(root + "/" + p, "utf8");
    const bad = [];
    // A release cut rolls "## [unreleased] — " into "## [vYYYY.MM.DD] — ", so the pin accepts both.
    const head = /^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — feat: the git hook installer runs on Node behind sh and ps1 launchers$/;
    const cl = read("CHANGELOG.md").split("\n");
    const at = cl.map((l, i) => (head.test(l) ? i : -1)).filter((i) => i >= 0);
    if (at.length !== 1) bad.push("the CHANGELOG heading appears " + at.length + " times");
    else {
      let end = cl.length;
      for (let i = at[0] + 1; i < cl.length; i += 1) if (cl[i].startsWith("## ")) { end = i; break; }
      const body = cl.slice(at[0] + 1, end).join("\n");
      for (const w of ["Node.js 22", "DR-4", "DR-6", "DR-11", "DR-12", "DR-15", "DR-16", "DR-17"]) if (!body.includes(w)) bad.push("the CHANGELOG body lacks " + w);
      if (!body.includes("Re-run `/aai-update` to pick up the new launchers and module.")) bad.push("the CHANGELOG body lacks the closing sentence");
    }
    const suText = read(".aai/SKILL_UPDATE.prompt.md");
    const su = suText.split("\n");
    const once = (l) => su.filter((x) => x === l).length;
    for (const l of [
      "   Both launchers run .aai/scripts/install-pre-commit-hook.mjs and need Node.js 22 or later.",
      "   It installs THREE hooks into the directory git resolves: the docs-index",
      "   pre-commit hook (AAI:INDEX-AUTOGEN), a reference-transaction hook",
      "   (AAI:REF-GUARD) that refuses any refs/heads/main update in this",
      "   repository unless AAI_GIT_WRITE=1 is set on that command, and a pre-push",
      "   hook (AAI:CLOSE-GATE). A recorded `ref_guard: declined` in",
      "   docs/ai/docs-audit.yaml is honoured: the ref-guard is skipped, not",
      "   re-armed. The installer is idempotent per hook, checks every slot before",
      "   writing any, and WITHOUT `--force` refuses to overwrite a foreign hook",
      "   in any slot, so a refusal installs nothing. Therefore:",
      "     git hooks installed (docs-index pre-commit, AAI:REF-GUARD reference-",
      "     transaction, AAI:CLOSE-GATE pre-push). Decline the ref-guard:",
      "     install-pre-commit-hook.sh --decline-ref-guard.\"",
    ]) {
      if (once(l) !== 1) bad.push("SKILL_UPDATE holds the line " + JSON.stringify(l) + " " + once(l) + " times");
    }
    if (Buffer.byteLength(suText) < 3600) bad.push("SKILL_UPDATE.prompt.md is under 3600 bytes");
    if (suText.includes("This installs BOTH hooks")) bad.push("SKILL_UPDATE still holds the two-hook paragraph");
    const ug = read("docs/USER_GUIDE.md");
    const block = ug.slice(ug.indexOf("**Install / uninstall:**"), ug.indexOf("## Git hooks the installer writes"));
    if (!block.includes("install-pre-commit-hook.mjs")) bad.push("the USER_GUIDE installer section does not name install-pre-commit-hook.mjs");
    if (!block.includes("Node.js 22")) bad.push("the USER_GUIDE installer section does not name Node.js 22");
    if (!block.includes("--uninstall` of the ref-guard is undone by the next plain install unless the guard is declined")) bad.push("the USER_GUIDE installer section lacks the uninstall sentence");
    const rfc = read("docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md").split("\n");
    const row = rfc.filter((l) => l.startsWith("| 5 |"));
    if (row.length !== 1) bad.push("the RFC phase 5 row appears " + row.length + " times");
    else {
      const r = row[0];
      if (!r.includes("| in progress |")) bad.push("the RFC phase 5 row is not in progress");
      // the allocator rewrites the link target at merge; only the suffix pre-commit-installer-on-node.md is pinned
      const sentence = "The sixteenth slice [moved the git hook installer to Node](LINK): one module holds the mode, policy, slot and write rules behind thin install-pre-commit-hook.sh and install-pre-commit-hook.ps1 launchers, compared with frozen copies of both twins, and the ref_guard policy is read and written only through guard-config.";
      const norm = r.replace(/\(\.\.\/issues\/[A-Za-z0-9-]*pre-commit-installer-on-node\.md\)/, "(LINK)");
      if (norm.split(sentence).length !== 2) bad.push("the RFC row does not hold the D-DOCS sentence once");
      const a = r.indexOf("The fifteenth slice"); const b = r.indexOf("The sixteenth slice"); const c = r.indexOf("The [remaining-scripts plan]");
      if (!(a >= 0 && a < b && b < c)) bad.push("the RFC sentence is not between the fifteenth slice and the remaining-scripts plan");
      if (!/\(\.\.\/issues\/[A-Za-z0-9-]*pre-commit-installer-on-node\.md\)/.test(r)) bad.push("the RFC link does not end with pre-commit-installer-on-node.md");
    }
    if (rfc.some((l) => /^\| `install-pre-commit-hook` \|/.test(l))) bad.push("the RFC inventory still holds an install-pre-commit-hook row");
    // the prompt-diet ledger entry of this ride states its measurement and matches the file on disk
    const ledger = read("tests/skills/lib/prompt-diet-ledger.sh").split("\n").filter((l) => l.includes("pre-commit-installer-on-node Spec-AC-19"));
    if (ledger.length !== 1) bad.push("the prompt-diet ledger holds " + ledger.length + " entries of this ride");
    else {
      const m = /"([0-9]+) pre-commit-installer-on-node .*SKILL_UPDATE\.prompt\.md ([0-9]+) -> ([0-9]+)/.exec(ledger[0]);
      if (!m) bad.push("the ledger entry does not state SKILL_UPDATE.prompt.md <before> -> <after>");
      else {
        if (Number(m[3]) - Number(m[2]) !== Number(m[1])) bad.push("the ledger credit is not after minus before");
        if (Number(m[3]) !== Buffer.byteLength(suText)) bad.push("the ledger after-size " + m[3] + " is not the file size " + Buffer.byteLength(suText));
      }
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT")" || log_fail "TEST-3998: the docs check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-3998: $out"
  for sel in "test-aai-prompt-diet.sh test_012_growth_sum_matches_ledger" "test-aai-prompt-diet.sh test_622_diet_true_up" "test-aai-pr-preflight.sh test_008" \
    "test-aai-suite-reuse.sh test_3278_canon_wording" "test-aai-git-ref-guard.sh test_621_update_prompt_names_both_hooks" "test-aai-expert-fetch.sh test_2624_inventory_matches_tree"; do
    rc=0
    # shellcheck disable=SC2086
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/${sel%% *}" ${sel#* } > "$work/sel.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/sel.log" >&2; log_fail "TEST-3998: ${sel#* } of ${sel%% *} exited $rc"; }
  done
  safe_rm_own "$work"
  log_pass "TEST-3998: the CHANGELOG entry, the SKILL_UPDATE step 4 lines, the USER_GUIDE installer section, the RFC-0017 sentence and inventory, and the prompt-diet ledger entry hold, and the prompt-diet, pr-preflight growth, suite-reuse growth, git-ref-guard and RFC inventory checks pass"
}

# The eighteen follow-ups this ride closes and the one it leaves open (D-FU), and the four it files.
CLOSED_FU="fu-installer-flag-lattice-no-mode fu-three-readers-three-whitespaces fu-installer-want-refguard-overloaded fu-ps1-writeerror-terminates-before-exit fu-ps1-symlink-config-replaced fu-ps1-decline-not-disclosed fu-ps1-refusal-no-manual-merge fu-ps1-decline-force-advice-wrong fu-ps1-enable-refguard-no-rationale fu-ps1-setcontent-rewrites-seed-eol fu-hook-tmpl-final-lf-parity fu-hook-installer-not-a-repo-msg fu-uninstall-refguard-leaves-armed fu-doubled-key-has-no-repair fu-ac05-counts-a-valueless-key fu-test618-positional-pattern fu-test641-passes-without-pwsh fu-skill-update-step4-both-hooks"
OPEN_FU="fu-seterr-suspended-left-of-or"
FILED_FU="fu-installer-not-in-l3-protected-paths fu-guard-dials-ignore-bom fu-update-ps1-colon-switch-args fu-hook-upgrade-resets-mode"

test_3999_follow_ups() {
  local work json out
  work="$(new_own_scratch followups)"
  json="$(node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status all --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-3999: follow-ups list failed"
  # the JSON is large: it goes to the checker on stdin, never as one argument (Linux caps a single argv string at 128 KiB)
  out="$(printf '%s' "$json" | node -e '
    const fs = require("fs");
    const root = process.argv[1];
    const closed = process.argv[2].split(" ");
    const open = process.argv[3].split(" ");
    const filed = process.argv[4].split(" ");
    const items = JSON.parse(fs.readFileSync(0, "utf8")).items;
    const by = new Map(items.map((i) => [i.id, i]));
    // the registry projection keeps the filing source; the close source lives on the latest follow_up_status record
    const closeSource = new Map();
    for (const line of fs.readFileSync(root + "/docs/ai/decisions.jsonl", "utf8").split("\n")) {
      if (!line.includes("\"follow_up_status\"")) continue;
      let rec;
      try { rec = JSON.parse(line); } catch { continue; }
      if (rec.type === "follow_up_status" && rec.status === "done") closeSource.set(rec.id, String(rec.source ?? ""));
    }
    const bad = [];
    if (new Set(closed).size !== 18) bad.push("the closed list does not hold eighteen ids");
    for (const id of closed) {
      const it = by.get(id);
      if (!it) { bad.push(id + " is not in the registry"); continue; }
      if (!it.closed || it.status !== "done") bad.push(id + " is not closed as done (" + it.status + ")");
      if (it.resolved_by !== "pre-commit-installer-on-node") bad.push(id + " resolved_by is " + it.resolved_by);
      const src = closeSource.get(id) ?? "";
      const m = /(tests\/[A-Za-z0-9_.\/-]+\.(?:sh|mjs)) (TEST-[0-9]+)/.exec(src);
      if (!m) { bad.push(id + " source names no test file and TEST id: " + src); continue; }
      const file = root + "/" + m[1];
      if (!fs.existsSync(file)) { bad.push(id + " source file " + m[1] + " does not exist"); continue; }
      if (!fs.readFileSync(file, "utf8").includes(m[2] + ":")) bad.push(id + " source " + m[1] + " holds no " + m[2] + ":");
    }
    for (const id of open) {
      const it = by.get(id);
      if (!it || it.closed) bad.push(id + " must stay open");
    }
    for (const id of filed) {
      const it = by.get(id);
      if (!it) { bad.push(id + " is not filed"); continue; }
      // filed open by this ride; a later ride may close it (installer-l3-protected closed fu-installer-not-in-l3-protected-paths)
      if (it.closed && (it.resolved_by === "pre-commit-installer-on-node" || !it.resolved_by)) bad.push(id + " is not open");
      if (it.ref_id !== "pre-commit-installer-on-node") bad.push(id + " ref is " + it.ref_id);
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT" "$CLOSED_FU" "$OPEN_FU" "$FILED_FU")" || log_fail "TEST-3999: the follow-up check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-3999: $out"
  safe_rm_own "$work"
  log_pass "TEST-3999: the eighteen follow-ups are closed with resolved_by pre-commit-installer-on-node and a source naming a test file and a TEST id it holds, fu-seterr-suspended-left-of-or stays open, and the four suggested follow-ups are filed with ref pre-commit-installer-on-node and open unless a later ride resolved them"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3998 and TEST-3999)"
  check_deps
  test_3998_docs
  test_3999_follow_ups
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
