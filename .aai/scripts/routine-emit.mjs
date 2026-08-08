#!/usr/bin/env node
// routine-emit.mjs — on-demand, agent-neutral standing-routine instantiator
// (CHANGE-0128-universal-routines / SPEC-DRAFT-spec-universal-routines.md).
//
// PURPOSE
//   Renders a vendored routine template (.aai/routines/<NAME>.routine.md)
//   with the caller's placeholders, checks a machine-readable merge
//   authorization record before ever emitting a merge-enabled contract, and
//   prints the harness-appropriate installation payload. EMIT-ONLY (D4):
//   this script writes NOTHING to crontab, launchd, Task Scheduler, or any
//   network API. Everything is text on stdout for the operator (or the
//   harness's own scheduling skill) to install.
//
// CLI GRAMMAR (frozen)
//   node .aai/scripts/routine-emit.mjs --routine <NAME> \
//     --harness <claude|codex|gemini|generic> --os <macos|linux|windows> \
//     --repo <slug> --schedule "<cron>" --model <id> --tz <zone> \
//     [--merge --ref <ref>] [--decisions <path>]
//
//   --routine <NAME>     routine template name; loads .aai/routines/<NAME>.routine.md
//   --harness <h>        claude | codex | gemini | generic
//   --os <o>              macos | linux | windows
//   --repo <slug>         substituted into {{REPO}}
//   --schedule <cron>     substituted into {{SCHEDULE}} and the crontab/task fields
//   --model <id>          substituted into {{MODEL}}
//   --tz <zone>           IANA timezone; claude payload `timezone` field only
//                         (not a template placeholder)
//   --merge               request the merge-enabled variant (requires --ref)
//   --ref <ref>           routine_authorization ref to check (required with --merge)
//   --decisions <path>    override the decisions ledger path (default
//                         docs/ai/decisions.jsonl under the project root;
//                         test/offline override, same convention as the
//                         rest of the AAI script layer)
//   -h / --help           print usage, exit 0
//
// MERGE-RIGHTS GUARD (D2 / Spec-AC-04)
//   With --merge, the ledger is scanned line-by-line for a JSON object
//   satisfying ALL FOUR: type === "routine_authorization", ref === --ref,
//   by === "human", grants includes "merge". Found -> merge-enabled variant.
//   Not found (including: file absent, file unreadable, a line that fails
//   JSON.parse, or every parseable line missing one of the four fields) ->
//   report-only variant, PLUS a loud line on stderr:
//     MERGE DISABLED — no routine_authorization record for ref=<ref> in <path>
//   and exit 0 (never a non-zero exit for a degraded-but-successful emission).
//   Fail-closed: any read/parse error is NO authorization, never skips the
//   check or throws past it. --merge omitted -> report-only silently (an
//   explicit choice, not a degradation — no loud line).
//
// TEMPLATE CONTRACT (Spec-AC-01/02)
//   The template's `## Placeholders` section is stripped before emission
//   (it is authoring-time documentation, not part of the routine itself).
//   A `<!-- MERGE-GATES:START -->` / `<!-- MERGE-GATES:END -->` marker pair
//   delimits the merge-gate section: merge-enabled keeps the interior (marker
//   lines removed), report-only removes the whole block. {{REPO}}, {{SCHEDULE}},
//   {{MODEL}}, {{MERGE_ALLOWED}} are substituted literally (no regex).
//
// PER-HARNESS EMISSION (Spec-AC-03 / D1)
//   claude   — ONE line of JSON.parse-able JSON
//              {name,cron,timezone,model,repo,merge_enabled,prompt}, `prompt`
//              equal to the rendered contract, then a one-line handoff
//              instruction naming Claude's own `schedule` skill as installer.
//   codex/gemini/generic + macos/linux — a crontab line carrying --schedule
//              verbatim, a POSIX `sh` runner invoking the named agent CLI
//              headless against a prompt file, and the rendered contract to
//              save into that prompt file.
//   codex/gemini/generic + windows      — a PowerShell Register-ScheduledTask
//              twin of the same runner.
//   Every non-claude emission prints BOTH twin filenames (<name>.sh and
//   <name>.ps1), regardless of which --os body is shown, so the operator
//   knows both exist.
//   Every emission (all 4 harnesses x both merge modes) ENDS with a
//   `## TEST AT CREATION` block (Spec-AC-07 / memory rule
//   cloud-routine-test-at-creation): a harness-appropriate immediate
//   fire command, and the three things to verify.
//
// CROSS-PLATFORM (hard rule): Node stdlib only, zero network, no hardcoded
// POSIX paths (os.homedir() untouched here — nothing under this script reads
// the operator's home directory, all paths are project-relative or CLI args).
//
// EXIT CODES (closed set)
//   0  emitted (including the degraded report-only case)
//   2  usage error (unknown flag, missing/invalid flag value, missing
//      template) — nothing printed to stdout

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PREFIX = 'routine-emit';
const HARNESSES = new Set(['claude', 'codex', 'gemini', 'generic']);
const OSES = new Set(['macos', 'linux', 'windows']);

