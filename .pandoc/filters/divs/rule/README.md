# rule

Conditional horizontal rule for decorating composed shortcuts. Renders a thin
line when `style=ruled`; returns an empty block list otherwise (div is
silently removed).

This handler is not used directly in Markdown. It is composed into system
shortcuts like `pullquote` via body injection, where the shortcut's `style`
interface attribute routes to `ks-rule.style`.

In shortcut bodies, the div contains a Markdown thematic break (`***`) as a
placeholder to prevent the content injection system from filling the rule div
with author content. `***` is used instead of `---` because `---` inside a
YAML block scalar can be misinterpreted as a document separator by Pandoc's
Markdown parser.

## Attributes

| Attribute | Values             | Required | Default |
| --------- | ------------------ | -------- | ------- |
| `style`   | `ruled`            | Yes      | —       |

When `style` is absent or not `ruled`, the handler returns an empty block list (no output).

## Files

| File             | Purpose                                      |
| ---------------- | -------------------------------------------- |
| `handler.lua`    | Conditional rule based on `style` attribute  |
| `macros.tex`     | `\keystonerule` macro with vertical spacing  |
| `style.css`      | Thin border-top for EPUB/HTML                |
| `style-docx.xml` | Rule paragraph style with bottom border      |
| `style-odt.xml`  | Rule paragraph style with bottom border      |
