#!/usr/bin/env python3
"""Reject accidental macOS script variables that collide with Zsh specials.

The macOS lifecycle scripts run under Zsh. Zsh exposes several shell-managed
parameters whose names look like ordinary variables (for example ``commands``,
``path``, and ``status``). Reusing one of those names for local state can change
its type or trigger a runtime error even when ``zsh -n`` reports valid syntax.

This check asks the runner's Zsh for its currently defined special parameters,
including the parameters supplied by ``zsh/parameter``, and compares those
names with ordinary assignment/declaration targets in ``scripts/mac/*.zsh``.
Intentional use of shell interface parameters is narrowly allowlisted.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SCRIPT_DIR = ROOT / "scripts" / "mac"
DEFAULT_ZSH = Path("/bin/zsh")

# These are deliberately used for their shell-defined behavior, not as ordinary
# application variables. Keep this allowlist small and require review to expand.
INTENTIONAL_SPECIAL_PARAMETERS = frozenset({"IFS", "PATH"})

# Discovery must include the three names that motivated this regression guard.
# If one is absent, the Zsh discovery command is not giving us the protection we
# expect and CI should fail closed rather than silently weakening the check.
REQUIRED_DISCOVERED_SPECIALS = frozenset({"commands", "path", "status"})

IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_]*"
DECLARATION_RE = re.compile(
    rf"\b(?:local|typeset|readonly|integer|float|export)\b(?P<body>[^;}}]*)"
)
READ_RE = re.compile(r"\bread\b(?P<body>[^;}]*)")
FOR_RE = re.compile(rf"\bfor\s+(?P<name>{IDENTIFIER})\s+(?:in\b|\()")
DECLARED_NAME_RE = re.compile(
    rf"(?:^|\s)(?P<name>{IDENTIFIER})(?=\s|\+?=|\[|$)"
)
STATEMENT_ASSIGNMENT_RE = re.compile(
    rf"(?:^\s*|[;{{]\s*|\bthen\s+|\bdo\s+|\belse\s+)"
    rf"(?P<name>{IDENTIFIER})\s*\+?="
)
ARITHMETIC_RE = re.compile(r"\(\((?P<body>.*?)\)\)")
ARITHMETIC_ASSIGNMENT_RE = re.compile(
    rf"(?:(?P<prefix>\+\+|--)?(?P<name>{IDENTIFIER})\s*"
    rf"(?P<operator>\+\+|--|(?:<<|>>|[+\-*/%&|^])?=))"
)
HEREDOC_RE = re.compile(
    r"<<-?(?!<)\s*(?:'(?P<single>[^']+)'|\"(?P<double>[^\"]+)\"|(?P<bare>[A-Za-z_][A-Za-z0-9_]*))"
)


@dataclass(frozen=True, order=True)
class Candidate:
    path: Path
    line_number: int
    name: str
    kind: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Reject ordinary macOS Zsh variables that collide with Zsh special parameters."
    )
    parser.add_argument(
        "--script-dir",
        type=Path,
        default=DEFAULT_SCRIPT_DIR,
        help="Directory containing macOS .zsh lifecycle scripts.",
    )
    parser.add_argument(
        "--zsh",
        type=Path,
        default=DEFAULT_ZSH,
        help="Zsh executable used to discover special parameters.",
    )
    return parser.parse_args()


def discover_special_parameters(zsh: Path) -> set[str]:
    """Return special parameter names reported by the runner's Zsh."""
    program = r"""
emulate -L zsh
zmodload zsh/parameter
for name in ${(k)parameters}; do
    [[ ${parameters[$name]} == *special* ]] && print -r -- "$name"
done
"""
    try:
        completed = subprocess.run(
            [str(zsh), "-f", "-c", program],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(f"Zsh executable not found: {zsh}") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip() or f"exit code {exc.returncode}"
        raise RuntimeError(f"Could not discover Zsh special parameters: {detail}") from exc

    names = {line.strip() for line in completed.stdout.splitlines() if line.strip()}
    missing = REQUIRED_DISCOVERED_SPECIALS - names
    if missing:
        raise RuntimeError(
            "Zsh special-parameter discovery is incomplete; missing expected names: "
            + ", ".join(sorted(missing))
        )
    return names


def mask_quotes_and_comments(line: str) -> str:
    """Mask quoted text and comments while preserving shell syntax positions."""
    chars = list(line.rstrip("\n"))
    masked = chars.copy()
    quote: str | None = None
    escaped = False
    index = 0

    while index < len(chars):
        char = chars[index]
        if escaped:
            if quote is not None:
                masked[index] = " "
            escaped = False
            index += 1
            continue

        if char == "\\" and quote != "'":
            if quote is not None:
                masked[index] = " "
            escaped = True
            index += 1
            continue

        if quote is not None:
            masked[index] = " "
            if char == quote:
                quote = None
            index += 1
            continue

        if char in {"'", '"'}:
            quote = char
            masked[index] = " "
            index += 1
            continue

        if char == "#":
            for rest in range(index, len(masked)):
                masked[rest] = " "
            break

        index += 1

    return "".join(masked)


def heredoc_delimiter(line: str) -> tuple[str, bool] | None:
    """Return the first unquoted here-document delimiter on a shell line."""
    quote: str | None = None
    escaped = False
    index = 0

    while index < len(line) - 1:
        char = line[index]
        if escaped:
            escaped = False
            index += 1
            continue
        if char == "\\" and quote != "'":
            escaped = True
            index += 1
            continue
        if quote is not None:
            if char == quote:
                quote = None
            index += 1
            continue
        if char in {"'", '"'}:
            quote = char
            index += 1
            continue
        if char == "#":
            return None
        if not line.startswith("<<", index):
            index += 1
            continue
        if line.startswith("<<<", index):
            index += 3
            continue

        cursor = index + 2
        strip_tabs = False
        if cursor < len(line) and line[cursor] == "-":
            strip_tabs = True
            cursor += 1
        while cursor < len(line) and line[cursor].isspace():
            cursor += 1
        if cursor >= len(line):
            return None

        if line[cursor] in {"'", '"'}:
            delimiter_quote = line[cursor]
            cursor += 1
            end = line.find(delimiter_quote, cursor)
            if end == -1:
                return None
            delimiter = line[cursor:end]
        else:
            match = re.match(IDENTIFIER, line[cursor:])
            if not match:
                return None
            delimiter = match.group(0)
        return delimiter, strip_tabs

    return None


def declared_names(body: str) -> set[str]:
    """Extract parameter names from a declaration/read argument region."""
    names: set[str] = set()
    for match in DECLARED_NAME_RE.finditer(body):
        name = match.group("name")
        # A declaration option such as -a NAME cannot match because the option's
        # leading '-' prevents the identifier from starting at whitespace.
        names.add(name)
    return names


def scan_script(path: Path) -> list[Candidate]:
    """Find ordinary shell variable targets without executing the script."""
    candidates: set[Candidate] = set()
    active_heredoc: tuple[str, bool] | None = None

    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            if active_heredoc is not None:
                delimiter, strip_tabs = active_heredoc
                comparison = raw_line.rstrip("\r\n")
                if strip_tabs:
                    comparison = comparison.lstrip("\t")
                if comparison == delimiter:
                    active_heredoc = None
                continue

            new_heredoc = heredoc_delimiter(raw_line)
            masked = mask_quotes_and_comments(raw_line)

            for match in DECLARATION_RE.finditer(masked):
                for name in declared_names(match.group("body")):
                    candidates.add(Candidate(path, line_number, name, "declaration"))

            for match in READ_RE.finditer(masked):
                body = re.split(r"[<>]", match.group("body"), maxsplit=1)[0]
                for name in declared_names(body):
                    candidates.add(Candidate(path, line_number, name, "read target"))

            for match in FOR_RE.finditer(masked):
                candidates.add(Candidate(path, line_number, match.group("name"), "for-loop target"))

            for match in STATEMENT_ASSIGNMENT_RE.finditer(masked):
                candidates.add(Candidate(path, line_number, match.group("name"), "assignment"))

            for arithmetic in ARITHMETIC_RE.finditer(masked):
                for match in ARITHMETIC_ASSIGNMENT_RE.finditer(arithmetic.group("body")):
                    candidates.add(
                        Candidate(path, line_number, match.group("name"), "arithmetic assignment")
                    )

            if new_heredoc is not None:
                active_heredoc = new_heredoc

    return sorted(candidates)


def relative_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def main() -> int:
    args = parse_args()
    script_dir = args.script_dir.resolve()
    files = sorted(script_dir.glob("*.zsh"))
    if not files:
        print(f"No macOS Zsh scripts found in {script_dir}.", file=sys.stderr)
        return 1

    try:
        special_parameters = discover_special_parameters(args.zsh)
    except RuntimeError as exc:
        print(f"Zsh special-parameter guard failed: {exc}", file=sys.stderr)
        return 1

    protected_parameters = special_parameters - INTENTIONAL_SPECIAL_PARAMETERS
    violations: list[Candidate] = []
    for path in files:
        for candidate in scan_script(path):
            if candidate.name in protected_parameters:
                violations.append(candidate)

    if violations:
        print("Zsh special-parameter guard failed:", file=sys.stderr)
        for violation in sorted(violations):
            print(
                f"- {relative_path(violation.path)}:{violation.line_number}: "
                f"{violation.name!r} is a Zsh special parameter used as an ordinary "
                f"{violation.kind}.",
                file=sys.stderr,
            )
        print(
            "Rename each ordinary script variable. Expand "
            "INTENTIONAL_SPECIAL_PARAMETERS only when the script deliberately needs "
            "the shell-defined parameter behavior.",
            file=sys.stderr,
        )
        return 1

    allowed = ", ".join(sorted(INTENTIONAL_SPECIAL_PARAMETERS))
    print(
        "Zsh special-parameter guard passed: "
        f"{len(files)} scripts checked against {len(special_parameters)} special parameters; "
        f"intentional shell parameters allowed: {allowed}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
