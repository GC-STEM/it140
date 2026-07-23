#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop first-use configuration
#
# Audience: IT 140 students
# Purpose: Connect this Codio Virtual Desktop to GitHub and configure the
#          student-specific Git and Visual Studio Code settings used in IT 140.
#
# Run this script from a terminal inside the graphical Codio Virtual Desktop.
# The script is safe to run again if configuration was interrupted.

set -Eeuo pipefail
IFS=$'\n\t'

readonly COURSE_DIR="$HOME/it140"
readonly LOG_DIR="$COURSE_DIR/logs"
readonly LOG_FILE="$LOG_DIR/it140_config_log.txt"
readonly WORKSPACE_FILE="$COURSE_DIR/it140.code-workspace"
readonly COMPLETION_FILE="$COURSE_DIR/.cvd_configuration_complete"
readonly GITHUB_HOST="github.com"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Save normal script output to a log while still displaying it in the terminal.
# Browser authentication output is sent directly to the terminal later so the
# temporary GitHub device code is not written to this file.
exec > >(tee -a "$LOG_FILE") 2>&1

handle_error() {
    local status="$?"

    printf '\nERROR: Configuration stopped at line %s (exit %s).\n' \
        "$LINENO" "$status" >&2
    printf 'Review %s for details.\n' "$LOG_FILE" >&2
    exit "$status"
}

trap handle_error ERR

print_line() {
    printf '%*s\n' 72 '' | tr ' ' '-'
}

print_section() {
    printf '\n'
    print_line
    printf '%s\n' "$1"
    print_line
}

pause_until_ready() {
    printf '\nPress Enter after you complete these steps.'
    read -r
    printf '\n'
}

