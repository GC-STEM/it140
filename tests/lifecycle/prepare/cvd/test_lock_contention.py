#!/usr/bin/env python3
"""Concurrency regression tests for CVD Prepare mutation locking."""
from __future__ import annotations

import fcntl
from pathlib import Path
import shutil
import sys
import unittest
from unittest.mock import patch

from runner_cvd import BASH_EXECUTABLE, CvdPrepareHarness, host_is_ubuntu

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"


def supported_test_host() -> bool:
    return sys.platform.startswith("linux") and BASH_EXECUTABLE is not None and host_is_ubuntu()


@unittest.skipUnless(
    supported_test_host(),
    "CVD Prepare lock-contention tests require an Ubuntu host with Bash.",
)
class CvdPrepareLockContentionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = CvdPrepareHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def _run_with_lock_held(self, scenario, *, mode: str = "refresh"):
        original_execute = self.harness._execute

        def execute_with_lock(*args, **kwargs):
            home = args[2]
            lock_path = home / ".cache" / "it140-cvd-mutation.lock"
            lock_path.parent.mkdir(parents=True, exist_ok=True)
            with lock_path.open("w", encoding="utf-8") as lock_handle:
                fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                try:
                    return original_execute(*args, **kwargs)
                finally:
                    fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)

        with patch.object(self.harness, "_execute", side_effect=execute_with_lock):
            return self.harness.run_scenario(scenario, mode=mode)

    def _assert_lock_rejected_before_overlay(self, run) -> None:
        diagnostics = run.combined_output
        self.assertEqual(7, run.returncode, diagnostics)
        self.assertIn("Another IT 140 CVD mutation script is running.", diagnostics)
        self.assertTrue((run.home / "it140" / ".git" / "HEAD").is_file(), diagnostics)
        self.assertTrue(
            (run.home / "it140" / "scripts" / "cvd" / "legacy_marker.txt").is_file(),
            diagnostics,
        )
        self.assertFalse((run.home / "it140" / "managed" / "version.txt").exists(), diagnostics)
        self.assertEqual([], run.protected_differences, diagnostics)
        self.assertFalse(list(run.tmp_dir.glob("it140-prepare.*")), diagnostics)

    def test_refresh_refuses_to_replace_course_files_while_mutation_lock_is_held(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        run = self._run_with_lock_held(scenario)
        try:
            self._assert_lock_rejected_before_overlay(run)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)

    def test_first_use_bootstrap_refuses_to_replace_course_files_while_lock_is_held(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        run = self._run_with_lock_held(scenario, mode="bootstrap")
        try:
            self._assert_lock_rejected_before_overlay(run)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
