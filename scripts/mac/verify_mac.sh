#!/bin/zsh
set -euo pipefail

readonly IT140_SCRIPT_VERSION="0.5.1"
readonly IT140_VERSION_DATE="2026-07-30"
readonly IT140_DEVELOPMENT_STATUS="Alpha Testing — Rebuilt Baseline"
readonly IT140_ACTION_ID="verify"
readonly IT140_USAGE="Usage: verify_mac.sh [--help] [--version] [--noninteractive] [--profile macos_bare_metal]"

typeset -g IT140_NONINTERACTIVE=0
typeset -g IT140_REQUESTED_PROFILE="macos_bare_metal"

show_help() {
    cat <<'HELP'
Verify the complete IT 140 course IDE without changing managed configuration.

Usage: verify_mac.sh [--help] [--version] [--noninteractive] [--profile macos_bare_metal]

Options:
  --help                 Show this help.
  --version              Show artifact metadata.
  --noninteractive       Do not open authentication or installer prompts.
  --profile PROFILE_ID   Must be macos_bare_metal.
HELP
}

readonly IT140_PLATFORM_ID="macos"
readonly IT140_PLATFORM_ABBREVIATION="mac"
readonly IT140_DEPLOYMENT_PROFILE="macos_bare_metal"
readonly IT140_COURSE_ROOT="${HOME}/it140"
readonly IT140_SCRIPT_ROOT="${IT140_COURSE_ROOT}/scripts"
readonly IT140_PLATFORM_SCRIPT_DIR="${IT140_SCRIPT_ROOT}/mac"
readonly IT140_MANIFEST_PATH="${IT140_SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly IT140_SCHEMA_PATH="${IT140_SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly IT140_LOG_DIR="${IT140_COURSE_ROOT}/logs"
readonly IT140_LOCK_PARENT="${HOME}/Library/Caches"
readonly IT140_LOCK_DIR="${IT140_LOCK_PARENT}/it140-mac-mutation.lock"
readonly IT140_REPOSITORY_URL="https://github.com/GC-STEM/it140"
readonly IT140_ARCHIVE_BASE="https://github.com/GC-STEM/it140/archive/refs/heads/main.zip"
readonly IT140_HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
readonly IT140_HOMEBREW_BIN="/opt/homebrew/bin/brew"
readonly IT140_PYTHON_BIN="/opt/homebrew/opt/python@3.12/bin/python3.12"
readonly IT140_CODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
readonly IT140_VENV_DIR="${IT140_COURSE_ROOT}/.venv"
readonly IT140_VENV_PYTHON="${IT140_VENV_DIR}/bin/python"
readonly IT140_DESKTOP_DIR="${HOME}/Desktop"
readonly IT140_COURSE_DESKTOP_LINK="${IT140_DESKTOP_DIR}/IT 140"
readonly IT140_VSCODE_DESKTOP_APP="${IT140_DESKTOP_DIR}/Visual Studio Code - IT 140.app"
readonly IT140_MANAGED_ENV_START="# >>> IT 140 managed environment >>>"
readonly IT140_MANAGED_ENV_END="# <<< IT 140 managed environment <<<"

typeset -g IT140_LOG_FILE=""
typeset -g IT140_LAST_COMMAND=""
typeset -g IT140_TEMP_ROOT=""
typeset -g IT140_TRANSACTION_ROOT=""
typeset -gi IT140_LOCK_HELD=0
typeset -gi IT140_TRANSACTION_ACTIVE=0
typeset -gi IT140_ERROR_ACTIVE=0
typeset -gi IT140_CHANGED=0
typeset -gi IT140_WARNINGS=0
typeset -gi IT140_FAILURES=0
typeset -gi IT140_PARTIAL=0
typeset -g IT140_START_EPOCH="$(date +%s)"

it140_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}
it140_info() { printf '[INFO] %s\n' "$1"; }
it140_success() { printf '[SUCCESS] %s\n' "$1"; }
it140_notice() { printf '[NOTICE] %s\n' "$1"; }
it140_warning() { IT140_WARNINGS=$((IT140_WARNINGS + 1)); printf '[WARNING] %s\n' "$1"; }
it140_error() { printf '[ERROR] %s\n' "$1" >&2; }

it140_print_version() {
    printf 'Script version   : %s\n' "$IT140_SCRIPT_VERSION"
    printf 'Version date     : %s\n' "$IT140_VERSION_DATE"
    printf 'Status           : %s\n' "$IT140_DEVELOPMENT_STATUS"
}

