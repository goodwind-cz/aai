---
id: friction-capture-foundation
number: 45
type: change
status: draft
links:
  rfc: RFC-0012
  spec: null
  pr: []
  commits: []
---

# RFC-0012 Phase 0 — friction capture foundation (protocol + schema + offline capture CLI + spool)

## Summary
- Implements ONLY Phase 0 of the accepted RFC-0012 (AAI self-improvement /
  friction feedback loop): the local-capture FOUNDATION. Everything downstream of
  capture — triage/upsert (`/aai-feedback-triage`), the maintainer skill, GitHub
  writes, `.aai/feedback.yaml` modes, budgets — is DEFERRED to later phases and is
  explicitly OUT of scope here.
- Deliver a canonical friction protocol, a versioned observation schema, a
  dependency-free OFFLINE capture CLI, an untracked spool, the D6 privacy
  allowlist enforced structurally, and skill-suite tests. This is the smallest
  self-contained slice that makes Phase 1 (local shadow mode) possible.

## Type
- change (feature — first implementation slice of RFC-0012)

## Impact
- Foundation for the whole feedback loop; nothing external happens yet (capture is
  offline-only, no token, no network). The privacy contract that D1/D5 shifted onto
  capture (RFC-0012 Decisions: mode-default local + minimal field allowlist + hard
  redaction + auto gate) BEGINS here: Phase 0 must guarantee capture performs NO
  network I/O and that NO identity field can enter the spool, and prove both in the
  skill suite. AAI-layer -> ships to downstream via `/aai-update`.

## Binding inputs (RFC-0012 decisions — do not re-litigate)
- D6 (safe fields — the privacy crux for Phase 0): the observation record's
  transmittable surface is a MINIMAL allowlist — OS family (linux/macos/windows),
  AAI pin/version, Node major version, skill id + phase, failure class, and the
  deterministic fingerprint. NEVER: hostnames, absolute paths, repository
  names/remotes, usernames, or project identifiers. Enforce STRUCTURALLY (drop
  non-allowlisted keys), not by hoping callers omit them.
- Capture is offline: `node .aai/scripts/aai-friction.mjs record --input
  <sanitized-json>` writes atomically to an untracked project-local spool, holds NO
  GitHub token, and performs NO network I/O.
- Failure taxonomy (record a candidate ONLY for AAI-owned failures):
  contradictory/ambiguous/impossible AAI instructions; missing/invalid AAI-owned
  files/commands/templates/transitions; deterministic failure of an AAI
  script/workflow contract; repeated recovery from an AAI abstraction leak; a human
  correction identifying an AAI prompt/skill defect; a documented
  downstream/cross-platform contract violation. EXCLUDE: expected test failures,
  normal target-project bugs, invalid user input, HITL pauses, transient
  provider/network failures, unavailable optional tools, cosmetic preferences
  (unless recurrence shows a systemic problem).
- Capture failure MUST NEVER replace or mask the calling skill's original result.

## Scope (Phase 0 only)
- IN SCOPE:
  1. `.aai/system/FRICTION_PROTOCOL.md` — the canonical contract: failure-class
     taxonomy + exclusions, the versioned observation schema (v1: schema version,
     timestamp, AAI pin, skill + phase, failure class, expected/observed, minimal
     reproduction, workaround, impact, confidence, recurrence evidence, safe
     evidence refs, redaction status, deterministic fingerprint), the D6 field
     allowlist, the v1 deterministic fingerprint algorithm (a documented,
     versioned compatibility contract), and the redaction/privacy policy. It is a
     SYSTEM doc (`.aai/system/*.md`), NOT a `*.prompt.md`, so it carries no
     prompt-diet ledger obligation.
  2. `.aai/scripts/aai-friction.mjs` — dependency-free (node stdlib only) CLI with
     `record --input <json>` (accept a path or stdin): validate against the schema;
     STRUCTURALLY drop any key not in the D6 allowlist before persisting; compute
     the v1 fingerprint; write atomically (temp + rename) as one JSONL line to the
     untracked spool; NO network, NO token; a malformed/oversized input is rejected
     with a clean non-zero exit and NO partial write; capture never throws in a way
     that could mask a caller. Include `--help` documenting the contract.
  3. Spool at `docs/ai/friction/` — gitignored (add the `.gitignore` stanza +
     a `.gitkeep`), JSONL append, project-local, never committed.
  4. `.aai/system/PROFILES.yaml` — classify BOTH new `.aai/**` files
     (`aai-friction.mjs` and `FRICTION_PROTOCOL.md`) so the layer-profiles
     manifest gate stays green.
  5. `tests/skills/test-aai-friction.sh` — see Verification.
