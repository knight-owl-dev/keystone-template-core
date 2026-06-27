-- symbols.lua — Build-symbol set parsing and ifdef/ifndef evaluation
--
-- publish.sh resolves the selected build configuration into a flat,
-- whitespace-separated symbol set and exports it as KEYSTONE_DEFINED_SYMBOLS.
-- The ifdef/ifndef handlers consume that set through this module:
--   parse()    — turn the env string into a membership set
--   evaluate() — does an element's `symbol=` attribute match the set? (OR)
--
-- "Defined" follows C #ifdef semantics: a symbol absent from the set is simply
-- false — there is no separate "declared" vocabulary at the symbol level, so a
-- typo just gates to nothing. A missing/blank `symbol=` attribute is different:
-- a bare `::: ifdef` gates nothing and almost certainly signals a mistake, so
-- evaluate() raises rather than silently passing.

local lib = {}

-- The single place that knows symbols are whitespace-separated. Both the
-- defined set (parse) and an element's `symbol=` attribute (evaluate) are the
-- same shape — one symbol list — so they tokenize through here to stay in
-- lockstep. nil-safe: iterates nothing for a nil/empty string.
local function each_symbol(str)
  return (str or ""):gmatch("%S+")
end

--- Parse a whitespace-separated symbol string into a membership set.
---@param str string|nil  e.g. "latex personal drafts" (nil/empty → empty set)
---@return table  { symbol = true, ... }
function lib.parse(str)
  local set = {}
  for sym in each_symbol(str) do
    set[sym] = true
  end
  return set
end

--- Evaluate an element's `symbol=` attribute against the defined set.
--- Multiple symbols are OR-combined: true when ANY of them is defined.
--- Errors when the attribute is missing or blank — a bare ifdef/ifndef gates
--- nothing, so we surface the authoring mistake instead of swallowing it.
---@param symbol_attr string|nil  the element's `symbol` attribute value
---@param defined table           membership set from parse()
---@return boolean
function lib.evaluate(symbol_attr, defined)
  if not symbol_attr or not symbol_attr:match("%S") then
    error("ifdef/ifndef requires a non-empty 'symbol' attribute")
  end
  for sym in each_symbol(symbol_attr) do
    if defined[sym] then
      return true
    end
  end
  return false
end

return lib
