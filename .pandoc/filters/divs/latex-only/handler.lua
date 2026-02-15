-- Includes ::: latex-only blocks in PDF builds; strips them in all others.
-- See README.md for usage.

return function(el)
  if FORMAT:match("latex") then
    return el.content
  else
    return {}
  end
end
