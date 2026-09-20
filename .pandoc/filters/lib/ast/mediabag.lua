-- ast/mediabag.lua — The document's resource store. Part of KAST; see
-- https://keystone.knight-owl.dev/engine/kast/
--
-- Pandoc resolves an Image src against this store before it looks at the
-- filesystem, and writes each entry out during conversion — into the EPUB
-- archive, the DOCX package, or the temporary directory the PDF engine reads.
-- So a filter can supply an asset that exists as no file, and every writer
-- still receives it.

-- type/subtype, each from RFC 6838's restricted name characters. Deliberately
-- excludes the comma and semicolon that structure a data URI.
local MEDIA_TYPE = "^[%w!#%$&%^_%.%+%-]+/[%w!#%$&%^_%.%+%-]+$"

local M = {}

--- Store an asset, replacing whatever was under `name`.
---
--- `name` is the string an Image src must carry to resolve here — a lookup key,
--- not a path. Nothing is written beside the manuscript.
---@param name string        key an Image src will reference
---@param media_type string  MIME type, e.g. "image/svg+xml"
---@param contents string    raw bytes
function M.insert(name, media_type, contents)
  pandoc.mediabag.insert(name, media_type, contents)
end

--- Decode base64 `data` into bytes.
---
--- Neither Lua nor the rest of the Pandoc API offers a base64 decoder. The
--- store's data-URI read is the only one within reach, so that is what this
--- is: a fetch of a URI assembled here rather than found in a document.
---
--- Anything that does not yield bytes returns nil, including data that is empty
--- or all padding. The underlying read keeps whatever looks like base64 and
--- drops the rest, so garbage would otherwise decode to a short run of
--- plausible bytes — or to none at all — and reach the book as a corrupt
--- asset. The check belongs to the decoder rather than to each caller.
---@param media_type string  MIME type the bytes carry
---@param data string        base64 text
---@return string|nil        the bytes, or nil when it cannot be decoded
function M.decode(media_type, data)
  -- The media type is interpolated into the URI, so a comma in it would end
  -- the header and make the rest of the URI the payload.
  if not media_type:match(MEDIA_TYPE) then return nil end

  -- Whitespace is legal on a wire and dropped; everything after that must be
  -- base64 with its padding at the end, where the decoder treats "=" as the
  -- terminator. Two chunks each padded and concatenated would otherwise decode
  -- to the first chunk alone, and be embedded as a truncated asset.
  local body = data:gsub("%s", "")
  local core, padding = body:match("^([A-Za-z0-9+/]*)(=*)$")
  if not core or #padding > 2 then return nil end
  if #core % 4 == 1 then return nil end

  local _, bytes = pandoc.mediabag.fetch("data:" .. media_type .. ";base64," .. body)
  if bytes == "" then return nil end
  return bytes
end

--- Retrieve a stored asset, or nothing when `name` holds none.
---@param name string  the key it was stored under
---@return string|nil media_type
---@return string|nil contents
function M.lookup(name)
  return pandoc.mediabag.lookup(name)
end

return M
