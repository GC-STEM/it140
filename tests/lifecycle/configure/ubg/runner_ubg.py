#!/usr/bin/env python3
"""Black-box harness for Ubuntu GNOME config_ubg.sh lifecycle tests."""
from __future__ import annotations

import copy
from dataclasses import dataclass
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

LIFECYCLE_ROOT = Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))
from common.configure_log import ConfigureTranscript, parse_configure_log  # noqa: E402
from common.snapshot import snapshot_differences, snapshot_paths  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[4]
CONFIGURE_SOURCE = REPO_ROOT / "scripts" / "nix" / "ubg" / "config_ubg.sh"
MANIFEST_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.json"
SCHEMA_SOURCE = REPO_ROOT / "scripts" / ".manifest" / "it140_manifest.schema.json"
BASH_EXECUTABLE = shutil.which("bash")
if BASH_EXECUTABLE is None:
    raise RuntimeError("Ubuntu GNOME Configure lifecycle tests require Bash on PATH")


@dataclass
class ConfigureRun:
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
        if self.state_file.is_file():
            sections.append(
                "Configure test state:\n"
                + self.state_file.read_text(encoding="utf-8").rstrip()
            )
        return "\n\n".join(sections)


@dataclass
class ConfigureSequence:
    root: Path
    first: ConfigureRun
    second: ConfigureRun
    first_state: dict[str, Any]
    second_state: dict[str, Any]


