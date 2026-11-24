#!/usr/bin/env bash
#
# Test: aai-phase5-closeout
# (docs/specs/SPEC-0311-spec-node-first-phase5-closeout.md; TEST-4024, TEST-4033, TEST-4034, TEST-4035 and TEST-4036)
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

# TEST-4033 (Spec-AC-10, D-REMEASURE and D-HOSTED): the record of this ride. Plan section 7 ("## 7. Re-measure after the phase 5 closeout
# (date)") is a DATED record, checked against the tree and the ledger as of that record: its file table (every reason non-empty, no logic
# row) names exactly the non-launcher scripts of the tree by file and class while section 7 is the latest re-measure section (the code line
# counts are the record's own measurement, and a deprecation launcher it lists may be gone: its scheduled deletion), and is checked for its
# shape only once a later re-measure section exists; its follow-up table equals the open P1 and P2 follow-ups of the plan refs in the ledger
# as of the end of the record date; its twin duplication line, outside-ref line (each id filed at P2 under a ref outside the plan refs),
# root-cause line and hosted line are present and well-formed; the odd-root downgrade is read from the records this ride wrote; the RFC phase
# 5 row follows the section 5 criteria while section 7 is the latest (done only when the hosted line reads "passed on <sha> (ps1-quality
# run <id>)", else in progress naming section 7); and, once the hosted line is "passed" and section 7 is the latest, the record commit
# changed only the four D-HOSTED paths when the cited sha object exists here. A later close of an item this ride filed or named is not a
# failure; the live guard of the tree is TEST-4025 (the strict check) and, for the latest section, TEST-4022.
test_4033_remeasure_record() {
  local out
  out="$(T4033_LIB="$CLASSES_LIB" T4033_ROOT="$PROJECT_ROOT" node --input-type=module -e '
    import fs from "node:fs";
    import { execFileSync } from "node:child_process";
    const { countCodeLines, classify, parseKeptNative, fileTableProblems, recordsThroughDate, filingRecord, oddDropProblems } = await import(process.env.T4033_LIB);
    const root = process.env.T4033_ROOT;
    const { readDecisionsLedger, foldFollowUps } = await import(root + "/.aai/scripts/follow-ups.mjs");
    const SELF = "node-first-phase5-closeout";
    const read = (p) => fs.readFileSync(root + "/" + p, "utf8");
    const bad = [];
    const files = execFileSync("git", ["-C", root, "ls-files", "-z", "--", ".aai/scripts"], { encoding: "utf8" })
      .split("\0").filter((f) => /\.(sh|ps1)$/.test(f));
    const rfcText = read("docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md");
    const kept = parseKeptNative(rfcText);
    const rows = files.map((f) => { const t = read(f); return { file: f, code: countCodeLines(t), cls: classify({ file: f, text: t, kept }) }; });
    const rest = rows.filter((r) => r.cls !== "launcher").sort((a, b) => (a.file < b.file ? -1 : 1));
    let dup = 0;
    for (const r of rows) {
      if (!r.file.endsWith(".sh") || r.cls !== "logic") continue;
      const twin = rows.find((x) => x.file === r.file.replace(/\.sh$/, ".ps1"));
      if (twin && twin.cls === "logic") dup += Math.min(r.code, twin.code);
    }
    const plan = read("docs/analysis/node-first-remaining-plan.md").split("\n");
    const HEAD = /^## (\d+)\. Re-measure after (.+) \((\d{4}-\d{2}-\d{2})\)$/;
    const heads = plan.map((l, i) => ({ i, m: HEAD.exec(l) })).filter((h) => h.m);
    const s7 = heads.find((h) => h.m[1] === "7" && h.m[2] === "the phase 5 closeout");
    if (!s7) { process.stdout.write("the plan has no section 7 Re-measure after the phase 5 closeout (date) heading"); process.exit(0); }
    // section 7 is the latest re-measure section, or a dated record once a later one exists
    const latest = heads[heads.length - 1] === s7;
    let end = plan.length;
    for (let i = s7.i + 1; i < plan.length; i += 1) if (plan[i].startsWith("## ")) { end = i; break; }
    const sec = plan.slice(s7.i + 1, end);
    const tableAfter = (header) => {
      const h = sec.findIndex((l) => l.startsWith(header));
      if (h < 0) return null;
      const out = [];
      for (let i = h + 2; i < sec.length && sec[i].startsWith("|"); i += 1) out.push(sec[i].split("|").slice(1, -1).map((c) => c.trim()));
      return out;
    };
    const t = tableAfter("| File |");
    if (!t) bad.push("section 7 has no file table");
    else bad.push(...fileTableProblems({ rows: t, tree: latest ? rest.map((r) => ({ file: r.file, code: r.code, cls: r.cls })) : null }).map((p) => "section 7: " + p));
    const logic = rest.filter((r) => r.cls === "logic");
    if (latest && logic.length) bad.push("the measurement holds logic files: " + logic.map((r) => r.file).join(" "));
    const dupLine = sec.find((l) => l.startsWith("- Twin duplication: "));
    if (!dupLine) bad.push("section 7 has no Twin duplication line");
    else if (!/^- Twin duplication: [0-9]+ code lines/.test(dupLine)) bad.push("section 7 twin duplication line is malformed: " + dupLine);
    else if (latest && !dupLine.startsWith("- Twin duplication: " + dup + " code lines")) bad.push("section 7 twin duplication is not " + dup + ": " + dupLine);
    // the ledger as of the end of the record date: open P1 and P2 follow-ups of the plan refs, install-path-parity-harness and node-first*
    const refs = new Set();
    for (const l of plan) { const m = /^\| \d+ \| ([a-z0-9-]+) \|/.exec(l); if (m) refs.add(m[1]); }
    if (refs.size !== 12) bad.push("the plan lists " + refs.size + " roadmap refs, want 12");
    const records = readDecisionsLedger(root + "/docs/ai/decisions.jsonl").records;
    const all = foldFollowUps(recordsThroughDate(records, s7.m[3])).items;
    const inScope = (i) => refs.has(i.ref_id) || i.ref_id === "install-path-parity-harness" || String(i.ref_id).startsWith("node-first");
    const open = all.filter((i) => (i.severity === "P1" || i.severity === "P2") && !i.closed && !i.id.startsWith("fu-amend-") && inScope(i))
      .map((i) => i.id + " " + i.severity + " " + i.ref_id).sort();
    const f = tableAfter("| Follow-up |");
    if (!f) bad.push("section 7 has no follow-up table");
    else {
      const got = f.map((c) => c[0].replace(/`/g, "") + " " + c[1] + " " + c[2]).filter((x) => !x.startsWith("none ")).sort();
      if (JSON.stringify(got) !== JSON.stringify(open)) bad.push("the section 7 follow-up table differs from the ledger as of " + s7.m[3] + ": want [" + open.join(" ; ") + "] got [" + got.join(" ; ") + "]");
      if (open.length === 0 && !f.some((c) => c[0].replace(/`/g, "") === "none")) bad.push("section 7 has no none row for an empty follow-up table");
    }
    // the open P2 items whose subject sounds related but whose ref lies outside the plan refs: each was filed at P2 under such a ref (the claim
    // of the line); whether it is still open is not this ride to pin
    const outLine = sec.find((l) => l.startsWith("- Open P2 follow-ups outside the plan refs"));
    if (!outLine) bad.push("section 7 has no outside-ref line");
    else {
      const named = [...outLine.matchAll(/`(fu-[a-z0-9-]+)`/g)].map((m) => m[1]).sort();
      const want = ["fu-hook-gate-skips-renamed-doc", "fu-release-preflight-scrubbed-env", "fu-release-pwsh-identity-crash"];
      if (JSON.stringify(named) !== JSON.stringify(want)) bad.push("the outside-ref line names [" + named.join(" ") + "], want [" + want.join(" ") + "]");
      for (const id of named) {
        const it = filingRecord(records, id);
        if (!it) bad.push(id + " was never filed in the ledger");
        else if (it.severity !== "P2" || inScope(it)) bad.push(id + " was not filed as a P2 outside the plan refs (" + it.severity + " " + it.ref_id + ")");
      }
    }
    // the hosted line, in one of its two forms, and the root-cause line bound to it
    const hosted = sec.find((l) => l.startsWith("- Parity harness and Pester (H1 to H3): "));
    let passed = false, sha = "", notNamed = false, oddOpen = false;
    if (!hosted) bad.push("section 7 has no Parity harness and Pester line");
    else {
      const rest2 = hosted.slice("- Parity harness and Pester (H1 to H3): ".length);
      const pm = /^passed on ([0-9a-f]{40}) \(ps1-quality run ([0-9]+)\)/.exec(rest2);
      if (pm) { passed = true; sha = pm[1]; }
      else if (!/^pending: \S/.test(rest2)) bad.push("the hosted line is neither passed on <full sha> (ps1-quality run <id>) nor pending: <what remains>: " + hosted);
    }
    const rc = sec.find((l) => l.startsWith("- Root cause of fu-parity-win-odd-root-dirs: "));
    if (!rc) bad.push("section 7 has no root-cause line");
    else {
      const body = rc.slice("- Root cause of fu-parity-win-odd-root-dirs: ".length);
      // third form (D-ODD step 6): the cause stays unnamed after three hosted diagnostic runs; the item stays open for the owner
      notNamed = /^not named after three hosted diagnostic runs \(D-ODD step 6\): \S.*, shown by ps1-quality run [0-9]+$/.test(body);
      if (passed) { if (!/, shown by ps1-quality run [0-9]+$/.test(body) || /^pending/.test(body)) bad.push("the hosted line passed but the root-cause line names no cause with a run id: " + rc); }
      else if (notNamed) bad.push("the root-cause line is in the not-named form while the hosted line is not passed: " + rc);
      else if (!/^pending\b/.test(body) && !/, shown by ps1-quality run [0-9]+$/.test(body)) bad.push("the root-cause line is neither pending nor a named cause: " + rc);
      if (notNamed) {
        const odd = all.find((x) => x.id === "fu-parity-win-odd-root-dirs");
        if (!odd) bad.push("the root-cause line is not named but fu-parity-win-odd-root-dirs is not in the ledger");
        else if (!odd.closed) {
          oddOpen = true;
          if (!f || !f.some((c) => c[0].replace(/`/g, "") === "fu-parity-win-odd-root-dirs")) bad.push("the root-cause line is not named but the section 7 follow-up table lacks fu-parity-win-odd-root-dirs");
        } else bad.push(...oddDropProblems(records, SELF));
      }
    }
    // the RFC phase 5 row: its status follows the criteria while section 7 is the latest section; a later section governs it afterwards
    const allHold = passed && logic.length === 0 && dup === 0 && open.length === 0;
    const rfc = rfcText.split("\n").filter((l) => l.startsWith("| 5 |"));
    if (rfc.length !== 1) bad.push("the RFC phase 5 row appears " + rfc.length + " times");
    else {
      const status = rfc[0].split("|").map((c) => c.trim())[3];
      if (latest) {
        if (allHold && status !== "done") bad.push("every section 5 criterion holds but the RFC phase 5 status is " + status);
        if (!allHold && status !== "in progress") bad.push("a section 5 criterion does not hold but the RFC phase 5 status is " + status);
        if (!allHold && !rfc[0].includes("section 7")) bad.push("the RFC phase 5 row does not name section 7");
        if (oddOpen && (status !== "in progress" || !rfc[0].includes("fu-parity-win-odd-root-dirs"))) bad.push("the root-cause line is not named and the item is open but the RFC phase 5 row is not in progress naming fu-parity-win-odd-root-dirs");
      }
      if (!rfc[0].includes("eighteenth slice") || !rfc[0].includes("node-first-phase5-closeout")) bad.push("the RFC phase 5 row lacks the eighteenth slice sentence linking the intake");
    }
    // D-HOSTED step 4: the record commit changed only the four record paths (checked when the cited object exists here and section 7 is the latest)
    if (passed && latest) {
      let have = true;
      try { execFileSync("git", ["-C", root, "cat-file", "-e", sha + "^{commit}"], { stdio: "ignore" }); } catch { have = false; }
      // the range sha..HEAD only describes the ride while the hosted sha is an ancestor of HEAD; after a squash merge it is not (the HEAD of main
      // is one commit that holds every file of the ride), so that arm is skipped with a note
      let anc = have;
      if (have) { try { execFileSync("git", ["-C", root, "merge-base", "--is-ancestor", sha, "HEAD"], { stdio: "ignore" }); } catch { anc = false; } }
      if (!have) console.error("INFO: TEST-4033 could not check the record diff: " + sha + " is not in this checkout");
      else if (!anc) console.error("INFO: TEST-4033 skipped the record diff: " + sha + " is not an ancestor of HEAD (a squash merge or a rebase)");
      else {
        // every commit after the hosted sha that rewrites the plan is a record commit and may touch only the four record paths; a later
        // code commit that does not touch the plan (a remediation of a pin) is not one, so it no longer trips this check
        const ok = new Set(["docs/analysis/node-first-remaining-plan.md", "docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md", "docs/product/node-first-phase5-closeout.md", "docs/ai/decisions.jsonl"]);
        const recs = execFileSync("git", ["-C", root, "log", "--format=%H", sha + "..HEAD", "--", "docs/analysis/node-first-remaining-plan.md"], { encoding: "utf8" }).split("\n").filter(Boolean);
        const extra = [];
        for (const c of recs) for (const n of execFileSync("git", ["-C", root, "diff-tree", "--no-commit-id", "--name-only", "-r", c], { encoding: "utf8" }).split("\n").filter(Boolean)) if (!ok.has(n)) extra.push(n);
        if (extra.length) bad.push("the record commit changed paths outside the four record paths: " + extra.join(" "));
      }
    }
    process.stdout.write(bad.join("; "));
  ')" || log_fail "TEST-4033: the record check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4033: $out"
  log_pass "TEST-4033: plan section 7 is a well-formed dated record; its file table, follow-up table, outside-ref line, root-cause line and hosted line match the tree (while it is the latest section) and the ledger as of its date, and the RFC phase 5 row follows them"
}

# TEST-4034 (Spec-AC-11, D-FU and D-HOSTED order): the follow-up closes. fu-cfshare-redact-escape-robust is closed now. The two Windows
# items follow the hosted line of plan section 7: while it reads pending both are still open; once it reads passed both are closed with
# resolved_by this ride, a source naming a test file and a TEST id that the file holds followed by a colon, and a ps1-quality run id.
test_4034_follow_ups() {
  local out
  out="$(T4034_LIB="$CLASSES_LIB" T4034_ROOT="$PROJECT_ROOT" node --input-type=module -e '
    import fs from "node:fs";
    const root = process.env.T4034_ROOT;
    const SELF = "node-first-phase5-closeout";
    const bad = [];
    const { oddDropProblems, rideStatusRecord } = await import(process.env.T4034_LIB);
    const records = fs.readFileSync(root + "/docs/ai/decisions.jsonl", "utf8").split("\n").map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
    // a close of this ride is read from the follow_up_status record the ride wrote; a later reopen or close by another ride is not what this check reads
    const checkClosed = (id, wantFile, wantTest, needRun) => {
      const rec = rideStatusRecord(records, id, SELF);
      if (!rec) { bad.push(id + " has no follow_up_status record of " + SELF); return; }
      if (rec.status !== "done") { bad.push(id + " is not closed as done by the ride (" + rec.status + ")"); return; }
      const src = String(rec.source ?? "");
      const m = /(tests\/[A-Za-z0-9_.\/-]+\.(?:sh|mjs)) (TEST-[0-9]+)/.exec(src);
      if (!m) { bad.push(id + " source names no test file and TEST id: " + src); return; }
      if (m[1] !== wantFile || m[2] !== wantTest) bad.push(id + " source names " + m[1] + " " + m[2] + ", want " + wantFile + " " + wantTest);
      if (!fs.existsSync(root + "/" + m[1])) bad.push(id + " source file " + m[1] + " does not exist");
      else if (!fs.readFileSync(root + "/" + m[1], "utf8").includes(m[2] + ":")) bad.push(id + " source " + m[1] + " holds no " + m[2] + ":");
      if (needRun && !/ps1-quality run [0-9]+/.test(src)) bad.push(id + " source names no ps1-quality run id: " + src);
    };
    checkClosed("fu-cfshare-redact-escape-robust", "tests/skills/lib/cloudflare-share.test.mjs", "TEST-4029", false);
    // the hosted line of section 7 decides the state of the two Windows items
    const plan = fs.readFileSync(root + "/docs/analysis/node-first-remaining-plan.md", "utf8").split("\n");
    // section 7 is this ride\x27s record; a later re-measure section has its own hosted line
    const at7 = plan.findIndex((l) => /^## 7\. Re-measure after the phase 5 closeout \(/.test(l));
    if (at7 < 0) bad.push("the plan has no section 7 Re-measure after the phase 5 closeout heading");
    let end7 = plan.length;
    for (let i = at7 + 1; i > 0 && i < plan.length; i += 1) if (plan[i].startsWith("## ")) { end7 = i; break; }
    const sec7 = at7 < 0 ? [] : plan.slice(at7 + 1, end7);
    const line = sec7.filter((l) => l.startsWith("- Parity harness and Pester (H1 to H3): ")).pop() ?? "";
    const passed = /: passed on [0-9a-f]{40} \(ps1-quality run [0-9]+\)/.test(line);
    const pending = /: pending: \S/.test(line);
    if (!passed && !pending) bad.push("the hosted line of section 7 is neither passed nor pending: " + line);
    const win = [
      ["fu-parity-win-odd-root-dirs", "tests/skills/lib/install-parity.test.mjs", "TEST-4031"],
      ["fu-parity-win-source-path", "tests/skills/lib/install-parity.test.mjs", "TEST-4032"],
    ];
    // the not-named root-cause form (D-ODD step 6): the odd-root item is open for the owner or dropped as superseded by its P3 successor (owner downgrade 2026-11-23), the source-path item closes with the run
    const rcLine = sec7.filter((l) => l.startsWith("- Root cause of fu-parity-win-odd-root-dirs: ")).pop() ?? "";
    const notNamed = /^- Root cause of fu-parity-win-odd-root-dirs: not named after three hosted diagnostic runs \(D-ODD step 6\): /.test(rcLine);
    if (notNamed && !passed) bad.push("the root-cause line is in the not-named form while the hosted line is not passed");
    for (const [id, file, test] of win) {
      if (passed && notNamed && id === "fu-parity-win-odd-root-dirs") bad.push(...oddDropProblems(records, SELF));
      else if (passed) checkClosed(id, file, test, true);
      else {
        // the hosted line still reads pending: neither item may have been closed by this ride yet
        if (!records.some((r) => r.type === "follow_up" && r.id === id)) bad.push(id + " was never filed in the ledger");
        else if (rideStatusRecord(records, id, SELF)) bad.push(id + " is closed by this ride while the hosted line still reads pending (D-HOSTED: the Windows items close in the record commit)");
      }
    }
    process.stdout.write(bad.join("; "));
  ')" || log_fail "TEST-4034: the follow-up check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4034: $out"
  log_pass "TEST-4034: fu-cfshare-redact-escape-robust is closed with its test source; the two Windows follow-ups follow the hosted line: open while it is pending, closed with a run id once it passed, or dropped as superseded by the successor under the owner decision"
}

# TEST-4036 (Spec-AC-13, D-WIRE and D-AMEND): the wiring and the record. One CHANGELOG heading of the D-WIRE title whose entry names each
# consumer-visible change; the suite on the suite map and the weights; the frozen release reference on both ps1-quality path lists (the
# helper only on the suite-map globs, a disclosed deviation); a PROFILES entry for every .aai file this branch added; the product doc
# complete once it exists; the D-AMEND records in the ledger and spec-amend list --strict exiting 0.
test_4036_docs_and_wiring() {
  local out rc=0 base added f
  out="$(T4036_ROOT="$PROJECT_ROOT" node --input-type=module -e '
    import fs from "node:fs";
    const root = process.env.T4036_ROOT;
    const read = (p) => fs.readFileSync(root + "/" + p, "utf8");
    const bad = [];
    // CHANGELOG
    const log = read("CHANGELOG.md").split("\n");
    // a release cut rolls "## [unreleased] — " into "## [vYYYY.MM.DD] — ", so the pin accepts both spellings (as test-aai-hook-installer-docs.sh does)
    const TITLE = /^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2}[0-9A-Za-z.-]*)\] — Node-first phase 5 closeout$/;
    const at = log.map((l, i) => (TITLE.test(l) ? i : -1)).filter((i) => i >= 0);
    if (at.length !== 1) bad.push("CHANGELOG.md holds " + at.length + " headings of the D-WIRE title (an [unreleased] or [vYYYY.MM.DD] heading ending in: Node-first phase 5 closeout)");
    else {
      let end = log.length;
      for (let i = at[0] + 1; i < log.length; i += 1) if (log[i].startsWith("## ")) { end = i; break; }
      const body = log.slice(at[0] + 1, end).join("\n");
      const named = ["cloudflare-share", "aai-release.ps1", "abbreviated", "common parameter", "positional", "without a value", "source path"];
      for (const w of named) if (!body.includes(w)) bad.push("the CHANGELOG entry does not name " + JSON.stringify(w));
    }
    // suite map and weights
    const map = read("tests/skills/suite-map.yaml").split("\n");
    const globs = (name) => {
      const h = map.findIndex((l) => l === "  " + name + ":");
      if (h < 0) return null;
      const out = [];
      for (let i = h + 1; i < map.length && !/^  [a-z0-9]/.test(map[i]); i += 1) { const m = /^\s+- (.+)$/.exec(map[i]); if (m) out.push(m[1].replace(/^[\x27"]|[\x27"]$/g, "")); }
      return out;
    };
    const mine = globs("aai-phase5-closeout");
    if (!mine) bad.push("suite-map.yaml has no aai-phase5-closeout entry");
    else for (const g of ["docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md", "docs/analysis/node-first-remaining-plan.md", "CHANGELOG.md", "docs/product/node-first-phase5-closeout.md", "tests/skills/lib/script-classes.mjs", ".aai/scripts/*.sh", ".aai/scripts/*.ps1", ".aai/scripts/lib/*.sh", "tests/skills/test-aai-follow-ups.sh", "tests/skills/test-aai-phase5-closeout.sh"]) if (!mine.includes(g)) bad.push("the suite-map entry lacks " + g);
    const cut = globs("aai-release-cut");
    if (!cut) bad.push("suite-map.yaml has no aai-release-cut entry");
    else for (const g of ["tests/fixtures/aai-release-reference/**", "tests/skills/lib/release-reference.mjs"]) if (!cut.includes(g)) bad.push("the aai-release-cut entry lacks " + g);
    const w = read("tests/skills/suite-weights.tsv").split("\n");
    const wi = w.findIndex((l) => /^aai-phase5-closeout\t[0-9]+$/.test(l));
    if (wi < 0) bad.push("suite-weights.tsv has no aai-phase5-closeout row");
    else if (!w[wi - 1].startsWith("# sample aai-phase5-closeout ")) bad.push("the aai-phase5-closeout weight row has no sample comment line before it");
    // ps1-quality path lists: the frozen reference on both
    const wf = read(".github/workflows/ps1-quality.yml");
    const n = wf.split("\n").filter((l) => l.trim().replace(/^- /, "").replace(/^[\x27"]|[\x27"]$/g, "") === "tests/fixtures/aai-release-reference/**").length;
    if (n < 2) bad.push("ps1-quality.yml names tests/fixtures/aai-release-reference/** " + n + " times, want both path lists");
    process.stdout.write(bad.join("; "));
  ')" || log_fail "TEST-4036: the wiring check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4036: $out"

  # a PROFILES entry for every .aai file this branch added (checked when a base ref resolves here)
  base=""
  for f in origin/main main; do
    if git -C "$PROJECT_ROOT" rev-parse --verify -q "$f^{commit}" >/dev/null 2>&1; then base="$f"; break; fi
  done
  if [[ -n "$base" ]]; then
    added="$(git -C "$PROJECT_ROOT" diff --name-only --diff-filter=A "$base"...HEAD -- .aai 2>/dev/null || true)"
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      /usr/bin/grep -qF -- "$f" "$PROJECT_ROOT/.aai/system/PROFILES.yaml" || log_fail "TEST-4036: the new file $f has no PROFILES.yaml entry"
    done <<< "$added"
  else
    log_info "TEST-4036: no base ref here; the PROFILES check for new .aai files is not run"
  fi

  # the product doc, once it exists, carries every required section
  if [[ -f "$PROJECT_ROOT/docs/product/node-first-phase5-closeout.md" ]]; then
    out="$(T4036_ROOT="$PROJECT_ROOT" node --input-type=module -e '
      import fs from "node:fs";
      const { missingProductSections } = await import(process.env.T4036_ROOT + "/.aai/scripts/lib/product-doc.mjs");
      const text = fs.readFileSync(process.env.T4036_ROOT + "/docs/product/node-first-phase5-closeout.md", "utf8");
      const miss = missingProductSections(text);
      const fm = /^capability: (.+)$/m.exec(text);
      const bad = [];
      if (miss.length) bad.push("the product doc is missing or has empty sections: " + miss.join(", "));
      if (!fm || fm[1].trim() !== "node-first-phase5-closeout") bad.push("the product doc capability is not node-first-phase5-closeout");
      process.stdout.write(bad.join("; "));
    ')" || log_fail "TEST-4036: the product-doc check failed to run"
    [[ -z "$out" ]] || log_fail "TEST-4036: $out"
  else
    log_info "TEST-4036: the product doc does not exist yet; its check is not run"
  fi

  # the D-AMEND records: one contract record per closed spec whose test body this scope edits, and a clean strict list
  out="$(T4036_ROOT="$PROJECT_ROOT" node --input-type=module -e '
    import fs from "node:fs";
    const root = process.env.T4036_ROOT;
    const recs = fs.readFileSync(root + "/docs/ai/decisions.jsonl", "utf8").split("\n").filter((l) => l.includes("\"spec_amendment\"") && l.includes("\"node-first-phase5-closeout\""))
      .map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter((r) => r && r.type === "spec_amendment" && r.ref_id === "node-first-phase5-closeout");
    const bad = [];
    for (const [spec, tests] of [["SPEC-0310", ["TEST-4021", "TEST-4022"]], ["SPEC-0282", ["TEST-3529"]], ["SPEC-0063", ["TEST-019"]], ["SPEC-0284", ["TEST-3565", "TEST-3566", "TEST-3568", "TEST-3570"]]]) {
      const mine = recs.filter((r) => String(r.spec).includes(spec + "-") && r.amendment_class === "contract");
      if (mine.length === 0) { bad.push("no contract spec_amendment record for " + spec); continue; }
      const text = mine.map((r) => r.what + " " + r.why).join(" ");
      for (const t of tests) if (!text.includes(t)) bad.push(spec + " records do not name " + t);
    }
    process.stdout.write(bad.join("; "));
  ')" || log_fail "TEST-4036: the amendment check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4036: $out"
  node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --strict --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-4036: spec-amend list --strict exited $rc"
  log_pass "TEST-4036: the CHANGELOG entry, the suite-map and weight rows, the ps1-quality path entries, the product doc and the D-AMEND records are in place and spec-amend list --strict exits 0"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-4024, TEST-4033 to TEST-4036)"
  check_deps
  test_4024_kept_native_rows
  test_4033_remeasure_record
  test_4034_follow_ups
  test_4035_every_launcher_runs
  test_4036_docs_and_wiring
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
