set -euo pipefail
readonly ARTIFACT_VERSION="0.2.0"
readonly VERSION_DATE="2026-07-29"
readonly DEVELOPMENT_STATUS="Alpha Testing"
readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly ARCHIVE_URL="https://github.com/GC-STEM/it140/archive/refs/heads/main.zip"
readonly TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/it140-bootstrap.XXXXXX")"
readonly ARCHIVE_PATH="${TEMP_ROOT}/it140-main.zip"
readonly EXTRACT_ROOT="${TEMP_ROOT}/extract"
LOG_FILE=""
cleanup() {
    set +e
    [ -d "$TEMP_ROOT" ] && [ ! -L "$TEMP_ROOT" ] && rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM
if [ "$(uname -s)" != "Darwin" ]; then
    printf '[ERROR] This bootstrap supports macOS only.\n' >&2
    exit 2
fi
if [ "$(id -u)" -eq 0 ]; then
    printf '[ERROR] Do not run this bootstrap with sudo or as root.\n' >&2
    exit 3
fi
mkdir -p "$LOG_DIR"
chmod 0700 "$LOG_DIR"
LOG_FILE="${LOG_DIR}/bootstrap_mac_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
printf '\n============================================================\n'
printf 'IT 140 macOS BOOTSTRAP\n'
printf '============================================================\n'
printf '[INFO] Artifact version : %s\n' "$ARTIFACT_VERSION"
printf '[INFO] Version date     : %s\n' "$VERSION_DATE"
printf '[INFO] Status           : %s\n' "$DEVELOPMENT_STATUS"
printf '[INFO] Current user     : %s\n' "$(id -un)"
printf '[INFO] Purpose          : Retrieve the IT 140 automation package\n'
printf '[INFO] Log file         : %s\n' "$LOG_FILE"
mkdir -p "$EXTRACT_ROOT"
/usr/bin/curl --fail --location --show-error --retry 5 --retry-delay 5 \
    --connect-timeout 30 --max-time 300 \
    "$ARCHIVE_URL" --output "$ARCHIVE_PATH"
/usr/bin/ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_ROOT"
SOURCE_ROOT=""
for candidate in "$EXTRACT_ROOT"/it140-*; do
    if [ -d "$candidate" ]; then
        SOURCE_ROOT="$candidate"
        break
    fi
done
if [ -z "$SOURCE_ROOT" ] || [ ! -d "$SOURCE_ROOT/scripts/mac" ]; then
    printf '[ERROR] The downloaded repository archive does not contain scripts/mac.\n' >&2
    exit 4
fi
mkdir -p "$COURSE_ROOT"
/usr/bin/ditto "$SOURCE_ROOT" "$COURSE_ROOT"
rm -rf "$COURSE_ROOT/.git"
find "$COURSE_ROOT/scripts" -type f \( -name '*.sh' -o -name '*.command' \) -exec chmod 0755 {} +
PLATFORM_SCRIPT_DIR="$COURSE_ROOT/scripts/mac"
export PATH="$PLATFORM_SCRIPT_DIR:$PATH"
printf '[SUCCESS] The current IT 140 course package is available at:\n'
printf '[SUCCESS] %s\n' "$COURSE_ROOT"
printf '[NOTICE] The macOS lifecycle scripts are available in this Terminal session.\n'
printf '[NOTICE] Next step: run setup_mac.sh as your normal macOS user.\n'
printf '[NOTICE] Bootstrap log: %s\n' "$LOG_FILE"
