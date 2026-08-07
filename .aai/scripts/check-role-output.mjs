#!/usr/bin/env node
//
// check-role-output.mjs — deterministic EXPECT validation of a dispatched
// role's `subagent_result` result block (SPEC-0094-spec-role-output-contracts,
// adoption of Promptbook's EXPECT/EXAMPLE pattern).
//
// PURPOSE
//   A malformed or incomplete subagent return (a stall, a missing block, a
//   duration that doesn't add up) currently costs wall-clock and only a
//   human/LLM read catches it. This script converts that into an instant,
//   cheap, LLM-free rejection with a precise machine-readable reason, run by
//   the orchestrator's merge protocol (.aai/SUBAGENT_PROTOCOL.md "Merge
//   protocol" step 1) BEFORE any docs/ai/STATE.yaml merge.
//
// THE SIX EXPECT POSTCONDITIONS (authoritative source: this header + the
// frozen spec's "Implementation plan" section — the schema itself lives in
// .aai/SUBAGENT_CONTRACT.md "Result block" section, byte-mirrored into
// .aai/templates/BRIEF_TEMPLATE.md Return Record; SEAM-1)
//   1. E-NO-BLOCK        — a parseable `subagent_result` YAML block is
//      present. The LAST fenced ```yaml (or bare ```) block whose body
//      starts with `subagent_result:` is extracted; absence or an
//      unparseable body fails this postcondition.
//   2. E-MISSING-FIELD   — every required core field is present: scope,
//      role, status, started_utc, ended_utc, duration_seconds, evidence,
//      files_changed, blockers. Extra extension fields are IGNORED (only
//      the required core is validated) — one violation line per missing
//      field.
//   3. E-BAD-STATUS       — `status` is one of PASS / FAIL / BLOCKED.
//   4. E-NO-EVIDENCE      — `evidence` has at least one entry with an
//      INTEGER `exit_code`.
//   8. E-MALFORMED-LINE — a base-indent block line that is neither a key nor a comment (never silently skipped)
//   5. E-BAD-TIMESTAMP    — `started_utc` and `ended_utc` are each a
//      parseable ISO-8601 UTC timestamp with an explicit `Z` or `+00:00`
//      offset (mirrors the CONTRACT timing rule; a non-UTC offset such as
//      `+02:00` is rejected).
//   9. E-PLANNING-VERDICT — a `role: Planning` block records a VALIDATION
//      VERDICT field (`last_validation`, `validation`, `validation_status`,
//      `validation_verdict`, `verdict`). CHANGE-0113 D2 probe R05.
//      THE DISTINCTION, because it is easy to get wrong: `status: PASS` is
//      NOT a validation claim and is NEVER rejected here — per
//      .aai/SUBAGENT_CONTRACT.md `status` is the ROLE RUN's own outcome and
//      every role (Planning included, see tests/fixtures/role-outputs/
//      planning-valid.md) uses PASS to mean "my run completed". What Planning
//      may not do is record a verdict ON THE WORK: that is Validation's, on
//      evidence that does not exist while the spec is still being frozen. The
//      same fields in a Validation block are legitimate and untouched.
//   6. E-BAD-DURATION / E-FUTURE-STARTED — `duration_seconds` equals
//      `ended_utc - started_utc` within +/-1s tolerance (E-BAD-DURATION on
//      mismatch), AND `started_utc` is not more than 300 seconds ahead of
//      the `--now` reference (E-FUTURE-STARTED beyond that bound) — the
//      SAME 300s threshold documented in .aai/SUBAGENT_PROTOCOL.md
//      merge-protocol step 2 (SEAM-2, kept from silently diverging by a
//      grep in the test suite). Both timing checks are skipped when the
//      operand timestamp(s) failed postcondition 5 (nothing sane to
//      compute from an unparseable timestamp).
//
// THE TWO OPTIONAL PLANNING GATES (CHANGE-0113 D2 probes R04 / R09)
//   Two Planning rules lived as prose in .aai/PLANNING.prompt.md with NO
//   runtime inspection of what the run actually did: "no code implementation
//   in planning" (R04) and "do not create a git worktree during Planning"
//   (R09). They are now checkable here, behind OPT-IN flags:
//     --base-ref <ref>            E-PLANNING-WROTE-CODE — for a `role: Planning`
//        block, every path in `git diff --name-only <ref>` plus every untracked
//        non-ignored file must sit under docs/specs/**, docs/ai/** or be
//        docs/INDEX.md. Anything else is code the role should not have written.
//     --worktree-baseline <path>  E-PLANNING-WORKTREE — the EXACT check: a
//        `git worktree list --porcelain` capture taken BEFORE the run; any
//        worktree present now and absent then was created during it.
//     --worktree-guard            E-PLANNING-WORKTREE — the baseline-FREE
//        approximation for callers with no before-capture: fires when a
//        worktree's path or branch names the block's own `scope`.
//   HONEST WIRING SCOPE: the orchestrator's merge-protocol step 1 passes only
//   `--file` today, so a live ride is gated only when the operator adds these
//   flags. tests/skills/test-aai-planning-probes.sh is what proves the gates
//   catch each violation (scripted fake-Planning runs). Documented in
//   .aai/SUBAGENT_PROTOCOL.md rather than silently assumed.
//
// USAGE
//   node .aai/scripts/check-role-output.mjs [--file <path>] [--now <ISO>]
//        [--base-ref <ref>] [--worktree-baseline <path>] [--worktree-guard]
//   (reads the role's final message text from stdin when --file is omitted)
//   --now defaults to the current system UTC time; pass an explicit value
//   for deterministic testing of the future-timestamp rule.
//
// OUTPUT / EXIT CONTRACT
//   Clean block:      no stdout output, exit 0.
//   Violating block:  one line per failed postcondition on stdout, each
//                      `ROLE-OUTPUT-VIOLATION: <CODE> <detail>`, exit 1.
//   Usage error (bad --now, unreadable --file, unrecognized argv): a
//                      message on stderr, exit 1 (this script's exit
//                      contract is binary — 0 clean / 1 anything else).
//
// SCOPE NOTES
//   Deterministic, LLM-free, zero-dependency: Node stdlib only (`node:fs`),
//   no network access, no model call, no package manifest (Technology
//   contract: docs/TECHNOLOGY.md). Semantic/quality judgment of a role's
//   work stays with Validation/Code Review — this script validates SHAPE
//   only. The result-block schema itself is never altered here.
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const REQUIRED_FIELDS = [
  'scope',
  'role',
  'status',
  'started_utc',
  'ended_utc',
  'duration_seconds',
  'evidence',
  'files_changed',
  'blockers',
];
const VALID_STATUSES = new Set(['PASS', 'FAIL', 'BLOCKED']);
// Fields that record a VALIDATION VERDICT. Reserved to the Validation role
// (E-PLANNING-VERDICT, see the header). `status` is deliberately NOT here.
const VERDICT_FIELDS = new Set([
  'last_validation', 'validation', 'validation_status', 'validation_verdict', 'verdict',
]);
const VERDICT_FORBIDDEN_ROLES = new Set(['planning']);
// The ONLY surface a Planning run may write (R04). Briefs live under
// docs/ai/briefs/ and are gitignored, so they never reach this list anyway.
const PLANNING_WRITE_ALLOWLIST = ['docs/specs/', 'docs/ai/'];
const PLANNING_WRITE_ALLOWFILES = ['docs/INDEX.md'];
const PLANNING_ROLE = 'planning';
const ISO_UTC_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|\+00:00)$/;
const FUTURE_TOLERANCE_SECONDS = 300; // mirrors SUBAGENT_PROTOCOL.md merge-protocol step 2
const DURATION_TOLERANCE_SECONDS = 1; // mirrors SUBAGENT_CONTRACT.md timing rule

