# Decapod Integration Skill

## Goal
Integrate Decapod attestation and compliance framework into the AAI workflow.

## What is Decapod?
Decapod is a compliance and attestation framework that provides:
- Advisory checks before planning (risk analysis, compliance gates)
- Attestation artifacts after validation (proof of testing, coverage, deployment)
- Integration with SOC2, ISO27001, and regulatory frameworks

## Prerequisites

### Check Installation
```bash
which decapod || echo "Not installed"
decapod --version
```

### Install (if needed)
```bash
npm install -g @decapod/cli
# or
pip install decapod-cli
```

### Initialize Project
```bash
decapod init
# Creates .decapod/config.yaml
```

## Operations

### 1. Pre-Planning Advisory (`/aai-decapod check`)

Run before planning to check for compliance issues:

```bash
decapod advisory --input docs/ai/intake/latest.md --output .decapod/advisory.json
```

**Integration with /aai-intake:**
- After intake artifact is saved, automatically run advisory check
- If high-severity findings exist, warn user before proceeding
- Save findings to `docs/ai/compliance/advisory-<timestamp>.json`

**Advisory Output:**
```json
{
  "verdict": "PASS|WARN|BLOCK",
  "findings": [
    {
      "severity": "high|medium|low",
      "category": "security|privacy|compliance",
      "message": "PII detected in requirement — data classification required",
      "recommendation": "Add data retention policy to PRD"
    }
  ]
}
```

**Action Logic:**
- `PASS`: Proceed normally
- `WARN`: Display warnings, ask user to acknowledge
- `BLOCK`: Halt workflow, require remediation

### 2. Post-Validation Attestation (`/aai-decapod attest`)

Generate attestation artifacts after validation:

```bash
decapod attest \
  --validation-report docs/ai/reports/LATEST.md \
  --coverage docs/ai/coverage/latest.json \
  --output .decapod/attestations/attest-<timestamp>.json
```

**Integration with /aai-validate-report:**
- After validation report is generated, automatically create attestation
- Include test results, coverage metrics, and screenshot evidence
- Sign with project key if configured

**Attestation Artifact:**
```json
{
  "attestation_id": "ATT-20260307-123456Z",
  "validation_run_id": "20260307-123456Z",
  "timestamp": "2026-03-07T12:34:56Z",
  "verdict": "PASS",
  "evidence": {
    "test_results": "docs/ai/reports/validation-20260307-123456Z.md",
    "screenshots": ["docs/ai/reports/screenshots/20260307-123456Z/*"],
    "coverage": {"line": 87, "branch": 82}
  },
  "signature": "sha256:abc123...",
  "compliance_frameworks": ["SOC2", "ISO27001"]
}
```

Save to:
- `.decapod/attestations/attest-<timestamp>.json`
- `docs/ai/compliance/attestations/attest-<timestamp>.json` (copy for archival)

Update `docs/ai/STATE.yaml`:
```yaml
compliance:
  last_attestation:
    id: ATT-20260307-123456Z
    timestamp: 2026-03-07T12:34:56Z
    verdict: PASS
    artifact_path: docs/ai/compliance/attestations/attest-20260307-123456Z.json
```

### 3. Configuration Management

**Check Config:**
```bash
decapod config show
```

**Default `.decapod/config.yaml`:**
```yaml
version: 1
project:
  name: ${PROJECT_NAME}
  compliance_frameworks:
    - SOC2
    - ISO27001

advisory:
  enabled: true
  severity_threshold: medium
  categories:
    - security
    - privacy
    - compliance

attestation:
  enabled: true
  sign_artifacts: false
  retention_days: 365
  output_dir: .decapod/attestations

integrations:
  aai:
    intake_hook: true
    validation_hook: true
```

**Create Default Config (if not exists):**
```bash
mkdir -p .decapod
cat > .decapod/config.yaml << 'EOF'
version: 1
project:
  name: ${PROJECT_NAME}
  compliance_frameworks: [SOC2, ISO27001]
advisory:
  enabled: true
  severity_threshold: medium
attestation:
  enabled: true
  sign_artifacts: false
integrations:
  aai:
    intake_hook: true
    validation_hook: true
EOF
```

### 4. Query Attestations

List all attestations:
```bash
decapod attest list --format json
```

View specific attestation:
```bash
decapod attest show ATT-20260307-123456Z
```

### 5. Compliance Report

Generate compliance dashboard:
```bash
decapod report --output docs/ai/compliance/report.html
```

## Usage Examples

### Example 1: Check Before Planning
```bash
# User runs: /aai-intake "Add user authentication"
# System saves intake artifact
# Auto-run:
decapod advisory --input docs/ai/intake/PRD-001.md --output .decapod/advisory-PRD-001.json

# If WARN or BLOCK, display findings:
# ⚠️  Advisory Findings:
# - [HIGH] Security: Authentication system requires penetration testing plan
# - [MEDIUM] Compliance: User data storage needs privacy impact assessment
#
# Continue anyway? (y/n)
```

