#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";
import { closeDatabase, openDatabase, type DatabaseHandle } from "./db.ts";
import {
  chooseProvider,
  describeProviderCapacity,
  getProviderSession,
  listProviderSessions,
  loadUsageWindows,
  loadUsageWindowsFromDb,
  markProviderSessionMissing,
  probeProviderSession,
  validateAuthMode,
  type Provider
} from "./provider-router.ts";
import { parseArgs, printJson, readJson, requireArg, resolveMaybe, splitCsv, type CliArgs } from "./common.ts";
import { getProject, listProjects, loadProjectConfig, registerProject } from "./registry.ts";
import {
  approvalExists,
  createWorkItem,
  evaluateGate,
  getWorkItem,
  listWorkItems,
  recordApproval,
  updateWorkItemStatus,
  type GateContext
} from "./queue.ts";
import { buildHandoffPacket, getRun, launchRun, prepareRun, validateManifest, type RunManifest } from "./runner.ts";
import {
  getTelegramBotProfile,
  inspectTelegramSetup,
  interactiveModel,
  loadCommandRegistry,
  parseCallbackData,
  pollTelegramOnce,
  runTelegramDaemon,
  simulateTelegramCommand
} from "./telegram.ts";
import {
  DEFAULT_MOUNT_ALLOWLIST_PATH,
  generateAllowlistTemplate,
  loadMountAllowlist,
  validateMounts,
  type RequestedMount
} from "./mount-security.ts";

function openHandle(args: CliArgs): DatabaseHandle {
  return openDatabase(requireArg(args, "db"));
}

function maybeUsage(args: CliArgs, handle?: DatabaseHandle) {
  if (args["usage-file"]) {
    return loadUsageWindows(requireArg(args, "usage-file"));
  }
  if (handle) {
    return loadUsageWindowsFromDb(handle);
  }
  return [];
}

function maybeProjectConfig(args: CliArgs) {
  return args["project-config"] ? loadProjectConfig(requireArg(args, "project-config")) : null;
}

function normalizeGateContext(args: CliArgs): GateContext {
  return {
    prd_ref: typeof args["prd-ref"] === "string" ? args["prd-ref"] : null,
    frozen_spec_ref: typeof args["frozen-spec-ref"] === "string" ? args["frozen-spec-ref"] : null,
    test_plan_ref: typeof args["test-plan-ref"] === "string" ? args["test-plan-ref"] : null,
    project_selection: typeof args["project-selection"] === "string" ? args["project-selection"] : null,
    provider_selection_or_policy:
      typeof args["provider-selection-or-policy"] === "string" ? args["provider-selection-or-policy"] : null,
    worktree_manifest: typeof args["worktree-manifest"] === "string" ? args["worktree-manifest"] : null,
    implementation_summary:
      typeof args["implementation-summary"] === "string" ? args["implementation-summary"] : null,
    changed_file_summary: typeof args["changed-file-summary"] === "string" ? args["changed-file-summary"] : null,
    validation_command_set:
      typeof args["validation-command-set"] === "string" ? args["validation-command-set"] : null,
    report_target_path: typeof args["report-target-path"] === "string" ? args["report-target-path"] : null,
    evidence_target_path: typeof args["evidence-target-path"] === "string" ? args["evidence-target-path"] : null
  };
}

