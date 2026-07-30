#!/usr/bin/env bash
#
# IT 140 Ubuntu Desktop with GNOME managed update and repair script
#
# Traceability: UPD-FR-001 through UPD-FR-016; UPD-DES-001 through UPD-DES-016
# Scope: Approved Ubuntu maintenance, course-managed automation assets, required
#        system software, user tools, and IDE extensions within Ubuntu 24.04 LTS.
# Excludes: OS release upgrades, coursework, assignment repositories, Git history,
#           optional extension removal, and undeclared files or settings.

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
readonly LOG_FILE="${LOG_DIR}/update_${PLATFORM_ABBREVIATION}_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly LOCK_FILE="${HOME}/.cache/it140-${PLATFORM_ABBREVIATION}-mutation.lock"
readonly COURSE_REPOSITORY="https://github.com/GC-STEM/it140.git"
readonly MANAGED_PATH_START="# >>> IT 140 managed PATH >>>"
readonly MANAGED_PATH_END="# <<< IT 140 managed PATH <<<"
readonly MANAGED_PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/ubg:$PATH"'
readonly APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
PARTIAL=false
START_EPOCH="$(date +%s)"
WARNINGS=0
FAILURES=0
STAGING_ROOT=""
USER_CONFIGURATION_COMPLETE=false
WORKFLOW_NAME="First use or incomplete configuration"
RESTART_REQUIRED=false
TEMP_FILES=()

print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

print_info() { printf '[INFO] %s\n' "$1"; }
print_success() { printf '[SUCCESS] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }
print_warning() { printf '[WARNING] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
print_error() { printf '[ERROR] %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

print_closing_notices() {
    print_notice "A log containing all output displayed while this script ran is available here:"
    print_notice "$LOG_FILE"
    print_notice "After reviewing the summary, type 'exit' and press Enter to close this Terminal."
    print_notice "Open a new Terminal before running another script or command so it loads the latest PATH and environment settings."
}

usage() {
    cat <<USAGE
Usage: update_ubg.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile ubuntu_gnome_bare_metal]

Synchronizes approved course automation assets and performs periodic maintenance
for the IT 140 Course IDE on Ubuntu Desktop 24.04 LTS with GNOME. Run as the
standard desktop user, not with sudo. The script may request the user's sudo
password. It never performs an Ubuntu release upgrade.

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

cleanup() {
    local file
    if [[ -n "$STAGING_ROOT" && -d "$STAGING_ROOT" ]]; then
        rm -rf "$STAGING_ROOT"
    fi
    for file in "${TEMP_FILES[@]}"; do
        [[ -n "$file" ]] && rm -f "$file"
    done
}

on_error() {
    local status=$?
    local line=${BASH_LINENO[0]:-unknown}
    print_error "Update stopped near line ${line} with exit status ${status}."
    print_error "Review the log: ${LOG_FILE}"
    cleanup
    if [[ "$CHANGED" == true ]]; then
        exit 7
    fi
    exit 1
}

on_interrupt() {
    print_error "Update was interrupted. Rerun update_ubg.sh to recover."
    cleanup
    if [[ "$CHANGED" == true ]]; then
        exit 7
    fi
    exit 6
}

validate_manifest_pair() {
    local manifest="$1"
    local schema="$2"
    python3 - "$manifest" "$schema" "$PLATFORM_ID" \
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
    "deployment_profiles", "managed_settings", "managed_assets", "logging",
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
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "vscode_extension"):
            print(binding["package_identifier"])
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
elif query == "retry_attempts":
    profile_id = manifest["policy"]["default_retry_profile_id"]
    print(manifest["policy"]["retry_profiles"][profile_id]["maximum_attempts"])
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}

retry_operation() {
    local description="$1"
    shift
    local attempts delay attempt
    attempts="$(manifest_lines retry_attempts 2>/dev/null || printf '5')"
    delay=5
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if "$@"; then
            return 0
        fi
        if ((attempt == attempts)); then
            print_error "$description failed after $attempts attempts."
            return 1
        fi
        print_warning "$description failed on attempt $attempt of $attempts. Retrying in $delay seconds."
        sleep "$delay"
        delay=$((delay * 2))
        ((delay > 60)) && delay=60
    done
}

check_platform_and_user() {
    if [[ "$EUID" -eq 0 ]]; then
        print_error "Do not run update_ubg.sh with sudo."
        print_error "Run it as the standard Ubuntu Desktop user."
        exit 2
    fi

    [[ -r /etc/os-release ]] || {
        print_error "Cannot identify the operating system."
        exit 2
    }
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != 24.04 ]]; then
        print_error "This script supports only Ubuntu Desktop 24.04 LTS."
        print_error "Detected: ${PRETTY_NAME:-unknown operating system}"
        exit 2
    fi

    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" != amd64 && "$architecture" != x86_64 ]]; then
        print_error "This release supports only x86_64. Detected: $architecture"
        exit 2
    fi

    command -v gnome-shell >/dev/null 2>&1 || {
        print_error "The GNOME desktop required by this script is unavailable."
        exit 2
    }
    command -v sudo >/dev/null 2>&1 || {
        print_error "sudo is unavailable."
        exit 3
    }

    if [[ "$NONINTERACTIVE" == true ]]; then
        sudo -n true >/dev/null 2>&1 || {
            print_error "Noninteractive mode requires an active passwordless or cached sudo authorization."
            exit 3
        }
    else
        print_notice "Ubuntu may request your account password for approved system maintenance."
        sudo -v || {
            print_error "Administrator authorization was not granted."
            exit 3
        }
    fi
}

