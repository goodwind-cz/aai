// Test canonicalization core (RFC-0006 / SPEC-0008).
//
// Deterministic engine for the aai-test-canon skill: Phase-1 matrix builder +
// coverage gap report + proposal gate, Phase-2 consolidation + archive move +
// RED stub scaffold + runner verification, re-run drift comparator.
//
// No global side effects on import. File writes happen only in the explicit
// runPhase2 mutation path.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execSync } from 'node:child_process';
import { parseFrontmatter } from './docs-model.mjs';

export const PROPOSAL_PATH = 'docs/ai/test-canon.proposal.json';
export const MAP_PATH = 'docs/ai/test-canon.map.json';
export const CANONICAL_TEST_DIR = 'tests/canonical';
export const ARCHIVE_TEST_DIR = 'tests/_archive';
export const CANONICAL_DOMAIN_MAP_PATH = 'docs/ai/docs-canon.map.json';
export const CANONICAL_DOC_DIR = 'docs/canonical';
export const REPORT_DIR = 'docs/ai/reports';

export function sha256(s) {
  return crypto.createHash('sha256').update(s).digest('hex');
}

// Read all *.md files under a directory, returning { rel, content, fm }
function collectMdFiles(root, dirs) {
  const out = [];
  for (const d of dirs) {
    const abs = path.join(root, d);
    if (!fs.existsSync(abs)) continue;
    const visit = (dir) => {
      const absDir = path.join(root, dir);
      if (!fs.existsSync(absDir)) return;
      for (const entry of fs.readdirSync(absDir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
        const relChild = path.join(dir, entry.name);
        if (entry.isDirectory()) { visit(relChild); continue; }
        if (!entry.name.endsWith('.md')) continue;
        const fullPath = path.join(root, relChild);
        const content = fs.readFileSync(fullPath, 'utf8');
        out.push({ rel: relChild, content, fm: parseFrontmatter(content) });
      }
    };
    visit(d);
  }
  return out.sort((a, b) => a.rel.localeCompare(b.rel));
}

// Discover test files in known test directories
function collectTestFiles(root) {
  const testDirs = ['tests/skills', 'tests/self-hosting'];
  const out = [];
  for (const d of testDirs) {
    const abs = path.join(root, d);
    if (!fs.existsSync(abs)) continue;
    for (const entry of fs.readdirSync(abs, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (entry.isFile() && (entry.name.endsWith('.sh') || entry.name.endsWith('.ps1') || entry.name.endsWith('.py') || entry.name.endsWith('.mjs'))) {
        const rel = path.join(d, entry.name);
        const fullPath = path.join(root, rel);
        const content = fs.readFileSync(fullPath, 'utf8');
        out.push({ rel, content, name: entry.name });
      }
    }
  }
  return out;
}

// Extract acceptance criteria from a canonical doc
function extractCriteria(content) {
  const criteria = [];
  const lines = content.split('\n');
  let inSection = false;
  for (const line of lines) {
    if (/^##\s+Acceptance\s+Criteria/i.test(line)) {
      inSection = true;
      continue;
    }
    if (/^##\s+/i.test(line) && inSection) {
      inSection = false;
    }
    if (inSection) {
      const m = line.match(/^\s*[-*]\s+(.+)/);
      if (m) criteria.push(m[1].trim());
    }
  }
  return criteria;
}

// Determine which criteria are covered by source test contents.
// A criterion is considered "covered" if any source test's content
// mentions the criterion text or its AC-<domain>-N tag.
function findCoveredCriteria(sourceContents, criteria, domain) {
  const coveredIndexes = new Set();
  for (let i = 0; i < criteria.length; i++) {
    const crit = criteria[i];
    const criterionTag = `AC-${domain}-${i + 1}`;
    const isCovered = sourceContents.some(sc =>
      sc.content.includes(crit) || sc.content.includes(criterionTag)
    );
    if (isCovered) coveredIndexes.add(i);
  }
  return coveredIndexes;
}

// Map a test file to canonical domains based on content analysis
function mapTestToDomain(testContent, testName, domains) {
  const matches = [];
  for (const [slug] of Object.entries(domains)) {
    const slugClean = slug.toLowerCase().replace(/-/g, '');
    const nameClean = testName.toLowerCase().replace(/\.sh|\.ps1|\.py|\.mjs/g, '').replace(/test-/g, '').replace(/-/g, '');
    if (nameClean.includes(slugClean) || slugClean.includes(nameClean)) {
      if (!matches.includes(slug)) matches.push(slug);
    }
    // Check content for domain references
    if (testContent.includes(slug) || testContent.includes(`domain: ${slug}`)) {
      if (!matches.includes(slug)) matches.push(slug);
    }
  }
  return matches;
}

// Read the canonical domain map
function readCanonDomainMap(root) {
  const mapPath = path.join(root, CANONICAL_DOMAIN_MAP_PATH);
  if (!fs.existsSync(mapPath)) return null;
  return JSON.parse(fs.readFileSync(mapPath, 'utf8'));
}

// --- Phase 1: Build traceability matrix + coverage gap report + proposal ---

export function runPhase1(root) {
  // Check for docs/canonical/ presence (soft prerequisite)
  const canonDocDir = path.join(root, CANONICAL_DOC_DIR);
  const canonDocsExist = fs.existsSync(canonDocDir);
  let degradedMode = false;
  if (!canonDocsExist) {
    console.error('[WARN] docs/canonical/ directory not found — running in degraded mode');
    console.error('[WARN] Mapping against raw docs/ docs instead of canonical docs');
    degradedMode = true;
  }

  // Read canonical domain map
  const domainMap = readCanonDomainMap(root);
  const domains = domainMap?.domains ?? {};

  // Discover test files
  const testFiles = collectTestFiles(root);

  // Read canonical docs for acceptance criteria
  const criteriaMap = {}; // domain -> [criteria strings]
  if (canonDocsExist) {
    const canonDocs = collectMdFiles(root, [CANONICAL_DOC_DIR]);
    for (const doc of canonDocs) {
      const domain = doc.fm?.domain || path.basename(doc.rel, '.md');
      criteriaMap[domain] = extractCriteria(doc.content);
    }
  } else {
    // Degraded mode: extract criteria from raw docs/
    const rawDocs = collectMdFiles(root, ['docs']);
    for (const doc of rawDocs) {
      const domain = path.basename(path.dirname(doc.rel)) || 'general';
      const criteria = extractCriteria(doc.content);
      if (criteria.length > 0) {
        if (!criteriaMap[domain]) criteriaMap[domain] = [];
        criteriaMap[domain].push(...criteria);
      }
    }
  }

  // Build traceability matrix: test -> [domains] with confidence
  const matrix = {};
  const unclear = [];
  for (const tf of testFiles) {
    const matched = mapTestToDomain(tf.content, tf.name, domains);
    if (matched.length === 0) {
      unclear.push(tf.rel);
      matrix[tf.rel] = { domains: [], confidence: 'unclear' };
    } else if (matched.length === 1) {
      matrix[tf.rel] = { domains: matched, confidence: 'heuristic' };
    } else {
      matrix[tf.rel] = { domains: matched, confidence: 'multiple' };
      unclear.push(tf.rel);
    }
  }

  // Build coverage gap report — per-criterion check
  const coverage = {};
  for (const [domain, criteria] of Object.entries(criteriaMap)) {
    const covered = [];
    const uncovered = [];
    // Collect source test contents for this domain for per-criterion matching
    const domainSourceContents = [];
    for (const [rel, m] of Object.entries(matrix)) {
      if (m.domains.includes(domain)) {
        const tf = testFiles.find(t => t.rel === rel);
        if (tf) domainSourceContents.push({ rel, content: tf.content });
      }
    }
    // Use the SAME text-OR-tag predicate as Phase 2 (findCoveredCriteria) so the
    // two phases agree: a source referencing the stable AC-<domain>-N tag (not the
    // full criterion text) is reported COVERED, not a false uncovered gap.
    const coveredIndexes = findCoveredCriteria(domainSourceContents, criteria, domain);
    for (let i = 0; i < criteria.length; i++) {
      if (coveredIndexes.has(i)) covered.push(criteria[i]);
      else uncovered.push(criteria[i]);
    }
    coverage[domain] = { covered, uncovered, total: criteria.length };
  }

  // Build proposed domain assignment
  const proposedDomains = {};
  for (const [rel, m] of Object.entries(matrix)) {
    if (m.confidence === 'unclear' || m.confidence === 'multiple') continue;
    for (const d of m.domains) {
      if (!proposedDomains[d]) proposedDomains[d] = { sources: [], confidence: 'heuristic' };
      if (!proposedDomains[d].sources.includes(rel)) proposedDomains[d].sources.push(rel);
    }
  }
  for (const v of Object.values(proposedDomains)) v.sources.sort();

  // Write proposal
  const proposal = {
    generated: 'phase1',
    approved: false,
    degraded: degradedMode,
    generatedAt: new Date().toISOString(),
    domains: proposedDomains,
    unclear: unclear.sort(),
    coverage,
  };

  const proposalAbs = path.join(root, PROPOSAL_PATH);
  fs.mkdirSync(path.dirname(proposalAbs), { recursive: true });
  fs.writeFileSync(proposalAbs, JSON.stringify(proposal, null, 2) + '\n');

  // Write human-readable coverage report
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 20);
  const reportPath = path.join(root, REPORT_DIR, `test-canon-coverage-${timestamp}.md`);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });

  const reportLines = [
    `# Test Canonicalization Coverage Report (Phase 1)`,
    ``,
    `Generated: ${new Date().toISOString()}`,
    `Degraded mode: ${degradedMode}`,
    ``,
    `## Traceability Matrix`,
    ``,
    `| Test File | Assigned Domain(s) | Confidence |`,
    `|-----------|-------------------|------------|`,
  ];
  for (const [rel, m] of Object.entries(matrix)) {
    const domainsStr = m.domains.length > 0 ? m.domains.join(', ') : '(unclear)';
    reportLines.push(`| ${rel} | ${domainsStr} | ${m.confidence} |`);
  }

  reportLines.push(``);
  reportLines.push(`## Coverage Gap Report`);
  reportLines.push(``);
  for (const [domain, c] of Object.entries(coverage)) {
    reportLines.push(`### ${domain}`);
    reportLines.push(`- Total criteria: ${c.total}`);
    reportLines.push(`- Covered: ${c.covered.length}`);
    reportLines.push(`- Uncovered: ${c.uncovered.length}`);
    if (c.uncovered.length > 0) {
      for (const u of c.uncovered) {
        reportLines.push(`  - ${u} (NO COVERING TEST)`);
      }
    }
    reportLines.push(``);
  }

  if (unclear.length > 0) {
    reportLines.push(`### Unclear Bucket`);
    reportLines.push(``);
    for (const u of unclear) {
      reportLines.push(`- ${u} — cannot be confidently mapped`);
    }
    reportLines.push(``);
  }

  reportLines.push(`## Proposed Domain Assignment`);
  reportLines.push(``);
  for (const [domain, pd] of Object.entries(proposedDomains)) {
    reportLines.push(`- **${domain}**: ${pd.sources.length} test(s) — ${pd.confidence}`);
    for (const s of pd.sources) {
      reportLines.push(`  - ${s}`);
    }
  }
  reportLines.push(``);

  fs.writeFileSync(reportPath, reportLines.join('\n') + '\n');

  return {
    proposal,
    reportPath: path.relative(root, reportPath),
    testFiles: testFiles.length,
    degraded: degradedMode,
  };
}