### Example 2: Attest After Validation
```bash
# User runs: /aai-validate-report
# System generates validation report
# Auto-run:
decapod attest \
  --validation-report docs/ai/reports/validation-20260307-123456Z.md \
  --output .decapod/attestations/attest-20260307-123456Z.json

# Output:
# ✓ Attestation created: ATT-20260307-123456Z
# ✓ Evidence: 12 tests passed, 87% coverage, 5 screenshots
# ✓ Saved to: docs/ai/compliance/attestations/attest-20260307-123456Z.json
```

### Example 3: Manual Compliance Check
```bash
# User runs: /aai-decapod check docs/ai/intake/HOTFIX-005.md
decapod advisory --input docs/ai/intake/HOTFIX-005.md --severity high
```

## Integration Points

### Hook: After /aai-intake
```yaml
# In .decapod/config.yaml
integrations:
  aai:
    intake_hook: true
```

After intake artifact is saved, run:
```bash
decapod advisory --input <intake-artifact> --output .decapod/advisory-<ref-id>.json
```

### Hook: After /aai-validate-report
```yaml
# In .decapod/config.yaml
integrations:
  aai:
    validation_hook: true
```

After validation report is generated, run:
```bash
decapod attest \
  --validation-report docs/ai/reports/LATEST.md \
  --output .decapod/attestations/attest-<run-id>.json
```

## File Structure
```
.decapod/
├── config.yaml              # Decapod configuration
├── advisory-<ref-id>.json   # Advisory findings per intake
└── attestations/
    └── attest-<timestamp>.json  # Attestation artifacts

docs/ai/compliance/
├── advisory/
│   └── advisory-<timestamp>.json
├── attestations/
│   └── attest-<timestamp>.json
└── report.html              # Compliance dashboard
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `decapod: not found` | `npm install -g @decapod/cli` or `pip install decapod-cli` |
| Config not found | `decapod init` or create `.decapod/config.yaml` manually |
| Advisory fails | Check input file exists and is valid Markdown |
| Attestation fails | Ensure validation report exists at specified path |
| Hook not firing | Check `.decapod/config.yaml` has `integrations.aai.intake_hook: true` |

## Security Notes
- Attestations are NOT cryptographically signed by default
- Enable signing with: `attestation.sign_artifacts: true` in config
- Store signing keys securely (not in git)
- Attestation artifacts contain references to test results but not credentials

## Setup Instructions

### First-Time Setup
```bash
# 1. Install Decapod
npm install -g @decapod/cli

# 2. Initialize in project
cd <project-root>
decapod init

# 3. Enable AAI integration
cat >> .decapod/config.yaml << 'EOF'
integrations:
  aai:
    intake_hook: true
    validation_hook: true
EOF

# 4. Test
decapod config show
```

### Verify Integration
```bash
# Run intake and check for advisory
/aai-intake "test feature"
# Should see: "Running decapod advisory check..."

# Run validation and check for attestation
/aai-validate-report
# Should see: "Generating decapod attestation..."
```

## Advanced: Custom Policies

Create `.decapod/policies/security.yaml`:
```yaml
rules:
  - id: AUTH-001
    name: Authentication required for user data
    severity: high
    pattern: "user.*data|personal.*information"
    message: "Features handling user data require authentication design"

  - id: TEST-001
    name: Minimum coverage threshold
    severity: medium
    check: coverage.line >= 80
    message: "Line coverage must be >= 80%"
```

Load policies:
```bash
decapod advisory --policies .decapod/policies/*.yaml
```

## Compliance Frameworks

Supported frameworks:
- **SOC2**: Service Organization Control 2
- **ISO27001**: Information Security Management
- **HIPAA**: Healthcare data protection
- **GDPR**: EU privacy regulation
- **PCI-DSS**: Payment card security

Configure in `.decapod/config.yaml`:
```yaml
project:
  compliance_frameworks:
    - SOC2
    - ISO27001
```

## Output

After running `/aai-decapod`:
```
Decapod Integration Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Installation:     ✓ Installed (v2.1.0)
Configuration:    ✓ Found (.decapod/config.yaml)
Frameworks:       SOC2, ISO27001

Integration Hooks:
  intake_hook:      ✓ Enabled
  validation_hook:  ✓ Enabled

Last Advisory:    2026-03-07 12:30:00 UTC
  Verdict:        PASS
  Findings:       2 warnings, 0 blocks

Last Attestation: 2026-03-07 11:45:00 UTC
  ID:             ATT-20260307-114500Z
  Verdict:        PASS
  Evidence:       12 tests, 87% coverage, 5 screenshots

Commands:
  /aai-decapod check <file>   - Run advisory check on file
  /aai-decapod attest         - Generate attestation from latest validation
  /aai-decapod report         - Generate compliance dashboard
  /aai-decapod config         - Show current configuration
```

BEGIN NOW.
