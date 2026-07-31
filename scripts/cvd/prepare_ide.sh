platform="cvd"
mkdir -p "$HOME/it140"
temp_dir="$(mktemp -d)"
git clone --depth 1 \
"https://github.com/GC-STEM/it140.git" \
"$temp_dir/it140"
rm -rf "$temp_dir/it140/.git"
cp -a "$temp_dir/it140/." "$HOME/it140/"
rm -rf "$HOME/it140/.git"
rm -rf "$temp_dir"
scripts_dir="$HOME/it140/scripts/$platform"
chmod +x "$scripts_dir/"*.sh
path_line="export PATH=\"\$HOME/it140/scripts/$platform:\$PATH\""
grep -qxF "$path_line" "$HOME/.bashrc" || printf '\n%s\n' "$path_line" >> "$HOME/.bashrc"
case ":$PATH:" in
    *":$scripts_dir:"*) ;;
    *) export PATH="$scripts_dir:$PATH" ;;
esac
hash -r