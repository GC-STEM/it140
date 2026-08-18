#!/usr/bin/env python3
"""Black-box harness for Windows install_it140.ps1 lifecycle tests."""

from __future__ import annotations

import copy
from dataclasses import dataclass
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Any

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.configure_log import ConfigureTranscript, parse_configure_log  # noqa: E402
from common.snapshot import snapshot_differences, snapshot_paths  # noqa: E402

REPO_ROOT = LIFECYCLE_ROOT.parents[1]
INSTALL_SOURCE = REPO_ROOT / "scripts" / "win" / "install_it140.ps1"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
POWERSHELL_EXECUTABLE = shutil.which("powershell.exe") or shutil.which("powershell")


@dataclass
class InstallRun:
    """Captured state for one production Install execution."""

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
    state_path: Path

    @property
    def combined_output(self) -> str:
        sections: list[str] = []
        captured = self.stdout + self.stderr
        if captured.strip():
            sections.append("Captured process output:\n" + captured.rstrip())
        if self.transcript is not None and self.transcript.text.strip():
            sections.append("Install transcript:\n" + self.transcript.text.rstrip())
        if self.state_path.is_file():
            sections.append(
                "Install test state:\n"
                + self.state_path.read_text(encoding="utf-8", errors="replace").rstrip()
            )
        return "\n\n".join(sections)


@dataclass
class InstallSequence:
    """Two successful Install executions against one mutable fixture."""

    root: Path
    first: InstallRun
    second: InstallRun
    first_state: dict[str, Any]
    second_state: dict[str, Any]


