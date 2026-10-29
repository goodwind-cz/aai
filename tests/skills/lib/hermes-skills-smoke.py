"""Exercise the installed Hermes consumer and real AAI sync without credentials."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

repo, hermes = (Path(p).resolve() for p in sys.argv[1:])
# One disposable tree, reused for every mutation. No real profile is read.
with tempfile.TemporaryDirectory(prefix="aai-hermes-") as temporary:
    scratch = Path(temporary).resolve()
    source, project, home = (scratch / p for p in ("source", "project", "home"))
    for p in (source, project, home):
        p.mkdir()
    os.environ["HERMES_HOME"] = str(home)
    os.environ["TERMINAL_CWD"] = str(project)
    os.environ.pop("HERMES_PROFILE", None)
    sys.path.insert(0, str(hermes))
    import yaml  # already installed in Hermes; this suite never installs dependencies
    from agent.skill_commands import (get_interactive_skill_commands,
                                      build_skill_invocation_message, reload_skills)
    from hermes_cli.main_agent_cmds import _cmd_skills_trust
    from tools.skills_tool import skills_list

    def run(*args, cwd=repo):
        result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        print(f"COMMAND {list(args)!r} cwd={cwd} exit={result.returncode}", flush=True)
        if result.returncode:
            print(result.stdout)
            raise AssertionError("command failed")
        return result.stdout

    print(f"ref_id=hermes-agent-skill-discovery workspace={project} home={home}")
    print(f"Hermes source={hermes} revision={run('git', '-C', str(hermes), 'rev-parse', 'HEAD').strip()}")
    print(f"runtime={sys.executable} Python={sys.version} platform={sys.platform}")
    for name in (".aai", ".claude/skills", ".agents/skills", ".codex/skills", ".gemini/skills", ".github", ".cursor", "hooks"):
        if (repo / name).exists():
            shutil.copytree(repo / name, source / name)
    for name in ("AGENTS.md", "CLAUDE.md", "CODEX.md", "GEMINI.md", "README.md"):
        shutil.copy2(repo / name, source / name)
    (source / "docs").mkdir()
    shutil.copy2(repo / "docs/USER_GUIDE.md", source / "docs/USER_GUIDE.md")
    run("git", "init", "-b", "main", str(project))
    manifest = yaml.safe_load((source / ".aai/system/HARNESS_SKILLS.yaml").read_text())
    excluded = {row.split("|")[1] for row in manifest["exclusions"] or []
                if row.split("|")[0] == ".agents/skills"}
    expected = {}
    for wrapper in (source / ".claude/skills").glob("*/SKILL.md"):
        if wrapper.parent.name not in excluded:
            metadata = dict(re.findall(r"^(name|description): (.*)$", wrapper.read_text(), re.M))
            metadata = {key: (yaml.safe_load(value) if value.startswith(('"', "'")) else value)
                        for key, value in metadata.items()}
            expected[metadata["name"]] = metadata["description"]
    assert expected and "aai-intake" in expected

    def sync():
        run("bash", str(source / ".aai/scripts/aai-sync.sh"), str(project), "--profile", "extended")

    def trust(action):
        _cmd_skills_trust(argparse.Namespace(skills_action=action, path=str(project)))
        reload_skills()

    def catalog():
        commands = get_interactive_skill_commands()
        listed = json.loads(skills_list())
        assert listed["success"]
        rows = [r for r in listed["skills"] if r["name"].startswith("aai-")]
        actual = {key.lstrip("/"): value["description"] for key, value in commands.items()
                  if key.lstrip("/").startswith("aai-")}
        assert actual == expected, f"interactive set/metadata mismatch: {set(expected) ^ set(actual)}"
        assert len(rows) == len(expected), "duplicate or missing listed skill"
        assert {r["name"]: r["description"] for r in rows} == expected
        assert all(actual.values())
        return actual

    def negative(label, assertion):
        try:
            assertion()
        except AssertionError as error:
            print(f"NEGATIVE {label}: observed assertion failure: {error}")
        else:
            raise AssertionError(f"negative control did not bite: {label}")

    def green(number, ac):
        print(f"TEST-{number:03} GREEN {ac}", flush=True)

    sync()
    assert project.is_absolute() and project.is_dir()
    os.chdir(project)
    assert not [k for k in get_interactive_skill_commands() if k.startswith('/aai-')]
    negative("remove trust", catalog)
    trust("trust")
    catalog()
    trust("untrust")
    negative("revoke trust", catalog)
    trust("trust")
    catalog()
    trust("trust")
    print("NATIVE INTERACTIVE MAP " + json.dumps(catalog(), sort_keys=True))
    green(1, "Spec-AC-01")

    nested = project / "src/nested"
    nested.mkdir(parents=True)
    os.environ["TERMINAL_CWD"] = str(nested)
    assert nested.is_absolute() and nested.is_dir()
    os.chdir(nested)
    reload_skills()
    catalog()
    intake = project / ".agents/skills/aai-intake/SKILL.md"
    original = intake.read_bytes()
    intake.unlink()
    reload_skills()
    negative("delete wrapper", catalog)
    intake.write_bytes(original)
    reload_skills()
    catalog()
    green(2, "Spec-AC-01")

    def selection():
        message = build_skill_invocation_message("/aai-intake", "native smoke")
        assert message, "native selection absent"
        pointers = re.findall(r"`(\.aai/[^`]+\.prompt\.md)`", message)
        assert pointers, "canonical prompt pointer absent"
        for pointer in pointers:
            resolved = project / pointer
            assert resolved.is_file(), f"selected prompt missing: {resolved}"
            assert resolved.read_bytes() == (source / pointer).read_bytes()
        assert ".aai/SKILL_INTAKE.prompt.md" in pointers
        return message

    print("NATIVE SELECTION " + selection())
    intake.write_bytes(original.replace(b"SKILL_INTAKE.prompt.md", b"MISSING.prompt.md"))
    reload_skills()
    negative("nonexistent prompt pointer", selection)
    intake.write_bytes(original)
    reload_skills()
    selection()
    green(3, "Spec-AC-02")

    personal = home / "skills/personal-note/SKILL.md"
    local = project / ".agents/skills/project-note/SKILL.md"
    for path in (personal, local):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"---\nname: {path.parent.name}\ndescription: User-owned note\n---\nKeep these bytes.\n")
    preserved = {p: p.read_bytes() for p in (personal, local)}
    sync()
    reload_skills()
    catalog()
    updated = expected["aai-intake"] + " Refreshed native fixture."
    source_intake = source / ".claude/skills/aai-intake/SKILL.md"
    source_intake.write_text(source_intake.read_text().replace(expected["aai-intake"], updated))
    run("node", str(source / ".aai/scripts/sync-harness-skills.mjs"), "--write", cwd=source)
    expected["aai-intake"] = updated
    reload_skills()
    negative("skip update sync", catalog)
    sync()
    reload_skills()
    catalog()
    green(4, "Spec-AC-03")

    def preservation():
        assert all(p.read_bytes() == content for p, content in preserved.items()), "user skill bytes changed"
    preservation()
    local.write_text("mutated")
    negative("alter unrelated skill", preservation)
    local.write_bytes(preserved[local])
    preservation()
    run("node", str(repo / ".aai/scripts/sync-harness-skills.mjs"), "--check")
    green(5, "Spec-AC-04")

    guide = source / "docs/USER_GUIDE.md"
    def documentation():
        section = guide.read_text().split("### Hermes Agent\n", 1)
        assert len(section) == 2, "Hermes guide section absent"
        section = section[1].split("### ", 1)[0]
        for token in ("bf0203a794a07aac3ff764972ab9087baa4e4f4e", "--profile extended",
                      "skills trust", "/path/to/your-project", "--profile work", "/reload-skills",
                      "fresh session", "/aai-intake", "Core", "Windows-native", "quarantined"):
            assert token in section, f"missing documented prerequisite: {token}"
        cli = (hermes / "cli.py").read_text()
        assert '"reload-skills": ("_cmd_reload_skills"' in cli
        assert "self._reload_skills()" in (hermes / "hermes_cli/cli_loops_mixin.py").read_text()
        assert "from agent.skill_commands import reload_skills" in (hermes / "hermes_cli/cli_info_mixin.py").read_text()
    documentation()
    text = guide.read_text()
    guide.write_text(text.replace("### Hermes Agent\n", "### Removed\n"))
    negative("remove guide", documentation)
    guide.write_text(text)
    documentation()
    green(6, "Spec-AC-05")
    print("6/6 GREEN; native execution; no skipped evidence; no credentials or LLM calls")
