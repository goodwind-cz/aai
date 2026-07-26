# AAI Friction Protocol (v1)

Canonical contract for RFC-0012 Phase 0 — the **offline capture foundation**
of the AAI self-improvement / friction feedback loop. This is a SYSTEM
document (`.aai/system/*.md`), not a `*.prompt.md`: it carries no prompt-diet
ledger obligation and defines a data/behaviour contract, not workflow.

Scope of this document (Phase 0 only): the failure-class taxonomy, the
versioned observation schema v1, the D6 persisted-field allowlist, the v1
deterministic fingerprint algorithm, and the redaction/privacy policy. It is
consumed by `.aai/scripts/aai-friction.mjs record`. Everything downstream of
local capture — triage/upsert, the maintainer skill, `.aai/feedback.yaml`
modes, any GitHub/network write, budgets/cooldown, fingerprint clustering — is
DEFERRED to later RFC-0012 phases and is out of scope here.

Binding decision inputs (RFC-0012 "## Decisions", frozen 2026-07-25): D6 (the
minimal safe-field allowlist) and the Privacy reconciliation (mode-default
local, structural identity exclusion, no network in Phase 0). These are not
re-litigated here; this document operationalizes them.

---

## Failure-class taxonomy

A friction observation is recorded ONLY as evidence of an **AAI-owned**
failure. The `failure_class` field MUST be exactly one of the closed set
below (any other value is a schema violation and is rejected):

| `failure_class` value            | Inclusion (record when...)                                                        |
|----------------------------------|-----------------------------------------------------------------------------------|
| `contradictory_instructions`     | AAI instructions are contradictory, ambiguous, or impossible to satisfy.          |
| `missing_or_invalid_artifact`    | A missing or invalid AAI-owned file, command, template, or state transition.      |
| `deterministic_script_failure`   | A deterministic failure of an AAI script or workflow contract.                    |
| `abstraction_leak_recovery`      | Repeated recovery work caused by an AAI abstraction leak.                          |
| `human_corrected_defect`         | A human correction that identifies an AAI prompt or skill defect.                  |
| `contract_violation`             | A documented downstream or cross-platform AAI contract violation.                 |

### Exclusions (never record — not AAI-owned friction)

These are NOT recordable failures and MUST NOT be filed as friction (they are
excluded by construction — there is no `failure_class` for them):

