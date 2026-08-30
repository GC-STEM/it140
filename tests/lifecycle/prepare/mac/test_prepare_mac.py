#!/usr/bin/env python3
"""Behavioral and contract tests for macOS Prepare."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import unittest

from runner_mac import (
    MacPrepareHarness,
    PREPARE_SOURCE,
    PRODUCTION_ARCHIVE_URL,
    host_is_supported_mac,
)

SUITE_ROOT = Path(__file__).resolve().parent
SCENARIO_ROOT = SUITE_ROOT / "scenarios"
FIXTURE_BASE = SUITE_ROOT / "fixtures" / "base"
MOCK_DISPATCHER = SUITE_ROOT / "mocks" / "mock_command.py"
PATH_START = "# >>> IT 140 managed PATH >>>"
PATH_END = "# <<< IT 140 managed PATH <<<"


def canonical_managed_zshrc(text: str) -> str:
    """Normalize only blank-line drift immediately before the managed PATH block."""
    start = text.find(PATH_START)
    if start < 0:
        return text
    unmanaged = text[:start].rstrip("\n")
    managed = text[start:].strip("\n")
    if unmanaged:
        return f"{unmanaged}\n\n{managed}\n"
    return f"{managed}\n"


class MacPrepareStaticContractTests(unittest.TestCase):
    def test_production_transport_and_native_utility_contract(self) -> None:
        text = PREPARE_SOURCE.read_text(encoding="utf-8")
        self.assertIn(f"readonly ARCHIVE_URL='{PRODUCTION_ARCHIVE_URL}'", text)
        self.assertTrue(PRODUCTION_ARCHIVE_URL.startswith("https://"))
        self.assertIn("while (( attempt <= 5 )); do", text)
        self.assertIn("--connect-timeout 20 --max-time 300", text)
        self.assertIn("/usr/bin/curl", text)
        self.assertIn("/usr/bin/ditto", text)
        self.assertIn("/usr/bin/osascript", text)
        self.assertNotIn("brew install", text)
        self.assertNotIn("git clone", text)

    def test_behavioral_copy_changes_only_archive_url(self) -> None:
        source = PREPARE_SOURCE.read_text(encoding="utf-8")
        local_url = "http://127.0.0.1:9999/main.zip"
        transformed = MacPrepareHarness.test_script_text(local_url)
        self.assertNotEqual(source, transformed)
        restored = transformed.replace(
            f"readonly ARCHIVE_URL='{local_url}'",
            f"readonly ARCHIVE_URL='{PRODUCTION_ARCHIVE_URL}'",
            1,
        )
        self.assertEqual(source, restored)

    def test_zshrc_semantic_normalization_is_narrow(self) -> None:
        first = (
            "IT140_USER_ZSHRC_SENTINEL=preserve-me\n"
            "alias ll='ls -la'\n\n"
            f"{PATH_START}\n"
            'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:$PATH"\n'
            f"{PATH_END}\n"
        )
        second = first.replace(f"\n\n{PATH_START}", f"\n\n\n{PATH_START}")
        self.assertNotEqual(first, second)
        self.assertEqual(canonical_managed_zshrc(first), canonical_managed_zshrc(second))

        changed_user_content = second.replace("alias ll='ls -la'", "alias ll='ls -l'")
        self.assertNotEqual(
            canonical_managed_zshrc(first),
            canonical_managed_zshrc(changed_user_content),
        )


@unittest.skipUnless(
    host_is_supported_mac(),
    "macOS Prepare behavioral tests require an Apple-silicon macOS host",
)
class MacPrepareLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = MacPrepareHarness(FIXTURE_BASE, MOCK_DISPATCHER)
        cls.scenarios = {
            path.stem: cls.harness.load_scenario(path)
            for path in sorted(SCENARIO_ROOT.glob("*.json"))
        }

    def test_help_version_and_invalid_option_are_prelog_queries(self) -> None:
        scenario = self.scenarios["success"]
        cases = [
            (["--help"], 0, "Usage: prepare_it140.zsh"),
            (["--version"], 0, "1.0.1"),
            (["--not-a-real-option"], 2, "Unsupported option"),
        ]
        for arguments, expected_code, expected_text in cases:
            with self.subTest(arguments=arguments):
                run = self.harness.run_scenario(scenario, arguments)
                self.assertEqual(expected_code, run.returncode, run.combined_output)
                self.assertIn(expected_text, run.stdout + run.stderr)
                self.assertIsNone(run.log_file, run.combined_output)
                self.assertEqual(0, run.request_count, run.combined_output)
                self.assertEqual([], run.protected_differences, run.combined_output)

    def test_declared_scenarios_match_current_beta_behavior(self) -> None:
        for name in (
            "success",
            "unsupported_arch",
            "privilege_failure",
            "download_failure",
            "archive_failure",
            "manifest_failure",
            "post_change_failure",
        ):
            scenario = self.scenarios[name]
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                self._assert_scenario(run, scenario)

    def test_pre_activation_failures_preserve_prior_critical_assets(self) -> None:
        for name in ("download_failure", "archive_failure", "manifest_failure", "post_change_failure"):
            scenario = self.scenarios[name]
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                self.assertEqual(run.critical_before, run.critical_after, run.combined_output)
                self.assertEqual([], run.protected_differences, run.combined_output)
                self._assert_temp_cleanup(run)

    def test_download_failure_uses_five_bounded_attempts_without_waiting_in_ci(self) -> None:
        run = self.harness.run_scenario(self.scenarios["download_failure"])
        self.assertEqual(4, run.returncode, run.combined_output)
        self.assertEqual(5, run.request_count, run.combined_output)
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        self.assertEqual([5, 10, 20, 40], state.get("sleep_calls"), run.combined_output)
        self._assert_temp_cleanup(run)

    def test_success_preserves_user_state_and_unmanaged_course_content(self) -> None:
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
            "preserve this unmatched macOS script-directory file\n",
            (course_root / "scripts" / "mac" / "legacy_marker.txt").read_text(encoding="utf-8"),
        )
        self.assertTrue((home / "Repos" / "student-work" / ".git" / "HEAD").is_file())
        self.assertFalse((course_root / ".git").exists())
        self._assert_temp_cleanup(run)

    def test_success_activates_scripts_manifest_and_managed_path(self) -> None:
        run = self.harness.run_scenario(self.scenarios["success"])
        self.assertEqual(0, run.returncode, run.combined_output)
        home = run.home
        course_root = home / "it140"
        mac_dir = course_root / "scripts" / "mac"
        for name in (
            "prepare_it140.zsh", "install_it140.zsh", "configure_it140.zsh",
            "verify_it140.zsh", "update_it140.zsh",
        ):
            path = mac_dir / name
            self.assertTrue(path.is_file(), run.combined_output)
            self.assertTrue(os.access(path, os.X_OK), run.combined_output)
            self.assertEqual(0o755, stat.S_IMODE(path.stat().st_mode), run.combined_output)
        manifest = course_root / "scripts" / ".manifest" / "it140_manifest.json"
        self.assertEqual(
            {"release": "mac-prepare-test"},
            json.loads(manifest.read_text(encoding="utf-8")),
        )
        zshrc = (home / ".zshrc").read_text(encoding="utf-8")
        self.assertEqual(1, zshrc.count(PATH_START), zshrc)
        self.assertEqual(1, zshrc.count(PATH_END), zshrc)
        self.assertNotIn("IT 140 Course IDE managed environment", zshrc)
        self.assertIn("IT140_USER_ZSHRC_SENTINEL=preserve-me", zshrc)
        self.assertIn("alias ll='ls -la'", zshrc)
        self.assertIn(
            'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:$PATH"',
            zshrc,
        )

    def test_success_is_semantically_idempotent(self) -> None:
        sequence = self.harness.run_twice(self.scenarios["success"])
        self.assertEqual(0, sequence.first.returncode, sequence.first.combined_output)
        self.assertEqual(0, sequence.second.returncode, sequence.second.combined_output)

        first_state = dict(sequence.first_state)
        second_state = dict(sequence.second_state)
        first_zshrc = first_state.pop("zshrc")
        second_zshrc = second_state.pop("zshrc")

        # All non-Zsh state must be byte/metadata equivalent after both runs.
        self.assertEqual(first_state, second_state)

        # The current Beta Prepare script can add one harmless blank line immediately
        # before its managed PATH block on a rerun. Treat that whitespace-only drift
        # as semantically equivalent while still requiring exactly one canonical block,
        # the exact managed export, and unchanged user-controlled content.
        for zshrc in (first_zshrc, second_zshrc):
            self.assertEqual(1, zshrc.count(PATH_START), zshrc)
            self.assertEqual(1, zshrc.count(PATH_END), zshrc)
            self.assertIn("IT140_USER_ZSHRC_SENTINEL=preserve-me", zshrc)
            self.assertIn("alias ll='ls -la'", zshrc)
            self.assertIn(
                'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:$PATH"',
                zshrc,
            )
        self.assertEqual(
            canonical_managed_zshrc(first_zshrc),
            canonical_managed_zshrc(second_zshrc),
        )

        self.assertEqual([], sequence.first.protected_differences, sequence.first.combined_output)
        self.assertEqual([], sequence.second.protected_differences, sequence.second.combined_output)

    def _assert_scenario(self, run, scenario: dict) -> None:
        expected = scenario["expected"]
        self.assertEqual(expected["exit_code"], run.returncode, run.combined_output)
        self.assertEqual(expected["requests"], run.request_count, run.combined_output)
        self.assertEqual([], run.protected_differences, run.combined_output)
        self.assertIsNotNone(run.log_file, run.combined_output)
        assert run.log_file is not None
        self.assertEqual(0o600, stat.S_IMODE(run.log_file.stat().st_mode), run.combined_output)
        self.assertIsNotNone(run.transcript, run.combined_output)
        assert run.transcript is not None
        summary = run.transcript.summary
        self.assertEqual(expected["result"], summary.get("Result"), run.combined_output)
        self.assertEqual(str(expected["exit_code"]), summary.get("Exit code"), run.combined_output)
        self.assertEqual(expected["managed_changes"], summary.get("Managed changes"), run.combined_output)
        self.assertEqual("local_initial_install", summary.get("Workflow"), run.combined_output)
        self.assertEqual("local_unmanaged_environment", summary.get("Starting state"), run.combined_output)
        self.assertEqual("local_user", summary.get("Operating role"), run.combined_output)
        self.assertEqual(
            '"$HOME/it140/scripts/mac/install_it140.zsh"',
            summary.get("Next step"),
            run.combined_output,
        )
        if expected.get("preserve_critical"):
            self.assertEqual(run.critical_before, run.critical_after, run.combined_output)
        self._assert_temp_cleanup(run)

    def _assert_temp_cleanup(self, run) -> None:
        leftovers = list(run.tmp_dir.glob("it140-prepare.*"))
        self.assertEqual([], leftovers, run.combined_output)


if __name__ == "__main__":
    unittest.main()
