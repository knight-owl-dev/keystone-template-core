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
# Supports PDF (via XeLaTeX), EPUB, DOCX, and ODT. keystone.lua settles the
# layout metadata before a writer sees it: papersize, geometry and fontsize are
# rewritten, and fontfamily and monofont consumed as registry keys. The page size
# joins the geometry list and papersize is cleared, so it no longer reaches
# \documentclass.
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
#   KEYSTONE_WARNINGS_AS_ERRORS — strict builds: true/1/yes/on fails the build
#                               on any warning (default false; project.conf,
#                               overridable by the environment for CI)
#   KEYSTONE_PROGRESS         — build progress detail: off/plain/auto/verbose
#                               (default auto; resolved and documented in
#                               .pandoc/progress.sh)
#   KEYSTONE_HOOKS_TIMEOUT / KEYSTONE_HOOKS_CACHE / KEYSTONE_HOOKS_CACHE_MAX
#                             — hook settings, resolved and documented in
#                               .pandoc/resolve-hooks.sh
#
# Environment (set by this script for Lua filters):
#   KEYSTONE_WARNING_SINK     — strict mode only: cross-process file the errors
#                               lib appends warnings to; checked post-build
#   KEYSTONE_DEFINED_SYMBOLS  — resolved active symbol set for ifdef/ifndef
#                               (selected configuration + the build's format symbol)
#   KEYSTONE_CSS_FONTS        — temp path for generated font CSS stylesheet
#   KEYSTONE_CSS_DIVS         — temp path for generated div handler CSS stylesheet
#   KEYSTONE_CSS_CODE_THEME   — temp path for generated code theme CSS stylesheet
#   KEYSTONE_CSS_JUSTIFY      — temp path for generated justify CSS stylesheet
#   KEYSTONE_CSS_INDENT       — temp path for generated indent CSS stylesheet
#   KEYSTONE_CODE_THEME       — resolved code theme name (default: tango)
#   KEYSTONE_TOC_DEPTH        — TOC depth in heading levels (default: 3)
#   KEYSTONE_SECNUMDEPTH      — deepest numbered heading level
#   KEYSTONE_SHORTCUTS        — path to preprocessed shortcuts Lua table (always set)
#   KEYSTONE_USER_FONTS       — path to preprocessed user font registry Lua table (when present)
#   KEYSTONE_USER_FONTS_DIR   — container path to user font files
#   KEYSTONE_JUSTIFY          — resolved justify boolean (1 = justified, 0 = ragged-right)
#   KEYSTONE_INDENT           — resolved indent boolean (1 = indented, 0 = no indent)
#   KEYSTONE_HEADER_RULE      — resolved header-rule boolean (1 = rule, 0 = none; PDF only)
#   KEYSTONE_TOC              — resolved toc boolean (1 = generate contents, 0 = none)
#   KEYSTONE_NUMBERSECTIONS   — resolved numbersections boolean (1 = number sections, 0 = none)
#   KEYSTONE_FONT_SCAN_OUTPUT — temp path for content font keys file (EPUB only)
#   KEYSTONE_EPUB_EMBED_ROWS  — temp path for the embed rows (EPUB only)
#   KEYSTONE_MATH_METHOD      — math method math-check probes with
#   KEYSTONE_FORMAT           — the requested output format, for hooks that
#                               pick an asset per format
#   KEYSTONE_HOOKS_DIR        — directory holding hook sockets (hooks only)
#                               The three settings above are re-exported here
#                               once resolved
#
# Usage: .pandoc/publish.sh [<format>]
#   <format>  — output format: pdf (default), epub, docx, or odt
#
# Output: ./artifacts/<project>-<target>[-<using>]-<date>.<format>
#   <target> is read from pandoc.yaml (default: book); <using> is the selected
#   build configuration, omitted for a plain build

# Shell-side diagnostics: warn / fail / warnings_as_errors. Sourced first so
# every message below routes through the WARN/ERROR helpers.
# shellcheck source=src/runtime/.pandoc/diagnostics.sh
source .pandoc/diagnostics.sh
# Stage reporting, and the owner of Pandoc's message stream — every Pandoc run
# below goes through it, so Pandoc's diagnostics reach the author in Keystone's
# vocabulary rather than its own.
# shellcheck source=src/runtime/.pandoc/progress.sh
source .pandoc/progress.sh
# shellcheck source=src/runtime/.pandoc/resolve-hooks.sh
source .pandoc/resolve-hooks.sh
# shellcheck source=src/runtime/.pandoc/resolve-epub-fonts.sh
source .pandoc/resolve-epub-fonts.sh

