#!/usr/bin/env bash

# progress.sh — Build progress, and the one owner of Pandoc's message stream
#
# A PDF build spends most of its wall time inside XeLaTeX, which prints nothing
# until it finishes. Pandoc reports its own stages — each filter, each LaTeX
# pass — but only under --verbose, which also dumps the generated .tex and the
# whole XeLaTeX log. So Pandoc runs under --verbose and this module reads its
# stderr, keeping the reportable records and dropping the dump.
#
# Owning that stream also puts Pandoc's diagnostics in Keystone's vocabulary:
# its level prefix is swapped for ours — `[WARNING]` to `WARN:`, `[ERROR]` to
# `ERROR:` — so a message carries the same shape whichever world raised it. In
# practice Pandoc logs no `[ERROR]` record at all; it prints failures as bare
# prose, which publish.sh frames with its own ERROR line. diagnostics.sh owns
# the shell's messages and filters/lib/errors.lua owns Lua's; this closes the
# third. Scope stops at the relabel — severity policy, hints, and the strict
# gate stay with diagnostics.sh.
#
# Progress is unlabeled on stdout; Pandoc's own output stays on the stderr it
# was written to, so a caller redirecting one still gets the other.
#
#   progress_pandoc <args...>        run Pandoc, reporting the stages it names
#   progress_phase <label> <cmd...>  run a command as one opaque stage
#   progress_now                     a start stamp for progress_duration
#   progress_duration <start>        elapsed since a stamp, formatted
#
# Environment:
#   KEYSTONE_PROGRESS — off | plain | auto | verbose (default auto)
#
# Usage: source progress.sh

# shellcheck source=src/runtime/.pandoc/diagnostics.sh
source "$(dirname "${BASH_SOURCE[0]}")/diagnostics.sh"

# Stage labels, keyed by filter basename. The words are the author-facing build
# stages from the manual's error map, so a stage named here is the stage named
# there when something goes wrong: https://keystone.knight-owl.dev/errors/
#
# A stage with no entry there takes its wording from here instead; Typesetting
# is the one that always will, being LaTeX rather than Keystone.
#
# Keys are quoted because a hyphen in an unquoted subscript reads as
# subtraction: shfmt rewrites `[math-check]` to `[math - check]`.
declare -gA PROGRESS_STAGES=(
  ["hooks"]="Rendering hooks"
  ["shortcuts"]="Expanding shortcuts"
  ["keystone"]="Resolving configuration"
  ["divs"]="Running handlers"
  ["page-furniture"]="Composing headers & footers"
  ["math-check"]="Converting math"
  ["xmp-metadata"]="Embedding PDF metadata"
  ["citeproc"]="Resolving citations"
)

# A stage quicker than this earns no line of its own on a terminal; it folds
# into the summary below. Output stays proportional to what is actually slow.
PROGRESS_FOLD_SECONDS=1

# Umbrella for the folded stages. Generic because the set varies per build.
PROGRESS_FOLD_LABEL="Preparing your artifact"

# Column the elapsed time starts at, wide enough for the longest label above
# plus a separating space. A label that outgrows it shifts its own duration
# right and breaks the column.
PROGRESS_LABEL_WIDTH=28

# ── Mode ──────────────────────────────────────────────────────────────

# progress_resolve_mode — set PROGRESS_MODE, the sole interpreter of
# KEYSTONE_PROGRESS. `auto` is a selector, not an outcome: it resolves to
# `styled` on a terminal and `plain` everywhere else, so the resolved set is
# off | plain | styled | verbose.
#
#   off      no --verbose and no stage reporting; relabeling still applies
#   plain    every stage keeps a line — a log wants the whole trace
#   styled   fast stages fold, and the running one ticks in place
#   verbose  the raw stream, for forensics; the only mode that bypasses here
#
# Assigns rather than prints: a rejected value has to stop the build, and
# `fail`'s exit inside a $(…) would end only that subshell, leaving the caller
# to carry on with an empty mode.
progress_resolve_mode() {
  local value="${KEYSTONE_PROGRESS:-auto}"
  case "${value,,}" in
    off | plain | verbose) PROGRESS_MODE="${value,,}" ;;
    auto) if [[ -t 1 ]]; then PROGRESS_MODE="styled"; else PROGRESS_MODE="plain"; fi ;;
    *)
      fail --problem "unknown KEYSTONE_PROGRESS value '${value}'" \
        --choices off --choices plain --choices auto --choices verbose
      ;;
  esac
}

