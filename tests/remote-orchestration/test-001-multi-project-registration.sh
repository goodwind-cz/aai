#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"
project2="$tmp/project2.yaml"

cat > "$project2" <<'EOF'
project_id: sample-two
default_branch: develop
allowed_docker_profile: worker-default
default_provider_policy: auto
phase_provider_preferences:
  planning: claude
  implementation: codex
  validation: claude
EOF

run_cli init --db "$db" > /dev/null
run_cli project register --db "$db" --project-config docs/ai/project-overrides/remote-control.yaml --repo-path "$PWD" --chat-ids 1001 --user-ids 2001 > /dev/null
run_cli project register --db "$db" --project-config "$project2" --repo-path "$tmp/repo-two" --chat-ids 1002 --user-ids 2002 > /dev/null
run_cli project list --db "$db" > "$tmp/out.json"
json_assert_file "$tmp/out.json" "data.projects.length === 2"
json_assert_file "$tmp/out.json" "data.projects.some((project) => project.project_id === 'aai-canonical')"
json_assert_file "$tmp/out.json" "data.projects.some((project) => project.project_id === 'sample-two')"
echo "PASS"
