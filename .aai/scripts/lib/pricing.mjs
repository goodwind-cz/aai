// pricing.mjs — shared PRICING.yaml parser + lookup_rules resolver
// (CHANGE-0009 D6/D7: metrics-flush.mjs and metrics-report.mjs must share ONE
// resolver so cost arithmetic can never fork between flush and report).
//
// Line-discipline parse (no YAML library, per docs/TECHNOLOGY.md) — the same
// 2-space-key scan the pricing contract suite (tests/skills/test-aai-pricing.sh)
// implements verbatim. Resolution order (CHANGE-0010 D4 lookup_rules):
//   1. strip-bracket-suffix: remove ONE trailing `[...]` from the runtime id
//   2. model-aliases: apply the model_aliases map
//   3. exact-match: exact key in models
//   4. longest-prefix: longest models key that is a prefix of the id
//   5. unknown-fallback: the `unknown` entry

import fs from 'node:fs';

function unq(s) {
  s = s.trim();
  if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) return s.slice(1, -1);
  if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) return s.slice(1, -1).replace(/''/g, "'");
  return s;
}

// parsePricing(raw) -> { aliases: {id: key}, models: {key: {input, output}},
// costBlend: {input_share} } — input/output are numbers or null (unpriced);
// costBlend.input_share is a number or null (telemetry-fields-not-prose D5).
export function parsePricing(raw) {
  const aliases = {};
  const models = {};
  const costBlend = { input_share: null };
  let section = null;
  let current = null;
  for (const line of String(raw).split(/\r?\n/)) {
    if (/^\S/.test(line)) {
      const m = line.match(/^([A-Za-z_][\w-]*):/);
      section = m ? m[1] : null;
      current = null;
      continue;
    }
    if (line.trim() === '' || line.trim().startsWith('#')) continue;
    if (section === 'model_aliases') {
      const m = line.match(/^ {2}(\S+|"[^"]*"):\s*(\S+)\s*$/);
      if (m) aliases[unq(m[1])] = unq(m[2]);
    } else if (section === 'models') {
      let m = line.match(/^ {2}([^\s:]+):\s*$/);
      if (m) {
        current = unq(m[1]);
        models[current] = { input: null, output: null };
        continue;
      }
      if (!current) continue;
      m = line.match(/^ {4}(\w+):\s*(.*)$/);
      if (!m) continue;
      const v = unq(m[2].replace(/\s+#.*$/, ''));
      if (m[1] === 'input_usd_per_m') models[current].input = v === 'null' ? null : Number(v);
      if (m[1] === 'output_usd_per_m') models[current].output = v === 'null' ? null : Number(v);
    } else if (section === 'cost_blend') {
      const m = line.match(/^ {2}(\w+):\s*(.*)$/);
      if (m && m[1] === 'input_share') {
        const v = unq(m[2].replace(/\s+#.*$/, ''));
        costBlend.input_share = v === 'null' || v === '' ? null : Number(v);
      }
    }
  }
  return { aliases, models, costBlend };
}

export function loadPricing(pricingPath) {
  try {
    return parsePricing(fs.readFileSync(pricingPath, 'utf8'));
  } catch {
    return { aliases: {}, models: {}, costBlend: { input_share: null } };
  }
}

// resolveModelKey(pricing, runtimeId) -> models key ('unknown' fallback),
// applying the lookup_rules steps IN ORDER.
export function resolveModelKey(pricing, runtimeId) {
  const { aliases, models } = pricing;
  let id = String(runtimeId ?? '').trim().replace(/\[[^\]]*\]$/, '');   // rule 1
  if (Object.prototype.hasOwnProperty.call(aliases, id)) id = aliases[id];   // rule 2
  if (Object.prototype.hasOwnProperty.call(models, id)) return id;           // rule 3
  let best = null;                                                           // rule 4
  for (const key of Object.keys(models)) {
    if (key !== 'unknown' && id.startsWith(key) && (best === null || key.length > best.length)) best = key;
  }
  if (best !== null) return best;
  return 'unknown';                                                          // rule 5
}

// runCostUsd(pricing, modelId, tokensIn, tokensOut) -> number | null.
// Cost exists ONLY when both token counts are integers AND the resolved entry
// carries both rates — anything else is null, never estimated.
export function runCostUsd(pricing, modelId, tokensIn, tokensOut) {
  if (typeof tokensIn !== 'number' || typeof tokensOut !== 'number') return null;
  const entry = pricing.models[resolveModelKey(pricing, modelId)];
  if (!entry || entry.input === null || entry.output === null
    || !Number.isFinite(entry.input) || !Number.isFinite(entry.output)) return null;
  return (tokensIn * entry.input + tokensOut * entry.output) / 1_000_000;
}

// blendedCostUsd(pricing, modelId, total) -> {cost, bounds:[allInput, allOutput]}
// | null (telemetry-fields-not-prose D5). Used ONLY when a run has no
// tokens_in/tokens_out split but does carry a token TOTAL (from the
// tokens_total field or, failing that, the usage_total_tokens= note marker —
// the caller resolves which). `share` is READ from the pricing table's
// cost_blend.input_share (never hardcoded here); its shipped value is a
// documented CONVENTION (PRICING.yaml), not a measurement — the repository
// has no recorded input/output ratio of its own. Falls back to the midpoint
// 0.5 only when the config omits the key entirely (never a silent 0 or 1).
// null (never NaN/0) whenever the resolved model carries no rates — an
// unpriced model must never fabricate a number.
export function blendedCostUsd(pricing, modelId, total) {
  if (typeof total !== 'number' || !Number.isFinite(total)) return null;
  const entry = pricing.models[resolveModelKey(pricing, modelId)];
  if (!entry || entry.input === null || entry.output === null
    || !Number.isFinite(entry.input) || !Number.isFinite(entry.output)) return null;
  const share = (pricing.costBlend && typeof pricing.costBlend.input_share === 'number'
    && Number.isFinite(pricing.costBlend.input_share)) ? pricing.costBlend.input_share : 0.5;
  const cost = (total * (share * entry.input + (1 - share) * entry.output)) / 1_000_000;
  const bounds = [(total * entry.input) / 1_000_000, (total * entry.output) / 1_000_000];
  return { cost, bounds };
}
