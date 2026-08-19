#!/usr/bin/env python3
"""Black-box harness for the current Beta CVD prepare_it140.sh."""

from __future__ import annotations

from dataclasses import dataclass
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[4]
PREPARE_SOURCE = REPO_ROOT / "scripts" / "cvd" / "prepare_it140.sh"
BASH_EXECUTABLE = shutil.which("bash")
if BASH_EXECUTABLE is None:
    raise RuntimeError("CVD Prepare lifecycle tests require Bash on PATH")


@dataclass
class PrepareTranscript:
    path: Path
    text: str


@dataclass
class PrepareRun:
    scenario_id: str
    root: Path
    returncode: int
    stdout: str
    stderr: str
    home: Path
    tmp_dir: Path
    log_dir: Path
    log_file: Path | None
    transcript: PrepareTranscript | None
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
            sections.append("Prepare transcript:\n" + self.transcript.text.rstrip())
        if self.trace_file.is_file():
            trace_text = self.trace_file.read_text(encoding="utf-8").strip()
            if trace_text:
                sections.append("Mock command trace:\n" + trace_text)
        if self.state_file.is_file():
            state_text = self.state_file.read_text(encoding="utf-8").strip()
            if state_text:
                sections.append("Prepare test state:\n" + state_text)
        return "\n\n".join(sections)

    @property
    def trace_entries(self) -> list[dict[str, Any]]:
        if not self.trace_file.is_file():
            return []
        return [
            json.loads(line)
            for line in self.trace_file.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]


@dataclass
class PrepareSequence:
    root: Path
    first: PrepareRun
    second: PrepareRun
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


def host_is_ubuntu() -> bool:
    """The current production CVD Prepare reads /etc/os-release directly."""
    path = Path("/etc/os-release")
    if not path.is_file():
        return False
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in raw or raw.lstrip().startswith("#"):
            continue
        key, value = raw.split("=", 1)
        values[key] = value.strip().strip('"')
    return values.get("ID") == "ubuntu"


