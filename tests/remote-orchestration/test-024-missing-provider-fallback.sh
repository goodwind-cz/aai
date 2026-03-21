#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo" "$tmp/bin" "$tmp/home/codex"

git -C "$tmp/repo" init >/dev/null
git -C "$tmp/repo" config user.email aai@example.test
git -C "$tmp/repo" config user.name "AAI Test"
echo "fixture" > "$tmp/repo/README.md"
git -C "$tmp/repo" add README.md
git -C "$tmp/repo" commit -m "init" >/dev/null

cat > "$tmp/bin/codex.js" <<'EOF'
console.log("codex 1.0.0");
EOF

bash apps/control-plane/scripts/install-host.sh \
  --repo-path "$tmp/repo" \
  --project-id fixture-install-024 \
  --project-config-path "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
  --db-path "$tmp/runtime/control-plane.db" \
  --summary-path "$tmp/runtime/install-summary.json" \
  --runtime-env-path "$tmp/runtime/control-plane.env" \
  --run-script-path "$tmp/runtime/run-control-plane.sh" \
  --default-branch main \
  --claude-cli-path "$tmp/bin/claude-missing.js" \
  --codex-cli-path "$tmp/bin/codex.js" \
  --codex-session-home "$tmp/home/codex" \
  --skip-deps \
  --skip-build > "$tmp/install.out"

assert_contains "$tmp/install.out" "Claude CLI not found. Install it manually"

run_cli auth status --db "$tmp/runtime/control-plane.db" > "$tmp/status.json"
json_assert_file "$tmp/status.json" "data.sessions.length === 2"
json_assert_file "$tmp/status.json" "data.sessions.some((entry) => entry.provider === 'claude' && entry.status === 'missing')"
json_assert_file "$tmp/status.json" "data.sessions.some((entry) => entry.provider === 'codex' && entry.status === 'ok')"

write_usage_fixture "$tmp/usage.json"
run_cli router choose \
  --db "$tmp/runtime/control-plane.db" \
  --project-config "$tmp/repo/docs/ai/project-overrides/remote-control.yaml" \
  --usage-file "$tmp/usage.json" \
  --phase planning \
  --provider auto > "$tmp/router.json"

json_assert_file "$tmp/router.json" "data.decision.provider === 'codex'"
json_assert_file "$tmp/router.json" "data.decision.reason === 'phase-preference-provider-unavailable-fallback'"
json_assert_file "$tmp/runtime/install-summary.json" "data.providers.claude.installed === false && data.providers.claude.recommended_action !== null"

echo "PASS"
