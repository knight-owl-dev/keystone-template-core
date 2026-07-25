# aside

Transforms `::: aside` divs into styled callout boxes with a colored left
border and light background tint. Four types are supported: **tip**,
**warning**, **note**, and **example**.

## Usage

### Basic types

```markdown
::: {.aside type="tip"}
Use `make lint` before every commit.
:::

::: {.aside type="warning"}
This operation cannot be undone.
:::

::: {.aside type="note"}
The default port is 8080.
:::

::: {.aside type="example"}
See the following code for a working implementation.
:::
```

### Custom title

Override the default title (which is the capitalized type name):

```markdown
::: {.aside type="warning" title="Caution"}
This operation cannot be undone.
:::
```

Suppress the title entirely with an empty string:

```markdown
::: {.aside type="example" title=""}
No title displayed.
:::
```

### Custom accent color

Override the accent color with a `#rrggbb` hex value:

```markdown
::: {.aside type="note" color="#8b6914"}
Custom accent color for both border and title.
:::
```

### Custom font

For a custom typeface inside a callout, nest a `.font` div:

```markdown
::: {.aside type="tip"}
::: {.font family="eb-garamond"}
Aside body rendered in EB Garamond.
:::
:::
```

A shortcut can compose the two handlers via body injection so authors
don't repeat the nesting:

```yaml
garamond-tip:
  class: aside
  interface:
    type:
      bind: class.type
      default: tip
  body: |
    ::: {.font family="eb-garamond"}
    :::
```

```markdown
::: garamond-tip
Aside body rendered in EB Garamond.
:::
```

### Border suppression

Remove the left border for a lighter look:

```markdown
::: {.aside type="note" border="none"}
Background tint only, no left border.
:::
```

## Attributes

| Attribute     | Values                             | Required | Default              |
| ------------- | ---------------------------------- | -------- | -------------------- |
| `type`        | `tip`, `warning`, `note`, `example`| yes      | --                   |
| `title`       | free text                          | no       | Capitalized type name|
| `color`       | `#rrggbb` hex                      | no       | Per-type default     |
| `border`      | `none`                             | no       | Visible left border  |

## Color palette

| Type    | Accent    | Background | Rationale                                |
| ------- | --------- | ---------- | ---------------------------------------- |
| tip     | `#5b7a5e` | `#f4f7f4`  | Subtle sage green, mid-gray in B&W       |
| warning | `#9e7c4a` | `#f8f5f0`  | Warm amber, distinct luminance from tip  |
| note    | `#4a6a8a` | `#f0f4f8`  | Cool steel blue, standard info tone      |
| example | `#6a5a7a` | `#f5f3f7`  | Muted plum, distinct from others         |

## Shortcuts

Define a named shortcut in `shortcuts.yaml` to avoid repeating attributes:

```yaml
tip:
  class: aside
  interface:
    type:
      bind: class.type
      default: tip

caution:
  class: aside
  interface:
    type:
      bind: class.type
      default: warning
    title:
      bind: class.title
      default: Caution
```

Then use it directly:

```markdown
::: tip
Use `make lint` before every commit.
:::
```

## Files

| File          | Purpose                                                          |
| ------------- | ---------------------------------------------------------------- |
| `handler.lua` | Validates attributes; emits tcolorbox (PDF) or styled div (EPUB) |
| `macros.tex`  | Loads tcolorbox, defines colors and `asidebox` environment       |
| `style.css`   | Left border and tinted background styling for EPUB/HTML          |
