# container

Pure structural grouping with no visual styling. The handler returns nil
for all formats, deferring to Pandoc's default behavior: EPUB/HTML emits
the element with its classes intact; LaTeX passes content through unchanged.

Designed as a terminal class for shortcuts that need structural grouping
(body injection, nesting) without any handler-specific styling.

## Usage

Block-level (fenced div):

```markdown
::: container
Grouped content with no visual treatment.
:::
```

Inline (span):

```markdown
Some [grouped text]{.container} in a sentence.
```

## Shortcuts

Two paths for shortcut authors:

- **No parameterization** — target `container` for grouping only:

  ```yaml
  wrapper:
    class: container
  ```

- **Custom font needed** — target `font` with `family`/`size` interface:

  ```yaml
  garamond:
    class: font
    interface:
      family:
        bind: class.family
        default: eb-garamond
      size:
        bind: class.size
      style:
        bind: class.style
  ```

Body injection works naturally with `container` as the terminal class:

```yaml
poem-footer:
  class: container
  body: |
    ::: poem-date
    Orem — 2026
    :::

    Written for the Keystone project.
```

## Files

| File          | Purpose                                         |
| ------------- | ----------------------------------------------- |
| `handler.lua` | Returns nil for all formats (no-op passthrough) |
