#!/bin/zsh
#
# IT 140 macOS user configuration and repair script
#
# Traceability: CFG-FR-001 through CFG-FR-016; CFG-DES-001 through CFG-DES-016
# Scope: Current-user folders, shell PATH, provider authentication, Git identity
#        and settings, course virtual environment, IDE extensions, and settings.
# Excludes: Homebrew installation, system package changes, macOS updates, and
#           student-owned course work.

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
readonly LOG_FILE="${LOG_DIR}/configure_${PLATFORM_ABBREVIATION}_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly VSCODE_SETTINGS_FILE="${HOME}/Library/Application Support/Code/User/settings.json"
readonly LOCK_PARENT="${HOME}/Library/Caches"
readonly LOCK_DIR="${LOCK_PARENT}/it140-${PLATFORM_ABBREVIATION}-mutation.lock"

NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
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

exit_canceled() {
    if [[ "$CHANGED" == true ]]; then
        print_error "Configuration is incomplete because some managed state changed."
        exit 7
    fi
    exit 6
}

usage() {
    cat <<'USAGE'
Usage: configure_mac.sh [--help] [--version] [--noninteractive]
                        [--deployment-profile macos_bare_metal]

Configures or repairs the current user's IT 140 macOS environment. Run from the
student or faculty macOS account that will complete course work, not with sudo.

In noninteractive mode, an existing GitHub CLI login is required and the GitHub
username is used as the Git display name.

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
    print_error "Configuration stopped near line ${LINENO:-unknown} with exit status ${status}."
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
    print_error "Configuration was canceled."
    print_error "Rerun configure_mac.sh to continue."
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

validate_manifest() {
    local python_path
    python_path="$(resolve_python)" || {
        print_error "Python 3.12 is unavailable. Run setup_mac.sh first."
        return 1
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
if "github_com" not in manifest["provider_profiles"]:
    raise SystemExit("required provider profile is unavailable")
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

if query == "system_commands":
    commands = []
    for binding in bindings.values():
        if binding.get("required") and binding.get("installation_scope") == "system":
            commands.extend(binding.get("verification", {}).get("executable_names", []))
    for command in sorted(set(commands)):
        print(command)
elif query == "venv_packages":
    packages = []
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "python_venv_package"):
            packages.append(binding["package_identifier"])
    if bindings.get("code_quality_tool", {}).get("required"):
        packages.append("ruff")
    for package in sorted(set(packages)):
        print(package)
elif query == "extensions":
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "vscode_extension"):
            print(binding["package_identifier"])
elif query == "git_settings":
    for profile_id in bindings["version_control_system"].get("settings_profile_ids", []):
        values = manifest["managed_settings"][profile_id]["values"]
        for key, value in values.items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            print(f"{key}\t{value}")
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
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
        print_error "Do not run configure_mac.sh with sudo."
        print_error "Personal settings must be saved under the intended macOS account."
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

check_disk_space() {
    local minimum available_kb available
    minimum="$(manifest_lines minimum_space)"
    available_kb="$(df -Pk "$HOME" | awk 'NR == 2 {print $4}')"
    available=$(( available_kb * 1024 ))
    if (( available < minimum )); then
        print_error "At least $(( minimum / 1024 / 1024 / 1024 )) GB of free space is required."
        exit 1
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

check_system_layer() {
    initialize_homebrew_environment || {
        print_error "Homebrew is unavailable. Run setup_mac.sh first."
        exit 1
    }

    local python_path code_cli
    python_path="$(resolve_python)" || true
    code_cli="$(resolve_code_cli)" || true

    local failed=0 command_name missing
    while IFS= read -r command_name; do
        [[ -n "$command_name" ]] || continue
        missing=false
        case "$command_name" in
            python3.12)
                [[ -x "$python_path" ]] || missing=true
                ;;
            code)
                [[ -x "$code_cli" ]] || missing=true
                ;;
            *)
                command -v "$command_name" >/dev/null 2>&1 || missing=true
                ;;
        esac
        if [[ "$missing" == true ]]; then
            print_error "Required system command is missing: $command_name"
            failed=1
        fi
    done < <(manifest_lines system_commands)

    if (( failed )); then
        print_error "The system layer is incomplete. Run setup_mac.sh first."
        exit 1
    fi

    print_success "Required system components are present."
}

