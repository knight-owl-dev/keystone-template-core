-- Includes ::: latex-only divs and [content]{.latex-only} spans in PDF builds;
-- strips them in all others. See README.md for usage.

local function handler(el)
  if FORMAT:match("latex") then
    return el.content
  else
    return {}
  end
end

return {
  div = handler,
  span = handler,
}
