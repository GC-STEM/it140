#!/usr/bin/env bash
# ==============================================================================
# IT 140 COURSE IDE — UPDATE (UBUNTU GNOME)
# ==============================================================================
# Repository path: scripts/nix/ubg/update_ubg.sh
# Purpose: Maintain manifest-declared IT 140 course IDE components without
#          upgrading the Ubuntu operating-system release.
# Artifact ID: IT140-UBG-UPDATE
# Artifact version: 0.3.0
# Supported profile: ubuntu_gnome_bare_metal (Ubuntu 24.04 LTS, x86_64)
# ==============================================================================
set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.3.0"
readonly PLATFORM_ID="ubuntu_gnome"
readonly DEPLOYMENT_PROFILE_ID="ubuntu_gnome_bare_metal"
readonly SUPPORTED_SCHEMA="2.2"
readonly COURSE_ROOT="$HOME/it140"
readonly SCRIPT_ROOT="$COURSE_ROOT/scripts"
readonly MANIFEST_DIR="$SCRIPT_ROOT/.manifest"
readonly MANIFEST_PATH="$MANIFEST_DIR/it140_manifest.json"
readonly SCHEMA_PATH="$MANIFEST_DIR/it140_manifest.schema.json"
readonly LOG_DIR="$COURSE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/update_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_FILE="$HOME/.cache/it140-ubg-mutation.lock"
readonly VENV_DIR="$COURSE_ROOT/.venv"
readonly EXIT_FAILURE=1 EXIT_UNSUPPORTED=2 EXIT_PRIVILEGE=3 EXIT_EXTERNAL=4 EXIT_MANIFEST=5 EXIT_CANCELED=6 EXIT_PARTIAL=7

# Behavioral-test seams are inert unless IT140_UPDATE_TEST_MODE=true.
readonly UPDATE_TEST_MODE="${IT140_UPDATE_TEST_MODE:-false}"
if [[ "$UPDATE_TEST_MODE" == true ]]; then
    readonly UPDATE_TEST_ROOT="${IT140_UPDATE_TEST_ROOT:-}"
else
    readonly UPDATE_TEST_ROOT=""
fi
readonly OS_RELEASE_PATH="${UPDATE_TEST_ROOT}/etc/os-release"
readonly REBOOT_REQUIRED_PATH="${UPDATE_TEST_ROOT}/var/run/reboot-required"

REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
PARTIAL=false
RESTART_REQUIRED=false
WARNINGS=0
FAILURES=0
FINALIZED=false
CURRENT_STAGE="initialization"
MANIFEST_RELEASE="unavailable"
MANIFEST_DTG="unavailable"
START_EPOCH="$(date +%s)"
STAGING_ROOT=""

