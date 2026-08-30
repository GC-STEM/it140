#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop user configuration and repair script
#
# Artifact ID: IT140-CVD-CONFIGURE
# Artifact version: 1.0.2
# Version date-time group: 2026-08-30-12-56
# Development status: Pilot — Active Development
#
# Traceability: CFG-FR-001 through CFG-FR-021; PKG-FR-021;
#               CFG-DES-001 through CFG-DES-021; PLT-DES-006; ERR-DES-014.
# Scope: Current-user course configuration, separate ~/Repos development
#        workspace, Xfce workspace emblem and desktop link, and repair of the
#        existing CVD Visual Studio Code launcher to open ~/Repos, removal of
#        obsolete CVD baseline desktop launchers, and current-session Num Lock.
#
# Student-data boundary: this script may create ~/Repos and manage metadata on
# that parent plus course-owned desktop integrations. It never recursively
# enumerates, deletes, moves, chmods, chowns, cleans, or rewrites its children.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="1.0.2"
readonly VERSION_DTG="2026-08-30-12-56"
readonly DEVELOPMENT_STATUS="Pilot — Active Development"
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
readonly LOG_FILE="${LOG_DIR}/configure_cvd_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly LOCK_FILE="${HOME}/.cache/it140-${PLATFORM_ID}-mutation.lock"
readonly -a CVD_BASELINE_DESKTOP_LAUNCHERS=("it140.desktop" "GitHub Login.desktop" "OneDrive Login.desktop")
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
Usage: configure_it140.sh [--help] [--version] [--noninteractive]
                        [--deployment-profile codio_cvd]

Configures or repairs the current user's IT 140 CVD environment. Run as the
standard desktop user, not with sudo. The script creates ~/Repos as the student
repository workspace but never changes repositories stored inside it.
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
            --help|-h) usage; exit "$EXIT_SUCCESS" ;;
            --version)
                printf '%s (%s; %s)\n' "$SCRIPT_VERSION" "$VERSION_DTG" "$DEVELOPMENT_STATUS"
                exit "$EXIT_SUCCESS"
                ;;
            --noninteractive) NONINTERACTIVE=true ;;
            --deployment-profile)
                shift
                [[ $# -gt 0 ]] || { print_error "Missing deployment profile."; exit "$EXIT_UNSUPPORTED"; }
                REQUESTED_PROFILE="$1"
                ;;
            *) print_error "Unsupported option: $1"; usage >&2; exit "$EXIT_UNSUPPORTED" ;;
        esac
        shift
    done
}
resolve_failure_code() {
    local requested="$1"
    case "$requested" in
        "$EXIT_MANIFEST"|"$EXIT_UNSUPPORTED"|"$EXIT_PRIVILEGE"|"$EXIT_EXTERNAL") printf '%s\n' "$requested" ;;
        "$EXIT_PARTIAL") printf '%s\n' "$EXIT_PARTIAL" ;;
        "$EXIT_CANCELED") [[ "$CHANGED" == true ]] && printf '%s\n' "$EXIT_PARTIAL" || printf '%s\n' "$EXIT_CANCELED" ;;
        *) [[ "$CHANGED" == true ]] && printf '%s\n' "$EXIT_PARTIAL" || printf '%s\n' "$EXIT_FAILURE" ;;
    esac
}
course_continuity_guidance() {
    print_notice "This issue affects the Codio Virtual Desktop (CVD)."
    print_notice "Follow the remediation above. If it continues, contact course support and include the log file."
}
finish() {
    local requested_code="${1:-0}" message="${2:-}" exit_code result next_step elapsed
    [[ "$FINALIZED" == false ]] || return "$requested_code"
    FINALIZED=true
    if ((requested_code == 0)); then exit_code=0; else exit_code="$(resolve_failure_code "$requested_code")"; fi
    if ((exit_code == 0)); then
        result="PASS"; next_step="Open a fresh Terminal and run verify_it140.sh."
    elif ((exit_code == EXIT_PARTIAL)); then
        result="PARTIAL"; next_step="Review the errors above, then rerun configure_it140.sh."
    else
        result="FAIL"; next_step="Resolve the reported issue, then rerun configure_it140.sh."
    fi
    elapsed=$(( $(date +%s) - START_EPOCH ))
    print_header "CONFIGURATION SUMMARY"
    [[ -n "$message" ]] && printf 'Conclusion      : %s\n' "$message"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Version DTG     : %s\n' "$VERSION_DTG"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'Manifest DTG    : %s\n' "$MANIFEST_DTG"
    printf 'Repository root : %s\n' "$REPOS_ROOT"
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
    local requested_code="$1"; shift
    local exit_code=0
    FAILURES=$((FAILURES + 1))
    print_error "$*"
    print_error "Failed stage: $CURRENT_STAGE"
    finish "$requested_code" "$*" || exit_code=$?
    exit "$exit_code"
}

