#!/usr/bin/env bash
#
# IT 140 Codio Virtual Desktop user configuration and repair script
#
# Traceability: CFG-FR-001 through CFG-FR-016; CFG-DES-001 through CFG-DES-016
# Scope: Current-user folders, PATH, provider authentication, Git identity and
#        settings, course virtual environment, IDE extensions and settings,
#        desktop launchers, panel integration, and file associations.
# Excludes: System package, repository, policy, and system application changes.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="2026.07.26.2"
readonly PLATFORM_ID="cvd"
readonly DEPLOYMENT_PROFILE_ID="codio_cvd"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly PLATFORM_SCRIPT_DIR="${SCRIPT_ROOT}/${PLATFORM_ID}"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/configure_${PLATFORM_ID}_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly LOCK_FILE="${HOME}/.cache/it140-${PLATFORM_ID}-mutation.lock"
readonly MANAGED_PATH_START="# >>> IT 140 managed PATH >>>"
readonly MANAGED_PATH_END="# <<< IT 140 managed PATH <<<"
readonly MANAGED_PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/cvd:$PATH"'

NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
START_EPOCH="$(date +%s)"
WARNINGS=0

print_header() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

print_info() { printf '[INFO] %s\n' "$1"; }
print_success() { printf '[SUCCESS] %s\n' "$1"; }
print_notice() { printf '[NOTICE] %s\n' "$1"; }
print_warning() { printf '[WARNING] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
print_error() { printf '[ERROR] %s\n' "$1" >&2; }

usage() {
    cat <<USAGE
Usage: configure_cvd.sh [--help] [--version] [--noninteractive]
                        [--deployment-profile codio_cvd]

Configures or repairs the current user's IT 140 environment. Run as the
standard Codio desktop user, not with sudo.

In noninteractive mode, an existing provider login is required and the
provider username is used as the Git display name.

Log directory: ~/it140/logs/
USAGE
}

parse_options() {
    while (($#)); do
        case "$1" in
            --help|-h)
                usage
                exit 0
                ;;
            --version)
                printf '%s\n' "$SCRIPT_VERSION"
                exit 0
                ;;
            --noninteractive)
                NONINTERACTIVE=true
                ;;
            --deployment-profile)
                shift
                [[ $# -gt 0 ]] || {
                    print_error "Missing deployment profile."
                    exit 2
                }
                REQUESTED_PROFILE="$1"
                ;;
            *)
                print_error "Unsupported option: $1"
                usage >&2
                exit 2
                ;;
        esac
        shift
    done
}

on_error() {
    local status=$?
    local line=${BASH_LINENO[0]:-unknown}
    print_error "Configuration stopped near line ${line} with exit status ${status}."
    print_error "Review the log: ${LOG_FILE}"
    if [[ "$CHANGED" == true ]]; then
        exit 7
    fi
    exit 1
}

on_interrupt() {
    print_error "Configuration was canceled. Rerun configure_cvd.sh to continue."
    if [[ "$CHANGED" == true ]]; then
        exit 7
    fi
    exit 6
}

validate_manifest() {
    python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" \
        "$REQUESTED_PROFILE" <<'PY'
import json
import pathlib
import sys

manifest_path, schema_path, platform_id, profile_id = sys.argv[1:]


class DuplicateKeyError(ValueError):
    pass


def no_duplicates(pairs):
    output = {}
    for key, value in pairs:
        if key in output:
            raise DuplicateKeyError(f"duplicate key: {key}")
        output[key] = value
    return output


try:
    manifest = json.loads(
        pathlib.Path(manifest_path).read_text(encoding="utf-8"),
        object_pairs_hook=no_duplicates,
    )
    schema = json.loads(
        pathlib.Path(schema_path).read_text(encoding="utf-8"),
        object_pairs_hook=no_duplicates,
    )
except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError) as exc:
    raise SystemExit(f"manifest validation failed: {exc}")

required = {
    "schema_version", "automation_release", "policy", "platforms",
    "deployment_profiles", "provider_profiles", "managed_settings",
}
missing = sorted(required - manifest.keys())
if missing:
    raise SystemExit(f"manifest missing required keys: {', '.join(missing)}")
