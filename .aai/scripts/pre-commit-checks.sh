#!/usr/bin/env bash
# Pre-commit quality gate checks for AAI projects
# Source: Inspired by pro-workflow quality gates (https://github.com/rohitg00/pro-workflow)
#
# Usage: Called from AAI skills before git commit, or as a standalone check.
#   bash .aai/scripts/pre-commit-checks.sh [--strict]
#
# Exit codes:
#   0 = all checks pass (warnings may exist)
#   1 = blocking errors found (commit should be prevented)
#
# --strict: treat warnings as errors

set -euo pipefail

# IN_REPO: is there a git directory (so an index) to judge? `--git-dir` succeeds in a work tree, inside
# `.git` and with GIT_DIR set, and fails only where there is no repository at all.
IN_REPO=0
git rev-parse --git-dir >/dev/null 2>&1 && IN_REPO=1
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || PROJECT_ROOT="$(pwd)"
STRICT="${1:-}"
ERRORS=0
WARNINGS=0

# Colors (if terminal supports them)
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

error() { echo -e "${RED}✗ $1${NC}"; ERRORS=$((ERRORS+1)); }
warn()  { echo -e "${YELLOW}⚠ $1${NC}"; WARNINGS=$((WARNINGS+1)); }
pass()  { echo -e "${GREEN}✓ $1${NC}"; }

# No check below uses a here-string, a here-document or a redirection on a builtin: when the descriptor table is
# nearly full, bash 3.2 cannot save a descriptor for such a redirection, applies it anyway and never restores it, so
# the rest of the report went to /dev/null. STATE is matched in the shell (`[[ =~ ]]`, per line as grep did), a line
# list is walked by parameter expansion, and a tool is looked up in a forked subshell, ( command -v node ).
PCC_RE_IMPL=$'phase:[^\n]*implementation'
PCC_RE_VALID=$'phase:[^\n]*validation'
PCC_RE_PASS='status: *pass'
PCC_RE_REQUIRED='required: *true'
PCC_RE_REVIEW_OK='status: *(pass|waived)'
# pcc_next_line: moves the first line of PCC_REST into PCC_LINE and drops it from PCC_REST.
pcc_next_line() {
  PCC_LINE="${PCC_REST%%$'\n'*}"
  case "$PCC_REST" in
    *$'\n'*) PCC_REST="${PCC_REST#*$'\n'}" ;;
    *) PCC_REST="" ;;
  esac
}

echo "─────────────────────────────────────"
echo "PRE-COMMIT QUALITY GATES"
echo "─────────────────────────────────────"
echo ""

