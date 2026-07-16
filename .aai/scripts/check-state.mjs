#!/usr/bin/env node
// STATE.yaml structural validator (ISSUE-0004 / SPEC-0010 Group B).
//
// Detects DUPLICATE TOP-LEVEL keys in docs/ai/STATE.yaml — most importantly a
// second `metrics:` mapping, which a lenient YAML `safe_load` silently collapses
// (last-key-wins), dropping the first block's work_items and agent_runs. This is
// a PURE TEXT SCAN — no YAML library dependency (the repo ships none, and
// top-level-key duplication is detectable structurally without a full parse).
//
// Usage:
//   node .aai/scripts/check-state.mjs [<path>]            # detect, exit 1 on dup
//   node .aai/scripts/check-state.mjs --repair [<path>]   # merge dup metrics blocks
//
// Default path: docs/ai/STATE.yaml
//
// --repair merges duplicate top-level `metrics:` blocks into ONE, with zero data
// loss: work_items are unioned and, for a ref present in more than one block, its
// agent_runs are concatenated (append, preserving order and count). Any OTHER
// duplicate top-level key is reported but NOT auto-merged (scoped, fail-loud).
//
// ISSUE-0007 adds a whole-file structural LIST-INDENT LINT (see
// listIndentViolations below): a `- ` sibling written shallower than the
// list's first item is invalid YAML this scan previously missed. Detection
// only — never auto-repaired.

import fs from 'node:fs';
import path from 'node:path';
// Shared structural primitives (SPEC-0012 D4): ONE definition of "duplicate
// top-level key" / line normalization / block location, shared with the
// transactional writer .aai/scripts/state.mjs — no logic fork.
import { TOP_KEY_RE, duplicateKeys, inlineChildConflicts, splitLines, topBlockRanges } from './lib/state-core.mjs';

// Report the "child lines under an inline-valued top-level header" corruption
// (e.g. `metrics: {}` followed by indented `work_items:` — a mapping value
// given twice; lenient YAML loads reject it). Detected, never auto-repaired.
function failOnInlineChildConflicts(lines) {
  const conflicts = inlineChildConflicts(lines);
  if (conflicts.length === 0) return;
  console.error(`FAIL: ${conflicts.length} top-level key(s) in ${target} carry an INLINE value with indented child lines beneath (invalid YAML — mapping value given twice):`);
  for (const c of conflicts) {
    console.error(`  - ${c.key} (line ${c.line}) — convert the inline value to block form (bare \`${c.key}:\` header) by hand`);
  }
  process.exit(1);
}

const ARGV = process.argv.slice(2);
const REPAIR = ARGV.includes('--repair');
const target = ARGV.find(a => !a.startsWith('--')) ?? 'docs/ai/STATE.yaml';

// --- structural list-indent lint (ISSUE-0007 / Spec-AC-02) -------------------
//
// The class check-state used to miss: a `- ` list item appended at a SHALLOWER
// indent than its siblings (e.g. 2 spaces past the key under a list whose
// items sit 4 past it) — invalid YAML PyYAML rejects while a top-level-keys
// scan passes. No YAML parser ships with node and the repo takes no deps, so
// this stays a pure text lint: for every block key whose first significant
// child is a `- ` item line, every subsequent direct sibling item of that
// block must share the FIRST item's indent. A `- ` line indented strictly
// between the key and the first item is exactly this corruption. Lines deeper
// than the first item belong to nested keys (agent_runs entries, item maps)
// and are validated by their own key's pass — no false positives by
// construction. Detection only; the write path is fixed in state-engine.mjs.

