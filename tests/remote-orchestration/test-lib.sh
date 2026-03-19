#!/usr/bin/env bash
set -euo pipefail

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
