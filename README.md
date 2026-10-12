# vimrc

Shared configs for every machine: Neovim with a blank-slate, prefix-free keybind system, a generated `.vimrc` fallback for plain-vim boxes, tmux, ripgrep, global Git ignore rules, and AeroSpace on macOS.

## One-line setup on a fresh machine

```bash
curl -fsSL https://raw.githubusercontent.com/helloluxi/vimrc/main/bootstrap.sh | bash
```

`bootstrap.sh` clones this repo to `~/vimrc` (or pulls if it's already there), then runs `run.sh`. Both `~/.config/nvim/` and `~/.vimrc` are installed regardless of whether `nvim`/`vim` are currently on PATH — the vim fallback is in place the moment vim is. It also installs the shared tmux, ripgrep, and Git configs, plus AeroSpace on macOS.

For the shared `~/v` checkout, run `bash ~/v/run.sh`. To install only the miscellaneous configs, run `bash ~/v/misc/run.sh`. The latter refuses to replace existing non-symlink files.

The shared configs link to `~/.tmux.conf`, `~/.ripgreprc`, and `~/.config/git/ignore`, plus `~/.config/aerospace/aerospace.toml` on macOS. The Git path honors `XDG_CONFIG_HOME` when set. Set `export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"` in each machine's shell config so ripgrep loads its defaults. Git reads its global ignore file by default unless `core.excludesFile` selects a different location.

## Files

| File | Purpose |
|------|---------|
| `bootstrap.sh` | Curl-friendly bootstrap: clone + `run.sh`. |
| `init.lua` | Neovim entry — options, lazy.nvim plugins, LSP, cmp, telescope commands. |
| `keybinds.conf` | **Single source of truth.** Per-mode `abstract-name = key-sequence`. |
| `vocab-nvim.conf` | Neovim vocab: `abstract-name = nvim-rhs`. |
| `vocab-vim.conf` | Plain-vim vocab: strict subset of `vocab-nvim.conf`. Entries it omits are skipped during vimrc generation (LSP, Telescope, plugin commands). |
| `run.sh` | Generator. Validates `keybinds.conf` (duplicates, prefix-free), then emits **both** `~/.config/nvim/lua/keybinds.lua` and `~/.vimrc` from the same `keybinds.conf`. Symlinks `init.lua`. |
| `misc/tmux.conf` | Shared tmux colors, clipboard, navigation, and keybindings. |
| `misc/ripgreprc` | Shared ripgrep defaults and directory exclusions. |
| `misc/gitignore` | Global Git ignore rules. |
| `misc/aerospace.toml` | Shared macOS window-manager preferences; installed only on macOS. |
| `misc/run.sh` | Links the miscellaneous configs; also called by `run.sh`. |

`init.lua` is symlinked into `~/.config/nvim/` by `run.sh`. Never edit the generated `keybinds.lua` or `~/.vimrc` directly.

## Workflow

Edit `keybinds.conf`, `vocab-nvim.conf`, or `vocab-vim.conf`, then:

```bash
bash ~/vimrc/run.sh
```

Validation errors (duplicates, prefix conflicts) abort before any file is written.

## Philosophy

**Blank slate** — all letter/punctuation keys are nop'd on startup in n/v/o modes. Every binding is explicit. Digits stay live so count prefixes (`5j`) still work.

**Prefix-free** — no key sequence is a prefix of another. The editor executes immediately on every keypress; zero timeout ambiguity. Operators (`d`, `c`, `y`) are declared `<operator>` in vocab and don't conflict with terminals.

**Minimal modifiers** — prefer pure lowercase sequences over Ctrl/Alt combos.

**Single source of truth** — `keybinds.conf` defines what each key does abstractly. Two vocab files translate the same abstract bindings into the right RHS for nvim vs. plain vim. To add a new binding portable across both, add it to `keybinds.conf` and to both vocabs. To make a binding nvim-only, just omit it from `vocab-vim.conf`.

## Key clusters

| Prefix | Domain |
|--------|--------|
| *(none)* | Single-key actions: navigation (`i/k/j/l`), insert (`n/m`), undo (`z/Z`), visual (`v/V`) |
| `o` | Line ops: `oj`=line-start, `ol`=line-end, `ok`=open-below, `oi`=open-above |
| `e` | Extremes: `ei`=file-top, `ek`=file-bottom |
| `f` | Fuzzy find (Telescope): `ff`=files, `fg`=grep, `fs`=symbols, `fd`=diagnostics … *(nvim only)* |
| `d/c/y` | Delete / Change / Yank — operator + motion/text-object |
| `g` | LSP: `gh`=hover, `gd`=definition, `gr`=references, `gn`=rename … *(nvim only)* |
| `w` | Windows: `wi/k/j/l`=focus, `wv/wh`=split, `wc`=close, `wt`=terminal |

**Navigation geometry (IJKL)**
```
i = up     k = down    j = left    l = right
I = para-prev           K = para-next
J = word-left           L = word-right
[ = page-up             ] = page-down
```

## Vim fallback — what's lost

The generated `~/.vimrc` is pure (no plugins, vim 8.1+). It keeps the geometry, operators, text-objects, windows, buffers, folds, quickfix, macros, terminal, and all option/autocmd settings. It **drops**: LSP (`g`-prefix), Telescope fuzzy find (`f`-prefix), file explorer (`a`), comment toggle (`,`), and the toggleterm manager. Those LHSes simply stay nop'd by the blank-slate preamble.

## Terminal

In nvim, `wt` toggles a vertical right-panel terminal (40 % width); `<C-\>` is a secondary toggle from toggleterm's default. In plain vim, `.` opens a native `:terminal` (no manager, no toggle).
