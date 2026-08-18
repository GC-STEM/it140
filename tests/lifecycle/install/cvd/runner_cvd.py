#!/usr/bin/env python3
"""Black-box harness for CVD install_it140.sh lifecycle tests."""

from __future__ import annotations

from dataclasses import dataclass
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[4]
INSTALL_SOURCE = REPO_ROOT / "scripts" / "cvd" / "install_it140.sh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
BASH_EXECUTABLE = shutil.which("bash")
if BASH_EXECUTABLE is None:
    raise RuntimeError("CVD Install lifecycle tests require Bash on PATH")


@dataclass
class InstallTranscript:
    path: Path
    text: str
    summary: dict[str, str]


@dataclass
class InstallRun:
    scenario_id: str
    root: Path
    returncode: int
    stdout: str
    stderr: str
    home: Path
    system_root: Path
    log_dir: Path
    log_file: Path | None
    transcript: InstallTranscript | None
    protected_differences: list[str]
    trace_file: Path
    state_file: Path

    @property
    def combined_output(self) -> str:
        sections: list[str] = []
        captured = self.stdout + self.stderr
        if captured.strip():
            sections.append("Captured process output:\n" + captured.rstrip())
        if self.transcript is not None and self.transcript.text.strip():
            sections.append("Install transcript:\n" + self.transcript.text.rstrip())
        if self.trace_file.is_file():
            trace = self.trace_file.read_text(encoding="utf-8").strip()
            if trace:
                sections.append("Mock command trace:\n" + trace)
        if self.state_file.is_file():
            state = self.state_file.read_text(encoding="utf-8").strip()
            if state:
                sections.append("Install test state:\n" + state)
        return "\n\n".join(sections)


@dataclass
class InstallSequence:
    root: Path
    first: InstallRun
    second: InstallRun
    first_state: dict[str, Any]
    second_state: dict[str, Any]


def _file_digest(path: Path) -> str | None:
    if not path.exists() and not path.is_symlink():
        return None
    if path.is_symlink():
        return "symlink:" + os.readlink(path)
    if path.is_file():
        return hashlib.sha256(path.read_bytes()).hexdigest()
    if path.is_dir():
        entries: list[str] = []
        for child in sorted(path.rglob("*")):
            rel = child.relative_to(path).as_posix()
            if child.is_symlink():
                entries.append(f"L {rel} {os.readlink(child)}")
            elif child.is_file():
                entries.append(f"F {rel} {hashlib.sha256(child.read_bytes()).hexdigest()}")
            elif child.is_dir():
                entries.append(f"D {rel}")
        return hashlib.sha256("\n".join(entries).encode()).hexdigest()
    return "other"


def _snapshot(paths: dict[str, Path]) -> dict[str, str | None]:
    return {name: _file_digest(path) for name, path in paths.items()}


def _differences(before: dict[str, str | None], after: dict[str, str | None]) -> list[str]:
    return sorted(name for name in before if before[name] != after[name])


def parse_install_log(path: Path) -> InstallTranscript:
    text = path.read_text(encoding="utf-8", errors="replace")
    summary: dict[str, str] = {}
    in_summary = False
    for raw_line in text.splitlines():
        line = raw_line.strip("\ufeff\r\n")
        if line == "INSTALLATION SUMMARY":
            in_summary = True
            continue
        if not in_summary or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key in {
            "Conclusion", "Result", "Script version", "Version DTG",
            "Manifest release", "Manifest DTG", "Warnings", "Failures",
            "Start time", "End time", "Managed changes", "Elapsed time",
            "Next step", "Log file", "Exit code",
        }:
            summary[key] = value.strip()
    return InstallTranscript(path=path, text=text, summary=summary)


