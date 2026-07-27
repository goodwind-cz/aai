// lib/product-doc.mjs — shared predicate over docs/product/<slug>.md product
// artifacts (D2, spec-product-docs-enforced). ONE identity, ONE placeholder
// rule (SEAM 3): consumed by close-work-item.mjs (the pre-write gate, core)
// AND generate-userguide-rollup.mjs (the rollup generator, extended). Classified
// core (PROFILES.yaml) because a core script (close-work-item.mjs) imports it —
// a core-only sync must never lose a dependency of a core script.
//
// Required sections mirror .aai/templates/PRODUCT_TEMPLATE.md's trio (the
// original operator-assignment gap: functional description, data model,
// interfaces): exact level-2 heading text, matched verbatim.
//
// Non-placeholder predicate (D2): take the body between a section heading and
// the next level-2 heading (or EOF); strip HTML comments and blank lines; the
// section is a PLACEHOLDER (== missing) when the remaining body is empty OR
// consists solely of unfilled template angle-bracket tokens (a line matching
// /^<[^>]*>$/). The literal "None." is REAL content (PRODUCT_TEMPLATE's explicit
// positive-empty marker) — it must PASS.

export const REQUIRED_PRODUCT_SECTIONS = ['What it does', 'Data model', 'Interfaces and contracts'];

// extractSection(content, heading) -> the raw body between the exact `## <heading>`
// line and the next `## ` heading (or EOF), or null when the heading is absent.
export function extractSection(content, heading) {
  const norm = String(content).replace(/\r\n?/g, '\n');
  const escaped = String(heading).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`^##[ \\t]+${escaped}[ \\t]*$`, 'm');
  const m = re.exec(norm);
  if (!m) return null;
  const rest = norm.slice(m.index + m[0].length);
  const next = rest.search(/^##[ \t]+/m);
  return next === -1 ? rest : rest.slice(0, next);
}

// sectionIsPlaceholder(body) -> true when `body` (from extractSection, or null
// for an absent heading) counts as missing under the D2 predicate above.
//
// Non-blank lines are joined with a single space before the angle-bracket
// test — PRODUCT_TEMPLATE.md's own placeholder tokens are hand-wrapped across
// multiple physical lines (e.g. the Data model token), so a strict per-line
// `^<.*>$` match would miss them; joining reconstructs the single logical
// token the template intends before testing.
export function sectionIsPlaceholder(body) {
  if (body == null) return true;
  const stripped = body
    .replace(/<!--[\s\S]*?-->/g, '')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  if (stripped.length === 0) return true;
  return /^<[^>]*>$/.test(stripped.join(' '));
}

// missingProductSections(content) -> the subset of REQUIRED_PRODUCT_SECTIONS
// that are absent or placeholder. Empty array == a REAL product doc (D2).
export function missingProductSections(content) {
  return REQUIRED_PRODUCT_SECTIONS.filter((h) => sectionIsPlaceholder(extractSection(content, h)));
}
