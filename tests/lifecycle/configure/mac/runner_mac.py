#!/usr/bin/env python3
"""Black-box harness for macOS configure_it140.zsh lifecycle tests."""

from __future__ import annotations

from dataclasses import dataclass
import copy
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))

from common.configure_log import ConfigureTranscript, parse_configure_log  # noqa: E402
from common.snapshot import snapshot_differences, snapshot_paths  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[4]
CONFIGURE_SOURCE = REPO_ROOT / "scripts" / "mac" / "configure_it140.zsh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
ZSH_EXECUTABLE = "/bin/zsh"
LAUNCHER_MARKER = "IT140-MAC-VSCODE-REPOS-LAUNCHER-v1"
MANAGED_ENV_START = "# >>> IT 140 managed PATH >>>"
MANAGED_ENV_END = "# <<< IT 140 managed PATH <<<"
LEGACY_ENV_START = "# >>> IT 140 Course IDE managed environment >>>"
LEGACY_ENV_END = "# <<< IT 140 Course IDE managed environment <<<"
MANAGED_ENV_EXPORT = 'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:$PATH"'


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
            sections.append("Configure transcript:\n" + self.transcript.text.rstrip())
        if self.trace_file.is_file():
            trace = self.trace_file.read_text(encoding="utf-8").strip()
            if trace:
                sections.append("Mock command trace:\n" + trace)
        return "\n\n".join(sections)


@dataclass
class ConfigureSequence:
    """Two successful executions against the same mutable fixture."""

    root: Path
    first: ConfigureRun
    second: ConfigureRun
    first_state: dict[str, Any]
    second_state: dict[str, Any]


