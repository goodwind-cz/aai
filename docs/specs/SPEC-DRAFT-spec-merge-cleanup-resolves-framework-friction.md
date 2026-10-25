---
id: spec-merge-cleanup-resolves-framework-friction
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: ff3ab61bfe9f03a72aeac444427fb8d51ad6292028d4017626bb9cf2df2042f9
ceremony_level: 2
links:
  requirement: merge-cleanup-resolves-framework-friction
  rfc: null
  pr: []
  commits: []
---

# Merge cleanup resolves framework-owned friction instead of handing it to the owner

SPEC-FROZEN: true

## Links

- Requirement: [CHANGE-0227](../issues/CHANGE-0227-merge-cleanup-resolves-framework-friction.md)
  (owner-approved, numbered by #500 at `fb171891`), AC-001 to AC-008.
- Capability: `directed-merge-and-post-merge-cleanup`
  ([product doc](../product/directed-merge-and-post-merge-cleanup.md)).
- Prior art: [SPEC-0218](SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md)
  (engine, exit contract, archive-first), [SPEC-0221](SPEC-0221-spec-merge-cleanup-submodule-worktree.md)
  (submodule proof), [SPEC-0222](SPEC-0222-spec-merge-cleanup-delete-remote-branch.md)
  (remote branch by lease), [SPEC-0223](SPEC-0223-spec-merge-cleanup-ride-leftovers.md)
  (CHANGE-0210: ride roadmap entry, ledger tails), [SPEC-0225](SPEC-0225-spec-merge-cleanup-dead-steps.md)
  (removed the never-used `archive-drafts` step), [SPEC-0244](SPEC-0244-spec-ride-state-handoff-to-worktree.md)
  (reconcile-origin).
- Engine: `.aai/scripts/merge-cleanup.mjs`. Canon: `.aai/SKILL_MERGE.prompt.md`.
  Suites: `tests/skills/test-aai-merge-cleanup.sh`, `tests/skills/aai-merge-cleanup.Tests.ps1`.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib, bash and PowerShell blocks).

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy

- Strategy: tdd
- Rationale: every Spec-AC changes what the cleanup engine does to user
  bytes, refs and worktrees (archive-first removal, base sync, keep-and-continue)
  or what the merge skill tells the agent to do; each has a refusal or
  interruption path. The intake asks for a full TDD recommendation. Each
  gating row stores a RED observed on `fb171891` and carries a mutation record.
  The prompt, AGENTS rule, ledger, profile and suite-map edits are pinned by
  mutation-gated inspection rows in the same TDD run.

## Isolation and review

- Worktree recommendation: recommended.
- Worktree rationale: the scope rewrites the cleanup engine's exit contract
  and amends about a dozen existing suite arms; the ride already runs in its
  own linked worktree, which keeps the shared main checkout (where every
  cleanup of this week ran) out of the fixtures' reach.
- User decision: worktree (recorded before Planning).
- Base ref: fb171891 (main).
- Worktree branch/path: change/merge-cleanup-resolves-framework-friction at /private/tmp/aai-merge-friction
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/merge-cleanup.mjs .aai/scripts/lib/merge-outcomes.mjs
  .aai/SKILL_MERGE.prompt.md .aai/AGENTS.md .aai/system/PROFILES.yaml
  tests/skills/test-aai-merge-cleanup.sh tests/skills/aai-merge-cleanup.Tests.ps1
  tests/skills/suite-map.yaml tests/skills/lib/prompt-diet-ledger.sh
  tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-pr-preflight.sh
  docs/specs/SPEC-DRAFT-spec-merge-cleanup-resolves-framework-friction.md
  docs/issues/CHANGE-0227-merge-cleanup-resolves-framework-friction.md
  (after LOOP COMPLETE the ship step adds docs/product/directed-merge-and-post-merge-cleanup.md
  and CHANGELOG.md and re-sets the review scope; an existing suite outside the list is
  edited only when one of its pins names a literal this scope changes, and the hand-off names it).

## Problem, measured

- Six merges this session (PRs #495 to #500) ended with
  `retained docs/issues/CHANGE-DRAFT-merge-cleanup-resolves-framework-friction.md [leftover_draft]`
  and `remaining: ... unexpected leftover draft; owner decision`. The draft was
  an untracked pre-numbering copy in the main checkout of the intake that #500
  numbered CHANGE-0227. The owner was asked by hand each time. Root cause:
  SPEC-0225 removed the `archive-drafts` step as never used, so
  `classifyDrafts` (merge-cleanup.mjs:265) now retains every untracked
  `docs/**/<TYPE>-DRAFT-*.md` without comparing it with anything.
- PR #485 (merge `89e7150e`): cleanup refused `REFUSE overlap docs/ai/roadmap.yaml`.
  The archived bytes (`docs/ai/archive/merge-cleanup/pr-485/overlap-resolution/`
  in the main checkout) show the local roadmap had two appended pair blocks,
  `smaller-node-core-and-faster-feedback` (active) and
  `selected-ci-scheduling-foundation` (active); the merge commit added the same
  two blocks with the child `done`. The diff local versus incoming is one line
  (`status: active` versus `status: done`). Two causes: (a) the merged
  CHANGE-0214 had `links.pr: []`, so `deliveredDoneDocs` (merge-cleanup.mjs:245)
  found no merged ref and `roadmapRideOnly` returned false at its first test;
  (b) even with the child ref known, the parent block is not the ride's entry,
  so `stripRideEntries` leaves it and the D3 comparison fails.
- `.aai/SKILL_MERGE.prompt.md` step 2 says "Exit 3 or 4: relay the `REFUSE` or
  `STOPPED` line verbatim and stop", step 1 says "Exit 3: relay the `REFUSE`
  line and stop", step 3 says "Divergent drafts stay with the owner". The agent
  followed that text: it ended its turn and waited for "Pokracuj".
- Today a worktree that holds one uncommitted edit refuses the whole cleanup
  (exit 3): the main checkout is not synced, the remote branch is not deleted,
  although neither step touches the worktree.

## Scope and design

### D1. Three classes, decided by one table in a new library

A new module `.aai/scripts/lib/merge-outcomes.mjs` (Node stdlib, pure, no I/O)
holds `OUTCOME_TABLE`: one entry per reason the engine can emit, built with
four helpers. The engine decides every refusal, stop and retained item by
looking the reason up; it never branches on prose. The helpers:

- `kept('<step>')` — class `auto`. The protected object is left exactly as it
  is, the named step (and its dependents, D6) is recorded `retained`, and the
  run continues with every other step. No question.
- `retry('<fallback>')` — class `auto` while the retry budget allows (D7):
  the step stopped mid-way (exit 4) or a read failed before any write (exit 3),
  and the next run is expected to get further. When the budget is spent the
  same reason becomes the fallback class: `decide` with options `retry` and
  `skip_step` (recommended `skip_step`), or `external` with the table's action.
- `decide([options], '<recommended>')` — class `decide`: two or three options
  from the closed set `keep_local`, `take_incoming`, `keep`, `archive_remove`,
  `retry`, `skip_step`, `direct_new_head`, `stop`, one recommended, each with a
  plain `effect` sentence and the item's `question`.
- `external('<action>')` — class `external`: the engine cannot proceed and the
  owner can; the `action` names the smallest thing to do.

An entry is one helper, or `{ plan: <helper>, step: <helper> }` when one
reason means different things before any write of its step (plan phase:
planChecks and the derivation at the start of a handler) and after a write in
that step began (step phase: a concurrent change caught by the late re-check).
The engine passes the phase; it never guesses it.

A condition that is resolved inside the run (D3 to D5) is class `auto` with
state `resolved` and emits no question. The rule for choosing `kept` over
`decide`: when the only alternatives are "keep the protected object and finish
the rest" and "stop", keeping dominates (a later run finishes the kept step once
its cause is gone), so it is not a decision.

