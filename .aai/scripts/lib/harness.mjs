// harness.mjs — detectHarness(env): which agent-CLI harness is running the
// current process (harness-universal-routing,
// SPEC-0177-spec-harness-universal-routing D3).
//
// PURE function of the inherited environment only: zero filesystem I/O,
// never inferred from a model name (aai-doctor.mjs CAT-16's standing rule).
// Ordered ladder, first match wins:
//   1. AAI_HARNESS set and non-empty -> that value if it is in the closed
//      set below, else "unknown" (an out-of-set value is a typo, not a new
//      harness -- degrade rather than invent a sixth value).
//   2. CLAUDECODE or CLAUDE_CODE_ENTRYPOINT non-empty -> "claude"
//   3. CODEX_HOME or CODEX_SANDBOX non-empty -> "codex"
//   4. CURSOR_TRACE_ID or CURSOR_AGENT non-empty -> "cursor"
//   5. GEMINI_HOME non-empty -> "gemini"
//   6. otherwise -> "unknown"
//
// Deliberately EXCLUDED from every probe (measured, not assumed — D3):
//   - GEMINI_CLI_IDE_* (measured present INSIDE a Claude Code session: an
//     IDE-companion leak, not evidence of which harness is running)
//   - CLAUDE_CONFIG_DIR (a path preference; people export it who are not
//     running Claude Code)
//   - any filesystem probe (.claude/.codex/.gemini/.cursor/.agents are
//     vendored mirrors present in every AAI project regardless of what is
//     running; ~/.codex/sessions and siblings prove a harness was once
//     installed, never that it is running now)
//   - any model name
export const HARNESS_VALUES = Object.freeze(['claude', 'codex', 'gemini', 'cursor', 'unknown']);

function isSet(v) {
  return typeof v === 'string' && v !== '';
}

export function detectHarness(env) {
  const e = env || {};
  if (isSet(e.AAI_HARNESS)) {
    return HARNESS_VALUES.includes(e.AAI_HARNESS) ? e.AAI_HARNESS : 'unknown';
  }
  if (isSet(e.CLAUDECODE) || isSet(e.CLAUDE_CODE_ENTRYPOINT)) return 'claude';
  if (isSet(e.CODEX_HOME) || isSet(e.CODEX_SANDBOX)) return 'codex';
  if (isSet(e.CURSOR_TRACE_ID) || isSet(e.CURSOR_AGENT)) return 'cursor';
  if (isSet(e.GEMINI_HOME)) return 'gemini';
  return 'unknown';
}
