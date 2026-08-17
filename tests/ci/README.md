# CI Tests

This directory contains fast, non-destructive structural checks used by `.github/workflows/ci.yml`.

- `detect_changes.py` maps changed paths to the affected static/syntax and lifecycle-test jobs.
- `check_repo.py` confirms the expected automation and first-generation lifecycle-test files exist and that the controlled JSON files parse without duplicate keys.
- `check_manifest.py` validates the controlled manifest against its Draft 2020-12 JSON Schema and performs a small set of semantic sanity checks.

The platform syntax jobs perform parsing only:

- CVD and Ubuntu/Linux: `bash -n`
- macOS: `zsh -n`
- Windows: Windows PowerShell parser

Behavioral lifecycle tests live under `tests/lifecycle/`. The first-generation `CVD Verify lifecycle tests` job executes the production CVD Verify entry point against isolated fixtures and mocked external commands.

Neither the fast CI checks nor the behavioral lifecycle tests replace end-to-end qualification on the actual supported course environments.
