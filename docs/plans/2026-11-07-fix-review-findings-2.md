# Fix Review Findings (Round 2) Plan

## Goal
Fix the five highest-impact findings from the review (conceal startup, always-sync sort, colors after disable, multi-line range containment, TSX `style`/`css` capture). Each fix is test-driven and behavior-visible without a running language server.

## Constraints
- Lua; Neovim plugin, supports 0.10+; keep the existing lspconfig (0.10) and native (0.11+) setup paths.
- No new production dependencies.
- `config.options` stays the single source of truth; never read config at require time.
- Keep `tw` attribute capture in the TSX query (backward-compat with twin.macro-style usage); only drop `style` and `css`, which are inline CSS, not class lists.

## Out of Scope (deferred to a follow-up milestone)
- Multi-client/workspace client resolution (`get_tailwindcss` picks first client globally).
- `register_regex` force-merge wiping `settings.experimental.classRegex`; detach cleanup of `extension_timer`/`last_sent_inside`.
- Lua-pattern scan O(matches × lines) optimization; nil/empty-match robustness; `treesitter` inner-offset bounds checks.
- Telescope/cmp/rplugin hardening and `TailwindSortSelection` command-range handling.
- Dedicated unit specs for the dynamic `class_regex` feature.

## Verification Commands
- test (single spec): `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/<path>"`
- test (full): `nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/ { init='tests/init.lua' }"`
- lint: `luacheck .`
- format check: `stylua --check .` (stylua not installed locally; CI pins 2.1.0)

Branch: `fix/review-findings-2` (off `main`).

---

### Task 1: Conceal activates when `conceal.enabled = true` in config

Files:
- modify `lua/tailwind-tools/init.lua`
- modify `tests/conceal/conceal_spec.lua`

Steps:
1. Write test: in `tests/conceal/conceal_spec.lua`, add an `it` that calls `require("tailwind-tools").setup({ conceal = { enabled = true } })`, then `vim.cmd.edit("tests/queries/html/index.html")`, and asserts `get_extmarks(0, ns)` equals the same `{ { 10, 14, 10, 47 }, { 11, 16, 11, 39 } }` as the first spec, and that `#vim.api.nvim_get_autocmds({ group = vim.g.tailwind_tools.conceal_au }) > 0`. Clean up with `vim.cmd.TailwindConcealDisable()`.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/conceal/conceal_spec.lua"`; confirm the new test fails (0 extmarks, 0 autocmds).
3. Implement: in `M.setup` (`lua/tailwind-tools/init.lua`), after `register_autocmd()`, add `if state.conceal.enabled then conceal.enable() end`.
4. Run the single spec; confirm it passes.
5. Run the full test command; confirm no regression.

Done when: a config with `conceal = { enabled = true }` conceals loaded buffers at startup and registers the conceal autocmds exactly once.

---

### Task 2: `TailwindSort` / `TailwindSortSelection` use the async path

Files:
- modify `lua/tailwind-tools/init.lua`
- create `tests/sort_spec.lua`

Steps:
1. Write test: in `tests/sort_spec.lua`, stub `vim.lsp.get_clients` to return a fake client `{ request = function(_, m) request_method = m end, request_sync = function() sync_called = true end }`, `vim.cmd.edit("tests/queries/html/index.html")`, then `vim.cmd.TailwindSort()`. Assert `request_method == "@/tailwindCSS/sortSelection"` and `sync_called ~= true`.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/sort_spec.lua"`; confirm it fails (the command callback passes the opts table as `sync`, so `request_sync` runs instead).
3. Implement: in `register_usercmd` (`lua/tailwind-tools/init.lua`), wrap both callbacks — `usercmd("TailwindSort", function() lsp.sort_classes() end, ...)` and `usercmd("TailwindSortSelection", function() lsp.sort_selection() end, ...)`.
4. Run the single spec; confirm it passes.
5. Run the full test command; confirm no regression.

Done when: `TailwindSort` issues an async `client:request` and `TailwindSortSelection` no longer receives the options table as its `sync` argument.

---

### Task 3: Color hints stay disabled after `TailwindColorDisable`

Files:
- modify `lua/tailwind-tools/lsp.lua`
- create `tests/color_spec.lua`

