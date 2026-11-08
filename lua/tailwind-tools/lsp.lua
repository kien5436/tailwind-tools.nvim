local M = {}

local log = require("tailwind-tools.log")
local utils = require("tailwind-tools.utils")
local state = require("tailwind-tools.state")
local config = require("tailwind-tools.config")
local classes = require("tailwind-tools.classes")
local filetypes = require("tailwind-tools.filetypes")

-- Tracks (client, buffer) pairs already wired, because Neovim fires both
-- LspAttach (handled by on_attach_cb) and the lspconfig on_attach wrapper
-- (make_on_attach) for the same attach.
local attached = {}

local color_events = {
  "BufEnter",
  "TextChanged",
  "TextChangedI",
  "CursorMoved",
  "CursorMovedI",
}

-- Last known inside/outside state per buffer, avoids spamming the server
-- with workspace/didChangeConfiguration on every CursorMoved.
local extension_inside = {}
local extension_timer = nil

---@param bufnr? number
---@return vim.lsp.Client?
local function get_tailwindcss(bufnr)
  ---@diagnostic disable-next-line: deprecated
  local get_client = vim.lsp.get_clients or vim.lsp.get_active_clients
  local clients = get_client({ bufnr = bufnr or 0, name = "tailwindcss" })
  return clients[1]
end

---@param bufnr number
---@param color lsp.ColorInformation
local function set_extmark(bufnr, color)
  local r = math.floor(color.color.red * 255)
  local g = math.floor(color.color.green * 255)
  local b = math.floor(color.color.blue * 255)
  local hl_kind = config.options.document_color.kind
  local hl_group = utils.set_hl_from(r, g, b, hl_kind)
  local namespace = vim.g.tailwind_tools.color_ns
  local start_row = color.range.start.line
  local start_col = color.range.start.character
  local opts = {}

  if hl_kind == "inline" then
    opts.virt_text = { { config.options.document_color.inline_symbol, hl_group } }
    opts.virt_text_pos = "inline"
  else
    opts.hl_group = hl_group
    opts.end_row = color.range["end"].line
    opts.end_col = color.range["end"].character
    opts.priority = 1000
  end

  vim.api.nvim_buf_set_extmark(bufnr, namespace, start_row, start_col, opts)
  state.color.active_buffers[bufnr] = true
end

---@param bufnr number
local function debounced_color_request(client, bufnr)
  local timer = state.color.request_timer

  if timer then
    state.color.request_timer = nil
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end

  state.color.request_timer = vim.defer_fn(
    function() M.color_request(client, bufnr) end,
    config.options.document_color.debounce
  )
end

