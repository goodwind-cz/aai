#!/usr/bin/env bash
#
# shard-plan-check.sh — independent shard-plan completeness check (D4,
# SPEC-0206-spec-ci-test-selection-narrowing-and-sharding). Shares NO code
# with .aai/scripts/select-suites.mjs on purpose: this is the second,
# independent proof that a shard plan is complete, not a restatement of the
# selector's own bookkeeping.
#
# USAGE
#   bash tests/skills/lib/shard-plan-check.sh --check   <plan-file> <skills-dir>
#   bash tests/skills/lib/shard-plan-check.sh --check-selected <plan-file> <skills-dir> <expected-list>
#   bash tests/skills/lib/shard-plan-check.sh --extract <shard-id|all> <plan-file>
#
# --check exits non-zero, naming the offender on stderr, unless the plan's
# suite set equals `find <skills-dir> -name 'test-aai-*.sh' -type f` exactly
# (no suite missing, none extra, none assigned twice) AND every planned name
# is a safe shape ([A-Za-z0-9_-]+) that resolves to a top-level
# <skills-dir>/test-<name>.sh — the only file a leg's
# `test-framework.sh --skill <name>` can run. On success it prints
# one line: shard_ids=[<distinct shard ids, ascending, comma-separated>]. A
# plan whose only content is a SHARD_FALLBACK line passes and prints the
# literal all-shards marker instead (see check_mode below).
#
# --check-selected requires one or two nonempty, contiguous shards containing
# each suite in <expected-list> exactly once. It rejects malformed plans and
# unsafe or non-runnable suites; on success it prints shard_ids=[1] or [1,2].
#
# --extract <i> prints shard i's suites in plan order, one per line. An id
# with no suites exits non-zero. --extract all on a fallback plan prints
# __ALL__.
#
# Hygiene: every producer below (awk, sort, comm) reads directly from a FILE
# argument, never from another process's stdout through a pipe that could
# close early — `sort`/`comm`/`uniq` are terminal consumers that always read
# to EOF, so piping INTO them is safe (pipe-grep-q-ratchet: only an
# early-closing reader like `grep -q`/`head` SIGPIPEs its writer).

set -euo pipefail

