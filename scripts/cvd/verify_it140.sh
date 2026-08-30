#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop read-only verification script
#
# Artifact ID: IT140-CVD-VERIFY
# Artifact version: 1.0.1
# Version date-time group: 2026-08-30-07-01
# Development status: Pilot — Active Development
#
# Traceability: VER-FR-001 through VER-FR-018; PKG-FR-021;
#               VER-DES-001 through VER-DES-018; PLT-DES-006; ERR-DES-014.
#
# State boundary: verification never repairs the system, desktop integration,
# or ~/Repos. The required transcript and an explicitly requested sanitized
# support directory are the only files this script creates.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="1.0.1"
readonly VERSION_DTG="2026-08-30-07-01"
readonly DEVELOPMENT_STATUS="Beta Testing"
readonly SUPPORTED_SCHEMA="2.2"
readonly PLATFORM_ID="cvd"
readonly DEPLOYMENT_PROFILE_ID="codio_cvd"
readonly COURSE_ROOT="${HOME}/it140"
readonly REPOS_ROOT="${HOME}/Repos"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly PLATFORM_SCRIPT_DIR="${SCRIPT_ROOT}/${PLATFORM_ID}"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/verify_cvd_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
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
readonly NUMLOCK_AUTOSTART_PATH="${VERIFY_TEST_ROOT}/etc/xdg/autostart/numlockx.desktop"
readonly -a CVD_BASELINE_DESKTOP_LAUNCHERS=("it140.desktop" "GitHub Login.desktop" "OneDrive Login.desktop")
readonly MANAGED_PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/cvd:$PATH"'
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_UNSUPPORTED=2
readonly EXIT_MANIFEST=5

REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
SUPPORT_BUNDLE=false
ASSUME_YES=false
SKIP_NETWORK=false
PASS_COUNT=0
WARNING_COUNT=0
FAIL_COUNT=0
NA_COUNT=0
MANIFEST_RELEASE="unavailable"
MANIFEST_DTG="unavailable"
START_EPOCH="$(date +%s)"
START_TIME="$(date --iso-8601=seconds)"
FINALIZED=false
REMediation_FILE=""

declare -a REMEDIATIONS=()
print_header() { printf '\n============================================================\n%s\n============================================================\n' "$1"; }
print_info() { printf '[INFO] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }

usage() {
    cat <<USAGE
Usage: verify_it140.sh [--help] [--version] [--deployment-profile codio_cvd]
                     [--support-bundle] [--yes] [--skip-network]
Verifies the IT 140 CVD system and current-user configuration without repairing
it. The script does not create probe files or change metadata under ~/Repos.

Exit codes:
  0  All required checks passed; warnings may be present
  1  One or more required checks failed
  2  Unsupported execution context
  5  Manifest or schema validation failed

Logs: ~/it140/logs/
USAGE
}
parse_options() {
    while (($#)); do
        case "$1" in
            --help|-h) usage; exit 0 ;;
            --version) printf '%s (%s; %s)\n' "$SCRIPT_VERSION" "$VERSION_DTG" "$DEVELOPMENT_STATUS"; exit 0 ;;
            --deployment-profile) shift; [[ $# -gt 0 ]] || { printf '[ERROR] Missing deployment profile.\n' >&2; exit 2; }; REQUESTED_PROFILE="$1" ;;
            --support-bundle) SUPPORT_BUNDLE=true ;;
            --yes) ASSUME_YES=true ;;
            --skip-network) SKIP_NETWORK=true ;;
            *) printf '[ERROR] Unsupported option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
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
record_result() {
    local status="$1" check_id="$2" detail="$3" remediation="${4:-}"
    printf '%-14s %-38s %s\n' "$status" "$check_id" "$detail"
    case "$status" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        WARNING) WARNING_COUNT=$((WARNING_COUNT + 1)); add_remediation "$remediation" ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)); add_remediation "$remediation" ;;
        "NOT APPLICABLE") NA_COUNT=$((NA_COUNT + 1)) ;;
    esac
}
config_remediation() { printf '%s\n' "Run configure_it140.sh to repair the current-user configuration."; }
install_remediation() { printf '%s\n' "Run update_it140.sh on the CVD to repair required system components, then rerun verify_it140.sh."; }
prepare_remediation() { printf '%s\n' "Run prepare_it140.sh to refresh the course automation package, then rerun verify_it140.sh."; }
course_continuity_guidance() {
    print_notice "This issue affects the Codio Virtual Desktop (CVD)."
    print_notice "Follow the remediation above. If it continues, contact course support and include the log file."
}

