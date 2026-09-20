-- Wraps content in a narrowed (indented) block — left and right margins.
-- No attributes — pure structural wrapper. Composed into shortcuts like
-- epigraph via body injection where it provides indentation.
-- See README.md for usage. LaTeX wraps content in a keystonequote environment
-- (macros.tex), same pattern as aside.

local kast = ks_require("ast")

local function latex(el)
  local body = kast.latex.blocks(el.content)
  return kast.RawBlock("latex", kast.latex.env("keystonequote", body))
end

local function html(el)
  el.classes = { "quote" }
  return el
end

local function docx(el)
  el.attributes["custom-style"] = "Quote"
  return el
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
