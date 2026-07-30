#!/usr/bin/env bash
# IT 140 Ubuntu verification script. Makes no intentional changes.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.3.0"
readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/verify_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${HOME}/.local/share/it140/venv"
FAILURES=0; WARNINGS=0; START=$(date +%s)
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
pass(){ printf '[PASS] %s\n' "$*"; }; fail(){ printf '[FAIL] %s\n' "$*"; FAILURES=$((FAILURES+1)); }; warn(){ printf '[WARNING] %s\n' "$*"; WARNINGS=$((WARNINGS+1)); }
printf '\n============================================================\nIT 140 UBUNTU GNOME VERIFICATION\n============================================================\n'
printf '[INFO] Script version   : %s\n[INFO] Current user     : %s\n[INFO] Log file         : %s\n' "$SCRIPT_VERSION" "$USER" "$LOG_FILE"
[[ $EUID -ne 0 ]] && pass "Running as a standard user." || fail "Do not run with sudo."
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == ubuntu ]] && pass "Ubuntu detected: ${PRETTY_NAME:-unknown}." || fail "Ubuntu was not detected."
  case ${VERSION_ID:-} in 22.04|24.04|26.04) pass "Supported LTS release detected: ${VERSION_ID}.";; *) fail "Unsupported Ubuntu release: ${VERSION_ID:-unknown}.";; esac
else fail "Cannot read /etc/os-release."; fi
command -v gnome-shell >/dev/null 2>&1 && pass "GNOME Shell is installed." || fail "GNOME Shell is not installed."
[[ $(uname -m) == x86_64 ]] && pass "Supported x86_64 architecture detected." || fail "Unsupported architecture: $(uname -m)."
[[ -d "$COURSE_ROOT/scripts/nix/Ubuntu" ]] && pass "Ubuntu automation scripts are present." || fail "Ubuntu automation scripts are missing."
[[ :$PATH: == *:"$COURSE_ROOT/scripts/nix/Ubuntu":* ]] && pass "Script directory is in PATH." || warn "Open a new Terminal to load the persistent script PATH."
for cmd in git gh code python3.12; do command -v "$cmd" >/dev/null 2>&1 && pass "$cmd is available." || fail "$cmd is missing."; done
if command -v python3.12 >/dev/null 2>&1; then
  [[ $(python3.12 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")') == 3.12 ]] && pass "Python 3.12 is active." || fail "Python 3.12 version check failed."
fi
[[ -x "$VENV_DIR/bin/python" ]] && pass "IT 140 Python environment exists." || fail "IT 140 Python environment is missing."
if [[ -x "$VENV_DIR/bin/python" ]]; then
  "$VENV_DIR/bin/python" -c 'import pytest, pytest_cov' >/dev/null 2>&1 && pass "pytest and pytest-cov are installed." || fail "Required Python packages are missing."
fi
gh auth status -h github.com >/dev/null 2>&1 && pass "GitHub CLI is authenticated." || fail "GitHub CLI is not authenticated. Run config_ubg.sh."
for key in user.name user.email init.defaultBranch core.autocrlf push.autoSetupRemote core.editor; do [[ -n $(git config --global --get "$key" || true) ]] && pass "Git setting $key is configured." || fail "Git setting $key is missing."; done
installed=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
for ext in ms-python.python charliermarsh.ruff hediet.vscode-drawio i2p-hub.i2p-pseudo streetsidesoftware.code-spell-checker cweijan.vscode-office; do grep -qx "$ext" <<<"$installed" && pass "VS Code extension $ext is installed." || fail "VS Code extension $ext is missing."; done
settings="$HOME/.config/Code/User/settings.json"; [[ -s $settings ]] && pass "VS Code user settings exist." || fail "VS Code user settings are missing."

result=PASS; exit_code=0
if ((FAILURES>0)); then result=FAIL; exit_code=1; elif ((WARNINGS>0)); then result=PASS_WITH_WARNINGS; exit_code=0; fi
printf '\n============================================================\nVERIFICATION SUMMARY\n============================================================\n'
printf '[INFO] Result           : %s\n[INFO] Failures         : %s\n[INFO] Warnings         : %s\n[INFO] Elapsed seconds  : %s\n' "$result" "$FAILURES" "$WARNINGS" "$(( $(date +%s)-START ))"
printf '[NOTICE] Log: %s\n' "$LOG_FILE"
exit "$exit_code"
