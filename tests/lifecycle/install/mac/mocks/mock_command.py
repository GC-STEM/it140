#!/usr/bin/env python3
"""Stateful deterministic command dispatcher for macOS Install tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
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


def create_vscode_app() -> None:
    home = Path(os.environ["HOME"])
    app = home / "Applications" / "Visual Studio Code.app"
    contents = app / "Contents"
    cli = contents / "Resources" / "app" / "bin" / "code"
    cli.parent.mkdir(parents=True, exist_ok=True)
    with (contents / "Info.plist").open("wb") as handle:
        plistlib.dump(
            {
                "CFBundleIdentifier": "com.microsoft.VSCode",
                "CFBundleName": "Visual Studio Code",
                "CFBundlePackageType": "APPL",
            },
            handle,
            sort_keys=True,
        )
    cli.write_text("#!/bin/zsh\nexit 0\n", encoding="utf-8")
    cli.chmod(0o755)


def install_package(state: dict, package: str, adapter: str) -> int:
    count = int(state.get("brew_install_count", 0)) + 1
    state["brew_install_count"] = count
    if int(state.get("brew_install_failure_at", 0) or 0) == count:
        save_state(state)
        return 1

    key = "installed_casks" if adapter == "homebrew_cask" else "installed_formulas"
    installed = set(state.get(key, []))
    installed.add(package)
    state[key] = sorted(installed, key=str.lower)
    save_state(state)

    mock_bin = Path(os.environ["IT140_MOCK_BIN"])
    commands = state.get("package_commands", {}).get(package, [])
    for command in commands:
        if command:
            write_wrapper(mock_bin / command, command)
    if package == "visual-studio-code":
        create_vscode_app()
        write_wrapper(mock_bin / "code", "code")
    return 0


def run_brew(state: dict, args: list[str]) -> int:
    if not args:
        return 0
    if args == ["shellenv"]:
        # The harness PATH already has the deterministic mock directory first.
        return 0
    if args == ["update"]:
        state["brew_update_count"] = int(state.get("brew_update_count", 0)) + 1
        save_state(state)
        return 1 if state.get("brew_update_failure", False) else 0
    if len(args) == 3 and args[0] == "list" and args[1] in {"--formula", "--cask"}:
        package = args[2]
        key = "installed_casks" if args[1] == "--cask" else "installed_formulas"
        return 0 if package in set(state.get(key, [])) else 1
    if len(args) >= 2 and args[0] == "install":
        if args[1] == "--cask" and len(args) >= 3:
            return install_package(state, args[2], "homebrew_cask")
        return install_package(state, args[1], "homebrew_formula")
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print("mock_command.py requires a command name", file=sys.stderr)
        return 2
    command = sys.argv[1]
    args = sys.argv[2:]
    state = load_state()
    trace(command, args)

    if command == "brew":
        return run_brew(state, args)
    if command.startswith("python3"):
        if "-c" in args:
            print("3.12")
        return 0
    # Git, GitHub CLI, VS Code, and any other manifest-declared executable
    # only need to be discoverable/executable during Install validation.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
