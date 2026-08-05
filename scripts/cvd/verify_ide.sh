#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop read-only verification script
#
# Artifact ID: IT140-CVD-VERIFY
# Artifact version: 0.7.3-alpha.1
# Version date-time group: 2026-08-05-11-39
# Development status: Alpha Testing
#
# Traceability: VER-FR-001 through VER-FR-014; PKG-FR-021;
#               VER-DES-001 through VER-DES-014; ERR-DES-014.
# Scope: Read-only inspection of the CVD system and current-user course layers.
#        The only files created are the required transcript and an explicitly
#        requested sanitized support bundle.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.7.3-alpha.1"
readonly VERSION_DTG="2026-08-05-11-39"
readonly DEVELOPMENT_STATUS="Alpha Testing"
readonly SUPPORTED_SCHEMA="2.2"
readonly PLATFORM_ID="cvd"
readonly DEPLOYMENT_PROFILE_ID="codio_cvd"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/verify_cvd_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly NUMLOCK_AUTOSTART_PATH="/etc/xdg/autostart/numlockx.desktop"
readonly EMOJI_PACKAGE="fonts-noto-color-emoji"
readonly EMOJI_FAMILY="Noto Color Emoji"
readonly MANAGED_PATH_START="# >>> IT 140 managed PATH >>>"
readonly MANAGED_PATH_END="# <<< IT 140 managed PATH <<<"
readonly MANAGED_PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/cvd:$PATH"'
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_UNSUPPORTED=2
readonly EXIT_PRIVILEGE=3
readonly EXIT_EXTERNAL=4
readonly EXIT_MANIFEST=5
readonly EXIT_CANCELED=6
readonly EXIT_PARTIAL=7
NONINTERACTIVE=false
SUPPORT_BUNDLE=false
CONFIRM_SUPPORT_BUNDLE=false
SKIP_NETWORK=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
START_EPOCH="$(date +%s)"
START_TIME="$(date --iso-8601=seconds)"
MANIFEST_RELEASE="unavailable"
MANIFEST_DTG="unavailable"
PASS_COUNT=0
WARNING_COUNT=0
FAIL_COUNT=0
NA_COUNT=0
MANIFEST_FAILURE=false
UNSUPPORTED_FAILURE=false
SUPPORT_STAGING=""
SUPPORT_BUNDLE_PATH=""
FINALIZED=false

