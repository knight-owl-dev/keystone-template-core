-- handler-namespace.lua — Resolve handler names across the ks- namespace
--
-- The ks- prefix provides unambiguous access to built-in handler classes.
-- System shortcuts shadow every handler name (e.g. "font" is a shortcut
-- that routes to ks-font). The ks- prefix always reaches the handler
-- directly, bypassing shortcut resolution.
--
-- This library centralizes name resolution so consumers never inline the
-- prefix pattern.

local PREFIX = "ks%-"
local PREFIX_LITERAL = "ks-"

local lib = {}

--- Strip the ks- prefix from a class name, returning the canonical handler name.
--- Returns the name unchanged if no prefix is present.
---@param name string  A class name, possibly ks-prefixed
---@return string      The canonical (bare) handler name
function lib.canonical(name)
  return name:match("^" .. PREFIX .. "(.+)$") or name
end

--- Check whether a name uses the reserved ks- prefix.
---@param name string
---@return boolean
function lib.is_reserved(name)
  return name:sub(1, #PREFIX_LITERAL) == PREFIX_LITERAL
end

return lib
