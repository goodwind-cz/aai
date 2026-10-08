# PR434 SSH-over-HTTPS alias research

Disposition: **real** at immutable head `ebbd0eaeaebfa9015f550193df6f0b54afc338c3`, thread `4213513507`, node `PRRT_kwDORMHhts6qJxU9`: the documented GitHub SSH443 origin is rejected before provider calls. This is an existing-route defect, not a request to add an unrelated provider or arbitrary-port capability.

Authority: CHANGE0204 line39 AC005 says existing GitHub and generic routes remain supported. SPEC0210 line75 SpecAC05 says preserve the declared readiness and ceremony route; line82 explicitly says use existing platform classification/sanitization rather than a second classifier and supports an ordinary remote without pushurl. Existing `pr-platform.mjs:344` classifies both github.com and every hostname ending .github.com as GitHub, including ssh.github.com. TEST007 (spec line116) expressly requires original GitHub classification unchanged. No frozen clause explicitly excludes the official SSH443 transport. I infer existing-scope applicability from these clauses and the actual inherited classifier, not from a guessed future capability.

Primary source checked on 2026-10-08: [GitHub Docs, Using SSH over the HTTPS port](https://docs.github.com/en/authentication/troubleshooting-ssh/using-ssh-over-the-https-port). It documents the clone URL `ssh://git@ssh.github.com:443/YOUR-USERNAME/YOUR-REPOSITORY.git`, explains the 443 endpoint hostname is ssh.github.com, and shows an SSH config override for github.com. Its GitHub Enterprise restrictions also argue against globally remapping arbitrary enterprise hosts. No live provider credentials, network Git operation or provider write was used in this reproduction.

Cause: `pr-preflight.mjs:116` rejects every nonempty parsed URL port. The documented SSH URL retains port443, unlike an HTTPS default443 URL whose URL.port is empty. `pr-preflight.mjs:185-189` assigns the raw remote hostname as provider repository.host; `:211`, `:234`, `:238` bind GH_HOST, authentication hostname and returned HTTPS URL to that host. Allowing the port alone is insufficient: the alias-no-port control proves auth is directed to ssh.github.com, whereas the lawful API fixture is bound to github.com. Minimal remediation should preserve literal effective-fetch/push equality and owner/repository checks, recognize only the documented SSH transport alias/443 combination, and bind that alias's GitHub API probes/returned URL checks to github.com. Retain ordinary-host/enterprise binding and refusal controls; do not broadly permit ports or normalize fetch/push endpoints before comparison.

Executed canonical command (exit0): `env AAI_ROLE=subagent AAI_TEST_TIMEOUT=30 bash .aai/scripts/aai-run-tests.sh node /private/tmp/aai-pr434-ssh443-research/probe.mjs` from `/private/tmp/aai-pr-capability-preflight`. Twelve real-Git effective URL cases are retained in observations.json and probe.log. Git configuration is isolated from system/global settings; provider mock denies unexpected argv and any API host except github.com. Private fixture Git objects/index were removed afterward so retained artifacts are text only. No shipping, lifecycle, STATE, index or outbound-comment writes occurred.

| Case | Observed exit/code | Provider calls |
| --- | --- | --- |
| HTTPS, scp GitHub SSH, scheme SSH without port | 0 READ_VERIFIED | 3 each, all GH_HOST github.com |
| documented ssh.github.com:443 alias | 2 IDENTITY_INVALID identity | 0 |
| documented alias with mismatched intended repository | 2 IDENTITY_INVALID identity | 0 |
| ssh.github.com:444, github.com SSH443, HTTPS444 | 2 IDENTITY_INVALID identity | 0 each |
| HTTPS default443 | 0 READ_VERIFIED | 3, github.com |
| ssh.github.com without port (cause isolation; not claimed lawful443) | 3 ACCESS_UNKNOWN gh.authentication | 2, ssh.github.com |
| ordinary GitHub mismatched intended repository | 2 IDENTITY_INVALID identity | 0 |
| hostname lookalike with provider repository fields | 2 IDENTITY_INVALID identity, platform unknown | 0 |

For the documented alias, real Git emits identical fetch/push strings `ssh://git@ssh.github.com:443/OWNER/REPO.git\n`; existing platform CLI returns github exit0, then actual unmodified preflight returns exit2 with zero providers. Complete stdout/stderr, calls and effective bytes are in observations.json. These are observations rather than a shipping test or independent Validation verdict. Model/tier actually used is unknown to this subagent; no usage estimate is reported.

Source SHA256 captured during execution:

- pr-preflight.mjs: aca4085d27c5e1f9e2db33a2f29eb9acbe6e9097838a1565dc275dc710a1430d
- pr-platform.mjs: 578c56a46c8d9300309ebc302bd378fdddd4322cbab810cae4cfc513d119e334
- SPEC0210: cf332dfb7afa2ee6384b87367f493e2ca383ad25fb9bf3547bf8c343b2fee79a
- CHANGE0204: 5103c792b1773650e6122e91fb58cd15ae8760e8ec3c9dc5642423b618a45460
