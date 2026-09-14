# Unsafe-early-closing-reader-pipe ratchet
# (spec-assertions-must-not-die-on-their-own-payload, Spec-AC-03 / Spec-AC-04;
# widened round 10, remediation for PR #381).
#
# THE SHAPE IT COUNTS
#   producer | grep -q pattern
#   producer | grep -m1 pattern
#   producer | head -n1
# Each of `grep -q`/`grep -m`/`head` can stop reading before the producer is
# done writing. The producer takes SIGPIPE (141), and `set -o pipefail` turns
# that into a FAILED assertion or an aborted suite even though the reader
# found exactly what it was looking for. It is load-dependent — harmless for
# years, then reddens CI the day the producer is slow enough (or the payload
# large enough) for the reader to close the pipe first. Nothing warns first.
# This ratchet is the warning: the count of the shape may FALL, never RISE.
#
# ROUND 10 — WHY THE PATTERN WIDENED
# Through round 9 this ratchet gated only the COPIED IDIOM — an `echo`/
# `printf` of a variable piped into `grep -q` — the one shape with a drop-in
# pipe-free replacement (tests/skills/lib/assert-payload.sh), and reported a
# wider surface as INFO only, never gating it. CI on 1aab60bb reddened twice
# from sites the narrow gate did not cover (test-aai-docs-audit.sh TEST-003:
# `sed ... | grep -qE ...`; test-aai-layer-profiles.sh TEST-402: `profile_list
# ... | grep -m1 ...`) — neither an echo/printf producer, so both were outside
# the gate while still live 141 traps. Round 10 drained the whole class
# mechanically (tests/skills/lib/pipe-safe.sh's `qgrep`/`qhead`: read stdin to
# EOF into a temp file before handing it to the real `grep`/`head`, so the
# producer never sees an early-closing reader) and widens THIS gate to match:
# the shape now covers every reader spelling (`/usr/bin/grep`, `grep`,
# `ugrep`, `egrep`, `fgrep`, `head`) and every early-closing flag (`-q*`,
# `--quiet`, `--silent`, `-m`), independent of the producer. `| qgrep` /
# `| qhead` are the sanctioned replacements and are excluded BY CONSTRUCTION:
# the pattern requires the reader word to start immediately after the pipe's
# optional whitespace, and `qgrep`/`qhead` both have a non-whitespace `q`
# there instead, so the anchored match never lands on them (no lookahead
# needed, `grep -E` doesn't have one). The narrow copied-idiom shape from
# rounds 1-9 is a strict SUBSET of this pattern, so it stays covered.
#
# This file is a PURE library when sourced: no `set -u`, no `cd`, no test
# execution. `--record` is the one direct entry point. bash-3.2 safe: no
# `declare -A`, no `mapfile`, no process substitution.

# The shape, as an ERE. Kept in one place so the scan and the record mode can
# never disagree about what is being counted.
PGQ_PATTERN='[^|]\|[[:space:]]*((command[[:space:]]+)?\\?(/usr/bin/|/bin/)?(grep|ugrep|egrep|fgrep)([[:space:]]+-[A-Za-z]+|[[:space:]]+--[a-z-]+)*[[:space:]]+(-[A-Za-z]*q|--quiet|--silent|-m[[:space:]]*[0-9]+|--max-count)|(command[[:space:]]+)?\\?(/usr/bin/|/bin/)?head([[:space:]]|$))'
# A still-wider, purely informational surface: ANY pipe into ANY spelling of
# grep, regardless of flags (so it also counts readers that consume to EOF
# and are not part of this bug class, e.g. `producer | grep -c pattern`).
# Reported, never gated — it exists only so a reviewer can see how much wider
# "any pipe into grep" is than the gated early-closing-reader shape above.
PGQ_SUPERSET_PATTERN='[^|]\|[[:space:]]*(/usr/bin/grep|grep|ugrep|egrep|fgrep)[[:space:]]+'

