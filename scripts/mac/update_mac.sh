#!/bin/zsh
set -euo pipefail

readonly IT140_SCRIPT_VERSION="0.3.1"
readonly IT140_VERSION_DATE="2026-07-30"
readonly IT140_DEVELOPMENT_STATUS="Alpha Testing"
readonly IT140_ACTION_ID="update"
readonly IT140_USAGE="Usage: update_mac.sh [--help] [--version] [--noninteractive] [--profile PROFILE_ID]"
IT140_NONINTERACTIVE=false

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
source "$SCRIPT_DIR/_mac_common.sh"

show_help() {
    cat <<HELP
$IT140_USAGE

Synchronize approved student lifecycle assets and update course IDE components.
This script does not install macOS updates or upgrade macOS to another release.
It never replaces setup_mac.sh.

Options:
  --help                 Show this help.
  --version              Show artifact metadata.
  --noninteractive       Suppress optional prompts.
  --profile PROFILE_ID   Override automatic Apple-silicon/Intel profile selection.
HELP
}

extract_script_version() {
    /usr/bin/awk -F'"' '/readonly IT140_SCRIPT_VERSION=/{print $2; exit}' "$1"
}

semver_compare() {
    local left="$1" right="$2" python_path="$3"
    "$python_path" - "$left" "$right" <<'PY'
import re
import sys
rx = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$")
def parse(value):
    match = rx.fullmatch(value)
    if not match:
        raise SystemExit(2)
    core = tuple(map(int, match.group(1, 2, 3)))
    pre = match.group(4)
    identifiers = None if pre is None else pre.split('.')
    return core, identifiers
def cmp_ident(a, b):
    if a is None and b is None: return 0
    if a is None: return 1
    if b is None: return -1
    for x, y in zip(a, b):
        if x == y: continue
        xn, yn = x.isdigit(), y.isdigit()
        if xn and yn: return (int(x) > int(y)) - (int(x) < int(y))
        if xn != yn: return -1 if xn else 1
        return (x > y) - (x < y)
    return (len(a) > len(b)) - (len(a) < len(b))
a, b = parse(sys.argv[1]), parse(sys.argv[2])
result = (a[0] > b[0]) - (a[0] < b[0])
if result == 0: result = cmp_ident(a[1], b[1])
print(result)
PY
}

atomic_install() {
    local source="$1" destination="$2" mode="$3"
    local parent temp backup
    parent="$(dirname "$destination")"
    mkdir -p "$parent"
    temp="$(mktemp "$parent/.it140-activate.XXXXXX")"
    backup="${destination}.previous"
    cp "$source" "$temp"
    chmod "$mode" "$temp"
    [ -f "$destination" ] && cp "$destination" "$backup" || true
    mv "$temp" "$destination"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help) show_help; exit 0 ;;
        --version) it140_print_version; exit 0 ;;
        --noninteractive) IT140_NONINTERACTIVE=true ;;
        --profile)
            [ "$#" -ge 2 ] || { printf '[ERROR] --profile requires a value.\n' >&2; exit 64; }
            IT140_REQUESTED_PROFILE="$2"; shift ;;
        *) printf '[ERROR] Unknown option: %s\n%s\n' "$1" "$IT140_USAGE" >&2; exit 64 ;;
    esac
    shift
done

it140_check_platform_and_user
it140_initialize_log
it140_install_cleanup_traps

it140_header "IT 140 macOS UPDATE"
it140_print_version | sed 's/^/[INFO] /'
it140_info "Deployment       : $IT140_REQUESTED_PROFILE"
it140_info "Current user     : $(id -un)"
it140_info "Course root      : $IT140_COURSE_ROOT"
it140_info "Log file         : $IT140_LOG_FILE"
it140_notice "This update maintains course-managed software and assets only."
it140_notice "macOS updates and macOS release upgrades are not installed by this script."
it140_notice "setup_mac.sh is intentionally excluded from student asset synchronization."

it140_initialize_homebrew || { it140_error "Homebrew is unavailable. Run setup_mac.sh first."; exit 7; }
PYTHON_PATH="$(it140_resolve_python)" || { it140_error "Python 3.12 is unavailable. Run setup_mac.sh first."; exit 7; }
CODE_PATH="$(it140_resolve_code_cli)" || { it140_error "Visual Studio Code is unavailable. Run setup_mac.sh first."; exit 7; }
INSTALLED_RELEASE="$(it140_validate_manifest_full)"
it140_check_free_space
it140_acquire_lock

CONFIG_COMPLETE=true
if ! gh auth status --hostname github.com >/dev/null 2>&1; then CONFIG_COMPLETE=false; fi
if ! git config --global --get user.name >/dev/null 2>&1; then CONFIG_COMPLETE=false; fi
if ! git config --global --get user.email | grep -Eq '@users\.noreply\.github\.com$'; then CONFIG_COMPLETE=false; fi
if ! grep -Fq "$IT140_MANAGED_ENV_START" "$HOME/.zprofile" 2>/dev/null; then CONFIG_COMPLETE=false; fi
if [ "$CONFIG_COMPLETE" = true ]; then WORKFLOW="Periodic maintenance"; else WORKFLOW="First use or reset environment"; fi

