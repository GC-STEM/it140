#!/usr/bin/env python3
"""Black-box harness for Windows verify_it140.ps1 lifecycle tests. """

from __future__ import annotations

import copy
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

from common.runner import VerifyRun  # noqa: E402
from common.snapshot import snapshot_differences, snapshot_paths  # noqa: E402
from common.verify_log import parse_verify_log  # noqa: E402

REPO_ROOT = LIFECYCLE_ROOT.parents[1]
VERIFY_SOURCE = REPO_ROOT / "scripts" / "win" / "verify_it140.ps1"
WIN_SCRIPTS_SOURCE = REPO_ROOT / "scripts" / "win"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
POWERSHELL_EXECUTABLE = shutil.which("powershell.exe") or shutil.which("powershell")


class WinVerifyHarness:
    """Build and execute one isolated Windows Verify scenario."""

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
                merged[key] = WinVerifyHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _load_manifest(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _set_environment_variable(
        environment: dict[str, str],
        name: str,
        value: str,
    ) -> None:
        """Set one Windows environment variable without case-duplicate keys.

        ``os.environ.copy()`` returns a plain ``dict``.  Adding ``Path`` to that
        dictionary can therefore leave the original ``PATH`` entry beside it,
        even though Windows treats those names as the same environment variable.
        CreateProcess does not define which duplicate wins.  Remove every
        case-equivalent key before adding the controlled value so the verifier
        observes the fixture PATH deterministically.
        """

        normalized_name = name.casefold()
        for existing_name in list(environment):
            if existing_name.casefold() == normalized_name:
                del environment[existing_name]
        environment[name] = value

    @staticmethod
    def _bindings(manifest: dict[str, Any]) -> dict[str, Any]:
        return manifest["platforms"]["windows"]["course_ide_bindings"]

    @classmethod
    def _required_extensions(cls, manifest: dict[str, Any]) -> list[str]:
        return [
            binding["package_identifier"]
            for binding in cls._bindings(manifest).values()
            if binding.get("required")
            and binding.get("installer_adapter_id") == "vscode_extension"
        ]

    @classmethod
    def _available_commands(cls, manifest: dict[str, Any]) -> list[str]:
        commands = {"winget.exe"}
        for binding in cls._bindings(manifest).values():
            if binding.get("required") and binding.get("installation_scope") == "system":
                commands.update(binding.get("verification", {}).get("executable_names", []))
        return sorted(commands)

    @classmethod
    def _git_config(cls, manifest: dict[str, Any]) -> dict[str, Any]:
        config: dict[str, Any] = {
            "user.name": "IT 140 Test Student",
            "user.email": "12345+it140-test@users.noreply.github.com",
        }
        binding = cls._bindings(manifest).get("version_control_system", {})
        for profile_id in binding.get("settings_profile_ids", []):
            config.update(manifest["managed_settings"][profile_id]["values"])
        return config

    @staticmethod
    def _deep_merge(target: dict[str, Any], source: dict[str, Any]) -> None:
        for key, value in source.items():
            if isinstance(value, dict) and isinstance(target.get(key), dict):
                WinVerifyHarness._deep_merge(target[key], value)
            else:
                target[key] = copy.deepcopy(value)

    @classmethod
    def _vscode_settings(cls, manifest: dict[str, Any], venv_python: Path) -> dict[str, Any]:
        settings = copy.deepcopy(manifest["managed_settings"]["vscode_course_defaults"]["values"])
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
        settings["it140.lifecycleTestSentinel"] = "preserve-me"
        return settings

    @classmethod
    def _default_state(
        cls,
        manifest: dict[str, Any],
        home: Path,
        venv_scripts: Path,
        windows_script_dir: Path,
        vscode_executable: Path,
    ) -> dict[str, Any]:
        releases = manifest["platforms"]["windows"]["os"]["releases"]
        release = str(releases[0]["release_id"])
        system_root = os.environ.get("SystemRoot", r"C:\Windows")
        repos = home / "Repos"
        available = cls._available_commands(manifest)
        versions = {name: f"{name} 0.0-test" for name in available}
        return {
            "is_administrator": False,
            "is_windows_sandbox": False,
            "windows_facts": {
                "Caption": "Microsoft Windows 11 Pro",
                "Architecture": "64-bit",
                "DisplayVersion": release,
                "BuildNumber": "28000",
            },
            "free_space_bytes": 20 * 1024**3,
            "available_commands": available,
            "command_versions": versions,
            "command_exit_codes": {},
            "python_version": "3.12",
            "venv_python_version": "3.12",
            "extensions": cls._required_extensions(manifest),
            "git_config": cls._git_config(manifest),
            "user_path": f"{venv_scripts};{windows_script_dir}",
            "pending_restart": False,
            "vscode_executable": str(vscode_executable),
            "repos_shortcut": {
                "TargetPath": str(Path(system_root) / "explorer.exe"),
                "Arguments": f'"{repos}"',
                "WorkingDirectory": str(repos),
                "IconLocation": f'{Path(system_root) / "explorer.exe"},0',
                "Description": "IT 140 Repos",
            },
            "vscode_shortcut": {
                "TargetPath": str(vscode_executable),
                "Arguments": f'"{repos}"',
                "WorkingDirectory": str(repos),
                "IconLocation": f"{vscode_executable},0",
                "Description": "IT 140 Visual Studio Code",
            },
        }

    def _prepare_fixture(self, temp_root: Path, scenario: dict[str, Any]) -> tuple[Path, Path, Path]:
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
        venv_scripts.mkdir(parents=True, exist_ok=True)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")
            manifest = self._load_manifest(MANIFEST_SOURCE)
        else:
            manifest = self._load_manifest(manifest_path)

        venv_python = venv_scripts / "python.exe"
        venv_python.write_bytes(b"IT140 lifecycle test placeholder\n")

        repos = home / "Repos"
        repos.mkdir(parents=True, exist_ok=True)
        desktop = home / "Desktop"
        desktop.mkdir(parents=True, exist_ok=True)
        (desktop / "Repos.lnk").write_bytes(b"IT140 test shortcut placeholder\n")
        (desktop / "Visual Studio Code - IT 140.lnk").write_bytes(b"IT140 test shortcut placeholder\n")

        settings_path = home / "AppData" / "Roaming" / "Code" / "User" / "settings.json"
        settings_path.parent.mkdir(parents=True, exist_ok=True)
        settings_path.write_text(
            json.dumps(self._vscode_settings(manifest, venv_python), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        vscode_executable = home / "AppData" / "Local" / "Programs" / "Microsoft VS Code" / "Code.exe"
        vscode_executable.parent.mkdir(parents=True, exist_ok=True)
        vscode_executable.write_bytes(b"IT140 test Code.exe placeholder\n")
        return home, win_dir, vscode_executable

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "repositories": home / "Repos",
            "vscode_settings": home / "AppData" / "Roaming" / "Code" / "User" / "settings.json",
            "desktop": home / "Desktop",
            "venv": home / "it140" / ".venv",
            "scripts": home / "it140" / "scripts",
        }

    def run_scenario(self, scenario: dict[str, Any]) -> VerifyRun:
        if not POWERSHELL_EXECUTABLE:
            raise RuntimeError("Windows PowerShell executable was not found")

        temp_root = Path(tempfile.mkdtemp(prefix="it140-verify-win-"))
        try:
            home, win_dir, vscode_executable = self._prepare_fixture(temp_root, scenario)
            manifest = self._load_manifest(MANIFEST_SOURCE)
            venv_scripts = home / "it140" / ".venv" / "Scripts"
            state = self._merge(
                self._default_state(manifest, home, venv_scripts, win_dir, vscode_executable),
                scenario.get("mock_overrides", {}),
            )
            state_path = temp_root / "verify-state.json"
            state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

            protected = self._protected_paths(home)
            before = snapshot_paths(protected)
            env = os.environ.copy()
            inherited_path = next(
                (value for key, value in env.items() if key.casefold() == "path"),
                "",
            )
            controlled_environment = {
                "IT140_VERIFY_TEST_ROOT": str(temp_root / "fixture"),
                "IT140_VERIFY_TEST_STATE": str(state_path),
                "USERPROFILE": str(home),
                "HOME": str(home),
                "APPDATA": str(home / "AppData" / "Roaming"),
                "LOCALAPPDATA": str(home / "AppData" / "Local"),
                "Path": f"{venv_scripts};{win_dir};{inherited_path}",
            }
            for name, value in controlled_environment.items():
                self._set_environment_variable(env, name, value)
            verify_path = win_dir / "verify_it140.ps1"
            completed = subprocess.run(
                [
                    POWERSHELL_EXECUTABLE,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(verify_path),
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
            log_dir = home / "it140" / "logs"
            logs = sorted(log_dir.glob("verify_win_*.log"))
            log_file = logs[-1] if logs else None
            transcript = parse_verify_log(log_file) if log_file else None
            return VerifyRun(
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
                trace_file=None,
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
