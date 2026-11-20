#!/bin/sh
# Review repro (code review of test-residue-files-and-processes, 2026-11-20).
# aai_residue_tmp_cleanup removes a verified temp root with plain `rm -rf`,
# which descends into a filesystem mounted inside the root and deletes that
# filesystem's contents (data the run never created). macOS only (hdiutil);
# acts only on a scratch directory and a disk image this script creates.
# Exit 1 = the mounted file was deleted (defect present); 0 = it survived.
set -u
LIB="${1:-.aai/scripts/lib/test-residue.sh}"
case "$LIB" in /*) : ;; *) LIB="$(pwd -P)/$LIB" ;; esac
command -v hdiutil >/dev/null 2>&1 || { echo "SKIP: needs hdiutil (macOS)"; exit 0; }
export DOCKER_HOST=unix:///nonexistent/aai-no-docker.sock CONTAINER_HOST=unix:///nonexistent/aai-no-docker.sock
S=$(mktemp -d "${TMPDIR:-/tmp}/aai-review-repro.XXXXXX") || exit 2
S=$(cd "$S" && pwd -P)
mkdir "$S/sb" "$S/src"
echo precious > "$S/src/precious.txt"
hdiutil create -quiet -srcfolder "$S/src" -volname aairepro -format UDRW "$S/img.dmg" || exit 2
TID='aai-1795089600-4242-0123abcd'
ST=$(( $(date +%s) - 5 ))
R="$S/sb/aai-tr-0123abcd"
mkdir "$R" "$R/mnt"
printf '%s %s\n' "$TID" "$ST" > "$R/.aai-test-run"
hdiutil attach -quiet -nobrowse -mountpoint "$R/mnt" "$S/img.dmg" || exit 2
AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$S/sb" TMPDIR="$S/sb" \
  sh -c '. "$1"; shift; aai_residue_tmp_cleanup "$@"' repro "$LIB" "$TID" "$ST" "$S/sb" "$R"
if [ -f "$R/mnt/precious.txt" ]; then rc=0; echo "OK: the mounted file survived"; else rc=1; echo "DEFECT: the file inside the mounted filesystem was deleted"; fi
hdiutil detach -quiet "$R/mnt"
rm -rf -- "$S"
exit "$rc"