class CvdPrepareHarness:
    """Build and execute isolated scenarios without modifying production Prepare."""

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
                merged[key] = CvdPrepareHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _default_mock_state() -> dict[str, Any]:
        return {
            "uid": 1000,
            "username": "ubuntu",
            "uname_s": "Linux",
            "uname_m": "x86_64",
            "fail_points": {},
            "curl_exit_code": 22,
            "curl_calls": 0,
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

    @staticmethod
    def _archive_script_payload(name: str) -> bytes:
        if name == "prepare":
            return PREPARE_SOURCE.read_bytes()
        return (
            "#!/usr/bin/env bash\n"
            f"# characterization archive placeholder for {name}_it140.sh\n"
            "exit 0\n"
        ).encode()

    @classmethod
    def _build_archive(cls, archive_path: Path, mode: str = "valid") -> None:
        with tarfile.open(archive_path, "w:gz") as archive:
            files: dict[str, tuple[bytes, int]] = {
                "it140-main/.git/HEAD": (b"ref: refs/heads/main\n", 0o600),
                "it140-main/managed/version.txt": (b"current-beta-prepare-suite\n", 0o600),
            }
            for action in ("prepare", "install", "configure", "verify", "update"):
                if mode == "missing_configure" and action == "configure":
                    continue
                files[f"it140-main/scripts/cvd/{action}_it140.sh"] = (
                    cls._archive_script_payload(action),
                    0o644,
                )
            sanitizer = (
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "if [[ \"${IT140_PREPARE_TEST_SANITIZE_FAIL:-false}\" == true ]]; then\n"
                "    exit 1\n"
                "fi\n"
                "printf 'invoked\\n' > \"$HOME/it140/sanitize-invoked.txt\"\n"
            ).encode()
            files["it140-main/scripts/cvd/sanitize_CVD.sh"] = (sanitizer, 0o644)
            for relative, (payload, mode_bits) in files.items():
                info = tarfile.TarInfo(relative)
                info.size = len(payload)
                info.mode = mode_bits
                archive.addfile(info, io.BytesIO(payload))

    def _prepare_fixture(
        self, temp_root: Path, scenario: dict[str, Any]
    ) -> tuple[Path, Path, Path, Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root)
        home = fixture_root / "home"
        course_root = home / "it140"
        cvd_dir = course_root / "scripts" / "cvd"
        cvd_dir.mkdir(parents=True, exist_ok=True)
        prepare_path = cvd_dir / PREPARE_SOURCE.name
        shutil.copy2(PREPARE_SOURCE, prepare_path)
        prepare_path.chmod(0o755)

        tmp_dir = temp_root / "tmp"
        tmp_dir.mkdir()
        archive_path = temp_root / "it140-main.tar.gz"
        archive_mode = scenario.get("fixture_overrides", {}).get("archive", "valid")
        self._build_archive(archive_path, archive_mode)

        state = self._merge(self._default_mock_state(), scenario.get("mock_overrides", {}))
        state["archive_path"] = str(archive_path)
        state_path = temp_root / "mock-state.json"
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        trace_path = temp_root / "mock-trace.jsonl"

        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir()
        for command in ("curl", "id", "uname"):
            self._write_mock_wrapper(mock_dir / command, command)

        native_dir = temp_root / "native-bin"
        native_dir.mkdir()
        # Deliberately expose only baseline utilities that current Prepare uses.
        # Git, gh, apt/apt-get, and later-stage course tools are absent.
        for command in (
            "bash", "cat", "chmod", "cp", "date", "find", "grep", "gzip",
            "mkdir", "mktemp", "rm", "tar", "tee", "touch",
        ):
            source = shutil.which(command)
            if source is None:
                raise RuntimeError(f"CVD Prepare tests require native utility: {command}")
            (native_dir / command).symlink_to(Path(source).resolve())

        return home, tmp_dir, mock_dir, native_dir, state_path, trace_path, prepare_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "nested_repo_git": home / "Repos" / "student-work" / ".git",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home / ".config" / "other-app" / "prefs.txt",
            "git_config": home / ".gitconfig",
            "course_unmanaged_file": home / "it140" / "local-unmanaged.txt",
            "course_legacy_marker": home / "it140" / "scripts" / "cvd" / "legacy_marker.txt",
        }

    def _environment(
        self,
        home: Path,
        tmp_dir: Path,
        mock_dir: Path,
        native_dir: Path,
        state_path: Path,
        trace_path: Path,
        scenario: dict[str, Any],
        mode: str,
    ) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(home),
                "TMPDIR": str(tmp_dir),
                "PATH": f"{mock_dir}:{native_dir}",
                "IT140_PREPARE_MODE": mode,
                "IT140_MOCK_STATE": str(state_path),
                "IT140_MOCK_TRACE": str(trace_path),
                "IT140_MOCK_DISPATCHER": str(self.mock_dispatcher),
                "IT140_MOCK_PYTHON": str(
                    Path("/usr/bin/python3")
                    if Path("/usr/bin/python3").is_file()
                    else Path(sys.executable).resolve()
                ),
            }
        )
        if scenario.get("fixture_overrides", {}).get("sanitize_failure"):
            env["IT140_PREPARE_TEST_SANITIZE_FAIL"] = "true"
        return env

    @staticmethod
    def _wait_for_log(log_file: Path | None) -> None:
        if log_file is None:
            return
        for _ in range(80):
            try:
                text = log_file.read_text(encoding="utf-8", errors="replace")
                if (
                    "SUCCESS: The IT 140 automation package is ready." in text
                    or "ERROR: Prepare did not complete successfully." in text
                    or "ERROR: Preparation did not complete." in text
                ):
                    return
            except OSError:
                pass
            time.sleep(0.05)

    def _execute(
        self,
        scenario: dict[str, Any],
        temp_root: Path,
        home: Path,
        tmp_dir: Path,
        mock_dir: Path,
        native_dir: Path,
        state_path: Path,
        trace_path: Path,
        prepare_path: Path,
        mode: str = "refresh",
    ) -> PrepareRun:
        protected = self._protected_paths(home)
        before = _snapshot(protected)
        log_dir = home / "it140" / "logs"
        before_logs = set(log_dir.glob("prepare_ide_*.log")) if log_dir.exists() else set()
        env = self._environment(
            home, tmp_dir, mock_dir, native_dir, state_path, trace_path, scenario, mode
        )
        completed = subprocess.run(
            [BASH_EXECUTABLE, str(prepare_path)],
            cwd=home,
            env=env,
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
        )
        after = _snapshot(protected)
        after_logs = set(log_dir.glob("prepare_ide_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_log(log_file)
        transcript = (
            PrepareTranscript(
                path=log_file,
                text=log_file.read_text(encoding="utf-8", errors="replace"),
            )
            if log_file is not None
            else None
        )
        return PrepareRun(
            scenario_id=scenario["id"],
            root=temp_root,
            returncode=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
            home=home,
            tmp_dir=tmp_dir,
            log_dir=log_dir,
            log_file=log_file,
            transcript=transcript,
            protected_differences=_differences(before, after),
            trace_file=trace_path,
            state_file=state_path,
        )

    def run_scenario(self, scenario: dict[str, Any], mode: str = "refresh") -> PrepareRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-prepare-cvd-"))
        try:
            prepared = self._prepare_fixture(temp_root, scenario)
            return self._execute(scenario, temp_root, *prepared, mode=mode)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    @staticmethod
    def _semantic_state(run: PrepareRun) -> dict[str, Any]:
        home = run.home
        course_root = home / "it140"
        script_modes: dict[str, int | None] = {}
        for name in (
            "prepare_it140.sh", "install_it140.sh", "configure_it140.sh",
            "verify_it140.sh", "update_it140.sh", "sanitize_CVD.sh",
        ):
            path = course_root / "scripts" / "cvd" / name
            script_modes[name] = stat.S_IMODE(path.stat().st_mode) if path.exists() else None
        return {
            "managed_version": (
                (course_root / "managed" / "version.txt").read_text(encoding="utf-8")
                if (course_root / "managed" / "version.txt").is_file()
                else None
            ),
            "bashrc": (home / ".bashrc").read_text(encoding="utf-8"),
            "top_level_git": (course_root / ".git").exists(),
            "sanitizer_marker": (
                (course_root / "sanitize-invoked.txt").read_text(encoding="utf-8")
                if (course_root / "sanitize-invoked.txt").is_file()
                else None
            ),
            "script_modes": script_modes,
            "protected": _snapshot(CvdPrepareHarness._protected_paths(home)),
        }

    def run_twice(self, scenario: dict[str, Any]) -> PrepareSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-prepare-cvd-twice-"))
        try:
            prepared = self._prepare_fixture(temp_root, scenario)
            first = self._execute(scenario, temp_root, *prepared)
            first_state = self._semantic_state(first)
            second = self._execute(scenario, temp_root, *prepared)
            second_state = self._semantic_state(second)
            return PrepareSequence(temp_root, first, second, first_state, second_state)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
