#!/usr/bin/env bash

# resolve-metadata.sh — Read document metadata, export normalized values as env vars
#
# Single entry point for "document metadata → resolved values". publish.sh
# sources this and calls resolve_metadata once; every downstream consumer reads
# the results instead of re-reading the YAML — Lua filters via the exported
# KEYSTONE_* env vars, the docx/odt reference-doc selector via reference_mask,
# and target/output naming via TARGET. A new scalar property joins the user file's
# batched scalar read at no extra IO; list-valued and toggle keys take their own
# passes, and the target file's backing defaults are read once.
#
# Resolution model: -control properties (justify, indent) read their value from
# user metadata and cascade through the target's backing default when the
# control is auto/absent; plain toggles (header-rule) and pass-through values
# (code-theme) resolve against a fixed default. Citation properties
# (bibliography, csl) are validated here and exported as resolved paths for
# publish.sh to feed Pandoc citeproc — bibliography is list-valued so it gets
# its own read rather than the scalar key/value stream. Shell owns all of it;
# Lua just reads the result.
#
# Before any resolution, reject_locked_overrides fails the build if the author's
# pandoc.yaml sets a Keystone-owned key.
#
# Adding a new property:
#   1. Add the key to src/shared/pandoc.yaml (user-facing, no prefix). Use
#      <prop>-control: auto for the cascade pattern, or a plain key otherwise.
#   2. (cascade props only) Add keystone-<prop>: true/false to each target yaml
#      in .pandoc/metadata/ — the backing default, prefixed to mark the
#      namespace boundary (see docs/targets.md "Naming convention for
#      target-yaml metadata keys").
#   3. Add a `["<key>", .["<key>"] // "<default>"]` pair to the user-file read
#      below (cascade props also add the backing-default key to the target-file
#      read, consumed via _null_to_empty).
#   4. Resolve it and export KEYSTONE_<PROP> from resolve_metadata.
#   5. (cascade props only) Create toggle payload files
#      (bit-N-toggle-{0,1}-<prop>-style-*.xml) and fold the new bit into
#      reference_mask().
#
# File-validated properties (bibliography, csl) follow a different shape and
# skip the recipe above: they reference files rather than cascade. Give each
# its own yq read below — bibliography is list-valued and can't join the
# scalar key/value stream — resolve the value to a path, validate the file
# exists (hard error, like the target file), and export KEYSTONE_<PROP> for
# publish.sh. No target backing default, no toggle payloads, no reference_mask
# bit (citations are passed to Pandoc, not baked into docx/odt reference docs).
#
# List-valued pass-through properties (marks) get their own yq read like
# bibliography but skip resolution entirely — pure extraction, exported
# newline-separated. Validation that needs Lua-domain knowledge (token
# grammar, the placeholder registry) stays in the consuming filter, not
# here (see the marks block below).
#
# Boolean toggles (toc, numbersections) also skip the // recipe: // treats a YAML
# false as empty and would swallow it, and a bare `==` would accept a quoted
# "false". They get their own read that emits, per key, a presence flag plus the
# canonical ==true / ==false facts (assembled by _toggle_facts_program), which
# require_toggle validates — only an unquoted lowercase true/false is accepted.
# To add one, map its key to its KEYSTONE_* variable in the toggle block (the read
# and validation loop over the map) and name that variable in the block's export.
#
# Usage: source .pandoc/resolve-metadata.sh
#        resolve_metadata <user_meta> <meta_dir> [<manuscript_dir>] [<csl_dir>]
#   then read the values it sets (see resolve_metadata below); for docx/odt,
#   get the reference-doc variant via reference_mask | mask_to_bits. The
#   manuscript/csl dir arguments default to the container's fixed paths and
#   exist so the citation resolver can be unit-tested off those paths.

# shellcheck source=src/runtime/.pandoc/diagnostics.sh
source "$(dirname "${BASH_SOURCE[0]}")/diagnostics.sh"

