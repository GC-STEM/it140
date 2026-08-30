<!-- To see this file in a clean, formatted view, right-click on the filename and choose “Open Preview.” -->

# IT 140 Faculty Guide

---

## 🧪 Beta Testing

IT 140 has completed end-to-end (E2E) Alpha Testing of the major course IDE components and is now in Beta Testing with faculty and staff. During this phase, faculty may encounter incomplete activity repositories, documentation gaps, or environment-specific setup issues that were not identified during Alpha Testing.

The **Codio Virtual Desktop (CVD)** is the course reference environment and the preferred starting platform for students. The CVD automation is expected to be reliable because each CVD begins from a standardized environment. Local Windows, macOS, and Linux computers vary in software, settings, permissions, security controls, and prior configurations, so Beta Testing may uncover conditions that were not encountered on fresh operating system installations.

Local installation is optional for students. Students using unsupported operating systems or devices, such as Chromebooks or tablets, should normally use the CVD rather than trying to reproduce the course IDE on an unsupported platform.

**Beta testers**: Please report technical issues and feature requests using the **Issues** tab in the appropriate GitHub repository. An issue is any error, failed step, unexpected result, missing or incorrect behavior, broken link, or instruction that prevents or makes a course task difficult to complete. A feature request is a suggestion for improving the automation, documentation, repository structure, or user experience.

---

## Overview

IT 140 uses a standardized course integrated development environment (**course IDE**) and a set of GitHub repositories to provide a consistent programming experience across the Codio Virtual Desktop (CVD) and supported local computers.

The CVD is the **reference and preferred student environment**. Course instructions, screenshots, demonstrations, primary testing, and troubleshooting procedures use the CVD as their reference. Students may also configure the course IDE on a supported local Windows, macOS, or Linux computer, but local installation is optional.

The course automation handles the installation and configuration of the supported development tools. Faculty and students generally should **not** manually install Python, Visual Studio Code (VS Code), Git, GitHub CLI, course VS Code extensions, or make installer-specific configuration choices when using a supported setup guide. This helps keep environments consistent and makes technical problems easier to reproduce and support.

The [main IT 140 repository](../README.md) is the central hub for:

* Course automation scripts
* Development and operational status
* Course activity repository links
* Activity repository release dates
* GitHub Issues and Discussions

