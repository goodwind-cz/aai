// merge-hooks-json.mjs — shared additive JSON-hooks merge.
//
// Extracted from aai-bootstrap.sh's --with-claude-hooks `install_claude_hooks`
// (RFC-0010 / spec-hook-enforced-gates), which merges a template's "hooks"
// key into a target's `.claude/settings.json` without ever removing an
// existing entry. Owner amendment to spec-sync-deletes-target-only-hooks
// (2026-09-30): the SAME shape and the SAME safety property are what
// `aai-sync.(sh|ps1)` needs for `hooks/hooks.json` / `hooks/hooks.windows.json`
// — a target-added registration must survive a sync, not be overwritten by
// the source's copy. One algorithm, two callers; this file is the single
// source so neither caller re-types a second dialect of the same merge.
//
// Purely additive: an existing destination entry is NEVER removed or
// rewritten — only a source hook whose exact `command` string is not already
// present anywhere in the destination's matching event is appended. Refuses
// loudly (throws, destination left byte-identical) when the destination does
// not parse as a JSON object, or when it carries a non-object "hooks" key
// (Review NB-1: a pre-existing non-object hooks key, e.g. `hooks: []`, would
// otherwise silently drop every merged entry while reporting success).
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

/**
 * Additively merge tplPath's "hooks" key into dstPath (created as `{}` if
 * absent). Writes dstPath only when at least one hook was newly added — a
 * no-op run leaves the file byte-identical (idempotent).
 *
 * @param {string} tplPath - source JSON carrying the hooks to merge in.
 * @param {string} dstPath - destination JSON, merged in place.
 * @returns {{added: number, skipped: number, wrote: boolean}}
 * @throws {Error} when dstPath exists but is not a JSON object, or carries a
 *   non-object "hooks" key. dstPath is left untouched in every throw path.
 */
export function mergeHooksJson(tplPath, dstPath) {
  const tpl = JSON.parse(fs.readFileSync(tplPath, 'utf8'));

  let dst = {};
  if (fs.existsSync(dstPath)) {
    try {
      dst = JSON.parse(fs.readFileSync(dstPath, 'utf8'));
    } catch {
      throw new Error(
        `existing ${dstPath} is not valid JSON — refusing to touch it. Merge the "hooks" key from ${tplPath} manually.`
      );
    }
  }
  if (typeof dst !== 'object' || dst === null || Array.isArray(dst)) {
    throw new Error(
      `existing ${dstPath} is not a JSON object — refusing to touch it. Merge manually from ${tplPath}.`
    );
  }
  // Review NB-1: a pre-existing non-object "hooks" key (e.g. hooks: []) would
  // make the merge silently drop entries while reporting success — refuse loud.
  if ('hooks' in dst && (typeof dst.hooks !== 'object' || dst.hooks === null || Array.isArray(dst.hooks))) {
    throw new Error(
      `existing ${dstPath} has a non-object "hooks" key — refusing to touch it. Fix it or merge manually from ${tplPath}.`
    );
  }

  dst.hooks = dst.hooks || {};
  let added = 0;
  let skipped = 0;
  for (const [event, matchers] of Object.entries(tpl.hooks || {})) {
    dst.hooks[event] = dst.hooks[event] || [];
    for (const m of matchers) {
      for (const h of (m.hooks || [])) {
        const present = dst.hooks[event].some((x) => (x.hooks || []).some((y) => y.command === h.command));
        if (present) {
          skipped++;
          continue;
        }
        let entry = dst.hooks[event].find((x) => x.matcher === m.matcher);
        if (!entry) {
          entry = (m.matcher !== undefined) ? { matcher: m.matcher, hooks: [] } : { hooks: [] };
          dst.hooks[event].push(entry);
        }
        entry.hooks.push(h);
        added++;
      }
    }
  }

  const wrote = added > 0;
  if (wrote) fs.writeFileSync(dstPath, JSON.stringify(dst, null, 2) + '\n');
  return { added, skipped, wrote };
}

function main() {
  const [tplPath, dstPath] = process.argv.slice(2);
  if (!tplPath || !dstPath) {
    console.error('usage: merge-hooks-json.mjs <template-path> <dest-path>');
    process.exit(2);
  }
  try {
    const { added, skipped } = mergeHooksJson(tplPath, dstPath);
    console.log(`${added} hook(s) added, ${skipped} already present -> ${dstPath}`);
    process.exit(0);
  } catch (err) {
    console.error(err.message || String(err));
    process.exit(1);
  }
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return p; }
}
const isMain = process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url));
if (isMain) main();
