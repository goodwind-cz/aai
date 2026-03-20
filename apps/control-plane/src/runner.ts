import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import type { DatabaseHandle } from "./db.ts";
import { ensureDir, nowUtc, writeJson } from "./common.ts";

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

function gitCommitSha(repoPath: string): string {
  const result = spawnSync("git", ["-C", repoPath, "rev-parse", "HEAD"], {
    encoding: "utf8"
  });

  if (result.status !== 0) {
    return "unknown";
  }

  return result.stdout.trim();
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
  ensureDir(worktreePath);

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
    commit_sha: gitCommitSha(options.repo_path),
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
        manifest_path
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    statement.run(runId, options.project_id, options.ref_id, options.provider, "prepared", nowUtc(), manifestPath);
  }

  return { manifest, manifest_path: manifestPath };
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
