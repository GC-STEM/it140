#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop managed update and repair script
#
# Artifact ID: IT140-CVD-UPDATE
# Artifact version: 1.0.2
# Version date-time group: 2026-08-30-12-56
# Development status: Pilot — Active Development
#
# Traceability: UPD-FR-001 through UPD-FR-016; PKG-FR-021;
#               UPD-DES-001 through UPD-DES-016; ERR-DES-014.
# Scope: Approved Ubuntu maintenance, controlled manifest refresh, required
#        course software, Python virtual-environment tools, VS Code extensions,
#        system integrations, and post-update checks. The script never upgrades
#        Ubuntu to a new release and never modifies coursework or repositories.
#
# User-data boundary: Update may inspect the shallow state of ~/Repos and
# course-managed desktop integrations only to choose the correct next lifecycle
# step. It never modifies ~/Repos or any repository stored inside it.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="1.0.2"
readonly VERSION_DTG="2026-08-30-12-56"
readonly DEVELOPMENT_STATUS="Pilot — Active Development"
readonly SUPPORTED_SCHEMA="2.2"
readonly PLATFORM_ID="cvd"
readonly DEPLOYMENT_PROFILE_ID="codio_cvd"
readonly COURSE_ROOT="${HOME}/it140"
readonly REPOS_ROOT="${HOME}/Repos"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly MANIFEST_DIR="${SCRIPT_ROOT}/.manifest"
readonly MANIFEST_PATH="${MANIFEST_DIR}/it140_manifest.json"
readonly SCHEMA_PATH="${MANIFEST_DIR}/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/update_cvd_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly LOCK_FILE="${HOME}/.cache/it140-${PLATFORM_ID}-mutation.lock"
readonly ARCHIVE_URL="https://github.com/GC-STEM/it140/archive/refs/heads/main.tar.gz"
# Test-only isolation root. It is honored only when explicit lifecycle test
# mode is enabled; normal course execution always resolves production paths.
readonly UPDATE_TEST_MODE="${IT140_UPDATE_TEST_MODE:-false}"
if [[ "$UPDATE_TEST_MODE" == true ]]; then
    readonly UPDATE_TEST_ROOT="${IT140_UPDATE_TEST_ROOT:-}"
else
    readonly UPDATE_TEST_ROOT=""
