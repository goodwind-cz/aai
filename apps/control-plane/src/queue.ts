export type ApprovalGate = 'implementation' | 'validation';

export type WorkItem = {
  ref_id: string;
  project_id: string;
  branch: string;
  phase: 'planning' | 'implementation' | 'validation' | 'remediation';
  status: 'queued' | 'running' | 'blocked' | 'done';
};

export type ApprovalRecord = {
  gate: ApprovalGate;
  approved_by: string;
  approved_at_utc: string;
  artifact_path: string;
};