# `grep` resolves to a shell FUNCTION in some interactive-adjacent environments
# in this repo (a ugrep wrapper), even non-interactively. Every measurement here
# goes through the absolute path so the number cannot depend on whose shell ran
# it. Falls back to PATH resolution where /usr/bin/grep does not exist.
PGQ_GREP=/usr/bin/grep
[ -x "$PGQ_GREP" ] || PGQ_GREP=grep

PGQ_BASELINE_DEFAULT_REL="tests/skills/lib/pipe-grep-q-baseline.tsv"

# pgq_scan <dir> — one `<count>\t<basename>` line per *.sh file in <dir> that
# carries the shape, sorted by name. Files with zero occurrences are omitted, so
# a file appearing at all is itself signal.
#
# `-o | wc -l` counts OCCURRENCES, not matching lines: two unsafe sites on one
# line would otherwise ratchet as one.
#
# `|| _pgq_n=0` is set -e safety, not belt-and-braces: `grep -Eo` on a CLEAN
# file exits 1, and a bare `_pgq_n="$(...)"` under the caller's `set -euo
# pipefail` aborts the whole suite on the first clean file. Most files are
# clean, so this fires immediately (the `rc=$?`-after-a-pipe trap, one layer
# down).
pgq_scan() {
  local _pgq_dir="$1" _pgq_f _pgq_n
  for _pgq_f in "$_pgq_dir"/*.sh; do
    [ -f "$_pgq_f" ] || continue
    _pgq_n="$("$PGQ_GREP" -vE '^[[:space:]]*#' "$_pgq_f" 2>/dev/null | "$PGQ_GREP" -Eo "$PGQ_PATTERN" 2>/dev/null | "$PGQ_GREP" -c '' 2>/dev/null)" || _pgq_n=0
    [ -n "$_pgq_n" ] || _pgq_n=0
    [ "$_pgq_n" -gt 0 ] || continue
    printf '%s\t%s\n' "$_pgq_n" "${_pgq_f##*/}"
  done | LC_ALL=C sort -k2,2
}

