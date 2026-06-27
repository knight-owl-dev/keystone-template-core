# NOTICE

This project makes use of the following third-party tools and formats, which are not bundled with the template but are essential to its operation. Each is licensed separately and remains the property of its respective maintainers.

## Primary Tools and Dependencies

### Pandoc

- License: [GNU General Public License v2 or later](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
- Source: [https://pandoc.org/](https://pandoc.org/)
- Included in the Docker image
- License file: [.licenses/Pandoc.md](.licenses/Pandoc.md)

### LaTeX / TeX Live

- License: [LaTeX Project Public License (LPPL)](https://www.latex-project.org/lppl/)
- Source: [https://www.latex-project.org/](https://www.latex-project.org/)
- Included in the Docker image (base distribution via `pandoc/latex`, additional packages via `tlmgr`)

### GNU Make

- License: [GNU General Public License v3 or later](https://www.gnu.org/licenses/gpl-3.0.html)
- Source: [https://www.gnu.org/software/make/](https://www.gnu.org/software/make/)
- Used as part of the build system (not redistributed)

### Lua

- License: [MIT License](https://www.lua.org/license.html)
- Source: [https://www.lua.org/](https://www.lua.org/)
- Used for optional Pandoc filters
- No Lua binaries are included in this project

### Docker

- License: [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Source: [https://www.docker.com/](https://www.docker.com/)
- Used to run Pandoc/LaTeX in an isolated container
- This project does not bundle or distribute Docker itself

### yq

- License: [MIT License](https://github.com/mikefarah/yq/blob/master/LICENSE)
- Source: [https://github.com/mikefarah/yq](https://github.com/mikefarah/yq)
- Included in the Docker image

## TeX Live Packages

The following packages are installed via `tlmgr` on top of the `pandoc/latex`
base image. All are licensed under the LaTeX Project Public License (LPPL).
Font packages installed via `tlmgr` are listed separately under Fonts.

### draftwatermark

- License: [LPPL 1.3c or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/draftwatermark](https://ctan.org/pkg/draftwatermark)
- Included in the Docker image

### endnotes

- License: [LPPL 1.2](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/endnotes](https://ctan.org/pkg/endnotes)
- Included in the Docker image

### fvextra

- License: [LPPL 1.3a or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/fvextra](https://ctan.org/pkg/fvextra)
- Included in the Docker image

### hyperxmp

- License: [LPPL 1.3c or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/hyperxmp](https://ctan.org/pkg/hyperxmp)
- Included in the Docker image

### koma-script

- License: [LPPL 1.3c or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/koma-script](https://ctan.org/pkg/koma-script)
- Included in the Docker image

### lettrine

- License: [LPPL 1.3c or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/lettrine](https://ctan.org/pkg/lettrine)
- Included in the Docker image

### lineno

- License: [LPPL 1.3a or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/lineno](https://ctan.org/pkg/lineno)
- Included in the Docker image

### pdfcol

- License: [LPPL 1.3c or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/pdfcol](https://ctan.org/pkg/pdfcol)
- Included in the Docker image

### ragged2e

- License: [LPPL 1.3c or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/ragged2e](https://ctan.org/pkg/ragged2e)
- Included in the Docker image

### tcolorbox

- License: [LPPL 1.3c or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/tcolorbox](https://ctan.org/pkg/tcolorbox)
- Included in the Docker image

### tikzfill

- License: [LPPL 1.3c or later](https://www.latex-project.org/lppl/)
- Source: [https://ctan.org/pkg/tikzfill](https://ctan.org/pkg/tikzfill)
- Included in the Docker image

## Fonts

The following font families are included in the Keystone Docker image. Each is
an independent work distributed alongside Keystone (mere aggregation under
GPL Section 2). All permit redistribution and EPUB embedding.

### Linux Libertine / Linux Biolinum

- License: GPL-2.0-or-later with Font Exception OR OFL-1.1 (dual-licensed)
- Source: [https://libertine-fonts.org/](https://libertine-fonts.org/)
- Included in the Docker image
- License file: [.licenses/Fonts.md](.licenses/Fonts.md)

### DejaVu

- License: Bitstream Vera License
- Source: [https://dejavu-fonts.github.io/](https://dejavu-fonts.github.io/)
- Included in the Docker image
- License file: [.licenses/Fonts.md](.licenses/Fonts.md)

### Latin Modern

- License: GUST Font License (LPPL-1.3c)
- Source: [https://www.gust.org.pl/projects/e-foundry/latin-modern](https://www.gust.org.pl/projects/e-foundry/latin-modern)
- Included in the Docker image
- License file: [.licenses/Fonts.md](.licenses/Fonts.md)

### TeX Gyre Family

Pagella, Termes, Heros, Schola, Bonum, Adventor, Cursor.

- License: GUST Font License (LPPL-1.3c)
- Source: [https://www.gust.org.pl/projects/e-foundry/tex-gyre](https://www.gust.org.pl/projects/e-foundry/tex-gyre)
- Included in the Docker image
- License file: [.licenses/Fonts.md](.licenses/Fonts.md)

### EB Garamond

- License: SIL Open Font License 1.1
- Source: [https://github.com/georgd/EB-Garamond](https://github.com/georgd/EB-Garamond)
- Included in the Docker image
- License file: [.licenses/Fonts.md](.licenses/Fonts.md)

### Fourier Ornaments

Ornamental glyph font (FourierOrns) from the fourier package.

- License: LaTeX Project Public License 1.3c
- Source: [https://ctan.org/pkg/fourier](https://ctan.org/pkg/fourier)
- Included in the Docker image
- License file: [.licenses/Fonts.md](.licenses/Fonts.md)

### IM Fell Flowers

Floral printer's ornaments (FeFlow1, FeFlow2) from the imfellenglish package.

- License: SIL Open Font License 1.1
- Source: [https://ctan.org/pkg/imfellenglish](https://ctan.org/pkg/imfellenglish)
- Included in the Docker image
- License file: [.licenses/Fonts.md](.licenses/Fonts.md)

## Citation Styles (CSL)

The following Citation Style Language (CSL) styles are included in the Keystone
Docker image to format citations and bibliographies via Pandoc citeproc. Each is
an independent data file distributed alongside Keystone (mere aggregation under
GPL Section 2) and is redistributed unmodified.

### Chicago Manual of Style

Chicago Manual of Style 18th edition — author-date and notes-and-bibliography
variants, from the Citation Style Language project.

- License: [Creative Commons Attribution-ShareAlike 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
- Source: [https://github.com/citation-style-language/styles](https://github.com/citation-style-language/styles)
- Included in the Docker image

---

This project is grateful for the incredible work of these communities and individuals. Their tools are the foundation on which Keystone is built.
