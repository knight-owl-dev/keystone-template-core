# no-indent

Suppresses first-line paragraph indentation within its scope. Useful for
dedications, poetry, title pages, or any content where paragraph indentation
is out of place. Naturally a no-op when indent is globally off (sets 0 to 0
in LaTeX / overrides nothing in CSS).

## Usage

```markdown
::: no-indent
This paragraph will not be indented.

Neither will this one.
:::
```

Compose with other handlers for richer formatting:

```markdown
::: no-indent
::: {.align style="center"}
*For E.*

*Who taught me to see.*
:::
:::
```

## Format behavior

| Format    | Output                                                  |
| --------- | ------------------------------------------------------- |
| PDF       | `\begingroup\setlength{\parindent}{0pt}...\endgroup`    |
| EPUB/HTML | Sets `.no-indent` class on the div                      |
| DOCX/ODT  | Content unwrap — review format, not worth per-section   |

## Files

| File          | Purpose                                              |
| ------------- | ---------------------------------------------------- |
| `handler.lua` | Format-specific indentation suppression              |
| `style.css`   | `.no-indent p + p { text-indent: 0; }` for EPUB/HTML |