ask_yes_no() {
    # Usage: ask_yes_no "Question" "y" or "n"
    local question="$1"
    local default_answer="$2"
    local prompt
    local reply

    if [[ "$default_answer" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    while true; do
        printf '%s %s ' "$question" "$prompt"
        read -r reply
        reply="${reply:-$default_answer}"

        case "${reply,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                printf 'Please enter Y for yes or N for no.\n'
                ;;
        esac
    done
}

prompt_with_default() {
    # Print the user's response, or the supplied default when Enter is pressed.
    local prompt_text="$1"
    local default_value="$2"
    local response

    printf '%s [%s]: ' "$prompt_text" "$default_value" >&2
    read -r response
    printf '%s' "${response:-$default_value}"
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

find_chrome() {
    local candidate

    for candidate in google-chrome google-chrome-stable; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done

    return 1
}

get_desktop_dir() {
    local desktop_dir

    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    printf '%s' "${desktop_dir:-$HOME/Desktop}"
}

configure_github_authentication() {
    print_section "1. Connect GitHub CLI to your GitHub account"

    printf '%s\n' \
        "GitHub CLI lets this CVD communicate securely with your GitHub account." \
        "You will complete the sign-in in Google Chrome. Do not enter your" \
        "GitHub password or verification code into this terminal."

    if gh api user >/dev/null 2>&1; then
        GITHUB_LOGIN="$(gh api user --jq '.login')"
        printf '\nGitHub CLI is already signed in as: %s\n' "$GITHUB_LOGIN"

        if ! ask_yes_no "Continue with this GitHub account?" "y"; then
            printf '%s\n' \
                "Configuration stopped so you can change accounts." \
                "Run the following command, then run this script again:" \
                "  gh auth logout --hostname github.com"
            exit 0
        fi
    else
        printf '\nYour browser may open behind this terminal window.\n'

        local -a auth_command=(
            gh auth login
            --hostname "$GITHUB_HOST"
            --git-protocol https
            --web
        )

        # On Linux, clipboard copying requires working graphical clipboard
        # support. Use the flag only when a common clipboard tool is available.
        if command -v xclip >/dev/null 2>&1 \
            || command -v xsel >/dev/null 2>&1 \
            || command -v wl-copy >/dev/null 2>&1; then
            auth_command+=(--clipboard)
            printf '%s\n' \
                "The one-time GitHub code will be copied to the clipboard." \
                "Paste it into the GitHub page when requested."
        else
            printf '%s\n' \
                "Clipboard support was not detected. GitHub CLI will display a" \
                "one-time code. Copy that code before continuing in the browser."
        fi

        # Send the interactive authentication flow directly to the terminal.
        # This prevents the temporary device code from being saved in the log.
        "${auth_command[@]}" </dev/tty >/dev/tty 2>/dev/tty

        if ! gh api user >/dev/null 2>&1; then
            printf 'ERROR: GitHub authentication was not completed.\n' >&2
            exit 1
        fi

        GITHUB_LOGIN="$(gh api user --jq '.login')"
    fi

    # Configure Git to use the secure credentials managed by GitHub CLI.
    gh auth setup-git --hostname "$GITHUB_HOST"

    printf 'GitHub CLI is connected as %s.\n' "$GITHUB_LOGIN"
}

configure_git_identity() {
    print_section "2. Configure the name and email stored in Git commits"

    local github_id
    local github_profile_name
    local suggested_name
    local suggested_email
    local git_author_name
    local git_author_email

    github_id="$(gh api user --jq '.id')"
    github_profile_name="$(gh api user --jq '.name // ""')"
    suggested_name="${github_profile_name:-$GITHUB_LOGIN}"
    suggested_email="${github_id}+${GITHUB_LOGIN}@users.noreply.github.com"

    printf '%s\n' \
        "Git stores an author name and email address in every commit." \
        "These values identify your work. They are not used to sign in." \
        "Use the professional name that you want instructors and employers to" \
        "see. GitHub provides a no-reply email address that protects your" \
        "personal email address."

    printf '\nGitHub account: %s\n' "$GITHUB_LOGIN"
    git_author_name="$(prompt_with_default \
        "Git author name" "$suggested_name")"

    while [[ -z "${git_author_name//[[:space:]]/}" ]]; do
        printf 'The Git author name cannot be empty.\n'
        git_author_name="$(prompt_with_default \
            "Git author name" "$suggested_name")"
    done

    printf '\nThe standard no-reply address derived from your account is:\n'
    printf '  %s\n' "$suggested_email"

    if ask_yes_no "Use this no-reply email address?" "y"; then
        git_author_email="$suggested_email"
    else
        printf '%s\n' \
            "Enter the no-reply address shown in GitHub under" \
            "Settings > Emails. It normally has one of these formats:" \
            "  NUMBER+USERNAME@users.noreply.github.com" \
            "  USERNAME@users.noreply.github.com"

        while true; do
            printf 'GitHub no-reply email address: '
            read -r git_author_email

            if [[ "$git_author_email" =~ \
                ^[^[:space:]@]+@users\.noreply\.github\.com$ ]]; then
                if [[ "$git_author_email" != "$suggested_email" ]]; then
                    printf '%s\n' \
                        "This differs from the standard address derived from" \
                        "your current account. Use it only if you copied it" \
                        "from GitHub Settings > Emails."
                    if ! ask_yes_no "Use the address you entered?" "n"; then
                        continue
                    fi
                fi
                break
            fi

            printf '%s\n' \
                "Enter a GitHub-provided address ending in" \
                "@users.noreply.github.com."
        done
    fi

    git config --global user.name "$git_author_name"
    git config --global user.email "$git_author_email"

    # Reapply course-standard Git defaults. These commands are harmless when
    # the master CVD already contains the same settings.
    git config --global init.defaultBranch main
    git config --global core.longpaths true
    git config --global core.editor "code --wait"
    git config --global push.autoSetupRemote true

    printf '\nGit commit identity configured:\n'
    printf '  Name:  %s\n' "$(git config --global user.name)"
    printf '  Email: %s\n' "$(git config --global user.email)"
}

create_vscode_workspace() {
    # A VS Code workspace records which folder VS Code should open and any
    # course-specific settings that should apply inside that folder.
    cat > "$WORKSPACE_FILE" <<EOF_WORKSPACE
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

    # Replace the user's VS Code desktop launcher, not the system launcher.
    # Opening this launcher will always start with the IT 140 workspace.
    cat > "$launcher" <<EOF_VSCODE_LAUNCHER
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
EOF_VSCODE_LAUNCHER

    chmod 0755 "$launcher"

    # Register the final launcher contents as trusted by Xfce.
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
        if ! grep -Fxiq "$extension" <<< "$installed_extensions"; then
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

    printf '%s\n' \
        "The script created an IT 140 workspace and set its theme to" \
        "Solarized Dark. The VS Code desktop icon will open ~/it140." \
        "VS Code requires you to approve Settings Sync in the application."

    code --new-window "$WORKSPACE_FILE" >/dev/null 2>&1 &

    printf '\nComplete these steps in VS Code:\n'
    printf '%s\n' \
        "  1. Select the Accounts icon near the lower-left corner." \
        "  2. Select Backup and Sync Settings." \
        "  3. Choose Sign in with GitHub." \
        "  4. Complete the sign-in in Chrome using the same GitHub account." \
        "  5. If VS Code asks how to combine settings, select Merge." \
        "  6. Return to this terminal."

    pause_until_ready
    verify_vscode_extensions

    printf 'Visual Studio Code configuration is complete.\n'
}

configure_chrome_optional() {
    print_section "4. Optional Google Chrome sign-in"

    printf '%s\n' \
        "Signing in to Chrome can synchronize browser settings, bookmarks," \
        "and other selected data. You do not need Chrome Sync to use IT 140." \
        "Turn on full synchronization only if this is your private, persistent" \
        "CVD. Avoid synchronizing saved passwords or payment information." \
        "You can sign in to a Google Workspace website without turning on" \
        "full browser synchronization."

    if ! ask_yes_no \
        "Would you like to open Chrome and sign in to a Google account?" "n"; then
        printf 'Chrome sign-in skipped.\n'
        return
    fi

    local chrome_command
    if ! chrome_command="$(find_chrome)"; then
        printf '%s\n' \
            "Google Chrome could not be found." \
            "Report this problem to your instructor or course support."
        return
    fi

    "$chrome_command" --new-window "chrome://settings/people" \
        >/dev/null 2>&1 &

    printf '\nComplete these steps in Chrome:\n'
    printf '%s\n' \
        "  1. Select the profile icon near the upper-right corner." \
        "  2. Select Sign in to Chrome." \
        "  3. Enter your information only in the Chrome window." \
        "  4. Choose which browser data, if any, you want to synchronize." \
        "  5. Return to this terminal."

    pause_until_ready
    printf 'Chrome step complete.\n'
}

configure_onedrive_optional() {
    print_section "5. Optional SNHU OneDrive access"

    printf '%s\n' \
        "Microsoft does not provide its OneDrive desktop sync application for" \
        "Linux. This script can open SNHU OneDrive in Chrome, but it cannot" \
        "make ~/it140 synchronize automatically." \
        "Keep active course work in ~/it140 and use GitHub for version control." \
        "You may use OneDrive in the browser for periodic backup copies."

    if ! ask_yes_no "Would you like to open SNHU OneDrive in Chrome?" "n"; then
        printf 'OneDrive access skipped.\n'
        return
    fi

    local chrome_command
    if ! chrome_command="$(find_chrome)"; then
        printf '%s\n' \
            "Google Chrome could not be found." \
            "Open https://www.office.com in another browser."
        return
    fi

    "$chrome_command" --new-window "https://www.office.com/" \
        >/dev/null 2>&1 &

    printf '\nComplete these steps in Chrome:\n'
    printf '%s\n' \
        "  1. Sign in using your SNHU Microsoft 365 account." \
        "  2. Open OneDrive from the Microsoft 365 app launcher." \
        "  3. Create an IT 140 folder if you want a place for backup copies." \
        "  4. Do not move the active ~/it140 folder out of the CVD." \
        "  5. Return to this terminal."

    pause_until_ready
    printf 'OneDrive step complete.\n'
}

run_final_checks() {
    print_section "6. Verify the course development environment"

    local python_version
    local git_version
    local gh_version
    local code_version

    python_version="$(python3 --version 2>&1)"
    git_version="$(git --version)"
    gh_version="$(gh --version)"
    gh_version="${gh_version%%$'\n'*}"
    code_version="$(code --version)"
    code_version="${code_version%%$'\n'*}"

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
        printf 'Completed: %s\n' "$(date --iso-8601=seconds)"
        printf 'GitHub account: %s\n' "$(gh api user --jq '.login')"
        printf 'Git author name: %s\n' "$(git config --global user.name)"
        printf 'Git author email: %s\n' "$(git config --global user.email)"
        printf 'Workspace: %s\n' "$WORKSPACE_FILE"
    } > "$COMPLETION_FILE"
    chmod 600 "$COMPLETION_FILE"

    trap - ERR
    printf '\nConfiguration completed successfully.\n'
    printf 'You may close this terminal and continue working in VS Code.\n'
    printf 'Configuration log: %s\n' "$LOG_FILE"
}

main() {
    printf 'IT 140 Codio Virtual Desktop Configuration\n'
    printf '%s\n' \
        "This script prepares your personal course environment." \
        "It will not ask for or store your GitHub, Google, or SNHU password."

    if [[ -f "$COMPLETION_FILE" ]]; then
        printf '\nThis CVD was configured previously.\n'
        if ! ask_yes_no "Run the configuration again?" "n"; then
            printf 'No changes were made.\n'
            exit 0
        fi
    fi

    if [[ ! -d "$COURSE_DIR" ]]; then
        printf 'ERROR: The course folder does not exist: %s\n' \
            "$COURSE_DIR" >&2
        exit 1
    fi

    for command_name in git gh code python3 sha256sum; do
        require_command "$command_name"
    done

    configure_github_authentication
    configure_git_identity
    configure_vscode
    configure_chrome_optional
    configure_onedrive_optional
    run_final_checks
}

main "$@"
