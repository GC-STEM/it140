#!/bin/zsh
# IT 140 macOS user configuration and repair script
# Artifact ID: IT140-MAC-CONFIGURE
# Artifact version: 0.8.0-alpha.1
# Version date-time group: 2026-08-07-10-44
# Development status: Alpha Testing
# Traceability: CFG-FR-001 through CFG-FR-021; CFG-DES-001 through CFG-DES-021.
#
# This script creates ~/Repos as the student development workspace and a
# Desktop/Repos link. Finder has no supported stable built-in emblem interface
# suitable for this automation package, so the visual-marker adapter is N/A.
# Student repositories beneath ~/Repos are never recursively managed.

set -euo pipefail
umask 077

readonly SCRIPT_VERSION="0.8.0-alpha.1"
readonly VERSION_DTG="2026-08-07-10-44"
readonly DEVELOPMENT_STATUS="Alpha Testing"
readonly PLATFORM_ID="macos"
readonly DEPLOYMENT_PROFILE_ID="macos_bare_metal"
readonly SUPPORTED_SCHEMA="2.2"
readonly COURSE_ROOT="$HOME/it140"
readonly REPOS_ROOT="$HOME/Repos"
readonly SCRIPT_ROOT="$COURSE_ROOT/scripts"
readonly PLATFORM_SCRIPT_DIR="$SCRIPT_ROOT/mac"
readonly MANIFEST_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="$COURSE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/configure_mac_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="$COURSE_ROOT/.venv"
readonly MANAGED_ENV_START="# >>> IT 140 managed PATH >>>"
readonly MANAGED_ENV_END="# <<< IT 140 managed PATH <<<"
readonly MANAGED_ENV_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:/usr/local/bin:$PATH"'

readonly EXIT_SUCCESS=0 EXIT_FAILURE=1 EXIT_UNSUPPORTED=2 EXIT_EXTERNAL=4 EXIT_MANIFEST=5 EXIT_CANCELED=6 EXIT_PARTIAL=7
NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false
WARNINGS=0
FAILURES=0
CURRENT_STAGE="initialization"
START_EPOCH="$(date +%s)"
START_TIME="$(date '+%Y-%m-%dT%H:%M:%S%z')"
MANIFEST_RELEASE="unavailable"
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

Configures the current macOS user for IT 140, including ~/Repos and a Desktop
Repos link. It does not install system software or alter repositories in ~/Repos.
Logs: ~/it140/logs/
USAGE
}
parse_options(){
  while (( $# )); do
    case "$1" in
      --help|-h) usage; exit 0;;
      --version) printf '%s (%s; %s)\n' "$SCRIPT_VERSION" "$VERSION_DTG" "$DEVELOPMENT_STATUS"; exit 0;;
      --noninteractive) NONINTERACTIVE=true;;
      --deployment-profile) shift; (( $# )) || { print_error "Missing deployment profile."; exit 2; }; REQUESTED_PROFILE="$1";;
      *) print_error "Unsupported option: $1"; usage >&2; exit 2;;
    esac
    shift
  done
}

