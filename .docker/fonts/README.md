<!-- cspell:ignore LICENCE RELOC -->

# Font Extraction

The image ships a slim font tree: the files the registry names, and the license
each travels under. Whole font packages would be many times the size — most of
what they carry is pdfLaTeX-era dead weight nothing here renders with — so the
throwaway `fonts` stage assembles the tree, and only that tree reaches the
image.

| File | What it does |
| --- | --- |
| `extract-fonts.sh` | copies the registry's font files out of the TeX Live tree |
| `extract-font-licenses.sh` | puts each family's license beside its fonts |
| `licenses.copy.txt` | says where each license comes from and where it lands |

A font license attaches its terms to the binaries, and the binaries are what
the image redistributes, so the terms travel with them. `NOTICE.md` names the
families and their terms; that is attribution. TeX Live's own `LICENSE.TL`
describes how the distribution is licensed and points at per-package terms.

These rows have a second reader:
[`.pandoc/filters/lib/font-registry.lua`](../../.pandoc/filters/lib/font-registry.lua)
names the same files in each entry's `main.license`, because an EPUB carries a
whole font file and its terms travel with it
(<https://keystone.knight-owl.dev/errors/missing-font-license/>). A destination
changed here has to change in the entry that names it; the build refuses one
the registry declares and no row staged.

## Adding a Font Family

1. Add the TeX Live package to
   [`packages/tlmgr/fonts.packages`](../packages/tlmgr/fonts.packages).
2. Find its files, below, and point the `path` of its
   [`.pandoc/filters/lib/font-registry.lua`](../../.pandoc/filters/lib/font-registry.lua)
   entry at `/opt/keystone/fonts/<subtree>`.
3. Find its license, below, and add a row per license file to
   `licenses.copy.txt`, then name the same files in the registry entry's
   `main.license`.
4. Record the family in your project's `NOTICE.md`.

The default text and math fonts are installed by the `base` stage instead;
their declaration is
[`packages/tlmgr/base-fonts.packages`](../packages/tlmgr/base-fonts.packages).

## Inspecting a Candidate Package

The package is installed nowhere yet, so the work happens in a scratch
container off `base` — the stage with a working `tlmgr`, pinned to the same
snapshot the image builds from. From the directory holding `.docker/`:

```shell
docker build --target base -t keystone-base:local -f .docker/Dockerfile .
docker run --rm -it keystone-base:local bash
tlmgr install --with-doc <package>
```

`--with-doc` because the stage installs without doc files, and a license is one.
Install without it and there is nothing to read — `tlmgr info --list` reports an
installed package's own files, so it stops naming the license too.

Nothing ships from that container; the sections below read what it now holds.

## Finding a Package's Files

```shell
find /opt/texlive/texdir/texmf-dist/fonts \( -name '*.otf' -o -name '*.ttf' \) \
  | grep -i <family>
```

The path after `…/texmf-dist/fonts/` is the subtree, e.g.
`opentype/public/myfont/`, and the registry `path` is `/opt/keystone/fonts/`
plus that subtree. Note the filenames of the regular, bold, italic and
bold-italic variants; most families are `.otf`, some — DejaVu among them —
`.ttf`.

## Locating a License

`tlmgr info --list <package>` prints the package's files grouped by type. The
license is among its doc files, under whatever name upstream chose: `LICENSE`,
`LICENCE.txt`, `OFL.txt`, `COPYING`, `GPL.txt`, `LICENSE_OFL.txt`,
`GUST-FONT-LICENSE.TXT` — case included: `lm` spells it `.TXT`, `lm-math`
`.txt`. Most sit under `doc/fonts/<package>/`, though `sourcecodepro` files its
under `doc/latex/`.

Do not take it from `tlmgr info`'s `cat-license`, which reports the CTAN
package's license rather than the font's: `dejavu` comes back `lppl1.3` where
the fonts are under the Bitstream Vera License.

Some packages need a judgment call:

- **A family whose terms span files.** `libertine` is dual-licensed:
  `LICENCE.txt` summarizes both halves, and `GPL.txt` is the only full text the
  package carries. Declare every file it has.
- **A package that ships no license file.** `fourier` states its terms in a
  section of its `README`, so the `README` is what has to travel. A package
  that states them nowhere cannot ship: with nothing to copy there is nothing
  to redistribute under.

## Writing a Row

A row names both ends, the source with the listing's `RELOC/doc/` prefix
dropped: `RELOC/doc/fonts/dejavu/LICENSE` is declared
`fonts/dejavu/LICENSE  truetype/public/dejavu/LICENSE`.

The destination has to sit in a directory the registry stages fonts into, which
is what puts the terms beside the binaries they cover; the build refuses any
other path. Its name is the image's own, so a snapshot that renames a file
upstream changes the row's left side and nothing that ships. One name is not
ours to choose: libertine's `LICENCE.txt` points at its `GPL.txt`, the only file
here that another one names.

## When a Row Stops Matching

`extract-font-licenses.sh` refuses the build and names what to fix — a license
the package does not carry, say, or a staged family whose terms the registry
names nowhere. Its own header lists what it holds.

Advancing `TL_SNAPSHOT` is what usually makes a row stale: upstream renames a
license file or moves it, and the row still names the old path. Locate the file
again in the new snapshot and update the row.

A license reported absent can also mean the package arrived ahead of its own
install, as a dependency of the base closure — `--with-doc` adds nothing to a
package already present, so such a family belongs in `base-fonts.packages`.

Nothing catches a license whose text changed under a name that did not. The
copy follows the snapshot; what the family is recorded as carrying does not. A
snapshot bump is when to re-read the terms, not only the filenames.
