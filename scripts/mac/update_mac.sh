#!/bin/zsh
#
# IT 140 macOS managed update and repair script
#
# Traceability: UPD-FR-001 through UPD-FR-016; UPD-DES-001 through UPD-DES-016
# Scope: Approved student automation assets, current-release Apple maintenance,
#        manifest-declared Homebrew software, course Python tools, VS Code
#        extensions, managed user settings, and safe cleanup.
# Excludes: macOS release upgrades, student-owned course work, Git history,
#           optional extension removal, and unvalidated asset replacement.

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
readonly LOG_FILE="${LOG_DIR}/update_${PLATFORM_ABBREVIATION}_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly VSCODE_SETTINGS_FILE="${HOME}/Library/Application Support/Code/User/settings.json"
readonly LOCK_PARENT="${HOME}/Library/Caches"
readonly LOCK_DIR="${LOCK_PARENT}/it140-${PLATFORM_ABBREVIATION}-mutation.lock"
readonly MANIFEST_BACKUP_PATH="${MANIFEST_PATH}.it140.previous"
readonly SCHEMA_BACKUP_PATH="${SCHEMA_PATH}.it140.previous"
readonly MANIFEST_ACTIVATION_MARKER="${SCRIPT_ROOT}/.manifest/.it140-activation-in-progress"
readonly MANAGED_ENV_START="# >>> IT 140 managed environment >>>"
readonly MANAGED_ENV_END="# <<< IT 140 managed environment <<<"
readonly DESKTOP_SHORTCUT="${HOME}/Desktop/IT 140"

NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
PARTIAL=false
APPLE_UPDATE_INSTALLED=false
LOCK_HELD=false
WARNINGS=0
FAILURES=0
START_EPOCH="$(date +%s)"
TEMP_PATHS=()
STAGING_ROOT=""
WORKFLOW_NAME="Periodic maintenance"
CONFIGURATION_COMPLETE=false
MANIFEST_RELEASE="unavailable"

print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

print_info() { printf '[INFO] %s\n' "$1"; }
print_success() { printf '[SUCCESS] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }
print_warning() { printf '[WARNING] %s\n' "$1"; WARNINGS=$(( WARNINGS + 1 )); }
print_error() { printf '[ERROR] %s\n' "$1" >&2; }

print_closing_notices() {
    print_notice "A log containing all output displayed while this script ran is available here:"
    print_notice "$LOG_FILE"
    print_notice "After reviewing the summary, type 'exit' and press Enter to close this Terminal."
    print_notice "Open a new Terminal before running another script or command so it loads the latest PATH and environment settings."
}

usage() {
    cat <<'USAGE'
Usage: update_mac.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile macos_bare_metal]

Synchronizes approved IT 140 student automation assets and maintains the local
macOS course IDE, including current-release Apple updates, Homebrew software,
course Python tools, VS Code extensions, and managed settings.

The script never installs a different major macOS release and never removes
student work, Git repositories, Git history, or optional VS Code extensions.

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

restore_interrupted_manifest_activation() {
    if [[ ! -e "$MANIFEST_ACTIVATION_MARKER" ]]; then
        rm -f "$MANIFEST_BACKUP_PATH" "$SCHEMA_BACKUP_PATH"
        rm -f "${MANIFEST_PATH}.it140.new" "${SCHEMA_PATH}.it140.new"
        return 0
    fi
    if [[ -f "$MANIFEST_BACKUP_PATH" ]]; then
        mv -f "$MANIFEST_BACKUP_PATH" "$MANIFEST_PATH"
    else
        rm -f "$MANIFEST_PATH"
    fi
    if [[ -f "$SCHEMA_BACKUP_PATH" ]]; then
        mv -f "$SCHEMA_BACKUP_PATH" "$SCHEMA_PATH"
    else
        rm -f "$SCHEMA_PATH"
    fi
    rm -f "${MANIFEST_PATH}.it140.new" "${SCHEMA_PATH}.it140.new"
    rm -f "$MANIFEST_ACTIVATION_MARKER"
}

cleanup() {
    set +e
    restore_interrupted_manifest_activation
    local temp_path
    for temp_path in "${TEMP_PATHS[@]}"; do
        [[ -n "$temp_path" ]] && rm -rf "$temp_path"
    done
    if [[ "$LOCK_HELD" == true && -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]]; then
        rm -rf "$LOCK_DIR"
    fi
}

on_error() {
    local exit_code=$?
    trap - ERR
    set +e
    print_error "Update stopped near line ${LINENO:-unknown} with exit status ${exit_code}."
    print_error "Review the log: ${LOG_FILE}"
    cleanup
    if [[ "$CHANGED" == true ]]; then
        exit 7
    fi
    exit 1
}

on_interrupt() {
    trap - INT TERM
    set +e
    print_error "Update was interrupted."
    print_error "Rerun update_mac.sh; staged operations are designed for safe retry."
    cleanup
    if [[ "$CHANGED" == true ]]; then
        exit 7
    fi
    exit 6
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

validate_manifest_pair() {
    local manifest_file="$1"
    local schema_file="$2"
    local python_path
    python_path="$(resolve_python)" || {
        print_error "Python 3.12 is unavailable. Run setup_mac.sh first."
        return 1
    }
    "$python_path" - "$manifest_file" "$schema_file" "$PLATFORM_ID" \
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

try:
    manifest = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
    schema = json.loads(pathlib.Path(schema_path).read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError) as exc:
    raise SystemExit(f"manifest validation failed: {exc}")
required = {
    "schema_version", "automation_release", "course", "control", "policy",
    "capabilities", "products", "software_sources", "provider_profiles",
    "platforms", "deployment_profiles", "managed_settings", "managed_assets",
    "obsolete_components", "logging",
}
missing = sorted(required - manifest.keys())
if missing:
    raise SystemExit(f"manifest missing required keys: {', '.join(missing)}")
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
    raise SystemExit("unsupported architecture or deployment profile")
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
print(manifest["automation_release"])
PY
}

manifest_lines() {
    local query="$1"
    local python_path
    python_path="$(resolve_python)"
    "$python_path" - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json
import sys

path, platform_id, query = sys.argv[1:]
manifest = json.load(open(path, encoding="utf-8"))
platform = manifest["platforms"][platform_id]
bindings = platform["course_ide_bindings"]

if query == "system_formulae":
    values = []
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "system" and
                binding.get("installer_adapter_id") == "homebrew_formula"):
            values.append(binding["package_identifier"])
    for value in sorted(set(values)):
        print(value)
elif query == "system_casks":
    values = []
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "system" and
                binding.get("installer_adapter_id") == "homebrew_cask"):
            values.append(binding["package_identifier"])
    for value in sorted(set(values)):
        print(value)
elif query == "system_commands":
    commands = []
    for binding in bindings.values():
        if binding.get("required") and binding.get("installation_scope") == "system":
            commands.extend(binding.get("verification", {}).get("executable_names", []))
    for command in sorted(set(commands)):
        print(command)
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
elif query == "git_settings":
    for profile_id in bindings["version_control_system"].get("settings_profile_ids", []):
        profile = manifest["managed_settings"][profile_id]
        if platform_id not in profile.get("platform_ids", []):
            continue
        for key, value in profile["values"].items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            print(f"{key}\t{value}")
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
elif query == "source_repository":
    print(manifest["control"]["source_repository"])
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}

