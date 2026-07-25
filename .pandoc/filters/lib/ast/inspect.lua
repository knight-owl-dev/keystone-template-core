-- ast/inspect.lua — Parsing and traversal over the AST. Part of KAST; see
-- docs/pandoc-integration/kast.md.

local text = ks_require("text")

local M = {}

--- Parse a markup string into a Pandoc document. Callers typically take the
--- `.blocks` of the result to splice into a larger tree.
---@param markup string       source markup
---@param format string|nil   reader name (defaults to "markdown")
---@return table              Pandoc document
function M.read(markup, format)
  return pandoc.read(markup, format or "markdown")
end

--- Walk a list of blocks with a Pandoc filter table and return the
--- transformed blocks. Wraps the `pandoc.Pandoc(blocks):walk(filter).blocks`
--- idiom. Exposes block-list traversal only — a whole-document walk, or one
--- returning the doc rather than its blocks, is a separate interface to be
--- added deliberately when a real need arrives.
---@param blocks table  list of Block elements
---@param filter table  Pandoc filter table (e.g. { Div = fn, Span = fn })
---@return table         transformed list of Block elements
function M.walk(blocks, filter)
  return pandoc.Pandoc(blocks):walk(filter).blocks
end

--- Flatten a list of blocks into a single inline list, dropping block-level
--- structure. Useful when a handler needs the inline content of arbitrary
--- block content (e.g. a scene-break ornament built from div body text).
---@param blocks table  list of Block elements
---@return table         list of Inline elements
function M.blocks_to_inlines(blocks)
  return pandoc.utils.blocks_to_inlines(blocks)
end

-- Cap on the leading-text snippet, in characters. Long enough to identify the
-- element in a diagnostic, short enough to stay on one line.
local SNIPPET_LIMIT = 40

--- A one-line, truncated plain-text lead from an element, for diagnostics.
--- Whitespace (including block-internal newlines) is collapsed to single
--- spaces so multi-paragraph content still renders on one line; an over-long
--- lead is cut on a UTF-8 character boundary and suffixed with an ellipsis.
local function snippet(el)
  local s = text.trim(pandoc.utils.stringify(el):gsub("%s+", " "))
  -- offset(s, LIMIT+1) is the byte just past the LIMIT-th character: nil (or
  -- past the end) when the text is already within the cap, so no truncation.
  local cut = utf8.offset(s, SNIPPET_LIMIT + 1)
  if not cut or cut > #s then return s end
  return s:sub(1, cut - 1) .. "…"
end

--- Describe an element for a diagnostic message: which classes and identifier
--- it carries, its attributes, and a leading-text snippet to locate it in the
--- manuscript. Lives in KAST because the snippet needs `stringify`. The classes
--- and attributes are copied so the returned table is a stable snapshot, not a
--- view a later handler mutation could disturb. This is also the seam where
--- source positions would attach if Keystone ever tags them (see #452).
---@param el table  a Pandoc element with an Attr (Div, Span, Header, Figure, …)
---@return table    { classes, identifier, attributes, snippet }
function M.describe(el)
  local classes = {}
  for _, class in ipairs(el.classes or {}) do
    classes[#classes + 1] = class
  end
  local attributes = {}
  for key, value in pairs(el.attributes or {}) do
    attributes[key] = value
  end
  return {
    classes = classes,
    identifier = el.identifier or "",
    attributes = attributes,
    snippet = snippet(el),
  }
end

return M
