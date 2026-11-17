#!/usr/bin/env bash
# Repro for review NB-1 (precommit-blob-read-cost r1): a cat-file --batch header whose size is
# zero-padded and holds an 8 or 9 ("028") is a bash arithmetic error in `big=$((size / 1048576))`.
# In a non-interactive bash that error aborts the WHOLE top-level `if [ "$PCC_LIST" -eq 1 ]; then ... fi`
# (set -e does not fire), so the copy loop and every count cross-check after it are skipped, and
# CHECK 2 silently skips the files that got no copy. A second case shows that an over-long size
# (20 digits, overflowing 64-bit arithmetic) does fail closed.
# Usage: bash repro-...sh <path to pre-commit-checks.sh>   (all fixtures live under a fresh mktemp dir)
set -u
SCRIPT="${1:?path to pre-commit-checks.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$(pwd)/$SCRIPT" ;; esac
REAL_GIT="$(command -v git)"
T="$(mktemp -d "${TMPDIR:-/tmp}/rv-size.XXXXXX")" || exit 2
case "$T" in /*) ;; *) echo "bad tmp"; exit 2 ;; esac
trap 'rm -rf "$T"' EXIT
fx="$T/fx"; mkdir -p "$fx/.aai/scripts"; cp "$SCRIPT" "$fx/.aai/scripts/pre-commit-checks.sh"
git -C "$fx" init -q -b main
printf 'clean a\n' > "$fx/a.txt"
printf '%s = "%s"\n' api_key abcdefghijklmno > "$fx/b.txt"   # exactly 28 bytes
git -C "$fx" add a.txt b.txt
for mode in pad huge; do
  wd="$T/w-$mode"; mkdir -p "$wd"
  if [ "$mode" = pad ]; then repl='\1028'; else repl='\199999999999999999999'; fi
  cat > "$wd/git" <<WRAP
#!/bin/bash
case " \$* " in *" cat-file --batch "*) "$REAL_GIT" "\$@" | sed -E 's/^([0-9a-f]{40} blob )28\$/$repl/'; exit "\${PIPESTATUS[0]}" ;; esac
exec "$REAL_GIT" "\$@"
WRAP
  chmod +x "$wd/git"
  rc=0
  ( [ -n "$fx" ] && cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null PATH="$wd:$PATH" bash .aai/scripts/pre-commit-checks.sh ) > "$T/out" 2> "$T/err" || rc=$?
  echo "== header size rewritten ($mode): exit $rc"
  grep -E 'value too great|Staged content could not|Potential secret|ALL CHECKS PASS|PASS WITH WARNINGS|BLOCKED' "$T/out" "$T/err" | sed 's/\x1b\[[0-9;]*m//g; s#^[^:]*/##'
done
