#!/usr/bin/env bash

# resolve-symbols.sh — Resolve the selected build configuration into a symbol set
#
# Conditional inclusion (ifdef/ifndef) gates content on build symbols. Symbols
# are build configuration, NOT document metadata, so they live in the env layer
# (project.conf), never in pandoc.yaml. project.conf declares named
# configurations as KEYSTONE_DEFINE_<name>="sym1 sym2 ..."; a build selects one
# with `make publish using=<name>` (forwarded as KEYSTONE_USING).
#
# This module turns the selector into the flat, whitespace-separated set the Lua
# handlers read via KEYSTONE_DEFINED_SYMBOLS. The set is always non-empty: the
# build's format symbol (latex/epub/docx/odt) is added automatically, which is
# also why those four names are reserved — a configuration may not set them.
#
# Resolution model: KEYSTONE_USING names a configuration → indirect-expand
# KEYSTONE_DEFINE_<name> (a hard error if undeclared — the configuration is the
# validated unit). Individual symbols stay free-form: an undefined symbol is
# simply false at gate time (C #ifdef semantics), so there is no per-symbol
# vocabulary to validate here.
#
# Usage: source .pandoc/resolve-symbols.sh
#        resolve_symbols <format>
#   Reads KEYSTONE_USING and the KEYSTONE_DEFINE_<name> configurations from the
#   environment; exports KEYSTONE_DEFINED_SYMBOLS. Traces the active set to
#   stdout when a configuration was selected.

# The format symbols the build owns, keyed by output format. Single source of
# truth for two things that must agree: format_symbol() reads it to define the
# per-build symbol (pdf → latex, etc.), and resolve_symbols treats its VALUES as
# reserved — a configuration may not set them. Add a format here and both the
# mapping and the guard pick it up.
#
# -g forces a global even when this file is sourced from inside a function (as
# BATS setup() does); a bare `declare` there would scope the map locally.
declare -gA FORMAT_SYMBOLS=(
  [pdf]=latex
  [epub]=epub
  [docx]=docx
  [odt]=odt
)

# Map an output format to the symbol the build defines for it. The mapping lets
# content target a format directly (ifdef/ifndef symbol="epub").
#   format_symbol <format>  →  latex | epub | docx | odt
format_symbol() {
  local format="$1"
  if [[ -z "${FORMAT_SYMBOLS[${format}]+x}" ]]; then
    echo "ERROR: resolve_symbols: unsupported format '${format}'" \
      "(expected one of: ${!FORMAT_SYMBOLS[*]})" >&2
    exit 1
  fi
  echo "${FORMAT_SYMBOLS[${format}]}"
}

# Resolve KEYSTONE_USING + the declared configurations into KEYSTONE_DEFINED_SYMBOLS.
#   resolve_symbols <format>
resolve_symbols() {
  local format="$1"
  local using="${KEYSTONE_USING:-}"

  # A selected configuration must be declared. Indirect-expand its value; the
  # +x test distinguishes "declared but empty" (valid) from "never declared"
  # (a typo or missing project.conf entry — fail loudly).
  local raw=""
  if [[ -n "${using}" ]]; then
    # The name becomes a KEYSTONE_DEFINE_<name> variable and an artifact-name
    # suffix, so it must be a plain identifier. Validate up front for a clear
    # error (a hyphenated name can't form the variable, and a path-like name
    # has no business in the filename) instead of a confusing downstream one.
    if [[ ! "${using}" =~ ^[A-Za-z0-9_]+$ ]]; then
      echo "ERROR: Invalid configuration name '${using}'" >&2
      echo "  Use letters, digits, and underscores only" >&2
      exit 1
    fi
    local cfg_var="KEYSTONE_DEFINE_${using}"
    if [[ -z "${!cfg_var+x}" ]]; then
      echo "ERROR: Unknown build configuration '${using}'" >&2
      echo "  Declare KEYSTONE_DEFINE_${using} in project.conf, or omit 'using='" >&2
      exit 1
    fi
    raw="${!cfg_var}"
  fi

  # Reserved names: the build owns the format symbols (the values of
  # FORMAT_SYMBOLS), so a configuration that lists one is a mistake — drop it
  # with a warning rather than let it shadow. A plain space-separated list,
  # padded inline at the membership test below.
  local reserved="${FORMAT_SYMBOLS[*]}"

  # Collect the resolved set order-preserving and de-duplicated. `seen` is a
  # space-padded membership string so substring tests stay exact.
  local -a out=()
  local seen=" "
  local -a config_symbols=()
  read -ra config_symbols <<< "${raw}"

  local sym
  for sym in "${config_symbols[@]}"; do
    if [[ " ${reserved} " == *" ${sym} "* ]]; then
      echo "WARN: Ignoring reserved symbol '${sym}' in configuration '${using}'" \
        "— format symbols (${reserved}) are set automatically." >&2
      continue
    fi
    if [[ "${seen}" != *" ${sym} "* ]]; then
      out+=("${sym}")
      seen+="${sym} "
    fi
  done

  # The format symbol is always present.
  local fmt_sym
  fmt_sym=$(format_symbol "${format}")
  if [[ "${seen}" != *" ${fmt_sym} "* ]]; then
    out+=("${fmt_sym}")
  fi

  KEYSTONE_DEFINED_SYMBOLS="${out[*]}"
  export KEYSTONE_DEFINED_SYMBOLS

  # Surface the active set when the author selected a configuration; plain
  # builds (no configuration → only the format symbol) stay quiet.
  if [[ -n "${using}" ]]; then
    echo "Configuration '${using}' → defined: ${KEYSTONE_DEFINED_SYMBOLS}"
  fi
}
