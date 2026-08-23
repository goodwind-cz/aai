# Code Review (re-review) — the-subagent-contract-omits-the-hazards

Narrow re-review of the remediation commit only. Full review at `f4b6f3f` is
`docs/ai/reviews/review-20260823T171026Z-the-subagent-contract-omits-the-hazards.md`
(verdict fail, one blocker). This pass checks only `git diff f4b6f3f..c044346`
(single commit `c044346 fix(learned): a dated record is history, not advice to
be rewritten`) against that blocker and its three sibling follow-ups plus the
allowlist recount. The rest of the change is not re-reviewed.

```yaml
review:
  scope: f4b6f3f...c044346 (branch feat/contract-carries-the-hazards)
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-spec-lint.sh, line: 1731-1733,
          issue: "Comment beside the TENTH allowlist-tax group still says the pass line was 'corrected here to a re-counted 31 paths across 11 groups'; c044346 added .aai/SUBAGENT_PROTOCOL.md to that group and bumped the log_pass string to 32, but did not update the comment that justifies the number.",
          failure_scenario: "A future reader re-derives the expected count from the comment (31) instead of recounting the case block, disagrees with the live log_pass (32), and either 'fixes' the correct pass line back to 31 or loses time reconciling a self-inflicted contradiction." }
  overall: pass
```

## What was checked (four corrections + one recount, per dispatch)

**1. THE BLOCKER — LEARNED.md's falsified historical record.** Diffed
`docs/knowledge/LEARNED.md` at `f46502e` (pre-defect) against `c044346`
byte-for-byte for the Session 2026-07-17 entry. The restored sentence —
`main — reproduced via git-stash comparison before touching anything (net
reduction 28187 bytes < 28672 required, ~485B short at c144736/PR #92).` — is
identical to `f46502e`. The new parenthetical note beside it ("*(That is what
was done on the day and the record stands. Do not repeat the method: stashing
reverts the SHARED working tree and HAZ-RESTORE now prohibits it. Reproduce
against a disposable worktree cut from the BASE ref instead...)*") explicitly
affirms the historical method rather than re-asserting the false claim in
softer words — it uses "now prohibits" (present tense) rather than implying
the prohibition existed in July, and opens with "the record stands." Confirmed
true. `fu-learned-rewrites-past-method` (already `done` in the ledger) is
correctly closed.

**2. `fu-learned-baseline-head-not-main` — both sites.** Line 37-42 (Session
2026-07-15/16) and the line 55-60 parenthetical (Session 2026-07-17) both now
name the BASE ref explicitly via a `main` example and explain why the default
HEAD is wrong on a working branch ("the default HEAD would give you your own
branch" / "on a working branch is the role's own commits"). Verified live:
ran `git worktree add --detach <scratch>` with no commit-ish on this checkout
(currently on `feat/contract-carries-the-hazards` at `c044346`) — the new
worktree came up detached at `c044346`, the branch tip, not `main`. Both
explanations are correct. `fu-learned-baseline-head-not-main` (`done`) is
correctly closed.

**3. `fu-learned-worktree-rule-overbroad`.** Line 146-150 now reads:
"HAZ-RESTORE ... prohibits those COMMANDS outright — it does not ban inline
work, which stays a supported mode." Checked against
`.aai/SUBAGENT_CONTRACT.md:13-14` (HAZ-RESTORE's literal text): "no restoring
git command on a tracked file (`git checkout --`, `git restore`, `git
stash`/`pop`, `git reset --hard`): mutate a COPY instead." The new LEARNED.md
text matches this scope exactly — commands, not inline work — and is
consistent with this scope's own spec (`worktree recommendation: not_needed`,
`user decision: inline`), which is the fact pattern the prior review used to
show the old text was wrong. `fu-learned-worktree-rule-overbroad` (`done`) is
correctly closed. One observation, not filed: the added clause "a role that
needs to mutate git state needs a disposable worktree" is elaboration beyond
HAZ-RESTORE's literal "mutate a COPY instead" (a worktree is one way to get a
copy, not the only one) — but for actual git-mutating commands a working tree
of some kind is required, so the elaboration is accurate in substance and is
not a repeat of the overbroad pattern.