on_error() {
    local status=$? line=${BASH_LINENO[0]:-unknown}
    local exit_code=0
    trap - ERR
    FAILURES=$((FAILURES + 1))
    print_error "Configuration stopped near line ${line} during ${CURRENT_STAGE} (status ${status})."
    finish "$EXIT_FAILURE" "An unexpected command failure stopped Configure." || exit_code=$?
    exit "$exit_code"
}
on_interrupt() {
    local exit_code=0
    trap - INT TERM
    print_error "Configuration was interrupted during ${CURRENT_STAGE}."
    finish "$EXIT_CANCELED" "Configure was interrupted; rerun it to recover." || exit_code=$?
    exit "$exit_code"
}
validate_manifest() {
    python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
import json, pathlib, sys
manifest_path, schema_path, platform_id, profile_id, supported_schema = sys.argv[1:]
class DuplicateKeyError(ValueError): pass
def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result: raise DuplicateKeyError(f"duplicate key: {key}")
        result[key] = value
    return result
try:
    manifest = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
    schema = json.loads(pathlib.Path(schema_path).read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError) as exc:
    raise SystemExit(f"controlled JSON validation failed: {exc}")
if manifest.get("schema_version") != supported_schema:
    raise SystemExit(f"unsupported manifest schema: {manifest.get('schema_version')!r}; expected {supported_schema}")
platform = manifest.get("platforms", {}).get(platform_id)
profile = manifest.get("deployment_profiles", {}).get(profile_id)
if not platform or not platform.get("enabled"): raise SystemExit("CVD platform is missing or disabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("CVD deployment profile is invalid")
if "github_com" not in manifest.get("provider_profiles", {}):
    raise SystemExit("required GitHub provider profile is unavailable")
try:
    import jsonschema  # type: ignore
except ImportError:
    pass
else:
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(manifest)
print(f"{manifest['automation_release']}\t{manifest.get('automation_release_date_time_group') or manifest.get('automation_release_date') or 'unavailable'}")
PY
}
manifest_query() {
    local query="$1"
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json, sys
path, platform_id, query = sys.argv[1:]
manifest = json.load(open(path, encoding="utf-8"))
platform = manifest["platforms"][platform_id]
bindings = platform["course_ide_bindings"]
if query == "system_commands":
    values=[]
    for b in bindings.values():
        if b.get("required") and b.get("installation_scope") == "system":
            values.extend(b.get("verification", {}).get("executable_names", []))
    for v in sorted(set(values)): print(v)
elif query == "venv_packages":
    values=[]
    for role,b in bindings.items():
        if b.get("required") and b.get("installation_scope") == "user" and b.get("installer_adapter_id") == "python_venv_package":
            values.append(b["package_identifier"])
        if role == "code_quality_tool" and b.get("required"): values.append("ruff")
    for v in sorted(set(values)): print(v)
elif query == "extensions":
    for b in bindings.values():
        if b.get("required") and b.get("installation_scope") == "user" and b.get("installer_adapter_id") == "vscode_extension":
            print(b["package_identifier"])
elif query == "git_settings":
    for pid in bindings["version_control_system"].get("settings_profile_ids", []):
        for k,v in manifest["managed_settings"][pid]["values"].items():
            if isinstance(v,bool): v="true" if v else "false"
            print(f"{k}\t{v}")
elif query == "vscode_settings":
    merged={}
    for pid in bindings["source_code_ide"].get("settings_profile_ids", []):
        merged.update(manifest["managed_settings"][pid]["values"])
    print(json.dumps(merged, separators=(",",":"), sort_keys=True))
elif query == "privacy_template":
    print(manifest["provider_profiles"]["github_com"]["privacy_identity"]["template"])
elif query == "retry_profile":
    pid=manifest["policy"]["default_retry_profile_id"]
    p=manifest["policy"]["retry_profiles"][pid]
    print("\t".join(str(p[k]) for k in ("maximum_attempts","initial_delay_seconds","backoff_multiplier","maximum_delay_seconds")))
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}
retry_operation() {
    local capture_var=""
    if [[ "${1:-}" == "--capture-var" ]]; then
        capture_var="$2"
        shift 2
    fi
    local description="$1"; shift
    local retry_data attempts delay multiplier maximum_delay attempt command_output=""
    retry_data="$(manifest_query retry_profile 2>/dev/null || printf '5\t5\t2\t60')"
    IFS=$'\t' read -r attempts delay multiplier maximum_delay <<< "$retry_data"
    for ((attempt=1; attempt<=attempts; attempt++)); do
        if [[ -n "$capture_var" ]]; then
            if command_output="$("$@")"; then
                printf -v "$capture_var" '%s' "$command_output"
                return 0
            fi
        elif "$@"; then
            return 0
        fi
        if ((attempt == attempts)); then print_error "$description failed after $attempts attempts."; return 1; fi
        print_warning "$description failed on attempt $attempt of $attempts; retrying in $delay seconds." >&2
        sleep "$delay"; delay=$((delay * multiplier)); ((delay > maximum_delay)) && delay="$maximum_delay"
    done
}
check_platform_and_user() {
    CURRENT_STAGE="execution-context validation"
    ((EUID != 0)) || fatal "$EXIT_UNSUPPORTED" "Do not run configure_it140.sh with sudo; personal settings must belong to the standard CVD account."
    [[ -r /etc/os-release ]] || fatal "$EXIT_UNSUPPORTED" "Cannot identify the operating system."
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || fatal "$EXIT_UNSUPPORTED" "This script supports only the IT 140 Ubuntu 24.04 CVD; detected ${PRETTY_NAME:-unknown}."
    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    [[ "$architecture" == amd64 || "$architecture" == x86_64 ]] || fatal "$EXIT_UNSUPPORTED" "This CVD implementation supports only x86_64; detected $architecture."
    [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] || fatal "$EXIT_UNSUPPORTED" "Unsupported deployment profile: $REQUESTED_PROFILE"
    command -v xfconf-query >/dev/null 2>&1 || fatal "$EXIT_UNSUPPORTED" "The required Xfce desktop tools are unavailable."
    command -v gio >/dev/null 2>&1 || fatal "$EXIT_UNSUPPORTED" "GIO desktop metadata tools are unavailable."
    print_info "Platform        : $PLATFORM_ID / $DEPLOYMENT_PROFILE_ID"
    print_info "Operating system: ${PRETTY_NAME:-Ubuntu 24.04}"
    print_info "Architecture    : $architecture"
}
check_restart_precondition() {
    CURRENT_STAGE="restart precondition validation"
    [[ ! -e /var/run/reboot-required ]] || fatal "$EXIT_FAILURE" "Ubuntu requires a CVD restart. Restart the CVD before running Configure."
}
check_system_layer() {
    CURRENT_STAGE="system-layer validation"
    local command_name failed=false
    while IFS= read -r command_name; do
        [[ -n "$command_name" ]] || continue
        command -v "$command_name" >/dev/null 2>&1 || { print_error "Required system command is missing: $command_name"; failed=true; }
    done < <(manifest_query system_commands)
    command -v python3.12 >/dev/null 2>&1 || { print_error "Required system command is missing: python3.12"; failed=true; }
    [[ "$failed" == false ]] || fatal "$EXIT_FAILURE" "The CVD system layer is incomplete. Rerun update_it140.sh before Configure."
}
acquire_lock() {
    CURRENT_STAGE="mutation-lock acquisition"
    command -v flock >/dev/null 2>&1 || { print_warning "flock is unavailable; concurrent lifecycle-script protection cannot be enforced."; return 0; }
    mkdir -p -- "$(dirname "$LOCK_FILE")"; chmod 0700 -- "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock --nonblock 9 || fatal "$EXIT_FAILURE" "Another IT 140 mutating lifecycle script is running."
}
upsert_managed_path_block() {
    local file="$1"
    python3 - "$file" <<'PY'
from pathlib import Path
import sys
path=Path(sys.argv[1]); start="# >>> IT 140 managed PATH >>>"; end="# <<< IT 140 managed PATH <<<"
block=start+'\n'+'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/cvd:$PATH"'+'\n'+end+'\n'
text=path.read_text(encoding="utf-8") if path.exists() else ""
if start in text and end in text:
    before=text.split(start,1)[0].rstrip("\n"); after=text.split(end,1)[1].lstrip("\n")
    text=((before+"\n\n") if before else "")+block+(("\n"+after) if after else "")
else:
    if text and not text.endswith("\n"): text+="\n"
    if text: text+="\n"
    text+=block
path.parent.mkdir(parents=True,exist_ok=True)
tmp=path.with_name(path.name+".it140.tmp")
try:
    tmp.write_text(text,encoding="utf-8",newline="\n"); tmp.replace(path)
finally:
    tmp.unlink(missing_ok=True)
PY
}
configure_paths_and_folders() {
    CURRENT_STAGE="course folders and PATH configuration"
    mkdir -p "$COURSE_ROOT" "$LOG_DIR" "$HOME/.cache"
    chmod 0700 "$LOG_DIR"
    touch "$HOME/.bashrc" "$HOME/.profile"
    upsert_managed_path_block "$HOME/.bashrc"; upsert_managed_path_block "$HOME/.profile"
    export PATH="$VENV_DIR/bin:$PLATFORM_SCRIPT_DIR:$PATH"; hash -r
    CHANGED=true
}

desktop_directory() { xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop\n' "$HOME"; }
ensure_repository_workspace() {
    CURRENT_STAGE="repository workspace configuration"
    if [[ -e "$REPOS_ROOT" && ! -d "$REPOS_ROOT" ]]; then
        fatal "$EXIT_FAILURE" "The required repository workspace path exists but is not a directory: $REPOS_ROOT"
    fi
    if [[ ! -d "$REPOS_ROOT" ]]; then mkdir -- "$REPOS_ROOT"; CHANGED=true; fi
    [[ -w "$REPOS_ROOT" ]] || fatal "$EXIT_FAILURE" "The repository workspace is not writable by the current user: $REPOS_ROOT"
    # Parent metadata only. Never recurse through student repositories. Preserve
    # any other emblems the user may already have applied to the workspace.
    local emblem_info emblem_values emblem_present=false i
    local -a emblems=()
    emblem_info="$(gio info -a metadata::emblems "$REPOS_ROOT" 2>/dev/null || true)"
    emblem_values="$(sed -n 's/^[[:space:]]*metadata::emblems:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p' <<< "$emblem_info")"
    if [[ -n "$emblem_values" ]]; then
        IFS=',' read -r -a emblems <<< "$emblem_values"
        for i in "${!emblems[@]}"; do
            emblems[$i]="${emblems[$i]#"${emblems[$i]%%[![:space:]]*}"}"
            emblems[$i]="${emblems[$i]%"${emblems[$i]##*[![:space:]]}"}"
            [[ "${emblems[$i]}" == development ]] && emblem_present=true
        done
    fi
    if [[ "$emblem_present" == false ]]; then
        emblems+=(development)
        gio set "$REPOS_ROOT" metadata::emblems --type=stringv "${emblems[@]}" >/dev/null 2>&1 \
            || fatal "$EXIT_FAILURE" "The Xfce development emblem could not be applied to $REPOS_ROOT."
        CHANGED=true
    fi
    gio info -a metadata::emblems "$REPOS_ROOT" 2>/dev/null | grep -Eq 'metadata::emblems:.*development' \
        || fatal "$EXIT_FAILURE" "The Xfce development emblem did not validate on $REPOS_ROOT."
    local desktop_dir shortcut
    desktop_dir="$(desktop_directory)"; mkdir -p -- "$desktop_dir"; shortcut="$desktop_dir/Repos"
    if [[ -L "$shortcut" ]]; then
        if [[ "$(readlink -f -- "$shortcut")" != "$(readlink -f -- "$REPOS_ROOT")" ]]; then
            fatal "$EXIT_FAILURE" "An existing Repos desktop link targets another location and was preserved: $shortcut"
        fi
    elif [[ -e "$shortcut" ]]; then
        fatal "$EXIT_FAILURE" "An unmanaged desktop item already uses the name Repos and was preserved: $shortcut"
    else
        ln -s -- "$REPOS_ROOT" "$shortcut"; CHANGED=true
    fi
    print_success "The development repository workspace is available at $REPOS_ROOT."
}
numlock_is_on() {
    local status
    command -v numlockx >/dev/null 2>&1 || return 1
    status="$(numlockx status 2>&1)" || return 1
    grep -Eiq '(^|[[:space:]])on([[:space:]]|$)' <<< "$status"
}
configure_numlock_session() {
    CURRENT_STAGE="Num Lock session configuration"
    command -v numlockx >/dev/null 2>&1 \
        || fatal "$EXIT_FAILURE" "Num Lock support is unavailable. Run update_it140.sh to install or repair numlockx before Configure."
    if numlock_is_on; then
        print_info "Num Lock is already enabled in the current Xfce session."
        return 0
    fi
    numlockx on >/dev/null 2>&1 \
        || fatal "$EXIT_FAILURE" "Num Lock could not be enabled in the current Xfce session."
    CHANGED=true
    numlock_is_on \
        || fatal "$EXIT_FAILURE" "Num Lock did not remain enabled after configuration."
    print_success "Num Lock is enabled in the current Xfce session."
}
remove_unwanted_baseline_desktop_launchers() {
    CURRENT_STAGE="CVD baseline desktop-launcher cleanup"
    local desktop_dir name path
    desktop_dir="$(desktop_directory)"
    for name in "${CVD_BASELINE_DESKTOP_LAUNCHERS[@]}"; do
        path="$desktop_dir/$name"
        if [[ -f "$path" && ! -L "$path" ]]; then
            rm -- "$path" \
                || fatal "$EXIT_FAILURE" "The unwanted CVD baseline desktop launcher could not be removed: $path"
            CHANGED=true
            print_success "Removed unwanted CVD baseline desktop launcher: $name"
        elif [[ -e "$path" || -L "$path" ]]; then
            fatal "$EXIT_FAILURE" "An unexpected desktop object uses the reserved CVD baseline name and was preserved: $path"
        fi
    done
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
find_vscode_launcher() {
    local desktop_dir candidate
    desktop_dir="$(desktop_directory)"; [[ -d "$desktop_dir" ]] || return 1
    for candidate in "$desktop_dir/visual-studio-code.desktop" "$desktop_dir/code.desktop" "$desktop_dir/Visual Studio Code.desktop"; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    while IFS= read -r -d '' candidate; do
        if grep -Eiq '^Name=.*Visual Studio Code|^Exec=([^[:space:]]*/)?code([[:space:]]|$)' "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
    done < <(find "$desktop_dir" -maxdepth 1 -type f -name '*.desktop' -print0)
    return 1
}
repair_vscode_launcher() {
    CURRENT_STAGE="Visual Studio Code desktop-launcher repair"
    local launcher code_path
    launcher="$(find_vscode_launcher 2>/dev/null || true)"
    [[ -n "$launcher" ]] || fatal "$EXIT_FAILURE" "The existing Visual Studio Code desktop launcher could not be found; no duplicate launcher was created."
    code_path="$(command -v code)"
    python3 - "$launcher" "$code_path" "$REPOS_ROOT" <<'PY'
from pathlib import Path
import shlex,sys
path=Path(sys.argv[1]); code_path=sys.argv[2]; workspace=sys.argv[3]
lines=path.read_text(encoding="utf-8").splitlines()
new_exec=f"Exec={shlex.quote(code_path)} --reuse-window {shlex.quote(workspace)}"
new_path=f"Path={workspace}"
output=[]; in_desktop=False; seen=False; replaced_exec=False; replaced_path=False
for line in lines:
    stripped=line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_desktop and not replaced_exec: output.append(new_exec); replaced_exec=True
        if in_desktop and not replaced_path: output.append(new_path); replaced_path=True
        in_desktop=(stripped=="[Desktop Entry]"); seen=seen or in_desktop; output.append(line); continue
    if in_desktop and stripped.startswith("Exec=") and not replaced_exec:
        output.append(new_exec); replaced_exec=True
    elif in_desktop and stripped.startswith("Path=") and not replaced_path:
        output.append(new_path); replaced_path=True
    else: output.append(line)
if in_desktop and not replaced_exec: output.append(new_exec); replaced_exec=True
if in_desktop and not replaced_path: output.append(new_path); replaced_path=True
if not seen or not replaced_exec: raise SystemExit("launcher lacks a valid [Desktop Entry] section")
tmp=path.with_name(path.name+".it140.tmp")
try:
    tmp.write_text("\n".join(output)+"\n",encoding="utf-8",newline="\n"); tmp.replace(path)
finally: tmp.unlink(missing_ok=True)
PY
    if command -v desktop-file-validate >/dev/null 2>&1; then
        desktop-file-validate "$launcher" \
            || fatal "$EXIT_FAILURE" "The repaired Visual Studio Code launcher failed desktop-entry validation."
    fi
    # Xfce/Thunar trusts launchers by storing the SHA-256 checksum of the
    # completed .desktop file in metadata::xfce-exe-checksum. Set trust only
    # after all content changes so the stored checksum cannot immediately stale.
    chmod 0755 -- "$launcher" \
        || fatal "$EXIT_FAILURE" "The Visual Studio Code launcher could not be marked executable."
    local launcher_checksum
    launcher_checksum="$(sha256sum -- "$launcher" | awk '{print $1}')"
    [[ -n "$launcher_checksum" ]] \
        || fatal "$EXIT_FAILURE" "The Visual Studio Code launcher checksum could not be calculated."
    gio set "$launcher" metadata::xfce-exe-checksum "$launcher_checksum" >/dev/null 2>&1 \
        || fatal "$EXIT_FAILURE" "The Visual Studio Code launcher could not be marked trusted by Xfce."
    launcher_is_xfce_trusted "$launcher" \
        || fatal "$EXIT_FAILURE" "The Visual Studio Code launcher trust metadata did not validate."
    VSCODE_LAUNCHER="$launcher"; CHANGED=true
    print_success "The existing Visual Studio Code desktop launcher now opens $REPOS_ROOT and is trusted by Xfce."
}
remove_obsolete_course_folder_shortcut() {
    CURRENT_STAGE="obsolete course-folder shortcut cleanup"
    local shortcut desktop_dir target
    desktop_dir="$(desktop_directory)"; shortcut="$desktop_dir/IT 140 Course Folder"
    if [[ -L "$shortcut" ]]; then
        target="$(readlink -f -- "$shortcut" 2>/dev/null || true)"
        if [[ "$target" == "$(readlink -f -- "$COURSE_ROOT")" ]]; then rm -- "$shortcut"; CHANGED=true; print_success "Removed the obsolete course-folder desktop link."; fi
    fi
}
resolve_provider_identity() {
    CURRENT_STAGE="GitHub authentication and identity resolution"
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        [[ "$NONINTERACTIVE" == false ]] || fatal "$EXIT_FAILURE" "GitHub CLI is not authenticated; interactive authentication is required."
        print_header "GITHUB AUTHENTICATION"
        print_notice "GitHub CLI will display a one-time code and open a browser."
        printf 'Press Enter to begin, or type C to cancel: '
        local response; IFS= read -r response
        [[ "${response,,}" != c ]] || fatal "$EXIT_CANCELED" "GitHub authentication was canceled before configuration changes began."
        gh auth login --hostname github.com --git-protocol https --web --clipboard || fatal "$EXIT_EXTERNAL" "GitHub authentication did not complete."
        CHANGED=true
    fi
    local identity_json="" template
    retry_operation --capture-var identity_json "GitHub account lookup" gh api user --jq '{id: .id, login: .login, name: .name}' \
        || fatal "$EXIT_EXTERNAL" "The authenticated GitHub account could not be read."
    IFS=$'\t' read -r GITHUB_ACCOUNT_ID GITHUB_LOGIN GIT_DISPLAY_NAME < <(python3 - "$identity_json" <<'PY'
import json,sys
v=json.loads(sys.argv[1]); aid=str(v.get("id") or ""); login=str(v.get("login") or "").strip(); display=str(v.get("name") or "").strip() or login
if not aid or not login: raise SystemExit(1)
print(f"{aid}\t{login}\t{display}")
PY
    ) || fatal "$EXIT_EXTERNAL" "GitHub returned incomplete account identity fields."
    if [[ "$NONINTERACTIVE" == false ]]; then
        print_notice "Review the Git commit display name shown below."
        print_notice "Press Enter to keep the name in brackets, or type a different name and press Enter."
        local requested_name
        printf 'Git commit display name [%s]: ' "$GIT_DISPLAY_NAME"
        IFS= read -r requested_name
        [[ -z "$requested_name" ]] || GIT_DISPLAY_NAME="$requested_name"
    fi
    [[ -n "${GIT_DISPLAY_NAME//[[:space:]]/}" ]] || fatal "$EXIT_FAILURE" "The Git commit display name cannot be empty."
    template="$(manifest_query privacy_template)" || fatal "$EXIT_MANIFEST" "The GitHub private-email template is unavailable."
    GIT_PRIVATE_EMAIL="${template//\$\{ACCOUNT_ID\}/$GITHUB_ACCOUNT_ID}"; GIT_PRIVATE_EMAIL="${GIT_PRIVATE_EMAIL//\$\{USERNAME\}/$GITHUB_LOGIN}"
    [[ "$GIT_PRIVATE_EMAIL" == *@users.noreply.github.com ]] || fatal "$EXIT_MANIFEST" "The provider private-email template produced an invalid result."
}
configure_python_tools() {
    CURRENT_STAGE="course Python environment configuration"
    local -a packages=(); mapfile -t packages < <(manifest_query venv_packages)
    if [[ ! -x "$VENV_DIR/bin/python" ]]; then python3.12 -m venv "$VENV_DIR" || fatal "$EXIT_FAILURE" "The course Python virtual environment could not be created."; CHANGED=true; fi
    retry_operation "Python packaging-tool configuration" "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade pip setuptools wheel \
        || fatal "$EXIT_EXTERNAL" "Python packaging tools could not be configured."
    ((${#packages[@]} == 0)) || retry_operation "Course Python tool configuration" "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade "${packages[@]}" \
        || fatal "$EXIT_EXTERNAL" "Required course Python tools could not be configured."
    CHANGED=true
}
configure_vscode_extensions() {
    CURRENT_STAGE="Visual Studio Code extension configuration"
    local extension
    while IFS= read -r extension; do
        [[ -n "$extension" ]] || continue
        retry_operation "VS Code extension configuration: $extension" code --install-extension "$extension" --force \
            || fatal "$EXIT_EXTERNAL" "Required VS Code extension could not be configured: $extension"
        CHANGED=true
    done < <(manifest_query extensions)
}
configure_git_settings() {
    CURRENT_STAGE="Git configuration"
    local key value
    git config --global user.name "$GIT_DISPLAY_NAME"; git config --global user.email "$GIT_PRIVATE_EMAIL"
    while IFS=$'\t' read -r key value; do [[ -n "$key" ]] || continue; git config --global "$key" "$value"; done < <(manifest_query git_settings)
    CHANGED=true
}
configure_vscode_settings() {
    CURRENT_STAGE="Visual Studio Code settings configuration"
    local settings_dir="$HOME/.config/Code/User" settings_file settings_json
    settings_file="$settings_dir/settings.json"; settings_json="$(manifest_query vscode_settings)" || fatal "$EXIT_MANIFEST" "VS Code managed settings could not be read from the manifest."
    mkdir -p "$settings_dir"
    IT140_SETTINGS_FILE="$settings_file" IT140_SETTINGS_JSON="$settings_json" IT140_VENV_PYTHON="$VENV_DIR/bin/python" python3 - <<'PY'
import json,os
from pathlib import Path
path=Path(os.environ["IT140_SETTINGS_FILE"]); managed=json.loads(os.environ["IT140_SETTINGS_JSON"])
managed["python.defaultInterpreterPath"]=os.environ["IT140_VENV_PYTHON"]
if path.exists():
    try: current=json.loads(path.read_text(encoding="utf-8"))
    except (OSError,UnicodeError,json.JSONDecodeError) as exc: raise SystemExit(f"existing VS Code settings are invalid and were preserved: {exc}")
    if not isinstance(current,dict): raise SystemExit("existing VS Code settings are not a JSON object and were preserved")
else: current={}
def merge(t,s):
    for k,v in s.items():
        if isinstance(v,dict) and isinstance(t.get(k),dict): merge(t[k],v)
        else: t[k]=v
merge(current,managed); path.parent.mkdir(parents=True,exist_ok=True); tmp=path.with_name(path.name+".it140.tmp")
try:
    tmp.write_text(json.dumps(current,indent=4,ensure_ascii=False)+"\n",encoding="utf-8",newline="\n"); json.loads(tmp.read_text(encoding="utf-8")); tmp.replace(path)
finally: tmp.unlink(missing_ok=True)
PY
    CHANGED=true
}
configure_file_associations() {
    CURRENT_STAGE="file-association configuration"
    command -v xdg-mime >/dev/null 2>&1 && xdg-mime default code.desktop text/x-python >/dev/null 2>&1 \
        || print_warning "The optional Python file association could not be updated."
}
launcher_opens_repos_root() {
    local launcher="$1"
    python3 - "$launcher" "$REPOS_ROOT" <<'PY'
import pathlib,shlex,sys
path=pathlib.Path(sys.argv[1]); workspace=sys.argv[2]; lines=path.read_text(encoding="utf-8").splitlines(); in_desktop=False; exec_value=None; path_value=None
for line in lines:
    stripped=line.strip()
    if stripped.startswith("[") and stripped.endswith("]"): in_desktop=(stripped=="[Desktop Entry]"); continue
    if in_desktop and stripped.startswith("Exec=") and exec_value is None: exec_value=stripped[5:]
    if in_desktop and stripped.startswith("Path=") and path_value is None: path_value=stripped[5:]
if not exec_value: raise SystemExit(1)
args=[a for a in shlex.split(exec_value) if not (a.startswith("%") and len(a)==2)]
if not args or pathlib.Path(args[0]).name != "code" or workspace not in args: raise SystemExit(1)
if path_value != workspace: raise SystemExit(1)
PY
}
validate_configuration() {
    CURRENT_STAGE="configuration validation"
    local key expected actual package extension installed_extensions desktop_dir shortcut marker name path
    gh auth status --hostname github.com >/dev/null 2>&1 || fatal "$EXIT_FAILURE" "GitHub CLI is not authenticated after configuration."
    [[ "$(git config --global --get user.name 2>/dev/null || true)" == "$GIT_DISPLAY_NAME" ]] || fatal "$EXIT_FAILURE" "Git display-name validation failed."
    [[ "$(git config --global --get user.email 2>/dev/null || true)" == "$GIT_PRIVATE_EMAIL" ]] || fatal "$EXIT_FAILURE" "Git private-email validation failed."
    while IFS=$'\t' read -r key expected; do [[ -n "$key" ]] || continue; actual="$(git config --global --get "$key" 2>/dev/null || true)"; [[ "$actual" == "$expected" ]] || fatal "$EXIT_FAILURE" "Git managed setting validation failed: $key"; done < <(manifest_query git_settings)
    grep -Fqx "$MANAGED_PATH_EXPORT" "$HOME/.bashrc" || fatal "$EXIT_FAILURE" "The managed PATH block is missing from ~/.bashrc."
    grep -Fqx "$MANAGED_PATH_EXPORT" "$HOME/.profile" || fatal "$EXIT_FAILURE" "The managed PATH block is missing from ~/.profile."
    [[ -x "$VENV_DIR/bin/python" ]] || fatal "$EXIT_FAILURE" "The course Python environment is unavailable after configuration."
    while IFS= read -r package; do [[ -n "$package" ]] || continue; "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1 || fatal "$EXIT_FAILURE" "Required Python package is missing after configuration: $package"; done < <(manifest_query venv_packages)
    installed_extensions="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r extension; do [[ -n "$extension" ]] || continue; grep -Fqx "${extension,,}" <<< "$installed_extensions" || fatal "$EXIT_FAILURE" "Required VS Code extension is missing after configuration: $extension"; done < <(manifest_query extensions)
    [[ -d "$REPOS_ROOT" && -w "$REPOS_ROOT" ]] || fatal "$EXIT_FAILURE" "The repository workspace is unavailable after configuration."
    desktop_dir="$(desktop_directory)"; shortcut="$desktop_dir/Repos"
    [[ -L "$shortcut" && "$(readlink -f -- "$shortcut")" == "$(readlink -f -- "$REPOS_ROOT")" ]] || fatal "$EXIT_FAILURE" "The desktop Repos link does not target $REPOS_ROOT."
    marker="$(gio info -a metadata::emblems "$REPOS_ROOT" 2>/dev/null || true)"; grep -Eq 'metadata::emblems:.*development' <<< "$marker" || fatal "$EXIT_FAILURE" "The Repos development emblem is missing."
    [[ -n "$VSCODE_LAUNCHER" && -f "$VSCODE_LAUNCHER" ]] || fatal "$EXIT_FAILURE" "The repaired Visual Studio Code desktop launcher is unavailable."
    launcher_opens_repos_root "$VSCODE_LAUNCHER" || fatal "$EXIT_FAILURE" "The Visual Studio Code desktop launcher does not open $REPOS_ROOT."
    launcher_is_xfce_trusted "$VSCODE_LAUNCHER" || fatal "$EXIT_FAILURE" "The Visual Studio Code desktop launcher is not executable and trusted by Xfce."
    for name in "${CVD_BASELINE_DESKTOP_LAUNCHERS[@]}"; do
        path="$desktop_dir/$name"
        [[ ! -e "$path" && ! -L "$path" ]] || fatal "$EXIT_FAILURE" "An unwanted CVD baseline desktop launcher remains: $path"
    done
    numlock_is_on || fatal "$EXIT_FAILURE" "Num Lock is not enabled in the current Xfce session."
    print_success "Required user configuration passed post-configuration validation."
}
main() {
    parse_options "$@"
    mkdir -p "$LOG_DIR"; chmod 0700 "$LOG_DIR"; touch "$LOG_FILE"; chmod 0600 "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap on_error ERR; trap on_interrupt INT TERM
    print_header "IT 140 CODIO VIRTUAL DESKTOP CONFIGURE"
    print_info "Script version : $SCRIPT_VERSION"
    print_info "Version DTG    : $VERSION_DTG"
    print_info "Status         : $DEVELOPMENT_STATUS"
    print_info "Current user   : $(id -un)"
    print_info "Purpose        : Configure the current user's course IDE and repository workspace."
    print_info "Course root    : $COURSE_ROOT"
    print_info "Repository root: $REPOS_ROOT"
    print_info "Log file       : $LOG_FILE"
    print_notice "Keep this Terminal open until the final summary appears."
    check_platform_and_user
    CURRENT_STAGE="controlled manifest validation"
    local manifest_info
    manifest_info="$(validate_manifest)" || fatal "$EXIT_MANIFEST" "The controlled manifest or schema is invalid."
    IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$manifest_info"
    check_restart_precondition; check_system_layer; acquire_lock
    configure_paths_and_folders
    configure_numlock_session
    ensure_repository_workspace
    resolve_provider_identity
    configure_python_tools
    gh api --method PUT /user/starred/GC-STEM/it140-m1-setup-tasks >/dev/null 2>&1 || true
    configure_vscode_extensions
    configure_git_settings
    configure_vscode_settings
    remove_unwanted_baseline_desktop_launchers
    repair_vscode_launcher
    remove_obsolete_course_folder_shortcut
    configure_file_associations
    validate_configuration
    finish "$EXIT_SUCCESS" "Required user configuration and repository-workspace operations completed."
}
main "$@"
