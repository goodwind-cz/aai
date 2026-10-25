// merge-outcomes.mjs — the outcome table of merge-cleanup.mjs and the pure helpers around it
// (docs/specs/SPEC-0252-spec-merge-cleanup-resolves-framework-friction.md, D1-D8).
// No I/O: the engine passes text and records in, this module returns objects and strings.
// Every reason the engine can emit is looked up in OUTCOME_TABLE; the engine never branches on prose.
// Node stdlib only (docs/TECHNOLOGY.md).

import crypto from 'node:crypto';

export const OUTCOME_PREFIX = 'OUTCOME ';
export const CLEANUP_WAITING = 'Cleanup: waiting for your decision on ';
export const MAX_AUTO_ATTEMPTS = 3;
export const DRAFT_LIFECYCLE_KEYS = ['number', 'number_reserved', 'status', 'links'];
export const GENERATED_PROJECTIONS = ['docs/ai/overview.html', 'docs/ai/overview-data.json', 'docs/ai/factory-report.html', 'docs/ai/factory-report-data.json'];

// ---- D1: four helpers (plus `resolved` for a condition settled inside the run) ------------------

const kept = (step) => ({ kind: 'kept', step });
const resolved = (step) => ({ kind: 'resolved', step });
const retry = (fallback) => ({ kind: 'retry', fallback });
const decide = (options, recommended) => ({ kind: 'decide', options, recommended });
const external = (action) => ({ kind: 'external', action });

const WORKTREE = { plan: kept('remove-worktree'), step: retry('decide') };

export const OUTCOME_TABLE = {
  no_direction: external('say /aai-merge with the PR yourself in this session'),
  not_open: external('reopen the PR on the platform or name another PR'),
  draft: external('mark the PR ready for review, then direct the merge again'),
  head_changed: decide(['direct_new_head', 'stop'], 'direct_new_head'),
  sweep_missing: external('the review sweep must be re-recorded for this head'),
  review_unresolved: external('the open review threads must be answered and resolved'),
  platform_mismatch: external('re-record the platform with node .aai/scripts/platform.mjs record --force'),
  platform_generic: external('do the manual step the platform adapter names'),
  gh_read_failed: retry('external'),
  az_read_failed: retry('external'),
  gh_read_invalid: external('check the GitHub CLI output for this PR'),
  az_read_invalid: external('check the Azure CLI output for this PR'),
  repo_mismatch: external('name a pull request of the repository the origin remote points at'),
  az_arg_unsafe: external('use a value without shell-special characters'),
  no_origin: external('run from a git checkout or pass --origin'),
  bad_base_name: external('fix the base branch name of the PR'),
  bad_head_name: external('fix the head branch name of the PR'),
  not_merged: external('merge the PR first (/aai-merge on the open PR)'),
  fetch_failed: retry('external'),
  merge_commit_not_on_base: retry('external'),
  origin_not_on_base: kept('sync-base'),
  base_diverged: kept('sync-base'),
  ledger_rewritten: kept('sync-base'),
  pending_unreadable: kept('sync-base'),
  pending_diverged: kept('sync-base'),
  overlap: decide(['keep_local', 'take_incoming'], 'keep_local'),
  overlap_staged: kept('sync-base'),
  untracked_not_file: kept('sync-base'),
  untracked_collision: decide(['take_incoming', 'keep_local'], 'take_incoming'),
  sync_failed: retry('decide'),
  ledger_merge_failed: retry('decide'),
  index_regen_failed: retry('decide'),
  worktree_missing: WORKTREE,
  cwd_inside_target: WORKTREE,
  worktree_dirty: { plan: kept('remove-worktree'), step: retry('decide') },
  tip_mismatch: WORKTREE,
  session_locked: WORKTREE,
  ledger_unaligned: WORKTREE,
  submodule_dirty: WORKTREE,
  submodule_unpushed: WORKTREE,
  submodule_stash: WORKTREE,
  submodule_no_remote: WORKTREE,
  submodule_unverifiable: WORKTREE,
  worktree_remove_failed: retry('decide'),
  branch_moved: retry('decide'),
  remote_bad_name: kept('delete-branch'),
  remote_fork: kept('delete-branch'),
  remote_unknown: kept('delete-branch'),
  remote_is_base: kept('delete-branch'),
  remote_moved: kept('delete-branch'),
  remote_has_dependents: kept('delete-branch'),
  remote_delete_rejected: kept('delete-branch'),
  reconcile_refused: kept('reconcile-origin'),
  reconcile_origin_failed: retry('decide'),
  sync_not_done: kept('reconcile-origin'),
  ledger_tails_wait_for_sync: kept('remove-worktree'),
  kept_with_worktree: kept('delete-branch'),
  superseded_draft: resolved('archive-drafts'),
  divergent_draft: decide(['keep', 'archive_remove'], 'keep'),
  archive_failed: retry('decide'),
};

