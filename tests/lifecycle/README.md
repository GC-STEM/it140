# Lifecycle Tests

This directory contains behavioral tests for the IT 140 lifecycle scripts. These tests complement the fast structural and syntax checks under `tests/ci/`; they do not replace qualification on the actual supported course environments.

The Verify suites established the common black-box conventions. Configure and Install now have behavioral coverage across all four supported platform families. The CVD Update suite extends those conventions to controlled-asset refresh, maintenance, restart-required outcomes, and post-update verification and serves as the reference pattern for the remaining Update suites.

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

### Install

Install behavioral suites now cover:

- CVD: `scripts/cvd/install_it140.sh`
- Ubuntu Desktop GNOME: `scripts/nix/ubg/setup_ubg.sh`
- macOS Apple silicon: `scripts/mac/install_it140.zsh`
- Windows bare metal: `scripts/win/install_it140.ps1`

They establish system-mutation contracts for:

- successful installation (`0`)
- unsupported context (`2`) and unavailable required privilege (`3`) before managed changes
- required external-source failure (`4`) before or after managed changes while preserving the specific external-service classification
- malformed controlled configuration (`5`) before managed changes
- post-install verification failure resolving to `PARTIAL` (`7`)
- preservation of student repositories and unrelated user configuration
- convergence of manifest-declared APT packages and approved repository artifacts
- CVD-specific Noto Color Emoji health, Xfce Num Lock autostart, and Chrome managed bookmarks
- Ubuntu GNOME-specific GitHub CLI and Visual Studio Code APT repository/key artifacts
- macOS-specific Homebrew formula/cask convergence while preserving compatible preexisting applications
- Windows-specific WinGet capability convergence while preserving compatible preexisting applications regardless of package-manager provenance
- semantic idempotence across two successful runs
- Install transcript permissions and summary/exit-code consistency

See `tests/lifecycle/install/cvd/README.md`, `tests/lifecycle/install/ubg/README.md`, `tests/lifecycle/install/mac/README.md`, and `tests/lifecycle/install/win/README.md` for the platform isolation models.

### Update

Update behavioral suites now cover all four supported platform families:

- CVD: `scripts/cvd/update_it140.sh`
- Ubuntu Desktop GNOME: `scripts/nix/ubg/update_ubg.sh`
- macOS Apple silicon: `scripts/mac/update_it140.zsh`
- Windows bare metal: `scripts/win/update_it140.ps1`

The Update suites establish maintenance-stage contracts for:

- successful controlled-manifest refresh and maintenance (`0`)
- unsupported context (`2`) and unavailable required privilege (`3`) before managed changes
- required external-source failure retaining its lifecycle classification (`4`) before or after managed changes
- malformed controlled configuration (`5`) before managed changes
- ordinary failure after managed changes resolving to `PARTIAL` (`7`)
- Ubuntu restart-required state resolving to `PARTIAL` (`7`) even when no required operation failed (CVD and Ubuntu GNOME)
- preservation of student repositories and unrelated user configuration
- convergence of manifest-declared system components, the course Python venv, and VS Code extensions
- CVD-specific Noto Color Emoji/fontconfig health and Xfce Num Lock autostart
- Ubuntu GNOME APT maintenance without an Ubuntu release upgrade
- macOS Homebrew formula/cask maintenance without a macOS major-version upgrade
- Windows WinGet course-component maintenance without running Windows Update
- validation and controlled activation of downloaded maintenance assets according to the platform implementation
- semantic idempotence across two successful runs
- Update transcript permissions and summary/exit-code consistency

Each Update-script change also routes through that platform's existing Verify suite as an independent end-state regression oracle.

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

CVD Install on Linux with the suite's isolated system-root seam:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/install/cvd \
  -p 'test_*.py' \
  -v
```

CVD Update on Linux with the suite's isolated system-root seam:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/update/cvd \
  -p 'test_*.py' \
  -v
```

Ubuntu GNOME Update on Ubuntu/Linux with isolated package/system boundaries:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/update/ubg \
  -p 'test_*.py' \
  -v
```

Ubuntu GNOME Install on Ubuntu/Linux with isolated APT/system paths:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/install/ubg \
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

macOS Apple silicon Install, Configure, and Verify:

```zsh
python3 -m unittest discover \
  -s tests/lifecycle/install/mac \
  -p 'test_*.py' \
  -v

python3 -m unittest discover \
  -s tests/lifecycle/update/mac \
  -p 'test_*.py' \
  -v

python3 -m unittest discover \
  -s tests/lifecycle/configure/mac \
  -p 'test_*.py' \
  -v

python3 -m unittest discover \
  -s tests/lifecycle/verify/mac \
  -p 'test_*.py' \
  -v
```

Windows PowerShell Install, Configure, and Verify:

```powershell
python -m unittest discover `
  -s tests/lifecycle/install/win `
  -p 'test_*.py' `
  -v

python -m unittest discover `
  -s tests/lifecycle/update/win `
  -p 'test_*.py' `
  -v

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

## Update test-isolation hooks

Test hooks are active only when explicitly set by the lifecycle harness. Normal course execution leaves them unset.

### CVD

- `IT140_UPDATE_TEST_MODE=true` explicitly enables CVD Update isolation; normal CVD execution leaves it unset.
- `IT140_UPDATE_TEST_ROOT` redirects the operating-system release fixture plus the Xfce Num Lock autostart and reboot-required files that Update reads directly.
- `IT140_UPDATE_TEST_EUID` supplies a deterministic non-root effective-user value only while Update test mode is active.

