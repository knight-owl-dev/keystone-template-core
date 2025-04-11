# 🧱 Keystone

> Simple things should be simple, and difficult things should be possible.

Keystone is a minimalist book publishing template that helps authors not only get to the finish line faster, but think more clearly about structure, tooling, and ownership.

It gives you a reproducible build system, clean separation of layout and content, and a dev-friendly workflow with just enough automation to stay out of your way.

Built with [Make](https://www.gnu.org/software/make/), [Markdown](https://www.markdownguide.org/getting-started/), [Pandoc](https://pandoc.org/), [LaTeX](https://www.latex-project.org/), and [Docker](https://www.docker.com/).

## Features

- ✍️ Write in plain [Markdown](https://www.markdownguide.org/getting-started/)
- 🚜 Build clean, timestamped artifacts via [`make`](https://www.gnu.org/software/make/)
- 📂 Inject metadata via [.env](.env) — control title, author, layout, keywords, and PDF formatting
- ⚖️ Powered by [Pandoc](https://pandoc.org/), [LaTeX](https://www.latex-project.org/), and [Docker](https://www.docker.com/)
- ⛏️ Keeps guts (like `.pandoc/`, [`publish.sh`](.pandoc/publish.sh)) out of your way
- ⌨️ Editor-agnostic: works from any terminal

**Why Pandoc?** It’s flexible, scriptable, and supports features like table of contents generation, custom styling, page breaks, heading levels, bibliography, footnotes, and cross-referencing — everything you need to produce a structured, professional-quality document.

### Markdown Formatting Capabilities

Keystone supports advanced formatting through [Pandoc's fenced div syntax](https://pandoc.org/MANUAL.html#extension-fenced_divs), using the form `::: div-name` and `:::`.

This lets you apply custom styling or behavior by wrapping sections of content in named blocks — like `::: dialog` for character conversations.

For example, you can create a dialog block like this:

```markdown
::: dialog

- Who’s there?
- Just the wind.
:::
```

> 💡 No special syntax is needed for prose-style dialog; just write your dialog using standard Markdown. The output will format it as prose.

For more examples, take a look at the sample [chapter-2.md](.keystone/sample/chapters/chapter-2.md) file.

## Quick Start

**1. Use this repo as a template:** Click the “Use this template” button on GitHub to create your own book project (e.g., `my-book`), then:

```shell
git clone git@github.com:yourname/my-book.git
cd my-book
```

**2. Edit your metadata:** Set your project name, book's title, author, description, etc. This file is version-controlled and used at build time.

```shell
nano .env
```

**3. Add content:** Write your book in [Markdown](https://www.markdownguide.org/getting-started/). Keystone uses a simple folder structure to keep things organized:

```text
chapters/      # Your main content, e.g., introduction.md, chapter-1.md
appendix/      # Optional extras, e.g., appendix-a.md
assets/        # Images, cover.png, etc.
```

The [publish.txt](publish.txt) file defines the exact order of files to be included in the output. Edit it to rearrange chapters or exclude drafts without renaming source files.

For example, create and add these files to [publish.txt](publish.txt):

```text
chapters/introduction.md
chapters/chapter-1.md
appendix/appendix-a.md
```

>💡 Pandoc numbers all top-level sections automatically.

Because of this, avoid including chapter numbers in your Markdown titles — they’re applied during export. This keeps the source files clean and makes renumbering painless.

To exclude specific headings (e.g. in a preface or appendix), use the `{.unnumbered}` attribute on each header in the file:

```markdown
# Preface {.unnumbered}
## Introduction {.unnumbered}
```

**4. Build your book:**

```shell
make all
```

Outputs will appear in the [artifacts/](/artifacts/) folder. For example, if you set `KEYSTONE_PROJECT=hello-world` in [.env](.env), the output will be:

```text
artifacts/
├── hello-world-book-20250405.pdf
├── hello-world-book-20250405.epub
└── ...
```

## Environment Configuration (`.env`)

All project metadata and publishing options live in the `.env` file.

This includes things like:

- Project title, subtitle, author, keywords
- Page size and margin settings for PDF builds
- Build metadata like date and description

The `.env` file is sourced by `publish.sh` and passed through to Pandoc. You can safely customize it to match your book or document.

> For examples and advanced options, see the commented block in `.env`.

### Bootstrap with Sample Content

You can install example content (`chapters`, `appendix`, and `publish.txt`) by running:

```shell
make sample
```

> ⚠️ This only works if [publish.txt](publish.txt) is effectively empty — containing **no publishable file entries**, only comments or blank lines.

This gives you a complete working example of a Keystone book, useful for experimenting or exploring the system.

To undo the sample installation and return to a clean state:

```shell
make reset
```

> ❌ This restores the repo to the last committed state (**be sure to back up any changes first**).

### Keystone Template Variants

This is the core Keystone template — the editor-agnostic version.

- 🛠️ No IDE-specific tooling
- 📄 Works with any text editor
- 🔧 Built for use directly from the terminal using make

Looking for a more integrated experience?

🎯 Use one of the editor-optimized templates:

- `keystone-template-vscode` (coming soon) – VS Code tasks, previews, and Markdown extensions
- More templates for other editors and IDEs are planned

### Requirements

- [Git](https://git-scm.com/)
- [Docker](https://www.docker.com/)
- [GNU Make](https://www.gnu.org/software/make/)
- Learn the [Markdown](https://www.markdownguide.org/basic-syntax/) basic syntax
- Use any editor or IDE of your choice

### Cross-Platform Compatibility & Line Endings

You can edit files in this project using any operating system and any text editor — whether you're on Windows (`CRLF`), macOS (`LF`), or Linux (`LF`). The Docker-based build process will take care of normalizing line endings automatically.

#### Core Autocrlf Setting

Check your current setting:

```shell
git config --get core.autocrlf
```

On Windows, make sure your `core.autocrlf` is set to `true` and update if necessary:

```shell
git config --global core.autocrlf true
```

On macOS and Linux, make sure it is set to `input` and update if necessary:

```shell
git config --global core.autocrlf input
```

### Using the GNU Make Utility

This project has the [Makefile](Makefile) to simplify the workflow, which requires [Docker Desktop](https://www.docker.com/products/docker-desktop/).

> 💡 If running on Windows, install [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) to access the GNU Make utility or even better - open this project in WSL for the best experience. See [this](https://learn.microsoft.com/en-us/windows/wsl/filesystems#file-storage-and-performance-across-file-systems) article for more info.

You can run these commands from your terminal or integrate them into your flow:

| Target    | Description                                                                      |
|-----------|----------------------------------------------------------------------------------|
| `image`   | Builds the Docker image using [docker-compose.yaml](.docker/docker-compose.yaml) |
| `prune`   | Prunes dangling Docker images to free up disk space                              |
| `publish` | Builds a specific format using [publish.sh](publish.sh)                          |
| `all`     | Builds `book.pdf`, and `book.epub`, then prunes unused images                    |
| `clean`   | Prunes images and deletes generated PDFs/EPUBs from [artifacts](/artifacts/)     |
| `reset`   | Resets the project to the last committed state (**use with caution**)            |
| `sample`  | Installs sample content (only if [publish.txt](publish.txt) is empty)            |
| `help`    | Displays a list of available `Make` targets and usage examples                   |

Example:

```shell
make publish
make publish format=epub
make all
make prune
make clean
make sample
make reset
make help
```

> Note: if you execute `make all`, you don’t need to worry about pruning dangling Docker images — it’s handled for you. However, if you publish individual targets, consider running `make prune` occasionally to conserve disk space.

### Project structure

```text
.                       # Project root
├── .docker/            # Docker image and Compose config
│   ├── Dockerfile
│   └── docker-compose.yaml
├── .keystone/          # Hidden helpers (sample content, etc.)
│   ├── sample/         # Sample chapters, appendix, and publish.txt
│   └── sync.json       # Sync metadata
├── .pandoc/            # Pandoc filters and metadata
│   ├── filters/
│   ├── includes/
│   ├── metadata/
│   └── publish.sh
├── appendix/           # Appendices (e.g., appendix-a.md)
├── artifacts/          # Output folder for built PDFs and EPUBs
├── assets/             # Images and cover art
├── chapters/           # Main content chapters (e.g., introduction.md, chapter-1.md)
├── drafts/             # Work-in-progress material
├── research/           # Notes, references, citations
├── .dockerignore       # Docker ignore file
├── .editorconfig       # Editor defaults
├── .env                # Project metadata (title, author, etc.)
├── .gitattributes      # Git attributes
├── .gitignore          # Git ignore file
├── LICENSE.md          # MIT license
├── Makefile            # Build commands
├── README.md           # This file
└── publish.txt         # List of content files to include in order
```

## A Note of Gratitude

Keystone stands on the shoulders of giants.

This project would not be possible without the incredible tools and communities that power its every build:

- [Pandoc](https://pandoc.org/) — the universal document converter
- [LaTeX](https://www.latex-project.org/) — for professional-quality typesetting
- [Docker](https://www.docker.com/) — containerized reproducibility made simple
- [GNU Make](https://www.gnu.org/software/make/) — declarative builds that just work
- [Lua](https://www.lua.org/) — a lightweight, expressive scripting language used to extend Pandoc
- [Markdown](https://www.markdownguide.org/) — the plain-text format that changed writing forever

Each one of these projects represents **years of collective wisdom**, **generosity**, and **craft** — made available freely, **for all**.

To their maintainers and contributors: **thank you**. Keystone is a bridge, but you laid the foundation.

## License

MIT License. You are free to modify and redistribute Keystone. Attribution appreciated but not required.

## Attribution

Project Keystone is developed and maintained by [Knight Owl LLC](https://github.com/knight-owl-dev).
If you use this template or build upon it, a link back to this repository is appreciated.

## Start writing

Keystone is the foundation. What you build with it is entirely yours.

Ready to write your first book like a dev? Let's go.
