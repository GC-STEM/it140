<!-- To see this file in a clean, formatted view, right-click on the filename and choose “Open Preview.” -->

# Main Course Repository

* **Course**: IT 140 - *Introduction to Scripting*
* **Activity Name**: Main Course Repository
* **Activity Purpose**: Central hub for course automation, development status, and links to course activity repositories.
* **Artifact Version**: 0.10.0-beta.1
* **Artifact Date**: 2026-08-09
* **Development Status**: Beta Testing

---

## About This Repository

The `it140` repository is the central hub for the IT 140 course development environment. It contains the course automation scripts, development and operational status information, and links to the repositories used for individual course activities.

This repository is **not an assignment repository and should not be manually cloned by faculty or students**. The course automation obtains the files it needs automatically. Students should clone only the assignment or project repositories identified in their course instructions.

### Quick Links

* [Module One Setup Tasks](https://github.com/GC-STEM/it140-m1-setup-tasks)
* [GitHub Issues](../../issues)
* [GitHub Discussions](../../discussions)
* [Faculty Guide](.faculty/README.md)

---

## 🧪 Beta Testing

IT 140 has completed end-to-end (E2E) Alpha Testing of the major course IDE components and is now in **Beta Testing with faculty and staff**.

The Codio Virtual Desktop (CVD) automation is expected to be reliable because each CVD begins from a standardized environment. Local Windows, macOS, and Linux computers can have different software, settings, permissions, security controls, and prior configurations, so Beta Testing may uncover conditions that were not encountered during testing on fresh operating system installations.

If you encounter a problem or have a suggestion:

* Use this repository's **GitHub Issues** for course-wide automation, central-hub, or repository-status problems.
* Use the **Module One Setup Tasks Issues** for problems with Module One setup instructions or platform-specific setup.
* Use **GitHub Discussions** for questions or discussions that are appropriate for both faculty and students.
* Faculty can find additional faculty-only communication options in the [Faculty Guide](.faculty/README.md).

---

## Course Automation Scripts

The course automation creates and maintains a consistent IT 140 course IDE across supported environments.

| **Platform**           | **Phase** | **Prepare** | **Install** | **Configure** | **Verify** | **Update** |  **Live ETA** |
| ---------------------- | :-------: | :---------: | :---------: | :-----------: | :--------: | :--------: | :-----------: |
| [Codio](scripts/cvd)   |    🅱️     |      🟢     |      🟢     |       🟢      |     🟢     |     🟢     | Aug. 10, 2026 |
| [Windows](scripts/win) |    🅱️     |      🟢     |      🟢     |       🟢      |     🟢     |     🟢     | Aug. 10, 2026 |
| [macOS](scripts/mac)   |    🅱️     |      🟢     |      🟢     |       🟢      |     🟢     |     🟢     | Aug. 11, 2026 |
| [Linux](scripts/nix)   |    🅰️     |      🟡     |      🟡     |       🟡      |     🟡     |     🟡     |      TBD      |

* 🅱️ = Beta Testing (Staff & Faculty)
* 🅰️ = Alpha Testing

---

## Course Activity Repositories

Course activity repositories are being published progressively during Faculty Beta Testing. **Repositories marked Not Yet Published are not expected to be available until their scheduled Live ETA.**

A repository name becomes a link when that repository is live. During Beta Testing, D2L Brightspace may contain links to activities whose GitHub repositories have not yet reached their scheduled release date.

| **Module** | **Activity**              | **Activity Repository**                                                                           |   **Availability**   |  **Live ETA** |
| ---------- | ------------------------- | ------------------------------------------------------------------------------------------------- | :------------------: | ------------: |
| One        | Setup Tasks               | [it140-m1-setup-tasks](https://github.com/GC-STEM/it140-m1-setup-tasks)                           |        🟢 Live       | Aug. 10, 2026 |
|            |   - GitHub Account        | [GitHub Setup](https://github.com/GC-STEM/it140-m1-setup-tasks/blob/main/github/README.md)        |        🟢 Live       | Aug. 10, 2026 |
|            |   - Codio Virtual Desktop | [CVD Setup](https://github.com/GC-STEM/it140-m1-setup-tasks/blob/main/codio/README.md)            |        🟢 Live       | Aug. 10, 2026 |
|            |   - Local Computer        | [Optional Local Setup](https://github.com/GC-STEM/it140-m1-setup-tasks/blob/main/local/README.md) |        🟢 Live       | Aug. 10, 2026 |
| Two        | Assignment                | `it140-m2-assignment`                                                                             | 🚧 Not Yet Published | Aug. 12, 2026 |
| Three      | Assignment                | `it140-m3-assignment`                                                                             | 🚧 Not Yet Published | Aug. 13, 2026 |
| Four       | Assignment                | `it140-m4-assignment`                                                                             | 🚧 Not Yet Published | Aug. 14, 2026 |
| Five       | Project One               | `it140-projects`                                                                                  | 🚧 Not Yet Published | Aug. 15, 2026 |
| Six        | Milestone                 | `it140-projects`                                                                                  | 🚧 Not Yet Published | Aug. 16, 2026 |
| Seven      | Project Two               | `it140-projects`                                                                                  | 🚧 Not Yet Published | Aug. 17, 2026 |

If a repository is still unavailable **after its Live ETA**, please report the problem using GitHub Issues.

---

## Status Legend

### Development Status

* 🗺️ Planned
* 🗓️ Requirements
* 📝 Design
* 🚧 Construction
* 🅰️ Alpha Testing
* 🅱️ Beta Testing (Staff & Faculty)
* ✅ Ready for Pilot
* 🔧 Maintenance
* 📦 Archived

### Operational Status

* 🟢 Live
* 🟡 Known Issue
* 🔴 Unavailable
