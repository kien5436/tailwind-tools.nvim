local M = {}

---@param red number
---@param green number
---@param blue number
---@param style TailwindTools.ColorHint
M.set_hl_from = function(red, green, blue, style)
  local suffix = style == "background" and "Bg" or "Fg"
  local color = string.format("%02x%02x%02x", red, green, blue)
  local hl_name = "TailwindColor" .. suffix .. color
  local opts

  if style == "background" then
    -- https://stackoverflow.com/questions/3942878
    local luminance = red * 0.299 + green * 0.587 + blue * 0.114
    local fg = luminance > 186 and "#000000" or "#FFFFFF"
    opts = { fg = fg, bg = "#" .. color }
  else
    opts = { fg = "#" .. color }
  end

  if next(vim.api.nvim_get_hl(0, { name = hl_name, create = false })) == nil then
    vim.api.nvim_set_hl(0, hl_name, opts)
  end

  return hl_name
end

---@param s string
M.extract_color = function(s)
  local base, _, _, r, g, b = 10, s:find("rgba?%((%d+).%s*(%d+).%s*(%d+)")

  if not r then
    base, _, _, r, g, b = 16, s:find("#(%x%x)(%x%x)(%x%x)")
  end

  if r then return tonumber(r, base), tonumber(g, base), tonumber(b, base) end
end

---Returns the 0-based range of the visual selection (start_row, start_col, end_row, end_col)
M.get_visual_range = function()
  local s_row = vim.fn.line("'<") - 1
  local s_col = vim.fn.col("'<") - 1
  local e_row = vim.fn.line("'>") - 1
  local e_col = vim.fn.col("'>")

  return s_row, s_col, e_row, e_col
end

-- Neovim 0.10 pre-binds LSP client methods (method_wrapper), so they must be
-- invoked with `.` and no self; 0.11+ defines real methods invoked with `:`.
-- Calling a bound method with `:` shifts every argument (bufnr receives the
-- handler function) and breaks requests on 0.10.
M.is_legacy_nvim = vim.fn.has("nvim-0.11") == 0

---@param client vim.lsp.Client
M.client_request = function(client, method, params, handler, bufnr)
  if M.is_legacy_nvim then return client.request(method, params, handler, bufnr) end
  return client:request(method, params, handler, bufnr)
end

---@param client vim.lsp.Client
M.client_request_sync = function(client, method, params, timeout_ms, bufnr)
  if M.is_legacy_nvim then return client.request_sync(method, params, timeout_ms, bufnr) end
  return client:request_sync(method, params, timeout_ms, bufnr)
end

---@param client vim.lsp.Client
M.client_notify = function(client, method, params)
  if M.is_legacy_nvim then return client.notify(method, params) end
  return client:notify(method, params)
end

return M