check_prerequisites() {
    local minimum available command_name
    minimum="$(manifest_lines minimum_space)"
    available="$(df -PB1 "$HOME" | awk 'NR==2 {print $4}')"
    if ((available < minimum)); then
        print_error "At least $((minimum / 1024 / 1024 / 1024)) GB of free space is required."
        exit 1
    fi

    for command_name in git python3 curl; do
        command -v "$command_name" >/dev/null 2>&1 || {
            print_error "Required command is unavailable: $command_name"
            print_error "Run setup_ubg.sh to repair the system layer."
            exit 1
        }
    done

    if pgrep -u "$(id -un)" -x code >/dev/null 2>&1; then
        print_notice "VS Code is open. Close and reopen it after the update."
    fi
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
    python3 - "$settings_file" "$VENV_DIR/bin/python" "$COURSE_ROOT" <<'PY'
import json
import pathlib
import sys

settings_path, expected_python, expected_root = sys.argv[1:]
try:
    settings = json.loads(pathlib.Path(settings_path).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
if not isinstance(settings, dict):
    raise SystemExit(1)
if settings.get("python.defaultInterpreterPath") != expected_python:
    raise SystemExit(1)
if settings.get("files.defaultFolder") != expected_root:
    raise SystemExit(1)
PY
}

detect_user_configuration() {
    local git_name git_email
    git_name="$(git config --global user.name 2>/dev/null || true)"
    git_email="$(git config --global user.email 2>/dev/null || true)"

    if command -v gh >/dev/null 2>&1 \
        && gh auth status --hostname github.com >/dev/null 2>&1 \
        && [[ -n "$git_name" ]] \
        && [[ "$git_email" =~ ^[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$ ]] \
        && has_managed_path_block "$HOME/.profile" \
        && has_managed_path_block "$HOME/.bashrc" \
        && has_valid_vscode_settings \
        && [[ -r "$APPLICATIONS_DIR/it140-folder.desktop" ]] \
        && [[ -r "$APPLICATIONS_DIR/it140-vscode.desktop" ]]; then
        USER_CONFIGURATION_COMPLETE=true
        WORKFLOW_NAME="Periodic maintenance"
        print_success "Existing IT 140 user configuration was detected."
    else
        USER_CONFIGURATION_COMPLETE=false
        WORKFLOW_NAME="First use or incomplete configuration"
        print_notice "IT 140 user configuration is not complete."
        print_notice "The Update Summary will direct you to config_ubg.sh."
    fi
}

acquire_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    if ! flock --nonblock 9; then
        print_error "Another IT 140 setup, configuration, or update is already running."
        exit 1
    fi
}

script_version() {
    local file="$1"
    sed -n 's/^readonly SCRIPT_VERSION="\([^"]*\)"/\1/p; s/^SCRIPT_VERSION="\([^"]*\)"/\1/p' \
        "$file" | head -1
}

is_valid_script_version() {
    local version="$1"
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]
}

