#!/bin/zsh
#
# IT 140 macOS managed update and repair script
#
# Traceability: UPD-FR-001 through UPD-FR-016; UPD-DES-001 through UPD-DES-016
# Scope: Approved automation assets, Homebrew software, user-scoped course tools,
#        required IDE extensions, managed settings, and safe maintenance.
# Excludes: macOS major-version upgrades, student-owned course work, Git history,
#           optional extension removal, and unvalidated asset replacement.

set -euo pipefail
umask 077

readonly SCRIPT_VERSION="2026.07.25.2"
readonly PLATFORM_ID="macos"
readonly PLATFORM_ABBREVIATION="mac"
readonly DEPLOYMENT_PROFILE_ID="macos_bare_metal"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly PLATFORM_SCRIPT_DIR="${SCRIPT_ROOT}/mac"
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

NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
PARTIAL=false
APPLE_UPDATE_INSTALLED=false
LOCK_HELD=false
WARNINGS=0
START_EPOCH="$(date +%s)"
TEMP_PATHS=()
STAGING_ROOT=""

print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

print_info() { printf '[INFO] %s\n' "$1"; }
print_success() { printf '[SUCCESS] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }
print_warning() {
    printf '[WARNING] %s\n' "$1"
    WARNINGS=$(( WARNINGS + 1 ))
}
print_error() { printf '[ERROR] %s\n' "$1" >&2; }

usage() {
    cat <<'USAGE'
Usage: update_mac.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile macos_bare_metal]

Synchronizes approved IT 140 automation assets and updates manifest-declared
Homebrew software, course Python tools, VS Code extensions, and managed settings.

The script installs Apple updates that it can classify as belonging to the
current macOS major release and skips labels for a different major release.

Log directory: ~/it140/logs/
USAGE
}

restore_interrupted_manifest_activation() {
    set +e
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
    local path
    for path in "${TEMP_PATHS[@]}"; do
        [[ -n "$path" ]] && rm -rf "$path"
    done
    if [[ "$LOCK_HELD" == true && -d "$LOCK_DIR" ]]; then
        rm -rf "$LOCK_DIR"
    fi
}

on_error() {
    local status=$?
    trap - ERR
    set +e
    print_error "Update stopped near line ${LINENO:-unknown} with exit status ${status}."
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

initialize_homebrew_environment() {
    if [[ "$(uname -m)" == "arm64" ]]; then
        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            return 0
        fi
        if command -v brew >/dev/null 2>&1 \
            && [[ "$(brew --prefix 2>/dev/null || true)" == "/opt/homebrew" ]]; then
            eval "$(brew shellenv)"
            return 0
        fi
        return 1
    fi

    if [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
        return 0
    fi
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
    local manifest_path="$1"
    local schema_path="$2"
    local python_path
    python_path="$(resolve_python)" || {
        print_error "Python 3.12 is unavailable. Run setup_mac.sh first."
        return 1
    }

    "$python_path" - "$manifest_path" "$schema_path" "$PLATFORM_ID" \
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
if not profile or not profile.get("enabled"):
    raise SystemExit("macOS deployment profile is not enabled")
if profile.get("platform_id") != platform_id:
    raise SystemExit("deployment profile platform mismatch")
if architecture not in platform["os"]["architectures"]:
    raise SystemExit("unsupported architecture")
if profile.get("architecture") != architecture:
    raise SystemExit("deployment profile architecture mismatch")
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
    if [[ "$(uname -m)" != "arm64" ]]; then
        print_error "The initial macOS release supports Apple Silicon only."
        print_error "Detected architecture: $(uname -m)"
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
    releases_json="$(/usr/bin/plutil -extract platforms.macos.os.releases json \
        -o - "$MANIFEST_PATH")" || exit 5
    profile_architecture="$(/usr/bin/plutil -extract \
        "deployment_profiles.${REQUESTED_PROFILE}.architecture" raw \
        -o - "$MANIFEST_PATH")" || exit 5

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

    local python_path code_cli
    python_path="$(resolve_python 2>/dev/null || true)"
    code_cli="$(resolve_code_cli 2>/dev/null || true)"

    for command_name in git gh; do
        command -v "$command_name" >/dev/null 2>&1 || {
            print_error "Required command is unavailable: $command_name"
            print_error "Run setup_mac.sh first."
            exit 1
        }
    done
    [[ -x "$python_path" ]] || {
        print_error "Python 3.12 is unavailable. Run setup_mac.sh first."
        exit 1
    }
    [[ -x "$code_cli" ]] || {
        print_error "Visual Studio Code is unavailable. Run setup_mac.sh first."
        exit 1
    }

    if pgrep -x "Visual Studio Code" >/dev/null 2>&1; then
        print_notice "Visual Studio Code is open. Close and reopen it after the update."
    fi
}

acquire_lock() {
    mkdir -p "$LOCK_PARENT"

    if mkdir "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        LOCK_HELD=true
        return
    fi

    local existing_pid=""
    [[ -r "$LOCK_DIR/pid" ]] && existing_pid="$(cat "$LOCK_DIR/pid")"
    case "$existing_pid" in
        ''|*[!0-9]*)
            ;;
        *)
            if kill -0 "$existing_pid" 2>/dev/null; then
                print_error "Another IT 140 macOS setup, configure, or update operation is running."
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

version_at_least_current() {
    local file="$1"
    local python_path
    python_path="$(resolve_python)"

    "$python_path" - "$file" "$SCRIPT_VERSION" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'^(?:readonly\s+)?SCRIPT_VERSION="([^"]+)"', text, re.MULTILINE)
if not match:
    raise SystemExit(1)

def key(value):
    return tuple(int(item) for item in re.findall(r"\d+", value))

raise SystemExit(key(match.group(1)) < key(sys.argv[2]))
PY
}

