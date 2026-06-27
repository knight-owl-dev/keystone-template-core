# font

Applies font-family, font-style, and/or font-size overrides to blocks or
inline text. All three attributes can be used independently or combined on a
single element.

## Usage

Block-level (fenced div):

```markdown
::: {.font family="libertine"}
This paragraph will render in Linux Libertine.
:::

::: {.font style="italic"}
This paragraph will render in italic.
:::

::: {.font size="small"}
This paragraph will render in a smaller font.
:::

::: {.font family="dejavu-sans" style="bold" size="large"}
This paragraph is set in bold DejaVu Sans at a larger size.
:::
```

Inline (bracketed span):

```markdown
A word in [Libertine]{.font family="libertine"} inline.

This has [italic text]{.font style="italic"} in the middle.

This has [small text]{.font size="small"} in the middle.

Here is [bold large DejaVu Sans]{.font family="dejavu-sans" style="bold" size="large"} inline.
```

## Supported families

User-defined fonts registered in `fonts/fonts-registry.yaml` are also
available as `family` values. See [`fonts/README.md`](../../../../../fonts/README.md)
for setup instructions.

### Built-in families

| Value | PDF font | EPUB fallback stack |
| ----- | -------- | ------------------- |
| `libertine` | Linux Libertine | Georgia, serif |
| `biolinum` | Linux Biolinum | Helvetica Neue, sans-serif |
| `dejavu-serif` | DejaVu Serif | Georgia, serif |
| `dejavu-sans` | DejaVu Sans | Helvetica Neue, sans-serif |
| `dejavu-mono` | DejaVu Sans Mono | Courier New, monospace |
| `eb-garamond` | EB Garamond | Garamond, Georgia, serif |
| `latin-modern` | Latin Modern Roman | Computer Modern, serif |
| `tex-gyre-adventor` | TeX Gyre Adventor | Avant Garde, sans-serif |
| `tex-gyre-bonum` | TeX Gyre Bonum | Bookman Old Style, serif |
| `tex-gyre-cursor` | TeX Gyre Cursor | Courier New, monospace |
| `tex-gyre-heros` | TeX Gyre Heros | Helvetica, Arial, sans-serif |
| `tex-gyre-pagella` | TeX Gyre Pagella | Palatino Linotype, Book Antiqua, serif |
| `tex-gyre-schola` | TeX Gyre Schola | Century Schoolbook, serif |
| `tex-gyre-termes` | TeX Gyre Termes | Times New Roman, serif |

### Ornamental families

Single-variant decorative fonts — fleurons, manicules, and floral printer's
ornaments. They have no bold/italic variants and render only in PDF and EPUB
(both embed the OTF); DOCX/ODT have no system ornament fallback, so the glyph
passes through in the document font. Glyph access differs per font — see
[`docs/fonts/ornaments.md`](../../../../../docs/fonts/ornaments.md) for the
full glyph reference and shortcut recipes.

| Value | PDF font | EPUB fallback stack |
| ----- | -------- | ------------------- |
| `fourier-ornaments` | Fourier Ornaments | serif |
| `imfell-flowers-1` | IM Fell Flowers 1 | serif |
| `imfell-flowers-2` | IM Fell Flowers 2 | serif |

## Supported styles

| Value | LaTeX | CSS |
| ----- | ----- | --- |
| `italic` | `\itshape` | `font-style: italic` |
| `bold` | `\bfseries` | `font-weight: bold` |
| `bold-italic` | `\bfseries\itshape` | `font-style: italic; font-weight: bold` |

Style declarations live inside the same `\begingroup` scope as the family
switch, so fontspec's NFSS reset does not discard them — unlike the align
handler's outer-scope approach where `\itshape` is silently lost.

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

## Shortcuts

Instead of repeating `.font family="eb-garamond"` throughout a manuscript,
define a named shortcut in `shortcuts.yaml`:

```yaml
garamond:
  class: font
  interface:
    family:
      bind: class.family
      default: eb-garamond
    size:
      bind: class.size
    style:
      bind: class.style

garamond-italic:
  class: garamond
  interface:
    style:
      bind: class.style
      default: italic
```

`garamond` exposes `size` and `style` without defaults — the author can
override them inline. `garamond-italic` chains to `garamond` and pins
`style` to italic while inheriting `family` and `size`.

Then use it directly:

```markdown
::: garamond
This paragraph renders in EB Garamond.
:::

A word in [EB Garamond]{.garamond} inline.
```

## DOCX/ODT rendering

TeX Live fonts are not available in word processors, so DOCX and ODT output
maps each registry font to its **system fallback** — the second quoted value
in the CSS fallback stack (e.g. `"Georgia"` for libertine). The handler sets
`custom-style` attributes that reference pre-generated styles in the
reference document.

Style IDs use a colon-delimited convention with segment order
**font:style:size**:

- Font only: `font:georgia` / `font:georgia:para`
- Style only: `style:italic` / `style:italic:para`
- Size only: `size:0.9` / `size:0.9:para`
- Font + style: `font:georgia:italic` / `font:georgia:italic:para`
- Font + size: `font:georgia:0.9` / `font:georgia:0.9:para`
- Style + size: `style:italic:0.9` / `style:italic:0.9:para`
- Full combo: `font:georgia:italic:0.9` / `font:georgia:italic:0.9:para`

Size IDs use em values (not names) because OOXML style lookups are
case-insensitive — `large`, `Large`, and `LARGE` would collide as names
but `1.2`, `1.44`, and `1.728` are unique.

Size values are computed from the registry's CSS `em` values:

- **DOCX**: half-point integers — `math.floor(em * 24 + 0.5)` (12pt base)
- **ODT**: point values — `em * 12` with one decimal place

The style XML fragments are generated by `scripts/build/generate-font-styles.sh`
from the font registry. Run `make generate-font-styles` to regenerate after
registry changes, then `make generate-reference` to rebuild the reference docs.

## Files

| File | Purpose |
| ---- | ------- |
| `handler.lua` | Emits `\begingroup\<font>\<style>\<size>...\endgroup` (PDF), CSS classes (EPUB), or `custom-style` (DOCX/ODT) |
| `style.css` | CSS rules for `.style-italic`, `.style-bold`, `.style-bold-italic` (EPUB/HTML) |
| `style-docx.xml` | Generated OOXML styles for all font × style × size permutations |
| `style-docx.xml.sha256` | Checksum sidecar for DOCX style generation caching |
| `style-odt.xml` | Generated ODF styles for all font × style × size permutations |
| `style-odt.xml.sha256` | Checksum sidecar for ODT style generation caching |

Font and size definitions — including `\newfontfamily` declarations (PDF),
CSS `font-family` rules, and CSS `font-size` rules (EPUB/HTML) — live in
the shared font registry at `filters/lib/font-registry.lua`. Both this
handler and `keystone.lua` load definitions from that single source.
`keystone.lua` generates and injects all styles into `header-includes`.
