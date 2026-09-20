#!/usr/bin/env bash
set -euo pipefail

# extract-font-licenses.sh — Stage each font's license beside the font
#
# Runs in the Docker font-extractor stage after extract-fonts.sh, copying the
# terms of every staged font to the path its row names. README.md in this
# directory owns why they ship, how a license is located, and why a row names
# both ends.
#
# Every staged font directory has to be covered by a row — a font whose license
# nobody located would otherwise ship without its terms, silently.
#
# Rows are read here rather than through packages/read-packages.sh: these carry
# two paths, where a package declaration carries a name and a free-text note.
#
# A list-command may follow, printing the paths font-registry.lua declares in
# its entries' main.license, relative to the staged tree (in practice `pandoc
# lua .../list-builtin-font-licenses.lua`). Every one has to have been staged:
# the registry names those files to put them in an EPUB beside the font, so one
# the copy list never staged would reach the publish step as a path that is not
# there. The declaration and the registry are two records of one set, and this
# is where they are held to each other.
#
# Usage: extract-font-licenses.sh <declaration> [list-command [args...]]
#   e.g. extract-font-licenses.sh .docker/fonts/licenses.copy.txt \
#          pandoc lua .pandoc/filters/lib/list-builtin-font-licenses.lua
#
# Environment:
#   DOC_ROOT    — TeX Live doc tree to copy from
#                 (default /opt/texlive/texdir/texmf-dist/doc)
#   STAGING_DIR — the tree extract-fonts.sh staged (default /staging)

DOC_ROOT="${DOC_ROOT:-/opt/texlive/texdir/texmf-dist/doc}"
STAGING_DIR="${STAGING_DIR:-/staging}"

if [[ $# -lt 1 ]]; then
  echo "ERROR: a declaration is required" >&2
  echo "  usage: extract-font-licenses.sh <declaration> [list-command [args...]]" >&2
  exit 2
fi
declaration="$1"
shift

if [[ ! -f "${declaration}" ]]; then
  echo "ERROR: declaration not found: ${declaration}" >&2
  exit 1
fi

if [[ ! -d "${STAGING_DIR}" ]]; then
  echo "ERROR: no staged font tree at ${STAGING_DIR}" >&2
  exit 1
fi

# Read before the first copy, so the licenses cannot answer for themselves in
# the coverage check below.
staged="$(find "${STAGING_DIR%/}" -type f)"
if [[ -z "${staged}" ]]; then
  echo "ERROR: the staged font tree is empty: ${STAGING_DIR}" >&2
  exit 1
fi

font_dirs=""
while IFS= read -r file; do
  dir="$(dirname "${file}")"
  font_dirs+="${dir#"${STAGING_DIR%/}/"}"$'\n'
done <<< "${staged}"
font_dirs="$(sort -u <<< "${font_dirs}")"

# An unreadable declaration fails the redirect, which ends the script — where
# reading it through a filter would hand back nothing and look like a file of
# comments.
count=0
covered=""
while IFS= read -r row || [[ -n "${row}" ]]; do
  row="${row#"${row%%[![:space:]]*}"}"
  [[ -n "${row}" ]] || continue
  [[ "${row}" != '#'* ]] || continue

  read -r rel_src rel_dst extra <<< "${row}"
  if [[ -z "${rel_dst}" || -n "${extra}" ]]; then
    echo "ERROR: a row needs a license path and where it lands: ${row}" >&2
    exit 1
  fi

  # The contract, and the reason a destination may name its own file: what it
  # names has to sit in a directory the registry staged fonts into. That holds
  # a license beside the fonts it covers and one level deep, so a destination
  # cannot wander into a path of its own.
  rel_dir="$(dirname "${rel_dst}")"
  if ! grep -qxF -- "${rel_dir}" <<< "${font_dirs}"; then
    echo "ERROR: ${rel_dst} does not land beside a staged font —" >&2
    echo "  no font is staged in ${rel_dir}" >&2
    exit 1
  fi

  src="${DOC_ROOT%/}/${rel_src}"
  dst="${STAGING_DIR%/}/${rel_dst}"
  if [[ ! -f "${src}" ]]; then
    echo "ERROR: declared license is absent from the image: ${src}" >&2
    exit 1
  fi

  # Refused rather than overwritten: a second row on one destination would
  # leave a family's terms unshipped with the count and the coverage check
  # both satisfied.
  if [[ -e "${dst}" ]]; then
    echo "ERROR: ${rel_dst} already exists in the staged tree" >&2
    exit 1
  fi

  cp "${src}" "${dst}"
  covered+="${rel_dir}"$'\n'
  count=$((count + 1))
done < "${declaration}"

uncovered=()
while IFS= read -r dir; do
  [[ -n "${dir}" ]] || continue
  grep -qxF -- "${dir}" <<< "${covered}" || uncovered+=("${dir}")
done <<< "${font_dirs}"

if [[ ${#uncovered[@]} -gt 0 ]]; then
  echo "ERROR: staged fonts carrying no license:" >&2
  printf '  %s\n' "${uncovered[@]}" >&2
  echo "  Declare one per directory in ${declaration} —" >&2
  echo "  .docker/fonts/README.md says how to find one" >&2
  exit 1
fi

# Held after staging, so the comparison is against what actually landed rather
# than against the rows that were meant to produce it.
if [[ $# -gt 0 ]]; then
  # Captured first, so a failing list-command aborts the build rather than
  # passing this check with nothing to say.
  declared="$("$@")"
  if [[ -z "${declared}" ]]; then
    echo "ERROR: the list-command produced no license files" >&2
    exit 1
  fi

  unstaged=()
  while IFS= read -r rel; do
    [[ -n "${rel}" ]] || continue
    # A `..` would resolve outside the tree and could report a file that is not
    # in the image as staged. The paths are the registry's own, so this holds a
    # property rather than filtering untrusted input.
    if [[ "/${rel}/" == */../* ]]; then
      echo "ERROR: a declared license path climbs out of the staged tree: ${rel}" >&2
      exit 1
    fi
    [[ -f "${STAGING_DIR%/}/${rel}" ]] || unstaged+=("${rel}")
  done <<< "${declared}"

  if [[ ${#unstaged[@]} -gt 0 ]]; then
    echo "ERROR: the registry declares licenses nothing staged:" >&2
    printf '  %s\n' "${unstaged[@]}" >&2
    echo "  Add a row for each to ${declaration}, or correct the" >&2
    echo "  main.license entry naming it — README.md says how" >&2
    exit 1
  fi

  # And the other way: a row can stage a text the registry has stopped naming.
  # The copy list alone cannot see that — its own row is what satisfies the
  # coverage check above — so the font would ship with terms no build carries.
  # This is the direction only the registry can answer, and the only gate a
  # fork has for it.
  declared_dirs=""
  while IFS= read -r rel; do
    [[ -n "${rel}" ]] || continue
    declared_dirs+="${rel%/*}"$'\n'
  done <<< "${declared}"

  undeclared=()
  while IFS= read -r dir; do
    [[ -n "${dir}" ]] || continue
    grep -qxF -- "${dir}" <<< "${declared_dirs}" || undeclared+=("${dir}")
  done <<< "${font_dirs}"

  if [[ ${#undeclared[@]} -gt 0 ]]; then
    echo "ERROR: staged fonts the registry names no license for:" >&2
    printf '  %s\n' "${undeclared[@]}" >&2
    echo "  Name the staged text in that family's main.license —" >&2
    echo "  README.md says how" >&2
    exit 1
  fi
fi

echo "Staged ${count} license file(s) into ${STAGING_DIR}"
