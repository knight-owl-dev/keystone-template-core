# dialog

Transforms a bullet list into stylized dialog lines — em-dashes in PDF,
em-dash-prefixed paragraphs in EPUB/HTML, both wrapped in a `dialog`
container so each format can apply its own visual contract (medskip
breathing room above and below the block, no first-line indent on
inner lines).

## Usage

### Default (tight)

Each `-` bullet becomes a single dialog turn. Continuation rows of a
wrapped turn flow flush with the body margin. Matches the Continental
em-dash convention used in French / Spanish / Russian literature.

```markdown
::: dialog
- Hello?
- It's me.
- I was wondering if after all these years…
:::
```

### Hanging variant

Continuation rows of a wrapped turn hang under the speech instead of
flowing back to the body margin. Common in McCarthy and many French
em-dash conventions — makes turn boundaries pop visually when turns
are long enough to wrap.

```markdown
::: {.dialog style=hanging}
- Hello? She paused, listening for any sound at all from the hallway,
  some footstep or shifting weight, anything to confirm that she had
  heard correctly the first time.
- It's me.
:::
```

In the rendered output, the second-and-later visual rows of the long
first turn sit ~1.5em right of the body margin, while the leading
em-dash of each turn stays flush at the body margin.

## Attributes

| Attribute | Values                 | Description                                              |
| --------- | ---------------------- | -------------------------------------------------------- |
| `style`   | `default` \| `hanging` | `hanging` adds a 1.5em hanging indent on wrapped rows    |

The `style` attribute is optional. Recognized values are `default`
(tight, flush-left wrap — same as omitting the attribute) and
`hanging`. Any other value is treated as `default` and the handler
logs `WARN: dialog: unknown style '<value>'` to stderr — consistent
with the convention used by the align, aside, font, and dropcap
handlers.

## Files

- `handler.lua` — routes each bullet to a `\dialogline` macro (PDF) or
  an em-dash paragraph (EPUB), and wraps the block in a `dialog` Div
- `macros.tex` — defines the four LaTeX macros: `\dialogline`,
  `\dialoglinehang`, `\beforedialogblock`, `\afterdialogblock`
- `style.css` — scopes `.dialog p`, `.dialog + p`, and
  `.dialog.hanging p` for EPUB / HTML
