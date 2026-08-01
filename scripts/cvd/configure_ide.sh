#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop user configuration and repair script
#
# Artifact ID: IT140-CVD-CONFIGURE
# Artifact version: 0.7.1-alpha.1
# Version date-time group: 2026-08-01-16-05
# Development status: Alpha Testing
#
# Traceability: CFG-FR-001 through CFG-FR-017; PKG-FR-021;
#               CFG-DES-001 through CFG-DES-017; ERR-DES-014.
# Scope: Current-user course folders, PATH, GitHub authentication, private Git
#        identity, course virtual environment, VS Code extensions and settings,
#        desktop launcher repair, and course-folder shortcut.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.7.1-alpha.1"
readonly VERSION_DTG="2026-08-01-16-05"
readonly DEVELOPMENT_STATUS="Alpha Testing"
readonly SUPPORTED_SCHEMA="2.2"
readonly PLATFORM_ID="cvd"
readonly DEPLOYMENT_PROFILE_ID="codio_cvd"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/configure_cvd_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly LOCK_FILE="${HOME}/.cache/it140-${PLATFORM_ID}-mutation.lock"
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
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
WARNINGS=0
FAILURES=0
START_EPOCH="$(date +%s)"
START_TIME="$(date --iso-8601=seconds)"
CURRENT_STAGE="initialization"
MANIFEST_RELEASE="unavailable"
MANIFEST_DTG="unavailable"
FINALIZED=false
GITHUB_LOGIN=""
GITHUB_ACCOUNT_ID=""
GIT_DISPLAY_NAME=""
GIT_PRIVATE_EMAIL=""
VSCODE_LAUNCHER=""

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
Usage: configure_ide.sh [--help] [--version] [--noninteractive]
                        [--deployment-profile codio_cvd]

Configures or repairs the current user's IT 140 CVD environment. Run as the
standard desktop user, not with sudo. In noninteractive mode, GitHub CLI must
already be authenticated.

Exit codes:
  0  Completed successfully
  1  Required operation or precondition failed
  2  Invalid use or unsupported execution context
  3  Required privilege unavailable
  4  Required external source or service unavailable
  5  Manifest, schema, or controlled configuration invalid
  6  User canceled before a managed change
  7  Partial result or interruption after a managed change

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
        "$EXIT_MANIFEST"|"$EXIT_UNSUPPORTED"|"$EXIT_PRIVILEGE"|"$EXIT_EXTERNAL")
            printf '%s\n' "$requested"
            ;;
        "$EXIT_PARTIAL")
            printf '%s\n' "$EXIT_PARTIAL"
            ;;
        "$EXIT_CANCELED")
            if [[ "$CHANGED" == true ]]; then
                printf '%s\n' "$EXIT_PARTIAL"
            else
                printf '%s\n' "$EXIT_CANCELED"
            fi
            ;;
        *)
            if [[ "$CHANGED" == true ]]; then
                printf '%s\n' "$EXIT_PARTIAL"
            else
                printf '%s\n' "$EXIT_FAILURE"
            fi
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
    if ((requested_code == 0)); then
        exit_code=0
    else
        exit_code="$(resolve_failure_code "$requested_code")"
    fi

    if ((exit_code == 0)); then
        result="PASS"
        next_step="Open a fresh Terminal and run verify_ide.sh."
    elif ((exit_code == EXIT_PARTIAL)); then
        result="PARTIAL"
        next_step="Review the errors above, then rerun configure_ide.sh."
    else
        result="FAIL"
        next_step="Resolve the reported issue, then rerun configure_ide.sh."
    fi
    elapsed=$(( $(date +%s) - START_EPOCH ))

    print_header "CONFIGURATION SUMMARY"
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
        print_success "The IT 140 CVD user configuration completed successfully."
    else
        course_continuity_guidance
    fi
    print_notice "Review the summary and log before closing this Terminal."
    print_notice "Open a new Terminal before running another IT 140 script."
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
    print_error "Configuration stopped near line ${line} during ${CURRENT_STAGE} (status ${status})."
    finish "$EXIT_FAILURE" "An unexpected command failure stopped Configure."
    exit $?
}

on_interrupt() {
    trap - INT TERM
    print_error "Configuration was interrupted during ${CURRENT_STAGE}."
    finish "$EXIT_CANCELED" "Configure was interrupted; rerun it to recover."
    exit $?
}

