#!/usr/bin/env python3
"""Behavioral and source-contract tests for Windows Prepare."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import unittest

from runner_win import (
    PREPARE_SOURCE,
    PRODUCTION_ARCHIVE_URL,
    WinPrepareHarness,
    host_is_windows,
)

SUITE_ROOT = Path(__file__).resolve().parent
SCENARIO_ROOT = SUITE_ROOT / "scenarios"
FIXTURE_BASE = SUITE_ROOT / "fixtures" / "base"


class WinPrepareStaticContractTests(unittest.TestCase):
    def test_production_bootstrap_contract(self) -> None:
        text = PREPARE_SOURCE.read_text(encoding="utf-8-sig")
        self.assertIn(f'$RepositoryArchive = "{PRODUCTION_ARCHIVE_URL}"', text)
        self.assertTrue(PRODUCTION_ARCHIVE_URL.startswith("https://"))
        self.assertIn("Get-Command curl.exe", text)
        self.assertIn("--retry 5", text)
        self.assertIn("--retry-delay 5", text)
        self.assertIn("--retry-all-errors", text)
        self.assertIn("--continue-at -", text)
        self.assertIn("Invoke-WebRequest -Uri $RepositoryArchive", text)
        self.assertIn("Expand-Archive -LiteralPath $ArchivePath", text)
        self.assertIn("Copy-Item -Destination $CourseRoot -Recurse -Force", text)
        self.assertIn('Join-Path $CourseRoot ".git"', text)
        self.assertIn("Set-UserPathEntry -PathEntry $PlatformScriptDirectory", text)
        self.assertNotIn("IT140_PREPARE_TEST_", text)
        bootstrap_prefix = text.split("function Get-NormalizedPathEntry", 1)[0]
        self.assertNotIn("param(", bootstrap_prefix)
        self.assertNotIn("[CmdletBinding()]", bootstrap_prefix)
        self.assertNotIn("it140_manifest.json", text)

    def test_behavioral_copy_changes_only_isolation_bindings(self) -> None:
        source = PREPARE_SOURCE.read_text(encoding="utf-8-sig")
        local_url = "http://127.0.0.1:9999/main.zip"
        transformed = WinPrepareHarness.test_script_text(local_url)
        self.assertNotEqual(source, transformed)
        restored = transformed
        for original, replacement, _ in reversed(
            WinPrepareHarness.transformation_pairs(local_url)
        ):
            restored = restored.replace(replacement, original)
        self.assertEqual(source, restored)


@unittest.skipUnless(
    host_is_windows(),
    "Windows Prepare behavioral tests require a Windows PowerShell host",
)
class WinPrepareLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = WinPrepareHarness(FIXTURE_BASE)
        cls.scenarios = {
            path.stem: cls.harness.load_scenario(path)
            for path in sorted(SCENARIO_ROOT.glob("*.json"))
        }

    def test_declared_scenarios_match_current_beta_behavior(self) -> None:
        for name in (
            "success",
            "iwr_success",
            "download_failure",
            "archive_failure",
            "missing_windows_scripts",
            "path_failure",
        ):
            scenario = self.scenarios[name]
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                self._assert_scenario(run, scenario)

    def test_success_uses_curl_branch_and_fallback_uses_invoke_web_request(self) -> None:
        self.assertIsNotNone(shutil.which("curl.exe"))

        curl_run = self.harness.run_scenario(self.scenarios["success"])
        self.assertEqual(0, curl_run.returncode, curl_run.combined_output)
        self.assertEqual(1, len(curl_run.user_agents), curl_run.combined_output)
        self.assertTrue(
            curl_run.user_agents[0].lower().startswith("curl/"),
            curl_run.combined_output,
        )

        iwr_run = self.harness.run_scenario(self.scenarios["iwr_success"])
        self.assertEqual(0, iwr_run.returncode, iwr_run.combined_output)
        self.assertEqual(1, len(iwr_run.user_agents), iwr_run.combined_output)
        self.assertFalse(
            iwr_run.user_agents[0].lower().startswith("curl/"),
            iwr_run.combined_output,
        )

    def test_pre_overlay_failures_preserve_prior_course_payload(self) -> None:
        for name in ("download_failure", "archive_failure"):
            scenario = self.scenarios[name]
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                self.assertEqual(run.course_before, run.course_after, run.combined_output)
                self.assertEqual([], run.protected_differences, run.combined_output)
                self.assertIsNone(run.user_path_after, run.combined_output)
                self._assert_temp_cleanup(run)

    def test_post_overlay_failures_characterize_no_rollback(self) -> None:
        for name in ("missing_windows_scripts", "path_failure"):
            scenario = self.scenarios[name]
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                self.assertNotEqual(run.course_before, run.course_after, run.combined_output)
                self.assertEqual([], run.protected_differences, run.combined_output)
                managed = run.home / "it140" / "managed" / "version.txt"
                self.assertTrue(managed.is_file(), run.combined_output)
                self.assertEqual(
                    "windows-prepare-characterization\n",
                    managed.read_text(encoding="utf-8"),
                )
                self._assert_temp_cleanup(run)

    def test_success_preserves_user_state_and_unmatched_course_content(self) -> None:
        run = self.harness.run_scenario(self.scenarios["success"])
        self.assertEqual(0, run.returncode, run.combined_output)
        self.assertEqual([], run.protected_differences, run.combined_output)
        home = run.home
        course_root = home / "it140"
        self.assertEqual(
            "preserve this course-root file\n",
            (course_root / "local-unmanaged.txt").read_text(encoding="utf-8"),
        )
        self.assertEqual(
            "prior Windows bootstrap package marker\n",
            (course_root / "prior-package.txt").read_text(encoding="utf-8"),
        )
        self.assertTrue((home / "Repos" / "student-work" / ".git" / "HEAD").is_file())
        self.assertFalse((course_root / ".git").exists())
        self._assert_temp_cleanup(run)

    def test_success_activates_windows_scripts_and_converges_user_path(self) -> None:
        run = self.harness.run_scenario(self.scenarios["success"])
        self.assertEqual(0, run.returncode, run.combined_output)
        win_dir = run.home / "it140" / "scripts" / "win"
        for name in (
            "prepare_it140.ps1",
            "install_it140.ps1",
            "configure_it140.ps1",
            "verify_it140.ps1",
            "update_it140.ps1",
        ):
            self.assertTrue((win_dir / name).is_file(), run.combined_output)

        self.assertIsNotNone(run.user_path_after, run.combined_output)
        assert run.user_path_after is not None
        entries = [entry for entry in run.user_path_after.split(";") if entry]
        normalized_target = str(win_dir.resolve()).rstrip("\\").casefold()
        target_matches = [
            entry
            for entry in entries
            if entry.rstrip("\\").casefold() == normalized_target
        ]
        self.assertEqual(1, len(target_matches), run.combined_output)
        self.assertEqual(str(win_dir.resolve()), entries[0], run.combined_output)
        self.assertIn(r"C:\UserTools", entries, run.combined_output)
        self.assertIn(r"C:\AnotherTool", entries, run.combined_output)

    def test_success_is_semantically_idempotent(self) -> None:
        sequence = self.harness.run_twice(self.scenarios["success"])
        self.assertEqual(0, sequence.first.returncode, sequence.first.combined_output)
        self.assertEqual(0, sequence.second.returncode, sequence.second.combined_output)
        self.assertEqual(sequence.first_state, sequence.second_state)
        self.assertEqual([], sequence.first.protected_differences, sequence.first.combined_output)
        self.assertEqual([], sequence.second.protected_differences, sequence.second.combined_output)
        self.assertEqual(2, sequence.second.request_count, sequence.second.combined_output)

    def _assert_scenario(self, run, scenario: dict) -> None:
        expected = scenario["expected"]
        self.assertEqual(expected["exit_code"], run.returncode, run.combined_output)
        self.assertEqual(expected["requests"], run.request_count, run.combined_output)
        self.assertEqual([], run.protected_differences, run.combined_output)
        self.assertIsNotNone(run.log_file, run.combined_output)
        self.assertIsNotNone(run.transcript, run.combined_output)
        assert run.transcript is not None
        self.assertIn("IT 140 WINDOWS BOOTSTRAP", run.transcript.text)
        if expected["exit_code"] == 0:
            self.assertIn("[SUCCESS]", run.transcript.text)
        if expected.get("preserve_course"):
            self.assertEqual(run.course_before, run.course_after, run.combined_output)
        if expected.get("package_activated"):
            self.assertTrue(
                (run.home / "it140" / "managed" / "version.txt").is_file(),
                run.combined_output,
            )
        if expected.get("path_updated"):
            self.assertIsNotNone(run.user_path_after, run.combined_output)
        self._assert_temp_cleanup(run)

    def _assert_temp_cleanup(self, run) -> None:
        leftovers = list(run.temp_parent.glob("it140-bootstrap-*"))
        self.assertEqual([], leftovers, run.combined_output)


if __name__ == "__main__":
    unittest.main()
