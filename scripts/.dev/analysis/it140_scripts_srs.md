# Software Requirements Specification

- **Course**: IT 140 - *Introduction to Scripting*
- **Activity**: Course Automation Script Development
- **Program Name**: IT 140 Course Automation Scripts
- **Document ID**: IT140-SRS-SCRIPTS
- **Status**: Draft for faculty review
- **Version**: 0.6.0
- **Version Date-Time Group**: 2026-08-07-10-44
- **Repository Baseline**: `GC-STEM/it140` commit `dbde859f90b1b957b05aa03e25b867563c113bb2`

## 0. General Description

### 0.1 Purpose

This Software Requirements Specification (SRS) defines what the **IT 140 Course Automation Scripts** package must do and the conditions it must satisfy. An SRS is an agreement about required software behavior. It describes the required results before developers choose the detailed design or write the final code.

The package supports the IT 140 course integrated development environment (IDE). An IDE is a collection of tools used to write, run, test, debug, and manage programs. The package consists of five coordinated platform implementations, listed in lifecycle order:

1. `prepare_it140.<ext>` provides the platform-native bootstrap commands that acquire or refresh the local course automation package and make the remaining lifecycle scripts available.
2. `install_it140.<ext>` establishes or repairs system-level software and settings.
3. `configure_it140.<ext>` establishes or repairs the current user's environment.
4. `verify_it140.<ext>` inspects the system and user layers without changing them.
5. `update_it140.<ext>` maintains approved course IDE software and course-managed assets over time.

On first use, the user copies and runs the documented `prepare_it140.<ext>` commands because the local package does not yet exist. After first use, the installed `prepare_it140.<ext>` artifact may be executed directly to refresh the automation package from the authorized course repository.

The five components form one software package because they share requirements, files, configuration data, logs, release information, and remediation paths. A **remediation path** is the recommended action for correcting a detected problem.

### 0.2 Product Scope

The package shall provide a consistent, supportable course integrated development environment (IDE) across designated course-supported deployment profiles. It shall reduce manual preparation, installation, and configuration steps, identify configuration problems, and provide useful diagnostic information to students, faculty, artificial intelligence (AI) support tools, and university technical support.

The requirements shall minimize unnecessary platform-specific assumptions and isolate platform-dependent behavior so that another deployment profile for which the complete required software stack has a viable implementation path can be added without redesigning the platform-independent lifecycle. The project is not required to discover, implement, test, or maintain every platform that upstream products might technically support. A deployment profile becomes course-supported only after its implementation, qualification testing, documentation, and approval are complete. Technical compatibility, vendor support, or successful unqualified use does not by itself imply course support.

The main body of this SRS defines stable capabilities, responsibility boundaries, and quality expectations without selecting a particular commercial or open-source product. The package shall use a shared **JavaScript Object Notation (JSON)** manifest. JSON is a plain-text data format that software can read and validate. The controlled manifest shall be the authoritative source for concrete approved products and services, vendor or project names, package and extension identifiers, versions or version ranges, approved distribution sources, supported platform releases, provider-specific integration rules, managed paths, and the current automation release.

The manifest is a **controlled configuration item**, meaning that proposed changes require review, testing, approval, and release tracking. A product or version may normally change through the manifest without changing this SRS when the required capability and constraints remain the same. A change that alters a required capability, user workflow, security boundary, or acceptance criterion also requires an SRS change.

The concrete reference environment used to review this SRS and design the initial acceptance tests is recorded in nonnormative Appendix A. Appendix A is informational and may become outdated; the current approved manifest controls implementation and deployment.

### 0.3 Intended Users and Stakeholders

| User or stakeholder | Primary use cases |
| --- | --- |
| IT 140 students | Prepare, install, configure, verify, and update their course environment. |
| IT 140 faculty | Use the same supported environment, review logs, and guide students. |
| Reference-platform administrators | Provision and maintain the shared reference environment. |
| University IT Service Desk | Use verification results and logs to diagnose problems. |
| AI support tools | Explain verification results and recommend approved remediation. |
| Computer science deans and subject matter experts (SMEs) | Approve, design, implement, test, and maintain the package and supporting files. |

### 0.4 Package Components and Responsibility Boundaries

**System-level** changes affect the operating system or all users of a computer. **User-specific** changes affect only the account running the script.

| Component | Primary responsibility | Expected user | May change system-level state? | May change user-specific state? |
| --- | --- | --- | ---: | ---: |
| `prepare_it140.<ext>` | Acquire or refresh the local automation package and make its scripts available. | Student or faculty standard user | No | Yes, only for course-managed files, logs, permissions, and user `PATH` entries |
| `install_it140.<ext>` | Install or repair the supported system-level course IDE. | Administrator or approved standard user with controlled privilege elevation | Yes | No, except for the minimum files required to create its own log |
| `configure_it140.<ext>` | Configure the current user's course environment and accounts. | Student or faculty user | No | Yes |
| `verify_it140.<ext>` | Inspect both layers and report results. | Student, faculty, AI support, or technical support | No | No |
| `update_it140.<ext>` | Update the supported environment and course-managed assets. | Student or faculty user with controlled privilege elevation when required | Yes | Yes, only for course-managed settings and tools |

### 0.5 Scope Exclusions

The package shall not:

- Create, solve, grade, or modify student programming assignments.
- Overwrite student programming-language source files, assignment repositories, version-control history, or Learning Management System (LMS) submissions. The package may create and identify the parent repository workspace but shall not recursively enumerate, rewrite, delete, move, permission-reset, or otherwise manage repositories or files stored inside that workspace.
- Store passwords, authentication tokens, browser session data, or other secrets.
- Perform an operating-system release upgrade unless a future approved requirement explicitly adds that capability.
- Provide general-purpose backup, reset, uninstall, or account-recovery functions.
- Treat student-selected optional software or unrelated user settings as course-managed assets.
- Require an existing course manifest, package manager, version-control client, or previously installed lifecycle script before the first-use preparation commands can run.

The **bootstrap command set** is the short, platform-native sequence represented by `prepare_it140.<ext>`. On first use, the sequence is copied and run as commands because the local package is not yet present. After installation, the same artifact may be executed directly to refresh the package.

### 0.6 Terms and Abbreviations

| Term | Definition and purpose in this SRS |
| --- | --- |
| AI | Artificial intelligence. AI support may interpret approved diagnostics but shall not receive secrets or unnecessary personal information. |
| Artifact | A versioned file or generated record created or maintained during analysis, design, construction, logging, testing, release, or maintenance. |
| API | Application Programming Interface. An API allows one program to request information or actions from another program or service. |
| Bootstrap command set | The first-use, platform-native commands represented by `prepare_it140.<ext>` that obtain or refresh the local automation package without depending on that package. |
| CLI | Command-Line Interface. A CLI is a text-based way to run and control software. |
| Controlled configuration item | A file or data set whose changes require review, testing, approval, and release tracking. The manifest is controlled because it selects the products and versions used by the package. |
| Course-supported deployment profile | A concrete local, virtual, or hosted environment—defined by operating-system family and release, architecture, deployment kind, desktop or session, and applicable platform implementation—that has completed required implementation, qualification testing, documentation, and approval for course use. |
| Platform implementation | One platform-native set of lifecycle scripts and adapters that may be reused by one or more deployment profiles. |
| Repository workspace | The current user's development workspace for assignment and project Git repositories. The standard path is `${HOME}/Repos` (or the exact native equivalent, such as `%USERPROFILE%\Repos` on Windows). Course automation owns only creation of the parent directory and explicitly defined desktop integrations; repository contents remain student-owned. |
| Exit code | A small integer returned when a script ends. Other programs and support tools use it to determine whether the run succeeded or why it failed. |
| GUI | Graphical User Interface. A GUI uses windows, icons, buttons, and menus rather than only typed commands. |
| IDE | Integrated Development Environment. It combines tools used to write, run, test, debug, and manage programs. |
| Idempotent | Safe to run repeatedly. An idempotent script reaches the required state without duplicating entries or damaging a correct configuration. |
| Least privilege | Giving a script only the permissions required for the current task. This limits the damage caused by mistakes or misuse. |
| Log or transcript | A timestamped text record of script actions and results. Logs support troubleshooting and auditing. |
| Lifecycle workflow | An approved ordered sequence of lifecycle components for a defined deployment profile, starting state, and operating role. A workflow does not remove or redefine the five lifecycle components. |
| Managed asset | A file, setting, package, launcher, extension, plug-in, or other item that the course automation is authorized to create, replace, update, or remove. |
| Manifest | The shared JSON file that defines the concrete approved environment, including products, versions, sources, settings, provider profiles, and managed paths. It prevents different scripts from using inconsistent requirements. |
| OS | Operating system. The OS manages computer hardware, files, applications, users, and permissions. |
| PATH | An operating-system setting that lists folders searched for executable commands. |
| PII | Personally Identifiable Information. PII is information that can identify a person, such as an email address. |
| Provider baseline master | The clean CVD provider image available to an authorized administrator before IT 140-specific system software is installed. |
| IT 140 course master | The CVD image after the administrator workflow has established and verified the approved IT 140 system layer; it is the starting image distributed to students. |
| Operating role | The authorized role selecting an applicable workflow, such as `local_user`, `cvd_administrator`, or `cvd_student`. |
| Provider profile | Manifest data that defines how the package interacts with an external service, including its CLI or API, authentication flow, account fields, and privacy-preserving identity rules. |
| QoS | Quality of Service. QoS requirements define measurable expectations for reliability, performance, error handling, and diagnostics. |
| Reference platform | The approved environment used for primary development, documentation, and acceptance testing. Its current products and versions are selected by the manifest. |
| Source-code hosting service | An external service that stores version-controlled repositories and may provide authentication, collaboration, and account APIs. |
| Semantic Versioning (SemVer) | A versioning scheme expressed as `MAJOR.MINOR.PATCH`. Incompatible changes increment MAJOR, backward-compatible functionality increments MINOR, and backward-compatible corrections increment PATCH. |
| SRS | Software Requirements Specification. It defines required software behavior and constraints. |
| Technical compatibility | Evidence that the required software stack might operate on a deployment profile. Technical compatibility does not establish implementation completeness, qualification, documentation, approval, or course support. |
| Version date-time group | The local date and 24-hour time, written as `YYYY-MM-DD-HH-MM`, at which a specific artifact version was created or approved. The date-time group supplements SemVer and does not determine version precedence. |
| Version-control system | Software that records file changes and preserves change history so earlier versions can be reviewed or restored. |