desktop_directory() { xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop\n' "$HOME"; }
find_vscode_launcher() {
    local desktop_dir candidate
    desktop_dir="$(desktop_directory)"; [[ -d "$desktop_dir" ]] || return 1
    for candidate in "$desktop_dir/visual-studio-code.desktop" "$desktop_dir/code.desktop" "$desktop_dir/Visual Studio Code.desktop"; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    while IFS= read -r -d '' candidate; do
        if grep -Eiq '^Name=.*Visual Studio Code|^Exec=([^[:space:]]*/)?code([[:space:]]|$)' "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
    done < <(find "$desktop_dir" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)
    return 1
}
launcher_opens_repos_root() {
    local launcher="$1"
    python3 - "$launcher" "$REPOS_ROOT" "$COURSE_ROOT" <<'PY'
import pathlib,shlex,sys
path=pathlib.Path(sys.argv[1]); workspace=sys.argv[2]; course=sys.argv[3]
lines=path.read_text(encoding="utf-8").splitlines(); in_desktop=False; exec_value=None; path_value=None
for line in lines:
    stripped=line.strip()
    if stripped.startswith("[") and stripped.endswith("]"): in_desktop=(stripped=="[Desktop Entry]"); continue
    if in_desktop and stripped.startswith("Exec=") and exec_value is None: exec_value=stripped[5:]
    if in_desktop and stripped.startswith("Path=") and path_value is None: path_value=stripped[5:]
if not exec_value: raise SystemExit(1)
args=[a for a in shlex.split(exec_value) if not (a.startswith("%") and len(a)==2)]
if not args or pathlib.Path(args[0]).name != "code" or workspace not in args: raise SystemExit(1)
if path_value != workspace: raise SystemExit(1)
# Reject a launcher that still explicitly opens the automation root as a folder.
if course in args: raise SystemExit(1)
PY
}
launcher_is_xfce_trusted() {
    local launcher="$1" current_checksum stored_checksum
    [[ -f "$launcher" && -x "$launcher" ]] || return 1
    current_checksum="$(sha256sum -- "$launcher" 2>/dev/null | awk '{print $1}')"
    [[ -n "$current_checksum" ]] || return 1
    stored_checksum="$(gio info -a metadata::xfce-exe-checksum "$launcher" 2>/dev/null \
        | sed -n 's/^[[:space:]]*metadata::xfce-exe-checksum:[[:space:]]*//p' \
        | head -n 1)"
    [[ "$stored_checksum" == "$current_checksum" ]]
}
numlock_is_on() {
    local status
    command -v numlockx >/dev/null 2>&1 || return 1
    status="$(numlockx status 2>&1)" || return 1
    grep -Eiq '(^|[[:space:]])on([[:space:]]|$)' <<< "$status"
}
validate_manifest() {
    python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
import json,pathlib,sys
manifest_path,schema_path,platform_id,profile_id,supported_schema=sys.argv[1:]
try:
    manifest=json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"))
    schema=json.loads(pathlib.Path(schema_path).read_text(encoding="utf-8"))
except Exception as exc: raise SystemExit(f"controlled JSON validation failed: {exc}")
if manifest.get("schema_version") != supported_schema: raise SystemExit(f"unsupported schema {manifest.get('schema_version')!r}")
platform=manifest.get("platforms",{}).get(platform_id); profile=manifest.get("deployment_profiles",{}).get(profile_id)
if not platform or not platform.get("enabled"): raise SystemExit("CVD platform missing or disabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id: raise SystemExit("CVD deployment profile invalid")
try:
    import jsonschema  # type: ignore
except ImportError: pass
else:
    jsonschema.Draft202012Validator.check_schema(schema); jsonschema.Draft202012Validator(schema).validate(manifest)
print(f"{manifest['automation_release']}\t{manifest.get('automation_release_date_time_group') or manifest.get('automation_release_date') or 'unavailable'}")
PY
}
manifest_query() {
    local query="$1"
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json,sys
manifest=json.load(open(sys.argv[1],encoding="utf-8")); platform=manifest["platforms"][sys.argv[2]]; query=sys.argv[3]; bindings=platform["course_ide_bindings"]
if query=="system_commands":
    vals=[]
    for b in bindings.values():
        if b.get("required") and b.get("installation_scope")=="system": vals.extend(b.get("verification",{}).get("executable_names",[]))
    print("\n".join(sorted(set(vals))))
elif query=="venv_packages":
    vals=[]
    for role,b in bindings.items():
        if b.get("required") and b.get("installation_scope")=="user" and b.get("installer_adapter_id")=="python_venv_package": vals.append(b["package_identifier"])
        if role=="code_quality_tool" and b.get("required"): vals.append("ruff")
    print("\n".join(sorted(set(vals))))
elif query=="extensions":
    vals=[]
    for b in bindings.values():
        if b.get("required") and b.get("installation_scope")=="user" and b.get("installer_adapter_id")=="vscode_extension": vals.append(b["package_identifier"])
    print("\n".join(vals))
elif query=="git_settings":
    for pid in bindings["version_control_system"].get("settings_profile_ids",[]):
        for k,v in manifest["managed_settings"][pid]["values"].items():
            if isinstance(v,bool): v="true" if v else "false"
            print(f"{k}\t{v}")
elif query=="vscode_settings":
    merged={}
    for pid in bindings["source_code_ide"].get("settings_profile_ids",[]): merged.update(manifest["managed_settings"][pid]["values"])
    print(json.dumps(merged,separators=(",",":"),sort_keys=True))
PY
}
check_platform_context() {
    if ((VERIFY_EFFECTIVE_UID == 0)); then record_result FAIL verify.user_context "Verify must run as the standard CVD user, not root." "Run verify_it140.sh without sudo."; return; fi
    [[ -r "$OS_RELEASE_PATH" ]] || { record_result FAIL verify.os "Cannot read /etc/os-release." "Contact course support."; return; }
    # shellcheck disable=SC1090
    source "$OS_RELEASE_PATH"
    if [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]]; then record_result PASS verify.os "${PRETTY_NAME:-Ubuntu 24.04}"; else record_result FAIL verify.os "Unsupported: ${PRETTY_NAME:-unknown}" "Use the approved IT 140 CVD."; fi
    local architecture; architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" == amd64 || "$architecture" == x86_64 ]]; then record_result PASS verify.architecture "$architecture"; else record_result FAIL verify.architecture "$architecture" "Use the approved x86_64 CVD."; fi
    command -v xfconf-query >/dev/null 2>&1 && record_result PASS verify.desktop "Xfce management interface available" || record_result FAIL verify.desktop "Xfce management interface unavailable" "$(config_remediation)"
    command -v gio >/dev/null 2>&1 && record_result PASS verify.gio "GIO metadata interface available" || record_result FAIL verify.gio "GIO metadata interface unavailable" "$(install_remediation)"
}
check_network() {
    if [[ "$SKIP_NETWORK" == true ]]; then record_result WARNING verify.network "Network check skipped by option" "Rerun Verify without --skip-network when network access is available."; return; fi
    if curl --head --silent --fail --max-time 10 https://github.com/ >/dev/null 2>&1; then record_result PASS verify.network "github.com reachable"; else record_result WARNING verify.network "github.com could not be reached" "Check network access and rerun Verify."; fi
}
check_system_layer() {
    local command_name failed=0
    while IFS= read -r command_name; do
        [[ -n "$command_name" ]] || continue
        if command -v "$command_name" >/dev/null 2>&1; then
            record_result PASS "verify.command.$command_name" "available"
        else
            record_result FAIL "verify.command.$command_name" "missing" "$(install_remediation)"
            failed=1
        fi
    done < <(manifest_query system_commands)
    if command -v python3.12 >/dev/null 2>&1; then
        record_result PASS verify.python312 "python3.12 available"
    else
        record_result FAIL verify.python312 "python3.12 missing" "$(install_remediation)"
    fi
    if dpkg-query -W -f='${Status}' numlockx 2>/dev/null | grep -Fqx 'install ok installed'; then
        record_result PASS verify.package.numlockx "installed"
    else
        record_result FAIL verify.package.numlockx "missing" "$(install_remediation)"
    fi
    if command -v numlockx >/dev/null 2>&1; then
        record_result PASS verify.command.numlockx "available"
    else
        record_result FAIL verify.command.numlockx "missing" "$(install_remediation)"
    fi
    if [[ -r "$NUMLOCK_AUTOSTART_PATH" ]] \
            && grep -Fqx 'Exec=/usr/bin/numlockx on' "$NUMLOCK_AUTOSTART_PATH" \
            && grep -Fqx 'OnlyShowIn=XFCE;' "$NUMLOCK_AUTOSTART_PATH"; then
        if command -v desktop-file-validate >/dev/null 2>&1 \
                && ! desktop-file-validate "$NUMLOCK_AUTOSTART_PATH" >/dev/null 2>&1; then
            record_result FAIL verify.numlock_autostart "desktop entry is invalid" "$(install_remediation)"
        else
            record_result PASS verify.numlock_autostart "Xfce startup enables Num Lock"
        fi
    else
        record_result FAIL verify.numlock_autostart "missing or incorrect" "$(install_remediation)"
    fi
    [[ $failed -eq 0 ]] || true
}
check_user_layer() {
    local package extension installed_extensions key expected actual desktop_dir shortcut marker launcher settings_json name path
    [[ -d "$COURSE_ROOT" ]] && record_result PASS verify.course_root "$COURSE_ROOT" || record_result FAIL verify.course_root "missing" "$(prepare_remediation)"
    [[ -d "$LOG_DIR" && -w "$LOG_DIR" ]] && record_result PASS verify.log_directory "$LOG_DIR" || record_result FAIL verify.log_directory "missing or not writable" "$(prepare_remediation)"
    [[ -f "$HOME/.bashrc" && $(grep -Fxc "$MANAGED_PATH_EXPORT" "$HOME/.bashrc" 2>/dev/null || true) -ge 1 ]] && record_result PASS verify.path_bashrc "managed PATH present" || record_result FAIL verify.path_bashrc "managed PATH missing" "$(config_remediation)"
    [[ -f "$HOME/.profile" && $(grep -Fxc "$MANAGED_PATH_EXPORT" "$HOME/.profile" 2>/dev/null || true) -ge 1 ]] && record_result PASS verify.path_profile "managed PATH present" || record_result FAIL verify.path_profile "managed PATH missing" "$(config_remediation)"
    if [[ -x "$VENV_DIR/bin/python" ]]; then record_result PASS verify.venv "$VENV_DIR"; else record_result FAIL verify.venv "missing" "$(config_remediation)"; fi
    if [[ -x "$VENV_DIR/bin/python" ]]; then
        while IFS= read -r package; do [[ -n "$package" ]] || continue; if "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then record_result PASS "verify.python_package.$package" "installed"; else record_result FAIL "verify.python_package.$package" "missing" "$(config_remediation)"; fi; done < <(manifest_query venv_packages)
    fi
    if command -v code >/dev/null 2>&1; then
        installed_extensions="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        while IFS= read -r extension; do [[ -n "$extension" ]] || continue; if grep -Fqx "${extension,,}" <<< "$installed_extensions"; then record_result PASS "verify.extension.$extension" "installed"; else record_result FAIL "verify.extension.$extension" "missing" "$(config_remediation)"; fi; done < <(manifest_query extensions)
    fi
    gh auth status --hostname github.com >/dev/null 2>&1 && record_result PASS verify.github_auth "authenticated" || record_result FAIL verify.github_auth "not authenticated" "$(config_remediation)"
    [[ -n "$(git config --global --get user.name 2>/dev/null || true)" ]] && record_result PASS verify.git_name "configured" || record_result FAIL verify.git_name "missing" "$(config_remediation)"
    if [[ "$(git config --global --get user.email 2>/dev/null || true)" =~ ^[0-9]+\+[^@[:space:]]+@users\.noreply\.github\.com$ ]]; then record_result PASS verify.git_email "private GitHub noreply identity configured"; else record_result FAIL verify.git_email "privacy-preserving identity missing" "$(config_remediation)"; fi
    while IFS=$'\t' read -r key expected; do [[ -n "$key" ]] || continue; actual="$(git config --global --get "$key" 2>/dev/null || true)"; if [[ "$actual" == "$expected" ]]; then record_result PASS "verify.git_setting.$key" "$expected"; else record_result FAIL "verify.git_setting.$key" "expected '$expected'; observed '$actual'" "$(config_remediation)"; fi; done < <(manifest_query git_settings)
    settings_json="$(manifest_query vscode_settings 2>/dev/null || printf '{}')"
    if [[ -f "$HOME/.config/Code/User/settings.json" ]]; then
        if IT140_EXPECTED="$settings_json" IT140_SETTINGS="$HOME/.config/Code/User/settings.json" IT140_VENV="$VENV_DIR/bin/python" python3 - <<'PY'
import json,os
expected=json.loads(os.environ["IT140_EXPECTED"]); expected["python.defaultInterpreterPath"]=os.environ["IT140_VENV"]
actual=json.load(open(os.environ["IT140_SETTINGS"],encoding="utf-8"))
def includes(a,e):
    return all(k in a and (includes(a[k],v) if isinstance(v,dict) and isinstance(a[k],dict) else a[k]==v) for k,v in e.items())
raise SystemExit(0 if isinstance(actual,dict) and includes(actual,expected) else 1)
PY
        then record_result PASS verify.vscode_settings "managed settings present"; else record_result FAIL verify.vscode_settings "managed settings missing or invalid" "$(config_remediation)"; fi
    else record_result FAIL verify.vscode_settings "settings.json missing" "$(config_remediation)"; fi
    # Repository workspace checks are shallow and read-only by design.
    if [[ -d "$REPOS_ROOT" && -r "$REPOS_ROOT" && -x "$REPOS_ROOT" ]]; then
        record_result PASS verify.repository_workspace "$REPOS_ROOT"
    else
        record_result FAIL verify.repository_workspace "missing or inaccessible" "$(config_remediation)"
    fi
    desktop_dir="$(desktop_directory)"; shortcut="$desktop_dir/Repos"
    if [[ -L "$shortcut" && "$(readlink -f -- "$shortcut" 2>/dev/null || true)" == "$(readlink -f -- "$REPOS_ROOT" 2>/dev/null || true)" ]]; then
        record_result PASS verify.repository_workspace_desktop "Desktop/Repos -> $REPOS_ROOT"
    else
        record_result FAIL verify.repository_workspace_desktop "desktop Repos link missing or incorrect" "$(config_remediation)"
    fi
    marker="$(gio info -a metadata::emblems "$REPOS_ROOT" 2>/dev/null || true)"
    if grep -Eq 'metadata::emblems:.*development' <<< "$marker"; then
        record_result PASS verify.repository_workspace_marker "Xfce development emblem present"
    else
        record_result FAIL verify.repository_workspace_marker "Xfce development emblem missing" "$(config_remediation)"
    fi
    for name in "${CVD_BASELINE_DESKTOP_LAUNCHERS[@]}"; do
        path="$desktop_dir/$name"
        if [[ ! -e "$path" && ! -L "$path" ]]; then
            record_result PASS "verify.desktop_cleanup.${name//[^[:alnum:]]/_}" "absent"
        else
            record_result FAIL "verify.desktop_cleanup.${name//[^[:alnum:]]/_}" "unwanted baseline launcher remains: $name" "$(config_remediation)"
        fi
    done
    launcher="$(find_vscode_launcher 2>/dev/null || true)"
    if [[ -n "$launcher" ]] && launcher_opens_repos_root "$launcher"; then
        record_result PASS verify.vscode_workspace_launcher "opens $REPOS_ROOT"
    else
        record_result FAIL verify.vscode_workspace_launcher "existing launcher does not open $REPOS_ROOT" "$(config_remediation)"
    fi
    if [[ -n "$launcher" && -x "$launcher" ]]; then
        record_result PASS verify.vscode_launcher_executable "launcher is executable"
    else
        record_result FAIL verify.vscode_launcher_executable "launcher is not executable" "$(config_remediation)"
    fi
    if [[ -n "$launcher" ]] && launcher_is_xfce_trusted "$launcher"; then
        record_result PASS verify.vscode_launcher_trust "Xfce checksum trust is current"
    else
        record_result FAIL verify.vscode_launcher_trust "Xfce checksum trust is missing or stale" "$(config_remediation)"
    fi
    if [[ -n "$launcher" && -x "$launcher" ]] && command -v desktop-file-validate >/dev/null 2>&1; then
        if desktop-file-validate "$launcher" >/dev/null 2>&1; then
            record_result PASS verify.vscode_launcher_format "desktop entry is valid"
        else
            record_result FAIL verify.vscode_launcher_format "desktop entry is invalid" "$(config_remediation)"
        fi
    fi
    if numlock_is_on; then
        record_result PASS verify.numlock_session "Num Lock is ON"
    else
        record_result FAIL verify.numlock_session "Num Lock is not ON in the current Xfce session" "$(config_remediation)"
    fi
}
create_support_directory() {
    [[ "$SUPPORT_BUNDLE" == true ]] || return 0
    if [[ "$ASSUME_YES" == false ]]; then
        printf 'Create a sanitized diagnostic support directory under ~/it140/logs/? [y/N] '
        local answer; IFS= read -r answer
        [[ "${answer,,}" == y || "${answer,,}" == yes ]] || { print_notice "Support-directory creation canceled."; return 0; }
    fi
    local support_dir="$LOG_DIR/it140_support_cvd_$(date +%Y%m%d_%H%M%S)"
    mkdir -m 0700 -- "$support_dir"
    {
        printf 'IT 140 CVD sanitized support summary\n'
        printf 'Script version: %s\nVersion DTG: %s\nManifest release: %s\n' "$SCRIPT_VERSION" "$VERSION_DTG" "$MANIFEST_RELEASE"
        printf 'OS: '; grep '^PRETTY_NAME=' "$OS_RELEASE_PATH" | cut -d= -f2- | tr -d '"'
        printf 'Architecture: %s\n' "$(uname -m)"
        printf 'Desktop: %s\n' "${XDG_CURRENT_DESKTOP:-unknown}"
        printf 'Repos exists: %s\n' "$( [[ -d "$REPOS_ROOT" ]] && printf yes || printf no )"
        printf 'Repos desktop link valid: %s\n' "$( [[ -L "$(desktop_directory)/Repos" ]] && printf yes || printf no )"
        printf 'Num Lock current: %s\n' "$( numlock_is_on && printf on || printf off-or-unavailable )"
        local support_launcher; support_launcher="$(find_vscode_launcher 2>/dev/null || true)"
        printf 'VS Code launcher trusted: %s\n' "$( [[ -n "$support_launcher" ]] && launcher_is_xfce_trusted "$support_launcher" && printf yes || printf no )"
    } > "$support_dir/system_summary.txt"
    cp -- "$LOG_FILE" "$support_dir/verification.log"
    chmod 0600 "$support_dir"/*
    print_notice "Sanitized support directory: $support_dir"
    print_notice "Student repository contents and Git history were not included."
}
finalize() {
    local forced_exit="${1:-}" exit_code elapsed result
    if [[ -n "$forced_exit" ]]; then
        exit_code="$forced_exit"
        result="NOT COMPLIANT"
    elif ((FAIL_COUNT > 0)); then
        exit_code="$EXIT_FAILURE"
        result="NOT COMPLIANT"
    else
        exit_code="$EXIT_SUCCESS"
        result="COMPLIANT"
    fi
    elapsed=$(( $(date +%s) - START_EPOCH ))
    print_header "VERIFICATION SUMMARY"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Version DTG     : %s\n' "$VERSION_DTG"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'Manifest DTG    : %s\n' "$MANIFEST_DTG"
    printf 'Passed          : %s\n' "$PASS_COUNT"
    printf 'Warnings        : %s\n' "$WARNING_COUNT"
    printf 'Failed          : %s\n' "$FAIL_COUNT"
    printf 'Not applicable  : %s\n' "$NA_COUNT"
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : %s\n' "$exit_code"
    if ((${#REMEDIATIONS[@]} > 0)); then
        printf '\nRemediation:\n'; local item; for item in "${REMEDIATIONS[@]}"; do printf -- '- %s\n' "$item"; done
    fi
    ((exit_code == 0)) || course_continuity_guidance
    return "$exit_code"
}
main() {
    parse_options "$@"
    if [[ -n "$VERIFY_TEST_ROOT" && "$VERIFY_TEST_ROOT" != /* ]]; then
        printf '[ERROR] IT140_VERIFY_TEST_ROOT must be an absolute path.\n' >&2
        exit "$EXIT_UNSUPPORTED"
    fi
    mkdir -p "$LOG_DIR"; chmod 0700 "$LOG_DIR"; touch "$LOG_FILE"; chmod 0600 "$LOG_FILE"
    if [[ -n "$VERIFY_TEST_ROOT" ]]; then
        # Test isolation avoids asynchronous process substitution so a short-lived
        # test process cannot leave tee attached after the verifier exits.
        exec >> "$LOG_FILE" 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
    print_header "IT 140 CODIO VIRTUAL DESKTOP VERIFY"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Version DTG    : $VERSION_DTG"
    print_info "Status         : $DEVELOPMENT_STATUS"
    print_info "Current user   : $(id -un)"
    print_info "Course root    : $COURSE_ROOT"
    print_info "Repository root: $REPOS_ROOT"
    print_info "Log file       : $LOG_FILE"
    print_notice "Verification is read-only except for this transcript and an explicitly requested sanitized support directory."
    [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] || { record_result FAIL verify.profile "Unsupported deployment profile: $REQUESTED_PROFILE" "Use --deployment-profile codio_cvd."; finalize "$EXIT_UNSUPPORTED"; exit $?; }
    check_platform_context
    if [[ ! -r "$MANIFEST_PATH" || ! -r "$SCHEMA_PATH" ]]; then
        record_result FAIL verify.manifest "Manifest or schema missing" "$(prepare_remediation)"
        MANIFEST_RELEASE="unavailable"; print_header "VERIFICATION SUMMARY"; printf 'Result          : NOT COMPLIANT\nExit code       : %s\nLog file        : %s\n' "$EXIT_MANIFEST" "$LOG_FILE"; course_continuity_guidance; exit "$EXIT_MANIFEST"
    fi
    local manifest_info
    if ! manifest_info="$(validate_manifest 2>&1)"; then
        record_result FAIL verify.manifest "$manifest_info" "$(prepare_remediation)"
        print_header "VERIFICATION SUMMARY"; printf 'Result          : NOT COMPLIANT\nExit code       : %s\nLog file        : %s\n' "$EXIT_MANIFEST" "$LOG_FILE"; course_continuity_guidance; exit "$EXIT_MANIFEST"
    fi
    IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$manifest_info"
    record_result PASS verify.manifest "release $MANIFEST_RELEASE"
    check_network
    check_system_layer
    check_user_layer
    create_support_directory
    finalize
}
main "$@"
