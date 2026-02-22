#!/usr/bin/env bash
set -euo pipefail

# import.sh — Convert external documents into Markdown for use in Keystone
#
# Converts supported formats (DOCX, ODT, HTML, etc.) into Markdown using
# Pandoc. The input file must be placed in the artifacts/ directory first.
# Media assets (images, etc.) are extracted alongside the converted file.
#
# This is a convenience tool for authors migrating existing content into
# the Keystone chapter structure. The output still needs manual review —
# Pandoc's conversion is a starting point, not a final result.
#
# Called by the Makefile's `import` target via docker compose exec.
#
# Usage: .pandoc/import.sh <artifact-file.ext>
#
# Output:
#   ./artifacts/<basename>-imported.md      — converted Markdown
#   ./artifacts/<basename>-assets/          — extracted media (if any)

# Ensure input is provided
if [[ $# -lt 1 ]]; then
  echo "ERROR: Usage: $0 <artifact-file.ext>" >&2
  exit 1
fi

INPUT_ARTIFACT_FILEPATH="artifacts/$1"
FILENAME="$(basename -- "${INPUT_ARTIFACT_FILEPATH}")"
EXTENSION="${FILENAME##*.}"
BASENAME="${FILENAME%.*}"

# Normalize extension to lowercase
EXTENSION="$(echo "${EXTENSION}" | tr '[:upper:]' '[:lower:]')"

# Ensure the input file exists
if [[ ! -f "${INPUT_ARTIFACT_FILEPATH}" ]]; then
  echo "ERROR: Input file not found: ${INPUT_ARTIFACT_FILEPATH}" >&2
  exit 1
fi

# Define output path (output to ./artifacts from host perspective)
OUTPUT_PATH="artifacts"
mkdir -p "${OUTPUT_PATH}"
OUTPUT_FILE="${OUTPUT_PATH}/${BASENAME}-imported.md"
OUTPUT_MEDIA_PATH="${OUTPUT_PATH}/${BASENAME}-assets"

# Convert to Markdown using Pandoc
echo "Converting '${FILENAME}' to Markdown..."
pandoc "${INPUT_ARTIFACT_FILEPATH}" \
  --output="${OUTPUT_FILE}" \
  --extract-media="${OUTPUT_MEDIA_PATH}" \
  --standalone

echo "OK: ${OUTPUT_FILE}"
if [[ -d "${OUTPUT_MEDIA_PATH}" ]]; then
  echo "  Media assets extracted to: ${OUTPUT_MEDIA_PATH}/"
fi