### 0.7 Requirement Conventions

Each mandatory requirement uses **shall** and has a unique identifier.

- `PKG-FR-###`: package-level functional requirement
- `PRE-FR-###`: prepare-script functional requirement
- `INS-FR-###`: install-script functional requirement
- `CFG-FR-###`: configure-script functional requirement
- `VER-FR-###`: verify-script functional requirement
- `UPD-FR-###`: update-script functional requirement
- `PKG-NFR-###`: package-level nonfunctional requirement
- `PKG-TC-###`: shared technology constraint
- `REF-TC-###`: reference-platform-specific technology constraint
- `PKG-QOS-###`: package-level quality-of-service constraint

A **functional requirement** states what the software shall do. A **nonfunctional requirement** states how well or under what general qualities it shall operate. A **technology constraint** limits the technologies or environment that may be used. A **Quality of Service (QoS) constraint** gives a measurable expectation for reliability, performance, security, or supportability.

A paragraph labeled **Why** explains the reason for a requirement. The explanation supports learning and review but does not replace the testable “shall” statement.

## 1. Functional Requirements

### 1.1 Package-Level Functional Requirements

The package shall:

- **PKG-FR-001** Provide one platform-native set of `prepare_it140.<ext>`, `install_it140.<ext>`, `configure_it140.<ext>`, `verify_it140.<ext>`, and `update_it140.<ext>` entry points for every platform implementation used by one or more designated course-supported deployment profiles. Multiple deployment profiles may reuse the same platform implementation.

  **Why:** Users and support personnel need the same five-stage lifecycle for every supported deployment profile without requiring duplicate script families for profiles that share the same native implementation.

- **PKG-FR-002** Use the filename pattern `<action>_it140.<ext>`, where `<action>` is `prepare`, `install`, `configure`, `verify`, or `update`, and `<ext>` is the platform-appropriate script extension. Each implementation shall reside in the approved platform directory.

  **Why:** Predictable names reduce user error and simplify documentation and support.

- **PKG-FR-003** Confirm that the running script matches the detected platform before making any change.

  **Why:** A script written for another operating system could fail or damage the environment.

- **PKG-FR-004** Read shared environment requirements from `~/it140/scripts/.manifest/it140_manifest.json` rather than maintaining independent authoritative software lists in each script.

  **Why:** One authoritative list prevents installation, configuration, verification, and maintenance from disagreeing.

- **PKG-FR-005** Validate the manifest before using its data. A script that requires the manifest shall stop safely when the manifest is missing, unreadable, or invalid.

  **Why:** Acting on incomplete or corrupted requirements could install the wrong software or change the wrong files.

- **PKG-FR-006** Display the script name, strict SemVer artifact version, version date-time group, detected platform, current user, start time, purpose, and log location near the beginning of each run.

  **Why:** Clear context helps beginners confirm that they started the correct tool and helps support personnel interpret the transcript.

- **PKG-FR-007** Save a timestamped transcript of each run under `~/it140/logs/` or the equivalent path derived from the current user's home folder.

  **Why:** A saved transcript allows a problem to be reviewed after the terminal window closes.

- **PKG-FR-008** End with a plain-language summary that identifies completed actions, warnings, failures, the log path, and the recommended next step.

  **Why:** Beginners should not need to interpret raw command output to know what to do next.

- **PKG-FR-009** Return a standardized exit code defined in Section 4.3.

  **Why:** Standard codes allow scripts, tests, AI support, and technical support tools to interpret results consistently.

- **PKG-FR-010** Preserve student work, assignment repositories, version-control history, optional extensions or plug-ins, and unrelated settings during every package operation.

  **Why:** Course automation must not put coursework or personal configuration at risk.

- **PKG-FR-022** Resolve and report the approved lifecycle workflow from the detected deployment profile, recognized starting state, and authorized operating role. The package shall preserve the local workflow `Prepare → Install → Configure → Verify`, define the CVD administrator workflow `Prepare → Update (initial provider baseline) → Install → Configure → Verify`, define the CVD student workflow `Prepare → Update (initial course master) → Configure → Verify`, and treat later Update runs as periodic maintenance.

  **Why:** Hosted image preparation and student initialization begin from different managed states even though both use the same five lifecycle components.

- **PKG-FR-023** Distinguish an **initial baseline update** from a **periodic maintenance update** in user output, logs, workflow resolution, and acceptance evidence. Initial baseline update shall bring the current image to the approved maintenance baseline without performing Install or Configure responsibilities; periodic maintenance shall maintain an already provisioned environment.

  **Why:** The word “update” otherwise hides materially different starting conditions and can make support instructions ambiguous.

- **PKG-FR-021** Whenever a managed lifecycle run ends with a nonzero exit code or a noncompliant result, display plain-language, profile-aware course-continuity guidance. If the affected environment is not CVD, or cannot be confirmed as CVD, tell the user they can continue their IT 140 coursework in CVD while the local course IDE issue is resolved. If CVD itself is affected, state that the issue affects CVD and direct the user to the applicable remediation and support path. The guidance shall supplement, not replace, the specific remediation and exact log path.

  **Why:** A local automation problem should not prevent a student from continuing required coursework, and a CVD failure should not misleadingly present the affected environment as its own alternative.

### 1.2 Prepare Script Requirements

The prepare component shall:

- **PRE-FR-001** Provide a platform-native first-use command set represented by `prepare_it140.<ext>` that can be copied and run without requiring the local IT 140 package to exist.

  **Why:** The first-use commands must bootstrap the package before any installed course script is available.

- **PRE-FR-002** Permit the installed `prepare_it140.<ext>` artifact to be executed directly after first use to refresh the local automation package.

  **Why:** Students and support personnel need a simple way to obtain corrected lifecycle scripts and controlled package files.

- **PRE-FR-003** Use only platform-native utilities expected on the supported baseline and shall not depend on the controlled manifest, a third-party package manager, a version-control client, or another lifecycle script.

  **Why:** Those dependencies may not exist until after the package has been prepared and installed.

- **PRE-FR-004** Confirm the supported operating-system family, any required processor architecture, and the approved standard-user privilege context before replacing local package files.

  **Why:** Preparation must stop safely when the commands are run on the wrong platform or with an unsafe privilege context.

- **PRE-FR-005** Derive the current user's home folder, create `~/it140/`, `~/it140/logs/`, and a unique temporary staging location as needed, and preserve existing contents not owned by the course automation.

  **Why:** Preparation must work for different account names and must not erase student work.

- **PRE-FR-006** Create a timestamped preparation log under `~/it140/logs/` and record the artifact SemVer version, version date-time group, current user, purpose, and exact log path before network retrieval begins.

  **Why:** First-use and refresh failures must be diagnosable even when later lifecycle scripts are unavailable.

- **PRE-FR-007** Download the current approved repository archive from the authorized course source over an encrypted connection using bounded retries and a unique temporary file.

  **Why:** Bounded retries tolerate temporary network failures without allowing an incomplete download to become the installed package.

- **PRE-FR-008** Extract the archive to a temporary staging location and verify that it contains the expected platform script directory and every lifecycle entry point required by the selected workflow before refreshing the course root.

  **Why:** A structurally incomplete or incorrect archive must not replace a usable package.

- **PRE-FR-009** Copy or refresh repository-managed files under `~/it140/` without deleting user-owned files, assignment content, or nested student repositories.

  **Why:** Refreshing automation assets must not endanger coursework.

- **PRE-FR-010** Remove only the downloaded package's top-level repository metadata from `~/it140/` and shall not remove version-control metadata from nested student repositories.

  **Why:** The installed course root is not intended to remain a clone of the main course repository, but student repositories must be preserved.

- **PRE-FR-011** Apply required script permissions and add the matching platform script directory to the current process and future user `PATH` configuration without creating duplicate entries.

  **Why:** The remaining lifecycle scripts must be available immediately and after a new terminal session begins.

- **PRE-FR-012** Remove temporary archives and extraction directories after success, failure, cancellation, or interruption when safe to do so.

  **Why:** Temporary package files should not consume space or expose stale content.

- **PRE-FR-013** Report the installed course root, preparation log path, resolved workflow identifier, workflow starting state, operating role, and exact next-step command after successful preparation. The default local next step shall remain `install_it140.<ext>`; both approved CVD initial workflows shall identify `update_it140.sh` as the next step.

  **Why:** Beginners and administrators need an unambiguous transition that matches the actual deployment state rather than a universal hard-coded Install transition.

- **PRE-FR-014** Preserve the prior valid local package when download, extraction, or structural validation fails and shall return a nonzero result with a plain-language explanation.

  **Why:** A failed refresh must not leave the user with a partially replaced automation package.

- **PRE-FR-015** Limit managed changes to retrieving or refreshing the automation package, writing its log, setting required script permissions, and establishing its user `PATH` entry; it shall not install course IDE software, authenticate external services, or configure IDE settings.

  **Why:** System installation and user configuration belong to later lifecycle stages.

