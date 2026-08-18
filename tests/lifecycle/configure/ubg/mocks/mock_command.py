#!/usr/bin/env python3
"""Stateful deterministic command dispatcher for Ubuntu GNOME Configure tests."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile


def state_path() -> Path:
    return Path(os.environ["IT140_MOCK_STATE"])


def load_state() -> dict:
    return json.loads(state_path().read_text(encoding="utf-8"))


def save_state(state: dict) -> None:
    path = state_path()
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, prefix=path.name + ".", delete=False
    ) as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temporary = Path(handle.name)
    temporary.replace(path)


def trace(command: str, args: list[str]) -> None:
    trace_path = os.environ.get("IT140_MOCK_TRACE")
    if trace_path:
        with Path(trace_path).open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"command": command, "args": args}) + "\n")


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def write_wrapper(path: Path, command_name: str) -> None:
    interpreter = os.environ["IT140_MOCK_PYTHON"]
    dispatcher = os.environ["IT140_MOCK_DISPATCHER"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "#!/bin/bash\n"
        f"exec {shell_quote(interpreter)} {shell_quote(dispatcher)} "
        f"{shell_quote(command_name)} \"$@\"\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def forced_exit(state: dict, command: str) -> int | None:
    configured = state.get("command_exit_codes", {})
    return int(configured[command]) if command in configured else None


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

    if command == "xdg-user-dir":
        if args == ["DESKTOP"]:
            print(Path(os.environ["HOME"]) / "Desktop")
            return 0
        return 1

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
            if state.get("fail_extension_install", False):
                return 1
            if extension in set(state.get("failing_extensions", [])):
                return 1
            if extension not in extensions:
                extensions.append(extension)
                extensions.sort(key=str.lower)
                save_state(state)
            return 0
        return 0

    if command == "python3.12":
        if len(args) == 3 and args[:2] == ["-m", "venv"]:
            write_wrapper(Path(args[2]) / "bin" / "python", "venv_python")
            return 0
        return 0

    if command == "venv_python":
        if len(args) >= 3 and args[:3] == ["-m", "pip", "install"]:
            if state.get("pip_install_failure", False):
                return 1
            packages = state.setdefault("venv_packages", [])
            if "--upgrade" in args:
                start = args.index("--upgrade") + 1
                for package in args[start:]:
                    if package.startswith("-"):
                        continue
                    if package not in packages:
                        packages.append(package)
                packages.sort(key=str.lower)
                save_state(state)
            return 0
        return 0

    if command == "gio":
        if len(args) >= 3 and args[0] == "set" and args[1] == "metadata::custom-icon-name":
            if state.get("gio_set_failure", False):
                return 1
            state["custom_icon"] = args[2]
            save_state(state)
            return 0
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
