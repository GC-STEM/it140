#!/usr/bin/env python3
"""Black-box harness for CVD update_it140.sh lifecycle tests."""

from __future__ import annotations

from dataclasses import dataclass
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[4]
UPDATE_SOURCE = REPO_ROOT / "scripts" / "cvd" / "update_it140.sh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
BASH_EXECUTABLE = shutil.which("bash")
if BASH_EXECUTABLE is None:
    raise RuntimeError("CVD Update lifecycle tests require Bash on PATH")


@dataclass
class UpdateTranscript:
    path: Path
    text: str
    summary: dict[str, str]


@dataclass
class UpdateRun:
    scenario_id: str
    root: Path
    returncode: int
    stdout: str
    stderr: str
    home: Path
    system_root: Path
    log_dir: Path
    log_file: Path | None
    transcript: UpdateTranscript | None
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
            sections.append("Update transcript:\n" + self.transcript.text.rstrip())
        if self.trace_file.is_file():
            trace = self.trace_file.read_text(encoding="utf-8").strip()
            if trace:
                sections.append("Mock command trace:\n" + trace)
        if self.state_file.is_file():
            state = self.state_file.read_text(encoding="utf-8").strip()
            if state:
                sections.append("Update test state:\n" + state)
        return "\n\n".join(sections)


@dataclass
class UpdateSequence:
    root: Path
    first: UpdateRun
    second: UpdateRun
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


def parse_update_log(path: Path) -> UpdateTranscript:
    text = path.read_text(encoding="utf-8", errors="replace")
    summary: dict[str, str] = {}
    in_summary = False
    for raw_line in text.splitlines():
        line = raw_line.strip("\ufeff\r\n")
        if line == "UPDATE SUMMARY":
            in_summary = True
            continue
        if not in_summary or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key in {
            "Conclusion", "Result", "Script version", "Version DTG",
            "Manifest release", "Manifest DTG", "Warnings", "Failures",
            "Restart required", "Start time", "End time", "Managed changes",
            "Elapsed time", "Next step", "Log file", "Exit code",
        }:
            summary[key] = value.strip()
    return UpdateTranscript(path=path, text=text, summary=summary)


