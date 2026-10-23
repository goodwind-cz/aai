#!/usr/bin/env bash
# Shared live-corpus helpers for tests/skills/test-aai-docs-audit.sh
# (docs-audit-suite-speed, D1).
#
# WHY THIS EXISTS
#   The suite used to launch the same full audit over the real repository
#   fourteen times and the real index generator eleven times per run, with
#   byte-identical results (measured: docs/analysis/docs-audit-suite-speed.md).
#   This library owns every such launch (the pinned-clock generation in
#   index_generate_at excepted) so each distinct one happens once per run.
#
#   live_audit <dest> <args...>
#       Runs `node .aai/scripts/docs-audit.mjs <args>` in LIVE_ROOT at most once
#       per cache key (the argument list plus live_fingerprint), copies the
#       combined stdout and stderr to <dest> and returns the stored exit code.
#       AAI_DOCS_AUDIT_LIVE_VERIFY=1 re-runs every hit and fails on a
#       difference, naming LIVE-CACHE MISMATCH.
#   live_index_pair
#       Generates the real index twice once per run, snapshots the three index
#       files after each run under $LIVE_PAIR_DIR, then restores INDEX.md and the
#       violations companion BEFORE returning, so no assertion runs against a
#       regenerated tree (the restore-order defect: a regenerated INDEX.md used
#       to be read as the "committed" index by the staleness check).
#   live_backup_real <dir> / live_restore_real <dir>
#       The backup and restore the pair uses; also used around the pinned-clock
#       generation in setup_indexarm_snapshots.
#
# Root is LIVE_ROOT, default PROJECT_ROOT, so the suite's own tests drive this
# against a fixture repository. The cache lives under TEST_DIR.
#
# This file is a PURE library: no `set -e`, no `set -u`, no `cd` in the caller's
# shell, no test execution. It relies on log_fail from the sourcing suite.
# bash-3.2 safe: no `declare -A`, no `mapfile`, no `$EPOCHREALTIME`.

LIVE_ROOT="${LIVE_ROOT:-}"
LIVE_CACHE_DIR="${LIVE_CACHE_DIR:-}"
LIVE_PAIR_DIR=""

live_cache_init() {
  if [[ -z "${LIVE_CACHE_DIR:-}" ]]; then
    if [[ -z "${TEST_DIR:-}" ]]; then
      TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-docs-audit-test.XXXXXX")"
    fi
    LIVE_CACHE_DIR="$TEST_DIR/live-cache"
  fi
  mkdir -p "$LIVE_CACHE_DIR"
}

# Everything the suite itself writes under the real tree that an audit reads:
# the root, its HEAD commit and the content of the two index files (absent is
# a value). Anything else under the root is constant for the length of a run.
live_fingerprint() {
  local root="${LIVE_ROOT:-$PROJECT_ROOT}" head f sums=""
  head="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo nohead)"
  for f in docs/INDEX.md docs/INDEX.violations.md; do
    if [[ -f "$root/$f" ]]; then
      sums="$sums $(cksum < "$root/$f")"
    else
      sums="$sums absent"
    fi
  done
  printf '%s|%s|%s' "$root" "$head" "$sums"
}

# One line per real launch, so a test (or a node shim) can count them.
live_log_launch() {  # $1 = kind, $2... = detail
  local kind="$1"; shift
  printf '%s\t%s\n' "$kind" "$*" >> "$LIVE_CACHE_DIR/launches.log"
}

live_launch_count() {  # $1 = kind (audit | index)
  if [[ ! -f "$LIVE_CACHE_DIR/launches.log" ]]; then
    printf '0'
    return 0
  fi
  awk -F '\t' -v k="$1" '$1 == k { n++ } END { print n + 0 }' "$LIVE_CACHE_DIR/launches.log"
}