### 1.3 Install Script Requirements

The install script shall:

- **INS-FR-001** Verify the supported operating-system release, processor architecture, available disk space, network access, and required administrative capability before beginning installation.

  **Why:** Early prerequisite checks prevent a long installation from failing after it has already changed the system.

- **INS-FR-002** Stop without making system changes when the detected platform is unsupported or the required administrative capability is unavailable.

  **Why:** Safe refusal is better than an incomplete or incorrect installation.

- **INS-FR-003** Install or repair the system-level applications, language runtimes, package managers, command-line tools, and operating-system packages declared by the manifest.

  **Why:** Install owns the shared software layer used by every course user on that computer.

- **INS-FR-004** Obtain software only from approved sources declared by the manifest or trusted operating-system repositories.

  **Why:** Approved sources reduce the risk of altered or malicious installers.

- **INS-FR-005** Configure required system package repositories, signing keys, certificates, and system policies before installing dependent software.

  **Why:** Package managers need trusted source information to verify and update software correctly.

- **INS-FR-006** Bring the supported operating-system packages to the approved baseline without upgrading the computer to a different operating-system release.

  **Why:** Security and compatibility updates are needed, but release upgrades can introduce untested changes.

- **INS-FR-007** Install system-level course integrations declared by the manifest, such as managed browser policies or system application registrations.

  **Why:** Some course features must be available to all users and therefore belong in install rather than user configuration.

- **INS-FR-008** Verify that each required system command is available and that installed versions meet the manifest requirements before reporting success.

  **Why:** A successful installer command does not always guarantee that the installed tool can run.

- **INS-FR-009** Be idempotent: rerunning install on a compliant system shall not duplicate repositories, keys, packages, policies, or other entries.

  **Why:** Install also serves as the approved repair method for missing system components.

- **INS-FR-010** Repair a missing or damaged course-managed system component when rerun, without resetting unrelated operating-system settings.

  **Why:** Users need a safe repair path that does not require a separate repair script.

- **INS-FR-011** Avoid source-code-hosting authentication, version-control identity configuration, user-specific IDE settings, user-scoped extensions or plug-ins, and other personal configuration.

  **Why:** These items belong to the individual account and are the responsibility of `configure_it140.<ext>`.

- **INS-FR-012** Recommend running the matching `configure_it140.<ext>` script after successful system installation.

  **Why:** System installation alone does not complete the current user's course environment.

### 1.4 Configure Script Requirements

The configure script shall:

- **CFG-FR-001** Run as the standard student or faculty account and refuse direct execution as the root or system-administrator account unless a platform-specific design explicitly requires it.

  **Why:** Personal settings and authentication must be saved to the intended user's account.

- **CFG-FR-002** Verify that required system-level components are present before changing user configuration.

  **Why:** User configuration cannot succeed reliably when installation is incomplete.

- **CFG-FR-003** Create the required course folders under the current user's home folder, including `~/it140/` and `~/it140/logs/`, without deleting existing contents.

  **Why:** A consistent folder structure simplifies instructions while preserving prior work.

- **CFG-FR-004** Add the correct platform script folder to the user's `PATH` without adding duplicate entries.

  **Why:** Users should be able to run the course scripts by name from a terminal.

- **CFG-FR-005** Check the current source-code-hosting CLI authentication status using the provider profile declared by the manifest and start the approved interactive authentication flow only when authentication is missing or invalid.

  **Why:** Requiring a new login on every run wastes time and may confuse users.

- **CFG-FR-006** Explain each required external-service authentication action in plain language and handle cancellation without treating it as successful configuration.

  **Why:** First-term students may be unfamiliar with device codes, browser authentication, and terminal prompts.

- **CFG-FR-007** Obtain the authenticated account data required by the provider profile through the approved API and apply the provider-specific privacy-preserving commit identity rule declared by the manifest, without asking the user to type values that can be obtained reliably.

  **Why:** Automated retrieval reduces typing errors and applies the approved privacy rule without exposing the student's personal contact information.

- **CFG-FR-008** Allow the user to accept the authenticated account username as the version-control display name or enter a different professional display name.

  **Why:** A version-control display name identifies the author of changes and may differ from the hosted account username.

- **CFG-FR-009** Apply the course-required version-control settings declared by the manifest, including the default branch, text line endings, automatic upstream configuration, and the approved IDE or editor for version-control messages.

  **Why:** Shared version-control settings make submissions and collaboration more consistent across platforms.

- **CFG-FR-010** Install or repair the required user-scoped programming-language tools and IDE extensions or plug-ins declared by the manifest.

  **Why:** These tools are associated with the current account and may not be installed system-wide.

- **CFG-FR-011** Merge course-required IDE settings into the user's existing settings without discarding unrelated valid settings.

  **Why:** Students may already use the approved IDE or editor for other courses or personal work.

- **CFG-FR-012** Derive user paths from the current home folder and shall not hardcode a username or home-directory path.

  **Why:** The same script must work for different account names.

- **CFG-FR-013** On a supported graphical desktop, preserve any existing course-root desktop integration unless it is explicitly obsolete and automation-managed; new student development navigation shall use the repository workspace integration defined by CFG-FR-019 rather than creating a new course-root shortcut.

  **Why:** A direct repository-workspace shortcut reduces file-navigation errors while keeping student development work separate from course-managed automation files.

- **CFG-FR-014** Configure manifest-approved IDE settings without forcing the course automation root to become the student's default development workspace. Profile-owned IDE launch behavior shall follow the repository-workspace rule in CFG-FR-021 where applicable.

  **Why:** Separating IDE development work from the course automation root reduces accidental edits to course-managed files and reinforces a clear Git repository workflow.

- **CFG-FR-015** Validate the resulting version-control client, source-code-hosting CLI, programming-language runtime and tools, IDE, extensions or plug-ins, course-folder configuration, repository workspace, applicable desktop integration, and profile-owned IDE launch behavior before reporting success.

  **Why:** Configuration is complete only when the resulting settings and managed integrations can be read and used.

- **CFG-FR-016** Be idempotent and preserve user-selected optional extensions and unrelated preferences when rerun.

  **Why:** Configure also serves as the approved repair method for user-specific settings.

- **CFG-FR-017** Recommend running the matching `verify_it140.<ext>` script after successful configuration.

- **CFG-FR-018** Create or preserve the current user's repository workspace at `${HOME}/Repos` or the exact platform-equivalent path. Configure shall create the parent directory when missing but shall not traverse or modify existing child repositories or files.

- **CFG-FR-019** On a supported graphical desktop, create or repair a desktop shortcut or link named `Repos` that resolves to the repository workspace. If an unrelated non-managed item already uses the required shortcut name, Configure shall preserve it and report the conflict rather than overwrite it.

- **CFG-FR-020** Apply a platform-appropriate repository-workspace visual treatment without substituting an application icon for a folder. The Codio Virtual Desktop (CVD) Xfce implementation shall apply the native `development` emblem. Windows bare metal shall retain the normal Windows folder appearance for the repository workspace and desktop `Repos` shortcut. Other qualified graphical desktop implementations may use an approved development or code-oriented folder icon or emblem when safely available; an implementation may report this visual-only integration as `NOT APPLICABLE` when its platform supplement documents that no safe supported native mechanism exists.

- **CFG-FR-021** Configure profile-owned Visual Studio Code desktop launch behavior so students can open the repository workspace directly. On the CVD, Configure shall repair the existing course-provided Visual Studio Code launcher to open the repository workspace as the active folder and shall not create a duplicate when the expected launcher is missing. On Windows bare metal, Configure shall create or repair a course-owned desktop shortcut named `Visual Studio Code - IT 140` that launches Visual Studio Code with `%USERPROFILE%\Repos` as both the active folder argument and working directory while preserving unrelated Visual Studio Code shortcuts.

  **Why:** Course-owned launchers should take students directly to the directory intended for assignment and project repositories without exposing course-managed automation files as the normal coding workspace or overwriting unrelated user shortcuts.

### 1.5 Verify Script Requirements

The verify script shall:

- **VER-FR-001** Operate in read-only mode and shall not install, update, remove, repair, or rewrite software or settings.

  **Why:** Verification must be safe to run during troubleshooting and must not hide the original problem by changing it.

- **VER-FR-002** Run without administrative privilege.

  **Why:** Students and support personnel should be able to collect diagnostics safely.

- **VER-FR-003** Validate the manifest and identify the automation SemVer release and release date used for comparison.

  **Why:** Verification results are meaningful only when compared with a known set of requirements.

- **VER-FR-004** Check the detected operating system, release, processor architecture, current user, available disk space, required permissions, and required network reachability.

  **Why:** Environment problems may exist even when individual applications are installed.

- **VER-FR-005** Check the presence and required versions of all system applications, command-line tools, language runtimes, package managers, and operating-system packages declared by the manifest.

  **Why:** Missing or incompatible versions can prevent course activities from working.

- **VER-FR-006** Check required programming-language packages, IDE extensions or plug-ins, version-control settings, source-code-hosting authentication status, IDE settings, script permissions, course folders, repository-workspace integration, and any profile-owned IDE launch target or argument on supported graphical desktops.

  **Why:** Verification must cover both the system-level and user-specific layers.

- **VER-FR-007** Validate the format and safe values of managed configuration files without displaying secrets or complete personally identifiable information (PII).

  **Why:** Support diagnostics must be useful without exposing private data.

- **VER-FR-008** Report each check as `PASS`, `WARNING`, `FAIL`, or `NOT APPLICABLE`.

  **Why:** Consistent result labels make the report easier to scan and interpret.