function usageError(msg) {
  process.stderr.write(`check-role-output: ${msg}\n`);
  process.stderr.write(
    'usage: node .aai/scripts/check-role-output.mjs [--file <path>] [--now <ISO 8601 UTC>]\n'
    + '       [--base-ref <ref>] [--worktree-baseline <path>] [--worktree-guard]\n'
    + '  --base-ref / --worktree-baseline / --worktree-guard are OPT-IN Planning\n'
    + '  gates (R04 no code written, R09 no worktree created); they are no-ops\n'
    + '  for every other role.\n'
  );
  process.exit(1);
}

function parseArgs(argv) {
  let filePath = null;
  let nowArg = null;
  let baseRef = null;
  let worktreeBaseline = null;
  let worktreeGuard = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--file') {
      filePath = argv[++i];
      if (filePath === undefined || filePath.startsWith('--')) usageError('--file requires a path value');
    } else if (argv[i] === '--now') {
      nowArg = argv[++i];
      if (nowArg === undefined || nowArg.startsWith('--')) usageError('--now requires an ISO timestamp value');
    } else if (argv[i] === '--base-ref') {
      baseRef = argv[++i];
      if (baseRef === undefined || baseRef.startsWith('--')) usageError('--base-ref requires a git ref value');
    } else if (argv[i] === '--worktree-baseline') {
      worktreeBaseline = argv[++i];
      if (worktreeBaseline === undefined || worktreeBaseline.startsWith('--')) usageError('--worktree-baseline requires a path value');
    } else if (argv[i] === '--worktree-guard') {
      worktreeGuard = true;
    } else {
      usageError(`unrecognized argument: ${argv[i]}`);
    }
  }
  return { filePath, nowArg, baseRef, worktreeBaseline, worktreeGuard };
}

