# Remote Orchestration User Guide

English version. Czech version: [REMOTE_ORCHESTRATION_USER_GUIDE.cs.md](./REMOTE_ORCHESTRATION_USER_GUIDE.cs.md)

This guide is written for the operator who wants to install the remote-orchestration control-plane on a Linux or WSL host, authenticate Claude/Codex with CLI subscriptions, connect the host to Telegram, and start using it without hand-editing project files.

## 1. What this gives you

After setup you will have:

- one host-side control-plane process
- one SQLite runtime database under `.runtime/`
- one generated launcher script for Telegram polling
- project registration for one or more managed repos
- Claude Code and Codex routing through CLI subscription mode only
- Telegram commands and inline buttons for queueing and controlling work

This feature does not use provider API keys. It expects the provider CLIs to already be installed and logged in on the host.

## 2. Before you start

Prepare a Linux or WSL host with:

- Node.js `>=20`
- `git`
- `bash`
- optional: Docker, if you want container runs
- a Telegram bot token from BotFather
- at least one provider CLI installed and logged in:
  - `claude`
  - `codex`

Quick checks:

```bash
node -v
git --version
bash --version
which claude || true
which codex || true
docker --version || true
```

Preferred on WSL: a native Linux Node from `~/.nvm`, ideally `v20+` or `v22+`.
The runtime now prefers a native Linux Node from `~/.nvm` before it falls back to `node.exe`.

## 3. Install and authenticate the agent CLIs

### Claude Code

Install the Claude Code CLI on the host using the provider's normal subscription login flow. Then log in with your Claude subscription account:

```bash
claude auth login
claude auth status --json
```

After login, verify:

```bash
which claude
claude --version
```

Expected WSL path shape:

```bash
/home/<user>/.local/bin/claude
```

### Codex

On this host the current global Codex install is broken and needs reinstall first:

```bash
npm install -g @openai/codex@latest
```

Then start Codex and choose `Sign in with ChatGPT`:

```bash
codex
```

After login, verify:

```bash
which codex
codex --help
```

If `codex --help` fails with a missing optional dependency error, reinstall it and run `codex` again.

### Important rule

The control-plane stores only metadata about provider health and usage. Your real provider login state stays in the native CLI homes, typically:

- `~/.claude`
- `~/.codex`

If a CLI is missing or broken, the installer will mark it as unavailable and will not route work to it automatically.

## 4. Create and verify the Telegram bot

### 4.1 Create the bot token

In Telegram:

1. Open `@BotFather`
2. Run `/newbot`
3. Choose the bot name and username
4. Copy the token

### 4.2 Verify the token from the host

From the repo root:

```bash
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
```

Expected result:

- `ok` JSON payload with the bot username
- if this fails, the token is wrong or the bot is not reachable

### 4.3 Collect the Telegram IDs you need

Before the installer asks for allowed chat IDs and user IDs, send at least one message to the bot from:

- every Telegram chat that should control the project
- the operator account that should be allowed to approve or stop work

Then run:

```bash
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>"
```

This prints:

- `chat_ids`: discovered chat IDs from recent messages/callbacks
- `user_ids`: discovered Telegram user IDs
- `recent_updates`: recent messages or callback queries

Use those values in the installer wizard.

If you want to see the bot identity and recent update sources together:

```bash
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>" --limit 20
```

## 5. Install the control-plane for the current project

If the current repo is the project you want to manage:

```bash
git checkout feature/remote-orchestration
npm --prefix apps/control-plane run install:wizard
```

The wizard asks only for:

1. managed project repository path
2. project id
3. default branch
4. allowed Telegram chat IDs
5. allowed Telegram user IDs
6. Telegram bot token

The installer then:

- runs `npm install` and `npm run build`
- creates `.runtime/control-plane.db`
- creates `docs/ai/project-overrides/remote-control.yaml` only if it does not exist
- registers the project in the host SQLite DB
- auto-detects `claude` and `codex`
- probes provider session status
- writes `.runtime/install-summary.<project>.json`
- writes `.runtime/control-plane.env` if you entered the token
- writes `.runtime/run-control-plane.sh`
- writes runtime logs to `.runtime/control-plane.log`
- prints the exact run command

## 6. Install the control-plane for another project

If you keep this AAI repo as the host controller and want to manage a different repo, run:

```bash
npm --prefix apps/control-plane run install:host -- \
  --repo-path /mnt/z/AI/my-other-project \
  --project-id my-other-project \
  --default-branch main \
  --chat-ids 123456789 \
  --user-ids 987654321 \
  --telegram-bot-token "<BOT_TOKEN>"
```

This keeps:

- host runtime data in this AAI repo under `.runtime/`
- portable project policy in the managed project under `docs/ai/project-overrides/remote-control.yaml`

## 7. Check what the installer created

After the wizard or non-interactive install, inspect:

```bash
cat .runtime/install-summary.<project>.json
cat docs/ai/project-overrides/remote-control.yaml
cat .runtime/control-plane.env
```

Important files:

- host DB: `.runtime/control-plane.db`
- install summary: `.runtime/install-summary.<project>.json`
- runtime env: `.runtime/control-plane.env`
- runtime log: `.runtime/control-plane.log`
- generated launcher: `.runtime/run-control-plane.sh`
- portable project policy: `docs/ai/project-overrides/remote-control.yaml`

