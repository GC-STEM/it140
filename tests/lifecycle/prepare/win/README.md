# Windows Prepare Lifecycle Tests

This suite exercises the current Beta `scripts/win/prepare_it140.ps1` bootstrap command set as a characterization/regression target. It applies the preservation, isolation, idempotence, and CI-integration lessons from the CVD, Ubuntu GNOME, and macOS Prepare suites while reusing the Windows hosted-runner conventions already used by the Install, Configure, Verify, and Update suites.

## Beta-protection rule

The production Windows Prepare file is **not changed by this suite**. The file intentionally models the commands students copy and run before the managed Windows lifecycle begins. It therefore differs from later Windows stages in important ways:

- it has no parameter block or managed `--help`/`--version` interface;
- it does not read the controlled manifest;
- it starts a PowerShell transcript rather than producing a managed lifecycle summary;
- it uses `curl.exe` when available and falls back to `Invoke-WebRequest`;
- it overlays the downloaded repository before checking that `scripts/win/` exists; and
- failures use PowerShell's current terminating-error behavior rather than the managed lifecycle exit-code taxonomy.

The suite protects that current behavior rather than refactoring a working Beta bootstrap into the newer Prepare architecture.

## Current behavior characterized

The tests cover:

- the approved HTTPS GitHub archive source;
- the current `curl.exe` retry/resume options and native `Invoke-WebRequest` fallback;
- archive extraction and first-directory selection;
- repository overlay while preserving unmatched course-root files;
- removal of only the deployed package's top-level `.git` directory;
- preservation of student repositories, nested student `.git` metadata, Git identity, personal Desktop content, and unrelated application configuration;
- Windows lifecycle-script availability after a successful overlay;
- persistent user-PATH convergence that places `scripts/win` first, removes equivalent duplicates, and preserves unrelated entries;
- the production source contract for adding the Windows scripts to the current-session PATH;
- temporary bootstrap-directory cleanup on success and tested failures;
- PowerShell transcript creation; and
- semantic idempotence across two successful runs.

The suite deliberately records a current behavior that is **not a recommendation**: validation that the downloaded package contains `scripts/win/` occurs after the repository has already been copied into `~/it140`. A structurally inadequate archive can therefore leave package changes behind before failing. Likewise, a failure while persisting the user PATH occurs after the package overlay and has no rollback. The tests characterize these post-overlay failures without redesigning the Beta bootstrap.

## Isolation model

The production script directly calls .NET user-profile and persistent user-environment APIs. Running those calls unmodified on a hosted runner would write into the runner account rather than the temporary fixture. The harness therefore executes a **temporary copy** of the production script with four narrowly verified isolation substitutions:

1. the approved archive URL is redirected to a deterministic loopback HTTP server;
2. the two user-profile lookups are redirected to the fixture home;
3. the persistent user-PATH read is redirected to a child-process test variable; and
4. the persistent user-PATH write is redirected to that child variable plus a temporary state file.

A source-level test reconstructs the original file by reversing those exact substitutions and requires byte-for-byte equality with production. The production file contains no `IT140_PREPARE_TEST_*` seam.

The loopback server supplies deterministic ZIP payloads. The normal success scenario uses the real Windows `curl.exe`. A second success scenario removes executable search paths from the child process so `Get-Command curl.exe` fails and the real `Invoke-WebRequest` fallback is exercised. No live GitHub request occurs during behavioral CI.

The harness follows the existing Windows lifecycle suites by resolving temporary roots before building expected path strings, avoiding hosted-runner 8.3 alias mismatches. Nested `.git` fixture metadata is created at runtime rather than stored in the repository.

## Scenarios

| Scenario | Current expected behavior |
| --- | --- |
| `success.json` | exit `0`; real `curl.exe`; package activated; user PATH converged |
| `iwr_success.json` | exit `0`; real `Invoke-WebRequest` fallback; package activated; user PATH converged |
| `download_failure.json` | exit `1`; failure before overlay; prior course payload preserved except expected transcript/log state |
| `archive_failure.json` | exit `1`; ZIP lacks a repository directory; failure before overlay; prior course payload preserved |
| `missing_windows_scripts.json` | exit `1`; overlay occurs, then missing `scripts/win/` is detected; no rollback |
| `path_failure.json` | exit `1`; package overlay succeeds, isolated persistent-PATH write fails; no rollback |

Additional tests cover download-branch selection, user-PATH de-duplication, user-state preservation, top-level versus nested Git metadata, temporary cleanup, production-source isolation integrity, and semantic idempotence.

## Run

From the repository root on Windows PowerShell:

```powershell
python -m unittest discover `
  -s tests/lifecycle/prepare/win `
  -p 'test_*.py' `
  -v
```

On non-Windows hosts, the source-level contract tests run and the Windows behavioral class skips.

## Qualification boundary

Passing this suite means the covered Windows bootstrap behavior is stable under controlled fixtures on the `windows-2025` hosted runner. It does not replace a qualification run on a supported local Windows environment using the live approved GitHub archive and the actual user-profile environment store.
