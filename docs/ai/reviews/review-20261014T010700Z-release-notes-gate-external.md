# External review response — release-notes-gate (PR 465)

Reviewed head before this response: `b1191035`. Threads fetched from
`gh api repos/goodwind-cz/aai/pulls/465/comments` and `gh pr view 465 --json reviews`.

| Thread | Author | Disposition |
| --- | --- | --- |
| `4265591933` P1, `.aai/scripts/release-notes-gate.mjs` | chatgpt-codex-connector | real |
| `4265591937` P2, `.aai/SKILL_PR.prompt.md` | chatgpt-codex-connector | real |
| `4265629042`, `.github/workflows/skill-suite.yml` `edited` | Copilot | disputed |

P1. Two commit endpoints treated a later base-only change as part of the
pull request. A docs-only head was refused because a base-only shipped file
appeared in the diff, and a note deleted on the base counted as a note the
head added. The range is now the merge base through the head. TEST-005 failed
on the previous module (`docs/ai/tdd/release-notes-gate-merge-base-red.log`,
failures=2) and passes after the change
(`docs/ai/tdd/release-notes-gate-merge-base-green.log`, failures=0).

P2. Step 3b told the ceremony to re-run the staged check after any body
change. After the commit that re-run sees an empty index and reports an
exemption. The staged check now applies only while the change is still
staged. The body submitted to `gh pr create`, including its Lane section, is
checked with `--base` and `--head`. Prompt growth is 32753 to 32833 bytes,
credited as `release-notes-gate-merge-base`.

Copilot. Adding `edited` re-runs the whole workflow. Guarding the other jobs
with `github.event.action != 'edited'` would skip the checks `main` requires:
`skill test suite (tests/skills/, via test-framework.sh)`, `self-hosting smoke`,
and `doc-numbering guards`. A skipped required check does not satisfy branch
protection. The cost of a body-edit rerun stays the accepted residual from
`review-20261013T235645Z-release-notes-gate.md`. Resolution stays with the reviewer.

Verdict: both prior dual verdicts still pass. These three threads are the
only external findings on this head.
