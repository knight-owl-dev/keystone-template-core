# dialog

Transforms a bullet list into stylized dialog lines — em-dashes in PDF,
plain dashes in EPUB.

## Usage

```markdown
::: dialog
- Hello?
- It's me.
- I was wondering if after all these years…
:::
```

## Files

| File          | Purpose                                                        |
| ------------- | -------------------------------------------------------------- |
| `handler.lua` | Converts each bullet into a `\dialogline{}` (PDF) or paragraph |
| `macros.tex`  | Defines `\dialogline` and `\afterdialogblock` LaTeX commands   |