---@param ranges { [integer]: number, delimiter?: { raw: string, pattern: string } }[]
---@param bufnr number
---@param sync boolean
local function sort_classes(ranges, bufnr, sync)
  local client = get_tailwindcss(bufnr)

  if not client then return log.error("tailwind-language-server is not running") end
  if #ranges == 0 then return end

  local class_text = {}

  for _, range in pairs(ranges) do
    local start_row, start_col, end_row, end_col = unpack(range)
    local text = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
    text = table.concat(text, "\n")
    if range.delimiter then text = string.gsub(text, range.delimiter.pattern, " ") end
    class_text[#class_text + 1] = text
  end

  local params = vim.tbl_extend("error", vim.lsp.util.make_text_document_params(bufnr), {
    classLists = class_text,
  })

  local handler = function(err, result, _, _)
    if err then return log.error(err.message) end
    if not result or not vim.api.nvim_buf_is_valid(bufnr) then return end
    if result.error then return log.error(result.error) end
    if not result.classLists then return end

    for i, edit in pairs(result.classLists) do
      if not ranges[i] then break end
      if ranges[i].delimiter then
        edit = table.concat(vim.split(edit, "%s+"), ranges[i].delimiter.raw)
      end

      local lines = vim.split(edit, "\n")
      local s_row, s_col, e_row, e_col = unpack(ranges[i])

      -- Dismiss useless error messages when undoing in nightly
      pcall(function() vim.api.nvim_buf_set_text(bufnr, s_row, s_col, e_row, e_col, lines) end)
    end
  end

  if sync then
    local response =
      utils.client_request_sync(client, "@/tailwindCSS/sortSelection", params, 2000, bufnr)

    if response then
      handler(response.err, response.result)
    else
      log.error("LSP request timed out")
    end
  else
    utils.client_request(client, "@/tailwindCSS/sortSelection", params, handler, bufnr)
  end
end
---@param regex string[] | string[][]
---@param client? vim.lsp.Client
M.register_regex = function(regex, client)
  client = client or get_tailwindcss()
  if not client then return end

  client.settings = client.settings or {}
  client.settings.tailwindCSS = client.settings.tailwindCSS or {}
  client.settings.tailwindCSS.experimental = client.settings.tailwindCSS.experimental or {}
  client.settings.tailwindCSS.experimental.classRegex = regex

  utils.client_notify(client, "workspace/didChangeConfiguration", {
    settings = client.settings,
  })
end

---@param server_config TailwindTools.ServerOption
---@return lspconfig.Config
local function build_conf(server_config)
  local conf = { settings = {} }

  conf.settings.tailwindCSS = vim.tbl_get(server_config, "settings", "tailwindCSS") or {}
  conf.settings.tailwindCSS =
    vim.tbl_deep_extend("keep", conf.settings.tailwindCSS, server_config.settings)
  conf.settings.tailwindCSS.includeLanguages = vim.tbl_extend(
    "keep",
    server_config.settings.includeLanguages or {},
    filetypes.get_server_map()
  )

  conf.capabilities = vim.lsp.protocol.make_client_capabilities()
  conf.capabilities.textDocument.colorProvider = {
    dynamicRegistration = true,
  }

  return conf
end

---@param server_config TailwindTools.ServerOption
---@param lspconfig { tailwindcss: lspconfig.Config }
M.setup = function(server_config, lspconfig)
  for key, _ in pairs(attached) do
    attached[key] = nil
  end
  local conf = build_conf(server_config)
  conf.on_attach = M.make_on_attach(server_config.on_attach)
  conf.root_dir = server_config.root_dir or M.make_root_dir(lspconfig)

  lspconfig.tailwindcss.setup(conf)
end

---@param server_config TailwindTools.ServerOption
M.setup_native = function(server_config)
  for key, _ in pairs(attached) do
    attached[key] = nil
  end
  local conf = build_conf(server_config)
  conf.on_attach = M.make_on_attach(server_config.on_attach)
  conf.filetypes = filetypes.get_all()

  -- Without nvim-lspconfig there is no base `lsp/tailwindcss.lua` config, so
  -- supply our own root markers. Mirrors the root_files in M.make_root_dir.
  -- Note: bare `package.json` is intentionally excluded (unlike the lspconfig
  -- path which checks for a tailwindcss dependency); it would otherwise
  -- attach the server to any JS project.
  conf.root_markers = {
    "tailwind.config.js",
    "tailwind.config.cjs",
    "tailwind.config.mjs",
    "tailwind.config.ts",
    "postcss.config.js",
    "postcss.config.cjs",
    "postcss.config.mjs",
  }

  -- Preserve the plugin's legacy `root_dir(fname)` option by adapting
  -- it to Neovim 0.11's asynchronous `root_dir(bufnr, on_dir)` callback.
  if server_config.root_dir then
    conf.root_dir = function(bufnr, on_dir)
      on_dir(server_config.root_dir(vim.api.nvim_buf_get_name(bufnr)))
    end
  end

  vim.lsp.config("tailwindcss", conf)
  vim.lsp.enable("tailwindcss")
end

---@type fun(lspconfig: any)
---@return function(fname: string): string?
M.make_root_dir = function(lspconfig)
  return function(fname)
    local root_files = lspconfig.util.insert_package_json({
      "tailwind.config.{js,cjs,mjs,ts}",
      "assets/tailwind.config.{js,cjs,mjs,ts}",
      "theme/static_src/tailwind.config.{js,cjs,mjs,ts}",
      "app/assets/stylesheets/application.tailwind.css",
      "app/assets/tailwind/application.css",
    }, "tailwindcss", fname)
    return lspconfig.util.root_pattern(root_files)(fname)
  end
end

---@type fun(user_on_attach: function | nil)
---@return function(client: vim.lsp.Client, bufnr: integer)
M.make_on_attach = function(user_on_attach)
  if type(user_on_attach) == "function" then
    return function(client, bufnr)
      user_on_attach(client, bufnr)
      M.on_attach(client, bufnr)
    end
  else
    return M.on_attach
  end
end

-- Last regex state sent per client (client-global setting). Per-buffer
-- extension_inside tracks cursor state; last_sent_inside tracks what each
-- server actually has, so returning to a buffer re-registers when needed.
local last_sent_inside = {}

---@param args vim.api.keyset.create_autocmd.callback_args
M.on_attach_cb = function(args)
  local clients = vim.lsp.get_clients({ bufnr = args.buf, name = "tailwindcss" })
  if #clients == 0 then return end
  M.on_attach(clients[1], args.buf)
end

---@param args vim.api.keyset.create_autocmd.callback_args
M.on_detach_cb = function(args)
  for key, _ in pairs(attached) do
    if key:match(":" .. args.buf .. "$") then
      local id = key:match("^(%d+):")
      attached[key] = nil
      if id then last_sent_inside[tonumber(id)] = nil end
    end
  end
  extension_inside[args.buf] = nil
  if extension_timer then
    extension_timer:stop()
    extension_timer:close()
    extension_timer = nil
  end
end

-- Last regex state sent per client (client-global setting). Per-buffer
-- extension_inside tracks cursor state; last_sent_inside tracks what each
-- server actually has, so returning to a buffer re-registers when needed.

---@param client vim.lsp.Client
---@param bufnr integer
local function send_extension_state(client, bufnr, inside)
  local user_regex = config.options.server.class_regex or {}
  if #user_regex == 0 then return end
  if last_sent_inside[client.id] == inside then
    M.color_request(client, bufnr)
    return
  end
  last_sent_inside[client.id] = inside
  local regex = inside and user_regex or {}
  M.register_regex(regex, client)
  M.color_request(client, bufnr)
end

---@param client vim.lsp.Client
---@param bufnr integer
M.on_attach = function(client, bufnr)
  local key = client.id .. ":" .. bufnr
  if attached[key] then return end
  attached[key] = true

  -- The plugin renders colors itself; disable Neovim's native documentColor
  -- provider (0.12+) for this client so colors are not double-rendered and
  -- TailwindColorDisable actually turns them off.
  if vim.lsp.document_color and vim.lsp.document_color.enable then
    vim.lsp.document_color.enable(false, { client_id = client.id })
  end

  vim.api.nvim_create_autocmd(color_events, {
    group = vim.g.tailwind_tools.color_au,
    buffer = bufnr,
    callback = function(a)
      if not state.color.enabled then return end
      if a.event == "TextChangedI" then
        debounced_color_request(client, bufnr)
      elseif vim.startswith(a.event, "Cursor") == state.conceal.enabled then
        M.color_request(client, bufnr)
      end
    end,
  })

  if config.options.server.client_extension then
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = vim.g.tailwind_tools.color_au,
      buffer = bufnr,
      callback = function(args)
        -- Only user-provided regexes are ever registered; an empty list
        -- keeps the feature inert (no server traffic, no catch-all noise).
        local user_regex = config.options.server.class_regex or {}
        if #user_regex == 0 then return end

        -- Dynamically toggle regex based on cursor position,
        -- only notifying the server when the state flips (debounced).
        local inside = classes.is_inside(args.buf)
        if extension_inside[args.buf] == inside then return end
        extension_inside[args.buf] = inside

        if extension_timer then
          extension_timer:stop()
          extension_timer:close()
          extension_timer = nil
        end

        extension_timer = vim.defer_fn(function()
          extension_timer = nil
          if not vim.api.nvim_buf_is_valid(args.buf) then return end
          send_extension_state(client, args.buf, extension_inside[args.buf])
        end, 200)
      end,
    })

    -- The regex is client-global: returning to a buffer whose cursor state
    -- differs from what the server last received must re-register.
    vim.api.nvim_create_autocmd("BufEnter", {
      group = vim.g.tailwind_tools.color_au,
      buffer = bufnr,
      callback = function(args)
        local user_regex = config.options.server.class_regex or {}
        if #user_regex == 0 then return end
        local inside = classes.is_inside(args.buf)
        extension_inside[args.buf] = inside
        send_extension_state(client, args.buf, inside)
      end,
    })

    vim.api.nvim_create_autocmd("BufDelete", {
      group = vim.g.tailwind_tools.color_au,
      buffer = bufnr,
      callback = function(args) extension_inside[args.buf] = nil end,
    })
  end

  if state.color.enabled then M.color_request(client, bufnr) end
