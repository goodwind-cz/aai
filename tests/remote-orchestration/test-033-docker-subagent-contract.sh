#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo" "$tmp/home/claude"

git -C "$tmp/repo" init >/dev/null
git -C "$tmp/repo" config user.email aai@example.test
git -C "$tmp/repo" config user.name "AAI Test"
echo "hello" > "$tmp/repo/README.md"
git -C "$tmp/repo" add README.md
git -C "$tmp/repo" commit -m "init" >/dev/null

cat > "$tmp/project.yaml" <<'EOF'
project_id: fixture-docker-033
default_branch: main
allowed_docker_profile: worker-default
default_provider_policy: claude
phase_provider_preferences:
  implementation: claude
EOF

cat > "$tmp/claude.js" <<'EOF'
const [command, subcommand, format] = process.argv.slice(2);
if (command === "auth" && subcommand === "status" && format === "--json") {
  console.log(JSON.stringify({
    loggedIn: true,
    email: "docker@example.test",
    subscriptionType: "max"
  }));
  process.exit(0);
}
process.exit(1);
EOF

cat > "$tmp/docker.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${AAI_TEST_DOCKER_ARGS_OUT:?}"
exit 0
EOF
chmod +x "$tmp/docker.sh"

run_cli init --db "$tmp/control-plane.db" > /dev/null
run_cli project register \
  --db "$tmp/control-plane.db" \
  --project-config "$tmp/project.yaml" \
  --repo-path "$tmp/repo" > /dev/null
run_cli queue create \
  --db "$tmp/control-plane.db" \
  --project-id fixture-docker-033 \
  --ref-id PRD-DOCKER-033 \
  --phase implementation \
  --branch aai/docker-033 \
  --provider claude > /dev/null
run_cli auth probe \
  --db "$tmp/control-plane.db" \
  --provider claude \
  --cli-path "$tmp/claude.js" \
  --session-home "$tmp/home/claude" \
  --probe-args auth,status,--json > /dev/null

run_cli run prepare \
  --db "$tmp/control-plane.db" \
  --project-id fixture-docker-033 \
  --ref-id PRD-DOCKER-033 \
  --repo-path "$tmp/repo" \
  --project-config "$tmp/project.yaml" \
  --worktrees-root "$tmp/worktrees" \
  --container-image ghcr.io/example/aai-worker:docker \
  --requirement-refs docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --spec-refs docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --report-refs docs/ai/reports/example.log \
  --provider auto > "$tmp/prepare.json"

manifest_path="$("$NODE_BIN" -e "const fs=require('node:fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(data.manifest_path)" "$tmp/prepare.json")"
handoff_path="$("$NODE_BIN" -e "const fs=require('node:fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(data.manifest.handoff_packet_path)" "$tmp/prepare.json")"

assert_file "$handoff_path"
json_assert_file "$handoff_path" "data.subagent_runtime.provider_session.mounted_session_home === '/var/run/aai/provider-session/claude'"
json_assert_file "$handoff_path" "data.handoff_contract.task_transfer === 'explicit-handoff-packet'"

AAI_TEST_DOCKER_ARGS_OUT="$tmp/docker-args.txt" \
run_cli run launch \
  --db "$tmp/control-plane.db" \
  --manifest "$manifest_path" \
  --mode docker \
  --docker-bin "$tmp/docker.sh" > "$tmp/launch.json"

json_assert_file "$tmp/launch.json" "data.status === 'done' && data.exit_code === 0"
assert_contains "$tmp/docker-args.txt" "-v"
assert_contains "$tmp/docker-args.txt" "$tmp/home/claude:/var/run/aai/provider-session/claude:ro"
assert_contains "$tmp/docker-args.txt" "AAI_PROVIDER_SESSION_HOME=/var/run/aai/provider-session/claude"
assert_contains "$tmp/docker-args.txt" "AAI_HANDOFF_PACKET=/workspace/.aai-handoff.json"
assert_contains "$tmp/docker-args.txt" "AAI_PROVIDER=claude"

echo "PASS"
