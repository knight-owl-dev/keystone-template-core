-- ast/inspect.lua — Parsing and traversal over the AST. Part of KAST; see
-- docs/pandoc-integration/kast.md.

local M = {}

--- Parse a markup string into a Pandoc document. Callers typically take the
--- `.blocks` of the result to splice into a larger tree.
---@param text string         source markup
---@param format string|nil   reader name (defaults to "markdown")
---@return table              Pandoc document
function M.read(text, format)
  return pandoc.read(text, format or "markdown")
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

return M
