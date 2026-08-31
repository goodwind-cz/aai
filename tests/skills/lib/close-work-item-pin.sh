# Shared close-work-item.mjs content-hash allowlist (role-verification-guards
# unification of two independently frozen byte-unchanged pins on the SAME
# file, for TWO DIFFERENT reasons):
#   - CHANGE-0142/SPEC-0129 D5 (tests/skills/test-aai-follow-ups.sh TEST-008):
#     follow-ups.mjs must never gain a `--resolves` wire into the close
#     transaction (coupling its rollback to a second append-only ledger).
#   - CHANGE-0143/SPEC-0131 D5 (tests/skills/test-aai-doc-numbering.sh
#     TEST-029): the close-regenerate-order scope proved it left the file's
#     exit contract (0/1/2/3/4/5), its snapshot/rollback transaction (D6 —
#     doc bytes + EVENTS.jsonl byte-length truncate) and its four
#     best-effort regen calls untouched.
#
# A pure "diff against base must be empty" pin cannot survive a THIRD spec
# legitimately touching the same file for an unrelated reason —
# role-verification-guards' G1 post-merge-close advisory is exactly that
# third reason, and it broke BOTH pins independently in two different ways
# (a keyword-scan escape hatch here, a hard byte-diff failure there). Single
# shared mechanism instead, sourced by BOTH owning suites so their
# protection can never again silently disagree: the file's sha256 content
# hash must equal ONE of the entries in CLOSE_WORK_ITEM_ALLOWED_HASHES below.
#
# Growing the list is the INTENDED path for a legitimate future edit
# (mirrors TEST-029's own header comment: "that friction is the point") —
# each entry is a human-authored, one-line, reviewed re-affirmation that
# BOTH frozen invariants above still hold for the new bytes. This is
# strictly what a byte-diff-empty pin enforced (ANY change requires a new,
# deliberate entry — no keyword can be phrased around it), while still
# tolerating that the file legitimately evolves: closer to the old pin's
# "force a human to look" property than a substring scan can be.
#
# This file is a PURE library: no `set -u`, no `cd`, no test execution. It
# is only ever sourced, never run directly (mirrors prompt-diet-ledger.sh's
# discipline). bash-3.2 / Windows-Git-Bash safe: no declare -A, no mapfile.

CLOSE_WORK_ITEM_REL=".aai/scripts/close-work-item.mjs"

CLOSE_WORK_ITEM_ALLOWED_HASHES=(
  "e55e053fe1dbd4aa36b7b37cec96faa8b5160a3c59b2d413bd378c38a7e0299a baseline — SPEC-0131/CHANGE-0143 D5 freeze (exit contract + D6 transaction + regen tail untouched); SPEC-0129/CHANGE-0142 D5 unwired (no follow-ups coupling)"
  "ac38d15ad1bf4e5034b7590146a9d19ff35fc8d74374559b6128f380e656a7f1 role-verification-guards G1 — adds ONE report-only post-merge-close stderr advisory (resolveUpstreamDefaultRef + emitPostMergeCloseWarning, called once in main() before the pre-write phase). Both frozen invariants re-affirmed: exit contract (0/1/2/3/4/5) unchanged, the D6 snapshot/rollback transaction and its four best-effort regen calls untouched (SPEC-0131 D5); no --resolves flag, no follow-ups.mjs invocation, no decisions.jsonl reference added (SPEC-0129 D5)"
  "8bdff81f98789cb560cd6cc3eccfa39a0a93b85cf6491cbab96e531d2245b8a7 cli-exit-truncates-pipe-sweep (ISSUE-0049) — every process.exit(N) call replaced with exit(N) from the new .aai/scripts/lib/cli-pipe-guard.mjs, and the top-level try/main/catch replaced with runMain(main, {onError}); same numeric codes on every path (0/1/2/3/4/5), same top-level catch behaviour (exit 1 on internal error). Both frozen invariants re-affirmed by reading the full diff: exit contract unchanged, the D6 snapshot/rollback transaction and its four best-effort regen calls untouched (SPEC-0131 D5); no --resolves flag, no follow-ups.mjs invocation, no decisions.jsonl reference added (SPEC-0129 D5). Purpose: this CLI stops truncating piped output the same way 37 siblings do"
  "7e8757291b7b5e61d9aef3005f193361ff91f49575f3cb1ee4072a86ad696060 spec-close-leaves-state-stale (ride ref close-leaves-state-stale) — adds the post-close STATE reconcile (planStateReconcile/applyStateReconcile), running STRICTLY AFTER the existing try/catch and writing ONLY through the sanctioned state.mjs CLI (set-phase/set-focus), never a raw STATE byte write. This DELIBERATELY WIDENS the SPEC-0131/CHANGE-0143 D5 exit contract from 0/1/2/3/4/5 to include 6 — PARTIAL (state-reconcile), a NAMED PARTIAL where the close itself STOOD: docs already flipped, close events already emitted, self-verify already CLEAN before this exit is ever reached. The D6 snapshot/rollback transaction and its four best-effort regen calls are UNTOUCHED: the reconcile runs outside that rollback scope by construction, is never rolled back by it and never triggers it. SPEC-0129/CHANGE-0142 D5 stays satisfied: no --resolves flag, no follow-ups.mjs invocation, no decisions.jsonl reference added"
  "87579a09e9b9698294f76e4a6032e6b6b81a7790ac76091f2c73e745509a3355 close-ceremony-ordering (ride ref close-ceremony-ordering, fu-close-before-push-ordering / fu-close-requires-pr-before-it-exists) — the ordering paradox (the correct ceremony runs close BEFORE push, but a PR number does not exist until AFTER push+PR-open) is resolved by SPLITTING the transaction, never by a guess: (1) parseArgs now accepts the literal sentinel --pr TBD (case-insensitive on input, canonicalized to the literal TBD) as the ONLY non-integer value, alongside the unchanged integer path — the existing integer --pr N --commit sha grammar and its validation are byte-identical; (2) a NEW, wholly SEPARATE --stamp-pr N mode (mutually exclusive with --pr/--commit/--dry-run, dispatched from main() BEFORE any of the existing resolution/gate logic runs, in the new runStampPr() function) replaces an already-stamped TBD with the real PR number once it exists, via a new narrow snapshot/self-verify/rollback of its own (reusing selfVerify/rollback/regenerateIndex verbatim, never touching the status flip or the close event set); (3) a new report-only scanForStaleTbdPr()/emitStaleTbdWarning() pair prints a named stderr WARNING on EVERY future invocation for any OTHER closed doc still carrying an unstamped TBD (the must-not-go-unfilled guarantee — a stale placeholder is loud, not silently plausible like the old guessed-number incident). Both frozen invariants re-affirmed by reading the full diff: the ORIGINAL close transaction's exit contract (0/1/2/3/4/5) and every exit() call inside it are byte-unchanged (git diff shows zero deletions inside main()'s D6 write path); the new --stamp-pr mode returns only 0/1/2, a subset of the existing closed set, never a new number. The D6 snapshot/rollback transaction and its four best-effort regen calls (regenerateOverviewBestEffort/regenerateUserguideRollupBestEffort/regenerateDocsHubBestEffort/regenerateFactoryReportBestEffort) are untouched — confirmed present, unmodified, and still called in the same order at the same site. SPEC-0129/CHANGE-0142 D5 stays satisfied: no --resolves flag, no follow-ups.mjs invocation, no decisions.jsonl reference added"
)

