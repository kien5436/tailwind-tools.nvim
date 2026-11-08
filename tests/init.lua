-- minimal init.lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end

vim.opt.rtp:prepend(lazypath)
vim.o.swapfile = false

-- Test-only dependencies track latest Neovim, but Neovim < 0.11 needs pins
-- to versions that still support it: nvim-treesitter's rewrite (main) and
-- recent telescope.nvim both require 0.11+. lazy.nvim's own version pinning
-- does not work on 0.10, so legacy plugins are cloned manually (pinned ref)
-- and put on the rtp directly instead of going through lazy specs.
local is_legacy = vim.fn.has("nvim-0.11") == 0

if is_legacy then
  local legacy_dir = vim.fn.stdpath("data") .. "/legacy"
  local pins = {
    { repo = "https://github.com/nvim-treesitter/nvim-treesitter.git", ref = "master" },
    { repo = "https://github.com/nvim-telescope/telescope.nvim.git", ref = "0.1.8" },
  }

  for _, pin in ipairs(pins) do
    local name = pin.repo:match("([^/]+)%.git$")
    local dir = legacy_dir .. "/" .. name

    if not (vim.uv or vim.loop).fs_stat(dir) then
      vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch", pin.ref, pin.repo, dir })
    end

    vim.opt.rtp:prepend(dir)
  end
end

local dependencies = is_legacy and { "neovim/nvim-lspconfig" }
  or {
    "nvim-treesitter/nvim-treesitter",
    "nvim-telescope/telescope.nvim",
    "neovim/nvim-lspconfig",
  }

require("lazy").setup({
  { "nvim-lua/plenary.nvim", cmd = "PlenaryBustedDirectory" },
  {
    dir = "./",
    dependencies = dependencies,
    config = function() require("tailwind-tools").setup({}) end,
  },
}, {
  -- Legacy plugins are prepended to the rtp manually above; keep lazy from
  -- resetting the runtime path and dropping them.
  performance = { rtp = { reset = false } },
})
