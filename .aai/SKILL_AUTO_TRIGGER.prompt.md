# Auto-Trigger Skill — DEPRECATED

Status: DEPRECATED (CHANGE-0008 / SPEC-0014, 2026-07-07). Do not create or
edit `.claude/triggers.json` — nothing consumes it.

## Why

This skill only managed pattern-matching CRUD over `.claude/triggers.json`, a
config file with no runtime consumer: nothing in Claude Code, the AAI hooks,
or any script in this repository ever reads it (grep-proven in SPEC-0013 D8;
the file does not even exist in this repo). Triggers wired here never fire,
so the old manual trapped operators into configuring an inert mechanism.

## The real auto-invocation channel

Skill auto-invocation already works through wrapper-description trigger
phrases: the `description:` frontmatter of each skill wrapper
(`.claude/skills/<name>/SKILL.md` plus the `.codex`/`.gemini` mirrors) is what
the agent's native skill-matching reads. Put the phrases users actually say
into that description and the skill is picked up without a slash command.

Precedent: the `aai-wrap-up` wrapper carries its trigger phrases ("wrap up",
"end session", "done for today", "hotovo", "konec", "bye") directly in its
description — delivered and grep-tested by SPEC-0013 (TEST-016).

## What to do instead

- To make a skill auto-invocable, enrich the TARGET skill's wrapper
  `description:` with concrete trigger phrases, mirroring the edit to all
  three wrapper trees.
- Do not wire `.claude/triggers.json`; configured triggers never fire.

## Scope note

Building a real triggers.json consumer is out of scope for CHANGE-0008 (a
separate feature, if ever wanted). The `/aai-auto-trigger` wrappers remain in
all three trees pointing at this notice so muscle memory and mirror
consistency stay intact.
