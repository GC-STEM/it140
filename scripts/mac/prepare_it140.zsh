#!/bin/zsh
# ==============================================================================
# IT 140 COURSE IDE — PREPARE (macOS APPLE SILICON)
# ==============================================================================
# Repository path: scripts/mac/prepare_it140.zsh
# Purpose: Acquire or refresh the IT 140 automation package without requiring
#          Homebrew, Git, the controlled manifest, or another lifecycle script.
# Artifact ID: IT140-MAC-PREPARE
# Artifact version: 0.10.0-beta.1
# Version date-time group: 2026-08-09-23-59
# Development status: Beta Testing
# Supported profile: macos_bare_metal (Apple silicon, arm64)
# Traceability: PRE-FR-001 through PRE-FR-015; PKG-FR-006 through PKG-FR-010;
#               PKG-FR-021; PKG-QOS-003 through PKG-QOS-005 and PKG-QOS-011
#               through PKG-QOS-015.
# ==============================================================================
set -euo pipefail
umask 077
readonly ARTIFACT_VERSION='0.10.0-beta.1'
readonly VERSION_DTG='2026-08-09-23-59'
readonly DEVELOPMENT_STATUS='Beta Testing'
readonly COURSE_ROOT="$HOME/it140"
readonly SCRIPT_ROOT="$COURSE_ROOT/scripts"
readonly SCRIPT_DIR="$SCRIPT_ROOT/mac"
readonly LOG_DIR="$COURSE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/prepare_ide_$(date +%Y%m%d_%H%M%S).log"
readonly ARCHIVE_URL='https://github.com/GC-STEM/it140/archive/refs/heads/main.zip'
readonly PATH_FILE="$HOME/.zshrc"
readonly PATH_START='# >>> IT 140 managed PATH >>>'
readonly PATH_END='# <<< IT 140 managed PATH <<<'
readonly LEGACY_PATH_START='# >>> IT 140 Course IDE managed environment >>>'
readonly LEGACY_PATH_END='# <<< IT 140 Course IDE managed environment <<<'
readonly PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:$PATH"'
TEMP_ROOT=''
BACKUP_ROOT=''
CHANGED=false
FINISHED=false
START_EPOCH="$(date +%s)"
CURRENT_STAGE='Initialization'
info() { printf '[INFO] %s\n' "$*"; }
success() { printf '[SUCCESS] %s\n' "$*"; }
notice() { printf '[NOTICE] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }
continuity() {
    notice 'Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.'
}
cleanup() {
    set +e
    [[ -n "$TEMP_ROOT" ]] && /bin/rm -rf -- "$TEMP_ROOT"
}
restore_critical_assets() {
    set +e
    [[ -n "$BACKUP_ROOT" && -d "$BACKUP_ROOT" ]] || return 0
    /bin/rm -rf -- "$SCRIPT_ROOT/mac"
    if [[ -d "$BACKUP_ROOT/mac" ]]; then
        /bin/mkdir -p -- "$SCRIPT_ROOT"
        /usr/bin/ditto "$BACKUP_ROOT/mac" "$SCRIPT_ROOT/mac"
    fi
    /bin/rm -rf -- "$SCRIPT_ROOT/.manifest"
    if [[ -d "$BACKUP_ROOT/manifest" ]]; then
        /bin/mkdir -p -- "$SCRIPT_ROOT"
        /usr/bin/ditto "$BACKUP_ROOT/manifest" "$SCRIPT_ROOT/.manifest"
    fi
}
finish() {
    local code="$1"
    local result="$2"
    local detail="$3"
    trap - ERR INT TERM HUP
    set +e
    FINISHED=true
    cleanup
    printf '\n============================================================\n'
    printf 'IT 140 macOS PREPARE SUMMARY\n'
    printf '============================================================\n'
    printf 'Result                  : %s\n' "$result"
    printf 'Artifact version        : %s\n' "$ARTIFACT_VERSION"
    printf 'Version date-time group : %s\n' "$VERSION_DTG"
    printf 'Development status      : %s\n' "$DEVELOPMENT_STATUS"
    printf 'Course root             : %s\n' "$COURSE_ROOT"
    printf 'Workflow                : local_initial_install\n'
    printf 'Starting state          : local_unmanaged_environment\n'
    printf 'Operating role          : local_user\n'
    printf 'Managed changes         : %s\n' "$( [[ "$CHANGED" == true ]] && printf 'Yes' || printf 'No' )"
    printf 'Elapsed time            : %s seconds\n' "$(( $(date +%s) - START_EPOCH ))"
    printf 'Detail                  : %s\n' "$detail"
    printf 'Next step               : %s\n' '"$HOME/it140/scripts/mac/install_it140.zsh"'
    printf 'Log file                : %s\n' "$LOG_FILE"
    printf 'Exit code               : %s\n' "$code"
    if (( code == 0 )); then
        success 'The IT 140 automation package is available and the macOS scripts are executable.'
    else
        continuity
    fi
    notice 'Review the summary and log before closing Terminal.'
    exit "$code"
}
fail() {
    local code="$1"
    shift
    local message="$*"
    error "$message"
    error "Failed stage: $CURRENT_STAGE"
    finish "$code" 'FAIL' "$message"
}
on_error() {
    local exit_status="$1"
    local line="$2"
    trap - ERR
    set +e
    if [[ "$CHANGED" == true ]]; then
        restore_critical_assets
        finish 7 'FAIL' "Preparation stopped unexpectedly near line ${line}; prior critical automation assets were restored when possible."
    fi
    finish "$exit_status" 'FAIL' "Preparation stopped unexpectedly near line ${line}."
}
on_interrupt() {
    trap - INT TERM HUP
    set +e
    if [[ "$CHANGED" == true ]]; then
        restore_critical_assets
        finish 7 'CANCELED' 'Preparation was interrupted; prior critical automation assets were restored when possible.'
    fi
    finish 6 'CANCELED' 'Preparation was canceled before package activation.'
}
validate_json_file() {
    local json_path="$1"
    /usr/bin/osascript -l JavaScript - "$json_path" <<'JXA' >/dev/null 2>&1
ObjC.import('Foundation')
function run(argv) {
    if (argv.length !== 1) {
        throw new Error('Expected one JSON file path.')
    }
    const data = $.NSData.dataWithContentsOfFile(argv[0])
    if (!data) {
        throw new Error('Unable to read JSON file.')
    }
    const text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)
    if (!text) {
        throw new Error('JSON file is not valid UTF-8.')
    }
    JSON.parse(ObjC.unwrap(text))
}
JXA
}
usage() {
    cat <<'USAGE'
Usage: prepare_it140.zsh [--help] [--version]
Acquire or refresh the IT 140 automation package for the approved Apple-silicon
macOS deployment profile. Prepare uses only native macOS utilities and does not
require Homebrew, Git, the controlled manifest, or another lifecycle script.
USAGE
}
while (( $# )); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --version) printf '%s (%s; %s)\n' "$ARTIFACT_VERSION" "$VERSION_DTG" "$DEVELOPMENT_STATUS"; exit 0 ;;
        *) printf '[ERROR] Unsupported option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
mkdir -p -- "$COURSE_ROOT" "$LOG_DIR"
chmod -- 0700 "$LOG_DIR"
: > "$LOG_FILE"
chmod -- 0600 "$LOG_FILE"
exec > >(/usr/bin/tee -a "$LOG_FILE") 2>&1
trap 'on_error $? $LINENO' ERR
trap 'on_interrupt' INT TERM HUP
printf '\n============================================================\n'
printf 'IT 140 macOS PREPARE\n'
printf '============================================================\n'
printf '[INFO] Artifact version        : %s\n' "$ARTIFACT_VERSION"
printf '[INFO] Version date-time group : %s\n' "$VERSION_DTG"
printf '[INFO] Status                  : %s\n' "$DEVELOPMENT_STATUS"
printf '[INFO] Current user            : %s\n' "$(id -un)"
printf '[INFO] Purpose                 : Acquire or refresh the IT 140 automation package.\n'
printf '[INFO] Log file                : %s\n' "$LOG_FILE"
CURRENT_STAGE='Check supported platform and user context'
[[ "$(uname -s)" == 'Darwin' ]] || fail 2 'This preparation script supports macOS only.'
(( $(id -u) != 0 )) || fail 2 'Do not run Prepare as root or with sudo.'
[[ "$(uname -m)" == 'arm64' ]] || fail 2 'The current IT 140 macOS implementation supports Apple silicon (arm64) only.'
command -v /usr/bin/curl >/dev/null || fail 2 'The native curl utility is unavailable.'
command -v /usr/bin/ditto >/dev/null || fail 2 'The native ditto utility is unavailable.'
command -v /usr/bin/osascript >/dev/null || fail 2 'The native osascript utility is unavailable.'
CURRENT_STAGE='Create private staging area'
TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/it140-prepare.XXXXXX")"
BACKUP_ROOT="$TEMP_ROOT/backup"
mkdir -p -- "$BACKUP_ROOT"
readonly ARCHIVE_PATH="$TEMP_ROOT/it140-main.zip"
readonly STAGE_ROOT="$TEMP_ROOT/stage"
mkdir -p -- "$STAGE_ROOT"
CURRENT_STAGE='Download approved repository archive'
attempt=1
delay=5
while (( attempt <= 5 )); do
    CACHE_BUSTER="$(date +%s)-$$-${attempt}"
    info "Downloading the approved course archive (attempt ${attempt}/5)."
    if /usr/bin/curl --fail --silent --show-error --location \
            --header 'Cache-Control: no-cache' --header 'Pragma: no-cache' \
            --connect-timeout 20 --max-time 300 \
            --output "$ARCHIVE_PATH" "${ARCHIVE_URL}?it140=${CACHE_BUSTER}"; then
        break
    fi
    rm -f -- "$ARCHIVE_PATH"
    if (( attempt == 5 )); then
        fail 4 'The approved course archive was unavailable after bounded retries.'
    fi
    sleep "$delay"
    delay=$((delay * 2))
    (( delay > 60 )) && delay=60
    attempt=$((attempt + 1))
done
CURRENT_STAGE='Extract and validate the staged package'
/usr/bin/ditto -x -k "$ARCHIVE_PATH" "$STAGE_ROOT"
SOURCE_ROOT="$(/usr/bin/find "$STAGE_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'it140-*' -print -quit)"
[[ -n "$SOURCE_ROOT" ]] || fail 5 'The downloaded archive did not contain the expected repository root.'
for action in prepare install configure verify update; do
    [[ -f "$SOURCE_ROOT/scripts/mac/${action}_it140.zsh" ]] || \
        fail 5 "The downloaded archive is missing scripts/mac/${action}_it140.zsh."