header(){ printf '\n============================================================\n%s\n============================================================\n' "$1"; }
info(){ printf '[INFO] %s\n' "$1"; }
success(){ printf '[SUCCESS] %s\n' "$1"; }
notice(){ printf '[NOTICE] %s\n' "$1"; }
warning(){ WARNINGS=$((WARNINGS+1)); printf '[WARNING] %s\n' "$1"; }
error(){ printf '[ERROR] %s\n' "$1" >&2; }
continuity(){ notice 'Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.'; }
usage(){ cat <<'USAGE'
Usage: update_ubg.sh [--help] [--version]
                     [--deployment-profile ubuntu_gnome_bare_metal]
Stages and validates the current controlled manifest assets, updates only
manifest-declared Ubuntu course components, the course Python environment, and
required VS Code extensions, then directs the user to Verify. It does not run
an Ubuntu release upgrade or modify student repositories.
Logs: ~/it140/logs/
USAGE
}
parse(){
    while (($#)); do
        case "$1" in
            --help|-h) usage; exit 0;;
            --version) printf '%s\n' "$SCRIPT_VERSION"; exit 0;;
            --deployment-profile|--profile) shift; (($#)) || { error 'Missing deployment profile.'; exit "$EXIT_UNSUPPORTED"; }; REQUESTED_PROFILE="$1";;
            *) error "Unsupported option: $1"; usage >&2; exit "$EXIT_UNSUPPORTED";;
        esac
        shift
    done
}
cleanup(){ [[ -z "$STAGING_ROOT" || ! -d "$STAGING_ROOT" ]] || rm -rf -- "$STAGING_ROOT"; STAGING_ROOT=""; }
resolve_failure_code(){
    local requested="$1"
    case "$requested" in
        "$EXIT_MANIFEST"|"$EXIT_UNSUPPORTED"|"$EXIT_PRIVILEGE"|"$EXIT_EXTERNAL"|"$EXIT_PARTIAL") printf '%s\n' "$requested";;
        "$EXIT_CANCELED") [[ "$CHANGED" == true ]] && printf '%s\n' "$EXIT_PARTIAL" || printf '%s\n' "$EXIT_CANCELED";;
        *) [[ "$CHANGED" == true ]] && printf '%s\n' "$EXIT_PARTIAL" || printf '%s\n' "$EXIT_FAILURE";;
    esac
}
summary_guidance(){
    local code="$1"
    if [[ "$RESTART_REQUIRED" == true ]]; then
        printf 'Save your work, restart Ubuntu, then run verify_ubg.sh.'
    elif ((code != 0)); then
        printf 'Resolve the reported issue, then rerun update_ubg.sh.'
    else
        printf 'Open a new Terminal and run verify_ubg.sh.'
    fi
}
finish(){
    local requested_code="${1:-0}" detail="${2:-}" code result next
    [[ "$FINALIZED" == false ]] || return "$requested_code"
    FINALIZED=true
    cleanup
    if [[ "$PARTIAL" == true && "$requested_code" -eq 0 ]]; then requested_code="$EXIT_PARTIAL"; fi
    code=0
    ((requested_code==0)) || code="$(resolve_failure_code "$requested_code")"
    if ((code==0)); then result=PASS; elif ((code==EXIT_PARTIAL)); then result=PARTIAL; else result=FAIL; fi
    next="$(summary_guidance "$code")"
    header 'UPDATE SUMMARY'
    [[ -n "$detail" ]] && printf 'Conclusion      : %s\n' "$detail"
    printf 'Result          : %s\n' "$result"
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'Manifest DTG    : %s\n' "$MANIFEST_DTG"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Failures        : %s\n' "$FAILURES"
    printf 'Restart required: %s\n' "$( [[ "$RESTART_REQUIRED" == true ]] && printf Yes || printf No )"
    printf 'Managed changes : %s\n' "$( [[ "$CHANGED" == true ]] && printf Yes || printf No )"
    printf 'Elapsed time    : %s seconds\n' "$(( $(date +%s)-START_EPOCH ))"
    printf 'Next step       : %s\n' "$next"
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : %s\n' "$code"
    if ((code==0)); then success 'The IT 140 Ubuntu GNOME update completed successfully.'; else continuity; fi
    notice 'Review the summary and log before closing Terminal.'
    return "$code"
}
fatal(){ local requested="$1" exit_code=0; shift; FAILURES=$((FAILURES+1)); error "$*"; error "Failed stage: $CURRENT_STAGE"; finish "$requested" "$*" || exit_code=$?; exit "$exit_code"; }
on_error(){ local status=$? line=${BASH_LINENO[0]:-unknown} exit_code=0; trap - ERR; FAILURES=$((FAILURES+1)); error "Update stopped near line ${line} during ${CURRENT_STAGE} (status ${status})."; finish "$EXIT_FAILURE" 'An unexpected command failure stopped Update.' || exit_code=$?; exit "$exit_code"; }
on_interrupt(){ local exit_code=0; trap - INT TERM HUP; error "Update was interrupted during ${CURRENT_STAGE}."; finish "$EXIT_CANCELED" 'Update was interrupted; rerun it to recover.' || exit_code=$?; exit "$exit_code"; }

