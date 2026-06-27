---@diagnostic disable: param-type-mismatch
-- format-registry.lua — Single source of truth for output-format capabilities
--
-- Centralizes FORMAT resolution and capability queries so individual
-- filters never hardcode format:match() checks. Handlers declare
-- format-keyed hook tables; the registry owns all FORMAT resolution.
--
-- Exported functions:
--   resolve_key(format_obj)        → canonical format string
--   resolve_hook(hook_table, key)  → handler function or nil
--   uses_tex(format_key)           → boolean
--   uses_css(format_key)           → boolean
--   embeds_fonts(format_key)       → boolean

local lib = {}

-- Canonical format keys and per-format capability flags.
-- Single source of truth — resolve_key() iterates the keys,
-- uses_tex() / uses_css() / embeds_fonts() query the values.
-- Update when adding formats.
local FORMATS = {
  latex = { tex = true },
  epub  = { css = true, embed_fonts = true },
  html  = { css = true },
  docx  = {},  -- styles live in the reference doc; see docs/pandoc-integration/docx.md
  odt   = {},  -- styles live in the reference doc; see docs/pandoc-integration/odt.md
}

--- Normalize a Pandoc FORMAT object into a canonical key.
--- Called once at filter load time. Uses :match() so it works with both
--- real Pandoc FORMAT (a string with match via metamethod) and mock FORMAT
--- objects used in tests.
---@param format_obj table|string  Pandoc FORMAT global
---@return string  Canonical key ("latex", "epub", "html", "docx", "odt", or raw string)
function lib.resolve_key(format_obj)
  for fmt in pairs(FORMATS) do
    if format_obj:match(fmt) then return fmt end
  end
  local raw = tostring(format_obj)
  io.stderr:write("WARN: format '" .. raw
    .. "' is not officially supported — handler output may be missing or incorrect\n")
  return raw
end

--- Whether the format uses LaTeX preamble injection (macros.tex).
---@param format_key string  Canonical key from resolve_key()
---@return boolean
function lib.uses_tex(format_key)
  local s = FORMATS[format_key]
  return s ~= nil and s.tex == true
end

--- Whether the format uses CSS stylesheets (style.css).
---@param format_key string  Canonical key from resolve_key()
---@return boolean
function lib.uses_css(format_key)
  local s = FORMATS[format_key]
  return s ~= nil and s.css == true
end

--- Whether the format embeds font files into the output archive.
--- EPUB bundles .otf files and needs @font-face CSS; other CSS formats
--- (HTML) rely on system/web fonts and skip embedding.
---@param format_key string  Canonical key from resolve_key()
---@return boolean
function lib.embeds_fonts(format_key)
  local s = FORMATS[format_key]
  return s ~= nil and s.embed_fonts == true
end

--- Look up a handler function from a format-hook table.
--- Tries the exact format key first, then falls back to "default".
---@param hook_table table   { latex = fn, epub = fn, default = fn, ... }
---@param format_key string  Canonical key from resolve_key()
---@return function|nil  Handler function, or nil if no match
function lib.resolve_hook(hook_table, format_key)
  return hook_table[format_key] or hook_table["default"]
end

return lib
