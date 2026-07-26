#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop system setup and repair script
#
# Traceability: SET-FR-001 through SET-FR-012; SET-DES-001 through SET-DES-012
# Scope: System-level software, trusted repositories, policies, and integrations.
# Excludes: Provider authentication, Git identity, user tools, IDE settings,
#           user extensions, and user launchers.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="2026.07.25.2"
readonly PLATFORM_ID="cvd"
readonly DEPLOYMENT_PROFILE_ID="codio_cvd"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/setup_${PLATFORM_ID}_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_FILE="${HOME}/.cache/it140-${PLATFORM_ID}-mutation.lock"

NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
START_EPOCH="$(date +%s)"
TEMP_FILES=()

cleanup() {
    local file
    for file in "${TEMP_FILES[@]}"; do
        [[ -n "$file" ]] && rm -f "$file"
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
print_warning() { printf '[WARNING] %s\n' "$1"; }
print_error() { printf '[ERROR] %s\n' "$1" >&2; }

usage() {
    cat <<USAGE
Usage: setup_cvd.sh [--help] [--version] [--noninteractive]
                    [--deployment-profile codio_cvd]

Installs or repairs the manifest-declared system layer for the IT 140 Codio
Virtual Desktop. Run as the standard Codio user, not with sudo.

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

on_error() {
    local status=$?
    local line=${BASH_LINENO[0]:-unknown}
    print_error "Setup stopped near line ${line} with exit status ${status}."
    print_error "Review the log: ${LOG_FILE}"
    if [[ "$CHANGED" == true ]]; then
        exit 7
    fi
    exit 1
}

on_interrupt() {
    print_error "Setup was interrupted. Rerun setup_cvd.sh to repair the system layer."
    if [[ "$CHANGED" == true ]]; then
        exit 7
    fi
    exit 6
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
    "schema_version", "automation_release", "policy", "platforms",
    "deployment_profiles", "managed_settings", "managed_assets", "logging",
}
missing = sorted(required - manifest.keys())
if missing:
    raise SystemExit(f"manifest missing required keys: {', '.join(missing)}")
if manifest["schema_version"] != "1.0":
    raise SystemExit("unsupported manifest schema version")
if not isinstance(schema, dict) or schema.get("$schema") != \
        "https://json-schema.org/draft/2020-12/schema":
    raise SystemExit("schema is not the approved Draft 2020-12 format")
if manifest["policy"].get("allow_os_release_upgrade") is not False:
    raise SystemExit("manifest attempts to allow an OS release upgrade")
platform = manifest["platforms"].get(platform_id)
profile = manifest["deployment_profiles"].get(profile_id)
if not platform or not platform.get("enabled"):
    raise SystemExit("CVD platform is not enabled")
if not profile or not profile.get("enabled"):
    raise SystemExit("CVD deployment profile is not enabled")
if profile.get("platform_id") != platform_id:
    raise SystemExit("deployment profile does not reference the CVD platform")
if profile.get("os_release_id") != "24.04":
    raise SystemExit("CVD profile does not declare Ubuntu 24.04")
if profile.get("architecture") != "x86_64":
    raise SystemExit("CVD profile does not declare x86_64")
if profile.get("desktop_environment", "").lower() != "xfce":
    raise SystemExit("CVD profile does not declare Xfce")

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

manifest_values() {
    local query="$1"
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json
import sys

path, platform_id, query = sys.argv[1:]
manifest = json.load(open(path, encoding="utf-8"))
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
    if [[ "$EUID" -eq 0 ]]; then
        print_error "Do not run setup_cvd.sh with sudo."
        print_error "Run it as the standard Codio desktop user."
        exit 2
    fi

    [[ -r /etc/os-release ]] || { print_error "Cannot identify the operating system."; exit 2; }
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
        print_error "This script supports only the IT 140 Ubuntu 24.04 CVD."
        print_error "Detected: ${PRETTY_NAME:-unknown operating system}"
        exit 2
    fi

    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" != "amd64" && "$architecture" != "x86_64" ]]; then
        print_error "This CVD release supports only x86_64. Detected: $architecture"
        exit 2
    fi

    command -v xfconf-query >/dev/null 2>&1 || {
        print_error "The Xfce desktop tools required by the CVD are unavailable."
        exit 2
    }

    command -v sudo >/dev/null 2>&1 || { print_error "sudo is unavailable."; exit 3; }
    sudo -n true >/dev/null 2>&1 || {
        print_error "The current user lacks the required passwordless sudo access."
        print_error "Contact Codio or course support."
        exit 3
    }
}

check_disk_space() {
    local minimum available
    minimum="$(manifest_values minimum_space)"
    available="$(df -PB1 "$HOME" | awk 'NR==2 {print $4}')"
    if (( available < minimum )); then
        print_error "At least $((minimum / 1024 / 1024 / 1024)) GB of free space is required."
        print_error "Available space: $((available / 1024 / 1024 / 1024)) GB."
        exit 1
    fi
}

acquire_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    if ! flock --nonblock 9; then
        print_error "Another IT 140 setup or repair operation is already running."
        exit 1
    fi
}

config_vendor_repositories() {
    print_info "Configuring approved software repositories..."
    sudo install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d

    local temp_key
    temp_key="$(mktemp)"
    TEMP_FILES+=("$temp_key")
    curl --fail --silent --show-error --location \
        --retry 5 --retry-delay 5 --retry-all-errors \
        https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        --output "$temp_key"
    sudo install -m 0644 "$temp_key" \
        /etc/apt/keyrings/githubcli-archive-keyring.gpg
    rm -f "$temp_key"

    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
        "$(dpkg --print-architecture)" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

    temp_key="$(mktemp)"
    TEMP_FILES+=("$temp_key")
    curl --fail --silent --show-error --location \
        --retry 5 --retry-delay 5 --retry-all-errors \
        https://packages.microsoft.com/keys/microsoft.asc \
        --output "$temp_key"
    gpg --dearmor < "$temp_key" \
        | sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null
    rm -f "$temp_key"
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

install_system_layer() {
    local apt_options
    apt_options=(-o Acquire::Retries=5 -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold)

    print_info "Refreshing Ubuntu package information..."
    sudo apt-get -o Acquire::Retries=5 update

    print_info "Installing repository prerequisites..."
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" install -y ca-certificates curl gpg

    config_vendor_repositories

    print_info "Applying security and maintenance updates within Ubuntu 24.04..."
    sudo apt-get -o Acquire::Retries=5 update
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" full-upgrade -y
    CHANGED=true

    mapfile -t system_packages < <(manifest_values system_packages)
    if ((${#system_packages[@]} == 0)); then
        print_error "The manifest declares no required CVD system packages."
        exit 5
    fi

    print_info "Installing or repairing manifest-declared system components..."
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" install -y "${system_packages[@]}"
    CHANGED=true
    print_success "Required system components are installed."
}

config_system_integrations() {
    print_info "Configuring system-level CVD integrations..."

    sudo install -d -m 0755 /etc/xdg/autostart
    sudo tee /etc/xdg/autostart/numlockx.desktop >/dev/null <<'EOF_NUMLOCK'
[Desktop Entry]
Type=Application
Name=Enable Num Lock
Comment=Enable Num Lock when the desktop session starts
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
        {"name": "TAG Projects", "url": "https://github.com/GC-STEM/it140-projects"}
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
        /etc/xdg/autostart/numlockx.desktop \
        /etc/opt/chrome/policies/managed/it140_bookmarks.json
    sudo chmod 0644 \
        /etc/xdg/autostart/numlockx.desktop \
        /etc/opt/chrome/policies/managed/it140_bookmarks.json
    python3 -m json.tool \
        /etc/opt/chrome/policies/managed/it140_bookmarks.json >/dev/null

    CHANGED=true
    print_success "System-level CVD integrations are configured."
}

post_validate() {
    local failed=0 package
    mapfile -t system_packages < <(manifest_values system_packages)

    print_info "Verifying required system packages and commands..."
    for package in "${system_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
            | grep -q 'install ok installed'; then
            print_error "Required package is not installed: $package"
            failed=1
        fi
    done

    for command_name in git gh python3.12 code; do
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

    python3 -m json.tool \
        /etc/opt/chrome/policies/managed/it140_bookmarks.json >/dev/null \
        || failed=1

    if ((failed)); then
        print_error "System-layer verification failed. Rerun setup_cvd.sh."
        exit 7
    fi

    print_success "System-layer verification passed."
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    print_header "SETUP SUMMARY"
    printf 'Result          : PASS\n'
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'Platform        : %s\n' "$PLATFORM_ID"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Next step       : Run config_cvd.sh\n'
    printf 'Log file        : %s\n' "$LOG_FILE"
    print_success "The IT 140 CVD system setup completed successfully."
}

main() {
    parse_options "$@"

    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap on_error ERR
    trap on_interrupt INT TERM
    trap cleanup EXIT

    print_header "IT 140 CODIO VIRTUAL DESKTOP SETUP"
    print_info "Script version  : $SCRIPT_VERSION"
    print_info "Current user    : $(id -un)"
    print_info "Purpose         : Install or repair the system-level course IDE."
    print_info "Log file        : $LOG_FILE"
    print_notice "This script changes system software but does not configure personal settings."

    check_platform
    acquire_lock

    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || {
        print_error "The manifest or schema is missing under $SCRIPT_ROOT/.manifest/."
        exit 5
    }

    MANIFEST_RELEASE="$(validate_manifest)" || exit 5
    readonly MANIFEST_RELEASE
    print_success "Manifest release $MANIFEST_RELEASE validated."

    check_disk_space
    install_system_layer
    config_system_integrations
    post_validate

    trap - ERR INT TERM
    finish
}

main "$@"
