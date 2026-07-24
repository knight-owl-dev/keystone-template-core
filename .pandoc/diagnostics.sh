#!/usr/bin/env bash

# diagnostics.sh — Shell-side diagnostic output (WARN/ERROR) and strict policy
#
# The publishing scripts report problems through warn/fail instead of
# hand-rolling `echo "..." >&2` (and exit), so the WARN/ERROR labels, message
# shape, and the warnings-as-errors policy have one shell-side owner. This is the
# shell analog of the Lua filters' errors lib (filters/lib/errors.lua) — same
# convention, separate runtime, so a separate implementation.
#
# Scope is diagnostics only: what goes *wrong*, on stderr. Success and progress
# output (`OK:`, on stdout) is the caller's — deliberately outside this boundary,
# as it is for the Lua errors lib. That is why there is no `ok` here.
#
#   warn <msg>            non-fatal — print; under strict mode, fail the build
#   fail <msg> [hint...]  terminal — print ERROR (+ indented hints), then exit 1
#   warnings_as_errors    succeed when strict mode is on
#
# Environment:
#   KEYSTONE_WARNINGS_AS_ERRORS — strict builds: true/1/yes/on makes any warning
#                                 fatal (default false)
#
# Usage: source diagnostics.sh

# warnings_as_errors — succeed when strict mode is on. The sole interpreter of
# KEYSTONE_WARNINGS_AS_ERRORS (true/1/yes/on, any case), so warn() and the
# caller's build gate agree on the truthy set.
warnings_as_errors() {
  local value="${KEYSTONE_WARNINGS_AS_ERRORS:-false}"
  case "${value,,}" in
    true | 1 | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

# fail <message> [hint...] — print an ERROR line, then any indented hint lines,
# to stderr and exit 1. When called inside a $(…) command substitution the exit
# ends only that subshell; the caller's `set -e` then propagates the failure.
fail() {
  echo "ERROR: $1" >&2
  shift
  local hint
  for hint in "$@"; do
    echo "  ${hint}" >&2
  done
  exit 1
}

# warn <message> — print a WARN line to stderr. Under strict mode the warning is
# fatal (routes through fail); otherwise it prints and returns so the caller can
# fall back to its default.
warn() {
  echo "WARN: $*" >&2
  if warnings_as_errors; then
    fail "warnings-as-errors is enabled — the warning above stops the build"
  fi
}