- **VER-FR-009** Identify the related requirement and recommend `prepare_it140.<ext>`, `install_it140.<ext>`, `configure_it140.<ext>`, or `update_it140.<ext>` for every failed required check.

  **Why:** A diagnosis is most useful when it tells the user how to correct the problem.

- **VER-FR-010** Distinguish a required failure from an optional recommendation.

  **Why:** Students should not be told that the course environment is unusable because an optional feature is missing.

- **VER-FR-011** Display totals for passed, warning, failed, and not-applicable checks at the end of the run.

  **Why:** A summary helps users quickly understand the overall result.

- **VER-FR-012** Return the standardized exit code that represents the most serious result.

  **Why:** Support tools need a reliable machine-readable result in addition to the human-readable report.

- **VER-FR-013** Save a sanitized verification transcript and, when explicitly requested, create a sanitized support bundle containing only approved diagnostic files.

  **Why:** A support bundle can speed troubleshooting, but it must not collect unnecessary personal or course data.

- **VER-FR-014** Identify unsupported conditions that the scripts cannot safely repair and direct the user to the appropriate support channel.

- **VER-FR-015** Check that the repository workspace exists at the required native path and is accessible to the current user without creating files or changing permissions.

- **VER-FR-016** Check that the desktop `Repos` shortcut or link resolves to the repository workspace without modifying the shortcut, link, or workspace.

- **VER-FR-017** Check the platform-approved repository-workspace visual treatment when that integration is applicable. On Windows bare metal, Verify shall confirm that stale course-managed application-icon metadata is not applied to the repository workspace. Report `NOT APPLICABLE` rather than failure only when the platform design explicitly declares the visual treatment unsupported.

- **VER-FR-018** Check profile-owned Visual Studio Code desktop launch behavior read-only. On the CVD, Verify shall check that the existing Visual Studio Code desktop launcher opens the repository workspace and does not target the course automation root. On Windows bare metal, Verify shall check that `Visual Studio Code - IT 140` launches Visual Studio Code with the repository workspace as both its active folder argument and working directory.

  **Why:** Some failures require platform administration rather than another script run.

### 1.6 Update Script Requirements

The update script shall:

- **UPD-FR-001** Verify the supported platform, current user, available disk space, network access, and required privilege-elevation capability before beginning changes.

  **Why:** Updating a partially supported environment can leave it less usable than before.

- **UPD-FR-002** Prevent more than one copy of the update script from changing the same environment at the same time.

  **Why:** Concurrent package or file updates can corrupt state or produce inconsistent results.

- **UPD-FR-003** Obtain the latest approved manifest and course-managed maintenance assets within the update scope from the authorized course source.

  **Why:** The update stage maintains the installed course IDE, while `prepare_it140.<ext>` remains the approved mechanism for refreshing the lifecycle script package itself.

- **UPD-FR-004** Download managed assets to a temporary staging location, validate them, and replace installed assets only after validation succeeds.

  **Why:** Staging prevents a failed or incomplete download from replacing a working file.

- **UPD-FR-005** Preserve the previous valid copy of a replaced managed asset until the new copy has been installed successfully.

  **Why:** A recoverable update is safer than an in-place overwrite.

- **UPD-FR-006** Refresh operating-system package information and install approved security, maintenance, and course-software updates.

  **Why:** Supported environments need current fixes and compatible tool versions.

- **UPD-FR-007** Not upgrade the computer to a different operating-system release.

  **Why:** A new release may not have been tested with the course IDE.

- **UPD-FR-008** Update or repair required programming-language tools and IDE extensions or plug-ins declared by the manifest.

  **Why:** Required tools must remain compatible with course activities.

- **UPD-FR-009** Preserve optional extensions and shall not remove them unless the user explicitly requests removal outside this package.

  **Why:** Optional extensions belong to the user, not the course automation.

- **UPD-FR-010** Remove obsolete course-managed components only when the manifest explicitly identifies them as obsolete and the target is within an approved managed path.

  **Why:** Explicit cleanup rules prevent accidental deletion of user files.

- **UPD-FR-011** Perform only safe package-cache and dependency cleanup that does not remove required course software or student work.

  **Why:** Cleanup should recover space without creating a new support problem.

- **UPD-FR-012** Use retry and clear failure handling for temporary network or package-source failures.

  **Why:** Brief internet failures should not require a complete manual recovery.

- **UPD-FR-013** Run post-update checks for required commands, versions, packages, extensions, managed assets, and package-manager consistency.

  **Why:** The updater must confirm that the final environment is usable.

- **UPD-FR-014** Report whether an application restart, sign-out, virtual-machine restart, or computer restart is required.

  **Why:** Some updates are not active until a process or system restarts.

- **UPD-FR-015** Be safely rerunnable after an interrupted or partially completed update.

  **Why:** Power, network, or session interruptions should have an approved recovery path.

- **UPD-FR-016** Recommend running the matching verify script after an update that reports a warning, failure, or required restart.

  **Why:** Verification confirms the final state after maintenance.

### 1.7 Shared Manifest and Managed-Asset Requirements

The package shall:

- **PKG-FR-011** Store the shared manifest as valid UTF-8 JSON at `~/it140/scripts/.manifest/it140_manifest.json`.

  **Why:** A standard text format can be read on all supported platforms and reviewed in source control.

- **PKG-FR-012** Include a manifest schema version, strict SemVer automation package release, and separate `YYYY-MM-DD` automation release date.

  **Why:** Scripts must know whether they understand the manifest structure, which release they are applying, and when that release was issued.

- **PKG-FR-013** Define each recognized platform implementation and deployment profile in the manifest, including the platform abbreviation, applicable operating-system releases, architectures, deployment constraints, platform script directory, platform script extension, and enabled state. Manifest enablement shall permit controlled resolution or qualification use but shall not by itself declare a deployment profile course-supported.

  **Why:** Platform resolution and course support must be explicit, bounded, and testable, while allowing qualification-only profiles to reuse an enabled implementation without being represented as student-supported.

- **PKG-FR-014** Define each required software or service capability and, for every concrete approved product, its product identifier, version rule, installation scope, verification method, and approved source in the manifest.

  **Why:** The same requirements must drive installation, verification, and update.

- **PKG-FR-015** Define provider profiles, required version-control and IDE settings, file associations, the course root, and release-selected managed integrations and paths in the manifest. Stable lifecycle-owned paths whose values are not release selections, including the `${HOME}/Repos` repository-workspace contract, may be specified by this SRS and the SDD rather than duplicated as manifest data. A provider profile shall identify the approved CLI or API, authentication flow, required account fields, and privacy-preserving commit identity rule.

  **Why:** User configuration and verification need one shared target state.

- **PKG-FR-016** Define the standard log directory, minimum free disk space, approved source locations, and managed-asset validation data in the manifest.

  **Why:** Operational and security rules should not be duplicated across scripts.

- **PKG-FR-017** Define obsolete managed components and their approved removal paths in the manifest.

  **Why:** Update must know exactly what it is authorized to remove.

- **PKG-FR-018** Contain no password, authentication token, private key, personal email address, or other secret.

  **Why:** The manifest is stored in a public course repository and copied to student computers.

- **PKG-FR-019** Be validated against an approved schema or equivalent structural validation before a script acts on its contents.

  **Why:** Structural validation detects missing, misspelled, or incorrectly typed fields.

- **PKG-FR-020** Treat files outside declared managed paths as user-owned and outside the package's authority.

  **Why:** A clear ownership boundary protects coursework and unrelated files.

## 2. Nonfunctional Requirements

### 2.1 Package-Level Requirements

The package shall:

- **PKG-NFR-001** Use consistent script structure, terminology, status labels, exit codes, log fields, and user-message patterns across all platforms.

  **Why:** Consistency lowers the learning burden and makes support documentation reusable.

- **PKG-NFR-002** Present student-facing instructions at approximately a ninth-grade reading level while retaining correct industry terminology.

  **Why:** IT 140 is a first programming course with students from many academic and technical backgrounds.

- **PKG-NFR-003** Define an abbreviation or specialized technical term when it first appears in student-facing output.

  **Why:** Beginners should not need outside knowledge to follow the required course IDE lifecycle.

- **PKG-NFR-004** Use deterministic logic wherever practical. The same supported starting state and inputs shall produce the same required final state.

  **Why:** Predictable behavior makes testing and troubleshooting easier.

- **PKG-NFR-005** Separate required behavior from optional enhancements in code, messages, logs, and tests.

  **Why:** Optional features must not prevent students from completing course work.

### 2.2 Usability

The package shall:

- **PKG-NFR-006** Display numbered stages or clearly named sections for multi-step operations.

  **Why:** Visible structure helps users understand progress and locate the step that failed.

- **PKG-NFR-007** State required user actions before displaying an interactive prompt.

  **Why:** Users need context before they choose or type an answer.

- **PKG-NFR-008** Use `INFO`, `SUCCESS`, `NOTICE`, `WARNING`, and `ERROR` consistently and shall not rely on color alone to communicate meaning.

  **Why:** Text labels remain understandable in plain logs and for users with color-vision differences.

- **PKG-NFR-009** Avoid false progress indicators. Any percentage or progress bar shall be based on completed work rather than an arbitrary timer.

  **Why:** A timed animation may report progress that has not actually occurred.

- **PKG-NFR-010** Provide copyable remediation commands using the installed script names and shall identify where the user should run them.

  **Why:** Concrete commands reduce transcription and navigation errors.

- **PKG-NFR-011** Avoid clearing the terminal or hiding earlier error information unless the user explicitly requests a clean display.

  **Why:** Earlier output may contain information needed for troubleshooting.

### 2.3 Maintainability and Testability

The package shall:

