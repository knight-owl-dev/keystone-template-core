-- Emit running-header marks for unnumbered headings.
--
-- Pandoc renders `# Title {.unnumbered}` as `\chapter*{Title}` and
-- `## Title {.unnumbered}` as `\section*{Title}`. The starred sectioning
-- commands never call `\chaptermark`/`\sectionmark`, so `\leftmark` and
-- `\rightmark` never update — the running header freezes on whatever last
-- set them, which is `\tableofcontents` (`\@mkboth{Contents}{Contents}`).
-- A book built entirely from `{.unnumbered}` headings therefore shows
-- "Contents" on every body page (issue #436).
--
-- This handler restores the marks the starred forms skip, mirroring the
-- numbered commands:
--   level 1 → `\markboth{title}{}`  (like `\chaptermark`; the empty second
--             group clears any stale section mark so a section-less chapter
--             doesn't inherit the previous chapter's section in `\rightmark`)
--   level 2 → `\markright{title}`   (like `\sectionmark`)
-- Levels 3+ reach the handler but emit nothing — the standard/KOMA classes
-- don't carry marks below the section level. Numbered headings never reach
-- it at all: routing dispatches only `.unnumbered` headings here (numbered
-- ones already mark themselves).
--
-- The mark RawBlock follows the heading so it lands after `\chapter*`'s
-- `\cleardoublepage`: the mark is set on the (bare) opening page and carries
-- to the following body pages via TeX's `\topmark`, exactly as a numbered
-- chapter's mark does.
--
-- Package-agnostic by construction: `\markboth`/`\markright` are LaTeX kernel
-- primitives. fancyhdr and scrlayer-scrpage both read them through
-- `\leftmark`/`\rightmark` (see page-layout-*.tex). The title is rendered
-- raw-case; display casing is the layout include's concern (the fancyhdr
-- include wraps marks in `\nouppercase`), so this handler stays
-- display-agnostic.
--
-- Routed via the `header` slot on Pandoc's own `.unnumbered` class — a public
-- Pandoc contract we tap rather than abstract, so there is no `ks-` name and
-- no system shortcut (nothing of ours to hide behind a stable facade). PDF
-- only: marks are meaningless in EPUB/DOCX/ODT, so only the latex hook exists
-- and every other format passes the heading through unchanged.

local kast = ks_require("ast")

local function latex(el)
  local title = kast.latex.inlines(el.content)
  if el.level == 1 then
    return { el, kast.RawBlock("latex", kast.latex.command("markboth", { args = { title, "" } })) }
  elseif el.level == 2 then
    return { el, kast.RawBlock("latex", kast.latex.command("markright", { args = { title } })) }
  end
end

return {
  header = {
    latex = latex,
  },
}