// --- the two optional Planning gates (R04 / R09) -----------------------------

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

// Every path the working tree changed against `ref`, tracked or not.
// A NEW untracked file is a write too — the R04 violation that matters most
// (a whole new source or test file) would be invisible to `git diff` alone.
function changedPathsSince(ref) {
  const tracked = git(['diff', '--name-only', ref, '--']);
  const untracked = git(['ls-files', '--others', '--exclude-standard']);
  const all = `${tracked}\n${untracked}`.split('\n').map((l) => l.trim()).filter(Boolean);
  return [...new Set(all)].sort();
}

function isAllowedPlanningPath(p) {
  if (PLANNING_WRITE_ALLOWFILES.includes(p)) return true;
  return PLANNING_WRITE_ALLOWLIST.some((prefix) => p.startsWith(prefix));
}

// Worktree entries as { path, branch } from `git worktree list --porcelain`.
function parseWorktreePorcelain(text) {
  const out = [];
  let cur = null;
  for (const raw of String(text).replace(/\r\n/g, '\n').split('\n')) {
    const line = raw.trim();
    if (line.startsWith('worktree ')) {
      if (cur) out.push(cur);
      cur = { path: line.slice('worktree '.length), branch: '' };
    } else if (line.startsWith('branch ') && cur) {
      cur.branch = line.slice('branch '.length);
    }
  }
  if (cur) out.push(cur);
  return out;
}

// Planning gate violations. Pure-ish: reads git and the baseline file only.
function planningGateViolations(parsed, opts) {
  const violations = [];
  const role = String(parsed.fields.role ?? '').trim().toLowerCase();
  if (role !== PLANNING_ROLE) return violations;

  if (opts.baseRef) {
    let paths;
    try {
      paths = changedPathsSince(opts.baseRef);
    } catch (err) {
      usageError(`--base-ref "${opts.baseRef}": git could not diff it (${String(err.message).split('\n')[0]})`);
    }
    for (const p of paths) {
      if (isAllowedPlanningPath(p)) continue;
      violations.push([
        'E-PLANNING-WROTE-CODE',
        `Planning wrote outside its surface: ${p} (allowed: ${[...PLANNING_WRITE_ALLOWLIST, ...PLANNING_WRITE_ALLOWFILES].join(', ')})`,
      ]);
    }
  }

  if (opts.worktreeBaseline || opts.worktreeGuard) {
    let now;
    try {
      now = parseWorktreePorcelain(git(['worktree', 'list', '--porcelain']));
    } catch (err) {
      usageError(`worktree gate: git worktree list failed (${String(err.message).split('\n')[0]})`);
    }
    if (opts.worktreeBaseline) {
      let before;
      try {
        before = parseWorktreePorcelain(readFileSync(opts.worktreeBaseline, 'utf8'));
      } catch (err) {
        usageError(`--worktree-baseline "${opts.worktreeBaseline}": cannot read it (${err.message})`);
      }
      const known = new Set(before.map((w) => w.path));
      for (const w of now) {
        if (known.has(w.path)) continue;
        violations.push([
          'E-PLANNING-WORKTREE',
          `Planning created a git worktree: ${w.path}${w.branch ? ` (${w.branch})` : ''} — Planning RECOMMENDS isolation, Implementation Preparation creates it`,
        ]);
      }
    } else {
      // Baseline-free approximation: a worktree naming this scope. Weaker by
      // construction (it cannot see a differently-named tree, and it cannot
      // tell WHO created one that matches) — asserted as such in the probes.
      const scope = String(parsed.fields.scope ?? '').trim();
      if (scope) {
        for (const w of now) {
          if (!w.path.includes(scope) && !w.branch.includes(scope)) continue;
          violations.push([
            'E-PLANNING-WORKTREE',
            `a git worktree for this scope exists: ${w.path}${w.branch ? ` (${w.branch})` : ''} — Planning RECOMMENDS isolation, Implementation Preparation creates it`,
          ]);
        }
      }
    }
  }
  return violations;
}

