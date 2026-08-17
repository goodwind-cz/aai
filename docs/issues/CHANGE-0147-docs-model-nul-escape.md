---
id: docs-model-nul-escape
number: 147
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-workflow
links:
  pr:
    - 262
  commits:
    - 838c8a1
---

# Change — two raw NUL bytes made a shared library invisible to grep

## Summary
- `.aai/scripts/lib/docs-model.mjs` carried two literal NUL bytes inside a
  template literal (`${domain}` NUL `${title}`, used as a duplicate-detection
  key). `file` classified the whole file as binary data, so `grep` skipped it
  and reported nothing — silently.
- Replaced the raw bytes with the backslash-u-0000 escape. Zero behaviour change; the
  file is text again and greppable.

## Motivation / Business Value
- Found during the 2026-08-17 registry triage, not by any test. The blast
  radius is narrower and sharper than a first reading suggests: `git grep` and
  ripgrep both still match the file, so agent searches using those were fine.
  POSIX and BSD `grep` are what fail — and that is exactly what this repo's own
  suites use. Code review proved the consequence with a planted canary: the
  negative taxonomy guard at `tests/skills/test-aai-delta-stage2.sh:210` found
  nothing and logged PASS, so it had been silently inert. This change re-arms
  it, and the suite is green with it armed.
- NUL as a key separator is a sound choice, since it cannot occur in a domain
  or a title. Only its spelling in the source was wrong.

## Scope
- In scope: the two-character escape substitution, and the `.aai/` branch-diff
  allowlist entry that edit necessarily triggers.
- Out of scope: the allowlist tax itself (`fu-test011-branch-diff-allowlist-tax`,
  P2, live) — this ride is its fourth payment, not its fix.

## Affected Area
- `.aai/scripts/lib/docs-model.mjs`
- `tests/skills/test-aai-spec-lint.sh` (TEST-011 allowlist)

## Desired Behavior (To-Be)
- The file contains no raw NUL bytes, `file` reports it as text, and `grep`
  matches its contents.
- The runtime key string is byte-identical to before.

## Acceptance Criteria
- AC-001: `.aai/scripts/lib/docs-model.mjs` contains zero raw NUL bytes.
- AC-002: the duplicate-detection key produced at runtime is unchanged,
  including a separator whose char code is 0.
- AC-003: apart from the two substituted spots, the file is byte-identical to
  its previous content.
- AC-004: the suites that consume the library stay green.

## Verification
- `tr -dc '\000' < .aai/scripts/lib/docs-model.mjs | wc -c` reports 0
- a script evaluating the same template literal from the pre-change and
  post-change sources produces identical strings, with separator char code 0
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-lint.sh`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` CLEAN and
  `node .aai/scripts/spec-lint.mjs` clean

## Constraints / Risks
- The escape must be a single backslash. A first attempt wrote `\\u0000`, which
  is a six-character literal rather than a NUL and would have changed the key;
  caught by evaluating the actual runtime value rather than reading the source.
- While writing the allowlist comment for this very change, a raw NUL byte was
  introduced into the test file — the same defect, in the fix for it. Caught by
  re-running the byte count. The comment is now plain ASCII and names the
  escape in words rather than spelling it.
- No secret is referenced by this scope.

## Notes
- Strategy: direct with targeted verification. There is no behaviour to
  RED-test: the change is provably a no-op at runtime, and the meaningful
  assertions are the byte count and the equality of the two evaluated keys,
  both run and recorded above.
- Registry items this does NOT close: `fu-test011-branch-diff-allowlist-tax`.
