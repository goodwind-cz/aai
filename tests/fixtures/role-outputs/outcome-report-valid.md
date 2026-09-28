# Validation report

```aai-outcome-v1
{
  "version": 1,
  "ref": "role-output-contracts",
  "validation_started_utc": "2026-01-02T00:00:00Z",
  "sources": [
    {"kind":"intake","path":"tests/fixtures/role-outputs/outcome-intake.md","sha256":"35d5131d1942d14f85b464164a37a4309f3d2e710aca0bfeeed93a1acc55512a"},
    {"kind":"spec","path":"tests/fixtures/role-outputs/outcome-spec.md","sha256":"f62463d4c0ac4cf3892262faecb5d44e04683a2ea6c13fb87647927f915e2c5b"}
  ],
  "requirements": [{
    "id":"REQ-001",
    "source":{"path":"tests/fixtures/role-outputs/outcome-intake.md","quote":"Validate the role-output contract."},
    "constraint":"Validate the role-output contract.",
    "spec_ac_ids":["Spec-AC-01"],
    "assessment":"aligned",
    "rationale":"The contract suite passed.",
    "required":true,
    "outcome_ids":["OUT-001"]
  }],
  "outcomes": [{
    "id":"OUT-001",
    "requirement_ids":["REQ-001"],
    "target":{"kind":"repository","expected_identity":"role-output-contracts","observed_identity":"role-output-contracts"},
    "verification":{"operation":"run role-output suite","evidence_path":"tests/fixtures/role-outputs/outcome-evidence.log","evidence_sha256":"984bc58aed2fd7c5669bae60fec4dcdbbab73b06545e25f216ae136c630ec667","observed_at_utc":"2026-01-02T00:02:00Z","result":"satisfied"},
    "persistence":{"applicable":false,"reason":"repository contract only"}
  }]
}
```
