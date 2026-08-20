#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.3.0"
readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/bootstrap_ubg_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'printf "[ERROR] Bootstrap stopped near line %s. Review %s\n" "${BASH_LINENO[0]:-unknown}" "$LOG_FILE" >&2' ERR

printf '\n============================================================\nIT 140 UBUNTU GNOME BOOTSTRAP\n============================================================\n'
printf '[INFO] Script version : %s\n[INFO] Course root    : %s\n[INFO] Log file       : %s\n' "$SCRIPT_VERSION" "$COURSE_ROOT" "$LOG_FILE"

[[ ${EUID} -ne 0 ]] || { printf '[ERROR] Run this command as your standard desktop user, not with sudo.\n' >&2; exit 2; }
[[ -r /etc/os-release ]] || { printf '[ERROR] Cannot identify Ubuntu.\n' >&2; exit 2; }
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || { printf '[ERROR] This script supports Ubuntu Desktop only. Detected: %s\n' "${PRETTY_NAME:-unknown}" >&2; exit 2; }
case ${VERSION_ID:-} in 22.04|24.04|26.04) ;; *) printf '[ERROR] Supported Ubuntu LTS releases: 22.04, 24.04, and 26.04. Detected: %s\n' "${VERSION_ID:-unknown}" >&2; exit 2;; esac
[[ ${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-} == *GNOME* || ${XDG_CURRENT_DESKTOP:-} == *ubuntu* ]] || printf '[WARNING] GNOME was not detected. The scripts are designed for Ubuntu Desktop with GNOME.\n'

if ! command -v git >/dev/null 2>&1; then
  printf '[INFO] Installing Git and certificate support. Ubuntu may request your password.\n'
  sudo apt-get -o Acquire::Retries=5 update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y git ca-certificates
fi

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
git clone --depth 1 https://github.com/GC-STEM/it140.git "$temp_dir/it140"
mkdir -p "$COURSE_ROOT"
find "$COURSE_ROOT" -mindepth 1 -maxdepth 1 ! -name logs -exec rm -rf {} +
cp -a "$temp_dir/it140/." "$COURSE_ROOT/"
rm -rf "$COURSE_ROOT/.git"
chmod 0755 "$COURSE_ROOT/scripts/nix/ubg/"*.sh

path_line='export PATH="$HOME/it140/scripts/nix/ubg:$PATH"'
touch "$HOME/.bashrc"
grep -qxF "$path_line" "$HOME/.bashrc" || printf '\n%s\n' "$path_line" >> "$HOME/.bashrc"

printf '[SUCCESS] IT 140 automation files were retrieved.\n'
printf '[NOTICE] Open a new Terminal, then run setup_ubg.sh.\n[NOTICE] Log: %s\n' "$LOG_FILE"
