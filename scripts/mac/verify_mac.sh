#!/bin/zsh
#
# IT 140 macOS read-only verification script
#
# Traceability: VER-FR-001 through VER-FR-014; VER-DES-001 through VER-DES-014
# Scope: Read-only inspection of the supported macOS system and current-user
#        course layers, with optional creation of a sanitized support bundle.
# Excludes: Installation, repair, update, removal, privilege elevation, settings
#           changes, and collection of student-owned course work.

set -euo pipefail
umask 077

readonly SCRIPT_VERSION="2026.07.27.1"
readonly PLATFORM_ID="macos"
readonly PLATFORM_ABBREVIATION="mac"
readonly DEPLOYMENT_PROFILE_ID="macos_bare_metal"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly PLATFORM_SCRIPT_DIR="${SCRIPT_ROOT}/${PLATFORM_ABBREVIATION}"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly RUN_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="${LOG_DIR}/verify_${PLATFORM_ABBREVIATION}_${RUN_TIMESTAMP}.log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly VSCODE_SETTINGS_FILE="${HOME}/Library/Application Support/Code/User/settings.json"
readonly MANAGED_ENV_START="# >>> IT 140 managed environment >>>"
readonly MANAGED_ENV_END="# <<< IT 140 managed environment <<<"
readonly DESKTOP_SHORTCUT="${HOME}/Desktop/IT 140"

NONINTERACTIVE=false
SUPPORT_BUNDLE_REQUESTED=false
CONFIRM_SUPPORT_BUNDLE=false
SUPPORT_BUNDLE_CANCELED=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
START_EPOCH="$(date +%s)"
PASS_COUNT=0
WARNING_COUNT=0
FAIL_COUNT=0
NOT_APPLICABLE_COUNT=0
TEMP_PATHS=()
INITIAL_STATE_SNAPSHOT=""
MANIFEST_RELEASE="unavailable"

print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

print_info() { printf '[INFO] %s\n' "$1"; }
print_success() { printf '[SUCCESS] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }
print_error() { printf '[ERROR] %s\n' "$1" >&2; }

print_closing_notices() {
    print_notice "A log containing all output displayed while this script ran is available here:"
    print_notice "$LOG_FILE"
    print_notice "After reviewing the summary, type 'exit' and press Enter to close this Terminal."
    print_notice "Open a new Terminal before running another script or command so it loads the latest PATH and environment settings."
}

usage() {
    cat <<'USAGE'
Usage: verify_mac.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile macos_bare_metal]
                     [--support-bundle] [--confirm-support-bundle]

Inspects the local IT 140 macOS system and user environment without installing,
repairing, updating, removing, or rewriting managed items.

--support-bundle requests a sanitized diagnostic archive. Interactive runs show
the inventory and request confirmation. Noninteractive creation also requires
--confirm-support-bundle.

Log directory: ~/it140/logs/
USAGE
}

parse_options() {
    while (( $# > 0 )); do
        case "$1" in
            --help|-h)
                usage
                exit 0
                ;;
            --version)
                printf '%s\n' "$SCRIPT_VERSION"
                exit 0
                ;;
            --noninteractive)
                NONINTERACTIVE=true
                ;;
            --support-bundle)
                SUPPORT_BUNDLE_REQUESTED=true
                ;;
            --confirm-support-bundle)
                CONFIRM_SUPPORT_BUNDLE=true
                ;;
            --deployment-profile)
                shift
                if (( $# == 0 )); then
                    print_error "Missing deployment profile."
                    exit 2
                fi
                REQUESTED_PROFILE="$1"
                ;;
            *)
                print_error "Unsupported option: $1"
                usage >&2
                exit 2
                ;;
        esac
        shift
    done
}

initialize_log() {
    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
}

cleanup() {
    set +e
    local temp_path
    for temp_path in "${TEMP_PATHS[@]}"; do
        [[ -n "$temp_path" ]] && rm -rf "$temp_path"
    done
}

