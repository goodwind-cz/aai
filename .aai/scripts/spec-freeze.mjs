#!/usr/bin/env node
// spec-freeze.mjs — ATOMIC spec freeze (CHANGE-0120 cheap-ticks, AC-003).
//
// Freezing a spec is a TWO-PART state:
//   1. frontmatter `status: implementing`
//   2. the body marker `SPEC-FROZEN: true`
// Writing one half without the other produces a doc the dispatcher cannot
// interpret. In the motivating ride Planning wrote the marker while the
// frontmatter stayed `draft`, and a full re-Planning agent was spawned to fix
// the tool's own paperwork. This script exists so that half-state has no
// producer: both halves are computed in memory and committed in ONE
// write+rename, or NOTHING is written at all. Its twin is spec-lint's
// `half-frozen` rule, which catches the state if it ever arrives by hand.
//
// Usage:
//   node .aai/scripts/spec-freeze.mjs --path <spec> [--json] [--dry-run] [--no-event]
//
// Behavior:
//   - Idempotent. A spec that is ALREADY `implementing` + marked is a no-op
//     success: no write, no event, byte-identical file.
//   - Repairs an existing half-state (either half missing, or a
//     `SPEC-FROZEN: false`/other marker value) by writing both halves.
//   - Records the transition as a `doc_lifecycle` <old> -> implementing event
//     via the sibling append-event.mjs — ONLY when the status actually
//     changed, so a re-freeze never grows the ledger. `--no-event` skips it.
//   - Preserves the file's original line endings (a CRLF checkout stays CRLF).
//
// Exit codes (closed contract):
//   0 frozen, or already frozen (idempotent no-op)
//   2 usage error (missing/unknown flag, missing value)
//   3 REFUSED — the doc cannot be frozen atomically, and NOTHING was written:
//     unreadable path, no frontmatter, no `status:` key in the frontmatter, or
//     a current status outside {draft, proposed, accepted, implementing}
//     (a terminal doc is never re-frozen)
//   1 internal error (unexpected exception; nothing was written) — INCLUDING a
//     failed post-transform assertion: before writing, the RESULT is re-parsed
//     and must satisfy the full frozen contract (frontmatter parses, status is
//     `implementing`, exactly one body `SPEC-FROZEN: true` and none inside the
//     frontmatter). A transform that cannot prove its own output is correct
//     writes nothing.
//
// The refusal codes are the whole point: this tool would rather leave a spec
// untouched than leave it half-frozen.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { normalizeNewlines, parseFrontmatter } from './lib/docs-model.mjs';

const ROOT = process.cwd();
const FROZEN_STATUS = 'implementing';
// Statuses a spec may be frozen FROM. Anything else (done, superseded,
// rejected, deferred, legacy, an unknown token) is refused rather than
// silently reopened.
const FREEZABLE = ['draft', 'proposed', 'accepted', 'implementing'];

function usage() {
  console.error(
    'Usage: spec-freeze --path <spec> [--json] [--dry-run] [--no-event]\n'
    + '  Writes frontmatter `status: implementing` AND the `SPEC-FROZEN: true`\n'
    + '  body marker in ONE atomic write, or writes nothing at all.\n'
    + '  Exit codes:\n'
    + '  0 frozen, or already frozen (idempotent no-op)\n'
    + '  2 usage error\n'
    + '  3 REFUSED - cannot freeze atomically; nothing written (no frontmatter,\n'
    + '    no status key, unreadable path, or a non-freezable current status)\n'
    + '  1 internal error',
  );
}

function fail(msg) {
  console.error(`spec-freeze: ${msg}`);
  usage();
  process.exit(2);
}

function refuse(msg, json) {
  if (json) console.log(JSON.stringify({ ok: false, refused: true, reason: msg }, null, 2));
  else console.error(`spec-freeze: REFUSED — ${msg}`);
  process.exit(3);
}

function parseArgs(argv) {
  const args = { path: null, json: false, dryRun: false, event: true };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--json') args.json = true;
    else if (tok === '--dry-run') args.dryRun = true;
    else if (tok === '--no-event') args.event = false;
    else if (tok === '--path') {
      args.path = argv[++i];
      if (args.path === undefined || args.path.startsWith('--')) fail('--path needs a value');
    } else if (tok === '-h' || tok === '--help') {
      usage();
      process.exit(2);
    } else fail(`unknown flag: ${tok}`);
  }
  if (!args.path) fail('missing --path');
  return args;
}

