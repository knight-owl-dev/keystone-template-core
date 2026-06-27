# ifdef

Includes content only when one of the requested build symbols is defined. In
every other case the content is removed entirely. Works with both block-level
fenced divs and inline spans.

Symbols are **build configuration**, not document metadata. They are declared as
named configurations in `project.conf` and selected at publish time — see the
conditional-inclusion guide in the docs. A symbol that is not defined is simply
false (C `#ifdef` semantics); a missing or blank `symbol` attribute is an error.

## Usage

Requires a `symbol` attribute. Multiple symbols are OR-combined — the content is
kept when **any** of them is defined.

Block-level (fenced div):

```markdown
::: {.ifdef symbol="personal"}
A dedication only the private edition should carry.
:::
```

Inline (span):

```markdown
For you[, and only you]{.ifdef symbol="personal"}.
```

Multiple symbols (kept when `personal` **or** `drafts` is defined):

```markdown
::: {.ifdef symbol="personal drafts"}
Working notes.
:::
```

Authors typically hide the attribute behind a shortcut (e.g. a `personal`
shortcut that chains to `ifdef` with a default `symbol`), so the manuscript
reads `::: personal`.

## Files

| File          | Purpose                                                          |
| ------------- | ---------------------------------------------------------------- |
| `handler.lua` | Unwraps div/span content when a symbol is defined; else strips   |
