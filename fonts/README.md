# Custom Fonts

Bring your own fonts to Keystone by placing `.otf` or `.ttf` files in this
directory and registering them in `fonts-registry.yaml`. Registered fonts work everywhere
built-in fonts do — as the document font, in `.font` div/span overrides, and
in shortcuts.

📚 For the full typography guide — built-in families, the `.font` shortcut, sizes,
and drop caps — see the manual at <https://keystone.knight-owl.dev/writing/typography/>.

## Quick Start

1. **Place font files** — copy `.otf` or `.ttf` files into this `fonts/` directory
2. **Register** — add an entry to `fonts-registry.yaml` (see examples below)
3. **Use** — reference the font key in `pandoc.yaml` or `.font` divs

## Registry Format

Each entry maps a key (your chosen name) to font metadata:

```yaml
my-serif:
  main:
    file: MySerif-Regular.otf
    bold: MySerif-Bold.otf
    italic: MySerif-Italic.otf
    bold_italic: MySerif-BoldItalic.otf
    license:
      - LICENSE.txt
      - GPL.txt
  css: '"My Serif", "Georgia", serif'
```

**Required:** `main.file` and `css` — an entry without either is skipped.
`main.license` is expected. The rest — `bold`, `italic`, `bold_italic`,
`sans`, `main.path` — are optional.

### The `license` field

The terms your font travels under, as filenames in this directory:

```yaml
main:
  license:
    - LICENSE.txt
    - GPL.txt
```

Always a list, even for a single file. A dual-licensed font names both texts,
and several fonts may name the same file. Leaving the field out warns;
`license: []` says there is nothing to pass on.
Why the texts have to travel, and which formats carry them, is at
<https://keystone.knight-owl.dev/errors/missing-font-license/>.

### The `css` field

The `css` value is a CSS `font-family` stack. The first quoted name becomes
the `@font-face` family name in EPUB; subsequent values are fallbacks for
e-readers that can't load embedded fonts.

```yaml
# Serif with fallbacks
css: '"My Serif", "Georgia", serif'

# Sans-serif with fallbacks
css: '"My Sans", "Helvetica Neue", sans-serif'

# Monospace with fallbacks
css: '"My Mono", "Courier New", monospace'
```

## Common Scenarios

### Serif with all variants

```yaml
my-serif:
  main:
    file: MySerif-Regular.otf
    bold: MySerif-Bold.otf
    italic: MySerif-Italic.otf
    bold_italic: MySerif-BoldItalic.otf
    license:
      - OFL.txt
  css: '"My Serif", "Georgia", serif'
```

### Single-weight display font

```yaml
my-display:
  main:
    file: MyDisplay-Regular.otf
    license:
      - LICENSE.txt
  css: '"My Display", "Georgia", serif'
```

### Serif + sans pair with companion

```yaml
my-serif:
  main:
    file: MySerif-Regular.otf
    bold: MySerif-Bold.otf
    italic: MySerif-Italic.otf
    bold_italic: MySerif-BoldItalic.otf
    license:
      - OFL.txt
  css: '"My Serif", "Georgia", serif'
  sans: my-sans

my-sans:
  main:
    file: MySans-Regular.otf
    bold: MySans-Bold.otf
    license:
      - OFL.txt
  css: '"My Sans", "Helvetica Neue", sans-serif'
```

When `my-serif` is set as the document font, Keystone also sets the
sans-serif font to `my-sans` automatically.

## Referencing User Fonts

### Document font

Set `fontfamily` in `pandoc.yaml` to the registry key:

```yaml
fontfamily: my-serif
```

### Inline overrides

Use `.font` divs and spans with `family=`:

```markdown
::: {.font family="my-serif"}
This paragraph renders in My Serif.
:::

A word in [My Serif]{.font family="my-serif"} inline.
```

Or define a shortcut in `shortcuts.yaml`:

```yaml
my-serif-text:
  class: font
  interface:
    family:
      bind: class.family
      default: my-serif
    size:
      bind: class.size
    style:
      bind: class.style
```

The `family` default pins the typeface. `size` and `style` have no
defaults — absent unless the author provides them inline
(`::: {.my-serif-text size="small" style="italic"}`).

## Validation

Keystone validates font entries at build time:

- **Missing files** — if a declared font file doesn't exist in `fonts/`,
  the entry is skipped with a warning. Check the build output for
  `WARN: user font` messages.
- **Key collisions** — if a user font key matches a built-in font name, the
  built-in wins and a warning is emitted. Choose a different key.
- **Missing required fields** — entries without `main.file` or `css` are
  skipped with a warning.
- **Duplicate filenames** — two entries naming the same file stop the build,
  case ignored. Rename yours, or drop the surplus entry. See
  <https://keystone.knight-owl.dev/errors/duplicate-font-file/>.
- **Undeclared terms** — a font that declares no license, or declares one
  Keystone cannot use, warns. See
  <https://keystone.knight-owl.dev/errors/missing-font-license/>.

## File Requirements

- Font files must be OpenType or TrueType (`.otf`/`.ttf`)
- All font files go flat in this `fonts/` directory (no subdirectories)
