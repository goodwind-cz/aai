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

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3432..3444)"
  check_deps
  setup_fixture
  test_3432_templates_single_copy
  test_3433_sh_writes_templates
  test_3434_twin_bytes
  test_3436_pipefail_large_stage
  test_3437_no_early_reader
  test_3439_crlf_and_rerun
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
