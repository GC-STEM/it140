<!-- To see this file in a clean, formatted view, right-click on the filename and choose “Open Preview.” -->

# IT 140 Main Course Repository | Course Automation Scripts

This guide explains the purpose of the IT 140 Course Automation Scripts package, the common script lifecycle, and the platform folders used to prepare and maintain the course integrated development environment (IDE).

> [!IMPORTANT]
> This README is informative and navigational. Follow the [Module One Setup Tasks](https://github.com/GC-STEM/it140-m1-setup-tasks) for the exact commands and workflow for your course environment. Run only the scripts that match your selected platform.

## Table of Contents

- [IT 140 Main Course Repository | Course Automation Scripts](#it-140-main-course-repository--course-automation-scripts)
  - [Table of Contents](#table-of-contents)
  - [Document Metadata](#document-metadata)
  - [1. Package Overview](#1-package-overview)
  - [2. Course IDE Lifecycle](#2-course-ide-lifecycle)
  - [3. Shared Script Behavior](#3-shared-script-behavior)
  - [4. Platform Folders](#4-platform-folders)
  - [5. Codio Virtual Desktop (`cvd/`)](#5-codio-virtual-desktop-cvd)
  - [6. Windows (`win/`)](#6-windows-win)
  - [7. macOS (`mac/`)](#7-macos-mac)
  - [8. Linux (`nix/`)](#8-linux-nix)
    - [Ubuntu Desktop LTS (`nix/ubg/`)](#ubuntu-desktop-lts-nixubg)
    - [Other Linux Distributions](#other-linux-distributions)
  - [9. Supporting Package Folders](#9-supporting-package-folders)
  - [10. Logs and Help](#10-logs-and-help)

## Document Metadata

- **Course**: IT 140 - *Introduction to Scripting*
- **Module Name**: Main Course Repository
- **Activity Name**: Course Automation Scripts
- **Activity Description**: This folder contains the platform automation scripts used to prepare, install, configure, verify, and update the IT 140 course IDE.
- **Program Name**: IT 140 Course Automation Scripts
- **Artifact ID**: `IT140-SCRIPTS-README`
- **Artifact Version**: `0.1.0`
- **Version Date-Time Group**: `2026-08-01-14-59`
- **Status**: Draft for faculty review
- **SRS Baseline**: `IT140-SRS-SCRIPTS`, version `0.5.0`, version date-time group `2026-08-01-10-43`
- **SDD Baseline**: `IT140-SDD-SCRIPTS`, version `0.5.0`, version date-time group `2026-08-01-10-43`
- **Manifest Baseline Reviewed**: Automation release `0.5.1`, release date `2026-07-30`, status `draft`

## 1. Package Overview

The **IT 140 Course Automation Scripts** package helps students and faculty create a consistent, supportable programming environment. The course IDE includes the applications, command-line tools, Python runtime, extensions, settings, folders, and shortcuts needed for IT 140 coursework.

Different operating systems require different commands and installation methods. The scripts in each platform folder handle those differences while working toward the same required course outcomes. Students do not need to understand every platform-specific command to use the package, but they must select the folder that matches their course environment.

The package supports designated hosted and local environments that have been implemented, tested, documented, and approved for course use. A platform may be technically capable of running the software without yet being a course-supported environment.

## 2. Course IDE Lifecycle

Each fully supported platform uses the same five-stage lifecycle:

> **Prepare → Install → Configure → Verify → Update**

| Stage | Script | Student-facing purpose |
| --- | --- | --- |
| Prepare | `prepare_it140.<ext>` | Obtains or refreshes the course automation package and makes the remaining scripts available. On first use, students copy and run the provided preparation commands because the script package is not yet installed. |
| Install | `install_it140.<ext>` | Installs or repairs the system-level software required for the course IDE. It may request permission to make approved changes to the computer. |
| Configure | `configure_it140.<ext>` | Configures the current user's course folders, tools, IDE settings, extensions, account integrations, and course shortcuts. |
| Verify | `verify_it140.<ext>` | Checks the system and user configuration without changing it. The report identifies passed checks, warnings, failures, and the recommended next step. |
| Update | `update_it140.<ext>` | Maintains approved course IDE software and course-managed assets after the environment has been prepared. It does not replace Prepare or perform an operating-system release upgrade. |

The exact workflow depends on the environment's starting state. A local installation normally follows **Prepare → Install → Configure → Verify**. A student CVD begins from a course-managed image, so its initial workflow normally follows **Prepare → Update → Configure → Verify**. After setup, **Update** is used for periodic maintenance when directed by the course.

## 3. Shared Script Behavior

Although the commands differ by platform, the scripts follow common rules:

- **Protect coursework**: The scripts are designed to preserve student programs, assignment repositories, version-control history, optional tools, and unrelated settings.
- **Support safe reruns**: Prepare, Install, Configure, and Update are designed to be rerun when an approved course-managed item is missing or damaged.
- **Keep Verify read-only**: Verify reports the current condition without installing, repairing, updating, or removing software.
- **Explain results**: Each run identifies its purpose, reports important actions, and ends with a plain-language summary and recommended next step.
- **Create support records**: Each lifecycle run saves a timestamped log or transcript under `~/it140/logs/` or the equivalent folder for the current platform.
- **Provide course continuity**: If a local course IDE cannot be prepared successfully, students can continue their IT 140 coursework in the Codio Virtual Desktop while the local issue is resolved.

## 4. Platform Folders

| Folder | Environment | Script type | Intended use |
| --- | --- | --- | --- |
| [`cvd/`](cvd/) | Codio Virtual Desktop | Shell scripts (`.sh`) | Hosted reference environment provided through the course |
| [`win/`](win/) | Microsoft Windows | PowerShell scripts (`.ps1`) | Supported local Windows computers |
| [`mac/`](mac/) | macOS on Apple silicon | Z shell scripts (`.zsh`) | Supported local Mac computers with Apple silicon processors |
| [`nix/ubg/`](nix/ubg/) | Ubuntu Desktop LTS with GNOME | Shell scripts (`.sh`) | Supported local Ubuntu Desktop computers |

> [!CAUTION]
> Platform scripts are not interchangeable. For example, do not run a Linux shell script on Windows or a Windows PowerShell script on macOS. Use the course setup instructions to select the correct environment and script folder.

## 5. Codio Virtual Desktop (`cvd/`)

The [Codio Virtual Desktop](cvd/) is the IT 140 **reference environment**. It is a hosted Linux desktop that students open through the course rather than install directly on a personal computer. Course screenshots, demonstrations, troubleshooting reproduction, and primary acceptance testing use this environment.

The reference CVD uses Ubuntu 24.04 LTS, the APT package manager, the Xfce desktop environment, and an x86_64 processor architecture. Because the course master image already contains the shared system layer, students normally use the CVD scripts to obtain the current automation package, apply the approved initial updates, configure their own account, and verify the result.

CVD is also the course-continuity option when a local Windows, macOS, or Ubuntu installation is unavailable or being repaired.

## 6. Windows (`win/`)

The [Windows folder](win/) contains PowerShell scripts for a supported local Windows installation. These scripts use Windows-native tools and approved software sources to prepare and maintain the same course IDE capabilities provided by the reference environment.

The main `win/` lifecycle is intended for a supported Windows computer on which Windows is installed directly. The scripts manage only approved course components and keep system installation separate from the current user's configuration and account settings.

<!--

### Windows Hyper-V

{{SME TODO: Add a short description of the Windows Hyper-V environment and its intended use, which is more for script development and testing rather than regular course work. Include links to Microsoft documentation for students who want to explore Hyper-V. Note that this use is well beyond the scope of IT 140 but is presented here for completeness, especially for students who will not take a programming course after IT 140.}}

#### Windows Sandbox (WSB)

{{SME TODO: Add a short description of the Windows Sandbox (WSB) environment and its intended use, which is more for script development and testing rather than regular course work. Include links to Microsoft documentation for students who want to explore WSB. Note that this use is well beyond the scope of IT 140 but is presented here for completeness, especially for students who will not take a programming course after IT 140.}}

#### Windows Subsystem for Linux (WSL)

{{SME TODO: Add a short description of the Windows Subsystem for Linux (WSL) environment and its possible use as a Linux development environment with Windows as the host. Note that this use is well beyond the scope of IT 140 but is presented here for completeness, especially for students who will not take a programming course after IT 140.}}

-->.

## 7. macOS (`mac/`)

The [macOS folder](mac/) contains Z shell scripts for supported Mac computers with Apple silicon processors. Apple silicon includes processors such as the Apple M1, M2, M3, and later members of the same processor family.

The macOS lifecycle installs or repairs the approved system tools, configures the current user's course environment, verifies the result without making changes, and performs approved maintenance. Intel-based Macs are not included unless current course documentation explicitly identifies an approved Intel deployment profile.

## 8. Linux (`nix/`)

The [`nix/`](nix/) folder organizes course automation for Linux and other Unix-like operating-system families. A **Linux distribution**, often called a *distro*, combines the Linux operating-system core with a particular set of installation tools, software repositories, defaults, and desktop options.

Scripts written for one distribution are not automatically safe or compatible with another. Package managers, package names, file locations, permissions, and desktop integrations can differ even when the same applications are available.

### Ubuntu Desktop LTS (`nix/ubg/`)

[Ubuntu Desktop LTS](nix/ubg/) is the local Linux environment currently described by the course automation design. **LTS** means *Long-Term Support*, a release intended to receive maintenance and security updates for an extended period.

Ubuntu is a Debian-derivative Linux distribution. It uses the **Advanced Package Tool (APT)** package manager to obtain, install, repair, and update software from approved repositories. Ubuntu Desktop uses the **GNOME** desktop environment, which provides its windows, menus, settings, file manager, and other graphical desktop features.

The `ubg/` abbreviation means **Ubuntu GNOME**. Its shell scripts adapt the common course IDE lifecycle to Ubuntu's APT-based software management, Linux file permissions, user environment, and GNOME desktop integrations.

### Other Linux Distributions

{{SME TODO: Add that students and faculty can request support for other Linux distributions by opening a GitHub Issue requesting addition. They need to provide precise distribution name, version, and any relevant configuration details.}}

## 9. Supporting Package Folders

Two hidden folders support the platform scripts but are not separate student platforms:

| Folder | Purpose |
| --- | --- |
| [`.manifest/`](.manifest/) | Contains the controlled JavaScript Object Notation (JSON) manifest and schema that identify approved products, versions, sources, settings, platforms, and managed assets. Platform scripts read this shared information so they do not maintain conflicting software lists. |
| [`.dev/`](.dev/) | Contains development-only requirements, design, flowchart, pseudoscript, and testing artifacts used by faculty, maintainers, testers, administrators, and technical support. Operational scripts must not depend on this folder being present in a student installation. |

Students should not edit the controlled manifest, schema, engineering artifacts, or platform scripts unless a course activity specifically instructs them to do so.

## 10. Logs and Help

Every lifecycle script saves a timestamped plain-text log or transcript under the course log folder:

- **Windows**: `%USERPROFILE%\it140\logs\`
- **macOS, Linux, and CVD**: `~/it140/logs/`

When a script reports a warning or failure, keep the final summary and the exact log path. These records help instructors, AI support tools, and university technical support identify the script version, platform, completed actions, and point of failure without requiring the student to remember every message shown in the terminal.

Follow the remediation and next-step instructions printed by the script. When requesting help, provide the final summary and the applicable log file through the support method identified in the course.
