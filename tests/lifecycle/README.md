# Lifecycle Tests

This directory contains behavioral tests for the IT 140 lifecycle scripts. These tests complement the fast structural and syntax checks under `tests/ci/`; they do not replace qualification on the actual supported course environments.

The current Verify suites establish reusable conventions for later Configure, Update, Install, and Prepare tests while keeping platform-specific fixtures and mocks isolated.

## Test conventions

- **Black-box entry points:** Tests execute the production lifecycle entry point rather than sourcing individual functions.
- **Fixtures describe starting state:** A known-good base filesystem is copied into an isolated temporary directory for each scenario.
- **Mocks replace external dependencies:** External commands, operating-system observations, and desktop-integration APIs are controlled at the boundary appropriate to each platform; verifier decision logic is not mocked.
- **Scenario files describe expected behavior:** JSON files define arguments, controlled failures, expected exit codes, key check results, and remediation text.
- **Exit codes are API contracts:** The process exit code must match the verifier summary.
- **Filesystem snapshots enforce state boundaries:** Protected user/course paths must not change during Verify. The verification transcript is the normal allowed filesystem output.
- **Logs are checked semantically:** Tests parse stable check IDs and summary fields instead of comparing an entire transcript as golden text.
- **Platform-specific harnesses stay isolated:** Shared snapshot/log behavior lives under `tests/lifecycle/common/`; platform-specific fixture construction and mocks live with each Verify suite.

## Current scope

Behavioral Verify suites cover all supported lifecycle platform families:

- CVD: `scripts/cvd/verify_it140.sh`
- Ubuntu Desktop GNOME: `scripts/nix/ubg/verify_ubg.sh`
- macOS Apple silicon: `scripts/mac/verify_it140.zsh`
- Windows: `scripts/win/verify_it140.ps1`

Each platform suite covers the same core behavioral contract:

- help and version output returning `0` without creating a verification log
- a compliant fixture with the network check skipped returning `0`
- a required-check failure returning `1`
- an unsupported platform, release, or deployment context returning `2`
- a malformed controlled manifest returning `5`
- semantic consistency among check records, summary counts, and the process exit code
- preservation of protected filesystem state
- creation and parsing of the verification transcript, including platform-appropriate permission assertions

The Ubuntu GNOME scripts currently retain their Alpha-era `*_ubg.sh` names. Keeping their lifecycle tests under `tests/lifecycle/verify/ubg/` localizes any future script rename.

## Run locally

Run a suite on its matching platform from the repository root.

CVD or Ubuntu 24.04:

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

macOS Apple silicon:

```zsh
python3 -m unittest discover \
  -s tests/lifecycle/verify/mac \
  -p 'test_*.py' \
  -v
```

Windows PowerShell:

```powershell
python -m unittest discover `
  -s tests/lifecycle/verify/win `
  -p 'test_*.py' `
  -v
```

The harness code uses only the Python standard library. The Unix/macOS CI jobs install `jsonschema` so production shell verifiers validate the copied production manifest against its schema during behavioral tests.

## Test-isolation hooks

Test hooks are active only when the corresponding lifecycle-test environment variables are explicitly set. Normal course execution leaves them unset.

### CVD and Ubuntu GNOME

- `IT140_VERIFY_TEST_ROOT` redirects verifier reads of system fixture files such as `/etc/os-release` into the temporary fixture tree. CVD also uses it for the Xfce Num Lock autostart fixture.
- `IT140_VERIFY_TEST_EUID` supplies a deterministic non-root effective-user value while test-root mode is active.

When test-root mode is active, these verifiers write directly to their transcript instead of using asynchronous `tee` process substitution. This keeps short-lived test processes deterministic while preserving transcript contents and permissions.

### macOS

- `IT140_VERIFY_TEST_ROOT` enables deterministic test transcript handling but does not redirect macOS system files or platform facts. The CI suite runs on the actual `macos-15` Apple-silicon runner for `uname`, `sw_vers`, and Xcode Command Line Tools checks.
- `IT140_VERIFY_TEST_EUID` supplies a deterministic non-root effective-user value while test-root mode is active.

Manifest-declared/user commands such as Git, GitHub CLI, Homebrew, and VS Code are supplied through the test `PATH`; the real Python 3.12 runtime installed by CI validates controlled JSON and launcher content.

### Windows

- `IT140_VERIFY_TEST_ROOT` relocates user-profile paths used by Verify (`Repos`, Desktop, and VS Code user settings) into the temporary fixture.
- `IT140_VERIFY_TEST_STATE` identifies a JSON file containing deterministic observations for Windows APIs and external boundaries that cannot be safely represented by filesystem fixtures alone, including elevation/Sandbox context, OS facts, native-command results, Git/VS Code observations, pending-restart state, and `.lnk` shortcut definitions.

The Windows verifier still executes as the production PowerShell entry point and performs its normal comparisons, branching, result recording, summary generation, and exit-code resolution. The test state replaces external observations only; it does not supply expected verifier results.

## Qualification boundary

Passing lifecycle tests means each verifier behaves correctly for the controlled fixtures and external observations in these suites. Release qualification must still include execution on the actual supported platform/course environment.
