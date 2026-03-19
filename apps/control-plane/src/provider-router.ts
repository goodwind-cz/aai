export type Provider = 'claude' | 'codex';

export type UsageWindow = {
  provider: Provider;
  window_label: string;
  used_percentage: number;
  reset_at_utc: string;
  collected_at_utc: string;
};

export type RoutingPolicy = {
  preferred: Provider | 'auto';
  fallback: Provider;
  strict_single_provider: boolean;
};

export function chooseProvider(policy: RoutingPolicy, usage: UsageWindow[]): Provider {
  if (policy.preferred !== 'auto') return policy.preferred;
  const claude = usage.find((u) => u.provider === 'claude');
  const codex = usage.find((u) => u.provider === 'codex');
  if (!claude) return 'codex';
  if (!codex) return 'claude';
  return claude.used_percentage <= codex.used_percentage ? 'claude' : 'codex';
}