done
[[ -f "$SOURCE_ROOT/scripts/.manifest/it140_manifest.json" ]] || fail 5 'The downloaded archive is missing the controlled manifest.'
[[ -f "$SOURCE_ROOT/scripts/.manifest/it140_manifest.schema.json" ]] || fail 5 'The downloaded archive is missing the manifest schema.'
validate_json_file "$SOURCE_ROOT/scripts/.manifest/it140_manifest.json" || fail 5 'The staged manifest is not valid JSON.'
validate_json_file "$SOURCE_ROOT/scripts/.manifest/it140_manifest.schema.json" || fail 5 'The staged manifest schema is not valid JSON.'
CURRENT_STAGE='Back up current critical automation assets'
if [[ -d "$SCRIPT_ROOT/mac" ]]; then
    /usr/bin/ditto "$SCRIPT_ROOT/mac" "$BACKUP_ROOT/mac"
fi
if [[ -d "$SCRIPT_ROOT/.manifest" ]]; then
    /usr/bin/ditto "$SCRIPT_ROOT/.manifest" "$BACKUP_ROOT/manifest"
fi
CURRENT_STAGE='Refresh repository-managed package files'
CHANGED=true
if ! /usr/bin/ditto "$SOURCE_ROOT" "$COURSE_ROOT"; then
    restore_critical_assets
    fail 7 'The package overlay failed; prior critical automation assets were restored when possible.'
