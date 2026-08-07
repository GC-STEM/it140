#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop system installation and repair script
#
# Artifact ID: IT140-CVD-INSTALL
# Artifact version: 0.7.3-alpha.1
# Version date-time group: 2026-08-05-11-39
# Development status: Alpha Testing
#
# Traceability: INS-FR-001 through INS-FR-012; INS-DES-001 through INS-DES-012.
# Scope: System-level software, trusted repositories, policies, and integrations.
# Excludes: Provider authentication, Git identity, user tools, IDE settings,
#           user extensions, and user launchers.
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
readonly LOG_FILE="${LOG_DIR}/install_${PLATFORM_ID}_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_FILE="${HOME}/.cache/it140-${PLATFORM_ID}-mutation.lock"
readonly NUMLOCK_AUTOSTART_PATH="/etc/xdg/autostart/numlockx.desktop"
readonly EMOJI_PACKAGE="fonts-noto-color-emoji"
readonly EMOJI_FAMILY="Noto Color Emoji"
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
START_EPOCH="$(date +%s)"
START_TIME="$(date --iso-8601=seconds)"
WARNINGS=0
FAILURES=0
CURRENT_STAGE="initialization"
MANIFEST_RELEASE="unavailable"
MANIFEST_DTG="unavailable"
FINALIZED=false
TEMP_FILES=()
cleanup() {
    local file
    for file in "${TEMP_FILES[@]}"; do
        [[ -n "$file" ]] && rm -f -- "$file"
    done
}
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
Usage: install_it140.sh [--help] [--version] [--noninteractive]
                      [--deployment-profile codio_cvd]

Installs or repairs the manifest-declared system layer for the IT 140 Codio
Virtual Desktop. Run as the standard Codio user, not with sudo.
Exit codes:
  0  Completed successfully
  1  Required operation failed
  2  Invalid use or unsupported execution context
  3  Required privilege unavailable
  4  Required external source or service unavailable
  5  Manifest, schema, or controlled configuration invalid
  6  User canceled before a managed change
  7  Partial result or interruption after change

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
    print_notice "Follow the remediation above. If it continues, contact course support and include the log file."
}

finish() {
    local requested_code="${1:-0}"
    local message="${2:-}"
    local exit_code result elapsed next_step

    [[ "$FINALIZED" == false ]] || return "$requested_code"
    FINALIZED=true
    cleanup
    if ((requested_code == 0)); then
        exit_code=0
        result="PASS"
        next_step="Open a fresh Terminal and run configure_it140.sh."
    else
        exit_code="$(resolve_failure_code "$requested_code")"
        if ((exit_code == EXIT_PARTIAL)); then
            result="PARTIAL"
        else
            result="FAIL"
        fi
        next_step="Review the errors above, then rerun install_it140.sh."
    fi
    elapsed=$(( $(date +%s) - START_EPOCH ))
    print_header "INSTALLATION SUMMARY"
    [[ -n "$message" ]] && printf 'Conclusion      : %s\n' "$message"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Version DTG     : %s\n' "$VERSION_DTG"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'Manifest DTG    : %s\n' "$MANIFEST_DTG"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Failures        : %s\n' "$FAILURES"
    printf 'Start time      : %s\n' "$START_TIME"
    printf 'End time        : %s\n' "$(date --iso-8601=seconds)"
    printf 'Managed changes : %s\n' "$( [[ "$CHANGED" == true ]] && printf 'Yes' || printf 'No' )"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Next step       : %s\n' "$next_step"
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : %s\n' "$exit_code"
    if ((exit_code == 0)); then
        print_success "The IT 140 CVD system installation completed successfully."
    else
        course_continuity_guidance
    fi
    print_notice "Review the summary and log before closing this Terminal."
    return "$exit_code"
}

