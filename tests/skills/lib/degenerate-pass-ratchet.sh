# Degenerate-pass ratchet (DEBT-0004 Target State item b, Spec-AC-14).
#
# THE SHAPE IT COUNTS
#   a `log_pass` call whose own message says the branch it sits on is
#   "skipped" or "not applicable" — a guard reporting success on a check it
#   never ran. Established fact 18 of the frozen spec named this shape at 35
#   sites, measured with a CASE-INSENSITIVE grep; validation round 1
#   (BLOCKING-7) found that number both undisclosed as such and inconsistent
#   with what this file actually scans with. The plain (case-sensitive) grep
#   this file uses — see DPR_PATTERN/DPR_QUALIFIER below — measures 31 sites
#   over `tests/skills/*.sh` on origin/main before this ride (35 only with
#   `grep -i`; measured, the four-site gap is entirely qualifier CASING —
#   "Skipped"/"SKIPPED" instead of "skipped" — never a different word; the
#   plain grep is the deliberate choice, matching every OTHER ratchet in
#   this file's own family (pipe-grep-q-ratchet.sh, cd-subshell-leak, etc.),
#   all case-sensitive). Nine of the
#   31 were named guards whose degenerate branch is a DEBT-0004 vacuous-pass
#   and are converted to a failing UNCOVERED report by this same scope
#   (Spec-AC-14); five of those nine happened to also carry this file's own
#   log_pass+skipped/not-applicable shape, so the SHIPPED baseline is 26 (31
#   minus those five — see docs/specs/SPEC-0179-spec-test-framework-sweep.md
#   `## Amendment`, which corrects Established fact 18 to these measured
#   numbers). The rest are legitimate platform/environment skips (a missing
#   binary, an OS this suite does not run on) that stay `log_pass`-shaped on
#   purpose — this ratchet holds THAT remainder at its measured count so a
#   NEW vacuous guard cannot be added silently, without demanding every skip
#   become a hard failure.
#
# This file is a PURE library when sourced: no `set -u`, no `cd`, no test
# execution. `--record` is the one direct entry point. bash-3.2 safe: no
# `declare -A`, no `mapfile`, no process substitution. Structurally identical
# to tests/skills/lib/pipe-grep-q-ratchet.sh (Spec-AC-11) — same scan/compare/
# render/record shape, a different pattern.

# The idiom. Kept in one place so the scan and the record mode can never
# disagree about what is being counted. Plain (non -i) grep: this is the
# MEASURED provenance of the 31/26 counts above (case-sensitive; `grep -i`
# over the same corpus reads 35/30 instead, entirely qualifier casing —
# "Skipped"/"SKIPPED" — never a different word), not the other way around —
# validation round 2 (NB-11): an earlier draft of this comment instead
# claimed the grep was chosen to MATCH the spec's established-fact number,
# which had the causality backwards and was corrected here. (Review NB-7 /
# validator R3-NB-4: the post-scope `-i` figure was mis-typed 31 here; it is
# 30, measured under bash with /usr/bin/grep — the casing gap is 4 in both
# directions, 35-31 pre-scope and 30-26 post-scope.)
DPR_PATTERN='log_pass'
DPR_QUALIFIER='skipped|not applicable'

DPR_GREP=/usr/bin/grep
[ -x "$DPR_GREP" ] || DPR_GREP=grep

DPR_BASELINE_DEFAULT_REL="tests/skills/lib/degenerate-pass-baseline.tsv"

# dpr_scan <dir> — one `<count>\t<basename>` line per *.sh file in <dir> that
# carries a `log_pass` line also matching the skipped/not-applicable
# qualifier. Files with zero occurrences are omitted.
dpr_scan() {
  local _dpr_dir="$1" _dpr_f _dpr_n
  for _dpr_f in "$_dpr_dir"/*.sh; do
    [ -f "$_dpr_f" ] || continue
    _dpr_n="$("$DPR_GREP" "$DPR_PATTERN" "$_dpr_f" 2>/dev/null | "$DPR_GREP" -cE "$DPR_QUALIFIER" 2>/dev/null)" || _dpr_n=0
    [ -n "$_dpr_n" ] || _dpr_n=0
    [ "$_dpr_n" -gt 0 ] || continue
    printf '%s\t%s\n' "$_dpr_n" "${_dpr_f##*/}"
  done | LC_ALL=C sort -k2,2
}

# dpr_total <scan-output> — the sum of the count column.
dpr_total() {
  printf '%s\n' "$1" | awk -F'\t' 'NF{t+=$1} END{print t+0}'
}

# dpr_lookup <scan-or-baseline text> <basename> — that file's recorded count,
# or 0 when it is absent.
dpr_lookup() {
  printf '%s\n' "$1" | awk -F'\t' -v want="$2" '
    NF && $2==want { print $1+0; found=1; exit }
    END { if (!found) print 0 }'
}

