#!/usr/bin/env python3
"""Behavioral tests for the macOS IT 140 Configure entry point."""

from __future__ import annotations

import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.configure_log import consistency_errors, summary_int  # noqa: E402
from runner_mac import (  # noqa: E402
    CONFIGURE_SOURCE,
    MANAGED_ENV_END,
    MANAGED_ENV_EXPORT,
    MANAGED_ENV_START,
    MANIFEST_SOURCE,
    MacConfigureHarness,
    ZSH_EXECUTABLE,
)

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"


def supported_mac_test_host() -> bool:
    return (
        sys.platform == "darwin"
        and platform.machine() == "arm64"
        and hasattr(os, "geteuid")
        and os.geteuid() != 0
        and Path(ZSH_EXECUTABLE).is_file()
    )


@unittest.skipUnless(
    supported_mac_test_host(),
    "macOS Configure behavioral tests require a non-root Apple-silicon macOS host.",
)
class MacConfigureLifecycleTests(unittest.TestCase):
    """Exercise configure_it140.zsh as a black-box process."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = MacConfigureHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_help_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("--help", "Usage: configure_it140.zsh")

    def test_version_returns_zero_without_creating_log(self) -> None:
        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        self._assert_early_exit("--version", manifest["automation_release"])

    def _assert_early_exit(self, argument: str, expected_text: str) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-configure-mac-cli-") as temp_name:
            home = Path(temp_name) / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                [ZSH_EXECUTABLE, str(CONFIGURE_SOURCE), argument],
                cwd=home,
                env=env,
                text=True,
                capture_output=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(0, completed.returncode, completed.stdout + completed.stderr)
            self.assertIn(expected_text, completed.stdout + completed.stderr)
            self.assertFalse((home / "it140" / "logs").exists())

    def test_declared_scenarios(self) -> None:
        for name in (
            "success.json",
            "manifest_failure.json",
            "unsupported.json",
            "partial_failure.json",
            "external_failure.json",
            "external_after_change.json",
        ):
            scenario = self.harness.load_scenario(SCENARIO_DIR / name)
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
            self._assert_scenario(sequence.second, scenario)
            self.assertEqual(
                sequence.first_state,
                sequence.second_state,
                sequence.second.combined_output,
            )
            for shell_file in ("zprofile", "zshrc"):
                text = sequence.second_state[shell_file]
                self.assertEqual(1, text.count(MANAGED_ENV_START))
                self.assertEqual(1, text.count(MANAGED_ENV_END))
                self.assertEqual(1, text.count(MANAGED_ENV_EXPORT))
        finally:
            shutil.rmtree(sequence.root, ignore_errors=True)

    def _assert_scenario(self, run, scenario) -> None:
        expected = scenario["expected"]
        diagnostics = run.combined_output or "No Configure output was captured."
        self.assertEqual(expected["exit_code"], run.returncode, diagnostics)
        self.assertEqual([], run.protected_differences, diagnostics)
        self.assertIsNotNone(run.log_file, diagnostics)
        self.assertIsNotNone(run.transcript, diagnostics)
        assert run.log_file is not None
        assert run.transcript is not None
        self.assertEqual(0o700, stat.S_IMODE(run.log_dir.stat().st_mode))
        self.assertEqual(0o600, stat.S_IMODE(run.log_file.stat().st_mode))
        transcript = run.transcript
        self.assertEqual(expected["result"], transcript.summary.get("result"), diagnostics)
        self.assertEqual(
            expected["managed_changes"],
            transcript.summary.get("managed changes"),
            diagnostics,
        )
        self.assertEqual(
            expected["exit_code"], summary_int(transcript, "exit code"), diagnostics
        )
        if "failures" in expected:
            self.assertEqual(
                expected["failures"], summary_int(transcript, "failures"), diagnostics
            )
        for text in expected.get("output_contains", []):
            self.assertIn(text, transcript.text, diagnostics)
        self.assertEqual([], consistency_errors(transcript, run.returncode), diagnostics)
        if expected.get("configured"):
            self._assert_configured_state(run)

    def _assert_configured_state(self, run) -> None:
        state = self.harness.configured_state(run)
        home = run.home

        self.assertIn("IT140_USER_ZPROFILE_SENTINEL=preserve-me", state["zprofile"])
        self.assertIn("IT140_USER_ZSHRC_SENTINEL=preserve-me", state["zshrc"])
        self.assertEqual(0o600, state["zprofile_mode"])
        self.assertEqual(0o600, state["zshrc_mode"])
        self.assertIn("alias it140-test-sentinel='printf preserved'", state["zshrc"])
        for text in (state["zprofile"], state["zshrc"]):
            self.assertEqual(1, text.count(MANAGED_ENV_START))
            self.assertEqual(1, text.count(MANAGED_ENV_END))
            self.assertEqual(1, text.count(MANAGED_ENV_EXPORT))
            self.assertNotIn("IT 140 Course IDE managed environment", text)

        self.assertEqual(str(home / "Repos"), state["repos_link"])
        self.assertEqual(0o755, state["launcher_mode"])
        self.assertEqual("IT140-MAC-VSCODE-REPOS-LAUNCHER-v1", state["launcher_marker"])
        self.assertIn("--reuse-window", state["launcher_text"])
        self.assertIn(str(home / "Repos"), state["launcher_text"])
        self.assertIn(str(home / "it140" / ".venv" / "bin" / "code"), state["launcher_text"])
        launcher_plist = state["launcher_plist"]
        self.assertEqual("edu.snhu.it140.vscode-repos", launcher_plist["CFBundleIdentifier"])
        self.assertEqual("open-repos", launcher_plist["CFBundleExecutable"])
        self.assertEqual("APPL", launcher_plist["CFBundlePackageType"])
        self.assertEqual(["arm64"], launcher_plist["LSArchitecturePriority"])

        settings = state["settings"]
        self.assertEqual("preserve-me", settings["it140.lifecycleTestSentinel"])
        self.assertEqual("on", settings["editor.wordWrap"])
        self.assertEqual(
            str(home / "it140" / ".venv" / "bin" / "python"),
            settings["python.defaultInterpreterPath"],
        )

        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        for key, value in self.harness.managed_vscode_settings(manifest).items():
            self.assertEqual(value, settings[key])

        mock_state = state["mock_state"]
        self.assertTrue(
            self.harness.required_extensions(manifest).issubset(
                set(mock_state["extensions"])
            )
        )
        self.assertTrue(
            self.harness.required_venv_packages(manifest).issubset(
                set(mock_state["venv_packages"])
            )
        )
        git_config = mock_state["git_config"]
        self.assertEqual("preserve-me", git_config["user.extra"])
        self.assertEqual("IT 140 Test Student", git_config["user.name"])
        self.assertTrue(git_config["user.email"].endswith("@users.noreply.github.com"))
        for key, value in self.harness.managed_git_settings(manifest).items():
            self.assertEqual(value, git_config[key])


if __name__ == "__main__":
    unittest.main()