- expected test failures (a RED in a TDD cycle is not friction);
- normal target-project bugs (defects in the downstream project's own code);
- invalid user input;
- HITL pauses (a human-decision-required stop is by design, not a defect);
- transient provider/network failures;
- unavailable optional tools;
- cosmetic preferences — UNLESS recurrence shows a systemic problem.

The taxonomy is the ownership gate: if a candidate does not fit exactly one
inclusion row above, it is not AAI friction and is not captured.

---

## Observation schema v1

An observation is a single JSON object supplied to
`aai-friction.mjs record --input <path|->`. `schema_version` MUST equal `1`.

**Required fields** (absent or wrong-typed -> clean rejection, no spool write):

| Field               | Type                     | Notes                                                        |
|---------------------|--------------------------|--------------------------------------------------------------|
| `schema_version`    | integer, MUST equal `1`  | the schema/compatibility version tag.                        |
| `skill_id`          | non-empty string, <= 128 chars | the AAI skill/role that hit the friction (e.g. `SKILL_TDD`). |
| `skill_phase`       | non-empty string, <= 128 chars | the phase within that skill (e.g. `implementation`).         |
| `failure_class`     | string, taxonomy enum, <= 128 chars | one of the six closed values above.                  |
| `expected_behavior` | non-empty string         | what the AAI contract promised (not persisted; feeds fingerprint). |
| `observed_behavior` | non-empty string         | what actually happened (not persisted; feeds fingerprint).   |

The three persisted string fields (`skill_id`, `skill_phase`, `failure_class`)
are capped at **128 characters** each — they are identifiers/enums, so an
over-length value is invalid input and is rejected (clean non-zero exit, no
spool write). This cap, together with the short derived/computed fields, keeps
every persisted line far below the atomic-append bound (see the allowlist
section). `expected_behavior` / `observed_behavior` are not persisted (they
feed only the fingerprint) and so are not length-capped.

**Optional fields** (validated for type when present; feed neither the
allowlist nor — except where noted — the fingerprint):

| Field          | Type                                          | Notes                                              |
|----------------|-----------------------------------------------|----------------------------------------------------|
| `impact`       | string enum `low` / `medium` / `high` / `critical` | severity of the friction.                     |
| `confidence`   | string enum `low` / `medium` / `high`         | reporter confidence in the AAI-ownership judgment. |
| `reproduction` | string                                        | minimal reproduction notes.                        |
| `workaround`   | string                                        | the recovery/workaround applied.                   |
| `recurrence`   | string                                        | recurrence evidence.                               |
| `evidence_refs`| array of strings                              | safe, non-identity evidence references.            |
| `redaction`    | string enum `none` / `standard` / `hard`      | the redaction status of the source material.       |
| `timestamp`    | string                                        | caller-supplied time; NEVER persisted, NEVER hashed (environment entropy). |

Locally derived fields (`os_family`, `aai_pin`, `node_major`) are NEVER read
from the input even if a caller supplies them — see the allowlist section. The
whole input is bounded: an input larger than 65536 bytes is rejected as a
schema violation (no spool write). Optional descriptive fields are validated
and may contribute to the fingerprint's semantic identity only as listed in
the fingerprint section; they are NOT written to the Phase 0 spool.

---

## Observation schema v2 (RFC-0013)

Schema v2 is backward compatible: a `schema_version: 1` record is accepted and
persisted EXACTLY as before (the eight v1 keys, byte-identical). A
`schema_version: 2` record additionally PERSISTS a small set of **structured
signal fields** — leak-free by construction (bool / enum / shape-restricted
pointer), so they carry triage signal without any free-text channel:

| Field          | Type / domain                              | Notes                                              |
|----------------|--------------------------------------------|----------------------------------------------------|
| `reproducible` | boolean                                    | did the reporter reproduce it deterministically    |
| `impact`       | enum `low \| medium \| high` (RFC-0013 D1)  | blast radius                                       |
| `confidence`   | enum `low \| medium \| high`               | reporter confidence it is AAI-owned                |
| `workaround`   | enum `none \| manual \| automatic`         | cost of the current workaround                     |
| `evidence_ref` | safe pointer: repo-relative `docs/…` path OR an AAI doc id (`SPEC-0079`, …) | URLs / absolute paths / free text are REJECTED |
| `summary`      | opt-in short free-text (<= 200 chars)      | persisted ONLY when enabled AND certified clean    |
| `redaction_status` | enum `none \| capture_clean \| capture_dropped_fields` | which redaction outcome the capture pass recorded |

Structured/enum/bool/`evidence_ref` fields BYPASS the redactor by construction —
only `summary` is ever redacted.

### Summary redaction (D2/D3/D4)

The free-text `summary` is off by default. It is persisted only when
`.aai/feedback.yaml` `capture.summary_enabled: true` AND the hard redactor
(`.aai/scripts/lib/aai-redact.mjs`) certifies it clean. The redactor is
FAIL-CLOSED and defends in two layers:

1. **Allow-list charset gate (primary).** Deny-list detection of secrets in free
   text is fundamentally incomplete, so the summary is first required to consist
   ONLY of a conservative ASCII prose set (letters, digits, space, and
   `,.;:'"()!?_-`). This categorically rejects — before any detector runs — every
   non-ASCII character (zero-width spaces, fullwidth digits, homoglyphs), path
   separators (`/` `\`), `@` (emails/handles/git remotes), and `+ = ~`.
   `_` is PERMITTED (real AAI filenames use it, e.g. `AAI_PIN.md`); an
   underscore-prefixed secret like Stripe `sk_live_…` is instead caught by the
   deny-list token detectors below.
2. **Deny-list detectors (defense-in-depth)** for threats that live inside the
   safe charset: secret prefixes (`AKIA`, `sk-`, `ghp_`…), high-entropy and
   mixed-case-with-digit token runs, IPv4 and `::`-compressed IPv6, FQDNs, long
   digit runs, PEM headers.

If EITHER layer fires, the field is DROPPED (never persisted class-redacted in
the capture pass) and `redaction_status` becomes `capture_dropped_fields` — the
structured record still persists. Residual risk (RFC-0013 Risks, accepted): a
bare hostname with no dot is indistinguishable from an ordinary word and cannot
be detected in free text; the opt-in/off-by-default/local-only posture bounds the
blast radius. This is the CAPTURE pass of RFC-0013's double redaction; the
TRANSMIT pass (later upsert slice) re-runs the SAME shared redactor before any
external write.

---

## D6 persisted-field allowlist

Per RFC-0012 D6, the observation's persisted (and, in later phases,
transmittable) surface is a MINIMAL allowlist. The spool line for any accepted
`record` call contains EXACTLY these eight keys and NOTHING else:

| Persisted key    | Source                                                        |
|------------------|---------------------------------------------------------------|
| `schema_version` | fixed by the protocol (`1`).                                  |
| `os_family`      | derived locally — normalized enum `linux` / `macos` / `windows` / `unknown`. |
| `aai_pin`        | derived locally from `.aai/system/AAI_PIN.md` (see below).    |
| `node_major`     | derived locally — the running Node major version integer.     |
| `skill_id`       | from the validated input.                                     |
| `skill_phase`    | from the validated input.                                     |
| `failure_class`  | from the validated input.                                     |
| `fingerprint`    | computed — see the fingerprint section.                       |

**Deny-by-default (the privacy crux).** The persisted record is built by
COPYING ONLY the eight allowlisted keys into a fresh object. It is NEVER built
by copying the input and deleting a denylist. Consequently:

- named forbidden identity fields — hostnames, absolute paths, repository
  names/remotes, usernames, project identifiers — are absent BY CONSTRUCTION;
- ANY novel/unknown key a caller invents is likewise absent by construction
  (a future identity field cannot leak through a stale denylist);
- caller-supplied values for the locally derived fields (`os_family`,
  `aai_pin`, `node_major`) are IGNORED — the machine derives its own, so a
  caller cannot forge or poison them.

`os_family` normalization: `process.platform` maps `linux -> linux`,
`darwin -> macos`, `win32 -> windows`, anything else `-> unknown`. The raw
platform string is never persisted.

`aai_pin` derivation: the value of the `- Template version:` line in
`.aai/system/AAI_PIN.md`, whitespace-trimmed. If the file is absent, the field
is absent, the value is empty, OR the value is an unfilled sync placeholder
(begins with `<`), the literal string `unknown` is used. This is read-only
consumption of an existing frozen contract (never written by capture).

**Atomic-append size guard.** The spool is an append log written with O_APPEND
so concurrent `record` processes never lose or interleave lines — but that
guarantee holds only for a line strictly under PIPE_BUF (4096 bytes on
Linux/macOS). Atomicity is therefore made true BY CONSTRUCTION, not assumed:
the persisted string fields are capped at 128 chars (schema section), and after
serializing the single JSONL line `record` REJECTS it (clean non-zero exit, no
spool write) if it would reach PIPE_BUF — so a line at or above the bound is
never appended. With the caps and the short derived/computed fields this guard
never fires in normal use; it is the structural backstop, not the normal path.

---

## Fingerprint v1 algorithm

The fingerprint is a pure, deterministic, version-tagged function of a
NORMALIZED observation. It carries no environment-derived entropy, so the same
normalized observation yields the same fingerprint across independent runs and
across different machines.

Fingerprint version: `1`. The emitted `fingerprint` string is tagged with the
literal prefix `v1:` so a future algorithm revision is detectable.

Deterministic steps (v1):

1. **Select** the semantic-identity fields, in this fixed order:
   `skill_id`, `skill_phase`, `failure_class`, `expected_behavior`,
   `observed_behavior`. Environment fields (`os_family`, `node_major`,
   `aai_pin`), the `timestamp`, and all severity/prose optional fields are
   EXCLUDED — they must not change a friction's identity.
2. **Normalize** each selected field: lowercase (locale-independent), collapse
   every run of Unicode whitespace to a single space, then trim leading and
   trailing whitespace.
3. **Canonicalize**: join the normalized fields with the US (unit separator,
   ``) delimiter, prefixed with the literal `v1` and the same delimiter:
   `v1␟<skill_id>␟<skill_phase>␟<failure_class>␟<expected_behavior>␟<observed_behavior>`.
4. **Hash**: SHA-256 the UTF-8 bytes of the canonical string (`node:crypto`
   `createHash('sha256')`), hex-encode, and take the first 32 hex characters
   (128 bits).
5. **Tag**: the emitted fingerprint is `v1:` followed by those 32 hex
   characters.

Because step 2 normalizes case and whitespace, two observations that differ
only in the case or spacing of a normalized field produce the SAME
fingerprint. Any change to steps 1-5 requires a new version tag (`v2:`),
keeping v1 fingerprints comparable across releases.

---

## Redaction and privacy policy

Phase 0 is offline and local-first. The capture CLI holds no GitHub token and
performs no network I/O of any kind; nothing leaves the machine. The privacy
guarantee therefore rests on structural exclusion, not on trusting callers or
on scrubbing text after the fact:

- **Structural exclusion (D6).** Identity fields are excluded by construction
  (deny-by-default allowlist above), never merely redacted out. There is no
  code path that copies an unlisted key into the spool.
- **Local derivation of environment fields.** `os_family`, `aai_pin`, and
  `node_major` are derived on the machine and are coarse by design (OS family
  not full platform string; Node MAJOR only, not the full version; AAI pin
  version only). A caller cannot substitute finer-grained or forged values.
- **No prose persisted in Phase 0.** Descriptive free-text fields
  (`expected_behavior`, `observed_behavior`, `reproduction`, `workaround`,
  `recurrence`, `evidence_refs`, ...) are validated and may feed the
  fingerprint, but are NOT written to the Phase 0 spool line — so free-text
  that could carry incidental identity data does not reach persistent storage
  here. Later phases that persist or transmit richer records must apply the
  `redaction` status and the hard/double-redaction rules (RFC-0012 D5) before
  any external write; none of that machinery exists in Phase 0.
- **Untracked spool.** Observations are appended to
  `docs/ai/friction/observations.jsonl`, which is gitignored (only a
  `.gitkeep` is tracked) and never committed.
- **Capture never masks the caller.** `record` is a standalone process. A bad
  input exits non-zero with a specific documented code and a single-purpose
  stderr message (never an uncaught-exception stack trace, never a false
  success); stdout is empty on rejection. Capture failure must never replace or
  mask the calling skill's original result — exit codes are the contract.

The standing invariants a downstream reviewer/validation checks: "capture
emits nothing over the network" and "no identity field ever leaves the
machine". Both are enforced by the skill suite (`tests/skills/test-aai-friction.sh`).

---

## Skill wiring (shadow capture)

RFC-0012 Phase 1 — local **shadow mode**. This is the ONE canonical seam every
universal AAI skill inherits (via the pointer in `.aai/AGENTS.md`); thin
platform wrappers reference this section rather than duplicating it. Capture is
silent evidence-gathering only — there is no triage, no upstream write, and no
network in this phase.

**When to record.** While running any AAI skill, record a friction observation
ONLY when you hit evidence of an AAI-owned failure per the failure-class
taxonomy above (contradictory/impossible AAI instructions; a missing or invalid
AAI-owned file, command, template, or transition; a deterministic AAI
script/workflow-contract failure; repeated recovery caused by an AAI abstraction
leak; a human correction identifying an AAI prompt/skill defect; a documented
downstream or cross-platform contract violation). Honor the Exclusions list —
expected test failures, ordinary target-project bugs, invalid user input, HITL
pauses, transient provider/network failures, unavailable optional tools, and
cosmetic preferences are NOT friction unless recurrence shows a systemic
problem. When in doubt, do not record.

**How to record.** Build a schema-v1 observation (see "Observation schema v1")
and hand it to the offline capture CLI on stdin or a file:

```
node .aai/scripts/aai-friction.mjs record --input <path|->
```

The CLI applies the D6 deny-by-default allowlist and appends one JSONL line to
the untracked spool `docs/ai/friction/observations.jsonl`. It performs no
network I/O and holds no token.

**Shadow contract (best-effort, never masks the caller).** Capture is
**best-effort** and MUST NOT change, replace, or mask the calling skill's own
result — exit codes and outputs of the skill are the contract, not the capture.
If `record` is absent, errors, or rejects the observation, **swallow** that
outcome (a single INFO line at most) and continue the skill unchanged; never
escalate a capture failure into a skill failure, and never make the skill's
success depend on a successful capture. This mirrors the "Capture never masks
the caller" invariant above.

### Deterministic hook points (default-on capture)

The guidance above is recall-dependent by design for the general case. At the
following moments, capture is instead the DEFAULT best-effort action — the
owning prompt names the hook and invokes capture right there, so an agent does
not need to recall this protocol to trigger it:

- **Validation FAIL recorded** — `.aai/VALIDATION.prompt.md` produces a FAIL
  verdict (step 8).
- **Remediation dispatched** — `.aai/REMEDIATION.prompt.md` categorizes an
  incoming failure as AAI-owned (step 1/2), before applying any fix.
- **Canon-file gate/lint/CI failure** handled — a gate, lint, or CI check fails
  on an AAI-owned canon file: validation discovery (`.aai/VALIDATION.prompt.md`
  step 5h) and the post-open CI-failure handling point in
  `.aai/SKILL_PR.prompt.md` (step 5d).
- **Canon-surface check failure during implementation** — a test suite, gate,
  lint, or accounting check (e.g. the prompt-diet ledger/headroom guard) fails
  mid-implementation in `.aai/IMPLEMENTATION.prompt.md` (post-verification
  block; added as the validation R2 disposition — the headroom-cap trap class
  fired there with no hook present).

At each hook the default is ATTEMPT, not recall: build a schema-v2 observation
(see "Observation schema v2" above) for the fitting `failure_class` and invoke
the record command above. The failure-class taxonomy and its exclusions remain
the ownership gate unchanged — a hook does not widen what counts as AAI-owned
friction, it only removes the recall dependency for an event that already fits
the taxonomy. The shadow contract is unchanged at a hook: capture stays
best-effort, must never mask or change the primary step's own result, and any
capture failure (absent CLI, unwritable spool, rejected input) is swallowed
with at most a single INFO line — the hook never widens the contract, it only
widens WHEN capture is attempted.