RESULT_LINES=()
REMEDIATION_LINES=()
print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}
print_info() { printf '[INFO] %s\n' "$1"; }
print_success() { printf '[SUCCESS] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }
print_error() { printf '[ERROR] %s\n' "$1" >&2; }
usage() {
    cat <<USAGE
Usage: verify_ide.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile codio_cvd]
                     [--support-bundle] [--yes] [--skip-network]

Checks the IT 140 Codio Virtual Desktop without installing, updating, removing,
or repairing managed software and settings.
--support-bundle  Offer to create a sanitized diagnostic bundle.
--yes             Approve support-bundle creation without an additional prompt.
--skip-network    Record the optional network-service check as not applicable.

Exit codes:
  0  All required checks passed; warnings may be present
  1  One or more required checks failed
  2  Invalid use or unsupported execution context
  5  Manifest, schema, or controlled configuration invalid

Logs: ~/it140/logs/
USAGE
}
parse_options() {
    while (($#)); do
        case "$1" in
            --help|-h)
                usage
                exit "$EXIT_SUCCESS"
                ;;
            --version)
                printf '%s (%s; %s)\n' "$SCRIPT_VERSION" "$VERSION_DTG" "$DEVELOPMENT_STATUS"
                exit "$EXIT_SUCCESS"
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
                    exit "$EXIT_UNSUPPORTED"
                }
                REQUESTED_PROFILE="$1"
                ;;
            *)
                print_error "Unsupported option: $1"
                usage >&2
                exit "$EXIT_UNSUPPORTED"
                ;;
        esac
        shift
    done
}
cleanup() {
    if [[ -n "${SUPPORT_STAGING:-}" && -d "$SUPPORT_STAGING" ]]; then
        rm -rf -- "$SUPPORT_STAGING"
    fi
    SUPPORT_STAGING=""
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
            exit "$EXIT_FAILURE"
            ;;
    esac
    printf '[%s] [%s] %s\n' "$label" "$check_id" "$message"
    RESULT_LINES+=("${label}|${check_id}|${message}")
}
validate_manifest() {
    python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" \
        "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
import json
import pathlib
import sys

manifest_path, schema_path, platform_id, profile_id, supported_schema = sys.argv[1:]

class DuplicateKeyError(ValueError):
    pass

def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate key: {key}")
        result[key] = value
    return result

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
    raise SystemExit(f"controlled JSON validation failed: {exc}")
required = {
    "schema_version", "automation_release", "automation_release_date_time_group", "course",
    "control", "policy", "capabilities", "products", "software_sources", "provider_profiles",
    "platforms", "deployment_profiles", "lifecycle_workflows", "managed_settings",
    "managed_assets", "obsolete_components", "logging",
}
missing = sorted(required - manifest.keys())
if missing:
    raise SystemExit("manifest missing required keys: " + ", ".join(missing))
if manifest.get("schema_version") != supported_schema:
    raise SystemExit(
        f"unsupported manifest schema: {manifest.get('schema_version')!r}; "
        f"expected {supported_schema}"
    )
if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
    raise SystemExit("schema is not the approved Draft 2020-12 format")
if manifest.get("policy", {}).get("allow_os_release_upgrade") is not False:
    raise SystemExit("manifest attempts to allow an operating-system release upgrade")
platform = manifest["platforms"].get(platform_id)
profile = manifest["deployment_profiles"].get(profile_id)
if not platform or not platform.get("enabled"):
    raise SystemExit("CVD platform is missing or disabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("CVD deployment profile is invalid")
if "github_com" not in manifest["provider_profiles"]:
    raise SystemExit("required GitHub provider profile is unavailable")
workflow = manifest["lifecycle_workflows"].get("cvd_course_master_student")
if not workflow or workflow.get("success_transitions", {}).get("verify") != "complete":
    raise SystemExit("CVD student workflow does not terminate after Verify")
required_packages = {
    "fonts_noto_color_emoji": "fonts-noto-color-emoji",
    "numlockx": "numlockx",
    "xclip": "xclip",
}
os_packages = platform.get("os_packages", {})
missing_packages = sorted(set(required_packages) - os_packages.keys())
if missing_packages:
    raise SystemExit("CVD manifest is missing required packages: " + ", ".join(missing_packages))
for package_id, package_identifier in sorted(required_packages.items()):
    package = os_packages[package_id]
    if (not package.get("required") or
            package.get("package_identifier") != package_identifier):
        raise SystemExit(f"CVD package definition is invalid: {package_id}")
try:
    import jsonschema  # type: ignore
except ImportError:
    pass
else:
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(manifest)

version_dtg = (
    manifest.get("automation_release_date_time_group")
    or manifest.get("automation_release_date")
    or "unavailable"
)
print(f"{manifest['automation_release']}\t{version_dtg}")
PY
}
manifest_query() {
    local query="$1"
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json
import sys

path, platform_id, query = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    manifest = json.load(stream)
platform = manifest["platforms"][platform_id]
bindings = platform["course_ide_bindings"]
if query == "os_packages":
    values = []
    for package in platform.get("os_packages", {}).values():
        if package.get("required"):
            values.append(package["package_identifier"])
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "system" and
                binding.get("installer_adapter_id") == "apt_package"):
            values.append(binding["package_identifier"])
    for value in sorted(set(values)):
        print(value)
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
        if role == "code_quality_tool" and binding.get("required"):
            values.append("ruff")
    for value in sorted(set(values)):
        print(value)
elif query == "extensions":
    for role, binding in bindings.items():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "vscode_extension"):
            print(f"{role}\t{binding['package_identifier']}")
elif query == "git_settings":
    for profile_id in bindings["version_control_system"].get("settings_profile_ids", []):
        for key, value in manifest["managed_settings"][profile_id]["values"].items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            print(f"{key}\t{value}")
elif query == "vscode_settings":
    merged = {}
    for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
        merged.update(manifest["managed_settings"][profile_id]["values"])
    print(json.dumps(merged, separators=(",", ":"), sort_keys=True))
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
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
    local settings_json
    [[ -r "$settings_file" ]] || return 1
    settings_json="$(manifest_query vscode_settings)" || return 1
    IT140_SETTINGS_FILE="$settings_file" \
    IT140_SETTINGS_JSON="$settings_json" \
    IT140_VENV_PYTHON="$VENV_DIR/bin/python" \
    python3 - <<'PY'
