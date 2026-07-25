# Software Requirements Specification

- **Course**: IT 140 - *Introduction to Scripting*
- **Activity**: Course Automation Script Development
- **Program Name**: IT 140 Course Automation Scripts
- **Document ID**: IT140-SRS-SCRIPTS
- **Status**: Draft for faculty review
- **Version**: 2026.07.25.1
- **Repository Baseline**: `GC-STEM/it140` commit `9cd02da434bb1786a027732edcccadb8c6f25ae9`

---

## 0. General Description

### 0.1 Purpose

This Software Requirements Specification (SRS) defines what the **IT 140 Course Automation Scripts** package must do and the conditions it must satisfy. An SRS is an agreement about required software behavior. It describes the required results before developers choose the detailed design or write the final code.

The package supports the IT 140 course integrated development environment (IDE). An IDE is a collection of tools used to write, run, test, debug, and manage programs. The package consists of four coordinated scripts for each supported operating system (OS) platform:

1. `setup_<platform>.<ext>` establishes system-level software and settings.
2. `configure_<platform>.<ext>` establishes settings for the current user.
3. `verify_<platform>.<ext>` checks the system and user configuration without changing them.
4. `update_<platform>.<ext>` maintains the supported environment over time.

The four scripts form one software package because they share requirements, files, configuration data, logs, release information, and remediation paths. A **remediation path** is the recommended action for correcting a detected problem.

### 0.2 Product Scope

The package shall provide a consistent, supportable course IDE across supported platforms. It shall reduce the number of manual setup steps, identify configuration problems, and provide useful diagnostic information to students, faculty, artificial intelligence (AI) support tools, and university technical support.

The package shall use a shared **JavaScript Object Notation (JSON)** manifest. JSON is a plain-text data format that software can read and validate. The manifest shall be the authoritative source for shared requirements such as supported platforms, required software, required extensions, managed paths, and the current automation release.

