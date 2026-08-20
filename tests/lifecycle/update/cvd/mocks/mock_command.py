#!/usr/bin/env python3
"""Stateful command dispatcher for isolated CVD Update lifecycle tests."""

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
TEST_ROOT = Path(os.environ["IT140_UPDATE_TEST_ROOT"])
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
    if text == "/etc" or text.startswith("/etc/") or text.startswith("/usr/share/") or text.startswith("/var/run/"):
        return TEST_ROOT / text.lstrip("/")
    return path


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def packages_after_install(args: list[str]) -> list[str]:
    try:
        start = args.index("install") + 1
    except ValueError:
        return []
    values: list[str] = []
    for arg in args[start:]:
        if arg == "--" or arg.startswith("-"):
            continue
        if "=" in arg and arg.split("=", 1)[0].isupper():
            continue
        values.append(arg)
    return values


def run_install(_state: dict[str, Any], args: list[str]) -> int:
    if "-d" in args:
        for arg in args:
            if arg.startswith("/"):
                mapped_system_path(arg).mkdir(parents=True, exist_ok=True)
        return 0
    if len(args) >= 2:
        src = Path(args[-2])
        dst = mapped_system_path(args[-1])
        ensure_parent(dst)
        if src.is_file():
            shutil.copyfile(src, dst)
            try:
                dst.chmod(0o644)
            except OSError:
                pass
            return 0
    return 1


def run_sudo(state: dict[str, Any], args: list[str]) -> int:
    if args[:2] == ["-n", "true"]:
        return 0 if state.get("sudo_noninteractive", True) else 1
    inner = list(args)
    if inner and inner[0] == "env":
        inner = inner[1:]
    while inner and "=" in inner[0] and not inner[0].startswith("-"):
        inner = inner[1:]
    if not inner:
        return 0
    return dispatch(state, inner[0], inner[1:])


def run_apt_get(state: dict[str, Any], args: list[str]) -> int:
    if "update" in args:
        count = int(state.get("apt_update_count", 0)) + 1
        state["apt_update_count"] = count
        save_state(state)
        fail_at = state.get("fail_points", {}).get("apt_update")
        return 1 if fail_at is True or fail_at == count else 0
    if "full-upgrade" in args:
        return 1 if state.get("fail_points", {}).get("full_upgrade") else 0
    if "install" in args:
        if state.get("fail_points", {}).get("apt_install"):
            return 1
        installed = set(state.get("installed_packages", []))
        skipped = set(state.get("skip_install_packages", []))
        for package in packages_after_install(args):
            if package not in skipped:
                installed.add(package)
        state["installed_packages"] = sorted(installed)
        if "fonts-noto-color-emoji" in installed:
            state.setdefault("package_versions", {})["fonts-noto-color-emoji"] = "1.0-test"
        save_state(state)
        return 0
    if "autoremove" in args or "clean" in args:
        return 0
    return 0


def run_dpkg_query(state: dict[str, Any], args: list[str]) -> int:
    package = args[-1] if args else ""
    installed = package in set(state.get("installed_packages", []))
    fmt = next((arg for arg in args if arg.startswith("-f")), "")
    if "${Version}" in fmt:
        if not installed:
            return 1
        print(state.get("package_versions", {}).get(package, "1.0-test"), end="")
        return 0
    if "${Status}" in fmt:
        if not installed:
            return 1
        print("install ok installed", end="")
        return 0
    return 0 if installed else 1


def run_curl(state: dict[str, Any], args: list[str]) -> int:
    count = int(state.get("archive_download_count", 0)) + 1
    state["archive_download_count"] = count
    save_state(state)
    if state.get("fail_points", {}).get("archive_download"):
        return 1
    if "--output" not in args:
        return 1
    output = Path(args[args.index("--output") + 1])
    ensure_parent(output)
    shutil.copyfile(Path(state["archive_path"]), output)
    return 0


