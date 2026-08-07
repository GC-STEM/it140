#!/usr/bin/env bash
# IT 140 Ubuntu Desktop GNOME read-only verification script
# Artifact ID: IT140-UBG-VERIFY
# Artifact version: 0.8.0-alpha.1
# Version date-time group: 2026-08-07-10-44
# Development status: Alpha Testing
# Traceability: VER-FR-001 through VER-FR-018; VER-DES-001 through VER-DES-018.
#
# Verification performs shallow checks of ~/Repos and its desktop integration;
# it never writes into or recursively traverses student repositories.

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
readonly LOG_FILE="$LOG_DIR/verify_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="$COURSE_ROOT/.venv"
readonly PATH_EXPORT='export PATH="$HOME/it140/.venv/bin:$HOME/it140/scripts/nix/ubg:$PATH"'
REQUESTED_PROFILE="$DEPLOYMENT_PROFILE_ID"
SKIP_NETWORK=false
PASS_COUNT=0 WARNING_COUNT=0 FAIL_COUNT=0 NA_COUNT=0 MANIFEST_RELEASE="unavailable"
declare -a REMEDIATIONS=()

header(){ printf '\n============================================================\n%s\n============================================================\n' "$1"; }
info(){ printf '[INFO] %s\n' "$1"; }
notice(){ printf '[NOTICE] %s\n' "$1"; }
usage(){ cat <<USAGE
Usage: verify_ubg.sh [--help] [--version]
                     [--deployment-profile ubuntu_gnome_bare_metal]
                     [--skip-network]
Read-only verification of the Ubuntu GNOME IT 140 environment and ~/Repos.
USAGE
}
parse(){ while (($#)); do case "$1" in --help|-h) usage; exit 0;; --version) printf '%s (%s)\n' "$SCRIPT_VERSION" "$VERSION_DTG"; exit 0;; --deployment-profile) shift; (($#)) || exit 2; REQUESTED_PROFILE="$1";; --skip-network) SKIP_NETWORK=true;; *) printf '[ERROR] Unsupported option: %s\n' "$1" >&2; exit 2;; esac; shift; done; }
add_remediation(){ local t="$1" x; [[ -n "$t" ]] || return; for x in "${REMEDIATIONS[@]:-}"; do [[ "$x" == "$t" ]] && return; done; REMEDIATIONS+=("$t"); }
record(){ local st="$1" id="$2" detail="$3" rem="${4:-}"; printf '%-14s %-38s %s\n' "$st" "$id" "$detail"; case "$st" in PASS) PASS_COUNT=$((PASS_COUNT+1));; WARNING) WARNING_COUNT=$((WARNING_COUNT+1)); add_remediation "$rem";; FAIL) FAIL_COUNT=$((FAIL_COUNT+1)); add_remediation "$rem";; 'NOT APPLICABLE') NA_COUNT=$((NA_COUNT+1));; esac; }
config_remediation(){ printf 'Run config_ubg.sh to repair current-user configuration.\n'; }
setup_remediation(){ printf 'Run setup_ubg.sh to repair required system software, then rerun verify_ubg.sh.\n'; }
continuity(){ notice "Course continuity: You can continue your IT 140 coursework in the Codio Virtual Desktop (CVD) while this local course IDE issue is resolved."; }
desktop_dir(){ xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop\n' "$HOME"; }

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
PY
}

