# CI Tests

This directory contains fast, non-destructive checks used by `.github/workflows/ci.yml`.

- `detect_changes.py` maps changed paths to the affected platform jobs.
- `check_repo.py` confirms the expected automation files exist and that the controlled JSON files parse without duplicate keys.
- `check_manifest.py` validates the controlled manifest against its Draft 2020-12 JSON Schema and performs a small set of semantic sanity checks.

The platform jobs perform syntax parsing only:

- CVD and Ubuntu/Linux: `bash -n`
- macOS: `zsh -n`
- Windows: Windows PowerShell parser

These CI checks do not replace end-to-end qualification on the actual supported course environments.
