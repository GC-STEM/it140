# Ubuntu GNOME Install Lifecycle Tests

This suite exercises `scripts/nix/ubg/setup_ubg.sh` as the Ubuntu GNOME **Install** lifecycle entry point on an isolated Ubuntu fixture.

## Coverage

The suite verifies:

- `--help` and `--version` return `0` without creating an Install transcript
- successful system-layer installation returns `0` / `PASS`
- unsupported deployment context returns `2`
- unavailable required privilege returns `3`
- required external-source failure returns `4` before or after managed changes while preserving the external-service classification
- malformed controlled configuration returns `5`
- ordinary post-install failure after managed changes resolves to `7` / `PARTIAL`
- manifest-declared Ubuntu APT packages and required system capabilities converge
- approved GitHub CLI and Visual Studio Code repository artifacts converge without touching unrelated user files
- student repositories and unrelated user configuration remain unchanged
- two successful runs are semantically idempotent
- transcript summary fields agree with the process exit code

## Isolation model

The production `setup_ubg.sh` entry point is executed directly. External commands that would mutate the hosted runner (`sudo`, APT, package queries, repository-key downloads, `gpg`, and system-file writes) are supplied through a test `PATH` and record deterministic state in JSON.

`IT140_INSTALL_TEST_MODE=true` explicitly enables the isolation seams. `IT140_INSTALL_TEST_ROOT` redirects only operating-system and approved APT repository files that Install otherwise reads or writes under `/etc` and `/usr/share`. `IT140_INSTALL_TEST_EUID` supplies a deterministic non-root effective-user observation while test isolation is active. All three are unset during normal course execution.

The fixture deliberately contains student and unrelated user files. Those paths are snapshotted before and after each run and must remain unchanged.

Run from the repository root on Ubuntu/Linux:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/install/ubg \
  -p 'test_*.py' \
  -v
```