### D2. The table (every reason the engine emits today, plus the new ones)

| Reason (engine) | Where | Class | Options or action |
|---|---|---|---|
| no_direction | preflight | external | say /aai-merge with the PR yourself in this session |
| not_open | preflight | external | reopen the PR on the platform or name another PR |
| draft | preflight | external | mark the PR ready for review, then direct the merge again |
| head_changed | preflight | decide | direct_new_head (recommended), stop |
| sweep_missing | preflight | external | the review sweep must be re-recorded for this head; the gate line is quoted |
| review_unresolved | preflight | external | the open review threads must be answered and resolved; their count is quoted |
| platform_mismatch | both | external | the re-record command the engine already prints |
| platform_generic | both | external | the manual step the adapter names |
| gh_read_failed, az_read_failed | both | apply: retry, then external; preflight: external on the first run | check the platform CLI login and network |
| gh_read_invalid, az_read_invalid, repo_mismatch, az_arg_unsafe | both | external | the adapter detail |
| no_origin, bad_base_name, bad_head_name | apply | external | the detail |
| not_merged | apply | external | merge the PR first (/aai-merge on the open PR) |
| fetch_failed, merge_commit_not_on_base | apply | retry, then external | check that git fetch of the base works |
| origin_not_on_base, base_diverged, ledger_rewritten, pending_unreadable, pending_diverged, overlap_staged (a staged local change the merge touches), untracked_not_file (a directory or other non-file where the merge adds a file) | sync-base | kept | main checkout left as it is; plan mode prints a keep line with the reason |
| overlap (not resolved by D4) | sync-base | decide | keep_local (recommended), take_incoming |
| untracked_collision (bytes differ) | sync-base | decide | take_incoming (recommended), keep_local |
| sync_failed, ledger_merge_failed, index_regen_failed | sync-base | retry, then decide | retry, skip_step (recommended) |
| worktree_missing, cwd_inside_target, worktree_dirty, tip_mismatch, session_locked, ledger_unaligned, submodule_dirty, submodule_unpushed, submodule_stash, submodule_no_remote, submodule_unverifiable | remove-worktree | plan phase: kept; step phase: retry, then decide | kept: worktree, its branch and its files left as they are; decide: retry, skip_step (recommended) |
| worktree_remove_failed | remove-worktree | retry, then decide | retry, skip_step (recommended) |
| tip_mismatch (no worktree) | delete-branch | kept | local branch left as it is |
| branch_moved | delete-branch | retry, then decide | retry, skip_step (recommended) |
| remote_bad_name, remote_fork, remote_unknown, remote_is_base, remote_moved, remote_has_dependents, remote_delete_rejected | delete-branch | kept | origin branch left as it is |
| reconcile_refused (any ride-handoff REFUSE) | reconcile-origin | kept | origin STATE left as it is |
| reconcile_origin_failed | reconcile-origin | retry, then decide | retry, skip_step (recommended) |
| superseded_draft (new, D3) | drafts | auto resolved | archived, then removed |
| divergent_draft (new, D3) | drafts | decide | keep (recommended), archive_remove |
| archive_failed (new, D3) | any archive | retry, then decide | retry, skip_step (recommended) |

Usage errors (exit 2) are not classified. The merge-phase exits of
`platform.mjs merge` (completion_pending, head_race_lost) keep their existing
SKILL_MERGE step 1 text (pinned by test-aai-platform-adapter.sh TEST-076) and
are out of scope.

### D3. Draft copies: compare with the merged counterpart

`classifyDrafts` keeps its candidate set (untracked, under `docs/`, basename
matching `DRAFT_BASENAME_RE`) and, for each draft `docs/<dir>/<TYPE>-DRAFT-<slug>.md`,
looks in the tree of `refs/remotes/origin/<base>` for numbered docs
`docs/<dir>/<TYPE>-<digits>-<slug>.md`.

- Counterpart: exactly one such doc whose frontmatter `id` equals the draft's
  frontmatter `id`. Zero or several: the draft is `untouched` (reported in a
  new `untouched` list, no outcome, no question; it is another item's work in
  progress, which the current engine wrongly reports as an owner decision).
- Comparison (`supersededDraft` in the library): the draft text and the
  counterpart blob text, each with the frontmatter keys in
  `DRAFT_LIFECYCLE_KEYS` (`number`, `number_reserved`, `status`, `links`,
  the `links` key with its indented children) removed, and with every
  occurrence of the draft stem `<TYPE>-DRAFT-<slug>` in the draft replaced by
  the counterpart stem `<TYPE>-<digits>-<slug>` (the substitution
  `allocate-doc-number.mjs` performs). Equal strings: `superseded_draft`.
  Different: `divergent_draft`. The comparison compares those two strings; it
  does not judge whether the difference matters.
- `superseded_draft`: `archiveFile` (reason `superseded_draft`, under
  `pr-<n>/drafts/<path>`), then the draft is unlinked only when the archive
  copy reads back byte-equal (the existing check). Runs in the `plan`-time
  derivation and the `apply` step `archive-drafts` reintroduced between `plan`
  and `archive-runtime` (one step id added to `STEP_IDS`; the journal reader
  already tolerates historical ids, SPEC-0225 TEST-056).
- `divergent_draft`: decide `keep` (recommended: the draft stays, and is not
  asked about again while its bytes stay the same) or `archive_remove`
  (archived as above, then removed).
- `archive_failed`: any `archiveFile` that throws (copy, read-back mismatch,
  or the test seam `AAI_MERGE_CLEANUP_FAIL_ARCHIVE=<original>`) stops the step
  with `STOPPED archive_failed <original>` (exit 4) and the source is never
  removed. Today a read-back mismatch is an uncaught throw (exit 1).

### D4. Roadmap overlap: a local change already represented in the incoming roadmap

`roadmapRideOnly` becomes `roadmapRepresented`. A library function splits a
roadmap text into entries: each pair block (`  - capability: <c>` and the
following lines indented four spaces or more) and each two-space wave line
(`  - <slug>`), keyed by capability or slug; everything else is `other`. Let
K be the keys whose entry text differs between the local file and the HEAD
blob (added, removed or changed). The local change is represented when:

1. stripping the entries of K from the local text and from the HEAD blob gives
   equal strings (no change outside entries), and
2. for every key in K, one of: (a) the incoming blob has an entry with the
   same key whose text equals the local entry text; (b) the key is a merged
   ref (D5) and the incoming blob has a pair block for it; (c) the key is a
   wave line that the local file removed and the key is a merged ref (the
   existing ship-append case).

Represented: archive the local file (reason `pre_sync_local_state`, the
existing path) and take the incoming blob; no outcome. Not represented: the
`overlap` outcome (decide), its `detail` naming each unrepresented key, and
`unproven <key>` for a key whose doc changed in the merge but whose identity
D5 does not prove.

