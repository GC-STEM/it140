#!/usr/bin/env bash
# ==============================================================================
# IT 140 COURSE IDE — CVD CLEANUP
# ==============================================================================
# Repository path: scripts/cvd/sanitize_CVD.sh
# Purpose: Prepare the approved Codio Virtual Desktop baseline for student use.
# Artifact version: 0.2.0-alpha.1
# Version date-time group: 2026-08-07-21-37
# Development status: Alpha Testing
# Supported platform: Codio Virtual Desktop (Ubuntu 24.04 LTS, Xfce, LightDM)
# Intended user: Standard CVD user; do not run as root or with sudo.
#
# Design:
#   * Cleanup is authorized only by exact controlled baseline fingerprints.
#   * Managed entries are removed through the active desktop service.
#   * The existing default collection and its desktop integration are preserved.
#   * Nonmatching baseline state is preserved.
#   * Stored values are never requested, printed, or copied to the transcript.
# ==============================================================================
set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.2.0-alpha.1"
readonly VERSION_DTG="2026-08-07-21-37"
readonly DEVELOPMENT_STATUS="Alpha Testing"

readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/sanitize_cvd_$(date +%Y%m%d_%H%M%S).log"

readonly TARGET_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/keyrings"
readonly BASELINE_PATH="${TARGET_DIR}/Default_keyring.keyring"
readonly SELECTOR_PATH="${TARGET_DIR}/default"
readonly BASELINE_SHA256="215619f917288eaba6849bb5899d438a7dfb6541b4519db9f4299f83e28abb6a"
readonly SELECTOR_SHA256="4cdef49af5efb670e834e46f8c4da809a74cc0e6885c9c803de4aeb5b42d351d"

readonly BUS_DESTINATION="org.freedesktop.secrets"
readonly DEFAULT_OBJECT="/org/freedesktop/secrets/aliases/default"
readonly PROPERTIES_INTERFACE="org.freedesktop.DBus.Properties"
readonly COLLECTION_INTERFACE="org.freedesktop.Secret.Collection"
readonly ITEM_INTERFACE="org.freedesktop.Secret.Item"

CURRENT_STAGE="initialization"

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

    command -v gdbus >/dev/null 2>&1 || {
        printf 'ERROR: A required CVD cleanup utility is unavailable.\n' >&2
        return 1
    }

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        printf 'ERROR: The active desktop session is unavailable.\n' >&2
        return 1
    fi
}

start_transcript() {
    CURRENT_STAGE="transcript setup"

    mkdir -p "$COURSE_ROOT" "$LOG_DIR"
    chmod 700 "$LOG_DIR"
    : > "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
}

baseline_matches() {
    CURRENT_STAGE="baseline validation"

    local baseline_digest
    local selector_digest

    [[ -f "$BASELINE_PATH" && -f "$SELECTOR_PATH" ]] || return 1

    baseline_digest="$(sha256_of "$BASELINE_PATH")"
    selector_digest="$(sha256_of "$SELECTOR_PATH")"

    [[ "$baseline_digest" == "$BASELINE_SHA256" &&
       "$selector_digest" == "$SELECTOR_SHA256" ]]
}

collection_is_ready() {
    CURRENT_STAGE="desktop service validation"

    local result=""

    if ! result="$(
        gdbus call \
            --session \
            --dest "$BUS_DESTINATION" \
            --object-path "$DEFAULT_OBJECT" \
            --method "${PROPERTIES_INTERFACE}.Get" \
            "$COLLECTION_INTERFACE" \
            "Locked" \
            2>/dev/null
    )"; then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi

    if [[ "$result" != *"<false>"* ]]; then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi
}

list_managed_items() {
    local result=""

    if ! result="$(
        gdbus call \
            --session \
            --dest "$BUS_DESTINATION" \
            --object-path "$DEFAULT_OBJECT" \
            --method "${PROPERTIES_INTERFACE}.Get" \
            "$COLLECTION_INTERFACE" \
            "Items" \
            2>/dev/null
    )"; then
        return 1
    fi

    printf '%s\n' "$result" \
        | grep -oE '/org/freedesktop/secrets/(collection|aliases)/[A-Za-z0-9_/]+' \
        | awk '!seen[$0]++' \
        || true
}

remove_managed_items() {
    CURRENT_STAGE="cleanup"

    local item=""
    local -a items=()

    local items_text=""

    if ! items_text="$(list_managed_items)"; then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi

    if [[ -n "$items_text" ]]; then
        mapfile -t items <<< "$items_text"
    fi

    if ((${#items[@]} == 0)); then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi

    for item in "${items[@]}"; do
        if [[ "$item" != /org/freedesktop/secrets/collection/* &&
              "$item" != /org/freedesktop/secrets/aliases/default/* ]]; then
            printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
            return 1
        fi

        if ! gdbus call \
            --session \
            --dest "$BUS_DESTINATION" \
            --object-path "$item" \
            --method "${ITEM_INTERFACE}.Delete" \
            >/dev/null 2>&1; then
            printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
            return 1
        fi
    done
}

verify_cleanup() {
    CURRENT_STAGE="post-cleanup validation"

    local item=""
    local -a remaining=()

    local remaining_text=""

    if ! remaining_text="$(list_managed_items)"; then
        printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
        return 1
    fi

    if [[ -n "$remaining_text" ]]; then
        mapfile -t remaining <<< "$remaining_text"
    fi

    for item in "${remaining[@]}"; do
        if [[ -n "$item" ]]; then
            printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
            return 1
        fi
    done

    if [[ ! -f "$BASELINE_PATH" || ! -f "$SELECTOR_PATH" ]]; then
        printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
        return 1
    fi

    if [[ "$(sha256_of "$BASELINE_PATH")" == "$BASELINE_SHA256" ]]; then
        printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
        return 1
    fi
}

main() {
    require_cvd_context
    start_transcript
    trap on_error ERR HUP INT TERM

    if baseline_matches; then
        collection_is_ready
        remove_managed_items
        verify_cleanup
    fi

    trap - ERR HUP INT TERM
    printf 'PASS: CVD cleaned for student use.\n'
}

main "$@"
