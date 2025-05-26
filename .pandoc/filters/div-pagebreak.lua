---@diagnostic disable: undefined-global
-- div-pagebreak.lua
-- Inserts LaTeX or HTML page breaks when a div has class "pagebreak"
--
-- Markdown sample:
--
-- ::: pagebreak
-- :::
--
function Div(el)
  if el.classes:includes("pagebreak") then
    if FORMAT:match("latex") then
      return pandoc.RawBlock("latex", "\\clearpage")
    elseif FORMAT:match("html") or FORMAT:match("epub") then
      return pandoc.RawBlock("html", '<div class="pagebreak"></div>')
    end
  end
end
