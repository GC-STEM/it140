# IT 140 Windows Sandbox Setup

## What is Windows Sandbox?

Windows Sandbox is a lightweight desktop environment that allows you to safely run applications in isolation. It is ideal for testing scripts, software, and configurations without affecting your main operating system. Each time you run Windows Sandbox, it creates a clean instance of Windows, ensuring that any changes made within the sandbox do not persist after it is closed.

## Enable Windows Sandbox

{{SME TODO: Add check to see if Windows Sandbox is enabled.}}

{{SME TODO: Add link to official Microsoft documentation for enabling Windows Hyper-V and Windows Sandbox.}}

## Prerequisites

1. {{SME TODO: Determine prereqs, such as running the Windows bootstrap commands following instructions at <link>}}.

## Launch the IT 140 Windows Sandbox

1. Navigate to the `it140\scripts\win\wsb` directory in **File Explorer**.

2. Double-click the `it140-wsb.wsb` file to launch the IT 140 version of Windows Sandbox.
   > This will open a new window with a fresh instance of Windows Sandbox.
   > It will automatically run the IT 140 bootstrap and setup scripts.

3. Wait for the setup script to complete. It can take 15 minutes or more. When the setup is finished, a PowerShell window will popup and display the following message:

    ```text
    IT 140 Windows Sandbox is ready.
    Run config_win.ps1 to configure the current user.
    After configuration, open a new PowerShell window and run verify_win.ps1.
    ```

## Configure the IT 140 Windows Sandbox

1. In the open PowerShell window, run the following commands to configure the current user:

    ```powershell
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    .\scripts\win\config_win.ps1
    ```

