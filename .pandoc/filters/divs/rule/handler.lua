-- Conditional horizontal rule for decorating composed shortcuts.
-- Renders a thin horizontal line when style=ruled; returns an empty block
-- list ({}) otherwise so the dispatcher suppresses the Div.
-- Div content is ignored — in shortcut bodies the div contains a Markdown
-- thematic break (***) as a placeholder to prevent content injection.
-- See README.md for usage.

local kast = ks_require("ast")

local function latex(el)
  if el.attributes["style"] ~= "ruled" then return {} end

  return kast.RawBlock("latex", "\\keystonerule")
end

--- Uses a native Pandoc Div so Pandoc handles XHTML serialization safely.
local function html(el)
  if el.attributes["style"] ~= "ruled" then return {} end

  return kast.Div({}, kast.Attr("", { "rule" }))
end

local function docx(el)
  if el.attributes["style"] ~= "ruled" then return {} end

  local div = kast.Div(
    { kast.Para({ kast.Str(" ") }) },
    kast.Attr("", {})
  )
  div.attributes["custom-style"] = "Rule"
  return div
end

return {
  div = {
    latex = latex,
    html = html,
    epub = html,
    docx = docx,
    odt = docx,
  },
}
