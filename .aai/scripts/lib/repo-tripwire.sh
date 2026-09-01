#!/bin/sh
#
# repo-tripwire.sh — the shipping-repository write tripwire
# (spec-suites-must-not-touch-the-shipping-repo).
#
# THE INCIDENT: on 2026-08-14 a read-only validator probe helper `cd`-ed into a
# fixture INSIDE a command substitution — a subshell — so the parent shell
# stayed in the real repository and two commits landed on `main`. It was caught
# by luck, not by a check. Two suites additionally rewrite tracked files on
# every run, so validation and remediation have to skip exactly the suites that
# cover the surface being changed.
#
# This library is sourced by the two funnels every suite enters through:
#   - tests/skills/test-framework.sh  (the one CI runs — load-bearing)
#   - .aai/scripts/aai-run-tests.sh   (the one roles invoke ad hoc)
# It is POSIX sh so both a bash caller and a /bin/sh caller can source it.
#
# CONTRACT
#   aai_tripwire_snapshot <repo_root> <out_file>
#       One snapshot: a `HEAD <sha>` line followed by verbatim
#       `git status --porcelain=v1` output. Exactly ONE `git status` call per
#       snapshot, so a before/after pair is exactly one pair per suite.
#       Unavailable inputs are written as explicit UNAVAILABLE markers rather
#       than as an empty (and therefore falsely "unchanged") snapshot.
#   aai_tripwire_usable <snapshot_file>
#       Returns 0 when that snapshot is a real observation of the repository,
#       1 when it could not be taken. Lets a caller tell "never armed" (both
#       snapshots unusable) from "lost mid-run" (the before-snapshot was taken
#       and the after-snapshot was not) — two cases with opposite consequences.
#   aai_tripwire_state <before_file> <after_file>
#       Echoes exactly one of: clean | dirty | unavailable. Always returns 0 so
#       a `set -e` caller can capture it.
#   aai_tripwire_report <before_file> <after_file> <label> <prefix> [remediation]
#       Prints the named, human-readable difference (what changed, not merely
#       that something did). The CALLER decides the exit-code consequence.
#       [remediation] is OPTIONAL and defaults to the suite sentence below —
#       every caller that omits it prints a byte-identical block to before
#       this parameter existed (D3, spec-adhoc-probes-unisolated-report-only).
#   aai_tripwire_changed_paths <before_file> <after_file>
#       Echoes one repository-relative path per line, one per status line that
#       appears on only one side, for a caller that must decide WHICH paths
#       moved rather than merely that some did.
#   aai_tripwire_hash_snapshot <repo_root> <out_file> <path>...
#       One CONTENT snapshot of a NAMED, BOUNDED set of paths: one
#       `<digest|ABSENT|UNREADABLE> <path>` line per path, after a `HASHER`
#       header line. This is the escape hatch from the class-not-content limit
#       below, priced per path rather than per tree.
#   aai_tripwire_hash_changed <before_file> <after_file>
#       Echoes one path per line whose CONTENT moved between two hash
#       snapshots — including a path whose `git status` class did not change.
#
# The tripwire must never write to the repository it watches:
# --no-optional-locks stops `git status` from refreshing and rewriting
# .git/index, so arming the tripwire cannot itself be a repository write.
#
# `clean` means the tree did not move. It does NOT mean the suite ran: a
# skipped or crashed suite touches nothing and so is trivially clean. Callers
# must keep those cases distinguishable (D4) — this library reports the tree,
# and only the tree.
#
# KNOWN LIMIT (D7): `git status --porcelain=v1` reports the change CLASS of a
# path, not its content. If a path is ALREADY dirty when the observed command
# starts, a further change by that command to the SAME path leaves the porcelain
# output byte-identical and this library reports `clean`.
#
# The dirt does NOT have to pre-exist the run. A caller that observes a SEQUENCE
# of commands against one checkout manufactures it: from the moment any observed
# command dirties a path, every later write to that same path is invisible to a
# status comparison — on a clean checkout exactly as much as on a dirty one. So
# the only true form of "the first write is always caught" is per PATH and per
# RUN, not per command: the first observed command to dirty a path is caught,
# and no later one is. A caller that treats a clean checkout as making this
# limit harmless is wrong whenever it observes more than one command.
#
# Closing it for the whole tree needs a content hash per observation, which
# costs more than the commands being watched. Closing it for a NAMED, BOUNDED
# path set is cheap, and that is what `aai_tripwire_hash_snapshot` and
# `aai_tripwire_hash_changed` exist for: a caller that knows which paths its own
# runs dirty hashes exactly those and gets a content answer for them.
# `tests/skills/test-framework.sh` hashes every path its known-offender ratchet
# names — precisely the set the ratchet itself dirties — so masking cannot be
# manufactured by the exemption mechanism. Every path OUTSIDE such a named set
# keeps the class-only bound above.
# Tracked as `fu-tripwire-porcelain-class-not-content`.
#
# KNOWN LIMIT, for a caller that scopes an exemption to a PATH LIST: this
# library reports the paths that MOVED, and a path that was ALREADY dirty when
# the observed command started does not move. So a caller comparing
# `aai_tripwire_changed_paths` against an allowlist cannot see an out-of-list
# write to a path that was dirty beforehand. In
# `tests/skills/test-framework.sh` that means an allowlisted suite writing both
# a listed path and an already-dirty NON-ratchet path reads
# `tripwire ALLOWED ... inside its listed path(s)` at exit 0, with the
# out-of-entry write landed (reproduced with a pre-existing `M docs/other.md`).
# Ratchet paths are exempt — they are content-hashed. It is stated rather than
# enforced because on a clean start the only way a non-ratchet path becomes
# pre-dirty is an earlier command that already failed the run, so it degrades a
# red run's offender list rather than making a run green. A caller that
# needs the bound closed must diff against its own before-snapshot, which it
# holds. Tracked as `fu-tripwire-allowed-ignores-pre-dirty` (validation
# suggested `fu-tripwire-attested-clean-ignores-pre-dirty-paths`, 10 characters
# over the ledger's 40-char id limit).

