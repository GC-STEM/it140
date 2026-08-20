#!/usr/bin/env python3
"""Black-box harness for Windows prepare_it140.ps1 bootstrap tests."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any
import zipfile

REPO_ROOT = Path(__file__).resolve().parents[4]
PREPARE_SOURCE = REPO_ROOT / "scripts" / "win" / "prepare_it140.ps1"
POWERSHELL_EXECUTABLE = shutil.which("powershell.exe") or shutil.which("powershell")
PRODUCTION_ARCHIVE_URL = "https://github.com/GC-STEM/it140/archive/refs/heads/main.zip"


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
    temp_parent: Path
    log_dir: Path
    log_file: Path | None
    transcript: PrepareTranscript | None
    protected_differences: list[str]
    course_before: str | None
    course_after: str | None
    user_path_before: str
    user_path_after: str | None
    request_count: int
    request_paths: list[str]
    user_agents: list[str]

    @property
    def combined_output(self) -> str:
        sections: list[str] = []
        captured = self.stdout + self.stderr
        if captured.strip():
            sections.append("Captured process output:\n" + captured.rstrip())
        if self.transcript is not None and self.transcript.text.strip():
            sections.append("Prepare transcript:\n" + self.transcript.text.rstrip())
        sections.append(
            "Loopback archive requests:\n"
            + json.dumps(
                {
                    "count": self.request_count,
                    "paths": self.request_paths,
                    "user_agents": self.user_agents,
                },
                indent=2,
            )
        )
        sections.append(
            "Isolated user PATH:\n"
            + json.dumps(
                {"before": self.user_path_before, "after": self.user_path_after},
                indent=2,
            )
        )
        return "\n\n".join(sections)


@dataclass
class PrepareSequence:
    root: Path
    first: PrepareRun
    second: PrepareRun
    first_state: dict[str, Any]
    second_state: dict[str, Any]


def _read_text_flexible(path: Path) -> str:
    """Read PowerShell transcript/state text across Windows encoding variants."""
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16", errors="replace")
    if data.count(b"\x00") > max(2, len(data) // 8):
        return data.decode("utf-16-le", errors="replace")
    return data.decode("utf-8-sig", errors="replace")


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


def _course_payload_digest(course_root: Path) -> str | None:
    """Hash course-root state while excluding Prepare's expected logs directory."""
    if not course_root.exists():
        return None
    rows: list[str] = []
    for child in sorted(course_root.rglob("*")):
        rel = child.relative_to(course_root)
        if rel.parts and rel.parts[0].casefold() == "logs":
            continue
        rel_text = rel.as_posix()
        if child.is_symlink():
            rows.append(f"L {rel_text} {os.readlink(child)}")
        elif child.is_file():
            rows.append(f"F {rel_text} {hashlib.sha256(child.read_bytes()).hexdigest()}")
        else:
            rows.append(f"D {rel_text}")
    return hashlib.sha256("\n".join(rows).encode()).hexdigest()


def _differences(before: dict[str, str | None], after: dict[str, str | None]) -> list[str]:
    return sorted(name for name in before if before[name] != after[name])


def host_is_windows() -> bool:
    return sys.platform == "win32" and POWERSHELL_EXECUTABLE is not None


class _ArchiveHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        server = self.server
        server.request_count += 1  # type: ignore[attr-defined]
        server.request_paths.append(self.path)  # type: ignore[attr-defined]
        server.user_agents.append(self.headers.get("User-Agent", ""))  # type: ignore[attr-defined]
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
        self.httpd.user_agents = []  # type: ignore[attr-defined]
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

    @property
    def user_agents(self) -> list[str]:
        return list(self.httpd.user_agents)  # type: ignore[attr-defined]

    def set_payload(self, payload: bytes) -> None:
        self.httpd.payload = payload  # type: ignore[attr-defined]

    def start(self) -> None:
        self.thread.start()

    def close(self) -> None:
        self.httpd.shutdown()
        self.thread.join(timeout=5)
        self.httpd.server_close()


