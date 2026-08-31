#!/usr/bin/env node
//
// close-work-item.mjs — deterministic close-ceremony mechanism
// (CHANGE-0037 / SPEC-0053). Mechanizes the close ceremony that was
// previously 100% agent-improvised prose (.aai/VALIDATION.prompt.md step 8b,
// .aai/SKILL_PR.prompt.md): frontmatter status transition, links.pr/
// links.commits stamping, the complete correctly-reffed close event set, and
// a self-verify against the REAL docs-audit engine with total rollback on
// any drift. See docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md
// for the full design record (D1-D10).
//
// POST-MERGE-CLOSE ADVISORY (role-verification-guards G1): a report-only
// stderr WARNING, printed at most once per invocation, when the delivery
// `--commit` already sits on the resolved upstream default ref — a git
// predicate (`git merge-base --is-ancestor`), never the PR API. Never
// changes the exit code or stdout; fail-open on any git failure.
//
// GRAMMAR (D1, closed; extended fu-close-requires-pr-before-it-exists —
// see the PR-NUMBER SPLIT note below)
//   node .aai/scripts/close-work-item.mjs --ref <slug> --pr <N|TBD> --commit <sha>
//     [--spec <spec-slug>] [--review <pass|waived|none>] [--dry-run]
//   node .aai/scripts/close-work-item.mjs --ref <slug> --stamp-pr <N> [--spec <spec-slug>]
//   --ref <slug>     the primary work-item doc's frontmatter slug `id`
//                     (change/issue/debt/spec). Required.
//   --pr <N|TBD>     PR number stamped into links.pr (integer; required).
//                     The literal sentinel `TBD` (case-insensitive, stored
//                     canonicalized as `TBD`) is accepted for the ordering
//                     paradox described below — it is NEVER a guess.
//   --commit <sha>   delivery commit stamped into links.commits AND used as
//                     the ac_evidence commit (required).
//   --spec <slug>    optional second doc (the spec) closed in the SAME
//                     transaction as the primary doc.
//   --review <t>     the code_review token for work_item_closed; optional,
//                     default "none" (validation is always "pass" — this
//                     ceremony only runs after a PASS).
//   --dry-run        print the planned mutation + event set as JSON, write
//                     nothing, exit 0.
//   --stamp-pr <N>   SEPARATE mode (mutually exclusive with --pr/--commit/
//                     --dry-run): replaces an already-stamped `TBD` in
//                     links.pr with the real integer N, once the PR exists.
//                     See PR-NUMBER SPLIT below.
//
// PR-NUMBER SPLIT (fu-close-before-push-ordering / fu-close-requires-pr-
// before-it-exists, ride ref close-ceremony-ordering): the correct ceremony
// order runs the close BEFORE push (so the framework reds the close itself
// clears are never misread as CI failures — 5 tests/skills/test-framework.sh
// reds were measured to clear ONLY once this script had run), but a PR
// number literally does not exist until AFTER push+PR-open. Guessing it
// (the historical N+1 read of the highest existing number) was luck, not
// procedure, and is not repeated here. Instead the ONE close transaction
// splits into two ordered halves that can never be satisfied out of order:
//   1. THE CLOSE ITSELF (this invocation, `--pr TBD`) — status flip, event
//      set, self-verify — runs BEFORE push, exactly like every other close.
//      `TBD` is stamped into links.pr as a literal, glaringly-incomplete
//      placeholder (never a plausible-looking wrong guess).
//   2. RECORDING WHICH PR CARRIED IT (`--stamp-pr <N>`, run immediately after
//      `gh pr create`/`az repos pr create` returns the real number, same
//      ceremony invocation, .aai/SKILL_PR.prompt.md step 5c) replaces the
//      TBD with N — a narrow, separate, self-verified transaction that never
//      re-runs the status flip or re-emits the close event set.
// A TBD left unstamped is never silent: `main()`'s pre-write phase (see
// scanForStaleTbdPr below) reports every OTHER closed doc still carrying a
// stale TBD as a named stderr WARNING on EVERY future close-work-item.mjs
// invocation in this repo — far more discoverable than a wrong guess, which
// looks correct until someone checks.
//
// RESOLUTION (D2): each slug is resolved against the SAME two-pass scan the
// docs-audit gate uses — exact frontmatter `id` match first, then filename-
// derived display-id fallback. Zero or >1 matches is a fatal usage error
// (exit 2) naming every candidate — fail-closed, never guess.
//
// STATUS TRANSITION (D3): the doc's ACTUAL on-disk `fm.status` drives the
// transition, never an assumed value (fixes the SPEC-0046 flip-miss class):
//   draft | implementing | accepted -> done (doc_lifecycle --from <ACTUAL>)
//   done                            -> no-op (idempotent, no event)
//   anything else (deferred | rejected | superseded | unknown)
//                                    -> fatal usage error (exit 2); never a
//                                       silent reopen/repurpose.
//
// EVENT SET + REF FORM (D5 — the crux correctness property): every emitted
// event uses the doc's resolved SLUG `id` as --ref (bare, NEVER the numbered
// fileId — docs-audit matches identity on fm.id). Ordering is status-flip
// FIRST (so a still-open doc can never carry work_item_closed and self-flag
// docs-audit's probable-false-open Arm C), then per doc: doc_lifecycle (only
// on a real transition), work_item_closed (deduped on an existing event with
// the same ref), ac_evidence --commit <sha> (deduped on ref+commit; emitted
// for BOTH the primary doc and the paired spec, D5).
//
// TRANSACTION (D6): snapshot every doc file's original bytes + the EVENTS.jsonl
// byte-length -> idempotency short-circuit if nothing would change -> apply
// (frontmatter rewrite for every doc, THEN the event set for every doc) ->
// self-verify (regenerate docs/INDEX.md, run the REAL docs-audit engine,
// assert every closed ref classifies tracked-done/aligned with no
// missing-close-telemetry) -> on any drift, FAIL-CLOSED: restore every
// mutated doc file byte-for-byte, truncate EVENTS.jsonl back to its snapshot
// byte-length, regenerate the INDEX again, print the offending reasons, exit
// non-zero. No half-closed doc is ever left on disk. With --spec, both docs
// are resolved up front (D7): either failing to resolve/transition aborts
// before any write; a self-verify failure rolls BOTH back.
//
// EXIT CONTRACT (D8)
//   0  closed successfully, OR nothing to do (already fully closed).
//   1  self-verify failed after a real close (rolled back), or an unexpected
//      internal error.
//   2  usage error: missing/invalid flag, unresolvable/ambiguous ref, or a
//      non-done-terminal status. Nothing written.
//   3  product-doc gate REFUSED (spec-product-docs-enforced D3): the primary
//      --ref doc's frontmatter carries a truthy `user_visible` and
//      docs/product/<slug>.md is missing/placeholder under a
//      `product_doc_gate: enforce` dial. Evaluated BEFORE any write (never a
//      rollback path) — nothing written. --dry-run never returns 3 (the
//      verdict is reported informationally in its JSON instead).
//   4  usage-capture gate REFUSED (spec-telemetry-completeness, Enforcement
//      design A): the closing ride's STATE agent_runs include a
//      harness-dispatched-role run (Planning, Implementation, TDD
//      Implementation, Validation, Code Review, Remediation) with no
//      usage_total_tokens marker, no decomposed tokens_in/out, and no
//      usage_capture=none sentinel, under a `usage_capture_gate: enforce` dial.
//      Evaluated BEFORE any write (never a rollback path) — nothing written.
//      --dry-run never returns 4 (verdict reported informationally in its JSON).
//   5  evidence-path gate REFUSED (CHANGE-0131 / spec-evidence-path-gate): a
//      closing doc's Acceptance Criteria Status Evidence cell cites a
//      path-shaped token that does not resolve from the MAIN checkout root
//      (PR #245 Codex P1: resolved via `git worktree list --porcelain`, NOT
//      process.cwd() — a close run from a linked worktree must not let
//      worktree-stranded evidence resolve "fine"), under an
//      `evidence_path_gate: enforce` dial. Evaluated BEFORE any write (never
//      a rollback path) — nothing written. --dry-run never returns 5
//      (verdict reported informationally in its JSON).
//   6  STATE RECONCILE PARTIAL (spec-close-leaves-state-stale D3): a genuine
//      mid-apply partial — the first state.mjs reconcile command succeeded but
//      a LATER one failed. The close itself already committed and self-
//      verified CLEAN (this exit is reached only strictly after the existing
//      try/catch above, never a rollback path). Named PARTIAL block on
//      stderr naming applied-of-total and the remaining commands verbatim.
//
// STATE RECONCILE (D1-D6, spec-close-leaves-state-stale) — after self-verify
// proves the close CLEAN (strictly outside the doc/event try/catch's rollback
// scope), reconcile docs/ai/STATE.yaml so it stops describing the just-closed
// scope as in-flight: active_work_items[<ref>].status -> done plus the
// resolved on-disk paths, and current_focus's paths when it names this scope.
// Written ONLY through the sanctioned `state.mjs` CLI (set-phase/set-focus,
// D2) — never a raw STATE byte write (Article 6). Nothing-written failures
// (STATE absent/unusable, the R-GUARD single-writer refusal, or the first
// command failing) degrade to a named WARN + exit 0 (Article 4: a STATE
// defect must never block a verified close); a genuine mid-apply partial is
// the new exit 6 above.
//
// Node stdlib only (docs/TECHNOLOGY.md). Reuses append-event.mjs verbatim
// (no forked event schema) and the shared docs-audit engine (no re-implemented
// heuristics — the real audit is the self-verify oracle).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { scanAuditDocs, loadConfig, runAudit, readEvents } from './lib/docs-audit-core.mjs';
import { parseFrontmatter, extractDocIds, DEFAULT_CATEGORY_PREFIXES, slugFamilyForPath, DOMAIN_SLUG_RE } from './lib/docs-model.mjs';
import { readGuardConfig } from './lib/guard-config.mjs';
import { REQUIRED_PRODUCT_SECTIONS, missingProductSections } from './lib/product-doc.mjs';
import { extractUsageTotal, hasUsageSentinel, isHarnessDispatchedRole } from './lib/usage-note.mjs';
import { unresolvedCitations } from './lib/evidence-paths.mjs';
import { loadState, findBlock, readScalar, unquoteScalar } from './lib/state-engine.mjs';
import { duplicateKeys, splitLines } from './lib/state-core.mjs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const ROOT = process.cwd();
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const STATE_CLI = path.join(SCRIPT_DIR, 'state.mjs');
const EVENTS_PATH = path.join(ROOT, 'docs/ai/EVENTS.jsonl');
const APPEND_EVENT = path.join(SCRIPT_DIR, 'append-event.mjs');
const GENERATE_INDEX = path.join(SCRIPT_DIR, 'generate-docs-index.mjs');
const GENERATE_OVERVIEW = path.join(SCRIPT_DIR, 'generate-overview.mjs');
const GENERATE_USERGUIDE_ROLLUP = path.join(SCRIPT_DIR, 'generate-userguide-rollup.mjs');
const GENERATE_DOCS_HUB = path.join(SCRIPT_DIR, 'generate-docs-hub.mjs');
const GENERATE_FACTORY_REPORT = path.join(SCRIPT_DIR, 'generate-factory-report.mjs');

