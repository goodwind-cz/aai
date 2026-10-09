# assert_companions — the replacement for a suite running another whole suite
# (nested-suite-reruns-duplicate-sweep-time, D4).
#
# WHY THIS EXISTS
#   An outer suite used to prove "the companion suites are green" by running
#   them nested, which paid their cost twice in every sweep. The companion is
#   now declared in tests/skills/suite-map.yaml (`companions:`) and
#   select-suites.mjs selects it whenever the outer suite is selected. This
#   helper pins that declaration: it feeds the outer suite's own test file to
#   the REAL selector against the REAL map and requires a SELECTED or CORE line
#   for every companion named. About 0.1 s instead of a nested suite run.
#
# USAGE (sourced; the caller owns `set -euo pipefail`)
#   assert_companions <outer-suite> <companion>...
#     outer-suite  suite name as in suite-map.yaml, e.g. aai-learned-append
#     returns 0 and prints one INFO line naming the companions when every one
#     is SELECTED or CORE; otherwise prints `MISSING companion <c> for <outer>`
#     per miss and returns 1 (a usage error returns 2).
#
# OVERRIDES (fixtures only)
#   COMPANION_ASSERT_ROOT  repo root fed to --repo-root (default: PROJECT_ROOT)
#   SELECT_SUITES_SCRIPT   selector path (default: PROJECT_ROOT/.aai/scripts/select-suites.mjs)
#
# PURE library: no `set -e`/`set -u`, no `cd`, no pipes into grep/head, no
# test execution. bash-3.2 safe (no declare -A, no mapfile).

assert_companions() {
  local outer="${1:-}" root selector out comp miss=0 names=""
  if [ -z "$outer" ] || [ "$#" -lt 2 ]; then
    echo "assert_companions: usage: assert_companions <outer-suite> <companion>..." >&2
    return 2
  fi
  shift
  root="${COMPANION_ASSERT_ROOT:-${PROJECT_ROOT:-}}"
  if [ -z "$root" ]; then
    echo "assert_companions: no PROJECT_ROOT or COMPANION_ASSERT_ROOT" >&2
    return 2
  fi
  selector="${SELECT_SUITES_SCRIPT:-${PROJECT_ROOT:-$root}/.aai/scripts/select-suites.mjs}"
  out="$(node "$selector" --files-from - --repo-root "$root" <<EOF_PATH
tests/skills/test-${outer}.sh
EOF_PATH
)" || out=""
  for comp in "$@"; do
    case "
$out
" in
      *"
SELECTED $comp "*|*"
CORE $comp "*) names="$names $comp" ;;
      *)
        echo "MISSING companion $comp for $outer"
        miss=1
        ;;
    esac
  done
  if [ "$miss" -ne 0 ]; then
    return 1
  fi
  echo "INFO: $outer companions selected with it:$names (run them when this suite changes)"
  return 0
}
