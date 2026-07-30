#!/bin/zsh
# Shared implementation helpers for the IT 140 macOS lifecycle scripts.
# This file is sourced by setup_mac.sh, config_mac.sh, update_mac.sh, and
# verify_mac.sh. It is not intended to be run directly.

readonly IT140_PLATFORM_ID="macos"
readonly IT140_PLATFORM_ABBREVIATION="mac"
readonly IT140_COURSE_ROOT="${HOME}/it140"
readonly IT140_SCRIPT_ROOT="${IT140_COURSE_ROOT}/scripts"
readonly IT140_PLATFORM_SCRIPT_DIR="${IT140_SCRIPT_ROOT}/${IT140_PLATFORM_ABBREVIATION}"
readonly IT140_MANIFEST_PATH="${IT140_SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly IT140_SCHEMA_PATH="${IT140_SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly IT140_LOG_DIR="${IT140_COURSE_ROOT}/logs"
readonly IT140_LOCK_PARENT="${HOME}/Library/Caches"
readonly IT140_LOCK_DIR="${IT140_LOCK_PARENT}/it140-${IT140_PLATFORM_ABBREVIATION}-mutation.lock"
readonly IT140_REPOSITORY_URL="https://github.com/GC-STEM/it140"
readonly IT140_REPOSITORY_ARCHIVE="https://github.com/GC-STEM/it140/archive/refs/heads/main.zip"
readonly IT140_HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
readonly IT140_CODE_APP_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
readonly IT140_DESKTOP_DIR="${HOME}/Desktop"
readonly IT140_COURSE_DESKTOP_LINK="${IT140_DESKTOP_DIR}/IT 140"
readonly IT140_VSCODE_DESKTOP_APP="${IT140_DESKTOP_DIR}/Visual Studio Code - IT 140.app"
readonly IT140_VSCODE_DESKTOP_BUNDLE_ID="org.gc-stem.it140.vscode-launcher"
readonly IT140_MANAGED_ENV_START="# >>> IT 140 managed environment >>>"
readonly IT140_MANAGED_ENV_END="# <<< IT 140 managed environment <<<"

IT140_CHANGED=false
IT140_LOCK_HELD=false
IT140_WARNINGS=0
IT140_FAILURES=0
IT140_PARTIAL=false
IT140_START_EPOCH="$(date +%s)"
IT140_REQUESTED_PROFILE=""
IT140_LOG_FILE=""
IT140_TEMP_ROOT=""

it140_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}
it140_info() { printf '[INFO] %s\n' "$1"; }
it140_success() { printf '[SUCCESS] %s\n' "$1"; }
it140_notice() { printf '[NOTICE] %s\n' "$1"; }
it140_warning() {
    printf '[WARNING] %s\n' "$1"
    IT140_WARNINGS=$((IT140_WARNINGS + 1))
}
it140_error() { printf '[ERROR] %s\n' "$1" >&2; }

it140_print_version() {
    printf 'Script version   : %s\n' "$IT140_SCRIPT_VERSION"
    printf 'Version date     : %s\n' "$IT140_VERSION_DATE"
    printf 'Status           : %s\n' "$IT140_DEVELOPMENT_STATUS"
}

it140_initialize_log() {
    mkdir -p "$IT140_LOG_DIR"
    chmod 0700 "$IT140_LOG_DIR"
    IT140_LOG_FILE="${IT140_LOG_DIR}/${IT140_ACTION_ID}_${IT140_PLATFORM_ABBREVIATION}_$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$IT140_LOG_FILE") 2>&1
}

it140_closing_notices() {
    it140_notice "Log file: $IT140_LOG_FILE"
    it140_notice "After reviewing the summary, type 'exit' and press Enter to close this Terminal."
    it140_notice "Open a new Terminal before running another lifecycle script so it loads the latest PATH and environment settings."
}

it140_detect_architecture() {
    uname -m
}

it140_default_profile() {
    case "$(it140_detect_architecture)" in
        arm64) printf '%s\n' "macos_bare_metal" ;;
        x86_64) printf '%s\n' "macos_intel_bare_metal" ;;
        *) return 1 ;;
    esac
}

it140_resolve_profile() {
    if [ -z "$IT140_REQUESTED_PROFILE" ]; then
        IT140_REQUESTED_PROFILE="$(it140_default_profile)" || {
            it140_error "Unsupported Mac architecture: $(it140_detect_architecture)"
            return 2
        }
    fi
}