validate_staged_file() {
    local file="$1"
    local mode="$2"

    if [[ "$mode" == "0755" ]]; then
        /bin/zsh -n "$file"
    elif [[ "$file" == *.json || "$file" == *.json.it140.new ]]; then
        "$(resolve_python)" -m json.tool "$file" >/dev/null
    fi
}

atomic_install_file() {
    local source="$1"
    local destination="$2"
    local mode="$3"
    local directory temp backup had_previous=false

    directory="$(dirname "$destination")"
    mkdir -p "$directory"
    temp="${destination}.it140.new"
    backup="${destination}.it140.previous"

    /usr/bin/install -m "$mode" "$source" "$temp"
    if ! validate_staged_file "$temp" "$mode"; then
        rm -f "$temp"
        print_error "A staged file failed validation: $(basename "$destination")"
        return 1
    fi

    if [[ -f "$destination" ]]; then
        cp -p "$destination" "$backup"
        had_previous=true
    fi

    if ! mv -f "$temp" "$destination"; then
        rm -f "$temp"
        print_error "Could not activate: $(basename "$destination")"
        return 1
    fi

    if ! validate_staged_file "$destination" "$mode"; then
        if [[ "$had_previous" == true && -f "$backup" ]]; then
            mv -f "$backup" "$destination"
        else
            rm -f "$destination"
        fi
        print_error "Activated-file validation failed; the prior file was restored."
        return 1
    fi

    rm -f "$backup"
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

    rm -f "$MANIFEST_ACTIVATION_MARKER"
    rm -f "$MANIFEST_BACKUP_PATH" "$SCHEMA_BACKUP_PATH"
    CHANGED=true
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
    if ! retry_operation "Course repository retrieval" \
        clone_course_repository "$clone_dir" "$repository"; then
        exit 4
    fi

    local candidate_manifest="${clone_dir}/scripts/.manifest/it140_manifest.json"
    local candidate_schema="${clone_dir}/scripts/.manifest/it140_manifest.schema.json"
    if [[ ! -r "$candidate_manifest" || ! -r "$candidate_schema" ]]; then
        print_error "The staged repository does not contain the manifest and schema."
        exit 5
    fi

    local candidate_release
    candidate_release="$(validate_manifest_pair "$candidate_manifest" "$candidate_schema")" \
        || exit 5
    print_success "Staged manifest release $candidate_release validated."

    activate_manifest_pair "$candidate_manifest" "$candidate_schema" || exit 5
    print_success "The course manifest and schema were activated transactionally."

    local script_name source_script
    for script_name in setup_mac.sh config_mac.sh verify_mac.sh update_mac.sh; do
        source_script="${clone_dir}/scripts/mac/${script_name}"
        if [[ ! -r "$source_script" ]]; then
            print_warning \
                "The repository lacks ${script_name}; the installed copy was preserved."
            PARTIAL=true
            continue
        fi
        if version_at_least_current "$source_script"; then
            if atomic_install_file "$source_script" \
                "${PLATFORM_SCRIPT_DIR}/${script_name}" 0755; then
                print_success "${script_name} synchronized."
            else
                PARTIAL=true
            fi
        else
            print_warning \
                "${script_name} is older than this updater; the installed copy was preserved."
            PARTIAL=true
        fi
    done

    MANIFEST_RELEASE="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH")" \
        || exit 5
    print_success "Active manifest release $MANIFEST_RELEASE validated."
}

