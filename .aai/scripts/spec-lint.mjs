#!/usr/bin/env node
// spec-lint — deterministic structural validation of spec documents
// (CHANGE spec-lint / SPEC spec-spec-lint, OpenSpec pattern per RES-0001 P3).
//
// BOUNDARY (SPEC spec-spec-lint D1): this tool owns INTRA-SPEC STRUCTURE —
// AC ids unique/sequential, AC status tokens, done-needs-evidence, Test Plan
// row -> Spec-AC mapping (BOTH directions, see `ac-without-test` below),
// SPEC-FROZEN vs strategy/AC-table/frontmatter-status consistency,
// ceremony_level enum, and AC rows the shared parser silently drops.
//
// AC -> TEST REVERSE COVERAGE (`ac-without-test`, CHANGE-0113 D2 probe R21):
// a Spec-AC that no Test Plan row claims. Scoped to in-flight specs
// (draft/proposed/accepted/implementing) because a terminal spec's Test Plan
// is history, not an actionable finding. spec-freeze.mjs reads this same rule
// as a hard freeze PRECONDITION — the lint reports, the freeze refuses.
// WHAT IT DOES NOT CHECK: whether the named test COMMAND actually runs, and
// whether the AC is measurable at all. Both stay Planning's judgment.
// docs-audit owns LIFECYCLE/DRIFT (orphans, frontmatter schema, staleness,
// false-done, close gate, telemetry, body lint). Shared token rules come from
// lib/docs-model.mjs so the engines cannot diverge on what a valid cell IS.
//
// Usage:
//   node .aai/scripts/spec-lint.mjs              # all docs/specs/**/*.md with type: spec
//   node .aai/scripts/spec-lint.mjs --path <p>   # exactly one file, any type
//   node .aai/scripts/spec-lint.mjs --json       # machine-readable result
//   node .aai/scripts/spec-lint.mjs --slug-handles  # CHANGE-0035 D6, see below
//   node .aai/scripts/spec-lint.mjs --strategy <v>  # CHANGE-0122, see below
//
// Exit codes: 0 clean / 1 findings / 2 usage error or unreadable --path.
// REPORT-ONLY: never writes any file, never emits events, never a hard gate
// in v1 — wired as an advisory line in PLANNING (post-freeze) and VALIDATION
// (step 1). No whitelist mechanism in v1: real corpus findings get FIXED.
//
// --slug-handles (CHANGE-0035 / SPEC-0047 D6): a SEPARATE, OPT-IN scan mode
// (slug-only handle discipline) — additive to the intra-spec-structure lint
// above, not a variant of it. Scope: FILENAMES under session-artifact dirs
// (docs/ai/reviews/, docs/ai/reports/, docs/ai/briefs/, tests/) embedding a
// governed `TYPE-NNN(N)` token with no corresponding numbered governed doc
// anywhere in the local tree -> WARN (the number was baked into an artifact
// before it was confirmed reserved). Same report-only exit contract (0 clean
// / 1 findings); never blocks.
//
// STRATEGY-SCALED EVIDENCE (CHANGE-0122): the evidence a spec may demand is a
// function of its RECORDED implementation strategy (CHANGE-0100). A spec whose
// strategy is `direct`/`untested` but whose evidence-bearing sections demand a
// STORED RED artifact / TDD-cycle evidence is a `strategy-evidence-mismatch`
// finding — the mismatch is cheap to fix at freeze and expensive at review
// (the motivating ride paid two extra agent runs for evidence its own strategy
// never promised). `tdd`/`hybrid` are byte-unchanged by this rule.
//   Strategy source, in precedence order (spec-lint reads NO state file — it is
//   pure over the document):
//     1. `--strategy <loop|tdd|hybrid|direct|untested|undecided>` (with
//        `--path`) — the caller (orchestration/dispatch, VALIDATION) passing
//        STATE's recorded `implementation_strategy.selected`, which this tool
//        cannot read;
//     2. frontmatter `strategy:`, when a project records it there;
//     3. the `- Strategy: <v>` body line SPEC_TEMPLATE writes under
//        `## Implementation strategy` (already the source of truth for the
//        frozen-without-strategy check).
//   Anything else — absent, `undecided`, unrecognized — FAILS OPEN: the rule
//   emits nothing rather than guessing.

import fs from 'node:fs';
import path from 'node:path';
import {
  normalizeNewlines, parseFrontmatter, parseAcTable, normalizeAcStatus,
  specFrozenInBody, walk, toPosix, parseLeanAcTable, parseDeltasSection,
  parseTestPlanTable, splitTableCells,
} from './lib/docs-model.mjs';

