export type RunManifest = {
  run_id: string;
  project_id: string;
  ref_id: string;
  provider: 'claude' | 'codex';
  branch: string;
  worktree_path: string;
  container_image: string;
  mounts: { source: string; target: string; read_only: boolean }[];
  commit_sha: string;
  input_refs: string[];
  output_artifacts: string[];
};
