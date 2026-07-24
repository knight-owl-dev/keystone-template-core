-- Switch the following chapters to appendix numbering for ::: appendix.
--
-- `\appendix` is a positional switch: every sectioning unit after it renumbers
-- — chapters in book/report/KOMA, sections in the article family — and the
-- running label becomes `\appendixname`. Pandoc's babel/polyglossia setup
-- localizes that from the document `lang`, so `\appendix` alone carries the
-- right label. The div is a marker: authors drop it in a control file or atop
-- their first appendix chapter, and any body content follows the switch back
-- into the flow (empty div → just the switch).
--
-- Lettered chapters and A.1/A.2 subsection numbering are a documentclass
-- artifact with no analog in other writers, so the switch is LaTeX-only. Every
-- other format unwraps the marker: content flows as ordinary chapters and an
-- empty marker vanishes.
--
-- `numbering=` selects the enumerator via CSS list-style tokens. The default
-- upper-alpha needs nothing — `\appendix` already sets `\Alph`; other styles
-- emit `\keystoneappendixnumbering` (see macros.tex).

local kast = ks_require("ast")

-- CSS list-style token → LaTeX counter-format command (consumed via \csname).
local NUMBERING = {
  ["upper-alpha"] = "Alph", -- default; matches bare \appendix
  ["lower-alpha"] = "alph",
  ["upper-roman"] = "Roman",
  ["lower-roman"] = "roman",
  ["arabic"] = "arabic",
}

local function latex(el, report)
  local blocks = { kast.RawBlock("latex", kast.latex.command("appendix")) }

  local token = el.attributes["numbering"]
  if token and token ~= "upper-alpha" then
    local cmd = NUMBERING[token]
    if not cmd then
      report.warn("appendix: unknown numbering '" .. token .. "'")
      -- Fall through: bare \appendix keeps the default upper-alpha.
    else
      table.insert(blocks, kast.RawBlock("latex",
        kast.latex.command("keystoneappendixnumbering", { args = { cmd } })))
    end
  end

  for _, block in ipairs(el.content) do
    table.insert(blocks, block)
  end
  return blocks
end

-- Non-LaTeX: unwrap the marker to its content (see the header).
local function unwrap(el)
  return el.content
end

return {
  div = {
    latex = latex,
    default = unwrap,
  },
}
