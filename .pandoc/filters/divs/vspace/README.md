# vspace

Inserts explicit vertical whitespace. The div must be empty — any content
triggers a warning. Supports named sizes for convenience and explicit CSS
lengths for full control.

## Usage

```markdown
::: {.vspace size=medium}
:::

::: {.vspace size=1.5em}
:::
```

## Named sizes

| Name     | Value  |
| -------- | ------ |
| `tiny`   | 0.5em  |
| `small`  | 1em    |
| `medium` | 2em    |
| `large`  | 4em    |
| `huge`   | 8em    |

Explicit CSS lengths pass through directly in PDF and EPUB. DOCX and ODT
snap explicit lengths to the nearest named size — these formats are
approximations for editing and feedback.

## Format behavior

| Format    | Output                                             |
| --------- | -------------------------------------------------- |
| PDF       | `\vspace*{<size>}` (starred — forces at page top)  |
| EPUB/HTML | `<div>` with `margin-top` inline style             |
| DOCX      | Spacer paragraph with custom style                 |
| ODT       | Spacer paragraph with custom style                 |

## Files

| File             | Purpose                                        |
| ---------------- | ---------------------------------------------- |
| `handler.lua`    | Size resolution and format-specific output     |
| `style.css`      | Restores `p + p` indent after vspace div       |
| `style-docx.xml` | Paragraph styles for DOCX named sizes          |
| `style-odt.xml`  | Paragraph styles for ODT named sizes           |

## Shortcuts

Define semantic spacing names via shortcuts:

```yaml
title-gap:
  class: vspace
  interface:
    size:
      bind: class.size
      default: 4em

subtitle-gap:
  class: vspace
  interface:
    size:
      bind: class.size
      default: 2em
```

```markdown
::: title-gap
:::

::: subtitle-gap
:::
```