fi
readonly OS_RELEASE_PATH="${UPDATE_TEST_ROOT}/etc/os-release"
readonly NUMLOCK_AUTOSTART_PATH="${UPDATE_TEST_ROOT}/etc/xdg/autostart/numlockx.desktop"
readonly REBOOT_REQUIRED_PATH="${UPDATE_TEST_ROOT}/var/run/reboot-required"
readonly EMOJI_PACKAGE="fonts-noto-color-emoji"
readonly EMOJI_FAMILY="Noto Color Emoji"
readonly MANAGED_PATH_START="# >>> IT 140 managed PATH >>>"
readonly MANAGED_PATH_END="# <<< IT 140 managed PATH <<<"
readonly MANAGED_PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/cvd:$PATH"'
readonly -a CVD_BASELINE_DESKTOP_LAUNCHERS=("it140.desktop" "GitHub Login.desktop" "OneDrive Login.desktop")
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_UNSUPPORTED=2
readonly EXIT_PRIVILEGE=3
readonly EXIT_EXTERNAL=4
readonly EXIT_MANIFEST=5
readonly EXIT_CANCELED=6
readonly EXIT_PARTIAL=7
NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
PARTIAL=false
RESTART_REQUIRED=false
USER_CONFIGURATION_COMPLETE=false
WARNINGS=0
FAILURES=0
START_EPOCH="$(date +%s)"
START_TIME="$(date --iso-8601=seconds)"
CURRENT_STAGE="initialization"
STAGING_ROOT=""
MANIFEST_RELEASE="unavailable"
MANIFEST_DTG="unavailable"
FINALIZED=false
print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}
print_info() { printf '[INFO] %s\n' "$1"; }
print_success() { printf '[SUCCESS] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }
print_warning() { printf '[WARNING] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
print_error() { printf '[ERROR] %s\n' "$1" >&2; }
usage() {
    cat <<USAGE
Usage: update_it140.sh [--help] [--version] [--noninteractive]
                       [--deployment-profile codio_cvd]

Maintains the approved IT 140 Codio Virtual Desktop on Ubuntu 24.04. Run as
its standard desktop user, not with sudo. A successful update may require a
CVD restart before another lifecycle script is run.
Exit codes:
  0  Completed successfully, including when a restart is required
  1  Required operation failed
  2  Invalid use or unsupported execution context
  3  Required privilege unavailable
  4  Required external source or service unavailable
  5  Manifest, schema, or controlled configuration invalid
  6  User canceled before a managed change
  7  Update completed partially or was interrupted after managed changes

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
    if [[ -n "${STAGING_ROOT:-}" && -d "$STAGING_ROOT" ]]; then
        rm -rf -- "$STAGING_ROOT"
    fi
    STAGING_ROOT=""
}
resolve_failure_code() {
    local requested="$1"
    case "$requested" in
        "$EXIT_MANIFEST"|"$EXIT_UNSUPPORTED"|"$EXIT_PRIVILEGE"|"$EXIT_EXTERNAL"|"$EXIT_PARTIAL")
            printf '%s\n' "$requested"
            ;;
        "$EXIT_CANCELED")
            [[ "$CHANGED" == true ]] && printf '%s\n' "$EXIT_PARTIAL" || printf '%s\n' "$EXIT_CANCELED"
            ;;
        *)
            [[ "$CHANGED" == true ]] && printf '%s\n' "$EXIT_PARTIAL" || printf '%s\n' "$EXIT_FAILURE"
            ;;
    esac
}
course_continuity_guidance() {
    print_notice "This issue affects the Codio Virtual Desktop (CVD)."
    print_notice "If this is the first failed Update, rerun update_it140.sh once."
    print_notice "If Update has failed twice consecutively, stop retrying it and contact course support."
    print_notice "Include this log file with the support request: $LOG_FILE"
    print_notice "Do not use manual sudo, APT, or file-repair commands unless course support directs you to do so."
}
summary_action() {
    local exit_code="$1"
    if ((exit_code == EXIT_CANCELED)); then
        printf 'RUN UPDATE WHEN READY'
    elif ((exit_code != 0)); then
        printf 'RETRY UPDATE ONCE'
    elif [[ "$RESTART_REQUIRED" == true ]]; then
        printf 'RESTART VM'
    else
        printf 'None'
    fi
}
summary_guidance() {
    local exit_code="$1"
    if ((exit_code == EXIT_CANCELED)); then
        printf 'Rerun update_it140.sh when you are ready.'
    elif ((exit_code != 0)); then
        printf 'Rerun update_it140.sh once. If this was already the rerun, stop and contact course support.'
    elif [[ "$RESTART_REQUIRED" == true ]]; then
        printf 'After the VM restarts, open Terminal and run configure_it140.sh.'
    elif [[ "$USER_CONFIGURATION_COMPLETE" == true ]]; then
        printf 'Open a fresh Terminal and run verify_it140.sh.'
    else
        printf 'Open a fresh Terminal and run configure_it140.sh.'
    fi
}
finish() {
    local requested_code="${1:-0}"
    local message="${2:-}"
    local exit_code result elapsed next_step action header_title
    [[ "$FINALIZED" == false ]] || return "$requested_code"
    FINALIZED=true
    cleanup
    if [[ "$PARTIAL" == true && "$requested_code" -eq 0 ]]; then
        requested_code="$EXIT_PARTIAL"
    fi
    if ((requested_code == 0)); then
        exit_code=0
    else
        exit_code="$(resolve_failure_code "$requested_code")"
    fi
    if ((exit_code == 0)); then
        result="PASS"
    elif ((exit_code == EXIT_PARTIAL)); then
        result="PARTIAL"
    elif ((exit_code == EXIT_CANCELED)); then
        result="CANCELED"
    else
        result="FAIL"
    fi
    elapsed=$(( $(date +%s) - START_EPOCH ))
    next_step="$(summary_guidance "$exit_code")"
    action="$(summary_action "$exit_code")"
    if ((exit_code == 0)) && [[ "$RESTART_REQUIRED" == true ]]; then
        header_title="UPDATE COMPLETE — RESTART REQUIRED"
    elif ((exit_code == 0)); then
        header_title="UPDATE COMPLETE"
    else
        header_title="UPDATE SUMMARY"
    fi
    print_header "$header_title"
    printf 'Result          : %s\n' "$result"
    printf 'Action required : %s\n' "$action"
    printf 'Next step       : %s\n' "$next_step"
    printf '\n------------------------------------------------------------\n'
    printf 'SUPPORT DETAILS\n'
    printf '%s\n' '------------------------------------------------------------'
    [[ -n "$message" ]] && printf 'Conclusion      : %s\n' "$message"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Version DTG     : %s\n' "$VERSION_DTG"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'Manifest DTG    : %s\n' "$MANIFEST_DTG"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Failures        : %s\n' "$FAILURES"
    printf 'Restart required: %s\n' "$( [[ "$RESTART_REQUIRED" == true ]] && printf 'Yes' || printf 'No' )"
    printf 'Start time      : %s\n' "$START_TIME"
    printf 'End time        : %s\n' "$(date --iso-8601=seconds)"
    printf 'Managed changes : %s\n' "$( [[ "$CHANGED" == true ]] && printf 'Yes' || printf 'No' )"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : %s\n' "$exit_code"
    if ((exit_code == 0)); then
        print_success "The IT 140 CVD update completed successfully."
        if [[ "$RESTART_REQUIRED" == true ]]; then
            print_notice "[ACTION] Save your work and click RESTART VM."
        fi
        print_notice "[NEXT] $next_step"
    elif ((exit_code == EXIT_CANCELED)); then
        print_notice "[CANCELED] Update stopped before managed changes were made."
        print_notice "[NEXT] Rerun update_it140.sh when you are ready."
    else
        [[ "$exit_code" -eq "$EXIT_PARTIAL" ]] && print_notice "[PARTIAL] Update did not finish all required operations."
        course_continuity_guidance
    fi
    print_notice "Review the support details and log before closing this Terminal."
    return "$exit_code"
}
fatal() {
    local requested_code="$1"
    shift
    local exit_code=0
    FAILURES=$((FAILURES + 1))
    print_error "$*"
    print_error "Failed stage: $CURRENT_STAGE"
    finish "$requested_code" "$*" || exit_code=$?
    exit "$exit_code"
}

