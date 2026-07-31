# Software Design Description

- **Course**: IT 140 - *Introduction to Scripting*
- **Activity**: Course Automation Script Development
- **Program Name**: IT 140 Course Automation Scripts
- **Document ID**: IT140-SDD-SCRIPTS
- **Status**: Draft for faculty review
- **Version**: 2026.07.25.2
- **SRS Baseline**: `IT140-SRS-SCRIPTS`, version `2026.07.25.2`
- **Repository Baseline**: `GC-STEM/it140` commit `dfcfe0bc1c0e8d0dc9ad47faf2b855a18bdf227e`

## 0. General Description

### 0.1 Purpose

This Software Design Description (SDD) explains how the **IT 140 Course Automation Scripts** package will be organized to satisfy the approved Software Requirements Specification (SRS). The SRS defines **what** the package must do. This SDD defines the planned software structure, data, interfaces, control flow, safety mechanisms, and platform-abstraction approach that developers will use to build it--in other words, **how** the package will fulfill the requirements.

The package contains five coordinated lifecycle components for each supported platform:

1. `prepare_ide.<ext>` acquires, installs, or refreshes the local course automation package required to execute the remaining lifecycle scripts.
2. `setup_ide.<ext>` establishes or repairs system-level software and settings.
3. `configure_ide.<ext>` establishes or repairs the current user's environment.
4. `verify_ide.<ext>` inspects the system and user layers without changing them.
5. `update_ide.<ext>` maintains approved software and course-managed assets over time.

