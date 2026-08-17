# appendix

Switches the chapters after it — sections on article targets — to appendix
numbering (PDF only); elsewhere the marker unwraps. The label is localized from
the document `lang`. `numbering=` picks the enumerator. See the `handler.lua`
header for the mechanism.

## Usage

```markdown
::: appendix
:::
```

```markdown
::: {.appendix numbering="upper-roman"}
:::
```

`numbering`: `upper-alpha` (default) | `lower-alpha` | `upper-roman` |
`lower-roman` | `arabic`.

## Files

| File          | Purpose                                     |
| ------------- | ------------------------------------------- |
| `handler.lua` | Emits `\appendix` (+ renumbering); PDF only |
| `macros.tex`  | Self-detecting counter-override macro       |
