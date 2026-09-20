# 🧱 Keystone

> Simple things should be simple, and difficult things should be possible.

Keystone turns a Markdown manuscript into professional-quality **PDF, EPUB,
DOCX, and ODT** — one source, every format. You write plain text, pick a target
(`book`, `report`, `article`), and Keystone typesets the result with
[Pandoc](https://pandoc.org/), [XeLaTeX](https://www.latex-project.org/), and a
[Docker](https://www.docker.com/) image you build yourself. Your book stays
diff-able, reviewable, and under version control. No LaTeX expertise is
required: you need [Docker](https://www.docker.com/) and
[GNU Make](https://www.gnu.org/software/make/).

📚 **The author's manual is at <https://keystone.knight-owl.dev/>** — writing,
configuration, and the shortcut reference all live there.

## This template

`core` is the full Keystone template: the entire engine ships inside your project
under `.pandoc/` — `publish.sh`, the Lua filters, the handlers, the metadata
bundles — and the Docker image is built locally rather than pulled. Nothing is
hidden, so there is nothing to reverse-engineer. Choose it to understand the
engine, customize it, or fork it.

If you only want to write, [`keystone-template-core-slim`](https://github.com/knight-owl-dev/keystone-template-core-slim)
runs the same engine from a prebuilt signed image, with faster builds and nothing
to maintain. The two produce identical output — see
[Choosing a template](https://keystone.knight-owl.dev/templates/).

## Quick start

**1. Make it yours.** Use the **Use this template** button on GitHub, or download
the source and put it under whatever version control you prefer.

**2. Configure.** [`project.conf`](project.conf) names the project and sets how
it builds; [`pandoc.yaml`](pandoc.yaml) holds the document metadata — title,
author, target, page layout, fonts, cover image.

**3. Write.** Markdown goes in `manuscript/`, images in `assets/`, and
[`publish.txt`](publish.txt) lists the files in reading order. Your own markup
vocabulary goes in [`shortcuts.yaml`](shortcuts.yaml).

**4. Build.**

```shell
make publish
```

The finished book lands in `artifacts/`. Expect the first run to be long: it
builds the image, which installs TeX Live from source. The
[Quickstart](https://keystone.knight-owl.dev/getting-started/quickstart/) walks
the same ground for `core-slim`, which pulls a prebuilt image instead.

## Commands

```shell
make image                # build the runtime image locally
make publish              # build a PDF (default)
make publish format=epub  # pdf | epub | docx | odt
make all                  # PDF, EPUB, and DOCX
make help                 # the full list of targets
```

The publish targets depend on `make image`, so the first build creates the image
and later ones reuse its cached layers — see
[the runtime image](https://keystone.knight-owl.dev/engine/runtime-image/). You
build it yourself, so there is no published image signature to check; the
template download is signed either way, per
[Verifying your download](https://keystone.knight-owl.dev/getting-started/verifying/).

## The engine, in your project

The runtime is here to be read and changed.
[The engine](https://keystone.knight-owl.dev/engine/) documents how a build works
and where the seams are.

## Learn more

- [`core`](https://keystone.knight-owl.dev/core/) — this template in full:
  every command, its options, and how to move onto a newer release.
- [Upgrading your project](https://keystone.knight-owl.dev/upgrading/) — what
  changes when a new Keystone release lands.
- [Writing](https://keystone.knight-owl.dev/writing/manuscript/) — dialogue,
  scene breaks, figures, typography, and every other authoring task.
- [Book metadata](https://keystone.knight-owl.dev/configuration/metadata/) —
  everything `pandoc.yaml` controls.
- [Project settings](https://keystone.knight-owl.dev/configuration/project-conf/)
  — everything `project.conf` controls.
- [Shortcuts](https://keystone.knight-owl.dev/shortcuts/) — Keystone's styling
  API, and how to build your own vocabulary on top of it.
- [Project anatomy](https://keystone.knight-owl.dev/getting-started/project-anatomy/)
  — what each file and directory is for.
- [Importing a draft](https://keystone.knight-owl.dev/getting-started/import/) —
  bring an existing DOCX, ODT, or RTF into Markdown.
- [keystone-hello-world](https://github.com/knight-owl-dev/keystone-hello-world)
  — a complete sample project, if you would rather read one than a guide.

## License

Keystone is released under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/): use it to
make your own books, share and adapt it under the same terms, but do not
repackage it as a commercial product. The binding terms are in
[`.licenses/Keystone.md`](.licenses/Keystone.md); the summary, and the notices
for Pandoc, LaTeX, and the bundled fonts, are in
[License & attribution](https://keystone.knight-owl.dev/license/).

Keystone is built on Pandoc, LaTeX, Docker, GNU Make, and Lua — freely given work
that made all of this possible. Keep the `.licenses/` and `NOTICE.md` notices in
place.

Developed and maintained by [Knight Owl LLC](https://github.com/knight-owl-dev).
