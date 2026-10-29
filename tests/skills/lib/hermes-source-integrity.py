"""Source-attestation regression fixtures; never modify the installed Hermes tree."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

repo = Path.cwd()
smoke = repo / "tests/skills/lib/hermes-skills-smoke.py"
with tempfile.TemporaryDirectory(prefix="hermes-integrity-") as directory:
    root = Path(directory).resolve()
    def git(*args):
        env = dict(os.environ, AAI_GIT_WRITE="1")
        subprocess.run(["git", "-C", str(root), *args], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    git("init", "-b", "main")
    agent = root / "agent"
    agent.mkdir()
    (agent / "__init__.py").write_text('raise SystemExit("IMPORT BEFORE PREFLIGHT")\n')
    tracked = root / "tracked.py"
    tracked.write_text("original = True\n")
    git("add", ".")
    git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
        "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture baseline")

    failures = []
    def probe(label, dirty):
        result = subprocess.run([sys.executable, str(smoke), str(repo), str(root)] +
                                ([] if dirty else ["--source-check-only"]), text=True, capture_output=True)
        output = result.stdout + result.stderr
        if dirty:
            if not (result.returncode != 0 and "Hermes source is dirty" in output and
                    "IMPORT BEFORE PREFLIGHT" not in output):
                failures.append(label)
                print(f"source-integrity {label} FAIL: {output}", flush=True)
                return
        else:
            if not (result.returncode == 0 and "Hermes source preflight clean" in output):
                failures.append(label)
                print(f"source-integrity {label} FAIL: {output}", flush=True)
                return
        print(f"source-integrity {label} GREEN", flush=True)

    # Each mutation is committed in this disposable fixture before the next case;
    # no restore/reset command touches tracked files or the real installation.
    tracked.write_text("worktree_change = True\n")
    probe("dirty worktree refused before import", True)
    git("add", "tracked.py")
    probe("dirty index refused before import", True)
    git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
        "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture second baseline")
    untracked = agent / "new_module.py"
    untracked.write_text("untracked = True\n")
    probe("nonignored untracked source refused before import", True)
    untracked.unlink()
    probe("clean source accepted without import", False)

assert not failures, failures
