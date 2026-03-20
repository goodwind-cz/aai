import { readJson } from "./common.ts";
import { createWorkItem, getWorkItem, updateWorkItemStatus } from "./queue.ts";
import type { DatabaseHandle } from "./db.ts";

const SAFE_CALLBACK_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export const PRIMARY_INLINE_ACTIONS = [
  "Approve implementation",
  "Approve validation",
  "Pause",
  "Resume",
  "Stop",
  "Use Claude",
  "Use Codex",
  "Use Auto Router",
  "Switch Project",
  "Open Latest Report"
] as const;

export const INTAKE_FORM_FIELDS = [
  "project_id",
  "ref_id",
  "provider_policy",
  "phase",
  "summary"
] as const;

export function loadCommandRegistry(filePath: string): Record<string, unknown> {
  return readJson<Record<string, unknown>>(filePath);
}

export function interactiveModel(): Record<string, unknown> {
  return {
    inline_actions: PRIMARY_INLINE_ACTIONS,
    form_fields: INTAKE_FORM_FIELDS,
    transport: "telegram-web-app-or-inline-buttons",
    callback_examples: [
      "approve:implementation:PRD-AAI-REMOTE-ORCHESTRATION-01",
      "provider:codex:PRD-AAI-REMOTE-ORCHESTRATION-01",
      "project:aai-canonical:PRD-AAI-REMOTE-ORCHESTRATION-01"
    ]
  };
}

export function isSafeCallbackId(value: string): boolean {
  if (!SAFE_CALLBACK_ID.test(value)) {
    return false;
  }
  return !value.includes("..") && !value.startsWith(".");
}

export function parseCallbackData(callbackData: string): {
  action: string;
  target: string;
  ref_id: string;
} {
  const [action, target, refId] = callbackData.split(":");
  if (!action || !target || !refId) {
    throw new Error("Invalid callback payload");
  }

  if (!isSafeCallbackId(target)) {
    throw new Error("Invalid callback target");
  }

  if (!isSafeCallbackId(refId)) {
    throw new Error("Invalid callback ref_id");
  }

  return {
    action,
    target,
    ref_id: refId
  };
}

export function simulateTelegramCommand(
  handle: DatabaseHandle,
  options: {
    command: string;
    project_id: string;
    ref_id: string;
    provider?: string;
    phase?: string;
    branch?: string | null;
    summary?: string | null;
  }
): Record<string, unknown> {
  switch (options.command) {
    case "/intake":
    case "/new":
      createWorkItem(handle, {
        project_id: options.project_id,
        ref_id: options.ref_id,
        branch: options.branch || `aai/${options.ref_id.toLowerCase()}`,
        phase: options.phase || "planning",
        status: "queued",
        provider: options.provider || "auto",
        summary: options.summary || "Created from Telegram intake"
      });
      return {
        command: options.command,
        message: `Work item ${options.ref_id} queued for ${options.project_id}.`,
        actions: PRIMARY_INLINE_ACTIONS
      };
    case "/approve":
      return {
        command: options.command,
        message: `Approval gate requested for ${options.ref_id}.`,
        actions: ["Approve implementation", "Approve validation", "Stop"]
      };
    case "/resume":
      return {
        command: options.command,
        work_item: updateWorkItemStatus(handle, options.project_id, options.ref_id, "running")
      };
    case "/stop":
      return {
        command: options.command,
        work_item: updateWorkItemStatus(handle, options.project_id, options.ref_id, "stopped")
      };
    case "/status":
      return {
        command: options.command,
        work_item: getWorkItem(handle, options.project_id, options.ref_id)
      };
    default:
      throw new Error(`Unsupported Telegram command: ${options.command}`);
  }
}
