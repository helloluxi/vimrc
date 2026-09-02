-- =============================================================================
-- init.lua — Neovim entry point
-- Symlinked to ~/.config/nvim/init.lua by nvim/run.sh
-- Keybinds live in keybinds.conf → generated to ~/.config/nvim/lua/keybinds.lua
-- =============================================================================

-- Disable netrw (replaced by nvim-tree)
vim.g.loaded_netrw       = 1
vim.g.loaded_netrwPlugin = 1

-- vim.deprecate()'s health-report backend fails to load on this Neovim build
-- (require('vim.deprecated.health') errors even though the file exists), which
-- turns any plugin's use of a deprecated API (e.g. toggleterm's old-style
-- vim.validate() call) into a hard crash instead of a warning. Swallow that.
do
  local orig_deprecate = vim.deprecate
  vim.deprecate = function(...)
    local ok = pcall(orig_deprecate, ...)
    if not ok then return end
  end
end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
local opt = vim.opt

opt.number         = true
opt.relativenumber = true
opt.cursorline     = true
opt.signcolumn     = "yes"

opt.tabstop        = 2
opt.shiftwidth     = 2
opt.expandtab      = true
opt.smartindent    = true

opt.wrap           = false
opt.scrolloff      = 0
opt.sidescrolloff  = 0

opt.ignorecase     = true
opt.smartcase      = true
opt.hlsearch       = false
opt.incsearch      = true

opt.splitbelow     = true
opt.splitright     = true

opt.clipboard      = "unnamedplus"
opt.undofile       = true
opt.autoread       = true
opt.swapfile       = false
opt.updatetime     = 400

-- Auto-save on every change
vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
  callback = function()
    if vim.bo.modifiable and vim.bo.buftype == "" and vim.fn.expand("%") ~= "" then
      vim.cmd("silent! update")
    end
  end,
})

-- Wrap prose filetypes only
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "tex", "gitcommit", "text", "rst" },
  callback = function()
    vim.opt_local.wrap      = true
    vim.opt_local.linebreak = true
  end,
})

-- Justfile detection (run :TSInstall just once for highlighting)
vim.filetype.add({
  filename = { ["justfile"] = "just", ["Justfile"] = "just" },
  pattern  = { [".*%.just"] = "just" },
})

-- Auto-reload on focus gained or buffer switch
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, { command = "silent! checktime" })

-- Poll for external changes (catches edits by Claude Code etc.)
vim.loop.new_timer():start(1000, 1000, vim.schedule_wrap(function()
  vim.cmd("silent! checktime")
end))

-- Zero timeout: prefix-free keybinds execute immediately
opt.timeout        = false
opt.ttimeout       = false

opt.termguicolors  = true
opt.showmode       = false   -- mode shown in statusline instead

-- Treesitter-based folding (language-aware fold structure for F-prefix fold keys)
opt.foldmethod     = "expr"
opt.foldexpr       = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel      = 99   -- start fully unfolded
opt.foldlevelstart = 99

