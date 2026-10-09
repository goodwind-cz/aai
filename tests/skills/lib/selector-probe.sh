#!/usr/bin/env bash
# selector-probe.sh <suite>... — probe each suite with an unknown selector.
#
# Run as `aai-run-tests.sh bash tests/skills/lib/selector-probe.sh <suite>...`:
# the suite files in the arguments make the wrapper classify the run as a
# suite run and build ONE isolated, seeded checkout for the whole loop, instead
# of one per probed suite (hygiene-pack test_094, TEST-473 / SPEC-0181).
#
# Prints exactly one line `PROBE-RC <suite> <rc>` per argument and never stops
# early; the caller decides what a given rc means (rc 0 on an unknown selector
# is the fail-open defect). Output of the probed suite is discarded here.
for rel in "$@"; do
  bash "$rel" no_such_test_xyz >/dev/null 2>&1 && rc=0 || rc=$?
  printf 'PROBE-RC %s %s\n' "$rel" "$rc"
done
exit 0
