#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo" "$tmp/worktrees"

git -C "$tmp/repo" init >/dev/null
git -C "$tmp/repo" config user.email aai@example.test
git -C "$tmp/repo" config user.name "AAI Test"
echo "fixture" > "$tmp/repo/README.md"
git -C "$tmp/repo" add README.md
git -C "$tmp/repo" commit -m "init" >/dev/null

run_cli init --db "$tmp/control-plane.db" > /dev/null

run_cli run prepare \
  --db "$tmp/control-plane.db" \
  --project-id fixture-parallel-034 \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --task-key backend-diff \
  --parallel-group impl-fanout \
  --repo-path "$tmp/repo" \
  --worktrees-root "$tmp/worktrees" \
  --container-image ghcr.io/example/worker:latest \
  --provider codex > "$tmp/backend.json"

run_cli run prepare \
  --db "$tmp/control-plane.db" \
  --project-id fixture-parallel-034 \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --task-key ui-regression \
  --parallel-group impl-fanout \
  --repo-path "$tmp/repo" \
  --worktrees-root "$tmp/worktrees" \
  --container-image ghcr.io/example/worker:latest \
  --provider codex > "$tmp/ui.json"

json_assert_file "$tmp/backend.json" "data.manifest.task_key === 'backend-diff' && data.manifest.parallel_group === 'impl-fanout'"
json_assert_file "$tmp/ui.json" "data.manifest.task_key === 'ui-regression' && data.manifest.parallel_group === 'impl-fanout'"
backend_worktree="$("$NODE_BIN" -e "const fs=require('node:fs');const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(data.manifest.worktree_path);" "$tmp/backend.json")"
ui_worktree="$("$NODE_BIN" -e "const fs=require('node:fs');const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(data.manifest.worktree_path);" "$tmp/ui.json")"
[[ "$backend_worktree" != "$ui_worktree" ]] || { echo "Expected distinct worktrees for parallel shard tasks"; exit 1; }
assert_file "$tmp/worktrees/fixture-parallel-034-PRD-AAI-REMOTE-ORCHESTRATION-01-backend-diff/run-manifest.json"
assert_file "$tmp/worktrees/fixture-parallel-034-PRD-AAI-REMOTE-ORCHESTRATION-01-ui-regression/run-manifest.json"

json_assert_file "$tmp/worktrees/fixture-parallel-034-PRD-AAI-REMOTE-ORCHESTRATION-01-backend-diff/.aai-handoff.json" "data.task_key === 'backend-diff' && data.parallel_group === 'impl-fanout' && data.runtime_state.parallel_execution.task_key === 'backend-diff'"
json_assert_file "$tmp/worktrees/fixture-parallel-034-PRD-AAI-REMOTE-ORCHESTRATION-01-ui-regression/.aai-handoff.json" "data.task_key === 'ui-regression' && data.parallel_group === 'impl-fanout' && data.runtime_state.parallel_execution.task_key === 'ui-regression'"

echo "PASS"
