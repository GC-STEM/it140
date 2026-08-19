#!/usr/bin/env python3
"""Deterministic command dispatcher for Ubuntu GNOME Prepare tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import stat
import sys
from typing import Any

STATE_PATH = Path(os.environ["IT140_MOCK_STATE"])
TRACE_PATH = Path(os.environ["IT140_MOCK_TRACE"])
COMMAND = os.environ.get("IT140_MOCK_COMMAND", Path(sys.argv[0]).name)
ARGS = sys.argv[1:]


def load_state() -> dict[str, Any]:
    return json.loads(STATE_PATH.read_text(encoding="utf-8"))


def save_state(state: dict[str, Any]) -> None:
    STATE_PATH.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def trace(command: str, args: list[str]) -> None:
    with TRACE_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"command": command, "args": args}, sort_keys=True) + "\n")


def write_git_wrapper() -> None:
    mock_bin = Path(os.environ["IT140_MOCK_BIN"])
    wrapper = mock_bin / "git"
    wrapper.write_text(
        "#!/usr/bin/env bash\n"
        "export IT140_MOCK_COMMAND='git'\n"
        'exec "$IT140_MOCK_PYTHON" "$IT140_MOCK_DISPATCHER" "$@"\n',
        encoding="utf-8",
    )
    wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run_git(state: dict[str, Any], args: list[str]) -> int:
    if args[:2] != ["clone", "--depth"] or len(args) < 5:
        return int(state.get("git_other_exit_code", 0))
    state["git_clone_calls"] = int(state.get("git_clone_calls", 0)) + 1
    save_state(state)
    if state.get("fail_points", {}).get("git_clone"):
        return int(state.get("git_clone_exit_code", 128))
    source = Path(state["repo_source"])
    target = Path(args[-1])
    shutil.copytree(source, target)
    return 0


def run_sudo(state: dict[str, Any], args: list[str]) -> int:
    state["sudo_calls"] = int(state.get("sudo_calls", 0)) + 1
    save_state(state)
    if state.get("fail_points", {}).get("sudo"):
        return int(state.get("sudo_exit_code", 100))
    if "install" in args and "git" in args:
        state["git_installed"] = True
        save_state(state)
        write_git_wrapper()
    return 0


def main() -> int:
    state = load_state()
    trace(COMMAND, ARGS)
    if COMMAND == "git":
        return run_git(state, ARGS)
    if COMMAND == "sudo":
        return run_sudo(state, ARGS)
    return 127


if __name__ == "__main__":
    raise SystemExit(main())