class CvdInstallHarness:
    """Build and execute isolated CVD Install scenarios."""

    def __init__(self, fixture_base: Path, mock_dispatcher: Path):
        self.fixture_base = fixture_base
        self.mock_dispatcher = mock_dispatcher.resolve()

    @staticmethod
    def load_scenario(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _merge(base: dict[str, Any], overrides: dict[str, Any]) -> dict[str, Any]:
        merged = copy.deepcopy(base)
        for key, value in overrides.items():
            if isinstance(value, dict) and isinstance(merged.get(key), dict):
                merged[key] = CvdInstallHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _default_mock_state() -> dict[str, Any]:
        return {
            "architecture": "amd64",
            "sudo_noninteractive": True,
            "free_space_bytes": 100 * 1024**3,
            "installed_packages": [],
            "package_versions": {},
            "font_healthy": True,
            "desktop_file_valid": True,
            "fail_points": {},
            "skip_install_packages": [],
            "command_exit_codes": {},
        }

    @staticmethod
    def _write_mock_wrapper(path: Path, command_name: str) -> None:
        path.write_text(
            "#!/usr/bin/env bash\n"
            f"export IT140_MOCK_COMMAND={command_name!r}\n"
            'exec "$IT140_MOCK_PYTHON" "$IT140_MOCK_DISPATCHER" "$@"\n',
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _prepare_fixture(
        self, temp_root: Path, scenario: dict[str, Any]
    ) -> tuple[Path, Path, Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root)
        home = fixture_root / "home"
        system_root = fixture_root / "system"
        course_root = home / "it140"
        manifest_dir = course_root / "scripts" / ".manifest"
        cvd_dir = course_root / "scripts" / "cvd"
        manifest_dir.mkdir(parents=True, exist_ok=True)
        cvd_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(INSTALL_SOURCE, cvd_dir / INSTALL_SOURCE.name)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            (manifest_dir / MANIFEST_SOURCE.name).write_text(
                "{ this is not valid JSON\n", encoding="utf-8"
            )
        font_file = system_root / "usr" / "share" / "fonts" / "test" / "NotoColorEmoji.ttf"
        font_file.parent.mkdir(parents=True, exist_ok=True)
        font_file.write_bytes(b"test-font-placeholder\n")
        state = self._merge(self._default_mock_state(), scenario.get("mock_overrides", {}))
        state["font_file"] = str(font_file)
        state_path = temp_root / "mock-state.json"
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        trace_path = temp_root / "mock-trace.jsonl"
        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        for command in (
            "code", "curl", "desktop-file-validate", "df", "dpkg", "dpkg-query",
            "fc-cache", "fc-list", "fc-match", "gh", "git", "gpg", "numlockx",
            "python3.12", "sudo", "xclip", "xfconf-query",
        ):
            self._write_mock_wrapper(mock_dir / command, command)
        return home, system_root, mock_dir, state_path, trace_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home / ".config" / "other-app" / "prefs.txt",
            "git_config": home / ".gitconfig",
        }

    def _environment(
        self,
        home: Path,
        system_root: Path,
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
    ) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(home),
                "PATH": f"{mock_dir}:{env.get('PATH', '')}",
                "IT140_INSTALL_TEST_MODE": "true",
                "IT140_INSTALL_TEST_ROOT": str(system_root),
                "IT140_INSTALL_TEST_EUID": "1000",
                "IT140_MOCK_STATE": str(state_path),
                "IT140_MOCK_TRACE": str(trace_path),
                "IT140_MOCK_DISPATCHER": str(self.mock_dispatcher),
                "IT140_MOCK_PYTHON": str(Path("/usr/bin/python3") if Path("/usr/bin/python3").is_file() else Path(sys.executable).resolve()),
            }
        )
        return env

    @staticmethod
    def _wait_for_log(log_file: Path | None) -> None:
        if log_file is None:
            return
        for _ in range(60):
            try:
                if "Exit code" in log_file.read_text(encoding="utf-8", errors="replace"):
                    return
            except OSError:
                pass
            time.sleep(0.05)

    def _execute(
        self,
        scenario: dict[str, Any],
        temp_root: Path,
        home: Path,
        system_root: Path,
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
    ) -> InstallRun:
        protected = self._protected_paths(home)
        before = _snapshot(protected)
        log_dir = home / "it140" / "logs"
        before_logs = set(log_dir.glob("install_cvd_*.log")) if log_dir.exists() else set()
        env = self._environment(home, system_root, mock_dir, state_path, trace_path)
        install_path = home / "it140" / "scripts" / "cvd" / "install_it140.sh"
        completed = subprocess.run(
            [BASH_EXECUTABLE, str(install_path), *scenario.get("arguments", [])],
            cwd=home,
            env=env,
            text=True,
            capture_output=True,
            check=False,
            timeout=45,
        )
        after = _snapshot(protected)
        after_logs = set(log_dir.glob("install_cvd_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_log(log_file)
        transcript = parse_install_log(log_file) if log_file else None
        return InstallRun(
            scenario_id=scenario["id"],
            root=temp_root,
            returncode=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
            home=home,
            system_root=system_root,
            log_dir=log_dir,
            log_file=log_file,
            transcript=transcript,
            protected_differences=_differences(before, after),
            trace_file=trace_path,
            state_file=state_path,
        )

    def run_scenario(self, scenario: dict[str, Any]) -> InstallRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-install-cvd-"))
        try:
            home, system_root, mock_dir, state_path, trace_path = self._prepare_fixture(
                temp_root, scenario
            )
            return self._execute(
                scenario, temp_root, home, system_root, mock_dir, state_path, trace_path
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    @staticmethod
    def _semantic_state(run: InstallRun) -> dict[str, Any]:
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        state.pop("apt_update_count", None)
        system_files: dict[str, str | None] = {}
        for relative in (
            "etc/apt/keyrings/githubcli-archive-keyring.gpg",
            "etc/apt/sources.list.d/github-cli.list",
            "usr/share/keyrings/microsoft.gpg",
            "etc/apt/sources.list.d/vscode.sources",
            "etc/xdg/autostart/numlockx.desktop",
            "etc/opt/chrome/policies/managed/it140_bookmarks.json",
        ):
            path = run.system_root / relative
            system_files[relative] = path.read_text(encoding="utf-8") if path.is_file() else None
        return {"mock_state": state, "system_files": system_files}

    def run_twice(self, scenario: dict[str, Any]) -> InstallSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-install-cvd-twice-"))
        try:
            home, system_root, mock_dir, state_path, trace_path = self._prepare_fixture(
                temp_root, scenario
            )
            first = self._execute(
                scenario, temp_root, home, system_root, mock_dir, state_path, trace_path
            )
            first_state = self._semantic_state(first)
            second = self._execute(
                scenario, temp_root, home, system_root, mock_dir, state_path, trace_path
            )
            second_state = self._semantic_state(second)
            return InstallSequence(temp_root, first, second, first_state, second_state)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
