# test-residue.sh — remove the container residue ONE test run provably
# created, and nothing else (CHANGE test-residue-safe-cleanup).
#
# POSIX sh, sourced (never executed) by .aai/scripts/aai-run-tests.sh.
#
# WHY THIS FILE IS SHAPED THE WAY IT IS. On 2026-11-19 an earlier draft of
# this cleanup removed objects from a LIST that one label filter produced. A
# mutation test dropped that filter and the run, which could reach the real
# Docker daemon, deleted every container, volume and network on the machine.
# So no single check here is trusted on its own:
#   1. the listing cannot be made without this run's id as a label filter,
#      and an empty or malformed id is a hard refusal, never "all" (B);
#   2. every listed object is re-inspected BY ID right before its removal and
#      removed only when its label equals the run id exactly AND it was
#      created at or after the recorded run start (A);
#   3. only single-object verbs exist: `rm -f <id>`, `volume rm <name>`,
#      `network rm <id>`; no prune, no --all, no compose (C);
#   4. more than AAI_RESIDUE_CAP candidates removes nothing (D);
#   5. inside a test (AAI_RESIDUE_IN_TEST set) the CLI must be the AAI test
#      stub, recognised by the sentinel line in its first lines, or nothing
#      is called at all (E).
# Any doubt skips the object (reported with the reason) or refuses the whole
# cleanup. Nothing here ever decides the wrapper's exit code; the caller does.
#
# Return codes of aai_residue_cleanup:
#   0  done, or a no-op with a NOTE (no CLI, daemon not answering)
#   2  refused: run id or run start missing or malformed (nothing called)
#   3  refused: test context without the stub CLI (nothing called)
#   4  refused: more candidates than the cap (nothing deleted)
#
# Environment:
#   AAI_RESIDUE_DOCKER   the container CLI (default: docker)
#   AAI_RESIDUE_DRY_RUN  1 = report what would be deleted, delete nothing
#   AAI_RESIDUE_IN_TEST  set (and not 0) = test context, see 5 above

AAI_RESIDUE_CAP=25
AAI_RESIDUE_STUB_SENTINEL='AAI-RESIDUE-STUB-SENTINEL-v1'

aai_residue_say() {
  printf 'AAI-RESIDUE: %s\n' "$*" >&2
}

# aai_residue_runid_valid <id> — 0 only for aai-<10-digit epoch>-<pid>-<8 hex>.
aai_residue_runid_valid() {
  case "${1:-}" in
    '' | *[!a-z0-9-]*) return 1 ;;
  esac
  printf '%s\n' "$1" | grep -Eqx 'aai-[0-9]{10}-[0-9]{1,10}-[0-9a-f]{8}'
}

# aai_residue_runid_new — print a fresh run id.
aai_residue_runid_new() {
  rn_rand=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  case "$rn_rand" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
    *) rn_rand=$(awk 'BEGIN { srand(); printf "%08x", int(rand() * 4294967295) }') ;;
  esac
  printf 'aai-%s-%s-%s\n' "$(date +%s)" "$$" "$rn_rand"
}

