# unnumbered

Restores running-header marks for `{.unnumbered}` headings in PDF output.

Pandoc emits `\chapter*`/`\section*` for unnumbered headings, and the
starred forms never update `\leftmark`/`\rightmark` — so a book built from
unnumbered headings freezes the `{chapter}`/`{section}` running-header
placeholders on the last value `\tableofcontents` set ("Contents"). This
handler emits `\markboth{title}{}` after a level-1 heading and
`\markright{title}` after a level-2 one, mirroring `\chaptermark`/
`\sectionmark` so the marks track the current heading.

This is not an authored construct — `.unnumbered` is Pandoc's own heading
class, routed here via the `header` slot. Authors write it exactly as
Pandoc documents; there is no shortcut and no `ks-` name.

## Usage

```markdown
# Chapter Title {.unnumbered}

## Section Title {.unnumbered}
```

No attributes. PDF only (marks have no meaning in EPUB/DOCX/ODT).

## Files

| File          | Purpose                                                    |
| ------------- | ---------------------------------------------------------- |
| `handler.lua` | Emits `\markboth`/`\markright` after an unnumbered heading |