it140_check_platform_and_user() {
    if [ "$(uname -s)" != "Darwin" ]; then
        it140_error "This script supports macOS only."
        return 2
    fi
    if [ "$(id -u)" -eq 0 ]; then
        it140_error "Do not run this script with sudo or as root."
        it140_error "Run it from the macOS account that will complete course work."
        return 3
    fi
    case "$(it140_detect_architecture)" in
        arm64|x86_64) ;;
        *)
            it140_error "Unsupported Mac architecture: $(it140_detect_architecture)"
            return 2
            ;;
    esac
    it140_resolve_profile
}

it140_initialize_homebrew() {
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            eval "$("$candidate" shellenv)"
            command -v brew >/dev/null 2>&1
            return
        fi
    done
    if command -v brew >/dev/null 2>&1; then
        eval "$(brew shellenv)"
        return
    fi
    return 1
}

it140_resolve_python() {
    if command -v python3.12 >/dev/null 2>&1; then
        command -v python3.12
        return
    fi
    if it140_initialize_homebrew; then
        local prefix
        prefix="$(brew --prefix python@3.12 2>/dev/null || true)"
        if [ -n "$prefix" ] && [ -x "$prefix/bin/python3.12" ]; then
            printf '%s/bin/python3.12\n' "$prefix"
            return
        fi
    fi
    return 1
}

it140_resolve_code_cli() {
    if command -v code >/dev/null 2>&1; then
        command -v code
        return
    fi
    if [ -x "$IT140_CODE_APP_CLI" ]; then
        printf '%s\n' "$IT140_CODE_APP_CLI"
        return
    fi
    return 1
}

it140_plist_raw() {
    /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

it140_plist_json() {
    /usr/bin/plutil -extract "$2" json -o - "$1" 2>/dev/null
}

it140_is_managed_vscode_launcher() {
    local app_path="${1:-$IT140_VSCODE_DESKTOP_APP}"
    local bundle_id

    [ -d "$app_path" ] && [ ! -L "$app_path" ] || return 1
    [ -r "$app_path/Contents/Info.plist" ] || return 1
    [ -x "$app_path/Contents/MacOS/open-it140-in-code" ] || return 1

    bundle_id="$(it140_plist_raw "$app_path/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)"
    [ "$bundle_id" = "$IT140_VSCODE_DESKTOP_BUNDLE_ID" ]
}

it140_semver_is_valid() {
    printf '%s\n' "$1" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-([0-9A-Za-z-]+\.)*[0-9A-Za-z-]+)?(\+([0-9A-Za-z-]+\.)*[0-9A-Za-z-]+)?$'
}

it140_date_is_valid() {
    printf '%s\n' "$1" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
}

