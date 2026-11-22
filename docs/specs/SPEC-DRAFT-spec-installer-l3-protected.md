---
id: spec-installer-l3-protected
type: spec
number: null
status: implementing
frozen_sha256: f33dc488e496997fc5bafcf96b4467dccdfd3c3959095517ffd6190c000efaaf
mutation_gate: v1
ceremony_level: 3
links:
  requirement: installer-l3-protected
  rfc: null
  pr: []
  commits: []
---

# The git hook installer and its hook body templates are L3 protected surfaces

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-installer-l3-protected.md
  (follow-up `fu-installer-not-in-l3-protected-paths`, P3; owner decision
  2026-11-22 that the installer is an L3 protected surface).
- Prior scope (closed, not edited):
  docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md (the Node
  installer module, its two launchers and the four single-source hook body
  templates under .aai/templates/git-hooks/).
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 suites through
  `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: the change is list data read live by three consumers; each
  new test is written first and observed failing on the unchanged lists
  (RED), then the lists are edited (GREEN). Not chosen at intake
  (autopilot); Planning chose it.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: the scope edits `.aai/workflow/WORKFLOW.md` (in
  `protected_paths_l3`) and the L3 list itself; the main checkout carries
  other sessions' uncommitted files.
- User decision: worktree (owner directive in the dispatch brief)
- Base ref: origin/main at 077ee649
- Worktree branch/path: chore/installer-l3-protected at
  /Users/ales/Projects/aai-worktrees/installer-l3-protected
- Review required: true
- Review scope (explicit paths): docs/ai/docs-audit.yaml;
  .aai/templates/docs-audit.template.yaml; .aai/workflow/WORKFLOW.md;
  tests/skills/test-aai-suite-select.sh;
  tests/skills/test-aai-ceremony-levels.sh; CHANGELOG.md;
  tests/skills/test-aai-hook-installer-node.sh;
  tests/skills/test-aai-git-hook-templates.sh;
  tests/skills/test-aai-install-parity.sh (added by the D7 amendment);
  docs/issues/CHANGE-DRAFT-installer-l3-protected.md;
  docs/specs/SPEC-DRAFT-spec-installer-l3-protected.md.

## Decisions

- D1 (which files). The three installer files and the four hook body
  templates the installer's `TEMPLATE_FILES` map names
  (`pre-commit-index.sh`, `pre-commit-guard-checks.sh`,
  `reference-transaction.sh`, `pre-push.sh`). A template change reaches
  every installed hook exactly as an installer change does. The two JSON
  files under `.aai/templates/hooks/` are harness settings, not installed by
  this installer, and stay off the list.
- D2 (exact paths, no glob). The CI impact selector matches
  `protected_paths_l3` entries by exact path (select-suites.mjs priority 1);
  a glob entry such as `.aai/templates/git-hooks/*` would be honoured by the
  delta re-check (`protectedMatch`) but not by the selector. Seven explicit
  entries keep the two readers in agreement.
- D3 (order and placement). The seven entries are appended after
  `.aai/scripts/hook-gate.mjs` and before `.aai/workflow/WORKFLOW.md`, as
  one "hook installer" group, in docs/ai/docs-audit.yaml and in
  .aai/templates/docs-audit.template.yaml identically (the sync-seed suite's
  TEST-006 pins the two blocks equal).
- D4 (canon text). WORKFLOW.md "Ceremony levels" gains a `hook installer:`
  bullet naming the three installer files and the template directory's four
  files.
- D5 (consumers checked, unchanged). merge-policy.mjs, lane-gate.mjs and
  hook-gate.mjs do not read the list (merge-policy only names
  docs/ai/docs-audit.yaml as a guarded config); PROFILES.yaml does not carry
  it; select-suites.mjs and lib/recheck.mjs read it live; no test pins the
  list's length (TEST-009 asks for at least four entries). Nothing else
  changes. (Amended by D7: three existing wiring tests did pin the selector's
  routing of these paths.)
- D6 (consumer record). The seed template reaches new installs, so one
  CHANGELOG `## [unreleased]` per-entry heading. Existing downstream
  docs-audit.yaml files are project-owned and are not rewritten; the entry
  says how to add the lines. No product doc: the change adds list entries,
  not a capability.

- D7 (amendment after review r1, B1). Three existing wiring tests expected
  the selector to route installer or template paths to a named suite:
  TEST-3997 (tests/skills/test-aai-hook-installer-node.sh), TEST-3443
  (tests/skills/test-aai-git-hook-templates.sh) and TEST-3571
  (tests/skills/test-aai-install-parity.sh). Once the paths are protected
  the selector prints only `FULL_RUN reason=protected-l3`, so each test now
  asserts that line for the listed paths it names and keeps the suite
  routing check for its other paths, as TEST-3458 already does for
  pre-commit-checks. Added with disclosure (`spec-amend.mjs add`, signoff
  none); the owner's merge direction signs it.

## Acceptance Criteria Mapping

- Spec-AC-01 maps to intake AC-001 (both lists).
- Spec-AC-02 maps to intake AC-002 (the selector, a gate that reads the
  list).
- Spec-AC-03 maps to intake AC-003 (the canon text).
- Spec-AC-04 maps to preservation of the existing wiring tests (D7).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN loadConfig of docs-audit-core.mjs reads this repository, its protected_paths_l3 SHALL contain each of the seven D1 paths, and the protected_paths_l3 block of .aai/templates/docs-audit.template.yaml SHALL contain each of them | planned | — | — | D1, D3 |
| Spec-AC-02 | WHEN select-suites.mjs runs against this repository with a file list holding one of the seven D1 paths, its output SHALL contain FULL_RUN reason=protected-l3 path= followed by that path, for each of the seven | planned | — | — | D2 |
| Spec-AC-04 | WHEN TEST-3997, TEST-3443 and TEST-3571 run against this repository, each SHALL assert FULL_RUN reason=protected-l3 for the installer or template paths it names and SHALL still assert its named suite for its other paths, and each SHALL exit 0 | planned | — | — | D7 |
| Spec-AC-03 | .aai/workflow/WORKFLOW.md SHALL carry a line starting with - hook installer: under its protected surfaces list that names install-pre-commit-hook.mjs, install-pre-commit-hook.sh, install-pre-commit-hook.ps1 and .aai/templates/git-hooks/ | planned | — | — | D4 |

## Implementation plan

- `docs/ai/docs-audit.yaml` and `.aai/templates/docs-audit.template.yaml`:
  the seven entries (D1, D3).
- `.aai/workflow/WORKFLOW.md`: the `hook installer:` bullet (D4).
- `tests/skills/test-aai-suite-select.sh`: TEST-4000 wired into `main()`,
  using `real_select`.
- `tests/skills/test-aai-ceremony-levels.sh`: TEST-4001 and TEST-4002 wired
  into `main()`.
- `CHANGELOG.md`: one `## [unreleased]` heading (D6).
- Seam crossed: the selector and the docs-audit reader parse the same file
  with two different parsers; TEST-4000 and TEST-4001 each go through one.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4001 | Spec-AC-01 | integration | tests/skills/test-aai-ceremony-levels.sh | loadConfig on the repository root lists each of the seven paths; the template's protected_paths_l3 block lists each of them; RED on the unchanged lists | target `.aai/templates/docs-audit.template.yaml`; `sed:s/\n  - \.aai\/templates\/git-hooks\/pre-push\.sh(?=\n)//` drops one template entry and the case must fail | planned |
| TEST-4000 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | the selector on the real repository names each of the seven paths FULL_RUN reason=protected-l3; RED on the unchanged list | target `docs/ai/docs-audit.yaml`; `sed:s/\n  - \.aai\/scripts\/install-pre-commit-hook\.mjs(?=\n)//` drops the module entry and the case must fail | planned |
| TEST-4002 | Spec-AC-03 | integration | tests/skills/test-aai-ceremony-levels.sh | WORKFLOW.md carries the hook installer bullet naming the three installer files and the template directory; RED on the unchanged canon | target `.aai/workflow/WORKFLOW.md`; `sed:s/\n- hook installer:[^\n]*//` drops the bullet's first line and the case must fail | planned |

| TEST-3997 | Spec-AC-04 | integration | tests/skills/test-aai-hook-installer-node.sh | the installer module and both launchers select FULL_RUN reason=protected-l3; the reference twins and test helpers still select aai-hook-installer-node | target `docs/ai/docs-audit.yaml`; `sed:s/\n  - \.aai\/scripts\/install-pre-commit-hook\.ps1(?=\n)//` drops the ps1 entry and the case must fail | planned |
| TEST-3443 | Spec-AC-04 | integration | tests/skills/test-aai-git-hook-templates.sh | the four templates and both launchers select FULL_RUN reason=protected-l3; the vendoring helper and the Pester file still select aai-git-hook-templates | target `docs/ai/docs-audit.yaml`; `sed:s/\n  - \.aai\/templates\/git-hooks\/reference-transaction\.sh(?=\n)//` drops one template entry and the case must fail | planned |
| TEST-3571 | Spec-AC-04 | integration | tests/skills/test-aai-install-parity.sh | both installer launchers select FULL_RUN reason=protected-l3; the sync, update and parity files still select aai-install-parity | target `docs/ai/docs-audit.yaml`; `sed:s/\n  - \.aai\/scripts\/install-pre-commit-hook\.sh(?=\n)//` drops the sh entry and the case must fail | planned |

