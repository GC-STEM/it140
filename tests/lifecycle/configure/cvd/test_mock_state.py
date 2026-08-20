#!/usr/bin/env python3
"""Concurrency regression tests for lifecycle mock-state transactions."""
from __future__ import annotations

import json
import multiprocessing
from pathlib import Path
import tempfile
import unittest
import sys

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))
from common.mock_state import load_state, save_state  # noqa: E402


def _worker(path_text: str, ready, release, scalar_name: str, list_value: str) -> None:
    path = Path(path_text)
    state = load_state(path)
    ready.put(scalar_name)
    release.wait(10)
    state[scalar_name] = 1
    state.setdefault("items", []).append(list_value)
    save_state(path, state)


def _counter_worker(path_text: str, ready, release) -> None:
    path = Path(path_text)
    state = load_state(path)
    ready.put("ready")
    release.wait(10)
    state["counter"] = int(state.get("counter", 0)) + 1
    save_state(path, state)


class MockStateTransactionTests(unittest.TestCase):
    def test_concurrent_independent_updates_are_merged(self) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-mock-state-") as directory:
            path = Path(directory) / "state.json"
            path.write_text('{"alpha":0,"beta":0,"items":[]}\n', encoding="utf-8")
            context = multiprocessing.get_context("spawn")
            ready = context.Queue()
            release = context.Event()
            processes = [
                context.Process(target=_worker, args=(str(path), ready, release, "alpha", "a")),
                context.Process(target=_worker, args=(str(path), ready, release, "beta", "b")),
            ]
            for process in processes:
                process.start()
            self.assertEqual({ready.get(timeout=10), ready.get(timeout=10)}, {"alpha", "beta"})
            release.set()
            for process in processes:
                process.join(15)
                self.assertEqual(process.exitcode, 0)

            state = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(state["alpha"], 1)
            self.assertEqual(state["beta"], 1)
            self.assertEqual(set(state["items"]), {"a", "b"})

    def test_concurrent_counter_increments_are_accumulated(self) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-mock-state-") as directory:
            path = Path(directory) / "state.json"
            path.write_text('{"counter":0}\n', encoding="utf-8")
            context = multiprocessing.get_context("spawn")
            ready = context.Queue()
            release = context.Event()
            processes = [
                context.Process(target=_counter_worker, args=(str(path), ready, release)),
                context.Process(target=_counter_worker, args=(str(path), ready, release)),
            ]
            for process in processes:
                process.start()
            ready.get(timeout=10)
            ready.get(timeout=10)
            release.set()
            for process in processes:
                process.join(15)
                self.assertEqual(process.exitcode, 0)
            self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["counter"], 2)

    def test_repeated_saves_refresh_the_callers_baseline(self) -> None:
        with tempfile.TemporaryDirectory(prefix="it140-mock-state-") as directory:
            path = Path(directory) / "state.json"
            path.write_text('{"one":0,"two":0}\n', encoding="utf-8")
            state = load_state(path)
            state["one"] = 1
            save_state(path, state)
            state["two"] = 2
            save_state(path, state)
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), {"one": 1, "two": 2})


if __name__ == "__main__":
    unittest.main()
