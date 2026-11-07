local assert = require("luassert")
local patterns = require("tailwind-tools.patterns")

describe("patterns:", function()
  it("scans many matches in linear time", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}
    for i = 1, 3000 do
      if i % 10 == 0 then
        lines[i] = 'let x = div { class: "flex items-center p-4" };'
      else
        lines[i] = "let y = 1;"
      end
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local start = vim.uv.hrtime()
    local ranges = patterns.find_class_ranges(buf, "class[=:]%s*[\"']([^\"']+)[\"']")
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    assert.same(300, #ranges)
    assert(elapsed_ms < 2000, "scan took " .. elapsed_ms .. "ms")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("rejects patterns without a capture group", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'x = "flex"' })
    assert.same({}, patterns.find_class_ranges(buf, "flex"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("makes progress on empty matches", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc" })
    assert.same({}, patterns.find_class_ranges(buf, "x*"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
