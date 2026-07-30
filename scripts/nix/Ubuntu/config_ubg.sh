#!/usr/bin/env bash
#
# IT 140 Ubuntu Desktop with GNOME user configuration and repair script
#
# Traceability: CFG-FR-001 through CFG-FR-016; CFG-DES-001 through CFG-DES-016
# Scope: Current-user folders, PATH, GitHub authentication, Git identity and
#        settings, course virtual environment, IDE extensions and settings,
#        GNOME application launchers, dock integration, and file associations.
# Excludes: System package, repository, policy, and system application changes.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="2026.07.27.1"
readonly PLATFORM_ID="ubuntu_gnome"
readonly PLATFORM_ABBREVIATION="ubg"
readonly DEPLOYMENT_PROFILE_ID="ubuntu_gnome_bare_metal"
readonly COURSE_ROOT="${HOME}/it140"
readonly SCRIPT_ROOT="${COURSE_ROOT}/scripts"
readonly PLATFORM_SCRIPT_DIR="${SCRIPT_ROOT}/${PLATFORM_ABBREVIATION}"
readonly MANIFEST_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="${SCRIPT_ROOT}/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/config_${PLATFORM_ABBREVIATION}_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${COURSE_ROOT}/.venv"
readonly LOCK_FILE="${HOME}/.cache/it140-${PLATFORM_ABBREVIATION}-mutation.lock"
readonly MANAGED_PATH_START="# >>> IT 140 managed PATH >>>"
readonly MANAGED_PATH_END="# <<< IT 140 managed PATH <<<"
readonly MANAGED_PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/ubg:$PATH"'
readonly APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
readonly COURSE_FOLDER_LAUNCHER="${APPLICATIONS_DIR}/it140-folder.desktop"
readonly COURSE_VSCODE_LAUNCHER="${APPLICATIONS_DIR}/it140-vscode.desktop"

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

print_closing_notices() {
    print_notice "A log containing all output displayed while this script ran is available here:"
    print_notice "$LOG_FILE"
    print_notice "After reviewing the summary, type 'exit' and press Enter to close this Terminal."
    print_notice "Open a new Terminal before running another script or command so it loads the latest PATH and environment settings."
}

usage() {
    cat <<USAGE
Usage: config_ubg.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile ubuntu_gnome_bare_metal]

Configures or repairs the current user's IT 140 environment on Ubuntu Desktop
24.04 LTS with GNOME. Run as the standard desktop user, not with sudo.

In noninteractive mode, an existing GitHub login is required. The existing Git
display name is retained; when none exists, the GitHub username is used.

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
    print_error "Configuration was canceled. Rerun config_ubg.sh to continue."
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
    raise SystemExit("Ubuntu GNOME platform is not enabled")
if not profile or not profile.get("enabled") or profile.get("platform_id") != platform_id:
    raise SystemExit("Ubuntu GNOME deployment profile is invalid")
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
        print_error "Do not run config_ubg.sh with sudo."
        print_error "Personal settings must be saved under the standard Ubuntu account."
        exit 2
    fi

    [[ -r /etc/os-release ]] || {
        print_error "Cannot identify the operating system."
        exit 2
    }
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != 24.04 ]]; then
        print_error "This script supports only Ubuntu Desktop 24.04 LTS."
        print_error "Detected: ${PRETTY_NAME:-unknown operating system}"
        exit 2
    fi

    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ "$architecture" != amd64 && "$architecture" != x86_64 ]]; then
        print_error "This release supports only x86_64. Detected: $architecture"
        exit 2
    fi

    command -v gnome-shell >/dev/null 2>&1 || {
        print_error "The GNOME desktop required by this script is unavailable."
        exit 2
    }
    command -v gsettings >/dev/null 2>&1 || {
        print_error "GNOME settings tools are unavailable."
        exit 2
    }
}

check_system_layer() {
    local command_name failed=0
    local -a system_commands
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
        print_error "The Ubuntu system layer is incomplete. Run setup_ubg.sh."
        exit 1
    fi
    print_success "Required system components are present."
}

acquire_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    if ! flock --nonblock 9; then
        print_error "Another IT 140 configuration or update operation is running."
        exit 1
    fi
}

