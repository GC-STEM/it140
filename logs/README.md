<!-- To see this file in a clean, formatted view, right-click on the filename and choose “Open Preview.” -->

# IT 140 Main Course Repository | Script Log Files

* **Course**: IT 140 - *Introduction to Scripting*
* **Module Name**: Main Course Repository
* **Activity Name**: Script Log Files
* **Activity Purpose**: Help you understand and use the log files created by the IT 140 course automation scripts.
* **Artifact Version**: 1.0.3
* **Artifact Date-Time Group**: 2026-09-02-09-37
* **Development Status**: Pilot — Active Development

## What Are These Log Files?

When you run an IT 140 course automation script, the script saves a **log file**, also called a **transcript**.

The log records much of the same information that appears in the Terminal while the script runs. This gives you a record that you can review later if setup works differently than expected.

Logs can help you:

* Confirm whether a script completed successfully.
* Find warnings and errors.
* Identify which part of a script failed.
* See the script and course-automation versions that were used.
* Review the recommended next step or remediation.
* Give an instructor, technical support specialist, peer, or AI assistant useful troubleshooting information.

These files are for **technical troubleshooting**. They are not assignment submissions and are not part of your graded Python programs.

## Where Are the Logs?

The standard IT 140 log folder is:

| **Environment** | **Log folder** |
| --------------------------- | --------------------------- |
| Codio Virtual Desktop (CVD) | `~/it140/logs/` |
| macOS or Linux | `~/it140/logs/` |
| Windows | `%USERPROFILE%\it140\logs\` |

> [!NOTE]
> In file paths, ~/ and %USERPROFILE%\ both refer to your home folder—the folder associated with your user account.
>
> On **CVD, Linux, macOS, and Windows PowerShell**, `~/` represents your home folder. For example, `~/it140/logs/` on the CVD will expand to `/home/ubuntu/it140/logs/` on the CVD or `C:\Users\YourUsername\it140\logs\` on Windows.
> In **Windows Command Prompt**, `%USERPROFILE%\` represents your Windows user-profile folder. For example, `%USERPROFILE%\it140\logs\` will expand to `C:\Users\YourUsername\it140\logs\`.
>
> Using these shortcuts allows the course instructions to work without needing to know your specific username.
If you are reading this README from your CVD or local computer, the generated log files may already be in the same folder as this file.

You can open a `.log` file as a normal text file in VS Code or another text editor.

## How Log File Names Work

Each run creates a new log with a timestamp in its filename. This allows you to keep records from several runs without replacing the previous log.

For example:

`verify_cvd_20260817_063015.log`

The timestamp identifies when the log was created:

`YYYYMMDD_HHMMSS`

In the example above, the log was created on August 17, 2026, at 06:30:15.

When troubleshooting, usually choose the **newest log whose name matches the script that had the problem**.

## CVD Log Files

The CVD automation uses the following log files:

| Filename pattern | Script | What the log helps explain |
| ---------------- | ------- | --------------------------- |
| `prepare_ide_*.log` | `prepare_it140.sh` | Downloading or refreshing the IT 140 automation package, platform checks, preparation stages, and preparation failures |
| `install_cvd_*.log` | `install_it140.sh` | Installing or repairing required system-level course software and validating the installation |
| `configure_cvd_*.log` | `configure_it140.sh` | Configuring your course folders, Git and GitHub integration, Python tools, VS Code extensions and settings, shortcuts, and other user settings |
| `verify_cvd_*.log` | `verify_it140.sh` | Checking the current environment and reporting individual passed checks, warnings, failures, and remediation guidance |
| `update_cvd_*.log` | `update_it140.sh` | Maintaining approved software and course-managed files, including whether changes or a restart are required |

The exact details differ by script, but logs commonly contain information such as:

* Script version and version date
* Environment or platform
* Start and end times
* Actions performed
* Success messages
* Warnings
* Errors
* The stage where a failure occurred
* Number of warnings or failures
* Whether managed changes were made
* Recommended next step
* Exit code

## Start with the End of the Log

You normally do **not** need to understand every line.

Start near the bottom.

Most IT 140 scripts provide a final summary. Look for information such as:

* `Result`
* `Warnings`
* `Failures`
* `Failed`
* `Remediation`
* `Next step`
* `Exit code`

A successful Install, Configure, or Update normally ends with `PASS` and exit code `0`.

A successful Verify reports:

```text
Result : COMPLIANT
Failed : 0
Exit code : 0
```

Prepare uses a simpler success message telling you that the IT 140 automation package is ready and identifying the next step.

If you see `FAIL`, `PARTIAL`, `NOT COMPLIANT`, a nonzero exit code, or remediation instructions, read the recommended next step before making changes yourself.

For more information about the automation stages and their results, see the [Course Automation](https://github.com/GC-STEM/it140/wiki/Course-Automation) wiki page.

## Find the Important Part of a Failed Log

After reading the final summary, search upward in the log for terms such as:

```text
[ERROR]
[WARNING]
FAIL
Failed stage
Remediation
```

The most useful information is often the error plus the lines immediately before it. Those earlier lines can show what the script was trying to do when the problem occurred.

For example, instead of sharing hundreds of lines immediately, you can often begin troubleshooting with:

1. The final summary.
2. The first relevant error or failed check.
3. About 20–40 lines surrounding that error.
4. The name of the script you ran.
5. What you were doing when the problem occurred.

Keep the original log unchanged. If you need to remove private information before sharing a log, make a copy and edit the copy.

## Using a Log to Troubleshoot Independently

A log can often tell you what to do next without requiring you to understand the internal script code.

Use this approach:

1. Confirm that you selected the log for the script that had the problem.
2. Read the final summary.
3. Find the first relevant error, warning, or failed Verify check.
4. Read the nearby lines for context.
5. Follow any `Remediation` or `Next step` provided by the script.
6. Return to the setup README or course instructions before making other system changes.

Do not make random repairs just because an error message mentions a program, package, file, or setting. Course automation manages some parts of the environment for you.

For detailed setup troubleshooting guidance, see [Setup Problems and Support](https://github.com/GC-STEM/it140-m1-setup-tasks/wiki/Setup-Problems-and-Support).

## Using a Log with an AI Chatbot

An AI chatbot can help you translate technical log output into beginner-friendly language.

You usually do not need to begin by uploading the entire log. Start with the final summary and the relevant error section.

For example:

```text
I am troubleshooting the IT 140 course IDE.