live_audit() {  # $1 = dest, $2... = docs-audit arguments
  local dest="$1"; shift
  local root="${LIVE_ROOT:-$PROJECT_ROOT}"
  live_cache_init
  local key_src="$* @ $(live_fingerprint)"
  local key base cache_out cache_rc rc=0
  key="$(printf '%s' "$key_src" | cksum | tr ' ' '-')"
  base="$LIVE_CACHE_DIR/audit-$key"
  cache_out="$base.out"
  if [[ -f "$cache_out" && -f "$base.rc" && -f "$base.key" && "$(cat "$base.key")" == "$key_src" ]]; then
    cache_rc="$(cat "$base.rc")"
    if [[ "${AAI_DOCS_AUDIT_LIVE_VERIFY:-}" == "1" ]]; then
      local fresh_out="$base.verify" fresh_rc=0
      (cd "$root" && node .aai/scripts/docs-audit.mjs "$@") > "$fresh_out" 2>&1 || fresh_rc=$?
      live_log_launch audit-verify "$*"
      if [[ "$fresh_rc" != "$cache_rc" ]] || ! cmp -s "$fresh_out" "$cache_out"; then
        log_fail "LIVE-CACHE MISMATCH for 'docs-audit $*' in $root: cached exit $cache_rc, fresh exit $fresh_rc, output differs or exit codes differ"
      fi
    fi
    cp "$cache_out" "$dest"
    return "$cache_rc"
  fi
  (cd "$root" && node .aai/scripts/docs-audit.mjs "$@") > "$base.tmp" 2>&1 || rc=$?
  live_log_launch audit "$*"
  mv "$base.tmp" "$cache_out"
  printf '%s\n' "$rc" > "$base.rc"
  printf '%s' "$key_src" > "$base.key"
  cp "$cache_out" "$dest"
  return "$rc"
}

# Copy INDEX.md and the violations companion (when present) into <dir>.
live_backup_real() {  # $1 = backup dir
  local root="${LIVE_ROOT:-$PROJECT_ROOT}"
  mkdir -p "$1"
  rm -f "$1/INDEX.md" "$1/INDEX.violations.md"
  if [[ -f "$root/docs/INDEX.md" ]]; then cp "$root/docs/INDEX.md" "$1/INDEX.md"; fi
  if [[ -f "$root/docs/INDEX.violations.md" ]]; then cp "$root/docs/INDEX.violations.md" "$1/INDEX.violations.md"; fi
}

# Put INDEX.md back byte for byte, put a pre-existing companion back, and remove
# one the generator created.
live_restore_real() {  # $1 = backup dir written by live_backup_real
  local root="${LIVE_ROOT:-$PROJECT_ROOT}"
  local live_idx="$root/docs/INDEX.md" live_idx_backup="$1/INDEX.md"
  local live_viol="$root/docs/INDEX.violations.md" live_viol_backup="$1/INDEX.violations.md"
  if [[ -f "$live_idx_backup" ]]; then
    cp "$live_idx_backup" "$live_idx"
  fi
  if [[ -f "$live_viol_backup" ]]; then
    cp "$live_viol_backup" "$live_viol"
  else
    rm -f "$live_viol"
  fi
}

live_pair_rc() {  # $1 = 1 | 2
  cat "$LIVE_PAIR_DIR/rc$1"
}

live_index_pair() {
  local root="${LIVE_ROOT:-$PROJECT_ROOT}" n rc f
  live_cache_init
  LIVE_PAIR_DIR="$LIVE_CACHE_DIR/index-pair"
  if [[ -f "$LIVE_PAIR_DIR/done" ]]; then
    return 0
  fi
  # The suite's restore floor covers an interrupted run on the shipping tree.
  if [[ "$root" == "$PROJECT_ROOT" && -z "${INDEX_REAL_BACKUP:-}" ]] \
      && declare -F index_arm_restore_floor >/dev/null 2>&1; then
    index_arm_restore_floor "$LIVE_CACHE_DIR/INDEX.real.orig"
  fi
  rm -rf "$LIVE_PAIR_DIR"
  mkdir -p "$LIVE_PAIR_DIR"
  live_backup_real "$LIVE_PAIR_DIR/real"
  for n in 1 2; do
    rc=0
    (cd "$root" && node .aai/scripts/generate-docs-index.mjs) > "$LIVE_PAIR_DIR/gen$n.log" 2>&1 || rc=$?
    live_log_launch index "run $n"
    printf '%s\n' "$rc" > "$LIVE_PAIR_DIR/rc$n"
    for f in INDEX.md INDEX.audit.md INDEX.violations.md; do
      if [[ -f "$root/docs/$f" ]]; then cp "$root/docs/$f" "$LIVE_PAIR_DIR/run$n.$f"; fi
    done
  done
  live_restore_real "$LIVE_PAIR_DIR/real"
  : > "$LIVE_PAIR_DIR/done"
}

# Fail, naming <label>, when either generator run of the pair exited nonzero.
live_pair_require_ok() {  # $1 = label
  local n
  for n in 1 2; do
    if [[ "$(live_pair_rc "$n")" != "0" ]]; then
      log_fail "$1 (run $n) failed: $(cat "$LIVE_PAIR_DIR/gen$n.log")"
    fi
  done
}
