#!/usr/bin/env node
//
// nothing-left-behind.mjs — the route-independent "nothing left behind" gate
// (ref simple-and-friendly-to-use / SPEC-0172-spec-simple-and-friendly-to-use,
// D2, Spec-AC-03 / Spec-AC-04).
//
// One command, four named classes, composed from the CLIs that already decide
// each half — nothing here re-derives a verdict another script owns:
//
//   files_left            `git status --porcelain` in the repository root —
//                         every modified, staged or untracked path is one item
//                         (fu-index-regen-eats-untracked: an untracked file
//                         leaking into docs/INDEX.md is exactly this class).
//   audit_findings        `docs-audit.mjs --check --strict --no-event` — the
//                         NEEDS-TRIAGE count of its verdict line, plus one item
//                         when it hard-fails without a triage count.
//   docs_open             over the corpus docs-audit itself scans
//                         (`scanAuditDocs`, so the two never disagree about
//                         which directories are in scope): the ride's own
//                         intake doc (frontmatter `id: <slug>`)
//                         and every spec linked to it (frontmatter id
//                         `spec-<slug>`, or `links.requirement` naming the
//                         intake path) whose `status` is not terminal — the
//                         "merged work still reading status: draft" shape
//                         (upstream issue #352) that docs-audit only sees when
//                         delivery evidence is visible to it.
//   registry_self_items   `follow-ups.mjs list --json --status open` filtered
//                         to `ref_id == <slug>` whose follow-up `id` begins
//                         with one of the CLOSED list of ceremony subject
//                         prefixes CEREMONY_FOLLOW_UP_ID_PREFIXES — a
//                         follow-up a ride filed about its own ceremony
//                         (fu-ac-flip-must-precede-close,
//                         fu-index-regen-eats-untracked). Pinned by TEST-005
//                         (behaviour) and TEST-008 (the list lives in exactly
//                         one file).
//
// Usage:
//   node .aai/scripts/nothing-left-behind.mjs --ref <slug> [--root <dir>] [--json]
//
// Exit codes:
//   0  all four classes empty; prints `CLEAN`
//   1  something was left behind; every item is named under its class heading
//   2  usage error (missing --ref, unreadable root)
//
// `--json` prints one object {ref, root, files_left, docs_open, audit_findings,
// registry_self_items, clean, items:{...}} — the golden flow reads its three
// gate fields from here and never recomputes them (Spec-AC-04). The exit code
// is the same in both modes. Runs from the repository root by default
// (`process.cwd()`), like docs-audit.mjs and close-work-item.mjs; sibling CLIs
// are resolved next to this file so the gate exercises the SAME vendored layer
// it ships in. Node stdlib only.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { parseFrontmatter, toPosix, TERMINAL_DOC_STATUS } from './lib/docs-model.mjs';
import { scanAuditDocs } from './lib/docs-audit-core.mjs';
// Read-only imports of the protected_paths_l3 STATE engine (D5, Spec-AC-02):
// this gate consults docs/ai/STATE.yaml current_focus.ref_id but never writes
// it — the SAME line-engine state.mjs itself uses, not a second reader.
import { readScalar } from './lib/state-engine.mjs';
import { splitLines } from './lib/state-core.mjs';

const SELF_DIR = path.dirname(fileURLToPath(import.meta.url));
const DOCS_AUDIT = path.join(SELF_DIR, 'docs-audit.mjs');
const FOLLOW_UPS = path.join(SELF_DIR, 'follow-ups.mjs');

