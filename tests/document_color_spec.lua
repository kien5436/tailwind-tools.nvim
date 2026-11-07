local assert = require("luassert")
local lsp = require("tailwind-tools.lsp")

describe("native document_color:", function()
  it("is disabled for the tailwind client on attach", function()
    local calls
    local saved = vim.lsp.document_color
    vim.lsp.document_color = {
      enable = function(enable, filter) calls = { enable, filter } end,
    }

    local fake = {
      id = 7,
      settings = {},
      request = function() end,
      notify = function() end,
    }
    local buf = vim.api.nvim_create_buf(false, true)
    lsp.on_attach(fake, buf)

    assert.is_table(calls)
    assert.same(false, calls[1])
    assert.same(7, calls[2].client_id)

    vim.lsp.document_color = saved
    lsp.on_detach_cb({ buf = buf })
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
