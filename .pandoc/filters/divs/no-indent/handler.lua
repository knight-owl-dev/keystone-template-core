-- Suppresses first-line paragraph indentation within its scope.
-- LaTeX: wraps content in a group with \parindent set to 0.
-- EPUB/HTML: sets the no-indent class on the div.
-- DOCX/ODT: unwraps content (review format, not worth per-section override).

local kast = ks_require("ast")

local function latex(el)
  local blocks = {}
  blocks[#blocks + 1] = kast.RawBlock("latex",
    "\\begingroup" .. kast.latex.command("setlength", { args = { "\\parindent", "0pt" } }))

  for _, block in ipairs(el.content) do
    blocks[#blocks + 1] = block
  end

  blocks[#blocks + 1] = kast.RawBlock("latex", "\\endgroup")

  return blocks
end

local function html(el)
  el.classes = { "no-indent" }
  return el
end

local function docx(el)
  return el.content
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
