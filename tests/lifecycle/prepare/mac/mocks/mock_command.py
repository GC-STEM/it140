#!/usr/bin/env python3
"""Deterministic PATH-level command mocks for macOS Prepare characterization tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
from typing import Any

LIFECYCLE_ROOT = Path(__file__).resolve().parents[3]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))
from common.mock_state import load_state as load_shared_state, save_state as save_shared_state  # noqa: E402

COMMAND = sys.argv[1]
ARGS = sys.argv[2:]
STATE_PATH = Path(os.environ["IT140_MOCK_STATE"])
TRACE_PATH = Path(os.environ["IT140_MOCK_TRACE"])


def load_state() -> dict[str, Any]:
    return load_shared_state(STATE_PATH)


def save_state(state: dict[str, Any]) -> None:
    save_shared_state(STATE_PATH, state)


def trace() -> None:
    with TRACE_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"command": COMMAND, "args": ARGS}, sort_keys=True) + "\n")


def main() -> int:
    state = load_state()
    trace()
    if COMMAND == "id":
        if ARGS == ["-u"]:
            print(state.get("uid", 1000))
        elif ARGS == ["-un"]:
            print(state.get("username", "it140-test"))
        return 0
    if COMMAND == "uname":
        if ARGS == ["-s"]:
            print(state.get("uname_s", "Darwin"))
        elif ARGS == ["-m"]:
            print(state.get("uname_m", "arm64"))
        else:
            print(state.get("uname_s", "Darwin"))
        return 0
    if COMMAND == "sleep":
        calls = list(state.get("sleep_calls", []))
        calls.append(int(ARGS[0]) if ARGS else 0)
        state["sleep_calls"] = calls
        save_state(state)
        return 0
    return 127


if __name__ == "__main__":
    raise SystemExit(main())
