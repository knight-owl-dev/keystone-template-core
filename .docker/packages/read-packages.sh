#!/usr/bin/env bash

# read-packages.sh — Read package names out of the declarations
#
# The install wrappers take declaration paths rather than package names, so a
# list that two stages install has one place to live. The guards are why that
# reading is shared: a declaration resolving to no names makes `apt-get install`
# a successful no-op, and `tlmgr install` likewise. BuildKit then caches the
# layer that installed nothing.
#
# Usage (in caller):
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/read-packages.sh"
#   read_package_names <file> [<file>...]
#
#   Prints column one of every row, one name per line, in the order the files
#   and their rows are given.

read_package_names() {
  if [[ $# -eq 0 ]]; then
    echo "ERROR: read_package_names needs at least one declaration" >&2
    return 2
  fi

  local declaration rows row rc
  for declaration in "$@"; do
    if [[ ! -f "${declaration}" ]]; then
      echo "ERROR: package file not found: ${declaration}" >&2
      return 2
    fi

    # Exit 1 is a file of nothing but comments, which the guard below refuses;
    # 2 and up is grep itself failing, which would otherwise read as that same
    # empty file and install silently short.
    rc=0
    rows=$(grep -Ev '^[[:space:]]*#|^[[:space:]]*$' "${declaration}") || rc=$?
    if [[ ${rc} -ge 2 ]]; then
      echo "ERROR: could not read package file: ${declaration}" >&2
      return 2
    fi
    if [[ -z "${rows}" ]]; then
      echo "ERROR: package file declares no packages: ${declaration}" >&2
      return 2
    fi

    while IFS= read -r row; do
      # Leading whitespace first: the comment filter tolerates an indented
      # comment, so a reader may reasonably indent a row too — and column one of
      # an indented row is the empty string, which an installer takes as an
      # argument.
      row="${row#"${row%%[![:space:]]*}"}"
      printf '%s\n' "${row%%[[:space:]]*}"
    done <<< "${rows}"
  done
}