fi
/bin/rm -rf -- "$COURSE_ROOT/.git"
chmod -- 0755 "$SCRIPT_DIR"/*.zsh
CURRENT_STAGE='Configure the current and future user PATH'
PATH_TEMP="$TEMP_ROOT/zshrc.new"
[[ -e "$PATH_FILE" ]] || : > "$PATH_FILE"
/usr/bin/awk \
    -v start="$PATH_START" -v finish="$PATH_END" \
    -v legacy_start="$LEGACY_PATH_START" -v legacy_finish="$LEGACY_PATH_END" '
    $0 == start || $0 == legacy_start {inside=1; next}
    $0 == finish || $0 == legacy_finish {inside=0; next}
    !inside {print}
' "$PATH_FILE" > "$PATH_TEMP"
printf '\n%s\n%s\n%s\n' "$PATH_START" "$PATH_EXPORT" "$PATH_END" >> "$PATH_TEMP"
chmod -- 0600 "$PATH_TEMP"
mv -f -- "$PATH_TEMP" "$PATH_FILE"
export PATH="$COURSE_ROOT/.venv/bin:$SCRIPT_DIR:/opt/homebrew/bin:$PATH"
hash -r
CURRENT_STAGE='Post-validate installed package'
for action in prepare install configure verify update; do
    [[ -x "$SCRIPT_DIR/${action}_it140.zsh" ]] || fail 7 "${action}_it140.zsh is not executable after activation."
done
grep -Fqx "$PATH_EXPORT" "$PATH_FILE" || fail 7 'The managed macOS PATH block was not activated correctly.'
success "The current IT 140 course package is available at: $COURSE_ROOT"
finish 0 'PASS' 'Package retrieval, structural validation, activation, permissions, and PATH configuration completed.'
