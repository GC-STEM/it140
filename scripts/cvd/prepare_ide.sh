#!/usr/bin/env bash
# ==============================================================================
# IT 140 COURSE IDE — PREPARE (CVD)
# ==============================================================================
# Repository path: scripts/cvd/prepare_ide.sh
# Purpose: Acquire or refresh the IT 140 automation package without requiring
#          Git, the course manifest, or another lifecycle script.
# Artifact version: 0.5.0
# Version date-time group: 2026-08-01-11-06
# Development status: Alpha Testing
# Supported platform: Codio Virtual Desktop (Ubuntu 24.04 LTS XFCE)
# Intended user: Standard CVD user; do not run as root or with sudo.
#
# FIRST-USE BOOTSTRAP COMMAND SET
# Copy only the commands between the BEGIN and END labels into the applicable
# README. The command section intentionally contains no comments or blank lines.
# When this installed artifact is executed normally, the guarded bootstrap
# section is skipped and the direct refresh implementation below is used.
# ==============================================================================

if [[ "${IT140_PREPARE_MODE:-refresh}" == "bootstrap" ]]; then
# ----- BEGIN COPYABLE BOOTSTRAP COMMAND SET -----
(
set -Eeuo pipefail
version="0.5.0"
version_dtg="2026-08-01-11-06"
course_root="$HOME/it140"
log_dir="$course_root/logs"
archive_url="https://github.com/GC-STEM/it140/archive/refs/heads/main.tar.gz"
mkdir -p "$course_root" "$log_dir"
chmod 700 "$log_dir"
log_path="$log_dir/prepare_ide_$(date +%Y%m%d_%H%M%S).log"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/it140-prepare.XXXXXX")"
cleanup() { rm -rf -- "$temp_root"; }
failed() { status=$?; printf 'ERROR: Preparation did not complete. Review: %s\n' "$log_path"; cleanup; exit "$status"; }
trap failed ERR HUP INT TERM
exec > >(tee -a "$log_path") 2>&1
printf 'IT 140 Course IDE Prepare %s (%s)\n' "$version" "$version_dtg"
printf 'User: %s\nPurpose: Acquire or refresh the course automation package.\nLog: %s\n' "$(id -un)" "$log_path"
[[ "$(id -u)" -ne 0 ]]
[[ "$(uname -s)" == "Linux" ]]
command -v curl >/dev/null
command -v tar >/dev/null
archive_path="$temp_root/it140-main.tar.gz"
stage_root="$temp_root/stage"
mkdir -p "$stage_root"
curl --fail --silent --show-error --location --retry 4 --retry-delay 2 --connect-timeout 20 --max-time 180 --output "$archive_path" "$archive_url"
tar -xzf "$archive_path" -C "$stage_root"
source_root="$(find "$stage_root" -mindepth 1 -maxdepth 1 -type d -name 'it140-*' -print -quit)"
[[ -n "$source_root" ]]
for script in prepare install configure verify update; do [[ -f "$source_root/scripts/cvd/${script}_ide.sh" ]]; done
cp -a "$source_root/." "$course_root/"
rm -rf -- "$course_root/.git"
chmod +x "$course_root/scripts/cvd/"*.sh
path_line='export PATH="$HOME/it140/scripts/cvd:$PATH"'
touch "$HOME/.bashrc"
grep -qxF "$path_line" "$HOME/.bashrc" || printf '\n%s\n' "$path_line" >> "$HOME/.bashrc"
export PATH="$course_root/scripts/cvd:$PATH"
hash -r
trap - ERR HUP INT TERM
cleanup
printf 'SUCCESS: The IT 140 automation package is ready.\nNext step: update_ide.sh\nLog: %s\n' "$log_path"
)
# ----- END COPYABLE BOOTSTRAP COMMAND SET -----
exit $?
fi

# ==============================================================================
# DIRECT REFRESH / REPAIR IMPLEMENTATION
# ==============================================================================

set -Eeuo pipefail

readonly SCRIPT_VERSION="0.5.0"
readonly VERSION_DTG="2026-08-01-11-06"
readonly DEVELOPMENT_STATUS="Alpha Testing"
readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly SCRIPT_DIR="${COURSE_ROOT}/scripts/cvd"
readonly ARCHIVE_URL="https://github.com/GC-STEM/it140/archive/refs/heads/main.tar.gz"
readonly PATH_LINE='export PATH="$HOME/it140/scripts/cvd:$PATH"'

LOG_PATH=""
TEMP_ROOT=""
CURRENT_STAGE="initialization"

cleanup() {
    if [[ -n "${TEMP_ROOT:-}" && -d "$TEMP_ROOT" ]]; then
        rm -rf -- "$TEMP_ROOT"
    fi
}

print_failure_guidance() {
    local status="$1"
    printf '\nERROR: Prepare did not complete successfully.\n'
    printf 'Failed stage: %s\n' "$CURRENT_STAGE"
    printf 'Exit code: %s\n' "$status"
    if [[ -n "${LOG_PATH:-}" ]]; then
        printf 'Log: %s\n' "$LOG_PATH"
    fi
    printf 'This issue affects the CVD preparation process. Retry Prepare once.\n'
    printf 'If it fails again, provide the log to your instructor or university technical support.\n'
}

on_error() {
    local status=$?
    trap - ERR HUP INT TERM
    print_failure_guidance "$status"
    cleanup
    exit "$status"
}

