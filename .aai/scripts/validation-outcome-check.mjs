#!/usr/bin/env node
// validation-outcome-check.mjs — mechanical gate for the single
// `aai-outcome-v1` JSON block in an independent Validation report.
//
// Usage:
//   node .aai/scripts/validation-outcome-check.mjs \
//     --report <path> --ref <scope-ref> --since <ISO-8601 UTC> [--root <repo>]
//
// Exit 0: mechanically admissible. Exit 1: evidence refusal, printed as
// `OUTCOME-CHECK: <reason>`. Exit 2: invalid CLI usage. Node stdlib only; this
// checker reads local bytes and never executes report content or uses a network.
//
// The single accepted schema is JSON object version 1 with:
//   ref, validation_started_utc,
//   sources[{kind:intake|spec,path,sha256}],
//   requirements[{id,source:{path,quote},constraint,spec_ac_ids[],assessment,
//     rationale,required:true,outcome_ids[]}], and
//   outcomes[{id,requirement_ids[],target:{kind,expected_identity,
//     observed_identity,...},verification:{operation,evidence_path,
//     evidence_sha256,observed_at_utc,result},persistence:{applicable,...}}].
// Local-file targets additionally carry consumed_path/consumed_sha256; external
// targets carry dynamic and, when false, immutable_revision. IDs and links are
// unique and reciprocal. An aligned requirement must map to at least one
// Spec-AC. The report wraps this object in exactly one `aai-outcome-v1` fence.

import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ISO_UTC_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|\+00:00)$/;
const SHA256_RE = /^[a-f0-9]{64}$/;
const ASSESSMENTS = new Set(['aligned', 'omitted', 'weakened', 'unknown']);
const RESULTS = new Set(['satisfied', 'violated', 'unknown']);
const TARGET_KINDS = new Set(['repository', 'local_file', 'external']);

function usage(message) {
  if (message) process.stderr.write(`validation-outcome-check: ${message}\n`);
  process.stderr.write('usage: node .aai/scripts/validation-outcome-check.mjs --report <path> --ref <ref> --since <UTC> [--root <repo>]\n');
  return 2;
}

function parseArgs(argv) {
  const options = { root: process.cwd() };
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    if (flag === '--help' || flag === '-h') return { help: true };
    if (!['--report', '--ref', '--since', '--root'].includes(flag)) return { error: `unknown argument: ${flag}` };
    const value = argv[i + 1];
    if (!value || value.startsWith('--')) return { error: `${flag} requires a value` };
    const key = flag.slice(2);
    if (Object.hasOwn(options, key) && key !== 'root') return { error: `duplicate argument: ${flag}` };
    options[key] = value;
    i += 1;
  }
  for (const key of ['report', 'ref', 'since']) {
    if (!options[key]) return { error: `--${key} is required` };
  }
  return { options };
}

function parseUtc(value) {
  if (typeof value !== 'string' || !ISO_UTC_RE.test(value)) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/.exec(value);
  if (!match) return null;
  if (date.getUTCFullYear() !== Number(match[1]) || date.getUTCMonth() + 1 !== Number(match[2])
      || date.getUTCDate() !== Number(match[3]) || date.getUTCHours() !== Number(match[4])
      || date.getUTCMinutes() !== Number(match[5]) || date.getUTCSeconds() !== Number(match[6])) return null;
  return date;
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function resolveLocal(root, relative, label, refuse) {
  if (typeof relative !== 'string' || relative.trim() === '') {
    refuse(`${label} path is missing`);
    return null;
  }
  if (path.isAbsolute(relative)) {
    refuse(`${label} path must be repository-relative: ${relative}`);
    return null;
  }
  const rootAbs = path.resolve(root);
  const resolved = path.resolve(rootAbs, relative);
  if (resolved !== rootAbs && !resolved.startsWith(`${rootAbs}${path.sep}`)) {
    refuse(`${label} path escapes --root: ${relative}`);
    return null;
  }
  return resolved;
}

function readHashedFile(root, entry, label, refuse) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    refuse(`${label} entry is missing or malformed`);
    return null;
  }
  const resolved = resolveLocal(root, entry.path, label, refuse);
  if (!resolved) return null;
  if (!SHA256_RE.test(entry.sha256 ?? '')) {
    refuse(`${label} sha256 is malformed`);
    return null;
  }
  let bytes;
  try {
    bytes = fs.readFileSync(resolved);
  } catch (error) {
    refuse(`${label} is unreadable: ${entry.path} (${error.code ?? error.message})`);
    return null;
  }
  const actual = sha256(bytes);
  if (actual !== entry.sha256) refuse(`${label} hash mismatch: ${entry.path}`);
  return { resolved, bytes, actual };
}

