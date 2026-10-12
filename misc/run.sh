#!/usr/bin/env bash
# Install shared miscellaneous configs, with AeroSpace only on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

sources=(tmux.conf ripgreprc gitignore)
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
targets=("$HOME/.tmux.conf" "$HOME/.ripgreprc" "$config_home/git/ignore")

if [ "$(uname -s)" = Darwin ]; then
  sources+=(aerospace.toml)
  targets+=("$HOME/.config/aerospace/aerospace.toml")
fi

# Check every target before updating any links.
for i in "${!sources[@]}"; do
  src="$ROOT/${sources[$i]}"
  dst="${targets[$i]}"
  if [ ! -f "$src" ]; then
    echo "shared config not found: $src" >&2
    exit 1
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "refusing to replace non-symlink $dst" >&2
    exit 1
  fi
done

for i in "${!sources[@]}"; do
  dst="${targets[$i]}"
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$ROOT/${sources[$i]}" "$dst"
done
echo "shared configs installed from $ROOT"
