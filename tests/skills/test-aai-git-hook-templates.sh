#!/usr/bin/env bash
#
# Test: aai-git-hook-templates
# (docs/specs/SPEC-DRAFT-spec-git-hook-bodies-single-source.md, TEST-3432..3444)
#
# The four git hook bodies live once, in .aai/templates/git-hooks/; both installers read them and
# write the same bytes. Every case works in fresh mktemp git repositories with a local identity;
# nothing touches the checkout's own hooks.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-git-hook-templates.sh                        # run all
#   bash tests/skills/test-aai-git-hook-templates.sh test_3432_templates_single_copy
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-git-hook-templates"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SH_INSTALLER="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh"
PS1_INSTALLER="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.ps1"
TPL_DIR="$PROJECT_ROOT/.aai/templates/git-hooks"
TPL_INDEX="$TPL_DIR/pre-commit-index.sh"
TPL_GUARD="$TPL_DIR/pre-commit-guard-checks.sh"
TPL_REFTX="$TPL_DIR/reference-transaction.sh"
TPL_PUSH="$TPL_DIR/pre-push.sh"
BASELINE_SHA="244ef0bf"
SPEC_ID="spec-git-hook-bodies-single-source"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/vendor-hook-installer.sh"

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
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-git-hook-templates.XXXXXX")" && pwd -P)"
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# make_repo <dir>: a fresh git repository with a local identity and no autocrlf.
make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email fixture@example.invalid
  git -C "$1" config user.name fixture
  git -C "$1" config commit.gpgsign false
  git -C "$1" config core.autocrlf false
}

# compose_expected <out file> [template dir]: the D-COMPOSE pre-commit bytes built from the templates
# (line 1 of the index template, the whole guard block, lines 2..end of the index template).
compose_expected() {
  local out="$1" d="${2:-$TPL_DIR}"
  { sed -n '1p' "$d/pre-commit-index.sh"; cat "$d/pre-commit-guard-checks.sh"; sed -n '2,$p' "$d/pre-commit-index.sh"; } > "$out"
}

# hooks_path <repo>: the hooks directory of a fixture repository.
hooks_path() { printf '%s/.git/hooks' "$1"; }

# --- TEST-3432 ------------------------------------------------------------------------------

# template_problems <file> <first line> <marker>: prints problems of one template (empty when clean).
template_problems() {
  node -e '
    const fs = require("fs");
    const [file, first, marker, last] = process.argv.slice(1);
    if (!fs.existsSync(file)) { process.stdout.write("missing"); process.exit(0); }
    const buf = fs.readFileSync(file);
    const bad = [];
    if (buf.some((b) => b > 0x7e || b === 13 || (b < 0x20 && b !== 10 && b !== 9))) bad.push("non-ASCII, CR or control byte");
    if (buf.length < 2 || buf[buf.length - 1] !== 10 || buf[buf.length - 2] === 10) bad.push("not exactly one final LF");
    const lines = buf.toString("latin1").split("\n");
    if (lines[0] !== first) bad.push("first line is not " + first);
    if (!lines.some((l) => l === marker || l.startsWith(marker + " "))) bad.push("lacks the marker " + marker);
    if (last && lines[lines.length - 2] !== last) bad.push("last line is not " + last);
    process.stdout.write(bad.join("; "));
  ' "$@"
}

# tracked_mode <path>: the git index mode of a tracked path (empty when untracked).
tracked_mode() {
  local line
  line="$(git -C "$PROJECT_ROOT" ls-files -s -- "$1")"
  printf '%s' "${line%% *}"
}

# installer_body_problems <installer>: prints the hook-body leftovers of one installer (empty when clean).
installer_body_problems() {
  local f="$1" out=""
  if /usr/bin/grep -qE 'REFTXHOOK|GUARDBLOCK|PREPUSHHOOK|<<-?[[:space:]]*.?HOOK.?$' "$f"; then out="$out heredoc delimiter;"; fi
  if /usr/bin/grep -qE '^[[:space:]]*\$(hookBody|reftxBody|prePushBody)[[:space:]]*=' "$f"; then out="$out here-string assignment;"; fi
  if /usr/bin/grep -qE '^[[:space:]]*(aai_guarded=0|_cg_refused=0|_gc_rc=0)$' "$f"; then out="$out body sentinel line;"; fi
  if /usr/bin/grep -qE '^[[:space:]]*GEN=' "$f"; then out="$out GEN= generator line;"; fi
  printf '%s' "$out"
}