on_error() {
    local status=$?
    local line=${BASH_LINENO[0]:-unknown}
    local exit_code=0
    trap - ERR
    FAILURES=$((FAILURES + 1))
    print_error "Update stopped near line ${line} during ${CURRENT_STAGE} (status ${status})."
    finish "$EXIT_FAILURE" "An unexpected command failure stopped Update." || exit_code=$?
    exit "$exit_code"
}
on_interrupt() {
    local exit_code=0
    trap - INT TERM
    print_error "Update was interrupted during ${CURRENT_STAGE}."
    finish "$EXIT_CANCELED" "Update was interrupted; rerun it to recover." || exit_code=$?
    exit "$exit_code"
}

validate_manifest_pair() {
    local manifest="$1"
    local schema="$2"
    python3 - "$manifest" "$schema" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
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
    "control", "policy", "capabilities", "products", "software_sources", "platforms",
    "deployment_profiles", "lifecycle_workflows", "managed_settings",
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
required_workflows = {
    "cvd_provider_baseline_administrator",
    "cvd_course_master_student",
    "cvd_periodic_maintenance",
}
allowed = set(profile.get("allowed_workflow_ids", []))
if not required_workflows <= allowed:
    raise SystemExit("CVD deployment profile does not allow every required CVD workflow")
for workflow_id in required_workflows:
    workflow = manifest["lifecycle_workflows"].get(workflow_id)
    if not workflow or profile_id not in workflow.get("deployment_profile_ids", []):
        raise SystemExit(f"invalid CVD workflow binding: {workflow_id}")
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
if query == "system_packages":
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
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "vscode_extension"):
            print(binding["package_identifier"])
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
elif query == "retry_profile":
    profile_id = manifest["policy"]["default_retry_profile_id"]
    profile = manifest["policy"]["retry_profiles"][profile_id]
    print("\t".join(str(profile[key]) for key in (
        "maximum_attempts", "initial_delay_seconds", "backoff_multiplier",
        "maximum_delay_seconds",
    )))
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}
retry_operation() {
    local description="$1"
    shift
    local retry_data attempts delay multiplier maximum_delay attempt
    retry_data="$(manifest_query retry_profile 2>/dev/null || printf '5\t5\t2\t60')"
    IFS=$'\t' read -r attempts delay multiplier maximum_delay <<< "$retry_data"
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if "$@"; then
            return 0
        fi
        if ((attempt == attempts)); then
            print_error "$description failed after $attempts attempts."
            return 1
        fi
        print_warning "$description failed on attempt $attempt of $attempts; retrying in $delay seconds." >&2
        sleep "$delay"
        delay=$((delay * multiplier))
        ((delay > maximum_delay)) && delay="$maximum_delay"
    done
}
check_platform_and_user() {
    CURRENT_STAGE="execution-context validation"
    local effective_euid="$EUID"
    if [[ "$UPDATE_TEST_MODE" == true && -n "${IT140_UPDATE_TEST_EUID:-}" ]]; then
        effective_euid="$IT140_UPDATE_TEST_EUID"
    fi
    if [[ "$effective_euid" -eq 0 ]]; then
        fatal "$EXIT_UNSUPPORTED" "Do not run update_it140.sh with sudo; use the standard CVD desktop account."
    fi
    [[ -r "$OS_RELEASE_PATH" ]] || fatal "$EXIT_UNSUPPORTED" "Cannot identify the operating system."
    # shellcheck disable=SC1090
    source "$OS_RELEASE_PATH"
    if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != 24.04 ]]; then
        fatal "$EXIT_UNSUPPORTED" "This script supports only the IT 140 Ubuntu 24.04 CVD; detected ${PRETTY_NAME:-unknown}."
    fi
    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" != amd64 && "$architecture" != x86_64 ]]; then
        fatal "$EXIT_UNSUPPORTED" "This CVD implementation supports only x86_64; detected $architecture."
    fi
    [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] \
        || fatal "$EXIT_UNSUPPORTED" "Unsupported deployment profile: $REQUESTED_PROFILE"
    command -v sudo >/dev/null 2>&1 \
        || fatal "$EXIT_PRIVILEGE" "The sudo command is unavailable."
    sudo -n true >/dev/null 2>&1 \
        || fatal "$EXIT_PRIVILEGE" "The current account lacks required passwordless sudo access."
    print_info "Platform        : $PLATFORM_ID / $DEPLOYMENT_PROFILE_ID"
    print_info "Operating system: ${PRETTY_NAME:-Ubuntu 24.04}"
    print_info "Architecture    : $architecture"
}
acquire_lock() {
    CURRENT_STAGE="mutation-lock acquisition"
    command -v flock >/dev/null 2>&1 || {
        print_warning "flock is unavailable; concurrent lifecycle-script protection cannot be enforced."
        return 0
    }
    mkdir -p -- "$(dirname "$LOCK_FILE")"
    chmod -- 0700 "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock --nonblock 9 || fatal "$EXIT_FAILURE" "Another IT 140 setup script is currently running. Return to the other Terminal and let it finish before starting another setup script."
}
check_prerequisites() {
    CURRENT_STAGE="prerequisite validation"
    local minimum available command_name
    minimum="$(manifest_query minimum_space)" \
        || fatal "$EXIT_MANIFEST" "The minimum-space policy could not be read from the manifest."
    available="$(df -PB1 "$HOME" | awk 'NR==2 {print $4}')"
    ((available >= minimum)) \
        || fatal "$EXIT_FAILURE" "At least $((minimum / 1024 / 1024 / 1024)) GB of free space is required."
    for command_name in curl tar python3 apt-get; do
        command -v "$command_name" >/dev/null 2>&1 \
            || fatal "$EXIT_FAILURE" "Required command is unavailable: $command_name"
    done
    if pgrep -u "$(id -un)" -x code >/dev/null 2>&1; then
        print_notice "Visual Studio Code is open. Close and reopen it after Update."
    fi
}
refresh_controlled_manifest_assets() {
    CURRENT_STAGE="controlled manifest refresh"
    local archive_path stage_dir source_root candidate_manifest candidate_schema candidate_info validated obsolete
    STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/it140-update.XXXXXXXX")"
    chmod 0700 "$STAGING_ROOT"
    archive_path="$STAGING_ROOT/it140-main.tar.gz"
    stage_dir="$STAGING_ROOT/stage"
    mkdir -p "$stage_dir"
    print_info "Downloading the current controlled manifest assets."
    retry_operation "Repository archive download" \
        curl --fail --location --show-error --silent \
            --connect-timeout 20 --max-time 180 \
            --output "$archive_path" "$ARCHIVE_URL" \
        || fatal "$EXIT_EXTERNAL" "The repository archive could not be downloaded."
    tar -xzf "$archive_path" -C "$stage_dir" \
        || fatal "$EXIT_EXTERNAL" "The downloaded repository archive could not be extracted."
    source_root="$(find "$stage_dir" -mindepth 1 -maxdepth 1 -type d -name 'it140-*' -print -quit)"
    [[ -n "$source_root" ]] \
        || fatal "$EXIT_MANIFEST" "The repository archive does not contain the expected root directory."
    candidate_manifest="$source_root/scripts/.manifest/it140_manifest.json"
    candidate_schema="$source_root/scripts/.manifest/it140_manifest.schema.json"
    candidate_info="$(validate_manifest_pair "$candidate_manifest" "$candidate_schema")" \
        || fatal "$EXIT_MANIFEST" "The downloaded manifest and schema failed validation."
    print_info "Downloaded controlled pair validated: ${candidate_info%%$'\t'*}."
    mkdir -p "$MANIFEST_DIR"
    if ! cmp -s "$candidate_manifest" "$MANIFEST_PATH"; then
        install -m 0600 "$candidate_manifest" "$MANIFEST_PATH.new"
        mv -f "$MANIFEST_PATH.new" "$MANIFEST_PATH"
        CHANGED=true
        print_success "The controlled manifest was refreshed atomically."
    else
        print_info "The controlled manifest is already current."
    fi
    if ! cmp -s "$candidate_schema" "$SCHEMA_PATH"; then
        install -m 0600 "$candidate_schema" "$SCHEMA_PATH.new"
        mv -f "$SCHEMA_PATH.new" "$SCHEMA_PATH"
        CHANGED=true
        print_success "The manifest schema was refreshed atomically."
    else
        print_info "The manifest schema is already current."
    fi
    validated="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH")" \
        || fatal "$EXIT_MANIFEST" "The activated manifest pair failed validation."
    IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$validated"
    for obsolete in "$COURSE_ROOT/it140_manifest.json" "$COURSE_ROOT/it140_manifest.schema.json"; do
        if [[ -e "$obsolete" ]]; then
            rm -f -- "$obsolete"
            CHANGED=true
            print_success "Removed obsolete root-level duplicate: $obsolete"
        fi
    done
}
package_version() {
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

emoji_font_resolves() {
    local family
    command -v fc-match >/dev/null 2>&1 || return 1
    family="$(fc-match -f '%{family}\n' emoji 2>/dev/null || true)"
    [[ "$family" == *"$EMOJI_FAMILY"* ]]
}

emoji_font_file() {
    command -v fc-list >/dev/null 2>&1 || return 1
    fc-list : family file 2>/dev/null \
        | awk -F: -v family="$EMOJI_FAMILY" 'index($0, family) {print $1; exit}'
}
emoji_font_file_discoverable() {
    local font_file
    font_file="$(emoji_font_file || true)"
    [[ -n "$font_file" && -r "$font_file" ]]
}
rebuild_font_cache() {
    CURRENT_STAGE="font-cache maintenance"
    command -v fc-cache >/dev/null 2>&1 \
        || fatal "$EXIT_FAILURE" "The fontconfig cache command is unavailable."
    print_info "Rebuilding the system font cache for graphical applications."
    sudo fc-cache -f >/dev/null \
        || fatal "$EXIT_FAILURE" "The system font cache could not be rebuilt."
    CHANGED=true
    print_success "The system font cache was rebuilt."
}
update_system_packages() {
    CURRENT_STAGE="Ubuntu package maintenance"
    local emoji_before_version emoji_after_version
    local emoji_before_healthy=false
    local -a packages=()
    mapfile -t packages < <(manifest_query system_packages)
    ((${#packages[@]} > 0)) \
        || fatal "$EXIT_MANIFEST" "The manifest declares no required CVD system packages."
    emoji_before_version="$(package_version "$EMOJI_PACKAGE")"
    if emoji_font_resolves && emoji_font_file_discoverable; then
        emoji_before_healthy=true
    fi
    print_info "Refreshing Ubuntu package information."
    retry_operation "Ubuntu package-index refresh" \
        sudo apt-get -o Acquire::Retries=3 update \
        || fatal "$EXIT_EXTERNAL" "Ubuntu package information could not be refreshed."
    print_info "Applying supported Ubuntu 24.04 package updates without a release upgrade."
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get \
        -o Acquire::Retries=3 \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        -y full-upgrade; then
        fatal "$EXIT_EXTERNAL" "Ubuntu package maintenance did not complete."
    fi
    CHANGED=true
    print_info "Installing or repairing manifest-required CVD packages."
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get \
        -o Acquire::Retries=3 \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        -y install -- "${packages[@]}"; then
        fatal "$EXIT_EXTERNAL" "One or more required system packages could not be installed or repaired."
    fi
    CHANGED=true
    emoji_after_version="$(package_version "$EMOJI_PACKAGE")"
    if [[ "$emoji_before_version" != "$emoji_after_version" ||
          "$emoji_before_healthy" != true ]] ||
          ! emoji_font_resolves || ! emoji_font_file_discoverable; then
        rebuild_font_cache
    fi
    if ! emoji_font_resolves || ! emoji_font_file_discoverable; then
        print_warning "Noto Color Emoji is installed but is not healthy in fontconfig; reinstalling the package."
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get \
            -o Acquire::Retries=3 \
            -o Dpkg::Options::=--force-confdef \
            -o Dpkg::Options::=--force-confold \
            -y install --reinstall -- "$EMOJI_PACKAGE"; then
            fatal "$EXIT_EXTERNAL" "The Noto Color Emoji package could not be repaired."
        fi
        CHANGED=true
        rebuild_font_cache
    fi
    print_success "Required Ubuntu packages, including Noto Color Emoji, xclip, and numlockx, are current."
    sudo apt-get -y autoremove --purge \
        || print_warning "Optional obsolete-package cleanup did not complete."
    sudo apt-get clean \
        || print_warning "Optional package-cache cleanup did not complete."
}
repair_numlock_autostart() {
    CURRENT_STAGE="Num Lock startup integration maintenance"
    local staged_entry
    staged_entry="$(mktemp)"
    cat > "$staged_entry" <<'EOF_NUMLOCK'
[Desktop Entry]
Type=Application
Name=Enable Num Lock
Comment=Enable Num Lock when the Codio Xfce desktop session starts
Exec=/usr/bin/numlockx on
OnlyShowIn=XFCE;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF_NUMLOCK
    sudo install -d -m 0755 "$(dirname "$NUMLOCK_AUTOSTART_PATH")"
    if sudo test -r "$NUMLOCK_AUTOSTART_PATH" && \
            sudo cmp -s "$staged_entry" "$NUMLOCK_AUTOSTART_PATH"; then
        print_info "The Xfce Num Lock autostart entry is already current."
    else
        sudo install -o root -g root -m 0644 "$staged_entry" "$NUMLOCK_AUTOSTART_PATH" \
            || fatal "$EXIT_FAILURE" "The Xfce Num Lock autostart entry could not be installed."
        CHANGED=true
        print_success "The Xfce Num Lock desktop-startup integration was installed or repaired."
    fi
    rm -f -- "$staged_entry"
    if command -v desktop-file-validate >/dev/null 2>&1; then
        desktop-file-validate "$NUMLOCK_AUTOSTART_PATH" >/dev/null 2>&1 \
            || fatal "$EXIT_FAILURE" "The Num Lock autostart desktop entry is invalid."
    fi
}
update_python_tools() {
    CURRENT_STAGE="course Python tool maintenance"
    local -a packages=()
    mapfile -t packages < <(manifest_query venv_packages)
    command -v python3.12 >/dev/null 2>&1 \
        || fatal "$EXIT_FAILURE" "Python 3.12 is unavailable after package maintenance."
    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        print_info "Creating the course Python virtual environment."
        python3.12 -m venv "$VENV_DIR" \
            || fatal "$EXIT_FAILURE" "The course Python virtual environment could not be created."
        CHANGED=true
    fi
    retry_operation "Python packaging-tool update" \
        "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check \
            --upgrade pip setuptools wheel \
        || fatal "$EXIT_EXTERNAL" "The Python packaging tools could not be updated."
    CHANGED=true
    if ((${#packages[@]} > 0)); then
        retry_operation "Course Python tool update" \
            "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check \
                --upgrade "${packages[@]}" \
            || fatal "$EXIT_EXTERNAL" "One or more required course Python tools could not be updated."
        CHANGED=true
    fi
    print_success "Course Python tools are current."
}
update_vscode_extensions() {
    CURRENT_STAGE="Visual Studio Code extension maintenance"
    local extension
    local -a extensions=()
    command -v code >/dev/null 2>&1 \
        || fatal "$EXIT_FAILURE" "Visual Studio Code is unavailable after package maintenance."
    mapfile -t extensions < <(manifest_query extensions)
    ((${#extensions[@]} > 0)) \
        || fatal "$EXIT_MANIFEST" "The manifest declares no required CVD extensions."
    for extension in "${extensions[@]}"; do
        retry_operation "VS Code extension update: $extension" \
            code --install-extension "$extension" --force \
            || fatal "$EXIT_EXTERNAL" "Required VS Code extension could not be installed: $extension"
        CHANGED=true
    done
    print_success "Required Visual Studio Code extensions are current."
}
has_managed_path_block() {
    local file="$1"
    [[ -r "$file" ]] || return 1
    grep -Fqx "$MANAGED_PATH_START" "$file" \
        && grep -Fqx "$MANAGED_PATH_EXPORT" "$file" \
        && grep -Fqx "$MANAGED_PATH_END" "$file"
}

desktop_directory() {
    xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop\n' "$HOME"
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
    while IFS= read -r -d '' candidate; do
        if grep -Eiq '^Name=.*Visual Studio Code|^Exec=([^[:space:]]*/)?code([[:space:]]|$)' "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$desktop_dir" -maxdepth 1 -type f -name '*.desktop' -print0)
    return 1
}
launcher_opens_repos_root() {
    local launcher="$1"
    python3 - "$launcher" "$REPOS_ROOT" "$COURSE_ROOT" <<'PY'
import pathlib
import shlex
import sys
path = pathlib.Path(sys.argv[1])
workspace = sys.argv[2]
course_root = sys.argv[3]
try:
    lines = path.read_text(encoding="utf-8").splitlines()
except (OSError, UnicodeError):
    raise SystemExit(1)
in_desktop = False
exec_value = None
path_value = None
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        in_desktop = stripped == "[Desktop Entry]"
        continue
    if in_desktop and stripped.startswith("Exec=") and exec_value is None:
        exec_value = stripped[5:]
    if in_desktop and stripped.startswith("Path=") and path_value is None:
        path_value = stripped[5:]
if not exec_value:
    raise SystemExit(1)
try:
    args = shlex.split(exec_value)
except ValueError:
    raise SystemExit(1)
args = [arg for arg in args if not (arg.startswith("%") and len(arg) == 2)]
if not args or pathlib.Path(args[0]).name != "code":
    raise SystemExit(1)
if workspace not in args or course_root in args or path_value != workspace:
    raise SystemExit(1)
PY
}
launcher_is_xfce_trusted() {
    local launcher="$1" current_checksum stored_checksum
    [[ -f "$launcher" && -x "$launcher" ]] || return 1
    current_checksum="$(sha256sum -- "$launcher" 2>/dev/null | awk '{print $1}')"
    [[ -n "$current_checksum" ]] || return 1
    stored_checksum="$(gio info -a metadata::xfce-exe-checksum "$launcher" 2>/dev/null \
        | sed -n 's/^[[:space:]]*metadata::xfce-exe-checksum:[[:space:]]*//p' \
        | head -n 1)"
    [[ "$stored_checksum" == "$current_checksum" ]]
}
numlock_is_on() {
    local status
    command -v numlockx >/dev/null 2>&1 || return 1
    status="$(numlockx status 2>&1)" || return 1
    grep -Eiq '(^|[[:space:]])on([[:space:]]|$)' <<< "$status"
}
repository_workspace_is_configured() {
    local desktop_dir shortcut marker name path
    [[ -d "$REPOS_ROOT" && -r "$REPOS_ROOT" && -x "$REPOS_ROOT" ]] || return 1
    desktop_dir="$(desktop_directory)"
    shortcut="$desktop_dir/Repos"
    [[ -L "$shortcut" ]] || return 1
    [[ "$(readlink -f -- "$shortcut" 2>/dev/null || true)" == "$(readlink -f -- "$REPOS_ROOT" 2>/dev/null || true)" ]] || return 1
    marker="$(gio info -a metadata::emblems "$REPOS_ROOT" 2>/dev/null || true)"
    grep -Eq 'metadata::emblems:.*development' <<< "$marker" || return 1
    for name in "${CVD_BASELINE_DESKTOP_LAUNCHERS[@]}"; do
        path="$desktop_dir/$name"
        [[ ! -e "$path" && ! -L "$path" ]] || return 1
    done
}
detect_user_configuration() {
    CURRENT_STAGE="user-configuration state detection"
    local launcher
    USER_CONFIGURATION_COMPLETE=true
    gh auth status --hostname github.com >/dev/null 2>&1 \
        || USER_CONFIGURATION_COMPLETE=false
    [[ -n "$(git config --global --get user.name 2>/dev/null || true)" ]] \
        || USER_CONFIGURATION_COMPLETE=false
    [[ -n "$(git config --global --get user.email 2>/dev/null || true)" ]] \
        || USER_CONFIGURATION_COMPLETE=false
    [[ -x "$VENV_DIR/bin/python" ]] || USER_CONFIGURATION_COMPLETE=false
    has_managed_path_block "$HOME/.bashrc" || USER_CONFIGURATION_COMPLETE=false
    has_managed_path_block "$HOME/.profile" || USER_CONFIGURATION_COMPLETE=false
    repository_workspace_is_configured || USER_CONFIGURATION_COMPLETE=false
    launcher="$(find_vscode_launcher 2>/dev/null || true)"
    [[ -n "$launcher" ]] && launcher_opens_repos_root "$launcher" \
        && launcher_is_xfce_trusted "$launcher" \
        || USER_CONFIGURATION_COMPLETE=false
    numlock_is_on || USER_CONFIGURATION_COMPLETE=false
}
post_update_checks() {
    CURRENT_STAGE="post-update verification"
    local command_name extension package installed_extensions
    local -a required_commands=(git gh python3.12 code xclip numlockx fc-cache fc-list fc-match)
    local -a extensions=() packages=() system_packages=()
    for command_name in "${required_commands[@]}"; do
        command -v "$command_name" >/dev/null 2>&1 \
            || fatal "$EXIT_FAILURE" "Post-update check failed; required command is unavailable: $command_name"
    done
    mapfile -t system_packages < <(manifest_query system_packages)
    for package in "${system_packages[@]}"; do
        dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
            | grep -Fqx 'install ok installed' \
            || fatal "$EXIT_FAILURE" "Post-update check failed; required package is missing: $package"
    done
    emoji_font_resolves \
        || fatal "$EXIT_FAILURE" "Post-update check failed; fc-match emoji does not resolve to $EMOJI_FAMILY."
    emoji_font_file_discoverable \
        || fatal "$EXIT_FAILURE" "Post-update check failed; the $EMOJI_FAMILY font file is not discoverable through fontconfig."
    [[ -r "$NUMLOCK_AUTOSTART_PATH" ]] \
        || fatal "$EXIT_FAILURE" "Post-update check failed; the Xfce Num Lock autostart entry is missing."
    grep -Fqx 'Exec=/usr/bin/numlockx on' "$NUMLOCK_AUTOSTART_PATH" \
        || fatal "$EXIT_FAILURE" "Post-update check failed; the Num Lock startup command is incorrect."
    grep -Fqx 'OnlyShowIn=XFCE;' "$NUMLOCK_AUTOSTART_PATH" \
        || fatal "$EXIT_FAILURE" "Post-update check failed; the Num Lock entry is not restricted to Xfce."
    if command -v desktop-file-validate >/dev/null 2>&1; then
        desktop-file-validate "$NUMLOCK_AUTOSTART_PATH" >/dev/null 2>&1 \
            || fatal "$EXIT_FAILURE" "Post-update check failed; the Num Lock desktop entry is invalid."
    fi
    [[ -x "$VENV_DIR/bin/python" ]] \
        || fatal "$EXIT_FAILURE" "Post-update check failed; the course Python environment is unavailable."
    mapfile -t packages < <(manifest_query venv_packages)
    for package in "${packages[@]}"; do
        "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1 \
            || fatal "$EXIT_FAILURE" "Post-update check failed; Python package is missing: $package"
    done
    mapfile -t extensions < <(manifest_query extensions)
    installed_extensions="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    for extension in "${extensions[@]}"; do
        grep -Fqx "${extension,,}" <<< "$installed_extensions" \
            || fatal "$EXIT_FAILURE" "Post-update check failed; VS Code extension is missing: $extension"
    done
    if [[ -e "$REBOOT_REQUIRED_PATH" ]]; then
        RESTART_REQUIRED=true
        print_notice "Ubuntu reports that a CVD restart is required before the lifecycle can continue."
    fi
    print_success "Post-update checks completed."
}
main() {
    parse_options "$@"
    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    touch "$LOG_FILE"
    chmod 0600 "$LOG_FILE"
    if [[ "$UPDATE_TEST_MODE" == true ]]; then
        # Behavioral tests use a short-lived synthetic process tree. Writing
        # directly avoids leaving an asynchronous tee process holding captured
        # pipes open while preserving the same transcript contents.
        exec >> "$LOG_FILE" 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
    trap on_error ERR
    trap on_interrupt INT TERM
    trap cleanup EXIT
    print_header "IT 140 CODIO VIRTUAL DESKTOP UPDATE"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Version DTG    : $VERSION_DTG"
    print_info "Status         : $DEVELOPMENT_STATUS"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Maintain approved software and controlled course assets."
    print_info "Log file       : $LOG_FILE"
    print_notice "Update will not upgrade Ubuntu to a different release."
    print_notice "Keep this Terminal open until the final summary appears."
    check_platform_and_user
    CURRENT_STAGE="local manifest validation"
    local manifest_info
    manifest_info="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH")" \
        || fatal "$EXIT_MANIFEST" "The local controlled manifest and schema failed validation."
    IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$manifest_info"
    print_success "Manifest release $MANIFEST_RELEASE (schema $SUPPORTED_SCHEMA) validated."
    acquire_lock
    check_prerequisites
    refresh_controlled_manifest_assets
    update_system_packages
    repair_numlock_autostart
    update_python_tools
    update_vscode_extensions
    detect_user_configuration
    post_update_checks
    trap - ERR INT TERM
    finish "$EXIT_SUCCESS" "Required update operations completed."
    exit $?
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
