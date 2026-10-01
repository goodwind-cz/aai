---
id: spec-friction-issues-arrive-without-a-description
type: spec
number: 203
status: done
mutation_gate: v1
frozen_sha256: 574932ff3bf6a679dee6bd56b0c27802bd7f4b6e1724b0a165550e0c6a6c1bb7
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0179-friction-issues-arrive-without-a-description.md
  rfc: null
  pr:
    - TBD
  commits:
    - 20f277e3cad5becad7668639a487b5f9c564c759
---

# Spec — a friction issue carries a description or is not filed

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0179-friction-issues-arrive-without-a-description.md (id `friction-issues-arrive-without-a-description`)
- Decision records: docs/ai/decisions.jsonl line 691 (`hitl_decision`, owner, 2026-09-05, ref `friction-issue-body-is-prose-free`, `owner_signoff: true`) — "Automatic capture stays prose-free. An observation a human deliberately PROMOTES may carry prose that the human wrote and read. capture.summary_enabled stays false." This spec is bound by it (PLANNING principle 3) and builds on it; it does not re-open it.
- Technology contract: docs/TECHNOLOGY.md
- Directly applicable prior art: docs/rfc/RFC-0013-friction-record-v2-redaction.md (D2 opt-in summary, D3 double redaction, D4 drop-the-field); docs/specs/SPEC-0176-spec-friction-publish-hides-required-followup.md (D4/D5: the draft is never read by the publish path — preserved here; Spec-AC-06: the certified-prose comment — untouched here); docs/specs/SPEC-0185-spec-friction-channel-sweep.md (D2 `--promote`, Spec-AC-05 the shared `noteSummaryDropped()` — the sub-case the intake says not to re-litigate); docs/specs/SPEC-0104-spec-issues-skill.md (`aai-issues.mjs` reader contract extended by Spec-AC-08).
- Registry items closed by this scope: fu-prompt-only-when-misses-dropped-case (Spec-AC-10 rewrites the SKILL_FEEDBACK_UPSERT section that described when the comment command is printed; under the new contract a record with no certified description is never filed, so the "only when" sentence the finding faults is replaced, not patched).
- NOT CLOSED by this scope (subject touched, each with the reason — a separate bullet so verify-closures never reads these as claims): fu-two-prompt-files-still-stale (names SKILL_WRAP_UP.prompt.md:135 and SKILL_FEEDBACK_TRIAGE.prompt.md:28, neither of which this scope edits; adding two more prompt-corpus edits widens the diet-ledger obligation of a channel ride that already carries one), fu-comment-fail-no-retry-exit0 (the second mutating call's failure accounting is SPEC-0176 Spec-AC-06's contract and is deliberately untouched, see Decisions D6), fu-runtests-capture-is-unscored-noise and fu-runtests-ps1-captures-no-friction (the wrapper's capture content is a producer-side concern; this scope changes what the channel FILES, not what the wrapper RECORDS), fu-friction-loop-has-no-scheduler (scheduling is orthogonal to body content), fu-friction-scoring-rewards-recurrence (named out of scope by the intake). The intake also names fu-friction-issue-body-is-prose-free as "already registered": the ledger shows it `done` since 2026-09-12 (decisions.jsonl line 776, resolved_by friction-publish-hides-required-followup), so there is nothing to close — the intake's premise that it is open is stale.

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: tdd
- Rationale: no intake-sourced choice exists in STATE (`implementation_strategy.selected: undecided`, `source: null`), so Planning decides. The scope changes the ONE mutating path of a channel that writes to a PUBLIC issue tracker, and that exact script is where the repository's two most expensive scars were cut: LEARNED 2026-09-05 `fu-learned-deny-by-default-mocks` and `fu-learned-positive-control-for-absence` both came from `aai-feedback-upsert.mjs` (ISSUE-0080 / SPEC-0166, four validation rounds, 24 blocking findings), and the owner's 2026-09-05 decision cites "the double redaction can be silenced without anyone noticing" as the reason the privacy default stays. Every refusal this spec adds is an ABSENCE (no gh call) and therefore needs a positive control and a RED observation, not a green run; every Test Plan row carries a machine-readable mutation and its RED is recorded at `docs/ai/tdd/spec-friction-issues-arrive-without-a-description/mutation-<TEST-id>.txt` via `node .aai/scripts/mutation-run.mjs`.

Allowed strategy values:
- loop: implementation agent covers all TEST-xxx entries in one focused pass
- tdd: RED-GREEN-REFACTOR is required per TEST-xxx
- hybrid: TDD for risky/core behavior, loop implementation for low-risk glue or docs
- direct: direct implementation plus targeted regression tests, no RED-first ceremony
- untested: direct implementation with NO tests; allowed only with a recorded rationale
- undecided: planning is incomplete and implementation must not start

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the main checkout at /Users/ales/Projects/aai is held by another session's ride (branch `change/readme-portable-workflow-onboarding`, uncommitted README.md); this ride already runs in its own worktree. The scope is PR-bound and touches a public-write path whose suite (test-aai-feedback-upsert.sh, 2005 lines) is long-running — isolation keeps its fixtures and the gitignored evidence tree out of the shared checkout.
- User decision: worktree (recorded in STATE before Planning: `worktree.user_decision: worktree`, `path: /Users/ales/Projects/aai-friction`)
- Base ref: origin/main
- Worktree branch/path: /Users/ales/Projects/aai-friction on `change/friction-issues-carry-a-description`. MEASURED DEFECT: `node .aai/scripts/branch-guard.mjs` refuses this branch ("does not correspond to current_focus.ref_id friction-issues-arrive-without-a-description"; `--suggest` prints `feat/friction-issues-arrive-without-a-description`). The PR ceremony fails closed on it. Remediation before the first commit: `git branch -m change/friction-issues-arrive-without-a-description` in the worktree, then `node .aai/scripts/state.mjs set-worktree --branch change/friction-issues-arrive-without-a-description` (the `change/` token is the intake's type; branch-guard accepts any `<type>/<ref-id>` whose ref-id matches).
- Inline review scope: not applicable (worktree chosen); the review scope is the explicit path list under `## Verification` → "Review scope".

Allowed worktree recommendation values:
- not_needed: small, low-risk, clearly scoped change
- optional: useful but not important for safety
- recommended: larger, experimental, PR-bound, or parallelizable work
- required: protected workflow/state/schema, migration, or high-risk work; user may still explicitly override inline

Allowed user decision values:
- undecided: no implementation may start when recommendation is recommended or required
- worktree: create/use a git worktree before implementation
- inline: continue in the current working tree with a clean explicit review scope
- waived: user explicitly accepts the risk of ambiguous isolation or review scope

## Measured current behaviour (every claim re-run 2026-10-01 in /Users/ales/Projects/aai-friction at a9568897; nothing is taken from the intake on trust)

- M1. `.aai/feedback.yaml:17` ships `summary_enabled: false` under `capture:`; `aai-friction.mjs:398-423` (`loadSummaryEnabled`) reads only that key and fails closed to `false`; `aai-friction.mjs:512` gates the summary on `promote || loadSummaryEnabled()`.
- M2. No automatic producer supplies a `summary`. The wrapper capture point `aai-run-tests.sh:208` builds `{schema_version:2, skill_id, skill_phase, failure_class, expected_behavior, observed_behavior, confidence:"low"}` and nothing else. The four default-on hook prompts (`VALIDATION.prompt.md:235,256`, `REMEDIATION.prompt.md:40`, `IMPLEMENTATION.prompt.md:136`, `SKILL_PR.prompt.md:474`) point at FRICTION_PROTOCOL and mention no summary field (`grep -c` of `"summary"` and `summary:` in each: 0). Consequence: flipping `summary_enabled` to `true` would change zero bytes of any automatically recorded observation.
- M3. `expected_behavior` and `observed_behavior` are REQUIRED at capture (`aai-friction.mjs:239-240`) and never persisted (`:479-489` builds the record from the allowlist; FRICTION_PROTOCOL "No prose persisted in Phase 0"). The sentence that says what happened exists at capture time and is discarded by design.
- M4. `MAX_SUMMARY_LEN = 200` (`.aai/scripts/lib/aai-redact.mjs:18`); the capture pass passes it explicitly (`aai-friction.mjs:513`), the transmit pass uses the default (`aai-feedback-upsert.mjs` `buildPayload`, `redactSummary(rep.summary)`). `redactSummary` refuses control characters (`:110`, so a newline is `control_char`), and the allow-list charset `:98` refuses `/`, `=`, backticks, `@`, `+`. Probed with `{maxLen: 1200}`: two realistic one-line "expected X; observed Y; where Z" descriptions of 238 and 246 chars certify `ok` (both exceed 200); two that name `hooks/merge-guard.sh` or `refuses=true` fail `unsafe_char` regardless of length; a 2006-char line fails `over_length`.
- M5. The upsert files a prose-free record silently: `buildPayload` renders the blockquote only when `rep.summary` certifies, else `redaction_status: 'none'`, and `main()` proceeds to `gh issue create` unconditionally; on success it PRINTS a `gh issue comment … --body-file <file>` command for the operator (SPEC-0176 D2). `HELP` and `.aai/SKILL_FEEDBACK_UPSERT.prompt.md:46-59` describe this as the contract ("Filing an issue is NOT the end of the work").
- M6. `representative()` picks the highest-signal member of a fingerprint (impact + confidence + reproducible) and ignores whether a member carries a summary; a promoted record can be shadowed by a prose-free sibling with the same fingerprint.
- M7. `aai-issues.mjs:236` fetches `--json number,title,labels,body,url`; `excerptOf(i.body)` (`:201`) is the only text the triage layer sees. Comments are never read.
- M8. Live queue (`gh issue list --repo goodwind-cz/aai --state open`, 2026-10-01): three open issues, all carrying the `aai-friction:` marker, all with ZERO prose lines in the body. #339: 0 comments (filed by the pre-SPEC-0178 template: no `harness`, `evidence_ref: docs/ai/factory-report.html`, a reporter-local generated page). #369 and #370: ONE comment each, `## Analysis (reporter follow-up)` by aleho70 (3,831 chars on 2026-09-10 and 3,640 chars on 2026-09-12), each a full symptom/mechanism write-up. #338 is CLOSED (2026-09-30T19:23:09Z, by aleho70: "the mechanization this reported is shipped"). The dispatch's statement that #369 and #370 carry no such comment is contradicted by this measurement; what made them look untriageable is M7.
- M9. The five issues the intake calls actionable (#414, #392, #391, #390 and the two above) were ALL hand-authored observations (impact/confidence/reproducible/workaround/evidence_ref set) whose author then wrote a 3.6-3.8k-char comment containing paths, code fences and `file:line` references — text the redactor can never certify (M4). The actionable content of this channel has therefore travelled with ZERO redaction, by hand, every time; the automatic body, which is double-redacted, has carried nothing. `--promote` (SPEC-0185 D2, shipped 2026-09-25) was used by none of the five.
- M10. The upsert suite's shared fixtures (`setup()` and `seed_single_candidate()` in tests/skills/test-aai-feedback-upsert.sh) carry NO summary; `gh issue list --json comments` is a valid field (measured: returns the comment arrays for #369/#370).

## Decisions (the five the dispatch requires, each explicit)

### D1 — What a friction issue must carry to be actionable (the field list)
A filed issue MUST carry, in this order: (1) the templated title `[<failure_class>] <skill>/<phase> (<impact> impact)` — unchanged; (2) ONE certified human-written description, rendered as the leading blockquote `> <text>` of the body: one line, 1..500 characters, certified by `redactSummary` with no detector hit; (3) the structured facts already emitted (failure_class, skill/phase, impact, confidence, reproducible, workaround, evidence_ref labelled reporter-local, os_family/node_major/aai_pin/harness, recurrence/score) — unchanged; (4) the dedup marker — unchanged. Item (2) is the new hard requirement; everything else already exists. The description's source is either the spool record's own `summary` (written at record time under `--promote`, or under `capture.summary_enabled: true` where an operator opted in) or a publish-time `--description <file>` (new, this spec). The mechanism, reproduction steps and anything naming a path or quoting output stay a hand-posted comment, because the redactor's allow-list cannot certify them (M4) and the redaction rules are out of scope. Ground: M9 — a one-line "expected; observed; where" is what a maintainer needs to START; the four actionable analyses all opened with exactly that paragraph.

### D2 — The capture default does NOT flip; the posture is written next to the flag
`capture.summary_enabled` stays `false`. Three grounds, any one sufficient. (a) A recorded owner decision says so (decisions.jsonl line 691, 2026-09-05, `owner_signoff: true`): automatic capture stays prose-free because no human reads agent-written text before it leaves for a PUBLIC tracker; Planning does not overrule a recorded human choice. (b) It would be ineffective: M2 shows no automatic producer writes a summary, so the flip changes nothing that is actually captured; the real lever is at the human-attested points (`--promote`, `--description`). (c) What the redaction guarantees are worth, stated plainly: a certified line consists only of ASCII prose characters and matches none of the enumerated secret/identity shapes (`aai-redact.mjs:26-85`); that is strong against keys, tokens, URLs, emails, paths, IPs and multi-label hosts, and worth nothing against a bare hostname, a customer or project name, or an internal code word written as an ordinary word (FRICTION_PROTOCOL's accepted residual) — and the suite once shipped green with the double redaction silenced (LEARNED 2026-09-05). A guarantee of "no known-shaped secret" is not a guarantee of "no identity", so it does not license unread agent prose on a public tracker. The human who writes and reads the line, then types `--confirm`, is the control the owner chose; this spec keeps it. Consequence for downstream projects: NO privacy default changes on their next sync. The trade-off is written as a comment block next to the flag (Spec-AC-07) so an operator who opts in does so informed.

### D3 — A record that cannot carry prose is NOT filed; the refusal names the field and makes no network call
Prepare marks such a cluster `blocked_no_description` and prints `not offered: no description — write one line (expected, observed, where) and pass --description <file> to --publish`. Publish refuses BEFORE the auth preflight, the dedup search, the label read and the create — zero `gh` invocations — with exit 2 and stderr `aai-feedback-upsert: refusing to file <fp>: no description — the record carries no certified summary and no --description <file> was given (a maintainer cannot act on structured fields alone)`. A `--description` the redactor refuses is refused the same way, naming the redactor's reason (`… the description was refused by the redactor (reason: <class>) — rewrite it without the offending shape`), still with zero `gh` calls. The alternative — file it anyway with a "no description captured, here is why" line — is rejected: M8 shows such an issue (#339) occupying the queue for 25 days with nobody able to act on it; the "why" would be the same constant sentence on every such issue and carries no information a maintainer can use; and the cost lands on a PUBLIC tracker. Signal volume (the intake's stated risk) is not lost: the local triage report and `aai-feedback-status.mjs` still show every cluster and its recurrence, and the one-line description the publisher must now write is exactly what the owner wrote by hand after filing, moved to before filing. Representative selection (M6) is corrected so a promoted record is never shadowed: among a fingerprint's members, one carrying a `summary` is preferred; ties by signal as today.

### D4 — The three live issues
- GitHub #338 - CLOSED by the owner 2026-09-30 ("the mechanization this reported is shipped") — already dispositioned; the intake's AC-005 naming it is satisfied by that record.
- GitHub #339 - CLOSED by this scope as unactionable: zero comments, zero prose lines, `evidence_ref` a reporter-local generated page, filed before `harness` existed; nothing to reconstruct. The close comment is the fixed text in `## Disposition of the live queue` below and names this spec. This is a public write: the ORCHESTRATOR (or the owner) runs it at the PR ceremony, never a subagent; the captured `gh issue view 339 --json state,comments` output is stored at `docs/ai/tdd/spec-friction-issues-arrive-without-a-description/issue-339-close.txt`.
- GitHub #369 - OPEN, actionable: it carries a 3,831-char analysis comment (M8). It is an intake candidate for `/aai-issues`, not this scope's to close.
- GitHub #370 - OPEN, actionable: it carries a 3,640-char analysis comment (M8). Same disposition.
- The reason #369/#370 read as undiagnosable is M7, and that reader gap is fixed here (Spec-AC-08): when a body has zero prose lines and the issue has comments, the excerpt is taken from the first comment and labelled `(from comment 1 of N)`. Leaving it would reproduce today's misreading on the next triage day.

### D5 — The 200-character cap does not survive; it becomes 500
`MAX_SUMMARY_LEN` moves from 200 to 500 in `aai-redact.mjs` (the single definition both passes consume). Ground: M4 — the realistic one-line descriptions that certify are 238-246 chars and are refused today as `over_length`; 200 holds a title, not a description. 500 holds "expected; observed; where" in one line and stays a headline (newlines remain refused, so this is not a multi-paragraph channel). Bounds: the spool line stays far under the PIPE_BUF 4096-byte atomic-append guard (`aai-friction.mjs:76,535`; a live record's structured part measures about 330 bytes); the leak surface grows 2.5x inside the SAME detector set (no rule changes); the `ghFailDetail` 200-char truncation (`aai-feedback-upsert.mjs`, a different constant for gh stderr) is NOT touched. RFC-0013 D2's "(<=200 char)" figure is superseded by this spec (no canonical REQ layer exists in this repository — `docs/canonical/` is absent — so there is no Delta block to write); FRICTION_PROTOCOL.md's two "<= 200" statements are updated by Spec-AC-10.

### D6 — Deliberately unchanged (stated so a reviewer does not read silence as oversight)
- The second mutating call (SPEC-0176 Spec-AC-06: a certified summary is also posted as a comment) stays as is. Under this spec every filed issue carries a certified description, so that comment will duplicate the body's blockquote on every publish. Collapsing it is a change to SPEC-0176's contract and to seven pinned tests (660/661/662/672 and the three-surface drift guard); it is left to a follow-up (suggested: `fu-upsert-comment-duplicates-body`) so this ride stays inside two review rounds.
- The redaction rules, the scoring formula, the publish/confirm gating and the wrapper's capture text are out of scope by the intake.
- No prompt asks an agent to write a summary at a hook point: D2 forbids unread agent prose, so there is nothing to add to the hook prompts and no prompt-diet cost from them.

### D7 — Downstream behaviour change, called out as such (the shipped-guards ride's convention)
On the next `/aai-update`, every downstream project gets: (1) `--publish <fp> --confirm` of a record without a certified description is REFUSED (it used to file); (2) prepare lists such clusters as `blocked_no_description`; (3) the summary cap rises 200 to 500 for both `record --promote` and the transmit pass; (4) `/aai-issues` excerpts show the first comment when the body is metadata-only. NO default flips. CHANGELOG carries one `## [unreleased] — fix: …` heading naming (1)-(4) (Spec-AC-10).

## Acceptance Criteria Mapping

- Maps to: CHANGE-0179 AC-001 (refuse or file actionable; never silently metadata-only) — Spec-AC-01, Spec-AC-02, Spec-AC-05
  - Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-upsert.sh 1301 1302 1305` exits 0; TEST-1301's positive control (same fixture plus `--description` files exactly once) proves the refusal arm is reachable.
- Maps to: CHANGE-0179 AC-002 (proved on the actual bytes reaching GitHub) — Spec-AC-03
  - Verification: the suite's deny-by-default `gh` stub records the exact `issue create` argv to `$GH_CALLS`; TEST-1303 asserts on that recorded line, never on a draft or a mock of the body.
- Maps to: CHANGE-0179 AC-003 (redaction unchanged; an uncertifiable text is dropped and the drop is named) — Spec-AC-04, Spec-AC-06
  - Verification: TEST-1304 (publish refuses a poisoned description naming the redactor class, zero gh calls), TEST-1306/1307 (the raised cap is the only change to what certifies; detectors unchanged, pinned by the untouched tests of test-aai-redact.sh).
- Maps to: CHANGE-0179 AC-004 (default posture stated in `.aai/feedback.yaml` with the trade-off) — Spec-AC-07
  - Verification: TEST-1308.
- Maps to: CHANGE-0179 AC-005 (live issues dispositioned, #338 and #339 named) — Spec-AC-09, plus the reader fix Spec-AC-08 that explains #369/#370
  - Verification: TEST-1311 (the table), TEST-1309/1310 (the reader); the live close evidence file named in D4.
- Maps to: the companion obligation (prompt corpus bytes) and the surfaces that describe the contract — Spec-AC-10
  - Verification: TEST-1312 plus `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` exit 0.

Spec-AC statements (WHEN/THEN; every one decided by one command and one observable):

- Spec-AC-01: WHEN `--publish <fp> --confirm` runs for a review_candidate whose representative carries no certified `summary` and no `--description` was given THEN the engine exits 2, stderr contains `refusing to file` and `no description` and `--description`, and the stub's call log is EMPTY (no `auth status`, no `search issues`, no `label list`, no `issue create`); AND WHEN the same fixture runs with `--description <file>` holding one clean line THEN exactly one `issue create` is recorded (positive control).
- Spec-AC-02: WHEN prepare runs over a cleared (dedup-clean, in-budget) cluster whose members carry no certified summary THEN its draft header reads `status: blocked_no_description`, stdout carries `blocked_no_description` and `not offered: no description` and `--description`, and carries NO `--publish` token for that fingerprint; AND WHEN a member carries a certified summary THEN the cluster is offered the runnable `--publish <fp> --confirm` line as today.
- Spec-AC-03: WHEN `--publish <fp> --confirm --description <file>` runs with a file holding `expected the gate to refuse` on line 1 and `observed it passed` on line 2 THEN the recorded `issue create` argv's `--body` begins with the blockquote `> expected the gate to refuse observed it passed` (lines joined by one space, trimmed) followed by the facts and the marker; the on-disk draft is not read (TEST-040's poisoned-draft invariance stays green unchanged); a `--description` without `--publish`, or naming an unreadable path, exits 2 naming the flag or the path.
- Spec-AC-04: WHEN the `--description` file contains `/Users/ales/.ssh/id_rsa` (or `AKIAABCDEFGHIJKLMNOP`) THEN the engine exits 2, stderr contains `refused by the redactor` and the reason class (`unsafe_char`, resp. `secret_aws`), and the call log is empty; AND WHEN the spool summary itself is poisoned and no `--description` is given THEN the publish refuses per Spec-AC-01 (it used to file prose-free — TEST-657(a)'s "issue still filed" arm is re-pinned to this).
- Spec-AC-05: WHEN a fingerprint has two members, member A with impact high and no summary and member B with impact low and a certified summary THEN `representative()` returns B, the prepared draft carries B's blockquote, and `--publish --confirm` without `--description` files once with that blockquote in the recorded body.
- Spec-AC-06: WHEN `redactSummary` receives a clean 500-character line THEN `ok: true`; WHEN 501 THEN `{ok:false, reason:'over_length'}`; AND WHEN `record --promote` receives a schema-v2 observation with a clean 450-character summary THEN the spool line carries that summary verbatim, `redaction_status: capture_clean`, and the line is under 4096 bytes (`wc -c` of the line, exclusive bound).
- Spec-AC-07: `.aai/feedback.yaml` keeps `summary_enabled: false` as the only `summary_enabled` line under `capture:`, and within the twelve lines preceding it the comment block names the literal tokens `PUBLIC`, `--promote`, `--description` and `trade-off`; `aai-friction.mjs record` against the shipped file with a summary and no `--promote` still prints `NOTE: summary dropped (reason: capture_gate)` on stderr and persists no summary.
- Spec-AC-08: `buildGhArgs()` emits `--json number,title,labels,body,url,comments`; WHEN an `--input` fixture issue has a body whose every non-empty line starts with `- ` or `<!--` and the issue carries one comment THEN its normalized `excerpt` starts with `(from comment 1 of 1) ` followed by the comment's sanitized, whitespace-collapsed text capped like a body; WHEN the body has a prose line THEN the excerpt is the body's as today; WHEN the body is metadata-only and `comments` is absent or empty THEN the excerpt is the body's as today; a comment containing a newline-forged `ISSUE #999` row or an ANSI escape produces no extra `ISSUE #` line and no escape byte in the text table.
- Spec-AC-09: this spec's `## Disposition of the live queue` table carries exactly the four rows `GitHub #338 - CLOSED by the owner 2026-09-30`, `GitHub #339 - CLOSED by this scope`, `GitHub #369 - OPEN`, `GitHub #370 - OPEN`, each with a reason cell; the evidence file `docs/ai/tdd/spec-friction-issues-arrive-without-a-description/issue-339-close.txt` holds the `gh issue view 339 --json state,comments` output showing `CLOSED` and a comment containing `spec-friction-issues-arrive-without-a-description`.
- Spec-AC-10: the four surfaces agree on the new contract: `node .aai/scripts/aai-feedback-upsert.mjs --help`, `.aai/SKILL_FEEDBACK_UPSERT.prompt.md`, `docs/USER_GUIDE.md` (the "Friction feedback loop" section) and `.aai/system/FRICTION_PROTOCOL.md` each contain `--description` and `no description`; the prompt and `--help` no longer contain the sentence `prose-free by design` paired with `after filing`; FRICTION_PROTOCOL.md contains `500` in both places that said `200` for the summary cap and no longer contains `<= 200`; `CHANGELOG.md` carries a `## [unreleased] — fix:` heading containing `--description`; and `tests/skills/test-aai-prompt-diet.sh` exits 0 with this ride's measured prompt byte delta credited 1:1 in `tests/skills/lib/prompt-diet-ledger.sh` under ref `friction-issues-arrive-without-a-description` if the delta is positive (the rewrite targets a non-positive delta; the ledger entry is mandatory only if the measurement says otherwise).

## Disposition of the live queue

| Issue | State after this scope | Reason |
|-------|------------------------|--------|
| GitHub #338 - CLOSED by the owner 2026-09-30 | closed, untouched | the owner closed it ("the mechanization this reported is shipped"); nothing left to do |
| GitHub #339 - CLOSED by this scope | closed with the fixed comment below | zero comments, zero prose lines, reporter-local evidence_ref; unreconstructable |
| GitHub #369 - OPEN | open, intake candidate | carries a full analysis comment (3,831 chars); actionable via /aai-issues once Spec-AC-08 reads comments |
| GitHub #370 - OPEN | open, intake candidate | carries a full analysis comment (3,640 chars); same |

Fixed close comment for #339 (posted verbatim by the orchestrator or owner; the spec id is the only variable text and it is a literal here):

```
Closing as unactionable. This issue was filed by the friction channel with a metadata-only body and never received a description; its evidence_ref (docs/ai/factory-report.html) is a reporter-local generated page, so nothing can be reconstructed. From spec-friction-issues-arrive-without-a-description onward the channel refuses to file a record that carries no certified description, so this class of issue is no longer produced. If the underlying SKILL_PR/close_pre_commit failure recurs, it will arrive with a description.
```

## Constitution deviations

None.

Article 5 (additive first) check: the publish refusal is a behaviour change at a public boundary and is explicit, documented in CHANGELOG and the four surfaces (D7, Spec-AC-10); the new flag and the raised cap are additive; no schema key is added or removed from the transmitted record. Article 4 (degrade and report): every refusal names its cause and the missing field. Article 1: no PASS without the recorded RED/GREEN evidence per row.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | publish of a description-less record refuses (exit 2, field named, zero gh calls); positive control files once with --description | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/upsert-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1301.log; mutation-TEST-1301.txt RED) | — | TEST-1301 |
| Spec-AC-02 | prepare marks a description-less cluster blocked_no_description and offers no --publish; a summary-carrying cluster is offered | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/upsert-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1302.log; mutation-TEST-1302.txt RED) | — | TEST-1302 |
| Spec-AC-03 | --description file renders as the leading blockquote in the recorded create argv; lines joined; draft never read; flag misuse exits 2 | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/upsert-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1303.log; mutation-TEST-1303.txt RED) | — | TEST-1303 |
| Spec-AC-04 | a redactor-refused description is refused naming the class, zero gh calls; a poisoned spool summary no longer files prose-free | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/upsert-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1304.log; mutation-TEST-1304.txt RED) | — | TEST-1304 |
| Spec-AC-05 | representative() prefers a summary-carrying member; its blockquote is what is filed | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/upsert-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1305.log; mutation-TEST-1305.txt RED) | — | TEST-1305 |
| Spec-AC-06 | MAX_SUMMARY_LEN is 500 for both passes; a 450-char promoted summary persists under the 4096-byte line bound | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/redact-suite.log and docs/ai/tdd/spec-friction-issues-arrive-without-a-description/friction-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1306.log, docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1307.log; mutation-TEST-1306.txt and mutation-TEST-1307.txt RED) | — | TEST-1306, TEST-1307 |
| Spec-AC-07 | feedback.yaml keeps the default false and states the posture tokens next to it; the shipped gate still drops an unpromoted summary with a NOTE | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/friction-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1308.log; mutation-TEST-1308.txt RED) | — | TEST-1308 |
| Spec-AC-08 | aai-issues fetches comments and excerpts the first comment for a metadata-only body, sanitized; body-prose and no-comment cases unchanged | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/issues-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1309.log, docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1310.log; mutation-TEST-1309.txt and mutation-TEST-1310.txt RED) | — | TEST-1309, TEST-1310 |
| Spec-AC-09 | the disposition table names the four issues with their states; #339 close evidence file present | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/upsert-suite.log (control: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/control-TEST-1311.log; mutation-TEST-1311.txt RED; the live #339 close evidence file is an orchestrator action) | — | TEST-1311; the live close is an orchestrator action |
| Spec-AC-10 | help, prompt, USER_GUIDE, FRICTION_PROTOCOL and CHANGELOG state the contract; stale prose-free sentence gone; prompt-diet suite green | done | docs/ai/tdd/spec-friction-issues-arrive-without-a-description/upsert-suite.log and docs/ai/tdd/spec-friction-issues-arrive-without-a-description/prompt-diet-suite.log (RED: docs/ai/tdd/spec-friction-issues-arrive-without-a-description/red-TEST-1312.log; mutation-TEST-1312.txt RED; prompt 3849 to 3705 B, delta -144 B, no ledger entry needed) | — | TEST-1312 |

