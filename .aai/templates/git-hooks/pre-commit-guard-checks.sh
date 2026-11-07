# AAI:GUARD-CHECKS BEGIN
# managed by install-pre-commit-hook; edit outside these markers
# Runs .aai/scripts/pre-commit-checks.sh (secrets detection blocks; the
# doc-numbering guard reports or blocks per docs/ai/docs-audit.yaml) on
# every commit, before the AAI:INDEX-AUTOGEN body below.
_gc_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_gc_script="$_gc_root/.aai/scripts/pre-commit-checks.sh"
if [ -f "$_gc_script" ]; then
  echo "AAI:GUARD-CHECKS: running .aai/scripts/pre-commit-checks.sh"
  _gc_rc=0
  bash "$_gc_script" || _gc_rc=$?
  if [ "$_gc_rc" -ne 0 ]; then
    echo "AAI:GUARD-CHECKS: pre-commit-checks.sh blocked this commit (rc=$_gc_rc)" >&2
    exit "$_gc_rc"
  fi
else
  echo "AAI:GUARD-CHECKS NOTE: .aai/scripts/pre-commit-checks.sh absent; guard checks skipped" >&2
fi
# AAI:GUARD-CHECKS END
