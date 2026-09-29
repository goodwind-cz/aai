# git-bash-path.sh — in-process Windows <-> Git Bash path translation.
# Sourced by aai-run-tests.sh (POSIX) and, via BASH_ENV, by a child bash
# suite. No cygpath, no wslpath: a missing helper used to exit 127 before
# the project Python interpreter was ever started.
#
# AAI_GIT_BASH_FS_ROOT, when set, prefixes the translated Git Bash path
# inside command_not_found_handle so a Linux test can place a sentinel
# file. Unset in production: the path stays a real Git Bash path (/c/...).

aai_to_git_bash_path() (
  p=$1
  case $p in
    [A-Za-z]:\\*|[A-Za-z]:/*)
      drive=$(printf '%s' "$p" | cut -c1 | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
      rest=$(printf '%s' "$p" | cut -c3-)
      rest=$(printf '%s' "$rest" | tr '\\' '/')
      case $rest in
        /*) ;;
        *) rest="/$rest" ;;
      esac
      printf '/%s%s' "$drive" "$rest"
      ;;
    *)
      printf '%s' "$p"
      ;;
  esac
)

aai_to_windows_path() (
  p=$1
  case $p in
    /[A-Za-z]/*)
      drive=$(printf '%s' "$p" | cut -c2 | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')
      rest=$(printf '%s' "$p" | cut -c4-)
      rest=$(printf '%s' "$rest" | tr '/' '\\')
      printf '%s:\\%s' "$drive" "$rest"
      ;;
    *)
      printf '%s' "$p"
      ;;
  esac
)

# Backslash Windows paths have no forward slash, so bash calls this hook
# instead of exec. A C:/ path contains a slash and is translated only when
# it arrives as a wrapper command argument (see aai-run-tests.sh / .ps1).
command_not_found_handle() {
  _aai_cnf_t=$(aai_to_git_bash_path "$1")
  if [ "$_aai_cnf_t" != "$1" ]; then
    shift
    if [ -n "${AAI_GIT_BASH_FS_ROOT:-}" ]; then
      _aai_cnf_t="${AAI_GIT_BASH_FS_ROOT%/}${_aai_cnf_t}"
    fi
    if [ -e "$_aai_cnf_t" ]; then
      exec "$_aai_cnf_t" "$@"
    fi
  fi
  return 127
}
