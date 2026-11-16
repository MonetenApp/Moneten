#!/usr/bin/env python3
"""Exercise CI routing and warning failures without a runner."""
import importlib.util
import pathlib
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("ci_plan", ROOT / "scripts/ci-plan.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CIContract(unittest.TestCase):
    def test_paths(self):
        cases = [
            (["README.md", "docs/a.txt", "openspec/a.yaml", ".github/ISSUE_TEMPLATE/bug.yml"], (False, False, False)),
            (["Sources/Domain/Ledger.swift"], (True, True, True)),
            (["Tests/FinTSTests/HelperProcessTests.swift"], (True, False, True)),
            (["scripts/test.sh"], (True, True, False)),
            ([".github/workflows/ci.yml"], (True, True, False)),
            ([".github/actions/ci-setup/action.yml"], (True, True, False)),
            (["Tools/FinTSHelper/FinTSHelper.java"], (True, False, False)),
            (["Package.resolved"], (True, False, False)),
            (["README.md", "Sources/Domain/Ledger.swift"], (True, True, True)),
            ([], (True, True, True)),
        ]
        for paths, expected in cases:
            with self.subTest(paths=paths):
                self.assertEqual(tuple(module.plan("pull_request", paths).values()), expected)
        for event in ["push", "workflow_dispatch"]:
            self.assertEqual(module.plan(event, ["README.md"]), dict(macos=True, app=True, periphery=True))

    def test_warning_exit_status(self):
        for diagnostic, code, expected in [
            ("Sources/Domain/Test.swift:1:2: warning: unused result", 0, 1),
            (f"{ROOT}/App/Sources/Test.swift:1:2: warning: unused result", 0, 1),
            (".build/checkouts/GRDB/Sources/Test.swift:1:2: warning: upstream", 0, 0),
            ("error: Demo.lua: expected test argument", 0, 0),
            ("plain output", 7, 7),
        ]:
            with self.subTest(diagnostic=diagnostic):
                result = subprocess.run([str(ROOT / "scripts/ci-run.sh"), sys.executable, "-c",
                                         "import sys; print(sys.argv[1]); sys.exit(int(sys.argv[2]))", diagnostic, str(code)],
                                        cwd=ROOT, capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
