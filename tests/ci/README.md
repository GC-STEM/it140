# CI Tests

This directory contains fast, non-destructive structural checks used by `.github/workflows/ci.yml`.

- `detect_changes.py` maps changed paths to the affected static/syntax and lifecycle-test jobs.
- `check_repo.py` confirms the expected automation and lifecycle-test files exist and that the controlled JSON files parse without duplicate keys.
- `check_manifest.py` validates the controlled manifest against its Draft 2020-12 JSON Schema and performs a small set of semantic sanity checks.

The platform syntax jobs perform parsing only:

- CVD and Ubuntu/Linux: `bash -n`
- macOS: `zsh -n`
- Windows: Windows PowerShell parser

Behavioral lifecycle tests live under `tests/lifecycle/`. CI currently executes:

- CVD: `CVD Verify lifecycle tests`
- CVD: `CVD Configure lifecycle tests`
- Ubuntu Desktop GNOME: `Ubuntu GNOME Verify lifecycle tests`
- macOS Apple silicon: `macOS Verify lifecycle tests`
- Windows: `Windows Verify lifecycle tests`

The change detector routes shared lifecycle infrastructure changes to all affected behavioral suites. Platform/stage-specific test changes run only the corresponding behavioral job, while controlled manifest/schema and CI-infrastructure changes exercise every current contract.

Neither the fast CI checks nor the behavioral lifecycle tests replace end-to-end qualification on the actual supported course environments.
