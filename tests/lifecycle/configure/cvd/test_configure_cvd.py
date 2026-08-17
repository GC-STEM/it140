#!/usr/bin/env python3
"""First-generation behavioral tests for CVD configure_it140.sh."""

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

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.configure_log import consistency_errors, summary_int  # noqa: E402
from runner_cvd import (  # noqa: E402
    BASH_EXECUTABLE,
    CONFIGURE_SOURCE,
    CvdConfigureHarness,
    MANIFEST_SOURCE,
)

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"


def supported_cvd_test_host() -> bool:
    if sys.platform != "linux" or not hasattr(os, "geteuid") or os.geteuid() == 0:
        return False
    try:
        os_release = Path("/etc/os-release").read_text(encoding="utf-8")
    except OSError:
        return False
    return "ID=ubuntu" in os_release and 'VERSION_ID="24.04"' in os_release


@unittest.skipUnless(
    supported_cvd_test_host(),
    "CVD Configure behavioral tests require a non-root Ubuntu 24.04 host.",
)
class CvdConfigureLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = CvdConfigureHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_help_returns_zero_without_creating_log(self) -> None:
        self._assert_early_exit("--help", "Usage: configure_it140.sh")

    def test_version_returns_zero_without_creating_log(self) -> None:
        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        self._assert_early_exit("--version", manifest["automation_release"])

    def _assert_early_exit(self, argument: str, expected_text: str) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-configure-cli-") as temp_name:
            home = Path(temp_name) / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(CONFIGURE_SOURCE), argument],
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
            "partial_failure.json",
            "external_failure.json",
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
            for shell_file in ("bashrc", "profile"):
                text = sequence.second_state[shell_file]
                self.assertEqual(1, text.count("# >>> IT 140 managed PATH >>>"))
                self.assertEqual(1, text.count("# <<< IT 140 managed PATH <<<"))
                self.assertEqual(
                    1,
                    text.count('export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/cvd:$PATH"'),
                )
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
        home = run.home
        self.assertEqual([], state["baseline_present"])
        self.assertFalse(state["obsolete_present"])
        self.assertTrue(state["mock_state"]["numlock_on"])
        self.assertIn("custom", state["mock_state"]["emblems"])
        self.assertIn("development", state["mock_state"]["emblems"])
        self.assertEqual(0o755, state["launcher_mode"])
        self.assertIn("--reuse-window", state["launcher_text"])
        self.assertIn(str(home / "Repos"), state["launcher_text"])
        self.assertEqual(str(home / "Repos"), str((home / "Desktop" / "Repos").resolve()))

        self.assertIn("IT140_USER_BASHRC_SENTINEL=preserve-me", state["bashrc"])
        self.assertIn("IT140_USER_PROFILE_SENTINEL=preserve-me", state["profile"])
        settings = state["settings"]
        self.assertEqual("preserve-me", settings["it140.lifecycleTestSentinel"])
        self.assertEqual("on", settings["editor.wordWrap"])
        self.assertEqual(
            str(home / "it140" / ".venv" / "bin" / "python"),
            settings["python.defaultInterpreterPath"],
        )

        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        bindings = manifest["platforms"]["cvd"]["course_ide_bindings"]
        required_extensions = {
            binding["package_identifier"]
            for binding in bindings.values()
            if binding.get("required")
            and binding.get("installation_scope") == "user"
            and binding.get("installer_adapter_id") == "vscode_extension"
        }
        self.assertTrue(required_extensions.issubset(set(state["mock_state"]["extensions"])))
        git_config = state["mock_state"]["git_config"]
        self.assertEqual("preserve-me", git_config["user.extra"])
        self.assertEqual("IT 140 Test Student", git_config["user.name"])
        self.assertTrue(git_config["user.email"].endswith("@users.noreply.github.com"))


if __name__ == "__main__":
    unittest.main()
