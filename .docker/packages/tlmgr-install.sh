#!/usr/bin/env bash
set -euo pipefail

# tlmgr-install.sh — Install TeX Live packages and assert tlmgr recorded them
#
# Wraps `tlmgr install` in the Docker builder stages, then asserts every
# requested package is recorded as installed. tlmgr can exit 0 having installed
# less than it was asked for; a pinned snapshot serving an incomplete set is
# enough. BuildKit then caches that layer, so the shortfall ships. Nothing
# downstream checks completeness: the font extractor catches missing font files
# and nothing else, and a missing .sty surfaces when an author renders content
# that loads it.
#
# The assertion is a post-condition, so it holds however the shortfall arose. An
# unknown package name already fails on its own; what this adds is the case of a
# known name whose content never arrived.
#
# It also asserts that tlmgr verified the repository's signature. tlmgr runs
# that check and installs regardless of the answer. No flag makes it a gate:
# --require-verification is deprecated into --verify-repo=all, which hard-fails
# only when gpg is missing outright. The keyring is the one install-tl laid
# down, pinned with the snapshot.
#
# One status covers every package: the signed database it verifies carries a
# checksum for each archive, and tlmgr checks every archive it fetches.
#
# The files themselves go unchecked. `tlmgr check files` would cover them, and
# `tlmgr check depends` the closure, but both exit non-zero on a healthy image
# here, so neither can gate a build. A package recorded with its files missing
# therefore passes.
#
# The two tlmgr calls are overridable so the check is exercisable without TeX
# Live.
#
# Doc files are off across the install (install-texlive.sh sets the profile
# option); --with-doc turns them back on for one declaration. What needs them is
# a font whose files ship — .docker/fonts/README.md owns why.
#
# Usage: tlmgr-install.sh [--with-doc] --from-file <path> [--from-file <path>]...
#
# Environment:
#   TLMGR_INSTALL   — command that installs the packages named after it
#                     (default `tlmgr install`)
#   TLMGR_INSTALLED — command that prints the installed package names, one per
#                     line (default `tlmgr info --only-installed --data name`)

USAGE="usage: tlmgr-install.sh [--with-doc] --from-file <path> [--from-file <path>]..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/runtime/.docker/packages/read-packages.sh
source "${SCRIPT_DIR}/read-packages.sh"

declare -a package_files=()
with_doc=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-doc)
      with_doc=true
      shift
      ;;
    --from-file)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --from-file needs a path" >&2
        echo "  ${USAGE}" >&2
        exit 2
      fi
      package_files+=("$2")
      shift 2
      ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      echo "  ${USAGE}" >&2
      exit 2
      ;;
  esac
done

if [[ "${#package_files[@]}" -eq 0 ]]; then
  echo "ERROR: at least one --from-file is required" >&2
  echo "  ${USAGE}" >&2
  exit 2
fi

# Read through a variable, not a pipeline: a declaration that fails partway
# still prints the names it reached, and reading those directly would install a
# short set under a successful exit.
names="$(read_package_names "${package_files[@]}")"
readarray -t packages <<< "${names}"

read -ra install_cmd <<< "${TLMGR_INSTALL:-tlmgr install}"
if [[ "${with_doc}" == true ]]; then
  install_cmd+=(--with-doc)
fi
read -ra installed_cmd <<< "${TLMGR_INSTALLED:-tlmgr info --only-installed --data name}"

# Streamed as it runs: capturing the output would withhold the install's
# progress to the end.
install_log="$(mktemp)"
trap 'rm -f "${install_log}"' EXIT

"${install_cmd[@]}" "${packages[@]}" | tee "${install_log}"

# Matched positively: the statuses tlmgr reports instead are upstream's to
# extend, and an enumeration of today's would pass one added later.
if ! grep -qF '(verified)' "${install_log}"; then
  echo "ERROR: tlmgr did not verify the package repository," >&2
  echo "  so the packages it installed are unauthenticated" >&2
  echo "  Its status line above says which check failed: it needs gpg on PATH," >&2
  echo "  and a key it cannot use means advancing TL_SNAPSHOT" >&2
  exit 1
fi

# A failing query aborts here (set -e on the command substitution) rather than
# yielding an empty list, which would report every package missing.
installed="$("${installed_cmd[@]}")"

# Exact, because the lists carry both lm and lm-math. Literal, because a
# package name may carry a dot.
missing=()
for pkg in "${packages[@]}"; do
  grep -qxF -- "${pkg}" <<< "${installed}" || missing+=("${pkg}")
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "ERROR: tlmgr reported success, but these packages are not installed:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "  The pinned snapshot is serving an incomplete set —" >&2
  echo "  retry once it has recovered, or move TL_SNAPSHOT to a date that carries them" >&2
  exit 1
fi

echo "Installed ${#packages[@]} package(s) from a verified repository"
