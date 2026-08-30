#!/usr/bin/env node
// follow-ups.mjs — typed, queryable follow-up registry over the EXISTING
// decision ledger (CHANGE-0142 / SPEC-0129-spec-followup-registry.md).
//
// PURPOSE
//   Deferred work used to live as free prose inside the `decision` field of
//   `review_nb_disposition` entries: 14 clauses, 1 typed entry, and nothing
//   in .aai/scripts able to list any of them. A lesson recorded that way was
//   repeated verbatim as a defect one ride later. This script closes that
//   loop with a typed entry shape on the ledger that already exists, a
//   deterministic fold, and a self-verifying close — no new store, no new
//   agent, no new mandatory prompt reading.
//
// ENTRY SHAPES (D1) — both appended to docs/ai/decisions.jsonl, both reusing
// the ledger's existing key vocabulary so no consumer sees an alien shape:
//
//   {"v":1,"ts":"<ISO8601Z>","actor":"<slug>","type":"follow_up",
//    "id":"fu-<slug>","ref_id":"<ref that RAISED it>","severity":"P1|P2|P3",
//    "finding":"<what, one line>","decision":"<why deferred, one line>",
//    "source":"<evidence path / review report / thread url>",
//    "origin":"backfill",        // OPTIONAL, backfill entries only
//    "source_ts":"<ISO8601Z>"}   // OPTIONAL, backfill entries only
//
//   {"v":1,"ts":"<ISO8601Z>","actor":"<slug>","type":"follow_up_status",
//    "id":"fu-<slug>","status":"done|dropped",
//    "resolved_by":"<ref that resolved it, or the reason for dropped>",
//    "source":"<commit sha / PR url / evidence path>"}
//
//   `status` lives ONLY on follow_up_status. A follow_up is `open` BY
//   CONSTRUCTION — an append-only ledger cannot carry mutable state on the
//   original line, and a `"status":"open"` field on it would invite exactly
//   the retro-edit this design forbids.
//
// ID FORM (D1) — ^fu-[a-z0-9]+(-[a-z0-9]+)*$, max 40 chars. Slug, not a dense
//   sequential number: dense numbering forces renumbering when two branches
//   allocate concurrently, and a renumbered id silently invalidates every
//   prose citation already written against it (github/spec-kit#4065 — the
//   exact failure this registry exists to prevent). Uniqueness is enforced at
//   WRITE time (duplicate --id on `add` is exit 2) and TOLERATED at READ time
//   (first occurrence wins, duplicate named in a NOTE) so a hand-written line
//   can never crash a reader.
//
// WHY A SUBCOMMAND AND NOT A HAND-WRITTEN LINE (D2) — routine-emit.mjs
//   checkAuthorization reads this ledger FAIL-CLOSED over its WHOLE contents:
//   ONE malformed non-comment line silently revokes merge authorization for
//   every scheduled routine, with no error anywhere near the cause. Here the
//   JSON is machine-serialized, so that failure class is structurally
//   unreachable from the sanctioned path (and it is fewer emitted tokens than
//   hand-authoring the object).
//
// APPEND DISCIPLINE — one `fs.appendFileSync` of one serialized line, the
//   house JSONL pattern (append-event.mjs, metrics-flush.mjs, aai-friction.mjs).
//   A single-line O_APPEND write is the atomic primitive here; the whole-file
//   tmp+rename ceremony learned-append.mjs needs is a read-modify-write of the
//   entire ledger and would LOSE a concurrent append instead of preventing one.
//   We never rewrite, so there is nothing for it to protect.
//
// READER ASYMMETRY (deliberate, and tested) — this reader is a REPORTER: a
//   malformed non-comment line is counted, NAMED and skipped. routine-emit's
//   authorization reader is a GATE: the same line poisons the whole ledger.
//   Both are correct for their job; the difference is pinned by a test.
//
// GRAMMAR
//   node .aai/scripts/follow-ups.mjs [list] [--ledger <path>] [--ref <ref>]
//        [--status open|done|dropped|all] [--age-days <n>] [--json]
//   node .aai/scripts/follow-ups.mjs add --id fu-<slug> --ref <ref>
//        --severity P1|P2|P3 --what "<one line>" --why "<one line>"
//        --source "<evidence>" [--ledger <path>] [--actor <slug>]
//        [--origin backfill] [--source-ts <ISO8601Z>]
//   node .aai/scripts/follow-ups.mjs close --id <id> --resolved-by <ref>
//        [--source <sha|url|path>] [--status done|dropped] [--ledger <path>]
//        [--actor <slug>]
//   node .aai/scripts/follow-ups.mjs --help
//
// CLOSING IS A DOCUMENTED MANUAL STEP (D5) — close-work-item.mjs is
//   deliberately NOT wired to this ledger. Its transaction snapshots the
//   EVENTS ledger's byte LENGTH and rolls back by TRUNCATING to it; extending
//   that arm to a second append-only ledger risks deleting decision history
//   to save one typed command. Instead `close` PROVES the flip: it appends,
//   then RE-READS the ledger from disk, re-folds it, and exits 0 only when the
//   re-read shows the new status.
//
// EXIT CONTRACT (D6)
//   0  success — INCLUDING a non-empty backlog (never an error), an empty
//      backlog, a skipped malformed line, and an idempotent re-close.
//   1  write path ONLY — the post-append re-read did not show the expected
//      state (e.g. a future-dated status record for the same id shadows it).
//      The READ/LIST path can never return 1.
//   2  usage error — unknown flag/subcommand, missing required flag, bad --id
//      shape, duplicate id on add, unknown id on close, unreadable ledger.
//
// EXIT MUST NOT TRUNCATE THE OUTPUT (cli-output-survives-a-pipe) — every exit
//   path here used to be `console.log(...); process.exit(code)`. To a FILE
//   stdout is synchronous, so that completes; to a PIPE it is asynchronous,
//   `process.exit` runs before the queued remainder is handed to the kernel,
//   and the reader gets exactly the 64 KB the pipe buffer took. Measured on
//   the live ledger: `list --json` was 87012 bytes to a file and 65536 through
//   a pipe, with `JSON.parse` failing at position 65522. The fix is structural,
//   not per-call-site: `exit(code)` THROWS an ExitSignal that `runMain` turns
//   into `process.exitCode`, so the process ends the ordinary way — after the
//   event loop has drained stdout — and the exit code is unchanged. Nothing
//   here opens a timer, a socket or a stdin read, so there is no handle to
//   keep the process alive past that drain.
//
// Node stdlib only, zero network, no LLM (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const DEFAULT_LEDGER = 'docs/ai/decisions.jsonl';
const FOLLOW_UP_ID_RE = /^fu-[a-z0-9]+(-[a-z0-9]+)*$/;
const ID_MAX_LEN = 40;
const SEVERITIES = ['P1', 'P2', 'P3'];
const TERMINAL_STATUSES = ['done', 'dropped'];
const DAY_MS = 86400000;