Generated projections: `docs/ai/overview.html`, `docs/ai/overview-data.json`,
`docs/ai/factory-report.html` and `docs/ai/factory-report-data.json`
(`GENERATED_PROJECTIONS`) are handled like `docs/INDEX.md` today when the
merge changed them: the local bytes are archived (`pre_sync_local_state`) and
the incoming blob is taken; no regeneration runs. Any other dirty file the
merge changed is `overlap` (decide).

Decision effects for `overlap`: `keep_local` records the choice and the step
`sync-base` is `retained` (main checkout untouched, D6 dependents apply);
`take_incoming` archives the local file and syncs as for a represented change.
For `untracked_collision`: `take_incoming` archives the untracked file then
removes it before the fast-forward (restored from the saved bytes if the
fast-forward fails, as `removeEqual` does today); `keep_local` retains the step.

### D5. Identity when links.pr is missing

`doneDocsBetween` keeps its links.pr test and adds one proof. A doc changed
by the merge commit (`mc^1..mc`, added or modified), type not `spec`, status
`done` at `mc`, is a merged ref when either:

- `linkedPrs` names this PR (today's rule, proof `links_pr`), or
- the raw `links.pr` value is absent, null or an empty list, AND the doc's
  status at `mc^1` is not `done` (or the doc is absent there): proof
  `merge_commit`.

A `links.pr` that names only other PRs, or a doc already `done` before the
merge, is not proven. The engine never writes `links.pr` or any other field of
a merged doc. The proven refs feed D4, D3 and `reconcile-origin` (SPEC-0244)
unchanged.

### D6. Keep-and-continue: the step dependencies

| When this step is retained or waits for a decision | Then |
|---|---|
| sync-base | reconcile-origin is retained (`sync_not_done`); remove-worktree keeps a worktree that has ledger tails (`ledger_tails_wait_for_sync`), so no ride line is appended to an unsynced main checkout |
| remove-worktree | delete-branch keeps the local branch (`kept_with_worktree`); the origin branch is still deleted by lease against the merged head (SPEC-0222) |
| archive-drafts | nothing else |

A `kept` reason raised in the step phase (for example `pending_diverged`
inside sync-base) also records the step retained and continues; only `retry`
and `decide` stop a step mid-way.

Every step keeps its own proofs: a kept step never weakens another step's
check. A pre-mutation verdict that today refuses the whole run (planChecks)
now records the kept step and continues. Exit codes after this change:
0 every step done, no-op or kept; 6 (new) the run reached the end and at
least one `decide` item waits; 4 a step stopped mid-way; 3 refused before any
write to the working tree, refs or index (only `external` gate reasons and a
`retry` read failure); 2 usage; 10 preflight ready. This is a breaking change
of the exit contract (Constitution article 5) and is documented in the
engine HELP, the skill and the product doc.

### D7. Bounded retries and progress

The engine appends one record per `apply` run to
`<git common dir>/aai-merge-cleanup/pr-<n>/attempts.jsonl`: exit code, the
ids of `retry` outcomes, and a fingerprint, the sha256 of: origin HEAD, the
journal `done` lines without timestamps, the manifest line count, and the
sorted outcome ids. The file lives in the git dir so an exit-3 run changes no
working-tree file (fixtures' `world_digest` excludes `.git`).
`nextAttempt(records, fingerprint)` in the library: a reason may be `retry`
when the trailing run of records that ended with a retry outcome is shorter
than `MAX_AUTO_ATTEMPTS - 1` (so at most three runs in one chain) and the last
record's fingerprint differs from this run's; otherwise the fallback class of
D2. A run that ends with no retry outcome ends the chain. The decision
`retry` starts a fresh chain once.

### D8. The outcome line, the decision channel and the summary

- Every classified item prints one line `OUTCOME <json>` on stdout after any
  `REFUSE`/`STOPPED` line and the report, with keys `v` (1), `id`
  (`<reason>@<12 hex>`, the sha256 of reason, subject and the evidence bytes:
  draft bytes and counterpart oid; local, HEAD and incoming blobs; worktree
  HEAD and status; new head sha; or the fingerprint for a fallback), `class`,
  `state` (`resolved`, `retry`, `pending`), `reason`, `subject`, `detail`,
  `options` (list of `{id, effect}`), `recommended`, `question`, `action`.
  Invariants (checked by TEST-2901): `decide` has two or three options,
  `recommended` among them, a non-empty `question`; `external` has a non-empty
  `action` and no options; `auto` has no options. `--json` adds the same
  objects as `outcomes` and a `summary` object to the report.
  The existing `REFUSE <reason> <detail>` and `STOPPED <reason> <detail>`
  lines keep their text.
- `apply --decide <id>=<option>[,<id>=<option>...]` (ids match
  `^[a-z_]+@[0-9a-f]{12}$`, options `^[a-z_]+$`, anything else exit 2). A
  pair whose id is no current outcome prints `IGNORED <pair> no_longer_applies`
  and the item, if still present, is offered again under its new id; an
  option the item does not offer prints `IGNORED <pair> option_not_offered`.
  An applied choice appends one line `{id, option, reason, subject, timestamp}`
  to `pr-<n>/choices.jsonl` unless the same id and option are already there;
  a recorded `keep` or `keep_local` resolves the same id on later runs without
  asking. `plan` and `preflight` take no `--decide`.
- Both SKILL_MERGE blocks pass `AAI_DECIDE` as `--decide` when it is set
  (bash: `set -- "$@" --decide "$AAI_DECIDE"`; PowerShell: an `$AaiDec` array
  like `$AaiDir`).
- The engine ends every `apply`/`plan` run, and every preflight refusal, with
  plain-language lines: `Merge: PR #<n> is merged as <mc 12 hex>.` (preflight
  refusal: `Merge: not done.` and the reason in words); one `Cleanup:` line
  (`Cleanup: complete.`, `Cleanup: complete; kept <k> item(s), nothing needs you.`,
  `Cleanup: waiting for your decision on <d> item(s); everything else is done.`,
  `Cleanup: interrupted at <step>; retrying.`,
  `Cleanup: interrupted at <step>; waiting for your decision.`,
  `Cleanup: not started; nothing was changed.`); one `Kept:` line per kept
  item; one `Decision:` line per pending decide item (question, options with
  effects, the recommended one marked); one `Needs you:` line per external
  item. `remaining` keeps kept and pending items in words; the wording
  "unexpected leftover draft; owner decision" is gone, and a kept remote
  branch says `kept` instead of `owner decision`.

### D9. The skill routes on outcomes

`.aai/SKILL_MERGE.prompt.md`:

- Step 1: "Exit 3: relay the `REFUSE` line and stop." becomes "Exit 3: route
  its `OUTCOME` lines as in step 2." `direct_new_head` re-runs preflight with
  the new head as `--expect-head` and the owner's menu answer as
  `--direction`; `stop` ends the run. The TEST-076 sentences stay verbatim.
- Step 2 (replacing "Exit 3 or 4: relay ... the only way forward"): read every
  `OUTCOME` line; state `retry` runs the same block again now with no
  question (the engine bounds it); class `decide` asks one menu (all pending
  items in one round, each with its options and effects, the recommended
  option first) and runs the block again with `AAI_DECIDE` set to the chosen
  `id=option` pairs; class `external` relays its `action` verbatim; state
  `resolved` needs nothing. While any `retry` line is present the block runs
  again first, so the menu is asked once, from a run with no `retry` line. "never finish a step by hand (no
  `git worktree remove --force`, branch delete or `git submodule deinit`)"
  stays.
- Step 3: the final report is the engine's `Merge:`, `Cleanup:`, `Kept:`,
  `Decision:` and `Needs you:` lines, relayed verbatim; a kept remote branch
  is relayed with its reason and the agent never deletes it.
- `.aai/AGENTS.md` Operator contract rule 2 gains: the framework diagnoses and
  recovers its own problems; the owner decides only product intent or
  meaningful risk, never a framework debugging task or a bare "continue". The
  section stays within its 40-line cap (test-aai-learned-routing.sh TEST-001;
  38 lines today).

### D10. Wording rule

Every new comment, HELP line, outcome text and doc sentence of this scope
states what a check compares ("the draft text and the counterpart text with
the lifecycle keys removed"), never what it guarantees. The words
`guarantee`, `always safe`, `cannot lose`, `proves ownership` do not appear in
the new code, the skill text or the CHANGELOG entry (TEST-2922).

### D11. Governance

- New file `.aai/scripts/lib/merge-outcomes.mjs`: listed once in
  `.aai/system/PROFILES.yaml` `core` next to `merge-cleanup.mjs`, and in the
  `aai-merge-cleanup` globs of `tests/skills/suite-map.yaml`. Ceiling 520 lines.
- `merge-cleanup.mjs` stays at or under the TEST-058 ceiling of 1490 lines
  (1344 today): the table, the outcome and summary formatting, the draft
  comparison, the roadmap entry parser and `nextAttempt` live in the library.
- Prompt corpus: the `.aai/*.prompt.md` glob measures 371301 B at `fb171891`
  with TEST-010 headroom 0. SKILL_MERGE growth is credited 1:1 by one
  `JUSTIFIED_ADDITIONS` entry keyed `merge-cleanup-resolves-framework-friction`
  equal to the deficit TEST-010 measures (ceiling 900 B); the TEST-012
  `want_growth` pin moves 63094 to 63094 plus that credit; the
  test-aai-pr-preflight.sh `want_growth` expression gains the same term with
  a comment naming the key. `.aai/AGENTS.md` (23394 B) sits outside the
  TEST-010 glob: its growth is named in the entry text with no credit.
- Product doc and CHANGELOG: written by the ship step after LOOP COMPLETE (an
  `## [unreleased] — <title>` heading), not in the TDD run.

### D12. Prior contracts this spec changes (disclosure)

SPEC-0218, SPEC-0221 and SPEC-0223 rows that assert "refused, exit 3,
nothing changed" for the D2 `kept` reasons describe the behavior before this
spec. Their suite arms are amended to assert the kept outcome, the protected
object unchanged and the other steps done (Spec-AC-09). The prior specs are
done and are not edited; this section is the disclosure.

Remediation round 1 (review r1 and validation round 1) amended behavior this
section's first paragraph does not cover: a failed platform read in preflight
(and any run without an attempts record) is `external` on the first run,
because the retry budget exists only in apply; a staged overlap and a
non-file untracked collision are the kept reasons `overlap_staged` and
`untracked_not_file` (no menu, the main checkout unchanged) where the D2
table offered a decide item whose choice had no effect, so the SPEC-0222 D6
remaining-line wording for the base sync names those reasons; a locally
deleted file the sync replaces is recreated by the fast-forward; an
interrupted-sync recovery runs only after the main checkout passes the
protection check. The TEST-046 staged arm asserts the kept outcome.

Remediation round 2 (non-blocking fold) amends further: the D2 table now lists
the two kept reasons `overlap_staged` and `untracked_not_file`; plan mode names
a kept sync-base step with a `keep ... (reason)` line under its `planned` step row;
the SKILL_MERGE retry sentence states what the engine compares (a second
consecutive retry only when the item, origin HEAD, the journal's done lines or
the manifest's row count differ from the retrying run); a draft whose frontmatter `id:` is blank or whitespace
is read as having no id; the preflight `Needs you:` text says to run the
preflight again, not the cleanup. The SPEC-0222 D6 remaining-line wording for
the base sync is changed by these two kept reasons (disclosed here, as in
round 1). The round-1 contract changes are recorded by an own-spec amendment.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 (every condition carries a routable
  outcome), Spec-AC-05 (choices resume the run) and Spec-AC-07 (retry runs
  without a question).
- Intake AC-002 maps to Spec-AC-02.
- Intake AC-003 maps to Spec-AC-03.
- Intake AC-004 maps to Spec-AC-04.
- Intake AC-005 maps to Spec-AC-05.
- Intake AC-006 maps to Spec-AC-06 and Spec-AC-09.
- Intake AC-007 maps to Spec-AC-07.
- Intake AC-008 maps to Spec-AC-08 and Spec-AC-10.

## Constitution deviations

None. Article 1: each row stores a RED and a mutation record. Article 2: one
library, one table, one new flag, one new step id; no service. Article 3:
attempts and choices are plain JSONL files. Article 4: every unknown is
`external` or `retry` with a named reason. Article 5: the exit-contract change
(D6) is explicit and documented. Article 6: the engine never writes STATE
except through the existing reconcile child. Article 7: no new merge path;
preflight gates are unchanged.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN merge-cleanup.mjs prints a REFUSE or STOPPED line or reports a retained, kept or pending item the system SHALL print one OUTCOME line per item whose JSON has the D8 keys and meets the D8 invariants, and OUTCOME_TABLE SHALL hold an entry for every reason literal the engine passes to refuse, stop, retain or keep, every adapter refusal reason and reconcile_refused. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2901.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2902.log | — | TEST-2901, TEST-2902 |
| Spec-AC-02 | WHEN apply runs on the PR #485 fixture (local roadmap with the parent block active and the child block active appended after the HEAD blob, incoming roadmap with both blocks and the child done, child intake changed to done by the merge commit with links.pr empty) the system SHALL exit 0, leave docs/ai/roadmap.yaml byte-equal to the incoming blob, archive the local bytes with their sha256 in the manifest before the rewrite, print no REFUSE overlap and print Cleanup: complete.; a crash at sync-after-rewrite followed by a re-run SHALL give the same bytes; WHEN a key in K is neither equal in incoming nor a merged ref the system SHALL emit the overlap decide outcome with keep_local recommended, leave the roadmap and main HEAD unchanged, continue the other steps and exit 6, and the choices take_incoming and keep_local SHALL have the D4 effects. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2903.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2904.log | — | TEST-2903, TEST-2904, TEST-2926 |
| Spec-AC-03 | WHEN a doc changed by the merge commit is done at mc, not done at mc^1 and has links.pr absent, null or empty the system SHALL treat its id as a merged ref (roadmap D4, reconcile-origin through the real ride-handoff.mjs); WHEN links.pr names only another PR, or the doc was already done at mc^1, it SHALL NOT, and a roadmap change for that key SHALL give the overlap decide outcome with unproven in its detail; the merged doc bytes SHALL be unchanged in every case. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2905.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2906.log | — | TEST-2905, TEST-2906 |
| Spec-AC-04 | WHEN an untracked draft has exactly one numbered counterpart in the incoming tree with the same frontmatter id and the two texts are equal after the D3 normalization (the counterpart produced by the real allocate-doc-number.mjs from the same draft) the system SHALL archive the draft with reason superseded_draft and a matching sha256 and then remove it, with no question; a different body SHALL give the divergent_draft decide outcome with keep recommended; a different frontmatter id or no counterpart SHALL leave the draft untouched with no pending outcome; a local generated projection the merge changed SHALL be archived and replaced by the incoming blob. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2907.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2908.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2909.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2910.log | — | TEST-2907, TEST-2908, TEST-2909, TEST-2910, TEST-2927, TEST-2929 |
| Spec-AC-05 | WHEN apply runs with --decide naming a current outcome id and an offered option the system SHALL apply the D4 or D3 effect, record the choice once in choices.jsonl and not ask again for a recorded keep while the evidence bytes are unchanged; a stale id or an option not offered SHALL print IGNORED and re-offer the item; a malformed pair SHALL exit 2; the bash block and the PowerShell block SHALL pass AAI_DECIDE as --decide, and a router that follows the step 2 rules over the real bash block SHALL finish a fixture with one retry and one decision in at most four block runs with no other input. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2911.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2912.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2913.log | — | TEST-2911, TEST-2912, TEST-2913 |
| Spec-AC-06 | WHEN a D2 kept reason holds (dirty worktree, worktree HEAD not the PR head, live session lock, dirty submodule; diverged main, main on another branch, rewritten ledger; moved local branch; moved origin branch) the system SHALL leave the protected worktree files, HEADs, refs and ledger bytes byte-identical, record the step retained with the reason, apply the D6 dependencies and finish the other steps; preflight SHALL still refuse a changed head (decide, no merge command printed), a missing sweep and unresolved threads (external), and SHALL call no merge; an archive copy that does not read back equal SHALL stop with archive_failed and keep the source; the engine source SHALL contain no new destructive git call. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2914.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2915.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2916.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2917.log | — | TEST-2914, TEST-2915, TEST-2916, TEST-2917, TEST-2928 |
| Spec-AC-07 | WHEN a retry reason recurs the system SHALL emit state retry at most twice in one chain and SHALL switch to the D2 fallback class when the fingerprint did not change or the chain reached MAX_AUTO_ATTEMPTS; the choice skip_step SHALL retain the step and finish the rest; a crash at each new mutation point (after a draft archive, after a choice record, after a take_incoming archive) followed by a re-run SHALL end with no duplicate manifest, choices or journal line and the same tree as an uninterrupted run; a pending sync journal that no longer matches SHALL keep sync-base and finish the rest. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2918.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2919.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2920.log | — | TEST-2918, TEST-2919, TEST-2920, TEST-2925 |
| Spec-AC-08 | WHEN apply, plan or a preflight refusal ends the system SHALL print the D8 Merge:, Cleanup:, Kept:, Decision: and Needs you: lines for each terminal kind (complete, complete with kept items, decision pending, interrupted with retry, interrupted with decision, refused), and the --json report SHALL carry the same counts in summary. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2921.log | — | TEST-2921 |
| Spec-AC-09 | The amended prior arms (TEST-004, TEST-009, TEST-011, TEST-014 diverged arm, TEST-015, TEST-029, TEST-030, TEST-034, TEST-035 unpushed-tag arm, TEST-046, TEST-048 of test-aai-merge-cleanup.sh and the TEST-016 dirty-worktree It of aai-merge-cleanup.Tests.ps1) SHALL assert the kept or decide outcome, the protected object unchanged and the other steps done, and SHALL each pass through the canonical dispatcher. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2924.log | — | TEST-2924 |
| Spec-AC-10 | SKILL_MERGE.prompt.md SHALL route on OUTCOME lines as D9 states (the step 1 exit 3 sentence and the step 2 exit 3 or 4 sentence replaced, the TEST-076 and TEST-034 literals kept, AAI_DECIDE in both blocks), name every option id that is not engine-executed (direct_new_head, stop), and contain none of the D10 words; AGENTS.md rule 2 SHALL carry the D9 sentence within the 40-line cap; PROFILES.yaml and suite-map.yaml SHALL list lib/merge-outcomes.mjs; the diet ledger SHALL hold one entry for this scope equal to the measured TEST-010 deficit, the TEST-012 pin and the pr-preflight expression SHALL move by it; merge-cleanup.mjs SHALL stay at or under 1490 lines and the library at or under 520. | done | docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2922.log, docs/ai/tdd/merge-cleanup-resolves-framework-friction/green/TEST-2923.log | — | TEST-2922, TEST-2923 |

### Mutation anchors

The Test Plan mutation cells name these code forms; Implementation writes them
as named. A cell whose form the code cannot keep is re-anchored with a
`spec-amend` restamp that keeps the same comparison disabled.

- `lib/merge-outcomes.mjs`: `export const OUTCOME_PREFIX = 'OUTCOME ';`,
  `fetch_failed: retry('external'),`, `worktree_dirty: { plan: kept('remove-worktree'), step: retry('decide') },`,
  `base_diverged: kept('sync-base'),`, `overlap: decide(['keep_local', 'take_incoming'], 'keep_local'),`,
  `divergent_draft: decide(['keep', 'archive_remove'], 'keep'),`,
  `head_changed: decide(['direct_new_head', 'stop'], 'direct_new_head'),`,
  `export const DRAFT_LIFECYCLE_KEYS = ['number', 'number_reserved', 'status', 'links'];`,
  `if (fmDraft.id !== fmNumbered.id) return false;`,
  `if (localEntry === incomingEntry) continue;`,
  `export const GENERATED_PROJECTIONS = ['docs/ai/overview.html', 'docs/ai/overview-data.json', 'docs/ai/factory-report.html', 'docs/ai/factory-report-data.json'];`,
  `export const MAX_AUTO_ATTEMPTS = 3;`,
  `if (last && last.fingerprint === fingerprint) return { retry: false, why: 'no_progress' };`,
  `return decisions.find((d) => d.id === o.id && o.options.some((x) => x.id === d.option)) ?? null;`,
  `export const CLEANUP_WAITING = 'Cleanup: waiting for your decision on ';`.
- `merge-cleanup.mjs`: `if (raw.length === 0 && before !== 'done') docs.push({ id: String(fm.id), rel, proof: 'merge_commit' });`
  (with `raw` the links.pr list and `before` the status at mc^1),
  `if (!known.some((c) => c.id === rec.id && c.option === rec.option)) appendJsonl(file, rec);`,
  `if (notDone(ctx, 'sync-base') && tails.length > 0) return keepStep(ctx, 'remove-worktree', 'ledger_tails_wait_for_sync');`,
  `if (notDone(ctx, 'remove-worktree')) return keepLocalBranch(ctx);`,
  `} catch { stop('archive_failed', original); }`,
  `const EXIT_DECISION_PENDING = 6;`, and the existing `if (!known) {` and
  `if (!fs.readFileSync(dest).equals(bytes)) throw new Error(` in `archiveFile`.
- `SKILL_MERGE.prompt.md`: `--decide "$AAI_DECIDE"` (bash block),
  `$AaiDec = @('--decide', $env:AAI_DECIDE)` (PowerShell block), the phrase
  `run the same block again`.
- `AGENTS.md`: the phrase `The framework diagnoses and recovers its own problems`.

## Implementation plan

- Batch A (library and table): `lib/merge-outcomes.mjs` with `OUTCOME_TABLE`,
  the helpers, `classify`, `outcomeLine`, `supersededDraft`, `roadmapEntries`,
  `representedChanges`, `nextAttempt`, `choiceFor`, `summaryLines`; TEST-2901,
  TEST-2918 first (unit, via `node -e` imports from the suite).
- Batch B (engine wiring): refuse/stop/retain call sites go through
  `classify`; planChecks collects verdicts into kept steps; D6 dependencies;
  exit 6; OUTCOME and summary emission; attempts ledger; `--decide` and
  choices; TEST-2902, TEST-2911, TEST-2914 to TEST-2917, TEST-2919, TEST-2921.
- Batch C (D3, D4, D5): `archive-drafts` step, `roadmapRepresented`,
  generated projections, identity fallback; TEST-2903 to TEST-2910, TEST-2920.
- Batch D (canon and governance): SKILL_MERGE, blocks, AGENTS rule 2, PROFILES,
  suite-map, ledger, pins; the amended prior arms and the Pester It;
  TEST-2912, TEST-2913, TEST-2922 to TEST-2924.
- Seams crossed by a real producer and a real consumer: allocate-doc-number.mjs
  output read by the draft comparison (TEST-2907); roadmap-edit.mjs
  ship-append output read by `roadmapRepresented` (TEST-2903); the identity
  fallback read by ride-handoff.mjs reconcile (TEST-2905); engine OUTCOME lines
  read by a router that executes the real prompt block (TEST-2912); the
  PowerShell block reading `AAI_DECIDE` (TEST-2913).
- Fixtures: every world is built by the suite's existing `build_world` family
  under the one scratch root, with private git identity and the deny-by-default
  gh stub. Large JSON goes on stdin (`json_get` already reads stdin); no fixture
  passes more than a PR number and short flags on argv (Linux 128 KiB cap). The
  router test pins `AAI_HARNESS=claude` although no engine path reads it.
- Edge cases named: a draft whose counterpart exists twice (untouched); a
  roadmap whose only change is outside entries (overlap); `--decide` on a
  re-run where the item resolved itself meanwhile (IGNORED); a kept worktree
  whose branch is checked out there (delete-branch keeps the local ref);
  `attempts.jsonl` unreadable (treated as no records: at most one extra retry,
  named in the hand-off).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2901 | Spec-AC-01 | unit | tests/skills/test-aai-merge-cleanup.sh | test_2901_outcome_table_complete imports lib/merge-outcomes.mjs: every reason literal scanned from merge-cleanup.mjs refuse, stop, retain and keep calls, the six adapter reasons and reconcile_refused has a table entry; classify on every entry gives an object meeting the D8 invariants (decide two or three options with effects, recommended among them, question non-empty; external action non-empty and no options; auto no options); outcomeLine starts with OUTCOME and parses back to the same object | `sed:s/fetch_failed: retry\('external'\),/fetch_failedx: retry('external'),/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2902 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2902_outcome_lines_from_real_runs: not_merged (external, exit 3, world_digest unchanged), fetch_failed via an unreachable origin URL (auto retry, exit 3), a dirty worktree (auto resolved kept, exit 0) and a divergent draft (decide pending, exit 6) each print OUTCOME lines that parse and meet the invariants, after the unchanged REFUSE text where one is printed | `sed:s/export const OUTCOME_PREFIX = 'OUTCOME ';/export const OUTCOME_PREFIX = 'RESULT ';/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2903 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2903_pr485_parent_child_roadmap: local roadmap = HEAD blob plus the parent block active plus the child block active (child written by the real roadmap-edit ship-append), incoming adds parent active and child done, child intake done at mc with links.pr empty, parent RFC doc implementing; apply exits 0, roadmap bytes equal git show origin/main roadmap, archive copy sha256 equals the local-before bytes and the manifest line names pre_sync_local_state, no REFUSE overlap, no pending OUTCOME, Cleanup: complete.; crash arm at sync-after-rewrite then re-run gives the same bytes; RED on fb171891 is REFUSE overlap docs/ai/roadmap.yaml | `sed:s/if \(localEntry === incomingEntry\) continue;/if (false) continue;/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2904 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2904_unrepresented_roadmap_decides: the parent block differs from incoming (status paused) and the parent is no merged ref; apply exits 6 with one overlap decide OUTCOME (keep_local recommended, detail names the parent key), roadmap and main HEAD unchanged, worktree without tails removed, reconcile retained sync_not_done; re-run with --decide id=keep_local exits 0 with sync-base retained and asks nothing on a second re-run; a fresh world with --decide id=take_incoming archives the local roadmap and syncs | `sed:s/const EXIT_DECISION_PENDING = 6;/const EXIT_DECISION_PENDING = 0;/` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2905 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2905_absent_links_pr_proven_by_merge_commit: the merged intake has no links.pr key (and a second arm links.pr empty list), status draft at mc^1 and done at mc; its ride roadmap entry is taken from incoming with no outcome, the real ride-handoff.mjs reconcile clears the origin STATE trace of that ref (RECONCILED), and the intake blob and file bytes are unchanged after apply | `sed:s/if \(raw\.length === 0 && before !== 'done'\) docs\.push/if (false) docs.push/` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2906 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2906_conflicting_or_old_identity_not_proven: links.pr naming only 999, and a doc already done at mc^1 with links.pr empty, each with a local roadmap change for the key; apply emits overlap decide with unproven key in detail, reconcile does not run for the ref, the doc bytes are unchanged | `sed:s/raw\.length === 0 && before !== 'done'/before !== 'done'/` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2907 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2907_superseded_draft_archived: the ride branch numbers an intake with the real allocate-doc-number.mjs (offline, so number_reserved false is stamped), the origin keeps the pre-allocation untracked copy (the #495 to #500 case); apply exits 0, the draft is gone, its archive under pr-N/drafts has the draft sha256 and reason superseded_draft in the manifest, no leftover_draft text, Cleanup: complete.; RED on fb171891 is retained leftover_draft | `sed:s/\['number', 'number_reserved', 'status', 'links'\]/['number_reserved', 'status', 'links']/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2908 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2908_divergent_draft_menu: the untracked copy has one extra body line; apply exits 6 with a divergent_draft decide OUTCOME (keep recommended, archive_remove offered), the draft bytes unchanged; --decide id=keep exits 0 and a second re-run asks nothing; after the draft changes again the item is offered under a new id; --decide id=archive_remove archives then removes it | `sed:s/divergent_draft: decide\(\['keep', 'archive_remove'\], 'keep'\),/divergent_draft: decide(['keep', 'archive_remove'], 'archive_remove'),/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2909 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2909_unproven_drafts_untouched: a draft whose frontmatter id differs from the counterpart with the same slug, a draft with no counterpart and a draft with two counterparts are left byte-identical, listed under untouched, and produce no pending OUTCOME and no remaining line | `sed:s/ fmDraft\.id !== fmNumbered\.id\) return false;/ false) return false;/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2910 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2910_generated_projection_taken: a dirty local docs/ai/overview-data.json and factory-report.html that the merge also changed are archived with pre_sync_local_state and replaced by the incoming blobs, apply exits 0; a dirty docs/USER_GUIDE.md the merge changed still gives the overlap decide outcome | `sed:s/export const GENERATED_PROJECTIONS = \[[^\]]*\];/export const GENERATED_PROJECTIONS = [];/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2911 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2911_decide_channel: a valid pair applies once and choices.jsonl holds one line after two identical re-runs; a pair with a stale digest prints IGNORED no_longer_applies and the item is re-offered with a new id; an option the item does not offer prints IGNORED option_not_offered; a malformed pair and --decide on plan exit 2 | `sed:s/d\.id === o\.id && //` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2912 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2912_router_resumes_in_one_interaction: a test router (in the suite, AAI_HARNESS=claude) runs the real bash block extracted from SKILL_MERGE, re-runs on state retry, answers every decide item with its recommended option through AAI_DECIDE, and stops on external; on a world with one forced sync_failed (seam) and one divergent draft it ends with exit 0 in at most four block runs and no other input | `sed:s/--decide "\$AAI_DECIDE"/--decide ""/` on .aai/SKILL_MERGE.prompt.md | green |
| TEST-2913 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | It TEST-2913 of tests/skills/aai-merge-cleanup.Tests.ps1, run by the suite selector TEST-016: the PowerShell block with AAI_DECIDE set to the archive_remove pair of a divergent draft archives and removes it, and without AAI_DECIDE the block throws exited 6 and the draft stays | `sed:s/\$AaiDec = @\('--decide', \$env:AAI_DECIDE\)/$AaiDec = @()/` on .aai/SKILL_MERGE.prompt.md | green |
| TEST-2914 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2914_worktree_protections_kept: arms dirty worktree, worktree HEAD ahead of the PR head, live foreign session lock, dirty submodule; each: worktree file hashes, git status, HEAD and the local branch ref identical before and after, remove-worktree and delete-branch retained with the reason, sync-base done, origin branch deleted by lease, exit 0, Kept: line present | `sed:s/worktree_dirty: \{ plan: kept\('remove-worktree'\)/worktree_dirty: { plan: external('x')/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2915 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2915_sync_protections_kept: arms main with a local commit, main on another branch, a rewritten EVENTS ledger; each: main HEAD, branch and ledger bytes identical, sync-base and reconcile-origin retained, a worktree without ledger tails removed and a worktree with tails kept with ledger_tails_wait_for_sync and its tail bytes still in the worktree, exit 0 | `sed:s/if \(notDone\(ctx, 'sync-base'\) && tails\.length > 0\) return keepStep\(ctx, 'remove-worktree', 'ledger_tails_wait_for_sync'\);//` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2916 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2916_preflight_gates_hold: a moved PR head gives REFUSE head_changed with a decide OUTCOME (direct_new_head recommended, stop) and no merge command line; a stale sweep and unresolved threads give external OUTCOMEs; world_digest unchanged and assert_no_merge_call for each | `sed:s/head_changed: decide\(\['direct_new_head', 'stop'\], 'direct_new_head'\),/head_changed: kept('sync-base'),/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2917 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2917_archive_verification_and_no_new_primitive: the seam AAI_MERGE_CLEANUP_CORRUPT_ARCHIVE alters a superseded draft archive copy after the copy; apply stops with STOPPED archive_failed, the draft bytes are intact, exit 4; the engine and library sources contain no git call with prune, branch -D, push --delete, reset, stash or clean, and worktree remove --force occurs once | `sed:s/if \(!fs\.readFileSync\(dest\)\.equals\(bytes\)\) throw new Error\(/if (false) throw new Error(/` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2918 | Spec-AC-07 | unit | tests/skills/test-aai-merge-cleanup.sh | test_2918_next_attempt: nextAttempt with no records gives retry; two trailing retry records with distinct fingerprints and a third distinct one gives no retry (budget); a last record with the same fingerprint gives no retry with why no_progress; a record ending without a retry outcome resets the chain | `sed:s/export const MAX_AUTO_ATTEMPTS = 3;/export const MAX_AUTO_ATTEMPTS = 99;/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2919 | Spec-AC-07 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2919_retry_chain_terminates: with a seam that fails the fast-forward every time, run 1 exits 4 with state retry, run 2 (no progress) exits 4 with sync_failed as decide (retry, skip_step recommended) and Cleanup: interrupted at sync-base; waiting for your decision.; --decide id=skip_step exits 0 with sync-base retained and the worktree steps done; attempts.jsonl has one line per run; an unreachable origin gives retry then external with a Needs you: line | `sed:s/if \(last && last\.fingerprint === fingerprint\) return \{ retry: false, why: 'no_progress' \};//` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2920 | Spec-AC-07 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2920_interrupted_recovery_converges: crash seams draft-after-archive, choice-after-record and take-incoming-after-archive, each followed by a re-run: manifest, choices and journal hold no duplicate line (timestamps stripped) and tree_sig equals an uninterrupted twin; a sync pending journal whose live ledger no longer starts with the HEAD blob gives sync-base kept pending_diverged, the journal and archive kept, the rest finished (closes fu-merge-pending-diverged-regression) | `sed:s/if \(!known\) \{/if (true) {/` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2921 | Spec-AC-08 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2921_plain_summary: for complete, complete with a kept worktree, a pending divergent draft, an interrupted retry, an interrupted fallback and a not_merged refusal the output has the exact Merge: and Cleanup: lines of D8 and one Kept:, Decision: or Needs you: line per item; the --json report summary counts equal the line counts; a preflight head_changed refusal prints Merge: not done. | `sed:s/export const CLEANUP_WAITING = 'Cleanup: waiting for your decision on ';/export const CLEANUP_WAITING = 'Cleanup: complete; ';/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2922 | Spec-AC-10 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2922_skill_and_engine_agree: SKILL_MERGE step 2 names OUTCOME, retry, decide, external, AAI_DECIDE and run the same block again, step 1 no longer holds Exit 3: relay the REFUSE line and stop, the TEST-076 sentences are present, both blocks pass the decide flag, every option id in OUTCOME_TABLE that the engine does not execute (direct_new_head, stop) is named in step 1 or 2, none of the D10 words occur in SKILL_MERGE, the library or the engine comments added by this scope; AGENTS.md Operator contract carries the D9 phrase and stays within 40 lines | `sed:s/run the same block again/run nothing/` on .aai/SKILL_MERGE.prompt.md | green |
| TEST-2923 | Spec-AC-10 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2923_governance: PROFILES core lists lib/merge-outcomes.mjs exactly once, the suite-map aai-merge-cleanup globs list it, the diet ledger holds exactly one merge-cleanup-resolves-framework-friction entry whose bytes equal the glob growth over 371301 and lie in 1..900, test-aai-prompt-diet.sh TEST-010 passes with headroom 0, the TEST-012 pin equals 63094 plus the entry, merge-cleanup.mjs has at most 1490 lines and the library at most 520 | `sed:s/lib\/merge-outcomes\.mjs/lib\/merge-outcomes-x.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-2924 | Spec-AC-09 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2924_amended_prior_arms runs the selectors TEST-004, TEST-009, TEST-011, TEST-014, TEST-015, TEST-029, TEST-030, TEST-034, TEST-035, TEST-046 and TEST-048 of the suite in a child process and requires exit 0 for each, after each arm was rewritten to assert the kept or decide outcome, the protected object unchanged and the other steps done (the Pester TEST-016 dirty It is amended the same way and runs in the PowerShell leg) | `sed:s/base_diverged: kept\('sync-base'\),/base_diverged: external('x'),/` on .aai/scripts/lib/merge-outcomes.mjs | green |
| TEST-2925 | Spec-AC-07 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2925_preflight_retry_is_bounded: a preflight against a gh that fails every read, run three times, gives REFUSE gh_read_failed with an external pending OUTCOME and a Needs you: line on every run (no state retry), the fixture digest unchanged, no merge call, and SKILL_MERGE no longer says the engine bounds the retries | `sed:s/const att = af \? nextAttempt\(readJsonl\(af\), fp\) : \{ retry: false \}/const att = af ? nextAttempt(readJsonl(af), fp) : { retry: true }/` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2926 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2926_unactionable_clash_choices_not_offered: a staged roadmap change gives overlap_staged kept (exit 0, a Kept: line, no Cleanup: complete., no decide outcome, main not moved); a directory where the merge adds a file gives untracked_not_file kept with the directory intact; keep_local on an offered overlap prints a Kept: line and not Cleanup: complete. | `sed:s/if \(staged\.has\(rel\)\) return \{ refusal: \['overlap_staged', rel\] \};//` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2927 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2927_locally_deleted_files_sync_cleanly: a generated projection deleted in the main checkout and changed by the merge, and a deleted guide answered take_incoming, each exit 0 with no ENOENT in stderr, main at the merge commit and the file recreated from the incoming blob | `sed:s/catch \{ .. deleted locally[^}]*\}/catch (e) { throw e; }/` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2928 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2928_recovery_waits_for_protection_check: a sync interrupted at sync-after-rewrite leaves a pending journal; the main checkout is then switched to another branch; apply keeps sync-base as origin_not_on_base, the file on that branch is byte-identical and the journal is still present | `sed:s/const gate = syncGate\(ctx\); if \(gate\.refusal\) halt\(\.\.\.gate\.refusal, \{ phase: 'plan' \}\);//` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-2929 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_2929_null_identity_never_matches: compareDraft of two texts without a frontmatter id gives false while equal ids still give superseded; a merged intake with links.pr ~ (YAML null) is proven by the merge commit like an empty list (roadmap taken, no pending outcome) | `sed:s/if \(!fmDraft\.id/if (false/` on .aai/scripts/lib/merge-outcomes.mjs | green |

### RED observations and positive controls

- TEST-2901, TEST-2918: RED on `fb171891` because `lib/merge-outcomes.mjs`
  does not exist (the import fails; the suite reports FAIL TEST-29xx, never a
  vacuous pass).
- TEST-2902 to TEST-2911, TEST-2914, TEST-2915, TEST-2917, TEST-2919 to
  TEST-2921: RED on `fb171891` (no OUTCOME line; REFUSE overlap; retained
  leftover_draft; exit 3 for kept reasons; uncaught throw on a corrupt
  archive; no --decide flag). The stored RED is the arm's own output on the
  base, under `docs/ai/tdd/merge-cleanup-resolves-framework-friction/red/`.
- TEST-2912, TEST-2913, TEST-2922: RED on the base (blocks lack AAI_DECIDE,
  step texts unchanged).
- TEST-2916: the refusals already hold on the base; the RED is the missing
  OUTCOME line, and the mutation record proves the class is read from the
  table.
- TEST-2923, TEST-2924: RED on the base (no ledger entry, no profile line;
  the prior arms still assert exit 3, which the new engine no longer gives).
- Positive controls: TEST-2903 asserts the RED shape (REFUSE overlap) on a
  copy of the base engine before the green run is trusted; TEST-2907 asserts
  the allocator really changed the number line (the draft and counterpart
  differ as raw bytes); TEST-2914 and TEST-2915 assert each arm's protection
  is present before apply (git status non-empty, rev-list count positive,
  lock alive, ledger not a prefix); TEST-2919 asserts the seam failed the
  fast-forward (stderr line).

## Verification

- Suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`
  exits 0 (with `AAI_TEST_TIMEOUT=3000` when run as part of a full sweep).
- Single rows: `env -u AAI_ROLE bash tests/skills/test-aai-merge-cleanup.sh --test TEST-29xx` per row.
- Pester: `pwsh -NoProfile -Command "Invoke-Pester tests/skills/aai-merge-cleanup.Tests.ps1"` where
  pwsh with Pester 5 is present; otherwise the PR's Windows CI leg is the evidence.
- Neighbours through the wrapper, each exit 0: test-aai-platform-adapter.sh,
  test-aai-ride-handoff.sh, test-aai-prompt-diet.sh, test-aai-pr-preflight.sh,
  test-aai-learned-routing.sh, test-aai-layer-profiles.sh, test-aai-hygiene-pack.sh,
  test-aai-suite-select.sh, test-aai-doc-numbering.sh.
- Selection: `git diff --name-only fb171891 | node .aai/scripts/select-suites.mjs --files-from -`;
  every selected suite exits 0; one full sweep before close.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'`
  per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint and audit: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error;
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <this spec>` reports no finding this scope introduced.
- Amendment ledger: `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- Replay of the real cases: Validation rebuilds the #485 roadmap bytes and the
  #495 to #500 draft case in a scratch clone and records the outputs.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/merge-cleanup-resolves-framework-friction/`, and the mutation
record from `mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/`
artifact at hand-off. Strategy tdd: stored RED per AC-gating test plus the
verification list above. Planning's measurements (371301 glob bytes, headroom
0, 1344 engine lines, 38 contract lines) are inputs, not attestations.

