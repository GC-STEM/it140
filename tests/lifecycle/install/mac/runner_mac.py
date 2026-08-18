#!/usr/bin/env python3
"""Black-box harness for macOS install_it140.zsh lifecycle tests."""

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
INSTALL_SOURCE = REPO_ROOT / "scripts" / "mac" / "install_it140.zsh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
ZSH_EXECUTABLE = Path("/bin/zsh")


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
    log_dir: Path
    log_file: Path | None
    transcript: InstallTranscript | None
    protected_differences: list[str]
    trace_file: Path
    state_file: Path
    mock_dir: Path

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
    return {key: _digest(value) for key, value in paths.items()}


def _differences(before: dict[str, str | None], after: dict[str, str | None]) -> list[str]:
    return sorted(key for key in before if before[key] != after[key])


def parse_install_log(path: Path) -> InstallTranscript:
    text = path.read_text(encoding="utf-8", errors="replace")
    summary: dict[str, str] = {}
    in_summary = False
    accepted = {
        "Result", "Artifact ID", "Artifact version", "Version date-time group",
        "Development status", "Manifest release", "Manifest release DTG",
        "Deployment profile", "Workflow", "Starting state", "Operating role",
        "Managed changes", "Warnings", "Failures", "Elapsed time", "Detail",
        "Next step", "Log file", "Exit code",
    }
    for raw_line in text.splitlines():
        line = raw_line.strip("\ufeff\r\n")
        if line == "IT 140 macOS INSTALL SUMMARY":
            in_summary = True
            continue
        if not in_summary or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key in accepted:
            summary[key] = value.strip()
    return InstallTranscript(path=path, text=text, summary=summary)


