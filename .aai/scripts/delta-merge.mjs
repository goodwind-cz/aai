#!/usr/bin/env node
// Close-time delta merge (RFC-0011, the delta-spec lifecycle — its third and
// final staged SPEC). Applies a merging spec's `## Deltas` into the per-domain
// `docs/canonical/<slug>.md` Requirements set, deterministically and with NO
// LLM in the write path (RFC-0011 rejected LLM-merged deltas).
//
// Usage:
//   node .aai/scripts/delta-merge.mjs --spec <path> [--root <dir>] [--check]
//
// Contract (RFC-0011 D1/D2/D5):
//   - The delta GRAMMAR is owned SOLELY by parseDeltasSection (the source of the
//     op/id/domain/slug/title/scenario/shall-count facts AND every violation)
//     and parseRequirementsSection (the canonical Requirements reader that
//     locates target blocks and computes the per-domain max NNN). This script
//     re-expresses NEITHER grammar; it only harvests the verbatim requirement
//     BODY text (the SHALL statement + scenario bullets) the writer copies in.
//   - FAIL-CLOSED (exit != 0, ZERO writes, reason named) on: any parseDeltasSection
//     violation; a target docs/canonical/<slug>.md that does not exist; a
//     MODIFIED/REMOVED id absent from that doc's `## Requirements` (and not
//     already retired by THIS spec on a prior run); an ADDED whose title
//     collides with an existing requirement in the domain.
//   - Validation is ALL-OR-NOTHING across every target file: if any precondition
//     fails, nothing is written.
//   - Provenance value = the merging spec's display id: its numbered `TYPE-000N`
//     when the filename carries one (the PR ceremony numbers the draft BEFORE
//     this step runs), else the frontmatter slug `id`.
//   - Line-surgical: only the touched blocks' lines change; every untouched line
//     is byte-identical. Byte-idempotent on a second run (ADDED guarded by
//     Provenance==this-spec + title; MODIFIED re-renders identically; a REMOVED
//     whose id is already retired-by-this-spec is a no-op, not an "id absent"
//     error — RFC-0011 D2).
//
// Retirement record (RFC-0011 D2): a REMOVED block is replaced in place by a
// tombstone comment `<!-- RETIRED <id> by <spec> -->`. It is the persistent
// "Provenance history shows this spec" record D2 relies on: it (a) makes the
// second run a defined no-op rather than an "id absent" fail-close, and (b)
// preserves the retired NNN in the per-domain max so a later ADDED never reuses
// it (ids are retired permanently, never renumbered — SPEC-0034 D1).

import fs from 'node:fs';
import path from 'node:path';
import {
  parseDeltasSection, parseRequirementsSection, parseFrontmatter,
  stripHtmlComments, normalizeNewlines,
} from './lib/docs-model.mjs';

// --- CLI --------------------------------------------------------------------

function parseArgs(argv) {
  const args = { spec: null, root: process.cwd(), check: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--spec') args.spec = argv[++i];
    else if (tok === '--root') args.root = argv[++i];
    else if (tok === '--check') args.check = true;
  }
  return args;
}

// --- helpers ----------------------------------------------------------------

// Display id the Provenance line records for the merging spec (RFC-0011 D1):
// the numbered TYPE-000N form when the filename carries one, else the
// frontmatter slug id, else the bare basename.
function specDisplayId(specPath, fm) {
  const base = path.basename(specPath).replace(/\.md$/i, '');
  const m = base.match(/^([A-Z]+(?:-[A-Z]+)*)-(\d{1,5})(?=-|$)/);
  if (m) return `${m[1]}-${m[2]}`;
  if (fm && fm.id != null && String(fm.id).trim() !== '') return String(fm.id).trim();
  return base;
}

// Harvest the VERBATIM body lines of each recognized-op `### ` block in the
// merging spec's `## Deltas` section, in document order. Structural markdown
// traversal ONLY — the op/id/title/validity are parseDeltasSection's job; this
// returns raw bodies the writer copies in, paired positionally with the
// validated deltas (guaranteed 1:1 in the no-violations path, since every
// recognized block yields exactly one delta in order). HTML comments are
// blanked exactly as parseDeltasSection blanks them, so a commented-out block
// contributes nothing.
function harvestDeltaBodies(content) {
  const lines = stripHtmlComments(normalizeNewlines(content)).split('\n');
  let start = -1;
  for (let i = 0; i < lines.length; i += 1) {
    if (/^##\s+Deltas\s*$/.test(lines[i])) { start = i; break; }
  }
  if (start < 0) return [];
  const blocks = [];
  let cur = null;
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^##\s/.test(line)) break;
    if (/^###\s/.test(line)) {
      if (cur) blocks.push(cur);
      cur = { bodyLines: [] };
      continue;
    }
    if (cur) cur.bodyLines.push(line);
  }
  if (cur) blocks.push(cur);
  return blocks;
}

function trimBlankEdges(arr) {
  const out = arr.slice();
  while (out.length && out[0].trim() === '') out.shift();
  while (out.length && out[out.length - 1].trim() === '') out.pop();
  return out;
}