## Risks and rollback

- Keep-and-continue (D6) changes what a reader of exit 3 could rely on: a
  dirty worktree no longer stops the base sync. Each step keeps its own proof;
  the dependency table is the whole coupling this spec claims. Residual: a
  coupling between steps that the table does not name is not tested.
- The identity fallback (D5) attributes a doc whose status the merge commit
  flipped to done and whose links.pr is empty. A PR that closes another ride's
  doc without stamping it is attributed too; the effects are archive-first
  (roadmap) and the reconcile of that ref's STATE traces.
- The draft comparison removes four frontmatter keys and substitutes the stem;
  a draft that differs only inside those keys (for example a different status)
  is archived and removed. The archive keeps its bytes.
- The skill's menu is prose shown by the harness; no automated test crosses
  the human answer. TEST-2912's router is a test double of the agent.
- Rollback: revert the PR; archives, choices and attempts files are gitignored
  or under `.git` and are inert for the old engine (its journal reader
  tolerates the added step id).

## Registry disposition

Registry items closed by this scope: CLOSED FULLY: `fu-merge-pending-diverged-regression`
(TEST-2920 adds the pending_diverged suite arm). NOT CLOSED (scanned):
`fu-platform-azure-links-pr-url` (an Azure URL in links.pr is a non-empty
value, so D5's fallback does not apply to it), `fu-merge-skip-worktree-hidden-edit`
(a separate worktree proof gap), `fu-merge-ledger-reset-window`.

## Owner decisions

- Recorded: the intake is owner-approved; the merge of this ride goes through
  the owner's menu (consumer-visible change to the shipped merge skill).
- For the owner, with a recommendation (the spec is frozen on the
  recommended answer; another answer is a spec amendment): protected
  conditions keep the object and finish the other steps without asking
  (recommended, D1 and D6), or they refuse as today and ask a keep-or-stop menu.
