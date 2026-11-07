-- Minimal init for running a single spec file without lazy.nvim.
-- PlenaryBustedFile cannot be used in this repo: plenary's test_file()
-- spawns the child with --noplugin and no -u init, so the plugin setup
-- (and vim.g.tailwind_tools) never happens. Use instead (from repo root):
--
--   nvim --headless --noplugin -u tests/minimal_init.lua \
--     -c 'lua require("plenary.busted").run("tests/lsp/lsp_v4_spec.lua")'
--
-- LSP specs additionally need tailwindcss-language-server on PATH, e.g.:
--   export PATH="$HOME/.local/share/nvim/mason/bin:$PATH"

vim.opt.rtp:append(".")

local lazy = vim.fn.stdpath("data") .. "/lazy"
for _, plug in ipairs({ "plenary.nvim", "nvim-treesitter", "nvim-lspconfig", "telescope.nvim" }) do
  local p = lazy .. "/" .. plug
  if vim.fn.isdirectory(p) == 1 then vim.opt.rtp:append(p) end
end

vim.o.swapfile = false

require("tailwind-tools").setup({})
