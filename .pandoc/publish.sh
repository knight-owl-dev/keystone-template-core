#!/usr/bin/env bash
set -euo pipefail

# publish.sh — Convert Markdown chapters into publishable book formats
#
# This is the core publishing engine of Keystone. It reads the chapter list
# from publish.txt, applies Lua filters for custom formatting (dialogs,
# page breaks, poems, etc.), and invokes Pandoc to produce the final output.
#
# All book metadata — title, author, layout, cover image, etc. — is read
# exclusively from pandoc.yaml (bind-mounted as user-metadata.yaml inside
# the container). Environment-variable metadata injection has been removed
# because the Pandoc CLI corrupts unicode when metadata is passed via -M
# flags; a YAML metadata file avoids this problem entirely.
#
# Supports PDF (via XeLaTeX), EPUB, DOCX, and ODT. PDF layout variables (papersize,
# geometry, fontsize, fontfamily) and EPUB options (cover-image) are set
# directly in pandoc.yaml — Pandoc reads them natively from YAML metadata.
#
# Called by the Makefile's `book`, `sample`, and similar targets via
# docker compose exec inside the Keystone container.
#
# Environment:
#   KEYSTONE_PROJECT  — project name for output filename (optional, default: keystone)
#
# Usage: .pandoc/publish.sh <target> [<format>]
#   <target>  — the metadata file stem (e.g., "book" loads book.yaml)
#   <format>  — output format: pdf (default), epub, docx, or odt
#
# Output: ./artifacts/<project>-<target>-<date>.<format>

# generate timestamp
DATE=$(date +%Y%m%d)

# validate arguments
TARGET="${1:?Target required — e.g., publish.sh book [format]}"
FORMAT="${2:-pdf}"

# Pandoc supports many output formats, but each one we officially support must
# work correctly with the div handler system and Lua filters — limit to tested formats.
case "${FORMAT}" in
  pdf | epub | docx | odt) ;; # supported formats
  *)
    echo "ERROR: Unsupported format '${FORMAT}'. Use: pdf, epub, docx, or odt" >&2
    exit 1
    ;;
esac

# fallback if KEYSTONE_PROJECT is not set
PROJECT="${KEYSTONE_PROJECT:-keystone}"

# set paths
FILE_LIST="publish.txt"
OUTPUT="artifacts/${PROJECT}-${TARGET}-${DATE}.${FORMAT}"
METADATA="${TARGET}.yaml"

if [[ ! -f ".pandoc/metadata/${METADATA}" ]]; then
  echo "ERROR: Target metadata file not found: ${METADATA}" >&2
  echo "   Ensure '${TARGET}' is a valid target (e.g., 'book')." >&2
  exit 1
fi

# Build the file list, ignoring comments and blank lines
file_content=$(grep -Ev '^\s*#|^\s*$' "${FILE_LIST}" || true)
if [[ -z "${file_content}" ]]; then
  echo "ERROR: '${FILE_LIST}' is empty. Please add your chapter files or run 'make sample'." >&2
  exit 1
fi
readarray -t FILES <<< "${file_content}"

if [[ "${PROJECT}" == "keystone" ]]; then
  echo "WARN: You're using the default project name \"keystone\"..."
  echo "   Set KEYSTONE_PROJECT (via project.conf or your environment) to personalize your output."
fi

# Pandoc common options
# Reference: # https://pandoc.org/MANUAL.html
#
# Two Lua filters handle all custom processing:
#   1. keystone.lua — metadata validation and enrichment (must run first)
#   2. divs.lua     — single-pass dispatcher for all fenced-div handlers
PANDOC_OPTS=(
  "${FILES[@]}"
  -o "${OUTPUT}"
  --table-of-contents
  --number-sections
  --data-dir=.pandoc
  --resource-path=.
  --metadata-file="${METADATA}"
  --lua-filter=keystone.lua
  --lua-filter=divs.lua
)

if [[ "${FORMAT}" == "pdf" ]]; then
  PANDOC_OPTS+=(--pdf-engine=xelatex)
fi

# Require user-metadata.yaml (pandoc.yaml on the host, bind-mounted by compose).
# The -s check uses the filesystem path; --metadata-file uses the Pandoc-relative
# path (resolved via --data-dir=.pandoc). The mismatch is intentional.
if [[ -s .pandoc/metadata/user-metadata.yaml ]]; then
  PANDOC_OPTS+=(--metadata-file=user-metadata.yaml)
else
  echo "ERROR: user-metadata.yaml is missing or empty (bind-mounted from pandoc.yaml)." >&2
  echo "   Ensure it exists and contains your book metadata." >&2
  exit 1
fi

# build with Pandoc
echo "Publishing target: '${TARGET}' | format: ${FORMAT}"
pandoc "${PANDOC_OPTS[@]}"
echo "OK: ${OUTPUT}"
echo ""
