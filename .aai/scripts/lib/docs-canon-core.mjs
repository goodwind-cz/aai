// Docs canonicalization core (RFC-0003 / SPEC-0002).
//
// Deterministic engine for the aai-docs-canon skill: supersession/dependency
// graph builder, Phase-1 domain-map proposal + HITL gate, Phase-2 synthesis
// scaffolding + archive move + bidirectional back-links, re-run drift
// comparator, and link-integrity checks. The LLM-driven prose synthesis of a
// canonical doc body is performed by the agent following the role prompt; this
// module owns every deterministic step and is unit/integration tested.
//
// No global side effects on import. File writes happen only in the explicit
// runPhase2 mutation path.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {
  CANONICAL_SECTIONS, domainToReqDomain, DOMAIN_SLUG_RE,
  parseFrontmatter, asList,
} from './docs-model.mjs';

export const CANONICAL_DIR = 'docs/canonical';
export const ARCHIVE_DIR = 'docs/_archive';
export const PROPOSAL_PATH = 'docs/ai/docs-canon.proposal.json';
export const MAP_PATH = 'docs/ai/docs-canon.map.json';

// Default target globs (RFC-0003 Risks: explicit input glob, default like index)
export const DEFAULT_TARGET_DIRS = ['docs/issues', 'docs/requirements', 'docs/specs', 'docs/rfc'];

// Any cross-reference DOC-ID anywhere in body text (PRD/SPEC/ISSUE/CHANGE...).
const BODY_ID_RE = /\b([A-Z]+(?:-[A-Z]+)*-\d{1,5}(?:-\d+)?)\b/g;
// Free-text supersession markers (RFC-0003 step 2).
const SUPERSESSION_MARKERS = [
  { key: 'superseded-by', re: /\bSUPERSEDED\s+BY\b/i },
  { key: 'deprecated', re: /\bDEPRECATED\b/i },
  { key: 'addendum', re: /\baddendum\b/i },
];

export function sha256(s) {
  return crypto.createHash('sha256').update(s).digest('hex');
}

function stripFrontmatter(content) {
  if (!content.startsWith('---\n')) return content;
  const end = content.indexOf('\n---', 4);
  if (end < 0) return content;
  return content.slice(end + 4);
}

// --- doc collection ----------------------------------------------------------

