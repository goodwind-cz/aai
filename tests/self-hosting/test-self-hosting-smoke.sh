#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/target-project"
TMP_ROOT="$(mktemp -d)"
TARGET="$TMP_ROOT/target-project"
INSTALLER_TARGET="$TMP_ROOT/installer-target"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_aai_installed() {
  local target_root="$1"

  test -f "$target_root/.aai/templates/TECHNOLOGY_TEMPLATE.md"
  test -f "$target_root/.aai/system/SELF_HOSTING.md"
  test -f "$target_root/.aai/scripts/aai-sync.sh"
  test -f "$target_root/docs/TECHNOLOGY.md"
  test -f "$target_root/CODEX.md"
  test -f "$target_root/SKILLS.md"
  grep -q "AAI-TEMPLATE: TECHNOLOGY_TEMPLATE v1" "$target_root/docs/TECHNOLOGY.md"
  grep -q "docs/ai/reports/\\*\\*" "$target_root/.gitignore"
  grep -q "!docs/ai/reports/.gitkeep" "$target_root/.gitignore"

  "$ROOT/.aai/scripts/validate-skills.sh" "$target_root" >/dev/null
}

cp -a "$FIXTURE" "$TARGET"
"$ROOT/.aai/scripts/aai-sync.sh" "$TARGET" >/dev/null
assert_aai_installed "$TARGET"

cp -a "$FIXTURE" "$INSTALLER_TARGET"
bash "$ROOT/install.sh" --source-root "$ROOT" --target-root "$INSTALLER_TARGET" >/dev/null
assert_aai_installed "$INSTALLER_TARGET"

echo "PASS: self-hosting smoke"