it140_header "Step 1: Synchronize Course-Managed Student Assets"
IT140_TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/it140-update.XXXXXX")"
STAGED_REPO="$IT140_TEMP_ROOT/it140"
it140_retry "Course repository retrieval" git clone --depth 1 --quiet "$IT140_REPOSITORY_URL" "$STAGED_REPO" || exit 4
STAGED_MANIFEST="$STAGED_REPO/scripts/.manifest/it140_manifest.json"
STAGED_SCHEMA="$STAGED_REPO/scripts/.manifest/it140_manifest.schema.json"
CANDIDATE_RELEASE="$(it140_validate_manifest_full "$STAGED_MANIFEST" "$STAGED_SCHEMA")"
if [ "$(semver_compare "$CANDIDATE_RELEASE" "$INSTALLED_RELEASE" "$PYTHON_PATH")" -lt 0 ]; then
    it140_error "Candidate manifest $CANDIDATE_RELEASE is older than installed manifest $INSTALLED_RELEASE."
    exit 5
fi

atomic_install "$STAGED_SCHEMA" "$IT140_SCHEMA_PATH" 0644
atomic_install "$STAGED_MANIFEST" "$IT140_MANIFEST_PATH" 0644
if ! ACTIVE_CANDIDATE_RELEASE="$(it140_validate_manifest_full 2>&1)"; then
    it140_error "Candidate manifest activation failed validation: $ACTIVE_CANDIDATE_RELEASE"
    [ -f "${IT140_SCHEMA_PATH}.previous" ] && cp "${IT140_SCHEMA_PATH}.previous" "$IT140_SCHEMA_PATH"
    [ -f "${IT140_MANIFEST_PATH}.previous" ] && cp "${IT140_MANIFEST_PATH}.previous" "$IT140_MANIFEST_PATH"
    it140_validate_manifest_full >/dev/null 2>&1 || true
    exit 5
fi
IT140_CHANGED=true

for script_name in config_mac.sh update_mac.sh verify_mac.sh; do
    source_script="$STAGED_REPO/scripts/mac/$script_name"
    destination_script="$IT140_PLATFORM_SCRIPT_DIR/$script_name"
    if [ ! -r "$source_script" ]; then
        if [ -x "$destination_script" ]; then
            it140_notice "$script_name was omitted by the candidate release; the installed copy was preserved."
            continue
        fi
        it140_warning "$script_name is missing from both the candidate and installed course assets."
        IT140_PARTIAL=true
        continue
    fi
    /bin/zsh -n "$source_script"
    candidate_version="$(extract_script_version "$source_script")"
    it140_semver_is_valid "$candidate_version" || { it140_error "$script_name does not declare a strict SemVer artifact version."; exit 5; }
    if [ -r "$destination_script" ]; then
        installed_version="$(extract_script_version "$destination_script" || true)"
        if it140_semver_is_valid "$installed_version" && [ "$(semver_compare "$candidate_version" "$installed_version" "$PYTHON_PATH")" -lt 0 ]; then
            it140_notice "$script_name $installed_version is newer than candidate $candidate_version; downgrade prevented."
            continue
        fi
    fi
    atomic_install "$source_script" "$destination_script" 0755
    /bin/zsh -n "$destination_script"
    IT140_CHANGED=true
    it140_success "$script_name synchronized."
done

COMMON_SOURCE="$STAGED_REPO/scripts/mac/_mac_common.sh"
if [ -r "$COMMON_SOURCE" ]; then
    /bin/zsh -n "$COMMON_SOURCE"
    atomic_install "$COMMON_SOURCE" "$IT140_PLATFORM_SCRIPT_DIR/_mac_common.sh" 0755
    IT140_CHANGED=true
    it140_success "Shared macOS lifecycle helpers synchronized."
fi
ACTIVE_RELEASE="$(it140_validate_manifest_full)"
it140_success "Course-managed student assets are active and valid."

it140_header "Step 2: Update Required Course IDE Software"
brew update
FORMULA_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-update-formulae.XXXXXX")"
CASK_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-update-casks.XXXXXX")"
it140_manifest_query system_formulae > "$FORMULA_FILE"
it140_manifest_query system_casks > "$CASK_FILE"
while IFS= read -r formula; do
    [ -n "$formula" ] || continue
    if brew list --formula "$formula" >/dev/null 2>&1; then
        brew upgrade "$formula" 2>/dev/null || brew reinstall "$formula"
    else
        brew install "$formula"
    fi
    IT140_CHANGED=true
done < "$FORMULA_FILE"
while IFS= read -r cask; do
    [ -n "$cask" ] || continue
    if brew list --cask "$cask" >/dev/null 2>&1; then
        brew upgrade --cask "$cask" 2>/dev/null || true
    else
        brew install --cask "$cask"
    fi
    IT140_CHANGED=true
done < "$CASK_FILE"
rm -f "$FORMULA_FILE" "$CASK_FILE"

