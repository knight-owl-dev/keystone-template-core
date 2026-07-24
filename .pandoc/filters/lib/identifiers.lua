-- identifiers.lua — Generate a name unique within a set, disambiguating a
-- collision with a sequencing suffix.
--
-- Pure standard Lua (no pandoc, no other libs), so it loads anywhere the loader
-- is installed. Domain-agnostic: the caller supplies the base name and the set.

local M = {}

--- Base-26 letter suffix: 1→a, 26→z, 27→aa, 28→ab, … Letters only, unbounded,
--- and bijective (no zero digit, unlike plain base-26), so every index maps to a
--- distinct non-empty suffix.
---@param n integer  1-based index
---@return string  letter suffix
function M.letter_suffix(n)
  local s = ""
  while n > 0 do
    n = n - 1
    s = string.char(97 + n % 26) .. s
    n = math.floor(n / 26)
  end
  return s
end

--- Reserve and return a unique variant of `base` within `seen`: `base` if free,
--- otherwise `base` .. suffix_fn(1), (2), … until one is unused. The result is
--- added to `seen` so successive calls never repeat. suffix_fn defaults to
--- letter_suffix.
---@param seen table<string, any>  set of already-claimed names (mutated)
---@param base string              desired name
---@param suffix_fn? fun(n: integer): string  collision-suffix generator
---@return string  the reserved unique name
function M.make_unique(seen, base, suffix_fn)
  suffix_fn = suffix_fn or M.letter_suffix
  local name, n = base, 0
  while seen[name] do
    n = n + 1
    name = base .. suffix_fn(n)
  end
  seen[name] = true
  return name
end

return M