**4. `fu-protocol-states-stale-60-line-cap`.** `.aai/SUBAGENT_PROTOCOL.md:6`
now reads "the ~85-line duty sheet". `wc -l .aai/SUBAGENT_CONTRACT.md` = 84
(the CONTRACT itself is untouched by this diff — only PROTOCOL.md,
LEARNED.md, and the spec-lint allowlist changed). "~85" overshoots the exact
count by one line (1.2%), against three other call sites
(`test_080`/TEST-010/TEST-020) that all cite the exact figure "84". This is
not a repeat of the prior 40%-stale defect — "~" signals an approximation and
84 rounds to "roughly 85" without being false — so it does not rise to a
finding. If shipping fresh, "~84-line" would be tighter and would match the
three exact call sites, but "~85-line" is not a false claim.

**5. Spec-lint allowlist recount, 31 → 32.** Recounted the eleven case groups
in `test_clarify_011_no_new_ceremony` (lines 1672-1734) independently:
3+2+4+5+1+1+1+2+10+1+2 = 32 paths across 11 groups, matching the shipped
`log_pass` string exactly. The recount itself is correct. Along the way, found
the NON-BLOCKING finding above: the comment justifying that same group (lines
1731-1733) still says the correction landed on "31 paths", one behind the
line it decorates.

## Verdict

**pass.** The one BLOCKING finding from the prior round is fixed and verified
true against the git history it describes, HAZ-RESTORE's literal wording, and
`git worktree add --detach`'s measured default. The allowlist recount is
independently confirmed exact. One new NON-BLOCKING, cosmetic finding filed
(`fu-test011-comment-count-stale`, P3) — a comment now disagrees with the
code it sits beside by one path; no suite enforces the comment text and it has
no runtime effect.

## Evidence

| Command | rc | Result |
|---|---|---|
| `git log --oneline f4b6f3f..c044346` | 0 | one commit: `c044346 fix(learned): a dated record is history, not advice to be rewritten` |
| `git diff f4b6f3f..c044346 -- docs/knowledge/LEARNED.md .aai/SUBAGENT_PROTOCOL.md tests/skills/test-aai-spec-lint.sh` | 0 | reviewed in full |
| `git show f46502e:docs/knowledge/LEARNED.md` vs current, Session 2026-07-17 entry | — | restored sentence byte-identical to `f46502e` |
| `wc -l .aai/SUBAGENT_CONTRACT.md` | 0 | 84 |
| `grep -n "HAZ-RESTORE" -A 6 .aai/SUBAGENT_CONTRACT.md` | 0 | "no restoring git command on a tracked file (...): mutate a COPY instead" |
| `git worktree add --detach <scratch>` (no commit-ish) on `feat/contract-carries-the-hazards` | 0 | "Preparing worktree (detached HEAD c044346)" — confirms default is HEAD/branch tip, not main |
| manual recount of `test_clarify_011_no_new_ceremony` case block | — | 11 groups, 32 paths, matches shipped `log_pass` |
| `node .aai/scripts/follow-ups.mjs list --ref the-subagent-contract-omits-the-hazards --status all` | 0 | confirms `fu-learned-rewrites-past-method`, `fu-learned-baseline-head-not-main`, `fu-learned-worktree-rule-overbroad`, `fu-protocol-states-stale-60-line-cap` all already `done` |
| `node .aai/scripts/follow-ups.mjs add --id fu-test011-comment-count-stale ...` then `list --status open` | 0 | filed and read back |

## Scope note

Per dispatch, this is a narrow re-review of the remediation commit only. The
full spec-compliance AC walk, the shell-correctness sweep, the HAZ-arm
mechanics, and the P1 backstop discussion from the prior round are not
repeated here — they were not touched by `c044346` and the prior review's
`pass`/`fail` calls on those axes stand.
