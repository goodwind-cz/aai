---
id: downstream-autopilot
type: product
capability: downstream-autopilot
status: current
delivered_by:
  - downstream-rides-ask-no-governance-questions
spec: docs/specs/SPEC-0200-spec-downstream-rides-ask-no-governance-questions.md
updated: 2026-10-01
---

# Downstream autopilot: rides ask nothing until the merge

## What it does

In a project that vendors AAI, `/aai-intake` and `/aai-ship` are the two entry points. A ride taken from them now runs intake, planning, implementation, tests, validation, review and product documentation without asking the owner about two things that belong to the canonical repository's own governance: a capability roadmap the project never wrote, and an owner signature on a specification amendment made mid-ride. The one human checkpoint stays at the merge.

The roadmap file `docs/ai/roadmap.yaml` is the posture switch. A project without that file is ungoverned: the ride gate admits every ride and prints one line saying the roadmap is absent and the gate was not consulted. A project that writes the file opts into the strict gate, and a file that exists but cannot be read or does not fit the roadmap shape still refuses, because a broken roadmap is a defect, not a choice.

A frozen specification that proves incomplete during a ride is amended additively and the amendment is disclosed on the decisions ledger without a signature. The owner is never asked mid-ride. Signatures still owed are listed once, as one line, in the merge checkpoint summary.

## How to use it

Nothing to configure. Run `/aai-ship <need>` (or `/aai-intake <need>` followed by `/aai-loop`) in the vendored project.

To check the posture of a project by hand:

```
node .aai/scripts/ride-select.mjs gate --ref <ref-id> --intake <path to the intake doc>
```

With no `docs/ai/roadmap.yaml` the command exits 0 and prints `ride-select: ADMIT <ref> — roadmap absent (<path>): gate not consulted`. With a roadmap present, the gate behaves as before.

To opt into roadmap governance, write `docs/ai/roadmap.yaml` in the closed shape documented in that file's header in the canonical repository, or let `node .aai/scripts/roadmap-propose.mjs write` create it.

To see signatures owed on a ride's amendments:

```
node .aai/scripts/follow-ups.mjs list --status open --ref <ref-id>
```

## Data model

None. No new file or record shape. The absence of `docs/ai/roadmap.yaml` is read as a state; it is never created by the gate. Amendments keep the existing `spec_amendment` record on `docs/ai/decisions.jsonl` and the existing `fu-amend-<spec id>` tracked item.

## Interfaces and contracts

- `ride-select.mjs gate`: exit 0 with one `ADMIT ... roadmap absent ... gate not consulted` line when the roadmap file is absent; exit 1 `REFUSED` when it is present but unreadable, empty, a directory or malformed; exit 2 on a usage error (missing or non-slug `--ref`, empty `--override`, an `--intake` whose id disagrees with `--ref`) in either posture. No side effect in the absent posture, including under `--override --events`.
- `ride-select.mjs validate` and `next`: unchanged (absent roadmap exits 2 and 1 respectively).
- `/aai-ship` step 1a records the skip in its step 6 merge summary (`ride gate:` line) and lists owed amendment signatures there (`owed sign-offs:` line).
- Canon prose (`SKILL_SHIP`, `SKILL_PR` amendment gate, `AUTONOMOUS_LOOP` 6a, `ROLE_COMMON`): `spec-amend.mjs add --signoff none` is the autonomous default; the owner is never asked mid-ride. `AGENTS.md` operator-contract rule 4 names the roadmap file as the switch.
- Stability: the absent-roadmap admit line and the exit codes above are a contract pinned by `tests/skills/test-aai-ride-select.sh` and `tests/skills/test-aai-downstream-autopilot.sh`.

## Limits and non-goals

- The tests prove the canon sentences exist and the gate behaves; they do not prove that every agent stops asking. The owner's next downstream ride is the real check.
- A broken symlink at the roadmap path reads as absent and is admitted.
- Unattended chaining (`ride-select.mjs next`) still refuses without a roadmap, so an unattended downstream run stops after its first pull request.
- Planning still lists open `fu-amend-*` items; they are informational, not a gate.
- No change to merge authorization, to the roadmap shape, or to the `spec-amend.mjs` record schema.

## Links

- Request: docs/issues/CHANGE-0200-downstream-rides-ask-no-governance-questions.md
- Spec: docs/specs/SPEC-0200-spec-downstream-rides-ask-no-governance-questions.md
- Validation evidence: docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md
