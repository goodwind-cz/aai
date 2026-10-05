// roadmap-model.mjs — the ONE parser of docs/ai/roadmap.yaml (SPEC
// roadmap-serves-downstream-projects D2). Moved verbatim from ride-select.mjs
// and shared with roadmap-edit.mjs, so the reader and the writer's certifier
// never drift on what a valid roadmap is.
//
// D1: the maintenance budget is OPT-IN. A roadmap with NO top-level `budget:`
// key is valid (rm.budget === null); a `budget:` block that is present must
// still carry exactly `maintenance_per_capability: 1`.

import fs from 'node:fs';

// A ref is a slug id OR a numbered display id (CHANGE-0042, RFC-0012): 36 docs carry the latter.
export const SLUG = /^(?:[a-z0-9][a-z0-9-]{1,79}|[A-Z]{2,10}-\d{4})$/;
export const MAINT_TYPES = new Set(['issue', 'hotfix', 'techdebt', 'chore', 'test', 'ci']);
// D1 (spec-roadmap-maintenance-budget-advisory): a maintenance_threshold value
// must be a bare positive integer — no quotes, no leading zero, no decimal,
// no sign, no trailing text or inline comment.
const THRESHOLD_RE = /^[1-9]\d*$/;

// Posture probe (Codex P1, PR #416): `fs.existsSync` returns false for EVERY
// stat failure, including EACCES on an unsearchable parent directory — a
// governed project would read as ungoverned. Only a not-found error selects
// the absent posture; any other failure is a present-but-unreadable roadmap
// and falls through to loadRoadmap()'s refusal. Twin of the same-named
// function in orchestration-dispatch.mjs (seam S1, TEST-1207).
export const ABSENT_CODES = new Set(['ENOENT', 'ENOTDIR']);
export function roadmapAbsent(p) {
  try { fs.statSync(p); return false; } catch (e) { return ABSENT_CODES.has(e && e.code); }
}

