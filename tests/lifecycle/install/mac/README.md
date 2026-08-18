# macOS Install Lifecycle Tests

This suite executes the production `scripts/mac/install_it140.zsh` entry point on the GitHub-hosted `macos-15` Apple-silicon runner.

## Isolation model

The suite deliberately keeps the macOS production environment observations that are safe and useful to exercise for real: Zsh, Darwin/arm64, `sw_vers`, Xcode Command Line Tools, filesystem semantics, `osascript` manifest processing, and the production transcript implementation.

Three explicit Install test seams make external or host-mutating boundaries deterministic:

- `IT140_INSTALL_TEST_MODE=true` enables the seams. They are inert in normal course execution.
- `IT140_INSTALL_TEST_BREW_PATH` supplies a stateful fake Homebrew executable so CI never installs or modifies host packages.
- `IT140_INSTALL_TEST_NETWORK_RESULT` supplies `success` or `failure` for the approved-source availability observation, avoiding dependence on live GitHub service health during lifecycle semantics tests.
- `IT140_INSTALL_TEST_ADMIN_RESULT` supplies the Administrator-account observation so exit-code `3` can be tested without changing the runner account.

The harness creates a temporary `HOME`, copies the production Install script and controlled manifest/schema into that home, and supplies package executables through a temporary test `PATH`. Homebrew installation state is held in JSON and mutated only by the fake Homebrew boundary. The Visual Studio Code cask creates a minimal valid bundle under the temporary user's `~/Applications`, never `/Applications`.

## Behavioral contract

The suite covers:

- `--help` and `--version` returning `0` without creating a log;
- successful manifest-declared system installation (`0/PASS`);
- unsupported deployment context (`2/FAIL`);
- unavailable required privilege (`3/FAIL`);
- external-source failure before managed changes (`4/FAIL`);
- malformed controlled configuration (`5/FAIL`);
- an ordinary package-install failure after a prior managed change resolving to `7/PARTIAL`;
- preservation of student repositories and unrelated user files;
- log permissions and summary/process exit-code agreement;
- semantic idempotence across two successful runs.

A passing suite is not a replacement for end-to-end qualification on a real student Mac. The August 18 faculty-verified successful macOS lifecycle behavior remains the production baseline; the test seams are explicitly gated and do not execute unless CI sets test mode.