# aai_residue_epoch <RFC 3339 time> — print epoch seconds, or fail.
# Accepts 2026-11-19T13:22:22Z, fractional seconds, and a +hh:mm/-hh:mm offset.
aai_residue_epoch() {
  printf '%s\n' "${1:-}" | awk '
    function dfc(y, m, d,   era, yoe, mp, doy, doe) {
      if (m <= 2) y--
      era = int(y / 400); yoe = y - era * 400
      mp = (m > 2) ? m - 3 : m + 9
      doy = int((153 * mp + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe - 719468
    }
    NR > 1 { bad = 1; exit }
    {
      if ($0 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?(Z|[+-][0-9][0-9]:[0-9][0-9])$/) { bad = 1; exit }
      y = substr($0, 1, 4) + 0; mo = substr($0, 6, 2) + 0; d = substr($0, 9, 2) + 0
      h = substr($0, 12, 2) + 0; mi = substr($0, 15, 2) + 0; s = substr($0, 18, 2) + 0
      if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60) { bad = 1; exit }
      off = 0
      z = substr($0, length($0), 1)
      if (z != "Z") {
        tz = substr($0, length($0) - 5, 6)
        off = (substr(tz, 2, 2) * 3600) + (substr(tz, 5, 2) * 60)
        if (substr(tz, 1, 1) == "-") off = -off
      }
      printf "%d\n", dfc(y, mo, d) * 86400 + h * 3600 + mi * 60 + s - off
      ok = 1
    }
    END { if (bad || !ok) exit 1 }
  '
}

# aai_residue_guard — 0 outside a test; inside one, 0 only for the stub CLI.
aai_residue_guard() {
  case "${AAI_RESIDUE_IN_TEST:-0}" in
    '' | 0) return 0 ;;
  esac
  rg_path=$(command -v "$AAI_RESIDUE_DOCKER" 2>/dev/null) || rg_path=''
  if [ -f "$rg_path" ] && sed -n '1,5p' "$rg_path" 2>/dev/null | grep -qF "$AAI_RESIDUE_STUB_SENTINEL"; then
    return 0
  fi
  aai_residue_say "REFUSED - this cleanup runs inside a test (AAI_RESIDUE_IN_TEST=$AAI_RESIDUE_IN_TEST) and the container CLI '${rg_path:-$AAI_RESIDUE_DOCKER}' is not the AAI test stub; a test must never reach a real daemon. Nothing listed, nothing deleted."
  return 3
}

# aai_residue_list <kind> <run id> — the ONLY listing. It builds the label
# filter itself from a validated run id; there is no way to call it without
# one, and an empty or malformed id is refused before any CLI call.
aai_residue_list() {
  if ! aai_residue_runid_valid "${2:-}"; then
    aai_residue_say "REFUSED - listing ${1:-} objects needs this run's id as the label filter, got '${2:-}'; an empty or malformed id would list objects this run does not own."
    # On stdout too, so a caller can tell this refusal from a CLI that
    # itself exits 2 (a daemon error is a NOTE, never a refusal).
    echo 'AAI-RESIDUE-LIST-REFUSED'
    return 2
  fi
  rl_filter="label=aai.test.run=$2"
  case "$1" in
    container) "$AAI_RESIDUE_DOCKER" ps -a -q --no-trunc --filter "$rl_filter" ;;
    volume) "$AAI_RESIDUE_DOCKER" volume ls -q --filter "$rl_filter" ;;
    network) "$AAI_RESIDUE_DOCKER" network ls -q --no-trunc --filter "$rl_filter" ;;
    *)
      aai_residue_say "REFUSED - unknown object kind '${1:-}'."
      return 2
      ;;
  esac
}

# aai_residue_verify <kind> <id> <run id> <run start> — re-inspect ONE object
# by id. 0 = this run's (label equal, created at or after the start); else
# print the reason on stdout and return 1.
aai_residue_verify() {
  # Its own inputs too, not only the caller's: this check must hold even if
  # the run id or start a caller hands it is empty (a missing label inspects
  # as an empty string on real docker, which an empty id would equal).
  aai_residue_runid_valid "${3:-}" || { echo "no valid run id to compare the label with"; return 1; }
  case "${4:-}" in
    '' | *[!0-9]*) echo "no valid run start to compare the creation time with"; return 1 ;;
  esac
  case "$1" in
    container) rv_out=$("$AAI_RESIDUE_DOCKER" container inspect --format '{{index .Config.Labels "aai.test.run"}} {{json .Created}}' "$2" </dev/null 2>/dev/null) ;;
    volume) rv_out=$("$AAI_RESIDUE_DOCKER" volume inspect --format '{{index .Labels "aai.test.run"}} {{json .CreatedAt}}' "$2" </dev/null 2>/dev/null) ;;
    network) rv_out=$("$AAI_RESIDUE_DOCKER" network inspect --format '{{index .Labels "aai.test.run"}} {{json .Created}}' "$2" </dev/null 2>/dev/null) ;;
    *) echo "unknown kind"; return 1 ;;
  esac || { echo "inspect by id failed"; return 1; }
  case "$rv_out" in
    *'
