# Decapod Integration Guide

## Overview

Decapod is a compliance and attestation framework that integrates with the AAI (Autonomous AI) workflow to provide:

- **Advisory checks** before planning (risk analysis, compliance gates)
- **Attestation artifacts** after validation (proof of testing, coverage, deployment)
- **Framework support** for SOC2, ISO27001, HIPAA, GDPR, and PCI-DSS

This integration adds compliance awareness to the AAI development lifecycle without disrupting the existing workflow.

## Architecture

```
AAI Workflow + Decapod Integration
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  /aai-intake → INTAKE ARTIFACT → [DECAPOD ADVISORY CHECK]      │
│                                           ↓                     │
│                                      PASS|WARN|BLOCK            │
│                                           ↓                     │
│  /aai-loop   → PLANNING/IMPLEMENTATION                         │
│                                           ↓                     │
│  /aai-validate-report → VALIDATION REPORT                      │
│                                           ↓                     │
│                              [DECAPOD ATTESTATION]              │
│                                           ↓                     │
│                              ATTESTATION ARTIFACT               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Setup Instructions

### 1. Install Decapod CLI

**Option A: npm**
```bash
npm install -g @decapod/cli
```

**Option B: pip**
```bash
pip install decapod-cli
```

**Verify Installation:**
```bash
decapod --version
# Expected: v2.1.0 or later
```

### 2. Initialize Decapod in Your Project

From your project root:

```bash
decapod init
```

This creates `.decapod/config.yaml` with default settings.

### 3. Configure AAI Integration

Enable the AAI hooks in `.decapod/config.yaml`:

```yaml
version: 1
project:
  name: my-project
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
    intake_hook: true      # Run advisory after /aai-intake
    validation_hook: true  # Generate attestation after /aai-validate-report
```

### 4. Verify Integration

Run the Decapod skill to check status:

```bash
/aai-decapod
```

You should see:
```
Decapod Integration Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Installation:     ✓ Installed (v2.1.0)
Configuration:    ✓ Found (.decapod/config.yaml)
Frameworks:       SOC2, ISO27001

Integration Hooks:
  intake_hook:      ✓ Enabled
  validation_hook:  ✓ Enabled
```

## How It Works

### Phase 1: Advisory Checks (Pre-Planning)

When you run `/aai-intake`, the system:

1. Collects requirements and creates intake artifact (e.g., `docs/ai/intake/PRD-001.md`)
2. **Automatically runs Decapod advisory check:**
   ```bash
   decapod advisory --input docs/ai/intake/PRD-001.md --output .decapod/advisory-PRD-001.json
   ```
3. Analyzes the findings based on severity:
   - **PASS**: No issues, proceed normally
   - **WARN**: Display warnings, ask user to acknowledge
   - **BLOCK**: Critical compliance issue, halt workflow

4. Saves advisory results to:
   - `.decapod/advisory-<ref-id>.json` (working copy)
   - `docs/ai/compliance/advisory/<timestamp>.json` (archive)

**Example Advisory Output:**

```json
{
  "verdict": "WARN",
  "findings": [
    {
      "severity": "high",
      "category": "security",
      "message": "PII detected in requirement — data classification required",
      "recommendation": "Add data retention policy to PRD"
    },
    {
      "severity": "medium",
      "category": "compliance",
      "message": "User data storage needs privacy impact assessment",
      "recommendation": "Document data flows in architecture section"
    }
  ]
}
```

**What You See:**

```
⚠️  Decapod Advisory Findings:

[HIGH] Security
  PII detected in requirement — data classification required
  → Add data retention policy to PRD

[MEDIUM] Compliance
  User data storage needs privacy impact assessment
  → Document data flows in architecture section

