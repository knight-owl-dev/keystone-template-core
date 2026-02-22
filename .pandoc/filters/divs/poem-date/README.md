# poem-date

Renders a right-aligned italic date line, typically placed below a poem
title or body.

## Usage

```markdown
::: poem-date
2025-05-23
:::
```

## Files

| File          | Purpose                                            |
| ------------- | -------------------------------------------------- |
| `handler.lua` | Emits `\poemdate{}` (PDF) or keeps the div (EPUB)  |
| `macros.tex`  | Defines the `\poemdate` LaTeX command              |
| `style.css`   | Right-aligned italic styling for EPUB/HTML         |