class WinInstallHarness:
    """Build and execute isolated Windows Install scenarios."""

    def __init__(self, fixture_base: Path):
        self.fixture_base = fixture_base

    @staticmethod
    def load_scenario(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _merge(base: dict[str, Any], overrides: dict[str, Any]) -> dict[str, Any]:
        merged = copy.deepcopy(base)
        for key, value in overrides.items():
            if isinstance(value, dict) and isinstance(merged.get(key), dict):
                merged[key] = WinInstallHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _load_manifest(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _set_environment_variable(
        environment: dict[str, str], name: str, value: str
    ) -> None:
        normalized_name = name.casefold()
        for existing_name in list(environment):
            if existing_name.casefold() == normalized_name:
                del environment[existing_name]
        environment[name] = value

    @staticmethod
    def _bindings(manifest: dict[str, Any]) -> list[dict[str, Any]]:
        bindings: list[dict[str, Any]] = []
        for role, binding in manifest["platforms"]["windows"]["course_ide_bindings"].items():
            if (
                binding.get("required")
                and binding.get("installation_scope") == "system"
                and binding.get("installer_adapter_id") == "winget_package"
            ):
                bindings.append(
                    {
                        "role": role,
                        "package_identifier": str(binding["package_identifier"]),
                        "executable_names": [
                            str(value)
                            for value in binding.get("verification", {}).get(
                                "executable_names", []
                            )
                        ],
                    }
                )
        return bindings

    @classmethod
    def package_commands(cls, manifest: dict[str, Any]) -> dict[str, list[str]]:
        return {
            binding["package_identifier"]: binding["executable_names"]
            for binding in cls._bindings(manifest)
        }

    @classmethod
    def required_commands(cls, manifest: dict[str, Any]) -> set[str]:
        commands: set[str] = set()
        for binding in cls._bindings(manifest):
            commands.update(binding["executable_names"])
        return commands

    @classmethod
    def external_compatible_binding(cls, manifest: dict[str, Any]) -> dict[str, Any]:
        for binding in cls._bindings(manifest):
            if binding["role"] == "version_control_system":
                return binding
        return cls._bindings(manifest)[0]

    @classmethod
    def _default_state(cls, manifest: dict[str, Any]) -> dict[str, Any]:
        releases = manifest["platforms"]["windows"]["os"]["releases"]
        release = str(releases[0]["release_id"])
        external = cls.external_compatible_binding(manifest)
        minimum_space = int(manifest["policy"]["minimum_free_space_bytes"])
        return {
            "is_administrator": True,
            "windows_facts": {
                "Caption": "Microsoft Windows 11 Pro",
                "Architecture": "64-bit",
                "DisplayVersion": release,
                "BuildNumber": "28000",
            },
            "free_space_bytes": max(minimum_space + 1024**3, 10 * 1024**3),
            "winget_available": True,
            "winget_packages": [],
            # One compatible application is deliberately external to WinGet so
            # success also proves package-manager provenance is not required.
            "available_commands": list(external["executable_names"]),
            "python_version": "3.12",
            "package_commands": cls.package_commands(manifest),
            "command_exit_codes": {},
            "command_versions": {
                "git.exe": "git version lifecycle-test",
                "gh.exe": "gh version lifecycle-test",
                "python.exe": "Python 3.12.lifecycle-test",
                "code.cmd": "1.lifecycle-test",
            },
            "fail_points": {},
        }

    def _prepare_fixture(
        self, temp_root: Path, scenario: dict[str, Any]
    ) -> tuple[Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root)
        home = fixture_root / "home"
        course_root = home / "it140"
        scripts_root = course_root / "scripts"
        win_dir = scripts_root / "win"
        manifest_dir = scripts_root / ".manifest"
        log_dir = course_root / "logs"
        win_dir.mkdir(parents=True, exist_ok=True)
        manifest_dir.mkdir(parents=True, exist_ok=True)
        log_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(INSTALL_SOURCE, win_dir / INSTALL_SOURCE.name)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        manifest = self._load_manifest(MANIFEST_SOURCE)
        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")

        state = self._merge(
            self._default_state(manifest), scenario.get("state_overrides", {})
        )
        if scenario.get("fixture_overrides", {}).get("fail_first_install_capability"):
            external = self.external_compatible_binding(manifest)["package_identifier"]
            target = next(
                binding["package_identifier"]
                for binding in self._bindings(manifest)
                if binding["package_identifier"] != external
            )
            state.setdefault("fail_points", {})["install_capability_missing"] = target

        state_path = fixture_root / "install_state.json"
        state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
        return fixture_root, home, state_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "gitconfig": home / ".gitconfig",
            "other_app": home / "AppData" / "Roaming" / "Other App",
            "personal_desktop": home / "Desktop" / "Personal Notes.txt",
            "student_repos": home / "Repos",
        }

    def _execute(
        self,
        scenario_id: str,
        root: Path,
        home: Path,
        state_path: Path,
        arguments: list[str],
        protected_before,
    ) -> InstallRun:
        if POWERSHELL_EXECUTABLE is None:
            raise RuntimeError("Windows PowerShell executable was not found")
        script = home / "it140" / "scripts" / "win" / "install_it140.ps1"
        log_dir = home / "it140" / "logs"
        environment = os.environ.copy()
        self._set_environment_variable(environment, "IT140_INSTALL_TEST_MODE", "true")
        self._set_environment_variable(
            environment, "IT140_INSTALL_TEST_STATE", str(state_path)
        )
        # HOME/USERPROFILE are not consumed for CourseRoot by the script copy,
        # but keeping them aligned makes subprocess diagnostics deterministic.
        self._set_environment_variable(environment, "HOME", str(home))
        self._set_environment_variable(environment, "USERPROFILE", str(home))

        completed = subprocess.run(
            [
                POWERSHELL_EXECUTABLE,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
                "-NonInteractive",
                *arguments,
            ],
            capture_output=True,
            text=True,
            timeout=45,
            check=False,
            env=environment,
        )
        log_files = sorted(log_dir.glob("setup_win_*.log"))
        log_file = log_files[-1] if log_files else None
        transcript = parse_configure_log(log_file) if log_file is not None else None
        protected_after = snapshot_paths(self._protected_paths(home))
        differences = snapshot_differences(protected_before, protected_after)
        return InstallRun(
            scenario_id=scenario_id,
            root=root,
            returncode=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
            home=home,
            log_dir=log_dir,
            log_file=log_file,
            transcript=transcript,
            protected_differences=differences,
            state_path=state_path,
        )

    def run_scenario(self, scenario: dict[str, Any]) -> InstallRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-install-win-"))
        _, home, state_path = self._prepare_fixture(temp_root, scenario)
        protected_before = snapshot_paths(self._protected_paths(home))
        return self._execute(
            scenario["id"],
            temp_root,
            home,
            state_path,
            list(scenario.get("arguments", [])),
            protected_before,
        )

    def run_twice(self, scenario: dict[str, Any]) -> InstallSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-install-win-twice-"))
        _, home, state_path = self._prepare_fixture(temp_root, scenario)
        protected_before = snapshot_paths(self._protected_paths(home))
        first = self._execute(
            scenario["id"] + "-first",
            temp_root,
            home,
            state_path,
            list(scenario.get("arguments", [])),
            protected_before,
        )
        first_state = json.loads(state_path.read_text(encoding="utf-8"))
        second = self._execute(
            scenario["id"] + "-second",
            temp_root,
            home,
            state_path,
            list(scenario.get("arguments", [])),
            protected_before,
        )
        second_state = json.loads(state_path.read_text(encoding="utf-8"))
        return InstallSequence(
            root=temp_root,
            first=first,
            second=second,
            first_state=first_state,
            second_state=second_state,
        )

    @staticmethod
    def configured_state(run: InstallRun) -> dict[str, Any]:
        return json.loads(run.state_path.read_text(encoding="utf-8"))
