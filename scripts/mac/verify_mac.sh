#!/bin/zsh
set -u
set -o pipefail

readonly IT140_SCRIPT_VERSION="0.3.0"
readonly IT140_VERSION_DATE="2026-07-29"
readonly IT140_DEVELOPMENT_STATUS="Alpha Testing"
readonly IT140_ACTION_ID="verify"
readonly IT140_USAGE="Usage: verify_mac.sh [--help] [--version] [--noninteractive] [--profile PROFILE_ID] [--support-bundle] [--yes] [--skip-network]"
IT140_NONINTERACTIVE=false
IT140_SUPPORT_BUNDLE=false
IT140_ASSUME_YES=false
IT140_SKIP_NETWORK=false
PASS_COUNT=0
WARNING_COUNT=0
FAIL_COUNT=0
NOT_APPLICABLE_COUNT=0
SUPPORT_BUNDLE_PATH=""

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
source "$SCRIPT_DIR/_mac_common.sh"

show_help() {
    cat <<HELP
$IT140_USAGE

Verify the IT 140 course IDE without changing installed software or user settings.
The log and an explicitly requested support bundle are the only files written.

Options:
  --help                 Show this help.
  --version              Show artifact metadata.
  --noninteractive       Suppress optional prompts.
  --profile PROFILE_ID   Override automatic Apple-silicon/Intel profile selection.
  --support-bundle       Create a sanitized diagnostics ZIP in the course log folder.
  --yes                  Accept support-bundle confirmation when needed.
  --skip-network         Skip external connectivity checks.
HELP
}

record_pass() { printf '[PASS] %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
record_warning() { printf '[WARNING] %s\n' "$1"; WARNING_COUNT=$((WARNING_COUNT + 1)); }
record_fail() { printf '[FAIL] %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
record_na() { printf '[N/A] %s\n' "$1"; NOT_APPLICABLE_COUNT=$((NOT_APPLICABLE_COUNT + 1)); }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help) show_help; exit 0 ;;
        --version) it140_print_version; exit 0 ;;
        --noninteractive) IT140_NONINTERACTIVE=true ;;
        --profile)
            [ "$#" -ge 2 ] || { printf '[ERROR] --profile requires a value.\n' >&2; exit 64; }
            IT140_REQUESTED_PROFILE="$2"; shift ;;
        --support-bundle) IT140_SUPPORT_BUNDLE=true ;;
        --yes) IT140_ASSUME_YES=true ;;
        --skip-network) IT140_SKIP_NETWORK=true ;;
        *) printf '[ERROR] Unknown option: %s\n%s\n' "$1" "$IT140_USAGE" >&2; exit 64 ;;
    esac
    shift
done

it140_check_platform_and_user
PLATFORM_STATUS=$?
if [ "$PLATFORM_STATUS" -ne 0 ]; then exit "$PLATFORM_STATUS"; fi
it140_initialize_log

it140_header "IT 140 macOS VERIFICATION"
it140_print_version | sed 's/^/[INFO] /'
it140_info "Deployment       : $IT140_REQUESTED_PROFILE"
it140_info "Current user     : $(id -un)"
it140_info "Course root      : $IT140_COURSE_ROOT"
it140_info "Log file         : $IT140_LOG_FILE"
it140_notice "Verification is read-only except for this log and any explicitly requested support bundle."

it140_header "1. Platform and Controlled Manifest"
record_pass "Operating system is macOS $(/usr/bin/sw_vers -productVersion)."
case "$(it140_detect_architecture)" in
    arm64) record_pass "Apple silicon architecture detected." ;;
    x86_64) record_pass "Intel x86_64 architecture detected." ;;
    *) record_fail "Unsupported architecture: $(it140_detect_architecture)." ;;
esac
if MANIFEST_RELEASE="$(it140_validate_manifest_basic 2>&1)"; then
    record_pass "Manifest basic validation passed."
else
    record_fail "Manifest basic validation failed: $MANIFEST_RELEASE"