The initial reference platform is the **Codio Virtual Desktop (CVD)**, which is an [Ubuntu 24.04 Long-Term Support](https://ubuntu.com/blog/ubuntu-desktop-24-04-noble-numbat-deep-dive) (LTS) virtual machine with the [Xfce](https://www.xfce.org/) graphical desktop. LTS means the operating-system release receives security and maintenance updates for an extended period.

### 0.3 Intended Users and Stakeholders

| User or stakeholder  | Primary use cases                                                       |
| -------------------- | ----------------------------------------------------------------------- |
| IT 140 students      | Configure, verify, and update their course environment.                 |
| IT 140 faculty       | Use the same supported environment, review logs, and guide students.    |
| Codio administrators | Provision and maintain the system-level CVD image.                      |
| SNHU IT Service Desk | Use verification results and logs to diagnose problems.                 |
| AI support tools     | Explain verification results and recommend approved remediation.        |
| CS Deans & SMEs      | Design, implement, test, and maintain the scripts and supporting files. |

### 0.4 Package Components and Responsibility Boundaries

**System-level** changes affect the operating system or all users of a computer. **User-specific** changes affect only the account running the script.

| Component | Primary responsibility | Expected user | May change system-level state? | May change user-specific state? |
|---|---|---|---:|---:|
| `setup_<platform>.<ext>` | Install or repair the supported system-level course IDE. | Administrator or approved standard user with controlled privilege elevation | Yes | No, except for the minimum files required to create its own log |
| `configure_<platform>.<ext>` | Configure the current user's course environment and accounts. | Student or faculty user | No | Yes |
| `verify_<platform>.<ext>` | Inspect both layers and report results. | Student, faculty, AI support, or technical support | No | No |
| `update_<platform>.<ext>` | Update the supported environment and course-managed assets. | Student or faculty user with controlled privilege elevation when required | Yes | Yes, only for course-managed settings and tools |

### 0.5 Scope Exclusions

The package shall not:

- Create, solve, grade, or modify student programming assignments.
- Overwrite student Python files, assignment repositories, Git history, or Learning Management System (LMS) submissions.
- Store passwords, authentication tokens, browser session data, or other secrets.
- Perform an operating-system release upgrade unless a future approved requirement explicitly adds that capability.
- Provide general-purpose backup, reset, uninstall, or account-recovery functions.
- Treat student-selected optional software or unrelated user settings as course-managed assets.
- Replace the platform bootstrap command set used before the scripts are available.

The **bootstrap command set** is the short, documented sequence that obtains the scripts, creates the initial course folder, sets permissions, and starts the correct script. It is outside the installed four-script package because it is needed before the package is present.

### 0.6 Terms and Abbreviations

| Term | Definition and purpose in this SRS |
|---|---|
| AI | Artificial intelligence. AI support may interpret approved diagnostics but shall not receive secrets or unnecessary personal information. |
| API | Application Programming Interface. An API allows one program to request information or actions from another program, such as obtaining the current GitHub username. |
| CLI | Command-Line Interface. A CLI is a text-based way to run software, such as GitHub CLI (`gh`). |
| CVD | Codio Virtual Desktop. It is the initial reference platform for the course IDE. |
| Exit code | A small integer returned when a script ends. Other programs and support tools use it to determine whether the run succeeded or why it failed. |
| GUI | Graphical User Interface. A GUI uses windows, icons, buttons, and menus rather than only typed commands. |
| IDE | Integrated Development Environment. It combines tools used to develop and test programs. |
| Idempotent | Safe to run repeatedly. An idempotent script reaches the required state without duplicating entries or damaging a correct configuration. |
| Least privilege | Giving a script only the permissions required for the current task. This limits the damage caused by mistakes or misuse. |
| Log or transcript | A timestamped text record of script actions and results. Logs support troubleshooting and auditing. |
| Managed asset | A file, setting, package, launcher, extension, or other item that the course automation is authorized to create, replace, update, or remove. |
| Manifest | The shared JSON file that defines the supported course environment. It prevents different scripts from using inconsistent lists or versions. |
| OS | Operating system, such as Ubuntu, Windows, or macOS. |
| PATH | An operating-system setting that lists folders searched for executable commands. |
| PII | Personally Identifiable Information. PII is information that can identify a person, such as an email address. |
| QoS | Quality of Service. QoS requirements define measurable expectations for reliability, performance, error handling, and diagnostics. |
| SRS | Software Requirements Specification. It defines required software behavior and constraints. |
| VS Code | Visual Studio Code, the code editor used in the course IDE. |

### 0.7 Requirement Conventions

Each mandatory requirement uses **shall** and has a unique identifier.

- `PKG-FR-###`: package-level functional requirement
- `SET-FR-###`: setup-script functional requirement
- `CFG-FR-###`: configure-script functional requirement
- `VER-FR-###`: verify-script functional requirement
- `UPD-FR-###`: update-script functional requirement
- `PKG-NFR-###`: package-level nonfunctional requirement
- `PKG-TC-###`: shared technology constraint
- `CVD-TC-###`: CVD-specific technology constraint
- `PKG-QOS-###`: package-level quality-of-service constraint

A **functional requirement** states what the software shall do. A **nonfunctional requirement** states how well or under what general qualities it shall operate. A **technology constraint** limits the technologies or environment that may be used. A **Quality of Service (QoS) constraint** gives a measurable expectation for reliability, performance, security, or supportability.

A paragraph labeled **Why** explains the reason for a requirement. The explanation supports learning and review but does not replace the testable “shall” statement.

---

## 1. Functional Requirements

### 1.1 Package-Level Functional Requirements

The package shall:

- **PKG-FR-001** Provide one `setup`, `configure`, `verify`, and `update` script for every supported platform listed in the manifest.

  **Why:** Users and support personnel need the same four-step lifecycle on each supported platform.

- **PKG-FR-002** Use the filename pattern `<action>_<platform>.<ext>`, where `<action>` is `setup`, `configure`, `verify`, or `update`; `<platform>` is the approved platform abbreviation; and `<ext>` is the platform-appropriate script extension.

  **Why:** Predictable names reduce user error and simplify documentation and support.

- **PKG-FR-003** Confirm that the running script matches the detected platform before making any change.

  **Why:** A script written for another operating system could fail or damage the environment.

- **PKG-FR-004** Read shared environment requirements from `~/it140/it140_manifest.json` rather than maintaining independent authoritative software lists in each script.

  **Why:** One authoritative list prevents setup, verification, and update from disagreeing.

- **PKG-FR-005** Validate the manifest before using its data. A script that requires the manifest shall stop safely when the manifest is missing, unreadable, or invalid.

  **Why:** Acting on incomplete or corrupted requirements could install the wrong software or change the wrong files.

- **PKG-FR-006** Display the script name, script version, detected platform, current user, start time, purpose, and log location near the beginning of each run.

  **Why:** Clear context helps beginners confirm that they started the correct tool and helps support personnel interpret the transcript.

- **PKG-FR-007** Save a timestamped transcript of each run under `~/it140/logs/` or the equivalent path derived from the current user's home folder.

  **Why:** A saved transcript allows a problem to be reviewed after the terminal window closes.

- **PKG-FR-008** End with a plain-language summary that identifies completed actions, warnings, failures, the log path, and the recommended next step.

  **Why:** Beginners should not need to interpret raw command output to know what to do next.

- **PKG-FR-009** Return a standardized exit code defined in Section 4.3.

  **Why:** Standard codes allow scripts, tests, AI support, and technical support tools to interpret results consistently.

- **PKG-FR-010** Preserve student work, assignment repositories, Git history, optional extensions, and unrelated settings during every package operation.

  **Why:** Course automation must not put coursework or personal configuration at risk.

### 1.2 Setup Script Requirements

The setup script shall:

- **SET-FR-001** Verify the supported operating-system release, processor architecture, available disk space, network access, and required administrative capability before beginning installation.

  **Why:** Early prerequisite checks prevent a long installation from failing after it has already changed the system.

- **SET-FR-002** Stop without making system changes when the detected platform is unsupported or the required administrative capability is unavailable.

  **Why:** Safe refusal is better than an incomplete or incorrect installation.

- **SET-FR-003** Install or repair the system-level applications, language runtimes, package managers, command-line tools, and operating-system packages declared by the manifest.

  **Why:** Setup owns the shared software layer used by every course user on that computer.

- **SET-FR-004** Obtain software only from approved sources declared by the manifest or trusted operating-system repositories.

  **Why:** Approved sources reduce the risk of altered or malicious installers.

- **SET-FR-005** Configure required system package repositories, signing keys, certificates, and system policies before installing dependent software.

  **Why:** Package managers need trusted source information to verify and update software correctly.

- **SET-FR-006** Bring the supported operating-system packages to the approved baseline without upgrading the computer to a different operating-system release.

  **Why:** Security and compatibility updates are needed, but release upgrades can introduce untested changes.

- **SET-FR-007** Install system-level course integrations declared by the manifest, such as managed browser policies or system application registrations.

  **Why:** Some course features must be available to all users and therefore belong in setup rather than user configuration.

- **SET-FR-008** Verify that each required system command is available and that installed versions meet the manifest requirements before reporting success.

  **Why:** A successful installer command does not always guarantee that the installed tool can run.

- **SET-FR-009** Be idempotent: rerunning setup on a compliant system shall not duplicate repositories, keys, packages, policies, or other entries.

  **Why:** Setup also serves as the approved repair method for missing system components.

- **SET-FR-010** Repair a missing or damaged course-managed system component when rerun, without resetting unrelated operating-system settings.

  **Why:** Users need a safe repair path that does not require a separate repair script.

- **SET-FR-011** Avoid GitHub authentication, Git identity configuration, user-specific VS Code settings, user-scoped extensions, and other personal configuration.

  **Why:** These items belong to the individual account and are the responsibility of `configure`.

- **SET-FR-012** Recommend running the matching configure script after successful system setup.

  **Why:** System installation alone does not complete the current user's course environment.

### 1.3 Configure Script Requirements

The configure script shall:

- **CFG-FR-001** Run as the standard student or faculty account and refuse direct execution as the root or system-administrator account unless a platform-specific design explicitly requires it.

  **Why:** Personal settings and authentication must be saved to the intended user's account.

- **CFG-FR-002** Verify that required system-level components are present before changing user configuration.

  **Why:** User configuration cannot succeed reliably when setup is incomplete.

- **CFG-FR-003** Create the required course folders under the current user's home folder, including `~/it140/`, `~/it140/logs/`, and `~/it140/scripts/`,without deleting existing contents.

  **Why:** A consistent folder structure simplifies instructions while preserving prior work.

- **CFG-FR-004** Add the correct platform script folder to the user's `PATH` without adding duplicate entries.

  **Why:** Users should be able to run the course scripts by name from a terminal, regardless of their current working directory.

- **CFG-FR-005** Check the current GitHub CLI authentication status and start the approved interactive authentication flow only when authentication is missing or invalid.

  **Why:** Requiring a new login on every run wastes time and may confuse users.

- **CFG-FR-006** Explain each required GitHub authentication action in plain language and handle cancellation without treating it as successful configuration.

  **Why:** First-term students may be unfamiliar with device codes, browser authentication, and terminal prompts.

- **CFG-FR-007** Obtain the authenticated GitHub username and numeric account identifier through the GitHub API and derive the GitHub-provided private `noreply` email address without asking the user to type it.

  **Why:** Automated retrieval reduces typing errors and helps protect the student's personal email address.

- **CFG-FR-008** Allow the user to accept the GitHub username as the Git display name or enter a different professional display name.

  **Why:** A Git display name identifies the author of commits and may differ from the GitHub username.

- **CFG-FR-009** Apply the course-required Git settings declared by the manifest, including the default branch, text line endings, automatic upstream configuration, and VS Code as the Git editor.

  **Why:** Shared Git settings make submissions and collaboration more consistent across platforms.

- **CFG-FR-010** Install or repair the required user-scoped Python tools and VS Code extensions declared by the manifest.

  **Why:** These tools are associated with the current account and may not be installed system-wide.

- **CFG-FR-011** Merge course-required VS Code settings into the user's existing settings without discarding unrelated valid settings.

  **Why:** Students may already use VS Code for other courses or personal work.

- **CFG-FR-012** Derive user paths from the current home folder and shall not hardcode a username or home-directory path.

  **Why:** The same script must work for different account names.

- **CFG-FR-013** Create or repair course-managed user integrations declared by the manifest, such as desktop shortcuts, panel launchers, file associations, and the default course folder.

  **Why:** Consistent shortcuts reduce navigation problems for beginning users.

- **CFG-FR-014** Validate the resulting Git, GitHub CLI, Python, VS Code, extension, and course-folder configuration before reporting success.

  **Why:** Configuration is complete only when the resulting settings can be read and used.

- **CFG-FR-015** Be idempotent and preserve user-selected optional extensions and unrelated preferences when rerun.

  **Why:** Configure also serves as the approved repair method for user-specific settings.

- **CFG-FR-016** Recommend running the matching verify script after successful configuration.

  **Why:** Verification provides an independent check of both setup and configuration.

### 1.4 Verify Script Requirements

The verify script shall:

- **VER-FR-001** Operate in read-only mode and shall not install, update, remove, repair, or rewrite software or settings.

  **Why:** Verification must be safe to run during troubleshooting and must not hide the original problem by changing it.

- **VER-FR-002** Run without administrative privilege.

  **Why:** Students and support personnel should be able to collect diagnostics safely.

- **VER-FR-003** Validate the manifest and identify the automation release used for comparison.

  **Why:** Verification results are meaningful only when compared with a known set of requirements.

- **VER-FR-004** Check the detected operating system, release, processor architecture, current user, available disk space, required permissions, and required network reachability.

  **Why:** Environment problems may exist even when individual applications are installed.

- **VER-FR-005** Check the presence and required versions of all system applications, command-line tools, language runtimes, package managers, and operating-system packages declared by the manifest.

  **Why:** Missing or incompatible versions can prevent course activities from working.

- **VER-FR-006** Check required Python packages, VS Code extensions, Git settings, GitHub CLI authentication status, VS Code settings, script permissions, course folders, and managed user integrations.

  **Why:** Verification must cover both the system-level and user-specific layers.

- **VER-FR-007** Validate the format and safe values of managed configuration files without displaying secrets or complete personally identifiable information (PII).

  **Why:** Support diagnostics must be useful without exposing private data.

- **VER-FR-008** Report each check as `PASS`, `WARNING`, `FAIL`, or `NOT APPLICABLE`.

  **Why:** Consistent result labels make the report easier to scan and interpret.

- **VER-FR-009** Identify the related requirement and recommend `setup`, `configure`, or `update` for every failed required check.

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

  **Why:** Some failures require platform administration rather than another script run.

### 1.5 Update Script Requirements

The update script shall:

- **UPD-FR-001** Verify the supported platform, current user, available disk space, network access, and required privilege-elevation capability before beginning changes.

  **Why:** Updating a partially supported environment can leave it less usable than before.

- **UPD-FR-002** Prevent more than one copy of the update script from changing the same environment at the same time.

  **Why:** Concurrent package or file updates can corrupt state or produce inconsistent results.

- **UPD-FR-003** Obtain the latest approved manifest and course-managed assets from the authorized course source.

  **Why:** Students need corrections to scripts and support files after the initial installation.

- **UPD-FR-004** Download managed assets to a temporary staging location, validate them, and replace installed assets only after validation succeeds.

  **Why:** Staging prevents a failed or incomplete download from replacing a working file.

- **UPD-FR-005** Preserve the previous valid copy of a replaced managed asset until the new copy has been installed successfully.

  **Why:** A recoverable update is safer than an in-place overwrite.

- **UPD-FR-006** Refresh operating-system package information and install approved security, maintenance, and course-software updates.

  **Why:** Supported environments need current fixes and compatible tool versions.

- **UPD-FR-007** Not upgrade the computer to a different operating-system release.

  **Why:** A new release may not have been tested with the course IDE.

- **UPD-FR-008** Update or repair required Python tools and VS Code extensions declared by the manifest.

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

### 1.6 Shared Manifest and Managed-Asset Requirements

The package shall:

- **PKG-FR-011** Store the shared manifest as valid UTF-8 JSON at `~/it140/it140_manifest.json`.

  **Why:** A standard text format can be read on all supported platforms and reviewed in source control.

- **PKG-FR-012** Include a manifest schema version and automation package release.

  **Why:** Scripts must know whether they understand the manifest structure and which release they are applying.

- **PKG-FR-013** Define each supported platform, platform abbreviation, supported operating-system releases, architectures, and platform script extension in the manifest.

  **Why:** Platform support must be explicit and testable.

- **PKG-FR-014** Define required system applications, operating-system packages, language runtimes, Python tools, VS Code extensions, and minimum acceptable versions in the manifest.

  **Why:** The same requirements must drive installation, verification, and update.

- **PKG-FR-015** Define required Git settings, VS Code settings, file associations, managed integrations, and managed paths in the manifest.

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

---

## 2. Nonfunctional Requirements

### 2.1 Package-Level Requirements

The package shall:

- **PKG-NFR-001** Use consistent script structure, terminology, status labels, exit codes, log fields, and user-message patterns across all platforms.

  **Why:** Consistency lowers the learning burden and makes support documentation reusable.

- **PKG-NFR-002** Present student-facing instructions at approximately a ninth-grade reading level while retaining correct industry terminology.

  **Why:** IT 140 is a first programming course with students from many academic and technical backgrounds.

- **PKG-NFR-003** Define an abbreviation or specialized technical term when it first appears in student-facing output.

  **Why:** Beginners should not need outside knowledge to follow a required setup process.

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

- **PKG-NFR-012** Keep authoritative requirement data in the manifest and avoid duplicated hardcoded lists that can drift apart.

  **Why:** A change should be made once and used by all four scripts.

- **PKG-NFR-013** Organize each script into small, purpose-specific functions or equivalent units with descriptive names.

  **Why:** Small units are easier to review, test, reuse, and repair.

- **PKG-NFR-014** Include comments that explain important intent, safety boundaries, and non-obvious decisions rather than restating each command.

  **Why:** Maintainers need to understand why a design choice exists.

- **PKG-NFR-015** Include a script version and maintain a change history through Git commits and releases.

  **Why:** Support personnel must be able to identify the code that produced a result.

- **PKG-NFR-016** Support automated tests for manifest parsing, platform detection, managed-path validation, exit codes, redaction, and idempotence.

  **Why:** Safety-critical logic should be tested without requiring a full manual installation for every change.

- **PKG-NFR-017** Pass the approved static-analysis tool for its scripting language with no unresolved high-severity findings.

  **Why:** Static analysis detects common errors before a script is run.

### 2.4 Portability

The package shall:

- **PKG-NFR-018** Maintain one platform-agnostic design for the four lifecycle operations and use separate platform implementations only where operating-system commands differ.

  **Why:** Shared logic reduces inconsistent behavior across platforms.

- **PKG-NFR-019** Derive home, desktop, temporary, configuration, and executable paths from the running environment rather than assuming a specific username.

  **Why:** Account names and standard folders vary across computers and platforms.

- **PKG-NFR-020** Quote or otherwise safely handle paths that contain spaces or special characters.

  **Why:** Common Windows and macOS paths include spaces.

- **PKG-NFR-021** Produce equivalent required outcomes on all supported platforms even when the implementation commands differ.

  **Why:** Students should receive the same course capabilities regardless of platform.

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

---

## 3. Technology Constraints

### 3.1 Shared Technology Constraints

The package shall:

- **PKG-TC-001** Use a platform-native scripting language approved for the target operating system.

  **Why:** Native tools reduce prerequisites and simplify execution for beginners.

- **PKG-TC-002** Use only software and services available to students without an additional course-related fee.

  **Why:** Every enrolled student must be able to complete course work without purchasing development software.

- **PKG-TC-003** Store source scripts and text configuration in UTF-8 with Line Feed (LF) line endings as defined by the repository `.gitattributes` file.

  **Why:** Consistent line endings reduce cross-platform script and submission problems.

- **PKG-TC-004** Use JSON for the shared manifest and validate it before use.

  **Why:** JSON is readable, portable, and supported by all target scripting environments.

- **PKG-TC-005** Store logs and support bundles under the current user's `~/it140/logs/` folder or the exact platform-equivalent path derived from the home folder.

  **Why:** A standard location helps students and support personnel find diagnostic files.

- **PKG-TC-006** Support only operating-system releases that still receive vendor security updates and that have been approved and tested for IT 140.

  **Why:** Unsupported systems may contain known security problems or incompatible tools.

- **PKG-TC-007** Use the course-required Python major and minor version declared by the manifest and aligned with the version used by required course activities.

  **Why:** Matching Python versions reduces differences between demonstrations, tests, and student results.

- **PKG-TC-008** Use Git, GitHub CLI, Python, pytest, pytest-cov, Ruff, VS Code, and approved VS Code extensions when those items are declared as required in the manifest.

  **Why:** These tools support version control, programming, provided tests, code quality, and course file formats.

- **PKG-TC-009** Use the current user's home folder as the base for user-owned course files and shall not require a fixed account name.

  **Why:** The package must work for different students and faculty accounts.

### 3.2 Codio Virtual Desktop Constraints

The CVD implementation shall:

- **CVD-TC-001** Target the approved Ubuntu 24.04 LTS CVD with the Xfce desktop until the manifest approves a different CVD release.

- **CVD-TC-002** Use Bash for CVD shell scripts and the Advanced Package Tool (APT) for Ubuntu system packages.

- **CVD-TC-003** Run student-facing scripts as the standard CVD user and use passwordless `sudo` only for approved system-level commands.

- **CVD-TC-004** Avoid restarting the active virtual desktop or its remote-display service during an update. When a restart is required, the script shall instruct the user to save work and use the approved CVD restart control.

- **CVD-TC-005** Derive user paths from `$HOME` and shall not hardcode `/home/codio` or another account path.

- **CVD-TC-006** Place system-wide browser policies and package repositories in `setup`, while placing Xfce user preferences, user launchers, VS Code user settings, and user-scoped extensions in `configure`.

- **CVD-TC-007** Use official Ubuntu, GitHub, Microsoft, Python, and VS Code distribution channels approved by the manifest.

### 3.3 Additional Platform Variants

A new platform variant shall not be marked supported until it:

- Implements all applicable requirements in this SRS.
- Has an approved platform abbreviation and native script extension.
- Has documented bootstrap instructions.
- Has platform-specific technology constraints.
- Passes the full acceptance-test set on a clean supported environment.
- Produces equivalent required outcomes to the reference platform.

---

## 4. Quality of Service Constraints

### 4.1 Reliability and Idempotence

The package shall:

- **PKG-QOS-001** Make `setup`, `configure`, and `update` idempotent.

- **PKG-QOS-002** Keep `verify` read-only, including when a check fails.

- **PKG-QOS-003** Leave the environment in a recoverable state after an interruption, failed download, failed package operation, or user cancellation.

- **PKG-QOS-004** Use staged or atomic replacement for course-managed files. An atomic replacement makes the complete new file visible at once instead of exposing a partially written file.

- **PKG-QOS-005** Prevent concurrent operations when simultaneous execution could corrupt package-manager, manifest, or managed-file state.

- **PKG-QOS-006** Preserve an already compliant required component when another independent component fails.

### 4.2 Performance and User Feedback

The package shall:

- **PKG-QOS-007** Display identifying information and the first meaningful status message within five seconds under normal supported conditions.

- **PKG-QOS-008** Avoid more than 60 seconds of silent operation during a long-running setup or update. The script shall display a truthful status message when the underlying tool does not provide visible progress.

- **PKG-QOS-009** Complete verification within 90 seconds on the approved reference CVD when required services are responsive and no support bundle is requested.

- **PKG-QOS-010** Avoid repeated downloads or installations when a compliant component can be verified locally.

### 4.3 Error Handling and Exit Codes

The package shall:

- **PKG-QOS-011** Stop a dependent stage after a required prerequisite fails while continuing only independent checks or cleanup that are safe.

- **PKG-QOS-012** Report the failed stage, a plain-language description, the underlying command or check when safe to disclose, and the recommended remediation.

- **PKG-QOS-013** Preserve the original nonzero result when error handling or log cleanup runs.

- **PKG-QOS-014** Use the following exit codes consistently:

| Exit code | Meaning |
| :--:      | ---     |
| `0`       | All required operations or checks completed successfully. Informational restart guidance may still be present. |
| `1`       | One or more required operations or checks failed. |
| `2`       | Invalid use, unsupported platform, or unsupported operating-system release. |
| `3`       | Required permission or privilege was unavailable. |
| `4`       | An approved external source, network service, or package service was unavailable after retries. |
| `5`       | The manifest or a course-managed asset was missing, invalid, corrupt, or failed integrity validation. |
| `6`       | The user canceled a required interactive operation. |
| `7`       | The run completed only partially and must be rerun or remediated before the environment is considered compliant. |

- **PKG-QOS-015** Use the most serious applicable exit code when more than one problem is detected.

### 4.4 Logging and Diagnostics

The package shall:

- **PKG-QOS-016** Create a unique timestamped log for each run using the action name, platform, date, and time.

- **PKG-QOS-017** Record the script version, manifest release, platform, operating-system version, architecture, current user identifier, start time, end time, elapsed time, major stages, results, and final exit code.

- **PKG-QOS-018** Record enough version, path, permission, and configuration information to diagnose failures while following the redaction rules in `PKG-NFR-025`.

- **PKG-QOS-019** Write logs as readable UTF-8 plain text and keep the terminal output understandable when ANSI color codes are unavailable.

- **PKG-QOS-020** State the exact log path in the opening information and final summary.

- **PKG-QOS-021** Create a support bundle only after an explicit command option or user confirmation and list the files included before final creation.

- **PKG-QOS-022** Exclude student source files, repository contents, Git commit history, authentication data, and browser data from support bundles.

---

## 5. Sample Input and Output

The exact wording may vary by platform, but every implementation shall communicate the same required information. In these examples, lines beginning with `>` represent user input.

### 5.1 Setup: Successful System Installation

```text
============================================================
IT 140 COURSE IDE SETUP
============================================================
Script version  : 2026.07.25.1
Platform        : CVD
Operating system: Ubuntu 24.04 LTS
Current user    : codio
Log file        : /home/codio/it140/logs/setup_cvd_20260725_113000.log

[INFO] Checking operating system, architecture, disk space, network access, and sudo access...
[SUCCESS] Setup prerequisites passed.

[INFO] Installing required system packages and applications...
[SUCCESS] Required system components are installed.

[INFO] Verifying required commands and versions...
[SUCCESS] System-level course IDE verification passed.

============================================================
SETUP SUMMARY
============================================================
Required operations: PASS
Warnings           : 0
Next step          : Run configure_cvd.sh
Log file           : /home/codio/it140/logs/setup_cvd_20260725_113000.log
```

### 5.2 Configure: First User Configuration

```text
============================================================
IT 140 USER CONFIGURATION
============================================================
Script version: 2026.07.25.1
Platform      : CVD
Current user  : codio
Log file      : /home/codio/it140/logs/configure_cvd_20260725_114500.log

[INFO] Required system components are present.
[INFO] GitHub CLI is not currently authenticated.

[ACTION REQUIRED] The GitHub CLI will display a one-time code and open a browser.
Press Enter to begin, or type C to cancel.
>

[SUCCESS] GitHub authentication completed.
Git display name [PeteyPenmen]:
> Petey Penmen

[SUCCESS] Git identity configured with a GitHub noreply address.
[SUCCESS] Required Git, Python, VS Code, extension, folder, and launcher settings are configured.

Next step: Run verify_cvd.sh
```

### 5.3 Verify: One Required Failure

```text
============================================================
IT 140 ENVIRONMENT VERIFICATION
============================================================
Manifest release: 2026.07.25.1

PASS    Operating system: Ubuntu 24.04 LTS
PASS    Python: required version available
PASS    GitHub CLI: authenticated
FAIL    VS Code extension: charliermarsh.ruff is missing
PASS    Course folder: /home/codio/it140
PASS    Log directory: writable

Remediation for failed check:
Run configure_cvd.sh to install or repair user-scoped course extensions.

============================================================
VERIFICATION SUMMARY
============================================================
Passed        : 5
Warnings      : 0
Failed        : 1
Not applicable: 0
Result        : NOT COMPLIANT
Exit code     : 1
Log file      : /home/codio/it140/logs/verify_cvd_20260725_120000.log
```

### 5.4 Update: Successful Maintenance with Restart Guidance

```text
============================================================
IT 140 COURSE IDE UPDATE
============================================================
[INFO] Validating the current manifest and staging updated course assets...
[SUCCESS] Course-managed assets validated and refreshed.

[INFO] Updating supported operating-system and course software...
[SUCCESS] Required packages and applications are current.

[INFO] Updating required Python tools and VS Code extensions...
[SUCCESS] Required user tools are current.

[INFO] Running post-update checks...
[SUCCESS] Post-update checks passed.

============================================================
UPDATE SUMMARY
============================================================
Required operations: PASS
Warnings           : 0
Restart required   : Yes
Next step          : Save your work, restart the virtual machine, and run verify_cvd.sh.
Log file           : /home/codio/it140/logs/update_cvd_20260725_121500.log
Exit code           : 0
```

---

## 6. Acceptance Test Cases

An **acceptance test** checks whether the completed software meets an agreed requirement. Each test below identifies the requirement or requirements, test condition, expected result, and pass criteria.

### 6.1 Package-Level Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
|---|---|---|---|
| AT-PKG-001 | PKG-FR-001, PKG-FR-002 | Inspect one fully supported platform implementation. | Exactly four correctly named lifecycle scripts are present, documented, and executable by the intended user. |
| AT-PKG-002 | PKG-FR-003, PKG-QOS-014 | Run a platform script on a different or unsupported OS. | The script makes no managed change, explains the mismatch, writes a log when possible, and exits with code `2`. |
| AT-PKG-003 | PKG-FR-004, PKG-FR-005, PKG-FR-019 | Replace the manifest with invalid JSON. | The script stops before managed changes, identifies the invalid manifest, and exits with code `5`. |
| AT-PKG-004 | PKG-FR-006 through PKG-FR-009 | Run each script under a normal supported condition. | Each run shows required opening information, creates a timestamped log, ends with a summary, and returns the documented exit code. |
| AT-PKG-005 | PKG-FR-010, PKG-FR-020 | Place student files and an unrelated repository beside managed assets, then run all applicable scripts. | File contents, timestamps, Git history, and repository state remain unchanged. |
| AT-PKG-006 | PKG-NFR-025, PKG-QOS-018 | Use a test account with known username, email, and token-like values, then inspect output, logs, and bundle. | No password, token, private key, complete personal email address, or unapproved PII appears. |
| AT-PKG-007 | PKG-NFR-001, PKG-NFR-008, PKG-QOS-014 | Compare results from two supported platform variants. | Status terms, summary fields, remediation meanings, and exit-code meanings are equivalent. |

### 6.2 Setup Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
|---|---|---|---|
| AT-SET-001 | SET-FR-001 through SET-FR-008 | Run setup on a clean supported system with sufficient space, network access, and required privilege. | All required system components are installed, version checks pass, no user-specific account settings are created, and exit code is `0`. |
| AT-SET-002 | SET-FR-009, SET-FR-010, PKG-QOS-001 | Run setup twice on the same compliant system. | The second run succeeds without duplicate repositories, keys, policies, PATH entries, or package definitions. |
| AT-SET-003 | SET-FR-001, SET-FR-002 | Run setup without required administrative capability. | No system installation begins; the user receives permission guidance and exit code `3`. |
| AT-SET-004 | SET-FR-004, PKG-NFR-024 | Substitute an unapproved or integrity-failing download source in a controlled test. | The asset is rejected, the previous valid state is preserved, and exit code is `4` or `5` as applicable. |
| AT-SET-005 | SET-FR-006 | Run setup when maintenance updates are available but a newer OS release also exists. | Approved updates install; the OS release does not change. |
| AT-SET-006 | SET-FR-010 | Remove one course-managed system component and rerun setup. | The missing component is repaired without resetting unrelated system settings. |
| AT-SET-007 | SET-FR-011 | Use a test account with no GitHub authentication or VS Code user settings, then run setup. | Setup does not authenticate GitHub, create Git identity, or write user VS Code settings. |

### 6.3 Configure Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
|---|---|---|---|
| AT-CFG-001 | CFG-FR-002 through CFG-FR-014 | Run configure for a new standard user after successful setup. | Required folders, PATH entry, GitHub authentication, Git identity, tools, extensions, settings, and integrations are correctly established. |
| AT-CFG-002 | CFG-FR-005 | Run configure while GitHub CLI is already authenticated. | The existing valid authentication is used; no unnecessary login flow starts. |
| AT-CFG-003 | CFG-FR-006, PKG-QOS-014 | Cancel the required GitHub authentication flow. | Configure reports cancellation, does not claim success, preserves prior settings, and exits with code `6`. |
| AT-CFG-004 | CFG-FR-007, PKG-NFR-025 | Complete authentication with a known test account. | The correct GitHub noreply address is configured, but the complete address is redacted in logs and support output. |
| AT-CFG-005 | CFG-FR-011, CFG-FR-015 | Add unrelated valid VS Code settings and optional extensions, then run configure twice. | Required settings are merged; unrelated settings and optional extensions remain; no duplicate entries are created. |
| AT-CFG-006 | CFG-FR-012, PKG-NFR-019 | Run configure under two different home-directory paths, including one with spaces where supported. | All managed paths are derived correctly; no hardcoded username or `/home/codio` dependency is present. |
| AT-CFG-007 | CFG-FR-013 | Remove one managed user launcher or file association, then rerun configure. | The missing managed integration is repaired without resetting unrelated desktop preferences. |
| AT-CFG-008 | CFG-FR-001 | Attempt to run configure directly as root or the system administrator account when not required by the platform design. | Configure stops before personal settings are written and provides the correct standard-user command. |

### 6.4 Verify Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
|---|---|---|---|
| AT-VER-001 | VER-FR-003 through VER-FR-012 | Run verify on a fully compliant supported environment. | All required checks pass, summary totals are correct, result is compliant, and exit code is `0`. |
| AT-VER-002 | VER-FR-005, VER-FR-008 through VER-FR-012 | Remove one required system application. | Verify reports `FAIL`, names the related requirement, recommends setup, and exits with code `1`. |
| AT-VER-003 | VER-FR-006, VER-FR-009 | Remove one required user setting or extension. | Verify reports `FAIL`, recommends configure, and does not recommend setup. |
| AT-VER-004 | VER-FR-001, VER-FR-002, PKG-QOS-002 | Record checksums and modification times of managed files before and after verify. | No managed file or setting changes, and verify does not request administrative privilege. |
| AT-VER-005 | VER-FR-008, VER-FR-010 | Omit an optional component. | Verify reports `WARNING` or `NOT APPLICABLE`, does not classify the environment as failed solely for that item, and uses the correct exit code. |
| AT-VER-006 | VER-FR-013, PKG-QOS-021, PKG-QOS-022 | Request a support bundle from a test environment containing student source files. | The bundle is created only after explicit request and contains approved diagnostics but no student source, repository content, Git history, or authentication data. |
| AT-VER-007 | VER-FR-014 | Simulate an unsupported administrative condition that no lifecycle script can repair. | Verify explains the limitation and directs the user to the approved support channel. |

### 6.5 Update Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
|---|---|---|---|
| AT-UPD-001 | UPD-FR-001, UPD-FR-006, UPD-FR-013 | Run update on a compliant environment with no available changes. | The script verifies the environment, avoids unnecessary reinstallations, reports that required components are current, and exits with code `0`. |
| AT-UPD-002 | UPD-FR-003 through UPD-FR-008 | Make approved package, tool, extension, manifest, and managed-script updates available. | Approved updates install from staged validated sources and post-update checks pass. |
| AT-UPD-003 | UPD-FR-002, PKG-QOS-005 | Start a second updater while one update holds the environment lock. | The second updater makes no changes, reports the concurrent run, and exits nonzero. |
| AT-UPD-004 | UPD-FR-004, UPD-FR-005, PKG-QOS-003, PKG-QOS-004 | Interrupt a managed-asset download or supply a truncated file. | The installed valid asset remains usable; the incomplete file is not activated; rerunning update can recover. |
| AT-UPD-005 | UPD-FR-007 | Run update when a new OS release is available. | Packages may update, but the OS release remains unchanged. |
| AT-UPD-006 | UPD-FR-009, UPD-FR-011 | Install an optional extension and create student files, then run update and cleanup. | Optional extension and student files remain; required tools remain installed. |
| AT-UPD-007 | UPD-FR-010, PKG-FR-017 | Mark a test managed component obsolete in the manifest and place a similarly named user file outside the managed path. | Only the explicitly listed managed component is removed; the user file remains. |
| AT-UPD-008 | UPD-FR-012 | Cause a temporary network failure that resolves within the approved retry policy. | Update retries, continues when the source becomes available, and records the event in the log. |
| AT-UPD-009 | UPD-FR-014, UPD-FR-016 | Apply an update that requires a restart. | The summary clearly identifies the required restart and recommends verification after the restart. |
| AT-UPD-010 | UPD-FR-015 | Interrupt update after one independent stage succeeds, then rerun it. | The rerun detects the current state, avoids harmful duplication, completes remaining work, and produces a correct final result. |

### 6.6 Cross-Script Lifecycle Acceptance Tests

| Test ID | Requirements | Test input or condition | Expected result and pass criteria |
|---|---|---|---|
| AT-LFC-001 | PKG-FR-001, SET-FR-012, CFG-FR-016, VER-FR-001 | On a clean supported environment, run setup, configure, and verify in order. | Setup establishes system state, configure establishes user state, and verify reports full compliance without changing either state. |
| AT-LFC-002 | SET-FR-010, VER-FR-009 | Remove a required system component, run verify, run its recommended remediation, and verify again. | First verify recommends setup; setup repairs the component; second verify passes that check. |
| AT-LFC-003 | CFG-FR-015, VER-FR-009 | Damage a required user setting, run verify, run its recommended remediation, and verify again. | First verify recommends configure; configure repairs the setting; second verify passes that check. |
| AT-LFC-004 | UPD-FR-003, UPD-FR-013, UPD-FR-016 | Publish a new approved automation release, run update, and then verify. | Update installs the approved managed assets and environment changes; verify evaluates against the new manifest release and passes. |
| AT-LFC-005 | PKG-FR-010, PKG-FR-020 | Complete the full lifecycle in an environment containing student work and unrelated user settings. | The lifecycle reaches compliance without changing user-owned files or unrelated settings. |

---

## Appendix A: Initial Reference Environment

This appendix records the initial CVD baseline found in the repository at the document baseline commit. The manifest shall become the authoritative source. Items may change through approved requirements and release management.

### A.1 Reference Platform

- Ubuntu 24.04 LTS
- Xfce desktop
- Bash shell
- APT package manager
- Standard CVD user with controlled passwordless `sudo` for approved system operations

### A.2 Initial System Applications and Packages

| Component | Course purpose |
|---|---|
| `ca-certificates`, `curl`, `gpg` | Securely retrieve and validate approved software sources. |
| `direnv` | Apply approved project-specific environment settings when present. |
| Git | Track file changes and interact with repositories. |
| GitHub CLI (`gh`) | Authenticate with GitHub and perform approved repository actions from the terminal. |
| Python 3 | Write, run, and test IT 140 programs. |
| `python3-pip`, `python3-venv` | Install Python tools and create isolated Python environments when required by the design. |
| VS Code (`code`) | Edit, run, test, debug, and manage course files. |
| `tree` | Display folder structures in a readable form. |
| `xclip` | Support clipboard operations in the Xfce desktop environment. |
| `numlockx` | Apply the approved Num Lock desktop behavior. |

### A.3 Initial Python Tools

| Tool | Course purpose |
|---|---|
| pytest | Run tests supplied with course activities. |
| pytest-cov | Report test coverage when included with supplied tests. |
| Ruff | Identify Python code-quality issues and format Python code consistently. |

Students are expected to run provided tests; this package does not require students to create their own tests.

### A.4 Initial Required VS Code Extensions

| Extension identifier | Course purpose |
|---|---|
| `ms-python.python` | Provide Python language support in VS Code. |
| `charliermarsh.ruff` | Integrate Ruff code checking and formatting. |
| `hediet.vscode-drawio` | View and edit approved diagrams. |
| `streetsidesoftware.code-spell-checker` | Identify likely spelling errors in code comments and documentation. |
| `i2p-hub.i2p-pseudo` | Support course pseudoscript files. |
| `cweijan.vscode-office` | View supported office-document formats in VS Code. |

### A.5 Initial Managed-Asset Categories

- Automation scripts
- `it140_manifest.json`
- Course workspace configuration
- Documentation explicitly marked as course-managed
- Required extension definitions
- Course-managed launchers and file associations
- Approved browser policies and bookmarks
- Obsolete components explicitly listed by the manifest

---

## Appendix B: Requirements Traceability and Change Control

**Traceability** means linking each requirement to its design, implementation, and test. Every approved requirement in this SRS shall be traceable to:

1. A design element in the Software Design Description (SDD).
2. One or more implementation files or functions.
3. One or more acceptance or automated tests.
4. A Git issue, pull request, or commit when the requirement changes.

A proposed requirement change shall identify:

- The requirement IDs affected.
- The reason for the change.
- The platforms and scripts affected.
- Changes required in the manifest, SDD, code, tests, and student documentation.
- Compatibility or migration effects for existing installations.

The SRS version and repository baseline shall be updated after an approved change is merged.