course_continuity(){
  print_notice "Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved."
}
finish(){
  local requested="${1:-0}" message="${2:-}" result="PASS" code=0 next="Open a new Terminal and run verify_it140.zsh."
  [[ "$FINALIZED" == false ]] || return "$requested"; FINALIZED=true
  if (( requested != 0 )); then code=$requested; result="FAIL"; [[ "$CHANGED" == true ]] && code=$EXIT_PARTIAL; next="Resolve the reported issue, then rerun configure_it140.zsh."; fi
  print_header "CONFIGURATION SUMMARY"
  [[ -n "$message" ]] && printf 'Conclusion       : %s\n' "$message"
  printf 'Result           : %s\nScript version   : %s\nVersion DTG      : %s\nManifest release : %s\nRepository root  : %s\nWarnings         : %s\nFailures         : %s\nNext step        : %s\nLog file         : %s\nExit code        : %s\n' "$result" "$SCRIPT_VERSION" "$VERSION_DTG" "$MANIFEST_RELEASE" "$REPOS_ROOT" "$WARNINGS" "$FAILURES" "$next" "$LOG_FILE" "$code"
  (( code == 0 )) && print_success "The macOS user configuration completed successfully." || course_continuity
  return "$code"
}
fatal(){ local code="$1"; shift; FAILURES=$((FAILURES+1)); print_error "$*"; print_error "Failed stage: $CURRENT_STAGE"; finish "$code" "$*"; exit $?; }
on_error(){ local status=$?; trap - ERR; FAILURES=$((FAILURES+1)); print_error "Configuration stopped during $CURRENT_STAGE (status $status)."; finish 1 "An unexpected command failure stopped Configure."; exit $?; }
on_interrupt(){ trap - INT TERM; print_error "Configuration was interrupted during $CURRENT_STAGE."; finish 6 "Configure was interrupted; rerun it to recover."; exit $?; }

validate_manifest(){
  python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
import json,pathlib,sys
m,s,p,profile,ver=sys.argv[1:]; manifest=json.loads(pathlib.Path(m).read_text()); schema=json.loads(pathlib.Path(s).read_text())
if manifest.get('schema_version')!=ver: raise SystemExit('unsupported manifest schema')
plat=manifest.get('platforms',{}).get(p); prof=manifest.get('deployment_profiles',{}).get(profile)
if not plat or not plat.get('enabled'): raise SystemExit('macOS platform missing or disabled')
if not prof or not prof.get('enabled') or prof.get('platform_id')!=p: raise SystemExit('macOS deployment profile invalid')
try:
 import jsonschema
except ImportError: pass
else: jsonschema.Draft202012Validator(schema).validate(manifest)
print(manifest['automation_release'])
PY
}
manifest_query(){
  python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$1" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); p=m['platforms'][sys.argv[2]]; q=sys.argv[3]; b=p['course_ide_bindings']
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
elif q=='privacy_template': print(m['provider_profiles']['github_com']['privacy_identity']['template'])
PY
}

check_context(){
  CURRENT_STAGE="execution-context validation"
  [[ "$(uname -s)" == Darwin ]] || fatal 2 "This script supports macOS only."
  [[ "$(uname -m)" == arm64 ]] || fatal 2 "This implementation supports Apple silicon (arm64) only."
  [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] || fatal 2 "Unsupported deployment profile: $REQUESTED_PROFILE"
  (( EUID != 0 )) || fatal 2 "Do not run configure_it140.zsh with sudo."
  local major; major="$(sw_vers -productVersion | cut -d. -f1)"
  case "$major" in 14|15|26) ;; *) fatal 2 "Unsupported macOS major release: $major";; esac
  for cmd in git gh python3.12 code; do command -v "$cmd" >/dev/null 2>&1 || fatal 1 "Required system command is missing: $cmd. Run install_it140.zsh first."; done
}

upsert_path(){
  local file="$1"
  python3 - "$file" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); a='# >>> IT 140 managed PATH >>>'; b='# <<< IT 140 managed PATH <<<'
block=a+'\n'+'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:/usr/local/bin:$PATH"'+'\n'+b+'\n'
t=p.read_text() if p.exists() else ''
if a in t and b in t: t=t.split(a,1)[0].rstrip('\n')+'\n\n'+block+t.split(b,1)[1].lstrip('\n')
else: t=t.rstrip('\n')+('\n\n' if t else '')+block
p.write_text(t)
PY
}

