CREATE TABLE IF NOT EXISTS projects (
  project_id TEXT PRIMARY KEY,
  default_branch TEXT NOT NULL,
  default_provider_policy TEXT NOT NULL,
  allowed_docker_profile TEXT NOT NULL,
  portable_config_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS host_bindings (
  project_id TEXT PRIMARY KEY,
  local_repo_path TEXT NOT NULL,
  allowed_telegram_chat_ids TEXT NOT NULL,
  allowed_telegram_user_ids TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS run_registry (
  run_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  ref_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  manifest_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS work_items (
  project_id TEXT NOT NULL,
  ref_id TEXT NOT NULL,
  branch TEXT NOT NULL,
  phase TEXT NOT NULL,
  status TEXT NOT NULL,
  provider TEXT NOT NULL,
  manifest_path TEXT,
  summary TEXT,
  created_at_utc TEXT NOT NULL,
  updated_at_utc TEXT NOT NULL,
  PRIMARY KEY (project_id, ref_id)
);

CREATE TABLE IF NOT EXISTS approval_records (
  project_id TEXT NOT NULL,
  ref_id TEXT NOT NULL,
  gate TEXT NOT NULL,
  approved_by TEXT NOT NULL,
  approved_at_utc TEXT NOT NULL,
  artifact_path TEXT NOT NULL,
  PRIMARY KEY (project_id, ref_id, gate)
);
