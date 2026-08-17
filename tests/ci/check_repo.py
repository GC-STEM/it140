#!/usr/bin/env python3
"""Fast repository-integrity checks for the IT 140 automation package."""

from __future__ import annotations

import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
REQUIRED_FILES = (
    "scripts/.manifest/it140_manifest.json",
    "scripts/.manifest/it140_manifest.schema.json",
    "scripts/cvd/prepare_it140.sh",
    "scripts/cvd/install_it140.sh",
    "scripts/cvd/configure_it140.sh",
    "scripts/cvd/verify_it140.sh",
    "scripts/cvd/update_it140.sh",
    "scripts/mac/prepare_it140.zsh",
    "scripts/mac/install_it140.zsh",
    "scripts/mac/configure_it140.zsh",
    "scripts/mac/verify_it140.zsh",
    "scripts/mac/update_it140.zsh",
    "scripts/win/prepare_it140.ps1",
    "scripts/win/install_it140.ps1",
    "scripts/win/configure_it140.ps1",
    "scripts/win/verify_it140.ps1",
    "scripts/win/update_it140.ps1",
    "scripts/nix/ubg/bootstrap_ubg.sh",
    "scripts/nix/ubg/setup_ubg.sh",
    "scripts/nix/ubg/config_ubg.sh",
    "scripts/nix/ubg/verify_ubg.sh",
    "scripts/nix/ubg/update_ubg.sh",
    "tests/lifecycle/README.md",
    "tests/lifecycle/common/__init__.py",
    "tests/lifecycle/common/runner.py",
    "tests/lifecycle/common/snapshot.py",
    "tests/lifecycle/common/verify_log.py",
    "tests/lifecycle/verify/cvd/test_verify_cvd.py",
    "tests/lifecycle/verify/cvd/mocks/mock_command.py",
    "tests/lifecycle/verify/cvd/fixtures/base/home/.bashrc",
    "tests/lifecycle/verify/cvd/fixtures/base/home/.profile",
    "tests/lifecycle/verify/cvd/fixtures/base/home/Repos/student-work/do_not_touch.py",
    "tests/lifecycle/verify/cvd/fixtures/base/system/etc/os-release",
    "tests/lifecycle/verify/cvd/fixtures/base/system/etc/xdg/autostart/numlockx.desktop",
    "tests/lifecycle/verify/cvd/scenarios/compliant.json",
    "tests/lifecycle/verify/cvd/scenarios/required_failure.json",
    "tests/lifecycle/verify/cvd/scenarios/manifest_failure.json",
    "tests/lifecycle/verify/cvd/scenarios/unsupported.json",
)


class DuplicateKeyError(ValueError):
    pass


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle, object_pairs_hook=reject_duplicate_keys)


def main() -> int:
    errors: list[str] = []
    for relative in REQUIRED_FILES:
        path = ROOT / relative
        if not path.is_file():
            errors.append(f"Missing required file: {relative}")
        elif path.stat().st_size == 0:
            errors.append(f"Required file is empty: {relative}")
    for relative in (
        "scripts/.manifest/it140_manifest.json",
        "scripts/.manifest/it140_manifest.schema.json",
    ):
        path = ROOT / relative
        if not path.is_file():
            continue
        try:
            load_json(path)
        except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError) as exc:
            errors.append(f"Invalid JSON in {relative}: {exc}")
    if errors:
        print("Repository validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Repository validation passed: {len(REQUIRED_FILES)} required files found.")
    print("Manifest and schema are valid JSON with no duplicate object keys.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
