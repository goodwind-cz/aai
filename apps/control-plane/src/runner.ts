import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import type { DatabaseHandle } from "./db.ts";
import { ensureDir, nowUtc, shellQuote, writeJson } from "./common.ts";
import { getProject } from "./registry.ts";
import { getProviderSession, type Provider } from "./provider-router.ts";

export type RunManifest = {
  run_id: string;
  project_id: string;
  ref_id: string;
  task_key: string | null;
  parallel_group: string | null;
  provider: string;
  branch: string;
  worktree_path: string;
  container_image: string;
  mounts: Array<{ source: string; target: string; read_only: boolean }>;
  commit_sha: string;
  input_refs: string[];
  output_artifacts: string[];
  portable_project_config_path: string | null;
  handoff_packet_path: string;
  handoff_target_path: string;
  provider_session:
    | {
        provider: string;
        auth_mode: "cli-subscription";
        status: "ok" | "missing" | "error";
        account_label: string | null;
        host_cli_path: string;
        host_session_home: string;
        mounted_session_home: string;
        cli_command_hint: string;
      }
    | null;
  memory_contract: {
    canonical_repo_sources: string[];
    handoff_packet_path: string;
    hidden_shared_memory_required: false;
    task_transfer: "repo-docs-plus-explicit-handoff";
  };
  created_at_utc: string;
};

export type RunLaunchResult = {
  run_id: string;
  status: "running" | "done" | "failed";
  exit_code: number;
  log_path: string;
  command: string;
};

function gitCommand(repoPath: string, args: string[]): { ok: boolean; stdout: string; stderr: string } {
  const result = spawnSync("git", ["-C", repoPath, ...args], { encoding: "utf8" });
  return {
    ok: result.status === 0,
    stdout: result.stdout || "",
    stderr: result.stderr || ""
  };
}

function gitCommitSha(repoPath: string): string {
  const result = gitCommand(repoPath, ["rev-parse", "HEAD"]);
  return result.ok ? result.stdout.trim() : "unknown";
}

function ensureGitWorktree(repoPath: string, branch: string, worktreePath: string): void {
  const rootProbe = gitCommand(repoPath, ["rev-parse", "--show-toplevel"]);
  if (!rootProbe.ok) {
    ensureDir(worktreePath);
    return;
  }

  if (fs.existsSync(worktreePath) && fs.readdirSync(worktreePath).length > 0) {
    const worktreeProbe = gitCommand(worktreePath, ["rev-parse", "--show-toplevel"]);
    if (worktreeProbe.ok) {
      return;
    }
    fs.rmSync(worktreePath, { recursive: true, force: true });
  }

  ensureDir(path.dirname(worktreePath));
  const addResult = gitCommand(repoPath, ["worktree", "add", "--force", "-B", branch, worktreePath, "HEAD"]);
  if (!addResult.ok) {
    throw new Error(`Failed to create git worktree: ${addResult.stderr.trim() || addResult.stdout.trim()}`);
  }
}

