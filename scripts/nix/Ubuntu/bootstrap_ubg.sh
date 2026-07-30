platform="ubg"
course_dir="$HOME/it140"
log_dir="$course_dir/logs"
mkdir -p "$log_dir"
log_file="$log_dir/bootstrap_${platform}_$(date +%Y%m%d_%H%M%S).log"
(
    set -Eeuo pipefail
    temp_dir=""
    cleanup() {
        [[ -n "$temp_dir" && -d "$temp_dir" ]] && rm -rf "$temp_dir"
    }
    trap cleanup EXIT
    printf '\n============================================================\n'
    printf 'IT 140 UBUNTU DESKTOP BOOTSTRAP\n'
    printf '============================================================\n'
    printf '[INFO] Purpose  : Retrieve the IT 140 course automation files.\n'
    printf '[INFO] Log file : %s\n' "$log_file"
    [[ -r /etc/os-release ]] || {
        printf '[ERROR] Cannot identify the operating system.\n' >&2
        exit 2
    }
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != 24.04 ]]; then
        printf '[ERROR] This command set supports only Ubuntu Desktop 24.04 LTS.\n' >&2
        printf '[ERROR] Detected: %s\n' "${PRETTY_NAME:-unknown operating system}" >&2
        exit 2
    fi
    if ! command -v git >/dev/null 2>&1; then
        printf '[INFO] Git is not installed. Ubuntu may request your account password.\n'
        sudo apt-get -o Acquire::Retries=5 update
        sudo env DEBIAN_FRONTEND=noninteractive \
            apt-get -o Acquire::Retries=5 install -y git ca-certificates
    fi
    mkdir -p "$course_dir"
    temp_dir="$(mktemp -d)"
    printf '[INFO] Retrieving the main IT 140 course repository...\n'
    git clone --depth 1 \
        "https://github.com/GC-STEM/it140.git" \
        "$temp_dir/it140"
    rm -rf "$temp_dir/it140/.git"
    cp -a "$temp_dir/it140/." "$course_dir/"
    rm -rf "$course_dir/.git"
    scripts_dir="$course_dir/scripts/$platform"
    [[ -d "$scripts_dir" ]] || {
        printf '[ERROR] The repository does not contain the Ubuntu GNOME scripts.\n' >&2
        exit 1
    }
    chmod 0755 "$scripts_dir/"*.sh
    path_line="export PATH=\"\$HOME/it140/scripts/$platform:\$PATH\""
    grep -qxF "$path_line" "$HOME/.bashrc" \
        || printf '\n%s\n' "$path_line" >> "$HOME/.bashrc"
    printf '[SUCCESS] IT 140 course automation files were retrieved.\n'
    printf '[NOTICE] A log containing all output from this command set is available here:\n'
    printf '[NOTICE] %s\n' "$log_file"
    printf '[NOTICE] Type '\''exit'\'' and press Enter to close this Terminal.\n'
    printf '[NOTICE] Open a new Terminal, then run setup_ubg.sh.\n'
) > >(tee -a "$log_file") 2>&1
status=$?
unset platform course_dir log_dir log_file status
