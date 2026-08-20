#!/usr/bin/env python3
"""Deterministic command dispatcher for CVD Prepare characterization tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import sys
from typing import Any

LIFECYCLE_ROOT = Path(__file__).resolve().parents[3]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))
from common.mock_state import load_state as load_shared_state, save_state as save_shared_state  # noqa: E402

STATE_PATH = Path(os.environ["IT140_MOCK_STATE"])
TRACE_PATH = Path(os.environ["IT140_MOCK_TRACE"])
COMMAND = os.environ.get("IT140_MOCK_COMMAND", Path(sys.argv[0]).name)
ARGS = sys.argv[1:]


def load_state() -> dict[str, Any]:
    return load_shared_state(STATE_PATH)


def save_state(state: dict[str, Any]) -> None:
    save_shared_state(STATE_PATH, state)


def trace(command: str, args: list[str]) -> None:
    with TRACE_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"command": command, "args": args}, sort_keys=True) + "\n")


def run_id(state: dict[str, Any], args: list[str]) -> int:
    if args == ["-u"]:
        print(state.get("uid", 1000))
        return 0
    if args == ["-un"]:
        print(state.get("username", "ubuntu"))
        return 0
    return 0


def run_uname(state: dict[str, Any], args: list[str]) -> int:
    if args == ["-s"]:
        print(state.get("uname_s", "Linux"))
        return 0
    if args == ["-m"]:
        print(state.get("uname_m", "x86_64"))
        return 0
    print(state.get("uname_s", "Linux"))
    return 0


def run_curl(state: dict[str, Any], args: list[str]) -> int:
    state["curl_calls"] = int(state.get("curl_calls", 0)) + 1
    save_state(state)
    if state.get("fail_points", {}).get("curl"):
        return int(state.get("curl_exit_code", 22))
    if "--output" not in args:
        return 2
    target = Path(args[args.index("--output") + 1])
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(state["archive_path"]), target)
    return 0


def main() -> int:
    state = load_state()
    trace(COMMAND, ARGS)
    if COMMAND == "id":
        return run_id(state, ARGS)
    if COMMAND == "uname":
        return run_uname(state, ARGS)
    if COMMAND == "curl":
        return run_curl(state, ARGS)
    return 127


if __name__ == "__main__":
    raise SystemExit(main())