# generate timestamp
DATE=$(date +%Y%m%d)

# Wall-clock start, reported on the success line so the author sees what the
# build cost. Set before any resolution work so the total covers all of it.
BUILD_START=$(progress_now)

# validate arguments
FORMAT="${1:-pdf}"

# Pandoc supports many output formats, but each one we officially support must
# work correctly with the div handler system and Lua filters — limit to tested formats.
case "${FORMAT}" in
  pdf | epub | docx | odt) ;; # supported formats
  *)
    fail --problem "unsupported format '${FORMAT}'" \
      --choices pdf --choices epub --choices docx --choices odt \
      --see "https://keystone.knight-owl.dev/errors/missing-metadata/#the-format-isnt-one-keystone-writes"
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

# ── Warnings-as-errors (strict builds) ────────────────────────────────
# project.conf declares KEYSTONE_WARNINGS_AS_ERRORS (default false); CI overrides
# it with `make publish strict=true` (see the template Makefile). Strict mode is
# enforced per diagnostic source: the shell resolvers fail fast via
# diagnostics.sh; Pandoc's own warnings via the --fail-if-warnings added below;
# and the Lua filters via the warning-sink file checked after the build.
# warnings_as_errors interprets the flag once; the sink and the Pandoc flag are
# wired here only when strict.
STRICT_PANDOC_OPTS=()
if warnings_as_errors; then
  KEYSTONE_WARNING_SINK="${KEYSTONE_TMPDIR}/warnings.sink"
  export KEYSTONE_WARNING_SINK
  STRICT_PANDOC_OPTS=(--fail-if-warnings)
fi

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
  fail --problem "system-shortcuts.yaml is missing or empty in the image"
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
    fail --problem "shortcuts.yaml contains invalid YAML" \
      --remedy "Fix the syntax errors, or remove the file."
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
  fail --problem "user-metadata.yaml is missing or empty (bind-mounted from pandoc.yaml)" \
    --remedy "Make sure it exists and carries your document metadata." \
    --see "https://keystone.knight-owl.dev/errors/missing-metadata/#the-metadata-file-is-missing-or-empty"
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

# Announce the build here, where the target and format are first both known, so
# it heads the stage lines rather than landing among them.
echo "Publishing target: '${TARGET}' | format: ${FORMAT}"

# Promote-on-success: build into staging (the tmpdir, auto-wiped by the EXIT
# trap), then move into artifacts/ only on a clean build — and, in strict mode,
# only when the warning sink stayed empty. A failed or warning-tripped build
# thus writes no new artifact (a prior same-day build keeps its date-stamped
# file). mv across tmpfs → the artifacts bind mount is a copy, negligible for a
# book-sized file.
STAGED_OUTPUT="${KEYSTONE_TMPDIR}/$(basename "${OUTPUT}")"

# Build the file list, ignoring comments and blank lines
file_content=$(grep -Ev '^\s*#|^\s*$' "${FILE_LIST}" || true)
if [[ -z "${file_content}" ]]; then
  fail --problem "'${FILE_LIST}' is empty" \
    --remedy "Add your chapter files." \
    --see "https://github.com/knight-owl-dev/keystone-hello-world"
fi
readarray -t FILES <<< "${file_content}"

if [[ "${PROJECT}" == "keystone" ]]; then
  warn --problem "the project name is still the default \"keystone\"" \
    --remedy "Set KEYSTONE_PROJECT, in project.conf or your environment, to name" \
    --remedy "your own output." \
    --see "https://keystone.knight-owl.dev/errors/default-project-name/"
fi

# ── Standard filter pipeline ──────────────────────────────────────────
# Order matters:
#   hooks          — substitute code blocks an external renderer claims,
#                    before anything reads them. Its output is author-level
#                    markup, so author-level expansion has to follow it; and
#                    keystone.lua collects fonts from content, which would
#                    miss anything arriving later. Absent unless a hook is
#                    wired (see the block above)
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
# ── Hooks ─────────────────────────────────────────────────────────────
# Whether a hook is present, and on what terms, is resolved in its own module;
# see .pandoc/resolve-hooks.sh. Naming the filter stays here with the other
# filter lists. Two arrays because the pipelines spell a filter differently:
# the main build resolves a bare name through --data-dir, the pre-scan does not.
resolve_hooks "${FORMAT}"

