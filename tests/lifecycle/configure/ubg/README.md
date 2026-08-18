# Ubuntu GNOME Configure Lifecycle Tests

This suite executes the production `scripts/nix/ubg/config_ubg.sh` entry point as a black box on a non-root Ubuntu 24.04 CI host while redirecting user-space mutations into a temporary `HOME`.

## What the suite establishes

- successful configuration returns exit code `0`
- malformed controlled configuration returns exit code `5` before managed user changes
- an unsupported deployment profile returns exit code `2` before managed user changes
- a required external-service failure before managed changes retains exit code `4`
- an external failure after managed changes resolves to `PARTIAL` / exit code `7`
- student repository content and unrelated user files are preserved
- managed Bash PATH blocks converge without duplication
- existing unmanaged VS Code settings are preserved while managed settings are merged
- Git settings, VS Code extensions, Python venv packages, GNOME workspace metadata, the repository workspace, and Desktop `Repos` integration converge to the required state
- a second successful run converges to the same semantic managed state as the first run
- logs use the expected permissions and their summary agrees with the process exit code

## Isolation model

The suite uses the hosted runner's real Bash, Ubuntu 24.04 `/etc/os-release`, x86-64 architecture, core filesystem utilities, and Python runtime. External/course-specific boundaries are placed first on `PATH` and implemented by a stateful mock dispatcher:

- Git and GitHub CLI
- Visual Studio Code CLI
- Python 3.12 virtual-environment creation and venv package operations
- GNOME/GIO workspace metadata
- XDG desktop-directory lookup

The mock state persists across command invocations so Configure must perform the mutations it later depends on. For the pre-change GitHub outage scenario, the harness first runs the real production Configure script successfully to create canonical configured state, then injects only the measured external failure. Expected Configure results are never supplied by the mock.

## Run locally

Run from the repository root on a non-root Ubuntu 24.04 x86-64 host:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/configure/ubg \
  -p 'test_*.py' \
  -v
```

The suite is skipped on root-owned containers and non-Ubuntu/non-24.04 hosts rather than weakening the production Configure execution-context checks.