def run_python312(state: dict[str, Any], args: list[str]) -> int:
    if len(args) >= 3 and args[:2] == ["-m", "venv"]:
        venv_dir = Path(args[2])
        python_path = venv_dir / "bin" / "python"
        python_path.parent.mkdir(parents=True, exist_ok=True)
        python_path.write_text(
            "#!/usr/bin/env bash\n"
            "export IT140_MOCK_COMMAND='venv-python'\n"
            'exec "$IT140_MOCK_PYTHON" "$IT140_MOCK_DISPATCHER" "$@"\n',
            encoding="utf-8",
        )
        python_path.chmod(0o755)
        return 0
    return 0


def run_venv_python(state: dict[str, Any], args: list[str]) -> int:
    if args[:3] == ["-m", "pip", "install"]:
        if state.get("fail_points", {}).get("pip_install"):
            return 1
        installed = set(state.get("venv_packages", []))
        skipped = set(state.get("skip_venv_packages", []))
        for arg in args[3:]:
            if arg.startswith("-"):
                continue
            if arg in {"pip", "setuptools", "wheel"}:
                continue
            if arg not in skipped:
                installed.add(arg)
        state["venv_packages"] = sorted(installed)
        save_state(state)
        return 0
    if args[:3] == ["-m", "pip", "show"] and len(args) >= 4:
        return 0 if args[3] in set(state.get("venv_packages", [])) else 1
    return 0


def run_code(state: dict[str, Any], args: list[str]) -> int:
    if "--install-extension" in args:
        if state.get("fail_points", {}).get("extension_install"):
            return 1
        index = args.index("--install-extension")
        extension = args[index + 1]
        if extension not in set(state.get("skip_extensions", [])):
            extensions = set(state.get("extensions", []))
            extensions.add(extension)
            state["extensions"] = sorted(extensions)
            save_state(state)
        return 0
    if args == ["--list-extensions"]:
        for extension in state.get("extensions", []):
            print(extension)
        return 0
    return 0


def run_git(state: dict[str, Any], args: list[str]) -> int:
    if len(args) >= 4 and args[:3] == ["config", "--global", "--get"]:
        key = args[3]
        value = state.get("git_config", {}).get(key)
        if value is None:
            return 1
        print(value)
        return 0
    return 0


def run_gio(state: dict[str, Any], args: list[str]) -> int:
    if len(args) >= 3 and args[0] == "info" and args[1] == "-a":
        attribute = args[2]
        if attribute == "metadata::emblems":
            print(f"  metadata::emblems: {state.get('repos_emblem', '')}")
            return 0
        if attribute == "metadata::xfce-exe-checksum":
            print(f"  metadata::xfce-exe-checksum: {state.get('launcher_checksum', '')}")
            return 0
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
    if command == "install":
        return run_install(state, args)
    if command == "test":
        if len(args) >= 2 and args[0] == "-r":
            return 0 if mapped_system_path(args[1]).is_file() else 1
        return 0
    if command == "cmp":
        paths = [mapped_system_path(arg) for arg in args if not arg.startswith("-")]
        if len(paths) >= 2 and paths[-2].is_file() and paths[-1].is_file():
            return 0 if paths[-2].read_bytes() == paths[-1].read_bytes() else 1
        return 1
    if command == "curl":
        return run_curl(state, args)
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
        return run_python312(state, args)
    if command == "venv-python":
        return run_venv_python(state, args)
    if command == "code":
        return run_code(state, args)
    if command == "gh":
        if args[:2] == ["auth", "status"]:
            return 0 if state.get("gh_auth", True) else 1
        return 0
    if command == "git":
        return run_git(state, args)
    if command == "xdg-user-dir":
        if args == ["DESKTOP"]:
            print(Path(os.environ["HOME"]) / "Desktop")
            return 0
        return 1
    if command == "gio":
        return run_gio(state, args)
    if command == "numlockx":
        if args == ["status"]:
            if state.get("numlock_on", True):
                print("Numlock is on")
                return 0
            print("Numlock is off")
            return 1
        return 0
    if command == "pgrep":
        return 1
    if command == "sleep":
        return 0
    if command == "xclip":
        return 0
    return 0


def main() -> int:
    state = load_state()
    return dispatch(state, COMMAND, ARGS)


if __name__ == "__main__":
    raise SystemExit(main())