APT, `sudo`, repository archive download, package queries, fontconfig, VS Code, Git/GitHub observations, and desktop-entry validation remain external boundaries supplied through the test `PATH`. The production Update entry point still validates and atomically activates the downloaded controlled manifest/schema pair, performs lifecycle branching and maintenance, runs post-update checks, generates the transcript/summary, and resolves the process exit code.

### Ubuntu GNOME

- `IT140_UPDATE_TEST_MODE=true` explicitly enables Ubuntu GNOME Update isolation.
- `IT140_UPDATE_TEST_ROOT` redirects `/etc/os-release` and reboot-required state into the temporary fixture tree.
- `IT140_UPDATE_TEST_EUID` supplies a deterministic non-root effective-user value only while test mode is active.

APT, `sudo`, package queries, Git retrieval, Python, and VS Code are supplied through the test `PATH`; normal Ubuntu GNOME execution remains manifest-driven and never performs an Ubuntu release upgrade.

### macOS

- `IT140_UPDATE_TEST_MODE=true` explicitly enables macOS Update isolation.
- `IT140_UPDATE_TEST_BREW_PATH` supplies a stateful fake Homebrew executable.
- `IT140_UPDATE_TEST_NETWORK_RESULT`, `IT140_UPDATE_TEST_ADMIN_RESULT`, `IT140_UPDATE_TEST_ARCHIVE_PATH`, and `IT140_UPDATE_TEST_DOWNLOAD_RESULT` make approved-source, administrator, and archive observations deterministic.

These seams are inert in normal execution. The suite still runs the production Zsh entry point on the Apple-silicon macOS runner and uses the real macOS manifest parser/filesystem behavior.

### Windows

- `IT140_UPDATE_TEST_MODE=true` explicitly enables Windows Update isolation.
- `IT140_UPDATE_TEST_STATE` identifies a temporary JSON state file that substitutes hosted-runner observations for UAC/administrator state, Windows release facts, required command availability, free space, package state, and user-tool state.

Normal Windows execution leaves these variables unset and continues to use real Windows APIs, WinGet, UAC, managed user settings, and system-drive state. The test seam never enables Windows Update or an OS release upgrade.

## Install test-isolation hooks

Test hooks are active only when explicitly set by the lifecycle harness. Normal course execution leaves them unset.

### CVD

- `IT140_INSTALL_TEST_MODE=true` explicitly enables the CVD Install isolation seams. With test mode unset, normal production behavior is used even if a test-root variable is present.
- `IT140_INSTALL_TEST_ROOT` redirects the operating-system release fixture and the Num Lock/Chrome policy files that Install later reads directly. With test mode disabled, those paths remain the production `/etc/...` locations.
- `IT140_INSTALL_TEST_EUID` supplies a deterministic effective-user value only while Install test mode/root isolation is active.

APT, `sudo`, vendor downloads, package queries, fontconfig, and desktop-entry validation remain external boundaries supplied through the test `PATH`. The production Install entry point still performs its normal manifest validation, lifecycle branching, managed-file generation, post-install verification, summary generation, and exit-code resolution.

### Ubuntu GNOME

- `IT140_INSTALL_TEST_MODE=true` explicitly enables Ubuntu GNOME Install isolation. Normal course execution leaves it unset.
- `IT140_INSTALL_TEST_ROOT` redirects `/etc/os-release` and the GitHub CLI / Visual Studio Code APT source and keyring files into the temporary fixture tree.
- `IT140_INSTALL_TEST_EUID` supplies a deterministic non-root effective-user value only while Install test isolation is active.

APT, `sudo`, repository downloads, package queries, `gpg`, and system-file writes remain external boundaries supplied through the test `PATH`. The real `setup_ubg.sh` entry point still performs manifest validation, lifecycle branching, capability decisions, post-install validation, summary generation, and exit-code resolution.

### macOS

- `IT140_INSTALL_TEST_MODE=true` explicitly enables macOS Install isolation; normal course execution leaves it unset.
- `IT140_INSTALL_TEST_BREW_PATH` supplies a stateful fake Homebrew executable so the hosted runner is never modified by package installation.
- `IT140_INSTALL_TEST_NETWORK_RESULT` supplies deterministic approved-source availability (`success` or `failure`) without coupling lifecycle semantics to current GitHub service health.
- `IT140_INSTALL_TEST_ADMIN_RESULT` supplies the Administrator-account observation needed to exercise exit code `3` without altering runner privileges.

The suite still uses the real macOS Apple-silicon runner for Darwin/arm64, `sw_vers`, Xcode Command Line Tools, filesystem behavior, `osascript` manifest parsing, and the production Zsh transcript path. These seams are inert unless explicit test mode is enabled.

### Windows

- `IT140_INSTALL_TEST_MODE=true` explicitly enables Windows Install isolation; normal course execution leaves it unset.
- `IT140_INSTALL_TEST_STATE` identifies a JSON file containing deterministic observations and mutable external state for administrator context, Windows release facts, system-drive free space, WinGet availability/ownership, command capabilities, and package-install outcomes.

Windows Install still executes as the production PowerShell entry point and performs its normal manifest validation, lifecycle branching, capability/provenance decisions, post-install validation, summary generation, and exit-code resolution. The state seam replaces hosted-runner observations and unsafe package-manager mutation only; it does not supply expected Install results.

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
