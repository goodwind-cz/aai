#!/usr/bin/env node
// tests/skills/lib/learned-guard-lints.mjs
//
// Spec-AC-15 (spec-test-framework-sweep) / D10: six lessons in
// docs/knowledge/LEARNED.md carry a `[guard -> fu-learned-*]` marker, which by
// that file's own contract means "the enforcement belongs in the layer and
// this id is the follow-up that will build it". This is that layer: six
// mechanical scans, invoked from tests/skills/test-aai-hygiene-pack.sh
// (test_125 / test_126), never shipped as a standalone CLI a guard could be
// bypassed by not running.
//
// Every rule is scoped to be exactly zero on the live corpus TODAY (measured
// 2026-09-13) and to bite on a fixture reproducing the historical shape named
// in the LEARNED entry it enforces. A rule broader than that measurement
// would either misreport a real occurrence as clean (false negative) or
// redden this repository's own tree (which the live-gate arm, TEST-428,
// would catch immediately) — the comments on each rule below record the
// live near-misses that shaped its exact boundary.
//
// Usage:
//   node learned-guard-lints.mjs <rule> <root> [<root> ...]
//   rule one of: local-crossref | cd-underived | immutable-pin |
//                deny-default-mock | absence-no-control | external-runner
//
// Output: one `<relpath>:<line>: <message>` per finding, then a final
// `TOTAL: <n>` line. Exit code is always 0 — the CALLER (the hygiene-pack
// test arms) decides what a nonzero TOTAL means; a scanner that fails closed
// on its own plumbing (unreadable root, etc.) exits 1 instead, distinctly.

import fs from "node:fs";
import path from "node:path";

function walk(root, exts) {
  const out = [];
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        stack.push(p);
      } else if (e.isFile() && exts.some((x) => e.name.endsWith(x))) {
        out.push(p);
      }
    }
  }
  return out.sort();
}

function relOf(root, p) {
  return path.relative(root, p);
}

function readLines(p) {
  return fs.readFileSync(p, "utf8").split("\n");
}

// ---------------------------------------------------------------------------
// RULE: local-crossref (fu-learned-bash32-local-crossref)
//
// Bash 3.2 evaluates every word of a single `local` statement's assignments
// BEFORE any of them takes effect (`local a=1 b=$a` leaves b empty — $a is
// not yet a local at the time $a is expanded). A `local` line naming two or
// more NAME=VALUE assignments where a later value references an EARLIER
// name declared on the SAME statement is that defect, verbatim.
//
// Continuation lines (trailing `\`) are joined before parsing, matching how
// bash itself reads the statement.
const LOCAL_START = /^\s*local\s+(?:-[a-zA-Z]+\s+)*(.*)$/;
const ASSIGN_RE = /([A-Za-z_][A-Za-z0-9_]*)=((?:"(?:[^"\\]|\\.)*")|(?:'[^']*')|(?:\S*))/g;

// `local n; n="$(...)"` is TWO statements on one physical line — the `local`
// statement ends at the first unquoted `;`. Without this cut, a later
// semicolon-separated reassignment (already a real local by then, so
// self-referencing it is fine) reads as a same-statement crossref and is a
// false positive (measured: test-aai-feedback-upsert.sh:872,
// test-aai-hygiene-pack.sh:1991/2233 before this cut was added).
function stripAfterSemicolon(text) {
  let inS = false;
  let inD = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inD) {
      if (c === "\\") { i++; continue; }
      if (c === '"') inD = false;
      continue;
    }
    if (inS) {
      if (c === "'") inS = false;
      continue;
    }
    if (c === '"') { inD = true; continue; }
    if (c === "'") { inS = true; continue; }
    if (c === ";") return text.slice(0, i);
  }
  return text;
}

