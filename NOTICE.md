# NOTICE

This project uses the third-party tools, fonts and data files listed below. Each is licensed separately and remains the
property of its respective maintainers.

## Primary Tools and Dependencies

### Pandoc

- License: [GNU General Public License v2 or later](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
- License file: [.licenses/Pandoc.md](.licenses/Pandoc.md)
- Source: [https://pandoc.org/](https://pandoc.org/)
- Included in the Docker image

### LaTeX / TeX Live

- License: [LaTeX Project Public License (LPPL)](https://www.latex-project.org/lppl/)
- Source: [https://www.latex-project.org/](https://www.latex-project.org/)
- Included in the Docker image; per-package licenses vary and are listed under TeX Live Packages

### GNU Make

- License: [GNU General Public License v3 or later](https://www.gnu.org/licenses/gpl-3.0.html)
- Source: [https://www.gnu.org/software/make/](https://www.gnu.org/software/make/)
- Used as part of the build system (not redistributed)

### Lua

- License: [MIT License](https://www.lua.org/license.html)
- Source: [https://www.lua.org/](https://www.lua.org/)
- Used for Pandoc filters; no Lua binary is redistributed

### Docker

- License: [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Source: [https://www.docker.com/](https://www.docker.com/)
- Used to run the engine in an isolated container; not redistributed

### yq

- License: [MIT License](https://github.com/mikefarah/yq/blob/master/LICENSE)
- Source: [https://github.com/mikefarah/yq](https://github.com/mikefarah/yq)
- Included in the Docker image

## System Packages

These are the packages the engine image asks Ubuntu's archive for. Each package's source is
`https://packages.ubuntu.com/<name>`, and its copyright file ships in the image at `/usr/share/doc/<name>/copyright` —
stating the terms outright, or naming a license whose text is at `/usr/share/common-licenses/<license>` in the same
image.

Installing them brings the other packages the distribution says they need. Those are redistributed as part of Ubuntu's
own package set rather than chosen here, and each carries its copyright file the same way.

The image is built on the published `pandoc/minimal` image, redistributed unmodified. Pandoc itself is listed above; the
rest of what that image carries is Ubuntu's package set on the same terms, documented the same way. Packages built from
one source share a copyright file, so a package without one of its own is covered by the file of another built from the
same source.

### Font rendering

How XeLaTeX reaches the fonts installed outside TeX Live.

- [MIT-style permissive (the fontconfig license)](https://gitlab.freedesktop.org/fontconfig/fontconfig/-/blob/main/COPYING):
  fontconfig (font discovery for XeLaTeX), libfontconfig1 (the fontconfig library itself)
- [FreeType License (FTL)](https://gitlab.freedesktop.org/freetype/freetype/-/blob/master/docs/FTL.TXT): libfreetype6
  (the library XeLaTeX renders glyphs with)

### Engine tools

Command-line programs the pipeline runs as subprocesses.

- [GNU Lesser General Public License v2 or later](https://www.gnu.org/licenses/old-licenses/lgpl-2.0.html): librsvg2-bin
  (rsvg-convert, which Pandoc shells out to for SVG to PDF)
- [GNU General Public License v2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html): socat (the client the engine
  uses to reach a hook's Unix socket)

## TeX Live Packages

Installed via `install-tl` and `tlmgr` from a pinned tlnet snapshot, each license as the TeX Live catalogue records it
for that package. Font packages are attributed under Fonts, as are `lm` and `lm-math`, which are installed for the
default and math fonts.

Hyphenation patterns (`hyphen-basque` through `hyphen-swedish`) ship via [hyph-utf8](https://ctan.org/pkg/hyph-utf8).
Each file under `/opt/texlive/texdir/texmf-dist/tex/generic/hyph-utf8/patterns/tex/` in the image carries its own
copyright and license in its header. Terms vary by language, and by file within a language, so no single license covers
the set.

### Base LaTeX / XeLaTeX packages

The general engine and pandoc-template closure, with the language files an author selects via `lang:`. Each package's
source is `https://ctan.org/pkg/<name>`.

- [LPPL 1](https://www.latex-project.org/lppl/): float
- [LPPL 1.2](https://www.latex-project.org/lppl/): upquote
- [LPPL 1.3](https://www.latex-project.org/lppl/): babel, babel-basque, babel-czech, babel-danish, babel-dutch,
  babel-english, babel-finnish, babel-german, babel-hungarian, babel-norsk, babel-polish, babel-portuges, babel-spanish,
  babel-swedish, caption, fancyvrb, hyperref, multirow, setspace, soul, xurl
- [LPPL 1.3c](https://www.latex-project.org/lppl/): amsmath, babel-french, babel-italian, bidi, bookmark, booktabs,
  fontspec, footnotehyper, geometry, graphics, iftex, latex, microtype, parskip, tools, unicode-math, xcolor
- [SIL Open Font License](https://openfontlicense.org/): amsfonts (AMS math symbol fonts)
- Free (permissive, redistribution allowed): ec (EC font metrics, required by soul), framed, ulem
- [X11/MIT License](https://spdx.org/licenses/X11.html): xetex

### Keystone feature packages

The packages Keystone's own features need. Each package's source is `https://ctan.org/pkg/<name>`.

- [LPPL 1.2](https://www.latex-project.org/lppl/): endnotes (collected endnotes, gathered at the end of a document),
  psnfss (provides pifont.sty for Dingbat symbols)
- [LPPL 1.3](https://www.latex-project.org/lppl/): fancyhdr (page layout, via page-layout-fancyhdr.tex), fvextra
  (fancyvrb extensions for code listings), tcolorbox (colored boxes for callout and aside blocks), tikzfill (fill
  patterns, a tcolorbox skins dependency)
- [LPPL 1.3c](https://www.latex-project.org/lppl/): draftwatermark (watermark overlay for draft documents), hyperxmp
  (embeds keywords and metadata into the PDF Info dict and XMP stream), koma-script (KOMA-Script document classes, plus
  scrlayer-scrpage.sty), lettrine (drop caps), lineno (line numbering, used by pandoc), pdfcol (color stacks, a
  tcolorbox skins dependency), ragged2e (hyphenation-preserving ragged-right)

## Fonts

These font families ship in the Keystone Docker image, each with its own license text beside its font files under
`/opt/keystone/fonts/`. Each is an independent work distributed alongside Keystone (mere aggregation under GPL Section
2), and all permit redistribution and EPUB embedding.

### Linux Libertine / Linux Biolinum

- License: GNU General Public License v2.0 or later with Font Exception, OR SIL Open Font License 1.1 (dual-licensed)
- SPDX: `GPL-2.0-or-later WITH Font-exception-2.0 OR OFL-1.1`
- Source: [https://libertine-fonts.org/](https://libertine-fonts.org/)
- Copyright: Philipp H. Poll and contributors
- Included in the Docker image

### DejaVu

- License: Bitstream Vera License (with DejaVu addendum)
- SPDX: `Bitstream-Vera`
- Source: [https://dejavu-fonts.github.io/](https://dejavu-fonts.github.io/)
- Copyright: Bitstream Inc., DejaVu authors
- Included in the Docker image

### Latin Modern

Latin Modern Roman and the Latin Modern Math font (latinmodern-math).

- License: GUST Font License (compatible with LPPL 1.3c)
- SPDX: `LPPL-1.3c`
- Source:
  [https://www.gust.org.pl/projects/e-foundry/latin-modern](https://www.gust.org.pl/projects/e-foundry/latin-modern)
- Copyright: GUST e-foundry
- Included in the Docker image

### TeX Gyre Family

Pagella, Termes, Heros, Schola, Bonum, Adventor, Cursor.

- License: GUST Font License (compatible with LPPL 1.3c)
- SPDX: `LPPL-1.3c`
- Source: [https://www.gust.org.pl/projects/e-foundry/tex-gyre](https://www.gust.org.pl/projects/e-foundry/tex-gyre)
- Copyright: GUST e-foundry
- Included in the Docker image

### EB Garamond

- License: SIL Open Font License 1.1
- SPDX: `OFL-1.1`
- Source: [https://github.com/georgd/EB-Garamond](https://github.com/georgd/EB-Garamond)
- Copyright: Georg Duffner, Octavio Pardo
- Included in the Docker image

### Noto Sans Mono

- License: SIL Open Font License 1.1
- SPDX: `OFL-1.1`
- Source: [https://github.com/notofonts/latin-greek-cyrillic](https://github.com/notofonts/latin-greek-cyrillic)
- Copyright: The Noto Project Authors (Google)
- Included in the Docker image

### Source Code Pro

- License: SIL Open Font License 1.1
- SPDX: `OFL-1.1`
- Source: [https://github.com/adobe-fonts/source-code-pro](https://github.com/adobe-fonts/source-code-pro)
- Copyright: Adobe Systems Incorporated
- Included in the Docker image

### Fourier Ornaments

Ornamental glyph font (`FourierOrns`) from the `fourier` package.

- License: LaTeX Project Public License 1.3c
- SPDX: `LPPL-1.3c`
- Source: [https://ctan.org/pkg/fourier](https://ctan.org/pkg/fourier)
- Copyright: Michel Bovani
- Included in the Docker image

### IM Fell Flowers

Floral printer's ornament fonts (`FeFlow1`, `FeFlow2`) from the `imfellenglish` package — a digital revival of the
17th-century IM Fell types.

- License: SIL Open Font License 1.1
- SPDX: `OFL-1.1`
- Source: [https://ctan.org/pkg/imfellenglish](https://ctan.org/pkg/imfellenglish)
- Copyright: Igino Marini (digital revival)
- Included in the Docker image

## Citation Styles (CSL)

These Citation Style Language (CSL) styles ship in the Keystone Docker image. Each is an independent data file
distributed alongside Keystone (mere aggregation under GPL Section 2) and is redistributed unmodified.

### Chicago Manual of Style

18th edition, author-date and notes-and-bibliography variants.

- License: [Creative Commons Attribution-ShareAlike 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
- Source: [https://github.com/citation-style-language/styles](https://github.com/citation-style-language/styles)
- Included in the Docker image
