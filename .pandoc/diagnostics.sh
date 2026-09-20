#!/usr/bin/env bash

# diagnostics.sh — Shell-side diagnostic output (WARN/ERROR) and strict policy
#
# The publishing scripts report problems through warn/fail instead of
# hand-rolling `echo "..." >&2` (and exit), so the WARN/ERROR labels, message
# presentation, and the warnings-as-errors policy have one shell-side owner.
# This is the shell analog of the Lua filters' errors lib
# (filters/lib/errors.lua) — same callouts, same rendered shape, separate
# runtime, so a separate implementation, kept in step by one catalogue of cases
# that drives both and diffs the text.
#
# Scope is diagnostics only: what goes *wrong*, on stderr. Success and progress
# output (`OK:`, on stdout) is the caller's — deliberately outside this boundary,
# as it is for the Lua errors lib. That is why there is no `ok` here.
#
#   warn <callout...>     non-fatal — print; under strict mode, fail the build
#   fail <callout...>     terminal — print, then exit 1
#   warnings_as_errors    succeed when strict mode is on
#
# A caller declares the PIECES of a diagnostic and this file assembles them —
# no labels, no gutter, no line breaks at the call site:
#
#   fail --problem "unsupported format '${FORMAT}'" \
#        --choices pdf --choices epub --choices docx --choices odt
#
#   --problem    what went wrong — a fragment reading on from "ERROR: ", so it
#                opens lowercase and ends in no terminator
#   --offenders  one of the items that caused it — Keystone's own enumeration
#   --verbatim   text Keystone did not write, reproduced as it arrived behind a
#                quote bar that says whose words these are
#   --because    the rule the problem breaks — a sentence
#   --effect     the consequence the problem had: a fallback applied, an input
#                skipped, an artifact not written — a sentence
#   --choices    the values that would have been accepted
#   --remedy     what to do about it — a sentence
#   --see        a URL worth following — usually the manual. Gets its own line
#                and is never wrapped
#
# The casing each takes, and the rule that settles which of `--because` and
# `--effect` a sentence belongs to, are the manual's:
# https://keystone.knight-owl.dev/engine/diagnostics/
#
# A flag repeats and appends, so a caller breaks a long sentence across source
# lines however it reads best; the join is per callout (prose by space, choices
# by comma, offenders by line). `--see` is the exception, carrying one URL and
# refusing a repeat.
#
# A lone bare argument is read as `--problem`, which is the string form handlers
# and forkers use. Beside flags it is refused rather than folded into the
# problem.
#
# The flags spell the callouts exactly — `--offenders` reads oddly for one item,
# but a flag named for the key it fills is a flag nothing has to translate,
# here or in the hook protocol that mirrors the same vocabulary.
#
# A flag this file does not render is an internal bug, not author input, so it
# stops the build rather than silently dropping the piece it carried.
#
# No callout can break the frame, whichever one carries the text: see
# _diag_printable below.
#
# Environment:
#   KEYSTONE_WARNINGS_AS_ERRORS — strict builds: true/1/yes/on makes any warning
#                                 fatal (default false)
#
# Usage: source diagnostics.sh

# Hard-coded rather than read from COLUMNS: rendering has to be a pure function
# of the callouts, or the shared fixtures cannot assert the text a diagnostic
# prints. Matches WIDTH in filters/lib/errors.lua.
# Plain, not readonly: publish.sh and each resolver source this file, and a
# second source would fail on a readonly reassignment.
_DIAG_WIDTH=80
_DIAG_GUTTER="  "
# Relayed text carries a quote bar, so an author can see at a glance which lines
# are Keystone's and which belong to the tool it is reporting for. The bar also
# gives the relayed text a left edge of its own, so a caret it carries still
# lands under the token it marks.
_DIAG_QUOTE_BAR="│ "
_DIAG_CHOICES_LABEL="Valid: "
# A wrapped value list hangs under its label, so its continuation cannot be read
# as the start of the next callout. Derived, not counted: the Lua renderer
# derives it too, and a hand-written width is a second place to keep in step.
printf -v _DIAG_CHOICES_HANG '%*s' "${#_DIAG_CHOICES_LABEL}" ''

# _diag_bug <what> — an internal-invariant complaint, printed flat. It cannot
# route through fail(): fail is what calls this, and the callout that reached
# here is the thing that could not be rendered.
_diag_bug() {
  # Through the filter like any other line: the text carries a caller's value —
  # `'$1' is not a callout` quotes whatever it was handed — and a diagnostic
  # about a broken diagnostic is no place to start printing raw bytes.
  #
  # Its newlines are caret-ed first, for the reason --see's are: one would be a
  # record boundary before the filter ever read it.
  _diag_printable <<< "ERROR: diagnostics: ${1//$'\n'/^J}" >&2
  exit 1
}

