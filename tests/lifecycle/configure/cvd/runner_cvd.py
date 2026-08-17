#!/usr/bin/env python3
"""Black-box harness for CVD configure_it140.sh lifecycle tests."""

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

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.configure_log import ConfigureTranscript, parse_configure_log  # noqa: E402
from common.snapshot import snapshot_differences, snapshot_paths  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[4]
CONFIGURE_SOURCE = REPO_ROOT / "scripts" / "cvd" / "configure_it140.sh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
BASH_EXECUTABLE = shutil.which("bash")
if BASH_EXECUTABLE is None:
    raise RuntimeError("CVD Configure lifecycle tests require Bash on PATH")


@dataclass
class ConfigureRun:
    scenario_id: str
    root: Path
    returncode: int
    stdout: str
    stderr: str
    home: Path
    log_dir: Path
    log_file: Path | None
    transcript: ConfigureTranscript | None
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
            sections.append("Configure transcript:\n" + self.transcript.text.rstrip())
        if self.trace_file.is_file():
            trace = self.trace_file.read_text(encoding="utf-8").strip()
            if trace:
                sections.append("Mock command trace:\n" + trace)
        return "\n\n".join(sections)


@dataclass
class ConfigureSequence:
    root: Path
    first: ConfigureRun
    second: ConfigureRun
    first_state: dict[str, Any]
    second_state: dict[str, Any]


