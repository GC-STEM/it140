#!/usr/bin/env bash
# IT 140 Ubuntu Desktop GNOME user configuration and repair script
# Artifact ID: IT140-UBG-CONFIGURE
# Artifact version: 0.8.0-alpha.1
# Version date-time group: 2026-08-07-10-44
# Development status: Alpha Testing
# Traceability: CFG-FR-001 through CFG-FR-021; CFG-DES-001 through CFG-DES-021.
#
# Creates ~/Repos as the student development workspace, applies a GNOME/GIO
# development icon when supported, and creates Desktop/Repos. It never
# recursively modifies repositories or files beneath ~/Repos.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.8.0-alpha.1"
readonly VERSION_DTG="2026-08-07-10-44"
readonly PLATFORM_ID="ubuntu_gnome"
readonly DEPLOYMENT_PROFILE_ID="ubuntu_gnome_bare_metal"
readonly SUPPORTED_SCHEMA="2.2"
readonly COURSE_ROOT="$HOME/it140"
readonly REPOS_ROOT="$HOME/Repos"
readonly SCRIPT_ROOT="$COURSE_ROOT/scripts"
readonly PLATFORM_SCRIPT_DIR="$SCRIPT_ROOT/nix/ubg"
readonly MANIFEST_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="$COURSE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/configure_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_FILE="$HOME/.cache/it140-ubg-mutation.lock"
readonly VENV_DIR="$COURSE_ROOT/.venv"
readonly PATH_START="# >>> IT 140 managed PATH >>>"
readonly PATH_END="# <<< IT 140 managed PATH <<<"
readonly PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/nix/ubg:$PATH"'
NONINTERACTIVE=false
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
CHANGED=false WARNINGS=0 FAILURES=0 MANIFEST_RELEASE="unavailable" CURRENT_STAGE="initialization" FINALIZED=false
header(){ printf '\n============================================================\n%s\n============================================================\n' "$1"; }
info(){ printf '[INFO] %s\n' "$1"; }
success(){ printf '[SUCCESS] %s\n' "$1"; }
notice(){ printf '[NOTICE] %s\n' "$1"; }
warning(){ printf '[WARNING] %s\n' "$1"; WARNINGS=$((WARNINGS+1)); }
error(){ printf '[ERROR] %s\n' "$1" >&2; }
usage(){ cat <<USAGE
Usage: config_ubg.sh [--help] [--version] [--noninteractive]
                     [--deployment-profile ubuntu_gnome_bare_metal]
Configures the current Ubuntu GNOME user, including ~/Repos and Desktop/Repos.
Logs: ~/it140/logs/
USAGE
}
parse(){ while (($#)); do case "$1" in --help|-h) usage; exit 0;; --version) printf '%s (%s)\n' "$SCRIPT_VERSION" "$VERSION_DTG"; exit 0;; --noninteractive) NONINTERACTIVE=true;; --deployment-profile) shift; (($#)) || exit 2; REQUESTED_PROFILE="$1";; *) error "Unsupported option: $1"; exit 2;; esac; shift; done; }
continuity(){ notice "Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved."; }
finish(){
 local code="$1" msg="$2" result=PASS
 [[ "$FINALIZED" == false ]] || return "$code"
 FINALIZED=true
 if ((code)); then
  result=FAIL
  if ((code==7)) || [[ "$CHANGED" == true ]]; then code=7; result=PARTIAL; fi
 fi
 header "CONFIGURATION SUMMARY"
 printf 'Conclusion      : %s\nResult          : %s\nScript version  : %s\nVersion DTG     : %s\nManifest release: %s\nRepository root : %s\nWarnings        : %s\nFailures        : %s\nManaged changes : %s\nLog file        : %s\nExit code       : %s\n' "$msg" "$result" "$SCRIPT_VERSION" "$VERSION_DTG" "$MANIFEST_RELEASE" "$REPOS_ROOT" "$WARNINGS" "$FAILURES" "$( [[ "$CHANGED" == true ]] && printf 'Yes' || printf 'No' )" "$LOG_FILE" "$code"
 ((code==0)) || continuity
 return "$code"
}
fatal(){
 local c="$1" exit_code=0
 shift
 FAILURES=$((FAILURES+1))
 error "$*"
 finish "$c" "$*" || exit_code=$?
 exit "$exit_code"
}
on_error(){
 local c=$?
 local exit_code=0
 trap - ERR
 FAILURES=$((FAILURES+1))
 error "Unexpected failure during $CURRENT_STAGE (status $c)."
 finish 1 "An unexpected command failure stopped Configure." || exit_code=$?
 exit "$exit_code"
}
acquire_lock(){
 CURRENT_STAGE="mutation-lock acquisition"
 command -v flock >/dev/null 2>&1 || fatal 1 "The required flock utility is unavailable; concurrent lifecycle protection cannot be enforced."
 mkdir -p "$(dirname "$LOCK_FILE")"; chmod 700 "$(dirname "$LOCK_FILE")"
 exec 9>"$LOCK_FILE"
 flock --nonblock 9 || fatal 7 "Another IT 140 Ubuntu mutation script is running."
}
validate_manifest(){ python3 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" <<'PY'
import json,pathlib,sys
mp,sp,pid,prof,sv=sys.argv[1:]; m=json.loads(pathlib.Path(mp).read_text()); s=json.loads(pathlib.Path(sp).read_text())
if m.get('schema_version')!=sv: raise SystemExit('unsupported manifest schema')
p=m.get('platforms',{}).get(pid); d=m.get('deployment_profiles',{}).get(prof)
if not p or not p.get('enabled') or not d or not d.get('enabled') or d.get('platform_id')!=pid: raise SystemExit('Ubuntu GNOME profile invalid')
try:
 import jsonschema
except ImportError: pass
else: jsonschema.Draft202012Validator(s).validate(m)
print(m['automation_release'])
PY
}
manifest_query(){ python3 - "$MANIFEST_PATH" "$PLATFORM_ID" "$1" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); b=m['platforms'][sys.argv[2]]['course_ide_bindings']; q=sys.argv[3]
if q=='venv_packages':
 vals=[]
 for role,x in b.items():
  if x.get('required') and x.get('installation_scope')=='user' and x.get('installer_adapter_id')=='python_venv_package': vals.append(x['package_identifier'])
  if role=='code_quality_tool' and x.get('required'): vals.append('ruff')
 print('\n'.join(sorted(set(vals))))
elif q=='extensions': print('\n'.join(x['package_identifier'] for x in b.values() if x.get('required') and x.get('installer_adapter_id')=='vscode_extension'))
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
upsert_path(){ local file="$1"; python3 - "$file" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); a='# >>> IT 140 managed PATH >>>'; b='# <<< IT 140 managed PATH <<<'
block=a+'\n'+'export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/nix/ubg:$PATH"'+'\n'+b+'\n'; t=p.read_text() if p.exists() else ''
if a in t and b in t: t=t.split(a,1)[0].rstrip('\n')+'\n\n'+block+t.split(b,1)[1].lstrip('\n')
else: t=t.rstrip('\n')+('\n\n' if t else '')+block
p.write_text(t)
PY
}
desktop_dir(){ xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop\n' "$HOME"; }
check_context(){ CURRENT_STAGE="execution-context validation"; ((EUID!=0)) || fatal 2 "Do not run config_ubg.sh with sudo."; source /etc/os-release; [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || fatal 2 "This implementation supports Ubuntu 24.04 LTS only."; [[ "$(uname -m)" == x86_64 ]] || fatal 2 "This implementation supports x86_64 only."; [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] || fatal 2 "Unsupported deployment profile."; for c in git gh python3.12 code gio; do command -v "$c" >/dev/null 2>&1 || fatal 1 "Required command is missing: $c.
Run setup_ubg.sh first."; done; }
configure_workspace(){
 CURRENT_STAGE="repository workspace configuration"; mkdir -p "$COURSE_ROOT" "$LOG_DIR" "$PLATFORM_SCRIPT_DIR"; chmod 700 "$LOG_DIR"; touch "$HOME/.bashrc" "$HOME/.profile"; upsert_path "$HOME/.bashrc"; upsert_path "$HOME/.profile"; export PATH="$VENV_DIR/bin:$PLATFORM_SCRIPT_DIR:$PATH"
 if [[ -e "$REPOS_ROOT" && ! -d "$REPOS_ROOT" ]]; then fatal 1 "The required repository workspace path exists but is not a directory."; fi
 [[ -d "$REPOS_ROOT" ]] || { mkdir "$REPOS_ROOT"; CHANGED=true; }; [[ -w "$REPOS_ROOT" ]] || fatal 1 "The repository workspace is not writable."
 local dd link; dd="$(desktop_dir)"; mkdir -p "$dd"; link="$dd/Repos"
 if [[ -L "$link" ]]; then [[ "$(readlink -f "$link")" == "$(readlink -f "$REPOS_ROOT")" ]] || fatal 1 "An existing desktop Repos link targets another location and was preserved."; elif [[ -e "$link" ]]; then fatal 1 "An unmanaged desktop item named Repos already exists and was preserved."; else ln -s "$REPOS_ROOT" "$link"; CHANGED=true; fi
 # GNOME/Nautilus supports GIO folder metadata on qualified versions. Themed
 # icon names let the active icon theme select the concrete artwork.
 if gio set "$REPOS_ROOT" metadata::custom-icon-name applications-development >/dev/null 2>&1; then CHANGED=true; success "Applied the GNOME development icon metadata to $REPOS_ROOT."; else warning "GNOME did not accept development icon metadata; workspace functionality is unaffected."; fi
 success "Repository workspace configured: $REPOS_ROOT"
}
configure_identity(){ CURRENT_STAGE="GitHub authentication and Git identity"; if ! gh auth status --hostname github.com >/dev/null 2>&1; then [[ "$NONINTERACTIVE" == false ]] || fatal 1 "GitHub authentication is required."; printf 'Press Enter to authenticate with GitHub, or type C to cancel: '; local r; IFS= read -r r; [[ "${r,,}" != c ]] || fatal 6 "GitHub authentication canceled."; gh auth login --hostname github.com --git-protocol https --web --clipboard || fatal 4 "GitHub authentication failed."; CHANGED=true; fi; local j aid login name t email entered; j="$(gh api user --jq '{id:.id,login:.login,name:.name}')" || fatal 4 "GitHub account data unavailable."; IFS=$'\t' read -r aid login name < <(python3 - "$j" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(f"{x['id']}\t{x['login']}\t{x.get('name') or x['login']}")
PY
); if [[ "$NONINTERACTIVE" == false ]]; then printf 'Git commit display name [%s]: ' "$name"; IFS= read -r entered; [[ -z "$entered" ]] || name="$entered"; fi; t="$(manifest_query privacy_template)"; email="${t//\$\{ACCOUNT_ID\}/$aid}"; email="${email//\$\{USERNAME\}/$login}"; git config --global user.name "$name"; git config --global user.email "$email"; while IFS=$'\t' read -r k v; do [[ -n "$k" ]] || continue; git config --global "$k" "$v"; done < <(manifest_query git_settings); CHANGED=true; }
configure_tools(){ CURRENT_STAGE="user tools and VS Code settings"; [[ -x "$VENV_DIR/bin/python" ]] || { python3.12 -m venv "$VENV_DIR"; CHANGED=true; }; mapfile -t pkgs < <(manifest_query venv_packages); ((${#pkgs[@]}==0)) || "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade "${pkgs[@]}"; while IFS= read -r ext; do [[ -n "$ext" ]] || continue; code --install-extension "$ext" --force >/dev/null; done < <(manifest_query extensions); local settings="$HOME/.config/Code/User/settings.json" managed; managed="$(manifest_query vscode_settings)"; IT140_SETTINGS="$settings" IT140_MANAGED="$managed" IT140_PY="$VENV_DIR/bin/python" python3 - <<'PY'
import json,os
from pathlib import Path
p=Path(os.environ['IT140_SETTINGS']); m=json.loads(os.environ['IT140_MANAGED']); m['python.defaultInterpreterPath']=os.environ['IT140_PY']
if p.exists():
 try:d=json.loads(p.read_text())
 except Exception as e:raise SystemExit(f'existing VS Code settings invalid and preserved: {e}')
else:d={}
def merge(a,b):
 for k,v in b.items():
  if isinstance(v,dict) and isinstance(a.get(k),dict):merge(a[k],v)
  else:a[k]=v
merge(d,m); p.parent.mkdir(parents=True,exist_ok=True); tmp=p.with_name(p.name+'.it140.tmp'); tmp.write_text(json.dumps(d,indent=4)+'\n'); json.loads(tmp.read_text()); tmp.replace(p)
PY
 CHANGED=true; }
validate(){ CURRENT_STAGE="configuration validation"; [[ -d "$REPOS_ROOT" && -w "$REPOS_ROOT" ]] || fatal 1 "Repository workspace validation failed."; local link="$(desktop_dir)/Repos"; [[ -L "$link" && "$(readlink -f "$link")" == "$(readlink -f "$REPOS_ROOT")" ]] || fatal 1 "Desktop Repos link validation failed."; gh auth status --hostname github.com >/dev/null 2>&1 || fatal 1 "GitHub authentication validation failed."; [[ -x "$VENV_DIR/bin/python" ]] || fatal 1 "Course virtual environment validation failed."; success "Ubuntu GNOME user configuration passed post-validation."; }
main(){ parse "$@"; mkdir -p "$LOG_DIR"; chmod 700 "$LOG_DIR"; touch "$LOG_FILE"; chmod 600 "$LOG_FILE"; exec > >(tee -a "$LOG_FILE") 2>&1; trap on_error ERR; header "IT 140 UBUNTU GNOME CONFIGURE"; info "Script version : $SCRIPT_VERSION"; info "Version DTG    : $VERSION_DTG"; info "Course root    : $COURSE_ROOT"; info "Repository root: $REPOS_ROOT"; info "Log file       : $LOG_FILE"; check_context; CURRENT_STAGE="controlled manifest validation"; MANIFEST_RELEASE="$(validate_manifest)" || fatal 5 "The controlled manifest or schema is invalid."; acquire_lock; configure_workspace; configure_identity; configure_tools; validate; finish 0 "Required Ubuntu GNOME user configuration and repository-workspace operations completed."; }
main "$@"
