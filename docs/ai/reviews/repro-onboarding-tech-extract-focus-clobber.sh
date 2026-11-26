#!/usr/bin/env bash
# Repro (review onboarding-tech-contract-and-lint-gaps r1, NB): TECH_EXTRACT step 8 (set-focus technology_extraction),
# run by a sole agent in a project with an active focus, replaces that focus, and the next orchestration tick
# dispatches Planning for the phantom ref technology-extraction.
# Usage: repro-tech-extract-focus-clobber.sh <worktree> <scratch-dir>   (exit 0 = reproduced)
set -uo pipefail
WT="$1"; SC="$2"
[[ -n "$WT" && "$WT" == /* && -n "$SC" && "$SC" == /* ]] || { echo "absolute paths required"; exit 2; }
P="$SC/proj"; rm -rf "$P"; mkdir -p "$P/docs/ai"
cp -R "$WT/.aai" "$P/.aai"
cd "$P" || exit 2
git init -q -b main .
env -u AAI_ROLE node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml >/dev/null || exit 2
env -u AAI_ROLE node .aai/scripts/state.mjs set-focus --type intake_change --ref CHANGE-0042 --path docs/issues/CHANGE-0042.md >/dev/null || exit 2
sed 's/Status: template-seed/Status: generated/' .aai/templates/TECHNOLOGY_TEMPLATE.md > docs/TECHNOLOGY.md
cmd="$(node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8");const m=[...t.matchAll(/`(node \.aai\/scripts\/state\.mjs set-focus[^`]+)`/g)];console.log(m[0][1])' .aai/TECH_EXTRACT.prompt.md)"
env -u AAI_ROLE bash -c "$cmd" >/dev/null || exit 2
focus="$(sed -n '/^current_focus:/,/^active_work_items:/p' docs/ai/STATE.yaml | grep 'ref_id:')"
route="$(env -u AAI_ROLE node .aai/scripts/orchestration-dispatch.mjs | node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(j.verdict,j.rule,j.role,j.ref_id)')"
echo "focus after TECH_EXTRACT step 8:$focus"
echo "next orchestration tick: $route"
[[ "$focus" == *technology-extraction* && "$route" == *"Planning technology-extraction"* ]]
