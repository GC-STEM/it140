#!/usr/bin/env python3
"""Semantic parser for IT 140 Configure transcripts."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re

SUMMARY_RE = re.compile(r"^([A-Za-z][A-Za-z ]*?)\s*:\s*(.*)$")
SUMMARY_KEYS = {
    "conclusion",
    "result",
    "script version",
    "version dtg",
    "manifest release",
    "manifest dtg",
    "repository root",
    "warnings",
    "failures",
    "start time",
    "end time",
    "managed changes",
    "elapsed time",
    "next step",
    "log file",
    "exit code",
}


@dataclass(frozen=True)
class ConfigureTranscript:
    """Structured Configure summary plus the original transcript text."""

    summary: dict[str, str]
    text: str


def parse_configure_text(text: str) -> ConfigureTranscript:
    """Parse stable Configure summary fields without depending on prose layout."""

    summary: dict[str, str] = {}
    for original_line in text.splitlines():
        line = original_line.strip()
        match = SUMMARY_RE.match(line)
        if not match:
            continue
        key, value = match.groups()
        normalized = " ".join(key.lower().split())
        if normalized in SUMMARY_KEYS:
            summary[normalized] = value.strip()
    return ConfigureTranscript(summary, text)


def parse_configure_log(path: Path) -> ConfigureTranscript:
    return parse_configure_text(path.read_text(encoding="utf-8", errors="replace"))


def summary_int(transcript: ConfigureTranscript, key: str) -> int | None:
    value = transcript.summary.get(key)
    if value is None:
        return None
    match = re.match(r"^-?\d+", value)
    return int(match.group(0)) if match else None


def consistency_errors(
    transcript: ConfigureTranscript,
    process_exit_code: int,
) -> list[str]:
    """Validate stable relationships among Configure summary fields."""

    errors: list[str] = []
    summary_exit = summary_int(transcript, "exit code")
    if summary_exit is None:
        errors.append("configuration summary does not contain a numeric exit code")
    elif summary_exit != process_exit_code:
        errors.append(
            f"summary exit code {summary_exit} != process exit code {process_exit_code}"
        )

    result = transcript.summary.get("result")
    expected_result = "PASS" if process_exit_code == 0 else (
        "PARTIAL" if process_exit_code == 7 else "FAIL"
    )
    if result != expected_result:
        errors.append(f"result {result!r} != expected {expected_result!r}")

    managed = transcript.summary.get("managed changes")
    if managed not in {"Yes", "No"}:
        errors.append(f"managed changes {managed!r} is not Yes or No")

    return errors