# pgq_scan_shipping <root> — the SECOND ratchet arm (round 10, PR #381 step
# 4): the same shape, over the SHIPPING scripts (`.aai/scripts/*.sh` and
# `.aai/scripts/lib/*.sh`), filtered to files that actually set `pipefail` —
# a script without it cannot suffer this class (no pipe status is promoted
# past the reader's own exit code), so it is deliberately left out of the
# gate rather than forced onto the here-string idiom for no defect behind
# it (same rationale as the tests/skills gate leaving structurally-small
# producers uncounted). One `<count>\t<relative-path>` line per matching
# file, sorted by path; a clean file is omitted.
# Deferred, by name and with a tracker: `.aai/scripts/pre-commit-checks.sh`
# is a protected_paths_l3 surface; this ride is ceremony 2 and may not edit
# it (test-aai-hitl-propagation TEST-014). Its 7 sites are tracked by
# fu-pre-commit-checks-pipe-grep-q and stay visible in the superset count.
PGQ_SHIPPING_DEFERRED_L3='.aai/scripts/pre-commit-checks.sh'
# Comment lines are dropped before counting in every arm: a `| head` quoted
# in prose is not a pipe (validation round 9 follow-through).
pgq_scan_shipping() {
  local _pgqs_root="$1" _pgqs_f _pgqs_n
  for _pgqs_f in "$_pgqs_root"/.aai/scripts/*.sh "$_pgqs_root"/.aai/scripts/lib/*.sh; do
    [ -f "$_pgqs_f" ] || continue
    [ "${_pgqs_f#"$_pgqs_root"/}" != "$PGQ_SHIPPING_DEFERRED_L3" ] || continue
    "$PGQ_GREP" -q 'pipefail' "$_pgqs_f" 2>/dev/null || continue
    _pgqs_n="$("$PGQ_GREP" -vE '^[[:space:]]*#' "$_pgqs_f" 2>/dev/null | "$PGQ_GREP" -Eo "$PGQ_PATTERN" 2>/dev/null | "$PGQ_GREP" -c '' 2>/dev/null)" || _pgqs_n=0
    [ -n "$_pgqs_n" ] || _pgqs_n=0
    [ "$_pgqs_n" -gt 0 ] || continue
    printf '%s\t%s\n' "$_pgqs_n" "${_pgqs_f#"$_pgqs_root"/}"
  done | LC_ALL=C sort -k2,2
}

# pgq_superset_count <dir> — the reported-only wider number.
pgq_superset_count() {
  local _pgq_dir="$1" _pgq_f _pgq_t=0 _pgq_n
  for _pgq_f in "$_pgq_dir"/*.sh; do
    [ -f "$_pgq_f" ] || continue
    _pgq_n="$("$PGQ_GREP" -vE '^[[:space:]]*#' "$_pgq_f" 2>/dev/null | "$PGQ_GREP" -Eo "$PGQ_SUPERSET_PATTERN" 2>/dev/null | "$PGQ_GREP" -c '' 2>/dev/null)" || _pgq_n=0
    [ -n "$_pgq_n" ] || _pgq_n=0
    _pgq_t=$(( _pgq_t + _pgq_n ))
  done
  printf '%s\n' "$_pgq_t"
}

# pgq_total <scan-output> — the sum of the count column.
pgq_total() {
  printf '%s\n' "$1" | awk -F'\t' 'NF{t+=$1} END{print t+0}'
}

# pgq_lookup <scan-or-baseline text> <basename> — that file's recorded count, or
# 0 when it is absent.
# One value, always exactly one line — no `| head -n 1` trimming a second line
# off, because a `head` on the right of a pipe is the same early-exit SIGPIPE
# shape this whole ratchet exists to remove.
pgq_lookup() {
  printf '%s\n' "$1" | awk -F'\t' -v want="$2" '
    NF && $2==want { print $1+0; found=1; exit }
    END { if (!found) print 0 }'
}

# pgq_compare <baseline text> <scan text> — one verdict line per divergence:
#   RISE   <file> <baseline> <now>   a file gained an occurrence          (FAIL)
#   NEW    <file> 0 <now>            a file not in the baseline has some  (FAIL)
#   SHRINK <file> <baseline> <now>   a file lost one                      (NOTE)
#   GONE   <file> <baseline> 0       a baselined file has none left       (NOTE)
# Silence means the corpus is exactly where it was recorded.
#
# THE BAR IS NEVER LOWERED AUTOMATICALLY. A SHRINK/GONE is reported so the
# operator can re-record deliberately — the same hand-drained discipline the
# known-offender ratchet in test-framework.sh uses, and for the same reason: a
# self-lowering ratchet re-arms itself one occurrence lower every time a file is
# edited for an unrelated reason, and nobody ever sees the bar move.
pgq_compare() {
  local _pgq_base="$1" _pgq_now="$2" _pgq_line _pgq_f _pgq_b _pgq_n

  # Files present NOW: RISE or NEW against the baseline.
  printf '%s\n' "$_pgq_now" | while IFS=$'\t' read -r _pgq_n _pgq_f; do
    [ -n "$_pgq_f" ] || continue
    _pgq_b="$(pgq_lookup "$_pgq_base" "$_pgq_f")"
    if [ "$_pgq_b" -eq 0 ]; then
      printf 'NEW %s %s %s\n' "$_pgq_f" 0 "$_pgq_n"
    elif [ "$_pgq_n" -gt "$_pgq_b" ]; then
      printf 'RISE %s %s %s\n' "$_pgq_f" "$_pgq_b" "$_pgq_n"
    elif [ "$_pgq_n" -lt "$_pgq_b" ]; then
      printf 'SHRINK %s %s %s\n' "$_pgq_f" "$_pgq_b" "$_pgq_n"
    fi
  done

  # Files in the baseline that have none left.
  printf '%s\n' "$_pgq_base" | while IFS=$'\t' read -r _pgq_b _pgq_f; do
    [ -n "$_pgq_f" ] || continue
    _pgq_n="$(pgq_lookup "$_pgq_now" "$_pgq_f")"
    if [ "$_pgq_n" -eq 0 ]; then
      printf 'GONE %s %s %s\n' "$_pgq_f" "$_pgq_b" 0
    fi
  done
}

# pgq_read_baseline <path> — the baseline's data lines, comments stripped.
pgq_read_baseline() {
  "$PGQ_GREP" -v '^#' "$1" 2>/dev/null | "$PGQ_GREP" -v '^[[:space:]]*$' 2>/dev/null
  return 0
}

# pgq_render_baseline <dir> — the full baseline file, header included. The
# numbers come from pgq_scan, i.e. from THE SAME function the ratchet arm runs
# (Spec-AC-04). Nothing in this file is transcribed from a document.
pgq_render_baseline() {
  local _pgq_dir="$1" _pgq_scan
  _pgq_scan="$(pgq_scan "$_pgq_dir")"
  printf '%s\n' \
    '# tests/skills/lib/pipe-grep-q-baseline.tsv' \
    '#' \
    '# GENERATED, never hand-edited:' \
    '#   bash tests/skills/lib/pipe-grep-q-ratchet.sh --record' \
    '#' \
    '# One `<occurrences>\t<suite file>` row per tests/skills/*.sh file that still' \
    '# pipes into an early-closing reader (`grep -q`/`-m`/`--quiet`/`--silent`, any' \
    '# spelling, or `head`). The count may FALL, never RISE: a rise fails' \
    '# tests/skills/test-aai-hygiene-pack.sh and names the file. A file that SHRINKS' \
    '# keeps its recorded number until someone re-records on purpose — the bar is' \
    '# lowered by hand, so that the lowering is visible.' \
    '#' \
    '# Every row is a latent CI red waiting for the producer to outrun the reader' \
    '# under `set -o pipefail`. The fix is tests/skills/lib/pipe-safe.sh (`qgrep`/' \
    '# `qhead`) for a real pipe, or tests/skills/lib/assert-payload.sh for the' \
    '# echo/printf-of-a-variable idiom specifically. This list only shrinks.' \
    '#'
  printf '%s\n' "$_pgq_scan"
}

# --record [<out-file> [<scan-dir>]] — regenerate the baseline from a LIVE SCAN.
# The two optional arguments exist so the Spec-AC-04 arm can point the recorder
# at a fixture tree with a KNOWN planted count and check that the number it
# writes is the number it measured. A recorder that could only ever write the
# real tree's number would be indistinguishable from one with the number typed
# into it.
# The `BASH_SOURCE == $0` half is load-bearing: a suite that SOURCES this
# library from inside one of its own functions would otherwise have that
# function's first argument tested against `--record`.
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ "${1:-}" = "--record" ]; then
  _pgq_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _pgq_root="$(cd "$_pgq_self_dir/../../.." && pwd)"
  _pgq_out="${2:-$_pgq_root/$PGQ_BASELINE_DEFAULT_REL}"
  _pgq_dir="${3:-$_pgq_root/tests/skills}"
  pgq_render_baseline "$_pgq_dir" > "$_pgq_out"
  _pgq_rec_scan="$(pgq_scan "$_pgq_dir")"
  printf 'recorded %s occurrence(s) across %s file(s) from %s -> %s\n' \
    "$(pgq_total "$_pgq_rec_scan")" \
    "$(printf '%s\n' "$_pgq_rec_scan" | "$PGQ_GREP" -c '[^[:space:]]')" \
    "$_pgq_dir" "$_pgq_out"
fi