class CvdConfigureHarness:
    """Build and execute isolated CVD Configure scenarios."""

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
                merged[key] = CvdConfigureHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _load_manifest(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _default_mock_state() -> dict[str, Any]:
        return {
            "architecture": "amd64",
            "gh_auth": True,
            "github_identity": {
                "id": 12345,
                "login": "it140-test",
                "name": "IT 140 Test Student",
            },
            "numlock_on": False,
            "extensions": [],
            "git_config": {"user.extra": "preserve-me"},
            "emblems": ["custom"],
            "xfce_checksums": {},
            "missing_python_packages": [],
            "command_exit_codes": {},
            "desktop_file_valid": True,
            "xdg_mime_success": True,
        }

    @staticmethod
    def _system_commands(manifest: dict[str, Any]) -> set[str]:
        commands: set[str] = set()
        bindings = manifest["platforms"]["cvd"]["course_ide_bindings"]
        for binding in bindings.values():
            if binding.get("required") and binding.get("installation_scope") == "system":
                commands.update(binding.get("verification", {}).get("executable_names", []))
        protected_real_commands = {
            "bash", "sh", "env", "python3", "awk", "grep", "sed", "find",
            "readlink", "sha256sum", "flock", "date", "tee", "mkdir", "chmod",
        }
        return commands - protected_real_commands

    def _write_mock_wrapper(self, path: Path, command_name: str) -> None:
        interpreter = Path(sys.executable).resolve()
        path.write_text(
            "#!/bin/bash\n"
            f"exec {shell_quote(str(interpreter))} {shell_quote(str(self.mock_dispatcher))} "
            f"{shell_quote(command_name)} \"$@\"\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def _prepare_fixture(
        self,
        temp_root: Path,
        scenario: dict[str, Any],
    ) -> tuple[Path, Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root, symlinks=True)
        home = fixture_root / "home"
        course_root = home / "it140"
        scripts_root = course_root / "scripts"
        manifest_dir = scripts_root / ".manifest"
        cvd_dir = scripts_root / "cvd"
        manifest_dir.mkdir(parents=True, exist_ok=True)
        cvd_dir.mkdir(parents=True, exist_ok=True)

        shutil.copy2(CONFIGURE_SOURCE, cvd_dir / CONFIGURE_SOURCE.name)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        manifest = self._load_manifest(MANIFEST_SOURCE)
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")

        desktop = home / "Desktop"
        desktop.mkdir(parents=True, exist_ok=True)
        obsolete = desktop / "IT 140 Course Folder"
        if obsolete.exists() or obsolete.is_symlink():
            obsolete.unlink()
        obsolete.symlink_to(course_root)

        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        required_mocks = self._system_commands(manifest) | {
            "code", "desktop-file-validate", "dpkg", "gh", "gio", "git",
            "numlockx", "python3.12", "sleep", "xdg-mime", "xdg-open",
            "xdg-user-dir", "xfconf-query", "update-desktop-database", "tree", "xclip",
        }
        for name in sorted(required_mocks):
            self._write_mock_wrapper(mock_dir / name, name)

        state = self._merge(
            self._default_mock_state(),
            scenario.get("mock_overrides", {}),
        )
        state_path = temp_root / "mock-state.json"
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        trace_path = temp_root / "mock-trace.jsonl"
        return home, mock_dir, state_path, trace_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home / ".config" / "other-app" / "prefs.txt",
        }

    def _environment(
        self,
        home: Path,
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
    ) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(home),
                "PATH": f"{mock_dir}:{env.get('PATH', '')}",
                "XDG_CURRENT_DESKTOP": "XFCE",
                "IT140_MOCK_STATE": str(state_path),
                "IT140_MOCK_TRACE": str(trace_path),
                "IT140_MOCK_DISPATCHER": str(self.mock_dispatcher),
                "IT140_MOCK_PYTHON": str(Path(sys.executable).resolve()),
            }
        )
        return env

    @staticmethod
    def _wait_for_log(log_file: Path | None) -> None:
        if log_file is None:
            return
        for _ in range(40):
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
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
    ) -> ConfigureRun:
        protected = self._protected_paths(home)
        before = snapshot_paths(protected)
        log_dir = home / "it140" / "logs"
        before_logs = set(log_dir.glob("configure_cvd_*.log")) if log_dir.exists() else set()

        env = self._environment(home, mock_dir, state_path, trace_path)
        configure_path = home / "it140" / "scripts" / "cvd" / "configure_it140.sh"
        stdout_path = temp_root / f"stdout-{time.time_ns()}.txt"
        stderr_path = temp_root / f"stderr-{time.time_ns()}.txt"
        with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
            "w", encoding="utf-8"
        ) as stderr_handle:
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(configure_path), *scenario.get("arguments", [])],
                cwd=home,
                env=env,
                text=True,
                stdout=stdout_handle,
                stderr=stderr_handle,
                check=False,
                timeout=30,
            )

        stdout = stdout_path.read_text(encoding="utf-8")
        stderr = stderr_path.read_text(encoding="utf-8")
        after = snapshot_paths(protected)
        differences = snapshot_differences(before, after)
        after_logs = set(log_dir.glob("configure_cvd_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_log(log_file)
        transcript = parse_configure_log(log_file) if log_file else None
        return ConfigureRun(
            scenario_id=scenario["id"],
            root=temp_root,
            returncode=completed.returncode,
            stdout=stdout,
            stderr=stderr,
            home=home,
            log_dir=log_dir,
            log_file=log_file,
            transcript=transcript,
            protected_differences=differences,
            trace_file=trace_path,
            state_file=state_path,
        )

    def run_scenario(self, scenario: dict[str, Any]) -> ConfigureRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-configure-cvd-"))
        try:
            home, mock_dir, state_path, trace_path = self._prepare_fixture(temp_root, scenario)
            return self._execute(
                scenario, temp_root, home, mock_dir, state_path, trace_path
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    def run_twice(self, scenario: dict[str, Any]) -> ConfigureSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-configure-cvd-idempotence-"))
        try:
            home, mock_dir, state_path, trace_path = self._prepare_fixture(temp_root, scenario)
            first = self._execute(
                scenario, temp_root, home, mock_dir, state_path, trace_path
            )
            first_state = self.configured_state(first)
            # Configure log filenames have one-second resolution. Keep each run's
            # transcript distinct without altering production time behavior.
            time.sleep(1.05)
            second = self._execute(
                scenario, temp_root, home, mock_dir, state_path, trace_path
            )
            second_state = self.configured_state(second)
            return ConfigureSequence(temp_root, first, second, first_state, second_state)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    @staticmethod
    def configured_state(run: ConfigureRun) -> dict[str, Any]:
        home = run.home
        desktop = home / "Desktop"
        launcher = desktop / "visual-studio-code.desktop"
        settings = home / ".config" / "Code" / "User" / "settings.json"
        repos_link = desktop / "Repos"
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        return {
            "bashrc": (home / ".bashrc").read_text(encoding="utf-8"),
            "profile": (home / ".profile").read_text(encoding="utf-8"),
            "settings": json.loads(settings.read_text(encoding="utf-8")),
            "launcher_text": launcher.read_text(encoding="utf-8"),
            "launcher_mode": stat.S_IMODE(launcher.stat().st_mode),
            "repos_link": os.readlink(repos_link) if repos_link.is_symlink() else None,
            "baseline_present": sorted(
                name for name in (
                    "it140.desktop", "GitHub Login.desktop", "OneDrive Login.desktop"
                ) if (desktop / name).exists() or (desktop / name).is_symlink()
            ),
            "obsolete_present": (
                (desktop / "IT 140 Course Folder").exists()
                or (desktop / "IT 140 Course Folder").is_symlink()
            ),
            "student_digest": file_digest(home / "Repos" / "student-work" / "do_not_touch.py"),
            "mock_state": {
                "gh_auth": state.get("gh_auth"),
                "numlock_on": state.get("numlock_on"),
                "extensions": sorted(state.get("extensions", []), key=str.lower),
                "git_config": state.get("git_config", {}),
                "emblems": state.get("emblems", []),
                "xfce_checksums": state.get("xfce_checksums", {}),
            },
        }


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"
