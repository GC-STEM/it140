#!/usr/bin/env python3
"""Deterministic command dispatcher used by macOS Verify tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys


def load_state() -> dict:
    return json.loads(Path(os.environ["IT140_MOCK_STATE"]).read_text(encoding="utf-8"))


def trace(command: str, args: list[str]) -> None:
    trace_path = os.environ.get("IT140_MOCK_TRACE")
    if not trace_path:
        return
    with Path(trace_path).open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"command": command, "args": args}) + "\n")


def main() -> int:
    if len(sys.argv) < 2:
        print("mock_command.py requires a command name", file=sys.stderr)
        return 2

    command = sys.argv[1]
    args = sys.argv[2:]
    state = load_state()
    trace(command, args)

    configured = state.get("command_exit_codes", {})
    if command in configured:
        return int(configured[command])

    if command == "gh":
        if args[:2] == ["auth", "status"]:
            return 0 if state.get("gh_auth", True) else 1
        if args == ["api", "user", "--jq", ".id"]:
            print(state.get("github_id", "12345"))
            return 0
        if args == ["api", "user", "--jq", ".login"]:
            print(state.get("github_login", "it140-test"))
            return 0
        return 0

    if command == "git":
        if args[:3] == ["config", "--global", "--get"] and len(args) >= 4:
            value = state.get("git_config", {}).get(args[3])
            if value is None:
                return 1
            print(str(value).lower() if isinstance(value, bool) else value)
            return 0
        return 0

    if command == "code":
        if args == ["--list-extensions"]:
            print("\n".join(state.get("extensions", [])))
        return 0

    if command == "venv_python":
        if len(args) >= 4 and args[:3] == ["-m", "pip", "show"]:
            package = args[3]
            if package in set(state.get("missing_python_packages", [])):
                return 1
            print(f"Name: {package}\nVersion: 0.0-test")
        return 0

    # Manifest-declared commands and Homebrew only need to exist for Verify.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
