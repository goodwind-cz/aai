# Uživatelský návod pro Remote Orchestration

Česká verze. English version: [REMOTE_ORCHESTRATION_USER_GUIDE.md](./REMOTE_ORCHESTRATION_USER_GUIDE.md)

Tento návod je pro operátora, který chce co nejkratší cestu od „mám repo a Telegram bota“ k „control-plane běží na pozadí a ovládám ho pár jednoduchými příkazy“.

## 1. Co po instalaci získáš

Po dokončení setupu budeš mít:

- jeden host-side control-plane daemon
- jednu SQLite runtime databázi v `.runtime/`
- jeden vygenerovaný launcher skript pro start, status, stop, restart, logy, probe a login
- registraci jednoho nebo více projektů
- routing mezi Claude Code a Codex přes CLI subscription mode
- Telegram commandy a inline akce pro queueing a řízení práce

Tato feature nepoužívá provider API klíče. Používá jen nativní Claude Code a Codex CLI subscription session na hostu.

## 2. Co připravit předem

Na Linux/WSL hostu připrav:

- Node.js `>=20`
- `git`
- `bash`
- volitelně Docker, pokud chceš kontejnery
- Telegram bot token z BotFathera
- aspoň jedno provider CLI nainstalované nebo připravené k instalaci:
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

## 3. Přihlášení Claude nebo Codex přes subscription

### Claude Code

Pokud je `claude` nainstalovaný:

```bash
claude auth login
claude auth status --json
which claude
```

Očekávaný tvar cesty ve WSL:

```bash
/home/<user>/.local/bin/claude
```

Jestli `claude auth status --json` říká, že jsi přihlášený, Claude je připravený pro control-plane.
Když tento login wizard najde později, stačí Enter pro ponechání nebo `s` pro přepnutí na jiný Claude subscription účet.

### Codex

Pokud `codex` chybí nebo je rozbitý, udělej nejdřív reinstall:

```bash
npm install -g @openai/codex@latest
```

Pak spusť Codex a zvol `Sign in with ChatGPT`:

```bash
codex
which codex
codex --help
```

Pokud `codex --help` spadne na chybě s optional dependency, udělej reinstall a spusť `codex` znovu.
Když wizard najde použitelný Codex login, Enter ho ponechá a `s` znovu otevře nativní Codex sign-in flow pro jiný ChatGPT účet.

### Důležité pravidlo

Skutečný login state zůstává v nativních CLI home adresářích, typicky:

- `~/.claude`
- `~/.codex`

Control-plane ukládá jen host-side metadata o tom, jestli CLI existuje, jestli probe prošel a jestli se podařilo načíst usage telemetry.

## 4. Vytvoření Telegram bota a zjištění ID

### 4.1 Vytvoření bot tokenu

V Telegramu:

1. otevři `@BotFather`
2. spusť `/newbot`
3. nastav jméno a username
4. zkopíruj token

### 4.2 Ověření tokenu z hostu

```bash
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
```

Očekávaný výsledek:

- JSON s username a id bota

### 4.3 Zjištění chat ID a user ID

Před spuštěním installeru:

1. Pošli botovi aspoň jednu zprávu z každého chatu, který má projekt ovládat.
2. Pošli aspoň jednu zprávu z každého uživatele, který smí approve, resume nebo stop.

Pak spusť:

```bash
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>" --limit 20
```

Výstup obsahuje:

- `chat_ids`
- `user_ids`
- zdroje posledních zpráv a callbacků

Tyto hodnoty použij ve wizardu.

## 5. Spuštění installeru

Pokud je tohle repo zároveň host controller a projekt, který chceš řídit:

```bash
npm --prefix apps/control-plane run install:wizard
```

Wizard drží operátorský vstup co nejkratší. Ptá se na:

1. cestu ke spravovanému projektu
2. `project id`
3. default branch
4. povolené Telegram chat ID
5. povolené Telegram user ID
6. Telegram bot token

Wizard potom:

- spustí `npm install` a `npm run build`
- vytvoří nebo znovu použije `.runtime/control-plane.db`
- vytvoří `docs/ai/project-overrides/remote-control.yaml`, jen pokud je potřeba
- zaregistruje projekt do host SQLite DB
- autodetekuje `claude` a `codex`
- ověří provider login state
- pokud je provider už přihlášený, ukáže aktuální účet a dovolí ho ponechat Enterem nebo přepnout přes `s`
- pokud provider ještě přihlášený není, nabídne okamžité otevření nativního interaktivního login flow
- vysvětlí, co dělat, když provider ukáže browser link nebo jednorázový device code
- zapíše `.runtime/install-summary.<project>.json`
- zapíše `.runtime/control-plane.env`
- zapíše `.runtime/run-control-plane.sh`
- zapisuje runtime log do `.runtime/control-plane.log`

Když wizard pustíš znovu později, převezme poslední známé hodnoty. Prakticky to znamená:

- Enter ponechá aktuální cestu k repu, project id, branch, chat ID, user ID i token
- existující hodnoty z `docs/ai/project-overrides/remote-control.yaml` se použijí jako výchozí i tehdy, když installer potřebuje projektový config znovu přepsat
- token se ukazuje maskovaně
- pokud najde existující config nebo runtime soubory, wizard se zeptá `Overwrite existing config/runtime state? [y/N]`

Příklad:

```text
Existing control-plane state detected.
Press Enter to preserve the current setup, or 'y' to overwrite it and reinitialize the DB.
Overwrite existing config/runtime state? [y/N]:
```

```text
Provider 'claude' is already logged in as ales@example.test (max).
Press Enter to keep this login, or type 's' to switch account [Enter/s]:
```

```text
Provider 'claude' is not ready yet (status: error).
Last probe detail: Claude CLI is installed but not logged in. Run 'claude auth login' on the host.
Press Enter to open interactive login now, or type 's' to skip for now [Enter/s]:
Complete the provider's native subscription login flow on this host.
If the CLI opens a browser, finish the login there.
If the CLI shows a verification link and one-time code, open the link, paste or confirm the code, and wait until the CLI returns.
```

Význam volby stavu:

- `N` nebo Enter ponechá aktuální config, DB, env, launcher i summary soubory
- `y` přepíše config/runtime soubory a vytvoří SQLite DB znovu od nuly

Neinteraktivní ekvivalent:

```bash
npm --prefix apps/control-plane run install:host -- --preserve-existing ...
npm --prefix apps/control-plane run install:host -- --overwrite-existing ...
```

## 6. Ověření login state providerů po instalaci

Nejjednodušší operátorský příkaz je:

```bash
bash .runtime/run-control-plane.sh probe
```

Ten znovu ověří oba providery a vypíše čitelný souhrn.

Význam stavů:

- `ok` znamená, že CLI existuje a login probe prošel
- `missing` znamená, že CLI na hostu není nainstalované
- `error` znamená, že CLI existuje, ale login nebo probe selhal

Přímé low-level příkazy:

```bash
npm --prefix apps/control-plane run auth:status -- --db .runtime/control-plane.db

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

Pokud chceš ověřit jen Claude přímo:

```bash
claude auth status --json
```

## 7. Spuštění control-plane na pozadí

Jakmile installer vytvoří `.runtime/control-plane.env`, používej:

```bash
bash .runtime/run-control-plane.sh start
```

To je doporučený startovací příkaz. Udělá toto:

- automaticky použije vygenerovaný env file
- spustí Telegram daemon na pozadí
- hned vrátí shell

Launcher i CLI wrapper předávají `--no-warnings`, takže při běžném použití by se už neměl zobrazovat `node:sqlite` experimental warning.

## 8. Denní operátorské příkazy

Řízení běhu na pozadí:

```bash
bash .runtime/run-control-plane.sh status
bash .runtime/run-control-plane.sh stop
bash .runtime/run-control-plane.sh restart
bash .runtime/run-control-plane.sh logs
```

Login a opětovné ověření providerů:

```bash
bash .runtime/run-control-plane.sh login claude
bash .runtime/run-control-plane.sh login codex
bash .runtime/run-control-plane.sh probe
```

Co přesně dělají příkazy `run-control-plane.sh`:

- `start`
  Spustí Telegram control-plane na pozadí a hned vrátí shell. To je normální způsob každodenního spuštění.
- `run`
  Spustí stejný daemon v popředí. Hodí se jen tehdy, když ho chceš sledovat přímo v aktuálním terminálu při debugování.
- `status`
  Ukáže, jestli daemon běží, jeho PID, cestu k DB a logům, jestli je nastavený Telegram token, aktuální stav provider session a aktivní vazbu na projekt.
- `stop`
  Zastaví daemon na pozadí a odstraní i zastaralý PID file, pokud už proces ve skutečnosti neběží.
- `restart`
  Daemon zastaví a znovu spustí se stejným vygenerovaným env file.
- `logs`
  Připojí se na strukturovaný runtime log. Použij ho tehdy, když daemon běží a chceš vidět, co právě dělá.
- `probe`
  Znovu ověří dostupnost a login state Claude i Codex a vypíše čitelný souhrn včetně informace o dostupnosti usage telemetry.
- `login claude`
  Otevře nativní interaktivní Claude login na hostu a potom znovu ověří Claude.
- `login codex`
  Otevře nativní interaktivní Codex login na hostu a potom znovu ověří Codex.

Ekvivalentní npm shortcuty:

```bash
npm --prefix apps/control-plane run daemon:start
npm --prefix apps/control-plane run daemon:status
npm --prefix apps/control-plane run daemon:stop
npm --prefix apps/control-plane run daemon:restart
npm --prefix apps/control-plane run daemon:logs
npm --prefix apps/control-plane run daemon:probe
npm --prefix apps/control-plane run daemon:login:claude
npm --prefix apps/control-plane run daemon:login:codex
```

`status` ukazuje:

- jestli daemon běží
- PID, DB path a log path
- jestli je nakonfigurovaný Telegram token
- čitelný stav provider session
- čitelný souhrn registrace projektu

## 9. Jak sledovat logy

```bash
bash .runtime/run-control-plane.sh logs
```

nebo:

```bash
npm --prefix apps/control-plane run daemon:logs
```

Strukturovaný log se zapisuje také do:

- `.runtime/control-plane.log`

## 10. Jak fungují Docker subagenti

Když úloha běží v Dockeru, control-plane do containeru nekopíruje žádnou skrytou agent memory.

Co worker dostane:

- git worktree mountnutý do `/workspace`
- run manifest v `/workspace/.aai-control-plane-run.json`
- explicitní handoff packet v `/workspace/.aai-handoff.json`
- session home vybraného providera mountnutý read-only do `/var/run/aai/provider-session/<provider>`

Co worker nedostane:

- provider API klíče
- celý host home adresář
- skrytou sdílenou memory z jiných agent runů
- Docker socket

Důležité pravidlo:

- Docker image už musí obsahovat správné CLI binárky, například `claude` nebo `codex`
- host předává jen login/session home a runtime hinty
- session mount je read-only

Předávání úkolů mezi agenty je explicitní:

- repo docs zůstávají kanonický source of truth
- handoff packet nese current work item, approvals, provider runtime contract a document refs
- další worker nebo subagent musí číst handoff packet, ne spoléhat na implicitní memory

## 11. Použití bota v Telegramu

### 11.1 Výpis projektů

```text
/projects
```

### 11.2 Vytvoření práce

```text
/intake <project_id> <ref_id> <summary>
```

Alias:

```text
/new <project_id> <ref_id> <summary>
```

### 11.3 Zjištění stavu

```text
/status
/status <project_id> <ref_id>
```

### 11.4 Zjištění provider usage

```text
/usage
```

Pokud ještě není dostupná quota telemetry, bot teď spadne do čitelného fallbacku se stavem provider session místo toho, aby jen napsal, že usage není k dispozici.

### 11.5 Změna providera

```text
/provider <project_id> <auto|claude|codex> [ref_id]
```

### 11.6 Resume a stop

```text
/resume <project_id> <ref_id>
/stop <project_id> <ref_id>
```

Inline akce podporují:

- `Resume`
- `Stop`
- `Use Claude`
- `Use Codex`
- výběr projektu

## 12. Krátká sada příkazů, kterou většina operátorů fakt potřebuje

```bash
npm --prefix apps/control-plane run install:wizard
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>"
bash .runtime/run-control-plane.sh probe
bash .runtime/run-control-plane.sh start
bash .runtime/run-control-plane.sh status
bash .runtime/run-control-plane.sh logs
```

## 13. Troubleshooting

### Claude nebo Codex chybí

Nainstaluj nebo reinstaluj CLI, přihlas ho a pak spusť:

```bash
bash .runtime/run-control-plane.sh probe
```

nebo znovu wizard:

```bash
npm --prefix apps/control-plane run install:wizard
```

### Nejjednodušší host-side login flow

```bash
bash .runtime/run-control-plane.sh login claude
bash .runtime/run-control-plane.sh login codex
bash .runtime/run-control-plane.sh probe
```

### Telegram token funguje, ale `telegram:setup-info` neukazuje žádná ID

Pošli botovi novou zprávu z cílového chatu a pak spusť:

```bash
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>" --limit 20
```

### Daemon běží, ale Telegram nic nedělá

Zkontroluj:

- `bash .runtime/run-control-plane.sh status`
- `bash .runtime/run-control-plane.sh logs`
- jestli jsou správně zaregistrovaná chat ID a user ID

## 13. Validace

Spusť celou sadu:

```bash
npm --prefix apps/control-plane run validate:remote
```

Aktuálně očekávaný výsledek:

- čitelné `[ OK ]` nebo `[FAIL]` pro každý test
- finální souhrn se seznamem passed a failed testů
- `30` passing testů v aktuální sadě

Focused checky:

```bash
npm --prefix apps/control-plane run test:remote:install
npm --prefix apps/control-plane run test:remote:provider-session
npm --prefix apps/control-plane run test:remote:telegram
npm --prefix apps/control-plane run test:remote:telegram-setup
npm --prefix apps/control-plane run test:remote:daemon
npm --prefix apps/control-plane run test:remote:npm
```

## 14. Pravidlo synchronizace dokumentace

Tento návod musí zůstat synchronizovaný s:

- [REMOTE_ORCHESTRATION_USER_GUIDE.md](./REMOTE_ORCHESTRATION_USER_GUIDE.md)

Každá budoucí změna onboarding flow nebo command surface musí upravit obě jazykové verze ve stejné změně.