- **PKG-NFR-012** Keep authoritative product names, versions, package and extension identifiers, platform-release data, provider-specific rules, source locations, and managed paths in the manifest and avoid duplicated hardcoded lists that can drift apart.

  **Why:** A change should be made once and used by all five scripts.

- **PKG-NFR-013** Organize each script into small, purpose-specific functions or equivalent units with descriptive names.

  **Why:** Small units are easier to review, test, reuse, and repair.

- **PKG-NFR-014** Include comments that explain important intent, safety boundaries, and non-obvious decisions rather than restating each command.

  **Why:** Maintainers need to understand why a design choice exists.

- **PKG-NFR-015** Assign every controlled design artifact, construction artifact, testing artifact, and maintenance artifact its own strict SemVer `MAJOR.MINOR.PATCH` version and a separate `YYYY-MM-DD-HH-MM` version date-time group. Incompatible changes shall increment MAJOR, backward-compatible functionality shall increment MINOR, and backward-compatible corrections shall increment PATCH. Generated logs, transcripts, support-bundle inventories, and test results shall record the SemVer version and version date-time group of the producing or evaluated script, package, manifest, test definition, or other governing artifact. A version date-time group shall supplement SemVer and shall not replace it or determine version precedence.

  **Why:** Developers, testers, faculty, and support personnel must be able to identify exactly which approved artifacts produced, tested, or governed a result.

- **PKG-NFR-016** Support automated tests for manifest parsing, platform detection, managed-path validation, exit codes, redaction, and idempotence.

  **Why:** Safety-critical logic should be tested without requiring a full manual installation for every change.

- **PKG-NFR-017** Pass the approved static-analysis tool for its scripting language with no unresolved high-severity findings.

  **Why:** Static analysis detects common errors before a script is run.

### 2.4 Portability

The package shall:

- **PKG-NFR-018** Maintain one platform-agnostic design for the five lifecycle operations and isolate platform-, package-manager-, desktop-, provider-, and product-dependent behavior behind reviewed interfaces or equivalent boundaries.

  **Why:** Stable lifecycle logic and explicit boundaries reduce inconsistent behavior without requiring one distributed cross-platform runtime.

- **PKG-NFR-019** Derive home, desktop, temporary, configuration, and executable paths from the running environment rather than assuming a specific username.

  **Why:** Account names and standard folders vary across computers and platforms.

- **PKG-NFR-020** Quote or otherwise safely handle paths that contain spaces or special characters.

  **Why:** Paths on supported operating systems may include spaces or special characters.

- **PKG-NFR-021** Produce equivalent required outcomes on all supported platforms even when the implementation commands differ.

  **Why:** Students should receive the same course capabilities regardless of platform.

- **PKG-NFR-028** Minimize unnecessary platform-specific assumptions so that an additional designated deployment profile can reuse the platform-independent lifecycle, an existing platform implementation, and existing adapter contracts without redesigning the package core. This requirement does not obligate the project to implement or qualify every technically compatible deployment profile.

  **Why:** The package should remain extensible while keeping implementation, testing, documentation, and maintenance commitments within available course resources.

### 2.5 Privacy and Security

The package shall:

- **PKG-NFR-022** Follow least privilege and elevate permission only for the specific system-level command that requires it.

  **Why:** Running an entire script with administrator rights increases risk.

- **PKG-NFR-023** Validate all user input, manifest paths, downloaded file names, and managed removal targets before use.

  **Why:** Validation prevents malformed data from becoming a command or unsafe file operation.

- **PKG-NFR-024** Use encrypted network connections and approved source verification, such as package signatures, checksums, or equivalent integrity controls.

  **Why:** The package must detect altered or incomplete downloads.

- **PKG-NFR-025** Exclude passwords, tokens, private keys, browser data, complete personal email addresses, and other secrets or unnecessary PII from terminal output, logs, and support bundles.

  **Why:** Diagnostic information may be shared with instructors, AI tools, or technical support.

- **PKG-NFR-026** Set log and temporary-file permissions so that other local users cannot read sensitive diagnostic data when the platform supports per-user permissions.

  **Why:** Logs may contain usernames, paths, versions, and configuration details.

- **PKG-NFR-027** Delete temporary files that contain downloaded or generated configuration data after successful use and safe error handling.

  **Why:** Unneeded temporary files create privacy, security, and storage risks.

## 3. Technology Constraints

### 3.1 Shared Technology Constraints

The package shall:

- **PKG-TC-001** Use a platform-native scripting language approved for the target operating system.

  **Why:** Native tools reduce prerequisites and simplify execution for beginners.

- **PKG-TC-002** Use only software and services available to students without an additional course-related fee.

  **Why:** Every enrolled student must be able to complete course work without purchasing development software.

- **PKG-TC-003** Store source scripts and text configuration in UTF-8 with Line Feed (LF) line endings as defined by the repository's approved text-file policy.

  **Why:** Consistent line endings reduce cross-platform script and submission problems.

- **PKG-TC-004** Use JSON for the shared manifest and validate it before use.

  **Why:** JSON is readable, portable, and supported by all target scripting environments.

- **PKG-TC-005** Store logs and support bundles under the current user's `~/it140/logs/` folder or the exact platform-equivalent path derived from the home folder.

  **Why:** A standard location helps students and support personnel find diagnostic files.

- **PKG-TC-006** Mark only designated deployment profiles as course-supported when their operating-system releases still receive approved security updates and the complete profile has been implemented, qualified, documented, and approved for IT 140.

  **Why:** Upstream product compatibility is not sufficient evidence that the complete course environment is secure and supportable.

- **PKG-TC-007** Use the course-required programming-language implementation and major and minor version declared by the manifest and aligned with the version used by required course activities.

  **Why:** Matching programming-language versions reduces differences between demonstrations, tests, and student results.

- **PKG-TC-008** Use the concrete products declared by the manifest for required capabilities such as version control, source-code hosting, programming-language execution, test running, coverage reporting, code-quality checking and formatting, source-code editing or IDE functions, diagram editing, spelling support, and document viewing.

  **Why:** The capabilities support version control, programming, provided tests, code quality, and course file formats while allowing approved products to change without rewriting the SRS.

- **PKG-TC-009** Use the current user's home folder as the base for user-owned course files and shall not require a fixed account name.

  **Why:** The package must work for different students and faculty accounts.

### 3.2 Reference Platform Constraints

The reference-platform implementation shall:

- **REF-TC-001** Target the approved reference-platform type, operating-system release, processor architecture, and graphical or remote-session environment declared by the manifest.

- **REF-TC-002** Use the platform-native scripting language and system package manager declared by the manifest.

- **REF-TC-003** Run student-facing scripts as the standard user and use only the manifest-approved controlled privilege-elevation mechanism for specific system-level commands.

- **REF-TC-004** Avoid restarting an active graphical desktop, virtual machine, or remote-display service during an update. When a restart is required, the script shall instruct the user to save work and use the approved platform restart control.

- **REF-TC-005** Derive user paths from the running environment and shall not hardcode a user name or home-directory path.

- **REF-TC-006** Place system-wide policies, package sources, and application registrations in `install_it140.<ext>`, while placing user preferences, user launchers, IDE settings, and user-scoped extensions or plug-ins in `configure_it140.<ext>`.

- **REF-TC-007** Obtain products only through the vendor, project, operating-system, or institutional distribution channels approved by the manifest.

### 3.3 Additional Course-Supported Deployment Profiles

The package is designed so additional deployment profiles can be considered selectively when course need and available implementation, testing, documentation, and support resources justify the work. The project is not required to identify or qualify every deployment profile that upstream products might technically support. Technical compatibility, vendor documentation, or successful unqualified use shall not be represented as course support.

A new deployment profile shall not be marked course-supported until it:

- Implements all applicable requirements in this SRS.
- Provides `prepare_it140.<ext>`, `install_it140.<ext>`, `configure_it140.<ext>`, `verify_it140.<ext>`, and `update_it140.<ext>` in the approved platform directory.
- Has an approved platform abbreviation and native script extension.
- Documents the first-use `prepare_it140.<ext>` command set and later direct-refresh use.
- Has platform-specific technology constraints.
- Passes the full acceptance-test set on a clean supported environment.
- Produces equivalent required outcomes to the reference platform.

## 4. Quality of Service Constraints

### 4.1 Reliability and Idempotence

The package shall:

- **PKG-QOS-001** Make `prepare_it140.<ext>`, `install_it140.<ext>`, `configure_it140.<ext>`, and `update_it140.<ext>` idempotent.

- **PKG-QOS-002** Keep `verify` read-only, including when a check fails.

- **PKG-QOS-003** Leave the environment in a recoverable state after an interruption, failed download, failed package operation, or user cancellation.

- **PKG-QOS-004** Use staged or atomic replacement for course-managed files. An atomic replacement makes the complete new file visible at once instead of exposing a partially written file.

- **PKG-QOS-005** Prevent concurrent operations when simultaneous execution could corrupt package-manager, manifest, or managed-file state.

- **PKG-QOS-006** Preserve an already compliant required component when another independent component fails.

### 4.2 Performance and User Feedback

The package shall:

- **PKG-QOS-007** Display identifying information and the first meaningful status message within five seconds under normal supported conditions.

- **PKG-QOS-008** Avoid more than 60 seconds of silent operation during a long-running prepare, install, or update operation. The component shall display a truthful status message when the underlying tool does not provide visible progress.

- **PKG-QOS-009** Complete verification within 90 seconds on the approved reference environment when required services are responsive and no support bundle is requested.

- **PKG-QOS-010** Avoid repeated downloads or installations when a compliant component can be verified locally.

### 4.3 Error Handling and Exit Codes

