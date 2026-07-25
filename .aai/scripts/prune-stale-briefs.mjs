// prune-stale-briefs.mjs — sweep stale work-item briefs (AAI docs-lifecycle hygiene).
//
// A brief `docs/ai/briefs/<REF-ID>.md` is a Planning-emitted subagent handoff — a
// gitignored runtime artifact (like docs/ai/reports/). It is LIVE only while its
// work item is OPEN; once the item reaches a terminal status
// (done | deferred | rejected | superseded | legacy) — or its doc no longer exists
// at all (an orphan) — the brief is dead clutter. `close-work-item.mjs` prunes the
// brief of the doc IT closes, but briefs closed BEFORE that hook shipped, or in
// bulk, accumulate as a backlog. This sweep prunes every stale brief in one pass.
// It ships in the .aai layer so ANY AAI project (not just this repo) sweeps its own
// briefs — the fix is at the framework level, not a one-off local `rm`.
//
// SAFE BY CONSTRUCTION: a brief is pruned ONLY when a scanned doc matching its name
// (by frontmatter slug id OR numbered display id) is terminal, or when NO doc
// matches it (orphan). A brief whose work item is still open is always KEPT — a
// live handoff is never removed.
//
// Usage:
//   node .aai/scripts/prune-stale-briefs.mjs [--dry-run] [--json]
//     --dry-run  report what WOULD be pruned; remove nothing.
//     --json     machine-readable summary on stdout.
// Exit 0 always (best-effort housekeeping — never blocks a caller). Node stdlib only.

import { readFileSync, readdirSync, rmSync, existsSync } from 'node:fs';
import path from 'node:path';
import { parseFrontmatter, extractDocIds, DEFAULT_CATEGORY_PREFIXES } from './lib/docs-model.mjs';
import { scanAuditDocs } from './lib/docs-audit-core.mjs';

// Statuses at which a work item is still in flight, so its brief is a LIVE handoff.
// Every other DOC_STATUS_ENUM value (done|deferred|rejected|superseded|legacy) is
// terminal — the brief is consumed and safe to prune.
const OPEN_STATUSES = new Set(['draft', 'proposed', 'accepted', 'implementing', 'frozen']);

const ROOT = process.cwd();
const BRIEFS_DIR = path.join(ROOT, 'docs', 'ai', 'briefs');

// Map EVERY doc identifier (frontmatter slug id AND numbered display id) -> status,
// so a brief named by either form resolves to its doc's lifecycle status.
function buildStatusIndex() {
  const idx = new Map();
  for (const { rel } of scanAuditDocs(ROOT)) {
    let fm;
    try { fm = parseFrontmatter(readFileSync(path.join(ROOT, rel), 'utf8')); } catch { continue; }
    if (!fm) continue;
    const status = String(fm.status || '').toLowerCase();
    if (!status) continue;
    const display = extractDocIds(path.basename(rel), DEFAULT_CATEGORY_PREFIXES);
    for (const key of [fm.id, display && display.primary].filter(Boolean)) {
      // First writer wins is fine — a doc's ids are unique; a later duplicate id is
      // itself a docs-audit finding, not this sweep's concern.
      if (!idx.has(key)) idx.set(key, status);
    }
  }
  return idx;
}

function main() {
  const dryRun = process.argv.includes('--dry-run');
  const asJson = process.argv.includes('--json');

  const pruned = [];
  const kept = [];

  if (existsSync(BRIEFS_DIR)) {
    const index = buildStatusIndex();
    const briefs = readdirSync(BRIEFS_DIR).filter((f) => f.endsWith('.md') && f !== '.gitkeep');
    for (const file of briefs) {
      const name = file.replace(/\.md$/i, '');
      const status = index.get(name);
      if (status && OPEN_STATUSES.has(status)) {
        kept.push({ file, status });
        continue;
      }
      const reason = status ? `terminal (${status})` : 'orphan (no matching doc)';
      if (!dryRun) {
        try { rmSync(path.join(BRIEFS_DIR, file)); } catch { /* best-effort */ }
      }
      pruned.push({ file, reason });
    }
  }

  if (asJson) {
    process.stdout.write(JSON.stringify({ dry_run: dryRun, pruned, kept_open: kept.length }, null, 2) + '\n');
  } else if (pruned.length === 0) {
    // Silent-ish: one line so a wrap-up caller can include it only when it did work.
    process.stdout.write(`prune-stale-briefs: nothing to prune (${kept.length} live brief(s) kept)\n`);
  } else {
    const verb = dryRun ? 'would prune' : 'pruned';
    process.stdout.write(`prune-stale-briefs: ${verb} ${pruned.length} stale brief(s), kept ${kept.length} live:\n`);
    for (const p of pruned) process.stdout.write(`  - ${p.file} (${p.reason})\n`);
  }
  process.exit(0);
}

main();