const ROOT = process.cwd();
const CEREMONY_ENUM = ['0', '1', '2', '3'];
const AC_ID_RE = /^Spec-AC-(\d{2})$/;
const AC_RANGE_RE = /^Spec-AC-(\d{2})\.\.(\d{2})$/;
const STRATEGY_ENUM = ['loop', 'tdd', 'hybrid', 'direct', 'untested', 'undecided'];
// Statuses at which `ac-without-test` (below) applies — the same set
// spec-freeze.mjs accepts as freezable, plus nothing else. See the rule.
const IN_FLIGHT_STATUSES = ['draft', 'proposed', 'accepted', 'implementing'];

function usage() {
  console.error(
    'Usage: spec-lint [--path <file>] [--json] [--slug-handles] [--strategy <v>]\n' +
    '  Lints spec documents for intra-spec structure (report-only).\n' +
    '  Default scope: docs/specs/**/*.md with frontmatter type: spec.\n' +
    '  --slug-handles: separate opt-in scan (CHANGE-0035 D6) over session-\n' +
    '  artifact filenames for unconfirmed TYPE-NNN(N) handles.\n' +
    `  --strategy: STATE's recorded implementation strategy (${STRATEGY_ENUM.join(' | ')})\n` +
    '  for the strategy-scaled evidence rule; requires --path, and omitting it\n' +
    '  reads the strategy from the spec itself.\n' +
    '  Exit: 0 clean | 1 findings | 2 usage error / unreadable --path.',
  );
}

function fail(msg) {
  console.error(`spec-lint: ${msg}`);
  usage();
  process.exit(2);
}

function parseArgs(argv) {
  const args = { path: null, json: false, slugHandles: false, strategy: null };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--json') args.json = true;
    else if (tok === '--slug-handles') args.slugHandles = true;
    else if (tok === '--path') {
      args.path = argv[++i];
      if (args.path === undefined || args.path.startsWith('--')) fail('--path needs a value');
    } else if (tok === '--strategy') {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) fail('--strategy needs a value');
      args.strategy = v.toLowerCase();
      if (!STRATEGY_ENUM.includes(args.strategy)) {
        fail(`--strategy "${v}" is not one of ${STRATEGY_ENUM.join(' | ')}`);
      }
    } else fail(`unknown flag: ${tok}`);
  }
  // --strategy names ONE ride's strategy; stamping it over a whole-corpus scan
  // would mislabel every other spec, so it is only accepted with --path.
  if (args.strategy && !args.path) fail('--strategy requires --path (it names one spec\'s recorded strategy)');
  return args;
}

// --- --slug-handles (CHANGE-0035 D6) -----------------------------------------

const SLUG_HANDLE_GOVERNED_DIRS = ['rfc', 'specs', 'issues', 'requirements', 'releases'];
const SLUG_HANDLE_PREFIXES = ['RFC', 'SPEC', 'ISSUE', 'CHANGE', 'DEBT', 'PRD', 'REL'];
const SESSION_ARTIFACT_DIRS = ['docs/ai/reviews', 'docs/ai/reports', 'docs/ai/briefs', 'tests'];

function walkAllFiles(dirAbs) {
  const out = [];
  const stack = [dirAbs];
  while (stack.length) {
    const cur = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(cur, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const ent of entries) {
      const abs = path.join(cur, ent.name);
      if (ent.isDirectory()) stack.push(abs);
      else if (ent.isFile()) out.push(abs);
    }
  }
  return out;
}

// Numeric TYPE:NUM pairs actually present as governed doc FILENAMES anywhere
// under docs/ (numeric equality, not string equality — an artifact token
// with a different zero-padding width than the eventual doc must still
// match, the exact motivating incident).
function knownGovernedIds(root) {
  const known = new Set();
  for (const dir of SLUG_HANDLE_GOVERNED_DIRS) {
    const abs = path.join(root, 'docs', dir);
    if (!fs.existsSync(abs)) continue;
    for (const f of fs.readdirSync(abs)) {
      const m = f.match(/^([A-Z]+(?:-[A-Z]+)*)-(\d{1,5})(?=[-.])/);
      if (m) known.add(`${m[1]}:${parseInt(m[2], 10)}`);
    }
  }
  return known;
}

