#!/usr/bin/env python3
"""Behavioral tests for the Ubuntu GNOME IT 140 Verify entry point."""

from __future__ import annotations

from pathlib import Path
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
import sys
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.runner import BASH_EXECUTABLE, REPO_ROOT  # noqa: E402
from common.verify_log import consistency_errors, summary_int  # noqa: E402
from verify.ubg.runner_ubg import UbgVerifyHarness  # noqa: E402


HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"
VERIFY_SOURCE = REPO_ROOT / "scripts" / "nix" / "ubg" / "verify_ubg.sh"
SCENARIOS = (
    "compliant.json",
    "required_failure.json",
    "manifest_failure.json",
    "unsupported.json",
)


class UbgVerifyLifecycleTests(unittest.TestCase):
    """Exercise verify_ubg.sh as a black-box process."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = UbgVerifyHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def _assert_scenario(self, scenario_name: str) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / scenario_name)
        run = self.harness.run_scenario(scenario)
        self.addCleanup(shutil.rmtree, run.root, True)
        expected = scenario["expected"]
        diagnostics = run.combined_output or "No verifier output was captured."

        self.assertEqual(
            run.returncode,
            expected["exit_code"],
            msg=f"{run.scenario_id}: wrong process exit code\n\n{diagnostics}",
        )
        self.assertEqual(
            run.protected_differences,
            [],
            msg=(
                f"{run.scenario_id}: Verify changed protected state:\n"
                + "\n".join(run.protected_differences)
                + f"\n\n{diagnostics}"
            ),
        )
        self.assertIsNotNone(
            run.log_file,
            msg=f"{run.scenario_id}: verifier transcript was not created\n\n{diagnostics}",
        )
        self.assertIsNotNone(
            run.transcript,
            msg=f"{run.scenario_id}: verifier transcript could not be parsed\n\n{diagnostics}",
        )
        assert run.log_file is not None
        assert run.transcript is not None

        self.assertEqual(
            stat.S_IMODE(run.log_dir.stat().st_mode),
            0o700,
            msg=f"{run.scenario_id}: log directory mode is not 0700",
        )
        self.assertEqual(
            stat.S_IMODE(run.log_file.stat().st_mode),
            0o600,
            msg=f"{run.scenario_id}: log mode is not 0600",
        )

        transcript = run.transcript
        self.assertEqual(
            transcript.summary.get("result"),
            expected["result"],
            msg=f"{run.scenario_id}: wrong summary result\n\n{diagnostics}",
        )
        self.assertEqual(
            summary_int(transcript, "exit code"),
            expected["exit_code"],
            msg=f"{run.scenario_id}: wrong summary exit code\n\n{diagnostics}",
        )

        checks = transcript.checks_by_id
        for check_id, expected_status in expected.get("checks", {}).items():
            self.assertIn(
                check_id,
                checks,
                msg=f"{run.scenario_id}: missing check {check_id}\n\n{diagnostics}",
            )
            self.assertEqual(
                checks[check_id].status,
                expected_status,
                msg=f"{run.scenario_id}: wrong status for {check_id}\n\n{diagnostics}",
            )

        if "failed" in expected:
            self.assertEqual(
                summary_int(transcript, "failed"),
                expected["failed"],
                msg=f"{run.scenario_id}: wrong failed count\n\n{diagnostics}",
            )

        for text in expected.get("remediation_contains", []):
            self.assertIn(
                text,
                transcript.text,
                msg=f"{run.scenario_id}: expected remediation missing: {text!r}\n\n{diagnostics}",
            )

        self.assertEqual(
            consistency_errors(transcript, run.returncode),
            [],
            msg=f"{run.scenario_id}: transcript is internally inconsistent\n\n{diagnostics}",
        )

    def test_declared_scenarios(self) -> None:
        for scenario_name in SCENARIOS:
            with self.subTest(scenario=scenario_name):
                self._assert_scenario(scenario_name)

    def test_help_returns_zero_without_creating_log(self) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-verify-ubg-help-") as temp:
            home = Path(temp) / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(VERIFY_SOURCE), "--help"],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, msg=completed.stdout + completed.stderr)
            self.assertIn("Usage: verify_ubg.sh", completed.stdout)
            self.assertFalse((home / "it140" / "logs").exists())

    def test_version_returns_zero_without_creating_log(self) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-verify-ubg-version-") as temp:
            home = Path(temp) / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(VERIFY_SOURCE), "--version"],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, msg=completed.stdout + completed.stderr)
            self.assertIn("0.8.0-alpha.1", completed.stdout)
            self.assertFalse((home / "it140" / "logs").exists())


if __name__ == "__main__":
    unittest.main()
