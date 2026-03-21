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
  --project-id fixture-install-028 \
  --project-config-path "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
  --db-path "$tmp/runtime/control-plane.db" \
  --summary-path "$tmp/runtime/install-summary.json" \
  --runtime-env-path "$tmp/runtime/control-plane.env" \
  --run-script-path "$tmp/runtime/run-control-plane.sh" \
  --default-branch main \
  --telegram-bot-token "token-028" \
  --claude-cli-path "$tmp/bin/claude.js" \
  --codex-cli-path "$tmp/bin/codex.js" \
  --claude-session-home "$tmp/home/claude" \
  --codex-session-home "$tmp/home/codex" \
  --skip-deps \
  --skip-build > "$tmp/install-initial.out"

run_cli queue create \
  --db "$tmp/runtime/control-plane.db" \
  --project-id fixture-install-028 \
  --ref-id KEEP-028 \
  --phase planning \
  --branch aai/keep-028 \
  --provider auto > /dev/null

printf '# preserve-marker\n' >> "$tmp/repo/docs/ai/project-overrides/remote-control.yaml"
printf 'PRESERVE_ME=1\n' > "$tmp/runtime/control-plane.env"
printf '#!/usr/bin/env bash\n# preserve-marker\n' > "$tmp/runtime/run-control-plane.sh"
printf '{"marker":"preserve"}\n' > "$tmp/runtime/install-summary.json"

if bash apps/control-plane/scripts/install-host.sh \
  --repo-path "$tmp/repo" \
  --project-id fixture-install-028 \
  --project-config-path "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
  --db-path "$tmp/runtime/control-plane.db" \
  --summary-path "$tmp/runtime/install-summary.json" \
  --runtime-env-path "$tmp/runtime/control-plane.env" \
  --run-script-path "$tmp/runtime/run-control-plane.sh" \
  --default-branch main \
  --telegram-bot-token "token-028" \
  --claude-cli-path "$tmp/bin/claude.js" \
  --codex-cli-path "$tmp/bin/codex.js" \
  --claude-session-home "$tmp/home/claude" \
  --codex-session-home "$tmp/home/codex" \
  --skip-deps \
  --skip-build > "$tmp/install-no-policy.out" 2>&1; then
  echo "install-host.sh should fail without explicit policy when state exists"
  exit 1
fi

assert_contains "$tmp/install-no-policy.out" "Existing control-plane state detected"

bash apps/control-plane/scripts/install-host.sh \
  --repo-path "$tmp/repo" \
  --project-id fixture-install-028 \
  --project-config-path "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
  --db-path "$tmp/runtime/control-plane.db" \
  --summary-path "$tmp/runtime/install-summary.json" \
  --runtime-env-path "$tmp/runtime/control-plane.env" \
  --run-script-path "$tmp/runtime/run-control-plane.sh" \
  --default-branch main \
  --telegram-bot-token "token-028" \
  --claude-cli-path "$tmp/bin/claude.js" \
  --codex-cli-path "$tmp/bin/codex.js" \
  --claude-session-home "$tmp/home/claude" \
  --codex-session-home "$tmp/home/codex" \
  --skip-deps \
  --skip-build \
  --preserve-existing > "$tmp/install-preserve.out"

assert_contains "$tmp/install-preserve.out" "Existing state policy: preserve"
assert_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "preserve-marker"
assert_contains "$tmp/runtime/control-plane.env" "PRESERVE_ME=1"
assert_contains "$tmp/runtime/run-control-plane.sh" "preserve-marker"
assert_contains "$tmp/runtime/install-summary.json" "\"marker\":\"preserve\""

run_cli queue status --db "$tmp/runtime/control-plane.db" --project-id fixture-install-028 > "$tmp/preserve-status.json"
json_assert_file "$tmp/preserve-status.json" "data.work_items.length === 1 && data.work_items[0].ref_id === 'KEEP-028'"

bash apps/control-plane/scripts/install-host.sh \
  --repo-path "$tmp/repo" \
  --project-id fixture-install-028 \
  --project-config-path "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
  --db-path "$tmp/runtime/control-plane.db" \
  --summary-path "$tmp/runtime/install-summary.json" \
  --runtime-env-path "$tmp/runtime/control-plane.env" \
  --run-script-path "$tmp/runtime/run-control-plane.sh" \
  --default-branch main \
  --telegram-bot-token "token-028" \
  --claude-cli-path "$tmp/bin/claude.js" \
  --codex-cli-path "$tmp/bin/codex.js" \
  --claude-session-home "$tmp/home/claude" \
  --codex-session-home "$tmp/home/codex" \
  --skip-deps \
  --skip-build \
  --overwrite-existing > "$tmp/install-overwrite.out"

assert_contains "$tmp/install-overwrite.out" "Existing state policy: overwrite"
assert_not_contains "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" "preserve-marker"
assert_contains "$tmp/runtime/control-plane.env" "AAI_TELEGRAM_BOT_TOKEN=token-028"
assert_not_contains "$tmp/runtime/run-control-plane.sh" "preserve-marker"
json_assert_file "$tmp/runtime/install-summary.json" "data.project_id === 'fixture-install-028'"

run_cli queue status --db "$tmp/runtime/control-plane.db" --project-id fixture-install-028 > "$tmp/overwrite-status.json"
json_assert_file "$tmp/overwrite-status.json" "Array.isArray(data.work_items) && data.work_items.length === 0"

echo "PASS"
