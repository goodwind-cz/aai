// aai-redact.mjs — hard, fail-closed redactor for RFC-0013 free-text fields.
//
// RFC-0013 D3/D4: redaction is deny-by-default and FAIL-CLOSED. A fixed detector
// set scans a candidate free-text string; if ANY detector fires (or the string
// is over the length cap), the caller must DROP the field — this module never
// returns a "best-effort redacted" string to persist in the capture pass. It is
// a PURE module (no I/O, no network, node stdlib only) so both the capture pass
// (aai-friction.mjs) and the later transmit pass can single-source it.
//
// Contract:
//   redactSummary(str, opts?) -> { ok: true,  value: <the safe string> }
//                             |  { ok: false, reason: <detector class> }
// `ok:false` means: do NOT persist this field (drop it). Structured/enum/bool
// fields must NOT be passed here — they cannot carry free content and bypass the
// redactor by construction (only free-text `summary` is ever redacted).

// Max length of a redactable summary (RFC-0013 D2: short, <= 200 chars).
export const MAX_SUMMARY_LEN = 200;

// Deny-by-default detectors. Order matters only for the reported reason; a single
// match is enough to fail closed. Each entry is [class, RegExp].
// Because `summary` is opt-in, off by default, and the contract is fail-closed
// DROP-on-uncertainty (a dropped summary just costs a human title, the record
// still persists), these detectors err AGGRESSIVELY toward dropping. False
// positives are cheap; a leaked secret/identity token is not.
const DETECTORS = [
  // Secret shapes -----------------------------------------------------------
  ['secret_pem', /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/],
  ['secret_aws', /\bAKIA[0-9A-Z]{16}\b/],
  // Provider token prefixes, hyphen OR underscore separated (Stripe sk_live_/
  // rk_live_/pk_live_, OpenAI sk-, GitHub ghp_/gho_/github_pat_, Slack xox*,
  // Google AIza, Twilio AC/SK). The prefix + >=10 tail chars.
  ['secret_token', /\b(?:xox[baprs]-|ghp_|gho_|github_pat_|sk[-_](?:live|test|proj)?[-_]?|rk[-_]live[-_]|pk[-_]live[-_]|AIza)[A-Za-z0-9_\-]{10,}/],
  // Twilio SID/key shape specifically: AC/SK + 30+ hex. Kept separate from the
  // prefix list above so it does not false-drop AAI skill names (SKILL_*) or
  // ordinary AC-/SK-initial words, which are not 30-hex runs.
  ['twilio_sid', /\b(?:AC|SK)[0-9a-fA-F]{30,}\b/],
  // A generic long secret/id run: hex >=32 (MD5/SHA/client_secret), base64 with
  // symbols >=32, OR any >=20-char alphanumeric/underscore/hyphen token THAT
  // CONTAINS A DIGIT (secret/id-shaped) — the digit requirement avoids dropping
  // long all-letter hyphenated slugs like `spec-friction-shadow-capture-wiring`.
  ['secret_highentropy', /\b[A-Fa-f0-9]{32,}\b|[A-Za-z0-9+/]{32,}={0,2}|\b(?=[A-Za-z0-9_\-]*\d)[A-Za-z0-9][A-Za-z0-9_\-]{19,}\b/],
  // Identity / location -----------------------------------------------------
  ['url', /\b[a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^\s]+/],
  ['email', /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/],
  ['git_remote', /\bgit@[^\s:]+:[^\s]+/],
  // Absolute POSIX path (leading /) OR any multi-segment path (>=2 slashes),
  // which catches relative paths like `home/ales/.ssh/id_rsa` that have no
  // leading slash. Dotfiles/traversal segments are inside either shape.
  ['abs_path_posix', /(?:^|\s)\/(?:[^\s/]+\/)*[^\s/]+/],
  ['path_multi', /(?:[^\s/]+\/){2,}[^\s/]+/],
  ['abs_path_windows', /\b[A-Za-z]:\\[^\s]+/],
  ['ipv4', /(?:\d{1,3}\.){3}\d{1,3}/],
  // IPv6 including the `::` zero-compression form humans actually write
  // (`::1`, `fe80::1`, `2001:db8::1`): two-or-more colon-separated hextet slots
  // where each slot may be empty (that is what `::` is).
  ['ipv6', /(?:[0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{0,4}/],
  // FQDN with a known TLD. The list is broadened (PR review) to common gTLDs and
  // ccTLDs beyond the original handful, while deliberately EXCLUDING code file
  // extensions (mjs/js/ts/sh/py/md/yaml/yml/json/jsonl/log/txt) so a summary
  // naming a script (`close-work-item.mjs`) is not a false positive. A bare
  // dotless hostname remains accepted residual (indistinguishable from a word).
  ['fqdn', /\b(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+(?:com|org|net|io|dev|co|edu|gov|internal|local|cz|ai|ru|uk|de|fr|eu|us|info|biz|app|cloud|xyz|tech|online|site|me|tv|gov\.uk|co\.uk)\b/],
  // Multi-label FQDN (>=3 labels / >=2 dots) with an alpha final label, e.g.
  // `api.customer.tech`, `build.internal.corp` — caught regardless of TLD so an
  // unlisted-TLD host does not leak (PR review P1). A single-dot `word.word`
  // (file `close-work-item.mjs`, or `build.company`) is deliberately NOT matched
  // here — it is indistinguishable from a filename/extension; the TLD list above
  // covers the common single-dot domains, and the rest is accepted residual.
  ['fqdn_multi', /\b[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?){1,}\.[a-z]{2,}\b/i],
  ['user_handle', /(?:^|\s)@[A-Za-z0-9_\-]{2,}\b/],
  ['user_pass', /\b[A-Za-z0-9._\-]+:[^\s@/]+@/],
  // Long digit runs (ids, phone numbers, account numbers). No \b anchor so a
  // run glued to surrounding letters (e.g. "server123456789x") is still caught.
  ['long_digits', /\d{9,}/],
  // Separator-broken digit groups totalling >=9 digits — phone / SSN / credit
  // card shapes (`4111-1111-1111-1111`, `123-45-6789`, `(555) 123-4567`) that a
  // contiguous run misses because `-`, space, `.`, `()` sit between the groups.
  ['pii_digit_groups', /(?:\d[\s.()\-]{0,3}){9,}/],
  // A mixed-case-AND-digit alphanumeric run of >=10 chars — the shape of API
  // keys/ids/tokens that are all in the safe charset (so the charset gate below
  // lets them through) yet too short for the >=20 generic-entropy detector.
  // Ordinary words never mix upper+lower+digits in a 10+ run.
  ['token_mixed', /\b(?=[A-Za-z0-9]*[a-z])(?=[A-Za-z0-9]*[A-Z])(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{10,}\b/],
];

// ALLOW-LIST charset gate (the primary defense — deny-list detection of secrets
// in free text is fundamentally incomplete). A summary is persisted ONLY if it
// consists solely of a conservative ASCII set: letters, digits, space, and basic
// sentence punctuation. This categorically rejects — before any detector runs —
// every non-ASCII character (zero-width spaces, fullwidth digits, homoglyphs),
// path separators (`/` `\`), `@` (emails/handles/git remotes), and `+ = ~`.
// `_` is PERMITTED (real AAI filenames use it, e.g. AAI_PIN.md,
// FRICTION_PROTOCOL.md) — underscore-prefixed secrets like Stripe `sk_live_` are
// caught by the deny-list `secret_token`/entropy detectors instead. `: . -` are
// likewise permitted for natural prose (times, script names) with the detectors
// still firing on `::1`, `AKIA…`, hyphen-tokens, digit/PII runs, etc.
const SAFE_SUMMARY_CHARS = /^[A-Za-z0-9 ,.;:'"()!?_\-]+$/;

// redactSummary: certify a candidate free-text summary as safe-to-persist, or
// fail closed. Returns {ok:true,value} ONLY when it is non-empty, within the
// length cap, and no detector fires. Any other case -> {ok:false,reason}.
export function redactSummary(input, opts = {}) {
  const maxLen = Number.isInteger(opts.maxLen) ? opts.maxLen : MAX_SUMMARY_LEN;
  if (typeof input !== 'string') return { ok: false, reason: 'not_a_string' };
  const value = input.trim();
  if (value.length === 0) return { ok: false, reason: 'empty' };
  if (value.length > maxLen) return { ok: false, reason: 'over_length' };
  // Control chars (newlines/tabs) are not allowed in a one-line summary.
  if (/[\x00-\x1f\x7f]/.test(value)) return { ok: false, reason: 'control_char' };
  // Primary allow-list gate: only the conservative ASCII prose charset. This
  // closes entire bypass classes (unicode/zero-width/fullwidth, paths, emails,
  // underscore tokens) that a deny-list can never fully enumerate.
  if (!SAFE_SUMMARY_CHARS.test(value)) return { ok: false, reason: 'unsafe_char' };
  // Deny-list detectors, as defense-in-depth for threats inside the safe charset.
  for (const [cls, re] of DETECTORS) {
    if (re.test(value)) return { ok: false, reason: cls };
  }
  return { ok: true, value };
}

// The detector classes, exported so tests can enumerate coverage.
export const DETECTOR_CLASSES = DETECTORS.map(([cls]) => cls);
