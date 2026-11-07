# Fix Review Findings (Deferred / Milestone 2) Plan

## Goal
Fix the findings deferred from `2026-11-07-fix-review-findings-2.md`: buffer-specific LSP client resolution, dynamic `class_regex` correctness and detach cleanup, command-range handling for sort-selection, Lua-pattern/treesitter robustness and performance, and telescope/cmp/rplugin hardening. Each fix is test-driven; most are verifiable without a running language server (multi-client is verified by stubbing `vim.lsp.get_clients`).

## Constraints
- Lua; Neovim 0.10+; preserve lspconfig (0.10) and native (0.11+) setup paths.
- No new production dependencies.
- `config.options` stays the single source of truth.
- Keep `tw` attribute capture (from round-2 plan); do not change query semantics beyond the anchoring fix below.

## Out of Scope
- Any item already completed in round 2 (conceal startup, sort async, color disable, containment, TSX `style`/`css`).
- Feature requests or new language support.

## Verification Commands
- test (single spec): `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/<path>"`
- test (full): `nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/ { init='tests/init.lua' }"`
- lint: `luacheck .`
- format check: `stylua --check .` (stylua not installed locally; CI pins 2.1.0)

Branch: `fix/review-findings-3` (off `main`, after round-2 lands).

---

## Milestone A — LSP client correctness

### Task A1: Resolve the tailwindcss client per buffer

Files:
- modify `lua/tailwind-tools/lsp.lua`

Steps:
1. Write test: add to `tests/sort_spec.lua` (or a new `tests/client_spec.lua`) a spec that stubs `vim.lsp.get_clients` to return client `A` for bufnr 1 and client `B` for bufnr 2 (filter on the `name == "tailwindcss"` and the passed `bufnr`). Open two HTML buffers, run `TailwindSort` in each, and assert each buffer's sort request reached its own client (record `self.id` in the fake `request`).
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/client_spec.lua"`; confirm it fails (both requests go to client A because `get_tailwindcss()` returns the first global client).
3. Implement: change `get_tailwindcss()` (`lua/tailwind-tools/lsp.lua:24-29`) to accept an optional `bufnr` and call `vim.lsp.get_clients({ bufnr = bufnr or 0, name = "tailwindcss" })[1]`. Update call sites: `sort_classes` (pass `bufnr`), `enable_color`/`color_request` (pass the buffer they operate on), and `register_regex` (accept a `client` argument rather than re-fetching).
4. Run the single spec; confirm it passes.
5. Run the full test command; confirm no regression.

Done when: sorting, color requests, and regex registration target the client attached to the buffer being edited, not the first client globally.

---

### Task A2: `class_regex` registration correctness and detach cleanup

Files:
- modify `lua/tailwind-tools/lsp.lua`

Steps:
1. Write test: extend `tests/client_spec.lua` to stub `client.settings`, call `M.register_regex(regex)` on a fake client, and assert the update merges only the `experimental.classRegex` key without wiping pre-existing `experimental.other`. Assert `on_detach_cb` clears `extension_timer` and `last_sent_inside` (set them first, fire detach, then assert nil).
2. Run the single spec; confirm it fails (`deep_extend("force", ...)` clobbers unrelated settings; `on_detach_cb` leaves timer/state).
3. Implement in `lua/tailwind-tools/lsp.lua`:
   - `register_regex` (`:132-148`): use a `vim.tbl_deep_extend("force", client.settings, { tailwindCSS = { experimental = { classRegex = regex } } })` that preserves sibling keys, or set `classRegex` on the existing table directly instead of force-merging the whole `experimental` block.
   - Track `last_sent_inside` per client id (map `client.id -> state`) instead of one module-global (`:264`).
   - `on_detach_cb` (`:254-259`): cancel/clear `extension_timer` and the per-client `last_sent_inside` entry, in addition to `attached` and `extension_inside`.
4. Run the single spec; confirm it passes.
5. Run the full test command; confirm no regression.

Done when: unrelated server settings survive regex toggling, and detaching a client leaves no stale timer or last-sent state.

---

### Task A3: Unit specs for the dynamic `class_regex` state machine

Files:
- create `tests/extension_spec.lua`

