#!/usr/bin/env python3
"""Black-box harness for macOS verify_it140.zsh lifecycle tests."""

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from typing import Any

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.runner import VerifyRun, shlex_quote  # noqa: E402
from common.snapshot import snapshot_differences, snapshot_paths  # noqa: E402
from common.verify_log import parse_verify_log  # noqa: E402

REPO_ROOT = LIFECYCLE_ROOT.parents[1]
VERIFY_SOURCE = REPO_ROOT / "scripts" / "mac" / "verify_it140.zsh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
ZSH_EXECUTABLE = "/bin/zsh"
LAUNCHER_MARKER = "IT140-MAC-VSCODE-REPOS-LAUNCHER-v1"


class MacVerifyHarness:
    """Build and execute one isolated macOS Verify scenario."""

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
                merged[key] = MacVerifyHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _load_manifest(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _bindings(manifest: dict[str, Any]) -> dict[str, Any]:
        return manifest["platforms"]["macos"]["course_ide_bindings"]

    @classmethod
    def _extensions(cls, manifest: dict[str, Any]) -> list[str]:
        return [
            binding["package_identifier"]
            for binding in cls._bindings(manifest).values()
            if binding.get("required")
            and binding.get("installer_adapter_id") == "vscode_extension"
        ]

    @classmethod
    def _system_commands(cls, manifest: dict[str, Any]) -> set[str]:
        commands: set[str] = set()
        for binding in cls._bindings(manifest).values():
            if binding.get("required") and binding.get("installation_scope") == "system":
                commands.update(binding.get("verification", {}).get("executable_names", []))
        return commands

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

    @classmethod
    def _vscode_settings(cls, manifest: dict[str, Any]) -> dict[str, Any]:
        settings: dict[str, Any] = {}
        binding = cls._bindings(manifest).get("source_code_ide", {})
        for profile_id in binding.get("settings_profile_ids", []):
            settings.update(manifest["managed_settings"][profile_id]["values"])
        return settings

    @classmethod
    def _default_mock_state(cls, manifest: dict[str, Any]) -> dict[str, Any]:
        return {
            "gh_auth": True,
            "github_id": "12345",
            "github_login": "it140-test",
            "extensions": cls._extensions(manifest),
            "git_config": cls._git_config(manifest),
            "missing_python_packages": [],
            "command_exit_codes": {},
        }

    def _write_mock_wrapper(self, path: Path, command_name: str) -> None:
        dispatcher = self.mock_dispatcher.resolve()
        interpreter = Path(sys.executable).resolve()
        path.write_text(
            "#!/bin/zsh\n"
            f"exec {shlex_quote(str(interpreter))} {shlex_quote(str(dispatcher))} "
            f"{shlex_quote(command_name)} \"$@\"\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    @staticmethod
    def _write_launcher(launcher: Path, repos: Path, code_cli: Path) -> None:
        contents = launcher / "Contents"
        macos = contents / "MacOS"
        resources = contents / "Resources"
        macos.mkdir(parents=True, exist_ok=True)
        resources.mkdir(parents=True, exist_ok=True)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(
                {
                    "CFBundleIdentifier": "edu.snhu.it140.vscode-repos",
                    "CFBundleExecutable": "open-repos",
                    "CFBundlePackageType": "APPL",
                    "LSArchitecturePriority": ["arm64"],
                },
                handle,
            )
        (resources / "it140-managed-launcher").write_text(
            LAUNCHER_MARKER + "\n", encoding="utf-8"
        )
        executable = macos / "open-repos"
        executable.write_text(
            "#!/bin/zsh\n"
            f"# {LAUNCHER_MARKER}\n"
            "set -euo pipefail\n"
            f"readonly REPOS_ROOT={shlex_quote(str(repos))}\n"
            f"readonly CODE_CLI={shlex_quote(str(code_cli))}\n"
            'cd -- "$REPOS_ROOT"\n'
            'exec "$CODE_CLI" --reuse-window "$REPOS_ROOT"\n',
            encoding="utf-8",
        )
        executable.chmod(0o755)

    def _prepare_fixture(self, temp_root: Path, scenario: dict[str, Any]) -> tuple[Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root, symlinks=True)
        home = fixture_root / "home"
        course_root = home / "it140"
        scripts_root = course_root / "scripts"
        manifest_dir = scripts_root / ".manifest"
        mac_dir = scripts_root / "mac"
        log_dir = course_root / "logs"
        venv_bin = course_root / ".venv" / "bin"
        for path in (manifest_dir, mac_dir, log_dir, venv_bin):
            path.mkdir(parents=True, exist_ok=True)
        log_dir.chmod(0o700)

        shutil.copy2(VERIFY_SOURCE, mac_dir / VERIFY_SOURCE.name)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")
            manifest = self._load_manifest(MANIFEST_SOURCE)
        else:
            manifest = self._load_manifest(manifest_path)

        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        required_mocks = self._system_commands(manifest) | {"brew", "code", "gh", "git"}
        # The real Python 3.12 installed by actions/setup-python validates the
        # controlled manifest/schema and managed JSON. Do not shadow it.
        required_mocks.discard("python3.12")
        for name in sorted(required_mocks):
            self._write_mock_wrapper(mock_dir / name, name)
        self._write_mock_wrapper(venv_bin / "python", "venv_python")

        desktop = home / "Desktop"
        desktop.mkdir(parents=True, exist_ok=True)
        repos = home / "Repos"
        repos.mkdir(parents=True, exist_ok=True)
        shortcut = desktop / "Repos"
        if shortcut.exists() or shortcut.is_symlink():
            shortcut.unlink()
        shortcut.symlink_to(repos)

        settings = self._vscode_settings(manifest)
        settings["python.defaultInterpreterPath"] = str(venv_bin / "python")
        settings["it140.lifecycleTestSentinel"] = "preserve-me"
        settings_path = home / "Library" / "Application Support" / "Code" / "User" / "settings.json"
        settings_path.parent.mkdir(parents=True, exist_ok=True)
        settings_path.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        self._write_launcher(
            desktop / "Visual Studio Code - Repos.app",
            repos,
            mock_dir / "code",
        )
        return home, mock_dir

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "repositories": home / "Repos",
            "zprofile": home / ".zprofile",
            "zshrc": home / ".zshrc",
            "vscode_settings": home / "Library" / "Application Support" / "Code" / "User" / "settings.json",
            "desktop": home / "Desktop",
            "venv": home / "it140" / ".venv",
            "scripts": home / "it140" / "scripts",
        }

    def run_scenario(self, scenario: dict[str, Any]) -> VerifyRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-verify-mac-"))
        try:
            home, mock_dir = self._prepare_fixture(temp_root, scenario)
            manifest = self._load_manifest(MANIFEST_SOURCE)
            state = self._merge(self._default_mock_state(manifest), scenario.get("mock_overrides", {}))
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
                    "IT140_MOCK_STATE": str(state_path),
                    "IT140_MOCK_TRACE": str(trace_path),
                    # Test root enables deterministic transcript handling and
                    # the test-only effective-EUID seam; it never redirects
                    # production macOS system paths.
                    "IT140_VERIFY_TEST_ROOT": str(temp_root / "test-root"),
                    "IT140_VERIFY_TEST_EUID": "501",
                }
            )
            verify_path = home / "it140" / "scripts" / "mac" / "verify_it140.zsh"
            completed = subprocess.run(
                [ZSH_EXECUTABLE, str(verify_path), *scenario.get("arguments", [])],
                cwd=home,
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )

            after = snapshot_paths(protected)
            differences = snapshot_differences(before, after)
            log_dir = home / "it140" / "logs"
            logs = sorted(log_dir.glob("verify_mac_*.log"))
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
                trace_file=trace_path,
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise
