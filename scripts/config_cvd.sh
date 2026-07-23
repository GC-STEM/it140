#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop automated configuration
#
# Audience: IT 140 students
# Purpose: Apply student-specific Git and Visual Studio Code settings after
#          the student completes GitHub CLI authorization in the README.
#
# This script is intentionally non-interactive. It does not open websites,
# ask questions, pause for input, or request account credentials. It is safe
# to run again because each configuration command replaces or verifies the
# same setting.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="2026.07.23.1"
readonly COURSE_DIR="$HOME/it140"
readonly LOG_DIR="$COURSE_DIR/logs"
readonly LOG_FILE="$LOG_DIR/it140_config_log.txt"
readonly WORKSPACE_FILE="$COURSE_DIR/it140.code-workspace"
readonly COMPLETION_FILE="$COURSE_DIR/.cvd_configuration_complete"
readonly GITHUB_HOST="github.com"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Display normal output and append it to the configuration log.
exec > >(tee -a "$LOG_FILE") 2>&1

handle_error() {
    local status="$1"
    local line_number="$2"

    printf '\nERROR: Configuration stopped at line %s (exit %s).\n' \
        "$line_number" "$status" >&2
    printf 'Review %s for details.\n' "$LOG_FILE" >&2
    exit "$status"
}

trap 'handle_error "$?" "$LINENO"' ERR

print_line() {
    printf '%*s\n' 72 '' | tr ' ' '-'
}

print_section() {
    printf '\n'
    print_line
    printf '%s\n' "$1"
    print_line
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'ERROR: Required command "%s" is not installed.\n' \
            "$command_name" >&2
        printf 'Report this problem to your instructor or course support.\n' >&2
        exit 1
    fi
}

get_desktop_dir() {
    local desktop_dir

    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    printf '%s' "${desktop_dir:-$HOME/Desktop}"
}

verify_github_authorization() {
    print_section "1. Verify GitHub CLI authorization"

    if ! gh auth status --hostname "$GITHUB_HOST" >/dev/null 2>&1; then
        printf '%s\n' \
            "ERROR: GitHub CLI is not authorized for this CVD." \
            "Complete the GitHub CLI authorization steps in README.md," \
            "then run this script again." >&2
        exit 1
    fi

    if ! gh api user >/dev/null 2>&1; then
        printf '%s\n' \
            "ERROR: The saved GitHub authorization could not access your" \
            "account. Repeat the GitHub CLI authorization steps in README.md," \
            "then run this script again." >&2
        exit 1
    fi

    printf 'GitHub CLI is authorized as %s.\n' \
        "$(gh api user --jq '.login')"
}

configure_git() {
    print_section "2. Configure Git"

    local github_login
    local github_id
    local github_profile_name
    local git_author_name
    local git_author_email

    github_login="$(gh api user --jq '.login')"
    github_id="$(gh api user --jq '.id')"
    github_profile_name="$(gh api user --jq '.name // ""')"

    # Git records an author name in every commit. Use the professional profile
    # name when one is available; otherwise, use the GitHub username.
    if [[ -n "${github_profile_name//[[:space:]]/}" ]]; then
        git_author_name="$github_profile_name"
    else
        git_author_name="$github_login"
    fi

    # GitHub's current private commit-email format combines the permanent
    # numeric account ID with the current GitHub username.
    git_author_email="${github_id}+${github_login}@users.noreply.github.com"

    git config --global user.name "$git_author_name"
    git config --global user.email "$git_author_email"
    git config --global init.defaultBranch main
    git config --global core.longpaths true
    git config --global core.editor "code --wait"
    git config --global push.autoSetupRemote true

    # Record HTTPS as the preferred Git protocol and configure Git to obtain
    # GitHub credentials from the already-authorized GitHub CLI.
    gh config set git_protocol https --host "$GITHUB_HOST"
    gh auth setup-git --hostname "$GITHUB_HOST"

    printf 'Git author name: %s\n' "$(git config --global user.name)"
    printf 'Git author email: %s\n' "$(git config --global user.email)"
    printf 'GitHub protocol: %s\n' \
        "$(gh config get git_protocol --host "$GITHUB_HOST")"
}

create_vscode_workspace() {
    cat > "$WORKSPACE_FILE" <<'EOF_WORKSPACE'
{
    "folders": [
        {
            "name": "IT 140",
            "path": "."
        }
    ],
    "settings": {
        "workbench.colorTheme": "Solarized Dark"
    }
}
EOF_WORKSPACE
}

