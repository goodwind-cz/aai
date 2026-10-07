# Focused maker remediation — independent gates pending

Scope `pr-capability-preflight`; base HEAD `609832744c202805234da8a09e40c5d3bb171308`. Started 2026-10-07T21:13:58Z; ended 2026-10-07T21:29:46Z; 948 seconds. Requested canonical standard/gpt5 unavailable; actual model unknown. Canonical Remediation prompt hash `06c890067c284f9f361c6818b6159ff052cfbc395574b962598b2e930d2ee620`. Trigger: last_validation fail; code_review not_run. This is maker fix verification, with no Validation or Review verdict.

The unsplittable push-destination readiness hazard is handled under the root's ONCE-applied standing owner decision (a), Validation PROCESS5c2, recorded at 2026-10-07T21:12:43Z. It authorizes one focused remediation/recheck. No second extension or gate waiver is authorized.

## B1 — actual push destination

The current-head external finding at https://github.com/goodwind-cz/aai/pull/434#discussion_r4211969090 is real. The independent real-Git reproduction and new TEST001 regression both demonstrated fetch GitHub READ_VERIFIED despite divergent Azure pushurl, before any product edit. RED observed expected refusal exit2 versus actual0. No provider write or push was executed.

`pr-preflight.mjs` now reads Git's effective fetch and push destinations with `remote get-url --all` and `--push --all`. Exactly one nonempty destination on each side and byte equality are required before provider reads. Git expands insteadOf/pushInsteadOf. Divergent endpoints, duplicate or distinct multiple push URLs, multiple fetch URLs, and pushInsteadOf rewrites refuse with sanitized IDENTITY_INVALID / git.push-destination. Alternate endpoint spellings conservatively require configuration repair. Ordinary remotes and a single explicitly matching pushurl succeed. Explicit selected CLI remote and true null local-only fallback remain supported; ceremony origin binding remains intact. Existing TEST001 carries these real-Git controls. No prompt growth, global gate policy or tool-engine edits.

## B2 — outer fixture timeout

The original WSL job113013349041 failed the four-second whole-CLI spawnSync bound in TEST007; raw evidence did not identify mode or probe. This was not an observed product PROBE_TIMEOUT. A delayed real-Git success fixture reproduced ETIMEDOUT against that old bound. Each probe may lawfully take ten seconds, and seven identity probes plus three provider probes are sequential.

The fixture now derives its finite outer bound as ten per-probe budgets plus a five-second startup allowance (default105000ms). Hang controls retain their4000ms outer cap. Bounded diagnostics identify test, invocation, mode, timings, error/signal, Git count, last three provider step names and stdout size without raw URLs or credentials. TEST007 delayed success crossed the old bound at5909ms with seven Git probes and all three providers. TEST004 remains strict: provider timeout1000ms, actual124 at1530ms, within3000ms, child gone and later0. Full preflight8/8 and platform full suite exit0.

Exact609 Windows native5.1/7 and exact609 WSL rerun each show Pester152pass/0fail/4existing named POSIX skips and TEST007/008 success. Their complete logs are preserved beside the original failure. They prove609 only; corrected-source native CI remains pending.

## B3 — lifecycle projection, actual aggregate still FAIL

Original full104 remains97PASS/6FAIL/1SKIP(aai-state absent), with all six failures sharing NEEDS-TRIAGE(1), probable-false-open on this reopened scope. Complete original job logs are retained. Root cause: date-only METRICS flush is interpreted by metricsFlushDateToTs as23:59:59.999Z; the same-day reopen at20:35 cannot supersede that conservative delivery timestamp. Existing delivery commits/closed events/AC evidence are not erased or rewritten.

In the one reused disposable checkout, the projection changes ONLY CHANGE0204 and SPEC0210 frontmatter implementing→done; its manifest records609 original and projected hashes, and byte comparison confirms the substitutions. Existing telemetry remains untouched. Open audit gives NEEDS-TRIAGE(1); projected audit gives CLEAN with eight report-only unreadable AC tables. All six original failing suites pass in that projection: doc-numbering35/35, delta-stage3 including complete nested docs-audit, doc-number-reservation, deslop and repo-tripwire. Projection is causal evidence, not actual closure, a full104 rerun, or a shipping PASS. An early hypothetical close dry-run exposed absent ignored mutation records in the disposable copy; its refusal is preserved, not represented as successful canonical closure.

Actual proper close and generated overview/roadmap reconciliation must occur only after independent Validation and Review. This leaves a lifecycle ordering tension: actual full-suite audit cannot become CLEAN until authorized closure. The next independent checker must assess that pending ceremony explicitly; maker does not waive it or request another extension.

## Evidence and amendments

Evidence directory: `docs/ai/tdd/pr-capability-preflight-pushurl-remediation-20261007T211358Z/`; artifact-hashes.json lists exact bytes/SHA256, source-hashes.json binds corrected sources. All wrappers settled; no active test sessions. RED and GREEN logs remain separate. Mandatory mutation replay8/8 behavioral RED, zero inconclusive; six product-target hashes freshly restamped (001–005,007),006/008 unchanged. Original eight patches and records were copied byte-for-byte into historical-mutations before replay. Current canonical mutation records remain under docs/ai/tdd/spec-pr-capability-preflight/ and must accompany root's snapshot.

Frozen contract amendment records effective push binding, bounded fixture contract and projection disclosure with signoff none and existing owed follow-up fu-amend-spec-pr-capability-preflight still open. Measurement amendment records six replay restamps honestly. Strict amendment audit exit0, AC gate exit0, AC-flip exit0, spec-lint0findings, diff whitespace check exit0. Decisions ledger retains its609 historical1164232-byte prefix. Friction recorded best effort: v1:33ca40d628a29b9e61c382100af01bbe. A sandbox denied ps inventory; wrapper sessions/logs sufficed, no blocker or escalation.

Changed source/spec/ledger files: .aai/scripts/pr-preflight.mjs; tests/skills/test-aai-pr-preflight.sh; docs/specs/SPEC-0210-spec-pr-capability-preflight.md; docs/ai/decisions.jsonl (root standing decision plus two scoped amendments). Added this report, its checked typed sibling, evidence directory, and updated six canonical mutation measurement records. Historical reports untouched. No shipping Git, STATE or GitHub write by maker.

Root-owned next commands (returned, not executed):

```sh
node .aai/scripts/state.mjs reset-block last_validation
node .aai/scripts/state.mjs set-phase --ref pr-capability-preflight --phase validation --status in_progress
node .aai/scripts/state.mjs append-run --ref pr-capability-preflight --role Remediation --model unknown --started 2026-10-07T21:13:58Z --verdict none --prompt-hash 06c890067c284f9f361c6818b6159ff052cfbc395574b962598b2e930d2ee620 --note "Focused push destination fix; preflight8/8 and mutation8/8; six projected closure suites pass; actual aggregate and fresh native CI pending independent gates; 948 seconds."
```

Leave code_review not_run untouched. Re-Validation and subsequent independent Review are pending; no maker gate verdict. No new human decision requested.
