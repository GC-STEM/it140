#!/usr/bin/env python3
"""Validate the controlled IT 140 manifest against its JSON Schema."""

from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator, FormatChecker
from jsonschema.exceptions import SchemaError


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "scripts/.manifest/it140_manifest.json"
SCHEMA_PATH = ROOT / "scripts/.manifest/it140_manifest.schema.json"


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


def format_path(parts) -> str:
    if not parts:
        return "$"
    rendered = "$"
    for part in parts:
        if isinstance(part, int):
            rendered += f"[{part}]"
        else:
            rendered += f".{part}"
    return rendered


def main() -> int:
    try:
        schema = load_json(SCHEMA_PATH)
        manifest = load_json(MANIFEST_PATH)
    except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError) as exc:
        print(f"Manifest validation failed while loading JSON: {exc}", file=sys.stderr)
        return 1

    try:
        Draft202012Validator.check_schema(schema)
    except SchemaError as exc:
        print(f"Manifest schema is not a valid Draft 2020-12 schema: {exc.message}", file=sys.stderr)
        return 1

    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(manifest), key=lambda error: list(error.absolute_path))

    if errors:
        print(f"Manifest does not conform to the schema ({len(errors)} error(s)):", file=sys.stderr)
        for error in errors:
            print(f"- {format_path(error.absolute_path)}: {error.message}", file=sys.stderr)
        return 1

    semantic_errors: list[str] = []

    expected_schema_version = (
        schema.get("properties", {})
        .get("schema_version", {})
        .get("const")
    )
    if expected_schema_version and manifest.get("schema_version") != expected_schema_version:
        semantic_errors.append(
            "manifest schema_version does not match the schema's declared compatibility version"
        )

    dtg = manifest.get("automation_release_date_time_group")
    if isinstance(dtg, str):
        try:
            datetime.strptime(dtg, "%Y-%m-%d-%H-%M")
        except ValueError:
            semantic_errors.append(
                "automation_release_date_time_group is not a real calendar date/time"
            )

    platforms = manifest.get("platforms", {})
    expected_platforms = {"cvd", "windows", "macos", "ubuntu_gnome"}
    missing_platforms = sorted(expected_platforms - set(platforms))
    if missing_platforms:
        semantic_errors.append(
            "missing expected platform definition(s): " + ", ".join(missing_platforms)
        )

    deployment_profiles = manifest.get("deployment_profiles", {})
    unknown_profile_platforms = sorted(
        {
            profile.get("platform_id")
            for profile in deployment_profiles.values()
            if profile.get("platform_id") not in platforms
        }
    )
    if unknown_profile_platforms:
        semantic_errors.append(
            "deployment profile(s) reference unknown platform_id value(s): "
            + ", ".join(str(item) for item in unknown_profile_platforms)
        )

    if semantic_errors:
        print("Manifest semantic validation failed:", file=sys.stderr)
        for error in semantic_errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        "Manifest validation passed: "
        f"schema_version={manifest.get('schema_version')}, "
        f"automation_release={manifest.get('automation_release')}, "
        f"platforms={len(platforms)}, "
        f"deployment_profiles={len(deployment_profiles)}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
