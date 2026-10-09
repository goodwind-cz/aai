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
# nonul_is_declared_binary <repo-root> <path> -> exit 0 only when
# .gitattributes DECLARES this path binary.
#
# The title of this guard says TEXT file and always did, but the scan walked
# every tracked path, so the first binary asset ever committed here
# (docs/assets/aai-readme-hero.png, CHANGE-0199) failed it for carrying the
# NUL bytes a PNG is made of. A guard that forbids what its own name exempts
# asserts more than it means.
#
# The exemption is DECLARED, never inferred. The obvious inference — ask git
# whether it calls the blob binary (`git ls-files --eol` reporting `i/-text`)
# — is circular here and was measured to empty this guard completely: git's
# definition of binary IS "contains a NUL in the first 8000 bytes", so a text
# file with a planted NUL is classified binary and walks straight through.
# That version of this function let a planted NUL pass on a scratch fixture.
#
# So a path is exempt only when a human wrote it into .gitattributes as
# `binary`, which is auditable in review and cannot be produced by the act of
# planting the byte. A file that is genuinely an asset gets one line there;
# everything else stays under the guard.
nonul_is_declared_binary() {
  case "$( git -C "$1" check-attr binary -- "$2" 2>/dev/null )" in
    *": binary: set") return 0 ;;
    *) return 1 ;;
  esac
}

# nonul_scan_perfile <repo-root> — the REFERENCE implementation: one node and
# one git check-attr process PER tracked file. Kept, unchanged, so the batch
# scan below can be proven byte-identical to it (hygiene-pack test_136).
nonul_scan_perfile() {
  local _nn_root="$1" _nn_f _nn_rc
  ( cd "$_nn_root" && git ls-files -z ) | while IFS= read -r -d '' _nn_f; do
    [ -f "$_nn_root/$_nn_f" ] || continue
    nonul_is_declared_binary "$_nn_root" "$_nn_f" && continue
    nonul_file_has_nul "$_nn_root/$_nn_f"
    _nn_rc=$?
    [ "$_nn_rc" -eq 0 ] || continue
    printf '%s\n' "$_nn_f"
  done
}

# nonul_scan_batch <repo-root> — the same answer in three processes: one
# git ls-files, one git check-attr --stdin, one node. The node program walks
# the tracked list in order and applies the reference's three skips (not a
# regular file or a link to one; declared binary, i.e. the attribute value
# is exactly set; unreadable) and prints each path whose bytes contain 0.
# Paths are handled as raw bytes so a non-UTF-8 name is printed unchanged.
nonul_scan_batch() {
  local _nn_root="$1" _nn_tmp _nn_rc=0
  _nn_tmp="$(mktemp -d "${TMPDIR:-/tmp}/aai-nonul.XXXXXX")" || { echo "no-nul-guard: could not scan (mktemp failed)" >&2; return 1; }
  case "$_nn_tmp" in /*) ;; *) echo "no-nul-guard: could not scan (mktemp returned a relative path)" >&2; return 1 ;; esac
  # An internal failure must never read as a clean tree: every step below
  # that fails sets _nn_rc, and the function returns it after cleanup.
  if git -C "$_nn_root" ls-files -z > "$_nn_tmp/files" 2>/dev/null \
     && git -C "$_nn_root" check-attr -z --stdin binary < "$_nn_tmp/files" > "$_nn_tmp/attrs" 2>/dev/null; then
    node -e '
      const fs = require("fs");
      const root = Buffer.from(process.argv[1]);
      const split = (b) => {
        const out = []; let s = 0;
        for (let i = 0; i < b.length; i++) if (b[i] === 0) { out.push(b.subarray(s, i)); s = i + 1; }
        return out;
      };
      const files = split(fs.readFileSync(process.argv[2]));
      const attrs = split(fs.readFileSync(process.argv[3]));
      const exempt = new Set();
      for (let i = 0; i + 2 < attrs.length; i += 3) {
        if (attrs[i + 2].toString("latin1") === "set") exempt.add(attrs[i].toString("latin1"));
      }
      const hits = [];
      for (const f of files) {
        const full = Buffer.concat([root, Buffer.from("/"), f]);
        let st;
        try { st = fs.statSync(full); } catch { continue; }
        if (!st.isFile()) continue;
        if (exempt.has(f.toString("latin1"))) continue;
        let buf;
        try { buf = fs.readFileSync(full); } catch { continue; }
        if (buf.includes(0)) hits.push(Buffer.concat([f, Buffer.from("\n")]));
      }
      if (hits.length) fs.writeSync(1, Buffer.concat(hits));
    ' "$_nn_root" "$_nn_tmp/files" "$_nn_tmp/attrs" || _nn_rc=1
  else
    _nn_rc=1
  fi
  rm -rf "$_nn_tmp"
  [ "$_nn_rc" -eq 0 ] || echo "no-nul-guard: could not scan $_nn_root (git ls-files, check-attr or node failed)" >&2
  return "$_nn_rc"
}

nonul_scan() {
  local _nn_root="$1"
  nonul_scan_batch "$_nn_root"
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
  _nn_out="$(nonul_scan "$_nn_root")" || exit 2
  if [ -n "$_nn_out" ]; then
    printf '%s\n' "$_nn_out"
    exit 1
  fi
  exit 0
fi