// Read every *.md doc under the target dirs (relative to root), returning
// { rel, content, fm, body }. Deterministic order (sorted by rel).
export function collectDocs(root, targetDirs = DEFAULT_TARGET_DIRS) {
  const out = [];
  const visit = (dir) => {
    const abs = path.join(root, dir);
    if (!fs.existsSync(abs)) return;
    for (const entry of fs.readdirSync(abs, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const relChild = path.join(dir, entry.name);
      if (entry.isDirectory()) { visit(relChild); continue; }
      if (!entry.name.endsWith('.md') || entry.name === 'INDEX.md') continue;
      const content = fs.readFileSync(path.join(root, relChild), 'utf8');
      const fm = parseFrontmatter(content);
      out.push({ rel: relChild, content, fm, body: stripFrontmatter(content) });
    }
  };
  for (const d of targetDirs) visit(d);
  return out.sort((a, b) => a.rel.localeCompare(b.rel));
}

// --- graph builder (Spec-AC-04) ---------------------------------------------

// Build a pure, deterministic supersession/dependency graph from a doc set.
// Input: array of { rel, content/fm/body } (as from collectDocs) OR plain
// { rel, content } objects (fm/body derived on demand).
// Output is a plain serializable object: same input ⇒ byte-identical JSON.
export function buildGraph(docs) {
  const normalized = docs.map(d => {
    const content = d.content ?? '';
    const fm = d.fm !== undefined ? d.fm : parseFrontmatter(content);
    const body = d.body !== undefined ? d.body : stripFrontmatter(content);
    return { rel: d.rel, content, fm, body };
  }).sort((a, b) => a.rel.localeCompare(b.rel));

  const nodes = [];
  const umbrellas = {}; // id -> [rel,...]

  for (const d of normalized) {
    const fmId = d.fm?.id ?? null;
    const status = d.fm?.status ? String(d.fm.status).toLowerCase() : null;
    const markers = [];
    for (const m of SUPERSESSION_MARKERS) {
      if (m.re.test(d.body)) markers.push(m.key);
    }
    // explicit "SUPERSEDED BY <ID>" edges
    const supersededBy = [];
    for (const mm of d.body.matchAll(/\bSUPERSEDED\s+BY\s+([A-Z]+(?:-[A-Z]+)*-\d{1,5}(?:-\d+)?)/gi)) {
      if (!supersededBy.includes(mm[1])) supersededBy.push(mm[1]);
    }
    // cross-reference dependency edges (any DOC-ID in body, excluding self id)
    const refs = [];
    for (const mm of d.body.matchAll(BODY_ID_RE)) {
      const id = mm[1];
      if (id === fmId) continue;
      if (!refs.includes(id)) refs.push(id);
    }
    refs.sort();
    const node = {
      rel: d.rel,
      id: fmId,
      status,
      superseded: status === 'superseded',
      markers: markers.sort(),
      supersededBy: supersededBy.sort(),
      crossRefs: refs,
    };
    nodes.push(node);
    if (fmId) {
      (umbrellas[fmId] ??= []).push(d.rel);
    }
  }

  // umbrella groups: ids shared by >= 2 files (RFC-0003: N files, one id)
  const umbrellaGroups = Object.entries(umbrellas)
    .filter(([, rels]) => rels.length >= 2)
    .map(([id, rels]) => ({ id, members: rels.slice().sort() }))
    .sort((a, b) => a.id.localeCompare(b.id));

  nodes.sort((a, b) => a.rel.localeCompare(b.rel));
  return { nodes, umbrellaGroups };
}

// Stable serialization for determinism checks (sorted keys, byte-identical).
export function serializeGraph(graph) {
  return JSON.stringify(graph, Object.keys(graph).length ? sortedReplacer : null, 2);
}
function sortedReplacer(key, value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return Object.keys(value).sort().reduce((acc, k) => { acc[k] = value[k]; return acc; }, {});
  }
  return value;
}

// --- Phase 1: domain-map proposal + gate (Spec-AC-05) -----------------------

// Heuristic clustering: group by umbrella id first, otherwise by the doc's
// directory leaf as a coarse domain hint. The HUMAN edits/approves the result;
// this only seeds a proposal. A source assigned to >1 domain goes to `unclear`.
export function proposeDomainMap(docs, graph) {
  const assignment = {}; // rel -> Set<domain>
  const note = {}; // rel -> hint
  for (const d of docs) {
    const dir = path.basename(path.dirname(d.rel));
    const um = graph.umbrellaGroups.find(g => g.members.includes(d.rel));
    if (um) {
      // umbrella members share one domain keyed by the umbrella id slug
      const domain = um.id.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
      (assignment[d.rel] ??= new Set()).add(domain);
      note[d.rel] = `umbrella ${um.id}`;
    } else {
      const domain = dir.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'general';
      (assignment[d.rel] ??= new Set()).add(domain);
      note[d.rel] = `dir hint ${dir}`;
    }
  }
  const domains = {};
  const unclear = [];
  for (const [rel, set] of Object.entries(assignment)) {
    if (set.size !== 1) { unclear.push(rel); continue; }
    const domain = [...set][0];
    (domains[domain] ??= { sources: [], confidence: 'heuristic' }).sources.push(rel);
  }
  for (const v of Object.values(domains)) v.sources.sort();
  unclear.sort();
  return {
    generated: 'phase1',
    approved: false,
    domains: Object.fromEntries(Object.entries(domains).sort(([a], [b]) => a.localeCompare(b))),
    unclear,
  };
}

// Gate: Phase 2 may only proceed when the persisted map is approved: true and
// has at least one domain with sources (Spec-AC-05 / TEST-113).
export function isApprovedMap(map) {
  if (!map || map.approved !== true) return false;
  const domains = map.domains ?? {};
  const entries = Object.entries(domains);
  if (entries.length === 0) return false;
  return entries.every(([slug, d]) => slug && asList(d?.sources).length > 0);
}

// --- link-integrity (Spec-AC-03 / SEAM-4) -----------------------------------

