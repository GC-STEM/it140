#!/bin/zsh
# ==============================================================================
# IT 140 COURSE IDE — CONFIGURE (macOS APPLE SILICON)
# ==============================================================================
# Repository path: scripts/mac/configure_it140.zsh
# Purpose: Configure or repair the current user's IT 140 course environment.
# Artifact ID: IT140-MAC-CONFIGURE
# Artifact version: 0.10.0-beta.1
# Version date-time group: 2026-08-09-23-59
# Development status: Beta Testing
# Supported profile: macos_bare_metal (Apple silicon, arm64)
# Traceability: CFG-FR-001 through CFG-FR-021; CFG-DES-001 through CFG-DES-021.
#
# This script creates ~/Repos as the student development workspace, a
# Desktop/Repos link, and a Visual Studio Code - Repos.app desktop launcher that
# opens ~/Repos. Finder has no supported stable built-in emblem interface, so
# the visual-marker adapter is N/A. Student repositories beneath ~/Repos are
# never recursively managed.
# ==============================================================================
set -euo pipefail
umask 077
readonly SCRIPT_VERSION="0.10.0-beta.1"
readonly VERSION_DTG="2026-08-09-23-59"
readonly DEVELOPMENT_STATUS="Beta Testing"
readonly PLATFORM_ID="macos"
readonly DEPLOYMENT_PROFILE_ID="macos_bare_metal"
readonly SUPPORTED_SCHEMA="2.2"
readonly COURSE_ROOT="$HOME/it140"
readonly REPOS_ROOT="$HOME/Repos"
readonly VSCODE_REPOS_LAUNCHER="$HOME/Desktop/Visual Studio Code - Repos.app"
readonly VSCODE_LAUNCHER_MARKER="IT140-MAC-VSCODE-REPOS-LAUNCHER-v1"
readonly SCRIPT_ROOT="$COURSE_ROOT/scripts"
readonly PLATFORM_SCRIPT_DIR="$SCRIPT_ROOT/mac"
readonly MANIFEST_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="$COURSE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/configure_mac_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="$COURSE_ROOT/.venv"
readonly MANAGED_ENV_START="# >>> IT 140 managed PATH >>>"
readonly MANAGED_ENV_END="# <<< IT 140 managed PATH <<<"
readonly LEGACY_ENV_START="# >>> IT 140 Course IDE managed environment >>>"
readonly LEGACY_ENV_END="# <<< IT 140 Course IDE managed environment <<<"
readonly MANAGED_ENV_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:$PATH"'
readonly LOCK_PARENT="$HOME/Library/Caches"
readonly LOCK_DIR="$LOCK_PARENT/it140-mac-mutation.lock"
readonly EXIT_SUCCESS=0 EXIT_FAILURE=1 EXIT_UNSUPPORTED=2 EXIT_EXTERNAL=4 EXIT_MANIFEST=5 EXIT_CANCELED=6 EXIT_PARTIAL=7
NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
LOCK_HELD=false
WARNINGS=0
FAILURES=0
CURRENT_STAGE="initialization"
START_EPOCH="$(date +%s)"
START_TIME="$(date '+%Y-%m-%dT%H:%M:%S%z')"
MANIFEST_RELEASE="unavailable"
MANIFEST_DTG="unavailable"
FINALIZED=false
GITHUB_LOGIN=""
print_header(){ printf '\n============================================================\n%s\n============================================================\n' "$1"; }
print_info(){ printf '[INFO] %s\n' "$1"; }
print_success(){ printf '[SUCCESS] %s\n' "$1"; }
print_notice(){ printf '[NOTICE] %s\n' "$1"; }
print_warning(){ printf '[WARNING] %s\n' "$1"; WARNINGS=$((WARNINGS+1)); }
print_error(){ printf '[ERROR] %s\n' "$1" >&2; }
usage(){ cat <<USAGE
Usage: configure_it140.zsh [--help] [--version] [--noninteractive]
                           [--deployment-profile macos_bare_metal]
Configures the current macOS user for IT 140, including ~/Repos, a Desktop
Repos link, and Visual Studio Code - Repos.app. It does not install system
software or alter repositories in ~/Repos.
Logs: ~/it140/logs/
USAGE
}
parse_options(){
  while (( $# )); do
    case "$1" in
      --help|-h) usage; exit 0;;
      --version) printf '%s (%s; %s)\n' "$SCRIPT_VERSION" "$VERSION_DTG" "$DEVELOPMENT_STATUS"; exit 0;;
      --noninteractive) NONINTERACTIVE=true;;
      --deployment-profile|--profile) shift; (( $# )) || { print_error "Missing deployment profile."; exit 2; }; REQUESTED_PROFILE="$1";;
      *) print_error "Unsupported option: $1"; usage >&2; exit 2;;
    esac
    shift
  done
}
course_continuity(){
  print_notice "Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved."
}
release_lock(){
  if [[ "$LOCK_HELD" == true && -d "$LOCK_DIR" ]]; then /bin/rm -rf -- "$LOCK_DIR"; fi
  LOCK_HELD=false
}
finish(){
  local requested="${1:-0}" message="${2:-}" result="PASS" code=0 next="Open a new Terminal and run verify_it140.zsh."
  [[ "$FINALIZED" == false ]] || return "$requested"
  FINALIZED=true
  trap - ERR INT TERM HUP
  set +e
  release_lock
  if (( requested != 0 )); then
    code=$requested; result="FAIL"
    [[ "$CHANGED" == true && "$requested" != "$EXIT_UNSUPPORTED" && "$requested" != "$EXIT_MANIFEST" ]] && code=$EXIT_PARTIAL
    next="Resolve the reported issue, then rerun configure_it140.zsh."
  fi
  print_header "CONFIGURATION SUMMARY"
  [[ -n "$message" ]] && printf 'Conclusion       : %s\n' "$message"
  printf 'Result           : %s\n' "$result"
  printf 'Script version   : %s\n' "$SCRIPT_VERSION"
  printf 'Version DTG      : %s\n' "$VERSION_DTG"
  printf 'Development status: %s\n' "$DEVELOPMENT_STATUS"
  printf 'Manifest release : %s\n' "$MANIFEST_RELEASE"
  printf 'Manifest DTG     : %s\n' "$MANIFEST_DTG"
  printf 'Repository root  : %s\n' "$REPOS_ROOT"
  printf 'Warnings         : %s\n' "$WARNINGS"
  printf 'Failures         : %s\n' "$FAILURES"
  printf 'Managed changes  : %s\n' "$( [[ "$CHANGED" == true ]] && printf 'Yes' || printf 'No' )"
  printf 'Elapsed time     : %s seconds\n' "$(( $(date +%s) - START_EPOCH ))"
  printf 'Next step        : %s\n' "$next"
  printf 'Log file         : %s\n' "$LOG_FILE"
  printf 'Exit code        : %s\n' "$code"
  (( code == 0 )) && print_success "The macOS user configuration completed successfully." || course_continuity
  return "$code"
}
fatal(){ local code="$1"; shift; FAILURES=$((FAILURES+1)); print_error "$*"; print_error "Failed stage: $CURRENT_STAGE"; finish "$code" "$*"; exit $?; }
on_error(){ local status=$?; trap - ERR; FAILURES=$((FAILURES+1)); print_error "Configuration stopped during $CURRENT_STAGE (status $status)."; finish 1 "An unexpected command failure stopped Configure."; exit $?; }
on_interrupt(){ trap - INT TERM HUP; print_error "Configuration was interrupted during $CURRENT_STAGE."; finish 6 "Configure was interrupted; rerun it to recover."; exit $?; }
acquire_lock(){
  CURRENT_STAGE="shared lifecycle mutation lock"
  /bin/mkdir -p -- "$LOCK_PARENT"
  if /bin/mkdir -- "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    printf '%s\n' "$(date +%s)" > "$LOCK_DIR/created_epoch"
    LOCK_HELD=true
    return 0
  fi
  local lock_pid="" created_epoch="0" now age
  [[ -r "$LOCK_DIR/pid" ]] && lock_pid="$(<"$LOCK_DIR/pid")"
  [[ -r "$LOCK_DIR/created_epoch" ]] && created_epoch="$(<"$LOCK_DIR/created_epoch")"
  [[ "$created_epoch" =~ ^[0-9]+$ ]] || created_epoch=0
  now="$(date +%s)"; age=$((now-created_epoch))
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$lock_pid" 2>/dev/null && (( age < 7200 )); then
    fatal 7 "Another IT 140 macOS lifecycle script is already running (process $lock_pid)."
  fi
  print_warning "A stale lifecycle lock was found and removed."
  /bin/rm -rf -- "$LOCK_DIR"
  /bin/mkdir -- "$LOCK_DIR" || fatal 1 "The lifecycle lock could not be acquired after stale-lock recovery."
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  printf '%s\n' "$(date +%s)" > "$LOCK_DIR/created_epoch"
  LOCK_HELD=true
}
validate_manifest(){
  python3.12 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" "$(sw_vers -productVersion | cut -d. -f1)" <<'PY'
import json, pathlib, sys
mp, sp, pid, prof, sv, os_major = sys.argv[1:]
def load(path):
    return json.loads(pathlib.Path(path).read_text(encoding='utf-8'), object_pairs_hook=_unique)
def _unique(pairs):
    out={}
    for k,v in pairs:
        if k in out: raise ValueError(f'duplicate JSON key: {k}')
        out[k]=v
    return out
m=load(mp); s=load(sp)
if m.get('schema_version') != sv: raise SystemExit('unsupported manifest schema')
if s.get('$schema') != 'https://json-schema.org/draft/2020-12/schema': raise SystemExit('unsupported JSON Schema draft')
p=m.get('platforms',{}).get(pid); d=m.get('deployment_profiles',{}).get(prof)
if not p or not p.get('enabled'): raise SystemExit('macOS platform missing or disabled')
if not d or not d.get('enabled') or d.get('platform_id') != pid or d.get('architecture') != 'arm64': raise SystemExit('macOS deployment profile invalid')
if os_major not in {str(x.get('release_id')) for x in p.get('os',{}).get('releases',[])}: raise SystemExit(f'unsupported macOS release: {os_major}')
if m.get('policy',{}).get('allow_os_release_upgrade') is not False: raise SystemExit('manifest must prohibit operating-system release upgrades')
wf=m.get('lifecycle_workflows',{}).get('local_initial_install')
if not wf or 'local_initial_install' not in d.get('allowed_workflow_ids',[]) or 'configure' not in wf.get('success_transitions',{}): raise SystemExit('local initial-install workflow is invalid for Configure')
try:
    import jsonschema
except ImportError:
    pass
else:
    jsonschema.Draft202012Validator.check_schema(s)
    jsonschema.Draft202012Validator(s).validate(m)
print(f"{m['automation_release']}\t{m['automation_release_date_time_group']}")
PY
}
manifest_query(){
  python3.12 - "$MANIFEST_PATH" "$PLATFORM_ID" "$1" <<'PY'
import json,sys
m=json.load(open(sys.argv[1],encoding='utf-8')); b=m['platforms'][sys.argv[2]]['course_ide_bindings']; q=sys.argv[3]
if q=='venv_packages':
 vals=[]
 for role,x in b.items():
  if x.get('required') and x.get('installation_scope')=='user' and x.get('installer_adapter_id')=='python_venv_package': vals.append(x['package_identifier'])
  if role=='code_quality_tool' and x.get('required'): vals.append('ruff')
 print('\n'.join(sorted(set(vals))))
elif q=='extensions':
 print('\n'.join(x['package_identifier'] for x in b.values() if x.get('required') and x.get('installer_adapter_id')=='vscode_extension'))
elif q=='git_settings':
 for pid in b['version_control_system'].get('settings_profile_ids',[]):
  for k,v in m['managed_settings'][pid]['values'].items():
   if isinstance(v,bool): v='true' if v else 'false'
   print(f'{k}\t{v}')
elif q=='vscode_settings':
 vals={}
 for pid in b['source_code_ide'].get('settings_profile_ids',[]): vals.update(m['managed_settings'][pid]['values'])
 print(json.dumps(vals,separators=(',',':')))
elif q=='privacy_template':
 print(m['provider_profiles']['github_com']['privacy_identity']['template'])
PY
}
check_context(){
  CURRENT_STAGE="execution-context validation"
  [[ "$(uname -s)" == Darwin ]] || fatal 2 "This script supports macOS only."
  [[ "$(uname -m)" == arm64 ]] || fatal 2 "This implementation supports Apple silicon (arm64) only."
  [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] || fatal 2 "Unsupported deployment profile: $REQUESTED_PROFILE"
  (( EUID != 0 )) || fatal 2 "Do not run configure_it140.zsh with sudo."
  for cmd in git gh python3.12 code; do command -v "$cmd" >/dev/null 2>&1 || fatal 1 "Required system command is missing: $cmd. Run install_it140.zsh first."; done
}
upsert_path(){
  local file="$1" temp
  temp="$(mktemp "${TMPDIR:-/tmp}/it140-path.XXXXXX")"
  [[ -e "$file" ]] || : > "$file"
  /usr/bin/awk \
    -v start="$MANAGED_ENV_START" -v finish="$MANAGED_ENV_END" \
    -v legacy_start="$LEGACY_ENV_START" -v legacy_finish="$LEGACY_ENV_END" '
    $0 == start || $0 == legacy_start {inside=1; next}
    $0 == finish || $0 == legacy_finish {inside=0; next}
    !inside {print}
  ' "$file" > "$temp"
  printf '\n%s\n%s\n%s\n' "$MANAGED_ENV_START" "$MANAGED_ENV_EXPORT" "$MANAGED_ENV_END" >> "$temp"
  chmod 0600 "$temp"
  if cmp -s "$temp" "$file"; then rm -f "$temp"; else mv -f "$temp" "$file"; CHANGED=true; fi
}
configure_paths(){
  CURRENT_STAGE="course paths and repository workspace"
  mkdir -p "$COURSE_ROOT" "$LOG_DIR" "$PLATFORM_SCRIPT_DIR"; chmod 700 "$LOG_DIR"
  touch "$HOME/.zprofile" "$HOME/.zshrc"; upsert_path "$HOME/.zprofile"; upsert_path "$HOME/.zshrc"
  export PATH="$VENV_DIR/bin:$PLATFORM_SCRIPT_DIR:/opt/homebrew/bin:$PATH"
  hash -r
  if [[ -e "$REPOS_ROOT" && ! -d "$REPOS_ROOT" ]]; then fatal 1 "The required repository workspace path exists but is not a directory: $REPOS_ROOT"; fi
  [[ -d "$REPOS_ROOT" ]] || { mkdir "$REPOS_ROOT"; CHANGED=true; }
  [[ -w "$REPOS_ROOT" ]] || fatal 1 "The repository workspace is not writable: $REPOS_ROOT"
  local desktop="$HOME/Desktop" link="$HOME/Desktop/Repos"
  mkdir -p "$desktop"
  if [[ -L "$link" ]]; then
    [[ "$(readlink "$link")" == "$REPOS_ROOT" ]] || fatal 1 "An existing Desktop/Repos link targets another location and was preserved."
  elif [[ -e "$link" ]]; then
    fatal 1 "An unmanaged Desktop item named Repos already exists and was preserved."
  else
    ln -s "$REPOS_ROOT" "$link"; CHANGED=true
  fi
  print_notice "Finder development marker: NOT APPLICABLE (no safe supported built-in emblem interface is used)."
  print_success "Repository workspace configured: $REPOS_ROOT"
}
vscode_repos_launcher_is_managed(){
  local launcher="${1:-$VSCODE_REPOS_LAUNCHER}" marker
  marker="$launcher/Contents/Resources/it140-managed-launcher"
  [[ -d "$launcher" && -f "$marker" ]] || return 1
  [[ "$(<"$marker")" == "$VSCODE_LAUNCHER_MARKER" ]]
}
vscode_repos_launcher_is_valid(){
  local launcher="${1:-$VSCODE_REPOS_LAUNCHER}" code_cli="${2:-}"
  [[ -n "$code_cli" ]] || code_cli="$(command -v code 2>/dev/null || true)"
  [[ -n "$code_cli" && -d "$launcher" ]] || return 1
  IT140_LAUNCHER="$launcher" IT140_REPOS="$REPOS_ROOT" IT140_CODE="$code_cli" IT140_MARKER="$VSCODE_LAUNCHER_MARKER" python3.12 - <<'PY'
import os, plistlib, shlex
from pathlib import Path
app=Path(os.environ['IT140_LAUNCHER'])
repos=os.environ['IT140_REPOS']; code=os.environ['IT140_CODE']; marker=os.environ['IT140_MARKER']
info=app/'Contents'/'Info.plist'; exe=app/'Contents'/'MacOS'/'open-repos'; mark=app/'Contents'/'Resources'/'it140-managed-launcher'
if not (info.is_file() and exe.is_file() and os.access(exe,os.X_OK) and mark.is_file()): raise SystemExit(1)
if mark.read_text(encoding='utf-8').strip()!=marker: raise SystemExit(1)
with info.open('rb') as f: p=plistlib.load(f)
if p.get('CFBundleIdentifier')!='edu.snhu.it140.vscode-repos' or p.get('CFBundleExecutable')!='open-repos' or p.get('CFBundlePackageType')!='APPL': raise SystemExit(1)
expected=("#!/bin/zsh\n"+f"# {marker}\n"+"set -euo pipefail\n"+f"readonly REPOS_ROOT={shlex.quote(repos)}\n"+f"readonly CODE_CLI={shlex.quote(code)}\n"+'cd -- "$REPOS_ROOT"\n'+'exec "$CODE_CLI" --reuse-window "$REPOS_ROOT"\n')
if exe.read_text(encoding='utf-8')!=expected: raise SystemExit(1)
PY
}
configure_vscode_repos_launcher(){
  CURRENT_STAGE="Visual Studio Code repository-workspace launcher"
  local launcher="$VSCODE_REPOS_LAUNCHER" code_cli temp_root temp_app icon=""
  code_cli="$(command -v code 2>/dev/null || true)"
  [[ -n "$code_cli" ]] || fatal 1 "Visual Studio Code is required, but the code command could not be resolved for the Desktop launcher."
  if vscode_repos_launcher_is_valid "$launcher" "$code_cli"; then
    print_success "Visual Studio Code - Repos.app already opens $REPOS_ROOT."
    return 0
  fi
  if [[ -e "$launcher" || -L "$launcher" ]]; then
    vscode_repos_launcher_is_managed "$launcher" || fatal 1 "An unmanaged Desktop item named Visual Studio Code - Repos.app already exists and was preserved: $launcher"
  fi
  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/it140-vscode-repos.XXXXXX")" || fatal 1 "A temporary launcher workspace could not be created."
  temp_app="$temp_root/Visual Studio Code - Repos.app"
  if [[ -f "/Applications/Visual Studio Code.app/Contents/Resources/Code.icns" ]]; then
    icon="/Applications/Visual Studio Code.app/Contents/Resources/Code.icns"
  elif [[ -f "$HOME/Applications/Visual Studio Code.app/Contents/Resources/Code.icns" ]]; then
    icon="$HOME/Applications/Visual Studio Code.app/Contents/Resources/Code.icns"
  fi
  IT140_APP="$temp_app" IT140_REPOS="$REPOS_ROOT" IT140_CODE="$code_cli" IT140_MARKER="$VSCODE_LAUNCHER_MARKER" IT140_ICON="$icon" python3.12 - <<'PY'
import os, plistlib, shlex, shutil
from pathlib import Path
app=Path(os.environ['IT140_APP']); repos=os.environ['IT140_REPOS']; code=os.environ['IT140_CODE']; marker=os.environ['IT140_MARKER']; icon=os.environ.get('IT140_ICON','')
macos=app/'Contents'/'MacOS'; resources=app/'Contents'/'Resources'; macos.mkdir(parents=True); resources.mkdir(parents=True)
exe=macos/'open-repos'
exe.write_text("#!/bin/zsh\n"+f"# {marker}\n"+"set -euo pipefail\n"+f"readonly REPOS_ROOT={shlex.quote(repos)}\n"+f"readonly CODE_CLI={shlex.quote(code)}\n"+'cd -- "$REPOS_ROOT"\n'+'exec "$CODE_CLI" --reuse-window "$REPOS_ROOT"\n',encoding='utf-8')
exe.chmod(0o755)
(resources/'it140-managed-launcher').write_text(marker+'\n',encoding='utf-8')
plist={'CFBundleDisplayName':'Visual Studio Code - Repos','CFBundleExecutable':'open-repos','CFBundleIdentifier':'edu.snhu.it140.vscode-repos','CFBundleName':'Visual Studio Code - Repos','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','LSUIElement':True,'NSHighResolutionCapable':True}
if icon and Path(icon).is_file():
    shutil.copy2(icon,resources/'Code.icns'); plist['CFBundleIconFile']='Code.icns'
with (app/'Contents'/'Info.plist').open('wb') as f: plistlib.dump(plist,f,sort_keys=True)
PY
  vscode_repos_launcher_is_valid "$temp_app" "$code_cli" || { /bin/rm -rf -- "$temp_root"; fatal 1 "The staged Visual Studio Code - Repos.app launcher did not validate."; }
  if [[ -e "$launcher" || -L "$launcher" ]]; then /bin/rm -rf -- "$launcher"; fi
  /bin/mv -- "$temp_app" "$launcher" || { /bin/rm -rf -- "$temp_root"; fatal 1 "Visual Studio Code - Repos.app could not be installed on the Desktop."; }
  /bin/rm -rf -- "$temp_root"
  vscode_repos_launcher_is_valid "$launcher" "$code_cli" || fatal 1 "Visual Studio Code - Repos.app failed post-installation validation."
  CHANGED=true
  print_success "Visual Studio Code - Repos.app now opens $REPOS_ROOT."
}
configure_identity(){
  CURRENT_STAGE="GitHub authentication and Git identity"
  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    [[ "$NONINTERACTIVE" == false ]] || fatal 1 "GitHub CLI is not authenticated; interactive authentication is required."
    printf 'GitHub authentication is required. Press Enter to begin, or type C to cancel: '
    local reply; IFS= read -r reply; case "$reply" in c|C) fatal 6 "GitHub authentication canceled.";; esac
    gh auth login --hostname github.com --git-protocol https --web --clipboard || fatal 4 "GitHub authentication did not complete."
    CHANGED=true
  fi
  local json aid login name template email requested
  json="$(gh api user --jq '{id:.id,login:.login,name:.name}')" || fatal 4 "GitHub account data could not be read."
  IFS=$'\t' read -r aid login name <<< "$(python3.12 - "$json" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(f"{x['id']}\t{x['login']}\t{x.get('name') or x['login']}")