// --- roadmap: closed shape, line-level ------------------------------------------
export function loadRoadmap(p) {
  let text;
  try { text = fs.readFileSync(p, 'utf8'); } catch { return { error: `roadmap not readable: ${p}` }; }
  const lines = text.replace(/\r\n?/g, '\n').split('\n').filter((l) => !/^\s*#/.test(l) && l.trim() !== '');
  const rm = { budget: null, advisory: null, pairs: [], wave_2: [] };
  let section = null; let cur = null; const seenSections = new Set();
  // D1: the advisory posture's two lines, either order — raw (trimmed, not
  // comment-stripped) values, so an inline comment or quoting fails the
  // shape check below rather than being silently tolerated.
  let bmode = null; let bthr = null;
  for (const line of lines) {
    let m;
    if ((m = /^([a-z_0-9]+):\s*$/.exec(line))) {
      section = m[1]; cur = null;
      if (!['budget', 'pairs', 'wave_2'].includes(section)) return { error: `unknown top-level key "${section}"` };
      if (seenSections.has(section)) return { error: `top-level key "${section}" appears twice` };
      seenSections.add(section); continue;
    }
    if (section === 'budget' && (m = /^  maintenance_per_capability:\s*(\d+)\s*$/.exec(line))) { if (rm.budget) return { error: 'budget.maintenance_per_capability appears twice' }; rm.budget = { maintenance_per_capability: Number(m[1]) }; continue; }
    if (section === 'budget' && (m = /^  mode:\s*(.*)$/.exec(line))) { if (bmode !== null) return { error: 'budget.mode appears twice' }; bmode = m[1].trim(); continue; }
    if (section === 'budget' && (m = /^  maintenance_threshold:\s*(.*)$/.exec(line))) { if (bthr !== null) return { error: 'budget.maintenance_threshold appears twice' }; bthr = m[1].trim(); continue; }
    if (section === 'pairs' && (m = /^  - capability:\s*(.+?)\s*$/.exec(line))) { cur = { capability: m[1], maintenance: null, status: null }; rm.pairs.push(cur); continue; }
    if (section === 'pairs' && cur && (m = /^    maintenance:\s*(.+?)\s*$/.exec(line))) { if (cur.maintenance !== null) return { error: `pair ${rm.pairs.length}: "maintenance" appears twice (last-wins would hide a second maintenance ref)` }; cur.maintenance = m[1]; continue; }
    if (section === 'pairs' && cur && (m = /^    status:\s*(planned|active|done)\s*$/.exec(line))) { if (cur.status !== null) return { error: `pair ${rm.pairs.length}: "status" appears twice` }; cur.status = m[1]; continue; }
    if (section === 'wave_2' && (m = /^  - (.+?)\s*$/.exec(line))) { rm.wave_2.push(m[1]); continue; }
    return { error: `line does not fit the closed roadmap shape: "${line.trim()}"` };
  }
  // D1: no `budget:` key = no maintenance budget (legal, off). A PRESENT
  // block is EITHER the 1:1 "on" form (exactly maintenance_per_capability: 1)
  // OR the advisory form (exactly mode: advisory + a positive-integer
  // maintenance_threshold, either line order) — never both, never a partial
  // advisory shape, never an unrecognized value. D2: rm.budget keeps meaning
  // "the 1:1 budget is on" and stays null in advisory; rm.advisory is the
  // advisory shape or null.
  const budgetDeclared = seenSections.has('budget');
  if (budgetDeclared) {
    if (rm.budget && (bmode !== null || bthr !== null)) return { error: 'budget: mode/maintenance_threshold cannot be combined with maintenance_per_capability' };
    if (!rm.budget && bmode === null && bthr === null) return { error: 'budget: block present but maintenance_per_capability is missing' };
    if (!rm.budget && bmode !== 'advisory') return { error: `budget.mode must be the bare word "advisory", got ${JSON.stringify(bmode)}` };
    if (!rm.budget && !THRESHOLD_RE.test(bthr ?? '')) return { error: `budget.maintenance_threshold must match ^[1-9][0-9]*$, got ${JSON.stringify(bthr ?? null)}` };
    if (rm.budget && rm.budget.maintenance_per_capability !== 1) return { error: `budget.maintenance_per_capability must be 1 (owner decision), got ${rm.budget.maintenance_per_capability}` };
    if (!rm.budget) rm.advisory = { maintenance_threshold: Number(bthr) };
  }
  rm.posture = rm.budget ? 'on' : (rm.advisory ? 'advisory' : 'off');
  if (!rm.pairs.length) return { error: 'no pairs' };
  const seen = new Set();
  for (const [i, pr] of rm.pairs.entries()) {
    const n = i + 1;
    // Spec-AC-01/D2: `maintenance` is now OPTIONAL — a pair with no
    // `maintenance:` line is a capability whose maintenance slot is UNBOUND
    // (null), not a malformed pair. `status` stays required.
    if (!pr.status) return { error: `pair ${n} (${pr.capability}) is missing status` };
    // Same-ref before the duplicate scan, or a pair naming one ref twice would be
    // reported as "appears twice" — true, but not the reason that matters.
    if (pr.maintenance !== null && pr.capability === pr.maintenance) return { error: `pair ${n}: capability and maintenance are the same ref "${pr.capability}"` };
    for (const r of [pr.capability, pr.maintenance]) {
      if (r === null) continue; // unbound maintenance slot — nothing to validate yet
      if (!SLUG.test(r)) return { error: `pair ${n}: "${r}" is neither a slug id nor a numbered display id` };
      if (seen.has(r)) return { error: `pair ${n}: "${r}" appears twice in the roadmap` };
      seen.add(r);
    }
  }
  for (const r of rm.wave_2) {
    if (!SLUG.test(r)) return { error: `wave_2: "${r}" is neither a slug id nor a numbered display id` };
    if (seen.has(r)) return { error: `wave_2: "${r}" appears twice in the roadmap` };
    seen.add(r);
  }
  return { roadmap: rm };
}