validate_manifest_pair(){
    local manifest="$1" schema="$2"
    python3 - "$manifest" "$schema" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
import json,pathlib,sys
mp,sp,pid,profile_id,supported=sys.argv[1:]
try:
    m=json.loads(pathlib.Path(mp).read_text(encoding='utf-8'))
    s=json.loads(pathlib.Path(sp).read_text(encoding='utf-8'))
except Exception as exc:
    raise SystemExit(f'controlled JSON validation failed: {exc}')
if m.get('schema_version')!=supported: raise SystemExit('unsupported manifest schema')
if s.get('$schema')!='https://json-schema.org/draft/2020-12/schema': raise SystemExit('unsupported JSON Schema draft')
if m.get('policy',{}).get('allow_os_release_upgrade') is not False: raise SystemExit('manifest attempts to allow an operating-system release upgrade')
p=m.get('platforms',{}).get(pid); d=m.get('deployment_profiles',{}).get(profile_id)
if not p or not p.get('enabled'): raise SystemExit('Ubuntu GNOME platform missing or disabled')
if not d or not d.get('enabled') or d.get('platform_id')!=pid or d.get('architecture')!='x86_64': raise SystemExit('Ubuntu GNOME deployment profile invalid')
if 'local_periodic_maintenance' not in d.get('allowed_workflow_ids',[]): raise SystemExit('periodic maintenance workflow is not allowed')
w=m.get('lifecycle_workflows',{}).get('local_periodic_maintenance',{})
if profile_id not in w.get('deployment_profile_ids',[]) or w.get('success_transitions',{}).get('update')!='verify': raise SystemExit('periodic maintenance workflow binding invalid')
print(f"{m['automation_release']}\t{m.get('automation_release_date_time_group','unavailable')}")
PY
}
manifest_query(){
    local query="$1"
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json,sys
m=json.load(open(sys.argv[1],encoding='utf-8')); p=m['platforms'][sys.argv[2]]; q=sys.argv[3]; b=p['course_ide_bindings']
if q=='system_packages':
    vals={x['package_identifier'] for x in p.get('os_packages',{}).values() if x.get('required') and x.get('package_identifier')}
    vals.update(x['package_identifier'] for x in b.values() if x.get('required') and x.get('installation_scope')=='system' and x.get('installer_adapter_id')=='apt_package')
    print('\n'.join(sorted(vals)))
elif q=='venv_packages':
    vals={x['package_identifier'] for x in b.values() if x.get('required') and x.get('installation_scope')=='user' and x.get('installer_adapter_id')=='python_venv_package'}
    if b.get('code_quality_tool',{}).get('required'): vals.add('ruff')
    print('\n'.join(sorted(vals)))
elif q=='extensions':
    print('\n'.join(sorted(x['package_identifier'] for x in b.values() if x.get('required') and x.get('installer_adapter_id')=='vscode_extension')))
PY
}
retry_operation(){
    local description="$1"; shift; local attempt=1 delay=1
    while ((attempt<=5)); do
        "$@" && return 0
        if ((attempt<5)); then warning "${description} failed on attempt ${attempt} of 5; retrying."; sleep "$delay"; delay=$((delay*2)); fi
        attempt=$((attempt+1))
    done
    return 1
}
check_context(){
    CURRENT_STAGE='Validate execution context'
    local effective_euid="$EUID"
    if [[ "$UPDATE_TEST_MODE" == true && -n "$UPDATE_TEST_ROOT" && -n "${IT140_UPDATE_TEST_EUID:-}" ]]; then effective_euid="${IT140_UPDATE_TEST_EUID}"; fi
    ((effective_euid!=0)) || fatal "$EXIT_UNSUPPORTED" 'Run Update as the regular desktop user, not with sudo.'
    [[ -r "$OS_RELEASE_PATH" ]] || fatal "$EXIT_UNSUPPORTED" 'Ubuntu could not be identified.'
    # shellcheck disable=SC1090
    source "$OS_RELEASE_PATH"
    [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || fatal "$EXIT_UNSUPPORTED" 'This implementation supports Ubuntu 24.04 LTS only.'
    [[ "$(uname -m)" == x86_64 ]] || fatal "$EXIT_UNSUPPORTED" 'This implementation supports x86_64 only.'
    [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] || fatal "$EXIT_UNSUPPORTED" "Unsupported deployment profile: $REQUESTED_PROFILE"
    command -v sudo >/dev/null 2>&1 || fatal "$EXIT_PRIVILEGE" 'sudo is required for system maintenance.'
    sudo -v || fatal "$EXIT_PRIVILEGE" 'Administrator authorization is required for system maintenance.'
}
refresh_controlled_assets(){
    CURRENT_STAGE='Stage and validate controlled maintenance assets'
    local candidate_root candidate_manifest candidate_schema validated
    STAGING_ROOT="$(mktemp -d)"
    candidate_root="$STAGING_ROOT/repository"
    retry_operation 'Repository checkout' git clone --depth 1 https://github.com/GC-STEM/it140.git "$candidate_root" || fatal "$EXIT_EXTERNAL" 'The current course maintenance assets were unavailable after bounded retries.'
    candidate_manifest="$candidate_root/scripts/.manifest/it140_manifest.json"
    candidate_schema="$candidate_root/scripts/.manifest/it140_manifest.schema.json"
    [[ -r "$candidate_manifest" && -r "$candidate_schema" ]] || fatal "$EXIT_MANIFEST" 'The downloaded controlled manifest or schema is missing.'
    validated="$(validate_manifest_pair "$candidate_manifest" "$candidate_schema" 2>&1)" || fatal "$EXIT_MANIFEST" 'The downloaded controlled manifest or schema failed validation.'
    mkdir -p "$MANIFEST_DIR"
    if ! cmp -s "$candidate_manifest" "$MANIFEST_PATH"; then install -m 0600 "$candidate_manifest" "$MANIFEST_PATH.new"; mv -f "$MANIFEST_PATH.new" "$MANIFEST_PATH"; CHANGED=true; success 'The controlled manifest was refreshed atomically.'; else info 'The controlled manifest is already current.'; fi
    if ! cmp -s "$candidate_schema" "$SCHEMA_PATH"; then install -m 0600 "$candidate_schema" "$SCHEMA_PATH.new"; mv -f "$SCHEMA_PATH.new" "$SCHEMA_PATH"; CHANGED=true; success 'The manifest schema was refreshed atomically.'; else info 'The manifest schema is already current.'; fi
    validated="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH" 2>&1)" || fatal "$EXIT_MANIFEST" 'The activated controlled manifest pair failed validation.'
    IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$validated"
}
apt_package_present(){ dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" 2>/dev/null | grep -q '^ii '; }
update_system_packages(){
    CURRENT_STAGE='Ubuntu package maintenance'
    local -a packages=(); mapfile -t packages < <(manifest_query system_packages)
    ((${#packages[@]})) || fatal "$EXIT_MANIFEST" 'The manifest declares no required Ubuntu GNOME system packages.'
    local package
    for package in "${packages[@]}"; do apt_package_present "$package" || fatal "$EXIT_FAILURE" "Required system package is missing: $package. Run setup_ubg.sh before Update."; done
    retry_operation 'Ubuntu package-index refresh' sudo apt-get -o Acquire::Retries=3 update || fatal "$EXIT_EXTERNAL" 'Ubuntu package information could not be refreshed.'
    sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 -y install --only-upgrade -- "${packages[@]}" || fatal "$EXIT_EXTERNAL" 'One or more required Ubuntu course components could not be updated.'
    CHANGED=true
    success 'Manifest-required Ubuntu system components are current.'
}
update_python_tools(){
    CURRENT_STAGE='Course Python tool maintenance'
    local -a packages=(); mapfile -t packages < <(manifest_query venv_packages)
    command -v python3.12 >/dev/null 2>&1 || fatal "$EXIT_FAILURE" 'Python 3.12 is unavailable. Run setup_ubg.sh before Update.'
    if [[ ! -x "$VENV_DIR/bin/python" ]]; then python3.12 -m venv "$VENV_DIR" || fatal "$EXIT_FAILURE" 'The course Python virtual environment could not be created.'; CHANGED=true; fi
    retry_operation 'Python packaging-tool update' "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade pip setuptools wheel || fatal "$EXIT_EXTERNAL" 'The Python packaging tools could not be updated.'
    CHANGED=true
    if ((${#packages[@]})); then retry_operation 'Course Python tool update' "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade "${packages[@]}" || fatal "$EXIT_EXTERNAL" 'One or more required course Python tools could not be updated.'; CHANGED=true; fi
    success 'Course Python tools are current.'
}
update_extensions(){
    CURRENT_STAGE='Visual Studio Code extension maintenance'
    command -v code >/dev/null 2>&1 || fatal "$EXIT_FAILURE" 'Visual Studio Code is unavailable. Run setup_ubg.sh before Update.'
    local extension; while IFS= read -r extension; do [[ -n "$extension" ]] || continue; retry_operation "VS Code extension update: $extension" code --install-extension "$extension" --force >/dev/null || fatal "$EXIT_EXTERNAL" "Required VS Code extension could not be updated: $extension"; CHANGED=true; done < <(manifest_query extensions)
    success 'Required Visual Studio Code extensions are current.'
}
post_validate(){
    CURRENT_STAGE='Post-update validation'
    local package; while IFS= read -r package; do [[ -n "$package" ]] || continue; apt_package_present "$package" || fatal "$EXIT_FAILURE" "Required system package is missing after Update: $package"; done < <(manifest_query system_packages)
    [[ -x "$VENV_DIR/bin/python" ]] || fatal "$EXIT_FAILURE" 'The course Python virtual environment is unavailable after Update.'
    local pkg; while IFS= read -r pkg; do [[ -n "$pkg" ]] || continue; "$VENV_DIR/bin/python" -m pip show "$pkg" >/dev/null 2>&1 || fatal "$EXIT_FAILURE" "Required course Python package is missing after Update: $pkg"; done < <(manifest_query venv_packages)
    local installed ext; installed="$(code --list-extensions 2>/dev/null || true)"
    while IFS= read -r ext; do [[ -n "$ext" ]] || continue; grep -Fxiq "$ext" <<< "$installed" || fatal "$EXIT_FAILURE" "Required VS Code extension is missing after Update: $ext"; done < <(manifest_query extensions)
    if [[ -e "$REBOOT_REQUIRED_PATH" ]]; then RESTART_REQUIRED=true; PARTIAL=true; notice 'Ubuntu reports that a restart is required before maintenance is fully complete.'; fi
    success 'Ubuntu GNOME Update passed post-validation.'
}
main(){
    parse "$@"
    mkdir -p "$LOG_DIR" "$(dirname "$LOCK_FILE")"; chmod 0700 "$LOG_DIR"; : > "$LOG_FILE"; chmod 0600 "$LOG_FILE"
    if [[ "$UPDATE_TEST_MODE" == true ]]; then exec >>"$LOG_FILE" 2>&1; else exec > >(tee -a "$LOG_FILE") 2>&1; fi
    trap on_error ERR; trap on_interrupt INT TERM HUP
    header 'IT 140 UBUNTU GNOME UPDATE'; info "Script version   : $SCRIPT_VERSION"; info "Current user     : $(id -un)"; info "Course root      : $COURSE_ROOT"; info "Log file         : $LOG_FILE"; notice 'Update does not install an Ubuntu release upgrade or modify student repositories.'
    check_context
    exec 9>"$LOCK_FILE"; flock -n 9 || fatal "$EXIT_PARTIAL" 'Another IT 140 Ubuntu mutation script is running.'
    CURRENT_STAGE='Validate local controlled manifest'; [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || fatal "$EXIT_MANIFEST" 'The local controlled manifest or schema is missing.'
    local validated; validated="$(validate_manifest_pair "$MANIFEST_PATH" "$SCHEMA_PATH" 2>&1)" || fatal "$EXIT_MANIFEST" 'The local controlled manifest and schema failed validation.'; IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$validated"; info "Manifest release: $MANIFEST_RELEASE"; info "Manifest DTG    : $MANIFEST_DTG"
    header 'Stage 1: Controlled Maintenance Assets'; refresh_controlled_assets
    header 'Stage 2: Manifest-Declared Ubuntu Components'; update_system_packages
    header 'Stage 3: User-Scoped Course Tools'; update_python_tools; update_extensions
    header 'Stage 4: Post-Update Validation'; post_validate
    local exit_code=0; finish 0 'Required Ubuntu GNOME course components were updated or confirmed current.' || exit_code=$?; exit "$exit_code"
}
main "$@"