const RETRY_ACTION = {
  gh_read_failed: 'check the GitHub CLI login and the network, then run the cleanup again',
  az_read_failed: 'check the Azure CLI login and the network, then run the cleanup again',
  fetch_failed: 'check that git fetch of the base branch works, then run the cleanup again',
  merge_commit_not_on_base: 'check that git fetch of the base branch works, then run the cleanup again',
};

const EFFECTS = {
  keep_local: 'the local file stays as it is and the base sync is left undone',
  take_incoming: 'the local file is archived, then replaced by the incoming one',
  keep: 'the draft stays as it is',
  archive_remove: 'the draft is archived, then removed',
  retry: 'run the step again now',
  skip_step: 'leave the step undone and finish the rest',
  direct_new_head: 'name the new head and run the preflight again',
  stop: 'end the run; nothing is merged',
};

const QUESTIONS = {
  overlap: (s, d) => `The local file ${s} also changed in the merge (${d}). Keep the local file and leave the base sync undone, or take the incoming file?`,
  untracked_collision: (s) => `The untracked file ${s} differs from the file the merge adds. Replace it with the incoming file (the local bytes are archived first), or keep it and leave the base sync undone?`,
  divergent_draft: (s) => `The untracked draft ${s} differs from its merged counterpart. Keep the draft, or archive it and remove it?`,
  head_changed: (s, d) => `The pull request head is not the judged head (${d}). Direct the merge of the new head, or stop?`,
};

// What a kept step leaves as it is, by the step that kept it.
export const STEP_OBJECT = {
  'sync-base': 'the main checkout', 'reconcile-origin': 'the origin STATE', 'remove-worktree': 'the worktree, its branch and its files',
  'delete-branch': 'the branch', 'archive-drafts': 'the draft',
};

export const outcomeId = (reason, subject, evidence = []) => {
  const h = crypto.createHash('sha256');
  for (const part of [reason, subject, ...evidence]) { h.update(String(part.length ?? 0)); h.update(':'); h.update(part); h.update('\n'); }
  return `${reason}@${h.digest('hex').slice(0, 12)}`;
};

const option = (id) => ({ id, effect: EFFECTS[id] });

// One outcome object (D8) for a reason. ctx: { phase: 'plan'|'step', subject, detail, evidence, retry: bool, pre: bool (preflight) }.
export function classify(reason, ctx = {}) {
  const entry = OUTCOME_TABLE[reason];
  if (!entry) throw new Error(`no outcome table entry for reason: ${reason}`);
  const phase = ctx.phase ?? 'step';
  let h = entry.plan ? entry[phase] : entry;
  const subject = String(ctx.subject ?? '');
  const detail = String(ctx.detail ?? '');
  if (h.kind === 'retry' && ctx.retry === false) {
    h = h.fallback === 'decide' ? decide(['retry', 'skip_step'], 'skip_step') : external(RETRY_ACTION[reason] ?? 'check the platform CLI login and network');
  }
  const o = { v: 1, id: outcomeId(reason, subject, ctx.evidence ?? []), class: 'auto', state: 'resolved', reason, subject, detail, options: [], recommended: null, question: '', action: '' };
  if (h.kind === 'retry') o.state = 'retry';
  else if (h.kind === 'decide') {
    o.class = 'decide'; o.state = 'pending'; o.options = h.options.map(option); o.recommended = h.recommended;
    o.question = (QUESTIONS[reason] ?? ((s, d) => `${reason} on ${s || 'this step'}${d ? ` (${d})` : ''}. Run the step again, or leave it undone and finish the rest?`))(subject, detail);
  } else if (h.kind === 'external') {
    o.class = 'external'; o.state = 'pending';
    o.action = h.action ?? RETRY_ACTION[reason] ?? 'see the detail';
    if (ctx.pre) o.action = o.action.replace('run the cleanup again', 'run the preflight again');
    if (detail) o.action += ` (${detail})`;
  }
  return o;
}