HOOK_FILTERS=()
PRESCAN_HOOK_FILTERS=()
if [[ -n "${KEYSTONE_HOOKS_DIR:-}" ]]; then
  HOOK_FILTERS=(--lua-filter=hooks.lua)
  PRESCAN_HOOK_FILTERS=(--lua-filter=.pandoc/filters/hooks.lua)
fi

STANDARD_FILTERS=(
  "${HOOK_FILTERS[@]}"
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
  -o "${STAGED_OUTPUT}"
  --data-dir=.pandoc
  --resource-path=.
  --metadata-file="${METADATA}"
  --metadata-file=user-metadata.yaml
  "${STANDARD_FILTERS[@]}"
  "${STRICT_PANDOC_OPTS[@]}"
)

# ── TOC / section-numbering presence ──────────────────────────────────
# --table-of-contents and --number-sections are writer flags: passing them
# unconditionally forces the contents/numbers on in EPUB/DOCX/ODT regardless of
# the toc/numbersections metadata (metadata can't override a writer flag). So
# append each only when its resolved toggle is on. When off, the non-PDF writer
# default (off) governs; PDF reads the same intent from the metadata template
# gate ($if(toc)$ / $if(numbersections)$), which the target yamls leave to
# user-metadata.yaml.
if [[ "${KEYSTONE_TOC}" == 1 ]]; then
  PANDOC_OPTS+=(--table-of-contents)
fi
if [[ "${KEYSTONE_NUMBERSECTIONS}" == 1 ]]; then
  PANDOC_OPTS+=(--number-sections)
fi

# ── Pre-scan filters ──────────────────────────────────────────────────
# Filters that must run before the main Pandoc invocation to collect data
# (e.g. font keys for EPUB embedding). Shortcuts is always prepended so
# scanners see expanded aliases, not raw shortcut classes — and hooks ahead of
# it, so a scanner sees the content a hook produced rather than the code block
# it replaced.
#
# Runs only when at least one scanner filter is needed.
PRESCAN_FILTERS=()

if [[ "${FORMAT}" == "epub" ]]; then
  KEYSTONE_FONT_SCAN_OUTPUT="${KEYSTONE_TMPDIR}/font-scan.txt"
  export KEYSTONE_FONT_SCAN_OUTPUT
  PRESCAN_FILTERS+=(--lua-filter=.pandoc/filters/font-scan.lua)
fi