it140_remove_path_safely() {
    local target="${1:-}"
    [ -n "$target" ] || return 0
    case "$target" in
        "${TMPDIR:-/tmp}"/it140-*|"$IT140_COURSE_ROOT"/scripts/.it140-transaction.*)
            [ -L "$target" ] && return 1
            [ -e "$target" ] && rm -rf -- "$target"
            ;;
        *) return 1 ;;
    esac
}

it140_rollback_transaction() {
    [ "$IT140_TRANSACTION_ACTIVE" -eq 1 ] || return 0
    [ -n "$IT140_TRANSACTION_ROOT" ] || return 0
    [ -d "$IT140_TRANSACTION_ROOT/backups" ] || return 0
    local record destination backup state
    while IFS=$'\t' read -r destination backup state; do
        [ -n "$destination" ] || continue
        if [ "$state" = "present" ] && [ -f "$backup" ]; then
            mkdir -p -- "$(dirname -- "$destination")"
            cp -p -- "$backup" "$destination"
        elif [ "$state" = "absent" ]; then
            rm -f -- "$destination"
        fi
    done < "$IT140_TRANSACTION_ROOT/records.tsv"
    IT140_TRANSACTION_ACTIVE=0
    it140_notice "Rolled back the interrupted managed-asset activation."
}

it140_release_lock() {
    if [ "$IT140_LOCK_HELD" -eq 1 ]; then
        if [ -d "$IT140_LOCK_DIR" ] && [ ! -L "$IT140_LOCK_DIR" ]; then
            local owner_pid=""
            [ -r "$IT140_LOCK_DIR/pid" ] && owner_pid="$(<"$IT140_LOCK_DIR/pid")"
            if [ "$owner_pid" = "$$" ]; then
                rm -rf -- "$IT140_LOCK_DIR"
            fi
        fi
        IT140_LOCK_HELD=0
    fi
}

it140_cleanup() {
    set +e
    it140_rollback_transaction
    it140_release_lock
    [ -n "$IT140_TEMP_ROOT" ] && it140_remove_path_safely "$IT140_TEMP_ROOT"
    [ -n "$IT140_TRANSACTION_ROOT" ] && it140_remove_path_safely "$IT140_TRANSACTION_ROOT"
}

it140_handle_error() {
    local exit_code="${1:-1}"
    local line_number="${2:-unknown}"
    local failed_command="${3:-unknown}"
    [ "$IT140_ERROR_ACTIVE" -eq 0 ] || return "$exit_code"
    IT140_ERROR_ACTIVE=1
    set +e
    it140_error "Unexpected failure near line $line_number."
    it140_error "Command: $failed_command"
    it140_error "Exit code: $exit_code"
    if [ -n "$IT140_LOG_FILE" ]; then
        it140_error "Log file: $IT140_LOG_FILE"
    else
        it140_error "Log file: not initialized"
    fi
    it140_cleanup
    trap - DEBUG ZERR INT TERM EXIT
    exit "$exit_code"
}

it140_handle_signal() {
    local exit_code="$1"
    local signal_name="$2"
    set +e
    it140_error "Interrupted by $signal_name."
    [ -n "$IT140_LOG_FILE" ] && it140_error "Log file: $IT140_LOG_FILE"
    it140_cleanup
    trap - DEBUG ZERR INT TERM EXIT
    exit "$exit_code"
}

it140_install_traps() {
    # This function is called before EXIT is installed. Installing EXIT inside
    # a zsh function would make it run when this function returns.
    trap 'IT140_LAST_COMMAND=$ZSH_DEBUG_CMD' DEBUG
    trap 'it140_handle_error "$?" "$LINENO" "${IT140_LAST_COMMAND:-unknown}"' ZERR
    trap 'it140_handle_signal 130 INT' INT
    trap 'it140_handle_signal 143 TERM' TERM
}



it140_write_managed_environment_block() {
    local target="$1"
    local temp
    mkdir -p -- "$(dirname -- "$target")"
    temp="$(mktemp "${TMPDIR:-/tmp}/it140-shell.XXXXXX")"
    if [ -f "$target" ]; then
        awk -v start="$IT140_MANAGED_ENV_START" -v finish="$IT140_MANAGED_ENV_END" '
            $0 == start {inside=1; next}
            $0 == finish {inside=0; next}
            !inside {print}
        ' "$target" > "$temp"
    fi
    cat >> "$temp" <<'ENV'

# >>> IT 140 managed environment >>>
export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
# <<< IT 140 managed environment <<<
ENV
    mv -- "$temp" "$target"
    chmod 0600 -- "$target"
}

