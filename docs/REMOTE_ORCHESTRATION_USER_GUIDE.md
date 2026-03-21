# Remote Orchestration User Guide

English version. Czech version: [REMOTE_ORCHESTRATION_USER_GUIDE.cs.md](./REMOTE_ORCHESTRATION_USER_GUIDE.cs.md)

This guide is for the operator who wants the shortest possible path from "I have a repo and a Telegram bot" to "the control-plane is running in the background and I can manage it with simple commands".

## 1. What this setup does

After setup you will have:

- one host-side control-plane daemon
- one SQLite runtime database in `.runtime/`
- one generated launcher script for background start, status, stop, restart, logs, probe, and login
- project registration for one or more managed repos
- Claude Code and Codex routing through CLI subscription mode only
- Telegram commands and inline actions for queueing and controlling work

This feature does not use provider API keys. It uses only the native Claude Code and Codex CLI subscription sessions on the host.

## 2. Before you start

Prepare a Linux or WSL host with:

- Node.js `>=20`
- `git`
- `bash`
- optional: Docker, if you want container runs
- a Telegram bot token from BotFather
- at least one provider CLI installed or ready to install:
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

## 3. Sign in to Claude or Codex with your subscription

### Claude Code

If `claude` is installed:

```bash
claude auth login
claude auth status --json
which claude
```

Expected WSL path shape:

```bash
/home/<user>/.local/bin/claude
```

If `claude auth status --json` says you are logged in, Claude is ready for the control-plane.

### Codex

If `codex` is missing or broken, reinstall it first:

```bash
npm install -g @openai/codex@latest
```

Then start Codex and choose `Sign in with ChatGPT`:

```bash
codex
which codex
codex --help
```

If `codex --help` fails with an optional dependency error, reinstall and run `codex` again.

### Important rule

Your real login state stays in the native CLI homes, typically:

- `~/.claude`
- `~/.codex`

The control-plane stores only host-side metadata about whether the CLI exists, whether the probe passed, and whether usage telemetry was collected.

## 4. Create the Telegram bot and collect the IDs

### 4.1 Create the bot token

In Telegram:

1. Open `@BotFather`
2. Run `/newbot`
3. Choose the bot name and username
4. Copy the token

### 4.2 Verify the token from the host

```bash
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
```

Expected result:

- JSON with the bot username and bot id

### 4.3 Find the chat IDs and user IDs

Before running the installer:

1. Send at least one message to the bot from every Telegram chat that should control the project.
2. Send at least one message from every user who should be allowed to approve, resume, or stop work.

Then run:

```bash
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>" --limit 20
```

This prints:

- `chat_ids`
- `user_ids`
- recent messages or callback sources

Use those values in the installer wizard.

## 5. Run the installer

If this repo is the host controller and also the project you want to manage:

```bash
npm --prefix apps/control-plane run install:wizard
```

The wizard keeps the operator input short. It asks for:

1. managed project repository path
2. project id
3. default branch
4. allowed Telegram chat IDs
5. allowed Telegram user IDs
6. Telegram bot token

The wizard then:

- runs `npm install` and `npm run build`
- creates or reuses `.runtime/control-plane.db`
- creates `docs/ai/project-overrides/remote-control.yaml` only if needed
- registers the project in the host SQLite DB
- auto-detects `claude` and `codex`
- probes provider login state
- offers interactive `claude` or `codex` login if the CLI exists but the probe is not `ok`
- writes `.runtime/install-summary.<project>.json`
- writes `.runtime/control-plane.env`
- writes `.runtime/run-control-plane.sh`
- writes runtime logs to `.runtime/control-plane.log`

When you rerun the wizard later, it reuses the last known values. In practice that means:

- pressing Enter keeps the current repository path, project id, branch, chat IDs, user IDs, and token
- existing values from `docs/ai/project-overrides/remote-control.yaml` are reused as defaults when the installer needs to rewrite the project config
- the token is shown masked
- if existing config or runtime files are found, the wizard asks `Overwrite existing config/runtime state? [y/N]`

Meaning of the state choice:

- `N` or Enter keeps the current config, DB, env, launcher, and summary files
- `y` rewrites config/runtime files and recreates the SQLite DB from scratch

Non-interactive equivalent:

```bash
npm --prefix apps/control-plane run install:host -- --preserve-existing ...
npm --prefix apps/control-plane run install:host -- --overwrite-existing ...
```

## 6. Verify the provider login state after install

The simplest operator command is:

```bash
bash .runtime/run-control-plane.sh probe
```

This re-checks both providers and prints a readable summary.

Status meaning:

- `ok` means the CLI exists and the login probe succeeded
- `missing` means the CLI is not installed on the host
- `error` means the CLI exists, but login or the probe failed

Direct low-level status commands:

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

If you only want to verify Claude directly:

```bash
claude auth status --json
```

## 7. Start the control-plane in the background

After the installer has written `.runtime/control-plane.env`, use:

```bash
bash .runtime/run-control-plane.sh start
```

This is the recommended startup command. It:

