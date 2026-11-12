#!/usr/bin/env bash
# B1 repro: during validation an opted-in spec's AC rows are still `planned`
# (VALIDATION AC-FLIP DEFERRAL), so the digest is never clean; clean_fail is then
# 0 by construction and PROMOTION turns eligible on 20 all-flagged pairs.
set -euo pipefail
WT=/Users/ales/Projects/aai-worktrees/model-effort-routing
cd "$WT"
echo "--- part 1: digest of this ride's own spec at its validated head"
env -u AAI_ROLE node .aai/scripts/evidence-digest.mjs run --ref model-effort-routing \
  --spec docs/specs/SPEC-DRAFT-spec-model-effort-routing.md | grep '^DIGEST'
echo "--- part 2: 20 flagged digests, each followed by a validation PASS, over 5 refs"
node --input-type=module -e "
import { scoreEvents } from '$WT/.aai/scripts/evidence-digest.mjs';
const ev = [];
for (let i = 0; i < 20; i++) {
  const ref = 'ride-' + (i % 5), head = String(i).padStart(40, 'a');
  ev.push({ event: 'evidence_digest', ref, payload: { head, clean: false, flags: 15 } });
  ev.push({ event: 'check_verdict', ref, payload: { role: 'validation', head, status: 'pass' } });
}
const r = scoreEvents(ev);
console.log('clean_pass=' + r.clean_pass + ' clean_fail=' + r.clean_fail + ' pairs=' + r.pairs + ' rides=' + r.rides + ' reason=' + r.reason);
if (r.reason === 'ok' && r.clean_pass === 0) { console.log('REPRO: PROMOTION eligible with zero clean digests'); process.exit(1); }
"