// Findings [{ rel, rule, detail }] for the --slug-handles scan. Pure given a
// (root, known-ids) pair so it stays unit-testable without a real tree.
export function lintSlugHandles(root) {
  const findings = [];
  const known = knownGovernedIds(root);
  const tokenRe = new RegExp(`\\b(${SLUG_HANDLE_PREFIXES.join('|')})-(\\d{2,5})\\b`, 'g');
  for (const dirRel of SESSION_ARTIFACT_DIRS) {
    const abs = path.join(root, dirRel);
    if (!fs.existsSync(abs)) continue;
    for (const fileAbs of walkAllFiles(abs)) {
      const rel = toPosix(path.relative(root, fileAbs));
      const base = path.basename(fileAbs);
      tokenRe.lastIndex = 0;
      let m;
      while ((m = tokenRe.exec(base))) {
        const key = `${m[1]}:${parseInt(m[2], 10)}`;
        if (!known.has(key)) {
          findings.push({
            rel,
            rule: 'slug-handle-unconfirmed',
            detail: `filename embeds ${m[1]}-${m[2]} with no corresponding numbered governed doc in the local tree`,
          });
        }
      }
    }
  }
  return findings;
}

// 1-based line number of a character offset in normalized content.
function lineAt(norm, offset) {
  return norm.slice(0, offset).split('\n').length;
}

// One-line local mirror of the docs-audit-core evidence rule (SPEC D2):
// an Evidence cell is empty when blank, em-dash, or dash.
const rowHasEvidence = (row) => {
  const e = (row['Evidence'] ?? '').trim();
  return e !== '' && e !== '—' && e !== '-';
};

// The Test Plan reader moved to lib/docs-model.mjs (CHANGE-0120) so this lint
// and orchestration-dispatch's confirm-by-script content hash cannot drift on
// what a Test Plan row IS. `splitCells` stays a local alias because
// isStrategyGuidanceRow() below reads ordinary table rows with the same cell
// grammar.
const splitCells = splitTableCells;
const parseTestPlan = parseTestPlanTable;

// Expand a Test Plan Spec-AC cell into { ids, malformed } token lists.
// Grammar: comma/space-separated tokens, each `Spec-AC-NN` or `Spec-AC-NN..MM`.
function expandAcRefs(cell) {
  const ids = [];
  const malformed = [];
  const raw = String(cell ?? '').trim();
  if (raw === '' || raw === '—' || raw === '-') return { ids, malformed: [raw === '' ? '(empty)' : raw] };
  for (const tok of raw.split(/[,\s]+/).filter(Boolean)) {
    const single = tok.match(AC_ID_RE);
    if (single) { ids.push(tok); continue; }
    const range = tok.match(AC_RANGE_RE);
    if (range) {
      const from = Number(range[1]);
      const to = Number(range[2]);
      if (from <= to) {
        for (let n = from; n <= to; n += 1) ids.push(`Spec-AC-${String(n).padStart(2, '0')}`);
        continue;
      }
    }
    malformed.push(tok);
  }
  return { ids, malformed };
}

// --- strategy-scaled evidence contract (CHANGE-0122) --------------------------

// Strategies whose contract does NOT include a stored RED artifact.
const LEAN_EVIDENCE_STRATEGIES = new Set(['direct', 'untested']);

// Sections that state what evidence the spec DEMANDS. Deliberately excludes
// `## Implementation strategy` (its Rationale legitimately argues ABOUT
// RED-first TDD — SPEC-0110's real shape) and every narrative section.
const EVIDENCE_SECTIONS = [
  'acceptance criteria status',
  'acceptance criteria mapping',
  'test plan',
  'verification',
  'evidence contract',
];

// A demand for STORED RED / TDD-cycle evidence: the artifact nouns, the stored
// RED log directory, and the RED-classification checker. Bare "RED phase" /
// "red" status tokens are NOT demands (the template's own Test Plan legend says
// "red: test written and verified failing" for every strategy).
const RED_DEMAND_RE = /\bred[-_ ]?(?:logs?|artifacts?|proofs?|evidence)\b|\bdocs\/ai\/tdd\/|\btdd-evidence-check\b|\btdd[- ]cycle\s+evidence\b|\bred[- ]green[- ]refactor\b/i;

// The same sentence WAIVING that evidence is the opposite of a demand.
const RED_WAIVED_RE = /\b(?:no|not|never|without|waived?|waiver|exempt|optional|n\/a)\b[^\n]{0,80}?\b(?:red|tdd)\b|\b(?:red|tdd)\b[^\n]{0,80}?\b(?:not required|never required|no longer required|optional|waived|exempt|n\/a)\b/i;

