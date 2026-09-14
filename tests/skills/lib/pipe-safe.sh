# Pipe-safe drop-in readers for `grep -q`/`grep -m`/`head`
# (remediation round 10, PR #381 — the early-closing-reader class).
#
# WHY THIS EXISTS
#   producer | grep -q pattern
#   producer | grep -m1 pattern
#   producer | head -n1
# Each reader exits at (or before) EOF while the producer may still be
# writing. The writer takes SIGPIPE, the shell reports 141, and under
# `set -o pipefail` that promotes to the PIPELINE's exit status — even
# though the reader found exactly what it was looking for. It is
# load-dependent: harmless while the producer finishes inside one pipe-
# buffer's worth of writes, a 141 the moment scheduling (or payload size)
# lets the reader close the pipe first. CI runs on 1aab60bb reddened this
# way under load (test-aai-docs-audit.sh TEST-003, test-aai-layer-profiles.sh
# TEST-402) though neither the shape nor the assertion changed.
#
# THE FIX
# Consume the producer's stdout to EOF into a temp file BEFORE handing it to
# `grep`/`head`. The producer then never has a reader that goes away early:
# there is no pipe to break. A temp file (not `$(cat)`) so a trailing newline
# in the payload survives byte-for-byte.
#
# `command grep` / `command head` so an aliased/shell-function `grep` (this
# repo's `ugrep` alias in some interactive-adjacent environments) never
# substitutes silently for the real one.
#
# Exit code is preserved exactly as `grep`/`head` would have returned it
# reading the same bytes from a pipe: a producer failure is still visible to
# the CALLER's `set -o pipefail` (the `cat` inside runs in the same
# command substitution / statement as the producer, so its own exit status
# still participates in the pipeline the caller wrote); qgrep/qhead only
# change how the READER consumes bytes, not what the producer's own failure
# does.

# qgrep [grep-args...] — reads stdin to EOF, then greps the captured bytes.
# Usage: producer | qgrep -qF needle   (same argv shape as `grep`, no FILE arg)
qgrep() {
  local _qg_tmp _qg_rc
  _qg_tmp="$(mktemp "${TMPDIR:-/tmp}/aai-qgrep.XXXXXX" 2>/dev/null || mktemp /tmp/aai-qgrep.XXXXXX)" || return 1
  cat > "$_qg_tmp"
  _qg_rc=0
  command grep "$@" "$_qg_tmp" || _qg_rc=$?
  rm -f "$_qg_tmp"
  return "$_qg_rc"
}

# qhead [head-args...] — reads stdin to EOF, then heads the captured bytes.
# Usage: producer | qhead -n1
qhead() {
  local _qh_tmp _qh_rc
  _qh_tmp="$(mktemp "${TMPDIR:-/tmp}/aai-qhead.XXXXXX" 2>/dev/null || mktemp /tmp/aai-qhead.XXXXXX)" || return 1
  cat > "$_qh_tmp"
  _qh_rc=0
  command head "$@" "$_qh_tmp" || _qh_rc=$?
  rm -f "$_qh_tmp"
  return "$_qh_rc"
}