test_3432_templates_single_copy() {
  local spec name first marker last p out f sentinel
  for spec in \
    "pre-commit-index.sh|#!/usr/bin/env bash|# AAI:INDEX-AUTOGEN|" \
    "pre-commit-guard-checks.sh|# AAI:GUARD-CHECKS BEGIN|# AAI:GUARD-CHECKS BEGIN|# AAI:GUARD-CHECKS END" \
    "reference-transaction.sh|#!/bin/sh|# AAI:REF-GUARD|" \
    "pre-push.sh|#!/usr/bin/env bash|# AAI:CLOSE-GATE|"; do
    IFS='|' read -r name first marker last <<<"$spec"
    p="$TPL_DIR/$name"
    out="$(template_problems "$p" "$first" "$marker" "$last")"
    [[ -z "$out" ]] || log_fail "TEST-3432: .aai/templates/git-hooks/$name: $out"
    [[ "$(tracked_mode ".aai/templates/git-hooks/$name")" == "100644" ]] || log_fail "TEST-3432: .aai/templates/git-hooks/$name is not tracked with mode 100644"
  done
  # The body sentinels live in the templates (so a body that lost one is reported) and in no installer.
  /usr/bin/grep -qE '^[[:space:]]*aai_guarded=0$' "$TPL_REFTX" 2>/dev/null || log_fail "TEST-3432: reference-transaction.sh lacks the aai_guarded=0 sentinel"
  /usr/bin/grep -qE '^[[:space:]]*_cg_refused=0$' "$TPL_PUSH" 2>/dev/null || log_fail "TEST-3432: pre-push.sh lacks the _cg_refused=0 sentinel"
  /usr/bin/grep -qE '^[[:space:]]*_gc_rc=0$' "$TPL_GUARD" 2>/dev/null || log_fail "TEST-3432: pre-commit-guard-checks.sh lacks the _gc_rc=0 sentinel"
  /usr/bin/grep -qE '^GEN=' "$TPL_INDEX" 2>/dev/null || log_fail "TEST-3432: pre-commit-index.sh lacks the GEN= generator line"
  for f in "$SH_INSTALLER" "$PS1_INSTALLER"; do
    out="$(installer_body_problems "$f")"
    [[ -z "$out" ]] || log_fail "TEST-3432: ${f##*/} still embeds a hook body:$out"
  done
  # Positive control: the baseline installers are reported by the same check.
  for sentinel in sh ps1; do
    git -C "$PROJECT_ROOT" show "$BASELINE_SHA:.aai/scripts/install-pre-commit-hook.$sentinel" > "$TEST_DIR/baseline.$sentinel"
    out="$(installer_body_problems "$TEST_DIR/baseline.$sentinel")"
    [[ -n "$out" ]] || log_fail "TEST-3432: positive control: the baseline .$sentinel installer was not reported"
  done
  log_pass "TEST-3432: four ASCII LF templates with mode 100644, and no hook body left in either installer"
}

# --- TEST-3433 ------------------------------------------------------------------------------

test_3433_sh_writes_templates() {
  local fx="$TEST_DIR/sh write/repo" fx2="$TEST_DIR/sh print/repo" h tok want="$TEST_DIR/want.pre-commit" rc=0 slot
  [[ -f "$TPL_INDEX" ]] || log_fail "TEST-3433: the templates do not exist"
  make_repo "$fx"
  ( cd "$fx" && bash "$SH_INSTALLER" ) >"$TEST_DIR/w.out" 2>"$TEST_DIR/w.err" || rc=$?
  [[ "$rc" == 0 ]] || { cat "$TEST_DIR/w.out" "$TEST_DIR/w.err" >&2; log_fail "TEST-3433: the sh installer exited $rc"; }
  h="$(hooks_path "$fx")"
  compose_expected "$want"
  cmp -s "$h/pre-commit" "$want" || log_fail "TEST-3433: pre-commit differs from the D-COMPOSE bytes"
  cmp -s "$h/reference-transaction" "$TPL_REFTX" || log_fail "TEST-3433: reference-transaction differs from its template"
  cmp -s "$h/pre-push" "$TPL_PUSH" || log_fail "TEST-3433: pre-push differs from its template"
  for slot in pre-commit reference-transaction pre-push; do
    [[ -x "$h/$slot" ]] || log_fail "TEST-3433: $slot is not executable"
  done
  /usr/bin/grep -qxF 'AAI:REF-GUARD refused this refs/heads/main update.' "$h/reference-transaction" || log_fail "TEST-3433: the written reference-transaction hook lacks its refused line"
  make_repo "$fx2"
  for tok in index guard-checks ref-guard pre-push; do
    case "$tok" in
      index) want="$TPL_INDEX" ;;
      guard-checks) want="$TPL_GUARD" ;;
      ref-guard) want="$TPL_REFTX" ;;
      pre-push) want="$TPL_PUSH" ;;
    esac
    ( cd "$fx2" && bash "$SH_INSTALLER" --print "$tok" ) > "$TEST_DIR/print.out" 2>"$TEST_DIR/print.err" || log_fail "TEST-3433: --print $tok failed"
    cmp -s "$TEST_DIR/print.out" "$want" || log_fail "TEST-3433: --print $tok differs from its template"
  done
  ( cd "$fx2" && bash "$SH_INSTALLER" --print ) > "$TEST_DIR/print.out" 2>/dev/null || log_fail "TEST-3433: bare --print failed"
  cmp -s "$TEST_DIR/print.out" "$TPL_INDEX" || log_fail "TEST-3433: bare --print differs from the index template"
  for slot in pre-commit reference-transaction pre-push; do
    [[ ! -e "$(hooks_path "$fx2")/$slot" ]] || log_fail "TEST-3433: --print wrote $slot"
  done
  log_pass "TEST-3433: the sh installer writes the D-COMPOSE bytes, executable, and --print emits exactly the template bytes and writes nothing"
}

# --- TEST-3437 ------------------------------------------------------------------------------

