# macOS Update Behavioral Tests

This suite executes the production `scripts/mac/update_it140.zsh` entry point on
the GitHub `macos-15` Apple-silicon runner. Real macOS/Zsh/JXA/archive behavior is
retained; only Homebrew state, required command state, and external network/archive
observations are deterministic test boundaries.

The suite protects the faculty-verified macOS lifecycle baseline. Production test
seams are inert unless `IT140_UPDATE_TEST_MODE=true`; normal users continue to use
real administrator checks, network retrieval, Homebrew, and the normal filesystem.

Contracts covered: success, 2/3/4/5 failures, external failure after a controlled
asset change retaining exit 4, ordinary post-change failure as 7/PARTIAL,
protected user state, transcript consistency, and semantic idempotence.
