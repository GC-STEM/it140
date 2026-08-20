#!/usr/bin/env python3
"""Black-box harness for macOS prepare_it140.zsh lifecycle tests."""

from __future__ import annotations

from dataclasses import dataclass
import copy
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any
import zipfile

REPO_ROOT = Path(__file__).resolve().parents[4]
PREPARE_SOURCE = REPO_ROOT / "scripts" / "mac" / "prepare_it140.zsh"
ZSH_EXECUTABLE = Path("/bin/zsh")
PRODUCTION_ARCHIVE_URL = "https://github.com/GC-STEM/it140/archive/refs/heads/main.zip"


@dataclass
class PrepareTranscript:
    path: Path
    text: str
    summary: dict[str, str]


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
    request_count: int
    request_paths: list[str]
    critical_before: dict[str, str | None]
    critical_after: dict[str, str | None]

    @property
    def combined_output(self) -> str:
        sections: list[str] = []
        captured = self.stdout + self.stderr
        if captured.strip():
            sections.append("Captured process output:\n" + captured.rstrip())
        if self.transcript is not None and self.transcript.text.strip():
            sections.append("Prepare transcript:\n" + self.transcript.text.rstrip())
        if self.trace_file.is_file():
            trace = self.trace_file.read_text(encoding="utf-8").strip()
            if trace:
                sections.append("Mock command trace:\n" + trace)
        if self.state_file.is_file():
            state = self.state_file.read_text(encoding="utf-8").strip()
            if state:
                sections.append("Prepare test state:\n" + state)
        sections.append(
            "Loopback archive requests:\n"
            + json.dumps({"count": self.request_count, "paths": self.request_paths}, indent=2)
        )
        return "\n\n".join(sections)


@dataclass
class PrepareSequence:
    root: Path
    first: PrepareRun
    second: PrepareRun
    first_state: dict[str, Any]
    second_state: dict[str, Any]


def _digest(path: Path) -> str | None:
    if not path.exists() and not path.is_symlink():
        return None
    if path.is_symlink():
        return "symlink:" + os.readlink(path)
    if path.is_file():
        return hashlib.sha256(path.read_bytes()).hexdigest()
    if path.is_dir():
        rows: list[str] = []
        for child in sorted(path.rglob("*")):
            rel = child.relative_to(path).as_posix()
            if child.is_symlink():
                rows.append(f"L {rel} {os.readlink(child)}")
            elif child.is_file():
                rows.append(f"F {rel} {hashlib.sha256(child.read_bytes()).hexdigest()}")
            else:
                rows.append(f"D {rel}")
        return hashlib.sha256("\n".join(rows).encode()).hexdigest()
    return "other"


def _snapshot(paths: dict[str, Path]) -> dict[str, str | None]:
    return {name: _digest(path) for name, path in paths.items()}


def _differences(before: dict[str, str | None], after: dict[str, str | None]) -> list[str]:
    return sorted(name for name in before if before[name] != after[name])


def parse_prepare_log(path: Path) -> PrepareTranscript:
    text = path.read_text(encoding="utf-8", errors="replace")
    summary: dict[str, str] = {}
    in_summary = False
    accepted = {
        "Result", "Artifact version", "Version date-time group", "Development status",
        "Course root", "Workflow", "Starting state", "Operating role", "Managed changes",
        "Elapsed time", "Detail", "Next step", "Log file", "Exit code",
    }
    for raw_line in text.splitlines():
        line = raw_line.strip("\ufeff\r\n")
        if line == "IT 140 macOS PREPARE SUMMARY":
            in_summary = True
            continue
        if not in_summary or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key in accepted:
            summary[key] = value.strip()
    return PrepareTranscript(path=path, text=text, summary=summary)


def host_is_supported_mac() -> bool:
    return (
        sys.platform == "darwin"
        and platform.machine() == "arm64"
        and ZSH_EXECUTABLE.is_file()
        and Path("/usr/bin/curl").is_file()
        and Path("/usr/bin/ditto").is_file()
        and Path("/usr/bin/osascript").is_file()
    )