upsert_managed_environment_block() {
    local profile_file="$HOME/.zprofile"
    local brew_path
    brew_path="$(command -v brew)"

    "$(resolve_python)" - "$profile_file" "$brew_path" \
        "$VENV_DIR/bin" "$PLATFORM_SCRIPT_DIR" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
brew_path, venv_dir, script_dir = sys.argv[2:]
start = "# >>> IT 140 managed environment >>>"
end = "# <<< IT 140 managed environment <<<"
block = (
    f"{start}\n"
    f'eval "$({brew_path} shellenv)"\n'
    'export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:'
    f'{venv_dir}:{script_dir}:$PATH"\n'
    f"{end}\n"
)
original = path.read_text(encoding="utf-8") if path.exists() else ""
if original.count(start) != original.count(end):
    raise SystemExit(
        "The existing ~/.zprofile contains an incomplete IT 140 managed block; "
        "the file was preserved."
    )
if original.count(start) > 1 or original.count(end) > 1:
    raise SystemExit(
        "The existing ~/.zprofile contains duplicate IT 140 managed blocks; "
        "the file was preserved."
    )
if start in original and original.index(start) > original.index(end):
    raise SystemExit(
        "The existing ~/.zprofile has reversed IT 140 block markers; "
        "the file was preserved."
    )

text = original
if start in text and end in text:
    before = text.split(start, 1)[0].rstrip("\n")
    after = text.split(end, 1)[1].lstrip("\n")
    text = (before + "\n\n" if before else "") + block
    if after:
        text += "\n" + after
else:
    if text and not text.endswith("\n"):
        text += "\n"
    if text:
        text += "\n"
    text += block
if text == original:
    print("unchanged")
    raise SystemExit(0)
path.parent.mkdir(parents=True, exist_ok=True)
temp = path.with_name(path.name + ".it140.tmp")
try:
    temp.write_text(text, encoding="utf-8", newline="\n")
    temp.replace(path)
finally:
    if temp.exists():
        temp.unlink()
print("changed")
PY
}

