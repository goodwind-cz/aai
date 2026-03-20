#!/usr/bin/env bash
set -euo pipefail

if command -v node.exe >/dev/null 2>&1; then
  NODE_BIN="node.exe"
else
  NODE_BIN="node"
fi

CLI=("$NODE_BIN" --experimental-strip-types apps/control-plane/src/cli.ts)

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Missing file: $path"; exit 1; }
}

assert_contains() {
  local path="$1"
  local pattern="$2"
  grep -q "$pattern" "$path" || { echo "Missing pattern '$pattern' in $path"; exit 1; }
}

assert_not_contains() {
  local path="$1"
  local pattern="$2"
  if grep -q "$pattern" "$path"; then
    echo "Forbidden pattern '$pattern' in $path"
    exit 1
  fi
}

run_cli() {
  NODE_NO_WARNINGS=1 "${CLI[@]}" "$@"
}

make_tmpdir() {
  mktemp -d .tmp-control-plane-XXXXXX
}

write_usage_fixture() {
  local path="$1"
  cat > "$path" <<'EOF'
{
  "windows": [
    {
      "provider": "claude",
      "window_label": "5h",
      "used_percentage": 22,
      "reset_at_utc": "2026-03-19T23:00:00Z",
      "collected_at_utc": "2026-03-19T18:00:00Z"
    },
    {
      "provider": "codex",
      "window_label": "24h",
      "used_percentage": 61,
      "reset_at_utc": "2026-03-20T00:00:00Z",
      "collected_at_utc": "2026-03-19T18:00:00Z"
    }
  ]
}
EOF
}

json_assert_file() {
  local path="$1"
  local expression="$2"
  NODE_NO_WARNINGS=1 "$NODE_BIN" - "$path" "$expression" <<'EOF'
const fs = require("node:fs");
const [filePath, expression] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(filePath, "utf8"));
const result = Function("data", `return (${expression});`)(data);
if (!result) {
  console.error(`JSON assertion failed: ${expression}`);
  process.exit(1);
}
EOF
}

json_assert_text() {
  local text="$1"
  local expression="$2"
  NODE_NO_WARNINGS=1 "$NODE_BIN" - "$text" "$expression" <<'EOF'
const [raw, expression] = process.argv.slice(2);
const data = JSON.parse(raw);
const result = Function("data", `return (${expression});`)(data);
if (!result) {
  console.error(`JSON assertion failed: ${expression}`);
  process.exit(1);
}
EOF
}
