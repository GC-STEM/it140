# macOS Prepare Lifecycle Tests

This suite exercises the current Beta `scripts/mac/prepare_it140.zsh` lifecycle entry point as a characterization/regression target. It follows the safety, preservation, idempotence, and CI-integration lessons established by the CVD and Ubuntu GNOME Prepare suites while reusing the macOS platform conventions already used by the Install, Configure, Verify, and Update suites.

## Beta-protection rule

The production macOS Prepare script is **not changed by this suite**. The current script was already field-verified during Beta testing, so the tests protect its behavior instead of adding a test-only production seam or refactoring working lifecycle logic.

The suite validates the current production contract for:

- Apple-silicon macOS and standard-user context checks;
- `--help`, `--version`, and unsupported-option behavior before log creation;
- native-tool-only preparation without Homebrew, Git, the controlled manifest, or another lifecycle script as a prerequisite;
- the approved GitHub archive URL and bounded five-attempt download loop;
- staged ZIP extraction and structural validation before activation;
- manifest and schema JSON validation with native `osascript`;
- preservation of prior critical macOS automation assets when download or staged-package validation fails;
- repository overlay without deleting unmatched course-root or macOS-script-directory files;
- removal of only the deployed package's top-level `.git` metadata while preserving nested student repository metadata;
- executable lifecycle scripts after activation;
- replacement of legacy/current managed Zsh PATH blocks with one canonical block;
- private Prepare logs and temporary-file cleanup; and
- semantic idempotence across two successful runs.

## Isolation model

`prepare_it140.zsh` deliberately calls `/usr/bin/curl`, `/usr/bin/ditto`, and `/usr/bin/osascript` by absolute path. Changing those calls or adding a test seam would modify a protected Beta script. Instead, the harness creates a **temporary execution copy** of the production script and substitutes only its `ARCHIVE_URL` declaration with a loopback HTTP URL. A static test proves that this is the only textual change from production.

The loopback server supplies deterministic ZIP payloads for success, missing-file, malformed-manifest, and HTTP-failure scenarios. No live GitHub archive request occurs during the behavioral suite. The real macOS `/usr/bin/curl`, `/usr/bin/ditto`, `/usr/bin/osascript`, filesystem semantics, and Zsh runtime are still exercised on the `macos-15` Apple-silicon GitHub Actions runner.

The production HTTPS source contract is tested separately against the unmodified source. PATH-level mocks are limited to `id`, `uname`, and `sleep` so the suite can exercise unsupported-architecture, root-context, and bounded-retry behavior without altering the hosted runner or waiting through exponential backoff.

Nested `.git` directories are created at runtime inside the temporary fixture. They are never stored as nested Git repositories in the course repository.

## Scenarios

| Scenario | Expected current behavior |
| --- | --- |
| `success.json` | exit `0`; package activated; scripts executable; PATH converged |
| `unsupported_arch.json` | exit `2`; no archive request; prior critical assets preserved |
| `privilege_failure.json` | exit `2`; no archive request; prior critical assets preserved |
| `download_failure.json` | exit `4`; five failed requests; prior critical assets preserved |
| `archive_failure.json` | exit `5`; staged package missing a required script; prior critical assets preserved |
| `manifest_failure.json` | exit `5`; staged manifest invalid JSON; prior critical assets preserved |
| `post_change_failure.json` | exit `7`; controlled PATH-stage failure after activation; prior critical scripts/manifest restored |

Additional tests cover help/version/invalid-option behavior, native/HTTPS static contracts, loopback-copy integrity, user-state preservation, private log permissions, temporary cleanup, managed PATH replacement, and semantic idempotence.

## Run

From the repository root on Apple-silicon macOS:

```zsh
python3 -m unittest discover \
  -s tests/lifecycle/prepare/mac \
  -p 'test_*.py' \
  -v
```

On other hosts, the source-level contract tests run and the macOS behavioral class skips.

## Qualification boundary

Passing this suite means the covered Prepare behavior is stable under controlled fixtures on the real macOS hosted runner. It does not replace final qualification on a supported local Apple-silicon Mac using the live approved GitHub archive.
