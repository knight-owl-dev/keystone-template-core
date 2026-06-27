-- Includes ::: ifdef divs and [content]{.ifdef} spans when one of the
-- requested build symbols is defined; strips them otherwise. Symbols come
-- from the selected build configuration (publish.sh resolves it into
-- KEYSTONE_DEFINED_SYMBOLS). See README.md for usage.

local symbols = ks_require("symbols")

-- The active symbol set is stable for the whole build — resolve it once.
local defined = symbols.parse(os.getenv("KEYSTONE_DEFINED_SYMBOLS") or "")

-- Keep (unwrap — content preserved, wrapper stripped) when any requested
-- symbol is defined; otherwise drop the content entirely.
local function gate(el)
  if symbols.evaluate(el.attributes.symbol, defined) then
    return el.content
  end
  return {}
end

return {
  div = { default = gate },
  span = { default = gate },
}
