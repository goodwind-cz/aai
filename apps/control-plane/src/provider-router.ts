import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import type { DatabaseHandle } from "./db.ts";
import { nowUtc, readJson } from "./common.ts";

export type Provider = "claude" | "codex";

export type UsageWindow = {
  provider: Provider;
  window_label: string;
  used_percentage: number;
  reset_at_utc: string;
  collected_at_utc: string;
};

export type ProviderDecision = {
  provider: Provider;
  reason: string;
};

export type ProviderSessionRecord = {
  provider: Provider;
  auth_mode: "cli-subscription";
  cli_path: string;
  session_home: string;
  account_label: string | null;
  status: "ok" | "missing" | "error";
  last_verified_at_utc: string | null;
  last_usage_sync_at_utc: string | null;
  last_error: string | null;
};

type CommandResult = {
  status: number | null;
  stdout: string;
  stderr: string;
  error: string | null;
};

type ProviderSessionRow = {
  provider: string;
  auth_mode: string;
  cli_path: string;
  session_home: string;
  account_label: string | null;
  status: string;
  last_verified_at_utc: string | null;
  last_usage_sync_at_utc: string | null;
  last_error: string | null;
};

type ProviderUsageRow = {
  provider: string;
  window_label: string;
  used_percentage: number;
  reset_at_utc: string;
  collected_at_utc: string;
};

export function loadUsageWindows(filePath: string): UsageWindow[] {
  const payload = readJson<unknown>(filePath);
  return normalizeUsagePayload(payload);
}

export function validateAuthMode(mode: string): { ok: true; mode: string; reason: string } {
  if (mode !== "cli-subscription") {
    throw new Error(`Unsupported auth mode: ${mode}. Only cli-subscription is allowed.`);
  }

  return {
    ok: true,
    mode,
    reason: "Host-authenticated CLI subscriptions are the only supported provider mode."
  };
}

export function chooseProvider(options: {
  policy?: string;
  fallback?: Provider;
  strictSingleProvider?: boolean;
  operatorOverride?: string | null;
  usage?: UsageWindow[];
  phasePreference?: string;
  sessions?: ProviderSessionRecord[];
}): ProviderDecision {
  const {
    policy,
    fallback,
    strictSingleProvider = false,
    operatorOverride = null,
    usage = [],
    phasePreference = "auto",
    sessions = []
  } = options;

  const availableProviders = getAvailableProviders(sessions);
  const hasAvailabilitySignal = sessions.length > 0;
  const filteredUsage =
    availableProviders.length > 0 ? usage.filter((entry) => availableProviders.includes(entry.provider)) : usage;

  if (operatorOverride && operatorOverride !== "auto") {
    return finalizeProviderDecision(
      operatorOverride as Provider,
      "operator-override",
      availableProviders,
      hasAvailabilitySignal,
      fallback
    );
  }

  if (policy && policy !== "auto") {
    return finalizeProviderDecision(
      policy as Provider,
      "project-policy-explicit",
      availableProviders,
      hasAvailabilitySignal,
      fallback
    );
  }

  if (phasePreference && phasePreference !== "auto") {
    return finalizeProviderDecision(
      phasePreference as Provider,
      "phase-preference",
      availableProviders,
      hasAvailabilitySignal,
      fallback
    );
  }

  if (hasAvailabilitySignal && availableProviders.length === 0) {
    throw new Error("No available provider CLIs are installed and authenticated on the host.");
  }

  const claude = filteredUsage.find((entry) => entry.provider === "claude");
  const codex = filteredUsage.find((entry) => entry.provider === "codex");

  if (!claude && codex) {
    return { provider: "codex", reason: "claude-usage-missing" };
  }

  if (!codex && claude) {
    return { provider: "claude", reason: "codex-usage-missing" };
  }

  if (!claude && !codex) {
    if (strictSingleProvider && fallback === undefined) {
      throw new Error("Strict single provider mode requires a concrete fallback provider.");
    }
    return { provider: fallback || "codex", reason: "usage-unavailable-fallback" };
  }

  if ((claude?.used_percentage ?? 0) >= 95 && (codex?.used_percentage ?? 0) < 95) {
    return { provider: "codex", reason: "claude-over-budget" };
  }

  if ((codex?.used_percentage ?? 0) >= 95 && (claude?.used_percentage ?? 0) < 95) {
    return { provider: "claude", reason: "codex-over-budget" };
  }

  if (!claude || !codex) {
    return { provider: fallback || "codex", reason: "usage-partial-fallback" };
  }

  if (claude.used_percentage === codex.used_percentage) {
    return { provider: fallback || "claude", reason: "usage-tie-fallback" };
  }

  return claude.used_percentage < codex.used_percentage
    ? { provider: "claude", reason: "lowest-usage" }
    : { provider: "codex", reason: "lowest-usage" };
}

