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

--- One line naming a longer text, for an error that has to say which input it
--- is about.
---
--- Whitespace collapses to single spaces, so a block spanning lines reads as
--- one phrase and a message stays one line however the input was laid out.
--- `limit` counts characters rather than bytes, and the cut lands on a
--- character boundary; text the host cannot measure as UTF-8 is returned whole
--- rather than sliced into something worse than the original.
---@param s string       the text to name
---@param limit integer  characters to keep before the ellipsis
---@return string        one line, at most `limit` characters plus the ellipsis;
---                     text this cannot measure comes back whole
function M.excerpt(s, limit)
  local flat = M.trim((s:gsub("%s+", " ")))

  local length = utf8.len(flat)
  if not length or length <= limit then return flat end

  return flat:sub(1, utf8.offset(flat, limit + 1) - 1) .. "…"
end

--- Width in columns, for laying text out rather than slicing it.
---
--- Characters, not bytes: an em dash or a check mark is one column and three
--- bytes, so byte counting pads and wraps them wrong.
---
--- Text the host cannot measure as UTF-8 falls back to counting the bytes that
--- are not continuations, which is what the shell renderer counts throughout —
--- so a string neither can read still breaks in the same place in both.
---@param s string   the text to measure
---@return integer   columns it occupies
function M.columns(s)
  local length = utf8.len(s)
  if length then return length end
  local _, continuations = s:gsub("[\128-\191]", "")
  return #s - continuations
end

--- Wrap text to a column budget, breaking only between words.
---
--- `first` prefixes the opening line and `rest` every continuation, so one call
--- produces a hanging indent (`rest` deeper than `first`) or a flat block (both
--- the same). Both prefixes count against `width`.
---
--- A word wider than the budget takes a line of its own rather than being split
--- — a URL or a path broken mid-token is worse than an overlong line.
---@param s string        the text to wrap; interior whitespace is normalized
---@param width integer   columns a line may occupy, prefix included
---@param first string    prefix for the first line
---@param rest string     prefix for every line after it
---@return string[]       complete lines, each carrying its own prefix
function M.wrap(s, width, first, rest)
  local lines, prefix = {}, first
  local line, filled

  for word in s:gmatch("%S+") do
    if not line then
      line, filled = prefix .. word, M.columns(prefix) + M.columns(word)
    elseif filled + 1 + M.columns(word) <= width then
      line, filled = line .. " " .. word, filled + 1 + M.columns(word)
    else
      lines[#lines + 1], prefix = line, rest
      line, filled = prefix .. word, M.columns(prefix) + M.columns(word)
    end
  end
  if line then lines[#lines + 1] = line end

  return lines
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

--- The closest candidate to `word` by edit distance, for the closest-match
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
