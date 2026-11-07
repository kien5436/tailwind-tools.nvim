# Fix Review Findings Plan

## Goal
Remove dead code and duplication first (verify the plugin still works), then fix the correctness bugs, then modernize CI and docs.

## Constraints
- Lua; Neovim plugin, supports 0.9 → nightly, native lspconfig path for 0.11+.
- No new production dependencies.
- Keep `config.options` as the single source of truth; never read config at require time.
- Refactors in Milestone 1 must be behavior-preserving; correctness changes are deferred to Milestone 2.
- Test before implementation (RED → GREEN → refactor), per TDD.

## Out of Scope
- Rewriting the telescope v3-only `rplugin` JS resolver for v4 (defer; document the limitation only).
- Supporting Neovim 0.9 in CI beyond what is verified locally.
- Style-only churn beyond what the listed dead-code items require.

## Verification Commands
- test (full): `nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/ { init='tests/init.lua' }"`
- test (single): `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/<path>_spec.lua"`
- lint: `luacheck .`
- format check: `stylua --check .`

---

## Milestone 1 — Dead code & duplication (plugin must still work)

### Task 1: Remove unused symbols
Files:
- modify `lua/tailwind-tools/keymaps.lua` (delete `M.unset_smart_increment` at 191-199)
- modify `lua/tailwind-tools/log.lua` (delete `M.debug` at line 8)
- modify `lua/tailwind-tools/config.lua` (delete unused `capabilities` annotation at line 33)
- modify `lua/tailwind-tools/lsp.lua` (delete stray `---@module 'lspconfig.configs'` at line 129)

Steps:
1. Implement each deletion.
2. Run `luacheck .`; confirm 0 warnings.
3. Run full test command; confirm no regression.

Done when: `luacheck` clean, full suite passes, no unreferenced symbols remain.

Note: keep `lua/tailwind-tools/filetypes.lua:60` `M.get_all` — it is unused now but is the fix source for Task 6; do not delete it here.

### Task 2: Extract shared `build_conf`
Files:
- modify `lua/tailwind-tools/lsp.lua`

Steps:
1. Implement: extract `build_conf(server_config)` returning the shared `settings`/`includeLanguages`/`capabilities` object; have `M.setup` (lspconfig path) and `M.setup_native` (native path) call it, then each adds its own `on_attach`/`root_dir`/`filetypes`. Preserve current behavior exactly (no filetypes/root_dir change yet).
2. Run `luacheck .`.
3. Run full test command; confirm LSP specs still pass.

Done when: the two setup paths share one settings builder and the suite is green.

### Milestone 1 gate
- Run full test command and `luacheck .`. Only proceed to Milestone 2 once green — this proves dead-code removal and the refactor broke nothing.

---

## Milestone 2 — Correctness (blocks merge)

### Task 3: Read smart-increment units at call time
Files:
- modify `lua/tailwind-tools/keymaps.lua`
- modify `tests/keymaps/increment_spec.lua`

Steps:
1. Write test: `setup({ keymaps = { smart_increment = { enabled = true, units = { { prefix = "x", values = { "1", "2" } } } } } })`, place cursor on `x-1`, trigger increment, assert text becomes `x-2`.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/keymaps/increment_spec.lua"`; confirm it fails (still uses default size table).
3. Implement: read `config.options.keymaps.smart_increment.units` at the top of `M.set_smart_increment` (line 161) instead of the deleted module-level `local units` (former line 13).
4. Run single test; confirm pass.
5. Run full test command; confirm no regression.

Done when: custom `units` are honored after `setup()`.

### Task 4: Register conceal autocmds once, apply per buffer
Files:
- modify `lua/tailwind-tools/conceal.lua`
- modify `lua/tailwind-tools/init.lua`
- modify `tests/conceal/conceal_spec.lua`

Steps:
1. Write test: call `conceal.enable()` three times; assert the autocmd count in `vim.g.tailwind_tools.conceal_au` is constant (does not grow 1→4→7).
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/conceal/conceal_spec.lua"`; confirm it fails (count grows).
3. Implement: split `conceal.lua` — one-time registration of `TextChanged`/`TextChangedI`/`BufEnter` autocmds (guarded so they are not re-added), plus an `M.apply(bufnr)` that runs `set_conceal`. `BufEnter` callback calls `M.apply(args.buf)` instead of `enable()`. Update `init.lua:36-41` to call `conceal.apply` (or rely on the registered `BufEnter` handler) instead of `conceal.enable()`. Update `disable()` to clear the whole `conceal_au` group (or stop adding autocmds on enable).
4. Run single test; confirm pass.
5. Run full test command; confirm no regression.

Done when: repeated `enable()`/`disable()` cycles do not grow the autocmd group, and every loaded buffer still conceals.

### Task 5: Dedupe double `on_attach`
Files:
- modify `lua/tailwind-tools/lsp.lua`
- modify `lua/tailwind-tools/init.lua`
- modify `tests/lsp/lsp_v3_spec.lua` (and `tests/lsp/lsp_v4_spec.lua` if it asserts autocmd counts)

Steps:
1. Write test: after one LSP attach, assert the buffer has exactly one set of color autocmds (not two). Use `vim.api.nvim_get_autocmds({ group = vim.g.tailwind_tools.color_au, buffer = bufnr })` and count.
2. Run single test; confirm it fails (14 registered).
3. Implement: add a `(client.id, bufnr)` dedupe map in `lsp.lua` so `M.on_attach` runs once per client+buffer; filter `on_attach_cb` with `vim.lsp.get_clients({ bufnr = args.buf, name = "tailwindcss" })` and bail when none. Keep exactly one path that calls the user `on_attach`.
4. Run single test; confirm pass.
5. Run full test command; confirm no regression.

