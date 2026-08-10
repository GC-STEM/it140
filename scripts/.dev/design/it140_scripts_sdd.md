# Software Design Description

- **Course**: IT 140 - *Introduction to Scripting*
- **Activity**: Course Automation Script Development
- **Program Name**: IT 140 Course Automation Scripts
- **Document ID**: IT140-SDD-SCRIPTS
- **Status**: Draft for faculty review
- **Version**: 0.6.0
- **Version Date-Time Group**: 2026-08-07-10-44
- **SRS Baseline**: `IT140-SRS-SCRIPTS`, version `0.6.0`, version date-time group `2026-08-07-10-44`
- **Repository Baseline**: `GC-STEM/it140` commit `dbde859f90b1b957b05aa03e25b867563c113bb2`

## 0. General Description

### 0.1 Purpose

This Software Design Description (SDD) explains how the **IT 140 Course Automation Scripts** package will be organized to satisfy the approved Software Requirements Specification (SRS). The SRS defines **what** the package must do. This SDD defines the planned software structure, data, interfaces, control flow, safety mechanisms, version-control approach, and platform-abstraction approach that developers will use to build it--in other words, **how** the package will fulfill the requirements.

The package contains five coordinated lifecycle components for each supported platform:

1. `prepare_it140.<ext>` provides the platform-native first-use command set and, after first use, refreshes the local course automation package.
2. `install_it140.<ext>` establishes or repairs system-level software and settings.
3. `configure_it140.<ext>` establishes or repairs the current user's environment.
4. `verify_it140.<ext>` inspects the system and user layers without changing them.
5. `update_it140.<ext>` maintains approved course IDE software and course-managed maintenance assets over time.

On first use, the user copies and runs the documented `prepare_it140.<ext>` commands because the local package does not yet exist. After first use, the installed `prepare_it140.<ext>` artifact may be executed directly to refresh the lifecycle scripts and controlled package files from the authorized course repository.

