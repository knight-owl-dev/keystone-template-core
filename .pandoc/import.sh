#!/usr/bin/env bash

# .pandoc/import.sh
# Convert supported documents (DOCX, ODT, HTML, etc.) to Markdown
# Output is saved to ./artifacts/<filename>-imported.md
#
# Usage: ./import.sh <artifact-file.ext>
# Example: ./import.sh my-document.docx

set -euo pipefail

# Ensure input is provided
if [ $# -lt 1 ]; then
  echo "❌ Usage: $0 <artifact-file.ext>"
  exit 1
fi

INPUT_ARTIFACT_FILEPATH="artifacts/$1"
FILENAME="$(basename -- "$INPUT_ARTIFACT_FILEPATH")"
EXTENSION="${FILENAME##*.}"
BASENAME="${FILENAME%.*}"

# Normalize extension to lowercase
EXTENSION="$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')"

# Ensure the input file exists
if [ ! -f "$INPUT_ARTIFACT_FILEPATH" ]; then
  echo "❌ Input file not found: $INPUT_ARTIFACT_FILEPATH"
  exit 1
fi

# Define output path (output to ./artifacts from host perspective)
OUTPUT_PATH="artifacts"
OUTPUT_FILE="${OUTPUT_PATH}/${BASENAME}-imported.md"
OUTPUT_MEDIA_PATH="${OUTPUT_PATH}/${BASENAME}-assets"

# Convert to Markdown using Pandoc
echo "⏳ Converting '$FILENAME' to Markdown..."
pandoc "$INPUT_ARTIFACT_FILEPATH" \
  --output="$OUTPUT_FILE" \
  --extract-media="$OUTPUT_MEDIA_PATH" \
  --standalone

echo "✅ Markdown saved to: ${OUTPUT_FILE}"
if [ -d "$OUTPUT_MEDIA_PATH" ]; then
  echo "🖼️  Media assets extracted to: ${OUTPUT_MEDIA_PATH}/"
fi