# --- CHECK 1: TDD Evidence Complete ---
STATE_FILE="$PROJECT_ROOT/docs/ai/STATE.yaml"
if [ -f "$STATE_FILE" ]; then
  STATE_DATA=$(grep -v '^[[:space:]]*#' "$STATE_FILE" 2>/dev/null || true)
  # Check if there's an active work item in implementation phase
  # Simple heuristic: look for phase: implementation without corresponding validation pass
  if [[ "$STATE_DATA" =~ $PCC_RE_IMPL ]]; then
    LAST_VALIDATION_BLOCK=$(echo "$STATE_DATA" | awk '
      /^last_validation:/ { flag=1; next }
      /^[^[:space:]]/ { flag=0 }
      flag { print }
    ')
    if ! [[ "$LAST_VALIDATION_BLOCK" =~ $PCC_RE_PASS ]]; then
      warn "TDD cycle may be incomplete — active implementation without validation pass"
    else
      pass "TDD evidence appears complete"
    fi
  else
    pass "No active implementation phase"
  fi
else
  warn "STATE.yaml not found — skipping TDD check"
fi

# --- Staged content: one batched index read ---
# CHECKs 2-4 judge what the commit records, not the working tree. The staged
# list comes from ONE `git diff --cached --raw -z` (NUL-separated, so a name git
# would quote is checked under its real path), and the blobs of every record
# that has a stage-0 object come from ONE `git cat-file --batch`, asked by
# object id. Each response is parsed by its declared size and copied to a
# scratch file; any shortfall (truncated, dropped, extra or misaligned output,
# a missing object, a failed write) blocks the commit instead of letting the
# checks scan less than was staged. A deletion, an unmerged path and a gitlink
# have no stage-0 blob and are skipped. Where no git directory exists at all
# (IN_REPO=0, a plain directory) there is nothing to judge: no scratch directory
# is made and the checks report no staged files, as before. Wherever one exists
# (a work tree, a cwd inside `.git`, GIT_DIR set) every failure blocks.
# Descriptor safety: when the descriptor table is nearly full, bash 3.2 cannot
# save a descriptor for a builtin's redirection (a here-string read, `read <&3`,
# `: >`), prints "cannot duplicate fd", applies the redirection anyway and
# never restores stdin, which ended a read loop after its first record. So the
# parse uses no builtin redirection: the list and the batch file are opened
# once with `exec` on descriptors 4 and 3 and read with `read -u`, the record
# is split by parameter expansion, and a copy is created by `dd` (an external
# command redirects in its own process). As defence in depth the counts are
# checked by tools that are not this loop: the NUL terminators of the list file
# (`tr`, `wc -c`) must be twice the parsed records, one more
# `git diff --cached --name-only -z` must name as many paths as were parsed,
# and the number of copies must equal the number of requests. The two
# descriptors stay open until the process ends; the EXIT trap runs `rm -rf` with 3 and 4 closed in the
# child (an external command's redirection is made there, so it needs no save), which leaves it the free
# descriptor it needs to walk the scratch directory when the table is nearly full.
# A size is a decimal without a leading zero (bash reads `028` as a bad octal) and at most 15 digits;
# a `PCC_PARSED` sentinel, set to 0 here and checked by a separate command wherever a git directory exists,
# blocks any abort of either block below.
staged_read_fail() {
  error "Staged content could not be read completely: $1 — commit blocked"
  exit 1
}
STAGED=()
STAGED_SHA=()
STAGED_BLOB=()
STAGED_REQ=()
PCC_TMP=""
PCC_LIST=0
PCC_PARSED=0
if [ "$IN_REPO" -eq 1 ]; then
  PCC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/aai-pre-commit.XXXXXX" 2>/dev/null)" || staged_read_fail "cannot create a scratch directory"
  trap 'rm -rf "$PCC_TMP" 3<&- 4<&-' EXIT
  # The NUL terminators of both lists are counted (by tr and wc, not the parse) before the parse. Another process
  # can change the index between the two reads: when the list's count is even and is not twice the names' count,
  # both are read once more. The loop stops after the second read whatever it finds, and at once on an odd list
  # count (malformed, not a race); the post-parse checks below judge the last pair and still block a mismatch.
  pcc_try=1
  while :; do
    git -C "$PROJECT_ROOT" diff --cached --raw -z --no-renames --no-abbrev --no-color > "$PCC_TMP/list" 2>/dev/null || staged_read_fail "git diff --cached failed"
    git -C "$PROJECT_ROOT" diff --cached --name-only -z --no-renames --no-color > "$PCC_TMP/names" 2>/dev/null || staged_read_fail "git diff --cached failed"
    tr -cd '\000' < "$PCC_TMP/list" > "$PCC_TMP/list.nul" || staged_read_fail "malformed staged list"
    nul="$(wc -c < "$PCC_TMP/list.nul")" || staged_read_fail "malformed staged list"
    tr -cd '\000' < "$PCC_TMP/names" > "$PCC_TMP/names.nul" || staged_read_fail "staged list count mismatch"
    nnames="$(wc -c < "$PCC_TMP/names.nul")" || staged_read_fail "staged list count mismatch"
    if [ "$pcc_try" -ge 2 ] || [ $((nul % 2)) -eq 1 ] || [ "$nul" -eq $((nnames * 2)) ]; then break; fi
    pcc_try=$((pcc_try + 1))
  done
  PCC_LIST=1
fi
if [ "$PCC_LIST" -eq 1 ]; then
  meta=""
  nrec=0
  exec 4< "$PCC_TMP/list" || staged_read_fail "git diff --cached failed"
  while IFS= read -r -d '' -u 4 meta; do
    IFS= read -r -d '' -u 4 f || staged_read_fail "malformed staged list"
    case "$meta" in :*) ;; *) staged_read_fail "malformed staged list" ;; esac
    rest="${meta#:}"
    spaces="${rest//[!\ ]/}"
    [ "${#spaces}" -eq 4 ] || staged_read_fail "malformed staged list"
    rest="${rest#* }"
    mode="${rest%% *}"
    rest="${rest#* }"
    rest="${rest#* }"
    sha="${rest%% *}"
    st="${rest#* }"
    nrec=$((nrec + 1))
    STAGED+=("$f")
    case "$st" in
      D|U) STAGED_SHA+=("") ;;
      *)
        if [ "$mode" = 160000 ]; then
          STAGED_SHA+=("")
        else
          case "$sha" in ''|*[!0-9a-f]*) staged_read_fail "malformed staged list" ;; esac
          case "$sha" in *[!0]*) ;; *) staged_read_fail "malformed staged list" ;; esac
          [ "${#sha}" -eq 40 ] || [ "${#sha}" -eq 64 ] || staged_read_fail "malformed staged list"
          STAGED_SHA+=("$sha")
          STAGED_REQ+=("$sha")
        fi
        ;;
    esac
    meta=""
  done
  [ -z "$meta" ] || staged_read_fail "malformed staged list"
  [ "$nul" -eq $((nrec * 2)) ] || staged_read_fail "malformed staged list"
  [ "$nnames" -eq "$nrec" ] || staged_read_fail "staged list count mismatch"
  if [ "${#STAGED_REQ[@]}" -gt 0 ]; then
    # A pipeline whose pipe cannot be made ends bash itself (exit 129, no report), while a command substitution
    # that cannot make one comes back empty: one is tried first, so a table too full for the pipe blocks here.
    pcc_probe="$(echo ok)"
    [ "$pcc_probe" = ok ] || staged_read_fail "git cat-file --batch failed"
    printf '%s\n' "${STAGED_REQ[@]}" | git -C "$PROJECT_ROOT" cat-file --batch > "$PCC_TMP/batch" 2>/dev/null || staged_read_fail "git cat-file --batch failed"
    exec 3< "$PCC_TMP/batch" || staged_read_fail "git cat-file --batch failed"
    for idx in "${!STAGED_SHA[@]}"; do
      sha="${STAGED_SHA[$idx]}"
      STAGED_BLOB[$idx]=""
      [ -n "$sha" ] || continue
      file="${STAGED[$idx]}"
      IFS= read -r -u 3 hdr || staged_read_fail "response missing for $file"
      size=""
      case "$hdr" in "$sha blob "*) size="${hdr#"$sha blob "}" ;; esac
      case "$size" in ''|*[!0-9]*|0?*) staged_read_fail "unexpected response for $file" ;; esac
      [ "${#size}" -le 15 ] || staged_read_fail "unexpected response for $file"
      obj="$PCC_TMP/$idx"
      big=$((size / 1048576))
      rem=$((size % 1048576))
      if [ "$size" -eq 0 ]; then
        dd if=/dev/null of="$obj" 2>/dev/null || staged_read_fail "copy failed for $file"
      elif [ "$big" -gt 0 ]; then
        dd bs=1048576 count="$big" <&3 > "$obj" 2>/dev/null || staged_read_fail "copy failed for $file"
        if [ "$rem" -gt 0 ]; then
          dd bs="$rem" count=1 <&3 >> "$obj" 2>/dev/null || staged_read_fail "copy failed for $file"
        fi
      else
        dd bs="$rem" count=1 <&3 > "$obj" 2>/dev/null || staged_read_fail "copy failed for $file"
      fi
      got="$(wc -c < "$obj")" || staged_read_fail "size mismatch for $file"
      [ "$got" -eq "$size" ] || staged_read_fail "size mismatch for $file"
      sep="x"
      IFS= read -r -u 3 sep || staged_read_fail "separator missing after $file"
      [ -z "$sep" ] || staged_read_fail "separator missing after $file"
      STAGED_BLOB[$idx]="$obj"
    done
    extra=""
    if IFS= read -r -u 3 extra || [ -n "$extra" ]; then staged_read_fail "unrequested trailing output"; fi
  fi
  ncopy=0
  if [ "${#STAGED_BLOB[@]}" -gt 0 ]; then
    for obj in "${STAGED_BLOB[@]}"; do
      [ -z "$obj" ] || ncopy=$((ncopy + 1))
    done
  fi
  [ "$ncopy" -eq "${#STAGED_REQ[@]}" ] || staged_read_fail "copy count mismatch"
  PCC_PARSED=1
fi
# A shell that aborts an arithmetic or expansion error drops the whole `if` block it is in and goes on with rc 0, count
# cross-checks included; this separate command makes any such abort block the commit. It is keyed on IN_REPO, not
# PCC_LIST, so an abort before the list flag is set blocks too, and PCC_PARSED is set above, never inherited.
[ "$IN_REPO" -eq 0 ] || [ "$PCC_PARSED" -eq 1 ] || staged_read_fail "parse did not complete"