check_platform_and_user() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        print_error "This script supports macOS only."
        exit 2
    fi
    if (( EUID == 0 )); then
        print_error "Do not run update_mac.sh with sudo."
        exit 2
    fi
    if [[ "$REQUESTED_PROFILE" != "$DEPLOYMENT_PROFILE_ID" ]]; then
        print_error "Unsupported deployment profile: $REQUESTED_PROFILE"
        exit 2
    fi
}

check_supported_release() {
    /usr/bin/plutil -lint "$MANIFEST_PATH" >/dev/null || {
        print_error "The course manifest is not valid JSON."
        exit 5
    }
    local product_version major releases_json architecture profile_architecture
    product_version="$(/usr/bin/sw_vers -productVersion)"
    major="${product_version%%.*}"
    architecture="$(uname -m)"
    releases_json="$(/usr/bin/plutil -extract platforms.macos.os.releases json -o - "$MANIFEST_PATH")" || exit 5
    profile_architecture="$(/usr/bin/plutil -extract deployment_profiles.${REQUESTED_PROFILE}.architecture raw -o - "$MANIFEST_PATH")" || exit 5
    if ! printf '%s\n' "$releases_json" \
        | grep -Eq "\"release_id\"[[:space:]]*:[[:space:]]*\"${major}\""; then
        print_error "macOS ${product_version} is not supported by the current manifest."
        exit 2
    fi
    if [[ "$profile_architecture" != "$architecture" ]]; then
        print_error "The deployment profile does not support ${architecture}."
        exit 2
    fi
}

check_prerequisites() {
    local minimum available_kb available
    minimum="$(manifest_lines minimum_space)"
    available_kb="$(df -Pk "$HOME" | awk 'NR == 2 {print $4}')"
    available=$(( available_kb * 1024 ))
    if (( available < minimum )); then
        print_error "At least $(( minimum / 1024 / 1024 / 1024 )) GB of free space is required."
        exit 1
    fi
    initialize_homebrew_environment || {
        print_error "Homebrew is unavailable. Run setup_mac.sh first."
        exit 1
    }
    local python_path code_cli command_name
    python_path="$(resolve_python 2>/dev/null || true)"
    code_cli="$(resolve_code_cli 2>/dev/null || true)"
    for command_name in git gh; do
        command -v "$command_name" >/dev/null 2>&1 || {
            print_error "Required command is unavailable: $command_name"
            print_error "Run setup_mac.sh first."
            exit 1
        }
    done
    [[ -x "$python_path" ]] || { print_error "Python 3.12 is unavailable. Run setup_mac.sh first."; exit 1; }
    [[ -x "$code_cli" ]] || { print_error "Visual Studio Code is unavailable. Run setup_mac.sh first."; exit 1; }
    if pgrep -x "Visual Studio Code" >/dev/null 2>&1; then
        print_notice "Visual Studio Code is open. Close and reopen it after the update."
    fi
}