- OUT OF SCOPE (later phases, do NOT build here):
  - triage/upsert, the maintainer skill, `.aai/feedback.yaml` modes, any GitHub
    write, budget/cooldown, fingerprint clustering (Phase 2+);
  - wiring `FRICTION_PROTOCOL` into every universal skill prompt — the seam is
    Phase 1 (it touches many `*.prompt.md` files -> a prompt-diet ledger churn that
    must not be bundled into this foundation);
  - network/mode gating (there is no network path in Phase 0 to gate).

## Verification
- Schema validation: a well-formed observation records; a missing required field
  or wrong-typed field is rejected with a clean non-zero exit and no spool write.
- D6 allowlist enforced STRUCTURALLY (the privacy invariant): an input that
  INCLUDES forbidden identity keys (hostname, absolute path, repo remote, username,
  project id) records with those keys DROPPED — the persisted spool line contains
  ONLY allowlisted keys. Test asserts the spool line has no forbidden key even when
  the input supplied them.
- No network / no token (structural): `aai-friction.mjs` contains no
  net/http/https/fetch/gh/child_process-network call; a test greps the source for
  those and asserts absence, and runs `record` with no network available.
- Fingerprint determinism: the same normalized observation yields the same v1
  fingerprint across runs and machines; a documented normalization; version tag in
  the fingerprint.
- Atomic write: a `record` writes exactly one JSONL line; an interrupted/failed
  record leaves no partial line (temp+rename).
- Capture-does-not-mask: `record` on a bad input exits non-zero but the test
  confirms the CLI is side-effect-free on the caller (it is a standalone process;
  assert no unexpected stdout/exit that a wrapper would misread).
- Portability (LEARNED 2026-07-19): the test spawns throwaway dirs — full `mktemp`
  templates, POSIX-safe, honor shebangs; green on Linux CI + macOS. `aai-friction.mjs`
  is node-stdlib-only, cross-platform.
- Full skill suite green (esp. `test-aai-layer-profiles.sh` after the PROFILES
  entries, and no prompt-diet regression since no prompt file is touched).

## Constraints / Risks
- Ceremony: this adds NEW production code (`aai-friction.mjs`) + a new contract; it
  is privacy-critical (D6). Recommend the ceremony lane match that (L2 full
  validation is defensible); Planning decides. It does NOT touch any
  `protected_paths_l3` (`state*.mjs`, `allocate-doc-number.mjs`, `pre-commit-checks.*`,
  `WORKFLOW.md`, `CONSTITUTION.md`) — confirm.
- The D6 allowlist is a DENY-by-default structure: persist only allowlisted keys.
  Do NOT implement it as a denylist of known-bad keys (a new identity field would
  leak). Test the deny-by-default property explicitly.
- The fingerprint is a versioned compatibility contract — stamp its version so a
  future algorithm change is detectable, per the RFC.
- Zero runtime dependencies + cross-platform (RFC + TECHNOLOGY.md): node stdlib
  only; no npm install; works under WSL/Linux/macOS/Windows Git-Bash.
- Companion obligations (PLANNING step 3a): TWO new `.aai/**` files -> PROFILES.yaml
  classification REQUIRED (in scope). NO `*.prompt.md`/`AGENTS.md` edit -> no
  prompt-diet ledger true-up.
- No secret referenced — SECRETS PREFLIGHT skipped (capture holds no token by
  design).

## Notes
- This is Phase 0 of a multi-phase RFC. Keeping it to the offline capture
  foundation makes the privacy guarantee (D6 deny-by-default + no network) small,
  auditable, and skill-suite-enforced BEFORE any network path exists — which is
  exactly the order the RFC's phased rollout and the privacy reconciliation
  demand. Phases 1-5 build on this frozen protocol/schema/fingerprint contract.
