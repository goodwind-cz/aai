#!/usr/bin/env bash
# AAI:CLOSE-GATE -- runs close-reconcile.mjs --check over every pushed range.
# Installed by .aai/scripts/install-pre-commit-hook.sh or .ps1 from .aai/templates/git-hooks/.
# Per pushed ref (stdin: <local ref> <local sha> <remote ref> <remote sha>):
#   - a deletion (all-zero local sha) is skipped;
#   - the default branch (refs/remotes/origin/HEAD, else main) is checked as
#     <remote sha>..<local sha>; a first push (all-zero remote sha) as
#     <local sha>^..<local sha> -- the rule .github/workflows/close-gate.yml
#     applies;
#   - any other ref as merge-base(refs/remotes/<remote>/<default>, local)..local.
# Verdict: `close_gate` read from the PUSHED commit's docs/ai/docs-audit.yaml
# (never the worktree copy). report-only (default): print, exit 0. enforce:
# refuse ONLY a push to the default branch; every other ref stays report-
# only, because WIP pushes legitimately precede the close ceremony.
# See docs/specs/SPEC-0201-spec-shipped-guards-have-no-downstream-trigger.md.

_cg_remote="${1:-origin}"
_cg_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_cg_script="$_cg_root/.aai/scripts/close-reconcile.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "AAI:CLOSE-GATE NOTE: node not found; close gate skipped" >&2
  exit 0
fi
if [ ! -f "$_cg_script" ]; then
  echo "AAI:CLOSE-GATE NOTE: $_cg_script absent; close gate skipped" >&2
  exit 0
fi

# R1 -- default branch: refs/remotes/origin/HEAD with the origin/ prefix
# stripped; else main, and say so.
_cg_default="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
_cg_default="${_cg_default#origin/}"
if [ -z "$_cg_default" ]; then
  _cg_default="main"
  echo "AAI:CLOSE-GATE NOTE: default branch assumed main (refs/remotes/origin/HEAD unset)" >&2
fi
echo "AAI:CLOSE-GATE: default branch $_cg_default (remote $_cg_remote)"

_cg_refused=0
while read -r _cg_lref _cg_local _cg_rref _cg_remote_sha; do
  [ -n "$_cg_lref" ] || continue
  case "$_cg_local" in
    *[!0]*) ;;
    *) echo "AAI:CLOSE-GATE: $_cg_rref is a deletion; nothing to check"; continue ;;
  esac
  # The dial, read from what is being PUSHED (the same "gate what ships,
  # never the worktree copy" discipline the pre-commit body applies).
  _cg_mode="report-only"
  _cg_cfg="$(git show "$_cg_local:docs/ai/docs-audit.yaml" 2>/dev/null || true)"
  if grep -Eq '^close_gate:[[:space:]]*enforce([[:space:]]|$)' <<<"$_cg_cfg"; then
    _cg_mode="enforce"
  fi
  _cg_is_default=0
  if [ "$_cg_rref" = "refs/heads/$_cg_default" ]; then
    _cg_is_default=1
  fi
  if [ "$_cg_is_default" = 1 ]; then
    case "$_cg_remote_sha" in
      *[!0]*) _cg_range="$_cg_remote_sha..$_cg_local" ;;
      *) _cg_range="$_cg_local^..$_cg_local" ;;
    esac
  else
    # Codex P2 on PR #417: git hands the pre-push hook whatever the user typed
    # as the remote, which may be a PATH or a URL rather than a configured
    # name (see the githooks pre-push contract). `refs/remotes/<url>/<default>`
    # is then an impossible ref, the NOTE fires and close-reconcile is skipped
    # -- so `git push <url> HEAD:feat` slipped past the gate this hook exists to
    # provide. Use the named remote when it IS one; otherwise fall back to the
    # origin tracking ref, which is what R1 already resolved the default from.
    if git config --get "remote.$_cg_remote.url" >/dev/null 2>&1; then
      _cg_track="refs/remotes/$_cg_remote/$_cg_default"
    else
      _cg_track="refs/remotes/origin/$_cg_default"
    fi
    _cg_base="$(git merge-base "$_cg_track" "$_cg_local" 2>/dev/null || true)"
    if [ -z "$_cg_base" ]; then
      echo "AAI:CLOSE-GATE NOTE: $_cg_rref skipped -- $_cg_track unresolvable" >&2
      continue
    fi
    _cg_range="$_cg_base..$_cg_local"
  fi
  echo "AAI:CLOSE-GATE: $_cg_rref range=$_cg_range close_gate=$_cg_mode"
  _cg_rc=0
  _cg_out="$(node "$_cg_script" --check --range "$_cg_range" --root "$_cg_root" 2>&1)" || _cg_rc=$?
  printf '%s\n' "$_cg_out"
  if [ "$_cg_rc" -eq 0 ]; then
    continue
  fi
  if [ "$_cg_rc" -eq 2 ]; then
    echo "AAI:CLOSE-GATE NOTE: close-reconcile.mjs could not resolve range $_cg_range (rc=2)" >&2
  fi
  if [ "$_cg_mode" = "enforce" ] && [ "$_cg_is_default" = 1 ]; then
    echo "AAI:CLOSE-GATE refused: push of $_cg_rref (close_gate: enforce, default branch $_cg_default) -- the close ceremony did not run for range $_cg_range (rc=$_cg_rc)." >&2
    echo "  Fix: run the close ceremony (/aai-pr, or the close-work-item.mjs command printed above), or set close_gate: report-only in docs/ai/docs-audit.yaml on the pushed commit." >&2
    _cg_refused=1
  else
    echo "AAI:CLOSE-GATE: reported for $_cg_rref (close_gate=$_cg_mode; push allowed)"
  fi
done
exit "$_cg_refused"