RED observations: all three tests are written first and run against the
unchanged lists and canon; their failing runs are stored as
`red-<selector>.log` under `docs/ai/tdd/installer-l3-protected/`.
TEST-3997, TEST-3443 and TEST-3571 (D7) existed before; they were red on the
listed paths after the list change (review r1 B1), and their failing
observation for the new assertions is the mutation record.

## Verification

- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh aai-suite-select aai-ceremony-levels aai-sync-seed`
  and (D7) the hook-installer-node, git-hook-templates and install-parity
  suites
- `node .aai/scripts/mutation-run.mjs --spec <this spec>`
- No full sweep: the change is list data plus two suites; the CI impact
  selector escalates the PR to the full run anyway (WORKFLOW.md is
  protected).
- PASS criteria: all TEST-xxx green and every Spec-AC terminal.

## Evidence contract

Per artifact: ref_id `installer-l3-protected`, Spec-AC and TEST-xxx,
command, exit code, evidence path under
`docs/ai/tdd/installer-l3-protected/` (RED and GREEN logs) and the
mutation records, commit SHA once committed.

Registry items closed by this scope: fu-installer-not-in-l3-protected-paths

## Residual risks

- Existing downstream projects keep their own list until they add the
  lines (D6); the CHANGELOG entry tells them how.
- The list remains consult-time policy for Planning and review plus the two
  live readers; no mechanical diff enforcement is added.
