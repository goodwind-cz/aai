import type { DatabaseHandle } from "./db.ts";
import { readJson, nowUtc, runtimeLog } from "./common.ts";
import { createWorkItem, evaluateGate, getWorkItem, listWorkItems, recordApproval, updateWorkItemStatus } from "./queue.ts";
import { listProjects } from "./registry.ts";
import { listProviderSessions, loadUsageWindowsFromDb } from "./provider-router.ts";

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

type TelegramUpdate = {
  update_id: number;
  message?: {
    message_id: number;
    text?: string;
    chat: { id: number | string };
    from?: { id: number | string };
  };
  callback_query?: {
    id: string;
    data?: string;
    message?: {
      message_id: number;
      chat: { id: number | string };
    };
    from?: { id: number | string };
  };
};

type TelegramApiResponse<T> = {
  ok: boolean;
  result: T;
};

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

export async function getTelegramBotProfile(
  options: {
    token: string;
    api_base?: string;
  }
): Promise<Record<string, unknown>> {
  const apiBase = (options.api_base || "https://api.telegram.org").replace(/\/$/, "");
  return callTelegram<Record<string, unknown>>(apiBase, options.token, "getMe", {});
}

export async function inspectTelegramSetup(
  options: {
    token: string;
    api_base?: string;
    limit?: number;
  }
): Promise<Record<string, unknown>> {
  const apiBase = (options.api_base || "https://api.telegram.org").replace(/\/$/, "");
  const limit = Math.max(1, Math.min(100, options.limit ?? 20));
  const [bot, updates] = await Promise.all([
    getTelegramBotProfile(options),
    callTelegram<TelegramUpdate[]>(apiBase, options.token, "getUpdates", { timeout: 0, limit })
  ]);

  const chats = new Map<string, Record<string, unknown>>();
  const users = new Map<string, Record<string, unknown>>();
  const recentUpdates: Array<Record<string, unknown>> = [];

  for (const update of updates) {
    if (update.message) {
      const chatId = String(update.message.chat.id);
      const userId = String(update.message.from?.id || "");
      if (!chats.has(chatId)) {
        chats.set(chatId, { chat_id: chatId, source: "message" });
      }
      if (userId && !users.has(userId)) {
        users.set(userId, { user_id: userId, source: "message" });
      }
      recentUpdates.push({
        update_id: update.update_id,
        type: "message",
        chat_id: chatId,
        user_id: userId || null,
        text: update.message.text || null
      });
      continue;
    }

    if (update.callback_query?.message) {
      const chatId = String(update.callback_query.message.chat.id);
      const userId = String(update.callback_query.from?.id || "");
      if (!chats.has(chatId)) {
        chats.set(chatId, { chat_id: chatId, source: "callback_query" });
      }
      if (userId && !users.has(userId)) {
        users.set(userId, { user_id: userId, source: "callback_query" });
      }
      recentUpdates.push({
        update_id: update.update_id,
        type: "callback_query",
        chat_id: chatId,
        user_id: userId || null,
        callback_data: update.callback_query.data || null
      });
    }
  }

  return {
    bot,
    updates_count: updates.length,
    chat_ids: Array.from(chats.values()),
    user_ids: Array.from(users.values()),
    recent_updates: recentUpdates
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

export async function pollTelegramOnce(
  handle: DatabaseHandle,
  options: {
    token: string;
    api_base?: string;
    approval_config: Record<string, string[]>;
    once?: boolean;
    default_phase?: string;
  }
): Promise<Record<string, unknown>> {
  const apiBase = (options.api_base || "https://api.telegram.org").replace(/\/$/, "");
  const cursor = getTelegramCursor(handle);
  const updates = await callTelegram<TelegramUpdate[]>(
    apiBase,
    options.token,
    "getUpdates",
    { offset: cursor + 1, timeout: options.once ? 0 : 1 }
  );

  let processed = 0;
  let lastUpdateId = cursor;
  for (const update of updates) {
    await processUpdate(handle, update, {
      token: options.token,
      apiBase,
      approvalConfig: options.approval_config,
      defaultPhase: options.default_phase || "planning"
    });
    lastUpdateId = Math.max(lastUpdateId, update.update_id);
    processed += 1;
  }

  if (lastUpdateId !== cursor) {
    setTelegramCursor(handle, lastUpdateId);
  }

  return {
    processed_updates: processed,
    last_update_id: lastUpdateId
  };
}

export async function runTelegramDaemon(
  handle: DatabaseHandle,
  options: {
    token: string;
    api_base?: string;
    approval_config: Record<string, string[]>;
    poll_interval_ms?: number;
    once?: boolean;
    max_idle_cycles?: number;
    default_phase?: string;
  }
): Promise<Record<string, unknown>> {
  const pollIntervalMs = options.poll_interval_ms ?? 250;
  const rawMaxIdleCycles = options.max_idle_cycles ?? 20;
  const maxIdleCycles = rawMaxIdleCycles <= 0 ? Number.POSITIVE_INFINITY : rawMaxIdleCycles;
  let idleCycles = 0;
  let totalProcessed = 0;
  let lastUpdateId = getTelegramCursor(handle);

  runtimeLog("telegram.daemon.start", {
    api_base: options.api_base || "https://api.telegram.org",
    once: options.once === true,
    poll_interval_ms: pollIntervalMs,
    max_idle_cycles: rawMaxIdleCycles,
    project_count: listProjects(handle).length,
    provider_session_count: listProviderSessions(handle).length,
    usage_window_count: loadUsageWindowsFromDb(handle).length
  });

  do {
    const result = await pollTelegramOnce(handle, {
      token: options.token,
      api_base: options.api_base,
      approval_config: options.approval_config,
      once: options.once,
      default_phase: options.default_phase
    });
    totalProcessed += Number(result.processed_updates);
    lastUpdateId = Number(result.last_update_id);
    idleCycles = Number(result.processed_updates) === 0 ? idleCycles + 1 : 0;

    runtimeLog("telegram.daemon.poll", {
      processed_updates: Number(result.processed_updates),
      last_update_id: lastUpdateId,
      idle_cycles: idleCycles
    });

    if (options.once || idleCycles >= maxIdleCycles) {
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
  } while (true);

  const summary = {
    processed_updates: totalProcessed,
    last_update_id: lastUpdateId,
    idle_cycles: idleCycles
  };

  runtimeLog("telegram.daemon.stop", summary);
  return summary;
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

async function processUpdate(
  handle: DatabaseHandle,
  update: TelegramUpdate,
  options: {
    token: string;
    apiBase: string;
    approvalConfig: Record<string, string[]>;
    defaultPhase: string;
  }
): Promise<void> {
  if (update.message?.text) {
    const chatId = String(update.message.chat.id);
    const userId = String(update.message.from?.id || "");
    touchTelegramSession(handle, chatId, userId);
    await processCommand(handle, chatId, userId, update.message.text, options);
    return;
  }

  if (update.callback_query?.data && update.callback_query.message) {
    const chatId = String(update.callback_query.message.chat.id);
    const userId = String(update.callback_query.from?.id || "");
    touchTelegramSession(handle, chatId, userId);
    await processCallback(handle, chatId, userId, update.callback_query.id, update.callback_query.data, options);
  }
}

async function processCommand(
  handle: DatabaseHandle,
  chatId: string,
  userId: string,
  text: string,
  options: {
    token: string;
    apiBase: string;
    approvalConfig: Record<string, string[]>;
    defaultPhase: string;
  }
): Promise<void> {
  const [command, ...rawArgs] = text.trim().split(/\s+/);
  const args = rawArgs.filter(Boolean);
  const projectId = resolveProjectSelection(handle, chatId, args[0]);

  switch (command) {
    case "/projects": {
      const projects = listProjects(handle);
      const lines = projects.map((project) => `- ${project.project_id} (${project.default_provider_policy})`);
      await sendMessage(options.apiBase, options.token, chatId, `Projects:\n${lines.join("\n")}`);
      break;
    }
    case "/intake":
    case "/new": {
      if (!projectId) {
        await sendProjectPicker(handle, chatId, options);
        break;
      }
      const [refIdArg, ...summaryParts] = projectId === args[0] ? args.slice(1) : args;
      const refId = refIdArg || `REMOTE-${Date.now()}`;
      const summary = summaryParts.join(" ") || "Created from Telegram intake";
      createWorkItem(handle, {
        project_id: projectId,
        ref_id: refId,
        branch: `aai/${refId.toLowerCase()}`,
        phase: options.defaultPhase,
        status: "queued",
        provider: "auto",
        summary
      });
      setSessionProject(handle, chatId, userId, projectId);
      await sendMessage(
        options.apiBase,
        options.token,
        chatId,
        `Queued ${refId} for ${projectId}`,
        inlineActionsMarkup(refId)
      );
      break;
    }
    case "/status": {
      const refId = args.at(-1);
      if (projectId && refId) {
        const workItem = getWorkItem(handle, projectId, refId);
        await sendMessage(options.apiBase, options.token, chatId, formatWorkItem(workItem));
      } else {
        const items = listWorkItems(handle, projectId || undefined);
        const lines = items.length > 0 ? items.map(formatWorkItem) : ["No work items."];
        await sendMessage(options.apiBase, options.token, chatId, lines.join("\n\n"));
      }
      break;
    }
    case "/usage": {
      const usage = loadUsageWindowsFromDb(handle);
      const lines = usage.length > 0 ? usage.map((entry) => `${entry.provider}: ${entry.used_percentage}% used, resets ${entry.reset_at_utc}`) : formatUsageUnavailable(handle);
      await sendMessage(options.apiBase, options.token, chatId, lines.join("\n"));
      break;
    }
    case "/provider": {
      if (!projectId || args.length < 2) {
        await sendMessage(options.apiBase, options.token, chatId, "Usage: /provider <project_id> <auto|claude|codex> [ref_id]");
        break;
      }
      const selectedProvider = args[1];
      const refId = args[2];
      if (refId) {
        const statement = handle.database.prepare(`
          UPDATE work_items
          SET provider = ?, updated_at_utc = ?
          WHERE project_id = ? AND ref_id = ?
        `);
        statement.run(selectedProvider, nowUtc(), projectId, refId);
      }
      await sendMessage(options.apiBase, options.token, chatId, `Provider policy set to ${selectedProvider}.`);
      break;
    }
    case "/resume":
    case "/stop": {
      if (!projectId || args.length === 0) {
        await sendMessage(options.apiBase, options.token, chatId, `Usage: ${command} <project_id> <ref_id>`);
        break;
      }
      const refId = args.at(-1) as string;
      const status = command === "/resume" ? "running" : "stopped";
      const workItem = updateWorkItemStatus(handle, projectId, refId, status);
      await sendMessage(options.apiBase, options.token, chatId, formatWorkItem(workItem));
      break;
    }
    default:
      await sendMessage(options.apiBase, options.token, chatId, `Unsupported command: ${command}`);
  }

  runtimeLog("telegram.command", {
    chat_id: chatId,
    user_id: userId || null,
    command,
    args
  });
}

async function processCallback(
  handle: DatabaseHandle,
  chatId: string,
  userId: string,
  callbackId: string,
  payload: string,
  options: {
    token: string;
    apiBase: string;
    approvalConfig: Record<string, string[]>;
    defaultPhase: string;
  }
): Promise<void> {
  const parsed = parseCallbackData(payload);
  const projectId = getSessionProject(handle, chatId);
  switch (parsed.action) {
    case "project":
      setSessionProject(handle, chatId, userId, parsed.target);
      await answerCallbackQuery(options.apiBase, options.token, callbackId, `Selected project ${parsed.target}`);
      await sendMessage(options.apiBase, options.token, chatId, `Default project set to ${parsed.target}.`);
      runtimeLog("telegram.callback", {
        chat_id: chatId,
        user_id: userId || null,
        action: parsed.action,
        target: parsed.target,
        ref_id: parsed.ref_id
      });
      return;
    case "resume":
    case "stop":
      if (!projectId) {
        await answerCallbackQuery(options.apiBase, options.token, callbackId, "Select a project first.");
        return;
      }
      await answerCallbackQuery(options.apiBase, options.token, callbackId, `${parsed.action} applied`);
      await sendMessage(
        options.apiBase,
        options.token,
        chatId,
        formatWorkItem(updateWorkItemStatus(handle, projectId, parsed.ref_id, parsed.action === "resume" ? "running" : "stopped"))
      );
      runtimeLog("telegram.callback", {
        chat_id: chatId,
        user_id: userId || null,
        action: parsed.action,
        target: parsed.target,
        ref_id: parsed.ref_id
      });
      return;
    case "approve": {
      if (!projectId) {
        await answerCallbackQuery(options.apiBase, options.token, callbackId, "Select a project first.");
        return;
      }
      const gateResult = evaluateGate(options.approvalConfig, parsed.target as "implementation" | "validation", {});
      recordApproval(handle, {
        project_id: projectId,
        ref_id: parsed.ref_id,
        gate: parsed.target,
        approved_by: `telegram:${userId}`,
        artifact_path: `telegram://callback/${callbackId}`
      });
      await answerCallbackQuery(options.apiBase, options.token, callbackId, gateResult.enabled ? "Approved" : "Approval recorded");
      await sendMessage(options.apiBase, options.token, chatId, `Approval recorded for ${parsed.ref_id} (${parsed.target}).`);
      runtimeLog("telegram.callback", {
        chat_id: chatId,
        user_id: userId || null,
        action: parsed.action,
        target: parsed.target,
        ref_id: parsed.ref_id
      });
      return;
    }
    case "provider":
      if (!projectId) {
        await answerCallbackQuery(options.apiBase, options.token, callbackId, "Select a project first.");
        return;
      }
      handle.database.prepare(`
        UPDATE work_items
        SET provider = ?, updated_at_utc = ?
        WHERE project_id = ? AND ref_id = ?
      `).run(parsed.target, nowUtc(), projectId, parsed.ref_id);
      await answerCallbackQuery(options.apiBase, options.token, callbackId, `Provider set to ${parsed.target}`);
      await sendMessage(options.apiBase, options.token, chatId, `Provider for ${parsed.ref_id} set to ${parsed.target}.`);
      runtimeLog("telegram.callback", {
        chat_id: chatId,
        user_id: userId || null,
        action: parsed.action,
        target: parsed.target,
        ref_id: parsed.ref_id
      });
      return;
    default:
      await answerCallbackQuery(options.apiBase, options.token, callbackId, `Unsupported action ${parsed.action}`);
      runtimeLog("telegram.callback.unsupported", {
        chat_id: chatId,
        user_id: userId || null,
        action: parsed.action,
        target: parsed.target,
        ref_id: parsed.ref_id
      });
  }
}

function formatUsageUnavailable(handle: DatabaseHandle): string[] {
  const sessions = listProviderSessions(handle);
  const lines = ["Usage telemetry unavailable."];

  if (sessions.length === 0) {
    lines.push("No provider sessions are registered yet.");
    lines.push("Run auth probe for installed provider CLIs first.");
    return lines;
  }

  for (const session of sessions) {
    lines.push(
      `${session.provider}: status=${session.status}, account=${session.account_label || "unknown"}, last_usage_sync=${session.last_usage_sync_at_utc || "never"}, error=${session.last_error || "none"}`
    );
  }

  lines.push("If the CLI supports quota output, rerun auth probe with --usage-args ...");
  return lines;
}

function resolveProjectSelection(handle: DatabaseHandle, chatId: string, maybeProjectArg?: string): string | null {
  const projects = listProjects(handle);
  if (maybeProjectArg && projects.some((project) => project.project_id === maybeProjectArg)) {
    return maybeProjectArg;
  }

  const sessionProject = getSessionProject(handle, chatId);
  if (sessionProject) {
    return sessionProject;
  }

  if (projects.length === 1) {
    return String(projects[0].project_id);
  }
  return null;
}

async function sendProjectPicker(
  handle: DatabaseHandle,
  chatId: string,
  options: {
    token: string;
    apiBase: string;
  }
): Promise<void> {
  const projects = listProjects(handle);
  const inline_keyboard = projects.map((project) => [
    {
      text: String(project.project_id),
      callback_data: `project:${project.project_id}:session`
    }
  ]);
  await sendMessage(options.apiBase, options.token, chatId, "Select project first.", { inline_keyboard });
}

function inlineActionsMarkup(refId: string): { inline_keyboard: Array<Array<{ text: string; callback_data: string }>> } {
  return {
    inline_keyboard: [
      [{ text: "Resume", callback_data: `resume:run:${refId}` }],
      [{ text: "Stop", callback_data: `stop:run:${refId}` }],
      [{ text: "Use Claude", callback_data: `provider:claude:${refId}` }],
      [{ text: "Use Codex", callback_data: `provider:codex:${refId}` }]
    ]
  };
}

function formatWorkItem(workItem: Record<string, unknown>): string {
  return [
    `project=${workItem.project_id}`,
    `ref=${workItem.ref_id}`,
    `phase=${workItem.phase}`,
    `status=${workItem.status}`,
    `provider=${workItem.provider}`
  ].join("\n");
}

async function callTelegram<T>(
  apiBase: string,
  token: string,
  method: string,
  payload: Record<string, unknown>
): Promise<T> {
  const response = await fetch(`${apiBase}/bot${token}/${method}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    throw new Error(`Telegram API ${method} failed with HTTP ${response.status}`);
  }

  const body = (await response.json()) as TelegramApiResponse<T>;
  if (!body.ok) {
    throw new Error(`Telegram API ${method} returned ok=false`);
  }
  return body.result;
}

async function sendMessage(
  apiBase: string,
  token: string,
  chatId: string,
  text: string,
  replyMarkup?: Record<string, unknown>
): Promise<void> {
  await callTelegram(apiBase, token, "sendMessage", {
    chat_id: chatId,
    text,
    reply_markup: replyMarkup
  });
}

async function answerCallbackQuery(apiBase: string, token: string, callbackId: string, text: string): Promise<void> {
  await callTelegram(apiBase, token, "answerCallbackQuery", {
    callback_query_id: callbackId,
    text
  });
}

function touchTelegramSession(handle: DatabaseHandle, chatId: string, userId: string): void {
  const statement = handle.database.prepare(`
    INSERT INTO telegram_sessions (chat_id, user_id, default_project_id, last_update_id, updated_at_utc)
    VALUES (?, ?, NULL, 0, ?)
    ON CONFLICT(chat_id) DO UPDATE SET
      user_id = excluded.user_id,
      updated_at_utc = excluded.updated_at_utc
  `);
  statement.run(chatId, userId || null, nowUtc());
}

function getSessionProject(handle: DatabaseHandle, chatId: string): string | null {
  const statement = handle.database.prepare(`
    SELECT default_project_id
    FROM telegram_sessions
    WHERE chat_id = ?
  `);
  const row = statement.get(chatId) as { default_project_id?: string | null } | undefined;
  return row?.default_project_id || null;
}

function setSessionProject(handle: DatabaseHandle, chatId: string, userId: string, projectId: string): void {
  const statement = handle.database.prepare(`
    INSERT INTO telegram_sessions (chat_id, user_id, default_project_id, last_update_id, updated_at_utc)
    VALUES (?, ?, ?, 0, ?)
    ON CONFLICT(chat_id) DO UPDATE SET
      user_id = excluded.user_id,
      default_project_id = excluded.default_project_id,
      updated_at_utc = excluded.updated_at_utc
  `);
  statement.run(chatId, userId || null, projectId, nowUtc());
}

function getTelegramCursor(handle: DatabaseHandle): number {
  const statement = handle.database.prepare(`
    SELECT last_update_id
    FROM telegram_sessions
    WHERE chat_id = '__bot__'
  `);
  const row = statement.get() as { last_update_id?: number } | undefined;
  return Number(row?.last_update_id || 0);
}

function setTelegramCursor(handle: DatabaseHandle, updateId: number): void {
  const statement = handle.database.prepare(`
    INSERT INTO telegram_sessions (chat_id, user_id, default_project_id, last_update_id, updated_at_utc)
    VALUES ('__bot__', NULL, NULL, ?, ?)
    ON CONFLICT(chat_id) DO UPDATE SET
      last_update_id = excluded.last_update_id,
      updated_at_utc = excluded.updated_at_utc
  `);
  statement.run(updateId, nowUtc());
}
