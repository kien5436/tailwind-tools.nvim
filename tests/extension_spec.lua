local assert = require("luassert")
local lsp = require("tailwind-tools.lsp")
local config = require("tailwind-tools.config")
local classes = require("tailwind-tools.classes")

describe("class_regex extension:", function()
  local user_regex = { "tw`([^`]*)`" }
  local orig_inside = classes.is_inside
  local orig_regex = config.options.server.class_regex

  local function make_client(id, notifies, requests)
    return {
      id = id,
      settings = {},
      notify = function(_, _, _) notifies[#notifies + 1] = true end,
      request = function(_, _, _, _) requests[#requests + 1] = true end,
    }
  end

  after_each(function()
    classes.is_inside = orig_inside
    config.options.server.class_regex = orig_regex
  end)

  it("registers, clears, and re-registers regex with cursor state", function()
    config.options.server.class_regex = user_regex
    classes.is_inside = function() return true end

    local notifies, requests = {}, {}
    local client = make_client(101, notifies, requests)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '<div class="flex">' })
    vim.api.nvim_set_current_buf(buf)

    lsp.on_attach(client, buf)
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
    vim.wait(2000, function() return #notifies >= 1 end)
    assert.same(user_regex, client.settings.tailwindCSS.experimental.classRegex)

    classes.is_inside = function() return false end
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
    vim.wait(2000, function() return #notifies >= 2 end)
    assert.same({}, client.settings.tailwindCSS.experimental.classRegex)

    -- returning to the buffer re-registers when the cursor is inside again
    classes.is_inside = function() return true end
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    vim.wait(2000, function() return #notifies >= 3 end)
    assert.same(user_regex, client.settings.tailwindCSS.experimental.classRegex)

    lsp.on_detach_cb({ buf = buf })
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("stays inert without user regex", function()
    config.options.server.class_regex = {}
    classes.is_inside = function() return true end

    local notifies, requests = {}, {}
    local client = make_client(102, notifies, requests)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)

    lsp.on_attach(client, buf)
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
    vim.wait(300)
    assert.same(0, #notifies)

    lsp.on_detach_cb({ buf = buf })
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
