#!/usr/bin/env bash
#
# Test: aai-sync-docs
# (docs/specs/SPEC-0310-spec-sync-on-node.md, TEST-4020 to TEST-4022)
#
# The documentation, follow-up and phase 5 re-measure half of the sync-on-node ride, split out of
# test-aai-sync-node.sh so that the long sync suite does not read the changelog (the release dry-run
# replays every suite that does). TEST-4020 checks the changelog entry, the README and USER_GUIDE sync blocks and the RFC-0017
# row and inventory; TEST-4021 reads the follow-up registry for the fourteen closed and the suggested open
# follow-ups; TEST-4022 re-measures every tracked .sh and .ps1 under .aai/scripts with the plan's section 1 method and
# compares it with the latest re-measure section of docs/analysis/node-first-remaining-plan.md. Its scratch directories carry its own prefix
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

# The thirteen follow-ups this ride closes (D-FU; fu-parity-win-source-path was reopened by run 9, see REOPENED_FU) and the fourteenth, fu-guard-config-not-l3-protected, closed by the owner-authorised
# Spec-AC-23 (TEST-4023); the three it files open (the fourth suggestion, fu-sync-sl-skill-dangling-core, is the already open
# fu-sync-core-profile-dangling-wrappers and is not filed again).
CLOSED_FU="fu-resolvebase-dotdot-after-symlink fu-suite-git-env-scrub-class fu-parity-pin-template-spacing fu-parity-ps1-timestamp-precision fu-parity-gitignore-block-order fu-parity-ps1-hook-exec-bit fu-parity-ps1-report-name-local-time fu-parity-ps1-report-backticks fu-parity-win-ps1-crlf-bom fu-parity-sh-report-stamp-two-reads fu-sync-ps1-merge-lib-stderr-5-1 fu-sync-ps1-dangling-src-symlink fu-sync-symlinked-tree-root fu-guard-config-not-l3-protected"
REOPENED_FU="fu-parity-win-source-path"
FILED_FU="fu-bootstrap-seed-use-shared-lib fu-runner-git-env-scrub fu-sync-aai-prefix-ignore"