// D3 — flip-eligible statuses. `done` is handled separately (no-op). Every
// other status (deferred | rejected | superseded | anything unrecognized) is
// a fatal usage error: the close ceremony never silently reopens/repurposes
// a terminal non-done doc.
const FLIP_ELIGIBLE = new Set(['draft', 'implementing', 'accepted']);

function usageError(msg) {
  process.stderr.write(`close-work-item: ${msg}\n`);
  process.stderr.write(
    'usage: node .aai/scripts/close-work-item.mjs --ref <slug> --pr <N|TBD> --commit <sha> ' +
      '[--spec <spec-slug>] [--review <pass|waived|none>] [--dry-run]\n' +
      '   or: node .aai/scripts/close-work-item.mjs --ref <slug> --stamp-pr <N> [--spec <spec-slug>]\n'
  );
  exit(2);
}

// TBD_SENTINEL — the ONLY non-integer value --pr accepts (case-insensitive
// on input, stored canonicalized as this exact literal). See PR-NUMBER
// SPLIT above.
const TBD_SENTINEL = 'TBD';

function parseArgs(argv) {
  const args = { spec: null, review: 'none', dryRun: false, stampPr: null };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--ref') args.ref = argv[++i];
    else if (tok === '--pr') args.pr = argv[++i];
    else if (tok === '--commit') args.commit = argv[++i];
    else if (tok === '--spec') args.spec = argv[++i];
    else if (tok === '--review') args.review = argv[++i];
    else if (tok === '--dry-run') args.dryRun = true;
    else if (tok === '--stamp-pr') args.stampPr = argv[++i];
    else usageError(`unrecognized flag: ${tok}`);
  }
  if (!args.ref) usageError('missing --ref');

  if (args.stampPr !== null) {
    // --stamp-pr mode: mutually exclusive with the close-transaction flags.
    if (args.pr !== undefined) usageError('--stamp-pr cannot be combined with --pr (they are separate modes)');
    if (args.commit !== undefined) usageError('--stamp-pr cannot be combined with --commit (they are separate modes)');
    if (args.dryRun) usageError('--stamp-pr cannot be combined with --dry-run');
    if (!/^\d+$/.test(String(args.stampPr))) usageError('--stamp-pr requires an integer PR number');
    return args;
  }

  if (!args.pr) usageError('missing --pr (integer, or the literal TBD before the PR exists)');
  if (String(args.pr).toUpperCase() === TBD_SENTINEL) {
    args.pr = TBD_SENTINEL;
  } else if (!/^\d+$/.test(String(args.pr))) {
    usageError('invalid --pr (integer, or the literal TBD before the PR exists)');
  }
  if (!args.commit) usageError('missing --commit');
  if (!['pass', 'waived', 'none'].includes(args.review)) usageError('--review must be one of pass|waived|none');
  return args;
}

// --- doc resolution (D2 — the SAME two-pass scan docs-audit's gateDoc uses) --

function resolveDoc(root, slug) {
  const config = loadConfig(root);
  // spec-product-docs-capability-model — a product doc (docs/product/
  // <capability>.md) is a maintained PROJECTION the close ceremony only ever
  // WRITES to (the delivered_by/updated upsert, keyed by capability path, not
  // by id) — it is never itself a valid --ref/--spec close TARGET. Excluding
  // it from the resolution candidate pool here also sidesteps the by-design
  // cross-axis id coincidence (a capability slug equalling its originating
  // change doc's ref id, the common 1:1 migration case) that would otherwise
  // make resolveDoc report a false "ambiguous id".
  const files = scanAuditDocs(root, { scanExclude: config?.scan_exclude ?? [] })
    .filter((f) => slugFamilyForPath(f.rel)?.type !== 'product');
  const categoryPrefixes = config?.category_prefixes ?? DEFAULT_CATEGORY_PREFIXES;
  const entries = files.map((f) => {
    const abs = path.join(root, f.rel);
    const content = fs.readFileSync(abs, 'utf8');
    const fm = parseFrontmatter(content);
    const ids = extractDocIds(path.basename(f.rel), categoryPrefixes) ?? { primary: f.fileId };
    return { rel: f.rel, abs, content, fm, fmId: fm?.id ?? null, fileIds: [ids.primary, f.fileId].filter(Boolean) };
  });
  let pass = 'frontmatter-id';
  let matches = entries.filter((e) => e.fmId === slug);
  if (matches.length === 0) {
    pass = 'display-id';
    matches = entries.filter((e) => e.fileIds.includes(slug));
  }
  if (matches.length === 0) {
    return { found: false, reasons: [`no scanned doc resolves to id "${slug}"`] };
  }
  if (matches.length > 1) {
    return {
      found: false,
      reasons: [
        `ambiguous id "${slug}": ${matches.length} scanned docs match in the ${pass} pass — fail-closed, no doc closed`,
        ...matches.map((m) => `candidate: ${m.rel}`),
      ],
    };
  }
  return { found: true, doc: matches[0] };
}

// scanForStaleTbdPr(root, excludeSlugs) -> the rel paths of every `status:
// done` doc (other than the refs THIS invocation is itself closing/stamping)
// whose links.pr still carries the literal TBD sentinel (fu-close-requires-
// pr-before-it-exists — "must not go unfilled"). Report-only, mechanized:
// close-work-item.mjs runs on nearly every ride, so a forgotten `--stamp-pr`
// surfaces as a named stderr WARNING on the very next invocation ANYWHERE in
// the repo, not a silently-wrong-forever placeholder. Never refuses, never
// affects the exit code — a stale doc elsewhere must not block an unrelated
// close.
function scanForStaleTbdPr(root, excludeSlugs) {
  const exclude = new Set(excludeSlugs);
  const config = loadConfig(root);
  const files = scanAuditDocs(root, { scanExclude: config?.scan_exclude ?? [] })
    .filter((f) => slugFamilyForPath(f.rel)?.type !== 'product');
  const stale = [];
  for (const f of files) {
    const abs = path.join(root, f.rel);
    let content;
    try {
      content = fs.readFileSync(abs, 'utf8');
    } catch {
      continue;
    }
    const fm = parseFrontmatter(content);
    const fmId = fm?.id ?? null;
    if (!fmId || exclude.has(fmId)) continue;
    if (String(fm?.status ?? '').toLowerCase() !== 'done') continue;
    if (hasLinkValue(content, 'pr', TBD_SENTINEL)) stale.push({ rel: f.rel, ref: fmId });
  }
  return stale;
}

function emitStaleTbdWarning(stale) {
  if (stale.length === 0) return;
  process.stderr.write(
    `close-work-item: WARNING ${stale.length} closed doc(s) still carry an unstamped TBD PR placeholder ` +
      '(fu-close-requires-pr-before-it-exists) — run --stamp-pr <N> for each:\n'
  );
  for (const s of stale) {
    process.stderr.write(`  - ${s.ref} (${s.rel}) — node .aai/scripts/close-work-item.mjs --ref ${s.ref} --stamp-pr <N>\n`);
  }
}

// --- product-doc gate (D1-D3, spec-product-docs-enforced) --------------------
//
// Evaluated ONLY for the PRIMARY --ref doc (D1 — the always-present anchor;
// --spec is optional and reading the trigger from it would silently fail-open
// on every close that omits --spec). Truthy `user_visible` is narrow: the
// frontmatter value lower-cased equals the string "true"; anything else
// (false, absent, garbage) leaves the gate silent (D1 legacy-safe default).

function truthyUserVisible(fm) {
  const v = fm?.user_visible;
  if (v === undefined || v === null) return false;
  return String(v).trim().toLowerCase() === 'true';
}

// spec-product-docs-capability-model D3 (SEAM-2) — the capability the
// product-doc gate keys on: the primary doc's frontmatter `capability`, or
// (legacy fallback, back-compat with a doc whose capability equals its own
// ride slug — i.e. every migrated doc) the primary doc's frontmatter slug id
// when `capability` is absent/blank.
function resolveCapability(primaryDoc) {
  const raw = primaryDoc.fm?.capability;
  const v = raw == null ? '' : String(raw).trim();
  return v !== '' ? v : primaryDoc.fmId;
}

// evaluateProductDocGate(primaryDoc) -> { userVisible, severity, slug?,
//   productDocPath?, productDocExists?, missingSections?, dial?, reason? }
// severity is 'none' (not gated, or a real product doc present), 'warn'
// (report-only dial), or 'refuse' (enforce dial). Read-only — callers decide
// whether/when to act on the verdict (D3: the refuse branch must run BEFORE
// any write; --dry-run must never act on it).
// `slug` here is the resolved CAPABILITY (spec-product-docs-capability-model
// D3, SEAM-2) — docs/product/<capability>.md, not the closing ref's own id.
function evaluateProductDocGate(primaryDoc) {
  if (!truthyUserVisible(primaryDoc.fm)) return { userVisible: false, severity: 'none' };
  const slug = resolveCapability(primaryDoc);
  // A checked-out work-item doc controls `capability` — validate the slug
  // BEFORE joining it into a path, or a value like "../../x" would escape
  // docs/product (Codex P1). Invalid slug = hard refusal, never a path build.
  if (!DOMAIN_SLUG_RE.test(slug)) {
    return {
      userVisible: true, severity: 'refuse', slug, productDocPath: null,
      productDocExists: false, missingSections: REQUIRED_PRODUCT_SECTIONS.slice(),
      reason: `capability "${slug}" is not a valid slug (must match ${DOMAIN_SLUG_RE}) — refusing to resolve a product-doc path from it`,
    };
  }
  const productDocPath = `docs/product/${slug}.md`;
  const abs = path.join(ROOT, productDocPath);
  const exists = fs.existsSync(abs);
  const missing = exists ? missingProductSections(fs.readFileSync(abs, 'utf8')) : REQUIRED_PRODUCT_SECTIONS.slice();
  if (missing.length === 0) {
    return { userVisible: true, severity: 'none', slug, productDocPath, productDocExists: true, missingSections: [] };
  }
  const dial = readGuardConfig(path.join(ROOT, 'docs/ai')).product_doc_gate;
  const reason = exists
    ? `user_visible scope "${slug}" product doc ${productDocPath} is missing/placeholder section(s): ${missing.join(', ')}`
    : `user_visible scope "${slug}" has no product doc at ${productDocPath}`;
  return {
    userVisible: true,
    severity: dial === 'enforce' ? 'refuse' : 'warn',
    slug,
    productDocPath,
    productDocExists: exists,
    missingSections: missing,
    dial,
    reason,
  };
}

// --- frontmatter line-surgical mutation (D4) ---------------------------------
// Line-surgical: only the frontmatter block's own lines are ever replaced or
// spliced; the doc body (everything from the closing `---` onward) is
// byte-untouched. Split off the frontmatter first the same EOL-agnostic way
// allocate-doc-number.mjs's stampNumber does (detect LF vs CRLF, preserve it).