Steps:
1. Write test: in `tests/color_spec.lua`, stub `vim.lsp.get_clients` to return a fake client whose `request` records calls, then:
   - `vim.cmd.TailwindColorDisable()`; record `vim.cmd("colorscheme vim")`; assert `request` was not called (the Colorscheme autocmd must not re-request).
   - `vim.cmd.TailwindColorEnable()`; assert `request` was called (enable must request after flipping state).
   Restore the original `vim.lsp.get_clients` and state at the end.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/color_spec.lua"`; confirm it fails (Colorscheme autocmd re-adds colors while disabled).
3. Implement in `lua/tailwind-tools/lsp.lua`:
   - Add `if not state.color.enabled then return end` at the top of `M.color_request` (after resolving `client`).
   - Reorder `M.enable_color` to set `state.color.enabled = true` before `M.color_request`.
   - In `M.disable_color`, cancel `state.color.request_timer` (stop/close and nil) so a pending debounce cannot re-add extmarks.
4. Run the single spec; confirm it passes.
5. Run the full test command; confirm no regression.

Done when: disabling colors survives a colorscheme change and a pending debounce, and enabling colors requests after the state is set.

---

### Task 4: Correct range containment for multi-line classes and same-line multiple ranges

Files:
- modify `lua/tailwind-tools/classes.lua`
- modify `lua/tailwind-tools/keymaps.lua`
- create `tests/queries/html/multiline.html`
- create `tests/multiline_spec.lua`
- create `tests/keymaps/multi.tsx`
- modify `tests/keymaps/increment_spec.lua`

Steps:
1. Write tests:
   - `tests/multiline_spec.lua`: create `tests/queries/html/multiline.html` with a `class="flex\n  items-center\n  p-4"` attribute; assert `classes.get_ranges(0)` returns `{ { 0, 12, 2, 5 } }`; place the cursor on line 2 (middle) and assert `classes.is_inside(0) == true`; also assert `false` for a row above the start and a row below the end.
   - `tests/keymaps/increment_spec.lua`: create `tests/keymaps/multi.tsx` containing `<div className="border-2" tw="border-4" />`; edit it, place the cursor on the digit of `border-4` (compute the column from `line:find("border-4")`), run `vim.cmd.TailwindIncrement()`, and assert the `tw` value becomes `border-6`.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/multiline_spec.lua"` and the increment spec; confirm both fail for the right reason (`is_inside` false on the middle line; `find_range_at_cursor` returns the first `className` range so increment falls back to `border-5`).
3. Implement:
   - `classes.is_inside` (`lua/tailwind-tools/classes.lua`): replace the single `(row >= s_row and row <= e_row) and (col >= s_col and col <= e_col)` check with line-aware logic — reject when `row == s_row and col < s_col`, or `row == e_row and col > e_col`; otherwise true when `row >= s_row and row <= e_row`.
   - `keymaps.find_range_at_cursor` (`lua/tailwind-tools/keymaps.lua`): keep both `row` and `col`, and return the range that actually contains the cursor (same line-aware containment), not the first range on the row.
4. Run both single specs; confirm they pass.
5. Run the full test command; confirm no regression.

Done when: multi-line class values report `inside` on middle lines, and smart increment targets the class under the cursor when two class ranges share a line.

---

### Task 5: TSX query excludes `style`/`css` attributes

Files:
- modify `queries/tsx/class.scm`
- modify `tests/queries/tsx/Component.tsx`
- modify `tests/queries/tsx_spec.lua`

Steps:
1. Write test: append `<div style="color: red" />` to `tests/queries/tsx/Component.tsx` (at the end, after `export default Component;`). Keep `tests/queries/tsx_spec.lua`'s expected three ranges unchanged.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/queries/tsx_spec.lua"`; confirm it fails (count becomes 4 because `style` is captured).
3. Implement: in `queries/tsx/class.scm`, change `(#any-of? @_attribute_name "class" "className" "style" "css" "tw")` to `(#any-of? @_attribute_name "class" "className" "tw")`.
4. Run the single spec; confirm it passes (count back to 3).
5. Run the full test command; confirm no regression.

Done when: `style`/`css` JSX attributes are not treated as Tailwind class ranges, while `class`/`className`/`tw` still are.

---

### Task 6: Full verification

Steps:
1. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/ { init='tests/init.lua' }"`; expect all non-LSP suites green (LSP v3/v4 suites still require `tailwindcss-language-server` on PATH and are expected to fail locally).
2. Run `luacheck .`; expect 0 warnings / 0 errors.
3. Run `stylua --check .` if stylua is available; otherwise rely on CI.
4. Review the diff for scope: only the files listed above changed.

Done when: new and existing non-LSP specs pass, lint is clean, and no changes leaked into deferred scope.
