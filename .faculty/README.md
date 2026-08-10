<!-- To see this file in a clean, formatted view, right-click on the filename and choose “Open Preview.” -->

# IT 140 Faculty Guide

---

## 🧪 Beta Testing

IT 140 has completed end-to-end (E2E) Alpha Testing of the major course IDE components and is now in Beta Testing with faculty and staff. During this phase, faculty may encounter incomplete activity repositories, documentation gaps, or environment-specific setup issues that were not identified during Alpha Testing.

The Codio Virtual Desktop (CVD) automation is expected to be reliable because each CVD begins from a standardized environment. Local Windows, macOS, and Linux computers vary in software, settings, permissions, security controls, and prior configurations, so Beta Testing may uncover conditions that were not encountered on fresh operating system installations.

**Beta testers**: Please report technical issues and feature requests using the **Issues** tab in the appropriate GitHub repository. An issue is any error, failed step, unexpected result, missing or incorrect behavior, broken link, or instruction that prevents or makes a course task difficult to complete. A feature request is a suggestion for improving the automation, documentation, repository structure, or user experience.

---

## Activity Metadata

- **Course**: IT 140 - *Introduction to Scripting*
- **Activity Title**: IT 140 Faculty Guide
- **Activity Type**: Faculty reference
- **Activity Purpose**: Orient faculty to the IT 140 course IDE, GitHub repository model, activity-repository release process, and faculty support resources.
- **Activity Description**: This guide explains how the IT 140 course repositories, automation scripts, course IDE, and GitHub workflow fit together. It also directs faculty to the Module One setup instructions and identifies where to report questions, concerns, technical issues, and feature requests.
- **Artifact Version**: 0.10.0-beta.1
- **Artifact Date**: 2026-08-09-23-59
- **Development Status**: Beta Testing

## Overview

IT 140 uses a standardized course integrated development environment (course IDE) and a set of GitHub repositories to provide a consistent programming experience across the Codio Virtual Desktop (CVD) and supported local computers.

The course automation handles the installation and configuration of the supported development tools. Faculty and students generally should **not** manually install Python, Visual Studio Code (VS Code), Git, GitHub CLI, course VS Code extensions, or make installer-specific configuration choices to ensure consistency across platforms and facilitate technical support.

The [main IT 140 repository](../README.md) is the central hub for:

- Course automation scripts
- Development and operational status
- Course activity repository links
- Activity repository release dates
- GitHub Issues and Discussions

## Course Repository Model

IT 140 uses different repositories for different purposes.