-- ---------------------------------------------------------------------------
-- Plugins (lazy.nvim)
-- ---------------------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({

  -- LSP
  { "williamboman/mason.nvim",          config = true },
  { "williamboman/mason-lspconfig.nvim" },
  { "neovim/nvim-lspconfig" },

  -- Completion
  { "hrsh7th/nvim-cmp" },
  { "hrsh7th/cmp-nvim-lsp" },
  { "hrsh7th/cmp-buffer" },
  { "hrsh7th/cmp-path" },

  -- Parser management; Neovim handles highlighting natively.
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    -- Parser installation requires the tree-sitter CLI. Keep Neovim usable on
    -- machines where it is not installed rather than failing during startup.
    enabled = function() return vim.fn.executable("tree-sitter") == 1 end,
    build = ":TSUpdate",
    config = function()
      local treesitter = require("nvim-treesitter")
      local required_parsers = { "python", "cpp", "cuda" }
      local required_parser = {}
      for _, parser in ipairs(required_parsers) do
        required_parser[parser] = true
      end

      treesitter.setup()

      local function buffer_language(buf)
        if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
          return nil
        end
        local filetype = vim.bo[buf].filetype
        return vim.treesitter.language.get_lang(filetype) or filetype
      end

      local function start_highlighting(buf, notify_on_error)
        local language = buffer_language(buf)
        if not language then return end

        local ok, err = pcall(vim.treesitter.start, buf)
        if not ok and notify_on_error and required_parser[language] then
          vim.notify_once(
            ("Tree-sitter highlighting unavailable for %s: %s"):format(language, err),
            vim.log.levels.WARN
          )
        end
      end

      -- Installation is asynchronous. A command-line buffer can reach FileType
      -- first, so retry required-language buffers after installation finishes.
      local install_finished = false
      local install_task = treesitter.install(required_parsers)
      install_task:await(function()
        install_finished = true
        vim.schedule(function()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if required_parser[buffer_language(buf)] then
              start_highlighting(buf, true)
            end
          end
        end)
      end)

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("treesitter-highlighting", { clear = true }),
        callback = function(ev)
          start_highlighting(ev.buf, install_finished)
        end,
      })
    end,
  },

  -- Git gutter (inline diff markers + hunk preview)
  { "lewis6991/gitsigns.nvim", config = true },

  -- Auto-close brackets/quotes; integrates with cmp confirm
  {
    "windwp/nvim-autopairs",
    dependencies = { "hrsh7th/nvim-cmp" },
    config = function()
      require("nvim-autopairs").setup()
      require("cmp").event:on(
        "confirm_done",
        require("nvim-autopairs.completion.cmp").on_confirm_done()
      )
    end,
  },

  -- Add/change/delete surroundings  (ys / cs / ds  in n;  s  in v)
  {
    "kylechui/nvim-surround",
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup()
      -- v4 removed keymap config from setup(); bind visual surround to 's' directly
      vim.keymap.set("v", "s", "<Plug>(nvim-surround-visual)", { noremap = false, silent = true })
    end,
  },

  -- File explorer sidebar  (bound to 'a' in normal mode via keybinds.conf)
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view     = { width = 30 },
        renderer = { group_empty = true },
        filters  = { dotfiles = false },
      })
    end,
  },

  -- Fuzzy find
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },

  -- LaTeX — use Skim with PDF sync on macOS when available; otherwise keep
  -- VimTeX's generic viewer without warning (e.g. on Linux).
  {
    "lervag/vimtex",
    init = function()
      local skim_installed = vim.fn.has("macunix") == 1
        and (
          vim.fn.isdirectory("/Applications/Skim.app") == 1
          or vim.fn.isdirectory(vim.fn.expand("~/Applications/Skim.app")) == 1
        )

      if skim_installed then
        vim.g.vimtex_view_method = "skim"
        vim.g.vimtex_view_skim_sync = 1
      end
    end,
  },

  -- LuTeX — live LaTeX/Markdown/Slides browser preview + HTTP file-jump listener (~/lutex)
  -- enabled-guard: silently skipped on machines that don't have ~/lutex checked out
  {
    dir     = "~/lutex",
    enabled = function() return vim.fn.isdirectory(vim.fn.expand("~/lutex")) == 1 end,
    build   = "pnpm install && pnpm run compile",
    config  = function() require("lutex").setup() end,
  },

  -- Jupyter
  { "benlubas/molten-nvim", build = ":UpdateRemotePlugins" },

  -- Floating terminal  (toggle with <C-\>)
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
      require("toggleterm").setup({
        open_mapping = [[<c-\>]],
        direction    = "vertical",
        size         = function(term)
          if term.direction == "vertical" then return vim.o.columns * 0.4 end
          return 20
        end,
      })
    end,
  },

  -- Debugger (future)
  { "mfussenegger/nvim-dap" },

  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = { theme = "tokyonight" },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = { { "filename", path = 1 } },
          lualine_x = {
            function()
              local ok, lutex = pcall(require, "lutex")
              return (ok and lutex.status()) or ""
            end,
            "filetype",
          },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
      })
    end,
  },

  -- Colorscheme
  { "folke/tokyonight.nvim", priority = 1000, config = function()
    vim.cmd.colorscheme("tokyonight-night")
  end },

}, {
  ui = { border = "rounded" },
})

-- ---------------------------------------------------------------------------
-- LSP
-- ---------------------------------------------------------------------------
-- Keep diagnostics visible without underlining the source text.
vim.diagnostic.config({ underline = false })

require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = {
    "clangd",    -- C / C++ / CUDA
    "pyright",   -- Python
    "ruff",      -- Python lint / import-sort / format
    "ts_ls",     -- JavaScript / TypeScript
    "omnisharp", -- C#
    "html",      -- HTML
    "cssls",     -- CSS
    "texlab",    -- LaTeX (LSP features; vimtex handles compilation)
  },
  automatic_installation = true,
})