Environment: Codio Virtual Desktop
Script: update_it140.sh
What I was trying to do: [brief description]
What happened: [brief description]

Final script summary:
[paste the summary]

Relevant log lines:
[paste the error and nearby lines]

Explain what the log is telling me in beginner-friendly language.
Suggest one safe troubleshooting step at a time.

Do not recommend deleting files, disabling security controls,
bypassing administrator restrictions, or changing important system
settings unless the official IT 140 instructions require that change.
```

AI tools can make mistakes. Review their suggestions before running commands.

If an AI assistant recommends deleting files, using unfamiliar administrator commands, changing security settings, or making a change you do not understand, stop and check the IT 140 instructions or ask your instructor or technical support.

The [Setup Problems and Support](https://github.com/GC-STEM/it140-m1-setup-tasks/wiki/Setup-Problems-and-Support#using-ai-for-setup-troubleshooting) page contains additional guidance for using AI during setup troubleshooting.

## Using a Log with a Peer

A classmate may recognize an error that they have already encountered.

When asking a peer for help, provide enough context to understand the problem:

* Which environment you are using
* Which script you ran
* What you expected to happen
* What happened instead
* The final summary
* The relevant error or failed check
* What troubleshooting you already tried

You usually do not need to send your entire log first.

Remember that a classmate's environment may not be identical to yours. Prefer solutions documented in the course instructions or confirmed by course faculty or technical support.

## Using a Log with Your Instructor or Technical Support

Logs are especially useful when someone else needs to diagnose a problem they cannot see on your computer.

When requesting help, include:

* Your environment, such as CVD, Windows, macOS, or Linux
* The setup README section or step
* The script involved
* What you expected
* What happened
* The final script summary
* The relevant log filename
* What you already tried

If requested, you can provide the relevant log file as an attachment after checking it for private information.

If the original problem occurred during one script and you later ran Verify, both logs may be useful. For example:

```text
update_cvd_20260817_061500.log
verify_cvd_20260817_062000.log
```

The first can show what happened during the update. The second can show the state of the environment afterward.

See [Status, Issues, and Discussions](https://github.com/GC-STEM/it140/wiki/Status-Issues-and-Discussions) for guidance about where to report course-wide technical problems or ask questions.

## Protect Your Private Information

A technical log can contain information about your computer or account, such as:

* Your local username
* File and folder paths
* Software versions
* Your Git display name or other account-related information
* Details about your system configuration

Before sharing a log with another person, posting it to GitHub, or providing it to an AI service, **review it first**.

Never share:

* Passwords
* Authentication or verification codes
* Personal access tokens
* Recovery codes
* Student identification numbers
* Private contact information
* Other credentials or secrets
* Complete solutions to graded assignments

When possible, share only the part of the log needed to understand the problem.

Public GitHub Issues and Discussions are visible to other people. A private message to your instructor is different from posting information publicly, but you should still avoid sending credentials or secrets.

For more guidance, see [Protect Your Private Information](https://github.com/GC-STEM/it140-m1-setup-tasks/wiki/Setup-Problems-and-Support#protect-your-private-information).

## Verify Can Create a Sanitized Support Directory

On the CVD, the Verify script has an optional support feature that course staff may ask you to use.

When requested, running:

```bash
verify_it140.sh --support-bundle
```

performs the normal verification and asks whether you want to create a sanitized diagnostic directory under:

```text
~/it140/logs/
```

The directory contains:

```text
system_summary.txt
verification.log
```

The system summary includes limited diagnostic information such as the operating system, processor architecture, desktop environment, and the status of selected course settings.

The support directory does **not** include the contents of your student repositories or your Git history.

Use this option when the course instructions, your instructor, or technical support asks you to create diagnostic information. You should still review the files before sharing them.

## Logs Are Part of Professional Troubleshooting

Learning to use logs is a useful software-development skill.

When a program or tool fails, developers often begin by asking:

> What does the log say happened?

You do not need to understand every message. Being able to identify the result, locate an error, preserve useful evidence, and explain what happened makes troubleshooting faster and helps others give you better assistance.

## More Help

* [Course Automation](https://github.com/GC-STEM/it140/wiki/Course-Automation) — what Prepare, Install, Configure, Verify, and Update do
* [Setup Problems and Support](https://github.com/GC-STEM/it140-m1-setup-tasks/wiki/Setup-Problems-and-Support) — detailed setup troubleshooting, AI guidance, privacy, and support channels
* [Status, Issues, and Discussions](https://github.com/GC-STEM/it140/wiki/Status-Issues-and-Discussions) — course-wide status and where to ask or report a problem

When a wiki page and the current setup README give different instructions, follow the current setup README and your IT 140 course instructions.
