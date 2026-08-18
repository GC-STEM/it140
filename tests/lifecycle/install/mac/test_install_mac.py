#!/usr/bin/env python3
"""Behavioral tests for macOS install_it140.zsh."""

from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

from runner_mac import INSTALL_SOURCE, MANIFEST_SOURCE, MacInstallHarness, ZSH_EXECUTABLE  # noqa: E402

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"


def supported_test_host() -> bool:
    return sys.platform == "darwin" and ZSH_EXECUTABLE.is_file()


def required_system_bindings() -> list[dict]:
    manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
    rows = []
    for role, binding in manifest["platforms"]["macos"]["course_ide_bindings"].items():
        if (
            binding.get("required") is True
            and binding.get("installation_scope") == "system"
            and binding.get("installer_adapter_id") in {"homebrew_formula", "homebrew_cask"}
        ):
            rows.append({"role": role, **binding})
    return rows


@unittest.skipUnless(supported_test_host(), "macOS Install tests require macOS with Zsh.")
class MacInstallLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = MacInstallHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_help_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("--help", "Usage: install_it140.zsh")

    def test_version_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("--version", "0.10.0-beta.1")

    def _assert_early_exit(self, argument: str, expected_text: str) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-install-mac-cli-") as temp_name:
            home = Path(temp_name) / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                [str(ZSH_EXECUTABLE), str(INSTALL_SOURCE), argument],
                cwd=home, env=env, text=True, capture_output=True, check=False,
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
            second = sequence.second
            diagnostics = second.combined_output
            self.assertEqual(0, second.returncode, diagnostics)
            self.assertEqual([], second.protected_differences, diagnostics)
            self.assertIsNotNone(second.transcript, diagnostics)
            assert second.transcript is not None
            self.assertEqual("PASS", second.transcript.summary.get("Result"), diagnostics)
            self.assertEqual("No", second.transcript.summary.get("Managed changes"), diagnostics)
            self.assertEqual("0", second.transcript.summary.get("Exit code"), diagnostics)
            self.assertEqual(sequence.first_state, sequence.second_state, diagnostics)
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
        self.assertEqual(0o600, stat.S_IMODE(run.log_file.stat().st_mode), diagnostics)
        self.assertEqual(0o700, stat.S_IMODE(run.log_dir.stat().st_mode), diagnostics)
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
        formulas = set(state.get("installed_formulas", []))
        casks = set(state.get("installed_casks", []))
        for binding in required_system_bindings():
            package = binding["package_identifier"]
            if binding["installer_adapter_id"] == "homebrew_cask":
                self.assertIn(package, casks, diagnostics)
            else:
                self.assertIn(package, formulas, diagnostics)
            for command in binding.get("verification", {}).get("executable_names", []):
                self.assertTrue((run.mock_dir / command).is_file(), diagnostics)
        vscode = run.home / "Applications" / "Visual Studio Code.app" / "Contents" / "Info.plist"
        self.assertTrue(vscode.is_file(), diagnostics)
        with vscode.open("rb") as handle:
            self.assertEqual("com.microsoft.VSCode", plistlib.load(handle).get("CFBundleIdentifier"))


if __name__ == "__main__":
    unittest.main()