// --- Approval gate ---

export function isApprovedMap(map) {
  if (!map || map.approved !== true) return false;
  const domains = map.domains ?? {};
  const entries = Object.entries(domains);
  if (entries.length === 0) return false;
  return entries.every(([slug, d]) => slug && (d?.sources || []).length > 0);
}

// --- Phase 2: Consolidate, archive, scaffold stubs ---

// Build a canonical test file content from sources and stubs
// Sources provide the actual test logic (run via bash on the archived copy);
// stubs are RED (failing) placeholders for uncovered criteria.
// dispatch: [{ rel, execRel, runner }] — each source paired with its own exec
// path and native runner so paths/runners always align with the actual source.
function renderCanonicalTest(domain, sources, dispatch, stubs) {
  const lines = [
    '#!/usr/bin/env bash',
    '#',
    `# Canonical test suite for domain: ${domain}`,
    '# Auto-generated by aai-test-canon (Phase 2)',
    '#',
    '# Sources:',
    ...sources.map(s => `#   ${s}`),
    '#',
    '# Archive:',
    ...dispatch.map(d => `#   ${d.execRel}`),
    '#',
    '# Stubs (uncovered criteria):',
    ...stubs.map(s => `#   ${s.tag}`),
    '#',
    'set -euo pipefail',
    '',
    `TEST_DOMAIN="${domain}"`,
    '',
  ];

  // Stubs for uncovered criteria — RED (failing) placeholders
  // Use return 1 (not exit 1) so run_all can tally passed/failed
  for (const stub of stubs) {
    lines.push(`test_${stub.criterionTag}() {`);
    lines.push(`  echo "FAIL (RED stub): ${stub.tag} — not yet implemented"`);
    lines.push('  return 1');
    lines.push('}');
    lines.push('');
  }

  lines.push('# Run all tests');
  lines.push('# When AAI_SKIP_STUBS=1, stubs are skipped so verifyRunner can check green exit.');
  lines.push('run_all() {');
  lines.push('  local passed=0');
  lines.push('  local failed=0');
  lines.push('  local total=0');
  lines.push('');

  // Run each source test via its NATIVE runner on the (archived) copy. Each
  // source is paired with its own exec path + runner so a .mjs/.py/.ps1 source
  // is dispatched correctly and paths never misalign with source contents.
  for (const d of dispatch) {
    lines.push(`  total=$((total + 1))`);
    lines.push(`  if ${d.runner} "${d.execRel}" 2>/dev/null; then passed=$((passed + 1)); else failed=$((failed + 1)); fi`);
  }

  // Only emit the stub-runner wrapper when there are stubs. An
  // `if ... then ... fi` with an empty body is a bash syntax error, which
  // would break `bash -n` for any fully-covered domain (0 stubs).
  if (stubs.length > 0) {
    lines.push('');
    lines.push('  # Stubs — skipped when AAI_SKIP_STUBS is set (verify mode)');
    lines.push('  if [ -z "${AAI_SKIP_STUBS:-}" ]; then');
    for (const stub of stubs) {
      lines.push(`    total=$((total + 1))`);
      lines.push(`    if test_${stub.criterionTag} 2>/dev/null; then passed=$((passed + 1)); else failed=$((failed + 1)); fi`);
    }
    lines.push('  fi');
  }

  lines.push('');
  lines.push('  echo "Canonical suite ${TEST_DOMAIN}: ${passed}/${total} passed, ${failed} failed"');
  lines.push('  return $failed');
  lines.push('}');
  lines.push('');
  lines.push('run_all');

  return lines.join('\n');
}

