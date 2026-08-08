#!/usr/bin/env bash
# ==============================================================================
# IT 140 COURSE IDE — SANITIZE CVD
# ==============================================================================
# Repository path: scripts/cvd/sanitize_CVD.sh
# Purpose: Remove known credential artifacts inherited from a contaminated
#          Codio Virtual Desktop master without deleting user-created keyrings.
# Artifact version: 0.1.1-alpha.1
# Version date-time group: 2026-08-07-20-23
# Development status: Alpha Testing
# Supported platform: Codio Virtual Desktop (Ubuntu 24.04 LTS, Xfce, LightDM)
# Intended user: Standard CVD user; do not run as root or with sudo.
#
# Security design:
#   * A credential-bearing keyring is altered only when its SHA-256 digest
#     exactly matches the controlled fingerprint of the contaminated master.
#   * Each matching artifact receives one best-effort overwrite pass before
#     removal. This reduces recoverability from the active filesystem but does
#     not guarantee forensic erasure from virtual-disk backing stores, snapshots,
#     storage-controller layers, or provider backups.
#   * The associated default-keyring selector is sanitized only after a matching
#     contaminated keyring is found and only when the selector's own digest
#     exactly matches the controlled fingerprint.
#   * Nonmatching files in the user's keyring directory are preserved.
#   * Secret contents are never printed or copied to the transcript.
# ==============================================================================

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.1.1-alpha.1"
readonly VERSION_DTG="2026-08-07-20-23"
readonly DEVELOPMENT_STATUS="Alpha Testing"
readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/sanitize_cvd_$(date +%Y%m%d_%H%M%S).log"
readonly KEYRING_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/keyrings"
readonly CONTAMINATED_KEYRING_SHA256="215619f917288eaba6849bb5899d438a7dfb6541b4519db9f4299f83e28abb6a"
readonly CONTAMINATED_SELECTOR_SHA256="4cdef49af5efb670e834e46f8c4da809a74cc0e6885c9c803de4aeb5b42d351d"
readonly DEFAULT_SELECTOR_PATH="${KEYRING_DIR}/default"

CURRENT_STAGE="initialization"
MATCH_FOUND=false
REMOVED_COUNT=0

print_failure_guidance() {
    local status="$1"
    printf '\nERROR: CVD credential sanitization did not complete successfully.\n' >&2
    printf 'Failed stage: %s\n' "$CURRENT_STAGE" >&2
    printf 'Exit code: %s\n' "$status" >&2
    printf 'Log: %s\n' "$LOG_FILE" >&2
    printf 'Do not enter or save credentials in this CVD until the issue is resolved.\n' >&2
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

    # One overwrite pass plus unlink. On a virtualized filesystem this is a
    # best-effort reduction in recoverability, not a guarantee of secure erasure.
    shred --iterations=1 --remove=unlink -- "$path"
}

