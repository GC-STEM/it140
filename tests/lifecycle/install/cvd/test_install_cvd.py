#!/usr/bin/env python3
"""Behavioral tests for CVD install_it140.sh."""

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
    CvdInstallHarness,
    INSTALL_SOURCE,
    MANIFEST_SOURCE,
)

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"


def supported_test_host() -> bool:
    return sys.platform.startswith("linux") and BASH_EXECUTABLE is not None


def required_cvd_packages() -> set[str]:
    manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
    platform = manifest["platforms"]["cvd"]
    packages = {
        item["package_identifier"]
        for item in platform.get("os_packages", {}).values()
        if item.get("required")
    }
    for binding in platform.get("course_ide_bindings", {}).values():
        if (
            binding.get("required")
            and binding.get("installation_scope") == "system"
            and binding.get("installer_adapter_id") == "apt_package"
        ):
            packages.add(binding["package_identifier"])
    return packages


@unittest.skipUnless(supported_test_host(), "CVD Install tests require a Linux host with Bash.")
class CvdInstallLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = CvdInstallHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_help_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("--help", "Usage: install_it140.sh")

    def test_version_returns_zero_without_creating_log(self) -> None:
        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        self._assert_early_exit("--version", manifest["automation_release"])

    def _assert_early_exit(self, argument: str, expected_text: str) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-install-cli-") as temp_name:
            home = Path(temp_name) / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(INSTALL_SOURCE), argument],
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
        ):
            scenario = self.harness.load_scenario(SCENARIO_DIR / name)
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                try:
                    self._assert_scenario(run, scenario)
                finally:
                    shutil.rmtree(run.root, ignore_errors=True)

    def test_successful_installation_is_semantically_idempotent(self) -> None:
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
        self.assertEqual(str(expected["exit_code"]), summary.get("Exit code"), diagnostics)
        self.assertEqual(str(run.log_file), summary.get("Log file"), diagnostics)
        self.assertEqual(run.returncode, int(summary.get("Exit code", "-1")), diagnostics)
        self.assertGreaterEqual(int(summary.get("Warnings", "-1")), 0, diagnostics)
        if run.returncode == 0:
            self.assertEqual(0, int(summary.get("Failures", "-1")), diagnostics)
            self._assert_installed_state(run)
        else:
            self.assertGreaterEqual(int(summary.get("Failures", "0")), 1, diagnostics)
        for text in expected.get("contains", []):
            self.assertIn(text, diagnostics)

    def _assert_installed_state(self, run) -> None:
        diagnostics = run.combined_output
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        installed = set(state.get("installed_packages", []))
        self.assertTrue(required_cvd_packages().issubset(installed), diagnostics)
        self.assertTrue(state.get("font_healthy"), diagnostics)
        numlock = run.system_root / "etc" / "xdg" / "autostart" / "numlockx.desktop"
        self.assertTrue(numlock.is_file(), diagnostics)
        numlock_text = numlock.read_text(encoding="utf-8")
        self.assertIn("Exec=/usr/bin/numlockx on", numlock_text)
        self.assertIn("OnlyShowIn=XFCE;", numlock_text)
        policy = (
            run.system_root
            / "etc"
            / "opt"
            / "chrome"
            / "policies"
            / "managed"
            / "it140_bookmarks.json"
        )
        self.assertTrue(policy.is_file(), diagnostics)
        policy_data = json.loads(policy.read_text(encoding="utf-8"))
        self.assertIs(policy_data.get("BookmarkBarEnabled"), True)
        managed = policy_data.get("ManagedBookmarks", [])
        self.assertTrue(managed and managed[0].get("toplevel_name") == "IT 140", diagnostics)


if __name__ == "__main__":
    unittest.main()