# Map yq's literal "null" output (what `yq -r` prints for an absent key) to an
# empty string; everything else passes through unchanged. Used only to
# normalize the boolean backing-default reads (keystone-justify /
# keystone-indent) before resolve_bit: those are true/false, so the // default
# operator can't supply their fallback (it treats a legitimate `false` as falsy
# and would swallow it). Scope is deliberately narrow — it normalizes only the
# literal "null" token (the absent-key case these internal keys hit), not other
# YAML null spellings like `~`; author-facing keys use // for that instead.
#   _null_to_empty <value>
_null_to_empty() {
  if [[ "$1" == "null" ]]; then echo ""; else echo "$1"; fi
}

# Build the yq program that classifies each toggle key in "$@". For every <key>
# it streams three boolean pairs, which the toggle read maps into `toggle`:
#   <key>-present   the key exists in the document
#   <key>-true      its value is a genuine !!bool equal to true
#   <key>-false     its value is a genuine !!bool equal to false
# The !!bool tag guard matters — a bare `== false` accepts a quoted "false", which
# require_toggle must fault. Assembled in shell (yq has no def, and an inline
# per-key helper would need command subs shellcheck rejects), one block per key so
# adding a toggle is a single edit: the caller's key list.
#   _toggle_facts_program <key>...  →  ( <pairs> ) | .[]
_toggle_facts_program() {
  local key bool sep=''
  printf '('
  for key in "$@"; do
    printf '%s ["%s-present", has("%s")]' "${sep}" "${key}" "${key}"
    sep=','
    for bool in true false; do
      printf ', ["%s-%s", (((.["%s"] | tag) == "!!bool") and (.["%s"] == %s))]' \
        "${key}" "${bool}" "${key}" "${key}" "${bool}"
    done
  done
  printf ' ) | .[]'
}

# Resolve a single -control property to 1 (ON) or 0 (OFF).
#   resolve_bit <control_value> <default_value> <property_name>
resolve_bit() {
  local control="$1"
  local default="$2"
  local property="$3"
  if [[ "${control}" == "disabled" ]]; then
    echo 0
    return
  fi
  if [[ "${control}" != "auto" ]] && [[ -n "${control}" ]]; then
    warn "Unknown ${property} value '${control}' — expected 'auto' or 'disabled', defaulting to auto"
  fi
  if [[ "${default}" == "true" ]]; then echo 1; else echo 0; fi
}

# Resolve the running-header rule toggle to 1 (rule) or 0 (none).
# Blank/absent → 0; an unknown value warns and falls back to 0 rather than
# silently swallowing a typo.
#   resolve_header_rule <value>
resolve_header_rule() {
  local value="$1"
  case "${value}" in
    enabled) echo 1 ;;
    disabled | "") echo 0 ;;
    *)
      warn "Unknown header-rule value '${value}' — expected 'enabled' or 'disabled', defaulting to disabled"
      echo 0
      ;;
  esac
}

# Resolve a CSL style selector to a file path.
#
# CSL (Citation Style Language) files control how citations and the
# bibliography are formatted. Authors select a style two ways:
#   * a bare name (e.g. "chicago-notes-bibliography") picks a style that
#     ships inside the image under <csl_dir>;
#   * a value ending in ".csl" is an author-supplied style file, located in
#     the manuscript directory by the same convention as bibliography files
#     (there is no other place to put it, and the author-facing value stays
#     decoupled from the container mount point).
#
# Pure: computes the path only; the caller checks that it exists.
#   resolve_csl_path <value> <manuscript_dir> <csl_dir>
resolve_csl_path() {
  local value="$1"
  local manuscript_dir="$2"
  local csl_dir="$3"
  case "${value}" in
    *.csl) echo "${manuscript_dir}/${value}" ;;
    *) echo "${csl_dir}/${value}.csl" ;;
  esac
}

