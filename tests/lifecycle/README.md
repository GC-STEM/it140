# Lifecycle Tests

This directory contains behavioral tests for the IT 140 lifecycle scripts. These tests complement the fast structural and syntax checks under `tests/ci/`; they do not replace qualification on the actual supported course environments.

The Verify suites established the common black-box conventions. The CVD, Ubuntu GNOME, macOS, and Windows Configure suites add mutation-specific conventions that later Configure, Update, Install, and Prepare suites can reuse.

## Test conventions

- **Black-box entry points:** Tests execute the production lifecycle entry point rather than sourcing individual functions.
- **Fixtures describe starting state:** A known base filesystem is copied into an isolated temporary directory for each scenario.
- **Mocks replace external dependencies:** External commands, operating-system observations, and desktop-integration APIs are controlled at the boundary appropriate to each platform; lifecycle decision logic is not mocked.
- **Scenario files describe expected behavior:** JSON files define arguments, controlled failures, expected exit codes, summary results, and diagnostic text.
- **Exit codes are API contracts:** The process exit code must match the lifecycle summary.
- **Filesystem snapshots enforce state boundaries:** Verify may not modify protected state. Mutating-stage tests instead snapshot paths that are outside the stage's ownership boundary and require them to remain unchanged.
- **Logs are checked semantically:** Tests parse stable summary fields instead of comparing an entire transcript as golden text.
- **Platform/stage harnesses stay isolated:** Shared snapshot and transcript behavior lives under `tests/lifecycle/common/`; stage- and platform-specific fixture construction and mocks live with each suite.
- **Idempotence is semantic:** A mutating stage may rewrite managed files or refresh metadata on a repeat run, but the resulting managed configuration and preserved user state must converge to the same semantic state.

## Current scope

### Verify

Behavioral Verify suites cover all supported lifecycle platform families:

- CVD: `scripts/cvd/verify_it140.sh`
- Ubuntu Desktop GNOME: `scripts/nix/ubg/verify_ubg.sh`
- macOS Apple silicon: `scripts/mac/verify_it140.zsh`
- Windows: `scripts/win/verify_it140.ps1`

Each Verify suite covers the same core behavioral contract:

- help and version output returning `0` without creating a verification log
- a compliant fixture with the network check skipped returning `0`
- a required-check failure returning `1`
- an unsupported platform, release, or deployment context returning `2`
- a malformed controlled manifest returning `5`
- semantic consistency among check records, summary counts, and the process exit code
- preservation of protected filesystem state
- creation and parsing of the verification transcript, including platform-appropriate permission assertions

The Ubuntu GNOME scripts currently retain their Alpha-era `*_ubg.sh` names. Keeping their lifecycle tests under `tests/lifecycle/verify/ubg/` localizes any future script rename.

### Configure

Behavioral Configure suites cover:

- CVD: `scripts/cvd/configure_it140.sh`
- Ubuntu Desktop GNOME: `scripts/nix/ubg/config_ubg.sh`
- macOS Apple silicon: `scripts/mac/configure_it140.zsh`
- Windows: `scripts/win/configure_it140.ps1`

They establish the shared mutation-specific contracts for:

- successful configuration (`0`)
- unsupported context before managed changes (`2`)
- required external-service failure retaining its lifecycle code before managed changes (`4`)
- malformed controlled configuration before managed changes (`5`)
- ordinary or external failure after managed changes resolving to `PARTIAL` (`7`)
- preservation of student repositories and unrelated user files
- merge-preservation behavior for shell and VS Code settings
- convergence of Git, VS Code extension, Python venv, desktop-integration, and workspace state
- semantic idempotence across two successful runs
- Configure transcript permissions and summary/exit-code consistency

The CVD suite additionally covers Xfce/Num Lock behavior. The Ubuntu GNOME suite covers managed Bash PATH blocks, GNOME/GIO workspace metadata, and the Desktop `Repos` link. The macOS suite covers managed Zsh PATH blocks, the Desktop `Repos` link, and `Visual Studio Code - Repos.app`. The Windows suite covers privilege-context enforcement, registry-backed user PATH semantics, merge-preserving VS Code settings, Python/extension/Git convergence, and the managed `Repos.lnk` and Visual Studio Code workspace shortcuts. See each platform suite README for its isolation model.

## Run locally

Run a suite on its matching platform from the repository root.

CVD or Ubuntu 24.04 Verify:

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

CVD Configure on a non-root Ubuntu 24.04 host:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/configure/cvd \
  -p 'test_*.py' \
  -v
```

Ubuntu GNOME Configure on a non-root Ubuntu 24.04 x86-64 host:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/configure/ubg \
  -p 'test_*.py' \
  -v
```

macOS Apple silicon Configure and Verify:

```zsh
python3 -m unittest discover \
  -s tests/lifecycle/configure/mac \
  -p 'test_*.py' \
  -v

python3 -m unittest discover \
  -s tests/lifecycle/verify/mac \
  -p 'test_*.py' \
  -v
```

Windows PowerShell Configure and Verify:

```powershell
python -m unittest discover `
  -s tests/lifecycle/configure/win `
  -p 'test_*.py' `
  -v

python -m unittest discover `
  -s tests/lifecycle/verify/win `
  -p 'test_*.py' `
  -v
```

The harness code uses only the Python standard library. Unix/macOS CI jobs install `jsonschema` so production shell lifecycle scripts validate the copied production manifest against its schema during behavioral tests.

## Configure test-isolation hooks

Test hooks are active only when the corresponding lifecycle-test environment variables are explicitly set. Normal course execution leaves them unset.

### Windows

- `IT140_CONFIGURE_TEST_ROOT` relocates user-profile paths used by Configure (`Repos`, Desktop, and VS Code user settings) into the temporary fixture.
- `IT140_CONFIGURE_TEST_STATE` identifies a JSON file containing deterministic observations and mutable managed state for Windows APIs and external boundaries that cannot safely be changed on a hosted runner, including elevation/Sandbox context, OS facts, user PATH, system commands, GitHub identity, Git settings, Python venv state, VS Code extensions, executable resolution, and `.lnk` shortcut definitions.

Windows Configure still executes as the production PowerShell entry point and performs its normal manifest validation, lifecycle branching, filesystem merges, state comparisons, summary generation, and exit-code resolution. Test state replaces external observations and unsafe host mutations only; it does not supply expected Configure results.

## Verify test-isolation hooks

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
- `IT140_VERIFY_TEST_STATE` identifies a JSON file containing deterministic observations for Windows APIs and external boundaries that cannot safely be represented by filesystem fixtures alone, including elevation/Sandbox context, OS facts, native-command results, Git/VS Code observations, pending-restart state, and `.lnk` shortcut definitions.

The Windows verifier still executes as the production PowerShell entry point and performs its normal comparisons, branching, result recording, summary generation, and exit-code resolution. The test state replaces external observations only; it does not supply expected verifier results.

## Qualification boundary

Passing lifecycle tests means the covered scripts behave correctly for the controlled fixtures and external observations in these suites. Release qualification must still include execution on the actual supported platform/course environment.
