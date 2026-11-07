local M = {}

local lsp = require("tailwind-tools.lsp")
local state = require("tailwind-tools.state")
local config = require("tailwind-tools.config")
local classes = require("tailwind-tools.classes")

---@param bufnr number
local function set_conceal(bufnr)
  local class_ranges = classes.get_ranges(bufnr)

  if #class_ranges == 0 then return end

  vim.wo.conceallevel = 2
  vim.api.nvim_buf_clear_namespace(bufnr, vim.g.tailwind_tools.conceal_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, vim.g.tailwind_tools.color_ns, 0, -1)
  state.conceal.active_buffers[bufnr] = true

  local opts = config.options.conceal

  for _, range in pairs(class_ranges) do
    local s_row, s_col, e_row, e_col = unpack(range)

    if not opts.min_length or e_row ~= s_row or e_col - s_col >= opts.min_length then
      vim.api.nvim_buf_set_extmark(bufnr, vim.g.tailwind_tools.conceal_ns, s_row, s_col, {
        end_line = e_row,
        end_col = e_col,
        conceal = opts.symbol,
        hl_group = "TailwindConceal",
        priority = 0, -- To ignore conceal hl_group when focused
      })
    end
  end
end

local registered = false

local function register()
  if registered then return end
  registered = true

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = vim.g.tailwind_tools.conceal_au,
    callback = function(args) set_conceal(args.buf) end,
  })
  -- Workaround to reset conceallevel per buffer
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.g.tailwind_tools.conceal_au,
    callback = function(args)
      vim.wo.conceallevel = vim.opt.conceallevel:get()
      if state.conceal.enabled then set_conceal(args.buf) end
    end,
  })
end

---@param bufnr integer
M.apply = function(bufnr)
  if state.conceal.enabled and vim.api.nvim_buf_is_valid(bufnr) then set_conceal(bufnr) end
end

M.enable = function()
  register()
  state.conceal.enabled = true

  for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then set_conceal(bufnr) end
  end

  -- Restore color hints
  if state.color.enabled then lsp.color_request(nil, 0) end
end

M.disable = function()
  state.conceal.enabled = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_option_value("conceallevel", 0, { win = win })
    end
  end
  vim.api.nvim_clear_autocmds({ group = vim.g.tailwind_tools.conceal_au })
  registered = false

  for bufnr, _ in pairs(state.conceal.active_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, vim.g.tailwind_tools.conceal_ns, 0, -1)
    end
  end

  if state.color.enabled then lsp.color_request(nil, 0) end

  state.conceal.active_buffers = {}
end

M.toggle = function()
  if state.conceal.enabled then
    M.disable()
  else
    M.enable()
  end
end

return M