import json
import os
from pathlib import Path
try:
    actual = json.loads(Path(os.environ["IT140_SETTINGS_FILE"]).read_text(encoding="utf-8"))
    expected = json.loads(os.environ["IT140_SETTINGS_JSON"])
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
if not isinstance(actual, dict):
    raise SystemExit(1)
expected["python.defaultInterpreterPath"] = os.environ["IT140_VENV_PYTHON"]
def contains(current, desired):
    if isinstance(desired, dict):
        return isinstance(current, dict) and all(
            key in current and contains(current[key], value)
            for key, value in desired.items()
        )
    return current == desired

if not contains(actual, expected):
    raise SystemExit(1)
PY
}

desktop_directory() {
    xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop\n' "$HOME"
}
list_vscode_launchers() {
    local desktop_dir candidate
    desktop_dir="$(desktop_directory)"
    [[ -d "$desktop_dir" ]] || return 0
    while IFS= read -r -d '' candidate; do
        if grep -Eiq '^Name=.*Visual Studio Code|^Exec=([^[:space:]]*/)?code([[:space:]]|$)' "$candidate"; then
            printf '%s\n' "$candidate"
        fi
    done < <(find "$desktop_dir" -maxdepth 1 -type f -name '*.desktop' -print0)
}
find_vscode_launcher() {
    local desktop_dir candidate
    desktop_dir="$(desktop_directory)"
    [[ -d "$desktop_dir" ]] || return 1
    for candidate in \
        "$desktop_dir/visual-studio-code.desktop" \
        "$desktop_dir/code.desktop" \
        "$desktop_dir/Visual Studio Code.desktop"; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    list_vscode_launchers | head -n 1
}
launcher_opens_course_root() {
    local launcher="$1"
    python3 - "$launcher" "$COURSE_ROOT" <<'PY'
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
course_root = sys.argv[2]
try:
    lines = path.read_text(encoding="utf-8").splitlines()
except (OSError, UnicodeError):
    raise SystemExit(1)
in_desktop = False
exec_value = None
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        in_desktop = stripped == "[Desktop Entry]"
        continue
    if in_desktop and stripped.startswith("Exec="):
        exec_value = stripped[5:]
        break
if not exec_value:
    raise SystemExit(1)
try:
    args = shlex.split(exec_value)
except ValueError:
    raise SystemExit(1)
args = [arg for arg in args if not (arg.startswith("%") and len(arg) == 2)]
if not args or pathlib.Path(args[0]).name != "code":
    raise SystemExit(1)
if course_root not in args:
    raise SystemExit(1)
PY
}
check_platform() {
    if [[ "$EUID" -eq 0 ]]; then
        UNSUPPORTED_FAILURE=true
        record_result fail "VER-CONTEXT-001" \
            "Verify must run as the standard CVD desktop user, not root." \
            "Open Terminal as the standard CVD user and run verify_ide.sh without sudo."
        return 1
    fi
    if [[ ! -r /etc/os-release ]]; then
        UNSUPPORTED_FAILURE=true
        record_result fail "VER-PLATFORM-001" \
            "The operating system could not be identified." \
            "Run Verify on the supported IT 140 CVD."
        return 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != 24.04 ]]; then
        UNSUPPORTED_FAILURE=true
        record_result fail "VER-PLATFORM-001" \
            "This is not the supported Ubuntu 24.04 CVD." \
            "Run the platform-specific Verify script for this environment."
        return 1
    fi
    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" != amd64 && "$architecture" != x86_64 ]]; then
        UNSUPPORTED_FAILURE=true
        record_result fail "VER-PLATFORM-002" \
            "The processor architecture is unsupported: $architecture." \
            "Use the supported x86_64 CVD."
        return 1
    fi
    if [[ "$REQUESTED_PROFILE" != "$DEPLOYMENT_PROFILE_ID" ]]; then
        UNSUPPORTED_FAILURE=true
        record_result fail "VER-PROFILE-001" \
            "The requested deployment profile is unsupported: $REQUESTED_PROFILE." \
            "Run Verify with deployment profile codio_cvd."
        return 1
    fi
    print_info "Platform        : $PLATFORM_ID / $DEPLOYMENT_PROFILE_ID"
    print_info "Operating system: ${PRETTY_NAME:-Ubuntu 24.04}"
    print_info "Architecture    : $architecture"
    record_result pass "VER-PLATFORM-001" "Ubuntu 24.04 x86_64 CVD execution context is supported."
}
check_manifest() {
    local info
    if ! info="$(validate_manifest 2>&1)"; then
        MANIFEST_FAILURE=true
        record_result fail "VER-MANIFEST-001" \
            "The controlled manifest or schema is invalid." \
            "Rerun prepare_ide.sh, then rerun verify_ide.sh."
        print_error "$info"
        return 1
    fi
    IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$info"
    record_result pass "VER-MANIFEST-001" \
        "Manifest release $MANIFEST_RELEASE using schema $SUPPORTED_SCHEMA is valid."
}
check_disk_space() {
    local minimum available
    minimum="$(manifest_query minimum_space)"
    available="$(df -PB1 "$HOME" | awk 'NR==2 {print $4}')"
    if ((available >= minimum)); then
        record_result pass "VER-DISK-001" "Required free disk space is available."
    else
        record_result fail "VER-DISK-001" \
            "Free disk space is below the manifest minimum." \
            "Remove unneeded files, then rerun verify_ide.sh."
    fi
}
check_system_packages() {
    local package role package_identifier executable_names executable found
    local -a packages=()
    mapfile -t packages < <(manifest_query os_packages)
    for package in "${packages[@]}"; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
                | grep -Fq 'install ok installed'; then
            record_result pass "VER-PKG-${package//[^A-Za-z0-9]/_}" \
                "Required Ubuntu package is installed: $package."
        else
            record_result fail "VER-PKG-${package//[^A-Za-z0-9]/_}" \
                "Required Ubuntu package is missing: $package." \
                "Run update_ide.sh, then rerun verify_ide.sh."
        fi
    done
    while IFS=$'\t' read -r role package_identifier executable_names; do
        [[ -n "$role" ]] || continue
        found=false
        IFS=',' read -ra executable_list <<< "$executable_names"
        for executable in "${executable_list[@]}"; do
            if command -v "$executable" >/dev/null 2>&1; then
                found=true
                break
            fi
        done
        if [[ "$found" == true ]]; then
            record_result pass "VER-CMD-${role}" \
                "Required capability command is available: $role."
        else
            record_result fail "VER-CMD-${role}" \
                "Required capability command is unavailable: $role." \
                "Run update_ide.sh, then rerun verify_ide.sh."
        fi
    done < <(manifest_query system_bindings)
}
check_emoji_font() {
    local family font_file remediation
    remediation="Run update_ide.sh, close and reopen Visual Studio Code, then rerun verify_ide.sh."

    if ! command -v fc-match >/dev/null 2>&1; then
        record_result fail "VER-CVD-EMOJI-MATCH-001" \
            "The fontconfig matching command is unavailable: fc-match." \
            "$remediation"
    else
        family="$(fc-match -f '%{family}\n' emoji 2>/dev/null || true)"
        if [[ "$family" == *"$EMOJI_FAMILY"* ]]; then
            record_result pass "VER-CVD-EMOJI-MATCH-001" \
                "fc-match emoji resolves to $EMOJI_FAMILY."
        else
            record_result fail "VER-CVD-EMOJI-MATCH-001" \
                "fc-match emoji does not resolve to $EMOJI_FAMILY; resolved family: ${family:-unavailable}." \
                "$remediation"
        fi
    fi

    if ! command -v fc-list >/dev/null 2>&1; then
        record_result fail "VER-CVD-EMOJI-FILE-001" \
            "The fontconfig listing command is unavailable: fc-list." \
            "$remediation"
    else
        font_file="$(fc-list : family file 2>/dev/null \
            | awk -F: -v family="$EMOJI_FAMILY" 'index($0, family) {print $1; exit}' || true)"
        if [[ -n "$font_file" && -r "$font_file" ]]; then
            record_result pass "VER-CVD-EMOJI-FILE-001" \
                "$EMOJI_FAMILY is discoverable through fontconfig: $font_file."
        else
            record_result fail "VER-CVD-EMOJI-FILE-001" \
                "$EMOJI_FAMILY is not discoverable through fontconfig." \
                "$remediation"
        fi
    fi
}
check_python_environment() {
    local package
    local -a packages=()
    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        record_result fail "VER-PYTHON-001" \
            "The course Python virtual environment is unavailable." \
            "Run configure_ide.sh, then rerun verify_ide.sh."
        return
    fi
    if "$VENV_DIR/bin/python" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info[:2] == (3, 12) else 1)