Steps:
1. Write test: stub `vim.lsp.get_clients` and `classes.is_inside` (or use the html multiline fixture from round 2) to exercise: entering a class range registers `config.options.server.class_regex`; leaving it registers `{}`; returning to a buffer re-registers based on `last_sent_inside`; `BufDelete` clears `extension_inside`. Assert the exact regex sequence sent to the (stubbed) client.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/extension_spec.lua"`; confirm it passes only after A1/A2 are in place (it encodes the fixed behavior).
3. Implement: no production change expected here beyond any needed to make `send_extension_state`/`on_attach` testable (e.g. passing `client` explicitly). Adjust as needed.
4. Run the single spec; confirm it passes.
5. Run the full test command; confirm no regression.

Done when: the `class_regex` enter/leave/return/delete transitions are covered by tests and green.

---

### Task A4: `TailwindSortSelection` honors the command range

Files:
- modify `lua/tailwind-tools/init.lua`
- modify `lua/tailwind-tools/lsp.lua`
- modify `tests/sort_spec.lua`

Steps:
1. Write test: in `tests/sort_spec.lua`, stub `vim.lsp.get_clients` and run `vim.cmd.TailwindSortSelection()` with no prior visual selection; assert no request is sent and no error is raised. Then set `'<`/`'>` via `vim.cmd.normal({ args = { "viw<Esc>" } })` on a word and assert the request is sent with the selected range.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/sort_spec.lua"`; confirm it fails (no-selection currently sends stale marks).
3. Implement:
   - `lua/tailwind-tools/init.lua`: change `TailwindSortSelection` to `range = true` and pass `args` to the callback.
   - `lua/tailwind-tools/lsp.lua` `M.sort_selection` (`:409-415`): when the visual marks are unset/empty (detect `line("'<") == 0`), fall back to `args.line1`/`args.line2` for a line-wise range, and return with a `log.info("No selection")` if that range is empty. Prefer the marks when present.
4. Run the single spec; confirm it passes.
5. Run the full test command; confirm no regression.

Done when: `TailwindSortSelection` no longer sorts stale marks when no selection exists, and still sorts the visual selection when marks are set.

---

## Milestone B — Extraction robustness & performance

### Task B1: Lua-pattern scan performance and robustness

Files:
- modify `lua/tailwind-tools/patterns.lua`
- create `tests/patterns_spec.lua`

Steps:
1. Write test: in `tests/patterns_spec.lua`, build a buffer with ~300 `class: "..."` matches over ~3000 lines and assert `find_class_ranges` returns 300 ranges and completes; add a case with a pattern that has no capture group and a pattern that can match empty, asserting both return gracefully (no error, no infinite loop).
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/patterns_spec.lua"`; confirm it fails (nil capture raises; a zero-length match does not advance).
3. Implement in `lua/tailwind-tools/patterns.lua`:
   - Precompute `line_offsets` once per buffer in `find_class_ranges` and pass them to `byte_range_to_pos` (remove the per-match O(lines) rebuild in `:6-32`).
   - Track a start index and use `string.find(pattern, init)` instead of re-slicing `substr` each iteration (`:64,:73`).
   - Guard: if `class` is nil, skip/continue; if `match_len <= 0`, advance the search index by at least 1 to guarantee progress.
4. Run the single spec; confirm it passes (and is measurably faster for the 300-match case).
5. Run the full test command; confirm no regression.

Done when: the pattern scan is O(lines + matches) instead of O(lines × matches), and malformed/zero-width patterns cannot error or loop.

---

### Task B2: Treesitter inner-offset bounds checks

Files:
- modify `lua/tailwind-tools/treesitter.lua`
- modify `tests/queries/filters_spec.lua`

Steps:
1. Write test: in `tests/queries/filters_spec.lua`, add a capture using a query whose `#set!` `start`/`end` exceed the node's named-children count; assert `get_class_range` returns the raw node range (or skips) without raising.
2. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedFile tests/queries/filters_spec.lua"`; confirm it fails (indexing `children[m_start + 1]`/`children[#children - m_end]` throws).
3. Implement in `lua/tailwind-tools/treesitter.lua` `get_class_range` (`:15-28`): clamp `m_start`/`m_end` so `m_start + 1 <= #children` and `#children - m_end >= 1`; if the adjusted indices are out of range, fall back to the node's full range.
4. Run the single spec; confirm it passes.
5. Run the full test command; confirm no regression.