validate_manifest() {
    python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
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
    manifest = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
    schema = json.loads(pathlib.Path(schema_path).read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError) as exc:
    raise SystemExit(f"controlled JSON validation failed: {exc}")
required = {
    "schema_version", "automation_release", "automation_release_date_time_group", "course",
    "control", "policy", "capabilities", "products", "software_sources", "provider_profiles",
    "platforms", "deployment_profiles", "lifecycle_workflows", "managed_settings",
    "managed_assets", "obsolete_components", "logging"
}
missing = sorted(required - manifest.keys())
if missing:
    raise SystemExit("manifest missing required keys: " + ", ".join(missing))
if manifest.get("schema_version") != supported_schema:
    raise SystemExit(f"unsupported manifest schema: {manifest.get('schema_version')!r}; expected {supported_schema}")
if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
    raise SystemExit("schema is not the approved Draft 2020-12 format")
platform = manifest["platforms"].get(platform_id)
profile = manifest["deployment_profiles"].get(profile_id)
if not platform or not platform.get("enabled"):
    raise SystemExit("CVD platform is missing or disabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("CVD deployment profile is invalid")
if "github_com" not in manifest["provider_profiles"]:
    raise SystemExit("required GitHub provider profile is unavailable")
workflow = manifest["lifecycle_workflows"].get("cvd_course_master_student")
if not workflow or workflow.get("success_transitions", {}).get("configure") != "verify":
    raise SystemExit("CVD student workflow does not transition from Configure to Verify")

try:
    import jsonschema  # type: ignore
except ImportError:
    pass
else:
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(manifest)

version_dtg = manifest.get("automation_release_date_time_group") or manifest.get("automation_release_date") or "unavailable"
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

if query == "system_commands":
    values = []
    for binding in bindings.values():
        if binding.get("required") and binding.get("installation_scope") == "system":
            values.extend(binding.get("verification", {}).get("executable_names", []))
    for value in sorted(set(values)):
        print(value)
elif query == "venv_packages":
    values = []
    for role, binding in bindings.items():
        if (binding.get("required") and binding.get("installation_scope") == "user"
                and binding.get("installer_adapter_id") == "python_venv_package"):
            values.append(binding["package_identifier"])
        if role == "code_quality_tool" and binding.get("required"):
            values.append("ruff")
    for value in sorted(set(values)):
        print(value)
elif query == "extensions":
    for binding in bindings.values():
        if (binding.get("required") and binding.get("installation_scope") == "user"
                and binding.get("installer_adapter_id") == "vscode_extension"):
            print(binding["package_identifier"])
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
elif query == "privacy_template":
    print(manifest["provider_profiles"]["github_com"]["privacy_identity"]["template"])
elif query == "retry_profile":
    profile_id = manifest["policy"]["default_retry_profile_id"]
    profile = manifest["policy"]["retry_profiles"][profile_id]
    print("\t".join(str(profile[key]) for key in (
        "maximum_attempts", "initial_delay_seconds", "backoff_multiplier", "maximum_delay_seconds"
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
    if [[ "$EUID" -eq 0 ]]; then
        fatal "$EXIT_UNSUPPORTED" "Do not run configure_ide.sh with sudo; personal settings must belong to the standard CVD account."
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
    print_info "Platform       : $PLATFORM_ID / $DEPLOYMENT_PROFILE_ID"
    print_info "Operating system: ${PRETTY_NAME:-Ubuntu 24.04}"
    print_info "Architecture   : $architecture"
    [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] \
        || fatal "$EXIT_UNSUPPORTED" "Unsupported deployment profile: $REQUESTED_PROFILE"
    command -v xfconf-query >/dev/null 2>&1 \
        || fatal "$EXIT_UNSUPPORTED" "The required Xfce desktop tools are unavailable."
}

check_restart_precondition() {
    CURRENT_STAGE="restart precondition validation"
    if [[ -e /var/run/reboot-required ]]; then
        fatal "$EXIT_FAILURE" "Ubuntu requires a CVD restart. Restart the CVD before running Configure."
    fi
}

check_system_layer() {
    CURRENT_STAGE="system-layer validation"
    local command_name failed=false
    local -a commands=()
    mapfile -t commands < <(manifest_query system_commands)
    for command_name in "${commands[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            print_error "Required system command is missing: $command_name"
            failed=true
        fi
    done
    command -v python3.12 >/dev/null 2>&1 || { print_error "Required system command is missing: python3.12"; failed=true; }
    [[ "$failed" == false ]] \
        || fatal "$EXIT_FAILURE" "The CVD system layer is incomplete. Rerun update_ide.sh before Configure."
    print_success "Required system components are present."
}

acquire_lock() {
    CURRENT_STAGE="mutation-lock acquisition"
    command -v flock >/dev/null 2>&1 || {
        print_warning "flock is unavailable; concurrent lifecycle-script protection cannot be enforced."
        return 0
    }
    mkdir -p -- "$(dirname "$LOCK_FILE")"
    chmod 0700 -- "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock --nonblock 9 || fatal "$EXIT_FAILURE" "Another IT 140 mutating lifecycle script is running."
}

resolve_provider_identity() {
    CURRENT_STAGE="GitHub authentication and identity resolution"
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        if [[ "$NONINTERACTIVE" == true ]]; then
            fatal "$EXIT_FAILURE" "GitHub CLI is not authenticated; interactive authentication is required."
        fi
        print_header "GITHUB AUTHENTICATION"
        print_notice "GitHub CLI will display a one-time code and open a browser."
        printf 'Press Enter to begin, or type C to cancel: '
        local response
        IFS= read -r response
        if [[ "${response,,}" == c ]]; then
            fatal "$EXIT_CANCELED" "GitHub authentication was canceled before configuration changes began."
        fi
        if ! gh auth login --hostname github.com --git-protocol https --web --clipboard; then
            fatal "$EXIT_EXTERNAL" "GitHub authentication did not complete."
        fi
        CHANGED=true
    fi

    local identity_json
    identity_json="$(retry_operation "GitHub account lookup" gh api user --jq '{id: .id, login: .login, name: .name}')" \
        || fatal "$EXIT_EXTERNAL" "The authenticated GitHub account could not be read."
    IFS=$'\t' read -r GITHUB_ACCOUNT_ID GITHUB_LOGIN GIT_DISPLAY_NAME < <(
        python3 - "$identity_json" <<'PY'
import json
import sys
value = json.loads(sys.argv[1])
account_id = str(value.get("id") or "")
login = str(value.get("login") or "").strip()
display = str(value.get("name") or "").strip() or login
if not account_id or not login:
    raise SystemExit(1)
print(f"{account_id}\t{login}\t{display}")
PY
    ) || fatal "$EXIT_EXTERNAL" "GitHub returned incomplete account identity fields."

    if [[ "$NONINTERACTIVE" == false ]]; then
        local requested_name
        printf 'Git commit display name [%s]: ' "$GIT_DISPLAY_NAME"
        IFS= read -r requested_name
        [[ -z "$requested_name" ]] || GIT_DISPLAY_NAME="$requested_name"
    fi
    [[ -n "${GIT_DISPLAY_NAME//[[:space:]]/}" ]] \
        || fatal "$EXIT_FAILURE" "The Git commit display name cannot be empty."

    local template
    template="$(manifest_query privacy_template)" \
        || fatal "$EXIT_MANIFEST" "The GitHub private-email template is unavailable."
    GIT_PRIVATE_EMAIL="${template//\$\{ACCOUNT_ID\}/$GITHUB_ACCOUNT_ID}"
    GIT_PRIVATE_EMAIL="${GIT_PRIVATE_EMAIL//\$\{USERNAME\}/$GITHUB_LOGIN}"
    [[ "$GIT_PRIVATE_EMAIL" == *@users.noreply.github.com ]] \
        || fatal "$EXIT_MANIFEST" "The provider private-email template produced an invalid result."
    print_success "GitHub authentication and privacy-preserving identity were resolved."
}

upsert_managed_path_block() {
    local file="$1"
    python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
start = "# >>> IT 140 managed PATH >>>"
end = "# <<< IT 140 managed PATH <<<"
block = start + "\n" + 'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/cvd:$PATH"' + "\n" + end + "\n"
text = path.read_text(encoding="utf-8") if path.exists() else ""
if start in text and end in text:
    before = text.split(start, 1)[0].rstrip("\n")
    after = text.split(end, 1)[1].lstrip("\n")
    text = ((before + "\n\n") if before else "") + block + (("\n" + after) if after else "")
else:
    if text and not text.endswith("\n"):
        text += "\n"
    if text:
        text += "\n"
    text += block
path.parent.mkdir(parents=True, exist_ok=True)
temp = path.with_name(path.name + ".it140.tmp")
try:
    temp.write_text(text, encoding="utf-8", newline="\n")
    temp.replace(path)
finally:
    temp.unlink(missing_ok=True)
PY
}

configure_paths_and_folders() {
    CURRENT_STAGE="course folders and PATH configuration"
    mkdir -p "$COURSE_ROOT" "$LOG_DIR" "$HOME/.cache"
    chmod 0700 "$LOG_DIR"
    touch "$HOME/.bashrc" "$HOME/.profile"
    upsert_managed_path_block "$HOME/.bashrc"
    upsert_managed_path_block "$HOME/.profile"
    export PATH="$VENV_DIR/bin:$PLATFORM_SCRIPT_DIR:$PATH"
    hash -r
    CHANGED=true
    print_success "Course folders and managed PATH blocks are configured."
}

configure_python_tools() {
    CURRENT_STAGE="course Python environment configuration"
    local -a packages=()
    mapfile -t packages < <(manifest_query venv_packages)
    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        python3.12 -m venv "$VENV_DIR" \
            || fatal "$EXIT_FAILURE" "The course Python virtual environment could not be created."
        CHANGED=true
    fi
    retry_operation "Python packaging-tool configuration" \
        "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade pip setuptools wheel \
        || fatal "$EXIT_EXTERNAL" "Python packaging tools could not be configured."
    if ((${#packages[@]} > 0)); then
        retry_operation "Course Python tool configuration" \
            "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade "${packages[@]}" \
            || fatal "$EXIT_EXTERNAL" "Required course Python tools could not be configured."
    fi
    CHANGED=true
    print_success "The course Python environment is configured."
}

configure_vscode_extensions() {
    CURRENT_STAGE="Visual Studio Code extension configuration"
    local extension
    local -a extensions=()
    mapfile -t extensions < <(manifest_query extensions)
    for extension in "${extensions[@]}"; do
        retry_operation "VS Code extension configuration: $extension" \
            code --install-extension "$extension" --force \
            || fatal "$EXIT_EXTERNAL" "Required VS Code extension could not be configured: $extension"
        CHANGED=true
    done
    print_success "Required Visual Studio Code extensions are configured."
}

configure_git_settings() {
    CURRENT_STAGE="Git configuration"
    local key value
    git config --global user.name "$GIT_DISPLAY_NAME"
    git config --global user.email "$GIT_PRIVATE_EMAIL"
    while IFS=$'\t' read -r key value; do
        [[ -n "$key" ]] || continue
        git config --global "$key" "$value"
    done < <(manifest_query git_settings)
    CHANGED=true
    print_success "Git identity and course defaults are configured with a private provider email."
}

configure_vscode_settings() {
    CURRENT_STAGE="Visual Studio Code settings configuration"
    local settings_dir settings_file settings_json
    settings_dir="$HOME/.config/Code/User"
    settings_file="$settings_dir/settings.json"
    settings_json="$(manifest_query vscode_settings)" \
        || fatal "$EXIT_MANIFEST" "VS Code managed settings could not be read from the manifest."
    mkdir -p "$settings_dir"
    IT140_SETTINGS_FILE="$settings_file" \
    IT140_SETTINGS_JSON="$settings_json" \
    IT140_VENV_PYTHON="$VENV_DIR/bin/python" \
    python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["IT140_SETTINGS_FILE"])
managed = json.loads(os.environ["IT140_SETTINGS_JSON"])
managed["python.defaultInterpreterPath"] = os.environ["IT140_VENV_PYTHON"]
if path.exists():
    try:
        current = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f"existing VS Code settings are invalid and were preserved: {exc}")
    if not isinstance(current, dict):
        raise SystemExit("existing VS Code settings are not a JSON object and were preserved")
else:
    current = {}

def merge(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge(target[key], value)
        else:
            target[key] = value

merge(current, managed)
path.parent.mkdir(parents=True, exist_ok=True)
temp = path.with_name(path.name + ".it140.tmp")
try:
    temp.write_text(json.dumps(current, indent=4, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    json.loads(temp.read_text(encoding="utf-8"))
    temp.replace(path)
finally:
    temp.unlink(missing_ok=True)
PY
    CHANGED=true
    print_success "Visual Studio Code settings are configured without removing unrelated valid settings."
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

repair_vscode_launcher() {
    CURRENT_STAGE="Visual Studio Code desktop-launcher repair"
    local launcher code_path
    launcher="$(find_vscode_launcher 2>/dev/null || true)"
    [[ -n "$launcher" ]] \
        || fatal "$EXIT_FAILURE" "The existing Visual Studio Code desktop launcher could not be found; no duplicate launcher was created."
    code_path="$(command -v code)"

    python3 - "$launcher" "$code_path" "$COURSE_ROOT" <<'PY'
from pathlib import Path
import shlex
import sys

path = Path(sys.argv[1])
code_path = sys.argv[2]
course_root = sys.argv[3]
try:
    lines = path.read_text(encoding="utf-8").splitlines()
except (OSError, UnicodeError) as exc:
    raise SystemExit(f"launcher could not be read: {exc}")

quoted_code = shlex.quote(code_path)
quoted_root = '"' + course_root.replace('\\', '\\\\').replace('"', '\\"') + '"'
new_exec = f"Exec={quoted_code} --reuse-window {quoted_root}"
new_path = f"Path={course_root}"
output = []
in_desktop = False
seen_desktop = False
replaced_exec = False
replaced_path = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_desktop and not replaced_exec:
            output.append(new_exec)
            replaced_exec = True
        if in_desktop and not replaced_path:
            output.append(new_path)
            replaced_path = True
        in_desktop = stripped == "[Desktop Entry]"
        seen_desktop = seen_desktop or in_desktop
        output.append(line)
        continue
    if in_desktop and stripped.startswith("Exec=") and not replaced_exec:
        output.append(new_exec)
        replaced_exec = True
    elif in_desktop and stripped.startswith("Path=") and not replaced_path:
        output.append(new_path)
        replaced_path = True
    else:
        output.append(line)
if in_desktop and not replaced_exec:
    output.append(new_exec)
    replaced_exec = True
if in_desktop and not replaced_path:
    output.append(new_path)
    replaced_path = True
if not seen_desktop or not replaced_exec:
    raise SystemExit("launcher lacks a valid [Desktop Entry] section")

temp = path.with_name(path.name + ".it140.tmp")
try:
    temp.write_text("\n".join(output) + "\n", encoding="utf-8", newline="\n")
    temp.replace(path)
finally:
    temp.unlink(missing_ok=True)
PY

    chmod 0755 "$launcher"
    if command -v desktop-file-validate >/dev/null 2>&1; then
        desktop-file-validate "$launcher" \
            || fatal "$EXIT_FAILURE" "The repaired Visual Studio Code launcher failed desktop-entry validation."
    fi
    if command -v gio >/dev/null 2>&1; then
        gio set "$launcher" metadata::trusted true >/dev/null 2>&1 \
            || print_warning "The launcher was repaired, but the desktop trust metadata could not be set automatically."
    fi
    VSCODE_LAUNCHER="$launcher"
    CHANGED=true
    print_success "The existing Visual Studio Code desktop launcher now opens $COURSE_ROOT."
}

configure_course_folder_shortcut() {
    CURRENT_STAGE="course-folder shortcut configuration"
    local desktop_dir shortcut
    desktop_dir="$(desktop_directory)"
    mkdir -p "$desktop_dir"
    shortcut="$desktop_dir/IT 140 Course Folder"
    if [[ -L "$shortcut" ]]; then
        if [[ "$(readlink -f "$shortcut")" != "$(readlink -f "$COURSE_ROOT")" ]]; then
            ln -sfn "$COURSE_ROOT" "$shortcut"
            CHANGED=true
        fi
    elif [[ -e "$shortcut" ]]; then
        fatal "$EXIT_FAILURE" "A non-managed item already uses the course-folder shortcut name and was preserved: $shortcut"
    else
        ln -s "$COURSE_ROOT" "$shortcut"
        CHANGED=true
    fi
    print_success "The desktop course-folder shortcut opens $COURSE_ROOT."
}

configure_file_associations() {
    CURRENT_STAGE="file-association configuration"
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default code.desktop text/x-python \
            || print_warning "The optional Python file association could not be updated."
    fi
}

launcher_opens_course_root() {
    local launcher="$1"
    python3 - "$launcher" "$COURSE_ROOT" <<'PY'
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
course_root = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()
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
args = shlex.split(exec_value)
args = [arg for arg in args if not (arg.startswith("%") and len(arg) == 2)]
if not args or pathlib.Path(args[0]).name != "code" or course_root not in args:
    raise SystemExit(1)
PY
}

validate_configuration() {
    CURRENT_STAGE="configuration validation"
    local key expected actual package extension
    local -a packages=() extensions=()

    gh auth status --hostname github.com >/dev/null 2>&1 \
        || fatal "$EXIT_FAILURE" "GitHub CLI is not authenticated after configuration."
    [[ "$(git config --global --get user.name 2>/dev/null || true)" == "$GIT_DISPLAY_NAME" ]] \
        || fatal "$EXIT_FAILURE" "Git display-name validation failed."
    [[ "$(git config --global --get user.email 2>/dev/null || true)" == "$GIT_PRIVATE_EMAIL" ]] \
        || fatal "$EXIT_FAILURE" "Git private-email validation failed."
    while IFS=$'\t' read -r key expected; do
        [[ -n "$key" ]] || continue
        actual="$(git config --global --get "$key" 2>/dev/null || true)"
        [[ "$actual" == "$expected" ]] \
            || fatal "$EXIT_FAILURE" "Git managed setting validation failed: $key"
    done < <(manifest_query git_settings)

    grep -Fqx "$MANAGED_PATH_EXPORT" "$HOME/.bashrc" \
        || fatal "$EXIT_FAILURE" "The managed PATH block is missing from ~/.bashrc."
    grep -Fqx "$MANAGED_PATH_EXPORT" "$HOME/.profile" \
        || fatal "$EXIT_FAILURE" "The managed PATH block is missing from ~/.profile."
    [[ -x "$VENV_DIR/bin/python" ]] \
        || fatal "$EXIT_FAILURE" "The course Python environment is unavailable after configuration."

    mapfile -t packages < <(manifest_query venv_packages)
    for package in "${packages[@]}"; do
        "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1 \
            || fatal "$EXIT_FAILURE" "Required Python package is missing after configuration: $package"
    done

    mapfile -t extensions < <(manifest_query extensions)
    local installed_extensions
    installed_extensions="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    for extension in "${extensions[@]}"; do
        grep -Fqx "${extension,,}" <<< "$installed_extensions" \
            || fatal "$EXIT_FAILURE" "Required VS Code extension is missing after configuration: $extension"
    done

    [[ -n "$VSCODE_LAUNCHER" && -f "$VSCODE_LAUNCHER" ]] \
        || fatal "$EXIT_FAILURE" "The repaired Visual Studio Code desktop launcher is unavailable."
    launcher_opens_course_root "$VSCODE_LAUNCHER" \
        || fatal "$EXIT_FAILURE" "The Visual Studio Code desktop launcher does not pass $COURSE_ROOT as a folder argument."
    print_success "Required user configuration passed post-configuration validation."
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

    print_header "IT 140 CODIO VIRTUAL DESKTOP CONFIGURE"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Version DTG    : $VERSION_DTG"
    print_info "Status         : $DEVELOPMENT_STATUS"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Configure the current user's course IDE environment."
    print_info "Log file       : $LOG_FILE"
    print_notice "Keep this Terminal open until the final summary appears."

    check_platform_and_user

    CURRENT_STAGE="controlled manifest validation"
    local manifest_info
    manifest_info="$(validate_manifest)" \
        || fatal "$EXIT_MANIFEST" "The controlled manifest and schema failed validation."
    IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$manifest_info"
    print_success "Manifest release $MANIFEST_RELEASE (schema $SUPPORTED_SCHEMA) validated."

    check_system_layer
    check_restart_precondition
    acquire_lock

    # Authentication occurs before course-file mutations so a student can
    # cancel the required interaction and receive exit code 6 without a partial
    # configuration result.
    resolve_provider_identity
    configure_paths_and_folders
    configure_python_tools
    configure_vscode_extensions
    configure_git_settings
    configure_vscode_settings
    repair_vscode_launcher
    configure_course_folder_shortcut
    configure_file_associations
    validate_configuration

    trap - ERR INT TERM
    finish "$EXIT_SUCCESS" "Required current-user configuration completed."
    exit $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
