# IT 140 macOS Lifecycle Script Update

- Artifact version: `0.6.0`
- Version date-time group: `2026-08-03-06-52`
- Status: Alpha Testing
- Target: `macos_bare_metal` on Apple silicon (`arm64`)
- Supported controlled manifest schema: `2.2`

## Included entry points

- `prepare_ide.zsh`
- `install_ide.zsh`
- `configure_ide.zsh`
- `verify_ide.zsh`
- `update_ide.zsh`

## Major alignment corrections

- Replaced legacy `automation_release_date` validation with `automation_release_date_time_group`.
- Updated managed-script validation from manifest schema `2.0` to `2.2`.
- Standardized the five lifecycle filenames and student-facing transitions.
- Corrected Prepare permissions from `*.sh` to `*.zsh`.
- Added minute-resolution artifact date-time groups, standardized exit codes, stale-lock recovery, profile-aware course-continuity guidance, and private logs under `~/it140/logs/`.
- Kept each lifecycle entry point self-contained; there is no distributed common-script dependency.
- Read concrete products, packages, extensions, and managed settings from the controlled manifest.
- Preserved the responsibility boundaries: Prepare refreshes the package, Install owns the system layer, Configure owns the user layer, Verify is read-only except approved reports, and Update owns maintenance assets and managed component updates.

## Repository issue requiring separate manifest correction

The current controlled manifest still identifies the macOS script extension as `.sh` and retains a legacy filename template even though the repository, SRS, SDD, pseudoscripts, and these lifecycle entry points use `.zsh` and `<action>_ide.zsh`. The scripts intentionally follow the current lifecycle artifacts and repository filenames rather than rejecting the current manifest for that known metadata inconsistency.

## Validation performed in the build environment

- UTF-8 and LF line endings
- Executable mode (`chmod -- 0755`) for every lifecycle script
- Shell syntax parsing with `bash -n` as a compatibility screen
- Static checks for required metadata, schema `2.2`, date-time-group usage, `.zsh` permissions, log paths, lifecycle names, and absence of the obsolete exact manifest key
- ZIP integrity and SHA-256 inventory

The build environment is Linux and does not include macOS, Z shell, JXA (`osascript`), Homebrew, or Visual Studio Code. Full clean-machine, repeated-run, interruption, and idempotence testing must therefore be completed on the approved Apple-silicon macOS alpha-test baseline before repository release.