'*) echo "inspect returned more than one line"; return 1 ;;
  esac
  # The creation time is the last field (JSON-quoted, no spaces); the label
  # is everything before it, so `<no value>` and a value with spaces stay whole.
  rv_label=${rv_out% *}
  rv_created=$(printf '%s' "${rv_out##* }" | tr -d '"')
  [ "$rv_label" = "$3" ] || { echo "label aai.test.run is '$rv_label', not this run's id"; return 1; }
  rv_epoch=$(aai_residue_epoch "$rv_created") || { echo "creation time '$rv_created' is unreadable"; return 1; }
  [ "$rv_epoch" -ge "$4" ] || { echo "created $rv_created, before this run started"; return 1; }
  return 0
}

# aai_residue_rm <kind> <id> — the three single-object removals; nothing else
# in this file mutates a daemon.
aai_residue_rm() {
  case "$1" in
    container) "$AAI_RESIDUE_DOCKER" rm -f "$2" </dev/null >/dev/null 2>&1 ;;
    volume) "$AAI_RESIDUE_DOCKER" volume rm "$2" </dev/null >/dev/null 2>&1 ;;
    network) "$AAI_RESIDUE_DOCKER" network rm "$2" </dev/null >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# aai_residue_id_shape <kind> <id> — 0 when the listed token looks like an id
# of that kind (64 hex for containers and networks, a docker volume name).
aai_residue_id_shape() {
  case "$1" in
    container | network)
      printf '%s\n' "$2" | grep -Eqx '[0-9a-f]{64}' ;;
    volume)
      printf '%s\n' "$2" | grep -Eqx '[A-Za-z0-9][A-Za-z0-9_.-]*' ;;
    *) return 1 ;;
  esac
}

# aai_residue_cleanup <run id> <run start epoch> — see the header.
aai_residue_cleanup() {
  rc_id="${1:-}"
  rc_start="${2:-}"
  if ! aai_residue_runid_valid "$rc_id"; then
    aai_residue_say "REFUSED - run id '$rc_id' is empty or malformed; nothing listed, nothing deleted."
    return 2
  fi
  case "$rc_start" in
    '' | *[!0-9]*)
      aai_residue_say "REFUSED - run start '$rc_start' is not an epoch in seconds; nothing listed, nothing deleted."
      return 2
      ;;
  esac
  AAI_RESIDUE_DOCKER="${AAI_RESIDUE_DOCKER:-docker}"
  if ! command -v "$AAI_RESIDUE_DOCKER" >/dev/null 2>&1; then
    aai_residue_say "NOTE - no container CLI ($AAI_RESIDUE_DOCKER) found; no container residue to clean."
    return 0
  fi
  aai_residue_guard || return 3

  rc_cands=''
  rc_n=0
  for rc_kind in container volume network; do
    rc_list=$(aai_residue_list "$rc_kind" "$rc_id" 2>/dev/null)
    rc_st=$?
    if [ "$rc_st" -eq 2 ] && [ "$rc_list" = 'AAI-RESIDUE-LIST-REFUSED' ]; then
      aai_residue_say "REFUSED - the $rc_kind listing refused this run's id; nothing deleted."
      return 2
    fi
    if [ "$rc_st" -ne 0 ]; then
      aai_residue_say "NOTE - the container daemon did not answer the $rc_kind listing (exit $rc_st); nothing deleted."
      return 0
    fi
    while IFS= read -r rc_obj; do
      [ -n "$rc_obj" ] || continue
      rc_cands="$rc_cands$rc_kind $rc_obj