it140_initialize_log() {
    mkdir -p -- "$IT140_LOG_DIR"
    chmod 0700 -- "$IT140_LOG_DIR"
    IT140_LOG_FILE="${IT140_LOG_DIR}/${IT140_ACTION_ID}_mac_$(date +%Y%m%d_%H%M%S).log"
    : > "$IT140_LOG_FILE"
    chmod 0600 -- "$IT140_LOG_FILE"
    exec > >(tee -a "$IT140_LOG_FILE") 2>&1
}

it140_prune_logs() {
    [ -d "$IT140_LOG_DIR" ] || return 0
    find "$IT140_LOG_DIR" -type f -name '*.log' -mtime +180 -delete 2>/dev/null || true
    /bin/ls -1t "$IT140_LOG_DIR"/*.log 2>/dev/null | /usr/bin/tail -n +51 | while IFS= read -r old_log; do
        [ -n "$old_log" ] && rm -f -- "$old_log"
    done
}

it140_fail() {
    local exit_code="$1"
    shift
    it140_error "$*"
    [ -n "$IT140_LOG_FILE" ] && it140_error "Log file: $IT140_LOG_FILE"
    exit "$exit_code"
}

it140_check_platform_user() {
    [ "$(uname -s)" = "Darwin" ] || it140_fail 2 "This script supports macOS only."
    [ "$(id -u)" -ne 0 ] || it140_fail 3 "Do not run this script with sudo or as root."
    local architecture
    architecture="$(uname -m)"
    [ "$architecture" = "arm64" ] || it140_fail 2 "This rebuilt baseline supports Apple silicon only. Detected architecture: $architecture"
}

it140_acquire_lock() {
    mkdir -p -- "$IT140_LOCK_PARENT"
    chmod 0700 -- "$IT140_LOCK_PARENT" 2>/dev/null || true
    if [ -L "$IT140_LOCK_DIR" ]; then
        it140_fail 5 "The mutation lock path is a symbolic link and was not trusted: $IT140_LOCK_DIR"
    fi
    if [ -d "$IT140_LOCK_DIR" ]; then
        local prior_pid="" prior_action="unknown"
        [ -r "$IT140_LOCK_DIR/pid" ] && prior_pid="$(<"$IT140_LOCK_DIR/pid")"
        [ -r "$IT140_LOCK_DIR/action" ] && prior_action="$(<"$IT140_LOCK_DIR/action")"
        if printf '%s\n' "$prior_pid" | grep -Eq '^[0-9]+$' && kill -0 "$prior_pid" 2>/dev/null; then
            it140_fail 7 "Another IT 140 $prior_action operation is running with process ID $prior_pid."
        fi
        it140_notice "Recovered a stale IT 140 operation lock${prior_pid:+ from process ID $prior_pid}."
        rm -rf -- "$IT140_LOCK_DIR"
    elif [ -e "$IT140_LOCK_DIR" ]; then
        it140_fail 5 "The mutation lock path exists but is not a directory: $IT140_LOCK_DIR"
    fi
    if ! mkdir -- "$IT140_LOCK_DIR"; then
        it140_fail 7 "Another IT 140 setup, configuration, or update operation started at the same time."
    fi
    printf '%s\n' "$$" > "$IT140_LOCK_DIR/pid"
    printf '%s\n' "$IT140_ACTION_ID" > "$IT140_LOCK_DIR/action"
    printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$IT140_LOCK_DIR/started_utc"
    chmod 0700 -- "$IT140_LOCK_DIR"
    IT140_LOCK_HELD=1
}

it140_json_validate() {
    local manifest_file="${1:-$IT140_MANIFEST_PATH}"
    local schema_file="${2:-$IT140_SCHEMA_PATH}"
    local product_version="$(/usr/bin/sw_vers -productVersion)"
    local output
    if ! output="$(env \
        IT140_JXA_MANIFEST_FILE="$manifest_file" \
        IT140_JXA_SCHEMA_FILE="$schema_file" \
        IT140_JXA_PRODUCT_VERSION="$product_version" \
        /usr/bin/osascript -l JavaScript <<'JXA' 2>&1
ObjC.import('Foundation');
function env(name) {
    var value = $.NSProcessInfo.processInfo.environment.objectForKey(name);
    if (!value) throw new Error('Missing environment value: ' + name);
    return ObjC.unwrap(value);
}
function readUtf8(path) {
    var data = $.NSData.dataWithContentsOfFile($(path).stringByStandardizingPath);
    if (!data) throw new Error('Unable to read: ' + path);
    var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (!text) throw new Error('File is not valid UTF-8: ' + path);
    return ObjC.unwrap(text);
}
function rejectDuplicateObjectKeys(text) {
    var index = 0;
    function fail(message) { throw new Error(message + ' at character ' + index); }
    function skipWhitespace() { while (index < text.length && /[\t\n\r ]/.test(text[index])) index += 1; }
    function parseString() {
        var start = index;
        if (text[index] !== '"') fail('Expected a JSON string');
        index += 1;
        while (index < text.length) {
            var ch = text[index];
            if (ch === '"') {
                index += 1;
                return JSON.parse(text.slice(start, index));
            }
            if (ch === '\\') {
                index += 1;
                if (index >= text.length) fail('Unterminated JSON escape');
                if (text[index] === 'u') {
                    if (!/^[0-9A-Fa-f]{4}$/.test(text.slice(index + 1, index + 5))) fail('Invalid JSON Unicode escape');
                    index += 5;
                } else {
                    if ('"\\\\/bfnrt'.indexOf(text[index]) < 0) fail('Invalid JSON escape');
                    index += 1;
                }
                continue;
            }
            if (text.charCodeAt(index) < 0x20) fail('Unescaped control character in JSON string');
            index += 1;
        }
        fail('Unterminated JSON string');
    }
    function parseNumber() {
        var match = text.slice(index).match(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/);
        if (!match) fail('Invalid JSON number');
        index += match[0].length;
    }
    function parseLiteral(literal) {
        if (text.slice(index, index + literal.length) !== literal) fail('Invalid JSON literal');
        index += literal.length;
    }
    function parseArray() {
        index += 1;
        skipWhitespace();
        if (text[index] === ']') { index += 1; return; }
        while (true) {
            parseValue();
            skipWhitespace();
            if (text[index] === ']') { index += 1; return; }
            if (text[index] !== ',') fail('Expected a comma in JSON array');
            index += 1;
            skipWhitespace();
        }
    }
    function parseObject() {
        var keys = new Set();
        index += 1;
        skipWhitespace();
        if (text[index] === '}') { index += 1; return; }
        while (true) {
            var key = parseString();
            if (keys.has(key)) throw new Error('Duplicate JSON object key: ' + key);
            keys.add(key);
            skipWhitespace();
            if (text[index] !== ':') fail('Expected a colon after JSON object key');
            index += 1;
            parseValue();
            skipWhitespace();
            if (text[index] === '}') { index += 1; return; }
            if (text[index] !== ',') fail('Expected a comma in JSON object');
            index += 1;
            skipWhitespace();
        }
    }
    function parseValue() {
        skipWhitespace();
        var ch = text[index];
        if (ch === '{') parseObject();
        else if (ch === '[') parseArray();
        else if (ch === '"') parseString();
        else if (ch === '-' || /[0-9]/.test(ch || '')) parseNumber();
        else if (ch === 't') parseLiteral('true');
        else if (ch === 'f') parseLiteral('false');
        else if (ch === 'n') parseLiteral('null');
        else fail('Unexpected JSON value');
    }
    parseValue();
    skipWhitespace();
    if (index !== text.length) fail('Unexpected content after JSON value');
}
function requireValue(condition, message) {
    if (!condition) throw new Error(message);
}
var manifestText = readUtf8(env('IT140_JXA_MANIFEST_FILE'));
var schemaText = readUtf8(env('IT140_JXA_SCHEMA_FILE'));
rejectDuplicateObjectKeys(manifestText);
rejectDuplicateObjectKeys(schemaText);
var manifest = JSON.parse(manifestText);
var schema = JSON.parse(schemaText);
var required = ['schema_version','automation_release','automation_release_date','course','control','policy','capabilities','products','software_sources','provider_profiles','platforms','deployment_profiles','managed_settings','managed_assets','obsolete_components','logging'];
required.forEach(function (key) { requireValue(Object.prototype.hasOwnProperty.call(manifest, key), 'Manifest missing required key: ' + key); });
requireValue(manifest.schema_version === '2.0', 'Unsupported manifest schema version: ' + manifest.schema_version);
requireValue(/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(String(manifest.automation_release)), 'Manifest automation_release is not three-part SemVer.');
requireValue(/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(String(manifest.automation_release_date)), 'Manifest automation_release_date is not YYYY-MM-DD.');
requireValue(schema.$schema === 'https://json-schema.org/draft/2020-12/schema', 'Schema does not declare JSON Schema Draft 2020-12.');
requireValue(manifest.policy.allow_os_release_upgrade === false, 'Manifest attempts to enable a macOS release upgrade.');
var platform = manifest.platforms.macos;
var profile = manifest.deployment_profiles.macos_bare_metal;
requireValue(platform && platform.enabled === true, 'macOS platform is not enabled.');
requireValue(profile && profile.enabled === true && profile.platform_id === 'macos', 'macOS deployment profile is invalid.');
requireValue(profile.architecture === 'arm64', 'macOS deployment profile is not Apple silicon.');
requireValue(Array.isArray(platform.os.architectures) && platform.os.architectures.length === 1 && platform.os.architectures[0] === 'arm64', 'macOS architectures must contain only arm64.');
var major = env('IT140_JXA_PRODUCT_VERSION').split('.')[0];
var releases = platform.os.releases.map(function (item) { return String(item.release_id); });
requireValue(releases.indexOf(major) >= 0, 'macOS major release ' + major + ' is not enabled.');
var bindings = platform.course_ide_bindings || {};
var expected = {
  version_control_system: ['homebrew_formula','git'],
  source_hosting_client: ['homebrew_formula','gh'],
  programming_language_runtime: ['homebrew_formula','python@3.12'],
  source_code_ide: ['homebrew_cask','visual-studio-code'],
  test_runner: ['python_venv_package','pytest'],
  coverage_reporter: ['python_venv_package','pytest-cov'],
  language_support: ['vscode_extension','ms-python.python'],
  code_quality_tool: ['vscode_extension','charliermarsh.ruff'],
  diagram_support: ['vscode_extension','hediet.vscode-drawio'],
  pseudocode_support: ['vscode_extension','i2p-hub.i2p-pseudo'],
  spell_checker: ['vscode_extension','streetsidesoftware.code-spell-checker'],
  file_viewer: ['vscode_extension','cweijan.vscode-office']
};
Object.keys(expected).forEach(function (role) {
    var binding = bindings[role];
    requireValue(binding && binding.required === true, 'Required macOS binding is missing: ' + role);
    requireValue(binding.installer_adapter_id === expected[role][0], 'Unexpected installer for macOS binding: ' + role);
    requireValue(binding.package_identifier === expected[role][1], 'Unexpected package identifier for macOS binding: ' + role);
});
String(manifest.automation_release) + '\t' + String(manifest.automation_release_date);
JXA
    )"; then
        it140_fail 5 "Controlled manifest validation failed: $output"
    fi
    printf '%s\n' "$output"
}

it140_manifest_query() {
    local query="$1"
    local manifest_file="${2:-$IT140_MANIFEST_PATH}"
    env IT140_JXA_QUERY="$query" IT140_JXA_MANIFEST_FILE="$manifest_file" /usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
function env(name) {
    var value = $.NSProcessInfo.processInfo.environment.objectForKey(name);
    if (!value) throw new Error('Missing environment value: ' + name);
    return ObjC.unwrap(value);
}
function readUtf8(path) {
    var data = $.NSData.dataWithContentsOfFile($(path).stringByStandardizingPath);
    if (!data) throw new Error('Unable to read: ' + path);
    var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (!text) throw new Error('File is not valid UTF-8: ' + path);
    return ObjC.unwrap(text);
}
function rejectDuplicateObjectKeys(text) {
    var index = 0;
    function fail(message) { throw new Error(message + ' at character ' + index); }
    function skipWhitespace() { while (index < text.length && /[\t\n\r ]/.test(text[index])) index += 1; }
    function parseString() {
        var start = index;
        if (text[index] !== '"') fail('Expected a JSON string');
        index += 1;
        while (index < text.length) {
            var ch = text[index];
            if (ch === '"') {
                index += 1;
                return JSON.parse(text.slice(start, index));
            }
            if (ch === '\\') {
                index += 1;
                if (index >= text.length) fail('Unterminated JSON escape');
                if (text[index] === 'u') {
                    if (!/^[0-9A-Fa-f]{4}$/.test(text.slice(index + 1, index + 5))) fail('Invalid JSON Unicode escape');
                    index += 5;
                } else {
                    if ('"\\\\/bfnrt'.indexOf(text[index]) < 0) fail('Invalid JSON escape');
                    index += 1;
                }
                continue;
            }
            if (text.charCodeAt(index) < 0x20) fail('Unescaped control character in JSON string');
            index += 1;
        }
        fail('Unterminated JSON string');
    }
    function parseNumber() {
        var match = text.slice(index).match(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/);
        if (!match) fail('Invalid JSON number');
        index += match[0].length;
    }
    function parseLiteral(literal) {
        if (text.slice(index, index + literal.length) !== literal) fail('Invalid JSON literal');
        index += literal.length;
    }
    function parseArray() {
        index += 1;
        skipWhitespace();
        if (text[index] === ']') { index += 1; return; }
        while (true) {
            parseValue();
            skipWhitespace();
            if (text[index] === ']') { index += 1; return; }
            if (text[index] !== ',') fail('Expected a comma in JSON array');
            index += 1;
            skipWhitespace();
        }
    }
    function parseObject() {
        var keys = new Set();
        index += 1;
        skipWhitespace();
        if (text[index] === '}') { index += 1; return; }
        while (true) {
            var key = parseString();
            if (keys.has(key)) throw new Error('Duplicate JSON object key: ' + key);
            keys.add(key);
            skipWhitespace();
            if (text[index] !== ':') fail('Expected a colon after JSON object key');
            index += 1;
            parseValue();
            skipWhitespace();
            if (text[index] === '}') { index += 1; return; }
            if (text[index] !== ',') fail('Expected a comma in JSON object');
            index += 1;
            skipWhitespace();
        }
    }
    function parseValue() {
        skipWhitespace();
        var ch = text[index];
        if (ch === '{') parseObject();
        else if (ch === '[') parseArray();
        else if (ch === '"') parseString();
        else if (ch === '-' || /[0-9]/.test(ch || '')) parseNumber();
        else if (ch === 't') parseLiteral('true');
        else if (ch === 'f') parseLiteral('false');
        else if (ch === 'n') parseLiteral('null');
        else fail('Unexpected JSON value');
    }
    parseValue();
    skipWhitespace();
    if (index !== text.length) fail('Unexpected content after JSON value');
}
function uniqueSorted(values) { return Array.from(new Set(values)).sort(); }
var manifestText = readUtf8(env('IT140_JXA_MANIFEST_FILE'));
rejectDuplicateObjectKeys(manifestText);
var manifest = JSON.parse(manifestText);
var query = env('IT140_JXA_QUERY');
var platform = manifest.platforms.macos;
var bindings = platform.course_ide_bindings;
var values = [];
var result = '';
if (query === 'formulae') {
    Object.keys(bindings).forEach(function (key) { var b=bindings[key]; if (b.required && b.installation_scope==='system' && b.installer_adapter_id==='homebrew_formula') values.push(b.package_identifier); });
    result = uniqueSorted(values).join('\n');
} else if (query === 'casks') {
    Object.keys(bindings).forEach(function (key) { var b=bindings[key]; if (b.required && b.installation_scope==='system' && b.installer_adapter_id==='homebrew_cask') values.push(b.package_identifier); });
    result = uniqueSorted(values).join('\n');
} else if (query === 'venv_packages') {
    Object.keys(bindings).forEach(function (key) { var b=bindings[key]; if (b.required && b.installation_scope==='user' && b.installer_adapter_id==='python_venv_package') values.push(b.package_identifier); });
    values.push('ruff');
    result = uniqueSorted(values).join('\n');
} else if (query === 'extensions') {
    Object.keys(bindings).forEach(function (key) { var b=bindings[key]; if (b.required && b.installation_scope==='user' && b.installer_adapter_id==='vscode_extension') values.push(b.package_identifier); });
    result = uniqueSorted(values).join('\n');
} else if (query === 'git_settings') {
    var profile = manifest.managed_settings.git_course_defaults;
    result = Object.keys(profile.values).sort().map(function (key) { return key + '\t' + String(profile.values[key]); }).join('\n');
} else if (query === 'vscode_settings') {
    result = JSON.stringify(manifest.managed_settings.vscode_course_defaults.values);
} else {
    throw new Error('Unknown manifest query: ' + query);
}
result;
JXA
}

it140_initialize_homebrew() {
    [ -x "$IT140_HOMEBREW_BIN" ] || return 1
    eval "$("$IT140_HOMEBREW_BIN" shellenv)"
    return 0
}

it140_command_line_tools_available() {
    /usr/bin/xcode-select -p >/dev/null 2>&1 && /usr/bin/xcrun --find clang >/dev/null 2>&1
}

it140_system_layer_available() {
    it140_command_line_tools_available || return 1
    it140_initialize_homebrew || return 1
    [ -x "$IT140_PYTHON_BIN" ] || return 1
    [ -x "$IT140_CODE_BIN" ] || return 1
    command -v git >/dev/null 2>&1 || return 1
    command -v gh >/dev/null 2>&1 || return 1
}

it140_check_free_space() {
    local available_kb required_bytes
    required_bytes="$(it140_manifest_policy_free_space)"
    available_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
    printf '%s\n' "$available_kb" | grep -Eq '^[0-9]+$' || it140_fail 1 "Unable to determine free disk space."
    [ $((available_kb * 1024)) -ge "$required_bytes" ] || it140_fail 1 "At least $((required_bytes / 1073741824)) GB of free space is required."
    it140_success "Required free space is available."
}

it140_manifest_policy_free_space() {
    env IT140_JXA_MANIFEST_FILE="$IT140_MANIFEST_PATH" /usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
var env=$.NSProcessInfo.processInfo.environment;
var path=ObjC.unwrap(env.objectForKey('IT140_JXA_MANIFEST_FILE'));
var data=$.NSData.dataWithContentsOfFile($(path).stringByStandardizingPath);
var text=$.NSString.alloc.initWithDataEncoding(data,$.NSUTF8StringEncoding);
String(JSON.parse(ObjC.unwrap(text)).policy.minimum_free_space_bytes);
JXA
}

it140_elapsed_seconds() {
    printf '%s\n' "$(( $(date +%s) - IT140_START_EPOCH ))"
}

it140_closing_notice() {
    it140_notice "Log file: $IT140_LOG_FILE"
    it140_notice "Close this Terminal window and open a new one before running the next lifecycle script."
}

check_pass() { printf '[PASS] %s\n' "$1"; }
check_fail() { IT140_FAILURES=$((IT140_FAILURES + 1)); printf '[FAIL] %s\n' "$1"; }
check_warn() { IT140_WARNINGS=$((IT140_WARNINGS + 1)); printf '[WARNING] %s\n' "$1"; }

check_command() {
    local command_name="$1"
    local display_name="$2"
    if command -v "$command_name" >/dev/null 2>&1; then check_pass "$display_name is available."; else check_fail "$display_name is missing."; fi
}

check_vscode_settings() {
    local settings_file="$HOME/Library/Application Support/Code/User/settings.json"
    [ -r "$settings_file" ] || { check_fail "Visual Studio Code settings are missing."; return; }
    if IT140_SETTINGS_FILE="$settings_file" IT140_VENV_PYTHON="$IT140_VENV_PYTHON" IT140_COURSE_ROOT="$IT140_COURSE_ROOT" "$IT140_VENV_PYTHON" - <<'PYVERIFY'
import json, os
from pathlib import Path
observed=json.loads(Path(os.environ['IT140_SETTINGS_FILE']).read_text(encoding='utf-8'))
expected={
 'files.eol':'\n', 'editor.formatOnSave':True,
 'python.testing.pytestEnabled':True, 'python.testing.unittestEnabled':False,
 'python.defaultInterpreterPath':os.environ['IT140_VENV_PYTHON'],
 'files.defaultFolder':os.environ['IT140_COURSE_ROOT'],
}
for key,value in expected.items():
    if observed.get(key) != value: raise SystemExit(1)
if observed.get('[python]',{}).get('editor.defaultFormatter') != 'charliermarsh.ruff': raise SystemExit(1)
if observed.get('files.associations',{}).get('*.pseudo') != 'pseudo': raise SystemExit(1)
PYVERIFY
    then check_pass "Course-managed Visual Studio Code settings are present."; else check_fail "One or more course-managed Visual Studio Code settings are missing or different."; fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help) show_help; exit 0 ;;
        --version) it140_print_version; exit 0 ;;
        --noninteractive) IT140_NONINTERACTIVE=1 ;;
        --profile)
            [ "$#" -ge 2 ] || { printf '[ERROR] --profile requires a value.\n' >&2; exit 64; }
            IT140_REQUESTED_PROFILE="$2"
            shift
            ;;
        *) printf '[ERROR] Unknown option: %s\n%s\n' "$1" "$IT140_USAGE" >&2; exit 64 ;;
    esac
    shift
done
[ "$IT140_REQUESTED_PROFILE" = "macos_bare_metal" ] || {
    printf '[ERROR] Only the macos_bare_metal profile is supported by this Apple-silicon baseline.\n' >&2
    exit 64
}

it140_install_traps
it140_check_platform_user
it140_initialize_log
trap 'it140_cleanup' EXIT
it140_prune_logs

it140_header "IT 140 macOS VERIFICATION"
it140_print_version | sed 's/^/[INFO] /'
it140_info "Deployment       : $IT140_REQUESTED_PROFILE"
it140_info "Current user     : $(id -un)"
it140_info "Course root      : $IT140_COURSE_ROOT"
it140_info "Log file         : $IT140_LOG_FILE"
it140_info "Operating system : $(/usr/bin/sw_vers -productName) $(/usr/bin/sw_vers -productVersion)"
it140_info "Architecture     : $(uname -m)"
manifest_summary="$(it140_json_validate)"
it140_info "Manifest release : ${manifest_summary%%$'\t'*}"

it140_header "Step 1: Verify System Components"
if it140_command_line_tools_available; then check_pass "Apple Command Line Tools are available."; else check_fail "Apple Command Line Tools are unavailable."; fi
if it140_initialize_homebrew; then check_pass "Homebrew is available."; else check_fail "Homebrew is unavailable."; fi
check_command git "Git"
check_command gh "GitHub CLI"
[ -x "$IT140_PYTHON_BIN" ] && "$IT140_PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3,12) else 1)' >/dev/null 2>&1 && check_pass "Python 3.12 is available." || check_fail "Python 3.12 is unavailable or has the wrong version."
[ -x "$IT140_CODE_BIN" ] && "$IT140_CODE_BIN" --version >/dev/null 2>&1 && check_pass "Visual Studio Code is available." || check_fail "Visual Studio Code is unavailable."

it140_header "Step 2: Verify User Configuration"
if gh auth status --hostname github.com >/dev/null 2>&1; then check_pass "GitHub authentication is configured."; else check_fail "GitHub authentication is not configured."; fi
[ -n "$(git config --global --get user.name 2>/dev/null || true)" ] && check_pass "Git display name is configured." || check_fail "Git display name is missing."
git_email="$(git config --global --get user.email 2>/dev/null || true)"
[[ "$git_email" == *@users.noreply.github.com ]] && check_pass "Git uses a privacy-preserving GitHub noreply address." || check_fail "Git does not use the expected GitHub noreply address."
while IFS=$'\t' read -r key value; do
    [ -n "$key" ] || continue
    observed="$(git config --global --get "$key" 2>/dev/null || true)"
    [ "$observed" = "$value" ] && check_pass "Git setting is correct: $key" || check_fail "Git setting is missing or different: $key"
done < <(it140_manifest_query git_settings)
for shell_file in "$HOME/.zprofile" "$HOME/.zshrc"; do
    grep -Fq "$IT140_MANAGED_ENV_START" "$shell_file" 2>/dev/null && check_pass "The managed shell environment block is present in $shell_file." || check_fail "The managed shell environment block is missing from $shell_file."
done

it140_header "Step 3: Verify Python and Visual Studio Code"
if [ -x "$IT140_VENV_PYTHON" ] && "$IT140_VENV_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3,12) else 1)' >/dev/null 2>&1; then
    check_pass "The course Python 3.12 virtual environment is available."
    while IFS= read -r package; do
        [ -n "$package" ] || continue
        "$IT140_VENV_PYTHON" -m pip show "$package" >/dev/null 2>&1 && check_pass "Python package is installed: $package" || check_fail "Python package is missing: $package"
    done < <(it140_manifest_query venv_packages)
else
    check_fail "The course Python virtual environment is missing or invalid."
fi
if [ -x "$IT140_CODE_BIN" ]; then
    installed_extensions="$($IT140_CODE_BIN --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    while IFS= read -r extension; do
        [ -n "$extension" ] || continue
        printf '%s\n' "$installed_extensions" | grep -Fxiq "$extension" && check_pass "VS Code extension is installed: $extension" || check_fail "VS Code extension is missing: $extension"
    done < <(it140_manifest_query extensions)
    if [ -x "$IT140_VENV_PYTHON" ]; then
        check_vscode_settings
    else
        check_fail "Visual Studio Code settings could not be validated because the course Python environment is unavailable."
    fi
fi

it140_header "Step 4: Verify Desktop Shortcuts"
if [ -L "$IT140_COURSE_DESKTOP_LINK" ] && [ "$(readlink "$IT140_COURSE_DESKTOP_LINK")" = "$IT140_COURSE_ROOT" ]; then check_pass "The IT 140 desktop folder link is correct."; else check_fail "The IT 140 desktop folder link is missing or incorrect."; fi
if [ -x "$IT140_VSCODE_DESKTOP_APP/Contents/MacOS/open-it140-in-code" ] && /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$IT140_VSCODE_DESKTOP_APP/Contents/Info.plist" 2>/dev/null | grep -Fxq 'org.gc-stem.it140.vscode-launcher'; then check_pass "The Visual Studio Code desktop launcher is correct."; else check_fail "The Visual Studio Code desktop launcher is missing or invalid."; fi

it140_header "VERIFICATION SUMMARY"
if [ "$IT140_FAILURES" -eq 0 ]; then
    it140_info "Result           : PASS"
    exit_code=0
else
    it140_info "Result           : FAIL"
    exit_code=1
fi
it140_info "Required failures: $IT140_FAILURES"
it140_info "Warnings         : $IT140_WARNINGS"
it140_info "Elapsed seconds  : $(it140_elapsed_seconds)"
it140_closing_notice
exit "$exit_code"
