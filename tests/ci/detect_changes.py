#!/usr/bin/env python3
"""Determine which IT 140 platform checks are affected by a Git change set."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import PurePosixPath


ZERO_SHA = "0" * 40


def git_changed_files(base: str, head: str) -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMRT", base, head],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def classify(paths: list[str], force_all: bool = False) -> dict[str, bool]:
    flags = {
        "manifest": False,
        "cvd": False,
        "cvd_verify": False,
        "nix": False,
        "ubg_verify": False,
        "mac": False,
        "mac_verify": False,
        "win": False,
        "win_verify": False,
    }
    if force_all:
        return {name: True for name in flags}

    for raw_path in paths:
        path = PurePosixPath(raw_path)
        posix = path.as_posix()

        # Changes to CI itself should exercise every CI branch.
        if posix == ".github/workflows/ci.yml" or posix.startswith("tests/ci/"):
            return {name: True for name in flags}
        # Controlled manifest/schema changes affect every platform contract and
        # the behavioral Verify contracts.
        if posix in {
            "scripts/.manifest/it140_manifest.json",
            "scripts/.manifest/it140_manifest.schema.json",
        }:
            return {name: True for name in flags}
        if posix.startswith("scripts/cvd/"):
            flags["manifest"] = True
            flags["cvd"] = True
            flags["cvd_verify"] = True
        elif posix == "tests/lifecycle/README.md" or posix.startswith("tests/lifecycle/common/"):
            flags["cvd_verify"] = True
            flags["ubg_verify"] = True
            flags["mac_verify"] = True
            flags["win_verify"] = True
        elif posix.startswith("tests/lifecycle/verify/cvd/"):
            flags["cvd_verify"] = True
        elif posix.startswith("tests/lifecycle/verify/ubg/"):
            flags["ubg_verify"] = True
        elif posix.startswith("tests/lifecycle/verify/mac/"):
            flags["mac_verify"] = True
        elif posix.startswith("tests/lifecycle/verify/win/"):
            flags["win_verify"] = True
        elif posix.startswith("tests/lifecycle/"):
            # Unknown/shared lifecycle test infrastructure should exercise every
            # behavioral Verify suite until it receives explicit routing.
            flags["cvd_verify"] = True
            flags["ubg_verify"] = True
            flags["mac_verify"] = True
            flags["win_verify"] = True
        elif posix.startswith("scripts/nix/"):
            flags["manifest"] = True
            flags["nix"] = True
            if posix == "scripts/nix/ubg/verify_ubg.sh":
                flags["ubg_verify"] = True
        elif posix.startswith("scripts/mac/"):
            flags["manifest"] = True
            flags["mac"] = True
            if posix == "scripts/mac/verify_it140.zsh":
                flags["mac_verify"] = True
        elif posix.startswith("scripts/win/"):
            flags["manifest"] = True
            flags["win"] = True
            if posix == "scripts/win/verify_it140.ps1":
                flags["win_verify"] = True

    return flags


def write_outputs(flags: dict[str, bool]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    lines = [f"{name}={'true' if value else 'false'}" for name, value in flags.items()]

    if output_path:
        with open(output_path, "a", encoding="utf-8", newline="\n") as handle:
            handle.write("\n".join(lines) + "\n")
    else:
        print("\n".join(lines))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", required=True)
    parser.add_argument("--base", default="")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument(
        "--files",
        nargs="*",
        help="Optional explicit paths for local testing; skips git diff.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.files is not None:
        flags = classify(args.files)
        write_outputs(flags)
        return 0

    if args.event == "workflow_dispatch":
        write_outputs(classify([], force_all=True))
        return 0

    if not args.base or args.base == ZERO_SHA:
        # New branches/initial pushes do not have a usable comparison base.
        write_outputs(classify([], force_all=True))
        return 0
    try:
        paths = git_changed_files(args.base, args.head)
    except subprocess.CalledProcessError:
        print(
            f"Could not calculate git diff {args.base}..{args.head}; running all checks.",
            file=sys.stderr,
        )
        write_outputs(classify([], force_all=True))
        return 0

    if paths:
        print("Changed files:")
        for path in paths:
            print(f"  {path}")
    else:
        print("No changed files detected.")
    write_outputs(classify(paths))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
