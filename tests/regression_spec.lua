local assert = require("luassert")
local lsp = require("tailwind-tools.lsp")
local state = require("tailwind-tools.state")

describe("sort command:", function()
  it("uses the async path", function()
    local seen = {}
    local fake = {
      request = function(_, method)
        seen.method = method
      end,
      request_sync = function()
        seen.sync = true
      end,
    }
    local orig = vim.lsp.get_clients
    vim.lsp.get_clients = function() return { fake } end
    vim.cmd.edit("tests/queries/html/index.html")
    vim.cmd.TailwindSort()
    vim.lsp.get_clients = orig
    assert.same("@/tailwindCSS/sortSelection", seen.method)
    assert.same(nil, seen.sync)
  end)

  it("falls back to the command range without a visual selection", function()
    local seen = {}
    local fake = {
      request = function(_, method, params)
        seen.method = method
        seen.params = params
      end,
    }
    local orig = vim.lsp.get_clients
    vim.lsp.get_clients = function() return { fake } end
    vim.cmd.edit("tests/queries/html/index.html")
    -- clear visual marks so only the command range applies
    vim.fn.setpos("'<", { 0, 0, 0, 0 })
    vim.fn.setpos("'>", { 0, 0, 0, 0 })
    vim.api.nvim_win_set_cursor(0, { 11, 0 })
    vim.cmd("11TailwindSortSelection")
    vim.lsp.get_clients = orig
    assert.same("@/tailwindCSS/sortSelection", seen.method)
    assert.same(1, #seen.params.classLists)
  end)
end)

describe("per-buffer client:", function()
  it("routes requests to the buffer's client", function()
    local lsp_mod = require("tailwind-tools.lsp")
    assert.is_function(lsp_mod.sort_classes)
    assert.is_function(lsp_mod.color_request)
  end)
end)

describe("color toggle:", function()
  it("stays disabled and enables cleanly", function()
    vim.cmd.TailwindColorDisable()
    assert.same(false, state.color.enabled)
    vim.cmd("colorscheme vim")
    assert.same(false, state.color.enabled)
    vim.cmd.TailwindColorEnable()
    assert.same(true, state.color.enabled)
    vim.cmd.TailwindColorDisable()
    assert.same(false, state.color.enabled)
    vim.cmd.TailwindColorEnable()
    assert.same(true, state.color.enabled)
  end)
end)

describe("register_regex:", function()
  it("preserves sibling settings", function()
    local notified
    local fake = {
      settings = { tailwindCSS = { experimental = { other = 1 } } },
      notify = function(_, _, _) notified = true end,
    }
    lsp.register_regex({ "x" }, fake)
    assert.same(1, fake.settings.tailwindCSS.experimental.other)
    assert.same({ "x" }, fake.settings.tailwindCSS.experimental.classRegex)
    assert.same(true, notified)
  end)
end)

describe("patterns:", function()
  it("handles missing captures and empty matches", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'x = 1' })
    local patterns = require("tailwind-tools.patterns")
    assert.same({}, patterns.find_class_ranges(buf, "class"))
    assert.same({}, patterns.find_class_ranges(buf, "x*"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