test_3437_no_early_reader() {
  local pat n t body="$TEST_DIR/baseline.hookBody"
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/pipe-grep-q-ratchet.sh"
  pat="$PGQ_PATTERN"
  for t in "$TPL_INDEX" "$TPL_GUARD" "$TPL_REFTX" "$TPL_PUSH"; do
    [[ -f "$t" ]] || log_fail "TEST-3437: ${t##*/} does not exist"
    n="$(/usr/bin/grep -cE "$pat" "$t" || true)"
    [[ "$n" == 0 ]] || log_fail "TEST-3437: ${t##*/} holds $n early-closing reader pipes"
  done
  git -C "$PROJECT_ROOT" show "$BASELINE_SHA:.aai/scripts/install-pre-commit-hook.ps1" > "$TEST_DIR/baseline.ps1"
  awk '/^\$hookBody = @/{p=1; next} /^.@$/{if(p){exit}} p' "$TEST_DIR/baseline.ps1" > "$body"
  n="$(/usr/bin/grep -cE "$pat" "$body" || true)"
  [[ "$n" == 5 ]] || log_fail "TEST-3437: positive control: the baseline ps1 hookBody gave $n matches, expected 5"
  log_pass "TEST-3437: PGQ_PATTERN matches 0 lines in the four templates and 5 in the baseline ps1 hookBody"
}

# --- TEST-3434 ------------------------------------------------------------------------------

# hook_shape_problems <file>: prints a problem when the hook lacks a final LF, holds a CR or is not executable.
hook_shape_problems() {
  local f="$1" last
  last="$(tail -c 1 "$f" | od -An -tx1 | tr -d ' \n')"
  [[ "$last" == "0a" ]] || printf 'no final LF in %s; ' "${f##*/}"
  if [[ "$(tr -d '\r' < "$f" | wc -c | tr -d ' ')" != "$(wc -c < "$f" | tr -d ' ')" ]]; then printf 'CR byte in %s; ' "${f##*/}"; fi
  [[ -x "$f" ]] || printf '%s is not executable; ' "${f##*/}"
}

# run_ps1 <repo> [args]: the ps1 installer under pwsh, run from inside the repo.
run_ps1() {
  local repo="$1"; shift
  ( cd "$repo" && pwsh -NoProfile -NonInteractive -File "$PS1_INSTALLER" "$@" )
}

test_3434_twin_bytes() {
  need_tool TEST-3434 pwsh || return 0
  local a="$TEST_DIR/twin/sh repo" b="$TEST_DIR/twin/ps1 repo" slot out rc=0
  make_repo "$a"; make_repo "$b"
  ( cd "$a" && bash "$SH_INSTALLER" ) >/dev/null 2>&1 || log_fail "TEST-3434: the sh installer failed"
  run_ps1 "$b" >"$TEST_DIR/t.out" 2>"$TEST_DIR/t.err" || rc=$?
  [[ "$rc" == 0 ]] || { cat "$TEST_DIR/t.out" "$TEST_DIR/t.err" >&2; log_fail "TEST-3434: the ps1 installer exited $rc"; }
  for slot in pre-commit reference-transaction pre-push; do
    cmp -s "$(hooks_path "$a")/$slot" "$(hooks_path "$b")/$slot" || log_fail "TEST-3434: the $slot hooks differ between the installers"
    out="$(hook_shape_problems "$(hooks_path "$b")/$slot")"
    [[ -z "$out" ]] || log_fail "TEST-3434: ps1-written hook: $out"
  done
  log_pass "TEST-3434: the ps1 and sh installers write byte-identical LF hooks, executable, with a final newline"
}

# --- TEST-3436 ------------------------------------------------------------------------------