end

---@param client vim.lsp.Client | nil
---@param bufnr number
M.color_request = function(client, bufnr)
  if not state.color.enabled then return end
  client = client or get_tailwindcss(bufnr)
  if not client then return end

  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }

  utils.client_request(client, "textDocument/documentColor", params, function(err, result, _, _)
    if err then return log.error(err.message) end
    if not result or not vim.api.nvim_buf_is_valid(bufnr) then return end

    ---@type lsp.ColorInformation[]
    local colors = result
    vim.api.nvim_buf_clear_namespace(bufnr, vim.g.tailwind_tools.color_ns, 0, -1)

    for _, color in pairs(colors) do
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- Starts at 1
      local cursor_aligned = (state.conceal.enabled and cursor_line == color.range.start.line)

      if not state.conceal.enabled or cursor_aligned then
        pcall(function() set_extmark(bufnr, color) end)
      end
    end
  end, bufnr)
end

M.enable_color = function()
  state.color.enabled = true
  local client = get_tailwindcss(0)
  if client then M.color_request(client, 0) end
end

M.disable_color = function()
  local timer = state.color.request_timer
  if timer then
    state.color.request_timer = nil
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  for bufnr, _ in pairs(state.color.active_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, vim.g.tailwind_tools.color_ns, 0, -1)
    end
  end

  state.color.active_buffers = {}
  state.color.enabled = false
end

M.toggle_colors = function()
  if state.color.enabled then
    M.disable_color()
  else
    M.enable_color()
  end
end

---@param sync boolean?
---@param opts? { line1: number, line2: number }
M.sort_selection = function(sync, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local s_row, s_col, e_row, e_col = utils.get_visual_range()

  if s_row < 0 and opts and opts.line1 and opts.line2 then
    s_row = opts.line1 - 1
    e_row = opts.line2 - 1
    s_col = 0
    e_col = #vim.api.nvim_buf_get_lines(bufnr, e_row, e_row + 1, false)[1]
  end

  if s_row < 0 then return log.info("No selection") end

  local class_ranges = { { s_row, s_col, e_row, e_col } }

  sort_classes(class_ranges, bufnr, sync)
end

---@param sync boolean
M.sort_classes = function(sync)
  local bufnr = vim.api.nvim_get_current_buf()
  local class_ranges = classes.get_ranges(bufnr, { sortable = true })

  sort_classes(class_ranges, bufnr, sync)
end

return M
