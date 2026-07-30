#!/usr/bin/env bash
# IT 140 Ubuntu course-component update and repair script. Does not upgrade Ubuntu.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.3.0"
readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/update_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${HOME}/.local/share/it140/venv"
readonly LOCK_FILE="${HOME}/.cache/it140-ubg-mutation.lock"
CHANGED=false; WARNINGS=0; START=$(date +%s)
mkdir -p "$LOG_DIR" "$(dirname "$LOCK_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
info(){ printf '[INFO] %s\n' "$*"; }; success(){ printf '[SUCCESS] %s\n' "$*"; }; warn(){ printf '[WARNING] %s\n' "$*"; WARNINGS=$((WARNINGS+1)); }; fail(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 's=$?; printf "[ERROR] Update stopped near line %s. Review %s\n" "${BASH_LINENO[0]:-unknown}" "$LOG_FILE" >&2; exit $([[ $CHANGED == true ]] && echo 7 || echo "$s")' ERR
exec 9>"$LOCK_FILE"; flock -n 9 || fail "Another IT 140 Ubuntu mutation script is running."
printf '\n============================================================\nIT 140 UBUNTU GNOME UPDATE\n============================================================\n'
info "Script version   : $SCRIPT_VERSION"; info "Log file         : $LOG_FILE"
[[ $EUID -ne 0 ]] || fail "Run as the standard desktop user, not with sudo."
# shellcheck disable=SC1091
source /etc/os-release
case ${VERSION_ID:-} in 22.04|24.04|26.04) ;; *) fail "Supported LTS releases are 22.04, 24.04, and 26.04.";; esac

info "Refreshing IT 140 automation files."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git clone --depth 1 https://github.com/GC-STEM/it140.git "$tmp/it140"
cp -a "$tmp/it140/scripts/." "$COURSE_ROOT/scripts/"
chmod 0755 "$COURSE_ROOT/scripts/nix/Ubuntu/"*.sh
CHANGED=true

info "Refreshing APT metadata and updating only IT 140 course components."
sudo apt-get -o Acquire::Retries=5 update
sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --only-upgrade git gh code python3.12 python3.12-venv ca-certificates curl jq xclip || warn "One or more APT course components could not be upgraded."
[[ -x "$VENV_DIR/bin/python" ]] || python3.12 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip pytest pytest-cov

extensions=(ms-python.python charliermarsh.ruff hediet.vscode-drawio i2p-hub.i2p-pseudo streetsidesoftware.code-spell-checker cweijan.vscode-office)
for ext in "${extensions[@]}"; do code --install-extension "$ext" --force >/dev/null || warn "Could not update VS Code extension $ext."; done

printf '\n============================================================\nUPDATE SUMMARY\n============================================================\n'
printf '[INFO] Result           : %s\n[INFO] Warnings         : %s\n[INFO] Ubuntu upgraded  : No\n[INFO] Elapsed seconds  : %s\n' "$([[ $WARNINGS -eq 0 ]] && echo PASS || echo PARTIAL)" "$WARNINGS" "$(( $(date +%s)-START ))"
success "IT 140 course components were updated or repaired."
printf '[NOTICE] Open a new Terminal, then run config_ubg.sh or verify_ubg.sh.\n[NOTICE] Log: %s\n' "$LOG_FILE"
