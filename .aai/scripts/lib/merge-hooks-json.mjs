// merge-hooks-json.mjs — shared additive-with-provable-update JSON-hooks merge.
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
// THE RULE (owner-directed scope extension, 2026-09-30 — "the merge must be
// able to UPDATE, not only ADD", under the standing priority "a user-modified
// hook is never overwritten"):
//
//   1. A source hook whose exact `command` is already present in the
//      destination's event is SKIPPED (idempotent).
//   2. Otherwise the hook is keyed on the script PATH inside its command
//      (`hookPathKey`). A destination hook in the same event with the same
//      key but a DIFFERENT command is the same registration, edited by
//      someone — the question is by whom.
//   3. That destination hook is UPDATED IN PLACE only when the caller passes
//      a `shipped` snapshot (what THIS engine last merged into THIS target)
//      and the destination's command is byte-equal to the snapshot's command
//      for that key: the entry is then provably unmodified engine output, so
//      rewriting it destroys nothing anyone authored.
//   4. In every other same-key-differing case — no snapshot, the snapshot
//      disagrees with the destination, or more than one candidate on either
//      side — the files alone cannot tell "user edited it" from "an older
//      source shipped it", so the owner's priority wins: the destination
//      entry is LEFT AS-IS, the source's version is NOT added beside it
//      (that would be the one-stale-entry-per-edit accumulation the update
//      exists to stop), and the case is reported as a `LEFT-AS-IS` line for
//      the caller's advisory. Never a silent rewrite.
//   5. A destination hook whose key the source does not ship at all is never
//      touched — that is the property the whole ride exists to deliver.
//   6. A source event carrying two hooks with the same key (e.g. the
//      bootstrap overlay template: one adapter script, three argument sets)
//      cannot be paired by key; those hooks fall back to exact-command
//      matching only (rule 1, else add) — never a guessed update.
//   7. A destination that does not exist yet is created as a byte-for-byte
//      COPY of the source file (nothing to preserve, so nothing to
//      regenerate — Validation NB-4: a re-serialised copy diverged from the
//      source bytes on any reformat).
//
// Refuses loudly (throws, destination left byte-identical) when the
// destination does not parse as a JSON object, or when it carries a
// non-object "hooks" key (Review NB-1: a pre-existing non-object hooks key,
// e.g. `hooks: []`, would otherwise silently drop every merged entry while
// reporting success).
//
// The `shipped` snapshot is written by this function AFTER a successful
// merge, as a verbatim copy of the source bytes, so it always says "the
// source this engine last merged here shipped exactly this". It is never
// written on a refusal. A malformed or absent snapshot is treated as absent
// (rule 4 applies — safe by construction).
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The first path-like token in a command: something with a directory
// separator and a file extension, quotes and `${VAR}` prefixes kept as
// written (the key is "stabler than the exact command string", not a
// resolved filesystem path — two spellings of one file are two keys, which
// errs toward LEFT-AS-IS / add, never toward a wrong update). Backslashes
// normalise to `/` so a Windows spelling pairs with itself across edits.
const PATH_TOKEN_RE = /[^\s"'`;|&()]*[\\/][^\s"'`;|&()]*\.[A-Za-z0-9]+/;

export function hookPathKey(command) {
  if (typeof command !== 'string') return null;
  const m = PATH_TOKEN_RE.exec(command);
  return m ? m[0].replace(/\\/g, '/') : null;
}

function readJsonObjectOrNull(p) {
  try {
    const v = JSON.parse(fs.readFileSync(p, 'utf8'));
    return (typeof v === 'object' && v !== null && !Array.isArray(v)) ? v : null;
  } catch {
    return null;
  }
}

// { key -> [command, ...] } over one event's matcher groups; a hook with no
// path key is not indexed (exact-command only).
function keyIndex(groups) {
  const idx = new Map();
  for (const g of (groups || [])) {
    for (const h of (g.hooks || [])) {
      const k = hookPathKey(h.command);
      if (k === null) continue;
      if (!idx.has(k)) idx.set(k, []);
      idx.get(k).push(h.command);
    }
  }
  return idx;
}

/**
 * Merge tplPath's "hooks" key into dstPath.
 *
 * @param {string} tplPath - source JSON carrying the hooks to merge in.
 * @param {string} dstPath - destination JSON, merged in place (created as a
 *   byte copy of tplPath when absent).
 * @param {{shipped?: string|null}} [opts] - `shipped`: path of the snapshot
 *   of what this engine last merged into dstPath; read before the merge to
 *   prove an entry is unmodified engine output, rewritten after a successful
 *   merge. Omit it (bootstrap does) and rule 3 never fires — every
 *   same-key-differing entry is LEFT-AS-IS.
 * @returns {{added: number, updated: number, skipped: number, left: number,
 *   wrote: boolean, conflicts: Array<{event: string, key: string,
 *   target: string, source: string, reason: string}>}}
 * @throws {Error} when dstPath exists but is not a JSON object, or carries a
 *   non-object "hooks" key. dstPath is left untouched in every throw path.
 */
export function mergeHooksJson(tplPath, dstPath, opts = {}) {
  const shippedPath = opts.shipped || null;
  const tplRaw = fs.readFileSync(tplPath, 'utf8');
  const tpl = JSON.parse(tplRaw);

  let dst = {};
  if (fs.existsSync(dstPath)) {
    try {
      dst = JSON.parse(fs.readFileSync(dstPath, 'utf8'));
    } catch {
      throw new Error(
        `existing ${dstPath} is not valid JSON — refusing to touch it. Merge the "hooks" key from ${tplPath} manually.`
      );
    }
  } else {
    // Rule 7: fresh destination — the source bytes ARE the merged result.
    let added = 0;
    for (const matchers of Object.values(tpl.hooks || {})) {
      for (const m of matchers) added += (m.hooks || []).length;
    }
    fs.mkdirSync(path.dirname(dstPath), { recursive: true });
    fs.writeFileSync(dstPath, tplRaw);
    writeShipped(shippedPath, tplRaw);
    return { added, updated: 0, skipped: 0, left: 0, wrote: true, conflicts: [] };
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

  const shipped = shippedPath && fs.existsSync(shippedPath) ? readJsonObjectOrNull(shippedPath) : null;
  const shippedHooks = (shipped && typeof shipped.hooks === 'object' && shipped.hooks !== null && !Array.isArray(shipped.hooks))
    ? shipped.hooks : {};

  dst.hooks = dst.hooks || {};
  let added = 0;
  let updated = 0;
  let skipped = 0;
  const conflicts = [];
  for (const [event, matchers] of Object.entries(tpl.hooks || {})) {
    dst.hooks[event] = dst.hooks[event] || [];
    const srcKeys = keyIndex(matchers);
    const shippedKeys = keyIndex(shippedHooks[event]);
    for (const m of matchers) {
      for (const h of (m.hooks || [])) {
        // Rule 1 — exact command already registered anywhere in this event.
        const present = dst.hooks[event].some((x) => (x.hooks || []).some((y) => y.command === h.command));
        if (present) {
          skipped++;
          continue;
        }
        const key = hookPathKey(h.command);
        // Rule 6 — unkeyed or ambiguous-in-source: exact-only, else add.
        const pairable = key !== null && (srcKeys.get(key) || []).length === 1;
        if (pairable) {
          // Every destination hook in this event carrying the same key.
          const candidates = [];
          for (const g of dst.hooks[event]) {
            for (let i = 0; i < (g.hooks || []).length; i++) {
              if (hookPathKey(g.hooks[i].command) === key) candidates.push({ group: g, index: i });
            }
          }
          if (candidates.length > 0) {
            const shippedCmds = shippedKeys.get(key) || [];
            const c = candidates[0];
            const targetCmd = c.group.hooks[c.index].command;
            let reason = null;
            if (candidates.length > 1) reason = 'more than one target entry carries this path';
            else if (!shipped) reason = 'no record of what this engine last shipped here';
            else if (shippedCmds.length !== 1) reason = 'the last-shipped record does not name this path exactly once';
            else if (shippedCmds[0] !== targetCmd) reason = 'the target entry differs from what this engine last shipped (edited locally, or shipped by another source)';
            if (reason !== null) {
              // Rule 4 — cannot prove it is unmodified engine output: leave
              // it, do not add beside it, report it.
              conflicts.push({ event, key, target: targetCmd, source: h.command, reason });
              continue;
            }
            // Rule 3 — provably unmodified engine output: update in place,
            // moving it only when the source's matcher changed too.
            if (c.group.matcher === m.matcher) {
              c.group.hooks[c.index] = h;
            } else {
              c.group.hooks.splice(c.index, 1);
              if (c.group.hooks.length === 0) {
                dst.hooks[event].splice(dst.hooks[event].indexOf(c.group), 1);
              }
              let entry = dst.hooks[event].find((x) => x.matcher === m.matcher);
              if (!entry) {
                entry = (m.matcher !== undefined) ? { matcher: m.matcher, hooks: [] } : { hooks: [] };
                dst.hooks[event].push(entry);
              }
              entry.hooks.push(h);
            }
            updated++;
            continue;
          }
        }
        // Add — nothing in the destination claims this hook.
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

  const wrote = added > 0 || updated > 0;
  if (wrote) fs.writeFileSync(dstPath, JSON.stringify(dst, null, 2) + '\n');
  writeShipped(shippedPath, tplRaw);
  return { added, updated, skipped, left: conflicts.length, wrote, conflicts };
}

// Verbatim copy of the source bytes, written only when they changed (a
// steady-state re-sync leaves the snapshot's mtime alone too).
function writeShipped(shippedPath, tplRaw) {
  if (!shippedPath) return;
  try {
    if (fs.existsSync(shippedPath) && fs.readFileSync(shippedPath, 'utf8') === tplRaw) return;
  } catch { /* unreadable: rewrite below */ }
  fs.mkdirSync(path.dirname(shippedPath), { recursive: true });
  fs.writeFileSync(shippedPath, tplRaw);
}

export function formatSummary(res, dstPath) {
  return `${res.added} hook(s) added, ${res.updated} updated, ${res.skipped} already present, ${res.left} left as-is -> ${dstPath}`;
}

// One line per LEFT-AS-IS entry, machine-readable prefix for the callers'
// advisories (aai-sync.sh / .ps1 parse the `LEFT-AS-IS ` prefix).
export function formatConflicts(res) {
  return res.conflicts.map((c) =>
    `LEFT-AS-IS ${c.event} ${c.key}: target has ${JSON.stringify(c.target)}, source now ships ${JSON.stringify(c.source)} — not rewritten and not added beside it (${c.reason}); reconcile the registration manually`);
}

function main() {
  const argv = process.argv.slice(2);
  const positional = [];
  let shipped = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--shipped') {
      shipped = argv[++i] ?? null;
      if (!shipped) {
        console.error('usage: merge-hooks-json.mjs <template-path> <dest-path> [--shipped <snapshot-path>]');
        process.exit(2);
      }
    } else {
      positional.push(argv[i]);
    }
  }
  const [tplPath, dstPath] = positional;
  if (!tplPath || !dstPath) {
    console.error('usage: merge-hooks-json.mjs <template-path> <dest-path> [--shipped <snapshot-path>]');
    process.exit(2);
  }
  try {
    const res = mergeHooksJson(tplPath, dstPath, { shipped });
    console.log(formatSummary(res, dstPath));
    for (const line of formatConflicts(res)) console.log(line);
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
