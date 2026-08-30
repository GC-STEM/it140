<!-- To see this file in a clean, formatted view, right-click on the filename and choose “Open Preview.” -->

# Controlled Manifest and Schema Guide

This guide explains the controlled configuration files in `scripts/.manifest/`, how the IT 140 Course Automation Scripts use them, and how maintainers should review, validate, change, and release them.

> [!IMPORTANT]
> This README is informative and navigational, not normative. It does not establish or replace requirements, design decisions, schema rules, approved configuration, qualification evidence, or release approval. The [Software Requirements Specification](../.dev/analysis/it140_scripts_srs.md) defines required behavior, the [Software Design Description](../.dev/design/it140_scripts_sdd.md) defines the approved high-level design, the [manifest schema](it140_manifest.schema.json) defines the permitted JSON structure, and the [controlled manifest](it140_manifest.json) selects the current concrete configuration.

- **Course**: IT 140 - *Introduction to Scripting*
- **Activity Name**: Main Course Repository | Controlled Manifest and Schema Guide
- **Activity Purpose**: Explain the controlled manifest and schema, their purpose, and how maintainers should review, validate, change, and release them.
- **Artifact Version**: 1.0.2
- **Artifact Date-Time Group**: 2026-08-30-12-56
- **Development Status**: Pilot — Active Development

> [!WARNING]
> This repository is a work in progress. Some modules and activities may not be fully implemented yet. Please check the status of each activity in the table below for the latest updates.

## Table of Contents