version_at_least() {
    local candidate_version="$1"
    local installed_version="$2"
    python3 - "$candidate_version" "$installed_version" <<'PY'
import sys


def key(value):
    return tuple(int(item) for item in value.split("."))


raise SystemExit(key(sys.argv[1]) < key(sys.argv[2]))
PY
}

validate_staged_file() {
    local file="$1"
    local mode="$2"
    if [[ "$mode" == 0755 ]]; then
        bash -n "$file"
    elif [[ "$file" == *.json || "$file" == *.json.it140.new ]]; then
        python3 -m json.tool "$file" >/dev/null
    fi
}

atomic_install_file() {
    local source="$1"
    local destination="$2"
    local mode="$3"
    local directory temp backup
    local had_previous=false
    directory="$(dirname "$destination")"
    mkdir -p "$directory"
    temp="${destination}.it140.new"
    backup="${destination}.it140.previous"

    install -m "$mode" "$source" "$temp"
    if ! validate_staged_file "$temp" "$mode"; then
        rm -f "$temp"
        print_error "A staged course-managed file failed validation: $(basename "$destination")"
        return 1
    fi

    if [[ -f "$destination" ]]; then
        cp -p "$destination" "$backup"
        had_previous=true
    fi
    if ! mv -f "$temp" "$destination"; then
        rm -f "$temp"
        print_error "Could not activate course-managed file: $(basename "$destination")"
        return 1
    fi
    if ! validate_staged_file "$destination" "$mode"; then
        if [[ "$had_previous" == true && -f "$backup" ]]; then
            mv -f "$backup" "$destination"
        else
            rm -f "$destination"
        fi
        print_error "Activated file validation failed; the prior valid file was restored."
        return 1
    fi
    rm -f "$backup"
    CHANGED=true
}

clone_course_repository() {
    local destination="$1"
    rm -rf "$destination"
    git clone --depth 1 --filter=blob:none "$COURSE_REPOSITORY" "$destination"
}

synchronize_course_assets() {
    print_header "Step 1: Synchronize Course Automation Assets"
    STAGING_ROOT="$(mktemp -d)"
    chmod 0700 "$STAGING_ROOT"
    local clone_dir="$STAGING_ROOT/it140"

    print_info "Retrieving the approved course repository into private staging..."
    if ! retry_operation "Course repository retrieval" \
        clone_course_repository "$clone_dir"; then
        exit 4
    fi

    local candidate_manifest="$clone_dir/scripts/.manifest/it140_manifest.json"
    local candidate_schema="$clone_dir/scripts/.manifest/it140_manifest.schema.json"
    [[ -r "$candidate_manifest" && -r "$candidate_schema" ]] || {
        print_error "The staged repository does not contain the manifest and schema."
        exit 5
    }

    local candidate_release
    if ! candidate_release="$(validate_manifest_pair "$candidate_manifest" "$candidate_schema")"; then
        print_error "The staged manifest or schema failed Ubuntu GNOME validation."
        exit 5
    fi
    print_success "Staged manifest release $candidate_release validated."

    atomic_install_file "$candidate_schema" "$SCHEMA_PATH" 0644
    atomic_install_file "$candidate_manifest" "$MANIFEST_PATH" 0644

    local target_script source_script installed_script
    local candidate_version installed_version
    for target_script in bootstrap_ubg.sh setup_ubg.sh config_ubg.sh verify_ubg.sh update_ubg.sh; do
        source_script="$clone_dir/scripts/ubg/$target_script"
        installed_script="$PLATFORM_SCRIPT_DIR/$target_script"

        if [[ ! -r "$source_script" ]]; then
            if [[ -r "$installed_script" ]] \
                && validate_staged_file "$installed_script" 0755; then
                print_notice "$target_script is not included in this repository release; the valid installed copy was preserved."
            else
                print_error "Required Ubuntu GNOME script is unavailable: $target_script"
                PARTIAL=true
            fi
            continue
        fi

        if [[ "$target_script" != bootstrap_ubg.sh ]]; then
            candidate_version="$(script_version "$source_script")"
            if ! is_valid_script_version "$candidate_version"; then
                print_error "The staged $target_script has an invalid or missing SCRIPT_VERSION."
                PARTIAL=true
                continue
            fi

            installed_version=""
            if [[ -r "$installed_script" ]]; then
                installed_version="$(script_version "$installed_script")"
            fi
            if [[ -n "$installed_version" ]] \
                && is_valid_script_version "$installed_version" \
                && ! version_at_least "$candidate_version" "$installed_version"; then
                print_notice "$target_script $installed_version is newer than repository release $candidate_version; the installed copy was preserved."
                continue
            fi
        fi

        atomic_install_file "$source_script" "$installed_script" 0755
        if [[ "$target_script" == bootstrap_ubg.sh ]]; then
            print_success "$target_script synchronized."
        else
            print_success "$target_script $candidate_version synchronized."
        fi
    done

    MANIFEST_RELEASE="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH")" \
        || exit 5
    readonly MANIFEST_RELEASE
    print_success "Course-managed assets are active and valid."

    rm -rf "$STAGING_ROOT"
    STAGING_ROOT=""
}

