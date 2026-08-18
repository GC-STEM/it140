# Windows Install lifecycle tests

This suite exercises the production `scripts/win/install_it140.ps1` entry point on a
GitHub-hosted Windows runner without installing, repairing, or removing software on
the runner itself.

## Behavioral contract

The suite covers:

- `-Help` and `-Version` returning `0` without creating a transcript;
- successful manifest-driven convergence of required Windows system capabilities;
- preservation of a compatible application even when WinGet does not own it;
- malformed controlled configuration returning `5` before managed changes;
- unsupported Windows release returning `2` before managed changes;
- unavailable required administrator privilege returning `3` before managed changes;
- unavailable Windows Package Manager repair returning `4` before managed changes;
- ordinary post-install capability failure returning `7` / `PARTIAL` after mutation;
- preservation of student repositories and unrelated user files;
- summary/process-exit consistency; and
- semantic idempotence across two successful executions.

## Isolation model

The suite copies the production script plus the controlled manifest/schema beneath a
temporary `home/it140/` tree and launches the actual PowerShell entry point. The
production script's explicitly gated Install test seam reads a JSON state file for
observations that cannot safely be changed on a hosted runner: administrator status,
Windows release facts, free space, WinGet availability/ownership, installed command
capabilities, and deterministic package-install outcomes.

The seam is active only when `IT140_INSTALL_TEST_MODE=true` and
`IT140_INSTALL_TEST_STATE` names the state file. Normal student execution leaves both
unset and continues to use Windows APIs, the system drive, WinGet, and native
commands normally.

The state file supplies observations and records mock external effects only. It does
not supply expected lifecycle results, summary values, or exit codes.
