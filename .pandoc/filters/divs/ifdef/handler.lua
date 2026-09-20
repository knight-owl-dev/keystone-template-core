-- Includes ::: ifdef divs and [content]{.ifdef} spans when one of the
-- requested build symbols is defined; strips them otherwise. Symbols come
-- from the selected build configuration (publish.sh resolves it into
-- KEYSTONE_DEFINED_SYMBOLS). See README.md for usage.

local kast = ks_require("ast")
local symbols = ks_require("symbols")
local env_io = ks_require("env-io")

-- The active symbol set is stable for the whole build — resolve it once.
local defined = symbols.parse(env_io.optional_env("KEYSTONE_DEFINED_SYMBOLS") or "")

-- Keep (unwrap — content preserved, wrapper stripped) when any requested
-- symbol is defined; otherwise drop the content entirely.
local function gate(el, report)
  if symbols.evaluate(el.attributes["symbol"], defined, report) then
    return el.content
  end
  return kast.Remove()
end

return {
  div = { default = gate },
  span = { default = gate },
}
