#!/usr/bin/env bash

# resolve-metadata.sh — Read document metadata once, export normalized values
#
# Single entry point for "document metadata → resolved values". publish.sh
# sources this and calls resolve_metadata once; every downstream consumer reads
# the results instead of re-reading the YAML — Lua filters via the exported
# KEYSTONE_* env vars, the docx/odt reference-doc selector via reference_mask,
# and target/output naming via TARGET. The user file is read once and the active
# target file once per build, so adding a new property costs no extra IO.
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
# Usage: source .pandoc/resolve-metadata.sh
#        resolve_metadata <user_meta> <meta_dir> [<manuscript_dir>] [<csl_dir>]
#   then read the values it sets (see resolve_metadata below); for docx/odt,
#   get the reference-doc variant via reference_mask | mask_to_bits. The
#   manuscript/csl dir arguments default to the container's fixed paths and
#   exist so the citation resolver can be unit-tested off those paths.

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
    echo "WARN: Unknown ${property} value '${control}'" \
      "— expected 'auto' or 'disabled'. Defaulting to auto." >&2
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
      echo "WARN: Unknown header-rule value '${value}'" \
        "— expected 'enabled' or 'disabled'. Defaulting to disabled." >&2
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

# Enforce the bare-filename contract for a citation reference. Authors name
# bibliography and .csl files by name only; the file lives in the manuscript
# directory (or, for csl, is a shipped style) by convention. A value carrying a
# path separator would break that convention and could point outside manuscript/
# (e.g. "../x.bib"), so reject it with a clear error rather than silently
# resolving an unintended path — the resolution prefixes a directory blindly.
#   require_bare_name <value> <field>
require_bare_name() {
  case "$1" in
    */*)
      echo "ERROR: ${2} must be a bare filename, not a path: '$1'" >&2
      echo "  Reference it by name only — citation files live in manuscript/" >&2
      exit 1
      ;;
  esac
}

# Read user + target metadata once and publish normalized values.
#
# Sets in the calling (sourced) shell:
#   TARGET                — selected target (default: book), internal-only
#   KEYSTONE_JUSTIFY      — exported: 1 = justified, 0 = ragged-right
#   KEYSTONE_INDENT       — exported: 1 = indented, 0 = no indent
#   KEYSTONE_HEADER_RULE  — exported: 1 = head rule, 0 = none (PDF only)
#   KEYSTONE_CODE_THEME   — exported: resolved theme name (default: tango)
#   KEYSTONE_BIBLIOGRAPHY — exported: resolved .bib paths (newline-separated;
#                           empty disables citeproc)
#   KEYSTONE_CSL          — exported: resolved .csl path (empty when no
#                           bibliography)
#   KEYSTONE_MARKS        — exported: author-declared running-header mark
#                           names (newline-separated; empty when none)
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

  # One read of the user file → an associative array keyed by metadata key.
  # Each pair below is self-contained (the key plus its default via //), so
  # adding a property is a one-line edit — no positional indices to keep
  # aligned. These keys are all string-valued, so // safely supplies the
  # default; the boolean target-file keys further down need _null_to_empty
  # instead, since // would treat YAML false as falsy. `(...) | .[]` streams
  # each key then its value on its own line; capturing to a var keeps yq
  # under set -e.
  local user_raw
  user_raw=$(yq -r '
    ( ["target",          .["target"]          // "book"],
      ["justify-control", .["justify-control"] // "auto"],
      ["indent-control",  .["indent-control"]  // "auto"],
      ["code-theme",      .["code-theme"]      // "tango"],
      ["header-rule",     .["header-rule"]     // "disabled"]
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
    echo "ERROR: Target metadata file not found: ${TARGET}.yaml" >&2
    echo "  Check 'target' in pandoc.yaml" >&2
    exit 1
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

  # PDF-only header rule — deliberately not part of the reference-doc mask
  # (header rules don't exist in EPUB/DOCX/ODT).
  KEYSTONE_HEADER_RULE=$(resolve_header_rule "${user["header-rule"]}")
  export KEYSTONE_HEADER_RULE

  # Code-theme name (default applied in the read above); publish.sh validates
  # the theme dir exists.
  KEYSTONE_CODE_THEME="${user["code-theme"]}"
  export KEYSTONE_CODE_THEME

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
    require_bare_name "${entry}" "bibliography entry"
    bib_path="${manuscript_dir}/${entry}"
    if [[ ! -f "${bib_path}" ]]; then
      echo "ERROR: bibliography file not found: ${entry}" >&2
      echo "  Place it in the manuscript/ directory and reference it by name in pandoc.yaml" >&2
      exit 1
    fi
    resolved_bibs+="${bib_path}"$'\n'
  done <<< "${bib_raw}"
  KEYSTONE_BIBLIOGRAPHY="${resolved_bibs%$'\n'}"
  export KEYSTONE_BIBLIOGRAPHY

  KEYSTONE_CSL=""
  if [[ -n "${KEYSTONE_BIBLIOGRAPHY}" ]]; then
    [[ -n "${csl_value}" ]] && require_bare_name "${csl_value}" "csl"
    [[ -z "${csl_value}" ]] && csl_value="${default_csl}"
    KEYSTONE_CSL=$(resolve_csl_path "${csl_value}" "${manuscript_dir}" "${csl_dir}")
    if [[ ! -f "${KEYSTONE_CSL}" ]]; then
      echo "ERROR: CSL style not found: ${csl_value}" >&2
      case "${csl_value}" in
        *.csl)
          echo "  Place the .csl file in the manuscript/ directory and reference it by name" >&2
          ;;
        *)
          echo "  Available shipped styles:" >&2
          for shipped in "${csl_dir}"/*.csl; do
            [[ -e "${shipped}" ]] || break
            echo "    - $(basename "${shipped}" .csl)" >&2
          done
          ;;
      esac
      exit 1
    fi
  elif [[ -n "${csl_value}" ]]; then
    echo "WARN: 'csl' is set but 'bibliography' is not — citations are disabled and csl is ignored" >&2
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