Continue anyway? (y/n)
```

### Phase 2: Attestation Generation (Post-Validation)

When you run `/aai-validate-report`, the system:

1. Executes standard validation (tests, coverage, screenshots)
2. Generates validation report (e.g., `docs/ai/reports/validation-20260307-123456Z.md`)
3. **Automatically creates Decapod attestation:**
   ```bash
   decapod attest \
     --validation-report docs/ai/reports/LATEST.md \
     --coverage docs/ai/coverage/latest.json \
     --output .decapod/attestations/attest-20260307-123456Z.json
   ```
4. Saves attestation artifact with:
   - Unique attestation ID
   - Test results and coverage metrics
   - Screenshot evidence paths
   - Compliance framework mappings
   - Optional cryptographic signature

5. Updates `docs/ai/STATE.yaml` with attestation metadata

**Example Attestation Artifact:**

```json
{
  "attestation_id": "ATT-20260307-123456Z",
  "validation_run_id": "20260307-123456Z",
  "timestamp": "2026-03-07T12:34:56Z",
  "verdict": "PASS",
  "evidence": {
    "test_results": "docs/ai/reports/validation-20260307-123456Z.md",
    "screenshots": [
      "docs/ai/reports/screenshots/20260307-123456Z/login-page.png",
      "docs/ai/reports/screenshots/20260307-123456Z/dashboard.png"
    ],
    "coverage": {
      "line": 87,
      "branch": 82
    }
  },
  "signature": "sha256:abc123def456...",
  "compliance_frameworks": ["SOC2", "ISO27001"]
}
```

**What You See:**

```
✓ Attestation created: ATT-20260307-123456Z
✓ Evidence: 12 tests passed, 87% coverage, 5 screenshots
✓ Saved to: docs/ai/compliance/attestations/attest-20260307-123456Z.json
```

## Benefits Over Plain AAI

| Feature | Plain AAI | AAI + Decapod |
|---------|-----------|---------------|
| **Pre-Planning Risk Analysis** | Manual review | Automated advisory checks |
| **Compliance Gates** | None | WARN/BLOCK verdicts with remediation guidance |
| **Validation Evidence** | Markdown reports | Cryptographically signed attestations |
| **Audit Trail** | Git history | Immutable attestation artifacts |
| **Framework Mapping** | Manual | Automatic SOC2/ISO27001/HIPAA mapping |
| **Retention Policy** | Not enforced | Configurable retention (default 365 days) |
| **Searchable History** | Git grep | `decapod attest list --filter "verdict:PASS"` |

## File Structure

After setup and first run, your project will have:

```
project-root/
├── .decapod/
│   ├── config.yaml                    # Decapod configuration
│   ├── advisory-PRD-001.json          # Advisory results (latest)
│   └── attestations/
│       ├── attest-20260307-123456Z.json
│       └── attest-20260308-091234Z.json
│
├── docs/ai/
│   ├── STATE.yaml                     # Updated with compliance metadata
│   ├── compliance/
│   │   ├── advisory/
│   │   │   ├── advisory-20260307-120000Z.json
│   │   │   └── advisory-20260308-090000Z.json
│   │   ├── attestations/
│   │   │   ├── attest-20260307-123456Z.json
│   │   │   └── attest-20260308-091234Z.json
│   │   └── report.html                # Compliance dashboard
│   └── reports/
│       ├── LATEST.md
│       └── validation-20260307-123456Z.md
│
└── .gitignore                         # Add .decapod/* (exclude from git)
```

**Recommended .gitignore entries:**

```gitignore
# Decapod working files (ephemeral)
.decapod/advisory-*.json
.decapod/attestations/

# Keep compliance archives in git
!docs/ai/compliance/
```

## Usage Examples

### Example 1: Check Before Planning

```bash
# User command
/aai-intake "Add user authentication with SSO support"

# System output
Intake type: prd
Creating PRD-001.md...
Running Decapod advisory check...

⚠️  Advisory Findings:

[HIGH] Security
  Authentication system requires penetration testing plan
  → Add security testing requirements to acceptance criteria

[MEDIUM] Compliance
  SSO integration needs data privacy impact assessment
  → Document user data flows and third-party integrations

Continue anyway? (y/n) _
```

If you answer `y`, the workflow continues. If `n`, the intake is saved but marked as blocked.

### Example 2: Generate Attestation After Validation

```bash
# User command
/aai-validate-report

# System output
Running validation...
✓ 12 tests passed
✓ Coverage: 87% line, 82% branch
✓ 5 screenshots captured

Generating Decapod attestation...
✓ Attestation created: ATT-20260307-123456Z
✓ Evidence: docs/ai/reports/validation-20260307-123456Z.md
✓ Frameworks: SOC2, ISO27001
✓ Saved to: docs/ai/compliance/attestations/attest-20260307-123456Z.json