// Generate a stub-only test file for an uncovered criterion (syntactically valid, RED)
function renderStubFile(domain, criterionTag, criterionText) {
  const lines = [
    '#!/usr/bin/env bash',
    '#',
    `# RED stub for: ${criterionTag}`,
    `# Domain: ${domain}`,
    `# Criterion: ${criterionText}`,
    '#',
    '# This is a RED (failing) stub scaffolded by aai-test-canon.',
    '# Implement GREEN via aai-tdd.',
    '#',
    'set -euo pipefail',
    '',
    `echo "FAIL (RED stub): ${criterionTag} — not yet implemented"`,
    'exit 1',
    '',
  ];
  return lines.join('\n');
}

// Compute archive destination for a source test file
function archiveDestRel(srcRel) {
  // Map tests/skills/foo.sh -> skills/foo.sh (strip tests/ prefix)
  // Then tests/_archive/ is prepended by the caller
  if (srcRel.startsWith('tests/')) {
    return srcRel.slice('tests/'.length);
  }
  return srcRel;
}

// Choose the first runner available on PATH; fall back to the first candidate.
function resolveRunner(candidates) {
  for (const r of candidates) {
    try {
      execSync(`command -v ${r}`, { stdio: 'ignore' });
      return r;
    } catch { /* not installed — try next candidate */ }
  }
  return candidates[0];
}

