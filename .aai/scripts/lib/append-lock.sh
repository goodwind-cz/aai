#!/bin/sh
#
# append-lock.sh — serialised appends to an append-only ledger
# (spec-sweep-runs-in-parallel).
#
# THE PROPERTY BEING PROTECTED. `docs/ai/tests/test-runs.jsonl` is append-only,
# and the discipline this repository is held to (HAZ-LEDGER) is about BYTES:
# the base must remain a byte-exact PREFIX of the result, and every line must
# be whole. A half-written line is not a merge conflict a tool reports — it is
# silent corruption that no reader detects until it parses.
#
# WHY A LOCK RATHER THAN TRUSTING THE KERNEL. An `O_APPEND` write of one short
# line is atomic on the platforms this runs on, so TODAY's single small
# `printf ... >>` would survive contention unaided. That is a property of the
# current PAYLOAD, not of the file. The first append that is written in two
# `printf`s instead of one — or that grows past the atomic write size — will
# interleave, and nothing will fail until a reader hits the broken line months
# later. The lock moves the guarantee from "this particular payload happens to
# be small" to "appends to this file are serialised", which is the property the
# acceptance criterion actually asks for.
#
# CROSS-PROCESS, not merely cross-thread: the mutex is a DIRECTORY beside the
# target file, so two independent framework processes appending to the same
# ledger contend on the same lock. `mkdir` is the portable atomic test-and-set
# — `flock` is absent on macOS and `noclobber` is shell-local.
#
# CONTRACT
#   aai_locked_append <file> <line>...
#       Appends each <line>, newline-terminated, one per argument, with the
#       whole group written under one hold of the lock. Returns 0 on success
#       and 1 when the lock could not be taken within the timeout. It NEVER
#       falls back to an unlocked append: a caller that cannot lock must decide
#       what that means, because appending anyway is precisely the corruption
#       this library exists to prevent.
#
# The lock directory is `<file>.aai-lock`. It lives beside the target rather
# than in $TMPDIR because two processes must agree on it, and $TMPDIR is
# per-process (this repository's own test fixtures set it deliberately). It is
# covered by the repository's `*.aai-lock/` ignore rule, so a lock that is
# briefly live cannot show up as an untracked path under `docs/`.

# Seconds before a lock is treated as abandoned. A run that is killed mid-append
# must not wedge the ledger for the next one.
AAI_APPEND_LOCK_TIMEOUT=${AAI_APPEND_LOCK_TIMEOUT:-30}

# aai_append_lock_age <lockdir> — seconds since the lock was taken, or empty
# when that cannot be established. Age rather than pid liveness on purpose: a
# pid can be reused, and a waiter would then block on an unrelated process.
aai_append_lock_age() {
  al_stamp=$(cat "$1/stamp" 2>/dev/null) || al_stamp=''
  case "$al_stamp" in
    ''|*[!0-9]*) printf '' ; return 0 ;;
  esac
  al_now=$(date +%s 2>/dev/null) || al_now=''
  case "$al_now" in
    ''|*[!0-9]*) printf '' ; return 0 ;;
  esac
  printf '%s' "$(( al_now - al_stamp ))"
  return 0
}

# aai_append_lock_acquire <lockdir> — 0 when held, 1 on timeout.
aai_append_lock_acquire() {
  al_lock="$1"
  al_spins=0
  al_max=$(( AAI_APPEND_LOCK_TIMEOUT * 20 ))
  while ! mkdir "$al_lock" 2>/dev/null; do
    al_age=$(aai_append_lock_age "$al_lock")
    if [ -n "$al_age" ] && [ "$al_age" -gt "$AAI_APPEND_LOCK_TIMEOUT" ]; then
      rm -rf "$al_lock" 2>/dev/null || true
      continue
    fi
    al_spins=$(( al_spins + 1 ))
    if [ "$al_spins" -gt "$al_max" ]; then
      return 1
    fi
    sleep 0.05 2>/dev/null || sleep 1
  done
  date +%s > "$al_lock/stamp" 2>/dev/null || true
  return 0
}

aai_append_lock_release() {
  rm -rf "$1" 2>/dev/null || true
  return 0
}

aai_locked_append() {
  al_file="$1"
  shift
  al_dir=$(dirname "$al_file")
  [ -d "$al_dir" ] || mkdir -p "$al_dir" 2>/dev/null || return 1
  al_lockdir="$al_file.aai-lock"
  aai_append_lock_acquire "$al_lockdir" || return 1
  al_rc=0
  for al_line in "$@"; do
    printf '%s\n' "$al_line" >> "$al_file" || al_rc=1
  done
  aai_append_lock_release "$al_lockdir"
  return "$al_rc"
}
