#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "docs/ai/project-overrides/remote-control.yaml"
assert_contains "docs/ai/project-overrides/remote-control.yaml" "project_id"
assert_file "docs/ai/project-overrides/remote-control.yaml"
assert_contains "docs/ai/project-overrides/remote-control.yaml" "default_provider_policy"
echo "PASS"
