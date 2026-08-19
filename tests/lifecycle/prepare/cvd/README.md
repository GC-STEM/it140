# CVD Prepare Lifecycle Tests

This suite executes the **current Beta** `scripts/cvd/prepare_it140.sh` as a black box. It is a characterization/regression suite: it protects the behavior of the Alpha-tested/Beta-deployed script without changing that production script to conform to a newer test contract.

CVD Prepare is the reference Prepare suite for the behavioral-test project. Later platform suites can reuse its safety and preservation principles while adapting to each platform's existing Prepare implementation.

## Beta-protection rule

The production `scripts/cvd/prepare_it140.sh` is the system under test and is **not modified by this suite**. Tests intentionally record current behavior, including current error-status behavior that may differ from the newer package-wide specification.

Examples of current behavior preserved by these tests:

- an unsupported CVD processor architecture currently exits `4` before a Prepare log is created;
- root execution currently exits `3` before a Prepare log is created;
- a `curl` download failure currently preserves the raw `curl` status (the test uses `22`);
- an archive missing a required CVD lifecycle script currently exits `6`;
- a sanitizer failure after the package overlay currently exits `1`; and
- the first-use bootstrap success message currently tells the user to close the Terminal rather than directly printing `update_it140.sh`.

Those observations are **characterizations, not recommendations**. They can be reconsidered in a later automation release without risking the current Beta baseline.

## Regression protections

The suite checks that the current Prepare implementation:

- can refresh the installed automation package successfully;
- can execute its first-use bootstrap path without Git, GitHub CLI, APT, the controlled manifest, or another lifecycle script;
- obtains the authorized repository archive over HTTPS with the current bounded `curl` options;
- validates the downloaded archive before overlaying it;
- preserves the existing package when download or structural validation fails before the overlay;
- preserves the student repository workspace, nested `.git` metadata, Git identity, personal Desktop files, unrelated application configuration, and unrelated course-root files;
- overlays repository-managed package files without deleting unmatched course-root content;
- removes the deployed package's top-level `.git` metadata after a successful overlay;
- makes the CVD lifecycle scripts executable;
- adds the current CVD PATH line without duplicating it on rerun;
- invokes the CVD sanitizer after activation;
- cleans temporary `it140-prepare.*` staging directories after success and tested failures; and
- converges to the same semantic package/user state after two successful refreshes.

## Isolation model

The harness redirects `HOME`, `TMPDIR`, repository download content, and the commands `id`, `uname`, and `curl` into temporary fixtures. The downloaded archive is generated locally; no GitHub network call occurs during the behavioral tests.

The harness deliberately provides only the baseline commands used by the current Prepare script. Git, `gh`, APT, package managers, and later-stage course tools are not placed on the test PATH.

The production script currently sources `/etc/os-release` directly. Rather than adding a test-only filesystem seam to a field-tested Beta script, this suite requires an **Ubuntu host**. The planned CVD Prepare GitHub Actions job should therefore run on `ubuntu-24.04`. On a non-Ubuntu host the test class skips.

The archive contains test placeholders for Install, Configure, Verify, Update, and a harmless test sanitizer. The production `sanitize_CVD.sh` is not executed by this isolated suite; its real behavior remains part of CVD qualification testing.

## Scenarios

| Scenario | Current expected behavior |
| --- | --- |
| `success.json` | exit `0`; package overlaid; sanitizer completes |
| `unsupported.json` | exit `4`; no Prepare log; prior package preserved |
| `privilege_failure.json` | exit `3`; no Prepare log; prior package preserved |
| `external_failure.json` | raw `curl` exit `22`; log created; prior package preserved |
| `archive_failure.json` | exit `6`; log created; prior package preserved |
| `sanitize_failure.json` | exit `1`; log created; overlay/PATH changes already applied |

Additional tests cover first-use bootstrap success/failure, the download command contract, pre-overlay preservation, the sanitizer/overlay boundary, and semantic idempotence.

## Run

From the repository root on Ubuntu:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/prepare/cvd \
  -p 'test_*.py' \
  -v
```

## Qualification boundary

Passing this suite means the current CVD Prepare script retains the covered behavior under controlled fixtures. It does not replace a real CVD qualification run using the live GitHub archive and the production `sanitize_CVD.sh`.