const __filename = fileURLToPath(import.meta.url);
const PROJECT_ROOT = path.resolve(path.dirname(__filename), '..', '..');

function fail(msg) {
  process.stderr.write(`${PREFIX}: ${msg}\n`);
  process.exit(2);
}

function usage() {
  process.stdout.write(
    [
      'Usage: node routine-emit.mjs --routine <NAME> --harness <claude|codex|gemini|generic>',
      '         --os <macos|linux|windows> --repo <slug> --schedule "<cron>" --model <id>',
      '         --tz <zone> [--merge --ref <ref>] [--decisions <path>]',
      '',
      'Renders a vendored routine template and prints the harness-appropriate',
      'installation payload. EMIT-ONLY: writes nothing to any scheduler or API.',
      '',
      '  --merge            request the merge-enabled variant (requires --ref)',
      '  --ref <ref>        routine_authorization ref to check (with --merge)',
      '  --decisions <path> override the decisions ledger path',
      '',
      'Exit: 0 on any emission (including degraded report-only) | 2 usage error',
      '      (nothing printed to stdout).',
    ].join('\n') + '\n',
  );
  process.exit(0);
}

function parseArgs(argv) {
  const args = {
    routine: null,
    harness: null,
    os: null,
    repo: null,
    schedule: null,
    model: null,
    tz: null,
    merge: false,
    ref: null,
    decisions: null,
  };
  const KNOWN = new Set([
    '--routine', '--harness', '--os', '--repo', '--schedule', '--model', '--tz',
    '--merge', '--ref', '--decisions',
  ]);
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '-h' || tok === '--help') {
      usage();
    } else if (tok === '--merge') {
      args.merge = true;
    } else if (KNOWN.has(tok)) {
      const v = argv[i + 1];
      if (v === undefined || (v.startsWith('--') && v !== '-')) fail(`${tok} requires a value`);
      const key = tok.slice(2);
      args[key] = v;
      i += 1;
    } else {
      fail(`unknown flag "${tok}"`);
    }
  }
  const REQUIRED = ['routine', 'harness', 'os', 'repo', 'schedule', 'model', 'tz'];
  for (const key of REQUIRED) {
    if (!args[key]) fail(`--${key} is required`);
  }
  if (!HARNESSES.has(args.harness)) {
    fail(`--harness must be one of: ${[...HARNESSES].join(', ')} (got "${args.harness}")`);
  }
  if (!OSES.has(args.os)) {
    fail(`--os must be one of: ${[...OSES].join(', ')} (got "${args.os}")`);
  }
  if (args.merge && !args.ref) {
    fail('--ref is required with --merge');
  }
  return args;
}

// --- template load + render (Spec-AC-01/02, seam S1) -----------------------

function loadTemplate(routine) {
  const p = path.join(PROJECT_ROOT, '.aai', 'routines', `${routine}.routine.md`);
  try {
    return fs.readFileSync(p, 'utf8');
  } catch {
    fail(`unknown routine "${routine}" (expected ${p})`);
  }
  return '';
}

// stripPlaceholdersBlock: the `## Placeholders` section is authoring-time
// documentation (it necessarily writes out literal {{TOKEN}} examples) —
// never part of the emitted routine.
function stripPlaceholdersBlock(text) {
  const lines = text.split('\n');
  const startIdx = lines.findIndex((l) => l.trim() === '## Placeholders');
  if (startIdx === -1) return text;
  let endIdx = lines.length;
  for (let i = startIdx + 1; i < lines.length; i += 1) {
    if (/^##\s/.test(lines[i])) {
      endIdx = i;
      break;
    }
  }
  lines.splice(startIdx, endIdx - startIdx);
  return lines.join('\n');
}

const GATE_START = '<!-- MERGE-GATES:START -->';
const GATE_END = '<!-- MERGE-GATES:END -->';

