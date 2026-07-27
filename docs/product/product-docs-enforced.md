---
id: product-docs-enforced
type: product
status: current
spec: docs/specs/SPEC-0092-spec-product-docs-enforced.md
updated: 2026-07-27
---

# Product docs enforced at close, plus a generated USER_GUIDE rollup

## What it does

Closing a user-facing work item now carries a real check: if the primary
request doc opts in with `user_visible: true` and the matching
docs/product/&lt;ref&gt;.md is missing or still has unfilled template sections,
the close ceremony prints a loud warning by default, or refuses outright
(nothing written) when the stricter dial is turned on. Separately,
docs/USER_GUIDE.md now carries a "Delivered features (generated)" section
that is rebuilt automatically every time a work item closes, listing every
real product doc with a link and a one-paragraph summary — so the user guide
can no longer silently drift out of date the way it used to.

## How to use it

Set `user_visible: true` on a change/issue/prd's frontmatter to opt that
scope into the check. Write its product doc at `docs/product/<id>.md` (use
`.aai/templates/PRODUCT_TEMPLATE.md`) with every required section filled in —
an explicit "None." is fine, an empty or `<placeholder>` section is not.
Control strictness in `docs/ai/docs-audit.yaml`:

```yaml
product_doc_gate: report-only   # default: warn only, close still proceeds
product_doc_gate: enforce       # refuse the close until the doc is real
```

To refresh the USER_GUIDE section by hand (it also runs automatically at
close):

```bash
node .aai/scripts/generate-userguide-rollup.mjs
```

## Data model

No new persistent records. Two existing surfaces gain optional/additive
fields: the primary work-item doc's frontmatter gains an optional
`user_visible: true|false` key (absent = not gated, safe for every
pre-existing doc); `docs/ai/docs-audit.yaml` gains a `product_doc_gate:
enforce|report-only` key next to the existing `close_gate` dial.

## Interfaces and contracts

- `node .aai/scripts/close-work-item.mjs ...` — new exit code `3`: the
  product-doc gate refused the close (enforce dial, nothing written,
  pre-write only — never a rollback path). Exit codes `0`/`1`/`2` are
  unchanged; a `report-only` warning still exits `0`.
- `node .aai/scripts/generate-userguide-rollup.mjs [--output <path>]` — new
  CLI. Rewrites only the region between the
  `<!-- AAI:USERGUIDE-ROLLUP:BEGIN ... -->` / `<!-- AAI:USERGUIDE-ROLLUP:END
  -->` markers in docs/USER_GUIDE.md (default target); every other byte in
  the file is untouched. Idempotent: re-running with unchanged product docs
  produces a byte-identical file (no timestamps are written into the marked
  region).
- `docs/ai/docs-audit.yaml` key `product_doc_gate: enforce|report-only`
  (default report-only when absent).

## Limits and non-goals

Legacy items (the ~106 pre-convention deliveries) are never retroactively
gated — the key is opt-in and absent means unaffected. This does not
generate or draft product-doc prose; it only checks presence/completeness
and renders what already exists. INTERFACES.md extraction automation is out
of scope (future work).

## Links

- Request: docs/issues/CHANGE-0066-product-docs-enforced.md
- Spec: docs/specs/SPEC-0092-spec-product-docs-enforced.md
- Validation evidence: docs/ai/tdd/green-20260727T073736Z-close-work-item.log, docs/ai/tdd/green-20260727T073142Z-userguide-rollup.log, docs/ai/tdd/green-20260727T073824Z-layer-profiles.log