fi
if it140_initialize_homebrew; then
    if FULL_RELEASE="$(it140_validate_manifest_full 2>&1)"; then
        MANIFEST_RELEASE="$FULL_RELEASE"
        record_pass "Manifest schema 2.0 and strict SemVer validation passed ($MANIFEST_RELEASE)."
    else
        record_fail "Full manifest validation failed: $FULL_RELEASE"
    fi
else
    record_fail "Homebrew is unavailable. Run setup_mac.sh."
fi

it140_header "2. Storage, Apple Tools, and Connectivity"
if it140_check_free_space >/dev/null 2>&1; then record_pass "Manifest-required free space is available."; else record_fail "Manifest-required free space is unavailable."; fi
if /usr/bin/xcode-select -p >/dev/null 2>&1; then record_pass "Apple Command Line Tools are installed."; else record_fail "Apple Command Line Tools are missing."; fi
if [ "$IT140_SKIP_NETWORK" = true ]; then
    record_na "External network verification skipped by request."
elif /usr/bin/curl --fail --silent --show-error --head --connect-timeout 15 --max-time 30 https://github.com/ >/dev/null 2>&1; then
    record_pass "GitHub connectivity succeeded."
else
    record_warning "GitHub connectivity could not be confirmed; a temporary network or service issue may exist."
fi

it140_header "3. Required System Software"
if it140_initialize_homebrew; then
    record_pass "$(brew --version | head -n 1) is available."
    FORMULA_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-verify-formulae.XXXXXX")"
    CASK_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-verify-casks.XXXXXX")"
    if it140_manifest_query system_formulae > "$FORMULA_FILE" 2>/dev/null; then
        while IFS= read -r formula; do
            [ -n "$formula" ] || continue
            if brew list --formula "$formula" >/dev/null 2>&1; then record_pass "Homebrew formula installed: $formula"; else record_fail "Required Homebrew formula missing: $formula"; fi
        done < "$FORMULA_FILE"
    fi
    if it140_manifest_query system_casks > "$CASK_FILE" 2>/dev/null; then
        while IFS= read -r cask; do
            [ -n "$cask" ] || continue
            if brew list --cask "$cask" >/dev/null 2>&1; then record_pass "Homebrew cask installed: $cask"; else record_fail "Required Homebrew cask missing: $cask"; fi
        done < "$CASK_FILE"
    fi
    rm -f "$FORMULA_FILE" "$CASK_FILE"
fi

for command_name in git gh; do
    if command -v "$command_name" >/dev/null 2>&1; then
        record_pass "$command_name is available: $($command_name --version | head -n 1)"
    else
        record_fail "$command_name is unavailable."
    fi
done
if PYTHON_PATH="$(it140_resolve_python 2>/dev/null)"; then
    if "$PYTHON_PATH" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 12) else 1)' >/dev/null 2>&1; then
        record_pass "Python runtime is $($PYTHON_PATH --version 2>&1)."
    else
        record_fail "Course runtime is not Python 3.12."
    fi
else
    record_fail "Python 3.12 is unavailable."
fi
if CODE_PATH="$(it140_resolve_code_cli 2>/dev/null)"; then
    record_pass "Visual Studio Code is available: $($CODE_PATH --version | head -n 1)"
else
    record_fail "Visual Studio Code command-line interface is unavailable."
fi

it140_header "4. Course Python and VS Code Components"
VENV_PATH="$IT140_COURSE_ROOT/.venv"
if [ -x "$VENV_PATH/bin/python" ]; then
    record_pass "Course Python virtual environment exists."
    PACKAGE_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-verify-python.XXXXXX")"
    if it140_manifest_query venv_packages > "$PACKAGE_FILE" 2>/dev/null; then
        while IFS= read -r package; do
            [ -n "$package" ] || continue
            if "$VENV_PATH/bin/python" -m pip show "$package" >/dev/null 2>&1; then record_pass "Python package installed: $package"; else record_fail "Required Python package missing: $package"; fi
        done < "$PACKAGE_FILE"
    fi
    rm -f "$PACKAGE_FILE"
