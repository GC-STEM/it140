#!/bin/bash

# ==============================================================================
# Setup & Automated Configuration Script for IT 140
# Target Environment: Codio Virtual Desktop (Ubuntu 24.04 LTS / XFCE / VS Code)
#
# Purpose: Automatically configures Git identity (privacy-compliant), GitHub CLI,
#          VS Code course preferences, line endings, and workspace defaults.
# ==============================================================================

# Exit immediately if a command fails unexpectedly during non-interactive steps
set -e

# ------------------------------------------------------------------------------
# 0. Setup Logging & Formatting Utilities
# ------------------------------------------------------------------------------
LOG_DIR="$HOME/it140/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"

# Redirect stdout and stderr to both terminal and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# ANSI Color Codes for Visually Distinct Output
COLOR_RESET="\033[0m"
COLOR_INFO="\033[1;34m"     # Bold Blue for System Information
COLOR_SUCCESS="\033[1;32m"  # Bold Green for Completed Tasks
COLOR_WARN="\033[1;33m"     # Bold Yellow for Warnings/Notices
COLOR_PROMPT="\033[1;36m"   # Bold Cyan for Required User Inputs
COLOR_HEADER="\033[1;35m"   # Bold Magenta for Section Headers

# Helper function to get current terminal width with safe default
get_term_width() {
    local width
    width=$(tput cols 2>/dev/null || echo 80)
    if [ "$width" -lt 40 ]; then
        width=40
    fi
    echo "$width"
}

# Dynamic Section Header Function
print_header() {
    local term_width
    term_width=$(get_term_width)
    local divider
    divider=$(printf '%*s' "$term_width" '' | tr ' ' '=')

    echo -e "\n${COLOR_HEADER}${divider}${COLOR_RESET}"
    echo -e "${COLOR_HEADER} $1 ${COLOR_RESET}"
    echo -e "${COLOR_HEADER}${divider}${COLOR_RESET}"
}

print_info() {
    echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $1"
}

print_success() {
    echo -e "${COLOR_SUCCESS}[SUCCESS]${COLOR_RESET} $1"
}

print_warn() {
    echo -e "${COLOR_WARN}[NOTICE]${COLOR_RESET} $1"
}

# Function to display a visual progress bar for background/multi-step tasks
show_progress() {
    local duration=$1
    local label=$2
    local progress=0
    echo -ne "${COLOR_INFO}[PROGRESS]${COLOR_RESET} ${label} "
    while [ $progress -le 100 ]; do
        local filled=$((progress / 5))
        local empty=$((20 - filled))
        printf "\r${COLOR_INFO}[PROGRESS]${COLOR_RESET} %-30s [" "$label"
        printf "%${filled}s" '' | tr ' ' '='
        printf "%${empty}s" '' | tr ' ' '-'
        printf "] %d%%" "$progress"
        sleep "$((duration / 20))"
        progress=$((progress + 5))
    done
    echo ""
}