# Enforce the bare-name contract for a by-name reference. Several fields name a
# value, not a path — bibliography and .csl files live in manuscript/ (csl may
# also ship as a named style); code-theme names a shipped theme directory. A
# value carrying a path separator breaks that convention and could point outside
# the expected root (e.g. "../x"), so reject it with a clear error rather than
# blindly prefixing a directory onto an unintended path. The hint is
# caller-supplied so each field explains where its value belongs.
#   require_bare_name <value> <field> [<hint>]
require_bare_name() {
  local value="$1" field="$2" hint="${3:-Reference it by name only}"
  # A slash is a path; a lone . or .. is traversal with no slash to match on.
  case "${value}" in
    */* | . | ..)
      fail "${field} must be a bare name, not a path: '${value}'" "${hint}"
      ;;
  esac
}

# Reject a value that isn't a positive integer (>= 1) with a hard error. Call it
# directly (not in $(...)), like require_bare_name, so the failure propagates
# without relying on set -e. The hint is caller-supplied, per field.
#   require_positive_int <value> <field> [<hint>]
require_positive_int() {
  local value="$1" field="$2"
  local hint="${3:-Set ${field} to a whole number of 1 or greater}"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    fail "${field} must be a positive integer, got: '${value}'" "${hint}"
  fi
}

# Require a present toggle to be a canonical YAML boolean. The caller passes the
# two equality facts from the read (== true, == false, each guarded to a real
# !!bool); exactly one holds for an unquoted true/false, and neither holding is a
# hard fault. Rejecting the rest is deliberate: yq and Pandoc read non-canonical
# spellings inconsistently — a quoted "false" is a truthy string to Pandoc, and
# `toc: True` renders as no TOC while `toc: TRUE` renders one — so normalizing
# them would silently diverge across formats. Call directly (not in $(...)), like
# require_positive_int, so the failure propagates. The hint is caller-supplied.
#   require_toggle <is_true> <is_false> <field> [<hint>]
require_toggle() {
  local is_true="$1" is_false="$2" field="$3"
  local hint="${4:-Set ${field} to true or false, or omit it to use the default}"
  if [[ "${is_true}" != "true" && "${is_false}" != "true" ]]; then
    fail "${field} must be true or false" "${hint}"
  fi
}

# Reject a value that isn't a #RRGGBB hex color with a hard error. Hyperlink
# colors take exactly this one notation — the form every OS color picker emits.
# Call directly (not in $(...)), like require_positive_int, so the failure
# propagates. The hint is caller-supplied, per field.
#   require_hex_color <value> <field> [<hint>]
require_hex_color() {
  local value="$1" field="$2"
  local hint="${3:-Use a 6-digit hex color like \"#1A5FB4\" (quote it — # starts a YAML comment)}"
  if [[ ! "${value}" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
    fail "${field} must be a #RRGGBB hex color, got: '${value}'" "${hint}"
  fi
}

# List the locked keys present in the author's key set, one per line. Pure — both
# sides arrive as newline strings — so it is unit-testable without yq. grep runs
# in an `if`; a bare `grep && echo` would trip set -e on a no-match.
#   locked_field_violations <author_keys> <locked_keys>
locked_field_violations() {
  local author_keys="$1" locked_keys="$2"
  local key
  while IFS= read -r key; do
    [[ -z "${key}" ]] && continue
    if grep -qxF -- "${key}" <<< "${author_keys}"; then
      echo "${key}"
    fi
  done <<< "${locked_keys}"
}

# The metadata keys Keystone owns and an author must not set. Keep in sync with
# the target yamls (.pandoc/metadata/): every owned key there is locked here or
# listed in keystone_overridable_fields. A new owned key is not locked until added
# here — until then it is silently author-overridable.
keystone_locked_fields() {
  printf '%s\n' \
    documentclass \
    css \
    header-includes \
    keystone-justify \
    keystone-indent \
    keystone-fontsize-set \
    keystone-required-fields
}

# The owned metadata keys an author MAY override. Add a new one here.
keystone_overridable_fields() {
  printf '%s\n' \
    keystone-note-placement
}

# Reject any author override of a Keystone-owned metadata key with a hard error.
#
# The author pandoc.yaml is Pandoc's last --metadata-file (publish.sh), so an
# owned key set there silently overrides the target: css/header-includes drop the
# core build wiring, documentclass breaks the target contract, and a backing key
# like keystone-required-fields defeats the validation it drives. Presence is the
# fault — a bare key (YAML null) still clobbers.
#   reject_locked_overrides <user_meta>
reject_locked_overrides() {
  local user_meta="$1"
  local locked_keys author_keys violations
  locked_keys=$(keystone_locked_fields)
  # `// {}` guards a pandoc.yaml that parses to null (e.g. every line commented):
  # `keys` of null is a yq error that would crash the build; an empty map has none.
  author_keys=$(yq -r '(. // {}) | keys | .[]' "${user_meta}")
  violations=$(locked_field_violations "${author_keys}" "${locked_keys}")
  [[ -z "${violations}" ]] && return 0

  local -a hints=("These keys are owned by Keystone and wire the build — remove them from pandoc.yaml:")
  local key
  while IFS= read -r key; do
    hints+=("  - ${key}")
  done <<< "${violations}"
  fail "pandoc.yaml overrides Keystone-owned metadata" "${hints[@]}"
}

# Read user + target metadata once and publish normalized values.
#
# Export contract: every value resolved here is exported, unconditionally.
# Whether any consumer reads a given export is beyond this resolver's concern.
#
# Sets in the calling (sourced) shell:
#   TARGET                — selected target (default: book), internal-only
#   KEYSTONE_JUSTIFY      — exported: 1 = justified, 0 = ragged-right
#   KEYSTONE_INDENT       — exported: 1 = indented, 0 = no indent
#   KEYSTONE_HEADER_RULE  — exported: 1 = head rule, 0 = none
#   KEYSTONE_TOC          — exported: 1 = generate table of contents, 0 = none
#   KEYSTONE_NUMBERSECTIONS — exported: 1 = number sections, 0 = none
#   KEYSTONE_COLORLINKS   — exported: 1 = color link text, 0 = boxed links
#   KEYSTONE_CODE_THEME   — exported: resolved theme name (default: tango)
#   KEYSTONE_FONTFAMILY   — exported: raw fontfamily value (empty when unset)
#   KEYSTONE_MONOFONT     — exported: raw monofont value (empty when unset)
#   KEYSTONE_TOC_DEPTH    — exported: TOC depth in heading levels (default: 3)
#   KEYSTONE_SECNUMDEPTH  — exported: deepest numbered heading level (empty when
#                           the author did not set it)
#   KEYSTONE_BIBLIOGRAPHY — exported: resolved .bib paths (newline-separated;
#                           empty disables citeproc)
#   KEYSTONE_CSL          — exported: resolved .csl path (empty when no
#                           bibliography)
#   KEYSTONE_MARKS        — exported: author-declared running-header mark
#                           names (newline-separated; empty when none)
#   KEYSTONE_LINKCOLOR    — exported: validated #RRGGBB link color, empty when
#                           unset. Also URLCOLOR/CITECOLOR/TOCCOLOR.
#
#   resolve_metadata <user_meta> <meta_dir> [<manuscript_dir>] [<csl_dir>]
resolve_metadata() {
  local user_meta="$1"
  local meta_dir="$2"
  # Conventional locations for author-referenced citation files. Authors
  # write a bare filename (bibliography: references.bib); the file lives in
  # the manuscript directory by convention, so the author-facing value stays
  # decoupled from the container mount point — change it here, not in every
  # author's pandoc.yaml, if the layout ever moves. Overridable by argument
  # so the resolver is testable off the container's fixed paths.
  local manuscript_dir="${3:-manuscript}"
  local csl_dir="${4:-.pandoc/csl}"

  # Reject target-owned overrides first — one would poison every value below.
  reject_locked_overrides "${user_meta}"

  # ── User metadata: scalar keys ─────────────────────────────────────
  # One read → an associative array keyed by metadata key, each value defaulted via
  # //. `(...) | .[]` streams key then value; capturing keeps yq under set -e.
  local user_raw
  user_raw=$(yq -r '
    ( ["target",          .["target"]          // "book"],
      ["justify-control", .["justify-control"] // "auto"],
      ["indent-control",  .["indent-control"]  // "auto"],
      ["code-theme",      .["code-theme"]      // "tango"],
      ["fontfamily",      .["fontfamily"]      // ""],
      ["monofont",        .["monofont"]        // ""],
      ["header-rule",     .["header-rule"]     // "disabled"],
      ["toc-depth",       .["toc-depth"]       // "3"],
      ["secnumdepth",     .["secnumdepth"]     // ""],
      ["linkcolor",       .["linkcolor"]       // ""],
      ["urlcolor",        .["urlcolor"]        // ""],
      ["citecolor",       .["citecolor"]       // ""],
      ["toccolor",        .["toccolor"]        // ""]
    ) | .[]' "${user_meta}")
  local -A user=()
  local key value
  while IFS= read -r key && IFS= read -r value; do
    user["${key}"]="${value}"
  done <<< "${user_raw}"

  # Target selection + validation (we read the target file just below).
  # // above defaults null/~/absent to book; :- additionally guards an
  # explicit empty string (// does not treat "" as null).
  # Subscripts are quoted so shfmt doesn't read the hyphen as arithmetic
  # minus (and so associative keys are matched literally).
  TARGET="${user["target"]:-book}"
  local target_meta="${meta_dir}/${TARGET}.yaml"
  if [[ ! -f "${target_meta}" ]]; then
    fail "Target metadata file not found: ${TARGET}.yaml" \
      "Check 'target' in pandoc.yaml"
  fi

  # One read of the target file: backing defaults for the cascade props. These
  # are YAML booleans, so _null_to_empty (not //) normalizes the absent-key
  # "null" to "" and the value passes through for resolve_bit to interpret.
  local justify_default indent_default target_raw target_lines
  target_raw=$(yq -r '.["keystone-justify"], .["keystone-indent"]' "${target_meta}")
  readarray -t target_lines <<< "${target_raw}"
  justify_default=$(_null_to_empty "${target_lines[0]}")
  indent_default=$(_null_to_empty "${target_lines[1]}")

  # Per-property booleans for Lua. The docx/odt reference-doc bitmask is
  # assembled from these by reference_mask() below — which owns the bit
  # layout, so consumers (publish.sh) only ever see an opaque mask.
  KEYSTONE_JUSTIFY=$(resolve_bit "${user["justify-control"]}" "${justify_default}" "justify-control")
  KEYSTONE_INDENT=$(resolve_bit "${user["indent-control"]}" "${indent_default}" "indent-control")
  export KEYSTONE_JUSTIFY KEYSTONE_INDENT

  # Header rule — deliberately not part of the reference-doc mask: it has no
  # EPUB/DOCX/ODT equivalent, so there is no reference-doc variant to encode.
  KEYSTONE_HEADER_RULE=$(resolve_header_rule "${user["header-rule"]}")
  export KEYSTONE_HEADER_RULE

  # ── Boolean toggles ────────────────────────────────────────────────
  # Resolve the on/off toggles. Map each key to its KEYSTONE_* variable, and name
  # that variable in the export below — shellcheck can't see the indirect printf -v
  # assignment. _toggle_facts_program maps each key to the facts require_toggle
  # validates; a canonical false → 0, absent or true → 1.
  local -A toggle_var=(
    [toc]=KEYSTONE_TOC
    [numbersections]=KEYSTONE_NUMBERSECTIONS
    [colorlinks]=KEYSTONE_COLORLINKS
  )

  local toggle_program toggle_raw
  toggle_program=$(_toggle_facts_program "${!toggle_var[@]}")
  toggle_raw=$(yq -r "${toggle_program}" "${user_meta}")

  local -A toggle=()
  while IFS= read -r key && IFS= read -r value; do
    toggle["${key}"]="${value}"
  done <<< "${toggle_raw}"

  local prop var
  for prop in "${!toggle_var[@]}"; do
    [[ "${toggle["${prop}-present"]}" == "true" ]] \
      && require_toggle "${toggle["${prop}-true"]}" "${toggle["${prop}-false"]}" "${prop}"

    var="${toggle_var["${prop}"]}"
    if [[ "${toggle["${prop}-false"]}" == "true" ]]; then
      printf -v "${var}" '%s' 0
    else
      printf -v "${var}" '%s' 1
    fi
  done
  export KEYSTONE_TOC KEYSTONE_NUMBERSECTIONS KEYSTONE_COLORLINKS

  # ── PDF hyperlink colors ────────────────────────────────────────────
  # Validate the four #RRGGBB colors (empty = unset) and export them verbatim;
  # keystone.lua normalizes them into the injected metadata.
  local color
  for color in linkcolor urlcolor citecolor toccolor; do
    [[ -n "${user["${color}"]:-}" ]] && require_hex_color "${user["${color}"]}" "${color}"
  done
  KEYSTONE_LINKCOLOR="${user["linkcolor"]:-}"
  KEYSTONE_URLCOLOR="${user["urlcolor"]:-}"
  KEYSTONE_CITECOLOR="${user["citecolor"]:-}"
  KEYSTONE_TOCCOLOR="${user["toccolor"]:-}"
  export KEYSTONE_LINKCOLOR KEYSTONE_URLCOLOR KEYSTONE_CITECOLOR KEYSTONE_TOCCOLOR

  # Code-theme name (default applied in the read above); publish.sh validates
  # the theme dir exists.
  require_bare_name "${user["code-theme"]}" "code-theme"
  KEYSTONE_CODE_THEME="${user["code-theme"]}"
  export KEYSTONE_CODE_THEME

  # Document body and code fonts — pure pass-through (empty when unset).
  KEYSTONE_FONTFAMILY="${user["fontfamily"]:-}"
  KEYSTONE_MONOFONT="${user["monofont"]:-}"
  export KEYSTONE_FONTFAMILY KEYSTONE_MONOFONT

  # TOC depth (heading levels in the table of contents). The YAML read owns the
  # default; validate the set value and export it. The :- covers toc-depth: ""
  # (which // doesn't), so the validator rejects it cleanly.
  require_positive_int "${user["toc-depth"]:-}" "toc-depth" \
    "Set toc-depth to how many heading levels the contents should list (1 or more)"
  KEYSTONE_TOC_DEPTH="${user["toc-depth"]}"
  export KEYSTONE_TOC_DEPTH

  # Section-numbering depth (deepest heading level that gets a number). Unlike
  # toc-depth it ships no default, so validate only when the author set it and
  # export empty otherwise; keystone.lua interprets empty.
  if [[ -n "${user["secnumdepth"]:-}" ]]; then
    require_positive_int "${user["secnumdepth"]}" "secnumdepth" \
      "Set secnumdepth to how many heading levels should be numbered (1 or more)"
  fi
  KEYSTONE_SECNUMDEPTH="${user["secnumdepth"]:-}"
  export KEYSTONE_SECNUMDEPTH

  # ── Bibliography / citations (Pandoc citeproc) ──────────────────────
  # bibliography is list-valued and csl can be legitimately empty, so both get
  # their own reads here rather than the scalar key/value stream above (a
  # trailing empty value there is swallowed by command substitution, breaking
  # the key/value pairing). Authors reference each bibliography file by bare
  # name; we prefix the manuscript convention dir and validate existence here,
  # the same hard-error contract the target file gets. publish.sh turns the
  # exported values into --citeproc plus a metadata override. csl resolves to
  # a shipped named style or an author .csl file; an absent csl pins a default
  # shipped style so citation output stays reproducible across Pandoc versions.
  local default_csl="chicago-author-date"
  local bib_raw resolved_bibs="" entry bib_path csl_value shipped
  bib_raw=$(yq -r '[.bibliography] | flatten | map(select(. != null)) | .[]' "${user_meta}")
  csl_value=$(yq -r '.csl // ""' "${user_meta}")
  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    require_bare_name "${entry}" "bibliography entry" "Reference it by name — the file lives in manuscript/"
    bib_path="${manuscript_dir}/${entry}"
    if [[ ! -f "${bib_path}" ]]; then
      fail "bibliography file not found: ${entry}" \
        "Place it in the manuscript/ directory and reference it by name in pandoc.yaml"
    fi
    resolved_bibs+="${bib_path}"$'\n'
  done <<< "${bib_raw}"
  KEYSTONE_BIBLIOGRAPHY="${resolved_bibs%$'\n'}"
  export KEYSTONE_BIBLIOGRAPHY

  KEYSTONE_CSL=""
  if [[ -n "${KEYSTONE_BIBLIOGRAPHY}" ]]; then
    [[ -n "${csl_value}" ]] && require_bare_name "${csl_value}" "csl" "Reference a shipped style name, or a .csl in manuscript/"
    [[ -z "${csl_value}" ]] && csl_value="${default_csl}"
    KEYSTONE_CSL=$(resolve_csl_path "${csl_value}" "${manuscript_dir}" "${csl_dir}")
    if [[ ! -f "${KEYSTONE_CSL}" ]]; then
      local -a hints=()
      case "${csl_value}" in
        *.csl)
          hints=("Place the .csl file in the manuscript/ directory and reference it by name")
          ;;
        *)
          hints=("Available shipped styles:")
          for shipped in "${csl_dir}"/*.csl; do
            [[ -e "${shipped}" ]] || break
            hints+=("  - $(basename "${shipped}" .csl)")
          done
          ;;
      esac
      fail "CSL style not found: ${csl_value}" "${hints[@]}"
    fi
  elif [[ -n "${csl_value}" ]]; then
    warn "'csl' is set but 'bibliography' is not — citations are disabled and csl is ignored"
  fi
  export KEYSTONE_CSL

  # ── Running-header marks (PDF) ──────────────────────────────────────
  # Author-declared mark channels (marks:) for the .set handler and {name}
  # placeholders. Own read (list-valued); pure extraction — the Lua filters
  # own validation (see marks.lua).
  local marks_raw resolved_marks="" mark
  marks_raw=$(yq -r '[.marks] | flatten | map(select(. != null)) | .[]' "${user_meta}")
  while IFS= read -r mark; do
    [[ -z "${mark}" ]] && continue
    resolved_marks+="${mark}"$'\n'
  done <<< "${marks_raw}"
  KEYSTONE_MARKS="${resolved_marks%$'\n'}"
  export KEYSTONE_MARKS
}

# Assemble the docx/odt reference-doc variant bitmask from the resolved
# per-property booleans. Each variant bit gets its own labeled block; to add a
# new variant, resolve its KEYSTONE_<prop> in resolve_metadata and append a
# block here with the next bit value. Owning the layout in one place keeps
# consumers (publish.sh) opaque to bit positions. Reads what resolve_metadata
# exported, so call it after.
#   reference_mask  →  e.g. 3 (justify + indent)
reference_mask() {
  local mask=0
  # bit 0: justify
  if [[ "${KEYSTONE_JUSTIFY}" -eq 1 ]]; then mask=$((mask | 1)); fi
  # bit 1: indent
  if [[ "${KEYSTONE_INDENT}" -eq 1 ]]; then mask=$((mask | 2)); fi
  echo "${mask}"
}

# Format a mask integer as an 8-digit binary string.
# NOTE: Duplicated as basestyle_mask_to_bits() in
# scripts/lib/basestyle.sh (host-side).
# Cannot share code across host/container boundary. Keep both in sync.
#
#   mask_to_bits 1   → 00000001
#   mask_to_bits 3   → 00000011
mask_to_bits() {
  local val="$1"
  local bits=""
  local divisor=128
  local i
  for ((i = 0; i < 8; i++)); do
    bits+=$((val / divisor))
    val=$((val % divisor))
    divisor=$((divisor / 2))
  done
  echo "${bits}"
}
