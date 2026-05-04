# AAI Self-Hosting Contract

AAI may be used to evolve itself, but only under a strict separation of concerns.

## Ownership model

### 1. Canonical authoring layer
This is the source of truth for reusable AAI behavior.

Includes:
- `.aai/*.prompt.md`
- `.aai/templates/*`
- `.aai/system/*`
- `.aai/scripts/*`
- shim docs such as `README.md`, `CLAUDE.md`, `CODEX.md`, `GEMINI.md`, `SKILLS.md`

Rules:
- Changes to reusable behavior must land here.
- Do not treat generated project docs as the source of truth.

### 2. Project-generated layer
This is the instantiated AAI state for one repository.

Includes:
- `docs/TECHNOLOGY.md`
- `docs/requirements/*`
- `docs/specs/*`
- `docs/decisions/*`
- `docs/knowledge/*`
- `docs/project-sessions/*`

Rules:
- These files describe the current repository instance.
- They may be regenerated or updated from prompts/templates.
- They must not be used as the canonical source for sync-managed behavior.

### 3. Runtime layer
This is local-only execution evidence and state.

Includes:
- `docs/ai/STATE.yaml`
- `docs/ai/*.jsonl`
- `docs/ai/reports/**`

Rules:
- Never treat runtime artifacts as reusable source content.
- Never commit runtime evidence as canonical product/project documentation.
- Promote only durable conclusions into project-generated docs.

## Recommended self-hosting workflow

1. Run the worktree recommendation gate for the AAI change.
   - A dedicated worktree/branch is strongly recommended for reusable AAI behavior.
   - The user may explicitly choose inline mode; record the override and review scope.
2. Implement the reusable change in the canonical authoring layer.
3. Sync the updated AAI into a disposable fixture target project.
4. Verify that the target project receives:
   - prompts/templates/scripts
   - seeded `docs/TECHNOLOGY.md`
   - expected ignore rules for runtime artifacts
5. Run smoke validation in the disposable target.
6. Only then merge the change into the canonical repo.

## Guardrails

- Do not modify canonical prompts by editing generated docs.
- Do not use `docs/ai/reports/` as long-term design memory.
- Do not overwrite a target project's filled `docs/TECHNOLOGY.md` during sync.
- Seed missing project docs from templates; preserve project-owned content after first generation.

## Fixture verification

Use the disposable fixture under `tests/fixtures/target-project/` plus:
- `tests/self-hosting/test-self-hosting-smoke.ps1`
- `tests/self-hosting/test-self-hosting-smoke.sh`

These checks verify the packaging and ownership model, not business-specific application code.
