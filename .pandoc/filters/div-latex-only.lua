---@diagnostic disable: undefined-global
-- .pandoc/filters/div-latex-only.lua
--
-- Removes ::: latex-only blocks from all output formats except LaTeX.
-- Allows users to write raw LaTeX inside Markdown without affecting EPUB, DOCX, or HTML.
--
-- Markdown sample:
--
-- ::: latex-only
-- \begin{center}
-- \begin{tabular}{|c|c|}
--   \hline
--   Markdown & \tick \\
--   \hline
-- \end{tabular}
-- \end{center}
-- :::
--
-- In PDF builds, this block will be included as-is.
-- In other formats, it will be removed entirely.
--
function Div(el)
  local is_pdf = FORMAT == "latex"

  if el.classes:includes("latex-only") then
    if is_pdf then
      return el.content
    else
      -- strip block for non-LaTeX formats
      return {}
    end
  end
end