function extractOutcomeBlock(markdown, refuse) {
  const blocks = [];
  let openFence = null;
  for (const line of markdown.split(/\r?\n/)) {
    if (!openFence) {
      const opener = /^(?: {0,3})(`{3,}|~{3,})(.*)$/.exec(line);
      if (!opener) continue;
      openFence = {
        character: opener[1][0],
        length: opener[1].length,
        outcome: opener[2].trim() === 'aai-outcome-v1',
        lines: [],
      };
      continue;
    }
    const closer = /^(?: {0,3})(`{3,}|~{3,})[ \t]*$/.exec(line);
    if (closer && closer[1][0] === openFence.character && closer[1].length >= openFence.length) {
      if (openFence.outcome) blocks.push(openFence.lines.join('\n'));
      openFence = null;
      continue;
    }
    openFence.lines.push(line);
  }
  if (openFence?.outcome) {
    refuse('unterminated aai-outcome-v1 block');
    return null;
  }
  if (blocks.length !== 1) {
    refuse(`expected exactly one aai-outcome-v1 block, found ${blocks.length}`);
    return null;
  }
  try {
    return JSON.parse(blocks[0]);
  } catch (error) {
    refuse(`aai-outcome-v1 JSON is malformed: ${error.message}`);
    return null;
  }
}

function requireString(value, label, refuse) {
  if (typeof value !== 'string' || value.trim() === '') {
    refuse(`${label} must be a nonempty string`);
    return false;
  }
  return true;
}

function uniqueIds(entries, label, refuse) {
  const ids = new Set();
  for (const [index, entry] of entries.entries()) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      refuse(`${label}[${index}] is malformed`);
      continue;
    }
    if (!requireString(entry.id, `${label}[${index}].id`, refuse)) continue;
    if (ids.has(entry.id)) refuse(`duplicate ${label} id: ${entry.id}`);
    ids.add(entry.id);
  }
  return ids;
}

