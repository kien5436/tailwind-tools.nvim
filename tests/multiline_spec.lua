local assert = require("luassert")
local classes = require("tailwind-tools.classes")

describe("multiline containment:", function()
  it("reports inside on middle lines and containing range", function()
    vim.cmd.edit("tests/queries/html/multiline.html")
    local ranges = classes.get_ranges(0)
    assert.same(1, #ranges)
    -- middle line, inside the class value
    vim.api.nvim_win_set_cursor(0, { 2, 4 })
    assert.same(true, classes.is_inside(0))
    -- above / below the range
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert.same(false, classes.is_inside(0))
  end)
end)
