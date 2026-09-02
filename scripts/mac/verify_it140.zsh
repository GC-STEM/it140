#!/bin/zsh
# ==============================================================================
# IT 140 COURSE IDE — VERIFY (macOS APPLE SILICON)
# ==============================================================================
# Repository path: scripts/mac/verify_it140.zsh
# Purpose: Read-only verification of the macOS IT 140 course environment.
# Artifact ID: IT140-MAC-VERIFY
# Artifact version: 1.0.3
# Version date-time group: 2026-09-02-09-37
# Development status: Pilot — Active Development
# Supported profile: macos_bare_metal (Apple silicon, arm64)
# Traceability: VER-FR-001 through VER-FR-018; VER-DES-001 through VER-DES-018.
#
# Verification does not write to ~/Repos or repair its desktop integration.
# It verifies the Desktop/Repos link and Visual Studio Code - Repos.app launcher.
# Finder visual-marker status is NOT APPLICABLE by approved design.
#
# Exit codes:
#   0 All required checks passed; warnings may be present
#   1 One or more required checks failed
#   2 The platform, architecture, or deployment profile is unsupported
#   5 Controlled manifest or schema validation failed
# ==============================================================================
set -euo pipefail
umask 077
readonly SCRIPT_VERSION="1.0.3"
readonly VERSION_DTG="2026-09-02-09-37"
readonly DEVELOPMENT_STATUS="Pilot — Active Development"
readonly PLATFORM_ID="macos"
readonly DEPLOYMENT_PROFILE_ID="macos_bare_metal"
readonly SUPPORTED_SCHEMA="2.2"
readonly COURSE_ROOT="$HOME/it140"
readonly REPOS_ROOT="$HOME/Repos"
readonly VSCODE_REPOS_LAUNCHER="$HOME/Desktop/Visual Studio Code - Repos.app"
readonly VSCODE_LAUNCHER_MARKER="IT140-MAC-VSCODE-REPOS-LAUNCHER-v1"
readonly SCRIPT_ROOT="$COURSE_ROOT/scripts"
readonly MANIFEST_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.json"
readonly SCHEMA_PATH="$SCRIPT_ROOT/.manifest/it140_manifest.schema.json"
readonly LOG_DIR="$COURSE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/verify_mac_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="$COURSE_ROOT/.venv"
readonly MANAGED_ENV_START='# >>> IT 140 managed PATH >>>'
readonly MANAGED_ENV_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/mac:/opt/homebrew/bin:$PATH"'
readonly TEST_ROOT="${IT140_VERIFY_TEST_ROOT:-}"
readonly TEST_EUID="${IT140_VERIFY_TEST_EUID:-}"
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
SKIP_NETWORK=false
PASS_COUNT=0
WARNING_COUNT=0
FAIL_COUNT=0
NA_COUNT=0
MANIFEST_FAILURE=false
UNSUPPORTED_FAILURE=false
MANIFEST_RELEASE="unavailable"
MANIFEST_DTG="unavailable"
START_EPOCH="$(date +%s)"
typeset -a REMEDIATIONS
header(){ printf '\n============================================================\n%s\n============================================================\n' "$1"; }
info(){ printf '[INFO] %s\n' "$1"; }
notice(){ printf '[NOTICE] %s\n' "$1"; }
usage(){ cat <<USAGE
Usage: verify_it140.zsh [--help] [--version]
                        [--deployment-profile macos_bare_metal] [--skip-network]
Read-only verification of the macOS IT 140 course environment and ~/Repos.
Logs: ~/it140/logs/
USAGE
}
parse_options(){
  while (( $# )); do
    case "$1" in
      --help|-h) usage; exit 0;;
      --version) printf '%s (%s; %s)\n' "$SCRIPT_VERSION" "$VERSION_DTG" "$DEVELOPMENT_STATUS"; exit 0;;
      --deployment-profile|--profile) shift; (( $# )) || exit 2; REQUESTED_PROFILE="$1";;
      --skip-network) SKIP_NETWORK=true;;
      *) printf '[ERROR] Unsupported option: %s\n' "$1" >&2; exit 2;;
    esac
    shift
  done
}
add_remediation(){ local x="$1" y; [[ -n "$x" ]] || return; for y in "${REMEDIATIONS[@]:-}"; do [[ "$x" == "$y" ]] && return; done; REMEDIATIONS+=("$x"); }
record(){
  local st="$1" id="$2" detail="$3" rem="${4:-}"
  printf '%-14s %-42s %s\n' "$st" "$id" "$detail"
  case "$st" in
    PASS) PASS_COUNT=$((PASS_COUNT+1));;
    WARNING) WARNING_COUNT=$((WARNING_COUNT+1)); add_remediation "$rem";;
    FAIL) FAIL_COUNT=$((FAIL_COUNT+1)); add_remediation "$rem";;
    'NOT APPLICABLE') NA_COUNT=$((NA_COUNT+1));;
  esac
}
config_remediation(){ printf 'Run configure_it140.zsh to repair current-user configuration.\n'; }
install_remediation(){ printf 'Run install_it140.zsh to repair required system software, then rerun verify_it140.zsh.\n'; }
continuity(){ notice "Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved."; }
effective_euid(){
  if [[ -n "$TEST_ROOT" && -n "$TEST_EUID" ]]; then printf '%s\n' "$TEST_EUID"; else printf '%s\n' "$EUID"; fi
}
validate_manifest(){
  python3.12 - "$MANIFEST_PATH" "$SCHEMA_PATH" "$PLATFORM_ID" "$REQUESTED_PROFILE" "$SUPPORTED_SCHEMA" "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1 || true)" <<'PY'
import json,pathlib,sys
mp,sp,pid,prof,sv,os_major=sys.argv[1:]
def unique(pairs):
 out={}
 for k,v in pairs:
  if k in out: raise ValueError(f'duplicate JSON key: {k}')
  out[k]=v
 return out
m=json.loads(pathlib.Path(mp).read_text(encoding='utf-8'),object_pairs_hook=unique)
s=json.loads(pathlib.Path(sp).read_text(encoding='utf-8'),object_pairs_hook=unique)
if m.get('schema_version')!=sv: raise SystemExit('unsupported manifest schema')
if s.get('$schema')!='https://json-schema.org/draft/2020-12/schema': raise SystemExit('unsupported JSON Schema draft')
p=m.get('platforms',{}).get(pid); d=m.get('deployment_profiles',{}).get(prof)
if not p or not p.get('enabled') or not d or not d.get('enabled') or d.get('platform_id')!=pid or d.get('architecture')!='arm64': raise SystemExit('macOS profile invalid')
if os_major not in {str(x.get('release_id')) for x in p.get('os',{}).get('releases',[])}: raise SystemExit(f'unsupported macOS release: {os_major}')
if m.get('policy',{}).get('allow_os_release_upgrade') is not False: raise SystemExit('manifest must prohibit operating-system release upgrades')
try:
 import jsonschema
except ImportError: pass
else:
 jsonschema.Draft202012Validator.check_schema(s); jsonschema.Draft202012Validator(s).validate(m)
print(f"{m['automation_release']}\t{m['automation_release_date_time_group']}")
PY
}
manifest_query(){
  python3.12 - "$MANIFEST_PATH" "$PLATFORM_ID" "$1" <<'PY'
import json,sys
m=json.load(open(sys.argv[1],encoding='utf-8')); b=m['platforms'][sys.argv[2]]['course_ide_bindings']; q=sys.argv[3]
if q=='system_commands':
 vals=[]
 for x in b.values():
  if x.get('required') and x.get('installation_scope')=='system':
   for n in x.get('verification',{}).get('executable_names',[]):
    if n not in vals: vals.append(n)
 print('\n'.join(vals))
elif q=='venv_packages':
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
PY
}
check_platform(){
  if [[ "$(uname -s)" == Darwin ]]; then record PASS verify.os "macOS"; else UNSUPPORTED_FAILURE=true; record FAIL verify.os "not macOS" "Use the approved macOS environment."; fi
  if [[ "$(uname -m)" == arm64 ]]; then record PASS verify.architecture arm64; else UNSUPPORTED_FAILURE=true; record FAIL verify.architecture "$(uname -m)" "Use an approved Apple silicon Mac."; fi
  (( $(effective_euid) != 0 )) && record PASS verify.user_context "standard user" || record FAIL verify.user_context root "Run Verify without sudo."
}
check_system(){
  /usr/bin/xcode-select -p >/dev/null 2>&1 && record PASS verify.command_line_tools available || record FAIL verify.command_line_tools missing "$(install_remediation)"
  if [[ -x /opt/homebrew/bin/brew ]] || command -v brew >/dev/null 2>&1; then record PASS verify.homebrew available; else record FAIL verify.homebrew missing "$(install_remediation)"; fi
  local cmd
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    command -v "$cmd" >/dev/null 2>&1 && record PASS "verify.command.$cmd" available || record FAIL "verify.command.$cmd" missing "$(install_remediation)"
  done < <(manifest_query system_commands)
  command -v python3.12 >/dev/null 2>&1 && [[ "$(python3.12 -c 'import sys; print(sys.version_info[:2] == (3, 12))')" == True ]] \
    && record PASS verify.python_runtime "Python $(python3.12 -c 'import platform; print(platform.python_version())')" \
    || record FAIL verify.python_runtime "Python 3.12 unavailable" "$(install_remediation)"
}
check_network(){
  if [[ "$SKIP_NETWORK" == true ]]; then record WARNING verify.network "skipped by option" "Rerun without --skip-network."; return; fi
  /usr/bin/curl -Is --max-time 10 https://github.com/ >/dev/null 2>&1 && record PASS verify.network "github.com reachable" || record WARNING verify.network "github.com unreachable" "Check the network and rerun Verify."
}
vscode_repos_launcher_is_valid(){
  local launcher="$VSCODE_REPOS_LAUNCHER" code_cli
  code_cli="$(command -v code 2>/dev/null || true)"
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
if p.get('CFBundleIdentifier')!='edu.snhu.it140.vscode-repos' or p.get('CFBundleExecutable')!='open-repos' or p.get('CFBundlePackageType')!='APPL' or p.get('LSArchitecturePriority')!=['arm64']: raise SystemExit(1)
expected=("#!/bin/zsh\n"+f"# {marker}\n"+"set -euo pipefail\n"+f"readonly REPOS_ROOT={shlex.quote(repos)}\n"+f"readonly CODE_CLI={shlex.quote(code)}\n"+'cd -- "$REPOS_ROOT"\n'+'exec "$CODE_CLI" --reuse-window "$REPOS_ROOT"\n')
if exe.read_text(encoding='utf-8')!=expected: raise SystemExit(1)
PY
}
check_user(){
  [[ -d "$COURSE_ROOT" ]] && record PASS verify.course_root "$COURSE_ROOT" || record FAIL verify.course_root missing "Run prepare_it140.zsh to refresh the course automation package."
  [[ -d "$LOG_DIR" && -w "$LOG_DIR" ]] && record PASS verify.log_directory "$LOG_DIR" || record FAIL verify.log_directory "missing or not writable" "Run prepare_it140.zsh."
  grep -Fqx "$MANAGED_ENV_EXPORT" "$HOME/.zprofile" 2>/dev/null && [[ "$(grep -Fxc "$MANAGED_ENV_START" "$HOME/.zprofile" 2>/dev/null || true)" == 1 ]] && record PASS verify.path_zprofile configured || record FAIL verify.path_zprofile "missing or duplicated" "$(config_remediation)"
  grep -Fqx "$MANAGED_ENV_EXPORT" "$HOME/.zshrc" 2>/dev/null && [[ "$(grep -Fxc "$MANAGED_ENV_START" "$HOME/.zshrc" 2>/dev/null || true)" == 1 ]] && record PASS verify.path_zshrc configured || record FAIL verify.path_zshrc "missing or duplicated" "$(config_remediation)"
  [[ -x "$VENV_DIR/bin/python" ]] && record PASS verify.venv "$VENV_DIR" || record FAIL verify.venv missing "$(config_remediation)"
  local pkg ext installed key expected actual lower_ext github_id github_login expected_email
  if [[ -x "$VENV_DIR/bin/python" ]]; then
    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] || continue
      "$VENV_DIR/bin/python" -m pip show "$pkg" >/dev/null 2>&1 && record PASS "verify.python_package.$pkg" installed || record FAIL "verify.python_package.$pkg" missing "$(config_remediation)"
    done < <(manifest_query venv_packages)
  fi
  if command -v code >/dev/null 2>&1; then
    installed="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r ext; do
      [[ -n "$ext" ]] || continue
      lower_ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
      grep -Fqx "$lower_ext" <<< "$installed" && record PASS "verify.extension.$ext" installed || record FAIL "verify.extension.$ext" missing "$(config_remediation)"
    done < <(manifest_query extensions)
  fi
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    record PASS verify.github_auth authenticated
    github_id="$(gh api user --jq .id 2>/dev/null || true)"
    github_login="$(gh api user --jq .login 2>/dev/null || true)"
  else
    record FAIL verify.github_auth missing "$(config_remediation)"
    github_id=""
    github_login=""
  fi
  [[ -n "$(git config --global --get user.name 2>/dev/null || true)" ]] && record PASS verify.git_name configured || record FAIL verify.git_name missing "$(config_remediation)"
  actual="$(git config --global --get user.email 2>/dev/null || true)"
  if [[ -n "$github_id" && -n "$github_login" ]]; then
    expected_email="${github_id}+${github_login}@users.noreply.github.com"
    [[ "$actual" == "$expected_email" ]] && record PASS verify.git_email "$actual" || record FAIL verify.git_email "expected '$expected_email'; got '$actual'" "$(config_remediation)"
  else
    record FAIL verify.git_email "unable to validate without authenticated GitHub identity" "$(config_remediation)"
  fi
  while IFS=$'\t' read -r key expected; do
    [[ -n "$key" ]] || continue
    actual="$(git config --global --get "$key" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] && record PASS "verify.git_setting.$key" "$expected" || record FAIL "verify.git_setting.$key" "expected '$expected'; got '$actual'" "$(config_remediation)"
  done < <(manifest_query git_settings)
  local settings="$HOME/Library/Application Support/Code/User/settings.json" managed
  managed="$(manifest_query vscode_settings)"
  if [[ -f "$settings" ]] && IT140_SETTINGS="$settings" IT140_MANAGED="$managed" IT140_PY="$VENV_DIR/bin/python" python3.12 - <<'PY'