The package shall:

- **PKG-QOS-011** Stop a dependent stage after a required prerequisite fails while continuing only independent checks or cleanup that are safe.

- **PKG-QOS-012** Report the failed stage, a plain-language description, the underlying command or check when safe to disclose, and the recommended remediation.

- **PKG-QOS-013** Preserve the original nonzero result when error handling or log cleanup runs.

- **PKG-QOS-014** Use the following exit codes consistently:

| Exit code | Meaning |
| ---: | --- |
| `0` | All required operations or checks completed successfully. Informational restart guidance may still be present. |
| `1` | One or more required operations or checks failed. |
| `2` | Invalid use, unsupported platform, or unsupported operating-system release. |
| `3` | Required permission or privilege was unavailable. |
| `4` | An approved external source, network service, or package service was unavailable after retries. |
| `5` | The manifest or a course-managed asset was missing, invalid, corrupt, or failed integrity validation. |
| `6` | The user canceled a required interactive operation. |
| `7` | The run completed only partially and must be rerun or remediated before the environment is considered compliant. |

- **PKG-QOS-015** Use the most serious applicable exit code when more than one problem is detected.

### 4.4 Logging and Diagnostics

The package shall:

- **PKG-QOS-016** Create a unique timestamped log for each run using the action name, platform, date, and time.

- **PKG-QOS-017** Record the producing script or component SemVer version and version date-time group, manifest SemVer release and release date when available, platform, operating-system version, architecture, current user identifier, start time, end time, elapsed time, major stages, results, and final exit code.

- **PKG-QOS-018** Record enough version, path, permission, and configuration information to diagnose failures while following the redaction rules in `PKG-NFR-025`.

- **PKG-QOS-019** Write logs as readable UTF-8 plain text and keep the terminal output understandable when ANSI color codes are unavailable.

- **PKG-QOS-020** State the exact log path in the opening information and final summary.

- **PKG-QOS-021** Create a support bundle only after an explicit command option or user confirmation and list the files included before final creation.

- **PKG-QOS-022** Exclude student source files, repository contents, version-control history, authentication data, and browser data from support bundles.

## 5. Sample Input and Output

The exact wording may vary by platform, but every implementation shall communicate the same required information. The sample platform abbreviation `ref` represents the current reference platform declared by the manifest. Product names are intentionally omitted from these normative examples and are recorded in the manifest and nonnormative Appendix A. Lines beginning with `>` represent user input.

### 5.1 Prepare: Successful First Use

```text
============================================================
IT 140 COURSE AUTOMATION PREPARE
============================================================
Artifact version : 0.2.0
Version date-time group     : 2026-07-31
Platform         : ref
Current user     : student
Log file         : ~/it140/logs/prepare_ide_20260731_112000.log

[INFO] Downloading the current IT 140 course automation package...
[SUCCESS] The approved package archive was downloaded and validated.
[INFO] Refreshing repository-managed files under ~/it140/...
[SUCCESS] The current IT 140 course automation package is available.
[SUCCESS] The platform script directory is available in the current and future user PATH.

Next step: Run install_it140.sh
Log file : ~/it140/logs/prepare_ide_20260731_112000.log
```

### 5.2 Install: Successful System Installation

```text
============================================================
IT 140 COURSE IDE INSTALL
============================================================
Script version  : 0.2.0
Version date-time group    : 2026-07-31
Platform        : ref
Operating system: Approved reference release
Current user    : student
Log file        : ~/it140/logs/install_ref_20260731_113000.log

[INFO] Checking operating system, architecture, disk space, network access, and privilege-elevation capability...
[SUCCESS] Install prerequisites passed.

[INFO] Installing required system packages and applications declared by the manifest...
[SUCCESS] Required system components are installed.

[INFO] Verifying required commands and versions...
[SUCCESS] System-level course IDE verification passed.

============================================================
INSTALL SUMMARY
============================================================
Required operations: PASS
Warnings           : 0
Next step          : Run configure_it140.sh
Log file           : ~/it140/logs/install_ref_20260731_113000.log
```

### 5.3 Configure: First User Configuration

```text
============================================================
IT 140 USER CONFIGURATION
============================================================
Script version: 0.2.0
Version date-time group  : 2026-07-31
Platform      : ref
Current user  : student
Log file      : ~/it140/logs/configure_ref_20260731_114500.log

[INFO] Required system components are present.
[INFO] The approved source-code-hosting CLI is not currently authenticated.

[ACTION REQUIRED] The approved CLI will display a one-time code and open a browser.
Press Enter to begin, or type C to cancel.
>

[SUCCESS] Source-code-hosting authentication completed.
Version-control display name [PeteyPenmen]:
> Petey Penmen

[SUCCESS] Version-control identity configured with the provider-approved private commit identity.
[SUCCESS] The repository workspace is available at ~/Repos/.
[SUCCESS] The desktop Repos shortcut opens ~/Repos/.
[SUCCESS] The development workspace marker is configured where supported.
[SUCCESS] The CVD Visual Studio Code launcher opens ~/Repos/ as the active folder.
[SUCCESS] Required version-control, programming-language, IDE, extension, folder, and launcher settings are configured.

Next step: Run verify_it140.sh
```

### 5.4 Verify: One Required Failure

```text
============================================================
IT 140 ENVIRONMENT VERIFICATION
============================================================
Script version   : 0.2.0
Version date-time group     : 2026-07-31
Manifest release : 0.2.0
Manifest date    : 2026-07-31

PASS    Operating system: approved reference release
PASS    Programming-language runtime: required version available
PASS    Source-code-hosting CLI: authenticated
FAIL    IDE extension: required formatter extension is missing
PASS    Course automation folder: ~/it140
PASS    Repository workspace: ~/Repos
PASS    Desktop Repos shortcut: target is correct
PASS    Development workspace marker: correct or not applicable by platform
PASS    CVD IDE launcher: opens ~/Repos
PASS    Log directory: writable

Remediation for failed check:
Run configure_it140.sh to install or repair user-scoped course extensions.

============================================================
VERIFICATION SUMMARY
============================================================
Passed        : 7
Warnings      : 0
Failed        : 1
Not applicable: 0
Result        : NOT COMPLIANT
Exit code     : 1
Log file      : ~/it140/logs/verify_ref_20260731_120000.log

Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.
```

### 5.5 Update: Successful Maintenance with Restart Guidance

```text
============================================================
IT 140 COURSE IDE UPDATE
============================================================
Script version: 0.2.0
Version date-time group  : 2026-07-31

[INFO] Validating the current manifest and staging updated maintenance assets...
[SUCCESS] Course-managed maintenance assets validated and refreshed.

[INFO] Updating approved course software...
[SUCCESS] Required packages and applications are current.

[INFO] Updating required programming-language tools and IDE extensions...
[SUCCESS] Required user tools are current.

[INFO] Running post-update checks...
[SUCCESS] Post-update checks passed.

============================================================
UPDATE SUMMARY
============================================================
Required operations: PASS
Warnings           : 0
Restart required   : Yes
Next step          : Save your work, restart the reference environment, and run verify_it140.sh.
Log file           : ~/it140/logs/update_ref_20260731_121500.log
Exit code           : 0
```

## 6. Acceptance Test Cases

An **acceptance test** checks whether the completed software meets an agreed requirement. Each test below identifies the requirement or requirements, test condition, expected result, and pass criteria.

### 6.1 Package-Level Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
| --- | --- | --- | --- |
| AT-PKG-001 | PKG-FR-001, PKG-FR-002 | Inspect one fully supported platform implementation. | Exactly five correctly named artifacts—`prepare_it140.<ext>`, `install_it140.<ext>`, `configure_it140.<ext>`, `verify_it140.<ext>`, and `update_it140.<ext>`—are present in the approved platform directory, documented, and usable by the intended user. |
| AT-PKG-002 | PKG-FR-003, PKG-QOS-014 | Run a platform component on a different or unsupported OS. | The component makes no managed change, explains the mismatch, writes a log when possible, and exits with code `2`. |
| AT-PKG-003 | PKG-FR-004, PKG-FR-005, PKG-FR-019 | Replace the manifest with invalid JSON. | Each manifest-dependent script stops before managed changes, identifies the invalid manifest, and exits with code `5`; first-use prepare remains independent of the manifest. |
| AT-PKG-004 | PKG-FR-006 through PKG-FR-009 | Run each component under a normal supported condition. | Each run shows required opening information, including SemVer and version date-time group, creates a timestamped log, ends with the required completion information, and returns the documented result. |
| AT-PKG-005 | PKG-FR-010, PKG-FR-020 | Place student files and an unrelated repository beside managed assets, then run all applicable components. | File contents, timestamps, version-control history, and repository state remain unchanged except for explicitly managed assets. |
| AT-PKG-006 | PKG-NFR-025, PKG-QOS-018 | Use a test account with known username, email, and token-like values, then inspect output, logs, and bundle. | No password, token, private key, complete personal email address, or unapproved PII appears. |
| AT-PKG-007 | PKG-NFR-001, PKG-NFR-008, PKG-QOS-014 | Compare results from two supported platform variants. | Status terms, summary fields, remediation meanings, and exit-code meanings are equivalent. |
| AT-PKG-008 | PKG-NFR-015, PKG-FR-006, PKG-FR-012, PKG-QOS-017 | Inspect representative design, construction, testing, logging, and maintenance artifacts. | Controlled authored artifacts contain strict `MAJOR.MINOR.PATCH` SemVer and a separate valid `YYYY-MM-DD-HH-MM` version date-time group; generated records identify the producing or evaluated artifact versions and dates; no date-based version substitutes for SemVer. |
| AT-PKG-009 | PKG-FR-008, PKG-FR-021, PKG-QOS-012, PKG-QOS-020 | Cause each lifecycle component on a non-CVD profile to end once with a handled nonzero or noncompliant result. Exercise the CVD-specific guidance branch through a representative CVD failure or an approved output-service test. | Each component attempts a final summary, gives problem-specific remediation and the exact log path, and presents CVD as the continuity option for the local-profile failure. The CVD branch states that CVD is affected and directs the user to the applicable remediation and support path. |
| AT-PKG-010 | PKG-NFR-018, PKG-NFR-028, PKG-TC-006, Section 3.3 | Review a proposed technically compatible but unqualified deployment profile. | The proposal is not represented as course-supported until all qualification conditions are complete. When it can reuse an approved platform implementation and adapter contracts, the platform-independent lifecycle requires no redesign and no duplicate script family. |