PY
    then
        record_result pass "VER-PYTHON-001" "The course virtual environment uses Python 3.12."
    else
        record_result fail "VER-PYTHON-001" \
            "The course virtual environment does not use Python 3.12." \
            "Run configure_ide.sh, then rerun verify_ide.sh."
    fi
    mapfile -t packages < <(manifest_query venv_packages)
    for package in "${packages[@]}"; do
        if "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
            record_result pass "VER-PYTHON-${package//[^A-Za-z0-9]/_}" \
                "Required Python package is installed: $package."
        else
            record_result fail "VER-PYTHON-${package//[^A-Za-z0-9]/_}" \
                "Required Python package is missing: $package." \
                "Run configure_ide.sh, then rerun verify_ide.sh."
        fi
    done
}
check_vscode_extensions() {
    local role extension installed_extensions
    if ! command -v code >/dev/null 2>&1; then
        record_result fail "VER-VSCODE-001" \
            "Visual Studio Code is unavailable." \
            "Run update_ide.sh, then rerun verify_ide.sh."
        return
    fi
    installed_extensions="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    while IFS=$'\t' read -r role extension; do
        [[ -n "$role" ]] || continue
        if grep -Fqx "${extension,,}" <<< "$installed_extensions"; then
            record_result pass "VER-EXT-${role}" \
                "Required VS Code extension is installed: $extension."
        else
            record_result fail "VER-EXT-${role}" \
                "Required VS Code extension is missing: $extension." \
                "Run configure_ide.sh, then rerun verify_ide.sh."
        fi
    done < <(manifest_query extensions)
}
check_provider_and_git() {
    local key expected actual email
    if gh auth status --hostname github.com >/dev/null 2>&1; then
        record_result pass "VER-GITHUB-001" "GitHub CLI is authenticated."
    else
        record_result fail "VER-GITHUB-001" \
            "GitHub CLI is not authenticated." \
            "Run configure_ide.sh and complete the browser authentication step."
    fi
    if [[ -n "$(git config --global --get user.name 2>/dev/null || true)" ]]; then
        record_result pass "VER-GIT-IDENTITY-001" "Git commit display name is configured."
    else
        record_result fail "VER-GIT-IDENTITY-001" \
            "Git commit display name is not configured." \
            "Run configure_ide.sh, then rerun verify_ide.sh."
    fi
    email="$(git config --global --get user.email 2>/dev/null || true)"
    if [[ "$email" == *@users.noreply.github.com ]]; then
        record_result pass "VER-GIT-IDENTITY-002" \
            "Git uses the approved private provider email format."
    else
        record_result fail "VER-GIT-IDENTITY-002" \
            "Git does not use the approved private provider email format." \
            "Run configure_ide.sh, then rerun verify_ide.sh."
    fi
    while IFS=$'\t' read -r key expected; do
        [[ -n "$key" ]] || continue
        actual="$(git config --global --get "$key" 2>/dev/null || true)"
        if [[ "$actual" == "$expected" ]]; then
            record_result pass "VER-GIT-${key//[^A-Za-z0-9]/_}" \
                "Managed Git setting is correct: $key."
        else
            record_result fail "VER-GIT-${key//[^A-Za-z0-9]/_}" \
                "Managed Git setting is incorrect: $key." \
                "Run configure_ide.sh, then rerun verify_ide.sh."
        fi
    done < <(manifest_query git_settings)
}
check_paths_and_settings() {
    if has_managed_path_block "$HOME/.bashrc"; then
        record_result pass "VER-PATH-001" "The managed PATH block is present in ~/.bashrc."
    else
        record_result fail "VER-PATH-001" \
            "The managed PATH block is missing or incorrect in ~/.bashrc." \
            "Run configure_ide.sh, then open a fresh Terminal."
    fi
    if has_managed_path_block "$HOME/.profile"; then
        record_result pass "VER-PATH-002" "The managed PATH block is present in ~/.profile."
    else
        record_result fail "VER-PATH-002" \
            "The managed PATH block is missing or incorrect in ~/.profile." \
            "Run configure_ide.sh, then open a fresh Terminal."
    fi
    if has_valid_vscode_settings; then
        record_result pass "VER-VSCODE-SETTINGS-001" \
            "Required VS Code settings are present without requiring unrelated settings to match."
    else
        record_result fail "VER-VSCODE-SETTINGS-001" \
            "Required VS Code settings are missing or invalid." \
            "Run configure_ide.sh, then rerun verify_ide.sh."
    fi
}
check_numlock_integration() {
    if command -v xclip >/dev/null 2>&1; then
        record_result pass "VER-CVD-XCLIP-001" "The CVD clipboard command is available: xclip."
    else
        record_result fail "VER-CVD-XCLIP-001" \
            "The required CVD clipboard command is unavailable: xclip." \
            "Run update_ide.sh, then rerun verify_ide.sh."
    fi
    if command -v numlockx >/dev/null 2>&1; then
        record_result pass "VER-CVD-NUMLOCK-001" "The CVD Num Lock command is available: numlockx."
    else
        record_result fail "VER-CVD-NUMLOCK-001" \
            "The required CVD Num Lock command is unavailable: numlockx." \
            "Run update_ide.sh, then rerun verify_ide.sh."
    fi
    if [[ ! -r "$NUMLOCK_AUTOSTART_PATH" ]]; then
        record_result fail "VER-CVD-NUMLOCK-STARTUP-001" \
            "The Xfce Num Lock desktop-startup entry is missing." \
            "Run update_ide.sh, then rerun verify_ide.sh."
        return
    fi
    if ! grep -Fqx 'Exec=/usr/bin/numlockx on' "$NUMLOCK_AUTOSTART_PATH"; then
        record_result fail "VER-CVD-NUMLOCK-STARTUP-001" \
            "The Xfce Num Lock desktop-startup command is incorrect." \
            "Run update_ide.sh, then rerun verify_ide.sh."
        return
    fi
    if ! grep -Fqx 'OnlyShowIn=XFCE;' "$NUMLOCK_AUTOSTART_PATH"; then
        record_result fail "VER-CVD-NUMLOCK-STARTUP-001" \
            "The Num Lock desktop-startup entry is not restricted to Xfce." \
            "Run update_ide.sh, then rerun verify_ide.sh."
        return
    fi
    if command -v desktop-file-validate >/dev/null 2>&1 && \
            ! desktop-file-validate "$NUMLOCK_AUTOSTART_PATH" >/dev/null 2>&1; then
        record_result fail "VER-CVD-NUMLOCK-STARTUP-001" \
            "The Num Lock desktop-startup entry is invalid." \
            "Run update_ide.sh, then rerun verify_ide.sh."
        return
    fi
    record_result pass "VER-CVD-NUMLOCK-STARTUP-001" \
        "Num Lock is configured to turn on when the CVD Xfce desktop session starts."
}
check_desktop_integrations() {
    local launcher launcher_count

    check_numlock_integration
    launcher="$(find_vscode_launcher 2>/dev/null || true)"
    if [[ -z "$launcher" ]]; then
        record_result fail "VER-LAUNCHER-001" \
            "The existing Visual Studio Code desktop launcher was not found." \
            "Run configure_ide.sh; it will repair the existing launcher without creating a duplicate."
    elif [[ ! -x "$launcher" ]]; then
        record_result fail "VER-LAUNCHER-001" \
            "The Visual Studio Code desktop launcher is not executable." \
            "Run configure_ide.sh, then rerun verify_ide.sh."
    elif ! launcher_opens_course_root "$launcher"; then
        record_result fail "VER-LAUNCHER-001" \
            "The Visual Studio Code desktop launcher does not open $COURSE_ROOT as a folder argument." \
            "Run configure_ide.sh, then rerun verify_ide.sh."
    elif command -v desktop-file-validate >/dev/null 2>&1 && \
            ! desktop-file-validate "$launcher" >/dev/null 2>&1; then
        record_result fail "VER-LAUNCHER-001" \
            "The repaired Visual Studio Code launcher is not a valid desktop entry." \
            "Run configure_ide.sh, then rerun verify_ide.sh."
    else
        record_result pass "VER-LAUNCHER-001" \
            "The existing Visual Studio Code launcher opens $COURSE_ROOT."
    fi
    launcher_count="$(list_vscode_launchers | sed '/^$/d' | wc -l | tr -d ' ')"
    if ((launcher_count > 1)); then
        record_result warning "VER-LAUNCHER-002" \
            "More than one Visual Studio Code desktop launcher is present; Configure did not create another launcher."
    else
        record_result pass "VER-LAUNCHER-002" \
            "No duplicate Visual Studio Code desktop launcher was detected."
    fi
}
check_restart_state() {
    if [[ -e /var/run/reboot-required ]]; then
        record_result fail "VER-RESTART-001" \
            "Ubuntu still requires a CVD restart." \
            "Save your work, restart the CVD, and rerun verify_ide.sh."
    else
        record_result pass "VER-RESTART-001" "No pending Ubuntu restart is reported."
    fi
}
check_network_service() {
    if [[ "$SKIP_NETWORK" == true ]]; then
        record_result not_applicable "VER-NETWORK-001" \
            "Optional GitHub service reachability check was skipped."
        return
    fi
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        record_result not_applicable "VER-NETWORK-001" \
            "GitHub service reachability was not tested because authentication is incomplete."
        return
    fi
    if timeout 30 gh api rate_limit --silent >/dev/null 2>&1; then
        record_result pass "VER-NETWORK-001" "The authenticated GitHub service is reachable."
    else
        record_result warning "VER-NETWORK-001" \
            "GitHub could not be reached during the bounded optional check."
    fi
}
check_log_directory() {
    local probe
    probe="$LOG_DIR/.verify-write-test.$$"
    if : > "$probe" 2>/dev/null; then
        rm -f -- "$probe"
        record_result pass "VER-LOG-001" "The private log directory is writable."
    else
        record_result fail "VER-LOG-001" \
            "The log directory is not writable." \
            "Repair ownership and permissions for ~/it140/logs, then rerun Verify."
    fi
}
sanitize_log() {
    local source="$1"
    local destination="$2"
    sed -E \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
        -e 's/(token|oauth_token|access_token|refresh_token)[=:][^[:space:]]+/\1=[REDACTED]/Ig' \
        "$source" > "$destination"
}