function localCrossrefFindings(root, files) {
  const findings = [];
  for (const f of files) {
    const lines = readLines(f);
    for (let i = 0; i < lines.length; i++) {
      const m = LOCAL_START.exec(lines[i]);
      LOCAL_START.lastIndex = 0;
      if (!m) continue;
      let text = m[1];
      let startLine = i + 1;
      // Join backslash-continuation lines onto the same logical statement,
      // UNLESS the statement already terminated at an unquoted `;` on the
      // opening line (a continuation backslash would then belong to the
      // following, separate statement).
      let j = i;
      if (stripAfterSemicolon(text) === text) {
        while (/\\\s*$/.test(lines[j]) && j + 1 < lines.length) {
          j++;
          text += " " + lines[j].replace(/^\s*/, "");
        }
      }
      text = stripAfterSemicolon(text);
      const assigns = [];
      let am;
      ASSIGN_RE.lastIndex = 0;
      while ((am = ASSIGN_RE.exec(text))) {
        assigns.push({ name: am[1], value: am[2] });
      }
      if (assigns.length < 2) continue;
      for (let k = 1; k < assigns.length; k++) {
        for (let p = 0; p < k; p++) {
          const earlier = assigns[p].name;
          const ref = new RegExp("\\$\\{?" + earlier.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b");
          if (ref.test(assigns[k].value)) {
            findings.push({
              file: relOf(root, f),
              line: startLine,
              msg: `local statement assigns '${assigns[k].name}' from '${earlier}' declared earlier in the SAME local statement — bash 3.2 leaves '${assigns[k].name}' empty (split into two local lines)`,
              victim: assigns[k].name,
            });
          }
        }
      }
    }
  }
  return findings;
}

// ---------------------------------------------------------------------------
// RULE: cd-underived (fu-empty-path-cd-stays-in-shipping-repo)
//
// The registry finding is the SAME chain as local-crossref, one step further:
// the variable a crossref leaves empty is then handed to `cd`, and `cd ""`
// silently stays in the shipping repository instead of failing. Scoped to
// variables THIS file's own local-crossref scan (above) already proved are
// victims — a generic scan of every `cd "$var"` in the corpus (1264
// occurrences measured 2026-09-13, nearly all of them fine) cannot be zero on
// the live tree without becoming so narrow it stops meaning anything; tying
// it to a proven-empty variable is the precise shape the LEARNED entry
// describes and is zero today because local-crossref is zero today.
function cdUnderivedFindings(root, files) {
  const findings = [];
  for (const f of files) {
    const victims = new Set(localCrossrefFindings(root, [f]).map((x) => x.victim));
    if (victims.size === 0) continue;
    const lines = readLines(f);
    for (let i = 0; i < lines.length; i++) {
      for (const v of victims) {
        const re = new RegExp('cd\\s+"?\\$\\{?' + v.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\}?\"?(\\s|$)");
        if (re.test(lines[i])) {
          findings.push({
            file: relOf(root, f),
            line: i + 1,
            msg: `cd "$${v}" — '${v}' is a local-crossref victim in this same file and can be empty; cd "" silently stays in the caller's cwd`,
          });
        }
      }
    }
  }
  return findings;
}

