# IT 140 Automation Scripts

*Pseudoscript* is a platform-agnostic, script-like representation of an automation task. It preserves the structure, sequence, comments, variables, and decision logic of a real script while expressing commands in plain language or generic operations rather than platform-specific syntax.

## Script Requirement Specification Notes

The four scripts form the **minimum complete lifecycle** for each supported platform:

1. `setup_any.<ext>` — establish the system-level course IDE.
2. `configure_any.<ext>` — establish the user-specific course environment.
3. `verify_any.<ext>` — assess both layers without changing them.
4. `update_any.<ext>` — maintain the supported environment over time.

I do **not** recommend adding another mandatory platform script for the first updated-course iteration. Instead, several essential capabilities should be assigned explicitly to these four scripts. Adding separate executables now would increase the development, testing, documentation, and support matrix without yet providing a clearly separate responsibility.

The current main repository also acts primarily as a course hub linking students to the individual activity repositories. That means the automation should manage the course environment and support files without treating students’ assignment repositories as course-managed files. fileciteturn7file0L10-L25

## Essential capabilities within the four scripts

| Capability                         | Owning script   | Reason                                                                                     |
| ---------------------------------- | --------------- | ------------------------------------------------------------------------------------------ |
| Repair missing system components   | `setup_any`     | Setup should be safely rerunnable and restore missing system-level components.             |
| Repair user configuration          | `configure_any` | Configure should be safely rerunnable without requiring a separate reset script.           |
| Produce support diagnostics        | `verify_any`    | Verification is already intended for students, instructors, AI support, and university IT. |
| Refresh course automation files    | `update_any`    | Students need corrected scripts and manifests as the course evolves.                       |
| Remove obsolete managed components | `update_any`    | Cleanup is part of maintaining the supported environment.                                  |
| Identify the correct remediation   | `verify_any`    | Each failed check should tell the user whether to rerun setup, configure, or update.       |

### 1. Make setup and configure idempotent

An idempotent script can be run repeatedly without causing damage or duplicating configuration.

That eliminates the immediate need for `repair_any.<ext>`. For example:

- A missing application, system package, or required VS Code extension → rerun `setup_any`.
- An incorrect user preference → rerun `configure_any`.
- An outdated package or extension → run `update_any`.
- An unknown problem → run `verify_any`.

This is simpler for students and support personnel than choosing among setup, configure, repair, reset, and update scripts.

### 2. Make course-file synchronization part of update

A synchronization capability is essential because students may receive a copied, non-Git version of the main repository. Otherwise, fixes to `verify`, `configure`, or other course support files would not reach existing installations.

I recommend that `update_any` refresh only **course-managed assets**, such as:

- Automation scripts
- The shared course IDE manifest
- Course workspace configuration
- Documentation expressly marked as managed
- Required VS Code extension definitions

It must not overwrite:

- Student Python files
- Student assignment repositories
- Student Git history
- Student-selected optional extensions
- Unrelated user settings

Include synchronization in `update_any`.

### 3. Make verification the support-collection script

The `verify_any` script should do the following:

- Remain read-only
- Display a plain-language summary
- Return standardized exit codes
- Save a timestamped transcript under `~/it140/logs/`
- Record relevant versions, paths, permissions, and configuration
- Redact credentials, tokens, email addresses, and other sensitive information
- Optionally create a sanitized support bundle
- Identify the recommended remediation command for every failed check

The current repository’s `verify_cvd.sh` contains only introductory comments and does not yet implement its stated checks, so this remains a major construction task. fileciteturn10file0L3-L23

## Supporting files that are required

### `course_ide_manifest.json`

Setup, configure, verify, and update must obtain shared requirements from one authoritative manifest rather than independently hardcoding them.

The manifest could define:

- Supported operating systems and releases
- Required applications
- Required language versions
- Required Python packages
- Required VS Code extensions
- Required Git settings (derived from GH account username and noreply email address obtained from `gh` cli)
- Managed paths
- Minimum disk-space requirements
- Current automation release
- Log-directory standard

