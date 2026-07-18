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
// GRAMMAR (D1, closed)
//   node .aai/scripts/close-work-item.mjs --ref <slug> --pr <N> --commit <sha>
//     [--spec <spec-slug>] [--review <pass|waived|none>] [--dry-run]
//   --ref <slug>     the primary work-item doc's frontmatter slug `id`
//                     (change/issue/debt/spec). Required.
//   --pr <N>         PR number stamped into links.pr (integer; required).
//   --commit <sha>   delivery commit stamped into links.commits AND used as
//                     the ac_evidence commit (required).
//   --spec <slug>    optional second doc (the spec) closed in the SAME
//                     transaction as the primary doc.
//   --review <t>     the code_review token for work_item_closed; optional,
//                     default "none" (validation is always "pass" — this
//                     ceremony only runs after a PASS).
//   --dry-run        print the planned mutation + event set as JSON, write
//                     nothing, exit 0.
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
//
// Node stdlib only (docs/TECHNOLOGY.md). Reuses append-event.mjs verbatim
// (no forked event schema) and the shared docs-audit engine (no re-implemented
// heuristics — the real audit is the self-verify oracle).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { scanAuditDocs, loadConfig, runAudit, readEvents } from './lib/docs-audit-core.mjs';
import { parseFrontmatter, extractDocIds, DEFAULT_CATEGORY_PREFIXES } from './lib/docs-model.mjs';

const ROOT = process.cwd();
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const EVENTS_PATH = path.join(ROOT, 'docs/ai/EVENTS.jsonl');
const APPEND_EVENT = path.join(SCRIPT_DIR, 'append-event.mjs');
const GENERATE_INDEX = path.join(SCRIPT_DIR, 'generate-docs-index.mjs');

// D3 — flip-eligible statuses. `done` is handled separately (no-op). Every
// other status (deferred | rejected | superseded | anything unrecognized) is
// a fatal usage error: the close ceremony never silently reopens/repurposes
// a terminal non-done doc.
const FLIP_ELIGIBLE = new Set(['draft', 'implementing', 'accepted']);

function usageError(msg) {
  process.stderr.write(`close-work-item: ${msg}\n`);
  process.stderr.write(
    'usage: node .aai/scripts/close-work-item.mjs --ref <slug> --pr <N> --commit <sha> ' +
      '[--spec <spec-slug>] [--review <pass|waived|none>] [--dry-run]\n'
  );
  process.exit(2);
}

function parseArgs(argv) {
  const args = { spec: null, review: 'none', dryRun: false };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--ref') args.ref = argv[++i];
    else if (tok === '--pr') args.pr = argv[++i];
    else if (tok === '--commit') args.commit = argv[++i];
    else if (tok === '--spec') args.spec = argv[++i];
    else if (tok === '--review') args.review = argv[++i];
    else if (tok === '--dry-run') args.dryRun = true;
    else usageError(`unrecognized flag: ${tok}`);
  }
  if (!args.ref) usageError('missing --ref');
  if (!args.pr || !/^\d+$/.test(String(args.pr))) usageError('missing or invalid --pr (integer required)');
  if (!args.commit) usageError('missing --commit');
  if (!['pass', 'waived', 'none'].includes(args.review)) usageError('--review must be one of pass|waived|none');
  return args;
}

// --- doc resolution (D2 — the SAME two-pass scan docs-audit's gateDoc uses) --

function resolveDoc(root, slug) {
  const config = loadConfig(root);
  const files = scanAuditDocs(root, { scanExclude: config?.scan_exclude ?? [] });
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

function stampStatus(lines, toStatus) {
  const idx = lines.findIndex((l) => /^status:/.test(l));
  if (idx === -1) throw new Error('frontmatter has no top-level "status:" key');
  lines[idx] = `status: ${toStatus}`;
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

// --- self-verify (D6.4) -------------------------------------------------------

// code-review B1 fix-at-cause: THROW on failure instead of calling
// process.exit() directly. process.exit() is uncatchable — when this ran
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

// --- main ----------------------------------------------------------------------

function main() {
  const args = parseArgs(process.argv.slice(2));
  const slugs = [args.ref, ...(args.spec ? [args.spec] : [])];

  // D2 + D3 — resolve EVERY doc and validate its status BEFORE any write
  // (D7 pair pre-write abort: either failing aborts the whole transaction).
  const resolved = [];
  for (const slug of slugs) {
    const r = resolveDoc(ROOT, slug);
    if (!r.found) {
      process.stderr.write(`close-work-item: ${r.reasons.join('; ')}\n`);
      process.exit(2);
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
      process.exit(2);
    }
    const status = String(r.doc.fm?.status ?? '').toLowerCase();
    if (!status) {
      process.stderr.write(`close-work-item: doc ${r.doc.rel} (${slug}) has no frontmatter status\n`);
      process.exit(2);
    }
    if (status !== 'done' && !FLIP_ELIGIBLE.has(status)) {
      process.stderr.write(
        `close-work-item: doc ${r.doc.rel} (${slug}) has non-done-terminal status "${status}" — refusing to reopen/repurpose\n`
      );
      process.exit(2);
    }
    resolved.push({ slug, ...r.doc, status });
  }

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

  if (args.dryRun) {
    console.log(JSON.stringify(
      {
        anyMutation,
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
    process.exit(0);
  }

  const refs = plan.map((p) => p.fmId);

  if (!anyMutation) {
    // D6.2 — idempotency short-circuit: nothing to write, but still
    // self-verify (nothing to roll back if this somehow fails — no write
    // happened this run).
    const problems = selfVerify(refs);
    if (problems.length > 0) {
      process.stderr.write('close-work-item: already-closed state failed self-verify (no write made this run):\n');
      for (const p of problems) process.stderr.write(`  - ${p}\n`);
      process.exit(1);
    }
    console.log(`close-work-item: nothing to do (already closed) for ${refs.join(', ')}`);
    process.exit(0);
  }

  // D6.1 — SNAPSHOT before any write.
  const snapshot = new Map(plan.map((p) => [p.abs, p.content]));
  const eventsSnapshotLen = fs.existsSync(EVENTS_PATH) ? fs.statSync(EVENTS_PATH).size : 0;

  try {
    // D6.3 — APPLY: every doc's frontmatter first, THEN every doc's events
    // (status-flip-first ordering — a still-open doc never carries a close
    // event, so probable-false-open's Arm C can never self-flag mid-close).
    for (const p of plan) {
      const mutated = applyDocMutation(p.content, {
        toStatus: p.needsFlip ? 'done' : null,
        pr: args.pr,
        commit: args.commit,
      });
      if (mutated !== p.content) fs.writeFileSync(p.abs, mutated);
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
      process.exit(1);
    }
  } catch (err) {
    rollback(snapshot, eventsSnapshotLen);
    try {
      regenerateIndex();
    } catch {
      /* best-effort revert of the INDEX; the doc/EVENTS rollback above is what matters */
    }
    process.stderr.write(`close-work-item: internal error — rolled back (${err.message})\n`);
    process.exit(1);
  }

  console.log(`close-work-item: closed ${refs.join(', ')} (pr #${args.pr}, commit ${args.commit})`);
  process.exit(0);
}

try {
  main();
} catch (err) {
  process.stderr.write(`close-work-item: internal error (${err.message})\n`);
  process.exit(1);
}
