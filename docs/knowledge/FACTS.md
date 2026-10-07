# Fact Index (Factual Memory)

- `.aai/scripts/worktree-seed.mjs` seeds only registered linked worktrees in
  the source repository's Git common directory. Its `inventory` uses
  `existingPath` to reject symlink ancestors of installed skill roots;
  `.aai/cache` is excluded, and tracked destination files remain authoritative.
  Evidence: `tests/skills/test-aai-worktree-seed.sh`, TEST-004/006/007.

This document contains VERIFIED, low-level facts extracted from code and past analyses.
No narrative, no intent, no workflow.

Rules:
- Each fact must include evidence (file path + symbol, or reproducible grep command).
- If uncertain, mark as UNCERTAIN and list as an open question.
- Prefer small deltas; avoid restating large documents.

## OpenAI GPT-6 flagship pricing (CHANGE-0197 / CHANGE-0198)

- OpenAI flagship table at `https://developers.openai.com/api/docs/pricing` (source_ref `openai-pricing`) lists **gpt-6-astra**, **gpt-6-sol**, **gpt-6-luna**, and **gpt-6.1-sol** with standard short-context USD/1M input/output (verified 2026-09-30): astra **$10 / $50**, sol and 6.1-sol **$2 / $10**, luna **$0.10 / $0.50**. Long-context and cached-input tiers are on the same page; standard list prices live in `input_usd_per_m` / `output_usd_per_m`.
- **gpt-6.1-astra** has no separate row on that page (only gpt-6-astra and gpt-6.1-sol); omission is noted in `.aai/system/PRICING.yaml` `pricing_meta` (CHANGE-0198).
- `.aai/system/PRICING.yaml` carries these keys; **`.aai/system/MODEL_ROUTING.yaml` remains out of scope** for pricing-only changes.

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

- Root-level untracked paths are copied into the clone and hashed in the D4
  map. D7 uses the same unstripped `sourceTreeFiles`. Omitting them
  false-REDs a suite that needs a new root file. Evidence: TEST-002
  `docs/ai/tdd/spec-mutation-clone-fidelity-windows-eol/mutation-TEST-002.txt`.

- Overlay, untracked copy, and allowlist writers in `buildIsolatedClone`
  walk clone ancestors (`ensureCloneParentDirs`) and unlink the leaf
  (`unlinkIfExists`, lstat never follow) so a leftover HEAD symlink cannot
  write through into ROOT. Evidence: TEST-004, TEST-005.

- `eolOnlyMismatchNote` in `.aai/scripts/lib/tree-hash.mjs` names changed
  paths whose source vs clone bytes differ only by CR using the token
  `EOL-only difference`. Evidence: TEST-003.