class CvdUpdateHarness:
    """Build and execute isolated CVD Update scenarios."""

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
                merged[key] = CvdUpdateHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _manifest_requirements(manifest: dict[str, Any]) -> tuple[list[str], list[str], list[str]]:
        platform = manifest["platforms"]["cvd"]
        bindings = platform["course_ide_bindings"]
        system_packages = {
            item["package_identifier"]
            for item in platform.get("os_packages", {}).values()
            if item.get("required")
        }
        venv_packages: set[str] = set()
        extensions: set[str] = set()
        for role, binding in bindings.items():
            if not binding.get("required"):
                continue
            scope = binding.get("installation_scope")
            adapter = binding.get("installer_adapter_id")
            identifier = binding.get("package_identifier")
            if scope == "system" and adapter == "apt_package" and identifier:
                system_packages.add(identifier)
            if scope == "user" and adapter == "python_venv_package" and identifier:
                venv_packages.add(identifier)
            if role == "code_quality_tool":
                venv_packages.add("ruff")
            if scope == "user" and adapter == "vscode_extension" and identifier:
                extensions.add(identifier)
        return sorted(system_packages), sorted(venv_packages), sorted(extensions)

    @classmethod
    def _default_mock_state(cls, manifest: dict[str, Any]) -> dict[str, Any]:
        system_packages, venv_packages, extensions = cls._manifest_requirements(manifest)
        return {
            "architecture": "amd64",
            "sudo_noninteractive": True,
            "free_space_bytes": 100 * 1024**3,
            "installed_packages": system_packages,
            "package_versions": {"fonts-noto-color-emoji": "1.0-test"},
            "font_healthy": True,
            "desktop_file_valid": True,
            "venv_packages": venv_packages,
            "extensions": extensions,
            "gh_auth": True,
            "git_config": {
                "user.name": "IT 140 Test Student",
                "user.email": "12345+it140-test@users.noreply.github.com",
            },
            "numlock_on": True,
            "repos_emblem": "development",
            "launcher_checksum": "",
            "fail_points": {},
            "skip_install_packages": [],
            "skip_venv_packages": [],
            "skip_extensions": [],
            "command_exit_codes": {},
            "archive_download_count": 0,
            "apt_update_count": 0,
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
    def _write_venv_python(path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "#!/usr/bin/env bash\n"
            "export IT140_MOCK_COMMAND='venv-python'\n"
            'exec "$IT140_MOCK_PYTHON" "$IT140_MOCK_DISPATCHER" "$@"\n',
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    @staticmethod
    def _build_archive(
        archive_path: Path,
        manifest_path: Path,
        schema_path: Path,
        mode: str = "same",
    ) -> None:
        manifest_bytes = manifest_path.read_bytes()
        schema_bytes = schema_path.read_bytes()
        if mode == "reformatted":
            manifest_obj = json.loads(manifest_bytes.decode("utf-8"))
            manifest_bytes = (json.dumps(manifest_obj, separators=(",", ":")) + "\n").encode()
        elif mode == "malformed":
            manifest_bytes = b"{ downloaded manifest is invalid\n"
        with tarfile.open(archive_path, "w:gz") as archive:
            for relative, payload in (
                ("it140-main/scripts/.manifest/it140_manifest.json", manifest_bytes),
                ("it140-main/scripts/.manifest/it140_manifest.schema.json", schema_bytes),
            ):
                info = tarfile.TarInfo(relative)
                info.size = len(payload)
                info.mode = 0o600
                archive.addfile(info, io.BytesIO(payload))

    def _prepare_fixture(
        self, temp_root: Path, scenario: dict[str, Any]
    ) -> tuple[Path, Path, Path, Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root)
        home = fixture_root / "home"
        system_root = fixture_root / "system"
        course_root = home / "it140"
        manifest_dir = course_root / "scripts" / ".manifest"
        cvd_dir = course_root / "scripts" / "cvd"
        manifest_dir.mkdir(parents=True, exist_ok=True)
        cvd_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(UPDATE_SOURCE, cvd_dir / UPDATE_SOURCE.name)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        fixture_overrides = scenario.get("fixture_overrides", {})
        if fixture_overrides.get("manifest") == "malformed":
            (manifest_dir / MANIFEST_SOURCE.name).write_text(
                "{ this is not valid JSON\n", encoding="utf-8"
            )
        if fixture_overrides.get("os_release") == "unsupported":
            (system_root / "etc" / "os-release").write_text(
                'PRETTY_NAME="Ubuntu 22.04 LTS"\nID=ubuntu\nVERSION_ID="22.04"\n',
                encoding="utf-8",
            )
        if fixture_overrides.get("reboot_required"):
            reboot = system_root / "var" / "run" / "reboot-required"
            reboot.parent.mkdir(parents=True, exist_ok=True)
            reboot.write_text("System restart required\n", encoding="utf-8")

        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        state = self._merge(self._default_mock_state(manifest), scenario.get("mock_overrides", {}))

        font_file = system_root / "usr" / "share" / "fonts" / "test" / "NotoColorEmoji.ttf"
        font_file.parent.mkdir(parents=True, exist_ok=True)
        font_file.write_bytes(b"test-font-placeholder\n")
        state["font_file"] = str(font_file)

        repos_root = home / "Repos"
        desktop = home / "Desktop"
        desktop.mkdir(parents=True, exist_ok=True)
        shortcut = desktop / "Repos"
        if shortcut.exists() or shortcut.is_symlink():
            shortcut.unlink()
        shortcut.symlink_to(repos_root, target_is_directory=True)
        launcher = desktop / "visual-studio-code.desktop"
        launcher.write_text(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=Visual Studio Code\n"
            f'Exec=code "{repos_root}"\n'
            f"Path={repos_root}\n"
            "Terminal=false\n",
            encoding="utf-8",
        )
        launcher.chmod(0o755)
        state["launcher_checksum"] = hashlib.sha256(launcher.read_bytes()).hexdigest()

        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        for command in (
            "code", "curl", "desktop-file-validate", "df", "dpkg", "dpkg-query",
            "fc-cache", "fc-list", "fc-match", "gh", "git", "gio", "numlockx",
            "pgrep", "python3.12", "sleep", "sudo", "xclip", "xdg-user-dir",
        ):
            self._write_mock_wrapper(mock_dir / command, command)

        self._write_venv_python(course_root / ".venv" / "bin" / "python")

        archive_path = temp_root / "it140-main.tar.gz"
        self._build_archive(
            archive_path,
            MANIFEST_SOURCE,
            SCHEMA_SOURCE,
            fixture_overrides.get("archive_manifest", "same"),
        )
        state["archive_path"] = str(archive_path)

        state_path = temp_root / "mock-state.json"
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        trace_path = temp_root / "mock-trace.jsonl"
        return home, system_root, mock_dir, state_path, trace_path, archive_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home / ".config" / "other-app" / "prefs.txt",
            "git_config": home / ".gitconfig",
            "bashrc": home / ".bashrc",
            "profile": home / ".profile",
        }

    def _environment(
        self,
        home: Path,
        system_root: Path,
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
        temp_root: Path,
    ) -> dict[str, str]:
        env = os.environ.copy()
        tmp_dir = temp_root / "tmp"
        tmp_dir.mkdir(exist_ok=True)
        env.update(
            {
                "HOME": str(home),
                "TMPDIR": str(tmp_dir),
                "PATH": f"{mock_dir}:{env.get('PATH', '')}",
                "IT140_UPDATE_TEST_MODE": "true",
                "IT140_UPDATE_TEST_ROOT": str(system_root),
                "IT140_UPDATE_TEST_EUID": "1000",
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
        home: Path,
        system_root: Path,
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
    ) -> UpdateRun:
        protected = self._protected_paths(home)
        before = _snapshot(protected)
        log_dir = home / "it140" / "logs"
        before_logs = set(log_dir.glob("update_cvd_*.log")) if log_dir.exists() else set()
        env = self._environment(home, system_root, mock_dir, state_path, trace_path, temp_root)
        update_path = home / "it140" / "scripts" / "cvd" / "update_it140.sh"
        command = [BASH_EXECUTABLE, str(update_path), *scenario.get("arguments", [])]
        process = subprocess.Popen(
            command,
            cwd=home,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=90)
        except subprocess.TimeoutExpired as exc:
            # Update starts a tee process substitution and may have child command
            # mocks. Kill the whole test process group so a timed-out scenario
            # cannot leave a descendant holding the captured pipes open.
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            raise RuntimeError(
                f"CVD Update scenario {scenario['id']!r} exceeded 90 seconds.\n"
                f"Captured stdout:\n{stdout}\nCaptured stderr:\n{stderr}"
            ) from exc
        completed = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
        after = _snapshot(protected)
        after_logs = set(log_dir.glob("update_cvd_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_log(log_file)
        transcript = parse_update_log(log_file) if log_file else None
        return UpdateRun(
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

    def run_scenario(self, scenario: dict[str, Any]) -> UpdateRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-update-cvd-"))
        try:
            home, system_root, mock_dir, state_path, trace_path, _archive = self._prepare_fixture(
                temp_root, scenario
            )
            return self._execute(
                scenario, temp_root, home, system_root, mock_dir, state_path, trace_path
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    @staticmethod
    def _semantic_state(run: UpdateRun) -> dict[str, Any]:
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        for key in ("apt_update_count", "archive_download_count"):
            state.pop(key, None)
        state.pop("archive_path", None)
        system_files: dict[str, str | None] = {}
        for relative in ("etc/xdg/autostart/numlockx.desktop",):
            path = run.system_root / relative
            system_files[relative] = path.read_text(encoding="utf-8") if path.is_file() else None
        manifest = run.home / "it140" / "scripts" / ".manifest" / "it140_manifest.json"
        schema = run.home / "it140" / "scripts" / ".manifest" / "it140_manifest.schema.json"
        return {
            "mock_state": state,
            "system_files": system_files,
            "manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
            "schema_sha256": hashlib.sha256(schema.read_bytes()).hexdigest(),
        }

    def run_twice(self, scenario: dict[str, Any]) -> UpdateSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-update-cvd-twice-"))
        try:
            home, system_root, mock_dir, state_path, trace_path, _archive = self._prepare_fixture(
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
            return UpdateSequence(temp_root, first, second, first_state, second_state)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
