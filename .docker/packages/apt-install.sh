#!/usr/bin/env bash
set -euo pipefail

# apt-install.sh — Install apt packages from declarations and assert they landed
#
# Wraps apt-get in the Docker stages: update, install, drop the package lists.
# The names come from the declarations, so the set a stage installs is named
# once however many stages install it.
#
# The assertion is a post-condition. `apt-get install` exits 0 having installed
# nothing when its argument list is empty, and a name that resolves through a
# virtual package installs a provider under a different one; neither shows in
# its exit status, and BuildKit caches the layer either way.
#
# The retry, timeout and strict-update settings come from /etc/apt/apt.conf,
# which each stage copies from keystone.aptconf; its header owns what they are
# and why. Nothing here passes `-o`, so the conf stays apt's last word on them.
#
# The apt calls, the installed query, and the lists it clears are overridable so
# the assertion is exercisable without apt.
#
# Usage: apt-install.sh --from-file <path> [--from-file <path>]...
#
# Environment:
#   APT_UPDATE     — command that refreshes the package index
#                    (default `apt-get -q --no-allow-insecure-repositories update`)
#   APT_INSTALL    — command that installs the packages named after it
#                    (default `apt-get install --assume-yes --no-install-recommends`)
#   APT_INSTALLED  — command that prints the installed package names, one per
#                    line (default a `dpkg-query` over the status database)
#   APT_LISTS      — directory of fetched package indexes, emptied on success
#                    (default `/var/lib/apt/lists`)

USAGE="usage: apt-install.sh --from-file <path> [--from-file <path>]..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/runtime/.docker/packages/read-packages.sh
source "${SCRIPT_DIR}/read-packages.sh"

declare -a declarations=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-file)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --from-file needs a path" >&2
        echo "  ${USAGE}" >&2
        exit 2
      fi
      declarations+=("$2")
      shift 2
      ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      echo "  ${USAGE}" >&2
      exit 2
      ;;
  esac
done

if [[ "${#declarations[@]}" -eq 0 ]]; then
  echo "ERROR: at least one --from-file is required" >&2
  echo "  ${USAGE}" >&2
  exit 2
fi

# Read through a variable, not a pipeline: a declaration that fails partway
# still prints the names it reached, and reading those directly would install a
# short set under a successful exit.
names="$(read_package_names "${declarations[@]}")"
readarray -t packages <<< "${names}"

# The `=*` version glob matches any candidate, so apt resolves a request exactly
# as it would the bare name, in the explicit-version form Dockerfile linters ask
# for.
declare -a requests=()
for package in "${packages[@]}"; do
  requests+=("${package}=*")
done

read -ra update_cmd <<< "${APT_UPDATE:-apt-get -q --no-allow-insecure-repositories update}"
read -ra install_cmd <<< "${APT_INSTALL:-apt-get install --assume-yes --no-install-recommends}"

"${update_cmd[@]}"
DEBIAN_FRONTEND=noninteractive "${install_cmd[@]}" "${requests[@]}"

# A failing query aborts here rather than yielding an empty list, which would
# report every package missing. `triggers-pending` and `triggers-awaited` count
# alongside `installed`: the files are all there, waiting on another package's
# trigger, and apt leaves a package in either state often enough that reading
# it as missing would fail a build that succeeded.
if [[ -n "${APT_INSTALLED:-}" ]]; then
  read -ra installed_cmd <<< "${APT_INSTALLED}"
  installed="$("${installed_cmd[@]}")"
else
  installed="$(dpkg-query -W -f='${Package} ${Status}\n' \
    | awk '$4 ~ /^(installed|triggers-pending|triggers-awaited)$/ { print $1 }')"
fi

missing=()
for package in "${packages[@]}"; do
  grep -qxF -- "${package}" <<< "${installed}" || missing+=("${package}")
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "ERROR: apt-get reported success, but these packages are not installed:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "  A name that resolves through a virtual package installs its provider instead;" >&2
  echo "  declare the package that ships" >&2
  exit 1
fi

rm -rf "${APT_LISTS:-/var/lib/apt/lists}"/*

echo "Installed ${#packages[@]} package(s)"
