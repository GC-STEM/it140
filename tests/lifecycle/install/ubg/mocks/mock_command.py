#!/usr/bin/env python3
"""Command dispatcher for isolated Ubuntu GNOME Install lifecycle tests."""
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
TEST_ROOT = Path(os.environ["IT140_INSTALL_TEST_ROOT"])
MOCK_BIN = Path(os.environ["IT140_MOCK_BIN"])
DISPATCHER = Path(os.environ["IT140_MOCK_DISPATCHER"])
PYTHON = os.environ["IT140_MOCK_PYTHON"]
COMMAND = os.environ.get("IT140_MOCK_COMMAND", Path(sys.argv[0]).name)
ARGS = sys.argv[1:]

PACKAGE_COMMANDS = {
    "git": ["git"],
    "gh": ["gh"],
    "python3.12": ["python3.12"],
    "code": ["code"],
}


def load_state() -> dict[str, Any]:
    return json.loads(STATE_PATH.read_text(encoding="utf-8"))


def save_state(state: dict[str, Any]) -> None:
    STATE_PATH.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def trace(command: str, args: list[str]) -> None:
    with TRACE_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"command": command, "args": args}, sort_keys=True) + "\n")


def wrapper_text(command_name: str) -> str:
    return (
        "#!/usr/bin/env bash\n"
        f"export IT140_MOCK_COMMAND={command_name!r}\n"
        'exec "$IT140_MOCK_PYTHON" "$IT140_MOCK_DISPATCHER" "$@"\n'
    )


def ensure_command_wrapper(command_name: str) -> None:
    path = MOCK_BIN / command_name
    path.write_text(wrapper_text(command_name), encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def remove_command_wrapper(command_name: str) -> None:
    path = MOCK_BIN / command_name
    if path.exists() or path.is_symlink():
        path.unlink()


def sync_package_commands(state: dict[str, Any]) -> None:
    installed = set(state.get("installed_packages", []))
    skipped = set(state.get("skip_install_packages", []))
    for package, command_names in PACKAGE_COMMANDS.items():
        present = package in installed and package not in skipped
        for command_name in command_names:
            if present:
                ensure_command_wrapper(command_name)
            else:
                remove_command_wrapper(command_name)


def mapped_system_path(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        return path
    root_text = str(TEST_ROOT)
    text = str(path)
    if text == root_text or text.startswith(root_text + os.sep):
        return path
    if text.startswith("/etc/") or text.startswith("/usr/share/"):
        return TEST_ROOT / text.lstrip("/")
    return path


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def apt_packages_after_install(args: list[str]) -> list[str]:
    try:
        start = args.index("install") + 1
    except ValueError:
        return []
    values: list[str] = []
    skip_next = False
    for arg in args[start:]:
        if skip_next:
            skip_next = False
            continue
        if arg in {"-o", "--option"}:
            skip_next = True
            continue
        if arg == "--" or arg.startswith("-"):
            continue
        values.append(arg)
    return values


def run_sudo(state: dict[str, Any], args: list[str]) -> int:
    if args == ["-v"]:
        return 0 if state.get("sudo_authorized", True) else 1
    if not args:
        return 0
    if args[0] == "env":
        inner = args[1:]
        while inner and "=" in inner[0] and not inner[0].startswith("-"):
            inner = inner[1:]
        if not inner:
            return 0
        return dispatch(state, inner[0], inner[1:])
    return dispatch(state, args[0], args[1:])


def run_apt_get(state: dict[str, Any], args: list[str]) -> int:
    if "update" in args:
        count = int(state.get("apt_update_count", 0)) + 1
        state["apt_update_count"] = count
        save_state(state)
        if state.get("fail_points", {}).get("apt_update") == count:
            return 1
        return 0
    if "install" in args:
        if state.get("fail_points", {}).get("apt_install"):
            return 1
        installed = set(state.get("installed_packages", []))
        skipped = set(state.get("skip_install_packages", []))
        for package in apt_packages_after_install(args):
            if package not in skipped:
                installed.add(package)
        state["installed_packages"] = sorted(installed)
        save_state(state)
        sync_package_commands(state)
        return 0
    return 0


def run_tee(state: dict[str, Any], args: list[str]) -> int:
    if not args:
        return 0
    target = mapped_system_path(args[-1])
    ensure_parent(target)
    data = sys.stdin.read()
    target.write_text(data, encoding="utf-8")
    sys.stdout.write(data)
    return 0


def run_install(state: dict[str, Any], args: list[str]) -> int:
    positional = [arg for arg in args if not arg.startswith("-")]
    if len(positional) >= 2:
        src = Path(positional[-2])
        dst = mapped_system_path(positional[-1])
        ensure_parent(dst)
        if src.is_file():
            shutil.copyfile(src, dst)
    return 0


def run_chmod(state: dict[str, Any], args: list[str]) -> int:
    # Permissions of test fixture system files are not part of the behavioral contract.
    return 0


def run_curl(state: dict[str, Any], args: list[str]) -> int:
    count = int(state.get("curl_count", 0)) + 1
    state["curl_count"] = count
    save_state(state)
    fail_point = state.get("fail_points", {}).get("curl")
    if fail_point is True or fail_point == count:
        return 1
    sys.stdout.buffer.write(b"test-signing-key\n")
    return 0


def run_dpkg_query(state: dict[str, Any], args: list[str]) -> int:
    package = args[-1] if args else ""
    if package not in set(state.get("installed_packages", [])):
        return 1
    print("ii  ")
    return 0


def dispatch(state: dict[str, Any], command: str, args: list[str]) -> int:
    trace(command, args)
    explicit = state.get("command_exit_codes", {}).get(command)
    if explicit is not None:
        return int(explicit)
    if command == "sudo":
        return run_sudo(state, args)
    if command == "apt-get":
        return run_apt_get(state, args)
    if command == "tee":
        return run_tee(state, args)
    if command == "install":
        return run_install(state, args)
    if command == "chmod":
        return run_chmod(state, args)
    if command == "curl":
        return run_curl(state, args)
    if command == "gpg":
        if state.get("fail_points", {}).get("gpg"):
            return 1
        sys.stdin.buffer.read()
        sys.stdout.buffer.write(b"dearmored-test-key\n")
        return 0
    if command == "dpkg":
        if args == ["--print-architecture"]:
            print(state.get("architecture", "amd64"))
        return 0
    if command == "dpkg-query":
        return run_dpkg_query(state, args)
    if command == "python3.12":
        if "-c" in args:
            print("3.12")
        return 0
    if command in {"git", "gh", "code"}:
        return 0
    return 0


def main() -> int:
    state = load_state()
    sync_package_commands(state)
    return dispatch(state, COMMAND, ARGS)


if __name__ == "__main__":
    raise SystemExit(main())
