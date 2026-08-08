# Blume (blume.codes) a alternativy — analýza pro AAI live dashboard

Datum: 2026-08-07. Podklad pro CHANGE-0127 (optional zero-LLM live dashboard).
Zdroje: web blume.codes (vč. inspekce app.asar v1.0.60), GitHub/weby nástrojů
níže. Dva nezávislé research passy (produkt + landscape).

## 1) Blume Sidecar — co to skutečně je

- Electron desktop app (mac/win/linux, ~174 MB DMG), Blume Corporation
  (Oslo/Toronto, zakladatelé Peder Aaby a Olav Ljosland, ex-Wordware YC S24).
  Verze 1.0.60 (2026-08-07) — čerstvý produkt, jeden blogpost, žádný HN/PH
  launch, žádné nezávislé recenze. Zdarma "zatím", closed source,
  account-gated (invite systém).
- Sleduje agenty čtením jejich session transkriptů přímo z disku:
  Claude Code (`~/.claude/projects/**/*.jsonl`), Codex (`~/.codex/...`),
  Pi (`~/.pi/agent/sessions`), omp (`~/.omp/agent/sessions`),
  Cursor (SQLite `state.vscdb`). Chokidar + mtime/size polling; stav
  running / idle / needs-approval odvozuje z růstu transkriptu.
- Kvóty: čte OAuth tokeny agentů (Claude Code z macOS Keychain — uživatel
  musí Blume přidat do Keychain ACL!) a volá `api.anthropic.com/api/oauth/usage`
  resp. `chatgpt.com/backend-api/wham/usage` — autoritativní 5h + týdenní
  okna (usedPercent, resetsAt).
- "Suggested improvements": lokální clustering korekcí/frustrace v chatech,
  ale GENERACE návrhů jde na Blume cloud proxy (Cloudflare Worker
  zakladatele, OpenAI-style endpoint, HMAC) — tzn. výňatky konverzací
  opouštějí stroj. Marketing "on-device" platí jen pro detekci.
- Telemetrie: PostHog, GA, Meta Pixel.

Verdikt pro AAI: nenasazovat. Closed source, čte celou konverzační historii,
chce Keychain přístup k OAuth tokenu, posílá výňatky do vlastního cloudu.
Fabrika stojí na kontrole v repu a CI. ALE architektura je poučná (níže).

## 2) Landscape alternativ (vše kromě dvou je OSS, zero-LLM-token)

| Nástroj | Co | Zdroj dat | Licence | Stav |
|---|---|---|---|---|
| ccusage | CLI token/cost reporty, multi-agent | session JSONL, dedup message.id+requestId, ceny LiteLLM | MIT | velmi aktivní |
| claude-monitor | realtime quota monitor, burn-rate | JSONL + HARDCODED odhady limitů (migrace na OAuth API, issue #202) | MIT | aktivní |
| sniffly | localhost web dashboard nad logy | JSONL | MIT | aktivní |
| opcode (ex-claudia) | GUI + usage analytics | JSONL → lokální SQLite | AGPL-3.0 | aktivní, 22k★ |
| claude-code-templates | analytics dashboard + live session detection | JSONL watch + process detection | MIT | aktivní, 30k★ |
| claude-powerline | statusline s oficiálními kvótami | statusline stdin JSON (rate_limits) | MIT | aktivní |
| Crystal→Nimbalyst, Conductor, Vibe Kanban, Claude Squad, cmux | session/worktree manažeři (PTY wrapping) | vlastní spawn agentů | mix; VK sunsetting | různé |
| Omnara | mobile/web control plane | wrapper/SDK relay | Apache-2.0 | pivotoval |
| OTel stacky (claude-code-otel aj.) | Grafana/Prometheus | nativní OTel export Claude Code | OSS | aktivní |
| GitHub Agent HQ | hosted fleet orchestrace | GitHub runners | proprietární | GA 2026 |

Pozn.: Claude Code sám už má `/usage` a `/stats` — část sidecar prostoru
absorbuje upstream.

## 3) Mechanismy použitelné pro deterministický zero-token dashboard

1. **Session JSONL parsing** (ccusage vzor): glob `~/.claude/projects/**/*.jsonl`
   (+ `CLAUDE_CONFIG_DIR`), stream, dedup `message.id`+`requestId`, agregace
   per den/projekt/model. Ověřeno lokálně: usage bloky (input/output/cache)
   jsou v každé assistant zprávě. Korpus ~484 MB → inkrementálně (mtime cut).
2. **Statusline tap** (claude-powerline vzor): Claude Code předává statusline
   skriptu na stdin JSON se SERVER-AUTORITATIVNÍMI
   `rate_limits.five_hour/seven_day.used_percentage` + `resets_at` + cost +
   context %. Malý skript to appenduje do lokálního spoolu; dashboard čte
   spool. Oficiální kvóty BEZ sítě v generátoru a BEZ odhadů limitů.
3. **Hooks liveness** (Stop/Notification/PostToolUse → spool): stav
   running / waiting-on-approval / finished bez PTY wrappingu.
4. Nepoužít: OAuth usage API (nedokumentované, network, UA-fragile),
   OTel stack (težkotonážní, kvóty stejně nemá), PTY wrapping (vidí jen
   vlastní sessions).

## 4) Co si AAI bere (návrh CHANGE-0127)

Optional, zero-LLM-token, zero-network, node-stdlib live-status vrstva nad
existující trojicí generátorů (dashboard / factory-report / overview):
lokální sessions + dnešní/týdenní spend per projekt (JSONL), oficiální kvóty
(statusline spool, degraduje tiše), liveness (hooks spool, degraduje tiše).
Blumeho "config drift" pilíř NEpřebíráme — u nás ho řeší docs-audit + diet
ledger + TEST piny deterministicky v CI. Blumeho "repeated corrections →
durable artifact" smyčku už fabrika dělá řízeně (friction spool → intake).
