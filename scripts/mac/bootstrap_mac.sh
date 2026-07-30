set -euo pipefail
readonly ARTIFACT_VERSION="0.5.1"
readonly VERSION_DATE="2026-07-30"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_DIR="${COURSE_ROOT}/scripts/mac"
readonly ARCHIVE_URL="https://github.com/GC-STEM/it140/archive/refs/heads/main.zip"
readonly TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/it140-bootstrap.XXXXXX")"
readonly ARCHIVE_PATH="${TEMP_ROOT}/it140-main.zip"
readonly EXTRACT_ROOT="${TEMP_ROOT}/extract"
cleanup() {
    set +e
    [ -d "$TEMP_ROOT" ] && [ ! -L "$TEMP_ROOT" ] && rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM
[ "$(uname -s)" = "Darwin" ] || {
    printf '[ERROR] This bootstrap supports macOS only.\n' >&2
    exit 2
}
[ "$(id -u)" -ne 0 ] || {
    printf '[ERROR] Do not run this bootstrap with sudo or as root.\n' >&2
    exit 3
}
mkdir -p -- "$COURSE_ROOT/logs" "$EXTRACT_ROOT"
chmod 0700 -- "$COURSE_ROOT/logs"
LOG_FILE="$COURSE_ROOT/logs/bootstrap_mac_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
printf '\n============================================================\n'
printf 'IT 140 macOS BOOTSTRAP\n'
printf '============================================================\n'
printf '[INFO] Artifact version : %s\n' "$ARTIFACT_VERSION"
printf '[INFO] Version date     : %s\n' "$VERSION_DATE"
printf '[INFO] Current user     : %s\n' "$(id -un)"
printf '[INFO] Log file         : %s\n' "$LOG_FILE"
/usr/bin/curl --fail --location --show-error --retry 5 --retry-delay 5 \
    "$ARCHIVE_URL" --output "$ARCHIVE_PATH"
/usr/bin/ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_ROOT"
SOURCE_ROOT=""
for candidate in "$EXTRACT_ROOT"/it140-*; do
    [ -f "$candidate/scripts/mac/setup_mac.sh" ] && SOURCE_ROOT="$candidate" && break
done
[ -n "$SOURCE_ROOT" ] || {
    printf '[ERROR] The downloaded archive does not contain setup_mac.sh.\n' >&2
    exit 4
}
/usr/bin/ditto "$SOURCE_ROOT" "$COURSE_ROOT"
rm -rf -- "$COURSE_ROOT/.git"
rm -f -- "$SCRIPT_DIR/_mac_common.sh"
chmod 0755 -- "$SCRIPT_DIR"/*.sh
printf '[SUCCESS] The current IT 140 course package is available at:\n'
printf '[SUCCESS] %s\n' "$COURSE_ROOT"
printf '[NOTICE] Next step: cd ~/it140/scripts/mac && ./setup_mac.sh\n'
printf '[NOTICE] Bootstrap log: %s\n' "$LOG_FILE"
