#!/bin/zsh
# ==============================================================================
# IT 140 COURSE IDE — INSTALL (macOS APPLE SILICON)
# ==============================================================================
# Repository path: scripts/mac/install_it140.zsh
# Purpose: Install or repair the manifest-declared macOS system layer for the IT 140 course IDE.
# Artifact ID: IT140-MAC-INSTALL
# Artifact version: 0.6.0
# Version date-time group: 2026-08-03-06-52
# Development status: Alpha Testing
# Supported profile: macos_bare_metal (Apple silicon, arm64)
# Traceability: INS-FR-001 through INS-FR-012; PKG-FR-003 through PKG-FR-010; PKG-FR-021; PKG-QOS-011 through PKG-QOS-015.
# ==============================================================================

set -euo pipefail
umask 077

readonly IT140_ACTION='install'
readonly IT140_ACTION_DISPLAY='Install'
readonly IT140_ARTIFACT_ID='IT140-MAC-INSTALL'
readonly IT140_ARTIFACT_VERSION='0.6.0'
readonly IT140_VERSION_DATE_TIME_GROUP='2026-08-03-06-52'
readonly IT140_DEVELOPMENT_STATUS='Alpha Testing'
readonly IT140_SUPPORTED_SCHEMA='2.2'
readonly IT140_PLATFORM_ID='macos'
readonly IT140_PLATFORM_ABBREVIATION='mac'
readonly IT140_DEFAULT_PROFILE='macos_bare_metal'
readonly IT140_COURSE_ROOT="${HOME}/it140"
readonly IT140_SCRIPT_ROOT="${IT140_COURSE_ROOT}/scripts"
readonly IT140_PLATFORM_SCRIPT_DIR="${IT140_SCRIPT_ROOT}/mac"
readonly IT140_MANIFEST_PATH="${IT140_SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly IT140_SCHEMA_PATH="${IT140_SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly IT140_LOG_DIR="${IT140_COURSE_ROOT}/logs"
readonly IT140_RUN_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly IT140_LOG_FILE="${IT140_LOG_DIR}/${IT140_ACTION}_ide_${IT140_RUN_TIMESTAMP}.log"
readonly IT140_LOCK_PARENT="${HOME}/Library/Caches"
readonly IT140_LOCK_DIR="${IT140_LOCK_PARENT}/it140-${IT140_PLATFORM_ABBREVIATION}-mutation.lock"
readonly IT140_VENV_DIR="${IT140_COURSE_ROOT}/.venv"
readonly IT140_VSCODE_SETTINGS_FILE="${HOME}/Library/Application Support/Code/User/settings.json"
readonly IT140_SHELL_STARTUP_FILE="${HOME}/.zshrc"
readonly IT140_MANAGED_ENV_START='# >>> IT 140 Course IDE managed environment >>>'
readonly IT140_MANAGED_ENV_END='# <<< IT 140 Course IDE managed environment <<<'

IT140_NONINTERACTIVE=false
IT140_REQUESTED_PROFILE="$IT140_DEFAULT_PROFILE"
IT140_CHANGED=false
IT140_LOCK_HELD=false
IT140_FINISHED=false
IT140_WARNINGS=0
IT140_FAILURES=0
IT140_START_EPOCH="$(date +%s)"
IT140_CURRENT_STAGE='Initialization'
IT140_MANIFEST_RELEASE='Unavailable'
IT140_MANIFEST_DTG='Unavailable'
IT140_WORKFLOW_ID='Unavailable'
IT140_STARTING_STATE='Unavailable'
IT140_OPERATING_ROLE='local_user'
IT140_NEXT_ACTION='configure'
IT140_MINIMUM_FREE_SPACE_BYTES=5368709120
IT140_NETWORK_TIMEOUT_SECONDS=60
IT140_RETRY_MAXIMUM_ATTEMPTS=5
IT140_RETRY_INITIAL_DELAY_SECONDS=5
IT140_TEMP_PATHS=()
IT140_RUNTIME_TEMP_DIR=''

it140_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

it140_info() { printf '[INFO] %s\n' "$*"; }
it140_success() { printf '[SUCCESS] %s\n' "$*"; }
it140_notice() { printf '[NOTICE] %s\n' "$*"; }
it140_warning() {
    IT140_WARNINGS=$((IT140_WARNINGS + 1))
    printf '[WARNING] %s\n' "$*"
}
it140_error() {
    IT140_FAILURES=$((IT140_FAILURES + 1))
    printf '[ERROR] %s\n' "$*" >&2
}

it140_usage() {
    cat <<'USAGE'
Usage: install_it140.zsh [--help] [--version] [--noninteractive]
                       [--deployment-profile macos_bare_metal]

Installs or repairs Apple Command Line Tools, Homebrew, and the manifest-declared system-scoped course IDE products. It does not authenticate GitHub or configure user settings.

Options:
  --help                         Show this help and exit.
  --version                      Show artifact metadata and exit.
  --noninteractive               Do not start optional interactive operations.
  --deployment-profile PROFILE   Select the approved macOS deployment profile.

Run this script from the intended macOS course account. Do not add sudo before
this command. The script requests administrator authorization only for an
individual operation that requires it.

Logs: ~/it140/logs/
USAGE
}

it140_show_version() {
    printf '%s %s (%s)\n' \
        "$IT140_ARTIFACT_ID" \
        "$IT140_ARTIFACT_VERSION" \
        "$IT140_VERSION_DATE_TIME_GROUP"
    printf 'Status: %s\n' "$IT140_DEVELOPMENT_STATUS"
}

it140_parse_options() {
    while (( $# > 0 )); do
        case "$1" in
            --help)
                it140_usage
                exit 0
                ;;
            --version)
                it140_show_version
                exit 0
                ;;
            --noninteractive)
                IT140_NONINTERACTIVE=true
                ;;
            --deployment-profile|--profile)
                if (( $# < 2 )); then
                    printf '[ERROR] %s requires a value.\n' "$1" >&2
                    exit 2
                fi
                IT140_REQUESTED_PROFILE="$2"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                printf '[ERROR] Unsupported option: %s\n' "$1" >&2
                it140_usage >&2
                exit 2
                ;;
        esac
        shift
    done
    if (( $# > 0 )); then
        printf '[ERROR] Unexpected argument: %s\n' "$1" >&2
        exit 2
    fi
}

it140_register_temp() {
    IT140_TEMP_PATHS+=("$1")
}

it140_release_lock() {
    if [[ "$IT140_LOCK_HELD" == true && -d "$IT140_LOCK_DIR" ]]; then
        /bin/rm -rf -- "$IT140_LOCK_DIR"
    fi
    IT140_LOCK_HELD=false
}

it140_cleanup() {
    set +e
    local path
    for path in "${IT140_TEMP_PATHS[@]}"; do
        [[ -n "$path" ]] && /bin/rm -rf -- "$path"
    done
    it140_release_lock
}

it140_course_continuity() {
    it140_notice 'Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved.'
}

it140_elapsed() {
    local now
    now="$(date +%s)"
    printf '%s' "$((now - IT140_START_EPOCH))"
}

it140_finish() {
    local exit_code="$1"
    local result="$2"
    local detail="$3"
    local next_step="$4"

    trap - ERR INT TERM HUP
    set +e
    IT140_FINISHED=true
    it140_cleanup

    it140_header "IT 140 macOS $(printf '%s' "$IT140_ACTION_DISPLAY" | /usr/bin/tr '[:lower:]' '[:upper:]') SUMMARY"
    printf 'Result                  : %s\n' "$result"
    printf 'Artifact ID             : %s\n' "$IT140_ARTIFACT_ID"
    printf 'Artifact version        : %s\n' "$IT140_ARTIFACT_VERSION"
    printf 'Version date-time group : %s\n' "$IT140_VERSION_DATE_TIME_GROUP"
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
    printf 'Next step               : %s\n' "$next_step"
    printf 'Log file                : %s\n' "$IT140_LOG_FILE"
    printf 'Exit code               : %s\n' "$exit_code"

    if (( exit_code == 0 )); then
        it140_success "The IT 140 macOS $IT140_ACTION completed successfully."
    else
        it140_course_continuity
    fi
    it140_notice 'Review the summary and log before closing Terminal.'
    if [[ "$next_step" != 'None' ]]; then
        it140_notice 'Open a new Terminal window before running the next lifecycle script.'
    fi
    exit "$exit_code"
}

it140_abort() {
    local exit_code="$1"
    shift
    local message="$*"
    if [[ "$IT140_CHANGED" == true && "$exit_code" -ne 2 && "$exit_code" -ne 5 ]]; then
        exit_code=7
    fi
    it140_error "$message"
    it140_error "Failed stage: $IT140_CURRENT_STAGE"
    it140_finish "$exit_code" 'FAIL' "$message" \
        "Rerun: \"$HOME/it140/scripts/mac/${IT140_ACTION}_it140.zsh\""
}

it140_on_error() {
    local status="$1"
    local line="$2"
    trap - ERR
    set +e
    local exit_code=1
    [[ "$IT140_CHANGED" == true ]] && exit_code=7
    it140_error "An unexpected command failure occurred near line ${line} during ${IT140_CURRENT_STAGE} (status ${status})."
    it140_finish "$exit_code" 'FAIL' \
        'An unexpected command failure stopped the script.' \
        "Rerun: \"$HOME/it140/scripts/mac/${IT140_ACTION}_it140.zsh\""
}

it140_on_interrupt() {
    trap - INT TERM HUP
    set +e
    local exit_code=6
    [[ "$IT140_CHANGED" == true ]] && exit_code=7
    it140_error "The script was interrupted during ${IT140_CURRENT_STAGE}."
    it140_finish "$exit_code" 'CANCELED' \
        'The operation did not finish. Rerun the same script to recover.' \
        "Rerun: \"$HOME/it140/scripts/mac/${IT140_ACTION}_it140.zsh\""
}

it140_initialize_log() {
    /bin/mkdir -p -- "$IT140_LOG_DIR"
    /bin/chmod -- 0700 "$IT140_LOG_DIR"
    : > "$IT140_LOG_FILE"
    /bin/chmod -- 0600 "$IT140_LOG_FILE"
    exec > >(/usr/bin/tee -a "$IT140_LOG_FILE") 2>&1

    IT140_RUNTIME_TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/it140-${IT140_ACTION}.XXXXXX")"
    it140_register_temp "$IT140_RUNTIME_TEMP_DIR"

    trap 'it140_on_error $? $LINENO' ERR
    trap 'it140_on_interrupt' INT TERM HUP

    it140_header "IT 140 macOS $(printf '%s' "$IT140_ACTION_DISPLAY" | /usr/bin/tr '[:lower:]' '[:upper:]')"
    printf '[INFO] Artifact ID             : %s\n' "$IT140_ARTIFACT_ID"
    printf '[INFO] Artifact version        : %s\n' "$IT140_ARTIFACT_VERSION"
    printf '[INFO] Version date-time group : %s\n' "$IT140_VERSION_DATE_TIME_GROUP"
    printf '[INFO] Status                  : %s\n' "$IT140_DEVELOPMENT_STATUS"
    printf '[INFO] Script                  : %s\n' "${0##*/}"
    printf '[INFO] Detected platform       : %s\n' "$(uname -s 2>/dev/null || printf 'Unknown')"
    printf '[INFO] Current user            : %s\n' "$(id -un 2>/dev/null || printf 'Unknown')"
    printf '[INFO] Start time              : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf '[INFO] Purpose                 : %s\n' 'Install or repair the manifest-declared macOS system layer for the IT 140 course IDE.'
    printf '[INFO] Log file                : %s\n' "$IT140_LOG_FILE"
}

it140_prune_logs() {
    set +e
    /usr/bin/find "$IT140_LOG_DIR" -type f -name '*.log' -mtime +180 -delete 2>/dev/null
    local stale
    /bin/ls -1t "$IT140_LOG_DIR"/*.log 2>/dev/null | /usr/bin/awk 'NR > 50' |
        while IFS= read -r stale; do
            [[ -n "$stale" ]] && /bin/rm -f -- "$stale"
        done
    set -e
}

it140_acquire_lock() {
    IT140_CURRENT_STAGE='Acquire mutation lock'
    /bin/mkdir -p -- "$IT140_LOCK_PARENT"

    if /bin/mkdir -- "$IT140_LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$IT140_LOCK_DIR/pid"
        printf '%s\n' "$(date +%s)" > "$IT140_LOCK_DIR/created_epoch"
        IT140_LOCK_HELD=true
        return 0
    fi

    local lock_pid=''
    local created_epoch='0'
    [[ -r "$IT140_LOCK_DIR/pid" ]] && lock_pid="$(<"$IT140_LOCK_DIR/pid")"
    [[ -r "$IT140_LOCK_DIR/created_epoch" ]] && created_epoch="$(<"$IT140_LOCK_DIR/created_epoch")"
    local now age
    now="$(date +%s)"
    age=$((now - created_epoch))

    if [[ "$lock_pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$lock_pid" 2>/dev/null && (( age < 7200 )); then
        it140_abort 7 "Another IT 140 macOS lifecycle script is already running (process ${lock_pid})."
    fi

    it140_warning 'A stale lifecycle lock was found and removed.'
    /bin/rm -rf -- "$IT140_LOCK_DIR"
    if ! /bin/mkdir -- "$IT140_LOCK_DIR"; then
        it140_abort 1 'The lifecycle lock could not be acquired after stale-lock recovery.'
    fi
    printf '%s\n' "$$" > "$IT140_LOCK_DIR/pid"
    printf '%s\n' "$(date +%s)" > "$IT140_LOCK_DIR/created_epoch"
    IT140_LOCK_HELD=true
}

it140_manifest_tool_at() {
    local manifest_path="$1"
    local schema_path="$2"
    local query="$3"
    shift 3

    /usr/bin/osascript -l JavaScript - \
        "$manifest_path" "$schema_path" "$query" "$@" <<'JXA'
ObjC.import('Foundation');

function readText(path) {
    var data = $.NSData.dataWithContentsOfFile($(path));
    if (!data) {
        throw new Error('cannot read file: ' + path);
    }
    var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (!text) {
        throw new Error('file is not valid UTF-8: ' + path);
    }
    return ObjC.unwrap(text);
}

function readJson(path) {
    return JSON.parse(readText(path));
}

function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requireObject(parent, key, label) {
    if (!isObject(parent[key])) {
        throw new Error(label + ' is missing or is not an object');
    }
    return parent[key];
}

function valueString(value) {
    if (typeof value === 'boolean') {
        return value ? 'true' : 'false';
    }
    if (value === null || value === undefined) {
        return '';
    }
    return String(value);
}

function run(argv) {
    var manifestPath = argv[0];
    var schemaPath = argv[1];
    var query = argv[2];
    var args = argv.slice(3);
    var manifest = readJson(manifestPath);
    var schema = readJson(schemaPath);
    var platformId = 'macos';
    var profileId = args.length > 1 ? args[1] : 'macos_bare_metal';

    if (query === 'validate') {
        var action = args[0];
        profileId = args[1];
        var osMajor = args[2];
        var expectedSchema = args[3];
        var required = [
            'schema_version', 'automation_release',
            'automation_release_date_time_group', 'course', 'control', 'policy',
            'capabilities', 'products', 'software_sources', 'provider_profiles',
            'platforms', 'deployment_profiles', 'lifecycle_workflows',
            'managed_settings', 'managed_assets', 'obsolete_components', 'logging'
        ];
        required.forEach(function (key) {
            if (!Object.prototype.hasOwnProperty.call(manifest, key)) {
                throw new Error('manifest missing required key: ' + key);
            }
        });
        if (manifest.schema_version !== expectedSchema) {
            throw new Error('unsupported manifest schema ' + manifest.schema_version +
                '; expected ' + expectedSchema);
        }
        if (!/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(manifest.automation_release)) {
            throw new Error('automation_release is not strict SemVer');
        }
        if (!/^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$/.test(manifest.automation_release_date_time_group)) {
            throw new Error('automation_release_date_time_group is invalid');
        }
        if (schema.$schema !== 'https://json-schema.org/draft/2020-12/schema') {
            throw new Error('schema is not JSON Schema Draft 2020-12');
        }
        if (!schema.properties || !schema.properties.schema_version ||
                schema.properties.schema_version.const !== expectedSchema) {
            throw new Error('schema_version contract does not match the script');
        }
        var platforms = requireObject(manifest, 'platforms', 'platforms');
        var platform = requireObject(platforms, platformId, 'macOS platform');
        if (platform.enabled !== true) {
            throw new Error('macOS platform is disabled');
        }
        var architectures = platform.os && platform.os.architectures;
        if (!Array.isArray(architectures) || architectures.indexOf('arm64') < 0) {
            throw new Error('macOS arm64 architecture is not enabled');
        }
        var releases = platform.os && platform.os.releases;
        if (!Array.isArray(releases) || !releases.some(function (release) {
            return String(release.release_id) === String(osMajor);
        })) {
            throw new Error('macOS release ' + osMajor + ' is not supported');
        }
        var profiles = requireObject(manifest, 'deployment_profiles', 'deployment_profiles');
        var profile = requireObject(profiles, profileId, 'deployment profile ' + profileId);
        if (profile.enabled !== true || profile.platform_id !== platformId ||
                profile.architecture !== 'arm64') {
            throw new Error('deployment profile is not an enabled macOS arm64 profile');
        }
        var workflowId = action === 'update' ?
            'local_periodic_maintenance' : 'local_initial_install';
        var workflows = requireObject(manifest, 'lifecycle_workflows', 'lifecycle_workflows');
        var workflow = requireObject(workflows, workflowId, 'workflow ' + workflowId);
        if (!Array.isArray(profile.allowed_workflow_ids) ||
                profile.allowed_workflow_ids.indexOf(workflowId) < 0) {
            throw new Error('workflow is not allowed for the selected profile');
        }
        if (!workflow.success_transitions ||
                !Object.prototype.hasOwnProperty.call(workflow.success_transitions, action)) {
            throw new Error('workflow does not define a transition for ' + action);
        }
        var policy = requireObject(manifest, 'policy', 'policy');
        var retryProfiles = requireObject(policy, 'retry_profiles', 'retry_profiles');
        var retryId = policy.default_retry_profile_id;
        var retry = requireObject(retryProfiles, retryId, 'default retry profile');
        return [
            'automation_release=' + manifest.automation_release,
            'automation_release_date_time_group=' + manifest.automation_release_date_time_group,
            'workflow_id=' + workflowId,
            'starting_state_id=' + workflow.starting_state_id,
            'operating_role=' + workflow.operating_roles[0],
            'next_action=' + workflow.success_transitions[action],
            'minimum_free_space_bytes=' + policy.minimum_free_space_bytes,
            'network_timeout_seconds=' + policy.network_timeout_seconds,
            'retry_maximum_attempts=' + retry.maximum_attempts,
            'retry_initial_delay_seconds=' + retry.initial_delay_seconds
        ].join('\n');
    }

    var platform = manifest.platforms[platformId];
    var bindings = platform.course_ide_bindings;

    if (query === 'system_formulae') {
        return Object.keys(bindings).filter(function (key) {
            var item = bindings[key];
            return item.required === true && item.installation_scope === 'system' &&
                item.installer_adapter_id === 'homebrew_formula';
        }).map(function (key) { return bindings[key].package_identifier; }).join('\n');
    }
    if (query === 'system_casks') {
        return Object.keys(bindings).filter(function (key) {
            var item = bindings[key];
            return item.required === true && item.installation_scope === 'system' &&
                item.installer_adapter_id === 'homebrew_cask';
        }).map(function (key) { return bindings[key].package_identifier; }).join('\n');
    }
    if (query === 'system_commands') {
        var values = [];
        Object.keys(bindings).forEach(function (key) {
            var item = bindings[key];
            if (item.required === true && item.installation_scope === 'system' &&
                    item.verification && Array.isArray(item.verification.executable_names)) {
                item.verification.executable_names.forEach(function (name) {
                    if (values.indexOf(name) < 0) values.push(name);
                });
            }
        });
        return values.join('\n');
    }
    if (query === 'python_executable') {
        return bindings.programming_language_runtime.verification.executable_names[0];
    }
    if (query === 'venv_packages') {
        return Object.keys(bindings).filter(function (key) {
            var item = bindings[key];
            return item.required === true && item.installation_scope === 'user' &&
                item.installer_adapter_id === 'python_venv_package';
        }).map(function (key) { return bindings[key].package_identifier; }).join('\n');
    }
    if (query === 'vscode_extensions') {
        return Object.keys(bindings).filter(function (key) {
            var item = bindings[key];
            return item.required === true && item.installation_scope === 'user' &&
                item.installer_adapter_id === 'vscode_extension';
        }).map(function (key) { return bindings[key].package_identifier; }).join('\n');
    }
    if (query === 'git_settings') {
        var gitValues = manifest.managed_settings.git_course_defaults.values;
        return Object.keys(gitValues).sort().map(function (key) {
            return key + '\t' + valueString(gitValues[key]);
        }).join('\n');
    }
    if (query === 'vscode_settings_json') {
        return JSON.stringify(manifest.managed_settings.vscode_course_defaults.values);
    }
    if (query === 'managed_assets') {
        var assets = manifest.managed_assets;
        return Object.keys(assets).sort().filter(function (key) {
            var item = assets[key];
            return Array.isArray(item.managed_by) && item.managed_by.indexOf('update') >= 0;
        }).map(function (key) {
            return key + '\t' + assets[key].source_path + '\t' + assets[key].destination;
        }).join('\n');
    }
    if (query === 'log_policy') {
        var retention = manifest.logging.retention;
        return String(retention.maximum_files) + '\t' + String(retention.maximum_age_days);
    }
    throw new Error('unsupported manifest query: ' + query);
}
JXA
}

it140_manifest_tool() {
    it140_manifest_tool_at "$IT140_MANIFEST_PATH" "$IT140_SCHEMA_PATH" "$@"
}

it140_semver_compare() {
    /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXAVER'
function parse(value) {
    var match = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/.exec(value);
    if (!match) throw new Error('invalid SemVer: ' + value);
    return {core: [Number(match[1]), Number(match[2]), Number(match[3])], pre: match[4] ? match[4].split('.') : null};
}
function identifiers(left, right) {
    if (left === null && right === null) return 0;
    if (left === null) return 1;
    if (right === null) return -1;
    var count = Math.min(left.length, right.length);
    for (var i = 0; i < count; i++) {
        if (left[i] === right[i]) continue;
        var ln = /^[0-9]+$/.test(left[i]);
        var rn = /^[0-9]+$/.test(right[i]);
        if (ln && rn) return Number(left[i]) < Number(right[i]) ? -1 : 1;
        if (ln !== rn) return ln ? -1 : 1;
        return left[i] < right[i] ? -1 : 1;
    }
    return left.length === right.length ? 0 : (left.length < right.length ? -1 : 1);
}
function run(argv) {
    var left = parse(argv[0]);
    var right = parse(argv[1]);
    for (var i = 0; i < 3; i++) {
        if (left.core[i] !== right.core[i]) return left.core[i] < right.core[i] ? '-1' : '1';
    }
    return String(identifiers(left.pre, right.pre));
}
JXAVER
}

it140_load_manifest() {
    IT140_CURRENT_STAGE='Validate controlled manifest and schema'
    if [[ ! -r "$IT140_MANIFEST_PATH" || ! -r "$IT140_SCHEMA_PATH" ]]; then
        it140_abort 5 'The controlled manifest or schema is missing or unreadable.'
    fi
    if ! /usr/bin/plutil -lint "$IT140_MANIFEST_PATH" >/dev/null 2>&1; then
        it140_abort 5 'The controlled manifest is not valid JSON.'
    fi
    if ! /usr/bin/plutil -lint "$IT140_SCHEMA_PATH" >/dev/null 2>&1; then
        it140_abort 5 'The manifest schema is not valid JSON.'
    fi

    local os_major summary key value
    os_major="$(/usr/bin/sw_vers -productVersion 2>/dev/null | /usr/bin/awk -F. '{print $1}')"
    if ! summary="$(it140_manifest_tool validate \
            "$IT140_ACTION" "$IT140_REQUESTED_PROFILE" "$os_major" \
            "$IT140_SUPPORTED_SCHEMA" 2>&1)"; then
        it140_abort 5 "Controlled manifest validation failed: ${summary}"
    fi

    while IFS='=' read -r key value; do
        case "$key" in
            automation_release) IT140_MANIFEST_RELEASE="$value" ;;
            automation_release_date_time_group) IT140_MANIFEST_DTG="$value" ;;
            workflow_id) IT140_WORKFLOW_ID="$value" ;;
            starting_state_id) IT140_STARTING_STATE="$value" ;;
            operating_role) IT140_OPERATING_ROLE="$value" ;;
            next_action) IT140_NEXT_ACTION="$value" ;;
            minimum_free_space_bytes) IT140_MINIMUM_FREE_SPACE_BYTES="$value" ;;
            network_timeout_seconds) IT140_NETWORK_TIMEOUT_SECONDS="$value" ;;
            retry_maximum_attempts) IT140_RETRY_MAXIMUM_ATTEMPTS="$value" ;;
            retry_initial_delay_seconds) IT140_RETRY_INITIAL_DELAY_SECONDS="$value" ;;
        esac
    done <<< "$summary"

    it140_info "Manifest release : ${IT140_MANIFEST_RELEASE}"
    it140_info "Manifest DTG     : ${IT140_MANIFEST_DTG}"
    it140_info "Workflow         : ${IT140_WORKFLOW_ID}"
    it140_info "Starting state   : ${IT140_STARTING_STATE}"
    it140_info "Operating role   : ${IT140_OPERATING_ROLE}"
}

it140_check_platform_base() {
    IT140_CURRENT_STAGE='Check supported platform and user context'
    if [[ "$(uname -s 2>/dev/null)" != 'Darwin' ]]; then
        it140_abort 2 'This script supports macOS only.'
    fi
    if (( $(id -u) == 0 )); then
        it140_abort 2 'Do not run this script as root or with sudo.'
    fi
    if [[ "$(uname -m 2>/dev/null)" != 'arm64' ]]; then
        it140_abort 2 'The current IT 140 macOS implementation supports Apple silicon (arm64) only.'
    fi
    if [[ "$IT140_REQUESTED_PROFILE" != "$IT140_DEFAULT_PROFILE" ]]; then
        it140_abort 2 "Unsupported deployment profile: ${IT140_REQUESTED_PROFILE}."
    fi
}

it140_check_admin_account() {
    IT140_CURRENT_STAGE='Check administrator capability'
    local current_user
    current_user="$(id -un)"
    if ! /usr/sbin/dseditgroup -o checkmember -m "$current_user" admin 2>/dev/null |
            /usr/bin/grep -q 'yes'; then
        it140_abort 3 'The account running this script must be an Administrator account.'
    fi
}

it140_check_disk_space() {
    IT140_CURRENT_STAGE='Check available storage'
    local available_kb available_bytes
    available_kb="$(/bin/df -Pk "$HOME" | /usr/bin/awk 'NR == 2 {print $4}')"
    if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
        it140_abort 1 'Available storage could not be determined.'
    fi
    available_bytes=$((available_kb * 1024))
    if (( available_bytes < IT140_MINIMUM_FREE_SPACE_BYTES )); then
        it140_abort 1 'At least 5 GB of available storage is required before continuing.'
    fi
    it140_info "Available storage: $((available_bytes / 1024 / 1024 / 1024)) GB"
}

it140_network_probe() {
    IT140_CURRENT_STAGE='Check approved network source'
    local attempt=1
    local delay="$IT140_RETRY_INITIAL_DELAY_SECONDS"
    while (( attempt <= IT140_RETRY_MAXIMUM_ATTEMPTS )); do
        if /usr/bin/curl --fail --silent --show-error --location \
                --connect-timeout 15 --max-time "$IT140_NETWORK_TIMEOUT_SECONDS" \
                --output /dev/null 'https://github.com/GC-STEM/it140'; then
            return 0
        fi
        if (( attempt < IT140_RETRY_MAXIMUM_ATTEMPTS )); then
            it140_warning "Network probe attempt ${attempt} failed; retrying in ${delay} seconds."
            /bin/sleep "$delay"
            delay=$((delay * 2))
            (( delay > 60 )) && delay=60
        fi
        attempt=$((attempt + 1))
    done
    it140_abort 4 'The approved GitHub source was unavailable after bounded retries.'
}

it140_download() {
    local url="$1"
    local destination="$2"
    local description="$3"
    local attempt=1
    local delay="$IT140_RETRY_INITIAL_DELAY_SECONDS"
    while (( attempt <= IT140_RETRY_MAXIMUM_ATTEMPTS )); do
        it140_info "Downloading ${description} (attempt ${attempt}/${IT140_RETRY_MAXIMUM_ATTEMPTS})."
        if /usr/bin/curl --fail --silent --show-error --location \
                --connect-timeout 20 --max-time 300 \
                --output "$destination" "$url"; then
            return 0
        fi
        /bin/rm -f -- "$destination"
        if (( attempt < IT140_RETRY_MAXIMUM_ATTEMPTS )); then
            /bin/sleep "$delay"
            delay=$((delay * 2))
            (( delay > 60 )) && delay=60
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

it140_find_brew() {
    if [[ -x '/opt/homebrew/bin/brew' ]]; then
        printf '%s' '/opt/homebrew/bin/brew'
        return 0
    fi
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi
    return 1
}

it140_activate_brew_environment() {
    local brew_path="$1"
    eval "$("$brew_path" shellenv)"
}

it140_make_list_file() {
    local query="$1"
    local path
    [[ -n "$IT140_RUNTIME_TEMP_DIR" && -d "$IT140_RUNTIME_TEMP_DIR" ]] || \
        it140_abort 1 'The private runtime staging directory is unavailable.'
    path="$IT140_RUNTIME_TEMP_DIR/${query}.$$.txt"
    if ! it140_manifest_tool "$query" > "$path"; then
        it140_abort 5 "The manifest query failed: ${query}."
    fi
    printf '%s' "$path"
}

it140_replace_managed_environment_block() {
    IT140_CURRENT_STAGE='Configure the user PATH'
    local temp_file
    temp_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/it140-zshrc.XXXXXX")"
    it140_register_temp "$temp_file"
    [[ -e "$IT140_SHELL_STARTUP_FILE" ]] || : > "$IT140_SHELL_STARTUP_FILE"
    /usr/bin/awk \
        -v start="$IT140_MANAGED_ENV_START" \
        -v finish="$IT140_MANAGED_ENV_END" '
        $0 == start {inside=1; next}
        $0 == finish {inside=0; next}
        !inside {print}
    ' "$IT140_SHELL_STARTUP_FILE" > "$temp_file"
    cat >> "$temp_file" <<'ENV'

# >>> IT 140 Course IDE managed environment >>>
export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:$PATH"
# <<< IT 140 Course IDE managed environment <<<
ENV
    /bin/chmod -- 0600 "$temp_file"
    if /usr/bin/cmp -s "$temp_file" "$IT140_SHELL_STARTUP_FILE"; then
        /bin/rm -f -- "$temp_file"
    else
        /bin/mv -f -- "$temp_file" "$IT140_SHELL_STARTUP_FILE"
        IT140_CHANGED=true
    fi
    export PATH="$IT140_VENV_DIR/bin:$IT140_PLATFORM_SCRIPT_DIR:/opt/homebrew/bin:$PATH"
    hash -r
}

it140_merge_vscode_settings() {
    local python_path="$1"
    local expected_json expected_file
    expected_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/it140-vscode-settings.XXXXXX")"
    it140_register_temp "$expected_file"
    if ! expected_json="$(it140_manifest_tool vscode_settings_json)"; then
        it140_abort 5 'The manifest-managed VS Code settings could not be read.'
    fi
    printf '%s\n' "$expected_json" > "$expected_file"
    /bin/mkdir -p -- "$(/usr/bin/dirname "$IT140_VSCODE_SETTINGS_FILE")"

    if ! "$python_path" - "$IT140_VSCODE_SETTINGS_FILE" "$expected_file" <<'PYSET'
import json
import os
import pathlib
import sys
import tempfile

settings_path = pathlib.Path(sys.argv[1])
expected_path = pathlib.Path(sys.argv[2])
expected = json.loads(expected_path.read_text(encoding='utf-8'))
if settings_path.exists():
    try:
        observed = json.loads(settings_path.read_text(encoding='utf-8'))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'existing VS Code settings are invalid JSON: {exc}')
    if not isinstance(observed, dict):
        raise SystemExit('existing VS Code settings must be a JSON object')
else:
    observed = {}

for key, value in expected.items():
    if isinstance(value, dict) and isinstance(observed.get(key), dict):
        merged = dict(observed[key])
        merged.update(value)
        observed[key] = merged
    else:
        observed[key] = value

settings_path.parent.mkdir(parents=True, exist_ok=True)
fd, temp_name = tempfile.mkstemp(prefix='.it140-settings-', dir=settings_path.parent)
try:
    with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
        json.dump(observed, stream, indent=4, sort_keys=True)
        stream.write('\n')
    os.chmod(temp_name, 0o600)
    os.replace(temp_name, settings_path)
finally:
    if os.path.exists(temp_name):
        os.unlink(temp_name)
PYSET
    then
        it140_abort 7 'VS Code settings could not be merged safely. The existing file was preserved when possible.'
    fi
    IT140_CHANGED=true
}

it140_configure_workspace_settings() {
    local python_path="$1"
    local workspace_dir="${IT140_COURSE_ROOT}/.vscode"
    local workspace_file="${workspace_dir}/settings.json"
    /bin/mkdir -p -- "$workspace_dir"
    if ! "$python_path" - "$workspace_file" "$IT140_VENV_DIR/bin/python" <<'PYWORK'
import json
import os
import pathlib
import sys
import tempfile

path = pathlib.Path(sys.argv[1])
venv_python = sys.argv[2]
if path.exists():
    try:
        values = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'existing workspace settings are invalid JSON: {exc}')
    if not isinstance(values, dict):
        raise SystemExit('workspace settings must be a JSON object')
else:
    values = {}
values.update({
    'python.defaultInterpreterPath': venv_python,
    'python.terminal.activateEnvironment': True,
    'python.testing.pytestEnabled': True,
    'python.testing.unittestEnabled': False,
})
fd, temp_name = tempfile.mkstemp(prefix='.it140-workspace-', dir=path.parent)
try:
    with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
        json.dump(values, stream, indent=4, sort_keys=True)
        stream.write('\n')
    os.chmod(temp_name, 0o600)
    os.replace(temp_name, path)
finally:
    if os.path.exists(temp_name):
        os.unlink(temp_name)
PYWORK
    then
        it140_abort 7 'The course workspace settings could not be configured safely.'
    fi
    IT140_CHANGED=true
}


it140_parse_options "$@"
it140_initialize_log
it140_prune_logs
it140_check_platform_base
it140_load_manifest
it140_check_admin_account
it140_check_disk_space
it140_network_probe
it140_acquire_lock

it140_header 'Stage 1: Apple Command Line Tools'
IT140_CURRENT_STAGE='Install or verify Apple Command Line Tools'
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    if [[ "$IT140_NONINTERACTIVE" == true ]]; then
        it140_abort 3 'Apple Command Line Tools are missing and require an interactive installation.'
    fi
    it140_notice 'macOS will open the Apple Command Line Tools installer.'
    it140_notice 'Complete the installer, then rerun install_it140.zsh in a new Terminal window.'
    /usr/bin/xcode-select --install >/dev/tty 2>&1 || true
    it140_finish 7 'PARTIAL' \
        'Apple Command Line Tools installation was requested and must finish before Install can continue.' \
        'After the installer finishes, rerun: "$HOME/it140/scripts/mac/install_it140.zsh"'
fi
it140_success 'Apple Command Line Tools are available.'

it140_header 'Stage 2: Homebrew'
IT140_CURRENT_STAGE='Install or verify Homebrew'
BREW_PATH=''
if ! BREW_PATH="$(it140_find_brew)"; then
    it140_notice 'Homebrew is required. The official installer may request the password for the current Administrator account.'
    INSTALLER_PATH="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/it140-homebrew-install.XXXXXX")"
    it140_register_temp "$INSTALLER_PATH"
    if ! it140_download \
            'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' \
            "$INSTALLER_PATH" 'the official Homebrew installer'; then
        it140_abort 4 'The official Homebrew installer was unavailable after bounded retries.'
    fi
    /bin/chmod -- 0700 "$INSTALLER_PATH"
    if [[ "$IT140_NONINTERACTIVE" == true ]]; then
        if ! NONINTERACTIVE=1 /bin/bash "$INSTALLER_PATH"; then
            it140_abort 3 'Homebrew could not be installed noninteractively with the available privileges.'
        fi
    else
        if ! /bin/bash "$INSTALLER_PATH" </dev/tty >/dev/tty 2>/dev/tty; then
            it140_abort 1 'The Homebrew installation did not complete.'
        fi
    fi
    IT140_CHANGED=true
    if ! BREW_PATH="$(it140_find_brew)"; then
        it140_abort 1 'Homebrew was not found after its installer completed.'
    fi
else
    it140_success 'Homebrew is already installed.'
fi
it140_activate_brew_environment "$BREW_PATH"

it140_header 'Stage 3: Manifest-Declared System Software'
IT140_CURRENT_STAGE='Refresh Homebrew metadata'
if ! "$BREW_PATH" update; then
    it140_abort 4 'Homebrew package metadata could not be refreshed.'
fi

FORMULAE_FILE="$(it140_make_list_file system_formulae)"
while IFS= read -r package_id; do
    [[ -n "$package_id" ]] || continue
    IT140_CURRENT_STAGE="Install Homebrew formula ${package_id}"
    if "$BREW_PATH" list --formula "$package_id" >/dev/null 2>&1; then
        it140_info "Homebrew formula already installed: ${package_id}"
    else
        it140_info "Installing Homebrew formula: ${package_id}"
        if ! "$BREW_PATH" install "$package_id"; then
            it140_abort 1 "Required Homebrew formula could not be installed: ${package_id}."
        fi
        IT140_CHANGED=true
    fi
done < "$FORMULAE_FILE"

CASKS_FILE="$(it140_make_list_file system_casks)"
while IFS= read -r package_id; do
    [[ -n "$package_id" ]] || continue
    IT140_CURRENT_STAGE="Install Homebrew cask ${package_id}"
    if "$BREW_PATH" list --cask "$package_id" >/dev/null 2>&1; then
        it140_info "Homebrew cask already installed: ${package_id}"
    else
        it140_info "Installing Homebrew cask: ${package_id}"
        if ! "$BREW_PATH" install --cask "$package_id"; then
            it140_abort 1 "Required Homebrew cask could not be installed: ${package_id}."
        fi
        IT140_CHANGED=true
    fi
done < "$CASKS_FILE"

it140_header 'Stage 4: Post-Installation Validation'
IT140_CURRENT_STAGE='Validate required system commands'
COMMANDS_FILE="$(it140_make_list_file system_commands)"
while IFS= read -r command_name; do
    [[ -n "$command_name" ]] || continue
    if ! command -v "$command_name" >/dev/null 2>&1; then
        it140_abort 1 "Required command is unavailable after installation: ${command_name}."
    fi
    it140_success "Required command available: ${command_name}"
done < "$COMMANDS_FILE"

PYTHON_COMMAND="$(it140_manifest_tool python_executable)"
if ! command -v "$PYTHON_COMMAND" >/dev/null 2>&1; then
    it140_abort 1 "The manifest-selected Python command is unavailable: ${PYTHON_COMMAND}."
fi
PYTHON_VERSION="$("$(command -v "$PYTHON_COMMAND")" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
if [[ "$PYTHON_VERSION" != 3.12.* ]]; then
    it140_abort 1 "Python ${PYTHON_VERSION} is outside the required 3.12 compatible range."
fi
it140_success "Python ${PYTHON_VERSION} satisfies the course runtime requirement."

it140_finish 0 'PASS' \
    'The macOS system layer is installed and passed post-installation checks.' \
    'Run next: "$HOME/it140/scripts/mac/configure_it140.zsh"'