// Class 4's membership rule — OWNER-SIGNED amendment to Spec-AC-03
// (spec-amend, 2026-09-07, owner_signoff true): the class is decided by the
// follow-up's `id` prefix, never by the prose in `finding`.
//
// WHY the change was signed. The old rule matched six words against the
// `finding` TEXT. `finding` is prose written to describe a defect, so the rule
// counted any item that MENTIONED the ceremony, not any item that WAS about
// the ride's ceremony. The scar: `fu-gate-ref-id-shape-mismatch` records a
// defect in THIS gate, and describing that defect necessarily uses the word
// "ceremony" — so the gate reported the ride as having left its own ceremony
// incomplete for naming its own weakness, and SKILL_PR step 5 would have
// stopped the push. Rewording the finding to dodge the regex is evading the
// guard, not fixing it; the fix is to stop deciding a structural question from
// prose.
//
// THE RULE. A follow-up counts iff `id` starts with one of the prefixes below.
// The `id` is a structured field, not prose: `follow-ups.mjs add` requires
// `--id` to match ^fu-[a-z0-9]+(-[a-z0-9]+)*$, ids are unique and never reused,
// and the segment(s) after `fu-` are the filer's declaration of the item's
// SUBJECT. The list below is that subject vocabulary — the same closed
// ceremony vocabulary the frozen AC always named, moved from the description
// to the subject. Consequences, all of them intended:
//   - a genuine "this ride left its own ceremony incomplete" item is still
//     caught: it is filed under a ceremony subject (fu-ac-flip-*, fu-close-*,
//     fu-stamp-*, fu-index-*, fu-false-open-*, fu-ceremony-*), which is how
//     every such item in this repository's live registry is already named;
//   - a follow-up whose SUBJECT is the gate or the tooling this ride DELIVERS
//     (fu-gate-*, fu-golden-flow-*) is not caught, however its prose reads;
//   - `fu-amend-*` sign-off items (SPEC-0165) stay excluded STRUCTURALLY —
//     their subject is the amendment, not the ceremony — instead of resting on
//     the accident that their wording carried none of the six words
//     (fu-amend-exclusion-rests-on-wording).
// DISCLOSED RESIDUAL: the rule trusts the id the filer chose, so a ceremony
// item filed under an unlisted subject is missed. That is the same trust the
// old rule placed in the filer's wording, minus the false positives, and it is
// evadable only by mis-naming the subject — which `follow-ups.mjs` will not
// let you change afterwards. Widening the list is a spec amendment, and
// TEST-008 pins the literal to this file so no seventh prefix arrives quietly.
export const CEREMONY_FOLLOW_UP_ID_PREFIXES = ['fu-ac-flip-', 'fu-acflip-', 'fu-allocator-', 'fu-ceremony-', 'fu-close-', 'fu-closeworkitem-', 'fu-false-open-', 'fu-index-', 'fu-stamp-'];

// Decidable from the structured `id` alone: no read of `finding`, `decision`
// or any other prose field.
export function isCeremonyFollowUpId(id) {
  const s = String(id ?? '').toLowerCase();
  return CEREMONY_FOLLOW_UP_ID_PREFIXES.some((p) => s.startsWith(p));
}
// The terminal set is NOT declared here: it is the layer's ONE lifecycle
// partition, lib/docs-model.mjs TERMINAL_DOC_STATUS. The private copy this
// line used to hold dropped `legacy` AND `current`, so a retired doc or a
// steady-state product doc read as "still open" on every run with no way to
// clear the item — the gate STOPPED a push over a doc nobody could close.

// ---- D5 (Spec-AC-02): the gate may not decide on --ref alone -----------------
// `--ref` is trusted input; this cross-checks it against docs/ai/STATE.yaml
// current_focus.ref_id and reports a mismatch as an item rather than printing
// CLEAN for a ref nobody is shipping. Read-only: never writes STATE (article 6).
// Absent STATE degrades to null (no mismatch) — the same "nothing to compare"
// posture check-committed-scope.mjs takes for a field it cannot read.
function checkFocusRef(root, ref) {
  const statePath = path.join(root, 'docs', 'ai', 'STATE.yaml');
  let text;
  try { text = fs.readFileSync(statePath, 'utf8'); } catch { return null; }
  const focusRef = readScalar(splitLines(text).lines, 'current_focus', 'ref_id');
  if (focusRef === null || focusRef === ref) return null;
  return `docs/ai/STATE.yaml current_focus.ref_id (${focusRef}) does not match --ref (${ref})`;
}

// ---- D6/Spec-AC-02: registry identity is the slug OR the doc's display id ---
// A follow-up may legitimately be filed with `--ref` set to the display id
// (CHANGE-0178) rather than the slug this gate is invoked with — both name
// the SAME ride. The display id is derived from the ride's own intake doc
// frontmatter (`type` + `number`), never re-typed from the filename.
const DISPLAY_ID_PREFIX = {
  change: 'CHANGE', issue: 'ISSUE', spec: 'SPEC', rfc: 'RFC',
  prd: 'PRD', hotfix: 'HOTFIX', techdebt: 'DEBT', research: 'RES',
};

