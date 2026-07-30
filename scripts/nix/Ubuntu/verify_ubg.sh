#!/usr/bin/env bash
#
# IT 140 Ubuntu Desktop with GNOME read-only verification script
#
# Traceability: VER-FR-001 through VER-FR-014; VER-DES-001 through VER-DES-014
# Scope: Read-only inspection of the Ubuntu GNOME system and current-user course
#        layers. The only files created are the required transcript and an
#        explicitly approved, sanitized support bundle.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="2026.07.27.1"
readonly PLATFORM_ID="ubuntu_gnome"
readonly PLATFORM_ABBREVIATION="ubg"
readonly DEPLOYMENT_PROFILE_ID="ubuntu_gnome_bare_metal"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly PLATFORM_SCRIPT_DIR="${SCRIPT_ROOT}/${PLATFORM_ABBREVIATION}"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/verify_${PLATFORM_ABBREVIATION}_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly MANAGED_PATH_START="# >>> IT 140 managed PATH >>>"
readonly MANAGED_PATH_END="# <<< IT 140 managed PATH <<<"
readonly MANAGED_PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/ubg:$PATH"'
readonly APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
readonly COURSE_FOLDER_LAUNCHER="${APPLICATIONS_DIR}/it140-folder.desktop"
readonly COURSE_VSCODE_LAUNCHER="${APPLICATIONS_DIR}/it140-vscode.desktop"

NONINTERACTIVE=false
SUPPORT_BUNDLE=false
CONFIRM_SUPPORT_BUNDLE=false
SKIP_NETWORK=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
START_EPOCH="$(date +%s)"

PASS_COUNT=0
WARNING_COUNT=0
FAIL_COUNT=0
NA_COUNT=0
MANIFEST_FAILURE=false
UNSUPPORTED_FAILURE=false
SUPPORT_STAGING=""
RESULT_LINES=()
REMEDIATION_LINES=()

print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

print_info() { printf '[INFO] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }
print_error() { printf '[ERROR] %s\n' "$1" >&2; }

print_closing_notices() {
    print_notice "A log containing all output displayed while this script ran is available here:"
    print_notice "$LOG_FILE"
    print_notice "After reviewing the summary, type 'exit' and press Enter to close this Terminal."
    print_notice "Open a new Terminal before running another script or command so it loads the latest PATH and environment settings."
}

cleanup() {
    if [[ -n "$SUPPORT_STAGING" && -d "$SUPPORT_STAGING" ]]; then
        rm -rf "$SUPPORT_STAGING"
    fi
    SUPPORT_STAGING=""
}

usage() {
    cat <<USAGE
Usage: verify_ubg.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile ubuntu_gnome_bare_metal]
                     [--support-bundle] [--yes] [--skip-network]

Checks the IT 140 Course IDE on Ubuntu Desktop 24.04 LTS with GNOME without
installing, updating, removing, repairing, or rewriting course software and
settings.

--support-bundle  Offer to create a sanitized diagnostic bundle.
--yes             Confirm support-bundle creation in noninteractive mode.
--skip-network    Record network reachability as NOT APPLICABLE.

Log directory: ~/it140/logs/
USAGE
}

parse_options() {
    while (($#)); do
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
                SUPPORT_BUNDLE=true
                ;;
            --yes|-y)
                CONFIRM_SUPPORT_BUNDLE=true
                ;;
            --skip-network)
                SKIP_NETWORK=true
                ;;
            --deployment-profile)
                shift
                [[ $# -gt 0 ]] || {
                    print_error "Missing deployment profile."
                    exit 2
                }
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

add_remediation() {
    local remediation="$1"
    local existing
    [[ -n "$remediation" ]] || return 0
    for existing in "${REMEDIATION_LINES[@]}"; do
        [[ "$existing" == "$remediation" ]] && return 0
    done
    REMEDIATION_LINES+=("$remediation")
}

record_result() {
    local status="$1"
    local check_id="$2"
    local message="$3"
    local remediation="${4:-}"
    local label

    case "$status" in
        pass)
            label="PASS"
            PASS_COUNT=$((PASS_COUNT + 1))
            ;;
        warning)
            label="WARNING"
            WARNING_COUNT=$((WARNING_COUNT + 1))
            ;;
        fail)
            label="FAIL"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            add_remediation "$remediation"
            ;;
        not_applicable)
            label="NOT APPLICABLE"
            NA_COUNT=$((NA_COUNT + 1))
            ;;
        *)
            print_error "Internal verification status is invalid: $status"
            exit 1
            ;;
    esac

    printf '[%s] [%s] %s\n' "$label" "$check_id" "$message"
    RESULT_LINES+=("${label}|${check_id}|${message}")
}

