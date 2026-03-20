#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"
usage="$tmp/usage.json"
allowlist="$tmp/mount-allowlist.json"

write_usage_fixture "$usage"
cat > "$allowlist" <<EOF
{
  "allowedRoots": [
    {
      "path": "$tmp",
      "allowReadWrite": true,
      "description": "test workspace"
    }
  ],
  "blockedPatterns": [],
  "nonMainReadOnly": true
}
EOF

mkdir -p "$tmp/docs"
run_cli init --db "$db" > /dev/null
run_cli run prepare \
  --db "$db" \
  --project-id aai-canonical \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --repo-path "$PWD" \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --usage-file "$usage" \
  --worktrees-root "$tmp/worktrees" \
  --container-image ghcr.io/example/aai-worker:preview \
  --provider auto \
  --input-refs docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --output-artifacts docs/ai/reports/validation.log \
  --read-only-mounts "docs|/repo-docs" \
  --extra-mounts "$tmp/docs|/workspace/extra/docs|rw" \
  --mount-allowlist "$allowlist" > "$tmp/out.json"

json_assert_file "$tmp/out.json" "data.manifest.project_id === 'aai-canonical'"
json_assert_file "$tmp/out.json" "data.manifest.mounts.length === 3"
json_assert_file "$tmp/out.json" "data.manifest.mounts[0].read_only === false"
json_assert_file "$tmp/out.json" "data.manifest.mounts[1].read_only === true"
json_assert_file "$tmp/out.json" "data.manifest.mounts[2].target === '/workspace/extra/docs'"
json_assert_file "$tmp/out.json" "data.decision.provider === 'codex'"
assert_file "$tmp/worktrees/aai-canonical-PRD-AAI-REMOTE-ORCHESTRATION-01/run-manifest.json"
echo "PASS"