it140_header "Step 3: Update Required User Tools and Extensions"
VENV_PATH="$IT140_COURSE_ROOT/.venv"
if [ ! -x "$VENV_PATH/bin/python" ]; then
    "$PYTHON_PATH" -m venv "$VENV_PATH"
    it140_warning "The missing course Python environment was recreated."
fi
"$VENV_PATH/bin/python" -m pip install --upgrade pip
PACKAGE_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-update-python.XXXXXX")"
it140_manifest_query venv_packages > "$PACKAGE_FILE"
while IFS= read -r package; do
    [ -n "$package" ] || continue
    "$VENV_PATH/bin/python" -m pip install --upgrade "$package"
done < "$PACKAGE_FILE"
rm -f "$PACKAGE_FILE"

if NODE_NO_WARNINGS=1 "$CODE_PATH" --update-extensions; then
    it140_success "Installed VS Code extensions updated."
else
    it140_warning "One or more optional installed extensions could not be updated."
    IT140_PARTIAL=true
fi
EXTENSION_FILE="$(mktemp "${TMPDIR:-/tmp}/it140-update-extensions.XXXXXX")"
it140_manifest_query extensions > "$EXTENSION_FILE"
while IFS= read -r extension; do
    [ -n "$extension" ] || continue
    if ! NODE_NO_WARNINGS=1 "$CODE_PATH" --install-extension "$extension" --force; then
        it140_warning "Required VS Code extension could not be installed: $extension"
        IT140_PARTIAL=true
    fi
done < "$EXTENSION_FILE"
rm -f "$EXTENSION_FILE"

VSCODE_USER_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
if [ -f "$VSCODE_USER_SETTINGS" ]; then
    CONTROLLED_SETTINGS="$(it140_manifest_query vscode_settings)"
    if ! "$VENV_PATH/bin/python" - "$VSCODE_USER_SETTINGS" "$CONTROLLED_SETTINGS" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
managed = json.loads(sys.argv[2])
try:
    current = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
def merge(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge(target[key], value)
        else:
            target[key] = value
merge(current, managed)
temp = path.with_suffix(path.suffix + ".it140-new")
temp.write_text(json.dumps(current, indent=4, sort_keys=True) + "\n", encoding="utf-8")
json.loads(temp.read_text(encoding="utf-8"))
temp.replace(path)
PY
    then
        it140_warning "Existing VS Code settings could not be refreshed; the prior file was preserved."
        IT140_PARTIAL=true
    else
        it140_success "Manifest-controlled VS Code settings refreshed."
    fi
else
    it140_notice "VS Code user settings are not configured; config_mac.sh will create them."
fi

if [ -f "$IT140_COURSE_ROOT/.vscode/settings.json" ]; then
    "$VENV_PATH/bin/python" - "$IT140_COURSE_ROOT/.vscode/settings.json" "$VENV_PATH/bin/python" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
settings = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
settings.update({
    "python.defaultInterpreterPath": sys.argv[2],
    "python.terminal.activateEnvironment": True,
    "python.testing.pytestEnabled": True,
    "python.testing.unittestEnabled": False,
})
path.write_text(json.dumps(settings, indent=4, sort_keys=True) + "\n", encoding="utf-8")
PY
fi
IT140_CHANGED=true

it140_header "Step 4: Clean and Post-Validate"
brew cleanup --prune=all >/dev/null 2>&1 || true
it140_validate_manifest_full >/dev/null
"$VENV_PATH/bin/python" -c 'import pytest, pytest_cov, ruff'
for required_command in git gh; do command -v "$required_command" >/dev/null; done
"$CODE_PATH" --version >/dev/null
it140_success "Required updated state passed post-validation."

RESULT="PASS"
EXIT_CODE=0
NEXT_SCRIPT="verify_mac.sh"
if [ "$CONFIG_COMPLETE" = false ]; then NEXT_SCRIPT="config_mac.sh"; fi
if [ "$IT140_PARTIAL" = true ]; then RESULT="PARTIAL"; EXIT_CODE=7; NEXT_SCRIPT="update_mac.sh"; fi

it140_header "UPDATE SUMMARY"
printf 'Result        : %s\n' "$RESULT"
printf 'Workflow      : %s\n' "$WORKFLOW"
printf 'Script version: %s\n' "$IT140_SCRIPT_VERSION"
printf 'Manifest      : %s\n' "$ACTIVE_RELEASE"
printf 'Warnings      : %s\n' "$IT140_WARNINGS"
printf 'Failures      : %s\n' "$IT140_FAILURES"
printf 'Restart       : No macOS restart requested by this script\n'
printf 'Elapsed       : %s seconds\n' "$(it140_elapsed)"
printf 'Next step     : %s\n' "$NEXT_SCRIPT"
printf 'Exit code     : %s\n' "$EXIT_CODE"
if [ "$EXIT_CODE" -eq 0 ]; then
    it140_success "The IT 140 macOS update completed successfully."
else
    it140_notice "Rerun update_mac.sh after reviewing the warnings."
fi
it140_closing_notices
exit "$EXIT_CODE"
