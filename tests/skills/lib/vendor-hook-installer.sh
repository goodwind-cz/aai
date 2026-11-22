# vendor_hook_installer <root> <sh|ps1|both>
# (spec-git-hook-bodies-single-source, D-HELPER): the one way a test vendors a hook installer.
# Copies the named installer(s) to <root>/.aai/scripts/, the Node module they launch (and its
# lib/guard-config.mjs and lib/resolve-base.mjs) for every choice, and the whole .aai/templates/git-hooks/
# directory to <root>/.aai/templates/git-hooks/, because an installer reads its templates from
# its own location. Pure library when sourced: no set -u, no cd outside a command substitution,
# no test execution. bash-3.2 safe.
vendor_hook_installer() {
  local root="$1" which="${2:-both}" src
  src="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
  mkdir -p "$root/.aai/scripts/lib" "$root/.aai/templates"
  cp "$src/.aai/scripts/install-pre-commit-hook.mjs" "$root/.aai/scripts/"
  cp "$src/.aai/scripts/lib/guard-config.mjs" "$root/.aai/scripts/lib/"
  cp "$src/.aai/scripts/lib/resolve-base.mjs" "$root/.aai/scripts/lib/"
  case "$which" in
    sh|both) cp "$src/.aai/scripts/install-pre-commit-hook.sh" "$root/.aai/scripts/" ;;
  esac
  case "$which" in
    ps1|both) cp "$src/.aai/scripts/install-pre-commit-hook.ps1" "$root/.aai/scripts/" ;;
  esac
  rm -rf "$root/.aai/templates/git-hooks"
  cp -R "$src/.aai/templates/git-hooks" "$root/.aai/templates/git-hooks"
}