Status values: planned | implementing | done | deferred | blocked | rejected
- planned: AC defined, no implementation started
- implementing: work in flight; not allowed at PASS claim time
- done: implementation complete; requires non-empty Evidence naming a docs/ai/tdd artifact at hand-off (a RUN_ID or suite output path may accompany it, never replace it) — never a commit SHA or PR reference here; the delivery citation is written by the close flip, not at hand-off (see .aai/ROLE_COMMON.md PRE-HANDOFF AC-TABLE RECONCILIATION)
- deferred: explicitly postponed; requires Review-By in the future (minimum +14 days) + Notes naming target doc or reason
- blocked: implementation cannot proceed; requires Review-By + Notes naming blocker
- rejected: AC will not be implemented; requires Notes with rationale; no Review-By needed (terminal)

Gate behavior (enforced by .aai/VALIDATION.prompt.md when this column is present):
- Any planned/implementing AC blocks PASS
- Any done AC with empty Evidence blocks PASS
- Any deferred/blocked AC anywhere in the repo with Review-By in the past blocks any PASS until re-decided
- Review-By must be at least 14 days in the future when set

## Implementation plan

Components affected (the review scope, exhaustively):
- `.aai/scripts/aai-feedback-upsert.mjs` — `parseArgs` gains `--description <path>` (the SAME `if (t === '--report' || …)` value-taking list; usage error when given without `--publish`); a new `certifiedDescription(rep, args)` returns `{ok:true, value}` from the `--description` file (lines joined by one space, trimmed, then `const cert = redactSummary(joined);`, guarded `if (!cert.ok) {` → `{ok:false, reason: cert.reason, source:'description'}`), else from `rep.summary` through the same certification, else `{ok:false, reason:'no_description'}`; the publish path calls it FIRST after the fingerprint shape check and before `ghAuthState()`, with the single guard line `if (!desc.ok) {` that writes the D3 refusal and exits 2; `buildPayload` takes the certified value as its blockquote (precedence: `--description` over `rep.summary`); `prepare()` computes `hasDescription` from `certifiedDescription(rep, {})` and the status ternary gains `: !hasDescription ? 'blocked_no_description'` BEFORE the `'new'` arm (first occurrence of the literal in the file is this ternary); `BLOCK_REASON.blocked_no_description` carries the D3 prepare text; `representative()` filters `const withSummary = members.filter((o) => typeof o.summary === 'string' && o.summary.length > 0);` and reduces over `const pool = withSummary.length ? withSummary : members;`; `HELP` rewritten per Spec-AC-10.
- `.aai/scripts/lib/aai-redact.mjs` — `export const MAX_SUMMARY_LEN = 500;` and its comment.
- `.aai/scripts/aai-friction.mjs` — no logic change; the HELP/comment lines that say 200 are updated (the cap is consumed by name at `:513`).
- `.aai/scripts/aai-issues.mjs` — `buildGhArgs` field list gains `,comments`; `normalizeIssues` computes `proseLineCount(body)` (non-empty lines not starting with `- ` and not starting with `<!--`) and, when `proseLineCount(body) === 0 && comments.length > 0`, sets `excerpt` to `(from comment 1 of N) ` + `excerptOf(firstComment.body)`; both helpers exported for the unit rows; the header comment's fixture shape gains the optional `comments` array.
- `.aai/feedback.yaml` — the `capture:` comment block (Spec-AC-07 tokens); the value line unchanged.
- `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` — the "Safety model" bullet and the "After a confirmed publish" section rewritten to the new contract (target: non-positive byte delta; `wc -c` before/after measured under plain bash and recorded in the TDD log).
- `.aai/system/FRICTION_PROTOCOL.md` — the two `<= 200` statements become 500; one paragraph on the publish-time `--description` path and the no-description refusal.
- `docs/USER_GUIDE.md` — the "Friction feedback loop" steps 4-5 state the refusal and `--description`.
- `CHANGELOG.md` — one `## [unreleased] — fix: a friction issue carries a description or is not filed (goodwind-cz/aai#339)` heading with the D7 list.
- `tests/skills/lib/prompt-diet-ledger.sh` — one `JUSTIFIED_ADDITIONS` entry ONLY if the measured prompt delta is positive.
- Tests: `tests/skills/test-aai-feedback-upsert.sh` (new 1301-1305, 1311, 1312; shared fixtures `setup()`/`seed_single_candidate()` gain a certified `summary` so every existing create-asserting test keeps its meaning; re-pinned by name: TEST-020 cleared arm, TEST-036, TEST-045, TEST-046, TEST-047, TEST-657(a), TEST-661(a) — each keeps its test id and gains a one-line comment naming this spec), `tests/skills/test-aai-redact.sh` (new 1306), `tests/skills/test-aai-friction.sh` (new 1307, 1308; TEST-658(b)'s 201-char `over_length` probe becomes 501), `tests/skills/test-aai-issues.sh` (new 1309, 1310; TEST-009's field-list pin re-pinned).

