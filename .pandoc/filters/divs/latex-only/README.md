# latex-only

Includes content only in PDF builds. In all other formats the content is
removed entirely. Works with both block-level fenced divs and inline spans.

## Usage

Block-level (fenced div):

```markdown
::: latex-only
\begin{center}
Custom LaTeX content here.
\end{center}
:::
```

Inline (span):

```markdown
Pandoc[, powered by \LaTeX,]{.latex-only}
makes publishing easy[\footnote{Via the
XeLaTeX engine.}]{.latex-only}.
```

- `\LaTeX` renders the stylized logo — a cosmetic touch for PDF readers.
- `\footnote{...}` adds a numbered footnote — EPUB has no fixed pages, so
  the span is stripped entirely.

Both spans are safely removable: in EPUB the sentence reads
"Pandoc makes publishing easy."

## Files

| File          | Purpose                                                          |
| ------------- | ---------------------------------------------------------------- |
| `handler.lua` | Passes div/span content through for LaTeX; strips for all others |
