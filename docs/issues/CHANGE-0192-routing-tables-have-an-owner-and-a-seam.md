---
id: routing-tables-have-an-owner-and-a-seam
type: change
number: 192
status: draft
links:
  pr: []
  commits: []
---

# The routing and pricing tables have a keeper, and a consumer's exception has somewhere to live

## Summary
- `.aai/system/MODEL_ROUTING.yaml` binds tier to model id; `.aai/system/PRICING.yaml`
  prices those ids. The routing file's own comment calls this "the single largest
  lever on autonomous-run cost" and requires the two files to be updated together.
- Both are core-vendored, so `/aai-update` overwrites a consumer's copy. That is
  CORRECT and this change does not propose to stop it: the tables track a moving
  external world (new models, changed prices) and a consumer will not track it
  for us. Owner decision, 2026-09-24.
- Two things follow from that being correct, and neither exists today.
  1. **Nobody keeps them current, and nothing notices when they are stale.**
     Measured at f84f84ab: `PRICING.yaml` carries no `as_of`, `last_reviewed` or
     any other freshness marker; `grep -rn "stale|last_reviewed|as_of"` over it
     returns nothing. Three scripts (`metrics-flush.mjs`, `metrics-report.mjs`,
     `orchestration-dispatch.mjs`) read it and none can tell fresh data from a
     year-old copy. Keeping it current is today an act of memory.
  2. **A consumer's exception has nowhere to live.** The only file they can edit
     to pin a role cheaper, override a tier or cap cost is the one we overwrite.
     The routing file's UPGRADING note tells them to re-apply the customization
     after every update — the defect handed to the user as a procedure.
- Filed as its own scope rather than bent into `update-installs-ref-guard-undisclosed`
  (sweep 5), which found the symptom as `fu-routing-file-overwritten-on-update`.
  That item is re-dispositioned by this intake: the fix is not "preserve the
  consumer's edit" but "the exception belongs somewhere we never overwrite".

## Motivation / Business Value
- Cost. Routing roughly 70% of mechanical calls away from frontier models is the
  factory's largest cost lever, and a stale table silently stops pulling it —
  a retired model id, a changed price, a new cheaper tier nobody bound.
- Trust. A consumer who customizes and loses it on update learns that our update
  is unsafe for their configuration. They then either stop updating or stop
  customizing; both are worse for them than a seam would be.
- Honesty. The current arrangement documents its own defect in a code comment
  and assigns the recurring work to the user.

## Scope
- In scope: a freshness contract for the two tables (what "current" means, how it
  is recorded, what notices when it lapses, and who acts); a consumer-owned
  configuration seam that `/aai-update` never overwrites, with the routing
  override as its first tenant; re-disposition of
  `fu-routing-file-overwritten-on-update`.
- Out of scope: choosing the models or prices themselves; a pricing API
  integration; changing how `orchestration-dispatch` resolves a tier.
- Explicitly open for Planning to split: the keeper half and the seam half are
  one problem seen from two ends and may well be a capability plus its
  maintenance half rather than one ride.

## Affected Area
- `.aai/system/MODEL_ROUTING.yaml`, `.aai/system/PRICING.yaml`,
  `.aai/system/PROFILES.yaml` (the `core:` list that makes them overwritten),
  `.aai/scripts/aai-sync.sh` and its `.ps1` twin, `.aai/scripts/aai-doctor.mjs`
  (a staleness category is the obvious notifier), and whatever reads the new
  consumer config.

## Desired Behavior (To-Be)
- The tables carry a machine-readable freshness marker, and something a project
  runs anyway reports when it has lapsed — a consumer should learn from a tool,
  not from a wrong invoice.
- A consumer can express a routing exception in a file `/aai-update` never
  touches, and that exception survives an update without being re-applied.
- The shipped tables keep being overwritten, and that is stated as intended
  rather than apologized for in a comment.
- A consumer who has expressed no exception is unaffected in every respect.

## Acceptance Criteria
- AC-001: the freshness marker exists in both tables and a tool reports a lapse
  against a configurable horizon, naming the file and the date it carries.
- AC-002: a consumer configuration file exists that `/aai-update` provably does
  not overwrite, demonstrated by an update run over a customized target.
- AC-003: a routing exception expressed there changes the resolved model for the
  role it names, and its absence changes nothing.
- AC-004: the routing file's UPGRADING note no longer instructs the reader to
  re-apply customizations after every update, because they no longer need to.

## Verification
- An update run against a target carrying both a customized shipped table and a
  consumer config: the shipped table is replaced, the consumer config is not.
- A table stamped older than the horizon produces the lapse report; a fresh one
  produces none; a table with a malformed marker fails closed (reports) rather
  than silently passing.
- `orchestration-dispatch.mjs` resolves the overridden role to the overridden
  model and every other role unchanged.

## Constraints / Risks
- The seam must not become a second routing table. An override that can express
  anything the shipped file can will drift into a fork, and then the consumer
  is back to maintaining it. Narrow is the point.
- A freshness marker that only a human updates is the same defect one level up:
  whatever stamps it should be part of the act of changing the table, not a
  separate discipline to remember.
- Prices and model ids change without notice from outside; the contract should
  make lapse VISIBLE, and must not claim to make it impossible.

## Notes
- Owner framing, 2026-09-24: "udržovat tu tabulku aktuální s novými modely a
  změnami cen uživatelé dělat nebudou, na to musí být nějaký pravidelný proces
  centrálně; přepisování uživatelem může být spíš nějaký výjimečný proces někam
  do centrálního jeho konfigu, který by stejně měl vzniknout."
- Measurements in this intake were taken at f84f84ab and are re-measurable; do
  not inherit them on trust at Planning.
