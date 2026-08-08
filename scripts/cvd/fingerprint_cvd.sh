#!/usr/bin/env bash
# Linux Codio Virtual Desktop (CVD) environment fingerprint
# Captures system, package, desktop, development-tool, and configuration state
# for comparison with a local Ubuntu/Xfce virtual machine.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="0.2.0"
readonly VERSION_DTG="2026-08-07-07-20"
readonly HOST_SHORT="$(hostname -s 2>/dev/null || hostname)"
readonly RUN_DTG="$(date +%Y%m%d_%H%M%S)"
readonly OUTPUT_DIR="$HOME/cvd_fingerprint_${HOST_SHORT}_${RUN_DTG}"
readonly LOG_FILE="$OUTPUT_DIR/fingerprint.log"

mkdir -p "$OUTPUT_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'status=$?; echo "ERROR: $SCRIPT_NAME stopped at line $LINENO (exit $status). Review: $LOG_FILE" >&2; exit "$status"' ERR

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

run_capture() {
    local output_file="$1"
    shift
    {
        printf '$'
        printf ' %q' "$@"
        printf '\n\n'
        "$@"
    } > "$OUTPUT_DIR/$output_file" 2>&1 || true
}

capture_shell_command() {
    local output_file="$1"
    local command_text="$2"
    {
        printf '$ %s\n\n' "$command_text"
        bash -lc "$command_text"
    } > "$OUTPUT_DIR/$output_file" 2>&1 || true
}

copy_if_readable() {
    local source_path="$1"
    local destination_name="$2"
    if [[ -r "$source_path" ]]; then
        cp -a -- "$source_path" "$OUTPUT_DIR/$destination_name"
    fi
}

redact_file() {
    local file_path="$1"
    [[ -f "$file_path" ]] || return 0
    sed -E -i \
        -e 's/(token|password|passwd|secret|authorization|cookie|session)[[:space:]]*[:=][[:space:]]*[^[:space:]]+/\1=<REDACTED>/Ig' \
        -e 's/(gh[pousr]_[A-Za-z0-9_]{20,})/<REDACTED_GITHUB_TOKEN>/g' \
        -e 's/(github_pat_[A-Za-z0-9_]{20,})/<REDACTED_GITHUB_TOKEN>/g' \
        -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/-]+/\1<REDACTED>/Ig' \
        "$file_path" || true
}

section "IT 140 CVD FINGERPRINT"
echo "Script version : $SCRIPT_VERSION"
echo "Version DTG    : $VERSION_DTG"
echo "Host           : $HOST_SHORT"
echo "User           : $(id -un)"
echo "Output         : $OUTPUT_DIR"
echo "Started        : $(date --iso-8601=seconds)"

cat > "$OUTPUT_DIR/README.txt" <<EOF_README
IT 140 CVD Environment Fingerprint

Created by : $SCRIPT_NAME
Version    : $SCRIPT_VERSION
Version DTG: $VERSION_DTG
Host       : $HOST_SHORT
Created    : $(date --iso-8601=seconds)

Purpose:
Capture the observable system state of the IT 140 Codio Virtual Desktop for
comparison with a local Ubuntu/Xfce virtual machine.

Security note:
The script avoids copying private keys, browser profiles, GitHub CLI credentials,
and other known credential stores. It also applies basic redaction to selected
text outputs. Review all files before sharing the fingerprint folder outside the project.
EOF_README

section "Capturing identity and operating system"
run_capture identity.txt id
run_capture hostnamectl.txt hostnamectl
run_capture os_release.txt cat /etc/os-release
run_capture uname.txt uname -a
run_capture lsb_release.txt lsb_release -a
run_capture locale.txt locale
run_capture timedatectl.txt timedatectl
run_capture uptime.txt uptime
run_capture kernel_cmdline.txt cat /proc/cmdline

