# Uživatelský návod pro Remote Orchestration

Česká verze. English version: [REMOTE_ORCHESTRATION_USER_GUIDE.md](./REMOTE_ORCHESTRATION_USER_GUIDE.md)

Tento návod je určený pro operátora, který chce na Linuxu nebo ve WSL nainstalovat remote-orchestration control-plane, přihlásit Claude/Codex přes CLI subscription, napojit host na Telegram a celé to spustit bez ručního editování projektových souborů.

## 1. Co po instalaci získáš

Po dokončení setupu budeš mít:

- jeden host-side control-plane proces
- jednu SQLite runtime databázi v `.runtime/`
- jeden vygenerovaný launcher skript pro Telegram polling
- registraci jednoho nebo více projektů
- routing mezi Claude Code a Codex přes CLI subscription mode
- Telegram commandy a inline tlačítka pro queueing a řízení práce

Tato feature nepoužívá provider API klíče. Počítá s tím, že provider CLI už jsou na hostu nainstalované a přihlášené.

## 2. Co připravit předem

Na Linux/WSL hostu připrav:

- Node.js `>=20`
- `git`
- `bash`
- volitelně Docker, pokud chceš kontejnery
- Telegram bot token z BotFathera
- aspoň jedno provider CLI nainstalované a přihlášené:
  - `claude`
  - `codex`

Rychlé ověření:

```bash
node -v
git --version
bash --version
which claude || true
which codex || true
docker --version || true
```

Preferovaná varianta ve WSL je nativní Linux Node z `~/.nvm`, ideálně `v20+` nebo `v22+`.
Runtime teď preferuje Linux Node z `~/.nvm` dřív než fallback na `node.exe`.

## 3. Instalace a přihlášení agent CLI

### Claude Code

Nainstaluj Claude Code CLI standardním způsobem od providera a přihlas ho přes subscription účet:

```bash
claude auth login
claude auth status --json
```

Pak ověř:

```bash
which claude
claude --version
```

Typický tvar cesty ve WSL:

```bash
/home/<user>/.local/bin/claude
```

### Codex

Na tomto hostu je aktuální globální instalace Codex CLI rozbitá a nejdřív potřebuje reinstall:

```bash
npm install -g @openai/codex@latest
```

Pak spusť Codex a zvol `Sign in with ChatGPT`:

```bash
codex
```

Pak ověř:

```bash
which codex
codex --help
```

Pokud `codex --help` spadne na chybě s missing optional dependency, udělej reinstall a spusť `codex` znovu.

### Důležité pravidlo

Control-plane ukládá jen metadata o zdraví a usage providera. Skutečný login state zůstává v nativních CLI home adresářích, typicky:

- `~/.claude`
- `~/.codex`

Pokud CLI chybí nebo je rozbité, installer ho označí jako nedostupné a autorouter na něj nebude posílat práci.

## 4. Vytvoření a ověření Telegram bota

### 4.1 Vytvoření bot tokenu

V Telegramu:

1. otevři `@BotFather`
2. spusť `/newbot`
3. nastav jméno a username
4. zkopíruj token

### 4.2 Ověření tokenu z hostu

Z rootu repa spusť:

```bash
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
```

Očekávaný výsledek:

- JSON payload s username bota
- pokud to spadne, token je špatně nebo bot není dostupný

### 4.3 Jak zjistit potřebná Telegram ID

Než installer bude chtít `allowed chat ids` a `allowed user ids`, pošli botovi aspoň jednu zprávu z:

- každého chatu, který má projekt ovládat
- každého uživatele, který smí approve/resume/stop

Pak spusť:

```bash
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>"
```

Výstup obsahuje:

- `chat_ids`: nalezená `chat_id` z posledních zpráv a callbacků
- `user_ids`: nalezená `user_id`
- `recent_updates`: poslední zprávy nebo callback query

Tyto hodnoty použij v installer wizardu.

Pokud chceš ověřit zároveň identitu bota i zdrojové Telegram ID:

```bash
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>" --limit 20
```

## 5. Instalace control-plane pro aktuální projekt

Pokud je aktuální repo zároveň projekt, který chceš řídit:

```bash
git checkout feature/remote-orchestration
npm --prefix apps/control-plane run install:wizard
```

Wizard se ptá jen na:

1. cestu ke spravovanému projektu
2. `project id`
3. default branch
4. povolené Telegram chat ID
5. povolené Telegram user ID
6. Telegram bot token