on_error() {
    local exit_code=$?
    trap - ERR
    set +e
    print_error "Verification stopped near line ${LINENO:-unknown} with exit status ${exit_code}."
    print_error "Review the log: ${LOG_FILE}"
    cleanup
    exit 1
}

on_interrupt() {
    trap - INT TERM
    set +e
    print_error "Verification was canceled."
    cleanup
    exit 6
}

record_result() {
    local result_name="$1"
    local check_id="$2"
    local detail="$3"
    local remediation="${4:-}"
    case "$result_name" in
        PASS) PASS_COUNT=$(( PASS_COUNT + 1 )) ;;
        WARNING) WARNING_COUNT=$(( WARNING_COUNT + 1 )) ;;
        FAIL) FAIL_COUNT=$(( FAIL_COUNT + 1 )) ;;
        "NOT APPLICABLE") NOT_APPLICABLE_COUNT=$(( NOT_APPLICABLE_COUNT + 1 )) ;;
        *) print_error "Internal result status is invalid: $result_name"; exit 1 ;;
    esac
    printf '[%s] [%s] %s\n' "$result_name" "$check_id" "$detail"
    if [[ -n "$remediation" && "$result_name" != "PASS" ]]; then
        printf '       Remediation: %s\n' "$remediation"
    fi
}

manifest_raw() {
    /usr/bin/plutil -extract "$1" raw -o - "$MANIFEST_PATH"
}

manifest_package() {
    manifest_raw "platforms.macos.course_ide_bindings.${1}.package_identifier"
}

initialize_homebrew_environment() {
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]]; then
            eval "$("$candidate" shellenv)"
            command -v brew >/dev/null 2>&1
            return
        fi
    done
    return 1
}

resolve_python() {
    if command -v python3.12 >/dev/null 2>&1; then
        command -v python3.12
        return
    fi
    if initialize_homebrew_environment; then
        local prefix
        prefix="$(brew --prefix python@3.12 2>/dev/null || true)"
        if [[ -n "$prefix" && -x "$prefix/bin/python3.12" ]]; then
            printf '%s/bin/python3.12\n' "$prefix"
            return
        fi
    fi
    return 1
}

