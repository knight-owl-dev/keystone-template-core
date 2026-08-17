-- Conditional horizontal rule for decorating composed shortcuts.
-- Renders a thin horizontal line when style=ruled, and removes itself
-- otherwise.
-- Div content is ignored — in shortcut bodies the div contains a Markdown
-- thematic break (***) as a placeholder to prevent content injection.
-- See README.md for usage.

local kast = ks_require("ast")

-- Wrap each format renderer so the style=ruled guard lives in one place.
local function when_ruled(render)
  return function(el, report)
    if el.attributes["style"] ~= "ruled" then return kast.Remove() end
    return render(el, report)
  end
end

local latex = when_ruled(function()
  return kast.RawBlock("latex", "\\keystonerule")
end)

-- Uses a native Pandoc Div so Pandoc handles XHTML serialization safely.
local html = when_ruled(function()
  return kast.Div({}, kast.Attr("", { "rule" }))
end)

local docx = when_ruled(function()
  return kast.Div(
    { kast.Para({ kast.Str(" ") }) },
    kast.Attr("", {}, { ["custom-style"] = "Rule" })
  )
end)

return {
  div = {
    latex = latex,
    html = html,
    epub = html,
    docx = docx,
    odt = docx,
  },
}