class _ArchiveHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        server = self.server
        server.request_count += 1  # type: ignore[attr-defined]
        server.request_paths.append(self.path)  # type: ignore[attr-defined]
        status = int(server.response_status)  # type: ignore[attr-defined]
        if status != 200:
            self.send_response(status)
            self.end_headers()
            return
        payload = bytes(server.payload)  # type: ignore[attr-defined]
        self.send_response(200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args: object) -> None:
        return


class ArchiveServer:
    def __init__(self, response_status: int = 200):
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), _ArchiveHandler)
        self.httpd.request_count = 0  # type: ignore[attr-defined]
        self.httpd.request_paths = []  # type: ignore[attr-defined]
        self.httpd.response_status = response_status  # type: ignore[attr-defined]
        self.httpd.payload = b""  # type: ignore[attr-defined]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    @property
    def url(self) -> str:
        host, port = self.httpd.server_address
        return f"http://{host}:{port}/main.zip"

    @property
    def request_count(self) -> int:
        return int(self.httpd.request_count)  # type: ignore[attr-defined]

    @property
    def request_paths(self) -> list[str]:
        return list(self.httpd.request_paths)  # type: ignore[attr-defined]

    def set_payload(self, payload: bytes) -> None:
        self.httpd.payload = payload  # type: ignore[attr-defined]

    def start(self) -> None:
        self.thread.start()

    def close(self) -> None:
        self.httpd.shutdown()
        self.thread.join(timeout=5)
        self.httpd.server_close()


