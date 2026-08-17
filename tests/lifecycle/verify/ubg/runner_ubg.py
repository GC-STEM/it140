#!/usr/bin/env python3
"""Black-box harness for Ubuntu GNOME verify_ubg.sh lifecycle tests."""

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

from common.runner import BASH_EXECUTABLE, VerifyRun, shlex_quote  # noqa: E402
from common.snapshot import snapshot_differences, snapshot_paths  # noqa: E402
from common.verify_log import parse_verify_log  # noqa: E402


REPO_ROOT = LIFECYCLE_ROOT.parents[1]
VERIFY_SOURCE = REPO_ROOT / "scripts" / "nix" / "ubg" / "verify_ubg.sh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"


class UbgVerifyHarness:
    """Build and execute one isolated Ubuntu GNOME Verify scenario."""

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
                merged[key] = UbgVerifyHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _load_manifest(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _default_mock_state(manifest: dict[str, Any]) -> dict[str, Any]:
        bindings = manifest["platforms"]["ubuntu_gnome"]["course_ide_bindings"]

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
        version_control = bindings.get("version_control_system", {})
        for profile_id in version_control.get("settings_profile_ids", []):
            git_config.update(manifest["managed_settings"][profile_id]["values"])

        return {
            "architecture": "x86_64",
            "gh_auth": True,
            "network_reachable": True,
            "workspace_marker": True,
            "extensions": extensions,
            "git_config": git_config,
            "missing_python_packages": [],
            "command_exit_codes": {},
        }

    @staticmethod
    def _system_commands(manifest: dict[str, Any]) -> set[str]:
        commands: set[str] = set()
        bindings = manifest["platforms"]["ubuntu_gnome"]["course_ide_bindings"]
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

    def _prepare_fixture(
        self,
        temp_root: Path,
        scenario: dict[str, Any],
    ) -> tuple[Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root, symlinks=True)
        home = fixture_root / "home"
        system_root = fixture_root / "system"

        course_root = home / "it140"
        scripts_root = course_root / "scripts"
        manifest_dir = scripts_root / ".manifest"
        ubg_dir = scripts_root / "nix" / "ubg"
        log_dir = course_root / "logs"
        venv_bin = course_root / ".venv" / "bin"

        manifest_dir.mkdir(parents=True, exist_ok=True)
        ubg_dir.mkdir(parents=True, exist_ok=True)
        log_dir.mkdir(parents=True, exist_ok=True)
        venv_bin.mkdir(parents=True, exist_ok=True)
        log_dir.chmod(0o700)

        shutil.copy2(VERIFY_SOURCE, ubg_dir / "verify_ubg.sh")
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        fixture_overrides = scenario.get("fixture_overrides", {})
        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        if fixture_overrides.get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")
            # Keep the production manifest for fixture construction; only the copy
            # presented to verify_ubg.sh is malformed.
            manifest = self._load_manifest(MANIFEST_SOURCE)
        else:
            manifest = self._load_manifest(manifest_path)

        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        required_mocks = self._system_commands(manifest) | {
            "code",
            "curl",
            "gh",
            "gio",
            "git",
            "python3.12",
            "uname",
            "xdg-user-dir",
        }
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

        settings_path = home / ".config" / "Code" / "User" / "settings.json"
        settings_path.parent.mkdir(parents=True, exist_ok=True)
        bindings = manifest["platforms"]["ubuntu_gnome"]["course_ide_bindings"]
        vscode_settings: dict[str, Any] = {}
        source_code_ide = bindings.get("source_code_ide", {})
        for profile_id in source_code_ide.get("settings_profile_ids", []):
            vscode_settings.update(manifest["managed_settings"][profile_id]["values"])
        vscode_settings["python.defaultInterpreterPath"] = str(venv_bin / "python")
        # Unmanaged sentinel proves Verify preserves unrelated student/user settings.
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
        temp_root = Path(tempfile.mkdtemp(prefix="it140-verify-ubg-"))
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
                    "XDG_CURRENT_DESKTOP": "GNOME",
                    "IT140_MOCK_STATE": str(state_path),
                    "IT140_MOCK_TRACE": str(trace_path),
                    "IT140_VERIFY_TEST_ROOT": str(system_root),
                    "IT140_VERIFY_TEST_EUID": "1000",
                }
            )

            verify_path = home / "it140" / "scripts" / "nix" / "ubg" / "verify_ubg.sh"
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(verify_path), *scenario.get("arguments", [])],
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
            logs = sorted(log_dir.glob("verify_ubg_*.log"))
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