test_4021_follow_ups() {
  local work out rcs
  work="$(new_own_scratch followups)"
  # the JSON is large (over 1 MB) and grows with the ledger: it streams from the lister straight into the checker on stdin, never through
  # a shell variable (holding it in bash and printf-piping it aborted on the Ubuntu runner with glibc "free(): invalid next size") and
  # never as one argument (Linux caps a single argv string at 128 KiB); PIPESTATUS names which side failed
  out="$(node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status all --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl" | node -e '
    const fs = require("fs");
    const root = process.argv[1];
    const closed = process.argv[2].split(" ");
    const filed = process.argv[3].split(" ");
    const reopened = process.argv[4];
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
    if (new Set(closed).size !== 14) bad.push("the closed list does not hold fourteen ids");
    // fu-parity-win-source-path: open until the hosted evidence H2, or closed by the phase 5 closeout ride with a source naming a test
    // file and a TEST id it holds followed by a colon and a ps1-quality run id (D-FU of node-first-phase5-closeout)
    const re = by.get(reopened);
    if (!re) bad.push(reopened + " is not in the registry");
    else if (re.closed) {
      const rsrc = closeSource.get(reopened) ?? "";
      const rm = /(tests\/[A-Za-z0-9_.\/-]+\.(?:sh|mjs)) (TEST-[0-9]+):?/.exec(rsrc);
      if (re.status !== "done" || re.resolved_by !== "node-first-phase5-closeout") bad.push(reopened + " is closed by " + re.resolved_by + " (" + re.status + "), want an open item or a close by node-first-phase5-closeout");
      else if (!rm) bad.push(reopened + " close source names no test file and TEST id: " + rsrc);
      else if (!fs.existsSync(root + "/" + rm[1]) || !fs.readFileSync(root + "/" + rm[1], "utf8").includes(rm[2] + ":")) bad.push(reopened + " close source " + rm[1] + " holds no " + rm[2] + ":");
      else if (!/ps1-quality run [0-9]+/.test(rsrc)) bad.push(reopened + " close source names no ps1-quality run id: " + rsrc);
    }
    for (const id of closed) {
      const it = by.get(id);
      if (!it) { bad.push(id + " is not in the registry"); continue; }
      if (!it.closed || it.status !== "done") bad.push(id + " is not closed as done (" + it.status + ")");
      if (it.resolved_by !== "sync-on-node") bad.push(id + " resolved_by is " + it.resolved_by);
      const src = closeSource.get(id) ?? "";
      const m = /(tests\/[A-Za-z0-9_.\/-]+\.(?:sh|mjs)) (TEST-[0-9]+)/.exec(src);
      if (!m) { bad.push(id + " source names no test file and TEST id: " + src); continue; }
      const file = root + "/" + m[1];
      if (!fs.existsSync(file)) { bad.push(id + " source file " + m[1] + " does not exist"); continue; }
      if (!fs.readFileSync(file, "utf8").includes(m[2] + ":")) bad.push(id + " source " + m[1] + " holds no " + m[2] + ":");
    }
    // the three this ride filed are read from the filing records it wrote (ref and severity as filed); a later close, drop or reopen by
    // another ride is not a failure of this ride, so the open state is not required
    for (const id of filed) {
      let fil = null;
      for (const line of fs.readFileSync(root + "/docs/ai/decisions.jsonl", "utf8").split("\n")) {
        if (!line.includes(id)) continue;
        let rec;
        try { rec = JSON.parse(line); } catch { continue; }
        if (rec.type === "follow_up" && rec.id === id) { fil = rec; break; }
      }
      if (!fil) { bad.push(id + " is not filed"); continue; }
      if (fil.ref_id !== "sync-on-node") bad.push(id + " was filed with ref " + fil.ref_id);
      if (fil.severity !== "P3") bad.push(id + " was filed at " + fil.severity);
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT" "$CLOSED_FU" "$FILED_FU" "$REOPENED_FU"
    printf '\nRC %s %s' "${PIPESTATUS[0]}" "${PIPESTATUS[1]}")" || log_fail "TEST-4021: the follow-up check failed to run"
  rcs="${out##*$'\n'RC }"
  out="${out%$'\n'RC *}"
  [[ "$rcs" == "0 0" ]] || log_fail "TEST-4021: the follow-up pipeline exited $rcs (follow-ups list, checker)"
  [[ -z "$out" ]] || log_fail "TEST-4021: $out"
  safe_rm_own "$work"
  log_pass "TEST-4021: the fourteen follow-ups are closed with resolved_by sync-on-node and a source naming a test file and a TEST id it holds, fu-parity-win-source-path is open or closed by the phase 5 closeout with its hosted run id, and the three suggested follow-ups were filed by this ride at P3 with ref sync-on-node (a later close by another ride is allowed)"
}

