# latex-only

Includes content only in PDF builds. In all other formats the block is
removed entirely.

## Usage

```markdown
::: latex-only
\begin{center}
Custom LaTeX content here.
\end{center}
:::
```

## Files

| File          | Purpose                                                   |
| ------------- | --------------------------------------------------------- |
| `handler.lua` | Passes content through for LaTeX; strips it for all other |