if manifest["schema_version"] != "1.0":
    raise SystemExit("unsupported manifest schema version")
if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
    raise SystemExit("schema is not the approved Draft 2020-12 format")
platform = manifest["platforms"].get(platform_id)
profile = manifest["deployment_profiles"].get(profile_id)
if not platform or not platform.get("enabled"):
    raise SystemExit("CVD platform is not enabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("CVD deployment profile is invalid")
if "github_com" not in manifest["provider_profiles"]:
    raise SystemExit("required provider profile is unavailable")

try:
    import jsonschema  # type: ignore
except ImportError:
    pass
else:
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(manifest)

print(manifest["automation_release"])
PY
}

manifest_lines() {
    local query="$1"
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$query" <<'PY'
import json
import sys

path, platform_id, query = sys.argv[1:]
manifest = json.load(open(path, encoding="utf-8"))
platform = manifest["platforms"][platform_id]
bindings = platform["course_ide_bindings"]

if query == "system_commands":
    for binding in bindings.values():
        if binding.get("required") and binding.get("installation_scope") == "system":
            for executable in binding.get("verification", {}).get("executable_names", []):
                print(executable)
elif query == "venv_packages":
    packages = []
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "python_venv_package"):
            packages.append(binding["package_identifier"])
    # Expose Ruff in the course virtual environment as well as through VS Code.
    if bindings.get("code_quality_tool", {}).get("required"):
        packages.append("ruff")
    for package in sorted(set(packages)):
        print(package)
elif query == "extensions":
    for binding in bindings.values():
        if (binding.get("required") and
                binding.get("installation_scope") == "user" and
                binding.get("installer_adapter_id") == "vscode_extension"):
            print(binding["package_identifier"])
elif query == "git_settings":
    profile_ids = bindings["version_control_system"].get("settings_profile_ids", [])
    for profile_id in profile_ids:
        values = manifest["managed_settings"][profile_id]["values"]
        for key, value in values.items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            print(f"{key}\t{value}")
else:
    raise SystemExit(f"unsupported manifest query: {query}")
PY
}

check_platform_and_user() {
    if [[ "$EUID" -eq 0 ]]; then
        print_error "Do not run configure_cvd.sh with sudo."
        print_error "Personal settings must be saved under the standard Codio account."
        exit 2
    fi

    [[ -r /etc/os-release ]] || {
        print_error "Cannot identify the operating system."
        exit 2
    }
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != 24.04 ]]; then
        print_error "This script supports only the IT 140 Ubuntu 24.04 CVD."
        print_error "Detected: ${PRETTY_NAME:-unknown operating system}"
        exit 2
    fi

    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" != amd64 && "$architecture" != x86_64 ]]; then
        print_error "This CVD release supports only x86_64. Detected: $architecture"
        exit 2
    fi

    command -v xfconf-query >/dev/null 2>&1 || {
        print_error "The Xfce desktop tools required by the CVD are unavailable."
        exit 2
    }
}

check_system_layer() {
    local command_name failed=0
    mapfile -t system_commands < <(manifest_lines system_commands)
    for command_name in "${system_commands[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            print_error "Required system command is missing: $command_name"
            failed=1
        fi
    done
    if ! command -v python3.12 >/dev/null 2>&1; then
        print_error "Required system command is missing: python3.12"
        failed=1
    fi
    if ((failed)); then
        print_error "The CVD system layer is incomplete. Run update_cvd.sh."
        print_error "If update_cvd.sh already passed, contact course support."
        exit 1
    fi
    print_success "Required system components are present."
}

acquire_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    if ! flock --nonblock 9; then
        print_error "Another IT 140 user-configuration operation is running."
        exit 1
    fi
}

upsert_managed_path_block() {
    local file="$1"
    python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
start = "# >>> IT 140 managed PATH >>>"
end = "# <<< IT 140 managed PATH <<<"
block = (
    f"{start}\n"
    'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/cvd:$PATH"\n'
    f"{end}\n"
)
text = path.read_text(encoding="utf-8") if path.exists() else ""
if start in text and end in text:
    before = text.split(start, 1)[0].rstrip("\n")
    after = text.split(end, 1)[1].lstrip("\n")
    text = (before + "\n\n" if before else "") + block
    if after:
        text += "\n" + after
else:
    if text and not text.endswith("\n"):
        text += "\n"
    if text:
        text += "\n"
    text += block
path.parent.mkdir(parents=True, exist_ok=True)
temp = path.with_name(path.name + ".it140.tmp")
try:
    temp.write_text(text, encoding="utf-8", newline="\n")
    temp.replace(path)
finally:
    if temp.exists():
        temp.unlink()
PY
}

