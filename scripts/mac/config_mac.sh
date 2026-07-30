#!/bin/zsh
set -euo pipefail

readonly IT140_SCRIPT_VERSION="0.4.0"
readonly IT140_VERSION_DATE="2026-07-30"
readonly IT140_DEVELOPMENT_STATUS="Alpha Testing"
readonly IT140_ACTION_ID="config"
readonly IT140_USAGE="Usage: config_mac.sh [--help] [--version] [--noninteractive] [--profile PROFILE_ID]"
IT140_NONINTERACTIVE=false

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
source "$SCRIPT_DIR/_mac_common.sh"

show_help() {
    cat <<HELP
$IT140_USAGE

Configure the current macOS user for the IT 140 course IDE.
This script does not install or update system-wide software.

Options:
  --help                 Show this help.
  --version              Show artifact metadata.
  --noninteractive       Do not start interactive GitHub authentication.
  --profile PROFILE_ID   Override automatic Apple-silicon/Intel profile selection.
HELP
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help) show_help; exit 0 ;;
        --version) it140_print_version; exit 0 ;;
        --noninteractive) IT140_NONINTERACTIVE=true ;;
        --profile)
            [ "$#" -ge 2 ] || { printf '[ERROR] --profile requires a value.\n' >&2; exit 64; }
            IT140_REQUESTED_PROFILE="$2"; shift ;;
        *) printf '[ERROR] Unknown option: %s\n%s\n' "$1" "$IT140_USAGE" >&2; exit 64 ;;
    esac
    shift
done

replace_managed_environment_block() {
    local file="$1" temp_file="$2"
    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || : > "$file"
    /usr/bin/awk -v start="$IT140_MANAGED_ENV_START" -v finish="$IT140_MANAGED_ENV_END" '
        $0 == start {inside=1; next}
        $0 == finish {inside=0; next}
        !inside {print}
    ' "$file" > "$temp_file"
    cat >> "$temp_file" <<ENV

$IT140_MANAGED_ENV_START
export PATH="\$HOME/it140/.venv/bin:\$HOME/it140/scripts/mac:/opt/homebrew/bin:/usr/local/bin:\$PATH"
$IT140_MANAGED_ENV_END
ENV
    mv "$temp_file" "$file"
}

configure_desktop_shortcuts() {
    local launcher_temp_app launcher_executable icon_source icon_entry existing_bundle_id

    if [ ! -d "$IT140_DESKTOP_DIR" ]; then
        it140_warning "The Desktop directory is unavailable; desktop shortcuts were not created."
        return 0
    fi

    if [ -L "$IT140_COURSE_DESKTOP_LINK" ]; then
        ln -sfn "$IT140_COURSE_ROOT" "$IT140_COURSE_DESKTOP_LINK"
    elif [ ! -e "$IT140_COURSE_DESKTOP_LINK" ]; then
        ln -s "$IT140_COURSE_ROOT" "$IT140_COURSE_DESKTOP_LINK"
    else
        it140_warning "$IT140_COURSE_DESKTOP_LINK already exists and is not a symbolic link; it was preserved."
    fi

    if [ -e "$IT140_VSCODE_DESKTOP_APP" ] || [ -L "$IT140_VSCODE_DESKTOP_APP" ]; then
        if it140_is_managed_vscode_launcher "$IT140_VSCODE_DESKTOP_APP"; then
            rm -rf "$IT140_VSCODE_DESKTOP_APP"
        else
            existing_bundle_id="$(it140_plist_raw "$IT140_VSCODE_DESKTOP_APP/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)"
            it140_warning "$IT140_VSCODE_DESKTOP_APP already exists and is not the managed IT 140 launcher${existing_bundle_id:+ ($existing_bundle_id)}; it was preserved."
            return 0
        fi
    fi

    IT140_TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/it140-vscode-launcher.XXXXXX")"
    launcher_temp_app="$IT140_TEMP_ROOT/Visual Studio Code - IT 140.app"
    launcher_executable="$launcher_temp_app/Contents/MacOS/open-it140-in-code"
    mkdir -p "$launcher_temp_app/Contents/MacOS" "$launcher_temp_app/Contents/Resources"

    cat > "$launcher_executable" <<'LAUNCHER'
#!/bin/zsh
set -u

readonly course_root="${HOME}/it140"
if [ ! -d "$course_root" ]; then
    /usr/bin/osascript \
        -e 'display alert "IT 140 folder not found" message "Run the IT 140 bootstrap and configuration scripts, then try again." as warning'
    exit 1