class MacConfigureHarness:
    """Build and execute isolated macOS Configure scenarios."""

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
                merged[key] = MacConfigureHarness._merge(merged[key], value)
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
    def required_extensions(cls, manifest: dict[str, Any]) -> set[str]:
        return {
            binding["package_identifier"]
            for binding in cls._bindings(manifest).values()
            if binding.get("required")
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

    @classmethod
    def managed_vscode_settings(cls, manifest: dict[str, Any]) -> dict[str, Any]:
        values: dict[str, Any] = {}
        binding = cls._bindings(manifest).get("source_code_ide", {})
        for profile_id in binding.get("settings_profile_ids", []):
            values.update(manifest["managed_settings"][profile_id]["values"])
        return values

    @staticmethod
    def _default_mock_state() -> dict[str, Any]:
        return {
            "gh_auth": True,
            "github_identity": {
                "id": 12345,
                "login": "it140-test",
                "name": "IT 140 Test Student",
            },
            "extensions": [],
            "venv_packages": [],
            "git_config": {"user.extra": "preserve-me"},
            "command_exit_codes": {},
        }

    def _write_mock_wrapper(self, path: Path, command_name: str) -> None:
        interpreter = Path(sys.executable).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "#!/bin/zsh\n"
            f"exec {shell_quote(str(interpreter))} {shell_quote(str(self.mock_dispatcher))} "
            f"{shell_quote(command_name)} \"$@\"\n",
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
                    "CFBundleDisplayName": "Visual Studio Code - Repos",
                    "CFBundleExecutable": "open-repos",
                    "CFBundleIdentifier": "edu.snhu.it140.vscode-repos",
                    "CFBundleName": "Visual Studio Code - Repos",
                    "CFBundlePackageType": "APPL",
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1",
                    "LSArchitecturePriority": ["arm64"],
                    "LSUIElement": True,
                    "NSHighResolutionCapable": True,
                },
                handle,
                sort_keys=True,
            )
        (resources / "it140-managed-launcher").write_text(
            LAUNCHER_MARKER + "\n", encoding="utf-8"
        )
        executable = macos / "open-repos"
        executable.write_text(
            "#!/bin/zsh\n"
            f"# {LAUNCHER_MARKER}\n"
            "set -euo pipefail\n"
            f"readonly REPOS_ROOT={shell_quote(str(repos))}\n"
            f"readonly CODE_CLI={shell_quote(str(code_cli))}\n"
            'cd -- "$REPOS_ROOT"\n'
            'exec "$CODE_CLI" --reuse-window "$REPOS_ROOT"\n',
            encoding="utf-8",
        )
        executable.chmod(0o755)

    @staticmethod
    def _write_managed_shell_state(path: Path, sentinel_lines: list[str]) -> None:
        path.write_text(
            "\n".join(
                [
                    *sentinel_lines,
                    MANAGED_ENV_START,
                    MANAGED_ENV_EXPORT,
                    MANAGED_ENV_END,
                    "",
                ]
            ),
            encoding="utf-8",
        )
        path.chmod(0o600)

    def _apply_preconfigured_state(self, home: Path, command_dir: Path) -> None:
        self._write_managed_shell_state(
            home / ".zprofile",
            [
                "# Student/user Zsh profile configuration that Configure must preserve.",
                "IT140_USER_ZPROFILE_SENTINEL=preserve-me",
            ],
        )
        self._write_managed_shell_state(
            home / ".zshrc",
            [
                "# Student/user Zsh configuration that Configure must preserve.",
                "IT140_USER_ZSHRC_SENTINEL=preserve-me",
                "alias it140-test-sentinel='printf preserved'",
            ],
        )
        repos = home / "Repos"
        repos.mkdir(parents=True, exist_ok=True)
        desktop = home / "Desktop"
        desktop.mkdir(parents=True, exist_ok=True)
        shortcut = desktop / "Repos"
        if shortcut.exists() or shortcut.is_symlink():
            shortcut.unlink()
        shortcut.symlink_to(repos)
        launcher = desktop / "Visual Studio Code - Repos.app"
        if launcher.exists():
            shutil.rmtree(launcher)
        self._write_launcher(launcher, repos, command_dir / "code")

    def _prepare_fixture(
        self,
        temp_root: Path,
        scenario: dict[str, Any],
    ) -> tuple[Path, Path, Path, Path]:
        fixture_root = temp_root / "fixture"
        shutil.copytree(self.fixture_base, fixture_root, symlinks=True)
        home = fixture_root / "home"
        course_root = home / "it140"
        scripts_root = course_root / "scripts"
        manifest_dir = scripts_root / ".manifest"
        mac_dir = scripts_root / "mac"
        venv_bin = course_root / ".venv" / "bin"
        manifest_dir.mkdir(parents=True, exist_ok=True)
        mac_dir.mkdir(parents=True, exist_ok=True)
        venv_bin.mkdir(parents=True, exist_ok=True)
        shutil.copy2(CONFIGURE_SOURCE, mac_dir / CONFIGURE_SOURCE.name)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        manifest = self._load_manifest(MANIFEST_SOURCE)
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")

        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        # Configure prepends $HOME/it140/.venv/bin and /opt/homebrew/bin to PATH.
        # Put boundary mocks in the venv bin as well as the general mock bin so
        # production PATH management cannot accidentally escape to host tools.
        for name in ("code", "gh", "git", "python3.12"):
            self._write_mock_wrapper(mock_dir / name, name)
            self._write_mock_wrapper(venv_bin / name, name)

        state = self._merge(self._default_mock_state(), scenario.get("mock_overrides", {}))
        state_path = temp_root / "mock-state.json"
        state_path.write_text(
            json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        trace_path = temp_root / "mock-trace.jsonl"

        if scenario.get("fixture_overrides", {}).get("preconfigured_before_identity"):
            self._apply_preconfigured_state(home, venv_bin)

        # Retain the parsed manifest as part of fixture preparation so a malformed
        # copied manifest never prevents construction of deterministic test mocks.
        _ = manifest
        return home, mock_dir, state_path, trace_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home
            / "Library"
            / "Application Support"
            / "Other App"
            / "prefs.txt",
        }

    def _environment(
        self,
        home: Path,
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
    ) -> dict[str, str]:
        env = os.environ.copy()
        venv_bin = home / "it140" / ".venv" / "bin"
        env.update(
            {
                "HOME": str(home),
                "PATH": f"{venv_bin}:{mock_dir}:{env.get('PATH', '')}",
                "IT140_MOCK_STATE": str(state_path),
                "IT140_MOCK_TRACE": str(trace_path),
                "IT140_MOCK_DISPATCHER": str(self.mock_dispatcher),
                "IT140_MOCK_PYTHON": str(Path(sys.executable).resolve()),
                "IT140_REAL_PYTHON": str(Path(sys.executable).resolve()),
            }
        )
        return env

    @staticmethod
    def _wait_for_log(log_file: Path | None) -> None:
        if log_file is None:
            return
        for _ in range(40):
            try:
                if "Exit code" in log_file.read_text(
                    encoding="utf-8", errors="replace"
                ):
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
    ) -> ConfigureRun:
        protected = self._protected_paths(home)
        before = snapshot_paths(protected)
        log_dir = home / "it140" / "logs"
        before_logs = set(log_dir.glob("configure_mac_*.log")) if log_dir.exists() else set()
        env = self._environment(home, mock_dir, state_path, trace_path)
        configure_path = home / "it140" / "scripts" / "mac" / "configure_it140.zsh"
        stdout_path = temp_root / f"stdout-{time.time_ns()}.txt"
        stderr_path = temp_root / f"stderr-{time.time_ns()}.txt"
        with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
            "w", encoding="utf-8"
        ) as stderr_handle:
            completed = subprocess.run(
                [ZSH_EXECUTABLE, str(configure_path), *scenario.get("arguments", [])],
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
        after_logs = set(log_dir.glob("configure_mac_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_log(log_file)
        transcript = parse_configure_log(log_file) if log_file else None
        return ConfigureRun(
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
            state_file=state_path,
            mock_dir=mock_dir,
        )

    def run_scenario(self, scenario: dict[str, Any]) -> ConfigureRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-configure-mac-"))
        try:
            home, mock_dir, state_path, trace_path = self._prepare_fixture(
                temp_root, scenario
            )
            return self._execute(
                scenario, temp_root, home, mock_dir, state_path, trace_path
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    def run_twice(self, scenario: dict[str, Any]) -> ConfigureSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-configure-mac-idempotence-"))
        try:
            home, mock_dir, state_path, trace_path = self._prepare_fixture(
                temp_root, scenario
            )
            first = self._execute(
                scenario, temp_root, home, mock_dir, state_path, trace_path
            )
            first_state = self.configured_state(first)
            # Configure log filenames have one-second resolution. Keep each run's
            # transcript distinct without altering production time behavior.
            time.sleep(1.05)
            second = self._execute(
                scenario, temp_root, home, mock_dir, state_path, trace_path
            )
            second_state = self.configured_state(second)
            return ConfigureSequence(
                temp_root, first, second, first_state, second_state
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    @staticmethod
    def configured_state(run: ConfigureRun) -> dict[str, Any]:
        home = run.home
        settings_path = (
            home / "Library" / "Application Support" / "Code" / "User" / "settings.json"
        )
        launcher = home / "Desktop" / "Visual Studio Code - Repos.app"
        executable = launcher / "Contents" / "MacOS" / "open-repos"
        marker = launcher / "Contents" / "Resources" / "it140-managed-launcher"
        plist_path = launcher / "Contents" / "Info.plist"
        repos_link = home / "Desktop" / "Repos"
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        with plist_path.open("rb") as handle:
            launcher_plist = plistlib.load(handle)
        zprofile = home / ".zprofile"
        zshrc = home / ".zshrc"
        return {
            "zprofile": zprofile.read_text(encoding="utf-8"),
            "zprofile_mode": stat.S_IMODE(zprofile.stat().st_mode),
            "zshrc": zshrc.read_text(encoding="utf-8"),
            "zshrc_mode": stat.S_IMODE(zshrc.stat().st_mode),
            "settings": json.loads(settings_path.read_text(encoding="utf-8")),
            "launcher_plist": launcher_plist,
            "launcher_text": executable.read_text(encoding="utf-8"),
            "launcher_mode": stat.S_IMODE(executable.stat().st_mode),
            "launcher_marker": marker.read_text(encoding="utf-8").strip(),
            "repos_link": os.readlink(repos_link) if repos_link.is_symlink() else None,
            "student_digest": file_digest(
                home / "Repos" / "student-work" / "do_not_touch.py"
            ),
            "mock_state": {
                "gh_auth": state.get("gh_auth"),
                "extensions": sorted(state.get("extensions", []), key=str.lower),
                "venv_packages": sorted(state.get("venv_packages", []), key=str.lower),
                "git_config": state.get("git_config", {}),
            },
        }


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"
