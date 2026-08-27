---
name: aai-overview
description: Use when the user wants a plain-language project overview — what the factory has delivered, what is in progress, and what waits on a human decision — rendered as a self-contained HTML page with links to specs and evidence.
---

Run `node .aai/scripts/generate-overview.mjs` from the project root, then tell the user where the outputs landed (`docs/ai/overview.html`, `docs/ai/overview-data.json`) and offer to open or publish the page (e.g. via `/aai-share`).

The script is read-only over project docs and telemetry; it writes only the two output files. If it does not exist, say: "generate-overview.mjs not found — are you in an AAI project? Expected: .aai/scripts/generate-overview.mjs"
