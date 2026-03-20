import type { DatabaseHandle } from "./db.ts";
import { nowUtc } from "./common.ts";

export type GateContext = {
  prd_ref?: string | null;
  frozen_spec_ref?: string | null;
  test_plan_ref?: string | null;
  project_selection?: string | null;
  provider_selection_or_policy?: string | null;
  worktree_manifest?: string | null;
  implementation_summary?: string | null;
  changed_file_summary?: string | null;
  validation_command_set?: string | null;
  report_target_path?: string | null;
  evidence_target_path?: string | null;
};

export function createWorkItem(
  handle: DatabaseHandle,
  workItem: {
    project_id: string;
    ref_id: string;
    branch: string;
    phase: string;
    status: string;
    provider: string;
    manifest_path?: string | null;
    summary?: string | null;
  }
): void {
  const timestamp = nowUtc();
  const statement = handle.database.prepare(`
    INSERT INTO work_items (
      project_id,
      ref_id,
      branch,
      phase,
      status,
      provider,
      manifest_path,
      summary,
      created_at_utc,
      updated_at_utc
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(project_id, ref_id) DO UPDATE SET
      branch = excluded.branch,
      phase = excluded.phase,
      status = excluded.status,
      provider = excluded.provider,
      manifest_path = excluded.manifest_path,
      summary = excluded.summary,
      updated_at_utc = excluded.updated_at_utc
  `);

  statement.run(
    workItem.project_id,
    workItem.ref_id,
    workItem.branch,
    workItem.phase,
    workItem.status,
    workItem.provider,
    workItem.manifest_path || null,
    workItem.summary || null,
    timestamp,
    timestamp
  );
}

export function getWorkItem(handle: DatabaseHandle, projectId: string, refId: string): Record<string, unknown> {
  const statement = handle.database.prepare(`
    SELECT
      project_id,
      ref_id,
      branch,
      phase,
      status,
      provider,
      manifest_path,
      summary,
      created_at_utc,
      updated_at_utc
    FROM work_items
    WHERE project_id = ? AND ref_id = ?
  `);

  const row = statement.get(projectId, refId) as Record<string, unknown> | undefined;
  if (!row) {
    throw new Error(`Unknown work item: ${projectId}/${refId}`);
  }
  return row;
}

export function updateWorkItemStatus(
  handle: DatabaseHandle,
  projectId: string,
  refId: string,
  status: string
): Record<string, unknown> {
  const statement = handle.database.prepare(`
    UPDATE work_items
    SET status = ?, updated_at_utc = ?
    WHERE project_id = ? AND ref_id = ?
  `);
  statement.run(status, nowUtc(), projectId, refId);
  return getWorkItem(handle, projectId, refId);
}

export function recordApproval(
  handle: DatabaseHandle,
  approval: {
    project_id: string;
    ref_id: string;
    gate: string;
    approved_by: string;
    approved_at_utc?: string;
    artifact_path: string;
  }
): void {
  const statement = handle.database.prepare(`
    INSERT INTO approval_records (
      project_id,
      ref_id,
      gate,
      approved_by,
      approved_at_utc,
      artifact_path
    ) VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(project_id, ref_id, gate) DO UPDATE SET
      approved_by = excluded.approved_by,
      approved_at_utc = excluded.approved_at_utc,
      artifact_path = excluded.artifact_path
  `);

  statement.run(
    approval.project_id,
    approval.ref_id,
    approval.gate,
    approval.approved_by,
    approval.approved_at_utc || nowUtc(),
    approval.artifact_path
  );
}

export function approvalExists(handle: DatabaseHandle, projectId: string, refId: string, gate: string): boolean {
  const statement = handle.database.prepare(`
    SELECT 1
    FROM approval_records
    WHERE project_id = ? AND ref_id = ? AND gate = ?
  `);
  return Boolean(statement.get(projectId, refId, gate));
}

export function evaluateGate(
  gatesConfig: Record<string, string[]>,
  gate: "implementation" | "validation",
  context: GateContext
): { gate: string; enabled: boolean; required: string[]; missing: string[] } {
  const fieldName =
    gate === "implementation" ? "approve_implementation_requires" : "approve_validation_requires";
  const required = gatesConfig[fieldName];
  if (!Array.isArray(required)) {
    throw new Error(`Gate configuration missing ${fieldName}`);
  }

  const missing = required.filter((key) => !context[key as keyof GateContext]);
  return {
    gate,
    enabled: missing.length === 0,
    required,
    missing
  };
}
