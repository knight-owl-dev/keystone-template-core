# source

Renders an attribution line from a `text` attribute. The handler prepends
an em-dash and renders the text right-aligned in upright (non-italic) style.
Returns an empty block list when the `text` attribute is absent — the div is
silently removed.

This handler is not used directly in Markdown. It is composed into system
shortcuts like `pullquote` and `epigraph` via body injection, where the
shortcut's `source` interface attribute routes to `ks-source.text`.

## Attributes

| Attribute | Values      | Required | Default |
| --------- | ----------- | -------- | ------- |
| `text`    | plain text  | Yes      | —       |

When `text` is absent, the handler returns an empty block list (no output).

## Files

| File | Purpose |
| --- | --- |
| `handler.lua` | Reads `text` attribute; emits attribution line |
| `macros.tex` | `\keystonesource` macro (right-aligned, em-dash) |
| `style.css` | Right-aligned, smaller font for EPUB/HTML |
| `style-docx.xml` | Source paragraph style for DOCX |
| `style-odt.xml` | Source paragraph style for ODT |