function applyMergeGate(text, mergeAllowed) {
  const startIdx = text.indexOf(GATE_START);
  const endIdx = text.indexOf(GATE_END);
  if (startIdx === -1 || endIdx === -1) return text;
  const before = text.slice(0, startIdx);
  const interior = text.slice(startIdx + GATE_START.length, endIdx);
  const after = text.slice(endIdx + GATE_END.length);
  if (mergeAllowed) {
    // keep interior content, drop only the marker comment lines
    return before + interior.replace(/^\n/, '') + after;
  }
  // drop the whole block including markers
  return before + after;
}

function substitute(text, vars) {
  let out = text;
  for (const [k, v] of Object.entries(vars)) {
    out = out.split(`{{${k}}}`).join(v);
  }
  return out;
}

// collapse 3+ consecutive blank lines down to 1, and trim to a single
// trailing newline — cosmetic tidy-up after section removal.
function tidy(text) {
  return text.replace(/\n{3,}/g, '\n\n').trim() + '\n';
}

function renderTemplate(raw, vars, mergeAllowed) {
  let body = stripPlaceholdersBlock(raw);
  body = applyMergeGate(body, mergeAllowed);
  body = substitute(body, {
    REPO: vars.repo,
    SCHEDULE: vars.schedule,
    MODEL: vars.model,
    MERGE_ALLOWED: mergeAllowed ? 'true' : 'false',
  });
  return tidy(body);
}

// --- merge-rights guard (D2 / Spec-AC-04, seam S2) --------------------------

function defaultDecisionsPath() {
  return path.join(PROJECT_ROOT, 'docs', 'ai', 'decisions.jsonl');
}

// checkAuthorization: fail-closed. Any read failure -> false. Any single
// line that fails JSON.parse is skipped (not fatal) so one malformed/
// truncated line never masks a valid record elsewhere in the ledger, and
// never masks the "no match" case either — both fold to `false`.
function checkAuthorization(decisionsPath, ref) {
  let raw;
  try {
    raw = fs.readFileSync(decisionsPath, 'utf8');
  } catch {
    return false;
  }
  const lines = raw.split('\n');
  for (const line of lines) {
    const t = line.trim();
    if (!t) continue;
    let obj;
    try {
      obj = JSON.parse(t);
    } catch {
      continue;
    }
    if (
      obj &&
      obj.type === 'routine_authorization' &&
      obj.ref === ref &&
      obj.by === 'human' &&
      Array.isArray(obj.grants) &&
      obj.grants.includes('merge')
    ) {
      return true;
    }
  }
  return false;
}

// --- TEST AT CREATION (Spec-AC-07) ------------------------------------------

function testAtCreationBlock(harness, os, baseName) {
  let fireCommand;
  if (harness === 'claude') {
    fireCommand = 'use the schedule skill\'s manual "run now" action on the newly installed trigger';
  } else if (os === 'windows') {
    fireCommand = `Start-ScheduledTask -TaskName "${baseName}" (or invoke ${baseName}.ps1 directly)`;
  } else {
    fireCommand = `bash ${baseName}.sh`;
  }
  return [
    '## TEST AT CREATION',
    `Fire immediately after installing: ${fireCommand}`,
    'Verify:',
    '- a digest was produced',
    '- the run did not crash',
    '- any degraded sections are named in the digest',
  ].join('\n');
}

// --- per-harness payload assembly (Spec-AC-03) ------------------------------

function baseNameFor(routine, harness) {
  return `aai-${routine.toLowerCase()}-${harness}`;
}

function buildClaudePayload({ routine, repo, schedule, model, tz, mergeAllowed, prompt }) {
  return {
    name: `aai-${routine.toLowerCase()}`,
    cron: schedule,
    timezone: tz,
    model,
    repo,
    merge_enabled: mergeAllowed,
    prompt,
  };
}

function agentCliInvocation(harness, promptFileName) {
  if (harness === 'codex') return `codex --prompt-file "${promptFileName}"`;
  if (harness === 'gemini') return `gemini --prompt-file "${promptFileName}"`;
  return `<agent-cli> --prompt-file "${promptFileName}"  # generic: substitute your CLI's headless invocation`;
}

