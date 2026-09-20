#!/usr/bin/env bash

# resolve-epub-fonts.sh — Stage what an EPUB embeds, and name the flags for it
#
# Pandoc names an archive entry after the basename of the file it is handed, so
# a file can only arrive under the name it already has. A license has to arrive
# under a different one, and one text covers several fonts, so the same source
# has to arrive several times over. Every entry therefore gets a symlink here,
# named as it will appear, and the link is what Pandoc is given.
#
# The contract with the enumerator: a row is `<source-path>\t<archive-name>`,
# written to the file named by KEYSTONE_EPUB_EMBED_ROWS. The enumerator itself
# arrives as arguments rather than hard-coded, as it does for
# .docker/fonts/extract-fonts.sh and for the reason that header gives.
#
# Side effects, all of them — this does more than its name suggests:
#   • exports KEYSTONE_EPUB_EMBED_ROWS, and the enumerator writes that file
#   • runs the enumerator as the build stage "Collecting your fonts"
#   • creates <tmpdir>/epub-fonts/ and one symlink in it per row
#   • writes <staged-list>, one staged link per line, in row order
#   • ends the build, through fail, on an enumerator that exits non-zero or a
#     name staged twice
#
# The caller names the list rather than reading a variable both sides have to
# know, so the handover is visible at each end.
#
# Usage: source .pandoc/resolve-epub-fonts.sh
#        resolve_epub_fonts <tmpdir> <staged-list> <enumerator-command> [args...]
#        then: readarray -t fonts < <staged-list>
#   Sourced rather than run, and the list written rather than printed: read
#   through a command substitution, a fail in here would end only that subshell
#   and leave a half-staged archive reported nowhere.

# fail comes from diagnostics.sh and progress_phase from progress.sh. Sourced
# here rather than relied on from the caller: publish.sh happens to source both
# above this file, and nothing states or checks that order.
# shellcheck source=src/runtime/.pandoc/diagnostics.sh
source "$(dirname "${BASH_SOURCE[0]}")/diagnostics.sh"
# shellcheck source=src/runtime/.pandoc/progress.sh
source "$(dirname "${BASH_SOURCE[0]}")/progress.sh"

# The rows go to a file because progress_phase leaves a command's stdout alone
# and writes the stage line to it, so rows sent there would reach the terminal.
resolve_epub_fonts() {
  local tmpdir="$1"
  local staged_list="$2"
  shift 2

  KEYSTONE_EPUB_EMBED_ROWS="${tmpdir}/epub-embed-rows.txt"
  export KEYSTONE_EPUB_EMBED_ROWS

  if ! progress_phase "Collecting your fonts" "$@"; then
    fail --problem "publishing failed while collecting the fonts to embed"
  fi

  local staging="${tmpdir}/epub-fonts"
  mkdir -p "${staging}"

  # Truncated rather than appended to, so the list holds this call's staging
  # and nothing else.
  : > "${staged_list}"

  local source name
  while IFS=$'\t' read -r source name; do
    [[ -n "${name}" ]] || continue
    if ! ln -s "${source}" "${staging}/${name}"; then
      fail --problem "publishing failed while staging '${name}' to embed"
    fi
    printf '%s\n' "${staging}/${name}" >> "${staged_list}"
  done < "${KEYSTONE_EPUB_EMBED_ROWS}"
}
