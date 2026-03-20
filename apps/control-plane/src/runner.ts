import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import type { DatabaseHandle } from "./db.ts";
import { ensureDir, nowUtc, shellQuote, writeJson } from "./common.ts";

export type RunManifest = {
  run_id: string;
  project_id: string;
  ref_id: string;
  provider: string;
  branch: string;
  worktree_path: string;
  container_image: string;
  mounts: Array<{ source: string; target: string; read_only: boolean }>;
  commit_sha: string;
  input_refs: string[];
  output_artifacts: string[];
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
    repo_path: string;
    worktrees_root: string;
    provider: string;
    branch?: string | null;
    manifest_path?: string | null;
    container_image: string;
    input_refs?: string[];
    output_artifacts?: string[];
    read_only_mounts?: Array<{ source: string; target: string }>;
    validated_extra_mounts?: Array<{ source: string; target: string; read_only: boolean }>;
  }
): { manifest: RunManifest; manifest_path: string } {
  const runId = `${options.project_id}-${options.ref_id}-${Date.now()}`;
  const branch = options.branch || `aai/${options.ref_id.toLowerCase()}`;
  const worktreePath = path.resolve(options.worktrees_root, `${options.project_id}-${options.ref_id}`);
  ensureGitWorktree(options.repo_path, branch, worktreePath);

  const manifestPath = path.resolve(options.manifest_path || path.join(worktreePath, "run-manifest.json"));
  const manifest: RunManifest = {
    run_id: runId,
    project_id: options.project_id,
    ref_id: options.ref_id,
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
        AAI_RUN_WORKTREE: manifest.worktree_path,
        AAI_RUN_ID: manifest.run_id
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
      ...(options.docker_args || []),
      manifest.container_image
    ];
    commandDescription = [shellQuote(dockerBin), ...dockerArgs.map(shellQuote)].join(" ");
    result = spawnSync(dockerBin, dockerArgs, {
      encoding: "utf8",
      env: {
        ...process.env,
        AAI_RUN_MANIFEST: "/workspace/.aai-control-plane-run.json",
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
    "output_artifacts"
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
    requirement_refs?: string[];
    spec_refs?: string[];
    report_refs?: string[];
  }
): Record<string, unknown> {
  const workItem = handle.database.prepare(`
    SELECT project_id, ref_id, phase, status, provider, branch, manifest_path
    FROM work_items
    WHERE project_id = ? AND ref_id = ?
  `).get(options.project_id, options.ref_id);

  const approvals = handle.database.prepare(`
    SELECT gate, approved_by, approved_at_utc, artifact_path
    FROM approval_records
    WHERE project_id = ? AND ref_id = ?
    ORDER BY gate
  `).all(options.project_id, options.ref_id);

  return {
    project_id: options.project_id,
    ref_id: options.ref_id,
    repo_truth: {
      requirement_refs: options.requirement_refs || [],
      spec_refs: options.spec_refs || [],
      report_refs: options.report_refs || []
    },
    runtime_state: {
      work_item: workItem || null,
      approvals
    },
    handoff_contract: {
      hidden_shared_memory_required: false,
      authority: "repo-docs-plus-runtime-db"
    }
  };
}
