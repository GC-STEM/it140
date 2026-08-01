# Software Development Worksheet

- **Course**: IT 140 - *Introduction to Scripting*
- **Activity**: Course Automation Script Development
- **Program Name**: IT 140 Course Automation Scripts
- **Document ID**: IT140-SDW-SCRIPTS
- **Status**: Draft for faculty review
- **Version**: 0.1.0
- **Version Date**: 2026-08-01
- **Repository Baseline**: `GC-STEM/it140` commit `e7d3e7fc24eeefd5aafccd8939982f5c0369c3f4` retrieved 2026-08-01

This worksheet records the stakeholder intent and analysis decisions that precede the Software Requirements Specification (SRS) and Software Design Description (SDD). It is a supporting analysis artifact. The approved SRS remains authoritative for required behavior.

## 1. Document Review

The following sources were reviewed when preparing this analysis baseline:

- [x] Current `scripts/` repository structure and platform implementations
- [x] Software Requirements Specification
- [x] Software Design Description
- [x] Controlled manifest and manifest schema
- [x] Platform-agnostic pseudoscripts
- [x] Existing acceptance-test definitions
- [x] Available platform test resources and course support model

## 2. Program Purpose and Stakeholder Intent

The IT 140 Course Automation Scripts package shall provide a consistent, supportable course integrated development environment (IDE) on **designated course-supported deployment profiles**. The package shall prepare, install, configure, verify, and maintain the course IDE while protecting student work and producing useful support diagnostics.

The requirements and architecture shall minimize unnecessary platform-specific assumptions and isolate platform-dependent behavior. This allows another profile supported by the complete required software stack to be added without redesigning the platform-independent lifecycle. The project is not required to discover, implement, test, or maintain every platform that upstream products might technically support.

A deployment profile becomes course-supported only after its implementation, qualification testing, documentation, and approval are complete. Vendor support, technical compatibility, or successful unqualified use does not by itself create a course-support commitment.

## 3. Required Program Behaviors

| SRS Area | What the Package Must Do |
| --- | --- |
| Package lifecycle | Provide the same Prepare → Install → Configure → Verify → Update lifecycle for every designated course-supported deployment profile. |
| Controlled configuration | Use the validated manifest and schema as the authoritative source for approved products, versions, sources, platform implementations, deployment profiles, settings, and managed assets. |
| Responsibility boundaries | Keep package retrieval, system installation, user configuration, read-only verification, and maintenance responsibilities separate. |
| Portability-conscious design | Keep platform-independent lifecycle logic stable and isolate platform-, package-manager-, desktop-, provider-, and product-specific behavior behind reviewed boundaries. |
| Selective platform qualification | Add support only when course need, implementation capacity, test resources, documentation, and approval justify the commitment. |
| Safe failure | Stop safely, preserve recoverable state, log the failure, provide remediation, and return a deterministic nonzero result. |
| Course continuity | Every unsuccessful managed lifecycle run shall provide course-continuity guidance. For a local course IDE issue, the guidance shall state that the user can continue coursework in the Codio Virtual Desktop (CVD) while the issue is resolved. If CVD itself is affected, the guidance shall direct the user to the applicable remediation and support path instead of presenting the affected environment as an alternative. |
| Student-data protection | Preserve student source files, repositories, version-control history, optional tools, and unrelated user settings. |
| Diagnostics | Save a timestamped transcript under `~/it140/logs/` or the exact platform-equivalent path and identify the log in opening and closing output. |

## 4. Inputs and Outputs

### Inputs

| Input | Source | Type or Format | Valid Values or Rules |
| --- | --- | --- | --- |
| Lifecycle action | User or course workflow | One of five entry points | Prepare, Install, Configure, Verify, or Update |
| Platform facts | Operating system | Structured detected values | Must match an approved platform and deployment profile before managed changes begin |
| Manifest and schema | Course package | UTF-8 JSON | Must pass syntax, schema, semantic, relationship, compatibility, path, and integrity validation |
| User choices | Interactive prompts or approved options | Bounded documented values | Must be validated; cancellation must preserve prior valid state |
| External software and services | Approved vendors, projects, repositories, and providers | Structured adapter results | Must use approved sources, bounded retries, and integrity controls |

### Outputs

| Output | Destination | Required Format |
| --- | --- | --- |
| Opening run information | Terminal and transcript | Script identity, version date, platform, user, purpose, and log path |
| Stage and result messages | Terminal and transcript | Stable plain-language status labels and sanitized detail |
| Final summary | Terminal and transcript | Result, changes, warnings, failures, restart guidance, remediation, next step, log path, and exit code |
| Course-continuity notice | Terminal and transcript after every unsuccessful managed run | For a local course IDE issue: `Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.` For a CVD issue: `Course continuity: This issue affects the Codio Virtual Desktop (CVD). Follow the remediation above. If the issue continues, contact course support and include the log file.` |
| Support bundle | User-approved file under the log directory | Sanitized diagnostics only; no student source, repository contents, history, credentials, or browser data |