Done when: malformed custom-query offsets degrade to the full node range instead of erroring.

---

## Milestone C — Integration & minors

### Task C1: Telescope/cmp/rplugin hardening

Files:
- modify `lua/telescope/_extensions/tailwind.lua`
- modify `lua/tailwind-tools/rplugin.lua`
- modify `lua/tailwind-tools/cmp.lua`

Steps:
1. Write test: none required for headless Telescope UI; instead verify by `require("tailwind-tools.rplugin")` with the remote plugin unregistered — assert `get_utilities`/`expand_utilities` return nil rather than raising E117 (wrap in `pcall`). Confirm `cmp.lspkind_format` returns `vim_item` unchanged when `doc` is missing.
2. Run `nvim --headless -u tests/init.lua -c "lua assert(require('tailwind-tools.rplugin').get_utilities() == nil)"` and the cmp call; confirm the rplugin assertion fails before the change.
3. Implement:
   - `rplugin.lua`: wrap `vim.fn.TailwindExpandUtilities`/`TailwindGetUtilities` in `pcall` and return nil on failure (keep `nil_wrap`).
   - `telescope.lua`: anchor `get_hl_kind` prefix matches to word boundaries (`:17-23`), flatten multi-line class text for `display` (`:99-136`), and `pcall` the rplugin calls so missing remote plugin/project notifies instead of throwing.
4. Re-run the assertions; confirm they pass.
5. Run the full test command; confirm no regression.

Done when: invoking telescope utilities or cmp formatting without the remote plugin/project fails softly.

---

### Task C2: Conceal, enable_color, native root, and setup-idempotence nits

Files:
- modify `lua/tailwind-tools/conceal.lua`
- modify `lua/tailwind-tools/lsp.lua`
- modify `lua/tailwind-tools/init.lua`
- modify `queries/javascript/class.scm`

Steps:
1. Write tests (each small, in the relevant existing spec):
   - `tests/conceal/conceal_spec.lua`: assert `conceallevel` is reset on disable in a second window showing the same buffer; assert `conceal.enable()` then `color_request` observes `state.conceal.enabled == true`.
   - `tests/color_spec.lua`: assert `TailwindColorEnable` sets `state.color.enabled = true` even when no client is attached.
   - `tests/queries/javascript_spec.lua`: assert an identifier containing `css`/`clsx` as a substring (e.g. `miscss(...)`) is not captured.
2. Run each single spec; confirm the relevant assertion fails before its fix.
3. Implement:
   - `conceal.lua`: set `state.conceal.enabled` before calling `lsp.color_request` in `enable`/`disable` (`:68-71,:85-88`); on disable, reset `conceallevel` for every window showing the buffer via `vim.api.nvim_win_call`/`nvim_set_option_value` (`:74-76`).
   - `lsp.lua` `enable_color`: set `state.color.enabled = true` before the client guard so enabling persists until the LSP attaches.
   - `lsp.lua` native root markers (`:190-199`): only add `package.json` when it declares a `tailwindcss` dependency (mirror the lspconfig path) or omit it; do not attach to arbitrary JS projects.
   - `init.lua` `setup`: reset the module-level `attached` map when augroups are recreated so a second `setup()` re-registers color autocmds.
   - `queries/javascript/class.scm`: anchor `#match?` to `^(clsx|classnames|t[vw]|css|cva)$`.
4. Re-run each single spec; confirm all pass.
5. Run the full test command and `luacheck .`; confirm no regression.

Done when: the five nits above are fixed and covered.

---

### Task C3: Full verification

Steps:
1. Run `nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/ { init='tests/init.lua' }"`; expect all non-LSP suites green (LSP v3/v4 still require `tailwindcss-language-server` on PATH and are expected to fail locally).
2. Run `luacheck .`; expect 0 warnings / 0 errors.
3. Run `stylua --check .` if stylua is available; otherwise rely on CI.
4. Review the diff for scope: only files listed above changed.

Done when: new and existing non-LSP specs pass, lint is clean, and no changes leaked outside the deferred scope.
