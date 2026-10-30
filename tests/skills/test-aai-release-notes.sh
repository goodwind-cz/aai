#!/usr/bin/env bash
# Real Git fixtures for spec-release-one-command-no-findings TEST-001..003.
# bash 3.2 compatible. No network; only disposable repositories are mutated.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$ROOT/.aai/scripts/release-notes-gate.mjs"
# Selector entrypoints (spec-watch-ci-cancelled-runs-and-release-gate-docs):
# a first argument runs one node:test case and exits; no argument runs it all.
run_docs_case() {
  local id="$1"
  if node --test --test-name-pattern="$id" "$ROOT/tests/skills/lib/release-notes-docs.test.mjs"; then
    echo "PASS $id"
  else
    echo "FAIL $id" >&2
    return 1
  fi
}
test_2706() { run_docs_case TEST-2706; }
test_2707() { run_docs_case TEST-2707; }
test_2708() { run_docs_case TEST-2708; }
test_2709() { run_docs_case TEST-2709; }
test_2710() { run_docs_case TEST-2710; }
test_2935() { run_docs_case TEST-2935; }
if [ "$#" -gt 0 ]; then
  if ! declare -F "$1" >/dev/null; then
    echo "Unknown selector: $1" >&2
    exit 2
  fi
  "$1"
  exit $?