# dpr_compare <baseline text> <scan text> — one verdict line per divergence:
#   RISE   <file> <baseline> <now>   a file gained a degenerate pass  (FAIL)
#   NEW    <file> 0 <now>            an unbaselined file has some     (FAIL)
#   SHRINK <file> <baseline> <now>   a file lost one                  (NOTE)
#   GONE   <file> <baseline> 0       a baselined file has none left   (NOTE)
# Silence means the corpus is exactly where it was recorded. The bar is never
# lowered automatically — same discipline as the pipe-grep-q ratchet.
dpr_compare() {
  local _dpr_base="$1" _dpr_now="$2" _dpr_f _dpr_b _dpr_n

  printf '%s\n' "$_dpr_now" | while IFS=$'\t' read -r _dpr_n _dpr_f; do
    [ -n "$_dpr_f" ] || continue
    _dpr_b="$(dpr_lookup "$_dpr_base" "$_dpr_f")"
    if [ "$_dpr_b" -eq 0 ]; then
      printf 'NEW %s %s %s\n' "$_dpr_f" 0 "$_dpr_n"
    elif [ "$_dpr_n" -gt "$_dpr_b" ]; then
      printf 'RISE %s %s %s\n' "$_dpr_f" "$_dpr_b" "$_dpr_n"
    elif [ "$_dpr_n" -lt "$_dpr_b" ]; then
      printf 'SHRINK %s %s %s\n' "$_dpr_f" "$_dpr_b" "$_dpr_n"
    fi
  done

  printf '%s\n' "$_dpr_base" | while IFS=$'\t' read -r _dpr_b _dpr_f; do
    [ -n "$_dpr_f" ] || continue
    _dpr_n="$(dpr_lookup "$_dpr_now" "$_dpr_f")"
    if [ "$_dpr_n" -eq 0 ]; then
      printf 'GONE %s %s %s\n' "$_dpr_f" "$_dpr_b" 0
    fi
  done
}

# dpr_read_baseline <path> — the baseline's data lines, comments stripped.
dpr_read_baseline() {
  "$DPR_GREP" -v '^#' "$1" 2>/dev/null | "$DPR_GREP" -v '^[[:space:]]*$' 2>/dev/null
  return 0
}

# dpr_render_baseline <dir> — the full baseline file, header included. The
# numbers come from dpr_scan, i.e. from THE SAME function the ratchet arm
# runs.
dpr_render_baseline() {
  local _dpr_dir="$1" _dpr_scan
  _dpr_scan="$(dpr_scan "$_dpr_dir")"
  printf '%s\n' \
    '# tests/skills/lib/degenerate-pass-baseline.tsv' \
    '#' \
    '# GENERATED, never hand-edited:' \
    '#   bash tests/skills/lib/degenerate-pass-ratchet.sh --record' \
    '#' \
    '# One `<sites>\t<suite file>` row per tests/skills/*.sh file that still' \
    '# calls log_pass on a branch its own message calls "skipped" or "not' \
    '# applicable" (DEBT-0004 Target State item b). The count may FALL, never' \
    '# RISE: a rise fails tests/skills/test-aai-hygiene-pack.sh and names the' \
    '# file. Nine such sites named in Spec-AC-14 are guards, converted to a' \
    '# failing UNCOVERED report instead of ratcheted; this baseline is the' \
    '# measured remainder — legitimate platform/environment skips.' \
    '#'
  printf '%s\n' "$_dpr_scan"
}

# --record [<out-file> [<scan-dir>]] — regenerate the baseline from a LIVE
# SCAN, same two-argument shape as the pipe-grep-q ratchet's recorder (Spec-
# AC-04 style: a fixture tree with a known planted count can be recorded and
# checked against what was measured).
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ "${1:-}" = "--record" ]; then
  _dpr_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _dpr_root="$(cd "$_dpr_self_dir/../../.." && pwd)"
  _dpr_out="${2:-$_dpr_root/$DPR_BASELINE_DEFAULT_REL}"
  _dpr_dir="${3:-$_dpr_root/tests/skills}"
  dpr_render_baseline "$_dpr_dir" > "$_dpr_out"
  _dpr_rec_scan="$(dpr_scan "$_dpr_dir")"
  printf 'recorded %s degenerate-pass site(s) across %s file(s) from %s -> %s\n' \
    "$(dpr_total "$_dpr_rec_scan")" \
    "$(printf '%s\n' "$_dpr_rec_scan" | "$DPR_GREP" -c '[^[:space:]]')" \
    "$_dpr_dir" "$_dpr_out"
fi
