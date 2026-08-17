#!/usr/bin/env bash
# IT 140 Ubuntu Desktop GNOME read-only verification script
# Artifact ID: IT140-UBG-VERIFY
# Artifact version: 0.8.0-alpha.1
# Version date-time group: 2026-08-07-10-44
# Development status: Alpha Testing
# Traceability: VER-FR-001 through VER-FR-018; VER-DES-001 through VER-DES-018.
#
# Verification performs shallow checks of ~/Repos and its desktop integration;
# it never writes into or recursively traverses student repositories.
set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.8.0-alpha.1"
readonly VERSION_DTG="2026-08-07-10-44"
readonly PLATFORM_ID="ubuntu_gnome"
readonly DEPLOYMENT_PROFILE_ID="ubuntu_gnome_bare_metal"
readonly SUPPORTED_SCHEMA="2.2"
readonly COURSE_ROOT="$HOME/it140"
readonly REPOS_ROOT="$HOME/Repos"
readonly SCRIPT_ROOT="$COURSE_ROOT/scripts"
readonly PLATFORM_SCRIPT_DIR="$SCRIPT_ROOT/nix/ubg"
readonly MANIFEST_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="$COURSE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/verify_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="$COURSE_ROOT/.venv"
readonly PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/nix/ubg:$PATH"'

# Test isolation hooks are inert during normal execution. They let automated
# lifecycle tests supply a fixture-backed /etc tree and deterministic EUID
# without modifying the CI runner's system files.
readonly VERIFY_TEST_ROOT="${IT140_VERIFY_TEST_ROOT:-}"
if [[ -n "$VERIFY_TEST_ROOT" ]]; then
    VERIFY_EFFECTIVE_UID="${IT140_VERIFY_TEST_EUID:-$EUID}"
else
    VERIFY_EFFECTIVE_UID="$EUID"
fi
readonly VERIFY_EFFECTIVE_UID
readonly OS_RELEASE_PATH="${VERIFY_TEST_ROOT}/etc/os-release"

readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_UNSUPPORTED=2
readonly EXIT_MANIFEST=5

REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
SKIP_NETWORK=false
PASS_COUNT=0
WARNING_COUNT=0
FAIL_COUNT=0
NA_COUNT=0
MANIFEST_RELEASE="unavailable"
declare -a REMEDIATIONS=()

header() { printf '\n============================================================\n%s\n============================================================\n' "$1"; }
info() { printf '[INFO] %s\n' "$1"; }
notice() { printf '[NOTICE] %s\n' "$1"; }

usage() {
    cat <<USAGE
Usage: verify_ubg.sh [--help] [--version]
                     [--deployment-profile ubuntu_gnome_bare_metal]
                     [--skip-network]
Read-only verification of the Ubuntu GNOME IT 140 environment and ~/Repos.

Exit codes:
  0  All required checks passed; warnings may be present
  1  One or more required checks failed
  2  Unsupported execution context
  5  Manifest or schema validation failed

Logs: ~/it140/logs/
USAGE
}

parse() {
    while (($#)); do
        case "$1" in
            --help|-h) usage; exit "$EXIT_SUCCESS" ;;
            --version) printf '%s (%s)\n' "$SCRIPT_VERSION" "$VERSION_DTG"; exit "$EXIT_SUCCESS" ;;
            --deployment-profile|--profile)
                shift
                (($#)) || { printf '[ERROR] Missing deployment profile.\n' >&2; exit "$EXIT_UNSUPPORTED"; }
                REQUESTED_PROFILE="$1"
                ;;
            --skip-network) SKIP_NETWORK=true ;;
            *) printf '[ERROR] Unsupported option: %s\n' "$1" >&2; usage >&2; exit "$EXIT_UNSUPPORTED" ;;
        esac
        shift
    done
}

add_remediation() {
    local text="$1" item
    [[ -n "$text" ]] || return 0
    for item in "${REMEDIATIONS[@]:-}"; do [[ "$item" == "$text" ]] && return 0; done
    REMEDIATIONS+=("$text")
}

