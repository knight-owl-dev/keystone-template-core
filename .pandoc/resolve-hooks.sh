#!/usr/bin/env bash

# resolve-hooks.sh — Decide whether this build talks to a hook, and on what terms
#
# A hook is an external process the author wires in through compose; it
# announces itself by leaving a socket in .hooks/. Deciding once, here, keeps
# the cost off every project that wires none: with no socket the filter is
# never staged, so there is no load and no walk to skip. A socket is what is
# looked for, not the directory — a named volume mounts empty.
#
# The author's three settings (timeout, cache location, cache size) are
# resolved and re-exported for the Lua filter to read. Where the cache lives is
# resolve_hook_cache's question, below.
#
# Environment:
#   KEYSTONE_HOOKS_TIMEOUT    — seconds a hook has to answer (optional, 30)
#   KEYSTONE_HOOKS_CACHE      — where replies are remembered (optional,
#                               .hooks-cache)
#   KEYSTONE_HOOKS_CACHE_MAX  — megabytes that cache may hold (optional, 64)
#
# Usage: source .pandoc/resolve-hooks.sh
#        resolve_hooks <format>
#   Exports KEYSTONE_HOOKS_DIR when a socket is present — the signal a caller
#   stages the hook filter on — along with the three settings above and
#   KEYSTONE_FORMAT. Which filter files a caller stages is its own business.
#
#   resolve_hook_cache is the second half, split out because where the cache
#   lives and how big it may be is a separate question from whether a hook is
#   listening — and the one a build can get wrong.

# shellcheck source=src/runtime/.pandoc/diagnostics.sh
source "$(dirname "${BASH_SOURCE[0]}")/diagnostics.sh"

# Directory a hook publishes its socket into, and the one the engine keeps its
# replies in. Both are relative to the working directory, which is the project
# root inside the container, and both arrive as volumes compose mounts.
KEYSTONE_HOOKS_DIR_DEFAULT=".hooks"
KEYSTONE_HOOKS_CACHE_DEFAULT=".hooks-cache"

resolve_hooks() {
  local format="${1:?resolve_hooks requires a format}"
  local hooks_dir="${KEYSTONE_HOOKS_DIR_DEFAULT}"

  unset KEYSTONE_HOOKS_DIR KEYSTONE_FORMAT

  local socket
  for socket in "${hooks_dir}"/*.sock; do
    [[ -S "${socket}" ]] || continue

    KEYSTONE_HOOKS_DIR="${hooks_dir}"
    # socat takes this verbatim; a value it cannot parse fails the connection,
    # which would otherwise be reported as a hook that did not answer.
    KEYSTONE_HOOKS_TIMEOUT="${KEYSTONE_HOOKS_TIMEOUT:-30}"
    if [[ ! "${KEYSTONE_HOOKS_TIMEOUT}" =~ ^[1-9][0-9]*$ ]]; then
      fail --problem "KEYSTONE_HOOKS_TIMEOUT must be a whole number of seconds," \
        --problem "got '${KEYSTONE_HOOKS_TIMEOUT}'" \
        --see "https://keystone.knight-owl.dev/errors/hook-failed/#the-cache-rather-than-the-hook"
    fi
    KEYSTONE_FORMAT="${format}"
    export KEYSTONE_HOOKS_DIR KEYSTONE_HOOKS_TIMEOUT KEYSTONE_FORMAT

    resolve_hook_cache
    return 0
  done
}

# The default is a volume compose mounts for the engine alone, so nothing an
# author does to artifacts/ can leave a build without a cache. A path of their
# own is theirs to make writable, and this says so plainly if they have not.
resolve_hook_cache() {
  KEYSTONE_HOOKS_CACHE="${KEYSTONE_HOOKS_CACHE:-${KEYSTONE_HOOKS_CACHE_DEFAULT}}"
  if ! mkdir -p "${KEYSTONE_HOOKS_CACHE}"; then
    fail --problem "KEYSTONE_HOOKS_CACHE is '${KEYSTONE_HOOKS_CACHE}'," \
      --problem "which could not be created" \
      --because "The cache needs a writable mount." \
      --see "https://keystone.knight-owl.dev/errors/hook-failed/#the-cache-rather-than-the-hook"
  fi

  # mkdir -p is satisfied by a directory that already exists, and the default's
  # always does: it ships in the image as the volume's mountpoint. Only a write
  # separates a mounted volume from that bare directory under a read-only
  # rootfs, which is what a compose file missing the volume leaves behind.
  # Asking now names the path; the alternative fails mid-render.
  local probe="${KEYSTONE_HOOKS_CACHE}/.write-probe"
  if ! : > "${probe}" 2> /dev/null; then
    fail --problem "KEYSTONE_HOOKS_CACHE is '${KEYSTONE_HOOKS_CACHE}'," \
      --problem "which could not be written" \
      --because "The cache needs a writable mount." \
      --see "https://keystone.knight-owl.dev/errors/hook-failed/#the-cache-rather-than-the-hook"
  fi
  rm -f "${probe}"

  # Megabytes because that is the unit an author thinks in; the filter
  # converts. A print-resolution diagram runs to a couple of hundred kilobytes,
  # so the default holds a few hundred of them.
  KEYSTONE_HOOKS_CACHE_MAX="${KEYSTONE_HOOKS_CACHE_MAX:-64}"
  if [[ ! "${KEYSTONE_HOOKS_CACHE_MAX}" =~ ^[1-9][0-9]*$ ]]; then
    fail --problem "KEYSTONE_HOOKS_CACHE_MAX must be a whole number of megabytes," \
      --problem "got '${KEYSTONE_HOOKS_CACHE_MAX}'" \
      --see "https://keystone.knight-owl.dev/errors/hook-failed/#the-cache-rather-than-the-hook"
  fi
  export KEYSTONE_HOOKS_CACHE KEYSTONE_HOOKS_CACHE_MAX
}