function help(): void {
  process.stdout.write(`AAI control-plane

Commands:
  init --db <path>
  project register --db <path> --project-config <yaml> --repo-path <path> [--chat-ids 1,2] [--user-ids 5,6]
  project list --db <path>
  project show --db <path> --project-id <id>
  auth validate --mode cli-subscription
  auth probe --db <path> --provider <claude|codex> --cli-path <path> --session-home <path> [--probe-args a,b] [--usage-args a,b]
  auth mark-missing --db <path> --provider <claude|codex> --session-home <path> [--cli-path <path>] [--message <text>]
  auth status --db <path> [--provider <claude|codex>]
  auth doctor --db <path> [--claude-cli-path <path>] [--claude-session-home <path>] [--codex-cli-path <path>] [--codex-session-home <path>]
  router choose --db <path> [--project-config <yaml>] [--usage-file <json>] [--phase implementation] [--provider auto] [--fallback codex]
  usage show [--db <path> | --usage-file <json>]
  queue create --db <path> --project-id <id> --ref-id <id> --phase <phase> --branch <branch> --provider <provider>
  queue status --db <path> --project-id <id> [--ref-id <id>]
  queue action --db <path> --project-id <id> --ref-id <id> --status <queued|running|blocked|stopped|done>
  approve check --gate <implementation|validation> [gate fields...]
  approve grant --db <path> --project-id <id> --ref-id <id> --gate <gate> --approved-by <user> --artifact-path <path>
  run prepare --db <path> --project-id <id> --ref-id <id> [--task-key <id>] [--parallel-group <id>] --repo-path <path> --worktrees-root <path> --container-image <image> --provider <provider> [--requirement-refs a,b] [--spec-refs a,b] [--report-refs a,b]
  run launch --db <path> --manifest <path> [--mode docker|process] [--worker-command <path>] [--docker-bin <path>] [--docker-args a,b]
  run inspect --db <path> --run-id <id>
  run validate --manifest <path>
  handoff build --db <path> --project-id <id> --ref-id <id> [--task-key <id>] [--parallel-group <id>] [--requirement-refs a,b] [--spec-refs a,b] [--report-refs a,b]
  telegram registry --config <json>
  telegram interactive
  telegram callback --data <action:target:ref>
  telegram get-me --token <bot-token> [--api-base <url>]
  telegram setup-info --token <bot-token> [--api-base <url>] [--limit 20]
  telegram poll --db <path> --token <bot-token> --approval-config <json> [--api-base <url>] [--once]
  telegram serve --db <path> --token <bot-token> --approval-config <json> [--api-base <url>] [--once] [--max-idle-cycles 10]
  telegram simulate --db <path> --command </intake|/approve|/resume|/stop|/status> --project-id <id> --ref-id <id>
  mounts template
  mounts validate [--allowlist <path>] --mounts <src|target|ro,...> [--project-role main|worker]
  defaults show --config <json>
`);
}

