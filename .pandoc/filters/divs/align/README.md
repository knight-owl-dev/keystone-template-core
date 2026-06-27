# align

Applies text alignment to block-level content via a single `style=` attribute.

## Usage

```markdown
::: {.align style="center"}
This paragraph is centered.
:::

::: {.align style="right"}
Right-aligned text.
:::
```

## Supported style values

| Value | LaTeX | CSS |
| ----- | ----- | --- |
| `left` | `\begin{flushleft}` | `text-align: left` |
| `center` | `\begin{center}` | `text-align: center` |
| `right` | `\begin{flushright}` | `text-align: right` |
| `justified` | `\begin{keystonejustify}` | `text-align: justify` |

## Shortcuts

Common patterns can be named in `shortcuts.yaml`. For combined alignment
and font styling, use body injection with a font slot:

```yaml
poem-date:
  class: align
  interface:
    style:
      bind: class.style
      default: right
  body: |
    ::: {.font style="italic"}
    :::
```

Then use it directly:

```markdown
::: poem-date
2025-05-23
:::
```

## Files

| File | Purpose |
| ---- | ------- |
| `handler.lua` | Emits LaTeX alignment environments (PDF) or CSS classes (EPUB/HTML) |
| `macros.tex` | LaTeX preamble — defines `keystonejustify` environment |
| `style.css` | Alignment CSS rules for EPUB/HTML |