class MacInstallHarness:
    """Build and execute isolated macOS Install scenarios."""

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
                merged[key] = MacInstallHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _system_bindings(manifest: dict[str, Any]) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for role, binding in manifest["platforms"]["macos"]["course_ide_bindings"].items():
            if (
                binding.get("required") is True
                and binding.get("installation_scope") == "system"
                and binding.get("installer_adapter_id") in {"homebrew_formula", "homebrew_cask"}
            ):
                rows.append(
                    {
                        "role": role,
                        "adapter": binding["installer_adapter_id"],
                        "package": binding["package_identifier"],
                        "commands": list(binding.get("verification", {}).get("executable_names", [])),
                    }
                )
        return rows

    def _default_state(self) -> dict[str, Any]:
        manifest = json.loads(MANIFEST_SOURCE.read_text(encoding="utf-8"))
        bindings = self._system_bindings(manifest)
        return {
            "installed_formulas": [],
            "installed_casks": [],
            "package_commands": {row["package"]: row["commands"] for row in bindings},
            "package_adapters": {row["package"]: row["adapter"] for row in bindings},
            "brew_update_count": 0,
            "brew_install_count": 0,
            "brew_install_failure_at": 0,
        }

    def _write_wrapper(self, path: Path, command_name: str) -> None:
        interpreter = Path(sys.executable).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "#!/bin/zsh\n"
            f"exec {shell_quote(str(interpreter))} {shell_quote(str(self.mock_dispatcher))} "
            f"{shell_quote(command_name)} \"$@\"\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def _prepare_fixture(
        self, temp_root: Path, scenario: dict[str, Any]
    ) -> tuple[Path, Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root, symlinks=True)
        home = fixture_root / "home"
        course_root = home / "it140"
        manifest_dir = course_root / "scripts" / ".manifest"
        mac_dir = course_root / "scripts" / "mac"
        manifest_dir.mkdir(parents=True, exist_ok=True)
        mac_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(INSTALL_SOURCE, mac_dir / INSTALL_SOURCE.name)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            (manifest_dir / MANIFEST_SOURCE.name).write_text(
                "{ this is not valid JSON\n", encoding="utf-8"
            )

        state = self._merge(self._default_state(), scenario.get("mock_overrides", {}))
        state_path = temp_root / "mock-state.json"
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        trace_path = temp_root / "mock-trace.jsonl"
        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        self._write_wrapper(mock_dir / "brew", "brew")
        # Keep host package executables out of PATH so Install decisions are
        # driven only by the scenario. Preserve only the real macOS facts that
        # production reads through PATH.
        for command in ("date", "id", "uname"):
            resolved = shutil.which(command)
            if resolved is None:
                raise RuntimeError(f"Required macOS host command is unavailable: {command}")
            (mock_dir / command).symlink_to(Path(resolved).resolve())
        return home, mock_dir, state_path, trace_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home / "Library" / "Application Support" / "Other App" / "prefs.txt",
            "git_config": home / ".gitconfig",
        }

    def _environment(
        self, home: Path, mock_dir: Path, state_path: Path, trace_path: Path, scenario: dict[str, Any]
    ) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(home),
                "PATH": str(mock_dir),
                "IT140_INSTALL_TEST_MODE": "true",
                "IT140_INSTALL_TEST_BREW_PATH": str(mock_dir / "brew"),
                "IT140_INSTALL_TEST_NETWORK_RESULT": scenario.get("network_result", "success"),
                "IT140_INSTALL_TEST_ADMIN_RESULT": scenario.get("admin_result", "true"),
                "IT140_MOCK_STATE": str(state_path),
                "IT140_MOCK_TRACE": str(trace_path),
                "IT140_MOCK_BIN": str(mock_dir),
                "IT140_MOCK_DISPATCHER": str(self.mock_dispatcher),
                "IT140_MOCK_PYTHON": str(Path(sys.executable).resolve()),
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
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
    ) -> InstallRun:
        protected = self._protected_paths(home)
        before = _snapshot(protected)
        log_dir = home / "it140" / "logs"
        before_logs = set(log_dir.glob("install_ide_*.log")) if log_dir.exists() else set()
        env = self._environment(home, mock_dir, state_path, trace_path, scenario)
        install_path = home / "it140" / "scripts" / "mac" / "install_it140.zsh"
        stdout_file = temp_root / f"stdout-{time.time_ns()}.txt"
        stderr_file = temp_root / f"stderr-{time.time_ns()}.txt"
        with stdout_file.open("w", encoding="utf-8") as out, stderr_file.open("w", encoding="utf-8") as err:
            completed = subprocess.run(
                [str(ZSH_EXECUTABLE), str(install_path), *scenario.get("arguments", [])],
                cwd=home,
                env=env,
                text=True,
                stdout=out,
                stderr=err,
                check=False,
                timeout=45,
            )
        stdout = stdout_file.read_text(encoding="utf-8")
        stderr = stderr_file.read_text(encoding="utf-8")
        after = _snapshot(protected)
        after_logs = set(log_dir.glob("install_ide_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_log(log_file)
        transcript = parse_install_log(log_file) if log_file else None
        return InstallRun(
            scenario_id=scenario["id"], root=temp_root, returncode=completed.returncode,
            stdout=stdout, stderr=stderr, home=home, log_dir=log_dir, log_file=log_file,
            transcript=transcript, protected_differences=_differences(before, after),
            trace_file=trace_path, state_file=state_path, mock_dir=mock_dir,
        )

    def run_scenario(self, scenario: dict[str, Any]) -> InstallRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-install-mac-"))
        try:
            home, mock_dir, state_path, trace_path = self._prepare_fixture(temp_root, scenario)
            return self._execute(scenario, temp_root, home, mock_dir, state_path, trace_path)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    @staticmethod
    def semantic_state(run: InstallRun) -> dict[str, Any]:
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        state.pop("brew_update_count", None)
        state.pop("brew_install_count", None)
        vscode = run.home / "Applications" / "Visual Studio Code.app"
        return {
            "installed_formulas": sorted(state.get("installed_formulas", []), key=str.lower),
            "installed_casks": sorted(state.get("installed_casks", []), key=str.lower),
            "vscode_app": vscode.is_dir(),
            "available_commands": sorted(
                path.name for path in run.mock_dir.iterdir() if path.is_file() and os.access(path, os.X_OK)
            ),
        }

    def run_twice(self, scenario: dict[str, Any]) -> InstallSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-install-mac-twice-"))
        try:
            home, mock_dir, state_path, trace_path = self._prepare_fixture(temp_root, scenario)
            first = self._execute(scenario, temp_root, home, mock_dir, state_path, trace_path)
            first_state = self.semantic_state(first)
            time.sleep(1.05)
            second = self._execute(scenario, temp_root, home, mock_dir, state_path, trace_path)
            second_state = self.semantic_state(second)
            return InstallSequence(temp_root, first, second, first_state, second_state)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"
