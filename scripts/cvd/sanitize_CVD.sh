#!/usr/bin/env bash
# ==============================================================================
# IT 140 COURSE IDE — CVD CLEANUP
# ==============================================================================
# Repository path: scripts/cvd/sanitize_cvd.sh# Purpose: Prepare the approved Codio Virtual Desktop baseline for student use.
# Artifact version: 1.0.3
# Version date-time group: 2026-09-02-09-37
# Development status: Pilot — Active Development
# Supported platform: Codio Virtual Desktop (Ubuntu 24.04 LTS, Xfce, LightDM)
# Intended user: Standard CVD user; do not run as root or with sudo.
#
# Design:
#   * Cleanup is authorized only by exact controlled baseline fingerprints.
#   * The active default collection is resolved dynamically.
#   * The collection is unlocked only when the desktop service can do so without
#     user interaction.
#   * Managed entries are removed through the active desktop service.
#   * The existing default collection and its desktop integration are preserved.
#   * Nonmatching baseline state is preserved.
#   * Stored values are never requested, printed, or copied to the transcript.
# ==============================================================================
set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.0.3"
readonly VERSION_DTG="2026-09-02-09-37"
readonly DEVELOPMENT_STATUS="Pilot — Active Development"

readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/sanitize_cvd_$(date +%Y%m%d_%H%M%S).log"

readonly TARGET_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/keyrings"
readonly BASELINE_PATH="${TARGET_DIR}/Default_keyring.keyring"
readonly SELECTOR_PATH="${TARGET_DIR}/default"
readonly BASELINE_SHA256="215619f917288eaba6849bb5899d438a7dfb6541b4519db9f4299f83e28abb6a"
readonly SELECTOR_SHA256="4cdef49af5efb670e834e46f8c4da809a74cc0e6885c9c803de4aeb5b42d351d"

readonly BUS_DESTINATION="org.freedesktop.secrets"
readonly SERVICE_OBJECT="/org/freedesktop/secrets"
readonly SERVICE_INTERFACE="org.freedesktop.Secret.Service"
readonly PROPERTIES_INTERFACE="org.freedesktop.DBus.Properties"
readonly COLLECTION_INTERFACE="org.freedesktop.Secret.Collection"
readonly ITEM_INTERFACE="org.freedesktop.Secret.Item"

CURRENT_STAGE="initialization"
COLLECTION_OBJECT=""

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

extract_first_object_path() {
    grep -oE "objectpath '[^']+'" | head -n 1 | cut -d"'" -f2
}

resolve_default_collection() {
    CURRENT_STAGE="desktop service validation"
    local result=""
    local object_path=""

    if ! result="$(
        gdbus call             --session             --dest "$BUS_DESTINATION"             --object-path "$SERVICE_OBJECT"             --method "${SERVICE_INTERFACE}.ReadAlias"             "default"             2>/dev/null
    )"; then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi

    object_path="$(printf '%s\n' "$result" | extract_first_object_path)"

    if [[ -z "$object_path" ||
          "$object_path" == "/" ||
          "$object_path" != /org/freedesktop/secrets/collection/* ]]; then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi

    COLLECTION_OBJECT="$object_path"
}

collection_locked_state() {
    local result=""

    if ! result="$(
        gdbus call             --session             --dest "$BUS_DESTINATION"             --object-path "$COLLECTION_OBJECT"             --method "${PROPERTIES_INTERFACE}.Get"             "$COLLECTION_INTERFACE"             "Locked"             2>/dev/null
    )"; then
        return 1
    fi

    if [[ "$result" == *"<true>"* ]]; then
        printf 'locked\n'
    elif [[ "$result" == *"<false>"* ]]; then
        printf 'unlocked\n'
    else
        return 1
    fi
}

ensure_collection_ready() {
    CURRENT_STAGE="desktop service validation"
    local state=""
    local result=""

    if ! state="$(collection_locked_state)"; then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi

    if [[ "$state" == "locked" ]]; then
        if ! result="$(
            gdbus call                 --session                 --dest "$BUS_DESTINATION"                 --object-path "$SERVICE_OBJECT"                 --method "${SERVICE_INTERFACE}.Unlock"                 "[objectpath '$COLLECTION_OBJECT']"                 2>/dev/null
        )"; then
            printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
            return 1
        fi

        if [[ "$result" != *"objectpath '$COLLECTION_OBJECT'"* ||
              "$result" != *"objectpath '/'"* ]]; then
            printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
            return 1
        fi
    fi

    if ! state="$(collection_locked_state)" || [[ "$state" != "unlocked" ]]; then
        printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
        return 1
    fi
}

list_managed_items() {
    local result=""
    local escaped_collection=""

    if ! result="$(
        gdbus call             --session             --dest "$BUS_DESTINATION"             --object-path "$COLLECTION_OBJECT"             --method "${PROPERTIES_INTERFACE}.Get"             "$COLLECTION_INTERFACE"             "Items"             2>/dev/null
    )"; then
        return 1
    fi

    escaped_collection="${COLLECTION_OBJECT//\//\\/}"
    printf '%s\n' "$result" \
        | grep -oE "${escaped_collection}/[A-Za-z0-9_]+" \
        | awk '!seen[$0]++' \
        || true
}

remove_managed_items() {
    CURRENT_STAGE="cleanup"
    local item=""
    local result=""
    local items_text=""
    local -a items=()

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
        if [[ "$item" != "$COLLECTION_OBJECT/"* ]]; then
            printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
            return 1
        fi

        if ! result="$(
            gdbus call                 --session                 --dest "$BUS_DESTINATION"                 --object-path "$item"                 --method "${ITEM_INTERFACE}.Delete"                 2>/dev/null
        )"; then
            printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
            return 1
        fi

        if [[ "$result" != *"objectpath '/'"* ]]; then
            printf 'ERROR: CVD cleanup could not safely continue.\n' >&2
            return 1
        fi
    done
}

verify_cleanup() {
    CURRENT_STAGE="post-cleanup validation"
    local alias_result=""
    local alias_path=""
    local remaining_text=""
    local attempt

    for attempt in {1..20}; do
        if ! remaining_text="$(list_managed_items)"; then
            printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
            return 1
        fi
        [[ -z "$remaining_text" ]] && break
        sleep 0.1
    done

    if [[ -n "$remaining_text" ]]; then
        printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
        return 1
    fi

    if [[ ! -f "$BASELINE_PATH" || ! -f "$SELECTOR_PATH" ]]; then
        printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
        return 1
    fi

    if ! alias_result="$(
        gdbus call             --session             --dest "$BUS_DESTINATION"             --object-path "$SERVICE_OBJECT"             --method "${SERVICE_INTERFACE}.ReadAlias"             "default"             2>/dev/null
    )"; then
        printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
        return 1
    fi

    alias_path="$(printf '%s\n' "$alias_result" | extract_first_object_path)"

    if [[ "$alias_path" != "$COLLECTION_OBJECT" ]]; then
        printf 'ERROR: Expected CVD cleanup state was not achieved.\n' >&2
        return 1
    fi
}

main() {
    require_cvd_context
    start_transcript
    trap on_error ERR HUP INT TERM

    if baseline_matches; then
        resolve_default_collection
        ensure_collection_ready
        remove_managed_items
        verify_cleanup
    fi

    trap - ERR HUP INT TERM
    printf 'PASS: CVD cleaned for student use.\n'
}

main "$@"
