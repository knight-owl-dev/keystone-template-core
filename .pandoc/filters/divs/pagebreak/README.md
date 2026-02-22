# pagebreak

Inserts a page break. Produces `\clearpage` in PDF and a CSS page-break
element in EPUB/HTML.

## Usage

```markdown
::: pagebreak
:::
```

## Files

| File          | Purpose                                          |
| ------------- | ------------------------------------------------ |
| `handler.lua` | Emits `\clearpage` (PDF) or an HTML div (EPUB)   |
| `style.css`   | `page-break-before: always` rule for EPUB/HTML   |
