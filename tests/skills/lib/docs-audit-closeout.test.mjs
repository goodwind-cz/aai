import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runAudit, hasUnfinishedRolloutPhases } from '../../../.aai/scripts/lib/docs-audit-core.mjs';

// TEST-2208 (Spec-AC-05). The strings below are the complete documents that
// setup_closeout_fixture wrote in the Bash suite at 34f0cbca, byte for byte.
// No git repository and no child process: runAudit reads the files directly.
// Migration map C1 to C9 is reconciled in docs/analysis/docs-audit-suite-speed.md.
const FIXTURES = [
  ['RFC-0010-shipped-parent.md', `---
id: RFC-0010
type: rfc
status: proposed
links:
  spec: SPEC-0010
---
# Shipped parent RFC — all linked specs done
`],
  ['SPEC-0010-done-child.md', `---
id: SPEC-0010
type: spec
status: done
links:
  rfc: RFC-0010
---
# Done child spec

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
  ['RFC-0020-mixed-parent.md', `---
id: RFC-0020
type: rfc
status: implementing
links:
  spec: [SPEC-0021, SPEC-0022]
---
# Mixed parent — one spec still open
`],
  ['SPEC-0021-done.md', `---
id: SPEC-0021
type: spec
status: done
links:
  rfc: RFC-0020
---
# Done sibling

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
  ['SPEC-0022-open.md', `---
id: SPEC-0022
type: spec
status: implementing
links:
  rfc: RFC-0020
---
# Still-open sibling
`],
  ['RFC-0030-done-parent.md', `---
id: RFC-0030
type: rfc
status: done
links:
  spec: SPEC-0031
---
# Already-terminal parent
`],
  ['SPEC-0031-done.md', `---
id: SPEC-0031
type: spec
status: done
links:
  rfc: RFC-0030
---
# Done spec under a done parent

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
  ['RFC-0032-superseded-parent.md', `---
id: RFC-0032
type: rfc
status: superseded
links:
  spec: SPEC-0033
---
# Superseded parent
`],
  ['SPEC-0033-done.md', `---
id: SPEC-0033
type: spec
status: done
links:
  rfc: RFC-0032
---
# Done spec under a superseded parent

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
  ['RFC-0034-draft-parent.md', `---
id: RFC-0034
type: rfc
status: draft
links:
  spec: SPEC-0035
---
# Draft parent — not yet ready
`],
  ['SPEC-0035-done.md', `---
id: SPEC-0035
type: spec
status: done
links:
  rfc: RFC-0034
---
# Done spec under a draft parent

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
  ['RFC-0050-no-link.md', `---
id: RFC-0050
type: rfc
status: proposed
links:
  pr: []
---
# Parent with no linked specs at all
`],
  ['CHANGE-0050-change-parent.md', `---
id: CHANGE-0050
type: change
status: proposed
links:
  spec: SPEC-0051
---
# change-type doc linking an all-done spec — out of parent scope
`],
  ['SPEC-0051-done.md', `---
id: SPEC-0051
type: spec
status: done
links:
  pr: []
---
# Done spec linked only by a change-type doc

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
  ['RFC-0052-unresolvable.md', `---
id: RFC-0052
type: rfc
status: proposed
links:
  spec: SPEC-9999
---
# Parent linking a spec id absent from the scan — cannot prove all-done
`],
  ['RFC-0060-reverse-only.md', `---
id: RFC-0060
type: rfc
status: proposed
links:
  pr: []
---
# Parent with no forward links.spec; only the child links back
`],
  ['SPEC-0060-done-reverse.md', `---
id: SPEC-0060
type: spec
status: done
links:
  rfc: RFC-0060
---
# Done child that names its parent via links.rfc

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
  ['RFC-0070-forward-nonspec.md', `---
id: RFC-0070
type: rfc
status: proposed
links:
  spec: CHANGE-0070
---
# Parent whose links.spec mistakenly names a non-spec (done) doc
`],
  ['CHANGE-0070-done-nonspec.md', `---
id: CHANGE-0070
type: change
status: done
links:
  pr: []
---
# A done CHANGE doc — not a spec; must not satisfy all-specs-done
`],
  ['RFC-0080-slug-umbrella.md', `---
id: slug-umbrella
type: rfc
status: implementing
links:
  spec: null
---
# Umbrella with a slug id, child links by display id
`],
  ['SPEC-0088-slug-child.md', `---
id: slug-child
type: spec
status: done
links:
  rfc: RFC-0080
---
# Done child linking the parent by DISPLAY id

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
  ['RFC-0090-roadmap-umbrella.md', `---
id: roadmap-umbrella
type: rfc
status: implementing
links:
  spec: null
---
# Umbrella whose specs are done but whose roadmap has pending phases

## Rollout Status

| Phase | Description | Status | Delivered by |
|-------|-------------|--------|--------------|
| 0 | first phase | done | SPEC-0090 |
| 1 | later phase | not started | — |
`],
  ['SPEC-0090-roadmap-child.md', `---
id: roadmap-child
type: spec
status: done
links:
  rfc: RFC-0090
---
# The only done child of the roadmap umbrella

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
`],
];

let root;
let candidates;

before(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-closeout-node-'));
  for (const [name, body] of FIXTURES) {
    const file = path.join(root, 'docs', 'closeout', name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, body);
  }
  const result = runAudit(root, { quick: true, scopePath: 'docs/closeout' });
  candidates = result.closeoutCandidates;
});

after(() => {
  if (root) fs.rmSync(root, { recursive: true, force: true });
});

const byId = (id) => candidates.find((c) => c.id === id);
const flagged = (id) => byId(id) !== undefined;

test('TEST-2208 control: the run produced candidates from all 23 written documents', () => {
  assert.equal(FIXTURES.length, 23);
  assert.ok(Array.isArray(candidates) && candidates.length > 0, 'closeoutCandidates must be a non-empty list');
});

test('TEST-2208 C1: RFC-0010 is flagged with satisfying spec SPEC-0010', () => {
  const c = byId('RFC-0010');
  assert.ok(c, 'RFC-0010 must be a closeout candidate');
  assert.ok(c.specs.includes('SPEC-0010'), 'RFC-0010 must name SPEC-0010');
  assert.ok(c.suggestedStep.startsWith('advance RFC-0010 to'), c.suggestedStep);
});

test('TEST-2208 C2: a parent with a non-done linked spec is withheld (RFC-0020)', () => {
  assert.ok(flagged('RFC-0010'), 'positive control');
  assert.equal(flagged('RFC-0020'), false);
});

test('TEST-2208 C3: done, superseded and draft parents are never flagged', () => {
  assert.ok(flagged('RFC-0010'), 'positive control');
  for (const id of ['RFC-0030', 'RFC-0032', 'RFC-0034']) assert.equal(flagged(id), false, id);
});

test('TEST-2208 C4: no-link, change-type and unresolvable parents are not flagged', () => {
  assert.ok(flagged('RFC-0010'), 'positive control');
  for (const id of ['RFC-0050', 'CHANGE-0050', 'RFC-0052']) assert.equal(flagged(id), false, id);
});

test('TEST-2208 C5: a parent reachable only through the spec reverse link is flagged with SPEC-0060', () => {
  assert.ok(flagged('RFC-0010'), 'positive control');
  const c = byId('RFC-0060');
  assert.ok(c, 'RFC-0060 must be a closeout candidate');
  assert.ok(c.specs.includes('SPEC-0060'), 'RFC-0060 must name SPEC-0060');
});

test('TEST-2208 C6: a forward link to a non-spec done doc does not satisfy all-specs-done', () => {
  assert.ok(flagged('RFC-0010'), 'positive control');
  assert.equal(flagged('RFC-0070'), false);
});

test('TEST-2208 C7: a slug-id parent whose done spec links by display id is flagged', () => {
  assert.ok(flagged('RFC-0080'), 'RFC-0080 must be a closeout candidate');
});

test('TEST-2208 C8: an umbrella with a not-started Rollout phase is withheld', () => {
  assert.ok(flagged('RFC-0080'), 'positive control');
  assert.equal(flagged('RFC-0090'), false);
});

test('TEST-2208 C9: hasUnfinishedRolloutPhases parses Rollout tables with and without outer pipes', () => {
  const outer = '## Rollout Status\n\n| Phase | Status | By |\n|---|---|---|\n| 0 | done | x |\n| 1 | not started | — |\n';
  const noOuter = '## Rollout Status\n\nPhase | Status | By\n--- | --- | ---\n0 | done | x\n1 | not started | —\n';
  const allDone = '## Rollout Status\n\nPhase | Status | By\n--- | --- | ---\n0 | done | x\n1 | done | y\n';
  const none = '## Other\n\n| a | b |\n|---|---|\n| 1 | 2 |\n';
  assert.deepEqual(
    [outer, noOuter, allDone, none].map((t) => hasUnfinishedRolloutPhases(t)),
    [true, true, false, false],
  );
});