has_managed_path_block() {
    local file="$1"
    [[ -r "$file" ]] || return 1
    grep -Fqx "$MANAGED_PATH_START" "$file" \
        && grep -Fqx "$MANAGED_PATH_EXPORT" "$file" \
        && grep -Fqx "$MANAGED_PATH_END" "$file"
}

has_valid_vscode_settings() {
    local settings_file="$HOME/.config/Code/User/settings.json"
    [[ -r "$settings_file" ]] || return 1
    python3 - "$settings_file" "$VENV_DIR/bin/python" "$COURSE_ROOT" <<'PY'
import json
import pathlib
import sys

settings_path, expected_python, expected_root = sys.argv[1:]
try:
    settings = json.loads(pathlib.Path(settings_path).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)

if not isinstance(settings, dict):
    raise SystemExit(1)
if settings.get("python.defaultInterpreterPath") != expected_python:
    raise SystemExit(1)
if settings.get("files.defaultFolder") != expected_root:
    raise SystemExit(1)
PY
}

has_managed_panel_launcher() {
    local panel_config_dir="$HOME/.config/xfce4/panel"
    local marker="$panel_config_dir/it140-vscode-plugin-id"
    local plugin_id
    [[ -s "$marker" ]] || return 1
    plugin_id="$(<"$marker")"
    [[ "$plugin_id" =~ ^[0-9]+$ ]] || return 1
    [[ -r "$panel_config_dir/launcher-$plugin_id/it140-vscode.desktop" ]]
}

configure_course_folders_and_path() {
    print_info "Creating or repairing course folders without deleting existing content..."
    mkdir -p "$COURSE_ROOT" "$LOG_DIR" "$PLATFORM_SCRIPT_DIR"
    chmod 0700 "$LOG_DIR"

    upsert_managed_path_block "$HOME/.profile"
    upsert_managed_path_block "$HOME/.bashrc"
    case ":$PATH:" in
        *":$VENV_DIR/bin:"*) ;;
        *) export PATH="$VENV_DIR/bin:$PATH" ;;
    esac
    case ":$PATH:" in
        *":$PLATFORM_SCRIPT_DIR:"*) ;;
        *) export PATH="$PLATFORM_SCRIPT_DIR:$PATH" ;;
    esac
    hash -r

    find "$PLATFORM_SCRIPT_DIR" -maxdepth 1 -type f -name '*_cvd.sh' \
        -exec chmod 0755 {} + 2>/dev/null || true
    CHANGED=true
    print_success "Course folders, script permissions, and PATH entries are configured."
}