class MacPrepareHarness:
    """Build and execute isolated macOS Prepare scenarios without altering production."""

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
                merged[key] = MacPrepareHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _default_state() -> dict[str, Any]:
        return {
            "uid": 1000,
            "username": "it140-test",
            "uname_s": "Darwin",
            "uname_m": "arm64",
            "sleep_calls": [],
        }

    @staticmethod
    def test_script_text(archive_url: str) -> str:
        source = PREPARE_SOURCE.read_text(encoding="utf-8")
        needle = f"readonly ARCHIVE_URL='{PRODUCTION_ARCHIVE_URL}'"
        replacement = f"readonly ARCHIVE_URL='{archive_url}'"
        if source.count(needle) != 1:
            raise RuntimeError("Expected exactly one production ARCHIVE_URL declaration")
        return source.replace(needle, replacement, 1)

    @staticmethod
    def _write_wrapper(path: Path, command_name: str, dispatcher: Path) -> None:
        interpreter = Path(sys.executable).resolve()
        path.write_text(
            "#!/bin/zsh\n"
            f"exec {shell_quote(str(interpreter))} {shell_quote(str(dispatcher))} "
            f"{shell_quote(command_name)} \"$@\"\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    @staticmethod
    def _placeholder(name: str) -> str:
        return "#!/bin/zsh\n" f"# macOS Prepare test placeholder for {name}\n" "exit 0\n"

    @classmethod
    def _build_archive(cls, prepare_text: str, mode: str) -> bytes:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            files: dict[str, str] = {
                "it140-main/.git/HEAD": "ref: refs/heads/main\n",
                "it140-main/managed/version.txt": "mac-prepare-characterization\n",
                "it140-main/scripts/mac/prepare_it140.zsh": prepare_text,
                "it140-main/scripts/mac/install_it140.zsh": cls._placeholder("install_it140.zsh"),
                "it140-main/scripts/mac/verify_it140.zsh": cls._placeholder("verify_it140.zsh"),
                "it140-main/scripts/mac/update_it140.zsh": cls._placeholder("update_it140.zsh"),
                "it140-main/scripts/.manifest/it140_manifest.json": '{"release":"mac-prepare-test"}\n',
                "it140-main/scripts/.manifest/it140_manifest.schema.json": '{"type":"object"}\n',
            }
            if mode != "missing_configure":
                files["it140-main/scripts/mac/configure_it140.zsh"] = cls._placeholder(
                    "configure_it140.zsh"
                )
            if mode == "malformed_manifest":
                files["it140-main/scripts/.manifest/it140_manifest.json"] = "{ invalid json\n"
            for relative, content in files.items():
                info = zipfile.ZipInfo(relative)
                info.create_system = 3
                info.external_attr = (0o755 if relative.endswith(".zsh") else 0o600) << 16
                archive.writestr(info, content.encode("utf-8"))
        return buffer.getvalue()

    def _seed_runtime_metadata(self, home: Path, prepare_text: str) -> None:
        course_root = home / "it140"
        student_git = home / "Repos" / "student-work" / ".git"
        student_git.mkdir(parents=True, exist_ok=True)
        (student_git / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")
        course_git = course_root / ".git"
        course_git.mkdir(parents=True, exist_ok=True)
        (course_git / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")

        mac_dir = course_root / "scripts" / "mac"
        manifest_dir = course_root / "scripts" / ".manifest"
        mac_dir.mkdir(parents=True, exist_ok=True)
        manifest_dir.mkdir(parents=True, exist_ok=True)
        (mac_dir / "prepare_it140.zsh").write_text(prepare_text, encoding="utf-8")
        for name in ("install_it140.zsh", "configure_it140.zsh", "verify_it140.zsh", "update_it140.zsh"):
            (mac_dir / name).write_text(f"#!/bin/zsh\n# prior critical {name}\nexit 0\n", encoding="utf-8")
        for path in mac_dir.glob("*.zsh"):
            path.chmod(0o755)
        (manifest_dir / "it140_manifest.json").write_text('{"prior":true}\n', encoding="utf-8")
        (manifest_dir / "it140_manifest.schema.json").write_text('{"prior_schema":true}\n', encoding="utf-8")

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "nested_repo_git": home / "Repos" / "student-work" / ".git",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home / "Library" / "Application Support" / "Other App" / "prefs.txt",
            "git_config": home / ".gitconfig",
        }

    @staticmethod
    def _critical_paths(home: Path) -> dict[str, Path]:
        course_root = home / "it140"
        return {
            "prepare": course_root / "scripts" / "mac" / "prepare_it140.zsh",
            "install": course_root / "scripts" / "mac" / "install_it140.zsh",
            "configure": course_root / "scripts" / "mac" / "configure_it140.zsh",
            "verify": course_root / "scripts" / "mac" / "verify_it140.zsh",
            "update": course_root / "scripts" / "mac" / "update_it140.zsh",
            "manifest": course_root / "scripts" / ".manifest" / "it140_manifest.json",
            "schema": course_root / "scripts" / ".manifest" / "it140_manifest.schema.json",
        }

    def _prepare_fixture(
        self, temp_root: Path, scenario: dict[str, Any], server: ArchiveServer
    ) -> tuple[Path, Path, Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root, symlinks=True)
        home = fixture_root / "home"
        tmp_dir = temp_root / "tmp"
        tmp_dir.mkdir()

        prepare_text = self.test_script_text(server.url)
        self._seed_runtime_metadata(home, prepare_text)
        if scenario.get("fixture_overrides", {}).get("path_file_unreadable"):
            (home / ".zshrc").chmod(0o000)
        archive_mode = str(scenario.get("archive", "valid"))
        server.set_payload(self._build_archive(prepare_text, archive_mode))

        state = self._merge(self._default_state(), scenario.get("mock_overrides", {}))
        state_path = temp_root / "mock-state.json"
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        trace_path = temp_root / "mock-trace.jsonl"
        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir()
        for command in ("id", "uname", "sleep"):
            self._write_wrapper(mock_dir / command, command, self.mock_dispatcher)
        return home, tmp_dir, mock_dir, state_path, trace_path

    @staticmethod
    def _environment(
        home: Path, tmp_dir: Path, mock_dir: Path, state_path: Path, trace_path: Path
    ) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(home),
                "TMPDIR": str(tmp_dir) + "/",
                "PATH": f"{mock_dir}:{env.get('PATH', '')}",
                "IT140_MOCK_STATE": str(state_path),
                "IT140_MOCK_TRACE": str(trace_path),
            }
        )
        return env

    @staticmethod
    def _wait_for_log(log_file: Path | None) -> None:
        if log_file is None:
            return
        for _ in range(80):
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
        server: ArchiveServer,
        home: Path,
        tmp_dir: Path,
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
        arguments: list[str] | None = None,
    ) -> PrepareRun:
        protected = self._protected_paths(home)
        before = _snapshot(protected)
        critical_before = _snapshot(self._critical_paths(home))
        log_dir = home / "it140" / "logs"
        before_logs = set(log_dir.glob("prepare_ide_*.log")) if log_dir.exists() else set()
        env = self._environment(home, tmp_dir, mock_dir, state_path, trace_path)
        prepare_path = home / "it140" / "scripts" / "mac" / "prepare_it140.zsh"
        stdout_path = temp_root / f"stdout-{time.time_ns()}.txt"
        stderr_path = temp_root / f"stderr-{time.time_ns()}.txt"
        with stdout_path.open("w", encoding="utf-8") as out, stderr_path.open("w", encoding="utf-8") as err:
            completed = subprocess.run(
                [str(ZSH_EXECUTABLE), str(prepare_path), *(arguments or [])],
                cwd=home,
                env=env,
                text=True,
                stdout=out,
                stderr=err,
                check=False,
                timeout=45,
            )
        stdout = stdout_path.read_text(encoding="utf-8")
        stderr = stderr_path.read_text(encoding="utf-8")
        after = _snapshot(protected)
        critical_after = _snapshot(self._critical_paths(home))
        after_logs = set(log_dir.glob("prepare_ide_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_log(log_file)
        transcript = parse_prepare_log(log_file) if log_file else None
        return PrepareRun(
            scenario_id=scenario["id"], root=temp_root, returncode=completed.returncode,
            stdout=stdout, stderr=stderr, home=home, tmp_dir=tmp_dir, log_dir=log_dir,
            log_file=log_file, transcript=transcript,
            protected_differences=_differences(before, after), trace_file=trace_path,
            state_file=state_path, request_count=server.request_count,
            request_paths=server.request_paths, critical_before=critical_before,
            critical_after=critical_after,
        )

    def run_scenario(
        self, scenario: dict[str, Any], arguments: list[str] | None = None
    ) -> PrepareRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-prepare-mac-"))
        server = ArchiveServer(int(scenario.get("http_status", 200)))
        server.start()
        try:
            prepared = self._prepare_fixture(temp_root, scenario, server)
            return self._execute(scenario, temp_root, server, *prepared, arguments=arguments)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
        finally:
            server.close()

    @staticmethod
    def _semantic_state(run: PrepareRun) -> dict[str, Any]:
        home = run.home
        course_root = home / "it140"
        script_modes: dict[str, int | None] = {}
        for name in (
            "prepare_it140.zsh", "install_it140.zsh", "configure_it140.zsh",
            "verify_it140.zsh", "update_it140.zsh",
        ):
            path = course_root / "scripts" / "mac" / name
            script_modes[name] = stat.S_IMODE(path.stat().st_mode) if path.exists() else None
        return {
            "managed_version": (
                (course_root / "managed" / "version.txt").read_text(encoding="utf-8")
                if (course_root / "managed" / "version.txt").is_file()
                else None
            ),
            "manifest": (
                (course_root / "scripts" / ".manifest" / "it140_manifest.json").read_text(encoding="utf-8")
                if (course_root / "scripts" / ".manifest" / "it140_manifest.json").is_file()
                else None
            ),
            "zshrc": (home / ".zshrc").read_text(encoding="utf-8"),
            "top_level_git": (course_root / ".git").exists(),
            "script_modes": script_modes,
            "protected": _snapshot(MacPrepareHarness._protected_paths(home)),
            "course_unmanaged": _digest(course_root / "local-unmanaged.txt"),
            "mac_legacy_marker": _digest(course_root / "scripts" / "mac" / "legacy_marker.txt"),
        }

    def run_twice(self, scenario: dict[str, Any]) -> PrepareSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-prepare-mac-twice-"))
        server = ArchiveServer(int(scenario.get("http_status", 200)))
        server.start()
        try:
            prepared = self._prepare_fixture(temp_root, scenario, server)
            first = self._execute(scenario, temp_root, server, *prepared)
            first_state = self._semantic_state(first)
            time.sleep(1.05)
            second = self._execute(scenario, temp_root, server, *prepared)
            second_state = self._semantic_state(second)
            return PrepareSequence(temp_root, first, second, first_state, second_state)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
        finally:
            server.close()


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"
