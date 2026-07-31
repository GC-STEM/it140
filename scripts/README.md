<!-- To see this file in a clean, formatted view, right-click on the filename and choose “Open Preview.” -->

# IT 140 Main Course Repository | Course Automation Scripts

- **Course**: IT 140 - *Introduction to Scripting*
- **Module Name**: Main Course Repository
- **Activity Name**: Course Automation Scripts
- **Activity Description**: This folder contains the automation scripts used in the IT 140 course.

> [!WARNING]
> This README file is under constructions. It is for students, faculty, and maintainers of the course automation scripts. If you have any suggestions, please open a [GitHub Issue](https://github.com/GC-STEM/it140/issues) with your suggestion.

{{SME TODO: Add documentation for the scripts directory. Include student-facing and instructor/tech support-facing information.}}

## Workflow for running scripts in Codio Virtual Desktop (CVD)

### Codio Administrators

1. Run the `master/install_ide.sh` script to set up the Codio environment for the course.
2. Publish the course master CVD.

### IT 140 Students

1. Copy, paste, and run the bootstrap commands from `prepare_ide.sh` in a terminal window. These commands will download the remaining automation scripts.
2. Run `update_ide.sh` to update the CVD to the latest version.
3. Run `configure_ide.sh` to configure the CVD for the course.
4. Run `verify_ide.sh` to verify that the CVD is configured correctly.
