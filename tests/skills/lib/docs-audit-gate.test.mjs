import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { gateDoc } from '../../../.aai/scripts/lib/docs-audit-core.mjs';

// TEST-2308 (Spec-AC-06). Five --gate-only Bash functions of
// tests/skills/test-aai-docs-audit.sh moved here (SPEC docs-audit-content-engine-split D4).
// Each case writes its fixture documents to a temp dir and calls the exported
// gateDoc: no git repository and no child process. Every clause the Bash
// function asserted is kept as an assertion on the structured reasons; the exit
// code and the rendered row names stay with the retained CLI owners
// (test_l1gate_lean_gate_pass, test_gateac_issue330_crosscheck).
// Migration map G1 to G5 is in docs/analysis/docs-audit-content-engine-split.md.

const JUST = 'Ceremony justification: S-sized single-surface fix (one script, one test).';

function root(t) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'docs-audit-gate-'));
  fs.mkdirSync(path.join(d, 'docs', 'specs'), { recursive: true });
  t.after(() => fs.rmSync(d, { recursive: true, force: true }));
  return d;
}

function put(d, name, text) {
  fs.writeFileSync(path.join(d, 'docs', 'specs', name), text);
}

function fm(id, status, level) {
  return ['---', `id: ${id}`, 'type: spec', `status: ${status}`, ...(level ? [`ceremony_level: ${level}`] : []),
    'links:', '  pr: []', '---', `# Fixture spec ${id}`, ''].join('\n');
}

const LEAN_HEAD = '| Spec-AC    | Requirement                 | Status |\n|------------|-----------------------------|--------|\n';
const CANON_HEAD = '| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |\n|------------|-------------|--------------|----------|-----------|-------|\n';

function lean(id, level, rows, just = true) {
  return `${fm(id, 'draft', level)}\n${just ? `${JUST}\n\n` : ''}## Acceptance Criteria\n\n${LEAN_HEAD}${rows}\n`;
}

function canon(id, rows, level) {
  return `${fm(id, 'draft', level)}\n## Acceptance Criteria Status\n\n${CANON_HEAD}${rows}\n`;
}

function reasons(d, id) {
  const r = gateDoc(d, id);
  assert.equal(r.found, true, `gateDoc must resolve ${id}`);
  return r;
}

function has(r, needle, lower = false) {
  const f = lower ? needle.toLowerCase() : needle;
  return r.reasons.some(x => (lower ? x.toLowerCase() : x).includes(f));
}

test('G1 missing justification: L1 lean spec without the line fails naming only that gap', t => {
  const d = root(t);
  put(d, 'SPEC-7111-nojust.md', lean('SPEC-7111', 1, '| Spec-AC-01 | does the small thing     | done   |', false));
  const r = reasons(d, 'SPEC-7111');
  assert.equal(r.ok, false, 'L1 without justification must fail the gate');
  assert.ok(has(r, 'Ceremony justification'), `reason must name the missing Ceremony justification line: ${r.reasons}`);
  assert.ok(!has(r, 'missing AC Status table'), `the lean table must satisfy the structural check: ${r.reasons}`);
});

test('G2 garbage ceremony_level fails closed: invalid reason and canonical table still required', t => {
  const d = root(t);
  put(d, 'SPEC-7131-banana.md', lean('SPEC-7131', 'banana', '| Spec-AC-01 | does the small thing     | done   |'));
  const r = reasons(d, 'SPEC-7131');
  assert.equal(r.ok, false, 'garbage ceremony_level must fail the gate');
  assert.ok(has(r, 'schema-invalid ceremony_level'), `gate must report the schema-invalid ceremony_level: ${r.reasons}`);
  assert.ok(has(r, 'missing AC Status table'), `garbage level must not unlock the lean shape: ${r.reasons}`);
});

