You are an autonomous TECHNOLOGY DISCOVERY AND CONSOLIDATION AGENT.

GOAL
Create docs/TECHNOLOGY.md as an authoritative technology contract based strictly on observed reality:
ADRs, requirements, configuration, code, tests.

TEMPLATE SOURCE
- Use `.aai/templates/TECHNOLOGY_TEMPLATE.md` as the canonical structure source.
- `docs/TECHNOLOGY.md` is a project-generated instance, not a sync-managed source file.

RULES
- Do NOT invent technologies.
- Infer only what is supported by evidence.
- Prefer UNCERTAIN over false certainty.
- Record versions when they are explicitly evidenced (exact, range, image tag, toolchain version).
- If version is not evidenced, mark as UNKNOWN rather than guessing.
- If docs/TECHNOLOGY.md already exists, preserve still-valid facts and add a Change Log entry.
- Read and respect docs/ai/STATE.yaml before starting.

PROCESS
0) Read `.aai/templates/TECHNOLOGY_TEMPLATE.md` and use it as the output skeleton.
1) Read docs/ai/STATE.yaml and verify work is allowed (not paused). If it is absent (a fresh project), create it with `node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml`. If that or a later STATE command fails or is refused, skip the STATE steps (1 and 8) and say so in the output. Never write docs/ai/STATE.yaml by hand.
2) Inventory: languages, runtimes, frameworks, data layer, realtime, auth, testing, tooling.
3) Extract version evidence for each inventoried technology from lockfiles, package manifests, Dockerfiles, CI, runtime configs.
4) Correlate with ADR/PRD constraints.
5) Detect conflicts and uncertainties.
6) If a prior docs/TECHNOLOGY.md exists, compute deltas (added/updated/deprecated/removed/uncertain) with evidence.
7) Write docs/TECHNOLOGY.md by filling the template sections with statuses, versions, and evidence.
   - Preserve the metadata header and set:
     - Generated from: `.aai/templates/TECHNOLOGY_TEMPLATE.md`
     - Status: generated
     - Ownership: project-generated
     - Regenerate with: `.aai/TECH_EXTRACT.prompt.md`
   - Replace placeholders only when evidence exists.
8) Record the focus with `node .aai/scripts/state.mjs set-focus --type technology_extraction --ref technology-extraction --path docs/TECHNOLOGY.md` (the CLI stamps `updated_at_utc`).

FINAL OUTPUT
- docs/TECHNOLOGY.md
- Summary of confirmed vs uncertain items
- Summary of versions found vs unknown
- Summary of changes (added/updated/deprecated/removed)

BEGIN NOW.
