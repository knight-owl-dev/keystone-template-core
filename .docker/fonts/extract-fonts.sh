#!/usr/bin/env bash
set -euo pipefail

# extract-fonts.sh — Stage the registry-referenced font files for the slim image
#
# Runs inside the Docker font-extractor stage, after the font packages are
# installed. font-registry.lua is the single source of truth for which files
# ship: the given list-command prints one font path per line, relative to
# SOURCE_ROOT (in practice `pandoc lua .../list-builtin-fonts.lua`). This script
# copies each of those files from SOURCE_ROOT into STAGING_DIR, preserving the
# subtree. The final image COPYs that tree to /opt/keystone/fonts/, carrying
# only the font files Keystone embeds (see the Dockerfile for why extraction
# earns a stage).
#
# A referenced file absent from SOURCE_ROOT is a hard error: the list-command
# emits only variants the registry declares, so a miss means the registry names
# a font the extractor stage never installed. Failing here keeps a broken image
# from shipping.
#
# Taking the list-command as arguments (rather than hard-coding the enumerator)
# keeps this a pure copy step: one responsibility, and unit-testable with a
# stub list-command that needs no pandoc.
#
# Usage: extract-fonts.sh <list-command> [args...]
#   e.g. extract-fonts.sh pandoc lua .pandoc/filters/lib/list-builtin-fonts.lua
#
# Environment:
#   SOURCE_ROOT — TeX Live fonts tree to copy from
#                 (default /opt/texlive/texdir/texmf-dist/fonts)
#   STAGING_DIR — directory to assemble the slim font tree into (default /staging)

SOURCE_ROOT="${SOURCE_ROOT:-/opt/texlive/texdir/texmf-dist/fonts}"
STAGING_DIR="${STAGING_DIR:-/staging}"

if [[ $# -eq 0 ]]; then
  echo "ERROR: a list-command is required (prints font paths relative to SOURCE_ROOT)" >&2
  echo "  usage: extract-fonts.sh <list-command> [args...]" >&2
  exit 2
fi

# Capture the list first so a failing list-command aborts the build (set -e on
# the command substitution) rather than silently yielding an empty tree.
font_list="$("$@")"

if [[ -z "${font_list}" ]]; then
  echo "ERROR: the list-command produced no font files" >&2
  exit 1
fi

count=0
while IFS= read -r rel; do
  [[ -z "${rel}" ]] && continue
  src="${SOURCE_ROOT%/}/${rel}"
  dst="${STAGING_DIR%/}/${rel}"
  if [[ ! -f "${src}" ]]; then
    echo "ERROR: font referenced by the registry is absent from the image: ${src}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${dst}")"
  cp "${src}" "${dst}"
  count=$((count + 1))
done <<< "${font_list}"

echo "Staged ${count} font file(s) into ${STAGING_DIR}"
