# dropcap

Applies drop-cap styling to the first letter of a paragraph — an enlarged
initial letter commonly used at chapter or section openings.

Supports two syntaxes: **span** (explicit letter control) and **div**
(automatic first-character extraction).

## Usage

### Span syntax (explicit)

The author marks the drop-cap letter directly:

```markdown
[E]{.dropcap}very project has a story.
```

Use span syntax when the first inline is not plain text — for example,
when the opening includes quotation marks or emphasis:

```markdown
["T]{.dropcap}he best way to predict the future is to invent it."
```

### Div syntax (automatic)

The handler extracts the first character from the first paragraph:

```markdown
::: dropcap
Every project has a story.
:::
```

If the first inline in the paragraph is not a plain `Str` (e.g. emphasis
or a link), the handler warns and returns nil — use span syntax instead.

### Custom drop height

The `lines` attribute controls how many lines the drop cap spans
(default: 3):

```markdown
[E]{.dropcap lines=2}very project has a story.

::: {.dropcap lines=4}
Every project has a story.
:::
```

### Custom font family

The `font-family` attribute applies a decorative font from the font
registry:

```markdown
[E]{.dropcap font-family="eb-garamond"}very project has a story.

::: {.dropcap font-family="eb-garamond"}
Every project has a story.
:::
```

### Why font-family lives here

Unlike most attributes, `font-family` is intrinsic to the drop cap
mechanism — the handler extracts the first character and wraps it in a
`\lettrine` command, so only it knows which piece of text receives the
font. A nested `.font` div would style the entire paragraph, not just
the initial letter. The trade-off is that `font-family` only takes
effect in PDF and EPUB; DOCX and ODT output ignores it.

## Paragraph length

Drop caps look best when the paragraph has enough text to wrap alongside
the enlarged letter. A three-line drop cap needs at least three or four
lines of body text to fill the space; shorter paragraphs leave the letter
floating in whitespace. For brief openings, use `lines=2` or move the
drop cap to a longer paragraph.

## Shortcuts

Define a named shortcut in `shortcuts.yaml` to avoid repeating attributes:

```yaml
fancy-drop:
  class: dropcap
  interface:
    font-family:
      bind: class.font-family
      default: eb-garamond
    lines:
      bind: class.lines
      default: 2
```

Then use it directly:

```markdown
[E]{.fancy-drop}very project has a story.
```

## Files

| File          | Purpose                                                    |
| ------------- | ---------------------------------------------------------- |
| `handler.lua` | Extracts/wraps letter; emits lettrine (PDF) or span (EPUB) |
| `macros.tex`  | Loads the `lettrine` package for LaTeX                     |
| `style.css`   | Float and scale styling for EPUB/HTML drop caps            |
