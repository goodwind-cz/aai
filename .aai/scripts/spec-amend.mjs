#!/usr/bin/env node
// spec-amend.mjs — post-freeze spec amendments get a DRAINABLE outflow
// (CHANGE unsigned-spec-amendment-has-no-outflow /
//  SPEC spec-unsigned-spec-amendment-has-no-outflow).
//
// PURPOSE
//   When an autonomous ride outgrows its frozen spec, the house convention is
//   additive-with-disclosure: amend the spec, append a `type: spec_amendment`
//   record, and say plainly that no owner sign-off was obtained. That
//   disclosure had no outflow. It landed in an append-only ledger no role is
//   obliged to read, set no `human_input`, filed no follow-up and entered no
//   queue — so a HITL gate was discharged by self-disclosure. Nine such
//   amendments across five specs stood unsigned when this script was written.
//
//   This script gives the disclosure a terminus, WITHOUT giving an autonomous
//   ride a new way to strand itself:
//
//     a fail-OPEN writer that co-creates, plus a fail-CLOSED detector at a gate
//
//   `add` never refuses an amendment for want of a tracked item — it
//   MANUFACTURES the tracked item in the same invocation. So after any
//   successful `add --signoff none` a follow-up naming the spec and the
//   sign-off still owed provably exists, satisfied by CONSTRUCTION rather than
//   by a refusal path that could halt a remediation round. The only non-zero
//   exits on `add` are usage errors — defects in the invocation, never states
//   of the world the ride cannot fix.
//
//   `list --strict` is the other half: it exits 1 when any amendment on the
//   ledger is untracked or unclassified. That is wired at the PR/close gate,
//   where stopping costs a re-run and not a stranded ride.
//
// THE FORMAT TRAP (why every query here parses JSON per line)
//   Measured on the live ledger at be0c8ed:
//     /usr/bin/grep -c '"type":"spec_amendment"' docs/ai/decisions.jsonl -> 4
//     JSON.parse per line                                                -> 10
//   Six of the ten records serialize the key WITH a space
//   (`"type": "spec_amendment"`). A grep-based query under-reports this
//   population by 60%. Nothing in this file may match the ledger by text.
//
// THE HEADING IS NOT A LOCATOR EITHER
//   SPEC-0164 carries three of the nine unsigned amendments and has no
//   `## Amendment` heading at all — it records them as inline `CORRECTED
//   post-freeze (…, amendment item N)` annotations. Heading text cannot
//   classify what heading text does not exist. The classifier is the
//   `owner_signoff` key, and nothing else.
//
// THREE BUCKETS, NOT TWO (D3)
//   owner_signoff === true   -> signed
//   owner_signoff === false  -> unsigned-tracked | unsigned-untracked
//   key absent, no overlay   -> unclassified
//
//   `unclassified` is a distinct bucket ON PURPOSE. Reading an absent field as
//   "unsigned" is a guess; reading it as "signed" is exactly how the one
//   genuinely owner-signed amendment on this ledger got laundered into a
//   precedent chain for unsigned ones (named, with its authority record, in
//   .aai/system/AUTONOMOUS_LOOP.md section 6a — the convention's only
//   statement, and the only file allowed to cite it). `--strict` fails on
//   `unclassified` for the same reason it fails on untracked: this mechanism
//   must never silently decide which of the two an old record was.
//
// RECORD SHAPES
//   {"v":1,"ts":"<ISO8601Z>","actor":"<slug>","type":"spec_amendment",
//    "ref_id":"<ride ref>","spec":"<repo-relative path>",
//    "spec_id":"<frontmatter id>","owner_signoff":<bool>,
//    "what":"<one line>","why":"<one line>",
//    "authority":"<evidence>",     // present iff owner_signoff true
//    "tracked_by":"fu-amend-…"}    // present iff owner_signoff false
//
//   {"v":1,"ts":"<ISO8601Z>","actor":"<slug>",
//    "type":"spec_amendment_classification",
//    "classifies_ts":"<target record ts>","classifies_ref":"<target ref_id>",
//    "owner_signoff":<bool>,"why":"<one line>","origin":"backfill",
//    "source":"<evidence>",
//    "tracked_by":"fu-amend-…"}    // OPTIONAL, see BACK-CLASSIFICATION below
//
//   The `follow_up` line this script writes is follow-ups.mjs's OWN documented
//   shape, unchanged — this script produces what that script consumes. It does
//   not import follow-ups.mjs's internals; it writes the same documented shape,
//   and tests/skills/test-aai-spec-amend.sh asserts the result THROUGH the real
//   `follow-ups.mjs list`, never through a mock.
//
// BACK-CLASSIFICATION IS BY APPEND (HAZ-LEDGER)
//   docs/ai/decisions.jsonl is append-only. The pre-existing records are never
//   edited. A `spec_amendment_classification` overlay carries the verdict, and
//   the fold takes the LATEST overlay per target, else the record's own
//   `owner_signoff` key, else `unclassified` — the same latest-wins shape
//   follow-ups.mjs already uses for `follow_up_status`.
//
//   The target is addressed by the `(ts, ref_id)` PAIR, never by line number:
//   line numbers are not stable identifiers. `classify` refuses an unmatched
//   or ambiguous target with exit 2 rather than guessing.
//
//   The overlay's `tracked_by` is the one field beyond the classification
//   itself: a record written before this script existed carries no
//   `tracked_by`, so without it a back-classified unsigned amendment could
//   never leave `unsigned-untracked` and `--strict` could never reach 0 on the
//   live ledger. It is OPTIONAL and only ever consulted when the amendment
//   record itself has none.
//
// THE ITEM ID KEYS ON THE FRONTMATTER `id`, NEVER THE FILENAME (SEAM-1)
//   allocate-doc-number.mjs renames `SPEC-DRAFT-<slug>.md` to
//   `SPEC-000N-<slug>.md` at merge. Every one of the nine standing amendments
//   cites a `SPEC-DRAFT-…` path that no longer exists on disk. A path-keyed id
//   would silently fork into two items across that rename, so the id is
//   `fu-amend-<spec frontmatter id>` — one durable item per SPEC, because the
//   owner's decision is per spec ("do I accept the amended SPEC-0161, or
//   reverse it?"), not per ledger line.
//
//   MEASURED CONSTRAINT: follow-ups.mjs enforces ^fu-[a-z0-9]+(-[a-z0-9]+)*$
//   at 40 chars max, and marks a longer id MALFORMED-ID on every read. TWO
//   of the five live spec ids fit (38 and 37 chars); THREE do not (44, 47,
//   55) — one is shortened, two are truncated-and-hashed
//   (`fu-amend-spec-metrics-flush-invalidates-pr-precondition` is 55). So
//   `amendItemId` is a FITTING function, not a concatenation: it returns the
//   plain form when it fits, else drops the redundant leading `spec-`, else
//   truncates and appends 6 hex of sha256(<full spec id>). The hash is taken
//   over the frontmatter id, so the durability SEAM-1 needs is preserved
//   exactly — the id is still a pure function of the spec's durable identity
//   and of nothing else.
//
//   Because it FITS, it is not the identity: the id is `fu-amend-<spec id>`
//   only when that fits, and THREE of the five live ids are the shortened or
//   hashed form (one shortened, two hashed). Anything that states the rule as a plain concatenation is
//   wrong, and `.aai/system/AUTONOMOUS_LOOP.md` section 6a and
//   `.aai/ROLE_COMMON.md` say "fitted" for that reason.
//
//   NOT INJECTIVE ACROSS THE `spec-` STRIP, accepted (validation NB-1). The
//   shortening branch maps `spec-<X>` and `<X>` to the same id whenever
//   `fu-amend-spec-<X>` exceeds 40 chars and `fu-amend-<X>` does not.
//   Measured: 0 collisions across all 167 spec frontmatter ids in docs/specs.
//   Hashing that branch too would restore injectivity and cost every future
//   id its readability at the gate, where a human reads
//   `fu-amend-spec-close-leaves-state-stale` and knows which spec is owed a
//   sign-off without resolving a hash first. The failure it would prevent
//   is two specs sharing ONE owner obligation — visible in the item's own
//   `finding`, which names its spec, and never a laundering: the record still
//   reads `unsigned-tracked`, never `signed`. Readability wins until a
//   collision is reachable.
//
// EXIT CONTRACT
//   0  success (including `list` with a non-empty unsigned backlog — a backlog
//      is the point of this tool, never an error)
//   1  a `--strict` violation, or a post-append re-read that did not confirm
//      the write
//   2  usage error: unknown flag/subcommand, missing required flag, an
//      unreadable ledger or spec, a spec with no frontmatter `id`, or an
//      ambiguous/unmatched `classify` target
//
// APPEND DISCIPLINE — one fs.appendFileSync of one serialized line, the house
//   JSONL pattern, with a leading \n when the ledger's last byte is not one.
//   The JSON is machine-serialized so this path can never be the source of the
//   malformed line that fails routine-emit.mjs's authorization reader CLOSED
//   over the whole ledger (SEAM-4).
//
// Node stdlib only, zero network, no LLM (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const DEFAULT_LEDGER = 'docs/ai/decisions.jsonl';
const ITEM_PREFIX = 'fu-amend-';
const FOLLOW_UP_ID_RE = /^fu-[a-z0-9]+(-[a-z0-9]+)*$/;
const ID_MAX_LEN = 40;
const HASH_LEN = 6;
const ITEM_SEVERITY = 'P2';
const TERMINAL_STATUSES = ['done', 'dropped'];
const BUCKETS = ['signed', 'unsigned-tracked', 'unsigned-untracked', 'unclassified'];