Installer potom:

- spustí `npm install` a `npm run build`
- vytvoří `.runtime/control-plane.db`
- vytvoří `docs/ai/project-overrides/remote-control.yaml`, jen pokud ještě neexistuje
- zaregistruje projekt do host SQLite DB
- autodetekuje `claude` a `codex`
- ověří provider session status
- zapíše `.runtime/install-summary.<project>.json`
- zapíše `.runtime/control-plane.env`, pokud zadáš token
- zapíše `.runtime/run-control-plane.sh`
- zapíše runtime log do `.runtime/control-plane.log`
- vypíše přesný run command

## 6. Instalace control-plane pro jiný projekt

Pokud si chceš nechat AAI repo jako host controller a řídit jiný projekt, spusť:

```bash
npm --prefix apps/control-plane run install:host -- \
  --repo-path /mnt/z/AI/my-other-project \
  --project-id my-other-project \
  --default-branch main \
  --chat-ids 123456789 \
  --user-ids 987654321 \
  --telegram-bot-token "<BOT_TOKEN>"
```

Výsledek:

- host runtime data zůstávají v tomto AAI repu v `.runtime/`
- přenositelná projektová policy zůstává v řízeném projektu v `docs/ai/project-overrides/remote-control.yaml`

## 7. Co po instalaci zkontrolovat

Po wizardu nebo neinteraktivní instalaci si zkontroluj:

```bash
cat .runtime/install-summary.<project>.json
cat docs/ai/project-overrides/remote-control.yaml
cat .runtime/control-plane.env
```

Důležité soubory:

- host DB: `.runtime/control-plane.db`
- install summary: `.runtime/install-summary.<project>.json`
- runtime env: `.runtime/control-plane.env`
- runtime log: `.runtime/control-plane.log`
- vygenerovaný launcher: `.runtime/run-control-plane.sh`
- portable project policy: `docs/ai/project-overrides/remote-control.yaml`

## 8. Ověření autentizace agentů po instalaci

Zjisti, co si control-plane myslí o dostupnosti providerů:

```bash
npm --prefix apps/control-plane run auth:status -- --db .runtime/control-plane.db
```

Pokud chceš providera znovu explicitně probe-nout:

```bash
npm --prefix apps/control-plane run auth:probe -- \
  --db .runtime/control-plane.db \
  --provider claude \
  --cli-path "$(command -v claude)" \
  --session-home ~/.claude \
  --probe-args auth,status,--json

npm --prefix apps/control-plane run auth:probe -- \
  --db .runtime/control-plane.db \
  --provider codex \
  --cli-path "$(command -v codex)" \
  --session-home ~/.codex \
  --probe-args --help
```

Aktuální Claude login na hostu si můžeš ověřit i přímo:

```bash
claude auth status --json
```

Očekávané stavy:

- `status: "ok"` pokud CLI existuje a probe prošel
- `status: "missing"` pokud CLI není nainstalované
- `status: "error"` pokud CLI existuje, ale probe selhal

## 9. Spuštění Telegram control-plane

Pokud jsi token zadal při instalaci:

```bash
bash .runtime/run-control-plane.sh
```

To je doporučený způsob spuštění, protože používá vygenerovaný env file i approval config.
Zároveň zapisuje strukturovaný daemon log do `.runtime/control-plane.log`.
Launcher i npm wrapper předávají `--no-warnings`, takže při běžném použití by se SQLite experimental warning už neměl zobrazovat.

Pokud jsi token při instalaci nezadal, nejdřív ho nastav:

```bash
export AAI_TELEGRAM_BOT_TOKEN="<BOT_TOKEN>"
npm --prefix apps/control-plane run telegram:serve -- \
  --db .runtime/control-plane.db \
  --token "$AAI_TELEGRAM_BOT_TOKEN" \
  --approval-config apps/control-plane/config/approval-gates.json
```

Průběh daemonu sleduj takto:

```bash
tail -f .runtime/control-plane.log
npm --prefix apps/control-plane run logs:tail
```

## 10. Jak bota používat v Telegramu

### 10.1 První kontakt

V chatu s botem pošli:

```text
/projects
```

Bot vypíše registrované projekty.

Pokud je registrovaných více projektů a session ještě nemá default projekt, použij:

```text
/new
```

Bot tě nejdřív nechá vybrat projekt.

### 10.2 Vytvoření nové práce