function parseIsoUtc(str) {
  if (typeof str !== 'string' || !ISO_UTC_RE.test(str)) return null;
  const d = new Date(str);
  if (Number.isNaN(d.getTime())) return null;
  // Round-trip the calendar components: JS Date silently rolls over
  // nonexistent dates (2026-02-30 -> Mar 2), which must be a violation.
  const mDate = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/.exec(str);
  if (!mDate) return null;
  if (d.getUTCFullYear() !== Number(mDate[1]) || d.getUTCMonth() + 1 !== Number(mDate[2])
      || d.getUTCDate() !== Number(mDate[3]) || d.getUTCHours() !== Number(mDate[4])
      || d.getUTCMinutes() !== Number(mDate[5]) || d.getUTCSeconds() !== Number(mDate[6])) {
    return null;
  }
  return d;
}

function parseScalar(v) {
  const s = v.trim();
  if (
    (s.startsWith('"') && s.endsWith('"') && s.length >= 2) ||
    (s.startsWith("'") && s.endsWith("'") && s.length >= 2)
  ) {
    return s.slice(1, -1);
  }
  return s;
}

// Split fenced-block text into {indent, content} rows, dropping blank lines
// (the schema uses no multi-line block scalars, so blank-line drop is safe).
function toIndentedLines(rawLines) {
  const out = [];
  for (const raw of rawLines) {
    if (raw.trim() === '') continue;
    const m = /^( *)(.*)$/.exec(raw);
    out.push({ indent: m[1].length, content: m[2] });
  }
  return out;
}