# _diag_wrap <first-prefix> <rest-prefix> <text> — the text wrapped to
# _DIAG_WIDTH, each line carrying its prefix.
#
# LC_ALL=C makes awk count bytes everywhere, and a UTF-8 character is one lead
# byte plus its continuation bytes — so stripping 0x80–0xBF leaves exactly one
# byte per character, whatever awk the host ships. Counting bytes instead would
# over-measure every em dash and break the line early; `fold -s` is byte-based
# on BSD and has no way to say otherwise.
#
# The three strings arrive through the environment, not `-v`: awk runs escape
# processing over a `-v` assignment, so a message naming a Windows path would
# reach the author with `\temp` rendered as a tab. A diagnostic prints the value
# it was given.
_diag_wrap() {
  _DIAG_FIRST="$1" _DIAG_REST="$2" _DIAG_TEXT="$3" \
    LC_ALL=C awk -v width="${_DIAG_WIDTH}" '
    function columns(s,   stripped) {
      stripped = s
      gsub(/[\200-\277]/, "", stripped)
      return length(stripped)
    }
    BEGIN {
      first = ENVIRON["_DIAG_FIRST"]
      rest = ENVIRON["_DIAG_REST"]
      prefix = first
      # [[:space:]], not a hand-listed three: %S+ on the Lua side treats a
      # carriage return, a vertical tab and a form feed as whitespace too, and a
      # separator the two renderers disagree on is a line they break apart.
      count = split(ENVIRON["_DIAG_TEXT"], word, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        if (word[i] == "") continue
        if (line == "") {
          line = prefix word[i]
          filled = columns(prefix) + columns(word[i])
        } else if (filled + 1 + columns(word[i]) <= width) {
          line = line " " word[i]
          filled += 1 + columns(word[i])
        } else {
          print line
          prefix = rest
          line = prefix word[i]
          filled = columns(prefix) + columns(word[i])
        }
      }
      if (line != "") print line
    }
  '
}

# cspell:ignore sprintf
#
# _diag_printable — the assembled diagnostic, with control characters shown
# rather than acted on.
#
# A carriage return in relayed text puts what follows at column zero, over the
# gutter that marks a line as part of this diagnostic; an escape sequence is
# whatever the terminal makes of it. Either forges a line Keystone never wrote,
# so the frame neutralizes them and no caller has to police what it relays.
# Caret notation, because `^M` is what was there.
#
# Matches printable() in filters/lib/errors.lua, which owns the reasoning; the
# shared fixtures hold the two to the same output.
#
# Tab alone survives — it moves along the line and cannot leave it. NUL cannot
# reach here either: a shell string ends at the first.
#
# A newline is already a record boundary by the time this runs, so it is not
# this filter's to catch. That is safe only where the caller guttered its own
# split — `--offenders` and `--verbatim` loop line by line, and `--see` carets
# its newline where the value is taken.
_diag_printable() {
  LC_ALL=C awk '
    BEGIN {
      for (code = 1; code < 32; code++) {
        if (code != 9) caret[sprintf("%c", code)] = sprintf("^%c", code + 64)
      }
      caret[sprintf("%c", 127)] = "^?"
    }
    {
      out = ""
      while (match($0, /[[:cntrl:]]/)) {
        found = substr($0, RSTART, 1)
        out = out substr($0, 1, RSTART - 1) (found in caret ? caret[found] : found)
        $0 = substr($0, RSTART + RLENGTH)
      }
      print out $0
    }
  '
}

