---@diagnostic disable: undefined-global
-- .keystone/filters/dialog.lua
-- Transforms ::: dialog blocks into stylized LaTeX dialog lines
--
-- Markdown sample:
--
-- ::: dialog
-- - Hello?
-- - It’s me.
-- - I was wondering if after all these years…
-- :::
--
-- Requires: % base-style.tex
-- \newcommand{\dialogline}[1]{\noindent---~#1\par\vspace{-0.5\baselineskip}}
-- \newcommand{\afterdialogblock}{\vspace{0.5\baselineskip}}
--
function Div(el)
  if not el.classes:includes("dialog") then return end

  local is_pdf = FORMAT == "latex"
  local blocks = {}

  for _, block in ipairs(el.content) do
    if block.t == "BulletList" then
      for _, item in ipairs(block.content) do
        local text = pandoc.utils.stringify(item[1])

        if is_pdf then
          table.insert(blocks, pandoc.RawBlock("latex", "\\dialogline{" .. text .. "}"))
        else
          table.insert(blocks, pandoc.Para({ pandoc.Str("— "), pandoc.Str(text) }))
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
