#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo" "$tmp/bin" "$tmp/home/claude" "$tmp/home/codex"

git -C "$tmp/repo" init >/dev/null
git -C "$tmp/repo" config user.email aai@example.test
git -C "$tmp/repo" config user.name "AAI Test"
echo "fixture" > "$tmp/repo/README.md"
git -C "$tmp/repo" add README.md
git -C "$tmp/repo" commit -m "init" >/dev/null

cat > "$tmp/bin/claude.js" <<'EOF'
console.log("claude 1.0.0");
EOF

cat > "$tmp/bin/codex.js" <<'EOF'
console.log("codex 1.0.0");
EOF

printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$tmp/repo" \
  "fixture-install-025" \
  "main" \
  "1001,1002" \
  "2001" \
  "telegram-token-025" | \
  bash apps/control-plane/scripts/install-host.sh \
    --wizard \
    --db-path "$tmp/runtime/control-plane.db" \
    --project-config-path "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
    --summary-path "$tmp/runtime/install-summary.json" \
    --runtime-env-path "$tmp/runtime/control-plane.env" \
    --run-script-path "$tmp/runtime/run-control-plane.sh" \
    --claude-cli-path "$tmp/bin/claude.js" \
    --codex-cli-path "$tmp/bin/codex.js" \
    --claude-session-home "$tmp/home/claude" \
    --codex-session-home "$tmp/home/codex" \
    --skip-deps \
    --skip-build > "$tmp/install.out" 2>&1

assert_contains "$tmp/install.out" "AAI Remote Orchestration Setup"
assert_contains "$tmp/install.out" "Run command: bash $tmp/runtime/run-control-plane.sh"
assert_file "$tmp/runtime/control-plane.env"
assert_file "$tmp/runtime/run-control-plane.sh"
assert_contains "$tmp/runtime/control-plane.env" "AAI_TELEGRAM_BOT_TOKEN=telegram-token-025"
assert_contains "$tmp/runtime/run-control-plane.sh" "telegram serve"

run_cli project show --db "$tmp/runtime/control-plane.db" --project-id fixture-install-025 > "$tmp/project.json"
json_assert_file "$tmp/project.json" "data.project.allowed_telegram_chat_ids.length === 2 && data.project.allowed_telegram_user_ids.length === 1"
json_assert_file "$tmp/runtime/install-summary.json" "data.project_id === 'fixture-install-025'"

echo "PASS"
