#!/usr/bin/env bash
# ==============================================================================
# IT 140 COURSE IDE — SYSTEM SETUP (UBUNTU GNOME)
# ==============================================================================
# Repository path: scripts/nix/ubg/setup_ubg.sh
# Purpose: Install missing system-level software for the approved local Ubuntu
#          GNOME profile while preserving compatible preexisting applications.
# Artifact ID: IT140-UBG-INSTALL
# Artifact version: 0.8.0-alpha.1
# Version date-time group: 2026-08-07-10-44
# Development status: Alpha Testing
# Supported profile: ubuntu_gnome_bare_metal (Ubuntu 24.04 LTS, x86_64)
# Traceability: INS-FR-001 through INS-FR-015; INS-DES-001 through INS-DES-015.
# ==============================================================================
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.8.0-alpha.1"
readonly VERSION_DTG="2026-08-07-10-44"
readonly DEVELOPMENT_STATUS="Alpha Testing"
readonly PLATFORM_ID="ubuntu_gnome"
readonly DEPLOYMENT_PROFILE_ID="ubuntu_gnome_bare_metal"
readonly SUPPORTED_SCHEMA="2.2"
readonly COURSE_ROOT="$HOME/it140"
readonly SCRIPT_ROOT="$COURSE_ROOT/scripts"
readonly SCRIPT_DIR="$SCRIPT_ROOT/nix/ubg"
readonly MANIFEST_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="$COURSE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/setup_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_FILE="$HOME/.cache/it140-ubg-mutation.lock"
readonly EXIT_FAILURE=1 EXIT_UNSUPPORTED=2 EXIT_PRIVILEGE=3 EXIT_EXTERNAL=4 EXIT_MANIFEST=5 EXIT_CANCELED=6 EXIT_PARTIAL=7
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
WARNINGS=0
FAILURES=0
FINALIZED=false
APT_METADATA_REFRESHED=false
CURRENT_STAGE="initialization"
MANIFEST_RELEASE="unavailable"
START_EPOCH="$(date +%s)"
header(){ printf '\n============================================================\n%s\n============================================================\n' "$1"; }
info(){ printf '[INFO] %s\n' "$1"; }
success(){ printf '[SUCCESS] %s\n' "$1"; }
notice(){ printf '[NOTICE] %s\n' "$1"; }
warning(){ printf '[WARNING] %s\n' "$1"; WARNINGS=$((WARNINGS+1)); }
error(){ printf '[ERROR] %s\n' "$1" >&2; }
state(){ printf '[STATE] %s — %s: %s\n' "$1" "$2" "$3"; }
continuity(){ notice 'Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.'; }
usage(){ cat <<USAGE
Usage: setup_ubg.sh [--help] [--version]
                    [--deployment-profile ubuntu_gnome_bare_metal]
Installs missing system-level IT 140 software on Ubuntu 24.04 GNOME. Compatible
preexisting applications are preserved even when APT did not install them.
Package-manager provenance is diagnostic; capability compliance is primary.
Logs: ~/it140/logs/
USAGE
}
parse(){
    while (($#)); do
        case "$1" in
            --help|-h) usage; exit 0;;
            --version) printf '%s (%s; %s)\n' "$SCRIPT_VERSION" "$VERSION_DTG" "$DEVELOPMENT_STATUS"; exit 0;;
            --deployment-profile|--profile) shift; (($#)) || { error 'Missing deployment profile.'; exit 2; }; REQUESTED_PROFILE="$1";;
            *) error "Unsupported option: $1"; usage >&2; exit 2;;
        esac
        shift
    done
}
finish(){
    local code="$1" result="$2" detail="$3"
    [[ "$FINALIZED" == false ]] || return "$code"
    FINALIZED=true
    header 'IT 140 UBUNTU GNOME SETUP SUMMARY'
    printf 'Result             : %s\n' "$result"
    printf 'Script version     : %s\n' "$SCRIPT_VERSION"
    printf 'Version DTG        : %s\n' "$VERSION_DTG"
    printf 'Development status: %s\n' "$DEVELOPMENT_STATUS"
    printf 'Manifest release   : %s\n' "$MANIFEST_RELEASE"
    printf 'Managed changes    : %s\n' "$( [[ "$CHANGED" == true ]] && printf Yes || printf No )"
    printf 'Warnings           : %s\n' "$WARNINGS"
    printf 'Failures           : %s\n' "$FAILURES"
    printf 'Elapsed seconds    : %s\n' "$(( $(date +%s)-START_EPOCH ))"
    printf 'Detail             : %s\n' "$detail"
    printf 'Next step          : %s\n' 'Open a new Terminal and run config_ubg.sh.'
    printf 'Log file           : %s\n' "$LOG_FILE"
    printf 'Exit code          : %s\n' "$code"
    ((code==0)) || continuity
    notice 'Review the summary and log before closing Terminal.'
    return "$code"
}
fatal(){ local code="$1"; shift; FAILURES=$((FAILURES+1)); error "$*"; finish "$code" FAIL "$*"; exit $?; }
on_error(){ local code=$?; trap - ERR; FAILURES=$((FAILURES+1)); error "Unexpected failure during ${CURRENT_STAGE} (status ${code})."; finish "$([[ "$CHANGED" == true ]] && printf 7 || printf 1)" FAIL "An unexpected command failure stopped Setup."; exit $?; }
on_interrupt(){ trap - INT TERM HUP; finish "$([[ "$CHANGED" == true ]] && printf 7 || printf 6)" CANCELED 'Setup was interrupted. Rerun it to reevaluate the system layer.'; exit $?; }
validate_manifest(){
    python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
import json,pathlib,sys
mp,sp,pid,profile,schema_version=sys.argv[1:]
m=json.loads(pathlib.Path(mp).read_text(encoding='utf-8'))
s=json.loads(pathlib.Path(sp).read_text(encoding='utf-8'))
if m.get('schema_version') != schema_version: raise SystemExit('unsupported manifest schema')
if s.get('$schema') != 'https://json-schema.org/draft/2020-12/schema': raise SystemExit('unsupported JSON Schema draft')
p=m.get('platforms',{}).get(pid); d=m.get('deployment_profiles',{}).get(profile)
if not p or not p.get('enabled') or not d or not d.get('enabled') or d.get('platform_id') != pid: raise SystemExit('Ubuntu GNOME profile invalid')
if d.get('architecture') != 'x86_64': raise SystemExit('Ubuntu GNOME architecture invalid')
print(m['automation_release'])
PY
}
manifest_query(){
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$1" <<'PY'
import json,sys
m=json.load(open(sys.argv[1],encoding='utf-8')); p=m['platforms'][sys.argv[2]]; q=sys.argv[3]
if q == 'os_packages':
    for x in p.get('os_packages',{}).values():
        if x.get('required') and x.get('package_identifier'):
            print(f"{x['package_identifier']}\t{x.get('source_id','ubuntu_archive')}")
elif q == 'system_bindings':
    for role,x in p.get('course_ide_bindings',{}).items():
        if x.get('required') and x.get('installation_scope') == 'system' and x.get('installer_adapter_id') == 'apt_package':
            commands=','.join(x.get('verification',{}).get('executable_names',[]))
            print(f"{role}\t{x['package_identifier']}\t{x.get('source_id','ubuntu_archive')}\t{commands}")
PY
}
apt_package_present(){ dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" 2>/dev/null | grep -q '^ii '; }
refresh_apt(){
    [[ "$APT_METADATA_REFRESHED" == true ]] && return
    CURRENT_STAGE='Refresh APT metadata'
    sudo apt-get -o Acquire::Retries=5 update || fatal "$EXIT_EXTERNAL" 'APT package metadata could not be refreshed.'
    APT_METADATA_REFRESHED=true
}
install_apt_packages(){
    (($#)) || return
    refresh_apt
    CURRENT_STAGE="Install missing APT packages: $*"
    sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y "$@" || fatal "$EXIT_FAILURE" "Required APT packages could not be installed: $*"
    CHANGED=true
    local package
    for package in "$@"; do apt_package_present "$package" || fatal "$EXIT_FAILURE" "APT did not report the required package installed: $package"; state 'INSTALLED — by IT 140' system_package "$package"; done
}
command_compatible(){
    local role="$1" command_name="$2"
    command -v "$command_name" >/dev/null 2>&1 || return 1
    if [[ "$role" == programming_language_runtime ]]; then
        [[ "$("$(command -v "$command_name")" -c 'import sys; print(".".join(map(str,sys.version_info[:2])))' 2>/dev/null || true)" == 3.12 ]]
    fi
}
ensure_github_cli_source(){
    local list='/etc/apt/sources.list.d/github-cli.list' key='/usr/share/keyrings/githubcli-archive-keyring.gpg'
    if [[ -e "$list" ]] && ! grep -Fq 'https://cli.github.com/packages' "$list"; then fatal "$EXIT_FAILURE" "An existing unmanaged GitHub CLI source file at $list conflicts with the approved source and was preserved."; fi
    if [[ ! -e "$key" ]]; then CURRENT_STAGE='Install GitHub CLI repository signing key'; curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee "$key" >/dev/null || fatal "$EXIT_EXTERNAL" 'The GitHub CLI repository signing key could not be retrieved.'; sudo chmod go+r "$key"; CHANGED=true; fi
    if [[ ! -e "$list" ]]; then printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' "$(dpkg --print-architecture)" "$key" | sudo tee "$list" >/dev/null; CHANGED=true; fi
    APT_METADATA_REFRESHED=false
}
ensure_vscode_source(){
    local list='/etc/apt/sources.list.d/vscode.list' key='/usr/share/keyrings/packages.microsoft.gpg'
    if [[ -e "$list" ]] && ! grep -Fq 'https://packages.microsoft.com/repos/code' "$list"; then fatal "$EXIT_FAILURE" "An existing unmanaged Visual Studio Code source file at $list conflicts with the approved source and was preserved."; fi
    if [[ ! -e "$key" ]]; then CURRENT_STAGE='Install Microsoft package signing key'; local temp; temp="$(mktemp)"; curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$temp" || { rm -f "$temp"; fatal "$EXIT_EXTERNAL" 'The Microsoft package signing key could not be retrieved.'; }; sudo install -m 0644 "$temp" "$key"; rm -f "$temp"; CHANGED=true; fi
    if [[ ! -e "$list" ]]; then printf 'deb [arch=%s signed-by=%s] https://packages.microsoft.com/repos/code stable main\n' "$(dpkg --print-architecture)" "$key" | sudo tee "$list" >/dev/null; CHANGED=true; fi
    APT_METADATA_REFRESHED=false
}
ensure_source(){ case "$1" in ubuntu_archive|'') ;; github_cli_packages) ensure_github_cli_source;; microsoft_vscode_packages) ensure_vscode_source;; *) fatal "$EXIT_MANIFEST" "Unsupported Ubuntu software source: $1";; esac; }
install_binding(){
    local role="$1" package="$2" source_id="$3" commands="$4" command_name="${commands%%,*}"
    CURRENT_STAGE="Evaluate required capability ${role}"
    if [[ -n "$command_name" ]] && command_compatible "$role" "$command_name"; then
        if apt_package_present "$package"; then state 'PRESENT — APT package present, compatible' "$role" "$(command -v "$command_name")"; else state 'PRESENT — externally installed, compatible' "$role" "$(command -v "$command_name")"; fi
        return
    fi
    if apt_package_present "$package"; then
        state 'INCOMPATIBLE — preserved' "$role" "$package is installed, but its required capability is unavailable or incompatible"
        fatal "$EXIT_FAILURE" "Existing $package was preserved. Repair or update it manually, then rerun Setup."
    fi
    state MISSING "$role" "$package"
    ensure_source "$source_id"
    install_apt_packages "$package"
    if [[ -n "$command_name" ]] && ! command_compatible "$role" "$command_name"; then fatal "$EXIT_FAILURE" "Required capability is unavailable after installing $package."; fi
}
parse "$@"
mkdir -p "$LOG_DIR" "$(dirname "$LOCK_FILE")"
chmod 0700 "$LOG_DIR"
: > "$LOG_FILE"; chmod 0600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
trap on_error ERR
trap on_interrupt INT TERM HUP
header 'IT 140 UBUNTU GNOME SYSTEM SETUP'
info "Script version : $SCRIPT_VERSION"
info "Version DTG    : $VERSION_DTG"
info "Status         : $DEVELOPMENT_STATUS"
info "Current user   : $(id -un)"
info "Course root    : $COURSE_ROOT"
info "Log file       : $LOG_FILE"
notice 'Compatible preexisting applications are preserved; package-manager ownership is not required for local capability compliance.'
notice 'Setup does not create the course Python environment or change personal Git/GitHub/VS Code settings; config_ubg.sh owns those tasks.'
CURRENT_STAGE='Validate execution context'
((EUID!=0)) || fatal "$EXIT_UNSUPPORTED" 'Run Setup as the regular desktop user, not with sudo.'
[[ -r /etc/os-release ]] || fatal "$EXIT_UNSUPPORTED" 'Ubuntu could not be identified.'
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || fatal "$EXIT_UNSUPPORTED" 'This implementation supports Ubuntu 24.04 LTS only.'
[[ "$(uname -m)" == x86_64 ]] || fatal "$EXIT_UNSUPPORTED" 'This implementation supports x86_64 only.'
[[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] || fatal "$EXIT_UNSUPPORTED" "Unsupported deployment profile: $REQUESTED_PROFILE"
command -v sudo >/dev/null 2>&1 || fatal "$EXIT_PRIVILEGE" 'sudo is required for system installation.'
sudo -v || fatal "$EXIT_PRIVILEGE" 'Administrator authorization is required for system installation.'
exec 9>"$LOCK_FILE"
flock -n 9 || fatal "$EXIT_PARTIAL" 'Another IT 140 Ubuntu mutation script is running.'
CURRENT_STAGE='Validate controlled manifest'
[[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || fatal "$EXIT_MANIFEST" 'The controlled manifest or schema is missing.'
MANIFEST_RELEASE="$(validate_manifest 2>&1)" || fatal "$EXIT_MANIFEST" "The controlled manifest is invalid: $MANIFEST_RELEASE"
info "Manifest release: $MANIFEST_RELEASE"
header 'Stage 1: Required Ubuntu Support Packages'
declare -a missing_os=()
while IFS=$'\t' read -r package source_id; do
    [[ -n "$package" ]] || continue
    if apt_package_present "$package"; then state 'PRESENT — APT package present' system_package "$package"; else state MISSING system_package "$package"; [[ "$source_id" == ubuntu_archive ]] && missing_os+=("$package"); fi
done < <(manifest_query os_packages)
((${#missing_os[@]}==0)) || install_apt_packages "${missing_os[@]}"
header 'Stage 2: Manifest-Declared System Capabilities'
while IFS=$'\t' read -r role package source_id commands; do
    [[ -n "$role" && -n "$package" ]] || continue
    install_binding "$role" "$package" "$source_id" "$commands"
done < <(manifest_query system_bindings)
header 'Stage 3: Post-Installation Validation'
while IFS=$'\t' read -r role package source_id commands; do
    [[ -n "$role" && -n "$package" ]] || continue
    command_name="${commands%%,*}"
    if [[ -n "$command_name" ]] && ! command_compatible "$role" "$command_name"; then fatal "$EXIT_FAILURE" "Required capability failed post-validation: $role ($command_name)."; fi
    if apt_package_present "$package"; then state 'PRESENT — APT package present, compatible' "$role" "$package"; else state 'PRESENT — externally installed, compatible' "$role" "$(command -v "$command_name")"; fi
done < <(manifest_query system_bindings)
success 'Required Ubuntu system capabilities passed post-validation.'
finish 0 PASS 'Required system software is compatible. Compatible preexisting applications were preserved.'
exit $?
