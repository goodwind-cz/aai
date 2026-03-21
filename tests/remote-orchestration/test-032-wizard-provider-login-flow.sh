#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/keep/repo" "$tmp/login/repo" "$tmp/bin" "$tmp/home/keep-claude" "$tmp/home/login-claude"

git -C "$tmp/keep/repo" init >/dev/null
git -C "$tmp/keep/repo" config user.email aai@example.test
git -C "$tmp/keep/repo" config user.name "AAI Test"
echo "fixture" > "$tmp/keep/repo/README.md"
git -C "$tmp/keep/repo" add README.md
git -C "$tmp/keep/repo" commit -m "init" >/dev/null

git -C "$tmp/login/repo" init >/dev/null
git -C "$tmp/login/repo" config user.email aai@example.test
git -C "$tmp/login/repo" config user.name "AAI Test"
echo "fixture" > "$tmp/login/repo/README.md"
git -C "$tmp/login/repo" add README.md
git -C "$tmp/login/repo" commit -m "init" >/dev/null

cat > "$tmp/bin/claude-keep.js" <<'EOF'
const [command, subcommand, format] = process.argv.slice(2);
if (command === "auth" && subcommand === "status" && format === "--json") {
  console.log(JSON.stringify({
    loggedIn: true,
    email: "current@example.test",
    subscriptionType: "max"
  }));
  process.exit(0);
}
if (command === "auth" && subcommand === "login") {
  console.error("unexpected login");
  process.exit(99);
}
console.log("ok");
EOF

cat > "$tmp/bin/claude-login.js" <<'EOF'
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
if (command === "auth" && subcommand === "login") {
  console.error("Open https://claude.example.test/device");
  console.error("Code: TEST-CODE-123");
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(stateFile, JSON.stringify({ ok: true }));
  process.exit(0);
}
console.log("ok");
EOF

printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$tmp/keep/repo" \
  "fixture-install-032-keep" \
  "main" \
  "5001" \
  "6001" \
  "telegram-token-032-keep" \
  "" | \
  AAI_INSTALL_HOST_TEST_MODE=1 \
  bash apps/control-plane/scripts/install-host.sh \
    --wizard \
    --db-path "$tmp/keep/runtime/control-plane.db" \
    --project-config-path "$tmp/keep/repo/docs/ai/project-overrides/remote-control.yaml" \
    --summary-path "$tmp/keep/runtime/install-summary.json" \
    --runtime-env-path "$tmp/keep/runtime/control-plane.env" \
    --run-script-path "$tmp/keep/runtime/run-control-plane.sh" \
    --claude-cli-path "$tmp/bin/claude-keep.js" \
    --claude-session-home "$tmp/home/keep-claude" \
    --skip-deps \
    --skip-build > "$tmp/keep/install.out" 2>&1

assert_contains "$tmp/keep/install.out" "Provider 'claude' is already logged in as current@example.test (max)."
assert_contains "$tmp/keep/install.out" "Keeping current claude login."
run_cli auth status --db "$tmp/keep/runtime/control-plane.db" --provider claude > "$tmp/keep/status.json"
json_assert_file "$tmp/keep/status.json" "data.session.status === 'ok' && data.session.account_label === 'current@example.test (max)'"

printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$tmp/login/repo" \
  "fixture-install-032-login" \
  "main" \
  "5002" \
  "6002" \
  "telegram-token-032-login" \
  "" | \
  AAI_INSTALL_HOST_TEST_MODE=1 \
  bash apps/control-plane/scripts/install-host.sh \
    --wizard \
    --db-path "$tmp/login/runtime/control-plane.db" \
    --project-config-path "$tmp/login/repo/docs/ai/project-overrides/remote-control.yaml" \
    --summary-path "$tmp/login/runtime/install-summary.json" \
    --runtime-env-path "$tmp/login/runtime/control-plane.env" \
    --run-script-path "$tmp/login/runtime/run-control-plane.sh" \
    --claude-cli-path "$tmp/bin/claude-login.js" \
    --claude-session-home "$tmp/home/login-claude" \
    --skip-deps \
    --skip-build > "$tmp/login/install.out" 2>&1

assert_contains "$tmp/login/install.out" "Provider 'claude' is not ready yet (status: error)."
assert_contains "$tmp/login/install.out" "Press Enter to open interactive login now, or type 's' to skip for now [Enter/s]:"
assert_contains "$tmp/login/install.out" "If the CLI shows a verification link and one-time code, open the link, then return to this same terminal, paste the authentication code here, and press Enter even if no prompt is visible yet."
assert_contains "$tmp/login/install.out" "If the terminal seems stuck after opening the browser, it is usually waiting for that pasted authentication code."
assert_contains "$tmp/login/install.out" "Open https://claude.example.test/device"
assert_contains "$tmp/login/install.out" "Code: TEST-CODE-123"
run_cli auth status --db "$tmp/login/runtime/control-plane.db" --provider claude > "$tmp/login/status.json"
json_assert_file "$tmp/login/status.json" "data.session.status === 'ok' && data.session.account_label === 'switched@example.test (max)'"

echo "PASS"
