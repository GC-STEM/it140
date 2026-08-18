# macOS Configure Lifecycle Tests

This suite executes the production `scripts/mac/configure_it140.zsh` entry point as a black box on the GitHub Actions `macos-15` Apple-silicon runner while redirecting user-space mutations into a temporary `HOME`.

## What the suite establishes

- successful configuration returns exit code `0`
- malformed controlled configuration returns exit code `5` before managed user changes
- an unsupported deployment profile returns exit code `2` before managed user changes
- an ordinary failure after managed changes resolves to `PARTIAL` with exit code `7`
- a required external-service failure before managed changes retains exit code `4`
- the same external-service failure after managed changes resolves to `PARTIAL` with exit code `7`
- student repository content and unrelated user files are preserved
- managed PATH blocks replace stale and legacy content without duplication or repeat-run whitespace drift
- existing unmanaged VS Code settings are preserved while managed settings are merged
- Git identity/settings, VS Code extensions, Python venv packages, repository workspace integration, and the Visual Studio Code - Repos.app launcher converge to the required state
- a second successful run converges to the same semantic managed state as the first run
- logs use the expected permissions and their summary agrees with the process exit code

## Isolation model

The suite runs only on a non-root Apple-silicon macOS host. It uses the runner's real Zsh, macOS platform facts (`uname` and `sw_vers`), filesystem tools, and the Python 3.12 runtime installed by CI for Configure's controlled JSON and launcher logic.

Commands that represent mutable user tooling or external services are placed ahead of the host on `PATH` and implemented by the stateful mock dispatcher:

- Git and GitHub CLI
- Visual Studio Code CLI
- Python 3.12 virtual-environment creation (other Python 3.12 invocations pass through to the real CI runtime)
- virtual-environment package installation

The command wrappers are also placed in the fixture's managed `.venv/bin` path because production Configure deliberately prepends that directory and `/opt/homebrew/bin` to `PATH`. This keeps external boundaries mocked even after Configure applies its real PATH policy and prevents a preinstalled runner tool from silently escaping the harness.

The mock state persists across command invocations so the production Configure script must perform the mutations that later assertions inspect. Expected Configure results are never supplied by the mock.

A special preconfigured fixture is used for the external-service scenario so a GitHub API failure occurs before any managed change. This distinguishes the lifecycle contract for external failure (`4`) from the same type of failure after mutation, which must resolve to partial (`7`).

## Run locally

Run from the repository root on a supported Apple-silicon Mac with Python 3.12 and `jsonschema` available:

```zsh
python3 -m unittest discover \
  -s tests/lifecycle/configure/mac \
  -p 'test_*.py' \
  -v
```

The suite is skipped on non-macOS, Intel, and root-owned hosts rather than weakening production Configure execution-context checks.