validate_manifest() {
    python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" \
        "$REQUESTED_PROFILE" <<'PY'
import json
import pathlib
import sys

manifest_path, schema_path, platform_id, profile_id = sys.argv[1:]


class DuplicateKeyError(ValueError):
    pass


def no_duplicates(pairs):
    output = {}
    for key, value in pairs:
        if key in output:
            raise DuplicateKeyError(f"duplicate key: {key}")
        output[key] = value
    return output


try:
    manifest = json.loads(
        pathlib.Path(manifest_path).read_text(encoding="utf-8"),
        object_pairs_hook=no_duplicates,
    )
    schema = json.loads(
        pathlib.Path(schema_path).read_text(encoding="utf-8"),
        object_pairs_hook=no_duplicates,
    )
except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError) as exc:
    raise SystemExit(f"manifest validation failed: {exc}")

required = {
    "schema_version", "automation_release", "policy", "platforms",
    "deployment_profiles", "provider_profiles", "managed_settings",
    "managed_assets", "logging",
}
missing = sorted(required - manifest.keys())
if missing:
    raise SystemExit(f"manifest missing required keys: {', '.join(missing)}")
if manifest["schema_version"] != "1.0":
    raise SystemExit("unsupported manifest schema version")
if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
    raise SystemExit("schema is not the approved Draft 2020-12 format")
if manifest["policy"].get("allow_os_release_upgrade") is not False:
    raise SystemExit("manifest attempts to allow an OS release upgrade")
platform = manifest["platforms"].get(platform_id)
profile = manifest["deployment_profiles"].get(profile_id)
if not platform or not platform.get("enabled"):
    raise SystemExit("Ubuntu GNOME platform is not enabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("Ubuntu GNOME deployment profile is invalid")

try:
    import jsonschema  # type: ignore
except ImportError:
    pass
else:
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(manifest)

print(manifest["automation_release"])
PY
}

manifest_lines() {
    local query="$1"
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json
import sys

path, platform_id, query = sys.argv[1:]
manifest = json.load(open(path, encoding="utf-8"))
platform = manifest["platforms"][platform_id]
bindings = platform["course_ide_bindings"]

if query == "os_packages":
    for package in platform.get("os_packages", {}).values():
        if package.get("required"):
            print(package["package_identifier"])
elif query == "system_bindings":
    for role, binding in bindings.items():
        if binding.get("required") and binding.get("installation_scope") == "system":
            names = binding.get("verification", {}).get("executable_names", [])
            print("\t".join([role, binding["package_identifier"], ",".join(names)]))
elif query == "venv_packages":
    values = []
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "python_venv_package"):
            values.append(binding["package_identifier"])
    if bindings.get("code_quality_tool", {}).get("required"):
        values.append("ruff")
    for value in sorted(set(values)):
        print(value)
elif query == "extensions":
    for role, binding in bindings.items():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "vscode_extension"):
            print("\t".join([role, binding["package_identifier"]]))
elif query == "git_settings":
    profile_ids = bindings["version_control_system"].get("settings_profile_ids", [])
    for profile_id in profile_ids:
        for key, value in manifest["managed_settings"][profile_id]["values"].items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            print(f"{key}\t{value}")
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
elif query == "network_timeout":
    print(manifest["policy"].get("network_timeout_seconds", 60))
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}

has_managed_path_block() {
    local file="$1"
    [[ -r "$file" ]] || return 1
    grep -Fqx "$MANAGED_PATH_START" "$file" \
        && grep -Fqx "$MANAGED_PATH_EXPORT" "$file" \
        && grep -Fqx "$MANAGED_PATH_END" "$file"
}