maybe_create_support_bundle() {
    [[ "$SUPPORT_BUNDLE" == true ]] || return 0
    local approved=false response bundle_name report_file facts_file
    if [[ "$CONFIRM_SUPPORT_BUNDLE" == true ]]; then
        approved=true
    elif [[ "$NONINTERACTIVE" == true ]]; then
        print_notice "Support-bundle creation was requested but not confirmed; use --yes to approve it."
        return 0
    else
        print_notice "The support bundle will contain only the sanitized current log, verification totals, manifest release, platform facts, and script versions."
        printf 'Create this bundle? [y/N]: '
        IFS= read -r response
        [[ "${response,,}" == y || "${response,,}" == yes ]] && approved=true
    fi
    [[ "$approved" == true ]] || {
        print_notice "Support-bundle creation was canceled."
        return 0
    }

    SUPPORT_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/it140-support.XXXXXXXX")"
    chmod 0700 "$SUPPORT_STAGING"
    sanitize_log "$LOG_FILE" "$SUPPORT_STAGING/verify_ide_sanitized.log"
    report_file="$SUPPORT_STAGING/verification_summary.txt"
    facts_file="$SUPPORT_STAGING/platform_facts.txt"
    {
        printf 'IT 140 CVD verification support summary\n'
        printf 'Script version: %s\n' "$SCRIPT_VERSION"
        printf 'Version DTG: %s\n' "$VERSION_DTG"
        printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
        printf 'Manifest DTG: %s\n' "$MANIFEST_DTG"
        printf 'Passed: %s\nWarnings: %s\nFailed: %s\nNot applicable: %s\n' \
            "$PASS_COUNT" "$WARNING_COUNT" "$FAIL_COUNT" "$NA_COUNT"
    } > "$report_file"
    {
        printf 'uname: %s\n' "$(uname -srm)"
        if [[ -r /etc/os-release ]]; then
            grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release
        fi
    } > "$facts_file"
    bundle_name="it140_cvd_support_$(date +%Y%m%d_%H%M%S).tar.gz"
    SUPPORT_BUNDLE_PATH="$LOG_DIR/$bundle_name"
    tar -czf "$SUPPORT_BUNDLE_PATH" -C "$SUPPORT_STAGING" .
    chmod 0600 "$SUPPORT_BUNDLE_PATH"
    print_success "Sanitized support bundle created: $SUPPORT_BUNDLE_PATH"
}

