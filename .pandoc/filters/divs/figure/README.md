# figure

Transforms `::: figure` divs into styled figures with explicit control
over sizing and captioning. Replaces raw Pandoc image attribute syntax
with clean div attributes. The figure handler has no alignment opinion —
compose it with the align handler for positioned figures.

## Usage

### Standalone images

Plain Markdown images are handled automatically — no div wrapper needed:

```markdown
![A descriptive caption](assets/photo.jpg)
```

In PDF, the handler replaces Pandoc's floating `\begin{figure}[htbp]` with
a non-floating `\captionof{figure}{}`, so the image stays where the author
placed it. In EPUB/HTML, standalone images pass through unchanged (base CSS
handles styling).

Width, caption, and cross-reference id all come from standard Pandoc
image syntax:

```markdown
![Caption text](assets/photo.jpg){ width=50% #fig-example }
```

### Basic figure with width (div)

```markdown
::: {.figure width=50%}
![A descriptive caption](assets/photo.jpg)
:::
```

Width is applied as `\includegraphics[width=\linewidth]` inside a
`\begin{minipage}{0.50\textwidth}` in PDF, constraining the caption to
the image width. In EPUB/HTML, `display: table` on the `.figure` div
shrink-wraps the caption to match the image.

### Alignment

The figure handler has no alignment attribute. Compose it with the align
handler by nesting a figure div inside an align div:

```markdown
::: {.align style=center}
::: {.figure width=75%}
![Centered figure](assets/photo.jpg)
:::
:::

::: {.align style=left}
::: {.figure width=50%}
![Left-aligned figure](assets/photo.jpg)
:::
:::
```

This gives every format (including DOCX and ODT) proper alignment via
the align handler's `custom-style` paragraph styles. Shortcuts can
collapse the nesting into a single div.

### Cross-referencing

Use `#` or `id=` syntax for cross-referencing (both set Pandoc's native
`identifier` field):

```markdown
::: {.figure width=50% #fig-architecture}
![System architecture](assets/architecture.png)
:::

::: {.figure width=50% id=fig-overview}
![System overview](assets/overview.png)
:::

See [Figure 1](#fig-architecture) for details.
```

This produces `\label{fig-architecture}` in LaTeX (for `\ref{}`) and
`id="fig-architecture"` in EPUB/HTML (for `[text](#id)` anchor links).

### No width (natural size)

```markdown
::: figure
![Caption text](assets/image.jpg)
:::
```

When no width is specified, the image renders at its natural size.

### Wide caption (escape hatch)

By default, captions are constrained to the image width. Use
`caption-width=full` to opt out and let the caption span the full
text width:

```markdown
::: {.figure width=25% caption-width=full}
![Wide caption under narrow image](assets/photo.jpg)
:::
```

In PDF this skips the minipage wrapper. In EPUB/HTML it adds a
`caption-full` class that restores `display: block`.

### Caption

The caption comes from the image alt text — the `![text here](...)` part.
An empty alt text (`![]()`) omits the caption entirely.

## Width handling

The handler reads width from two sources, in priority order:

1. **Div attribute** — `{.figure width=50%}`
2. **Image attribute** — `![](img){ width=50% }` (fallback)

Percentage values are converted to `\textwidth` fractions for LaTeX
(`50%` → `0.50\textwidth`). Other units (`5cm`, `200px`) pass through
unchanged.

## Shortcuts

Define reusable figure presets in `shortcuts.yaml`:

```yaml
thumbnail:
  class: figure
  interface:
    width:
      bind: class.width
      default: 25%

hero:
  class: figure
  interface:
    width:
      bind: class.width
      default: 100%
```

Then use the shortcut name directly:

```markdown
::: thumbnail
![Book cover](assets/cover.jpg)
:::
```

## Attributes

| Attribute | Values | Default | Effect |
| --------- | ------ | ------- | ------ |
| `width` | CSS length (`50%`, `5cm`) | none | Sets image width |
| `identifier` | `#` or `id=` value | none | Cross-reference label (`el.identifier`) |
| `caption-width` | `full` | (constrained) | Opts out of caption constraining |

## Files

| File | Purpose |
| ---- | ------- |
| `handler.lua` | Finds image, applies width, emits LaTeX figure or CSS classes |
| `style.css` | Shrink-wrap and responsive sizing rules for EPUB/HTML |