// --- reading ------------------------------------------------------------------

// Same contract as follow-ups.mjs's reader: blank and `#` comment lines are
// skipped (the real ledger opens with a comment header), a malformed
// non-comment line is COUNTED and named, never fatal to a REPORTER. The split
// by err.code matters: ENOENT is an ABSENT ledger; anything else (EISDIR,
// EACCES, EIO) is UNREADABLE and must never be folded into "absent" — a
// directory answering "no amendments here" is the failure shape this split
// exists to remove.
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

function str(value) {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}

function slugify(value) {
  const s = String(value ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return s === '' ? 'unknown' : s;
}

// fitItemId(core) — render one slug into follow-ups.mjs's id grammar. See the
// MEASURED CONSTRAINT note in the header: this is a fitting function, and the
// hashed branch is reached by real spec ids on this repo today, not
// hypothetically.
function fitItemId(core) {
  const slug = slugify(core);
  const full = `${ITEM_PREFIX}${slug}`;
  if (full.length <= ID_MAX_LEN && FOLLOW_UP_ID_RE.test(full)) return full;
  const short = slug.replace(/^spec-/, '');
  const shortened = `${ITEM_PREFIX}${short}`;
  if (shortened.length <= ID_MAX_LEN && FOLLOW_UP_ID_RE.test(shortened)) return shortened;
  const hash = crypto.createHash('sha256').update(slug).digest('hex').slice(0, HASH_LEN);
  const budget = ID_MAX_LEN - ITEM_PREFIX.length - 1 - HASH_LEN;
  const stem = short.slice(0, budget).replace(/-+$/, '') || 'spec';
  return `${ITEM_PREFIX}${stem}-${hash}`;
}

function amendItemId(specId) {
  return fitItemId(specId);
}

// A second amendment on a spec whose item was already CLOSED reopens the
// obligation under a disambiguated id. The stamp is lowercase on purpose:
// follow-ups.mjs's grammar has no uppercase, so a `yyyymmddThhmm` stamp would
// be marked MALFORMED-ID on every read of the registry forever.
function stampFor(iso) {
  const m = String(iso ?? '').match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
  return m ? `${m[1]}${m[2]}${m[3]}t${m[4]}${m[5]}` : 'unknown';
}

function amendItemIdStamped(specId, stamp) {
  return fitItemId(`${specId}-${stamp}`);
}

function overlayKey(ts, ref) {
  const t = str(ts);
  const r = str(ref);
  if (t === null || r === null) return null;
  return `${t} ${r}`;
}

// Codepoint ordering, never localeCompare: "latest wins" must not depend on
// the machine's LANG/ICU build (follow-ups.mjs review NB-2, same reasoning).
function byTsAscending(a, b) {
  const at = String(a.ts ?? '');
  const bt = String(b.ts ?? '');
  return at < bt ? -1 : at > bt ? 1 : 0;
}

// foldAmendments(records) -> { items, followUps, notes, counts, byKey }
// The projection is computed, never stored. Every read in this file goes
// through here so the CLI's four surfaces cannot drift from each other.
function foldAmendments(records) {
  const notes = [];
  const amendments = [];
  const overlays = new Map();
  const fuItems = new Map();
  const fuStatuses = new Map();
  let danglingOverlays = 0;

  for (const rec of records) {
    if (!rec || typeof rec !== 'object') continue;
    // THE TWO ERROR DIRECTIONS ARE DELIBERATELY OPPOSITE (validation NB-2).
    // A `type` value carrying stray whitespace (`" spec_amendment "`) reads as
    // an amendment to every human and to no exact-match query, so the two
    // AMENDMENT types are matched on the TRIMMED value: over-detecting what
    // the gate must catch can only turn a green gate red, never launder a
    // record. The follow-up types keep the house exact-match convention on
    // purpose — those are what EXCUSE an amendment, and over-detecting an
    // excuse is the one error this file must not make. A record that reaches
    // `--strict` through the trim and is tracked by an item that only a trim
    // would find therefore still fails, which is the correct answer.
    const recType = typeof rec.type === 'string' ? rec.type.trim() : rec.type;
    if (recType === 'spec_amendment') {
      amendments.push(rec);
    } else if (recType === 'spec_amendment_classification') {
      const key = overlayKey(rec.classifies_ts, rec.classifies_ref);
      if (key === null) {
        danglingOverlays += 1;
        continue;
      }
      if (!overlays.has(key)) overlays.set(key, []);
      overlays.get(key).push(rec);
    } else if (rec.type === 'follow_up') {
      const id = str(rec.id);
      if (id !== null && !fuItems.has(id)) fuItems.set(id, rec);
    } else if (rec.type === 'follow_up_status') {
      const id = str(rec.id);
      if (id === null) continue;
      if (!fuStatuses.has(id)) fuStatuses.set(id, []);
      fuStatuses.get(id).push(rec);
    }
  }

  // follow-ups.mjs's own fold, narrowed to the one question asked here: is
  // this id present, and is it closed? Latest usable status wins; a status
  // record with no usable `status` key never re-opens or closes anything.
  const followUps = new Map();
  for (const [id, rec] of fuItems) {
    const history = (fuStatuses.get(id) ?? []).slice().sort(byTsAscending);
    const usable = history.filter((h) => str(h.status) !== null).pop() ?? null;
    const status = usable ? usable.status.trim() : 'open';
    followUps.set(id, { id, rec, status, closed: TERMINAL_STATUSES.includes(status) });
  }

  const byKey = new Map();
  const items = [];
  let duplicateKeys = 0;
  for (const rec of amendments) {
    const key = overlayKey(rec.ts, rec.ref_id);
    const history = key === null ? [] : (overlays.get(key) ?? []).slice().sort(byTsAscending);
    const overlay = history.filter((h) => typeof h.owner_signoff === 'boolean').pop() ?? null;

    let signoff = null;
    let classifiedBy = null;
    if (overlay !== null) {
      signoff = overlay.owner_signoff;
      classifiedBy = str(overlay.ts);
    } else if (typeof rec.owner_signoff === 'boolean') {
      signoff = rec.owner_signoff;
    }

    // The record's OWN tracked_by wins; the overlay's is the back-fill route
    // for a record written before this script existed. Never the other way
    // round — an overlay must not be able to re-point a live record's item.
    const trackedBy = str(rec.tracked_by)
      ?? (overlay !== null ? str(overlay.tracked_by) : null)
      ?? (history.map((h) => str(h.tracked_by)).filter((v) => v !== null).pop() ?? null);
    const trackedItem = trackedBy === null ? null : followUps.get(trackedBy) ?? null;

    let bucket;
    if (signoff === true) bucket = 'signed';
    else if (signoff === false) bucket = trackedItem !== null ? 'unsigned-tracked' : 'unsigned-untracked';
    else bucket = 'unclassified';

    const item = {
      ts: str(rec.ts),
      ref_id: str(rec.ref_id),
      spec: str(rec.spec) ?? str(rec.amends),
      spec_id: str(rec.spec_id),
      actor: str(rec.actor),
      owner_signoff: signoff,
      classified_by: classifiedBy,
      tracked_by: trackedBy,
      tracked_status: trackedItem === null ? null : trackedItem.status,
      bucket,
      what: str(rec.what) ?? str(rec.change) ?? str(rec.finding) ?? '',
    };
    items.push(item);
    if (key !== null) {
      if (byKey.has(key)) duplicateKeys += 1;
      else byKey.set(key, item);
    }
  }

  let orphanOverlays = 0;
  for (const key of overlays.keys()) if (!byKey.has(key)) orphanOverlays += 1;

  if (danglingOverlays) {
    notes.push(`NOTE ${danglingOverlays} spec_amendment_classification record(s) carry no usable classifies_ts/classifies_ref pair — counted, never applied`);
  }
  if (orphanOverlays) {
    notes.push(`NOTE ${orphanOverlays} spec_amendment_classification record(s) address a (ts, ref_id) pair with no spec_amendment — counted, never applied`);
  }
  if (duplicateKeys) {
    notes.push(`NOTE ${duplicateKeys} spec_amendment record(s) share a (ts, ref_id) pair with an earlier one — every record is still LISTED and counted; only \`classify\` refuses such a pair, as ambiguous`);
  }

  const counts = { total: items.length };
  for (const b of BUCKETS) counts[b] = items.filter((i) => i.bucket === b).length;
  return { items, followUps, notes, counts, byKey };
}

function loadLedger(absPath) {
  const { records, malformed, missing, unreadable } = readDecisionsLedger(absPath);
  const folded = foldAmendments(records);
  const notes = [];
  if (missing) notes.push(`NOTE decision ledger absent at ${absPath} — no amendments to report`);
  if (unreadable) notes.push(`NOTE decision ledger at ${absPath} could not be read (${unreadable.code}: ${unreadable.message}) — refused, never treated as an empty ledger`);
  if (malformed) {
    notes.push(`EXCLUDED ${malformed} malformed decision ledger line(s) (unparseable JSON, skipped — comment lines are not counted) — the counts above may therefore be UNDERSTATED`);
  }
  return { ...folded, notes: notes.concat(folded.notes), malformed, missing, unreadable };
}

// --- writing ------------------------------------------------------------------

function nowIso() {
  return `${new Date().toISOString().slice(0, 19)}Z`;
}

// pickAmendItemId — the ONE place that decides which item an unsigned
// amendment attaches to, shared by `add` and `classify` so the two writers
// cannot drift. A base item that is already open is reused (the owner's
// decision is per SPEC, not per ledger line); one that is already CLOSED is
// not silently re-used, because attaching a new amendment to a discharged
// obligation would mark it signed by an owner who never saw it — the
// obligation reopens under a disambiguated, stamped id instead.
function pickAmendItemId(reg, specKey, tsIso) {
  const base = amendItemId(specKey);
  const existing = reg.followUps.get(base) ?? null;
  if (existing === null) return { itemId: base, note: null };
  if (!existing.closed) {
    return { itemId: base, note: `tracked item ${base} already open — this amendment attaches to it (the owner's decision is per SPEC, not per ledger line)` };
  }
  const stamp = stampFor(tsIso);
  let candidate = amendItemIdStamped(specKey, stamp);
  if (reg.followUps.has(candidate)) candidate = amendItemIdStamped(`${specKey}-${stamp}`, '2');
  return { itemId: candidate, note: `tracked item ${base} is ${existing.status} — this amendment reopens the obligation as ${candidate}` };
}

// appendAmendItem — the follow-ups.mjs `follow_up` line both writers file, in
// ONE place: the item `add` co-creates and the item `classify` co-creates are
// the same obligation in the same words, so a gate cleared by either route
// reads identically in `follow-ups.mjs list`.
function appendAmendItem(absPath, { actor, itemId, ref, specId, specRel, what, why, sourceTs }) {
  appendLine(absPath, {
    v: 1,
    ts: nowIso(),
    actor,
    type: 'follow_up',
    id: itemId,
    ref_id: ref,
    severity: ITEM_SEVERITY,
    finding: `owner sign-off owed on the post-freeze amendment(s) to ${specId} (${specRel}): ${what}`,
    decision: `filed unsigned under the additive-with-disclosure convention by ${actor}; the owner may accept the amended spec or reverse it. ${why}`,
    source: `${path.relative(process.cwd(), absPath) || absPath} ts=${sourceTs} type=spec_amendment ref_id=${ref}`,
  });
}

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

// --- CLI ----------------------------------------------------------------------

const USAGE = `Usage:
  node .aai/scripts/spec-amend.mjs add --spec <path> --ref <ref_id>
       --what "<one line>" --why "<one line>" --signoff owner|none
       [--authority "<evidence>"]   (REQUIRED when --signoff owner)
       [--actor <slug>] [--ledger <path>]

  node .aai/scripts/spec-amend.mjs classify --ts <ISO8601Z> --ref <ref_id>
       --signoff owner|none --why "<one line>" --source "<evidence>"
       [--origin backfill] [--tracked-by fu-amend-<id>] [--actor <slug>]
       [--ledger <path>]

  node .aai/scripts/spec-amend.mjs list [--status unsigned|signed|unclassified|all]
       [--json] [--strict] [--ledger <path>]

  node .aai/scripts/spec-amend.mjs --help

\`add\` NEVER refuses an unsigned amendment for want of a tracked item: it
appends the amendment AND manufactures the follow-up naming the spec and the
sign-off still owed, in one invocation. Its only non-zero exits are usage
errors. Enforcement that nobody bypassed this writer lives in \`list --strict\`,
which is a GATE, not a writer: it exits 1 on any untracked or unclassified
amendment and is run at the PR/close gate.

Buckets are decided by the \`owner_signoff\` key alone — never by heading text
and never by prose inside \`authority\`. A record with the key absent and no
classification overlay is \`unclassified\`, its own bucket, because deciding
which of the other two an old record "must have been" is the laundering this
tool exists to stop.

\`classify\` back-classifies an existing record by APPENDING an overlay
(docs/ai/decisions.jsonl is append-only — HAZ-LEDGER); the target record is
never edited. The target is the (--ts, --ref) PAIR, never a line number.
Like \`add\`, \`classify --signoff none\` CO-CREATES the tracked item when the
target has none, so ONE call takes a record from \`unsigned-untracked\` or
\`unclassified\` to \`unsigned-tracked\` and \`list --strict\` to exit 0. Pass
\`--tracked-by fu-…\` only to attach an item you have already filed; the id is
otherwise derived from the target's own \`spec_id\`. That is why the ONLY
remedy \`--strict\` names is \`classify\`: \`add\` records a NEW amendment and
leaves the offending record untracked, and \`follow-ups.mjs add\` files an item
that is attached to nothing.

A flag value may begin with two dashes as long as it is not EXACTLY a flag
token this CLI knows. When it is, write it as --flag=value instead, which
takes everything after the FIRST = verbatim.

Exit codes: 0 success (a non-empty unsigned backlog is NEVER an error) |
1 a --strict violation, or a post-append re-read that did not confirm the
write | 2 usage error, an unreadable ledger or spec, a spec with no
frontmatter id, or an ambiguous/unmatched classify target.`;

function usageError(msg) {
  process.stderr.write(`spec-amend: ${msg}\n`);
  process.stderr.write('Run `node .aai/scripts/spec-amend.mjs --help` for the grammar.\n');
  exit(2);
}

const FLAG_SPECS = {
  add: ['--ledger', '--spec', '--ref', '--what', '--why', '--signoff', '--authority', '--actor'],
  classify: ['--ledger', '--ts', '--ref', '--signoff', '--why', '--source', '--origin', '--tracked-by', '--actor'],
  list: ['--ledger', '--status'],
};

// A value is a value unless it is EXACTLY a token this CLI knows — never a
// prefix test, and the known-token set is built from EVERY subcommand's flags
// (follow-ups.mjs review NB-1): a per-subcommand set lets a mistyped or
// foreign-subcommand flag in value position be silently swallowed as a value,
// which is "a bad input reads as success" one function over from where this
// tool removes it.
function parseArgs(argv) {
  const rest = argv.slice(2);
  let sub = 'list';
  if (rest.length > 0 && !rest[0].startsWith('-')) sub = rest.shift();
  if (sub === 'help') {
    console.log(USAGE);
    exit(0);
  }
  if (!Object.prototype.hasOwnProperty.call(FLAG_SPECS, sub)) {
    usageError(`unknown subcommand "${sub}" (expected add, classify or list)`);
  }
  const valueFlags = FLAG_SPECS[sub];
  const knownTokens = new Set([...Object.values(FLAG_SPECS).flat(), '--json', '--strict', '--help', '-h']);
  const opts = { json: false, strict: false };
  for (let i = 0; i < rest.length; i += 1) {
    const tok = rest[i];
    if (tok === '-h' || tok === '--help') {
      console.log(USAGE);
      exit(0);
    }
    if (tok === '--json') {
      if (sub !== 'list') usageError('--json is only valid on `list`');
      opts.json = true;
      continue;
    }
    if (tok === '--strict') {
      if (sub !== 'list') usageError('--strict is only valid on `list`');
      opts.strict = true;
      continue;
    }
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

function requireReadableFile(abs, label) {
  let st;
  try {
    st = fs.statSync(abs);
  } catch (err) {
    usageError(`${label} not found or not readable: ${abs} (${err && err.code})`);
    return;
  }
  if (!st.isFile()) usageError(`${label} is not a regular file: ${abs}`);
  try {
    fs.accessSync(abs, fs.constants.R_OK);
  } catch {
    usageError(`${label} not readable: ${abs}`);
  }
}

function loadLedgerOrRefuse(abs) {
  requireReadableFile(abs, 'ledger');
  const reg = loadLedger(abs);
  if (reg.unreadable) usageError(`ledger not readable: ${abs} (${reg.unreadable.code}: ${reg.unreadable.message})`);
  return reg;
}

function requireSignoff(opts, sub) {
  const v = str(opts.signoff);
  if (v === null) usageError(`\`${sub}\` requires --signoff (owner or none)`);
  if (v !== 'owner' && v !== 'none') usageError(`--signoff must be "owner" or "none" (got "${v}")`);
  return v === 'owner';
}

// readSpecId — SEAM-1. The tracked item's key is the spec's frontmatter `id`
// and is NEVER guessed from the filename: allocate-doc-number.mjs renames the
// file at merge, and every standing amendment on this ledger cites a
// SPEC-DRAFT-… path that no longer exists.
function readSpecId(absSpec) {
  requireReadableFile(absSpec, '--spec');
  let text;
  try {
    text = fs.readFileSync(absSpec, 'utf8');
  } catch (err) {
    usageError(`--spec not readable: ${absSpec} (${err && err.code})`);
    return null;
  }
  const fm = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!fm) {
    usageError(`--spec ${absSpec} has no YAML frontmatter block — the tracked item keys on the frontmatter \`id\`, never on the filename, so it cannot be derived here`);
    return null;
  }
  const idLine = fm[1].match(/^id:[ \t]*(.+?)[ \t]*$/m);
  const id = idLine ? str(idLine[1]) : null;
  if (id === null) {
    usageError(`--spec ${absSpec} has no frontmatter \`id\` — the tracked item keys on it, never on the filename, so it cannot be derived here`);
    return null;
  }
  return id;
}

function cmdAdd(opts) {
  const abs = ledgerPath(opts);
  for (const [flag, key] of [['--spec', 'spec'], ['--ref', 'ref'], ['--what', 'what'], ['--why', 'why']]) {
    if (str(opts[key]) === null) usageError(`\`add\` requires ${flag}`);
  }
  const signed = requireSignoff(opts, 'add');
  // The one REJECTED input this writer has that is not a missing flag: an
  // owner-signed amendment with nothing on the record saying who authorized
  // it would be indistinguishable from the laundering this tool exists to
  // stop, so the message names the flag rather than describing it.
  if (signed && str(opts.authority) === null) {
    usageError('`add --signoff owner` requires --authority naming the owner decision that authorized this amendment (an owner sign-off with no evidence on the record is exactly the laundering this tool exists to prevent)');
  }

  const absSpec = path.resolve(process.cwd(), opts.spec);
  const specId = readSpecId(absSpec);
  const specRel = path.relative(process.cwd(), absSpec) || opts.spec;

  const reg = loadLedgerOrRefuse(abs);

  const entry = {
    v: 1,
    ts: nowIso(),
    actor: str(opts.actor) ?? 'orchestrator',
    type: 'spec_amendment',
    ref_id: opts.ref,
    spec: specRel,
    spec_id: specId,
    owner_signoff: signed,
    what: opts.what,
    why: opts.why,
  };

  let itemId = null;
  let reusedNote = null;
  if (!signed) {
    const picked = pickAmendItemId(reg, specId, entry.ts);
    itemId = picked.itemId;
    reusedNote = picked.note;
    entry.tracked_by = itemId;
  } else {
    entry.authority = opts.authority;
  }

  appendLine(abs, entry);

  if (!signed && !reg.followUps.has(itemId)) {
    appendAmendItem(abs, {
      actor: entry.actor,
      itemId,
      ref: opts.ref,
      specId,
      specRel,
      what: opts.what,
      why: opts.why,
      sourceTs: entry.ts,
    });
  }

  // Prove BOTH writes by re-reading from disk and re-folding — the same
  // discipline follow-ups.mjs's `close` uses. A claim that the ledger now
  // holds the obligation is worth nothing if it was never read back.
  const after = loadLedger(abs);
  const key = overlayKey(entry.ts, entry.ref_id);
  const landed = after.byKey.get(key) ?? null;
  if (landed === null) {
    process.stderr.write(`spec-amend: appended the amendment for ${opts.ref} but the re-read of ${abs} did not show it\n`);
    exit(1);
  }
  if (!signed && (landed.tracked_by !== itemId || !after.followUps.has(itemId))) {
    process.stderr.write(`spec-amend: appended the amendment for ${opts.ref} but the re-read of ${abs} does not show the tracked item ${itemId} — AC-001 is NOT satisfied by this write\n`);
    exit(1);
  }

  if (signed) {
    console.log(`spec-amend: recorded a SIGNED amendment on ${specId} (ref ${opts.ref}, authority on the record) — no tracked item is owed`);
  } else {
    console.log(`spec-amend: recorded an UNSIGNED amendment on ${specId} (ref ${opts.ref}) tracked by ${itemId} — bucket ${landed.bucket}`);
    if (reusedNote) console.log(`NOTE ${reusedNote}`);
    console.log(`NOTE drain it with: node .aai/scripts/follow-ups.mjs list --status open`);
  }
  exit(0);
}

function cmdClassify(opts) {
  const abs = ledgerPath(opts);
  for (const [flag, key] of [['--ts', 'ts'], ['--ref', 'ref'], ['--why', 'why'], ['--source', 'source']]) {
    if (str(opts[key]) === null) usageError(`\`classify\` requires ${flag}`);
  }
  const signed = requireSignoff(opts, 'classify');
  if (opts.origin !== undefined && opts.origin !== 'backfill') {
    usageError(`--origin only accepts "backfill" (got "${opts.origin}")`);
  }
  const trackedBy = str(opts.tracked_by);
  if (trackedBy !== null && !FOLLOW_UP_ID_RE.test(trackedBy)) {
    usageError(`--tracked-by "${trackedBy}" does not match ^fu-[a-z0-9]+(-[a-z0-9]+)*$`);
  }

  const reg = loadLedgerOrRefuse(abs);
  const targets = reg.items.filter((i) => i.ts === str(opts.ts) && i.ref_id === str(opts.ref));
  if (targets.length === 0) {
    usageError(`no spec_amendment matches --ts "${opts.ts}" --ref "${opts.ref}" in ${abs} — the target is addressed by the (ts, ref_id) pair, never by line number`);
  }
  if (targets.length > 1) {
    usageError(`--ts "${opts.ts}" --ref "${opts.ref}" matches ${targets.length} spec_amendment records in ${abs} — ambiguous, refused rather than guessed`);
  }

  const entry = {
    v: 1,
    ts: nowIso(),
    actor: str(opts.actor) ?? 'orchestrator',
    type: 'spec_amendment_classification',
    classifies_ts: opts.ts,
    classifies_ref: opts.ref,
    owner_signoff: signed,
    why: opts.why,
  };
  if (opts.origin !== undefined) entry.origin = opts.origin;
  entry.source = opts.source;

  // `classify --signoff none` CO-CREATES, exactly as `add` does (validation
  // F1). Until this was here, `classify` was a writer that could leave the
  // gate red: back-classifying a record as unsigned told `--strict` the
  // record was unsigned and untracked, and the only route to a green gate ran
  // through `--tracked-by` plus a separately filed item — a fixed point named
  // in no prose, while the prose that WAS written named `classify` alone.
  // D2's fail-OPEN half applies to BOTH writers or to neither: a refusal whose
  // documented remedy does not clear the refusal is the very defect this
  // script exists to remove, one level up.
  const target = targets[0];
  const specKey = target.spec_id ?? target.ref_id;
  let reusedNote = null;
  if (!signed) {
    const candidate = trackedBy ?? target.tracked_by;
    if (candidate !== null) {
      // `pickAmendItemId` refuses to attach a NEW amendment to a DISCHARGED
      // obligation — "it would mark it signed by an owner who never saw it".
      // An explicit `--tracked-by` bypassed that check entirely, so naming a
      // CLOSED item took the gate green while `follow-ups.mjs list --status
      // open` — the drain list the refusal itself advertises — stayed empty.
      // That is this script's own defect class: an obligation with no outflow
      // (code review NB-B, reproduced). Refusing here does not strand anyone:
      // D2's fail-OPEN rule covers a MISSING item, and the remedy is to drop
      // the flag and let the writer reopen the obligation under a stamped id,
      // which the message below names.
      const named = reg.followUps.get(candidate) ?? null;
      if (trackedBy !== null && named !== null && named.closed) {
        usageError(`--tracked-by ${candidate} names an obligation that is already ${named.status}; attaching a new amendment to a discharged item would mark it signed by an owner who never saw it, and it would not appear in \`follow-ups.mjs list --status open\`. Drop --tracked-by and re-run: the writer reopens the obligation under a stamped id.`);
      }
      entry.tracked_by = candidate;
    } else {
      const picked = pickAmendItemId(reg, specKey, entry.ts);
      entry.tracked_by = picked.itemId;
      reusedNote = picked.note;
    }
  } else if (trackedBy !== null) {
    entry.tracked_by = trackedBy;
  }
  appendLine(abs, entry);

  // The item is filed against the EFFECTIVE tracked id read back off disk, not
  // against the one this call proposed: the fold lets a record's OWN
  // `tracked_by` outrank any overlay's, so filing before the re-read could
  // manufacture an orphan item for an id the gate will never consult.
  let after = loadLedger(abs);
  let landed = after.byKey.get(overlayKey(opts.ts, opts.ref)) ?? null;
  if (!signed && landed !== null && landed.tracked_by !== null && !after.followUps.has(landed.tracked_by)) {
    appendAmendItem(abs, {
      actor: entry.actor,
      itemId: landed.tracked_by,
      ref: opts.ref,
      specId: target.spec_id ?? specKey,
      specRel: target.spec ?? '(spec path not on the record)',
      what: target.what || `back-classified as unsigned: ${opts.why}`,
      why: opts.why,
      sourceTs: opts.ts,
    });
    after = loadLedger(abs);
    landed = after.byKey.get(overlayKey(opts.ts, opts.ref)) ?? null;
  }

  if (landed === null || landed.owner_signoff !== signed) {
    process.stderr.write(`spec-amend: appended the classification for ts=${opts.ts} ref=${opts.ref}, but the re-read of ${abs} shows owner_signoff "${landed ? landed.owner_signoff : 'MISSING'}" — the classification is NOT proven (a later-dated overlay for this target may shadow it)\n`);
    exit(1);
  }
  if (!signed && landed.bucket === 'unsigned-untracked') {
    process.stderr.write(`spec-amend: appended the classification for ts=${opts.ts} ref=${opts.ref} but the re-read of ${abs} still shows it ${landed.bucket} — the tracked item this call owed is NOT on the ledger, so \`list --strict\` would still refuse\n`);
    exit(1);
  }
  console.log(`spec-amend: classified ts=${opts.ts} ref=${opts.ref} as owner_signoff=${signed} — bucket ${landed.bucket}, proven by re-reading ${abs}`);
  if (!signed) {
    console.log(`spec-amend: tracked by ${landed.tracked_by} — drain it with: node .aai/scripts/follow-ups.mjs list --status open`);
    if (reusedNote) console.log(`NOTE ${reusedNote}`);
  }
  exit(0);
}

function formatRow(item) {
  return [
    item.bucket,
    item.ts ?? '-',
    item.ref_id ?? '-',
    `spec=${item.spec_id ?? '-'}`,
    `tracked_by=${item.tracked_by ?? '-'}`,
    `signoff=${item.owner_signoff === null ? 'absent' : String(item.owner_signoff)}`,
  ].join('  ');
}

const STATUS_FILTERS = {
  all: BUCKETS,
  signed: ['signed'],
  unsigned: ['unsigned-tracked', 'unsigned-untracked'],
  unclassified: ['unclassified'],
};

// A --strict violation is exactly the two buckets that mean "this ledger
// cannot answer the question this tool exists to answer": an unsigned
// amendment nobody can drain, and a record whose sign-off state is unknown.
const STRICT_VIOLATION_BUCKETS = ['unsigned-untracked', 'unclassified'];

function cmdList(opts) {
  const abs = ledgerPath(opts);
  const reg = loadLedgerOrRefuse(abs);
  const wantStatus = str(opts.status) ?? 'all';
  if (!Object.prototype.hasOwnProperty.call(STATUS_FILTERS, wantStatus)) {
    usageError(`--status must be one of ${Object.keys(STATUS_FILTERS).join(', ')} (got "${wantStatus}")`);
  }
  const allowed = STATUS_FILTERS[wantStatus];
  const shown = reg.items.filter((i) => allowed.includes(i.bucket));
  // --strict is judged over the WHOLE ledger, never over the filtered view: a
  // gate that could be silenced by narrowing its own query is not a gate.
  const violations = reg.items.filter((i) => STRICT_VIOLATION_BUCKETS.includes(i.bucket));
  const counts = { shown: shown.length, ...reg.counts };

  if (opts.json) {
    console.log(JSON.stringify({
      ledger: abs,
      strict: opts.strict,
      counts,
      items: shown,
      violations: violations.map((v) => ({ ts: v.ts, ref_id: v.ref_id, bucket: v.bucket })),
      notes: reg.notes,
    }, null, 2));
  } else {
    console.log(`spec-amend: shown=${counts.shown} total=${counts.total} signed=${counts.signed} unsigned-tracked=${counts['unsigned-tracked']} unsigned-untracked=${counts['unsigned-untracked']} unclassified=${counts.unclassified} ledger=${abs}`);
    for (const item of shown) console.log(formatRow(item));
    if (shown.length === 0) console.log('(no spec_amendment records match this view)');
    for (const n of reg.notes) console.log(n);
    for (const v of violations) {
      console.log(`STRICT-VIOLATION ${v.bucket} ts=${v.ts ?? '-'} ref=${v.ref_id ?? '-'} spec=${v.spec_id ?? '-'}`);
    }
  }

  if (opts.strict && violations.length > 0) {
    // A refusal whose named remedy does not clear the refusal is the defect
    // this script exists to remove, one level up (validation F1). Every
    // command named here is one that takes a record OUT of the two violating
    // buckets, and the two commands that do NOT are named as not doing it.
    process.stderr.write(`spec-amend: --strict found ${violations.length} amendment record(s) that are untracked or unclassified — an unsigned amendment with no tracked item has no outflow, and an unclassified one cannot be told from a signed one.\n`);
    process.stderr.write('Clear EACH record named above by APPEND, with its own ts and ref:\n');
    for (const v of violations) {
      // A record missing `ts` or `ref_id` cannot be matched by `classify`,
      // which keys on that pair — so printing a `<ts>` placeholder would be
      // a remedy that cannot be run, the degenerate cousin of the very
      // defect this block was rewritten to remove (validation OBS-1). Say
      // that instead. Neither writer can produce such a record (`add`
      // always stamps both), so reaching this line means the ledger was
      // hand-appended.
      if (v.ts === undefined || v.ts === null || v.ref_id === undefined || v.ref_id === null) {
        const missing = [
          (v.ts === undefined || v.ts === null) ? 'ts' : null,
          (v.ref_id === undefined || v.ref_id === null) ? 'ref_id' : null,
        ].filter(Boolean).join(' and ');
        process.stderr.write(`  (no runnable remedy: this record carries no ${missing}, and classify matches on the ts+ref pair. Neither writer can emit that, so the record was hand-appended; append a corrected record rather than editing it.)\n`);
        continue;
      }
      // JSON.stringify, not bare quotes: `--ref` is unvalidated free text at
      // `add`, so a ref carrying a double quote produced a line that breaks
      // when pasted — and TEST-013 runs this line through `eval` (code
      // review NB-E, reproduced through the writer, not only by hand-append).
      process.stderr.write(`  node .aai/scripts/spec-amend.mjs classify --ts ${JSON.stringify(v.ts)} --ref ${JSON.stringify(v.ref_id)} --signoff none --why "<one line>" --source "<evidence>"\n`);
    }
    process.stderr.write('`--signoff none` also FILES the tracked item in that same call, so each command above takes its record to `unsigned-tracked` and this gate to exit 0; use `--signoff owner --why … --source …` instead when the owner actually decided, naming the record that proves it, and `--tracked-by fu-…` to attach an item you have already filed.\n');
    process.stderr.write('NOT remedies: `spec-amend.mjs add` records a NEW amendment and leaves the record named above untracked; `follow-ups.mjs add` files an item but attaches it to nothing. Never edit the ledger in place (HAZ-LEDGER).\n');
    exit(1);
  }
  exit(0);
}

function main() {
  const opts = parseArgs(process.argv);
  if (opts._sub === 'add') return cmdAdd(opts);
  if (opts._sub === 'classify') return cmdClassify(opts);
  return cmdList(opts);
}

// path.resolve() never follows symlinks, so invoking this script through a
// symlinked path (macOS TMPDIR under /var -> /private/var, or a vendored
// symlink) makes argv[1] differ from the module path and isMain silently
// false. Compare REALPATHS on both sides (follow-ups.mjs carries the same
// hardening for the same reason).
function realpathOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
const __filename = fileURLToPath(import.meta.url);
const isMain = process.argv[1] && realpathOrResolve(process.argv[1]) === realpathOrResolve(__filename);
if (isMain) runMain(() => main());

export {
  DEFAULT_LEDGER,
  ITEM_PREFIX,
  ID_MAX_LEN,
  BUCKETS,
  STRICT_VIOLATION_BUCKETS,
  readDecisionsLedger,
  foldAmendments,
  loadLedger,
  amendItemId,
  amendItemIdStamped,
};