# sha_cmd() -> the portable sha256 CLI invocation for this host (mirrors
# test-aai-deslop.sh's sha_cmd: shasum on macOS/BSD hosts, sha256sum on
# Linux/CI hosts lacking shasum).
sha_cmd() {
  if command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    echo "sha256sum"
  fi
}

# close_work_item_pin_check <project_root> -> prints one of:
#   "OK <hash>"            — the file's current content hash is allowlisted
#   "MISMATCH <hash>"       — the file changed and its new hash is NOT yet
#                             allowlisted (the pin's failure case)
#   "ABSENT"                — the file does not exist at all (fail-closed,
#                             never silently "pass")
close_work_item_pin_check() {
  local root="$1" f hash
  f="$root/$CLOSE_WORK_ITEM_REL"
  [[ -f "$f" ]] || { echo "ABSENT"; return; }
  hash="$($(sha_cmd) "$f" | awk '{print $1}')"
  local entry allowed_hash
  for entry in "${CLOSE_WORK_ITEM_ALLOWED_HASHES[@]}"; do
    allowed_hash="${entry%% *}"
    if [[ "$hash" == "$allowed_hash" ]]; then
      echo "OK $hash"
      return
    fi
  done
  echo "MISMATCH $hash"
}

# close_work_item_pin_assert <project_root> -> prints "OK <hash>" and returns
# 0 when close_work_item_pin_check's result is the positive OK status;
# otherwise prints a one-line failure reason on stdout and returns 1 —
# NEVER silently treats ABSENT, MISMATCH, or any other unrecognized status as
# success (role-verification-guards remediation, N-B).
#
# Hoisted here (rather than left as an if/elif chain copy-pasted into each
# caller) because the ORIGINAL per-caller copy WAS the guard, and a per-caller
# copy is a per-caller opportunity to silently lose it: round-3's validation
# proved that deleting the `elif [[ "$status" != "OK" ]]` branch from a real
# caller and grepping the caller's OWN source for the literal `!= "OK"` text
# (the N1-round static pin) still passes when a COMMENT mentioning that
# literal survives the deletion — a textual pin over a textual guard has
# nothing behavioural left to check once the two diverge. Hoisting the
# if/elif into ONE function both callers delegate to removes that gap
# entirely: there is now exactly one guard, in one place, and test_010 in
# tests/skills/test-aai-follow-ups.sh drives THIS function directly (by
# shadowing close_work_item_pin_check and calling close_work_item_pin_assert
# for real) instead of grepping for a string that could survive its own
# deletion.
close_work_item_pin_assert() {
  local root="$1" result status hash
  result="$(close_work_item_pin_check "$root")"
  status="${result%% *}"
  hash="${result#* }"
  if [[ "$status" == "ABSENT" ]]; then
    echo "$CLOSE_WORK_ITEM_REL not found"
    return 1
  elif [[ "$status" == "MISMATCH" ]]; then
    echo "close-work-item.mjs content hash $hash is not on the shared allowlist (D5) -- tests/skills/lib/close-work-item-pin.sh needs a new itemized entry re-affirming both frozen invariants, added in the same commit as the edit"
    return 1
  elif [[ "$status" != "OK" ]]; then
    echo "close_work_item_pin_check returned an unrecognized status '$status' (expected OK, ABSENT or MISMATCH) -- asserting the positive case rather than only denylisting the two known failures"
    return 1
  fi
  echo "$result"
  return 0
}