# _diag_render <severity> <callout...> — assemble and print one diagnostic.
#
# Reading order: what went wrong, which items did it, what the tool being
# reported for said, why that is a refusal, what followed from it, what would
# have been accepted, what to do, where to read more.
_diag_render() {
  local severity="$1"
  shift

  local problem="" offenders="" verbatim="" because="" effect="" choices="" remedy="" see=""
  local flag value saw_flag=0
  while (($#)); do
    case "$1" in
      --*)
        [[ $# -ge 2 ]] || _diag_bug "$1 needs a value"
        flag="$1"
        value="$2"
        saw_flag=1
        shift 2
        ;;
      *)
        # The bare form is the whole call or nothing: a loose argument beside
        # flags is an array of hints that predates the callouts, and appending it
        # to the problem would reflow a list into one paragraph. Checked on the
        # flags seen so far as well as the count, so the order cannot excuse it.
        [[ $# -eq 1 && ${saw_flag} -eq 0 ]] || _diag_bug "'$1' is not a callout"
        flag="--problem"
        value="$1"
        shift
        ;;
    esac
    # An empty value carries nothing, and appending one would leave a doubled
    # separator behind it. The Lua renderer drops them the same way.
    [[ -n "${value}" ]] || continue

    case "${flag}" in
      --problem) problem="${problem}${problem:+ }${value}" ;;
      --because) because="${because}${because:+ }${value}" ;;
      --effect) effect="${effect}${effect:+ }${value}" ;;
      --remedy) remedy="${remedy}${remedy:+ }${value}" ;;
      --choices) choices="${choices}${choices:+, }${value}" ;;
      # Stripped per value, as the Lua renderer strips per item: a captured
      # tool's output nearly always ends in a newline, and joining two of them
      # would print a bare gutter between the pieces.
      --offenders) offenders="${offenders}${offenders:+$'\n'}${value%$'\n'}" ;;
      --verbatim) verbatim="${verbatim}${verbatim:+$'\n'}${value%$'\n'}" ;;
      # One URL, so a repeat is a caller bug rather than something to join.
      #
      # The newline is caret-ed here rather than below, and it is the only
      # character that has to be: `see` is the one callout printed without a
      # per-line loop, so a newline in it would end the record before
      # _diag_printable ever read it and the text after would reach the author
      # at column zero. Everything else it carries is caught inside the record.
      --see)
        [[ -z "${see}" ]] || _diag_bug "--see takes one URL"
        see="${value//$'\n'/^J}"
        ;;
      *) _diag_bug "'${flag}' is not a callout" ;;
    esac
  done

  # Trimmed, not just non-empty: whitespace renders a bare label with nothing
  # after it, which tells the author less than no diagnostic at all.
  [[ -n "${problem//[[:space:]]/}" ]] || _diag_bug "a diagnostic needs a problem"

  # Assembled whole, then filtered. A pipeline would put every render guard
  # below in a subshell whose status is discarded — SC2312, which this repo
  # enables and takes no suppression for.
  local rendered
  rendered="$(
    _diag_wrap "${severity}: " "${_DIAG_GUTTER}" "${problem}"

    if [[ -n "${offenders}" ]]; then
      local offender
      while IFS= read -r offender; do
        echo "${_DIAG_GUTTER}${offender}"
      done <<< "${offenders}"
    fi

    if [[ -n "${verbatim}" ]]; then
      local relayed
      while IFS= read -r relayed; do
        echo "${_DIAG_GUTTER}${_DIAG_QUOTE_BAR}${relayed}"
      done <<< "${verbatim}"
    fi

    [[ -z "${because}" ]] || _diag_wrap "${_DIAG_GUTTER}" "${_DIAG_GUTTER}" "${because}"
    [[ -z "${effect}" ]] || _diag_wrap "${_DIAG_GUTTER}" "${_DIAG_GUTTER}" "${effect}"
    [[ -z "${choices}" ]] || _diag_wrap \
      "${_DIAG_GUTTER}${_DIAG_CHOICES_LABEL}" "${_DIAG_GUTTER}${_DIAG_CHOICES_HANG}" "${choices}"
    [[ -z "${remedy}" ]] || _diag_wrap "${_DIAG_GUTTER}" "${_DIAG_GUTTER}" "${remedy}"
    [[ -z "${see}" ]] || echo "${_DIAG_GUTTER}See ${see}"
  )"
  _diag_printable <<< "${rendered}" >&2
}

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

# fail <callout...> — print an ERROR diagnostic to stderr and exit 1. When
# called inside a $(…) command substitution the exit ends only that subshell;
# the caller's `set -e` then propagates the failure.
fail() {
  _diag_render ERROR "$@"
  exit 1
}

# warn <callout...> — print a WARN diagnostic to stderr. Under strict mode the
# warning is fatal (routes through fail); otherwise it prints and returns so the
# caller can apply its fallback. Author-facing wording follows
# filters/lib/errors.lua.
warn() {
  _diag_render WARN "$@"
  if warnings_as_errors; then
    fail --problem "warnings-as-errors is enabled" \
      --because "The warning above stops the build." \
      --effect "No new artifact was written." \
      --remedy "Fix the warning above, or unset KEYSTONE_WARNINGS_AS_ERRORS for" \
      --remedy "a lenient build." \
      --see "https://keystone.knight-owl.dev/errors/#strict-mode"
  fi
}