export const outcomeLine = (o) => `${OUTCOME_PREFIX}${JSON.stringify(o)}`;
export const parseOutcomeLine = (line) => (line.startsWith(OUTCOME_PREFIX) ? JSON.parse(line.slice(OUTCOME_PREFIX.length)) : null);

// ---- D7: bounded retries --------------------------------------------------------------------------

// records: the attempts.jsonl lines of earlier runs, oldest first ({ retries: [ids], fingerprint, reset? }).
export function nextAttempt(records, fingerprint) {
  let chain = 0;
  for (let i = records.length - 1; i >= 0; i--) {
    if (Array.isArray(records[i].retries) && records[i].retries.length > 0 && !records[i].reset) chain++; else break;
  }
  if (chain >= MAX_AUTO_ATTEMPTS - 1) return { retry: false, why: 'budget' };
  const last = chain > 0 ? records[records.length - 1] : null;
  if (last && last.fingerprint === fingerprint) return { retry: false, why: 'no_progress' };
  return { retry: true };
}

// ---- D8: the decision channel -----------------------------------------------------------------------

// The decision (recorded or given now) that names this outcome and one of its offered options.
export function choiceFor(o, decisions) {
  return decisions.find((d) => d.id === o.id && o.options.some((x) => x.id === d.option)) ?? null;
}

// A bare pair list `id=option,id=option`; null when any pair is malformed.
export function parseDecide(value) {
  const pairs = String(value).split(',').map((p) => p.match(/^([a-z_]+@[0-9a-f]{12})=([a-z_]+)$/));
  return pairs.length > 0 && pairs.every(Boolean) ? pairs.map((m) => ({ id: m[1], option: m[2], pair: m[0] })) : null;
}

// ---- D3: draft against its numbered counterpart -------------------------------------------------------

function frontmatterSplit(text) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---(\r?\n|$)/);
  return m ? { fm: m[1].split(/\r?\n/), rest: text.slice(m[0].length), head: m[0].length } : { fm: [], rest: text, head: 0 };
}

export const frontmatterId = (text) => frontmatterSplit(text).fm.map((l) => l.match(/^id:[ \t]*(\S.*?)\s*$/)).find(Boolean)?.[1] ?? null;

// The text with the lifecycle keys (and the indented children of a key) removed from its frontmatter.
export function withoutLifecycle(text) {
  const { fm, rest } = frontmatterSplit(text);
  const out = [];
  let skipping = false;
  for (const line of fm) {
    const key = line.match(/^([A-Za-z_][\w-]*):/)?.[1];
    if (key) skipping = DRAFT_LIFECYCLE_KEYS.includes(key);
    else if (!/^\s/.test(line) && !/^\s*-/.test(line)) skipping = false;
    if (!skipping) out.push(line);
  }
  return `${out.join('\n')}\n---\n${rest}`;
}

// false: another item (the frontmatter ids differ). Else 'superseded' when the draft text, with its stem
// replaced by the numbered stem, equals the numbered text once the lifecycle keys are removed from both,
// else 'divergent'. The comparison compares those two strings; it does not judge whether a difference matters.
export function compareDraft(draftText, numberedText, draftStem, numberedStem) {
  const fmDraft = { id: frontmatterId(draftText) };
  const fmNumbered = { id: frontmatterId(numberedText) };
  if (!fmDraft.id || fmDraft.id !== fmNumbered.id) return false;
  const a = withoutLifecycle(draftText.split(draftStem).join(numberedStem));
  return a === withoutLifecycle(numberedText) ? 'superseded' : 'divergent';
}

// ---- D4: roadmap entries ------------------------------------------------------------------------------