has_valid_vscode_settings() {
    local settings_file="$HOME/.config/Code/User/settings.json"
    [[ -r "$settings_file" ]] || return 1

    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$settings_file" \
        "$VENV_DIR/bin/python" "$COURSE_ROOT" <<'PY'
import json
import pathlib
import sys

manifest_path, platform_id, settings_path, python_path, course_root = sys.argv[1:]
try:
    manifest = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"))
    settings = json.loads(pathlib.Path(settings_path).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
if not isinstance(settings, dict):
    raise SystemExit(1)
bindings = manifest["platforms"][platform_id]["course_ide_bindings"]
expected = {}
for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
    expected.update(manifest["managed_settings"][profile_id]["values"])
expected["python.defaultInterpreterPath"] = python_path
expected["files.defaultFolder"] = course_root


def contains(actual, desired):
    if isinstance(desired, dict):
        return isinstance(actual, dict) and all(
            key in actual and contains(actual[key], value)
            for key, value in desired.items()
        )
    return actual == desired


if not contains(settings, expected):
    raise SystemExit(1)
PY
}

check_platform() {
    if [[ "$EUID" -eq 0 ]]; then
        record_result fail "verify.user_context" \
            "Verify must run as the standard Ubuntu user, not root." \
            "Run verify_ubg.sh without sudo."
    else
        record_result pass "verify.user_context" \
            "Verify is running as the standard user $(id -un)."
    fi

    if [[ ! -r /etc/os-release ]]; then
        record_result fail "verify.platform" \
            "The operating system could not be identified." \
            "Use a supported Ubuntu Desktop 24.04 LTS computer."
        UNSUPPORTED_FAILURE=true
        return
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]]; then
        record_result pass "verify.os_release" \
            "Ubuntu 24.04 LTS is detected."
    else
        record_result fail "verify.os_release" \
            "This is not the supported Ubuntu Desktop 24.04 LTS release." \
            "Use a supported Ubuntu Desktop 24.04 LTS computer."
        UNSUPPORTED_FAILURE=true
    fi

    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" == amd64 || "$architecture" == x86_64 ]]; then
        record_result pass "verify.architecture" \
            "The x86_64 architecture is detected."
    else
        record_result fail "verify.architecture" \
            "Unsupported architecture detected: $architecture" \
            "Use an x86_64 computer for the qualified Ubuntu release."
        UNSUPPORTED_FAILURE=true
    fi

    if command -v gnome-shell >/dev/null 2>&1 \
        && command -v gsettings >/dev/null 2>&1; then
        record_result pass "verify.desktop" \
            "The GNOME desktop interface and settings tools are available."
    else
        record_result fail "verify.desktop" \
            "The required GNOME desktop interface is unavailable." \
            "Use Ubuntu Desktop 24.04 LTS with GNOME."
        UNSUPPORTED_FAILURE=true
    fi

    if [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* \
        || "${XDG_CURRENT_DESKTOP:-}" == *ubuntu* ]]; then
        record_result pass "verify.desktop_session" \
            "The current graphical session reports GNOME."
    else
        record_result warning "verify.desktop_session" \
            "The current Terminal session does not report an active GNOME desktop session."
    fi
}

check_disk_and_network() {
    local minimum available timeout
    minimum="$(manifest_lines minimum_space)"
    available="$(df -PB1 "$HOME" | awk 'NR==2 {print $4}')"

    if ((available >= minimum)); then
        record_result pass "verify.disk_space" \
            "$((available / 1024 / 1024 / 1024)) GB is available."
    else
        record_result fail "verify.disk_space" \
            "Less than the required $((minimum / 1024 / 1024 / 1024)) GB is available." \
            "Remove unneeded personal files, then rerun verify_ubg.sh."
    fi

    if [[ "$SKIP_NETWORK" == true ]]; then
        record_result not_applicable "verify.network" \
            "Network reachability was skipped by request."
        return
    fi

    timeout="$(manifest_lines network_timeout 2>/dev/null || printf '60')"
    if command -v curl >/dev/null 2>&1 \
        && curl --head --silent --fail --max-time "$timeout" \
            https://github.com/ >/dev/null; then
        record_result pass "verify.network" \
            "The approved source-code hosting service is reachable."
    else
        record_result warning "verify.network" \
            "The approved source-code hosting service did not respond within ${timeout} seconds."
    fi
}

