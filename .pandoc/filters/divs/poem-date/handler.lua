-- Styles ::: poem-date blocks as right-aligned italic dates.
-- See README.md for usage. LaTeX macros loaded from macros.tex.

return function(el)
  if FORMAT:match("latex") then
    local inlines = pandoc.utils.blocks_to_inlines(el.content)
    local latex = pandoc.write(pandoc.Pandoc({pandoc.Plain(inlines)}), "latex")
    latex = latex:gsub("%s+$", "")
    return pandoc.RawBlock("latex", "\\poemdate{" .. latex .. "}")
  elseif FORMAT:match("html") or FORMAT:match("epub") then
    return el
  end
end