// Pick the native runner for a source test by extension.
function runnerForExt(rel) {
  if (rel.endsWith('.ps1')) return resolveRunner(['pwsh', 'powershell']);
  if (rel.endsWith('.py')) return resolveRunner(['python3', 'python']);
  if (rel.endsWith('.mjs')) return 'node';
  return 'bash';
}

// Comment prefix for a source's language (so the archive back-link stays a valid
// comment when the archived copy is run by its native runner).
function commentPrefixForExt(rel) {
  if (rel.endsWith('.mjs') || rel.endsWith('.js')) return '//';
  return '#'; // .sh, .py, .ps1
}

// Prepend a "Canonical: <path>" back-link to an archived source WITHOUT breaking
// it: inserted AFTER a leading shebang (a shebang is only valid on line 1 — for
// JS a `#!` on line 2 is a syntax error) using a language-appropriate comment.
function withBacklink(content, canonTestRel, rel) {
  const backlink = `${commentPrefixForExt(rel)} Canonical: ${canonTestRel}`;
  if (content.startsWith('#!')) {
    const nl = content.indexOf('\n');
    if (nl === -1) return `${content}\n${backlink}\n`;
    return content.slice(0, nl + 1) + backlink + '\n' + content.slice(nl + 1);
  }
  return `${backlink}\n${content}`;
}