// PowerShell single-quoted string literals treat every character literally
// except '' (a doubled single quote, representing one literal quote) — no
// backslash or double-quote escaping is needed inside them. Building the
// nested `-Command "..."` value this way (instead of a double-quoted PS
// string, which needs backtick escapes for embedded quotes) keeps the
// windows -Argument literal correct regardless of what agentCliInvocation()
// embeds.
function psSingleQuoteLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function buildLocalSchedulerText({ routine, harness, os, repo, schedule, prompt }) {
  const baseName = baseNameFor(routine, harness);
  const shName = `${baseName}.sh`;
  const ps1Name = `${baseName}.ps1`;
  const promptFileName = `${baseName}.prompt.md`;
  const cliInvocation = agentCliInvocation(harness, promptFileName);
  const lines = [];
  lines.push(`Routine: ${routine} (${repo}) — harness=${harness} os=${os}`);
  lines.push('');
  if (os === 'windows') {
    // Windows Task Scheduler runs `pwsh -Command "<cliInvocation>"` as a
    // literal child-process command line, so the -Argument VALUE must carry
    // that nested double-quoted string with its inner quotes backslash-
    // escaped (standard Windows argument-quoting). psSingleQuoteLiteral()
    // wraps that value in a PowerShell single-quoted literal so nothing in
    // it needs PS-level escaping. Backtick (`) is PowerShell's line
    // continuation character — backslash is not, and using it here (as the
    // previous emission did) splits each statement in two and drops
    // -Argument/-Description entirely (Spec-AC-03 regression, see TEST-009).
    const argumentValue = `-Command "${cliInvocation.replace(/"/g, '\\"')}"`;
    lines.push('PowerShell scheduled task (Register-ScheduledTask):');
    lines.push('$Action = New-ScheduledTaskAction -Execute "pwsh" `');
    lines.push(`  -Argument ${psSingleQuoteLiteral(argumentValue)}`);
    lines.push(`$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)  # cron: ${schedule} (adjust to match)`);
    lines.push(`Register-ScheduledTask -TaskName "${baseName}" -Action $Action -Trigger $Trigger \``);
    lines.push(`  -Description "AAI routine ${routine} (${repo})"`);
  } else {
    lines.push('Crontab line:');
    lines.push(`${schedule} /usr/bin/env bash "$(pwd)/${shName}" >> "$(pwd)/${baseName}.log" 2>&1`);
    lines.push('');
    lines.push(`Runner (${shName}):`);
    lines.push('#!/usr/bin/env bash');
    lines.push('set -euo pipefail');
    lines.push(`cd "$(dirname "$0")"`);
    lines.push(cliInvocation);
  }
  lines.push('');
  lines.push(`Twins: ${shName} / ${ps1Name}`);
  lines.push('');
  lines.push(`Prompt file (${promptFileName}):`);
  lines.push('-----8<-----');
  lines.push(prompt);
  lines.push('-----8<-----');
  return lines.join('\n');
}

// --- main --------------------------------------------------------------------

function run(args) {
  const decisionsPath = args.decisions || defaultDecisionsPath();
  let mergeAllowed = false;
  let loudLine = null;
  if (args.merge) {
    mergeAllowed = checkAuthorization(decisionsPath, args.ref);
    if (!mergeAllowed) {
      loudLine = `MERGE DISABLED — no routine_authorization record for ref=${args.ref} in ${decisionsPath}`;
    }
  }

  const templateRaw = loadTemplate(args.routine);
  const prompt = renderTemplate(templateRaw, { repo: args.repo, schedule: args.schedule, model: args.model }, mergeAllowed);
  const baseName = baseNameFor(args.routine, args.harness);
  const footer = testAtCreationBlock(args.harness, args.os, baseName);

  if (loudLine) process.stderr.write(`${loudLine}\n`);

  const stdoutLines = [];
  if (args.harness === 'claude') {
    const payload = buildClaudePayload({
      routine: args.routine,
      repo: args.repo,
      schedule: args.schedule,
      model: args.model,
      tz: args.tz,
      mergeAllowed,
      prompt,
    });
    stdoutLines.push(JSON.stringify(payload));
    stdoutLines.push(
      "Handoff: install via Claude's schedule skill (routines), passing the JSON object above as the trigger definition.",
    );
  } else {
    stdoutLines.push(
      buildLocalSchedulerText({
        routine: args.routine,
        harness: args.harness,
        os: args.os,
        repo: args.repo,
        schedule: args.schedule,
        prompt,
      }),
    );
  }
  stdoutLines.push('');
  stdoutLines.push(footer);
  process.stdout.write(stdoutLines.join('\n') + '\n');
  return 0;
}

function main() {
  const args = parseArgs(process.argv);
  process.exit(run(args));
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === __filename;
if (isMain) main();

export {
  PROJECT_ROOT,
  loadTemplate,
  stripPlaceholdersBlock,
  applyMergeGate,
  substitute,
  renderTemplate,
  checkAuthorization,
  defaultDecisionsPath,
  testAtCreationBlock,
  baseNameFor,
  buildClaudePayload,
  buildLocalSchedulerText,
  run,
};
