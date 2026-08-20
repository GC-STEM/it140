#!/usr/bin/env python3
"""Command dispatcher for isolated CVD Install lifecycle tests."""

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
TEST_ROOT = Path(os.environ["IT140_INSTALL_TEST_ROOT"])
COMMAND = os.environ.get("IT140_MOCK_COMMAND", Path(sys.argv[0]).name)
ARGS = sys.argv[1:]


def load_state() -> dict[str, Any]:
    return load_shared_state(STATE_PATH)


def save_state(state: dict[str, Any]) -> None:
    save_shared_state(STATE_PATH, state)


def trace(command: str, args: list[str]) -> None:
    with TRACE_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"command": command, "args": args}, sort_keys=True) + "\n")


def mapped_system_path(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        return path
    text = str(path)
    root_text = str(TEST_ROOT)
    if text == root_text or text.startswith(root_text + os.sep):
        return path
    if text.startswith("/etc/") or text == "/etc" or text.startswith("/usr/share/"):
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
        if "=" in arg and arg.split("=", 1)[0].isupper():
            continue
        values.append(arg)
    return values


def run_sudo(state: dict[str, Any], args: list[str]) -> int:
    if args[:2] == ["-n", "true"]:
        return 0 if state.get("sudo_noninteractive", True) else 1
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
        fail_point = state.get("fail_points", {}).get("apt_update")
        if fail_point == count:
            return 1
        return 0
    if "full-upgrade" in args:
        if state.get("fail_points", {}).get("full_upgrade"):
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
        if "fonts-noto-color-emoji" in installed:
            state.setdefault("package_versions", {})["fonts-noto-color-emoji"] = "1.0-test"
        save_state(state)
        return 0
    return 0


def run_install(state: dict[str, Any], args: list[str]) -> int:
    if "-d" in args:
        for arg in args:
            if arg.startswith("/"):
                mapped_system_path(arg).mkdir(parents=True, exist_ok=True)
        return 0
    positional = [arg for arg in args if not arg.startswith("-")]
    if len(positional) >= 2:
        src = Path(positional[-2])
        dst = mapped_system_path(positional[-1])
        ensure_parent(dst)
        if src.is_file():
            shutil.copyfile(src, dst)
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


def run_chmod(state: dict[str, Any], args: list[str]) -> int:
    for arg in args[1:]:
        if arg.startswith("/"):
            target = mapped_system_path(arg)
            if target.exists():
                target.chmod(int(args[0], 8))
    return 0


def run_curl(state: dict[str, Any], args: list[str]) -> int:
    if state.get("fail_points", {}).get("curl"):
        return 1
    if "--output" in args:
        index = args.index("--output")
        target = Path(args[index + 1])
        ensure_parent(target)
        target.write_bytes(b"test-signing-key\n")
    return 0


def run_dpkg_query(state: dict[str, Any], args: list[str]) -> int:
    package = args[-1] if args else ""
    installed = package in set(state.get("installed_packages", []))
    format_arg = next((arg for arg in args if arg.startswith("-f=")), "")
    if "${Version}" in format_arg:
        if not installed:
            return 1
        print(state.get("package_versions", {}).get(package, "1.0-test"), end="")
        return 0
    if "${Status}" in format_arg:
        if not installed:
            return 1
        print("install ok installed", end="")
        return 0
    return 0 if installed else 1


def dispatch(state: dict[str, Any], command: str, args: list[str]) -> int:
    trace(command, args)
    explicit = state.get("command_exit_codes", {}).get(command)
    if explicit is not None:
        return int(explicit)
    if command == "sudo":
        return run_sudo(state, args)
    if command == "apt-get":
        return run_apt_get(state, args)
    if command == "install":
        return run_install(state, args)
    if command == "tee":
        return run_tee(state, args)
    if command == "chmod":
        return run_chmod(state, args)
    if command == "chown":
        return 0
    if command == "curl":
        return run_curl(state, args)
    if command == "gpg":
        if state.get("fail_points", {}).get("gpg"):
            return 1
        sys.stdout.buffer.write(b"dearmored-test-key\n")
        return 0
    if command == "dpkg":
        if args == ["--print-architecture"]:
            print(state.get("architecture", "amd64"))
        return 0
    if command == "dpkg-query":
        return run_dpkg_query(state, args)
    if command == "df":
        available = int(state.get("free_space_bytes", 100 * 1024**3))
        print("Filesystem 1-blocks Used Available Capacity Mounted on")
        print(f"testfs {available * 2} 0 {available} 0% /")
        return 0
    if command == "fc-match":
        if state.get("font_healthy", True):
            if "-f" in args:
                print("Noto Color Emoji")
            else:
                print("NotoColorEmoji.ttf: Noto Color Emoji")
        else:
            print("DejaVu Sans")
        return 0
    if command == "fc-list":
        if state.get("font_healthy", True):
            print(f"{state['font_file']}: Noto Color Emoji")
        return 0
    if command == "fc-cache":
        if state.get("fail_points", {}).get("font_cache"):
            return 1
        state["font_healthy"] = True
        save_state(state)
        return 0
    if command == "desktop-file-validate":
        return 0 if state.get("desktop_file_valid", True) else 1
    if command == "python3.12":
        if args == ["-"]:
            sys.stdin.read()
            return 0
        return 0
    return 0


def main() -> int:
    state = load_state()
    return dispatch(state, COMMAND, ARGS)


if __name__ == "__main__":
    raise SystemExit(main())
