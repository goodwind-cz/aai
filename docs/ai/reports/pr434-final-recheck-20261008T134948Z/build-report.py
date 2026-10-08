from pathlib import Path
import json,re,hashlib,datetime,subprocess
r=Path('/private/tmp/aai-pr-capability-preflight');o=r/'docs/ai/reports/pr434-final-recheck-20261008T134948Z';old=r/'docs/ai/reports/VALIDATION-20261008T133306Z-pr434-final.md';report=r/'docs/ai/reports/VALIDATION-20261008T134948Z-pr434-final-recheck.md'
now=datetime.datetime.now(datetime.timezone.utc).isoformat(); sha=lambda b:hashlib.sha256(b).hexdigest()
body=json.loads(re.search(r'```aai-outcome-v1\n(.*?)\n```',old.read_text(),re.S).group(1));body['validation_started_utc']='2026-10-08T13:49:48Z'
for source in body['sources']:assert sha((r/source['path']).read_bytes())==source['sha256']
assert (o/'exits.txt').read_text().splitlines()==['preflight 0','parent-replay 0','generic-replay 0','case-replay 0','adversarial 0','adversarial-reaped 0']
checks=[]
for name in ['preflight','parent-replay','generic-replay','case-replay','adversarial-reaped']:
 p=o/(name+'.log');b=p.read_bytes();checks.append({'file':str(p.relative_to(r)),'sha256':sha(b),'completed_file_mtime_utc':datetime.datetime.fromtimestamp(p.stat().st_mtime,datetime.timezone.utc).isoformat(),'inspected_at_utc':now,'exit_code':0})
