# CVD Configure Lifecycle Tests

This suite executes the production `scripts/cvd/configure_it140.sh` entry point as a black box on an Ubuntu 24.04 CI host while redirecting all user-space mutations into a temporary `HOME`.

## What the suite establishes

- successful configuration returns exit code `0`
- malformed controlled configuration returns exit code `5` before managed user changes
- an unsupported deployment profile returns exit code `2` before managed user changes
- an ordinary failure after managed changes resolves to partial-result exit code `7`
- a required external-service failure retains exit code `4`
- student repository content and unrelated user files are preserved
- managed PATH blocks replace stale content without duplication
- existing unmanaged VS Code settings are preserved while managed settings are merged
- Git settings, extensions, Num Lock state, repository workspace integration, and the existing VS Code desktop launcher converge to the required state
- a second successful run converges to the same semantic managed state as the first run
- logs use the expected permissions and their summary agrees with the process exit code

## Isolation model

The test runs only on a non-root Ubuntu 24.04 host. It uses the host's real Bash, core filesystem tools, `/etc/os-release`, and Python 3 runtime for the Configure script's own logic. External or course-environment-specific boundaries are placed ahead of the host on `PATH` and implemented by the stateful mock dispatcher:

- Git and GitHub CLI
- Visual Studio Code CLI
- Python 3.12 virtual-environment creation and venv package operations
- Xfce/GIO metadata
- Num Lock
- XDG desktop/file-association tools
- manifest-declared system commands

The mock state persists across command invocations so the script must actually perform the mutations it later validates. Expected Configure results are never supplied by the mock.

## Run locally

Run from the repository root on the CVD or another non-root Ubuntu 24.04 test host:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/configure/cvd \
  -p 'test_*.py' \
  -v
```

The suite is skipped on root-owned containers and non-Ubuntu/non-24.04 hosts rather than weakening the production Configure execution-context checks.
