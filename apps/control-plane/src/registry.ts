import path from "node:path";
import type { DatabaseHandle } from "./db.ts";
import { parseJsonColumn } from "./db.ts";
import { loadYamlFile } from "./yaml-lite.ts";

type YamlConfig = Record<string, string | number | boolean | Record<string, string>>;

export type ProjectPortableConfig = {
  config_path: string;
  project_id: string;
  default_branch: string;
  allowed_docker_profile: string;
  default_provider_policy: string;
  phase_provider_preferences: Record<string, string>;
};

export type HostProjectBinding = {
  local_repo_path: string;
  allowed_telegram_chat_ids: string[];
  allowed_telegram_user_ids: string[];
};

export function loadProjectConfig(configPath: string): ProjectPortableConfig {
  const config = loadYamlFile(configPath) as YamlConfig;
  return {
    config_path: path.resolve(configPath),
    project_id: String(config.project_id),
    default_branch: String(config.default_branch),
    allowed_docker_profile: String(config.allowed_docker_profile),
    default_provider_policy: String(config.default_provider_policy),
    phase_provider_preferences: (config.phase_provider_preferences as Record<string, string>) || {}
  };
}

export function registerProject(
  handle: DatabaseHandle,
  config: ProjectPortableConfig,
  binding: HostProjectBinding
): void {
  const upsertProject = handle.database.prepare(`
    INSERT INTO projects (
      project_id,
      default_branch,
      default_provider_policy,
      allowed_docker_profile,
      portable_config_path
    ) VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(project_id) DO UPDATE SET
      default_branch = excluded.default_branch,
      default_provider_policy = excluded.default_provider_policy,
      allowed_docker_profile = excluded.allowed_docker_profile,
      portable_config_path = excluded.portable_config_path
  `);

  const upsertBinding = handle.database.prepare(`
    INSERT INTO host_bindings (
      project_id,
      local_repo_path,
      allowed_telegram_chat_ids,
      allowed_telegram_user_ids
    ) VALUES (?, ?, ?, ?)
    ON CONFLICT(project_id) DO UPDATE SET
      local_repo_path = excluded.local_repo_path,
      allowed_telegram_chat_ids = excluded.allowed_telegram_chat_ids,
      allowed_telegram_user_ids = excluded.allowed_telegram_user_ids
  `);

  upsertProject.run(
    config.project_id,
    config.default_branch,
    config.default_provider_policy,
    config.allowed_docker_profile,
    config.config_path
  );

  upsertBinding.run(
    config.project_id,
    path.resolve(binding.local_repo_path),
    JSON.stringify(binding.allowed_telegram_chat_ids),
    JSON.stringify(binding.allowed_telegram_user_ids)
  );
}

export function listProjects(handle: DatabaseHandle): Array<Record<string, unknown>> {
  const statement = handle.database.prepare(`
    SELECT
      p.project_id,
      p.default_branch,
      p.default_provider_policy,
      p.allowed_docker_profile,
      p.portable_config_path,
      h.local_repo_path,
      h.allowed_telegram_chat_ids,
      h.allowed_telegram_user_ids
    FROM projects p
    LEFT JOIN host_bindings h ON h.project_id = p.project_id
    ORDER BY p.project_id
  `);

  return statement.all().map((row) => ({
    project_id: row.project_id,
    default_branch: row.default_branch,
    default_provider_policy: row.default_provider_policy,
    allowed_docker_profile: row.allowed_docker_profile,
    portable_config_path: row.portable_config_path,
    local_repo_path: row.local_repo_path,
    allowed_telegram_chat_ids: parseJsonColumn(row.allowed_telegram_chat_ids as string | null),
    allowed_telegram_user_ids: parseJsonColumn(row.allowed_telegram_user_ids as string | null)
  }));
}

export function getProject(handle: DatabaseHandle, projectId: string): Record<string, unknown> {
  const statement = handle.database.prepare(`
    SELECT
      p.project_id,
      p.default_branch,
      p.default_provider_policy,
      p.allowed_docker_profile,
      p.portable_config_path,
      h.local_repo_path,
      h.allowed_telegram_chat_ids,
      h.allowed_telegram_user_ids
    FROM projects p
    LEFT JOIN host_bindings h ON h.project_id = p.project_id
    WHERE p.project_id = ?
  `);

  const row = statement.get(projectId) as Record<string, string | null> | undefined;
  if (!row) {
    throw new Error(`Unknown project_id: ${projectId}`);
  }

  return {
    project_id: row.project_id,
    default_branch: row.default_branch,
    default_provider_policy: row.default_provider_policy,
    allowed_docker_profile: row.allowed_docker_profile,
    portable_config_path: row.portable_config_path,
    local_repo_path: row.local_repo_path,
    allowed_telegram_chat_ids: parseJsonColumn(row.allowed_telegram_chat_ids),
    allowed_telegram_user_ids: parseJsonColumn(row.allowed_telegram_user_ids)
  };
}
