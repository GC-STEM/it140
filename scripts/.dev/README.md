# Engineering Executive Summary and Artifact Guide

This guide gives faculty, course developers, maintainers, testers, platform administrators, and technical support personnel a concise overview of the IT 140 Course Automation Scripts package, its lifecycle and architecture, and the engineering artifacts that govern its development.

> [!IMPORTANT]
> This README is informative and navigational, not normative. It does not establish or replace requirements, acceptance criteria, design decisions, configuration rules, or release evidence. The [Software Requirements Specification](analysis/it140_scripts_srs.md) defines required behavior, and the [Software Design Description](design/it140_scripts_sdd.md) defines the approved high-level design. Both are currently drafts for faculty review; this README does not imply release approval.

## Table of Contents

- [Engineering Executive Summary and Artifact Guide](#engineering-executive-summary-and-artifact-guide)
  - [Table of Contents](#table-of-contents)
  - [Document Metadata](#document-metadata)
  - [1. Executive Summary](#1-executive-summary)
  - [2. Waterfall SDLC](#2-waterfall-sdlc)
  - [3. Package Lifecycle at a Glance](#3-package-lifecycle-at-a-glance)
  - [4. Architecture and Design Rationale](#4-architecture-and-design-rationale)
  - [5. Artifact Authority and Traceability](#5-artifact-authority-and-traceability)
  - [6. Current Repository Structure](#6-current-repository-structure)
  - [7. Deployment and Support Model](#7-deployment-and-support-model)
    - [Shared Operational Conventions](#shared-operational-conventions)
  - [8. Reading Guide](#8-reading-guide)
  - [9. Current Artifact Alignment Snapshot](#9-current-artifact-alignment-snapshot)
  - [10. Maintaining This Guide](#10-maintaining-this-guide)

## Document Metadata

- **Course**: IT 140 - *Introduction to Scripting*
- **Program name**: IT 140 Course Automation Scripts
- **Artifact ID**: `IT140-DEV-README`
- **Artifact version**: `0.2.0`
- **Version date**: `2026-08-01`
- **Status**: Draft for faculty review
- **SRS baseline**: `IT140-SRS-SCRIPTS`, version `0.3.0`, version date `2026-08-01`
- **SDD baseline**: `IT140-SDD-SCRIPTS`, version `0.3.0`, version date `2026-08-01`
- **Manifest baseline reviewed**: automation release `0.5.1`, release date `2026-07-30`, status `draft`

> [!IMPORTANT]
> This README is an **informative and navigational executive summary**. It does not create or replace requirements, acceptance criteria, design decisions, configuration rules, or release evidence. The [Software Requirements Specification](analysis/it140_scripts_srs.md) controls required behavior, and the [Software Design Description](design/it140_scripts_sdd.md) controls the approved high-level design. The current repository headers identify both artifacts as drafts for faculty review; this README does not imply release approval.

## 1. Executive Summary

The **IT 140 Course Automation Scripts** package prepares and maintains a consistent course integrated development environment (IDE) across supported hosted and local platforms. It is designed for a large, introductory course whose adult learners bring widely different devices, operating-system experience, and technical backgrounds.

The engineering objective is not to make every platform implementation identical. It is to produce **equivalent required course outcomes** through predictable lifecycle stages, controlled configuration, safe state boundaries, and supportable diagnostics.

The package supports only designated deployment profiles that the course can implement, qualify, document, approve, and maintain. Its architecture minimizes unnecessary platform-specific assumptions so another justified profile can reuse the stable lifecycle and adapter contracts. Technical compatibility with the software stack does not by itself imply course support, and the project does not promise to test every platform that upstream products might support.

This `.dev/` directory contains analysis and design artifacts used by computer science faculty, course developers, platform administrators, maintainers, testers, and technical support personnel. Student installations may omit `.dev/`; operational scripts must not depend on development-only files.

## 2. Waterfall SDLC

The project follows the [Waterfall](https://en.wikipedia.org/wiki/Waterfall_model) software development lifecycle (SDLC), since IT 140 students will follow a simplified version of this model in the course. Work proceeds through defined analysis, design, construction, and testing baselines while allowing controlled feedback when testing or maintenance reveals a requirements or design defect.

| Phase | Primary question | Principal artifacts and evidence |
| --- | --- | --- |
| Requirements analysis | What behavior, constraints, quality, and acceptance results are required? | [SRS](analysis/it140_scripts_srs.md) |
| High-level design | How will the package be organized to satisfy the SRS? | [SDD](design/it140_scripts_sdd.md) |
| Mid-level design | How do major processes, decisions, and control paths interact? | [Flowcharts](flowcharts/) |
| Low-level design | What detailed platform-neutral logic, sequencing, state handling, and error behavior should be constructed? | [Pseudoscripts](pseudoscripts/) |
| Construction | How is the design implemented for each platform and controlled configuration item? | [Manifest schema](../.manifest/it140_manifest.schema.json), [controlled manifest](../.manifest/it140_manifest.json), and platform scripts |
| Testing and qualification | Does the implementation satisfy the requirements and design on clean, repeated, interrupted, invalid, and support scenarios? | SRS acceptance tests, SDD traceability and review criteria, implementation tests, and versioned test-result records |
| Release and maintenance | Which exact artifact versions are approved, deployed, diagnosed, repaired, or superseded? | SemVer identities, version dates, release records, logs, support bundles, and maintenance evidence |

Analysis and design artifacts remain reviewable during later phases, but a discovered defect must be corrected through the applicable change-control process rather than silently implemented around.

## 3. Package Lifecycle at a Glance

Every fully supported platform is intended to provide the same five-component lifecycle:

> **Prepare → Install → Configure → Verify → Update**

| Component | Primary responsibility | Permitted state changes | Privilege boundary | Main support use |
| --- | --- | --- | --- | --- |
| `prepare_ide.<ext>` | On first use, provide copyable platform-native commands that acquire the local package; after first use, refresh the installed automation package. | Course-managed package files, preparation logs, script permissions, and the user's script `PATH` entry only. It does not install the course IDE or configure accounts. | Standard user; no dependency on the manifest, a third-party package manager, a version-control client, or another lifecycle script. | Restore or refresh trusted lifecycle files while preserving the prior valid package and user-owned content. |
| `install_ide.<ext>` | Install or repair the manifest-declared system software and system integrations. | Approved system-level software, repositories, trust material, policies, and integrations. | Approved standard-user execution with controlled operation-level elevation, or an approved administrative deployment context. | Repair the shared system layer without changing personal authentication or preferences. |
| `configure_ide.<ext>` | Configure or repair the current user's course environment. | Course folders, authentication flow, version-control identity, user tools, IDE settings, and desktop integrations within declared managed boundaries. | Standard student or faculty account; no general system-level changes. | Repair user-specific state, including the course-folder shortcut and an IDE launcher that opens the course root. |
| `verify_ide.<ext>` | Inspect the system and user layers and report compliance. | None. Verification is structurally read-only. | Standard user without administrative privilege. | Preserve the original problem, classify results, and identify whether Prepare, Install, Configure, Update, or technical support owns remediation. |
| `update_ide.<ext>` | Maintain approved course IDE software and course-managed maintenance assets over time. | Manifest-declared maintenance-scope system and user assets only; no operating-system release upgrade and no lifecycle-package refresh. | Standard user with controlled elevation only when an approved update requires it. | Apply periodic maintenance and direct the user to Verify when validation is appropriate. |

Prepare, Install, Configure, and Update are designed to be idempotent: rerunning the component should converge on the required state without harmful duplication. Mutating components use a query-plan-apply-verify pattern, bounded retries, staging, cleanup, and rollback where practical. Verify never repairs state.

## 4. Architecture and Design Rationale

The SDD defines a layered **orchestrator-and-adapter architecture** with a minimal Prepare boundary:

```text
First-use native commands
        → Prepare
        → validated local package
        → Install | Configure | Verify | Update entry point
        → orchestrator and shared services
        → reviewed platform, capability, and provider adapters
        → operating system, approved products, and external services
```

The main specifications and design choices address the following needs:

- **Varied learners and devices**: predictable names, stages, summaries, shortcuts, and next steps reduce cognitive load for first-term students without weakening technical safety.
- **Platform-equivalent outcomes**: Windows, macOS, Linux, and hosted environments may require different native commands, but they must satisfy the same capabilities, status meanings, and acceptance criteria.
- **Separated state ownership**: Prepare owns package acquisition, Install owns system state, Configure owns current-user state, Verify owns diagnosis, and Update owns maintenance-scope changes. This separation limits privilege and clarifies remediation.
- **Dependency-minimal preparation**: first-use preparation cannot assume that the course package, manifest, package manager, version-control client, or course runtime is already installed.
- **Manifest-controlled configuration**: one validated manifest selects current products, versions, sources, platforms, provider profiles, managed settings, and managed assets. Stable behavior remains in the SRS, SDD, and reviewed code.
- **Reviewed adapters instead of executable manifest commands**: the manifest may select approved behavior but may not become an arbitrary command-execution mechanism.
- **Idempotence and interruption recovery**: real student computers may be partially configured, manually changed, disconnected, restarted, or interrupted. State inspection, staging, atomic replacement, locks, cleanup, and rerunnable repair paths reduce damage and support burden.
- **Read-only verification**: diagnosis must not conceal the original defect by changing the machine while it is being inspected.
- **Least privilege and managed-path protection**: scripts may change only the layer and paths they own. Student work, nested repositories, unrelated preferences, credentials, and other user-owned content remain outside automation authority.
- **Supportable diagnostics**: consistent plain-language output, deterministic exit codes, and timestamped logs let faculty, AI support tools, and technical support diagnose a run after the terminal closes.
- **Predictable course entry points**: supported graphical desktops provide a shortcut to the course root and an IDE launcher that opens the course root as the active folder or workspace.
- **Independent artifact identity**: each controlled artifact uses its own strict Semantic Versioning (SemVer) `MAJOR.MINOR.PATCH` identifier and separate `YYYY-MM-DD` version date so release and support evidence identifies exactly what was designed, executed, or tested.

## 5. Artifact Authority and Traceability

| Artifact | Question answered and authority | Repository link |
| --- | --- | --- |
| Software Requirements Specification (SRS) | Defines required behavior, constraints, quality expectations, and acceptance tests. It is the authoritative requirements baseline. | [SRS](analysis/it140_scripts_srs.md) |
| Software Design Description (SDD) | Defines the package architecture, responsibility boundaries, data, interfaces, control flow, safety mechanisms, platform abstraction, and traceability. It is the authoritative high-level design baseline. | [SDD](design/it140_scripts_sdd.md) |
| Flowcharts | Provide visual mid-level design for major processes, branches, and control paths. They must agree with the SRS and SDD. | [Flowchart directory](flowcharts/) |
| Pseudoscripts | Provide detailed platform-neutral low-level designs for lifecycle sequencing, state handling, validation, errors, and recovery. They must agree with the SRS, SDD, and applicable flowcharts. | [Pseudoscript directory](pseudoscripts/) |
| Manifest schema | Defines the valid JSON structure, value types, patterns, and structural constraints for controlled configuration. | [Manifest schema](../.manifest/it140_manifest.schema.json) |
| Controlled manifest | Selects the products, versions, approved sources, platforms, deployment profiles, provider profiles, settings, and managed assets approved for the current automation release. | [Controlled manifest](../.manifest/it140_manifest.json) |
| Platform scripts | Implement the approved design through platform-native entry points and reviewed adapters. Code does not override a requirement or design decision. | [CVD](../cvd/), [Windows](../win/), [macOS](../mac/), and [Ubuntu GNOME](../nix/ubg/) |
| Acceptance tests and test evidence | Demonstrate that an exact implementation and configuration baseline satisfies the SRS and SDD. The SRS defines acceptance cases; the SDD defines traceability and design-review criteria. | [SRS](analysis/it140_scripts_srs.md) and [SDD](design/it140_scripts_sdd.md) |
| Software Development Worksheet | Provides a supporting planning template. It is not a project-specific controlling requirements or design artifact in its current form. | [Worksheet](analysis/it140_scripts_sdw.md) |
| This README | Orients readers and maps questions to controlling artifacts. It is informative and must not introduce normative behavior. | `scripts/.dev/README.md` |

A manifest-only change is appropriate when a selected product or version changes without changing a required capability, user workflow, trust boundary, design logic, or acceptance criterion. A change to any of those elements requires SRS and SDD review and may require corresponding flowchart, pseudoscript, implementation, and test changes.

Each controlled artifact receives the SemVer increment required by its own compatibility effect and a new version date when changed. Related artifacts do not receive artificial version changes merely to make their version numbers match. Release and maintenance records must identify the exact versions and dates used for the decision.

## 6. Current Repository Structure

```text
scripts/
├── .dev/
│   ├── analysis/
│   │   ├── it140_scripts_srs.md
│   │   └── it140_scripts_sdw.md
│   ├── design/
│   │   └── it140_scripts_sdd.md
│   ├── flowcharts/
│   ├── pseudoscripts/
│   └── README.md
├── .manifest/
│   ├── it140_manifest.json
│   ├── it140_manifest.schema.json
│   └── README.md
├── cvd/
├── mac/
├── nix/
│   └── ubg/
├── win/
│   └── wsb/
└── README.md
```

The repository separates development-only specifications and designs from operational configuration and platform scripts. The installed course package may omit `.dev/`; the controlled manifest, schema, platform scripts, and logging path must remain available where required by the implementation.

Only explicitly declared repository-managed files, managed assets, paths, settings keys, and obsolete components are writable by automation. Naming alone does not make a folder course-managed, and Prepare must overlay validated package content without deleting unrelated course-root files or nested student repositories.

## 7. Deployment and Support Model

A **course-supported deployment profile** is a specific operating-system, release, architecture, deployment, desktop or session, and script-implementation combination that has completed implementation, qualification testing, documentation, and approval for course use. Vendor documentation, technical compatibility, or successful unqualified use does not create a course-support commitment.

The architecture is intentionally extensible, but platform expansion is selective. A new deployment profile is considered when it is useful to the course and implementation, testing, documentation, and ongoing support resources are available. The project does not maintain an inventory of every deployment profile that upstream products might technically support.

Manifest `enabled` status allows a profile to be resolved for controlled operation or qualification; it is not, by itself, a student-support declaration. Approved qualification evidence and course documentation determine the profile's support role. Multiple deployment profiles may reuse one platform-native script implementation.

| Deployment profile | Role in the package |
| --- | --- |
| Codio Virtual Desktop: Ubuntu 24.04 LTS, APT, Xfce, x86_64 | **Reference deployment** for primary course documentation, screenshots, support reproduction, development, and release acceptance testing. |
| Manifest-approved Windows x86_64 bare-metal deployment | Supported local deployment that must pass the complete platform conformance suite. |
| Supported macOS on Apple Silicon, arm64 | Supported local deployment that must pass the complete platform conformance suite. |
| Ubuntu 24.04 LTS, APT, GNOME, x86_64 | Supported local Linux deployment that must pass the complete platform conformance suite. |
| Windows Sandbox, x86_64 | Ephemeral testing and support-reproduction profile; it does not replace bare-metal Windows qualification. |

The reference designation standardizes course-facing evidence and support reproduction; it does not permit reduced outcomes on other supported platforms. Exploratory architectures and negative unsupported-platform test systems are not supported deployments until they satisfy the applicable qualification requirements.

### Shared Operational Conventions

| Item | Standard |
| --- | --- |
| Course root | `~/it140/`, derived from the current user's home folder; on Windows, the equivalent is `%USERPROFILE%\it140\`. |
| Log directory | `~/it140/logs/` or the exact platform-equivalent path. Every lifecycle run records a timestamped plain-text log or transcript when the environment permits it. |
| Desktop course entry | Configure creates or repairs a shortcut or launcher that opens the course root in the platform file manager on supported graphical desktops. |
| IDE course entry | Configure creates or repairs a launcher that starts the approved IDE with the course root opened as the active folder or workspace; Verify checks the target and behavior. |
| Script discovery | Prepare and Configure establish the matching platform script directory in the current and future user `PATH` without duplicate entries. |
| Version evidence | Opening output, logs, test results, support-bundle inventories, and release records identify applicable artifact versions and version dates. |
| Unsuccessful run | Specific remediation and the exact log path are followed by profile-aware course-continuity guidance. A local-profile failure states: `Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.` A CVD failure directs the user to the applicable remediation and support path. |

## 8. Reading Guide

| Reader or question | Start here | Continue with |
| --- | --- | --- |
| Faculty or SME reviewing scope, student impact, safety, or acceptance criteria | This executive summary | [SRS](analysis/it140_scripts_srs.md), then [SDD](design/it140_scripts_sdd.md) |
| Designer deciding component boundaries, architecture, data flow, or recovery | [SDD](design/it140_scripts_sdd.md) | [Flowcharts](flowcharts/) and [pseudoscripts](pseudoscripts/) |
| Platform developer implementing a lifecycle component | Applicable [pseudoscript](pseudoscripts/) | [SDD](design/it140_scripts_sdd.md), [schema](../.manifest/it140_manifest.schema.json), [manifest](../.manifest/it140_manifest.json), and the applicable platform directory |
| Tester deriving normal, repeat, invalid, interruption, privacy, or desktop-integration tests | SRS acceptance-test section | SDD traceability and design-review sections, then the exact implementation and manifest baseline |
| Technical support diagnosing a student environment | `verify_ide.<ext>` summary and its log under `~/it140/logs/` | Lifecycle responsibility table above, applicable platform script, and the deployment profile in the [manifest](../.manifest/it140_manifest.json) |
| Platform administrator maintaining the reference environment | [Controlled manifest](../.manifest/it140_manifest.json) | SDD platform and operational design, then [CVD scripts](../cvd/) |
| Maintainer evaluating a product or version change | [Controlled manifest](../.manifest/it140_manifest.json) | [Schema](../.manifest/it140_manifest.schema.json); review the SRS and SDD when capability, workflow, trust, design, or acceptance changes |

## 9. Current Artifact Alignment Snapshot

This section records the repository state reviewed for README version `0.2.0`; it is not a release approval.

| Area | Current observation | Required follow-through |
| --- | --- | --- |
| SRS and SDD | Both use the five-component lifecycle, SemVer, version dates, designated course-supported deployment profiles, selective portability, profile-aware course-continuity behavior, desktop course-root integration, and updated traceability. Both headers currently say **Draft for faculty review**. | Complete the applicable faculty review and approval record before treating them as released baselines. |
| Flowcharts | The directory contains root-only Draw.io placeholder files named `setup.drawio`, `config.drawio`, `verify.drawio`, and `update.drawio`. It has no Prepare flowchart, current `install` and `configure` filenames, diagram content, or `.drawio.png` exports. | Create and version the mid-level designs before relying on flowcharts as lifecycle evidence. The empty placeholders are not part of this revision. |
| Pseudoscripts | Files exist for Prepare, Install, Configure, Verify, and Update, plus a template. Version `0.3.0` adds the shared profile-aware course-continuity behavior to unsuccessful conclusions. Some files still retain legacy implementation references or other terminology outside the scope of this revision. | Complete the broader pseudoscript reconciliation against SRS `0.3.0` and SDD `0.3.0` before treating the low-level design set as fully aligned. |
| CVD, Windows, and macOS directories | Each directory currently exposes five lifecycle filenames using `prepare_ide`, `install_ide`, `configure_ide`, `verify_ide`, and `update_ide`. Filename presence alone is not conformance evidence. | Maintain platform-specific test and release evidence against the current SRS, SDD, manifest, and script versions. |
| Ubuntu GNOME directory | The current files retain legacy `bootstrap_ubg`, `setup_ubg`, `config_ubg`, `verify_ubg`, and `update_ubg` names. | Refactor and qualify the implementation against the five approved entry-point names and current lifecycle contracts. |
| Windows Sandbox directory | The current auxiliary testing files retain legacy `bootstrap_wsb`, `setup_wsb`, `config_wsb`, and `verify_wsb` names. | Keep the Sandbox profile clearly separated from the general Windows student lifecycle and update its support documentation when the auxiliary design changes. |
| Test artifacts | No dedicated `scripts/.dev/tests/` directory is present in the reviewed structure. Acceptance cases exist in the SRS, and the SDD defines test traceability and review criteria. | Establish or document the controlled location for executable test definitions and versioned result evidence. |
| Software Development Worksheet | The worksheet now records the project-specific stakeholder intent, selective platform-support boundary, portability objective, and CVD course-continuity requirement as draft analysis input. | Review and approve the analysis baseline with the SRS and SDD; the SRS remains authoritative for required behavior. |

## 10. Maintaining This Guide

Update this README when its executive summary, artifact map, repository structure, or alignment snapshot changes. Increment its independent SemVer according to the compatibility effect of the README change and assign a new `version_date`. Do not change its version solely because another artifact changed.

Keep links relative, keep the document concise, and direct readers to the controlling artifact rather than copying detailed requirements, algorithms, traceability matrices, test cases, platform commands, or troubleshooting procedures into this guide.