# ── Elapsed time ──────────────────────────────────────────────────────

# progress_now — a start stamp to hand progress_duration later.
# EPOCHREALTIME is formatted with the shell's own radix character, so a comma
# locale yields "1756…,12". The substitution normalizes it at the point of
# capture — an LC_ALL prefix on the awk below would be too late, the shell
# having already expanded the value.
progress_now() {
  printf '%s' "${EPOCHREALTIME/,/.}"
}

# Seconds since a stamp, as a float.
_progress_span() {
  local now="${EPOCHREALTIME/,/.}"
  LC_ALL=C awk -v start="$1" -v now="${now}" \
    'BEGIN { printf "%.3f", now - start }'
}

# Render a span for display: tenths under a minute, whole seconds above it.
#   _progress_format <seconds>  →  "0.4s" | "31.2s" | "1m 04s"
_progress_format() {
  LC_ALL=C awk -v s="$1" 'BEGIN {
    if (s < 60) { printf "%.1fs", s }
    else { printf "%dm %02ds", int(s / 60), int(s) % 60 }
  }'
}

# progress_duration <start> — elapsed since a stamp, formatted.
progress_duration() {
  local seconds
  seconds=$(_progress_span "$1")
  _progress_format "${seconds}"
}

# ── Stream rendering ──────────────────────────────────────────────────

# Renderer state, file-scope because the helpers below read and assign it. The
# renderer runs in the caller's shell, so a build that renders twice (the EPUB
# pre-scan, then the main pass) would inherit the first run's state —
# _progress_reset, called on entry, is what keeps the two independent.
_progress_report=1   # report stages at all (0 for off)
_progress_styled=0   # fold fast stages and tick the running one in place
_progress_derive=1   # derive stages from Pandoc's records (0 for a phase)
_progress_scope=pass # where an indented continuation goes: pass | drop
_progress_stage=""   # label of the running stage, empty when none
_progress_start=""   # its start stamp
_progress_fold=0     # summed seconds of the folded stages
_progress_folded=0   # how many folded, so an empty group prints nothing
_progress_live=0     # a tick is currently drawn and needs clearing
_progress_fifo=""    # scratch dir holding the stream FIFO, swept by a trap

_progress_reset() {
  _progress_report=1
  _progress_styled=0
  _progress_derive=1
  _progress_scope=pass
  _progress_stage=""
  _progress_start=""
  _progress_fold=0
  _progress_folded=0
  _progress_live=0
}

# Erase the in-place line so nothing lands on top of it. The next tick redraws.
_progress_clear() {
  if ((_progress_live)); then
    printf '\r\033[K'
    _progress_live=0
  fi
}

# Pandoc's own output, on the stream Pandoc used.
_progress_pass() {
  _progress_clear
  echo "$1" >&2
}

# A settled stage, unlabeled on stdout: ✓ finished, ✗ is where a build died.
# The one owner of the stage line's shape.
#   _progress_settled <marker> <label> <seconds>
_progress_settled() {
  local shown
  shown=$(_progress_format "$3")
  _progress_clear
  printf '  %s %-*s %s\n' "$1" "${PROGRESS_LABEL_WIDTH}" "$2" "${shown}"
}

# Redraw the running stage with its elapsed time. Driven by the read timeout,
# so a silent stretch still shows the clock moving.
_progress_tick() {
  [[ -n "${_progress_stage}" ]] || return 0
  local shown
  shown=$(progress_duration "${_progress_start}")
  printf '\r\033[K  ⋯ %-*s %s' "${PROGRESS_LABEL_WIDTH}" "${_progress_stage}" "${shown}"
  _progress_live=1
}

_progress_fold_flush() {
  ((_progress_folded)) || return 0
  _progress_settled "✓" "${PROGRESS_FOLD_LABEL}" "${_progress_fold}"
  _progress_fold=0
  _progress_folded=0
}

