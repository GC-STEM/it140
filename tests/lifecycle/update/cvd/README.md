# CVD Update Lifecycle Tests

This suite exercises `scripts/cvd/update_it140.sh` as a black-box lifecycle entry point on an isolated Ubuntu fixture. It is the reference Update behavioral suite for later Ubuntu GNOME, macOS, and Windows Update coverage.

The harness copies the production Update script and controlled manifest/schema into a temporary `HOME`, preserves student and unrelated user files, and replaces only external/system boundaries with stateful command mocks. The production script still performs its own manifest validation, lifecycle branching, archive activation, package/Python/VS Code maintenance, user-configuration detection, post-update checks, transcript generation, and exit-code resolution.

## Covered contracts

- successful maintenance returns `0 / PASS`
- unsupported execution context returns `2`
- unavailable passwordless privilege returns `3`
- required external-source failures retain `4`, including after a controlled manifest change
- malformed local controlled configuration returns `5`
- ordinary failure after a managed change resolves to `7 / PARTIAL`
- a required CVD restart resolves to `7 / PARTIAL` with `Restart required: Yes`
- student repositories and unrelated user configuration remain unchanged
- system packages, Python tools, VS Code extensions, Noto Color Emoji, and Num Lock integration converge
- a fully configured user environment directs a successful Update to Verify
- repeated successful Update runs converge to the same semantic managed state
- transcript permissions and process/summary exit codes agree

## Test isolation hooks

The production script honors these only when `IT140_UPDATE_TEST_MODE=true`:

- `IT140_UPDATE_TEST_ROOT` redirects `/etc/os-release`, the Xfce Num Lock autostart file, and `/var/run/reboot-required` into the temporary fixture.
- `IT140_UPDATE_TEST_EUID` supplies a deterministic effective-user observation.

APT, `sudo`, archive retrieval, package queries, fontconfig, Python venv package operations, VS Code extensions, Git/GitHub observations, Xfce metadata, and Num Lock state are supplied through the test `PATH`. Normal CVD execution leaves all test variables unset.

Run from the repository root:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/update/cvd \
  -p 'test_*.py' \
  -v
```
