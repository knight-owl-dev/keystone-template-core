#!/usr/bin/env bash
set -euo pipefail

# publish.sh — Convert Markdown chapters into publishable document formats
#
# This is the core publishing engine of Keystone. It reads the chapter list
# from publish.txt, applies Lua filters for custom formatting (dialogs,
# page breaks, poems, etc.), and invokes Pandoc to produce the final output.
#
# All document metadata — title, author, layout, cover image, etc. — is read
# exclusively from pandoc.yaml (bind-mounted as user-metadata.yaml inside
# the container). Environment-variable metadata injection has been removed
# because the Pandoc CLI corrupts unicode when metadata is passed via -M
# flags; a YAML metadata file avoids this problem entirely.
#
# Supports PDF (via XeLaTeX), EPUB, DOCX, and ODT. PDF layout variables (papersize,
# geometry, fontsize, fontfamily) and EPUB options (cover-image) are set
# directly in pandoc.yaml — Pandoc reads them natively from YAML metadata.
#
# Called by the Makefile's `publish` and `all` targets via
# docker compose run inside the Keystone container.
#
# Environment (input):
#   KEYSTONE_PROJECT          — project name for output filename (optional, default: keystone)
#   KEYSTONE_DEFINE_<name>    — build configurations: named symbol sets for
#                               conditional inclusion (declared in project.conf)
#   KEYSTONE_USING            — selected configuration name (optional; empty =
#                               plain build). Also suffixes the output filename
#
# Environment (set by this script for Lua filters):
#   KEYSTONE_DEFINED_SYMBOLS  — resolved active symbol set for ifdef/ifndef
#                               (selected configuration + the build's format symbol)
#   KEYSTONE_CSS_FONTS        — temp path for generated font CSS stylesheet
#   KEYSTONE_CSS_DIVS         — temp path for generated div handler CSS stylesheet
#   KEYSTONE_CSS_CODE_THEME   — temp path for generated code theme CSS stylesheet
#   KEYSTONE_CSS_JUSTIFY      — temp path for generated justify CSS stylesheet
#   KEYSTONE_CSS_INDENT       — temp path for generated indent CSS stylesheet
#   KEYSTONE_CODE_THEME       — resolved code theme name (default: tango)
#   KEYSTONE_SHORTCUTS        — path to preprocessed shortcuts Lua table (always set)
#   KEYSTONE_USER_FONTS       — path to preprocessed user font registry Lua table (when present)
#   KEYSTONE_USER_FONTS_DIR   — container path to user font files
#   KEYSTONE_JUSTIFY          — resolved justify boolean (1 = justified, 0 = ragged-right)
#   KEYSTONE_INDENT           — resolved indent boolean (1 = indented, 0 = no indent)
#   KEYSTONE_HEADER_RULE      — resolved header-rule boolean (1 = rule, 0 = none; PDF only)
#   KEYSTONE_FONT_SCAN_OUTPUT — temp path for content font keys file (EPUB only)
#   KEYSTONE_MATH_METHOD      — math method math-check probes with
#
# Usage: .pandoc/publish.sh [<format>]
#   <format>  — output format: pdf (default), epub, docx, or odt
#
# Output: ./artifacts/<project>-<target>[-<using>]-<date>.<format>
#   <target> is read from pandoc.yaml (default: book); <using> is the selected
#   build configuration, omitted for a plain build

# generate timestamp
DATE=$(date +%Y%m%d)

# validate arguments
FORMAT="${1:-pdf}"

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
mkdir -p artifacts

# Temp workspace for intermediate files shared between publish.sh and Lua filters.
# Individual paths are exported so each consumer reads its location from the
# environment — no hardcoded /tmp paths in Lua.
KEYSTONE_TMPDIR="$(mktemp -d /tmp/keystone.XXXXXX)"
trap 'rm -rf "${KEYSTONE_TMPDIR}"' EXIT

