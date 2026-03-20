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
  manifest_path TEXT NOT NULL,
  started_at_utc TEXT,
  finished_at_utc TEXT,
  exit_code INTEGER,
  log_path TEXT
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

CREATE TABLE IF NOT EXISTS provider_sessions (
  provider TEXT PRIMARY KEY,
  auth_mode TEXT NOT NULL,
  cli_path TEXT NOT NULL,
  session_home TEXT NOT NULL,
  account_label TEXT,
  status TEXT NOT NULL,
  last_verified_at_utc TEXT,
  last_usage_sync_at_utc TEXT,
  last_error TEXT
);

CREATE TABLE IF NOT EXISTS provider_usage_snapshots (
  provider TEXT PRIMARY KEY,
  window_label TEXT NOT NULL,
  used_percentage REAL NOT NULL,
  reset_at_utc TEXT NOT NULL,
  collected_at_utc TEXT NOT NULL,
  raw_payload TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS telegram_sessions (
  chat_id TEXT PRIMARY KEY,
  user_id TEXT,
  default_project_id TEXT,
  last_update_id INTEGER NOT NULL DEFAULT 0,
  updated_at_utc TEXT NOT NULL
);
