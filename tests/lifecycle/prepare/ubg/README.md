# Ubuntu GNOME Prepare Lifecycle Tests

This suite executes `scripts/nix/ubg/bootstrap_ubg.sh` as a black box and uses the CVD Prepare suite as the reference for safety, isolation, preservation, and idempotence principles.

The UBG bootstrap remains an Alpha-era implementation, so these tests are primarily **characterization/regression tests**. They protect its current behavior rather than refactoring it to match the newer package-wide Prepare specification.

## Confirmed path defect and narrow correction

Before this suite was added, `bootstrap_ubg.sh` referenced `scripts/nix/Ubuntu/` when making deployed scripts executable and when adding the lifecycle directory to `PATH`. The repository's actual directory is `scripts/nix/ubg/`.

That mismatch prevents the normal bootstrap path from completing after the repository has already been copied into `~/it140`. The accompanying production change therefore makes only these two path corrections:

- `scripts/nix/Ubuntu/` → `scripts/nix/ubg/` for `chmod`; and
- `scripts/nix/Ubuntu` → `scripts/nix/ubg` in the Bash `PATH` line.

No other production UBG Prepare behavior is changed by this work.

## Current behavior characterized

The suite checks that the corrected current bootstrap:

- runs as the production `bootstrap_ubg.sh` entry point;
- accepts the supported Ubuntu release family on the real Ubuntu CI host;
- retrieves the authorized `GC-STEM/it140` repository with a depth-1 Git clone;
- installs Git and certificate support through the script's existing APT path when Git is absent;
- preserves the prior course package if Git installation or repository clone fails before activation;
- preserves student repositories, nested student `.git` metadata, Git identity, personal Desktop files, and unrelated application configuration;
- removes the deployed course package's top-level `.git` metadata after a successful refresh;
- makes the UBG lifecycle scripts executable;
- adds the corrected `scripts/nix/ubg` PATH line without duplication on a rerun;
- cleans its temporary clone directory on success and tested failures; and
- converges to the same semantic package and user state after two successful runs.

The suite also deliberately records one current behavior that is **not a recommendation**: after cloning successfully, the Alpha-era bootstrap removes all existing top-level `~/it140` content except `logs` before copying the fresh package. The tests protect student and unrelated user state outside that package boundary but do not silently redesign this behavior during the current lifecycle-test effort.

## Isolation model

The harness redirects `HOME`, `TMPDIR`, Git clone content, `git`, and `sudo` into temporary fixtures and mocks. No live repository clone or APT change occurs during the behavioral tests.

The production script sources `/etc/os-release` and uses Bash's real `EUID` directly. Rather than adding test-only seams to an existing bootstrap script, the behavioral tests run only on a supported **non-root Ubuntu host**. The planned GitHub Actions job uses `ubuntu-24.04`.

A static contract test runs on any host and rejects a return of the incorrect `scripts/nix/Ubuntu` deployment path.

## Scenarios

| Scenario | Current expected behavior |
| --- | --- |
| `success.json` | exit `0`; fresh package deployed; corrected UBG PATH added |
| `clone_failure.json` | raw Git clone exit `128`; prior package preserved |
| `git_install_success.json` | Git absent; current sudo/APT bootstrap succeeds; clone then succeeds |
| `git_install_failure.json` | raw sudo/APT exit `100`; prior package preserved |
| `gnome_warning.json` | GNOME variables absent; warning emitted; bootstrap still succeeds |

## Run

From the repository root on a supported non-root Ubuntu host:

```bash
python3 -m unittest discover \
  -s tests/lifecycle/prepare/ubg \
  -p 'test_*.py' \
  -v
```

On other platforms, the static path-contract test runs and the Ubuntu behavioral class skips.

## Qualification boundary

Passing this suite means the covered UBG Prepare behavior is stable under controlled fixtures. It does not replace a qualification run on an actual supported Ubuntu Desktop GNOME environment.