const indentOf = l => (l.match(/^ */) ?? [''])[0].length;
const isSkipLine = l => l.trim() === '' || l.trim().startsWith('#') || l.startsWith('---');
// A block key line: `key:` with no inline value (optionally a trailing comment).
const BLOCK_KEY_RE = /^( *)([^\s#-][^:]*):\s*(?:#.*)?$/;

function listIndentViolations(lines) {
  const out = [];
  for (let i = 0; i < lines.length; i += 1) {
    const km = lines[i].match(BLOCK_KEY_RE);
    if (!km) continue;
    const keyIndent = km[1].length;
    let j = i + 1;
    while (j < lines.length && isSkipLine(lines[j])) j += 1;
    if (j >= lines.length) continue;
    const first = lines[j].match(/^( *)- /);
    if (!first || first[1].length <= keyIndent) continue;   // not a block sequence
    const itemIndent = first[1].length;
    for (let t = j; t < lines.length; t += 1) {
      const l = lines[t];
      if (isSkipLine(l)) continue;
      const ind = indentOf(l);
      if (ind <= keyIndent) {
        // A `- ` line at EXACTLY the key's indent cannot be a sibling mapping
        // key (keys never start with `- `) and cannot belong to this list
        // (its items sit deeper) — it is an orphaned item, invalid YAML
        // (validation-ISSUE-0007-20260715T233312Z probe d, RED-D shape).
        if (ind === keyIndent && /^-(\s|$)/.test(l.slice(ind))) {
          out.push({
            line: t + 1,
            key: km[2].trim(),
            got: ind,
            want: itemIndent,
          });
          continue;   // an orphan cannot END the mapping — keep scanning
        }
        break;   // block ended
      }
      const m = l.match(/^( *)- /);
      if (m && ind < itemIndent) {
        out.push({
          line: t + 1,
          key: km[2].trim(),
          got: ind,
          want: itemIndent,
        });
      }
    }
  }
  return out;
}

// --- orphaned-item lint (ISSUE-0007 remediation) -----------------------------
//
// The shape validation-ISSUE-0007-20260715T233312Z proved the lint above
// misses: a `- ` item line at indent I directly following (or following the
// span of) a `key: <inline-value>` line at indent I. The inline value IS the
// key's whole value, so the item belongs to nothing — invalid YAML (PyYAML:
// `expected <block end>, but found '-'`). Historically produced by whole-field
// rewrites over 0-relative-indent lists (fieldSpan excluded the equal-indent
// items; fixed in state-engine.mjs — this lint is the safety net for files
// corrupted before the fix or by foreign writers). No false positives by
// construction: within a block mapping every entry at indent I is a `key:`
// line, and a compact mapping's parent-sequence dashes sit at least 2 columns
// LEFT of its keys, so a `- ` at exactly a key's indent is never legal there.
// Deeper lines after the inline value are skipped as the key's own span
// (block-scalar `>-`/`|` continuations, flow-collection folds).

// A key line CARRYING an inline value (not a bare `key:`, not comment-only).
const INLINE_KEY_RE = /^( *)([^\s#-][^:]*): +[^#\s]/;

function orphanItemViolations(lines) {
  const out = [];
  for (let i = 0; i < lines.length; i += 1) {
    const km = lines[i].match(INLINE_KEY_RE);
    if (!km) continue;
    const keyIndent = km[1].length;
    let j = i + 1;
    while (j < lines.length) {
      const c = lines[j];
      if (c.startsWith('---')) { j = lines.length; break; }   // document boundary — stop
      if (c.trim() === '' || c.trim().startsWith('#')) { j += 1; continue; }
      if (indentOf(c) > keyIndent) { j += 1; continue; }      // the key's own span
      break;
    }
    if (j >= lines.length) continue;
    const l = lines[j];
    if (indentOf(l) === keyIndent && /^-(\s|$)/.test(l.slice(keyIndent))) {
      out.push({ line: j + 1, key: km[2].trim(), keyLine: i + 1 });
    }
  }
  return out;
}

function failOnOrphanItemViolations(lines) {
  const bad = orphanItemViolations(lines);
  if (bad.length === 0) return;
  console.error(`FAIL: ${bad.length} ORPHANED list item(s) in ${target} (invalid YAML — a \`- \` item at the same indent as a key that already carries an inline value belongs to nothing):`);
  for (const v of bad) {
    console.error(`  - key "${v.key}" (line ${v.keyLine}) carries an inline value, but line ${v.line} is a \`- \` item at the key's own indent`);
  }
  console.error('This is the ISSUE-0007 remediation class (a whole-field rewrite over a');
  console.error('0-relative-indent list left its items orphaned). Re-attach the flagged');
  console.error('item(s) to the right key (or delete them) by hand.');
  process.exit(1);
}

function failOnListIndentViolations(lines) {
  const bad = listIndentViolations(lines);
  if (bad.length === 0) return;
  console.error(`FAIL: ${bad.length} mis-indented list item(s) in ${target} (invalid YAML — a sibling must share the indent of the list's first item):`);
  for (const v of bad) {
    console.error(`  - key "${v.key}": item at line ${v.line} has indent ${v.got}, the list's first item uses indent ${v.want}`);
  }
  console.error('This is the ISSUE-0007 class (a list append written shallower than its');
  console.error('siblings). Re-indent the flagged item(s) to match the first item by hand.');
  process.exit(1);
}

// --- structural metrics-block merge (repair) --------------------------------

// Return the [start, end) line-index ranges of every top-level `metrics:` block.
function metricsBlockRanges(lines) {
  return topBlockRanges(lines, /^metrics:\s*$/);
}

// Parse one metrics block (its raw lines) into an ordered work_items structure.
// Preserves raw line text verbatim so re-emission loses nothing.
function parseMetricsBlock(blockLines) {
  const header = blockLines[0];           // `metrics:`
  let i = 1;
  const pre = [];                         // lines between `metrics:` and `work_items:`
  while (i < blockLines.length && !/^ {2}work_items:\s*$/.test(blockLines[i])) {
    pre.push(blockLines[i]); i += 1;
  }
  let workItemsHeader = null;
  if (i < blockLines.length) { workItemsHeader = blockLines[i]; i += 1; }

  const refs = [];                        // { ref, header, other:[], runsHeader, runs:[[...]] }
  let cur = null;
  const flush = () => { if (cur) refs.push(cur); cur = null; };

  for (; i < blockLines.length; i += 1) {
    const line = blockLines[i];
    const refMatch = line.match(/^ {4}([\w-]+):\s*$/);
    if (refMatch) {
      flush();
      cur = { ref: refMatch[1], header: line, other: [], hasRuns: false, runs: [] };
      continue;
    }
    if (!cur) { pre.push(line); continue; }   // stray line before any ref
    if (/^ {6}agent_runs:\s*$/.test(line)) {
      cur.hasRuns = true;
      let curItem = null;
      let j = i + 1;
      for (; j < blockLines.length; j += 1) {
        const l2 = blockLines[j];
        if (/^ {4}[\w-]+:\s*$/.test(l2)) break;                       // next ref
        if (/^ {6}[\w-]+:\s*$/.test(l2) && !/^ {8}/.test(l2)) break;  // sibling indent-6 key
        if (/^ {8}- /.test(l2)) { if (curItem) cur.runs.push(curItem); curItem = [l2]; }
        else if (curItem) curItem.push(l2);
        else cur.other.push(l2);
      }
      if (curItem) cur.runs.push(curItem);
      i = j - 1;
      continue;
    }
    // Inline agent_runs (e.g. the auto-init `agent_runs: []` form): mark the
    // field present but do NOT keep it in `other`, so the merge re-emits a
    // SINGLE canonical agent_runs and never produces a duplicate nested key
    // (Codex P2 / ISSUE-0004 self-fix). An inline `[]` contributes no runs.
    if (/^ {6}agent_runs:\s*\S/.test(line)) { cur.hasRuns = true; continue; }
    cur.other.push(line);
  }
  flush();
  return { header, pre, workItemsHeader, refs };
}

// Merge parsed metrics blocks: union work_items (first occurrence wins for
// non-agent_runs fields), concatenate agent_runs in block order.
function mergeMetricsBlocks(parsed) {
  const order = [];
  const map = new Map();
  let workItemsHeader = null;
  const pre = parsed[0].pre;
  const header = parsed[0].header;
  for (const b of parsed) {
    if (!workItemsHeader && b.workItemsHeader) workItemsHeader = b.workItemsHeader;
    for (const r of b.refs) {
      if (!map.has(r.ref)) {
        order.push(r.ref);
        map.set(r.ref, { header: r.header, other: r.other, hasRuns: r.hasRuns, runs: [...r.runs] });
      } else {
        const ex = map.get(r.ref);
        ex.hasRuns = ex.hasRuns || r.hasRuns;
        ex.runs.push(...r.runs);
      }
    }
  }
  const out = [header, ...pre];
  if (workItemsHeader) out.push(workItemsHeader);
  for (const ref of order) {
    const r = map.get(ref);
    out.push(r.header, ...r.other);
    // Emit exactly ONE canonical agent_runs field — block form when there are
    // runs, else the inline empty form when the field was present (never both,
    // so the auto-init `agent_runs: []` + a duplicate block never collide).
    if (r.runs.length) {
      out.push('      agent_runs:');
      for (const item of r.runs) out.push(...item);
    } else if (r.hasRuns) {
      out.push('      agent_runs: []');
    }
  }
  return out;
}

function repairMetrics(lines) {
  const ranges = metricsBlockRanges(lines);
  if (ranges.length <= 1) return { lines, merged: false };
  const parsed = ranges.map(([s, e]) => parseMetricsBlock(lines.slice(s, e)));
  const mergedBlock = mergeMetricsBlocks(parsed);

  // Rebuild the file: put the merged block where the FIRST metrics block was,
  // drop every other metrics block range. Preserve all non-metrics lines verbatim.
  const drop = new Set();
  for (let k = 1; k < ranges.length; k += 1) {
    for (let idx = ranges[k][0]; idx < ranges[k][1]; idx += 1) drop.add(idx);
  }
  const [firstStart, firstEnd] = ranges[0];
  const out = [];
  for (let idx = 0; idx < lines.length; idx += 1) {
    if (idx === firstStart) { out.push(...mergedBlock); continue; }
    if (idx > firstStart && idx < firstEnd) continue;   // consumed by mergedBlock
    if (drop.has(idx)) continue;
    out.push(lines[idx]);
  }
  return { lines: out, merged: true };
}

function main() {
  const abs = path.resolve(process.cwd(), target);
  if (!fs.existsSync(abs)) {
    console.error(`ERROR: STATE file not found: ${target}`);
    process.exit(2);
  }
  const original = fs.readFileSync(abs, 'utf8');
  // splitLines drops the synthetic trailing empty element from a terminal
  // newline so counts and re-emission are exact (shared normalization).
  const split = splitLines(original);
  const trailingNewline = split.trailingNewline;
  let lines = split.lines;

  if (REPAIR) {
    const before = duplicateKeys(lines);
    const metricsDup = before.some(d => d.key === 'metrics');
    if (metricsDup) {
      const { lines: repaired, merged } = repairMetrics(lines);
      if (merged) {
        lines = repaired;
        fs.writeFileSync(abs, lines.join('\n') + (trailingNewline ? '\n' : ''));
        console.log(`REPAIRED: merged ${before.find(d => d.key === 'metrics').count} duplicate top-level \`metrics:\` blocks into one (work_items unioned, agent_runs concatenated, zero data loss).`);
      }
    }
    // Re-validate the (possibly rewritten) file.
    const after = duplicateKeys(lines);
    if (after.length > 0) {
      console.error('FAIL: duplicate top-level key(s) remain after repair:');
      for (const d of after) {
        const note = d.key === 'metrics' ? '' : ' (not auto-merged — only `metrics:` is repaired; resolve by hand)';
        console.error(`  - ${d.key} (x${d.count})${note}`);
      }
      process.exit(1);
    }
    failOnInlineChildConflicts(lines);
    failOnListIndentViolations(lines);
    failOnOrphanItemViolations(lines);
    console.log('OK: STATE.yaml has exactly one of every top-level key.');
    process.exit(0);
  }

  const dups = duplicateKeys(lines);
  if (dups.length > 0) {
    console.error(`FAIL: ${dups.length} duplicate top-level key(s) in ${target}:`);
    for (const d of dups) console.error(`  - ${d.key} (appears ${d.count}x)`);
    console.error('A duplicate top-level `metrics:` key silently shadows the first block on a');
    console.error('lenient YAML load (ISSUE-0004). Run with --repair to merge duplicate');
    console.error('`metrics:` blocks (union work_items, concatenate agent_runs, zero data loss).');
    process.exit(1);
  }
  failOnInlineChildConflicts(lines);
  failOnListIndentViolations(lines);
  failOnOrphanItemViolations(lines);
  console.log(`OK: ${target} has exactly one of every top-level key.`);
  process.exit(0);
}

main();
