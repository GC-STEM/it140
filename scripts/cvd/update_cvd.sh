#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop update script
#
# Audience: IT 140 students and faculty using the Codio Virtual Desktop
# Purpose: Update the supported Ubuntu 24.04 course environment, including
#          system packages, the course IDE, Python command-line tools, and
#          VS Code extensions.
#
# Run this script as the standard CVD desktop user. Do not run it with sudo.
# The script invokes passwordless sudo only for system-level package changes.
# It does not perform an Ubuntu release upgrade or modify student coursework.

set -Eeuo pipefail
umask 022

SCRIPT_VERSION="2026.07.24.1"
LOG_DIR="$HOME/it140/logs"
LOG_FILE="$LOG_DIR/update_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'status=$?; printf "\nERROR: CVD update stopped at line %s (exit %s).\nReview: %s\n" "$LINENO" "$status" "$LOG_FILE" >&2; exit "$status"' ERR

print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

print_info() {
    printf '[INFO] %s\n' "$1"
}

print_success() {
    printf '[SUCCESS] %s\n' "$1"
}

print_notice() {
    printf '[NOTICE] %s\n' "$1"
}

print_error() {
    printf '[ERROR] %s\n' "$1" >&2
}

# Prevent user-specific updates from being installed under /root.
if [[ "$EUID" -eq 0 ]]; then
    print_error "Do not run this script with sudo."
    print_error "Run it as: bash update_cvd.sh"
    exit 1
fi

# Confirm that this is the supported CVD operating-system release.
if [[ ! -r /etc/os-release ]]; then
    print_error "Cannot identify the operating system."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    print_error "This script supports only the IT 140 Ubuntu 24.04 CVD."
    print_error "Detected: ${PRETTY_NAME:-unknown operating system}"
    exit 1
fi

# The standard Codio user is expected to have passwordless sudo access.
if ! command -v sudo >/dev/null 2>&1; then
    print_error "The sudo command is not available."
    exit 1
fi

if ! sudo -n true >/dev/null 2>&1; then
    print_error "The current user does not have the required passwordless sudo access."
    print_error "Contact Codio or course support before attempting the update again."
    exit 1
fi

# Prevent two copies of the updater from running at the same time.
if command -v flock >/dev/null 2>&1; then
    LOCK_FILE="$HOME/.cache/it140-update.lock"
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    if ! flock --nonblock 9; then
        print_error "Another IT 140 CVD update is already running."
        exit 1
    fi
fi

print_header "IT 140 CODIO VIRTUAL DESKTOP UPDATE"
print_info "Updater version : $SCRIPT_VERSION"
CURRENT_USER="$(id -un)"
print_info "Current user    : $CURRENT_USER"
print_info "Operating system: ${PRETTY_NAME}"
print_info "Log file        : $LOG_FILE"
print_info "Available space : $(df -h --output=avail / | tail -n 1 | xargs)"
print_notice "Keep this terminal window open until the update finishes."
print_notice "The script will not upgrade Ubuntu to a different release."

if pgrep -u "$CURRENT_USER" -x code >/dev/null 2>&1; then
    print_notice "VS Code is open. Close and reopen it after the update."
fi

APT_OPTIONS=(
    -o Acquire::Retries=3
    -o Dpkg::Options::=--force-confdef
    -o Dpkg::Options::=--force-confold
)

COURSE_PACKAGES=(
    ca-certificates
    curl
    gpg
    direnv
    git
    gh
    numlockx
    tree
    xclip
    python3
    python3-pip
    python3-venv
    code
)

REQUIRED_EXTENSIONS=(
    ms-python.python
    charliermarsh.ruff
    hediet.vscode-drawio
    streetsidesoftware.code-spell-checker
    i2p-hub.i2p-pseudo
    cweijan.vscode-office
)

print_header "Step 1: Update Ubuntu Package Information"
sudo apt-get -o Acquire::Retries=3 update
print_success "Ubuntu package information updated."

print_header "Step 2: Upgrade Ubuntu and Course Software"
# List services that need restarting instead of restarting the VNC desktop
# session while the learner is connected.
sudo env \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=l \
    apt-get "${APT_OPTIONS[@]}" full-upgrade -y
print_success "Installed Ubuntu packages upgraded."

print_info "Verifying the required IT 140 system packages..."
sudo env \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=l \
    apt-get "${APT_OPTIONS[@]}" install -y "${COURSE_PACKAGES[@]}"
print_success "Required IT 140 system packages are installed and current."

print_header "Step 3: Update Python Course Tools"
USER_BIN="$(python3 -m site --user-base)/bin"
export PATH="$USER_BIN:$PATH"

# Preserve access to user-installed Python commands in future sessions.
if ! grep -Fqs '$HOME/.local/bin' "$HOME/.profile"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.profile"
fi

python3 -m pip install \
    --user \
    --upgrade \
    --break-system-packages \
    pytest \
    pytest-cov \
    ruff
