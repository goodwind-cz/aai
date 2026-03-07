# Decapod + AAI Workflow

## Visual Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    AAI + Decapod Integration                     │
└─────────────────────────────────────────────────────────────────┘

PHASE 1: INTAKE & ADVISORY
──────────────────────────────────────────────────────────────────
User: /aai-intake "Add user authentication with SSO"
                            ↓
              SKILL_INTAKE.prompt.md
                            ↓
         Creates: docs/ai/intake/PRD-001.md
                            ↓
                   [DECAPOD HOOK]
                            ↓
          decapod advisory --input PRD-001.md
                            ↓
                   Checks for:
                   • Security risks
                   • Privacy concerns
                   • Compliance issues
                            ↓
          Saves: compliance/advisory/PRD-001.json
                            ↓
        ┌─────────┬─────────┬─────────┐
        │  PASS   │  WARN   │  BLOCK  │
        └─────────┴─────────┴─────────┘
            ↓         ↓          ↓
      Continue   Ask User   Halt Work
                  Confirm


PHASE 2: PLANNING & IMPLEMENTATION
──────────────────────────────────────────────────────────────────
User: /aai-loop
                            ↓
         Planning → Implementation → Testing
                            ↓
              Standard AAI workflow
                            ↓
         (No Decapod interaction here)


PHASE 3: VALIDATION & ATTESTATION
──────────────────────────────────────────────────────────────────
User: /aai-validate-report
                            ↓
           VALIDATION.prompt.md
                            ↓
            Runs tests, checks coverage
                            ↓
          Captures screenshots (if any)
                            ↓
    Creates: docs/ai/reports/validation-<RUN_ID>.md
                            ↓
                   [DECAPOD HOOK]
                            ↓
        decapod attest --validation-report LATEST.md
                            ↓
               Collects evidence:
               • Test results (12 passed)
               • Coverage (87% line, 82% branch)
               • Screenshots (5 files)
                            ↓
  Saves: compliance/attestations/attest-<RUN_ID>.json
                            ↓
         Updates: docs/ai/STATE.yaml
         ├── compliance.last_attestation.id
         ├── compliance.last_attestation.verdict
         └── compliance.last_attestation.artifact_path
                            ↓
                    ✓ COMPLETE


PHASE 4: COMPLIANCE REPORTING (Optional)
──────────────────────────────────────────────────────────────────
User: /aai-decapod report
                            ↓
     Generates: compliance/report.html
                            ↓
          Dashboard showing:
          • All attestations (timeline)
          • Advisory history (findings)
          • Framework coverage (SOC2, ISO27001)
          • Trend graphs (coverage, test count)
```

## Example Lifecycle

### 1. Start New Feature

```bash
/aai-intake "Add user authentication with SSO support"
```

**Output:**
```
Intake type: prd
Creating PRD-001.md...
Running Decapod advisory check...

⚠️  Advisory Findings:

[HIGH] Security
  Authentication system requires penetration testing plan
  → Add security testing requirements to acceptance criteria

[MEDIUM] Privacy
  PII detected - user email requires data classification
  → Document data retention policy

Continue anyway? (y/n) y

✓ Intake saved: docs/ai/intake/PRD-001.md
✓ Advisory saved: docs/ai/compliance/advisory/PRD-001.json
Next: /aai-loop to begin planning
```

### 2. Implement Feature

```bash
/aai-loop
```

**Output:**
```
Planning phase...
✓ Created implementation plan
✓ Generated test specifications

Implementation phase...
✓ Implemented authentication service
✓ Implemented SSO provider integration
✓ Created unit tests
✓ Created integration tests

Ready for validation
```

### 3. Validate & Attest

```bash
/aai-validate-report
```

**Output:**
```
Running validation...
✓ 12 tests passed (0 failed)
✓ Coverage: 87% line, 82% branch
✓ 5 screenshots captured

Generating Decapod attestation...
✓ Attestation created: ATT-20260307-123456Z
✓ Evidence collected:
  - Test results: 12 passed
  - Coverage: 87.3% line, 82.1% branch
  - Screenshots: 5 files
  - Compliance: SOC2, ISO27001