vim.lsp.config('*', { capabilities = require("cmp_nvim_lsp").default_capabilities() })
vim.lsp.enable({ "clangd", "pyright", "ruff", "ts_ls", "omnisharp", "html", "cssls", "texlab" })

-- Inlay hints (servers that support them — omnisharp, clangd, ts_ls, etc.)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.server_capabilities.inlayHintProvider then
      vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
    end
  end,
})

-- Highlight all references of the symbol under the cursor (servers that support it)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.server_capabilities.documentHighlightProvider then
      local group = vim.api.nvim_create_augroup("lsp-document-highlight-" .. args.buf, { clear = true })
      vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        buffer = args.buf, group = group,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = args.buf, group = group,
        callback = vim.lsp.buf.clear_references,
      })
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Completion (nvim-cmp)
-- ---------------------------------------------------------------------------
local cmp = require("cmp")
cmp.setup({
  mapping = cmp.mapping.preset.insert({
    ["<Tab>"]     = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
    ["<S-Tab>"]   = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
    ["<CR>"]      = cmp.mapping.confirm({ select = true }),
    ["<C-Space>"] = cmp.mapping.complete(),
    ["<C-e>"]     = cmp.mapping.abort(),
  }),
  sources = cmp.config.sources({
    { name = "nvim_lsp" },
    { name = "buffer" },
    { name = "path" },
  }),
})

-- ---------------------------------------------------------------------------
-- Workspace commands (Telescope)
-- ---------------------------------------------------------------------------
local telescope_builtin = require("telescope.builtin")

local workspace_commands = {
  WorkspaceFiles = function()
    telescope_builtin.find_files({ hidden = true, no_ignore = true })
  end,
  WorkspaceGitFiles = function()
    telescope_builtin.git_files({ show_untracked = true })
  end,
  WorkspaceGrep = function()
    telescope_builtin.live_grep()
  end,
  WorkspaceWordGrep = function()
    telescope_builtin.grep_string({ search = vim.fn.expand("<cword>") })
  end,
  WorkspaceBuffers = function()
    telescope_builtin.buffers()
  end,
  WorkspaceRecent = function()
    telescope_builtin.oldfiles()
  end,
  WorkspaceSymbols = function()
    telescope_builtin.lsp_workspace_symbols()
  end,
  WorkspaceDiagnostics = function()
    telescope_builtin.diagnostics()
  end,
  WorkspaceCommands = function()
    telescope_builtin.commands()
  end,
  WorkspaceHelp = function()
    telescope_builtin.help_tags()
  end,
  WorkspaceKeymaps = function()
    telescope_builtin.keymaps()
  end,
  WorkspaceResume = function()
    telescope_builtin.resume()
  end,
}

for name, fn in pairs(workspace_commands) do
  vim.api.nvim_create_user_command(name, fn, {})
end

-- ---------------------------------------------------------------------------
-- Terminal: auto-enter insert mode on focus
-- ---------------------------------------------------------------------------
local function term_startinsert()
  if vim.bo.buftype == "terminal" then
    vim.schedule(function() vim.cmd("startinsert") end)
  end
end
vim.api.nvim_create_autocmd({ "BufEnter", "TermOpen" }, {
  pattern = "term://*",
  callback = term_startinsert,
})
vim.api.nvim_create_autocmd("WinEnter", {
  callback = term_startinsert,
})

-- ---------------------------------------------------------------------------
-- Terminal helpers
-- ---------------------------------------------------------------------------
function _G.new_terminal()
  local terms = require("toggleterm.terminal").get_all(true)
  local max_id = 0
  for _, t in ipairs(terms) do
    if t.id > max_id then max_id = t.id end
  end
  vim.cmd((max_id + 1) .. "ToggleTerm")
end

-- ---------------------------------------------------------------------------
-- Mouse: right-click enters insert mode
-- ---------------------------------------------------------------------------
vim.keymap.set("n", "<RightMouse>", "i")

-- ---------------------------------------------------------------------------
-- LuTeX keybind glue — call a require('lutex') method only when the optional
-- ~/lutex plugin is present; warn instead of throwing when it is absent.
-- ---------------------------------------------------------------------------
function _G.lutex_call(method, ...)
  local ok, lutex = pcall(require, "lutex")
  if not ok then
    vim.notify("[lutex] not installed (~/lutex absent)", vim.log.levels.WARN)
    return
  end
  lutex[method](...)
end

-- ---------------------------------------------------------------------------
-- Keybinds (generated from keybinds.conf by nvim/run.sh)
-- ---------------------------------------------------------------------------
require("keybinds")
