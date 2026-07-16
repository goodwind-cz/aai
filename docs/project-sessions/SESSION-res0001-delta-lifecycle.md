# RES-0001 + delta-spec lifecycle

- Session ID: `res0001-delta-lifecycle`
- Status: `active`
- Language: `cs`
- Created: `2026-07-17`
- Last Updated: `2026-07-17`

## Purpose

Trvalý lidsky čitelný záznam vícevlnové dodávky, kdy jsme AAI framework
vylepšovali jeho vlastním pipeline (intake → frozen SPEC → implementace →
nezávislá validace → dual-verdict review → PR ceremony → operator merge).
Zachycuje, co bylo dodáno, klíčová rozhodnutí a — hlavně — procesní poučení,
protože metriky jednotlivých scope se u worktree-izolovaných úloh nedají zpětně
zrekonstruovat (viz níže).

## Current Framing

Kompletně dodáno a zmergováno:
- **RES-0001** (P1 + P2 + P3) — všechny tiery doporučení z výzkumu.
- **RFC-0011 delta-spec lifecycle** — všechny tři stage.

`main` je čistý, přísný docs-audit CLEAN, žádné držené locky, worktrees/branch
uklizené. Zbývá jen volitelný wrap-up a onboarding druhého projektu.

## Decision Trail

- `2026-07-16`: **Owner-directed merge** — vlastník opakovaně pověřil Claude, aby
  sám prováděl `gh pr merge` v rámci autonomní dodávky ("pokracuj plne autonome
  a vyres vse"). Zaznamenáno v `docs/ai/decisions.jsonl` (Article 7 owner
  prerogative) a v paměti `merge-authorization-owner-override`.
- `2026-07-16`: **L1 close gate (poslední P3 lock, PR #85)** — SPEC-0036/
  CHANGE-0024. Kořenová příčina hlubší než původní nález: první živý L1 spec
  (SPEC-0032) odhalil, že lean close-gate mlčky zahazoval řádky s literal pipe →
  falešný GATE PASS. Vyřešeno tím, že `parseLeanAcTable` vrací `declaredIds`
  (jeden zdroj pravdy) a gate i drift-check se smiřují declared-vs-parsed.
- `2026-07-16`: **PROFILES.yaml drift + TEST-002 baseline (PR #86)** — pět
  vendored souborů nebylo klasifikováno (100% invariant), a `test-aai-layer-
  profiles.sh` TEST-002 byl rozbitý by-construction po mergi #84 (pre-change
  engine se bral z `HEAD`). Baseline přepnut na rodiče commitu, který zavedl
  profily (odvozeno přes `git log --reverse -S PROFILES.yaml`).
- `2026-07-16`: **Volba "delta stage 2 & 3"** — uživatel z menu vybral pokračování
  delta lifecycle jako další směr.
- `2026-07-16`: **Delta stage 2 (PR #87)** — SPEC-0037/CHANGE-0025. Producent:
  volitelná SPEC sekce `## Deltas` (ADDED/MODIFIED/REMOVED) + spec-lint shape
  validace; sdílený reader `parseDeltasSection`. Review odhalil past: šablona
  vozí příklad v HTML komentáři → `parseDeltasSection` bez strippingu komentářů
  parsoval fantomové delty (mina pro stage 3). Opraveno `stripHtmlComments`.
- `2026-07-16..17`: **Delta stage 3 (PR #88)** — SPEC-0038/CHANGE-0026. Konzument:
  `delta-merge.mjs` aplikuje delty do `docs/canonical/` v PR ceremony
  (fail-closed, byte-idempotentní, line-surgical), docs-audit provenance drift
  check, vyřešeno NB-1. **Nezávislá validace (jiný model) tento scope nejdřív
  FAILNULA**: tombstone REMOVED se při re-renderu sousedního MODIFIED bloku mlčky
  smazal → nekonzistentní idempotence a **reuse retired NNN**. Remediováno
  (tombstony jsou samostatné keep-verbatim elementy) + 3 nové regresní testy,
  re-validováno přímým spuštěním přes adversariální tvary.

## Working Assumptions

- `docs/canonical/` je v tomto repu prázdný → delta-merge i drift jsou zde no-op;
  engine je fixture-tested a připravený pro projekt s canonical vrstvou.
- Merge trigger = PR ceremony; REQ id = per-domain sekvenční (`REQ-<DOMAIN>-NNN`)
  — rozhodnuto v RFC-0011.
- Taxonomy guard zakazuje tokeny `stage N` na `.aai` površích; odkazuje se na
  "RFC-0011 (delta-spec lifecycle)" obsahem.

## Open Questions / Risks

- **Metriky per-scope pro tuto session jsou nevratné.** L1-close-gate, delta-2 a
  delta-3 běžely v subagentových worktrees; STATE.yaml je gitignored a žil ve
  worktree, který byl po mergi odstraněn (`git worktree remove`) → jeho metriky
  nebyly flushnuté do `docs/ai/METRICS.jsonl` a jsou pryč. Rekonstrukce by byla
  fabrikace dat (porušení truth-scoring principu, SPEC-0032). **Procesní
  poučení:** flush metrik (nebo archivace STATE) MUSÍ proběhnout PŘED
  `git worktree remove`.
- Delta lifecycle je ověřený jen fixture-based; první reálné použití (canonical
  doména + spec s `## Deltas`) ho teprve prověří naostro.

## Related Formal Artifacts

- `existing`: `docs/rfc/RFC-0011-delta-spec-lifecycle.md`
- `existing`: `docs/specs/SPEC-0034-spec-delta-stage-1.md`, `SPEC-0037-…`, `SPEC-0038-…`
- `existing`: `.aai/scripts/delta-merge.mjs`, `.aai/scripts/lib/docs-model.mjs`
- `existing`: `CHANGELOG.md` (položky CHANGE-0024/0025/0026)
- `existing`: `docs/ai/decisions.jsonl` (owner-directed merge záznamy)
- `needed`: LEARNED zápis o pořadí flush-před-worktree-remove (procesní poučení)

## Next Resume Point

Na výběr (uživateli otevřeno): (a) onboarding druhého projektu — `/aai-update`
+ přejmenování mis-numbered PRD (potřebuje cestu k projektu); (b) nový výzkum
`/aai-intake` pro další tier; (c) ostré vyzkoušení delta vrstvy (docs-canon →
spec s `## Deltas` → delta-merge). Metriky pro budoucí scope flushovat před
odstraněním worktree.

## Change Log

- `2026-07-17`: session vytvořena při wrap-upu — zachycen RES-0001 tail, celý
  delta lifecycle (#87/#88), closeout hygiena (#86) a procesní poučení o
  nevratných metrikách worktree-izolovaných scope.
