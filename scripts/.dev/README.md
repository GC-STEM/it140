# IT 140 Course Automation Scripts

This directory contains development-only analysis, design, pseudoscript, and test artifacts for the IT 140 course automation package. Student installations may omit `scripts/.dev/`; operational files must not depend on this directory.

## Package Lifecycle

Each supported platform implementation provides four lifecycle scripts:

1. `setup_<platform>.<ext>` installs or repairs system-level course software.
2. `config_<platform>.<ext>` applies user-specific course settings and integrations.
3. `verify_<platform>.<ext>` performs read-only checks and produces support diagnostics.
4. `update_<platform>.<ext>` updates approved software and course-managed assets.

Setup, configure, and update are designed to be idempotent. Verify remains read-only and identifies whether setup, configure, update, or technical support owns the remediation.

## Authoritative Engineering Artifacts

| Artifact | Repository path | Purpose |
| --- | --- | --- |
| Software Requirements Specification | `scripts/.dev/analysis/it140_scripts_srs.md` | Defines required behavior, constraints, and acceptance criteria. |
| Software Design Description | `scripts/.dev/design/it140_scripts_sdd.md` | Defines architecture, data, interfaces, control flow, and safety design. |
| Manifest schema | `scripts/.manifest/it140_manifest.schema.json` | Defines the valid machine-readable manifest structure. |
| Controlled manifest | `scripts/.manifest/it140_manifest.json` | Selects approved products, versions, sources, platforms, deployment profiles, settings, and managed assets. |
| Platform-agnostic pseudoscripts | `scripts/.dev/pseudoscripts/` | Describe shared lifecycle logic before platform-specific construction. |
| Development tests | `scripts/.dev/tests/` | Verify parsing, safety boundaries, adapters, idempotence, and acceptance behavior. |

The manifest and schema are operational course-managed assets and must remain available in student clones or copied installations even when `.dev/` is excluded.

## Reference and Supported Deployments

The reference deployment is the **Codio Virtual Desktop** using:

- Ubuntu 24.04 LTS
- Advanced Package Tool (APT)
- Xfce
- x86_64
- A hosted remote graphical desktop session

Supported local deployment profiles are:

- Supported Windows 11 on x86_64 bare metal
- Supported macOS on Apple Silicon bare metal
- Ubuntu 24.04 LTS with APT and GNOME on x86_64 bare metal

The reference designation controls primary documentation, screenshots, support reproduction, and release acceptance testing. All supported platforms must still provide equivalent required course outcomes.

## Initial Conformance-Test Resources

Available resettable test systems support the initial qualification matrix:

- Codio Virtual Desktop provider reset for the reference environment
- Windows bare-metal fresh installation
- macOS bare-metal fresh installation
- Ubuntu bare-metal fresh installation
- Raspberry Pi 4B and 5 for exploratory Ubuntu ARM64 testing
- Windows XP, 7, and 8 for negative unsupported-platform tests

Raspberry Pi ARM64 is not a supported deployment until the complete conformance suite passes for a declared desktop profile. Windows XP, 7, and 8 must be rejected safely before managed changes.

## Responsibility Boundaries

- `setup` may change system-level state but does not perform personal account authentication or user-preference configuration.
- `configure` changes only the current user's course-managed settings and integrations.
- `verify` does not install, repair, update, remove, or rewrite managed state.
- `update` may change only manifest-declared software, settings, and managed assets.
- Files outside declared managed paths are user-owned.
- Every run saves a timestamped log or transcript under `~/it140/logs/`.

## Construction Status

The package is under active development. Existing scripts may still use the shorter `config_<platform>` filename while the approved architecture standardizes new lifecycle entry points on `config_<platform>`. Construction work should trace each implementation unit and test to the current SRS, SDD, schema, and manifest.