config_vendor_repositories() {
    print_info "Repairing approved software repositories..."
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
}

update_system_packages() {
    print_header "Step 2: Update Ubuntu and Required System Software"
    local -a apt_options system_packages
    apt_options=(-o Acquire::Retries=5 -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold)

    print_info "Refreshing Ubuntu package information..."
    if ! retry_operation "Ubuntu package-information refresh" \
        sudo apt-get -o Acquire::Retries=5 update; then
        exit 4
    fi

    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" install -y ca-certificates curl gpg
    config_vendor_repositories

    print_info "Applying security and maintenance updates within Ubuntu 24.04 LTS..."
    sudo apt-get -o Acquire::Retries=5 update
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" full-upgrade -y
    CHANGED=true

    mapfile -t system_packages < <(manifest_lines system_packages)
    print_info "Installing or repairing manifest-declared system packages..."
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get "${apt_options[@]}" install -y "${system_packages[@]}"
    CHANGED=true
    print_success "Required system software is current."

    [[ -e /var/run/reboot-required ]] && RESTART_REQUIRED=true
}

update_user_tools() {
    print_header "Step 3: Update Required User Tools and IDE Extensions"

    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        print_notice "Creating the missing course virtual environment before maintenance."
        python3.12 -m venv "$VENV_DIR"
        USER_CONFIGURATION_COMPLETE=false
        CHANGED=true
    fi

    local extension
    local -a venv_packages required_extensions
    mapfile -t venv_packages < <(manifest_lines venv_packages)
    "$VENV_DIR/bin/python" -m pip install --upgrade pip
    "$VENV_DIR/bin/python" -m pip install --upgrade "${venv_packages[@]}"
    CHANGED=true
    print_success "Required course Python tools are current."

    if NODE_NO_WARNINGS=1 code --update-extensions; then
        print_success "Installed IDE extensions were updated without removing optional extensions."
    else
        print_warning "One or more installed extensions could not be updated."
        PARTIAL=true
    fi

    mapfile -t required_extensions < <(manifest_lines extensions)
    for extension in "${required_extensions[@]}"; do
        if NODE_NO_WARNINGS=1 code --install-extension "$extension" --force; then
            print_success "Required extension is installed and current: $extension"
        else
            print_warning "Required extension could not be updated: $extension"
            PARTIAL=true
        fi
    done
    CHANGED=true
}

