-- json.lua — The engine's one JSON codec.
--
-- Wherever the engine writes structured data for something outside itself to
-- read — a hook on the other end of a socket, a cache entry a later run picks
-- up — it is this shape. Keeping the codec in one place is what keeps those
-- readers agreeing; two would be two things to hold in step.
--
-- This is only the encoding. What the fields mean belongs to whoever chose
-- them: hook-protocol/ for a request on the wire, hook-cache for an entry.

local M = {}

--- Encode a value as JSON.
---@param value any
---@return string
function M.encode(value)
  return pandoc.json.encode(value)
end

--- Decode JSON.
---
--- Returns whatever the text held, which need not be an object — a caller that
--- requires one checks, rather than this pretending the input was well formed.
---@param text string
---@return any
function M.decode(text)
  return pandoc.json.decode(text)
end

--- Whether a decoded value is JSON null.
---
--- Null decodes to a sentinel rather than to nil, so a key set to one arrives
--- present. Every `~= nil` test over a decoded object is wrong without this. A
--- serializer writing each optional field it had no value for is the ordinary
--- way such an object is built.
---@param value any
---@return boolean
function M.is_null(value)
  -- By type, not by identity: the sentinel is the decoder's to choose, and
  -- nothing else in a decoded document is userdata.
  return type(value) == "userdata"
end

return M
