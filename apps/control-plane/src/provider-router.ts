import { readJson } from "./common.ts";

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

export function loadUsageWindows(filePath: string): UsageWindow[] {
  const payload = readJson<{ windows: UsageWindow[] }>(filePath);
  if (!Array.isArray(payload.windows)) {
    throw new Error("Usage payload must contain a windows array");
  }
  return payload.windows;
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
}): ProviderDecision {
  const {
    policy,
    fallback,
    strictSingleProvider = false,
    operatorOverride = null,
    usage = [],
    phasePreference = "auto"
  } = options;

  if (operatorOverride && operatorOverride !== "auto") {
    return { provider: operatorOverride as Provider, reason: "operator-override" };
  }

  if (policy && policy !== "auto") {
    return { provider: policy as Provider, reason: "project-policy-explicit" };
  }

  if (phasePreference && phasePreference !== "auto") {
    return { provider: phasePreference as Provider, reason: "phase-preference" };
  }

  const claude = usage.find((entry) => entry.provider === "claude");
  const codex = usage.find((entry) => entry.provider === "codex");

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

  if (claude.used_percentage === codex.used_percentage) {
    return { provider: fallback || "claude", reason: "usage-tie-fallback" };
  }

  return claude.used_percentage < codex.used_percentage
    ? { provider: "claude", reason: "lowest-usage" }
    : { provider: "codex", reason: "lowest-usage" };
}