# TEST-4022 (D-PHASE5): the phase 5 re-measure. Every tracked .sh and .ps1 under .aai/scripts (lib included) is measured with the plan's
# section 1 method (non-blank, non-comment lines, /usr/bin/grep under bash) and classified: launcher (20 code lines or fewer and no policy
# token), deprecation launcher (a first-lines RETIRED comment), kept native (a row of the RFC-0017 kept-native table) or logic. The latest re-measure section
# of docs/analysis/node-first-remaining-plan.md must list exactly the files that are not launchers (a deleted deprecation launcher it lists is fine) with their classes, the
# twin duplication (the smaller side of a pair whose two files are both logic), the open P1 and P2 follow-ups of the plan's refs and the
# parity and Pester status; the RFC-0017 phase 5 status is done only when every criterion of section 5 holds on that measurement.
test_4022_phase5_remeasure() {
  local work f n out
  work="$(new_own_scratch phase5)"
  : > "$work/measure.tsv"
  while IFS= read -r -d '' f; do
    case "$f" in .aai/scripts/*.sh|.aai/scripts/*.ps1) ;; *) continue ;; esac
    n="$(/usr/bin/grep -cvE '^[[:space:]]*(#|$)' "$PROJECT_ROOT/$f" || true)"
    printf '%s\t%s\n' "$n" "$f" >> "$work/measure.tsv"
  done < <(git -C "$PROJECT_ROOT" ls-files -z -- .aai/scripts)
  [[ -s "$work/measure.tsv" ]] || log_fail "TEST-4022: the measurement found no script"
  out="$(T4022_LIB="$PROJECT_ROOT/tests/skills/lib/script-classes.mjs" node --input-type=module -e '
    import fs from "node:fs";
    const { KEPT_NATIVE_HEADING, classify, parseKeptNative, fileTableProblems, recordsThroughDate } = await import(process.env.T4022_LIB);
    const [root, measure] = process.argv.slice(1);
    const { readDecisionsLedger, foldFollowUps } = await import(root + "/.aai/scripts/follow-ups.mjs");
    const read = (p) => fs.readFileSync(root + "/" + p, "utf8");
    const bad = [];
    const rows = fs.readFileSync(measure, "utf8").split("\n").filter(Boolean).map((l) => { const [n, f] = l.split("\t"); return { file: f, code: Number(n) }; });
    // kept native: the rows of the RFC-0017 table under the heading "Kept native scripts", read and classified
    // through the shared classifier (tests/skills/lib/script-classes.mjs, D-CLASS)
    const rfcText = read("docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md");
    const rfc = rfcText.split("\n");
    const keptRows = parseKeptNative(rfcText);
    const kept = new Map(keptRows.filter((k) => k.reason !== "").map((k) => [k.file, k.reason]));
    if (!rfc.includes(KEPT_NATIVE_HEADING)) bad.push("RFC-0017 has no Kept native scripts heading");
    else if (kept.size < 4) bad.push("the RFC kept-native table holds " + kept.size + " rows, want 4 or more");
    for (const r of rows) r.cls = classify({ file: r.file, text: read(r.file), kept: keptRows });
    for (const f of kept.keys()) if (!rows.some((r) => r.file === f)) bad.push("the RFC kept-native table names " + f + ", which is not a tracked script");
    const rest = rows.filter((r) => r.cls !== "launcher").sort((a, b) => (a.file < b.file ? -1 : 1));
    // the twin duplication: pairs (same stem, .sh and .ps1) whose two files are both logic
    let dup = 0;
    for (const r of rows) {
      if (!r.file.endsWith(".sh") || r.cls !== "logic") continue;
      const twin = rows.find((x) => x.file === r.file.replace(/\.sh$/, ".ps1"));
      if (twin && twin.cls === "logic") dup += Math.min(r.code, twin.code);
    }
    // the LATEST re-measure section of the plan ("## N. Re-measure after ... (YYYY-MM-DD)"; section 6 stays as a dated record)
    const plan = read("docs/analysis/node-first-remaining-plan.md").split("\n");
    let at = -1, secNo = "", secDate = "";
    plan.forEach((l, i) => { const m = /^## (\d+)\. Re-measure after .+ \((\d{4}-\d{2}-\d{2})\)$/.exec(l); if (m) { at = i; secNo = m[1]; secDate = m[2]; } });
    if (at < 0) { process.stdout.write(bad.concat("the plan has no Re-measure after ... section").join("; ")); process.exit(0); }
    let end = plan.length;
    for (let i = at + 1; i < plan.length; i += 1) if (plan[i].startsWith("## ")) { end = i; break; }
    const sec = plan.slice(at + 1, end);
    const tableAfter = (header) => {
      const h = sec.findIndex((l) => l.startsWith(header));
      const out = [];
      if (h < 0) return null;
      for (let i = h + 2; i < sec.length && sec[i].startsWith("|"); i += 1) out.push(sec[i].split("|").slice(1, -1).map((c) => c.trim()));
      return out;
    };
    const t = tableAfter("| File |");
    if (!t) bad.push("section " + secNo + " has no file table");
    else {
      // the file and its class are compared with the tree; the code lines are the record own measurement, and a deprecation launcher the record
      // lists may already be deleted (its scheduled deletion), so neither an edit of a kept-native script nor that deletion fails here; a new
      // undeclared logic script is the strict check of TEST-4025
      bad.push(...fileTableProblems({ rows: t, tree: rest }).map((p) => "section " + secNo + ": " + p));
    }
    const dupLine = sec.find((l) => l.startsWith("- Twin duplication: "));
    if (!dupLine) bad.push("section " + secNo + " has no Twin duplication line");
    else if (!dupLine.startsWith("- Twin duplication: " + dup + " code lines")) bad.push("section " + secNo + " twin duplication is not " + dup + ": " + dupLine);
    // the open P1 and P2 follow-ups of the plan twelve roadmap refs, install-path-parity-harness and node-first*; the owner sign-off items
    // (fu-amend-*) are counted by spec-amend list, not here
    const refs = new Set();
    for (const l of plan) { const m = /^\| \d+ \| ([a-z0-9-]+) \|/.exec(l); if (m) refs.add(m[1]); }
    if (refs.size !== 12) bad.push("the plan lists " + refs.size + " roadmap refs, want 12");
    // as of the end of the day the section is dated: a later filing or close belongs to a later record
    const open = foldFollowUps(recordsThroughDate(readDecisionsLedger(root + "/docs/ai/decisions.jsonl").records, secDate)).items
      .filter((i) => (i.severity === "P1" || i.severity === "P2") && !i.closed && !i.id.startsWith("fu-amend-") && (refs.has(i.ref_id) || String(i.ref_id).startsWith("node-first")))
      .map((i) => i.id + " " + i.severity + " " + i.ref_id).sort();
    const f = tableAfter("| Follow-up |");
    if (!f) bad.push("section " + secNo + " has no follow-up table");
    else {
      const got = f.map((c) => c[0].replace(/`/g, "") + " " + c[1] + " " + c[2]).filter((x) => !x.startsWith("none ")).sort();
      if (JSON.stringify(got) !== JSON.stringify(open)) bad.push("the section " + secNo + " follow-up table differs from the ledger: want [" + open.join(" ; ") + "] got [" + got.join(" ; ") + "]");
    }
    const hosted = sec.find((l) => l.startsWith("- Parity harness and Pester (H1 to H3): "));
    if (!hosted) bad.push("section " + secNo + " has no Parity harness and Pester line");
    // the phase 5 status of the RFC row follows the criteria
    const hostedPassed = hosted ? /: passed\b/.test(hosted) : false;
    const logic = rest.filter((r) => r.cls === "logic");
    const allHold = logic.length === 0 && dup === 0 && open.length === 0 && hostedPassed;
    const row = rfc.filter((l) => l.startsWith("| 5 |"));
    if (row.length !== 1) bad.push("the RFC phase 5 row appears " + row.length + " times");
    else {
      const cells = row[0].split("|").map((c) => c.trim());
      const status = cells[3];
      if (allHold && status !== "done") bad.push("every section 5 criterion holds but the RFC phase 5 status is " + status);
      if (!allHold && status !== "in progress") bad.push("a section 5 criterion does not hold but the RFC phase 5 status is " + status);
      if (!allHold) {
        if (!row[0].includes("section " + secNo)) bad.push("the RFC phase 5 row does not name the section " + secNo + " list");
        for (const r of logic) if (!row[0].includes(r.file.replace(/^\.aai\/scripts\//, ""))) bad.push("the RFC phase 5 row does not name " + r.file);
      }
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT" "$work/measure.tsv")" || log_fail "TEST-4022: the phase 5 check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4022: $out"
  safe_rm_own "$work"
  log_pass "TEST-4022: the latest re-measure section of the remaining-scripts plan lists exactly the non-launcher scripts with their classes, the twin duplication, the open P1 and P2 follow-ups of the plan refs as of its date and the hosted status, and the RFC-0017 phase 5 status follows the section 5 criteria"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-4020 to TEST-4022)"
  check_deps
  test_4020_docs
  test_4021_follow_ups
  test_4022_phase5_remeasure
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