function frontmatterDisplayId(fm) {
  const num = fm.number;
  if (num == null) return null;
  const n = String(num).trim();
  if (!/^\d+$/.test(n)) return null;
  const prefix = DISPLAY_ID_PREFIX[String(fm.type ?? '').trim().toLowerCase()];
  if (!prefix) return null;
  return `${prefix}-${n.padStart(4, '0')}`;
}

function refIdentitySet(docs, slug) {
  const ids = new Set([slug]);
  for (const d of docs) {
    if (String(d.fm.id ?? '') !== slug) continue;
    const disp = frontmatterDisplayId(d.fm);
    if (disp) ids.add(disp);
  }
  return ids;
}

// D6: a ceremony item filed under an id prefix outside
// CEREMONY_FOLLOW_UP_ID_PREFIXES is still caught when its OWN finding text
// discloses, in the same narrow self-referential terms the code above already
// uses to describe the shape ("this ride left its own ceremony incomplete"),
// that it is about the ride's own ceremony. DELIBERATELY narrower than the
// six-word finding-text regex this file's own history records removing
// (TEST-005 pins it gone): "ceremony" alone is not enough — TEST-005's own
// fu-gate-*/fu-amend-* negative controls use that word without tripping this
// arm, because neither carries the phrase "own ceremony".
const CEREMONY_CONTENT_RE = /\bown ceremony\b/i;

function isCeremonyContentMatch(finding) {
  return CEREMONY_CONTENT_RE.test(String(finding ?? ''));
}

// ---- D4/Spec-AC-03: the roadmap-paired maintenance half -----------------
// docs/ai/roadmap.yaml's shape is closed (see its own header comment): a
// `pairs:` list of { capability, maintenance, status } maps. No YAML library
// (Node stdlib only, docs/TECHNOLOGY.md) — a small line-scan mirrors the
// engine's own block/line discipline rather than re-parsing arbitrary YAML.
// Absent file degrades to [] SILENTLY (D5 edge case: "a roadmap that is
// absent — the paired-half class must stay silent, not crash").
function readRoadmapPairs(root) {
  let text;
  try { text = fs.readFileSync(path.join(root, 'docs', 'ai', 'roadmap.yaml'), 'utf8'); } catch { return []; }
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  const pairs = [];
  let inPairs = false;
  let cur = null;
  for (const line of lines) {
    if (/^pairs:\s*$/.test(line)) { inPairs = true; continue; }
    if (/^[A-Za-z_][\w-]*:/.test(line) && !/^\s/.test(line)) { inPairs = false; }
    if (!inPairs) continue;
    const cap = line.match(/^\s*-\s*capability:\s*(.+)$/);
    if (cap) { if (cur) pairs.push(cur); cur = { capability: cap[1].trim(), maintenance: null, status: null }; continue; }
    const m = line.match(/^\s*maintenance:\s*(.+)$/);
    if (m && cur) { cur.maintenance = m[1].trim(); continue; }
    const s = line.match(/^\s*status:\s*(.+)$/);
    if (s && cur) { cur.status = s[1].trim(); continue; }
  }
  if (cur) pairs.push(cur);
  return pairs;
}

// Returns a docs_open-shaped item array (0 or 1 entries): the ride's own
// roadmap-paired maintenance half, when it is not yet terminal. `docs` is the
// SAME scanAuditDocs()-derived corpus docsOpen() already built, imported
// rather than re-walked.
function roadmapPairedOpen(root, slug, docs) {
  const pairs = readRoadmapPairs(root);
  const pair = pairs.find((p) => p.capability === slug);
  if (!pair || !pair.maintenance) return [];
  const doc = docs.find((d) => String(d.fm.id ?? '') === pair.maintenance);
  if (!doc) return [];
  const status = String(doc.fm.status ?? '').trim().toLowerCase();
  if (TERMINAL_DOC_STATUS.has(status)) return [];
  return [`${doc.rel} (paired maintenance half of ${slug}) status: ${status || 'missing'}`];
}

function usage(msg) {
  process.stderr.write(`nothing-left-behind: ${msg}\n`);
  process.stderr.write('usage: node .aai/scripts/nothing-left-behind.mjs --ref <slug> [--root <dir>] [--json]\n');
  exit(2);
}