configure_provider_identity() {
    print_header "Step 2: Source-Code Hosting Authentication and Identity"
    print_info "Checking GitHub authentication status..."

    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        if [[ "$NONINTERACTIVE" == true ]]; then
            print_error "GitHub authentication is required but interaction is disabled."
            exit 6
        fi

        print_notice "GitHub CLI will copy a one-time code to the clipboard and display a web address."
        print_notice " - Right-click the web address and select Open Link."
        print_notice " - Paste the one-time code when prompted into the browser."
        print_notice " - Complete the browser steps, and then return to this terminal."
        printf '[ACTION REQUIRED] Press Enter to begin, or type C to cancel: '
        read -r response
        if [[ "${response,,}" == c ]]; then
            exit 6
        fi

        gh auth login --hostname github.com --git-protocol https --web --clipboard
        CHANGED=true
    fi

    gh auth status --hostname github.com >/dev/null 2>&1 || {
        print_error "GitHub authentication did not complete successfully."
        exit 1
    }
    print_success "GitHub authentication is valid."

    local gh_id gh_user display_name default_display_name private_email
    gh_id="$(gh api user --jq '.id')"
    gh_user="$(gh api user --jq '.login')"
    [[ "$gh_id" =~ ^[0-9]+$ ]] || {
        print_error "GitHub account ID is invalid."
        exit 1
    }
    [[ "$gh_user" =~ ^[A-Za-z0-9-]+$ ]] || {
        print_error "GitHub username is invalid."
        exit 1
    }
    private_email="${gh_id}+${gh_user}@users.noreply.github.com"
    default_display_name="$(git config --global user.name 2>/dev/null || true)"
    default_display_name="${default_display_name:-$gh_user}"

    if [[ "$NONINTERACTIVE" == true ]]; then
        display_name="$default_display_name"
    else
        print_notice "Your Git display name is public in version-control history."
        printf '[ACTION REQUIRED] Git display name [%s]: ' "$default_display_name"
        read -r display_name
        display_name="${display_name:-$default_display_name}"
    fi

    if [[ -z "$display_name" || ${#display_name} -gt 100 \
        || "$display_name" == *$'\n'* || "$display_name" == *$'\r'* ]]; then
        print_error "The Git display name is invalid."
        exit 1
    fi

    git config --global user.name "$display_name"
    git config --global user.email "$private_email"

    while IFS=$'\t' read -r key value; do
        [[ -n "$key" ]] || continue
        git config --global "$key" "$value"
    done < <(manifest_lines git_settings)

    CHANGED=true
    print_success "Git identity and course defaults are configured."
    print_info "Git display name : $display_name"
    print_info "Commit identity  : GitHub private noreply identity"
    print_info "GitHub account   : $gh_user"
}

configure_user_tools() {
    print_header "Step 3: Course Python Tools and IDE Extensions"

    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        print_info "Creating the IT 140 course virtual environment..."
        python3.12 -m venv "$VENV_DIR"
        CHANGED=true
    else
        print_success "The IT 140 course virtual environment is available."
    fi

    local package extension installed_extensions
    local -a missing_packages=() required_extensions=() missing_extensions=()

    mapfile -t venv_packages < <(manifest_lines venv_packages)
    for package in "${venv_packages[@]}"; do
        if ! "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done
    if ((${#missing_packages[@]})); then
        print_info "Installing missing course Python tools..."
        "$VENV_DIR/bin/python" -m pip install "${missing_packages[@]}"
        CHANGED=true
    else
        print_success "Required course Python tools are already installed."
    fi

    installed_extensions="$(NODE_NO_WARNINGS=1 code --list-extensions 2>/dev/null \
        | tr '[:upper:]' '[:lower:]')"
    mapfile -t required_extensions < <(manifest_lines extensions)
    for extension in "${required_extensions[@]}"; do
        if ! grep -Fxq "${extension,,}" <<<"$installed_extensions"; then
            missing_extensions+=("$extension")
        fi
    done
    if ((${#missing_extensions[@]})); then
        print_info "Installing missing required IDE extensions..."
        for extension in "${missing_extensions[@]}"; do
            NODE_NO_WARNINGS=1 code --install-extension "$extension"
        done
        CHANGED=true
    else
        print_success "Required IDE extensions are already installed."
    fi

    print_success "Required user-scoped tools and IDE extensions are configured."
}

merge_vscode_settings() {
    local settings_dir="$HOME/.config/Code/User"
    local settings_file="$settings_dir/settings.json"
    mkdir -p "$settings_dir"

    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$settings_file" \
        "$VENV_DIR/bin/python" "$COURSE_ROOT" "$LOG_DIR" <<'PY'
import json
import pathlib
import sys

manifest_path, platform_id, settings_path, python_path, course_root, log_dir = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
settings_file = pathlib.Path(settings_path)
settings_file.parent.mkdir(parents=True, exist_ok=True)

bindings = manifest["platforms"][platform_id]["course_ide_bindings"]
profile_ids = bindings["source_code_ide"].get("settings_profile_ids", [])
managed = {}
for profile_id in profile_ids:
    managed.update(manifest["managed_settings"][profile_id]["values"])

managed.update({
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "files.trimTrailingWhitespace": True,
    "files.insertFinalNewline": True,
    "terminal.integrated.defaultProfile.linux": "bash",
    "python.defaultInterpreterPath": python_path,
    "python.testing.pytestArgs": ["."],
    "cSpell.language": "en",
    "files.defaultFolder": course_root,
    "workbench.editorAssociations": {
        "README.md": "vscode.markdown.preview.editor",
        "*_srs.md": "vscode.markdown.preview.editor",
        "*_sdd.md": "vscode.markdown.preview.editor",
    },
    "settingsSync.ignoredSettings": [
        "python.defaultInterpreterPath",
        "files.defaultFolder",
    ],
})

existing = {}
if settings_file.exists() and settings_file.stat().st_size:
    try:
        existing = json.loads(settings_file.read_text(encoding="utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        diagnostic = pathlib.Path(log_dir) / "invalid_vscode_settings_diagnostic.txt"
        diagnostic.write_text(
            "The existing VS Code settings file is invalid and was not changed.\n"
            f"Settings path: {settings_file}\n"
            f"Parser result: {type(exc).__name__}\n",
            encoding="utf-8",
            newline="\n",
        )
        raise SystemExit(
            "Existing VS Code settings are invalid. The original file was preserved; "
            f"a content-free diagnostic was written to {diagnostic}."
        )
if not isinstance(existing, dict):
    raise SystemExit("Existing VS Code settings must be a JSON object")


def deep_merge(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = value


deep_merge(existing, managed)
serialized = json.dumps(existing, indent=4, ensure_ascii=False) + "\n"
temp = settings_file.with_name(settings_file.name + ".it140.tmp")
try:
    temp.write_text(serialized, encoding="utf-8", newline="\n")
    json.loads(temp.read_text(encoding="utf-8"))
    temp.replace(settings_file)
finally:
    if temp.exists():
        temp.unlink()
PY

    CHANGED=true
    print_success "Course-managed IDE settings were merged without removing unrelated settings."
}

set_xfconf_bool() {
    local property="$1" value="$2"
    if xfconf-query -c xfce4-desktop -p "$property" >/dev/null 2>&1; then
        xfconf-query -c xfce4-desktop -p "$property" -s "$value"
    else
        xfconf-query -c xfce4-desktop -p "$property" -n -t bool -s "$value"
    fi
}

set_xfconf_string() {
    local channel="$1" property="$2" value="$3"
    if xfconf-query -c "$channel" -p "$property" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$property" -s "$value"
    else
        xfconf-query -c "$channel" -p "$property" -n -t string -s "$value"
    fi
}

configure_desktop_integrations() {
    print_header "Step 4: CVD Desktop Integration"

    local desktop_dir panel_config_dir directory_plugin_id course_panel_id
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    desktop_dir="${desktop_dir:-$HOME/Desktop}"
    panel_config_dir="$HOME/.config/xfce4/panel"
    mkdir -p "$desktop_dir" "$panel_config_dir"

    set_xfconf_bool /desktop-icons/file-icons/show-filesystem false
    set_xfconf_bool /desktop-icons/file-icons/show-home false

    cat > "$desktop_dir/it140.desktop" <<EOF_FOLDER
[Desktop Entry]
Version=1.0
Type=Application
Name=it140
Comment=Open the IT 140 course directory
Exec=exo-open --launch FileManager "$COURSE_ROOT"
Icon=folder
Terminal=false
StartupNotify=true
EOF_FOLDER

    if [[ -f /usr/share/applications/code.desktop ]]; then
        install -m 0755 /usr/share/applications/code.desktop \
            "$desktop_dir/visual-studio-code.desktop"
    else
        print_warning "The system VS Code launcher was not found."
    fi
    chmod 0755 "$desktop_dir/it140.desktop"

    local launcher checksum
    for launcher in "$desktop_dir/it140.desktop" \
        "$desktop_dir/visual-studio-code.desktop"; do
        [[ -f "$launcher" ]] || continue
        if command -v desktop-file-validate >/dev/null 2>&1; then
            desktop-file-validate "$launcher"
        fi
        if command -v gio >/dev/null 2>&1; then
            checksum="$(sha256sum "$launcher" | awk '{print $1}')"
            gio set --type=string "$launcher" \
                metadata::xfce-exe-checksum "$checksum" 2>/dev/null \
                || print_warning "Could not mark $(basename "$launcher") as trusted."
        fi
    done

    directory_plugin_id="$(
        xfconf-query -c xfce4-panel -p /plugins -l -v 2>/dev/null \
        | awk '$NF == "directorymenu" {sub(/^.*plugin-/, "", $1); print $1; exit}'
    )"
    if [[ -n "$directory_plugin_id" ]]; then
        set_xfconf_string xfce4-panel \
            "/plugins/plugin-$directory_plugin_id/base-directory" "$COURSE_ROOT"
    else
        print_warning "The Xfce Directory Menu plugin was not found."
    fi

    course_panel_id=""
    if [[ -n "$directory_plugin_id" ]]; then
        local panel_id existing_id candidate last_plugin_id
        local -a panel_ids=() plugin_ids=() updated_plugin_ids=() panel_args=()
        mapfile -t panel_ids < <(
            xfconf-query -c xfce4-panel -p /panels 2>/dev/null \
            | awk '$1 ~ /^[0-9]+$/ {print $1}'
        )
        for panel_id in "${panel_ids[@]}"; do
            mapfile -t plugin_ids < <(
                xfconf-query -c xfce4-panel \
                    -p "/panels/panel-$panel_id/plugin-ids" 2>/dev/null \
                | awk '$1 ~ /^[0-9]+$/ {print $1}'
            )
            if printf '%s\n' "${plugin_ids[@]}" \
                | grep -Fxq "$directory_plugin_id"; then
                course_panel_id="$panel_id"
                break
            fi
        done
    fi

    if [[ -n "$course_panel_id" && -f /usr/share/applications/code.desktop ]]; then
        local marker plugin_id launcher_dir launcher_name items_property panel_property
        marker="$panel_config_dir/it140-vscode-plugin-id"
        plugin_id=""
        if [[ -s "$marker" ]]; then
            candidate="$(<"$marker")"
            if [[ "$candidate" =~ ^[0-9]+$ ]] && \
                [[ "$(xfconf-query -c xfce4-panel \
                    -p "/plugins/plugin-$candidate" 2>/dev/null || true)" == launcher ]]; then
                plugin_id="$candidate"
            fi
        fi
        if [[ -z "$plugin_id" ]]; then
            last_plugin_id="$(
                xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null \
                | sed -n 's#^/plugins/plugin-\([0-9][0-9]*\).*#\1#p' \
                | sort -n | tail -1
            )"
            plugin_id="$(( ${last_plugin_id:-0} + 1 ))"
            printf '%s\n' "$plugin_id" > "$marker"
        fi

        launcher_name="it140-vscode.desktop"
        launcher_dir="$panel_config_dir/launcher-$plugin_id"
        mkdir -p "$launcher_dir"
        install -m 0644 /usr/share/applications/code.desktop \
            "$launcher_dir/$launcher_name"
        set_xfconf_string xfce4-panel "/plugins/plugin-$plugin_id" launcher

        items_property="/plugins/plugin-$plugin_id/items"
        xfconf-query -c xfce4-panel -p "$items_property" -r 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "$items_property" -n -a \
            -t string -s "$launcher_name"

        panel_property="/panels/panel-$course_panel_id/plugin-ids"
        mapfile -t plugin_ids < <(
            xfconf-query -c xfce4-panel -p "$panel_property" 2>/dev/null \
            | awk '$1 ~ /^[0-9]+$/ {print $1}'
        )
        updated_plugin_ids=()
        for existing_id in "${plugin_ids[@]}"; do
            [[ "$existing_id" == "$plugin_id" ]] || updated_plugin_ids+=("$existing_id")
        done
        updated_plugin_ids+=("$plugin_id")
        xfconf-query -c xfce4-panel -p "$panel_property" -r
        panel_args=()
        for existing_id in "${updated_plugin_ids[@]}"; do
            panel_args+=(-t int -s "$existing_id")
        done
        xfconf-query -c xfce4-panel -p "$panel_property" -n -a "${panel_args[@]}"
    else
        print_warning "The VS Code panel launcher could not be configured."
    fi

    local mime_type
    for mime_type in text/plain text/markdown text/x-python text/x-shellscript; do
        xdg-mime default code.desktop "$mime_type"
    done

    xfdesktop --reload 2>/dev/null || true
    xfce4-panel -r 2>/dev/null || true
    CHANGED=true
    print_success "Course desktop launchers and file associations are configured."
}

post_validate() {
    local failed=0 package extension configured_email

    [[ -d "$COURSE_ROOT" && -d "$LOG_DIR" && -x "$VENV_DIR/bin/python" ]] || {
        print_error "Required course folders or virtual environment are missing."
        failed=1
    }

    has_managed_path_block "$HOME/.profile" || {
        print_error "The managed PATH block is missing from ~/.profile."
        failed=1
    }
    has_managed_path_block "$HOME/.bashrc" || {
        print_error "The managed PATH block is missing from ~/.bashrc."
        failed=1
    }

    mapfile -t venv_packages < <(manifest_lines venv_packages)
    for package in "${venv_packages[@]}"; do
        if ! "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
            print_error "Required course Python package is missing: $package"
            failed=1
        fi
    done

    local installed_extensions
    installed_extensions="$(NODE_NO_WARNINGS=1 code --list-extensions 2>/dev/null \
        | tr '[:upper:]' '[:lower:]')"
    mapfile -t required_extensions < <(manifest_lines extensions)
    for extension in "${required_extensions[@]}"; do
        if ! grep -Fxq "${extension,,}" <<<"$installed_extensions"; then
            print_error "Required IDE extension is missing: $extension"
            failed=1
        fi
    done

    gh auth status --hostname github.com >/dev/null 2>&1 || {
        print_error "GitHub authentication is not valid."
        failed=1
    }
    [[ -n "$(git config --global user.name 2>/dev/null || true)" ]] || {
        print_error "Git display name is not configured."
        failed=1
    }
    configured_email="$(git config --global user.email 2>/dev/null || true)"
    [[ "$configured_email" =~ ^[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$ ]] || {
        print_error "Git does not use the approved private commit identity."
        failed=1
    }

    has_valid_vscode_settings || {
        print_error "VS Code does not contain the required IT 140 settings."
        failed=1
    }
    has_managed_panel_launcher || {
        print_error "The managed VS Code panel launcher is missing or invalid."
        failed=1
    }

    [[ -x "$PLATFORM_SCRIPT_DIR/verify_cvd.sh" ]] || {
        print_error "verify_cvd.sh is not executable."
        failed=1
    }

    if ((failed)); then
        print_error "User-layer validation failed. Rerun configure_cvd.sh."
        exit 7
    fi
    print_success "User-layer validation passed."
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    print_header "CONFIGURATION SUMMARY"
    printf 'Result          : PASS\n'
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'GitHub login    : Valid\n'
    printf 'Course folder   : %s\n' "$COURSE_ROOT"
    printf 'Python          : %s\n' "$VENV_DIR/bin/python"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Failures        : 0\n'
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Next step       : Close this terminal, open a new Terminal, and run verify_cvd.sh.\n'
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : 0\n'
    print_success "The IT 140 CVD user configuration completed successfully."
}

main() {
    parse_options "$@"

    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap on_error ERR
    trap on_interrupt INT TERM

    print_header "IT 140 CODIO VIRTUAL DESKTOP CONFIGURATION"
    print_info "Script version  : $SCRIPT_VERSION"
    print_info "Current user    : $(id -un)"
    print_info "Purpose         : Configure the current user's course environment."
    print_info "Log file        : $LOG_FILE"
    print_notice "This script does not install or change system-wide software."

    check_platform_and_user
    acquire_lock

    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || {
        print_error "The manifest or schema is missing. Run update_cvd.sh."
        print_error "If the problem continues, contact course support."
        exit 5
    }
    MANIFEST_RELEASE="$(validate_manifest)" || exit 5
    readonly MANIFEST_RELEASE
    print_success "Manifest release $MANIFEST_RELEASE validated."

    print_header "Step 1: Course Folders and System Prerequisites"
    check_system_layer
    configure_course_folders_and_path
    configure_provider_identity
    configure_user_tools

    print_header "Step 4: Course IDE Settings"
    merge_vscode_settings
    configure_desktop_integrations

    print_header "Step 5: Configuration Validation"
    post_validate

    trap - ERR INT TERM
    finish
}

main "$@"