fi
SCRATCH_ROOT="${AAI_NOTES_SCRATCH_ROOT:-/tmp/aai-release-one-command-scratch/notes}"
case "$SCRATCH_ROOT" in /*) ;; *) echo 'scratch must be absolute' >&2; exit 1;; esac
mkdir -p "$SCRATCH_ROOT"
FIXTURE="$(mktemp -d "$SCRATCH_ROOT/repo.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git init -q -b main "$FIXTURE"
git -C "$FIXTURE" config user.name notes-fixture
git -C "$FIXTURE" config user.email notes-fixture@example.invalid
git -C "$FIXTURE" config core.hooksPath /dev/null
mkdir -p "$FIXTURE/.aai"
printf 'old\n' > "$FIXTURE/.aai/tool.txt"
printf '# Changelog\n\n## [unreleased]\n\n## [unreleased] — old note\n\n- Existing description.\n' > "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add -- .aai/tool.txt CHANGELOG.md
git -C "$FIXTURE" commit -qm initial
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
BODY="$FIXTURE/body.txt"
printf '## Summary\n' > "$BODY"
FAILURES=0
expect() {
  local id="$1" wanted="$2" label="$3"
  shift 3
  local rc=0 ok
  (case "$FIXTURE" in /*) cd "$FIXTURE";; *) exit 99;; esac; node "$GATE" "$@") > "$FIXTURE/out" 2>&1 || rc=$?
  # A missing CLI is infrastructure, never evidence of a working refusal.
  if [ "$wanted" = pass ]; then
    [ "$rc" -eq 0 ] && ok=yes || ok=no
  else
    [ "$rc" -ne 0 ] && grep -q '^REFUSED: release-notes ' "$FIXTURE/out" && ok=yes || ok=no
  fi
  if [ "$ok" = yes ]; then
    printf '%s PASS %s (exit=%s)\n' "$id" "$label" "$rc"
  else
    printf '%s FAIL %s (exit=%s)\n' "$id" "$label" "$rc"
    cat "$FIXTURE/out"
    FAILURES=$((FAILURES + 1))
  fi
}
both() {
  local id="$1" wanted="$2" label="$3"
  if [ "$label" != "docs only" ]; then
    printf "%s\n" "$label" >> "$FIXTURE/.aai/tool.txt"
    git -C "$FIXTURE" add -- .aai/tool.txt
  fi
  expect "$id" "$wanted" "staged: $label" --staged --body-file "$BODY"
  git -C "$FIXTURE" commit -qm "fixture $label" --allow-empty
  HEAD_SHA="$(git -C "$FIXTURE" rev-parse HEAD)"
  expect "$id" "$wanted" "CI range: $label" --base "$BASE" --head "$HEAD_SHA" --body-file "$BODY"
}
printf 'changed\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
both TEST-001 refuse 'shipped without notes; unchanged old entry'
printf '\n## [unreleased]\n\n' >> "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add -- CHANGELOG.md .aai/tool.txt
both TEST-001 refuse 'blank scaffold'
printf '\n## [unreleased] — new feature\n\n- New behavior ships.\n' >> "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add -- CHANGELOG.md
# Stage a shipped change again so staged and commit-range arms both exercise it.
printf 'changed again\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
both TEST-002 pass 'new nonempty notes'
# Begin a fresh comparison from this commit, with notes already old.
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
printf 'another change\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
printf 'no-notes:    \n' > "$BODY"
both TEST-002 refuse 'empty exemption'
printf 'no-notes:\n\nUnrelated paragraph\n' > "$BODY"
both TEST-002 refuse 'blank marker cannot consume later paragraph'
printf 'no-notes: maintenance needs no operator action\n' > "$BODY"
printf 'yet another change\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
both TEST-002 pass 'explicit reason'
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
mkdir -p "$FIXTURE/docs/specs"
printf 'docs change\n' > "$FIXTURE/docs/specs/x.md"
git -C "$FIXTURE" add -- docs/specs/x.md
printf 'Summary\n' > "$BODY"
both TEST-002 pass 'docs only'
expect TEST-003 refuse 'missing body' --staged --body-file "$FIXTURE/absent-body"
expect TEST-003 refuse 'unreadable body (directory)' --staged --body-file "$FIXTURE"
expect TEST-003 refuse 'missing history' --base deadbeef --head HEAD --body-file "$BODY"
printf 'no-notes: $(touch "%s/executed") `touch "%s/executed"`\n' "$FIXTURE" "$FIXTURE" > "$BODY"
printf 'untrusted-body change\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
both TEST-003 pass 'body stays data'
if [ -e "$FIXTURE/executed" ]; then echo 'TEST-003 FAIL body executed'; FAILURES=$((FAILURES + 1)); else echo 'TEST-003 PASS no body execution'; fi
# Resolve the executable through a symlink as the installed CLI can be linked.
REAL_GATE="$GATE"
ln -s "$REAL_GATE" "$FIXTURE/notes-gate-link.mjs"
GATE="$FIXTURE/notes-gate-link.mjs"
expect TEST-003 refuse 'symlink invocation executes gate' --staged --body-file "$FIXTURE/absent-body"
GATE="$REAL_GATE"
# Integration contracts: both entrypoints must invoke the same production CLI.
if grep -q 'release-notes-gate.mjs --staged --body-file' "$ROOT/.aai/SKILL_PR.prompt.md" &&
   grep -q 'release-notes-gate.mjs --base' "$ROOT/.github/workflows/skill-suite.yml" &&
   grep -q 'pull-requests: read' "$ROOT/.github/workflows/skill-suite.yml"; then
  echo 'TEST-003 PASS local and CI shared gate invocation'
else
  echo 'TEST-003 FAIL local/CI wiring missing'; FAILURES=$((FAILURES + 1))
fi
GATE_MODULE="$ROOT/.aai/scripts/release-notes-gate.mjs" node --input-type=module -e '
import { pathToFileURL } from "node:url";
const mod = await import(pathToFileURL(process.env.GATE_MODULE).href);
const { isShipped, hasNoNotesReason } = mod;
if (typeof isShipped !== "function" || typeof hasNoNotesReason !== "function") process.exit(1);
if (!isShipped(".aai/x", "") || !isShipped("tool", "100755") || isShipped("docs/specs/x.md", "100644")) process.exit(2);
if (!hasNoNotesReason("no-notes: because\n") || hasNoNotesReason("no-notes:   \n")) process.exit(3);
' && echo 'TEST-004 PASS exports' || { echo 'TEST-004 FAIL exports'; FAILURES=$((FAILURES + 1)); }
# SPEC-0229's notes-only absence assertions ended with its original ride.
# Finish composition is now checked in release TEST-015; retain this live gate pin.
if grep -q '  - .aai/scripts/release-notes-gate.mjs' "$ROOT/.aai/system/PROFILES.yaml"; then
  echo 'TEST-004 PASS gate profile'
else
  echo 'TEST-004 FAIL gate profile'; FAILURES=$((FAILURES + 1))
fi
# A later base commit is not part of the pull request. Two-dot diff would
# treat that base-only shipped edit as a reverse change, and a base-deleted
# note as a note the head added.
FORK="$(git -C "$FIXTURE" rev-parse HEAD)"
git -C "$FIXTURE" checkout -q -b diverge-head
mkdir -p "$FIXTURE/docs/specs"
printf 'docs only\n' > "$FIXTURE/docs/specs/x.md"
git -C "$FIXTURE" add -- docs/specs/x.md
git -C "$FIXTURE" commit -qm 'docs only head'
git -C "$FIXTURE" checkout -q -b diverge-base "$FORK"
printf 'base only shipped\n' >> "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
git -C "$FIXTURE" commit -qm 'base shipped'
printf 'Summary\n' > "$BODY"
expect TEST-005 pass 'docs-only head ignores a base-only shipped file' --base diverge-base --head diverge-head --body-file "$BODY"
git -C "$FIXTURE" checkout -q -B notes-head "$FORK"
printf 'shipped on head\n' >> "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
git -C "$FIXTURE" commit -qm 'head shipped no notes'
git -C "$FIXTURE" checkout -q -B notes-base "$FORK"
node -e 'const fs=require("fs"); const p=process.argv[1]; const t=fs.readFileSync(p,"utf8"); if(!t.includes("- New behavior ships.")) process.exit(2); fs.writeFileSync(p, t.replace("\n- New behavior ships.\n","\n"));' "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add -- CHANGELOG.md
git -C "$FIXTURE" commit -qm 'base drops an old note'
printf 'Summary\n' > "$BODY"
expect TEST-005 refuse 'a note deleted on the base is not a note the head added' --base notes-base --head notes-head --body-file "$BODY"
# spec-notes-content-and-merged-links TEST-001..004: compare actual Git notes
# content, not cosmetic replacement lines. All fixtures use the real CLI.
AAI_NOVELTY_GATE="$GATE" AAI_NOVELTY_SCRATCH="$SCRATCH_ROOT" AAI_NOVELTY_ROOT="$ROOT" node --input-type=module <<'JS' || { echo 'TEST-001 FAIL notes-content regressions'; FAILURES=$((FAILURES + 1)); }
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const scratch = process.env.AAI_NOVELTY_SCRATCH;
if (!scratch || !path.isAbsolute(scratch)) throw Error('absolute novelty scratch required');
const old = '## [unreleased] — Existing\n- Existing note.\n';
const corpus = fs.readFileSync(path.join(process.env.AAI_NOVELTY_ROOT,'CHANGELOG.md'),'utf8');
console.log(`Corpus files=1 path=CHANGELOG.md lines=${corpus.split('\n').length} sha256=${createHash('sha256').update(corpus).digest('hex')}`);
const cases = [
 ['TEST-001','trailing spaces',old,old.replace('note.\n','note.   \n'),1],
 ['TEST-001','trailing tab',old,old.replace('note.\n','note.\t\n'),1],
 ['TEST-002','LF to CRLF',old,old.replace(/\n/g,'\r\n'),1],
 ['TEST-002','CRLF to LF',old.replace(/\n/g,'\r\n'),old,1],
 ['TEST-003','new substantive note',old,old+'- Newly described behavior.\n',0],
 ['TEST-003','changed words',old,old.replace('Existing note.','Existing behavior now works.'),0],
 ['TEST-003','interior inline-code spacing','## [unreleased] — Existing\n- Use `a b`.\n','## [unreleased] — Existing\n- Use `a  b`.\n',0],
 ['TEST-003','mixed cosmetic and substantive',old,old.replace('note.\n','note.\t\n')+'- Newly described behavior.\n',0],
 ['TEST-001','explicit exemption control',old,old.replace('note.\n','note. \n'),0,'no-notes: cosmetic notes need no new entry\n'],
 ['TEST-004','unstaged content cannot satisfy indexed cosmetic edit',old,old.replace('note.\n','note. \n'),1,'Summary\n','- Unstaged substantive note.\n'],
 ['TEST-002','actual corpus formatting only',corpus,corpus.replace(/\r?\n/g,'\r\n'),1],
 ['TEST-003','actual corpus genuine addition',corpus,corpus+'\n## [unreleased] — new corpus control\n- A genuinely added note.\n',0],
];
let failures = 0;
for (const [id,label,before,after,wanted,body='Summary\n',unstaged=''] of cases) {
 const fixture = fs.mkdtempSync(path.join(scratch,'novelty.'));
 const git = (...args) => execFileSync('git',args,{cwd:fixture,encoding:'utf8'}).trim();
 try {
  git('init','-q','-b','main');git('config','user.name','novelty-fixture');git('config','user.email','novelty@example.invalid');git('config','core.hooksPath','/dev/null');
  fs.mkdirSync(path.join(fixture,'.aai'));fs.writeFileSync(path.join(fixture,'.aai/tool'),'old');fs.writeFileSync(path.join(fixture,'CHANGELOG.md'),before);
  git('add','--','.aai/tool','CHANGELOG.md');git('commit','-qm','base');const base=git('rev-parse','HEAD');
  fs.writeFileSync(path.join(fixture,'.aai/tool'),'new');fs.writeFileSync(path.join(fixture,'CHANGELOG.md'),after);git('add','--','.aai/tool','CHANGELOG.md');
  fs.writeFileSync(path.join(fixture,'body'),body);
  if (unstaged) fs.appendFileSync(path.join(fixture,'CHANGELOG.md'),unstaged);
  for (const mode of ['staged','range']) {
   if (mode==='range') git('commit','-qm','target');
   const args=mode==='staged'?['--staged']:['--base',base,'--head','HEAD'];
   const shipped=git('diff',...(mode==='staged'?['--cached',base]:[base,'HEAD']),'--name-only','--').split('\n').includes('.aai/tool');
   const result=spawnSync(process.execPath,[process.env.AAI_NOVELTY_GATE,...args,'--body-file',path.join(fixture,'body')],{cwd:fixture,encoding:'utf8'});
   const output=(result.stdout||'')+(result.stderr||'');const expected=wanted===1?'REFUSED: release-notes missing newly added':body.startsWith('no-notes:')?'PASS: release-notes explicit no-notes':'PASS: release-notes newly added unreleased';
   const ok=shipped && result.status===wanted && output.includes(expected);
   console.log(`${id} ${ok?'PASS':'FAIL'} ${mode}: ${label} shipped=${shipped} expected=${wanted} exit=${result.status} fixture=${fixture} base=${base} head=${git('rev-parse','HEAD')}\n${output.trim()}`);
   if (!ok) failures++;
  }
 } finally { fs.rmSync(fixture,{recursive:true,force:true}); }
}
console.log(`notes content assertions=${cases.length*2} failures=${failures}`);process.exitCode=failures?1:0;
JS

# SPEC-0229 Spec-AC-01 TEST-001..003: comments are scanned across every
# region before interpreting headings; hidden headings never reset state.
AAI_PARSER_GATE="$GATE" AAI_PARSER_SCRATCH="$SCRATCH_ROOT" node --input-type=module <<'JS' || { echo 'TEST-001 FAIL comment parser regressions'; FAILURES=$((FAILURES + 1)); }
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
const scratch = process.env.AAI_PARSER_SCRATCH;
if (!scratch || !path.isAbsolute(scratch)) throw new Error('absolute parser scratch required');
let failures = 0;
const cases = [
  ['hidden heading inside active region', '## [unreleased] — visible title\n<!--\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['hidden heading outside active region', '<!--\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['ordinary multiline comment control', '## [unreleased] — visible title\n<!--\nHidden text only.\n-->\n', 1],
  ['multiple closed comments and reopened comment', '## [unreleased] — visible title\n<!-- first --> <!-- second --> <!--\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['inline-code marker in title', '## [unreleased] — handle `<!--` markers\n- Literal markers render correctly.\n', 0],
  ['double-backtick span containing a single backtick', '## [unreleased] — handle `` ` <!-- `` markers\n- Literal markers render correctly.\n', 0],
  ['triple-backtick span containing shorter runs', '## [unreleased] — handle ``` `` <!-- ` ``` markers\n- Literal markers render correctly.\n', 0],
  ['unmatched backtick does not hide a genuine comment', '## [unreleased] — unmatched ` <!--\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['unmatched double run cannot become a single opener', '## [unreleased] — unmatched ``<!--`\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['unmatched triple run cannot become a shorter opener', '## [unreleased] — unmatched ```<!--``\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['mismatched delimiter does not hide a genuine comment', '## [unreleased] — unmatched `` ` <!--\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['literal code marker followed by genuine comment', '## [unreleased] — handle `<!--` <!--\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['escaped backtick does not hide a genuine comment', '## [unreleased] — escaped \\`<!--`\n## [unreleased] — hidden title\nHidden text only.\n-->\n', 1],
  ['code ticks within genuine comment remain hidden', '<!-- `\n## [unreleased] — hidden title\nHidden text only. `\n-->\n', 1],
  ['visible note positive control', '## [unreleased] — visible title\n- Real release note.\n', 0],
  ['visible body after closing comment', '## [unreleased] — visible title\n<!--\n## [v1] — hidden released title\n-->- Real release note after close.\n', 0],
  ['visible region after outside comment', '<!--\n## [unreleased] — hidden title\nHidden text only.\n-->\n## [unreleased] — visible title\n- Real release note.\n', 0],
];
for (const [label, notes, wanted] of cases) {
  const fixture = fs.mkdtempSync(path.join(scratch, 'parser.'));
  const git = (...args) => execFileSync('git', args, {cwd:fixture, encoding:'utf8'}).trim();
  try {
    git('init','-q','-b','main'); git('config','user.name','notes-parser-fixture');
    git('config','user.email','notes-parser@example.invalid'); git('config','core.hooksPath','/dev/null');
    fs.mkdirSync(path.join(fixture,'.aai')); fs.writeFileSync(path.join(fixture,'.aai/tool'),'old');
    fs.writeFileSync(path.join(fixture,'CHANGELOG.md'),'# Changelog\n'); git('add','--','.aai/tool','CHANGELOG.md'); git('commit','-qm','base');
    const base = git('rev-parse','HEAD');
    fs.writeFileSync(path.join(fixture,'.aai/tool'),'new'); fs.appendFileSync(path.join(fixture,'CHANGELOG.md'), notes);
    git('add','--','.aai/tool','CHANGELOG.md'); fs.writeFileSync(path.join(fixture,'body'),'Summary\n');
    for (const mode of ['staged','range']) {
      if (mode === 'range') git('commit','-qm','parser target');
      const args = mode === 'staged' ? ['--staged'] : ['--base',base,'--head','HEAD'];
      const result = spawnSync(process.execPath,[process.env.AAI_PARSER_GATE,...args,'--body-file',path.join(fixture,'body')],{cwd:fixture,encoding:'utf8'});
      const output = (result.stdout || '') + (result.stderr || '');
      const expected = wanted === 0 ? 'PASS: release-notes newly added unreleased entry' : 'REFUSED: release-notes missing newly added';
      const ok = result.status === wanted && output.includes(expected);
      console.log(`TEST-${wanted === 0 ? '002' : '001'} ${ok ? 'PASS' : 'FAIL'} ${mode}: ${label} expected=${wanted} exit=${result.status} fixture=${fixture} base=${base} head=${git('rev-parse','HEAD')}\n${output.trim()}`);
      if (!ok) failures++;
    }
  } finally { fs.rmSync(fixture,{recursive:true,force:true}); }
}
console.log(`comment parser assertions=${cases.length * 2} failures=${failures}`);
process.exitCode = failures ? 1 : 0;
JS
for fn in test_2706 test_2707 test_2708 test_2709 test_2710 test_2935; do "$fn" || FAILURES=$((FAILURES + 1)); done
printf 'release-notes assertions: failures=%s fixture=%s base=%s head=%s\n' "$FAILURES" "$FIXTURE" "$BASE" "$(git -C "$FIXTURE" rev-parse HEAD)"
[ "$FAILURES" -eq 0 ]
