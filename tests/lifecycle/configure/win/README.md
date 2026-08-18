# Windows Configure Behavioral Tests

This suite exercises `scripts/win/configure_it140.ps1` as a black-box Windows PowerShell process on the GitHub Actions Windows runner.

## Coverage

The scenarios validate the shared Configure lifecycle contract plus Windows-specific behavior:

- successful configuration returns `0` / `PASS`
- malformed controlled configuration before mutation returns `5` / `FAIL`
- unsupported Windows release before mutation returns `2` / `FAIL`
- invalid elevation context before mutation returns `3` / `FAIL`
- required external-service failure before mutation returns `4` / `FAIL`
- failure after managed state changes returns `7` / `PARTIAL`
- unrelated repository, Desktop, application, Git, VS Code, extension, and PATH state is preserved
- managed user PATH, Git identity/settings, Python venv packages, VS Code extensions/settings, repository workspace, and desktop shortcuts converge to the required state
- a second successful run is semantically idempotent and reports no managed changes
- the Configure transcript result, managed-change state, and exit code agree with the process exit code
- `-Help` and `-Version` return `0` without entering the lifecycle mutation path

## Isolation model

The test suite runs the production PowerShell entry point. Two test-only environment variables isolate Windows APIs and state that cannot safely be changed on a hosted CI runner:

- `IT140_CONFIGURE_TEST_ROOT` relocates user-profile paths into the temporary fixture.
- `IT140_CONFIGURE_TEST_STATE` supplies deterministic observations for elevation/Sandbox context, Windows release facts, user PATH, system commands, GitHub identity, Git settings, Python venv state, VS Code extensions, executable resolution, and `.lnk` shortcut definitions.

Normal course execution leaves these variables unset, so production continues to use the real Windows APIs, registry, commands, and shell integration.

The fixture also contains student/unrelated files that Configure must not modify. Scenario expectations describe lifecycle behavior; the test state supplies environmental observations only and does not provide expected results.

## Run locally

From the repository root on Windows:

```powershell
python -m unittest discover `
  -s tests/lifecycle/configure/win `
  -p 'test_*.py' `
  -v
```