# --- CHECK 2: Secrets Detection ---
# A finding is one line of a staged blob that looks like a credential. What counts is the VALUE, judged by shape (a
# value with a blank, a word, a reference, a placeholder, a URL or a relative path is not a credential); a file name
# only picks the rules (a name hit also gets the unquoted-assignment and URL-credential rules) and blocks by itself
# only for a key file or a blob holding a NUL byte. A project-owned allowlist read from the index exempts reviewed
# false positives; every finding prints its line number and a fingerprint, never the value. The two awk programs
# are plain POSIX awk (no interval expression, no gawk extension) and run under LC_ALL=C; they contain no apostrophe
# because they sit in shell single quotes. Per file: a grep prefilter (every rule needs one of its words), then awk.
SECRETS_FOUND=0
PCC_VALUE_MINLEN=8
PCC_ALLOWLIST="docs/ai/secrets-allowlist.txt"
PCC_PRE='password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|A[KS]IA|g[h][pousr]_|github[_]pat_|-----BEGIN'
PCC_AWK='
function has_space(v) {
  return (index(v, " ") > 0 || index(v, "\t") > 0)
}
function is_letter(c) {
  return ((c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || (c > "~" && c != "\177"))
}
function is_wordlike(v) {
  wl_n = length(v)
  if (wl_n > 0 && index(".!?:", substr(v, wl_n, 1)) > 0) wl_n--
  wl_st = 0
  for (wl_i = 1; wl_i <= wl_n; wl_i++) {
    wl_c = substr(v, wl_i, 1)
    if (is_letter(wl_c)) wl_st = 1
    else if ((wl_c == "-" || wl_c == "\047" || wl_c == ".") && wl_st == 1) wl_st = 0
    else return 0
  }
  return (wl_st == 1)
}
function is_reference(v) {
  if (substr(v, 1, 1) == "$" || index(v, "${") > 0 || substr(v, 1, 2) == "{{") return 1
  if (length(v) > 1 && substr(v, 1, 1) == "%" && substr(v, length(v), 1) == "%") return 1
  if (index(v, "process.env.") == 1 || index(v, "import.meta.env.") == 1 || index(v, "os.environ") == 1) return 1
  if (index(v, "os.getenv(") == 1 || index(v, "System.getenv(") == 1 || index(v, "ENV[") == 1 || index(v, "env(") == 1) return 1
  return 0
}
function is_placeholder(v) {
  pl_v = tolower(v)
  if (substr(pl_v, 1, 1) == "<" && index(pl_v, ">") > 0) return 1
  pl_same = 1
  for (pl_i = 2; pl_i <= length(pl_v); pl_i++) {
    if (substr(pl_v, pl_i, 1) != substr(pl_v, 1, 1)) { pl_same = 0; break }
  }
  if (pl_same == 1) return 1
  if (index(pl_v, "changeme") > 0 || index(pl_v, "change_me") > 0 || index(pl_v, "change-me") > 0) return 1
  if (index(pl_v, "replaceme") > 0 || index(pl_v, "replace_me") > 0 || index(pl_v, "replace-me") > 0) return 1
  if (index(pl_v, "placeholder") > 0 || index(pl_v, "example") > 0 || index(pl_v, "dummy") > 0) return 1
  if (index(pl_v, "redacted") > 0 || index(pl_v, "xxxx") > 0) return 1
  if (index(pl_v, "your_") == 1 || index(pl_v, "your-") == 1) return 1
  if (length(pl_v) >= 5 && (substr(pl_v, length(pl_v) - 4) == "_here" || substr(pl_v, length(pl_v) - 4) == "-here")) return 1
  return 0
}
function is_url(v) {
  return (v ~ "^[A-Za-z][A-Za-z0-9+.-]*://")
}
function kwkey(k) {
  return (tolower(k) ~ /password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key/ || ("_" tolower(k)) ~ /[^a-z]pass(phrase)?[^a-z]/)
}
function is_label(v) {
  lb_c = substr(v, 1, 1)
  if (length(v) > 20 || !((lb_c >= "A" && lb_c <= "Z") || (lb_c > "~" && lb_c != "\177"))) return 0
  return (substr(v, 2) !~ /[A-Z]/)
}
function cred(v, kw) {
  if (length(v) < minlen) return 0
  if (has_space(v)) return 0
  if (is_reference(v)) return 0
  if (is_placeholder(v)) return 0
  if (is_wordlike(v) && (kw != 1 || is_label(v))) return 0
  if (is_url(v)) return 0
  if (substr(v, 1, 2) == "./" || substr(v, 1, 3) == "../" || substr(v, 1, 2) == "~/") return 0
  return 1
}
function trim(s) {
  sub(/^[ \t]+/, "", s)
  sub(/[ \t]+$/, "", s)
  return s
}
function emit(n, text,   fn) {
  if (n == last) return
  last = n
  print n "\n"
  if (fpon == "1") {
    fn = fpb "." n
    print fnm "\n" trim(text) > fn
    close(fn)
    print fn "\n" >> fpl
  }
}
function r1(s,   lc, off, e, q, v, p) {
  lc = tolower(s)
  off = 0
  while (match(substr(lc, off + 1), R1RE)) {
    e = off + RSTART + RLENGTH
    q = substr(s, e - 1, 1)
    v = substr(s, e)
    p = index(v, q)
    if (p > 0) v = substr(v, 1, p - 1)
    if (substr(v, 1, 8) !~ /["\047]/ && cred(v, 1)) return 1
    off = e - 1
  }
  return 0
}
function r2(s,   lc, off, e, c, v, p) {
  lc = tolower(s)
  off = 0
  while (match(substr(lc, off + 1), R2RE)) {
    e = off + RSTART + RLENGTH
    v = substr(s, e)
    sub(/^[ \t]+/, "", v)
    c = substr(v, 1, 1)
    if (c == "\"" || c == "\047") {
      v = substr(v, 2)
      p = index(v, c)
      if (p > 0) v = substr(v, 1, p - 1)
    } else {
      p = match(v, /[ \t]/)
      if (p > 0) v = substr(v, 1, p - 1)
    }
    if (cred(v, 1)) return 1
    off = e - 1
  }
  return 0
}
function r3(s,   off, p, a, k, at, u, c) {
  off = 0
  while ((p = index(substr(s, off + 1), "://")) > 0) {
    p = off + p
    off = p + 2
    if (substr(s, 1, p - 1) !~ /[A-Za-z][A-Za-z0-9+.-]*$/) continue
    a = substr(s, p + 3)
    k = match(a, "[/?# \t\"\047]")
    if (k > 0) a = substr(a, 1, k - 1)
    at = 0
    for (k = 1; k <= length(a); k++) if (substr(a, k, 1) == "@") at = k
    if (at == 0) continue
    u = substr(a, 1, at - 1)
    c = index(u, ":")
    if (c > 0 && cred(substr(u, c + 1), 1)) return 1
  }
  return 0
}
function r5(s,   v, c, p, kk) {
  if (!match(s, /^[ \t]*(export[ \t]+)?[A-Za-z_][A-Za-z0-9_.-]*[ \t]*=/)) return 0
  kk = kwkey(substr(s, 1, RLENGTH))
  v = substr(s, RLENGTH + 1)
  sub(/^[ \t]+/, "", v)
  c = substr(v, 1, 1)
  if (c == "\"" || c == "\047") {
    v = substr(v, 2)
    p = index(v, c)
    if (p > 0) v = substr(v, 1, p - 1)
  } else {
    p = match(v, /[ \t]/)
    if (p > 0) v = substr(v, 1, p - 1)
  }
  return cred(v, kk)
}
function r7(s) {
  if (!match(s, /^[ \t]*export[ \t]/)) return 0
  return r5(s)
}
function aws(s,   p, b, t) {
  p = 1
  while (p <= length(s)) {
    if (!match(substr(s, p), /(AKIA|ASIA)[A-Z0-9]+/)) return 0
    b = p + RSTART - 1
    t = substr(s, b, RLENGTH)
    if (length(t) == 20 && (b == 1 || substr(s, b - 1, 1) !~ /[A-Z0-9]/) && !is_placeholder(t)) return 1
    p = b + 1
  }
  return 0
}
function ghc(s,   p, b, t) {
  p = 1
  while (p <= length(s)) {
    if (!match(substr(s, p), /gh[pousr]_[A-Za-z0-9]+/)) return 0
    b = p + RSTART - 1
    t = substr(s, b, RLENGTH)
    if (length(t) >= 40 && !is_placeholder(t)) return 1
    p = b + 4
  }
  return 0
}
function ghf(s,   p, b, t, u, i) {
  p = 1
  while (p <= length(s)) {
    if (!match(substr(s, p), /github_pat_[A-Za-z0-9]+_[A-Za-z0-9]+/)) return 0
    b = p + RSTART - 1
    t = substr(s, b, RLENGTH)
    u = substr(t, 12)
    i = index(u, "_")
    if (i - 1 >= 22 && length(u) - i >= 59 && !is_placeholder(t)) return 1
    p = b + 11
  }
  return 0
}
function pkpos(t) {
  return index(t, "PRIVATE KEY")
}
function pkh(s,   t, k) {
  t = trim(s)
  if (index(t, "-----BEGIN ") != 1) return 0
  k = pkpos(t)
  if (k == 0) return 0
  if (substr(t, 12, k - 12) !~ "^([A-Za-z0-9]+ )*$") return 0
  return (substr(t, k + 11) == "-----" || substr(t, k + 11) == " BLOCK-----")
}
function pkscan(s,   off, a, t, k, r, c, again) {
  off = 0
  while ((a = index(substr(s, off + 1), "-----BEGIN ")) > 0) {
    a = off + a
    off = a + 10
    t = substr(s, a + 11)
    k = pkpos(t)
    if (k == 0) continue
    if (substr(t, 1, k - 1) !~ "^([A-Za-z0-9]+ )*$") continue
    r = substr(t, k + 11)
    if (substr(r, 1, 5) == "-----") r = substr(r, 6)
    else if (substr(r, 1, 12) == " BLOCK-----") r = substr(r, 13)
    else continue
    again = 1
    while (again == 1) {
      again = 0
      sub(/^[ \t"\047,+;)]+/, "", r)
      if (substr(r, 1, 1) == "\\") {
        sub(/^\\+/, "", r)
        c = substr(r, 1, 1)
        if (c == "n" || c == "r") r = substr(r, 2)
        again = 1
      }
    }
    if (r == "") return 2
    if (index(r, "Proc-Type:") == 1) return 1
    if (match(r, /^[A-Za-z0-9+\/=]+/) && RLENGTH >= 40) return 1
  }
  return 0
}
function r6(s,   off, b, e, sep, pv, nx, v, c, p, kk) {
  off = 0
  while (match(substr(s, off + 1), /[A-Za-z_][A-Za-z0-9_.-]*["\047]?[ \t]*[:=]/)) {
    b = off + RSTART
    e = off + RSTART + RLENGTH
    off = e - 1
    sep = substr(s, e - 1, 1)
    pv = ""
    if (b > 1) pv = substr(s, b - 1, 1)
    if ((pv == "\"" || pv == "\047") && b > 2) pv = substr(s, b - 2, 1)
    if (pv != "" && index(" \t{,;([#", pv) == 0) continue
    nx = substr(s, e, 1)
    if (sep == ":") {
      if (nx != "" && nx != " " && nx != "\t" && nx != "\"" && nx != "\047") continue
    } else if (nx == "=") continue
    kk = kwkey(substr(s, b, e - b))
    v = substr(s, e)
    sub(/^[ \t]+/, "", v)
    c = substr(v, 1, 1)
    if (c == "\"" || c == "\047") {
      v = substr(v, 2)
      p = index(v, c)
      if (p > 0) v = substr(v, 1, p - 1)
    } else {
      p = match(v, /[ \t]/)
      if (p > 0) v = substr(v, 1, p - 1)
    }
    if (cred(v, kk)) return 1
  }
  return 0
}
BEGIN {
  ORS = ""
  fnm = ENVIRON["PCC_FILE"]
  fpb = ENVIRON["PCC_FPBASE"]
  fpl = ENVIRON["PCC_FPLIST"]
  fpon = ENVIRON["PCC_FPON"]
  R1RE = "(api[_-]?key|api[_-]?secret|password|passwd|secret[_-]?key|access[_-]?token|private[_-]?key)[ \t]*[:=][ \t]*[\"\047]"
  R2RE = "(password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)[A-Za-z0-9_.-]*[\"\047]?[ \t]*[:=]"
}
{
  sub(/\r$/, "")
  if (pend == 1) {
    pb = trim($0)
    if (pb != "") {
      pend = 0
      if (pl == 1) sub(/^[ \t"\047,+]+/, "", pb)
      if (index(pb, "Proc-Type:") == 1) emit(pn, pt)
      else if (pl == 1 && match(pb, /^[A-Za-z0-9+\/=]+/) && RLENGTH >= 40) emit(pn, pt)
      else if (pl == 0 && length(pb) >= 40 && pb ~ "^[A-Za-z0-9+/=]+$") emit(pn, pt)
    }
  }
  if (pkh($0)) { pend = 1; pl = 0; pn = NR; pt = $0; next }
  pk = pkscan($0)
  if (pk == 1) { emit(NR, $0); next }
  if (pk == 2) { pend = 1; pl = 1; pn = NR; pt = $0 }
  if (aws($0) || ghc($0) || ghf($0)) { emit(NR, $0); next }
  if (r1($0) || (nh == 1 && (r2($0) || r3($0))) || (ak == 2 && r6($0)) || (ak == 1 && r7($0))) emit(NR, $0)
}
END { print "done" }
'
PCC_AWK_AL='
BEGIN { ORS = "" }
{
  l = $0
  if (NR == 1) sub(/^\357\273\277/, "", l)
  sub(/\r$/, "", l)
  sub(/^[ \t]+/, "", l)
  sub(/[ \t]+$/, "", l)
  if (l == "" || substr(l, 1, 1) == "#") next
  if (index(l, "path ") == 1) {
    g = substr(l, 6)
    sub(/^[ \t]+/, "", g)
    if (g != "") { print "P " NR " " g "\n"; next }
  } else if (index(l, "fingerprint ") == 1) {
    h = substr(l, 13)
    sub(/^[ \t]+/, "", h)
    if ((length(h) == 40 || length(h) == 64) && h ~ /^[0-9a-f]+$/) { print "F " h "\n"; next }
  }
  print "B " NR "\n"
}
END { print "done" }
'
PCC_ALLOWED=0
PCC_APATHS=""
PCC_AFPS=""
PCC_HASHES=""
pcc_nfind=0
PCC_FL=()
PCC_KF=()
PCC_NL=$'\n'

if [ "${#STAGED[@]}" -gt 0 ]; then
  pcc_judged=0
  for idx in "${!STAGED[@]}"; do
    [ -z "${STAGED_BLOB[$idx]:-}" ] || pcc_judged=$((pcc_judged + 1))
  done

  # The allowlist in effect is the index's: the staged blob when the commit stages it, else the entry the index holds.
  if [ "$pcc_judged" -gt 0 ]; then
    pcc_ablob=""
    pcc_astaged=0
    for idx in "${!STAGED[@]}"; do
      if [ "${STAGED[$idx]}" = "$PCC_ALLOWLIST" ]; then
        pcc_astaged=1
        pcc_ablob="${STAGED_BLOB[$idx]:-}"
      fi
    done
    if [ "$pcc_astaged" -eq 0 ]; then
      pcc_aid="$(git -C "$PROJECT_ROOT" rev-parse -q --verify ":$PCC_ALLOWLIST" 2>/dev/null)" || pcc_aid=""
      if [ -n "$pcc_aid" ]; then
        pcc_ablob="$PCC_TMP/allow"
        git -C "$PROJECT_ROOT" cat-file blob "$pcc_aid" > "$pcc_ablob" 2>/dev/null || staged_read_fail "secrets allowlist"
      fi
    fi
    if [ -n "$pcc_ablob" ]; then
      [ -f "$pcc_ablob" ] && [ -r "$pcc_ablob" ] || staged_read_fail "secrets allowlist"
      pcc_ap="$(LC_ALL=C awk "$PCC_AWK_AL" < "$pcc_ablob" 2>/dev/null || true)"
      case "$pcc_ap" in done|*$'\n'done) ;; *) staged_read_fail "secrets allowlist" ;; esac
      PCC_REST="$pcc_ap"
      while [ -n "$PCC_REST" ]; do
        pcc_next_line
        case "$PCC_LINE" in
          "P "*)
            pcc_g="${PCC_LINE#P }"
            pcc_n="${pcc_g%% *}"
            pcc_g="${pcc_g#* }"
            pcc_catch_all=0
            # A glob with no literal character once its wildcards, bracket expressions and slashes are removed
            # (a negated class like [!z]* included) is judged as the bare wildcard.
            pcc_lit=""
            pcc_s="$pcc_g"
            while [ -n "$pcc_s" ]; do
              pcc_c="${pcc_s%"${pcc_s#?}"}"
              pcc_s="${pcc_s#?}"
              if [ "$pcc_c" = "[" ]; then
                # A bracket expression: a leading ! or ^ negates, a leading ] is literal, [:class:] holds a ].
                pcc_t="$pcc_s"
                case "$pcc_t" in '!'*|'^'*) pcc_t="${pcc_t#?}" ;; esac
                case "$pcc_t" in ']'*) pcc_t="${pcc_t#?}" ;; esac
                pcc_closed=0
                while [ -n "$pcc_t" ]; do
                  case "$pcc_t" in
                    '[:'*)
                      pcc_aft="${pcc_t#??}"
                      case "$pcc_aft" in
                        *:\]*) pcc_t="${pcc_aft#*:\]}"; continue ;;
                      esac
                      ;;
                    ']'*) pcc_t="${pcc_t#?}"; pcc_closed=1; break ;;
                  esac
                  pcc_t="${pcc_t#?}"
                done
                if [ "$pcc_closed" -eq 1 ]; then pcc_s="$pcc_t"; continue; fi
              fi
              pcc_lit="$pcc_lit$pcc_c"
            done
            pcc_gm="$pcc_g"
            pcc_lit="${pcc_lit//[*?\/]/}"
            [ -n "$pcc_lit" ] || pcc_gm='*'
            for pcc_probe in zz-aai-allowlist-probe zz/aai/allowlist/probe.zz; do
              case "$pcc_probe" in $pcc_gm) pcc_catch_all=1 ;; esac
            done
            if [ "$pcc_catch_all" -eq 1 ]; then
              error "Secrets allowlist line $pcc_n: catch-all path glob '$pcc_g' rejected — commit blocked"
              SECRETS_FOUND=1
            else
              PCC_APATHS="$PCC_APATHS$pcc_g$PCC_NL"
            fi
            ;;
          "F "*) PCC_AFPS="$PCC_AFPS${PCC_LINE#F }$PCC_NL" ;;
          "B "*)
            error "Secrets allowlist line ${PCC_LINE#B }: unrecognised entry — commit blocked"
            SECRETS_FOUND=1
            ;;
        esac
      done
    fi
  fi

  # Phase 1: classify and scan each staged blob; a finding that needs a fingerprint is written to a scratch file.
  for idx in "${!STAGED[@]}"; do
    file="${STAGED[$idx]}"
    blob="${STAGED_BLOB[$idx]:-}"
    [ -n "$blob" ] || continue

    # A copy that cannot be opened must not read as zero hits: grep -c always prints a number, so anything else is
    # a failed scan.
    [ -f "$blob" ] && [ -r "$blob" ] || staged_read_fail "copy failed for $file"

    # Name hit. AAI evidence folders are judged by content alone, except a dotenv file.
    name_check=1
    case "$file" in
      docs/ai/reports/*|docs/ai/tdd/*|docs/ai/validation/*|docs/ai/reviews/*) name_check=0 ;;
    esac
    case "${file##*/}" in
      .env|.env.*|*.env) name_check=1 ;;
    esac
    pcc_namehit=0
    pcc_keyfile=0
    pcc_anykey=0
    pcc_anydata=0
    if [ "$name_check" -eq 1 ] && { [[ "$file" == *.env* ]] || [[ "$file" == *credentials* ]] || [[ "$file" == *secret* ]]; }; then
      pcc_namehit=1
      # R6: a name hit that is not a dotenv template judges a credential-shaped value under any key; in a data or
      # config file (dotenv, yaml, json, toml, ini, txt, no extension) every pair, in any other file only export KEY=value.
      case "${file##*/}" in
        .env.example|.env.sample|.env.template|.env.dist|.env.defaults) ;;
        *) pcc_anykey=1 ;;
      esac
      case "${file##*/}" in
        .env|.env.*|*.env|*.yaml|*.yml|*.json|*.toml|*.ini|*.cfg|*.conf|*.properties|*.tfvars|*.txt|*.xml|*.plist) pcc_anydata=1 ;;
        ?*.*) ;;
        *) pcc_anydata=1 ;;
      esac
    fi
    if [ "$pcc_namehit" -eq 1 ]; then
      pcc_kext=0
      case "${file##*/}" in
        *.key|*.pem|*.p12|*.pfx|*.jks|*.keystore) pcc_kext=1 ;;
      esac
      LC_ALL=C tr -cd '\000' < "$blob" > "$PCC_TMP/nulbytes" || staged_read_fail "copy failed for $file"
      pcc_nul="$(wc -c < "$PCC_TMP/nulbytes")" || staged_read_fail "copy failed for $file"
      case "$pcc_nul" in ''|*[!0-9\ ]*) staged_read_fail "copy failed for $file" ;; esac
      if [ "$pcc_kext" -eq 1 ] || [ "$pcc_nul" -gt 0 ]; then
        pcc_keyfile=1
      fi
    fi

    pcc_pathok=0
    PCC_REST="$PCC_APATHS"
    while [ -n "$PCC_REST" ]; do
      pcc_next_line
      case "$file" in
        $PCC_LINE) pcc_pathok=1 ;;
      esac
    done

    if [ "$pcc_keyfile" -eq 1 ]; then
      if [ "$pcc_pathok" -eq 1 ]; then
        PCC_ALLOWED=$((PCC_ALLOWED + 1))
      else
        PCC_KF[$idx]=1
      fi
      continue
    fi

    pcc_pre="$PCC_PRE"
    [ "$pcc_namehit" -eq 0 ] || pcc_pre="$PCC_PRE|://"
    [ "$pcc_anykey" -eq 0 ] || pcc_pre="$pcc_pre|:|="
    hits=$(LC_ALL=C grep -cEi "$pcc_pre" < "$blob" || true)
    case "$hits" in ''|*[!0-9]*) staged_read_fail "copy failed for $file" ;; esac
    [ "$hits" -gt 0 ] || continue
    # A blob with a NUL byte reaches awk as a copy with each NUL turned into a newline: BWK awk cuts a record at its
    # first NUL, mawk and gawk do not, and the old grep matched around it. A name-hit blob with a NUL was blocked above.
    pcc_src="$blob"
    if [ "$pcc_namehit" -eq 0 ]; then
      LC_ALL=C tr -cd '\000' < "$blob" > "$PCC_TMP/nulbytes" || staged_read_fail "copy failed for $file"
      pcc_nul="$(wc -c < "$PCC_TMP/nulbytes")" || staged_read_fail "copy failed for $file"
      case "$pcc_nul" in ''|*[!0-9\ ]*) staged_read_fail "copy failed for $file" ;; esac
      if [ "$pcc_nul" -gt 0 ]; then
        pcc_src="$PCC_TMP/nulfree.$idx"
        LC_ALL=C tr '\000' '\n' < "$blob" > "$pcc_src" || staged_read_fail "copy failed for $file"
      fi
    fi
    pcc_fpon=1
    [ "$pcc_pathok" -eq 0 ] || pcc_fpon=0
    pcc_out="$(PCC_FILE="$file" PCC_FPBASE="$PCC_TMP/fp.$idx" PCC_FPLIST="$PCC_TMP/fplist" PCC_FPON="$pcc_fpon" LC_ALL=C awk -v nh="$pcc_namehit" -v ak="$((pcc_anykey * (1 + pcc_anydata)))" -v minlen="$PCC_VALUE_MINLEN" "$PCC_AWK" < "$pcc_src" 2>/dev/null || true)"
    case "$pcc_out" in done|*$'\n'done) ;; *) staged_read_fail "copy failed for $file" ;; esac
    pcc_fl="${pcc_out%done}"
    pcc_cnt="${pcc_fl//[!$PCC_NL]/}"
    [ "${#pcc_cnt}" -gt 0 ] || continue
    if [ "$pcc_pathok" -eq 1 ]; then
      PCC_ALLOWED=$((PCC_ALLOWED + ${#pcc_cnt}))
    else
      PCC_FL[$idx]="$pcc_fl"
      pcc_nfind=$((pcc_nfind + ${#pcc_cnt}))
    fi
  done

  # Phase 2: every fingerprint of the run comes from one git hash-object, made only when a finding needs one.
  if [ "$pcc_nfind" -gt 0 ]; then
    git -C "$PROJECT_ROOT" hash-object --no-filters --stdin-paths < "$PCC_TMP/fplist" > "$PCC_TMP/fphash" 2>/dev/null || staged_read_fail "fingerprints"
    PCC_HASHES="$(cat "$PCC_TMP/fphash")" || staged_read_fail "fingerprints"
    pcc_cnt="${PCC_HASHES//[!$PCC_NL]/}"
    [ "$((${#pcc_cnt} + 1))" -eq "$pcc_nfind" ] || staged_read_fail "fingerprints"
  fi

  # Phase 3: report in staged order.
  for idx in "${!STAGED[@]}"; do
    file="${STAGED[$idx]}"
    if [ "${PCC_KF[$idx]:-0}" -eq 1 ]; then
      error "Sensitive file staged: $file"
      SECRETS_FOUND=1
    fi
    pcc_fl="${PCC_FL[$idx]:-}"
    [ -n "$pcc_fl" ] || continue
    pcc_bad=0
    pcc_det=""
    PCC_REST="$pcc_fl"
    while [ -n "$PCC_REST" ]; do
      pcc_next_line
      pcc_n="$PCC_LINE"
      pcc_h="${PCC_HASHES%%$PCC_NL*}"
      case "$PCC_HASHES" in
        *$PCC_NL*) PCC_HASHES="${PCC_HASHES#*$PCC_NL}" ;;
        *) PCC_HASHES="" ;;
      esac
      case "$PCC_NL$PCC_AFPS" in
        *"$PCC_NL$pcc_h$PCC_NL"*) PCC_ALLOWED=$((PCC_ALLOWED + 1)) ;;
        *)
          pcc_bad=$((pcc_bad + 1))
          if [ "$pcc_bad" -le 3 ]; then pcc_det="$pcc_det    line $pcc_n, fingerprint $pcc_h$PCC_NL"; fi
          ;;
      esac
    done
    if [ "$pcc_bad" -gt 0 ]; then
      error "Potential secret detected in $file"
      printf '%s' "$pcc_det"
      if [ "$pcc_bad" -gt 3 ]; then echo "    ... and $((pcc_bad - 3)) more"; fi
      SECRETS_FOUND=1
    fi
  done

  [ "$PCC_ALLOWED" -eq 0 ] || pass "Secrets allowlist: $PCC_ALLOWED finding(s) allowed by $PCC_ALLOWLIST"
  if [ "$SECRETS_FOUND" -eq 0 ]; then
    pass "No secrets detected in staged files"
  fi
else
  pass "No staged files to check"
fi

# --- CHECK 3: Debug Statements ---
DEBUG_FOUND=0
if [ "${#STAGED[@]}" -gt 0 ]; then
  for idx in "${!STAGED[@]}"; do
    file="${STAGED[$idx]}"
    blob="${STAGED_BLOB[$idx]:-}"
    [ -n "$blob" ] || continue

    # Skip non-source files
    case "$file" in
      *.md|*.yaml|*.yml|*.json|*.jsonl|*.txt|*.sh|*.ps1|*.gitignore) continue ;;
    esac

    # Check for debug statements
    [ -f "$blob" ] && [ -r "$blob" ] || staged_read_fail "copy failed for $file"
    matches=$(grep -n 'console\.log\|debugger\|pdb\.set_trace\|binding\.pry\|var_dump' < "$blob" || true)
    if [ -n "$matches" ]; then
      warn "Debug statements in $file:"
      PCC_REST="$matches"
      PCC_SHOWN=0
      while [ -n "$PCC_REST" ] && [ "$PCC_SHOWN" -lt 3 ]; do
        pcc_next_line
        echo "    $PCC_LINE"
        PCC_SHOWN=$((PCC_SHOWN + 1))
      done
      DEBUG_FOUND=1
    fi
  done

  if [ "$DEBUG_FOUND" -eq 0 ]; then
    pass "No debug statements found"
  fi
fi

# --- CHECK 4: TODO/FIXME markers ---
TODO_COUNT=0
if [ "${#STAGED[@]}" -gt 0 ]; then
  for idx in "${!STAGED[@]}"; do
    file="${STAGED[$idx]}"
    blob="${STAGED_BLOB[$idx]:-}"
    [ -n "$blob" ] || continue
    # Keep this skip list a subset of CHECK 3's: CHECK 4 re-tests every copy CHECK 3 reads, so a copy that vanishes
    # while CHECK 3 reads it (and reads as no matches there) blocks here.
    case "$file" in
      *.md|*.yaml|*.yml|*.txt|*.sh|*.ps1) continue ;;
    esac

    [ -f "$blob" ] && [ -r "$blob" ] || staged_read_fail "copy failed for $file"
    count=$(grep -c 'TODO\|FIXME\|HACK\|XXX' < "$blob" || true)
    case "$count" in ''|*[!0-9]*) staged_read_fail "copy failed for $file" ;; esac
    if [ "$count" -gt 0 ]; then
      TODO_COUNT=$((TODO_COUNT + count))
    fi
  done

  if [ "$TODO_COUNT" -gt 0 ]; then
    warn "$TODO_COUNT TODO/FIXME markers in staged files"
  else
    pass "No TODO/FIXME markers"
  fi