"
      rc_n=$((rc_n + 1))
    done <<EOF
$rc_list
EOF
  done

  if [ "$rc_n" -gt "$AAI_RESIDUE_CAP" ]; then
    aai_residue_say "REFUSED - $rc_n objects carry this run's label, more than the cap of $AAI_RESIDUE_CAP; nothing deleted. Inspect them by hand."
    return 4
  fi

  rc_del=0
  rc_skip=0
  rc_fail=0
  while IFS=' ' read -r rc_kind rc_obj <&3; do
    [ -n "$rc_kind" ] || continue
    if ! aai_residue_id_shape "$rc_kind" "$rc_obj"; then
      aai_residue_say "skipped $rc_kind '$rc_obj' - the listing returned something that is not an id"
      rc_skip=$((rc_skip + 1))
      continue
    fi
    if ! rc_why=$(aai_residue_verify "$rc_kind" "$rc_obj" "$rc_id" "$rc_start"); then
      aai_residue_say "skipped $rc_kind $rc_obj - $rc_why"
      rc_skip=$((rc_skip + 1))
      continue
    fi
    if [ "${AAI_RESIDUE_DRY_RUN:-0}" = "1" ]; then
      aai_residue_say "would delete $rc_kind $rc_obj (label and creation time match this run)"
      rc_del=$((rc_del + 1))
      continue
    fi
    if aai_residue_rm "$rc_kind" "$rc_obj"; then
      aai_residue_say "deleted $rc_kind $rc_obj (label and creation time match this run)"
      rc_del=$((rc_del + 1))
    else
      aai_residue_say "FAILED to delete $rc_kind $rc_obj"
      rc_fail=$((rc_fail + 1))
    fi
  done 3<<EOF
$rc_cands
EOF
  if [ "${AAI_RESIDUE_DRY_RUN:-0}" = "1" ]; then
    aai_residue_say "run $rc_id (dry run): would delete $rc_del, skipped $rc_skip"
  else
    aai_residue_say "run $rc_id: deleted $rc_del, skipped $rc_skip, failed $rc_fail"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# RUN TEMP ROOT AND LEFTOVER PROCESSES (test-residue-files-and-processes).
# The wrapper that owns a run (no inherited AAI_TEST_OWNER) gives its command
# a private temp root, <base>/aai-tr-<8 hex>, holding a marker file, and the
# marker opened on descriptor 9. Afterwards it terminates the processes that
# still hold the marker on descriptor 9 and removes the root. The same rules
# as above: nothing is acted on from a listing alone. A process is re-checked
# by pid right before every signal (uid, start time, not an ancestor, still
# holding the marker on 9, same start time as first seen); the root is
# removed only when its exact name AND its marker prove this run made it.
# Temp entries outside the root are reported, never removed. Inside a test
# nothing runs unless the test names its sandbox (AAI_RESIDUE_SANDBOX); then
# the base must be the sandbox and only pids listed in <sandbox>/pids may be
# signalled. Return codes: 0 done or kept with a reason, 2 refused (bad id,
# start, base, root or marker; nothing touched), 4 refused (more candidates
# than the cap; nothing signalled).

AAI_RESIDUE_PROC_CAP=25

# aai_residue_tree_mode — real outside a test, sandbox inside a test that
# names a sandbox directory, off otherwise.
aai_residue_tree_mode() {
  case "${AAI_RESIDUE_IN_TEST:-0}" in
    '' | 0) echo real; return 0 ;;
  esac
  if [ -n "${AAI_RESIDUE_SANDBOX:-}" ] && [ -d "$AAI_RESIDUE_SANDBOX" ] && [ ! -L "$AAI_RESIDUE_SANDBOX" ]; then
    echo sandbox
  else
    echo off
  fi
}

# aai_residue_suffix <id> — the id's 8-hex tail.
aai_residue_suffix() { printf '%s\n' "${1##*-}"; }