it140_validate_manifest_basic() {
    local manifest_file="${1:-$IT140_MANIFEST_PATH}"
    local schema_file="${2:-$IT140_SCHEMA_PATH}"
    local architecture product_version major schema_version release release_date
    local platform_enabled profile_enabled profile_platform profile_architecture
    local architectures_json releases_json allow_upgrade

    [ -r "$manifest_file" ] && [ -r "$schema_file" ] || {
        it140_error "The controlled manifest or schema is missing or unreadable."
        return 5
    }
    /usr/bin/plutil -lint "$manifest_file" >/dev/null 2>&1 || {
        it140_error "The controlled manifest is not valid JSON."
        return 5
    }
    /usr/bin/plutil -lint "$schema_file" >/dev/null 2>&1 || {
        it140_error "The manifest schema is not valid JSON."
        return 5
    }

    schema_version="$(it140_plist_raw "$manifest_file" schema_version)" || return 5
    release="$(it140_plist_raw "$manifest_file" automation_release)" || return 5
    release_date="$(it140_plist_raw "$manifest_file" automation_release_date)" || return 5
    allow_upgrade="$(it140_plist_raw "$manifest_file" policy.allow_os_release_upgrade)" || return 5

    [ "$schema_version" = "2.0" ] || {
        it140_error "Unsupported manifest schema version: ${schema_version:-missing}. Expected 2.0."
        return 5
    }
    it140_semver_is_valid "$release" || {
        it140_error "The manifest automation_release is not strict SemVer: ${release:-missing}."
        return 5
    }
    it140_date_is_valid "$release_date" || {
        it140_error "The manifest automation_release_date is invalid: ${release_date:-missing}."
        return 5
    }
    [ "$allow_upgrade" = "false" ] || {
        it140_error "Operating-system release upgrades must remain disabled in the manifest."
        return 5
    }

    architecture="$(it140_detect_architecture)"
    product_version="$(/usr/bin/sw_vers -productVersion)"
    major="${product_version%%.*}"
    platform_enabled="$(it140_plist_raw "$manifest_file" platforms.${IT140_PLATFORM_ID}.enabled)" || return 5
    profile_enabled="$(it140_plist_raw "$manifest_file" deployment_profiles.${IT140_REQUESTED_PROFILE}.enabled)" || return 5
    profile_platform="$(it140_plist_raw "$manifest_file" deployment_profiles.${IT140_REQUESTED_PROFILE}.platform_id)" || return 5
    profile_architecture="$(it140_plist_raw "$manifest_file" deployment_profiles.${IT140_REQUESTED_PROFILE}.architecture)" || return 5
    architectures_json="$(it140_plist_json "$manifest_file" platforms.${IT140_PLATFORM_ID}.os.architectures)" || return 5
    releases_json="$(it140_plist_json "$manifest_file" platforms.${IT140_PLATFORM_ID}.os.releases)" || return 5

    [ "$platform_enabled" = "true" ] || {
        it140_error "The macOS platform is disabled in the controlled manifest."
        return 5
    }
    [ "$profile_enabled" = "true" ] && [ "$profile_platform" = "$IT140_PLATFORM_ID" ] || {
        it140_error "The deployment profile is missing, disabled, or assigned to another platform: $IT140_REQUESTED_PROFILE"
        return 5
    }
    [ "$profile_architecture" = "$architecture" ] || {
        it140_error "Deployment profile $IT140_REQUESTED_PROFILE expects $profile_architecture, but this Mac reports $architecture."
        return 2
    }
    printf '%s\n' "$architectures_json" | grep -Eq "\"${architecture}\"" || {
        it140_error "Architecture $architecture is not enabled for macOS in the controlled manifest."
        return 2
    }
    printf '%s\n' "$releases_json" | grep -Eq "\"release_id\"[[:space:]]*:[[:space:]]*\"${major}\"" || {
        it140_error "macOS $product_version is not supported by the controlled manifest."
        return 2
    }

    printf '%s\n' "$release"
}

it140_validate_manifest_full() {
    local manifest_file="${1:-$IT140_MANIFEST_PATH}"
    local schema_file="${2:-$IT140_SCHEMA_PATH}"
    local python_path
    python_path="$(it140_resolve_python)" || {
        it140_error "Python 3.12 is unavailable for full manifest validation. Run setup_mac.sh first."
        return 5
    }
    "$python_path" - "$manifest_file" "$schema_file" "$IT140_PLATFORM_ID" \
        "$IT140_REQUESTED_PROFILE" "$(it140_detect_architecture)" \
        "$(/usr/bin/sw_vers -productVersion)" <<'PY'
import datetime as dt
import json
import pathlib
import re
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
    "schema_version", "automation_release", "automation_release_date", "course",
    "control", "policy", "capabilities", "products", "software_sources",
    "provider_profiles", "platforms", "deployment_profiles", "managed_settings",
    "managed_assets", "obsolete_components", "logging",
}
missing = sorted(required - manifest.keys())
if missing:
    raise SystemExit(f"manifest missing required keys: {', '.join(missing)}")
if manifest["schema_version"] != "2.0":
    raise SystemExit("unsupported manifest schema version")
semver = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")
if not semver.fullmatch(str(manifest["automation_release"])):
    raise SystemExit("automation_release is not strict SemVer")
try:
    dt.date.fromisoformat(str(manifest["automation_release_date"]))
except ValueError as exc:
    raise SystemExit("automation_release_date is not YYYY-MM-DD") from exc
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