PY
)"
  GITHUB_LOGIN="$login"
  if [[ "$NONINTERACTIVE" == false ]]; then printf 'Git commit display name [%s]: ' "$name"; IFS= read -r requested; [[ -z "$requested" ]] || name="$requested"; fi
  template="$(manifest_query privacy_template)"; email="${template//\$\{ACCOUNT_ID\}/$aid}"; email="${email//\$\{USERNAME\}/$login}"
  git config --global user.name "$name"; git config --global user.email "$email"
  while IFS=$'\t' read -r key value; do [[ -n "$key" ]] || continue; git config --global "$key" "$value"; done < <(manifest_query git_settings)
  CHANGED=true
}
configure_tools(){
  CURRENT_STAGE="user-scoped tools and VS Code"
  [[ -x "$VENV_DIR/bin/python" ]] || { python3.12 -m venv "$VENV_DIR"; CHANGED=true; }
  local package
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade "$package" || fatal 4 "Required course Python package could not be installed: $package"
    CHANGED=true
  done < <(manifest_query venv_packages)
  local ext
  while IFS= read -r ext; do
    [[ -n "$ext" ]] || continue
    code --install-extension "$ext" --force >/dev/null || fatal 4 "Required Visual Studio Code extension could not be installed: $ext"
    CHANGED=true
  done < <(manifest_query extensions)
  local settings="$HOME/Library/Application Support/Code/User/settings.json" managed
  managed="$(manifest_query vscode_settings)"
  IT140_SETTINGS="$settings" IT140_MANAGED="$managed" IT140_PY="$VENV_DIR/bin/python" python3.12 - <<'PY'
import json,os
from pathlib import Path
p=Path(os.environ['IT140_SETTINGS']); m=json.loads(os.environ['IT140_MANAGED']); m['python.defaultInterpreterPath']=os.environ['IT140_PY']
if p.exists():
 try: d=json.loads(p.read_text(encoding='utf-8'))
 except Exception as e: raise SystemExit(f'existing VS Code settings are invalid and were preserved: {e}')
 if not isinstance(d,dict): raise SystemExit('existing VS Code settings are not an object')
else: d={}
def merge(a,b):
 for k,v in b.items():
  if isinstance(v,dict) and isinstance(a.get(k),dict): merge(a[k],v)
  else: a[k]=v
merge(d,m); p.parent.mkdir(parents=True,exist_ok=True); tmp=p.with_name(p.name+'.it140.tmp'); tmp.write_text(json.dumps(d,indent=4,sort_keys=True)+'\n',encoding='utf-8'); json.loads(tmp.read_text(encoding='utf-8')); tmp.replace(p)
PY
  CHANGED=true
}
validate_configuration(){
  CURRENT_STAGE="configuration validation"
  [[ -d "$REPOS_ROOT" && -w "$REPOS_ROOT" ]] || fatal 1 "Repository workspace validation failed."
  [[ -L "$HOME/Desktop/Repos" && "$(readlink "$HOME/Desktop/Repos")" == "$REPOS_ROOT" ]] || fatal 1 "Desktop Repos link validation failed."
  vscode_repos_launcher_is_valid "$VSCODE_REPOS_LAUNCHER" "$(command -v code 2>/dev/null || true)" || fatal 1 "Visual Studio Code - Repos.app validation failed."
  gh auth status --hostname github.com >/dev/null 2>&1 || fatal 1 "GitHub authentication validation failed."
  [[ -x "$VENV_DIR/bin/python" ]] || fatal 1 "Course virtual environment validation failed."
  grep -Fqx "$MANAGED_ENV_EXPORT" "$HOME/.zprofile" || fatal 1 "Managed PATH is missing from ~/.zprofile."
  grep -Fqx "$MANAGED_ENV_EXPORT" "$HOME/.zshrc" || fatal 1 "Managed PATH is missing from ~/.zshrc."
  [[ "$(grep -Fxc "$MANAGED_ENV_START" "$HOME/.zprofile")" == 1 ]] || fatal 1 "Managed PATH block is duplicated in ~/.zprofile."
  [[ "$(grep -Fxc "$MANAGED_ENV_START" "$HOME/.zshrc")" == 1 ]] || fatal 1 "Managed PATH block is duplicated in ~/.zshrc."
  print_success "Required macOS user configuration passed post-validation."
}
main(){
  parse_options "$@"
  mkdir -p "$LOG_DIR"; chmod 700 "$LOG_DIR"; : > "$LOG_FILE"; chmod 600 "$LOG_FILE"
  exec > >(/usr/bin/tee -a "$LOG_FILE") 2>&1
  trap on_error ERR; trap on_interrupt INT TERM HUP
  print_header "IT 140 macOS CONFIGURE"
  print_info "Script version : $SCRIPT_VERSION"
  print_info "Version DTG    : $VERSION_DTG"
  print_info "Status         : $DEVELOPMENT_STATUS"
  print_info "Current user   : $(id -un)"
  print_info "Purpose        : Configure or repair the current user's IT 140 environment."
  print_info "Course root    : $COURSE_ROOT"
  print_info "Repository root: $REPOS_ROOT"
  print_info "Log file       : $LOG_FILE"
  check_context
  CURRENT_STAGE="controlled manifest validation"
  local manifest_meta
  manifest_meta="$(validate_manifest 2>&1)" || fatal 5 "The controlled manifest or schema is invalid: $manifest_meta"
  IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$manifest_meta"
  print_info "Manifest release: $MANIFEST_RELEASE"
  print_info "Manifest DTG    : $MANIFEST_DTG"
  acquire_lock
  configure_paths
  configure_vscode_repos_launcher
  configure_identity
  configure_tools
  validate_configuration
  finish 0 "Required macOS user configuration and repository-workspace operations completed."
  exit $?
}
main "$@"
