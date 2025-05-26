---@diagnostic disable: undefined-global
-- .keystone/filters/div-poem-date.lua
-- Filter to handle ::: poem-date blocks in Pandoc
--
-- Markdown sample:
--
-- ::: poem-date
-- 2025-05-23
-- :::
--
-- Requires: % base-style.tex
-- \newcommand{\poemdate}[1]{\begin{flushright}\textit{#1}\end{flushright}}
--
function Div(el)
  if el.classes:includes("poem-date") then
    local content = pandoc.utils.stringify(el.content)

    if FORMAT:match("latex") then
      return pandoc.RawBlock("latex", "\\poemdate{" .. content .. "}")
    elseif FORMAT:match("html") or FORMAT:match("epub") then
      if not el.classes:includes("poem-date") then
        table.insert(el.classes, "poem-date")
      end
      return el
    end
  end
end
