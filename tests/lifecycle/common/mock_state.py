#!/usr/bin/env python3
"""Transactional JSON state helpers for lifecycle command mocks.

Mock dispatchers run as separate processes.  This module keeps their shared JSON
state valid under concurrency and merges each process's changes against the
latest on-disk state so independent updates are not silently lost.
"""
from __future__ import annotations

from contextlib import contextmanager
import copy
import json
import os
from pathlib import Path
import tempfile
import time
from typing import Any, Iterator

_BASELINES: dict[str, Any] = {}
_LOCK_TIMEOUT_SECONDS = 10.0
_STALE_LOCK_SECONDS = 300.0
_POLL_SECONDS = 0.01


def _key(path: Path) -> str:
    return str(path.resolve())


@contextmanager
def _state_lock(path: Path) -> Iterator[None]:
    """Acquire a small cross-platform interprocess lock beside ``path``."""
    lock_dir = path.with_name(path.name + ".lock")
    deadline = time.monotonic() + _LOCK_TIMEOUT_SECONDS
    while True:
        try:
            lock_dir.mkdir()
            break
        except FileExistsError:
            try:
                age = time.time() - lock_dir.stat().st_mtime
            except FileNotFoundError:
                continue
            if age > _STALE_LOCK_SECONDS:
                try:
                    lock_dir.rmdir()
                except (FileNotFoundError, OSError):
                    pass
                continue
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Timed out waiting for mock-state lock: {lock_dir}")
            time.sleep(_POLL_SECONDS)
    try:
        yield
    finally:
        try:
            lock_dir.rmdir()
        except FileNotFoundError:
            pass


def _read(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _atomic_write(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            dir=path.parent,
            prefix=path.name + ".",
            delete=False,
        ) as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
            temporary = Path(handle.name)
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _merge_list_delta(base: list[Any], current: list[Any], desired: list[Any]) -> list[Any]:
    if desired == base:
        return copy.deepcopy(current)

    removed = [item for item in base if item not in desired]
    added = [item for item in desired if item not in base]
    merged = [item for item in current if item not in removed]
    for item in added:
        if item not in merged:
            merged.append(copy.deepcopy(item))
    return merged


def _merge_delta(base: Any, current: Any, desired: Any) -> Any:
    """Apply the caller's base->desired delta to the latest current value."""
    if desired == base:
        return copy.deepcopy(current)

    if isinstance(base, dict) and isinstance(current, dict) and isinstance(desired, dict):
        merged = copy.deepcopy(current)
        for name in base.keys() - desired.keys():
            merged.pop(name, None)
        for name, desired_value in desired.items():
            if name not in base:
                merged[name] = copy.deepcopy(desired_value)
                continue
            current_value = current.get(name, copy.deepcopy(base[name]))
            merged[name] = _merge_delta(base[name], current_value, desired_value)
        return merged

    if isinstance(base, list) and isinstance(current, list) and isinstance(desired, list):
        return _merge_list_delta(base, current, desired)

    # Mock state uses integer fields primarily for invocation counters.  Apply
    # the caller's numeric delta to the latest value so two overlapping
    # increments cannot collapse into one.  Booleans are excluded even though
    # bool is an int subclass in Python.
    if (
        isinstance(base, int)
        and not isinstance(base, bool)
        and isinstance(current, int)
        and not isinstance(current, bool)
        and isinstance(desired, int)
        and not isinstance(desired, bool)
    ):
        return current + (desired - base)

    return copy.deepcopy(desired)


def load_state(path: Path) -> dict[str, Any]:
    """Load one state snapshot and remember the caller's merge baseline."""
    value = _read(path)
    if not isinstance(value, dict):
        raise TypeError(f"Mock state must be a JSON object: {path}")
    _BASELINES[_key(path)] = copy.deepcopy(value)
    return value


def save_state(path: Path, state: dict[str, Any]) -> None:
    """Transactionally merge and atomically save one mock-state update.

    ``state`` is refreshed in place to the merged value.  That matters when one
    dispatcher performs several saves during a single command invocation: later
    mutations then start from the most recent shared state rather than a stale
    process-local snapshot.
    """
    key = _key(path)
    with _state_lock(path):
        current = _read(path)
        if not isinstance(current, dict):
            raise TypeError(f"Mock state must be a JSON object: {path}")
        base = _BASELINES.get(key, copy.deepcopy(current))
        merged = _merge_delta(base, current, state)
        if not isinstance(merged, dict):
            raise TypeError(f"Mock state must remain a JSON object: {path}")
        _atomic_write(path, merged)

    state.clear()
    state.update(copy.deepcopy(merged))
    _BASELINES[key] = copy.deepcopy(merged)