For first-time setup procedures, use the [Module One Setup Tasks repository](https://github.com/GC-STEM/it140-m1-setup-tasks).

## Platform Roles in IT 140

Several systems support IT 140, but they have different purposes.

| **Platform** | **Primary Role** |
| ------------ | ---------------- |
| **D2L Brightspace** | Authoritative course learning-management system for course content, assignment instructions, submissions, grading, instructor feedback, and student management |
| **Codio Virtual Desktop (CVD)** | Reference and preferred student development environment for completing programming work |
| **Supported local course IDE** | Optional alternative development environment on supported Windows, macOS, or Linux computers |
| **GitHub** | Hosts course repositories and supports the Git/GitHub development workflow |
| **Visual Studio Code** | Primary application used to create, edit, run, test, debug, and manage course files |

GitHub, VS Code, and Codio support the **development workflow**. They do not replace Brightspace as the course LMS.

**Assignment submissions, grading, and instructor feedback remain in D2L Brightspace unless an activity explicitly states otherwise.** Faculty should direct students to the Brightspace assignment instructions for submission requirements rather than treating a GitHub repository, Git commit, Codio workspace, or other development artifact as the official course submission.

## Course Repository Model

IT 140 uses different repositories for different purposes.

| **Repository Type** | **Purpose** | **Clone It?** |
| ------------------- | ----------- | :-----------: |
| [`it140`](https://github.com/GC-STEM/it140) | Central course hub for automation and links to other repos | No |
| [`it140-m1-setup-tasks`](https://github.com/GC-STEM/it140-m1-setup-tasks) | Student-facing Module One instructions for setting up GitHub and the course IDE | No |
| [`it140-m2-assignment`](https://github.com/GC-STEM/it140-m2-assignment) | Starter files and instructions for assignment | in Module 2 |
| [`it140-m3-assignment`](https://github.com/GC-STEM/it140-m3-assignment) | Starter files and instructions for assignment | in Module 3 |
| [`it140-m4-assignment`](https://github.com/GC-STEM/it140-m4-assignment) | Starter files and instructions for assignment | in Module 4 |
| [`it140-projects`](https://github.com/GC-STEM/it140-projects) | Starter files and instructions for projects and milestones | in Module 5 |

The `it140` and `it140-m1-setup-tasks` repositories are infrastructure and documentation repositories. The automation may retrieve files from these repositories as part of the setup process, but faculty and students should not manually clone either repository to their computers.

Beginning with the Module Two Assignment, students will use the designated activity repository when directed by the course instructions. The standard development workflow is to clone the activity repository from within the course IDE into the `Repos` folder in the user's home directory.

The repository contains the files students work with; **Brightspace remains the authoritative location for assignment requirements and submission**.

For more information about the repository model, see the [Course Repositories](https://github.com/GC-STEM/it140/wiki/Course-Repositories) wiki page.

## Course IDE

The IT 140 course IDE is the standardized collection of development tools, settings, folders, and supporting files used to complete programming activities. The supported environment includes:

* Visual Studio Code (VS Code)
* Python 3.12
* Git
* GitHub CLI
* Course-supported VS Code extensions
* Course VS Code settings and configuration
* A `Repos` folder for course activity repositories

### Why the CVD Is the Reference Environment

The **Codio Virtual Desktop (CVD)** is the course reference and preferred student environment.

The CVD provides several advantages for an introductory programming course:

* Each student begins from a consistent course-managed system image.
* Course screenshots, demonstrations, and instructions can use one reference environment.
* Faculty and technical support can more easily reproduce student problems.
* Students do not need administrator access to install the full course IDE on their personal computer.
* Students with unsupported operating systems or devices can still access the course environment through a browser.
* A configured CVD provides a fallback if a local installation later stops working.

Faculty should therefore encourage students to **configure and verify the CVD before relying on a local installation**, even when a student plans to complete most programming work locally.

The Brightspace link may be labeled **Optional Codio Virtual Desktop**. "Optional" means students are not required to perform all programming work in Codio. It does not change the CVD's role as the course reference environment or the recommendation that students configure it so they have a known working course IDE available.

### Local Course IDE

Students may optionally configure the same core course IDE on a supported local computer.

Local installation can be convenient for students who prefer to work directly on their own computers, but it introduces more variability because personal computers may have:

* Different operating-system versions
* Existing developer tools
* Different permissions
* Security or endpoint-management software
* Prior application configurations
* Employer, school, or family management restrictions

Students using a supported operating system should follow the appropriate automated local setup guide.

Students using an unsupported operating system or device—including Chromebooks, tablets, unsupported Windows or macOS versions, or other Linux distributions—should normally be directed to the **CVD**. The generic manual setup guide is available as a best-effort option for advanced users who intentionally want to configure an unsupported environment, but it is not the recommended student path.

For current setup options, see the [Setup Options](https://github.com/GC-STEM/it140-m1-setup-tasks/wiki/Setup-Options) wiki page.

### Automated Setup

The course setup process uses automation so students do not need to make platform-specific installation and configuration decisions. Depending on the platform, the automation performs the following stages:

1. **Prepare** - Checks the computer and obtains the course automation files needed for setup.
2. **Install** - Installs or repairs the supported system-level development software.
3. **Configure** - Applies course settings, configures the user environment, and creates the course workspace.
4. **Verify** - Checks that the required software and configuration are working as expected.
5. **Update** - Applies later course-managed updates and repairs when needed.

Because the automation manages the supported installation, a separate manual tutorial for installing VS Code for Python is not part of the standard supported IT 140 workflow. Faculty and students also do not normally need to select VS Code installer options, manually add Python to the system path, or choose course extensions individually.

If a setup guide instructs the user to make a manual choice, follow that platform-specific instruction.

If a script reports `FAIL`, `PARTIAL`, `NOT COMPLIANT`, a nonzero exit code, or another unexpected result, students should not guess at repairs or blindly continue. Direct them to the script's final summary, the current README, and [Setup Problems and Support](https://github.com/GC-STEM/it140-m1-setup-tasks/wiki/Setup-Problems-and-Support).

## GitHub in IT 140

GitHub is part of the recommended IT 140 development workflow.

During Module One, students are guided through setting up a GitHub account and connecting the course IDE to GitHub. This introduces Git and GitHub early in the course and prepares students to access later course activity repositories.

Beginning with the Module Two Assignment, students will use GitHub and VS Code to access designated assignment and project repositories. When directed by the activity instructions, students will clone the activity repository into their `Repos` folder and work with those files in VS Code.

Students should **not** be instructed to clone the central `it140` repository or the `it140-m1-setup-tasks` repository.

GitHub is **not the course LMS or grading system**. Students should follow the corresponding Brightspace activity for submission requirements. Faculty grading and feedback remain in D2L Brightspace.

For the student-facing GitHub account instructions, see the [Module One GitHub Setup Guide](https://github.com/GC-STEM/it140-m1-setup-tasks/blob/main/github/README.md).

For a broader explanation, see [GitHub in IT 140](https://github.com/GC-STEM/it140-m1-setup-tasks/wiki/GitHub-in-IT-140).

## Course Activity Repository Releases

During Faculty Beta Testing, assignment and project repositories are being published progressively rather than all at once.

The current release status and Live ETA for each course activity repository are maintained in the [Course Activity Repositories](../README.md#course-activity-repositories) table in the main IT 140 repository.

An activity link in D2L Brightspace may reference a repository that has not yet reached its scheduled release date during Beta Testing. If a repository link does not resolve or the expected starter files are not yet available:

1. Check the activity's status and Live ETA in the main IT 140 repository.
2. If the scheduled release date has not arrived, no action is required.
3. If the repository is marked live or the scheduled release date has passed and the repository is still unavailable, report the problem as a [GitHub issue](https://github.com/GC-STEM/it140/issues).

Do not assume that an unreleased assignment repository represents a broken course link during the staged Beta release.

## Faculty Setup and Familiarization

Faculty are encouraged to complete the same Module One setup experience that students will use. This helps faculty understand the student workflow and provides a working reference environment when helping students.

Start with the [IT 140 Faculty Setup Instructions](https://github.com/GC-STEM/it140-m1-setup-tasks/blob/main/.faculty/README.md).

Faculty should at minimum:

1. Set up a GitHub account for course use.
2. Access, configure, and verify the Codio Virtual Desktop (CVD).
3. Review the student-facing Module One setup instructions.
4. Become familiar with the student CVD experience and common success checkpoints.
5. Review the local setup options so you understand how to guide students who choose them.
6. Optionally set up the course IDE on a supported local computer for additional testing and convenience.

The CVD should be the faculty reference when comparing a student's environment with the intended course configuration. A local faculty installation is useful for familiarity and Beta Testing but is not a replacement for understanding the CVD workflow.

The Module One faculty guide contains the detailed steps for completing these tasks. This course-wide guide should be used for orientation and reference rather than as a substitute for the activity-specific setup instructions.

## Guiding Students

When helping students with the course environment:

* **Start with the current README.** The README files contain the current step-by-step procedures; the wikis provide explanation, context, and troubleshooting.

* **Prefer the CVD when environment choice is uncertain.** It is the course reference environment and usually provides the simplest path to a known supported configuration.

* **Treat local setup as optional.** Students do not need a working local installation to complete IT 140.

* **Use the supported local guide when applicable.** Students on supported Windows, macOS, or Ubuntu-GNOME systems should use the automated guide rather than manually assembling the environment.

* **Direct unsupported devices to the CVD.** Chromebooks, tablets, unsupported operating-system versions, and other unsupported platforms should normally use the CVD.

* **Keep coursework moving.** If a local setup problem is consuming substantial time, have the student continue in the CVD while the local issue is investigated.

* **Do not improvise system repairs.** Avoid advising students to disable security controls, remove unrelated software, bypass administrator restrictions, or run unexplained system commands.

* **Protect student information.** Do not ask students to post credentials, authentication codes, access tokens, private identifying information, or complete graded solutions in public GitHub areas.

* **Keep academic workflow in Brightspace.** Assignment submissions, grading, and instructor feedback remain in D2L Brightspace.

## Student Workflow at a Glance

The intended student workflow is:

1. **Module One - GitHub:** Set up a GitHub account for IT 140.

2. **Module One - Codio:** Configure the Codio Virtual Desktop (CVD).

3. **Module One - Optional Local Setup:** If students desire, configure the course IDE on a supported local Windows, macOS, or Linux computer. Students using unsupported devices or operating systems should normally continue using the CVD.

4. **Modules Two through Seven:** Open the designated repository when directed and paste the given commands to copy the repository to their GitHub account and clone it to their local `Repos` folder. Students may complete all assignment work in the course IDE—diagrams (flowcharts and maps), pseudocode, Python code, and their IDE Features reflection.

5. **Throughout the course:** Follow the activity instructions in D2L Brightspace and submit required coursework there. Faculty grading and feedback also remain in Brightspace.

GitHub provides course code repositories and supports the development workflow. The CVD and local course IDE provide development environments. **D2L Brightspace remains the authoritative course learning-management system for course content, submissions, grading, feedback, and student management.**

## Common Faculty Questions

### Is the CVD required?

Students are not required to perform all programming work in the CVD, but the CVD is the **reference and preferred starting environment**. Students should be encouraged to configure and verify it even if they plan to work primarily on a supported local computer.

Having a configured CVD gives students a known supported environment that matches course screenshots and demonstrations and provides a fallback if local setup fails.

### Can students complete the course entirely in the CVD?

Yes. A local installation is completely optional. Students can complete IT 140 using the CVD without installing the course IDE on their own computer.

### What should I tell a student using a Chromebook, tablet, or unsupported operating system?

Direct the student to the CVD. It is the recommended environment for unsupported devices and operating systems.

The generic manual local setup guide is available as a best-effort option for advanced users, but students should not be expected to modify an unsupported device or operating system to complete IT 140.

### What should I do if a student's local setup is taking too long to troubleshoot?

Help the student keep coursework moving by returning to the CVD first. The local problem can then be investigated without blocking course progress.

See [Setup Problems and Support](https://github.com/GC-STEM/it140-m1-setup-tasks/wiki/Setup-Problems-and-Support) for the information to collect and the appropriate support channel.

### Do students need a tutorial for installing VS Code for Python?

Normally, no. The standard supported course setup uses automation to install and configure the development environment. Students should follow the Module One setup instructions rather than a generic VS Code installation tutorial.

A generic manual setup procedure is available for students who intentionally choose manual installation, but it is not the preferred path on a supported operating system.

### Which options should students select in the course IDE installers?

Normally, none when using a supported automated setup. The course automation makes the supported installation and configuration choices. If a platform requires a manual choice, the platform-specific setup guide will identify it.

### Are students expected to use GitHub?

Yes. GitHub is part of the recommended course development workflow. Students set up a GitHub account during Module One and then use GitHub with course IDE to access designated assignment and project repositories as directed by later course activities.

### Do students submit assignments through GitHub or Codio?

No. **Assignment submissions, grading, and feedback remain in D2L Brightspace.** GitHub hosts repositories and supports the development workflow; Codio provides the reference development environment.

### Where do faculty grade work and provide feedback?

In **D2L Brightspace**. Brightspace remains the authoritative system for assignment submissions, grading, and instructor feedback.

### Why is an assignment repository missing?

During Beta Testing, activity repositories are released progressively. Check the [Course Activity Repositories](../README.md#course-activity-repositories) table for the current status and Live ETA before reporting a missing repository.

### Should students clone the `it140` or `it140-m1-setup-tasks` repositories?

No. These are central infrastructure and setup-documentation repositories. Students should clone only the assignment or project repositories identified in the corresponding course activities.

## Questions, Concerns, or Issues

### Questions and Concerns

For the initial pilot term, post faculty questions, concerns, and feedback about the new course IDE or GitHub repositories in the [IT 140 Community of Practice](https://teams.microsoft.com/l/team/19%3A165fa3c3a9904a1999ca640d2ed13d27%40thread.tacv2/conversations?groupId=61d85fe7-44f7-4918-896f-bb83a07883c1&tenantId=2baef15b-b8de-423f-9d8a-46f3686d8848).

Do **not** post faculty-sensitive information, student-specific grading information, or other private course information in GitHub Discussions because the course repositories and discussion areas are also visible to students.

### Technical Issues and Feature Requests

If you encounter a technical issue with automation, repository content, documentation, or a course GitHub link, submit a GitHub issue in the repository where the problem occurs.

* Use the [`it140` Issues](https://github.com/GC-STEM/it140/issues) page for course-wide automation, central-hub, or repository-status problems.
* Use the [`it140-m1-setup-tasks` Issues](https://github.com/GC-STEM/it140-m1-setup-tasks/issues) page for Module One setup instructions or platform-specific setup problems.
* Once later activity repositories are live, report activity-specific technical problems in that activity's repository.

When reporting an issue, include the relevant platform, activity, step, expected result, actual result, and any error message or screenshot that can help reproduce the problem. Do not include passwords, authentication codes, access tokens, student information, grades, complete assignment solutions, or other private information.

Questions about an individual student's submission, grade, or feedback should remain in the appropriate private Brightspace or university communication channel rather than a public GitHub area.

## Activity Metadata

* **Course**: IT 140 - *Introduction to Scripting*
* **Activity Title**: IT 140 Faculty Guide
* **Activity Type**: Faculty reference
* **Activity Purpose**: Orient faculty to the IT 140 course IDE, GitHub repository model, activity-repository release process, student workflow, and faculty support resources.
* **Activity Description**: This guide explains how the IT 140 course repositories, automation scripts, course IDE, GitHub workflow, Codio Virtual Desktop, and D2L Brightspace fit together. It also directs faculty to the Module One setup instructions and identifies where to report questions, concerns, technical issues, and feature requests.
* **Artifact Version**: 1.0.2
* **Artifact Date**: 2026-08-30-12-56
* **Development Status**: Pilot — Active Development