Data flows and seams (each crossed by a test, never mocked at the boundary):
- S1 spool `summary` → `representative()` → `buildPayload` → `gh issue create --body` (TEST-1305 produces on the spool side and asserts on the recorded argv).
- S2 `--description` file → join → `redactSummary` → blockquote → recorded argv (TEST-1303, TEST-1304).
- S3 the refusal → zero `gh` calls (TEST-1301/1304 assert the EMPTY call log with a positive control in the same test).
- S4 `MAX_SUMMARY_LEN` → capture pass (TEST-1307 drives `record --promote`) and transmit pass (TEST-1306 drives the pure function; the transmit pass uses the default argument, pinned by the untouched import).
- S5 `gh issue list --json …,comments` → `normalizeIssues` → text table / `--json` (TEST-1309 via `--input` fixture with a `comments` array, TEST-1310 pins the argv).
- S6 the four prose surfaces + CHANGELOG (TEST-1312 reads each file).

Edge cases: `--description` file empty → redactor `empty` → refuse; file with only whitespace → same; CRLF file → lines joined, `\r` stripped by the join (split on `/\r?\n/`); `--description` plus a spool summary → description wins, summary not appended; a cluster whose representative has a summary that the transmit pass REFUSES and no `--description` → refuse naming the redactor class (never file prose-free); `comments` absent from an old `--input` fixture → treated as empty; comment author never printed.