// freezeContent(norm) -> { content, from } | { refuse: <reason> }
// PURE over the normalized document: the whole transformation happens here, so
// the caller either has a complete new document to write or a refusal. There
// is deliberately no code path that returns a partially-transformed doc.
export function freezeContent(norm) {
  const fmMatch = norm.match(/^---\n([\s\S]*?)\n---/);
  if (!fmMatch) return { refuse: 'the document has no YAML frontmatter block, so `status:` cannot be set — a marker-only write WOULD BE the half-frozen state' };
  const fmBody = fmMatch[1];
  const statusLine = fmBody.match(/^status:[ \t]*(\S*)[ \t]*$/m);
  if (!statusLine) return { refuse: 'the frontmatter has no `status:` key — refusing to write the marker alone' };
  const from = statusLine[1].trim().toLowerCase();
  if (!FREEZABLE.includes(from)) {
    return { refuse: `frontmatter status is "${from || '(empty)'}" — only ${FREEZABLE.join(' | ')} may be frozen (a terminal spec is never re-frozen)` };
  }

  // Half 1 — the frontmatter status, rewritten INSIDE the frontmatter block
  // only (a `status:` line in the body is prose, not the doc's status).
  const fmStart = fmMatch.index + 4; // past the opening "---\n"
  const newFm = fmBody.replace(/^status:[ \t]*\S*[ \t]*$/m, `status: ${FROZEN_STATUS}`);
  let out = norm.slice(0, fmStart) + newFm + norm.slice(fmStart + fmBody.length);

  // Half 2 — the body marker. An existing SPEC-FROZEN line (any value) is
  // normalized in place; otherwise the marker is inserted after the H1 title,
  // which is where SPEC_TEMPLATE and the whole corpus put it.
  const markerRe = /^SPEC-FROZEN:[ \t]*\S+[ \t]*$/m;
  if (markerRe.test(out)) {
    out = out.replace(markerRe, 'SPEC-FROZEN: true');
  } else {
    const h1 = out.match(/^#[ \t]+[^\n]*$/m);
    if (h1) {
      const at = h1.index + h1[0].length;
      out = `${out.slice(0, at)}\n\nSPEC-FROZEN: true${out.slice(at)}`;
    } else {
      // No H1 (SPEC-0100/0101/0102 and every doc-generator spec): place the
      // marker immediately after the frontmatter block so it is still where
      // every reader (dispatch rule 6, spec-lint) looks.
      //
      // The offset MUST be re-derived from `out`. `fmMatch` was matched against
      // `norm`, but the status rewrite above already changed the document's
      // length (draft -> implementing is +7 bytes), so reusing fmMatch's index
      // splices the marker INSIDE the frontmatter and pushes the bytes it
      // overran out behind it — the exact corruption signature
      // `status: implement` + `SPEC-FROZEN: trueing`.
      const outFm = out.match(/^---\n[\s\S]*?\n---/);
      if (!outFm) throw new Error('post-transform: the rewritten frontmatter no longer parses — refusing to write');
      const end = outFm.index + outFm[0].length;
      out = `${out.slice(0, end)}\n\nSPEC-FROZEN: true${out.slice(end)}`;
    }
  }

  // POST-TRANSFORM ASSERTION — the last line of defense, and the reason an
  // offset bug can never again reach the disk. The RESULT is re-parsed from
  // scratch (not trusted from the transform's own bookkeeping) and must satisfy
  // the full frozen contract. A violation is an internal error: throw, so main
  // exits 1 with NOTHING written.
  const bad = assertFrozen(out);
  if (bad) throw new Error(`post-transform assertion failed: ${bad} — refusing to write a corrupted spec`);

  return { content: out, from };
}

// assertFrozen(out) -> null when the transformed document satisfies the frozen
// contract, otherwise a human reason. Re-parses `out` independently:
//   1. it still opens with a parseable YAML frontmatter block
//   2. that frontmatter carries `status: implementing`
//   3. NO SPEC-FROZEN line lives inside the frontmatter block
//   4. the BODY carries EXACTLY ONE SPEC-FROZEN line, and its value is `true`
export function assertFrozen(out) {
  const fm = out.match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return 'the result carries no parseable frontmatter block';
  const st = fm[1].match(/^status:[ \t]*(\S*)[ \t]*$/m);
  const got = st ? st[1].trim().toLowerCase() : null;
  if (got !== FROZEN_STATUS) return `the result's frontmatter status is "${got ?? '(absent)'}" (expected "${FROZEN_STATUS}")`;
  if (/^SPEC-FROZEN:/m.test(fm[1])) return 'the freeze marker landed INSIDE the frontmatter block';
  const body = out.slice(fm.index + fm[0].length);
  const markers = body.match(/^SPEC-FROZEN:[ \t]*\S*[ \t]*$/gm) ?? [];
  if (markers.length !== 1) return `the result's body carries ${markers.length} SPEC-FROZEN line(s) (expected exactly 1)`;
  if (!/^SPEC-FROZEN:[ \t]*true[ \t]*$/.test(markers[0])) return `the body marker reads "${markers[0].trim()}" (expected "SPEC-FROZEN: true")`;
  return null;
}

function main() {
  const args = parseArgs(process.argv);
  const abs = path.isAbsolute(args.path) ? args.path : path.join(ROOT, args.path);
  let raw;
  try {
    raw = fs.readFileSync(abs, 'utf8');
  } catch {
    refuse(`file not found or unreadable: "${args.path}"`, args.json);
    return;
  }
  const crlf = raw.includes('\r\n');
  const norm = normalizeNewlines(raw);
  const res = freezeContent(norm);
  if (res.refuse) refuse(res.refuse, args.json);

  const changed = res.content !== norm;
  const statusChanged = res.from !== FROZEN_STATUS;
  const report = {
    ok: true,
    spec: args.path,
    from: res.from,
    to: FROZEN_STATUS,
    changed,
    dry_run: args.dryRun,
  };

  if (changed && !args.dryRun) {
    // Atomic: a complete new document is staged beside the target and renamed
    // over it, so no reader can ever observe a partially written spec.
    const tmp = `${abs}.spec-freeze.tmp`;
    fs.writeFileSync(tmp, crlf ? res.content.replace(/\n/g, '\r\n') : res.content);
    fs.renameSync(tmp, abs);
    if (args.event && statusChanged) {
      const id = parseFrontmatter(norm)?.id ?? null;
      if (id) {
        const appender = path.join(path.dirname(fileURLToPath(import.meta.url)), 'append-event.mjs');
        try {
          execFileSync(process.execPath, [appender, '--event', 'doc_lifecycle',
            '--ref', String(id), '--from', res.from, '--to', FROZEN_STATUS],
          { cwd: ROOT, stdio: 'ignore' });
          report.event = 'doc_lifecycle';
        } catch {
          // NOTE (degrade-with-NOTE): the freeze itself SUCCEEDED and is on
          // disk; only the audit line failed. Say so rather than reporting a
          // clean freeze or rolling back a correct write.
          console.error('spec-freeze: NOTE — the spec was frozen but the doc_lifecycle audit event could not be appended');
          report.event = null;
        }
      }
    }
  }

  if (args.json) console.log(JSON.stringify(report, null, 2));
  else if (!changed) console.log(`spec-freeze: ${args.path} is already frozen (status: ${FROZEN_STATUS} + SPEC-FROZEN: true) — no write`);
  else if (args.dryRun) console.log(`spec-freeze: DRY RUN — would freeze ${args.path} (status ${res.from} -> ${FROZEN_STATUS} + SPEC-FROZEN: true)`);
  else console.log(`spec-freeze: froze ${args.path} (status ${res.from} -> ${FROZEN_STATUS} + SPEC-FROZEN: true)`);
  process.exit(0);
}

// Run only when executed directly (tests may import freezeContent).
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  try {
    main();
  } catch (err) {
    console.error(`spec-freeze: internal error: ${err && err.stack ? err.stack : err}`);
    process.exit(1);
  }
}