export function markProviderSessionMissing(
  handle: DatabaseHandle,
  options: {
    provider: Provider;
    session_home: string;
    cli_path?: string;
    account_label?: string | null;
    message?: string;
  }
): ProviderSessionRecord {
  return upsertProviderSession(handle, {
    provider: options.provider,
    auth_mode: "cli-subscription",
    cli_path: path.resolve(options.cli_path || path.join(options.session_home, `${options.provider}-not-installed`)),
    session_home: path.resolve(options.session_home),
    account_label: options.account_label || null,
    status: "missing",
    last_verified_at_utc: nowUtc(),
    last_usage_sync_at_utc: null,
    last_error: options.message || `${options.provider} CLI is not installed on this host.`
  });
}

export function probeProviderSession(
  handle: DatabaseHandle,
  options: {
    provider: Provider;
    cli_path: string;
    session_home: string;
    account_label?: string | null;
    probe_args?: string[];
    usage_args?: string[];
  }
): { session: ProviderSessionRecord; usage_windows: UsageWindow[] } {
  const verifiedAt = nowUtc();
  const cliPath = path.resolve(options.cli_path);
  const sessionHome = path.resolve(options.session_home);
  if (!fs.existsSync(cliPath)) {
    const session = upsertProviderSession(handle, {
      provider: options.provider,
      auth_mode: "cli-subscription",
      cli_path: cliPath,
      session_home: sessionHome,
      account_label: options.account_label || null,
      status: "missing",
      last_verified_at_utc: verifiedAt,
      last_usage_sync_at_utc: null,
      last_error: `CLI binary not found: ${cliPath}`
    });
    return { session, usage_windows: [] };
  }

  const probeArgs =
    options.probe_args && options.probe_args.length > 0 ? options.probe_args : defaultProbeArgs(options.provider);
  const probeResult = runCommand(cliPath, probeArgs, sessionHome);

  let status: ProviderSessionRecord["status"] = "ok";
  let lastError: string | null = null;
  let accountLabel = options.account_label || inferAccountLabel(options.provider, probeResult.stdout);
  if (probeResult.error) {
    status = "missing";
    lastError = probeResult.error;
  } else if (probeResult.status !== 0) {
    status = "error";
    lastError = probeResult.stderr.trim() || probeResult.stdout.trim() || `Probe exited with ${probeResult.status}`;
  } else {
    const authCheck = inspectProbeResult(options.provider, probeResult.stdout);
    if (authCheck.status !== "ok") {
      status = authCheck.status;
      lastError = authCheck.last_error;
    }
    if (authCheck.account_label) {
      accountLabel = authCheck.account_label;
    }
  }

  let usageWindows: UsageWindow[] = [];
  let usageSyncedAt: string | null = null;
  if (status === "ok" && options.usage_args && options.usage_args.length > 0) {
    const usageResult = runCommand(cliPath, options.usage_args, sessionHome);
    if (usageResult.status === 0) {
      usageWindows = normalizeUsagePayload(usageResult.stdout, options.provider);
      saveUsageWindows(handle, usageWindows);
      usageSyncedAt = nowUtc();
    } else {
      status = "error";
      lastError =
        usageResult.error ||
        usageResult.stderr.trim() ||
        usageResult.stdout.trim() ||
        `Usage probe exited with ${usageResult.status}`;
    }
  }

  const session = upsertProviderSession(handle, {
    provider: options.provider,
    auth_mode: "cli-subscription",
    cli_path: cliPath,
    session_home: sessionHome,
    account_label: accountLabel,
    status,
    last_verified_at_utc: verifiedAt,
    last_usage_sync_at_utc: usageSyncedAt,
    last_error: lastError
  });

  return { session, usage_windows: usageWindows };
}

