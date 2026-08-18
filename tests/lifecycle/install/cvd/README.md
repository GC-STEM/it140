# CVD Install Lifecycle Tests

This suite exercises `scripts/cvd/install_it140.sh` as a black-box lifecycle entry point on an isolated Ubuntu fixture.

## Coverage

The suite verifies:

- `--help` and `--version` return `0` without creating an Install transcript
- successful system-layer installation returns `0` / `PASS`
- unsupported deployment context returns `2`
- unavailable passwordless privilege returns `3`
- required external-source failure returns `4`
- malformed controlled configuration returns `5`
- post-install verification failure returns `7` / `PARTIAL`
- an external failure after a managed change retains the specific external-service code while reporting `Managed changes: Yes`
- system integration files converge to the required Num Lock and Chrome managed-bookmark content
- package state converges to the manifest-declared required system packages
- student repositories and unrelated user configuration remain unchanged
- two successful runs are semantically idempotent
- transcript summary fields agree with the process exit code

## Isolation model

The production Install entry point is executed directly. External commands that would mutate the hosted runner (`sudo`, APT, vendor-key downloads, package queries, fontconfig, and desktop validation) are supplied through a test `PATH` and record deterministic state in JSON.

`IT140_INSTALL_TEST_MODE=true` explicitly enables the isolation seams. `IT140_INSTALL_TEST_ROOT` is a test-only production seam that redirects only the system files Install later reads directly. `IT140_INSTALL_TEST_EUID` provides a deterministic non-root effective-user observation while that test root is active. Both are unset during normal course execution.

The fixture deliberately contains student and unrelated user files. Those paths are snapshotted before and after each run and must remain unchanged.

Run on a non-root Ubuntu host or in CI with:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/install/cvd \
  -p 'test_*.py' \
  -v
```
