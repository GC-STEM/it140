#!/usr/bin/env python3
"""Stateful deterministic command dispatcher for macOS Configure tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys

LIFECYCLE_ROOT = Path(__file__).resolve().parents[3]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))
from common.mock_state import load_state as load_shared_state, save_state as save_shared_state  # noqa: E402


def state_path() -> Path:
    return Path(os.environ["IT140_MOCK_STATE"])


def load_state() -> dict:
    return load_shared_state(state_path())


def save_state(state: dict) -> None:
    save_shared_state(state_path(), state)


def trace(command: str, args: list[str]) -> None:
    trace_path = os.environ.get("IT140_MOCK_TRACE")
    if not trace_path:
        return
    with Path(trace_path).open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"command": command, "args": args}) + "\n")


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def write_wrapper(path: Path, command_name: str) -> None:
    interpreter = os.environ["IT140_MOCK_PYTHON"]
    dispatcher = os.environ["IT140_MOCK_DISPATCHER"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "#!/bin/zsh\n"
        f"exec {shell_quote(interpreter)} {shell_quote(dispatcher)} "
        f"{shell_quote(command_name)} \"$@\"\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def forced_exit(state: dict, command: str) -> int | None:
    configured = state.get("command_exit_codes", {})
    if command in configured:
        return int(configured[command])
    return None


def main() -> int:
    if len(sys.argv) < 2:
        print("mock_command.py requires a command name", file=sys.stderr)
        return 2

    command = sys.argv[1]
    args = sys.argv[2:]
    state = load_state()
    trace(command, args)

    forced = forced_exit(state, command)
    if forced is not None:
        return forced

    if command == "python3.12":
        if len(args) == 3 and args[:2] == ["-m", "venv"]:
            venv = Path(args[2])
            write_wrapper(venv / "bin" / "python", "venv_python")
            return 0
        real_python = os.environ["IT140_REAL_PYTHON"]
        os.execv(real_python, [real_python, *args])

    if command == "venv_python":
        if len(args) >= 5 and args[:3] == ["-m", "pip", "install"]:
            package = args[-1]
            if package in set(state.get("failing_python_packages", [])):
                return 1
            packages = state.setdefault("venv_packages", [])
            if package not in packages:
                packages.append(package)
                packages.sort(key=str.lower)
                save_state(state)
            return 0
        return 0

    if command == "gh":
        if args[:2] == ["auth", "status"]:
            return 0 if state.get("gh_auth", True) else 1
        if args[:2] == ["auth", "login"]:
            if state.get("gh_login_failure", False):
                return 1
            state["gh_auth"] = True
            save_state(state)
            return 0
        if args[:2] == ["api", "user"]:
            if state.get("gh_api_user_failure", False):
                return 1
            identity = state.get(
                "github_identity",
                {"id": 12345, "login": "it140-test", "name": "IT 140 Test Student"},
            )
            print(json.dumps(identity, separators=(",", ":")))
            return 0
        if args and args[0] == "api":
            return 0
        return 0

    if command == "git":
        config = state.setdefault("git_config", {})
        if args[:3] == ["config", "--global", "--get"] and len(args) >= 4:
            value = config.get(args[3])
            if value is None:
                return 1
            print(str(value).lower() if isinstance(value, bool) else value)
            return 0
        if args[:2] == ["config", "--global"] and len(args) >= 4:
            config[args[2]] = args[3]
            save_state(state)
            return 0
        return 0

    if command == "code":
        extensions = state.setdefault("extensions", [])
        if args == ["--list-extensions"]:
            print("\n".join(extensions))
            return 0
        if len(args) >= 2 and args[0] == "--install-extension":
            extension = args[1]
            if extension in set(state.get("failing_extensions", [])):
                return 1
            if extension not in extensions:
                extensions.append(extension)
                extensions.sort(key=str.lower)
                save_state(state)
            return 0
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
