# Ubuntu GNOME Update Behavioral Tests

This suite executes `scripts/nix/ubg/update_ubg.sh` as a black-box process on the
GitHub `ubuntu-24.04` runner. External mutation boundaries are deterministic test
doubles; the production lifecycle entry point, manifest queries, file handling,
summary generation, preservation rules, and exit-code resolution execute normally.

Contracts covered: success, unsupported context (2), privilege failure (3),
required external-source failure (4) before or after managed changes, controlled
configuration failure (5), ordinary post-change failure (7/PARTIAL), restart
required (7/PARTIAL), protected user state, transcript consistency, and semantic
idempotence.

Test seams are active only when `IT140_UPDATE_TEST_MODE=true`; normal Ubuntu GNOME
execution continues to use `/etc`, real sudo/APT/Git, and real user tools.