This is particularly important because the current update script embeds separate lists of system packages and VS Code extensions. fileciteturn11file0L108-L137 Those lists also appear in the uploaded setup design, creating a future drift risk between setup, update, and verify.

### Platform bootstrap command set

Each platform needs a small documented command set that:

1. Creates `~/it140` and adds a desktop shortcut to it;
2. Adds the correct `~/it140/scripts/<platform>` directory to the user’s PATH;
3. obtains the current automation files;
4. verifies that the download succeeded;
5. sets appropriate permissions;
6. launches the correct setup or configuration script.

This is not meaningfully an installed script because the user needs it **before the scripts are available**. The existing copy-and-paste PowerShell and shell command sets fit this role.

## Scripts to defer

These may eventually be useful, but they are not yet “for sure” requirements.

| Possible script       | Recommendation                                                                                                               |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `repair_any.<ext>`    | Defer. Add only if idempotent setup/configure/update cannot provide safe remediation.                                        |
| `sync_any.<ext>`      | Defer if synchronization is incorporated into update.                                                                        |
| `reset_any.<ext>`     | Avoid initially. “Reset” is ambiguous and could overwrite preferences or coursework.                                         |
| `uninstall_any.<ext>` | Not needed to complete the course; potentially risky.                                                                        |
| `backup_any.<ext>`    | Defer. GitHub and LMS submission workflows should provide the primary protections.                                           |
| `clean_any.<ext>`     | Fold safe package/cache cleanup into update.                                                                                 |
| `support_any.<ext>`   | Fold sanitized diagnostic collection into verify.                                                                            |
| `launch_any.<ext>`    | Desktop shortcuts, PATH entries, and normal application launchers are sufficient.                                            |
| `test_any.<ext>`      | Use verify as the installed-environment acceptance test. Development tests can reside outside the student-facing script set. |

## Source and repository findings

Several current files need to be aligned with the four-script architecture before construction proceeds:

- The uploaded SRS, SDD, and software development worksheet are still generic templates containing unresolved placeholders. They do not yet establish formal lifecycle requirements or traceability for these scripts. fileciteturn0file0 fileciteturn0file1 fileciteturn0file2
- The uploaded [`setup_any.pseudo`](sandbox:/mnt/data/setup_any.pseudo) is currently a CVD Bash provisioning script rather than a platform-agnostic pseudoscript. It also includes user-specific operations such as user-local Python packages, Git configuration, VS Code extensions, desktop launchers, and Xfce panel configuration. Those responsibilities should be reassigned between setup and configure.
- The uploaded [`config_any.pseudo`](sandbox:/mnt/data/config_any.pseudo) is also executable CVD-specific Bash rather than platform-agnostic plain-language logic.
- The live `config_cvd.sh` appropriately includes GitHub authentication, Git identity, and VS Code user preferences, but its log is named `setup_<timestamp>.log`; it should use `configure_<timestamp>.log`. fileciteturn9file0L17-L24
- The live configuration script hardcodes `/home/codio/it140` in VS Code settings rather than deriving the path from `$HOME`. fileciteturn9file0L218-L246
- The live update script already has a strong, distinct scope: operating-system packages, Python tools, VS Code extensions, launcher refresh, cleanup, and reporting. fileciteturn11file0L139-L197
- The repository standardizes LF endings for shell, PowerShell, batch, command, and pseudoscript files, which supports consistent cross-platform source management. fileciteturn12file0L6-L23
- At the expected main-branch path, `scripts/cvd/setup_cvd.sh` is not currently present. The searchable CVD files are `config_cvd.sh`, `verify_cvd.sh`, and `update_cvd.sh`; the uploaded setup pseudoscript therefore represents planned work rather than a completed repository implementation.

## Proposed definitive script set

```text
setup_<platform>.<ext>
configure_<platform>.<ext>
verify_<platform>.<ext>
update_<platform>.<ext>
```

Standardizing on **`configure`**, rather than mixing `config` and `configure`, because all four filenames then begin with unambiguous action verbs.

The fifth operational capability—keeping course-managed automation assets current—should be an explicit requirement of `update_<platform>.<ext>`, not another script.
