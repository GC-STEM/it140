#!/bin/zsh
# ==============================================================================
# IT 140 COURSE IDE — INSTALL (macOS APPLE SILICON)
# ==============================================================================
# Repository path: scripts/mac/install_it140.zsh
# Purpose: Install or repair the manifest-declared macOS system layer for the IT 140 course IDE.
# Artifact ID: IT140-MAC-INSTALL
# Artifact version: 0.10.0-beta.1
# Version date-time group: 2026-08-09-23-59
# Development status: Beta Testing
# Supported profile: macos_bare_metal (Apple silicon, arm64)
# Traceability: INS-FR-001 through INS-FR-015; PKG-FR-003 through PKG-FR-010; PKG-FR-021; PKG-QOS-011 through PKG-QOS-015.
# ==============================================================================
set -euo pipefail
umask 077
readonly IT140_ACTION='install'
readonly IT140_ACTION_DISPLAY='Install'
readonly IT140_ARTIFACT_ID='IT140-MAC-INSTALL'
readonly IT140_ARTIFACT_VERSION='0.10.0-beta.1'
readonly IT140_VERSION_DATE_TIME_GROUP='2026-08-09-23-59'
readonly IT140_DEVELOPMENT_STATUS='Beta Testing'
readonly IT140_PURPOSE='Install missing manifest-declared macOS system capabilities while preserving compatible preexisting applications.'
readonly IT140_SUPPORTED_SCHEMA='2.2'
readonly IT140_PLATFORM_ID='macos'
readonly IT140_PLATFORM_ABBREVIATION='mac'
readonly IT140_DEFAULT_PROFILE='macos_bare_metal'
readonly IT140_COURSE_ROOT="${HOME}/it140"
readonly IT140_SCRIPT_ROOT="${IT140_COURSE_ROOT}/scripts"
readonly IT140_MANIFEST_PATH="${IT140_SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly IT140_SCHEMA_PATH="${IT140_SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly IT140_LOG_DIR="${IT140_COURSE_ROOT}/logs"
readonly IT140_RUN_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly IT140_LOG_FILE="${IT140_LOG_DIR}/${IT140_ACTION}_ide_${IT140_RUN_TIMESTAMP}.log"
readonly IT140_LOCK_PARENT="${HOME}/Library/Caches"
readonly IT140_LOCK_DIR="${IT140_LOCK_PARENT}/it140-${IT140_PLATFORM_ABBREVIATION}-mutation.lock"
IT140_NONINTERACTIVE=false
IT140_REQUESTED_PROFILE="$IT140_DEFAULT_PROFILE"
IT140_CHANGED=false
IT140_LOCK_HELD=false
IT140_WARNINGS=0
IT140_FAILURES=0
IT140_START_EPOCH="$(date +%s)"
IT140_CURRENT_STAGE='Initialization'
IT140_MANIFEST_RELEASE='Unavailable'
IT140_MANIFEST_DTG='Unavailable'
IT140_WORKFLOW_ID='Unavailable'
IT140_STARTING_STATE='Unavailable'
IT140_OPERATING_ROLE='local_user'
IT140_MINIMUM_FREE_SPACE_BYTES=5368709120
IT140_NETWORK_TIMEOUT_SECONDS=60
IT140_RETRY_MAXIMUM_ATTEMPTS=5
IT140_RETRY_INITIAL_DELAY_SECONDS=5
IT140_RUNTIME_TEMP_DIR=''
IT140_TEMP_PATHS=()
IT140_BREW_METADATA_REFRESHED=false
it140_usage() {
    cat <<'USAGE'
Usage: install_it140.zsh [--help] [--version] [--noninteractive]
                         [--deployment-profile macos_bare_metal]

Installs missing Apple Command Line Tools, Homebrew, and manifest-declared
system capabilities. Compatible preexisting applications are preserved even
when Homebrew did not install them. Package-manager ownership is not required
for local capability compliance.
The script never uses Homebrew --adopt or --force to take ownership of an
existing application. It does not authenticate GitHub or configure personal
Git, Python-environment, VS Code-extension, or editor settings.
Logs: ~/it140/logs/
USAGE
}
it140_parse_options() {
    while (( $# > 0 )); do
        case "$1" in
            --help|-h) it140_usage; exit 0;;
            --version) printf '%s %s (%s)\nStatus: %s\n' "$IT140_ARTIFACT_ID" "$IT140_ARTIFACT_VERSION" "$IT140_VERSION_DATE_TIME_GROUP" "$IT140_DEVELOPMENT_STATUS"; exit 0;;
            --noninteractive) IT140_NONINTERACTIVE=true;;
            --deployment-profile|--profile) (( $# >= 2 )) || { printf '[ERROR] %s requires a value.\n' "$1" >&2; exit 2; }; IT140_REQUESTED_PROFILE="$2"; shift;;
            --) shift; break;;
            *) printf '[ERROR] Unsupported option: %s\n' "$1" >&2; it140_usage >&2; exit 2;;
        esac
        shift
    done
    (( $# == 0 )) || { printf '[ERROR] Unexpected argument: %s\n' "$1" >&2; exit 2; }
}
it140_header(){ printf '\n============================================================\n%s\n============================================================\n' "$1"; }
it140_info(){ printf '[INFO] %s\n' "$*"; }
it140_success(){ printf '[SUCCESS] %s\n' "$*"; }
it140_notice(){ printf '[NOTICE] %s\n' "$*"; }
it140_warning(){ IT140_WARNINGS=$((IT140_WARNINGS+1)); printf '[WARNING] %s\n' "$*"; }
it140_error(){ IT140_FAILURES=$((IT140_FAILURES+1)); printf '[ERROR] %s\n' "$*" >&2; }
it140_state(){ local state="$1" role="$2" detail="$3"; it140_info "${state} — ${role}: ${detail}"; }
it140_register_temp(){ IT140_TEMP_PATHS+=("$1"); }
it140_release_lock(){ [[ "$IT140_LOCK_HELD" == true && -d "$IT140_LOCK_DIR" ]] && /bin/rm -rf -- "$IT140_LOCK_DIR"; IT140_LOCK_HELD=false; }
it140_cleanup(){ set +e; local p; for p in "${IT140_TEMP_PATHS[@]}"; do [[ -n "$p" ]] && /bin/rm -rf -- "$p"; done; it140_release_lock; }
it140_elapsed(){ printf '%s' "$(( $(date +%s)-IT140_START_EPOCH ))"; }
it140_continuity(){ it140_notice 'Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.'; }
it140_finish() {
    local code="$1" result="$2" detail="$3" next="$4"
    trap - ERR INT TERM HUP; set +e; it140_cleanup
    it140_header 'IT 140 macOS INSTALL SUMMARY'
    printf 'Result                  : %s\n' "$result"
    printf 'Artifact ID             : %s\n' "$IT140_ARTIFACT_ID"
    printf 'Artifact version        : %s\n' "$IT140_ARTIFACT_VERSION"
    printf 'Version date-time group : %s\n' "$IT140_VERSION_DATE_TIME_GROUP"
    printf 'Development status      : %s\n' "$IT140_DEVELOPMENT_STATUS"
    printf 'Manifest release        : %s\n' "$IT140_MANIFEST_RELEASE"
    printf 'Manifest release DTG    : %s\n' "$IT140_MANIFEST_DTG"
    printf 'Deployment profile      : %s\n' "$IT140_REQUESTED_PROFILE"
    printf 'Workflow                : %s\n' "$IT140_WORKFLOW_ID"
    printf 'Starting state          : %s\n' "$IT140_STARTING_STATE"
    printf 'Operating role          : %s\n' "$IT140_OPERATING_ROLE"
    printf 'Managed changes         : %s\n' "$( [[ "$IT140_CHANGED" == true ]] && printf 'Yes' || printf 'No' )"
    printf 'Warnings                : %s\n' "$IT140_WARNINGS"
    printf 'Failures                : %s\n' "$IT140_FAILURES"
    printf 'Elapsed time            : %s seconds\n' "$(it140_elapsed)"
    printf 'Detail                  : %s\n' "$detail"
    printf 'Next step               : %s\n' "$next"
    printf 'Log file                : %s\n' "$IT140_LOG_FILE"
    printf 'Exit code               : %s\n' "$code"
    (( code == 0 )) && it140_success 'The IT 140 macOS Install completed successfully.' || it140_continuity
    it140_notice 'Review the summary and log before closing Terminal.'
    [[ "$next" == 'None' ]] || it140_notice 'Open a new Terminal window before running the next lifecycle script.'
    exit "$code"
}
it140_abort(){ local code="$1"; shift; local msg="$*"; [[ "$IT140_CHANGED" == true && "$code" -ne 2 && "$code" -ne 5 ]] && code=7; it140_error "$msg"; it140_error "Failed stage: $IT140_CURRENT_STAGE"; it140_finish "$code" 'FAIL' "$msg" 'Rerun: "$HOME/it140/scripts/mac/install_it140.zsh"'; }
it140_on_error(){ local exit_status="$1" line="$2"; trap - ERR; set +e; local code=1; [[ "$IT140_CHANGED" == true ]] && code=7; it140_error "Unexpected failure near line ${line} during ${IT140_CURRENT_STAGE} (status ${exit_status})."; it140_finish "$code" 'FAIL' 'An unexpected command failure stopped Install.' 'Rerun: "$HOME/it140/scripts/mac/install_it140.zsh"'; }
it140_on_interrupt(){ trap - INT TERM HUP; set +e; local code=6; [[ "$IT140_CHANGED" == true ]] && code=7; it140_error "Install was interrupted during ${IT140_CURRENT_STAGE}."; it140_finish "$code" 'CANCELED' 'The operation did not finish; rerun Install to recover.' 'Rerun: "$HOME/it140/scripts/mac/install_it140.zsh"'; }
it140_initialize_log() {
    /bin/mkdir -p -- "$IT140_LOG_DIR"; /bin/chmod 0700 "$IT140_LOG_DIR"; : > "$IT140_LOG_FILE"; /bin/chmod 0600 "$IT140_LOG_FILE"
    exec > >(/usr/bin/tee -a "$IT140_LOG_FILE") 2>&1
    IT140_RUNTIME_TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/it140-install.XXXXXX")"; it140_register_temp "$IT140_RUNTIME_TEMP_DIR"
    trap 'it140_on_error $? $LINENO' ERR; trap 'it140_on_interrupt' INT TERM HUP
    it140_header 'IT 140 macOS INSTALL'
    it140_info "Artifact version        : $IT140_ARTIFACT_VERSION"
    it140_info "Version date-time group : $IT140_VERSION_DATE_TIME_GROUP"
    it140_info "Status                  : $IT140_DEVELOPMENT_STATUS"
    it140_info "Current user            : $(id -un 2>/dev/null || printf Unknown)"
    it140_info "Purpose                 : $IT140_PURPOSE"
    it140_info "Log file                : $IT140_LOG_FILE"
    it140_notice 'Compatible preexisting applications are preserved; package-manager ownership is not required for local compliance.'
}
it140_prune_logs(){ set +e; /usr/bin/find "$IT140_LOG_DIR" -type f -name '*.log' -mtime +180 -delete 2>/dev/null; /bin/ls -1t "$IT140_LOG_DIR"/*.log 2>/dev/null | /usr/bin/awk 'NR>50' | while IFS= read -r f; do [[ -n "$f" ]] && /bin/rm -f -- "$f"; done; set -e; }
it140_acquire_lock() {
    IT140_CURRENT_STAGE='Acquire mutation lock'; /bin/mkdir -p -- "$IT140_LOCK_PARENT"
    if /bin/mkdir -- "$IT140_LOCK_DIR" 2>/dev/null; then printf '%s\n' "$$" > "$IT140_LOCK_DIR/pid"; printf '%s\n' "$(date +%s)" > "$IT140_LOCK_DIR/created_epoch"; IT140_LOCK_HELD=true; return; fi
    local pid='' created=0 now age; [[ -r "$IT140_LOCK_DIR/pid" ]] && pid="$(<"$IT140_LOCK_DIR/pid")"; [[ -r "$IT140_LOCK_DIR/created_epoch" ]] && created="$(<"$IT140_LOCK_DIR/created_epoch")"; [[ "$created" =~ ^[0-9]+$ ]] || created=0; now="$(date +%s)"; age=$((now-created))
    if [[ "$pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$pid" 2>/dev/null && (( age < 7200 )); then it140_abort 7 "Another IT 140 macOS lifecycle script is running (process ${pid})."; fi
    it140_warning 'A stale lifecycle lock was found and removed.'; /bin/rm -rf -- "$IT140_LOCK_DIR"; /bin/mkdir -- "$IT140_LOCK_DIR" || it140_abort 1 'The lifecycle lock could not be acquired.'
    printf '%s\n' "$$" > "$IT140_LOCK_DIR/pid"; printf '%s\n' "$(date +%s)" > "$IT140_LOCK_DIR/created_epoch"; IT140_LOCK_HELD=true
}
it140_manifest_tool() {
    local query="$1"; shift
    /usr/bin/osascript -l JavaScript - "$IT140_MANIFEST_PATH" "$IT140_SCHEMA_PATH" "$query" "$@" <<'JXA'
ObjC.import('Foundation')
function readText(p){var d=$.NSData.dataWithContentsOfFile($(p));if(!d)throw new Error('cannot read '+p);var t=$.NSString.alloc.initWithDataEncoding(d,$.NSUTF8StringEncoding);if(!t)throw new Error('invalid UTF-8 '+p);return ObjC.unwrap(t)}
function run(argv){
  var m=JSON.parse(readText(argv[0])),s=JSON.parse(readText(argv[1])),q=argv[2],a=argv.slice(3),pid='macos';
  if(q==='validate'){
    var prof=a[0],os=a[1],sv=a[2],p=m.platforms&&m.platforms[pid],d=m.deployment_profiles&&m.deployment_profiles[prof];
    var required=['schema_version','automation_release','automation_release_date_time_group','policy','platforms','deployment_profiles','lifecycle_workflows'];
    required.forEach(function(k){if(!(k in m))throw new Error('manifest missing required key '+k)});
    if(m.schema_version!==sv)throw new Error('unsupported manifest schema '+m.schema_version);
    if(!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(String(m.automation_release)))throw new Error('invalid automation release');
    if(!/^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$/.test(String(m.automation_release_date_time_group)))throw new Error('invalid automation release date-time group');
    if(!s.properties||!s.properties.schema_version||s.properties.schema_version.const!==sv)throw new Error('schema contract mismatch');
    if(!p||p.enabled!==true||!d||d.enabled!==true||d.platform_id!==pid||d.architecture!=='arm64')throw new Error('macOS profile invalid');
    if(!p.os.releases.some(function(r){return String(r.release_id)===String(os)}))throw new Error('unsupported macOS release '+os);
    if(m.policy.allow_os_release_upgrade!==false)throw new Error('OS release upgrades must be prohibited');
    var w=m.lifecycle_workflows.local_initial_install;if(!w||d.allowed_workflow_ids.indexOf('local_initial_install')<0)throw new Error('initial-install workflow unavailable');
    var rp=m.policy.retry_profiles[m.policy.default_retry_profile_id];
    return ['release='+m.automation_release,'dtg='+m.automation_release_date_time_group,'workflow=local_initial_install','starting='+w.starting_state_id,'role='+w.operating_roles[0],'space='+m.policy.minimum_free_space_bytes,'timeout='+m.policy.network_timeout_seconds,'attempts='+rp.maximum_attempts,'delay='+rp.initial_delay_seconds].join('\n');
  }
  var b=m.platforms[pid].course_ide_bindings;
  if(q==='system_bindings'){
    var rows=[];Object.keys(b).forEach(function(role){var x=b[role];if(x.required===true&&x.installation_scope==='system'&&(x.installer_adapter_id==='homebrew_formula'||x.installer_adapter_id==='homebrew_cask')){var e=(x.verification&&x.verification.executable_names)||[];rows.push([role,x.installer_adapter_id,x.package_identifier,e.join(',')].join('\t'));}});return rows.join('\n');
  }
  throw new Error('unsupported manifest query '+q);
}
JXA
}
it140_load_manifest() {
    IT140_CURRENT_STAGE='Validate controlled manifest and schema'; [[ -r "$IT140_MANIFEST_PATH" && -r "$IT140_SCHEMA_PATH" ]] || it140_abort 5 'The controlled manifest or schema is missing or unreadable.'
    local os summary k v; os="$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $1}')"; summary="$(it140_manifest_tool validate "$IT140_REQUESTED_PROFILE" "$os" "$IT140_SUPPORTED_SCHEMA" 2>&1)" || it140_abort 5 "Controlled manifest validation failed: ${summary}"
    while IFS='=' read -r k v; do case "$k" in release) IT140_MANIFEST_RELEASE="$v";; dtg) IT140_MANIFEST_DTG="$v";; workflow) IT140_WORKFLOW_ID="$v";; starting) IT140_STARTING_STATE="$v";; role) IT140_OPERATING_ROLE="$v";; space) IT140_MINIMUM_FREE_SPACE_BYTES="$v";; timeout) IT140_NETWORK_TIMEOUT_SECONDS="$v";; attempts) IT140_RETRY_MAXIMUM_ATTEMPTS="$v";; delay) IT140_RETRY_INITIAL_DELAY_SECONDS="$v";; esac; done <<< "$summary"
    it140_info "Manifest release : $IT140_MANIFEST_RELEASE"; it140_info "Workflow         : $IT140_WORKFLOW_ID"
}
it140_check_context() {
    IT140_CURRENT_STAGE='Check supported platform and user context'; [[ "$(uname -s)" == Darwin ]] || it140_abort 2 'This script supports macOS only.'; (( $(id -u) != 0 )) || it140_abort 2 'Do not run this script with sudo.'; [[ "$(uname -m)" == arm64 ]] || it140_abort 2 'The current macOS implementation supports Apple silicon (arm64) only.'; [[ "$IT140_REQUESTED_PROFILE" == "$IT140_DEFAULT_PROFILE" ]] || it140_abort 2 "Unsupported deployment profile: $IT140_REQUESTED_PROFILE"
    local u="$(id -un)"; /usr/sbin/dseditgroup -o checkmember -m "$u" admin 2>/dev/null | /usr/bin/grep -q yes || it140_abort 3 'The account running Install must be a macOS Administrator account.'
    local kb bytes; kb="$(/bin/df -Pk "$HOME" | /usr/bin/awk 'NR==2{print $4}')"; [[ "$kb" =~ ^[0-9]+$ ]] || it140_abort 1 'Available storage could not be determined.'; bytes=$((kb*1024)); (( bytes >= IT140_MINIMUM_FREE_SPACE_BYTES )) || it140_abort 1 'At least 5 GB of available storage is required.'
}
it140_network_probe(){ IT140_CURRENT_STAGE='Check approved network source'; local a=1 d="$IT140_RETRY_INITIAL_DELAY_SECONDS"; while (( a<=IT140_RETRY_MAXIMUM_ATTEMPTS )); do /usr/bin/curl --fail --silent --show-error --location --connect-timeout 15 --max-time "$IT140_NETWORK_TIMEOUT_SECONDS" --output /dev/null 'https://github.com/GC-STEM/it140' && return; ((a<IT140_RETRY_MAXIMUM_ATTEMPTS)) && /bin/sleep "$d"; d=$((d*2)); ((d>60))&&d=60; a=$((a+1)); done; it140_abort 4 'The approved GitHub source was unavailable after bounded retries.'; }
it140_download(){ local url="$1" out="$2" desc="$3" a=1 d="$IT140_RETRY_INITIAL_DELAY_SECONDS"; while ((a<=IT140_RETRY_MAXIMUM_ATTEMPTS)); do it140_info "Downloading ${desc} (attempt ${a}/${IT140_RETRY_MAXIMUM_ATTEMPTS})."; /usr/bin/curl --fail --silent --show-error --location --connect-timeout 20 --max-time 300 --output "$out" "$url" && return 0; /bin/rm -f -- "$out"; ((a<IT140_RETRY_MAXIMUM_ATTEMPTS))&&/bin/sleep "$d"; d=$((d*2)); ((d>60))&&d=60; a=$((a+1)); done; return 1; }
it140_find_brew(){ [[ -x /opt/homebrew/bin/brew ]] && { printf '%s' /opt/homebrew/bin/brew; return; }; command -v brew >/dev/null 2>&1 && { command -v brew; return; }; return 1; }
it140_refresh_brew(){ [[ "$IT140_BREW_METADATA_REFRESHED" == true ]] && return; IT140_CURRENT_STAGE='Refresh Homebrew metadata'; "$BREW_PATH" update || it140_abort 4 'Homebrew package metadata could not be refreshed.'; IT140_BREW_METADATA_REFRESHED=true; }
it140_command_compatible(){ local role="$1" cmd="$2"; command -v "$cmd" >/dev/null 2>&1 || return 1; if [[ "$role" == programming_language_runtime ]]; then local v; v="$("$(command -v "$cmd")" -c 'import sys; print(".".join(map(str,sys.version_info[:2])))' 2>/dev/null)" || return 1; [[ "$v" == 3.12 ]]; fi; }
IT140_VSCODE_APP_PATH=''
IT140_VSCODE_CONFLICT_PATH=''
it140_detect_vscode_app() {
    local app bundle
    IT140_VSCODE_APP_PATH=''
    IT140_VSCODE_CONFLICT_PATH=''
    for app in '/Applications/Visual Studio Code.app' "$HOME/Applications/Visual Studio Code.app"; do
        [[ -d "$app" ]] || continue
        bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"
        if [[ "$bundle" == 'com.microsoft.VSCode' ]]; then
            IT140_VSCODE_APP_PATH="$app"
            return 0
        fi
        IT140_VSCODE_CONFLICT_PATH="$app"
        return 2
    done
    return 1
}
it140_abort_vscode_conflict() {
    it140_state 'INCOMPATIBLE — preserved' 'source_code_ide' "$IT140_VSCODE_CONFLICT_PATH exists but is not the approved Microsoft Visual Studio Code bundle"
    it140_abort 1 'A conflicting application occupies the Visual Studio Code application path. It was preserved; remove or rename the conflict manually before rerunning Install.'
}
it140_repair_vscode_cli() {
    local app="$1" cli="$app/Contents/Resources/app/bin/code" target='/usr/local/bin/code'
    [[ -f "$cli" ]] || it140_abort 1 'Visual Studio Code is present, but its command-line launcher could not be found inside the application bundle.'
    if command -v code >/dev/null 2>&1; then return; fi
    IT140_CURRENT_STAGE='Repair Visual Studio Code command-line integration'
    if [[ -e "$target" || -L "$target" ]]; then
        [[ -L "$target" && "$(/usr/bin/readlink "$target" 2>/dev/null || true)" == "$cli" ]] || it140_abort 1 "A different item already exists at ${target}. It was preserved."
    else
        /usr/bin/sudo /usr/bin/install -d -m 0755 /usr/local/bin
        /usr/bin/sudo /bin/ln -s "$cli" "$target"
        IT140_CHANGED=true
        it140_state 'REPAIRED — course integration only' 'source_code_ide' "created ${target} -> ${cli}"
    fi
    rehash
    command -v code >/dev/null 2>&1 || it140_abort 1 'Visual Studio Code is installed, but the repaired code command is not discoverable on PATH.'
}
it140_install_formula(){ local role="$1" package="$2" executable_names_csv="$3" cmd="${executable_names_csv%%,*}"; IT140_CURRENT_STAGE="Evaluate Homebrew formula ${package}"; if [[ -n "$cmd" ]] && it140_command_compatible "$role" "$cmd"; then if "$BREW_PATH" list --formula "$package" >/dev/null 2>&1; then it140_state 'PRESENT — package-manager-managed, compatible' "$role" "$package"; else it140_state 'PRESENT — externally installed, compatible' "$role" "$(command -v "$cmd")"; fi; return; fi; if "$BREW_PATH" list --formula "$package" >/dev/null 2>&1; then it140_state 'INCOMPATIBLE — preserved' "$role" "$package is Homebrew-managed but its required capability is unavailable or incompatible"; it140_abort 1 "Existing ${package} was preserved.
Repair or update it manually, then rerun Install."; fi; it140_state 'MISSING' "$role" "$package"; it140_refresh_brew; "$BREW_PATH" install "$package" || it140_abort 1 "Required Homebrew formula could not be installed: ${package}."; IT140_CHANGED=true; rehash; [[ -n "$cmd" ]] && it140_command_compatible "$role" "$cmd" || it140_abort 1 "Required capability is unavailable after installing ${package}."; it140_state 'INSTALLED — by IT 140' "$role" "$package"; }
it140_install_cask() {
    local role="$1" package="$2" executable_names_csv="$3" cmd="${executable_names_csv%%,*}" app='' detection_status=0
    IT140_CURRENT_STAGE="Evaluate Homebrew cask ${package}"
    if [[ "$package" == visual-studio-code ]]; then
        if it140_detect_vscode_app; then
            app="$IT140_VSCODE_APP_PATH"
            it140_repair_vscode_cli "$app"
            if "$BREW_PATH" list --cask "$package" >/dev/null 2>&1; then
                it140_state 'PRESENT — package-manager-managed, compatible' "$role" "$app"
            else
                it140_state 'PRESENT — externally installed, compatible' "$role" "$app"
            fi
            return
        else
            detection_status=$?
            (( detection_status == 2 )) && it140_abort_vscode_conflict
        fi
    elif [[ -n "$cmd" ]] && command -v "$cmd" >/dev/null 2>&1; then
        if "$BREW_PATH" list --cask "$package" >/dev/null 2>&1; then
            it140_state 'PRESENT — package-manager-managed, compatible' "$role" "$package"
        else
            it140_state 'PRESENT — externally installed, compatible' "$role" "$(command -v "$cmd")"
        fi
        return
    fi
    if "$BREW_PATH" list --cask "$package" >/dev/null 2>&1; then
        it140_state 'INCOMPATIBLE — preserved' "$role" "$package is registered with Homebrew but its required capability is unavailable"
        it140_abort 1 "Existing ${package} was preserved. Repair or update it manually, then rerun Install."
    fi
    it140_state 'MISSING' "$role" "$package"
    it140_refresh_brew
    "$BREW_PATH" install --cask "$package" || it140_abort 1 "Required Homebrew cask could not be installed: ${package}."
    IT140_CHANGED=true
    rehash
    if [[ "$package" == visual-studio-code ]]; then
        if ! it140_detect_vscode_app; then
            detection_status=$?
            (( detection_status == 2 )) && it140_abort_vscode_conflict
            it140_abort 1 'Microsoft Visual Studio Code was not found after installation.'
        fi
        app="$IT140_VSCODE_APP_PATH"
        it140_repair_vscode_cli "$app"
    elif [[ -n "$cmd" ]]; then
        command -v "$cmd" >/dev/null 2>&1 || it140_abort 1 "Required capability is unavailable after installing ${package}."
    fi
    it140_state 'INSTALLED — by IT 140' "$role" "$package"
}

it140_parse_options "$@"
it140_initialize_log
it140_prune_logs
it140_check_context
it140_load_manifest
it140_network_probe
it140_acquire_lock
it140_header 'Stage 1: Apple Command Line Tools'
IT140_CURRENT_STAGE='Install or verify Apple Command Line Tools'
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    it140_state 'MISSING' 'apple_command_line_tools' 'Command Line Tools for Xcode'
    [[ "$IT140_NONINTERACTIVE" == true ]] && it140_abort 3 'Apple Command Line Tools are missing and require an interactive installation.'
    it140_notice 'macOS will open the Apple Command Line Tools installer. Complete it, then rerun Install in a new Terminal.'
    /usr/bin/xcode-select --install >/dev/tty 2>&1 || true
    it140_finish 7 'PARTIAL' 'Apple Command Line Tools installation was requested and must finish before Install can continue.' 'After the installer finishes, rerun: "$HOME/it140/scripts/mac/install_it140.zsh"'
fi
it140_state 'PRESENT — compatible' 'apple_command_line_tools' "$(/usr/bin/xcode-select -p)"
it140_header 'Stage 2: Homebrew'
IT140_CURRENT_STAGE='Install or verify Homebrew'
BREW_PATH=''
if ! BREW_PATH="$(it140_find_brew)"; then
    it140_state 'MISSING' 'package_manager' 'Homebrew'
    INSTALLER_PATH="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/it140-homebrew-install.XXXXXX")"; it140_register_temp "$INSTALLER_PATH"
    it140_download 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' "$INSTALLER_PATH" 'the official Homebrew installer' || it140_abort 4 'The official Homebrew installer was unavailable after bounded retries.'
    /bin/chmod 0700 "$INSTALLER_PATH"
    if [[ "$IT140_NONINTERACTIVE" == true ]]; then NONINTERACTIVE=1 /bin/bash "$INSTALLER_PATH" || it140_abort 3 'Homebrew could not be installed noninteractively.'; else /bin/bash "$INSTALLER_PATH" </dev/tty >/dev/tty 2>/dev/tty || it140_abort 1 'The Homebrew installation did not complete.'; fi
    IT140_CHANGED=true; BREW_PATH="$(it140_find_brew)" || it140_abort 1 'Homebrew was not found after installation.'; it140_state 'INSTALLED — by IT 140' 'package_manager' "$BREW_PATH"
else
    it140_state 'PRESENT — compatible' 'package_manager' "$BREW_PATH"
fi
eval "$("$BREW_PATH" shellenv)"
it140_header 'Stage 3: Manifest-Declared System Capabilities'
BINDINGS_FILE="$IT140_RUNTIME_TEMP_DIR/system_bindings.txt"; it140_manifest_tool system_bindings > "$BINDINGS_FILE" || it140_abort 5 'The manifest system-binding query failed.'
while IFS=$'\t' read -r role adapter package executable_names_csv; do
    [[ -n "$role" && -n "$adapter" && -n "$package" ]] || continue
    case "$adapter" in
        homebrew_formula) it140_install_formula "$role" "$package" "$executable_names_csv";;
        homebrew_cask) it140_install_cask "$role" "$package" "$executable_names_csv";;
        *) it140_abort 5 "Unsupported macOS system installer adapter: ${adapter}";;
    esac
done < "$BINDINGS_FILE"
it140_header 'Stage 4: Post-Installation Validation'
while IFS=$'\t' read -r role adapter package executable_names_csv; do
    [[ -n "$role" ]] || continue
    if [[ "$package" == visual-studio-code ]]; then
        if ! it140_detect_vscode_app; then
            detection_status=$?
            (( detection_status == 2 )) && it140_abort_vscode_conflict
            it140_abort 1 'Microsoft Visual Studio Code is unavailable after Install.'
        fi
        app="$IT140_VSCODE_APP_PATH"
        command -v code >/dev/null 2>&1 || it140_abort 1 'The Visual Studio Code command-line integration is unavailable after Install.'
        it140_success "Required capability available: ${role} (${app})"
        continue
    fi
    cmd="${executable_names_csv%%,*}"; [[ -n "$cmd" ]] || continue
    it140_command_compatible "$role" "$cmd" || it140_abort 1 "Required capability is unavailable or incompatible after Install: ${role} (${cmd})."
    it140_success "Required capability available: ${role} ($(command -v "$cmd"))"
done < "$BINDINGS_FILE"
it140_finish 0 'PASS' 'The macOS system capabilities are available; compatible preexisting applications were preserved.' 'Run next: "$HOME/it140/scripts/mac/configure_it140.zsh"'
