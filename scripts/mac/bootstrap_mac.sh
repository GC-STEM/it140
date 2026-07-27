platform="mac"
course_dir="$HOME/it140"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/it140-bootstrap.XXXXXX")"
archive_file="$temp_dir/it140-main.zip"
/usr/bin/curl --fail --location --show-error \
--retry 5 --retry-delay 5 \
"https://github.com/GC-STEM/it140/archive/refs/heads/main.zip" \
--output "$archive_file"
/usr/bin/ditto -x -k "$archive_file" "$temp_dir"
mkdir -p "$course_dir"
/usr/bin/ditto "$temp_dir/it140-main" "$course_dir"
rm -rf "$course_dir/.git"
rm -rf "$temp_dir"
scripts_dir="$course_dir/scripts/$platform"
chmod 0755 "$scripts_dir/"*_mac.sh
path_line="export PATH=\"\$HOME/it140/scripts/$platform:\$PATH\""
grep -qxF "$path_line" "$HOME/.zshrc" \
|| printf '\n%s\n' "$path_line" >> "$HOME/.zshrc"
case ":$PATH:" in
    *":$scripts_dir:"*) ;;
    *) export PATH="$scripts_dir:$PATH" ;;
esac
hash -r 2>/dev/null || rehash