- [Controlled Manifest and Schema Guide](#controlled-manifest-and-schema-guide)
  - [Table of Contents](#table-of-contents)
  - [Document Metadata](#document-metadata)
  - [1. Purpose and Audience](#1-purpose-and-audience)
  - [2. Student View: Why Use a Manifest?](#2-student-view-why-use-a-manifest)
  - [3. Files and Authority](#3-files-and-authority)
  - [4. Configuration Model](#4-configuration-model)
  - [5. Current Controlled Baseline](#5-current-controlled-baseline)
    - [Current Course IDE Selection](#current-course-ide-selection)
    - [Current Platform Implementations](#current-platform-implementations)
    - [Current Deployment Profiles](#current-deployment-profiles)
  - [6. Validation and Runtime Use](#6-validation-and-runtime-use)
    - [Validation Layers](#validation-layers)
    - [Lifecycle Use](#lifecycle-use)
  - [7. Safety and Ownership Boundaries](#7-safety-and-ownership-boundaries)
  - [8. Change Control and Versioning](#8-change-control-and-versioning)
  - [9. Maintainer Review Workflow](#9-maintainer-review-workflow)
  - [10. Current Artifact Alignment Snapshot](#10-current-artifact-alignment-snapshot)
  - [11. Maintaining This Guide](#11-maintaining-this-guide)

## Document Metadata

- **Course**: IT 140 - *Introduction to Scripting*
- **Program name**: IT 140 Course Automation Scripts
- **Artifact ID**: `IT140-MANIFEST-README`
- **Artifact version**: `0.1.0`
- **Version date**: `2026-08-01`
- **Status**: Draft for faculty review
- **SRS baseline**: `IT140-SRS-SCRIPTS`, version `0.2.0`, version date `2026-07-31`
- **SDD baseline**: `IT140-SDD-SCRIPTS`, version `0.2.0`, version date `2026-07-31`
- **Manifest baseline reviewed**: schema compatibility `2.0`; automation release `0.5.1`; release date `2026-07-30`; status `draft`
- **Manifest source revision**: `2ad2ff23346896c3e27d3a8b64a9d40d652196e4`
- **Schema standard**: JSON Schema Draft 2020-12

## 1. Purpose and Audience

The `.manifest/` directory contains operational configuration artifacts used by the IT 140 Course Automation Scripts. Unlike the development-only files in `scripts/.dev/`, the manifest and schema must remain available in student installations when required by the implementation.

This guide serves several audiences:

- **Students** can understand why the course uses a manifest and why they should not edit it casually.
- **Faculty and subject matter experts** can review the concrete course IDE selection and its relationship to the requirements and design.
- **Maintainers and platform developers** can locate the source of product, version, platform, provider, settings, path, and logging decisions.
- **Testers** can identify the exact configuration baseline that must accompany test definitions and results.
- **Technical support personnel and AI support tools** can interpret manifest-related validation or compatibility failures without treating the manifest as executable instructions.

The manifest centralizes configuration that would otherwise be duplicated across Windows, macOS, Linux, and hosted-platform scripts. Stable capabilities and safety rules remain in the SRS, SDD, and reviewed code; the manifest selects the concrete products and approved implementation data used for a particular automation release.

## 2. Student View: Why Use a Manifest?

A **manifest** is a structured list that tells software what approved items belong in an environment. The IT 140 manifest is written in **JavaScript Object Notation (JSON)**, a plain-text format that uses names, values, lists, and nested objects.

For the course automation package, the manifest helps all supported environments work toward the same required outcome. For example, it identifies the approved programming-language version, development tools, extensions, installation sources, settings, supported platform characteristics, and log location. Each platform may use different native installation commands, but the scripts can refer to the same capability definitions and target configuration.

Students normally do not need to open or edit these files. A local change can make the manifest invalid, cause verification to fail, or create an environment that no longer matches the approved course baseline. Personal preferences and coursework belong outside the manifest unless the course explicitly declares a setting or asset as course-managed.

## 3. Files and Authority

| File | Role | Authority and limits |
| --- | --- | --- |
| [`it140_manifest.json`](it140_manifest.json) | Controlled manifest | Selects the current approved products, versions or version rules, sources, provider profiles, platforms, deployment profiles, settings, managed assets, obsolete components, and logging policy for the automation release. It is data, not executable code. |
| [`it140_manifest.schema.json`](it140_manifest.schema.json) | Manifest schema | Defines the permitted JSON structure, required fields, data types, patterns, enumerations, ranges, and structural relationships. Passing schema validation does not replace semantic, path, integrity, compatibility, or qualification validation. |
| [`README.md`](README.md) | Informative guide | Explains the directory and directs readers to controlling artifacts. It does not approve a manifest release or add requirements. |

The artifact authority order depends on the question being asked:

| Question | Controlling artifact or process |
| --- | --- |
| What behavior, safety boundary, quality, or acceptance result is required? | [SRS](../.dev/analysis/it140_scripts_srs.md) |
| How must the package be organized to satisfy those requirements? | [SDD](../.dev/design/it140_scripts_sdd.md) |
| What JSON structure and value constraints are permitted? | [Manifest schema](it140_manifest.schema.json) |
| Which concrete products, sources, profiles, settings, and assets are selected now? | [Controlled manifest](it140_manifest.json) |
| Which native operation is performed for an approved adapter identifier? | Reviewed platform implementation and adapter code |
| Is an enabled deployment profile course-supported? | Approved qualification evidence, documentation, and release decision—not manifest enablement alone |

A manifest-only change is appropriate when a selected product, product version, approved source, or similarly bounded configuration value changes without altering a required capability, user workflow, trust boundary, design rule, or acceptance criterion. A change to any of those elements requires review of the SRS and SDD and may require corresponding flowchart, pseudoscript, implementation, schema, and test changes.

## 4. Configuration Model

The controlled manifest currently organizes configuration into the following top-level sections:

| Section | Purpose |
| --- | --- |
| `schema_version` | Identifies the manifest structure that the schema and scripts must understand. |
| `automation_release` and `automation_release_date` | Identify the coordinated automation-package release selected by the manifest. |
| `course` | Identifies IT 140 and the IT 140 Course IDE environment. |
| `control` | Records development or approval status, source repository, source revision, and change summary. |
| `policy` | Defines shared paths, free-space minimums, network timing, operating-system upgrade policy, student-cost policy, retry behavior, and permitted integrity methods. |
| `capabilities` | Defines stable course needs such as version control, a programming runtime, testing, an IDE, and IDE support features. |
| `products` | Describes concrete approved products that can satisfy capability roles. |
| `software_sources` | Allowlists approved repositories, marketplaces, or downloads and their integrity and retry rules. |
| `provider_profiles` | Defines reviewed external-service integration, authentication flow, minimum account fields, privacy-preserving identity rules, and redaction. |
| `platforms` | Binds capability roles to platform-specific packages, installation scopes, adapters, sources, version probes, and dependencies. |
| `deployment_profiles` | Describes concrete hosted, local, bare-metal, or test environments that reuse a platform implementation. Presence and enablement do not independently establish course support. |
| `managed_settings` | Declares the specific user settings the package may merge, replace, and verify. |
| `managed_assets` | Declares repository-managed files that approved lifecycle operations may replace through controlled methods. |
| `obsolete_components` | Declares components and paths that Update is explicitly authorized to remove. An empty object authorizes no obsolete-component removal. |
| `logging` | Defines log naming, encoding, location, retention, redaction, and support-bundle content boundaries. |

The design intentionally separates three concepts:

1. A **capability** describes what students need to do, such as write Python programs or run course-provided tests.
2. A **product** identifies the approved tool that satisfies one or more capabilities.
3. A **platform binding** identifies how that product is installed, configured, and verified on a particular platform implementation.

This separation lets maintainers replace an approved product or source without embedding the same product-specific decision in every script. The manifest may select only adapter identifiers already reviewed and distributed with the package; it cannot introduce new executable behavior by supplying command text.

## 5. Current Controlled Baseline

The current controlled manifest identifies automation release `0.5.1`, dated `2026-07-30`, with status `draft`. Its shared policy includes:

| Policy item | Current value |
| --- | --- |
| Course root | `${HOME}/it140` |
| Script root | `${COURSE_ROOT}/scripts` |
| Minimum free space | `5,368,709,120` bytes (5 GiB) |
| Network timeout | 60 seconds |
| Operating-system release upgrades | Not allowed |
| Student cost policy | No additional course fee |
| Default retry profile | At most 5 attempts; 5-second initial delay; multiplier 2; 60-second maximum delay |
| Log directory | `${COURSE_ROOT}/logs` |
| Log filename pattern | `{action}_{platform}_{timestamp}.log` |
| Log retention data | At most 50 files and 180 days |

### Current Course IDE Selection

The current manifest selects these concrete products for the required course capabilities:

| Capability group | Selected products |
| --- | --- |
| Version control and source hosting | Git and GitHub CLI |
| Programming runtime | Python 3.12, with a compatible version rule of `>=3.12,<3.13` |
| Course-provided testing | pytest and pytest-cov |
| Code editor and IDE | Visual Studio Code |
| Python language support | Python Extension for Visual Studio Code |
| Code quality | Ruff Extension for Visual Studio Code |
| Diagram support | Draw.io Integration for Visual Studio Code |
| Pseudocode support | Pseudocode Support for Visual Studio Code |
| Spelling support | Code Spell Checker |
| Course file viewing | Office Viewer for Visual Studio Code |

The manifest also declares approved software sources, including the course repository, operating-system or vendor package sources, Homebrew repositories, the Python Package Index, and the Visual Studio Marketplace. Scripts must use the declared source and reviewed adapter for the selected platform rather than substituting an unapproved download location.

### Current Platform Implementations

| Platform ID | Abbreviation | Current platform constraints | Native script and package model | Current role |
| --- | --- | --- | --- | --- |
| `cvd` | `cvd` | Ubuntu 24.04 LTS, Xfce, x86_64 | Bash-compatible `.sh` scripts and APT | Reference platform implementation |
| `windows` | `win` | Manifest-listed Windows 10 or Windows 11 releases, x86_64 | PowerShell `.ps1` scripts and WinGet, with approved prerequisite handling | Local Windows implementation |
| `macos` | `mac` | Manifest-listed macOS releases on Apple silicon, arm64 | Z shell-compatible `.sh` scripts and Homebrew | Local macOS implementation; Intel remains outside the enabled baseline |
| `ubuntu_gnome` | `ubg` | Ubuntu 24.04 LTS, GNOME, x86_64 | Bash-compatible `.sh` scripts and APT | Local Ubuntu GNOME implementation |

A platform entry defines reusable native behavior. More than one deployment profile may reuse a platform implementation when its lifecycle behavior and adapter contracts are equivalent.

### Current Deployment Profiles

| Deployment profile ID | Environment | Manifest role |
| --- | --- | --- |
| `codio_cvd` | Codio Virtual Desktop, Ubuntu 24.04 LTS, Xfce, x86_64 | Enabled reference deployment for course documentation, support reproduction, development, and release acceptance testing |
| `windows_bare_metal` | Supported Windows x86_64 computer | Enabled local bare-metal profile used for complete Windows conformance testing |
| `windows_sandbox` | Windows Sandbox, x86_64 | Enabled ephemeral qualification and support-reproduction profile; it does not replace bare-metal Windows qualification |
| `macos_bare_metal` | Supported macOS on Apple silicon | Enabled local bare-metal profile used for complete macOS conformance testing |
| `ubuntu_gnome_bare_metal` | Ubuntu 24.04 LTS with GNOME, x86_64 | Enabled local bare-metal profile used for complete Ubuntu conformance testing |

> [!CAUTION]
> `enabled: true` permits controlled resolution, testing, or operation. It does **not** by itself mean that a deployment profile is approved for student course support. Course support also requires complete implementation, qualification testing, documentation, approval, and current release evidence.

## 6. Validation and Runtime Use

### Validation Layers

A manifest is not safe to use merely because it looks readable or parses as JSON. Before a managed lifecycle action relies on it, the package design requires layered validation:

1. **File validation** confirms that the expected file exists, is readable, uses the expected encoding, and stays within an approved size limit.
2. **Syntax validation** confirms valid JSON and rejects duplicate-key ambiguity.
3. **Schema validation** confirms required fields, data types, patterns, enumerations, and bounded values.
4. **Artifact-identity validation** confirms supported versions, valid dates, and compatible identities.
5. **Semantic validation** confirms unique identifiers and meaningful required capability bindings.
6. **Relationship validation** confirms that referenced products, sources, adapters, profiles, settings, and assets exist and are compatible.
7. **Path validation** expands variables, canonicalizes paths, and confirms that managed paths remain inside approved boundaries.
8. **Integrity and trust validation** confirms that manifest and managed-asset data come through the approved trust chain.
9. **Compatibility validation** confirms that the running script supports the manifest structure, automation release, and selected adapter interfaces.

The JSON schema performs structural validation. Platform scripts and shared validation services remain responsible for the semantic, relationship, path, integrity, trust, and runtime-compatibility checks that JSON Schema alone cannot prove.

A syntax-only command such as `python -m json.tool` can detect malformed JSON, but it is not sufficient release evidence because it does not apply the manifest schema or the required semantic checks.

### Lifecycle Use

| Lifecycle component | Relationship to the manifest |
| --- | --- |
| Prepare | Must work before the local manifest exists. It does not depend on or load the manifest during first-use acquisition. It validates its embedded identity and the staged package structure before refreshing course-managed package files. |
| Install | Loads and validates the manifest before selecting system software, sources, packages, versions, privilege operations, and platform adapters. |
| Configure | Loads and validates the manifest before applying current-user provider integration, managed settings, paths, and approved desktop or IDE integration. |
| Verify | Loads and validates the manifest as the expected-state baseline, then performs read-only checks. A manifest failure is reported; Verify does not repair or rewrite the file. |
| Update | Loads and validates the manifest before maintaining approved software, settings, and managed assets. It may remove only obsolete components explicitly declared by the manifest. |

No mutating managed action should begin until the validation layers required by that action pass. A failed manifest validation must produce a deterministic result, specific remediation, and an exact log path. When a managed lifecycle run on a local or unconfirmed profile ends nonzero or noncompliant, the package also provides course-continuity guidance that students may continue their coursework in the Codio Virtual Desktop while the local issue is resolved.

## 7. Safety and Ownership Boundaries

The manifest and schema help enforce the following boundaries:

- The manifest contains declarative data; it does not contain arbitrary executable commands.
- Adapter identifiers must resolve only to reviewed behavior distributed with the approved package.
- The manifest must not contain passwords, authentication tokens, private keys, personal email addresses, browser data, or other secrets.
- Provider authentication secrets remain in the approved provider or operating-system credential store, not in the manifest or logs.
- Path templates may use only approved variables such as `${HOME}`, `${DESKTOP}`, `${COURSE_ROOT}`, `${SCRIPT_ROOT}`, `${LOG_DIR}`, and `${TEMP}`.
- Expanded paths must be canonicalized and checked before use; `..` traversal and secret-like path variables are prohibited by the schema.
- Files outside explicitly declared managed paths are user-owned.
- Missing optional fields must not be interpreted as permission to act. Required and optional behavior must be explicit.
- An empty `obsolete_components` object authorizes no removal.
- Managed settings use bounded merge policies so unrelated user settings are preserved.
- Managed assets use declared source, destination, integrity, replacement, scope, and lifecycle ownership data.
- Support bundles require explicit confirmation and exclude student source files, repository contents, version-control history, authentication data, and browser data.

The manifest must never be used to justify overwriting assignment repositories, student source files, unrelated preferences, nested repositories, credentials, or files that are merely located under a similarly named directory.

## 8. Change Control and Versioning

Every proposed manifest or schema change requires review, testing, approval appropriate to its status, and traceable release evidence.

| Change type | Minimum review expectation |
| --- | --- |
| Product version, package identifier, or approved source changes within an unchanged capability and trust model | Manifest and schema compatibility review; affected adapter and platform tests; verification and update tests; release-record update |
| New product satisfying an existing capability | Product, source, licensing or cost, integrity, adapter, platform-binding, settings, update, and verification review |
| New operating-system release or architecture | Platform constraint review, upstream support review, clean-environment qualification, idempotence, interruption, and negative-path testing |
| New deployment profile reusing an existing platform implementation | Profile resolution, documentation, complete qualification evidence, support designation, and release approval |
| New platform implementation | SRS and SDD review; schema and manifest changes; all five lifecycle entry points; adapters; flowcharts; pseudoscripts; full conformance evidence |
| Capability, user workflow, trust boundary, responsibility boundary, or acceptance-criterion change | SRS and SDD change control before or with downstream artifact updates |
| Schema structure change | Compatibility analysis, schema identity change, manifest migration, loader compatibility, negative tests, and release coordination |
| Managed path, setting, asset, or obsolete-component authority change | Ownership, least-privilege, preservation, rollback, path-boundary, and destructive-operation review |

Version identities serve different purposes and should not be forced to match:

- The **README artifact version** identifies this guide.
- The **SRS version** identifies the requirements baseline.
- The **SDD version** identifies the design baseline.
- The **schema version or compatibility identity** identifies the manifest structure understood by validators and scripts.
- The **manifest artifact identity** should identify the controlled configuration item independently.
- The **automation release** identifies the coordinated package release selected by the manifest.
- Each script, test definition, and test-result artifact retains its own identity and version date.

A changed artifact receives the Semantic Versioning increment required by its own compatibility effect and a new version date. Related artifacts do not receive artificial version changes merely to make their version numbers match. Test and release records must identify the exact versions, dates, source revisions, and results used for the decision.

## 9. Maintainer Review Workflow

Use the following sequence for a proposed manifest or schema change:

1. **Classify the change.** Determine whether it is configuration-only or changes a capability, workflow, trust boundary, responsibility boundary, design rule, or acceptance criterion.
2. **Review controlling artifacts.** Confirm the proposal against the current SRS, SDD, applicable flowcharts, pseudoscripts, and platform implementation contracts.
3. **Update the schema first when structure changes.** Add or revise required fields, types, patterns, enumerations, ranges, and compatibility rules before relying on new manifest data.
4. **Update the manifest declaratively.** Use stable identifiers, approved variables, explicit required status, allowlisted sources, reviewed adapter IDs, bounded values, and no embedded command text or secrets.
5. **Perform syntax and schema validation.** Reject malformed JSON, duplicate keys, unknown properties, missing fields, invalid types, invalid patterns, and out-of-range values.
6. **Perform semantic and relationship validation.** Confirm referenced objects exist, required capabilities have valid platform bindings, exactly one enabled reference deployment is selected, and profile facts agree with platform facts.
7. **Perform path and security review.** Expand and canonicalize every managed path; confirm ownership scope, merge or replacement policy, redaction, integrity, and obsolete-component authority.
8. **Run affected tests.** Include normal, repeated, missing, corrupt, incompatible, interrupted, unsupported-platform, privacy, student-work-preservation, and rollback or recovery cases as applicable.
9. **Qualify affected profiles.** An enabled profile is not course-supported until the complete required implementation, test, documentation, and approval evidence is recorded.
10. **Update identities and release evidence.** Assign independent versions and dates to every changed artifact and record the exact source revision, test definition, test result, and approval decision.
11. **Update this guide when needed.** Revise the baseline, structure, examples, workflow, or alignment snapshot without copying detailed normative rules unnecessarily.

A proposed manifest change should not be merged merely because the JSON parses or the schema accepts it. Release approval requires the applicable semantic, security, adapter, platform, lifecycle, and qualification evidence.

## 10. Current Artifact Alignment Snapshot

This section records the repository state reviewed for README version `0.1.0`; it is not a release approval.

| Area | Current observation | Required follow-through |
| --- | --- | --- |
| Manifest control state | Automation release `0.5.1` is marked `draft`, with release date `2026-07-30` and source revision `2ad2ff23346896c3e27d3a8b64a9d40d652196e4`. | Preserve draft handling until the required review, test, approval, and release records exist. |
| Schema standard | The schema uses JSON Schema Draft 2020-12, prohibits unknown root properties, and documents required semantic checks that scripts must perform beyond schema validation. | Maintain executable semantic-validation and negative-test evidence; do not describe schema validation alone as complete validation. |
| Artifact identities | The current manifest identifies `schema_version`, `automation_release`, and `automation_release_date`, but does not contain the independent manifest and schema artifact identity objects described by the current SDD data design. The schema compatibility value is `2.0`, while the current SRS and SDD call for strict SemVer artifact identity. | Reconcile the manifest and schema identity model with the current SRS and SDD, define compatibility and migration behavior, then update loaders, tests, logs, and release evidence. |
| Platform script metadata | Current platform entries declare script extensions, interpreter adapters, line endings, and the legacy filename template `{action}_{platform}{extension}`. They do not declare an explicit platform script directory. | Align schema and manifest script metadata with the approved `prepare_ide`, `install_ide`, `configure_ide`, `verify_ide`, and `update_ide` entry points and the current platform directory layout. |
| Desktop integration | The current SRS and SDD require manifest-controlled course-root and IDE course-root integrations. The current manifest has supporting platform packages and settings but no dedicated top-level `desktop_integrations` definitions. | Add schema-valid, platform-portable desktop integration definitions and corresponding adapters, verification checks, and conformance evidence. |
| Deployment-profile support | The manifest contains five enabled deployment profiles, including Windows Sandbox. Current SRS and SDD rules state that enablement permits controlled use or qualification but does not itself establish course support. | Keep support designations in approved qualification and release records. Continue to identify Windows Sandbox as qualification-only. |
| Windows release data | The Windows platform includes Windows 10 version 22H2 with `security_updates_required: true` and a recorded support end date of `2025-10-14`. | Review the entry against the current security-update and course-support policy, then revise, restrict, qualify, or retire the profile data as appropriate. |
| Managed settings | The current shared Git and Visual Studio Code setting profiles list Windows, macOS, and Ubuntu GNOME platform IDs but not the CVD platform ID. | Confirm whether CVD intentionally uses separate provider-managed configuration or whether the manifest setting scope should include the reference platform. |
| Managed assets and obsolescence | The manifest and schema are declared as atomically replaceable managed assets for Update. `obsolete_components` is currently empty. | Preserve atomic replacement and trust-chain validation. Do not remove any component unless an explicit reviewed obsolete-component entry authorizes it. |
| Logging and support data | The manifest defines the course log directory, naming pattern, retention data, prohibited fields, explicit support-bundle confirmation, and permitted and prohibited bundle content. | Confirm every platform implementation applies equivalent redaction, retention, summary, and support-bundle behavior and records exact artifact identities. |
| Course continuity | Current SRS and SDD require profile-aware CVD continuity guidance after an unsuccessful managed lifecycle conclusion. The current manifest does not define this stable message or behavior. | Keep the behavior in the requirements, design, message catalog, and reviewed code unless a future design explicitly assigns bounded message selection to controlled configuration. |

## 11. Maintaining This Guide

Update this README when its purpose, artifact map, current baseline, configuration model, maintainer workflow, or alignment snapshot changes. Increment its independent SemVer according to the compatibility effect of the README change and assign a new version date. Do not change its version solely because another artifact changed.

Keep links relative. Keep student explanations brief and accessible. Direct maintainers to the controlling artifact instead of copying complete schema definitions, platform bindings, package inventories, validation algorithms, acceptance tests, or troubleshooting procedures into this guide.

When the manifest or schema changes, verify that this guide does not accidentally describe a draft configuration as approved, equate `enabled` with course-supported, treat structural validation as complete validation, or imply that manifest data may introduce unreviewed executable behavior.
