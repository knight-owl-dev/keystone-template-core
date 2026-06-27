-- ast/construct.lua — Explicit, documented wrappers over Pandoc's element
-- constructors. Part of KAST; see docs/pandoc-integration/kast.md.
--
-- Each function is a one-line forwarder that resolves `pandoc.<symbol>` at
-- CALL time, never at load — so a cached module honors a `pandoc` swapped on
-- _G between test cases (the laziness rule). They are written out explicitly
-- rather than generated in a loop on purpose: an explicit wrapper is the only
-- form that can absorb a Pandoc *signature* change in one place (a `...`
-- passthrough is signature-blind), and it gives editors and luacheck real
-- signatures plus symbol-named errors when a constructor disappears.

local M = {}

--- A raw block — markup passed through the named writer verbatim.
---@param format string  writer name, e.g. "latex", "html", "openxml", "opendocument"
---@param text string    raw markup for that writer
---@return table         RawBlock element
function M.RawBlock(format, text) return pandoc.RawBlock(format, text) end

--- A raw inline — like RawBlock but inside a paragraph's inline run.
---@param format string  writer name, e.g. "latex", "html"
---@param text string    raw markup for that writer
---@return table         RawInline element
function M.RawInline(format, text) return pandoc.RawInline(format, text) end

--- A text run. The atomic unit of inline content; whitespace between words
--- is a separate Space, not part of the Str.
---@param text string
---@return table  Str element
function M.Str(text) return pandoc.Str(text) end

--- A paragraph — a block of inline content rendered with paragraph spacing.
---@param content table  list of Inline elements
---@return table         Para element
function M.Para(content) return pandoc.Para(content) end

--- A plain block — inline content with no paragraph break or spacing. Use
--- when wrapping inlines for serialization without `\par` separators.
---@param content table  list of Inline elements
---@return table         Plain element
function M.Plain(content) return pandoc.Plain(content) end

--- A generic block container, the AST node behind a fenced `:::` div. Carries
--- an Attr (identifier, classes, attributes) that handlers dispatch on.
---@param content table  list of Block elements
---@param attr table|nil Attr (from M.Attr) or nil for an empty attribute set
---@return table         Div element
function M.Div(content, attr) return pandoc.Div(content, attr) end

--- A generic inline container — the inline analogue of Div, behind a `[…]{…}`
--- bracketed span.
---@param content table  list of Inline elements
---@param attr table|nil Attr (from M.Attr) or nil
---@return table         Span element
function M.Span(content, attr) return pandoc.Span(content, attr) end

--- Strong (bold) inline emphasis.
---@param content table  list of Inline elements
---@return table         Strong element
function M.Strong(content) return pandoc.Strong(content) end

--- Inter-word space — a distinct inline element, not a character inside a Str.
---@return table  Space element
function M.Space() return pandoc.Space() end

--- A Pandoc List: an array-like table with helper methods (`:insert`, etc.).
--- Returned so callers building element sequences get the native list API,
--- not a bare Lua table.
---@param t table|nil  initial items (defaults to empty)
---@return table       pandoc.List
function M.List(t) return pandoc.List(t) end

--- An element attribute set: identifier, classes, and key-value attributes.
--- The triple every Div/Span carries; handlers read classes/attributes from
--- it and write the identifier for `\label`/`id`.
---@param identifier string|nil  element id ("" for none)
---@param classes table|nil      list of class-name strings
---@param attributes table|nil   key-value attribute map
---@return table                 Attr
function M.Attr(identifier, classes, attributes)
  return pandoc.Attr(identifier, classes, attributes)
end

--- A metadata list value — the MetaValue used for repeatable keys such as
--- `header-includes` and `css`. Distinct from a plain Lua table: Pandoc only
--- recognizes MetaList/MetaString/MetaInlines as metadata.
---@param t table|nil  initial items (defaults to empty)
---@return table       MetaList
function M.MetaList(t) return pandoc.MetaList(t) end

--- A metadata string value — a scalar `key: value` with no inline formatting.
---@param s string
---@return table  MetaString
function M.MetaString(s) return pandoc.MetaString(s) end

--- A metadata inlines value — a metadata scalar that carries inline content
--- (so emphasis, links, etc. survive). Used where a Str must read back as a
--- formatted metadata value, e.g. a computed date.
---@param inlines table  list of Inline elements
---@return table         MetaInlines
function M.MetaInlines(inlines) return pandoc.MetaInlines(inlines) end

return M
