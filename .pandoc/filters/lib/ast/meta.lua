-- ast/meta.lua — Pandoc Meta inspection and the two metadata-mutation idioms.
-- Part of KAST; see docs/pandoc-integration/kast.md.
--
-- Pandoc surfaces bare YAML keys (e.g. `subject:` with no value) as non-nil
-- MetaValues that stringify to an empty string. Plain Lua truthiness reads
-- those as set, which silently breaks bridges and defaults. The inspection
-- helpers centralize the "is this really set?" check so every filter agrees
-- on the semantics. The mutators own the `or MetaList{}` first-use guard so
-- it is spelled exactly once.

local M = {}

--- Stringify a metadata value and trim leading/trailing whitespace.
---
--- Wraps `pandoc.utils.stringify` (which does not trim) and adds the
--- whitespace strip so callers can compare the result directly to "auto",
--- "disabled", etc. without re-implementing the trim. Returns "" for nil
--- and for bare YAML keys (e.g. `subject:` with no value), tilde-null
--- (`subject: ~`), and whitespace-only strings (`subject: "  "`) — all of
--- which Pandoc surfaces as non-nil but content-free Meta values.
---
---@param value any  A pandoc Meta value (MetaInlines, MetaString, etc.) or nil
---@return string    Trimmed string ("" if blank or nil)
function M.stringify(value)
  if value == nil then return "" end
  return pandoc.utils.stringify(value):match("^%s*(.-)%s*$")
end

--- True if a metadata value is absent or carries no usable content.
---
--- Convenience predicate over `stringify` — true when the trimmed string
--- is empty.
---
---@param value any  A pandoc Meta value (MetaInlines, MetaString, etc.) or nil
---@return boolean
function M.is_blank(value)
  return M.stringify(value) == ""
end

--- Append a LaTeX RawBlock to `header-includes`, creating the MetaList on
--- first use. `header-includes` is the metadata list Pandoc injects into the
--- preamble; it must be a MetaList, so the first append seeds one. Centralizes
--- the `meta[k] = meta[k] or MetaList{}; insert` idiom.
---@param meta table   Pandoc Meta object
---@param latex string raw LaTeX for the preamble
function M.add_header_include(meta, latex)
  meta["header-includes"] = meta["header-includes"] or pandoc.MetaList{}
  table.insert(meta["header-includes"], pandoc.RawBlock("latex", latex))
end

--- Append a stylesheet path to `meta.css`, creating the MetaList on first use.
--- `css` is the metadata list of stylesheet paths Pandoc links into CSS-based
--- outputs (EPUB/HTML). Centralizes the same first-use guard as
--- add_header_include.
---@param meta table  Pandoc Meta object
---@param path string stylesheet path
function M.add_css(meta, path)
  meta.css = meta.css or pandoc.MetaList{}
  table.insert(meta.css, pandoc.MetaString(path))
end

return M