// Verify that canonical tests are runnable via existing runners (syntax check + runtime)
export function verifyRunner(root, canonicalDir) {
  const canonAbs = path.join(root, canonicalDir);
  if (!fs.existsSync(canonAbs)) return { ok: false, errors: ['canonical test directory not found'] };

  const errors = [];
  for (const entry of fs.readdirSync(canonAbs, { withFileTypes: true })) {
    // Skip stub files — they are standalone RED scripts expected to fail
    if (entry.isFile() && entry.name.endsWith('.sh') && !entry.name.includes('.stub')) {
      const abs = path.join(canonAbs, entry.name);
      try {
        const content = fs.readFileSync(abs, 'utf8');
        // Shebang check
        if (!content.startsWith('#!/usr/bin/env bash')) {
          errors.push(`${entry.name}: missing shebang`);
          continue;
        }
        // Syntax check via bash -n
        try {
          execSync(`bash -n "${abs}"`, { stdio: ['ignore', 'pipe', 'pipe'] });
        } catch (synErr) {
          errors.push(`${entry.name}: syntax check failed (bash -n): ${synErr.stderr?.toString().trim() || synErr.message}`);
          continue;
        }
        // Runtime check — verify real tests exit GREEN (exit 0).
        // Stubs are skipped via AAI_SKIP_STUBS=1 so only real test logic runs.
        try {
          execSync(`AAI_SKIP_STUBS=1 bash "${abs}"`, { stdio: ['ignore', 'pipe', 'pipe'], timeout: 10000 });
        } catch (runErr) {
          // Non-zero exit means real tests failed — gate must block archiving
          if (runErr.signal) {
            errors.push(`${entry.name}: runtime crash (${runErr.signal})`);
          } else {
            errors.push(`${entry.name}: real tests exited non-zero (${runErr.status}) — suite not green`);
          }
        }
      } catch (e) {
        errors.push(`${entry.name}: ${e.message}`);
      }
    }
  }

  return { ok: errors.length === 0, errors };
}