# aai_residue_mtime <file> — modification time in epoch seconds.
aai_residue_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# aai_residue_tmp_create <owner id> <start> <base> — make <base>/aai-tr-<tail>
# (mode 700, never an existing path) with its marker; print the root.
aai_residue_tmp_create() {
  aai_residue_runid_valid "${1:-}" || return 2
  case "${2:-}" in '' | *[!0-9]*) return 2 ;; esac
  case "${3:-}" in /?*) : ;; *) return 2 ;; esac
  tc_new="$3/aai-tr-$(aai_residue_suffix "$1")"
  (umask 077 && mkdir -- "$tc_new") 2>/dev/null || return 1
  printf '%s %s\n' "$1" "$2" > "$tc_new/.aai-test-run" || return 1
  printf '%s\n' "$tc_new"
}

# aai_residue_tmp_verify <id> <start> <base> <root> — 0 only when <root> is
# provably this run's; otherwise print the reason and return 1.
aai_residue_tmp_verify() {
  tv_id="${1:-}"
  tv_start="${2:-}"
  tv_base="${3:-}"
  tv_root="${4:-}"
  aai_residue_runid_valid "$tv_id" || { echo "no valid owner id"; return 1; }
  case "$tv_start" in '' | *[!0-9]*) echo "no valid run start"; return 1 ;; esac
  case "$tv_base" in /?*) : ;; *) echo "base '$tv_base' is not an absolute path other than /"; return 1 ;; esac
  [ "$tv_base" != "${HOME:-/nonexistent-home}" ] || { echo "base '$tv_base' is HOME"; return 1; }
  [ "$(cd "$tv_base" 2>/dev/null && pwd -P)" = "$tv_base" ] || { echo "base '$tv_base' is not its own physical path"; return 1; }
  if [ "$(aai_residue_tree_mode)" = sandbox ]; then
    [ "$(cd "$AAI_RESIDUE_SANDBOX" 2>/dev/null && pwd -P)" = "$tv_base" ] || { echo "base '$tv_base' is not the test sandbox"; return 1; }
  fi
  tv_want="$tv_base/aai-tr-$(aai_residue_suffix "$tv_id")"
  [ "$tv_root" = "$tv_want" ] || { echo "'$tv_root' is not $tv_want"; return 1; } # layer:name
  [ ! -L "$tv_root" ] || { echo "'$tv_root' is a symlink"; return 1; }
  [ -d "$tv_root" ] || { echo "'$tv_root' is not a directory"; return 1; }
  tv_uid=$(ls -ldn -- "$tv_root" 2>/dev/null | awk '{ print $3 }')
  [ "$tv_uid" = "$(id -u)" ] || { echo "'$tv_root' is owned by uid '$tv_uid'"; return 1; }
  tv_mark="$tv_root/.aai-test-run"
  { [ -f "$tv_mark" ] && [ ! -L "$tv_mark" ]; } || { echo "no regular marker file in '$tv_root'"; return 1; }
  tv_line=$(sed -n '1p' "$tv_mark" 2>/dev/null)
  [ "$tv_line" = "$tv_id $tv_start" ] || { echo "the marker names '$tv_line', not this run"; return 1; } # layer:marker
  tv_mt=$(aai_residue_mtime "$tv_mark")
  case "$tv_mt" in '' | *[!0-9]*) echo "the marker's time is unreadable"; return 1 ;; esac
  [ "$tv_mt" -ge "$tv_start" ] || { echo "the marker is older than the run start"; return 1; }
  return 0
}