else
    record_fail "Course Python virtual environment is missing. Run config_mac.sh."
fi

if [ -n "${CODE_PATH:-}" ]; then
    EXTENSIONS="$($CODE_PATH --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    EXTENSION_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-verify-extensions.XXXXXX")"
    if it140_manifest_query extensions > "$EXTENSION_FILE" 2>/dev/null; then
        while IFS= read -r extension; do
            [ -n "$extension" ] || continue
            if printf '%s\n' "$EXTENSIONS" | grep -Fxqi "$extension"; then record_pass "VS Code extension installed: $extension"; else record_fail "Required VS Code extension missing: $extension"; fi
        done < "$EXTENSION_FILE"
    fi
    rm -f "$EXTENSION_FILE"
fi

it140_header "5. User Authentication and Managed Configuration"
if gh auth status --hostname github.com >/dev/null 2>&1; then record_pass "GitHub CLI authentication is valid."; else record_fail "GitHub CLI authentication is incomplete. Run config_mac.sh."; fi
if GIT_NAME="$(git config --global --get user.name 2>/dev/null)" && [ -n "$GIT_NAME" ]; then record_pass "Git user.name is configured."; else record_fail "Git user.name is missing."; fi
if GIT_EMAIL="$(git config --global --get user.email 2>/dev/null)" && printf '%s\n' "$GIT_EMAIL" | grep -Eq '@users\.noreply\.github\.com$'; then
    record_pass "Git user.email uses the approved GitHub private noreply format."
else
    record_fail "Git user.email is missing or does not use the approved private noreply format."
fi
if command -v git >/dev/null 2>&1; then
    while IFS=$'\t' read -r key expected; do
        [ -n "$key" ] || continue
        actual="$(git config --global --get "$key" 2>/dev/null || true)"
        if [ "$actual" = "$expected" ]; then
            record_pass "Managed Git setting is correct: $key"
        else
            record_fail "Managed Git setting $key is '$actual'; expected '$expected'."
        fi
    done <<SETTINGS
$(it140_manifest_query git_settings 2>/dev/null)
SETTINGS
fi
if grep -Fq "$IT140_MANAGED_ENV_START" "$HOME/.zprofile" 2>/dev/null && grep -Fq "$IT140_MANAGED_ENV_END" "$HOME/.zprofile" 2>/dev/null; then
    record_pass "Managed PATH block exists in .zprofile."
else
    record_fail "Managed PATH block is missing from .zprofile."
fi
if grep -Fq "$IT140_MANAGED_ENV_START" "$HOME/.zshrc" 2>/dev/null && grep -Fq "$IT140_MANAGED_ENV_END" "$HOME/.zshrc" 2>/dev/null; then
    record_pass "Managed PATH block exists in .zshrc."
else
    record_fail "Managed PATH block is missing from .zshrc."
fi
case ":$PATH:" in
    *":$VENV_PATH/bin:"*) record_pass "Course virtual-environment commands are available in the current PATH." ;;
    *) record_warning "This Terminal has not loaded the managed course PATH; open a new Terminal after configuration." ;;
esac

VSCODE_USER_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
if [ -f "$VSCODE_USER_SETTINGS" ] && [ -x "$VENV_PATH/bin/python" ]; then
    CONTROLLED_SETTINGS="$(it140_manifest_query vscode_settings 2>/dev/null || printf '{}')"
    if "$VENV_PATH/bin/python" - "$VSCODE_USER_SETTINGS" "$CONTROLLED_SETTINGS" <<'PY'
import json
import pathlib
import sys
current = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
managed = json.loads(sys.argv[2])
def contains(actual, expected):
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(k in actual and contains(actual[k], v) for k, v in expected.items())
    return actual == expected
raise SystemExit(0 if contains(current, managed) else 1)
PY
    then
        record_pass "Manifest-controlled VS Code user settings are present."
    else
        record_fail "VS Code user settings are invalid or missing controlled values."
    fi
else
    record_fail "VS Code user settings are missing."
