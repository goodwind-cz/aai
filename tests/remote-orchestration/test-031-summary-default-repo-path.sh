#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/docs/ai/project-overrides" "$tmp/runtime" "$tmp/bin" "$tmp/home/claude" "$tmp/home/codex"

git -C "$tmp/repo" init >/dev/null
git -C "$tmp/repo" config user.email aai@example.test
git -C "$tmp/repo" config user.name "AAI Test"
echo "fixture" > "$tmp/repo/README.md"
git -C "$tmp/repo" add README.md
git -C "$tmp/repo" commit -m "init" >/dev/null

cat > "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" <<'EOF'
project_id: fixture-summary-031
default_branch: main
allowed_docker_profile: worker-default
default_provider_policy: auto
phase_provider_preferences:
  planning: claude
  implementation: codex
  validation: codex
EOF

cat > "$tmp/runtime/install-summary.fixture-summary-031.json" <<EOF
{
  "managed_repo_path": "$tmp/repo",
  "project_config_path": "$tmp/repo/docs/ai/project-overrides/remote-control.yaml",
  "project_id": "fixture-summary-031",
  "default_branch": "main",
  "host_binding": {
    "allowed_telegram_chat_ids": ["3101"],
    "allowed_telegram_user_ids": ["4101"]
  },
  "providers": {
    "claude": {
      "cli_path": "$tmp/bin/claude.js",
      "session_home": "$tmp/home/claude"
    },
    "codex": {
      "cli_path": "$tmp/bin/codex.js",
      "session_home": "$tmp/home/codex"
    }
  }
}
EOF

cat > "$tmp/bin/claude.js" <<'EOF'
const [command, subcommand, format] = process.argv.slice(2);
if (command === "auth" && subcommand === "status" && format === "--json") {
  console.log(JSON.stringify({ loggedIn: true, email: "summary@example.test", subscriptionType: "max" }));
  process.exit(0);
}
process.exit(1);
EOF

cat > "$tmp/bin/codex.js" <<'EOF'
console.log("codex ok");
EOF

printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "" \
  "" \
  "" \
  "" \
  "" \
  "" \
  "overwrite" | \
  bash apps/control-plane/scripts/install-host.sh \
    --wizard \
    --db-path "$tmp/runtime/control-plane.db" \
    --runtime-env-path "$tmp/runtime/control-plane.env" \
    --run-script-path "$tmp/runtime/run-control-plane.sh" \
    --skip-deps \
    --skip-build > "$tmp/install.out" 2>&1

assert_contains "$tmp/install.out" "Managed project repository path [$tmp/repo]"
assert_contains "$tmp/install.out" "Project id [fixture-summary-031]"
assert_contains "$tmp/install.out" "Allowed Telegram chat ids (csv, optional) [3101]"
assert_contains "$tmp/install.out" "Allowed Telegram user ids (csv, optional) [4101]"

echo "PASS"