// Run Phase 2: consolidate, archive, scaffold stubs
export function runPhase2(root, map, { resync = false } = {}) {
  if (!isApprovedMap(map)) {
    throw new Error('runPhase2: refusing to run without an approved: true domain map');
  }

  const result = { written: [], skipped: [], drifted: [], resynced: [], archived: [], map };

  const canonDir = path.join(root, CANONICAL_TEST_DIR);
  const archiveDir = path.join(root, ARCHIVE_TEST_DIR);
  fs.mkdirSync(canonDir, { recursive: true });
  fs.mkdirSync(archiveDir, { recursive: true });

  // Read canonical docs for acceptance criteria
  const canonDocDir = path.join(root, CANONICAL_DOC_DIR);
  const criteriaMap = {};
  if (fs.existsSync(canonDocDir)) {
    const canonDocs = collectMdFiles(root, [CANONICAL_DOC_DIR]);
    for (const doc of canonDocs) {
      const domain = doc.fm?.domain || path.basename(doc.rel, '.md');
      criteriaMap[domain] = extractCriteria(doc.content);
    }
  }

  for (const [domain, d] of Object.entries(map.domains)) {
    const sources = d.sources || [];
    if (sources.length === 0) continue;

    const recorded = d.sourceHashes ?? null;
    const canonTestRel = path.join(CANONICAL_TEST_DIR, `${domain}.sh`);
    const canonTestAbs = path.join(root, canonTestRel);

    // Re-run idempotence: unchanged sources + existing canonical => skip
    let isDrifted = false;
    if (recorded && fs.existsSync(canonTestAbs)) {
      const rerunHashes = hashTestSources(root, sources, d.archivedAt);
      const unchanged = sources.every(s => rerunHashes[s] === recorded[s]);
      if (unchanged) { result.skipped.push(domain); continue; }
      isDrifted = true;
      result.drifted.push(domain);
      if (!resync) { continue; } // Skip processing if not resyncing
    }

    // Track whether this domain was previously drifted and is now being re-synced
    const wasDrifted = resync && isDrifted;

    // Collect source test contents (from original or archived locations)
    const sourceContents = [];
    for (const src of sources) {
      const srcAbs = path.join(root, src);
      if (fs.existsSync(srcAbs)) {
        sourceContents.push({ rel: src, content: fs.readFileSync(srcAbs, 'utf8') });
      } else if (d.archivedAt?.[src]) {
        const archivedAbs = path.join(root, d.archivedAt[src]);
        if (fs.existsSync(archivedAbs)) {
          sourceContents.push({ rel: src, content: fs.readFileSync(archivedAbs, 'utf8') });
        }
      }
    }

    // Determine which criteria are covered by source tests
    const domainCriteria = criteriaMap[domain] || [];
    const coveredIndexes = findCoveredCriteria(sourceContents, domainCriteria, domain);

    // Generate stubs only for UNCOVERED criteria
    const stubs = [];
    for (let i = 0; i < domainCriteria.length; i++) {
      if (coveredIndexes.has(i)) continue; // skip covered criteria
      const crit = domainCriteria[i];
      const criterionTag = `AC-${domain}-${i + 1}`;
      stubs.push({
        tag: `${domain}:${criterionTag}`,
        criterionTag,
        text: crit,
      });
    }

    // Pair each source with its OWN exec path + native runner so paths/runners
    // always align with the actual source content (never indexed positionally,
    // which misaligns when sourceContents is a subset of sources).
    // Step 1 dispatch: verify against EXISTING paths (original, archived fallback).
    const dispatchVerify = sourceContents.map(sc => {
      const src = sc.rel;
      let execRel = src; // original path if it still exists
      if (!fs.existsSync(path.join(root, src)) && d.archivedAt?.[src]) {
        const archivedAbs = path.join(root, d.archivedAt[src]);
        if (fs.existsSync(archivedAbs)) execRel = d.archivedAt[src];
      }
      return { rel: src, execRel, runner: runnerForExt(src) };
    });
    // Step 4 dispatch: final canonical references the stable archived copies.
    const dispatchFinal = sourceContents.map(sc => ({
      rel: sc.rel,
      execRel: path.join(ARCHIVE_TEST_DIR, archiveDestRel(sc.rel)),
      runner: runnerForExt(sc.rel),
    }));

    // --- Step 1: Write canonical test with EXISTING source paths for verification ---
    const testContentVerify = renderCanonicalTest(domain, sourceContents.map(s => s.rel), dispatchVerify, stubs);
    fs.writeFileSync(canonTestAbs, testContentVerify);
    fs.chmodSync(canonTestAbs, 0o755);

    // Write stub files for each uncovered criterion
    for (const stub of stubs) {
      const stubPath = path.join(canonDir, `${domain}.${stub.criterionTag}.stub.sh`);
      fs.writeFileSync(stubPath, renderStubFile(domain, stub.criterionTag, stub.text));
      fs.chmodSync(stubPath, 0o755);
    }

    // --- Step 2: Verify canonical tests run green BEFORE archiving ---
    // This gate ensures real test logic is preserved and runnable.
    const verification = verifyRunner(root, CANONICAL_TEST_DIR);
    if (!verification.ok) {
      for (const err of verification.errors) {
        console.error(`[ERROR] Runner verification failed: ${err}`);
      }
      console.error('[ERROR] Aborting Phase 2 before archiving — canonical tests are not runnable');
      if (fs.existsSync(canonTestAbs)) fs.rmSync(canonTestAbs);
      for (const stub of stubs) {
        const stubPath = path.join(canonDir, `${domain}.${stub.criterionTag}.stub.sh`);
        if (fs.existsSync(stubPath)) fs.rmSync(stubPath);
      }
      throw new Error(`Runner verification failed for domain "${domain}" — aborting before archive`);
    }

    // --- Step 3: Move originals to archive with back-links ---
    // The archive step is atomic per domain: if any git mv fails partway
    // through, the sources already moved in this loop are rolled back to their
    // original paths so the repo returns to its pre-Phase-2 state.
    d.archivedAt = d.archivedAt ?? {};
    const archiveErrors = [];
    const movedSources = []; // { src, srcAbs, destRel, destAbs, originalContent }
    for (const src of sources) {
      const srcAbs = path.join(root, src);
      if (!fs.existsSync(srcAbs)) continue;

      const destRel = path.join(ARCHIVE_TEST_DIR, archiveDestRel(src));
      const destAbs = path.join(root, destRel);

      let content;
      try {
        content = fs.readFileSync(srcAbs, 'utf8');
      } catch (readErr) {
        archiveErrors.push(`Failed to read ${srcAbs}: ${readErr.message}`);
        break;
      }

      fs.mkdirSync(path.dirname(destAbs), { recursive: true });

      try {
        execSync(`git mv "${srcAbs}" "${destAbs}"`, { stdio: ['ignore', 'pipe', 'pipe'] });
      } catch (mvErr) {
        archiveErrors.push(`git mv failed for ${srcAbs} -> ${destAbs}: ${mvErr.stderr?.toString().trim() || mvErr.message}`);
        break;
      }

      const originalContent = content;
      content = withBacklink(content, canonTestRel, src);
      fs.writeFileSync(destAbs, content);
      result.archived.push(destRel);
      d.archivedAt[src] = destRel;
      movedSources.push({ src, srcAbs, destRel, destAbs, originalContent });
    }

    if (archiveErrors.length > 0) {
      for (const err of archiveErrors) {
        console.error(`[ERROR] Archive move failed: ${err}`);
      }
      // Roll back the sources already archived for THIS domain so the archive
      // step is atomic — move each back to its original path, restore the
      // original content (dropping the prepended back-link), and undo the
      // archived-source bookkeeping.
      for (const moved of movedSources.reverse()) {
        try {
          execSync(`git mv -f "${moved.destAbs}" "${moved.srcAbs}"`, { stdio: ['ignore', 'pipe', 'pipe'] });
        } catch (rbErr) {
          console.error(`[ERROR] Rollback git mv failed for ${moved.destAbs} -> ${moved.srcAbs}: ${rbErr.stderr?.toString().trim() || rbErr.message}`);
        }
        if (fs.existsSync(moved.srcAbs)) fs.writeFileSync(moved.srcAbs, moved.originalContent);
        const ai = result.archived.indexOf(moved.destRel);
        if (ai >= 0) result.archived.splice(ai, 1);
        delete d.archivedAt[moved.src];
      }
      console.error('[ERROR] Aborting Phase 2 — archive moves incomplete, rolled back partial archive and cleaning up written canonical files');
      if (fs.existsSync(canonTestAbs)) fs.rmSync(canonTestAbs);
      for (const stub of stubs) {
        const stubPath = path.join(canonDir, `${domain}.${stub.criterionTag}.stub.sh`);
        if (fs.existsSync(stubPath)) fs.rmSync(stubPath);
      }
      throw new Error(`Archive move failed for domain "${domain}" — partial archive rolled back`);
    }

    // --- Step 4: Rewrite canonical test with archive paths (now exist) ---
    // This ensures the canonical suite references the stable archived copies,
    // not the (now-moved) original locations.
    const testContentFinal = renderCanonicalTest(domain, sourceContents.map(s => s.rel), dispatchFinal, stubs);
    fs.writeFileSync(canonTestAbs, testContentFinal);

    // --- Step 4b: RE-VERIFY against the archive paths ---
    // A source test that derives its location from BASH_SOURCE/$0 can pass at its
    // ORIGINAL path but FAIL once executed from tests/_archive/ (different repo
    // root / path depth). Step 2's green gate ran against the originals, so we
    // MUST re-verify now that the canonical points at the archived copies. If it
    // fails, roll the archive back and abort so a suite that only breaks once
    // archived never silently ships.
    const reverification = verifyRunner(root, CANONICAL_TEST_DIR);
    if (!reverification.ok) {
      for (const err of reverification.errors) {
        console.error(`[ERROR] Post-archive runner verification failed: ${err}`);
      }
      // Roll the archive back: move each archived copy to its original path,
      // restore original content (dropping the back-link), and undo bookkeeping —
      // reusing the same movedSources rollback as the Step 3 archive-move failure.
      for (const moved of movedSources.reverse()) {
        try {
          execSync(`git mv -f "${moved.destAbs}" "${moved.srcAbs}"`, { stdio: ['ignore', 'pipe', 'pipe'] });
        } catch (rbErr) {
          console.error(`[ERROR] Rollback git mv failed for ${moved.destAbs} -> ${moved.srcAbs}: ${rbErr.stderr?.toString().trim() || rbErr.message}`);
        }
        if (fs.existsSync(moved.srcAbs)) fs.writeFileSync(moved.srcAbs, moved.originalContent);
        const ai = result.archived.indexOf(moved.destRel);
        if (ai >= 0) result.archived.splice(ai, 1);
        delete d.archivedAt[moved.src];
      }
      console.error('[ERROR] Aborting Phase 2 — canonical suite fails once archived; rolled back archive and cleaning up canonical files');
      if (fs.existsSync(canonTestAbs)) fs.rmSync(canonTestAbs);
      for (const stub of stubs) {
        const stubPath = path.join(canonDir, `${domain}.${stub.criterionTag}.stub.sh`);
        if (fs.existsSync(stubPath)) fs.rmSync(stubPath);
      }
      throw new Error(`Post-archive runner verification failed for domain "${domain}" — rolled back archive`);
    }

    // Update result tracking — resynced domains should not also appear as drifted
    if (wasDrifted) {
      result.resynced.push(domain);
      // Remove from drifted list to avoid double-counting in CLI output
      const idx = result.drifted.indexOf(domain);
      if (idx >= 0) result.drifted.splice(idx, 1);
    } else {
      result.written.push(domain);
    }

    // Record source hashes from archived paths (originals no longer exist)
    d.sourceHashes = hashTestSources(root, d.sources, d.archivedAt);
  }

  return result;
}

