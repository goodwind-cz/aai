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

bash apps/control-plane/scripts/install-host.sh \
  --repo-path "$tmp/repo" \
  --project-id fixture-install-023 \
  --project-config-path "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
  --db-path "$tmp/runtime/control-plane.db" \
  --summary-path "$tmp/runtime/install-summary.json" \
  --default-branch main \
  --chat-ids 1001,1002 \
  --user-ids 2001 \
  --claude-cli-path "$tmp/bin/claude.js" \
  --codex-cli-path "$tmp/bin/codex.js" \
  --claude-session-home "$tmp/home/claude" \
  --codex-session-home "$tmp/home/codex" \
  --skip-deps \
  --skip-build > "$tmp/install.out"

assert_contains "$tmp/install.out" "Install complete."
assert_file "$tmp/repo/docs/ai/project-overrides/remote-control.yaml"
assert_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "project_id: fixture-install-023"
assert_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "default_branch: main"
assert_file "$tmp/runtime/install-summary.json"

run_cli project show --db "$tmp/runtime/control-plane.db" --project-id fixture-install-023 > "$tmp/project.json"
json_assert_file "$tmp/project.json" "data.project.local_repo_path.includes('repo') && data.project.allowed_telegram_chat_ids.length === 2"

run_cli auth status --db "$tmp/runtime/control-plane.db" > "$tmp/status.json"
json_assert_file "$tmp/status.json" "data.sessions.length === 2 && data.sessions.every((entry) => entry.status === 'ok')"

json_assert_file "$tmp/runtime/install-summary.json" "data.providers.claude.cli_path.includes('claude.js') && data.providers.codex.cli_path.includes('codex.js')"

echo "PASS"
