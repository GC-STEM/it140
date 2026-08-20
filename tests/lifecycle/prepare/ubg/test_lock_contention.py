#!/usr/bin/env python3
"""Concurrency regression tests for Ubuntu GNOME Bootstrap mutation locking."""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import shutil
import sys
import unittest
from unittest.mock import patch

from runner_ubg import BASH_EXECUTABLE, UbgPrepareHarness, host_is_supported_ubuntu

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"


def supported_test_host() -> bool:
    return (
        sys.platform.startswith("linux")
        and BASH_EXECUTABLE is not None
        and host_is_supported_ubuntu()
        and hasattr(os, "geteuid")
        and os.geteuid() != 0
    )


@unittest.skipUnless(
    supported_test_host(),
    "Ubuntu GNOME Bootstrap lock-contention tests require a supported non-root Ubuntu host.",
)
class UbgPrepareLockContentionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = UbgPrepareHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_bootstrap_refuses_to_mutate_course_state_while_lock_is_held(self) -> None:
        scenario = self.harness.load_scenario(SCENARIO_DIR / "success.json")
        original_execute = self.harness._execute

        def execute_with_lock(*args, **kwargs):
            home = args[2]
            lock_path = home / ".cache" / "it140-ubg-mutation.lock"
            lock_path.parent.mkdir(parents=True, exist_ok=True)
            with lock_path.open("w", encoding="utf-8") as lock_handle:
                fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                try:
                    return original_execute(*args, **kwargs)
                finally:
                    fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)

        with patch.object(self.harness, "_execute", side_effect=execute_with_lock):
            run = self.harness.run_scenario(scenario)
        try:
            diagnostics = run.combined_output
            self.assertEqual(7, run.returncode, diagnostics)
            self.assertIn("Another IT 140 Ubuntu mutation script is running.", diagnostics)
            course_root = run.home / "it140"
            self.assertTrue((course_root / "legacy-package.txt").is_file(), diagnostics)
            self.assertTrue((course_root / "local-unmanaged.txt").is_file(), diagnostics)
            self.assertTrue((course_root / ".git" / "HEAD").is_file(), diagnostics)
            self.assertFalse((course_root / "managed" / "version.txt").exists(), diagnostics)
            self.assertEqual([], run.protected_differences, diagnostics)
            self.assertEqual([], run.trace_entries, diagnostics)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