# aai_residue_tmp_outside <base> <root> — one NOTE naming the temp entries made
# in <base> after the marker, outside the root (and outside any aai-tr- root).
aai_residue_tmp_outside() {
  to_out=$(find "$1" -mindepth 1 -maxdepth 1 -user "$(id -u)" -newer "$2/.aai-test-run" ! -name 'aai-tr-*' -print 2>/dev/null)
  [ -n "$to_out" ] || return 0
  to_n=$(printf '%s\n' "$to_out" | awk 'END { print NR }')
  to_names=$(printf '%s\n' "$to_out" | awk -F/ 'NR <= 5 { printf "%s%s", (NR > 1 ? ", " : ""), $NF }')
  aai_residue_say "NOTE - $to_n temp entr$( [ "$to_n" -eq 1 ] && echo y || echo ies) in $1 changed since this run started (by this run or any other process), outside its temp root, not removed: $to_names"
}

# aai_residue_tmp_cleanup <id> <start> <base> <root> — report what lies
# outside the root, then remove the root when aai_residue_tmp_verify proves it.
aai_residue_tmp_cleanup() {
  if ! aai_residue_runid_valid "${1:-}"; then
    aai_residue_say "REFUSED - owner id '${1:-}' is empty or malformed; no temp root removed."
    return 2
  fi
  case "${2:-}" in
    '' | *[!0-9]*) aai_residue_say "REFUSED - run start '${2:-}' is not an epoch in seconds; no temp root removed."; return 2 ;;
  esac
  if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
    aai_residue_say "REFUSED - empty temp base or root; nothing removed."
    return 2
  fi
  [ "$(aai_residue_tree_mode)" != off ] || return 0
  tc_base="$3"
  tc_root="$4"
  if ! tc_why=$(aai_residue_tmp_verify "$1" "$2" "$tc_base" "$tc_root"); then
    aai_residue_say "kept temp root $tc_root - $tc_why"
    return 0
  fi
  aai_residue_tmp_outside "$tc_base" "$tc_root"
  # rm -rf would descend into a filesystem mounted inside the root (a test's
  # disk image or bind mount) and delete data this run never made: keep the
  # root when anything below it lies on another filesystem.
  tc_all=$(find "$tc_root" 2>/dev/null | awk 'END { print NR }')
  tc_one=$(find "$tc_root" -xdev 2>/dev/null | awk 'END { print NR }')
  if [ -z "$tc_all" ] || [ "$tc_all" != "$tc_one" ]; then
    aai_residue_say "kept temp root $tc_root - another filesystem is mounted inside it; unmount it and remove the root by hand"
    return 0
  fi
  # A bind mount of a directory on the same filesystem keeps the device, so the
  # walk above cannot see it; the mount table can.
  if mount 2>/dev/null | grep -qF " on $tc_root/"; then
    aai_residue_say "kept temp root $tc_root - the mount table lists a mount inside it; unmount it and remove the root by hand"
    return 0
  fi
  if [ "${AAI_RESIDUE_DRY_RUN:-0}" = "1" ]; then
    aai_residue_say "would delete temp root $tc_root (name and marker match this run)"
    return 0
  fi
  rm -rf -- "$tc_root" 2>/dev/null
  [ ! -e "$tc_root" ] || aai_residue_say "FAILED to delete temp root $tc_root"
  return 0
}

# aai_residue_ancestors — this shell's pid and every ancestor's, space-separated.
aai_residue_ancestors() {
  an_p=$$
  an_out=" $$ "
  while [ -n "$an_p" ] && [ "$an_p" -gt 1 ]; do
    an_p=$(ps -o ppid= -p "$an_p" 2>/dev/null | tr -d ' ')
    case "$an_p" in '' | *[!0-9]*) break ;; esac
    an_out="$an_out$an_p "
  done
  printf '%s\n' "$an_out"
}

# aai_residue_etime_s <[[dd-]hh:]mm:ss> — elapsed seconds.
aai_residue_etime_s() {
  printf '%s\n' "$1" | awk '{
    s = $1; d = 0
    if (index(s, "-")) { split(s, a, "-"); d = a[1]; s = a[2] }
    n = split(s, b, ":"); t = 0
    for (i = 1; i <= n; i++) t = t * 60 + b[i]
    printf "%d\n", d * 86400 + t
  }'
}

