# Lifecycle Tests

This directory contains behavioral tests for the IT 140 lifecycle scripts. These tests complement the fast structural and syntax checks under `tests/ci/`; they do not replace qualification on the actual supported course environments.

The current Verify suites establish reusable conventions for later Configure, Update, Install, and Prepare tests while keeping platform-specific fixtures and mocks isolated.

## Test conventions

- **Black-box entry points:** Tests execute the production lifecycle entry point rather than sourcing individual functions.
- **Fixtures describe starting state:** A known-good base filesystem is copied into an isolated temporary directory for each scenario.
- **Mocks replace external dependencies:** Commands such as `gh`, `git`, `code`, `gio`, package tools, and desktop utilities are replaced through a test `PATH`; verifier logic is not mocked.
- **Scenario files describe expected behavior:** JSON files define arguments, controlled failures, expected exit codes, key check results, and remediation text.
- **Exit codes are API contracts:** The process exit code must match the verifier summary.
- **Filesystem snapshots enforce state boundaries:** Protected user/course paths must not change during Verify. The verification transcript is the normal allowed filesystem output.
- **Logs are checked semantically:** Tests parse stable check IDs and summary fields instead of comparing an entire transcript as golden text.
- **Platform-specific harnesses stay isolated:** Shared snapshot/log behavior lives under `tests/lifecycle/common/`; platform-specific fixture construction and mocks live with each Verify suite.

## Current scope

Behavioral Verify suites currently cover:

- CVD: `scripts/cvd/verify_it140.sh`
- Ubuntu Desktop GNOME: `scripts/nix/ubg/verify_ubg.sh`

Each suite covers:

- `--help` and `--version` returning `0` without creating a log
- a compliant fixture with `--skip-network` returning `0`
- a required-check failure returning `1`
- an unsupported deployment profile returning `2`
- a malformed manifest returning `5`
- log directory/file permissions
- semantic consistency among check records, summary counts, and the process exit code
- preservation of protected filesystem state

The Ubuntu GNOME scripts currently retain their Alpha-era `*_ubg.sh` names. Keeping their lifecycle tests under `tests/lifecycle/verify/ubg/` localizes any future script rename.

## Run locally

From the repository root on Ubuntu 24.04:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/verify/cvd \
  -p 'test_*.py' \
  -v

python3 -m unittest discover \
  -s tests/lifecycle/verify/ubg \
  -p 'test_*.py' \
  -v
```

The test harness uses only the Python standard library. If `jsonschema` is installed, the production verifiers also validate the copied production manifest against its schema, just as they normally do.

## Shell Verify test-isolation hooks

The CVD and Ubuntu GNOME shell verifiers expose two environment variables only for isolated lifecycle tests:

- `IT140_VERIFY_TEST_ROOT` redirects verifier reads of system fixture files such as `/etc/os-release` into the temporary fixture tree. CVD also uses it for the Xfce Num Lock autostart fixture.
- `IT140_VERIFY_TEST_EUID` supplies a deterministic non-root effective-user value when `IT140_VERIFY_TEST_ROOT` is active, which allows the suites to run from root-owned development containers without weakening normal execution.

When `IT140_VERIFY_TEST_ROOT` is active, each verifier writes directly to its transcript instead of using asynchronous `tee` process substitution. This keeps short-lived test processes deterministic while preserving the transcript contents and permissions asserted by the suite. These hooks are inert during normal course execution.

## Qualification boundary

Passing lifecycle tests means the verifier behaves correctly for the controlled fixtures and mocks in these suites. Release qualification must still include execution on the actual supported platform/course environment.
