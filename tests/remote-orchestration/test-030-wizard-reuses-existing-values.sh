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
const [command, subcommand, format] = process.argv.slice(2);
if (command === "auth" && subcommand === "status" && format === "--json") {
  console.log(JSON.stringify({
    loggedIn: true,
    email: "reuse@example.test",
    subscriptionType: "max"
  }));
  process.exit(0);
}
console.error("unsupported");
process.exit(1);
EOF

cat > "$tmp/bin/codex.js" <<'EOF'
console.log("codex ok");
EOF

bash apps/control-plane/scripts/install-host.sh \
  --repo-path "$tmp/repo" \
  --project-id fixture-install-030 \
  --project-config-path "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
  --db-path "$tmp/runtime/control-plane.db" \
  --summary-path "$tmp/runtime/install-summary.json" \
  --runtime-env-path "$tmp/runtime/control-plane.env" \
  --run-script-path "$tmp/runtime/run-control-plane.sh" \
  --default-branch main \
  --docker-profile worker-special \
  --default-provider-policy claude \
  --planning-provider codex \
  --implementation-provider claude \
  --validation-provider claude \
  --chat-ids 3001,3002 \
  --user-ids 4001 \
  --telegram-bot-token "telegram-token-030" \
  --claude-cli-path "$tmp/bin/claude.js" \
  --codex-cli-path "$tmp/bin/codex.js" \
  --claude-session-home "$tmp/home/claude" \
  --codex-session-home "$tmp/home/codex" \
  --skip-deps \
  --skip-build > /dev/null

printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$tmp/repo" \
  "" \
  "" \
  "" \
  "" \
  "" \
  "overwrite" | \
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

assert_contains "$tmp/install.out" "Project id [fixture-install-030]"
assert_contains "$tmp/install.out" "Allowed Telegram chat ids (csv, optional) [3001,3002]"
assert_contains "$tmp/install.out" "Allowed Telegram user ids (csv, optional) [4001]"
assert_contains "$tmp/install.out" "Telegram bot token (leave blank to add later) [Enter to keep tele...-030]"
assert_contains "$tmp/install.out" "Existing state policy: overwrite"
assert_contains "$tmp/runtime/control-plane.env" "AAI_TELEGRAM_BOT_TOKEN=telegram-token-030"
assert_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "allowed_docker_profile: worker-special"
assert_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "default_provider_policy: claude"
assert_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "planning: codex"
assert_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "implementation: claude"
assert_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "validation: claude"

run_cli project show --db "$tmp/runtime/control-plane.db" --project-id fixture-install-030 > "$tmp/project.json"
json_assert_file "$tmp/project.json" "data.project.allowed_telegram_chat_ids.length === 2 && data.project.allowed_telegram_user_ids.length === 1"

echo "PASS"
