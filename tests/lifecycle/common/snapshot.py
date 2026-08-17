#!/usr/bin/env python3
"""Filesystem snapshot helpers for lifecycle state-boundary tests."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
import stat


@dataclass(frozen=True)
class SnapshotEntry:
    """Stable metadata recorded for one filesystem object."""

    object_type: str
    mode: int | None
    size: int | None
    mtime_ns: int | None
    digest: str | None = None
    link_target: str | None = None


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _entry(path: Path) -> SnapshotEntry:
    if not path.exists() and not path.is_symlink():
        return SnapshotEntry("missing", None, None, None)

    metadata = path.lstat()
    mode = stat.S_IMODE(metadata.st_mode)
    common = {
        "mode": mode,
        "size": metadata.st_size,
        "mtime_ns": metadata.st_mtime_ns,
    }

    if stat.S_ISLNK(metadata.st_mode):
        return SnapshotEntry(
            "symlink",
            link_target=path.readlink().as_posix(),
            **common,
        )
    if stat.S_ISREG(metadata.st_mode):
        return SnapshotEntry("file", digest=_sha256(path), **common)
    if stat.S_ISDIR(metadata.st_mode):
        return SnapshotEntry("directory", **common)
    return SnapshotEntry("other", **common)


def snapshot_path(path: Path) -> dict[str, SnapshotEntry]:
    """Snapshot one file/directory without following symlinks."""

    path = path.resolve() if not path.is_symlink() else path.absolute()
    snapshot = {".": _entry(path)}
    if not path.is_dir() or path.is_symlink():
        return snapshot

    for child in sorted(path.rglob("*"), key=lambda item: item.as_posix()):
        relative = child.relative_to(path).as_posix()
        snapshot[relative] = _entry(child)
    return snapshot


def snapshot_paths(paths: dict[str, Path]) -> dict[str, dict[str, SnapshotEntry]]:
    """Snapshot named protected paths."""

    return {name: snapshot_path(path) for name, path in paths.items()}


def snapshot_differences(
    before: dict[str, dict[str, SnapshotEntry]],
    after: dict[str, dict[str, SnapshotEntry]],
) -> list[str]:
    """Return human-readable differences between two protected snapshots."""

    differences: list[str] = []
    for name in sorted(set(before) | set(after)):
        left = before.get(name, {})
        right = after.get(name, {})
        for relative in sorted(set(left) | set(right)):
            if left.get(relative) != right.get(relative):
                differences.append(
                    f"{name}:{relative}: before={left.get(relative)!r}; "
                    f"after={right.get(relative)!r}"
                )
    return differences