update_homebrew_software() {
    print_header "Step 3: Update Homebrew and System Software"

    retry_operation "Homebrew metadata update" brew update || exit 4

    local formula
    while IFS= read -r formula; do
        [[ -n "$formula" ]] || continue
        if brew list --formula "$formula" >/dev/null 2>&1; then
            if brew outdated --formula "$formula" | grep -Fxq "$formula"; then
                if ! retry_operation "Homebrew upgrade for ${formula}" \
                    brew upgrade "$formula"; then
                    print_warning "Could not update required formula: ${formula}"
                    PARTIAL=true
                else
                    CHANGED=true
                    print_success "Required formula was updated: ${formula}"
                fi
            else
                print_success "Required formula is already current: ${formula}"
            fi
        else
            if ! retry_operation "Homebrew installation for ${formula}" \
                brew install "$formula"; then
                print_warning "Could not install required formula: ${formula}"
                PARTIAL=true
            else
                CHANGED=true
                print_success "Required formula was installed: ${formula}"
            fi
        fi
    done < <(manifest_lines system_formulae)

    local cask
    while IFS= read -r cask; do
        [[ -n "$cask" ]] || continue
        if brew list --cask "$cask" >/dev/null 2>&1; then
            if brew outdated --cask "$cask" | grep -Fxq "$cask"; then
                if ! retry_operation "Homebrew cask upgrade for ${cask}" \
                    brew upgrade --cask --no-quit "$cask"; then
                    print_warning "Could not update required cask: ${cask}"
                    PARTIAL=true
                else
                    CHANGED=true
                    print_success "Required cask was updated: ${cask}"
                fi
            else
                print_success "Required cask is already current: ${cask}"
            fi
        else
            if ! retry_operation "Homebrew cask installation for ${cask}" \
                brew install --cask "$cask"; then
                print_warning "Could not install required cask: ${cask}"
                PARTIAL=true
            else
                CHANGED=true
                print_success "Required cask was installed: ${cask}"
            fi
        fi
    done < <(manifest_lines system_casks)
}

