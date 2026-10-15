"""Deterministic regression for WORK reuse across built Lean checkouts.

Uses the repository's runner and real comparator/exporter/Lean binaries.
Set COMPARATOR_SRC and LEAN4EXPORT_SRC to built v4.33.0 checkouts and put
Lean 4.33.1's lake/lean on PATH. No Hypothesis or full FLT build is required.
ANTHROPIC_RUNNER can select a candidate repair for the same assertions.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
GOOD = "theorem proofFromTree : True := True.intro\n"
BAD = "axiom forbidden : True\ntheorem proofFromTree : True := forbidden\n"


class WorkRootTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for name in ("COMPARATOR_SRC", "LEAN4EXPORT_SRC"):
            if not os.environ.get(name):
                raise RuntimeError(f"Set {name} to the corresponding built v4.33.0 checkout")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="flt-work-root-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.env = os.environ.copy()
        self.env.pop("LEAN_PATH", None)
        self.env.update(LEAN_NUM_THREADS="4", VMEM_GB="640")

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def run_cmd(self, args, root, env=None):
        return subprocess.run(args, cwd=root, env=env or self.env, text=True,
                              capture_output=True, timeout=60, check=False)

    def build(self, root):
        result = self.run_cmd(["lake", "build"], root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def tree(self, name, proof):
        root = self.base / name
        runner = Path(os.environ.get("ANTHROPIC_RUNNER", HERE.parent / "comparator/run.sh"))
        script = root / "verification/comparator/run.sh"
        script.parent.mkdir(parents=True)
        shutil.copyfile(runner, script)
        self.write(root / "lean-toolchain", "leanprover/lean4:v4.33.1\n")
        self.write(root / "lakefile.toml", 'name = "fixture"\n'
                   'defaultTargets = ["Theorems", "Mathlib"]\n'
                   '[[lean_lib]]\nname = "Theorems"\n'
                   '[[lean_lib]]\nname = "Mathlib"\n')
        self.write(root / "Theorems.lean", "import Theorems.Proof\n")
        self.write(root / "Theorems/Proof.lean", proof)
        # The fixture uses only Lean core; this empty library satisfies the
        # runner's prerequisite without importing or claiming to test Mathlib.
        self.write(root / "Mathlib.lean", "-- Lean-core-only fixture.\n")
        config = root / "verification/comparator"
        self.write(config / "Challenge.lean", "theorem sample : True := True.intro\n")
        self.write(config / "Solution.lean",
                   "import Theorems.Proof\ntheorem sample : True := proofFromTree\n")
        self.write(config / "lakefile.toml", 'name = "fixture_wrapper"\n'
                   '[[lean_lib]]\nname = "Challenge"\n'
                   '[[lean_lib]]\nname = "Solution"\n')
        self.write(config / "config.json", json.dumps({
            "challenge_module": "Challenge", "solution_module": "Solution",
            "theorem_names": ["sample"], "permitted_axioms": [],
            "enable_nanoda": False,
        }) + "\n")
        self.build(root)
        return root

    def verify(self, root, work):
        result = self.run_cmd(["bash", str(root / "verification/comparator/run.sh")],
                              root, {**self.env, "WORK": str(work)})
        details = result.stdout + result.stderr
        for name in ("comparator.log", "comparator.err"):
            path = work / "wrapper" / name
            if path.exists():
                details += path.read_text(encoding="utf-8")
        return result.returncode, details

    def test_valid_tree_is_accepted(self):
        good = self.tree("good", GOOD)
        status, log = self.verify(good, self.base / "work")
        self.assertEqual(status, 0, log)
        self.assertIn("Your solution is okay!", log)

    def test_fresh_work_rejects_unpermitted_axiom(self):
        bad = self.tree("bad", BAD)
        status, log = self.verify(bad, self.base / "work")
        self.assertNotEqual(status, 0, log)
        self.assertIn("Illegal axiom detected: 'forbidden'", log)

    def test_reused_work_must_not_accept_previous_tree(self):
        good = self.tree("good", GOOD)
        bad = self.tree("bad", BAD)
        work = self.base / "shared-work"
        status, log = self.verify(good, work)
        self.assertEqual(status, 0, log)
        status, log = self.verify(bad, work)
        self.assertNotEqual(status, 0,
                            "The current tree uses an unpermitted axiom; a prior tree "
                            "must not supply its verification result.\n" + log)

    def test_same_root_rebuild_is_observed(self):
        root = self.tree("current", GOOD)
        work = self.base / "work"
        status, log = self.verify(root, work)
        self.assertEqual(status, 0, log)
        self.write(root / "Theorems/Proof.lean", BAD)
        self.build(root)
        status, log = self.verify(root, work)
        self.assertNotEqual(status, 0, log)
        self.assertIn("Illegal axiom detected: 'forbidden'", log)


if __name__ == "__main__":
    unittest.main()
