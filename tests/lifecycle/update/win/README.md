# Windows Update behavioral tests

This suite executes `scripts/win/update_it140.ps1` as a black-box Windows PowerShell process on the GitHub-hosted Windows runner.

The production script exposes an explicit `IT140_UPDATE_TEST_MODE` state seam so CI can exercise lifecycle branching, manifest validation, package/user-tool convergence, failure classification, transcript semantics, preservation, and idempotence without invoking UAC, WinGet, COM shortcuts, or registry-backed user configuration on the hosted runner. The seam is inert unless test mode is explicitly enabled.

The suite verifies success, unsupported context, privilege failure, external failure before and after a managed change, malformed controlled configuration, post-update partial failure, preservation of unrelated/student state, and semantic idempotence. Update never runs Windows Update or performs a Windows release upgrade.
