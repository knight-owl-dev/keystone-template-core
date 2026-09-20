---@diagnostic disable: undefined-global
-- math-check.lua — Refuse to ship equations that won't convert
--
-- Validation-only filter (never rewrites the AST). The gap it closes: math that
-- is valid XeLaTeX can use constructs Pandoc's texmath converter doesn't
-- implement (e.g. the optional [pos] arg of \begin{array}). On the texmath-
-- backed writers those leave raw TeX in the output while the build still
-- "succeeds" — silently shipping an e-book full of literal $…$. This filter
-- probes the build (kast.math.unconvertible) and hard-fails it instead, naming
-- every offending equation so the author can fix it.
--
-- No format gate — every format runs the same probe. PDF clears it because the
-- latex writer emits raw TeX, which never fails the probe, not by exemption.
--
-- Reports ALL offenders at once and fails once, departing from the codebase's
-- fail-fast convention on purpose: this is a report to the author, and stopping
-- at the first would force a rebuild (minutes) per equation — the opposite of
-- the fast feedback the guardrail exists to give.
--
-- Environment (set by publish.sh):
--   KEYSTONE_MATH_METHOD — the math method to probe with, matching what the
--                          build renders with

local path = pandoc.path

local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end

-- Install the memoized module loader, then acquire KAST and the format registry.
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)
local kast = ks_require("ast")
local errors = ks_require("errors")
local format_registry = ks_require("format-registry")
local env_io = ks_require("env-io")

-- Canonical format name for the human-facing message ("epub", not "epub3").
local FORMAT_KEY = format_registry.resolve_key(FORMAT)

function Pandoc(doc)
  local opts = { html_math_method = env_io.optional_env("KEYSTONE_MATH_METHOD") }
  local failures = kast.math.unconvertible(doc, FORMAT, opts)
  if #failures == 0 then return doc end

  -- Report every offender in one message, then fail once (see the header note
  -- on the deliberate all-at-once departure from fail-fast).
  -- Pandoc's diagnostics, relayed whole: each names its equation on its first
  -- line and carets the failing token below, so they keep their own breaks and
  -- their own alignment. Nothing of Keystone's goes in front — a number would
  -- shift every caret by its own width, in the one message whose point is where
  -- the caret lands.
  errors.fatal({
    problem = string.format("%d equation(s) cannot be converted for %s output",
      #failures, FORMAT_KEY),
    verbatim = failures,
    because = "These equations are valid LaTeX and typeset in PDF, but they use"
      .. " constructs Pandoc's math converter does not support, so they would"
      .. " leak into the output as raw TeX.",
    remedy = "Simplify each to standard notation, then rebuild.",
    see = "https://keystone.knight-owl.dev/errors/unconvertible-math/",
  })
end
