#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/aai-control-plane-npm-XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo"

git -C "$tmp/repo" init >/dev/null
git -C "$tmp/repo" config user.email aai@example.test
git -C "$tmp/repo" config user.name "AAI Test"
echo "fixture" > "$tmp/repo/README.md"
git -C "$tmp/repo" add README.md
git -C "$tmp/repo" commit -m "init" >/dev/null

cat > "$tmp/remote-control.yaml" <<'EOF'
project_id: fixture-npm-026
default_branch: main
allowed_docker_profile: worker-default
default_provider_policy: auto
phase_provider_preferences:
  planning: claude
  implementation: codex
  validation: codex
EOF

run_npm --silent --prefix apps/control-plane run build >/dev/null
run_npm --silent --prefix apps/control-plane run help > "$tmp/help.txt"
run_npm --silent --prefix apps/control-plane run init -- --db "$tmp/control-plane.db" > "$tmp/init.json"
run_npm --silent --prefix apps/control-plane run project:register -- \
  --db "$tmp/control-plane.db" \
  --project-config "$tmp/remote-control.yaml" \
  --repo-path "$tmp/repo" \
  --chat-ids 1001 \
  --user-ids 2001 > "$tmp/register.json"
run_npm --silent --prefix apps/control-plane run project:show -- \
  --db "$tmp/control-plane.db" \
  --project-id fixture-npm-026 > "$tmp/show.json"
run_npm --silent --prefix apps/control-plane run auth:validate -- --mode cli-subscription > "$tmp/auth.json"
run_npm --silent --prefix apps/control-plane run router:choose -- \
  --db "$tmp/control-plane.db" \
  --project-config "$tmp/remote-control.yaml" \
  --phase planning \
  --provider auto > "$tmp/router.json"
run_npm --silent --prefix apps/control-plane run usage:show -- --db "$tmp/control-plane.db" > "$tmp/usage.json"
run_npm --silent --prefix apps/control-plane run telegram:registry -- \
  --config apps/control-plane/config/command-registry.json > "$tmp/registry.json"
run_npm --silent --prefix apps/control-plane run telegram:interactive > "$tmp/interactive.json"
run_npm --silent --prefix apps/control-plane run telegram:callback -- \
  --data "resume:fixture-npm-026:REF-026" > "$tmp/callback.json"
run_npm --silent --prefix apps/control-plane run mounts:template > "$tmp/mounts.json"
run_npm --silent --prefix apps/control-plane run defaults:show -- \
  --config apps/control-plane/config/command-registry.json > "$tmp/defaults.json"
run_npm --silent --prefix apps/control-plane run policy:show -- \
  --project-config "$tmp/remote-control.yaml" > "$tmp/policy.json"

assert_contains "$tmp/help.txt" "telegram serve"
json_assert_file "$tmp/init.json" "data.ok === true && data.db_path.endsWith('control-plane.db')"
json_assert_file "$tmp/register.json" "data.project.project_id === 'fixture-npm-026'"
json_assert_file "$tmp/show.json" "data.project.allowed_telegram_chat_ids[0] === '1001'"
json_assert_file "$tmp/auth.json" "data.mode === 'cli-subscription'"
json_assert_file "$tmp/router.json" "data.decision.provider === 'claude' && data.phase === 'planning'"
json_assert_file "$tmp/usage.json" "Array.isArray(data.windows)"
json_assert_file "$tmp/registry.json" "typeof data.commands === 'object' && data.commands['/usage'] === 'provider-router'"
json_assert_file "$tmp/interactive.json" "Array.isArray(data.form_fields) && Array.isArray(data.inline_actions)"
json_assert_file "$tmp/callback.json" "data.action === 'resume' && data.target === 'fixture-npm-026'"
json_assert_file "$tmp/mounts.json" "Array.isArray(data.allowedRoots) && data.allowedRoots.length > 0"
json_assert_file "$tmp/defaults.json" "typeof data.commands === 'object' && data.commands['/usage'] === 'provider-router'"
json_assert_file "$tmp/policy.json" "data.project_id === 'fixture-npm-026' && data.phase_provider_preferences.validation === 'codex'"

echo "PASS"
