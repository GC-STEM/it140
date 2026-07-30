#!/bin/zsh
set -euo pipefail

readonly IT140_SCRIPT_VERSION="0.3.0"
readonly IT140_VERSION_DATE="2026-07-29"
readonly IT140_DEVELOPMENT_STATUS="Alpha Testing"
readonly IT140_ACTION_ID="setup"
readonly IT140_USAGE="Usage: setup_mac.sh [--help] [--version] [--noninteractive] [--profile PROFILE_ID]"
IT140_NONINTERACTIVE=false

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=_mac_common.sh
source "$SCRIPT_DIR/_mac_common.sh"

show_help() {
    cat <<HELP
$IT140_USAGE

Install or repair the system-level IT 140 course IDE components on a supported Mac.
This script does not install macOS updates or upgrade macOS to another release.

Options:
  --help                 Show this help.
  --version              Show artifact metadata.
  --noninteractive       Do not open installer or authentication dialogs.
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

it140_check_platform_and_user
it140_initialize_log
trap 'status=$?; it140_cleanup_common; exit $status' EXIT INT TERM

it140_header "IT 140 macOS SETUP"
it140_print_version | sed 's/^/[INFO] /'
it140_info "Deployment       : $IT140_REQUESTED_PROFILE"
it140_info "Current user     : $(id -un)"
it140_info "Course root      : $IT140_COURSE_ROOT"
it140_info "Log file         : $IT140_LOG_FILE"
it140_notice "This script installs or repairs required course IDE software."
it140_notice "macOS updates are not installed by this script."
it140_notice "It does not configure personal GitHub, Git, Python, or VS Code settings."
it140_info "Operating system : $(/usr/bin/sw_vers -productName) $(/usr/bin/sw_vers -productVersion)"
it140_info "Build            : $(/usr/bin/sw_vers -buildVersion)"
it140_info "Architecture     : $(it140_detect_architecture)"

MANIFEST_RELEASE="$(it140_validate_manifest_basic)"
it140_info "Manifest release : $MANIFEST_RELEASE"
it140_info "Manifest date    : $(it140_plist_raw "$IT140_MANIFEST_PATH" automation_release_date)"
it140_check_free_space
it140_acquire_lock

it140_header "Step 1: Verify Apple Command Line Tools"
if /usr/bin/xcode-select -p >/dev/null 2>&1; then
    it140_success "Apple Command Line Tools are available."
else
    if [ "$IT140_NONINTERACTIVE" = true ]; then
        it140_error "Apple Command Line Tools are required. Run 'xcode-select --install', finish the Apple installer, and rerun setup_mac.sh."
        exit 7
    fi
    it140_notice "Opening Apple's Command Line Tools installer."
    /usr/bin/xcode-select --install || true
    it140_notice "Complete the Apple installer, then rerun setup_mac.sh."
    exit 7
fi

it140_header "Step 2: Install or Repair Homebrew"
if it140_initialize_homebrew; then
    it140_success "Homebrew is available: $(brew --version | head -n 1)"
else
    if [ "$IT140_NONINTERACTIVE" = true ]; then
        it140_error "Homebrew is missing and cannot be installed in noninteractive mode."
        exit 7
    fi
    it140_info "Installing Homebrew from the official installer."
    HOMEBREW_INSTALL_COMMAND="$(/usr/bin/curl --fail --location --show-error --retry 5 "$IT140_HOMEBREW_INSTALLER")"
    if [ "$IT140_NONINTERACTIVE" = true ]; then
        NONINTERACTIVE=1 /bin/bash -c "$HOMEBREW_INSTALL_COMMAND"
    else
        /bin/bash -c "$HOMEBREW_INSTALL_COMMAND"
    fi
    unset HOMEBREW_INSTALL_COMMAND
    it140_initialize_homebrew || { it140_error "Homebrew installation did not produce a usable brew command."; exit 1; }
    IT140_CHANGED=true
    it140_success "Homebrew installed."
fi

it140_header "Step 3: Install Required Course IDE Software"
FORMULA_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-formulae.XXXXXX")"
CASK_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-casks.XXXXXX")"
it140_manifest_query system_formulae > "$FORMULA_FILE"
it140_manifest_query system_casks > "$CASK_FILE"

brew update
while IFS= read -r formula; do
    [ -n "$formula" ] || continue
    if brew list --formula "$formula" >/dev/null 2>&1; then
        it140_info "Upgrading or repairing Homebrew formula: $formula"
        brew upgrade "$formula" 2>/dev/null || brew reinstall "$formula"
    else
        it140_info "Installing Homebrew formula: $formula"
        brew install "$formula"
    fi
    IT140_CHANGED=true
done < "$FORMULA_FILE"

while IFS= read -r cask; do
    [ -n "$cask" ] || continue
    if brew list --cask "$cask" >/dev/null 2>&1; then
        it140_info "Upgrading Homebrew cask: $cask"
        brew upgrade --cask "$cask" 2>/dev/null || true
    else
        it140_info "Installing Homebrew cask: $cask"
        brew install --cask "$cask"
    fi
    IT140_CHANGED=true
done < "$CASK_FILE"
rm -f "$FORMULA_FILE" "$CASK_FILE"

it140_header "Step 4: Validate the Installed System Layer"
it140_initialize_homebrew
MANIFEST_RELEASE="$(it140_validate_manifest_full)"
PYTHON_PATH="$(it140_resolve_python)"
CODE_PATH="$(it140_resolve_code_cli)"
for required_command in git gh; do
    command -v "$required_command" >/dev/null 2>&1 || { it140_error "$required_command is unavailable after installation."; exit 1; }
done
"$PYTHON_PATH" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 12) else 1)' || {
    it140_error "The installed Python runtime is not Python 3.12."
    exit 1
}
"$CODE_PATH" --version >/dev/null
it140_success "Required system components are installed and the manifest is valid."

it140_header "SETUP SUMMARY"
printf 'macOS         : %s\n' "$(/usr/bin/sw_vers -productVersion)"
printf 'Architecture  : %s\n' "$(it140_detect_architecture)"
printf 'Profile       : %s\n' "$IT140_REQUESTED_PROFILE"
printf 'Manifest      : %s\n' "$MANIFEST_RELEASE"
printf 'Homebrew      : %s\n' "$(brew --version | head -n 1)"
printf 'Python        : %s\n' "$($PYTHON_PATH --version 2>&1)"
printf 'Git           : %s\n' "$(git --version)"
printf 'GitHub CLI    : %s\n' "$(gh --version | head -n 1)"
printf 'VS Code       : %s\n' "$($CODE_PATH --version | head -n 1)"
printf 'Elapsed       : %s seconds\n' "$(it140_elapsed)"
printf 'Result        : PASS\n'
it140_success "The IT 140 macOS system setup completed successfully."
it140_notice "Next step: open a new Terminal and run config_mac.sh."
it140_closing_notices
