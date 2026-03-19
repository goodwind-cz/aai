export type ProjectPortableConfig = {
  project_id: string;
  default_branch: string;
  allowed_docker_profile: string;
  default_provider_policy: 'auto' | 'claude' | 'codex' | 'project-default';
  phase_provider_preferences?: Record<string, 'claude' | 'codex' | 'auto'>;
};

export type HostProjectBinding = {
  project_id: string;
  local_repo_path: string;
  allowed_telegram_chat_ids: string[];
  allowed_telegram_user_ids: string[];
};