acquire_lock() {
    mkdir -p "$LOCK_PARENT"
    if [[ -L "$LOCK_DIR" ]]; then
        print_error "The lifecycle lock path is an unexpected symbolic link: $LOCK_DIR"
        exit 1
    fi
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        LOCK_HELD=true
        return
    fi
    local existing_pid=""
    [[ -r "$LOCK_DIR/pid" ]] && existing_pid="$(cat "$LOCK_DIR/pid")"
    case "$existing_pid" in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$existing_pid" 2>/dev/null; then
                print_error "Another IT 140 macOS setup, configuration, or update operation is running."
                exit 1
            fi
            ;;
    esac
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    LOCK_HELD=true
}

retry_operation() {
    local label="$1"
    shift
    local attempt=1
    local delay=5
    while (( attempt <= 5 )); do
        if "$@"; then
            return 0
        fi
        if (( attempt == 5 )); then
            print_error "${label} failed after ${attempt} attempts."
            return 1
        fi
        print_warning "${label} failed. Retrying in ${delay} seconds."
        sleep "$delay"
        attempt=$(( attempt + 1 ))
        delay=$(( delay * 2 ))
        (( delay > 60 )) && delay=60
    done
}

validate_staged_file() {
    local staged_file="$1"
    local mode="$2"
    if [[ "$mode" == "0755" ]]; then
        /bin/zsh -n "$staged_file"
    elif [[ "$staged_file" == *.json || "$staged_file" == *.json.it140.new ]]; then
        "$(resolve_python)" -m json.tool "$staged_file" >/dev/null
    fi
}

atomic_install_file() {
    local source_file="$1"
    local destination_file="$2"
    local mode="$3"
    local destination_dir temporary_file backup_file had_previous=false
    destination_dir="$(dirname "$destination_file")"
    mkdir -p "$destination_dir"
    temporary_file="${destination_file}.it140.new"
    backup_file="${destination_file}.it140.previous"

    if [[ -f "$destination_file" ]] && cmp -s "$source_file" "$destination_file"; then
        chmod "$mode" "$destination_file"
        return 0
    fi
    /usr/bin/install -m "$mode" "$source_file" "$temporary_file"
    if ! validate_staged_file "$temporary_file" "$mode"; then
        rm -f "$temporary_file"
        print_error "A staged file failed validation: $(basename "$destination_file")"
        return 1
    fi
    if [[ -f "$destination_file" ]]; then
        cp -p "$destination_file" "$backup_file"
        had_previous=true
    fi
    if ! mv -f "$temporary_file" "$destination_file"; then
        rm -f "$temporary_file"
        print_error "Could not activate: $(basename "$destination_file")"
        return 1
    fi
    if ! validate_staged_file "$destination_file" "$mode"; then
        if [[ "$had_previous" == true && -f "$backup_file" ]]; then
            mv -f "$backup_file" "$destination_file"
        else
            rm -f "$destination_file"
        fi
        print_error "Activated-file validation failed; the prior file was restored."
        return 1
    fi
    rm -f "$backup_file"
    CHANGED=true
}

activate_manifest_pair() {
    local candidate_manifest="$1"
    local candidate_schema="$2"
    local manifest_temp="${MANIFEST_PATH}.it140.new"
    local schema_temp="${SCHEMA_PATH}.it140.new"
    mkdir -p "$(dirname "$MANIFEST_PATH")"
    /usr/bin/install -m 0644 "$candidate_manifest" "$manifest_temp"
    /usr/bin/install -m 0644 "$candidate_schema" "$schema_temp"
    if ! validate_manifest_pair "$manifest_temp" "$schema_temp" >/dev/null; then
        rm -f "$manifest_temp" "$schema_temp"
        print_error "The staged manifest pair failed validation."
        return 1
    fi
    cp -p "$MANIFEST_PATH" "$MANIFEST_BACKUP_PATH"
    cp -p "$SCHEMA_PATH" "$SCHEMA_BACKUP_PATH"
    : > "$MANIFEST_ACTIVATION_MARKER"
    mv -f "$schema_temp" "$SCHEMA_PATH"
    mv -f "$manifest_temp" "$MANIFEST_PATH"
    if ! validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH" >/dev/null; then
        restore_interrupted_manifest_activation
        print_error "Activated manifest validation failed; the previous pair was restored."
        return 1
    fi
    rm -f "$MANIFEST_ACTIVATION_MARKER" "$MANIFEST_BACKUP_PATH" "$SCHEMA_BACKUP_PATH"
    CHANGED=true
}

