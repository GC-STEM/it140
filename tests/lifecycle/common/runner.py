#!/usr/bin/env python3
"""Reusable black-box runner for IT 140 lifecycle behavioral tests."""

from __future__ import annotations

from dataclasses import dataclass
import copy
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Any

from .snapshot import snapshot_differences, snapshot_paths
from .verify_log import VerifyTranscript, parse_verify_log


REPO_ROOT = Path(__file__).resolve().parents[3]
VERIFY_SOURCE = REPO_ROOT / "scripts" / "cvd" / "verify_it140.sh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"


@dataclass
class VerifyRun:
    scenario_id: str
    root: Path
    returncode: int
    stdout: str
    stderr: str
    home: Path
    log_dir: Path
    log_file: Path | None
    transcript: VerifyTranscript | None
    protected_differences: list[str]
    trace_file: Path

    @property
    def combined_output(self) -> str:
        return self.stdout + self.stderr


class CvdVerifyHarness:
    """Build and execute one isolated CVD Verify scenario."""

    def __init__(self, fixture_base: Path, mock_dispatcher: Path):
        self.fixture_base = fixture_base
        self.mock_dispatcher = mock_dispatcher

    @staticmethod
    def load_scenario(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _merge(base: dict[str, Any], overrides: dict[str, Any]) -> dict[str, Any]:
        merged = copy.deepcopy(base)
        for key, value in overrides.items():
            if isinstance(value, dict) and isinstance(merged.get(key), dict):
                merged[key] = CvdVerifyHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _load_manifest(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _default_mock_state(manifest: dict[str, Any]) -> dict[str, Any]:
        platform = manifest["platforms"]["cvd"]
        bindings = platform["course_ide_bindings"]

        extensions = [
            binding["package_identifier"]
            for binding in bindings.values()
            if binding.get("required")
            and binding.get("installation_scope") == "user"
            and binding.get("installer_adapter_id") == "vscode_extension"
        ]

        git_config: dict[str, Any] = {
            "user.name": "IT 140 Test Student",
            "user.email": "12345+it140-test@users.noreply.github.com",
        }
        for profile_id in bindings["version_control_system"].get("settings_profile_ids", []):
            git_config.update(manifest["managed_settings"][profile_id]["values"])

        return {
            "architecture": "amd64",
            "gh_auth": True,
            "network_reachable": True,
            "numlock_package_installed": True,
            "numlock_on": True,
            "extensions": extensions,
            "git_config": git_config,
            "missing_python_packages": [],
            "invalid_desktop_paths": [],
            "command_exit_codes": {},
        }

    @staticmethod
    def _system_commands(manifest: dict[str, Any]) -> set[str]:
        commands: set[str] = set()
        bindings = manifest["platforms"]["cvd"]["course_ide_bindings"]
        for binding in bindings.values():
            if binding.get("required") and binding.get("installation_scope") == "system":
                commands.update(binding.get("verification", {}).get("executable_names", []))
        return commands

    def _write_mock_wrapper(self, path: Path, command_name: str) -> None:
        dispatcher = self.mock_dispatcher.resolve()
        interpreter = Path(sys.executable).resolve()
        path.write_text(
            "#!/usr/bin/env bash\n"
            f"exec {shlex_quote(str(interpreter))} {shlex_quote(str(dispatcher))} "
            f"{shlex_quote(command_name)} \"$@\"\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def _prepare_fixture(self, temp_root: Path, scenario: dict[str, Any]) -> tuple[Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root, symlinks=True)
        home = fixture_root / "home"
        system_root = fixture_root / "system"

        course_root = home / "it140"
        scripts_root = course_root / "scripts"
        manifest_dir = scripts_root / ".manifest"
        cvd_dir = scripts_root / "cvd"
        log_dir = course_root / "logs"
        venv_bin = course_root / ".venv" / "bin"

        manifest_dir.mkdir(parents=True, exist_ok=True)
        cvd_dir.mkdir(parents=True, exist_ok=True)
        log_dir.mkdir(parents=True, exist_ok=True)
        venv_bin.mkdir(parents=True, exist_ok=True)
        log_dir.chmod(0o700)

        shutil.copy2(VERIFY_SOURCE, cvd_dir / "verify_it140.sh")
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)
        (cvd_dir / "verify_it140.sh").chmod(0o755)

        fixture_overrides = scenario.get("fixture_overrides", {})
        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        if fixture_overrides.get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")
            # We still need the original production manifest to construct the
            # otherwise-compliant fixture before the verifier reads the malformed copy.
            manifest = self._load_manifest(MANIFEST_SOURCE)
        else:
            manifest = self._load_manifest(manifest_path)

        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        required_mocks = self._system_commands(manifest) | {
            "curl",
            "desktop-file-validate",
            "dpkg",
            "dpkg-query",
            "gh",
            "gio",
            "git",
            "numlockx",
            "python3.12",
            "xdg-user-dir",
            "xfconf-query",
        }
        for name in sorted(required_mocks):
            self._write_mock_wrapper(mock_dir / name, name)

        self._write_mock_wrapper(venv_bin / "python", "venv_python")

        desktop = home / "Desktop"
        desktop.mkdir(parents=True, exist_ok=True)
        repos = home / "Repos"
        shortcut = desktop / "Repos"
        if shortcut.exists() or shortcut.is_symlink():
            shortcut.unlink()
        shortcut.symlink_to(repos)

        launcher = desktop / "visual-studio-code.desktop"
        launcher.write_text(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=Visual Studio Code\n"
            f"Exec=code {repos}\n"
            f"Path={repos}\n",
            encoding="utf-8",
        )
        launcher.chmod(0o755)

        settings_path = home / ".config" / "Code" / "User" / "settings.json"
        settings_path.parent.mkdir(parents=True, exist_ok=True)
        bindings = manifest["platforms"]["cvd"]["course_ide_bindings"]
        vscode_settings: dict[str, Any] = {}
        for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
            vscode_settings.update(manifest["managed_settings"][profile_id]["values"])
        vscode_settings["python.defaultInterpreterPath"] = str(venv_bin / "python")
        # Include an unmanaged sentinel to prove Verify preserves unrelated settings.
        vscode_settings["it140.lifecycleTestSentinel"] = "preserve-me"
        settings_path.write_text(
            json.dumps(vscode_settings, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        return home, system_root, mock_dir

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "repositories": home / "Repos",
            "bashrc": home / ".bashrc",
            "profile": home / ".profile",
            "vscode_settings": home / ".config" / "Code" / "User" / "settings.json",
            "desktop": home / "Desktop",
            "venv": home / "it140" / ".venv",
            "scripts": home / "it140" / "scripts",
        }

    def run_scenario(self, scenario: dict[str, Any]) -> VerifyRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-verify-"))
        try:
            home, system_root, mock_dir = self._prepare_fixture(temp_root, scenario)

            manifest = self._load_manifest(MANIFEST_SOURCE)
            state = self._merge(
                self._default_mock_state(manifest),
                scenario.get("mock_overrides", {}),
            )
            state_path = temp_root / "mock-state.json"
            trace_path = temp_root / "mock-trace.jsonl"
            state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

            protected = self._protected_paths(home)
            before = snapshot_paths(protected)

            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(home),
                    "PATH": f"{mock_dir}:{env.get('PATH', '')}",
                    "XDG_CURRENT_DESKTOP": "XFCE",
                    "IT140_MOCK_STATE": str(state_path),
                    "IT140_MOCK_TRACE": str(trace_path),
                    "IT140_VERIFY_TEST_ROOT": str(system_root),
                    # Allows deterministic execution when a developer runs the
                    # test suite from a root-owned container. The production
                    # verifier honors this only when the test root is active.
                    "IT140_VERIFY_TEST_EUID": "1000",
                }
            )

            verify_path = home / "it140" / "scripts" / "cvd" / "verify_it140.sh"
            stdout_path = temp_root / "stdout.txt"
            stderr_path = temp_root / "stderr.txt"
            with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
                "w", encoding="utf-8"
            ) as stderr_handle:
                completed = subprocess.run(
                    [str(verify_path), *scenario.get("arguments", [])],
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

            log_dir = home / "it140" / "logs"
            logs = sorted(log_dir.glob("verify_cvd_*.log"))
            log_file = logs[-1] if logs else None
            transcript = parse_verify_log(log_file) if log_file else None

            return VerifyRun(
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
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise


def shlex_quote(value: str) -> str:
    """Small local shell-quoting helper to avoid another runtime dependency."""

    if not value:
        return "''"
    if all(character.isalnum() or character in "@%_+=:,./-" for character in value):
        return value
    return "'" + value.replace("'", "'\"'\"'") + "'"


def mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)
