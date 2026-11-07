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
local ok, ts = pcall(require, "nvim-treesitter")

if ok and ts.install then
  ts.install(parsers):wait(300000)
else
  vim.cmd.TSInstallSync(parsers)
end

vim.cmd.quit()