check_system_layer() {
    local package role package_id executables binding_ok version_text executable
    local -a executable_names

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
            | grep -q 'install ok installed'; then
            record_result pass "verify.package.${package}" \
                "Required operating-system package is installed: $package"
        else
            record_result fail "verify.package.${package}" \
                "Required operating-system package is missing: $package" \
                "Run setup_ubg.sh. If the same check still fails, contact course support."
        fi
    done < <(manifest_lines os_packages)

    while IFS=$'\t' read -r role package_id executables; do
        [[ -n "$role" ]] || continue
        binding_ok=true
        IFS=',' read -r -a executable_names <<<"$executables"

        if ((${#executable_names[@]} == 0)); then
            binding_ok=false
        else
            for executable in "${executable_names[@]}"; do
                command -v "$executable" >/dev/null 2>&1 || binding_ok=false
            done
        fi

        version_text="available"
        if [[ "$binding_ok" == true ]]; then
            case "$role" in
                programming_language_runtime)
                    version_text="$(python3.12 --version 2>&1 || true)"
                    python3.12 -c \
                        'import sys; raise SystemExit(sys.version_info[:2] != (3, 12))' \
                        || binding_ok=false
                    ;;
                version_control_system)
                    version_text="$(git --version 2>&1 || true)"
                    ;;
                source_hosting_client)
                    version_text="$(gh --version 2>&1 | head -1 || true)"
                    ;;
                source_code_ide)
                    version_text="$(code --version 2>&1 | head -1 || true)"
                    ;;
            esac
        fi

        if [[ "$binding_ok" == true ]]; then
            record_result pass "verify.capability.${role}" \
                "Required system capability is available: $version_text"
        else
            record_result fail "verify.capability.${role}" \
                "Required system capability is missing or not compliant: $package_id" \
                "Run setup_ubg.sh. If the same check still fails, contact course support."
        fi
    done < <(manifest_lines system_bindings)

    if [[ -r /etc/apt/sources.list.d/github-cli.list \
        && -r /etc/apt/keyrings/githubcli-archive-keyring.gpg ]]; then
        record_result pass "verify.repository.github_cli" \
            "The approved GitHub CLI package source is configured."
    else
        record_result fail "verify.repository.github_cli" \
            "The approved GitHub CLI package source is incomplete." \
            "Run setup_ubg.sh."
    fi

    if [[ -r /etc/apt/sources.list.d/vscode.sources \
        && -r /usr/share/keyrings/microsoft.gpg ]]; then
        record_result pass "verify.repository.vscode" \
            "The approved Visual Studio Code package source is configured."
    else
        record_result fail "verify.repository.vscode" \
            "The approved Visual Studio Code package source is incomplete." \
            "Run setup_ubg.sh."
    fi

    if [[ -e /var/run/reboot-required ]]; then
        record_result warning "verify.restart" \
            "Ubuntu reports that a restart is required to finish updates."
    else
        record_result pass "verify.restart" \
            "Ubuntu does not report a pending required restart."
    fi
}