// Given the produced trees, verify the canonical sources: list and each
// archived doc's canonical: pointer resolve bidirectionally.
// Returns { ok, violations: [string] }.
export function checkLinkIntegrity(root, { canonicalDir = CANONICAL_DIR, archiveDir = ARCHIVE_DIR } = {}) {
  const violations = [];
  const canonAbs = path.join(root, canonicalDir);
  const archiveAbs = path.join(root, archiveDir);

  const canonicalFiles = fs.existsSync(canonAbs)
    ? fs.readdirSync(canonAbs).filter(f => f.endsWith('.md')) : [];
  for (const f of canonicalFiles) {
    const rel = path.join(canonicalDir, f);
    const fm = parseFrontmatter(fs.readFileSync(path.join(root, rel), 'utf8'));
    for (const src of asList(fm?.sources)) {
      if (!fs.existsSync(path.join(root, src))) {
        violations.push(`${rel}: dangling source "${src}"`);
      }
    }
  }
  // walk archive tree
  const walkArchive = (dir) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) { walkArchive(abs); continue; }
      if (!entry.name.endsWith('.md')) continue;
      const rel = path.relative(root, abs);
      const fm = parseFrontmatter(fs.readFileSync(abs, 'utf8'));
      const ptr = fm?.canonical ? String(fm.canonical).trim() : '';
      if (!ptr) { violations.push(`${rel}: missing canonical pointer`); continue; }
      if (!fs.existsSync(path.join(root, ptr))) {
        violations.push(`${rel}: dangling canonical pointer "${ptr}"`);
      }
    }
  };
  walkArchive(archiveAbs);
  return { ok: violations.length === 0, violations };
}

// --- drift comparator (Spec-AC-07) ------------------------------------------

// A domain is clean when the hash of every contributing source (in declared
// order) matches what was recorded at last synthesis; otherwise it drifted.
// sourceHashes: { rel -> sha256 } recorded in the map at synthesis time.
export function detectDrift(map, root) {
  const drifted = [];
  const clean = [];
  for (const [domain, d] of Object.entries(map.domains ?? {})) {
    const recorded = d.sourceHashes ?? {};
    const sources = asList(d.sources);
    const current = hashSources(root, sources, archivedResolver(d));
    let isDrift = false;
    for (const src of sources) {
      if (current[src] !== recorded[src]) { isDrift = true; break; }
    }
    if (isDrift) drifted.push(domain); else clean.push(domain);
  }
  return { drifted: drifted.sort(), clean: clean.sort() };
}

// Compute the source-BODY-hash map for a set of source rels under root.
// We hash the body only (frontmatter stripped) so that Phase-2's own
// frontmatter injection (status/canonical) does not register as drift; only a
// real content edit to a source/archived doc flips the hash.
// `resolve` maps a declared source rel to its current on-disk location (the
// archived copy after Phase 2). Missing files hash to null.
export function hashSources(root, sources, resolve = (s) => s) {
  const out = {};
  for (const src of sources) {
    const loc = resolve(src);
    const abs = path.join(root, loc);
    out[src] = fs.existsSync(abs) ? sha256(stripFrontmatter(fs.readFileSync(abs, 'utf8'))) : null;
  }
  return out;
}

// Resolve a declared source rel to its archived location given a map's
// recorded archivedAt table (falls back to the original rel).
function archivedResolver(domainEntry) {
  const at = domainEntry?.archivedAt ?? {};
  return (s) => at[s] ?? s;
}

// --- Phase 2: synthesis scaffold + archive move (Spec-AC-03/06) -------------

