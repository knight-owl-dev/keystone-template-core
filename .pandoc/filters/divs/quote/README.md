# quote

Wraps content in a narrowed (indented) block with left and right margins.
A pure structural wrapper with no attributes — the block-level equivalent
of indentation.

This handler is not typically used directly in Markdown. It is composed
into system shortcuts like `epigraph` via body injection. In composed
shortcuts, `quote` should be an **inner** handler (not the outer class)
so that other handlers' LaTeX wrapping (e.g. font's `\begingroup`) lands
outside the `quote` environment — otherwise the wrapping triggers
paragraph indentation inside the LaTeX `quote` list context.

LaTeX uses a `keystonequote` environment (defined in `macros.tex`) that
wraps the built-in `quote` with vertical spacing. Content is serialized
via `kast.latex.blocks()` into a single RawBlock (same pattern as `aside`).

## Attributes

None. The handler always applies when matched.

## Known limitations

**LaTeX paragraph indent when outer**: If `quote` is the outermost handler
in a composed shortcut (`class: ks-quote`), any inner handler that injects
LaTeX RawBlocks (e.g. font's `\begingroup`) will create a phantom paragraph
inside the `quote` list context, triggering `\parindent` on the first
visible line. Fix: make `quote` an inner handler and place the other handler
as the outer class. The `epigraph` shortcut demonstrates this — font is
outer (`class: ks-font`), quote is in the body.

**DOCX/ODT composition**: When `quote` is nested inside a composed
shortcut, Pandoc's DOCX and ODT writers do not propagate the
`custom-style="Quote"` through nested handler divs. The `Quote` paragraph
style is present in the reference document but does not appear in the
final output. The style works correctly when `quote` is used as a
standalone div (`::: quote`).

## Files

| File             | Purpose                                           |
| ---------------- | ------------------------------------------------- |
| `handler.lua`    | Wraps content in indented block per format        |
| `macros.tex`     | `keystonequote` environment (quote + vspace)      |
| `style.css`      | Left/right margins for EPUB/HTML                  |
| `style-docx.xml` | Quote paragraph style with left/right indentation |
| `style-odt.xml`  | Quote paragraph style with left/right margins     |