fi
if [ -f "$IT140_COURSE_ROOT/.vscode/settings.json" ]; then record_pass "Course workspace settings exist."; else record_fail "Course workspace settings are missing."; fi
for lifecycle_script in config_mac.sh setup_mac.sh update_mac.sh verify_mac.sh _mac_common.sh; do
    script_path="$IT140_PLATFORM_SCRIPT_DIR/$lifecycle_script"
    if [ -r "$script_path" ] && /bin/zsh -n "$script_path" >/dev/null 2>&1; then
        record_pass "Lifecycle asset is readable and syntactically valid: $lifecycle_script"
    else
        record_fail "Lifecycle asset is missing or invalid: $lifecycle_script"
    fi
done
if [ -L "$HOME/Desktop/IT 140" ] || [ ! -d "$HOME/Desktop" ]; then record_pass "Course desktop integration is present or not applicable."; else record_warning "The optional IT 140 desktop link is missing."; fi

if [ "$IT140_SUPPORT_BUNDLE" = true ]; then
    it140_header "6. Sanitized Support Bundle"
    BUNDLE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/it140-support.XXXXXX")"
    {
        printf 'Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'macOS: %s\n' "$(/usr/bin/sw_vers -productVersion)"
        printf 'Build: %s\n' "$(/usr/bin/sw_vers -buildVersion)"
        printf 'Architecture: %s\n' "$(it140_detect_architecture)"
        printf 'Profile: %s\n' "$IT140_REQUESTED_PROFILE"
        printf 'Manifest release: %s\n' "${MANIFEST_RELEASE:-unknown}"
        printf 'Shell: %s\n' "${SHELL:-unknown}"
    } > "$BUNDLE_ROOT/system.txt"
    {
        command -v brew >/dev/null 2>&1 && brew --version | head -n 1
        command -v git >/dev/null 2>&1 && git --version
        command -v gh >/dev/null 2>&1 && gh --version | head -n 1
        [ -n "${PYTHON_PATH:-}" ] && "$PYTHON_PATH" --version 2>&1
        [ -n "${CODE_PATH:-}" ] && "$CODE_PATH" --version | head -n 1
    } > "$BUNDLE_ROOT/versions.txt"
    cp "$IT140_LOG_FILE" "$BUNDLE_ROOT/verify.log"
    SUPPORT_BUNDLE_PATH="$IT140_LOG_DIR/it140_mac_support_$(date +%Y%m%d_%H%M%S).zip"
    (cd "$BUNDLE_ROOT" && /usr/bin/zip -q -r "$SUPPORT_BUNDLE_PATH" .)
    rm -rf "$BUNDLE_ROOT"
    record_pass "Sanitized support bundle created: $SUPPORT_BUNDLE_PATH"
fi

it140_header "VERIFICATION SUMMARY"
RESULT="PASS"
EXIT_CODE=0
NEXT_STEP="Course IDE is ready."
if [ "$FAIL_COUNT" -gt 0 ]; then RESULT="FAIL"; EXIT_CODE=1; NEXT_STEP="Run the indicated lifecycle script, then rerun verify_mac.sh."; fi
printf 'Result        : %s\n' "$RESULT"
printf 'Script version: %s\n' "$IT140_SCRIPT_VERSION"
printf 'Manifest      : %s\n' "${MANIFEST_RELEASE:-unknown}"
printf 'Passed        : %s\n' "$PASS_COUNT"
printf 'Warnings      : %s\n' "$WARNING_COUNT"
printf 'Failed        : %s\n' "$FAIL_COUNT"
printf 'Not applicable: %s\n' "$NOT_APPLICABLE_COUNT"
printf 'Elapsed       : %s seconds\n' "$(it140_elapsed)"
printf 'Next step     : %s\n' "$NEXT_STEP"
printf 'Exit code     : %s\n' "$EXIT_CODE"
[ -n "$SUPPORT_BUNDLE_PATH" ] && printf 'Support bundle: %s\n' "$SUPPORT_BUNDLE_PATH"
it140_notice "Verification log: $IT140_LOG_FILE"
exit "$EXIT_CODE"
