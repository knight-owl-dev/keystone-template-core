# font

Applies font-family and/or font-size overrides to blocks or inline text.
Both attributes can be used independently or combined on a single element.

## Usage

Block-level (fenced div):

```markdown
::: {.font family="libertine"}
This paragraph will render in Linux Libertine.
:::

::: {.font size="small"}
This paragraph will render in a smaller font.
:::

::: {.font family="dejavu-sans" size="large"}
This paragraph is set in DejaVu Sans at a larger size.
:::
```

Inline (bracketed span):

```markdown
A word in [Libertine]{.font family="libertine"} inline.

This has [small text]{.font size="small"} in the middle.

Here is [large DejaVu Sans]{.font family="dejavu-sans" size="large"} inline.
```

## Supported families

| Value | PDF font | EPUB fallback stack |
| ----- | -------- | ------------------- |
| `libertine` | Linux Libertine | Georgia, serif |
| `biolinum` | Linux Biolinum | Helvetica Neue, sans-serif |
| `dejavu-serif` | DejaVu Serif | Georgia, serif |
| `dejavu-sans` | DejaVu Sans | Helvetica Neue, sans-serif |
| `dejavu-mono` | DejaVu Sans Mono | Courier New, monospace |
| `latin-modern` | Latin Modern Roman | Computer Modern, serif |

## Supported sizes

Values map 1:1 to [LaTeX's built-in size commands](https://www.overleaf.com/learn/latex/Font_sizes%2C_families%2C_and_styles#Font_sizes).

| Value | LaTeX | CSS |
| ----- | ----- | --- |
| `tiny` | `\tiny` | `0.6em` |
| `scriptsize` | `\scriptsize` | `0.7em` |
| `footnotesize` | `\footnotesize` | `0.8em` |
| `small` | `\small` | `0.9em` |
| `normalsize` | `\normalsize` | `1.0em` |
| `large` | `\large` | `1.2em` |
| `Large` | `\Large` | `1.44em` |
| `LARGE` | `\LARGE` | `1.728em` |
| `huge` | `\huge` | `2.074em` |
| `Huge` | `\Huge` | `2.488em` |

## Files

| File | Purpose |
| ---- | ------- |
| `handler.lua` | Emits `\begingroup\<font>\<size>...\endgroup` (PDF) or CSS classes (EPUB) |

Font and size definitions — including `\newfontfamily` declarations (PDF),
CSS `font-family` rules, and CSS `font-size` rules (EPUB/HTML) — live in
the shared font registry at `filters/lib/font-registry.lua`. Both this
handler and `keystone.lua` load definitions from that single source.
`keystone.lua` generates and injects all styles into `header-includes`.
