#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/sql/001_init.sql"
assert_contains "apps/control-plane/sql/001_init.sql" "CREATE TABLE IF NOT EXISTS projects"
assert_file "apps/control-plane/sql/001_init.sql"
assert_contains "apps/control-plane/sql/001_init.sql" "CREATE TABLE IF NOT EXISTS host_bindings"
echo "PASS"