_progress_stage_begin() {
  # off suppresses stage reporting everywhere, phases included. Refusing to open
  # a stage is the whole of it: nothing opened can later settle or tick.
  ((_progress_report)) || return 0
  _progress_stage_end
  _progress_stage="$1"
  _progress_start=$(progress_now)
  ((_progress_styled)) && _progress_tick
  return 0
}

# Close the running stage: fold it when it was quick enough to be noise,
# otherwise flush whatever folded before it and give it a line.
_progress_stage_end() {
  [[ -n "${_progress_stage}" ]] || return 0
  local seconds
  seconds=$(_progress_span "${_progress_start}")

  if ((_progress_styled)) && LC_ALL=C awk -v s="${seconds}" \
    -v limit="${PROGRESS_FOLD_SECONDS}" 'BEGIN { exit !(s < limit) }'; then
    _progress_fold=$(LC_ALL=C awk -v a="${_progress_fold}" -v b="${seconds}" \
      'BEGIN { printf "%.3f", a + b }')
    # Assignment rather than ((n++)), whose value is the pre-increment 0 on the
    # first fold — a zero is a non-zero exit status, which `set -e` would take
    # as a failure and kill the renderer mid-stream.
    _progress_folded=$((_progress_folded + 1))
  else
    _progress_fold_flush
    _progress_settled "✓" "${_progress_stage}" "${seconds}"
  fi

  _progress_stage=""
}

# Map a filter path to its stage label, falling back to the bare stem so a
# filter added without an entry above reads plainly instead of breaking.
_progress_label() {
  local stem
  stem=$(basename "$1" .lua)
  echo "${PROGRESS_STAGES[${stem}]:-${stem}}"
}

# The records worth reporting. Everything else Pandoc logs at INFO is its own
# detail — `Loaded <file> from <path>` alone fires once per resource — and we
# turned --verbose on for our purposes, so silence is the right default. This is
# the only place upstream wording is matched, and a rename costs a stage line
# rather than correctness: _progress_label falls back to the filter's own name.
_progress_info() {
  local msg="$1"
  local label
  case "${msg}" in
    'Running filter '*)
      label=$(_progress_label "${msg#'Running filter '}")
      _progress_stage_begin "${label}"
      ;;
    'Completed filter '*)
      _progress_stage_end
      ;;
    '[makePDF] LaTeX run number '*)
      _progress_stage_begin "Typesetting (pass ${msg##* })"
      ;;
  esac
}

# Classify one line of Pandoc's stream.
#
# A record is a `[LEVEL] …` line; the lines indented beneath it are its
# continuation. The dumps that make --verbose unusable are always INFO
# continuations, so dropping those is structural — no message text is matched to
# recognize the noise.
#
# The flush-left case resets the scope, and that is what protects our own
# output. A Lua error prints flush-left, then tab-indented detail and a
# `stack traceback:` block, all while Pandoc's last record is still an INFO
# `Running filter …`. Without the reset the traceback body would be read as that
# record's continuation and dropped. The LaTeX error tail needs no reset — it is
# flush-left throughout, so the branch below carries it either way.
#
# A blank line keeps the current scope instead of resetting it: it is never a
# new thought, and treating it as flush-left would reopen a suppressed dump.
_progress_line() {
  local line="$1"
  case "${line}" in
    '[INFO] '*)
      _progress_scope=drop
      ((_progress_derive)) && _progress_info "${line#'[INFO] '}"
      ;;
    '[WARNING] '*)
      _progress_scope=pass
      _progress_pass "WARN: ${line#'[WARNING] '}"
      ;;
    '[ERROR] '*)
      _progress_scope=pass
      _progress_pass "ERROR: ${line#'[ERROR] '}"
      ;;
    '')
      [[ "${_progress_scope}" == pass ]] && _progress_pass "${line}"
      ;;
    [[:space:]]*)
      [[ "${_progress_scope}" == pass ]] && _progress_pass "${line}"
      ;;
    *)
      _progress_scope=pass
      _progress_pass "${line}"
      ;;
  esac
  return 0
}