script_version() {
    local script_file="$1"
    sed -nE 's/^[[:space:]]*readonly[[:space:]]+SCRIPT_VERSION="([0-9]+(\.[0-9]+)*)".*/\1/p' "$script_file" | head -n 1
}

candidate_not_older() {
    local candidate_file="$1"
    local installed_file="$2"
    local candidate_version installed_version python_path
    candidate_version="$(script_version "$candidate_file")"
    [[ -n "$candidate_version" ]] || return 1
    if [[ ! -f "$installed_file" ]]; then
        return 0
    fi
    installed_version="$(script_version "$installed_file")"
    [[ -n "$installed_version" ]] || return 0
    python_path="$(resolve_python)"
    "$python_path" - "$candidate_version" "$installed_version" <<'PY'
import sys

def key(value):
    return tuple(int(part) for part in value.split("."))

raise SystemExit(0 if key(sys.argv[1]) >= key(sys.argv[2]) else 1)
PY
}

clone_course_repository() {
    local destination="$1"
    local repository="$2"
    rm -rf "$destination"
    git clone --depth 1 --filter=blob:none "$repository" "$destination"
}

synchronize_course_assets() {
    print_header "Step 1: Synchronize Course Automation Assets"
    STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/it140-mac-update.XXXXXX")"
    TEMP_PATHS+=("$STAGING_ROOT")
    chmod 0700 "$STAGING_ROOT"
    local clone_dir="${STAGING_ROOT}/it140"
    local repository
    repository="$(manifest_lines source_repository)"

    print_info "Retrieving the approved course repository into private staging..."
    retry_operation "Course repository retrieval" clone_course_repository "$clone_dir" "$repository" || exit 4

    local candidate_manifest="${clone_dir}/scripts/.manifest/it140_manifest.json"
    local candidate_schema="${clone_dir}/scripts/.manifest/it140_manifest.schema.json"
    if [[ ! -r "$candidate_manifest" || ! -r "$candidate_schema" ]]; then
        print_error "The staged repository does not contain the manifest and schema."
        exit 5
    fi
    local candidate_release
    candidate_release="$(validate_manifest_pair "$candidate_manifest" "$candidate_schema")" || exit 5
    print_success "Staged manifest release $candidate_release validated."
    activate_manifest_pair "$candidate_manifest" "$candidate_schema" || exit 5
    print_success "The course manifest and schema were activated transactionally."

    local script_name source_script installed_script
    for script_name in setup_mac.sh config_mac.sh verify_mac.sh update_mac.sh; do
        source_script="${clone_dir}/scripts/mac/${script_name}"
        installed_script="${PLATFORM_SCRIPT_DIR}/${script_name}"
        if [[ ! -r "$source_script" ]]; then
            if [[ -x "$installed_script" ]] && /bin/zsh -n "$installed_script"; then
                print_notice "The repository omits ${script_name}; the valid installed copy was preserved."
            else
                print_error "The required script is absent from both staging and the installed environment: ${script_name}"
                FAILURES=$(( FAILURES + 1 ))
                PARTIAL=true
            fi
            continue
        fi
        if ! /bin/zsh -n "$source_script"; then
            print_error "The staged script failed syntax validation: ${script_name}"
            FAILURES=$(( FAILURES + 1 ))
            PARTIAL=true
            continue
        fi
        if candidate_not_older "$source_script" "$installed_script"; then
            if atomic_install_file "$source_script" "$installed_script" 0755; then
                print_success "${script_name} synchronized."
            else
                FAILURES=$(( FAILURES + 1 ))
                PARTIAL=true
            fi
        else
            print_notice "A newer installed ${script_name} was preserved; downgrade was prevented."
        fi
    done

    MANIFEST_RELEASE="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH")" || exit 5
    print_success "Active manifest release $MANIFEST_RELEASE validated."
}

