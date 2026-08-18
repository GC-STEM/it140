#!/usr/bin/env python3
"""Behavioral tests for the Windows IT 140 Configure entry point."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.configure_log import consistency_errors, summary_int  # noqa: E402
from runner_win import (  # noqa: E402
    CONFIGURE_SOURCE,
    MANIFEST_SOURCE,
    POWERSHELL_EXECUTABLE,
    WinConfigureHarness,
)

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
SCENARIO_DIR = HERE / "scenarios"
SCENARIOS = (
    "success.json",
    "manifest_failure.json",
    "unsupported.json",
    "privilege_failure.json",
    "external_failure.json",
    "partial_failure.json",
)


@unittest.skipUnless(sys.platform == "win32", "Windows Configure tests require a Windows runner")
class WinConfigureLifecycleTests(unittest.TestCase):
    """Exercise configure_it140.ps1 as a black-box Windows PowerShell process."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = WinConfigureHarness(FIXTURE_BASE)

    def test_help_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("-Help", "IT 140 Windows configure script")

    def test_version_returns_zero_without_creating_log(self) -> None:
        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        self._assert_early_exit("-Version", manifest["automation_release"])

    def _assert_early_exit(self, option: str, expected_text: str) -> None:
        assert POWERSHELL_EXECUTABLE is not None
        repo_log_dir = CONFIGURE_SOURCE.parents[2] / "logs"
        before_logs = set(repo_log_dir.glob("config_win_*.log")) if repo_log_dir.exists() else set()
        completed = subprocess.run(
            [
                POWERSHELL_EXECUTABLE,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(CONFIGURE_SOURCE),
                option,
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        after_logs = set(repo_log_dir.glob("config_win_*.log")) if repo_log_dir.exists() else set()
        self.assertEqual(0, completed.returncode, completed.stdout + completed.stderr)
        self.assertIn(expected_text, completed.stdout + completed.stderr)
        self.assertEqual(before_logs, after_logs)

    def test_declared_scenarios(self) -> None:
        for scenario_name in SCENARIOS:
            scenario = self.harness.load_scenario(SCENARIO_DIR / scenario_name)
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                try:
                    self._assert_scenario(run, scenario)
                finally:
                    shutil.rmtree(run.root, ignore_errors=True)

    def test_successful_configuration_is_semantically_idempotent(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        sequence = self.harness.run_twice(scenario)
        try:
            self._assert_scenario(sequence.first, scenario)
            self.assertEqual(0, sequence.second.returncode, sequence.second.combined_output)
            assert sequence.second.transcript is not None
            self.assertEqual("PASS", sequence.second.transcript.summary.get("result"))
            self.assertEqual(
                [], consistency_errors(sequence.second.transcript, sequence.second.returncode)
            )
            self.assertEqual(sequence.first_state, sequence.second_state)
        finally:
            shutil.rmtree(sequence.root, ignore_errors=True)

    def _assert_scenario(self, run, scenario) -> None:
        expected = scenario["expected"]
        diagnostics = run.combined_output or "No Configure output was captured."
        self.assertEqual(expected["exit_code"], run.returncode, diagnostics)
        self.assertEqual([], run.protected_differences, diagnostics)
        self.assertIsNotNone(run.log_file, diagnostics)
        self.assertIsNotNone(run.transcript, diagnostics)
        assert run.transcript is not None
        transcript = run.transcript
        self.assertEqual(expected["result"], transcript.summary.get("result"), diagnostics)
        self.assertEqual(
            expected["managed_changes"],
            transcript.summary.get("managed changes"),
            diagnostics,
        )
        self.assertEqual(expected["exit_code"], summary_int(transcript, "exit code"), diagnostics)
        if "failures" in expected:
            self.assertEqual(expected["failures"], summary_int(transcript, "failures"), diagnostics)
        for text in expected.get("output_contains", []):
            self.assertIn(text, transcript.text, diagnostics)
        self.assertEqual([], consistency_errors(transcript, run.returncode), diagnostics)
        if expected.get("configured"):
            self._assert_configured_state(run)

    def _assert_configured_state(self, run) -> None:
        state = self.harness.configured_state(run)
        mock_state = state["state"]
        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        home = run.home
        win_dir = home / "it140" / "scripts" / "win"
        venv_scripts = home / "it140" / ".venv" / "Scripts"
        venv_python = venv_scripts / "python.exe"

        self.assertEqual(
            [str(venv_scripts), str(win_dir), r"C:\UserTools"],
            mock_state["user_path"].split(";"),
        )
        self.assertEqual("3.12", mock_state["venv_python_version"])
        self.assertTrue(
            self.harness.required_venv_packages(manifest).issubset(
                set(mock_state["python_packages"])
            )
        )
        self.assertTrue(
            self.harness.required_extensions(manifest).issubset(
                {value.lower() for value in mock_state["extensions"]}
            )
        )
        self.assertIn("publisher.unrelated", mock_state["extensions"])

        git_config = mock_state["git_config"]
        self.assertEqual("preserve-me", git_config["it140.unmanaged"])
        self.assertEqual("IT 140 Test Student", git_config["user.name"])
        self.assertEqual(
            "12345+it140-test@users.noreply.github.com", git_config["user.email"]
        )
        for key, value in self.harness.managed_git_settings(manifest).items():
            self.assertEqual(value, git_config[key])

        settings = state["settings"]
        self.assertEqual("preserve-me", settings["it140.lifecycleTestSentinel"])
        self.assertEqual(17, settings["editor.fontSize"])
        self.assertEqual("Default Dark+", settings["workbench.colorTheme"])
        for key, value in self.harness.managed_vscode_settings(manifest, venv_python).items():
            self.assertEqual(value, settings[key])

        shortcuts = mock_state["shortcuts"]
        self.assertIn("Repos.lnk", shortcuts)
        self.assertIn("Visual Studio Code - IT 140.lnk", shortcuts)
        self.assertEqual(str(home / "Repos"), shortcuts["Repos.lnk"]["WorkingDirectory"])
        self.assertEqual(
            str(home / "Repos"),
            shortcuts["Visual Studio Code - IT 140.lnk"]["WorkingDirectory"],
        )


if __name__ == "__main__":
    unittest.main()
