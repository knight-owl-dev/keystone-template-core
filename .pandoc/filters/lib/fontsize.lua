-- fontsize.lua — Curated LaTeX base font sizes, keyed by target class family.
--
-- `fontsize` is a raw Pandoc passthrough into \documentclass[<size>]{...}, and
-- both class families fail silently on an unsupported size:
--   * standard classes (book/report/article) accept only 10/11/12pt as a class
--     option and drop anything else to their 10pt default;
--   * KOMA classes (scr*) honor an arbitrary size, so an absurd value renders
--     and breaks typearea layout.
-- Each target yaml declares which set it allows via `keystone-fontsize-set`;
-- keystone.lua enforces membership and substitutes a fallback.
--
-- Sets are named so the six target yamls reference one by id rather than each
-- inlining — and independently drifting — the same array. Each set is a record:
-- its allowed `sizes` (ascending) and an optional `hint` for when the author's
-- size misses, so the enforcing filter stays generic over the set. `default` is
-- the fallback for an unparseable size and must be a member of every set.

local M = {}

M.sets = {
  -- Standard classes: the only sizes LaTeX honors as a class option.
  standard = {
    sizes = { "10pt", "11pt", "12pt" },
    hint = "For a larger base size, switch to a KOMA target — see"
      .. " https://keystone.knight-owl.dev/configuration/targets/#base-font-size",
  },
  -- KOMA classes: the standard sizes plus the conventional larger steps
  -- 14/17/20pt — 20pt is a sane ceiling for body text. 13pt fills the 12→14 gap
  -- so the common low range is contiguous. No hint: already the widest set.
  koma = {
    sizes = { "10pt", "11pt", "12pt", "13pt", "14pt", "17pt", "20pt" },
  },
}

M.default = "11pt"

--- The sizes a declared id allows, or nil for an unknown id.
---@param id string  a `keystone-fontsize-set` value
---@return table|nil  the ascending list of allowed sizes, or nil
function M.sizes(id)
  local set = M.sets[id]
  return set and set.sizes
end

--- Guidance shown when an author's size misses this set (e.g. where larger
--- sizes live), or nil when the set offers none. Lets the enforcing filter
--- append set-specific advice without knowing which set it is.
---@param id string  a `keystone-fontsize-set` value
---@return string|nil
function M.hint(id)
  local set = M.sets[id]
  return set and set.hint
end

--- True when `id` names a declared set. Distinct from is_allowed (which tests a
--- size against a set): this tests the set identifier itself — the target
--- contract — so a false here is a wiring bug, not an author mistake.
---@param id string  a `keystone-fontsize-set` value
---@return boolean
function M.is_valid(id)
  return M.sets[id] ~= nil
end

--- Sorted list of declared set ids, for diagnostics.
---@return table  set id strings, ascending
function M.ids()
  local ids = {}
  for id in pairs(M.sets) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

--- True when `value` is exactly a member of `sizes`. Match is exact-string, not
--- numeric — the author's literal string is what reaches \documentclass, so
--- "12.0pt" is not "12pt" (it falls through to the nearest allowed size).
---@param sizes table  list of allowed `<n>pt` sizes
---@param value string a stringified `fontsize` value
---@return boolean
function M.is_allowed(sizes, value)
  for _, size in ipairs(sizes) do
    if size == value then return true end
  end
  return false
end

--- Parse a size to its numeric points, or nil for a wrong unit or non-numeric
--- garbage. Accepts a bare `12` as well as `12pt` — unquoted `fontsize: 12`
--- reads as the integer 12, a common slip. The caller reads nil as "malformed"
--- (fall back to `default`) and a returned number as one to check against the
--- set (out of set → nearest).
---@param size string  a stringified `fontsize` value
---@return number|nil  the size in points, or nil if unparseable
function M.points(size)
  local n = size:match("^%s*(%d+%.?%d*)%s*pt%s*$")
    or size:match("^%s*(%d+%.?%d*)%s*$")
  return n and tonumber(n) or nil
end

--- The member of `sizes` nearest to `value` points by absolute distance; ties
--- resolve to the smaller size (layout-safe). Order-independent — does not rely
--- on the list being sorted. `sizes` is non-empty (every declared set is).
---@param sizes table  list of `<n>pt` sizes
---@param value number target size in points
---@return string      the nearest allowed size
function M.nearest(sizes, value)
  local best, best_dist
  for _, size in ipairs(sizes) do
    local pts = M.points(size)
    local dist = math.abs(pts - value)
    if not best_dist or dist < best_dist
        or (dist == best_dist and pts < M.points(best)) then
      best, best_dist = size, dist
    end
  end
  return best
end

return M
