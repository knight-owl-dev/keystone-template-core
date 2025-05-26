# Appendix A: On Craft and Clarity {.unnumbered}

> “Engineers do for a dime what any fool can do for a dollar.”
> — Henry Ford

This appendix is a quiet corner — a space to reflect on the craft of building books and the clarity that good tooling brings.

## A Few Guiding Ideas {.unnumbered}

- **You don’t need a GUI to do beautiful work.**
  Command-line workflows can feel minimalist, expressive, and even joyful — when they’re designed well.

- **Version everything.**
  Your content *is* your code. Treat it with the same care. Keystone encourages you to track changes, review diffs, and evolve your work with intent.

- **Start with structure.**
  You can’t revise what you haven’t framed. Whether you’re outlining a novel or documenting a system, structure is your friend.

- **Automate with humility.**
  Keystone automates what’s tedious, not what’s meaningful. It gives you a sharp pencil — not a robot hand.

## How to Extend This Book {.unnumbered}

Keystone is designed for clean, reproducible authoring without touching internal scripts. Here are some ways you can extend your project:

- Add a new chapter (e.g., `chapter-3.md`) and include it in `publish.txt`
- Drop a new image in `assets/` and reference it in your content
- Customize title, author, font, paper size in the `.env` file
- Explore advanced features like `::: dialog` or `::: latex-only` blocks to stylize content using custom divs

> For power users: Advanced settings (like Lua filters or LaTeX macros) live in `.pandoc/`. But casual users won’t need to touch them.

## A Note of Gratitude {.unnumbered}

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

---

This book is yours now.
Your words, your structure, your craft.

Build well.