Done when: a real attach registers one set of autocmds and one color request per `documentColor` event.

### Task 6: Native setup sets filetypes and root_dir
Files:
- modify `lua/tailwind-tools/lsp.lua`

Steps:
1. Write test: on nvim-0.11 path, call `lsp.setup_native({})` then assert `vim.lsp.config.tailwindcss.filetypes` is non-nil/non-empty and `vim.lsp.config.tailwindcss.root_dir` (or `root_markers`) is set. Add to `tests/lsp/lsp_v4_spec.lua`.
2. Run single test; confirm it fails (`filetypes == nil`, `root_dir == nil`).
3. Implement: in `M.setup_native`, set `conf.filetypes = filetypes.get_all()` and provide a default `root_dir`/`root_markers` equivalent to `M.make_root_dir` (root files: `tailwind.config.{js,cjs,mjs,ts}`, plus the existing list). Reuse `M.make_root_dir`'s root_files list. This also resolves the `get_all` dead-code flag from Task 1's note.
4. Run single test; confirm pass.
5. Run full test command; confirm no regression.

Done when: native path does not attach to all filetypes and resolves a project root.

### Task 7: Guard nil/malformed sort response
Files:
- modify `lua/tailwind-tools/lsp.lua`

Steps:
1. Write test: call the `sort_classes` handler path with `result = nil` and with `result = { error = "x" }`; assert no error raised and no buffer edit. Add a spec under `tests/lsp/`.
2. Run single test; confirm it fails (indexes `result.error` before nil-check).
3. Implement: reorder `lua/tailwind-tools/lsp.lua:99-104` — `if not result or not vim.api.nvim_buf_is_valid(bufnr) then return end` first, then `if result.error then ...`, then guard `result.classLists` and `ranges[i]`.
4. Run single test; confirm pass.
5. Run full test command; confirm no regression.

Done when: nil/error results return cleanly without raising.

### Task 8: Fix per-buffer classRegex cache
Files:
- modify `lua/tailwind-tools/lsp.lua`

Steps:
1. Write test: with two buffers and a global `class_regex`, flip state in buffer B, return to buffer A, assert the server received the correct regex for A (track last registered regex). Also assert `extension_inside` is cleared on `BufDelete`. Add a spec under `tests/lsp/`.
2. Run single test; confirm it fails (early return at line 270 uses stale `inside`).
3. Implement: track the last globally sent regex state per client; re-register on `BufEnter`; clear `extension_inside[bufnr]` on `BufDelete`; guard the deferred timer callback with `vim.api.nvim_buf_is_valid(args.buf)`.
4. Run single test; confirm pass.
5. Run full test command; confirm no regression.

Done when: switching buffers re-registers the correct regex and stale per-buffer state is cleared.

---

## Milestone 3 — CI & docs

### Task 9: Modernize CI workflows
Files:
- modify `.github/workflows/test.yml`
- modify `.github/workflows/docs.yml`
- modify `.github/workflows/lint.yml`

Steps:
1. `test.yml`: bump `checkout@v4`, `setup-node@v4` with `node-version: 22`, pin `@tailwindcss/language-server` and `neovim` versions, replace `npm install` with `npm ci`, add a `0.10` matrix entry (0.9 if still supported) to match README's 0.9+ promise.
2. `docs.yml`: bump `checkout@v4`, pin `kdheepak/panvimdoc` to a tag, pin `git-auto-commit-action` (e.g. `@v5`), update `version` to current Neovim.
3. `lint.yml`: pin `JohnnyMorganz/stylua-action` and set a fixed `version` (match `.stylua.toml`).
4. Regenerate `doc/tailwind-tools.nvim.txt` locally and commit alongside.

Done when: workflows use pinned/current actions, and the matrix covers the documented minimum Neovim.

### Task 10: Fix README/doc drift
Files:
- modify `README.md`
- modify `doc/tailwind-tools.nvim.txt` (via panvimdoc regen)

Steps:
1. Fix `lua/tailwind/units.lua` → `lua/tailwind-tools/units.lua` (`README.md:117`).
2. Add `TailwindIncrement`/`TailwindDecrement` and the `Sync` commands to the command list (`README.md:147-158`).
3. Add a v3-only caveat to the telescope utilities section (`README.md:196-202`).
4. Note `tailwind.config.mjs` lookup parity in the JS resolver or document the gap.
5. Regenerate vimdoc and confirm no stale "2025 May 22" header.

Done when: README matches `init.lua` user commands and file paths, and vimdoc is regenerated.

### Task 11: Fix test fixtures
Files:
- modify `tests/lsp/v4/vite.config.js` (remove `@vitejs/plugin-react` import/plugin or add the dep to `tests/lsp/v4/package.json`)
- modify `tests/parsers.lua` (derive from `filetypes.get_all()` or document the intentional subset)

Steps:
1. Fix the vite fixture so `npm run dev/build` succeeds.
2. Derive `tests/parsers.lua` from `filetypes.get_all()` (minus non-treesitter entries) or add a comment explaining the subset.
3. Run the LSP specs and `npm run build` in `tests/lsp/v4`.

Done when: v4 fixture builds and parser list no longer silently drifts.

---

## Final
- Run full suite: `nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/ { init='tests/init.lua' }"`
- Run `luacheck .` and `stylua --check .`
- Report output; do not merge or delete the branch.