# Maximum number of changed status lines reported before truncation. A suite
# that rewrites hundreds of files must not flood a CI log; the truncation is
# NAMED rather than silent (AGENTS.md degrade-with-NOTE convention).
AAI_TRIPWIRE_MAX_LINES=${AAI_TRIPWIRE_MAX_LINES:-40}

aai_tripwire_snapshot() {
  # $1 = repository root, $2 = output file
  tw_root="$1"
  tw_out="$2"
  {
    if tw_head=$(git --no-optional-locks -C "$tw_root" rev-parse HEAD 2>/dev/null); then
      printf 'HEAD %s\n' "$tw_head"
    else
      printf 'HEAD UNAVAILABLE\n'
    fi
    git --no-optional-locks -C "$tw_root" status --porcelain=v1 2>/dev/null \
      || printf 'STATUS UNAVAILABLE\n'
  } > "$tw_out" 2>/dev/null
  return 0
}

aai_tripwire_usable() {
  # $1 = snapshot file. 0 = a real observation, 1 = it could not be taken.
  # No pipelines in the predicates below: a caller running under
  # `set -o pipefail` turns a SIGPIPE from `head` into a false negative.
  if [ ! -s "$1" ]; then
    return 1
  fi
  tw_u_head=$(head -n 1 "$1")
  if [ "$tw_u_head" = 'HEAD UNAVAILABLE' ]; then
    return 1
  fi
  if grep -q '^STATUS UNAVAILABLE$' "$1"; then
    return 1
  fi
  return 0
}

aai_tripwire_state() {
  # $1 = before file, $2 = after file. Echoes clean | dirty | unavailable.
  if ! aai_tripwire_usable "$1" || ! aai_tripwire_usable "$2"; then
    echo unavailable
    return 0
  fi
  if cmp -s "$1" "$2"; then
    echo clean
  else
    echo dirty
  fi
  return 0
}

aai_tripwire_report() {
  # $1 = before file, $2 = after file, $3 = label, $4 = line prefix,
  # $5 = OPTIONAL trailing remediation line (D3,
  # spec-adhoc-probes-unisolated-report-only). Defaulted to today's sentence so
  # every EXISTING caller (test-framework.sh, and this wrapper's own suite/
  # framework branch) prints a byte-identical block by omitting it; only the
  # ad-hoc caller in aai-run-tests.sh ever passes something else.
  tw_before="$1"
  tw_after="$2"
  tw_label="$3"
  tw_prefix="$4"
  tw_remediation="${5:-A suite must run against a fixture, never against PROJECT_ROOT.}"
  printf '%s FAIL: %s changed the shipping repository.\n' "$tw_prefix" "$tw_label"
  tw_hb=$(head -n 1 "$tw_before")
  tw_ha=$(head -n 1 "$tw_after")
  tw_hb=${tw_hb#HEAD }
  tw_ha=${tw_ha#HEAD }
  if [ "$tw_hb" != "$tw_ha" ]; then
    printf '%s   HEAD moved: %s -> %s\n' "$tw_prefix" "$tw_hb" "$tw_ha"
  fi
  tw_n=0
  tw_more=0
  # `diff` exits 1 whenever the files differ, which is ALWAYS the case here.
  # Left bare, that status becomes the pipeline's status under
  # `set -o pipefail` and kills a `set -e` caller mid-report — which is exactly
  # how the first draft of this library truncated the framework's own run.
  { diff "$tw_before" "$tw_after" 2>/dev/null || true; } | {
    while IFS= read -r tw_line; do
      case "$tw_line" in
        '< HEAD '* | '> HEAD '*) continue ;;
        '< '*) tw_kind='was' ; tw_body=${tw_line#< } ;;
        '> '*) tw_kind='now' ; tw_body=${tw_line#> } ;;
        *) continue ;;
      esac
      tw_n=$((tw_n + 1))
      if [ "$tw_n" -le "$AAI_TRIPWIRE_MAX_LINES" ]; then
        printf '%s   %s: %s\n' "$tw_prefix" "$tw_kind" "$tw_body"
      else
        tw_more=$((tw_more + 1))
      fi
    done
    if [ "$tw_more" -gt 0 ]; then
      printf '%s   NOTE: %s further changed status line(s) not shown (cap AAI_TRIPWIRE_MAX_LINES=%s).\n' \
        "$tw_prefix" "$tw_more" "$AAI_TRIPWIRE_MAX_LINES"
    fi
  }
  printf '%s   %s\n' "$tw_prefix" "$tw_remediation"
  return 0
}

