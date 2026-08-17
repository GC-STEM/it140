#!/usr/bin/env python3
"""Behavioral tests for the Windows IT 140 Verify entry point."""

from __future__ import annotations

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.runner import REPO_ROOT  # noqa: E402
from common.verify_log import consistency_errors, summary_int  # noqa: E402
from verify.win.runner_win import POWERSHELL_EXECUTABLE, WinVerifyHarness  # noqa: E402

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
SCENARIO_DIR = HERE / "scenarios"
VERIFY_SOURCE = REPO_ROOT / "scripts" / "win" / "verify_it140.ps1"
SCENARIOS = (
    "compliant.json",
    "required_failure.json",
    "manifest_failure.json",
    "unsupported.json",
)


@unittest.skipUnless(sys.platform == "win32", "Windows Verify tests require a Windows runner")
class WinVerifyLifecycleTests(unittest.TestCase):
    """Exercise verify_it140.ps1 as a black-box Windows PowerShell process."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = WinVerifyHarness(FIXTURE_BASE)

    def _assert_scenario(self, scenario_name: str) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / scenario_name)
        run = self.harness.run_scenario(scenario)
        self.addCleanup(shutil.rmtree, run.root, True)
        expected = scenario["expected"]
        diagnostics = run.combined_output or "No verifier output was captured."

        self.assertEqual(run.returncode, expected["exit_code"], msg=f"{run.scenario_id}: wrong process exit code\n\n{diagnostics}")
        self.assertEqual(run.protected_differences, [], msg=f"{run.scenario_id}: Verify changed protected state:\n" + "\n".join(run.protected_differences) + f"\n\n{diagnostics}")
        self.assertIsNotNone(run.log_file, msg=f"{run.scenario_id}: verifier transcript was not created\n\n{diagnostics}")
        self.assertIsNotNone(run.transcript, msg=f"{run.scenario_id}: verifier transcript could not be parsed\n\n{diagnostics}")
        assert run.transcript is not None
        transcript = run.transcript
        self.assertEqual(summary_int(transcript, "exit code"), expected["exit_code"], msg=diagnostics)
        checks = transcript.checks_by_id
        for check_id, expected_status in expected.get("checks", {}).items():
            self.assertIn(check_id, checks, msg=f"{run.scenario_id}: missing {check_id}\n\n{diagnostics}")
            self.assertEqual(checks[check_id].status, expected_status, msg=diagnostics)
        if "failed" in expected:
            self.assertEqual(summary_int(transcript, "failed"), expected["failed"], msg=diagnostics)
        for text in expected.get("remediation_contains", []):
            self.assertIn(text, transcript.text, msg=f"{run.scenario_id}: missing remediation {text!r}\n\n{diagnostics}")
        self.assertEqual(consistency_errors(transcript, run.returncode), [], msg=diagnostics)

    def test_declared_scenarios(self) -> None:
        for scenario_name in SCENARIOS:
            with self.subTest(scenario=scenario_name):
                self._assert_scenario(scenario_name)

    def _run_cli(self, option: str) -> subprocess.CompletedProcess[str]:
        assert POWERSHELL_EXECUTABLE is not None
        return subprocess.run(
            [POWERSHELL_EXECUTABLE, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(VERIFY_SOURCE), option],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )

    def test_help_returns_zero_without_creating_log(self) -> None:
        log_dir = REPO_ROOT / "logs"
        before = set(log_dir.glob("verify_win_*.log")) if log_dir.exists() else set()
        completed = self._run_cli("-Help")
        after = set(log_dir.glob("verify_win_*.log")) if log_dir.exists() else set()
        self.assertEqual(completed.returncode, 0, msg=completed.stdout + completed.stderr)
        self.assertIn("IT 140 Windows verification script", completed.stdout)
        self.assertEqual(before, after)

    def test_version_returns_zero_without_creating_log(self) -> None:
        log_dir = REPO_ROOT / "logs"
        before = set(log_dir.glob("verify_win_*.log")) if log_dir.exists() else set()
        completed = self._run_cli("-Version")
        after = set(log_dir.glob("verify_win_*.log")) if log_dir.exists() else set()
        self.assertEqual(completed.returncode, 0, msg=completed.stdout + completed.stderr)
        self.assertIn("0.10.0-beta.1", completed.stdout)
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