it140_manifest_query() {
    local query="$1"
    local manifest_file="${2:-$IT140_MANIFEST_PATH}"
    local python_path
    python_path="$(it140_resolve_python)" || return 1
    "$python_path" - "$manifest_file" "$IT140_PLATFORM_ID" "$query" <<'PY'
import json
import sys

path, platform_id, query = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    manifest = json.load(handle)
platform = manifest["platforms"][platform_id]
bindings = platform["course_ide_bindings"]
if query == "system_formulae":
    values = {
        binding["package_identifier"]
        for binding in bindings.values()
        if binding.get("required")
        and binding.get("installation_scope") == "system"
        and binding.get("installer_adapter_id") == "homebrew_formula"
    }
    print(*sorted(values), sep="\n")
elif query == "system_casks":
    values = {
        binding["package_identifier"]
        for binding in bindings.values()
        if binding.get("required")
        and binding.get("installation_scope") == "system"
        and binding.get("installer_adapter_id") == "homebrew_cask"
    }
    print(*sorted(values), sep="\n")
elif query == "system_commands":
    values = set()
    for binding in bindings.values():
        if binding.get("required") and binding.get("installation_scope") == "system":
            values.update(binding.get("verification", {}).get("executable_names", []))
    print(*sorted(values), sep="\n")
elif query == "venv_packages":
    values = {
        binding["package_identifier"]
        for binding in bindings.values()
        if binding.get("required")
        and binding.get("installation_scope") == "user"
        and binding.get("installer_adapter_id") == "python_venv_package"
    }
    if bindings.get("code_quality_tool", {}).get("required"):
        values.add("ruff")
    print(*sorted(values), sep="\n")
elif query == "extensions":
    values = {
        binding["package_identifier"]
        for binding in bindings.values()
        if binding.get("required")
        and binding.get("installation_scope") == "user"
        and binding.get("installer_adapter_id") == "vscode_extension"
    }
    print(*sorted(values), sep="\n")
elif query == "git_settings":
    for profile_id in bindings["version_control_system"].get("settings_profile_ids", []):
        profile = manifest["managed_settings"][profile_id]
        if platform_id not in profile.get("platform_ids", []):
            continue
        for key, value in profile["values"].items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            print(f"{key}\t{value}")
elif query == "vscode_settings":
    result = {}
    for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
        profile = manifest["managed_settings"][profile_id]
        if platform_id in profile.get("platform_ids", []):
            result.update(profile["values"])
    print(json.dumps(result, sort_keys=True))
elif query == "minimum_space":
    print(manifest["policy"]["minimum_free_space_bytes"])
elif query == "source_repository":
    print(manifest["control"]["source_repository"])
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}

it140_check_free_space() {
    local required available
    required="$(it140_plist_raw "$IT140_MANIFEST_PATH" policy.minimum_free_space_bytes 2>/dev/null || printf '%s' 5368709120)"
    available="$(/bin/df -Pk "$HOME" | /usr/bin/awk 'NR==2 {print $4 * 1024}')"
    if [ -z "$available" ] || [ "$available" -lt "$required" ]; then
        it140_error "At least $required bytes of free space are required."
        return 1
    fi
    it140_success "Required free space is available."
}

it140_acquire_lock() {
    mkdir -p "$IT140_LOCK_PARENT"
    if mkdir "$IT140_LOCK_DIR" 2>/dev/null; then
        IT140_LOCK_HELD=true
        printf '%s\n' "$$" > "$IT140_LOCK_DIR/pid"
        return
    fi
    it140_error "Another IT 140 lifecycle script may already be changing this Mac."
    it140_error "If no script is running, remove $IT140_LOCK_DIR and rerun."
    return 1
}

it140_release_lock() {
    if [ "$IT140_LOCK_HELD" = true ] && [ -d "$IT140_LOCK_DIR" ] && [ ! -L "$IT140_LOCK_DIR" ]; then
        rm -rf "$IT140_LOCK_DIR"
        IT140_LOCK_HELD=false
    fi
}

it140_retry() {
    local description="$1"
    shift
    local attempt=1 delay=5 maximum=5
    while [ "$attempt" -le "$maximum" ]; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -eq "$maximum" ]; then
            it140_error "$description failed after $maximum attempts."
            return 1
        fi
        it140_warning "$description failed on attempt $attempt; retrying in $delay seconds."
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
        [ "$delay" -le 60 ] || delay=60
    done
}

it140_cleanup_common() {
    set +e
    if [ -n "$IT140_TEMP_ROOT" ] && [ -d "$IT140_TEMP_ROOT" ] && [ ! -L "$IT140_TEMP_ROOT" ]; then
        rm -rf "$IT140_TEMP_ROOT"
    fi
    it140_release_lock
}

it140_elapsed() {
    printf '%s\n' "$(( $(date +%s) - IT140_START_EPOCH ))"
}

it140_manifest_package() {
    local role="$1"
    local python_path
    python_path="$(it140_resolve_python)" || return 1
    "$python_path" - "$IT140_MANIFEST_PATH" "$IT140_PLATFORM_ID" "$role" <<'PY'
import json
import sys
path, platform_id, role = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    manifest = json.load(handle)
print(manifest["platforms"][platform_id]["course_ide_bindings"][role]["package_identifier"])
PY
}