// Hash test source files for drift detection.
// When archivedAt is provided, falls back to archived paths when originals don't exist.
function hashTestSources(root, sources, archivedAt) {
  const out = {};
  for (const src of sources) {
    const abs = path.join(root, src);
    if (fs.existsSync(abs)) {
      const content = fs.readFileSync(abs, 'utf8');
      out[src] = sha256(content);
    } else if (archivedAt?.[src]) {
      const archivedAbs = path.join(root, archivedAt[src]);
      if (fs.existsSync(archivedAbs)) {
        const content = fs.readFileSync(archivedAbs, 'utf8');
        out[src] = sha256(content);
      } else {
        out[src] = null;
      }
    } else {
      out[src] = null;
    }
  }
  return out;
}

// --- Drift detection ---

export function detectDrift(map, root) {
  const drifted = [];
  const clean = [];
  for (const [domain, d] of Object.entries(map.domains ?? {})) {
    const recorded = d.sourceHashes ?? {};
    const sources = d.sources || [];
    const current = hashTestSources(root, sources, d.archivedAt);
    let isDrift = false;
    for (const src of sources) {
      if (current[src] !== recorded[src]) { isDrift = true; break; }
    }
    if (isDrift) drifted.push(domain); else clean.push(domain);
  }
  return { drifted: drifted.sort(), clean: clean.sort() };
}

// --- JSON I/O ---

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
