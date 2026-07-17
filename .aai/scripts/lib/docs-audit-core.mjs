// Docs hygiene & drift audit core (RFC-0002 / SPEC-0001).
// Pure analysis: classifies every prefixed doc under docs/ and derives drift
// verdicts. REPORTS only — never writes to any doc, plan, or backlog file.

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import {
  DOC_STATUS_ENUM, TERMINAL_AC, DOC_TYPE_ENUM, DOC_ID_RE,
  DEFAULT_CATEGORY_PREFIXES, extractDocIds, normalizeAcStatus,
  parseFrontmatter, parseAcTable, parseLeanAcTable, parseISODate, parseReviewBy,
  specFrozenInBody, validateCanonicalFrontmatter, asList, toPosix,
  detectNearMissAcTable, parseRequirementsSection,
} from './docs-model.mjs';
import { guardConfigPresent } from './guard-config.mjs';

// CONFIG_PATH stays here (audit-core owns its scan root); the PRESENCE probe
// that flips enforced vs report-only mode is the SHARED one from
// lib/guard-config.mjs (CHANGE-0009 D8) — the same file also carries the
// independence/close_gate/doc_number_guard dials read by state.mjs and the
// pre-commit hooks, so the coupling is documented at one import site.
export const CONFIG_PATH = 'docs/ai/docs-audit.yaml';
export const EVENTS_PATH = 'docs/ai/EVENTS.jsonl';
const SCAN_ROOT = 'docs';
// RFC-0003 / SPEC-0002 SEAM-3: the canonicalization layer archives originals to
// `docs/_archive/` (with underscore). The historical exclude list named
// `archive` (no underscore), which would let archived docs be scanned and
// mis-flagged as orphans. Both names are excluded so the chosen archive dir is
// consistently treated as preserved-not-active.
const EXCLUDE_DIRS = new Set(['ai', 'knowledge', 'archive', '_archive', 'project-sessions', 'templates']);
const ID_FILE_RE = DOC_ID_RE;
// CHANGE-0012 / spec-slug-refs-across-tooling D3: `<TYPE>-DRAFT-<slug>.md`
// basenames (SPEC-0015 slug-first drafts) are first-class audit citizens —
// the same `(?:DRAFT|\d{1,5})` filename form generate-docs-index.mjs and
// allocate-doc-number.mjs already accept. A DRAFT doc's audit id is its
// frontmatter slug `id`; its fileId stays null (no display id until merge).
const DRAFT_FILE_RE = /^[A-Z]+(?:-[A-Z]+)*-DRAFT(?=[-.])/;
const OPEN_STATUSES = new Set(['draft', 'implementing']);
// CHANGE-0027 / SPEC-0039 D1 — eligible statuses for the false-open drift
// heuristic. Deliberately separate from OPEN_STATUSES (which still drives
// ONLY probable-stale-open): false-open additionally covers `accepted`.
const FALSE_OPEN_STATUSES = new Set(['draft', 'implementing', 'accepted']);
// RFC-0009 L0/L1 level-inflation guard: the literal `Ceremony justification: `
// body line. Shared by the close gate and the done-drift check
// (spec-l1-close-gate D2/D3) — one definition, no fork.
const CEREMONY_JUSTIFICATION_RE = /(?:^|\n)Ceremony justification:[ \t]*\S/;
// spec-l1-close-gate D2 — lean-eligibility comes ONLY from a validly declared
// ceremony_level of 0 or 1. Absent/null = legacy implicit L2; a garbage value
// keeps full canonical requirements (fail-closed, same discipline as the
// dispatch: a bad declaration can only ever ADD ceremony, never remove it).
const isLeanCeremonyLevel = (clRaw) => clRaw !== undefined && clRaw !== null
  && (String(clRaw) === '0' || String(clRaw) === '1');
// spec-l1-close-gate — the lean AC parser splits rows on a naive `|`, so a row
// whose cell carries a literal pipe (plain `|` OR an escaped `\|`, which this
// parser does NOT unescape) gains a phantom cell, fails the column-count check,
// and is SILENTLY dropped — leaving a consumer to validate only the survivors
// while a declared row goes unchecked. parseLeanAcTable returns `declaredIds`
// (every Spec-AC id in the SAME line set it walks, dropped rows included); a
// declared id absent from the parsed `rows` is an unparseable row. Both the
// close gate and the done-drift check reconcile on it so neither can pass/clean
// while a declared AC is invisible.
const unparseableLeanIds = (lean) => {
  // Compare on the LEADING Spec-AC-NN of each parsed row's id cell, matching how
  // declaredIds is extracted (`^\s*\|\s*(Spec-AC-\d+)\b`). A well-formed but
  // suffixed id cell (e.g. "Spec-AC-02 (note)") parses cleanly and must NOT be
  // misreported as an unparseable pipe-drop — it declared and it parsed.
  const parsed = new Set(lean.rows.map(r => {
    const m = String(r['Spec-AC'] ?? '').match(/^(Spec-AC-\d+)\b/);
    return m ? m[1] : r['Spec-AC'];
  }));
  return (lean.declaredIds ?? []).filter(id => !parsed.has(id));
};
const DEFAULT_STALE_DAYS = 90;
// closeout-candidate detection (SPEC-0003 / CHANGE-0004): parents are scoped to
// rfc/prd only (change docs also carry links.spec and would false-positive), and
// only non-terminal, ready statuses are eligible (draft excluded — not yet ready).
const CLOSEOUT_PARENT_TYPES = new Set(['rfc', 'prd']);
const CLOSEOUT_PARENT_STATUSES = new Set(['proposed', 'accepted', 'implementing']);

// SPEC-0006 Spec-AC-06 — open-decision-on-done guard. A body line that asserts an
// UNRESOLVED decision: a token below combined with a WARNING context (a literal
// WARNING word or a GitHub `> [!WARNING]` callout block), or an explicit
// `<!-- OPEN-DECISION -->` marker. Narrow on purpose — an ordinary informational
// note (no token, no WARNING) must NOT trip it (false-positive negative control).
const OPEN_DECISION_TOKEN_RE = /\b(?:unresolved|open decisions?|must be (?:resolved|confirmed|decided)|pending (?:confirmations?|decisions?)|to be (?:resolved|confirmed|decided))\b/i;
const OPEN_DECISION_COMMENT_RE = /<!--\s*OPEN-DECISION\s*-->/i;

// --- config -----------------------------------------------------------------

