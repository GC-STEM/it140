#!/bin/zsh
#
# IT 140 macOS system setup and repair script
#
# Traceability: SET-FR-001 through SET-FR-012; SET-DES-001 through SET-DES-012
# Scope: Xcode Command Line Tools, Homebrew, and manifest-declared system software.
# Excludes: Provider authentication, Git identity, user tools, IDE settings,
#           IDE extensions, and student-owned course work.

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
readonly LOG_FILE="${LOG_DIR}/setup_${PLATFORM_ABBREVIATION}_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_PARENT="${HOME}/Library/Caches"
readonly LOCK_DIR="${LOCK_PARENT}/it140-${PLATFORM_ABBREVIATION}-mutation.lock"

NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
APPLE_UPDATE_INSTALLED=false
LOCK_HELD=false
WARNINGS=0
START_EPOCH="$(date +%s)"
TEMP_PATHS=()

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
Usage: setup_mac.sh [--help] [--version] [--noninteractive]
                    [--deployment-profile macos_bare_metal]

Installs or repairs the manifest-declared system layer for the IT 140 macOS
course environment. Run as the intended macOS user, not with sudo.

The initial supported macOS implementation targets Apple Silicon. Homebrew may
request administrator authorization during its first installation.

Log directory: ~/it140/logs/
USAGE
}

cleanup() {
    set +e
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
    print_error "Setup stopped near line ${LINENO:-unknown} with exit status ${status}."
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
    print_error "Setup was interrupted."
    print_error "Rerun setup_mac.sh to repair the system layer."
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

manifest_raw() {
    /usr/bin/plutil -extract "$1" raw -o - "$MANIFEST_PATH"
}

validate_manifest_bootstrap() {
    [[ -r "$MANIFEST_PATH" ]] || {
        print_error "The course manifest is missing: $MANIFEST_PATH"
        return 1
    }
    [[ -r "$SCHEMA_PATH" ]] || {
        print_error "The manifest schema is missing: $SCHEMA_PATH"
        return 1
    }

    /usr/bin/plutil -lint "$MANIFEST_PATH" >/dev/null
    /usr/bin/plutil -lint "$SCHEMA_PATH" >/dev/null

    [[ "$(manifest_raw schema_version)" == "1.0" ]] || {
        print_error "The manifest schema version is unsupported."
        return 1
    }
    [[ "$(manifest_raw policy.allow_os_release_upgrade)" == "false" ]] || {
        print_error "The manifest attempts to permit a macOS release upgrade."
        return 1
    }
    [[ "$(manifest_raw platforms.macos.enabled)" == "true" ]] || {
        print_error "The macOS platform is not enabled."
        return 1
    }
    [[ "$(manifest_raw deployment_profiles.${REQUESTED_PROFILE}.enabled)" == "true" ]] || {
        print_error "The requested macOS deployment profile is not enabled."
        return 1
    }
    [[ "$(manifest_raw \
        "deployment_profiles.${REQUESTED_PROFILE}.platform_id")" == "$PLATFORM_ID" ]] || {
        print_error "The requested deployment profile does not reference macOS."
        return 1
    }
}

check_platform() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        print_error "This script supports macOS only."
        exit 2
    fi
    if (( EUID == 0 )); then
        print_error "Do not run setup_mac.sh with sudo."
        print_error "Run it from the intended macOS user account."
        exit 2
    fi
    if [[ "$REQUESTED_PROFILE" != "$DEPLOYMENT_PROFILE_ID" ]]; then
        print_error "Unsupported deployment profile: $REQUESTED_PROFILE"
        exit 2
    fi

    local product_version major architecture releases_json architectures_json
    product_version="$(/usr/bin/sw_vers -productVersion)"
    major="${product_version%%.*}"
    architecture="$(uname -m)"
    releases_json="$(/usr/bin/plutil -extract platforms.macos.os.releases json \
        -o - "$MANIFEST_PATH")"
    architectures_json="$(/usr/bin/plutil -extract platforms.macos.os.architectures json \
        -o - "$MANIFEST_PATH")"

    if ! printf '%s\n' "$releases_json" \
        | grep -Eq "\"release_id\"[[:space:]]*:[[:space:]]*\"${major}\""; then
        print_error "macOS ${product_version} is not approved by the current manifest."
        exit 2
    fi
    if ! printf '%s\n' "$architectures_json" \
        | grep -Eq "\"${architecture}\""; then
        print_error "Architecture ${architecture} is not enabled for macOS."
        exit 2
    fi
    if [[ "$(manifest_raw deployment_profiles.${REQUESTED_PROFILE}.architecture)" \
        != "$architecture" ]]; then
        print_error "The selected deployment profile does not match ${architecture}."
        exit 2
    fi
}