Validation complete: PASS
Report: /workspace/project/docs/ai/reports/LATEST.md
```

### Example 3: Manual Compliance Check

```bash
# Check a specific file for compliance issues
/aai-decapod check docs/ai/intake/HOTFIX-005.md

# Output
Running advisory check on HOTFIX-005.md...

✓ No compliance issues found
Verdict: PASS

Advisory saved to: .decapod/advisory-HOTFIX-005.json
```

### Example 4: Query Attestation History

```bash
# List all attestations
/aai-decapod attest list

# Output
Attestations:
- ATT-20260308-091234Z  PASS  2026-03-08 09:12:34 UTC  (12 tests, 87% coverage)
- ATT-20260307-123456Z  PASS  2026-03-07 12:34:56 UTC  (10 tests, 85% coverage)
- ATT-20260306-154321Z  FAIL  2026-03-06 15:43:21 UTC  (8 tests, 2 failed)
```

### Example 5: Generate Compliance Dashboard

```bash
# Generate HTML dashboard with all compliance data
/aai-decapod report

# Output
Generating compliance report...
✓ Included 3 attestations
✓ Included 5 advisory checks
✓ Report saved to: docs/ai/compliance/report.html

Open in browser: file:///workspace/project/docs/ai/compliance/report.html
```

## Advanced Configuration

### Custom Compliance Policies

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

  - id: PII-001
    name: PII detection
    severity: high
    pattern: "email|phone|ssn|credit.?card"
    message: "PII detected — add data classification and retention policy"
```

Load custom policies:

```bash
decapod advisory --policies .decapod/policies/*.yaml
```

### Cryptographic Signing

Enable attestation signing in `.decapod/config.yaml`:

```yaml
attestation:
  sign_artifacts: true
  signing_key_path: ~/.decapod/signing-key.pem  # Keep out of git!
```

Generate a signing key:

```bash
# Generate RSA key pair
openssl genrsa -out ~/.decapod/signing-key.pem 2048
openssl rsa -in ~/.decapod/signing-key.pem -pubout -out ~/.decapod/signing-key.pub

# Verify attestation signature
decapod attest verify ATT-20260307-123456Z --public-key ~/.decapod/signing-key.pub
```

### Framework-Specific Settings

Configure per-framework requirements:

```yaml
project:
  compliance_frameworks:
    - SOC2
    - ISO27001
    - HIPAA

frameworks:
  SOC2:
    controls:
      - CC6.1  # Logical access controls
      - CC7.2  # System monitoring

  ISO27001:
    controls:
      - A.12.6.1  # Technical vulnerability management
      - A.14.2.8  # System security testing

  HIPAA:
    safeguards:
      - technical
      - administrative
    requires_encryption: true
```

## Integration with AAI Workflow

### STATE.yaml Updates

After attestation generation, `docs/ai/STATE.yaml` is updated:

```yaml
last_validation:
  run_at_utc: 2026-03-07T12:34:56Z
  verdict: PASS
  evidence_paths:
    - docs/ai/reports/validation-20260307-123456Z.md
    - docs/ai/reports/screenshots/20260307-123456Z/

compliance:
  last_advisory:
    ref_id: PRD-001
    timestamp: 2026-03-07T10:00:00Z
    verdict: WARN
    findings_count: 2
    artifact_path: docs/ai/compliance/advisory/advisory-20260307-100000Z.json

  last_attestation:
    id: ATT-20260307-123456Z
    timestamp: 2026-03-07T12:34:56Z
    verdict: PASS
    frameworks: [SOC2, ISO27001]
    artifact_path: docs/ai/compliance/attestations/attest-20260307-123456Z.json

updated_at_utc: 2026-03-07T12:34:56Z
```

### Skill Commands

The `/aai-decapod` skill provides these commands:

```bash
# Check installation and configuration status
/aai-decapod

# Run advisory check on a specific file
/aai-decapod check <file-path>

# Generate attestation from latest validation
/aai-decapod attest

# List all attestations
/aai-decapod attest list

# Show specific attestation details
/aai-decapod attest show <attestation-id>

# Generate compliance dashboard
/aai-decapod report

# Show current configuration
/aai-decapod config
```

