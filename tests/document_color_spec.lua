local assert = require("luassert")
local lsp = require("tailwind-tools.lsp")

describe("native document_color:", function()
  it("is disabled for the buffer on attach (single source of truth)", function()
    local calls = {}
    local scheduled = {}
    local saved = vim.lsp.document_color
    local saved_schedule = vim.schedule
    vim.lsp.document_color = {
      enable = function(enable, filter) table.insert(calls, { enable, filter }) end,
    }
    vim.schedule = function(fn) table.insert(scheduled, fn) end

    local fake = {
      id = 7,
      settings = {},
      request = function() end,
      notify = function() end,
    }
    local buf = vim.api.nvim_create_buf(false, true)
    lsp.on_attach(fake, buf)

    -- synchronous buffer-scoped disable (covers tailwind + cssls)
    assert.same(false, calls[1][1])
    assert.same(buf, calls[1][2].bufnr)
    assert.is_nil(calls[1][2].client_id)
    -- deferred re-disable wins over core's scheduled Capability:on_attach
    assert.same(1, #scheduled)
    scheduled[1]()
    assert.same(false, calls[2][1])
    assert.same(buf, calls[2][2].bufnr)

    vim.lsp.document_color = saved
    vim.schedule = saved_schedule
    lsp.on_detach_cb({ buf = buf })
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