export function getProviderSession(handle: DatabaseHandle, provider: Provider): ProviderSessionRecord {
  const statement = handle.database.prepare(`
    SELECT
      provider,
      auth_mode,
      cli_path,
      session_home,
      account_label,
      status,
      last_verified_at_utc,
      last_usage_sync_at_utc,
      last_error
    FROM provider_sessions
    WHERE provider = ?
  `);

  const row = statement.get(provider) as ProviderSessionRow | undefined;
  if (!row) {
    throw new Error(`Unknown provider session: ${provider}`);
  }

  return {
    provider: row.provider as Provider,
    auth_mode: row.auth_mode as "cli-subscription",
    cli_path: String(row.cli_path),
    session_home: String(row.session_home),
    account_label: row.account_label,
    status: row.status as ProviderSessionRecord["status"],
    last_verified_at_utc: row.last_verified_at_utc,
    last_usage_sync_at_utc: row.last_usage_sync_at_utc,
    last_error: row.last_error
  };
}

export function listProviderSessions(handle: DatabaseHandle): ProviderSessionRecord[] {
  const statement = handle.database.prepare(`
    SELECT
      provider,
      auth_mode,
      cli_path,
      session_home,
      account_label,
      status,
      last_verified_at_utc,
      last_usage_sync_at_utc,
      last_error
    FROM provider_sessions
    ORDER BY provider
  `);

  return (statement.all() as ProviderSessionRow[]).map((row) => ({
    provider: row.provider as Provider,
    auth_mode: row.auth_mode as "cli-subscription",
    cli_path: row.cli_path,
    session_home: row.session_home,
    account_label: row.account_label || null,
    status: row.status as ProviderSessionRecord["status"],
    last_verified_at_utc: row.last_verified_at_utc || null,
    last_usage_sync_at_utc: row.last_usage_sync_at_utc || null,
    last_error: row.last_error || null
  }));
}

export function loadUsageWindowsFromDb(handle: DatabaseHandle): UsageWindow[] {
  const statement = handle.database.prepare(`
    SELECT provider, window_label, used_percentage, reset_at_utc, collected_at_utc
    FROM provider_usage_snapshots
    ORDER BY provider
  `);

  return (statement.all() as ProviderUsageRow[]).map((row) => ({
    provider: row.provider as Provider,
    window_label: row.window_label,
    used_percentage: Number(row.used_percentage),
    reset_at_utc: row.reset_at_utc,
    collected_at_utc: row.collected_at_utc
  }));
}

function upsertProviderSession(handle: DatabaseHandle, session: ProviderSessionRecord): ProviderSessionRecord {
  const statement = handle.database.prepare(`
    INSERT INTO provider_sessions (
      provider,
      auth_mode,
      cli_path,
      session_home,
      account_label,
      status,
      last_verified_at_utc,
      last_usage_sync_at_utc,
      last_error
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(provider) DO UPDATE SET
      auth_mode = excluded.auth_mode,
      cli_path = excluded.cli_path,
      session_home = excluded.session_home,
      account_label = excluded.account_label,
      status = excluded.status,
      last_verified_at_utc = excluded.last_verified_at_utc,
      last_usage_sync_at_utc = excluded.last_usage_sync_at_utc,
      last_error = excluded.last_error
  `);

  statement.run(
    session.provider,
    session.auth_mode,
    session.cli_path,
    session.session_home,
    session.account_label,
    session.status,
    session.last_verified_at_utc,
    session.last_usage_sync_at_utc,
    session.last_error
  );
  return getProviderSession(handle, session.provider);
}

function getAvailableProviders(sessions: ProviderSessionRecord[]): Provider[] {
  return sessions.filter((session) => session.status === "ok").map((session) => session.provider);
}

function defaultProbeArgs(provider: Provider): string[] {
  switch (provider) {
    case "claude":
      return ["auth", "status", "--json"];
    case "codex":
      return ["--help"];
    default:
      return ["--version"];
  }
}

function inspectProbeResult(
  provider: Provider,
  stdout: string
): { status: ProviderSessionRecord["status"]; last_error: string | null; account_label: string | null } {
  if (provider !== "claude") {
    return {
      status: "ok",
      last_error: null,
      account_label: inferAccountLabel(provider, stdout)
    };
  }

  try {
    const parsed = JSON.parse(stdout) as {
      loggedIn?: boolean;
      email?: string;
      subscriptionType?: string;
    };

    if (parsed.loggedIn === false) {
      return {
        status: "error",
        last_error: "Claude CLI is installed but not logged in. Run 'claude auth login' on the host.",
        account_label: null
      };
    }

    return {
      status: "ok",
      last_error: null,
      account_label: formatAccountLabel(parsed.email, parsed.subscriptionType)
    };
  } catch {
    return {
      status: "ok",
      last_error: null,
      account_label: inferAccountLabel(provider, stdout)
    };
  }
}

