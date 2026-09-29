# Fact Index (Factual Memory)

This document contains VERIFIED, low-level facts extracted from code and past analyses.
No narrative, no intent, no workflow.

Rules:
- Each fact must include evidence (file path + symbol, or reproducible grep command).
- If uncertain, mark as UNCERTAIN and list as an open question.
- Prefer small deltas; avoid restating large documents.

## implementation_strategy.ref_id (SPEC-0192)

- `cmdSetStrategy` (`.aai/scripts/state.mjs`) writes `implementation_strategy.ref_id` to `--ref` or else `current_focus.ref_id`. Non-null mismatch: exit 2, message contains `disagrees`, no write. Neither bound: exit 2, message contains `--ref`, no write. `--ref` with unset focus is the CHANGE-0100 intake bind (SPEC-0192 D2 / Spec-AC-07).
- `readStrategy` (`.aai/scripts/lane-gate.mjs`) returns `{ok:false}` when both strategy `ref_id` and `current_focus.ref_id` are non-null and differ — HEAVY lane, not the leftover `selected`.
- `orchestration-dispatch.mjs` treats that same mismatch as `strategy_selected: undecided` (rule 7 / prompts as unbound). Missing `ref_id` is legacy honor.
- `.aai/INTAKE_COMMON.md` IMPLEMENTATION MODE CHOICE records `set-strategy --source intake --ref <this intake's ref_id>` before Planning `set-focus`. A live other focus `disagrees` falls back to intake Notes; PLANNING skips later `set-strategy` only when `implementation_strategy.ref_id` equals this item.

## mutation clone-fidelity mixed EOL (SPEC-0193)

- `buildIsolatedClone` in `.aai/scripts/mutation-run.mjs` overlays tracked
  working-tree bytes (`overlayTrackedWorkingTreeBytes`) after checkout so
  clone-fidelity hashes mixed EOL as they sit on disk, not as `git apply`
  reconstructed them. Evidence: `overlayTrackedWorkingTreeBytes`, TEST-001.

- Root-level untracked paths are skipped on copy and stripped only from the
  D4 comparison copy of `sourceTreeFiles`. The returned map stays unstripped
  so D7 does not report `added: scratch.tmp`. Evidence: TEST-002
  `docs/ai/tdd/spec-mutation-clone-fidelity-windows-eol/mutation-TEST-002.txt`.

- `eolOnlyMismatchNote` in `.aai/scripts/lib/tree-hash.mjs` names changed
  paths whose source vs clone bytes differ only by CR using the token
  `EOL-only difference`. Evidence: TEST-003.
