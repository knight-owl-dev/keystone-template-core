-- Inserts a page break for ::: pagebreak blocks.
-- See README.md for usage. EPUB/HTML styling loaded from style.css.

return function(_el)
  if FORMAT:match("latex") then
    return pandoc.RawBlock("latex", "\\clearpage")
  elseif FORMAT:match("html") or FORMAT:match("epub") then
    return pandoc.RawBlock("html", '<div class="pagebreak"></div>')
  end
end