## Troubleshooting

### Problem: `decapod: command not found`

**Solution:**
```bash
# Install via npm
npm install -g @decapod/cli

# Or via pip
pip install decapod-cli

# Verify
which decapod
decapod --version
```

### Problem: Config file not found

**Solution:**
```bash
# Initialize Decapod in project root
cd /path/to/project
decapod init

# Or create manually
mkdir -p .decapod
cat > .decapod/config.yaml << 'EOF'
version: 1
project:
  name: my-project
  compliance_frameworks: [SOC2, ISO27001]
advisory:
  enabled: true
attestation:
  enabled: true
integrations:
  aai:
    intake_hook: true
    validation_hook: true
EOF
```

### Problem: Advisory check fails

**Possible causes:**
- Input file doesn't exist
- Input file is not valid Markdown
- Decapod binary not in PATH

**Solution:**
```bash
# Verify file exists
ls -lah docs/ai/intake/PRD-001.md

# Test advisory manually
decapod advisory --input docs/ai/intake/PRD-001.md --output /tmp/test.json

# Check Decapod logs
decapod --debug advisory --input docs/ai/intake/PRD-001.md
```

### Problem: Attestation generation fails

**Possible causes:**
- Validation report not found
- Coverage file missing
- Permission issues

**Solution:**
```bash
# Verify validation artifacts exist
ls -lah docs/ai/reports/LATEST.md
ls -lah docs/ai/coverage/latest.json

# Test attestation manually
decapod attest \
  --validation-report docs/ai/reports/LATEST.md \
  --output /tmp/test-attest.json
```

### Problem: Hooks not firing

**Possible causes:**
- `.decapod/config.yaml` has `intake_hook: false`
- Decapod not installed
- AAI skill not updated to support hooks

**Solution:**
```bash
# Check config
cat .decapod/config.yaml | grep -A5 "integrations:"

# Ensure hooks are enabled
yq eval '.integrations.aai.intake_hook = true' -i .decapod/config.yaml
yq eval '.integrations.aai.validation_hook = true' -i .decapod/config.yaml

# Test manually
/aai-decapod config
```

## Security Considerations

### What Gets Stored

**Attestation artifacts contain:**
- ✓ Paths to validation reports and screenshots
- ✓ Test counts and coverage percentages
- ✓ Compliance framework mappings
- ✓ Timestamps and run IDs

**Attestation artifacts DO NOT contain:**
- ✗ Source code
- ✗ Credentials or secrets
- ✗ Full test logs (only summaries)
- ✗ User data or PII

### Key Management

If using signed attestations:

```bash
# Generate key pair (do this once)
openssl genrsa -out ~/.decapod/signing-key.pem 2048
chmod 600 ~/.decapod/signing-key.pem

# Extract public key
openssl rsa -in ~/.decapod/signing-key.pem -pubout -out ~/.decapod/signing-key.pub

# IMPORTANT: Never commit private key to git
echo ".decapod/signing-key.pem" >> .gitignore
```

### Retention and Cleanup

Configure retention in `.decapod/config.yaml`:

```yaml
attestation:
  retention_days: 365  # Keep attestations for 1 year
```

Cleanup old attestations:

```bash
# List attestations older than 365 days
decapod attest list --older-than 365d

# Delete old attestations
decapod attest cleanup --older-than 365d --confirm
```

## Summary

Decapod integration enhances AAI with:

1. **Advisory Checks**: Automated compliance scanning before planning
2. **Attestation Artifacts**: Cryptographically verifiable evidence of validation
3. **Framework Mapping**: SOC2, ISO27001, HIPAA, GDPR support
4. **Audit Trail**: Immutable history of compliance events
5. **Zero Workflow Disruption**: Runs automatically via hooks

**Next Steps:**

1. Install Decapod CLI: `npm install -g @decapod/cli`
2. Initialize in project: `decapod init`
3. Enable AAI hooks in `.decapod/config.yaml`
4. Run `/aai-decapod` to verify setup
5. Use `/aai-intake` and `/aai-validate-report` as normal

The integration is designed to be **invisible when everything is compliant** and **helpful when issues arise**.