function parseMountSpecs(rawSpecs: string[]): RequestedMount[] {
  return rawSpecs.map((spec) => {
    const [source, target, mode = "ro"] = spec.split("|");
    if (!source || !target) {
      throw new Error(`Invalid mount spec: ${spec}`);
    }
    return {
      source,
      target,
      read_only: mode !== "rw"
    };
  });
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const [domain, action] = args._;

  try {
    if (!domain || domain === "help") {
      help();
      return;
    }

    if (domain === "init") {
      const handle = openHandle(args);
      closeDatabase(handle);
      printJson({ ok: true, db_path: handle.absolutePath });
      return;
    }

    if (domain === "project" && action === "register") {
      const config = loadProjectConfig(requireArg(args, "project-config"));
      const handle = openHandle(args);
      registerProject(handle, config, {
        local_repo_path: requireArg(args, "repo-path"),
        allowed_telegram_chat_ids: splitCsv(args["chat-ids"]),
        allowed_telegram_user_ids: splitCsv(args["user-ids"])
      });
      const project = getProject(handle, config.project_id);
      closeDatabase(handle);
      printJson({ ok: true, project });
      return;
    }

    if (domain === "project" && action === "list") {
      const handle = openHandle(args);
      const projects = listProjects(handle);
      closeDatabase(handle);
      printJson({ projects });
      return;
    }

    if (domain === "project" && action === "show") {
      const handle = openHandle(args);
      const project = getProject(handle, requireArg(args, "project-id"));
      closeDatabase(handle);
      printJson({ project });
      return;
    }

    if (domain === "auth" && action === "validate") {
      printJson(validateAuthMode(requireArg(args, "mode")));
      return;
    }

    if (domain === "auth" && action === "probe") {
      const handle = openHandle(args);
      const result = probeProviderSession(handle, {
        provider: requireArg(args, "provider") as Provider,
        cli_path: requireArg(args, "cli-path"),
        session_home: requireArg(args, "session-home"),
        account_label: typeof args["account-label"] === "string" ? args["account-label"] : null,
        probe_args: splitCsv(args["probe-args"]),
        usage_args: splitCsv(args["usage-args"])
      });
      closeDatabase(handle);
      printJson(result);
      return;
    }

    if (domain === "auth" && action === "mark-missing") {
      const handle = openHandle(args);
      const session = markProviderSessionMissing(handle, {
        provider: requireArg(args, "provider") as Provider,
        session_home: requireArg(args, "session-home"),
        cli_path: typeof args["cli-path"] === "string" ? args["cli-path"] : undefined,
        account_label: typeof args["account-label"] === "string" ? args["account-label"] : null,
        message: typeof args.message === "string" ? args.message : undefined
      });
      closeDatabase(handle);
      printJson({ session });
      return;
    }

    if (domain === "auth" && action === "status") {
      const handle = openHandle(args);
      const provider = typeof args.provider === "string" ? (args.provider as Provider) : null;
      const payload = provider ? getProviderSession(handle, provider) : listProviderSessions(handle);
      closeDatabase(handle);
      printJson(provider ? { session: payload } : { sessions: payload });
      return;
    }

    if (domain === "auth" && action === "doctor") {
      const handle = openHandle(args);
      const providers: Provider[] = ["claude", "codex"];
      for (const provider of providers) {
        const cliPathKey = `${provider}-cli-path`;
        const sessionHomeKey = `${provider}-session-home`;
        const cliPath = typeof args[cliPathKey] === "string" ? String(args[cliPathKey]) : "";
        const sessionHome = typeof args[sessionHomeKey] === "string" ? String(args[sessionHomeKey]) : "";

        if (!sessionHome) {
          continue;
        }

        if (!cliPath) {
          markProviderSessionMissing(handle, {
            provider,
            session_home: sessionHome,
            message: `${provider} CLI is not installed on this host.`
          });
          continue;
        }

        probeProviderSession(handle, {
          provider,
          cli_path: cliPath,
          session_home: sessionHome
        });
      }

      const sessions = listProviderSessions(handle);
      const usage = loadUsageWindowsFromDb(handle);
      const capacities = sessions.map((session) =>
        describeProviderCapacity({
          provider: session.provider,
          usage,
          sessions
        })
      );
      closeDatabase(handle);
      printJson({ sessions, usage_windows: usage, capacities });
      return;
    }

    if (domain === "router" && action === "choose") {
      const handle = args.db ? openHandle(args) : undefined;
      const projectConfig = maybeProjectConfig(args);
      const usage = maybeUsage(args, handle);
      const sessions = handle ? listProviderSessions(handle) : [];
      const phase = typeof args.phase === "string" ? args.phase : "implementation";
      const decision = chooseProvider({
        policy: typeof args.provider === "string" ? args.provider : projectConfig?.default_provider_policy,
        fallback: (typeof args.fallback === "string" ? args.fallback : "codex") as Provider,
        strictSingleProvider: args.strict === "true",
        operatorOverride: typeof args.override === "string" ? args.override : null,
        usage,
        phasePreference: projectConfig?.phase_provider_preferences?.[phase] || "auto",
        sessions
      });
      const capacities = ["claude", "codex"].map((provider) =>
        describeProviderCapacity({
          provider: provider as Provider,
          usage,
          sessions
        })
      );
      if (handle) {
        closeDatabase(handle);
      }
      printJson({
        phase,
        decision,
        usage,
        sessions,
        capacities,
        selected_capacity: capacities.find((entry) => entry.provider === decision.provider) || null
      });
      return;
    }

    if (domain === "usage" && action === "show") {
      if (args.db) {
        const handle = openHandle(args);
        const windows = loadUsageWindowsFromDb(handle);
        const sessions = listProviderSessions(handle);
        const capacities = ["claude", "codex"].map((provider) =>
          describeProviderCapacity({
            provider: provider as Provider,
            usage: windows,
            sessions
          })
        );
        closeDatabase(handle);
        printJson({ windows, sessions, capacities });
      } else {
        const windows = loadUsageWindows(requireArg(args, "usage-file"));
        const capacities = ["claude", "codex"].map((provider) =>
          describeProviderCapacity({
            provider: provider as Provider,
            usage: windows,
            sessions: []
          })
        );
        printJson({
          windows,
          providers: windows.map((entry) => ({
            provider: entry.provider,
            window_label: entry.window_label,
            used_percentage: entry.used_percentage,
            reset_at_utc: entry.reset_at_utc
          })),
          capacities
        });
      }
      return;
    }

    if (domain === "queue" && action === "create") {
      const handle = openHandle(args);
      const projectId = requireArg(args, "project-id");
      const refId = requireArg(args, "ref-id");
      createWorkItem(handle, {
        project_id: projectId,
        ref_id: refId,
        branch: requireArg(args, "branch"),
        phase: requireArg(args, "phase"),
        status: typeof args.status === "string" ? args.status : "queued",
        provider: requireArg(args, "provider"),
        manifest_path: resolveMaybe(args["manifest-path"]),
        summary: typeof args.summary === "string" ? args.summary : null
      });
      const workItem = getWorkItem(handle, projectId, refId);
      closeDatabase(handle);
      printJson({ work_item: workItem });
      return;
    }

    if (domain === "queue" && action === "status") {
      const handle = openHandle(args);
      const projectId = requireArg(args, "project-id");
      const payload =
        typeof args["ref-id"] === "string"
          ? { work_item: getWorkItem(handle, projectId, requireArg(args, "ref-id")) }
          : { work_items: listWorkItems(handle, projectId) };
      closeDatabase(handle);
      printJson(payload);
      return;
    }

    if (domain === "queue" && action === "action") {
      const handle = openHandle(args);
      const workItem = updateWorkItemStatus(
        handle,
        requireArg(args, "project-id"),
        requireArg(args, "ref-id"),
        requireArg(args, "status")
      );
      closeDatabase(handle);
      printJson({ work_item: workItem });
      return;
    }

    if (domain === "approve" && action === "check") {
      const configPath = fileURLToPath(new URL("../config/approval-gates.json", import.meta.url));
      const gatesConfig = readJson<Record<string, string[]>>(configPath);
      printJson(evaluateGate(gatesConfig, requireArg(args, "gate") as "implementation" | "validation", normalizeGateContext(args)));
      return;
    }

    if (domain === "approve" && action === "grant") {
      const handle = openHandle(args);
      recordApproval(handle, {
        project_id: requireArg(args, "project-id"),
        ref_id: requireArg(args, "ref-id"),
        gate: requireArg(args, "gate"),
        approved_by: requireArg(args, "approved-by"),
        artifact_path: path.resolve(requireArg(args, "artifact-path"))
      });
      closeDatabase(handle);
      printJson({ ok: true });
      return;
    }

    if (domain === "run" && action === "prepare") {
      const handle = openHandle(args);
      const projectConfig = maybeProjectConfig(args);
      const usage = maybeUsage(args, handle);
      const sessions = listProviderSessions(handle);
      const phase = typeof args.phase === "string" ? args.phase : "implementation";
      const decision = chooseProvider({
        policy: typeof args.provider === "string" ? args.provider : projectConfig?.default_provider_policy,
        fallback: (typeof args.fallback === "string" ? args.fallback : "codex") as Provider,
        strictSingleProvider: args.strict === "true",
        operatorOverride: typeof args.override === "string" ? args.override : null,
        usage,
        phasePreference: projectConfig?.phase_provider_preferences?.[phase] || "auto",
        sessions
      });
      const result = prepareRun(handle, {
        project_id: requireArg(args, "project-id"),
        ref_id: requireArg(args, "ref-id"),
        task_key: typeof args["task-key"] === "string" ? args["task-key"] : null,
        parallel_group: typeof args["parallel-group"] === "string" ? args["parallel-group"] : null,
        repo_path: requireArg(args, "repo-path"),
        worktrees_root: requireArg(args, "worktrees-root"),
        provider: decision.provider,
        branch: typeof args.branch === "string" ? args.branch : null,
        manifest_path: typeof args["manifest-path"] === "string" ? args["manifest-path"] : null,
        container_image: requireArg(args, "container-image"),
        input_refs: splitCsv(args["input-refs"]),
        output_artifacts: splitCsv(args["output-artifacts"]),
        requirement_refs: splitCsv(args["requirement-refs"]),
        spec_refs: splitCsv(args["spec-refs"]),
        report_refs: splitCsv(args["report-refs"]),
        read_only_mounts: splitCsv(args["read-only-mounts"]).map((entry) => {
          const [source, target] = entry.split("|");
          return { source, target };
        }),
        validated_extra_mounts: (() => {
          const rawSpecs = splitCsv(args["extra-mounts"]);
          if (rawSpecs.length === 0) {
            return [];
          }
          const allowlist = loadMountAllowlist(
            typeof args["mount-allowlist"] === "string" ? args["mount-allowlist"] : DEFAULT_MOUNT_ALLOWLIST_PATH
          );
          const validation = validateMounts(
            parseMountSpecs(rawSpecs),
            allowlist,
            (typeof args["project-role"] === "string" ? args["project-role"] : "main") === "main"
          );
          if (validation.rejected.length > 0) {
            throw new Error(validation.rejected.map((entry) => entry.reason).join("; "));
          }
          return validation.accepted;
        })()
      });
      closeDatabase(handle);
      printJson({ decision, ...result });
      return;
    }

    if (domain === "run" && action === "launch") {
      const handle = openHandle(args);
      const result = launchRun(handle, {
        manifest_path: requireArg(args, "manifest"),
        mode: (typeof args.mode === "string" ? args.mode : "docker") as "docker" | "process",
        worker_command: typeof args["worker-command"] === "string" ? args["worker-command"] : null,
        docker_bin: typeof args["docker-bin"] === "string" ? args["docker-bin"] : null,
        docker_args: splitCsv(args["docker-args"])
      });
      closeDatabase(handle);
      printJson(result);
      return;
    }

    if (domain === "run" && action === "inspect") {
      const handle = openHandle(args);
      const run = getRun(handle, requireArg(args, "run-id"));
      closeDatabase(handle);
      printJson({ run });
      return;
    }

    if (domain === "run" && action === "validate") {
      const manifest = readJson<Partial<RunManifest>>(requireArg(args, "manifest"));
      printJson(validateManifest(manifest));
      return;
    }

    if (domain === "handoff" && action === "build") {
      const handle = openHandle(args);
      const packet = buildHandoffPacket(handle, {
        project_id: requireArg(args, "project-id"),
        ref_id: requireArg(args, "ref-id"),
        task_key: typeof args["task-key"] === "string" ? args["task-key"] : null,
        parallel_group: typeof args["parallel-group"] === "string" ? args["parallel-group"] : null,
        requirement_refs: splitCsv(args["requirement-refs"]),
        spec_refs: splitCsv(args["spec-refs"]),
        report_refs: splitCsv(args["report-refs"])
      });
      closeDatabase(handle);
      printJson(packet);
      return;
    }

    if (domain === "telegram" && action === "registry") {
      printJson(loadCommandRegistry(requireArg(args, "config")));
      return;
    }

    if (domain === "telegram" && action === "interactive") {
      printJson(interactiveModel());
      return;
    }

    if (domain === "telegram" && action === "callback") {
      printJson(parseCallbackData(requireArg(args, "data")));
      return;
    }

    if (domain === "telegram" && action === "get-me") {
      const result = await getTelegramBotProfile({
        token: requireArg(args, "token"),
        api_base: typeof args["api-base"] === "string" ? args["api-base"] : undefined
      });
      printJson(result);
      return;
    }

    if (domain === "telegram" && action === "setup-info") {
      const result = await inspectTelegramSetup({
        token: requireArg(args, "token"),
        api_base: typeof args["api-base"] === "string" ? args["api-base"] : undefined,
        limit: typeof args.limit === "string" ? Number(args.limit) : undefined
      });
      printJson(result);
      return;
    }

    if (domain === "telegram" && action === "poll") {
      const handle = openHandle(args);
      const result = await pollTelegramOnce(handle, {
        token: requireArg(args, "token"),
        api_base: typeof args["api-base"] === "string" ? args["api-base"] : undefined,
        approval_config: readJson<Record<string, string[]>>(requireArg(args, "approval-config")),
        once: args.once === true
      });
      closeDatabase(handle);
      printJson(result);
      return;
    }

    if (domain === "telegram" && action === "serve") {
      const handle = openHandle(args);
      const result = await runTelegramDaemon(handle, {
        token: requireArg(args, "token"),
        api_base: typeof args["api-base"] === "string" ? args["api-base"] : undefined,
        approval_config: readJson<Record<string, string[]>>(requireArg(args, "approval-config")),
        once: args.once === true,
        max_idle_cycles: typeof args["max-idle-cycles"] === "string" ? Number(args["max-idle-cycles"]) : undefined,
        poll_interval_ms: typeof args["poll-interval-ms"] === "string" ? Number(args["poll-interval-ms"]) : undefined
      });
      closeDatabase(handle);
      printJson(result);
      return;
    }

    if (domain === "telegram" && action === "simulate") {
      const handle = openHandle(args);
      const result = simulateTelegramCommand(handle, {
        command: requireArg(args, "command"),
        project_id: requireArg(args, "project-id"),
        ref_id: requireArg(args, "ref-id"),
        provider: typeof args.provider === "string" ? args.provider : "auto",
        phase: typeof args.phase === "string" ? args.phase : "planning",
        branch: typeof args.branch === "string" ? args.branch : null,
        summary: typeof args.summary === "string" ? args.summary : null
      });
      closeDatabase(handle);
      printJson(result);
      return;
    }

    if (domain === "defaults" && action === "show") {
      printJson(readJson<Record<string, unknown>>(requireArg(args, "config")));
      return;
    }

    if (domain === "mounts" && action === "template") {
      printJson(generateAllowlistTemplate());
      return;
    }

    if (domain === "mounts" && action === "validate") {
      const allowlist = loadMountAllowlist(
        typeof args.allowlist === "string" ? args.allowlist : DEFAULT_MOUNT_ALLOWLIST_PATH
      );
      const mounts = parseMountSpecs(splitCsv(args.mounts));
      printJson(
        validateMounts(
          mounts,
          allowlist,
          (typeof args["project-role"] === "string" ? args["project-role"] : "main") === "main"
        )
      );
      return;
    }

    if (domain === "policy" && action === "show") {
      printJson(maybeProjectConfig(args));
      return;
    }

    if (domain === "approval" && action === "exists") {
      const handle = openHandle(args);
      const exists = approvalExists(handle, requireArg(args, "project-id"), requireArg(args, "ref-id"), requireArg(args, "gate"));
      closeDatabase(handle);
      printJson({ exists });
      return;
    }

    throw new Error(`Unknown command: ${args._.join(" ")}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  }
}

await main();
