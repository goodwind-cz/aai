#!/usr/bin/env bash
#
# gitignore-block.sh — shared runtime-sidecar .gitignore reconcile
# (spec-aai-update-gitignore-drift-reconcile).
#
# THE FORK THIS CLOSES. aai-bootstrap.sh's ensure_gitignore() and
# aai-sync.sh's gitignore section each carried their OWN copy of this loop,
# with DIFFERENT marker text. A target that got bootstrapped and later synced
# ended up with two "# AAI runtime sidecars" marker lines (measured: `grep -c
# '# AAI runtime sidecars' .gitignore` == 2). This library is the ONE bash
# reconcile both callers source instead of carrying their own append loop.
# `.aai/scripts/aai-sync.ps1` mirrors this in PowerShell, driven by the same
# data file — a shell library cannot be shared across bash and PowerShell, so
# the goal is one implementation PER LANGUAGE over one data file, not one
# implementation total.
#
# SINGLE SOURCE OF DATA: .aai/system/RUNTIME_IGNORE.list. This library never
# hardcodes a pattern; it only reads that file.
#
# Bash 3.2 compatible (the repo's floor — macOS ships 3.2).
#
# CONTRACT
#   aai_gitignore_seed_runtime <gitignore_path> <runtime_list_path> <marker_text> [<dry_run>]
#       Appends every non-blank, non-comment line of <runtime_list_path> that
#       is not already present in <gitignore_path> as an exact line
#       (`grep -qxF`). Writes <marker_text> at most once, and only when
#       <gitignore_path> carries no line starting with the shared marker
#       PREFIX "# AAI runtime sidecars" — detection is by prefix, never by
#       full-string match, so neither caller's legacy marker text can produce
#       a second marker line. Prints one summary line naming the count added
#       (nothing when there is nothing to add). <dry_run> = "1" previews the
#       count without writing, prefixed "[dry-run]". When <runtime_list_path>
#       does not exist, prints a note naming the missing path and returns 0
#       without writing anything and without failing the caller.
#
# A caller whose `source` of this file fails (library absent downstream) must
# itself print an equivalent named-skip note before falling back to no-op —
# this library cannot degrade for a caller that never loaded it.

# CANONICAL COPY of the marker prefix. Cannot be shared across languages, so
# it is also mirrored (as a literal, not a reference) in: aai-sync.ps1's
# detection regex and written marker text, and the caller marker texts in
# aai-bootstrap.sh and aai-sync.sh. tests/skills/test-aai-sync-seed.sh
# TEST-020 pins all 5 copies to THIS constant -- update it first on any
# marker-text change, then update the other 4 to match.
AAI_GITIGNORE_MARKER_PREFIX="# AAI runtime sidecars"

aai_gitignore_seed_runtime() {
  local gitignore_path="$1"
  local runtime_list_path="$2"
  local marker_text="$3"
  local dry_run="${4:-0}"

  if [[ ! -f "$runtime_list_path" ]]; then
    echo "skipped runtime-sidecar gitignore seed: $runtime_list_path missing"
    return 0
  fi

  # Match against a CR-STRIPPED copy of the target, read once: a
  # CRLF-terminated .gitignore (Windows-authored, or CRLF-normalized by a
  # later step) carries a trailing CR on every on-disk line that plain
  # grep -xF never strips, so an already-present LF pattern would never
  # exact-match its own CR-suffixed line on disk and get silently
  # re-appended on every run (Copilot review, PR #326).
  local target_content
  target_content=$(tr -d "\r" < "$gitignore_path" 2>/dev/null)

  local line
  local missing=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    grep -qxF "$line" <<<"$target_content" || missing+=("$line")
  done < "$runtime_list_path"

  [[ ${#missing[@]} -eq 0 ]] && return 0

  if [[ "$dry_run" -eq 1 ]]; then
    echo "[dry-run] $gitignore_path add ${#missing[@]} AAI runtime sidecar pattern(s)"
    return 0
  fi

  {
    echo
    grep -q "^${AAI_GITIGNORE_MARKER_PREFIX}" "$gitignore_path" 2>/dev/null || echo "$marker_text"
    printf '%s\n' "${missing[@]}"
  } >> "$gitignore_path"
  echo "$gitignore_path add ${#missing[@]} AAI runtime sidecar pattern(s)"
}