function parseArgs(argv) {
  const out = { ref: null, root: null, json: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--ref') out.ref = argv[++i];
    else if (a === '--root') out.root = argv[++i];
    else if (a === '--json') out.json = true;
    else usage(`unknown argument ${a}`);
  }
  if (!out.ref || !out.ref.trim()) usage('--ref <slug> is required');
  return out;
}

function run(cmd, args, cwd) {
  const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return { code: r.status === null ? -1 : r.status, stdout: r.stdout ?? '', stderr: r.stderr ?? '', error: r.error };
}

// ---- class 1: files ----------------------------------------------------------
function filesLeft(root) {
  const r = run('git', ['status', '--porcelain', '--untracked-files=all'], root);
  if (r.error || r.code !== 0) {
    return [`git status failed in ${root}: ${(r.stderr || r.error?.message || '').trim() || 'exit ' + r.code}`];
  }
  return r.stdout.split('\n').filter(l => l.trim()).map(l => l.trimEnd());
}

// ---- class 2: docs-audit -----------------------------------------------------
function auditFindings(root) {
  const r = run(process.execPath, [DOCS_AUDIT, '--check', '--strict', '--no-event'], root);
  const text = `${r.stdout}\n${r.stderr}`;
  const items = [];
  const verdict = text.match(/^### Verdict: (.+)$/m);
  const triage = verdict ? verdict[1].match(/NEEDS-TRIAGE \((\d+) items?\)/) : null;
  const count = triage ? Number(triage[1]) : 0;
  if (count > 0 || r.code !== 0) {
    // Name the rows of every counted section (a table row or a list bullet
    // under a `### <Section>: N` heading with N > 0), skipping the report-only
    // sections that never feed the verdict.
    const reportOnly = /^### (Rollout progress|Closeout candidates|Open decisions on done docs|Near-miss AC tables|Review-By claims|Missing close telemetry|Pending commit|Annotations)/;
    let inCounted = false;
    for (const line of text.split('\n')) {
      const h = line.match(/^### (.+?): (\d+)$/);
      if (h) { inCounted = Number(h[2]) > 0 && !reportOnly.test(line); continue; }
      if (/^### /.test(line)) { inCounted = false; continue; }
      if (!inCounted) continue;
      if (/^\|\s*-+/.test(line) || /^\| *(Doc|Id|Canonical doc|Parent) /.test(line)) continue; // table rule / header
      if (/^\|/.test(line) || /^- /.test(line)) items.push(line.trim());
    }
    const failed = text.match(/^CHECK FAILED: .+$/m);
    if (failed) items.push(failed[0]);
    if (r.error) items.push(`docs-audit could not run: ${r.error.message}`);
  }
  const n = Math.max(count, (r.code !== 0 && count === 0) ? 1 : 0);
  return { count: n, items, verdict: verdict ? verdict[1] : (r.error ? 'unavailable' : `exit ${r.code}`) };
}

// ---- class 3: the ride's own docs ------------------------------------------
// The corpus is scanAuditDocs() from lib/docs-audit-core.mjs — the SAME walk
// (and the same EXCLUDE_DIRS) docs-audit itself uses, imported rather than
// re-typed. The private walk this used to hold excluded only
// {docs/ai, docs/_archive, docs/knowledge}, re-introducing the `archive` vs
// `_archive` drift docs-audit-core.mjs's own SEAM-3 comment records having
// already fixed once: a doc under docs/archive, docs/project-sessions or
// docs/templates would have been counted by the gate while being invisible to
// `docs-audit --strict`, so clearing the item meant editing an archived file.
// This file still owns the frontmatter read (scanAuditDocs returns paths).
function listDocs(root) {
  const out = [];
  for (const { rel } of scanAuditDocs(root)) {
    let content;
    try { content = fs.readFileSync(path.join(root, rel), 'utf8'); } catch { continue; }
    const fm = parseFrontmatter(content);
    if (!fm) continue;
    out.push({ rel: toPosix(rel), fm });
  }
  return out;
}

function docsOpen(docs, slug) {
  const items = [];
  const intake = docs.filter(d => String(d.fm.id ?? '') === slug);
  if (intake.length === 0) {
    items.push(`no intake doc carries frontmatter id: ${slug}`);
    return items;
  }
  const seen = new Set();
  const check = (d, role) => {
    if (seen.has(d.rel)) return;
    seen.add(d.rel);
    const status = String(d.fm.status ?? '').trim().toLowerCase();
    if (!TERMINAL_DOC_STATUS.has(status)) items.push(`${d.rel} (${role}) status: ${status || 'missing'}`);
  };
  for (const d of intake) check(d, 'intake');
  const intakeRels = new Set(intake.map(d => d.rel));
  for (const d of docs) {
    if (String(d.fm.type ?? '') !== 'spec') continue;
    const byId = String(d.fm.id ?? '') === `spec-${slug}`;
    const req = d.fm.links && typeof d.fm.links === 'object' ? String(d.fm.links.requirement ?? '') : '';
    const byLink = req && intakeRels.has(toPosix(req.replace(/^\.\//, '')));
    if (byId || byLink) check(d, 'spec');
  }
  return items;
}

// ---- class 4: the registry -------------------------------------------------
// `refIdentity` (Spec-AC-02/D6): the slug plus every display id derivable
// from the ride's own intake doc(s) — a follow-up filed with either counts.
function registrySelfItems(root, refIdentity) {
  const ledger = path.join(root, 'docs', 'ai', 'decisions.jsonl');
  if (!fs.existsSync(ledger)) return { items: [], note: 'no docs/ai/decisions.jsonl (registry empty)' };
  const r = run(process.execPath, [FOLLOW_UPS, 'list', '--json', '--status', 'open', '--ledger', ledger], root);
  if (r.error || r.code !== 0) {
    return { items: [`follow-ups.mjs list failed: ${(r.stderr || r.error?.message || '').trim() || 'exit ' + r.code}`], note: null };
  }
  let parsed;
  try { parsed = JSON.parse(r.stdout); } catch (err) {
    return { items: [`follow-ups.mjs list --json was not JSON: ${err.message}`], note: null };
  }
  const items = [];
  for (const it of parsed.items ?? []) {
    if (!refIdentity.has(String(it.ref_id ?? ''))) continue;
    if (it.closed) continue;
    if (!isCeremonyFollowUpId(it.id) && !isCeremonyContentMatch(it.finding)) continue;
    items.push(`${it.id} (${it.severity}): ${it.finding}`);
  }
  return { items, note: null };
}

// ---- main ------------------------------------------------------------------
export function runGate(root, slug) {
  const files = filesLeft(root);
  const audit = auditFindings(root);
  const docs = listDocs(root);
  const docsOpenItems = docsOpen(docs, slug);
  const pairedOpen = roadmapPairedOpen(root, slug, docs);
  const docsOpenAll = [...docsOpenItems, ...pairedOpen];
  const refIdentity = refIdentitySet(docs, slug);
  const registry = registrySelfItems(root, refIdentity);
  const focusMismatch = checkFocusRef(root, slug);
  const refMismatchItems = focusMismatch ? [focusMismatch] : [];
  return {
    ref: slug,
    root,
    files_left: files.length,
    docs_open: docsOpenAll.length,
    audit_findings: audit.count,
    registry_self_items: registry.items.length,
    ref_mismatch: refMismatchItems.length,
    clean: files.length + docsOpenAll.length + audit.count + registry.items.length + refMismatchItems.length === 0,
    audit_verdict: audit.verdict,
    items: {
      files_left: files, docs_open: docsOpenAll, audit_findings: audit.items,
      registry_self_items: registry.items, ref_mismatch: refMismatchItems,
    },
    notes: [registry.note].filter(Boolean),
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.root ?? process.cwd());
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) usage(`root is not a directory: ${root}`);
  const result = runGate(root, args.ref);
  if (args.json) {
    process.stdout.write(JSON.stringify(result) + '\n');
  } else {
    const lines = [`nothing-left-behind: ref=${result.ref} root=${result.root}`];
    for (const cls of ['files_left', 'docs_open', 'audit_findings', 'registry_self_items', 'ref_mismatch']) {
      lines.push(`## ${cls}: ${result[cls]}`);
      for (const it of result.items[cls]) lines.push(`- ${it}`);
    }
    for (const n of result.notes) lines.push(`note: ${n}`);
    const total = result.files_left + result.docs_open + result.audit_findings + result.registry_self_items + result.ref_mismatch;
    lines.push(result.clean ? 'CLEAN' : `LEFT BEHIND: ${total} item(s) — see the classes above`);
    process.stdout.write(lines.join('\n') + '\n');
  }
  exit(result.clean ? 0 : 1);
}

runMain(() => main());
