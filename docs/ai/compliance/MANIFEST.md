# Decapod Integration PoC - File Manifest

## Created Files

This manifest lists all files created for the Decapod integration proof-of-concept.

### 1. Core Integration Files

#### `.claude/skills/aai-decapod/SKILL.md`
- **Size:** 488 bytes
- **Purpose:** Skill definition for Claude Code
- **Status:** Pre-existing (verified)
- **Invocation:** `/aai-decapod`

#### `.aai/SKILL_DECAPOD.prompt.md`
- **Size:** 9.4 KB
- **Lines:** 396
- **Purpose:** Integration prompt with detailed instructions
- **Status:** Pre-existing (verified)
- **Features:**
  - Installation verification (`command -v decapod`)
  - Advisory check integration with `/aai-intake`
  - Attestation generation integration with `/aai-validate-report`
  - Configuration management
  - Query and reporting commands
  - Example outputs and troubleshooting

### 2. Documentation Files

#### `docs/ai/DECAPOD_INTEGRATION.md`
- **Size:** 18 KB
- **Lines:** 688
- **Purpose:** Complete integration guide
- **Status:** Created
- **Contents:**
  - Overview and architecture diagram
  - Setup instructions (npm and pip)
  - Advisory checks workflow
  - Attestation generation workflow
  - Benefits comparison table
  - 5 usage examples
  - Advanced configuration
  - Troubleshooting guide
  - Security considerations

#### `docs/ai/compliance/README.md`
- **Size:** 3.7 KB
- **Purpose:** Compliance directory overview
- **Status:** Created
- **Contents:**
  - Quick start guide
  - Integration points
  - File structure
  - JSON schema definitions
  - Retention policy
  - Security notes

#### `docs/ai/compliance/WORKFLOW.md`
- **Size:** 9.5 KB
- **Lines:** 282
- **Purpose:** Visual workflow documentation
- **Status:** Created
- **Contents:**
  - ASCII workflow diagrams (4 phases)
  - Complete lifecycle example
  - Decision trees (advisory & attestation)
  - File relationships diagram
  - Integration points table
  - Command reference

### 3. Configuration & Examples

#### `docs/ai/.decapod-config-example.yaml`
- **Size:** 1.3 KB
- **Lines:** 41
- **Purpose:** Example Decapod configuration
- **Status:** Created
- **Features:**
  - Project settings (name, frameworks)
  - Advisory configuration (enabled, threshold, categories)
  - Attestation settings (signing, retention, output)
  - AAI integration hooks (intake_hook, validation_hook)
  - Framework-specific controls (SOC2, ISO27001)

#### `docs/ai/compliance/example-advisory.json`
- **Size:** 2.2 KB
- **Purpose:** Sample advisory check output
- **Status:** Created
- **Contents:**
  - 3 findings (high, medium, low severity)
  - Security, privacy, compliance categories
  - SOC2, ISO27001, GDPR framework mappings
  - Detailed recommendations and locations
  - Summary statistics

#### `docs/ai/compliance/example-attestation.json`
- **Size:** 3.2 KB
- **Purpose:** Sample attestation artifact
- **Status:** Created
- **Contents:**
  - Attestation ID and verdict
  - Test results (12 passed, 0 failed)
  - Coverage metrics (87% line, 82% branch)
  - 5 screenshot references with SHA256 hashes
  - SOC2 & ISO27001 control mappings
  - Cryptographic signature (example)

#### `docs/ai/compliance/MANIFEST.md`
- **Size:** This file
- **Purpose:** File listing and metadata
- **Status:** Created

## Total Statistics

- **Files Created:** 6 new files
- **Files Verified:** 2 pre-existing files
- **Total Documentation:** 1000+ lines
- **Total Size:** ~47 KB

## Integration Architecture

```
.claude/skills/aai-decapod/SKILL.md
            ↓
    Loads and executes
            ↓
.aai/SKILL_DECAPOD.prompt.md
            ↓
    ┌───────┴───────┐
    ↓               ↓
Advisory Hook   Attestation Hook
    ↓               ↓
/aai-intake    /aai-validate-report
    ↓               ↓
advisory.json  attestation.json
    ↓               ↓
compliance/advisory/  compliance/attestations/
```

## Documentation Hierarchy

```
docs/ai/DECAPOD_INTEGRATION.md (Main guide)
    ↓
docs/ai/compliance/README.md (Directory overview)
    ↓
docs/ai/compliance/WORKFLOW.md (Visual workflows)
    ↓
docs/ai/compliance/example-*.json (Concrete examples)
```

## Quick Reference

### Installation
```bash
npm install -g @decapod/cli
cd /workspace/extra/ai-os
decapod init
cp docs/ai/.decapod-config-example.yaml .decapod/config.yaml
```

### Verification
```bash
/aai-decapod
```

### Usage
```bash
/aai-intake "feature description"    # Advisory check runs automatically
/aai-validate-report                 # Attestation generated automatically
/aai-decapod report                  # Generate compliance dashboard
```

### File Locations

| File Type | Location | Example |
|-----------|----------|---------|
| Advisory Results | `docs/ai/compliance/advisory/` | `advisory-PRD-001.json` |
| Attestations | `docs/ai/compliance/attestations/` | `attest-20260307-123456Z.json` |
| Dashboard | `docs/ai/compliance/` | `report.html` |
| Config | `.decapod/` | `config.yaml` |

## Compliance Frameworks

Supported frameworks with control mappings:

- **SOC2:** Service Organization Control 2
  - CC6.1 - Logical and Physical Access Controls
  - CC7.2 - System monitoring

- **ISO27001:** Information Security Management
  - A.9.4 - System and application access control
  - A.12.4.1 - Event logging
  - A.12.6.1 - Technical vulnerability management
  - A.14.2.8 - System security testing

- **GDPR:** EU General Data Protection Regulation
  - Article 5 - Principles relating to processing of personal data

- **HIPAA:** Healthcare data protection (configurable)

- **PCI-DSS:** Payment card security (configurable)

## Next Steps

1. **Read:** Start with `DECAPOD_INTEGRATION.md` for setup
2. **Configure:** Copy `.decapod-config-example.yaml` to `.decapod/config.yaml`
3. **Install:** Run `npm install -g @decapod/cli`
4. **Test:** Execute `/aai-decapod` to verify
5. **Use:** Run `/aai-intake` and `/aai-validate-report` normally

## Maintenance

- **Update frequency:** As needed when Decapod CLI updates
- **Retention:** Attestations kept for 365 days (configurable)
- **Cleanup:** Run `decapod attest cleanup --older-than 365d`

## Support

For questions about:
- **Decapod CLI:** See Decapod documentation
- **AAI Integration:** See `DECAPOD_INTEGRATION.md`
- **Workflow:** See `WORKFLOW.md`
- **Examples:** See `example-advisory.json` and `example-attestation.json`

---

**Version:** 1.0 (PoC)
**Created:** 2026-03-07
**Status:** Ready for testing