| Repository Type | Purpose | Should Faculty or Students Manually Clone It? |
| --- | --- | --- |
| [`it140`](https://github.com/GC-STEM/it140) | Central course hub for automation, development status, and links to course activity repositories | **No** |
| [`it140-m1-setup-tasks`](https://github.com/GC-STEM/it140-m1-setup-tasks) | Student-facing Module One instructions for setting up GitHub and the course IDE | **No** |
| Module assignment repositories | Starter files and instructions for individual programming assignments | **Yes, when directed by the activity** |
| `it140-projects` | Starter files and instructions for course projects and milestones | **Yes, when directed by the activity** |

The `it140` and `it140-m1-setup-tasks` repositories are infrastructure and documentation repositories. The automation may retrieve files from these repositories as part of the setup process, but faculty and students should not manually clone either repository to their computers.

Beginning with the Module Two Assignment, students will use the designated activity repository when directed by the course instructions. The standard workflow is to clone the activity repository from within the course IDE into the `Repos` folder in the user's home directory.

## Course IDE

The IT 140 course IDE is the standardized collection of development tools, settings, folders, and supporting files used to complete programming activities. The supported environment includes:

- Visual Studio Code (VS Code)
- Python 3.12
- Git
- GitHub CLI
- Course-supported VS Code extensions
- Course VS Code settings and configuration
- A `Repos` folder for course activity repositories

The Codio Virtual Desktop (CVD) is the course reference environment. Students may complete their programming work in the CVD or, when supported, configure the same course IDE on a local Windows, macOS, or Linux computer.

### Automated Setup

The course setup process uses automation so students do not need to make platform-specific installation and configuration decisions. Depending on the platform, the automation performs the following stages:

1. **Prepare** - Checks the computer and obtains the course automation files needed for setup.
2. **Install** - Installs or repairs the supported system-level development software.
3. **Configure** - Applies course settings, configures the user environment, and creates the course workspace.
4. **Verify** - Checks that the required software and configuration are working as expected.
5. **Update** - Applies later course-managed updates and repairs when needed.

Because the automation manages the supported installation, a separate manual tutorial for installing VS Code for Python is not part of the standard IT 140 workflow. Faculty and students also do not normally need to select VS Code installer options, manually add Python to the system path, or choose course extensions individually.

If a setup guide instructs the user to make a manual choice, follow that platform-specific instruction.

## GitHub in IT 140

GitHub is part of the recommended IT 140 development workflow.

During Module One, students are guided through setting up a GitHub account and connecting the course IDE to GitHub. This introduces Git and GitHub early in the course and prepares students to access later course activity repositories.

Beginning with the Module Two Assignment, students will use GitHub and VS Code to access designated assignment and project repositories. When directed by the activity instructions, students will clone the activity repository into their local `Repos` folder and work with those files in VS Code.

Students should **not** be instructed to clone the central `it140` repository or the `it140-m1-setup-tasks` repository.

For the student-facing GitHub account instructions, see the [Module One GitHub Setup Guide](https://github.com/GC-STEM/it140-m1-setup-tasks/blob/main/github/README.md).

## Course Activity Repository Releases

During Faculty Beta Testing, assignment and project repositories are being published progressively rather than all at once.

The current release status and Live ETA for each course activity repository are maintained in the [Course Activity Repositories](../README.md#course-activity-repositories) table in the main IT 140 repository.

An activity link in D2L Brightspace may reference a repository that has not yet reached its scheduled release date during Beta Testing. If a repository link does not resolve or the expected starter files are not yet available:

1. Check the activity's status and Live ETA in the main IT 140 repository.
2. If the scheduled release date has not arrived, no action is required.
3. If the repository is marked live or the scheduled release date has passed and the repository is still unavailable, report the problem as a [GitHub issue](https://github.com/GC-STEM/it140/issues).

Do not assume that an unreleased assignment repository represents a broken course link during the staged Beta release.

## Faculty Setup and Familiarization

Faculty are encouraged to complete the same Module One setup experience that students will use. This helps faculty become familiar with the course IDE and provides a working reference environment when helping students.

Start with the [IT 140 Faculty Setup Instructions](https://github.com/GC-STEM/it140-m1-setup-tasks/blob/main/.faculty/README.md).

Faculty should at minimum:

1. Set up a GitHub account for course use.
2. Access and configure the Codio Virtual Desktop (CVD).
3. Review the student-facing Module One setup instructions.
4. Verify that the course IDE works in the CVD.
5. Optionally set up the course IDE on a supported local computer for additional testing and convenience.

The Module One faculty guide contains the detailed steps for completing these tasks. This course-wide guide should be used for orientation and reference rather than as a substitute for the activity-specific setup instructions.

## Student Workflow at a Glance

The intended student workflow is:

1. **Module One:** Set up a GitHub account and configure the course IDE on at least the Codio Virtual Desktop (CVD).

2. **Modules Two through Four:** Open the designated assignment repository when directed, clone it into the `Repos` folder, and complete the activity in VS Code.

3. **Modules Five through Seven:** Use the designated project repository and continue working with project or milestone files as directed by the activity instructions.

4. **Throughout the course:** Use the course IDE for development and submit required coursework through D2L Brightspace as directed by the assignment or project instructions.

GitHub provides the course code repositories and development workflow. D2L Brightspace remains the course learning-management system for course content, submissions, grading, and student management.

## Common Faculty Questions

### Do students need a tutorial for installing VS Code for Python?

No. The standard course setup uses automation to install and configure the supported development environment. Students should follow the Module One setup instructions rather than a generic VS Code installation tutorial.

### Which options should students select in the VS Code or Python installers?

Normally, none. The course automation makes the supported installation and configuration choices. If a platform requires a manual choice, the platform-specific setup guide will identify it.

### Are students expected to use GitHub?

Yes. GitHub is part of the recommended course workflow. Students set up GitHub during Module One and then use GitHub with VS Code to access designated assignment and project repositories as directed by later course activities.

### Why is an assignment repository missing?

During Beta Testing, activity repositories are released progressively. Check the [Course Activity Repositories](../README.md#course-activity-repositories) table for the current status and Live ETA before reporting a missing repository.

### Should students clone the `it140` or `it140-m1-setup-tasks` repositories?

No. These are central infrastructure and setup-documentation repositories. Students should clone only the assignment or project repositories identified in the corresponding course activities.

## Questions, Concerns, or Issues

### Questions and Concerns

For the initial pilot term, post faculty questions, concerns, and feedback about the new course IDE or GitHub repositories in the [IT 140 Community of Practice](https://teams.microsoft.com/l/team/19%3A165fa3c3a9904a1999ca640d2ed13d27%40thread.tacv2/conversations?groupId=61d85fe7-44f7-4918-896f-bb83a07883c1&tenantId=2baef15b-b8de-423f-9d8a-46f3686d8848).

Do **not** post faculty-sensitive information in GitHub Discussions because the course repositories and discussion areas are also visible to students.

### Technical Issues and Feature Requests

If you encounter a technical issue with automation, repository content, documentation, or a course GitHub link, submit a GitHub issue in the repository where the problem occurs.

- Use the [`it140` Issues](https://github.com/GC-STEM/it140/issues) page for course-wide automation, central-hub, or repository-status problems.

- Use the [`it140-m1-setup-tasks` Issues](https://github.com/GC-STEM/it140-m1-setup-tasks/issues) page for Module One setup instructions or platform-specific setup problems.

- Once later activity repositories are live, report activity-specific problems in that activity's repository.

When reporting an issue, include the relevant platform, activity, step, expected result, actual result, and any error message or screenshot that can help reproduce the problem. Do not include passwords, authentication codes, access tokens, student information, or other private information.
