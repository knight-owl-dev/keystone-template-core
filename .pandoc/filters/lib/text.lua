-- text.lua — Small string helpers shared across filters.
--
-- Pure standard Lua (no pandoc, no other libs), so it loads anywhere the loader
-- is installed — including standalone entry points that bootstrap the loader
-- themselves (epub-font-paths.lua).

local M = {}

--- Strip leading and trailing whitespace, returning the inner content.
---
--- The lazy capture `(.-)` matches as little as it can, so the trailing `%s*$`
--- consumes all end whitespace and the capture stops just before it; `^%s*`
--- eats the leading run. An all-whitespace (or empty) string trims to "".
---@param s string  the string to trim
---@return string   `s` with both ends stripped
function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- Levenshtein edit distance (insert / delete / substitute, unit cost), computed
-- with the standard two-row dynamic program. Compares by byte: callers here
-- match short ASCII identifiers (class names), where bytes and characters
-- coincide.
---@param a string  first string
---@param b string  second string
---@return integer  minimum single-character edits to turn `a` into `b`
local function levenshtein(a, b)
  local la, lb = #a, #b
  if la == 0 then return lb end
  if lb == 0 then return la end

  local prev = {}
  for j = 0, lb do prev[j] = j end

  for i = 1, la do
    local curr = { [0] = i }
    local ai = a:byte(i)
    for j = 1, lb do
      local sub = prev[j - 1] + (ai == b:byte(j) and 0 or 1)
      local del = prev[j] + 1
      local ins = curr[j - 1] + 1
      local best = sub
      if del < best then best = del end
      if ins < best then best = ins end
      curr[j] = best
    end
    prev = curr
  end

  return prev[lb]
end

-- A suggestion is only useful if it's plausibly the word the author meant; a
-- typo is a slip or two, not a different word. Two edits catches a transposition
-- (spelled as two substitutions) without suggesting unrelated names.
local NEAREST_MAX_DISTANCE = 2

--- The closest candidate to `word` by edit distance, for "did you mean …?"
--- hints. Returns nil when nothing is within NEAREST_MAX_DISTANCE. Ties break
--- lexicographically so the hint is deterministic — callers build the pool from
--- unordered table iteration, so first-scanned would vary run to run.
---@param word string           the unrecognized token
---@param candidates string[]    known names to match against
---@return string|nil            the nearest candidate, or nil if none is close
function M.nearest(word, candidates)
  local best, best_distance = nil, NEAREST_MAX_DISTANCE + 1
  for _, candidate in ipairs(candidates) do
    local d = levenshtein(word, candidate)
    if d < best_distance or (best and d == best_distance and candidate < best) then
      best, best_distance = candidate, d
    end
  end
  return best
end

return M