## 8. Verify agent authentication after install

Check what the control-plane thinks about provider availability:

```bash
npm --prefix apps/control-plane run auth:status -- --db .runtime/control-plane.db
```

If you want to re-probe a provider explicitly:

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

Current local Claude status can also be checked directly with:

```bash
claude auth status --json
```

Expected state:

- `status: "ok"` if the CLI exists and the probe succeeded
- `status: "missing"` if the CLI is not installed
- `status: "error"` if the CLI exists but the probe failed

## 9. Start the Telegram control-plane

If you entered the token during install:

```bash
bash .runtime/run-control-plane.sh
```

That is the preferred launch command because it uses the generated env file and approval config automatically.
It also appends structured daemon logs to `.runtime/control-plane.log`.
The launcher and npm wrapper pass `--no-warnings`, so the SQLite experimental warning should not appear during normal operator use.

If you did not enter the token during install, set it first:

```bash
export AAI_TELEGRAM_BOT_TOKEN="<BOT_TOKEN>"
npm --prefix apps/control-plane run telegram:serve -- \
  --db .runtime/control-plane.db \
  --token "$AAI_TELEGRAM_BOT_TOKEN" \
  --approval-config apps/control-plane/config/approval-gates.json
```

Watch what the daemon is doing:

```bash
tail -f .runtime/control-plane.log
npm --prefix apps/control-plane run logs:tail
```

## 10. Use the bot in Telegram

### 10.1 First contact

Open your bot chat and send:

```text
/projects
```

This should list registered projects.

If multiple projects are registered and no session default exists yet, use:

```text
/new
```

The bot will ask you to select a project first.

### 10.2 Create new work

```text
/intake <project_id> <ref_id> <summary>
```

Example:

```text
/intake my-other-project PRD-123 Add dockerized worker launcher
```

Alias:

```text
/new my-other-project PRD-123 Add dockerized worker launcher
```

### 10.3 Check status

```text
/status
/status <project_id> <ref_id>
```

### 10.4 See provider usage

```text
/usage
```

If no provider has synced machine-readable quota data yet, the bot now shows provider session status and tells you that quota telemetry has not been synced.
For Claude, the fallback status also includes the detected account email and subscription type when `claude auth status --json` is available.

### 10.5 Override provider

```text
/provider <project_id> <auto|claude|codex> [ref_id]
```

### 10.6 Resume or stop work

```text
/resume <project_id> <ref_id>
/stop <project_id> <ref_id>
```

Inline buttons also support:

- `Resume`
- `Stop`
- `Use Claude`
- `Use Codex`
- project picker selection

## 11. Run and inspect work from the host

Prepare a run:

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

Launch in Docker mode:

```bash
npm --prefix apps/control-plane run run:launch -- \
  --db .runtime/control-plane.db \
  --manifest .runtime/worktrees/my-other-project-PRD-123/run-manifest.json \
  --mode docker
```

Inspect the run:

```bash
npm --prefix apps/control-plane run run:inspect -- \
  --db .runtime/control-plane.db \
  --run-id <RUN_ID>
```

## 12. Recommended commands you will actually use

```bash
npm --prefix apps/control-plane run install:wizard
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>"
npm --prefix apps/control-plane run auth:status -- --db .runtime/control-plane.db
bash .runtime/run-control-plane.sh
npm --prefix apps/control-plane run validate:remote
```

## 13. Troubleshooting

### The installer says Claude or Codex is missing

That means the CLI binary was not found or could not be probed. Install the CLI on the host, log in with your subscription, then rerun:

```bash
npm --prefix apps/control-plane run install:wizard
```

or:

```bash
npm --prefix apps/control-plane run auth:probe -- --db .runtime/control-plane.db ...
```

For Claude subscription login on this host, the direct commands are:

```bash
claude auth login
claude auth status --json
```

For Codex on this host, reinstall first:

```bash
npm install -g @openai/codex@latest
codex
```

Then choose `Sign in with ChatGPT`.

### Telegram bot token works, but no IDs appear in `telegram:setup-info`

Send a fresh message to the bot from the target chat and then rerun:

```bash
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>"
```

### The bot starts but does not react in the correct project

Check:

- registered projects: `npm --prefix apps/control-plane run project:list -- --db .runtime/control-plane.db`
- Telegram ACLs in the project row
- current session default by sending `/projects` and `/new`

## 14. Validation

Run the full suite:

```bash
npm --prefix apps/control-plane run validate:remote
```

Target result:

- `27/27 PASS`

Focused checks:

```bash
npm --prefix apps/control-plane run test:remote:install
npm --prefix apps/control-plane run test:remote:provider-session
npm --prefix apps/control-plane run test:remote:telegram
npm --prefix apps/control-plane run test:remote:telegram-setup
npm --prefix apps/control-plane run test:remote:npm
```

## 15. Documentation sync rule

This guide must be kept in sync with:

- [REMOTE_ORCHESTRATION_USER_GUIDE.cs.md](./REMOTE_ORCHESTRATION_USER_GUIDE.cs.md)

Any future onboarding or command-surface change must update both language versions in the same change.