✓ Attestation saved: docs/ai/compliance/attestations/attest-20260307-123456Z.json
✓ STATE.yaml updated

Validation: PASS
Report: /workspace/extra/ai-os/docs/ai/reports/LATEST.md
```

### 4. Generate Compliance Report

```bash
/aai-decapod report
```

**Output:**
```
Generating compliance dashboard...
✓ Included 3 attestations
✓ Included 5 advisory checks
✓ Framework coverage: SOC2 (100%), ISO27001 (100%)
✓ Report saved: docs/ai/compliance/report.html

Open: file:///workspace/extra/ai-os/docs/ai/compliance/report.html
```

## Decision Flow

### Advisory Check Decision Tree

```
Advisory Check Result
         ↓
    ┌────┴────┐
    │ Verdict │
    └────┬────┘
         │
    ┌────┴────────────┬─────────────┐
    ↓                 ↓             ↓
  PASS              WARN          BLOCK
    │                 │             │
    ↓                 ↓             ↓
Continue        Show Findings   Halt Workflow
 Silently       Ask: Continue?  Require Fix
                     │
               ┌─────┴─────┐
               ↓           ↓
              Yes         No
               │           │
               ↓           ↓
          Continue    Save & Exit
          with Log
```

### Attestation Verdict Flow

```
Validation Results
         ↓
    ┌────┴────┐
    │ Tests   │
    └────┬────┘
         │
    ┌────┴────────┐
    ↓             ↓
 All Pass     Any Fail
    │             │
    ↓             ↓
Attest PASS   Attest FAIL
    │             │
    ↓             ↓
Sign & Store  Mark Blocked
Update STATE  Require Retest
```

## File Relationships

```
.decapod/config.yaml (project config)
        ↓
        ├─→ Enables: advisory.enabled = true
        │            ↓
        │   Triggers on: /aai-intake completion
        │            ↓
        │   Creates: compliance/advisory/<ref-id>.json
        │
        └─→ Enables: attestation.enabled = true
                     ↓
            Triggers on: /aai-validate-report completion
                     ↓
            Creates: compliance/attestations/attest-<RUN_ID>.json
                     ↓
            Updates: docs/ai/STATE.yaml
                     └─→ compliance.last_attestation.*
```

## Integration Points Summary

| AAI Skill | Decapod Integration | Artifact Created | STATE.yaml Updated |
|-----------|---------------------|------------------|-------------------|
| `/aai-intake` | Advisory check | `compliance/advisory/<ref-id>.json` | `compliance.last_advisory.*` |
| `/aai-validate-report` | Attestation generation | `compliance/attestations/attest-<RUN_ID>.json` | `compliance.last_attestation.*` |
| `/aai-decapod` | Status/manual ops | Report, config display | No |

## Commands Reference

### Check Status
```bash
/aai-decapod
```
Shows installation, config, hooks, and recent activity

### Manual Advisory Check
```bash
/aai-decapod check <file-path>
```
Run advisory on specific file (e.g., `docs/ai/intake/HOTFIX-005.md`)

### Manual Attestation
```bash
/aai-decapod attest
```
Generate attestation from latest validation (if validation hook failed)

### List Attestations
```bash
/aai-decapod attest list
```
Show all attestations with verdict and date

### Show Attestation Details
```bash
/aai-decapod attest show <ATT-ID>
```
Display full details of specific attestation

### Generate Dashboard
```bash
/aai-decapod report
```
Create HTML compliance dashboard

### Show Configuration
```bash
/aai-decapod config
```
Display current `.decapod/config.yaml` settings

---

**Next Steps:**
1. Install Decapod: `npm install -g @decapod/cli`
2. Initialize: `decapod init` in project root
3. Enable hooks in `.decapod/config.yaml`
4. Run `/aai-decapod` to verify

**See Also:**
- [DECAPOD_INTEGRATION.md](../DECAPOD_INTEGRATION.md) - Complete setup guide
- [README.md](./README.md) - Compliance directory overview
