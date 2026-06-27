# ifndef

Includes content only when **none** of the requested build symbols are defined —
the inverse of [`ifdef`](../ifdef/README.md). Works with both block-level fenced
divs and inline spans.

Symbols are **build configuration**, not document metadata. They are declared as
named configurations in `project.conf` and selected at publish time — see the
conditional-inclusion guide in the docs. A symbol that is not defined is simply
false (C `#ifndef` semantics); a missing or blank `symbol` attribute is an error.

## Usage

Requires a `symbol` attribute. Multiple symbols are OR-combined — the content is
removed when **any** of them is defined (kept only when all are absent).

Block-level (fenced div):

```markdown
::: {.ifndef symbol="personal"}
A note shown in every edition except the private one.
:::
```

Inline (span):

```markdown
Thanks for reading[ this public edition]{.ifndef symbol="personal"}.
```

A common pairing is gating the same region two ways — `ifdef` for the private
edition, `ifndef` for the public one.

## Files

| File          | Purpose                                                          |
| ------------- | ---------------------------------------------------------------- |
| `handler.lua` | Unwraps div/span content when no symbol is defined; else strips  |
