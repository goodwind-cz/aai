# PR 434 native checkout path repair

The three native jobs at published 8045957286bd1bc5356e8be32b8b4dd025be262a failed during checkout before any test ran. The first reported invalid path has a colon in its timestamp. A complete tracked path scan found exactly six invalid paths and no case collisions.

Category: missing CI prerequisite evidence. Each historical mutation artifact was renamed to a Windows-safe timestamp, preserving bytes. Its old name and Git blob remain recoverable at 8045957286bd1bc5356e8be32b8b4dd025be262a; the alias map binds old and new paths. No sealed report or product source was edited.

| Original path at Git804 | Portable path | SHA-256, both paths' bytes | Git804 blob |
|---|---|---|---|
| `docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-007.2026-10-07T12:49:40Z.patch` | `docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-007.2026-10-07T12-49-40Z.patch` | `5cb7ee0e5754d4ae20e924b69fc1c68e1ca73dfc94027abc88e35ce937d666c8` | `58ce0b57de3d8a48a211acfdc54a38751b071532` |
| `docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-007.2026-10-07T12:49:40Z.txt` | `docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-007.2026-10-07T12-49-40Z.txt` | `0f425773b623039dbb0b9d624e9c2343597d1042dcf7955b289a695923eda380` | `1638070e9a5febea8236d142ab4eb11437acca72` |
| `docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-001.2026-10-08T11:26:19Z.txt` | `docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-001.2026-10-08T11-26-19Z.txt` | `56194d581e4ff09abbdde68997ac7bfababf17e5ba26a5477636a670720503fa` | `ad61caf9d2a85d623dd1ad3f4dae7cd2bbd5de3d` |
| `docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-001.2026-10-08T11:26:58Z.txt` | `docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-001.2026-10-08T11-26-58Z.txt` | `add9a9c2f641a77d55844eff76466c7d5611125d69cecf7d25acb1be2af3d0c6` | `4e3e9beead6cf1ceb152dae3be4d31852084d1b2` |
| `docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-007.2026-10-08T11:26:37Z.patch` | `docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-007.2026-10-08T11-26-37Z.patch` | `ff3457bd16e58c04e00640bd75dbe0c3196658970f481dd88e702e1c5add0818` | `180d163523ee2681580743ca5a1cb5f665630dca` |
| `docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-007.2026-10-08T11:26:37Z.txt` | `docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-007.2026-10-08T11-26-37Z.txt` | `a6b9ab341b920ff92bddaf4f482809cb54c64fe21c8235fe63ed65a8801ab0dd` | `5f10ec6360fb354fda440fab5463a0e4fda9b643` |

The transformed tracked inventory contains 2604 files, zero Windows-invalid paths, zero case collisions, and longest relative path 136 characters (`docs/ai/tdd/pr-capability-preflight-final-remediation-20261007T224314Z/historical-mutations/mutation-TEST-003.2026-10-07T12-32-21Z.patch`). Frozen source, tests, three specs, index and STATE retained their SHA-256 pins in the map. 621 pre-existing files under reports/reviews retained their aggregate content pin.

The assembly Review PASS predates this metadata repair and covers the unchanged semantic source. It is not a new review of these aliases. Fresh native/full CI and independent parent Validation remain pending after root publication. No readiness verdict is claimed here. Suggested follow-up: make historical mutation rotation filenames portable at generation time; this was not filed.

## Focused verification

The three existing mutation gates returned exit 0 without replay or restamp: parent 8/8, generic URL child 2/2, case identity child 2/2. Each reported `degraded=0 unstamped=0 uncomparable=0`. A post-rename audit rechecked all six aliases against Git804 blobs, seven frozen file pins, and the same 621 old report/review files.

The full local filesystem scan has 3,926 files and eight additional colon-bearing mutation history files under `docs/ai/tdd/spec-pr-generic-url-validity/`. Those eight are ignored, untracked, and absent from the Git804 intended checkout inventory; this repair leaves their legitimate local bytes untouched. The 2,604-file intended tracked inventory after the six renames has zero Windows-invalid names or case collisions. The alias files and this report are also ignored by repository patterns, so root must explicitly add the six aliases and two report files while recording the six deletions. No index action was taken here.
