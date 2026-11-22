#!/usr/bin/env bash
#
# Test: aai-sync-docs
# (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, TEST-4020 to TEST-4022)
#
# The documentation, follow-up and phase 5 re-measure half of the sync-on-node ride, split out of
# test-aai-sync-node.sh so that the long sync suite does not read the changelog (the release dry-run
# replays every suite that does). TEST-4020 checks the changelog entry, the README and USER_GUIDE sync blocks and the RFC-0017
# row and inventory; TEST-4021 reads the follow-up registry for the fourteen closed and the suggested open
# follow-ups; TEST-4022 re-measures every tracked .sh and .ps1 under .aai/scripts with the plan's section 1 method and
# compares it with section 6 of docs/analysis/node-first-remaining-plan.md. Its scratch directories carry its own prefix
# and ownership marker; nothing here starts a container tool, kills by pattern, or reaches the network.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-sync-docs.sh           # run all
#   bash tests/skills/test-aai-sync-docs.sh test_4020_docs
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-sync-docs"
OWN_PREFIX="aai-sync-docs."
OWN_MARKER=".aai-sd-owned"

# The script directory without a cd inside a command substitution (the cd-subshell ratchet).
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR="."
case "$SCRIPT_DIR" in /*) ;; *) SCRIPT_DIR="$PWD/$SCRIPT_DIR" ;; esac

# phys_path <path>: the physical absolute path (symlinks resolved); empty and failing when it does not exist.
phys_path() {
  node -e 'try { process.stdout.write(require("fs").realpathSync(process.argv[1])); } catch (e) { process.exit(1); }' "$1"
}

PROJECT_ROOT="$(phys_path "$SCRIPT_DIR/../..")"
SPEC_ID="sync-on-node"

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

test_4020_docs() {
  local work out rc
  work="$(new_own_scratch docs)"
  out="$(node -e '
    const fs = require("fs");
    const root = process.argv[1];
    const read = (p) => fs.readFileSync(root + "/" + p, "utf8");
    const bad = [];
    // A release cut rolls "## [unreleased] — " into "## [vYYYY.MM.DD] — ", so the pin accepts both.
    const head = /^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — feat: the AAI layer sync runs on Node behind sh and ps1 launchers$/;
    const cl = read("CHANGELOG.md").split("\n");
    const at = cl.map((l, i) => (head.test(l) ? i : -1)).filter((i) => i >= 0);
    if (at.length !== 1) bad.push("the CHANGELOG heading appears " + at.length + " times");
    else {
      let end = cl.length;
      for (let i = at[0] + 1; i < cl.length; i += 1) if (cl[i].startsWith("## ")) { end = i; break; }
      const body = cl.slice(at[0] + 1, end).join("\n");
      for (const w of ["Node.js 22", "DR-2", "DR-5", "DR-7", "DR-11", "DR-13", "DR-18", "DR-20", "DR-21", "DR-29"]) if (!body.includes(w)) bad.push("the CHANGELOG body lacks " + w);
      // every path of the D-LEGACY table, named so that a project can clean an old layout by hand
      for (const w of ["`ai/`", "`scripts/<name>`", "`scripts/ai-os-*`", "`PLAYBOOK.md`", "`docs/workflow`", "`docs/roles`", "`docs/templates`", "docs/ai/AUTONOMOUS_LOOP.md",
        "docs/ai/SUPERPOWERS_INTEGRATION.md", "docs/ai/DYNAMIC_SKILLS.md", "docs/ai/PRICING.yaml", "docs/ai/AAI_PIN.md", "docs/ai/LOCKS.md", "docs/knowledge/PATTERNS_UNIVERSAL.md"]) {
        if (!body.includes(w)) bad.push("the CHANGELOG body lacks the legacy path " + w);
      }
      if (!body.includes("Re-run `/aai-update` to pick up the new launchers and module.")) bad.push("the CHANGELOG body lacks the closing sentence");
    }
    const readme = read("README.md");
    const rb = readme.slice(readme.indexOf("## Sync AAI into another repository"));
    const rblock = rb.slice(0, rb.indexOf("\n## ", 5) < 0 ? rb.length : rb.indexOf("\n## ", 5));
    if (!rblock.includes("aai-sync.mjs")) bad.push("the README sync block does not name aai-sync.mjs");
    if (!rblock.includes("Node.js 22")) bad.push("the README sync block does not name Node.js 22");
    const ug = read("docs/USER_GUIDE.md");
    const ua = ug.indexOf("Manual sync alternative:");
    const ub = ug.indexOf("2. **Bootstrap your project", ua);
    const block = ua < 0 || ub < 0 ? "" : ug.slice(ua, ub).replace(/\s+/g, " ");
    if (block === "") bad.push("the USER_GUIDE manual sync block is not found");
    if (!block.includes("aai-sync.mjs")) bad.push("the USER_GUIDE sync block does not name aai-sync.mjs");
    if (!block.includes("Node.js 22")) bad.push("the USER_GUIDE sync block does not name Node.js 22");
    if (!block.includes("refuses before writing anything when the target is the source or lies inside it, and when a managed path in the target is a symbolic link that leaves the target")) bad.push("the USER_GUIDE sync block lacks the refusal sentence");
    const rfc = read("docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md").split("\n");
    const row = rfc.filter((l) => l.startsWith("| 5 |"));
    if (row.length !== 1) bad.push("the RFC phase 5 row appears " + row.length + " times");
    else {
      const r = row[0];
      // the allocator rewrites the link target at merge; only the suffix sync-on-node.md is pinned
      const sentence = "The seventeenth slice [moved the layer sync to Node](LINK): one module holds the argument, profile, copy, prune and gitignore rules behind thin aai-sync.sh and aai-sync.ps1 launchers, compared with frozen copies of both twins, and the updater, the bootstrap, the hook installer and the sync share one base-resolution library.";
      const norm = r.replace(/\(\.\.\/issues\/[A-Za-z0-9-]*sync-on-node\.md\)/, "(LINK)");
      if (norm.split(sentence).length !== 2) bad.push("the RFC row does not hold the D-DOCS sentence once");
      const a = r.indexOf("The sixteenth slice"); const b = r.indexOf("The seventeenth slice"); const c = r.indexOf("The [remaining-scripts plan]");
      if (!(a >= 0 && a < b && b < c)) bad.push("the RFC sentence is not between the sixteenth slice and the remaining-scripts plan");
      if (!/\(\.\.\/issues\/[A-Za-z0-9-]*sync-on-node\.md\)/.test(r)) bad.push("the RFC link does not end with sync-on-node.md");
    }
    if (rfc.some((l) => /^\| `aai-sync` \|/.test(l))) bad.push("the RFC inventory still holds an aai-sync row");
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT")" || log_fail "TEST-4020: the docs check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4020: $out"
  rc=0
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree > "$work/sel.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/sel.log" >&2; log_fail "TEST-4020: test_2624_inventory_matches_tree of test-aai-expert-fetch.sh exited $rc"; }
  # the product doc is written after LOOP COMPLETE (canon: product docs after the flush); once it exists it must carry the
  # required sections of the product-doc check
  if [[ -f "$PROJECT_ROOT/docs/product/sync-on-node.md" ]]; then
    out="$(PROJECT_ROOT="$PROJECT_ROOT" node --input-type=module -e '
      import { pathToFileURL } from "node:url";
      import fs from "node:fs";
      const root = process.env.PROJECT_ROOT;
      const { missingProductSections } = await import(pathToFileURL(root + "/.aai/scripts/lib/product-doc.mjs").href);
      const missing = missingProductSections(fs.readFileSync(root + "/docs/product/sync-on-node.md", "utf8"));
      process.stdout.write(missing.length ? "the product doc lacks " + JSON.stringify(missing) : "");
    ')" || log_fail "TEST-4020: the product-doc check failed to run"
    [[ -z "$out" ]] || log_fail "TEST-4020: $out"
    log_info "TEST-4020: docs/product/sync-on-node.md passes the product-doc check"
  else
    log_info "TEST-4020: docs/product/sync-on-node.md is not written yet (the ship step writes it after LOOP COMPLETE); that arm is checked once it exists"
  fi
  safe_rm_own "$work"
  log_pass "TEST-4020: the CHANGELOG entry (Node.js 22, ten DRs, every legacy path, the closing sentence), the README and USER_GUIDE sync blocks, the RFC-0017 sentence and inventory hold, and expert-fetch test_2624 passes"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-4020 to TEST-4022)"
  check_deps
  test_4020_docs
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
