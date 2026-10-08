# PR434 exhausted-package disposition

Recorded by: orchestrator
Observed UTC: 2026-10-08T02:48:44Z
Source HEAD: 1691558c034e13258a31b8288df5642f6263a8cb
Parent ref: pr-capability-preflight

## Accepted result and boundary

The checked independent full-scope review review-20261008T023456Z-pr434-scp.md is FAIL for spec compliance and code quality. Actual role02:34:56–02:46:23Z687seconds; root audit completed before STATE merge. Typed checker exits0. Manifest SHA2798c645c2d24445bf91606fcfb96dd449d2f04461584f08db55151b54421fb0 has34 verified rows plus itself,35 files. Current SCP/SSH authority repairs pass8/8 local rows and four compatibility suites; this does not override the independent failures.

B1 independently reproduces malformed https://github.com:bad/Org/Repo.git accepted as generic capability-not-applicable while real Git rejects its nonnumeric port. B2 independently reproduces a case-equivalent GitHub provider result rejected after three successful provider probes; the primary provider contract makes owner/name case-insensitive. They confirm actual external threads4213850825 and4213850832. All8 platform threads remain unresolved;6 older findings are reviewed fixed but final closing replies/resolution sweep have not occurred.

Current native Linux157PASS0FAIL0SKIP and WSL153PASS0FAIL4SKIP are SUCCESS. Native Windows remains pending in the independent sealed observation. Full run37718516740 is FAILURE104=97PASS6FAIL1SKIP. Six lifecycle-dependent failures remain observed. No metadata closure, ValidationPASS, sweep completion or merge is authorized. Existing unsigned fu-amend-spec-pr-capability-preflight remains owed.

## Exhausted-package decision

The raw-ssh-path-identity package has now completed both independent finding-bearing checks: review-20261008T015150Z-pr434-raw.md at525a and review-20261008T023456Z-pr434-scp.md at1691. DECISION-pr434-raw-ssh-path.md explicitly prohibits unlimited relabeling; no third implicit maker/checker cycle or numerical cap waiver is used. Preserve actual FAIL and park the parent scope pending a concrete split decision.

Canonical .aai/AGENTS.md operator rule3: “Two review rounds max. A third finding-bearing round means the ride was cut wrong: split it, do not re-verify it.” SKILL_LOOP stop2b: human_input.required true means “A human must answer before the loop resumes.” This is a scope/review-cap stop, not a sandbox auto-review rejection and not a request for merge authorization.

## Reviewable next-step menu

Recommended: split the remaining existing-requirement repair into two separately scoped changes, preserving PR434 and all historical evidence. Proposed ref pr-generic-url-validity covers scheme parse refusal before generic fallback in pr-preflight.mjs and focused existing matrix controls: malformed URL refuses with zero provider calls; lawful unrecognized host and local routes still succeed. Proposed ref pr-github-case-identity covers case-insensitive GitHub owner/name comparisons and their spec amendment/test mapping: case-equivalent input/remote/provider successes, truly different-repository negatives, exact effective fetch/push endpoint equality retained. Both require their own explicit source scope, independent review and evidence; neither silently restarts the exhausted parent package. No new provider capability, live credentials, global config, worktree or merge authorization is proposed. Owner chooses the split disposition before dispatch.

Alternative: leave PR434 parked and unmerged.

STATE remains ReviewFAIL, Validationnot_run and parent remediation/blocked with human_input required. Main checkout receives only the human-input mirror and keeps its worktree pointer. No closed lifecycle event, gate waiver, false done status, destructive reset or worktree archive. New review and this disposition are staged explicitly as durable local evidence; they are not falsely called pushed artifacts. Runtime metrics remain recorded without invented model/usage and are not flushed as a completed ride.

## Final runtime checkpoint

The accepted STATE merge records independent ReviewFAIL and Validationnot_run. Canonical orchestration-dispatch --human --confirm returned exit3, rule2/no_action, reason human_input_required; no role was dispatched. Docs scope lock was released and the original session lock92228 was explicitly released after its ordinary sandbox attempt refused EPERM; the narrowly scoped escalation succeeded. This was a filesystem permission boundary, not an automatic approval-review rejection. Worktree remains intact and unmerged.
