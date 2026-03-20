#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat > "$tmp/bin/claude.js" <<'EOF'
const command = process.argv[2];
if (command === "probe") {
  console.log("claude session ok");
  process.exit(0);
}
if (command === "usage") {
  console.log(JSON.stringify({
    windows: [
      {
        provider: "claude",
        window_label: "5h",
        used_percentage: 33,
        reset_at_utc: "2026-03-20T05:00:00Z",
        collected_at_utc: "2026-03-20T02:00:00Z"
      }
    ]
  }));
  process.exit(0);
}
console.error("unsupported");
process.exit(1);
EOF

run_cli init --db "$tmp/control-plane.db" > /dev/null
run_cli auth probe \
  --db "$tmp/control-plane.db" \
  --provider claude \
  --cli-path "$tmp/bin/claude.js" \
  --session-home "$tmp/home" \
  --probe-args probe \
  --usage-args usage > "$tmp/probe.json"

json_assert_file "$tmp/probe.json" "data.session.status === 'ok' && data.usage_windows[0].provider === 'claude' && data.usage_windows[0].used_percentage === 33"

run_cli auth status --db "$tmp/control-plane.db" --provider claude > "$tmp/status.json"
json_assert_file "$tmp/status.json" "data.session.cli_path.includes('claude.js') && data.session.last_usage_sync_at_utc !== null"

run_cli usage show --db "$tmp/control-plane.db" > "$tmp/usage.json"
json_assert_file "$tmp/usage.json" "data.windows.length === 1 && data.windows[0].reset_at_utc === '2026-03-20T05:00:00Z'"

echo "PASS"