section "Capturing virtualization and hardware"
run_capture systemd_detect_virt.txt systemd-detect-virt
run_capture cpu.txt lscpu
run_capture memory.txt free -h
run_capture block_devices.txt lsblk -e 7 -o NAME,TYPE,SIZE,FSTYPE,FSVER,MOUNTPOINTS,MODEL
run_capture filesystems.txt df -hT
run_capture pci.txt lspci -nn
run_capture usb.txt lsusb

section "Capturing Debian and APT state"
capture_shell_command dpkg_packages.tsv "dpkg-query -W -f='\${Package}\t\${Version}\t\${Architecture}\\n' | sort"
capture_shell_command apt_manual.txt "apt-mark showmanual | sort"
capture_shell_command apt_holds.txt "apt-mark showhold | sort"
run_capture apt_policy.txt apt-cache policy
capture_shell_command apt_sources.txt "grep -RhsE '^[[:space:]]*(deb|Types:|URIs:|Suites:|Components:|Signed-By:)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | sed 's/[[:space:]]\+$//'"
run_capture dpkg_architecture.txt dpkg --print-architecture
run_capture foreign_architectures.txt dpkg --print-foreign-architectures

section "Capturing desktop and display environment"
capture_shell_command desktop_environment.txt "printf 'XDG_CURRENT_DESKTOP=%s\\nDESKTOP_SESSION=%s\\nXDG_SESSION_DESKTOP=%s\\nXDG_SESSION_TYPE=%s\\nDISPLAY=%s\\nWAYLAND_DISPLAY=%s\\n' \"\${XDG_CURRENT_DESKTOP-}\" \"\${DESKTOP_SESSION-}\" \"\${XDG_SESSION_DESKTOP-}\" \"\${XDG_SESSION_TYPE-}\" \"\${DISPLAY-}\" \"\${WAYLAND_DISPLAY-}\""
run_capture xfce_session_version.txt xfce4-session --version
run_capture xfce_panel_version.txt xfce4-panel --version
run_capture xfconf_version.txt xfconf-query --version
capture_shell_command xfconf_channels.txt "xfconf-query -l 2>/dev/null | sort"
capture_shell_command xfce4_config_files.txt "find \"$HOME/.config/xfce4\" -type f -printf '%P\\n' 2>/dev/null | sort"

if [[ -d "$HOME/.config/xfce4" ]]; then
    cp -a -- "$HOME/.config/xfce4" "$OUTPUT_DIR/xfce4_config"
fi
if [[ -d "$HOME/.config/autostart" ]]; then
    cp -a -- "$HOME/.config/autostart" "$OUTPUT_DIR/autostart_config"
fi
if [[ -d "$HOME/Desktop" ]]; then
    find "$HOME/Desktop" -maxdepth 2 -printf '%M\t%u\t%g\t%p -> %l\n' \
        > "$OUTPUT_DIR/desktop_entries.txt" 2>&1 || true
fi

section "Capturing development tools"
for tool in bash git gh python3 pip3 pytest ruff code; do
    if command -v "$tool" >/dev/null 2>&1; then
        command -v "$tool" >> "$OUTPUT_DIR/tool_paths.txt"
    else
        printf '%s\tNOT FOUND\n' "$tool" >> "$OUTPUT_DIR/tool_paths.txt"
    fi
done

run_capture bash_version.txt bash --version
run_capture git_version.txt git --version
run_capture gh_version.txt gh --version
run_capture python_version.txt python3 --version
run_capture pip_version.txt python3 -m pip --version
run_capture pip_list.txt python3 -m pip list
run_capture pip_freeze.txt python3 -m pip freeze
run_capture pip_debug.txt python3 -m pip debug
run_capture pytest_version.txt python3 -m pytest --version
run_capture ruff_version.txt ruff --version
run_capture vscode_version.txt code --version
run_capture vscode_extensions.txt code --list-extensions --show-versions