# aai_residue_marker_ok <marker> — 0 for an existing regular .aai-test-run
# file under an absolute path.
aai_residue_marker_ok() {
  case "${1:-}" in
    /*/.aai-test-run) [ -f "$1" ] && [ ! -L "$1" ] ;;
    *) return 1 ;;
  esac
}

# aai_residue_proc_list <marker> — the ONLY process listing: pids holding the
# marker open on descriptor 9. No marker, no listing (never "every process").
aai_residue_proc_list() {
  if ! aai_residue_marker_ok "${1:-}"; then
    aai_residue_say "REFUSED - listing processes needs this run's marker file, got '${1:-}'; nothing listed."
    echo 'AAI-RESIDUE-LIST-REFUSED'
    return 2
  fi
  "$AAI_RESIDUE_LSOF" -a -d 9 -F p -- "$1" 2>/dev/null | sed -n 's/^p\([0-9][0-9]*\)$/\1/p'
}

# aai_residue_proc_verify <pid> <marker> <start> — re-check ONE process. 0 =
# this run's: print its start time (the identity a signal re-compares); else
# print the reason and return 1.
aai_residue_proc_verify() {
  pv_pid="${1:-}"
  case "$pv_pid" in '' | *[!0-9]* | 0 | 1) echo "pid '$pv_pid' is not a process this run can own"; return 1 ;; esac
  case "${3:-}" in '' | *[!0-9]*) echo "no valid run start"; return 1 ;; esac
  pv_excl=$(aai_residue_ancestors)
  case " $pv_excl " in *" $pv_pid "*) echo "is this wrapper or one of its ancestors"; return 1 ;; esac
  pv_info=$(ps -o uid= -o etime= -o lstart= -p "$pv_pid" 2>/dev/null) || { echo "is gone"; return 1; }
  set -- $pv_info "$2" "$3"
  [ "$#" -ge 4 ] || { echo "is gone"; return 1; }
  pv_uid=$1
  pv_et=$(aai_residue_etime_s "$2")
  shift 2
  pv_m=''
  pv_st=''
  pv_ident=''
  while [ "$#" -gt 2 ]; do pv_ident="${pv_ident:+$pv_ident }$1"; shift; done
  pv_m=$1
  pv_st=$2
  [ "$pv_uid" = "$(id -u)" ] || { echo "belongs to uid $pv_uid"; return 1; }
  case "$pv_et" in '' | *[!0-9]*) echo "its elapsed time is unreadable"; return 1 ;; esac
  [ $(( $(date +%s) - pv_et )) -ge $(( pv_st - 1 )) ] || { echo "started before this run"; return 1; }
  if [ "$(aai_residue_tree_mode)" = sandbox ]; then
    grep -qx "$pv_pid" "$AAI_RESIDUE_SANDBOX/pids" 2>/dev/null || { echo "is not listed in the test sandbox"; return 1; }
  fi
  "$AAI_RESIDUE_LSOF" -a -p "$pv_pid" -d 9 -F f -- "$pv_m" 2>/dev/null | grep -qx 'f9' || { echo "does not hold this run's marker on descriptor 9"; return 1; }
  printf '%s\n' "$pv_ident"
}

# aai_residue_proc_signal <pid> <TERM|KILL> <marker> <start> <identity> —
# re-check, then signal that one pid if its identity is unchanged.
aai_residue_proc_signal() {
  ps_now=$(aai_residue_proc_verify "$1" "$3" "$4") || { echo "$ps_now"; return 1; }
  [ "$ps_now" = "${5:-}" ] || { echo "its start time changed (pid reused)"; return 1; }
  case "$2" in TERM | KILL) : ;; *) echo "unknown signal '$2'"; return 1 ;; esac
  kill -s "$2" "$1" 2>/dev/null || { echo "kill -s $2 failed"; return 1; }
  return 0
}

# aai_residue_proc_cleanup <id> <start> <marker> — terminate the processes
# that still hold this run's marker on descriptor 9.
aai_residue_proc_cleanup() {
  if ! aai_residue_runid_valid "${1:-}"; then
    aai_residue_say "REFUSED - owner id '${1:-}' is empty or malformed; no process signalled."
    return 2
  fi
  case "${2:-}" in
    '' | *[!0-9]*) aai_residue_say "REFUSED - run start '${2:-}' is not an epoch in seconds; no process signalled."; return 2 ;;
  esac
  [ "$(aai_residue_tree_mode)" != off ] || return 0
  if ! aai_residue_marker_ok "${3:-}"; then
    aai_residue_say "REFUSED - listing processes needs this run's marker file, got '${3:-}'; no process signalled."
    return 2
  fi
  pc_line=$(sed -n '1p' "$3" 2>/dev/null)
  if [ "${pc_line%% *}" != "$1" ]; then
    aai_residue_say "REFUSED - the marker '$3' names '${pc_line%% *}', not this run; no process signalled."
    return 2
  fi
  AAI_RESIDUE_LSOF="${AAI_RESIDUE_LSOF:-lsof}"
  if ! command -v "$AAI_RESIDUE_LSOF" >/dev/null 2>&1; then
    aai_residue_say "NOTE - no lsof found; leftover processes of this run were not checked."
    return 0
  fi
  pc_list=$(aai_residue_proc_list "$3")
  case "$pc_list" in *AAI-RESIDUE-LIST-REFUSED*) return 2 ;; esac
  pc_n=0
  for pc_pid in $pc_list; do pc_n=$((pc_n + 1)); done
  [ "$pc_n" -gt 0 ] || return 0
  if [ "$pc_n" -gt "$AAI_RESIDUE_PROC_CAP" ]; then
    aai_residue_say "REFUSED - $pc_n processes hold this run's marker, more than the cap of $AAI_RESIDUE_PROC_CAP; none signalled. Inspect them by hand."
    return 4
  fi
  pc_sent=''
  for pc_pid in $pc_list; do
    if ! pc_id=$(aai_residue_proc_verify "$pc_pid" "$3" "$2"); then
      aai_residue_say "skipped process $pc_pid - $pc_id"
      continue
    fi
    pc_cmd=$(ps -o comm= -p "$pc_pid" 2>/dev/null)
    if [ "${AAI_RESIDUE_DRY_RUN:-0}" = "1" ]; then
      aai_residue_say "would terminate process $pc_pid ($pc_cmd), left by this run"
      continue
    fi
    if pc_why=$(aai_residue_proc_signal "$pc_pid" TERM "$3" "$2" "$pc_id"); then
      aai_residue_say "terminated process $pc_pid ($pc_cmd), left by this run"
      pc_sent="$pc_sent$pc_pid $pc_id
"
    else
      aai_residue_say "skipped process $pc_pid - $pc_why"
    fi
  done
  [ -n "$pc_sent" ] || return 0
  # TERM first; whatever still runs after two seconds gets KILL, re-checked first.
  pc_i=0
  while [ "$pc_i" -lt 20 ]; do
    pc_alive=0
    for pc_pid in $(printf '%s' "$pc_sent" | awk '{ print $1 }'); do kill -0 "$pc_pid" 2>/dev/null && pc_alive=1; done
    [ "$pc_alive" -eq 1 ] || return 0
    sleep 0.1 2>/dev/null || sleep 1
    pc_i=$((pc_i + 1))
  done
  printf '%s' "$pc_sent" | while read -r pc_pid pc_id; do
    [ -n "$pc_pid" ] || continue
    kill -0 "$pc_pid" 2>/dev/null || continue
    if pc_why=$(aai_residue_proc_signal "$pc_pid" KILL "$3" "$2" "$pc_id"); then
      aai_residue_say "killed process $pc_pid, which ignored TERM"
    else
      aai_residue_say "skipped KILL of process $pc_pid - $pc_why"
    fi
  done
  return 0
}