check_disk_space() {
    local minimum available_kb available
    minimum="$(manifest_raw policy.minimum_free_space_bytes)"
    available_kb="$(df -Pk "$HOME" | awk 'NR == 2 {print $4}')"
    available=$(( available_kb * 1024 ))
    if (( available < minimum )); then
        print_error "At least $(( minimum / 1024 / 1024 / 1024 )) GB of free space is required."
        print_error "Available space: $(( available / 1024 / 1024 / 1024 )) GB."
        exit 1
    fi
}

check_network() {
    if ! /usr/bin/curl -fsSIL --connect-timeout 10 --max-time 30 \
        https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
        >/dev/null; then
        print_error "The Homebrew installer source could not be reached."
        exit 4
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

ensure_command_line_tools() {
    print_header "Step 1: Xcode Command Line Tools"

    if /usr/bin/xcode-select -p >/dev/null 2>&1 \
        && /usr/bin/xcrun --find clang >/dev/null 2>&1; then
        print_success "Xcode Command Line Tools are available."
        return
    fi

    if [[ "$NONINTERACTIVE" == true ]]; then
        print_error "Xcode Command Line Tools require interactive installation."
        print_error "Run xcode-select --install, complete the Apple installer, and rerun setup."
        exit 6
    fi

    print_notice "macOS will open the Apple Command Line Tools installer."
    print_notice "Complete the installer before returning to this Terminal window."
    /usr/bin/xcode-select --install >/dev/null 2>&1 || true

    printf '[ACTION REQUIRED] Press Enter after installation, or type C to cancel: '
    local response
    IFS= read -r response
    response="$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')"
    if [[ "$response" == "c" || "$response" == "cancel" ]]; then
        exit 6
    fi

    if ! /usr/bin/xcode-select -p >/dev/null 2>&1 \
        || ! /usr/bin/xcrun --find clang >/dev/null 2>&1; then
        print_error "Xcode Command Line Tools are still unavailable."
        exit 1
    fi

    CHANGED=true
    print_success "Xcode Command Line Tools are available."
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
        print_error "Apple Software Update could not complete its check."
        exit 4
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
            print_error "Apple updates require administrator authorization."
            exit 3
        fi
    else
        print_notice "macOS may request administrator authorization for Apple updates."
        sudo -v || exit 3
    fi

    for label in "${safe_labels[@]}"; do
        print_info "Installing approved Apple update: $label"
        if sudo /usr/sbin/softwareupdate --install "$label"; then
            CHANGED=true
            APPLE_UPDATE_INSTALLED=true
            print_success "Apple update installed: $label"
        else
            print_error "Apple update could not be installed: $label"
            exit 4
        fi
    done
}

ensure_homebrew() {
    print_header "Step 3: Homebrew"

    if initialize_homebrew_environment; then
        print_success "Homebrew is already installed."
        return
    fi

    print_notice "Homebrew will explain its changes and may request administrator authorization."
    local installer_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    if [[ "$NONINTERACTIVE" == true ]]; then
        if ! NONINTERACTIVE=1 /bin/bash -c \
            "$(/usr/bin/curl -fsSL "$installer_url")"; then
            exit 3
        fi
    else
        /bin/bash -c "$(/usr/bin/curl -fsSL "$installer_url")"
    fi

    if ! initialize_homebrew_environment; then
        print_error "Homebrew installation completed without an available brew command."
        exit 1
    fi

    CHANGED=true
    print_success "Homebrew is installed and available."
}

manifest_package() {
    local role="$1"
    manifest_raw "platforms.macos.course_ide_bindings.${role}.package_identifier"
}

install_or_upgrade_formula() {
    local formula="$1"

    if brew list --formula "$formula" >/dev/null 2>&1; then
        if brew outdated --formula "$formula" | grep -Fxq "$formula"; then
            retry_operation "Homebrew upgrade for ${formula}" brew upgrade "$formula" \
                || exit 4
            CHANGED=true
            print_success "${formula} was upgraded."
        else
            print_success "${formula} is already current."
        fi
    else
        retry_operation "Homebrew installation for ${formula}" brew install "$formula" \
            || exit 4
        CHANGED=true
        print_success "${formula} was installed."
    fi
}

install_or_upgrade_cask() {
    local cask="$1"

    if brew list --cask "$cask" >/dev/null 2>&1; then
        if brew outdated --cask "$cask" | grep -Fxq "$cask"; then
            retry_operation "Homebrew cask upgrade for ${cask}" \
                brew upgrade --cask --no-quit "$cask" || exit 4
            CHANGED=true
            print_success "${cask} was upgraded."
        else
            print_success "${cask} is already current."
        fi
    else
        retry_operation "Homebrew cask installation for ${cask}" \
            brew install --cask "$cask" || exit 4
        CHANGED=true
        print_success "${cask} was installed."
    fi
}

install_system_software() {
    print_header "Step 4: Course IDE System Software"

    retry_operation "Homebrew metadata update" brew update || exit 4

    local -a formulae
    formulae=(
        "$(manifest_package version_control_system)"
        "$(manifest_package source_hosting_client)"
        "$(manifest_package programming_language_runtime)"
    )

    local formula
    for formula in "${formulae[@]}"; do
        [[ -n "$formula" ]] || continue
        install_or_upgrade_formula "$formula"
    done

    local ide_cask
    ide_cask="$(manifest_package source_code_ide)"
    install_or_upgrade_cask "$ide_cask"
}

resolve_python() {
    if command -v python3.12 >/dev/null 2>&1; then
        command -v python3.12
        return
    fi
    local prefix
    prefix="$(brew --prefix "$(manifest_package programming_language_runtime)")"
    printf '%s/bin/python3.12\n' "$prefix"
}

resolve_code_cli() {
    if command -v code >/dev/null 2>&1; then
        command -v code
        return
    fi
    printf '%s\n' "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
}

validate_installed_manifest() {
    local python_path
    python_path="$(resolve_python)"
    [[ -x "$python_path" ]] || {
        print_error "Python 3.12 is unavailable after installation."
        exit 1
    }

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

manifest = json.loads(
    pathlib.Path(manifest_path).read_text(encoding="utf-8"),
    object_pairs_hook=no_duplicates,
)
schema = json.loads(
    pathlib.Path(schema_path).read_text(encoding="utf-8"),
    object_pairs_hook=no_duplicates,
)
if manifest.get("schema_version") != "1.0":
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

post_validate() {
    print_header "Step 5: System-Layer Verification"

    local python_path code_cli
    python_path="$(resolve_python)"
    code_cli="$(resolve_code_cli)"

    command -v brew >/dev/null 2>&1 || {
        print_error "Homebrew is unavailable."
        exit 7
    }
    command -v git >/dev/null 2>&1 || {
        print_error "Git is unavailable."
        exit 7
    }
    command -v gh >/dev/null 2>&1 || {
        print_error "GitHub CLI is unavailable."
        exit 7
    }
    [[ -x "$python_path" ]] || {
        print_error "Python 3.12 is unavailable."
        exit 7
    }
    [[ -x "$code_cli" ]] || {
        print_error "The Visual Studio Code command-line interface is unavailable."
        exit 7
    }

    local python_version
    python_version="$("$python_path" -c \
        'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    [[ "$python_version" == "3.12" ]] || {
        print_error "Python 3.12 was expected; detected ${python_version}."
        exit 7
    }

    print_success "Required system components are installed and usable."
    printf 'Homebrew     : %s\n' "$(brew --version | head -n 1)"
    printf 'Git          : %s\n' "$(git --version)"
    printf 'GitHub CLI   : %s\n' "$(gh --version | head -n 1)"
    printf 'Python       : %s\n' "$("$python_path" --version 2>&1)"
    printf 'VS Code      : %s\n' "$("$code_cli" --version | head -n 1)"

    if ! brew doctor >/dev/null 2>&1; then
        print_warning "Homebrew reported diagnostic warnings. Review the log before deployment."
    fi
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    local result="PASS"
    (( WARNINGS > 0 )) && result="PASS WITH WARNINGS"

    print_header "SETUP SUMMARY"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'macOS           : %s\n' "$(/usr/bin/sw_vers -productVersion)"
    printf 'Architecture    : %s\n' "$(uname -m)"
    printf 'Changes applied : %s\n' "$CHANGED"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    if [[ "$APPLE_UPDATE_INSTALLED" == true ]]; then
        printf 'Restart guidance: Save work and restart if macOS requests it.\n'
    else
        printf 'Restart guidance: No Apple update was installed by this run.\n'
    fi
    printf 'Next step       : Run configure_mac.sh\n'
    printf 'Log file        : %s\n' "$LOG_FILE"
    print_success "The IT 140 macOS system setup completed successfully."
}

main() {
    parse_options "$@"
    initialize_log
    trap cleanup EXIT
    trap on_error ERR
    trap on_interrupt INT TERM

    print_header "IT 140 macOS SYSTEM SETUP"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Install or repair system-level course IDE components."
    print_info "Log file       : $LOG_FILE"
    print_notice "This script does not configure Git identity, provider login, or user settings."

    validate_manifest_bootstrap || exit 5
    check_platform
    check_disk_space
    check_network
    acquire_lock

    BOOTSTRAP_MANIFEST_RELEASE="$(manifest_raw automation_release)"
    print_success "Manifest release $BOOTSTRAP_MANIFEST_RELEASE passed bootstrap validation."

    ensure_command_line_tools
    update_current_macos_release
    ensure_homebrew
    install_system_software

    MANIFEST_RELEASE="$(validate_installed_manifest)" || exit 5
    print_success "Manifest release $MANIFEST_RELEASE passed installed validation."

    post_validate
    finish

    trap - ERR INT TERM
}

main "$@"