// Level-2 sections of `norm`, filtered to `titles` (lowercased, exact).
// Returns [{ title, body, start }] where start is body's offset in norm.
function sectionsByTitle(norm, titles) {
  const out = [];
  const re = /(?:^|\n)##\s+([^\n]+)\n([\s\S]*?)(?=\n##\s|$)/g;
  let m;
  while ((m = re.exec(norm))) {
    if (!titles.includes(m[1].trim().toLowerCase())) continue;
    out.push({ title: m[1].trim(), body: m[2], start: m.index + m[0].length - m[2].length });
  }
  return out;
}

// A per-strategy GUIDANCE row (first cell is only strategy tokens, e.g.
// `| tdd / hybrid | RED artifact ... |`) states what EACH strategy owes — it is
// never this spec's own demand, so the evidence table SPEC_TEMPLATE ships is
// not self-flagging.
function isStrategyGuidanceRow(text) {
  if (!text.startsWith('|')) return false;
  const first = (splitCells(text)[0] ?? '').trim().toLowerCase();
  if (first === '') return false;
  const tokens = first.split(/[\s/,+]+/).filter(Boolean);
  return tokens.length > 0 && tokens.every((t) => STRATEGY_ENUM.includes(t));
}

// Split a section body into assertion units: each table row is its own unit,
// each bullet/paragraph is joined across its wrapped lines and then split into
// sentences, so a demand and a waiver never merge into one unit and a wrapped
// demand never splits across two. Each unit carries its 1-based start line.
function assertionUnits(body, start, norm) {
  const units = [];
  let para = [];
  let paraOffset = 0;
  let offset = 0;
  const flush = () => {
    if (!para.length) return;
    const line = lineAt(norm, start + paraOffset);
    const joined = para.join(' ').replace(/\s+/g, ' ').trim();
    for (const s of joined.split(/(?<=[.;])\s+/)) {
      if (s.trim()) units.push({ text: s.trim(), line });
    }
    para = [];
  };
  for (const raw of body.split('\n')) {
    const t = raw.trim();
    if (t === '' || t.startsWith('|') || /^[-*]\s/.test(t)) flush();
    if (t === '') { /* separator only */ } else if (t.startsWith('|')) {
      units.push({ text: t, line: lineAt(norm, start + offset) });
    } else {
      if (!para.length) paraOffset = offset;
      para.push(t);
    }
    offset += raw.length + 1;
  }
  flush();
  return units;
}