# progress_render <mode> [phase-label] — filter Pandoc's stream on stdin.
#
# With a phase label the whole run is one stage and Pandoc's own records are
# ignored, so a pass that re-runs filters the main build also runs (the EPUB
# pre-scan) reports once instead of naming those stages twice.
progress_render() {
  local mode="$1"
  local phase="${2:-}"

  _progress_reset
  [[ "${mode}" == off ]] && _progress_report=0
  [[ "${mode}" == styled ]] && _progress_styled=1
  if [[ -n "${phase}" ]]; then
    _progress_derive=0
    _progress_stage_begin "${phase}"
  fi

  local line rc held=""
  while true; do
    rc=0
    if ((_progress_styled)); then
      IFS= read -r -t 1 line || rc=$?
    else
      IFS= read -r line || rc=$?
    fi

    # read reports a timeout above 128 and end-of-input at 1. A timeout is the
    # heartbeat: nothing arrived this second, so redraw the clock. Whatever did
    # arrive is held — read hands back the partial line on timeout, and dropping
    # it loses the head of any line that straddles a tick. A lost head is worse
    # than a truncation: `[WARNING] ` going missing reclassifies the remainder,
    # and a remainder starting with whitespace is then swallowed outright.
    if ((rc > 128)); then
      held+="${line}"
      _progress_tick
      continue
    fi

    # rc 0 is a whole line, which may legitimately be empty; anything else is
    # end-of-input, carrying a final line only if it lacked a trailing newline.
    if ((rc == 0)); then
      _progress_line "${held}${line}"
      held=""
    else
      [[ -n "${held}${line}" ]] && _progress_line "${held}${line}"
      break
    fi
  done

}

# progress_finish <exit-status> — settle what the stream left open.
#
# Typesetting passes and phases are never announced as complete, so one stage is
# still open at end-of-input. The stream cannot say whether it finished or died
# in the attempt; the command's exit status can. Hence the split from rendering:
# a failed build marks that stage `✗` rather than reporting it complete.
progress_finish() {
  local status="$1"

  if [[ -n "${_progress_stage}" ]] && ((status != 0)); then
    local seconds
    seconds=$(_progress_span "${_progress_start}")
    _progress_fold_flush
    _progress_settled "✗" "${_progress_stage}" "${seconds}"
    _progress_stage=""
  fi

  _progress_stage_end
  _progress_fold_flush
  _progress_clear
}

# ── Invocation ────────────────────────────────────────────────────────

# Run a command with its stderr rendered, returning the command's own status.
#
# A FIFO rather than a pipeline, for three reasons: `wait` yields the command's
# own status directly, the command's stdout is never redirected at all, and the
# renderer reaching end-of-input means the writer has closed — so there is no
# race between the last rendered line and the caller's next output.
_progress_piped() {
  local phase="$1"
  shift

  local fifo pid rc=0
  # File-scope rather than local so the trap can name it: a trap body expands
  # when it fires, by which point a local of this function is gone — and under
  # `set -u`, naming a gone local aborts the build instead of cleaning up.
  # Trapped at all because an interrupted build never reaches the removal below
  # and would strand a FIFO per Pandoc run.
  _progress_fifo=$(mktemp -d /tmp/keystone-progress.XXXXXX)
  trap 'rm -rf "${_progress_fifo}"' RETURN INT TERM
  fifo="${_progress_fifo}/stream"
  mkfifo "${fifo}"

  "$@" 2> "${fifo}" &
  pid=$!
  progress_render "${PROGRESS_MODE}" "${phase}" < "${fifo}"
  wait "${pid}" || rc=$?
  progress_finish "${rc}"

  return "${rc}"
}

# progress_pandoc <args...> — run Pandoc, reporting the stages it names.
progress_pandoc() {
  progress_resolve_mode

  # off leaves Pandoc at its default verbosity, where it logs no INFO at all —
  # so the stage rules simply never fire, and only the relabel remains.
  local -a opts=()
  [[ "${PROGRESS_MODE}" == off ]] || opts=(--verbose)

  if [[ "${PROGRESS_MODE}" == verbose ]]; then
    pandoc "$@" "${opts[@]}"
    return
  fi
  _progress_piped "" pandoc "$@" "${opts[@]}"
}

# progress_phase <label> <cmd...> — run a command as one opaque stage.
progress_phase() {
  local label="$1"
  shift
  progress_resolve_mode

  if [[ "${PROGRESS_MODE}" == verbose ]]; then
    "$@"
    return
  fi
  _progress_piped "${label}" "$@"
}
