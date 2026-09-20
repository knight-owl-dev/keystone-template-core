# Package Declarations

What the image installs, one directory per installer. `<installer>-install.sh`
reads its directory's files with `--from-file`, so a Dockerfile stage names a
declaration rather than a list of packages, and `read-packages.sh` is the row
parser both wrappers share.

## Row Format

One package per row, alphabetical: name in column one, an optional note as the
rest of the line. `#` comments, blank lines and leading whitespace are ignored.

## Classes

An `apt/` stem carries a class — `<name>.<class>.packages` — because the final
stage starts from the base image again and copies in what the builder stages
produced. A builder's apt layer is not among what it inherits.

| Class | Installed by | Layer reaches the final image |
| --- | --- | --- |
| `build` | a builder stage | no |
| `runtime` | the final stage | yes |

The class names the layer, not the package: `gzip` and `tar` are `build` here
and in the base image too. Nothing reads it; each stage names its declarations
in full.

Installing a `runtime` package brings whatever the distribution says it needs;
those arrive undeclared, and no file here lists them.

`tlmgr/` stems carry no class: every package there is installed and reaches the
final image, either whole or as the files the font extractor stages.
