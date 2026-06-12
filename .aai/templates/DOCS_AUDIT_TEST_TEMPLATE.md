# Docs Audit CI Gate Template (RFC-0002)

Portable CI wrapper around `node .aai/scripts/docs-audit.mjs --check`.
The audit gate is the script's exit code, so any test runner or plain CI step
works. Pick the variant matching your stack and copy it into your project.

The gate hard-fails only in enforced mode (when `docs/ai/docs-audit.yaml`
exists with a `legacy_until_date`). Without the config the audit is
report-only and the gate passes — enable enforcement deliberately.

## Plain CI step (any provider)

```yaml
# e.g. .github/workflows/ci.yml
- name: Docs hygiene gate (RFC-0002)
  run: node .aai/scripts/docs-audit.mjs --check --no-event
```

## Vitest wrapper

Copy to `docs/__tests__/aai-docs-tracker.test.ts`:

```ts
import { describe, it } from 'vitest';
import { execFileSync } from 'node:child_process';

describe('AAI docs hygiene (RFC-0002)', () => {
  it('has no new orphan docs and no schema violations', () => {
    // Throws (failing the test) when --check exits non-zero; stdout is
    // attached to the error so the digest shows up in the test report.
    execFileSync('node', ['.aai/scripts/docs-audit.mjs', '--check', '--no-event'], {
      cwd: process.cwd(),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  }, 30_000);
});
```

## Pytest wrapper

Copy to `docs/__tests__/test_aai_docs_tracker.py`:

```python
import subprocess

def test_docs_hygiene_gate():
    # Fails with the audit digest in the assertion message on a non-zero exit.
    result = subprocess.run(
        ["node", ".aai/scripts/docs-audit.mjs", "--check", "--no-event"],
        capture_output=True, text=True, timeout=30,
    )
    assert result.returncode == 0, result.stdout
```

## Notes

- `--no-event` keeps CI runs out of `docs/ai/EVENTS.jsonl` — audit events
  belong to operator/loop runs, not to every CI execution.
- The gate is per-repo (RFC-0002 D5): submodules with their own AAI layer
  mount their own copy.
- Do not edit docs to silence the gate from CI; triage via `/aai-docs-audit`.
