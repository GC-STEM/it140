#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop read-only verification script
#
# Traceability: VER-FR-001 through VER-FR-014; VER-DES-001 through VER-DES-014
# Scope: Read-only inspection of the CVD system and current-user course layers.
# The only files created are the required transcript and an explicitly approved,
# sanitized support bundle.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="2026.07.25.2"
readonly PLATFORM_ID="cvd"
readonly DEPLOYMENT_PROFILE_ID="codio_cvd"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly PLATFORM_SCRIPT_DIR="${SCRIPT_ROOT}/${PLATFORM_ID}"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/verify_${PLATFORM_ID}_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"

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
EXTERNAL_FAILURE=false
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

cleanup() {
    if [[ -n "$SUPPORT_STAGING" && -d "$SUPPORT_STAGING" ]]; then
        rm -rf "$SUPPORT_STAGING"
    fi
    SUPPORT_STAGING=""
}

usage() {
    cat <<USAGE
Usage: verify_cvd.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile codio_cvd]
                     [--support-bundle] [--yes] [--skip-network]

Checks the IT 140 Codio Virtual Desktop without installing, updating, removing,
repairing, or rewriting course software and settings.

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
                [[ $# -gt 0 ]] || { print_error "Missing deployment profile."; exit 2; }
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

record_result() {
    local status="$1" check_id="$2" message="$3" remediation="${4:-}"
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
    if [[ "$status" == fail && -n "$remediation" ]]; then
        REMEDIATION_LINES+=("${check_id}|${remediation}")
    fi
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
    raise SystemExit("CVD platform is not enabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("CVD deployment profile is invalid")

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
    for role, binding in bindings.items():
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
    for profile_id in bindings["version_control_system"].get("settings_profile_ids", []):
        for key, value in manifest["managed_settings"][profile_id]["values"].items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            print(f"{key}\t{value}")
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
elif query == "asset_destinations":
    values = {
        "HOME": str(__import__('pathlib').Path.home()),
        "COURSE_ROOT": str(__import__('pathlib').Path.home() / "it140"),
        "SCRIPT_ROOT": str(__import__('pathlib').Path.home() / "it140" / "scripts"),
    }
    for asset_id, asset in manifest.get("managed_assets", {}).items():
        destination = asset["destination"]
        for key, value in values.items():
            destination = destination.replace("${" + key + "}", value)
        print(f"{asset_id}\t{destination}")
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}

check_platform() {
    if [[ "$EUID" -eq 0 ]]; then
        record_result fail "verify.user_context" \
            "Verify must run as the standard CVD user, not root." \
            "Run verify_cvd.sh without sudo."
    else
        record_result pass "verify.user_context" \
            "Verify is running as the standard user $(id -un)."
    fi

    if [[ ! -r /etc/os-release ]]; then
        record_result fail "verify.platform" \
            "The operating system could not be identified." \
            "Contact Codio or course support."
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
            "This is not the supported Ubuntu 24.04 CVD." \
            "Contact Codio or course support."
        UNSUPPORTED_FAILURE=true
    fi

    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" == amd64 || "$architecture" == x86_64 ]]; then
        record_result pass "verify.architecture" "The x86_64 architecture is detected."
    else
        record_result fail "verify.architecture" \
            "Unsupported architecture detected: $architecture" \
            "Contact Codio or course support."
        UNSUPPORTED_FAILURE=true
    fi

    if command -v xfconf-query >/dev/null 2>&1; then
        record_result pass "verify.desktop" "The Xfce desktop interface is available."
    else
        record_result fail "verify.desktop" \
            "The required Xfce desktop interface is unavailable." \
            "Contact Codio or course support."
        UNSUPPORTED_FAILURE=true
    fi
}

check_disk_and_network() {
    local minimum available
    minimum="$(manifest_lines minimum_space)"
    available="$(df -PB1 "$HOME" | awk 'NR==2 {print $4}')"
    if ((available >= minimum)); then
        record_result pass "verify.disk_space" \
            "$((available / 1024 / 1024 / 1024)) GB is available."
    else
        record_result fail "verify.disk_space" \
            "Less than the required $((minimum / 1024 / 1024 / 1024)) GB is available." \
            "Remove unneeded personal files or contact Codio support."
    fi

    if [[ "$SKIP_NETWORK" == true ]]; then
        record_result not_applicable "verify.network" \
            "Network reachability was skipped by request."
    elif command -v curl >/dev/null 2>&1 && \
        curl --head --silent --fail --max-time 10 https://github.com/ >/dev/null; then
        record_result pass "verify.network" \
            "The approved source-code hosting service is reachable."
    else
        record_result warning "verify.network" \
            "The approved source-code hosting service did not respond within 10 seconds." \
            "Check the network connection before setup, configuration, or update."
        EXTERNAL_FAILURE=true
    fi
}

check_system_layer() {
    local package role package_id executables executable

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
            | grep -q 'install ok installed'; then
            record_result pass "verify.package.${package}" \
                "Required operating-system package is installed: $package"
        else
            record_result fail "verify.package.${package}" \
                "Required operating-system package is missing: $package" \
                "Run setup_cvd.sh from a terminal."
        fi
    done < <(manifest_lines os_packages)

    while IFS=$'\t' read -r role package_id executables; do
        [[ -n "$role" ]] || continue
        local binding_ok=true
        IFS=',' read -r -a executable_names <<<"$executables"
        if ((${#executable_names[@]} == 0)); then
            binding_ok=false
        else
            for executable in "${executable_names[@]}"; do
                if ! command -v "$executable" >/dev/null 2>&1; then
                    binding_ok=false
                fi
            done
        fi
        if [[ "$binding_ok" == true ]]; then
            local version_text="available"
            case "$role" in
                programming_language_runtime)
                    version_text="$(python3.12 --version 2>&1 || true)"
                    if ! python3.12 -c 'import sys; raise SystemExit(sys.version_info[:2] != (3, 12))'; then
                        binding_ok=false
                    fi
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
            if [[ "$binding_ok" == true ]]; then
                record_result pass "verify.capability.${role}" \
                    "Required system capability is available: $version_text"
            else
                record_result fail "verify.capability.${role}" \
                    "The required runtime version is not compliant." \
                    "Run setup_cvd.sh from a terminal."
            fi
        else
            record_result fail "verify.capability.${role}" \
                "Required system capability is missing: $package_id" \
                "Run setup_cvd.sh from a terminal."
        fi
    done < <(manifest_lines system_bindings)

    if [[ -r /etc/opt/chrome/policies/managed/it140_bookmarks.json ]] && \
        python3 -m json.tool \
            /etc/opt/chrome/policies/managed/it140_bookmarks.json >/dev/null 2>&1; then
        record_result pass "verify.system.chrome_policy" \
            "The course browser bookmark policy is valid."
    else
        record_result fail "verify.system.chrome_policy" \
            "The course browser bookmark policy is missing or invalid." \
            "Run setup_cvd.sh from a terminal."
    fi

    if [[ -r /etc/xdg/autostart/numlockx.desktop ]]; then
        record_result pass "verify.system.numlock" \
            "The CVD Num Lock session policy is present."
    else
        record_result fail "verify.system.numlock" \
            "The CVD Num Lock session policy is missing." \
            "Run setup_cvd.sh from a terminal."
    fi
}

check_user_layer() {
    local package role extension expected actual

    if [[ -d "$COURSE_ROOT" && -d "$LOG_DIR" ]]; then
        record_result pass "verify.course_folders" \
            "The course root and log folder are present."
    else
        record_result fail "verify.course_folders" \
            "The required course folders are incomplete." \
            "Run configure_cvd.sh from a terminal."
    fi

    if grep -Fq '# >>> IT 140 managed PATH >>>' "$HOME/.profile" 2>/dev/null && \
        grep -Fq "$HOME/it140/scripts/cvd" <(sed "s#\$HOME#$HOME#g" "$HOME/.profile") 2>/dev/null; then
        record_result pass "verify.user_path" \
            "The managed course PATH entry is present in the user profile."
    else
        record_result fail "verify.user_path" \
            "The managed course PATH entry is missing." \
            "Run configure_cvd.sh from a terminal."
    fi

    if [[ -x "$VENV_DIR/bin/python" ]]; then
        record_result pass "verify.virtual_environment" \
            "The course Python virtual environment is usable."
    else
        record_result fail "verify.virtual_environment" \
            "The course Python virtual environment is missing." \
            "Run configure_cvd.sh from a terminal."
    fi

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if [[ -x "$VENV_DIR/bin/python" ]] && \
            "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
            record_result pass "verify.user_tool.${package}" \
                "Required course Python tool is installed: $package"
        else
            record_result fail "verify.user_tool.${package}" \
                "Required course Python tool is missing: $package" \
                "Run configure_cvd.sh from a terminal."
        fi
    done < <(manifest_lines venv_packages)

    local installed_extensions=""
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
                "Run configure_cvd.sh from a terminal."
        fi
    done < <(manifest_lines extensions)

    if gh auth status --hostname github.com >/dev/null 2>&1; then
        record_result pass "verify.provider_authentication" \
            "Source-code hosting authentication is valid."
    else
        record_result fail "verify.provider_authentication" \
            "Source-code hosting authentication is missing or invalid." \
            "Run configure_cvd.sh from a terminal."
    fi

    if [[ -n "$(git config --global user.name || true)" ]]; then
        record_result pass "verify.git_display_name" \
            "A Git display name is configured."
    else
        record_result fail "verify.git_display_name" \
            "The Git display name is missing." \
            "Run configure_cvd.sh from a terminal."
    fi

    local git_email
    git_email="$(git config --global user.email || true)"
    if [[ "$git_email" =~ ^[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$ ]]; then
        record_result pass "verify.git_private_identity" \
            "Git uses the provider-approved private noreply identity."
    else
        record_result fail "verify.git_private_identity" \
            "Git does not use the approved private commit identity." \
            "Run configure_cvd.sh from a terminal."
    fi

    while IFS=$'\t' read -r expected actual; do
        [[ -n "$expected" ]] || continue
        local configured
        configured="$(git config --global --get "$expected" || true)"
        if [[ "$configured" == "$actual" ]]; then
            record_result pass "verify.git_setting.${expected}" \
                "Managed Git setting is correct: $expected"
        else
            record_result fail "verify.git_setting.${expected}" \
                "Managed Git setting is incorrect: $expected" \
                "Run configure_cvd.sh from a terminal."
        fi
    done < <(manifest_lines git_settings)

    local settings_file="$HOME/.config/Code/User/settings.json"
    if python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$settings_file" \
        "$VENV_DIR/bin/python" "$COURSE_ROOT" <<'PY'
import json
import pathlib
import sys

manifest_path, platform_id, settings_path, python_path, course_root = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
settings = json.load(open(settings_path, encoding="utf-8"))
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
    then
        record_result pass "verify.ide_settings" \
            "Required IDE settings are present and valid."
    else
        record_result fail "verify.ide_settings" \
            "Required IDE settings are missing, invalid, or not compliant." \
            "Run configure_cvd.sh from a terminal."
    fi

    local desktop_dir
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    desktop_dir="${desktop_dir:-$HOME/Desktop}"
    if [[ -x "$desktop_dir/it140.desktop" && \
          -x "$desktop_dir/visual-studio-code.desktop" ]]; then
        record_result pass "verify.desktop_launchers" \
            "The course folder and IDE desktop launchers are present."
    else
        record_result fail "verify.desktop_launchers" \
            "One or more course desktop launchers are missing." \
            "Run configure_cvd.sh from a terminal."
    fi

    local marker="$HOME/.config/xfce4/panel/it140-vscode-plugin-id"
    if [[ -s "$marker" && "$(<"$marker")" =~ ^[0-9]+$ ]]; then
        record_result pass "verify.panel_launcher" \
            "The managed VS Code panel-launcher record is present."
    else
        record_result warning "verify.panel_launcher" \
            "The managed VS Code panel-launcher record was not found." \
            "Run configure_cvd.sh to repair the panel launcher."
    fi

    local script
    for script in setup_cvd.sh configure_cvd.sh verify_cvd.sh update_cvd.sh; do
        if [[ -x "$PLATFORM_SCRIPT_DIR/$script" ]]; then
            record_result pass "verify.script_permissions.${script}" \
                "$script is executable."
        else
            record_result fail "verify.script_permissions.${script}" \
                "$script is missing or not executable." \
                "Run configure_cvd.sh or update_cvd.sh from a terminal."
        fi
    done
}

check_managed_assets() {
    local asset_id destination
    while IFS=$'\t' read -r asset_id destination; do
        [[ -n "$asset_id" ]] || continue
        if [[ -r "$destination" ]]; then
            record_result pass "verify.asset.${asset_id}" \
                "Managed asset is present: ${destination/#$HOME/~}"
        else
            record_result fail "verify.asset.${asset_id}" \
                "Managed asset is missing: ${destination/#$HOME/~}" \
                "Run update_cvd.sh from a terminal."
        fi
    done < <(manifest_lines asset_destinations)
}

create_support_bundle() {
    [[ "$SUPPORT_BUNDLE" == true ]] || return 0

    print_header "SANITIZED SUPPORT BUNDLE"
    print_notice "The bundle will include only:"
    printf '  - Sanitized verification log\n'
    printf '  - Manifest and script release summary\n'
    printf '  - Supported platform facts\n'
    printf '  - Required capability version summary\n'
    print_notice "It will not include coursework, repositories, Git history, credentials, or browser data."

    if [[ "$NONINTERACTIVE" == true ]]; then
        if [[ "$CONFIRM_SUPPORT_BUNDLE" != true ]]; then
            record_result warning "verify.support_bundle" \
                "Bundle creation was not confirmed in noninteractive mode."
            return 0
        fi
    elif [[ "$CONFIRM_SUPPORT_BUNDLE" != true ]]; then
        printf '[ACTION REQUIRED] Create the sanitized bundle? [y/N]: '
        read -r response
        if [[ "${response,,}" != y && "${response,,}" != yes ]]; then
            record_result warning "verify.support_bundle" \
                "Bundle creation was canceled; the verification log remains available."
            return 0
        fi
    fi

    local staging bundle timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    staging="$(mktemp -d)"
    SUPPORT_STAGING="$staging"
    bundle="$LOG_DIR/verify_${PLATFORM_ID}_${timestamp}_support.tar.gz"

    sed -E \
        -e 's/[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com/[PRIVATE_NOREPLY_IDENTITY]/g' \
        -e 's#(/home/)[^/]+#\1[USER]#g' \
        "$LOG_FILE" > "$staging/sanitized_verify.log"

    cat > "$staging/release_summary.txt" <<SUMMARY
Script version: $SCRIPT_VERSION
Manifest release: ${MANIFEST_RELEASE:-unavailable}
Schema version: 1.0
Platform: $PLATFORM_ID
Deployment profile: $REQUESTED_PROFILE
SUMMARY

    {
        printf 'Operating system: '
        if [[ -r /etc/os-release ]]; then
            # shellcheck disable=SC1091
            source /etc/os-release
            printf '%s\n' "${PRETTY_NAME:-unknown}"
        else
            printf 'unknown\n'
        fi
        printf 'Architecture: %s\n' "$(uname -m)"
        printf 'Desktop: Xfce\n'
        printf 'Session: remote desktop\n'
    } > "$staging/platform_facts.txt"

    {
        command -v python3.12 >/dev/null 2>&1 && python3.12 --version
        command -v git >/dev/null 2>&1 && git --version
        command -v gh >/dev/null 2>&1 && gh --version | head -1
        command -v code >/dev/null 2>&1 && code --version | head -1
        [[ -x "$VENV_DIR/bin/python" ]] && "$VENV_DIR/bin/python" -m pip --version
    } > "$staging/version_summary.txt"

    printf '%s\n' \
        sanitized_verify.log \
        release_summary.txt \
        platform_facts.txt \
        version_summary.txt \
        > "$staging/inventory.txt"

    if grep -RIEq '(token|password|private[_ -]?key|BEGIN [A-Z ]*PRIVATE KEY)' "$staging"; then
        print_error "The bundle safety scan found prohibited diagnostic content."
        rm -rf "$staging"
        SUPPORT_STAGING=""
        return 1
    fi

    tar -C "$staging" -czf "$bundle" .
    chmod 0600 "$bundle"
    rm -rf "$staging"
    SUPPORT_STAGING=""
    record_result pass "verify.support_bundle" \
        "Sanitized support bundle created: $bundle"
}

resolve_exit_code() {
    if [[ "$MANIFEST_FAILURE" == true ]]; then
        printf '5'
    elif [[ "$UNSUPPORTED_FAILURE" == true ]]; then
        printf '2'
    elif ((FAIL_COUNT > 0)); then
        printf '1'
    else
        printf '0'
    fi
}

print_summary() {
    local exit_code="$1" elapsed
    elapsed=$(( $(date +%s) - START_EPOCH ))
    print_header "VERIFICATION SUMMARY"
    printf 'PASS          : %s\n' "$PASS_COUNT"
    printf 'WARNING       : %s\n' "$WARNING_COUNT"
    printf 'FAIL          : %s\n' "$FAIL_COUNT"
    printf 'NOT APPLICABLE: %s\n' "$NA_COUNT"
    printf 'Script version: %s\n' "$SCRIPT_VERSION"
    printf 'Manifest      : %s\n' "${MANIFEST_RELEASE:-unavailable}"
    printf 'Elapsed time  : %s seconds\n' "$elapsed"
    printf 'Exit code     : %s\n' "$exit_code"
    printf 'Log file      : %s\n' "$LOG_FILE"

    if ((${#REMEDIATION_LINES[@]})); then
        printf '\nRecommended remediation:\n'
        local line check remediation
        for line in "${REMEDIATION_LINES[@]}"; do
            IFS='|' read -r check remediation <<<"$line"
            printf '  - %s: %s\n' "$check" "$remediation"
        done
    elif ((WARNING_COUNT > 0)); then
        printf 'Next step     : Review warnings; no required failure was detected.\n'
    else
        printf 'Next step     : No action is required.\n'
    fi
}

main() {
    parse_options "$@"

    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap cleanup EXIT

    print_header "IT 140 CODIO VIRTUAL DESKTOP VERIFICATION"
    print_info "Script version: $SCRIPT_VERSION"
    print_info "Current user  : $(id -un)"
    print_info "Purpose       : Inspect the system and user layers without changing them."
    print_info "Log file      : $LOG_FILE"
    print_notice "Verify never requests administrative privilege or repairs a failed check."

    check_platform

    if [[ ! -r "$MANIFEST_PATH" || ! -r "$SCHEMA_PATH" ]]; then
        record_result fail "verify.manifest" \
            "The controlled manifest or schema is missing." \
            "Run update_cvd.sh or contact course support."
        MANIFEST_FAILURE=true
        local exit_code
        exit_code="$(resolve_exit_code)"
        print_summary "$exit_code"
        exit "$exit_code"
    fi

    if MANIFEST_RELEASE="$(validate_manifest 2>&1)"; then
        readonly MANIFEST_RELEASE
        record_result pass "verify.manifest" \
            "Manifest release $MANIFEST_RELEASE is valid."
    else
        local validation_error="$MANIFEST_RELEASE"
        MANIFEST_RELEASE="unavailable"
        record_result fail "verify.manifest" \
            "Manifest validation failed: $validation_error" \
            "Run update_cvd.sh or contact course support."
        MANIFEST_FAILURE=true
        local exit_code
        exit_code="$(resolve_exit_code)"
        print_summary "$exit_code"
        exit "$exit_code"
    fi

    print_header "Environment Checks"
    check_disk_and_network

    print_header "System-Layer Checks"
    check_system_layer

    print_header "User-Layer Checks"
    check_user_layer

    print_header "Managed-Asset Checks"
    check_managed_assets

    create_support_bundle

    local exit_code
    exit_code="$(resolve_exit_code)"
    print_summary "$exit_code"
    exit "$exit_code"
}

main "$@"