## Test Plan

| Test ID   | Spec-AC    | Type        | File path (expected)                          | Description | Mutation | Status  |
|-----------|------------|-------------|-----------------------------------------------|-------------|----------|---------|
| TEST-1301 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-upsert.sh | test_1301_publish_refuses_without_description — seed_single_candidate with the summary stripped; `--publish --confirm` exits 2, stderr carries `refusing to file`, `no description`, `--description`; `$GH_CALLS` is empty; positive control: same fixture plus `--description` (one clean line) records exactly one `issue create`. | sed:s/if \(!desc\.ok\) \{/if (false) {/ | green |
| TEST-1302 | Spec-AC-02 | integration | tests/skills/test-aai-feedback-upsert.sh | test_1302_prepare_blocks_without_description — prepare over a summary-less cleared cluster: draft header `status: blocked_no_description`, stdout carries `not offered: no description` and `--description` and no `--publish v1:aaaa…` token; the summary-carrying fixture is offered the runnable command. | sed:s/'blocked_no_description'/'new'/ | green |
| TEST-1303 | Spec-AC-03 | integration | tests/skills/test-aai-feedback-upsert.sh | test_1303_description_file_becomes_blockquote — a two-line description file; the recorded `issue create` line carries ` > expected the gate to refuse observed it passed` before `- failure_class:` and the marker after it; `--description` without `--publish` exits 2 naming the flag; an unreadable path exits 2 naming it; TEST-040 re-run inside this test stays byte-identical. | sed:s/t === '--description'/t === '--descriptionX'/ | green |
| TEST-1304 | Spec-AC-04 | integration | tests/skills/test-aai-feedback-upsert.sh | test_1304_poisoned_description_refused — `--description` holding `/Users/ales/.ssh/id_rsa` exits 2 with `refused by the redactor` and `unsafe_char`, empty call log; `AKIAABCDEFGHIJKLMNOP` names `secret_aws`; a poisoned spool summary with no `--description` refuses per Spec-AC-01 (creates=0) — positive control in the same test: a clean description files once. | sed:s/const cert = redactSummary\(joined\);/const cert = { ok: true, value: joined };/ | green |
| TEST-1305 | Spec-AC-05 | integration | tests/skills/test-aai-feedback-upsert.sh | test_1305_representative_prefers_summary — two spool members of one fingerprint (A impact high no summary, B impact low certified summary); prepare draft carries B's blockquote; `--publish --confirm` without `--description` files once and the recorded body carries B's text. | sed:s/withSummary\.length \? withSummary : members/members/ | green |
| TEST-1306 | Spec-AC-06 | unit        | tests/skills/test-aai-redact.sh | assert_ok on a clean 500-char line, assert_drop over_length at 501; existing detector cases untouched. | sed:s/MAX_SUMMARY_LEN = 500/MAX_SUMMARY_LEN = 200/ | green |
| TEST-1307 | Spec-AC-06 | integration | tests/skills/test-aai-friction.sh | test_1307_promote_persists_450_chars — `record --promote` with a clean 450-char summary: spool line carries it verbatim, `redaction_status: capture_clean`, `wc -c` of the line is under 4096; TEST-658(b)'s over_length probe moved to 501 chars in the same edit. | sed:s/maxLen: MAX_SUMMARY_LEN/maxLen: 200/ | green |
| TEST-1308 | Spec-AC-07 | integration | tests/skills/test-aai-friction.sh | test_1308_shipped_default_and_posture — the shipped `.aai/feedback.yaml` has exactly one `summary_enabled:` line under `capture:` and it is `false`; the twelve preceding lines contain `PUBLIC`, `--promote`, `--description`, `trade-off`; `record` against the shipped file with a summary and no `--promote` prints the capture_gate NOTE and persists no summary. | sed:s/summary_enabled: false/summary_enabled: true/ | green |
| TEST-1309 | Spec-AC-08 | integration | tests/skills/test-aai-issues.sh | test_1309_excerpt_from_first_comment — `--input` fixture: issue 1 metadata-only body with one comment, issue 2 prose body with a comment, issue 3 metadata-only with no comments; `--json` excerpts: 1 starts `(from comment 1 of 1) `, 2 is the body's, 3 is the body's; a comment with a forged `ISSUE #999` line and an ANSI escape yields exactly three `ISSUE #` rows and no escape byte. | sed:s/proseLineCount\(body\) === 0/false/ | green |
| TEST-1310 | Spec-AC-08 | unit        | tests/skills/test-aai-issues.sh | test_1310_gh_args_include_comments — `buildGhArgs()` output contains `number,title,labels,body,url,comments`; TEST-009 re-pinned to the same list. | sed:s/number,title,labels,body,url,comments/number,title,labels,body,url/ | green |
| TEST-1311 | Spec-AC-09 | unit        | tests/skills/test-aai-feedback-upsert.sh | test_1311_disposition_table_pinned — the spec file's Disposition table carries the four exact `GitHub #NNN - …` cells and each row has a non-empty reason cell; `docs/ai/tdd/spec-friction-issues-arrive-without-a-description/issue-339-close.txt` exists and contains `CLOSED` (skipped with a named SKIP line when the evidence tree is absent, as on CI). | sed:s/#339 - CLOSED by this scope/#339 - OPEN/ | green |
| TEST-1312 | Spec-AC-10 | integration | tests/skills/test-aai-feedback-upsert.sh | test_1312_surfaces_state_the_contract — `--help`, the prompt, USER_GUIDE's friction section and FRICTION_PROTOCOL each contain `--description` and `no description`; help and prompt no longer contain `prose-free by design` together with `after filing`; FRICTION_PROTOCOL contains no `<= 200`; CHANGELOG has a `## [unreleased] — fix:` heading containing `--description`; then runs `tests/skills/test-aai-prompt-diet.sh` and requires exit 0. | sed:s/--description/--describe/ | green |

Test status values: pending → red → green
- pending: test not yet written
- red: test written and verified failing (TDD RED phase)
- green: test passes with implementation

Notes:
- Every Spec-AC has at least one TEST-xxx entry; ids are stable after freeze.
- Mutation targets, by row: TEST-1301..1305 `.aai/scripts/aai-feedback-upsert.mjs`; TEST-1306 `.aai/scripts/lib/aai-redact.mjs`; TEST-1307 `.aai/scripts/aai-friction.mjs`; TEST-1308 `.aai/feedback.yaml`; TEST-1309/1310 `.aai/scripts/aai-issues.mjs`; TEST-1311 this spec file; TEST-1312 `.aai/SKILL_FEEDBACK_UPSERT.prompt.md`. The identifiers the cells anchor on (`desc.ok`, `cert`, `joined`, `withSummary`, `proseLineCount`, the literal `blocked_no_description` first occurring in the status ternary) are part of the contract: an implementation that renames them must amend the cell via `spec-amend.mjs`, never leave a cell that no longer matches (the uncomparable ratchet reads them).
- RED first: each new test function is run on the pre-change tree and observed failing before the implementation lands; the record lives at `docs/ai/tdd/spec-friction-issues-arrive-without-a-description/mutation-<TEST-id>.txt` via `mutation-run.mjs`. TEST-1311 cannot go RED on the pre-change tree for the table (the table is in this spec already) — its evidence is the mutation control plus the evidence-file arm.
- Re-pinned existing tests keep their ids: U-020 (cleared arm uses the summary-carrying fixture), U-036 (success line no longer states prose-free; comment command still printed only when no certified prose was posted), U-045/U-046/U-047 (new tokens), U-657(a) and U-661(a) (prose-free now refuses: creates=0, exit 2), F-658(b) (501), I-009 (field list). None is deleted; each gains a one-line comment naming this spec id.

## Verification
- Suites, run from the repository root through the canonical wrapper:
  - `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-upsert.sh` → exit 0
  - `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-redact.sh` → exit 0
  - `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-friction.sh` → exit 0
  - `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-issues.sh` → exit 0
  - `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` → exit 0
  - `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-friction-capture-points.sh` and `test-aai-feedback-triage.sh` → exit 0 (regression; untouched by this scope, they read the same spool shape)
- Mutation gate: `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0203-spec-friction-issues-arrive-without-a-description.md` → every row KILLED; `node .aai/scripts/mutation-gate.mjs --spec <path>` → PASS.
- Live (orchestrator, after merge or at the PR ceremony, never a subagent): `gh issue close 339 --repo goodwind-cz/aai --comment "<the fixed text>"`, then `gh issue view 339 --repo goodwind-cz/aai --json state,comments > docs/ai/tdd/spec-friction-issues-arrive-without-a-description/issue-339-close.txt`; `node .aai/scripts/aai-issues.mjs --json` on the live repository shows #369/#370 excerpts starting `(from comment 1 of 1)`.
- Evidence artifacts: the five suite logs under `docs/ai/tdd/spec-friction-issues-arrive-without-a-description/`, the twelve mutation records, the issue-339 evidence file, the `wc -c` before/after of the prompt.
- PASS criteria: all TEST-1301..1312 green AND all Spec-AC in a terminal status AND mutation-gate PASS.
- Review scope (explicit paths): `.aai/scripts/aai-feedback-upsert.mjs`, `.aai/scripts/lib/aai-redact.mjs`, `.aai/scripts/aai-friction.mjs`, `.aai/scripts/aai-issues.mjs`, `.aai/feedback.yaml`, `.aai/SKILL_FEEDBACK_UPSERT.prompt.md`, `.aai/system/FRICTION_PROTOCOL.md`, `docs/USER_GUIDE.md`, `CHANGELOG.md`, `tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/test-aai-feedback-upsert.sh`, `tests/skills/test-aai-redact.sh`, `tests/skills/test-aai-friction.sh`, `tests/skills/test-aai-issues.sh`, `docs/specs/SPEC-0203-spec-friction-issues-arrive-without-a-description.md`.

## Residual risks (written down, not left out)
- R1. A certified description can still carry a bare hostname, a customer name or a project code word written as an ordinary word (the accepted RFC-0013 residual); the field is now 2.5x longer and present on EVERY filed issue. The guard is the human who writes and reads it and types `--confirm`; no automated test can cross this seam.
- R2. The allow-list refuses `/`, `=`, backticks and newlines, so a description naming `hooks/merge-guard.sh` or `refuses=true` is refused (M4). Operators will rephrase or fall back to the hand-posted comment. Redaction rules are out of scope; suggested follow-up `fu-redactor-forbids-relative-paths`.
- R3. Every filed issue now carries the description twice (blockquote plus the SPEC-0176 comment) — D6; suggested follow-up `fu-upsert-comment-duplicates-body`.
- R4. `gh issue list --json comments` returns every comment of every listed issue; bounded by `--limit`, and comment text is untrusted data sanitized by the same `sanitizeLine`; authors are never printed.
- R5. The close of #339 is a public write done outside the suite; TEST-1311 pins the spec's table and the presence of the evidence file, not the live state.
- R6. Adding a certified summary to the upsert suite's shared fixture makes the SPEC-0176 comment call fire in tests that previously saw one mutating call; any test asserting a call count must be re-pinned by name (never by loosening the deny-by-default stub).

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: friction-issues-arrive-without-a-description
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/spec-friction-issues-arrive-without-a-description/…)
- commit SHA or diff range when available

### Evidence by strategy

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