export function prepareRun(
  handle: DatabaseHandle | null,
  options: {
    project_id: string;
    ref_id: string;
    task_key?: string | null;
    parallel_group?: string | null;
    repo_path: string;
    worktrees_root: string;
    provider: string;
    branch?: string | null;
    manifest_path?: string | null;
    container_image: string;
    input_refs?: string[];
    output_artifacts?: string[];
    requirement_refs?: string[];
    spec_refs?: string[];
    report_refs?: string[];
    read_only_mounts?: Array<{ source: string; target: string }>;
    validated_extra_mounts?: Array<{ source: string; target: string; read_only: boolean }>;
  }
): { manifest: RunManifest; manifest_path: string } {
  const taskKey = normalizeTaskKey(options.task_key);
  const parallelGroup = normalizeTaskKey(options.parallel_group);
  const taskSuffix = taskKey ? `-${taskKey}` : "";
  const runId = `${options.project_id}-${options.ref_id}${taskSuffix}-${Date.now()}`;
  const branch = options.branch || `aai/${options.ref_id.toLowerCase()}${taskKey ? `--${taskKey}` : ""}`;
  const worktreePath = path.resolve(options.worktrees_root, `${options.project_id}-${options.ref_id}${taskSuffix}`);
  ensureGitWorktree(options.repo_path, branch, worktreePath);

  const manifestPath = path.resolve(options.manifest_path || path.join(worktreePath, "run-manifest.json"));
  const handoffPacketPath = path.join(worktreePath, ".aai-handoff.json");
  const providerSession = resolveProviderSession(handle, options.provider);
  const project = safeGetProject(handle, options.project_id);
  const memoryContract = buildRunHandoffPacket(handle, {
    project_id: options.project_id,
    ref_id: options.ref_id,
    task_key: taskKey,
    parallel_group: parallelGroup,
    requirement_refs: options.requirement_refs || [],
    spec_refs: options.spec_refs || [],
    report_refs: options.report_refs || [],
    worktree_path: worktreePath,
    portable_project_config_path:
      project && typeof project.portable_config_path === "string" ? project.portable_config_path : null,
    provider_session: providerSession
  });
  writeJson(handoffPacketPath, memoryContract);
  const manifest: RunManifest = {
    run_id: runId,
    project_id: options.project_id,
    ref_id: options.ref_id,
    task_key: taskKey,
    parallel_group: parallelGroup,
    provider: options.provider,
    branch,
    worktree_path: worktreePath,
    container_image: options.container_image,
    mounts: [
      {
        source: worktreePath,
        target: "/workspace",
        read_only: false
      },
      ...(providerSession
        ? [
            {
              source: providerSession.host_session_home,
              target: providerSession.mounted_session_home,
              read_only: true
            }
          ]
        : []),
      ...(options.read_only_mounts || []).map((mount) => ({
        source: path.resolve(mount.source),
        target: mount.target,
        read_only: true
      })),
      ...(options.validated_extra_mounts || []).map((mount) => ({
        source: path.resolve(mount.source),
        target: mount.target,
        read_only: mount.read_only
      }))
    ],
    commit_sha: gitCommitSha(worktreePath),
    input_refs: options.input_refs || [],
    output_artifacts: options.output_artifacts || [],
    portable_project_config_path:
      project && typeof project.portable_config_path === "string" ? String(project.portable_config_path) : null,
    handoff_packet_path: handoffPacketPath,
    handoff_target_path: "/workspace/.aai-handoff.json",
    provider_session: providerSession,
    memory_contract: {
      canonical_repo_sources: [
        "/workspace/docs",
        "/workspace/docs/requirements",
        "/workspace/docs/specs",
        "/workspace/docs/decisions",
        "/workspace/docs/knowledge"
      ],
      handoff_packet_path: "/workspace/.aai-handoff.json",
      hidden_shared_memory_required: false,
      task_transfer: "repo-docs-plus-explicit-handoff"
    },
    created_at_utc: nowUtc()
  };

  writeJson(manifestPath, manifest);
  fs.writeFileSync(
    path.join(worktreePath, ".aai-control-plane-run.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
    "utf8"
  );

  if (handle) {
    const statement = handle.database.prepare(`
      INSERT INTO run_registry (
        run_id,
        project_id,
        ref_id,
        provider,
        status,
        created_at_utc,
        manifest_path,
        started_at_utc,
        finished_at_utc,
        exit_code,
        log_path
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(run_id) DO UPDATE SET
        manifest_path = excluded.manifest_path
    `);
    statement.run(runId, options.project_id, options.ref_id, options.provider, "prepared", nowUtc(), manifestPath, null, null, null, null);
  }

  return { manifest, manifest_path: manifestPath };
}

export function launchRun(
  handle: DatabaseHandle,
  options: {
    manifest_path: string;
    mode?: "docker" | "process";
    worker_command?: string | null;
    docker_bin?: string | null;
    docker_args?: string[];
  }
): RunLaunchResult {
  const manifest = JSON.parse(fs.readFileSync(options.manifest_path, "utf8")) as RunManifest;
  const logsDir = path.join(path.dirname(options.manifest_path), "logs");
  ensureDir(logsDir);
  const logPath = path.join(logsDir, `${manifest.run_id}.log`);
  const startedAt = nowUtc();

  let commandDescription = "";
  let result;
  if ((options.mode || "docker") === "process") {
    const workerCommand = options.worker_command ? path.resolve(options.worker_command) : null;
    if (!workerCommand || !fs.existsSync(workerCommand)) {
      throw new Error("Process launch mode requires an existing --worker-command");
    }
    const executable = isNodeScript(workerCommand) ? process.execPath : workerCommand;
    const finalArgs = isNodeScript(workerCommand) ? [workerCommand, options.manifest_path] : [options.manifest_path];
    commandDescription = [shellQuote(executable), ...finalArgs.map(shellQuote)].join(" ");
    result = spawnSync(executable, finalArgs, {
      encoding: "utf8",
      env: {
        ...process.env,
        AAI_RUN_MANIFEST: options.manifest_path,
        AAI_HANDOFF_PACKET: manifest.handoff_packet_path,
        AAI_RUN_WORKTREE: manifest.worktree_path,
        AAI_RUN_ID: manifest.run_id,
        ...(manifest.provider_session
          ? {
              AAI_PROVIDER: manifest.provider_session.provider,
              AAI_PROVIDER_SESSION_HOME: manifest.provider_session.host_session_home,
              AAI_PROVIDER_CLI_HINT: manifest.provider_session.cli_command_hint,
              AAI_PROVIDER_ACCOUNT_LABEL: manifest.provider_session.account_label || ""
            }
          : {})
      }
    });
  } else {
    const dockerBin = options.docker_bin || "docker";
    const dockerArgs = [
      "run",
      "--rm",
      "--name",
      manifest.run_id.replace(/[^A-Za-z0-9_.-]/g, "-"),
      ...manifest.mounts.flatMap((mount) => ["-v", `${mount.source}:${mount.target}${mount.read_only ? ":ro" : ""}`]),
      "-e",
      "AAI_RUN_MANIFEST=/workspace/.aai-control-plane-run.json",
      "-e",
      `AAI_HANDOFF_PACKET=${manifest.handoff_target_path}`,
      "-e",
      `AAI_RUN_ID=${manifest.run_id}`,
      ...(manifest.provider_session
        ? [
            "-e",
            `AAI_PROVIDER=${manifest.provider_session.provider}`,
            "-e",
            `AAI_PROVIDER_SESSION_HOME=${manifest.provider_session.mounted_session_home}`,
            "-e",
            `AAI_PROVIDER_CLI_HINT=${manifest.provider_session.cli_command_hint}`,
            "-e",
            `AAI_PROVIDER_ACCOUNT_LABEL=${manifest.provider_session.account_label || ""}`
          ]
        : []),
      ...(options.docker_args || []),
      manifest.container_image
    ];
    commandDescription = [shellQuote(dockerBin), ...dockerArgs.map(shellQuote)].join(" ");
    result = spawnSync(dockerBin, dockerArgs, {
      encoding: "utf8",
      env: {
        ...process.env,
        AAI_RUN_ID: manifest.run_id
      }
    });
  }

  const logBody = [
    `started_at_utc=${startedAt}`,
    `command=${commandDescription}`,
    "",
    "[stdout]",
    result.stdout || "",
    "",
    "[stderr]",
    result.stderr || "",
    ""
  ].join("\n");
  fs.writeFileSync(logPath, logBody, "utf8");

  const finishedAt = nowUtc();
  const exitCode = typeof result.status === "number" ? result.status : 1;
  const status = exitCode === 0 ? "done" : "failed";

  const statement = handle.database.prepare(`
    UPDATE run_registry
    SET status = ?, started_at_utc = ?, finished_at_utc = ?, exit_code = ?, log_path = ?
    WHERE run_id = ?
  `);
  statement.run(status, startedAt, finishedAt, exitCode, logPath, manifest.run_id);

  return {
    run_id: manifest.run_id,
    status,
    exit_code: exitCode,
    log_path: logPath,
    command: commandDescription
  };
}

function isNodeScript(filePath: string): boolean {
  return /\.(cjs|mjs|js|ts)$/i.test(filePath);
}

export function getRun(handle: DatabaseHandle, runId: string): Record<string, unknown> {
  const statement = handle.database.prepare(`
    SELECT
      run_id,
      project_id,
      ref_id,
      provider,
      status,
      created_at_utc,
      manifest_path,
      started_at_utc,
      finished_at_utc,
      exit_code,
      log_path
    FROM run_registry
    WHERE run_id = ?
  `);

  const row = statement.get(runId) as Record<string, unknown> | undefined;
  if (!row) {
    throw new Error(`Unknown run_id: ${runId}`);
  }
  return row;
}

export function validateManifest(manifest: Partial<RunManifest>): { valid: boolean; missing: string[] } {
  const required = [
    "run_id",
    "project_id",
    "ref_id",
    "provider",
    "branch",
    "worktree_path",
    "container_image",
    "mounts",
    "commit_sha",
    "input_refs",
    "output_artifacts",
    "handoff_packet_path",
    "handoff_target_path",
    "memory_contract"
  ] satisfies Array<keyof RunManifest>;

  const missing = required.filter((key) => manifest[key] === undefined || manifest[key] === null);
  return {
    valid: missing.length === 0 && Array.isArray(manifest.mounts),
    missing
  };
}

export function buildHandoffPacket(
  handle: DatabaseHandle,
  options: {
    project_id: string;
    ref_id: string;
    task_key?: string | null;
    parallel_group?: string | null;
    requirement_refs?: string[];
    spec_refs?: string[];
    report_refs?: string[];
  }
): Record<string, unknown> {
  return buildRunHandoffPacket(handle, {
    project_id: options.project_id,
    ref_id: options.ref_id,
    task_key: options.task_key,
    parallel_group: options.parallel_group,
    requirement_refs: options.requirement_refs,
    spec_refs: options.spec_refs,
    report_refs: options.report_refs
  });
}

function buildRunHandoffPacket(
  handle: DatabaseHandle | null,
  options: {
    project_id: string;
    ref_id: string;
    task_key?: string | null;
    parallel_group?: string | null;
    requirement_refs?: string[];
    spec_refs?: string[];
    report_refs?: string[];
    worktree_path?: string | null;
    portable_project_config_path?: string | null;
    provider_session?: RunManifest["provider_session"];
  }
): Record<string, unknown> {
  const project = safeGetProject(handle, options.project_id);
  const workItem = handle
    ? handle.database
        .prepare(`
    SELECT project_id, ref_id, phase, status, provider, branch, manifest_path
    FROM work_items
    WHERE project_id = ? AND ref_id = ?
  `)
        .get(options.project_id, options.ref_id)
    : null;

  const approvals = handle
    ? handle.database
        .prepare(`
    SELECT gate, approved_by, approved_at_utc, artifact_path
    FROM approval_records
    WHERE project_id = ? AND ref_id = ?
    ORDER BY gate
  `)
        .all(options.project_id, options.ref_id)
    : [];

  return {
    project_id: options.project_id,
    ref_id: options.ref_id,
    task_key: options.task_key || null,
    parallel_group: options.parallel_group || null,
    repo_truth: {
      requirement_refs: options.requirement_refs || [],
      spec_refs: options.spec_refs || [],
      report_refs: options.report_refs || []
    },
    project_context: {
      local_repo_path: project?.local_repo_path || null,
      portable_config_path: options.portable_project_config_path || project?.portable_config_path || null,
      default_branch: project?.default_branch || null,
      default_provider_policy: project?.default_provider_policy || null,
      worktree_path: options.worktree_path || null
    },
    subagent_runtime: {
      provider_session: options.provider_session
        ? {
            provider: options.provider_session.provider,
            auth_mode: options.provider_session.auth_mode,
            status: options.provider_session.status,
            account_label: options.provider_session.account_label,
            mounted_session_home: options.provider_session.mounted_session_home,
            cli_command_hint: options.provider_session.cli_command_hint
          }
        : null
    },
    runtime_state: {
      parallel_execution: {
        task_key: options.task_key || null,
        parallel_group: options.parallel_group || null
      },
      work_item: workItem || null,
      approvals
    },
    handoff_contract: {
      hidden_shared_memory_required: false,
      authority: "repo-docs-plus-runtime-db",
      task_transfer: "explicit-handoff-packet",
      worker_must_read: [
        "/workspace/.aai-control-plane-run.json",
        "/workspace/.aai-handoff.json",
        "/workspace/docs"
      ]
    }
  };
}

function resolveProviderSession(handle: DatabaseHandle | null, provider: string): RunManifest["provider_session"] {
  if (!handle) {
    return null;
  }
  try {
    const session = getProviderSession(handle, provider as Provider);
    if (session.status !== "ok") {
      return null;
    }
    return {
      provider: session.provider,
      auth_mode: session.auth_mode,
      status: session.status,
      account_label: session.account_label,
      host_cli_path: session.cli_path,
      host_session_home: session.session_home,
      mounted_session_home: `/var/run/aai/provider-session/${session.provider}`,
      cli_command_hint: path.basename(session.cli_path) || session.provider
    };
  } catch {
    return null;
  }
}

function safeGetProject(
  handle: DatabaseHandle | null,
  projectId: string
):
  | {
      project_id?: string;
      local_repo_path?: string | null;
      portable_config_path?: string | null;
      default_branch?: string;
      default_provider_policy?: string;
    }
  | null {
  if (!handle) {
    return null;
  }
  try {
    return getProject(handle, projectId) as {
      project_id?: string;
      local_repo_path?: string | null;
      portable_config_path?: string | null;
      default_branch?: string;
      default_provider_policy?: string;
    };
  } catch {
    return null;
  }
}

function normalizeTaskKey(value?: string | null): string | null {
  if (!value) {
    return null;
  }
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return normalized || null;
}
