#!/usr/bin/env python3
"""Characterization/regression tests for the current Beta CVD Prepare script."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import stat
import sys
import unittest

from runner_cvd import (  # noqa: E402
    BASH_EXECUTABLE,
    CvdPrepareHarness,
    host_is_ubuntu,
)

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"
PATH_LINE = 'export PATH="$HOME/it140/scripts/cvd:$PATH"'


def supported_test_host() -> bool:
    # The current production script directly sources /etc/os-release before
    # establishing its transcript. Do not add a production test seam merely to
    # make this suite portable; the CVD CI job runs on Ubuntu 24.04.
    return sys.platform.startswith("linux") and BASH_EXECUTABLE is not None and host_is_ubuntu()


@unittest.skipUnless(
    supported_test_host(),
    "Current CVD Prepare characterization tests require an Ubuntu host with Bash.",
)
class CvdPrepareLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = CvdPrepareHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_declared_refresh_scenarios_match_current_beta_behavior(self) -> None:
        for name in (
            "success.json",
            "unsupported.json",
            "privilege_failure.json",
            "external_failure.json",
            "archive_failure.json",
            "sanitize_failure.json",
        ):
            scenario = self.harness.load_scenario(SCENARIO_DIR / name)
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                try:
                    self._assert_current_scenario(run, scenario)
                finally:
                    shutil.rmtree(run.root, ignore_errors=True)

    def test_successful_refresh_is_semantically_idempotent(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        sequence = self.harness.run_twice(scenario)
        try:
            self._assert_current_scenario(sequence.first, scenario)
            self._assert_current_scenario(sequence.second, scenario)
            self.assertEqual(
                sequence.first_state,
                sequence.second_state,
                sequence.second.combined_output,
            )
            bashrc = (sequence.second.home / ".bashrc").read_text(encoding="utf-8")
            self.assertEqual(1, bashrc.splitlines().count(PATH_LINE), sequence.second.combined_output)
        finally:
            shutil.rmtree(sequence.root, ignore_errors=True)

    def test_first_use_bootstrap_works_without_git_manifest_or_package_manager(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        run = self.harness.run_scenario(scenario, mode="bootstrap")
        try:
            diagnostics = run.combined_output
            self.assertEqual(0, run.returncode, diagnostics)
            self.assertEqual([], run.protected_differences, diagnostics)
            self.assertIsNotNone(run.log_file, diagnostics)
            self.assertEqual(0o700, stat.S_IMODE(run.log_dir.stat().st_mode) & 0o777, diagnostics)
            self._assert_installed_state(run, sanitizer_completed=True)
            commands = {entry["command"] for entry in run.trace_entries}
            self.assertEqual({"curl", "id", "uname"}, commands, diagnostics)
            self.assertIn(
                "Next step: Close this terminal window by typing 'exit' and pressing 'Enter'.",
                diagnostics,
            )
            self.assertFalse(list(run.tmp_dir.glob("it140-prepare.*")), diagnostics)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)

    def test_first_use_bootstrap_preserves_current_raw_curl_failure_status(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "external_failure.json")
        run = self.harness.run_scenario(scenario, mode="bootstrap")
        try:
            diagnostics = run.combined_output
            self.assertEqual(22, run.returncode, diagnostics)
            self.assertEqual([], run.protected_differences, diagnostics)
            self.assertIsNotNone(run.log_file, diagnostics)
            self.assertIn("ERROR: Preparation did not complete. Review:", diagnostics)
            self._assert_prior_package_preserved(run)
            self.assertFalse(list(run.tmp_dir.glob("it140-prepare.*")), diagnostics)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)

    def test_download_contract_uses_authorized_https_archive_and_bounded_options(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        run = self.harness.run_scenario(scenario)
        try:
            diagnostics = run.combined_output
            curl_entries = [entry for entry in run.trace_entries if entry["command"] == "curl"]
            self.assertEqual(1, len(curl_entries), diagnostics)
            args = curl_entries[0]["args"]
            self.assertIn("--retry", args, diagnostics)
            self.assertEqual("4", args[args.index("--retry") + 1], diagnostics)
            self.assertIn("--retry-delay", args, diagnostics)
            self.assertIn("--connect-timeout", args, diagnostics)
            self.assertIn("--max-time", args, diagnostics)
            urls = [arg for arg in args if arg.startswith("http")]
            self.assertEqual(1, len(urls), diagnostics)
            self.assertEqual(
                "https://github.com/GC-STEM/it140/archive/refs/heads/main.tar.gz",
                urls[0],
                diagnostics,
            )
        finally:
            shutil.rmtree(run.root, ignore_errors=True)

    def test_pre_overlay_failures_preserve_existing_package(self) -> None:
        for name in ("external_failure.json", "archive_failure.json"):
            scenario = self.harness.load_scenario(SCENARIO_DIR / name)
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                try:
                    self._assert_prior_package_preserved(run)
                finally:
                    shutil.rmtree(run.root, ignore_errors=True)

    def test_sanitizer_failure_occurs_after_current_overlay_boundary(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "sanitize_failure.json")
        run = self.harness.run_scenario(scenario)
        try:
            diagnostics = run.combined_output
            self.assertEqual(1, run.returncode, diagnostics)
            self.assertTrue(
                (run.home / "it140" / "managed" / "version.txt").is_file(), diagnostics
            )
            self.assertFalse((run.home / "it140" / ".git").exists(), diagnostics)
            self.assertFalse((run.home / "it140" / "sanitize-invoked.txt").exists(), diagnostics)
            bashrc = (run.home / ".bashrc").read_text(encoding="utf-8")
            self.assertEqual(1, bashrc.splitlines().count(PATH_LINE), diagnostics)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)

    def _assert_current_scenario(self, run, scenario: dict) -> None:
        expected = scenario["expected"]
        diagnostics = run.combined_output
        self.assertEqual(expected["exit_code"], run.returncode, diagnostics)
        self.assertEqual([], run.protected_differences, diagnostics)
        if expected["log"]:
            self.assertIsNotNone(run.log_file, diagnostics)
            self.assertIsNotNone(run.transcript, diagnostics)
            assert run.log_file is not None
            self.assertEqual(
                0o600,
                stat.S_IMODE(run.log_file.stat().st_mode) & 0o777,
                diagnostics,
            )
            self.assertEqual(
                0o700,
                stat.S_IMODE(run.log_dir.stat().st_mode) & 0o777,
                diagnostics,
            )
        else:
            self.assertIsNone(run.log_file, diagnostics)
        if expected["package_activated"]:
            self.assertTrue(
                (run.home / "it140" / "managed" / "version.txt").is_file(), diagnostics
            )
            self.assertFalse((run.home / "it140" / ".git").exists(), diagnostics)
        else:
            self._assert_prior_package_preserved(run)
        if run.returncode == 0:
            self._assert_installed_state(
                run,
                sanitizer_completed=bool(expected.get("sanitizer_completed", False)),
            )
        self.assertFalse(list(run.tmp_dir.glob("it140-prepare.*")), diagnostics)
        for text in expected.get("contains", []):
            self.assertIn(text, diagnostics)

    def _assert_prior_package_preserved(self, run) -> None:
        diagnostics = run.combined_output
        marker = run.home / "it140" / "scripts" / "cvd" / "legacy_marker.txt"
        self.assertEqual("prior-package-marker\n", marker.read_text(encoding="utf-8"), diagnostics)
        prior_git = run.home / "it140" / ".git" / "HEAD"
        self.assertTrue(prior_git.is_file(), diagnostics)
        self.assertFalse((run.home / "it140" / "managed" / "version.txt").exists(), diagnostics)

    def _assert_installed_state(self, run, *, sanitizer_completed: bool) -> None:
        diagnostics = run.combined_output
        home = run.home
        course_root = home / "it140"
        managed_version = course_root / "managed" / "version.txt"
        self.assertEqual(
            "current-beta-prepare-suite\n",
            managed_version.read_text(encoding="utf-8"),
            diagnostics,
        )
        self.assertFalse((course_root / ".git").exists(), diagnostics)
        for name in (
            "prepare_it140.sh", "install_it140.sh", "configure_it140.sh",
            "verify_it140.sh", "update_it140.sh", "sanitize_CVD.sh",
        ):
            path = course_root / "scripts" / "cvd" / name
            self.assertTrue(path.is_file(), diagnostics)
            self.assertTrue(path.stat().st_mode & stat.S_IXUSR, diagnostics)
        bashrc = (home / ".bashrc").read_text(encoding="utf-8")
        self.assertIn("IT140_USER_BASHRC_SENTINEL=preserve-me", bashrc, diagnostics)
        self.assertEqual(1, bashrc.splitlines().count(PATH_LINE), diagnostics)
        sanitizer_marker = course_root / "sanitize-invoked.txt"
        self.assertEqual(sanitizer_completed, sanitizer_marker.is_file(), diagnostics)
        if sanitizer_completed:
            self.assertEqual("invoked\n", sanitizer_marker.read_text(encoding="utf-8"), diagnostics)
        nested_git = home / "Repos" / "student-work" / ".git" / "HEAD"
        self.assertEqual("ref: refs/heads/main\n", nested_git.read_text(encoding="utf-8"), diagnostics)
        unmanaged = course_root / "local-unmanaged.txt"
        self.assertIn("must be preserved", unmanaged.read_text(encoding="utf-8"), diagnostics)
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        self.assertGreaterEqual(int(state.get("curl_calls", 0)), 1, diagnostics)


if __name__ == "__main__":
    unittest.main()