record() {
    local status="$1" check_id="$2" detail="$3" remediation="${4:-}"
    printf '%-14s %-38s %s\n' "$status" "$check_id" "$detail"
    case "$status" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        WARNING) WARNING_COUNT=$((WARNING_COUNT + 1)); add_remediation "$remediation" ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)); add_remediation "$remediation" ;;
        'NOT APPLICABLE') NA_COUNT=$((NA_COUNT + 1)) ;;
    esac
}

config_remediation() { printf 'Run config_ubg.sh to repair current-user configuration.\n'; }
setup_remediation() { printf 'Run setup_ubg.sh to repair required system software, then rerun verify_ubg.sh.\n'; }
continuity() { notice "Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved."; }
desktop_dir() { xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop\n' "$HOME"; }

validate_manifest() {
    python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
import json
import pathlib
import sys

manifest_path, schema_path, platform_id, profile_id, supported_schema = sys.argv[1:]
try:
    manifest = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"))
    schema = json.loads(pathlib.Path(schema_path).read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"controlled JSON validation failed: {exc}")
if manifest.get("schema_version") != supported_schema:
    raise SystemExit("unsupported manifest schema")
platform = manifest.get("platforms", {}).get(platform_id)
profile = manifest.get("deployment_profiles", {}).get(profile_id)
if not platform or not platform.get("enabled") or not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("Ubuntu GNOME profile invalid")
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

manifest_query() {
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$1" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
bindings = manifest["platforms"][sys.argv[2]]["course_ide_bindings"]
query = sys.argv[3]
if query == "venv_packages":
    values = []
    for role, binding in bindings.items():
        if binding.get("required") and binding.get("installation_scope") == "user" and binding.get("installer_adapter_id") == "python_venv_package":
            values.append(binding["package_identifier"])
        if role == "code_quality_tool" and binding.get("required"):
            values.append("ruff")
    print("\n".join(sorted(set(values))))
elif query == "extensions":
    print("\n".join(binding["package_identifier"] for binding in bindings.values() if binding.get("required") and binding.get("installer_adapter_id") == "vscode_extension"))
elif query == "git_settings":
    for profile_id in bindings["version_control_system"].get("settings_profile_ids", []):
        for key, value in manifest["managed_settings"][profile_id]["values"].items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            print(f"{key}\t{value}")
elif query == "vscode_settings":
    values = {}
    for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
        values.update(manifest["managed_settings"][profile_id]["values"])
    print(json.dumps(values, separators=(",", ":")))
PY
}

check_platform() {
    if [[ ! -r "$OS_RELEASE_PATH" ]]; then
        record FAIL verify.os "Cannot read $OS_RELEASE_PATH" "Use Ubuntu 24.04 LTS GNOME."
    else
        # shellcheck disable=SC1090
        source "$OS_RELEASE_PATH"
        [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] \
            && record PASS verify.os "${PRETTY_NAME:-Ubuntu 24.04}" \
            || record FAIL verify.os "unsupported OS" "Use Ubuntu 24.04 LTS GNOME."
    fi
    local architecture
    architecture="$(uname -m 2>/dev/null || true)"
    [[ "$architecture" == x86_64 ]] \
        && record PASS verify.architecture x86_64 \
        || record FAIL verify.architecture "${architecture:-unknown}" "Use the approved x86_64 profile."
    ((VERIFY_EFFECTIVE_UID != 0)) \
        && record PASS verify.user_context "standard user" \
        || record FAIL verify.user_context root "Run Verify without sudo."
    command -v gio >/dev/null 2>&1 \
        && record PASS verify.gio available \
        || record FAIL verify.gio missing "$(setup_remediation)"
}

check_network() {
    if [[ "$SKIP_NETWORK" == true ]]; then
        record WARNING verify.network skipped "Rerun without --skip-network."
        return
    fi
    curl -Is --max-time 10 https://github.com/ >/dev/null 2>&1 \
        && record PASS verify.network "github.com reachable" \
        || record WARNING verify.network "github.com unreachable" "Check the network and rerun Verify."
}

check_system() {
    local command_name
    for command_name in git gh python3.12 code gio; do
        command -v "$command_name" >/dev/null 2>&1 \
            && record PASS "verify.command.$command_name" available \
            || record FAIL "verify.command.$command_name" missing "$(setup_remediation)"
    done
}

check_user() {
    [[ -d "$COURSE_ROOT" ]] && record PASS verify.course_root "$COURSE_ROOT" || record FAIL verify.course_root missing "Run bootstrap_ubg.sh to refresh the course package."
    [[ -d "$LOG_DIR" && -w "$LOG_DIR" ]] && record PASS verify.log_directory "$LOG_DIR" || record FAIL verify.log_directory "missing or not writable" "Run bootstrap_ubg.sh."
    grep -Fqx "$PATH_EXPORT" "$HOME/.bashrc" 2>/dev/null && record PASS verify.path_bashrc configured || record FAIL verify.path_bashrc missing "$(config_remediation)"
    grep -Fqx "$PATH_EXPORT" "$HOME/.profile" 2>/dev/null && record PASS verify.path_profile configured || record FAIL verify.path_profile missing "$(config_remediation)"
    [[ -x "$VENV_DIR/bin/python" ]] && record PASS verify.venv "$VENV_DIR" || record FAIL verify.venv missing "$(config_remediation)"

    local package extension installed key expected actual
    if [[ -x "$VENV_DIR/bin/python" ]]; then
        while IFS= read -r package; do
            [[ -n "$package" ]] || continue
            "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1 \
                && record PASS "verify.python_package.$package" installed \
                || record FAIL "verify.python_package.$package" missing "$(config_remediation)"
        done < <(manifest_query venv_packages)
    fi
    if command -v code >/dev/null 2>&1; then
        installed="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        while IFS= read -r extension; do
            [[ -n "$extension" ]] || continue
            grep -Fqx "${extension,,}" <<< "$installed" \
                && record PASS "verify.extension.$extension" installed \
                || record FAIL "verify.extension.$extension" missing "$(config_remediation)"
        done < <(manifest_query extensions)
    fi
    gh auth status --hostname github.com >/dev/null 2>&1 && record PASS verify.github_auth authenticated || record FAIL verify.github_auth missing "$(config_remediation)"
    [[ -n "$(git config --global --get user.name 2>/dev/null || true)" ]] && record PASS verify.git_name configured || record FAIL verify.git_name missing "$(config_remediation)"
    [[ "$(git config --global --get user.email 2>/dev/null || true)" == *@users.noreply.github.com ]] && record PASS verify.git_email private || record FAIL verify.git_email invalid "$(config_remediation)"
    while IFS=$'\t' read -r key expected; do
        [[ -n "$key" ]] || continue
        actual="$(git config --global --get "$key" 2>/dev/null || true)"
        [[ "$actual" == "$expected" ]] \
            && record PASS "verify.git_setting.$key" "$expected" \
            || record FAIL "verify.git_setting.$key" "expected '$expected'; got '$actual'" "$(config_remediation)"
    done < <(manifest_query git_settings)

    local settings="$HOME/.config/Code/User/settings.json"
    local managed="$(manifest_query vscode_settings)"
    if [[ -f "$settings" ]] && IT140_SETTINGS="$settings" IT140_MANAGED="$managed" IT140_PY="$VENV_DIR/bin/python" python3 - <<'PY'
import json
import os

managed = json.loads(os.environ["IT140_MANAGED"])
managed["python.defaultInterpreterPath"] = os.environ["IT140_PY"]
actual = json.load(open(os.environ["IT140_SETTINGS"], encoding="utf-8"))
def includes(actual_value, expected_value):
    return all(key in actual_value and (includes(actual_value[key], value) if isinstance(value, dict) and isinstance(actual_value[key], dict) else actual_value[key] == value) for key, value in expected_value.items())
raise SystemExit(0 if isinstance(actual, dict) and includes(actual, managed) else 1)
PY
    then
        record PASS verify.vscode_settings configured
    else
        record FAIL verify.vscode_settings "missing or different" "$(config_remediation)"
    fi

    [[ -d "$REPOS_ROOT" && -r "$REPOS_ROOT" && -x "$REPOS_ROOT" ]] && record PASS verify.repository_workspace "$REPOS_ROOT" || record FAIL verify.repository_workspace missing "$(config_remediation)"
    local link="$(desktop_dir)/Repos"
    [[ -L "$link" && "$(readlink -f "$link")" == "$(readlink -f "$REPOS_ROOT" 2>/dev/null || true)" ]] \
        && record PASS verify.repository_workspace_desktop "Desktop/Repos -> $REPOS_ROOT" \
        || record FAIL verify.repository_workspace_desktop incorrect "$(config_remediation)"
    local marker="$(gio info -a metadata::custom-icon-name "$REPOS_ROOT" 2>/dev/null || true)"
    if grep -Eq 'metadata::custom-icon-name:.*applications-development' <<< "$marker"; then
        record PASS verify.repository_workspace_marker "GNOME development icon metadata present"
    else
        record WARNING verify.repository_workspace_marker "GNOME development icon metadata unavailable or not rendered" "Run config_ubg.sh; workspace functionality is unaffected if GNOME does not support the marker."
    fi
}

finalize() {
    local forced_exit="${1:-}" exit_code result
    if [[ -n "$forced_exit" ]]; then
        exit_code="$forced_exit"
    elif ((FAIL_COUNT > 0)); then
        exit_code="$EXIT_FAILURE"
    else
        exit_code="$EXIT_SUCCESS"
    fi
    ((exit_code == EXIT_SUCCESS)) && result="COMPLIANT" || result="NOT COMPLIANT"
    header "VERIFICATION SUMMARY"
    printf 'Result          : %s\nScript version  : %s\nVersion DTG     : %s\nManifest release: %s\nPassed          : %s\nWarnings        : %s\nFailed          : %s\nNot applicable  : %s\nLog file        : %s\nExit code       : %s\n' \
        "$result" "$SCRIPT_VERSION" "$VERSION_DTG" "$MANIFEST_RELEASE" "$PASS_COUNT" "$WARNING_COUNT" "$FAIL_COUNT" "$NA_COUNT" "$LOG_FILE" "$exit_code"
    if ((${#REMEDIATIONS[@]})); then
        printf '\nRemediation:\n'
        local remediation
        for remediation in "${REMEDIATIONS[@]}"; do printf -- '- %s\n' "$remediation"; done
    fi
    ((exit_code == EXIT_SUCCESS)) || continuity
    return "$exit_code"
}

main() {
    parse "$@"
    if [[ -n "$VERIFY_TEST_ROOT" && "$VERIFY_TEST_ROOT" != /* ]]; then
        printf '[ERROR] IT140_VERIFY_TEST_ROOT must be an absolute path.\n' >&2
        exit "$EXIT_UNSUPPORTED"
    fi
    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    touch "$LOG_FILE"
    chmod 0600 "$LOG_FILE"
    if [[ -n "$VERIFY_TEST_ROOT" ]]; then
        exec >> "$LOG_FILE" 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    header "IT 140 UBUNTU GNOME VERIFY"
    info "Script version : $SCRIPT_VERSION"
    info "Version DTG    : $VERSION_DTG"
    info "Course root    : $COURSE_ROOT"
    info "Repository root: $REPOS_ROOT"
    info "Log file       : $LOG_FILE"
    notice "Verify is read-only except for this transcript."

    if [[ "$REQUESTED_PROFILE" != "$DEPLOYMENT_PROFILE_ID" ]]; then
        record FAIL verify.profile "unsupported profile: $REQUESTED_PROFILE" "Use --deployment-profile ubuntu_gnome_bare_metal."
        finalize "$EXIT_UNSUPPORTED"
        exit $?
    fi

    check_platform
    if [[ ! -r "$MANIFEST_PATH" || ! -r "$SCHEMA_PATH" ]]; then
        record FAIL verify.manifest "manifest or schema missing" "Run bootstrap_ubg.sh."
        finalize "$EXIT_MANIFEST"
        exit $?
    fi
    local manifest_info
    if ! manifest_info="$(validate_manifest 2>&1)"; then
        record FAIL verify.manifest "$manifest_info" "Run bootstrap_ubg.sh."
        finalize "$EXIT_MANIFEST"
        exit $?
    fi
    MANIFEST_RELEASE="$manifest_info"
    record PASS verify.manifest "release $MANIFEST_RELEASE"
    check_network
    check_system
    check_user
    finalize
}

main "$@"