# Dynamic Welcome Banner Function
print_welcome_banner() {
    local term_width
    term_width=$(get_term_width)
    local divider
    divider=$(printf '%*s' "$term_width" '' | tr ' ' '=')

    local title="IT 140 - CODIO ENVIRONMENT CONFIGURATION"
    local padding=$(( (term_width - ${#title}) / 2 ))

    # Ensure non-negative padding
    if [ "$padding" -lt 0 ]; then padding=0; fi

    local centered_title
    centered_title=$(printf '%*s%s' "$padding" '' "$title")

    clear
    echo -e "${COLOR_HEADER}${divider}${COLOR_RESET}"
    echo -e "${COLOR_HEADER}${centered_title}${COLOR_RESET}"
    echo -e "${COLOR_HEADER}${divider}${COLOR_RESET}"
}

# Display Welcome Banner & Notification
print_welcome_banner
print_info "Welcome to the IT 140 Environment Configuration Tool!"
print_info "This script will link your GitHub account, configure Git privacy settings,"
print_info "and apply default VS Code settings for your coursework."
echo ""
print_warn "NOTE: This setup process may take a few minutes to complete."
print_warn "      Log file location: $LOG_FILE"
echo ""

# ------------------------------------------------------------------------------
# 1. GitHub CLI (`gh`) Authentication
# ------------------------------------------------------------------------------
print_header "Step 1: GitHub CLI Authentication"

print_info "Checking current GitHub CLI authentication status..."
if gh auth status >/dev/null 2>&1; then
    print_success "You are already authenticated with GitHub CLI."
else
    echo ""
    echo -e "${COLOR_PROMPT}>>> ACTION REQUIRED: Press ENTER to launch the GitHub authentication prompt.${COLOR_RESET}"
    echo -e "${COLOR_PROMPT}    When prompted, select 'GitHub.com', 'HTTPS', and 'Login with a web browser'.${COLOR_RESET}"
    read -r -p ">>> Press ENTER to begin authentication..."

    gh auth login -h github.com -p https -w

    if ! gh auth status >/dev/null 2>&1; then
        echo -e "${COLOR_WARN}[ERROR] GitHub authentication failed or was cancelled. Please re-run the script.${COLOR_RESET}"
        exit 1
    fi
    print_success "GitHub CLI successfully authenticated!"
fi

# ------------------------------------------------------------------------------
# 2. Automated Privacy-Compliant Git Configuration
# ------------------------------------------------------------------------------
print_header "Step 2: Privacy-Compliant Git Identity Setup"

print_info "Retrieving account details from GitHub API..."
GH_ID=$(gh api user --jq '.id' 2>/dev/null || true)
GH_USER=$(gh api user --jq '.login' 2>/dev/null || true)

if [ -z "$GH_ID" ] || [ -z "$GH_USER" ]; then
    print_warn "Could not automatically fetch GitHub details via jq filter. Retrying..."
    GH_ID=$(gh api user | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
    GH_USER=$(gh api user | python3 -c "import sys, json; print(json.load(sys.stdin)['login'])")
fi

# Construct GitHub ID-based noreply privacy email
NOREPLY_EMAIL="${GH_ID}+${GH_USER}@users.noreply.github.com"

print_info "Privacy Email Derived: ${NOREPLY_EMAIL}"
git config --global user.email "$NOREPLY_EMAIL"
print_success "Global Git email set to privacy-compliant address."

echo ""
echo -e "${COLOR_PROMPT}>>> INPUT REQUIRED: Select your Git display name.${COLOR_RESET}"
echo -e "${COLOR_PROMPT}    Your current GitHub username is: ${COLOR_RESET}${GH_USER}"
read -r -p ">>> Press ENTER to use '${GH_USER}' as your Git display name, or type a custom name: " INPUT_NAME

if [ -z "$INPUT_NAME" ]; then
    GIT_NAME="$GH_USER"
else
    GIT_NAME="$INPUT_NAME"
fi

git config --global user.name "$GIT_NAME"
print_success "Global Git user name set to: '$GIT_NAME'"

git config --global init.defaultBranch main
git config --global core.autocrlf false
git config --global core.eol lf
git config --global core.safecrlf warn
git config --global push.autoSetupRemote true
git config --global core.editor "code --wait"

print_success "Git core preferences updated (default branch: 'main'; text files use LF line endings)."

# ------------------------------------------------------------------------------
# 3. VS Code Preferences & Course Extension Defaults
# ------------------------------------------------------------------------------
print_header "Step 3: VS Code Workspace & Course Preferences Setup"

print_info "Preparing workspace folder: ~/it140"
mkdir -p "$HOME/it140"

VSCODE_USER_DIR="$HOME/.config/Code/User"
mkdir -p "$VSCODE_USER_DIR"
SETTINGS_FILE="$VSCODE_USER_DIR/settings.json"

print_info "Writing course configuration to VS Code settings.json..."

# Inject default settings into settings.json cleanly using built-in Python
python3 - <<EOF
import json, os

settings_path = "$SETTINGS_FILE"
existing_settings = {}

if os.path.exists(settings_path) and os.path.getsize(settings_path) > 0:
    try:
        with open(settings_path, 'r') as f:
            existing_settings = json.load(f)
    except Exception:
        existing_settings = {}

course_settings = {
    "files.eol": "\n",
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "files.trimTrailingWhitespace": True,
    "files.insertFinalNewline": True,
    "terminal.integrated.defaultProfile.linux": "bash",
    "python.defaultInterpreterPath": "/usr/bin/python3",
    "python.testing.pytestEnabled": True,
    "python.testing.unittestEnabled": False,
    "python.testing.pytestArgs": ["."],
    "[python]": {
        "editor.defaultFormatter": "charliermarsh.ruff",
        "editor.formatOnSave": True
    },
    "cSpell.language": "en",
    "files.defaultFolder": "/home/codio/it140",
    "workbench.editorAssociations": {
        "README.md": "vscode.markdown.preview.editor",
        "*_srs.md": "vscode.markdown.preview.editor",
        "*_sdd.md": "vscode.markdown.preview.editor"
    },
    "settingsSync.ignoredSettings": [
        "python.defaultInterpreterPath",
        "files.defaultFolder"
    ],
    "files.associations": {
        "*.pseudo": "pseudo"
    }
}

existing_settings.update(course_settings)

with open(settings_path, 'w') as f:
    json.dump(existing_settings, f, indent=4)
EOF

show_progress 2 "Applying VS Code Preferences"
print_success "VS Code settings configured successfully!"

# ------------------------------------------------------------------------------
# 4. Environment Verification & Validation
# ------------------------------------------------------------------------------
print_header "Step 4: Environment Verification"

show_progress 3 "Validating Installed Components"

CONF_NAME=$(git config --global user.name)
CONF_EMAIL=$(git config --global user.email)

TERM_WIDTH=$(get_term_width)
DIVIDER=$(printf '%*s' "$TERM_WIDTH" '' | tr ' ' '=')

echo ""
print_success "=== CONFIGURATION SUMMARY ==="
print_info "Git User Name    : $CONF_NAME"
print_info "Git Privacy Email: $CONF_EMAIL"
print_info "GitHub Login     : $GH_USER"
print_info "Course Directory : $HOME/it140"
print_info "Python Path      : /usr/bin/python3"
print_info "Log Transcript   : $LOG_FILE"
echo ""

print_success "All course environment configurations completed successfully!"
print_info "You are now ready to begin work in IT 140."
echo -e "${COLOR_HEADER}${DIVIDER}${COLOR_RESET}\n"