# big_stage_fixture <repo>: docs/a.md plus 4000 further staged paths (over 200 KB of staged names), and
# stub generator and docs-audit scripts (the audit stub appends each argv line to $AUDIT_LOG).
big_stage_fixture() {
  local repo="$1"
  mkdir -p "$repo/.aai/scripts" "$repo/docs"
  printf 'import fs from "node:fs";\nfs.writeFileSync("docs/INDEX.md", "# index\\n");\n' > "$repo/.aai/scripts/generate-docs-index.mjs"
  printf 'import fs from "node:fs";\nfs.appendFileSync(process.env.AUDIT_LOG, process.argv.slice(2).join(" ") + "\\n");\n' > "$repo/.aai/scripts/docs-audit.mjs"
  printf '# a\n' > "$repo/docs/a.md"
  ( cd "$repo" && node -e '
    const fs = require("fs");
    fs.mkdirSync("zbulk");
    for (let i = 0; i < 4000; i++) fs.writeFileSync("zbulk/" + "p".repeat(40) + "-" + String(i).padStart(4, "0") + ".txt", "");
  ' && git add docs/a.md zbulk )
}

# pipefail_problems <label> <repo>: runs the written pre-commit under bash and prints the first problem.
pipefail_problems() {
  local label="$1" repo="$2" log="$TEST_DIR/audit-$$.log" gates
  : > "$log"
  big_stage_fixture "$repo"
  if ! ( cd "$repo" && AUDIT_LOG="$log" bash "$(hooks_path "$repo")/pre-commit" ) >"$TEST_DIR/pf.out" 2>"$TEST_DIR/pf.err"; then
    printf '%s: the hook exited non-zero on the large staged set' "$label"; return 0
  fi
  [[ -f "$repo/docs/INDEX.md" ]] || { printf '%s: docs/INDEX.md was not regenerated' "$label"; return 0; }
  [[ -n "$(git -C "$repo" diff --cached --name-only -- docs/INDEX.md)" ]] || { printf '%s: docs/INDEX.md was not staged' "$label"; return 0; }
  ( cd "$repo" && node -e '
    const fs = require("fs");
    fs.mkdirSync("docs/specs", { recursive: true });
    fs.writeFileSync("docs/specs/SPEC-9999-big.md", "---\nid: SPEC-9999\nstatus: done\n---\n" + "line of a long staged spec body\n".repeat(7000));
  ' && git add docs/specs/SPEC-9999-big.md )
  : > "$log"
  if ! ( cd "$repo" && AUDIT_LOG="$log" bash "$(hooks_path "$repo")/pre-commit" ) >"$TEST_DIR/pf.out" 2>"$TEST_DIR/pf.err"; then
    printf '%s: the hook exited non-zero on the large staged spec' "$label"; return 0
  fi
  gates="$(/usr/bin/grep -c -e '--gate-file' "$log" || true)"
  [[ "$gates" == 1 ]] || printf '%s: the audit stub received %s --gate-file calls, expected 1' "$label" "$gates"
}

test_3436_pipefail_large_stage() {
  local out a="$TEST_DIR/pipefail/sh repo" b="$TEST_DIR/pipefail/ps1 repo"
  make_repo "$a"
  ( cd "$a" && bash "$SH_INSTALLER" ) >/dev/null 2>&1 || log_fail "TEST-3436: the sh installer failed"
  out="$(pipefail_problems "sh-written hook" "$a")"
  [[ -z "$out" ]] || log_fail "TEST-3436: $out"
  if need_tool TEST-3436 pwsh; then
    make_repo "$b"
    run_ps1 "$b" >/dev/null 2>&1 || log_fail "TEST-3436: the ps1 installer failed"
    out="$(pipefail_problems "ps1-written hook" "$b")"
    [[ -z "$out" ]] || log_fail "TEST-3436: $out"
  fi
  log_pass "TEST-3436: a hook written by either installer regenerates the index and runs one --gate-file call on a 4000-path staged set"
}

# --- TEST-3439 ------------------------------------------------------------------------------

to_crlf() { awk '{ printf "%s\r\n", $0 }' "$1" > "$1.crlf" && mv "$1.crlf" "$1"; }

test_3439_crlf_and_rerun() {
  need_tool TEST-3439 pwsh || return 0
  local a="$TEST_DIR/crlf/sh root" b="$TEST_DIR/crlf/ps1 root" slot f out rc=0 keep="$TEST_DIR/crlf/keep"
  [[ -f "$TPL_INDEX" ]] || log_fail "TEST-3439: the templates do not exist"
  mkdir -p "$keep"
  make_repo "$a"; make_repo "$b"
  vendor_hook_installer "$a" sh; vendor_hook_installer "$b" ps1
  for f in "$a"/.aai/templates/git-hooks/*.sh "$b"/.aai/templates/git-hooks/*.sh; do to_crlf "$f"; done
  ( cd "$a" && bash .aai/scripts/install-pre-commit-hook.sh ) >/dev/null 2>&1 || log_fail "TEST-3439: the sh installer failed on CRLF templates"
  ( cd "$b" && pwsh -NoProfile -NonInteractive -File .aai/scripts/install-pre-commit-hook.ps1 ) >/dev/null 2>&1 || log_fail "TEST-3439: the ps1 installer failed on CRLF templates"
  for slot in pre-commit reference-transaction pre-push; do
    out="$(hook_shape_problems "$(hooks_path "$a")/$slot")$(hook_shape_problems "$(hooks_path "$b")/$slot")"
    [[ -z "$out" ]] || log_fail "TEST-3439: from CRLF templates: $out"
    cmp -s "$(hooks_path "$a")/$slot" "$(hooks_path "$b")/$slot" || log_fail "TEST-3439: the $slot hooks differ between the installers"
    cp "$(hooks_path "$a")/$slot" "$keep/$slot"
  done
  # A plain re-run of either installer over hooks the OTHER one wrote changes no byte.
  ( cd "$a" && pwsh -NoProfile -NonInteractive -File "$PS1_INSTALLER" ) >"$TEST_DIR/r1.out" 2>&1 || log_fail "TEST-3439: ps1 re-run over sh-written hooks failed"
  ( cd "$b" && bash "$SH_INSTALLER" ) >"$TEST_DIR/r2.out" 2>&1 || log_fail "TEST-3439: sh re-run over ps1-written hooks failed"
  for slot in pre-commit reference-transaction pre-push; do
    cmp -s "$(hooks_path "$a")/$slot" "$keep/$slot" || log_fail "TEST-3439: the ps1 re-run changed $slot"
    cmp -s "$(hooks_path "$b")/$slot" "$keep/$slot" || log_fail "TEST-3439: the sh re-run changed $slot"
  done
  for f in "$TEST_DIR/r1.out" "$TEST_DIR/r2.out"; do
    for slot in "AAI pre-commit hook already installed" "AAI reference-transaction hook already installed" "AAI pre-push hook already installed"; do
      /usr/bin/grep -qF "$slot" "$f" || log_fail "TEST-3439: a re-run did not print '$slot' ($f)"
    done
  done
  log_pass "TEST-3439: CRLF templates still yield CR-free identical hooks, and a plain re-run over the other installer's hooks changes nothing"
}

# --- TEST-3435 ------------------------------------------------------------------------------

test_3435_pester() {
  local pester="$SCRIPT_DIR/install-pre-commit-hook.Tests.ps1"
  [[ -f "$pester" ]] || log_fail "TEST-3435: tests/skills/install-pre-commit-hook.Tests.ps1 does not exist"
  need_tool TEST-3435 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3435 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PESTER_FILE="$pester" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 6) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3435: install-pre-commit-hook.Tests.ps1 failed, skipped a case or ran fewer than 6 cases (rc=$rc)"; }
  log_pass "TEST-3435: install-pre-commit-hook.Tests.ps1 passes with no skip under pwsh ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

# --- TEST-3438 ------------------------------------------------------------------------------

# template_for_token <token>: the template file name of one hook token.
template_for_token() {
  case "$1" in
    index) printf 'pre-commit-index.sh' ;;
    guard-checks) printf 'pre-commit-guard-checks.sh' ;;
    ref-guard) printf 'reference-transaction.sh' ;;
    pre-push) printf 'pre-push.sh' ;;
  esac
}

# missing_round <label> <engine sh|ps1> <token>: one installer with one template removed.
missing_round() {
  local label="$1" engine="$2" tok="$3" root name want seed rc=0 slot
  root="$TEST_DIR/missing/$label $engine $tok"
  name="$(template_for_token "$tok")"
  want="$root/.aai/templates/git-hooks/$name"
  make_repo "$root"
  vendor_hook_installer "$root" "$engine"
  rm -f "$want"
  mkdir -p "$(hooks_path "$root")"
  seed="$TEST_DIR/missing/seed.pre-push"
  printf '#!/bin/sh\n# AAI:CLOSE-GATE old body\nexit 0\n' > "$seed"
  cp "$seed" "$(hooks_path "$root")/pre-push"
  if [[ "$engine" == sh ]]; then
    ( cd "$root" && bash .aai/scripts/install-pre-commit-hook.sh ) >"$TEST_DIR/m.out" 2>"$TEST_DIR/m.err" || rc=$?
  else
    ( cd "$root" && pwsh -NoProfile -NonInteractive -File .aai/scripts/install-pre-commit-hook.ps1 ) >"$TEST_DIR/m.out" 2>"$TEST_DIR/m.err" || rc=$?
  fi
  [[ "$rc" == 1 ]] || log_fail "TEST-3438: $engine installer without $name exited $rc, expected 1"
  /usr/bin/grep -qxF "ERROR: AAI hook template missing: $want" "$TEST_DIR/m.err" || { cat "$TEST_DIR/m.err" >&2; log_fail "TEST-3438: $engine installer did not name $want on stderr"; }
  cmp -s "$seed" "$(hooks_path "$root")/pre-push" || log_fail "TEST-3438: $engine installer changed the pre-seeded pre-push without $name"
  for slot in pre-commit reference-transaction; do
    [[ ! -e "$(hooks_path "$root")/$slot" ]] || log_fail "TEST-3438: $engine installer wrote $slot without $name"
  done
  if [[ "$engine" == sh ]]; then
    rc=0; ( cd "$root" && bash .aai/scripts/install-pre-commit-hook.sh --print "$tok" ) >"$TEST_DIR/p.out" 2>"$TEST_DIR/p.err" || rc=$?
    [[ "$rc" == 1 && ! -s "$TEST_DIR/p.out" ]] || log_fail "TEST-3438: --print $tok without $name exited $rc"
    /usr/bin/grep -qxF "ERROR: AAI hook template missing: $want" "$TEST_DIR/p.err" || log_fail "TEST-3438: --print $tok did not name $want"
    rc=0; ( cd "$root" && bash .aai/scripts/install-pre-commit-hook.sh --uninstall ) >/dev/null 2>&1 || rc=$?
  else
    rc=0; ( cd "$root" && pwsh -NoProfile -NonInteractive -File .aai/scripts/install-pre-commit-hook.ps1 -Uninstall ) >/dev/null 2>&1 || rc=$?
  fi
  [[ "$rc" == 0 ]] || log_fail "TEST-3438: $engine --uninstall without $name exited $rc"
}

test_3438_missing_template() {
  local tok
  [[ -f "$TPL_INDEX" ]] || log_fail "TEST-3438: the templates do not exist"
  for tok in index guard-checks ref-guard pre-push; do
    missing_round r sh "$tok"
    if need_tool TEST-3438 pwsh; then missing_round r ps1 "$tok"; fi
  done
  log_pass "TEST-3438: a missing template refuses by name, writes and changes no hook, --print exits 1 the same way, --uninstall still exits 0"
}

# --- TEST-3440 ------------------------------------------------------------------------------

doctor_cat17() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const c = j.categories.find((x) => x.id === "CAT-17");
    process.stdout.write(c ? c.status + " " + c.reason : "absent");
  ' < <(node "$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs" --json --root "$1" 2>/dev/null || true)
}

test_3440_refguard_message_and_doctor() {
  local line a="$TEST_DIR/doctor/sh repo" b="$TEST_DIR/doctor/ps1 repo" out sel
  for line in \
    '  Fix:    re-run this ONE command with AAI_GIT_WRITE=1 set.' \
    '            POSIX shell:  AAI_GIT_WRITE=1 git commit ...' \
    "            PowerShell:   pwsh -NoProfile -Command '\$env:AAI_GIT_WRITE=1; git commit ...'" \
    '  Uninstall this guard: bash .aai/scripts/install-pre-commit-hook.sh --uninstall' \
    '            (PowerShell: pwsh .aai/scripts/install-pre-commit-hook.ps1 -Uninstall)' \
    'AAI:REF-GUARD refused this refs/heads/main update.'; do
    /usr/bin/grep -qxF -- "$line" "$TPL_REFTX" 2>/dev/null || log_fail "TEST-3440: the reference-transaction template lacks the line: $line"
  done
  make_repo "$a"; git -C "$a" checkout -q -b main 2>/dev/null || true
  ( cd "$a" && bash "$SH_INSTALLER" --arm-ref-guard ) >/dev/null 2>&1 || log_fail "TEST-3440: the sh installer could not arm the guard"
  out="$(doctor_cat17 "$a")"
  [[ "$out" == "PASS armed"* ]] || log_fail "TEST-3440: CAT-17 after the sh installer: $out"
  if need_tool TEST-3440 pwsh; then
    make_repo "$b"; git -C "$b" checkout -q -b main 2>/dev/null || true
    run_ps1 "$b" -ArmRefGuard >/dev/null 2>&1 || log_fail "TEST-3440: the ps1 installer could not arm the guard"
    out="$(doctor_cat17 "$b")"
    [[ "$out" == "PASS armed"* ]] || log_fail "TEST-3440: CAT-17 after the ps1 installer: $out"
  fi
  for sel in test_309_ps1_twin_static test_314_print_flag test_316_ps1_ascii_outside_here_strings test_611_print_ref_guard_body \
    test_612_foreign_reftx_names_a_real_command test_613_install_discloses_ref_guard test_614_help_documents_the_new_surface; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-git-ref-guard.sh" "$sel" >"$TEST_DIR/rg.out" 2>&1 || { cat "$TEST_DIR/rg.out" >&2; log_fail "TEST-3440: test-aai-git-ref-guard.sh $sel failed"; }
  done
  log_pass "TEST-3440: the template carries the D-MSG lines, CAT-17 reports armed for both installers, and the seven ref-guard selectors pass"
}

# --- TEST-3441 ------------------------------------------------------------------------------

test_3441_downstream_install() {
  local tgt="$TEST_DIR/core target/proj" name want="$TEST_DIR/core.want" slot prof="$PROJECT_ROOT/.aai/system/PROFILES.yaml" n
  make_repo "$tgt"
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$tgt" --profile core >/dev/null 2>&1 || log_fail "TEST-3441: aai-sync.sh --profile core failed"
  for name in pre-commit-guard-checks.sh pre-commit-index.sh pre-push.sh reference-transaction.sh; do
    [[ -f "$tgt/.aai/templates/git-hooks/$name" ]] || log_fail "TEST-3441: the core install lacks .aai/templates/git-hooks/$name"
    cmp -s "$tgt/.aai/templates/git-hooks/$name" "$TPL_DIR/$name" || log_fail "TEST-3441: the installed $name differs from the source"
    n="$(awk -v want="  - .aai/templates/git-hooks/$name" '/^core:/{c=1; next} /^[a-z]/{c=0} c && $0==want{k++} END{print k+0}' "$prof")"
    [[ "$n" == 1 ]] || log_fail "TEST-3441: PROFILES lists $name $n times under core, expected once"
  done
  ( cd "$tgt" && bash .aai/scripts/install-pre-commit-hook.sh ) >/dev/null 2>&1 || log_fail "TEST-3441: the target's own sh installer failed"
  compose_expected "$want"
  cmp -s "$(hooks_path "$tgt")/pre-commit" "$want" || log_fail "TEST-3441: the target's pre-commit differs from the D-COMPOSE bytes"
  cmp -s "$(hooks_path "$tgt")/reference-transaction" "$TPL_REFTX" || log_fail "TEST-3441: the target's reference-transaction differs from its template"
  cmp -s "$(hooks_path "$tgt")/pre-push" "$TPL_PUSH" || log_fail "TEST-3441: the target's pre-push differs from its template"
  if need_tool TEST-3441 pwsh; then
    ( cd "$tgt" && bash .aai/scripts/install-pre-commit-hook.sh --uninstall ) >/dev/null 2>&1 || log_fail "TEST-3441: the target's uninstall failed"
    for slot in pre-commit reference-transaction pre-push; do
      [[ ! -e "$(hooks_path "$tgt")/$slot" ]] || log_fail "TEST-3441: uninstall left $slot"
    done
    ( cd "$tgt" && pwsh -NoProfile -NonInteractive -File .aai/scripts/install-pre-commit-hook.ps1 ) >/dev/null 2>&1 || log_fail "TEST-3441: the target's own ps1 installer failed"
    cmp -s "$(hooks_path "$tgt")/pre-commit" "$want" || log_fail "TEST-3441: the target's ps1-written pre-commit differs from the D-COMPOSE bytes"
    cmp -s "$(hooks_path "$tgt")/reference-transaction" "$TPL_REFTX" || log_fail "TEST-3441: the target's ps1-written reference-transaction differs"
    cmp -s "$(hooks_path "$tgt")/pre-push" "$TPL_PUSH" || log_fail "TEST-3441: the target's ps1-written pre-push differs"
  fi
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-layer-profiles.sh" test_manifest_conformance >"$TEST_DIR/lp.out" 2>&1 || { cat "$TEST_DIR/lp.out" >&2; log_fail "TEST-3441: test-aai-layer-profiles.sh test_manifest_conformance failed"; }
  log_pass "TEST-3441: aai-sync --profile core into a spaced path vendors the four templates and the target's own installers write the D-COMPOSE bytes"
}

# --- TEST-3442 ------------------------------------------------------------------------------

# fn_body <file> <function>: the text of one shell function (from its header line to the next
# column-0 closing brace).
fn_body() {
  awk -v fn="$2" '$0 ~ "^"fn"\\(\\)"{p=1} p{print} p && /^}/{exit}' "$1"
}

# bare_cp_sites <dir>: file:line of every cp of a path ending in install-pre-commit-hook.sh or .ps1
# in a tests/skills/*.sh other than the shared helper and this suite.
bare_cp_sites() {
  local f
  for f in "$1"/test-aai-*.sh; do
    [[ "${f##*/}" == test-aai-git-hook-templates.sh ]] && continue
    awk -v f="${f##*/}" '/^[[:space:]]*cp[[:space:]]/ && /install-pre-commit-hook\.(sh|ps1)"?[[:space:]]*$/ { print f ":" NR }' "$f"
  done
}

test_3442_fixtures_use_helper() {
  local spec file fn out sel
  for spec in \
    "test-aai-docs-audit.sh setup_spec0010_hook_repo" \
    "test-aai-docs-audit.sh setup_spec0011_hook_repo" \
    "test-aai-doctor.sh test_1344_cat17_seam1_installed_hook_passes" \
    "test-aai-doctor.sh t812_repo" \
    "test-aai-git-ref-guard.sh test_310_doctor_category" \
    "test-aai-hygiene-pack.sh sg_repo" \
    "test-aai-hygiene-pack.sh test_813_ps1_twin_parity" \
    "test-aai-hygiene-pack.sh test_818_ps1_upgrade_is_byte_exact_and_order_checked" \
    "test-aai-tracked-ignored.sh test_1709_real_hook_refuses_commit"; do
    file="${spec%% *}"; fn="${spec#* }"
    out="$(fn_body "$SCRIPT_DIR/$file" "$fn")"
    [[ -n "$out" ]] || log_fail "TEST-3442: $file has no function $fn"
    /usr/bin/grep -qF 'vendor_hook_installer' <<<"$out" || log_fail "TEST-3442: $file $fn does not vendor its installer through vendor_hook_installer"
  done
  out="$(bare_cp_sites "$SCRIPT_DIR")"
  [[ -z "$out" ]] || log_fail "TEST-3442: a suite copies an installer file by hand: $out"
  # Positive control: a scratch copy of one suite with a bare cp is reported.
  mkdir -p "$TEST_DIR/cpctl"
  { cat "$SCRIPT_DIR/test-aai-doctor.sh"; printf '  cp "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh" "$d/.aai/scripts/install-pre-commit-hook.sh"\n'; } > "$TEST_DIR/cpctl/test-aai-doctor.sh"
  out="$(bare_cp_sites "$TEST_DIR/cpctl")"
  [[ "$out" == test-aai-doctor.sh:* ]] || log_fail "TEST-3442: positive control: a bare cp of an installer was not reported ($out)"
  for sel in "test-aai-hygiene-pack.sh test_031_guard_config_conformance" "test-aai-hygiene-pack.sh test_813_ps1_twin_parity" \
    "test-aai-hygiene-pack.sh test_818_ps1_upgrade_is_byte_exact_and_order_checked" "test-aai-doctor.sh test_1344_cat17_seam1_installed_hook_passes" \
    "test-aai-git-ref-guard.sh test_310_doctor_category" "test-aai-tracked-ignored.sh test_1709_real_hook_refuses_commit"; do
    file="${sel%% *}"; fn="${sel#* }"
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/$file" "$fn" >"$TEST_DIR/f.out" 2>&1 || { cat "$TEST_DIR/f.out" >&2; log_fail "TEST-3442: $file $fn failed"; }
  done
  log_pass "TEST-3442: the nine fixtures vendor their installer through the helper, no suite copies an installer by hand, and the six pins pass"
}

# --- TEST-3443 ------------------------------------------------------------------------------

# selected_for <path>: the select-suites output for one changed path.
selected_for() {
  printf '%s\n' "$1" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT"
}

test_3443_wiring() {
  local f out n s wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" tsv="$SCRIPT_DIR/suite-weights.tsv" nsl="$SCRIPT_DIR/lib/nested-suite-lint.mjs"
  local helper_suites="aai-docs-audit aai-doctor aai-git-ref-guard aai-hygiene-pack aai-tracked-ignored"
  for f in .aai/templates/git-hooks/pre-commit-index.sh .aai/templates/git-hooks/pre-commit-guard-checks.sh .aai/templates/git-hooks/reference-transaction.sh \
    .aai/templates/git-hooks/pre-push.sh .aai/scripts/install-pre-commit-hook.sh .aai/scripts/install-pre-commit-hook.ps1 \
    tests/skills/lib/vendor-hook-installer.sh tests/skills/install-pre-commit-hook.Tests.ps1; do
    out="$(selected_for "$f")"
    [[ "$out" == *'SELECTED aai-git-hook-templates '* ]] || log_fail "TEST-3443: $f does not select aai-git-hook-templates: $out"
  done
  # The helper and the templates it copies reach every suite whose fixtures read them.
  for f in tests/skills/lib/vendor-hook-installer.sh .aai/templates/git-hooks/pre-push.sh; do
    out="$(selected_for "$f")"
    for s in $helper_suites; do
      [[ "$out" == *"SELECTED $s "* || "$out" == *"CORE $s "* ]] || log_fail "TEST-3443: $f does not select $s: $out"
    done
  done
  n="$(awk -F'\t' '$1=="aai-git-hook-templates"{c++} END{print c+0}' "$tsv")"
  [[ "$n" == 1 ]] || log_fail "TEST-3443: suite-weights holds $n aai-git-hook-templates rows, expected 1"
  for f in test_090_suite_map_pin test_129_mutation_gate_suite_registration; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-hygiene-pack.sh" "$f" >/dev/null 2>&1 || log_fail "TEST-3443: test-aai-hygiene-pack.sh $f failed"
  done
  node "$nsl" --allowlist "$SCRIPT_DIR/lib/nested-suite-allowlist.tsv" "$SCRIPT_DIR" >/dev/null 2>&1 || log_fail "TEST-3443: nested-suite-lint failed"
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >/dev/null 2>&1 || log_fail "TEST-3443: check-cd-subshell-leak.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$SCRIPT_DIR" >/dev/null 2>&1 || log_fail "TEST-3443: check-test-registration.mjs failed"
  # The early-closing-reader ratchet: no row for this suite, the helper or either installer.
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/pipe-grep-q-ratchet.sh"
  out="$(pgq_scan "$SCRIPT_DIR")$(pgq_scan "$SCRIPT_DIR/lib")$(pgq_scan_shipping "$PROJECT_ROOT")"
  case "$out" in
    *test-aai-git-hook-templates.sh*|*vendor-hook-installer.sh*|*install-pre-commit-hook.sh*) log_fail "TEST-3443: the early-closing-reader ratchet reports a file of this scope: $out" ;;
  esac
  n="$(awk '/^  push:/{s="push"} /^  pull_request:/{s="pr"} /^  workflow_dispatch/{s=""} s!="" && $0=="      - '"'"'.aai/templates/git-hooks/**'"'"'"{c[s]++} END{print c["push"]+0, c["pr"]+0}' "$wf")"
  [[ "$n" == "1 1" ]] || log_fail "TEST-3443: the ps1-quality path lists hold the templates glob '$n' times (push pr), expected 1 1"
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-win-fallback.sh" test_034 >/dev/null 2>&1 || log_fail "TEST-3443: test-aai-win-fallback.sh test_034 failed"
  /usr/bin/grep -qxF '.aai/templates/git-hooks/*.sh text eol=lf' "$PROJECT_ROOT/.gitattributes" || log_fail "TEST-3443: .gitattributes lacks the D-EOL line"
  log_pass "TEST-3443: select-suites, weights, hygiene pins, lints, ps1-quality path lists and .gitattributes are wired"
}

