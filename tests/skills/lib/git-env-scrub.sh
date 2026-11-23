# git-env-scrub.sh - the installer suites scrub the caller's git environment
# (docs/specs/SPEC-0310-spec-sync-on-node.md D-GITENV, closes the class of fu-suite-git-env-scrub-class).
#
# WHY: a hook installer run by a test resolves its hooks directory through git, and git reads the caller's
# environment: GIT_CONFIG_COUNT/KEY_n/VALUE_n and GIT_CONFIG_PARAMETERS (what `git -c core.hooksPath=... ` hands to its
# children) can each point core.hooksPath at a directory outside the test's scratch root, and the installer then writes
# its hooks there. Setting GIT_CONFIG_NOSYSTEM and an empty GIT_CONFIG_GLOBAL is not enough.
#
# Pure library when sourced: no set -u/-e, no cd, no test execution, no command substitution that changes directory.
# bash 3.2 compatible (no associative arrays, no mapfile, no ${var^^}).
#
# The scratch root is the first non-empty of AAI_GIT_SCRUB_ROOT, TMP_ROOT and TEST_DIR in the caller; it must be an
# absolute path to an existing directory.

# _aai_scrub_root: prints the caller's scratch root, or fails (prints nothing) when it is empty or relative.
_aai_scrub_root() {
  local root="${AAI_GIT_SCRUB_ROOT:-${TMP_ROOT:-${TEST_DIR:-}}}"
  [[ -n "$root" && "$root" == /* && -d "$root" ]] || return 1
  printf '%s' "$root"
}

# aai_git_scrubbed <cmd...>: runs the command with every variable whose name starts with GIT_ removed, then
# GIT_CONFIG_NOSYSTEM=1 and GIT_CONFIG_GLOBAL an empty file under the caller's scratch root. Refuses (returns 1, runs
# nothing) with no command, or when the scratch root is empty or relative.
aai_git_scrubbed() {
  local root v cfg
  local unset_args=()
  [[ "$#" -gt 0 ]] || { echo "aai_git_scrubbed: no command" >&2; return 1; }
  root="$(_aai_scrub_root)" || { echo "aai_git_scrubbed: the scratch root (AAI_GIT_SCRUB_ROOT, TMP_ROOT or TEST_DIR) is empty or relative" >&2; return 1; }
  cfg="$root/.aai-git-scrub-gitconfig"
  : > "$cfg" || { echo "aai_git_scrubbed: cannot write $cfg" >&2; return 1; }
  while IFS= read -r v; do
    case "$v" in GIT_*) unset_args+=(-u "$v") ;; esac
  done < <(compgen -e)
  env ${unset_args[@]+"${unset_args[@]}"} GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$cfg" "$@"
}

# aai_assert_hooks_under <dir> <root>: the pre-commit hook path git resolves for <dir> (under the scrubbed
# environment) lies under <root> once both are resolved; returns 1 with a line on stderr otherwise. The caller's test
# fails on a non-zero return. An empty or relative <dir> or <root> fails.
aai_assert_hooks_under() {
  local dir="${1:-}" root="${2:-}" hook
  [[ -n "$dir" && "$dir" == /* && -d "$dir" ]] || { echo "aai_assert_hooks_under: the repository directory is empty, relative or missing: '$dir'" >&2; return 1; }
  [[ -n "$root" && "$root" == /* && -d "$root" ]] || { echo "aai_assert_hooks_under: the scratch root is empty, relative or missing: '$root'" >&2; return 1; }
  hook="$(aai_git_scrubbed git -C "$dir" rev-parse --git-path hooks/pre-commit)" || { echo "aai_assert_hooks_under: git could not resolve the hooks path of $dir" >&2; return 1; }
  [[ "$hook" == /* ]] || hook="$dir/$hook"
  node -e '
    const fs = require("fs"); const path = require("path");
    const real = (p) => { let d = path.dirname(path.resolve(p)); const tail = [path.basename(p)];
      for (;;) { try { return path.join(fs.realpathSync(d), ...tail.reverse()); } catch (e) { tail.push(path.basename(d)); const up = path.dirname(d); if (up === d) return ""; d = up; } } };
    const root = fs.realpathSync(process.argv[2]); const hook = real(process.argv[1]);
    process.exit(hook !== "" && (hook === root || hook.startsWith(root.endsWith(path.sep) ? root : root + path.sep)) ? 0 : 1);
  ' "$hook" "$root" || { echo "aai_assert_hooks_under: the hooks path $hook of $dir lies outside the scratch root $root" >&2; return 1; }
}