section "Capturing Git and shell configuration"
capture_shell_command git_config_global.txt "git config --global --list --show-origin 2>/dev/null"
capture_shell_command git_config_system.txt "git config --system --list --show-origin 2>/dev/null"
capture_shell_command shell_environment.txt "env | sort"
capture_shell_command shell_options.txt "set -o"
capture_shell_command aliases.txt "alias -p"
capture_shell_command path_entries.txt "tr ':' '\\n' <<< \"\$PATH\" | nl -ba"
copy_if_readable "$HOME/.bashrc" bashrc.txt
copy_if_readable "$HOME/.profile" profile.txt
copy_if_readable "$HOME/.gitconfig" gitconfig.txt

section "Capturing services and startup state"
run_capture enabled_services.txt systemctl list-unit-files --type=service --no-pager
run_capture active_services.txt systemctl list-units --type=service --state=running --no-pager
run_capture failed_units.txt systemctl --failed --no-pager
capture_shell_command user_crontab.txt "crontab -l 2>/dev/null"

section "Capturing fonts"
capture_shell_command fonts.txt "fc-list | sort"
run_capture font_match_emoji.txt fc-match emoji
capture_shell_command noto_emoji_font_files.txt "fc-list | grep -i 'Noto Color Emoji' | sort"
run_capture fontconfig_version.txt fc-cache --version

section "Capturing networking without credentials"
run_capture ip_addresses.txt ip -brief address
run_capture ip_routes.txt ip route
run_capture resolvectl.txt resolvectl status
run_capture hosts.txt cat /etc/hosts

section "Capturing IT 140 deployment state"
if [[ -d "$HOME/it140" ]]; then
    capture_shell_command it140_tree.txt "find \"$HOME/it140\" -maxdepth 4 -printf '%M\\t%u\\t%g\\t%s\\t%TY-%Tm-%TdT%TH:%TM:%TS\\t%P -> %l\\n' | sort"
    capture_shell_command it140_script_hashes.txt "find \"$HOME/it140/scripts\" -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum"
    capture_shell_command it140_version_markers.txt "grep -RhsE 'SCRIPT_VERSION|VERSION_DTG|MANIFEST_VERSION|release_version|version_dtg' \"$HOME/it140/scripts\" 2>/dev/null | sort -u"
else
    printf '%s\n' "$HOME/it140 was not found." > "$OUTPUT_DIR/it140_tree.txt"
fi

section "Capturing selected configuration metadata"
if [[ -d "$HOME/.config/Code/User" ]]; then
    find "$HOME/.config/Code/User" -maxdepth 1 -type f \
        -printf '%f\t%s bytes\t%TY-%Tm-%TdT%TH:%TM:%TS\n' \
        > "$OUTPUT_DIR/vscode_user_config_files.txt" 2>&1 || true
    copy_if_readable "$HOME/.config/Code/User/settings.json" vscode_settings.json
    copy_if_readable "$HOME/.config/Code/User/keybindings.json" vscode_keybindings.json
fi

# Redact selected copied and generated text files before hashing.
while IFS= read -r -d '' file_path; do
    redact_file "$file_path"
done < <(find "$OUTPUT_DIR" -maxdepth 1 -type f \
    \( -name '*.txt' -o -name '*.json' -o -name '*.tsv' -o -name '*.log' \) \
    -print0)

section "Generating checksums"
find "$OUTPUT_DIR" -type f ! -name SHA256SUMS -printf '%P\0' \
    | sort -z \
    | while IFS= read -r -d '' relative_path; do
        sha256sum "$OUTPUT_DIR/$relative_path"
      done \
    > "$OUTPUT_DIR/SHA256SUMS"

section "FINGERPRINT COMPLETE"
echo "Result directory: $OUTPUT_DIR"
echo "Completed       : $(date --iso-8601=seconds)"
echo
echo "Review the fingerprint folder before sharing it outside the IT 140 project."
