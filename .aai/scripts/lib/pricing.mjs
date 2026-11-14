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
  const sources = Object.create(null);
  const costBlend = { input_share: null };
  let section = null;
  let current = null;
  let currentSource = null;
  for (const line of String(raw).split(/\r?\n/)) {
    if (/^\S/.test(line)) {
      const m = line.match(/^([A-Za-z_][\w-]*):/);
      section = m ? m[1] : null;
      current = null;
      currentSource = null;
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
        models[current] = { input: null, output: null, source_ref: null };
        continue;
      }
      if (!current) continue;
      m = line.match(/^ {4}(\w+):\s*(.*)$/);
      if (!m) continue;
      const v = unq(m[2].replace(/\s+#.*$/, ''));
      if (m[1] === 'input_usd_per_m') models[current].input = v === 'null' ? null : Number(v);
      if (m[1] === 'output_usd_per_m') models[current].output = v === 'null' ? null : Number(v);
      if (m[1] === 'source_ref') models[current].source_ref = v === 'null' || v === '' ? null : v;
    } else if (section === 'sources') {
      let m = line.match(/^ {2}([^\s:]+):\s*$/);
      if (m) {
        currentSource = unq(m[1]);
        sources[currentSource] = { provider: null };
        continue;
      }
      if (!currentSource) continue;
      m = line.match(/^ {4}provider:\s*(.*)$/);
      if (m) {
        const v = unq(m[1].replace(/\s+#.*$/, ''));
        sources[currentSource].provider = v === 'null' || v === '' ? null : v;
      }
    } else if (section === 'cost_blend') {
      const m = line.match(/^ {2}(\w+):\s*(.*)$/);
      if (m && m[1] === 'input_share') {
        const v = unq(m[2].replace(/\s+#.*$/, ''));
        costBlend.input_share = v === 'null' || v === '' ? null : Number(v);
      }
    }
  }
  return { aliases, models, sources, costBlend };
}

export function loadPricing(pricingPath) {
  try {
    return parsePricing(fs.readFileSync(pricingPath, 'utf8'));
  } catch {
    return { aliases: {}, models: {}, sources: Object.create(null), costBlend: { input_share: null } };
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

function hasRates(entry) {
  return !!entry && entry.input !== null && entry.output !== null
    && Number.isFinite(entry.input) && Number.isFinite(entry.output);
}

// attachProjectPrices(pricing, prices) -> a copy of pricing carrying the
// consumer's project prices as `project` (D-PREC; see resolvePrice).
export function attachProjectPrices(pricing, prices) {
  return { ...pricing, project: prices };
}

// resolveProjectKey(prices, id) -> key | null: strip ONE trailing bracket
// suffix, then exact key, then the longest key that is a prefix of the id.
// No alias step (aliases belong to the shipped table).
export function resolveProjectKey(prices, id) {
  return projectExactKey(prices, id) ?? projectPrefixKey(prices, id);
}

function projectBare(id) {
  return String(id ?? '').trim().replace(/\[[^\]]*\]$/, '');
}
function projectExactKey(prices, id) {
  const bare = projectBare(id);
  return Object.prototype.hasOwnProperty.call(prices, bare) ? bare : null;
}
function projectPrefixKey(prices, id) {
  const bare = projectBare(id);
  let best = null;
  for (const key of Object.keys(prices)) {
    if (bare.startsWith(key) && (best === null || key.length > best.length)) best = key;
  }
  return best;
}

// shipped exact key: bracket strip + alias + exact models key (null if none).
function shippedExactKey(pricing, runtimeId) {
  const { aliases, models } = pricing;
  let id = String(runtimeId ?? '').trim().replace(/\[[^\]]*\]$/, '');
  if (Object.prototype.hasOwnProperty.call(aliases, id)) id = aliases[id];
  return { id, key: Object.prototype.hasOwnProperty.call(models, id) ? id : null };
}
function shippedPrefixKey(pricing, id) {
  let best = null;
  for (const key of Object.keys(pricing.models)) {
    if (key !== 'unknown' && id.startsWith(key) && (best === null || key.length > best.length)) best = key;
  }
  return best;
}

// resolvePrice(pricing, modelId) -> { source: 'shipped'|'project', key, entry } | null
// D-PREC lookup order: shipped exact, project exact, shipped longest-prefix,
// project longest-prefix, unknown (null). An EXACT project price therefore
// beats a shipped PREFIX match, and the shipped table still wins an exact id.
// A shipped exact row that carries no rates is skipped (and, as before, stops
// the shipped prefix step); only rows carrying both rates are returned.
export function resolvePrice(pricing, modelId) {
  const project = pricing.project ? pricing.project : null;
  const { id, key: exact } = shippedExactKey(pricing, modelId);
  if (exact !== null && hasRates(pricing.models[exact])) return { source: 'shipped', key: exact, entry: pricing.models[exact] };
  if (project !== null) {
    const pk = projectExactKey(project, modelId);
    if (pk !== null && hasRates(project[pk])) return { source: 'project', key: pk, entry: project[pk] };
  }
  if (exact === null) {
    const sk = shippedPrefixKey(pricing, id);
    if (sk !== null && hasRates(pricing.models[sk])) return { source: 'shipped', key: sk, entry: pricing.models[sk] };
  }
  if (project !== null) {
    const pk = projectPrefixKey(project, modelId);
    if (pk !== null && hasRates(project[pk])) return { source: 'project', key: pk, entry: project[pk] };
  }
  return null;
}

function rateEntry(pricing, modelId) {
  const r = resolvePrice(pricing, modelId);
  return r === null ? null : r.entry;
}

// priceSource(pricing, modelId) -> 'shipped' | 'project' | null, same order.
export function priceSource(pricing, modelId) {
  const r = resolvePrice(pricing, modelId);
  return r === null ? null : r.source;
}

// shippedExactPriced(pricing, modelId) -> true when the shipped table prices the
// id by an exact (bracket-stripped, aliased) match: the only case where a
// project row is shadowed (D-PREC).
export function shippedExactPriced(pricing, modelId) {
  const { key } = shippedExactKey(pricing, modelId);
  return key !== null && hasRates(pricing.models[key]);
}

// modelProvider(pricing, modelId) -> provider string | null: the provider of
// the row that prices the id (resolvePrice); for an id nothing prices, the
// shipped row's source provider, else null.
export function modelProvider(pricing, modelId) {
  const r = resolvePrice(pricing, modelId);
  if (r !== null && r.source === 'project') return r.entry.provider ?? null;
  const key = r !== null ? r.key : resolveModelKey(pricing, modelId);
  if (key !== 'unknown') {
    const ref = pricing.models[key].source_ref;
    const src = pricing.sources && ref ? pricing.sources[ref] : null;
    return src ? src.provider : null;
  }
  const project = pricing.project ? pricing.project : null;
  if (project === null) return null;
  const pk = resolveProjectKey(project, modelId);
  return pk === null ? null : (project[pk].provider ?? null);
}

// runCostUsd(pricing, modelId, tokensIn, tokensOut) -> number | null.
// Cost exists ONLY when both token counts are integers AND the resolved entry
// carries both rates — anything else is null, never estimated.
export function runCostUsd(pricing, modelId, tokensIn, tokensOut) {
  if (typeof tokensIn !== 'number' || typeof tokensOut !== 'number') return null;
  const entry = rateEntry(pricing, modelId);
  if (!hasRates(entry)) return null;
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
  const entry = rateEntry(pricing, modelId);
  if (!hasRates(entry)) return null;
  const share = (pricing.costBlend && typeof pricing.costBlend.input_share === 'number'
    && Number.isFinite(pricing.costBlend.input_share)) ? pricing.costBlend.input_share : 0.5;
  const cost = (total * (share * entry.input + (1 - share) * entry.output)) / 1_000_000;
  const bounds = [(total * entry.input) / 1_000_000, (total * entry.output) / 1_000_000];
  return { cost, bounds };
}