(o/'fresh-evidence-inspection.json').write_text(json.dumps({'meaning':'Fresh executions and subsequent log read-back; mtime records actual completed file timestamp, not historical restamping','observed_at_utc':now,'commands':checks},indent=2)+'\n')
# Recheck boundary immediately before report generation.
bound=json.loads(Path('/private/tmp/aai-pr434-final-recheck-boundary.json').read_text());matches={p:sha((r/p).read_bytes())==h for p,h in bound.items() if p!='index_raw_nul_sha256'};matches['index_raw_nul_sha256']=sha(subprocess.check_output(['git','ls-files','--stage','-z'],cwd=r))==bound['index_raw_nul_sha256'];assert all(matches.values())
(o/'final-boundary.json').write_text(json.dumps({'observed_at_utc':now,'matches':matches,'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()},indent=2)+'\n')
for req in body['requirements']:
 if req['id']=='R-RED':req['rationale']='Independently matched authentic historical tool records, four-artifact cat order and 1740-byte UTF8 extraction, eight product failures, original maker exit1/checker0 and current checker0; current recovery hash is not a historical pin.'
 elif req['id']=='R-TRANSPORT':req['rationale']='Freshly verified 46 sealed prior files and all 2614 tracked files against unchanged HEAD; reuse prior exact-head six-alias/five-transitive-alias/605-file audit with its original observation times.'
 elif req['id']=='R-NATIVE':req['rationale']='Fresh read-back verifies three successful captured CI runs and 11 raw logs at exact current HEAD; execution timestamps remain historical, not restamped.'
for outcome in body['outcomes']:
 req=next(x for x in body['requirements'] if x['id']==outcome['requirement_ids'][0]);i=req['id']
 f='preflight.log'
 if i=='R-RED':f='recovery-inspection.json'
 elif i=='R-PRESERVE':f='final-boundary.json'
 elif i=='R-NATIVE':f='ci-inspection.json'
 elif i=='R-TRANSPORT':f='prior-seals.json'
 outcome['verification']={'operation':req['rationale'],'evidence_path':str((o/f).relative_to(r)),'evidence_sha256':sha((o/f).read_bytes()),'observed_at_utc':now,'result':'satisfied'}
text='''# Final parent Validation recheck — PR434

Verdict: **PASS** for current reviewed source plus recovered historical evidence. Code review gate: **pass** (retained independent assembly dual PASS). AC status gate: **pass**. This is a new validation outcome, not a rewrite of the genuine earlier FAIL. Final metadata-commit CI and the external review sweep remain the root orchestrator's delivery work.

## Scope and independence

System-clock start: 2026-10-08T13:49:48Z. Fresh independent Validation context; no implementation conversation used. Requested validator gpt-6-astra and requested maker gpt-6-luna differ, but actual serving weights are unknown. No claim of weight-level independence. Original intake CHANGE-0204, frozen SPEC-0210, owner split decision, technology contract, source, relevant test/prose boundaries and recorded artifacts were independently read. This validation uses the explicit final-delivery override, not the default rule6 Planning dispatch for already-done documents. STATE was active, human_input.required=false and strategy=tdd. No STATE, lifecycle, Git/index, external or old evidence writes were made. No delegation: the requirements share the identity/provider/ceremony boundary and are not independent groups.

Complete scope: bdeb425c040ada918dd97e5b878b71e420bad83a..9d90d1e4dad24ff56f69a938f87c97510d61b740 plus restored original RED bytes. Source SHA256 e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf and suite SHA256 239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c match the supplied boundary. All 2614 tracked files match HEAD. The .aai/tests diff from reviewed 8701da75 to HEAD is empty. The prior full-scope inspection covers 1002 changed paths; its 46 sealed report/evidence files were hash-and-size verified unchanged. Prior findings and observations are reused explicitly, not described as new executions.

## Requirement coverage

| Requirement | Spec | Implementation and executable evidence |
|---|---|---|
| AC-001 explicit unambiguous repository/remote/source/base | Spec-AC-01 | CLI identity/raw URL checks; fresh TEST001 plus malformed port, dot-path, password and endpoint mismatch probes |
| AC-002 bounded noninteractive Azure read; create unknown | Spec-AC-02 | probe/readiness/launcher; fresh TEST002 exact argv, closed stdin, inherited environment controls and split UTF8; prior exact-head native matrix |
| AC-003 named safe failures and bounded cleanup | Spec-AC-03 | Refusal, byte/time caps; fresh TEST003–005; 1495ms timeout, child_alive=false, later_probes=0; reached secret emitter |
| AC-004 preflight before writes, preserve local state | Spec-AC-04 | SKILL_PR preconditions and CLI; fresh TEST006 origin/alternate/null and STATE/index/HEAD/reservation preservation; source/prose ordering read |
| AC-005 GitHub and generic contracts retained | Spec-AC-05 | identity ASCII folding and literal endpoint equality; fresh TEST007, public/enterprise combined-case, Unicode distinction, generic numeric-port redaction/null controls |
| AC-006 classification, selection and measured prompt bytes | Spec-AC-06 | profiles/map/diet and fixture companions; fresh TEST008 LF/CRLF, shallow clone, captured stderr and delayed/hung replay controls; exact-head full CI |
| RED before implementation | Test Plan / Evidence by strategy | Original maker test exit1 and checker0 at 2026-10-07T12:26:40.910Z; authentic full read at 14:02:46.776Z; independent extraction and current checker0; fresh 8+2+2 mutation RED |
| No auto-install/credential disclosure; preserve unrelated work | Provider/ceremony seams | Read-only source, strict argv allowlists, reached secret control, fresh boundary pins and tracked-byte equality |
| Native platform proof | Verification | Captured Windows5.1/pwsh7/WSL1/Linux execution on exactly current HEAD; fresh identity/log read-back |
| Historical evidence preservation | Evidence contract | 46 sealed files unchanged, current tracked bytes unchanged; prior six-alias/five-transitive-alias/605-file transport audit retained with original timestamps |

No intake requirement was omitted or weakened. The complete source-quoted requirement inventory is in the machine-readable block below. Its observations of old material are new **read-back inspections**, never claims of rerunning old CI or original RED.

## Recovered RED evidence

Independent comparison against both original preserved session files matches complete call/output records, including their ordinals, timestamps and call IDs. The historical cat command names four artifacts in order: original RED, mutation replay, native Windows status, Pester baseline. Extraction starts at RED_CLASS and ends immediately before the next lower-case `command: node .aai/scripts/mutation-run.mjs --replay --spec` marker. It contains exactly TEST001..008 FAIL rows, Unicode 雪, the original header and terminal newline. All 1740 UTF8 bytes match both recovery original-red.log and restored docs/ai/tdd/pr-capability-preflight-red.log. SHA256 dfe1829c14b3bb4fe9f2c28f3cb89be248777381553b8e108fc870df4bf85fab is a **current recovery hash**; no historical original hash exists or is claimed.

The preserved maker tool call actually ran a disclosed parseable no-op baseline through the wrapper, captured exit1, wrote the evidence header plus raw stdout, and obtained checker acceptance (exit0). The baseline retained in docs/ai/tdd/spec-pr-capability-preflight/baseline.mjs matches that disclosed no-op. Original prompt/distribution failures are explicitly named for TEST006/008. This is authentic historical product RED, not a newly simulated run. Recovery closes earlier B1; the old report and its unknown outcome/checker refusal remain unchanged.

## Commands and outcomes

Evidence is under docs/ai/reports/pr434-final-recheck-20261008T134948Z/. Fresh tests ran in the ONE authorized standalone copy /private/tmp/aai-pr434-final-recheck-scratch. Wrapper, fixture TMPDIR and all mutation experiments stayed there. The wrapper's AAI_TEST_ISOLATION=0 wording calls its cwd shipping; that cwd was the copy. Step epochs and post-step reapers were used by run-validation.sh and run-adversarial.sh, with zero survivors.

| Command | Exit | Evidence |
|---|---:|---|
| wrapper + bash tests/skills/test-aai-pr-preflight.sh | 0 | preflight.log: 8 named PASS |
| wrapper + node .aai/scripts/mutation-run.mjs --replay --spec SPEC-0210 path | 0 | parent-replay.log: 8/8 RED, 0 inconclusive, 0 restamped |
| same replay, SPEC-0211 path | 0 | generic-replay.log: 2/2 RED, 0 inconclusive, 0 restamped |
| same replay, SPEC-0212 path | 0 | case-replay.log: 2/2 RED, 0 inconclusive, 0 restamped |
| wrapper + sealed prior adversarial.cjs, scratch root, 007 | 0 | adversarial-reaped.log: 11 positive/negative seam probes |
| node .aai/scripts/tdd-evidence-check.mjs --red docs/ai/tdd/pr-capability-preflight-red.log | 0 | red-check.log: ACCEPTED product_red |
| node .aai/scripts/docs-audit.mjs --gate SPEC-0210 | 0 | ac-gate.log: all rows terminal/evidenced, Review-By valid |
| node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0210-spec-pr-capability-preflight.md | 0 | spec-lint.log: no structural findings |
| node .aai/scripts/docs-audit.mjs --no-event | 0 | docs-audit.log: CLEAN, 8 report-only unreadable tables and 2 report-only missing-close-telemetry observations |
| independent extraction/seal/boundary/corpus checks | passed assertions | recovery-inspection.json, prior-seals.json, boundary-corpus.json, final-boundary.json |
| python3 inspect-ci.py | 0 | ci-inspection.json: exact-head 3 runs and 11 logs |

This is the final delivery recheck after the prior final FAIL, not a new broad implementation round. Discovery finds 104 framework suites, plus test-framework.sh and test-ps1-quality.sh drivers (106 test-*.sh files), and five Pester files. No browser/e2e config, deployed surface, package build or separate application test runner exists. The explicitly authorized prior **full** exact-head CI supplies the broad sweep; it was not redundantly rerun locally. CI runs 37778220504 (skills), 37778220619 (PowerShell), 37778220735 (docs) are completed/success at 9d90d1e4dad24ff56f69a938f87c97510d61b740. Full shards total 103 PASS, 0 FAIL, 1 named aai-state SKIP; no skip is counted as PASS. Native Windows5.1/pwsh7/WSL1 each show 153/0/4 documented POSIX-only skips; Linux Pester 157/0/0. Every native preflight arm ran. Docs success has API job/step proof; missing raw docs logs are not claimed read. All original CI timestamps remain in the raw captured artifacts. No CI claim is made about a future metadata commit.

## Gates, failure categories and residual limits

AC gate PASS: six parent rows terminal/evidenced. Repo-wide scan: 216 specs, 210 opted tables, zero overdue deferred/blocked rows. The two deferred rows are in other specs, due 2026-10-17 and 2026-10-20; the per-validated-spec 14-day rule has no applicable parent rows. No lifecycle/AC rows/events were edited under the dispatch's freeze.

Product failures: none in this recheck. Evidence completeness: original missing RED now independently verified; earlier FAIL is retained. Validator infrastructure: the first inspection helper incorrectly stripped the source record ordinal, then a later stage used headSha instead of raw REST head_sha; corrected comparisons and the independent CI helper pass. These helper errors are not product RED. The first successful adversarial execution did not preserve its epoch for a separate post-step reaper; it was repeated with the fully recorded wrapper/reaper script, also exit0 and zero survivors. Mutation logs retain named nested-scratch EISDIR exclusions; all 12 records still redden, none inconclusive/restamped. The unsupported checker --help probe exited1 with usage; it is not a validation result.

Carried residuals: live authenticated Azure adoption/downstream reproduction and future create permission remain unverified; prose ordering cannot attest arbitrary future agent obedience. Actual model-weight independence remains unknown. Filed P3 fu-review-log-attribution (N1) remains open, as do the three unsigned-amendment follow-ups for parent/generic/case specs; no signatures or repairs are fabricated. Historical 621-file narrative versus available 605 Git804 report/review inventory remains disclosed. Full CI's aai-state skip remains a skip. The new recovery depends on preserved local harness output rather than an unavailable original historical hash; this provenance and extraction were directly checked.

Verification-before-claim was applied by identifying the scope, rerunning its matrix/replays, reading outputs and comparing identities/hashes before the outcome checker. Root owns STATE merge commands, metadata commit, resulting-head CI, external sweep and owner-directed merge. This report author stops at the checked handoff.

## Outcome binding

'''
report.write_text(text+'```aai-outcome-v1\n'+json.dumps(body,indent=2)+'\n```\n')
print(report)