update_current_macos_release() {
    print_header "Step 2: Update the Current macOS Release"
    local output_file current_major
    output_file="$(mktemp "${TMPDIR:-/tmp}/it140-softwareupdate.XXXXXX")"
    TEMP_PATHS+=("$output_file")
    current_major="$(/usr/bin/sw_vers -productVersion | cut -d. -f1)"

    print_info "Checking Apple Software Update for current-release updates..."
    if ! /usr/sbin/softwareupdate --list >"$output_file" 2>&1; then
        cat "$output_file"
        print_warning "Apple Software Update could not complete its check."
        PARTIAL=true
        return
    fi
    cat "$output_file"

    local -a safe_labels
    safe_labels=()
    local label lower_label
    while IFS= read -r label; do
        [[ -n "$label" ]] || continue
        lower_label="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
        if [[ "$lower_label" == *"macos"* ]]; then
            if printf '%s\n' "$label" \
                | grep -Eiq "macOS.*(^|[^0-9])${current_major}([. -]|$)"; then
                safe_labels+=("$label")
            else
                print_notice "Skipping a different-major macOS upgrade: $label"
            fi
        else
            safe_labels+=("$label")
        fi
    done < <(sed -nE 's/^[[:space:]]*[*-][[:space:]]+Label:[[:space:]]*(.*)$/\1/p' "$output_file")

    if (( ${#safe_labels[@]} == 0 )); then
        if grep -Fq "No new software available" "$output_file"; then
            print_success "Apple reports no new software updates."
        else
            print_notice "No safely classified current-release Apple updates were selected."
            print_notice "Review System Settings > General > Software Update manually."
        fi
        return
    fi

    if [[ "$NONINTERACTIVE" == true ]]; then
        if ! sudo -n true >/dev/null 2>&1; then
            print_warning "Apple updates require administrator authorization."
            print_warning "Run update_mac.sh interactively to apply them."
            PARTIAL=true
            return
        fi
    else
        print_notice "macOS may request administrator authorization for Apple updates."
        if ! sudo -v; then
            print_warning "Administrator authorization was not granted."
            PARTIAL=true
            return
        fi
    fi

    for label in "${safe_labels[@]}"; do
        print_info "Installing approved Apple update: $label"
        if sudo /usr/sbin/softwareupdate --install "$label"; then
            CHANGED=true
            APPLE_UPDATE_INSTALLED=true
            print_success "Apple update installed: $label"
        else
            print_warning "Apple update could not be installed: $label"
            PARTIAL=true
        fi
    done
}

update_homebrew_software() {
    print_header "Step 3: Update Homebrew and System Software"
    retry_operation "Homebrew metadata update" brew update || exit 4
    local formula
    while IFS= read -r formula; do
        [[ -n "$formula" ]] || continue
        if brew list --formula "$formula" >/dev/null 2>&1; then
            if brew outdated --formula "$formula" | grep -Fxq "$formula"; then
                if retry_operation "Homebrew upgrade for ${formula}" brew upgrade "$formula"; then
                    CHANGED=true
                    print_success "Required formula was updated: ${formula}"
                else
                    print_warning "Could not update required formula: ${formula}"
                    PARTIAL=true
                fi
            else
                print_success "Required formula is already current: ${formula}"
            fi
        else
            if retry_operation "Homebrew installation for ${formula}" brew install "$formula"; then
                CHANGED=true
                print_success "Required formula was installed: ${formula}"
            else
                print_warning "Could not install required formula: ${formula}"
                PARTIAL=true
            fi
        fi
    done < <(manifest_lines system_formulae)

    local cask
    while IFS= read -r cask; do
        [[ -n "$cask" ]] || continue
        if brew list --cask "$cask" >/dev/null 2>&1; then
            if brew outdated --cask "$cask" | grep -Fxq "$cask"; then
                if retry_operation "Homebrew cask upgrade for ${cask}" brew upgrade --cask "$cask"; then
                    CHANGED=true
                    print_success "Required cask was updated: ${cask}"
                else
                    print_warning "Could not update required cask: ${cask}"
                    PARTIAL=true
                fi
            else
                print_success "Required cask is already current: ${cask}"
            fi
        else
            if retry_operation "Homebrew cask installation for ${cask}" brew install --cask "$cask"; then
                CHANGED=true
                print_success "Required cask was installed: ${cask}"
            else
                print_warning "Could not install required cask: ${cask}"
                PARTIAL=true
            fi
        fi
    done < <(manifest_lines system_casks)
}

update_user_tools() {
    print_header "Step 4: Update Course Python Tools and VS Code Extensions"
    local python_path code_cli venv_version
    python_path="$(resolve_python)"
    code_cli="$(resolve_code_cli)"

    if [[ -x "$VENV_DIR/bin/python" ]]; then
        venv_version="$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
        if [[ "$venv_version" != "3.12" ]]; then
            print_warning "The managed virtual environment used Python ${venv_version:-unknown} and will be rebuilt."
            rm -rf "$VENV_DIR"
            CHANGED=true
        fi
    fi
    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        if [[ "$WORKFLOW_NAME" == "Periodic maintenance" ]]; then
            print_warning "The course virtual environment was missing and will be repaired."
        else
            print_notice "The course virtual environment will be created for first use."
        fi
        "$python_path" -m venv "$VENV_DIR"
        CHANGED=true
    fi

    if ! "$VENV_DIR/bin/python" -m pip install --upgrade pip; then
        print_warning "The Python package installer could not be updated."
        PARTIAL=true
    else
        CHANGED=true
    fi

    local -a packages
    packages=()
    local package
    while IFS= read -r package; do
        [[ -n "$package" ]] && packages+=("$package")
    done < <(manifest_lines venv_packages)
    if ! "$VENV_DIR/bin/python" -m pip install --upgrade "${packages[@]}"; then
        print_warning "One or more required Python tools could not be updated."
        PARTIAL=true
    else
        CHANGED=true
        print_success "Required course Python tools are current."
    fi

    if NODE_NO_WARNINGS=1 "$code_cli" --update-extensions; then
        print_success "Installed VS Code extensions were updated; optional extensions were preserved."
    else
        print_warning "One or more installed VS Code extensions could not be updated."
        PARTIAL=true
    fi
    local extension
    while IFS= read -r extension; do
        [[ -n "$extension" ]] || continue
        if NODE_NO_WARNINGS=1 "$code_cli" --install-extension "$extension" --force; then
            print_success "Required extension is installed and current: ${extension}"
        else
            print_warning "Required extension could not be updated: ${extension}"
            PARTIAL=true
        fi
    done < <(manifest_lines extensions)
    CHANGED=true
}

upsert_managed_environment_block() {
    local target_file="$1"
    local brew_path
    brew_path="$(command -v brew)"
    "$(resolve_python)" - "$target_file" "$brew_path" <<'PY'
from pathlib import Path
import sys

target = Path(sys.argv[1])
brew_path = sys.argv[2]
start = "# >>> IT 140 managed environment >>>"
end = "# <<< IT 140 managed environment <<<"
block = (
    f"{start}\n"
    f'eval "$({brew_path} shellenv)"\n'
    'export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:'
    '$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:$PATH"\n'
    f"{end}\n"
)
original = target.read_text(encoding="utf-8") if target.exists() else ""
if original.count(start) != original.count(end):
    raise SystemExit(f"{target} contains an incomplete IT 140 managed block")
if original.count(start) > 1 or original.count(end) > 1:
    raise SystemExit(f"{target} contains duplicate IT 140 managed blocks")
if start in original and original.index(start) > original.index(end):
    raise SystemExit(f"{target} contains reversed IT 140 managed markers")
if start in original:
    before = original.split(start, 1)[0].rstrip("\n")
    after = original.split(end, 1)[1].lstrip("\n")
    updated = (before + "\n\n" if before else "") + block
    if after:
        updated += "\n" + after
else:
    updated = original
    if updated and not updated.endswith("\n"):
        updated += "\n"
    if updated:
        updated += "\n"
    updated += block
if updated == original:
    print("unchanged")
    raise SystemExit(0)
target.parent.mkdir(parents=True, exist_ok=True)
temporary = target.with_name(target.name + ".it140.tmp")
try:
    temporary.write_text(updated, encoding="utf-8", newline="\n")
    temporary.replace(target)
finally:
    if temporary.exists():
        temporary.unlink()
print("changed")
PY
}

refresh_vscode_settings() {
    local python_path
    python_path="$(resolve_python)"
    "$python_path" - "$MANIFEST_PATH" "$PLATFORM_ID" "$VSCODE_SETTINGS_FILE" \
        "$VENV_DIR/bin/python" <<'PY'
import json
import pathlib
import sys

manifest_path, platform_id, settings_path, interpreter_path = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
settings_file = pathlib.Path(settings_path)
settings = json.loads(settings_file.read_text(encoding="utf-8"))
if not isinstance(settings, dict):
    raise SystemExit("VS Code settings root is not an object")
bindings = manifest["platforms"][platform_id]["course_ide_bindings"]
managed = {}
for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
    profile = manifest["managed_settings"][profile_id]
    if platform_id in profile.get("platform_ids", []):
        managed.update(profile["values"])
managed.update({
    "python.defaultInterpreterPath": interpreter_path,
    "python.testing.pytestArgs": ["."],
    "terminal.integrated.defaultProfile.osx": "zsh",
    "terminal.integrated.cwd": "${userHome}/it140",
})

def deep_merge(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = value

deep_merge(settings, managed)
ignored = settings.get("settingsSync.ignoredSettings", [])
if not isinstance(ignored, list):
    raise SystemExit("settingsSync.ignoredSettings must be an array when present")
if "python.defaultInterpreterPath" not in ignored:
    ignored.append("python.defaultInterpreterPath")
settings["settingsSync.ignoredSettings"] = ignored
temporary = settings_file.with_name(settings_file.name + ".it140.tmp")
try:
    temporary.write_text(json.dumps(settings, indent=4, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    json.loads(temporary.read_text(encoding="utf-8"))
    temporary.replace(settings_file)
finally:
    if temporary.exists():
        temporary.unlink()
PY
}

validate_vscode_settings() {
    local python_path
    python_path="$(resolve_python 2>/dev/null || true)"
    [[ -x "$python_path" && -r "$VSCODE_SETTINGS_FILE" ]] || return 1
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

refresh_managed_integrations() {
    print_header "Step 5: Refresh Managed User Settings and Integrations"
    local shell_file environment_result
    for shell_file in "$HOME/.zprofile" "$HOME/.zshrc"; do
        environment_result=""
        if environment_result="$(upsert_managed_environment_block "$shell_file")"; then
            if [[ "$environment_result" == "changed" ]]; then
                CHANGED=true
                print_success "Managed terminal environment refreshed in ${shell_file}."
            else
                print_success "Managed terminal environment is already correct in ${shell_file}."
            fi
        else
            print_warning "The managed terminal environment could not be refreshed in ${shell_file}."
            PARTIAL=true
        fi
    done
    local vscode_cli_dir="/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
    export PATH="${vscode_cli_dir}:${VENV_DIR}/bin:${PLATFORM_SCRIPT_DIR}:$PATH"
    hash -r 2>/dev/null || rehash

    local key expected actual
    while IFS=$'\t' read -r key expected; do
        [[ -n "$key" ]] || continue
        actual="$(git config --global --get "$key" 2>/dev/null || true)"
        if [[ "$actual" != "$expected" ]]; then
            git config --global "$key" "$expected"
            CHANGED=true
            print_success "Managed Git setting was refreshed: ${key}"
        else
            print_success "Managed Git setting is already correct: ${key}"
        fi
    done < <(manifest_lines git_settings)

    if [[ -r "$VSCODE_SETTINGS_FILE" ]]; then
        local before_hash after_hash
        before_hash="$(/usr/bin/shasum -a 256 "$VSCODE_SETTINGS_FILE" | awk '{print $1}')"
        if refresh_vscode_settings; then
            after_hash="$(/usr/bin/shasum -a 256 "$VSCODE_SETTINGS_FILE" | awk '{print $1}')"
            if [[ "$before_hash" != "$after_hash" ]]; then
                CHANGED=true
                print_success "Managed VS Code settings were refreshed."
            else
                print_success "Managed VS Code settings are already correct."
            fi
        else
            print_warning "Managed VS Code settings were not refreshed; the existing file was preserved."
            PARTIAL=true
        fi
    else
        print_notice "VS Code user settings are not present; config_mac.sh will create them."
    fi

    mkdir -p "$HOME/Desktop"
    if [[ -L "$DESKTOP_SHORTCUT" ]]; then
        if [[ "$(/usr/bin/readlink "$DESKTOP_SHORTCUT")" == "$COURSE_ROOT" ]]; then
            print_success "The IT 140 desktop shortcut is already correct."
        else
            print_warning "The existing desktop shortcut named 'IT 140' points elsewhere and was preserved."
        fi
    elif [[ -e "$DESKTOP_SHORTCUT" ]]; then
        print_warning "A desktop item named 'IT 140' already exists and was preserved."
    else
        ln -s "$COURSE_ROOT" "$DESKTOP_SHORTCUT"
        CHANGED=true
        print_success "The IT 140 desktop course-folder shortcut was created."
    fi
}

safe_cleanup() {
    print_header "Step 6: Safe Homebrew Cleanup"
    local item
    while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        brew cleanup "$item" >/dev/null 2>&1 || print_warning "Homebrew cleanup could not complete for ${item}."
    done < <(manifest_lines system_formulae)
    while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        brew cleanup "$item" >/dev/null 2>&1 || print_warning "Homebrew cleanup could not complete for ${item}."
    done < <(manifest_lines system_casks)
    print_success "Cleanup was limited to manifest-declared Homebrew items."
}

configuration_complete() {
    gh auth status --hostname github.com >/dev/null 2>&1 || return 1
    [[ -n "$(git config --global user.name 2>/dev/null || true)" ]] || return 1
    local git_email shell_file
    git_email="$(git config --global user.email 2>/dev/null || true)"
    printf '%s\n' "$git_email" \
        | grep -Eq '^[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$' || return 1
    for shell_file in "$HOME/.zprofile" "$HOME/.zshrc"; do
        [[ -r "$shell_file" ]] \
            && grep -Fq "$MANAGED_ENV_START" "$shell_file" \
            && grep -Fq '$HOME/it140/.venv/bin' "$shell_file" \
            && grep -Fq '$HOME/it140/scripts/mac' "$shell_file" || return 1
    done
    [[ -x "$VENV_DIR/bin/python" ]] || return 1
    validate_vscode_settings >/dev/null 2>&1 || return 1
    return 0
}

detect_workflow() {
    if configuration_complete; then
        WORKFLOW_NAME="Periodic maintenance"
        CONFIGURATION_COMPLETE=true
    else
        WORKFLOW_NAME="First use or reset environment"
        CONFIGURATION_COMPLETE=false
        print_notice "User configuration is incomplete; the summary will direct you to config_mac.sh."
    fi
}

post_validate() {
    print_header "Step 7: Post-Update Verification"
    local failed=0 formula cask package extension command_name python_path code_cli
    python_path="$(resolve_python)"
    code_cli="$(resolve_code_cli)"

    validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH" >/dev/null || {
        print_error "The active manifest pair failed post-update validation."
        failed=1
    }
    while IFS= read -r formula; do
        [[ -n "$formula" ]] || continue
        brew list --formula "$formula" >/dev/null 2>&1 || {
            print_error "Required formula is missing after update: ${formula}"
            failed=1
        }
    done < <(manifest_lines system_formulae)
    while IFS= read -r cask; do
        [[ -n "$cask" ]] || continue
        brew list --cask "$cask" >/dev/null 2>&1 || {
            print_error "Required cask is missing after update: ${cask}"
            failed=1
        }
    done < <(manifest_lines system_casks)
    while IFS= read -r command_name; do
        [[ -n "$command_name" ]] || continue
        case "$command_name" in
            python3.12) [[ -x "$python_path" ]] || { print_error "Python 3.12 is unavailable after update."; failed=1; } ;;
            code) [[ -x "$code_cli" ]] || { print_error "VS Code CLI is unavailable after update."; failed=1; } ;;
            *) command -v "$command_name" >/dev/null 2>&1 || { print_error "Required command is missing after update: ${command_name}"; failed=1; } ;;
        esac
    done < <(manifest_lines system_commands)
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1 || {
            print_error "Required Python package is missing after update: ${package}"
            failed=1
        }
    done < <(manifest_lines venv_packages)

    local installed_extensions
    installed_extensions="$(NODE_NO_WARNINGS=1 "$code_cli" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r extension; do
        [[ -n "$extension" ]] || continue
        if ! printf '%s\n' "$installed_extensions" \
            | grep -Fxq "$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"; then
            print_error "Required extension is missing after update: ${extension}"
            failed=1
        fi
    done < <(manifest_lines extensions)

    local script_name
    for script_name in setup_mac.sh config_mac.sh verify_mac.sh update_mac.sh; do
        if [[ ! -x "$PLATFORM_SCRIPT_DIR/$script_name" ]] \
            || ! /bin/zsh -n "$PLATFORM_SCRIPT_DIR/$script_name"; then
            print_error "Managed script failed post-update validation: ${script_name}"
            failed=1
        fi
    done
    if [[ -r "$VSCODE_SETTINGS_FILE" ]] && ! validate_vscode_settings; then
        print_error "Managed VS Code settings are incorrect after update."
        failed=1
    fi

    if (( failed )); then
        FAILURES=$(( FAILURES + failed ))
        PARTIAL=true
        print_error "One or more required post-update checks failed."
    else
        print_success "Required software and managed assets passed post-update checks."
    fi

    if configuration_complete; then
        CONFIGURATION_COMPLETE=true
    else
        CONFIGURATION_COMPLETE=false
    fi
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    local result="PASS"
    local next_step
    local exit_code=0
    if [[ "$PARTIAL" == true || $FAILURES -gt 0 ]]; then
        result="PARTIAL"
        exit_code=7
        next_step="Correct the reported problems, then rerun update_mac.sh."
    elif (( WARNINGS > 0 )); then
        result="PASS WITH WARNINGS"
    fi
    if (( exit_code == 0 )); then
        if [[ "$CONFIGURATION_COMPLETE" == true ]]; then
            next_step="Close this Terminal, open a new Terminal, and run verify_mac.sh."
        else
            next_step="Close this Terminal, open a new Terminal, and run config_mac.sh."
        fi
    fi

    print_header "UPDATE SUMMARY"
    printf 'Result          : %s\n' "$result"
    printf 'Workflow        : %s\n' "$WORKFLOW_NAME"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'macOS           : %s\n' "$(/usr/bin/sw_vers -productVersion)"
    printf 'Architecture    : %s\n' "$(uname -m)"
    printf 'Changes applied : %s\n' "$CHANGED"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Failures        : %s\n' "$FAILURES"
    printf 'Restart required: %s\n' "$APPLE_UPDATE_INSTALLED"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Next step       : %s\n' "$next_step"
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : %s\n' "$exit_code"
    if [[ "$APPLE_UPDATE_INSTALLED" == true ]]; then
        print_notice "Save work and restart macOS if Apple requests it before the next step."
    fi
    if (( exit_code == 0 )); then
        print_success "The IT 140 macOS update completed successfully."
    else
        print_notice "The update completed only partially."
    fi
    return "$exit_code"
}

main() {
    parse_options "$@"
    initialize_log
    trap cleanup EXIT
    trap on_error ERR
    trap on_interrupt INT TERM

    print_header "IT 140 macOS MANAGED UPDATE"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Maintain approved software and course-managed assets."
    print_info "Log file       : $LOG_FILE"
    print_notice "The script will not install a different major macOS release."
    print_notice "Keep this Terminal open until the script displays its final summary."

    check_platform_and_user
    initialize_homebrew_environment || {
        print_error "Homebrew is unavailable. Run setup_mac.sh first."
        exit 1
    }
    acquire_lock
    restore_interrupted_manifest_activation
    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || {
        print_error "The installed manifest or schema is missing."
        exit 5
    }
    check_supported_release
    INSTALLED_MANIFEST_RELEASE="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH")" || exit 5
    print_success "Installed manifest release $INSTALLED_MANIFEST_RELEASE validated."
    check_prerequisites
    detect_workflow

    synchronize_course_assets
    update_current_macos_release
    update_homebrew_software
    update_user_tools
    refresh_managed_integrations
    safe_cleanup
    post_validate

    trap - ERR INT TERM
    local final_code=0
    finish || final_code=$?
    print_closing_notices
    return "$final_code"
}

main "$@"
