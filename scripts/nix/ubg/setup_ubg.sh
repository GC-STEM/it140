#!/usr/bin/env bash
# IT 140 Ubuntu Desktop with GNOME system setup and repair script.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.3.0"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_DIR="${COURSE_ROOT}/scripts/nix/Ubuntu"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/setup_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_FILE="${HOME}/.cache/it140-ubg-mutation.lock"
readonly VENV_DIR="${HOME}/.local/share/it140/venv"
WARNINGS=0; CHANGED=false; START=$(date +%s)
mkdir -p "$LOG_DIR" "$(dirname "$LOCK_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
info(){ printf '[INFO] %s\n' "$*"; }; success(){ printf '[SUCCESS] %s\n' "$*"; }; warn(){ printf '[WARNING] %s\n' "$*"; WARNINGS=$((WARNINGS+1)); }; fail(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 's=$?; printf "[ERROR] Setup stopped near line %s with exit status %s.\n[ERROR] Review %s\n" "${BASH_LINENO[0]:-unknown}" "$s" "$LOG_FILE" >&2; exit $([[ $CHANGED == true ]] && echo 7 || echo 1)' ERR
exec 9>"$LOCK_FILE"; flock -n 9 || fail "Another IT 140 Ubuntu mutation script is running."

printf '\n============================================================\nIT 140 UBUNTU GNOME SETUP\n============================================================\n'
info "Script version   : $SCRIPT_VERSION"; info "Deployment       : ubuntu_gnome_bare_metal"; info "Current user     : $USER"; info "Course root      : $COURSE_ROOT"; info "Log file         : $LOG_FILE"
[[ $EUID -ne 0 ]] || fail "Run as the standard desktop user, not with sudo."
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || fail "Ubuntu Desktop is required."
case ${VERSION_ID:-} in 22.04|24.04|26.04) ;; *) fail "Supported LTS releases are 22.04, 24.04, and 26.04.";; esac
[[ $(uname -m) == x86_64 ]] || fail "This release supports x86_64 Ubuntu systems."
command -v gnome-shell >/dev/null 2>&1 || warn "GNOME Shell was not detected."

info "Refreshing APT package metadata."
sudo apt-get -o Acquire::Retries=5 update
base=(ca-certificates curl git gnupg jq software-properties-common xclip python3-venv)
sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y "${base[@]}"
CHANGED=true

if [[ ${VERSION_ID} == 22.04 ]] && ! apt-cache show python3.12 >/dev/null 2>&1; then
  info "Adding the Deadsnakes PPA to provide Python 3.12 on Ubuntu 22.04 LTS."
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get -o Acquire::Retries=5 update
fi

if ! command -v gh >/dev/null 2>&1; then
  info "Adding the official GitHub CLI APT repository."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$(dpkg --print-architecture)" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
fi

if ! command -v code >/dev/null 2>&1; then
  info "Adding the official Microsoft Visual Studio Code APT repository."
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg >/dev/null
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main\n' "$(dpkg --print-architecture)" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
fi

sudo apt-get -o Acquire::Retries=5 update
sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y gh code python3.12 python3.12-venv
python3.12 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip pytest pytest-cov

mkdir -p "$HOME/.local/bin"
ln -sfn "$VENV_DIR/bin/python" "$HOME/.local/bin/python-it140"
ln -sfn "$VENV_DIR/bin/pytest" "$HOME/.local/bin/pytest-it140"
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  touch "$rc"
  line='export PATH="$HOME/it140/scripts/nix/Ubuntu:$HOME/.local/bin:$PATH"'
  grep -qxF "$line" "$rc" || printf '\n%s\n' "$line" >> "$rc"
done
chmod 0755 "$SCRIPT_DIR/"*.sh

elapsed=$(( $(date +%s)-START ))
printf '\n============================================================\nSETUP SUMMARY\n============================================================\n'
printf '[INFO] Result           : PASS\n[INFO] Warnings         : %s\n[INFO] Elapsed seconds  : %s\n' "$WARNINGS" "$elapsed"
success "The IT 140 system software is installed or repaired."
printf '[NOTICE] Open a new Terminal, then run config_ubg.sh.\n[NOTICE] Log: %s\n' "$LOG_FILE"
