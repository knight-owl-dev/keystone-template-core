-- Transforms ::: dialog blocks into stylized dialog lines.
-- See README.md for usage. LaTeX macros loaded from macros.tex.

return function(el)
  local is_pdf = FORMAT:match("latex")
  local blocks = {}

  for _, block in ipairs(el.content) do
    if block.t == "BulletList" then
      for _, item in ipairs(block.content) do
        local inlines = item[1].content

        if is_pdf then
          local latex = pandoc.write(pandoc.Pandoc({pandoc.Plain(inlines)}), "latex")
          latex = latex:gsub("%s+$", "")
          table.insert(blocks, pandoc.RawBlock("latex", "\\dialogline{" .. latex .. "}"))
        else
          local line = pandoc.List({pandoc.Str("\u{2014}"), pandoc.Space()})
          line:extend(inlines)
          table.insert(blocks, pandoc.Para(line))
        end
      end
    end
  end

  if is_pdf then
    -- Add vertical space after the dialog block to separate it from the next paragraph
    table.insert(blocks, pandoc.RawBlock("latex", "\\afterdialogblock"))
  end

  return blocks
end