// ---------------------------------------------------------------------------
// RULE: immutable-pin (fu-learned-immutable-pin-lint)
//
// A comment claiming a pin is immutable, followed within a short window by an
// assignment that resolves THAT pin through a moving ref (bare `origin/main`
// or bare `HEAD`) rather than a fixed SHA. Scoped to the assignment
// IMMEDIATELY following the claim (within 5 lines, skipping blank/comment
// lines) rather than any origin/main mention nearby: tests/skills carries
// live "immutable" comments sitting a few lines above an UNRELATED
// origin/main resolution for a different variable's own (legitimately
// moving) base-ref arm (test-aai-spec-amend.sh:66-78, measured) — a
// proximity-only scan would misreport that file today.
const IMMUTABLE_COMMENT_RE = /^\s*#.*\b(immutable|cannot rot)\b/i;
const MOVING_ASSIGN_RE = /^\s*(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*=\s*"?(?:origin\/main|HEAD)"?\s*$/;
const MOVING_VALUE_RE = /^\s*(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*=.*\borigin\/main\b/;

function immutablePinFindings(root, files) {
  const findings = [];
  for (const f of files) {
    const lines = readLines(f);
    for (let i = 0; i < lines.length; i++) {
      if (!IMMUTABLE_COMMENT_RE.test(lines[i])) continue;
      // Walk forward past the rest of this comment block, then look at the
      // next up-to-3 non-blank, non-comment (code) lines.
      let j = i + 1;
      while (j < lines.length && /^\s*(#.*)?$/.test(lines[j])) j++;
      let seen = 0;
      while (j < lines.length && seen < 3) {
        const line = lines[j];
        if (/^\s*#/.test(line) || /^\s*$/.test(line)) {
          j++;
          continue;
        }
        seen++;
        if (MOVING_ASSIGN_RE.test(line) || MOVING_VALUE_RE.test(line)) {
          findings.push({
            file: relOf(root, f),
            line: j + 1,
            msg: `pin described as immutable at line ${i + 1} resolves through a moving ref here — pin the SHA the comment describes`,
          });
        }
        j++;
      }
    }
  }
  return findings;
}

// ---------------------------------------------------------------------------
// RULE: deny-default-mock (fu-learned-deny-by-default-mocks)
//
// A `case` statement's `*)` (default) arm whose body exits 0 (accepts
// unrecognised argv) instead of refusing. Scoped to case-arm bodies that
// literally contain `exit 0` with no rejection signal anywhere in the same
// arm (reject/log_fail/exit 1/exit 2/stderr/"unknown"/"unexpected"/
// "unpinned") — measured zero over tests/skills/*.sh today; the shipped good
// example (test-aai-feedback-upsert.sh's gh stub) instead falls OFF the case
// statement entirely to a `gh_reject` call after `esac`, which is why it does
// not trip this rule.
function denyDefaultMockFindings(root, files) {
  const findings = [];
  const rejectRe = /reject|log_fail|exit 1\b|exit 2\b|>&2|unknown|unexpected|unpinned/i;
  for (const f of files) {
    const lines = readLines(f);
    let armStart = -1;
    let body = "";
    for (let i = 0; i < lines.length; i++) {
      if (armStart === -1 && /^\s*\*\)/.test(lines[i])) {
        armStart = i;
        body = "";
      }
      if (armStart !== -1) {
        body += lines[i] + "\n";
        // The `*)` line itself may already close the arm (`*) exit 0 ;;`, the
        // common single-line stub shape) — checked on every line INCLUDING
        // the opening one, not just subsequent ones.
        if (/;;/.test(lines[i])) {
          if (/exit\s+0\b/.test(body) && !rejectRe.test(body)) {
            findings.push({
              file: relOf(root, f),
              line: armStart + 1,
              msg: `case default arm ('*)') exits 0 on unrecognised argv instead of refusing — pin the expected shape and deny everything else`,
            });
          }
          armStart = -1;
          body = "";
        }
      }
    }
  }
  return findings;
}

// ---------------------------------------------------------------------------
// RULE: absence-no-control (fu-learned-positive-control-for-absence)
//
// An assertion that a call-recording variable (named `*CALLS*`, the
// established idiom in this corpus — e.g. GH_CALLS) does NOT contain
// something, with no accompanying MUST-match assertion against the same
// variable nearby proving the code under test actually ran. Window-scoped
// (25 lines either side) rather than function-scoped: brace-accurate
// function boundaries are not reliably parseable with a line scanner over
// this corpus's mix of case/if/array shapes, and a same-variable, same-arm
// positive control is never more than a few lines from the absence check it
// backs in the files that carry this idiom today (measured).
const ABSENCE_RE = /\$\{?([A-Za-z_]*CALLS)\}?["']?.*&&\s*log_fail/;

// A positive control does not have to name the CALLS variable literally — the
// established idiom in this corpus is an ACCESSOR function (e.g. `creates()`,
// defined to `grep -c ... "$GH_CALLS"`) asserted with `[ "$(accessor)" = ...
// ] || log_fail`. Collect every function in the file whose body mentions the
// variable, one-line (`name() { ...; }`) and multi-line (`name() {` ... `}`)
// definitions both.
function findAccessorFunctions(lines, varName) {
  const names = new Set();
  const oneLine = /^\s*([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{.*\}\s*$/;
  const multiStart = /^\s*([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{\s*$/;
  const varRe = new RegExp("\\$\\{?" + varName + "\\b");
  for (let i = 0; i < lines.length; i++) {
    let m = oneLine.exec(lines[i]);
    if (m) {
      if (varRe.test(lines[i])) names.add(m[1]);
      continue;
    }
    m = multiStart.exec(lines[i]);
    if (m) {
      let body = "";
      let j = i + 1;
      while (j < lines.length && !/^\s*\}\s*$/.test(lines[j])) {
        body += lines[j] + "\n";
        j++;
      }
      if (varRe.test(body)) names.add(m[1]);
    }
  }
  return names;
}

function absenceNoControlFindings(root, files) {
  const findings = [];
  const WINDOW = 25;
  for (const f of files) {
    const lines = readLines(f);
    for (let i = 0; i < lines.length; i++) {
      const m = ABSENCE_RE.exec(lines[i]);
      ABSENCE_RE.lastIndex = 0;
      if (!m) continue;
      const varName = m[1];
      const accessors = findAccessorFunctions(lines, varName);
      const patterns = [new RegExp("\\$\\{?" + varName + "\\}?.*\\|\\|\\s*log_fail")];
      for (const acc of accessors) {
        patterns.push(new RegExp("\\$\\(\\s*" + acc + "\\s*\\).*(\\|\\||&&)\\s*log_fail"));
      }
      let hasControl = false;
      const lo = Math.max(0, i - WINDOW);
      const hi = Math.min(lines.length, i + WINDOW);
      for (let k = lo; k < hi; k++) {
        if (k === i) continue;
        if (patterns.some((re) => re.test(lines[k]))) {
          hasControl = true;
          break;
        }
      }
      if (!hasControl) {
        findings.push({
          file: relOf(root, f),
          line: i + 1,
          msg: `absence assertion against $${varName} has no nearby MUST-match ("|| log_fail") assertion against the same call log (directly or via an accessor function) — this arm cannot prove it ran`,
        });
      }
    }
  }
  return findings;
}

// ---------------------------------------------------------------------------
// RULE: external-runner (fu-learned-external-runner-routing)
//
// A prompt instructing a direct runner invocation (vitest/tsc/npm run dev/
// npm start) as an actual command line, rather than routed through the AAI
// test wrapper. Scoped to true command-shaped lines (start of line, no
// leading list/backtick prose) — the live prompt corpus mentions these
// runner names only in backtick-quoted prose ("never invoke `vitest`/`tsc`/
// dev-servers directly"), which this pattern does not match (measured zero
// over .aai/*.prompt.md today).
const RUNNER_CMD_RE = /^\s*(?:npx\s+)?(?:vitest\b|tsc\b)|^\s*npm\s+(?:run\s+dev\b|start\b)/;
function externalRunnerFindings(root, files) {
  const findings = [];
  for (const f of files) {
    const lines = readLines(f);
    for (let i = 0; i < lines.length; i++) {
      if (RUNNER_CMD_RE.test(lines[i]) && !/aai-run-tests\.sh/.test(lines[i])) {
        findings.push({
          file: relOf(root, f),
          line: i + 1,
          msg: `runner invoked directly as a command line — route through .aai/scripts/aai-run-tests.sh so a hung process cannot outlive the step that spawned it`,
        });
      }
    }
  }
  return findings;
}

// ---------------------------------------------------------------------------
// RULE: session-marker (spec-friction-channel-sweep Spec-AC-10,
// fu-triage-undated-learned-log)
//
// docs/knowledge/LEARNED.md's own header says every bullet under a
// `## Session …` heading carries exactly one `[local]` or `[guard → <id>]`
// marker, placed right after the leading `- `. This rule is that check: a
// top-level bullet (a line starting with `- ` at column 0, inside a section
// whose most recent `## ` heading starts with "Session") whose text — right
// after the `- ` — does NOT open with a literal `[local]` or a
// `[guard <arrow> <id>]` token is flagged.
//
// STRICT BY DESIGN: the marker check is anchored on the two literal marker
// shapes, never "any bracketed token" — a bullet that opens with an
// unrelated bracket (a stray `[2026-09-25]` date with no real marker
// following it, say) must still be flagged. A rule widened to accept any
// leading `[...]` would silently accept exactly that decoy and misreport a
// genuinely unmarked bullet as compliant.
const SESSION_HEADING_RE = /^##\s+Session\b/;
const ANY_HEADING_RE = /^##\s+/;
const BULLET_START_RE = /^-\s+(.*)$/;
// A Session bullet is either undated (marker is the FIRST bracket, the shape
// this triage introduced) or already follows the file's own dated-entry
// convention (an optional leading `[YYYY-MM-DD] ` date bracket, THEN the
// marker) — several `## Session …` blocks (e.g. 2026-08-24 onward) already
// carry dated, marked entries predating this rule.
const SESSION_MARKER_RE = /^(?:\[\d{4}-\d{2}-\d{2}\]\s+)?(?:\[local\]|\[guard\s*(?:->|→)\s*[^\]]+\])/;
function sessionMarkerFindings(root, files) {
  const findings = [];
  for (const f of files) {
    const lines = readLines(f);
    let inSession = false;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (ANY_HEADING_RE.test(line)) {
        inSession = SESSION_HEADING_RE.test(line);
        continue;
      }
      if (!inSession) continue;
      const bm = BULLET_START_RE.exec(line);
      if (!bm) continue;
      if (!SESSION_MARKER_RE.test(bm[1])) {
        findings.push({
          file: relOf(root, f),
          line: i + 1,
          msg: `Session bullet carries no [local] or [guard → <id>] marker right after "- "`,
        });
      }
    }
  }
  return findings;
}

const RULES = {
  "local-crossref": { fn: localCrossrefFindings, exts: [".sh"] },
  "cd-underived": { fn: cdUnderivedFindings, exts: [".sh"] },
  "immutable-pin": { fn: immutablePinFindings, exts: [".sh"] },
  "deny-default-mock": { fn: denyDefaultMockFindings, exts: [".sh"] },
  "absence-no-control": { fn: absenceNoControlFindings, exts: [".sh"] },
  "external-runner": { fn: externalRunnerFindings, exts: [".prompt.md"] },
  "session-marker": { fn: sessionMarkerFindings, exts: [".md"] },
};

function main() {
  const [, , rule, ...roots] = process.argv;
  if (!rule || !RULES[rule] || roots.length === 0) {
    console.error(
      `usage: learned-guard-lints.mjs <${Object.keys(RULES).join("|")}> <root> [<root> ...]`
    );
    process.exit(1);
  }
  const { fn, exts } = RULES[rule];
  let total = 0;
  for (const root of roots) {
    if (!fs.existsSync(root)) {
      console.error(`root does not exist: ${root}`);
      process.exit(1);
    }
    const files = walk(root, exts);
    const findings = fn(root, files);
    for (const finding of findings) {
      console.log(`${finding.file}:${finding.line}: ${finding.msg}`);
      total++;
    }
  }
  console.log(`TOTAL: ${total}`);
  process.exit(0);
}

main();