// Build the canonical doc text: frontmatter + the fixed sections
// (CANONICAL_SECTIONS — six since RFC-0011). The agent supplies
// per-section prose via `sectionBodies` (slug-keyed); deterministic code
// guarantees the section contract and provenance frontmatter. Superseded
// source back-links are harvested into the final section.
//
// `## Requirements` (RFC-0011, delta-spec lifecycle) is emitted as
// a SKELETON: the contract comment plus — when no `sectionBodies.requirements`
// content is supplied — an explicit empty-valid placeholder. Empty is a
// COMPLETE state (a domain may carry zero formalized requirements until specs
// declare deltas against it), so the generic `_To be synthesized._`
// placeholder is deliberately not used here.
export function renderCanonicalDoc({ domain, sources, supersededSources = [], sectionBodies = {} }) {
  const fm = [
    '---',
    `id: CANON-${domain}`,
    'type: canonical',
    `domain: ${domain}`,
    `status: accepted`,
    'sources:',
    ...sources.map(s => `  - ${s}`),
    '---',
    '',
  ];
  const lines = [`# Canonical: ${domain}`, ''];
  for (const section of CANONICAL_SECTIONS) {
    lines.push(`## ${section}`);
    lines.push('');
    if (section === 'Superseded decisions') {
      if (supersededSources.length === 0) {
        lines.push('_No superseded decisions harvested for this domain._');
      } else {
        for (const s of supersededSources) {
          lines.push(`- Superseded source: [${s}](${path.posix.relative(CANONICAL_DIR, s)})`);
        }
      }
      lines.push('');
    } else if (section === 'Requirements') {
      // Contract comment: continuation lines are indented so the example
      // heading is never parsed as a real `### ` requirement block.
      lines.push('<!-- Requirements contract (RFC-0011): each requirement block is');
      lines.push('  `### REQ-<DOMAIN>-NNN — <title>` + exactly one SHALL statement + optional');
      lines.push('  "- Scenario:" bullet(s) + a "Provenance:" line naming the spec that merged');
      lines.push('  it ("Provenance: —" until a close-time delta merge fills it).');
      lines.push(`  \`<DOMAIN>\` is the uppercase kebab→snake of this doc's domain slug`);
      lines.push(`  ("${domain}" -> "${domainToReqDomain(domain)}"). Ids are stable — never renumber, never reuse;`);
      lines.push('  a removed requirement retires its id. Shape: .aai/templates/CANONICAL_TEMPLATE.md -->');
      lines.push(sectionBodies.requirements ?? '_No requirements recorded for this domain yet._');
      lines.push('');
    } else {
      const slug = section.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
      lines.push(sectionBodies[slug] ?? '_To be synthesized._');
      lines.push('');
    }
  }
  return fm.join('\n') + lines.join('\n');
}

// Set/replace a frontmatter scalar field, preserving the rest of the doc.
function setFrontmatterField(content, key, value) {
  if (!content.startsWith('---\n')) {
    return `---\n${key}: ${value}\n---\n\n${content}`;
  }
  const end = content.indexOf('\n---', 4);
  const block = content.slice(4, end);
  const rest = content.slice(end + 4);
  const lines = block.split('\n');
  let replaced = false;
  const out = [];
  let skipNested = false;
  for (const line of lines) {
    const m = line.match(/^([a-zA-Z_][\w-]*):/);
    if (m && !line.startsWith(' ')) skipNested = (m[1] === key);
    if (m && m[1] === key && !line.startsWith(' ')) {
      out.push(`${key}: ${value}`);
      replaced = true;
      continue;
    }
    if (skipNested && (line.startsWith(' ') || line.trim().startsWith('-'))) continue;
    out.push(line);
  }
  if (!replaced) out.push(`${key}: ${value}`);
  return `---\n${out.join('\n')}\n---${rest}`;
}

// Compute the archive destination (archive-relative path) for a source rel,
// preserving the sub-structure under docs/. Shared by the move and the
// pre-flight plan validation so both reason about identical paths.
function archiveDestRel(srcRel, archiveDir) {
  const underDocs = srcRel.startsWith('docs/') ? srcRel.slice('docs/'.length) : srcRel;
  return path.join(archiveDir, underDocs);
}

