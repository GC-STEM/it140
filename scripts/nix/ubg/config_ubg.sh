#!/usr/bin/env bash
# IT 140 Ubuntu user configuration script.
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.3.0"
readonly COURSE_ROOT="${HOME}/it140"
readonly LOG_DIR="${COURSE_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/config_ubg_$(date +%Y%m%d_%H%M%S).log"
readonly VENV_DIR="${HOME}/.local/share/it140/venv"
WARNINGS=0; START=$(date +%s)
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
info(){ printf '[INFO] %s\n' "$*"; }; success(){ printf '[SUCCESS] %s\n' "$*"; }; warn(){ printf '[WARNING] %s\n' "$*"; WARNINGS=$((WARNINGS+1)); }; fail(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'printf "[ERROR] Configuration stopped near line %s. Review %s\n" "${BASH_LINENO[0]:-unknown}" "$LOG_FILE" >&2' ERR
printf '\n============================================================\nIT 140 UBUNTU GNOME CONFIGURATION\n============================================================\n'
info "Script version   : $SCRIPT_VERSION"; info "Current user     : $USER"; info "Log file         : $LOG_FILE"
[[ $EUID -ne 0 ]] || fail "Run as the standard desktop user, not with sudo."
for cmd in git gh code python3.12; do command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is missing. Run setup_ubg.sh first."; done
[[ -x "$VENV_DIR/bin/python" ]] || fail "The IT 140 Python environment is missing. Run setup_ubg.sh first."

git config --global init.defaultBranch main
git config --global core.autocrlf input
git config --global push.autoSetupRemote true
git config --global core.editor 'code --wait'

if ! gh auth status -h github.com >/dev/null 2>&1; then
  printf '\n[NOTICE] Sign in to GitHub in your browser. The one-time code will be copied to the clipboard.\n'
  gh auth login -h github.com -p https -w --clipboard
fi
account=$(gh api user --jq .login)
account_id=$(gh api user --jq .id)
current_name=$(git config --global user.name || true)
if [[ -z $current_name ]]; then
  read -r -p "Enter the name to use for Git commits: " current_name
  git config --global user.name "$current_name"
fi
git config --global user.email "${account_id}+${account}@users.noreply.github.com"

extensions=(ms-python.python charliermarsh.ruff hediet.vscode-drawio i2p-hub.i2p-pseudo streetsidesoftware.code-spell-checker cweijan.vscode-office)
for ext in "${extensions[@]}"; do code --install-extension "$ext" --force >/dev/null; done

settings_dir="$HOME/.config/Code/User"; settings="$settings_dir/settings.json"; mkdir -p "$settings_dir"
python3 - "$settings" "$VENV_DIR/bin/python" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); interpreter=sys.argv[2]
try: data=json.loads(p.read_text()) if p.exists() else {}
except Exception: data={}
data.update({"files.eol":"\n","editor.formatOnSave":True,"python.testing.pytestEnabled":True,"python.testing.unittestEnabled":False,"python.defaultInterpreterPath":interpreter})
data.setdefault("[python]",{})["editor.defaultFormatter"]="charliermarsh.ruff"
data.setdefault("files.associations",{})["*.pseudo"]="pseudo"
t=p.with_suffix('.tmp'); t.write_text(json.dumps(data,indent=4)+"\n"); t.replace(p)
PY

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/it140-vscode.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=IT 140 Course IDE
Comment=Open the IT 140 course workspace in Visual Studio Code
Exec=code ${COURSE_ROOT}
Icon=com.visualstudio.code
Terminal=false
Categories=Development;Education;
DESKTOP
chmod 0644 "$HOME/.local/share/applications/it140-vscode.desktop"

printf '\n============================================================\nCONFIGURATION SUMMARY\n============================================================\n'
printf '[INFO] Result           : PASS\n[INFO] GitHub account   : %s\n[INFO] Warnings         : %s\n[INFO] Elapsed seconds  : %s\n' "$account" "$WARNINGS" "$(( $(date +%s)-START ))"
success "The current user's IT 140 environment is configured."
printf '[NOTICE] Open a new Terminal, then run verify_ubg.sh.\n[NOTICE] Log: %s\n' "$LOG_FILE"
