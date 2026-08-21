---
id: assertions-must-not-die-on-their-own-payload
number: 155
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-test-canon
links:
  pr:
    - 272
  commits:
    - 90555fb9cd8b4b1e5770643e87fc4de9eb548cd5
---

# Change — an assertion that pipes into `grep -q` fails on a payload that matched

## Summary
- `printf '%s\n' "$out" | grep -qF <needle>` under `set -o pipefail` reports
  **failure** once `$out` passes the 64 KiB pipe buffer, even when the needle is
  present. `grep -q` exits at the first match, the writer takes SIGPIPE (141),
  and `pipefail` promotes that to the pipeline's status.
- It turned CI red on `test-aai-docs-audit.sh` while the same arm passed
  locally, because the payload sat either side of 64 KiB depending on how many
  documents the index held.

## Evidence
Measured on this machine, 2026-08-21, under `set -euo pipefail`:

```
payload 17978 B   failures  0/20
payload 52194 B   failures  0/20
payload 90778 B   failures 20/20
payload 181779 B  failures 20/20
```

Deterministic, not a race: a threshold at the pipe buffer. The failing CI run is
`32496747671` job `96816946878`; the assertion printed
`FAIL: the failure must name the path problem (expected 'not POSIX')` while its
own payload contained hundreds of lines saying exactly `not POSIX`.

Census of the shape across the repository:

```
printf/echo of a variable piped into grep -q   387 occurrences, ~40 files
any pipe into grep -q (superset)               657
pipe into head                                  86
suites running pipefail                         51 of 83
```

Four occurrences were fixed in `test-aai-docs-audit.sh` when CI went red. The
rest are unswept. `assert_contains` is NOT affected — it greps a **file**, with
no pipe.

## Impact
- A test that goes red *because it found what it was looking for*, and whose
  message names the wrong cause. This is the same misattribution class as
  ISSUE-0033, one layer down.
- Latent: a site is harmless for years and fails the day its corpus grows past
  the buffer. Nothing warns first.

## Suspected Cause
Not 387 separate mistakes — one idiom, copied. The safe form is available and
no more verbose (`[[ "$out" == *needle* ]]`), but nothing makes the unsafe form
visible as unsafe, and nothing stops a new one being added.

## Desired Behavior
No assertion in this repository can report failure because its payload was
large. New occurrences of the unsafe shape cannot be added silently.

## Acceptance Criteria
- AC-001: every site whose payload can exceed 32 KiB is converted to a
  pipe-free form. The at-risk set is **measured at runtime**, not guessed from
  reading code — see Verification.
- AC-002: a pipe-free assertion helper exists in the shared framework, is used
  by the converted sites, and its own failure message names the needle and
  shows a bounded prefix of the payload rather than all of it.
- AC-003: a ratchet arm counts occurrences of the unsafe shape and fails when
  the count **rises** above the recorded number, naming the file that grew.
  Prove it bites by adding one occurrence.
- AC-004: the ratchet's recorded number is measured by the arm itself, not
  typed in from this document.
- AC-005: no converted assertion changes what it asserts. Prove it: each
  converted site keeps its needle and its message, demonstrated by a diff
  review arm or by the suites that own them staying green.

## Verification
- **Measure the at-risk set, do not read for it.** Put a `grep` shim first on
  `PATH` that, when `-q` is present and stdin is a pipe, reads stdin to EOF,
  records the byte count and the caller, then performs the match. Run the full
  framework under it. Every recorded size is a real payload; anything near the
  buffer is at risk. Note in the report that the shim MASKS the bug by reading
  to EOF — that is deliberate, it is a size census, not a reproduction.
- prove AC-003 bites by adding an occurrence and watching the ratchet name it
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns

## Constraints / Risks
- **387 sites is too many to convert blindly and most are harmless.** A blanket
  rewrite is a large diff with real risk of changing what an assertion means,
  for mostly theoretical benefit. Convert what the measurement shows, ratchet
  the rest. If the measurement says the at-risk set is empty except the four
  already fixed, say so and ship the helper and the ratchet alone.
- `assert_contains`/`assert_not_contains` read a file and are NOT affected. Do
  not touch them.
- The same 64 KiB boundary produced the `follow-ups.mjs` truncation fixed in
  CHANGE-0153. Different mechanism, same buffer; the two must not be conflated
  in the write-up.
- `tests/skills/test-aai-docs-audit.sh` runs ~128 s. Suites are serial only.
- Nine of the framework's suites are shell twins with a `.ps1` side; the shape
  is a POSIX-shell hazard and PowerShell is out of scope.
- No secret is referenced by this scope.

## Notes
- Registry item this scope closes: `fu-suite-asserts-pipe-into-grep-q` (P1).
- Related and NOT in scope: `fu-test011-branch-diff-allowlist-tax` (P2), the
  hand-maintained `.aai/` allowlist that reddens three suites for any unlisted
  path. Different defect, same suite family.
- Ride discipline: ship on these acceptance criteria and nothing else. A finding
  outside them is filed, not fixed here. Two validation rounds maximum.
- Worth knowing while working: `grep` resolves to a shell function even
  non-interactively here, zsh does not word-split unquoted variables,
  `find -newermt` is a hard error, and reading an exit code after a pipe reports
  the pipe's last command — all four have produced fabricated measurements here.