# --- TEST-3444 ------------------------------------------------------------------------------

# code_lines <file>: non-blank, non-comment lines (the plan's method; /usr/bin/grep when present).
code_lines() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -cvE '^[[:space:]]*(#|$)' "$1" || true
}

RFC17="${GHT_RFC:-$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md}"
D_RFC_SENTENCE='The eighth slice [moved the git hook bodies to shared templates](../issues/CHANGE-DRAFT-git-hook-bodies-single-source.md): both installers write the same bytes from one copy, which ends the early-closing pipes of the PowerShell-written pre-commit hook.'

test_3444_line_budget_and_rfc() {
  local d="${GHT_BUDGET_DIR:-$PROJECT_ROOT}" sh_t sh_c ps_t ps_c tpl_t=0 f row n out rc=0
  sh_t="$(wc -l < "$d/.aai/scripts/install-pre-commit-hook.sh" | tr -d ' ')"
  sh_c="$(code_lines "$d/.aai/scripts/install-pre-commit-hook.sh")"
  ps_t="$(wc -l < "$d/.aai/scripts/install-pre-commit-hook.ps1" | tr -d ' ')"
  ps_c="$(code_lines "$d/.aai/scripts/install-pre-commit-hook.ps1")"
  for f in "$d"/.aai/templates/git-hooks/*.sh; do
    [[ -f "$f" ]] || log_fail "TEST-3444: the templates do not exist"
    tpl_t=$((tpl_t + $(wc -l < "$f" | tr -d ' ')))
  done
  [[ "$sh_t" -le 1050 && "$sh_c" -le 560 ]] || log_fail "TEST-3444: install-pre-commit-hook.sh has $sh_t lines and $sh_c code lines, caps 1050 and 560"
  [[ "$ps_t" -le 840 && "$ps_c" -le 570 ]] || log_fail "TEST-3444: install-pre-commit-hook.ps1 has $ps_t lines and $ps_c code lines, caps 840 and 570"
  [[ "$tpl_t" -le 330 ]] || log_fail "TEST-3444: the four templates hold $tpl_t lines, cap 330"
  log_info "line counts (lines/code) before: sh 1313/749, ps1 1097/749, embedded bodies sh 312/217 ps1 308/216"
  log_info "line counts (lines/code) after:  sh $sh_t/$sh_c, ps1 $ps_t/$ps_c, templates together $tpl_t"
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3444: test_2624_inventory_matches_tree exited $rc"; }
  row="$(/usr/bin/grep '^| 5 | ' "$RFC17" || true)"
  [[ "$row" == *'| in progress |'* ]] || log_fail "TEST-3444: the phase 5 row is not in progress"
  [[ "$row" == *"$D_RFC_SENTENCE"* ]] || log_fail "TEST-3444: the phase 5 row lacks the D-RFC sentence"
  n="$(/usr/bin/grep -cF -- "$D_RFC_SENTENCE" "$RFC17" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3444: the D-RFC sentence appears $n times, expected once"
  [[ "$row" == *'git-hook-bodies-single-source.md)'* ]] || log_fail "TEST-3444: the phase 5 row has no link ending git-hook-bodies-single-source.md"
  log_pass "TEST-3444: sh $sh_t/$sh_c, ps1 $ps_t/$ps_c, templates $tpl_t lines within the caps; the RFC-0017 inventory equals the tree and the phase 5 row holds the sentence once"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3432..3444)"
  check_deps
  setup_fixture
  test_3432_templates_single_copy
  test_3433_sh_writes_templates
  test_3434_twin_bytes
  test_3436_pipefail_large_stage
  test_3435_pester
  test_3437_no_early_reader
  test_3438_missing_template
  test_3439_crlf_and_rerun
  test_3440_refguard_message_and_doctor
  test_3441_downstream_install
  test_3442_fixtures_use_helper
  test_3443_wiring
  test_3444_line_budget_and_rfc
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
