-- collections.lua — Table/collection helpers shared across filters.
--
-- Pure standard Lua (no pandoc, no other libs), so it loads anywhere the loader
-- is installed, including standalone entry points that bootstrap it themselves.

local M = {}

--- A map's keys as an ascending-sorted array, for deterministic emission.
--- Keys must be mutually comparable; mixed types raise table.sort's ordering error.
---@param t table       map whose keys to sort
---@return table        keys in ascending order
function M.sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

--- Iterate a map's entries in sorted-key order, for a call site that reads as
--- the algorithm rather than the collect / sort / ipairs scaffold. Sites that
--- need the keys as an array (a length check, a concat) want sorted_keys instead.
---@param t table       map to iterate
---@return function     iterator yielding each key, value in ascending key order
function M.sorted_pairs(t)
  local keys = M.sorted_keys(t)
  local i = 0
  return function()
    i = i + 1
    local k = keys[i]
    if k ~= nil then return k, t[k] end
  end
end

return M
