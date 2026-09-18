# no-nul-guard.sh — no TRACKED text file may carry a literal NUL byte
# (spec-close-ceremony-sweep Spec-AC-27).
#
# M7 measured exactly one offender on this tree at planning time:
# `.aai/scripts/spec-amend.mjs` line 253, a byte hiding inside a template
# literal used as a Map-key join separator — invisible to prose review and to
# EVERY `/usr/bin/grep` guard over that file (grep answers "Binary file ...
# matches" and stops looking). That NUL is now written as a JS unicode escape
# sequence instead of the literal byte (same runtime value, zero behavior
# change); this guard is what proves the tree stays that way. NOTE for the
# next editor of THIS file: do not type that escape sequence literally in a
# comment here — writing prose about it that way is exactly how the original
# byte got planted (see docs/knowledge/LEARNED.md, 2026-08-24 entry); spell
# it out in words instead, as this comment now does.
#
# THE PROBE is a portable Node one-liner, not `grep -P` (missing on BSD grep)
# and not perl (no dependency this repo does not already have): read the
# whole file as a Buffer and ask whether byte 0x00 occurs anywhere in it
# (docs/knowledge/LEARNED.md 2026-08-24, "writing prose about a control-
# character escape reliably inserts the literal control character into the
# file" — the same portable probe that entry recommends).
#
# This file is a PURE library when sourced: no `set -u`, no `cd`, no test
# execution. bash-3.2 safe: no `declare -A`, no `mapfile`.

# nonul_file_has_nul <path> -> exit 0 if the file contains a NUL byte, 1 if it
# does not (or cannot be read at all — a missing/unreadable file is not
# itself the NUL-byte class this guard exists for; the caller decides how to
# treat "could not look", separately, per Spec-AC-28's own discipline of
# never letting "could not check" read as "nothing found").
nonul_file_has_nul() {
  node -e '
    const fs = require("fs");
    let buf;
    try { buf = fs.readFileSync(process.argv[1]); } catch { process.exit(2); }
    process.exit(buf.includes(0) ? 0 : 1);
  ' "$1"
}

# nonul_scan <repo-root> — one offending TRACKED path per line (relative to
# <repo-root>), or nothing when the tree is clean. `git ls-files -z` is the
# enumeration Spec-AC-27's own verification text names; NUL-separated so a
# tracked path containing whitespace is still read whole, matching the
# repository's own `git ls-files -z` convention used elsewhere (D3, M7).
nonul_scan() {
  local _nn_root="$1" _nn_f _nn_rc
  ( cd "$_nn_root" && git ls-files -z ) | while IFS= read -r -d '' _nn_f; do
    [ -f "$_nn_root/$_nn_f" ] || continue
    nonul_file_has_nul "$_nn_root/$_nn_f"
    _nn_rc=$?
    [ "$_nn_rc" -eq 0 ] || continue
    printf '%s\n' "$_nn_f"
  done
}

# --check [<repo-root>] — direct CLI entry point (the "guard" Spec-AC-27
# names): prints each offending path and exits 1 when any tracked file
# carries a NUL byte; prints nothing and exits 0 over a clean tree. Defaults
# <repo-root> to this file's own repository (three directories up from
# tests/skills/lib/). The `BASH_SOURCE == $0` guard is load-bearing, same
# reasoning as pipe-grep-q-ratchet.sh's `--record` entry: a suite that
# SOURCES this library from inside one of its own functions must never have
# that function's first argument tested against `--check`.
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ "${1:-}" = "--check" ]; then
  _nn_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _nn_root="${2:-$(cd "$_nn_self_dir/../../.." && pwd)}"
  _nn_out="$(nonul_scan "$_nn_root")"
  if [ -n "$_nn_out" ]; then
    printf '%s\n' "$_nn_out"
    exit 1
  fi
  exit 0
fi
