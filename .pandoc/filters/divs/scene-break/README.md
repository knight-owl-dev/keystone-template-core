# scene-break

Inserts a decorative scene break between sections. Empty divs produce a
default `* * *` ornament; content divs preserve whatever the author writes.
LaTeX output includes page-break protection so the ornament is never
orphaned at the top of a page.

## Usage

```markdown
::: scene-break
:::

::: scene-break
~ ~ ~
:::
```

## Content priority

1. **Div content** — if the div has content, it is used as-is
2. **Default `* * *`** — when the div is empty

Custom ornaments are supplied via shortcut body injection, not handler
attributes. The handler stays simple — content vs. default.

## Files

| File          | Purpose                                                     |
| ------------- | ----------------------------------------------------------- |
| `handler.lua` | Emits `\scenebreak{}` (PDF) or an HTML div (EPUB)           |
| `macros.tex`  | Defines `\scenebreak` with `\nopagebreak` protection        |
| `style.css`   | Centering and `break-inside: avoid` for EPUB/HTML           |

## Shortcuts

Scene breaks pair naturally with shortcut body injection. Define the
ornament once and every usage stays clean:

```yaml
pause:
  class: scene-break
  body: |
    ~ ~ ~
```

```markdown
::: pause
:::
```

The `body` is parsed as Markdown and injected into the empty div before
the handler runs. The handler sees content and uses it as-is.