// Segments of a roadmap text: { key, pair, text } for each pair block and wave line, key null otherwise.
function roadmapSegments(text) {
  const lines = text.split(/(?<=\n)/);
  const segs = [];
  const seen = new Map();
  let section = '';
  for (let i = 0; i < lines.length; i++) {
    const body = lines[i].replace(/\r?\n$/, '');
    const top = body.match(/^([A-Za-z_][\w-]*):\s*$/);
    if (top) section = top[1];
    const cap = body.match(/^ {2}- capability: (.+)$/);
    const wave = !cap && body.match(/^ {2}- ([^:\s][^:]*)$/);
    const id = cap ? cap[1] : wave ? wave[1] : null;
    if (id === null) { segs.push({ key: null, text: lines[i] }); continue; }
    let block = lines[i];
    if (cap) while (i + 1 < lines.length && /^ {4}/.test(lines[i + 1])) block += lines[++i];
    const base = `${section}|${id}`;
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    segs.push({ key: n === 1 ? base : `${base}#${n}`, id, pair: !!cap, text: block });
  }
  return segs;
}

const entriesOf = (text) => new Map(roadmapSegments(text).filter((s) => s.key).map((s) => [s.key, s]));
const stripKeys = (text, keys) => roadmapSegments(text).filter((s) => !s.key || !keys.has(s.key)).map((s) => s.text).join('');

// The local change against the HEAD blob is represented when it stays inside entries and every changed entry
// is the incoming entry, a merged ref the incoming roadmap carries as a pair block, or a wave line of a merged ref.
// refs: ids of merged work items; unproven: ids of docs the merge changed whose identity is not proven.
export function representedChanges({ local, head, incoming, refs, unproven = new Set() }) {
  const L = entriesOf(local); const H = entriesOf(head); const I = entriesOf(incoming);
  const K = new Set([...L.keys(), ...H.keys()].filter((k) => L.get(k)?.text !== H.get(k)?.text));
  const bad = [];
  if (stripKeys(local, K) !== stripKeys(head, K)) bad.push('(change outside the entries)');
  for (const key of [...K].sort()) {
    const localEntry = L.get(key)?.text;
    const incomingEntry = I.get(key)?.text;
    if (localEntry === incomingEntry) continue;
    const id = (L.get(key) ?? H.get(key)).id;
    const pairInIncoming = I.get(key)?.pair === true;
    const waveRemoved = !L.has(key) && H.get(key)?.pair === false;
    if (refs.has(id) && (pairInIncoming || waveRemoved)) continue;
    bad.push(unproven.has(id) ? `unproven ${id}` : key.split('|')[1]);
  }
  return { represented: bad.length === 0, unrepresented: bad };
}

// ---- D8: the plain-language lines ------------------------------------------------------------------------

export const keptLine = (o, step) => `Kept: ${STEP_OBJECT[step] ?? 'the item'} stays as it is (${o.reason}${o.subject ? ` ${o.subject}` : ''}${o.detail && o.detail !== o.subject ? `: ${o.detail}` : ''})`;
export const decisionLine = (o) => `Decision: ${o.question} Options: ${o.options.map((x) => `${x.id}${x.id === o.recommended ? ' (recommended)' : ''} - ${x.effect}`).join('; ')}. id: ${o.id}`;
export const needsLine = (o) => `Needs you: ${o.action}`;

// s: { pr, mc, kind, kept: [line], pending: [outcome], needs: [outcome], step }
// kind: complete | refused | interrupted_retry | interrupted_decision. Returns { lines, summary }.
export function summaryLines(s) {
  const k = s.kept.length; const d = s.pending.length;
  let cleanup;
  if (s.kind === 'refused' || s.kind === 'planned') cleanup = 'Cleanup: not started; nothing was changed.';
  else if (s.kind === 'interrupted_retry') cleanup = `Cleanup: interrupted at ${s.step}; retrying.`;
  else if (s.kind === 'interrupted_decision') cleanup = `Cleanup: interrupted at ${s.step}; waiting for your decision.`;
  else if (d > 0) cleanup = `${CLEANUP_WAITING}${d} item(s); everything else is done.`;
  else cleanup = k > 0 ? `Cleanup: complete; kept ${k} item(s), nothing needs you.` : 'Cleanup: complete.';
  const lines = [s.mc ? `Merge: PR #${s.pr} is merged as ${String(s.mc).slice(0, 12)}.` : 'Merge: not done.', ...(s.noCleanup ? [] : [cleanup]),
    ...s.kept, ...s.pending.map(decisionLine), ...s.needs.map((o) => needsLine(o))];
  const kind = s.kind === 'complete' ? (d > 0 ? 'decision_pending' : k > 0 ? 'complete_kept' : 'complete') : s.kind;
  return { lines, summary: { kind, kept: k, decisions: d, needs_you: s.needs.length } };
}