configure_vscode_launcher() {
    local desktop_dir
    local launcher
    local launcher_checksum

    desktop_dir="$(get_desktop_dir)"
    launcher="$desktop_dir/visual-studio-code.desktop"
    mkdir -p "$desktop_dir"

    # This desktop icon opens the IT 140 workspace instead of an empty window.
    cat > "$launcher" <<EOF_LAUNCHER
[Desktop Entry]
Version=1.0
Type=Application
Name=Visual Studio Code
Comment=Open the IT 140 course workspace
Exec=code --new-window "$WORKSPACE_FILE"
Icon=com.visualstudio.code
Terminal=false
StartupNotify=true
Categories=TextEditor;Development;IDE;
EOF_LAUNCHER

    chmod 0755 "$launcher"

    # Mark the launcher as trusted in XFCE when the required desktop services
    # are available. Failure here should not stop the remaining configuration.
    if command -v gio >/dev/null 2>&1; then
        launcher_checksum="$(sha256sum "$launcher" | awk '{print $1}')"
        gio set \
            --type=string \
            "$launcher" \
            metadata::xfce-exe-checksum \
            "$launcher_checksum" \
            2>/dev/null || true
    fi

    if command -v xfdesktop >/dev/null 2>&1; then
        xfdesktop --reload 2>/dev/null || true
    fi
}

verify_vscode_extensions() {
    local -a required_extensions=(
        ms-python.python
        charliermarsh.ruff
        hediet.vscode-drawio
        streetsidesoftware.code-spell-checker
        i2p-hub.i2p-pseudo
        cweijan.vscode-office
    )
    local installed_extensions
    local extension

    installed_extensions="$(code --list-extensions 2>/dev/null || true)"

    for extension in "${required_extensions[@]}"; do
        if grep -Fxiq "$extension" <<< "$installed_extensions"; then
            printf 'VS Code extension already installed: %s\n' "$extension"
        else
            printf 'Installing missing VS Code extension: %s\n' "$extension"
            NODE_NO_WARNINGS=1 code \
                --install-extension "$extension" \
                --force
        fi
    done
}

configure_vscode() {
    print_section "3. Configure Visual Studio Code"

    create_vscode_workspace
    configure_vscode_launcher
    verify_vscode_extensions

    printf 'Workspace created: %s\n' "$WORKSPACE_FILE"
    printf '%s\n' \
        "The Visual Studio Code desktop icon now opens the IT 140 workspace." \
        "The workspace uses the Solarized Dark theme."
}

run_final_checks() {
    print_section "4. Verify the course development environment"

    local git_version
    local gh_version
    local python_version
    local code_version

    git_version="$(git --version)"
    gh_version="$(gh --version | head -n 1)"
    python_version="$(python3 --version 2>&1)"
    code_version="$(code --version | head -n 1)"

    printf 'GitHub account: %s\n' "$(gh api user --jq '.login')"
    printf 'Git author name: %s\n' "$(git config --global user.name)"
    printf 'Git author email: %s\n' "$(git config --global user.email)"
    printf 'Git: %s\n' "$git_version"
    printf 'GitHub CLI: %s\n' "$gh_version"
    printf 'Python: %s\n' "$python_version"
    printf 'VS Code: %s\n' "$code_version"
    printf 'Course folder: %s\n' "$COURSE_DIR"
    printf 'Workspace: %s\n' "$WORKSPACE_FILE"

    {
        printf 'Script version: %s\n' "$SCRIPT_VERSION"
        printf 'Completed: %s\n' "$(date --iso-8601=seconds)"
        printf 'GitHub account: %s\n' "$(gh api user --jq '.login')"
        printf 'Git author name: %s\n' "$(git config --global user.name)"
        printf 'Git author email: %s\n' "$(git config --global user.email)"
        printf 'Workspace: %s\n' "$WORKSPACE_FILE"
    } > "$COMPLETION_FILE"
    chmod 600 "$COMPLETION_FILE"

    trap - ERR
    printf '\nAutomated CVD configuration completed successfully.\n'
    printf 'Configuration log: %s\n' "$LOG_FILE"
}

main() {
    printf 'IT 140 Codio Virtual Desktop Automated Configuration\n'
    printf 'Script version: %s\n' "$SCRIPT_VERSION"
    printf '%s\n' \
        "This script applies settings that do not require browser interaction." \
        "It does not ask questions or request account credentials."

    if [[ ! -d "$COURSE_DIR" ]]; then
        printf 'ERROR: The course folder does not exist: %s\n' \
            "$COURSE_DIR" >&2
        exit 1
    fi

    for command_name in git gh code python3 sha256sum; do
        require_command "$command_name"
    done

    verify_github_authorization
    configure_git
    configure_vscode
    run_final_checks
}

main "$@"
