#!/usr/bin/env node
// close-before-push-guard.mjs — deterministic close-BEFORE-push ordering gate
// (fu-close-before-push-ordering, ride ref close-ceremony-ordering).
//
// THE INCIDENT this replaces: the correct PR ceremony order runs
// close-work-item.mjs BEFORE the push, not after — validation round 4 of
// spec-deslop-corpus-honesty measured that 5 tests/skills/test-framework.sh
// reds are ride-caused and clear ONLY once close-work-item.mjs has run;
// pushing first means CI reads those reds as genuine failures and a ride
// spends a whole diagnostic round rediscovering the same thing every time.
// Until this guard, the ordering was prose an agent had to remember
// (.aai/SKILL_PR.prompt.md step 5c ran AFTER push+PR-open). It is now a
// mechanized precondition check, mirroring branch-guard.mjs's shape: fails
// CLOSED before the push line in SKILL_PR step 5 when the current ref's
// primary work-item doc has not already been closed (frontmatter status
// still open) in step 4c.
//
// READ-ONLY: resolves the doc via the SAME two-pass scan (frontmatter `id`
// then filename-derived display-id) close-work-item.mjs's own resolveDoc
// uses, via the shared docs-audit-core / docs-model libraries. Never writes
// anything.
//
// CLI: node close-before-push-guard.mjs --ref <slug> [--root <dir>]
//   --ref <slug>   the primary work-item doc's frontmatter slug `id`
//                  (the same --ref close-work-item.mjs was/will be given).
//   --root <dir>   repo root to scan; default process.cwd().
//
// Exit codes:
//   0 — the doc resolves and its frontmatter status is `done` (step 4c's
//       close-work-item.mjs --pr TBD already ran) — push is safe.
//   1 — the doc resolves but status is NOT `done` — step 4c has not run (or
//       failed) yet. REFUSED; names the remediation command.
//   2 — usage error: missing --ref, or the ref does not resolve to exactly
//       one scanned doc (unresolvable / ambiguous) — fail-closed, never a
//       silent pass.
//
// Node stdlib + the shared docs-audit-core/docs-model libraries only
// (docs/TECHNOLOGY.md). No forked scanning/parsing logic.

import fs from 'node:fs';
import path from 'node:path';
import { scanAuditDocs, loadConfig } from './lib/docs-audit-core.mjs';
import { parseFrontmatter, extractDocIds, DEFAULT_CATEGORY_PREFIXES, slugFamilyForPath } from './lib/docs-model.mjs';

function usageError(msg) {
  process.stderr.write(`close-before-push-guard: ${msg}\n`);
  process.stderr.write('usage: node .aai/scripts/close-before-push-guard.mjs --ref <slug> [--root <dir>]\n');
  process.exit(2);
}

function parseArgs(argv) {
  const args = { root: process.cwd() };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--ref') args.ref = argv[++i];
    else if (tok === '--root') args.root = argv[++i];
    else usageError(`unrecognized flag: ${tok}`);
  }
  if (!args.ref) usageError('missing --ref');
  return args;
}

// Same two-pass resolution close-work-item.mjs's resolveDoc uses (frontmatter
// `id` first, then filename-derived display-id fallback), minus the write-
// path concerns (product-doc exclusion is irrelevant here — a product doc
// never carries the work-item status this guard reads).
function resolveDocStatus(root, slug) {
  const config = loadConfig(root);
  const files = scanAuditDocs(root, { scanExclude: config?.scan_exclude ?? [] })
    .filter((f) => slugFamilyForPath(f.rel)?.type !== 'product');
  const categoryPrefixes = config?.category_prefixes ?? DEFAULT_CATEGORY_PREFIXES;
  const entries = files.map((f) => {
    const abs = path.join(root, f.rel);
    const content = fs.readFileSync(abs, 'utf8');
    const fm = parseFrontmatter(content);
    const ids = extractDocIds(path.basename(f.rel), categoryPrefixes) ?? { primary: f.fileId };
    return { rel: f.rel, fm, fmId: fm?.id ?? null, fileIds: [ids.primary, f.fileId].filter(Boolean) };
  });
  let matches = entries.filter((e) => e.fmId === slug);
  if (matches.length === 0) matches = entries.filter((e) => e.fileIds.includes(slug));
  if (matches.length === 0) return { found: false, reason: `no scanned doc resolves to id "${slug}"` };
  if (matches.length > 1) {
    return {
      found: false,
      reason: `ambiguous id "${slug}": ${matches.length} scanned docs match — fail-closed`,
    };
  }
  const doc = matches[0];
  return { found: true, rel: doc.rel, status: String(doc.fm?.status ?? '').toLowerCase() };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const result = resolveDocStatus(args.root, args.ref);
  if (!result.found) {
    process.stderr.write(`close-before-push-guard: ${result.reason}\n`);
    process.exit(2);
  }
  if (result.status === 'done') {
    console.log(`close-before-push-guard: OK — ${args.ref} (${result.rel}) is already closed (status: done); push is safe.`);
    process.exit(0);
  }
  process.stderr.write(
    `close-before-push-guard: REFUSED — ${args.ref} (${result.rel}) has status "${result.status || '(none)'}", not "done". ` +
      'Run the close ceremony BEFORE pushing (.aai/SKILL_PR.prompt.md step 4c): ' +
      `node .aai/scripts/close-work-item.mjs --ref ${args.ref} --pr TBD --commit <sha> [--spec <spec-slug>] --review <pass|waived|none>\n`
  );
  process.exit(1);
}

main();
