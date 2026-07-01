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

import fs from 'node:fs';
import path from 'node:path';

const ARGV = process.argv.slice(2);
const REPAIR = ARGV.includes('--repair');
const target = ARGV.find(a => !a.startsWith('--')) ?? 'docs/ai/STATE.yaml';

// A top-level key line: `name:` at column 0 (no leading whitespace). Excludes
// comments (`# ...`), document markers (`---`), and blank lines. Block-scalar and
// nested content is indented, so it never matches at column 0.
const TOP_KEY_RE = /^([A-Za-z_][\w-]*):/;

function topLevelKeyCounts(lines) {
  const counts = new Map();
  for (const raw of lines) {
    if (!raw || raw.startsWith('#') || raw.startsWith('---')) continue;
    const m = raw.match(TOP_KEY_RE);
    if (!m) continue;
    counts.set(m[1], (counts.get(m[1]) ?? 0) + 1);
  }
  return counts;
}

function duplicateKeys(lines) {
  const dups = [];
  for (const [key, n] of topLevelKeyCounts(lines)) {
    if (n > 1) dups.push({ key, count: n });
  }
  return dups;
}

// --- structural metrics-block merge (repair) --------------------------------

// Return the [start, end) line-index ranges of every top-level `metrics:` block.
function metricsBlockRanges(lines) {
  const ranges = [];
  for (let i = 0; i < lines.length; i += 1) {
    if (!/^metrics:\s*$/.test(lines[i])) continue;
    let end = lines.length;
    for (let j = i + 1; j < lines.length; j += 1) {
      const l = lines[j];
      if (l.startsWith('#') || l.startsWith('---')) continue;
      if (TOP_KEY_RE.test(l)) { end = j; break; }
    }
    ranges.push([i, end]);
  }
  return ranges;
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
      cur = { ref: refMatch[1], header: line, other: [], runsHeader: null, runs: [] };
      continue;
    }
    if (!cur) { pre.push(line); continue; }   // stray line before any ref
    if (/^ {6}agent_runs:\s*$/.test(line)) {
      cur.runsHeader = line;
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
        map.set(r.ref, { header: r.header, other: r.other, runsHeader: r.runsHeader, runs: [...r.runs] });
      } else {
        const ex = map.get(r.ref);
        if (r.runs.length) {
          if (!ex.runsHeader) ex.runsHeader = r.runsHeader;
          ex.runs.push(...r.runs);
        }
      }
    }
  }
  const out = [header, ...pre];
  if (workItemsHeader) out.push(workItemsHeader);
  for (const ref of order) {
    const r = map.get(ref);
    out.push(r.header, ...r.other);
    if (r.runsHeader) out.push(r.runsHeader);
    for (const item of r.runs) out.push(...item);
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
  const trailingNewline = original.endsWith('\n');
  let lines = original.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
  // Drop the synthetic trailing empty element from a terminal newline so counts
  // and re-emission are exact.
  if (trailingNewline && lines.length && lines[lines.length - 1] === '') lines.pop();

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
  console.log(`OK: ${target} has exactly one of every top-level key.`);
  process.exit(0);
}

main();