// Validate the FULL set of planned archive moves before any mutation, so a
// malformed operator-approved map fails fast and never leaves a partially
// mutated tree (WARNING-1 remediation). Mirrors runPhase2's branching: only
// domains entering first-synthesis actually move sources. Pure read-only.
// Catches: one source assigned to more than one domain (the second move would
// crash mid-loop on a now-missing file), two sources colliding on a single
// archive destination, a destination that already exists on disk (silent
// overwrite), and a declared source that no longer exists. Returns
// { ok, errors:[string] } with errors sorted for determinism.
export function validatePhase2Plan(root, map, { canonicalDir = CANONICAL_DIR, archiveDir = ARCHIVE_DIR } = {}) {
  const errors = [];
  const sourceOwner = {}; // srcRel -> first domain that claimed it
  const destOwner = {};   // destRel -> first srcRel that maps there
  const isArchived = (rel) => rel.startsWith(archiveDir + '/') || rel.startsWith(archiveDir + path.sep);
  for (const [domain, d] of Object.entries(map.domains ?? {})) {
    // Review NB-2: reject an invalid domain slug HERE, at pre-flight, before any
    // archiveSource mutation. renderCanonicalDoc -> domainToReqDomain throws on
    // a bad slug, and render runs AFTER sources are archived — an unchecked bad
    // key left a half-mutated tree (sources archived, no canonical) that failed
    // the next preflight with "source does not exist".
    if (!DOMAIN_SLUG_RE.test(domain)) {
      errors.push(`domain key "${domain}" is not a valid slug (${DOMAIN_SLUG_RE}) — lowercase kebab-case required`);
      continue;
    }
    // domains that will skip or drift (recorded hashes + existing canonical)
    // do not move anything, so they impose no plan constraints.
    const recorded = d?.sourceHashes ?? null;
    const canonAbs = path.join(root, canonicalDir, `${domain}.md`);
    if (recorded && fs.existsSync(canonAbs)) continue;
    for (const src of asList(d?.sources)) {
      if (isArchived(src)) continue; // no-op move on idempotent re-run
      if (sourceOwner[src] === undefined) {
        sourceOwner[src] = domain;
      } else if (sourceOwner[src] !== domain) {
        errors.push(`source "${src}" assigned to multiple domains ("${sourceOwner[src]}" and "${domain}")`);
      }
      if (!fs.existsSync(path.join(root, src))) {
        errors.push(`domain "${domain}": source "${src}" does not exist (already archived or moved?)`);
        continue;
      }
      const destRel = archiveDestRel(src, archiveDir);
      if (destOwner[destRel] === undefined) {
        destOwner[destRel] = src;
      } else if (destOwner[destRel] !== src) {
        errors.push(`archive destination "${destRel}" claimed by both "${destOwner[destRel]}" and "${src}"`);
      }
      if (fs.existsSync(path.join(root, destRel))) {
        errors.push(`archive destination "${destRel}" already exists (refusing to overwrite)`);
      }
    }
  }
  return { ok: errors.length === 0, errors: [...new Set(errors)].sort() };
}

// Move a source doc into the archive tree preserving its relative path, set
// status: archived, and add the canonical: forward pointer. Returns the new
// archive-relative path. Idempotent: a doc already under archiveDir is skipped.
// Refuses to overwrite an existing archive file (defense-in-depth; runPhase2's
// pre-flight validatePhase2Plan normally catches this earlier).
export function archiveSource(root, srcRel, canonicalRel, { archiveDir = ARCHIVE_DIR } = {}) {
  if (srcRel.startsWith(archiveDir + '/') || srcRel.startsWith(archiveDir + path.sep)) {
    return srcRel; // already archived
  }
  const destRel = archiveDestRel(srcRel, archiveDir);
  const destAbs = path.join(root, destRel);
  const srcAbs = path.join(root, srcRel);
  let content = fs.readFileSync(srcAbs, 'utf8');
  content = setFrontmatterField(content, 'status', 'archived');
  content = setFrontmatterField(content, 'canonical', canonicalRel);
  fs.mkdirSync(path.dirname(destAbs), { recursive: true });
  if (fs.existsSync(destAbs)) {
    throw new Error(`archiveSource: refusing to overwrite existing archive file ${destRel}`);
  }
  fs.writeFileSync(destAbs, content);
  fs.rmSync(srcAbs);
  return destRel;
}