### 6.2 Prepare Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
| --- | --- | --- | --- |
| AT-PRE-001 | PRE-FR-001, PRE-FR-003, PRE-FR-005 through PRE-FR-013 | On a clean supported local user account with no local `~/it140/` package, run the documented first-use command set. | The commands use only baseline native utilities, create the course root and log, download and validate the approved archive, install all five platform artifacts, establish permissions and `PATH`, clean temporary files, resolve the local workflow, and identify the exact Install next step. |
| AT-PRE-011 | PRE-FR-008, PRE-FR-013, PKG-FR-022 | Run Prepare on the CVD provider baseline master as the authorized CVD administrator. | Prepare validates the CVD lifecycle entry points, resolves `cvd_provider_baseline_administrator`, and reports `update_it140.sh` as the exact next step. |
| AT-PRE-012 | PRE-FR-008, PRE-FR-013, PKG-FR-022 | Run Prepare on the IT 140 course master as a CVD student. | Prepare validates the CVD student lifecycle entry points, resolves `cvd_course_master_student`, and reports `update_it140.sh` as the exact next step. |
| AT-PRE-002 | PRE-FR-002, PRE-FR-009 through PRE-FR-011, PKG-QOS-001 | Place an older installed automation package beside student files and a nested student repository, then execute the installed prepare artifact twice. | Repository-managed package files refresh to the approved versions, the second run creates no duplicate `PATH` entry, and student files and nested repository history remain unchanged. |
| AT-PRE-003 | PRE-FR-007, PRE-FR-008, PRE-FR-014, PKG-QOS-003, PKG-QOS-004 | Interrupt the download or provide a truncated archive. | The incomplete archive is not activated, the prior valid package remains usable, temporary files are cleaned when safe, the failure is logged, and the result is nonzero. |
| AT-PRE-004 | PRE-FR-004 | Run the prepare commands on an unsupported OS or in a prohibited root or administrator context. | Preparation stops before replacing package files, explains the platform or privilege mismatch, and returns the applicable nonzero result. |
| AT-PRE-005 | PRE-FR-008 | Provide a structurally valid archive that omits the matching `install_it140.<ext>` artifact. | Preparation rejects the archive, preserves the installed package, records the failed structural check, and returns a validation failure. |
| AT-PRE-006 | PRE-FR-015 | Inspect system software, external-service authentication, and IDE settings before and after prepare. | Prepare changes only the automation package, log, required permissions, and user `PATH`; it does not install IDE software, authenticate services, or write IDE settings. |

### 6.3 Install Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
| --- | --- | --- | --- |
| AT-INS-001 | INS-FR-001 through INS-FR-008 | Run install on a clean supported system with sufficient space, network access, and required privilege. | All required system components are installed, version checks pass, no user-specific account settings are created, and exit code is `0`. |
| AT-INS-002 | INS-FR-009, INS-FR-010, PKG-QOS-001 | Run install twice on the same compliant system. | The second run succeeds without duplicate repositories, keys, policies, PATH entries, or package definitions. |
| AT-INS-003 | INS-FR-001, INS-FR-002 | Run install without required administrative capability. | No system installation begins; the user receives permission guidance and exit code `3`. |
| AT-INS-004 | INS-FR-004, PKG-NFR-024 | Substitute an unapproved or integrity-failing download source in a controlled test. | The asset is rejected, the previous valid state is preserved, and exit code is `4` or `5` as applicable. |
| AT-INS-005 | INS-FR-006 | Run install when maintenance updates are available but a newer OS release also exists. | Approved updates install; the OS release does not change. |
| AT-INS-006 | INS-FR-010 | Remove one course-managed system component and rerun install. | The missing component is repaired without resetting unrelated system settings. |
| AT-INS-007 | INS-FR-011 | Use a test account with no source-code-hosting authentication or IDE user settings, then run install. | Install does not authenticate an external source-code-hosting service, create version-control identity, or write user IDE settings. |

### 6.4 Configure Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
| --- | --- | --- | --- |
| AT-CFG-001 | CFG-FR-002 through CFG-FR-021 | Run configure for a new standard user after successful install. | Required course folders, repository workspace, PATH entry, source-code-hosting authentication, version-control identity, tools, extensions or plug-ins, settings, desktop Repos link, applicable development marker, and profile-owned IDE launch behavior are correctly established. |
| AT-CFG-002 | CFG-FR-005 | Run configure while the manifest-approved source-code-hosting CLI is already authenticated. | The existing valid authentication is used; no unnecessary login flow starts. |
| AT-CFG-003 | CFG-FR-006, PKG-QOS-014 | Cancel the required external-service authentication flow. | Configure reports cancellation, does not claim success, preserves prior settings, and exits with code `6`. |
| AT-CFG-004 | CFG-FR-007, PKG-NFR-025 | Complete authentication with a known test account. | The provider-profile privacy rule produces the correct commit identity, but complete private identity data is redacted in logs and support output. |
| AT-CFG-005 | CFG-FR-011, CFG-FR-016 | Add unrelated valid IDE settings and optional extensions or plug-ins, then run configure twice. | Required settings are merged; unrelated settings and optional extensions remain; no duplicate entries are created. |
| AT-CFG-006 | CFG-FR-012, PKG-NFR-019 | Run configure under two different home-directory paths, including one with spaces where supported. | All managed paths are derived correctly; no hardcoded user name or home-directory dependency is present. |
| AT-CFG-007 | CFG-FR-018 through CFG-FR-021 | Populate `~/Repos/` with a test Git repository, then delete or corrupt only the course-managed workspace desktop integration and rerun Configure. | `~/Repos/` still contains the unchanged test repository; the desktop `Repos` shortcut resolves to the workspace; the approved development marker is repaired where applicable; on CVD the existing Visual Studio Code launcher opens `~/Repos/`; unrelated desktop preferences remain unchanged. |
| AT-CFG-008 | CFG-FR-001 | Attempt to run configure directly as root or the system administrator account when not required by the platform design. | Configure stops before personal settings are written and provides the correct standard-user command. |

| AT-CFG-009 | CFG-FR-018, CFG-FR-016, PKG-FR-010 | Place committed and uncommitted test files, nested directories, and Git metadata beneath `~/Repos/`, record hashes and Git status, and run Configure twice. | Configure creates or repairs only the workspace parent and course-owned integrations. All nested file hashes, Git status, repository remotes, branches, timestamps where the platform preserves them, and repository permissions remain unchanged. |
| AT-CFG-010 | CFG-FR-019 | Place an unrelated regular file or directory at the required desktop shortcut name before Configure. | Configure preserves the conflicting unmanaged item, reports the conflict, and does not replace, rename, or delete it. |

### 6.5 Verify Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
| --- | --- | --- | --- |
| AT-VER-001 | VER-FR-003 through VER-FR-012 | Run verify on a fully compliant supported environment. | All required checks pass, summary totals are correct, result is compliant, and exit code is `0`. |
| AT-VER-002 | VER-FR-005, VER-FR-008 through VER-FR-012 | Remove one required system application. | Verify reports `FAIL`, names the related requirement, recommends `install_it140.<ext>`, and exits with code `1`. |
| AT-VER-003 | VER-FR-006, VER-FR-009, VER-FR-015 through VER-FR-018 | Remove one required user setting or extension, remove the desktop `Repos` link, or on CVD change the Visual Studio Code launch argument away from `~/Repos/`. | Verify reports `FAIL`, recommends `configure_it140.<ext>`, and does not recommend Install. |
| AT-VER-004 | VER-FR-001, VER-FR-002, PKG-QOS-002 | Record checksums and modification times of managed files before and after verify. | No managed file or setting changes, and verify does not request administrative privilege. |
| AT-VER-005 | VER-FR-008, VER-FR-010 | Omit an optional component. | Verify reports `WARNING` or `NOT APPLICABLE`, does not classify the environment as failed solely for that item, and uses the correct exit code. |
| AT-VER-006 | VER-FR-013, PKG-QOS-021, PKG-QOS-022 | Request a support bundle from a test environment containing student source files. | The bundle is created only after explicit request and contains approved diagnostics but no student source, repository content, version-control history, or authentication data. |
| AT-VER-007 | VER-FR-014 | Simulate an unsupported administrative condition that no lifecycle component can repair. | Verify explains the limitation and directs the user to the approved support channel. |

| AT-VER-008 | VER-FR-001, VER-FR-015 through VER-FR-018 | Record hashes, Git status, and filesystem metadata for content beneath `~/Repos/`, then run Verify. | Verify reports the workspace integration state without creating, editing, deleting, moving, or permission-changing any workspace content or desktop integration. |
| AT-VER-009 | VER-FR-017, CFG-FR-020 | Run Verify on a qualified platform whose supplement declares no safe supported native development-marker mechanism. | The visual-marker check reports `NOT APPLICABLE`; required workspace and desktop-link checks still run normally and no marker is synthesized. |

