#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
# Real git worktree cleanup is intentionally skipped here because recursive
# deletion of Windows-backed worktrees is slow and can outlive the test timeout.
mkdir -p "$tmp/repo"

git -C "$tmp/repo" init >/dev/null
git -C "$tmp/repo" config user.email aai@example.test
git -C "$tmp/repo" config user.name "AAI Test"
echo "hello" > "$tmp/repo/README.md"
git -C "$tmp/repo" add README.md
git -C "$tmp/repo" commit -m "init" >/dev/null

cat > "$tmp/project.yaml" <<'EOF'
project_id: fixture-project
default_branch: main
allowed_docker_profile: worker-default
default_provider_policy: auto
phase_provider_preferences:
  implementation: codex
EOF

cat > "$tmp/worker.js" <<'EOF'
const fs = require("node:fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
fs.writeFileSync(`${manifest.worktree_path}/worker-output.txt`, "worker-ok\n", "utf8");
console.log("worker completed");
EOF

run_cli init --db "$tmp/control-plane.db" >/dev/null
run_cli project register \
  --db "$tmp/control-plane.db" \
  --project-config "$tmp/project.yaml" \
  --repo-path "$tmp/repo" >/dev/null

run_cli run prepare \
  --db "$tmp/control-plane.db" \
  --project-id fixture-project \
  --ref-id PRD-RUN-020 \
  --repo-path "$tmp/repo" \
  --project-config "$tmp/project.yaml" \
  --worktrees-root "$tmp/worktrees" \
  --container-image ghcr.io/example/aai-worker:test \
  --provider auto > "$tmp/prepare.json"

manifest_path="$("$NODE_BIN" -e "const fs=require('node:fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(data.manifest_path)" "$tmp/prepare.json")"
run_id="$("$NODE_BIN" -e "const fs=require('node:fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(data.manifest.run_id)" "$tmp/prepare.json")"
worktree_path="$("$NODE_BIN" -e "const fs=require('node:fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(data.manifest.worktree_path)" "$tmp/prepare.json")"

run_cli run launch \
  --db "$tmp/control-plane.db" \
  --manifest "$manifest_path" \
  --mode process \
  --worker-command "$tmp/worker.js" > "$tmp/launch.json"

json_assert_file "$tmp/launch.json" "data.status === 'done' && data.exit_code === 0"
"$NODE_BIN" -e "const fs = require('node:fs'); process.exit(fs.existsSync(process.argv[1]) ? 0 : 1)" "$worktree_path/worker-output.txt"
"$NODE_BIN" -e "const fs = require('node:fs'); const text = fs.readFileSync(process.argv[1], 'utf8'); process.exit(text.includes('worker-ok') ? 0 : 1)" "$worktree_path/worker-output.txt"

run_cli run inspect --db "$tmp/control-plane.db" --run-id "$run_id" > "$tmp/run.json"
json_assert_file "$tmp/run.json" "data.run.status === 'done' && data.run.log_path.includes('logs')"

echo "PASS"
