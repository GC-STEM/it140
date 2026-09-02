#!/usr/bin/env python3
"""First-generation behavioral tests for CVD verify_it140.sh."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest


LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.runner import BASH_EXECUTABLE, CvdVerifyHarness, REPO_ROOT  # noqa: E402
from common.verify_log import consistency_errors, summary_int  # noqa: E402


HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"
VERIFY_SOURCE = REPO_ROOT / "scripts" / "cvd" / "verify_it140.sh"


class CvdVerifyLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = CvdVerifyHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_help_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("--help", "Usage: verify_it140.sh")

    def test_version_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("--version", "1.0.3")

    def _assert_early_exit(self, argument: str, expected_text: str) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-verify-cli-") as temp_name:
            home = Path(temp_name) / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(VERIFY_SOURCE), argument],
                cwd=home,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertIn(expected_text, completed.stdout + completed.stderr)
            self.assertFalse((home / "it140" / "logs").exists())

    def test_declared_scenarios(self) -> None:
        scenario_paths = [
            SCENARIO_DIR / "compliant.json",
            SCENARIO_DIR / "required_failure.json",
            SCENARIO_DIR / "manifest_failure.json",
            SCENARIO_DIR / "unsupported.json",
        ]

        for path in scenario_paths:
            scenario = self.harness.load_scenario(path)
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                try:
                    self._assert_scenario(run, scenario)
                finally:
                    shutil.rmtree(run.root, ignore_errors=True)

    def _assert_scenario(self, run, scenario) -> None:
        expected = scenario["expected"]
        self.assertEqual(
            expected["exit_code"],
            run.returncode,
            run.combined_output,
        )
        self.assertEqual([], run.protected_differences, run.combined_output)
        self.assertIsNotNone(
            run.log_file,
            "Verify should create exactly one transcript.\n" + run.combined_output,
        )
        self.assertIsNotNone(run.transcript, run.combined_output)

        assert run.log_file is not None
        assert run.transcript is not None

        self.assertEqual(0o700, stat.S_IMODE(run.log_dir.stat().st_mode))
        self.assertEqual(0o600, stat.S_IMODE(run.log_file.stat().st_mode))
        self.assertEqual(
            [],
            list(run.log_dir.glob("it140_support_cvd_*")),
            "Support directories must not be created unless explicitly requested.",
        )

        transcript = run.transcript
        self.assertEqual(expected["result"], transcript.summary.get("result"))
        self.assertEqual(
            expected["exit_code"],
            summary_int(transcript, "exit code"),
        )

        checks = transcript.checks_by_id
        for check_id, expected_status in expected.get("checks", {}).items():
            self.assertIn(check_id, checks, transcript.text)
            self.assertEqual(expected_status, checks[check_id].status)

        if "failed" in expected:
            self.assertEqual(expected["failed"], summary_int(transcript, "failed"))

        remediation = expected.get("remediation_contains")
        if remediation:
            self.assertIn(remediation, transcript.text)

        self.assertEqual(
            [],
            consistency_errors(transcript, run.returncode),
            transcript.text,
        )


if __name__ == "__main__":
    unittest.main()