print_success "pytest, pytest-cov, and Ruff updated."

print_header "Step 4: Update VS Code Extensions"
EXTENSION_FAILURES=0

# Update all installed extensions, including any optional extensions selected
# by the user. The required course extensions are then explicitly verified.
if NODE_NO_WARNINGS=1 code --update-extensions; then
    print_success "Installed VS Code extensions updated."
else
    print_notice "VS Code could not update one or more installed extensions."
    EXTENSION_FAILURES=$((EXTENSION_FAILURES + 1))
fi

for extension in "${REQUIRED_EXTENSIONS[@]}"; do
    print_info "Verifying $extension..."
    if NODE_NO_WARNINGS=1 code --install-extension "$extension" --force; then
        print_success "$extension is installed and current."
    else
        print_notice "Could not update required extension: $extension"
        EXTENSION_FAILURES=$((EXTENSION_FAILURES + 1))
    fi
done

print_header "Step 5: Refresh VS Code Desktop Launchers"
SYSTEM_CODE_LAUNCHER="/usr/share/applications/code.desktop"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/Desktop}"
DESKTOP_CODE_LAUNCHER="$DESKTOP_DIR/visual-studio-code.desktop"

if [[ -f "$SYSTEM_CODE_LAUNCHER" ]]; then
    mkdir -p "$DESKTOP_DIR"
    install -m 0755 "$SYSTEM_CODE_LAUNCHER" "$DESKTOP_CODE_LAUNCHER"

    if command -v gio >/dev/null 2>&1; then
        launcher_checksum="$(sha256sum "$DESKTOP_CODE_LAUNCHER" | awk '{print $1}')"
        gio set \
            --type=string \
            "$DESKTOP_CODE_LAUNCHER" \
            metadata::xfce-exe-checksum \
            "$launcher_checksum" \
            2>/dev/null || print_notice "Could not refresh the desktop launcher's trusted status."
    fi

    PANEL_CONFIG_DIR="$HOME/.config/xfce4/panel"
    VSCODE_PLUGIN_MARKER="$PANEL_CONFIG_DIR/it140-vscode-plugin-id"

    if [[ -s "$VSCODE_PLUGIN_MARKER" ]]; then
        VSCODE_PLUGIN_ID="$(<"$VSCODE_PLUGIN_MARKER")"

        if [[ "$VSCODE_PLUGIN_ID" =~ ^[0-9]+$ ]]; then
            PANEL_CODE_LAUNCHER_DIR="$PANEL_CONFIG_DIR/launcher-$VSCODE_PLUGIN_ID"
            PANEL_CODE_LAUNCHER="$PANEL_CODE_LAUNCHER_DIR/it140-vscode.desktop"
            mkdir -p "$PANEL_CODE_LAUNCHER_DIR"
            install -m 0644 "$SYSTEM_CODE_LAUNCHER" "$PANEL_CODE_LAUNCHER"
        else
            print_notice "The saved VS Code panel-launcher ID is invalid; the panel launcher was not refreshed."
        fi
    else
        print_notice "No managed VS Code panel launcher was found; the desktop launcher was refreshed."
    fi

    if command -v xfdesktop >/dev/null 2>&1; then
        xfdesktop --reload 2>/dev/null || true
    fi

    print_success "VS Code launcher files refreshed."
else
    print_notice "The system VS Code launcher was not found; launcher files were not refreshed."
fi

print_header "Step 6: Clean and Verify the CVD"
sudo env \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=l \
    apt-get "${APT_OPTIONS[@]}" autoremove -y

sudo apt-get autoclean -y
sudo apt-get clean
sudo apt-get check
print_success "Package cleanup and dependency checks completed."

print_header "UPDATE SUMMARY"
printf 'Ubuntu       : %s\n' "${PRETTY_NAME}"
printf 'Python       : %s\n' "$(python3 --version 2>&1)"
printf 'Git          : %s\n' "$(git --version)"
printf 'GitHub CLI   : %s\n' "$(gh --version | head -n 1)"
printf 'VS Code      : %s\n' "$(code --version | head -n 1)"
printf 'pytest       : %s\n' "$(pytest --version | head -n 1)"
printf 'Ruff         : %s\n' "$(ruff --version)"
printf 'Log file     : %s\n' "$LOG_FILE"

if [[ -f /var/run/reboot-required ]]; then
    print_notice "A VM restart is required to finish applying system updates."
    print_notice "Save your work, close applications, and use Codio's RESTART VM control."
else
    print_notice "A VM restart is not currently required by Ubuntu."
    print_notice "Close and reopen VS Code before continuing coursework."
fi

if (( EXTENSION_FAILURES > 0 )); then
    print_notice "$EXTENSION_FAILURES VS Code extension update operation(s) reported a problem."
    print_notice "Review the log and retry the script before requesting support."
    exit 1
fi

trap - ERR
print_success "The IT 140 Codio Virtual Desktop update completed successfully."