aai_tripwire_hasher() {
  # Echoes the digest command to use, or nothing when the environment has none.
  # Always returns 0: a `tw_x=$(aai_tripwire_hasher)` assignment in a `set -e`
  # caller must not become the thing that kills the run.
  if [ -n "${AAI_TRIPWIRE_HASHER:-}" ]; then
    # An override naming a command that is not there must degrade as NO hasher,
    # not as a hasher that silently fails on every path: two failed digests
    # compare equal, which would read as an unchanged file.
    if command -v "${AAI_TRIPWIRE_HASHER%% *}" >/dev/null 2>&1; then
      printf '%s\n' "$AAI_TRIPWIRE_HASHER"
    fi
    return 0
  fi
  for tw_hh in 'shasum -a 256' 'sha256sum' 'cksum'; do
    if command -v "${tw_hh%% *}" >/dev/null 2>&1; then
      printf '%s\n' "$tw_hh"
      return 0
    fi
  done
  return 0
}

aai_tripwire_hash_snapshot() {
  # $1 = repository root, $2 = output file, $3.. = repository-relative paths.
  # Digests are read from STDIN so the tool's own filename echo cannot end up in
  # the record; an absent or unreadable path is written as an explicit marker
  # rather than as a missing line, so a deletion still shows up as a change.
  tw_hs_root="$1"
  tw_hs_out="$2"
  shift 2
  tw_hs_cmd="$(aai_tripwire_hasher)"
  {
    if [ -z "$tw_hs_cmd" ]; then
      printf 'HASHER UNAVAILABLE\n'
    else
      printf 'HASHER %s\n' "$tw_hs_cmd"
      for tw_hs_p in "$@"; do
        [ -n "$tw_hs_p" ] || continue
        if [ -f "$tw_hs_root/$tw_hs_p" ]; then
          # Intentionally unquoted: the hasher is a command plus its flags.
          # shellcheck disable=SC2086
          tw_hs_d=$($tw_hs_cmd < "$tw_hs_root/$tw_hs_p" 2>/dev/null | tr -d '[:space:]-') \
            || tw_hs_d=''
          if [ -z "$tw_hs_d" ]; then
            printf 'UNREADABLE %s\n' "$tw_hs_p"
          else
            printf '%s %s\n' "$tw_hs_d" "$tw_hs_p"
          fi
        else
          printf 'ABSENT %s\n' "$tw_hs_p"
        fi
      done
    fi
  } > "$tw_hs_out" 2>/dev/null
  return 0
}

aai_tripwire_hash_usable() {
  # $1 = hash snapshot file. 0 = the paths were really digested, 1 = they were
  # not (no hasher on this machine), so a caller can NAME the degrade instead of
  # reading an empty difference as proof of an unchanged file.
  if [ ! -s "$1" ]; then
    return 1
  fi
  tw_hu_head=$(head -n 1 "$1")
  if [ "$tw_hu_head" = 'HASHER UNAVAILABLE' ]; then
    return 1
  fi
  return 0
}

aai_tripwire_hash_changed() {
  # $1 = before file, $2 = after file. One path per line, for every watched path
  # whose CONTENT moved — the answer `git status --porcelain=v1` cannot give.
  # Only the after-side (`> `) lines are read: both snapshots carry one line per
  # watched path in the same order, so a changed path contributes exactly one.
  { diff "$1" "$2" 2>/dev/null || true; } | {
    while IFS= read -r tw_hc_line; do
      case "$tw_hc_line" in
        '> HASHER '*) continue ;;
        '> '*) tw_hc_body=${tw_hc_line#> } ;;
        *) continue ;;
      esac
      printf '%s\n' "${tw_hc_body#* }"
    done
  }
  return 0
}

aai_tripwire_changed_paths() {
  # $1 = before file, $2 = after file. One path per line.
  # A HEAD move has no path and is deliberately NOT reported here: a caller
  # that scopes a decision to paths must never treat a commit as path-free.
  { diff "$1" "$2" 2>/dev/null || true; } | {
    while IFS= read -r tw_cp_line; do
      case "$tw_cp_line" in
        '< HEAD '* | '> HEAD '*) continue ;;
        '< '* | '> '*) tw_cp_body=${tw_cp_line#??} ;;
        *) continue ;;
      esac
      # porcelain v1 is two status characters, a space, then the path. A path
      # git quotes (special characters) or a rename (`old -> new`) is emitted
      # verbatim rather than parsed: it then matches no caller's known-path
      # list, which is the fail-closed direction.
      printf '%s\n' "${tw_cp_body#???}"
    done
  }
  return 0
}