KEYSTONE_CSS_FONTS="${KEYSTONE_TMPDIR}/fonts.css"
KEYSTONE_CSS_DIVS="${KEYSTONE_TMPDIR}/divs.css"
KEYSTONE_CSS_CODE_THEME="${KEYSTONE_TMPDIR}/code-theme.css"
KEYSTONE_CSS_JUSTIFY="${KEYSTONE_TMPDIR}/justify.css"
KEYSTONE_CSS_INDENT="${KEYSTONE_TMPDIR}/indent.css"
export KEYSTONE_CSS_FONTS KEYSTONE_CSS_DIVS \
  KEYSTONE_CSS_CODE_THEME KEYSTONE_CSS_JUSTIFY KEYSTONE_CSS_INDENT

# Convert a YAML config to a Lua table and export the result path.
# No-op when the source file is missing or empty. Uses -f (not just -s)
# because a missing host file causes Docker to create a directory at the
# mount point, and -s returns true for directories.
#   yaml_to_lua <source_yaml> <env_var_name>
yaml_to_lua() {
  local source="$1"
  local env_var="$2"
  if [[ -f "${source}" ]] && [[ -s "${source}" ]]; then
    local stem
    stem=$(basename "${source}" .yaml)
    local output="${KEYSTONE_TMPDIR}/${stem}.lua"
    yq -o=lua '.' "${source}" > "${output}"
    export "${env_var}=${output}"
  fi
}

# ── System + user shortcuts merge ─────────────────────────────────────
# System shortcuts ship inside the image and define the public API surface.
# User shortcuts layer on top with last-writer-wins.
SYSTEM_SHORTCUTS=".pandoc/system-shortcuts.yaml"
if [[ ! -f "${SYSTEM_SHORTCUTS}" ]] || [[ ! -s "${SYSTEM_SHORTCUTS}" ]]; then
  echo "ERROR: system-shortcuts.yaml is missing or empty in the image" >&2
  exit 1
fi

if [[ -f "shortcuts.yaml" ]] && [[ -s "shortcuts.yaml" ]]; then
  # yq -e exits non-zero for both parse errors and null documents.
  # Happy path (valid non-null YAML) passes in one invocation.
  if yq -e '.' shortcuts.yaml > /dev/null 2>&1; then
    MERGED_SHORTCUTS="${KEYSTONE_TMPDIR}/shortcuts-merged.yaml"
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
      "${SYSTEM_SHORTCUTS}" shortcuts.yaml > "${MERGED_SHORTCUTS}"
  # Disambiguate: yq without -e exits 0 for valid YAML (including null),
  # non-zero for parse errors. Null/comment-only files are treated as absent.
  elif ! yq '.' shortcuts.yaml > /dev/null 2>&1; then
    echo "ERROR: shortcuts.yaml contains invalid YAML" >&2
    echo "  Fix the syntax errors or remove the file" >&2
    exit 1
  else
    MERGED_SHORTCUTS="${SYSTEM_SHORTCUTS}"
  fi
else
  MERGED_SHORTCUTS="${SYSTEM_SHORTCUTS}"
fi
yaml_to_lua "${MERGED_SHORTCUTS}" "KEYSTONE_SHORTCUTS"

# ── User font registry ───────────────────────────────────────────────
# Optional user-defined fonts in fonts/fonts-registry.yaml, with font
# files in fonts/. Converted to Lua for the font registry lib.
yaml_to_lua "fonts/fonts-registry.yaml" "KEYSTONE_USER_FONTS"

KEYSTONE_USER_FONTS_DIR="/keystone/fonts/"
export KEYSTONE_USER_FONTS_DIR

# Require user-metadata.yaml (pandoc.yaml on the host, bind-mounted by compose).
# Validated early because metadata is read from it below.
if [[ ! -s .pandoc/metadata/user-metadata.yaml ]]; then
  echo "ERROR: user-metadata.yaml is missing or empty (bind-mounted from pandoc.yaml)" >&2
  echo "  Ensure it exists and contains your document metadata" >&2
  exit 1
fi

# Read + normalize all document metadata in one pass: one yq read of the user
# file + one of the resolved target file. Sets TARGET and exports the KEYSTONE_*
# values the Lua filters consume; validates the target file exists.
# shellcheck source=src/runtime/.pandoc/resolve-metadata.sh
source .pandoc/resolve-metadata.sh
resolve_metadata .pandoc/metadata/user-metadata.yaml .pandoc/metadata