configure_course_folders_and_path() {
    print_header "Step 1: Course Folders and Terminal Environment"

    local folders_changed=false path_result
    [[ -d "$COURSE_ROOT" ]] || folders_changed=true
    [[ -d "$LOG_DIR" ]] || folders_changed=true
    [[ -d "$PLATFORM_SCRIPT_DIR" ]] || folders_changed=true

    mkdir -p "$COURSE_ROOT" "$LOG_DIR" "$PLATFORM_SCRIPT_DIR"
    chmod 0700 "$LOG_DIR"

    path_result="$(upsert_managed_environment_block)"
    local vscode_cli_dir="/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
    export PATH="${vscode_cli_dir}:${VENV_DIR}/bin:${PLATFORM_SCRIPT_DIR}:$PATH"

    setopt local_options null_glob
    local script_path
    for script_path in "$PLATFORM_SCRIPT_DIR"/*_mac.sh; do
        [[ -f "$script_path" ]] && chmod 0755 "$script_path"
    done

    if [[ "$folders_changed" == true || "$path_result" == "changed" ]]; then
        CHANGED=true
        print_success "Course folders and the managed terminal environment were configured."
    else
        print_success "Course folders and the managed terminal environment are already correct."
    fi
    print_success "Course script permissions were verified."
}

configure_provider_identity() {
    print_header "Step 2: GitHub Authentication and Git Identity"
    print_info "Checking GitHub CLI authentication status..."

    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        if [[ "$NONINTERACTIVE" == true ]]; then
            print_error "GitHub authentication is required but interaction is disabled."
            exit_canceled
        fi

        print_notice "GitHub CLI will display a one-time code and open a browser."
        print_notice "Complete the browser steps, then return to this Terminal window."
        printf '[ACTION REQUIRED] Press Enter to begin, or type C to cancel: '
        local response
        IFS= read -r response
        response="$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')"
        if [[ "$response" == "c" || "$response" == "cancel" ]]; then
            exit_canceled
        fi

        if ! gh auth login --hostname github.com --git-protocol https --web; then
            print_error "GitHub authentication was canceled or did not complete."
            exit_canceled
        fi
        CHANGED=true
    fi

    gh auth status --hostname github.com >/dev/null 2>&1 || {
        print_error "GitHub authentication did not complete successfully."
        exit 1
    }
    print_success "GitHub authentication is valid."

    local gh_id gh_user private_email display_name
    gh_id="$(gh api user --jq '.id' 2>/dev/null || true)"
    gh_user="$(gh api user --jq '.login' 2>/dev/null || true)"

    if [[ -z "$gh_id" || -z "$gh_user" ]]; then
        local python_path
        python_path="$(resolve_python)"
        gh_id="$(gh api user | "$python_path" -c \
            'import json,sys; print(json.load(sys.stdin)["id"])')"
        gh_user="$(gh api user | "$python_path" -c \
            'import json,sys; print(json.load(sys.stdin)["login"])')"
    fi

    case "$gh_id" in
        ''|*[!0-9]*)
            print_error "The provider account ID is invalid."
            exit 1
            ;;
    esac
    if ! printf '%s\n' "$gh_user" | grep -Eq '^[A-Za-z0-9-]+$'; then
        print_error "The provider username is invalid."
        exit 1
    fi

    private_email="${gh_id}+${gh_user}@users.noreply.github.com"

    if [[ "$NONINTERACTIVE" == true ]]; then
        display_name="$gh_user"
    else
        print_notice "Your Git display name is public in version-control history."
        printf '[ACTION REQUIRED] Git display name [%s]: ' "$gh_user"
        IFS= read -r display_name
        display_name="${display_name:-$gh_user}"
    fi

    if [[ -z "$display_name" || ${#display_name} -gt 100 \
        || "$display_name" == *$'\n'* || "$display_name" == *$'\r'* ]]; then
        print_error "The Git display name is invalid."
        exit 1
    fi

    local identity_changed=false current_value
    current_value="$(git config --global --get user.name 2>/dev/null || true)"
    if [[ "$current_value" != "$display_name" ]]; then
        git config --global user.name "$display_name"
        identity_changed=true
    fi

    current_value="$(git config --global --get user.email 2>/dev/null || true)"
    if [[ "$current_value" != "$private_email" ]]; then
        git config --global user.email "$private_email"
        identity_changed=true
    fi

    local key value
    while IFS=$'\t' read -r key value; do
        [[ -n "$key" ]] || continue
        current_value="$(git config --global --get "$key" 2>/dev/null || true)"
        if [[ "$current_value" != "$value" ]]; then
            git config --global "$key" "$value"
            identity_changed=true
        fi
    done < <(manifest_lines git_settings)

    if [[ "$identity_changed" == true ]]; then
        CHANGED=true
        print_success "Git identity and course defaults were configured."
    else
        print_success "Git identity and course defaults are already correct."
    fi
    print_info "Git display name : $display_name"
    print_info "Commit identity  : GitHub private noreply identity"
    print_info "GitHub account   : $gh_user"
}

configure_user_tools() {
    print_header "Step 3: Course Python Tools and VS Code Extensions"

    local python_path code_cli
    python_path="$(resolve_python)"
    code_cli="$(resolve_code_cli)"

    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        print_info "Creating the IT 140 course virtual environment..."
        "$python_path" -m venv "$VENV_DIR"
        CHANGED=true
    fi

    local -a venv_packages
    venv_packages=()
    local package
    while IFS= read -r package; do
        [[ -n "$package" ]] && venv_packages+=("$package")
    done < <(manifest_lines venv_packages)

    print_info "Installing or repairing required course Python tools..."
    "$VENV_DIR/bin/python" -m pip install --upgrade pip
    "$VENV_DIR/bin/python" -m pip install --upgrade "${venv_packages[@]}"
    CHANGED=true

    local -a extensions
    extensions=()
    local extension
    while IFS= read -r extension; do
        [[ -n "$extension" ]] && extensions+=("$extension")
    done < <(manifest_lines extensions)

    print_info "Installing missing required VS Code extensions..."
    local installed_extensions
    installed_extensions="$(NODE_NO_WARNINGS=1 "$code_cli" --list-extensions 2>/dev/null \
        | tr '[:upper:]' '[:lower:]')"
    for extension in "${extensions[@]}"; do
        if printf '%s\n' "$installed_extensions" \
            | grep -Fxq "$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"; then
            print_success "Required extension is already installed: ${extension}"
        else
            NODE_NO_WARNINGS=1 "$code_cli" --install-extension "$extension"
            CHANGED=true
            print_success "Required extension was installed: ${extension}"
        fi
    done

    print_success "Required user-scoped tools and extensions are configured."
}

merge_vscode_settings() {
    print_header "Step 4: VS Code Course Settings"

    local python_path before_hash after_hash
    python_path="$(resolve_python)"
    mkdir -p "$(dirname "$VSCODE_SETTINGS_FILE")"
    if [[ -r "$VSCODE_SETTINGS_FILE" ]]; then
        before_hash="$(/usr/bin/shasum -a 256 "$VSCODE_SETTINGS_FILE" | awk '{print $1}')"
    else
        before_hash="missing"
    fi

    "$python_path" - "$MANIFEST_PATH" "$PLATFORM_ID" "$VSCODE_SETTINGS_FILE" \
        "$VENV_DIR/bin/python" "$LOG_DIR" <<'PY'
import json
import pathlib
import sys

manifest_path, platform_id, settings_path, interpreter_path, log_dir = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
settings_file = pathlib.Path(settings_path)
settings_file.parent.mkdir(parents=True, exist_ok=True)

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

existing = {}
if settings_file.exists() and settings_file.stat().st_size:
    try:
        existing = json.loads(settings_file.read_text(encoding="utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        diagnostic = pathlib.Path(log_dir) / "invalid_vscode_settings_diagnostic.txt"
        diagnostic.write_text(
            "The existing VS Code settings file is invalid and was not changed.\n"
            f"Settings path: {settings_file}\n"
            f"Parser result: {type(exc).__name__}\n",
            encoding="utf-8",
            newline="\n",
        )
        raise SystemExit(
            "Existing VS Code settings are invalid. The original file was preserved; "
            f"a content-free diagnostic was written to {diagnostic}."
        )
if not isinstance(existing, dict):
    raise SystemExit("Existing VS Code settings must be a JSON object")

def deep_merge(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = value

deep_merge(existing, managed)
ignored = existing.get("settingsSync.ignoredSettings", [])
if not isinstance(ignored, list):
    raise SystemExit("settingsSync.ignoredSettings must be an array when present")
if "python.defaultInterpreterPath" not in ignored:
    ignored.append("python.defaultInterpreterPath")
existing["settingsSync.ignoredSettings"] = ignored
serialized = json.dumps(existing, indent=4, ensure_ascii=False) + "\n"
temp = settings_file.with_name(settings_file.name + ".it140.tmp")
try:
    temp.write_text(serialized, encoding="utf-8", newline="\n")
    json.loads(temp.read_text(encoding="utf-8"))
    temp.replace(settings_file)
finally:
    if temp.exists():
        temp.unlink()
PY

    after_hash="$(/usr/bin/shasum -a 256 "$VSCODE_SETTINGS_FILE" | awk '{print $1}')"
    if [[ "$before_hash" != "$after_hash" ]]; then
        CHANGED=true
        print_success "Managed VS Code settings were merged without removing unrelated settings."
    else
        print_success "Managed VS Code settings are already correct."
    fi
}

post_validate() {
    print_header "Step 5: User-Layer Verification"

    local failed=0 package extension key expected actual
    local code_cli
    code_cli="$(resolve_code_cli)"

    [[ -d "$COURSE_ROOT" && -d "$LOG_DIR" && -x "$VENV_DIR/bin/python" ]] || {
        print_error "Required course folders or the virtual environment are missing."
        failed=1
    }

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if ! "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
            print_error "Required course Python package is missing: $package"
            failed=1
        fi
    done < <(manifest_lines venv_packages)

    local installed_extensions
    installed_extensions="$(NODE_NO_WARNINGS=1 "$code_cli" --list-extensions 2>/dev/null \
        | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r extension; do
        [[ -n "$extension" ]] || continue
        if ! printf '%s\n' "$installed_extensions" \
            | grep -Fxq "$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"; then
            print_error "Required VS Code extension is missing: $extension"
            failed=1
        fi
    done < <(manifest_lines extensions)

    gh auth status --hostname github.com >/dev/null 2>&1 || {
        print_error "GitHub authentication is not valid."
        failed=1
    }
    git config --global user.name >/dev/null 2>&1 || {
        print_error "Git display name is not configured."
        failed=1
    }

    local configured_email
    configured_email="$(git config --global user.email 2>/dev/null || true)"
    if ! printf '%s\n' "$configured_email" \
        | grep -Eq '^[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$'; then
        print_error "Git does not use the approved private commit identity."
        failed=1
    fi

    while IFS=$'\t' read -r key expected; do
        [[ -n "$key" ]] || continue
        actual="$(git config --global --get "$key" 2>/dev/null || true)"
        if [[ "$actual" != "$expected" ]]; then
            print_error "Managed Git setting is incorrect: $key"
            failed=1
        fi
    done < <(manifest_lines git_settings)

    if [[ -r "$HOME/.zprofile" ]] \
        && grep -Fq "# >>> IT 140 managed environment >>>" "$HOME/.zprofile" \
        && grep -Fq "$VENV_DIR/bin" "$HOME/.zprofile" \
        && grep -Fq "$PLATFORM_SCRIPT_DIR" "$HOME/.zprofile"; then
        :
    else
        print_error "The managed terminal environment is missing or incomplete."
        failed=1
    fi

    if ! "$(resolve_python)" - "$MANIFEST_PATH" "$PLATFORM_ID" \
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
        print_error "Managed VS Code settings are invalid or incomplete."
        failed=1
    fi

    local script_name
    for script_name in setup_mac.sh configure_mac.sh verify_mac.sh update_mac.sh; do
        if [[ ! -x "$PLATFORM_SCRIPT_DIR/$script_name" ]]; then
            print_error "${script_name} is missing or is not executable."
            failed=1
        fi
    done

    if (( failed )); then
        print_error "User-layer verification failed. Rerun configure_mac.sh."
        exit 7
    fi

    print_success "User-layer verification passed."
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    local result="PASS"
    (( WARNINGS > 0 )) && result="PASS WITH WARNINGS"

    print_header "CONFIGURATION SUMMARY"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'GitHub login    : Valid\n'
    printf 'Course folder   : %s\n' "$COURSE_ROOT"
    printf 'Python          : %s\n' "$VENV_DIR/bin/python"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Next step       : Run verify_mac.sh\n'
    printf 'Log file        : %s\n' "$LOG_FILE"
    print_success "The IT 140 macOS user configuration completed successfully."
}

main() {
    parse_options "$@"
    initialize_log
    trap cleanup EXIT
    trap on_error ERR
    trap on_interrupt INT TERM

    print_header "IT 140 macOS USER CONFIGURATION"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Configure the current user's course environment."
    print_info "Log file       : $LOG_FILE"
    print_notice "This script does not install or change system-wide software."

    check_platform_and_user
    initialize_homebrew_environment || {
        print_error "Homebrew is unavailable. Run setup_mac.sh first."
        exit 1
    }

    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || {
        print_error "The manifest or schema is missing. Run setup_mac.sh or update_mac.sh."
        exit 5
    }

    check_supported_release
    MANIFEST_RELEASE="$(validate_manifest)" || exit 5
    print_success "Manifest release $MANIFEST_RELEASE validated."

    check_disk_space
    acquire_lock
    check_system_layer

    configure_course_folders_and_path
    configure_provider_identity
    configure_user_tools
    merge_vscode_settings
    post_validate
    finish

    trap - ERR INT TERM
}

main "$@"
