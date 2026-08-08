#!/usr/bin/env bash
# ==============================================================================
# IT 140 COURSE IDE — CVD CLEANUP
# ==============================================================================
# Repository path: scripts/cvd/sanitize_CVD.sh
# Purpose: Prepare the approved Codio Virtual Desktop baseline for student use.
# Artifact version: 0.1.2-alpha.1
# Version date-time group: 2026-08-07-20-47
# Development status: Alpha Testing
# Supported platform: Codio Virtual Desktop (Ubuntu 24.04 LTS, Xfce, LightDM)
# Intended user: Standard CVD user; do not run as root or with sudo.
#
# Design:
#   * Only files matching controlled SHA-256 fingerprints are altered.
#   * Each matching file receives one best-effort overwrite pass before removal.
#   * Nonmatching files are preserved.
#   * File contents are never printed or copied to the transcript.
# ==============================================================================
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.1.2-alpha.1"
readonly VERSION_DTG="2026-08-07-20-47"
readonly DEVELOPMENT_STATUS="Alpha Testing"
readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/sanitize_cvd_$(date +%Y%m%d_%H%M%S).log"
readonly TARGET_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/keyrings"
readonly PRIMARY_SHA256="215619f917288eaba6849bb5899d438a7dfb6541b4519db9f4299f83e28abb6a"
readonly SECONDARY_SHA256="4cdef49af5efb670e834e46f8c4da809a74cc0e6885c9c803de4aeb5b42d351d"
readonly SECONDARY_PATH="${TARGET_DIR}/default"
CURRENT_STAGE="initialization"
MATCH_FOUND=false

print_failure_guidance() {
    local status="$1"
    printf '\nERROR: CVD cleanup did not complete successfully.\n' >&2
    printf 'Failed stage: %s\n' "$CURRENT_STAGE" >&2
    printf 'Exit code: %s\n' "$status" >&2
    printf 'Log: %s\n' "$LOG_FILE" >&2
    printf 'Use the course CVD only after this issue has been resolved.\n' >&2
}

on_error() {
    local status=$?
    trap - ERR HUP INT TERM
    print_failure_guidance "$status"
    exit "$status"
}

sha256_of() {
    local path="$1"
    sha256sum -- "$path" | awk '{print $1}'
}

overwrite_once_and_remove() {
    local path="$1"

    # One best-effort overwrite pass followed by unlinking the file.
    shred --iterations=1 --remove=unlink -- "$path"
}

require_cvd_context() {
    CURRENT_STAGE="platform checks"

    if [[ "$(id -u)" -eq 0 ]]; then
        printf 'ERROR: Run sanitize_CVD.sh as the normal CVD user, not as root or with sudo.\n' >&2
        return 2
    fi
    if [[ "$(uname -s)" != "Linux" || ! -r /etc/os-release ]]; then
        printf 'ERROR: This cleanup supports only the approved Linux-based CVD profile.\n' >&2
        return 2
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
        printf 'ERROR: This cleanup requires the approved Ubuntu 24.04 CVD baseline.\n' >&2
        return 2
    fi
    if ! command -v xfconf-query >/dev/null 2>&1; then
        printf 'ERROR: The expected Xfce CVD environment was not detected.\n' >&2
        return 2
    fi
    command -v sha256sum >/dev/null 2>&1 || {
        printf 'ERROR: A required CVD cleanup utility is unavailable.\n' >&2
        return 1
    }
    command -v shred >/dev/null 2>&1 || {
        printf 'ERROR: A required CVD cleanup utility is unavailable.\n' >&2
        return 1
    }
}

start_transcript() {
    CURRENT_STAGE="transcript setup"
    mkdir -p "$COURSE_ROOT" "$LOG_DIR"
    chmod 700 "$LOG_DIR"
    : > "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
}

find_matching_files() {
    CURRENT_STAGE="baseline validation"
    local path digest

    [[ -d "$TARGET_DIR" ]] || return 0
    while IFS= read -r -d '' path; do
        digest="$(sha256_of "$path")"
        if [[ "$digest" == "$PRIMARY_SHA256" ]]; then
            MATCH_FOUND=true
        fi
    done < <(find "$TARGET_DIR" -maxdepth 1 -type f -print0)
}

stop_required_service() {
    CURRENT_STAGE="active service stop"
    local attempt
    local daemon_pattern='^/usr/bin/gnome-keyring-daemon( |$)'
    local -a daemon_pids=()

    mapfile -t daemon_pids < <(pgrep -u "$(id -u)" -f "$daemon_pattern" 2>/dev/null || true)
    if ((${#daemon_pids[@]} == 0)); then
        return 0
    fi

    kill -TERM "${daemon_pids[@]}" 2>/dev/null || true
    for attempt in {1..20}; do
        if ! pgrep -u "$(id -u)" -f "$daemon_pattern" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done

    mapfile -t daemon_pids < <(pgrep -u "$(id -u)" -f "$daemon_pattern" 2>/dev/null || true)
    if ((${#daemon_pids[@]} > 0)); then
        kill -KILL "${daemon_pids[@]}" 2>/dev/null || true
    fi
    sleep 0.1
    if pgrep -u "$(id -u)" -f "$daemon_pattern" >/dev/null 2>&1; then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi
}

remove_matching_files() {
    CURRENT_STAGE="cleanup"
    local path digest secondary_digest

    while IFS= read -r -d '' path; do
        digest="$(sha256_of "$path")"
        if [[ "$digest" == "$PRIMARY_SHA256" ]]; then
            overwrite_once_and_remove "$path"
        fi
    done < <(find "$TARGET_DIR" -maxdepth 1 -type f -print0)

    if [[ -f "$SECONDARY_PATH" ]]; then
        secondary_digest="$(sha256_of "$SECONDARY_PATH")"
        if [[ "$secondary_digest" == "$SECONDARY_SHA256" ]]; then
            overwrite_once_and_remove "$SECONDARY_PATH"
        fi
    fi

    chmod 700 "$TARGET_DIR"
}

verify_cleanup() {
    CURRENT_STAGE="post-cleanup validation"
    local path digest

    while IFS= read -r -d '' path; do
        digest="$(sha256_of "$path")"
        if [[ "$digest" == "$PRIMARY_SHA256" ]]; then
            printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
            return 1
        fi
    done < <(find "$TARGET_DIR" -maxdepth 1 -type f -print0)
}

main() {
    require_cvd_context
    start_transcript
    trap on_error ERR HUP INT TERM

    find_matching_files

    if [[ "$MATCH_FOUND" == true ]]; then
        stop_required_service
        remove_matching_files
        verify_cleanup
    fi

    trap - ERR HUP INT TERM
    printf 'PASS: CVD cleaned for student use.\n'
}

main "$@"