fi

/usr/bin/open -a "Visual Studio Code" "$course_root"
LAUNCHER
    chmod 0755 "$launcher_executable"

    icon_source="/Applications/Visual Studio Code.app/Contents/Resources/Code.icns"
    icon_entry=""
    if [ -r "$icon_source" ]; then
        cp "$icon_source" "$launcher_temp_app/Contents/Resources/IT140Code.icns"
        icon_entry='    <key>CFBundleIconFile</key>
    <string>IT140Code.icns</string>'
    fi

    cat > "$launcher_temp_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>
    <key>CFBundleDisplayName</key>
    <string>Visual Studio Code - IT 140</string>
    <key>CFBundleExecutable</key>
    <string>open-it140-in-code</string>
    <key>CFBundleIdentifier</key>
    <string>$IT140_VSCODE_DESKTOP_BUNDLE_ID</string>
$icon_entry
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Visual Studio Code - IT 140</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$IT140_SCRIPT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

    /usr/bin/plutil -lint "$launcher_temp_app/Contents/Info.plist" >/dev/null
    mv "$launcher_temp_app" "$IT140_VSCODE_DESKTOP_APP"
    rm -rf "$IT140_TEMP_ROOT"
    IT140_TEMP_ROOT=""
    /usr/bin/touch "$IT140_VSCODE_DESKTOP_APP"

    IT140_CHANGED=true
    it140_success "The IT 140 folder link and VS Code desktop launcher are configured."
}

it140_check_platform_and_user
it140_initialize_log
trap 'status=$?; it140_cleanup_common; exit $status' EXIT INT TERM

it140_header "IT 140 macOS CONFIGURATION"
it140_print_version | sed 's/^/[INFO] /'
it140_info "Deployment       : $IT140_REQUESTED_PROFILE"
it140_info "Current user     : $(id -un)"
it140_info "Course root      : $IT140_COURSE_ROOT"
it140_info "Log file         : $IT140_LOG_FILE"
it140_notice "This script changes only the current user's IT 140 environment."
it140_notice "It does not install or update system-wide software."

it140_initialize_homebrew || { it140_error "Homebrew is unavailable. Run setup_mac.sh first."; exit 7; }
MANIFEST_RELEASE="$(it140_validate_manifest_full)"
it140_check_free_space
it140_acquire_lock
PYTHON_PATH="$(it140_resolve_python)" || { it140_error "Python 3.12 is unavailable. Run setup_mac.sh first."; exit 7; }
CODE_PATH="$(it140_resolve_code_cli)" || { it140_error "Visual Studio Code is unavailable. Run setup_mac.sh first."; exit 7; }
for required_command in git gh; do
    command -v "$required_command" >/dev/null 2>&1 || { it140_error "$required_command is unavailable. Run setup_mac.sh first."; exit 7; }
done
it140_success "Required system components are present."

it140_header "Step 1: Configure the Course Shell Environment"
mkdir -p "$IT140_COURSE_ROOT" "$IT140_COURSE_ROOT/.vscode"
TEMP_ZPROFILE="$(mktemp "${TMPDIR:-/tmp}/it140-zprofile.XXXXXX")"
TEMP_ZSHRC="$(mktemp "${TMPDIR:-/tmp}/it140-zshrc.XXXXXX")"
replace_managed_environment_block "$HOME/.zprofile" "$TEMP_ZPROFILE"
replace_managed_environment_block "$HOME/.zshrc" "$TEMP_ZSHRC"
export PATH="$IT140_COURSE_ROOT/.venv/bin:$IT140_PLATFORM_SCRIPT_DIR:/opt/homebrew/bin:/usr/local/bin:$PATH"
IT140_CHANGED=true
it140_success "The course Python and macOS script directories are first in the user PATH."

it140_header "Step 2: Configure GitHub Authentication and Git Identity"
if gh auth status --hostname github.com >/dev/null 2>&1; then
    it140_success "GitHub CLI is authenticated to github.com."
else
    if [ "$IT140_NONINTERACTIVE" = true ]; then
        it140_error "GitHub authentication is incomplete. Rerun without --noninteractive."
        exit 7
    fi
    it140_notice "A browser will open for GitHub authentication. The one-time code will be copied to the clipboard when supported."
    gh auth login --hostname github.com --git-protocol https --web --clipboard