if [[ ${#PRESCAN_FILTERS[@]} -gt 0 ]]; then
  PRESCAN_FILTERS=(
    "${PRESCAN_HOOK_FILTERS[@]}"
    --lua-filter=.pandoc/filters/shortcuts.lua
    "${PRESCAN_FILTERS[@]}"
  )
  # Frame the phase: a pre-scan failure is otherwise indistinguishable from a
  # main-build failure in the log (both are just Pandoc exiting non-zero). Under
  # strict mode this reader pass is also where Pandoc's own warnings first fail.
  #
  # Reported as one stage rather than its filters: this pass re-runs filters the
  # main build runs too, and naming them twice reads as a stutter. The label is
  # format-neutral because the scanner set is.
  if ! progress_phase "Scanning your manuscript" \
    pandoc "${PRESCAN_FILTERS[@]}" "${STRICT_PANDOC_OPTS[@]}" \
    "${FILES[@]}" --to=native -o /dev/null; then
    fail --problem "publishing failed during the EPUB pre-scan"
  fi
fi

# Format-specific Pandoc options (PANDOC_OPTS only — no side effects)
case "${FORMAT}" in
  pdf)
    # xmp-metadata.lua conditionally injects \usepackage{hyperxmp} into
    # header-includes. Gated to PDF only because hyperxmp is irrelevant
    # for non-LaTeX formats and its preamble would be silently dropped.
    # Bare filter name (no path) — resolved via --data-dir=.pandoc above,
    # matching the STANDARD_FILTERS convention.
    # -no-shell-escape locks XeLaTeX's shell-escape fully off. The default is
    # *restricted* — a command whitelist (kpsewhich, bibtex, …), not zero — so
    # untrusted content could still reach those via \write18 or a piped \openin.
    # No shipped feature needs shell-escape, so refuse it outright, closing both
    # as code-execution vectors.
    PANDOC_OPTS+=(
      --pdf-engine=xelatex
      --pdf-engine-opt=-no-shell-escape
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

    # Dependencies: KEYSTONE_FONTFAMILY, KEYSTONE_MONOFONT, KEYSTONE_FONT_SCAN_OUTPUT
    #
    # The @font-face CSS is generated by keystone.lua; this puts the files it
    # names into the archive, and the terms each of them travels under.
    epub_staged="${KEYSTONE_TMPDIR}/epub-staged.txt"
    resolve_epub_fonts "${KEYSTONE_TMPDIR}" "${epub_staged}" \
      pandoc lua .pandoc/filters/lib/epub-font-paths.lua

    readarray -t staged_fonts < "${epub_staged}"
    for staged_font in "${staged_fonts[@]}"; do
      PANDOC_OPTS+=("--epub-embed-font=${staged_font}")
    done
    ;;
  docx | odt)
    # reference_mask (resolve-metadata.sh) owns the bit layout; we just map
    # the resulting opaque mask to its pre-built reference-doc variant.
    ref_mask=$(reference_mask)
    ref_bits=$(mask_to_bits "${ref_mask}")
    ref_path=".pandoc/includes/reference-${ref_bits}.${FORMAT}"
    if [[ ! -f "${ref_path}" ]]; then
      warn --problem "reference variant ${ref_bits} not found;" \
        --problem "falling back to the base reference document"
      ref_bits=$(mask_to_bits 0)
      ref_path=".pandoc/includes/reference-${ref_bits}.${FORMAT}"
    fi
    PANDOC_OPTS+=(--reference-doc="${ref_path}")
    ;;
esac

# ── TOC depth ─────────────────────────────────────────────────────────
# EPUB/DOCX/ODT honor --toc-depth. PDF gets no flag: the author's toc-depth is
# in metadata, which overrides this flag for PDF, so keystone.lua delivers it
# there instead. All formats draw the same resolved KEYSTONE_TOC_DEPTH. Passed
# regardless of toc: an EPUB's navigation document is always generated and takes
# its depth from this flag. Gating on toc would let that nav fall back to Pandoc's
# default depth once toc: false drops the flag; for DOCX/ODT the flag is a
# harmless no-op then, as toc: false leaves no TOC field to bound.
if [[ "${FORMAT}" != "pdf" ]]; then
  PANDOC_OPTS+=(--toc-depth="${KEYSTONE_TOC_DEPTH}")
fi

# ── Code theme ────────────────────────────────────────────────────────
# KEYSTONE_CODE_THEME is resolved (with its default) by resolve_metadata
# above; here we validate the theme dir exists and pass it to Pandoc.
if [[ ! -d ".pandoc/filters/code-themes/${KEYSTONE_CODE_THEME}" ]]; then
  fail --problem "unknown code-theme '${KEYSTONE_CODE_THEME}'" \
    --remedy "See pandoc.yaml for the themes this image carries."
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
if ! progress_pandoc "${PANDOC_OPTS[@]}"; then
  fail --problem "publishing failed during the main build (format: ${FORMAT})"
fi

# Strict gate: report-all-then-fail. The build finished, but if any warning
# tripped the sink, refuse to promote the staged artifact and list what tripped.
if warnings_as_errors && [[ -s "${KEYSTONE_WARNING_SINK}" ]]; then
  # De-dupe: a filter that runs in both the pre-scan and main pass (shortcuts)
  # appends the same warning twice, but each should show once. Each tripped
  # warning goes in as its own offender, so they list verbatim under the ERROR.
  recap=$(awk '!seen[$0]++' "${KEYSTONE_WARNING_SINK}")
  readarray -t tripped <<< "${recap}"
  offenders=()
  for tripped_warning in "${tripped[@]}"; do
    offenders+=(--offenders "${tripped_warning}")
  done
  fail --problem "warnings-as-errors is enabled and the build produced warnings:" \
    "${offenders[@]}" \
    --effect "No new artifact was written." \
    --remedy "Fix the warnings above, or unset KEYSTONE_WARNINGS_AS_ERRORS for a" \
    --remedy "lenient build." \
    --see "https://keystone.knight-owl.dev/errors/#strict-mode"
fi

# Promote the staged artifact into place — the build is clean. Framed like the
# build phases so a read-only artifacts/ reads as a publish failure, not a bare
# mv error.
if ! mv "${STAGED_OUTPUT}" "${OUTPUT}"; then
  fail --problem "publishing failed while promoting the artifact to ${OUTPUT}" \
    --see "https://keystone.knight-owl.dev/errors/artifact-not-written/"
fi
TOTAL=$(progress_duration "${BUILD_START}")
echo "OK: ${OUTPUT} (${TOTAL})"
echo ""