post_validate() {
    print_header "Step 4: Update Validation"
    local failed=0 package extension command_name
    local installed_extensions
    local -a system_packages venv_packages required_extensions

    mapfile -t system_packages < <(manifest_lines system_packages)
    for package in "${system_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
            | grep -q 'install ok installed'; then
            print_error "Required system package is missing: $package"
            failed=1
        fi
    done

    for command_name in git gh python3.12 code; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            print_error "Required command is unavailable: $command_name"
            failed=1
        fi
    done

    mapfile -t venv_packages < <(manifest_lines venv_packages)
    for package in "${venv_packages[@]}"; do
        if ! "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
            print_error "Required course Python tool is missing: $package"
            failed=1
        fi
    done

    installed_extensions="$(NODE_NO_WARNINGS=1 code --list-extensions 2>/dev/null \
        | tr '[:upper:]' '[:lower:]')"
    mapfile -t required_extensions < <(manifest_lines extensions)
    for extension in "${required_extensions[@]}"; do
        if ! grep -Fxq "${extension,,}" <<<"$installed_extensions"; then
            print_error "Required IDE extension is missing: $extension"
            failed=1
        fi
    done

    if ((failed)); then
        PARTIAL=true
        print_warning "One or more required update checks failed. Review the messages above."
    else
        print_success "Required update checks passed."
    fi
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    local result="PASS" exit_code=0 next_step

    if [[ "$PARTIAL" == true || "$FAILURES" -gt 0 ]]; then
        result="PARTIAL"
        exit_code=7
    fi

    if [[ "$USER_CONFIGURATION_COMPLETE" != true ]]; then
        next_step="Close this terminal, open a new Terminal, and run config_ubg.sh."
    elif [[ "$RESTART_REQUIRED" == true ]]; then
        next_step="Restart Ubuntu, then run verify_ubg.sh in a new Terminal."
    else
        next_step="Close this terminal, open a new Terminal, and run verify_ubg.sh."
    fi

    print_header "UPDATE SUMMARY"
    printf 'Result          : %s\n' "$result"
    printf 'Workflow        : %s\n' "$WORKFLOW_NAME"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "${MANIFEST_RELEASE:-unavailable}"
    printf 'Platform        : %s (%s)\n' "$PLATFORM_ID" "$PLATFORM_ABBREVIATION"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Failures        : %s\n' "$FAILURES"
    printf 'Restart needed  : %s\n' "$([[ "$RESTART_REQUIRED" == true ]] && printf YES || printf NO)"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Next step       : %s\n' "$next_step"
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : %s\n' "$exit_code"

    if [[ "$result" == PASS ]]; then
        print_success "The IT 140 Ubuntu Desktop maintenance update completed successfully."
    else
        print_warning "The maintenance update completed with unresolved items."
    fi
    print_closing_notices
    exit "$exit_code"
}

main() {
    parse_options "$@"

    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap on_error ERR
    trap on_interrupt INT TERM
    trap cleanup EXIT

    print_header "IT 140 UBUNTU DESKTOP UPDATE"
    print_info "Script version  : $SCRIPT_VERSION"
    print_info "Current user    : $(id -un)"
    print_info "Purpose         : Synchronize course scripts and maintain the supported course IDE."
    print_info "Log file        : $LOG_FILE"
    print_notice "This script updates Ubuntu 24.04 LTS but will not upgrade to another Ubuntu release."
    print_notice "Personal coursework, assignment repositories, and unrelated settings are not changed."

    print_header "Platform and Local Manifest Validation"
    check_platform_and_user
    acquire_lock

    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || {
        print_error "The manifest or schema is missing under $SCRIPT_ROOT/.manifest/."
        print_error "Run bootstrap_ubg.sh again to restore course automation assets."
        exit 5
    }
    LOCAL_MANIFEST_RELEASE="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH")" \
        || exit 5
    readonly LOCAL_MANIFEST_RELEASE
    print_success "Local manifest release $LOCAL_MANIFEST_RELEASE validated."

    check_prerequisites
    detect_user_configuration
    synchronize_course_assets
    update_system_packages
    update_user_tools
    post_validate

    trap - ERR INT TERM
    finish
}

main "$@"
