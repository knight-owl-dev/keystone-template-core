-- Renders an attribution line from a text= attribute.
-- The handler prepends an em-dash and renders the text right-aligned in
-- upright (non-italic) style. Removes the div silently when the text
-- attribute is absent or empty.
-- Used by system shortcuts (pullquote, epigraph) via body injection.
-- See README.md for usage.

local kast = ks_require("ast")

--- Em-dash + thin space prefix for non-LaTeX formats.
--- LaTeX uses \textemdash\, in the macro instead.
local EM_DASH = "\u{2014}\u{2009}"

local function validate(el)
  local text = el.attributes["text"]
  if not text or text == "" then return nil end
  return text
end

local function latex(el)
  local text = validate(el)
  if not text then return kast.Remove() end

  local escaped = kast.latex.inlines({ kast.Str(text) })
  return kast.RawBlock("latex", kast.latex.command("keystonesource", { args = { escaped } }))
end

local function html(el)
  local text = validate(el)
  if not text then return kast.Remove() end

  return kast.Div(
    { kast.Plain({ kast.Str(EM_DASH), kast.Str(text) }) },
    kast.Attr("", { "source" })
  )
end

--- Shared DOCX/ODT handler. Both use custom-style but differ in block type:
--- DOCX propagates custom-style to Plain; ODT requires Para.
---@param el table     Pandoc Div element
---@param block_fn function  kast.Plain (DOCX) or kast.Para (ODT)
local function doc(el, block_fn)
  local text = validate(el)
  if not text then return kast.Remove() end

  return kast.Div(
    { block_fn({ kast.Str(EM_DASH), kast.Str(text) }) },
    kast.Attr("", {}, { ["custom-style"] = "Source" })
  )
end

return {
  div = {
    latex = latex,
    html = html,
    epub = html,
    docx = function(el) return doc(el, kast.Plain) end,
    odt = function(el) return doc(el, kast.Para) end,
  },
}