export function checkOutcomeReport({ reportPath, ref, since, root = process.cwd(), now = new Date() }) {
  const reasons = [];
  const refuse = (reason) => {
    if (!reasons.includes(reason)) reasons.push(reason);
  };
  const sinceDate = parseUtc(since);
  if (!sinceDate) return { ok: false, reasons: ['--since is not a valid ISO-8601 UTC timestamp'] };
  const nowDate = now instanceof Date ? now : parseUtc(now);
  if (!nowDate || Number.isNaN(nowDate.getTime())) return { ok: false, reasons: ['checker clock is invalid'] };

  let markdown;
  try {
    markdown = fs.readFileSync(path.resolve(root, reportPath), 'utf8');
  } catch (error) {
    return { ok: false, reasons: [`report is unreadable: ${reportPath} (${error.code ?? error.message})`] };
  }
  const data = extractOutcomeBlock(markdown, refuse);
  if (data === null && reasons.length > 0) return { ok: false, reasons };
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    refuse('outcome block must be a JSON object');
    return { ok: false, reasons, data };
  }
  if (data.version !== 1) refuse(`unsupported outcome schema version: ${JSON.stringify(data.version)}`);
  if (data.ref !== ref) refuse(`report ref mismatch: expected ${ref}, got ${JSON.stringify(data.ref)}`);
  const startedDate = parseUtc(data.validation_started_utc);
  if (!startedDate) refuse('validation_started_utc is invalid');
  else if (startedDate.getTime() > nowDate.getTime()) refuse('validation_started_utc is in the future');

  if (!Array.isArray(data.sources) || data.sources.length < 2) refuse('sources must contain intake and frozen spec entries');
  const sourcePaths = new Set();
  const sourceKinds = new Set();
  if (Array.isArray(data.sources)) {
    for (const [index, source] of data.sources.entries()) {
      if (!source || typeof source !== 'object' || Array.isArray(source)) {
        refuse(`sources[${index}] is malformed`);
        continue;
      }
      if (!['intake', 'spec'].includes(source.kind)) refuse(`sources[${index}].kind must be intake or spec`);
      if (sourceKinds.has(source.kind)) refuse(`duplicate source kind: ${source.kind}`);
      sourceKinds.add(source.kind);
      if (sourcePaths.has(source.path)) refuse(`duplicate source path: ${source.path}`);
      sourcePaths.add(source.path);
      readHashedFile(root, source, `source ${source.kind ?? index}`, refuse);
    }
  }
  for (const kind of ['intake', 'spec']) if (!sourceKinds.has(kind)) refuse(`missing ${kind} source`);

  if (!Array.isArray(data.requirements) || data.requirements.length === 0) refuse('requirement inventory must be nonempty');
  if (!Array.isArray(data.outcomes) || data.outcomes.length === 0) refuse('outcomes must be nonempty');
  const requirements = Array.isArray(data.requirements) ? data.requirements : [];
  const outcomes = Array.isArray(data.outcomes) ? data.outcomes : [];
  const requirementIds = uniqueIds(requirements, 'requirement', refuse);
  const outcomeIds = uniqueIds(outcomes, 'outcome', refuse);
  const validIdEntry = (entry) => entry && typeof entry === 'object' && !Array.isArray(entry)
    && typeof entry.id === 'string' && entry.id.trim() !== '';
  const requirementById = new Map(requirements.filter(validIdEntry).map((entry) => [entry.id, entry]));
  const outcomeById = new Map(outcomes.filter(validIdEntry).map((entry) => [entry.id, entry]));

  const linkedRequirements = new Set();
  for (const requirement of requirements) {
    if (!requirement || typeof requirement !== 'object') continue;
    requireString(requirement.constraint, `requirement ${requirement.id}.constraint`, refuse);
    requireString(requirement.rationale, `requirement ${requirement.id}.rationale`, refuse);
    if (!requirement.source || typeof requirement.source !== 'object') {
      refuse(`requirement ${requirement.id} source citation is missing`);
    } else {
      if (!sourcePaths.has(requirement.source.path)) refuse(`requirement ${requirement.id} cites an undeclared source path`);
      requireString(requirement.source.quote, `requirement ${requirement.id} source quote`, refuse);
    }
    if (!Array.isArray(requirement.spec_ac_ids)) refuse(`requirement ${requirement.id}.spec_ac_ids must be an array`);
    else if (requirement.spec_ac_ids.some((id) => typeof id !== 'string' || id.trim() === '')) {
      refuse(`requirement ${requirement.id} has malformed Spec-AC link`);
    } else if (requirement.assessment === 'aligned' && requirement.spec_ac_ids.length === 0) {
      refuse(`aligned requirement ${requirement.id} must map to at least one Spec-AC`);
    } else if (new Set(requirement.spec_ac_ids).size !== requirement.spec_ac_ids.length) {
      refuse(`requirement ${requirement.id} has duplicate Spec-AC links`);
    }
    if (!ASSESSMENTS.has(requirement.assessment)) refuse(`requirement ${requirement.id} assessment is invalid`);
    else if (requirement.assessment !== 'aligned') refuse(`requirement ${requirement.id} is ${requirement.assessment}`);
    if (requirement.required !== true) refuse(`requirement ${requirement.id} must declare required: true`);
    if (!Array.isArray(requirement.outcome_ids) || requirement.outcome_ids.length === 0) {
      refuse(`requirement ${requirement.id} has no outcome links`);
    } else {
      const seenLinks = new Set();
      for (const outcomeId of requirement.outcome_ids) {
        if (typeof outcomeId !== 'string' || outcomeId.trim() === '') {
          refuse(`requirement ${requirement.id} has malformed outcome link`);
          continue;
        }
        if (seenLinks.has(outcomeId)) refuse(`requirement ${requirement.id} has duplicate outcome link: ${outcomeId}`);
        seenLinks.add(outcomeId);
        if (!outcomeIds.has(outcomeId)) refuse(`requirement ${requirement.id} has dangling outcome link: ${outcomeId}`);
        else if (!Array.isArray(outcomeById.get(outcomeId)?.requirement_ids)
          || !outcomeById.get(outcomeId).requirement_ids.includes(requirement.id)) {
          refuse(`requirement ${requirement.id} link to ${outcomeId} is not reciprocal`);
        }
      }
    }
  }

  for (const outcome of outcomes) {
    if (!outcome || typeof outcome !== 'object') continue;
    if (!Array.isArray(outcome.requirement_ids) || outcome.requirement_ids.length === 0) {
      refuse(`outcome ${outcome.id} has no requirement links`);
    } else {
      const seenLinks = new Set();
      for (const requirementId of outcome.requirement_ids) {
        if (typeof requirementId !== 'string' || requirementId.trim() === '') {
          refuse(`outcome ${outcome.id} has malformed requirement link`);
          continue;
        }
        if (seenLinks.has(requirementId)) refuse(`outcome ${outcome.id} has duplicate requirement link: ${requirementId}`);
        seenLinks.add(requirementId);
        if (!requirementIds.has(requirementId)) refuse(`outcome ${outcome.id} has dangling requirement link: ${requirementId}`);
        else if (!Array.isArray(requirementById.get(requirementId)?.outcome_ids)
          || !requirementById.get(requirementId).outcome_ids.includes(outcome.id)) {
          refuse(`outcome ${outcome.id} link to ${requirementId} is not reciprocal`);
        }
        linkedRequirements.add(requirementId);
      }
    }
    const target = outcome.target;
    if (!target || typeof target !== 'object' || !TARGET_KINDS.has(target.kind)) {
      refuse(`outcome ${outcome.id} target kind is invalid`);
      continue;
    }
    requireString(target.expected_identity, `outcome ${outcome.id} expected identity`, refuse);
    requireString(target.observed_identity, `outcome ${outcome.id} observed identity`, refuse);
    if (target.kind === 'local_file') {
      const expectedPath = resolveLocal(root, target.expected_identity, `outcome ${outcome.id} expected target`, refuse);
      const observedPath = resolveLocal(root, target.observed_identity, `outcome ${outcome.id} observed target`, refuse);
      if (expectedPath && observedPath && expectedPath !== observedPath) refuse(`outcome ${outcome.id} target identity mismatch`);
    } else if (target.expected_identity !== target.observed_identity) {
      refuse(`outcome ${outcome.id} target identity mismatch`);
    }

    const verification = outcome.verification;
    if (!verification || typeof verification !== 'object') {
      refuse(`outcome ${outcome.id} verification is missing`);
      continue;
    }
    requireString(verification.operation, `outcome ${outcome.id} verification operation`, refuse);
    readHashedFile(root, { path: verification.evidence_path, sha256: verification.evidence_sha256 }, `outcome ${outcome.id} evidence`, refuse);
    const observedDate = parseUtc(verification.observed_at_utc);
    if (!observedDate) refuse(`outcome ${outcome.id} observation timestamp is invalid`);
    else if (observedDate.getTime() > nowDate.getTime()) refuse(`outcome ${outcome.id} observation is in the future`);
    if (!RESULTS.has(verification.result)) refuse(`outcome ${outcome.id} result is invalid`);
    else if (verification.result !== 'satisfied') refuse(`outcome ${outcome.id} result is ${verification.result}`);

    const persistence = outcome.persistence;
    if (!persistence || typeof persistence !== 'object' || typeof persistence.applicable !== 'boolean') {
      refuse(`outcome ${outcome.id} persistence applicability is missing`);
    } else if (persistence.applicable) {
      if (!['saved', 'exported', 'applied'].includes(persistence.boundary)) refuse(`outcome ${outcome.id} persistence boundary is invalid`);
      if (!/read[- ]?back|reopen/i.test(verification.operation ?? '')) refuse(`outcome ${outcome.id} lacks a read-back or reopen operation`);
    } else {
      requireString(persistence.reason, `outcome ${outcome.id} persistence not-applicable reason`, refuse);
    }

    if (target.kind === 'local_file') {
      const expectedPath = resolveLocal(root, target.expected_identity, `outcome ${outcome.id} expected target`, refuse);
      const consumedPath = resolveLocal(root, target.consumed_path, `outcome ${outcome.id} consumed target`, refuse);
      if (expectedPath && consumedPath && expectedPath !== consumedPath) refuse(`outcome ${outcome.id} consumed path does not match expected target`);
      const consumed = readHashedFile(root, { path: target.consumed_path, sha256: target.consumed_sha256 }, `outcome ${outcome.id} consumed file`, refuse);
      if (consumed && persistence?.applicable !== true) refuse(`outcome ${outcome.id} local file must declare persistence applicable`);
    } else if (target.kind === 'external') {
      if (typeof target.dynamic !== 'boolean') refuse(`outcome ${outcome.id} external target must declare dynamic`);
      if (target.dynamic === true && observedDate && observedDate.getTime() < sinceDate.getTime()) {
        refuse(`outcome ${outcome.id} dynamic observation predates verification horizon`);
      }
      if (target.dynamic === false) requireString(target.immutable_revision, `outcome ${outcome.id} immutable revision`, refuse);
    }
  }
  for (const requirementId of requirementIds) {
    if (!linkedRequirements.has(requirementId)) refuse(`requirement ${requirementId} is not linked back from an outcome`);
  }
  return { ok: reasons.length === 0, reasons, data };
}

export function formatOutcomeRefusals(result) {
  return result.reasons.map((reason) => `OUTCOME-CHECK: ${reason}`);
}

function main() {
  const parsed = parseArgs(process.argv.slice(2));
  if (parsed.help) {
    process.stdout.write('validation-outcome-check.mjs — validate one aai-outcome-v1 JSON report block\n\n');
    process.stdout.write('Schema: version/ref/start, intake+spec sources, reciprocal requirements/outcomes, target identity, hashed evidence, persistence and freshness.\n');
    process.stdout.write('usage: node .aai/scripts/validation-outcome-check.mjs --report <path> --ref <ref> --since <UTC> [--root <repo>]\n');
    return 0;
  }
  if (parsed.error) return usage(parsed.error);
  if (!parseUtc(parsed.options.since)) return usage('--since is not a valid ISO-8601 UTC timestamp');
  const result = checkOutcomeReport({
    reportPath: parsed.options.report,
    ref: parsed.options.ref,
    since: parsed.options.since,
    root: parsed.options.root,
  });
  if (result.ok) return 0;
  for (const line of formatOutcomeRefusals(result)) process.stdout.write(`${line}\n`);
  return 1;
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) process.exitCode = main();
