# Analýza Pro-Workflow a návrh integrace do AAI

**Datum:** 2026-03-08
**Zdroj:** [rohitg00/pro-workflow](https://github.com/rohitg00/pro-workflow)
**Cíl:** Udělat kroky AI vývoje uživatelsky přívětivé, jasné a neotravné, se správným množstvím informací

---

## Stručné shrnutí

Pro-workflow klade důraz na **kontrolní body místo neustálého komentování** a na **učení z oprav** namísto ukecaných průběžných statusů. Hlavní poznatek: uživatelé chtějí *kontrolní brány* v rozhodovacích bodech, ne permanentní reportování postupu.

**Doporučená vylepšení AAI:**
1. **Fázové checkpointy** v `/aai-loop` (schvalovací brány mezi fázemi)
2. **Pravidla učení** z oprav (perzistentní paměť)
3. **Minimální průběžné aktualizace** (akčně orientované, ne sloh)
4. **Rituál uzavření sezení** (zachycení poznatků)
5. **Hook systém** pro quality gates (pre-commit kontroly)
6. **Pre-compact uložení kontextu** (zachování stavu před kompresí kontextu)
7. **Diagnostika prostředí** (`/aai-doctor`)
8. **Kontextový replay poznatků** (zobrazení relevantních minulých poznatků)

---

## Současné komunikační vzorce AAI

### Co AAI dělá dobře ✅

1. **Validace založená na důkazech** - screenshoty, test logy, metriky
2. **Strukturované artefakty** - PRD, specifikace, rozhodnutí na předvídatelných místech
3. **Jasné hranice fází** - RED→GREEN→REFACTOR, Planning→Implementation→Validation
4. **Transparentní stav** - `STATE.yaml` ukazuje aktuální fokus a stav

### Co by šlo zlepšit ⚠️

1. **Příliš autonomní režim** - `/aai-loop` běží až 20 ticků bez checkpointů
2. **Žádné učení z oprav** - opakované chyby se nemění na pravidla
3. **Přílišná ukecanost v chatu** - moc textu typu "Teď udělám...", "Podívám se..."
4. **Chybí rituál uzavření** - sezení končí bez zachycení poznatků
5. **Chybí quality gates před akcí** - commity probíhají bez finálních připomínek

---

## Vzorce z Pro-Workflow k převzetí

### 1. Fázové checkpointy (VYSOKÁ PRIORITA)

**Problém:** `/aai-loop` běží autonomně až 20 ticků bez lidského schválení mezi Planning→Implementation→Validation.

**Přístup pro-workflow:** "Research > Plan > Implement > Review & Commit" s validačními branami

**Navržené rozšíření AAI:**

```yaml
# Přidat do .aai/SKILL_LOOP.prompt.md

CHECKPOINT_MODE (volitelný parametr):
  - none: současné chování (autonomních 20 ticků)
  - staged: pauza na schválení mezi hlavními fázemi
  - paranoid: pauza po každém ticku

When checkpoint_mode == "staged":
  1. Spusť orchestration tick
  2. Pokud se změní kategorie role (Planning→Implementation, Implementation→Validation):
     → POZASTAV a vypiš žádost o schválení checkpointu
     → Uživatel musí explicitně schválit pokračování
  3. Po schválení pokračuj dalším tickem
```

**Uživatelsky přívětivý formát:**

```
─────────────────────────────────────
CHECKPOINT: Planning → Implementation
─────────────────────────────────────

Plánování dokončeno:
• Specifikace: docs/specs/SPEC-007-user-profile.md
• Test Plan: definováno 8 testů (TEST-001..TEST-008)
• Odhad: ~2 TDD cykly

Přejít na implementaci?
[y] Ano, pokračovat  [n] Ne, upravit plán  [p] Pozastavit loop
─────────────────────────────────────
```

**Přínosy:**
- Uživatel řídí, kdy se mezi hlavními fázemi pokračuje
- Menší riziko, že dlouhý autonomní běh ujede mimo směr
- Soulad s pro-workflow: "dávkové review v checkpointech"

---

### 2. Pravidla učení (VYSOKÁ PRIORITA)

**Problém:** Když uživatel opraví chybu (např. "nepoužívej console.log v produkci"), AAI si to do dalších sezení nepamatuje.

**Přístup pro-workflow:** "Po opravě navrhni pravidlo → po schválení přidej do LEARNED"

**Navržené rozšíření AAI:**

Vytvořit `docs/knowledge/LEARNED.md` (projektově specifická pravidla):

```markdown
# Naučená pravidla specifická pro projekt

## Styl kódu
- [2026-03-08] Vždy používej `logger.debug()` místo `console.log()` (zdroj: oprava od uživatele)
- [2026-03-07] Upřednostnit named exports před default exports (zdroj: code review)

## Testování
- [2026-03-06] E2E testy musí používat `playwright-mcp` server, ne lokální Playwright (zdroj: preference uživatele)

## Workflow
- [2026-03-05] Po přidání nových npm balíčků vždy spustit `/aai-bootstrap` (zdroj: debugging sezení)
```

**Trigger mechanismus:**

Když zpráva uživatele obsahuje opravný vzorec ("nedělej X", "použij Y", "tohle je špatně"):
1. Detekuj vzorec opravy
2. Navrhni pravidlo v chatu: "Mám si zapamatovat: 'Vždy používej logger.debug() místo console.log()'?"
3. Po schválení přidej záznam do `docs/knowledge/LEARNED.md` s časem a zdrojem
4. V dalších sezeních načítej LEARNED.md do kontextu

**Přínosy:**
- Kumulace oprav (feedback se časem zhodnocuje)
- Méně opakovaných chyb
- Projektové know-how přetrvává mezi sezeními

---

### 3. Minimální průběžné aktualizace (STŘEDNÍ PRIORITA)

**Problém:** Zprávy AAI v chatu jsou příliš verbose: "Let me check...", "I will now...", "Processing..."

**Přístup pro-workflow:** "Minimální, akčně orientované notifikace" místo popisného vyprávění

**Současné AAI (verbose):**

```
Podívám se na aktuální stav repozitáře.
Teď načtu STATE.yaml, abych zjistil, v jaké jsme fázi.
Vidím, že plánování je hotové. Teď spustím implementační fázi.
Nejdřív vytvořím testovací soubor...
```

**Navržené AAI (minimal):**

```
✓ Stav ověřen → fáze Implementation
⚙ Spouštím TDD cyklus (TEST-001: validace hesla)
```

**Pravidla:**

1. **Používat symboly** místo slohu:
   - ✓ (dokončeno)
   - ⚙ (probíhá)
   - ⚠ (varování)
   - ✗ (chyba)
   - ⏸ (pozastaveno / čeká)

2. **Jednořádkový status** pro hlavní akce:
   ```
   ⚙ RED fáze: píšu failing test
   ✓ Test padá podle očekávání → docs/ai/tdd/red-20260308.log
   ⚙ GREEN fáze: minimální implementace
   ✓ Test prochází → docs/ai/tdd/green-20260308.log
   ⚙ REFACTOR fáze: extrahuji validační logiku
   ✓ Všechny testy procházejí → docs/ai/tdd/refactor-20260308.log
   ```

3. **Bez úvodů typu "Teď udělám..."** - jen co běží nebo co je hotovo

4. **Výjimka: checkpointy** - tam má být text podrobnější a jasný

**Přínosy:**
- Méně šumu v chatu
- Rychlejší čitelnost
- Důraz na výsledek místo popisu procesu

---

### 4. Rituál uzavření sezení (STŘEDNÍ PRIORITA)

**Problém:** Sezení končí náhle bez zachycení toho, co se naučilo nebo co je dál.

**Přístup pro-workflow:** "Strukturovaný checklist na konci sezení zachytí poznatky"

**Navržené rozšíření AAI:**

Přidat skill `/aai-wrap-up`:

```markdown
# Wrap-Up Skill

## Cíl
Zachytit poznatky a připravit další sezení.

## Instrukce

1. **Zkontroluj aktuální sezení**
   - Ověř `docs/ai/STATE.yaml` pro dokončenou práci
   - Ověř `docs/ai/METRICS.jsonl` pro poslední záznamy
   - Identifikuj, co bylo dokončeno

2. **Zachyť poznatky**
   ```
   POZNATKY Z TOHOTO SEZENÍ
   ────────────────────────

   Dokončeno:
   • [Feature] Profil uživatele s uploadem avataru
   • [TDD] 8 testů (TEST-001..TEST-008) → vše green
   • [Evidence] validační report se screenshoty

   Výzvy:
   • Problémy s připojením Playwright MCP serveru → vyřešeno restartem
   • Pokrytí testy spadlo na 78 % → přidány 2 edge-case testy

   Rozhodnutí:
   • Pro ukládání avatarů použito Cloudflare R2 (viz DEC-009)
   • Zvoleny optimistic UI updates kvůli UX (viz DEC-010)

   Další sezení:
   • Implementovat úpravu profilu (REQ-008)
   • Přidat nastavení soukromí profilu
   ```

3. **Navrhni nová pravidla**
   - Projdi sezení kvůli opakujícím se vzorcům
   - Navrhni doplnění do `docs/knowledge/LEARNED.md`

4. **Zkontroluj necommitnutou práci**
   ```bash
   git status
   # Pokud je necommitnutá práce, navrhni commit nebo stash
   ```

5. **Aktualizuj STATE.yaml**
   ```yaml
   last_session:
     ended_utc: 2026-03-08T10:30:00Z
     summary: "Feature profilu dokončena, 8 testů green"
     next_focus: "Úprava profilu (REQ-008)"
   ```

6. **Vypiš shrnutí**
   - Co se dokončilo
   - Jaké jsou další kroky
   - Pokud je potřeba, vyzvi k commitu/pushi
```

**Auto-trigger na konci sezení:**
- Detekovat konec sezení (uživatel napíše "bye", "done", "to je vše")
- Automaticky spustit wrap-up rituál
- Uložit log sezení do `docs/ai/sessions/SESSION-<timestamp>.md`

**Přínosy:**
- Jasné hranice sezení
- Systematicky zachycené poznatky
- Snadný návrat v dalším sezení

---

### 5. Quality Gate Hooky (STŘEDNÍ PRIORITA)

**Problém:** Chybí připomínky před rizikovými akcemi (commity, push, destruktivní operace).

**Přístup pro-workflow:** "PreToolUse hooky pro připomenutí quality gates před editací/commitem"

**Navržené rozšíření AAI:**

Přidat quality gate kontroly do commit operací:

```markdown
# Pre-Commit Quality Gates

Před `git commit` ověř:

1. **Je TDD evidence kompletní?**
   - Pokud `STATE.yaml` ukazuje nedokončený TDD cyklus (chybí red/green/refactor evidence)
   - Varování: "⚠ TDD cyklus není kompletní - chybí REFACTOR evidence. Pokračovat v commitu? [y/n]"

2. **Prochází testy?**
   - Spusť test suite
   - Pokud některý test selže, commit ZABLOKOVAT
   - Chyba: "✗ Nelze commitnout - 3 testy selhávají. Nejprve oprav testy."

3. **Je hotová validace?**
   - Zkontroluj, zda pro aktuální work item existuje validační report
   - Varování: "⚠ Nenalezen validační report. Spustit nejdřív `/aai-validate-report`? [y/n]"

4. **Kontrola secrets?**
   - Sken staged souborů na běžné vzory secrets (API klíče, tokeny, hesla)
   - Pokud nalezeno, commit ZABLOKOVAT
   - Chyba: "✗ Možné secrets detekovány v src/config.ts:12 - před commitem zkontrolujte"

5. **Debug výpisy?**
   - Sken na `console.log`, `debugger`, `TODO`, `FIXME` ve staged souborech
   - Varování: "⚠ Nalezeny 2 výskyty console.log. Odstranit před commitem? [y/n]"
```

**Integrace hooků:**

- Tyto kontroly spouštět automaticky před commitem v `/aai-tdd`, `/aai-loop`, `/aai-validate-report`
- Uživatel může přepsat varování (ne chyby)
- Chyby blokují commit, dokud nejsou vyřešené

**Přínosy:**
- Prevence běžných chyb
- Vynucení kvalitativních standardů
- Zachycení problémů před commitem

---

### 6. Pre-Compact uložení kontextu (VYSOKÁ PRIORITA)

**Problém:** Když Claude Code komprimuje předchozí zprávy kvůli limitu kontextového okna, kritické informace (aktuální rozhodnutí, průběžné uvažování, nezachycené poznatky) se mohou ztratit. Nejvíc trpí dlouhá sezení.

**Přístup pro-workflow:** Hook skript `pre-compact`, který uloží stav sezení do souboru před kompresí.

**Navržené rozšíření AAI:**

Hook, který automaticky uloží kritický kontext:

```bash
# .aai/scripts/pre-compact-save.sh
# Spuštěn před kompresí kontextu

# Uložit snapshot aktuálního stavu
cp docs/ai/STATE.yaml docs/ai/.pre-compact-state-backup.yaml

# Zachytit shrnutí kontextu sezení
cat > docs/ai/.session-context.md << 'CONTEXT'
# Snapshot kontextu před kompresí
# Auto-generováno — přečtěte po kompresi kontextu

## Aktuální stav
$(cat docs/ai/STATE.yaml)

## Poslední rozhodnutí
$(tail -5 docs/ai/decisions.jsonl)

## Poslední metriky
$(tail -3 docs/ai/METRICS.jsonl)
CONTEXT
```

**Integrace:** Konfigurace jako Claude Code hook v `.claude/settings.local.json`:
```json
{
  "hooks": {
    "PreCompact": [
      { "command": "bash .aai/scripts/pre-compact-save.sh" }
    ]
  }
}
```

**Přínosy:**
- Žádná ztráta kontextu během dlouhých sezení
- Automatické — bez zásahu uživatele
- Kontinuita stavu přes komprese kontextu
- Kritická rozhodnutí zachována i po kompresi zpráv

---

### 7. Diagnostika prostředí (STŘEDNÍ PRIORITA)

**Problém:** AAI má mnoho pohyblivých částí (STATE.yaml, prompt soubory, skills, skripty, MCP servery, znalostní soubory). Když něco chybí nebo je špatně nakonfigurováno, chyby jsou kryptické.

**Přístup pro-workflow:** Příkaz `/doctor`, který diagnostikuje konfiguraci a zdraví prostředí.

**Navržené rozšíření AAI:**

Vytvořit skill `/aai-doctor` s komplexní kontrolou zdraví:

```
KONTROLA ZDRAVÍ AAI PROSTŘEDÍ
──────────────────────────────

Základní soubory:
  ✓ .aai/AGENTS.md existuje
  ✓ .aai/PLAYBOOK.md existuje
  ✓ docs/ai/STATE.yaml existuje a je validní YAML
  ✗ docs/TECHNOLOGY.md chybí — spusťte /aai-intake

Skills:
  ✓ 18/18 univerzálních skillů má SKILL.md
  ✓ 18/18 prompt souborů (.aai/SKILL_*.prompt.md) existuje
  ⚠ 0 dynamických skillů — spusťte /aai-bootstrap

Znalosti:
  ✓ docs/knowledge/FACTS.md existuje
  ⚠ docs/knowledge/PATTERNS.md prázdný (0 vzorů)
  ✓ docs/knowledge/UI_MAP.md existuje

Stav:
  ✓ STATE.yaml prochází INV-01..INV-10
  ✓ Žádné zastaralé zámky
  ⚠ Žádné aktivní work itemy

Git:
  ✓ Čistý pracovní strom
  ✓ Na větvi: main
  ⚠ 2 nesledované soubory v docs/analysis/

Celkově: ZDRAVÉ (2 varování)
```

**Rozdíl oproti `/aai-check-state`:**
- `/aai-check-state` validuje pouze invarianty STATE.yaml
- `/aai-doctor` kontroluje celé prostředí: soubory, skills, git, znalosti, závislosti

**Přínosy:**
- Rychlá diagnostika při problémech
- Onboarding — noví uživatelé si ověří nastavení
- Proaktivní detekce chybějících nebo poškozených komponent

---

### 8. Kontextový replay poznatků (STŘEDNÍ PRIORITA)

**Problém:** I s LEARNED.md se do kontextu načtou všechny poznatky bez ohledu na relevanci. Jak soubor roste, plýtvá se kontextovým oknem a signál se ztrácí v šumu.

**Přístup pro-workflow:** Příkaz `/replay`, který prohledá databázi poznatků a zobrazí pouze ty relevantní pro aktuální úkol.

**Navržené rozšíření AAI:**

Vytvořit skill `/aai-replay`, který:

1. Přečte aktuální kontext (STATE.yaml focus, aktivní work itemy, nedávné soubory)
2. Prohledá znalostní soubory (FACTS.md, PATTERNS.md, LEARNED.md, decisions.jsonl)
3. Zobrazí pouze relevantní záznamy

```
RELEVANTNÍ POZNATKY PRO: REQ-010 (reset hesla)
────────────────────────────────────────────────

Z LEARNED.md:
  • [2026-03-06] Vždy testovat edge case expirace tokenu u auth funkcí
  • [2026-03-05] Pro hashování hesel používat bcrypt, nikdy SHA-256

Z PATTERNS.md:
  • Auth endpointy: vždy rate-limit na 5 req/min za IP
  • Odesílání e-mailů: používat frontu, nikdy synchronně v handleru

Z rozhodnutí:
  • DEC-005: Zvolen JWT pro session tokeny (2026-03-04)

Žádné shody ve FACTS.md.
────────────────────────────────────────────────
3 poznatky, 2 vzory, 1 rozhodnutí zobrazeno
```

**Strategie vyhledávání:**
- Extrakce klíčových slov z aktuálního work itemu (název požadavku, specifikace, testy)
- Full-text prohledání znalostních souborů
- Řazení podle relevance a aktuálnosti
- Zobrazení top N nejrelevantnějších (výchozí: 10)

**Možnost auto-triggeru:**
- Automatické spuštění na začátku Implementation fáze v `/aai-loop`
- Zajistí, že relevantní minulé poznatky ovlivní aktuální práci

**Přínosy:**
- Kontextově citlivé — zobrazeny pouze relevantní poznatky
- Škáluje s rostoucí znalostní bází
- Předchází opakování minulých chyb u podobných úkolů
- Funguje se stávajícími znalostními soubory (žádná nová databáze)

---

## Implementační plán

### Fáze 1: Quick Wins ✅ IMPLEMENTOVÁNO

1. **Minimální průběžné aktualizace** ✅
   - Upraven `.aai/AGENTS.md` o komunikační pravidla a legendu symbolů
   - Pravidla: žádné úvody, jednořádkový status, symboly místo slohu

2. **Pre-Commit Quality Gates** ✅
   - Vytvořen `.aai/scripts/pre-commit-checks.sh` a `.ps1`
   - Kontroly: secrets, debug výpisy, TODO/FIXME, TDD evidence, validační reporty
   - Podpora `--strict` režimu; integrováno do AGENTS.md

### Fáze 2: Systém učení ✅ IMPLEMENTOVÁNO

3. **Pravidla učení** ✅
   - Vytvořena šablona `docs/knowledge/LEARNED.md` s kategorizovanými sekcemi
   - Přidáno do CLAUDE.md a AGENTS.md jako kanonický zdroj
   - Přidána logika detekce oprav do AGENTS.md

4. **Rituál uzavření sezení** ✅
   - Vytvořen skill `/aai-wrap-up` (SKILL.md + SKILL_WRAP_UP.prompt.md)
   - Zachytí poznatky, navrhne pravidla, zkontroluje necommitnutou práci
   - Dokumentovány auto-trigger vzory pro detekci konce sezení

### Fáze 3: Odolnost a diagnostika (3-5 dní)

5. **Pre-Compact uložení kontextu** ✅ IMPLEMENTOVÁNO
   - Vytvořen `.aai/scripts/pre-compact-save.sh` a `.ps1`
   - Ukládá snapshot STATE.yaml + nedávná rozhodnutí/metriky před kompresí
   - Konfigurace hooku připravena pro `.claude/settings.local.json`

6. **Diagnostika prostředí** ✅ IMPLEMENTOVÁNO
   - Vytvořen skill `/aai-doctor`
   - Kontroluje: základní soubory, skills, znalosti, STATE.yaml, git status
   - Hlásí ZDRAVÉ / DEGRADOVANÉ / POŠKOZENÉ s akčními varováními

7. **Kontextový replay poznatků** ✅ IMPLEMENTOVÁNO
   - Vytvořen skill `/aai-replay`
   - Prohledává LEARNED.md, PATTERNS.md, FACTS.md, decisions.jsonl
   - Zobrazuje pouze relevantní poznatky pro aktuální kontext

### Fáze 4: Checkpointy ✅ IMPLEMENTOVÁNO

8. **Fázové checkpointy** ✅
   - Upraven `.aai/SKILL_LOOP.prompt.md` s parametrem checkpoint_mode (none/staged/paranoid)
   - Přidán formát checkpointu s [y/n/p] schvalovací bránou
   - Sledování kategorie rolí pro přechody mezi fázemi

---

## Migrační průvodce

### Pro stávající uživatele AAI

**Bez breaking changes** - všechna vylepšení jsou aditivní nebo opt-in:

1. **Fázové checkpointy**: opt-in parametrem
   ```bash
   /aai-loop checkpoint_mode=staged
   ```

2. **Pravidla učení**: automatické, ale každé pravidlo vyžaduje schválení uživatelem

3. **Minimální update zprávy**: automaticky v nových skillech, postupné rolloutování

4. **Wrap-up rituál**: manuálně přes `/aai-wrap-up` nebo auto-trigger

5. **Quality gates**: automatické, ale s možností override

**Doporučené pořadí adopce:**
- Začít quality gates (Fáze 1)
- Přidat wrap-up rituál na konec sezení
- Vyzkoušet fázové checkpointy na dalším feature
- Průběžně budovat LEARNED.md během 2-3 sezení

---

## Metriky a kritéria úspěchu

### Spokojenost uživatele

- **Méně chat šumu**: měřit počet řádků chatu na work item (cíl: -40 %)
- **Méně opakovaných chyb**: sledovat frekvenci oprav (cíl: -70 % po 5 sezeních)
- **Lepší přehled o postupu**: průzkum jasnosti (cíl: >8/10)

### Efektivita

- **Hodnota checkpointů**: % checkpointů, kde uživatel změnil plán (cíl: >20 % = užitečné)
- **Nálezy quality gates**: počet problémů zachycených před commitem (sledovat baseline)
- **Kontinuita sezení**: % sezení navazujících na předchozí poznatky (cíl: >80 %)

---

## Příklad: Před a po

### Před (současné AAI)

```
Uživatel: Přidej funkci resetu hesla
AI: Zkontroluji aktuální stav repozitáře.
AI: Vidím v STATE.yaml, že jsme připravení začít novou práci.
AI: Teď spustím intake proces a vytvořím requirement dokument.
AI: Intake dokončen. Nyní vytvořím specifikaci.
AI: Specifikace hotová. Pokračuji implementací.
AI: Vytvářím testovací soubor...
AI: Test napsán. Teď implementuji minimální řešení.
AI: Implementace hotová. Spouštím testy.
AI: Testy prošly. Pokračuji refaktorem.
AI: Refaktor hotov. Teď spouštím validaci.
AI: Validace dokončena. Všechny acceptance criteria splněny.
AI: Commituji změny.

** Uživatel vidí 40+ řádků bez rozhodovacích bodů **
```

### Po (pro-workflow styl)

```
Uživatel: Přidej funkci resetu hesla

AI: ✓ Intake hotový → REQ-010
AI: ✓ Specifikace hotová → SPEC-010 (12 testů)

─────────────────────────────────────
CHECKPOINT: Planning → Implementation
─────────────────────────────────────
Přejít na implementaci? [y/n]: y

AI: ⚙ RED (TEST-001..TEST-006)
AI: ✓ Failing testy zachyceny
AI: ⚙ GREEN
AI: ✓ Všechny testy prochází
AI: ⚙ REFACTOR
AI: ✓ Kód vyčištěn, testy stále green

─────────────────────────────────────
CHECKPOINT: Implementation → Validation
─────────────────────────────────────
Přejít na validaci? [y/n]: y

AI: ⚙ Validation
AI: ✓ Screenshoty zachyceny (3)
AI: ✓ Report vygenerován
AI: ✓ Všechna acceptance criteria splněna

─────────────────────────────────────
LOOP DOKONČEN
─────────────────────────────────────
Feature: Reset hesla
Stav: ✓ PASS
Evidence: docs/ai/reports/VALIDATION_REPORT_20260308T103000Z.md

** Uživatel vidí 15 řádků se 4 rozhodovacími body **

** Wrap-up rituál **

AI: Uzavřít sezení?

POZNATKY Z TOHOTO SEZENÍ
────────────────────────
Dokončeno:
• Feature resetu hesla (REQ-010, SPEC-010)
• 12 testů → vše green
• Validační report se 3 screenshoty

Výzvy:
• Edge case expirace tokenu vyžadoval extra test (TEST-009)

Rozhodnutí:
• Použita 1hodinová expirace tokenu (viz DEC-011)
• E-mail šablony v databázi kvůli flexibilitě

Mám si zapamatovat:
"U auth funkcí vždy testovat edge case expirace tokenu"?
[y/n]: y

AI: ✓ Přidáno do docs/knowledge/LEARNED.md

Další sezení:
• Implementovat úpravu profilu (REQ-008 pending)

Necommitnutá práce: žádná
Připraveno k pushi? [y/n]
```

**Srovnání:**
- **Počet řádků v chatu**: 40+ → 15 (snížení o 62 %)
- **Rozhodovací body**: 0 → 4 (fázová kontrola)
- **Zachycení poznatků**: ne → ano (perzistentní pravidlo)
- **Uzavření sezení**: náhlé → strukturované
- **Quality gates**: žádné → 5 kontrol

---

## Závěr

**Co nás pro-workflow učí:**
1. Uživatelé chtějí *kontrolu* v rozhodovacích bodech, ne průběžné komentování
2. Opravy se mají měnit na *poznatky*, ne opakované chyby
3. Průběžné statusy mají být *minimální* a akčně orientované
4. Sezení se má *uzavírat vědomě* se zachycením poznatků

**Doporučená priorita adopce v AAI:**
1. **HIGH**: Fázové checkpointy, Pravidla učení, Pre-compact uložení kontextu
2. **MEDIUM**: Minimální aktualizace postupu, Wrap-up sezení, Quality gates, Diagnostika prostředí, Kontextový replay poznatků
3. **LOW**: Pokročilé přizpůsobení hook systému

**Náročnost implementace:** 2-3 týdny (postupný rollout)

**Očekávaný dopad:**
- 40-60% snížení chat šumu
- 70%+ snížení opakovaných chyb
- Jasnější uživatelská kontrola nad autonomními procesy
- Lepší kontinuita mezi sezeními

---

**Další krok:** Implementovat Fázi 1 (Quick Wins) v nové feature branch `feature/pro-workflow-ux`
