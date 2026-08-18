#!/usr/bin/env python3
"""Black-box harness for Windows configure_it140.ps1 lifecycle tests."""

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
CONFIGURE_SOURCE = REPO_ROOT / "scripts" / "win" / "configure_it140.ps1"
WIN_SCRIPTS_SOURCE = REPO_ROOT / "scripts" / "win"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
POWERSHELL_EXECUTABLE = shutil.which("powershell.exe") or shutil.which("powershell")


@dataclass
class ConfigureRun:
    """Captured state for one production Configure execution."""

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
            sections.append("Configure transcript:\n" + self.transcript.text.rstrip())
        if self.state_path.is_file():
            sections.append(
                "Configure test state:\n"
                + self.state_path.read_text(encoding="utf-8", errors="replace").rstrip()
            )
        return "\n\n".join(sections)


@dataclass
class ConfigureSequence:
    """Two successful Configure executions against one mutable fixture."""

    root: Path
    first: ConfigureRun
    second: ConfigureRun
    first_state: dict[str, Any]
    second_state: dict[str, Any]


class WinConfigureHarness:
    """Build and execute isolated Windows Configure scenarios."""

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
                merged[key] = WinConfigureHarness._merge(merged[key], value)
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
    def _bindings(manifest: dict[str, Any]) -> dict[str, Any]:
        return manifest["platforms"]["windows"]["course_ide_bindings"]

    @classmethod
    def required_extensions(cls, manifest: dict[str, Any]) -> set[str]:
        return {
            binding["package_identifier"].lower()
            for binding in cls._bindings(manifest).values()
            if binding.get("required")
            and binding.get("installation_scope") == "user"
            and binding.get("installer_adapter_id") == "vscode_extension"
        }

    @classmethod
    def required_venv_packages(cls, manifest: dict[str, Any]) -> set[str]:
        packages: set[str] = set()
        for role, binding in cls._bindings(manifest).items():
            if (
                binding.get("required")
                and binding.get("installation_scope") == "user"
                and binding.get("installer_adapter_id") == "python_venv_package"
            ):
                packages.add(binding["package_identifier"])
            if role == "code_quality_tool" and binding.get("required"):
                packages.add("ruff")
        return packages

    @classmethod
    def available_commands(cls, manifest: dict[str, Any]) -> list[str]:
        commands: set[str] = set()
        for binding in cls._bindings(manifest).values():
            if binding.get("required") and binding.get("installation_scope") == "system":
                commands.update(binding.get("verification", {}).get("executable_names", []))
        return sorted(commands)

    @classmethod
    def managed_git_settings(cls, manifest: dict[str, Any]) -> dict[str, str]:
        values: dict[str, str] = {}
        binding = cls._bindings(manifest).get("version_control_system", {})
        for profile_id in binding.get("settings_profile_ids", []):
            for key, value in manifest["managed_settings"][profile_id]["values"].items():
                if isinstance(value, bool):
                    values[key] = "true" if value else "false"
                else:
                    values[key] = str(value)
        return values

    @staticmethod
    def _deep_merge(target: dict[str, Any], source: dict[str, Any]) -> None:
        for key, value in source.items():
            if isinstance(value, dict) and isinstance(target.get(key), dict):
                WinConfigureHarness._deep_merge(target[key], value)
            else:
                target[key] = copy.deepcopy(value)

    @classmethod
    def managed_vscode_settings(
        cls, manifest: dict[str, Any], venv_python: Path
    ) -> dict[str, Any]:
        settings = copy.deepcopy(
            manifest["managed_settings"]["vscode_course_defaults"]["values"]
        )
        implementation = {
            "files.autoSave": "afterDelay",
            "files.autoSaveDelay": 1000,
            "files.trimTrailingWhitespace": True,
            "files.insertFinalNewline": True,
            "terminal.integrated.defaultProfile.windows": "PowerShell",
            "python.defaultInterpreterPath": str(venv_python),
            "python.testing.pytestArgs": ["."],
            "cSpell.language": "en",
            "workbench.editorAssociations": {
                "README.md": "vscode.markdown.preview.editor",
                "*_srs.md": "vscode.markdown.preview.editor",
                "*_sdd.md": "vscode.markdown.preview.editor",
            },
            "settingsSync.ignoredSettings": ["python.defaultInterpreterPath"],
        }
        cls._deep_merge(settings, implementation)
        return settings

    @classmethod
    def _default_state(
        cls,
        manifest: dict[str, Any],
        home: Path,
        win_dir: Path,
        vscode_executable: Path,
    ) -> dict[str, Any]:
        release = str(manifest["platforms"]["windows"]["os"]["releases"][0]["release_id"])
        inherited_path = os.environ.get("Path", os.environ.get("PATH", ""))
        return {
            "is_administrator": False,
            "is_windows_sandbox": False,
            "windows_facts": {
                "Caption": "Microsoft Windows 11 Pro",
                "Architecture": "64-bit",
                "DisplayVersion": release,
                "BuildNumber": "28000",
            },
            "machine_path": inherited_path,
            "user_path": r"C:\UserTools",
            "available_commands": cls.available_commands(manifest),
            "command_exit_codes": {},
            "python_version": "3.12",
            "venv_python_version": "",
            "python_packages": [],
            "github_authenticated": True,
            "github_login": "it140-test",
            "github_id": "12345",
            "git_config": {
                "user.name": "IT 140 Test Student",
                "it140.unmanaged": "preserve-me",
            },
            "extensions": ["publisher.unrelated"],
            "vscode_executable": str(vscode_executable),
            "shortcuts": {},
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
        venv_scripts = course_root / ".venv" / "Scripts"
        shutil.copytree(WIN_SCRIPTS_SOURCE, win_dir, dirs_exist_ok=True)
        manifest_dir.mkdir(parents=True, exist_ok=True)
        log_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        manifest = self._load_manifest(MANIFEST_SOURCE)
        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")

        vscode_executable = (
            home
            / "AppData"
            / "Local"
            / "Programs"
            / "Microsoft VS Code"
            / "Code.exe"
        )
        vscode_executable.parent.mkdir(parents=True, exist_ok=True)
        vscode_executable.write_bytes(b"IT140 lifecycle test Code.exe placeholder\n")

        state = self._merge(
            self._default_state(manifest, home, win_dir, vscode_executable),
            scenario.get("mock_overrides", {}),
        )
        if scenario.get("fixture_overrides", {}).get("preconfigured_before_identity"):
            venv_scripts.mkdir(parents=True, exist_ok=True)
            (venv_scripts / "python.exe").write_bytes(
                b"IT140 lifecycle test python placeholder\n"
            )
            state["venv_python_version"] = "3.12"
            state["python_packages"] = sorted(self.required_venv_packages(manifest))
            state["user_path"] = ";".join(
                [str(venv_scripts), str(win_dir), r"C:\UserTools"]
            )

        state_path = temp_root / "configure-state.json"
        state_path.write_text(
            json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        return home, win_dir, state_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home
            / "AppData"
            / "Roaming"
            / "Other App"
            / "prefs.txt",
        }

    def _environment(self, home: Path, state_path: Path) -> dict[str, str]:
        env = os.environ.copy()
        controlled = {
            "IT140_CONFIGURE_TEST_ROOT": str(home.parent),
            "IT140_CONFIGURE_TEST_STATE": str(state_path),
            "USERPROFILE": str(home),
            "HOME": str(home),
            "APPDATA": str(home / "AppData" / "Roaming"),
            "LOCALAPPDATA": str(home / "AppData" / "Local"),
        }
        for name, value in controlled.items():
            self._set_environment_variable(env, name, value)
        return env

    def _execute(
        self,
        scenario: dict[str, Any],
        temp_root: Path,
        home: Path,
        win_dir: Path,
        state_path: Path,
    ) -> ConfigureRun:
        if not POWERSHELL_EXECUTABLE:
            raise RuntimeError("Windows PowerShell executable was not found")
        protected = self._protected_paths(home)
        before = snapshot_paths(protected)
        log_dir = home / "it140" / "logs"
        before_logs = set(log_dir.glob("config_win_*.log")) if log_dir.exists() else set()
        env = self._environment(home, state_path)
        completed = subprocess.run(
            [
                POWERSHELL_EXECUTABLE,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(win_dir / "configure_it140.ps1"),
                "-NonInteractive",
                *scenario.get("arguments", []),
            ],
            cwd=home,
            env=env,
            capture_output=True,
            text=True,
            timeout=45,
            check=False,
        )
        after = snapshot_paths(protected)
        differences = snapshot_differences(before, after)
        after_logs = set(log_dir.glob("config_win_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        transcript = parse_configure_log(log_file) if log_file else None
        return ConfigureRun(
            scenario_id=scenario["id"],
            root=temp_root,
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

    @staticmethod
    def _new_temp_root(prefix: str) -> Path:
        # GitHub's Windows runner may expose its temporary directory through an
        # 8.3 alias (for example, RUNNER~1). Resolve it before building expected
        # managed paths so Python and PowerShell compare the same path spelling.
        return Path(tempfile.mkdtemp(prefix=prefix)).resolve()

    def run_scenario(self, scenario: dict[str, Any]) -> ConfigureRun:
        temp_root = self._new_temp_root("it140-configure-win-")
        try:
            home, win_dir, state_path = self._prepare_fixture(temp_root, scenario)
            return self._execute(scenario, temp_root, home, win_dir, state_path)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    def run_twice(self, scenario: dict[str, Any]) -> ConfigureSequence:
        temp_root = self._new_temp_root("it140-configure-win-twice-")
        try:
            home, win_dir, state_path = self._prepare_fixture(temp_root, scenario)
            first = self._execute(scenario, temp_root, home, win_dir, state_path)
            first_state = self.configured_state(first)
            first_log = first.log_file
            if first_log is not None:
                first_log.rename(first_log.with_name(first_log.stem + "_first.log"))
                first.log_file = first_log.with_name(first_log.stem + "_first.log")
            second = self._execute(scenario, temp_root, home, win_dir, state_path)
            second_state = self.configured_state(second)
            return ConfigureSequence(
                root=temp_root,
                first=first,
                second=second,
                first_state=first_state,
                second_state=second_state,
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    @staticmethod
    def configured_state(run: ConfigureRun) -> dict[str, Any]:
        settings_path = (
            run.home / "AppData" / "Roaming" / "Code" / "User" / "settings.json"
        )
        return {
            "state": json.loads(run.state_path.read_text(encoding="utf-8")),
            "settings": json.loads(settings_path.read_text(encoding="utf-8")),
            "student_work": (
                run.home / "Repos" / "student-work" / "do_not_touch.py"
            ).read_text(encoding="utf-8"),
            "personal_desktop": (run.home / "Desktop" / "Personal Notes.txt").read_text(
                encoding="utf-8"
            ),
        }