fatal() {
    local requested_code="$1"
    shift
    FAILURES=$((FAILURES + 1))
    print_error "$*"
    print_error "Failed stage: $CURRENT_STAGE"
    finish "$requested_code" "$*"
    exit $?
}
on_error() {
    local status=$?
    local line=${BASH_LINENO[0]:-unknown}
    trap - ERR
    FAILURES=$((FAILURES + 1))
    print_error "Install stopped near line ${line} during ${CURRENT_STAGE} (status ${status})."
    finish "$EXIT_FAILURE" "An unexpected command failure stopped Install."
    exit $?
}

on_interrupt() {
    trap - INT TERM
    print_error "Install was interrupted during ${CURRENT_STAGE}."
    finish "$EXIT_CANCELED" "Install was interrupted; rerun it to recover."
    exit $?
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
    raise SystemExit(f"manifest validation failed: {exc}")
required = {
    "schema_version", "automation_release", "automation_release_date_time_group",
    "course", "control", "policy", "capabilities", "products", "software_sources",
    "platforms", "deployment_profiles", "lifecycle_workflows", "managed_settings",
    "managed_assets", "obsolete_components", "logging",
}
missing = sorted(required - manifest.keys())
if missing:
    raise SystemExit(f"manifest missing required keys: {', '.join(missing)}")
if manifest.get("schema_version") != supported_schema:
    raise SystemExit(
        f"unsupported manifest schema: {manifest.get('schema_version')!r}; "
        f"expected {supported_schema}"
    )
if not isinstance(schema, dict) or schema.get("$schema") != \
        "https://json-schema.org/draft/2020-12/schema":
    raise SystemExit("schema is not the approved Draft 2020-12 format")
if manifest.get("policy", {}).get("allow_os_release_upgrade") is not False:
    raise SystemExit("manifest attempts to allow an operating-system release upgrade")
platform = manifest["platforms"].get(platform_id)
profile = manifest["deployment_profiles"].get(profile_id)
if not platform or not platform.get("enabled"):
    raise SystemExit("CVD platform is missing or disabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("CVD deployment profile is invalid")
if profile.get("os_release_id") != "24.04":
    raise SystemExit("CVD profile does not declare Ubuntu 24.04")
if profile.get("architecture") != "x86_64":
    raise SystemExit("CVD profile does not declare x86_64")
if profile.get("desktop_environment", "").lower() != "xfce":
    raise SystemExit("CVD profile does not declare Xfce")
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
manifest_values() {
    local query="$1"
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json
import sys

path, platform_id, query = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    manifest = json.load(stream)
platform = manifest["platforms"][platform_id]
if query == "system_packages":
    values = []
    for package in platform.get("os_packages", {}).values():
        if package.get("required"):
            values.append(package["package_identifier"])
    for binding in platform.get("course_ide_bindings", {}).values():
        if (binding.get("required") and
                binding.get("installation_scope") == "system" and
                binding.get("installer_adapter_id") == "apt_package"):
            values.append(binding["package_identifier"])
    for value in sorted(set(values)):
        print(value)
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}
check_platform() {
    CURRENT_STAGE="execution-context validation"
    if [[ "$EUID" -eq 0 ]]; then
        fatal "$EXIT_UNSUPPORTED" "Do not run install_it140.sh with sudo; use the standard CVD desktop account."
    fi
    [[ -r /etc/os-release ]] || fatal "$EXIT_UNSUPPORTED" "Cannot identify the operating system."
    # shellcheck disable=SC1091
    source /etc/os-release
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
    command -v xfconf-query >/dev/null 2>&1 \
        || fatal "$EXIT_UNSUPPORTED" "The Xfce desktop tools required by the CVD are unavailable."
    command -v sudo >/dev/null 2>&1 \
        || fatal "$EXIT_PRIVILEGE" "The sudo command is unavailable."
    sudo -n true >/dev/null 2>&1 \
        || fatal "$EXIT_PRIVILEGE" "The current account lacks required passwordless sudo access."
    print_info "Platform        : $PLATFORM_ID / $DEPLOYMENT_PROFILE_ID"
    print_info "Operating system: ${PRETTY_NAME:-Ubuntu 24.04}"
    print_info "Architecture    : $architecture"
}
check_disk_space() {
    CURRENT_STAGE="free-space validation"
    local minimum available
    minimum="$(manifest_values minimum_space)" \
        || fatal "$EXIT_MANIFEST" "The minimum-space policy could not be read from the manifest."
    available="$(df -PB1 "$HOME" | awk 'NR==2 {print $4}')"
    ((available >= minimum)) \
        || fatal "$EXIT_FAILURE" "At least $((minimum / 1024 / 1024 / 1024)) GB of free space is required."
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
    flock --nonblock 9 || fatal "$EXIT_FAILURE" "Another IT 140 mutating lifecycle script is running."
}
config_vendor_repositories() {
    CURRENT_STAGE="approved repository configuration"
    print_info "Configuring approved software repositories."
    sudo install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
    local temp_key
    temp_key="$(mktemp)"
    TEMP_FILES+=("$temp_key")
    curl --fail --silent --show-error --location \
        --retry 5 --retry-delay 5 --retry-all-errors \
        https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        --output "$temp_key" \
        || fatal "$EXIT_EXTERNAL" "The GitHub CLI signing key could not be downloaded."
    sudo install -m 0644 "$temp_key" /etc/apt/keyrings/githubcli-archive-keyring.gpg
    rm -f -- "$temp_key"
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
        "$(dpkg --print-architecture)" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    temp_key="$(mktemp)"
    TEMP_FILES+=("$temp_key")
    curl --fail --silent --show-error --location \
        --retry 5 --retry-delay 5 --retry-all-errors \
        https://packages.microsoft.com/keys/microsoft.asc \
        --output "$temp_key" \
        || fatal "$EXIT_EXTERNAL" "The Microsoft signing key could not be downloaded."
    gpg --dearmor < "$temp_key" | sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null
    rm -f -- "$temp_key"
    sudo chmod 0644 /usr/share/keyrings/microsoft.gpg
    sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null <<EOF_REPO
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF_REPO

    CHANGED=true
    print_success "Approved software repositories are configured."
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
install_system_layer() {
    CURRENT_STAGE="system software installation"
    local apt_options emoji_before_version emoji_after_version
    local emoji_before_healthy=false
    local -a system_packages=()
    apt_options=(-o Acquire::Retries=5 -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold)

    emoji_before_version="$(package_version "$EMOJI_PACKAGE")"
    if emoji_font_resolves && emoji_font_file_discoverable; then
        emoji_before_healthy=true
    fi
    print_info "Refreshing Ubuntu package information."
    sudo apt-get -o Acquire::Retries=5 update \
        || fatal "$EXIT_EXTERNAL" "Ubuntu package information could not be refreshed."
    print_info "Installing repository prerequisites."
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" install -y ca-certificates curl gpg \
        || fatal "$EXIT_EXTERNAL" "Repository prerequisites could not be installed."

    config_vendor_repositories
    print_info "Applying supported Ubuntu 24.04 maintenance without a release upgrade."
    sudo apt-get -o Acquire::Retries=5 update \
        || fatal "$EXIT_EXTERNAL" "Ubuntu package information could not be refreshed after repository configuration."
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" full-upgrade -y \
        || fatal "$EXIT_EXTERNAL" "Ubuntu package maintenance did not complete."
    CHANGED=true
    mapfile -t system_packages < <(manifest_values system_packages)
    ((${#system_packages[@]} > 0)) \
        || fatal "$EXIT_MANIFEST" "The manifest declares no required CVD system packages."
    print_info "Installing or repairing manifest-declared system components."
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" install -y -- "${system_packages[@]}" \
        || fatal "$EXIT_EXTERNAL" "One or more required system packages could not be installed or repaired."
    CHANGED=true

    emoji_after_version="$(package_version "$EMOJI_PACKAGE")"
    if [[ "$emoji_before_version" != "$emoji_after_version" ||
          "$emoji_before_healthy" != true ]] ||
          ! emoji_font_resolves || ! emoji_font_file_discoverable; then
        rebuild_font_cache
    fi
    if ! emoji_font_resolves || ! emoji_font_file_discoverable; then
        print_warning "Noto Color Emoji is installed but is not healthy in fontconfig; reinstalling the package."
        sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
            apt-get "${apt_options[@]}" install --reinstall -y -- "$EMOJI_PACKAGE" \
            || fatal "$EXIT_EXTERNAL" "The Noto Color Emoji package could not be repaired."
        CHANGED=true
        rebuild_font_cache
    fi
    print_success "Required system components, including Noto Color Emoji, xclip, and numlockx, are installed."
}
configure_system_integrations() {
    CURRENT_STAGE="system integration configuration"
    print_info "Configuring system-level CVD integrations."

    sudo install -d -m 0755 /etc/xdg/autostart
    sudo tee "$NUMLOCK_AUTOSTART_PATH" >/dev/null <<'EOF_NUMLOCK'
[Desktop Entry]
Type=Application
Name=Enable Num Lock
Comment=Enable Num Lock when the Codio Xfce desktop session starts
Exec=/usr/bin/numlockx on
OnlyShowIn=XFCE;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF_NUMLOCK
    sudo install -d -m 0755 /etc/opt/chrome/policies/managed
    sudo tee /etc/opt/chrome/policies/managed/it140_bookmarks.json >/dev/null <<'JSON_BOOKMARKS'
{
  "BookmarkBarEnabled": true,
  "ManagedBookmarks": [
    {"toplevel_name": "IT 140"},
    {
      "name": "GitHub Repositories",
      "children": [
        {"name": "Main Course Repository", "url": "https://github.com/GC-STEM/it140"},
        {"name": "Module 1 - Setup", "url": "https://github.com/GC-STEM/it140-m1-setup-tasks"},
        {"name": "Module 2", "url": "https://github.com/GC-STEM/it140-m2-assignment"},
        {"name": "Module 3", "url": "https://github.com/GC-STEM/it140-m3-assignment"},
        {"name": "Module 4", "url": "https://github.com/GC-STEM/it140-m4-assignment"},
        {"name": "Projects", "url": "https://github.com/GC-STEM/it140-projects"}
      ]
    },
    {
      "name": "Learn Python",
      "children": [
        {"name": "Python Video Tutorials", "url": "https://www.youtube.com/playlist?list=PL-osiE80TeTt2d9bfVyTiXJA-UTHn6WwU"},
        {"name": "Microsoft Learn Course", "url": "https://learn.microsoft.com/en-us/shows/intro-to-python-development/"},
        {"name": "VS Code for EDU Course", "url": "https://vscodeedu.com/courses/intro-to-python"}
      ]
    },
    {
      "name": "Python Resources",
      "children": [
        {"name": "Python Visualizer", "url": "https://pythontutor.com/visualize.html#mode=edit"},
        {"name": "Python Docs v3.12", "url": "https://docs.python.org/3.12/contents.html"},
        {"name": "PEP 8 - Style Guide for Python", "url": "https://peps.python.org/pep-0008/"},
        {"name": "PEP 257 - Docstring Conventions", "url": "https://peps.python.org/pep-0257/"},
        {"name": "Google Python Style Guide", "url": "https://google.github.io/styleguide/pyguide.html"}
      ]
    },
    {
      "name": "Course Resources",
      "children": [
        {"name": "IT 140 - Intro to Python Workshop", "url": "https://snhuacademicresourcecenter.screenstepslive.com/a/1834032-group-sessions-schedule-workshops-office-hours-and-peer-groups#workshops"},
        {"name": "IT Basics Office Hours", "url": "https://snhuacademicresourcecenter.screenstepslive.com/a/1834032-group-sessions-schedule-workshops-office-hours-and-peer-groups#office-hours"},
        {"name": "Academic Resource Center", "url": "https://snhuacademicresourcecenter.screenstepslive.com/m/138398"},
        {"name": "Shapiro Library", "url": "https://libguides.snhu.edu/c.php?g=708165&p=9774924"},
        {"name": "Zotero Group Library", "url": "https://www.zotero.org/groups/6612597/it140/library"}
      ]
    }
  ]
}
JSON_BOOKMARKS
    sudo chown root:root \
        "$NUMLOCK_AUTOSTART_PATH" \
        /etc/opt/chrome/policies/managed/it140_bookmarks.json
    sudo chmod 0644 \
        "$NUMLOCK_AUTOSTART_PATH" \
        /etc/opt/chrome/policies/managed/it140_bookmarks.json
    python3 -m json.tool /etc/opt/chrome/policies/managed/it140_bookmarks.json >/dev/null \
        || fatal "$EXIT_FAILURE" "The managed Chrome bookmarks policy is invalid."

    CHANGED=true
    print_success "System-level CVD integrations are configured."
}
post_validate() {
    CURRENT_STAGE="post-install verification"
    local failed=0 package command_name
    local -a system_packages=()
    mapfile -t system_packages < <(manifest_values system_packages)
    print_info "Verifying required system packages, commands, fonts, and integrations."
    for package in "${system_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
            | grep -Fq 'install ok installed'; then
            print_error "Required package is not installed: $package"
            failed=1
        fi
    done
    for command_name in git gh python3.12 code xclip numlockx fc-cache fc-list fc-match; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            print_error "Required command is unavailable: $command_name"
            failed=1
        fi
    done

    python3.12 - <<'PY' || failed=1
import sys
if sys.version_info[:2] != (3, 12):
    raise SystemExit("Python 3.12 is required")
PY

    if ! emoji_font_resolves; then
        print_error "fc-match emoji does not resolve to $EMOJI_FAMILY."
        failed=1
    fi
    if ! emoji_font_file_discoverable; then
        print_error "The $EMOJI_FAMILY font file is not discoverable through fontconfig."
        failed=1
    fi
    python3 -m json.tool /etc/opt/chrome/policies/managed/it140_bookmarks.json >/dev/null \
        || failed=1
    if [[ ! -r "$NUMLOCK_AUTOSTART_PATH" ]]; then
        print_error "The Xfce Num Lock autostart entry is missing: $NUMLOCK_AUTOSTART_PATH"
        failed=1
    else
        grep -Fqx 'Exec=/usr/bin/numlockx on' "$NUMLOCK_AUTOSTART_PATH" || {
            print_error "The Num Lock autostart command is incorrect."
            failed=1
        }
        grep -Fqx 'OnlyShowIn=XFCE;' "$NUMLOCK_AUTOSTART_PATH" || {
            print_error "The Num Lock autostart entry is not restricted to Xfce."
            failed=1
        }
        if command -v desktop-file-validate >/dev/null 2>&1; then
            desktop-file-validate "$NUMLOCK_AUTOSTART_PATH" >/dev/null 2>&1 || {
                print_error "The Num Lock autostart desktop entry is invalid."
                failed=1
            }
        fi
    fi
    if ((failed)); then
        fatal "$EXIT_PARTIAL" "System-layer verification failed. Rerun install_it140.sh."
    fi
    print_success "System-layer verification passed."
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
    print_header "IT 140 CODIO VIRTUAL DESKTOP INSTALL"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Version DTG    : $VERSION_DTG"
    print_info "Status         : $DEVELOPMENT_STATUS"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Install or repair the system-level course IDE."
    print_info "Log file       : $LOG_FILE"
    print_notice "This script changes system software but does not configure personal settings."
    print_notice "Keep this Terminal open until the final summary appears."
    check_platform
    acquire_lock
    CURRENT_STAGE="controlled manifest validation"
    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] \
        || fatal "$EXIT_MANIFEST" "The manifest or schema is missing under $SCRIPT_ROOT/.manifest/."
    local manifest_info
    manifest_info="$(validate_manifest)" \
        || fatal "$EXIT_MANIFEST" "The controlled manifest and schema failed validation."
    IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$manifest_info"
    print_success "Manifest release $MANIFEST_RELEASE (schema $SUPPORTED_SCHEMA) validated."
    check_disk_space
    install_system_layer
    configure_system_integrations
    post_validate

    trap - ERR INT TERM
    finish "$EXIT_SUCCESS" "Required installation operations completed."
    exit $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