require_cvd_context() {
    CURRENT_STAGE="platform and privilege checks"

    if [[ "$(id -u)" -eq 0 ]]; then
        printf 'ERROR: Run sanitize_CVD.sh as the normal CVD user, not as root or with sudo.\n' >&2
        return 2
    fi
    if [[ "$(uname -s)" != "Linux" || ! -r /etc/os-release ]]; then
        printf 'ERROR: This sanitizer supports only the approved Linux-based CVD profile.\n' >&2
        return 2
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
        printf 'ERROR: This sanitizer requires the approved Ubuntu 24.04 CVD baseline.\n' >&2
        return 2
    fi
    if ! command -v xfconf-query >/dev/null 2>&1; then
        printf 'ERROR: The expected Xfce CVD environment was not detected.\n' >&2
        return 2
    fi
    command -v sha256sum >/dev/null 2>&1 || {
        printf 'ERROR: The required sha256sum utility is unavailable.\n' >&2
        return 1
    }
    command -v shred >/dev/null 2>&1 || {
        printf 'ERROR: The required shred utility is unavailable; refusing to remove credential artifacts without the requested overwrite pass.\n' >&2
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

    printf 'IT 140 Course IDE — Sanitize CVD\n'
    printf 'Script: sanitize_CVD.sh\n'
    printf 'Version: %s\n' "$SCRIPT_VERSION"
    printf 'Version date-time group: %s\n' "$VERSION_DTG"
    printf 'Status: %s\n' "$DEVELOPMENT_STATUS"
    printf 'User: %s\n' "$(id -un)"
    printf 'Start time: %s\n' "$(date --iso-8601=seconds)"
    printf 'Purpose: Remove only known credential artifacts inherited from the CVD master.\n'
    printf 'Sanitization method: Exact SHA-256 match, one best-effort overwrite pass, then removal.\n'
    printf 'Log: %s\n\n' "$LOG_FILE"
}

find_contaminated_keyrings() {
    CURRENT_STAGE="credential fingerprint inspection"
    local path digest

    [[ -d "$KEYRING_DIR" ]] || return 0

    while IFS= read -r -d '' path; do
        digest="$(sha256_of "$path")"
        if [[ "$digest" == "$CONTAMINATED_KEYRING_SHA256" ]]; then
            MATCH_FOUND=true
            printf 'NOTICE: Found a keyring matching the controlled contaminated-master fingerprint: %s\n' "$(basename -- "$path")"
        fi
    done < <(find "$KEYRING_DIR" -maxdepth 1 -type f -print0)
}

stop_keyring_daemon() {
    CURRENT_STAGE="GNOME Keyring shutdown"
    local attempt
    local daemon_pattern='^/usr/bin/gnome-keyring-daemon( |$)'
    local -a daemon_pids=()

    mapfile -t daemon_pids < <(pgrep -u "$(id -u)" -f "$daemon_pattern" 2>/dev/null || true)
    if ((${#daemon_pids[@]} == 0)); then
        return 0
    fi

    printf 'INFO: Stopping the current user GNOME Keyring service before sanitizing inherited credential data.\n'
    kill -TERM "${daemon_pids[@]}" 2>/dev/null || true

    for attempt in {1..20}; do
        if ! pgrep -u "$(id -u)" -f "$daemon_pattern" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done

    printf 'WARNING: GNOME Keyring did not stop after SIGTERM; forcing termination.\n'
    mapfile -t daemon_pids < <(pgrep -u "$(id -u)" -f "$daemon_pattern" 2>/dev/null || true)
    if ((${#daemon_pids[@]} > 0)); then
        kill -KILL "${daemon_pids[@]}" 2>/dev/null || true
    fi
    sleep 0.1

    if pgrep -u "$(id -u)" -f "$daemon_pattern" >/dev/null 2>&1; then
        printf 'ERROR: GNOME Keyring is still running; refusing to alter credential files.\n' >&2
        return 1
    fi
}

remove_matching_artifacts() {
    CURRENT_STAGE="matched credential artifact sanitization"
    local path digest selector_digest

    while IFS= read -r -d '' path; do
        digest="$(sha256_of "$path")"
        if [[ "$digest" == "$CONTAMINATED_KEYRING_SHA256" ]]; then
            overwrite_once_and_remove "$path"
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
            printf 'INFO: Overwrote once and removed contaminated inherited keyring: %s\n' "$(basename -- "$path")"
        fi
    done < <(find "$KEYRING_DIR" -maxdepth 1 -type f -print0)

    if [[ -f "$DEFAULT_SELECTOR_PATH" ]]; then
        selector_digest="$(sha256_of "$DEFAULT_SELECTOR_PATH")"
        if [[ "$selector_digest" == "$CONTAMINATED_SELECTOR_SHA256" ]]; then
            overwrite_once_and_remove "$DEFAULT_SELECTOR_PATH"
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
            printf 'INFO: Overwrote once and removed the matching inherited default-keyring selector.\n'
        else
            printf 'INFO: Preserved the default-keyring selector because its fingerprint does not match the contaminated master.\n'
        fi
    fi

    chmod 700 "$KEYRING_DIR"
}

verify_sanitization() {
    CURRENT_STAGE="post-sanitization verification"
    local path digest

    while IFS= read -r -d '' path; do
        digest="$(sha256_of "$path")"
        if [[ "$digest" == "$CONTAMINATED_KEYRING_SHA256" ]]; then
            printf 'ERROR: A contaminated keyring fingerprint remains after sanitization: %s\n' "$(basename -- "$path")" >&2
            return 1
        fi
    done < <(find "$KEYRING_DIR" -maxdepth 1 -type f -print0)
}

main() {
    require_cvd_context
    start_transcript
    trap on_error ERR HUP INT TERM

    find_contaminated_keyrings

    if [[ "$MATCH_FOUND" != true ]]; then
        trap - ERR HUP INT TERM
        printf 'PASS: No keyring matched the controlled contaminated-master fingerprint; no credential files were changed.\n'
        printf 'Log: %s\n' "$LOG_FILE"
        return 0
    fi

    stop_keyring_daemon
    remove_matching_artifacts
    verify_sanitization

    trap - ERR HUP INT TERM
    printf '\nPASS: Inherited CVD credential artifacts were sanitized.\n'
    printf 'Artifacts sanitized and removed: %d\n' "$REMOVED_COUNT"
    printf 'Nonmatching keyring files were preserved.\n'
    printf 'NOTE: The overwrite is best-effort and does not guarantee erasure from virtual-disk snapshots, backing stores, or provider backups.\n'
    printf 'Log: %s\n' "$LOG_FILE"
}

main "$@"