class UbgConfigureHarness:
    """Build and execute isolated Ubuntu GNOME Configure scenarios."""

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
                merged[key] = UbgConfigureHarness._merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    @staticmethod
    def _load_manifest(path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def _bindings(manifest: dict[str, Any]) -> dict[str, Any]:
        return manifest["platforms"]["ubuntu_gnome"]["course_ide_bindings"]

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
            "custom_icon": None,
            "command_exit_codes": {},
        }

    def _write_mock_wrapper(self, path: Path, command_name: str) -> None:
        interpreter = Path(sys.executable).resolve()
        path.write_text(
            "#!/bin/bash\n"
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
        scripts_root = course_root / "scripts"
        manifest_dir = scripts_root / ".manifest"
        ubg_dir = scripts_root / "nix" / "ubg"
        manifest_dir.mkdir(parents=True, exist_ok=True)
        ubg_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(CONFIGURE_SOURCE, ubg_dir / CONFIGURE_SOURCE.name)
        shutil.copy2(MANIFEST_SOURCE, manifest_dir / MANIFEST_SOURCE.name)
        shutil.copy2(SCHEMA_SOURCE, manifest_dir / SCHEMA_SOURCE.name)

        manifest_path = manifest_dir / MANIFEST_SOURCE.name
        if scenario.get("fixture_overrides", {}).get("manifest") == "malformed":
            manifest_path.write_text("{ this is not valid JSON\n", encoding="utf-8")

        mock_dir = temp_root / "mock-bin"
        mock_dir.mkdir(parents=True)
        for name in ("code", "gh", "gio", "git", "python3.12", "xdg-user-dir"):
            self._write_mock_wrapper(mock_dir / name, name)

        preconfigure = bool(
            scenario.get("fixture_overrides", {}).get("preconfigured_before_identity")
        )
        initial_overrides = (
            scenario.get("seed_mock_overrides", {})
            if preconfigure
            else scenario.get("mock_overrides", {})
        )
        state = self._merge(self._default_mock_state(), initial_overrides)
        state_path = temp_root / "mock-state.json"
        state_path.write_text(
            json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        trace_path = temp_root / "mock-trace.jsonl"
        return home, mock_dir, state_path, trace_path

    @staticmethod
    def _protected_paths(home: Path) -> dict[str, Path]:
        return {
            "student_work": home / "Repos" / "student-work",
            "personal_desktop_file": home / "Desktop" / "Personal Notes.txt",
            "unrelated_app_config": home / ".config" / "other-app" / "prefs.txt",
        }

    def _environment(
        self,
        home: Path,
        mock_dir: Path,
        state_path: Path,
        trace_path: Path,
    ) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(home),
                "PATH": f"{mock_dir}:{env.get('PATH', '')}",
                "XDG_CURRENT_DESKTOP": "GNOME",
                "IT140_MOCK_STATE": str(state_path),
                "IT140_MOCK_TRACE": str(trace_path),
                "IT140_MOCK_DISPATCHER": str(self.mock_dispatcher),
                "IT140_MOCK_PYTHON": str(Path(sys.executable).resolve()),
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
        before_logs = set(log_dir.glob("configure_ubg_*.log")) if log_dir.exists() else set()
        env = self._environment(home, mock_dir, state_path, trace_path)
        configure_path = home / "it140" / "scripts" / "nix" / "ubg" / "config_ubg.sh"
        stdout_path = temp_root / f"stdout-{time.time_ns()}.txt"
        stderr_path = temp_root / f"stderr-{time.time_ns()}.txt"
        with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
            "w", encoding="utf-8"
        ) as stderr_handle:
            completed = subprocess.run(
                [BASH_EXECUTABLE, str(configure_path), *scenario.get("arguments", [])],
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
        after_logs = set(log_dir.glob("configure_ubg_*.log")) if log_dir.exists() else set()
        new_logs = sorted(after_logs - before_logs)
        log_file = new_logs[-1] if new_logs else (sorted(after_logs)[-1] if after_logs else None)
        self._wait_for_log(log_file)
        transcript = parse_configure_log(log_file) if log_file else None
        return ConfigureRun(
            scenario["id"], temp_root, completed.returncode, stdout, stderr, home,
            log_dir, log_file, transcript, differences, trace_path, state_path
        )

    def run_scenario(self, scenario: dict[str, Any]) -> ConfigureRun:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-configure-ubg-"))
        try:
            home, mock_dir, state_path, trace_path = self._prepare_fixture(temp_root, scenario)
            if scenario.get("fixture_overrides", {}).get("preconfigured_before_identity"):
                seed_scenario = copy.deepcopy(scenario)
                seed_scenario["id"] = f"{scenario['id']}-seed"
                seed_run = self._execute(
                    seed_scenario, temp_root, home, mock_dir, state_path, trace_path
                )
                if seed_run.returncode != 0:
                    raise RuntimeError(
                        "Production Configure could not seed canonical configured state.\n"
                        + seed_run.combined_output
                    )
                state = json.loads(state_path.read_text(encoding="utf-8"))
                state = self._merge(state, scenario.get("mock_overrides", {}))
                state_path.write_text(
                    json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
                )
                trace_path.unlink(missing_ok=True)
                time.sleep(1.05)
            return self._execute(
                scenario, temp_root, home, mock_dir, state_path, trace_path
            )
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    def run_twice(self, scenario: dict[str, Any]) -> ConfigureSequence:
        temp_root = Path(tempfile.mkdtemp(prefix="it140-configure-ubg-idempotence-"))
        try:
            home, mock_dir, state_path, trace_path = self._prepare_fixture(temp_root, scenario)
            first = self._execute(scenario, temp_root, home, mock_dir, state_path, trace_path)
            first_state = self.configured_state(first)
            time.sleep(1.05)
            second = self._execute(scenario, temp_root, home, mock_dir, state_path, trace_path)
            second_state = self.configured_state(second)
            return ConfigureSequence(temp_root, first, second, first_state, second_state)
        except Exception:
            shutil.rmtree(temp_root, ignore_errors=True)
            raise

    @staticmethod
    def configured_state(run: ConfigureRun) -> dict[str, Any]:
        home = run.home
        settings = home / ".config" / "Code" / "User" / "settings.json"
        repos_link = home / "Desktop" / "Repos"
        state = json.loads(run.state_file.read_text(encoding="utf-8"))
        return {
            "bashrc": (home / ".bashrc").read_text(encoding="utf-8"),
            "profile": (home / ".profile").read_text(encoding="utf-8"),
            "settings": json.loads(settings.read_text(encoding="utf-8")),
            "repos_link": os.readlink(repos_link) if repos_link.is_symlink() else None,
            "student_digest": file_digest(home / "Repos" / "student-work" / "do_not_touch.py"),
            "mock_state": {
                "gh_auth": state.get("gh_auth"),
                "extensions": sorted(state.get("extensions", []), key=str.lower),
                "venv_packages": sorted(state.get("venv_packages", []), key=str.lower),
                "git_config": state.get("git_config", {}),
                "custom_icon": state.get("custom_icon"),
            },
        }


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"
