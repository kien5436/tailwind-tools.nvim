-- NOTE: these are nvim-treesitter *parser* names, not filetypes, so this
-- list intentionally differs from lua/tailwind-tools/filetypes.lua (which
-- uses filetype names like blade, eruby, javascriptreact). Keep both in sync
-- when adding language support.
local parsers = {
  "html",
  "css",
  "tsx",
  "astro",
  "php",
  "twig",
  "svelte",
  "vue",
  "clojure",
  "htmldjango",
  "heex",
  "elixir",
  "javascript",
  "typescript",
  "templ",
}

-- nvim-treesitter's rewrite (main branch) removed :TSInstallSync in favor of
-- require("nvim-treesitter").install(); keep the old command as fallback.
-- Always quit (non-zero on failure): an error before quit would leave a
-- headless `nvim --headless` waiting on stdin forever and stall CI.
local ok, err = pcall(function()
  local ts_ok, ts = pcall(require, "nvim-treesitter")

  if ts_ok and ts.install then
    ts.install(parsers):wait(300000)
  else
    -- master branch (or older): user command installed by the plugin entry.
    vim.cmd("TSInstallSync " .. table.concat(parsers, " "))
  end
end)

if not ok then
  print("parsers install failed: " .. tostring(err))
  vim.cmd("cquit 1")
end

vim.cmd.quit()