finish() {
    local exit_code result elapsed
    [[ "$FINALIZED" == false ]] || return 0
    FINALIZED=true
    if [[ "$MANIFEST_FAILURE" == true ]]; then
        exit_code="$EXIT_MANIFEST"
    elif [[ "$UNSUPPORTED_FAILURE" == true ]]; then
        exit_code="$EXIT_UNSUPPORTED"
    elif ((FAIL_COUNT > 0)); then
        exit_code="$EXIT_FAILURE"
    else
        exit_code="$EXIT_SUCCESS"
    fi
    ((exit_code == 0)) && result="COMPLIANT" || result="NOT COMPLIANT"
    elapsed=$(( $(date +%s) - START_EPOCH ))
    print_header "VERIFICATION SUMMARY"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Version DTG     : %s\n' "$VERSION_DTG"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'Manifest DTG    : %s\n' "$MANIFEST_DTG"
    printf 'Passed          : %s\n' "$PASS_COUNT"
    printf 'Warnings        : %s\n' "$WARNING_COUNT"
    printf 'Failed          : %s\n' "$FAIL_COUNT"
    printf 'Not applicable  : %s\n' "$NA_COUNT"
    printf 'Start time      : %s\n' "$START_TIME"
    printf 'End time        : %s\n' "$(date --iso-8601=seconds)"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Log file        : %s\n' "$LOG_FILE"
    [[ -n "$SUPPORT_BUNDLE_PATH" ]] && printf 'Support bundle  : %s\n' "$SUPPORT_BUNDLE_PATH"
    printf 'Exit code       : %s\n' "$exit_code"
    if ((${#REMEDIATION_LINES[@]} > 0)); then
        printf '\nRemediation:\n'
        local remediation
        for remediation in "${REMEDIATION_LINES[@]}"; do
            printf '  - %s\n' "$remediation"
        done
    fi
    if ((exit_code == 0)); then
        print_notice "No required remediation is needed."
    else
        print_notice "This issue affects the Codio Virtual Desktop (CVD)."
        print_notice "If remediation does not resolve it, contact course support and include the log file."
    fi
    print_notice "Review the summary and log before closing this Terminal."
    cleanup
    return "$exit_code"
}
on_error() {
    local status=$?
    local line=${BASH_LINENO[0]:-unknown}
    trap - ERR
    record_result fail "VER-INTERNAL-001" \
        "Verification stopped unexpectedly near line $line with status $status." \
        "Rerun verify_ide.sh; if it fails again, provide the log to course support."
    finish
    exit $?
}
on_interrupt() {
    trap - INT TERM
    record_result fail "VER-INTERRUPT-001" \
        "Verification was interrupted before all checks completed." \
        "Rerun verify_ide.sh."
    finish
    exit $?
}

main() {
    parse_options "$@"

    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    touch "$LOG_FILE"
    chmod 0600 "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap on_error ERR
    trap on_interrupt INT TERM
    trap cleanup EXIT
    print_header "IT 140 CODIO VIRTUAL DESKTOP VERIFY"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Version DTG    : $VERSION_DTG"
    print_info "Status         : $DEVELOPMENT_STATUS"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Inspect the system and user course environment without repairing it."
    print_info "Log file       : $LOG_FILE"
    if ! check_platform; then
        maybe_create_support_bundle
        trap - ERR INT TERM
        finish
        exit $?
    fi
    if ! check_manifest; then
        maybe_create_support_bundle
        trap - ERR INT TERM
        finish
        exit $?
    fi
    check_disk_space
    check_system_packages
    check_emoji_font
    check_python_environment
    check_vscode_extensions
    check_provider_and_git
    check_paths_and_settings
    check_desktop_integrations
    check_restart_state
    check_network_service
    check_log_directory
    maybe_create_support_bundle

    trap - ERR INT TERM
    finish
    exit $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
