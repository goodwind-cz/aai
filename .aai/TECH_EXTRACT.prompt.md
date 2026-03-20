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
1) Read docs/ai/STATE.yaml and verify work is allowed (not paused).
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
8) Update docs/ai/STATE.yaml:
   - current_focus
   - active_work_items status for technology extraction scope
   - updated_at_utc

FINAL OUTPUT
- docs/TECHNOLOGY.md
- Summary of confirmed vs uncertain items
- Summary of versions found vs unknown
- Summary of changes (added/updated/deprecated/removed)

BEGIN NOW.
