#!/usr/bin/env python3
"""Concurrency regression tests for Ubuntu GNOME Configure mutation locking."""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import shutil
import sys
import unittest
from unittest.mock import patch

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))
from common.configure_log import summary_int  # noqa: E402
from runner_ubg import BASH_EXECUTABLE, UbgConfigureHarness  # noqa: E402

HERE = Path(__file__).resolve().parent
FIXTURE_BASE = HERE / "fixtures" / "base"
MOCK_DISPATCHER = HERE / "mocks" / "mock_command.py"
SCENARIO_DIR = HERE / "scenarios"


def supported_ubg_test_host() -> bool:
    if sys.platform != "linux" or not hasattr(os, "geteuid") or os.geteuid() == 0:
        return False
    try:
        os_release = Path("/etc/os-release").read_text(encoding="utf-8")
    except OSError:
        return False
    return "ID=ubuntu" in os_release and 'VERSION_ID="24.04"' in os_release


@unittest.skipUnless(
    supported_ubg_test_host(),
    "Ubuntu GNOME Configure lock-contention tests require a non-root Ubuntu 24.04 host.",
)
class UbgConfigureLockContentionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = UbgConfigureHarness(FIXTURE_BASE, MOCK_DISPATCHER)

    def test_configure_returns_partial_without_managed_changes_when_lock_is_held(self) -> None:
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
            self.assertEqual([], run.protected_differences, diagnostics)
            self.assertIsNotNone(run.transcript, diagnostics)
            assert run.transcript is not None
            self.assertEqual("PARTIAL", run.transcript.summary.get("result"), diagnostics)
            self.assertEqual("No", run.transcript.summary.get("managed changes"), diagnostics)
            self.assertEqual(7, summary_int(run.transcript, "exit code"), diagnostics)
        finally:
            shutil.rmtree(run.root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