function splitFrontmatter(content) {
  const open = content.match(/^---(\r?\n)/);
  if (!open) return null;
  const eol = open[1];
  const fmEnd = content.indexOf(`${eol}---`, open[0].length);
  if (fmEnd < 0) return null;
  return { head: content.slice(0, fmEnd), rest: content.slice(fmEnd), eol };
}

function stripQuotes(s) {
  return s.replace(/^["']|["']$/g, '');
}

// Locate the `links.<field>` sub-key within the frontmatter's `links:` block
// by direct line scan. parseFrontmatter's generic parser only supports one
// level of YAML nesting cleanly; `links: { pr: [...], commits: [...] }` is a
// SECOND level (a list nested under a key nested under `links:`), which it
// mis-parses (see docs-model.mjs). This reader/mutator owns its own narrow,
// convention-matching scan instead — the observed repo convention is
// `links:` / two-space `pr:`|`commits:` / four-space `- <item>` lines, with
// an inline `pr: []` for the empty case.
function locateLinksField(lines, field) {
  const linksIdx = lines.findIndex((l) => /^links:\s*$/.test(l));
  if (linksIdx === -1) return { linksIdx: -1 };
  let blockEnd = linksIdx + 1;
  while (blockEnd < lines.length && /^\s+\S/.test(lines[blockEnd])) blockEnd += 1;
  const fieldRe = new RegExp(`^ {2}${field}:\\s*(.*)$`);
  for (let i = linksIdx + 1; i < blockEnd; i += 1) {
    const m = lines[i].match(fieldRe);
    if (!m) continue;
    const inlineVal = m[1].trim();
    let itemsEnd = i + 1;
    const items = [];
    while (itemsEnd < blockEnd) {
      const im = lines[itemsEnd].match(/^ {4}-\s*(.*)$/);
      if (!im) break;
      items.push(stripQuotes(im[1].trim()));
      itemsEnd += 1;
    }
    if (inlineVal.startsWith('[') && inlineVal.endsWith(']') && inlineVal !== '[]') {
      for (const raw of inlineVal.slice(1, -1).split(',')) {
        const v = stripQuotes(raw.trim());
        if (v) items.push(v);
      }
    }
    return {
      linksIdx, blockEnd, fieldIdx: i, itemsEnd, items,
      inlineEmpty: inlineVal === '[]',
      // code-review B2: an INLINE non-empty list (`pr: [42]`) needs the SAME
      // normalize-to-block treatment as inlineEmpty before an append —
      // otherwise stampLink's default branch (block-append) would splice a
      // bare block item directly after the still-inline field line, yielding
      // malformed mixed inline+block YAML.
      inlineNonEmpty: inlineVal.startsWith('[') && inlineVal.endsWith(']') && inlineVal !== '[]',
    };
  }
  return { linksIdx, blockEnd, fieldIdx: -1 };
}

// Read-only: does links.<field> already carry `value` (D6.2 idempotency probe)?
function hasLinkValue(content, field, value) {
  const split = splitFrontmatter(content);
  if (!split) return false;
  const lines = split.head.split(split.eol);
  const loc = locateLinksField(lines, field);
  return (loc.items ?? []).includes(String(value));
}

// Mutate `lines` (the frontmatter head, in place) so links.<field> contains
// `value` — append-if-absent, dedupe, create the key/block if missing (D4).
function stampLink(lines, field, value) {
  const v = String(value);
  const loc = locateLinksField(lines, field);
  if (loc.linksIdx === -1) {
    lines.push('links:', `  ${field}:`, `    - ${v}`);
    return;
  }
  if (loc.fieldIdx === -1) {
    lines.splice(loc.linksIdx + 1, 0, `  ${field}:`, `    - ${v}`);
    return;
  }
  if (loc.items.includes(v)) return; // already present — no duplicate
  if (loc.inlineEmpty) {
    lines.splice(loc.fieldIdx, 1, `  ${field}:`, `    - ${v}`);
    return;
  }
  if (loc.inlineNonEmpty) {
    // code-review B2 fix-at-cause: normalize the pre-existing inline
    // non-empty list to block form (carrying its already-parsed items) in
    // the SAME splice that appends the new value, instead of leaving the
    // inline line in place and appending a block item after it (which
    // produced malformed mixed inline+block YAML).
    const blockLines = loc.items.map((item) => `    - ${item}`);
    lines.splice(loc.fieldIdx, loc.itemsEnd - loc.fieldIdx, `  ${field}:`, ...blockLines, `    - ${v}`);
    return;
  }
  lines.splice(loc.itemsEnd, 0, `    - ${v}`);
}

// replaceLinkValue(lines, field, oldValue, newValue) -> true when `oldValue`
// was found in links.<field> and replaced by `newValue` (dedup against an
// already-present newValue); false when `oldValue` is not present (no
// mutation — the caller decides whether that is an error). Reuses
// locateLinksField's block/inline parsing exactly like stampLink; always
// rewrites the field to normalized block form (same normalize-on-touch
// convention stampLink already applies to a pre-existing inline list), never
// touches any OTHER links.<field2> block. --stamp-pr's ONLY mutation path
// (fu-close-requires-pr-before-it-exists): replaces the TBD sentinel with
// the real PR number once it exists.
function replaceLinkValue(lines, field, oldValue, newValue) {
  const from = String(oldValue);
  const to = String(newValue);
  const loc = locateLinksField(lines, field);
  if (loc.linksIdx === -1 || loc.fieldIdx === -1) return false;
  if (!loc.items.includes(from)) return false;
  const replaced = loc.items.map((item) => (item === from ? to : item));
  const deduped = [...new Set(replaced)];
  const blockLines = deduped.map((item) => `    - ${item}`);
  lines.splice(loc.fieldIdx, loc.itemsEnd - loc.fieldIdx, `  ${field}:`, ...blockLines);
  return true;
}

function stampStatus(lines, toStatus) {
  const idx = lines.findIndex((l) => /^status:/.test(l));
  if (idx === -1) throw new Error('frontmatter has no top-level "status:" key');
  lines[idx] = `status: ${toStatus}`;
}

// --- product-doc delivered_by/updated upsert (SEAM-2/SEAM-3, D3) ------------
//
// Same line-surgical convention as stampLink/stampStatus, but for a
// TOP-LEVEL (not links-nested) block-list key — `delivered_by:` on
// docs/product/<capability>.md (2-space item indent, mirroring RFC-0003's
// `sources:` convention parseFrontmatter already understands).

function locateTopLevelListField(lines, field) {
  const fieldRe = new RegExp(`^${field}:\\s*(.*)$`);
  const idx = lines.findIndex((l) => fieldRe.test(l));
  if (idx === -1) return { idx: -1 };
  const inlineVal = lines[idx].match(fieldRe)[1].trim();
  let itemsEnd = idx + 1;
  const items = [];
  while (itemsEnd < lines.length) {
    const im = lines[itemsEnd].match(/^ {2}-\s*(.*)$/);
    if (!im) break;
    items.push(stripQuotes(im[1].trim()));
    itemsEnd += 1;
  }
  if (inlineVal.startsWith('[') && inlineVal.endsWith(']') && inlineVal !== '[]') {
    for (const raw of inlineVal.slice(1, -1).split(',')) {
      const v = stripQuotes(raw.trim());
      if (v) items.push(v);
    }
  }
  return {
    idx, itemsEnd, items,
    inlineEmpty: inlineVal === '[]',
    inlineNonEmpty: inlineVal.startsWith('[') && inlineVal.endsWith(']') && inlineVal !== '[]',
  };
}

// stampTopLevelList(lines, field, value) -> true when `value` was newly
// appended (a real mutation), false when it was already present (no-op —
// the D6.2/D3 byte-idempotency contract).
function stampTopLevelList(lines, field, value) {
  const v = String(value);
  const loc = locateTopLevelListField(lines, field);
  if (loc.idx === -1) {
    // Defensive fallback: a product doc predating the `delivered_by:` key
    // (should not happen once PRODUCT_TEMPLATE.md carries it) still gets a
    // well-formed block list appended at EOF of the frontmatter head.
    lines.push(`${field}:`, `  - ${v}`);
    return true;
  }
  if (loc.items.includes(v)) return false;
  if (loc.inlineEmpty) {
    lines.splice(loc.idx, 1, `${field}:`, `  - ${v}`);
    return true;
  }
  if (loc.inlineNonEmpty) {
    const blockLines = loc.items.map((item) => `  - ${item}`);
    lines.splice(loc.idx, loc.itemsEnd - loc.idx, `${field}:`, ...blockLines, `  - ${v}`);
    return true;
  }
  lines.splice(loc.itemsEnd, 0, `  - ${v}`);
  return true;
}

function stampTopLevelScalar(lines, field, value) {
  const idx = lines.findIndex((l) => new RegExp(`^${field}:`).test(l));
  if (idx === -1) { lines.push(`${field}: ${value}`); return; }
  lines[idx] = `${field}: ${value}`;
}

function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

// applyProductDocMutation(content, ref) -> the new content (byte-identical to
// `content` when `ref` is already in delivered_by — the D3 byte-idempotency
// contract). Appends `ref` to `delivered_by` (append-if-absent, deduped) and
// stamps `updated` to today ONLY when a real append happened, so a no-op
// upsert never touches `updated` either. Authored prose (everything after
// the frontmatter block) is never touched.
function applyProductDocMutation(content, ref) {
  const split = splitFrontmatter(content);
  if (!split) throw new Error('cannot locate a frontmatter block to mutate (product doc)');
  const lines = split.head.split(split.eol);
  const appended = stampTopLevelList(lines, 'delivered_by', ref);
  if (!appended) return content;
  stampTopLevelScalar(lines, 'updated', todayISO());
  return lines.join(split.eol) + split.rest;
}

// Apply the full D3+D4 mutation to one doc's raw content; returns the new
// content (body untouched). `toStatus` is null when no transition is needed.
function applyDocMutation(content, { toStatus, pr, commit }) {
  const split = splitFrontmatter(content);
  if (!split) throw new Error('cannot locate a frontmatter block to mutate');
  const lines = split.head.split(split.eol);
  if (toStatus) stampStatus(lines, toStatus);
  stampLink(lines, 'pr', pr);
  stampLink(lines, 'commits', commit);
  return lines.join(split.eol) + split.rest;
}

// --- events (D5) --------------------------------------------------------------

function hasWorkItemClosed(events, ref) {
  return events.some((e) => e.event === 'work_item_closed' && e.ref === ref);
}

function hasAcEvidence(events, ref, commit) {
  return events.some((e) => e.event === 'ac_evidence' && e.ref === ref && e.payload?.commit === commit);
}

function emitEvent(event, ref, extraArgs) {
  execFileSync('node', [APPEND_EVENT, '--event', event, '--ref', ref, ...extraArgs], {
    stdio: 'ignore',
    cwd: ROOT,
  });
}

// --- post-merge-close advisory (role-verification-guards G1, D1) ------------
//
// Detects a close running AFTER its delivery commit already reached the
// upstream default branch — proxy for "the PR is merged" via a git predicate
// only, never the PR API (D1: close-work-item stays network-free and every
// one of its arms hermetic; pr-platform.mjs is a URL classifier with no
// PR-state reader). Fail-open on every git failure or absent remote: a false
// silence costs nothing, a false alarm in the close ceremony trains people to
// ignore the line. Resolution order: `origin/HEAD` symbolic ref, then the
// literal `origin/main`, then `origin/master` — first hit wins.

function resolveUpstreamDefaultRef(root) {
  try {
    const out = execFileSync('git', ['symbolic-ref', '--quiet', 'refs/remotes/origin/HEAD'], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (out) return out.replace(/^refs\/remotes\//, '');
  } catch { /* fall through to the literal candidates */ }
  for (const ref of ['origin/main', 'origin/master']) {
    try {
      execFileSync('git', ['rev-parse', '--verify', '--quiet', ref], {
        cwd: root, stdio: ['ignore', 'ignore', 'ignore'],
      });
      return ref;
    } catch { /* try the next candidate */ }
  }
  return null;
}

// emitPostMergeCloseWarning(root, commit, pr) — called ONCE per invocation
// (never once per ref, so a pair-close still prints at most one line). Prints
// to stderr only; never touches stdout or the exit code. Any unexpected
// failure here is swallowed — this advisory must never affect the close.
function emitPostMergeCloseWarning(root, commit, pr) {
  try {
    if (!commit) return;
    const ref = resolveUpstreamDefaultRef(root);
    if (!ref) return;
    try {
      execFileSync('git', ['merge-base', '--is-ancestor', commit, ref], {
        cwd: root, stdio: ['ignore', 'ignore', 'ignore'],
      });
    } catch {
      return; // not an ancestor (or the commit/ref is unresolvable) -> silence
    }
    process.stderr.write(
      `close-work-item: WARN post-merge-close - delivery commit ${commit} is already an ` +
      `ancestor of ${ref}; commits produced by this close will be in neither PR #${pr} nor its CI\n`
    );
  } catch {
    /* fail-open: never let this advisory affect the close */
  }
}

// --- self-verify (D6.4) -------------------------------------------------------

// code-review B1 fix-at-cause: THROW on failure instead of calling
// exit() directly. exit() is uncatchable — when this ran
// from inside the post-apply selfVerify() (:436), it terminated the process
// before the enclosing try's catch(err) (:444, which owns rollback()) ever
// ran, leaving a half-closed doc + appended EVENTS on disk with exit 1
// (violates D6.5 / Spec-AC-04). Throwing lets both call sites react
// correctly: the post-apply call is inside the try/catch, so the throw
// propagates to catch(err), which rolls back BEFORE exiting non-zero; the
// pre-write idempotency-short-circuit call (nothing written that run, so
// nothing to roll back) lets the throw reach the top-level try/catch, which
// already exits non-zero on any internal error — same D8 "self-verify
// failed" exit-1 contract, just via `throw` instead of a direct exit.
function regenerateIndex() {
  if (!fs.existsSync(GENERATE_INDEX)) {
    throw new Error('generate-docs-index.mjs not found — cannot self-verify (fail-closed)');
  }
  try {
    execFileSync('node', [GENERATE_INDEX], { stdio: 'ignore', cwd: ROOT });
  } catch (err) {
    throw new Error(`INDEX regeneration failed — cannot self-verify (fail-closed): ${err.message}`);
  }
}

// --- overview regen (Spec-AC-06, token-economics-end-to-end) -----------------
//
// Best-effort regen of the stakeholder overview, invoked as the STRICTLY LAST
// step of a successful close (after self-verify + pruneBriefs, called from
// main() only once every write/event/self-verify/brief-prune step has
// already succeeded). A generator failure here must NEVER change the close
// exit code and must NEVER reach rollback() -- the close verdict never
// depends on a report page (negative control: token-economics TEST-009).
// Unlike regenerateIndex() (which THROWS so self-verify failures still roll
// back the close), this function swallows every failure itself -- there is
// no caller left that could roll back by the time it runs.
function regenerateOverviewBestEffort() {
  try {
    if (!fs.existsSync(GENERATE_OVERVIEW)) return;
    execFileSync('node', [GENERATE_OVERVIEW], { stdio: 'ignore', cwd: ROOT });
  } catch (err) {
    process.stderr.write(`close-work-item: INFO overview regen skipped (best-effort, non-fatal): ${err.message}\n`);
  }
}

// --- USER_GUIDE rollup regen (D5, spec-product-docs-enforced) ---------------
//
// Best-effort regen of the USER_GUIDE "Delivered features (generated)"
// section, invoked as the STRICTLY LAST step of a successful close,
// immediately AFTER regenerateOverviewBestEffort() -- reusing that exact
// pattern verbatim: fs.existsSync guard (the generator is an `extended`-
// profile file and may be absent in a core-only sync, D6), swallow every
// failure to an INFO stderr line, never reach rollback, never change the exit
// code (negative-control-backed, Spec-AC-04).
function regenerateUserguideRollupBestEffort() {
  try {
    if (!fs.existsSync(GENERATE_USERGUIDE_ROLLUP)) return;
    // Capture stdout instead of discarding it: the rollup's EXCLUDED
    // diagnostics (CHANGE-0075) must reach the operator through THIS primary
    // production path too, not only on manual runs (PR #181 review).
    const out = execFileSync('node', [GENERATE_USERGUIDE_ROLLUP], { stdio: ['ignore', 'pipe', 'ignore'], cwd: ROOT }).toString();
    for (const line of out.split('\n')) {
      if (line.includes('EXCLUDED')) process.stderr.write(`close-work-item: ${line}\n`);
    }
  } catch (err) {
    process.stderr.write(`close-work-item: INFO userguide rollup regen skipped (best-effort, non-fatal): ${err.message}\n`);
  }
}

// --- skills catalog regen (spec-docs-hub-generator) --------------------------
//
// Best-effort regen of the AAI skills catalog, invoked as the STRICTLY LAST
// step of a successful close, immediately AFTER
// regenerateUserguideRollupBestEffort() -- reusing that exact pattern
// verbatim: fs.existsSync guard (the generator is an `extended`-profile file
// and may be absent in a core-only sync), swallow every failure to an INFO
// stderr line, never reach rollback, never change the exit code.
function regenerateDocsHubBestEffort() {
  try {
    if (!fs.existsSync(GENERATE_DOCS_HUB)) return;
    execFileSync('node', [GENERATE_DOCS_HUB], { stdio: 'ignore', cwd: ROOT });
  } catch (err) {
    process.stderr.write(`close-work-item: INFO docs-hub regen skipped (best-effort, non-fatal): ${err.message}\n`);
  }
}

// --- factory performance report regen (SPEC spec-factory-performance-report) -
//
// Best-effort regen of the Factory Performance Report, invoked as the STRICTLY
// LAST step of a successful close, immediately AFTER
// regenerateDocsHubBestEffort() -- reusing that exact pattern verbatim:
// fs.existsSync guard (the generator is an `extended`-profile file and may be
// absent in a core-only sync), swallow every failure to an INFO stderr line,
// never reach rollback, never change the exit code (negative-control-backed,
// Spec-AC-09 / test-aai-factory-report TEST-013).
function regenerateFactoryReportBestEffort() {
  try {
    if (!fs.existsSync(GENERATE_FACTORY_REPORT)) return;
    execFileSync('node', [GENERATE_FACTORY_REPORT], { stdio: 'ignore', cwd: ROOT });
  } catch (err) {
    process.stderr.write(`close-work-item: INFO factory-report regen skipped (best-effort, non-fatal): ${err.message}\n`);
  }
}

// --- CAPTURE POINT 2 — deterministic remediation-at-close friction ----------
// (CHANGE deterministic-friction-capture) When the closing ride carried
// remediation runs, append ONE raw schema-v2 observation summarizing that a
// completed ride reached close carrying recovery work. RAW only — no ownership
// judgment here (confidence `low`); triage stays review-mode. Same discipline
// as the report/docs-hub regen hooks: best-effort, STRICTLY LAST, never changes
// the close exit code, never reaches rollback.

// countRemediationRuns(ref) -> the number of `role: Remediation` agent_runs
// recorded for `ref` in docs/ai/STATE.yaml (0 if the file/block is absent).
// A minimal indentation-scoped line reader (Node stdlib only, no YAML dep,
// mirroring aai-friction.mjs's feedback.yaml discipline): metrics: (col 0) ->
// work_items: (2) -> <ref>: (4) -> count `role: Remediation` strictly inside
// that ref's block (indent > 4). Other refs' remediation runs are never counted.
function countRemediationRuns(ref) {
  let text;
  try {
    text = fs.readFileSync(path.join(ROOT, 'docs/ai/STATE.yaml'), 'utf8');
  } catch {
    return 0;
  }
  let inMetrics = false;
  let inWorkItems = false;
  let inRef = false;
  let count = 0;
  for (const raw of text.split('\n')) {
    if (!raw.trim()) continue;
    const indent = raw.length - raw.trimStart().length;
    const line = raw.trim();
    if (!inMetrics) {
      if (indent === 0 && /^metrics\s*:/.test(line)) inMetrics = true;
      continue;
    }
    if (indent === 0) break; // metrics block ended
    if (!inWorkItems) {
      if (indent === 2 && /^work_items\s*:/.test(line)) inWorkItems = true;
      continue;
    }
    if (indent === 2) break; // work_items ended (sibling metrics key)
    if (!inRef) {
      if (indent === 4 && line === `${ref}:`) inRef = true;
      continue;
    }
    if (indent <= 4) break; // this ref's block ended (next ref or dedent)
    if (/^-?\s*role\s*:\s*Remediation\b/.test(line)) count += 1;
  }
  return count;
}

// --- CLOSE-TIME usage-capture gate (spec-telemetry-completeness, design A) ---
//
// The per-ride deterministic checkpoint the intake's leak analysis names as
// "the empty seat": close-work-item runs while the ride's agent_runs are STILL
// in STATE.yaml (before flush strands them), it already reads that block
// (countRemediationRuns), and it already owns a fail-open guard-config dial
// pattern (the product-doc gate). This gate scans those runs for a
// harness-dispatched-role run that dropped its usage capture and, mirroring
// product_doc_gate, WARNs (report-only, shipped default) or REFUSEs pre-write
// (enforce, opt-in). Reuses lib/usage-note.mjs for the marker grammar
// (extractUsageTotal), the honest-gap sentinel (hasUsageSentinel), and the
// canonical harness-role vocabulary (isHarnessDispatchedRole) — no re-declared
// regex, no forked role list.

// scanAgentRuns(ref) -> [{ role, note, tokensIn, tokensOut }] for every
// agent_run recorded under metrics.work_items.<ref> in docs/ai/STATE.yaml, or
// [] when the file/block is absent (a fixture repo with no STATE.yaml is never
// gated — the close suite's non-regression property). Same indentation-scoped
// line reader as countRemediationRuns (Node stdlib only, no YAML dep):
// metrics: (col 0) -> work_items: (2) -> <ref>: (4), then split the ref block
// (indent > 4) into runs on each `        - role:` line (indent 8). The folded
// (`note: >-`) scalar is re-joined with single spaces so the marker/sentinel
// grammar (delimited on both sides) matches across continuation lines.
function scanAgentRuns(ref) {
  let text;
  try {
    text = fs.readFileSync(path.join(ROOT, 'docs/ai/STATE.yaml'), 'utf8');
  } catch {
    return [];
  }
  // Phase 1 — collect the raw lines strictly inside this ref's block (indent > 4).
  const blockLines = [];
  let inMetrics = false;
  let inWorkItems = false;
  let inRef = false;
  for (const raw of text.split('\n')) {
    if (!raw.trim()) continue;
    const indent = raw.length - raw.trimStart().length;
    const line = raw.trim();
    if (!inMetrics) {
      if (indent === 0 && /^metrics\s*:/.test(line)) inMetrics = true;
      continue;
    }
    if (indent === 0) break;
    if (!inWorkItems) {
      if (indent === 2 && /^work_items\s*:/.test(line)) inWorkItems = true;
      continue;
    }
    if (indent === 2) break;
    if (!inRef) {
      if (indent === 4 && line === `${ref}:`) inRef = true;
      continue;
    }
    if (indent <= 4) break;
    blockLines.push(raw);
  }
  // Phase 2 — split into runs on `- role:` (indent 8); parse note + tokens.
  const parseTok = (v) => {
    const t = String(v).trim();
    if (t === '' || t === 'null' || t === '~') return null;
    return /^-?\d+$/.test(t) ? Number(t) : null;
  };
  const runs = [];
  let cur = null;
  let inNote = false;
  for (const raw of blockLines) {
    const indent = raw.length - raw.trimStart().length;
    const body = raw.trimStart();
    const roleM = indent === 8 ? body.match(/^-\s*role:\s*(.+?)\s*$/) : null;
    if (roleM) {
      if (cur) runs.push(cur);
      cur = { role: stripQuotes(roleM[1].trim()), noteParts: [], tokensIn: null, tokensOut: null };
      inNote = false;
      continue;
    }
    if (!cur) continue;
    if (indent === 10) {
      const noteM = body.match(/^note:\s*(.*)$/);
      if (noteM) {
        inNote = true;
        const v = noteM[1].trim();
        // Skip a bare block-scalar indicator (>-, >, |, |-, |+ ...); keep an
        // inline `note: text` value.
        if (v && !/^[>|][+-]?$/.test(v)) cur.noteParts.push(stripQuotes(v));
        continue;
      }
      const tiM = body.match(/^tokens_in:\s*(.+?)\s*$/);
      if (tiM) { inNote = false; cur.tokensIn = parseTok(tiM[1]); continue; }
      const toM = body.match(/^tokens_out:\s*(.+?)\s*$/);
      if (toM) { inNote = false; cur.tokensOut = parseTok(toM[1]); continue; }
      inNote = false; // any other indent-10 field ends the note block
      continue;
    }
    if (indent >= 12 && inNote) { cur.noteParts.push(body.trim()); continue; }
  }
  if (cur) runs.push(cur);
  return runs.map((r) => ({
    role: r.role,
    note: r.noteParts.join(' '),
    tokensIn: r.tokensIn,
    tokensOut: r.tokensOut,
  }));
}

// usageCaptured(run) -> true when the run carries ANY honest usage signal:
// decomposed tokens (both in AND out present), a valid usage_total_tokens
// marker, or the usage_capture=none sentinel (the honest-gap escape hatch).
// Mirrors the metrics-flush 3-way classifier (decomposed | undecomposed-note |
// capture-missing) plus the sentinel — never a re-declared regex.
function usageCaptured(run) {
  // decomposed arm: BOTH counts present AND non-negative (bot review: state.mjs
  // currently accepts negative ints; a -1/-1 pair is not honest capture).
  if (run.tokensIn !== null && run.tokensOut !== null
    && run.tokensIn >= 0 && run.tokensOut >= 0) return true;
  if (extractUsageTotal(run.note) !== null) return true;
  if (hasUsageSentinel(run.note)) return true;
  return false;
}

// evaluateUsageCaptureGate(ref) -> { severity, dial?, roles?, reason? }.
// severity 'none' (no gateable gap), 'warn' (report-only dial), or 'refuse'
// (enforce dial). Read-only — the caller decides WARN vs REFUSE-before-write
// (product-doc-gate discipline). Only KNOWN harness-dispatched roles are gated;
// meta-roles (Orchestration, Metrics Flush) and any unrecognized role are never
// gated (conservative — intake Constraints).
function evaluateUsageCaptureGate(ref) {
  const runs = scanAgentRuns(ref);
  const unmarked = runs.filter((r) => isHarnessDispatchedRole(r.role) && !usageCaptured(r));
  if (unmarked.length === 0) return { severity: 'none', roles: [] };
  const dial = readGuardConfig(path.join(ROOT, 'docs/ai')).usage_capture_gate;
  const roles = unmarked.map((r) => r.role);
  const reason =
    `ride "${ref}" carries ${unmarked.length} harness-dispatched run(s) with no usage capture ` +
    `(no usage_total_tokens marker, no decomposed tokens_in/out, no usage_capture=none sentinel): ${roles.join(', ')}`;
  return { severity: dial === 'enforce' ? 'refuse' : 'warn', dial, roles, reason };
}

// --- CLOSE-TIME evidence-path gate (CHANGE-0131 / spec-evidence-path-gate) --
//
// The mechanical checkpoint the CHANGE-0127 incident named as missing: an AC
// Status Evidence cell can cite a docs/ai/tdd/... transcript that resolves
// only inside a worktree that gets deleted, and nothing before this gate ever
// checked whether the bytes an Evidence cell points at exist anywhere. Same
// fail-open guard-config-dial discipline as its two siblings above: WARN
// (report-only, shipped default) or REFUSE pre-write (enforce, opt-in).
// Scans every doc `close-work-item.mjs` already resolved (D5 — the primary
// --ref doc AND, when given, --spec), never a repo-wide sweep.

// resolveEvidenceRoot(root) -> the MAIN checkout's absolute path (PR #245
// Codex P1 / CHANGE-0127 regression). SKILL_PR step 4c runs close-work-item
// FROM a linked git worktree, so resolving citations against ROOT =
// process.cwd() (the worktree itself) lets evidence stranded ONLY in that
// worktree resolve "fine" — defeating the gate's exact purpose. Found the
// same way reconcile-telemetry.mjs's listWorktrees does: `git worktree list
// --porcelain` always lists the main checkout FIRST, linked worktrees after.
// Falls back to `root` unchanged (current behavior, byte-identical) when git
// is unavailable, the command errors, or the porcelain output is
// unparseable — and, with no special-casing needed, when the current tree
// already IS the main checkout: git's first-listed entry then IS `root`
// (mod realpath), so a plain clone resolves to the exact same path either
// way. No new dependency, no network (D10 discipline, same as the rest of
// this gate).
function resolveEvidenceRoot(root) {
  let out;
  try {
    out = execFileSync('git', ['worktree', 'list', '--porcelain'], {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return root;
  }
  const first = out.split('\n').find((l) => l.startsWith('worktree '));
  const mainPath = first ? first.slice('worktree '.length).trim() : '';
  if (!mainPath) return root;
  try {
    return fs.realpathSync(mainPath);
  } catch {
    return path.resolve(mainPath);
  }
}

// evaluateEvidencePathGate(docs, evidenceRoot) -> { severity, dial?,
// unresolved, reason?, resolutionRoot }. severity is 'none' (nothing
// unresolvable across any doc), 'warn' (report-only dial), or 'refuse'
// (enforce dial). Read-only — the caller decides whether/when to act (D8:
// the refuse branch must run BEFORE any write; --dry-run must never act on
// it). `unresolved` is [{ doc, acId, token }] across every scanned doc, in
// scan order. `evidenceRoot` (PR #245 Codex P1) is the MAIN checkout root
// resolved by resolveEvidenceRoot — citations resolve against it, never
// against cwd, so worktree-stranded evidence cannot silently pass; it is
// echoed back as `resolutionRoot` so the behavior stays observable (dry-run
// JSON, docs-audit-relevant tooling).
function evaluateEvidencePathGate(docs, evidenceRoot) {
  const unresolved = [];
  for (const d of docs) {
    for (const { acId, token } of unresolvedCitations(d.content, evidenceRoot)) {
      unresolved.push({ doc: d.rel, acId, token });
    }
  }
  if (unresolved.length === 0) return { severity: 'none', unresolved, resolutionRoot: evidenceRoot };
  const dial = readGuardConfig(path.join(ROOT, 'docs/ai')).evidence_path_gate;
  const reason = unresolved
    .map((u) => `${u.doc} ${u.acId ?? '(unknown AC)'} cites "${u.token}" which does not resolve from the main checkout root`)
    .join('; ');
  return { severity: dial === 'enforce' ? 'refuse' : 'warn', dial, unresolved, reason, resolutionRoot: evidenceRoot };
}

// Best-effort remediation-friction capture. Fires ONLY on a real close (called
// once from the main() success path). Isolation mirrors the wrapper's capture
// point: honors the AAI_FRICTION_CAPTURE off-switch, and writes only when the
// resolved spool DIR already exists (a fixture repo lacking docs/ai/friction can
// never be polluted). Every failure is swallowed — the close outcome is the sole
// contract.
function captureRemediationFriction(ref) {
  try {
    if (process.env.AAI_FRICTION_CAPTURE === '0') return;
    const n = countRemediationRuns(ref);
    if (n <= 0) return;
    const spoolDir = process.env.AAI_FRICTION_SPOOL_DIR || path.join(ROOT, 'docs', 'ai', 'friction');
    if (!fs.existsSync(spoolDir) || !fs.statSync(spoolDir).isDirectory()) return;
    const cli = path.join(SCRIPT_DIR, 'aai-friction.mjs');
    if (!fs.existsSync(cli)) return;
    // observed_behavior is deliberately GENERIC (no ref/count) so recurring
    // remediation load clusters to ONE fingerprint; the ref+count go to the
    // operator-visible INFO line, never to the persisted (leak-free) record.
    const obs = {
      schema_version: 2,
      skill_id: 'close-work-item',
      skill_phase: 'close',
      failure_class: 'abstraction_leak_recovery',
      expected_behavior: 'a ride reaches close-work-item with no remediation rounds',
      observed_behavior: 'a completed ride reached close carrying one or more remediation runs',
      impact: 'low',
      confidence: 'low',
    };
    execFileSync('node', [cli, 'record', '--input', '-'], {
      input: JSON.stringify(obs),
      stdio: ['pipe', 'ignore', 'ignore'],
      cwd: ROOT,
      env: { ...process.env, AAI_FRICTION_SPOOL_DIR: spoolDir },
    });
    process.stderr.write(
      `close-work-item: INFO friction observation recorded (${ref} carried ${n} remediation run(s))\n`
    );
  } catch (err) {
    process.stderr.write(
      `close-work-item: INFO friction capture skipped (best-effort, non-fatal): ${err.message}\n`
    );
  }
}

// For each closed ref, assert the REAL audit classifies it tracked-done /
// aligned with no missing-close-telemetry entry (Spec-AC-02). The audit
// engine is the oracle — no heuristic is re-implemented here.
function findProblems(audit, refs) {
  const problems = [];
  for (const ref of refs) {
    const doc = audit.docs.find((d) => d.id === ref);
    if (!doc) {
      problems.push(`${ref}: not found in the docs-audit scan`);
      continue;
    }
    if (doc.cls !== 'tracked-done' || doc.verdict !== 'aligned') {
      problems.push(`${ref}: cls=${doc.cls} verdict=${doc.verdict ?? '—'} reasons=${(doc.reasons || []).join('; ') || '—'}`);
    }
    if (audit.missingCloseTelemetry.some((m) => m.id === ref)) {
      problems.push(`${ref}: missing-close-telemetry`);
    }
  }
  return problems;
}

// D6.4 — regenerate the INDEX, run the REAL audit, and report every problem
// for `refs`. Shared by both self-verify call sites (the idempotency
// short-circuit and the post-apply verify) so the two paths can never drift.
function selfVerify(refs) {
  regenerateIndex();
  return findProblems(runAudit(ROOT, {}), refs);
}

// --- rollback (D6.5) ----------------------------------------------------------

function rollback(snapshot, eventsSnapshotLen) {
  for (const [abs, original] of snapshot) {
    fs.writeFileSync(abs, original);
  }
  if (fs.existsSync(EVENTS_PATH)) {
    const fd = fs.openSync(EVENTS_PATH, 'r+');
    try {
      fs.ftruncateSync(fd, eventsSnapshotLen);
    } finally {
      fs.closeSync(fd);
    }
  }
}

// --- --stamp-pr mode (fu-close-requires-pr-before-it-exists) ----------------
//
// A NARROW, SEPARATE transaction from the main close: it replaces the TBD
// placeholder a prior `--pr TBD` close stamped with the real PR number, once
// the PR exists (.aai/SKILL_PR.prompt.md step 5c, run right after `gh pr
// create`/`az repos pr create` returns N). It never re-runs the status flip,
// never re-emits doc_lifecycle/work_item_closed/ac_evidence (those already
// happened, self-verified, at the original close) — only links.pr changes.
// Same D6-style discipline as the main transaction: snapshot -> apply ->
// self-verify against the REAL audit engine -> rollback on any drift.
// Returns the process exit code (0 success/no-op, 1 self-verify failed
// (rolled back), 2 usage error).
function runStampPr(args) {
  const slugs = [args.ref, ...(args.spec ? [args.spec] : [])];
  const n = String(args.stampPr);

  const resolved = [];
  for (const slug of slugs) {
    const r = resolveDoc(ROOT, slug);
    if (!r.found) {
      process.stderr.write(`close-work-item: ${r.reasons.join('; ')}\n`);
      return 2;
    }
    if (!r.doc.fmId) {
      process.stderr.write(`close-work-item: doc ${r.doc.rel} (${slug}) has no frontmatter "id:" — cannot resolve a stable slug ref\n`);
      return 2;
    }
    const status = String(r.doc.fm?.status ?? '').toLowerCase();
    if (status !== 'done') {
      process.stderr.write(
        `close-work-item: doc ${r.doc.rel} (${slug}) has status "${status || '(none)'}", not "done" — ` +
          'the close ceremony has not run yet; run it with --pr TBD BEFORE --stamp-pr\n'
      );
      return 2;
    }
    resolved.push({ slug, ...r.doc, status });
  }

  emitStaleTbdWarning(scanForStaleTbdPr(ROOT, resolved.map((d) => d.fmId)));

  const plan = resolved.map((d) => ({
    ...d,
    alreadyStamped: hasLinkValue(d.content, 'pr', n),
    hasTbd: hasLinkValue(d.content, 'pr', TBD_SENTINEL),
  }));

  const needsWrite = plan.filter((p) => !p.alreadyStamped);
  if (needsWrite.length === 0) {
    console.log(`close-work-item: nothing to do (already stamped pr #${n}) for ${resolved.map((d) => d.fmId).join(', ')}`);
    return 0;
  }
  const missingTbd = needsWrite.filter((p) => !p.hasTbd);
  if (missingTbd.length > 0) {
    for (const p of missingTbd) {
      process.stderr.write(
        `close-work-item: doc ${p.rel} (${p.fmId}) has no TBD placeholder in links.pr to stamp — ` +
          'this doc was not closed with --pr TBD; use the full close ceremony\'s --pr <N> instead\n'
      );
    }
    return 2;
  }

  const snapshot = new Map(plan.map((p) => [p.abs, p.content]));
  try {
    for (const p of needsWrite) {
      const split = splitFrontmatter(p.content);
      if (!split) throw new Error(`cannot locate a frontmatter block to mutate (${p.rel})`);
      const lines = split.head.split(split.eol);
      replaceLinkValue(lines, 'pr', TBD_SENTINEL, n);
      fs.writeFileSync(p.abs, lines.join(split.eol) + split.rest);
    }
    const refs = resolved.map((d) => d.fmId);
    const problems = selfVerify(refs);
    if (problems.length > 0) {
      rollback(snapshot, fs.existsSync(EVENTS_PATH) ? fs.statSync(EVENTS_PATH).size : 0);
      try {
        regenerateIndex();
      } catch {
        /* best-effort revert of the INDEX; the doc rollback above is what matters */
      }
      process.stderr.write('close-work-item: post-stamp audit not CLEAN — rolled back. Findings:\n');
      for (const p of problems) process.stderr.write(`  - ${p}\n`);
      return 1;
    }
  } catch (err) {
    rollback(snapshot, fs.existsSync(EVENTS_PATH) ? fs.statSync(EVENTS_PATH).size : 0);
    try {
      regenerateIndex();
    } catch {
      /* best-effort revert of the INDEX; the doc rollback above is what matters */
    }
    process.stderr.write(`close-work-item: internal error — rolled back (${err.message})\n`);
    return 1;
  }

  console.log(`close-work-item: stamped pr TBD -> #${n} for ${resolved.map((d) => d.fmId).join(', ')}`);
  return 0;
}

// Best-effort prune of each closed doc's Planning-emitted work-item brief
// (docs/ai/briefs/<REF-ID>.md — a gitignored runtime handoff artifact, like
// docs/ai/reports/). The brief is consumed once the item is durably closed, so
// leaving it on disk only lets stale briefs accumulate for done items.
//
// PLANNING step 11 names the brief by `<REF-ID>`, which is historically EITHER
// the frontmatter slug `id` (e.g. friction-capture-foundation.md) OR the numbered
// display id (e.g. CHANGE-0027.md) — both forms exist on disk. So for each closed
// doc we prune every candidate name: the slug (fmId) AND each display id
// (fileIds), deduped (bot-review P2: display-ID briefs were being missed).
//
// Runs ONLY after the self-verified close: a missing brief, an unlink error, or a
// name that could escape the briefs dir is silently skipped — the close is the
// durable outcome and must never fail on a housekeeping unlink. A later re-plan
// regenerates the brief, so removal here is safe.
function pruneBriefs(plan) {
  const names = new Set();
  for (const d of plan) {
    for (const id of [d.fmId, ...(d.fileIds || [])]) {
      if (id) names.add(id);
    }
  }
  const pruned = [];
  for (const name of names) {
    if (name.includes('/') || name.includes('\\') || name.includes('..')) continue;
    const p = path.join(ROOT, 'docs/ai/briefs', `${name}.md`);
    try {
      if (fs.existsSync(p)) {
        fs.rmSync(p);
        pruned.push(`${name}.md`);
      }
    } catch {
      /* best-effort housekeeping; the close already succeeded */
    }
  }
  return pruned;
}

// --- STATE RECONCILE (D1-D6, spec-close-leaves-state-stale) ------------------
//
// planStateReconcile is PURE and read-only: it never writes a byte, never
// shells out, and never calls process.exit — it is evaluated pre-write,
// alongside the three existing gates above, purely to compute a plan.
// applyStateReconcile is the ONLY function that shells out to the sanctioned
// `state.mjs` CLI (D2), and main() calls it strictly AFTER the existing
// try/catch has proved the close CLEAN (D3) — outside that block's rollback
// scope by construction.

// Closed sets MIRRORING state.mjs's own CLI enums (PHASES, FOCUS_TYPES).
// state.mjs cannot be imported as a library for these — its main() runs
// unconditionally at import (no import.meta.url guard), so importing it here
// would execute its own argv-parsing CLI path. A narrow, bounded duplication
// of two small closed sets instead of a live import of the protected file.
const RECONCILE_PHASES = new Set(['planning', 'preparation', 'implementation', 'validation', 'code_review', 'remediation']);
const RECONCILE_FOCUS_TYPES = new Set(['intake_change', 'intake_issue', 'intake_prd', 'intake_hotfix',
  'intake_research', 'intake_rfc', 'intake_release', 'technology_extraction', 'maintenance', 'none']);
const RECONCILE_REF_RE = /^[A-Z]+-\d+$/;
const RECONCILE_SLUG_RE = /^(?=[a-z0-9-]{3,53}$)[a-z0-9]+(?:-[a-z0-9]+)*$/;

function reconcileRefShapeOk(v) {
  return typeof v === 'string' && (RECONCILE_REF_RE.test(v) || RECONCILE_SLUG_RE.test(v));
}

// Read a current_focus scalar, unquoted (readScalar itself never unquotes —
// every other caller of it in this codebase pairs it with unquoteScalar).
function readFocusScalar(lines, field) {
  const v = readScalar(lines, 'current_focus', field);
  return v === null ? null : unquoteScalar(v);
}

// Parse active_work_items into [{ ref_id, status, phase, spec_path,
// primary_path }] — a read-only mirror of orchestration-dispatch.mjs's own
// parseWorkItems (that function is local/unexported there; no shared export
// exists for this one-level-deep item scan).
function parseActiveWorkItems(lines) {
  const b = findBlock(lines, 'active_work_items');
  if (!b) return [];
  const items = [];
  let cur = null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (l.trim() === '' || l.trim().startsWith('#')) continue;
    if (/^ {2}- /.test(l)) { cur = {}; items.push(cur); }
    if (!cur) continue;
    const indent = l.length - l.trimStart().length;
    const m = l.match(/^(?: {2}- | {4})([\w-]+):\s*(.*)$/);
    if (m && indent <= 4) {
      const v = m[2].trim();
      cur[m[1]] = v === '' || v === 'null' ? null : unquoteScalar(v);
    }
  }
  return items;
}

// planStateReconcile(root, resolved, args) -> { severity: 'none'|'skip'|'apply',
// reason?, statePath, commands: [[bin, args[]]], echo: [string] }. `resolved`
// is close-work-item's own already-resolved doc list (resolved[0] the primary
// --ref doc; resolved[1] the --spec doc when given) — resolveDoc's `rel` is
// reused verbatim as the path STATE should carry (D1), never re-derived.
function planStateReconcile(root, resolved, args) {
  const statePath = path.join(root, 'docs/ai/STATE.yaml');
  const none = () => ({ severity: 'none', statePath, commands: [], echo: [] });
  const skip = (reason) => ({ severity: 'skip', reason, statePath, commands: [], echo: [] });

  // STATE absent -> none, silently — the same non-regression property
  // scanAgentRuns/countRemediationRuns already have for a fixture repo with
  // no STATE.yaml (D1 Surface 1 bullet).
  if (!fs.existsSync(statePath)) return none();

  let rawLines;
  try {
    rawLines = splitLines(fs.readFileSync(statePath, 'utf8')).lines;
  } catch (err) {
    return skip(`STATE unreadable: ${err.message}`);
  }
  // Pre-check duplicate top-level keys OURSELVES before calling the protected
  // loadState(): loadState() refuses via engineFail(), which calls
  // exit() directly and is NOT catchable — invoking it against an
  // already-corrupt STATE would hard-crash this whole close. A STATE defect
  // must never block a verified close (Article 4 / D3), so this precondition
  // is guaranteed before loadState() is ever reached, and its own duplicate-
  // key branch is therefore provably unreachable from here.
  const dups = duplicateKeys(rawLines);
  if (dups.length > 0) {
    return skip(`STATE has duplicate top-level key(s) [${dups.map((d) => `${d.key} x${d.count}`).join(', ')}] — cannot safely reconcile`);
  }
  const { lines } = loadState(statePath);

  // D5 — identity set: the PRIMARY doc's frontmatter fmId plus its display
  // fileIds (the same two-pass identity resolveDoc uses). The --spec doc
  // never contributes identity — a close's spec ref is never itself a valid
  // active_work_items/current_focus key.
  const primary = resolved[0];
  const identity = new Set([primary.fmId, ...(primary.fileIds || [])].filter(Boolean));
  const targetPrimaryPath = primary.rel;
  const targetSpecPath = args.spec ? resolved[1].rel : undefined;

  const commands = [];
  const echo = [];
  let reason = null;

  // --- work-item arm -----------------------------------------------------
  const items = parseActiveWorkItems(lines);
  const item = items.find((it) => it.ref_id && identity.has(it.ref_id));
  if (item) {
    if (!item.phase || !RECONCILE_PHASES.has(item.phase)) {
      reason = `active_work_items[${item.ref_id ?? '?'}].phase "${item.phase ?? ''}" is absent/outside the CLI's phase enum — skipping the STATE reconcile`;
    } else if (!reconcileRefShapeOk(item.ref_id)) {
      reason = `active_work_items ref "${item.ref_id}" matches neither the display shape ^[A-Z]+-\\d+$ nor the slug shape — skipping the STATE reconcile`;
    } else {
      const needsStatus = item.status !== 'done';
      const needsPrimary = item.primary_path !== targetPrimaryPath;
      const needsSpec = targetSpecPath !== undefined && item.spec_path !== targetSpecPath;
      if (needsStatus || needsPrimary || needsSpec) {
        const cliArgs = ['set-phase', '--ref', item.ref_id, '--phase', item.phase, '--status', 'done', '--path', targetPrimaryPath];
        if (targetSpecPath !== undefined) cliArgs.push('--spec-path', targetSpecPath);
        commands.push(['node', [STATE_CLI, ...cliArgs]]);
        echo.push(`node .aai/scripts/state.mjs ${cliArgs.join(' ')}`);
      }
    }
  }

  // --- focus arm -----------------------------------------------------------
  if (reason === null) {
    const focusRefId = readFocusScalar(lines, 'ref_id');
    if (focusRefId && identity.has(focusRefId)) {
      const focusType = readFocusScalar(lines, 'type');
      if (!focusType || !RECONCILE_FOCUS_TYPES.has(focusType)) {
        reason = `current_focus.type "${focusType ?? ''}" is absent/outside the CLI's type enum — skipping the STATE reconcile`;
      } else if (!reconcileRefShapeOk(focusRefId)) {
        reason = `current_focus.ref_id "${focusRefId}" matches neither the display shape ^[A-Z]+-\\d+$ nor the slug shape — skipping the STATE reconcile`;
      } else {
        const focusPrimaryPath = readFocusScalar(lines, 'primary_path');
        const focusSpecPath = readFocusScalar(lines, 'spec_path');
        const needsPrimary = focusPrimaryPath !== targetPrimaryPath;
        const needsSpec = targetSpecPath !== undefined && focusSpecPath !== targetSpecPath;
        if (needsPrimary || needsSpec) {
          const cliArgs = ['set-focus', '--type', focusType, '--ref', focusRefId, '--path', targetPrimaryPath];
          if (targetSpecPath !== undefined) cliArgs.push('--spec-path', targetSpecPath);
          commands.push(['node', [STATE_CLI, ...cliArgs]]);
          echo.push(`node .aai/scripts/state.mjs ${cliArgs.join(' ')}`);
        }
      }
    }
  }

  if (reason !== null) return skip(reason);
  if (commands.length === 0) return none();
  return { severity: 'apply', statePath, commands, echo };
}

// applyStateReconcile(plan) -> { applied, total, failedAt, childStderr }.
// Runs each planned command in order via execFileSync; env is NEVER touched
// (D4 — the AAI_ROLE=subagent marker, if present, must reach the child
// unfiltered so the R-GUARD refusal fires there, not here). Stops at the
// first failure: `failedAt` is that command's index (0 = the first command
// itself failed — a nothing-written WARN per D3), or -1 when every command
// applied.
function applyStateReconcile(plan) {
  let applied = 0;
  let failedAt = -1;
  let childStderr = '';
  for (let i = 0; i < plan.commands.length; i += 1) {
    const [bin, cmdArgs] = plan.commands[i];
    try {
      execFileSync(bin, cmdArgs, { stdio: ['ignore', 'ignore', 'pipe'], cwd: ROOT });
      applied += 1;
    } catch (err) {
      failedAt = i;
      childStderr = err.stderr ? err.stderr.toString() : (err.message || '');
      break;
    }
  }
  return { applied, total: plan.commands.length, failedAt, childStderr };
}

// One stderr line (Spec-AC-03: "exactly one stderr line"), naming the reason
// and echoing every planned command verbatim.
function emitStateReconcileWarn(reason, echoCommands) {
  const cmdsText = echoCommands.length > 0 ? ` — run: ${echoCommands.join(' ; ')}` : '';
  process.stderr.write(`close-work-item: WARN (state-reconcile) — ${reason}${cmdsText}\n`);
}

// Multi-line block (D3: "a close-work-item: PARTIAL (state-reconcile) block"),
// naming applied-of-total and echoing the remaining commands verbatim.
function emitStateReconcilePartial(applied, total, remaining) {
  process.stderr.write(
    `close-work-item: PARTIAL (state-reconcile) — ${applied} of ${total} state.mjs command(s) applied; `
    + 'STATE.yaml is PARTIALLY reconciled. Remaining command(s) to run manually:\n'
  );
  for (const cmd of remaining) process.stderr.write(`  ${cmd}\n`);
}

// D6 — worktree advisory: when this close ran from a linked worktree, the
// STATE the reconcile just wrote is THIS checkout's own (gitignored, distinct
// from the main checkout's) — name both so the operator is never surprised
// that the main checkout's STATE stayed stale.
function emitStateReconcileWorktreeAdvisory(root, evidenceRoot, statePath) {
  if (evidenceRoot === root) return;
  process.stderr.write(
    `close-work-item: INFO state-reconcile wrote ${statePath} (this worktree's own STATE); `
    + `the main checkout's STATE at ${path.join(evidenceRoot, 'docs/ai/STATE.yaml')} is untouched\n`
  );
}

// runStateReconcile(statePlan, evidenceRoot) -> the close's own trailing exit
// code (0 normally, 6 on a genuine mid-apply PARTIAL, D3). Shared by BOTH
// success tails (the D6.2 idempotency short-circuit and the full close
// success path) so the two can never classify a WARN/PARTIAL differently.
function runStateReconcile(statePlan, evidenceRoot) {
  if (statePlan.severity === 'none') return 0;
  if (statePlan.severity === 'skip') {
    emitStateReconcileWarn(statePlan.reason, statePlan.echo);
    return 0;
  }
  const result = applyStateReconcile(statePlan);
  if (result.applied > 0) emitStateReconcileWorktreeAdvisory(ROOT, evidenceRoot, statePlan.statePath);
  if (result.failedAt === 0) {
    const detail = result.childStderr ? result.childStderr.trim().split('\n')[0] : 'state.mjs exited non-zero';
    emitStateReconcileWarn(`state.mjs command failed (${detail})`, statePlan.echo);
    return 0;
  }
  if (result.failedAt > 0) {
    const remaining = statePlan.echo.slice(result.failedAt);
    emitStateReconcilePartial(result.applied, result.total, remaining);
    return 6;
  }
  return 0;
}

// --- main ----------------------------------------------------------------------

function main() {
  const args = parseArgs(process.argv.slice(2));

  // fu-close-requires-pr-before-it-exists — --stamp-pr is a SEPARATE, narrow
  // mode: dispatch it before any of the main close-transaction resolution/
  // gate logic below, which does not apply to it.
  if (args.stampPr !== null) {
    exit(runStampPr(args));
    return;
  }

  const slugs = [args.ref, ...(args.spec ? [args.spec] : [])];

  // role-verification-guards G1 — post-merge-close advisory, evaluated ONCE
  // per invocation before any resolution or write (report-only; --dry-run
  // already reports everything informationally in its own JSON, so this line
  // is suppressed there too, matching the three gates below).
  if (!args.dryRun) emitPostMergeCloseWarning(ROOT, args.commit, args.pr);
  // fu-close-requires-pr-before-it-exists — "must not go unfilled": a stale
  // TBD left by an EARLIER close on a DIFFERENT ref is reported here too, on
  // every close-work-item.mjs invocation repo-wide (report-only; never
  // refuses THIS close).
  if (!args.dryRun) emitStaleTbdWarning(scanForStaleTbdPr(ROOT, slugs));

  // D2 + D3 — resolve EVERY doc and validate its status BEFORE any write
  // (D7 pair pre-write abort: either failing aborts the whole transaction).
  const resolved = [];
  for (const slug of slugs) {
    const r = resolveDoc(ROOT, slug);
    if (!r.found) {
      process.stderr.write(`close-work-item: ${r.reasons.join('; ')}\n`);
      exit(2);
    }
    // code-review B3 fix-at-cause: reject a doc with no usable frontmatter
    // "id:" (resolved only via the display-id fallback) BEFORE any write.
    // Without this guard, refs downstream carry `null` (D5's ref form),
    // status validation passes, applyDocMutation writes the frontmatter
    // mutation, and emitEvent(..., null, ...) only THEN throws inside
    // execFileSync — caught by the generic internal-error handler, which
    // rolls back correctly but wastes a whole apply/rollback cycle on a
    // usage error that was knowable up front.
    if (!r.doc.fmId) {
      process.stderr.write(
        `close-work-item: doc ${r.doc.rel} (${slug}) has no frontmatter "id:" — cannot resolve a stable slug ref for close events; add an "id:" key before closing\n`
      );
      exit(2);
    }
    const status = String(r.doc.fm?.status ?? '').toLowerCase();
    if (!status) {
      process.stderr.write(`close-work-item: doc ${r.doc.rel} (${slug}) has no frontmatter status\n`);
      exit(2);
    }
    if (status !== 'done' && !FLIP_ELIGIBLE.has(status)) {
      process.stderr.write(
        `close-work-item: doc ${r.doc.rel} (${slug}) has non-done-terminal status "${status}" — refusing to reopen/repurpose\n`
      );
      exit(2);
    }
    resolved.push({ slug, ...r.doc, status });
  }

  // D3 — product-doc gate: evaluated for the PRIMARY doc (resolved[0] ==
  // args.ref, D1) directly after resolution + status validation, BEFORE
  // anything else that could write (including the idempotency short-circuit's
  // own INDEX regen below) -- a refusal must write nothing (hard constraint).
  // --dry-run reports the verdict informationally in its JSON further below
  // and always writes nothing / exits 0 regardless of the dial, so the
  // refuse/warn branches here are skipped for it.
  const productDocGate = evaluateProductDocGate(resolved[0]);
  if (!args.dryRun && productDocGate.severity === 'refuse') {
    process.stderr.write(`close-work-item: REFUSED (product-doc gate) — ${productDocGate.reason}\n`);
    exit(3);
  }
  if (!args.dryRun && productDocGate.severity === 'warn') {
    process.stderr.write(`close-work-item: WARNING (product-doc gate) — ${productDocGate.reason}\n`);
  }

  // spec-telemetry-completeness (Enforcement design A) — close-time
  // usage-capture gate for the PRIMARY ride (resolved[0].fmId, the STATE
  // work_items key). Same pre-write discipline as the product-doc gate above:
  // evaluated BEFORE anything that could write (including the idempotency
  // short-circuit's INDEX regen); --dry-run reports the verdict in its JSON
  // below and never acts on it.
  const usageGate = evaluateUsageCaptureGate(resolved[0].fmId);
  if (!args.dryRun && usageGate.severity === 'refuse') {
    process.stderr.write(`close-work-item: REFUSED (usage-capture gate) — ${usageGate.reason}\n`);
    exit(4);
  }
  if (!args.dryRun && usageGate.severity === 'warn') {
    process.stderr.write(`close-work-item: WARNING (usage-capture gate) — ${usageGate.reason}\n`);
  }

  // CHANGE-0131 / spec-evidence-path-gate — close-time evidence-path gate for
  // EVERY resolved doc (D5: primary --ref, and --spec when given). Same
  // pre-write discipline as the two gates above: evaluated BEFORE anything
  // that could write (including the idempotency short-circuit's INDEX regen
  // below, D8); --dry-run reports the verdict in its JSON below and never
  // acts on it.
  const evidenceRoot = resolveEvidenceRoot(ROOT);
  const evidenceGate = evaluateEvidencePathGate(resolved, evidenceRoot);
  if (!args.dryRun && evidenceGate.severity === 'refuse') {
    process.stderr.write(`close-work-item: REFUSED (evidence-path gate) — ${evidenceGate.reason}\n`);
    exit(5);
  }
  if (!args.dryRun && evidenceGate.severity === 'warn') {
    process.stderr.write(`close-work-item: WARNING (evidence-path gate) — ${evidenceGate.reason}\n`);
  }

  // spec-close-leaves-state-stale D1 — plan the STATE reconcile pre-write,
  // alongside the three gates above. PURE: computes what WOULD run; nothing
  // is written or executed here (that happens strictly after self-verify,
  // via runStateReconcile() near the two success tails below).
  const statePlan = planStateReconcile(ROOT, resolved, args);

  const events = readEvents(ROOT);
  const plan = resolved.map((d) => ({
    ...d,
    needsFlip: d.status !== 'done',
    needsPr: !hasLinkValue(d.content, 'pr', args.pr),
    needsCommit: !hasLinkValue(d.content, 'commits', args.commit),
    needsClosedEvent: !hasWorkItemClosed(events, d.fmId),
    needsAcEvidence: !hasAcEvidence(events, d.fmId, args.commit),
  }));
  const anyMutation = plan.some((p) => p.needsFlip || p.needsPr || p.needsCommit || p.needsClosedEvent || p.needsAcEvidence);

  // spec-product-docs-capability-model D3 (SEAM-2/SEAM-3) — when the gate did
  // not refuse and a REAL product doc exists at the resolved capability path
  // (the ship flow authors it from the template BEFORE close runs), plan the
  // delivered_by/updated upsert inside the SAME snapshot/rollback transaction
  // (D6) as the primary/spec doc mutations below. A missing product doc
  // (warn dial, nothing on disk yet) has nothing to upsert into — the ship
  // flow's create-else-update step owns creation, not this ceremony.
  let productDocPlan = null;
  if (productDocGate.userVisible && productDocGate.productDocExists) {
    const abs = path.join(ROOT, productDocGate.productDocPath);
    const content = fs.readFileSync(abs, 'utf8');
    const mutated = applyProductDocMutation(content, resolved[0].fmId);
    productDocPlan = { abs, content, mutated, needsUpdate: mutated !== content };
  }
  // Spec-AC-02's self-recovery does not hinge on anyMutationTotal: BOTH tails
  // below (the idempotency short-circuit and the full write path) end by
  // calling runStateReconcile(statePlan, ...), so a repo whose docs/events
  // are already closed but whose STATE is stale still reconciles on a re-run
  // either way — through the short-circuit's own tail when no doc/product-doc
  // mutation is needed. anyMutationTotal only selects WHICH tail runs (and
  // therefore whether the four best-effort regens/pruneBriefs run), never
  // whether the STATE reconcile itself runs.
  const anyMutationTotal = anyMutation || Boolean(productDocPlan && productDocPlan.needsUpdate);

  if (args.dryRun) {
    console.log(JSON.stringify(
      {
        anyMutation: anyMutationTotal,
        productDocGate,
        usageCaptureGate: usageGate,
        evidencePathGate: evidenceGate,
        stateReconcile: { severity: statePlan.severity, reason: statePlan.reason ?? null, statePath: statePlan.statePath, commands: statePlan.echo },
        productDocUpdate: productDocPlan
          ? { path: productDocGate.productDocPath, needsUpdate: productDocPlan.needsUpdate }
          : null,
        plan: plan.map((p) => ({
          ref: p.fmId,
          rel: p.rel,
          from: p.status,
          to: 'done',
          needsFlip: p.needsFlip,
          needsPr: p.needsPr,
          needsCommit: p.needsCommit,
          needsClosedEvent: p.needsClosedEvent,
          needsAcEvidence: p.needsAcEvidence,
        })),
      },
      null,
      2
    ));
    exit(0);
  }

  const refs = plan.map((p) => p.fmId);

  if (!anyMutationTotal) {
    // D6.2 — idempotency short-circuit: nothing to write, but still
    // self-verify (nothing to roll back if this somehow fails — no write
    // happened this run).
    const problems = selfVerify(refs);
    if (problems.length > 0) {
      process.stderr.write('close-work-item: already-closed state failed self-verify (no write made this run):\n');
      for (const p of problems) process.stderr.write(`  - ${p}\n`);
      exit(1);
    }
    console.log(`close-work-item: nothing to do (already closed) for ${refs.join(', ')}`);
    // statePlan.severity can be 'none', 'skip', OR 'apply' here — this tail
    // runs the reconcile itself (Spec-AC-02), so a stale-STATE-only repo
    // still self-recovers without ever routing through the write path above.
    exit(runStateReconcile(statePlan, evidenceRoot));
  }

  // D6.1 — SNAPSHOT before any write. The product doc (when planned) joins
  // the SAME snapshot map so a self-verify failure rolls it back too
  // (spec-product-docs-capability-model D3: "inside the existing snapshot/
  // rollback transaction").
  const snapshot = new Map(plan.map((p) => [p.abs, p.content]));
  if (productDocPlan) snapshot.set(productDocPlan.abs, productDocPlan.content);
  const eventsSnapshotLen = fs.existsSync(EVENTS_PATH) ? fs.statSync(EVENTS_PATH).size : 0;

  try {
    // D6.3 — APPLY: every doc's frontmatter first, THEN the product-doc
    // upsert, THEN every doc's events (status-flip-first ordering — a still-
    // open doc never carries a close event, so probable-false-open's Arm C
    // can never self-flag mid-close).
    for (const p of plan) {
      const mutated = applyDocMutation(p.content, {
        toStatus: p.needsFlip ? 'done' : null,
        pr: args.pr,
        commit: args.commit,
      });
      if (mutated !== p.content) fs.writeFileSync(p.abs, mutated);
    }
    if (productDocPlan && productDocPlan.needsUpdate) {
      fs.writeFileSync(productDocPlan.abs, productDocPlan.mutated);
    }
    for (const p of plan) {
      if (p.needsFlip) emitEvent('doc_lifecycle', p.fmId, ['--from', p.status, '--to', 'done']);
      if (p.needsClosedEvent) emitEvent('work_item_closed', p.fmId, ['--validation', 'pass', '--code-review', args.review]);
      if (p.needsAcEvidence) emitEvent('ac_evidence', p.fmId, ['--commit', args.commit]);
    }

    // D6.4 — SELF-VERIFY against the REAL audit engine (the oracle).
    const problems = selfVerify(refs);
    if (problems.length > 0) {
      rollback(snapshot, eventsSnapshotLen);
      try {
        regenerateIndex();
      } catch {
        /* best-effort revert of the INDEX; the doc/EVENTS rollback above is what matters */
      }
      process.stderr.write('close-work-item: post-close audit not CLEAN — rolled back. Findings:\n');
      for (const p of problems) process.stderr.write(`  - ${p}\n`);
      exit(1);
    }
  } catch (err) {
    rollback(snapshot, eventsSnapshotLen);
    try {
      regenerateIndex();
    } catch {
      /* best-effort revert of the INDEX; the doc/EVENTS rollback above is what matters */
    }
    process.stderr.write(`close-work-item: internal error — rolled back (${err.message})\n`);
    exit(1);
  }

  const pruned = pruneBriefs(plan);
  const briefNote = pruned.length
    ? ` (pruned brief${pruned.length > 1 ? 's' : ''}: ${pruned.join(', ')})`
    : '';
  console.log(
    `close-work-item: closed ${refs.join(', ')} (pr #${args.pr}, commit ${args.commit})${briefNote}`
  );
  regenerateOverviewBestEffort();
  regenerateUserguideRollupBestEffort();
  regenerateDocsHubBestEffort();
  regenerateFactoryReportBestEffort();
  // CAPTURE POINT 2 (deterministic friction): strictly last, best-effort — a
  // capture failure never changes the exit code and never reaches rollback. Only
  // the primary --ref ride's remediation load is summarized (the anchor doc).
  captureRemediationFriction(resolved[0].fmId);
  // spec-close-leaves-state-stale D3 — STATE RECONCILE, strictly AFTER the
  // try/catch above has proved the close CLEAN: OUTSIDE that block's rollback
  // scope by construction. Never affects the doc/event transaction; only its
  // own 0/6 tail.
  exit(runStateReconcile(statePlan, evidenceRoot));
}

runMain(() => main(), {
  onError(err) {
    process.stderr.write(`close-work-item: internal error (${err.message})\n`);
    process.exitCode = 1;
  },
});