// Render a canonical requirement block from a delta body (ADDED/MODIFIED). The
// body (SHALL statement + `- Scenario:` bullets) is copied verbatim; any stray
// Provenance line is dropped and the merging-spec Provenance appended.
function renderBlock(id, title, bodyLines, spec) {
  const body = trimBlankEdges(bodyLines).filter(l => !/^Provenance:\s*/.test(l));
  return [`### ${id} — ${title}`, ...body, '', `Provenance: ${spec}`];
}

function tombstone(id, spec) {
  return `<!-- RETIRED ${id} by ${spec} -->`;
}

const TOMBSTONE_RE = /^<!--\s*RETIRED\s+(REQ-[A-Z0-9][A-Z0-9_]*-\d{3,})\s+by\s+(.+?)\s*-->\s*$/;

function nnnOf(id) {
  const m = String(id).match(/-(\d{3,})$/);
  return m ? Number(m[1]) : null;
}

// Locate the `## Requirements` section of a canonical doc (line indices over a
// non-normalized line array — bytes of untouched lines are preserved exactly).
function locateRequirements(lines) {
  let hi = -1;
  for (let i = 0; i < lines.length; i += 1) {
    if (/^##\s+Requirements\s*$/.test(lines[i])) { hi = i; break; }
  }
  if (hi < 0) return null;
  let endIdx = lines.length;
  for (let i = hi + 1; i < lines.length; i += 1) {
    if (/^##\s/.test(lines[i])) { endIdx = i; break; }
  }
  return { hi, endIdx };
}

// Apply the deltas targeting ONE canonical file. Returns { text } on success or
// throws an Error (fail-closed, reason in message). `entries` is a list of
// { delta, body } for this file, in document order.
function applyToFile(rawText, entries, spec) {
  const lines = rawText.split('\n');
  const loc = locateRequirements(lines);
  if (!loc) throw new Error('target canonical doc has no "## Requirements" section');

  const parsed = parseRequirementsSection(rawText);
  const byId = new Map(parsed.requirements.map(r => [r.id, r]));

  // Per-domain max NNN over live requirement ids AND retired (tombstoned) ids,
  // so a retired number is never reused (RFC-0011 D2 / SPEC-0034 D1).
  const domain = entries[0].delta.domain;
  let maxN = 0;
  for (const r of parsed.requirements) {
    const tok = r.id.replace(/^REQ-/, '').replace(/-\d+$/, '');
    if (tok === domain) maxN = Math.max(maxN, nnnOf(r.id) ?? 0);
  }
  const retiredByThisSpec = new Set();
  for (const l of lines) {
    const tm = l.match(TOMBSTONE_RE);
    if (!tm) continue;
    const tok = tm[1].replace(/^REQ-/, '').replace(/-\d+$/, '');
    if (tok === domain) maxN = Math.max(maxN, nnnOf(tm[1]) ?? 0);
    if (tm[2].trim() === spec) retiredByThisSpec.add(tm[1]);
  }

  // Resolve each delta to a concrete op with a full target id; validate
  // preconditions (throws on any). ADDED gets its NNN from the running max.
  let nextN = maxN + 1;
  const ops = { modified: new Map(), removed: new Set(), added: [] };
  for (const { delta, body } of entries) {
    if (delta.op === 'MODIFIED') {
      if (byId.has(delta.id)) {
        ops.modified.set(delta.id, renderBlock(delta.id, delta.title, body, spec));
      } else if (retiredByThisSpec.has(delta.id)) {
        // already retired by this spec on a prior run — nothing to modify (no-op)
      } else {
        throw new Error(`MODIFIED target ${delta.id} is absent from the canonical Requirements`);
      }
    } else if (delta.op === 'REMOVED') {
      if (byId.has(delta.id)) {
        ops.removed.add(delta.id);
      } else if (retiredByThisSpec.has(delta.id)) {
        // idempotent: this spec already removed it — no-op, not an error (D2)
      } else {
        throw new Error(`REMOVED target ${delta.id} is absent from the canonical Requirements`);
      }
    } else { // ADDED
      const dup = parsed.requirements.find(
        r => r.title.trim().toLowerCase() === String(delta.title).trim().toLowerCase(),
      );
      if (dup) {
        if (dup.provenance === spec) continue; // idempotent: this spec already added it
        throw new Error(`ADDED title "${delta.title}" collides with existing requirement ${dup.id} in domain ${domain}`);
      }
      const id = `REQ-${domain}-${String(nextN).padStart(3, '0')}`;
      nextN += 1;
      ops.added.push(renderBlock(id, delta.title, body, spec));
    }
  }

  if (ops.modified.size === 0 && ops.removed.size === 0 && ops.added.length === 0) {
    return { text: rawText, changed: false };
  }

  // Rebuild the section body line-surgically. Split into `core` (up to the last
  // non-blank line) + `finalBlanks` (the trailing blank run before the next
  // `## ` heading), so ADDED blocks land after the last requirement's content
  // but before that separator.
  const section = lines.slice(loc.hi + 1, loc.endIdx);
  let lastContent = section.length - 1;
  while (lastContent >= 0 && section[lastContent].trim() === '') lastContent -= 1;
  const core = section.slice(0, lastContent + 1);
  const finalBlanks = section.slice(lastContent + 1);

  const newCore = [];
  let i = 0;
  while (i < core.length) {
    if (/^###\s/.test(core[i])) {
      // A block's body ends at the NEXT `### ` heading OR the next tombstone
      // line — a tombstone is a standalone element (emitted verbatim by the
      // else-branch below), NEVER absorbed into the preceding block, so
      // re-rendering a MODIFIED block can never touch an adjacent retirement
      // record (RFC-0011 D2: retired ids and their NNN survive every re-merge).
      let j = i + 1;
      while (j < core.length && !/^###\s/.test(core[j]) && !TOMBSTONE_RE.test(core[j])) j += 1;
      const block = core.slice(i, j);
      let ce = block.length - 1;
      while (ce >= 0 && block[ce].trim() === '') ce -= 1;
      const innerBlanks = block.slice(ce + 1);
      const idm = block[0].match(/^###\s+(REQ-[A-Z0-9][A-Z0-9_]*-\d{3,})\b/);
      const id = idm ? idm[1] : null;
      if (id && ops.removed.has(id)) {
        newCore.push(tombstone(id, spec), ...innerBlanks);
      } else if (id && ops.modified.has(id)) {
        newCore.push(...ops.modified.get(id), ...innerBlanks);
      } else {
        newCore.push(...block);
      }
      i = j;
    } else {
      newCore.push(core[i]);
      i += 1;
    }
  }
  for (const added of ops.added) newCore.push('', ...added);

  const newLines = [
    ...lines.slice(0, loc.hi + 1),
    ...newCore,
    ...finalBlanks,
    ...lines.slice(loc.endIdx),
  ];
  // `changed` reflects the ACTUAL byte difference, not merely that an op ran, so
  // re-merging an already-merged spec is a true no-op (accurate --check;
  // byte-idempotent write path).
  const text = newLines.join('\n');
  return { text, changed: text !== rawText };
}

// --- main -------------------------------------------------------------------

function fail(msg) {
  console.error(`delta-merge: FAIL-CLOSED — ${msg}`);
  process.exit(1);
}

function main() {
  const args = parseArgs(process.argv);
  if (!args.spec) fail('missing --spec <path>');
  const specPath = path.isAbsolute(args.spec) ? args.spec : path.join(args.root, args.spec);
  if (!fs.existsSync(specPath)) fail(`spec not found: ${args.spec}`);

  const specContent = fs.readFileSync(specPath, 'utf8');
  const fm = parseFrontmatter(specContent);
  const spec = specDisplayId(specPath, fm);

  const parsed = parseDeltasSection(specContent);
  if (!parsed.present || parsed.deltas.length === 0) {
    console.log('delta-merge: no `## Deltas` to apply (no-op).');
    process.exit(0);
  }
  if (parsed.violations.length) {
    fail(`the spec\'s Deltas are invalid — ${parsed.violations.map(v => `${v.code}: ${v.detail}`).join('; ')}`);
  }

  const bodies = harvestDeltaBodies(specContent);
  if (bodies.length !== parsed.deltas.length) {
    fail('internal: delta body harvest did not pair 1:1 with parsed deltas');
  }

  // Group deltas by target canonical file (slug). Any unresolved slug/domain is
  // already a parseDeltasSection violation, caught above.
  const byFile = new Map();
  parsed.deltas.forEach((delta, idx) => {
    const rel = path.join('docs', 'canonical', `${delta.slug}.md`);
    if (!byFile.has(rel)) byFile.set(rel, []);
    byFile.get(rel).push({ delta, body: bodies[idx].bodyLines });
  });

  // Precompute every write in memory (ALL-OR-NOTHING); a single fail-close
  // aborts before any file is touched.
  const writes = [];
  const reasons = [];
  for (const [rel, entries] of byFile) {
    const abs = path.join(args.root, rel);
    if (!fs.existsSync(abs)) {
      reasons.push(`canonical doc not found: ${rel} (a domain doc must exist before deltas can merge)`);
      continue;
    }
    try {
      const res = applyToFile(fs.readFileSync(abs, 'utf8'), entries, spec);
      if (res.changed) writes.push({ abs, rel, text: res.text });
    } catch (e) {
      reasons.push(`${rel}: ${e.message}`);
    }
  }
  if (reasons.length) fail(reasons.join('; '));

  if (args.check) {
    if (writes.length === 0) console.log('delta-merge: --check OK — already merged (no changes).');
    else console.log(`delta-merge: --check OK — ${writes.length} canonical file(s) would change (no writes made).`);
    process.exit(0);
  }

  for (const w of writes) fs.writeFileSync(w.abs, w.text);
  if (writes.length === 0) console.log(`delta-merge: nothing to do — ${spec} already merged (byte-idempotent).`);
  else console.log(`delta-merge: applied ${spec} into ${writes.map(w => w.rel).join(', ')}.`);
  process.exit(0);
}

main();
