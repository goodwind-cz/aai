#!/usr/bin/env bash
# Native integration; requires an already prepared Hermes Python environment.
# AAI_HERMES_SOURCE=/absolute/hermes-agent AAI_HERMES_PYTHON=/absolute/venv/bin/python
# Run through .aai/scripts/aai-run-tests.sh from the AAI repository root.
# Exit 42 means unavailable native evidence, never native PASS. No bootstrapping.
set -euo pipefail
if [[ -z "${AAI_HERMES_SOURCE:-}" || -z "${AAI_HERMES_PYTHON:-}" ]]; then
  echo 'NATIVE UNAVAILABLE: set AAI_HERMES_SOURCE and AAI_HERMES_PYTHON (prepared runtime)'
  exit 42
fi
if [[ "$AAI_HERMES_SOURCE" != /* || "$AAI_HERMES_PYTHON" != /* || ! -x "$AAI_HERMES_PYTHON" || ! -f "$AAI_HERMES_SOURCE/agent/skill_commands.py" ]]; then
  echo 'NATIVE UNAVAILABLE: source and prepared Python must be absolute paths'
  exit 42
fi
export PYTHONDONTWRITEBYTECODE=1
exec "$AAI_HERMES_PYTHON" tests/skills/lib/hermes-skills-smoke.py "$PWD" "$AAI_HERMES_SOURCE"