The design follows a modified [Waterfall Model](https://www.geeksforgeeks.org/software-engineering/waterfall-model/) software development lifecycle (SDLC): requirements analysis, design, construction, and testing. **SDLC** means the organized process used to plan, build, verify, release, and maintain software.

### 0.2 Design Philosophy

The main body of this SDD is intentionally **evergreen**. It describes stable capabilities and design contracts instead of embedding current product names, package identifiers, extension identifiers, or product versions. The controlled manifest selects the concrete approved products and versions used by each platform implementation.

Product names are retained only when one of the following conditions applies:

- A concrete external interface cannot be described honestly without identifying its provider.
- A repository filename, command, or file format is itself part of the approved design.
- A nonnormative appendix records the reference environment used for review and testing.

The manifest is not allowed to contain arbitrary executable commands. It may select approved adapters and provide validated data, but executable behavior remains in reviewed source code. An **adapter** is a component that translates a stable package operation into commands appropriate for one platform, package manager, application, or external service.

Every controlled analysis, design, construction, testing, release, and maintenance artifact has its own strict Semantic Versioning (SemVer) `MAJOR.MINOR.PATCH` version and separate `YYYY-MM-DD-HH-MM` version date-time group. Generated logs, transcripts, test results, and support-bundle inventories record the version and version date-time group of the artifact that produced or governed the result. Version date-time groups supplement SemVer; they do not determine version precedence.

### 0.3 Relationship Among Requirements, Design, Configuration, and Code

| Artifact | Primary question answered | Change authority |
| :------: | :----------------------- | :---------------- |
| [SRS](../analysis/it140_scripts_srs.md) | What behavior and quality are required? | Approved requirements change process |
| SDD | How will the package be structured to satisfy the SRS? | Approved high-level design change process |
| [Flowcharts](../flowcharts/) | How do the package's major processes, decisions, and control paths interact? | Approved mid-level design change process |
| [Pseudoscripts](../pseudoscripts/) | What detailed, platform-neutral logic, sequencing, state handling, and error behavior must each lifecycle component implement? | Approved low-level design change process |
| [Manifest schema](../../.manifest/it140_manifest.schema.json) | What configuration structure and value types are valid? | Design and configuration-control process |
| [Controlled manifest](../../.manifest/it140_manifest.json) | Which products, versions, sources, platforms, and provider profiles are approved now? | Configuration review, testing, approval, and release process |
| [Platform scripts](../../../scripts/) | How is the approved design implemented and verified on each platform? | Source-control review and testing process |

A manifest-only change is appropriate when the selected product or product version changes but the required capability, user workflow, trust boundary, design logic, and acceptance criteria remain the same. An SRS and SDD review is required when a change alters any of those items. Affected flowcharts and pseudoscripts must also be reviewed and updated when a design change alters their documented processes, decisions, sequencing, state handling, or error behavior.

Each controlled artifact carries an independent `artifact_version` or equivalent SemVer identifier and `version_date`. Traceability records identify the exact versions and dates of the SRS, SDD, applicable flowcharts, applicable pseudoscripts, manifest schema, controlled manifest, implementation, test definition, and test result used for a release decision. A changed artifact receives the SemVer increment required by its own compatibility effect; related artifacts do not receive artificial version changes merely to make their numbers match.

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

- The package architecture and five-component lifecycle.
- The special first-use and refresh behavior of `prepare_it140.<ext>`.
- The logical design of the controlled manifest and its schema.
- Shared services used by the managed lifecycle scripts.
- Script-specific component and control-flow designs.
- Command-line, file, operating-system, package-manager, desktop-integration, and external-service interfaces.
- Error handling, recovery, privacy, security, logging, and support-bundle design.
- SemVer, version-date, release-identity, and traceability design.
- Platform adapters and the selective process for adding another designated course-supported deployment profile.
- Traceability from SRS requirements to design elements and supporting artifacts.

This SDD does not define:

- Student assignment solutions or grading logic.
- The final syntax of every platform implementation.
- Product and product-version selections that belong in the controlled manifest.
- General-purpose backup, reset, uninstall, or account-recovery features.
- A second bootstrap mechanism separate from the command set represented by `prepare_it140.<ext>`.

### 0.6 Terms and Abbreviations

| Term | Definition and purpose in this SDD |
| --- | --- |
| Adapter | A component that translates a stable package operation into platform-, product-, or provider-specific actions. |
| Artifact | A versioned file or generated record created or maintained during analysis, design, construction, logging, testing, release, or maintenance. |
| Atomic replacement | A file update that makes the complete new file visible at once instead of exposing a partially written file. |
| Bootstrap command set | The first-use, platform-native commands represented by `prepare_it140.<ext>` that obtain or refresh the local automation package without depending on that package. |
| Capability role | A generic function required by the course, such as source-code editing, version control, test running, or code-quality checking. The manifest binds each role to an approved product. |
| Check registry | The ordered collection of verification checks, including each check's requirement mapping, severity, and remediation owner. |
| Component | A cohesive part of the design with one primary responsibility and a defined interface. |
| Controlled configuration item | A file or data set whose changes require review, testing, approval, and release tracking. |
| Course-supported deployment profile | A deployment profile whose applicable platform implementation, bindings, qualification testing, documentation, and approval for course use are complete. |
| Deployment profile | A concrete local, virtual, or hosted environment that uses one platform implementation and records provider, desktop, session, release, architecture, reset characteristics, and permitted lifecycle workflows. |
| Lifecycle workflow | A manifest-selected ordered sequence of lifecycle components for a deployment profile, starting-state classification, and operating role. |
| Repository workspace | The student development root at `${HOME}/Repos` or exact native equivalent. Configure may create the parent directory and explicitly course-owned integrations; all child repositories and files are student-owned and outside lifecycle-script mutation scope. |
| Provider baseline master | The clean CVD provider image before IT 140-specific system provisioning. |
| IT 140 course master | The CVD image after the administrator workflow has installed and verified the IT 140 system layer and before student-specific configuration. |
| Dependency | A component, tool, file, service, or condition required before another operation can succeed. |
| Idempotent | Safe to run repeatedly. Repeated execution reaches the required state without harmful duplication or damage. |
| Managed asset | A file, setting, package, launcher, extension, plug-in, or other item the package is authorized to manage. |
| Manifest | The controlled JavaScript Object Notation (JSON) file that selects approved products, versions, sources, settings, provider profiles, and managed paths. |
| Orchestrator | The script layer that controls processing order, calls shared services and adapters, and produces the final result. |
| Platform adapter | The code that performs operating-system-specific detection, installation, settings, privilege, restart, path, and desktop-integration operations. |
| Platform implementation | One platform-native set of lifecycle entry points and adapters that may serve one or more deployment profiles. |
| Provider profile | Validated manifest data describing an approved external service's authentication method, account fields, identity rules, and selected provider adapter. |
| Read-only | Designed not to install, update, remove, repair, or rewrite software, files, or settings. |
| Redaction | Removing or masking secrets and unnecessary personally identifiable information (PII) before displaying or saving data. |
| Rollback | Restoring a previous valid state after a new managed asset cannot be installed successfully. |
| Run context | The in-memory data describing one script run, including action, artifact version, version date-time group, platform, user, time, paths, manifest release, and accumulated result. |
| Schema | A machine-readable definition of allowed manifest fields, data types, required values, and structural rules. |
| Semantic Versioning (SemVer) | A versioning scheme expressed as `MAJOR.MINOR.PATCH`. Incompatible changes increment MAJOR, backward-compatible functionality increments MINOR, and backward-compatible corrections increment PATCH. |
| Staging | Downloading or generating a candidate asset in a temporary location before validating and activating it. |
| Technical compatibility | Evidence that the required stack might operate on a profile. It does not establish implementation completeness, qualification, documentation, approval, or course support. |
| Trust root | The small, preapproved source of authority used to decide whether downloaded configuration or code is authentic. |
| Validation | Checking structure, type, value, relationships, paths, integrity, and compatibility before data is used. |
| Version date-time group | The calendar date, written as `YYYY-MM-DD`, on which a specific artifact version was created or approved. It supplements SemVer and does not determine version precedence. |

### 0.7 Design Element Identifiers

Each important design element has a stable identifier. Design identifiers support traceability but do not create new stakeholder requirements.

- `ARC-DES-###`: package architecture
- `DAT-DES-###`: data and manifest design
- `INT-DES-###`: interface and input/output design
- `SHR-DES-###`: shared service design
- `PRE-DES-###`: prepare-component design
- `INS-DES-###`: install-script design
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
| ARC-DES-001 | Preserve the five lifecycle components while permitting profile-specific workflow sequences. | Each supported platform provides `prepare`, `install`, `configure`, `verify`, and `update` entry points; a workflow resolver selects the permitted sequence and next step from deployment profile, starting state, and operating role. | PKG-FR-001, PKG-FR-002, PKG-FR-022, PKG-FR-023 |
| ARC-DES-002 | Separate package preparation, system installation, user configuration, read-only verification, and maintenance responsibilities. | Each operation is placed in the component that owns the required privilege, data, and state boundary. | PRE-FR-015, INS-FR-011, VER-FR-001, REF-TC-006 |
| ARC-DES-003 | Keep the main design capability-based and product-neutral. | Product names and identifiers are resolved through manifest role bindings and approved adapters. | PKG-TC-008, PKG-NFR-018, PKG-NFR-021 |
| ARC-DES-004 | Use one controlled source of configuration truth after preparation. | Managed lifecycle scripts load the same validated manifest and do not maintain independent authoritative product lists; Prepare uses only its embedded trust-root data and structural expectations. | PKG-FR-004, PKG-NFR-012, PRE-FR-003 |
| ARC-DES-005 | Preserve user-owned work and unrelated settings. | Managed paths, settings keys, package-refresh targets, and removal targets are allowlisted; all other content is treated as user-owned. | PKG-FR-010, PKG-FR-020, PRE-FR-009, PRE-FR-010 |
| ARC-DES-006 | Make repair and refresh normal lifecycle behavior. | Prepare refreshes package files; install and configure repair their owned layers; update repairs maintenance-scope assets; verify identifies the correct owner. | PRE-FR-002, INS-FR-009, INS-FR-010, CFG-FR-016, UPD-FR-015, VER-FR-009 |
| ARC-DES-007 | Support beginners without weakening technical correctness. | Output uses consistent stages, labels, explanations, exact next steps, desktop entry points, and copyable commands. | PKG-NFR-002, PKG-NFR-003, PKG-NFR-006 through PKG-NFR-011, CFG-FR-013, CFG-FR-014 |
| ARC-DES-008 | Avoid requiring a course-managed runtime before installation establishes it. | Prepare uses only approved platform-native facilities expected on the baseline; each managed entry point uses the approved platform-native scripting language. | PRE-FR-003, PKG-TC-001, REF-TC-002 |
| ARC-DES-009 | Make failure recoverable and diagnosable. | Mutating operations use validation, staging, bounded retries, locks where applicable, rollback where practical, logs, and deterministic exit codes. | PRE-FR-012, PRE-FR-014, PKG-QOS-003 through PKG-QOS-005, PKG-QOS-011 through PKG-QOS-022 |
| ARC-DES-010 | Maintain complete traceability. | Every SRS requirement maps to one or more versioned design elements, implementation artifacts, tests, and maintenance records. | Appendix B of the SRS |
| ARC-DES-011 | Give every controlled artifact an independent release identity. | Artifact headers, manifest metadata, logs, test records, support inventories, and traceability records carry strict SemVer and a separate version date-time group. | PKG-FR-006, PKG-NFR-015, VER-FR-003 |
| ARC-DES-012 | Design for selective platform expansion rather than universal platform coverage. | Stable lifecycle orchestration and reviewed adapter boundaries allow a justified deployment profile to be added without redesigning the package core, while support remains limited to profiles the course can implement, qualify, document, approve, and maintain. | PKG-NFR-018, PKG-NFR-028, PKG-TC-006, Section 3.3 of the SRS |

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

The package uses a **layered orchestrator-and-adapter architecture** with a minimal bootstrap boundary.

- The **prepare boundary** is a self-contained, platform-native command set that obtains or refreshes the package before the manifest and shared implementation can be assumed available.
- The **entry-point layer** identifies a managed lifecycle action and initializes the run.
- The **orchestration layer** controls the action's stages and decisions.
- The **shared-service layer** provides manifest handling, logging, version identity, validation, command execution, locking, redaction, result aggregation, and file safety.
- The **platform-adapter layer** performs operating-system-specific operations.
- The **capability-adapter layer** manages approved product roles such as the programming runtime, source-code editor or IDE, test tools, and external provider client.
- The **data layer** contains the manifest, schema, logs, temporary staging data, managed assets, and artifact identity metadata.

This architecture is extensible but does not create a universal support commitment. Platform deployment profiles are selected for implementation and qualification according to course need and available resources. Upstream product compatibility or successful unqualified use does not make a profile course-supported.

```text
First-use user commands                 Installed package
 | |
        +---------------+----------------------+
                        v
               Prepare Component
       (native retrieval, staging, validation,
          package refresh, PATH, transcript)
 |
                        v
             Local Package Available
 |
                        v
           Managed Lifecycle Entry Point
       (install | configure | verify | update)
 |
                        v
                Action Orchestrator
 |
        +---------------- Shared Services ----------------+
 | Manifest | Version | Log | Validation | Lock |
 | Results | Paths | Staging | Command Runner |
        +-------------------------------------------------+
 |
        +---------------+----------------+----------------+
        v                                v                v
Platform Adapter              Capability Adapters  Provider Adapter
 | | |
        v                                v                v
Operating System              Approved Products   External Service
```

### 2.2 Package Lifecycle and Workflow Resolution

The package preserves five lifecycle components, but it does not impose one universal initial sequence. The workflow resolver uses the selected deployment profile, a bounded starting-state classification, and an authorized operating role. It does not infer workflow authority from a username alone.

```text
Local unmanaged environment
    Prepare → Install → Configure → Verify

CVD provider baseline master (authorized administrator or SME)
    Prepare → Update [initial provider baseline] → Install → Configure → Verify

IT 140 course master (student or faculty course user)
    Prepare → Update [initial course master] → Configure → Verify

Any initialized environment
    Update [periodic maintenance] → Verify when indicated
```

The **provider baseline master** is the clean provider image before IT 140-specific system provisioning. The **IT 140 course master** is the administrator-produced image after the approved system layer has been installed and verified. A student never runs Install on the IT 140 course master because that responsibility has already been completed before image distribution.

Update receives a resolved update mode: `initial_provider_baseline`, `initial_course_master`, or `periodic_maintenance`. The mode changes sequencing, labels, prerequisites, and next-step output; it does not transfer Install or Configure responsibilities into Update. Verify remains callable from any package-present state and remains read-only.

### 2.3 Normal Processing Pattern

#### 2.3.1 Prepare Processing Pattern

Prepare uses a deliberately small native flow because the controlled manifest, shared modules, package manager, version-control client, and other lifecycle scripts may not exist yet:

1. Enable strict native error handling and register cleanup.
2. Derive the current user's home, course, log, and temporary paths.
3. Create the log directory and start a transcript before network retrieval.
4. Display the Prepare artifact version, version date-time group, platform, user, purpose, and log path.
5. Validate the operating-system family, required architecture, and standard-user context.
6. Download the authorized repository archive with bounded retries into a unique temporary location.
7. Extract and structurally validate the staged package, including the matching platform directory and every lifecycle entry point required by the resolved workflow.
8. Refresh only repository-managed package files while preserving user-owned content and nested repositories.
9. Remove only the downloaded package's top-level repository metadata.
10. Apply required script permissions and establish the platform script directory in the current and future user `PATH` without duplicates.
11. Resolve the workflow and report the course root, log path, workflow identifier, starting state, operating role, update mode when applicable, and exact next step.
12. Remove temporary data on success, failure, cancellation, or supported interruption.

#### 2.3.2 Managed Lifecycle Processing Pattern

Install, Configure, Verify, and Update follow this high-level processing pattern where applicable:

1. Initialize a minimal run context, artifact identity, and safe error handling.
2. Parse supported command-line options.
3. Create the standard log location and start the transcript.
4. Display the artifact version and version date-time group with the run context.
5. Detect the platform, current user, privilege state, paths, and available native facilities.
6. Locate, load, and validate the manifest.
7. Select the platform, capability, and provider adapters named by approved manifest identifiers.
8. Acquire an operation lock when the action may change shared state.
9. Run action-specific prerequisite checks.
10. Build an operation or check plan.
11. Execute the plan with stage-level results.
12. Run post-operation validation when the action changes state.
13. Determine restart guidance, remediation, summary totals, and final exit code.
14. When the result is nonzero or noncompliant, add profile-aware course-continuity guidance without replacing the specific remediation.
15. Remove temporary data, release locks, close the log, and exit.

### 2.4 Planned Design Artifacts

The following supporting artifacts shall describe the same design at different levels of detail:

| Artifact | Purpose |
| --- | --- |
| `it140_scripts_sdd.md` | Package architecture, interfaces, component design, version policy, and traceability |
| `architecture.drawio` | Editable component, data-flow, trust-boundary, and preparation-boundary diagram |
| `lifecycle.drawio` | Editable normal, refresh, and remediation lifecycle diagram |
| `prepare_it140.pseudo` | Platform-agnostic first-use and package-refresh control flow |
| `install_it140.pseudo` | Platform-agnostic system-installation and repair control flow |
| `configure_it140.pseudo` | Platform-agnostic user-configuration control flow |
| `verify_it140.pseudo` | Platform-agnostic verification control flow |
| `update_it140.pseudo` | Platform-agnostic maintenance control flow |
| `scripts/.manifest/it140_manifest.schema.json` | Machine-readable manifest structural contract |
| `scripts/.manifest/it140_manifest.json` | Controlled concrete product, version, source, platform, deployment-profile, desktop-integration, and maintenance-asset selections |
| Automated and manual test artifacts | Unit, integration, safety, idempotence, interruption, acceptance, and platform-conformance evidence |
| Release and maintenance records | Approved changes, compatibility effects, SemVer decisions, version date-time groups, and deployed baselines |

Every controlled artifact in this table has its own SemVer version and version date-time group. Generated test results and release records identify the versions and dates of the artifacts they evaluate. The diagrams and pseudoscripts are detailed design artifacts. This SDD remains authoritative when a supporting artifact is incomplete or inconsistent.

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
│   │   ├── prepare_it140.<ext>
│   │   ├── install_it140.<ext>
│   │   ├── configure_it140.<ext>
│   │   ├── verify_it140.<ext>
│   │   └── update_it140.<ext>
│   └── .dev/
│       ├── analysis/
│       ├── design/
│       ├── pseudoscripts/
│       └── tests/
└── README.md
```

The installed package may omit `.dev/` files unless they are intentionally distributed as course-managed documentation. Student-owned folders and repositories are never inferred from naming alone; only explicitly declared managed paths and repository-distribution paths are writable by automation. Prepare overlays validated repository-managed files but does not delete unrelated content already under the course root.

### 3.2 Entry Points and Shared Implementation

Each platform provides five entry points with two implementation profiles.

The `prepare_it140.<ext>` artifact is a self-contained platform-native command set. Its source file is both the documented first-use command sequence and the executable refresh artifact installed for later use. It embeds only the minimum constants and helpers needed for trusted archive retrieval, logging, staging, validation, package refresh, permissions, `PATH`, cleanup, and next-step output. It does not require the manifest, accept advanced lifecycle options, authenticate an external account, or load another course script.

The four managed entry points--Install, Configure, Verify, and Update--should contain only:

- Platform-native startup and strict-mode configuration.
- Artifact SemVer and version-date constants or metadata.
- Loading of approved platform-local modules or helper functions.
- Construction of the run context.
- Invocation of the corresponding orchestrator.
- Final cleanup and exit.

Shared implementation should be factored into small, purpose-specific platform-local modules where supported, implementing `PKG-NFR-013`. Important intent, safety boundaries, and non-obvious decisions shall be explained in comments rather than restating commands, implementing `PKG-NFR-014`. Automated tests shall cover manifest parsing, artifact-version validation, platform detection, managed paths, desktop integration, exit codes, redaction, and idempotence, implementing `PKG-NFR-016`.

The project shall not require one universal executable runtime before Install has established the course environment. Cross-platform consistency is achieved through this SDD, the five pseudoscripts, manifest schema, conformance tests, shared message catalog, and traceability--not by introducing an additional bootstrap dependency.

All source scripts and text configuration shall use UTF-8 encoding with Line Feed (LF) line endings under the repository's approved text-file policy. This design rule implements `PKG-TC-003`.

### 3.3 Shared Components

| Design ID | Component | Responsibility | Primary inputs | Primary outputs | Related SRS requirements |
| --- | --- | --- | --- | --- | --- |
| SHR-DES-001 | Run-context builder | Capture action, artifact SemVer, version date-time group, platform, user, times, paths, and manifest release for one run. | Entry-point metadata and detected environment | `RunContext` | PKG-FR-006, PKG-NFR-015, PKG-QOS-017 |
| SHR-DES-002 | Output service | Produce consistent stage headings, status labels, prompts, summaries, profile-aware course-continuity guidance, and plain-text fallbacks. | Message key, severity, values | Terminal and log messages | PKG-FR-008, PKG-FR-021, PKG-NFR-001 through PKG-NFR-011 |
| SHR-DES-003 | Transcript service | Create a unique timestamped UTF-8 log in the approved course log directory and write terminal output without losing the original exit result. | Run context and output stream | Log file | PKG-FR-007, PKG-TC-005, PKG-QOS-013, PKG-QOS-016 through PKG-QOS-020 |
| SHR-DES-004 | Manifest loader | Locate and read the controlled manifest as data. | Manifest path | Raw manifest object | PKG-FR-004, PKG-FR-011 |
| SHR-DES-005 | Manifest validator | Perform schema, semantic, relationship, version, compatibility, path, and integrity checks before use. | Raw manifest and schema | Validated immutable configuration or failure | PKG-FR-005, PKG-FR-019, PKG-TC-004 |
| SHR-DES-006 | Platform detector | Identify platform type, operating-system release, architecture, session type, current user, home path, desktop path, and privilege facilities. | Native environment | `PlatformFacts` | PKG-FR-003, PRE-FR-004, INS-FR-001, VER-FR-004, UPD-FR-001 |
| SHR-DES-007 | Adapter registry | Resolve allowlisted platform, capability, package-manager, desktop, and provider adapters from manifest identifiers. | Validated adapter IDs | Adapter objects or unsupported result | PKG-TC-008, REF-TC-001 through REF-TC-007 |
| SHR-DES-008 | Command runner | Execute reviewed commands with argument separation, captured status, bounded output handling, and optional privilege elevation for one command. | Executable, argument list, privilege policy | `OperationResult` | PKG-NFR-022 through PKG-NFR-024, PKG-QOS-012 |
| SHR-DES-009 | Path safety service | Expand approved variables, canonicalize paths, enforce managed boundaries, and reject traversal or protected targets. | Path template and run context | Validated canonical path | PKG-FR-020, PRE-FR-005, PRE-FR-009, PKG-NFR-019, PKG-NFR-020, PKG-NFR-023 |
| SHR-DES-010 | Lock manager | Prevent overlapping operations that could modify the same package-manager or managed-file state. | Action and lock scope | Acquired lock or conflict result | UPD-FR-002, PKG-QOS-005 |
| SHR-DES-011 | Staging and replacement service | Create private temporary locations, validate candidate assets, preserve prior valid copies, and activate with atomic replacement. | Asset metadata and downloaded file | Activated asset or rollback result | PRE-FR-007 through PRE-FR-014, UPD-FR-004, UPD-FR-005, PKG-QOS-003, PKG-QOS-004 |
| SHR-DES-012 | Result aggregator | Collect stage results, warnings, failures, restart needs, remediation, course-continuity status, counts, and deterministic final exit code. | `OperationResult` and `CheckResult` objects | `RunSummary` | PKG-FR-008, PKG-FR-009, PKG-FR-021, VER-FR-011, VER-FR-012, PKG-QOS-014, PKG-QOS-015 |
| SHR-DES-013 | Redaction service | Remove secrets and unnecessary PII from messages, logs, and support files using field-aware and pattern-based rules. | Candidate diagnostic text and structured fields | Sanitized output | VER-FR-007, VER-FR-013, PKG-NFR-025 |
| SHR-DES-014 | Retry service | Apply bounded retries with delay and clear progress for approved temporary external failures. | Retry policy and operation callback | Final operation result and attempt history | PRE-FR-007, UPD-FR-012, PKG-QOS-008 |
| SHR-DES-015 | Settings merger | Read, validate, merge, and safely write only approved settings while preserving unrelated valid content. | Existing settings and managed settings | Updated settings or unchanged result | CFG-FR-009, CFG-FR-011, CFG-FR-016 |
| SHR-DES-016 | Restart detector | Identify application, sign-out, session, virtual-machine, or computer restart needs without performing an unsafe restart. | Platform facts and update results | Restart guidance | UPD-FR-014, REF-TC-004 |
| SHR-DES-017 | Artifact identity service | Validate strict SemVer and `YYYY-MM-DD` values, render version output, and attach governing artifact identities to logs, tests, and support inventories. | Artifact metadata | `ArtifactIdentity` or validation failure | PKG-FR-006, PKG-NFR-015, VER-FR-003 |
| SHR-DES-018 | Desktop integration service | Create, query, and validate the repository-workspace desktop link, platform development marker, profile-owned IDE workspace launcher, and supported file associations without changing unrelated desktop preferences or nested repository content. | Validated integration definitions and platform paths | Integration results and probes | CFG-FR-013 through CFG-FR-021, VER-FR-006, VER-FR-015 through VER-FR-018 |

### 3.4 Responsibility Boundary Rules

- Prepare may retrieve or refresh repository-managed package files, write its own log, set required script permissions, and establish the platform script directory in the user's `PATH`. It shall not install course IDE software, use the manifest as a prerequisite, authenticate external services, or configure IDE settings.
- Install may create its own log under the invoking user's course log folder, but it shall not perform personal account authentication or user-preference configuration.
- Configure shall not install or change system-wide components. If system prerequisites are missing, it directs the user to Install.
- Verify shall not call a mutating adapter method. The verify orchestrator receives read-only adapter interfaces.
- Update may change system and user-managed maintenance state, but only through manifest-declared capability roles, managed settings, and managed paths. It shall not refresh lifecycle script source files; that responsibility belongs to Prepare.
- Desktop integration writes are limited to the repository-workspace parent metadata, the course-created `Repos` desktop link or shortcut, the CVD course-owned IDE launcher workspace argument, and explicitly declared file-association settings. They never recurse into repository-workspace children.
- Shared services may be reused by the four managed scripts, but they shall not silently broaden the authority of the calling script. Prepare may implement equivalent minimal helpers locally because shared modules cannot be assumed present on first use.

## 4. Data Design

### 4.1 Manifest Design Principles

The manifest is a controlled configuration item, not a program. It contains declarative data that selects reviewed behavior. The schema and code jointly prevent it from becoming an unreviewed command-execution channel.

| Design ID | Manifest design rule | Purpose | Related SRS requirements |
| --- | --- | --- | --- |
| DAT-DES-001 | The root object contains artifact identity, release control, policy, capabilities, products, sources, provider profiles, platforms, optional deployment profiles, managed settings, desktop integrations, managed assets, obsolete components, and logging data. | Provides a predictable top-level contract while separating stable platform bindings from concrete deployment environments. | PKG-FR-011 through PKG-FR-017, PKG-NFR-015 |
| DAT-DES-002 | `schema_version` uses strict SemVer and a documented compatibility policy separate from the automation release. The schema artifact also has its own version date-time group. | Allows scripts to reject a manifest structure they cannot interpret and identify the governing schema precisely. | PKG-FR-012, PKG-FR-019, PKG-NFR-015 |
| DAT-DES-003 | Capability definitions use stable role identifiers rather than product names in script logic. | Allows an approved product to change without changing lifecycle logic. | PKG-TC-008, PKG-NFR-012 |
| DAT-DES-004 | Platform entries bind capability roles to concrete package identifiers, commands, version probes, sources, settings, and adapter IDs. | Keeps product-specific data in one controlled location and enforces the no-additional-fee selection constraint. | PKG-FR-013, PKG-FR-014, PKG-FR-015, PKG-FR-016, PKG-TC-002 |
| DAT-DES-005 | Provider profiles identify an allowlisted provider adapter and validated authentication, account-field, and privacy-identity parameters. | Supports provider-specific behavior without hardcoding it throughout Configure and Verify. | CFG-FR-005 through CFG-FR-008, VER-FR-006 |
| DAT-DES-006 | Manifest values may select only adapter identifiers compiled into or distributed with the approved package release. | Prevents arbitrary manifest data from becoming executable code. | PKG-NFR-023, PKG-NFR-024 |
| DAT-DES-007 | Managed assets include ownership scope, source, destination, integrity data, replacement mode, artifact identity, and optional obsolete-state metadata. | Defines exactly what Update may replace or remove. | UPD-FR-003 through UPD-FR-005, UPD-FR-010, PKG-FR-017, PKG-FR-020 |
| DAT-DES-008 | Managed settings identify the target file or interface, allowed keys, desired values, merge policy, and validation method. | Prevents whole-file replacement when only selected settings are owned. | CFG-FR-009, CFG-FR-011, CFG-FR-014, CFG-FR-016 |
| DAT-DES-009 | Paths are expressed with approved variables such as `${HOME}`, `${DESKTOP}`, `${COURSE_ROOT}`, and `${TEMP}` rather than fixed usernames. | Supports different users and platforms. | CFG-FR-012, PKG-NFR-019, PKG-TC-009, REF-TC-005 |
| DAT-DES-010 | Product version rules use an explicit comparison scheme per capability, such as exact, minimum, compatible range, or presence-only. Artifact identities use strict SemVer without substituting product-version comparison schemes. | Makes install, update, and verify decisions consistent while preserving strict artifact release control. | INS-FR-008, VER-FR-005, PKG-TC-007, PKG-NFR-015 |
| DAT-DES-011 | Required and optional items are represented explicitly and are never inferred from missing fields. | Keeps optional features from causing required failures. | VER-FR-010, PKG-NFR-005 |
| DAT-DES-012 | Retry limits, timeouts, and performance settings are bounded by schema validation and safe code-defined maximums. | Allows controlled tuning without indefinite waits or excessive load. | PRE-FR-007, UPD-FR-012, PKG-QOS-007 through PKG-QOS-010 |
| DAT-DES-013 | Secrets, personal values, and runtime authentication data are prohibited in the manifest schema and semantic validator. | Keeps the public controlled file safe to distribute. | PKG-FR-018, PKG-NFR-025 |
| DAT-DES-014 | A manifest release is approved only with its schema validation, platform conformance tests, integrity metadata, SemVer decision, version date-time group, and release record. | Treats product selection as controlled engineering data. | PKG-FR-019, PKG-NFR-015, Appendix B of the SRS |
| DAT-DES-015 | Deployment profiles reference a platform implementation and record deployment kind, provider, desktop, session, release, architecture, reset method, reference status, and allowed workflow identifiers. | Distinguishes hosted, local, and test deployments without duplicating course IDE product bindings. | REF-TC-001 through REF-TC-006, PKG-FR-022, Section 3.3 of the SRS |
| DAT-DES-018 | A top-level workflow catalog defines each workflow identifier, deployment-profile applicability, operating role, starting-state identifier, ordered actions, update mode, and exact success transitions. | Keeps lifecycle sequencing declarative and testable without allowing arbitrary commands in the manifest. | PKG-FR-022, PKG-FR-023, PRE-FR-013 |
| DAT-DES-016 | Every controlled manifest, schema, design, construction, test, release, and maintenance record stores or is associated with an `ArtifactIdentity` containing artifact ID, SemVer, and version date-time group. | Supports exact traceability without requiring unrelated artifact versions to match. | PKG-NFR-015 |
| DAT-DES-017 | Desktop integrations separately declare the repository-workspace target, desktop-link name, development-marker adapter, any profile-owned IDE executable role and workspace argument, ownership scope, and validation probe. | Makes the student development workspace portable and testable without hardcoding one desktop command while preserving platform-specific marker limitations. | CFG-FR-013 through CFG-FR-021, VER-FR-006, VER-FR-015 through VER-FR-018 |

### 4.2 Illustrative Logical Manifest Structure

The following example is informative. Field names may be refined when the JSON schema is constructed, but the separation of responsibilities shall remain.

```json
{
  "artifact": {
    "id": "IT140-MANIFEST",
    "version": "0.2.0",
    "version_date_time_group": "2026-07-31-12-00"
  },
  "schema": {
    "version": "0.2.0",
    "version_date_time_group": "2026-07-31-12-00"
  },
  "automation_release": {
    "version": "0.2.0",
    "version_date_time_group": "2026-07-31-12-00"
  },
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
      "desktop_adapter_id": "approved-desktop-adapter",
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
  "desktop_integrations": {
    "course_root_shortcut": {
      "target": "${COURSE_ROOT}",
      "open_with": "platform_file_manager"
    },
    "ide_course_root_launcher": {
      "capability_role": "source_code_ide",
      "folder_argument": "${COURSE_ROOT}",
      "default_folder_when_supported": "${COURSE_ROOT}"
    }
  },
  "managed_assets": [],
  "logging": {
    "format_version": "1.0.0",
    "retention_policy_id": "course-default"
  }
}
```

### 4.3 Validation Layers

Manifest validation occurs in this order:

1. **File validation**: path exists, file is readable, expected encoding is used, and size is within a safe limit.
2. **Syntax validation**: content parses as JSON without duplicate-key ambiguity.
3. **Schema validation**: required fields, types, enumerations, patterns, and ranges are correct.
4. **Artifact-identity validation**: required artifact versions are strict SemVer, version date-time groups are valid `YYYY-MM-DD-HH-MM` values, and compatibility declarations are internally consistent.
5. **Semantic validation**: identifiers are unique; required capability roles have bindings; product versions, sources, and desktop integration definitions are meaningful.
6. **Relationship validation**: referenced adapters, provider profiles, platforms, assets, integrations, and policies exist and are compatible.
7. **Path validation**: expanded managed paths remain within approved boundaries and do not target protected or user-owned locations.
8. **Integrity and trust validation**: the manifest release and managed-asset metadata are obtained through the approved trust chain.
9. **Compatibility validation**: the running script supports the manifest schema, automation release, and selected adapter interface versions.

No mutating managed action begins until all validation layers required by that action pass. Prepare does not load the manifest; it validates its own embedded artifact identity and the staged repository structure before refreshing package files.

### 4.4 Runtime Data Structures

The names below describe logical structures. Native implementations may use records, dictionaries, associative arrays, objects, or equivalent structures.

| Data structure | Required fields | Purpose |
| --- | --- | --- |
| `ArtifactIdentity` | artifact ID, strict SemVer, version date-time group, development or release status, optional compatibility range | Identifies one controlled artifact independently of other artifacts. |
| `RunContext` | action, artifact identity, platform ID, user ID, paths, start time, manifest identity, interactivity | Provides common context to every component. |
| `PlatformFacts` | OS type and release, architecture, session type, home path, desktop path, temporary path, privilege capability | Supports platform matching and prerequisite checks. |
| `DeploymentProfile` | platform identifier, deployment kind, provider, desktop environment, session type, release, architecture, reset method, and reference flag | Selects environment-specific behavior and testing evidence without duplicating product bindings. |
| `CapabilityBinding` | role ID, product ID, adapter ID, required status, package identifiers, product-version rule, probes | Connects a generic capability to the current approved implementation. |
| `ProviderProfile` | adapter ID, authentication method, account fields, identity rule, validation rules | Controls approved external-service integration. |
| `DesktopIntegration` | integration ID, workspace target path, desktop-link name, marker adapter, application role when applicable, launch arguments, ownership scope, query probe | Defines the repository-workspace desktop integration and any profile-owned IDE workspace launch behavior. |
| `ManagedAsset` | asset ID, artifact identity, source, destination, scope, integrity, replacement policy, obsolete policy | Authorizes managed-file synchronization. |
| `OperationResult` | operation ID, status, changed flag, message key, diagnostic details, remediation, restart flag | Represents one mutating or query operation. |
| `CheckResult` | check ID, SRS ID, status, observed value, expected rule, remediation owner, sanitized detail | Represents one verification result. |
| `RunSummary` | artifact identities, counts, changed items, warnings, failures, restart guidance, next step, profile-aware course-continuity guidance when required, final exit code | Produces consistent terminal and log summaries. |

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
2026-07-31T12:00:00-07:00 [INFO] [run.identity] Script version 0.2.0; version date-time group 2026-07-31-12-00.
2026-07-31T12:00:01-07:00 [INFO] [manifest.validate] Manifest version 0.2.0; version date-time group 2026-07-31-12-00.
2026-07-31T12:00:02-07:00 [PASS] [platform.release] Detected platform release is supported.
2026-07-31T12:00:03-07:00 [FAIL] [capability.quality_tool] Required capability is not available.
```

The transcript service records:

- Producing script artifact ID, SemVer, and version date-time group.
- Package, manifest, and schema artifact identities when applicable.
- Test-definition or support-inventory identity when the log is generated by testing or support tooling.
- Detected platform and architecture.
- A nonsecret current-user identifier.
- Start, end, and elapsed times.
- Major stages and operation identifiers.
- Sanitized observed and expected values.
- Changes, warnings, failures, remediation, restart guidance, and exit code.

Prepare starts its transcript before network retrieval and records its embedded artifact version and version date-time group even when the package cannot be downloaded. Logs do not record passwords, tokens, private keys, browser data, complete personal email addresses, or student source files.

### 4.7 Support-Bundle Design

When explicitly requested, Verify creates a temporary bundle containing only approved diagnostics, such as:

- Sanitized verification log.
- Bundle-inventory artifact ID, SemVer, and version date-time group.
- SRS, SDD, script, manifest, schema, and test-definition artifact identities relevant to the result.
- Supported platform facts.
- Required capability product-version results.
- Managed-path and desktop-integration permission results.
- Sanitized selected configuration values.
- A bundle inventory describing every included file.

The bundle excludes assignment repositories, source files, version-control history, authentication stores, browser profiles, and unrelated settings. The user sees the proposed inventory before final creation.

## 5. Interface and Input/Output Design

### 5.1 Command-Line Interface

| Design ID | Interface rule | Planned behavior | Related SRS requirements |
| --- | --- | --- | --- |
| INT-DES-001 | First-use Prepare requires no installed course command. | The documented platform-native `prepare_it140.<ext>` content can be copied and run directly; after installation, the same artifact can be executed by name or approved path to refresh the package. | PRE-FR-001, PRE-FR-002, PRE-FR-003 |
| INT-DES-002 | Managed lifecycle invocation requires no advanced arguments. | Running Install, Configure, Verify, or Update by its installed name starts the normal student- or administrator-facing workflow. | PKG-NFR-002, PKG-NFR-010 |
| INT-DES-003 | Managed scripts support help; Prepare remains minimal. | Help explains purpose, intended user, prerequisites, common invocation, log location, and exit-code meanings without changing state. Prepare instead uses embedded comments, opening output, and exact next-step output because it must remain copyable and dependency-free. | PKG-FR-006, PRE-FR-003, PKG-NFR-003 |
| INT-DES-004 | Every artifact exposes its version identity. | Managed scripts provide a local version operation; Prepare displays and logs its embedded SemVer and version date-time group during every run. No external service is required to obtain version identity. | PKG-FR-006, PRE-FR-006, PKG-NFR-015, PKG-QOS-017 |
| INT-DES-005 | Interactive prompts are used only when user choice or external authentication is required. | The script explains the action, available choices, default, cancellation method, and effect before reading input. | CFG-FR-006, PKG-NFR-007 |
| INT-DES-006 | Noninteractive execution fails safely when required interaction cannot be completed. | Automated or managed runs receive a clear result rather than waiting indefinitely for input. | PKG-QOS-003, PKG-QOS-011 |
| INT-DES-007 | Verify alone may expose a support-bundle option. | The option requests bundle preparation; final creation still displays the approved inventory and obtains explicit confirmation when interactive. | VER-FR-013, PKG-QOS-021 |
| INT-DES-008 | Unsupported options cause no managed change. | The script prints help-oriented guidance and returns the invalid-use exit code. | PKG-QOS-014 |
| INT-DES-009 | Prompts accept documented values case-insensitively where practical. | Blank input uses a clearly displayed safe default; invalid input is explained and reprompted within a bounded loop. | PKG-NFR-007, PKG-NFR-009 |
| INT-DES-010 | Student-facing output uses consistent status labels. | `INFO`, `SUCCESS`, `NOTICE`, `WARNING`, and `ERROR` appear as text and do not rely on color. | PKG-NFR-008, PKG-QOS-019 |
| INT-DES-011 | Progress reflects completed stages or underlying tool output. | Timed animations are not used as progress measurements. A truthful heartbeat appears during long silent operations. | PKG-NFR-009, PKG-QOS-008 |
| INT-DES-012 | Remediation commands are rendered from detected platform metadata. | Commands use the installed action name and tell the user where to run them. | PRE-FR-013, VER-FR-009, PKG-NFR-010 |
| INT-DES-013 | The final summary is always attempted for managed scripts. | The summary shows result, changes, warnings, failures, restart guidance, next step, log path, and exit code, even after a handled failure. Prepare provides a smaller success or failure conclusion with the log path and the exact next step resolved from the approved lifecycle workflow; local initialization selects Install, while both CVD initialization workflows select Update. | PKG-FR-008, PRE-FR-013, PRE-FR-014, PKG-QOS-012, PKG-QOS-020 |
| INT-DES-014 | Every unsuccessful managed lifecycle conclusion preserves course continuity. | When a run ends nonzero or noncompliant, the output and transcript add profile-aware guidance. For a local or unconfirmed profile, display: `Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.` For a CVD profile, display: `Course continuity: This issue affects the Codio Virtual Desktop (CVD). Follow the remediation above. If the issue continues, contact course support and include the log file.` The guidance never replaces the problem-specific remediation or exact log path. | PKG-FR-021 |

### 5.2 Common Opening Output

Each normal run displays the following fields near the beginning:

- Package and action name.
- Artifact SemVer.
- Artifact version date-time group.
- Manifest release and release date after validation, except Prepare because the manifest is not a prerequisite.
- Detected platform and operating-system release when available.
- Current user identifier.
- Purpose and expected scope of changes.
- Log path.
- Important warnings, including whether privilege elevation or interaction may occur.

Prepare displays and logs its identity before network retrieval so failures can be associated with the exact bootstrap artifact.

### 5.3 External Interface Contracts

| Interface | Stable package operation | Adapter responsibility | Failure behavior |
| --- | --- | --- | --- |
| Authorized repository archive | Retrieve the current package for first use or refresh. | Prepare uses the embedded approved source, encrypted transport, bounded retries, unique staging, and structural validation. | Existing package remains unchanged when retrieval, extraction, or structure validation fails. |
| Operating system | Detect release, architecture, users, paths, permissions, session, and restart needs. | Translate native information into `PlatformFacts`. | Unsupported or unreadable facts stop unsafe actions. |
| System package manager | Refresh metadata, query, install, update, repair, remove approved obsolete packages, validate consistency. | Use native package operations and approved sources. | Return structured result; never parse only localized success text when an exit status or structured query exists. |
| Programming runtime | Locate executable, report version, manage required user tools when designed. | Apply role binding and product-version rule. | Missing system runtime is owned by Install; missing user tool is owned by Configure or Update. |
| Source-code editor or IDE | Locate CLI, report version, manage approved extensions or plug-ins, merge approved settings, and launch a declared folder or workspace. | Use manifest-selected capability adapter. | Preserve optional extensions and unrelated settings; invalid course-root launch behavior maps to Configure. |
| Version-control client | Query version and apply approved user settings. | Use managed keys only. | Never alter repositories or history. |
| Source-code hosting provider | Check authentication, start approved flow, query account fields, derive privacy identity. | Use allowlisted provider adapter and provider profile. | Cancellation, provider unavailability, and invalid identity data produce distinct results. |
| Managed-asset source | Retrieve manifest and maintenance-scope assets. | Update uses encrypted transport and integrity validation; lifecycle script refresh remains Prepare's responsibility. | Candidate data remains staged; installed valid data is preserved on failure. |
| Desktop or session environment | Create and query the repository-workspace desktop link, development visual marker, profile-owned IDE workspace launcher where required, and file associations; detect restart needs. | Apply only declared integrations, preserve unrelated desktop preferences, and never traverse workspace children. | Missing required workspace integrations are Configure-owned failures; a visual marker explicitly unsupported by the qualified platform is `NOT APPLICABLE`. |

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

This flow applies to Install, Configure, Verify, and Update. Prepare uses the specialized flow in Section 7 because the package and manifest may not exist.

```text
BEGIN managed action
    initialize strict error handling
    parse supported options
    validate embedded artifact identity
    build minimal run context
    create log directory and transcript
    display opening information, version, and version date-time group

    detect platform and user context
    IF action-platform mismatch OR unsupported platform
        record unsupported result
        summarize and exit
    ENDIF

    load manifest and schema
    validate syntax, structure, artifact identities, semantics, paths, trust, and compatibility
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
    IF resolved exit code is nonzero OR result is noncompliant
        display and log profile-aware course-continuity guidance
    ENDIF
    close transcript
    return resolved exit code
END managed action
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

Prepare, Install, Configure, and Update follow a **query-plan-apply-verify** principle adapted to their ownership boundaries:

1. Query or stage the current and desired state using a stable probe.
2. Compare the observed state with the approved rule or validated package contents.
3. Plan only the changes required to reach compliance.
4. Apply the smallest approved change.
5. Query again or validate the result.

Prepare never deletes the course root before refreshing it. It validates the archive before overlaying repository-managed files, preserves unrelated files and nested repositories, removes only top-level downloaded repository metadata, and avoids duplicate `PATH` entries. Install and Configure do not reinstall or rewrite a compliant component merely because the script is rerun. Settings mergers compare managed keys, package adapters query installed state, desktop integration probes validate exact shortcut targets and IDE launch arguments, and managed assets compare validated release or integrity data.

## 6.8 Workflow Resolver Design

The workflow resolver accepts only schema-valid identifiers from the controlled workflow catalog. Its inputs are the deployment profile, an explicit or safely detected starting-state identifier, and an operating role authorized by that profile. It returns the workflow identifier, ordered actions, current action index, update mode when the current action is Update, and exact next action. Ambiguous or unauthorized combinations fail safely and require an explicit approved selection; they never default a CVD student into Install.

The CVD implementation recognizes:

- `cvd_provider_baseline_administrator`: `prepare`, `update`, `install`, `configure`, `verify`; Update mode `initial_provider_baseline`.
- `cvd_course_master_student`: `prepare`, `update`, `configure`, `verify`; Update mode `initial_course_master`.
- `cvd_periodic_maintenance`: `update`, with Verify recommended when required; Update mode `periodic_maintenance`.

Local deployment profiles retain `local_initial_install`: `prepare`, `install`, `configure`, `verify`, followed by periodic Update.

## 7. Prepare Script Design

Prepare is the package bootstrap and refresh boundary. On first use, its source is presented as a short platform-native command set that the user copies and runs. After first use, the same artifact is present under the platform script directory and may be executed directly to refresh the package. Prepare is intentionally self-contained and does not require the manifest, another lifecycle script, a third-party package manager, or a version-control client.

| Design ID | Planned Prepare behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| PRE-DES-001 | Represent the complete first-use command set in `prepare_it140.<ext>` so it can be copied and run before `~/it140/` exists. | Platform-native shell or PowerShell | PRE-FR-001 |
| PRE-DES-002 | Install the Prepare artifact with the package and permit direct reruns to refresh repository-managed package files. | Package refresh logic | PRE-FR-002 |
| PRE-DES-003 | Use only baseline platform-native facilities and embedded constants; do not load the manifest, package manager, version-control client, or another lifecycle script. | Native retrieval and archive tools | PRE-FR-003 |
| PRE-DES-004 | Validate the OS family, required architecture, and standard-user context before replacing local package files. | Minimal native platform probes | PRE-FR-004 |
| PRE-DES-005 | Derive home paths, create the course and log roots, and allocate a unique private staging directory without removing existing course-root content. | Native path and temporary-directory facilities | PRE-FR-005 |
| PRE-DES-006 | Start a timestamped transcript before retrieval and record the Prepare artifact SemVer, version date-time group, user, purpose, and log path. | Minimal local transcript helper | PRE-FR-006 |
| PRE-DES-007 | Retrieve the authorized repository archive over encrypted transport with bounded attempts into a unique partial or temporary file. | Native HTTPS client, retry loop | PRE-FR-007 |
| PRE-DES-008 | Extract into staging and require the expected platform directory plus every lifecycle entry point required by the resolved workflow before package refresh begins. | Native archive tool, structural validator | PRE-FR-008 |
| PRE-DES-009 | Overlay only repository-managed source files into the course root while preserving unrelated files, assignment content, and nested repositories. | Package refresh copier, path boundary rules | PRE-FR-009 |
| PRE-DES-010 | Remove only top-level repository metadata copied from the downloaded package; never recursively search for and delete nested version-control metadata. | Exact-path deletion helper | PRE-FR-010 |
| PRE-DES-011 | Apply required executable permissions and prepend or add the platform script directory to the current and future user `PATH` idempotently. | Native permission and user-environment interfaces | PRE-FR-011 |
| PRE-DES-012 | Register cleanup before retrieval and remove only the unique staging archive and extraction tree on normal exit, handled failure, cancellation, or supported interruption. | Native trap, `finally`, or cleanup handler | PRE-FR-012 |
| PRE-DES-013 | On success, print the installed course root, exact log path, resolved workflow identifier, starting state, operating role, and exact platform-specific next-step command. Local initialization selects Install; both CVD initialization workflows select Update. | Minimal output helper and bounded workflow resolver | PRE-FR-013, PKG-FR-022 |
| PRE-DES-014 | Complete download, extraction, and structural validation before touching existing package files; on pre-refresh failure, leave the prior package unchanged and return nonzero. | Staging validator, error handler | PRE-FR-014 |
| PRE-DES-015 | Enforce an explicit authority allowlist limited to package retrieval or refresh, logging, script permissions, and user `PATH`. | Prepare boundary checks | PRE-FR-015 |

### 7.1 First-Use and Refresh Control Flow

```text
initialize strict native error handling
validate embedded SemVer and version date-time group constants
resolve home, course, log, and unique temporary paths
create log directory and start transcript
register cleanup handler
display artifact identity, user, purpose, and log path

validate supported platform, architecture, and standard-user context
IF validation fails
    explain the condition and exit nonzero
ENDIF

retrieve authorized repository archive with bounded retries
extract archive into unique staging directory
locate staged repository root
resolve bounded workflow context
validate matching platform directory and all workflow-required entry points
IF any staging validation fails
    preserve current package and exit nonzero
ENDIF

overlay repository-managed files into course root
remove only course-root top-level downloaded repository metadata
apply script permissions
establish current-session and persistent user PATH entry without duplicates
report course root, log path, workflow context, and exact resolved next step
cleanup unique temporary data
exit success
```

### 7.2 Package Refresh Safety

Prepare treats the course root as a mixed-ownership tree:

- Repository-managed top-level files and package directories may be created or replaced from the validated staged archive.
- Existing files that are absent from the staged repository are not deleted merely because Prepare is rerun.
- Student assignment folders, nested repositories, source files, and unrelated user content are outside the Prepare deletion authority.
- The exact top-level `.git` metadata path copied from the main repository may be removed; nested `.git` paths are never discovered or removed through recursive matching.
- Download, extraction, and structural validation occur before any package refresh write.
- Platform implementations should use per-file staging and atomic replacement where native facilities make that practical, but shall not add a dependency that prevents first use.

### 7.3 Prepare Platform Profile

A platform-specific Prepare implementation or supplement records:

- The native HTTPS retrieval utility and retry options.
- The native archive extraction utility.
- Supported OS-family and architecture probes.
- Standard-user or root-context rejection rules.
- User `PATH` persistence interface.
- Script permission requirements.
- Cleanup signal or exception handling.
- The exact platform-specific Install next-step command.

These differences may change commands but shall not change the PRE-DES behavior or the SRS acceptance criteria.

## 8. Install Script Design

The Install orchestrator owns the shared system layer. It may use controlled privilege elevation for specific commands but is not run wholesale with elevated authority unless a platform design proves that unavoidable and receives approval.

| Design ID | Planned Install behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| INS-DES-001 | Gather and evaluate the approved OS release, architecture, disk space, network reachability, and privilege capability before planning installation. | Platform detector, manifest validator | INS-FR-001 |
| INS-DES-002 | Stop before system mutation when the platform or privilege model is unsupported; preserve the diagnostic log when possible. | Result aggregator, output service | INS-FR-002 |
| INS-DES-003 | Build a system capability plan from required manifest roles and system package bindings. | Adapter registry, package adapter | INS-FR-003 |
| INS-DES-004 | Accept install sources only from validated manifest bindings and native trusted repositories. | Manifest validator, trust service | INS-FR-004 |
| INS-DES-005 | Configure prerequisite repositories, trust keys, certificates, or registrations through reviewed adapter methods before dependent installation. | Platform and package adapters | INS-FR-005 |
| INS-DES-006 | Apply the approved package baseline within the current OS release; release-upgrade operations are excluded from the adapter interface. | Package adapter | INS-FR-006 |
| INS-DES-007 | Install or repair manifest-declared system integrations through system-scope adapter operations. | Platform adapter | INS-FR-007 |
| INS-DES-008 | Probe every required system capability and product version after installation before declaring Install successful. | Capability adapters, result aggregator | INS-FR-008 |
| INS-DES-009 | Query before applying and compare after applying so reruns do not duplicate repositories, registrations, policies, or packages. | Package adapter, settings service | INS-FR-009 |
| INS-DES-010 | Treat a missing managed system component as a repair plan item while leaving unrelated system configuration untouched. | Managed-boundary service | INS-FR-010 |
| INS-DES-011 | Exclude provider authentication, personal identity, user-scoped tools, user settings, and user launchers from the Install plan. | Orchestrator boundary checks | INS-FR-011 |
| INS-DES-012 | On successful post-validation, render the matching `configure_it140.<ext>` command as the next step. | Output service, platform metadata | INS-FR-012 |

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
recommend Configure when successful
```

### 8.2 Install Privilege Design

The command runner receives a privilege policy per operation:

- `none`: command must run as the standard user.
- `elevate_one_command`: only the specific command is elevated.
- `administrator_context_required`: permitted only by an approved platform-specific design exception.

Arguments are passed as separate values rather than assembled into an unvalidated command string. Install refuses to save user-specific files under an administrator's home directory accidentally.

## 9. Configure Script Design

The Configure orchestrator owns the current user's course environment. It runs as the student or faculty account and does not make system-wide changes.

| Design ID | Planned Configure behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| CFG-DES-001 | Confirm the script is running as the intended standard user and reject an unintended system-administrator context. | Platform detector | CFG-FR-001 |
| CFG-DES-002 | Probe required system capabilities before writing user configuration; missing system prerequisites map to Install remediation. | Capability adapters, result aggregator | CFG-FR-002 |
| CFG-DES-003 | Create missing approved course folders with safe permissions while preserving all existing contents. | Path safety and file services | CFG-FR-003 |
| CFG-DES-004 | Add the approved platform script directory to the user's executable search path through an idempotent managed entry. | Settings merger | CFG-FR-004 |
| CFG-DES-005 | Query provider authentication through the selected provider adapter and start the approved interactive flow only when required. | Provider adapter | CFG-FR-005 |
| CFG-DES-006 | Explain authentication steps, choices, browser or device interaction, expected delay, and cancellation before starting the provider flow. | Output service | CFG-FR-006 |
| CFG-DES-007 | Request only approved provider account fields and apply the provider profile's privacy-preserving commit-identity rule. | Provider adapter, redaction service | CFG-FR-007 |
| CFG-DES-008 | Present the provider user name as the default version-control display name while permitting a validated professional alternative. | Input validator, settings merger | CFG-FR-008 |
| CFG-DES-009 | Apply only manifest-declared version-control settings and use the manifest-selected IDE role where an editor setting is required. | Settings merger, role binding | CFG-FR-009 |
| CFG-DES-010 | Install or repair required user-scoped programming tools and IDE extensions or plug-ins through capability adapters. | Runtime and IDE adapters | CFG-FR-010 |
| CFG-DES-011 | Parse and validate existing IDE settings, merge only managed keys, preserve unrelated valid settings, and write atomically. | Settings merger, staging service | CFG-FR-011 |
| CFG-DES-012 | Resolve all user paths from the run context and approved variables; reject fixed-user paths in manifest data. | Path safety service | CFG-FR-012 |
| CFG-DES-013 | Preserve an existing course-root integration unless it is explicitly obsolete and automation-managed; new student navigation uses the repository-workspace integration. | Desktop integration service, ownership probe | CFG-FR-013 |
| CFG-DES-014 | Configure approved IDE settings without making the course automation root the student's default development workspace; defer profile-owned launch targets to the repository-workspace contract. | IDE adapter, settings merger | CFG-FR-014 |
| CFG-DES-015 | Query provider status, version-control settings, runtime tools, IDE settings, extensions, course folders, repository workspace, desktop integration, and profile-owned IDE workspace launch behavior before success. | Capability adapters, desktop integration probes | CFG-FR-015 |
| CFG-DES-016 | Use managed-key merging and query-plan-apply-verify behavior so reruns repair managed integrations while preserving optional extensions and unrelated preferences. | Settings merger, adapters | CFG-FR-016 |
| CFG-DES-017 | Render the matching `verify_it140.<ext>` command after successful configuration. | Output service, platform metadata | CFG-FR-017 |
| CFG-DES-018 | Ensure the repository-workspace parent exists at the native `${HOME}/Repos` equivalent. Create only the parent when absent; never enumerate or mutate child repositories as part of configuration. | Path safety service, file service | CFG-FR-018 |
| CFG-DES-019 | Create or repair the desktop item named `Repos` so it resolves exactly to the repository workspace. Preserve and report any conflicting unmanaged item rather than replacing it. | Desktop integration service, ownership probe | CFG-FR-019 |
| CFG-DES-020 | Apply the qualified platform's repository-workspace visual treatment. CVD uses native `development` emblem metadata; Windows retains the normal Windows folder appearance and removes only stale course-managed application-icon metadata; Ubuntu GNOME uses safe native development metadata when supported; macOS reports the visual-only integration `NOT APPLICABLE`. | Platform desktop adapter | CFG-FR-020 |
| CFG-DES-021 | Configure profile-owned Visual Studio Code desktop launch behavior. CVD repairs the existing course-provided launcher and fails rather than creating a duplicate when it is missing. Windows bare metal creates or repairs the course-owned `Visual Studio Code - IT 140` shortcut so its executable, repository-workspace folder argument, and working directory are correct while preserving unrelated VS Code shortcuts. | Platform desktop adapter, IDE adapter | CFG-FR-021 |

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

### 9.3 Repository-Workspace Desktop Integration Algorithm

For each supported graphical desktop:

1. Resolve the repository workspace as `${HOME}/Repos` (or the exact native equivalent) and resolve the desktop folder without hardcoding a user name.
2. If the workspace path is absent, create only the parent directory. If the path exists as a non-directory, preserve it and report a conflict.
3. Never traverse, enumerate for maintenance, recursively permission-change, move, delete, or otherwise mutate repositories or files beneath the workspace.
4. Create or repair the course-managed desktop item named `Repos` so its target resolves exactly to the repository workspace; preserve and report any conflicting unmanaged item.
5. Apply the platform adapter's approved repository-workspace visual treatment. CVD applies its native development emblem. Windows retains the normal folder appearance, removes only stale course-managed application-icon metadata from earlier implementations, and uses a standard folder icon for the desktop `Repos` shortcut. Treat visual treatment as cosmetic and do not add a software-package dependency solely to provide it.
6. Configure profile-owned Visual Studio Code desktop launch behavior. On CVD, repair the existing course-provided launcher and do not create a duplicate when the expected launcher is missing. On Windows bare metal, create or repair the course-owned `Visual Studio Code - IT 140` shortcut so it targets the resolved Visual Studio Code executable and uses the repository workspace as both the active folder argument and working directory; preserve unrelated VS Code shortcuts.
7. Query the resulting workspace, desktop target, applicable visual treatment, and profile-owned IDE launcher fields and compare them with the required state.
8. Repair only course-owned integration metadata while preserving unrelated desktop layout, icons, preferences, launchers, and all student repository content.

## 10. Verify Script Design

Verify uses read-only adapter interfaces. A platform implementation shall make mutating methods unavailable to the Verify orchestrator rather than relying only on developer discipline.

| Design ID | Planned Verify behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| VER-DES-001 | Construct a read-only check plan and expose no install, repair, update, removal, package-refresh, or settings-write operations. | Read-only adapter interfaces | VER-FR-001, PKG-QOS-002 |
| VER-DES-002 | Run entirely as the standard user and report inaccessible privileged facts as designed warnings or failures without elevating. | Platform adapter | VER-FR-002 |
| VER-DES-003 | Validate the manifest and record its automation SemVer release, release date, schema identity, and Verify artifact identity as the comparison baseline. | Manifest loader, validator, artifact identity service | VER-FR-003 |
| VER-DES-004 | Check platform, release, architecture, user context, disk space, permissions, and approved network endpoints. | Platform detector, network probe | VER-FR-004 |
| VER-DES-005 | Iterate over required system capability bindings and compare presence and product versions with manifest rules. | Capability adapters, check registry | VER-FR-005 |
| VER-DES-006 | Check required user tools, extensions, version-control settings, provider authentication, IDE settings, script permissions, course folders, repository-workspace integration, and profile-owned IDE workspace launch behavior. | Read-only capability, provider, and desktop adapters | VER-FR-006 |
| VER-DES-007 | Validate managed configuration structure and safe values while redacting secrets and complete personal identifiers. | Redaction service, settings readers | VER-FR-007 |
| VER-DES-008 | Represent each check as one `CheckResult` with `PASS`, `WARNING`, `FAIL`, or `NOT APPLICABLE`. | Check registry | VER-FR-008 |
| VER-DES-009 | Store the owning remediation action and related SRS ID in each check definition so failures produce the correct Prepare, Install, Configure, or Update command. | Check registry, output service | VER-FR-009 |
| VER-DES-010 | Store required or optional classification in manifest data and check definitions; optional absence cannot create a required failure. | Manifest validator, result aggregator | VER-FR-010 |
| VER-DES-011 | Count results by status and display the totals with overall compliance. | Result aggregator | VER-FR-011 |
| VER-DES-012 | Resolve the final exit code from the most serious observed result using the shared precedence table. | Result aggregator | VER-FR-012 |
| VER-DES-013 | Save a sanitized transcript and, only on explicit request, prepare a versioned inventory-reviewed support bundle. | Transcript service, bundle builder, artifact identity service | VER-FR-013 |
| VER-DES-014 | Map unrepairable or administrative conditions to a manifest- or platform-declared support channel rather than an inappropriate lifecycle script. | Check registry, output service | VER-FR-014 |
| VER-DES-015 | Query only the repository-workspace parent path and accessibility; do not create a probe file or change permissions. | Read-only path adapter | VER-FR-015 |
| VER-DES-016 | Resolve the desktop `Repos` shortcut or link target read-only and compare it with the canonical repository workspace. | Read-only desktop adapter | VER-FR-016 |
| VER-DES-017 | Query the qualified repository-workspace visual treatment without writing it. On Windows, detect stale course-managed application-icon metadata; map a platform-declared unsupported visual treatment to `NOT APPLICABLE`. | Read-only desktop metadata adapter | VER-FR-017 |
| VER-DES-018 | Parse profile-owned Visual Studio Code desktop launch integration read-only. On CVD, require the existing launcher to use the repository-workspace folder argument and reject a course-root-only launch target. On Windows bare metal, require `Visual Studio Code - IT 140` to target the resolved VS Code executable and use the repository workspace as both its active folder argument and working directory. | Read-only desktop-entry or shortcut probe | VER-FR-018 |

### 10.1 Check Registry Structure

Each check definition contains:

```text
check_id
check_definition_version
check_definition_version_date
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

The registry lets Install, Configure, and Update reuse selected post-operation probes without allowing Verify to mutate state. Prepare-related checks are read-only structural and version probes that recommend Prepare when package files are missing, stale, or inconsistent.

### 10.2 Verification Flow

```text
load ordered check registry and validate its artifact identity
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
optionally create approved versioned support bundle
return resolved exit code
```

## 11. Update Script Design

Update owns maintenance of approved system software, user-scoped course tools, the latest approved manifest within update compatibility, and course-managed maintenance assets. It does not perform an operating-system release upgrade, refresh lifecycle script source files, or modify student-owned work.

| Design ID | Planned Update behavior | Main collaborators | Related SRS requirement |
| --- | --- | --- | --- |
| UPD-DES-001 | Evaluate platform, user, disk space, network reachability, and privilege capability before planning changes. | Platform detector | UPD-FR-001 |
| UPD-DES-002 | Acquire action- and resource-scoped locks before package or managed-file mutation. | Lock manager | UPD-FR-002 |
| UPD-DES-003 | Retrieve the latest approved manifest and maintenance-scope asset inventory through the trust chain while excluding lifecycle script refresh. | Retry, trust, and manifest services | UPD-FR-003 |
| UPD-DES-004 | Download candidates into a private staging directory and validate syntax, schema, artifact identity, compatibility, paths, and integrity before activation. | Staging service, validators | UPD-FR-004 |
| UPD-DES-005 | Preserve the previous valid asset until activation and post-read validation succeed; restore it when activation fails. | Replacement service | UPD-FR-005 |
| UPD-DES-006 | Refresh package metadata and install approved security, maintenance, and course-capability updates within the current OS release. | Package adapter | UPD-FR-006 |
| UPD-DES-007 | Exclude OS release-upgrade operations from the Update adapter contract and reject a manifest that attempts to request one. | Manifest validator, platform adapter | UPD-FR-007 |
| UPD-DES-008 | Update or repair required user-scoped programming tools and IDE extensions or plug-ins from role bindings. | Runtime and IDE adapters | UPD-FR-008 |
| UPD-DES-009 | Enumerate and preserve optional user extensions or plug-ins; only required managed items are enforced. | IDE adapter | UPD-FR-009 |
| UPD-DES-010 | Remove an obsolete component only when its exact managed asset ID, canonical path, scope, and removal rule are approved. | Path safety and asset services | UPD-FR-010 |
| UPD-DES-011 | Perform only adapter-defined safe cache and dependency cleanup followed by required-component validation. | Package adapter | UPD-FR-011 |
| UPD-DES-012 | Apply bounded retry policy to temporary network and source failures while preserving installed valid state. | Retry service | UPD-FR-012 |
| UPD-DES-013 | Run post-update probes for required capabilities, product versions, settings, maintenance assets, and package consistency. | Check helpers, result aggregator | UPD-FR-013 |
| UPD-DES-014 | Detect and report the least disruptive restart action required; never restart an active session automatically. | Restart detector | UPD-FR-014 |
| UPD-DES-015 | Use state queries, staging, locks, and idempotent operations so an interrupted run can be rerun safely. | Shared services | UPD-FR-015 |
| UPD-DES-016 | Recommend Verify after warnings, failures, partial completion, or required restart; successful no-restart maintenance may report Verify as optional. | Output service | UPD-FR-016 |

### 11.1 Managed-Asset Update Transaction

```text
retrieve approved maintenance release metadata
validate artifact identity, trust, scope, and compatibility
create private staging directory
FOR EACH changed maintenance-scope managed asset
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
2. Obtain and validate approved maintenance release metadata and a compatible manifest.
3. Stage compatible maintenance-scope assets required for the run.
4. Activate compatible manifest and maintenance assets using rollback protection.
5. Refresh system package information and approved system software.
6. Update required user-scoped tools and extensions.
7. Refresh declared maintenance-scope integrations.
8. Remove explicitly obsolete managed components.
9. Perform safe cleanup.
10. Run post-update checks and restart detection.

Lifecycle scripts, their supporting source files, and incompatible schema transitions are not activated by Update. When the installed scripts are too old for the available manifest or maintenance release, Update stops safely and recommends `prepare_it140.<ext>` to refresh the package before maintenance continues.

## 12. Error and Exception Handling

### 12.1 Error-Handling Principles

- Detect predictable failures before mutation whenever possible.
- Preserve the original root-cause result during cleanup and logging.
- Stop dependent stages after a required prerequisite fails.
- Continue only independent read-only checks or safe cleanup that adds useful diagnostics.
- Distinguish unsupported, permission, external-service, integrity, cancellation, partial-state, and general failures.
- Never claim success solely because an external command returned without obvious text errors; verify the resulting state.
- Preserve course continuity by adding profile-aware guidance to every unsuccessful managed lifecycle conclusion after the specific remediation is known.

### 12.2 Error and Recovery Components

| Design ID | Condition | Detection | Planned response | Related SRS requirements |
| --- | --- | --- | --- | --- |
| ERR-DES-001 | Unsupported invocation, platform, architecture, or user context | Option parser and platform matcher | Make no managed change, explain supported use, return code `2` or the platform-defined safe nonzero result. | PKG-FR-003, PRE-FR-004, INS-FR-002, PKG-QOS-014 |
| ERR-DES-002 | Missing required privilege | Native privilege probe before mutation | Stop affected action, provide approved command or support path, return code `3`. | INS-FR-001, UPD-FR-001, PKG-NFR-022 |
| ERR-DES-003 | Missing, unreadable, or invalid manifest | File, JSON, schema, artifact-identity, semantic, and compatibility validation | Stop before managed change, identify validation stage, return code `5`. | PKG-FR-005, PKG-FR-019 |
| ERR-DES-004 | Integrity or staged-package validation failure | Checksum, signature, trusted metadata, structure probe, or equivalent control | Reject candidate, preserve installed package or asset, return code `5`. | PRE-FR-008, PRE-FR-014, PKG-NFR-024, UPD-FR-004 |
| ERR-DES-005 | Temporary source or network failure | Adapter-classified retryable result | Retry within bounded policy, show truthful status, return code `4` after exhaustion. | PRE-FR-007, UPD-FR-012, PKG-QOS-008 |
| ERR-DES-006 | Concurrent mutating operation | Nonblocking scoped lock | Make no overlapping change, identify active action, return a nonzero result. | UPD-FR-002, PKG-QOS-005 |
| ERR-DES-007 | User cancellation | Explicit prompt result or provider adapter cancellation status | Preserve prior state, mark dependent stages skipped, return code `6` unless a higher-precedence failure exists. | CFG-FR-006, PKG-QOS-014 |
| ERR-DES-008 | Partial operation or interruption | Stage journal, changed flags, incomplete post-validation, or signal handling | Preserve recoverable state, explain rerun or remediation, return code `7`. | PRE-FR-012, UPD-FR-015, PKG-QOS-003 |
| ERR-DES-009 | Invalid existing user settings | Parser or platform settings API | Preserve original file, create sanitized diagnostic copy when safe, do not overwrite with defaults. | CFG-FR-011, PKG-FR-010 |
| ERR-DES-010 | Unsafe managed path, package-refresh target, or removal target | Canonical path and allowlist validation | Reject operation, record security-relevant failure, make no deletion. | PRE-FR-009, PRE-FR-010, PKG-FR-020, UPD-FR-010, PKG-NFR-023 |
| ERR-DES-011 | Post-operation verification failure | Required probe after change | Attempt approved rollback where available; otherwise mark partial state and give remediation. | INS-FR-008, CFG-FR-015, UPD-FR-013 |
| ERR-DES-012 | Invalid artifact identity | Strict SemVer parser, version-date validator, or compatibility check | Refuse release, test, or managed execution as applicable; identify the invalid artifact and preserve prior state. | PKG-NFR-015, VER-FR-003 |
| ERR-DES-013 | Unexpected internal error | Strict error handling and top-level exception or trap | Capture safe context, preserve original status, clean temporary data, summarize, and return code `1` or `7` based on changed state. | PRE-FR-012, PKG-QOS-003, PKG-QOS-012, PKG-QOS-013 |
| ERR-DES-014 | Unsuccessful managed lifecycle conclusion | Final result or resolved exit code | Preserve the specific remediation and log path, then display and log profile-aware course-continuity guidance before exit. | PKG-FR-021 |

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

1. User input entering a managed script.
2. The repository archive entering Prepare from the authorized course source.
3. Manifest and managed assets entering Update from an authorized remote source.
4. Provider account information entering through an external CLI or API.
5. Commands crossing from a script into the operating system or package manager.
6. Diagnostic information leaving the computer in a support bundle.

Every boundary has validation, least-privilege, ownership, and redaction controls.

| Design ID | Security or privacy control | Design implementation | Related SRS requirements |
| --- | --- | --- | --- |
| SEC-DES-001 | Least privilege | Entry points run as the intended standard user; only specific approved system operations receive elevation. Prepare rejects unsafe root or administrator context when required by the deployment profile. | PRE-FR-004, PKG-NFR-022, REF-TC-003 |
| SEC-DES-002 | No arbitrary manifest execution | Manifest selects allowlisted adapter IDs and validated parameters; it cannot provide executable command strings. | PKG-NFR-023, PKG-NFR-024 |
| SEC-DES-003 | Argument-safe command execution | Executable and arguments remain separate; user and manifest values are never interpolated into an unvalidated shell expression. | PKG-NFR-023 |
| SEC-DES-004 | Managed-path allowlist | Canonical target must fall within an approved managed scope and match the declared asset, integration, settings, or Prepare package ownership. | PRE-FR-009, PRE-FR-010, PKG-FR-020, UPD-FR-010 |
| SEC-DES-005 | Trusted-source validation | Prepare's repository archive and managed remote data use encrypted transport plus approved integrity, authenticity, and structural controls anchored in a trust root. | PRE-FR-007, PRE-FR-008, INS-FR-004, PKG-NFR-024 |
| SEC-DES-006 | Secret minimization | Authentication occurs in the provider's approved mechanism; scripts do not request or store passwords or tokens. | PKG-FR-018, PKG-NFR-025 |
| SEC-DES-007 | Field-aware redaction | Structured sensitive fields are removed before pattern-based fallback redaction and output. | VER-FR-007, PKG-NFR-025 |
| SEC-DES-008 | Private diagnostics | Logs, temporary files, and support bundles use restrictive per-user permissions when supported. | PRE-FR-005, PKG-NFR-026 |
| SEC-DES-009 | Temporary-data lifecycle | Prepare and managed scripts delete private downloaded or generated temporary data after safe use and error handling. | PRE-FR-012, PKG-NFR-027 |
| SEC-DES-010 | User-owned data exclusion | Package refresh, support collection, and cleanup start from explicit allowlists, not broad recursive collection. | PRE-FR-009, PRE-FR-010, PKG-FR-010, PKG-QOS-022 |
| SEC-DES-011 | Provider-data minimization | Provider adapters request only account fields declared by the approved profile and needed by configuration. | CFG-FR-007, PKG-NFR-025 |
| SEC-DES-012 | Change auditability | Logs identify artifact SemVer, version date-time group, stage, managed asset IDs, and result without storing secret values. | PKG-NFR-015, PKG-QOS-017, PKG-QOS-018 |

### 13.2 Redaction Order

1. Remove fields marked secret by the adapter contract.
2. Replace complete personal email addresses with an approved masked representation or identity type.
3. Remove token-, key-, cookie-, and credential-like values.
4. Normalize user-specific paths when a full path is not required for diagnosis.
5. Apply pattern-based checks as a defense in depth.
6. Scan the final support-bundle inventory and contents before creation.

### 13.3 Trust-Root Design

The manifest cannot prove its own authenticity using only values stored inside itself. The initial implementation anchors trust in one or more items distributed with or embedded in the approved script release, such as:

- An allowlisted institutional or project source location.
- The exact authorized repository archive location used by Prepare.
- A pinned public verification key.
- Release metadata with independently verifiable signatures.
- A trusted native package repository.
- Staged archive structural requirements, including the matching platform directory and Install artifact.

Prepare must carry enough trusted source and structural information to validate the package before the manifest is available. Managed scripts then use the manifest, schema, and release metadata through the approved trust chain. The exact approved mechanism is platform- and release-specific and belongs in the platform design and controlled release process.

## 14. Platform and Provider Abstraction Design

### 14.1 Platform-Independent and Platform-Specific Layers

| Design ID | Design element | Stable interface | Platform-specific implementation | Related SRS requirements |
| --- | --- | --- | --- | --- |
| PLT-DES-001 | Platform detection | Return normalized platform facts. | Native OS and session queries. | PKG-FR-003, PRE-FR-004, REF-TC-001 |
| PLT-DES-002 | Native scripting | Implement the same five lifecycle outcomes and result contracts. | Approved platform-native scripting language and conventions. | PRE-FR-003, PKG-TC-001, REF-TC-002 |
| PLT-DES-003 | Package management | Query, refresh, install, update, repair, cleanup, and validate approved packages. | Native package-manager adapter. | INS-FR-003 through INS-FR-006, UPD-FR-006, UPD-FR-011 |
| PLT-DES-004 | Privilege control | Determine capability and elevate one approved operation. | Native privilege mechanism. | PRE-FR-004, PKG-NFR-022, REF-TC-003 |
| PLT-DES-005 | Path resolution | Return canonical home, desktop, temporary, configuration, and executable paths. | Native environment and folder APIs. | PRE-FR-005, PKG-NFR-019, PKG-NFR-020, REF-TC-005 |
| PLT-DES-006 | User integration | Create or query the repository-workspace parent integration, desktop `Repos` item, development marker, profile-owned IDE workspace launcher, and file associations. | Native shortcut, launcher, desktop-entry, folder-metadata, shell, or IDE interface. | CFG-FR-013 through CFG-FR-021, VER-FR-015 through VER-FR-018, REF-TC-006 |
| PLT-DES-007 | Restart detection | Report required application, session, virtual-machine, or computer restart. | Native update and session indicators. | UPD-FR-014, REF-TC-004 |
| PLT-DES-008 | Provider integration | Expose stable authentication and account operations. | Allowlisted provider adapter selected by the profile. | CFG-FR-005 through CFG-FR-008 |
| PLT-DES-009 | Equivalent outcomes | Use the same status, artifact identity, log, remediation, and acceptance semantics. | Different native commands may produce the required final state. | PKG-NFR-001, PKG-NFR-015, PKG-NFR-021 |
| PLT-DES-010 | Deployment-profile qualification | Require five lifecycle entry points, platform constraints, complete Prepare behavior, documentation, approval, and full conformance testing before course support is declared. | Platform-specific evidence package. | PKG-FR-001, PKG-TC-006, Section 3.3 of the SRS |
| PLT-DES-011 | Deployment-profile resolution | Select one enabled profile by detected environment or explicit approved context, then confirm its platform, release, architecture, desktop, and session constraints. | Provider, desktop-session, and reset detection appropriate to the profile. | REF-TC-001 through REF-TC-006, PKG-FR-003 |
| PLT-DES-012 | Prepare bootstrap profile | Implement archive retrieval, extraction, structural validation, package overlay, permission, cleanup, and user `PATH` behavior using only baseline native facilities. | PowerShell and native Windows tools, Z shell and native macOS tools, or equivalent approved baseline. | PRE-FR-001 through PRE-FR-015 |
| PLT-DES-013 | Support-scope boundary | Reuse stable lifecycle and adapter contracts for selected new deployment profiles while representing only qualified and approved deployment profiles as course-supported. | Deployment-specific bindings and evidence are added only when course need and available resources justify the commitment. | PKG-NFR-028, PKG-TC-006, Section 3.3 of the SRS |

### 14.2 Repository Workspace Desktop Adapter Matrix

The repository workspace is a stable user-facing contract, but desktop decoration is adapter-specific. No implementation may install a package solely to satisfy the visual marker.

| Qualified platform | Workspace path | Development marker | Desktop integration | IDE workspace behavior |
| --- | --- | --- | --- | --- |
| CVD / Xfce | `${HOME}/Repos` | Required native `development` emblem through GIO metadata | Symbolic link named `Repos` on the resolved Xfce desktop | Repair the existing course-provided Visual Studio Code desktop entry so its working path and folder argument use `${HOME}/Repos`; missing expected launcher is a Configure failure, not permission to create a duplicate |
| Ubuntu Desktop / GNOME | `${HOME}/Repos` | Prefer a safe native development/code-oriented folder metadata value when supported; otherwise return documented warning or `NOT APPLICABLE` for the visual-only marker | Symbolic link named `Repos` on the resolved desktop | Leave the normal platform Visual Studio Code launcher unchanged |
| Windows bare metal | `%USERPROFILE%\Repos` | Normal Windows folder appearance; do not substitute an application icon or require `desktop.ini` icon customization | `.lnk` named `Repos` on the resolved desktop using a standard Windows File Explorer/folder icon | Create or repair the course-owned `.lnk` named `Visual Studio Code - IT 140`; target the resolved `Code.exe`, pass `%USERPROFILE%\Repos` as the active folder argument, set the working directory to the same workspace, and preserve unrelated Visual Studio Code shortcuts |
| macOS bare metal | `${HOME}/Repos` | `NOT APPLICABLE`; Finder does not expose a stable supported built-in emblem interface appropriate for this automation design | Symbolic link named `Repos` on the resolved Finder Desktop | Leave the normal platform Visual Studio Code launcher unchanged |

Each adapter exposes both mutation and query operations. Configure may call mutation operations only on the workspace parent and explicitly course-owned integration objects. Verify is bound exclusively to query operations. Neither interface receives a recursive workspace path operation.

### 14.3 Adapter Contract Rules

Every adapter method shall:

- Accept validated structured parameters.
- Return an `OperationResult` or structured query value.
- Avoid writing directly to the terminal except through the output or captured-command interface.
- Identify whether it changed state.
- Preserve the native exit status and sanitized diagnostic detail.
- Declare whether privilege is required.
- Support a query operation used for idempotence and verification.
- Avoid product-specific logic in the orchestrator.

### 14.4 Provider Adapter Rules

A provider adapter is added only when:

- Its authentication flow can be explained and supported for first-term students.
- It can report authentication status without exposing credentials.
- It can return the approved minimum account fields.
- It has a documented privacy-preserving commit-identity rule when required.
- Its failure and cancellation states can be distinguished.
- It has automated contract tests and controlled test accounts or mocks.

### 14.4 Selective New Deployment-Profile Qualification

A deployment profile may be proposed when it is useful to the course and the project has sufficient implementation, testing, documentation, and support resources. The design does not require maintainers to inventory or qualify every profile that upstream products might technically support. Technical compatibility, vendor documentation, and successful unqualified use are inputs to evaluation, not evidence of course support.

An enabled manifest profile is available for controlled resolution, testing, or operation; enablement is not itself a course-support designation. Approved qualification evidence and course documentation determine whether an enabled profile is course-supported, qualification-only, or otherwise restricted. Multiple deployment profiles may reuse one platform implementation when their native lifecycle behavior is equivalent.

A proposed deployment profile is not marked course-supported until it provides:

- Five correctly named lifecycle entry points.
- A first-use Prepare command set that works before the package, manifest, package manager, version-control client, and course runtime exist.
- Direct Prepare refresh behavior after first use.
- A manifest platform entry, any applicable deployment-profile entry, and schema-valid role bindings.
- Platform, package-manager, privilege, path, settings, restart, desktop-integration, and user-integration adapters.
- Unit and integration tests for adapters and artifact-version validation.
- Full SRS acceptance-test evidence on a clean supported environment.
- Idempotence evidence from repeated Prepare, Install, Configure, and Update runs.
- Read-only evidence for Verify.
- Repository-workspace desktop-link, development-marker, and profile-owned IDE workspace-launch evidence on supported graphical desktops.
- Student-work preservation, interruption recovery, redaction, and version-traceability evidence.

### 14.6 Initial Platform Conformance Test Matrix

The initial release qualification uses resettable environments selected for supported-profile conformance and qualification-only testing.

| Test target | Role | Required use |
| --- | --- | --- |
| Codio Virtual Desktop: Ubuntu 24.04 LTS, APT, Xfce, x86_64 | Reference deployment | Run the complete Prepare, Install, Configure, Verify, Update, acceptance, idempotence, interruption, support-log, desktop-integration, and student-work-preservation suites for every release candidate. |
| Manifest-approved Windows x86_64 bare-metal deployment | Supported local deployment | Reset to a clean approved release and run the complete platform conformance suite, including repository-workspace desktop and applicable IDE workspace launch targets, before approval. |
| Windows Sandbox on x86_64 | Qualification-only deployment | Run the approved ephemeral-environment and support-reproduction tests. Passing this profile does not qualify or replace the Windows bare-metal deployment. |
| Supported macOS on Apple Silicon bare metal | Supported local deployment | Erase or restore to a clean supported release and run the complete platform conformance suite before approval. |
| Ubuntu 24.04 LTS with APT and GNOME on x86_64 bare metal | Supported local deployment | Reinstall or restore a clean image and run the complete platform conformance suite before approval. |
| Raspberry Pi 4B and 5 | Exploratory ARM64 targets | Evaluate portability, package availability, desktop behavior, and performance. Do not mark ARM64 supported until the full suite passes for an enabled deployment profile. |
| Windows XP, 7, and 8 systems | Negative unsupported-platform targets | Confirm that Prepare and managed platform detection report an unsupported environment, create only the minimum safe diagnostic log when possible, and perform no managed system or user changes. |

A clean test begins from a fresh operating-system installation, provider reset, or approved image restoration. Test evidence records the exact OS release, build, architecture, deployment profile, SRS version and date, SDD version and date, manifest version and date, script versions and dates, test-definition version and date, and final result artifact identity.

## 15. Performance, Logging, and Operational Design

### 15.1 Performance Controls

- Prepare starts the log and displays identifying information before network work.
- Managed entry points start the log and display artifact version information before lengthy package work.
- Manifest and schema files are loaded once per managed run and passed as immutable validated data.
- Local state probes are preferred over downloads or reinstallations.
- Capability checks may run in parallel only when they are read-only, independent, and the platform implementation can preserve deterministic output and reasonable resource use.
- Package-manager mutations remain serialized.
- Verification uses bounded timeouts for network checks and should not wait on interactive authentication.
- Verification shall complete within the SRS limit on the approved reference platform under the stated normal conditions, implementing `PKG-QOS-009`.
- Platform adapters shall accept only manifest-approved operating-system releases that meet the current SRS support policy, implementing `PKG-TC-006`.
- Long operations emit truthful stage messages at intervals required by the SRS.

### 15.2 Log Filename Design

The default logical pattern is:

```text
<action>_ide_<YYYYMMDD>_<HHMMSS>.<log-extension>
```

The path is derived from the current user's approved course log directory. A collision-resistant suffix may be added when two runs begin within the same second. The filename is not the artifact identity; the log header records the producing artifact's ID, SemVer, and version date-time group.

### 15.3 Message Catalog

Student-facing messages should use stable message keys and parameterized values where practical. This improves consistency across scripts and platforms and supports future accessibility or localization work without changing orchestration logic.

Example logical keys:

```text
run.start
artifact.identity
prepare.archive.valid
prepare.package.refreshed
manifest.valid
platform.unsupported
privilege.required
provider.auth.action_required
integration.course_root.valid
integration.ide_course_root.valid
operation.changed
operation.unchanged
verify.remediation
run.summary
run.course_continuity.local
run.course_continuity.cvd
```

Exact English wording may differ slightly by platform when needed, but meaning, status label, version identity, and remediation shall remain equivalent.

### 15.4 Artifact and Release Records

Each approved release record identifies:

- The artifact ID, SemVer, and version date-time group of every changed controlled artifact.
- The reason each artifact received a MAJOR, MINOR, or PATCH increment.
- The SRS and SDD baselines used for construction.
- The manifest, schema, and platform implementation versions tested.
- The test-definition and test-result versions and dates.
- Compatibility, migration, rollback, and deployed-platform effects.
- The repository commit and approval evidence.

Logs and test results are generated records rather than source artifacts, but they still record the version and date of the producing or governing artifact as required by `PKG-NFR-015`.

## 16. Design Decisions and Rationale

| # | Design decision | Rationale | Alternative considered |
| ---: | --- | --- | --- |
| 1 | Use one combined package SDD. | The five components share data, services, interfaces, quality rules, and remediation paths. One SDD reduces duplication and drift. | Separate SDD per script; rejected for the initial release because shared design would be repeated. |
| 2 | Keep stable capability roles in the design and concrete products in the controlled manifest. | Product selections change more often than course capabilities. | Hardcode products in every script and design section; rejected because it increases maintenance and inconsistency. |
| 3 | Allow only reviewed adapter identifiers in the manifest. | A public configuration file must not become an arbitrary command-execution mechanism. | Store executable command templates in JSON; rejected for security and portability reasons. |
| 4 | Use platform-native entry points rather than one course-managed cross-platform runtime. | Prepare and Install must run before the course runtime is guaranteed to exist. | Require a shared runtime before preparation; rejected because it creates an impossible bootstrap dependency. |
| 5 | Use five entry points with a minimal Prepare boundary and shared managed services. | Separate actions are easier for students and support personnel to understand while shared services maintain consistency. | One script with many subcommands; deferred because it increases command complexity for beginners. |
| 6 | Make Prepare, Install, and Configure approved refresh or repair paths. | Rerunning the component that owns the state is simpler than adding a separate repair or sync command. | Add separate `sync` and `repair` scripts; rejected because they would expand the lifecycle and support matrix. |
| 7 | Keep Verify structurally read-only. | Troubleshooting should observe the original problem and remain safe for students and support staff. | Permit optional repair inside Verify; rejected because it mixes diagnosis and mutation. |
| 8 | Assign lifecycle-script package refresh to Prepare and maintenance-scope updates to Update. | This preserves a clear bootstrap trust boundary and prevents Update from replacing the code currently governing its own run. | Synchronize lifecycle scripts inside Update; rejected because it conflicts with the Prepare stage and complicates schema transitions. |
| 9 | Use query-plan-apply-verify for mutating actions. | This pattern supports idempotence, minimal change, and evidence that the final state is usable. | Always reinstall or overwrite; rejected because it is slower and risks user settings. |
| 10 | Use staging and atomic replacement where practical. | A failed download or interrupted write must not replace a working asset with a partial file. | Write directly to the destination; rejected because recovery is weaker. |
| 11 | Use plain-text logs with stable version fields. | Students and support personnel can read them without specialized tools while identifying the exact producing artifact. | Store only structured machine logs; rejected for student usability, though structured supplemental data may be added later. |
| 12 | Keep the reference product mapping in a nonnormative appendix. | Reviewers need concrete context, but the manifest remains the current authority. | Remove all product names; rejected because it weakens review and test context. |
| 13 | Give each controlled artifact an independent SemVer and version date-time group. | Independent identities support exact traceability and correct compatibility decisions without forcing unrelated files to share a version. | Use one date-based package number for every artifact; rejected because dates do not express compatibility or change type. |
| 14 | Separate the student repository workspace from the course automation root and provide a predictable desktop entry to the repository workspace; on CVD, repair the existing IDE launcher, and on Windows bare metal, provide a separate course-owned IDE shortcut that opens that workspace. | Beginning students receive a predictable development location without conflating student-owned repositories with course-managed automation files or replacing unrelated user launchers. | Put student repositories under the course automation root or commandeer an unrelated IDE shortcut; rejected because those approaches create ambiguous ownership and raise the risk of automation touching student work or preferences. |
| 15 | Design for selective extensibility instead of universal platform coverage. | Stable lifecycle orchestration and adapter contracts keep future expansion practical, while explicit qualification prevents an unbounded testing and maintenance commitment. | Promise support for every platform accepted by any upstream product; rejected because the course cannot implement, test, document, and maintain that open-ended matrix responsibly. |
| 16 | Add profile-aware course-continuity guidance to every unsuccessful managed lifecycle conclusion. | Students can continue required coursework in CVD while a local environment issue is repaired, without misleading users when CVD itself is affected. | Provide remediation only; rejected because it can leave beginners believing they must stop coursework until local repair is complete. |

## 17. Requirements Traceability

A range in this table is inclusive. The design elements listed for a range apply to every requirement in that range. Script-specific requirements map one-to-one to the correspondingly numbered script design element where practical.

| SRS requirement(s) | Primary SDD design elements | Supporting planned artifact(s) |
| --- | --- | --- |
| PKG-FR-001 through PKG-FR-003 | ARC-DES-001 through ARC-DES-004, SHR-DES-006, PLT-DES-001, PLT-DES-010 | Architecture diagram; all five pseudoscripts |
| PKG-FR-004 through PKG-FR-005 | ARC-DES-004, SHR-DES-004, SHR-DES-005, DAT-DES-001 through DAT-DES-006 | Manifest schema; four managed pseudoscripts |
| PKG-FR-006 through PKG-FR-009 | ARC-DES-011, SHR-DES-001 through SHR-DES-003, SHR-DES-012, SHR-DES-017, INT-DES-001 through INT-DES-013 | Shared-output design; all five pseudoscripts |
| PKG-FR-010 | ARC-DES-005, SHR-DES-009, SEC-DES-004, SEC-DES-010 | Safety tests; managed-path tests |
| PKG-FR-021 | SHR-DES-002, SHR-DES-012, INT-DES-014, ERR-DES-014 | All five pseudoscripts; handled-failure and noncompliance acceptance tests |
| PRE-FR-001 through PRE-FR-015 | PRE-DES-001 through PRE-DES-015, PLT-DES-012 | `prepare_it140.pseudo`; Prepare flowchart; first-use, refresh, interruption, and preservation tests |
| INS-FR-001 through INS-FR-012 | INS-DES-001 through INS-DES-012 | `install_it140.pseudo`; Install flowchart; Install tests |
| CFG-FR-001 through CFG-FR-021 | CFG-DES-001 through CFG-DES-021, SHR-DES-018, DAT-DES-017, PLT-DES-006 | `configure_it140.pseudo`; desktop-integration design; Configure tests |
| VER-FR-001 through VER-FR-018 | VER-DES-001 through VER-DES-018, PLT-DES-006 | `verify_it140.pseudo`; check registry; Verify tests |
| UPD-FR-001 through UPD-FR-016 | UPD-DES-001 through UPD-DES-016 | `update_it140.pseudo`; update transaction diagram; Update tests |
| PKG-FR-011 through PKG-FR-020 | DAT-DES-001 through DAT-DES-017, SHR-DES-009, SEC-DES-004 | Manifest schema; configuration-control procedure |
| PKG-NFR-001 through PKG-NFR-005 | ARC-DES-003 through ARC-DES-011, SHR-DES-002, DAT-DES-011 | Architecture diagram; conformance tests |
| PKG-NFR-006 through PKG-NFR-011 | INT-DES-005, INT-DES-009 through INT-DES-013, SHR-DES-002 | Message catalog; usability review |
| PKG-NFR-012 through PKG-NFR-017 | ARC-DES-004, ARC-DES-010, ARC-DES-011, DAT-DES-014, DAT-DES-016, SHR-DES-017, shared component structure | Artifact-control procedure; static-analysis configuration; automated tests; change history |
| PKG-NFR-018 through PKG-NFR-021 | ARC-DES-003, ARC-DES-008, PLT-DES-001 through PLT-DES-012 | Platform adapter contract; conformance suite |
| PKG-NFR-028 | ARC-DES-003, ARC-DES-012, PLT-DES-001 through PLT-DES-013 | Platform adapter contract; deployment-profile proposal and qualification evidence |
| PKG-NFR-022 through PKG-NFR-027 | SHR-DES-008, SHR-DES-009, SHR-DES-013, SEC-DES-001 through SEC-DES-012 | Security tests; redaction tests; support-bundle tests |
| PKG-TC-001 through PKG-TC-009 | ARC-DES-003, ARC-DES-008, DAT-DES-001 through DAT-DES-017, PLT-DES-001 through PLT-DES-012 | Manifest schema; platform design documents |
| REF-TC-001 through REF-TC-007 | PLT-DES-001 through PLT-DES-007, PLT-DES-011, Appendix A | Reference-platform adapter design and acceptance evidence |
| PKG-QOS-001 through PKG-QOS-006 | ARC-DES-006, SHR-DES-010 through SHR-DES-012, ERR-DES-006, ERR-DES-008, ERR-DES-011 | Idempotence, interruption, and concurrency tests |
| PKG-QOS-007 through PKG-QOS-010 | INT-DES-011, Section 15.1 | Performance acceptance tests |
| PKG-QOS-011 through PKG-QOS-015 | SHR-DES-012, Section 5.5, ERR-DES-001 through ERR-DES-013 | Error-injection and exit-code tests |
| PKG-QOS-016 through PKG-QOS-022 | SHR-DES-001 through SHR-DES-003, SHR-DES-013, SHR-DES-017, DAT-DES-014, DAT-DES-016, INT-DES-013, SEC-DES-007 through SEC-DES-012 | Log tests; support-bundle tests |

### 17.1 Construction Traceability Rule

During construction, each implementation function or module shall identify its primary SDD design element in a nearby comment, docstring, test name, or traceability record. Each controlled implementation file records its own artifact ID, strict SemVer, and version date-time group. Source code should not be cluttered by listing every related requirement when a versioned module-level traceability record provides the mapping clearly.

### 17.2 Test Traceability Rule

Automated and manual tests shall use stable test identifiers and identify:

- The test-definition artifact ID, SemVer, and version date-time group.
- The SRS version and date plus the requirement or acceptance test being verified.
- The SDD version and date plus the design element being exercised.
- The implementation, manifest, and schema artifact versions and dates evaluated.
- The platform, deployment profile, and repository baseline used.
- The starting state and expected final state.
- Whether the test verifies normal, boundary, invalid, interruption, security, privacy, desktop integration, versioning, or idempotence behavior.
- The generated test-result artifact identity and execution date.

A maintenance or release decision shall not rely on a test result whose evaluated artifact identities are missing or ambiguous.

## 18. Design Review Criteria

Before construction or release approval, reviewers shall confirm the following evidence:

| Review area | Acceptance evidence |
| --- | --- |
| SRS coverage | Every SRS requirement is included in Section 17 traceability. |
| Lifecycle completeness | Prepare, Install, Configure, Verify, and Update are present for every supported platform and have exact next-step transitions. |
| Prepare boundary | First use requires only baseline native facilities; refresh validates staged package structure and preserves user-owned content. |
| Responsibility separation | Prepare, Install, Configure, Verify, and Update remain within their approved state and privilege boundaries. |
| Evergreen design | Main-body orchestration uses capability roles and adapters rather than current product names. |
| Controlled configuration | Concrete products, product versions, sources, provider rules, desktop integrations, and maintenance assets are assigned to the manifest and schema. |
| Version governance | Every controlled analysis, design, construction, testing, release, and maintenance artifact has strict SemVer and a version date-time group; logs and results record governing artifact identities. |
| Manifest safety | Manifest data cannot directly introduce arbitrary executable commands or unsafe paths. |
| Idempotence | Query-plan-apply-verify behavior is defined for Prepare, Install, Configure, and Update. |
| Read-only verification | Verify receives only read interfaces and cannot invoke mutating adapter methods. |
| Repository workspace behavior | Configure creates and validates the `Repos` workspace parent, desktop link, applicable development marker, and CVD IDE workspace launcher; Verify checks the same state read-only without traversing student repositories. |
| User-data protection | Package-refresh targets, managed paths, and settings keys are explicit; other content is user-owned. |
| Error recovery | Staging, rollback, locks, retry boundaries, interruption handling, and exit precedence are defined. |
| Privacy and security | Least privilege, trust roots, input validation, redaction, file permissions, and bundle exclusions are defined. |
| Student usability | Stages, labels, prompts, explanations, exact next steps, shortcuts, logs, and profile-aware course-continuity guidance is understandable without relying on color. |
| Platform portability | Platform-independent lifecycle logic, adapter boundaries, selective profile qualification, and the limit on universal support commitments are defined. |
| Design consistency | The SRS, SDD, diagrams, five pseudoscripts, schema, implementation, tests, and release records describe one solution without contradiction. |

## Appendix A (Nonnormative): Reference Environment Used for Initial Design and Testing

### A.1 Purpose and Authority

This appendix records the concrete reference environment used to review this SDD and design the initial adapters and tests. It is **nonnormative**, meaning it provides context but does not override the SRS or controlled manifest. The current approved `it140_manifest.json` is authoritative when this appendix and the manifest differ.

The reference mapping should be updated when convenient for historical clarity, but a routine product or product-version change does not require an SDD change unless the architecture, capability, interface, security boundary, or workflow changes. Appendix updates still receive their own SDD SemVer increment and version date-time group under the artifact-control policy.

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
| Standard repository workspace | `$HOME/Repos` |
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

Each supported platform may have a concise, independently versioned supplement that records only design details that cannot remain generic, including:

- Supplement artifact ID, SemVer, and version date-time group.
- Native script language conventions and strict mode.
- Prepare retrieval, extraction, structure validation, cleanup, and `PATH` behavior.
- Package-manager operations and source configuration.
- Privilege-elevation mechanism.
- Native path and desktop-folder discovery.
- Repository-workspace desktop-link, development-marker, and profile-owned IDE workspace-launch interfaces.
- User settings and file-association interfaces.
- Restart detection and user instructions.
- Capability adapter bindings that require platform-specific code.
- Known platform limitations and approved workarounds.
- Evidence that the platform produces equivalent required outcomes.

A supplement shall not redefine shared exit codes, log fields, artifact identity rules, status meanings, manifest ownership, user-data boundaries, or lifecycle responsibilities.

## Appendix C: References

- `scripts/.dev/analysis/it140_scripts_srs.md`, *IT 140 Course Automation Scripts Software Requirements Specification*, version `0.6.0`, version date-time group `2026-08-07-10-44`.
- `scripts/.dev/README.md`, development notes and five-component lifecycle decisions.
- `scripts/.dev/pseudoscripts/prepare_it140.pseudo`, platform-agnostic Prepare design artifact.
- `scripts/.dev/pseudoscripts/install_it140.pseudo`, platform-agnostic Install design artifact.
- `scripts/.dev/pseudoscripts/configure_it140.pseudo`, platform-agnostic Configure design artifact.
- `scripts/.dev/pseudoscripts/verify_it140.pseudo`, platform-agnostic Verify design artifact.
- `scripts/.dev/pseudoscripts/update_it140.pseudo`, platform-agnostic Update design artifact.
- `scripts/win/prepare_it140.ps1`, current Windows first-use and package-refresh implementation reviewed for this design update.
- `scripts/mac/prepare_it140.zsh`, current macOS first-use and package-refresh implementation reviewed for this design update.
- `scripts/.manifest/it140_manifest.json`, controlled product, platform, deployment-profile, provider, product-version, source, desktop-integration, and maintenance-asset selections when populated and approved.
- Repository acceptance-test and platform-script files at commit `dbde859f90b1b957b05aa03e25b867563c113bb2`.
