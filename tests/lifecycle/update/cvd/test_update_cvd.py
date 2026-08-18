#!/usr/bin/env python3
"""Behavioral tests for CVD update_it140.sh."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

from runner_cvd import (  # noqa: E402
    BASH_EXECUTABLE,
    CvdUpdateHarness,
    MANIFEST_SOURCE,
    UPDATE_SOURCE,
)

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"


def supported_test_host() -> bool:
    return sys.platform.startswith("linux") and BASH_EXECUTABLE is not None


def manifest_requirements() -> tuple[set[str], set[str], set[str]]:
    manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
    system, venv, extensions = CvdUpdateHarness._manifest_requirements(manifest)
    return set(system), set(venv), set(extensions)


@unittest.skipUnless(supported_test_host(), "CVD Update tests require a Linux host with Bash.")
class CvdUpdateLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = CvdUpdateHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_help_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("--help", "Usage: update_it140.sh")

    def test_version_returns_zero_without_creating_log(self) -> None:
        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        self._assert_early_exit("--version", manifest["automation_release"])

    def _assert_early_exit(self, argument: str, expected_text: str) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-update-cli-") as temp_name:
            home = Path(temp_name) / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(UPDATE_SOURCE), argument],
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
        for name in (
            "success.json",
            "manifest_failure.json",
            "unsupported.json",
            "privilege_failure.json",
            "external_failure.json",
            "external_after_change.json",
            "partial_failure.json",
            "restart_required.json",
        ):
            scenario = self.harness.load_scenario(SCENARIO_DIR / name)
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                try:
                    self._assert_scenario(run, scenario)
                finally:
                    shutil.rmtree(run.root, ignore_errors=True)

    def test_successful_update_is_semantically_idempotent(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        sequence = self.harness.run_twice(scenario)
        try:
            self._assert_scenario(sequence.first, scenario)
            self._assert_scenario(sequence.second, scenario)
            self.assertEqual(
                sequence.first_state,
                sequence.second_state,
                sequence.second.combined_output,
            )
        finally:
            shutil.rmtree(sequence.root, ignore_errors=True)

    def _assert_scenario(self, run, scenario: dict) -> None:
        expected = scenario["expected"]
        diagnostics = run.combined_output
        self.assertEqual(expected["exit_code"], run.returncode, diagnostics)
        self.assertEqual([], run.protected_differences, diagnostics)
        self.assertIsNotNone(run.log_file, diagnostics)
        self.assertIsNotNone(run.transcript, diagnostics)
        assert run.log_file is not None
        assert run.transcript is not None
        self.assertEqual(0o600, stat.S_IMODE(run.log_file.stat().st_mode) & 0o777, diagnostics)
        self.assertEqual(0o700, stat.S_IMODE(run.log_dir.stat().st_mode) & 0o777, diagnostics)
        summary = run.transcript.summary
        self.assertEqual(expected["result"], summary.get("Result"), diagnostics)
        self.assertEqual(expected["managed_changes"], summary.get("Managed changes"), diagnostics)
        self.assertEqual(expected["restart_required"], summary.get("Restart required"), diagnostics)
        self.assertEqual(str(expected["exit_code"]), summary.get("Exit code"), diagnostics)
        self.assertEqual(str(run.log_file), summary.get("Log file"), diagnostics)
        self.assertEqual(run.returncode, int(summary.get("Exit code", "-1")), diagnostics)
        self.assertEqual(expected["failures"], int(summary.get("Failures", "-1")), diagnostics)
        self.assertGreaterEqual(
            int(summary.get("Warnings", "-1")),
            int(expected.get("warnings_min", 0)),
            diagnostics,
        )
        for text in expected.get("contains", []):
            self.assertIn(text, diagnostics)
        if run.returncode == 0:
            self._assert_updated_state(run)

    def _assert_updated_state(self, run) -> None:
        diagnostics = run.combined_output
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        required_system, required_venv, required_extensions = manifest_requirements()
        self.assertTrue(required_system.issubset(set(state.get("installed_packages", []))), diagnostics)
        self.assertTrue(required_venv.issubset(set(state.get("venv_packages", []))), diagnostics)
        self.assertTrue(required_extensions.issubset(set(state.get("extensions", []))), diagnostics)
        self.assertTrue(state.get("font_healthy"), diagnostics)
        numlock = run.system_root / "etc" / "xdg" / "autostart" / "numlockx.desktop"
        self.assertTrue(numlock.is_file(), diagnostics)
        numlock_text = numlock.read_text(encoding="utf-8")
        self.assertIn("Exec=/usr/bin/numlockx on", numlock_text)
        self.assertIn("OnlyShowIn=XFCE;", numlock_text)
        active_manifest = run.home / "it140" / "scripts" / ".manifest" / "it140_manifest.json"
        active_schema = run.home / "it140" / "scripts" / ".manifest" / "it140_manifest.schema.json"
        self.assertEqual(MANIFEST_SOURCE.read_bytes(), active_manifest.read_bytes(), diagnostics)
        self.assertTrue(active_schema.is_file(), diagnostics)


if __name__ == "__main__":
    unittest.main()