function inferAccountLabel(provider: Provider, stdout: string): string | null {
  if (provider !== "claude") {
    return null;
  }

  try {
    const parsed = JSON.parse(stdout) as {
      email?: string;
      subscriptionType?: string;
    };
    return formatAccountLabel(parsed.email, parsed.subscriptionType);
  } catch {
    return null;
  }
}

function formatAccountLabel(email?: string, subscriptionType?: string): string | null {
  const normalizedEmail = email?.trim();
  const normalizedPlan = subscriptionType?.trim();
  if (normalizedEmail && normalizedPlan) {
    return `${normalizedEmail} (${normalizedPlan})`;
  }
  if (normalizedEmail) {
    return normalizedEmail;
  }
  if (normalizedPlan) {
    return normalizedPlan;
  }
  return null;
}

function finalizeProviderDecision(
  provider: Provider,
  reason: string,
  availableProviders: Provider[],
  hasAvailabilitySignal: boolean,
  fallback?: Provider
): ProviderDecision {
  if (!hasAvailabilitySignal) {
    return { provider, reason };
  }

  if (availableProviders.includes(provider)) {
    return { provider, reason };
  }

  const preferredFallback = fallback && availableProviders.includes(fallback) ? fallback : availableProviders[0];
  if (preferredFallback) {
    return {
      provider: preferredFallback,
      reason: `${reason}-provider-unavailable-fallback`
    };
  }

  throw new Error(`Provider ${provider} is not available on this host.`);
}

function saveUsageWindows(handle: DatabaseHandle, windows: UsageWindow[]): void {
  const statement = handle.database.prepare(`
    INSERT INTO provider_usage_snapshots (
      provider,
      window_label,
      used_percentage,
      reset_at_utc,
      collected_at_utc,
      raw_payload
    ) VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(provider) DO UPDATE SET
      window_label = excluded.window_label,
      used_percentage = excluded.used_percentage,
      reset_at_utc = excluded.reset_at_utc,
      collected_at_utc = excluded.collected_at_utc,
      raw_payload = excluded.raw_payload
  `);

  for (const window of windows) {
    statement.run(
      window.provider,
      window.window_label,
      window.used_percentage,
      window.reset_at_utc,
      window.collected_at_utc,
      JSON.stringify(window)
    );
  }
}

function normalizeUsagePayload(rawPayload: unknown, forcedProvider?: Provider): UsageWindow[] {
  const payload = typeof rawPayload === "string" ? JSON.parse(rawPayload) : rawPayload;
  const maybeWindows = Array.isArray(payload)
    ? payload
    : typeof payload === "object" && payload !== null && Array.isArray((payload as { windows?: unknown[] }).windows)
      ? (payload as { windows: unknown[] }).windows
      : [payload];

  const windows = maybeWindows
    .filter(Boolean)
    .map((entry) => normalizeUsageWindow(entry as Record<string, unknown>, forcedProvider));

  if (windows.length === 0) {
    throw new Error("Usage payload must contain at least one usage window.");
  }
  return windows;
}

function normalizeUsageWindow(entry: Record<string, unknown>, forcedProvider?: Provider): UsageWindow {
  const provider = (forcedProvider || entry.provider) as Provider | undefined;
  if (provider !== "claude" && provider !== "codex") {
    throw new Error("Usage payload entry is missing a supported provider.");
  }

  return {
    provider,
    window_label: String(entry.window_label || entry.window || "unknown"),
    used_percentage: Number(entry.used_percentage ?? entry.percent_used ?? 0),
    reset_at_utc: String(entry.reset_at_utc || entry.reset_at || nowUtc()),
    collected_at_utc: String(entry.collected_at_utc || entry.collected_at || nowUtc())
  };
}

function runCommand(cliPath: string, args: string[], sessionHome: string): CommandResult {
  try {
    const executable = isNodeScript(cliPath) ? process.execPath : cliPath;
    const finalArgs = isNodeScript(cliPath) ? [cliPath, ...args] : args;
    const result = spawnSync(executable, finalArgs, {
      encoding: "utf8",
      env: {
        ...process.env,
        HOME: sessionHome,
        AAI_PROVIDER_SESSION_HOME: sessionHome
      }
    });

    return {
      status: result.status,
      stdout: result.stdout || "",
      stderr: result.stderr || "",
      error: result.error ? result.error.message : null
    };
  } catch (error) {
    return {
      status: null,
      stdout: "",
      stderr: "",
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

function isNodeScript(filePath: string): boolean {
  return /\.(cjs|mjs|js|ts)$/i.test(filePath);
}