require_standard_cvd_user() {
    CURRENT_STAGE="platform and privilege checks"

    if [[ "$(id -u)" -eq 0 ]]; then
        printf 'ERROR: Run prepare_ide.sh as the normal CVD user, not as root or with sudo.\n' >&2
        return 3
    fi

    if [[ "$(uname -s)" != "Linux" ]]; then
        printf 'ERROR: This prepare script supports only the Linux-based CVD profile.\n' >&2
        return 4
    fi

    if [[ ! -r /etc/os-release ]]; then
        printf 'ERROR: The operating-system release could not be identified.\n' >&2
        return 4
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        printf 'ERROR: This prepare script requires the approved Ubuntu CVD baseline.\n' >&2
        return 4
    fi

    case "$(uname -m)" in
        x86_64|amd64) ;;
        *)
            printf 'ERROR: Unsupported processor architecture: %s\n' "$(uname -m)" >&2
            return 4
            ;;
    esac

    command -v curl >/dev/null 2>&1 || {
        printf 'ERROR: The baseline curl utility is unavailable.\n' >&2
        return 5
    }
    command -v tar >/dev/null 2>&1 || {
        printf 'ERROR: The baseline tar utility is unavailable.\n' >&2
        return 5
    }
}

start_transcript() {
    CURRENT_STAGE="transcript setup"
    mkdir -p "$COURSE_ROOT" "$LOG_DIR"
    chmod 700 "$LOG_DIR"
    LOG_PATH="$LOG_DIR/prepare_ide_$(date +%Y%m%d_%H%M%S).log"
    : > "$LOG_PATH"
    chmod 600 "$LOG_PATH"
    exec > >(tee -a "$LOG_PATH") 2>&1

    printf 'IT 140 Course IDE — Prepare\n'
    printf 'Script: prepare_ide.sh\n'
    printf 'Version: %s\n' "$SCRIPT_VERSION"
    printf 'Version date-time group: %s\n' "$VERSION_DTG"
    printf 'Status: %s\n' "$DEVELOPMENT_STATUS"
    printf 'Platform: Codio Virtual Desktop (Ubuntu)\n'
    printf 'User: %s\n' "$(id -un)"
    printf 'Start time: %s\n' "$(date --iso-8601=seconds)"
    printf 'Purpose: Refresh or repair the local IT 140 automation package.\n'
    printf 'Log: %s\n\n' "$LOG_PATH"
}

create_staging_area() {
    CURRENT_STAGE="temporary staging setup"
    TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/it140-prepare.XXXXXX")"
}

download_archive() {
    CURRENT_STAGE="repository archive download"
    local archive_path="$TEMP_ROOT/it140-main.tar.gz"

    printf 'INFO: Downloading the authorized course repository archive.\n'
    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 4 \
        --retry-delay 2 \
        --connect-timeout 20 \
        --max-time 180 \
        --output "$archive_path" \
        "$ARCHIVE_URL"
}

extract_and_validate_archive() {
    CURRENT_STAGE="archive extraction and structural validation"
    local archive_path="$TEMP_ROOT/it140-main.tar.gz"
    local stage_root="$TEMP_ROOT/stage"
    local source_root
    local script

    mkdir -p "$stage_root"
    tar -xzf "$archive_path" -C "$stage_root"
    source_root="$(find "$stage_root" -mindepth 1 -maxdepth 1 -type d -name 'it140-*' -print -quit)"

    if [[ -z "$source_root" ]]; then
        printf 'ERROR: The downloaded archive has an unexpected top-level structure.\n' >&2
        return 6
    fi

    for script in prepare install configure verify update; do
        if [[ ! -f "$source_root/scripts/cvd/${script}_ide.sh" ]]; then
            printf 'ERROR: The archive is missing scripts/cvd/%s_ide.sh.\n' "$script" >&2
            return 6
        fi
    done

    printf '%s\n' "$source_root" > "$TEMP_ROOT/source-root.txt"
}

refresh_managed_package() {
    CURRENT_STAGE="course package refresh"
    local source_root

    source_root="$(cat "$TEMP_ROOT/source-root.txt")"
    printf 'INFO: Refreshing repository-managed files without deleting unmatched user files.\n'
    cp -a "$source_root/." "$COURSE_ROOT/"

    # The course root is a deployed package, not a working clone. This removes
    # only top-level repository metadata and does not inspect nested repositories.
    rm -rf -- "$COURSE_ROOT/.git"
}

activate_scripts_and_path() {
    CURRENT_STAGE="script permissions and PATH activation"

    chmod +x "$SCRIPT_DIR/"*.sh
    touch "$HOME/.bashrc"
    if ! grep -qxF "$PATH_LINE" "$HOME/.bashrc"; then
        printf '\n%s\n' "$PATH_LINE" >> "$HOME/.bashrc"
        printf 'INFO: Added the CVD lifecycle script directory to ~/.bashrc.\n'
    else
        printf 'INFO: The persistent CVD script PATH entry is already present.\n'
    fi

    case ":$PATH:" in
        *":$SCRIPT_DIR:"*) ;;
        *) export PATH="$SCRIPT_DIR:$PATH" ;;
    esac
    hash -r
}

main() {
    require_standard_cvd_user
    start_transcript
    trap on_error ERR HUP INT TERM

    create_staging_area
    download_archive
    extract_and_validate_archive
    refresh_managed_package
    activate_scripts_and_path

    CURRENT_STAGE="cleanup"
    cleanup
    trap - ERR HUP INT TERM

    printf '\nSUCCESS: The IT 140 automation package is ready.\n'
    printf 'Course root: %s\n' "$COURSE_ROOT"
    printf 'Workflow: Continue with the applicable CVD initialization workflow.\n'
    printf 'Starting state: CVD provider baseline or IT 140 course master.\n'
    printf 'Operating role: CVD administrator or CVD student.\n'
    printf 'Log: %s\n' "$LOG_PATH"
    printf 'Next step: update_ide.sh\n'
}

main "$@"