fi

# --- CHECK 5: Validation Report ---
if [ -f "$STATE_FILE" ]; then
  STATE_DATA=$(grep -v '^[[:space:]]*#' "$STATE_FILE" 2>/dev/null || true)
  LAST_VALIDATION_BLOCK=$(echo "$STATE_DATA" | awk '
    /^last_validation:/ { flag=1; next }
    /^[^[:space:]]/ { flag=0 }
    flag { print }
  ')
  if [[ "$STATE_DATA" =~ $PCC_RE_VALID ]] ||
     [[ "$LAST_VALIDATION_BLOCK" =~ $PCC_RE_PASS ]]; then
    REPORTS_DIR="$PROJECT_ROOT/docs/ai/reports"
    if [ -d "$REPORTS_DIR" ] && {
      ls "$REPORTS_DIR"/validation-*.md 1>/dev/null 2>&1 ||
      ls "$REPORTS_DIR"/VALIDATION_REPORT_*.md 1>/dev/null 2>&1 ||
      [ -f "$REPORTS_DIR/LATEST.md" ]
    }; then
      pass "Validation report exists"
    else
      warn "No validation report found — consider running /aai-validate-report"
    fi
  fi
fi

# --- CHECK 6: Code Review Gate ---
if [ -f "$STATE_FILE" ]; then
  CODE_REVIEW_BLOCK=$(awk '
    /^code_review:/ { flag=1; next }
    /^[^[:space:]]/ { flag=0 }
    flag { print }
  ' "$STATE_FILE")
  if [[ "$CODE_REVIEW_BLOCK" =~ $PCC_RE_REQUIRED ]]; then
    if [[ "$CODE_REVIEW_BLOCK" =~ $PCC_RE_REVIEW_OK ]]; then
      pass "Code review gate satisfied"
    else
      warn "Code review required but not pass/waived"
    fi
  fi
fi

# --- CHECK 7: PowerShell parse gate ---
# A staged .ps1 with a parse error breaks /aai-update et al. for Windows users
# silently (the failure only surfaces when they run it). If pwsh is available,
# parse-check every staged .ps1 so a broken script can't land. No-op when pwsh is
# absent (most macOS/Linux dev boxes) — the full gate runs in tests/skills/.
STAGED_PS1=$(git -C "$PROJECT_ROOT" diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.ps1$' || true)
if [ -n "$STAGED_PS1" ]; then
  if ( command -v pwsh ) >/dev/null 2>&1; then
    PS1_BAD=0
    PCC_REST="$STAGED_PS1"
    while [ -n "$PCC_REST" ]; do
      pcc_next_line
      f="$PCC_LINE"
      [ -z "$f" ] && continue
      [ -f "$PROJECT_ROOT/$f" ] || continue
      if ! pwsh -NoProfile -Command "\$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile('$PROJECT_ROOT/$f', [ref]\$null, [ref]\$e) | Out-Null; if (\$e -and \$e.Count) { exit 1 } else { exit 0 }" >/dev/null 2>&1; then
        error "PowerShell parse error in staged $f"
        PS1_BAD=$((PS1_BAD+1))
      fi
    done
    [ "$PS1_BAD" -eq 0 ] && pass "Staged .ps1 scripts parse cleanly"
  else
    warn "Staged .ps1 changes not parse-checked (pwsh not installed)"
  fi
fi

# --- CHECK 8: Doc-numbering guards (SPEC-0015 / RFC-0007) ---
# Two predicates, report-only by DEFAULT (mirroring close_gate / body_lint),
# flippable to enforce via docs/ai/docs-audit.yaml `doc_number_guard: enforce`:
#   - no-DRAFT-at-merge: any docs/*/*-DRAFT-*.md, or a governed doc still carrying
#     `number: null`, present at the merge/commit point.
#   - duplicate-number: two governed docs of the same type resolving to the same
#     TYPE-000N (same type + number, or identical numeric filename prefixes).
# A clean, fully-numbered tree passes both with exit 0. The allocator engine
# (`--guard`) is the single source of truth for both predicates.
# NOTE (CHANGE-0009 D8): this grep is a deliberate THIN mirror of the guard
# dial; the CANONICAL reader of docs-audit.yaml is .aai/scripts/lib/guard-config.mjs
# (a conformance test asserts this pattern and the reader agree on fixtures).
DOC_NUMBER_GUARD="$PROJECT_ROOT/.aai/scripts/allocate-doc-number.mjs"
if [ -f "$DOC_NUMBER_GUARD" ] && ( command -v node ) >/dev/null 2>&1; then
  DN_MODE="report-only"
  if grep -Eq $'^(\xef\xbb\xbf)?doc_number_guard:[[:space:]]*enforce([[:space:]]|$)' \
       "$PROJECT_ROOT/docs/ai/docs-audit.yaml" 2>/dev/null; then
    DN_MODE="enforce"
  fi
  # Merge-point-aware enforce (shipped-guards-have-no-downstream-trigger D2):
  # the AAI flow COMMITS drafts on branches by design (numbering is assigned
  # at merge by the allocator), so `no-DRAFT-at-merge` has a legitimate
  # false positive at commit time on any non-default branch — measured, an
  # enforce dial refused this repository's own intake commits once the
  # pre-commit hook started reaching this script. `enforce` therefore bites
  # on the DEFAULT branch only (R1: refs/remotes/origin/HEAD, else main) and
  # downgrades to report-only elsewhere with ONE line saying so.
  DN_DEFAULT="$(git -C "$PROJECT_ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  DN_DEFAULT="${DN_DEFAULT#origin/}"
  if [ -z "$DN_DEFAULT" ]; then
    DN_DEFAULT="main"
    echo "    NOTE: default branch assumed main (refs/remotes/origin/HEAD unset)"
  fi
  DN_BRANCH="$(git -C "$PROJECT_ROOT" symbolic-ref -q --short HEAD 2>/dev/null || true)"
  [ -n "$DN_BRANCH" ] || DN_BRANCH="(detached HEAD)"
  DN_DOWNGRADE=""
  if [ "$DN_MODE" = "enforce" ] && ! [ "$DN_BRANCH" = "$DN_DEFAULT" ]; then
    DN_MODE="report-only"
    DN_DOWNGRADE="Doc-numbering guard: enforce applies on $DN_DEFAULT only; on $DN_BRANCH this is report-only"
  fi
  if DN_OUT="$(cd "$PROJECT_ROOT" && node "$DOC_NUMBER_GUARD" --guard 2>&1)"; then
    pass "Doc-numbering guards clean (no-DRAFT-at-merge + duplicate-number)"
  elif [ "$DN_MODE" = "enforce" ]; then
    error "Doc-numbering guard failed (doc_number_guard: enforce) — commit blocked:"
    echo "$DN_OUT" | sed 's/^/    /'
  else
    warn "Doc-numbering guard found violations (report-only; commit allowed):"
    echo "$DN_OUT" | sed 's/^/    /'
    [ -z "$DN_DOWNGRADE" ] || echo "    $DN_DOWNGRADE"
  fi
else
  pass "Doc-numbering guard skipped (allocator absent or node unavailable)"
fi

# --- CHECK 9: Gitignored paths staged (post-validation-pushes-reuse-test-results D3) ---
# tracked-ignored.mjs --staged is the one predicate (repository .gitignore
# rules only; core.excludesFile and .git/info/exclude are not counted). An
# ADDED ignored path (git add -f, copy or rename destination) blocks; a
# MODIFIED already-tracked one warns (blocking only under --strict); a
# deletion passes. The remedy for deliberate tracking is a `!<path>`
# re-include in .gitignore, which is reviewable; there is no env bypass.
TRACKED_IGNORED_SCRIPT="$PROJECT_ROOT/.aai/scripts/tracked-ignored.mjs"
if [ -f "$TRACKED_IGNORED_SCRIPT" ] && ( command -v node ) >/dev/null 2>&1; then
  TI_RC=0
  TI_OUT="$(node "$TRACKED_IGNORED_SCRIPT" --staged 2>&1)" || TI_RC=$?
  if [ "$TI_RC" -gt 1 ]; then
    warn "Gitignored-path check could not run (tracked-ignored.mjs exit $TI_RC) — skipped"
    echo "$TI_OUT" | sed 's/^/    /'
  else
    TI_SEEN=0
    TI_ADDED=0
    PCC_REST="$TI_OUT"
    while [ -n "$PCC_REST" ]; do
      pcc_next_line
      TI_LINE="$PCC_LINE"
      case "$TI_LINE" in
        "IGNORED_ADDED "*)
          TI_REST="${TI_LINE#IGNORED_ADDED }"
          TI_PATH="${TI_REST% rule=*}"; TI_RULE="${TI_REST##* rule=}"
          TI_SEEN=1
          TI_ADDED=1
          error "Gitignored path staged for ADD: $TI_PATH (rule $TI_RULE) — to track it deliberately add \"!$TI_PATH\" to .gitignore; otherwise unstage it: git rm --cached -- \"$TI_PATH\""
          ;;
        "IGNORED_MODIFIED "*)
          TI_REST="${TI_LINE#IGNORED_MODIFIED }"
          TI_PATH="${TI_REST% rule=*}"; TI_RULE="${TI_REST##* rule=}"
          TI_SEEN=1
          warn "Tracked path matched by .gitignore is modified: $TI_PATH (rule $TI_RULE) — untrack it (git rm --cached) or re-include it with \"!$TI_PATH\""
          ;;
        "IGNORED_PREEXISTING count="*)
          TI_SEEN=1
          warn "${TI_LINE#IGNORED_PREEXISTING count=} tracked path(s) already match .gitignore (not touched by this commit) — run: node .aai/scripts/tracked-ignored.mjs --all"
          ;;
      esac
    done
    if [ "$TI_RC" -eq 1 ] && [ "$TI_ADDED" -eq 0 ]; then
      # exit 1 is "an ADDED ignored path"; with no IGNORED_ADDED line the script
      # itself failed (e.g. an uncaught load error) and checked nothing.
      warn "Gitignored-path check could not run (tracked-ignored.mjs exit 1 without an IGNORED_ADDED line) — skipped"
      echo "$TI_OUT" | sed 's/^/    /'
    elif [ "$TI_SEEN" -eq 0 ]; then
      pass "No gitignored path staged"
    fi
  fi
else
  warn "Gitignored-path check skipped (tracked-ignored.mjs absent or node unavailable)"
fi

# --- SUMMARY ---
echo ""
echo "─────────────────────────────────────"
if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}BLOCKED: $ERRORS error(s), $WARNINGS warning(s)${NC}"
  echo "Fix errors before committing."
  exit 1
elif [ "$WARNINGS" -gt 0 ] && [ "$STRICT" = "--strict" ]; then
  echo -e "${YELLOW}BLOCKED (strict mode): $WARNINGS warning(s)${NC}"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}PASS WITH WARNINGS: $WARNINGS warning(s)${NC}"
  exit 0
else
  echo -e "${GREEN}ALL CHECKS PASS${NC}"
  exit 0
fi