class WinPrepareHarness:
    """Build and execute isolated Windows bootstrap scenarios."""

    def __init__(self, fixture_base: Path):
        self.fixture_base = fixture_base

    @staticmethod
    def load_scenario(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _set_environment_variable(environment: dict[str, str], name: str, value: str) -> None:
        normalized_name = name.casefold()
        for existing_name in list(environment):
            if existing_name.casefold() == normalized_name:
                del environment[existing_name]
        environment[name] = value

    @staticmethod
    def transformation_pairs(archive_url: str) -> list[tuple[str, str, int]]:
        return [
            (
                f'$RepositoryArchive = "{PRODUCTION_ARCHIVE_URL}"',
                f'$RepositoryArchive = "{archive_url}"',
                1,
            ),
            (
                '[Environment]::GetFolderPath("UserProfile")',
                '$env:IT140_PREPARE_TEST_HOME',
                2,
            ),
            (
                '$ExistingUserPath = [Environment]::GetEnvironmentVariable("Path", "User")',
                '$ExistingUserPath = $env:IT140_PREPARE_TEST_USER_PATH',
                1,
            ),
            (
                '[Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")',
                '$env:IT140_PREPARE_TEST_USER_PATH = $NewUserPath\n'
                '    Set-Content -LiteralPath $env:IT140_PREPARE_TEST_USER_PATH_STATE '
                '-Value $NewUserPath -Encoding UTF8',
                1,
            ),
        ]

    @classmethod
    def test_script_text(cls, archive_url: str) -> str:
        source = PREPARE_SOURCE.read_text(encoding="utf-8-sig")
        transformed = source
        for original, replacement, expected_count in cls.transformation_pairs(archive_url):
            actual = transformed.count(original)
            if actual != expected_count:
                raise RuntimeError(
                    f"Expected {expected_count} occurrence(s) of {original!r}; found {actual}"
                )
            transformed = transformed.replace(original, replacement)
        return transformed

    @staticmethod
    def _placeholder(name: str) -> str:
        return (
            "# Windows Prepare lifecycle test placeholder\r\n"
            f'Write-Output "{name} placeholder"\r\n'
        )

    @classmethod
    def _build_archive(cls, mode: str) -> bytes:
        source_text = PREPARE_SOURCE.read_text(encoding="utf-8-sig")
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            if mode == "no_repository_root":
                archive.writestr("not-a-directory.txt", "invalid archive structure\n")
                return buffer.getvalue()

            files: dict[str, str] = {
                "it140-main/.git/HEAD": "ref: refs/heads/main\n",
                "it140-main/managed/version.txt": "windows-prepare-characterization\n",
                "it140-main/scripts/.manifest/it140_manifest.json": '{"release":"win-prepare-test"}\n',
                "it140-main/scripts/.manifest/it140_manifest.schema.json": '{"type":"object"}\n',
            }
            if mode != "missing_windows_scripts":
                files["it140-main/scripts/win/prepare_it140.ps1"] = source_text
                for name in (
                    "install_it140.ps1",
                    "configure_it140.ps1",
                    "verify_it140.ps1",
                    "update_it140.ps1",
                ):
                    files[f"it140-main/scripts/win/{name}"] = cls._placeholder(name)
            for relative, content in files.items():
                archive.writestr(relative, content.encode("utf-8"))
        return buffer.getvalue()

    @staticmethod
    def _new_temp_root(prefix: str) -> Path:
        # Match the existing Windows lifecycle harnesses: normalize away any
        # 8.3 alias exposed by the hosted runner before comparing path strings.
        return Path(tempfile.mkdtemp(prefix=prefix)).resolve()

    def _prepare_fixture(
        self, temp_root: Path, scenario: dict[str, Any], server: ArchiveServer
    ) -> tuple[Path, Path, Path, Path, str]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root)
        home = (fixture_root / "home").resolve()
        temp_parent = (temp_root / "temp").resolve()
        temp_parent.mkdir()

        # Git metadata used to verify preservation must be synthesized at
        # runtime; nested .git directories are not stored as repository fixtures.
        student_git = home / "Repos" / "student-work" / ".git"
        student_git.mkdir(parents=True, exist_ok=True)
        (student_git / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")

        script_path = temp_root / "prepare-under-test.ps1"
        script_path.write_text(self.test_script_text(server.url), encoding="utf-8-sig")
        server.set_payload(self._build_archive(str(scenario.get("archive", "valid"))))

        target_path = str((home / "it140" / "scripts" / "win").resolve())
        initial_user_path = f"{target_path}\\;C:\\UserTools;{target_path};C:\\AnotherTool"
        path_state = temp_root / "user-path-state.txt"
        if scenario.get("path_state_failure"):
            path_state.mkdir()
        return home, temp_parent, script_path, path_state, initial_user_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "student_git": home / "Repos" / "student-work" / ".git",
            "gitconfig": home / ".gitconfig",
            "other_app": home / "AppData" / "Roaming" / "Other App",
            "personal_desktop": home / "Desktop" / "Personal Notes.txt",
        }

    def _environment(
        self,
        home: Path,
        temp_parent: Path,
        path_state: Path,
        initial_user_path: str,
        download_mode: str,
    ) -> dict[str, str]:
        env = os.environ.copy()
        controlled = {
            "HOME": str(home),
            "USERPROFILE": str(home),
            "APPDATA": str(home / "AppData" / "Roaming"),
            "LOCALAPPDATA": str(home / "AppData" / "Local"),
            "TEMP": str(temp_parent),
            "TMP": str(temp_parent),
            "IT140_PREPARE_TEST_HOME": str(home),
            "IT140_PREPARE_TEST_USER_PATH": initial_user_path,
            "IT140_PREPARE_TEST_USER_PATH_STATE": str(path_state),
        }
        if download_mode == "invoke_web_request":
            # PowerShell cmdlets remain available without PATH. Removing the
            # inherited executable search path makes Get-Command curl.exe fail
            # deterministically so the production fallback branch runs.
            controlled["PATH"] = str(temp_parent / "no-curl-bin")
            Path(controlled["PATH"]).mkdir(exist_ok=True)
        for name, value in controlled.items():
            self._set_environment_variable(env, name, value)
        return env

    @staticmethod
    def _read_user_path_state(path: Path) -> str | None:
        if not path.is_file():
            return None
        return _read_text_flexible(path).strip()

    @staticmethod
    def _wait_for_transcript(path: Path | None) -> None:
        if path is None:
            return
        for _ in range(60):
            try:
                if path.stat().st_size > 0:
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
        temp_parent: Path,
        script_path: Path,
        path_state: Path,
        initial_user_path: str,
    ) -> PrepareRun:
        if POWERSHELL_EXECUTABLE is None:
            raise RuntimeError("Windows PowerShell executable was not found")

        protected = self._protected_paths(home)
        before = _snapshot(protected)
        course_root = home / "it140"
        course_before = _course_payload_digest(course_root)
        log_dir = course_root / "logs"
        before_logs = set(log_dir.glob("prepare_ide_*.log")) if log_dir.exists() else set()
        environment = self._environment(
            home,
            temp_parent,
            path_state,
            initial_user_path,
            str(scenario.get("download_mode", "curl")),
        )
        completed = subprocess.run(
            [
                POWERSHELL_EXECUTABLE,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script_path),
            ],
            cwd=home,
            env=environment,
            capture_output=True,
            text=True,
            timeout=45,
            check=False,
        )
        after = _snapshot(protected)
        course_after = _course_payload_digest(course_root)
        after_logs = set(log_dir.glob("prepare_ide_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_transcript(log_file)
        transcript = None
        if log_file is not None:
            transcript = PrepareTranscript(
                path=log_file,
                text=_read_text_flexible(log_file),
            )
        return PrepareRun(
            scenario_id=str(scenario["id"]),
            root=temp_root,
            returncode=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
            home=home,
            temp_parent=temp_parent,
            log_dir=log_dir,
            log_file=log_file,
            transcript=transcript,
            protected_differences=_differences(before, after),
            course_before=course_before,
            course_after=course_after,
            user_path_before=initial_user_path,
            user_path_after=self._read_user_path_state(path_state),
            request_count=server.request_count,
            request_paths=server.request_paths,
            user_agents=server.user_agents,
        )

    def run_scenario(self, scenario: dict[str, Any]) -> PrepareRun:
        temp_root = self._new_temp_root("it140-prepare-win-")
        server = ArchiveServer(int(scenario.get("http_status", 200)))
        server.start()
        try:
            prepared = self._prepare_fixture(temp_root, scenario, server)
            return self._execute(scenario, temp_root, server, *prepared)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
        finally:
            server.close()

    @staticmethod
    def semantic_state(run: PrepareRun) -> dict[str, Any]:
        home = run.home
        course_root = home / "it140"
        win_dir = course_root / "scripts" / "win"
        scripts = {}
        for name in (
            "prepare_it140.ps1",
            "install_it140.ps1",
            "configure_it140.ps1",
            "verify_it140.ps1",
            "update_it140.ps1",
        ):
            scripts[name] = _digest(win_dir / name)
        return {
            "managed_version": (
                (course_root / "managed" / "version.txt").read_text(encoding="utf-8")
                if (course_root / "managed" / "version.txt").is_file()
                else None
            ),
            "scripts": scripts,
            "top_level_git": (course_root / ".git").exists(),
            "user_path": run.user_path_after,
            "protected": _snapshot(WinPrepareHarness._protected_paths(home)),
            "course_unmanaged": _digest(course_root / "local-unmanaged.txt"),
            "prior_package": _digest(course_root / "prior-package.txt"),
        }

    def run_twice(self, scenario: dict[str, Any]) -> PrepareSequence:
        temp_root = self._new_temp_root("it140-prepare-win-twice-")
        server = ArchiveServer(int(scenario.get("http_status", 200)))
        server.start()
        try:
            prepared = self._prepare_fixture(temp_root, scenario, server)
            first = self._execute(scenario, temp_root, server, *prepared)
            first_state = self.semantic_state(first)
            # Feed the first persistent user-PATH result into the second run and
            # ensure the transcript timestamp cannot collide.
            if first.user_path_after is not None:
                prepared = (*prepared[:-1], first.user_path_after)
            time.sleep(1.05)
            second = self._execute(scenario, temp_root, server, *prepared)
            second_state = self.semantic_state(second)
            return PrepareSequence(
                root=temp_root,
                first=first,
                second=second,
                first_state=first_state,
                second_state=second_state,
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
        finally:
            server.close()
