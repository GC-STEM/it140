#!/usr/bin/env python3
"""Semantic parser for IT 140 Verify transcripts."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


CHECK_RE = re.compile(
    r"^(?:\[(PASS|WARNING|FAIL|NOT APPLICABLE)\]|"
    r"(PASS|WARNING|FAIL|NOT APPLICABLE))\s+"
    r"(verify\.[^\s]+)\s+(.*)$"
)
SUMMARY_RE = re.compile(r"^([A-Za-z][A-Za-z ]*?)\s*:\s*(.*)$")
SUMMARY_KEYS = {
    "result",
    "script version",
    "version dtg",
    "manifest release",
    "manifest dtg",
    "passed",
    "warnings",
    "failed",
    "not applicable",
    "elapsed time",
    "log file",
    "exit code",
}


@dataclass(frozen=True)
class CheckRecord:
    status: str
    check_id: str
    detail: str


@dataclass(frozen=True)
class VerifyTranscript:
    checks: tuple[CheckRecord, ...]
    summary: dict[str, str]
    text: str

    @property
    def checks_by_id(self) -> dict[str, CheckRecord]:
        return {record.check_id: record for record in self.checks}

    def status_count(self, status: str) -> int:
        return sum(1 for record in self.checks if record.status == status)


def parse_verify_text(text: str) -> VerifyTranscript:
    """Parse shell-style and Windows PowerShell Verify transcripts semantically."""

    checks: list[CheckRecord] = []
    summary: dict[str, str] = {}

    for original_line in text.splitlines():
        line = original_line.strip()
        check_match = CHECK_RE.match(line)
        if check_match:
            bracket_status, plain_status, check_id, detail = check_match.groups()
            checks.append(
                CheckRecord(bracket_status or plain_status, check_id, detail)
            )
            continue

        # Windows Write-Info prefixes summary records with [INFO]. Unix Verify
        # summaries are plain text. Strip only this known presentation prefix.
        summary_line = line[7:].lstrip() if line.startswith("[INFO] ") else line
        summary_match = SUMMARY_RE.match(summary_line)
        if summary_match:
            key, value = summary_match.groups()
            normalized = " ".join(key.lower().split())
            if normalized in SUMMARY_KEYS:
                summary[normalized] = value.strip()

    return VerifyTranscript(tuple(checks), summary, text)


def _decode_transcript(data: bytes) -> str:
    """Decode Unix or Windows PowerShell transcript encodings safely."""

    for encoding in ("utf-8-sig", "utf-16", "utf-16-le"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def parse_verify_log(path: Path) -> VerifyTranscript:
    return parse_verify_text(_decode_transcript(path.read_bytes()))


def summary_int(transcript: VerifyTranscript, key: str) -> int | None:
    value = transcript.summary.get(key)
    if value is None:
        return None
    match = re.match(r"^-?\d+", value)
    return int(match.group(0)) if match else None


def consistency_errors(
    transcript: VerifyTranscript,
    process_exit_code: int,
) -> list[str]:
    """Check semantic consistency where the corresponding summary fields exist."""

    errors: list[str] = []
    summary_exit = summary_int(transcript, "exit code")
    if summary_exit is not None and summary_exit != process_exit_code:
        errors.append(
            f"summary exit code {summary_exit} != process exit code {process_exit_code}"
        )

    count_fields = {
        "passed": "PASS",
        "warnings": "WARNING",
        "failed": "FAIL",
        "not applicable": "NOT APPLICABLE",
    }
    for field, status in count_fields.items():
        summary_count = summary_int(transcript, field)
        if summary_count is None:
            continue
        actual_count = transcript.status_count(status)
        if summary_count != actual_count:
            errors.append(
                f"summary {field}={summary_count} != {status} records={actual_count}"
            )

    failed = summary_int(transcript, "failed")
    result = transcript.summary.get("result")
    if failed is not None and result is not None:
        expected_result = (
            "COMPLIANT"
            if failed == 0 and process_exit_code == 0
            else "NOT COMPLIANT"
        )
        if result != expected_result:
            errors.append(f"result {result!r} != expected {expected_result!r}")

    return errors
