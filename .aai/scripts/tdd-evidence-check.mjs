#!/usr/bin/env node
//
// tdd-evidence-check.mjs — TDD RED evidence classifier (SPEC-0044 / CHANGE-0033).
//
// PURPOSE
//   Machine-distinguish a genuine PRODUCT red (the test's own assertion/
//   expectation output was reached and failed for the spec'd reason) from an
//   INFRASTRUCTURE failure (the run died before any test assertion executed:
//   runner/module-loader exception, import/module-resolution error, syntax
//   error in the test file, missing fixture/file, command-not-found, timeout,
//   or a crash with no assertion output). Both shapes exit non-zero from the
//   underlying test command and both satisfy the letter of "RED observed" —
//   only this check tells them apart.
//
// GRAMMAR (D1)
//   The RED log MUST carry exactly one line matching:
//     ^RED_CLASS:[ \t]*(product_red|infra_fail)[ \t]*$
//   (CRLF-tolerant: a trailing \r is stripped before matching; the anchor is
//   per-line, so an indented or embedded-in-sentence decoy never matches.)
//   Zero matching lines, more than one matching line (even with identical
//   values — the exactly-one rule keeps the parser unambiguous), or a line
//   whose value is anything other than the two literal tokens above, are all
//   UNCLASSIFIED — never silently accepted as product_red (D2: no default
//   that silently passes).
//
// CLASSIFICATION RULE (D5, language-agnostic; author-asserted in v1)
//   Classify product_red ONLY when the log shows the test's OWN assertion/
//   expectation output was reached — the expected-vs-actual or failure
//   message the test itself emits (e.g. an AssertionError with expected/
//   actual values, a suite's own `FAIL: TEST-xxx <reason>` line). Classify
//   infra_fail when the run died BEFORE any test assertion executed: a
//   runner/module-loader exception (import/module-resolution error, syntax
//   error in the test file, missing fixture/file, command not found), a
//   timeout, or a crash with no assertion output. Judge by "was the test's
//   own assertion output reached", never by a specific runner's exception
//   format — this works uniformly across bash suites, vitest, pytest, cargo,
//   etc. Auto-derivation heuristics are OUT of scope for v1; a reviewer or
//   Validation spot-checks the raw log against this rule, the same spot-check
//   model already used for today's "failure is for the right reason" item.
//
// USAGE
//   node .aai/scripts/tdd-evidence-check.mjs --red <path-to-red-log>
//
// EXIT CONTRACT (D4)
//   0  product_red   — accepted as RED-proof
//   1  infra_fail    — REJECTED; fix the infrastructure and re-capture
//   2  unclassified/invalid (missing RED_CLASS line, more than one such
//      line, or an unrecognized value) — REJECTED per D2 (no silent default)
//   3  usage error (missing/unreadable --red path, wrong argv shape) — fail
//      fast with context (Constitution art. 4)
//
// SCOPE NOTES
//   One log file = one classification. A multi-section log (several test
//   stanzas concatenated) is classified as a WHOLE — if any section is infra
//   noise, the author fixes or splits the log before claiming RED for that
//   section. This script never scans a directory or globs docs/ai/tdd/ — it
//   only classifies the single path it is given (D8: forward-looking,
//   additive gate; no repo-wide sweep exists anywhere in this change). The
//   path may live anywhere (not restricted to docs/ai/tdd/) — placement
//   discipline stays with SKILL_TDD.
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import { readFileSync, existsSync, statSync } from 'node:fs';

const RED_CLASS_RE = /^RED_CLASS:[ \t]*(\S+)[ \t]*$/;
const VALID_VALUES = new Set(['product_red', 'infra_fail']);

function usageError(msg) {
  process.stderr.write(`tdd-evidence-check: ${msg}\n`);
  process.stderr.write(
    'usage: node .aai/scripts/tdd-evidence-check.mjs --red <path-to-red-log>\n'
  );
  process.exit(3);
}

function parseArgs(argv) {
  let redPath = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--red') {
      redPath = argv[i + 1];
      i++;
    } else {
      usageError(`unrecognized argument: ${argv[i]}`);
    }
  }
  if (!redPath) usageError('missing required --red <path>');
  return redPath;
}

function main() {
  const redPath = parseArgs(process.argv.slice(2));

  if (!existsSync(redPath)) {
    usageError(`red log not found: ${redPath}`);
  }

  let stat;
  try {
    stat = statSync(redPath);
  } catch (err) {
    usageError(`cannot stat red log: ${redPath} (${err.message})`);
  }
  if (!stat.isFile()) {
    usageError(`red log path is not a file: ${redPath}`);
  }

  let content;
  try {
    content = readFileSync(redPath, 'utf8');
  } catch (err) {
    usageError(`cannot read red log: ${redPath} (${err.message})`);
  }

  const lines = content.split('\n').map((line) => line.replace(/\r$/, ''));
  const matches = [];
  for (const line of lines) {
    const m = RED_CLASS_RE.exec(line);
    if (m) matches.push(m[1]);
  }

  if (matches.length !== 1) {
    console.log(
      `UNCLASSIFIED: ${redPath} (${matches.length} RED_CLASS line(s) found, exactly 1 required)`
    );
    process.exit(2);
  }

  const value = matches[0];
  if (!VALID_VALUES.has(value)) {
    console.log(`UNCLASSIFIED: ${redPath} (unrecognized RED_CLASS value "${value}")`);
    process.exit(2);
  }

  if (value === 'infra_fail') {
    console.log(`REJECTED (infra_fail): ${redPath}`);
    process.exit(1);
  }

  console.log(`ACCEPTED (product_red): ${redPath}`);
  process.exit(0);
}

main();