### 6.6 Update Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
| --- | --- | --- | --- |
| AT-UPD-001 | UPD-FR-001, UPD-FR-006, UPD-FR-013 | Run update on a compliant environment with no available changes. | The script verifies the environment, avoids unnecessary reinstallations, reports that required components are current, and exits with code `0`. |
| AT-UPD-002 | UPD-FR-003 through UPD-FR-008 | Make approved package, tool, extension, manifest, and maintenance-asset updates available. | Approved update-scope changes install from staged validated sources and post-update checks pass; lifecycle script refresh remains the responsibility of prepare. |
| AT-UPD-003 | UPD-FR-002, PKG-QOS-005 | Start a second updater while one update holds the environment lock. | The second updater makes no changes, reports the concurrent run, and exits nonzero. |
| AT-UPD-004 | UPD-FR-004, UPD-FR-005, PKG-QOS-003, PKG-QOS-004 | Interrupt a managed-asset download or supply a truncated file. | The installed valid asset remains usable; the incomplete file is not activated; rerunning update can recover. |
| AT-UPD-005 | UPD-FR-007 | Run update when a new OS release is available. | Packages may update, but the OS release remains unchanged. |
| AT-UPD-006 | UPD-FR-009, UPD-FR-011 | Install an optional extension and create student files, then run update and cleanup. | Optional extension and student files remain; required tools remain installed. |
| AT-UPD-007 | UPD-FR-010, PKG-FR-017 | Mark a test managed component obsolete in the manifest and place a similarly named user file outside the managed path. | Only the explicitly listed managed component is removed; the user file remains. |
| AT-UPD-008 | UPD-FR-012 | Cause a temporary network failure that resolves within the approved retry policy. | Update retries, continues when the source becomes available, and records the event in the log. |
| AT-UPD-009 | UPD-FR-014, UPD-FR-016 | Apply an update that requires a restart. | The summary clearly identifies the required restart and recommends verification after the restart. |
| AT-UPD-010 | UPD-FR-015 | Interrupt update after one independent stage succeeds, then rerun it. | The rerun detects the current state, avoids harmful duplication, completes remaining work, and produces a correct final result. |

### 6.7 Cross-Script Lifecycle Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
| --- | --- | --- | --- |
| AT-LFC-001 | PKG-FR-001, PKG-FR-022, PRE-FR-001, INS-FR-012, CFG-FR-017, VER-FR-001 | On a clean supported local environment, run Prepare, Install, Configure, and Verify in order. | Prepare resolves the local workflow; Install establishes system state; Configure establishes user state and desktop integrations; Verify reports full compliance without changing either state. |
| AT-LFC-002 | INS-FR-010, VER-FR-009 | Remove a required system component, run verify, run its recommended remediation, and verify again. | First verify recommends install; install repairs the component; second verify passes that check. |
| AT-LFC-003 | CFG-FR-016, VER-FR-009 | Damage a required user setting, run verify, run its recommended remediation, and verify again. | First verify recommends configure; configure repairs the setting; second verify passes that check. |
| AT-LFC-004 | PRE-FR-002, PRE-FR-009, UPD-FR-003, UPD-FR-013, UPD-FR-016 | Publish a new approved automation package and maintenance release, rerun prepare, run update, and then verify. | Prepare refreshes the lifecycle scripts and controlled package files; update applies approved maintenance-scope changes; verify evaluates against the new manifest release and passes. |
| AT-LFC-005 | PKG-FR-010, PKG-FR-020 | Complete the full prepare, install, configure, verify, and update lifecycle in an environment containing student work and unrelated user settings. | The lifecycle reaches compliance without changing user-owned files or unrelated settings. |
| AT-LFC-006 | PKG-FR-022, PKG-FR-023, PRE-FR-013 | From a clean CVD provider baseline master, run Prepare, initial Update, Install, Configure, and Verify. | Each component reports the administrator workflow and correct next transition; initial Update maintains the OS baseline without performing Install or Configure work; final Verify reports compliance. |
| AT-LFC-007 | PKG-FR-022, PKG-FR-023, PRE-FR-013 | From an IT 140 course master distributed to a student, run Prepare, initial Update, Configure, and Verify. | Prepare and initial Update omit Install from the student path, Configure establishes the current-user layer, and Verify reports compliance. |
| AT-LFC-008 | PKG-FR-023, UPD-FR-001 through UPD-FR-016 | Run Update again after either CVD initialization workflow has completed. | Update identifies periodic maintenance mode, applies only approved maintenance responsibilities, and recommends Verify when appropriate. |

## Appendix A (Nonnormative): Reference Environment at the SRS Baseline

### A.1 Purpose and Authority

This appendix records the concrete environment used to review this SRS and design the initial acceptance tests at repository baseline commit `dbde859f90b1b957b05aa03e25b867563c113bb2`. **Nonnormative** means that this appendix provides context but does not create binding requirements.

The controlled `it140_manifest.json` file is the sole authoritative source for products, services, identifiers, versions, approved sources, provider profiles, and supported platform releases. When this appendix and the manifest differ, the manifest controls. Deployment approval requires a complete, valid, and approved manifest.

Where the repository baseline did not pin an exact product version, this appendix records the approved version policy instead of inventing a version number.

### A.2 Reference Platform

| Category | Reference selection at the baseline |
| --- | --- |
| Virtual desktop provider | Codio Virtual Desktop |
| Operating system | Ubuntu 24.04 Long-Term Support (LTS) |
| Graphical desktop | Xfce |
| Shell scripting language | Bash |
| System package manager | Advanced Package Tool (APT) |
| Standard user model | Standard Codio user with controlled passwordless `sudo` for approved system operations |

### A.3 Reference Applications, Services, and Command-Line Tools

| Capability | Reference product or component | Version or policy at the baseline | Course purpose |
| --- | --- | --- | --- |
| Secure source retrieval | `ca-certificates`, `curl`, and `gpg` | Ubuntu 24.04 approved package versions | Retrieve and validate approved software sources. |
| Project environment loading | `direnv` | Ubuntu 24.04 approved package version | Apply approved project-specific environment settings when present. |
| Version control | Git | Ubuntu 24.04 approved package version | Track file changes and interact with repositories. |
| Source-code hosting | GitHub | Hosted service release | Store course and student repositories and support collaboration. |
| Source-code-hosting CLI | GitHub CLI (`gh`) | Current approved release from the official GitHub package source | Authenticate and perform approved repository actions from the terminal. |
| Programming-language runtime | Python 3.12 | Python 3.12 major and minor version | Write, run, and test IT 140 programs. |
| Language package and environment tools | `pip` and `venv` | Versions compatible with the approved Python runtime | Install course tools and create isolated environments when required. |
| Integrated development environment | Visual Studio Code (`code`) | Current approved stable release from the official product source | Edit, run, test, debug, and manage course files. |
| Web browser | Google Chrome | Version included in the approved reference image | Access course resources and approved authentication flows. |
| Folder display utility | `tree` | Ubuntu 24.04 approved package version | Display folder structures in a readable form. |
| Clipboard utility | `xclip` | Ubuntu 24.04 approved package version | Support clipboard operations in the graphical desktop. |
| Keyboard-state utility | `numlockx` | Ubuntu 24.04 approved package version | Apply the approved Num Lock desktop behavior. |

### A.4 Reference Programming-Language Tools

| Tool | Version or policy at the baseline | Course purpose |
| --- | --- | --- |
| pytest | Current manifest-approved version compatible with Python 3.12 | Run tests supplied with course activities. |
| pytest-cov | Current manifest-approved version compatible with Python 3.12 | Report test coverage when included with supplied tests. |
| Ruff | Current manifest-approved version compatible with Python 3.12 | Identify code-quality issues and format code consistently. |

Students are expected to run provided tests; this package does not require students to create their own tests.

### A.5 Reference IDE Extensions

| Extension identifier | Reference product or capability | Course purpose |
| --- | --- | --- |
| `ms-python.python` | Python language support | Provide programming-language support in the IDE. |
| `charliermarsh.ruff` | Ruff integration | Integrate code checking and formatting. |
| `hediet.vscode-drawio` | Draw.io diagram support | View and edit approved diagrams. |
| `streetsidesoftware.code-spell-checker` | Code Spell Checker | Identify likely spelling errors in comments and documentation. |
| `i2p-hub.i2p-pseudo` | I2P Pseudo | Support course pseudoscript files. |
| `cweijan.vscode-office` | Office Viewer | View supported office-document formats in the IDE. |

### A.6 Initial Managed-Asset Categories

- Automation scripts
- `it140_manifest.json`
- Course workspace configuration
- Documentation explicitly marked as course-managed
- Required extension definitions
- Course-managed launchers and file associations
- Approved browser policies and bookmarks
- Obsolete components explicitly listed by the manifest

## Appendix B: Requirements Traceability and Change Control

**Traceability** means linking each requirement to its design, implementation, and test. Every approved requirement in this SRS shall be traceable to:

1. A versioned design element in the Software Design Description (SDD) or another approved design artifact.
2. One or more versioned implementation files, manifests, schemas, generated assets, or functions.
3. One or more versioned acceptance tests, automated tests, or test reports.
4. A versioned maintenance record, repository issue, approved change request, release note, or version-control commit when the requirement changes.

A proposed requirement change shall identify:

- The requirement IDs affected.
- The reason for the change.
- The platforms and scripts affected.
- Changes required in the manifest, SDD, code, tests, logs or support records, maintenance artifacts, and student documentation.
- The required SemVer increment and new version date-time group for each affected controlled artifact.
- Compatibility or migration effects for existing installations.

The SRS SemVer version, SRS version date-time group, and repository baseline shall be updated after an approved change is merged.
