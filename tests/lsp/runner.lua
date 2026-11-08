local assert = require("luassert")
local utils = require("tailwind-tools.utils")
local state = require("tailwind-tools.state")
local config = require("tailwind-tools.config")
local get_extmarks = require("tests.common").get_extmarks

local M = {}

---@class LspTestSpec
---@field id string
---@field version string
---@field path string

---@param spec LspTestSpec
M.test = function(spec)
  describe(("project (%s):"):format(spec.id), function()
    it("Should initialize project", function()
      -- A previous spec in the same process may have left a live tailwindcss
      -- server running for another project root (only relevant when specs run
      -- sequentially). Force-stop for a clean slate.
      for _, c in ipairs(vim.lsp.get_clients({ name = "tailwindcss" })) do
        vim.lsp.stop_client(c.id, true)
      end

      vim.wait(10000, function() return #vim.lsp.get_clients({ name = "tailwindcss" }) == 0 end)

      vim.cmd.edit(spec.path)

      ---@type vim.lsp.Client | nil
      local client

      vim.wait(20000, function()
        for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0, name = "tailwindcss" })) do
          -- A previous spec's dying client may still be attached; only accept
          -- the client actually rooted at this spec's project.
          local root = c.config and c.config.root_dir
          if type(root) ~= "string" or root:sub(-#spec.id) == spec.id then
            client = c
            return true
          end
        end
        return false
      end)

      assert(client, "Couldn't get client")

      local bufnr = vim.api.nvim_get_current_buf()
      local params = vim.lsp.util.make_text_document_params(bufnr)
      local response

      -- The language server detects the project asynchronously after startup
      -- and reports `result: null` until it has finished; on a cold start (CI)
      -- this can exceed the default budget, so poll with a generous one.
      vim.wait(60000, function()
        response =
          utils.client_request_sync(client, "@/tailwindCSS/getProject", params, 10000, bufnr)
        return response and response.result ~= nil
      end)

      assert(response and response.result, "No project found: " .. vim.json.encode(response or {}))

      -- Patch drift (server 0.16 vs fixture pins) must not break CI, but a
      -- wrong-major project still fails loudly.
      local reported = response.result.version or ""
      local expected_major = spec.version:match("^(%d+)")
      local reported_major = reported:match("^(%d+)")
      assert(
        expected_major ~= nil and reported_major == expected_major,
        ("Version mismatch: server reports %q, fixture expects major %q (pin %q)"):format(
          reported,
          expected_major,
          spec.version
        )
      )
    end)
  end)

  describe(("color (%s):"):format(spec.id), function()
    local ns = vim.g.tailwind_tools.color_ns

    it("Should show inline colors", function()
      config.options.document_color.kind = "inline"

      vim.wait(5000, function() return #state.color.active_buffers ~= 0 end)

      local symbol = config.options.document_color.inline_symbol
      local extmarks = get_extmarks(0, ns, { "virt_text" })

      local expected = {
        { 12, 64, { virt_text = { { symbol, "TailwindColorFg111827" } } } },
        { 14, 40, { virt_text = { { symbol, "TailwindColorFg22d3ee" } } } },
      }

      assert.same(expected, extmarks)
    end)

    it("Should clear colors", function()
      vim.cmd.TailwindColorDisable()

      assert.same({}, get_extmarks(0, ns))
      assert.same({}, state.color.active_buffers)
    end)

    it("Should show background colors", function()
      config.options.document_color.kind = "background"

      vim.cmd.TailwindColorEnable()
      vim.wait(5000, function() return #state.color.active_buffers ~= 0 end)

      local extmarks = get_extmarks(0, ns, { "hl_group" })

      local expected = {
        { 12, 64, 12, 76, { hl_group = "TailwindColorBg111827" } },
        { 14, 40, 14, 54, { hl_group = "TailwindColorBg22d3ee" } },
      }

      assert.same(expected, extmarks)

      vim.cmd.TailwindColorDisable()
    end)

    it("Should show foreground colors", function()
      config.options.document_color.kind = "foreground"

      vim.cmd.TailwindColorEnable()
      vim.wait(5000, function() return #state.color.active_buffers ~= 0 end)

      local extmarks = get_extmarks(0, ns, { "hl_group" })

      local expected = {
        { 12, 64, 12, 76, { hl_group = "TailwindColorFg111827" } },
        { 14, 40, 14, 54, { hl_group = "TailwindColorFg22d3ee" } },
      }

      assert.same(expected, extmarks)
    end)

    it("Should not be affected by colorscheme", function()
      vim.cmd.colorscheme("vim")

      local extmarks = get_extmarks(0, ns, { "hl_group" })

      local expected = {
        { 12, 64, 12, 76, { hl_group = "TailwindColorFg111827" } },
        { 14, 40, 14, 54, { hl_group = "TailwindColorFg22d3ee" } },
      }

      assert.same(expected, extmarks)
    end)
  end)

  describe(("sort (%s):"):format(spec.id), function()
    it("Should sort selection", function()
      vim.cmd.TailwindNextClass()
      vim.cmd.normal('vi"\28\14')
      vim.cmd([['<,'>TailwindSortSelectionSync]])

      local s_row, s_col, e_row, e_col = utils.get_visual_range()
      local class = vim.api.nvim_buf_get_text(0, s_row, s_col, e_row, e_col, {})
      local expected = "flex h-screen w-screen items-center justify-center bg-[#111827]"

      assert.same(expected, class[1])
    end)

    it("Should sort all classes", function()
      vim.cmd.normal("u")
      vim.cmd.TailwindSortSync()

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)

      vim.cmd.edit("tests/lsp/sorted.html")

      local expected = vim.api.nvim_buf_get_lines(0, 0, -1, true)

      assert.same(expected, lines)
    end)
  end)

  -- Force-stop the language server before this spec's process exits. Plenary
  -- runs each spec in its own `nvim --headless` job and fails the job on a
  -- non-zero exit; leaving a live client to Neovim's shutdown path exits 1 on
  -- some nightly Linux builds even after every test passes.
  for _, c in ipairs(vim.lsp.get_clients({ name = "tailwindcss" })) do
    vim.lsp.stop_client(c.id, true)
  end
  vim.wait(3000, function() return #vim.lsp.get_clients({ name = "tailwindcss" }) == 0 end)
end

return M