fi
gh auth setup-git

GITHUB_LOGIN="$(gh api user --jq '.login')"
GITHUB_ID="$(gh api user --jq '.id')"
GITHUB_NAME="$(gh api user --jq '.name // empty')"
if ! git config --global --get user.name >/dev/null 2>&1; then
    git config --global user.name "${GITHUB_NAME:-$GITHUB_LOGIN}"
fi
git config --global user.email "${GITHUB_ID}+${GITHUB_LOGIN}@users.noreply.github.com"
while IFS=$'\t' read -r key value; do
    [ -n "$key" ] || continue
    git config --global "$key" "$value"
done <<SETTINGS
$(it140_manifest_query git_settings)
SETTINGS
IT140_CHANGED=true
it140_success "GitHub authentication and manifest-controlled Git defaults are configured."

it140_header "Step 3: Configure the Course Python Environment"
VENV_PATH="$IT140_COURSE_ROOT/.venv"
if [ ! -x "$VENV_PATH/bin/python" ]; then
    "$PYTHON_PATH" -m venv "$VENV_PATH"
    IT140_CHANGED=true
fi
"$VENV_PATH/bin/python" -m pip install --upgrade pip
PACKAGE_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-python-packages.XXXXXX")"
it140_manifest_query venv_packages > "$PACKAGE_FILE"
while IFS= read -r package; do
    [ -n "$package" ] || continue
    "$VENV_PATH/bin/python" -m pip install --upgrade "$package"
done < "$PACKAGE_FILE"
rm -f "$PACKAGE_FILE"
"$VENV_PATH/bin/python" -c 'import pytest, pytest_cov, ruff; print("Course Python imports succeeded.")'
IT140_CHANGED=true
it140_success "The Python 3.12 virtual environment and course packages are configured."

it140_header "Step 4: Configure Visual Studio Code"
EXTENSION_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-vscode-extensions.XXXXXX")"
it140_manifest_query extensions > "$EXTENSION_FILE"
while IFS= read -r extension; do
    [ -n "$extension" ] || continue
    NODE_NO_WARNINGS=1 "$CODE_PATH" --install-extension "$extension" --force
 done < "$EXTENSION_FILE"
rm -f "$EXTENSION_FILE"

VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
VSCODE_USER_SETTINGS="$VSCODE_USER_DIR/settings.json"
mkdir -p "$VSCODE_USER_DIR"
CONTROLLED_SETTINGS="$(it140_manifest_query vscode_settings)"
"$VENV_PATH/bin/python" - "$VSCODE_USER_SETTINGS" "$CONTROLLED_SETTINGS" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
managed = json.loads(sys.argv[2])
current = {}
if path.exists():
    try:
        current = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        backup = path.with_suffix(path.suffix + ".invalid-backup")
        path.replace(backup)
current.update(managed)
path.write_text(json.dumps(current, indent=4, sort_keys=True) + "\n", encoding="utf-8")
PY

"$VENV_PATH/bin/python" - "$IT140_COURSE_ROOT/.vscode/settings.json" "$VENV_PATH/bin/python" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
settings = {
    "python.defaultInterpreterPath": sys.argv[2],
    "python.terminal.activateEnvironment": True,
    "python.testing.pytestEnabled": True,
    "python.testing.unittestEnabled": False,
}
path.write_text(json.dumps(settings, indent=4, sort_keys=True) + "\n", encoding="utf-8")
PY

IT140_CHANGED=true
it140_success "Required VS Code extensions, settings, and course integration are configured."

it140_header "Step 5: Configure Desktop Shortcuts"
configure_desktop_shortcuts

it140_header "CONFIGURATION SUMMARY"
printf 'macOS         : %s\n' "$(/usr/bin/sw_vers -productVersion)"
printf 'Architecture  : %s\n' "$(it140_detect_architecture)"
printf 'Profile       : %s\n' "$IT140_REQUESTED_PROFILE"
printf 'Manifest      : %s\n' "$MANIFEST_RELEASE"
printf 'Python venv   : %s\n' "$VENV_PATH"
printf 'GitHub account: %s\n' "$GITHUB_LOGIN"
printf 'Elapsed       : %s seconds\n' "$(it140_elapsed)"
printf 'Result        : PASS\n'
it140_success "The IT 140 macOS user configuration completed successfully."
it140_notice "Next step: open a new Terminal and run verify_mac.sh."
it140_closing_notices