- uses the generated env file automatically
- starts the Telegram daemon in the background
- returns control to the shell immediately

The launcher and CLI wrapper pass `--no-warnings`, so the `node:sqlite` experimental warning should not appear during normal operator use.

## 8. Daily operator commands

Background control:

```bash
bash .runtime/run-control-plane.sh status
bash .runtime/run-control-plane.sh stop
bash .runtime/run-control-plane.sh restart
bash .runtime/run-control-plane.sh logs
```

Provider login and re-check:

```bash
bash .runtime/run-control-plane.sh login claude
bash .runtime/run-control-plane.sh login codex
bash .runtime/run-control-plane.sh probe
```

What each `run-control-plane.sh` command does:

- `start`
  Starts the Telegram control-plane in the background and returns immediately to the shell. Use this for normal daily startup.
- `run`
  Starts the same daemon in the foreground. Use this only when you want to watch it directly in the current terminal for debugging.
- `status`
  Shows whether the daemon is running, its PID, DB path, log paths, whether the Telegram token is configured, current provider session health, and the active project binding.
- `stop`
  Stops the background daemon and removes the stale PID file if the process is already gone.
- `restart`
  Stops the daemon and starts it again with the same generated env file.
- `logs`
  Tails the structured runtime log. Use this when the daemon is already running and you want to see what it is doing.
- `probe`
  Re-checks Claude and Codex availability and login state, then prints a readable summary including usage telemetry availability.
- `login claude`
  Opens the native Claude interactive login flow on the host and then re-probes Claude.
- `login codex`
  Opens the native Codex interactive login flow on the host and then re-probes Codex.

Equivalent npm shortcuts:

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

`status` shows:

- whether the daemon is running
- PID, DB path, and log paths
- whether the Telegram token is configured
- readable provider session status
- readable project registration summary

## 9. Watch logs

```bash
bash .runtime/run-control-plane.sh logs
```

or:

```bash
npm --prefix apps/control-plane run daemon:logs
```

The structured log is also written to:

- `.runtime/control-plane.log`

## 10. Use the bot in Telegram

### 10.1 List projects

```text
/projects
```

### 10.2 Create work

```text
/intake <project_id> <ref_id> <summary>
```

Alias:

```text
/new <project_id> <ref_id> <summary>
```

### 10.3 Check status

```text
/status
/status <project_id> <ref_id>
```

### 10.4 Check provider usage

```text
/usage
```

If quota telemetry is not available yet, the bot falls back to readable provider session state instead of only saying that usage is unavailable.

### 10.5 Override provider

```text
/provider <project_id> <auto|claude|codex> [ref_id]
```

### 10.6 Resume or stop work

```text
/resume <project_id> <ref_id>
/stop <project_id> <ref_id>
```

Inline actions support:

- `Resume`
- `Stop`
- `Use Claude`
- `Use Codex`
- project picker selection

## 11. Short command set most operators need

```bash
npm --prefix apps/control-plane run install:wizard
npm --silent --prefix apps/control-plane run telegram:get-me -- --token "<BOT_TOKEN>"
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>"
bash .runtime/run-control-plane.sh probe
bash .runtime/run-control-plane.sh start
bash .runtime/run-control-plane.sh status
bash .runtime/run-control-plane.sh logs
```

## 12. Troubleshooting

### Claude or Codex is missing

Install or reinstall the CLI, log in, then run:

```bash
bash .runtime/run-control-plane.sh probe
```

or rerun the wizard:

```bash
npm --prefix apps/control-plane run install:wizard
```

### The easiest host-side login flow

```bash
bash .runtime/run-control-plane.sh login claude
bash .runtime/run-control-plane.sh login codex
bash .runtime/run-control-plane.sh probe
```

### Telegram bot token works, but `telegram:setup-info` shows no IDs

Send a fresh message to the bot from the target chat, then rerun:

```bash
npm --silent --prefix apps/control-plane run telegram:setup-info -- --token "<BOT_TOKEN>" --limit 20
```

### The daemon is running, but Telegram does nothing

Check:

- `bash .runtime/run-control-plane.sh status`
- `bash .runtime/run-control-plane.sh logs`
- whether the correct chat IDs and user IDs were registered

## 13. Validation

Run the full suite:

```bash
npm --prefix apps/control-plane run validate:remote
```

Current expected result:

- readable `[ OK ]` or `[FAIL]` output for each test
- final summary listing passed and failed test names
- `30` passing tests in the current suite

Focused checks:

```bash
npm --prefix apps/control-plane run test:remote:install
npm --prefix apps/control-plane run test:remote:provider-session
npm --prefix apps/control-plane run test:remote:telegram
npm --prefix apps/control-plane run test:remote:telegram-setup
npm --prefix apps/control-plane run test:remote:daemon
npm --prefix apps/control-plane run test:remote:npm
```

## 14. Documentation sync rule

This guide must be kept in sync with:

- [REMOTE_ORCHESTRATION_USER_GUIDE.cs.md](./REMOTE_ORCHESTRATION_USER_GUIDE.cs.md)

Any future onboarding or command-surface change must update both language versions in the same change.