# Resolve the selected build configuration into KEYSTONE_DEFINED_SYMBOLS (the
# set the ifdef/ifndef handlers read). Symbols are build config, not document
# metadata — sourced from the environment (project.conf), not user-metadata.yaml.
# shellcheck source=src/runtime/.pandoc/resolve-symbols.sh
source .pandoc/resolve-symbols.sh
resolve_symbols "${FORMAT}"

METADATA="${TARGET}.yaml"

# Suffix the output filename with the configuration name so editions (e.g. a
# private vs public build) don't clobber each other in artifacts/.
USING_SUFFIX=""
if [[ -n "${KEYSTONE_USING:-}" ]]; then
  USING_SUFFIX="-${KEYSTONE_USING}"
fi
OUTPUT="artifacts/${PROJECT}-${TARGET}${USING_SUFFIX}-${DATE}.${FORMAT}"

# Build the file list, ignoring comments and blank lines
file_content=$(grep -Ev '^\s*#|^\s*$' "${FILE_LIST}" || true)
if [[ -z "${file_content}" ]]; then
  echo "ERROR: '${FILE_LIST}' is empty. Please add your chapter files" >&2
  echo "  For a working example, see: https://github.com/knight-owl-dev/keystone-hello-world" >&2
  exit 1
fi
readarray -t FILES <<< "${file_content}"

if [[ "${PROJECT}" == "keystone" ]]; then
  echo "WARN: You're using the default project name \"keystone\"..."
  echo "  Set KEYSTONE_PROJECT (via project.conf or your environment) to personalize your output"
fi

# ── Standard filter pipeline ──────────────────────────────────────────
# Order matters:
#   shortcuts      — expand user-defined aliases first so downstream
#                    filters see fully resolved Spans/Divs
#   keystone       — metadata enrichment, font/code-theme injection
#   divs           — dispatch system handlers (.font, .align, ...)
#   page-furniture — render running header/footer slot macros AFTER
#                    handlers and shortcuts have rewritten metadata Spans
#   math-check     — final validation gate: probes the target writer and
#                    fails the build on any equation that won't convert,
#                    rather than leaking raw TeX. PDF passes (latex emits raw
#                    TeX, never fails). Last so it sees the fully-resolved AST.
STANDARD_FILTERS=(
  --lua-filter=shortcuts.lua
  --lua-filter=keystone.lua
  --lua-filter=divs.lua
  --lua-filter=page-furniture.lua
  --lua-filter=math-check.lua
)

# Pandoc common options
# Reference: # https://pandoc.org/MANUAL.html
PANDOC_OPTS=(
  "${FILES[@]}"
  -o "${OUTPUT}"
  --table-of-contents
  --number-sections
  --data-dir=.pandoc
  --resource-path=.
  --metadata-file="${METADATA}"
  --metadata-file=user-metadata.yaml
  "${STANDARD_FILTERS[@]}"
)

# ── Pre-scan filters ──────────────────────────────────────────────────
# Filters that must run before the main Pandoc invocation to collect data
# (e.g. font keys for EPUB embedding). Shortcuts is always prepended so
# scanners see expanded aliases, not raw shortcut classes.
#
# Runs only when at least one scanner filter is needed.
PRESCAN_FILTERS=()

if [[ "${FORMAT}" == "epub" ]]; then
  KEYSTONE_FONT_SCAN_OUTPUT="${KEYSTONE_TMPDIR}/font-scan.txt"
  export KEYSTONE_FONT_SCAN_OUTPUT
  PRESCAN_FILTERS+=(--lua-filter=.pandoc/filters/font-scan.lua)
fi

