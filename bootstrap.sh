#!/usr/bin/env bash
# bootstrap.sh — one-line bootstrap for the custom nvim/vim config.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/helloluxi/vimrc/main/bootstrap.sh | bash
#
# What it does:
#   1. Clones helloluxi/vimrc to ~/vimrc (skipped if already a git repo there;
#      fast-forward pulls if it is).
#   2. Runs ~/vimrc/run.sh, which:
#        - symlinks ~/.config/nvim/init.lua  → ~/vimrc/init.lua
#        - generates ~/.config/nvim/lua/keybinds.lua (from keybinds.conf + vocab-nvim.conf)
#        - generates ~/.vimrc                       (from keybinds.conf + vocab-vim.conf)
#
# Both configs are installed unconditionally — no PATH check. That way the
# vim fallback is in place even on boxes where you'll later install nvim.
#
# Override:
#   VIMRC_INIT_REPO=<git-url>   default https://github.com/helloluxi/vimrc
#   VIMRC_INIT_DIR=<path>       default $HOME/vimrc

set -euo pipefail

REPO_URL="${VIMRC_INIT_REPO:-https://github.com/helloluxi/vimrc}"
REPO_DIR="${VIMRC_INIT_DIR:-$HOME/vimrc}"

log() { echo ":: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required"

if [[ -d "$REPO_DIR/.git" ]]; then
  log "Repo present at $REPO_DIR — pulling latest"
  git -C "$REPO_DIR" pull --ff-only || log "  (pull failed; using existing checkout)"
elif [[ -e "$REPO_DIR" ]]; then
  die "$REPO_DIR exists but is not a git repo; refusing to overwrite"
else
  log "Cloning $REPO_URL → $REPO_DIR"
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi

bash "$REPO_DIR/run.sh"

log "Done."
log "  nvim config: ~/.config/nvim/   (first \`nvim\` launch installs lazy.nvim + plugins)"
log "  vim  config: ~/.vimrc           (pure, no plugins — runs anywhere)"
