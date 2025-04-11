#!/usr/bin/env bash

set -e

# generate timestamp
DATE=$(date +%Y%m%d)

# validate argument
TARGET="$1"
FORMAT="${2:-pdf}"

# fallback if KEYSTONE_PROJECT is not set
PROJECT="${KEYSTONE_PROJECT:-keystone}"

# set paths
FILE_LIST="publish.txt"
OUTPUT="artifacts/${PROJECT}-${TARGET}-${DATE}.${FORMAT}"
METADATA="${TARGET}.yaml"

# Build the file list, ignoring comments and blank lines
readarray -t FILES < <(grep -Ev '^\s*#|^\s*$' "$FILE_LIST")

# Validate publish.txt is not empty
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "❌ Error: '$FILE_LIST' is empty. Please add your chapter files or run 'make sample'."
  exit 1
fi

if [[ "$PROJECT" == "keystone" ]]; then
  echo "⚠️  You're using the default project name \"keystone\"..."
  echo "   To personalize your output, edit the .env file and update KEYSTONE_PROJECT."
fi

# Pandoc common options
PANDOC_OPTS=(
  "${FILES[@]}"
  -o "$OUTPUT"
  --toc
  --number-sections
  --pdf-engine=xelatex
  --data-dir=.pandoc
  --resource-path=.
  --metadata-file="$METADATA"
)

# Pandoc Lua filters
LUA_FILTERS=(
  keystone.lua
  div-dialog.lua
)

for f in "${LUA_FILTERS[@]}"; do
  PANDOC_OPTS+=(--lua-filter="$f")
done

if [[ "$FORMAT" == "pdf" ]]; then
  PANDOC_OPTS+=(--pdf-engine=xelatex)
  [[ -n "$KEYSTONE_LATEX_PAPERSIZE" ]] && PANDOC_OPTS+=(-V papersize="$KEYSTONE_LATEX_PAPERSIZE")
  [[ -n "$KEYSTONE_LATEX_GEOMETRY" ]] && PANDOC_OPTS+=(-V geometry="$KEYSTONE_LATEX_GEOMETRY")
  [[ -n "$KEYSTONE_LATEX_FONTSIZE" ]] && PANDOC_OPTS+=(-V fontsize="$KEYSTONE_LATEX_FONTSIZE")
  [[ -n "$KEYSTONE_LATEX_FONTFAMILY" ]] && PANDOC_OPTS+=(-V fontfamily="$KEYSTONE_LATEX_FONTFAMILY")
fi

# Source metadata overrides from environment variables
PANDOC_OPTS+=(
  -M title="$KEYSTONE_TITLE"
  -M subtitle="$KEYSTONE_SUBTITLE"
  -M author="$KEYSTONE_AUTHOR"
  -M date="$KEYSTONE_DATE"
  -M footer-copyright="$KEYSTONE_FOOTER_COPYRIGHT"
  -M description="$KEYSTONE_DESCRIPTION"
  -M keywords="$KEYSTONE_KEYWORDS"
)

# build with Pandoc
echo "⏳ Publishing target: '$TARGET' | format: $FORMAT"
pandoc "${PANDOC_OPTS[@]}"
echo "✅ Done: $OUTPUT"
echo ""
