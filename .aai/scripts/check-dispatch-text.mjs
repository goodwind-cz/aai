#!/usr/bin/env node
// check-dispatch-text.mjs — a dispatch carries evidence and reproductions,
// never a priority order, a ranked list of expected findings, or a
// conclusion to weigh first (dispatch-state-sweep D11 / Spec-AC-11,
// fu-dispatch-prompt-coaching-bias). SUBAGENT_PROTOCOL.md states the rule
// this reads; this is the mechanical check for it, so it can be wired into
// an orchestration tick without trusting the author's own read of their text.
//
// WHY THIS EXISTS. A dispatch that pre-rates its own findings ("1. the auth
// bug (P1) ... 2. the timeout (P2)") hands a reviewer a conclusion to
// confirm, not a scope to review — the exact coaching-bias shape
// .aai/SKILL_CODE_REVIEW.prompt.md's ANTI-GAMING CONTRACT already forbids
// the ORCHESTRATOR from doing narratively. This makes that prose rule a
// readable text file rather than trusting the dispatching agent's own
// self-assessment.
//
// CLOSED DETECTOR SET, derived from the recorded incident, not invented:
//   1. an ordered list (`1.`/`2.` or `- P1`/`- P2`) inside a section whose
//      heading matches /findings|issues|problems|defects|things to look/i.
//   2. a literal pre-rating phrase: "in priority order", "most likely",
//      "the top <digit>", "ranked", "answer key", "start with the".
//   3. a severity token (P1/P2/P3/BLOCKING) on a line that ALSO predicts
//      rather than reports (/expect|likely|probably|should find/i) — a
//      severity token reporting a REAL finding never matches this, because
//      a report does not also carry a predictive verb on the same line.
//
// Every detector has a negative control: a reproduction command, a measured
// number, and a bare file path list must never trip any of the three.
//
// CLI
//   node check-dispatch-text.mjs [--path <file>] [--strict]
//   (reads stdin when --path is omitted)
//
// Exit codes:
//   0  clean, or a detection found WITHOUT --strict (advisory: NOTES only,
//      so this can be wired into a tick without turning a false positive
//      into a stopped factory)
//   6  --strict AND at least one detection — the line(s) are named
//   2  usage error

import fs from 'node:fs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

function usage(msg) {
  process.stderr.write(`check-dispatch-text: ${msg}\n`);
  exit(2);
}

function parseArgs(argv) {
  const opts = { path: undefined, strict: false };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--path') {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) usage('--path requires a value');
      opts.path = v;
      i += 1;
    } else if (tok === '--strict') {
      opts.strict = true;
    } else if (tok === '-h' || tok === '--help') {
      process.stdout.write('usage: node check-dispatch-text.mjs [--path <file>] [--strict]  (reads stdin when --path is omitted)\n');
      exit(0);
    } else {
      usage(`unknown argument "${tok}"`);
    }
  }
  return opts;
}

// A "section heading" — a markdown ATX heading, or a bare label line ending
// in a colon with nothing after it ("Findings:") — the shape a dispatch
// prompt actually uses, markdown or not.
const HEADING_RE = /^(?:#{1,6}\s+.+|[A-Za-z][\w /-]*:)\s*$/;
const FINDINGS_SECTION_RE = /findings|issues|problems|defects|things to look/i;
const ORDERED_ITEM_RE = /^\s*(?:\d+\.\s|-\s*P[1-3]\b)/;
const PRE_RATING_PHRASE_RE = /(in priority order|most likely|the top \d|ranked|answer key|start with the)/i;
const SEVERITY_TOKEN_RE = /\b(?:P1|P2|P3|BLOCKING)\b/;
const PREDICTIVE_VERB_RE = /expect|likely|probably|should find/i;

// Returns an array of { line (1-based), detector, text } — never throws.
function detect(content) {
  const lines = content.split(/\r?\n/);
  const findings = [];
  let sectionHeading = null;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (HEADING_RE.test(line)) { sectionHeading = line; continue; }
    if (sectionHeading && FINDINGS_SECTION_RE.test(sectionHeading) && ORDERED_ITEM_RE.test(line)) {
      findings.push({ line: i + 1, detector: 'ordered-list-in-findings-section', text: line });
    }
    if (PRE_RATING_PHRASE_RE.test(line)) {
      findings.push({ line: i + 1, detector: 'pre-rating-phrase', text: line });
    }
    if (SEVERITY_TOKEN_RE.test(line) && PREDICTIVE_VERB_RE.test(line)) {
      findings.push({ line: i + 1, detector: 'predicted-severity', text: line });
    }
  }
  return findings;
}

function main(argv) {
  const opts = parseArgs(argv);
  let content;
  if (opts.path !== undefined) {
    try { content = fs.readFileSync(opts.path, 'utf8'); }
    catch (e) { usage(`cannot read --path ${opts.path} (${(e && e.code) || 'unknown'})`); }
  } else {
    try { content = fs.readFileSync(0, 'utf8'); }
    catch (e) { usage(`cannot read stdin (${(e && e.code) || 'unknown'})`); }
  }

  const findings = detect(content);
  for (const f of findings) {
    process.stdout.write(`NOTE line ${f.line} [${f.detector}]: ${f.text.trim()}\n`);
  }
  if (findings.length === 0) {
    process.stdout.write('check-dispatch-text: clean — no pre-rating shape found\n');
    exit(0);
  }
  if (opts.strict) {
    process.stderr.write(`check-dispatch-text: ${findings.length} pre-rating shape(s) found — a dispatch names evidence `
      + 'and reproductions, never a ranked answer key (SUBAGENT_PROTOCOL.md)\n');
    exit(6);
  }
  exit(0);
}

runMain(() => main(process.argv.slice(2)));
