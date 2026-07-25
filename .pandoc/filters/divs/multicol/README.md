# multicol

Wraps content in a multi-column layout. PDF output uses the `multicol`
LaTeX package; EPUB/HTML output uses CSS `column-count`.

## Usage

### Default two-column layout

```markdown
::: multicol
First column content flows here. When the text reaches the midpoint
of the page width, it wraps to the second column automatically.
:::
```

### Custom column count

The `cols` attribute sets the number of columns (2-4, default 2):

```markdown
::: {.multicol cols=3}
Content flows across three columns. Useful for compact reference
lists, glossaries, or index-style layouts.
:::
```

## Attributes

| Attribute | Values | Required | Default |
| --------- | ------ | -------- | ------- |
| `cols`    | 2-4    | No       | 2       |

Invalid values (non-numeric, fractional, or outside the 2-4 range) produce
a warning and the div is returned unchanged.

## Shortcuts

Define a named shortcut in `shortcuts.yaml` to avoid repeating attributes:

```yaml
three-col:
  class: multicol
  interface:
    cols:
      bind: class.cols
      default: 3
```

Then use it directly:

```markdown
::: three-col
Content in three columns.
:::
```

## Files

| File          | Purpose                                      |
| ------------- | -------------------------------------------- |
| `handler.lua` | Column count validation; emits LaTeX or HTML |
| `macros.tex`  | Loads the `multicol` package for LaTeX       |
| `style.css`   | Default two-column CSS for EPUB/HTML         |