update_user_tools() {
    print_header "Step 4: Update Course Python Tools and VS Code Extensions"

    local python_path code_cli
    python_path="$(resolve_python)"
    code_cli="$(resolve_code_cli)"

    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        print_warning "The course virtual environment was missing and will be repaired."
        "$python_path" -m venv "$VENV_DIR"
        CHANGED=true
    fi

    local -a packages
    packages=()
    local package
    while IFS= read -r package; do
        [[ -n "$package" ]] && packages+=("$package")
    done < <(manifest_lines venv_packages)

    "$VENV_DIR/bin/python" -m pip install --upgrade pip
    if ! "$VENV_DIR/bin/python" -m pip install --upgrade "${packages[@]}"; then
        print_warning "One or more required Python tools could not be updated."
        PARTIAL=true
    else
        CHANGED=true
        print_success "Required course Python tools are current."
    fi

    if NODE_NO_WARNINGS=1 "$code_cli" --update-extensions; then
        print_success \
            "Installed VS Code extensions were updated; optional extensions were preserved."
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

refresh_managed_settings() {
    print_header "Step 5: Refresh Managed User Settings"

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

    if [[ ! -r "$VSCODE_SETTINGS_FILE" ]]; then
        print_warning "VS Code settings are not present; run config_mac.sh."
        PARTIAL=true
        return
    fi

    local python_path before_hash after_hash
    python_path="$(resolve_python)"
    before_hash="$(/usr/bin/shasum -a 256 "$VSCODE_SETTINGS_FILE" | awk '{print $1}')"

    if ! "$python_path" - "$MANIFEST_PATH" "$PLATFORM_ID" \
        "$VSCODE_SETTINGS_FILE" "$VENV_DIR/bin/python" <<'PY'
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
temp = settings_file.with_name(settings_file.name + ".it140.tmp")
try:
    temp.write_text(
        json.dumps(settings, indent=4, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    json.loads(temp.read_text(encoding="utf-8"))
    temp.replace(settings_file)
finally:
    if temp.exists():
        temp.unlink()
PY
    then
        print_warning \
            "Managed VS Code settings were not refreshed; the existing file was preserved."
        PARTIAL=true
    else
        after_hash="$(/usr/bin/shasum -a 256 "$VSCODE_SETTINGS_FILE" | awk '{print $1}')"
        if [[ "$before_hash" != "$after_hash" ]]; then
            CHANGED=true
            print_success "Managed VS Code settings were refreshed."
        else
            print_success "Managed VS Code settings are already correct."
        fi
    fi
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
    done < <(
        sed -nE \
            's/^[[:space:]]*[*-][[:space:]]+Label:[[:space:]]*(.*)$/\1/p' \
            "$output_file"
    )

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
        sudo -v || {
            print_warning "Administrator authorization was not granted."
            PARTIAL=true
            return
        }
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

safe_cleanup() {
    print_header "Step 6: Safe Homebrew Cleanup"

    local item
    while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        brew cleanup "$item" >/dev/null 2>&1 || \
            print_warning "Homebrew cleanup could not complete for ${item}."
    done < <(manifest_lines system_formulae)

    while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        brew cleanup "$item" >/dev/null 2>&1 || \
            print_warning "Homebrew cleanup could not complete for ${item}."
    done < <(manifest_lines system_casks)

    print_success "Safe cleanup was attempted only for manifest-declared Homebrew items."
}

post_validate() {
    print_header "Step 7: Post-Update Verification"

    local failed=0 formula cask package extension key expected actual
    local python_path code_cli
    python_path="$(resolve_python)"
    code_cli="$(resolve_code_cli)"

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

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1 || {
            print_error "Required Python package is missing after update: ${package}"
            failed=1
        }
    done < <(manifest_lines venv_packages)

    local installed_extensions
    installed_extensions="$(NODE_NO_WARNINGS=1 "$code_cli" --list-extensions 2>/dev/null \
        | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r extension; do
        [[ -n "$extension" ]] || continue
        if ! printf '%s\n' "$installed_extensions" \
            | grep -Fxq "$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"; then
            print_error "Required extension is missing after update: ${extension}"
            failed=1
        fi
    done < <(manifest_lines extensions)

    while IFS=$'\t' read -r key expected; do
        [[ -n "$key" ]] || continue
        actual="$(git config --global --get "$key" 2>/dev/null || true)"
        if [[ "$actual" != "$expected" ]]; then
            print_error "Managed Git setting is incorrect after update: ${key}"
            failed=1
        fi
    done < <(manifest_lines git_settings)

    if ! "$python_path" - "$MANIFEST_PATH" "$PLATFORM_ID" \
        "$VSCODE_SETTINGS_FILE" "$VENV_DIR/bin/python" <<'PY'
import json
import pathlib
import sys

manifest_path, platform_id, settings_path, interpreter_path = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
settings = json.loads(pathlib.Path(settings_path).read_text(encoding="utf-8"))
bindings = manifest["platforms"][platform_id]["course_ide_bindings"]
expected = {}
for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
    profile = manifest["managed_settings"][profile_id]
    if platform_id in profile.get("platform_ids", []):
        expected.update(profile["values"])
expected.update({
    "python.defaultInterpreterPath": interpreter_path,
    "python.testing.pytestArgs": ["."],
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
    then
        print_error "Managed VS Code settings are incorrect after update."
        failed=1
    fi

    validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH" >/dev/null || failed=1

    local script_name
    for script_name in setup_mac.sh config_mac.sh verify_mac.sh update_mac.sh; do
        /bin/zsh -n "$PLATFORM_SCRIPT_DIR/$script_name" || {
            print_error "Managed script failed syntax validation: ${script_name}"
            failed=1
        }
    done

    if (( failed )); then
        print_error "Post-update verification failed."
        PARTIAL=true
    else
        print_success "Required software and managed assets passed post-update checks."
    fi
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    local result="PASS"
    if [[ "$PARTIAL" == true ]]; then
        result="PARTIAL"
    elif (( WARNINGS > 0 )); then
        result="PASS WITH WARNINGS"
    fi

    print_header "UPDATE SUMMARY"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "${MANIFEST_RELEASE:-unavailable}"
    printf 'macOS           : %s\n' "$(/usr/bin/sw_vers -productVersion)"
    printf 'Architecture    : %s\n' "$(uname -m)"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Log file        : %s\n' "$LOG_FILE"

    if [[ "$APPLE_UPDATE_INSTALLED" == true ]]; then
        printf 'Restart guidance: Save work and restart if macOS requests it.\n'
    else
        printf 'Restart guidance: No Apple update was installed by this run.\n'
    fi

    if [[ "$PARTIAL" == true ]]; then
        printf 'Next step       : Run verify_mac.sh after correcting warnings.\n'
        print_warning "The update completed only partially."
        return 7
    fi

    printf 'Next step       : Run verify_mac.sh after a restart or any warning.\n'
    print_success "The IT 140 macOS update completed successfully."
    return 0
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
    INSTALLED_MANIFEST_RELEASE="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH")" \
        || exit 5
    print_success "Installed manifest release $INSTALLED_MANIFEST_RELEASE validated."

    check_prerequisites

    synchronize_course_assets
    update_current_macos_release
    update_homebrew_software
    update_user_tools
    refresh_managed_settings
    safe_cleanup
    post_validate

    trap - ERR INT TERM
    finish
}

main "$@"
