local M = {}

---@param b_start number
---@param b_end number
---@param line_offsets number[]
local function byte_range_to_pos(b_start, b_end, line_offsets)
  local s_row, s_col, e_row, e_col

  local lo, hi = 1, #line_offsets
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local offset = line_offsets[mid]
    local next_offset = line_offsets[mid + 1]
    if b_start < offset then
      hi = mid - 1
    elseif next_offset and b_start >= next_offset then
      lo = mid + 1
    else
      s_row = mid - 1
      s_col = b_start - offset
      break
    end
  end

  lo, hi = 1, #line_offsets
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local offset = line_offsets[mid]
    local next_offset = line_offsets[mid + 1]
    if b_end < offset then
      hi = mid - 1
    elseif next_offset and b_end >= next_offset then
      lo = mid + 1
    else
      e_row = mid - 1
      e_col = b_end - offset
      break
    end
  end

  return s_row, s_col, e_row, e_col
end

---@param bufnr number
---@param pattern_definition string | { pattern: string, delimiter: string }
M.find_class_ranges = function(bufnr, pattern_definition)
  local results = {}

  local pattern
  local delimiter = nil
  if type(pattern_definition) == "table" then
    pattern = pattern_definition.pattern
    if pattern_definition.delimiter then
      delimiter = {
        raw = pattern_definition.delimiter,
        pattern = string.gsub(pattern_definition.delimiter, "%W", "%%%1"),
      }
    end
  else
    pattern = pattern_definition
  end

  if not pattern then return results end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local text = table.concat(lines, "\n")

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local line_offsets = {}
  for i = 1, line_count do
    line_offsets[i] = vim.api.nvim_buf_get_offset(bufnr, i - 1)
  end

  local init = 1
  while init <= #text + 1 do
    local b_start, b_end, class = text:find(pattern, init)

    if b_start == nil then break end
    if type(class) ~= "string" or #class == 0 then break end
    if b_end < init then break end

    local class_start = text:find(class, b_start, true)
    if not class_start then break end
    local class_end = class_start + #class - 1
    local s_row, s_col, e_row, e_col = byte_range_to_pos(class_start - 1, class_end, line_offsets)

    if s_row == nil or e_row == nil then break end

    results[#results + 1] = { s_row, s_col, e_row, e_col, delimiter = delimiter }
    init = b_end + 1
  end

  return results
end

return M