configure_paths(){
  CURRENT_STAGE="course paths and repository workspace"
  mkdir -p "$COURSE_ROOT" "$LOG_DIR" "$PLATFORM_SCRIPT_DIR"; chmod 700 "$LOG_DIR"
  touch "$HOME/.zprofile" "$HOME/.zshrc"; upsert_path "$HOME/.zprofile"; upsert_path "$HOME/.zshrc"
  export PATH="$VENV_DIR/bin:$PLATFORM_SCRIPT_DIR:/opt/homebrew/bin:/usr/local/bin:$PATH"
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
  IFS=$'\t' read -r aid login name <<< "$(python3 - "$json" <<'PY'
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
  local -a packages; packages=(${(f)"$(manifest_query venv_packages)"})
  (( ${#packages[@]} == 0 )) || "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade "${packages[@]}"
  local ext; while IFS= read -r ext; do [[ -n "$ext" ]] || continue; code --install-extension "$ext" --force >/dev/null; done < <(manifest_query extensions)
  local settings="$HOME/Library/Application Support/Code/User/settings.json" managed
  managed="$(manifest_query vscode_settings)"
  IT140_SETTINGS="$settings" IT140_MANAGED="$managed" IT140_PY="$VENV_DIR/bin/python" python3 - <<'PY'
import json,os
from pathlib import Path
p=Path(os.environ['IT140_SETTINGS']); m=json.loads(os.environ['IT140_MANAGED']); m['python.defaultInterpreterPath']=os.environ['IT140_PY']
if p.exists():
 try: d=json.loads(p.read_text())
 except Exception as e: raise SystemExit(f'existing VS Code settings are invalid and were preserved: {e}')
 if not isinstance(d,dict): raise SystemExit('existing VS Code settings are not an object')
else: d={}
def merge(a,b):
 for k,v in b.items():
  if isinstance(v,dict) and isinstance(a.get(k),dict): merge(a[k],v)
  else: a[k]=v
merge(d,m); p.parent.mkdir(parents=True,exist_ok=True); tmp=p.with_name(p.name+'.it140.tmp'); tmp.write_text(json.dumps(d,indent=4)+'\n'); json.loads(tmp.read_text()); tmp.replace(p)
PY
  CHANGED=true
}

validate_configuration(){
  CURRENT_STAGE="configuration validation"
  [[ -d "$REPOS_ROOT" && -w "$REPOS_ROOT" ]] || fatal 1 "Repository workspace validation failed."
  [[ -L "$HOME/Desktop/Repos" && "$(readlink "$HOME/Desktop/Repos")" == "$REPOS_ROOT" ]] || fatal 1 "Desktop Repos link validation failed."
  gh auth status --hostname github.com >/dev/null 2>&1 || fatal 1 "GitHub authentication validation failed."
  [[ -x "$VENV_DIR/bin/python" ]] || fatal 1 "Course virtual environment validation failed."
  grep -Fqx "$MANAGED_ENV_EXPORT" "$HOME/.zprofile" || fatal 1 "Managed PATH is missing from ~/.zprofile."
  grep -Fqx "$MANAGED_ENV_EXPORT" "$HOME/.zshrc" || fatal 1 "Managed PATH is missing from ~/.zshrc."
  print_success "Required macOS user configuration passed post-validation."
}

main(){
  parse_options "$@"; mkdir -p "$LOG_DIR"; chmod 700 "$LOG_DIR"; touch "$LOG_FILE"; chmod 600 "$LOG_FILE"; exec > >(tee -a "$LOG_FILE") 2>&1
  trap on_error ERR; trap on_interrupt INT TERM
  print_header "IT 140 MACOS CONFIGURE"; print_info "Script version : $SCRIPT_VERSION"; print_info "Version DTG    : $VERSION_DTG"; print_info "Current user   : $(id -un)"; print_info "Course root    : $COURSE_ROOT"; print_info "Repository root: $REPOS_ROOT"; print_info "Log file       : $LOG_FILE"
  check_context
  CURRENT_STAGE="controlled manifest validation"; MANIFEST_RELEASE="$(validate_manifest)" || fatal 5 "The controlled manifest or schema is invalid."
  configure_paths; configure_identity; configure_tools; validate_configuration
  finish 0 "Required macOS user configuration and repository-workspace operations completed."
}
main "$@"
