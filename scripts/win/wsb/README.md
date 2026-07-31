# IT 140 Windows Sandbox Setup

## What is Windows Sandbox?

Windows Sandbox is a lightweight, temporary Windows environment used to test the IT 140 automation workflow without changing the host computer. Each launch starts with a fresh Windows image. Closing the sandbox permanently discards its installed software, settings, files, and logs.

Windows Sandbox is intended for faculty, SMEs, and technical-support testing. It is not part of the student setup workflow.

## Enable Windows Sandbox

{{SME TODO: Add check to see if Windows Sandbox is enabled.}}

{{SME TODO: Add link to official Microsoft documentation for enabling Windows Hyper-V and Windows Sandbox.}}

## Launch the IT 140 Windows Sandbox

1. Navigate to the `it140\scripts\win\wsb` directory in **File Explorer**.

2. Double-click `it140_wsb.wsb`.

   The configuration file launches a fresh Windows Sandbox, downloads `bootstrap_wsb.ps1`, retrieves the current course repository, and runs `setup_wsb.ps1`.

3. Allow the bootstrap and setup scripts to finish. The initial sandbox image is intentionally bare, so `setup_wsb.ps1` installs or repairs Windows Package Manager before installing the manifest-required course IDE software.

4. When setup succeeds, a normal Windows PowerShell continuation window opens and displays:

    ```text
    IT 140 Windows Sandbox is ready.
    Run configure_ide.ps1 to configure the current user.
    After configuration, close this window, open the desktop shortcut again, and run verify_ide.ps1.
    ```

## Configure the Sandbox User

In the continuation PowerShell window, run:

```powershell
configure_ide.ps1
```

Complete any interactive GitHub authentication prompts. The tested Windows configuration script automatically recognizes the `WDAGUtilityAccount` account and uses the `windows_sandbox` deployment profile.

## Verify the Sandbox

1. Close the configuration PowerShell window.
2. Double-click **Continue IT 140 Setup** on the Windows Sandbox desktop.
3. In the new PowerShell window, run:

    ```powershell
    verify_ide.ps1
    ```

The tested Windows verification script automatically recognizes the Windows Sandbox deployment profile.

## Lifecycle Scope

The Windows Sandbox lifecycle is:

```text
it140_wsb.wsb
    -> bootstrap_wsb.ps1
    -> setup_wsb.ps1
    -> configure_ide.ps1
    -> verify_ide.ps1
```

Do not run `update_ide.ps1` in Windows Sandbox. Every sandbox launch starts from a fresh Windows image, so periodic maintenance does not apply.

## Logs

All script transcripts are stored under:

```text
C:\Users\WDAGUtilityAccount\it140\logs
```

Copy any needed logs or screenshots to the host computer before closing Windows Sandbox. Closing the sandbox discards them.