// Every unit in an evidence-bearing section that demands stored RED / TDD-cycle
// evidence. Pure over the document. Returns [{ section, excerpt, line }].
export function redEvidenceDemands(norm) {
  const hits = [];
  for (const sec of sectionsByTitle(norm, EVIDENCE_SECTIONS)) {
    // The template's own "### Evidence by strategy" subsection is per-strategy
    // GUIDANCE by definition (it describes what tdd owes so it necessarily
    // names RED artifacts) — a direct spec derived from SPEC_TEMPLATE was
    // self-flagging on it (bot P2). Strip that subsection before scanning:
    // from its ### heading to the next heading of any level.
    const body = sec.body.replace(
      /^###\s+Evidence by strategy[^\n]*\n[\s\S]*?(?=^#{1,4}\s|(?![\s\S]))/m, '');
    for (const unit of assertionUnits(body, sec.start, norm)) {
      if (isStrategyGuidanceRow(unit.text)) continue;
      // Self-reference: a sentence ABOUT the lint rule is documentation,
      // not a demand.
      if (unit.text.includes('strategy-evidence-mismatch')) continue;
      if (!RED_DEMAND_RE.test(unit.text)) continue;
      if (RED_WAIVED_RE.test(unit.text)) continue;
      const excerpt = unit.text.length > 90 ? `${unit.text.slice(0, 87)}...` : unit.text;
      hits.push({ section: sec.title, excerpt, line: unit.line });
    }
  }
  return hits;
}

// Lint one document's content. Pure: no filesystem, no git. Returns findings
// [{ rule, detail, line }] — rel/id are attached by the caller.
// opts.strategy: STATE's recorded implementation strategy when the CALLER knows
// it (--strategy); it outranks the document's own record. See the header.
export function lintContent(content, opts = {}) {
  const findings = [];
  const add = (rule, detail, line = null) => findings.push({ rule, detail, line });
  const norm = normalizeNewlines(content);
  const fm = parseFrontmatter(norm) ?? {};
  const ac = parseAcTable(norm);
  const fmStatus = String(fm.status ?? '').trim().toLowerCase();

  // spec-id-shape (SPEC-0058): a type: spec doc whose frontmatter id is a
  // collision-prone bare slug (neither the legacy numbered SPEC-NNNN form nor
  // a spec--prefixed slug) shares its originating change/issue's id — the
  // root cause of several real spec-id collisions. Guarded on type===spec so
  // --path mode never flags a non-spec doc. Empty/missing id is docs-audit's
  // boundary, not this check's.
  if (String(fm.type ?? '').toLowerCase() === 'spec') {
    const id = String(fm.id ?? '');
    const numbered = /^SPEC-\d+$/i.test(id);
    const prefixed = id.startsWith('spec-');
    if (id !== '' && !numbered && !prefixed) {
      add('spec-id-shape', `spec id "${id}" is a bare slug (neither the numbered SPEC-NNNN form nor a spec-<slug> id) — rename it to spec-<change-slug> so it cannot collide with its change/issue id`);
    }
  }

  // ceremony_level enum (advisory freeze-time twin of the close-gate check;
  // absent or YAML null is legacy implicit level 2, never flagged).
  let level = 2;
  const clRaw = fm.ceremony_level;
  if (clRaw !== undefined && clRaw !== null) {
    if (!CEREMONY_ENUM.includes(String(clRaw))) {
      add('ceremony-level-invalid', `ceremony_level "${clRaw}" is not one of 0 | 1 | 2 | 3`);
    } else {
      level = Number(clRaw);
    }
  }

  // --- AC Status table structure ------------------------------------------
  const knownIds = new Set();
  if (ac.hasGate) {
    const nums = [];
    for (const row of ac.rows) {
      const id = row['Spec-AC'];

      if (knownIds.has(id)) add('ac-id-duplicate', `${id} appears more than once in the AC Status table`);
      knownIds.add(id);
      const m = id.match(AC_ID_RE);
      if (m) nums.push(Number(m[1]));
      else add('ac-id-malformed', `AC id "${id}" does not match Spec-AC-NN (two digits)`);
      const rawStatus = row['Status'] ?? '';
      const st = normalizeAcStatus(rawStatus);
      if (rawStatus.trim() && !st.canonical) {
        add('ac-status-invalid', `${id} status "${rawStatus}" is not a canonical AC status`);
      }
      if (st.status === 'done' && !rowHasEvidence(row)) {
        add('done-without-evidence', `${id} is done but Evidence is empty`);
      }
    }
    const uniq = [...new Set(nums)].sort((a, b) => a - b);
    if (uniq.length) {
      const missing = [];
      for (let n = 1; n <= uniq[uniq.length - 1]; n += 1) {
        if (!uniq.includes(n)) missing.push(`Spec-AC-${String(n).padStart(2, '0')}`);
      }
      if (missing.length) add('ac-id-gap', `AC ids are not sequential from Spec-AC-01: missing ${missing.join(', ')}`);
    }

    // Rows the shared parser silently DROPPED (cell-count mismatch, e.g.
    // markdown-escaped pipes in a cell): invisible to docs-audit, the index,
    // and the close gate — the exact SPEC-0012 Spec-AC-08 shape.
    const section = norm.match(/(?:^|\n)##\s+Acceptance Criteria Status\b[^\n]*\n([\s\S]+?)(?=\n##\s|\n*$)/i);
    if (section) {
      const sectionStart = section.index + section[0].indexOf(section[1]);
      let offset = 0;
      // SPEC-0051: tally the RAW first-cell id on every data row (filtered to
      // well-formed Spec-AC-NN so range rows / malformed ids never enter it —
      // range rows already fail the (?=\s|\|) lookahead below; malformed ids
      // are owned by ac-id-malformed) for the raw-vs-parsed reconciliation.
      const rawCount = new Map();
      for (const line of section[1].split('\n')) {
        const lineNo = lineAt(norm, sectionStart + offset);
        offset += line.length + 1;
        // Review F1: anchor the capture to the id CELL — the old \S* greedily
        // swallowed pipes on compact rows (|Spec-AC-01|a|...), mangling the id
        // into the whole pipe-run and firing a spurious unparseable finding.
        const raw = line.match(/^\|\s*(Spec-AC-\d+)(?=\s|\|)/);
        if (!raw) continue;
        if (AC_ID_RE.test(raw[1])) rawCount.set(raw[1], (rawCount.get(raw[1]) ?? 0) + 1);
        if (!knownIds.has(raw[1])) {
          add('ac-row-unparseable', `row for ${raw[1]} was dropped by the shared table parser (cell count breaks the header — check escaped/raw pipes in a cell); it is invisible to docs-audit, the index, and the close gate`, lineNo);
        }
      }
      // SPEC-0051: a duplicate id whose second (or later) copy is dropped by
      // the shared parser's cell-count break is invisible to BOTH existing
      // checks — the surviving copy seeds knownIds (silencing ac-row-
      // unparseable) and only one copy reaches ac.rows (silencing ac-id-
      // duplicate). Reconcile rawCount against the parser's surviving rows:
      // rawCount > parsedCount AND parsedCount >= 1 (the >=1 guard hands the
      // fully-vanished case, parsedCount == 0, to ac-row-unparseable so
      // neither rule double-reports the other's shape).
      const parsedCount = new Map();
      for (const row of ac.rows) {
        const id = row['Spec-AC'];
        if (AC_ID_RE.test(id)) parsedCount.set(id, (parsedCount.get(id) ?? 0) + 1);
      }
      for (const [id, rc] of rawCount) {
        const pc = parsedCount.get(id) ?? 0;
        if (rc > pc && pc >= 1) {
          const dropped = rc - pc;
          add('duplicate-ac-id', `${id} appears in ${rc} raw AC-table rows but only ${pc} survived the shared parser — a duplicate id dropped ${dropped} row${dropped === 1 ? '' : 's'} (invisible to docs-audit, the index, and the close gate)`);
        }
      }
    }
  } else if (level <= 1) {
    // L0/L1 lean table (no canonical gate): seed knownIds so the Test-Plan
    // mapping check below doesn't flag every lean AC id as unknown (validation
    // F1 second face — the lean ids ARE the spec's ACs at these levels).
    const lean = parseLeanAcTable(norm);
    for (const row of lean.rows) {
      const id = row['Spec-AC'];
      if (id) knownIds.add(id);
    }
  }

  // --- Test Plan -> Spec-AC mapping -----------------------------------------
  const tp = parseTestPlan(norm);
  const coveredAcIds = new Set();
  for (const row of tp.rows) {
    const { ids, malformed } = expandAcRefs(row.acCell);
    for (const tok of malformed) {
      add('test-ac-malformed', `${row.testId} Spec-AC cell token "${tok}" does not match Spec-AC-NN or Spec-AC-NN..MM`, row.line);
    }
    for (const id of ids) {
      coveredAcIds.add(id);
      if (!knownIds.has(id)) {
        add('test-ac-unknown', `${row.testId} references ${id}, which is not in the AC Status table`, row.line);
      }
    }
  }

  // --- Spec-AC -> TEST reverse coverage (CHANGE-0113 D2 probe R21) ----------
  // The mapping check above is one-directional: it catches a TEST row pointing
  // at an AC that does not exist, never an AC that no TEST row claims. The
  // altitude replay (docs/analysis/altitude-replay.md, task T3) is the
  // motivating evidence — a Planning candidate produced well-formed ACs whose
  // tests were absent or non-functional, and nothing in the toolchain said so.
  // Both AC-table shapes feed it: the canonical gate table and the L0/L1 lean
  // table already seeded into `knownIds` above, so the lean path needs no
  // second parser.
  //   SCOPE — in-flight specs only (draft/proposed/accepted/implementing, the
  //   same set spec-freeze.mjs will freeze). A terminal spec's Test Plan is
  //   HISTORY: its suites have since been renamed, folded or archived, and
  //   re-litigating them yields noise, not action (12 such specs live in this
  //   corpus today). The rule bites exactly where it can still change an
  //   outcome — the freeze boundary.
  if (IN_FLIGHT_STATUSES.includes(fmStatus)) {
    for (const id of knownIds) {
      // Malformed ids are owned by `ac-id-malformed`; do not double-report.
      if (!AC_ID_RE.test(id)) continue;
      if (coveredAcIds.has(id)) continue;
      // parseAcTable rows carry no line field — locate the id's own table
      // row (first `| <id>` line) so the finding is jump-to-able (bot review).
      const acLineIdx = norm.split('\n').findIndex(l => l.trim().startsWith('|') && l.includes(id));
      add('ac-without-test', `${id} has no Test Plan row claiming it — every Spec-AC needs at least one TEST-xxx entry naming a runnable command before the spec is frozen`, acLineIdx >= 0 ? acLineIdx + 1 : null);
    }
  }

  // --- Deltas shape validation (RFC-0011, delta-spec lifecycle) -------------
  // The optional `## Deltas` section declares intended requirement changes;
  // spec-lint checks their SHAPE via the shared parseDeltasSection reader (same
  // grammar the canonical layer accepts — one source of truth). A spec with NO
  // `## Deltas` section produces ZERO findings here (legacy specs untouched);
  // a present-but-empty section is a valid state. Each parsed violation renders
  // one-for-one into a finding with its D2 code and the block's line number.
  const deltas = parseDeltasSection(norm);
  for (const v of deltas.violations) add(v.code, v.detail, v.line ?? null);

  // --- SPEC-FROZEN consistency ----------------------------------------------
  // Strategy is exempt at levels 0/1 (RFC-0009 lean artifacts). The AC table:
  // L0 exempt (tech-note lives in the CHANGE doc); L1 satisfied by a LEAN
  // table (ids+status) — must match the close gate, which now accepts it
  // (CHANGE l1-close-gate); L2+ require the canonical gate table. Reporting a
  // frozen-without-ac-table on an L1 lean spec that the gate passes CLEAN was
  // a real tool-disagreement (validation F1).
  // The recorded strategy, caller-supplied value first (header precedence
  // note). Read once: the frozen check below uses the DOCUMENT's own line
  // (a caller's flag cannot make a spec self-consistent), the CHANGE-0122
  // evidence rule uses the resolved value, and unknown/`undecided` stays null
  // so the evidence rule fails open.
  const bodyStrategy = norm.match(/^-\s*Strategy:\s*(\S+)/m);
  const fmStrategy = fm.strategy === undefined || fm.strategy === null ? null : String(fm.strategy);
  const declared = (opts.strategy ?? fmStrategy ?? (bodyStrategy ? bodyStrategy[1] : null));
  const declaredLc = declared ? String(declared).toLowerCase() : null;
  const strategy = STRATEGY_ENUM.includes(declaredLc) && declaredLc !== 'undecided' ? declaredLc : null;

  // half-frozen (CHANGE-0120) — freeze is a TWO-PART state: the
  // `SPEC-FROZEN: true` body marker AND frontmatter `status: implementing`.
  // Writing one half without the other is paperwork the dispatcher cannot
  // interpret, and a live ride burned a full re-Planning agent fixing exactly
  // that. Flagged HERE, at freeze time, so the mismatch cannot survive to
  // dispatch; `.aai/scripts/spec-freeze.mjs` is the tool that writes both
  // halves in one atomic write and therefore cannot produce this state.
  //   Marker arm: the marker with a PRE-implementation status (draft /
  //   proposed / accepted) — the exact incident shape.
  //   Status arm: `implementing` with no marker — the mirror image.
  // `done` is deliberately OUTSIDE the status arm: a completed spec is past
  // the freeze gate, and the pre-marker-convention specs still in the corpus
  // are history, not half-freezes.
  const frozenMarker = specFrozenInBody(norm);
  if (frozenMarker &&['draft', 'proposed', 'accepted'].includes(fmStatus)) {
    add('half-frozen', `SPEC-FROZEN is true but frontmatter status is "${fmStatus}" — freeze is atomic (marker + status: implementing); run node .aai/scripts/spec-freeze.mjs --path <spec> instead of writing either half by hand`);
  } else if (!frozenMarker && fmStatus === 'implementing') {
    add('half-frozen', 'frontmatter status is "implementing" but the SPEC-FROZEN marker is absent — freeze is atomic (marker + status: implementing); run node .aai/scripts/spec-freeze.mjs --path <spec> instead of writing either half by hand');
  }

  if (frozenMarker) {
    if (level >= 2) {
      const bodyLc = bodyStrategy ? bodyStrategy[1].toLowerCase() : null;
      if (!bodyLc || bodyLc === 'undecided') {
        add('frozen-without-strategy', `SPEC-FROZEN is true but implementation strategy is ${bodyLc ? `"${bodyLc}"` : 'missing'}`);
      }
    }
    if (level >= 2 && !ac.hasGate) {
      add('frozen-without-ac-table', 'SPEC-FROZEN is true but no canonical Acceptance Criteria Status gate table is present');
    } else if (level === 1 && !ac.hasGate) {
      const lean = parseLeanAcTable(norm);
      if (lean.rows.length === 0) {
        add('frozen-without-ac-table', 'SPEC-FROZEN is true (ceremony_level 1) but no Acceptance Criteria table (lean or canonical) is present');
      }
    }
  }

  // --- strategy-scaled evidence contract (CHANGE-0122) ----------------------
  // Only direct/untested can mismatch; tdd/hybrid and unknown emit nothing.
  if (LEAN_EVIDENCE_STRATEGIES.has(strategy)) {
    const demands = redEvidenceDemands(norm);
    if (demands.length) {
      const owed = strategy === 'direct'
        ? 'targeted regression tests green + the scoped diff'
        : 'the recorded strategy rationale + the scoped diff';
      const more = demands.length > 1 ? ` (+${demands.length - 1} more)` : '';
      add(
        'strategy-evidence-mismatch',
        `implementation strategy is "${strategy}" but "## ${demands[0].section}" demands stored RED / TDD-cycle evidence: "${demands[0].excerpt}"${more} — a ${strategy} ride owes ${owed}, not a stored RED artifact; scale the demand to the strategy or re-record the strategy (CHANGE-0122)`,
        demands[0].line,
      );
    }
  }

  return findings;
}

function lintFileAt(absPath, rel, opts = {}) {
  let content;
  try {
    content = fs.readFileSync(absPath, 'utf8');
  } catch {
    return null;
  }
  const fm = parseFrontmatter(normalizeNewlines(content));
  const id = fm?.id ?? null;
  return { id, findings: lintContent(content, opts).map((f) => ({ rel, id, ...f })) };
}

function main() {
  const args = parseArgs(process.argv);

  if (args.slugHandles) {
    const findings = lintSlugHandles(ROOT);
    const clean = findings.length === 0;
    if (args.json) {
      console.log(JSON.stringify({ mode: 'slug-handles', findings, clean }, null, 2));
    } else {
      console.log(`## Spec Lint — slug-handles — ${new Date().toISOString().slice(0, 10)}`);
      console.log('');
      console.log(`- Findings: ${findings.length}`);
      console.log('');
      if (clean) {
        console.log('LINT PASS: no unconfirmed slug-handle findings.');
      } else {
        console.log('LINT FINDINGS (report-only — advisory, never a hard gate):');
        for (const f of findings) console.log(`- ${f.rel} [${f.rule}] ${f.detail}`);
      }
    }
    process.exit(clean ? 0 : 1);
  }

  const findings = [];
  let scanned = 0;
  let skipped = 0;

  if (args.path) {
    const abs = path.isAbsolute(args.path) ? args.path : path.join(ROOT, args.path);
    if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) fail(`file not found or unreadable: "${args.path}"`);
    const res = lintFileAt(abs, toPosix(path.relative(ROOT, abs)), { strategy: args.strategy });
    if (!res) fail(`file not found or unreadable: "${args.path}"`);
    scanned = 1;
    findings.push(...res.findings);
  } else {
    for (const abs of walk(path.join(ROOT, 'docs/specs'))) {
      const rel = toPosix(path.relative(ROOT, abs));
      let content;
      try {
        content = fs.readFileSync(abs, 'utf8');
      } catch {
        skipped += 1;
        continue;
      }
      const fm = parseFrontmatter(normalizeNewlines(content));
      if (String(fm?.type ?? '').toLowerCase() !== 'spec') { skipped += 1; continue; }
      scanned += 1;
      // No opts: --strategy is --path-scoped (parseArgs enforces it), so a
      // corpus scan always reads each spec's own recorded strategy.
      findings.push(...lintContent(content).map((f) => ({ rel, id: fm?.id ?? null, ...f })));
    }
  }

  const clean = findings.length === 0;
  if (args.json) {
    console.log(JSON.stringify({ scanned, skipped, findings, clean }, null, 2));
  } else {
    console.log(`## Spec Lint — ${new Date().toISOString().slice(0, 10)}`);
    console.log('');
    console.log(`- Scanned: ${scanned} spec doc(s) | Skipped: ${skipped} non-spec | Findings: ${findings.length}${args.path ? ` | Scope: ${args.path}` : ''}`);
    console.log('');
    if (clean) {
      console.log('LINT PASS: no structural findings.');
    } else {
      console.log('LINT FINDINGS (report-only — advisory, never a hard gate in v1):');
      for (const f of findings) {
        console.log(`- ${f.rel}${f.line ? `:${f.line}` : ''} [${f.rule}] ${f.detail}`);
      }
    }
  }
  process.exit(clean ? 0 : 1);
}

// Run only when executed directly (tests may import lintContent).
import { fileURLToPath } from 'node:url';
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main();
}