// Extract the LAST fenced ```yaml/```yml/``` block whose body's first
// non-blank line is exactly `subagent_result:` at column 0 (edge case:
// roles may echo the template skeleton earlier in their message — only the
// LAST fence is validated).
function extractLastResultBlock(text) {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  let inFence = false;
  let fenceStart = -1;
  let candidate = null;
  for (let idx = 0; idx < lines.length; idx++) {
    const trimmed = lines[idx].trim();
    if (!inFence) {
      if (/^```(yaml|yml)?$/.test(trimmed)) {
        inFence = true;
        fenceStart = idx + 1;
      }
    } else if (trimmed === '```') {
      const body = lines.slice(fenceStart, idx);
      if (isSubagentResultBody(body)) candidate = body;
      inFence = false;
    }
  }
  return candidate;
}

function isSubagentResultBody(bodyLines) {
  for (const l of bodyLines) {
    if (l.trim() === '') continue;
    return l === 'subagent_result:';
  }
  return false;
}

// A sequence of scalar items ("- value") at nested's own indent level.
function parseScalarList(nested) {
  if (nested.length === 0) return [];
  const listIndent = nested[0].indent;
  const items = [];
  for (const line of nested) {
    if (line.indent !== listIndent) continue;
    if (line.content === '-') {
      items.push('');
    } else if (line.content.startsWith('- ')) {
      items.push(parseScalar(line.content.slice(2)));
    }
  }
  return items;
}

// A sequence of mapping items ("- key: value" plus sibling "key: value"
// continuation lines two spaces further in) at nested's own indent level.
function parseEvidenceList(nested) {
  if (nested.length === 0) return [];
  const listIndent = nested[0].indent;
  const items = [];
  let i = 0;
  while (i < nested.length) {
    const line = nested[i];
    if (line.indent !== listIndent || !line.content.startsWith('- ')) {
      i++;
      continue;
    }
    const obj = {};
    const rest = line.content.slice(2);
    const m = /^([A-Za-z0-9_.-]+):[ \t]*(.*)$/.exec(rest);
    if (m && m[2].trim() !== '') obj[m[1]] = parseScalar(m[2]);
    else if (m) obj[m[1]] = '';
    i++;
    const fieldIndent = listIndent + 2;
    while (i < nested.length && nested[i].indent === fieldIndent) {
      const fm = /^([A-Za-z0-9_.-]+):[ \t]*(.*)$/.exec(nested[i].content);
      if (fm) {
        obj[fm[1]] = parseScalar(fm[2]);
        if (fm[1] === 'exit_code') obj.exit_code_raw = fm[2].trim();
      }
      i++;
    }
    if (obj.exit_code !== undefined) {
      // Type-preserving: only an UNQUOTED integer literal counts — a quoted
      // "0" is a string in YAML and must fail the integer requirement
      // (PR #168 Codex P2).
      const rawInt = typeof obj.exit_code_raw === 'string' && /^-?\d+$/.test(obj.exit_code_raw);
      obj.exit_code = rawInt ? Number(obj.exit_code_raw) : obj.exit_code_raw;
      delete obj.exit_code_raw;
    }
    items.push(obj);
  }
  return items;
}

// Parse the extracted block into { present: Set<key>, fields, evidence,
// files_changed, blockers }. Returns null when the body is unparseable
// (no top-level `subagent_result:` header, or no children under it).
function parseSubagentResultBlock(candidateRawLines) {
  const blockLines = toIndentedLines(candidateRawLines);
  if (blockLines.length === 0) return null;
  const header = blockLines[0];
  if (header.indent !== 0 || header.content !== 'subagent_result:') return null;
  const body = blockLines.slice(1);
  if (body.length === 0) return null;
  const baseIndent = body[0].indent;
  if (baseIndent <= 0) return null;

  const present = new Set();
  const fields = {};
  const malformed = [];
  let evidence = [];
  let filesChanged = [];
  let blockers = [];

  let i = 0;
  while (i < body.length) {
    if (body[i].indent !== baseIndent) {
      i++;
      continue;
    }
    const m = /^([A-Za-z0-9_.-]+):[ \t]*(.*)$/.exec(body[i].content);
    if (!m) {
      // Track instead of silently skipping (PR #168 Codex P2): a base-indent
      // line that is neither a key nor a comment is a malformed block line.
      if (!body[i].content.startsWith('#')) malformed.push(body[i].content.slice(0, 60));
      i++;
      continue;
    }
    const key = m[1];
    const inlineVal = m[2].trim();
    i++;
    const nestedStart = i;
    while (i < body.length && body[i].indent > baseIndent) i++;
    const nested = body.slice(nestedStart, i);

    present.add(key);
    if (
      key === 'scope' ||
      key === 'role' ||
      key === 'status' ||
      key === 'started_utc' ||
      key === 'ended_utc' ||
      key === 'duration_seconds'
    ) {
      fields[key] = inlineVal !== '' ? parseScalar(inlineVal) : '';
    } else if (key === 'evidence') {
      evidence = inlineVal === '[]' ? [] : parseEvidenceList(nested);
    } else if (key === 'files_changed') {
      filesChanged = inlineVal === '[]' ? [] : parseScalarList(nested);
    } else if (key === 'blockers') {
      blockers = inlineVal === '[]' ? [] : parseScalarList(nested);
    }
    // else: extra extension field — nested lines already consumed above;
    // intentionally ignored (validate required core only).
  }
  return { present, fields, evidence, files_changed: filesChanged, blockers, malformed };
}

function validateResult(parsed, nowMs) {
  const violations = [];

  for (const bad of parsed.malformed ?? []) {
    violations.push(['E-MALFORMED-LINE', `unparseable block line: ${bad}`]);
  }

  for (const key of REQUIRED_FIELDS) {
    if (!parsed.present.has(key)) {
      violations.push(['E-MISSING-FIELD', `missing required field: ${key}`]);
    }
  }

  if (parsed.present.has('status')) {
    const status = parsed.fields.status;
    if (!VALID_STATUSES.has(status)) {
      violations.push([
        'E-BAD-STATUS',
        `status must be one of PASS|FAIL|BLOCKED, got: ${JSON.stringify(status)}`,
      ]);
    }
  }

  // E-PLANNING-VERDICT (R05) — role-scoped, field-based, value-independent:
  // Planning has no business recording ANY validation verdict, pass or fail.
  // Sorted so the violation lines stay byte-stable across runs (TEST-005).
  if (parsed.present.has('role')) {
    const role = String(parsed.fields.role ?? '').trim().toLowerCase();
    if (VERDICT_FORBIDDEN_ROLES.has(role)) {
      for (const key of [...parsed.present].sort()) {
        if (!VERDICT_FIELDS.has(key)) continue;
        violations.push([
          'E-PLANNING-VERDICT',
          `role "${parsed.fields.role}" may not record a validation verdict: field "${key}" is Validation's, on evidence Planning does not yet have (status: PASS remains the role-run outcome and is not this violation)`,
        ]);
      }
    }
  }

  if (parsed.present.has('evidence')) {
    const hasIntExitCode = parsed.evidence.some((e) => e && Number.isInteger(e.exit_code));
    if (!hasIntExitCode) {
      violations.push(['E-NO-EVIDENCE', 'no evidence entry with an integer exit_code']);
    }
  }

  let startedDate = null;
  let endedDate = null;
  for (const key of ['started_utc', 'ended_utc']) {
    if (!parsed.present.has(key)) continue;
    const raw = parsed.fields[key];
    const d = parseIsoUtc(raw);
    if (!d) {
      violations.push([
        'E-BAD-TIMESTAMP',
        `${key} is not a parseable ISO-8601 UTC timestamp (Z or +00:00 required): ${JSON.stringify(raw)}`,
      ]);
    } else if (key === 'started_utc') {
      startedDate = d;
    } else {
      endedDate = d;
    }
  }

  if (startedDate && endedDate && parsed.present.has('duration_seconds')) {
    const declared = Number(parsed.fields.duration_seconds);
    const actual = (endedDate.getTime() - startedDate.getTime()) / 1000;
    // Reversed timestamps (ended before started) are a violation even when
    // the declared negative duration "matches" — a negative wall-clock is
    // never a valid role run (PR review 20260727T100151Z NB-1).
    if (!Number.isFinite(declared) || actual < 0
        || Math.abs(declared - actual) > DURATION_TOLERANCE_SECONDS) {
      violations.push([
        'E-BAD-DURATION',
        `duration_seconds (${parsed.fields.duration_seconds}) does not match ended_utc-started_utc (${actual}s), tolerance +/-${DURATION_TOLERANCE_SECONDS}s`,
      ]);
    }
  }

  if (startedDate) {
    const aheadSeconds = (startedDate.getTime() - nowMs) / 1000;
    if (aheadSeconds > FUTURE_TOLERANCE_SECONDS) {
      violations.push([
        'E-FUTURE-STARTED',
        `started_utc is ${Math.round(aheadSeconds)}s ahead of --now, limit ${FUTURE_TOLERANCE_SECONDS}s`,
      ]);
    }
  }

  return violations;
}

function main() {
  const { filePath, nowArg, baseRef, worktreeBaseline, worktreeGuard } = parseArgs(process.argv.slice(2));

  let nowMs;
  if (nowArg) {
    const d = parseIsoUtc(nowArg);
    if (!d) usageError(`--now is not a parseable ISO-8601 UTC timestamp: ${nowArg}`);
    nowMs = d.getTime();
  } else {
    nowMs = Date.now();
  }

  let text;
  try {
    text = readFileSync(filePath ?? 0, 'utf8');
  } catch (err) {
    usageError(`cannot read input (${err.message})`);
  }

  const candidate = extractLastResultBlock(text);
  if (!candidate) {
    console.log('ROLE-OUTPUT-VIOLATION: E-NO-BLOCK no parseable subagent_result YAML fence found');
    process.exit(1);
  }

  const parsed = parseSubagentResultBlock(candidate);
  if (!parsed) {
    console.log('ROLE-OUTPUT-VIOLATION: E-NO-BLOCK subagent_result fence body is unparseable');
    process.exit(1);
  }

  const violations = validateResult(parsed, nowMs);
  violations.push(...planningGateViolations(parsed, { baseRef, worktreeBaseline, worktreeGuard }));
  if (violations.length === 0) process.exit(0);

  for (const [code, detail] of violations) {
    console.log(`ROLE-OUTPUT-VIOLATION: ${code} ${detail}`);
  }
  process.exit(1);
}

main();