check_user_layer() {
    local package role extension key expected_value configured_value
    local git_email installed_extensions script

    if [[ -d "$COURSE_ROOT" && -d "$LOG_DIR" ]]; then
        record_result pass "verify.course_folders" \
            "The course root and log folder are present."
    else
        record_result fail "verify.course_folders" \
            "The required course folders are incomplete." \
            "Run config_ubg.sh, close this terminal, open a new Terminal, and rerun verify_ubg.sh."
    fi

    if has_managed_path_block "$HOME/.profile" \
        && has_managed_path_block "$HOME/.bashrc"; then
        record_result pass "verify.user_path_files" \
            "The exact managed course PATH block is present in ~/.profile and ~/.bashrc."
    else
        record_result fail "verify.user_path_files" \
            "The exact managed course PATH block is missing from ~/.profile or ~/.bashrc." \
            "Run config_ubg.sh, close this terminal, open a new Terminal, and rerun verify_ubg.sh."
    fi

    if [[ ":$PATH:" == *":$VENV_DIR/bin:"* \
        && ":$PATH:" == *":$PLATFORM_SCRIPT_DIR:"* ]]; then
        record_result pass "verify.current_path" \
            "The current Terminal session includes the course Python and script folders."
    else
        record_result fail "verify.current_path" \
            "The current Terminal session does not include all managed course PATH entries." \
            "Close this terminal, open a new Terminal, and rerun verify_ubg.sh."
    fi

    if [[ -x "$VENV_DIR/bin/python" ]]; then
        record_result pass "verify.virtual_environment" \
            "The course Python virtual environment is usable."
    else
        record_result fail "verify.virtual_environment" \
            "The course Python virtual environment is missing." \
            "Run config_ubg.sh, close this terminal, open a new Terminal, and rerun verify_ubg.sh."
    fi

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if [[ -x "$VENV_DIR/bin/python" ]] \
            && "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
            record_result pass "verify.user_tool.${package}" \
                "Required course Python tool is installed: $package"
        else
            record_result fail "verify.user_tool.${package}" \
                "Required course Python tool is missing: $package" \
                "Run config_ubg.sh, close this terminal, open a new Terminal, and rerun verify_ubg.sh."
        fi
    done < <(manifest_lines venv_packages)

    installed_extensions=""
    if command -v code >/dev/null 2>&1; then
        installed_extensions="$(NODE_NO_WARNINGS=1 code --list-extensions 2>/dev/null \
            | tr '[:upper:]' '[:lower:]')"
    fi
    while IFS=$'\t' read -r role extension; do
        [[ -n "$role" ]] || continue
        if grep -Fxq "${extension,,}" <<<"$installed_extensions"; then
            record_result pass "verify.extension.${role}" \
                "Required IDE extension is installed: $extension"
        else
            record_result fail "verify.extension.${role}" \
                "Required IDE extension is missing: $extension" \
                "Run config_ubg.sh, close this terminal, open a new Terminal, and rerun verify_ubg.sh."
        fi
    done < <(manifest_lines extensions)

    if gh auth status --hostname github.com >/dev/null 2>&1; then
        record_result pass "verify.provider_authentication" \
            "GitHub authentication is valid."
    else
        record_result fail "verify.provider_authentication" \
            "GitHub authentication is missing or invalid." \
            "Run config_ubg.sh, close this terminal, open a new Terminal, and rerun verify_ubg.sh."
    fi

    if [[ -n "$(git config --global user.name 2>/dev/null || true)" ]]; then
        record_result pass "verify.git_display_name" \
            "A Git display name is configured."
    else
        record_result fail "verify.git_display_name" \
            "The Git display name is missing." \
            "Run config_ubg.sh."
    fi

    git_email="$(git config --global user.email 2>/dev/null || true)"
    if [[ "$git_email" =~ ^[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$ ]]; then
        record_result pass "verify.git_private_identity" \
            "Git uses the approved private noreply identity."
    else
        record_result fail "verify.git_private_identity" \
            "Git is not using the approved private noreply identity." \
            "Run config_ubg.sh."
    fi

    while IFS=$'\t' read -r key expected_value; do
        [[ -n "$key" ]] || continue
        configured_value="$(git config --global --get "$key" 2>/dev/null || true)"
        if [[ "$configured_value" == "$expected_value" ]]; then
            record_result pass "verify.git_setting.${key}" \
                "Git setting is correct: $key=$expected_value"
        else
            record_result fail "verify.git_setting.${key}" \
                "Git setting is incorrect: $key" \
                "Run config_ubg.sh."
        fi
    done < <(manifest_lines git_settings)

    if has_valid_vscode_settings; then
        record_result pass "verify.vscode_settings" \
            "Course-managed VS Code settings are present and valid."
    else
        record_result fail "verify.vscode_settings" \
            "Course-managed VS Code settings are missing or invalid." \
            "Run config_ubg.sh."
    fi

    for script in bootstrap_ubg.sh setup_ubg.sh config_ubg.sh verify_ubg.sh update_ubg.sh; do
        if [[ -r "$PLATFORM_SCRIPT_DIR/$script" ]] \
            && bash -n "$PLATFORM_SCRIPT_DIR/$script" 2>/dev/null; then
            record_result pass "verify.script.${script}" \
                "Course automation file is readable and syntactically valid: $script"
        else
            record_result fail "verify.script.${script}" \
                "Course automation file is missing or invalid: $script" \
                "Run bootstrap_ubg.sh again or restore the file from the course repository."
        fi
    done
}

check_desktop_layer() {
    local favorite_apps bookmark
    bookmark="file://${COURSE_ROOT} IT 140"

    if [[ -r "$COURSE_FOLDER_LAUNCHER" ]] \
        && desktop-file-validate "$COURSE_FOLDER_LAUNCHER" >/dev/null 2>&1; then
        record_result pass "verify.desktop.folder_launcher" \
            "The IT 140 course-folder application launcher is valid."
    else
        record_result fail "verify.desktop.folder_launcher" \
            "The IT 140 course-folder application launcher is missing or invalid." \
            "Run config_ubg.sh."
    fi

    if [[ -r "$COURSE_VSCODE_LAUNCHER" ]] \
        && desktop-file-validate "$COURSE_VSCODE_LAUNCHER" >/dev/null 2>&1; then
        record_result pass "verify.desktop.vscode_launcher" \
            "The IT 140 Visual Studio Code application launcher is valid."
    else
        record_result fail "verify.desktop.vscode_launcher" \
            "The IT 140 Visual Studio Code application launcher is missing or invalid." \
            "Run config_ubg.sh."
    fi

    if grep -Fqx "$bookmark" "$HOME/.config/gtk-3.0/bookmarks" 2>/dev/null \
        || grep -Fqx "$bookmark" "$HOME/.config/gtk-4.0/bookmarks" 2>/dev/null; then
        record_result pass "verify.desktop.file_manager_bookmark" \
            "The IT 140 folder is available as a file-manager bookmark."
    else
        record_result warning "verify.desktop.file_manager_bookmark" \
            "The optional IT 140 file-manager bookmark was not found."
    fi

    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        favorite_apps="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || true)"
        if grep -Fq "it140-vscode.desktop" <<<"$favorite_apps"; then
            record_result pass "verify.desktop.dock" \
                "The IT 140 Visual Studio Code launcher is available on the GNOME dock."
        else
            record_result warning "verify.desktop.dock" \
                "The optional IT 140 Visual Studio Code dock favorite was not found."
        fi
    else
        record_result not_applicable "verify.desktop.dock" \
            "GNOME dock status cannot be checked outside an active graphical session."
    fi
}

create_support_bundle() {
    [[ "$SUPPORT_BUNDLE" == true ]] || return 0

    local confirmed=false response bundle timestamp
    if [[ "$NONINTERACTIVE" == true ]]; then
        [[ "$CONFIRM_SUPPORT_BUNDLE" == true ]] && confirmed=true
    else
        print_notice "The support bundle contains only a sanitized verification log and diagnostic summary."
        printf '[ACTION REQUIRED] Create the sanitized support bundle? [y/N]: '
        read -r response
        [[ "${response,,}" == y || "${response,,}" == yes ]] && confirmed=true
    fi

    if [[ "$confirmed" != true ]]; then
        print_notice "Support-bundle creation was not approved."
        return 0
    fi

    timestamp="$(date +%Y%m%d_%H%M%S)"
    bundle="$LOG_DIR/it140_support_${PLATFORM_ABBREVIATION}_${timestamp}.tar.gz"
    SUPPORT_STAGING="$(mktemp -d)"
    chmod 0700 "$SUPPORT_STAGING"

    python3 - "$LOG_FILE" "$SUPPORT_STAGING/verify_sanitized.log" \
        "$HOME" "$(id -un)" <<'PY'
import pathlib
import re
import sys

source, destination, home, username = sys.argv[1:]
text = pathlib.Path(source).read_text(encoding="utf-8", errors="replace")
text = text.replace(home, "~")
text = re.sub(rf"\b{re.escape(username)}\b", "<user>", text)
text = re.sub(
    r"\b[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com\b",
    "<private-noreply-email>",
    text,
)
pathlib.Path(destination).write_text(text, encoding="utf-8", newline="\n")
PY

    {
        printf 'IT 140 Ubuntu GNOME Verification Summary\n'
        printf 'Created: %s\n' "$(date --iso-8601=seconds)"
        printf 'Script version: %s\n' "$SCRIPT_VERSION"
        printf 'Manifest release: %s\n' "${MANIFEST_RELEASE:-unavailable}"
        printf 'Platform: %s (%s)\n' "$PLATFORM_ID" "$PLATFORM_ABBREVIATION"
        printf 'PASS: %s\n' "$PASS_COUNT"
        printf 'WARNING: %s\n' "$WARNING_COUNT"
        printf 'FAIL: %s\n' "$FAIL_COUNT"
        printf 'NOT APPLICABLE: %s\n' "$NA_COUNT"
        printf '\nVersions:\n'
        printf 'Ubuntu: %s\n' "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")"
        printf 'Kernel: %s\n' "$(uname -sr)"
        printf 'Git: %s\n' "$(git --version 2>/dev/null || printf unavailable)"
        printf 'GitHub CLI: %s\n' "$(gh --version 2>/dev/null | head -1 || printf unavailable)"
        printf 'Python: %s\n' "$(python3.12 --version 2>/dev/null || printf unavailable)"
        printf 'VS Code: %s\n' "$(code --version 2>/dev/null | head -1 || printf unavailable)"
    } > "$SUPPORT_STAGING/summary.txt"

    tar -czf "$bundle" -C "$SUPPORT_STAGING" verify_sanitized.log summary.txt
    chmod 0600 "$bundle"
    rm -rf "$SUPPORT_STAGING"
    SUPPORT_STAGING=""
    print_success "Sanitized support bundle created: $bundle"
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    local exit_code=0 result="PASS"

    if [[ "$MANIFEST_FAILURE" == true ]]; then
        exit_code=5
        result="FAIL"
    elif [[ "$UNSUPPORTED_FAILURE" == true ]]; then
        exit_code=2
        result="FAIL"
    elif ((FAIL_COUNT > 0)); then
        exit_code=1
        result="FAIL"
    elif ((WARNING_COUNT > 0)); then
        result="PASS WITH WARNINGS"
    fi

    print_header "VERIFICATION SUMMARY"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "${MANIFEST_RELEASE:-unavailable}"
    printf 'Platform        : %s (%s)\n' "$PLATFORM_ID" "$PLATFORM_ABBREVIATION"
    printf 'PASS             : %s\n' "$PASS_COUNT"
    printf 'WARNING          : %s\n' "$WARNING_COUNT"
    printf 'FAIL             : %s\n' "$FAIL_COUNT"
    printf 'NOT APPLICABLE   : %s\n' "$NA_COUNT"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : %s\n' "$exit_code"

    if ((${#REMEDIATION_LINES[@]})); then
        printf '\nRequired next actions:\n'
        local remediation
        for remediation in "${REMEDIATION_LINES[@]}"; do
            printf ' - %s\n' "$remediation"
        done
    elif [[ -e /var/run/reboot-required ]]; then
        printf 'Next step       : Restart Ubuntu, then rerun verify_ubg.sh.\n'
    else
        printf 'Next step       : The IT 140 Course IDE is ready to use.\n'
    fi

    create_support_bundle
    print_closing_notices
    exit "$exit_code"
}

main() {
    parse_options "$@"

    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap cleanup EXIT
    trap 'print_error "Verification was interrupted."; exit 6' INT TERM

    print_header "IT 140 UBUNTU DESKTOP VERIFICATION"
    print_info "Script version  : $SCRIPT_VERSION"
    print_info "Current user    : $(id -un)"
    print_info "Purpose         : Inspect the system and user course layers without changing them."
    print_info "Log file        : $LOG_FILE"

    print_header "Step 1: Platform Validation"
    check_platform

    print_header "Step 2: Manifest Validation"
    if [[ ! -r "$MANIFEST_PATH" || ! -r "$SCHEMA_PATH" ]]; then
        record_result fail "verify.manifest_files" \
            "The manifest or schema is missing." \
            "Run bootstrap_ubg.sh again to restore course automation assets."
        MANIFEST_FAILURE=true
        finish
    fi
    if MANIFEST_RELEASE="$(validate_manifest)"; then
        readonly MANIFEST_RELEASE
        record_result pass "verify.manifest" \
            "Manifest release $MANIFEST_RELEASE is valid for Ubuntu GNOME."
    else
        record_result fail "verify.manifest" \
            "The manifest or schema is invalid for Ubuntu GNOME." \
            "Run bootstrap_ubg.sh again. If validation still fails, contact course support."
        MANIFEST_FAILURE=true
        finish
    fi

    print_header "Step 3: Capacity and Network"
    check_disk_and_network

    print_header "Step 4: System Layer"
    check_system_layer

    print_header "Step 5: User Layer"
    check_user_layer

    print_header "Step 6: GNOME Desktop Integration"
    check_desktop_layer

    finish
}

main "$@"