// Full Phase-2 run for one approved map. Writes canonical docs, moves sources
// to the archive with back-links, records source hashes into the map for drift,
// and skips unchanged domains on re-run (idempotence, Spec-AC-07).
// sectionContent: optional { domain -> { supersededSources, sectionBodies } }.
export function runPhase2(root, map, { canonicalDir = CANONICAL_DIR, archiveDir = ARCHIVE_DIR, sectionContent = {}, resync = false } = {}) {
  if (!isApprovedMap(map)) {
    throw new Error('runPhase2: refusing to run without an approved: true domain map');
  }
  // Fail-fast: validate every planned move before mutating anything, so a
  // malformed map never leaves a half-archived tree (WARNING-1 remediation).
  const plan = validatePhase2Plan(root, map, { canonicalDir, archiveDir });
  if (!plan.ok) {
    throw new Error('runPhase2: unsafe archive plan, aborting before any change:\n  - ' + plan.errors.join('\n  - '));
  }
  const result = { written: [], skipped: [], drifted: [], resynced: [], archived: [], map };
  fs.mkdirSync(path.join(root, canonicalDir), { recursive: true });

  for (const [domain, d] of Object.entries(map.domains)) {
    const sources = asList(d.sources);
    const recorded = d.sourceHashes ?? null;
    const canonRel = path.join(canonicalDir, `${domain}.md`);
    const canonAbs = path.join(root, canonRel);

    // re-run idempotence: unchanged sources + existing canonical => skip.
    // On re-run, sources already live under the archive — resolve and hash
    // their bodies so a real edit (not Phase-2's own frontmatter) flips drift.
    if (recorded && fs.existsSync(canonAbs)) {
      const rerunHashes = hashSources(root, sources, archivedResolver(d));
      const unchanged = sources.every(s => rerunHashes[s] === recorded[s]);
      if (unchanged) { result.skipped.push(domain); continue; }
      // changed source after synthesis => DRIFT. By default do NOT silently
      // overwrite; with resync the operator opts in to re-synthesizing the
      // canonical from the CURRENT (archived) sources and re-baselining the
      // drift hashes — the CLI path that resolves a drift without hand-editing
      // the map (WARNING-2 remediation).
      if (!resync) { result.drifted.push(domain); continue; }
      const resolve = archivedResolver(d);
      const archivedSources = sources.map(s => resolve(s));
      const extra = sectionContent[domain] ?? {};
      const supersededSources = extra.supersededSources ?? asList(d.supersededArchived);
      const text = renderCanonicalDoc({
        domain, sources: archivedSources, supersededSources,
        sectionBodies: extra.sectionBodies ?? {},
      });
      fs.writeFileSync(canonAbs, text);
      d.sourceHashes = rerunHashes; // re-baseline so the domain reads clean next run
      result.resynced.push(domain);
      continue;
    }

    // first synthesis: hash source bodies at their original location (keyed by
    // declared source rel) before moving them.
    const currentHashes = hashSources(root, sources);

    const extra = sectionContent[domain] ?? {};
    // classify which sources are superseded BEFORE the move (reads original fm)
    const supersededOriginals = sources.filter(s => {
      const fm = parseFrontmatter(fs.readFileSync(path.join(root, s), 'utf8'));
      return String(fm?.status ?? '').toLowerCase() === 'superseded';
    });

    // move sources to archive with back-links; record original->archive mapping.
    // The canonical's sources: list must point at the ARCHIVED locations so
    // bidirectional link-integrity resolves (Spec-AC-03 / SEAM-4).
    d.archivedAt = d.archivedAt ?? {};
    const archivedSources = [];
    const archivedSuperseded = [];
    for (const src of sources) {
      const dest = archiveSource(root, src, canonRel, { archiveDir });
      result.archived.push(dest);
      d.archivedAt[src] = dest;
      archivedSources.push(dest);
      if (supersededOriginals.includes(src)) archivedSuperseded.push(dest);
    }

    const supersededSources = extra.supersededSources ?? archivedSuperseded;
    const text = renderCanonicalDoc({
      domain, sources: archivedSources, supersededSources,
      sectionBodies: extra.sectionBodies ?? {},
    });
    fs.writeFileSync(canonAbs, text);
    result.written.push(domain);

    // record source-body hashes for future drift detection (idempotence + drift)
    d.sourceHashes = currentHashes;
    // persist which archived sources were superseded so a later --resync can
    // re-harvest them (the move overwrote their status to `archived`).
    d.supersededArchived = archivedSuperseded;
  }
  return result;
}

export function writeJson(root, rel, obj) {
  const abs = path.join(root, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, JSON.stringify(obj, null, 2) + '\n');
}

export function readJson(root, rel) {
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) return null;
  return JSON.parse(fs.readFileSync(abs, 'utf8'));
}
