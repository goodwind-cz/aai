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
const fs = require("node:fs");
const path = require("node:path");
const [command, subcommand, format] = process.argv.slice(2);
const stateFile = path.join(process.env.AAI_PROVIDER_SESSION_HOME || process.env.HOME || ".", "claude-login-state.json");
if (command === "auth" && subcommand === "status" && format === "--json") {
  if (fs.existsSync(stateFile)) {
    console.log(JSON.stringify({
      loggedIn: true,
      email: "switched@example.test",
      subscriptionType: "max"
    }));
  } else {
    console.log(JSON.stringify({ loggedIn: false }));
  }
  process.exit(0);
}
console.error("unsupported");
process.exit(1);
EOF

cat > "$tmp/bin/codex.js" <<'EOF'
const fs = require("node:fs");
const path = require("node:path");
const [command, subcommand] = process.argv.slice(2);
const stateFile = path.join(process.env.AAI_PROVIDER_SESSION_HOME || process.env.HOME || ".", "codex-login-state.txt");
if (command === "login" && subcommand === "status") {
  if (fs.existsSync(stateFile)) {
    console.log("Logged in using ChatGPT");
  } else {
    console.log("Not logged in");
  }
  process.exit(0);
}
console.error("unsupported");
process.exit(1);
EOF

printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$tmp/repo" \
  "fixture-install-032" \
  "main" \
  "5001" \
  "6001" \
  "telegram-token-032" | \
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

assert_contains "$tmp/install.out" "Auth setup/check:   bash $tmp/runtime/run-control-plane.sh auth setup"
assert_contains "$tmp/install.out" "Claude is not ready yet. Finish native CLI auth later"

bash "$tmp/runtime/run-control-plane.sh" auth setup > "$tmp/auth-setup.out" 2>&1

assert_contains "$tmp/auth-setup.out" "SuperTurtle-style rule: init/install only prepares config and runtime."
assert_contains "$tmp/auth-setup.out" "claude.js auth login"
assert_contains "$tmp/auth-setup.out" "Run this native provider login in a separate direct WSL/Linux terminal:"

printf '%s\n' '{"ok":true}' > "$tmp/home/claude/claude-login-state.json"
printf '%s\n' 'ok' > "$tmp/home/codex/codex-login-state.txt"

bash "$tmp/runtime/run-control-plane.sh" auth status > "$tmp/auth-status.out" 2>&1
assert_contains "$tmp/auth-status.out" "Provider auth status"
assert_contains "$tmp/auth-status.out" "- claude: ok"
assert_contains "$tmp/auth-status.out" "- codex: ok"

run_cli auth status --db "$tmp/runtime/control-plane.db" --provider claude > "$tmp/claude-status.json"
json_assert_file "$tmp/claude-status.json" "data.session.status === 'ok' && data.session.account_label === 'switched@example.test (max)'"

run_cli auth status --db "$tmp/runtime/control-plane.db" --provider codex > "$tmp/codex-status.json"
json_assert_file "$tmp/codex-status.json" "data.session.status === 'ok' && data.session.account_label === 'ChatGPT'"

echo "PASS"