resolve_code_cli() {
    if command -v code >/dev/null 2>&1; then
        command -v code
        return
    fi
    local candidate="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    [[ -x "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

validate_manifest() {
    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || return 1
    /usr/bin/plutil -lint "$MANIFEST_PATH" >/dev/null
    /usr/bin/plutil -lint "$SCHEMA_PATH" >/dev/null

    local python_path
    python_path="$(resolve_python 2>/dev/null || true)"
    if [[ ! -x "$python_path" ]]; then
        [[ "$(manifest_raw schema_version)" == "1.0" ]] || return 1
        [[ "$(manifest_raw policy.allow_os_release_upgrade)" == "false" ]] || return 1
        [[ "$(manifest_raw platforms.macos.enabled)" == "true" ]] || return 1
        [[ "$(manifest_raw deployment_profiles.${REQUESTED_PROFILE}.enabled)" == "true" ]] || return 1
        [[ "$(manifest_raw deployment_profiles.${REQUESTED_PROFILE}.platform_id)" == "$PLATFORM_ID" ]] || return 1
        return 0
    fi

    "$python_path" - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" \
        "$REQUESTED_PROFILE" "$(uname -m)" "$(/usr/bin/sw_vers -productVersion)" <<'PY'
import json
import pathlib
import sys

manifest_path, schema_path, platform_id, profile_id, architecture, version = sys.argv[1:]

class DuplicateKeyError(ValueError):
    pass

def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate key: {key}")
        result[key] = value
    return result

manifest = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
schema = json.loads(pathlib.Path(schema_path).read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
required = {
    "schema_version", "automation_release", "course", "control", "policy",
    "capabilities", "products", "software_sources", "provider_profiles",
    "platforms", "deployment_profiles", "managed_settings", "managed_assets",
    "obsolete_components", "logging",
}
if required - manifest.keys():
    raise SystemExit("manifest is missing required root fields")
if manifest["schema_version"] != "1.0":
    raise SystemExit("unsupported manifest schema version")
if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
    raise SystemExit("unapproved JSON Schema dialect")
if manifest["policy"].get("allow_os_release_upgrade") is not False:
    raise SystemExit("OS release upgrades must remain disabled")
platform = manifest["platforms"].get(platform_id)
profile = manifest["deployment_profiles"].get(profile_id)
if not platform or not platform.get("enabled"):
    raise SystemExit("macOS platform is not enabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("macOS deployment profile is invalid")
if architecture not in platform["os"]["architectures"] or profile.get("architecture") != architecture:
    raise SystemExit("unsupported architecture")
major = version.split(".", 1)[0]
if major not in {item["release_id"] for item in platform["os"]["releases"]}:
    raise SystemExit("unsupported macOS release")
try:
    import jsonschema  # type: ignore
except ImportError:
    pass
else:
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(manifest)
PY
}

check_platform() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        print_error "This script supports macOS only."
        exit 2
    fi
    if (( EUID == 0 )); then
        print_error "Run verify_mac.sh as the standard user, not with sudo."
        exit 2
    fi
    if [[ "$REQUESTED_PROFILE" != "$DEPLOYMENT_PROFILE_ID" ]]; then
        print_error "Unsupported deployment profile: $REQUESTED_PROFILE"
        exit 2
    fi
}

check_supported_release() {
    local product_version major architecture releases_json architectures_json profile_architecture
    product_version="$(/usr/bin/sw_vers -productVersion)"
    major="${product_version%%.*}"
    architecture="$(uname -m)"
    releases_json="$(/usr/bin/plutil -extract platforms.macos.os.releases json -o - "$MANIFEST_PATH")" || exit 5
    architectures_json="$(/usr/bin/plutil -extract platforms.macos.os.architectures json -o - "$MANIFEST_PATH")" || exit 5
    profile_architecture="$(manifest_raw deployment_profiles.${REQUESTED_PROFILE}.architecture)"
    if ! printf '%s\n' "$releases_json" \
        | grep -Eq "\"release_id\"[[:space:]]*:[[:space:]]*\"${major}\""; then
        print_error "macOS ${product_version} is not supported by the current manifest."
        exit 2
    fi
    if ! printf '%s\n' "$architectures_json" | grep -Eq "\"${architecture}\"" \
        || [[ "$profile_architecture" != "$architecture" ]]; then
        print_error "The deployment profile does not support ${architecture}."
        exit 2
    fi
}

snapshot_managed_state() {
    local managed_file
    for managed_file in \
        "$MANIFEST_PATH" \
        "$SCHEMA_PATH" \
        "$HOME/.zprofile" \
        "$HOME/.zshrc" \
        "$HOME/.gitconfig" \
        "$VSCODE_SETTINGS_FILE"; do
        if [[ -f "$managed_file" ]]; then
            /usr/bin/shasum -a 256 "$managed_file" | awk '{print $1}'
        elif [[ -L "$managed_file" ]]; then
            printf 'symlink:%s\n' "$(/usr/bin/readlink "$managed_file")"
        else
            printf 'missing\n'
        fi
    done
    if [[ -L "$DESKTOP_SHORTCUT" ]]; then
        printf 'desktop-symlink:%s\n' "$(/usr/bin/readlink "$DESKTOP_SHORTCUT")"
    elif [[ -e "$DESKTOP_SHORTCUT" ]]; then
        printf 'desktop-existing-item\n'
    else
        printf 'desktop-missing\n'
    fi
}

check_environment() {
    print_header "Environment Checks"
    local version architecture available_kb available minimum timeout
    version="$(/usr/bin/sw_vers -productVersion)"
    architecture="$(uname -m)"
    minimum="$(manifest_raw policy.minimum_free_space_bytes)"
    timeout="$(manifest_raw policy.network_timeout_seconds)"
    available_kb="$(df -Pk "$HOME" | awk 'NR == 2 {print $4}')"
    available=$(( available_kb * 1024 ))

    record_result PASS "verify.platform" \
        "macOS ${version} on ${architecture} matches the approved deployment profile."
    if (( available >= minimum )); then
        record_result PASS "verify.disk_space" "$(( available / 1024 / 1024 / 1024 )) GB is available."
    else
        record_result FAIL "verify.disk_space" "Less than the required free space is available." \
            "Free disk space, then rerun verify_mac.sh."
    fi
    if /usr/bin/curl -fsSIL --connect-timeout 5 --max-time "$timeout" \
        https://github.com/ >/dev/null 2>&1; then
        record_result PASS "verify.network" "The approved source-code hosting service is reachable."
    else
        record_result WARNING "verify.network" \
            "The approved source-code hosting service did not respond in time." \
            "Check the network connection and retry when online access is needed."
    fi
}

check_system_layer() {
    print_header "System-Layer Checks"
    if /usr/bin/xcode-select -p >/dev/null 2>&1 \
        && /usr/bin/xcrun --find clang >/dev/null 2>&1; then
        record_result PASS "verify.xcode_command_line_tools" "Xcode Command Line Tools are available."
    else
        record_result FAIL "verify.xcode_command_line_tools" "Xcode Command Line Tools are unavailable." \
            "Run setup_mac.sh."
    fi

    if initialize_homebrew_environment; then
        record_result PASS "verify.homebrew" "$(brew --version | head -n 1) is available."
    else
        record_result FAIL "verify.homebrew" "Homebrew is unavailable." "Run setup_mac.sh."
        return
    fi

    local role package
    for role in version_control_system source_hosting_client programming_language_runtime; do
        package="$(manifest_package "$role")"
        if brew list --formula "$package" >/dev/null 2>&1; then
            record_result PASS "verify.system.${role}" "Required Homebrew formula is installed: ${package}."
        else
            record_result FAIL "verify.system.${role}" "Required Homebrew formula is missing: ${package}." \
                "Run setup_mac.sh."
        fi
    done
    package="$(manifest_package source_code_ide)"
    if brew list --cask "$package" >/dev/null 2>&1; then
        record_result PASS "verify.system.source_code_ide" "Required Homebrew cask is installed: ${package}."
    else
        record_result FAIL "verify.system.source_code_ide" "Required Homebrew cask is missing: ${package}." \
            "Run setup_mac.sh."
    fi

    local python_path code_cli python_version
    python_path="$(resolve_python 2>/dev/null || true)"
    code_cli="$(resolve_code_cli 2>/dev/null || true)"
    if command -v git >/dev/null 2>&1; then
        record_result PASS "verify.command.git" "$(git --version)"
    else
        record_result FAIL "verify.command.git" "The git command is unavailable." "Run setup_mac.sh."
    fi
    if command -v gh >/dev/null 2>&1; then
        record_result PASS "verify.command.gh" "$(gh --version | head -n 1)"
    else
        record_result FAIL "verify.command.gh" "The gh command is unavailable." "Run setup_mac.sh."
    fi
    if [[ -x "$python_path" ]]; then
        python_version="$("$python_path" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
        if [[ "$python_version" == "3.12" ]]; then
            record_result PASS "verify.command.python" "$("$python_path" --version 2>&1)"
        else
            record_result FAIL "verify.command.python" \
                "Python ${python_version} does not satisfy the required 3.12 range." "Run setup_mac.sh."
        fi
    else
        record_result FAIL "verify.command.python" "Python 3.12 is unavailable." "Run setup_mac.sh."
    fi
    if [[ -x "$code_cli" ]]; then
        record_result PASS "verify.command.code" \
            "Visual Studio Code $("$code_cli" --version | head -n 1) is available."
    else
        record_result FAIL "verify.command.code" \
            "The Visual Studio Code command-line interface is unavailable." "Run setup_mac.sh."
    fi
}

validate_git_settings() {
    local python_path
    python_path="$(resolve_python 2>/dev/null || true)"
    [[ -x "$python_path" ]] || return 2
    "$python_path" - "$MANIFEST_PATH" "$PLATFORM_ID" <<'PY'
import json
import subprocess
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
platform_id = sys.argv[2]
bindings = manifest["platforms"][platform_id]["course_ide_bindings"]
expected_settings = {}
for profile_id in bindings["version_control_system"].get("settings_profile_ids", []):
    profile = manifest["managed_settings"][profile_id]
    if platform_id in profile.get("platform_ids", []):
        expected_settings.update(profile["values"])
for key, expected in expected_settings.items():
    actual = subprocess.run(
        ["git", "config", "--global", "--get", key],
        check=False,
        capture_output=True,
        text=True,
    ).stdout.rstrip("\n")
    if isinstance(expected, bool):
        expected = "true" if expected else "false"
    if actual != str(expected):
        raise SystemExit(f"managed Git setting differs: {key}")
PY
}

validate_vscode_settings() {
    local python_path
    python_path="$(resolve_python 2>/dev/null || true)"
    [[ -x "$python_path" && -r "$VSCODE_SETTINGS_FILE" ]] || return 2
    "$python_path" - "$MANIFEST_PATH" "$PLATFORM_ID" "$VSCODE_SETTINGS_FILE" \
        "$VENV_DIR/bin/python" <<'PY'
import json
import pathlib
import sys

manifest_path, platform_id, settings_path, interpreter_path = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
settings = json.loads(pathlib.Path(settings_path).read_text(encoding="utf-8"))
if not isinstance(settings, dict):
    raise SystemExit("VS Code settings root is not an object")
bindings = manifest["platforms"][platform_id]["course_ide_bindings"]
expected = {}
for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
    profile = manifest["managed_settings"][profile_id]
    if platform_id in profile.get("platform_ids", []):
        expected.update(profile["values"])
expected.update({
    "python.defaultInterpreterPath": interpreter_path,
    "python.testing.pytestArgs": ["."],
    "terminal.integrated.defaultProfile.osx": "zsh",
    "terminal.integrated.cwd": "${userHome}/it140",
})

def contains(actual, desired):
    if isinstance(desired, dict):
        return isinstance(actual, dict) and all(
            key in actual and contains(actual[key], value)
            for key, value in desired.items()
        )
    return actual == desired

if not contains(settings, expected):
    raise SystemExit("managed VS Code settings differ")
PY
}

check_user_layer() {
    print_header "User-Layer Checks"
    if [[ -d "$COURSE_ROOT" && -d "$LOG_DIR" && -d "$PLATFORM_SCRIPT_DIR" ]]; then
        record_result PASS "verify.course_folders" "Required course folders are present."
    else
        record_result FAIL "verify.course_folders" "One or more required course folders are missing." \
            "Run config_mac.sh."
    fi

    local shell_file shell_label
    for shell_file in "$HOME/.zprofile" "$HOME/.zshrc"; do
        shell_label="${shell_file:t}"
        if [[ -r "$shell_file" ]] \
            && grep -Fq "$MANAGED_ENV_START" "$shell_file" \
            && grep -Fq "$MANAGED_ENV_END" "$shell_file" \
            && grep -Fq '$HOME/it140/.venv/bin' "$shell_file" \
            && grep -Fq '$HOME/it140/scripts/mac' "$shell_file"; then
            record_result PASS "verify.user_path.${shell_label}" \
                "The managed IT 140 shell environment is present in ~/${shell_label}."
        else
            record_result FAIL "verify.user_path.${shell_label}" \
                "The managed shell environment is missing or incomplete in ~/${shell_label}." \
                "Run config_mac.sh."
        fi
    done

    local python_path code_cli
    python_path="$(resolve_python 2>/dev/null || true)"
    code_cli="$(resolve_code_cli 2>/dev/null || true)"
    if [[ -x "$VENV_DIR/bin/python" ]]; then
        record_result PASS "verify.virtual_environment" "The course Python virtual environment is available."
        local package
        for package in "$(manifest_package test_runner)" "$(manifest_package coverage_reporter)" ruff; do
            if "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
                record_result PASS "verify.python_package.${package}" \
                    "Required Python package is installed: ${package}."
            else
                record_result FAIL "verify.python_package.${package}" \
                    "Required Python package is missing: ${package}." "Run config_mac.sh."
            fi
        done
    else
        record_result FAIL "verify.virtual_environment" \
            "The course Python virtual environment is unavailable." "Run config_mac.sh."
    fi

    if [[ -x "$code_cli" ]]; then
        local installed_extensions extension
        installed_extensions="$(NODE_NO_WARNINGS=1 "$code_cli" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        for extension in \
            "$(manifest_package language_support)" \
            "$(manifest_package code_quality_tool)" \
            "$(manifest_package diagram_support)" \
            "$(manifest_package pseudocode_support)" \
            "$(manifest_package spell_checker)" \
            "$(manifest_package file_viewer)"; do
            if printf '%s\n' "$installed_extensions" \
                | grep -Fxq "$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"; then
                record_result PASS "verify.extension.${extension}" \
                    "Required VS Code extension is installed: ${extension}."
            else
                record_result FAIL "verify.extension.${extension}" \
                    "Required VS Code extension is missing: ${extension}." "Run config_mac.sh."
            fi
        done
    else
        record_result FAIL "verify.extensions" "VS Code extensions could not be inspected." "Run setup_mac.sh."
    fi

    if command -v gh >/dev/null 2>&1 \
        && gh auth status --hostname github.com >/dev/null 2>&1; then
        record_result PASS "verify.provider_authentication" "GitHub CLI authentication is valid."
    else
        record_result FAIL "verify.provider_authentication" "GitHub CLI authentication is not valid." \
            "Run config_mac.sh."
    fi

    local git_name git_email
    git_name="$(git config --global user.name 2>/dev/null || true)"
    git_email="$(git config --global user.email 2>/dev/null || true)"
    if [[ -n "$git_name" ]]; then
        record_result PASS "verify.git_display_name" "A Git display name is configured."
    else
        record_result FAIL "verify.git_display_name" "A Git display name is not configured." "Run config_mac.sh."
    fi
    if printf '%s\n' "$git_email" \
        | grep -Eq '^[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$'; then
        record_result PASS "verify.git_private_identity" \
            "Git uses the approved GitHub private noreply identity."
    else
        record_result FAIL "verify.git_private_identity" \
            "Git does not use the approved private commit identity." "Run config_mac.sh."
    fi

    local git_validation_code=0
    validate_git_settings || git_validation_code=$?
    if (( git_validation_code == 0 )); then
        record_result PASS "verify.git_settings" "Manifest-declared Git settings are correct."
    elif (( git_validation_code == 2 )); then
        record_result FAIL "verify.git_settings" \
            "Git settings could not be validated because Python 3.12 is unavailable." "Run setup_mac.sh."
    else
        record_result FAIL "verify.git_settings" \
            "One or more manifest-declared Git settings are incorrect." "Run config_mac.sh."
    fi

    local vscode_validation_code=0
    validate_vscode_settings || vscode_validation_code=$?
    if (( vscode_validation_code == 0 )); then
        record_result PASS "verify.vscode_settings" "Managed VS Code settings are valid and correct."
    elif (( vscode_validation_code == 2 )); then
        record_result FAIL "verify.vscode_settings" \
            "VS Code settings could not be read or validated." "Run config_mac.sh."
    else
        record_result FAIL "verify.vscode_settings" \
            "Managed VS Code settings are invalid or incomplete." "Run config_mac.sh."
    fi

    local script_name
    for script_name in setup_mac.sh config_mac.sh verify_mac.sh update_mac.sh; do
        if [[ -x "$PLATFORM_SCRIPT_DIR/$script_name" ]]; then
            record_result PASS "verify.script.${script_name}" "${script_name} is present and executable."
        else
            record_result FAIL "verify.script.${script_name}" \
                "${script_name} is missing or is not executable." "Run bootstrap again or run update_mac.sh."
        fi
    done

    if [[ -L "$DESKTOP_SHORTCUT" && "$(/usr/bin/readlink "$DESKTOP_SHORTCUT")" == "$COURSE_ROOT" ]]; then
        record_result PASS "verify.desktop_shortcut" "The IT 140 desktop course-folder shortcut is correct."
    elif [[ -e "$DESKTOP_SHORTCUT" ]]; then
        record_result WARNING "verify.desktop_shortcut" \
            "A desktop item named 'IT 140' exists but is not the managed shortcut." \
            "Course work is unaffected; rename it and rerun config_mac.sh to create the shortcut."
    else
        record_result WARNING "verify.desktop_shortcut" \
            "The optional IT 140 desktop shortcut is not present." \
            "Run config_mac.sh to recreate this convenience shortcut."
    fi

    if [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]]; then
        record_result PASS "verify.managed_assets" "The course manifest and schema are present and readable."
    else
        record_result FAIL "verify.managed_assets" "The course manifest or schema is missing." \
            "Run bootstrap again or run update_mac.sh."
    fi
}

assert_read_only_behavior() {
    local final_snapshot
    final_snapshot="$(snapshot_managed_state)"
    if [[ "$INITIAL_STATE_SNAPSHOT" == "$final_snapshot" ]]; then
        record_result PASS "verify.read_only_assertion" \
            "No monitored managed file changed during verification."
    else
        record_result FAIL "verify.read_only_assertion" \
            "A monitored managed file changed during verification." \
            "Preserve the log and report this as an automation defect."
    fi
}

create_support_bundle() {
    print_header "Optional Sanitized Support Bundle"
    print_info "Proposed inventory:"
    printf '  - Sanitized verification log\n'
    printf '  - Manifest and script release summary\n'
    printf '  - macOS release and architecture\n'
    printf '  - Required component version summary\n'
    print_notice "Student files, repositories, Git history, credentials, and browser data are excluded."

    if [[ "$NONINTERACTIVE" == true ]]; then
        if [[ "$CONFIRM_SUPPORT_BUNDLE" != true ]]; then
            print_notice "Bundle creation was not confirmed in noninteractive mode."
            SUPPORT_BUNDLE_CANCELED=true
            return
        fi
    else
        printf '[ACTION REQUIRED] Create this sanitized bundle? [y/N]: '
        local response
        IFS= read -r response
        response="$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')"
        if [[ "$response" != "y" && "$response" != "yes" ]]; then
            print_notice "Support-bundle creation was canceled."
            SUPPORT_BUNDLE_CANCELED=true
            return
        fi
    fi

    local python_path staging sanitized_log summary_file bundle_path
    python_path="$(resolve_python 2>/dev/null || true)"
    if [[ ! -x "$python_path" ]]; then
        print_error "Python 3.12 is required to sanitize the support bundle."
        SUPPORT_BUNDLE_CANCELED=true
        return
    fi

    staging="$(mktemp -d "${TMPDIR:-/tmp}/it140-mac-support.XXXXXX")"
    TEMP_PATHS+=("$staging")
    chmod 0700 "$staging"
    sanitized_log="$staging/verify_mac_sanitized.log"
    summary_file="$staging/environment_summary.txt"
    bundle_path="$LOG_DIR/verify_mac_support_${RUN_TIMESTAMP}.tar.gz"

    "$python_path" - "$LOG_FILE" "$sanitized_log" "$HOME" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
home = sys.argv[3]
text = source.read_text(encoding="utf-8", errors="replace")
text = text.replace(home, "~")
text = re.sub(
    r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
    "<redacted-email>",
    text,
)
text = re.sub(
    r"(?i)(token|password|private[_ -]?key)\s*[:=]\s*\S+",
    r"\1=<redacted>",
    text,
)
destination.write_text(text, encoding="utf-8", newline="\n")
PY

    {
        printf 'Script version: %s\n' "$SCRIPT_VERSION"
        printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
        printf 'Deployment profile: %s\n' "$DEPLOYMENT_PROFILE_ID"
        printf 'macOS version: %s\n' "$(/usr/bin/sw_vers -productVersion)"
        printf 'Architecture: %s\n' "$(uname -m)"
        printf 'Pass count: %s\n' "$PASS_COUNT"
        printf 'Warning count: %s\n' "$WARNING_COUNT"
        printf 'Fail count: %s\n' "$FAIL_COUNT"
        initialize_homebrew_environment && printf 'Homebrew: %s\n' "$(brew --version | head -n 1)"
        command -v git >/dev/null 2>&1 && printf 'Git: %s\n' "$(git --version)"
        command -v gh >/dev/null 2>&1 && printf 'GitHub CLI: %s\n' "$(gh --version | head -n 1)"
        local code_cli python_path
        code_cli="$(resolve_code_cli 2>/dev/null || true)"
        python_path="$(resolve_python 2>/dev/null || true)"
        [[ -x "$python_path" ]] && printf 'Python: %s\n' "$("$python_path" --version 2>&1)"
        [[ -x "$code_cli" ]] && printf 'VS Code: %s\n' "$("$code_cli" --version | head -n 1)"
    } > "$summary_file"

    /usr/bin/tar -czf "$bundle_path" -C "$staging" \
        "$(basename "$sanitized_log")" "$(basename "$summary_file")"
    chmod 0600 "$bundle_path"
    print_success "Sanitized support bundle created: $bundle_path"
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    local overall="PASS"
    (( FAIL_COUNT > 0 )) && overall="FAIL"
    if (( FAIL_COUNT == 0 && WARNING_COUNT > 0 )); then
        overall="PASS WITH WARNINGS"
    fi

    print_header "VERIFICATION SUMMARY"
    printf 'Overall result   : %s\n' "$overall"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'PASS             : %s\n' "$PASS_COUNT"
    printf 'WARNING          : %s\n' "$WARNING_COUNT"
    printf 'FAIL             : %s\n' "$FAIL_COUNT"
    printf 'NOT APPLICABLE   : %s\n' "$NOT_APPLICABLE_COUNT"
    printf 'Elapsed time     : %s seconds\n' "$elapsed"
    printf 'Log file         : %s\n' "$LOG_FILE"

    if (( FAIL_COUNT > 0 )); then
        print_notice "Run the remediation script named by each failed check."
        return 1
    fi
    if [[ "$SUPPORT_BUNDLE_CANCELED" == true ]]; then
        return 6
    fi
    print_success "The IT 140 macOS environment passed all required checks."
    return 0
}

main() {
    parse_options "$@"
    initialize_log
    trap cleanup EXIT
    trap on_error ERR
    trap on_interrupt INT TERM

    print_header "IT 140 macOS ENVIRONMENT VERIFICATION"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Inspect the system and user course environment."
    print_info "Log file       : $LOG_FILE"
    print_notice "This script does not request privilege elevation or repair managed state."

    check_platform
    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || {
        print_error "The manifest or schema is missing."
        exit 5
    }
    check_supported_release
    validate_manifest || {
        print_error "The manifest or schema failed validation."
        exit 5
    }
    MANIFEST_RELEASE="$(manifest_raw automation_release)"
    print_success "Manifest release $MANIFEST_RELEASE validated."

    INITIAL_STATE_SNAPSHOT="$(snapshot_managed_state)"
    check_environment
    check_system_layer
    check_user_layer
    assert_read_only_behavior
    if [[ "$SUPPORT_BUNDLE_REQUESTED" == true ]]; then
        create_support_bundle
    fi

    trap - ERR INT TERM
    local final_code=0
    finish || final_code=$?
    print_closing_notices
    return "$final_code"
}

main "$@"