import json,os
m=json.loads(os.environ['IT140_MANAGED']); m['python.defaultInterpreterPath']=os.environ['IT140_PY']; a=json.load(open(os.environ['IT140_SETTINGS'],encoding='utf-8'))
def inc(a,e): return all(k in a and (inc(a[k],v) if isinstance(v,dict) and isinstance(a[k],dict) else a[k]==v) for k,v in e.items())
raise SystemExit(0 if isinstance(a,dict) and inc(a,m) else 1)
PY
  then record PASS verify.vscode_settings configured; else record FAIL verify.vscode_settings "missing or different" "$(config_remediation)"; fi
  [[ -d "$REPOS_ROOT" && -r "$REPOS_ROOT" && -x "$REPOS_ROOT" && -w "$REPOS_ROOT" ]] && record PASS verify.repository_workspace "$REPOS_ROOT" || record FAIL verify.repository_workspace "missing or inaccessible" "$(config_remediation)"
  [[ -L "$HOME/Desktop/Repos" && "$(readlink "$HOME/Desktop/Repos")" == "$REPOS_ROOT" ]] && record PASS verify.repository_workspace_desktop "Desktop/Repos -> $REPOS_ROOT" || record FAIL verify.repository_workspace_desktop incorrect "$(config_remediation)"
  record 'NOT APPLICABLE' verify.repository_workspace_marker "Finder has no approved built-in development-emblem adapter"
  vscode_repos_launcher_is_valid && record PASS verify.repository_workspace_vscode_launcher "Visual Studio Code - Repos.app opens $REPOS_ROOT" || record FAIL verify.repository_workspace_vscode_launcher "missing, unmanaged, or incorrect" "$(config_remediation)"
}
resolve_exit_code(){
  if [[ "$MANIFEST_FAILURE" == true ]]; then printf '5\n'; return; fi
  if [[ "$UNSUPPORTED_FAILURE" == true ]]; then printf '2\n'; return; fi
  if (( FAIL_COUNT > 0 )); then printf '1\n'; return; fi
  printf '0\n'
}
main(){
  parse_options "$@"
  mkdir -p "$LOG_DIR"; chmod 700 "$LOG_DIR"; : > "$LOG_FILE"; chmod 600 "$LOG_FILE"
  if [[ -n "$TEST_ROOT" ]]; then exec >>"$LOG_FILE" 2>&1; else exec > >(/usr/bin/tee -a "$LOG_FILE") 2>&1; fi
  header "IT 140 macOS VERIFY"
  info "Script version : $SCRIPT_VERSION"
  info "Version DTG    : $VERSION_DTG"
  info "Status         : $DEVELOPMENT_STATUS"
  info "Current user   : $(id -un)"
  info "Purpose        : Read-only verification of the macOS IT 140 course environment."
  info "Course root    : $COURSE_ROOT"
  info "Repository root: $REPOS_ROOT"
  info "Log file       : $LOG_FILE"
  notice "Verify is read-only except for this transcript."
  if [[ "$REQUESTED_PROFILE" != "$DEPLOYMENT_PROFILE_ID" ]]; then
    UNSUPPORTED_FAILURE=true
    record FAIL verify.profile "unsupported profile" "Use macos_bare_metal."
  fi
  check_platform
  if [[ "$UNSUPPORTED_FAILURE" != true ]]; then
    if [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]] && command -v python3.12 >/dev/null 2>&1; then
      local manifest_meta
      if manifest_meta="$(validate_manifest 2>&1)"; then
        IFS=$'\t' read -r MANIFEST_RELEASE MANIFEST_DTG <<< "$manifest_meta"
        record PASS verify.manifest "release $MANIFEST_RELEASE ($MANIFEST_DTG)"
        check_network; check_system; check_user
      else
        MANIFEST_FAILURE=true
        record FAIL verify.manifest "$manifest_meta" "Run prepare_it140.zsh, then install_it140.zsh."
      fi
    else
      MANIFEST_FAILURE=true
      record FAIL verify.manifest "manifest/schema or Python 3.12 missing" "Run prepare_it140.zsh, then install_it140.zsh."
    fi
  fi
  local code result
  code="$(resolve_exit_code)"
  result=COMPLIANT
  (( code == 0 )) || result='NOT COMPLIANT'
  header "VERIFICATION SUMMARY"
  printf 'Result          : %s\n' "$result"
  printf 'Script version  : %s\n' "$SCRIPT_VERSION"
  printf 'Version DTG     : %s\n' "$VERSION_DTG"
  printf 'Development stat: %s\n' "$DEVELOPMENT_STATUS"
  printf 'Manifest release: %s\n' "$MANIFEST_RELEASE"
  printf 'Manifest DTG    : %s\n' "$MANIFEST_DTG"
  printf 'Passed          : %s\n' "$PASS_COUNT"
  printf 'Warnings        : %s\n' "$WARNING_COUNT"
  printf 'Failed          : %s\n' "$FAIL_COUNT"
  printf 'Not applicable  : %s\n' "$NA_COUNT"
  printf 'Elapsed time    : %s seconds\n' "$(( $(date +%s) - START_EPOCH ))"
  printf 'Log file        : %s\n' "$LOG_FILE"
  printf 'Exit code       : %s\n' "$code"
  if (( ${#REMEDIATIONS[@]} )); then printf '\nRemediation:\n'; local r; for r in "${REMEDIATIONS[@]}"; do printf -- '- %s\n' "$r"; done; fi
  (( code == 0 )) || continuity
  exit "$code"
}
main "$@"