test('G3 lean pipe-drop: plain, escaped, indented rows fail naming the row; suffixed id does not trip', t => {
  const d = root(t);
  const ok1 = '| Spec-AC-01 | plain requirement no pipes  | done   |';
  put(d, 'SPEC-7141-pipedrop.md', lean('SPEC-7141', 1, `${ok1}\n| Spec-AC-02 | value is a | inside the cell | done   |`));
  let r = reasons(d, 'SPEC-7141');
  assert.equal(r.ok, false, 'pipe-dropped declared row must fail, not pass on survivors');
  assert.ok(has(r, 'Spec-AC-02'), `reason must name Spec-AC-02: ${r.reasons}`);
  assert.ok(has(r, 'did not parse', true), `reason must say the row did not parse: ${r.reasons}`);
  // negative control: an escaped pipe does not rescue the author
  put(d, 'SPEC-7142-esc.md', lean('SPEC-7142', 1, `${ok1}\n| Spec-AC-02 | value is a \\| inside the cell | done   |`));
  r = reasons(d, 'SPEC-7142');
  assert.equal(r.ok, false, 'escaped-pipe row must still fail');
  assert.ok(has(r, 'Spec-AC-02'), `escaped variant must name Spec-AC-02: ${r.reasons}`);
  // indented broken row (same whitespace tolerance as the parser)
  put(d, 'SPEC-7143-indent.md', lean('SPEC-7143', 1, `${ok1}\n  | Spec-AC-02 | indented with a | pipe   | done   |`));
  r = reasons(d, 'SPEC-7143');
  assert.equal(r.ok, false, 'indented pipe-dropped row must fail');
  assert.ok(has(r, 'Spec-AC-02'), `indented variant must name Spec-AC-02: ${r.reasons}`);
  // a well-formed but suffixed id cell parses and must not read as a pipe-drop
  put(d, 'SPEC-7144-suffix.md', `${fm('SPEC-7144', 'draft', 1)}\n${JUST}\n\n## Acceptance Criteria\n\n| Spec-AC          | Requirement                | Status |\n|------------------|----------------------------|--------|\n| Spec-AC-01       | plain requirement no pipes | done   |\n| Spec-AC-02 (opt) | suffixed id, clean row     | done   |\n`);
  r = reasons(d, 'SPEC-7144');
  assert.ok(!has(r, 'did not parse', true), `suffixed-but-parseable id cell must not trip the pipe-drop message: ${r.reasons}`);
});

test('G4 canonical pipe-drop: plain, escaped, indented, L2 and L3 fail naming the row; clean table passes', t => {
  const d = root(t);
  const r1 = '| Spec-AC-01 | first       | done         | a1b2c3d  | TDD       | —     |';
  const bad = `${r1}\n| Spec-AC-02 | second      | implementing | —        | —         | value is a | inside the cell |`;
  put(d, 'SPEC-7201-pipedrop.md', canon('SPEC-7201', bad));
  let r = reasons(d, 'SPEC-7201');
  assert.equal(r.ok, false, 'pipe-dropped declared canonical row must fail, not pass on survivors');
  assert.ok(has(r, 'Spec-AC-02'), `reason must name Spec-AC-02: ${r.reasons}`);
  assert.ok(has(r, 'did not parse', true), `reason must say the row did not parse: ${r.reasons}`);
  put(d, 'SPEC-7202-esc.md', canon('SPEC-7202', bad.replace('a | inside', 'a \\| inside')));
  r = reasons(d, 'SPEC-7202');
  assert.equal(r.ok, false, 'escaped-pipe canonical row must still fail');
  assert.ok(has(r, 'Spec-AC-02'), `escaped variant must name Spec-AC-02: ${r.reasons}`);
  put(d, 'SPEC-7203-indent.md', canon('SPEC-7203', `${r1.replace('done         ', 'done')}\n  | Spec-AC-02 | second    | done   | b2c3d4e  | TDD       | indented with a | pipe |`));
  r = reasons(d, 'SPEC-7203');
  assert.equal(r.ok, false, 'indented pipe-dropped canonical row must fail');
  assert.ok(has(r, 'Spec-AC-02'), `indented variant must name Spec-AC-02: ${r.reasons}`);
  for (const cl of [2, 3]) {
    const id = `SPEC-72${cl}0`;
    put(d, `${id}-cl${cl}.md`, canon(id, bad, cl));
    r = reasons(d, id);
    assert.equal(r.ok, false, `ceremony_level ${cl} pipe-dropped row must also fail`);
    assert.ok(has(r, 'Spec-AC-02'), `ceremony_level ${cl} variant must name Spec-AC-02: ${r.reasons}`);
  }
  // negative control: a fully parseable terminal table passes
  put(d, 'SPEC-7209-clean.md', canon('SPEC-7209', `${r1.replace('done         ', 'done')}\n| Spec-AC-02 | second      | done   | b2c3d4e  | TDD       | value is safe, no pipes here |`));
  r = reasons(d, 'SPEC-7209');
  assert.equal(r.ok, true, `a fully-parseable canonical table must still pass: ${r.reasons}`);
});

test('G5 lean-eligible doc volunteering the full canonical table still reconciles a pipe-dropped row', t => {
  const d = root(t);
  put(d, 'SPEC-7211-leanvol.md', `${fm('SPEC-7211', 'draft', 1)}\n${JUST}\n\n## Acceptance Criteria Status\n\n${CANON_HEAD}| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |\n| Spec-AC-02 | second      | done   | b2c3d4e  | TDD       | value is a | inside the cell |\n`);
  const r = reasons(d, 'SPEC-7211');
  assert.equal(r.ok, false, 'a lean-eligible doc volunteering the full table with a dropped row must still fail');
  assert.ok(has(r, 'Spec-AC-02'), `reason must name Spec-AC-02: ${r.reasons}`);
  assert.ok(has(r, 'did not parse', true), `reason must say the row did not parse: ${r.reasons}`);
});