## 5. Processing Plan

1. Initialize strict error handling, artifact identity, paths, and a private transcript.
2. Detect the platform, deployment context, user, privilege capability, and native facilities.
3. Validate the running entry point against a designated course-supported profile.
4. Load and validate controlled configuration when the lifecycle stage permits it.
5. Resolve reviewed adapters and build a query-plan-apply-verify or read-only check plan.
6. Execute only operations within the lifecycle component's approved responsibility boundary.
7. Preserve user-owned content and prior valid managed state when a stage fails or is interrupted.
8. Aggregate results, remediation, restart guidance, and the deterministic exit code.
9. For any unsuccessful result, display profile-aware course-continuity guidance in addition to the specific remediation.
10. Close the transcript and report the exact log path and next action.

## 6. Planned Code and Artifact Structure

| Component or Artifact | Responsibility |
| --- | --- |
| SRS | Defines required behavior, support boundaries, quality constraints, and acceptance criteria. |
| SDD | Defines the layered orchestrator-and-adapter architecture, shared services, interfaces, recovery, and platform qualification process. |
| Manifest and schema | Declare current approved products, sources, platform implementations, deployment profiles, settings, managed assets, and valid configuration structure. |
| Platform-agnostic pseudoscripts | Define detailed lifecycle sequencing and common unsuccessful-run behavior before platform construction. |
| Platform-native entry points | Implement the approved lifecycle for one designated course-supported deployment profile. |
| Shared or generated platform-local helpers | Reduce duplication without creating a student runtime dependency on development-only source. |
| Acceptance tests and evidence | Demonstrate conformance on exact approved platform and artifact baselines. |

## 7. Constraints and Required Techniques

- **Platform support boundary**: Only deployment profiles explicitly implemented, qualified, documented, and approved for course use are course-supported. Manifest enablement permits controlled resolution or testing but does not by itself declare course support.
- **No universal coverage obligation**: The project does not promise support for every platform listed by an upstream product vendor.
- **Extensibility requirement**: Platform-specific behavior shall remain isolated so an additional approved profile can reuse stable lifecycle and adapter contracts.
- **Native bootstrap**: Prepare cannot require the manifest, a course runtime, a third-party package manager, or another lifecycle script before first use.
- **No distributed development dependency**: Student execution shall not depend on `scripts/.dev/` or a development-time generator.
- **Security**: Use least privilege, approved sources, integrity checks, argument-safe command execution, managed-path allowlists, and redaction.
- **Reliability**: Use idempotent operations, staging or atomic replacement where practical, bounded retries, locks, post-operation validation, and recoverable interruption handling.
- **Diagnostics**: Save logs under `~/it140/logs/` or the exact platform equivalent.
- **Course continuity**: An unsuccessful local lifecycle result must not imply that the student must stop coursework while the local environment is repaired; CVD remains the approved continuity option. A CVD failure must instead point to the applicable retry and support path.

## 8. Invalid Input and Error Cases

| Invalid Input or Error | Expected Program Response |
| --- | --- |
| Unsupported invocation, platform, release, architecture, or user context | Make no managed change, explain the mismatch, display profile-aware course-continuity guidance, log when possible, and return the documented nonzero code. |
| Missing privilege | Stop before the affected mutation, provide approved remediation or support guidance, display profile-aware course-continuity guidance, and return the permission code. |
| Missing or invalid manifest or schema | Stop before managed changes, identify the failed validation layer, preserve prior valid state, display profile-aware course-continuity guidance, and return the configuration-validation code. |
| Temporary network or source failure | Retry within the approved bound, preserve installed valid state after exhaustion, display remediation and the continuity notice, and return the external-service code. |
| User cancellation | Preserve prior valid state, skip dependent work, display profile-aware course-continuity guidance, and return the cancellation code unless a more serious result applies. |
| Interruption or partial completion | Clean safe temporary state, preserve recoverability, identify rerun or repair guidance, display profile-aware course-continuity guidance, and return the partial-result code. |
| Verification detects a required failure | Remain read-only, identify the owning lifecycle remediation, display profile-aware course-continuity guidance, and return the required-failure code. |

## 9. Ready-to-Design and Ready-to-Code Check

- [x] The stakeholder intent distinguishes portability-conscious design from universal platform support.
- [x] The designated course-supported deployment profile is the unit of support and qualification.
- [x] Technical compatibility alone does not create a course-support commitment.
- [x] Platform expansion is selective and based on course need, resources, qualification evidence, and approval.
- [x] Platform-dependent behavior is isolated without adding a student runtime dependency on development-only shared source.
- [x] Every unsuccessful managed lifecycle run includes specific remediation, the exact log path, and profile-aware course-continuity guidance.
- [x] The SRS, SDD, pseudoscripts, implementation, and tests can trace these decisions.

## Questions or Unclear Requirements

None for this analysis revision. Concrete wording may be adapted by platform, but every unsuccessful managed lifecycle conclusion must preserve the same course-continuity meaning.