upsert_managed_path_block() {
    local file="$1"
    python3 - "$file" "$MANAGED_PATH_START" "$MANAGED_PATH_END" \
        "$MANAGED_PATH_EXPORT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
start, end, export_line = sys.argv[2:]
block = f"{start}\n{export_line}\n{end}\n"
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

config_course_folders_and_path() {
    print_header "Step 1: Course Folders and Terminal PATH"
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

    find "$PLATFORM_SCRIPT_DIR" -maxdepth 1 -type f -name '*_ubg.sh' \
        -exec chmod 0755 {} + 2>/dev/null || true
    CHANGED=true
    print_success "Course folders, script permissions, and PATH entries are configured."
}

config_provider_identity() {
    print_header "Step 2: GitHub Authentication and Git Identity"
    print_info "Checking GitHub authentication status..."

    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        if [[ "$NONINTERACTIVE" == true ]]; then
            print_error "GitHub authentication is required but interaction is disabled."
            exit 6
        fi

        print_notice "GitHub CLI will display a one-time code and open a browser sign-in page."
        print_notice "Copy the code shown in this Terminal and enter it in the browser when requested."
        print_notice "After GitHub confirms the login, close the browser tab and return here."
        printf '[ACTION REQUIRED] Press Enter to begin, or type C to cancel: '
        read -r response
        if [[ "${response,,}" == c ]]; then
            exit 6
        fi

        gh auth login --hostname github.com --git-protocol https --web
        CHANGED=true
    fi

    gh auth status --hostname github.com >/dev/null 2>&1 || {
        print_error "GitHub authentication did not complete successfully."
        exit 1
    }
    gh auth setup-git --hostname github.com
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
        print_notice "Press Enter to use the displayed name as your Git author name."
        print_notice "Or enter a different name to use for your Git commits."
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

config_user_tools() {
    print_header "Step 3: Course Python Tools and IDE Extensions"

    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        print_info "Creating the IT 140 course virtual environment..."
        python3.12 -m venv "$VENV_DIR"
        CHANGED=true
    else
        print_success "The IT 140 course virtual environment is available."
    fi

    local package extension installed_extensions
    local -a venv_packages missing_packages required_extensions missing_extensions
    mapfile -t venv_packages < <(manifest_lines venv_packages)
    missing_packages=()
    for package in "${venv_packages[@]}"; do
        if ! "$VENV_DIR/bin/python" -m pip show "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done
    if ((${#missing_packages[@]})); then
        print_info "Installing missing course Python tools..."
        "$VENV_DIR/bin/python" -m pip install --upgrade pip
        "$VENV_DIR/bin/python" -m pip install "${missing_packages[@]}"
        CHANGED=true
    else
        print_success "Required course Python tools are already installed."
    fi

    installed_extensions="$(NODE_NO_WARNINGS=1 code --list-extensions 2>/dev/null \
        | tr '[:upper:]' '[:lower:]')"
    mapfile -t required_extensions < <(manifest_lines extensions)
    missing_extensions=()
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

add_nautilus_bookmark() {
    local bookmark_file="$1"
    local bookmark="file://${COURSE_ROOT} IT 140"
    mkdir -p "$(dirname "$bookmark_file")"
    touch "$bookmark_file"
    grep -Fqx "$bookmark" "$bookmark_file" || printf '%s\n' "$bookmark" >> "$bookmark_file"
}

add_gnome_favorite() {
    local desktop_id="$1"
    local current updated

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        print_warning "A GNOME session bus is unavailable; VS Code was not added to the dock."
        return 0
    fi

    current="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)" || {
        print_warning "GNOME favorites could not be read; VS Code was not added to the dock."
        return 0
    }
    updated="$(python3 - "$current" "$desktop_id" <<'PY'
import ast
import sys

current, desktop_id = sys.argv[1:]
try:
    values = ast.literal_eval(current)
except (SyntaxError, ValueError):
    raise SystemExit(1)
if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
    raise SystemExit(1)
if desktop_id not in values:
    values.append(desktop_id)
print(repr(values))
PY
)" || {
        print_warning "GNOME favorites could not be interpreted; VS Code was not added to the dock."
        return 0
    }

    if gsettings set org.gnome.shell favorite-apps "$updated"; then
        print_success "The IT 140 VS Code launcher is available on the GNOME dock."
    else
        print_warning "VS Code was not added to the GNOME dock; it remains available in Applications."
    fi
}

config_desktop_integrations() {
    print_header "Step 4: GNOME Desktop Integration"
    mkdir -p "$APPLICATIONS_DIR"

    cat > "$COURSE_FOLDER_LAUNCHER" <<EOF_FOLDER
[Desktop Entry]
Version=1.0
Type=Application
Name=IT 140 Course Folder
Comment=Open the IT 140 course directory
TryExec=xdg-open
Exec=xdg-open "$COURSE_ROOT"
Icon=folder
Terminal=false
StartupNotify=true
Categories=Development;Education;
EOF_FOLDER

    cat > "$COURSE_VSCODE_LAUNCHER" <<EOF_CODE
[Desktop Entry]
Version=1.0
Type=Application
Name=IT 140 in Visual Studio Code
Comment=Open the IT 140 course directory in Visual Studio Code
TryExec=code
Exec=code --new-window "$COURSE_ROOT"
Icon=com.visualstudio.code
Terminal=false
StartupNotify=true
Categories=Development;Education;IDE;
EOF_CODE

    chmod 0644 "$COURSE_FOLDER_LAUNCHER" "$COURSE_VSCODE_LAUNCHER"
    if command -v desktop-file-validate >/dev/null 2>&1; then
        desktop-file-validate "$COURSE_FOLDER_LAUNCHER"
        desktop-file-validate "$COURSE_VSCODE_LAUNCHER"
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
    fi

    add_nautilus_bookmark "$HOME/.config/gtk-3.0/bookmarks"
    add_nautilus_bookmark "$HOME/.config/gtk-4.0/bookmarks"
    add_gnome_favorite "it140-vscode.desktop"

    local mime_type
    for mime_type in text/plain text/markdown text/x-python text/x-shellscript; do
        xdg-mime default code.desktop "$mime_type" 2>/dev/null \
            || print_warning "Could not set VS Code as the default for $mime_type."
    done

    CHANGED=true
    print_success "Course application launchers, file-manager bookmarks, and file associations are configured."
}

has_valid_vscode_settings() {
    local settings_file="$HOME/.config/Code/User/settings.json"
    [[ -r "$settings_file" ]] || return 1
    python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$settings_file" \
        "$VENV_DIR/bin/python" "$COURSE_ROOT" <<'PY'
import json
import pathlib
import sys

manifest_path, platform_id, settings_path, python_path, course_root = sys.argv[1:]
try:
    manifest = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"))
    settings = json.loads(pathlib.Path(settings_path).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
if not isinstance(settings, dict):
    raise SystemExit(1)
bindings = manifest["platforms"][platform_id]["course_ide_bindings"]
expected = {}
for profile_id in bindings["source_code_ide"].get("settings_profile_ids", []):
    expected.update(manifest["managed_settings"][profile_id]["values"])
expected["python.defaultInterpreterPath"] = python_path
expected["files.defaultFolder"] = course_root


def contains(actual, desired):
    if isinstance(desired, dict):
        return isinstance(actual, dict) and all(
            key in actual and contains(actual[key], value)
            for key, value in desired.items()
        )
    return actual == desired


if not contains(settings, expected):
    raise SystemExit(1)
PY
}

post_validate() {
    local failed=0 package extension configured_email key expected_value configured_value
    local installed_extensions
    local -a venv_packages required_extensions

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
        print_error "Git is not using the approved GitHub private noreply identity."
        failed=1
    }

    while IFS=$'\t' read -r key expected_value; do
        [[ -n "$key" ]] || continue
        configured_value="$(git config --global --get "$key" 2>/dev/null || true)"
        if [[ "$configured_value" != "$expected_value" ]]; then
            print_error "Git setting is not configured as required: $key"
            failed=1
        fi
    done < <(manifest_lines git_settings)

    has_valid_vscode_settings || {
        print_error "Course-managed VS Code settings are incomplete or invalid."
        failed=1
    }
    [[ -r "$COURSE_FOLDER_LAUNCHER" && -r "$COURSE_VSCODE_LAUNCHER" ]] || {
        print_error "Required GNOME application launchers are missing."
        failed=1
    }

    if ((failed)); then
        print_error "User-configuration validation failed. Rerun config_ubg.sh."
        exit 7
    fi
    print_success "User-configuration validation passed."
}

finish() {
    local elapsed=$(( $(date +%s) - START_EPOCH ))
    print_header "CONFIGURATION SUMMARY"
    printf 'Result          : PASS\n'
    printf 'Script version  : %s\n' "$SCRIPT_VERSION"
    printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
    printf 'Platform        : %s (%s)\n' "$PLATFORM_ID" "$PLATFORM_ABBREVIATION"
    printf 'Warnings        : %s\n' "$WARNINGS"
    printf 'Failures        : 0\n'
    printf 'Elapsed time    : %s seconds\n' "$elapsed"
    printf 'Next step       : Close this terminal, open a new Terminal, and run verify_ubg.sh.\n'
    printf 'Log file        : %s\n' "$LOG_FILE"
    printf 'Exit code       : 0\n'
    print_success "The IT 140 Ubuntu Desktop user configuration completed successfully."
    print_closing_notices
}

main() {
    parse_options "$@"

    mkdir -p "$LOG_DIR"
    chmod 0700 "$LOG_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap on_error ERR
    trap on_interrupt INT TERM

    print_header "IT 140 UBUNTU DESKTOP CONFIGURATION"
    print_info "Script version  : $SCRIPT_VERSION"
    print_info "Current user    : $(id -un)"
    print_info "Purpose         : Configure or repair the current user's course IDE."
    print_info "Log file        : $LOG_FILE"
    print_notice "This script changes only the current user's approved course settings and tools."

    print_header "Platform and Manifest Validation"
    check_platform_and_user
    acquire_lock

    [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] || {
        print_error "The manifest or schema is missing under $SCRIPT_ROOT/.manifest/."
        exit 5
    }
    MANIFEST_RELEASE="$(validate_manifest)" || exit 5
    readonly MANIFEST_RELEASE
    print_success "Manifest release $MANIFEST_RELEASE validated."
    check_system_layer

    config_course_folders_and_path
    config_provider_identity
    config_user_tools

    print_header "Step 4: IDE Settings"
    merge_vscode_settings
    config_desktop_integrations

    print_header "Step 5: Configuration Validation"
    post_validate

    trap - ERR INT TERM
    finish
}

main "$@"
