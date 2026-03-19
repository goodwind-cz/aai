#!/usr/bin/env bash
set -euo pipefail
for t in tests/remote-orchestration/test-*.sh; do
  bash "$t"
done