export function loadConfig(root) {
  const p = path.join(root, CONFIG_PATH);
  if (!guardConfigPresent(path.dirname(p))) return null;
  const cfg = {
    legacy_until_date: null,
    stale_after_days: DEFAULT_STALE_DAYS,
    plan_scan_mode: 'lenient',
    scan_exclude: [],
    backlog_globs: [],
    review_by_methods: [],
    category_prefixes: [...DEFAULT_CATEGORY_PREFIXES],
    // SPEC-0011 G5/config — close-time gate enforcement mode. Only the CALLERS
    // (the G5 pre-commit hook, the closeout skills) consult this to choose
    // block-vs-warn; `--gate` itself always returns the raw predicate exit code.
    // Default report-only keeps mid-migration downstream repos non-blocking.
    close_gate: 'report-only',
    // SPEC-0013 H1/config — body-lint enforcement mode, mirroring close_gate.
    // Consulted only by the pre-commit hook to choose block-vs-warn;
    // `--lint-body-file` itself always returns the raw predicate exit code.
    body_lint: 'report-only',
    // RFC-0009 / spec-scale-adaptive-ceremony — project-owned L3
    // protected-surface list (POLICY + canonical defaults live in
    // .aai/workflow/WORKFLOW.md "Ceremony levels"). Consult-time input for
    // Planning (a spec touching a listed path must declare ceremony_level: 3)
    // and review upward re-classification; no mechanical diff enforcement yet.
    protected_paths_l3: [],
  };
  const LIST_KEYS = new Set(['scan_exclude', 'backlog_globs', 'review_by_methods', 'category_prefixes', 'protected_paths_l3']);
  let listKey = null;
  for (const raw of fs.readFileSync(p, 'utf8').split('\n')) {
    const line = raw.replace(/#.*$/, '').trimEnd();
    if (!line.trim()) continue;
    const item = line.match(/^\s+-\s+(.*)$/);
    if (item && listKey) { cfg[listKey].push(item[1].trim().replace(/^["']|["']$/g, '')); continue; }
    // key pattern allows digits after the first char (protected_paths_l3)
    const kv = line.match(/^([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)$/);
    if (!kv) continue;
    const [, key, rawVal] = kv;
    const val = rawVal.trim();
    if (LIST_KEYS.has(key)) {
      listKey = key;
      // an explicit value replaces the default (block items follow when empty)
      if (val && val !== '[]') {
        cfg[key] = val.replace(/^\[|\]$/g, '').split(',').map(s => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
        listKey = null;
      } else {
        cfg[key] = [];
        if (val === '[]') listKey = null;
      }
      continue;
    }
    listKey = null;
    if (key === 'legacy_until_date') cfg.legacy_until_date = val || null;
    else if (key === 'stale_after_days') cfg.stale_after_days = Number(val) || DEFAULT_STALE_DAYS;
    else if (key === 'plan_scan_mode') cfg.plan_scan_mode = (val === 'strict') ? 'strict' : 'lenient';
    else if (key === 'close_gate') cfg.close_gate = (val === 'enforce') ? 'enforce' : 'report-only';
    else if (key === 'body_lint') cfg.body_lint = (val === 'enforce') ? 'enforce' : 'report-only';
  }
  return cfg;
}

// --- git probes (skipped in quick mode) --------------------------------------

function git(root, cmd) {
  try {
    return execSync(`git ${cmd}`, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

export function firstCommitDate(root, rel) {
  // no --follow: its rename detection mis-attributes a file's add commit to
  // an unrelated commit that added similar content (CHANGE-0002 D13 fixture)
  const out = git(root, `log --diff-filter=A --format=%cs -- "${rel}"`);
  if (!out) return null;
  const lines = out.split('\n').filter(Boolean);
  return lines.length ? lines[lines.length - 1] : null;
}

function lastEditDate(root, rel) {
  return git(root, `log -1 --format=%cs -- "${rel}"`) || null;
}

function lastIdMentionDate(root, id) {
  return git(root, `log -1 --grep="${id}" --format=%cs`) || null;
}

// CHANGE-0027 / SPEC-0039 D4 — mention boundary (CHANGE-0002 D11 extended to
// slugs). A numbered id (TYPE-NNNN, e.g. CHANGE-0027) allows a trailing "-"
// (so a basename mention "CHANGE-0009-<slug>" counts for CHANGE-0009) but
// never matches inside a longer sibling numeric id (CHANGE-030 never matches
// inside CHANGE-0301). A slug id (no trailing digit) never matches inside a
// longer sibling slug (its right boundary excludes "-" too).
const NUMBERED_ID_RE = /^[A-Z]+(?:-[A-Z]+)*-\d{1,5}(?:-\d+)?$/;
function idMentionRegex(id) {
  const esc = String(id).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return NUMBERED_ID_RE.test(id)
    ? new RegExp(`(?<![0-9A-Za-z])${esc}(?![0-9])`)
    : new RegExp(`(?<![0-9A-Za-z-])${esc}(?![0-9A-Za-z-])`);
}

// D3 — commit hashes that ADDED the doc's file (the intake commit(s)); these
// never count as delivery evidence (no --follow, per CHANGE-0002 D13, mirrors
// firstCommitDate).
function addCommitHashes(root, rel) {
  const out = git(root, `log --diff-filter=A --format=%H -- "${rel}"`);
  return out ? new Set(out.split('\n').filter(Boolean)) : new Set();
}

// D2(a)/D3/D4 — every commit whose SUBJECT is delivery-shaped (feat/fix/chore)
// AND mentions `id` at a real boundary. `git log --grep` pre-filters at the
// git level (cheap, may over-match); the exact D4 boundary regex re-checks
// the SUBJECT only (never the body), so a coincidental body-only mention can
// never masquerade as delivery evidence.
const DELIVERY_SUBJECT_RE = /^(feat|fix|chore)(\([^)]*\))?!?:/;

// D2(c) corroboration — an Evidence cell whose ONLY content is a path under
// docs/ai/tdd/ (this project's RED/GREEN proof-log convention) is same-session
// test-pass proof, not delivery corroboration. See falseOpenEvidence below.
const TDD_LOG_EVIDENCE_RE = /docs\/ai\/tdd\//;
function deliveryCommitsForId(root, id) {
  const out = git(root, `log --grep="${id}" --format=%H%x1f%s`);
  if (!out) return [];
  const re = idMentionRegex(id);
  const hashes = [];
  for (const line of out.split('\n')) {
    if (!line) continue;
    const sep = line.indexOf('\x1f');
    if (sep < 0) continue;
    const hash = line.slice(0, sep);
    const subject = line.slice(sep + 1);
    if (DELIVERY_SUBJECT_RE.test(subject) && re.test(subject)) hashes.push(hash);
  }
  return hashes;
}

// CHANGE-0027 / SPEC-0039 — D2's three delivery-evidence signals for one
// eligible open doc. Returns { evidenced, reasons }; reasons names every
// signal that actually fired (D10) — never fabricated, never silent.
function falseOpenEvidence(root, doc, events) {
  const reasons = [];
  let evidenced = false;

  // D2(a)/D3/D4 — delivery commit(s) mentioning the id or numbered fileId,
  // excluding the doc's own add-commit(s).
  const idCandidates = [...new Set([doc.id, doc.fileId].filter(Boolean))];
  if (idCandidates.length) {
    const addCommits = addCommitHashes(root, doc.rel);
    const hashes = new Set();
    for (const idc of idCandidates) {
      for (const hash of deliveryCommitsForId(root, idc)) {
        if (!addCommits.has(hash)) hashes.add(hash);
      }
    }
    if (hashes.size) {
      evidenced = true;
      const shortHashes = [...hashes].slice(0, 3).map(h => h.slice(0, 7));
      reasons.push(`delivery commit(s) ${shortHashes.join(', ')} mention ${doc.id}`);
    }
  }

  // D2(b) — ac_evidence event, same roll-up boundary as probable-false-done
  // (CHANGE-0002 D11): ref equal to the id, or ref.startsWith(id + '/').
  if (events.some(e => e.event === 'ac_evidence'
      && (String(e.ref) === doc.id || String(e.ref).startsWith(doc.id + '/')))) {
    evidenced = true;
    reasons.push('ac_evidence event');
  }

  // D2(c) — fully terminal canonical AC Status table, every done row evidenced.
  // Corroboration: a done row's Evidence pointing ONLY at this project's own
  // same-session TDD proof log (docs/ai/tdd/*.log — the RED/GREEN artifact
  // named in the Evidence contract) proves the tests passed locally; it does
  // NOT by itself prove the work was DELIVERED. Without that distinction,
  // D2(c) alone fires on every spec's normal mid-validation lifecycle state
  // (AC table completed by TDD, doc still draft/implementing, close ceremony
  // simply not run yet) — indistinguishable from "delivered and abandoned
  // open" (the incident class D2(c) exists to catch). At least one done row
  // must therefore cite something else (a commit hash, PR link, ac_evidence
  // ref, etc.) for the table-alone signal to fire; rowHasEvidence itself is
  // unchanged (still reused as-is — no parser fork).
  const ac = doc.ac;
  if (ac?.hasGate && ac.rows.length > 0) {
    const statuses = ac.rows.map(r => normalizeAcStatus(r['Status'] ?? '').status);
    const allTerminal = statuses.every(s => TERMINAL_AC.has(s));
    const doneRows = ac.rows.filter((r, i) => statuses[i] === 'done');
    const allDoneEvidenced = doneRows.every(r => rowHasEvidence(r));
    const hasDeliveryEvidence = doneRows.some(r =>
      rowHasEvidence(r) && !TDD_LOG_EVIDENCE_RE.test(String(r['Evidence'] ?? '')));
    if (allTerminal && allDoneEvidenced && hasDeliveryEvidence) {
      evidenced = true;
      reasons.push('AC Status table fully terminal with evidence');
    }
  }

  return { evidenced, reasons };
}

// --- events -----------------------------------------------------------------

export function readEvents(root) {
  const p = path.join(root, EVENTS_PATH);
  if (!fs.existsSync(p)) return [];
  const events = [];
  for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try { events.push(JSON.parse(line)); } catch { /* tolerate partial lines */ }
  }
  return events;
}

// SPEC-0011 G3 — read-only probe for a corroborating code-review artifact under
// docs/ai/{reviews,reports}/ whose filename contains the doc id, per the naming
// convention `docs/ai/{reviews,reports}/*<ID>*`. Boundary-aware: the id must not be
// immediately flanked by an ADDITIONAL digit, so a shorter id (e.g. SPEC-001) is not
// falsely corroborated by an artifact named for a longer sibling (e.g. SPEC-0011) —
// mirroring the `id + '/'` roll-up boundary discipline used elsewhere in the engine.
function reviewArtifactExists(root, id) {
  const esc = String(id).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(?<![0-9])${esc}(?![0-9])`);
  for (const sub of ['reviews', 'reports']) {
    const dir = path.join(root, 'docs/ai', sub);
    if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) continue;
    for (const name of fs.readdirSync(dir)) {
      if (re.test(name)) return true;
    }
  }
  return false;
}

// SPEC-0011 G3 — is a `Review-By: code-review` claim on `id` corroborated by an
// event (code_review_completed, or work_item_closed with code_review ~ /^pass/i)
// whose ref equals or rolls up to the id, OR by a review/report artifact?
function reviewClaimBacked(events, id, root) {
  const refMatch = (ref) => String(ref) === id || String(ref).startsWith(id + '/');
  const byEvent = events.some(e => {
    if (!refMatch(e.ref)) return false;
    if (e.event === 'code_review_completed') return true;
    if (e.event === 'work_item_closed') {
      const cr = e.payload?.code_review;
      return typeof cr === 'string' && /^pass/i.test(cr);
    }
    return false;
  });
  return byEvent || reviewArtifactExists(root, id);
}

// --- scan -------------------------------------------------------------------

export function scanAuditDocs(root, { scopePath = null, scanExclude = [] } = {}) {
  const found = [];
  const base = path.join(root, SCAN_ROOT);
  const visit = (dir, depth) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (depth === 0 && entry.isDirectory() && EXCLUDE_DIRS.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      // SPEC-0007 WARNING-1 — normalize to POSIX forward-slash separators so that
      // scanExclude glob matching (POSIX) and the Orphans section of docs/INDEX.md
      // carry forward-slash paths on every OS (no backslashes on Windows).
      const rel = toPosix(path.relative(root, full));
      if (scanExclude.some(g => rel === g || rel.startsWith(g.replace(/\/+$/, '') + '/'))) continue;
      if (entry.isDirectory()) { visit(full, depth + 1); continue; }
      if (!entry.name.endsWith('.md') || entry.name === 'INDEX.md') continue;
      const m = entry.name.match(ID_FILE_RE);
      // RFC-0003 / SPEC-0002: canonical docs are named <domain>.md (no ID
      // prefix); they carry their id in frontmatter and must still be scanned
      // so their canonical-provenance schema is validated. Their fileId is
      // derived from the frontmatter id at parse time.
      // rel is POSIX-normalized (SPEC-0007 WARNING-1), so compare against a
      // POSIX literal — path.join(...)+path.sep would be backslash on Windows
      // and never match the forward-slash rel, dropping canonical docs there.
      const inCanonical = rel.startsWith('docs/canonical/');
      // CHANGE-0012 D3: DRAFT basenames join the scan set so `--gate <slug>`
      // can resolve them and `--check --strict --path <DRAFT>` is non-vacuous.
      const isDraft = !m && DRAFT_FILE_RE.test(entry.name);
      if (!m && !isDraft && !inCanonical) continue;
      if (scopePath) {
        const scope = toPosix(path.relative(root, path.resolve(root, scopePath)));
        if (rel !== scope && !rel.startsWith(scope.replace(/\/+$/, '') + '/')) continue;
      }
      found.push({ rel, fileId: m ? m[1] : null });
    }
  };
  visit(base, 0);
  return found.sort((a, b) => a.rel.localeCompare(b.rel));
}

// --- backlog cross-check (read-only) -----------------------------------------

function backlogDoneClaims(root, globs, knownIds) {
  const claims = new Set();
  for (const g of globs) {
    const p = path.join(root, g);
    if (!fs.existsSync(p) || !fs.statSync(p).isFile()) continue;
    for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
      if (!/✅|\bDone\b/i.test(line)) continue;
      for (const id of knownIds) {
        if (line.includes(id)) claims.add(id);
      }
    }
  }
  return claims;
}

// --- classification + drift ---------------------------------------------------

function daysBetween(fromYmd, toDate) {
  const d = parseISODate(fromYmd);
  if (!d || d.invalid) return null;
  return Math.floor((toDate.getTime() - d.getTime()) / 86400000);
}

function rowHasEvidence(row) {
  const e = (row['Evidence'] ?? '').trim();
  return e !== '' && e !== '—' && e !== '-';
}

// SPEC-0006 Spec-AC-06 — scan a doc body for an open-decision marker OUTSIDE
// fenced code blocks. Returns { marker, line } (1-based) for the first hit, or
// null. Fenced ``` / ~~~ regions are skipped so inline examples never trip it.
export function findOpenDecisionMarker(content) {
  const lines = String(content ?? '').split('\n');
  let inFence = false;
  let fenceCh = null;
  let calloutActive = false;
  for (let i = 0; i < lines.length; i += 1) {
    const raw = lines[i];
    const fence = raw.match(/^\s*(```|~~~)/);
    if (fence) {
      const ch = fence[1][0];
      if (!inFence) { inFence = true; fenceCh = ch; }
      else if (raw.trim()[0] === fenceCh) { inFence = false; fenceCh = null; }
      continue;
    }
    if (inFence) continue;

    // Strip inline code spans before any pattern test so markers that appear
    // only inside backticks (documentation examples, not real callouts) are not
    // matched. Fenced-code-block awareness is handled above; this covers the
    // single-line inline case.
    const stripped = raw.replace(/`[^`\n]*`/g, '');

    if (OPEN_DECISION_COMMENT_RE.test(stripped)) return { marker: 'OPEN-DECISION marker', line: i + 1 };

    // Track a `> [!WARNING]` callout: its contiguous blockquote lines are a
    // warning context too (the token may sit on a following quoted line).
    const isCalloutHeader = /^\s*>\s*\[!WARNING\]/i.test(raw);
    const isBlockquote = /^\s*>/.test(raw);
    if (isCalloutHeader) calloutActive = true;
    else if (calloutActive && !isBlockquote) calloutActive = false;

    const inWarning = /\bWARNING\b/.test(stripped) || (calloutActive && isBlockquote);
    if (inWarning && OPEN_DECISION_TOKEN_RE.test(stripped)) {
      return { marker: 'WARNING with open-decision token', line: i + 1 };
    }
  }
  return null;
}

// --- body lint (SPEC-0013 H1 / D1-D2) -----------------------------------------
// Three conservative rules over the body AFTER the frontmatter block. Fenced
// code blocks and inline code spans are NEVER flagged (the CHANGE-0007 intake
// itself carries `</content>` in inline code — mandatory negative control).
// Fence model (D1, CommonMark-aligned, conservative): a fence opens at a line
// starting (after optional whitespace) with N >= 3 backticks or tildes; it
// closes only at a fence-chars-only line of >= N of the SAME character. Nested
// shorter fences inside an open fence are content, not fences. Two SPEC-0013
// review-W3 refinements: a line-initial backtick run with another backtick on
// the same line is an inline span, not a fence (backtick info strings may not
// contain backticks), and inline code spans may cross line breaks within a
// paragraph (minimal multi-line pairing; the span interior is never flagged).

const STRAY_MARKUP_RE = /<\/content>|<content>|<\/invoke>|<invoke |<result>|<\/result>|<function_results>|<\/function_results>|<parameter /i;
// (a) unfilled ID residue (literal X's): SPEC-XXXX, PRD-XXXX, ...
const PLACEHOLDER_ID_RE = /\b[A-Z]{2,}-X{4,}\b/;
// (b) literal all-caps angle token: <PLACEHOLDER>, <TODO_FILL>. Mixed-case /
// prose angle text (`<why isolation is or is not useful>`) is intentionally
// NOT flagged — false-positive posture wins (D1).
const PLACEHOLDER_ANGLE_RE = /<[A-Z][A-Z0-9_]{2,}>/;

// All backtick runs in a string, with positions and lengths.
function backtickRuns(s) {
  const runs = [];
  const re = /`+/g;
  let m;
  while ((m = re.exec(s)) !== null) runs.push({ start: m.index, end: m.index + m[0].length, len: m[0].length });
  return runs;
}

// Mask inline code spans in a single line, CommonMark-style: a run of N
// backticks opens a span closed by the NEXT run of exactly N backticks; the
// span content (and its delimiters) is blanked. Unpaired runs stay literal, so
// a lone ``` in prose cannot mis-pair with a later single-backtick span.
function maskInlineCode(line) {
  const runs = backtickRuns(line);
  if (runs.length < 2) return line;
  const chars = line.split('');
  let i = 0;
  while (i < runs.length) {
    let j = i + 1;
    while (j < runs.length && runs[j].len !== runs[i].len) j += 1;
    if (j < runs.length) {
      for (let k = runs[i].start; k < runs[j].end; k += 1) chars[k] = ' ';
      i = j + 1;
    } else {
      i += 1;
    }
  }
  return chars.join('');
}

// Lint one doc's content. Returns [{ rule, line, detail }] with 1-based line
// numbers over the ORIGINAL file (frontmatter included in the numbering, never
// in the linted range). Pure function — no filesystem, no git.
export function lintBody(content) {
  const lines = String(content ?? '').split(/\r\n|\r|\n/);
  // skip the frontmatter block if present (parseFrontmatter contract: opening
  // '---' on line 1, closing line starting with '---')
  let start = 0;
  if (lines[0] === '---') {
    for (let i = 1; i < lines.length; i += 1) {
      if (lines[i].startsWith('---')) { start = i + 1; break; }
    }
  }
  const findings = [];
  const lintMaskedLine = (masked, idx) => {
    const stray = masked.match(STRAY_MARKUP_RE);
    if (stray) findings.push({ rule: 'stray-tool-markup', line: idx + 1, detail: `stray tool markup "${stray[0]}"` });
    const phId = masked.match(PLACEHOLDER_ID_RE);
    if (phId) findings.push({ rule: 'template-placeholder', line: idx + 1, detail: `unfilled template id "${phId[0]}"` });
    const phAngle = masked.match(PLACEHOLDER_ANGLE_RE);
    if (phAngle) findings.push({ rule: 'template-placeholder', line: idx + 1, detail: `template placeholder token "${phAngle[0]}"` });
  };
  let fence = null;   // { ch, len, line }
  for (let i = start; i < lines.length; i += 1) {
    const raw = lines[i];
    const f = raw.match(/^\s*(`{3,}|~{3,})/);
    // SPEC-0013 W3b (CommonMark): a backtick fence's info string may not
    // contain backticks, so a line-initial backtick run followed by ANOTHER
    // backtick on the SAME line (e.g. ``` x ``` as a 3-run code span) is
    // inline code, not a fence open — fall through to ordinary masking
    // instead of opening a phantom fence that swallows the rest of the doc.
    // Only an OPENING candidate gets this treatment; inside an open fence
    // every line is content. Tilde fences are unaffected (their info strings
    // may contain backticks and they never close on the opening line).
    const isInlineSpanNotFence = f && !fence && f[1][0] === '`' && raw.slice(f[0].length).includes('`');
    if (f && !isInlineSpanNotFence) {
      const ch = f[1][0];
      const len = f[1].length;
      if (!fence) {
        fence = { ch, len, line: i + 1 };
        continue;   // opening fence line (incl. info string) is never linted
      }
      // closes only at a fence-chars-only line of >= N of the SAME character
      const closing = raw.trim();
      const fenceCharsOnly = closing.split('').every(c => c === ch);
      if (ch === fence.ch && len >= fence.len && fenceCharsOnly) {
        fence = null;
      }
      continue;   // any fence-looking line inside a fence is content
    }
    if (fence) continue;
    const masked = maskInlineCode(raw);
    // SPEC-0013 W3a: minimal multi-line inline-span pairing. CommonMark code
    // spans may cross line breaks within a paragraph; per-line masking cannot
    // see them. If an UNPAIRED run survives single-line masking, look ahead
    // for a run of exactly the same length later in the SAME paragraph (no
    // blank line, no fence-shaped line in between). When found, everything
    // from the opener to that closer is span content: lint only the text
    // before the opener and after the closer (D1 conservative posture — the
    // interior is NEVER flagged).
    const leftover = backtickRuns(masked);
    if (leftover.length > 0) {
      const open = leftover[leftover.length - 1];
      let closeAt = -1;
      let closeRun = null;
      for (let j = i + 1; j < lines.length; j += 1) {
        const look = lines[j];
        if (look.trim() === '') break;               // spans cannot cross blank lines
        if (/^\s*(`{3,}|~{3,})/.test(look)) break;   // fence-shaped boundary — stay conservative
        const r = backtickRuns(look).find((x) => x.len === open.len);
        if (r) { closeAt = j; closeRun = r; break; }
      }
      if (closeAt !== -1) {
        lintMaskedLine(masked.slice(0, open.start), i);
        const rest = ' '.repeat(closeRun.end) + lines[closeAt].slice(closeRun.end);
        lintMaskedLine(maskInlineCode(rest), closeAt);
        i = closeAt;   // interior lines are span content — skipped entirely
        continue;
      }
    }
    lintMaskedLine(masked, i);
  }
  if (fence) {
    findings.push({ rule: 'unbalanced-fence', line: fence.line, detail: `fence opened here (${fence.ch.repeat(fence.len)}) is still open at EOF` });
  }
  return findings;
}

export function runAudit(root, { quick = false, scopePath = null, today = new Date(), strict = false, strictTypes = false } = {}) {
  const config = loadConfig(root);
  const mode = quick ? 'quick' : ((config || strict) ? 'enforced' : 'report-only');
  const staleDays = config?.stale_after_days ?? DEFAULT_STALE_DAYS;
  const legacyUntil = config?.legacy_until_date ?? null;
  const todayUTC = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));

  const files = scanAuditDocs(root, { scopePath, scanExclude: config?.scan_exclude ?? [] });
  const events = quick ? [] : readEvents(root);
  const categoryPrefixes = config?.category_prefixes ?? DEFAULT_CATEGORY_PREFIXES;
  const extraMethods = config?.review_by_methods ?? [];
  const planMode = config?.plan_scan_mode ?? 'lenient';
  const docs = [];
  const violations = [];
  const typeWarnings = [];
  const annotations = [];
  const openDecisionDoneDocs = [];   // SPEC-0006 Spec-AC-06 (report-only)
  const nearMissWarnings = [];       // SPEC-0011 G4 (report-only)
  const reviewClaimUnbacked = [];    // SPEC-0011 G3 (report-only)
  const missingCloseTelemetry = [];  // SPEC-0011 G2 (report-only)
  const bodyLint = [];               // SPEC-0013 H1 (report-only; --strict promotes)
  // RFC-0011 (delta-spec lifecycle) D3 — canonical-provenance drift. Collected
  // per canonical doc during the scan, resolved in a post-pass once every
  // scanned id is known. NO-OP when there are no canonical docs (this repo's
  // live state) — contributes nothing, no false positive.
  const canonicalTrace = [];         // [{ rel, id, requirements: [{ id, provenance }] }]

  for (const f of files) {
    const content = fs.readFileSync(path.join(root, f.rel), 'utf8');
    const fm = parseFrontmatter(content);
    const ac = parseAcTable(content);
    // SPEC-0011 G4 — near-miss AC table detection (report-only; NEVER hardFail).
    // Attached to the doc record and aggregated; consumed by docs-audit.mjs and
    // (independently recomputed) by generate-docs-index.mjs.
    const nearMiss = detectNearMissAcTable(content).warnings;
    // filename-derived primary/related/scope (CHANGE-0002 D14/D15)
    const ids = extractDocIds(path.basename(f.rel), categoryPrefixes) ?? { primary: f.fileId, related: [], scope: null };
    const id = fm?.id ?? ids.primary;
    const doc = {
      rel: f.rel, id, fileId: ids.primary, relatedIds: ids.related, scope: ids.scope,
      fm, ac, cls: null, verdict: null, reasons: [], legacy: false, nearMiss,
    };
    docs.push(doc);
    if (nearMiss.length) nearMissWarnings.push({ id, rel: f.rel, warnings: nearMiss });

    // SPEC-0013 H1 — body lint over the governed scan set, further excluding
    // docs/plans/ under plan_scan_mode: lenient (operator notes, not authored
    // content). Report-only in the digest; counts toward hardFail ONLY under
    // the explicit --strict flag (D2 — never in config-enforced mode alone).
    if (!(planMode === 'lenient' && f.rel.startsWith('docs/plans/'))) {
      for (const bl of lintBody(content)) {
        bodyLint.push({ rel: f.rel, id, rule: bl.rule, line: bl.line, detail: bl.detail });
      }
    }

    // legacy/new split (D4): first-commit date vs legacy_until_date; untracked => new
    if (!quick && legacyUntil) {
      const first = firstCommitDate(root, f.rel);
      doc.firstCommit = first;
      doc.legacy = first != null && first < legacyUntil;
    } else if (quick || !legacyUntil) {
      // report-only / quick: nothing hard-fails; strict (intake post-save
      // check) treats every doc as new even without a config
      doc.legacy = !strict;
      doc.softLegacy = !strict;
    }

    if (!fm || !fm.id || !fm.status) {
      // operator plan files are work-tracking artifacts, not authored content
      // needing canonical schema (CHANGE-0002 D12)
      if (planMode === 'lenient' && f.rel.startsWith('docs/plans/')) {
        doc.cls = 'tracked-open';
        doc.verdict = 'aligned';
        doc.reasons.push('operator plan file (plan_scan_mode: lenient)');
        continue;
      }
      doc.cls = 'orphan';
      doc.reasons.push(!fm ? 'no frontmatter' : `missing ${!fm.id ? 'id' : 'status'} in frontmatter`);
      continue;
    }
    const status = String(fm.status).toLowerCase();
    if (!DOC_STATUS_ENUM.has(status)) {
      doc.cls = 'orphan';
      doc.reasons.push(`unknown status "${fm.status}"`);
      violations.push({ rel: f.rel, msg: `unknown frontmatter status "${fm.status}"` });
      continue;
    }
    for (const row of ac.rows) {
      // SPEC-0010 Group C (ISSUE-0005) — same shared normalizer as the generator,
      // so a qualified `<canonical> (<qualifier>)` is accepted (base status carried
      // on the row) and only a genuinely-invalid status is a violation.
      const rawStatus = row['Status'] ?? '';
      const norm = normalizeAcStatus(rawStatus);
      row._baseStatus = norm.status;
      if (rawStatus.trim() && !norm.canonical) violations.push({ rel: f.rel, msg: `unknown AC status "${rawStatus}" for ${row['Spec-AC']}` });
      const rb = parseReviewBy(row['Review-By'], extraMethods);
      if (rb.kind === 'invalid') violations.push({ rel: f.rel, msg: `invalid Review-By "${rb.raw}" for ${row['Spec-AC']} (ISO date, skill label, label:date, or "<actor> <method>")` });
    }
    doc.status = status;

    // SPEC-0011 G3 — Review-By truthfulness cross-check (report-only; NEVER
    // hardFail). For any AC row whose Review-By label is `code-review`, require a
    // corroborating review event OR a docs/ai/{reviews,reports}/*<id>* artifact;
    // absent all corroboration → verdict `review-claim-unbacked`. Skipped in quick
    // mode (no EVENTS read). Cross-checked regardless of the row's own status.
    if (!quick) {
      let backed = null;   // computed lazily, once per doc
      for (const row of ac.rows) {
        const rb = parseReviewBy(row['Review-By'], extraMethods);
        if (rb.label && rb.label.toLowerCase() === 'code-review') {
          if (backed === null) backed = reviewClaimBacked(events, id, root);
          if (!backed) {
            reviewClaimUnbacked.push({ id, rel: f.rel, specAc: row['Spec-AC'], reviewBy: row['Review-By'], verdict: 'review-claim-unbacked' });
          }
        }
      }
    }

    // SPEC-0011 G2 — telemetry-at-close (report-only; NEVER hardFail). A
    // `status: done` doc with NO `work_item_closed` event whose ref equals the id
    // (or rolls up id/<suffix>, mirroring the ac_evidence roll-up) is surfaced as
    // `missing-close-telemetry`. Skipped in quick mode (no EVENTS read).
    if (status === 'done' && !quick) {
      const hasClose = events.some(e => e.event === 'work_item_closed'
        && (String(e.ref) === id || String(e.ref).startsWith(id + '/')));
      if (!hasClose) missingCloseTelemetry.push({ id, rel: f.rel });
    }

    // SPEC-0006 Spec-AC-06 — READ-ONLY: a done doc carrying a buried open-decision
    // marker (outside fenced code). Surfaced in its own digest section; NEVER
    // feeds hardFail/needsTriage or any exit code (RFC-0001 mechanism-over-
    // discipline: gated/indexed, not a hard gate until the signal is proven clean).
    if (status === 'done') {
      const od = findOpenDecisionMarker(content);
      if (od) openDecisionDoneDocs.push({ id, rel: f.rel, marker: od.marker, line: od.line });
    }

    // type validation (CHANGE-0001 D7): soft warning, hard with --strict-types
    if (fm.type && !DOC_TYPE_ENUM.has(String(fm.type).toLowerCase())) {
      const msg = `unknown type "${fm.type}" (allowed: ${[...DOC_TYPE_ENUM].join(', ')})`;
      typeWarnings.push({ rel: f.rel, id, msg });
      if (strictTypes) violations.push({ rel: f.rel, msg });
    }

    // canonical provenance validation (RFC-0003 / SPEC-0002 Spec-AC-02):
    // a canonical doc must carry a valid domain slug + non-empty sources list.
    // These are hard schema violations (count toward hardFail under --strict).
    if (String(fm.type ?? '').toLowerCase() === 'canonical') {
      const v = validateCanonicalFrontmatter(fm);
      for (const msg of v.violations) {
        violations.push({ rel: f.rel, msg: `canonical frontmatter: ${msg}` });
      }
      // RFC-0011 D3 — harvest this canonical doc's requirement provenance for
      // the post-scan drift resolution. parseRequirementsSection is the shared
      // reader (D5 — no grammar re-expressed).
      const req = parseRequirementsSection(content);
      if (req.present && req.requirements.length) {
        canonicalTrace.push({
          id, rel: f.rel,
          requirements: req.requirements.map(r => ({ id: r.id, provenance: r.provenance })),
        });
      }
    }

    // amendment annotations (CHANGE-0001 D3): recognized sibling fields
    for (const key of ['amendment_note', 'amended_by', 'superseded_by']) {
      if (fm[key]) annotations.push({ id, rel: f.rel, key, value: fm[key] });
    }

    if (status === 'superseded' || status === 'rejected') { doc.cls = 'superseded'; continue; }

    // CHANGE-0027 / SPEC-0039 — false-open drift heuristic. Runs BEFORE the
    // frozen-marker early exit (D6 — a frozen-in-body draft is still checked)
    // and BEFORE the stale-open branch below (D5 — a doc that is both stale
    // and delivery-evidenced upgrades to the more actionable
    // probable-false-open). Skipped entirely in --quick (D7 — no git/EVENTS
    // probes). A doc without delivery evidence falls through unchanged.
    if (FALSE_OPEN_STATUSES.has(status) && !quick) {
      const fo = falseOpenEvidence(root, doc, events);
      if (fo.evidenced) {
        doc.verdict = 'probable-false-open';
        doc.reasons.push(...fo.reasons);
        doc.cls = 'drifted';
        continue;
      }
    }

    // legacy frozen-in-body marker (CHANGE-0001 D2): a draft doc carrying
    // SPEC-FROZEN: true is effectively frozen, not a stale-open candidate
    if (status === 'draft' && specFrozenInBody(content)) {
      doc.effectiveStatus = 'frozen';
      doc.reasons.push('SPEC-FROZEN marker in body');
      doc.verdict = 'aligned';
      doc.cls = 'tracked-open';
      continue;
    }

    // drift heuristics (deliverable 2)
    const type = (fm.type ?? '').toLowerCase();
    if (status === 'done') {
      // SPEC-0010 Group C — classify by the normalized BASE status so a qualified
      // `done (pre-existing)` counts as terminal `done`, aligned with the generator.
      const baseOf = (r) => r._baseStatus ?? (r['Status'] ?? '').toLowerCase();
      const nonTerminal = ac.rows.filter(r => !TERMINAL_AC.has(baseOf(r)));
      const doneNoEvidence = ac.rows.filter(r => baseOf(r) === 'done' && !rowHasEvidence(r));
      if (ac.hasGate && (nonTerminal.length || doneNoEvidence.length)) {
        doc.verdict = 'probable-false-done';
        if (nonTerminal.length) doc.reasons.push(`${nonTerminal.length} AC row(s) non-terminal`);
        if (doneNoEvidence.length) doc.reasons.push(`${doneNoEvidence.length} done AC row(s) without evidence`);
      } else if (!ac.hasGate && type === 'spec') {
        // spec-l1-close-gate D3 — a validly declared ceremony_level 0/1 spec
        // closes on the lean shape (mirrors gateContent exactly): lean AC
        // table (Spec-AC + Status) with terminal rows + the `Ceremony
        // justification: ` line. Anything else (incl. garbage levels —
        // fail-closed) keeps the legacy probable-partial verdict.
        const clRaw = fm.ceremony_level;
        const lean = isLeanCeremonyLevel(clRaw) ? parseLeanAcTable(content) : null;
        if (!isLeanCeremonyLevel(clRaw)) {
          doc.verdict = 'probable-partial';
          doc.reasons.push('status done but mandated AC Status table is absent');
        } else if (!lean.hasLean || lean.rows.length === 0) {
          doc.verdict = 'probable-partial';
          doc.reasons.push(`status done but the ceremony_level ${clRaw} lean AC table (Spec-AC + Status columns) is absent`);
        } else if (!CEREMONY_JUSTIFICATION_RE.test(content)) {
          doc.verdict = 'probable-partial';
          doc.reasons.push(`status done but the ceremony_level ${clRaw} "Ceremony justification: ..." body line is absent`);
        } else {
          // D3 — mirror the gate's silent-drop reconciliation: an unparseable
          // declared row (literal pipe) hides its own status, so a done spec
          // carrying one cannot be trusted done (probable-false-done), exactly
          // as the close gate refuses to pass it.
          const unparseable = unparseableLeanIds(lean);
          const leanNonTerminal = lean.rows.filter(r => !TERMINAL_AC.has(normalizeAcStatus(r['Status'] ?? '').status));
          if (unparseable.length) {
            doc.verdict = 'probable-false-done';
            doc.reasons.push(`${unparseable.length} lean AC row(s) unparseable (${unparseable.join(', ')} — a literal "|" in a cell hides the row's status)`);
          }
          if (leanNonTerminal.length) {
            doc.verdict = 'probable-false-done';
            doc.reasons.push(`${leanNonTerminal.length} lean AC row(s) non-terminal`);
          }
          // all lean rows terminal, parseable + justified: aligned (tracked-done below)
        }
      } else if (!ac.hasGate && !quick) {
        const hasCommit = lastIdMentionDate(root, id) != null;
        // PARENT-ID/sub-item refs roll up to the parent, but sibling IDs
        // (CHANGE-0045 vs CHANGE-004) must not cross-match (CHANGE-0002 D11)
        const hasEvidence = events.some(e => e.event === 'ac_evidence'
          && (String(e.ref) === id || String(e.ref).startsWith(id + '/')));
        if (!hasCommit && !hasEvidence) {
          doc.verdict = 'probable-false-done';
          doc.reasons.push('no commit and no ac_evidence event references this doc');
        }
      }
    } else if (OPEN_STATUSES.has(status) && !quick) {
      const lastEdit = lastEditDate(root, f.rel);
      const lastMention = lastIdMentionDate(root, id);
      const editAge = lastEdit ? daysBetween(lastEdit, todayUTC) : null;
      const mentionAge = lastMention ? daysBetween(lastMention, todayUTC) : null;
      if (editAge != null && editAge > staleDays && (mentionAge == null || mentionAge > staleDays)) {
        doc.verdict = 'probable-stale-open';
        doc.reasons.push(`status ${status}, last edit ${lastEdit}, last DOC-ID commit ${lastMention ?? 'never'} (> ${staleDays}d)`);
      }
    }
    if (doc.verdict) { doc.cls = 'drifted'; continue; }
    doc.verdict = 'aligned';

    if (status === 'done') { doc.cls = 'tracked-done'; continue; }

    // obsolete: deferred with every Review-By overdue, or inactive legacy doc
    if (status === 'deferred') {
      const reviewDates = ac.rows.map(r => parseReviewBy(r['Review-By']).date).filter(d => d instanceof Date);
      if (reviewDates.length && reviewDates.every(d => d < todayUTC)) {
        doc.cls = 'obsolete';
        doc.reasons.push('deferred with all Review-By dates overdue');
        continue;
      }
    }
    doc.cls = 'tracked-open';
  }

  // backlog cross-check (read-only, strengthens false-done)
  if (!quick && config?.backlog_globs?.length) {
    const claims = backlogDoneClaims(root, config.backlog_globs, docs.map(d => d.id));
    for (const d of docs) {
      if (claims.has(d.id) && d.cls !== 'tracked-done' && d.cls !== 'superseded') {
        if (d.verdict === 'aligned') d.verdict = 'probable-false-done';
        if (d.cls === 'tracked-open' || d.cls === 'obsolete') d.cls = 'drifted';
        d.reasons.push('backlog row claims Done but doc state disagrees');
      }
    }
  }

  // closeout-candidate detection (SPEC-0003 / CHANGE-0004): READ-ONLY post-pass.
  // Surface every non-terminal rfc/prd parent whose every resolved linked spec
  // is `done`, so an operator can close the parent. Reuses the in-memory docs[]
  // id index and asList() — no second scan. NOT part of hardFail/needsTriage.
  const closeoutCandidates = closeoutCandidatesFor(docs);

  // pending-commit notice (CHANGE-0001 D6): the verdict already reflects the
  // working tree; this only tells the operator which scanned docs differ from git
  let pendingCommit = [];
  if (!quick) {
    const porcelain = git(root, 'status --porcelain -- docs');
    if (porcelain) {
      const dirty = new Set(porcelain.split('\n').map(l => l.slice(3).trim()).filter(Boolean));
      pendingCommit = docs.filter(d => dirty.has(d.rel)).map(d => d.rel);
    }
  }

  // RFC-0011 D3 — resolve canonical-provenance drift now that every scanned id
  // is known. A requirement with an empty/null Provenance is untraced; one
  // naming a spec id that resolves to no scanned doc is broken. When there are
  // no canonical docs this loop is empty — the check contributes nothing.
  const provenanceDrift = [];
  if (canonicalTrace.length) {
    const knownIds = new Set();
    for (const d of docs) {
      for (const k of [d.id, d.fileId, ...(d.relatedIds ?? [])]) {
        if (k) knownIds.add(String(k));
      }
    }
    for (const c of canonicalTrace) {
      for (const r of c.requirements) {
        if (r.provenance == null) {
          provenanceDrift.push({ rel: c.rel, id: c.id, reqId: r.id, kind: 'untraced-canonical-requirement', detail: 'empty Provenance (never merged from a spec)' });
        } else if (!knownIds.has(String(r.provenance))) {
          provenanceDrift.push({ rel: c.rel, id: c.id, reqId: r.id, kind: 'broken-canonical-provenance', detail: `Provenance "${r.provenance}" resolves to no scanned doc` });
        }
      }
    }
  }

  const orphans = docs.filter(d => d.cls === 'orphan');
  const orphansNew = orphans.filter(d => !d.legacy);
  const orphansLegacy = orphans.filter(d => d.legacy);
  const drift = docs.filter(d => d.cls === 'drifted');
  const planLenient = docs.filter(d => d.reasons.some(r => r.startsWith('operator plan file')));
  const counts = {
    total: docs.length,
    orphans: orphans.length,
    orphansNew: orphansNew.length,
    drifted: drift.length,
    stale: drift.filter(d => d.verdict === 'probable-stale-open').length,
    falseOpen: drift.filter(d => d.verdict === 'probable-false-open').length,
    obsolete: docs.filter(d => d.cls === 'obsolete').length,
    trackedOpen: docs.filter(d => d.cls === 'tracked-open').length,
    trackedDone: docs.filter(d => d.cls === 'tracked-done').length,
    superseded: docs.filter(d => d.cls === 'superseded').length,
    violations: violations.length,
    typeWarnings: typeWarnings.length,
    closeoutCandidates: closeoutCandidates.length,
    openDecisionDone: openDecisionDoneDocs.length,
    nearMiss: nearMissWarnings.length,
    reviewClaimUnbacked: reviewClaimUnbacked.length,
    missingCloseTelemetry: missingCloseTelemetry.length,
    bodyLint: bodyLint.length,
    provenanceDrift: provenanceDrift.length,
  };
  // SPEC-0011 G2/G3/G4 signals (nearMissWarnings, reviewClaimUnbacked,
  // missingCloseTelemetry) are deliberately ABSENT from hardFail AND from the
  // NEEDS-TRIAGE tally — report-only, preserving the RFC-0002 report-not-block
  // posture (the audit REPORTS; the operator DECIDES).
  // SPEC-0013 H1 (D2): body lint promotes to hardFail ONLY under the explicit
  // --strict flag (the intake POST-SAVE path) — never in config-enforced mode
  // alone, so mid-migration repos with legacy bodies keep a passing --check.
  // RFC-0011 D3 — canonical-provenance drift is a hard governance gate: it
  // fails --check in enforced OR --strict mode (mirroring the violations gate),
  // and stays a report-only digest signal otherwise. Empty canonical => zero
  // findings => no effect (this repo stays CLEAN).
  const hardFail = (mode === 'enforced' && (orphansNew.length > 0 || violations.length > 0))
    || (strict && bodyLint.length > 0)
    || ((mode === 'enforced' || strict) && provenanceDrift.length > 0);

  return {
    mode, config, docs, orphansNew, orphansLegacy, drift, violations,
    typeWarnings, annotations, pendingCommit, planLenient, closeoutCandidates,
    openDecisionDoneDocs, nearMissWarnings, reviewClaimUnbacked,
    missingCloseTelemetry, bodyLint, provenanceDrift, counts, hardFail,
  };
}

// Resolve non-terminal rfc/prd parents whose every linked spec is done.
// Returns [{ id, rel, type, status, specs: [doneSpecId...], suggestedStep }].
// Linked-spec resolution = forward asList(links.spec) UNION reverse links
// (a scanned spec whose links.rfc / links.requirement names the parent). A
// parent is flagged iff it resolves >= 1 spec AND every resolved spec id maps to
// a scanned doc with status `done` (an unresolvable id => not flagged).
export function closeoutCandidatesFor(docs) {
  const byId = new Map();
  for (const d of docs) { if (d.id) byId.set(d.id, d); }
  const docType = (d) => String(d.fm?.type ?? '').toLowerCase();
  const out = [];
  for (const parent of docs) {
    if (!CLOSEOUT_PARENT_TYPES.has(docType(parent))) continue;
    if (!CLOSEOUT_PARENT_STATUSES.has(parent.status)) continue;
    const specIds = new Set(asList(parent.fm?.links?.spec));
    for (const d of docs) {
      if (docType(d) !== 'spec' || !d.id) continue;
      const reverse = [...asList(d.fm?.links?.rfc), ...asList(d.fm?.links?.requirement)];
      if (reverse.includes(parent.id)) specIds.add(d.id);
    }
    if (specIds.size === 0) continue;
    const resolved = [...specIds].map(sid => byId.get(sid));
    // Every resolved id must be an actual spec that is done. A forward
    // links.spec that names a non-spec (e.g. a done CHANGE) or an unresolvable
    // id does not count as "all linked specs done" (guards a misfiled link).
    if (resolved.some(r => !r || docType(r) !== 'spec' || r.status !== 'done')) continue;
    out.push({
      id: parent.id,
      rel: parent.rel,
      type: docType(parent),
      status: parent.status,
      specs: [...specIds].sort(),
      suggestedStep: `advance ${parent.id} to done/accepted; record the implementing commit`,
    });
  }
  return out.sort((a, b) => a.id.localeCompare(b.id));
}

// SPEC-0011 G1 — offline structural close-time gate for ONE doc. Resolves docId
// against the scanned docs (frontmatter id or filename id) and returns
// { found, ok, reasons }. FAILS (ok:false) when the doc has no canonical AC
// Status gate table, any AC row is non-terminal, any done row lacks Evidence, or
// any Review-By token is schema-invalid. Purely on-disk (no git/event probing),
// so it is deterministic and testable. Reuses the shared parsers — no fork.
// Shared structural gate over already-read doc CONTENT (no filesystem/id
// resolution). Reused by both gateDoc (resolve-by-id, worktree file) and gateFile
// (an explicit file path — e.g. a materialized STAGED blob) so the two entry points
// apply byte-identical gate logic to whatever content they were handed.
function gateContent(content, extraMethods) {
  const ac = parseAcTable(content);
  const reasons = [];
  // RFC-0009 / spec-scale-adaptive-ceremony — ceremony-level close checks.
  // The enum lives in SPEC frontmatter (a governed docs surface), so its
  // validation belongs HERE, not in check-state (which validates only
  // docs/ai/STATE.yaml structure — STATE never stores the level). An ABSENT
  // field is legacy implicit L2 and is never flagged (zero migration); a YAML
  // `null` counts as absent. Enforcement rides the existing `close_gate` dial
  // (report-only by default) — the dispatch fail-closes independently, so an
  // invalid value can only be reported here, never prune a gate there.
  const fm = parseFrontmatter(content);
  const clRaw = fm ? fm.ceremony_level : undefined;
  if (clRaw !== undefined && clRaw !== null) {
    if (!['0', '1', '2', '3'].includes(String(clRaw))) {
      reasons.push(`schema-invalid ceremony_level "${clRaw}" (allowed: 0 | 1 | 2 | 3)`);
    } else if (isLeanCeremonyLevel(clRaw)
      && !CEREMONY_JUSTIFICATION_RE.test(content)) {
      reasons.push(`ceremony_level ${clRaw} requires a "Ceremony justification: ..." body line (RFC-0009 level-inflation guard)`);
    }
  }
  // Canonical vs lean structural check (spec-l1-close-gate D1/D2). `canonical`
  // = true runs the exact legacy row checks (Review-By always schema-checked,
  // done rows always need Evidence) so every non-lean-eligible doc keeps
  // byte-identical gate reasons. Lean rows check the optional columns only
  // when the table actually carries them.
  const checkRows = (rows, canonical) => {
    for (const row of rows) {
      const specAc = row['Spec-AC'];
      const base = normalizeAcStatus(row['Status'] ?? '').status;
      if (!TERMINAL_AC.has(base)) {
        reasons.push(`${specAc} is non-terminal (status "${row['Status'] ?? ''}")`);
      }
      if (base === 'done' && (canonical || row['Evidence'] !== undefined) && !rowHasEvidence(row)) {
        reasons.push(`${specAc} is done but Evidence is empty`);
      }
      if (canonical || row['Review-By'] !== undefined) {
        const rb = parseReviewBy(row['Review-By'], extraMethods);
        if (rb.kind === 'invalid') {
          reasons.push(`${specAc} has schema-invalid Review-By "${rb.raw}"`);
        }
      }
    }
  };
  if (!isLeanCeremonyLevel(clRaw)) {
    // Legacy path — absent/null/garbage/2/3: unchanged behavior.
    if (!ac.hasGate || ac.rows.length === 0) {
      reasons.push('missing AC Status table');
    } else {
      checkRows(ac.rows, true);
    }
  } else if (ac.hasGate && ac.rows.length > 0) {
    // A lean-eligible doc that volunteers the full canonical table gets the
    // full canonical checks.
    checkRows(ac.rows, true);
  } else {
    const lean = parseLeanAcTable(content);
    if (!lean.hasLean || lean.rows.length === 0) {
      reasons.push(`missing AC table (ceremony_level ${clRaw} lean shape: a "## Acceptance Criteria" table with Spec-AC + Status columns)`);
    } else {
      for (const id of unparseableLeanIds(lean)) {
        reasons.push(`${id} is declared in the AC table but its row did not parse (a literal "|" inside a cell breaks the row — reword to remove pipes)`);
      }
      checkRows(lean.rows, false);
    }
  }
  return { ok: reasons.length === 0, reasons };
}

// CHANGE-0012 D2 — two-pass resolution over the scanned docs (DRAFT basenames
// included per D3): (1) exact frontmatter `id` match (the durable PK per
// SPEC-0015 D2 — covers slug DRAFTs and legacy docs whose frontmatter carries
// `id: TYPE-000N`); (2) only when pass 1 finds nothing, filename-derived
// display-id match. MORE THAN ONE match within a pass is an ERROR (found:false
// => exit 2) listing every candidate path — the old per-file first-match loop
// silently gated whichever file sorted first, i.e. the WRONG doc on an id
// collision.
export function gateDoc(root, docId) {
  const config = loadConfig(root);
  const files = scanAuditDocs(root, { scanExclude: config?.scan_exclude ?? [] });
  const categoryPrefixes = config?.category_prefixes ?? DEFAULT_CATEGORY_PREFIXES;
  const extraMethods = config?.review_by_methods ?? [];
  const entries = files.map(f => {
    const content = fs.readFileSync(path.join(root, f.rel), 'utf8');
    const fm = parseFrontmatter(content);
    const ids = extractDocIds(path.basename(f.rel), categoryPrefixes) ?? { primary: f.fileId };
    return { rel: f.rel, content, fmId: fm?.id ?? null, fileIds: [ids.primary, f.fileId] };
  });
  let pass = 'frontmatter-id';
  let matches = entries.filter(e => e.fmId === docId);
  if (matches.length === 0) {
    pass = 'display-id';
    matches = entries.filter(e => e.fileIds.includes(docId));
  }
  if (matches.length === 0) {
    return { found: false, ok: false, reasons: [`no scanned doc resolves to id "${docId}"`] };
  }
  if (matches.length > 1) {
    return {
      found: false, ok: false,
      reasons: [
        `ambiguous id "${docId}": ${matches.length} scanned docs match in the ${pass} pass — fail-closed, no doc gated`,
        ...matches.map(m => `candidate: ${m.rel}`),
      ],
    };
  }
  const { ok, reasons } = gateContent(matches[0].content, extraMethods);
  return { found: true, ok, reasons };
}

// SPEC-0011 G5 — gate the content of an EXPLICIT file path (not resolved by id).
// The G5 pre-commit hook materializes the STAGED blob (`git show :<path>`) into a
// temp file and gates THAT, so a staged-but-unreconciled `status: done` cannot pass
// merely because the worktree has unstaged Evidence. Config (review_by_methods) is
// still loaded from `root` so a project's configured methods are honored.
export function gateFile(root, filePath) {
  const config = loadConfig(root);
  const extraMethods = config?.review_by_methods ?? [];
  const abs = path.isAbsolute(filePath) ? filePath : path.join(root, filePath);
  if (!fs.existsSync(abs)) return { found: false, ok: false, reasons: [`file not found: "${filePath}"`] };
  const content = fs.readFileSync(abs, 'utf8');
  const { ok, reasons } = gateContent(content, extraMethods);
  return { found: true, ok, reasons };
}

// SPEC-0013 H1 — lint the content of an EXPLICIT file path (not resolved by id),
// mirroring gateFile (SPEC-0011 G5). The pre-commit hook materializes the STAGED
// blob (`git show :<path>`, LEARNED 2026-07-03) into a temp file and lints THAT,
// so a staged-but-dirty body cannot pass merely because the worktree copy was
// fixed after staging. Returns { found, findings }.
export function lintFile(root, filePath) {
  const abs = path.isAbsolute(filePath) ? filePath : path.join(root, filePath);
  if (!fs.existsSync(abs)) return { found: false, findings: [] };
  let content;
  try {
    content = fs.readFileSync(abs, 'utf8');
  } catch {
    return { found: false, findings: [] };
  }
  return { found: true, findings: lintBody(content) };
}

export function suggestedStep(doc) {
  if (doc.cls === 'orphan') return `add frontmatter per .aai/templates (type ${doc.rel.split('/')[1] ?? 'doc'})`;
  switch (doc.verdict) {
    case 'probable-false-done': return 'reconcile AC table / evidence, then re-confirm done status';
    case 'probable-false-open': return 'confirm delivery, then run close ceremony (status flip + links.pr/commits + doc_lifecycle/work_item_closed events)';
    case 'probable-partial': return 'add the Acceptance Criteria Status table, then re-validate';
    case 'probable-stale-open': return 'confirm whether work shipped elsewhere; close or revive';
    default: return doc.cls === 'obsolete' ? 're-decide overdue deferral' : '—';
  }
}
