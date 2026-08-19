#!/usr/bin/env python3
"""Characterization/regression tests for Ubuntu GNOME Prepare bootstrap."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import stat
import sys
import unittest

from runner_ubg import (  # noqa: E402
    BASH_EXECUTABLE,
    BOOTSTRAP_SOURCE,
    UbgPrepareHarness,
    host_is_supported_ubuntu,
)

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"
PATH_LINE = 'export PATH="$HOME/it140/scripts/nix/ubg:$PATH"'


def supported_test_host() -> bool:
    return (
        sys.platform.startswith("linux")
        and BASH_EXECUTABLE is not None
        and host_is_supported_ubuntu()
        and hasattr(os, "geteuid")
        and os.geteuid() != 0
    )


class UbgPrepareStaticContractTests(unittest.TestCase):
    def test_deployed_script_directory_matches_repository_ubg_path(self) -> None:
        text = BOOTSTRAP_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("scripts/nix/Ubuntu", text)
        self.assertIn('$COURSE_ROOT/scripts/nix/ubg/', text)
        self.assertIn('$HOME/it140/scripts/nix/ubg:$PATH', text)


@unittest.skipUnless(
    supported_test_host(),
    "Ubuntu GNOME Prepare behavioral tests require a supported non-root Ubuntu host with Bash.",
)
class UbgPrepareLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = UbgPrepareHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_declared_scenarios_match_current_bootstrap_behavior(self) -> None:
        for name in (
            "success.json",
            "clone_failure.json",
            "git_install_success.json",
            "git_install_failure.json",
            "gnome_warning.json",
        ):
            scenario = self.harness.load_scenario(SCENARIO_DIR / name)
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                try:
                    self._assert_scenario(run, scenario)
                finally:
                    shutil.rmtree(run.root, ignore_errors=True)

    def test_successful_bootstrap_is_semantically_idempotent(self) -> None:
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
            bashrc = (sequence.second.home / ".bashrc").read_text(encoding="utf-8")
            self.assertEqual(1, bashrc.splitlines().count(PATH_LINE), sequence.second.combined_output)
        finally:
            shutil.rmtree(sequence.root, ignore_errors=True)

    def test_clone_contract_uses_authorized_repository_and_shallow_clone(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        run = self.harness.run_scenario(scenario)
        try:
            diagnostics = run.combined_output
            entries = [entry for entry in run.trace_entries if entry["command"] == "git"]
            self.assertEqual(1, len(entries), diagnostics)
            args = entries[0]["args"]
            self.assertEqual("clone", args[0], diagnostics)
            self.assertIn("--depth", args, diagnostics)
            self.assertEqual("1", args[args.index("--depth") + 1], diagnostics)
            self.assertIn("https://github.com/GC-STEM/it140.git", args, diagnostics)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)

    def test_missing_git_uses_current_apt_bootstrap_then_clones(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "git_install_success.json")
        run = self.harness.run_scenario(scenario)
        try:
            diagnostics = run.combined_output
            self.assertEqual(0, run.returncode, diagnostics)
            commands = [entry["command"] for entry in run.trace_entries]
            self.assertGreaterEqual(commands.count("sudo"), 2, diagnostics)
            self.assertIn("git", commands, diagnostics)
            state = json.loads(run.state_file.read_text(encoding="utf-8"))
            self.assertTrue(state.get("git_installed"), diagnostics)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)

    def test_pre_activation_failures_preserve_prior_course_package(self) -> None:
        for name in ("clone_failure.json", "git_install_failure.json"):
            scenario = self.harness.load_scenario(SCENARIO_DIR / name)
            with self.subTest(scenario=scenario["id"]):
                run = self.harness.run_scenario(scenario)
                try:
                    self._assert_prior_package_preserved(run)
                finally:
                    shutil.rmtree(run.root, ignore_errors=True)

    def _assert_scenario(self, run, scenario: dict) -> None:
        diagnostics = run.combined_output
        expected = scenario["expected"]
        self.assertEqual(expected["exit_code"], run.returncode, diagnostics)
        self.assertEqual([], run.protected_differences, diagnostics)
        self.assertIsNotNone(run.log_file, diagnostics)
        self.assertIsNotNone(run.transcript, diagnostics)
        assert run.log_file is not None
        self.assertEqual(0o600, stat.S_IMODE(run.log_file.stat().st_mode) & 0o777, diagnostics)
        self.assertEqual(0o700, stat.S_IMODE(run.log_dir.stat().st_mode) & 0o777, diagnostics)
        for text in expected.get("contains", []):
            self.assertIn(text, diagnostics)
        self.assertFalse(list(run.tmp_dir.iterdir()), diagnostics)

        if run.returncode == 0:
            self._assert_installed_state(run)
        else:
            self._assert_prior_package_preserved(run)

    def _assert_prior_package_preserved(self, run) -> None:
        diagnostics = run.combined_output
        course_root = run.home / "it140"
        self.assertTrue((course_root / "legacy-package.txt").is_file(), diagnostics)
        self.assertTrue((course_root / "local-unmanaged.txt").is_file(), diagnostics)
        self.assertTrue((course_root / ".git" / "HEAD").is_file(), diagnostics)
        bashrc = (run.home / ".bashrc").read_text(encoding="utf-8")
        self.assertNotIn(PATH_LINE, bashrc.splitlines(), diagnostics)

    def _assert_installed_state(self, run) -> None:
        diagnostics = run.combined_output
        home = run.home
        course_root = home / "it140"
        self.assertEqual(
            "ubg-prepare-characterization\n",
            (course_root / "managed" / "version.txt").read_text(encoding="utf-8"),
            diagnostics,
        )
        self.assertFalse((course_root / ".git").exists(), diagnostics)
        # Characterize current bootstrap behavior: it replaces all prior
        # course-root content except logs before copying the fresh package.
        self.assertFalse((course_root / "legacy-package.txt").exists(), diagnostics)
        self.assertFalse((course_root / "local-unmanaged.txt").exists(), diagnostics)
        for name in (
            "bootstrap_ubg.sh", "setup_ubg.sh", "config_ubg.sh",
            "verify_ubg.sh", "update_ubg.sh",
        ):
            path = course_root / "scripts" / "nix" / "ubg" / name
            self.assertTrue(path.is_file(), diagnostics)
            self.assertTrue(path.stat().st_mode & stat.S_IXUSR, diagnostics)
        bashrc = (home / ".bashrc").read_text(encoding="utf-8")
        self.assertIn("IT140_USER_BASHRC_SENTINEL=preserve-me", bashrc, diagnostics)
        self.assertEqual(1, bashrc.splitlines().count(PATH_LINE), diagnostics)
        nested_git = home / "Repos" / "student-work" / ".git" / "HEAD"
        self.assertEqual("ref: refs/heads/main\n", nested_git.read_text(encoding="utf-8"), diagnostics)


if __name__ == "__main__":
    unittest.main()
