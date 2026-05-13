#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_CONF="${SCRIPT_DIR}/keybinds.conf"
VOCAB_CONF="${SCRIPT_DIR}/vocab-nvim.conf"
OUT="$HOME/.config/nvim/lua/keybinds.lua"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo ":: $*" >&2; }
normalize_ctrl_notation() {
  # Allow ^x syntax in keybinds.conf and normalize to Neovim's <C-x>.
  sed -E 's/\^([[:alnum:]])/<C-\1>/g' <<< "$1"
}
lua_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
declare -A vocab
declare -a section_order=()
declare -A section_keys_raw  # "n,v" -> "lhs=rhs_abstract#desc\n..."
declare -A bindings          # "mode:lhs" -> rhs_abstract
declare -A descs             # "mode:lhs" -> desc
errors=0

# ---------------------------------------------------------------------------
# Parse
# ---------------------------------------------------------------------------
[[ -f "$KEYS_CONF" ]] || die "Key config not found: $KEYS_CONF"
[[ -f "$VOCAB_CONF" ]] || die "Vocab config not found: $VOCAB_CONF"

# Parse vocab-nvim.conf: abstract = rhs
vocab_line_num=0
while IFS= read -r line || [[ -n "$line" ]]; do
  ((vocab_line_num++)) || true

  line="${line%"${line##*[^[:space:]]}"}"
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^\[ ]] && die "$VOCAB_CONF:$vocab_line_num: sections are not allowed"

  if [[ "$line" =~ ^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*([^#]+)(#[[:space:]]*(.*))?$ ]]; then
    key="${BASH_REMATCH[1]}"
    val_raw="${BASH_REMATCH[2]}"
    val_raw="${val_raw%"${val_raw##*[^[:space:]]}"}"
    val="$(normalize_ctrl_notation "$val_raw")"
    vocab["$key"]="$val"
    continue
  fi

  die "$VOCAB_CONF:$vocab_line_num: unrecognized: $line"
done < "$VOCAB_CONF"

line_num=0
current_section=""

while IFS= read -r line || [[ -n "$line" ]]; do
  ((line_num++)) || true

  # trim trailing whitespace
  line="${line%"${line##*[^[:space:]]}"}"

  # skip blank and comment lines
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

  # section header: [nv] or [n] or [v]
  if [[ "$line" =~ ^\[([nv]+)\]$ ]]; then
    current_section="${BASH_REMATCH[1]}"
    # Expand shorthand to full mode list
    case "$current_section" in
      nv) modes_str="n,v" ;;
      n)  modes_str="n" ;;
      v)  modes_str="v" ;;
      *)  die "$KEYS_CONF:$line_num: unknown section [$current_section]" ;;
    esac
    # record section order on first encounter
    found=false
    for s in "${section_order[@]}"; do
      [[ "$s" == "$modes_str" ]] && found=true && break
    done
    $found || section_order+=("$modes_str")
    continue
  fi

  # key = [# description] means disabled (ignored): default is already <Nop>
  if [[ "$line" =~ ^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*([[:space:]]*#[[:space:]]*(.*))?$ ]]; then
    continue
  fi

  # key = value [# description]
  if [[ "$line" =~ ^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*([^#[:space:]]+)([[:space:]]*#[[:space:]]*(.*))?$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="$(normalize_ctrl_notation "${BASH_REMATCH[2]}")"
    desc="${BASH_REMATCH[4]:-}"

    case "$current_section" in
      *)
        IFS=',' read -ra mode_list <<< "$modes_str"
        for m in "${mode_list[@]}"; do
          # In modes sections: key is the abstract name, val is the lhs (key binding)
          abstract="$key"
          lhs="$val"
          # duplicate check
          if [[ -n "${bindings["${m}:${lhs}"]+_}" ]]; then
            echo "ERROR: duplicate key binding '$lhs' in mode '$m'" >&2
            ((errors++))
          fi
          bindings["${m}:${lhs}"]="$abstract"
          descs["${m}:${lhs}"]="$desc"
        done
        # append to section's ordered key list
        section_keys_raw["$modes_str"]+="${lhs}=${abstract}#${desc}"$'\n'
        ;;
    esac
    continue
  fi

  die "$KEYS_CONF:$line_num: unrecognized: $line"
done < "$KEYS_CONF"

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

# 1. Vocab references
for entry in "${!bindings[@]}"; do
  val="${bindings[$entry]}"
  [[ "$val" == "<operator>" || "$val" == "<nop>" ]] && continue
  if [[ -z "${vocab[$val]+_}" ]]; then
    echo "ERROR: unknown command '$val' for binding '$entry'" >&2
    ((errors++))
  fi
done

# 2. Prefix-free per mode
for mode in $(printf '%s\n' "${!bindings[@]}" | cut -d: -f1 | sort -u); do
  declare -a terminals=() prefixes=()

  for entry in "${!bindings[@]}"; do
    [[ "$entry" == "${mode}:"* ]] || continue
    lhs="${entry#${mode}:}"
    rhs="${bindings[$entry]}"
    # Check if the abstract value resolves to <operator> in vocab
    resolved_rhs="${vocab[$rhs]:-$rhs}"
    if [[ "$rhs" == "<operator>" || "$resolved_rhs" == "<operator>" ]]; then
      prefixes+=("$lhs")
    else
      terminals+=("$lhs")
    fi
  done

  # No terminal is a strict prefix of any other key in the same mode
  for t in "${terminals[@]}"; do
    for other in "${terminals[@]}" "${prefixes[@]}"; do
      [[ "$t" == "$other" ]] && continue
      if [[ "$other" == "${t}"* ]]; then
        echo "ERROR [mode $mode]: terminal '$t' is a prefix of '$other'" >&2
        ((errors++))
      fi
    done
  done

  # No operator (prefix) should be a prefix of any terminal
  for p in "${prefixes[@]}"; do
    for t in "${terminals[@]}"; do
      if [[ "$t" == "${p}"* ]]; then
        echo "ERROR [mode $mode]: operator '$p' is a prefix of terminal '$t'" >&2
        ((errors++))
      fi
    done
  done

  # No key is both terminal and operator in the same mode
  for t in "${terminals[@]}"; do
    for p in "${prefixes[@]}"; do
      if [[ "$t" == "$p" ]]; then
        echo "ERROR [mode $mode]: '$t' is both terminal and operator" >&2
        ((errors++))
      fi
    done
  done

  unset terminals prefixes
done

if (( errors > 0 )); then
  echo "Validation failed ($errors error(s))" >&2
  exit 1
fi

log "Validation passed"

# ---------------------------------------------------------------------------
# Generate keybinds.lua
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$OUT")"
ln -sf "$SCRIPT_DIR/init.lua" "$HOME/.config/nvim/init.lua"

{
  # 1. Generated-by header
  printf '%s\n' "-- Generated by run.sh from keybinds.conf + vocab-nvim.conf on $(date -Iseconds)"
  printf '%s\n\n' '-- DO NOT EDIT -- changes will be overwritten. Edit keybinds.conf / vocab-nvim.conf and re-run.'

  # 2. Philosophy block
  cat <<'PHILOSOPHY'
-- =============================================================================
-- PHILOSOPHY
--
-- Background: coming from VSCode, new to Neovim. Loves modal editing
-- (normal / visual / insert) but wants to redesign ALL keybinds from scratch.
--
-- BLANK SLATE
--   All letter and punctuation keys are nop'd at startup in n/v/o modes.
--   Every binding below is explicit and intentional. Nothing is inherited
--   from vim's defaults by accident.
--
-- PREFIX-FREE DESIGN
--   Inspired by prefix-free (Huffman) codes: no key sequence is a prefix of
--   another. If "d" is a prefix (delete operator), then "d" alone does nothing
--   and no standalone command starts with "d". If "i" is a terminal (move up),
--   then no command starts with "i".
--   Consequence: zero timeout ambiguity — vim executes immediately on every
--   keypress. No waiting, no misfires.
--   Enforced externally: keybinds are defined in keybinds.conf and this file
--   is generated by run.sh which validates prefix-free constraints.
--
-- TWO NAMING PRINCIPLES
--   1. Location-first  — navigation keys cluster spatially around IJKL.
--                        Shape of the hand / keyboard geometry drives layout.
--   2. Function-first  — all non-navigation keys are named by what they do:
--                        d=delete, f=find, u=undo, v=visual, etc.
-- MINIMAL MODIFIER KEY:
--   Use ctrl, shift, alt as minimal as possible, user prefers pure-small-letter command palette style
--
-- NAVIGATION GEOMETRY (IJKL cluster)
--   i=up  k=down  j=left  l=right       (home row + above)
--   I=file-top  K=file-bottom            (Shift = extreme)
--   J=line-start  L=line-end            (Shift = extreme horizontal)
--   Ctrl+J=word-left  Ctrl+L=word-right  (Ctrl = word jump)
--   Ctrl+U=page-up  Ctrl+O=page-down    (Ctrl = page)
--
-- INSERT MODE ENTRY
--   h=insert  H=insert-at-line-start    (h is left of j=left, feels natural)
--   a=append  A=append-at-line-end
--   o=open-below  O=open-above
--
-- TEXT OBJECTS
--   n = inner prefix  (replaces vim's "i" — e.g. dnw = delete inner word)
--   a = around prefix (same as vim's "a" — e.g. da( = delete around parens)
--   Both use noremap=false so vim resolves the text object natively.
--
-- PLUGIN ECOSYSTEM (minimal, justified)
--   lazy.nvim       — plugin manager
--   mason + lspconfig — LSP for C++/CUDA/Python/JS/TS/C#/HTML/CSS/LaTeX
--   telescope       — fuzzy find files and symbols
--   vimtex          — LaTeX compile + PDF sync (irreplaceable)
--   molten.nvim     — Jupyter notebook cells inline
--   toggleterm      — floating terminal for Claude Code CLI
--   nvim-dap        — debugger (future use)
--
-- LEADER
--   Hard-coded to Space (VSCode-like, thumb key)
-- =============================================================================
PHILOSOPHY

  # 3. Leader settings (hard-coded)
  printf '\nvim.g.mapleader = "<Space>"\n'
  printf 'vim.g.maplocalleader = "<Space>"\n\n'

  # 4. map() helper
  cat <<'MAPHELPER'
local map = function(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
end
MAPHELPER

  # 5. nop_defaults()
  cat <<'NOP'

-- =============================================================================
-- BLANK SLATE: nop all letter + punctuation + digit keys in n/v/o modes.
-- Explicit map() calls below override these Nops.
-- =============================================================================
local function nop_defaults()
  local modes = { "n", "v", "o" }
  local letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  for i = 1, #letters do
    vim.keymap.set(modes, letters:sub(i, i), "<Nop>", { noremap = true, silent = true })
  end
  for _, k in ipairs({ "~", "!", "@", "#", "$", "%", "^", "&", "*",
                       "-", "+", "=", "[", "]", "{", "}", "|", "\\",
                       ";", "'", '"', ",", ".", "/", "<", ">", "?", "`" }) do
    vim.keymap.set(modes, k, "<Nop>", { noremap = true, silent = true })
  end
end
nop_defaults()
NOP

  # 6. Keybindings by section
  for modes_str in "${section_order[@]}"; do
    printf '\n-- =============================================================================
-- [modes: %s]
-- =============================================================================\n\n' "$modes_str"

    # format mode list for Lua
    IFS=',' read -ra mode_arr <<< "$modes_str"
    if [[ ${#mode_arr[@]} -eq 1 ]]; then
      lua_mode="\"${mode_arr[0]}\""
    else
      lua_mode="{ "
      first=true
      for m in "${mode_arr[@]}"; do
        $first || lua_mode+=", "
        lua_mode+="\"$m\""
        first=false
      done
      lua_mode+=" }"
    fi

    # iterate keys in this section (preserving order)
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      lhs="${entry%%=*}"
      rest="${entry#*=}"
      rhs_abstract="${rest%%#*}"
      desc="${rest#*#}"
      # trim whitespace from desc
      desc="${desc#"${desc%%[![:space:]]*}"}"

      if [[ "$rhs_abstract" == "<operator>" ]]; then
        echo "-- ${lhs} = <operator> (prefix, nop'ed)"
        continue
      fi

      if [[ "$rhs_abstract" == "<nop>" ]]; then
        lhs_lua="$(lua_escape "$lhs")"
        desc_lua="$(lua_escape "$desc")"
        printf 'vim.keymap.set(%s, "%s", "<Nop>", { noremap = true, silent = true, desc = "%s" })\n' \
          "$lua_mode" "$lhs_lua" "$desc_lua"
        continue
      fi

      # resolve via vocab
      resolved="${vocab[$rhs_abstract]:-}"
      
      # Check if resolved value is <operator> or <nop>
      if [[ "$resolved" == "<operator>" ]]; then
        echo "-- ${lhs} = <operator> (prefix, nop'ed)"
        continue
      fi
      
      if [[ "$resolved" == "<nop>" ]]; then
        lhs_lua="$(lua_escape "$lhs")"
        desc_lua="$(lua_escape "$desc")"
        printf 'vim.keymap.set(%s, "%s", "<Nop>", { noremap = true, silent = true, desc = "%s" })\n' \
          "$lua_mode" "$lhs_lua" "$desc_lua"
        continue
      fi

      lhs_lua="$(lua_escape "$lhs")"
      resolved_lua="$(lua_escape "$resolved")"
      desc_lua="$(lua_escape "$desc")"
      printf 'map(%s, "%s", "%s", "%s")\n' "$lua_mode" "$lhs_lua" "$resolved_lua" "$desc_lua"
    done <<< "${section_keys_raw[$modes_str]:-}"
  done

} > "$OUT"

log "Generated $OUT"

# ===========================================================================
# PART 2: Generate ~/.vimrc from keybinds.conf + vocab-vim.conf
# ---------------------------------------------------------------------------
# Same keybinds.conf (single source of truth). vocab-vim.conf is a strict
# subset of vocab-nvim.conf — entries it omits are skipped here, leaving their
# LHS nop'd by the blank-slate preamble in the generated vimrc.
# ===========================================================================
VIM_CONF="${SCRIPT_DIR}/vocab-vim.conf"
VIMRC_OUT="$HOME/.vimrc"

if [[ ! -f "$VIM_CONF" ]]; then
  log "No vocab-vim.conf — skipping vimrc generation"
  exit 0
fi

declare -A vocab_vim
vim_line_num=0
while IFS= read -r line || [[ -n "$line" ]]; do
  ((vim_line_num++)) || true
  line="${line%"${line##*[^[:space:]]}"}"
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  if [[ "$line" =~ ^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*([^#]+)(#[[:space:]]*(.*))?$ ]]; then
    key="${BASH_REMATCH[1]}"
    val_raw="${BASH_REMATCH[2]}"
    val_raw="${val_raw%"${val_raw##*[^[:space:]]}"}"
    val="$(normalize_ctrl_notation "$val_raw")"
    vocab_vim["$key"]="$val"
    continue
  fi
  die "$VIM_CONF:$vim_line_num: unrecognized: $line"
done < "$VIM_CONF"

# Back up an existing ~/.vimrc that's not one of ours
if [[ -f "$VIMRC_OUT" && ! -L "$VIMRC_OUT" ]] \
   && ! grep -q "Generated by ~/vimrc/run.sh" "$VIMRC_OUT" 2>/dev/null; then
  backup="${VIMRC_OUT}.bak.$(date +%s)"
  cp "$VIMRC_OUT" "$backup"
  log "Backed up existing $VIMRC_OUT → $backup"
fi

{
  printf '" Generated by ~/vimrc/run.sh from keybinds.conf + vocab-vim.conf on %s\n' \
    "$(date -Iseconds)"
  printf '" DO NOT EDIT — edit those files and re-run.\n\n'

  cat <<'VIMRC_HEAD'
set nocompatible
set encoding=utf-8

" --- display
set number
set relativenumber
set cursorline
set signcolumn=yes

" --- indent
set tabstop=2
set shiftwidth=2
set expandtab
set smartindent

" --- scroll / wrap
set nowrap
set scrolloff=8
set sidescrolloff=8

" --- search
set ignorecase
set smartcase
set nohlsearch
set incsearch

" --- splits
set splitbelow
set splitright

" --- buffers / state
set clipboard^=unnamedplus
set autoread
set noswapfile
set updatetime=400
if has('persistent_undo')
  if !isdirectory($HOME . '/.vim/undo')
    silent! call mkdir($HOME . '/.vim/undo', 'p', 0700)
  endif
  set undodir=~/.vim/undo//
  set undofile
endif

" --- prefix-free: zero timeout (keybinds.conf is a prefix-free code)
set notimeout
set nottimeout

" --- auto-save on InsertLeave / TextChanged
augroup VimrcAutosave
  autocmd!
  autocmd InsertLeave,TextChanged * silent! if &modifiable && &buftype ==# '' && expand('%') !=# '' | update | endif
augroup END

" --- auto-reload external changes
augroup VimrcAutoreload
  autocmd!
  autocmd FocusGained,BufEnter,CursorHold * silent! checktime
augroup END

" --- leader (matches nvim config)
let mapleader = ' '
let maplocalleader = ' '

" --- macro toggle helper (Q starts/stops recording to register q)
function! ToggleMacroQ() abort
  if exists('*reg_recording') && reg_recording() !=# ''
    normal! q
  else
    normal! qq
  endif
endfunction

" =============================================================================
" BLANK SLATE — nop every letter + punctuation key in n/v/o modes.
" Explicit bindings emitted below override these Nops.
" Digits stay live so count prefixes (e.g. 5j) still work.
" Ctrl/Alt combos are not nopped (matches nvim init.lua).
" =============================================================================
for s:m in ['n','v','o']
  for s:c in split('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', '\zs')
    execute s:m . 'noremap ' . s:c . ' <Nop>'
  endfor
  for s:c in ['~','!','@','#','$','%','^','&','*','-','+','=','[',']','{','}','`',';','''','"',',','.','/','?','>']
    execute s:m . 'noremap ' . s:c . ' <Nop>'
  endfor
  execute s:m . 'noremap <bar> <Nop>'
  execute s:m . 'noremap <bslash> <Nop>'
  execute s:m . 'noremap <lt> <Nop>'
endfor
unlet s:m s:c

VIMRC_HEAD

  # ---- Mappings, by section, mirroring keybinds.conf order ----
  for modes_str in "${section_order[@]}"; do
    printf '\n" --- modes: %s ---\n' "$modes_str"
    IFS=',' read -ra mode_arr <<< "$modes_str"

    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      lhs="${entry%%=*}"
      rest="${entry#*=}"
      rhs_abstract="${rest%%#*}"

      # Skip prefixes (operators) and explicit nops — blank slate already covers them
      [[ "$rhs_abstract" == "<operator>" ]] && continue
      [[ "$rhs_abstract" == "<nop>" ]] && continue

      resolved="${vocab_vim[$rhs_abstract]:-}"
      [[ -z "$resolved" ]] && continue   # not portable to vim — skip silently

      for m in "${mode_arr[@]}"; do
        printf '%snoremap <silent> %s %s\n' "$m" "$lhs" "$resolved"
      done
    done <<< "${section_keys_raw[$modes_str]:-}"
  done

} > "$VIMRC_OUT"

log "Generated $VIMRC_OUT"