check_platform(){ source /etc/os-release; [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] && record PASS verify.os "${PRETTY_NAME:-Ubuntu 24.04}" || record FAIL verify.os "unsupported OS" "Use Ubuntu 24.04 LTS GNOME."; [[ "$(uname -m)" == x86_64 ]] && record PASS verify.architecture x86_64 || record FAIL verify.architecture "$(uname -m)" "Use the approved x86_64 profile."; ((EUID!=0)) && record PASS verify.user_context "standard user" || record FAIL verify.user_context root "Run Verify without sudo."; command -v gio >/dev/null 2>&1 && record PASS verify.gio available || record FAIL verify.gio missing "$(setup_remediation)"; }
check_network(){ [[ "$SKIP_NETWORK" == true ]] && { record WARNING verify.network skipped "Rerun without --skip-network."; return; }; curl -Is --max-time 10 https://github.com/ >/dev/null 2>&1 && record PASS verify.network "github.com reachable" || record WARNING verify.network "github.com unreachable" "Check the network and rerun Verify."; }
check_system(){ local c; for c in git gh python3.12 code gio; do command -v "$c" >/dev/null 2>&1 && record PASS "verify.command.$c" available || record FAIL "verify.command.$c" missing "$(setup_remediation)"; done; }
check_user(){
 [[ -d "$COURSE_ROOT" ]] && record PASS verify.course_root "$COURSE_ROOT" || record FAIL verify.course_root missing "Run bootstrap_ubg.sh to refresh the course package."
 [[ -d "$LOG_DIR" && -w "$LOG_DIR" ]] && record PASS verify.log_directory "$LOG_DIR" || record FAIL verify.log_directory "missing or not writable" "Run bootstrap_ubg.sh."
 grep -Fqx "$PATH_EXPORT" "$HOME/.bashrc" 2>/dev/null && record PASS verify.path_bashrc configured || record FAIL verify.path_bashrc missing "$(config_remediation)"
 grep -Fqx "$PATH_EXPORT" "$HOME/.profile" 2>/dev/null && record PASS verify.path_profile configured || record FAIL verify.path_profile missing "$(config_remediation)"
 [[ -x "$VENV_DIR/bin/python" ]] && record PASS verify.venv "$VENV_DIR" || record FAIL verify.venv missing "$(config_remediation)"
 local pkg ext installed key expected actual
 if [[ -x "$VENV_DIR/bin/python" ]]; then while IFS= read -r pkg; do [[ -n "$pkg" ]] || continue; "$VENV_DIR/bin/python" -m pip show "$pkg" >/dev/null 2>&1 && record PASS "verify.python_package.$pkg" installed || record FAIL "verify.python_package.$pkg" missing "$(config_remediation)"; done < <(manifest_query venv_packages); fi
 if command -v code >/dev/null 2>&1; then installed="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"; while IFS= read -r ext; do [[ -n "$ext" ]] || continue; grep -Fqx "${ext,,}" <<< "$installed" && record PASS "verify.extension.$ext" installed || record FAIL "verify.extension.$ext" missing "$(config_remediation)"; done < <(manifest_query extensions); fi
 gh auth status --hostname github.com >/dev/null 2>&1 && record PASS verify.github_auth authenticated || record FAIL verify.github_auth missing "$(config_remediation)"
 [[ -n "$(git config --global --get user.name 2>/dev/null || true)" ]] && record PASS verify.git_name configured || record FAIL verify.git_name missing "$(config_remediation)"
 [[ "$(git config --global --get user.email 2>/dev/null || true)" == *@users.noreply.github.com ]] && record PASS verify.git_email private || record FAIL verify.git_email invalid "$(config_remediation)"
 while IFS=$'\t' read -r key expected; do [[ -n "$key" ]] || continue; actual="$(git config --global --get "$key" 2>/dev/null || true)"; [[ "$actual" == "$expected" ]] && record PASS "verify.git_setting.$key" "$expected" || record FAIL "verify.git_setting.$key" "expected '$expected'; got '$actual'" "$(config_remediation)"; done < <(manifest_query git_settings)
 local settings="$HOME/.config/Code/User/settings.json" managed="$(manifest_query vscode_settings)"
 if [[ -f "$settings" ]] && IT140_SETTINGS="$settings" IT140_MANAGED="$managed" IT140_PY="$VENV_DIR/bin/python" python3 - <<'PY'
import json,os
m=json.loads(os.environ['IT140_MANAGED']); m['python.defaultInterpreterPath']=os.environ['IT140_PY']; a=json.load(open(os.environ['IT140_SETTINGS']))
def inc(a,e): return all(k in a and (inc(a[k],v) if isinstance(v,dict) and isinstance(a[k],dict) else a[k]==v) for k,v in e.items())
raise SystemExit(0 if isinstance(a,dict) and inc(a,m) else 1)
PY
 then record PASS verify.vscode_settings configured; else record FAIL verify.vscode_settings "missing or different" "$(config_remediation)"; fi

 # Shallow repository-workspace checks only.
 [[ -d "$REPOS_ROOT" && -r "$REPOS_ROOT" && -x "$REPOS_ROOT" ]] && record PASS verify.repository_workspace "$REPOS_ROOT" || record FAIL verify.repository_workspace missing "$(config_remediation)"
 local link="$(desktop_dir)/Repos"; [[ -L "$link" && "$(readlink -f "$link")" == "$(readlink -f "$REPOS_ROOT" 2>/dev/null || true)" ]] && record PASS verify.repository_workspace_desktop "Desktop/Repos -> $REPOS_ROOT" || record FAIL verify.repository_workspace_desktop incorrect "$(config_remediation)"
 local marker="$(gio info -a metadata::custom-icon-name "$REPOS_ROOT" 2>/dev/null || true)"; if grep -Eq 'metadata::custom-icon-name:.*applications-development' <<< "$marker"; then record PASS verify.repository_workspace_marker "GNOME development icon metadata present"; else record WARNING verify.repository_workspace_marker "GNOME development icon metadata unavailable or not rendered" "Run config_ubg.sh; workspace functionality is unaffected if GNOME does not support the marker."; fi
}

main(){ parse "$@"; mkdir -p "$LOG_DIR"; chmod 700 "$LOG_DIR"; touch "$LOG_FILE"; chmod 600 "$LOG_FILE"; exec > >(tee -a "$LOG_FILE") 2>&1; header "IT 140 UBUNTU GNOME VERIFY"; info "Script version : $SCRIPT_VERSION"; info "Version DTG    : $VERSION_DTG"; info "Course root    : $COURSE_ROOT"; info "Repository root: $REPOS_ROOT"; info "Log file       : $LOG_FILE"; notice "Verify is read-only except for this transcript."; [[ "$REQUESTED_PROFILE" == "$DEPLOYMENT_PROFILE_ID" ]] || record FAIL verify.profile "unsupported profile" "Use ubuntu_gnome_bare_metal."; check_platform; if [[ -r "$MANIFEST_PATH" && -r "$SCHEMA_PATH" ]]; then if MANIFEST_RELEASE="$(validate_manifest 2>&1)"; then record PASS verify.manifest "release $MANIFEST_RELEASE"; check_network; check_system; check_user; else record FAIL verify.manifest "$MANIFEST_RELEASE" "Run bootstrap_ubg.sh."; fi; else record FAIL verify.manifest "manifest or schema missing" "Run bootstrap_ubg.sh."; fi; local code=0 result=COMPLIANT; ((FAIL_COUNT>0)) && { code=1; result='NOT COMPLIANT'; }; header "VERIFICATION SUMMARY"; printf 'Result          : %s\nScript version  : %s\nVersion DTG     : %s\nManifest release: %s\nPassed          : %s\nWarnings        : %s\nFailed          : %s\nNot applicable  : %s\nLog file        : %s\nExit code       : %s\n' "$result" "$SCRIPT_VERSION" "$VERSION_DTG" "$MANIFEST_RELEASE" "$PASS_COUNT" "$WARNING_COUNT" "$FAIL_COUNT" "$NA_COUNT" "$LOG_FILE" "$code"; if ((${#REMEDIATIONS[@]})); then printf '\nRemediation:\n'; local r; for r in "${REMEDIATIONS[@]}"; do printf -- '- %s\n' "$r"; done; fi; ((code==0)) || continuity; exit "$code"; }
main "$@"
