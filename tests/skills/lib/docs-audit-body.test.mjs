import test from 'node:test';
import assert from 'node:assert/strict';
import { lintBody } from '../../../.aai/scripts/lib/docs-audit-core.mjs';

// The strings below are the complete original SPEC-7702..7710 and
// SPEC-7920..7921 fixtures from the Bash suite at a15065159a26.
const doc = (lines, finalNewline = true) => lines.join('\n') + (finalNewline ? '\n' : '');
const metadata = (id) => ['---', `id: ${id}`, 'type: spec', 'status: draft', 'links:', '  pr: []', '---'];
const fixtures = {
  fence: doc([...metadata('SPEC-7702'), '# Spec with an unclosed fence', '', 'Prose.', '```js', 'const x = 1;']),
  placeholder: doc([...metadata('SPEC-7703'), '# Spec with template residue', '', 'Unfilled id SPEC-XXXX left in the body.', 'An all-caps token <PLACEHOLDER> and <TODO_FILL> too.', 'But <why isolation is or is not useful> is legitimate prose.']),
  clean: doc([...metadata('SPEC-7704'), '# Entirely clean spec', '', 'Ordinary prose only.']),
  examples: doc([...metadata('SPEC-7705'), '# Spec whose EXAMPLES carry the tokens (fences-in-examples control)', '', '```text', '</content>', '<PLACEHOLDER>', 'SPEC-XXXX', '```', '', 'Inline `</content>` and `SPEC-XXXX` and `<PLACEHOLDER>` in code spans.']),
  emptyBody: doc(metadata('SPEC-7706')),
  fmOnly: doc(metadata('SPEC-7707'), false),
  nested: doc([...metadata('SPEC-7708'), '# Four-backtick fence wrapping a three-backtick example', '', '````markdown', '```js', '</content>', '```', '````']),
  tilde: doc([...metadata('SPEC-7709'), '# Tilde fence', '', '~~~', '</content>', '~~~']),
  tildeOpen: doc([...metadata('SPEC-7710'), '# Unclosed tilde fence', '', '~~~', 'still open at EOF']),
  multilineSpan: doc([...metadata('SPEC-7920'), '# Multi-line inline code span', '', 'Prose with `code that', '</content>', 'keeps going` and ends clean.']),
  sameLineSpan: doc([...metadata('SPEC-7921'), '# Line-initial two-run code span', '', '``` x ```', 'prose after the span', '</content>']),
};

const expected = (...pairs) => pairs.map(([rule, line]) => ({ rule, line }));
const result = (content) => lintBody(content).map(({ rule, line }) => ({ rule, line }));
for (const [ending, convert] of [['LF', (s) => s], ['CRLF', (s) => s.replace(/\n/g, '\r\n')]]) {
  test(`unbalanced_fence ${ending}: unclosed backtick fence opens at line 11`, () => {
    const input = convert(fixtures.fence);
    assert.deepEqual(result(input), expected(['unbalanced-fence', 11]));
    assert.match(lintBody(input)[0].detail, /fence opened here/);
  });

  test(`placeholder ${ending}: id and first all-caps angle token, mixed-case prose spared`, () => {
    const findings = lintBody(convert(fixtures.placeholder));
    assert.deepEqual(findings.map(({ rule, line }) => ({ rule, line })), expected(['template-placeholder', 10], ['template-placeholder', 11]));
    assert.match(findings[0].detail, /SPEC-XXXX/);
    assert.match(findings[1].detail, /<PLACEHOLDER>/);
    assert.equal(findings.some(({ line, detail }) => line === 12 || detail.includes('why isolation')), false);
  });

  test(`negative_controls ${ending}: prose, fenced tokens and inline spans yield zero`, () => {
    const clean = lintBody(convert(fixtures.clean));
    const examples = lintBody(convert(fixtures.examples));
    assert.deepEqual(clean, []);
    assert.deepEqual(examples, []);
    assert.equal(clean.length + examples.length, 0);
  });

  test(`degenerate_fixtures ${ending}: four clean inputs and one open tilde fence`, () => {
    for (const name of ['emptyBody', 'fmOnly', 'nested', 'tilde']) {
      assert.deepEqual(lintBody(convert(fixtures[name])), [], `${name} must yield zero findings`);
    }
    const open = lintBody(convert(fixtures.tildeOpen));
    assert.deepEqual(open.map(({ rule, line }) => ({ rule, line })), expected(['unbalanced-fence', 10]));
    assert.equal(open.length, 1);
  });

  test(`span_edges ${ending}: multiline span masked and live markup after same-line span found`, () => {
    const masked = lintBody(convert(fixtures.multilineSpan));
    const live = lintBody(convert(fixtures.sameLineSpan));
    assert.deepEqual(masked, []);
    assert.deepEqual(live.map(({ rule, line }) => ({ rule, line })), expected(['stray-tool-markup', 12]));
    assert.equal(masked.length + live.length, 1);
    assert.match(live[0].detail, /<\/content>/);
  });
}