// --- reading ------------------------------------------------------------------

// readDecisionsLedger(absPath) -> { records, malformed, missing, unreadable }
// Skips blank and `#` comment lines (the real ledger opens with a 15-line `#`
// header). A malformed non-comment line is COUNTED, never fatal — the caller
// names it in a NOTE. The catch is split by err.code (D2): ENOENT is an
// ABSENT ledger (missing:true, today's behaviour, byte-for-byte); anything
// else (EISDIR, EACCES, EIO, ...) is UNREADABLE (missing:false, unreadable
// set) and must never be folded into "absent" — a directory answering "the
// registry is empty" is the exact defect this split exists to remove.
function readDecisionsLedger(absPath) {
  const records = [];
  let malformed = 0;
  let raw;
  try {
    raw = fs.readFileSync(absPath, 'utf8');
  } catch (err) {
    if (err && err.code === 'ENOENT') return { records, malformed, missing: true, unreadable: null };
    return { records, malformed, missing: false, unreadable: { code: err && err.code, message: err && err.message } };
  }
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (t === '' || t.startsWith('#')) continue;
    try {
      records.push(JSON.parse(t));
    } catch {
      malformed += 1;
    }
  }
  return { records, malformed, missing: false, unreadable: null };
}

function slugify(value) {
  const s = String(value ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return s === '' ? 'unknown' : s;
}

// deriveLegacyId(rec) — D1b: the one pre-existing id-less `follow_up` is NOT
// rewritten and NOT re-emitted as a duplicate. Its id is DERIVED from ref_id +
// ts as fu-<ref-slug>-<yyyymmddThhmm> and the derivation is named in a NOTE.
function deriveLegacyId(rec) {
  const ts = typeof rec.ts === 'string' ? rec.ts : '';
  const m = ts.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
  const stamp = m ? `${m[1]}${m[2]}${m[3]}T${m[4]}${m[5]}` : 'unknown';
  return `fu-${slugify(rec.ref_id)}-${stamp}`;
}

function ageDays(isoTs, nowMs) {
  if (typeof isoTs !== 'string') return null;
  const t = Date.parse(isoTs);
  if (Number.isNaN(t)) return null;
  if (t > nowMs) return null;               // never a negative age
  return Math.floor((nowMs - t) / DAY_MS);
}

// foldFollowUps(records, opts) -> { items, notes, counts }
// D1c: the registry state is a PROJECTION, never a stored view. For each id,
// the FIRST `follow_up` is the item; every `follow_up_status` for that id is
// applied in `ts` order, latest wins. A status whose id has no `follow_up` is
// DANGLING: counted, named, never listed, never fatal.
function foldFollowUps(records, opts = {}) {
  const nowMs = typeof opts.nowMs === 'number' ? opts.nowMs : Date.now();
  const notes = [];
  const byId = new Map();
  const statuses = new Map();
  let duplicates = 0;
  let derived = 0;
  let unparseableTs = 0;
  let malformedIds = 0;

  for (const rec of records) {
    if (!rec || typeof rec !== 'object') continue;
    if (rec.type === 'follow_up') {
      let id = typeof rec.id === 'string' && rec.id.trim() !== '' ? rec.id.trim() : null;
      let isDerived = false;
      if (id === null) { id = deriveLegacyId(rec); isDerived = true; derived += 1; }
      if (byId.has(id)) { duplicates += 1; continue; }   // first occurrence wins
      byId.set(id, { rec, derived: isDerived });
    } else if (rec.type === 'follow_up_status') {
      const id = typeof rec.id === 'string' ? rec.id.trim() : '';
      if (id === '') continue;
      if (!statuses.has(id)) statuses.set(id, []);
      statuses.get(id).push(rec);
    }
  }

  const items = [];
  for (const [id, { rec, derived: isDerived }] of byId) {
    // Codepoint ordering, NOT localeCompare (review NB-2): the item sort
    // below compares with < / >, so a locale-sensitive comparator here could
    // pick a different "latest" than the rest of the fold under another
    // LANG/ICU build — determinism must not depend on the machine's locale.
    const history = (statuses.get(id) ?? [])
      .slice()
      .sort((a, b) => {
        const at = String(a.ts ?? ''); const bt = String(b.ts ?? '');
        return at < bt ? -1 : (at > bt ? 1 : 0);
      });
    const latest = history.length ? history[history.length - 1] : null;
    // A status record carrying NO usable status key must never silently
    // re-open a closed item (review NB-1): that was the one hand-written
    // malformation that changed the answer without naming itself. Such a
    // record is ignored for the verdict and named below.
    const latestUsable = history.filter(
      (h) => typeof h.status === 'string' && h.status.trim() !== '',
    ).pop() ?? null;
    const statuslessCount = history.length - history.filter(
      (h) => typeof h.status === 'string' && h.status.trim() !== '',
    ).length;
    const status = latestUsable ? latestUsable.status.trim() : 'open';
    // A status value outside the closed vocabulary must never SILENTLY hide an
    // item — it stays in the backlog and is named (degrade-with-NOTE).
    if (latest && !TERMINAL_STATUSES.includes(status) && status !== 'open') {
      notes.push(`NOTE follow-up ${id} carries a non-terminal status value "${status}" — left in the backlog`);
    }
    if (statuslessCount > 0) {
      notes.push(`NOTE follow-up ${id} has ${statuslessCount} follow_up_status record(s) with no status key — ignored for the verdict, never silently re-opening the item`);
    }
    const effectiveTs = typeof rec.source_ts === 'string' ? rec.source_ts : rec.ts;
    const age = ageDays(effectiveTs, nowMs);
    if (age === null) unparseableTs += 1;
    // D3/D3a: a hand-written id that does not match the grammar is NAMED, not
    // excluded — excluding it would recreate D2's own silent-undercount defect
    // one layer down. A DERIVED id (D1b) is never checked: deriveLegacyId's
    // yyyymmddThhmm stamp contains an uppercase T, so it never matches
    // FOLLOW_UP_ID_RE by construction and is already named by its own note.
    const idMalformed = !isDerived && (!FOLLOW_UP_ID_RE.test(id) || id.length > ID_MAX_LEN);
    if (idMalformed) malformedIds += 1;
    items.push({
      id,
      ref_id: typeof rec.ref_id === 'string' ? rec.ref_id : null,
      severity: typeof rec.severity === 'string' ? rec.severity : null,
      status,
      closed: TERMINAL_STATUSES.includes(status),
      finding: typeof rec.finding === 'string' ? rec.finding : '',
      decision: typeof rec.decision === 'string' ? rec.decision : '',
      source: typeof rec.source === 'string' ? rec.source : null,
      ts: typeof rec.ts === 'string' ? rec.ts : null,
      source_ts: typeof rec.source_ts === 'string' ? rec.source_ts : null,
      origin: typeof rec.origin === 'string' ? rec.origin : null,
      age_days: age,
      derived_id: isDerived,
      id_malformed: idMalformed,
      resolved_by: latest && typeof latest.resolved_by === 'string' ? latest.resolved_by : null,
      resolved_ts: latest && typeof latest.ts === 'string' ? latest.ts : null,
    });
  }

  let dangling = 0;
  for (const id of statuses.keys()) if (!byId.has(id)) dangling += 1;

  // Oldest-first, id-tiebroken so the order is total and byte-stable.
  items.sort((a, b) => {
    const at = a.source_ts ?? a.ts ?? '';
    const bt = b.source_ts ?? b.ts ?? '';
    if (at !== bt) return at < bt ? -1 : 1;
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
  });

  if (derived) notes.push(`NOTE ${derived} id-less follow_up entr${derived === 1 ? 'y' : 'ies'} folded under a derived id (fu-<ref_id-slug>-<yyyymmddThhmm>) — the original line is never rewritten`);
  if (duplicates) notes.push(`NOTE ${duplicates} duplicate follow_up id(s) in the ledger — the FIRST occurrence wins, the later line(s) ignored`);
  if (dangling) notes.push(`NOTE ${dangling} dangling follow_up_status record(s) (an id with no follow_up) — counted, never listed as an item`);
  if (unparseableTs) notes.push(`NOTE ${unparseableTs} follow-up(s) carry an unparseable or future timestamp — age shown as n/a, never 0`);
  if (malformedIds) notes.push(`NOTE ${malformedIds} follow-up(s) carry an id that does not match the id grammar (marked MALFORMED-ID) — still counted in the open/closed/total counts above, never excluded`);

  // D3: the open count is deliberately NOT filtered by id_malformed — a
  // mistyped id must never make a real deferred item vanish from the number
  // this registry publishes.
  const open = items.filter((i) => !i.closed).length;
  return {
    items,
    notes,
    counts: { open, closed: items.length - open, total: items.length, dangling, duplicates, derived, malformed_ids: malformedIds },
  };
}

// loadRegistry(absPath) -> the fold PLUS the reader's own degradation notes.
// One entry point so the CLI and generate-factory-report.mjs cannot drift.
function loadRegistry(absPath, opts = {}) {
  const { records, malformed, missing, unreadable } = readDecisionsLedger(absPath);
  const folded = foldFollowUps(records, opts);
  const notes = [];
  if (missing) notes.push(`NOTE decision ledger absent at ${absPath} — follow-up registry reported as empty`);
  // D2: an unreadable ledger (a directory, EACCES, EIO, ...) is NEVER folded
  // into the absent note above — that would be exactly today's defect one
  // string over. This note is textually discriminable from it: it never
  // contains "absent" and never contains "reported as empty".
  if (unreadable) notes.push(`NOTE decision ledger at ${absPath} could not be read (${unreadable.code}: ${unreadable.message}) — refused, never treated as an empty registry`);
  // D4: the exclusion note keeps its existing prefix verbatim (test_029 pins
  // it) and gains the understatement clause — an excluded line may have
  // carried a follow_up, so every count above may be UNDERSTATED, not just
  // short by the excluded line count.
  if (malformed) notes.push(`EXCLUDED ${malformed} malformed decision ledger line(s) (unparseable JSON, skipped — comment lines are not counted) — the counts above may therefore be UNDERSTATED`);
  return { ...folded, notes: notes.concat(folded.notes), malformed, missing, unreadable };
}

// --- writing ------------------------------------------------------------------

function nowIso() {
  return `${new Date().toISOString().slice(0, 19)}Z`;
}

// One appendFileSync of one serialized line (D2). A ledger whose last line
// lacks its terminating newline would otherwise get a GLUED record.
function appendLine(absPath, entry) {
  let prefix = '';
  try {
    const size = fs.statSync(absPath).size;
    if (size > 0) {
      const fd = fs.openSync(absPath, 'r');
      try {
        const buf = Buffer.alloc(1);
        fs.readSync(fd, buf, 0, 1, size - 1);
        if (buf[0] !== 0x0a) prefix = '\n';
      } finally {
        fs.closeSync(fd);
      }
    }
  } catch { /* absent file: appendFileSync creates it */ }
  fs.appendFileSync(absPath, `${prefix}${JSON.stringify(entry)}\n`);
}

// --- exit discipline ----------------------------------------------------------
//
// exit()/runMain() now come from ./lib/cli-pipe-guard.mjs (originally
// hand-rolled here; sync-harness-skills.mjs independently hand-rolled the
// same fix, so cli-exit-truncates-pipe-sweep extracted both into one shared
// module). Behavior unchanged: `exit(code)` throws instead of calling
// `process.exit` directly, so `runMain` can record `process.exitCode` and let
// Node drain stdout/stderr before the process actually ends. No `catch`
// block in this file wraps a call to `exit()`, so it always reaches
// `runMain`'s default (re-throw any non-exit error).

// --- CLI ----------------------------------------------------------------------

const USAGE = `Usage:
  node .aai/scripts/follow-ups.mjs [list] [--ledger <path>] [--ref <ref>]
       [--status open|done|dropped|all] [--age-days <n>] [--json]
  node .aai/scripts/follow-ups.mjs add --id fu-<slug> --ref <ref>
       --severity P1|P2|P3 --what "<one line>" --why "<one line>"
       --source "<evidence>" [--ledger <path>] [--actor <slug>]
       [--origin backfill] [--source-ts <ISO8601Z>]
  node .aai/scripts/follow-ups.mjs close --id <id> --resolved-by <ref>
       [--source <sha|url|path>] [--status done|dropped] [--ledger <path>]
       [--actor <slug>] [--origin backfill] [--source-ts <ISO8601Z>]
  node .aai/scripts/follow-ups.mjs --help

Ids match ^fu-[a-z0-9]+(-[a-z0-9]+)*$ (max ${ID_MAX_LEN} chars) and are never
renumbered or reused. Resolution is a SEPARATE appended follow_up_status line;
the original follow_up line is never edited.

A flag value may begin with two dashes (e.g. --what "--decisions is
undocumented") as long as it is not EXACTLY a flag token this subcommand
knows. When it is (for example the literal value --why), bare argv cannot
tell a value from the next flag — write it as --flag=value instead
(e.g. --what=--why), which takes everything after the FIRST = verbatim.

Closing is a documented MANUAL step — close-work-item.mjs is deliberately not
wired to this ledger (its rollback arm truncates, and a bug there would delete
decision history). Run it yourself when a follow-up ships:

  node .aai/scripts/follow-ups.mjs close --id fu-x --resolved-by CHANGE-0143 --source <sha>

It appends the status line, RE-READS the ledger from disk, re-folds it, and
exits 0 only when the re-read confirms the flip.

Exit codes: 0 success (a non-empty backlog is NEVER an error) | 1 the
post-append re-read did not confirm the write | 2 usage error.`;

function usageError(msg) {
  process.stderr.write(`follow-ups: ${msg}\n`);
  process.stderr.write('Run `node .aai/scripts/follow-ups.mjs --help` for the grammar.\n');
  exit(2);
}

const FLAG_SPECS = {
  list: ['--ledger', '--ref', '--status', '--age-days'],
  add: ['--ledger', '--id', '--ref', '--severity', '--what', '--why', '--source', '--actor', '--origin', '--source-ts'],
  close: ['--ledger', '--id', '--resolved-by', '--source', '--status', '--actor', '--origin', '--source-ts'],
};

// D1 — a value is a value unless it is EXACTLY a token this subcommand knows.
// The old rule (`val.startsWith('--')`) rejected ANY dashed value, so a
// finding could never quote a flag name, and the old `-h`/`--help` PRE-SCAN
// (`rest.includes(...)`) swallowed a value that happened to equal --help
// into a silent help-and-exit-0 — the same defect class, folded in here.
function parseArgs(argv) {
  const rest = argv.slice(2);
  let sub = 'list';
  if (rest.length > 0 && !rest[0].startsWith('-')) {
    sub = rest.shift();
  }
  if (sub === 'help') {
    console.log(USAGE);
    exit(0);
  }
  if (!Object.prototype.hasOwnProperty.call(FLAG_SPECS, sub)) {
    usageError(`unknown subcommand "${sub}" (expected list, add or close)`);
  }
  const valueFlags = FLAG_SPECS[sub];
  // Lookahead-ambiguous tokens (D1 rule 2): a value-taking flag's NEXT token
  // is the value UNLESS it is EXACTLY one of these — never a prefix test.
  // -h/--help/--json are always in this set regardless of subcommand. The
  // set is built from EVERY subcommand's flags, not just this one's (review
  // NB-1): a per-subcommand set let a MISTYPED or foreign-subcommand flag in
  // value position (e.g. `add ... --what --sorce`, `list --ref --resolved-by`)
  // be silently swallowed as the value — reintroducing D2's own "a bad input
  // reads as success" shape one function over from where it was removed.
  const knownTokens = new Set([...Object.values(FLAG_SPECS).flat(), '--json', '--help', '-h']);
  const opts = { json: false };
  for (let i = 0; i < rest.length; i += 1) {
    const tok = rest[i];
    // Fires ONLY in flag position: a value already consumed via `i += 1`
    // below is never re-examined by this check (D1 rule 3).
    if (tok === '-h' || tok === '--help') {
      console.log(USAGE);
      exit(0);
    }
    if (tok === '--json') {
      if (sub !== 'list') usageError(`--json is only valid on \`list\``);
      opts.json = true;
      continue;
    }
    // D1 rule 1 — the `--flag=value` escape hatch: split on the FIRST `=`,
    // the remainder is the value verbatim, whatever it starts with. Only a
    // token that itself STARTS WITH `--` is considered for this split, so a
    // bare value containing `=` (`--what "a=b"`) is unaffected.
    if (tok.startsWith('--') && tok.includes('=')) {
      const eq = tok.indexOf('=');
      const flag = tok.slice(0, eq);
      const val = tok.slice(eq + 1);
      if (!valueFlags.includes(flag)) usageError(`unknown flag "${flag}" for \`${sub}\``);
      opts[flag.replace(/^--/, '').replace(/-/g, '_')] = val;
      continue;
    }
    if (!valueFlags.includes(tok)) usageError(`unknown flag "${tok}" for \`${sub}\``);
    const val = rest[i + 1];
    if (val === undefined || knownTokens.has(val)) usageError(`flag "${tok}" requires a value`);
    opts[tok.replace(/^--/, '').replace(/-/g, '_')] = val;
    i += 1;
  }
  opts._sub = sub;
  return opts;
}

function ledgerPath(opts) {
  return path.resolve(process.cwd(), opts.ledger ?? DEFAULT_LEDGER);
}

function requireReadableLedger(abs) {
  if (!fs.existsSync(abs)) usageError(`ledger not found: ${abs}`);
  // D2 — a directory passes existsSync AND accessSync(R_OK) (directories are
  // "readable" for permission purposes), then throws EISDIR on the actual
  // read and used to land in the absent branch: "the registry is empty" for
  // a mistyped path. Refuse it here, before any read is attempted.
  // statSync follows symlinks, so a symlink to a real ledger still passes.
  let st;
  try {
    st = fs.statSync(abs);
  } catch (err) {
    usageError(`ledger not readable: ${abs} (${err && err.code})`);
    return;
  }
  if (!st.isFile()) usageError(`ledger is not a regular file: ${abs}`);
  try {
    fs.accessSync(abs, fs.constants.R_OK);
  } catch {
    usageError(`ledger not readable: ${abs}`);
  }
}

function formatRow(item) {
  const age = item.age_days === null ? 'age=n/a' : `age=${item.age_days}d`;
  // D3: the MALFORMED-ID token is inserted AFTER the id, never touching the
  // leading status word row-detection (SEAM-6, test_002) depends on. A
  // malformed id is rendered through JSON.stringify (review NB-4): an id
  // containing a newline (or other row-breaking whitespace) would otherwise
  // push MALFORMED-ID onto a fabricated continuation line while the item's
  // own row still looked well-formed — the one input shape where D3's "named
  // ON THE ROW" promise was not kept.
  const idDisplay = item.id_malformed ? JSON.stringify(item.id) : item.id;
  const parts = [item.status, idDisplay];
  if (item.id_malformed) parts.push('MALFORMED-ID');
  parts.push(item.severity ?? 'P?', item.ref_id ?? '-', age, item.finding);
  return parts.join('  ');
}

function cmdList(opts) {
  const abs = ledgerPath(opts);
  requireReadableLedger(abs);
  const reg = loadRegistry(abs);
  if (reg.unreadable) usageError(`ledger not readable: ${abs} (${reg.unreadable.code}: ${reg.unreadable.message})`);

  const wantStatus = opts.status ?? 'open';
  if (!['open', 'done', 'dropped', 'all'].includes(wantStatus)) {
    usageError(`--status must be one of open, done, dropped, all (got "${wantStatus}")`);
  }
  let minAge = null;
  if (opts.age_days !== undefined) {
    minAge = Number(opts.age_days);
    if (!Number.isInteger(minAge) || minAge < 0) usageError(`--age-days must be a non-negative integer (got "${opts.age_days}")`);
  }

  const notes = reg.notes.slice();
  let shown = reg.items;
  if (wantStatus !== 'all') shown = shown.filter((i) => i.status === wantStatus);
  if (opts.ref !== undefined) shown = shown.filter((i) => i.ref_id === opts.ref);
  if (minAge !== null) {
    const undated = shown.filter((i) => i.age_days === null).length;
    if (undated) notes.push(`NOTE ${undated} follow-up(s) excluded from the --age-days view (no usable timestamp)`);
    shown = shown.filter((i) => i.age_days !== null && i.age_days >= minAge);
  }

  const counts = { shown: shown.length, ...reg.counts };
  if (opts.json) {
    console.log(JSON.stringify({ ledger: abs, counts, items: shown, notes }, null, 2));
    exit(0);
  }
  console.log(`follow-ups: shown=${counts.shown} open=${counts.open} closed=${counts.closed} total=${counts.total} ledger=${abs}`);
  for (const item of shown) console.log(formatRow(item));
  if (shown.length === 0) console.log('(no follow-ups match this view)');
  for (const n of notes) console.log(n);
  exit(0);
}

function cmdAdd(opts) {
  const abs = ledgerPath(opts);
  for (const [flag, key] of [['--id', 'id'], ['--ref', 'ref'], ['--severity', 'severity'], ['--what', 'what'], ['--why', 'why'], ['--source', 'source']]) {
    if (opts[key] === undefined || String(opts[key]).trim() === '') usageError(`\`add\` requires ${flag}`);
  }
  const id = String(opts.id).trim();
  if (id.length > ID_MAX_LEN) usageError(`--id "${id}" is ${id.length} chars (max ${ID_MAX_LEN})`);
  if (!FOLLOW_UP_ID_RE.test(id)) usageError(`--id "${id}" does not match ^fu-[a-z0-9]+(-[a-z0-9]+)*$`);
  if (!SEVERITIES.includes(opts.severity)) usageError(`--severity must be one of ${SEVERITIES.join(', ')} (got "${opts.severity}")`);
  if (opts.origin !== undefined && opts.origin !== 'backfill') usageError(`--origin only accepts "backfill" (got "${opts.origin}")`);
  if (opts.source_ts !== undefined && Number.isNaN(Date.parse(opts.source_ts))) usageError(`--source-ts "${opts.source_ts}" is not a parseable timestamp`);

  requireReadableLedger(abs);
  const reg = loadRegistry(abs);
  if (reg.unreadable) usageError(`ledger not readable: ${abs} (${reg.unreadable.code}: ${reg.unreadable.message})`);
  if (reg.items.some((i) => i.id === id)) usageError(`duplicate --id "${id}" — ids are never reused (first occurrence already in ${abs})`);

  const entry = {
    v: 1,
    ts: nowIso(),
    actor: opts.actor ?? 'orchestrator',
    type: 'follow_up',
    id,
    ref_id: opts.ref,
    severity: opts.severity,
    finding: opts.what,
    decision: opts.why,
    source: opts.source,
  };
  if (opts.origin !== undefined) entry.origin = opts.origin;
  if (opts.source_ts !== undefined) entry.source_ts = opts.source_ts;
  appendLine(abs, entry);

  // Prove the write the same way `close` does: re-read from disk and re-fold.
  const after = loadRegistry(abs);
  const item = after.items.find((i) => i.id === id);
  if (!item) {
    process.stderr.write(`follow-ups: appended ${id} but the re-read did not show it in ${abs}\n`);
    exit(1);
  }
  console.log(`follow-ups: added ${id} (${item.severity} ${item.ref_id}) — open backlog is now ${after.counts.open}`);
  exit(0);
}

function cmdClose(opts) {
  const abs = ledgerPath(opts);
  if (opts.id === undefined || String(opts.id).trim() === '') usageError('`close` requires --id');
  if (opts.resolved_by === undefined || String(opts.resolved_by).trim() === '') usageError('`close` requires --resolved-by');
  const id = String(opts.id).trim();
  const status = opts.status ?? 'done';
  if (!TERMINAL_STATUSES.includes(status)) usageError(`--status must be one of ${TERMINAL_STATUSES.join(', ')} (got "${status}")`);
  if (opts.origin !== undefined && opts.origin !== 'backfill') usageError(`--origin only accepts "backfill" (got "${opts.origin}")`);
  if (opts.source_ts !== undefined && Number.isNaN(Date.parse(opts.source_ts))) usageError(`--source-ts "${opts.source_ts}" is not a parseable timestamp`);

  requireReadableLedger(abs);
  const before = loadRegistry(abs);
  if (before.unreadable) usageError(`ledger not readable: ${abs} (${before.unreadable.code}: ${before.unreadable.message})`);
  const current = before.items.find((i) => i.id === id);
  if (!current) usageError(`unknown --id "${id}" — no follow_up with that id in ${abs}`);
  if (current.closed) {
    console.log(`NOTE follow-up ${id} is already ${current.status} (resolved_by ${current.resolved_by ?? 'n/a'}) — nothing appended, re-close is idempotent`);
    exit(0);
  }

  const entry = {
    v: 1,
    ts: nowIso(),
    actor: opts.actor ?? 'orchestrator',
    type: 'follow_up_status',
    id,
    status,
    resolved_by: opts.resolved_by,
    source: opts.source ?? '',
  };
  if (opts.origin !== undefined) entry.origin = opts.origin;
  if (opts.source_ts !== undefined) entry.source_ts = opts.source_ts;
  appendLine(abs, entry);

  // PROVE THE FLIP (D5/AC-005): re-read from disk, re-fold, and only then
  // claim success. A future-dated status record for the same id shadows the
  // append — that is a real, reachable failure and it must exit 1, not 0.
  const after = loadRegistry(abs);
  const item = after.items.find((i) => i.id === id);
  if (!item || item.status !== status) {
    process.stderr.write(`follow-ups: appended the ${status} status for ${id}, but the re-read of ${abs} shows status "${item ? item.status : 'MISSING'}" — the flip is NOT proven (a later-dated status record for this id may shadow it)\n`);
    exit(1);
  }
  console.log(`follow-ups: ${id} -> ${item.status} (resolved_by ${item.resolved_by}), proven by re-reading ${abs} — open backlog is now ${after.counts.open}`);
  exit(0);
}

function main() {
  const opts = parseArgs(process.argv);
  if (opts._sub === 'add') return cmdAdd(opts);
  if (opts._sub === 'close') return cmdClose(opts);
  return cmdList(opts);
}

// COPILOT/routine-emit hardening: path.resolve() never follows symlinks, so
// invoking this script through a symlinked path (macOS TMPDIR under /var ->
// /private/var, or a vendored symlink) made argv[1] differ from the module
// path and isMain silently false. Compare REALPATHS on both sides.
function realpathOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
const __filename = fileURLToPath(import.meta.url);
const isMain = process.argv[1] && realpathOrResolve(process.argv[1]) === realpathOrResolve(__filename);
if (isMain) runMain(() => main());

export {
  DEFAULT_LEDGER,
  FOLLOW_UP_ID_RE,
  ID_MAX_LEN,
  readDecisionsLedger,
  foldFollowUps,
  loadRegistry,
  deriveLegacyId,
};