The design follows a modified [Waterfall Model](https://www.geeksforgeeks.org/software-engineering/waterfall-model/) software development lifecycle (SDLC): requirements analysis, design, construction, and testing. **SDLC** means the organized process used to plan, build, verify, release, and maintain software.

### 0.2 Design Philosophy

The main body of this SDD is intentionally **evergreen**. It describes stable capabilities and design contracts instead of embedding current product names, package identifiers, extension identifiers, or versions. The controlled manifest selects the concrete approved products and versions used by each platform implementation.

Product names are retained only when one of the following conditions applies:

- A concrete external interface cannot be described honestly without identifying its provider.
- A repository filename, command, or file format is itself part of the approved design.
- A nonnormative appendix records the reference environment used for review and testing.

The manifest is not allowed to contain arbitrary executable commands. It may select approved adapters and provide validated data, but executable behavior remains in reviewed source code. An **adapter** is a component that translates a stable package operation into commands appropriate for one platform, package manager, application, or external service.

### 0.3 Relationship Among the SRS, SDD, Manifest, and Code

| Artifact | Primary question answered | Change authority |
| :------: | ------------------------- | ---------------- |
| [SRS](../analysis/it140_scripts_srs.md) | What behavior and quality are required? | Approved requirements change process |
| SDD | How will the package be structured to satisfy the SRS? | Approved design change process |
| [Manifest schema](../../.manifest/it140_manifest_schema.json) | What configuration structure and value types are valid? | Design and configuration-control process |
| [Controlled manifest](../../.manifest/it140_manifest.json) | Which products, versions, sources, platforms, and provider profiles are approved now? | Configuration review, testing, approval, and release process |
| Platform scripts and tests | How is the approved design implemented and verified on a platform? | Source-control review and testing process |

A manifest-only change is appropriate when the selected product or version changes but the required capability, user workflow, trust boundary, and acceptance criteria remain the same. An SRS and SDD review is required when a change alters any of those items.

### 0.4 Intended Audience

This SDD is written for:

- Computer science faculty and subject matter experts who approve and implement the package.
- Course developers and platform administrators who review platform-specific behavior.
- Test developers who derive automated and manual tests from the SRS and this design.
- Faculty and technical support personnel who need to understand script responsibilities and diagnostics.
- First-term students who want to understand how a professional software design connects requirements to code.

Technical terms and abbreviations are defined when first introduced. The document uses industry terminology while explaining why each major design choice exists.

### 0.5 Design Scope

This SDD covers:

- The package architecture and five-script lifecycle.
- The logical design of the controlled manifest and its schema.
- Shared services used by all five scripts.
- Script-specific component and control-flow designs.
- Command-line, file, operating-system, package-manager, and external-service interfaces.
- Error handling, recovery, privacy, security, logging, and support-bundle design.
- Platform adapters and the process for adding another supported platform.
- Traceability from SRS requirements to design elements and supporting artifacts.

This SDD does not define:

- Student assignment solutions or grading logic.
- The final syntax of every platform implementation.
- Product and version selections that belong in the controlled manifest.
- General-purpose backup, reset, uninstall, or account-recovery features.
- A replacement for the bootstrap command set used before the scripts are available.

### 0.6 Terms and Abbreviations

| Term | Definition and purpose in this SDD |
| --- | --- |
| Adapter | A component that translates a stable package operation into platform-, product-, or provider-specific actions. |
| Atomic replacement | A file update that makes the complete new file visible at once instead of exposing a partially written file. |
| Capability role | A generic function required by the course, such as source-code editing, version control, test running, or code-quality checking. The manifest binds each role to an approved product. |
| Check registry | The ordered collection of verification checks, including each check's requirement mapping, severity, and remediation owner. |
| Component | A cohesive part of the design with one primary responsibility and a defined interface. |
| Controlled configuration item | A file or data set whose changes require review, testing, approval, and release tracking. |
| Deployment profile | A concrete local, virtual, or hosted environment that uses one platform implementation and records provider, desktop, session, release, architecture, and reset characteristics. |
| Dependency | A component, tool, file, service, or condition required before another operation can succeed. |
| Idempotent | Safe to run repeatedly. Repeated execution reaches the required state without harmful duplication or damage. |
| Managed asset | A file, setting, package, launcher, extension, plug-in, or other item the package is authorized to manage. |
| Manifest | The controlled JavaScript Object Notation (JSON) file that selects approved products, versions, sources, settings, provider profiles, and managed paths. |
| Orchestrator | The script layer that controls processing order, calls shared services and adapters, and produces the final result. |
| Platform adapter | The code that performs operating-system-specific detection, installation, settings, privilege, restart, and path operations. |
| Provider profile | Validated manifest data describing an approved external service's authentication method, account fields, identity rules, and selected provider adapter. |
| Read-only | Designed not to install, update, remove, repair, or rewrite software, files, or settings. |
| Redaction | Removing or masking secrets and unnecessary personally identifiable information (PII) before displaying or saving data. |
| Rollback | Restoring a previous valid state after a new managed asset cannot be installed successfully. |
| Run context | The in-memory data describing one script run, including action, version, platform, user, time, paths, manifest release, and accumulated result. |
| Schema | A machine-readable definition of allowed manifest fields, data types, required values, and structural rules. |
| Staging | Downloading or generating a candidate asset in a temporary location before validating and activating it. |
| Trust root | The small, preapproved source of authority used to decide whether downloaded configuration or code is authentic. |
| Validation | Checking structure, type, value, relationships, paths, and integrity before data is used. |

### 0.7 Design Element Identifiers

Each important design element has a stable identifier. Design identifiers support traceability but do not create new stakeholder requirements.

- `ARC-DES-###`: package architecture
- `DAT-DES-###`: data and manifest design
- `INT-DES-###`: interface and input/output design
- `SHR-DES-###`: shared service design
- `SET-DES-###`: setup-script design
- `CFG-DES-###`: configure-script design
- `VER-DES-###`: verify-script design
- `UPD-DES-###`: update-script design
- `ERR-DES-###`: error-handling and recovery design
- `SEC-DES-###`: privacy and security design
- `PLT-DES-###`: platform and provider abstraction design

## 1. Design Goals and Constraints

The design uses the following goals as decision rules when alternatives are available.

| Design ID | Goal or constraint | Design effect | Related SRS requirements |
| --- | --- | --- | --- |
| ARC-DES-001 | Preserve the five-script lifecycle. | The package exposes exactly four student- or administrator-facing lifecycle entry points per supported platform. | PKG-FR-001, PKG-FR-002 |
| ARC-DES-002 | Separate system-level, user-specific, read-only, and maintenance responsibilities. | Each operation is placed in the script that owns the required privilege and state boundary. | SET-FR-011, VER-FR-001, REF-TC-006 |
| ARC-DES-003 | Keep the main design capability-based and product-neutral. | Product names and identifiers are resolved through manifest role bindings and approved adapters. | PKG-TC-008, PKG-NFR-018, PKG-NFR-021 |
| ARC-DES-004 | Use one controlled source of configuration truth. | Scripts load the same validated manifest and do not maintain independent authoritative product lists. | PKG-FR-004, PKG-NFR-012 |
| ARC-DES-005 | Preserve user-owned work and unrelated settings. | Managed paths, settings keys, and removal targets are allowlisted; all other content is treated as user-owned. | PKG-FR-010, PKG-FR-020 |
| ARC-DES-006 | Make repair a normal lifecycle behavior. | Idempotent setup and configure repair their owned layers; update repairs current managed assets; verify identifies the correct owner. | SET-FR-009, SET-FR-010, CFG-FR-015, UPD-FR-015, VER-FR-009 |
| ARC-DES-007 | Support beginners without weakening technical correctness. | Output uses consistent stages, labels, explanations, next steps, and copyable commands. | PKG-NFR-002, PKG-NFR-003, PKG-NFR-006 through PKG-NFR-011 |
| ARC-DES-008 | Avoid requiring a course-managed runtime before setup installs it. | Each platform entry point uses an approved platform-native scripting language and native facilities available at bootstrap time. | PKG-TC-001, REF-TC-002 |
| ARC-DES-009 | Make failure recoverable and diagnosable. | Mutating operations use validation, staging, locks, bounded retries, rollback where practical, logs, and deterministic exit codes. | PKG-QOS-003 through PKG-QOS-005, PKG-QOS-011 through PKG-QOS-022 |
| ARC-DES-010 | Maintain complete traceability. | Every SRS requirement maps to one or more design elements, implementation artifacts, and tests. | Appendix B of the SRS |

### 1.1 Design Quality Priorities

When priorities conflict, the implementation shall use the following order:

1. Protect student work, credentials, privacy, and system integrity.
2. Refuse unsupported or unsafe operations.
3. Preserve a recoverable state.
4. Meet required course capabilities consistently.
5. Produce useful diagnostic information.
6. Minimize student effort and cognitive load.
7. Optimize execution time and convenience.

This order means that a script may stop rather than continue when continuing could damage files, expose private information, or create an unsupported state.

### 1.2 Simplicity Boundary

The package should be understandable to students, but implementation simplicity must not remove required safety. The design therefore favors:

- Straight-line orchestration with small purpose-specific functions.
- Declarative configuration in validated JSON.
- Allowlisted adapters instead of arbitrary command templates.
- Explicit state checks instead of assumptions.
- Clear result objects instead of parsing human-readable text when a structured interface is available.
- Reusable platform-local modules when the native scripting language supports them.
- Deterministic logic for the same supported starting state and inputs, implementing `PKG-NFR-004`.
- Equivalent separately implemented helpers when code cannot be shared safely across platforms.

## 2. Solution Overview

### 2.1 Architectural Pattern

The package uses a **layered orchestrator-and-adapter architecture**.

- The **entry-point layer** identifies the lifecycle action and initializes the run.
- The **orchestration layer** controls the action's stages and decisions.
- The **shared-service layer** provides manifest handling, logging, validation, command execution, locking, redaction, result aggregation, and file safety.
- The **platform-adapter layer** performs operating-system-specific operations.
- The **capability-adapter layer** manages approved product roles such as the programming runtime, source-code editor or IDE, test tools, and external provider client.
- The **data layer** contains the manifest, schema, logs, temporary staging data, and managed assets.

```text
User or Administrator
        |
        v
Lifecycle Entry Point
(setup | configure | verify | update)
        |
        v
Action Orchestrator
        |
        +---------------- Shared Services ----------------+
        | Manifest | Log | Validation | Lock | Redaction |
        | Results  | Paths | Staging | Command Execution |
        +--------------------------------------------------+
        |
        +--------------------+-----------------------------+
        v                    v                             v
Platform Adapter     Capability Adapters           Provider Adapter
        |                    |                             |
        v                    v                             v
Operating System     Approved Local Products       Approved External Service
```

### 2.2 Package Lifecycle

The lifecycle is state-based but does not store one authoritative state flag. State is derived from observable checks so that the scripts can recover from manual changes or interrupted runs.

```text
Unmanaged Environment
        |
        | setup
        v
System Layer Ready
        |
        | configure
        v
System + User Layers Ready
        |
        | verify (read-only)
        v
Compliant Environment
        |
        | update
        v
Maintained Environment
        |
        | verify when indicated
        v
Compliant Environment
```

`verify` may run from any state. It does not advance or repair state; it reports the observed condition and the appropriate remediation owner.

### 2.3 Normal Processing Pattern

Each entry point follows the same high-level processing pattern where applicable:

1. Initialize a minimal run context and safe error handling.
2. Parse supported command-line options.
3. Create the standard log location and start the transcript.
4. Detect the platform, current user, privilege state, paths, and available native facilities.
5. Locate, load, and validate the manifest.
6. Select the platform, capability, and provider adapters named by approved manifest identifiers.
7. Acquire an operation lock when the action may change shared state.
8. Run action-specific prerequisite checks.
9. Build an operation or check plan.
10. Execute the plan with stage-level results.
11. Run post-operation validation when the action changes state.
12. Determine restart guidance, remediation, summary totals, and final exit code.
13. Remove temporary data, release locks, close the log, and exit.

### 2.4 Planned Design Artifacts

The following supporting artifacts shall describe the same design at different levels of detail:

| Artifact | Purpose |
| --- | --- |
| `it140_scripts_sdd.md` | Package architecture, interfaces, component design, and traceability |
| `it140_scripts_architecture.drawio` | Editable component, data-flow, and trust-boundary diagram |
| `it140_scripts_lifecycle.drawio` | Editable normal and remediation lifecycle diagram |
| `install_ide.pseudo` | Platform-agnostic setup control flow |
| `configure_ide.pseudo` | Platform-agnostic user-configuration control flow |
| `verify_ide.pseudo` | Platform-agnostic verification control flow |
| `update_ide.pseudo` | Platform-agnostic update control flow |
| `scripts/.manifest/it140_manifest.schema.json` | Machine-readable manifest structural contract |
| `scripts/.manifest/it140_manifest.json` | Controlled concrete product, version, source, platform, and deployment-profile selections |
| Automated test files | Unit, integration, safety, idempotence, and acceptance-test support |

The diagrams and pseudoscripts are detailed design artifacts. This SDD remains authoritative when a supporting artifact is incomplete or inconsistent.

## 3. Program Structure

### 3.1 Repository and Installed Layout

The repository layout separates development artifacts from released platform scripts. The installed layout keeps logs and managed automation files separate from student assignment repositories.

```text
it140/
├── .faculty/
├── docs/
├── logs/
├── scripts/
│   ├── .manifest/
│   │   ├── it140_manifest.json
│   │   └── it140_manifest.schema.json
│   ├── <platform>/
│   │   ├── setup_ide.<ext>
│   │   ├── configure_ide.<ext>
│   │   ├── verify_ide.<ext>
│   │   └── update_ide.<ext>
│   └── .dev/
│       ├── analysis/
│       ├── design/
│       ├── pseudoscripts/
│       └── tests/
└── README.md
```

The installed package may omit `.dev/` files unless they are intentionally distributed as course-managed documentation. Student-owned folders and repositories are never inferred from naming alone; only explicitly declared managed paths are writable by automation.

### 3.2 Entry Points and Shared Implementation

Each platform provides four executable entry points. Entry points should contain only:

- Platform-native startup and strict-mode configuration.
- Loading of approved platform-local modules or helper functions.
- Construction of the run context.
- Invocation of the corresponding orchestrator.
- Final cleanup and exit.

Shared implementation should be factored into small, purpose-specific platform-local modules where supported, implementing `PKG-NFR-013`. Important intent, safety boundaries, and non-obvious decisions shall be explained in comments rather than restating commands, implementing `PKG-NFR-014`. Automated tests shall cover manifest parsing, platform detection, managed paths, exit codes, redaction, and idempotence, implementing `PKG-NFR-016`. The project shall not require one universal executable runtime before setup has installed the course environment. Cross-platform consistency is achieved through this SDD, the pseudoscripts, manifest schema, conformance tests, shared message catalog, and traceability—not by introducing an additional bootstrap dependency.

All source scripts and text configuration shall use UTF-8 encoding with Line Feed (LF) line endings under the repository's approved text-file policy. This design rule implements `PKG-TC-003`.

### 3.3 Shared Components

| Design ID | Component | Responsibility | Primary inputs | Primary outputs | Related SRS requirements |
| --- | --- | --- | --- | --- | --- |
| SHR-DES-001 | Run-context builder | Capture action, script version, platform, user, times, paths, and manifest release for one run. | Entry-point metadata and detected environment | `RunContext` | PKG-FR-006, PKG-QOS-017 |
| SHR-DES-002 | Output service | Produce consistent stage headings, status labels, prompts, summaries, and plain-text fallbacks. | Message key, severity, values | Terminal and log messages | PKG-FR-008, PKG-NFR-001 through PKG-NFR-011 |
| SHR-DES-003 | Transcript service | Create a unique timestamped UTF-8 log in the approved course log directory and write terminal output without losing the original exit result. | Run context and output stream | Log file | PKG-FR-007, PKG-TC-005, PKG-QOS-013, PKG-QOS-016 through PKG-QOS-020 |
| SHR-DES-004 | Manifest loader | Locate and read the controlled manifest as data. | Manifest path | Raw manifest object | PKG-FR-004, PKG-FR-011 |
| SHR-DES-005 | Manifest validator | Perform schema, semantic, relationship, compatibility, path, and integrity checks before use. | Raw manifest and schema | Validated immutable configuration or failure | PKG-FR-005, PKG-FR-019, PKG-TC-004 |
| SHR-DES-006 | Platform detector | Identify platform type, operating-system release, architecture, session type, current user, home path, and privilege facilities. | Native environment | `PlatformFacts` | PKG-FR-003, SET-FR-001, VER-FR-004, UPD-FR-001 |
| SHR-DES-007 | Adapter registry | Resolve allowlisted platform, capability, package-manager, and provider adapters from manifest identifiers. | Validated adapter IDs | Adapter objects or unsupported result | PKG-TC-008, REF-TC-001 through REF-TC-007 |
| SHR-DES-008 | Command runner | Execute reviewed commands with argument separation, captured status, bounded output handling, and optional privilege elevation for one command. | Executable, argument list, privilege policy | `OperationResult` | PKG-NFR-022 through PKG-NFR-024, PKG-QOS-012 |
| SHR-DES-009 | Path safety service | Expand approved variables, canonicalize paths, enforce managed boundaries, and reject traversal or protected targets. | Path template and run context | Validated canonical path | PKG-FR-020, PKG-NFR-019, PKG-NFR-020, PKG-NFR-023 |
| SHR-DES-010 | Lock manager | Prevent overlapping operations that could modify the same package-manager or managed-file state. | Action and lock scope | Acquired lock or conflict result | UPD-FR-002, PKG-QOS-005 |
| SHR-DES-011 | Staging and replacement service | Create private temporary locations, validate candidate assets, preserve prior valid copies, and activate with atomic replacement. | Asset metadata and downloaded file | Activated asset or rollback result | UPD-FR-004, UPD-FR-005, PKG-QOS-003, PKG-QOS-004 |
| SHR-DES-012 | Result aggregator | Collect stage results, warnings, failures, restart needs, remediation, counts, and deterministic final exit code. | `OperationResult` and `CheckResult` objects | `RunSummary` | PKG-FR-008, PKG-FR-009, VER-FR-011, VER-FR-012, PKG-QOS-014, PKG-QOS-015 |
| SHR-DES-013 | Redaction service | Remove secrets and unnecessary PII from messages, logs, and support files using field-aware and pattern-based rules. | Candidate diagnostic text and structured fields | Sanitized output | VER-FR-007, VER-FR-013, PKG-NFR-025 |
| SHR-DES-014 | Retry service | Apply bounded retries with delay and clear progress for approved temporary external failures. | Retry policy and operation callback | Final operation result and attempt history | UPD-FR-012, PKG-QOS-008 |
| SHR-DES-015 | Settings merger | Read, validate, merge, and safely write only approved settings while preserving unrelated valid content. | Existing settings and managed settings | Updated settings or unchanged result | CFG-FR-009, CFG-FR-011, CFG-FR-015 |
| SHR-DES-016 | Restart detector | Identify application, sign-out, session, virtual-machine, or computer restart needs without performing an unsafe restart. | Platform facts and update results | Restart guidance | UPD-FR-014, REF-TC-004 |

### 3.4 Responsibility Boundary Rules

- Setup may create its own log under the invoking user's course log folder, but it shall not perform personal account authentication or user-preference configuration.
- Configure shall not install or change system-wide components. If system prerequisites are missing, it directs the user to setup.
- Verify shall not call a mutating adapter method. The verify orchestrator receives read-only adapter interfaces.
- Update may change system and user-managed state, but only through manifest-declared capability roles, managed settings, and managed paths.
- Shared services may be reused by all scripts, but they shall not silently broaden the authority of the calling script.

## 4. Data Design

### 4.1 Manifest Design Principles

The manifest is a controlled configuration item, not a program. It contains declarative data that selects reviewed behavior. The schema and code jointly prevent it from becoming an unreviewed command-execution channel.

| Design ID | Manifest design rule | Purpose | Related SRS requirements |
| --- | --- | --- | --- |
| DAT-DES-001 | The root object contains release control, policy, capabilities, products, sources, provider profiles, platforms, optional deployment profiles, managed settings, managed assets, obsolete components, and logging data. | Provides a predictable top-level contract while separating stable platform bindings from concrete deployment environments. | PKG-FR-012 through PKG-FR-017 |
| DAT-DES-002 | `schema_version` uses a documented compatibility policy separate from the automation release. | Allows scripts to reject a manifest structure they cannot interpret. | PKG-FR-012, PKG-FR-019 |
| DAT-DES-003 | Capability definitions use stable role identifiers rather than product names in script logic. | Allows an approved product to change without changing lifecycle logic. | PKG-TC-008, PKG-NFR-012 |
| DAT-DES-004 | Platform entries bind capability roles to concrete package identifiers, commands, version probes, sources, settings, and adapter IDs. | Keeps product-specific data in one controlled location and enforces the no-additional-fee selection constraint. | PKG-FR-013, PKG-FR-014, PKG-FR-015, PKG-FR-016, PKG-TC-002 |
| DAT-DES-005 | Provider profiles identify an allowlisted provider adapter and validated authentication, account-field, and privacy-identity parameters. | Supports provider-specific behavior without hardcoding it throughout configure and verify. | CFG-FR-005 through CFG-FR-008, VER-FR-006 |
| DAT-DES-006 | Manifest values may select only adapter identifiers compiled into or distributed with the approved package release. | Prevents arbitrary manifest data from becoming executable code. | PKG-NFR-023, PKG-NFR-024 |
| DAT-DES-007 | Managed assets include ownership scope, source, destination, integrity data, replacement mode, and optional obsolete-state metadata. | Defines exactly what update may replace or remove. | UPD-FR-003 through UPD-FR-005, UPD-FR-010, PKG-FR-017, PKG-FR-020 |
| DAT-DES-008 | Managed settings identify the target file or interface, allowed keys, desired values, merge policy, and validation method. | Prevents whole-file replacement when only selected settings are owned. | CFG-FR-009, CFG-FR-011, CFG-FR-013, CFG-FR-015 |
| DAT-DES-009 | Paths are expressed with approved variables such as `${HOME}`, `${DESKTOP}`, `${COURSE_ROOT}`, and `${TEMP}` rather than fixed usernames. | Supports different users and platforms. | CFG-FR-012, PKG-NFR-019, PKG-TC-009, REF-TC-005 |
| DAT-DES-010 | Version rules use an explicit comparison scheme per capability, such as exact, minimum, compatible range, or presence-only. | Makes install, update, and verify decisions consistent. | SET-FR-008, VER-FR-005, PKG-TC-007 |
| DAT-DES-011 | Required and optional items are represented explicitly and are never inferred from missing fields. | Keeps optional features from causing required failures. | VER-FR-010, PKG-NFR-005 |
| DAT-DES-012 | Retry limits, timeouts, and performance settings are bounded by schema validation and safe code-defined maximums. | Allows controlled tuning without indefinite waits or excessive load. | UPD-FR-012, PKG-QOS-007 through PKG-QOS-010 |
| DAT-DES-013 | Secrets, personal values, and runtime authentication data are prohibited in the manifest schema and semantic validator. | Keeps the public controlled file safe to distribute. | PKG-FR-018, PKG-NFR-025 |
| DAT-DES-014 | A manifest release is approved only with its schema validation, platform conformance tests, integrity metadata, and release record. | Treats product selection as controlled engineering data. | PKG-FR-019, PKG-NFR-015, Appendix B of the SRS |
| DAT-DES-015 | Optional deployment profiles reference a platform implementation and record deployment kind, provider, desktop, session, release, architecture, reset method, and reference status. | Distinguishes the Codio CVD from local Ubuntu GNOME without duplicating course IDE product bindings or treating a desktop profile as an operating-system package list. | REF-TC-001 through REF-TC-006, Section 3.3 of the SRS |

### 4.2 Illustrative Logical Manifest Structure

The following example is informative. Field names may be refined when the JSON schema is constructed, but the separation of responsibilities shall remain.

```json
{
  "schema_version": "1.0",
  "automation_release": "YYYY.MM.DD.N",
  "policy": {
    "course_root": "${HOME}/it140",
    "log_directory": "${COURSE_ROOT}/logs",
    "minimum_free_space_bytes": 0,
    "retry_policy_id": "bounded-default"
  },
  "capabilities": {
    "version_control_client": {"required": true},
    "source_host_client": {"required": true},
    "programming_runtime": {"required": true},
    "test_runner": {"required": true},
    "coverage_reporter": {"required": true},
    "quality_tool": {"required": true},
    "source_code_ide": {"required": true}
  },
  "provider_profiles": {
    "source_host": {
      "adapter_id": "approved-provider-adapter",
      "authentication_method": "browser_device_flow",
      "account_fields": ["user_name", "account_id"],
      "private_commit_identity_rule": "approved-template-id"
    }
  },
  "platforms": {
    "reference-platform": {
      "abbreviation": "ref",
      "native_script_adapter_id": "approved-platform-adapter",
      "package_manager_adapter_id": "approved-package-adapter",
      "role_bindings": {
        "programming_runtime": {"product_id": "manifest-selected-product"},
        "source_code_ide": {"product_id": "manifest-selected-product"}
      }
    }
  },
  "deployment_profiles": {
    "reference_deployment": {
      "platform_id": "reference-platform",
      "deployment_kind": "hosted_virtual_desktop",
      "desktop_environment": "manifest-selected-desktop",
      "reference_profile": true
    }
  },
  "managed_assets": [],
  "logging": {
    "format_version": "1",
    "retention_policy_id": "course-default"
  }
}
```

### 4.3 Validation Layers

Manifest validation occurs in this order:

1. **File validation**: path exists, file is readable, expected encoding is used, and size is within a safe limit.
2. **Syntax validation**: content parses as JSON without duplicate-key ambiguity.
3. **Schema validation**: required fields, types, enumerations, patterns, and ranges are correct.
4. **Semantic validation**: identifiers are unique; required capability roles have bindings; versions and sources are meaningful.
5. **Relationship validation**: referenced adapters, provider profiles, platforms, assets, and policies exist and are compatible.
6. **Path validation**: expanded managed paths remain within approved boundaries and do not target protected or user-owned locations.
7. **Integrity and trust validation**: the manifest release and managed-asset metadata are obtained through the approved trust chain.
8. **Compatibility validation**: the running script supports the manifest schema and selected adapter interface versions.

No mutating action begins until all validation layers required by that action pass.

### 4.4 Runtime Data Structures

The names below describe logical structures. Native implementations may use records, dictionaries, associative arrays, objects, or equivalent structures.

| Data structure | Required fields | Purpose |
| --- | --- | --- |
| `RunContext` | action, script version, platform ID, user ID, paths, start time, manifest release, interactivity | Provides common context to every component. |
| `PlatformFacts` | OS type and release, architecture, session type, home path, desktop path, temporary path, privilege capability | Supports platform matching and prerequisite checks. |
| `DeploymentProfile` | Platform identifier, deployment kind, provider, desktop environment, session type, release, architecture, reset method, and reference flag | Selects environment-specific behavior and testing evidence without duplicating product bindings. |
| `CapabilityBinding` | role ID, product ID, adapter ID, required status, package identifiers, version rule, probes | Connects a generic capability to the current approved implementation. |
| `ProviderProfile` | adapter ID, authentication method, account fields, identity rule, validation rules | Controls approved external-service integration. |
| `ManagedAsset` | asset ID, source, destination, scope, integrity, replacement policy, obsolete policy | Authorizes managed-file synchronization. |
| `OperationResult` | operation ID, status, changed flag, message key, diagnostic details, remediation, restart flag | Represents one mutating or query operation. |
| `CheckResult` | check ID, SRS ID, status, observed value, expected rule, remediation owner, sanitized detail | Represents one verification result. |
| `RunSummary` | counts, changed items, warnings, failures, restart guidance, next step, final exit code | Produces consistent terminal and log summaries. |

### 4.5 Status and Result Values

Shared result values are represented internally by stable identifiers and rendered as student-facing text at the interface boundary.

| Internal result | Student-facing meaning |
| --- | --- |
| `pass` | The required condition is present and usable. |
| `success` | The requested operation completed. |
| `warning` | The environment remains usable, but attention may be needed. |
| `fail` | A required condition or operation did not succeed. |
| `not_applicable` | The check does not apply to the detected platform or approved configuration. |
| `skipped_dependency` | The operation was not attempted because a required prerequisite failed. |
| `canceled` | The user intentionally stopped a required interactive operation. |
| `changed` | The operation modified an approved managed item. |
| `unchanged` | The item was already compliant and no modification was needed. |

### 4.6 Log Design

Logs are human-readable UTF-8 plain text. Each meaningful line begins with a timestamp and stable level label when practical.

```text
2026-07-25T12:00:00-07:00 [INFO] [manifest.validate] Manifest schema and release validated.
2026-07-25T12:00:01-07:00 [PASS] [platform.release] Detected platform release is supported.
2026-07-25T12:00:02-07:00 [FAIL] [capability.quality_tool] Required capability is not available.
```

The transcript service records:

- Script and manifest release identifiers.
- Detected platform and architecture.
- A nonsecret current-user identifier.
- Start, end, and elapsed times.
- Major stages and operation identifiers.
- Sanitized observed and expected values.
- Changes, warnings, failures, remediation, restart guidance, and exit code.

Logs do not record passwords, tokens, private keys, browser data, complete personal email addresses, or student source files.

### 4.7 Support-Bundle Design

When explicitly requested, verify creates a temporary bundle containing only approved diagnostics, such as:

- Sanitized verification log.
- Manifest release and schema version, not secrets.
- Script version inventory.
- Supported platform facts.
- Required capability version results.
- Managed-path permission results.
- Sanitized selected configuration values.
- A bundle inventory describing every included file.

The bundle excludes assignment repositories, source files, version-control history, authentication stores, browser profiles, and unrelated settings. The user sees the proposed inventory before final creation.

## 5. Interface and Input/Output Design

### 5.1 Command-Line Interface

| Design ID | Interface rule | Planned behavior | Related SRS requirements |
| --- | --- | --- | --- |
| INT-DES-001 | Normal invocation requires no advanced arguments. | Running the platform script by name starts its normal student- or administrator-facing workflow. | PKG-NFR-002, PKG-NFR-010 |
| INT-DES-002 | Every script supports a help operation. | Help explains purpose, intended user, prerequisites, common invocation, log location, and exit-code meanings without changing state. | PKG-FR-006, PKG-NFR-003 |
| INT-DES-003 | Every script supports a version operation. | Version output identifies the script release and supported manifest schema range without loading external services. | PKG-NFR-015, PKG-QOS-017 |
| INT-DES-004 | Interactive prompts are used only when user choice or external authentication is required. | The script explains the action, available choices, default, cancellation method, and effect before reading input. | CFG-FR-006, PKG-NFR-007 |
| INT-DES-005 | Noninteractive execution fails safely when required interaction cannot be completed. | Automated or managed runs receive a clear result rather than waiting indefinitely for input. | PKG-QOS-003, PKG-QOS-011 |
| INT-DES-006 | Verify alone may expose a support-bundle option. | The option requests bundle preparation; final creation still displays the approved inventory and obtains explicit confirmation when interactive. | VER-FR-013, PKG-QOS-021 |
| INT-DES-007 | Unsupported options cause no managed change. | The script prints help-oriented guidance and returns the invalid-use exit code. | PKG-QOS-014 |
| INT-DES-008 | Prompts accept documented values case-insensitively where practical. | Blank input uses a clearly displayed safe default; invalid input is explained and reprompted within a bounded loop. | PKG-NFR-007, PKG-NFR-009 |
| INT-DES-009 | Student-facing output uses consistent status labels. | `INFO`, `SUCCESS`, `NOTICE`, `WARNING`, and `ERROR` appear as text and do not rely on color. | PKG-NFR-008, PKG-QOS-019 |
| INT-DES-010 | Progress reflects completed stages or underlying tool output. | Timed animations are not used as progress measurements. A truthful heartbeat appears during long silent operations. | PKG-NFR-009, PKG-QOS-008 |
| INT-DES-011 | Remediation commands are rendered from detected platform metadata. | Commands use the installed action name and tell the user where to run them. | VER-FR-009, PKG-NFR-010 |
| INT-DES-012 | The final summary is always attempted. | The summary shows result, changes, warnings, failures, restart guidance, next step, log path, and exit code, even after a handled failure. | PKG-FR-008, PKG-QOS-012, PKG-QOS-020 |

### 5.2 Common Opening Output

Each normal run displays the following fields near the beginning:

- Package and action name.
- Script version.
- Manifest release after validation.
- Detected platform and operating-system release.
- Current user identifier.
- Purpose and expected scope of changes.
- Log path.
- Important warnings, including whether privilege elevation or interaction may occur.

### 5.3 External Interface Contracts

| Interface | Stable package operation | Adapter responsibility | Failure behavior |
| --- | --- | --- | --- |
| Operating system | Detect release, architecture, users, paths, permissions, session, restart needs | Translate native information into `PlatformFacts` | Unsupported or unreadable facts stop unsafe actions. |
| System package manager | Refresh metadata, query, install, update, repair, remove approved obsolete packages, validate consistency | Use native package operations and approved sources | Return structured result; never parse only localized success text when an exit status or structured query exists. |
| Programming runtime | Locate executable, report version, manage required user tools when designed | Apply role binding and version rule | Missing system runtime is owned by setup; missing user tool is owned by configure or update. |
| Source-code editor or IDE | Locate CLI, report version, manage approved extensions or plug-ins, merge approved settings | Use manifest-selected capability adapter | Preserve optional extensions and unrelated settings. |
| Version-control client | Query version and apply approved user settings | Use managed keys only | Never alter repositories or history. |
| Source-code hosting provider | Check authentication, start approved flow, query account fields, derive privacy identity | Use allowlisted provider adapter and provider profile | Cancellation, provider unavailability, and invalid identity data produce distinct results. |
| Managed-asset source | Retrieve release metadata, manifest, schema, and assets | Use encrypted transport and integrity validation | Candidate data remains staged; installed valid data is preserved on failure. |
| Desktop or session environment | Create approved user launchers and file associations; detect restart needs | Apply only declared integrations | Missing optional integration is a warning unless manifest marks it required. |

### 5.4 Provider-Profile Interface

The provider adapter exposes stable operations:

```text
get_authentication_status()
start_approved_authentication_flow()
get_account_identity(approved_fields)
derive_private_commit_identity(profile_rule, account_identity)
validate_provider_configuration()
```

The manifest selects the provider adapter and supplies validated parameters. The provider profile does not contain raw shell commands, secrets, or personal identity values.

### 5.5 Exit-Code Resolution

The result aggregator uses a deterministic precedence when more than one condition applies. Precedence is based on safety and remediation value, not numeric order.

| Precedence | Exit code | Condition |
| :--: | :--: | --- |
| 1 | `5` | Manifest or managed asset is invalid, corrupt, or fails integrity validation. |
| 2 | `2` | Invocation, platform, or operating-system release is unsupported. |
| 3 | `3` | Required permission or privilege is unavailable. |
| 4 | `4` | Approved external source or service remains unavailable after retries. |
| 5 | `7` | The run changed or completed only part of the required state and needs remediation. |
| 6 | `1` | One or more required operations or checks failed for another reason. |
| 7 | `6` | The user canceled a required interactive operation before a more serious failure occurred. |
| 8 | `0` | All required operations or checks completed successfully. |

The exit code does not replace detailed stage results. A summary may report multiple failures while returning the highest-precedence applicable code.

## 6. Program Logic and Control Flow

### 6.1 Common Orchestration Flow

```text
BEGIN action
    initialize strict error handling
    parse supported options
    build minimal run context
    create log directory and transcript
    display opening information

    detect platform and user context
    IF action-platform mismatch OR unsupported platform
        record unsupported result
        summarize and exit
    ENDIF

    load manifest and schema
    validate syntax, structure, semantics, paths, trust, and compatibility
    IF validation fails
        record manifest or asset failure
        summarize and exit
    ENDIF

    resolve allowlisted adapters
    IF required adapter is unavailable
        record unsupported configuration
        summarize and exit
    ENDIF

    IF action changes shared state
        acquire required lock
        IF lock is unavailable
            record concurrent-operation failure
            summarize and exit
        ENDIF
    ENDIF

    run action-specific prerequisite checks
    build action plan
    execute or inspect each independent plan item
    aggregate results
    perform post-validation when state changed
    determine restart guidance and remediation
    remove temporary data and release locks
    display final summary
    close transcript
    return resolved exit code
END action
```

### 6.2 Dependency Handling

Each planned operation declares:

- A stable operation ID.
- Required dependencies.
- Whether it is read-only or mutating.
- Required privilege scope.
- Managed targets.
- Whether failure blocks later operations.
- Rollback or recovery behavior.
- Related SRS requirements.

When a prerequisite fails, dependent operations receive `skipped_dependency`; independent safe checks or cleanup may continue. This design avoids misleading secondary errors while preserving useful diagnostics.

### 6.3 Idempotence Strategy

Setup, configure, and update follow a **query-plan-apply-verify** pattern:

1. Query the current state using a structured or stable probe.
2. Compare the observed state with the manifest rule.
3. Plan only the changes required to reach compliance.
4. Apply the smallest approved change.
5. Query again to verify the final state.

A component is not reinstalled or rewritten merely because the script is rerun. Settings mergers compare managed keys, package adapters query installed state, and managed assets compare validated release or integrity data.

## 7. Prepare Script Design

## 8. Install Script Design

The install orchestrator owns the shared system layer. It may use controlled privilege elevation for specific commands but is not run wholesale with elevated authority unless a future platform design proves that unavoidable and receives approval.

| Design ID | Planned setup behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| SET-DES-001 | Gather and evaluate the approved OS release, architecture, disk space, network reachability, and privilege capability before planning installation. | Platform detector, manifest validator | SET-FR-001 |
| SET-DES-002 | Stop before system mutation when the platform or privilege model is unsupported; preserve the diagnostic log when possible. | Result aggregator, output service | SET-FR-002 |
| SET-DES-003 | Build a system capability plan from required manifest roles and system package bindings. | Adapter registry, package adapter | SET-FR-003 |
| SET-DES-004 | Accept install sources only from validated manifest bindings and native trusted repositories. | Manifest validator, trust service | SET-FR-004 |
| SET-DES-005 | Configure prerequisite repositories, trust keys, certificates, or registrations through reviewed adapter methods before dependent installation. | Platform and package adapters | SET-FR-005 |
| SET-DES-006 | Apply approved maintenance and security updates within the current OS release; release upgrades are excluded from the adapter interface. | Package adapter | SET-FR-006 |
| SET-DES-007 | Install or repair manifest-declared system integrations through system-scope adapter operations. | Platform adapter | SET-FR-007 |
| SET-DES-008 | Probe every required system capability and version after installation before declaring setup successful. | Capability adapters, result aggregator | SET-FR-008 |
| SET-DES-009 | Query before applying and compare after applying so reruns do not duplicate repositories, registrations, policies, or packages. | Package adapter, settings service | SET-FR-009 |
| SET-DES-010 | Treat a missing managed system component as a repair plan item while leaving unrelated system configuration untouched. | Managed-boundary service | SET-FR-010 |
| SET-DES-011 | Exclude provider authentication, personal identity, user-scoped tools, user settings, and user launchers from the setup plan. | Orchestrator boundary checks | SET-FR-011 |
| SET-DES-012 | On successful post-validation, render the matching configure command as the next step. | Output service, platform metadata | SET-FR-012 |

### 8.1 Install Control Flow

```text
validate system prerequisites
build system capability plan
FOR EACH plan stage in dependency order
    query current state
    IF compliant
        record unchanged success
    ELSE
        perform the smallest approved system change
        verify resulting state
        IF verification fails
            record required failure
            skip dependent operations
        ENDIF
    ENDIF
ENDFOR
run complete system-layer verification
recommend configure when successful
```

### 8.2 Install Privilege Design

The command runner receives a privilege policy per operation:

- `none`: command must run as the standard user.
- `elevate_one_command`: only the specific command is elevated.
- `administrator_context_required`: permitted only by an approved platform-specific design exception.

Arguments are passed as separate values rather than assembled into an unvalidated command string. Setup refuses to save user-specific files under an administrator's home directory accidentally.

## 9. Configure Script Design

The configure orchestrator owns the current user's course environment. It runs as the student or faculty account and does not make system-wide changes.

| Design ID | Planned configure behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| CFG-DES-001 | Confirm the script is running as the intended standard user and reject an unintended system-administrator context. | Platform detector | CFG-FR-001 |
| CFG-DES-002 | Probe required system capabilities before writing user configuration; missing system prerequisites map to setup remediation. | Capability adapters, result aggregator | CFG-FR-002 |
| CFG-DES-003 | Create missing approved course folders with safe permissions while preserving all existing contents. | Path safety and file services | CFG-FR-003 |
| CFG-DES-004 | Add the approved platform script directory to the user's executable search path through an idempotent managed entry. | Settings merger | CFG-FR-004 |
| CFG-DES-005 | Query provider authentication through the selected provider adapter and start the approved interactive flow only when required. | Provider adapter | CFG-FR-005 |
| CFG-DES-006 | Explain authentication steps, choices, browser or device interaction, expected delay, and cancellation before starting the provider flow. | Output service | CFG-FR-006 |
| CFG-DES-007 | Request only approved provider account fields and apply the provider profile's privacy-preserving commit-identity rule. | Provider adapter, redaction service | CFG-FR-007 |
| CFG-DES-008 | Present the provider user name as the default version-control display name while permitting a validated professional alternative. | Input validator, settings merger | CFG-FR-008 |
| CFG-DES-009 | Apply only manifest-declared version-control settings and use the manifest-selected source-code editor or IDE role where an editor setting is required. | Settings merger, role binding | CFG-FR-009 |
| CFG-DES-010 | Install or repair required user-scoped programming tools and IDE extensions or plug-ins through capability adapters. | Runtime and IDE adapters | CFG-FR-010 |
| CFG-DES-011 | Parse and validate existing IDE settings, merge only managed keys, preserve unrelated valid settings, and write atomically. | Settings merger, staging service | CFG-FR-011 |
| CFG-DES-012 | Resolve all user paths from the run context and approved variables; reject fixed-user paths in manifest data. | Path safety service | CFG-FR-012 |
| CFG-DES-013 | Create or repair only declared user integrations, such as launchers, file associations, or default course-folder behavior. | Platform adapter | CFG-FR-013 |
| CFG-DES-014 | Query provider status, version-control settings, runtime tools, IDE settings, extensions, folders, and integrations before success. | Capability adapters, check helpers | CFG-FR-014 |
| CFG-DES-015 | Use managed-key merging and query-plan-apply-verify behavior so reruns preserve optional extensions and unrelated preferences. | Settings merger, adapters | CFG-FR-015 |
| CFG-DES-016 | Render the matching verify command after successful configuration. | Output service, platform metadata | CFG-FR-016 |

### 9.1 Authentication Flow

```text
query provider authentication status
IF authentication is valid
    continue without opening a new flow
ELSE
    explain the approved flow and cancellation method
    request user confirmation
    IF canceled
        record cancellation and stop dependent identity steps
    ELSE
        start provider adapter authentication
        query status again
        IF status is not valid
            record required failure
        ENDIF
    ENDIF
ENDIF
```

Authentication secrets remain in the provider's approved credential store. Configure receives only the minimum status and account fields required by the provider profile.

### 9.2 Settings Merge Algorithm

1. Read the existing settings file or interface.
2. If the target does not exist, start with an empty valid structure.
3. If existing content is invalid, preserve a diagnostic copy and stop rather than silently discarding it.
4. Update only manifest-declared managed keys.
5. Preserve unrelated keys and optional extension selections.
6. Serialize deterministically to a staged file.
7. Validate the staged result.
8. Replace the target atomically.
9. Read the target again and verify managed keys.

## 10. Verify Script Design

Verify uses read-only adapter interfaces. A platform implementation shall make mutating methods unavailable to the verify orchestrator rather than relying only on developer discipline.

| Design ID | Planned verify behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| VER-DES-001 | Construct a read-only check plan and expose no install, repair, update, removal, or settings-write operations. | Read-only adapter interfaces | VER-FR-001, PKG-QOS-002 |
| VER-DES-002 | Run entirely as the standard user and report inaccessible privileged facts as designed warnings or failures without elevating. | Platform adapter | VER-FR-002 |
| VER-DES-003 | Validate the manifest and record the automation release used as the comparison baseline. | Manifest loader and validator | VER-FR-003 |
| VER-DES-004 | Check platform, release, architecture, user context, disk space, permissions, and approved network endpoints. | Platform detector, network probe | VER-FR-004 |
| VER-DES-005 | Iterate over required system capability bindings and compare presence and versions with manifest rules. | Capability adapters, check registry | VER-FR-005 |
| VER-DES-006 | Check required user-scoped tools, extensions, version-control settings, provider authentication, IDE settings, script permissions, folders, and integrations. | Read-only capability and provider adapters | VER-FR-006 |
| VER-DES-007 | Validate managed configuration structure and safe values while redacting secrets and complete personal identifiers. | Redaction service, settings readers | VER-FR-007 |
| VER-DES-008 | Represent each check as one `CheckResult` with `PASS`, `WARNING`, `FAIL`, or `NOT APPLICABLE`. | Check registry | VER-FR-008 |
| VER-DES-009 | Store the owning remediation action and related SRS ID in each check definition so failures produce the correct command. | Check registry, output service | VER-FR-009 |
| VER-DES-010 | Store required or optional classification in manifest data and check definitions; optional absence cannot create a required failure. | Manifest validator, result aggregator | VER-FR-010 |
| VER-DES-011 | Count results by status and display the totals with overall compliance. | Result aggregator | VER-FR-011 |
| VER-DES-012 | Resolve the final exit code from the most serious observed result using the shared precedence table. | Result aggregator | VER-FR-012 |
| VER-DES-013 | Save a sanitized transcript and, only on explicit request, prepare an inventory-reviewed support bundle. | Transcript service, bundle builder | VER-FR-013 |
| VER-DES-014 | Map unrepairable or administrative conditions to a manifest- or platform-declared support channel rather than an inappropriate lifecycle script. | Check registry, output service | VER-FR-014 |

### 10.1 Check Registry Structure

Each check definition contains:

```text
check_id
related_srs_id
capability_or_setting_role
required_or_optional
read_operation
expected_rule
result_formatter
redaction_rule
remediation_action
support_escalation_rule
```

The registry lets setup, configure, and update reuse selected post-operation probes without allowing verify to mutate state.

### 10.2 Verification Flow

```text
load ordered check registry
FOR EACH check
    IF check does not apply to the platform or manifest
        record NOT APPLICABLE
    ELSE
        execute read-only probe
        sanitize observed data
        compare observed state with expected rule
        record PASS, WARNING, or FAIL
        attach requirement and remediation
    ENDIF
ENDFOR
aggregate totals and compliance
optionally create approved support bundle
return resolved exit code
```

## 11. Update Script Design

Update owns maintenance of approved system software, user-scoped course tools, and course-managed assets. It does not perform an operating-system release upgrade and does not modify student-owned work.

| Design ID | Planned update behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| UPD-DES-001 | Evaluate platform, user, disk space, network reachability, and privilege capability before planning changes. | Platform detector | UPD-FR-001 |
| UPD-DES-002 | Acquire action- and resource-scoped locks before package or managed-file mutation. | Lock manager | UPD-FR-002 |
| UPD-DES-003 | Retrieve approved release metadata, schema, manifest, and managed-asset inventory from the authorized source through the trust chain. | Retry, trust, and manifest services | UPD-FR-003 |
| UPD-DES-004 | Download candidates into a private staging directory and validate syntax, schema, compatibility, paths, and integrity before activation. | Staging service, validators | UPD-FR-004 |
| UPD-DES-005 | Preserve the previous valid asset until activation and post-read validation succeed; restore it when activation fails. | Replacement service | UPD-FR-005 |
| UPD-DES-006 | Refresh package metadata and install approved security, maintenance, and course-capability updates within the current OS release. | Package adapter | UPD-FR-006 |
| UPD-DES-007 | Exclude OS release-upgrade operations from the update adapter contract and reject a manifest that attempts to request one. | Manifest validator, platform adapter | UPD-FR-007 |
| UPD-DES-008 | Update or repair required user-scoped programming tools and IDE extensions or plug-ins from role bindings. | Runtime and IDE adapters | UPD-FR-008 |
| UPD-DES-009 | Enumerate and preserve optional user extensions or plug-ins; only required managed items are enforced. | IDE adapter | UPD-FR-009 |
| UPD-DES-010 | Remove an obsolete component only when its exact managed asset ID, canonical path, scope, and removal rule are approved. | Path safety and asset services | UPD-FR-010 |
| UPD-DES-011 | Perform only adapter-defined safe cache and dependency cleanup followed by required-component validation. | Package adapter | UPD-FR-011 |
| UPD-DES-012 | Apply bounded retry policy to temporary network and source failures while preserving installed valid state. | Retry service | UPD-FR-012 |
| UPD-DES-013 | Run post-update probes for required capabilities, versions, settings, managed assets, and package consistency. | Check helpers, result aggregator | UPD-FR-013 |
| UPD-DES-014 | Detect and report the least disruptive restart action required; never restart an active session automatically. | Restart detector | UPD-FR-014 |
| UPD-DES-015 | Use state queries, staging, locks, and idempotent operations so an interrupted run can be rerun safely. | Shared services | UPD-FR-015 |
| UPD-DES-016 | Recommend verify after warnings, failures, partial completion, or required restart; successful no-restart maintenance may report verify as optional. | Output service | UPD-FR-016 |

### 11.1 Managed-Asset Update Transaction

```text
retrieve release metadata
validate trust and compatibility
create private staging directory
FOR EACH changed managed asset
    download candidate
    validate size, integrity, structure, and destination
    preserve prior valid asset
    atomically activate candidate
    validate activated asset
    IF activation validation fails
        restore prior valid asset
        record failure
    ENDIF
ENDFOR
remove only explicitly obsolete managed assets
remove staging data
```

### 11.2 Update Ordering

The planned default ordering is:

1. Validate current environment and available space.
2. Obtain and validate approved release metadata and manifest.
3. Stage updated automation assets required for the remainder of the run.
4. Activate compatible script and manifest assets using rollback protection.
5. Refresh system package information and approved system software.
6. Update required user-scoped tools and extensions.
7. Refresh declared managed integrations.
8. Remove explicitly obsolete managed components.
9. Perform safe cleanup.
10. Run post-update checks and restart detection.

A release may require a compatibility bridge when a new manifest schema cannot be interpreted by the installed updater. Release metadata shall identify the minimum updater version and provide an approved staged updater transition rather than allowing incompatible data to be used.

## 12. Error and Exception Handling

### 12.1 Error-Handling Principles

- Detect predictable failures before mutation whenever possible.
- Preserve the original root-cause result during cleanup and logging.
- Stop dependent stages after a required prerequisite fails.
- Continue only independent read-only checks or safe cleanup that adds useful diagnostics.
- Distinguish unsupported, permission, external-service, integrity, cancellation, partial-state, and general failures.
- Never claim success solely because an external command returned without obvious text errors; verify the resulting state.

### 12.2 Error and Recovery Components

| Design ID | Condition | Detection | Planned response | Related SRS requirements |
| --- | --- | --- | --- | --- |
| ERR-DES-001 | Unsupported invocation or platform | Option parser and platform matcher | Make no managed change, explain supported use, return code `2`. | PKG-FR-003, SET-FR-002, PKG-QOS-014 |
| ERR-DES-002 | Missing required privilege | Native privilege probe before mutation | Stop affected action, provide approved command or support path, return code `3`. | SET-FR-001, UPD-FR-001, PKG-NFR-022 |
| ERR-DES-003 | Missing, unreadable, or invalid manifest | File, JSON, schema, semantic, and compatibility validation | Stop before managed change, identify validation stage, return code `5`. | PKG-FR-005, PKG-FR-019 |
| ERR-DES-004 | Integrity validation failure | Checksum, signature, trusted metadata, or equivalent control | Reject candidate, preserve installed asset, return code `5`. | PKG-NFR-024, UPD-FR-004 |
| ERR-DES-005 | Temporary source or network failure | Adapter-classified retryable result | Retry within bounded policy, show truthful status, return code `4` after exhaustion. | UPD-FR-012, PKG-QOS-008 |
| ERR-DES-006 | Concurrent mutating operation | Nonblocking scoped lock | Make no overlapping change, identify active action, return a nonzero result. | UPD-FR-002, PKG-QOS-005 |
| ERR-DES-007 | User cancellation | Explicit prompt result or provider adapter cancellation status | Preserve prior state, mark dependent stages skipped, return code `6` unless a higher-precedence failure exists. | CFG-FR-006, PKG-QOS-014 |
| ERR-DES-008 | Partial operation or interruption | Stage journal, changed flags, incomplete post-validation, or signal handling | Preserve recoverable state, explain rerun or remediation, return code `7`. | UPD-FR-015, PKG-QOS-003 |
| ERR-DES-009 | Invalid existing user settings | Parser or platform settings API | Preserve original file, create sanitized diagnostic copy when safe, do not overwrite with defaults. | CFG-FR-011, PKG-FR-010 |
| ERR-DES-010 | Unsafe managed path or removal target | Canonical path and allowlist validation | Reject operation, record security-relevant failure, make no deletion. | PKG-FR-020, UPD-FR-010, PKG-NFR-023 |
| ERR-DES-011 | Post-operation verification failure | Required probe after change | Attempt approved rollback where available; otherwise mark partial state and give remediation. | SET-FR-008, CFG-FR-014, UPD-FR-013 |
| ERR-DES-012 | Unexpected internal error | Strict error handling and top-level exception or trap | Capture safe context, preserve original status, clean temporary data, summarize, and return code `1` or `7` based on changed state. | PKG-QOS-003, PKG-QOS-012, PKG-QOS-013 |

### 12.3 Retry Policy

Retry behavior is applied only to errors classified as temporary. The initial design uses:

- A small bounded number of attempts.
- Increasing delays between attempts within schema-defined safe limits.
- No retry for invalid credentials, unsupported platforms, integrity failures, invalid manifests, unsafe paths, or user cancellation.
- A visible message before a wait longer than a few seconds.
- Attempt history in the log without exposing secrets.

### 12.4 Interruption and Cleanup

Mutating scripts install handlers for normal termination and supported interruption signals or exceptions. Cleanup attempts to:

- Preserve the original failure result.
- Release locks.
- Remove private temporary files that are no longer needed.
- Leave a valid installed asset active.
- Avoid deleting evidence needed for support.
- Record the stage and whether any managed state changed.

## 13. Privacy and Security Design

### 13.1 Trust Boundaries

The package crosses the following trust boundaries:

1. User input entering the script.
2. Manifest and managed assets entering from an authorized remote source.
3. Provider account information entering through an external CLI or API.
4. Commands crossing from the script into the operating system or package manager.
5. Diagnostic information leaving the computer in a support bundle.

Every boundary has validation, least-privilege, and redaction controls.

| Design ID | Security or privacy control | Design implementation | Related SRS requirements |
| --- | --- | --- | --- |
| SEC-DES-001 | Least privilege | Entry points run as the intended standard user; only specific approved system operations receive elevation. | PKG-NFR-022, REF-TC-003 |
| SEC-DES-002 | No arbitrary manifest execution | Manifest selects allowlisted adapter IDs and validated parameters; it cannot provide executable command strings. | PKG-NFR-023, PKG-NFR-024 |
| SEC-DES-003 | Argument-safe command execution | Executable and arguments remain separate; user and manifest values are never interpolated into an unvalidated shell expression. | PKG-NFR-023 |
| SEC-DES-004 | Managed-path allowlist | Canonical target must fall within an approved managed scope and match the declared asset or settings ownership. | PKG-FR-020, UPD-FR-010 |
| SEC-DES-005 | Trusted-source validation | Remote data uses encrypted transport plus approved integrity or authenticity controls anchored in a trust root. | SET-FR-004, PKG-NFR-024 |
| SEC-DES-006 | Secret minimization | Authentication occurs in the provider's approved mechanism; scripts do not request or store passwords or tokens. | PKG-FR-018, PKG-NFR-025 |
| SEC-DES-007 | Field-aware redaction | Structured sensitive fields are removed before pattern-based fallback redaction and output. | VER-FR-007, PKG-NFR-025 |
| SEC-DES-008 | Private diagnostics | Logs, temporary files, and support bundles use restrictive per-user permissions when supported. | PKG-NFR-026 |
| SEC-DES-009 | Temporary-data lifecycle | Temporary authentication-adjacent or generated configuration data is deleted after safe use and error handling. | PKG-NFR-027 |
| SEC-DES-010 | User-owned data exclusion | File discovery for support and cleanup starts from explicit allowlists, not broad recursive collection. | PKG-FR-010, PKG-QOS-022 |
| SEC-DES-011 | Provider-data minimization | Provider adapters request only account fields declared by the approved profile and needed by configuration. | CFG-FR-007, PKG-NFR-025 |
| SEC-DES-012 | Change auditability | Logs identify release, stage, managed asset IDs, and result without storing secret values. | PKG-QOS-017, PKG-QOS-018 |

### 13.2 Redaction Order

1. Remove fields marked secret by the adapter contract.
2. Replace complete personal email addresses with an approved masked representation or identity type.
3. Remove token-, key-, cookie-, and credential-like values.
4. Normalize user-specific paths when a full path is not required for diagnosis.
5. Apply pattern-based checks as a defense in depth.
6. Scan the final support-bundle inventory and contents before creation.

### 13.3 Trust-Root Design

The manifest cannot prove its own authenticity using only values stored inside itself. The initial implementation shall anchor trust in one or more items distributed with the approved script release, such as:

- An allowlisted institutional or project source location.
- A pinned public verification key.
- A release metadata format with independently verifiable signatures.
- A trusted native package repository.

The exact approved mechanism is platform- and release-specific and belongs in the platform design and controlled release process.

## 14. Platform and Provider Abstraction Design

### 14.1 Platform-Independent and Platform-Specific Layers

| Design ID | Design element | Stable interface | Platform-specific implementation | Related SRS requirements |
| --- | --- | --- | --- | --- |
| PLT-DES-001 | Platform detection | Return normalized platform facts. | Native OS and session queries. | PKG-FR-003, REF-TC-001 |
| PLT-DES-002 | Native scripting | Implement the same orchestrator stages and result contracts. | Approved platform-native scripting language and conventions. | PKG-TC-001, REF-TC-002 |
| PLT-DES-003 | Package management | Query, refresh, install, update, repair, cleanup, and validate approved packages. | Native package-manager adapter. | SET-FR-003 through SET-FR-006, UPD-FR-006, UPD-FR-011 |
| PLT-DES-004 | Privilege control | Determine capability and elevate one approved operation. | Native privilege mechanism. | PKG-NFR-022, REF-TC-003 |
| PLT-DES-005 | Path resolution | Return canonical home, desktop, temporary, configuration, and executable paths. | Native environment and folder APIs. | PKG-NFR-019, PKG-NFR-020, REF-TC-005 |
| PLT-DES-006 | User integration | Create or query approved launchers, file associations, and default-folder behavior. | Native desktop or shell integration. | CFG-FR-013, REF-TC-006 |
| PLT-DES-007 | Restart detection | Report required application, session, virtual-machine, or computer restart. | Native update and session indicators. | UPD-FR-014, REF-TC-004 |
| PLT-DES-008 | Provider integration | Expose stable authentication and account operations. | Allowlisted provider adapter selected by the profile. | CFG-FR-005 through CFG-FR-008 |
| PLT-DES-009 | Equivalent outcomes | Use the same status, log, remediation, and acceptance semantics. | Different native commands may produce the required final state. | PKG-NFR-001, PKG-NFR-021 |
| PLT-DES-010 | Platform qualification | Require manifest entry, adapter implementation, bootstrap instructions, platform constraints, and full conformance testing. | Platform-specific evidence package. | Section 3.3 of the SRS |
| PLT-DES-011 | Deployment-profile resolution | Select one enabled profile by detected environment or explicit approved context, then confirm its platform, release, architecture, desktop, and session constraints. | Provider, desktop-session, and reset detection appropriate to the profile. | REF-TC-001 through REF-TC-006, PKG-FR-003 |

### 14.2 Adapter Contract Rules

Every adapter method shall:

- Accept validated structured parameters.
- Return an `OperationResult` or structured query value.
- Avoid writing directly to the terminal except through the output or captured-command interface.
- Identify whether it changed state.
- Preserve the native exit status and sanitized diagnostic detail.
- Declare whether privilege is required.
- Support a query operation used for idempotence and verification.
- Avoid product-specific logic in the orchestrator.

### 14.3 Provider Adapter Rules

A provider adapter is added only when:

- Its authentication flow can be explained and supported for first-term students.
- It can report authentication status without exposing credentials.
- It can return the approved minimum account fields.
- It has a documented privacy-preserving commit-identity rule when required.
- Its failure and cancellation states can be distinguished.
- It has automated contract tests and controlled test accounts or mocks.

### 14.4 New Platform Qualification

A proposed platform implementation is not marked supported until it provides:

- Four correctly named lifecycle entry points.
- A manifest platform entry, any applicable deployment-profile entry, and schema-valid role bindings.
- Platform, package-manager, privilege, path, settings, restart, and user-integration adapters.
- Bootstrap instructions that work before the managed environment exists.
- Unit and integration tests for adapters.
- Full SRS acceptance-test evidence on a clean supported environment.
- Idempotence evidence from repeated setup, configure, and update runs.
- Read-only evidence for verify.
- Student-work preservation and redaction evidence.

### 14.5 Initial Platform Conformance Test Matrix

The initial release qualification uses resettable environments that match enabled deployment profiles.

| Test target | Role | Required use |
| --- | --- | --- |
| Codio Virtual Desktop: Ubuntu 24.04 LTS, APT, Xfce, x86_64 | Reference deployment | Run the complete lifecycle, acceptance, idempotence, interruption, support-log, and student-work-preservation suites for every release candidate. |
| Supported Windows 11 on x86_64 bare metal | Supported local deployment | Reset to a clean supported release and run the complete platform conformance suite before approval. |
| Supported macOS on Apple Silicon bare metal | Supported local deployment | Erase or restore to a clean supported release and run the complete platform conformance suite before approval. |
| Ubuntu 24.04 LTS with APT and GNOME on x86_64 bare metal | Supported local deployment | Reinstall or restore a clean image and run the complete platform conformance suite before approval. |
| Raspberry Pi 4B and 5 | Exploratory ARM64 targets | Evaluate portability, package availability, desktop behavior, and performance. Do not mark ARM64 supported until the full suite passes for an enabled deployment profile. |
| Windows XP, 7, and 8 systems | Negative unsupported-platform targets | Confirm that platform detection reports an unsupported environment, creates only the minimum safe diagnostic log when possible, and performs no managed system or user changes. |

A clean test begins from a fresh operating-system installation, provider reset, or approved image restoration. Test evidence records the exact release, build, architecture, deployment profile, manifest release, script release, and final results.

## 15. Performance, Logging, and Operational Design

### 15.1 Performance Controls

- The entry point starts the log and displays identifying information before lengthy network or package work.
- Manifest and schema files are loaded once per run and passed as immutable validated data.
- Local state probes are preferred over downloads or reinstallations.
- Capability checks may run in parallel only when they are read-only, independent, and the platform implementation can preserve deterministic output and reasonable resource use.
- Package-manager mutations remain serialized.
- Verification uses bounded timeouts for network checks and should not wait on interactive authentication.
- Verification shall complete within the SRS limit on the approved reference platform under the stated normal conditions, implementing `PKG-QOS-009`.
- Platform adapters shall accept only manifest-approved operating-system releases that still receive vendor security updates, implementing `PKG-TC-006`.
- Long operations emit truthful stage messages at intervals required by the SRS.

### 15.2 Log Filename Design

The default logical pattern is:

```text
<action>_<platform>_<YYYYMMDD>_<HHMMSS>.<log-extension>
```

The path is derived from the current user's approved course log directory. A collision-resistant suffix may be added when two runs begin within the same second.

### 15.3 Message Catalog

Student-facing messages should use stable message keys and parameterized values where practical. This improves consistency across scripts and platforms and supports future accessibility or localization work without changing orchestration logic.

Example logical keys:

```text
run.start
manifest.valid
platform.unsupported
privilege.required
provider.auth.action_required
operation.changed
operation.unchanged
verify.remediation
run.summary
```

Exact English wording may differ slightly by platform when needed, but meaning, status label, and remediation shall remain equivalent.

## 16. Design Decisions and Rationale

| # | Design decision | Rationale | Alternative considered |
| ---: | --- | --- | --- |
| 1 | Use one combined package SDD. | The five scripts share data, services, interfaces, quality rules, and remediation paths. One SDD reduces duplication and drift. | Separate SDD per script; rejected for the initial release because shared design would be repeated. |
| 2 | Keep stable capability roles in the design and concrete products in the controlled manifest. | Product selections change more often than course capabilities. | Hardcode products in every script and design section; rejected because it increases maintenance and inconsistency. |
| 3 | Allow only reviewed adapter identifiers in the manifest. | A public configuration file must not become an arbitrary command-execution mechanism. | Store executable command templates in JSON; rejected for security and portability reasons. |
| 4 | Use platform-native entry points rather than one course-managed cross-platform runtime. | Setup must run before the course runtime is guaranteed to exist. | Require a shared runtime before setup; rejected because it adds a bootstrap dependency. |
| 5 | Use four entry points with shared services. | Separate actions are easier for students and support personnel to understand while shared services maintain consistency. | One script with many subcommands; deferred because it increases command complexity for beginners. |
| 6 | Make setup and configure idempotent repair paths. | Rerunning the correct lifecycle script is simpler than adding a separate repair script. | Add `repair`; deferred unless evidence shows the five-script model is insufficient. |
| 7 | Keep verify structurally read-only. | Troubleshooting should observe the original problem and remain safe for students and support staff. | Permit optional repair inside verify; rejected because it mixes diagnosis and mutation. |
| 8 | Put course-managed asset synchronization in update. | Existing copied installations need corrected scripts and manifests without another mandatory command. | Add a separate sync script; deferred to avoid expanding the support matrix. |
| 9 | Use query-plan-apply-verify for mutating actions. | This pattern supports idempotence, minimal change, and evidence that the final state is usable. | Always reinstall or overwrite; rejected because it is slower and risks user settings. |
| 10 | Use staging and atomic replacement for managed files. | A failed download or interrupted write must not replace a working asset with a partial file. | Write directly to the destination; rejected because recovery is weaker. |
| 11 | Use plain-text logs with stable fields. | Students and support personnel can read them without specialized tools. | Store only structured machine logs; rejected for student usability, though structured supplemental data may be added later. |
| 12 | Keep the reference product mapping in a nonnormative appendix. | Reviewers need concrete context, but the manifest remains the current authority. | Remove all product names; rejected because it weakens review and test context. |

## 17. Requirements Traceability

A range in this table is inclusive. The design elements listed for a range apply to every requirement in that range. Script-specific requirements map one-to-one to the correspondingly numbered script design element where possible.

| SRS requirement(s) | Primary SDD design elements | Supporting planned artifact(s) |
| --- | --- | --- |
| PKG-FR-001 through PKG-FR-003 | ARC-DES-001, ARC-DES-003, SHR-DES-006, PLT-DES-001, PLT-DES-010 | Architecture diagram; all four pseudoscripts |
| PKG-FR-004 through PKG-FR-005 | ARC-DES-004, SHR-DES-004, SHR-DES-005, DAT-DES-001 through DAT-DES-006 | Manifest schema; all four pseudoscripts |
| PKG-FR-006 through PKG-FR-009 | SHR-DES-001 through SHR-DES-003, SHR-DES-012, INT-DES-001 through INT-DES-012 | Shared-output design; all four pseudoscripts |
| PKG-FR-010 | ARC-DES-005, SHR-DES-009, SEC-DES-004, SEC-DES-010 | Safety tests; managed-path tests |
| SET-FR-001 through SET-FR-012 | SET-DES-001 through SET-DES-012 | `install_ide.pseudo`; setup flowchart; setup tests |
| CFG-FR-001 through CFG-FR-016 | CFG-DES-001 through CFG-DES-016 | `configure_ide.pseudo`; configure flowchart; configure tests |
| VER-FR-001 through VER-FR-014 | VER-DES-001 through VER-DES-014 | `verify_ide.pseudo`; check registry; verify tests |
| UPD-FR-001 through UPD-FR-016 | UPD-DES-001 through UPD-DES-016 | `update_ide.pseudo`; update transaction diagram; update tests |
| PKG-FR-011 through PKG-FR-020 | DAT-DES-001 through DAT-DES-014, SHR-DES-009, SEC-DES-004 | Manifest schema; configuration-control procedure |
| PKG-NFR-001 through PKG-NFR-005 | ARC-DES-003 through ARC-DES-010, SHR-DES-002, DAT-DES-011; explicit coverage includes PKG-NFR-004 | Architecture diagram; conformance tests |
| PKG-NFR-006 through PKG-NFR-011 | INT-DES-004, INT-DES-008 through INT-DES-012, SHR-DES-002 | Message catalog; usability review |
| PKG-NFR-012 through PKG-NFR-017 | ARC-DES-004, ARC-DES-010, DAT-DES-014, shared component structure; explicit coverage includes PKG-NFR-013, PKG-NFR-014, and PKG-NFR-016 | Static-analysis configuration; automated tests; change history |
| PKG-NFR-018 through PKG-NFR-021 | ARC-DES-003, ARC-DES-008, PLT-DES-001 through PLT-DES-010 | Platform adapter contract; conformance suite |
| PKG-NFR-022 through PKG-NFR-027 | SHR-DES-008, SHR-DES-009, SHR-DES-013, SEC-DES-001 through SEC-DES-012 | Security tests; redaction tests; support-bundle tests |
| PKG-TC-001 through PKG-TC-009 | ARC-DES-003, ARC-DES-008, DAT-DES-001 through DAT-DES-014, PLT-DES-001 through PLT-DES-010; explicit coverage includes PKG-TC-002, PKG-TC-003, PKG-TC-005, and PKG-TC-006 | Manifest schema; platform design documents |
| REF-TC-001 through REF-TC-007 | PLT-DES-001 through PLT-DES-007, Appendix A | Reference-platform adapter design and acceptance evidence |
| PKG-QOS-001 through PKG-QOS-006 | ARC-DES-006, SHR-DES-010 through SHR-DES-012, ERR-DES-006, ERR-DES-008, ERR-DES-011 | Idempotence, interruption, and concurrency tests |
| PKG-QOS-007 through PKG-QOS-010 | INT-DES-010, Section 14.1; explicit verification-time coverage includes PKG-QOS-009 | Performance acceptance tests |
| PKG-QOS-011 through PKG-QOS-015 | SHR-DES-012, Section 5.5, ERR-DES-001 through ERR-DES-012 | Error-injection and exit-code tests |
| PKG-QOS-016 through PKG-QOS-022 | SHR-DES-001 through SHR-DES-003, SHR-DES-013, DAT-DES-014, INT-DES-012, SEC-DES-007 through SEC-DES-012 | Log tests; support-bundle tests |

### 17.1 Construction Traceability Rule

During construction, each implementation function or module shall identify its primary SDD design element in a nearby comment, docstring, test name, or traceability record. Source code should not be cluttered by listing every related requirement when a module-level traceability record provides the mapping clearly.

### 17.2 Test Traceability Rule

Automated and manual tests shall use stable test identifiers and identify:

- The SRS requirement or acceptance test being verified.
- The SDD design element being exercised.
- The platform and manifest release used.
- The starting state and expected final state.
- Whether the test verifies normal, boundary, invalid, interruption, security, privacy, or idempotence behavior.

## 18. Design Review Criteria

Before construction begins, reviewers shall confirm the following evidence:

| Review area | Acceptance evidence |
| --- | --- |
| SRS coverage | Every SRS requirement is included in Section 16 traceability. |
| Responsibility separation | Setup, configure, verify, and update remain within their approved state and privilege boundaries. |
| Evergreen design | Main-body orchestration uses capability roles and adapters rather than current product names. |
| Controlled configuration | Concrete products, versions, sources, and provider rules are assigned to the manifest and schema. |
| Manifest safety | Manifest data cannot directly introduce arbitrary executable commands or unsafe paths. |
| Idempotence | Query-plan-apply-verify behavior is defined for setup, configure, and update. |
| Read-only verification | Verify receives only read interfaces and cannot invoke mutating adapter methods. |
| User-data protection | Managed paths and settings keys are explicit; other content is user-owned. |
| Error recovery | Staging, rollback, locks, retry boundaries, interruption handling, and exit precedence are defined. |
| Privacy and security | Least privilege, trust roots, input validation, redaction, file permissions, and bundle exclusions are defined. |
| Student usability | Stages, labels, prompts, explanations, next steps, and logs are understandable without relying on color. |
| Platform portability | Adapter contracts and new-platform qualification evidence are defined. |
| Design consistency | The SDD, diagrams, pseudoscripts, schema, implementation, and tests can describe one solution without contradiction. |

## Appendix A (Nonnormative): Reference Environment Used for Initial Design and Testing

### A.1 Purpose and Authority

This appendix records the concrete reference environment used to review this SDD and design the initial adapters and tests. It is **nonnormative**, meaning it provides context but does not override the SRS or controlled manifest. The current approved `it140_manifest.json` is authoritative when this appendix and the manifest differ.

The reference mapping should be updated when convenient for historical clarity, but a routine product or version change does not require an SDD change unless the architecture, capability, interface, security boundary, or workflow changes.

### A.2 Reference Platform Mapping

| Generic design role | Initial reference selection |
| --- | --- |
| Deployment profile identifier | `codio_cvd` |
| Hosted virtual desktop provider | Codio Virtual Desktop (CVD) |
| Operating system | Ubuntu 24.04 Long-Term Support (LTS) |
| Graphical desktop | Xfce |
| Session type | Hosted remote graphical desktop |
| Native script language | Bash |
| System package manager | Advanced Package Tool (APT) |
| Controlled privilege elevation | Passwordless `sudo` for approved system commands |
| Standard course root | `$HOME/it140` |
| Standard log directory | `$HOME/it140/logs` |

### A.3 Reference Capability Bindings

| Generic capability role | Initial reference product or tool | Initial design purpose |
| --- | --- | --- |
| Version-control client | Git | Record file changes and interact with repositories. |
| Source-code hosting provider | GitHub | Store course repositories and provide authentication and account APIs. |
| Source-host command-line client | GitHub CLI (`gh`) | Authenticate and perform approved provider operations from the terminal. |
| Programming-language runtime | Python 3.12 | Run course programs and approved tools. |
| Programming package installer and environment support | `pip`, `venv` | Install user-scoped course tools and create isolated environments when required. |
| Test runner | pytest | Run tests supplied with course activities. |
| Coverage reporter | pytest-cov | Report coverage when included with supplied tests. |
| Code-quality checker and formatter | Ruff | Identify style or quality issues and format code consistently. |
| Source-code editor or IDE | Visual Studio Code | Edit, run, test, debug, and manage course files. |
| Secure retrieval and source validation | `ca-certificates`, `curl`, `gpg` | Retrieve and validate approved software sources. |
| Project environment helper | direnv | Apply approved project-specific environment settings when present. |
| Folder-tree display | `tree` | Display folder structures in a readable form. |
| Desktop clipboard helper | `xclip` | Support clipboard operations in the reference graphical desktop. |
| Keyboard-state helper | `numlockx` | Apply the approved Num Lock desktop behavior. |

### A.4 Reference IDE Extensions

| Extension identifier | Course capability |
| --- | --- |
| `ms-python.python` | Programming-language support in the IDE. |
| `charliermarsh.ruff` | Code-quality checking and formatting integration. |
| `hediet.vscode-drawio` | Diagram viewing and editing. |
| `streetsidesoftware.code-spell-checker` | Spelling support for comments and documentation. |
| `i2p-hub.i2p-pseudo` | Pseudoscript file support. |
| `cweijan.vscode-office` | Supported office-document viewing. |

### A.5 Reference Provider Profile

The initial provider adapter is GitHub-specific because the current workflow uses GitHub authentication, account APIs, a numeric account identifier, a public user name, and GitHub's private `noreply` commit-email convention. These details belong in the controlled provider profile and provider adapter rather than the generic configure orchestrator.

The provider profile shall select the approved browser-based authentication method, required account fields, privacy identity template, validation rules, and support guidance. Authentication tokens remain in the GitHub CLI credential store and are not copied into the manifest, log, or script settings.

### A.6 Reference Distribution Channels

The initial reference implementation uses approved official operating-system, vendor, project, and institutional distribution channels recorded in the manifest. Concrete URLs, repository definitions, signing keys, package identifiers, and integrity values belong in the controlled manifest or platform release data rather than this SDD.

## Appendix B: Planned Platform-Specific Design Supplements

Each supported platform may have a concise supplement that records only design details that cannot remain generic, including:

- Native script language conventions and strict mode.
- Package-manager operations and source configuration.
- Privilege-elevation mechanism.
- Native path and desktop-folder discovery.
- User settings and launcher interfaces.
- Restart detection and user instructions.
- Capability adapter bindings that require platform-specific code.
- Known platform limitations and approved workarounds.
- Evidence that the platform produces equivalent required outcomes.

A supplement shall not redefine shared exit codes, log fields, status meanings, manifest ownership, user-data boundaries, or lifecycle responsibilities.

## Appendix C: References

- `scripts/.dev/analysis/it140_scripts_srs.md`, *IT 140 Course Automation Scripts Software Requirements Specification*, version 2026.07.25.2.
- `scripts/.dev/README.md`, development notes and five-script lifecycle decisions.
- `scripts/.manifest/it140_manifest.json`, controlled product, platform, deployment-profile, provider, version, source, and managed-asset selections when populated and approved.
- `scripts/.dev/design/it140_scripts_sdd.md`, prior generic SDD template used as the structural starting point for this document.
- Repository acceptance-test and platform-script files at the baseline commit identified in the document metadata.