TMP_PREFIX="${TMPDIR:-/tmp}/aai-shard-plan-check"
# A plain indexed array (bash 3.2 safe; no `declare -A`) plus ONE top-level
# EXIT trap — not a per-function `trap ... RETURN`, which bash scopes to the
# WHOLE PROCESS rather than to the defining function: it would still fire
# when an unrelated later function (e.g. `main` itself) returns, referencing
# a `local` temp-file variable that has by then gone out of scope under
# `set -u`.
ALL_TMP_FILES=()
cleanup() {
  if [[ ${#ALL_TMP_FILES[@]} -gt 0 ]]; then
    rm -f "${ALL_TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

usage() {
  echo "usage: shard-plan-check.sh --check <plan-file> <skills-dir>" >&2
  echo "       shard-plan-check.sh --check-selected <plan-file> <skills-dir> <expected-list>" >&2
  echo "       shard-plan-check.sh --extract <shard-id|all> <plan-file>" >&2
  exit 2
}

check_mode() {
  local plan="$1" skills_dir="$2"
  [[ -f "$plan" ]] || { echo "shard-plan-check: plan file not found: $plan" >&2; exit 1; }
  [[ -d "$skills_dir" ]] || { echo "shard-plan-check: skills dir not found: $skills_dir" >&2; exit 1; }

  if grep -qE '^SHARD_FALLBACK ' "$plan"; then
    echo 'shard_ids=["all"]'
    return 0
  fi

  local all_tmp planned_tmp expected_tmp ids_tmp
  all_tmp="$(mktemp "${TMP_PREFIX}-all.XXXXXX")"
  planned_tmp="$(mktemp "${TMP_PREFIX}-planned.XXXXXX")"
  expected_tmp="$(mktemp "${TMP_PREFIX}-expected.XXXXXX")"
  ids_tmp="$(mktemp "${TMP_PREFIX}-ids.XXXXXX")"
  ALL_TMP_FILES+=("$all_tmp" "$planned_tmp" "$expected_tmp" "$ids_tmp")

  awk '/^SHARD /{print $3}' "$plan" > "$all_tmp"
  sort -u "$all_tmp" > "$planned_tmp"
  find "$skills_dir" -name 'test-aai-*.sh' -type f -exec basename {} \; \
    | sed -e 's/^test-//' -e 's/\.sh$//' | sort -u > "$expected_tmp"

  local dup_tmp
  dup_tmp="$(mktemp "${TMP_PREFIX}-dup.XXXXXX")"
  ALL_TMP_FILES+=("$dup_tmp")
  sort "$all_tmp" | uniq -d > "$dup_tmp"
  local dup_count
  dup_count="$(wc -l < "$dup_tmp" | tr -d ' ')"
  if [[ "$dup_count" -ne 0 ]]; then
    local dup_offender
    # Read the first line from a FILE, not a pipe: `head`/`sed` closing early
    # against a REGULAR FILE never signals anything upstream, unlike the
    # `uniq -d | head -n1` shape this replaced (SIGPIPE under set -o pipefail
    # if uniq is still writing when head exits after its first line).
    dup_offender="$(awk 'NR==1' "$dup_tmp")"
    echo "shard-plan-check: suite assigned to more than one shard: $dup_offender" >&2
    exit 1
  fi

  # A suite can be PROVEN complete by the recursive find above and still be
  # unrunnable: each CI leg executes its shard via
  # `test-framework.sh --skill <name>`, which resolves only the TOP-LEVEL
  # "$skills_dir/test-<name>.sh" (test-framework.sh discover_tests(), the
  # SPECIFIC_SKILLS branch) and whose own `exit 2` on a missing file is lost
  # through a process-substitution pipeline, so a leg with a planned-but-
  # unresolvable suite ahead of others silently runs fewer suites and still
  # exits 0. Fail loudly here, naming the offender, instead of a green gate
  # hiding dropped coverage (BLOCKING-1, review-20261003T124300Z.md).
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
      echo "shard-plan-check: planned suite name has an unsafe shape, not [A-Za-z0-9_-]+: $name" >&2
      exit 1
    fi
    if [[ ! -f "$skills_dir/test-$name.sh" ]]; then
      echo "shard-plan-check: planned suite is not resolvable by test-framework.sh --skill (no top-level $skills_dir/test-$name.sh: nested in a subdirectory, or not on disk): $name" >&2
      exit 1
    fi
  done < "$planned_tmp"

  local planned_set expected_set
  planned_set="$(cat "$planned_tmp")"
  expected_set="$(cat "$expected_tmp")"
  if [[ "$planned_set" != "$expected_set" ]]; then
    local missing extra
    missing="$(comm -23 "$expected_tmp" "$planned_tmp" | tr '\n' ',' | sed 's/,$//')"
    extra="$(comm -13 "$expected_tmp" "$planned_tmp" | tr '\n' ',' | sed 's/,$//')"
    echo "shard-plan-check: plan suite set does not match on-disk suites (missing=${missing:-none} extra=${extra:-none})" >&2
    exit 1
  fi

  awk '/^SHARD /{print $2}' "$plan" | sort -un > "$ids_tmp"
  local ids
  ids="$(tr '\n' ',' < "$ids_tmp" | sed 's/,$//')"
  echo "shard_ids=[${ids}]"
}

# Selected mode is fail-closed and independent of the Node producer. Check
# grammar before extracting any fields; full-mode fallback stays unchanged.
check_selected_mode() {
  local plan="$1" skills_dir="$2" expected="$3" tmp name ids
  [[ -f "$plan" && -d "$skills_dir" && -f "$expected" ]] || {
    echo "selected-plan-check: unreadable plan, skills directory or expected list" >&2; exit 1;
  }
  tmp="$(mktemp -d "${TMP_PREFIX}-selected.XXXXXX")"
  # Reuse the file cleanup list; remove the directory explicitly on success.
  ALL_TMP_FILES+=("$tmp/expected" "$tmp/expected-unique" "$tmp/planned" "$tmp/raw")
  awk '
    /^$/ { next }
    /^SHARD [12] [A-Za-z0-9_-]+ weight=[1-9][0-9]*$/ { print $3; next }
    /^SHARDS count=[12] suites=[1-9][0-9]*$/ { summary++; next }
    /^SELECTED_DECISION runners=[12] reason=[a-z-]+ suites=[1-9][0-9]* workers=4 startup_seconds=30 min_suites=8 min_wall_seconds=120 min_saving_seconds=30 max_wall_ratio=0\.8 max_runner_ratio=1\.25 w1=[0-9]+ w2=[0-9]+ r1=[0-9]+ r2=[0-9]+$/ { decision++; next }
    { print "selected-plan-check: malformed record: " $0 > "/dev/stderr"; bad=1 }
    END { if (summary != 1 || decision != 1) { print "selected-plan-check: invalid metadata record count" > "/dev/stderr"; bad=1 } if (bad) exit 1 }
  ' "$plan" > "$tmp/raw" || exit 1
  [[ -s "$tmp/raw" ]] || { echo 'selected-plan-check: empty plan' >&2; exit 1; }
  sort "$tmp/raw" > "$tmp/planned"
  sort -u "$tmp/raw" > "$tmp/expected"
  if ! cmp -s "$tmp/planned" "$tmp/expected"; then
    echo "selected-plan-check: duplicate suite: $(sort "$tmp/raw" | uniq -d)" >&2; exit 1
  fi
  while IFS= read -r name || [[ -n "$name" ]]; do
    [[ -n "$name" ]] || continue
    [[ "$name" =~ ^aai-[A-Za-z0-9_-]+$ && -f "$skills_dir/test-$name.sh" ]] || {
      echo "selected-plan-check: unsafe or non-runnable expected suite: $name" >&2; exit 1;
    }
  done < "$expected"
  sed '/^$/d' "$expected" | sort > "$tmp/expected"
  [[ -s "$tmp/expected" ]] || { echo 'selected-plan-check: empty expected list' >&2; exit 1; }
  sort -u "$tmp/expected" > "$tmp/expected-unique"
  if ! cmp -s "$tmp/expected" "$tmp/expected-unique"; then
    echo "selected-plan-check: duplicate expected suite: $(uniq -d "$tmp/expected")" >&2; exit 1
  fi
  if ! cmp -s "$tmp/planned" "$tmp/expected"; then
    echo "selected-plan-check: membership mismatch: $(comm -3 "$tmp/expected" "$tmp/planned")" >&2; exit 1
  fi
  while IFS= read -r name; do
    [[ "$name" =~ ^aai-[A-Za-z0-9_-]+$ && -f "$skills_dir/test-$name.sh" ]] || {
      echo "selected-plan-check: unsafe or non-runnable planned suite: $name" >&2; exit 1;
    }
  done < "$tmp/planned"
  ids="$(awk '$1=="SHARD"{print $2}' "$plan" | sort -un | tr '\n' ',')"
  [[ "$ids" == '1,' || "$ids" == '1,2,' ]] || {
    echo "selected-plan-check: noncontiguous shard ids: $ids" >&2; exit 1;
  }
  awk '
    $1=="SHARD" { n++; seen[$2]=1 }
    $1=="SHARDS" { split($2,a,"="); count=a[2]; split($3,b,"="); total=b[2] }
    $1=="SELECTED_DECISION" { split($2,a,"="); runners=a[2]; split($4,b,"="); suites=b[2] }
    END { k=seen[1]+seen[2]; if (k!=count || n!=total || (runners && (runners!=k || suites!=n))) {
      print "selected-plan-check: inconsistent SHARDS/SELECTED_DECISION counts" > "/dev/stderr"; exit 1
    } }
  ' "$plan" || exit 1
  rm -f "$tmp/expected" "$tmp/expected-unique" "$tmp/planned" "$tmp/raw"
  rmdir "$tmp"
  echo "shard_ids=[${ids%,}]"
}

extract_mode() {
  local idx="$1" plan="$2"
  [[ -f "$plan" ]] || { echo "shard-plan-check: plan file not found: $plan" >&2; exit 1; }

  if [[ "$idx" == "all" ]]; then
    if grep -qE '^SHARD_FALLBACK ' "$plan"; then
      echo '__ALL__'
      return 0
    fi
    echo "shard-plan-check: --extract all is only valid on a fallback plan" >&2
    exit 1
  fi

  [[ "$idx" =~ ^[0-9]+$ ]] || { echo "shard-plan-check: invalid shard id: $idx" >&2; exit 1; }

  local found_tmp
  found_tmp="$(mktemp "${TMP_PREFIX}-extract.XXXXXX")"
  ALL_TMP_FILES+=("$found_tmp")
  awk -v idx="$idx" '$1=="SHARD" && $2 == idx {print $3}' "$plan" > "$found_tmp"
  if [[ ! -s "$found_tmp" ]]; then
    echo "shard-plan-check: no suites for shard id: $idx" >&2
    exit 1
  fi
  cat "$found_tmp"
}

main() {
  [[ $# -ge 1 ]] || usage
  local mode="$1"; shift
  case "$mode" in
    --check-selected)
      [[ $# -eq 3 ]] || usage
      check_selected_mode "$1" "$2" "$3"
      ;;
    --check)
      [[ $# -eq 2 ]] || usage
      check_mode "$1" "$2"
      ;;
    --extract)
      [[ $# -eq 2 ]] || usage
      extract_mode "$1" "$2"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
