#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/target-project"
TMP_ROOT="$(mktemp -d)"
TARGET="$TMP_ROOT/target-project"
trap 'rm -rf "$TMP_ROOT"' EXIT

cp -a "$FIXTURE" "$TARGET"

"$ROOT/.aai/scripts/aai-sync.sh" "$TARGET" >/dev/null

test -f "$TARGET/.aai/templates/TECHNOLOGY_TEMPLATE.md"
test -f "$TARGET/.aai/system/SELF_HOSTING.md"
test -f "$TARGET/docs/TECHNOLOGY.md"
grep -q "AAI-TEMPLATE: TECHNOLOGY_TEMPLATE v1" "$TARGET/docs/TECHNOLOGY.md"
grep -q "docs/ai/reports/\\*\\*" "$TARGET/.gitignore"
grep -q "!docs/ai/reports/.gitkeep" "$TARGET/.gitignore"

"$ROOT/.aai/scripts/validate-skills.sh" "$TARGET" >/dev/null

echo "PASS: self-hosting smoke"