if [[ ${#PRESCAN_FILTERS[@]} -gt 0 ]]; then
  PRESCAN_FILTERS=(--lua-filter=.pandoc/filters/shortcuts.lua "${PRESCAN_FILTERS[@]}")
  pandoc "${PRESCAN_FILTERS[@]}" \
    "${FILES[@]}" --to=native -o /dev/null
fi

# Format-specific Pandoc options (PANDOC_OPTS only — no side effects)
case "${FORMAT}" in
  pdf)
    # xmp-metadata.lua conditionally injects \usepackage{hyperxmp} into
    # header-includes. Gated to PDF only because hyperxmp is irrelevant
    # for non-LaTeX formats and its preamble would be silently dropped.
    # Bare filter name (no path) — resolved via --data-dir=.pandoc above,
    # matching the STANDARD_FILTERS convention.
    PANDOC_OPTS+=(
      --pdf-engine=xelatex
      --lua-filter=xmp-metadata.lua
    )
    ;;
  epub)
    # Render math as self-contained MathML (no JavaScript, no network) so the
    # build stays hermetic.
    PANDOC_OPTS+=(--mathml)

    # EPUB's math method is flag-selectable (html_math_method); declare it
    # beside --mathml so the writer flag and the probe method can't drift.
    KEYSTONE_MATH_METHOD="mathml"
    export KEYSTONE_MATH_METHOD

    # Dependency: KEYSTONE_FONT_SCAN_OUTPUT
    #
    # Generate --epub-embed-font paths from metadata + pre-scan results.
    # The @font-face CSS is generated by keystone.lua; this step copies the
    # actual .otf files into the EPUB archive. System fonts (no path) use
    # CSS fallback stacks only.
    epub_font_paths=$(pandoc lua .pandoc/filters/lib/epub-font-paths.lua \
      .pandoc/metadata/user-metadata.yaml)
    if [[ -n "${epub_font_paths}" ]]; then
      while IFS= read -r font_path; do
        PANDOC_OPTS+=("--epub-embed-font=${font_path}")
      done <<< "${epub_font_paths}"
    fi
    ;;
  docx | odt)
    # reference_mask (resolve-metadata.sh) owns the bit layout; we just map
    # the resulting opaque mask to its pre-built reference-doc variant.
    ref_mask=$(reference_mask)
    ref_bits=$(mask_to_bits "${ref_mask}")
    ref_path=".pandoc/includes/reference-${ref_bits}.${FORMAT}"
    if [[ ! -f "${ref_path}" ]]; then
      echo "WARN: Reference variant ${ref_bits} not found, using default" >&2
      ref_bits=$(mask_to_bits 0)
      ref_path=".pandoc/includes/reference-${ref_bits}.${FORMAT}"
    fi
    PANDOC_OPTS+=(--reference-doc="${ref_path}")
    ;;
esac

# ── Code theme ────────────────────────────────────────────────────────
# KEYSTONE_CODE_THEME is resolved (with its default) by resolve_metadata
# above; here we validate the theme dir exists and pass it to Pandoc.
if [[ ! -d ".pandoc/filters/code-themes/${KEYSTONE_CODE_THEME}" ]]; then
  echo "ERROR: Unknown code-theme '${KEYSTONE_CODE_THEME}'" >&2
  echo "  See pandoc.yaml for available themes" >&2
  exit 1
fi
PANDOC_OPTS+=("--syntax-highlighting=${KEYSTONE_CODE_THEME}")

# ── Bibliography / citations (Pandoc citeproc) ────────────────────────
# resolve_metadata validated the referenced files and exported the resolved
# paths. When a bibliography is present, enable citeproc and hand Pandoc a
# metadata override whose bibliography/csl point at the resolved locations —
# authors reference a bare filename, but the file lives in manuscript/ by
# convention, so Pandoc must see the resolved path, not the author value.
# Passed as the LAST --metadata-file so it wins: right-most --metadata-file
# overrides the bare bibliography the author set in pandoc.yaml. yq builds the
# file from the exported env vars (KEYSTONE_BIBLIOGRAPHY is newline-separated),
# so paths are quoted correctly without hand-rolled escaping.
if [[ -n "${KEYSTONE_BIBLIOGRAPHY}" ]]; then
  CITATIONS_META="${KEYSTONE_TMPDIR}/citations.yaml"
  yq -n '
    .bibliography = (strenv(KEYSTONE_BIBLIOGRAPHY) | split("\n")) |
    .csl = strenv(KEYSTONE_CSL)
  ' > "${CITATIONS_META}"
  PANDOC_OPTS+=(--citeproc --metadata-file="${CITATIONS_META}")
fi

# build with Pandoc
echo "Publishing target: '${TARGET}' | format: ${FORMAT}"
pandoc "${PANDOC_OPTS[@]}"
echo "OK: ${OUTPUT}"
echo ""
