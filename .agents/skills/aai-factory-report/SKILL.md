---
name: aai-factory-report
description: Use when the user wants a continuous factory-efficiency overview — what the AAI factory delivers, how fast, at what token cost, and at what quality, trended over time — rendered as a self-contained HTML page from the METRICS and EVENTS ledgers.
---

Run `node .aai/scripts/generate-factory-report.mjs` from the project root, then tell the user where the outputs landed (`docs/ai/factory-report.html`, `docs/ai/factory-report-data.json`) and offer to open or publish the page (e.g. via `/aai-share`).

The report has four dimensions, each with an overall value and a per-ISO-week trend series: throughput (delivered per week and per release, lead time), speed (per-ride busy time and per-role split), cost (undecomposed tokens only — never a USD figure), and quality (first-pass-clean rate, remediation distribution, verdict mix). Numbers that are not honestly derivable from the ledgers stay visibly `n/a` — never imputed.

The script is read-only over `docs/ai/METRICS.jsonl`, `docs/ai/EVENTS.jsonl`, and `docs/releases/*.md`; it writes only the two output files and needs no network. It also refreshes automatically at every successful close (best-effort, wired into `close-work-item.mjs`). If it does not exist, say: "generate-factory-report.mjs not found — are you in an AAI project? Expected: .aai/scripts/generate-factory-report.mjs"