```text
/intake <project_id> <ref_id> <summary>
```

Příklad:

```text
/intake my-other-project PRD-123 Add dockerized worker launcher
```

Alias:

```text
/new my-other-project PRD-123 Add dockerized worker launcher
```

### 10.3 Zjištění stavu

```text
/status
/status <project_id> <ref_id>
```

### 10.4 Zobrazení provider usage

```text
/usage
```

Pokud ještě žádný provider neposlal machine-readable quota data, bot teď vypíše stav provider session a informaci, že quota telemetry ještě není synchronizovaná.
U Claude fallback navíc ukáže i detekovaný account e-mail a subscription typ, pokud je dostupný `claude auth status --json`.

### 10.5 Změna providera

```text
/provider <project_id> <auto|claude|codex> [ref_id]
```

### 10.6 Resume a stop

```text
/resume <project_id> <ref_id>
/stop <project_id> <ref_id>
```

Inline tlačítka dnes podporují:

- `Resume`
- `Stop`
- `Use Claude`
- `Use Codex`
- výběr projektu

## 11. Spuštění a inspekce práce z hostu

Příprava runu:

```bash
npm --prefix apps/control-plane run run:prepare -- \
  --db .runtime/control-plane.db \
  --project-id my-other-project \
  --ref-id PRD-123 \
  --repo-path /mnt/z/AI/my-other-project \
  --project-config /mnt/z/AI/my-other-project/docs/ai/project-overrides/remote-control.yaml \
  --worktrees-root .runtime/worktrees \
  --container-image ghcr.io/example/aai-worker:preview \
  --provider auto
```

Spuštění v Docker módu:

```bash
npm --prefix apps/control-plane run run:launch -- \
  --db .runtime/control-plane.db \
  --manifest .runtime/worktrees/my-other-project-PRD-123/run-manifest.json \
  --mode docker
```

Inspekce runu:

```bash
npm --prefix apps/control-plane run run:inspect -- \
  --db .runtime/control-plane.db \
  --run-id <RUN_ID>
```

## 12. Doporučené příkazy, které fakt budeš používat

```bash
npm --prefix apps/control-plane run install:wizard
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>"
npm --prefix apps/control-plane run auth:status -- --db .runtime/control-plane.db
bash .runtime/run-control-plane.sh
npm --prefix apps/control-plane run validate:remote
```

## 13. Troubleshooting

### Installer hlásí, že Claude nebo Codex chybí

To znamená, že CLI binárka nebyla nalezena nebo neprošla probe. Nainstaluj CLI na host, přihlas ho přes subscription a pak spusť znovu:

```bash
npm --prefix apps/control-plane run install:wizard
```

nebo:

```bash
npm --prefix apps/control-plane run auth:probe -- --db .runtime/control-plane.db ...
```

Pro Claude subscription login na tomto hostu jsou přímé příkazy:

```bash
claude auth login
claude auth status --json
```

Pro Codex na tomto hostu nejdřív reinstall:

```bash
npm install -g @openai/codex@latest
codex
```

Pak zvol `Sign in with ChatGPT`.

### Telegram token funguje, ale `telegram:setup-info` neukazuje žádná ID

Pošli botovi novou zprávu z cílového chatu a pak spusť znovu:

```bash
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>"
```

### Bot běží, ale nereaguje v očekávaném projektu

Zkontroluj:

- registrované projekty: `npm --prefix apps/control-plane run project:list -- --db .runtime/control-plane.db`
- Telegram ACL v project row
- aktuální session default přes `/projects` a `/new`

## 14. Validace

Spusť celou sadu:

```bash
npm --prefix apps/control-plane run validate:remote
```

Cílový výsledek:

- `27/27 PASS`

Focused checks:

```bash
npm --prefix apps/control-plane run test:remote:install
npm --prefix apps/control-plane run test:remote:provider-session
npm --prefix apps/control-plane run test:remote:telegram
npm --prefix apps/control-plane run test:remote:telegram-setup
npm --prefix apps/control-plane run test:remote:npm
```

## 15. Pravidlo synchronizace dokumentace

Tento návod musí zůstat synchronizovaný s:

- [REMOTE_ORCHESTRATION_USER_GUIDE.md](./REMOTE_ORCHESTRATION_USER_GUIDE.md)

Každá budoucí změna onboarding flow nebo command surface musí upravit obě jazykové verze ve stejné změně.
